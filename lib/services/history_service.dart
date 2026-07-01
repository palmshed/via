import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';
import '../logging/logger.dart' show logger;
import '../main.dart' show profileManager;
import '../models/tab_data.dart';

class HistoryService {
  static const int maxHistoryEntries = 200;
  static const int maxTabHistoryEntries = 50;
  static const int maxNavigationCacheEntries = 200;
  static const int navigationCachePrewarmCount = 8;
  static const Duration navigationCachePrewarmTimeout = Duration(seconds: 3);

  final List<String> history = [];
  final Map<String, int> navigationCacheIndex = {};
  Future<void> _saveQueue = Future<void>.value();

  bool isValidHistoryUrl(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.scheme != 'http' &&
          uri.scheme != 'https' &&
          uri.scheme != 'about') {
        return false;
      }
      if (url.contains('file://') || url.contains('javascript:')) {
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  String normalizeKey(String value) => value.trim().toLowerCase();

  Future<void> loadHistory({
    required bool privateBrowsing,
    required bool advancedCacheEnabled,
    required String Function(String) getUserAgent,
  }) async {
    if (privateBrowsing) return;
    final historyKey = profileManager.historyKey;
    final prefs = await SharedPreferences.getInstance();
    if (profileManager.historyKey != historyKey) return;
    final historyJson = prefs.getString(historyKey);
    if (historyJson == null || historyJson.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(historyJson);
      if (decoded is! List) return;
      history
        ..clear()
        ..addAll(decoded.whereType<String>());
      if (history.length > maxHistoryEntries) {
        history.removeRange(0, history.length - maxHistoryEntries);
      }
    } catch (e, s) {
      logger.w('Failed to load browsing history', error: e, stackTrace: s);
    }
    if (advancedCacheEnabled) {
      await prewarmNavigationCache(getUserAgent: getUserAgent);
    }
  }

  Future<void> saveHistory({
    required bool privateBrowsing,
  }) async {
    if (privateBrowsing) return;
    final historyKey = profileManager.historyKey;
    final data = jsonEncode(List<String>.from(history));
    _saveQueue = _saveQueue.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (profileManager.historyKey != historyKey) return;
        await prefs.setString(historyKey, data);
      } catch (e, s) {
        logger.w('Failed to save browsing history', error: e, stackTrace: s);
      }
    });
    return _saveQueue;
  }

  void recordHistory(
    TabData tab,
    String url, {
    required bool privateBrowsing,
    required bool advancedCacheEnabled,
    required String Function(String) getUserAgent,
  }) {
    if (privateBrowsing || url.isEmpty) return;

    if (tab.history.isEmpty || tab.history.last != url) {
      tab.history.add(url);
      if (tab.history.length > maxTabHistoryEntries) {
        tab.history.removeAt(0);
      }
    }

    if (history.isEmpty || history.last != url) {
      history.add(url);
      if (history.length > maxHistoryEntries) {
        history.removeAt(0);
      }
      saveHistory(privateBrowsing: privateBrowsing);
    }

    if (advancedCacheEnabled) {
      recordNavigationCache(url, privateBrowsing: privateBrowsing);
    }
  }

  Future<void> loadNavigationCacheIndex({
    required bool privateBrowsing,
    required bool advancedCacheEnabled,
    required String Function(String) getUserAgent,
  }) async {
    if (privateBrowsing) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(
      profileManager.getScopedStorageKey(navigationCacheIndexKey),
    );
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      navigationCacheIndex
        ..clear()
        ..addEntries(
          decoded.entries.where((entry) => entry.key.trim().isNotEmpty).map(
              (entry) => MapEntry(entry.key, (entry.value as num).toInt())),
        );
      if (advancedCacheEnabled) {
        await prewarmNavigationCache(getUserAgent: getUserAgent);
      }
    } catch (e, s) {
      logger.w('Failed to load navigation cache index',
          error: e, stackTrace: s);
    }
  }

  Future<void> saveNavigationCacheIndex({
    required bool privateBrowsing,
  }) async {
    if (privateBrowsing) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      profileManager.getScopedStorageKey(navigationCacheIndexKey),
      jsonEncode(navigationCacheIndex),
    );
  }

  void recordNavigationCache(String url, {required bool privateBrowsing}) {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) return;
    navigationCacheIndex[url] = DateTime.now().millisecondsSinceEpoch;
    if (navigationCacheIndex.length > maxNavigationCacheEntries) {
      final oldest = navigationCacheIndex.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      final overflow = navigationCacheIndex.length - maxNavigationCacheEntries;
      for (var i = 0; i < overflow; i++) {
        navigationCacheIndex.remove(oldest[i].key);
      }
    }
    saveNavigationCacheIndex(privateBrowsing: privateBrowsing);
  }

  Future<void> prewarmNavigationCache({
    required String Function(String) getUserAgent,
  }) async {
    final recent = navigationCacheIndex.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final targets = recent
        .map((e) => e.key)
        .where((url) {
          final uri = Uri.tryParse(url);
          return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
        })
        .take(navigationCachePrewarmCount)
        .toList();
    for (final url in targets) {
      try {
        final uri = Uri.parse(url);
        await http.head(uri, headers: {
          'User-Agent': getUserAgent(url)
        }).timeout(navigationCachePrewarmTimeout);
      } catch (_) {
      }
    }
  }

  Iterable<String> urlSuggestions(String rawInput) {
    final query = rawInput.trim().toLowerCase();
    if (query.isEmpty) return const <String>[];

    final seen = <String>{};
    final matches = <String>[];
    for (final url in history.reversed) {
      final normalized = url.trim();
      if (normalized.isEmpty) continue;
      final lower = normalized.toLowerCase();
      if (!lower.contains(query)) continue;
      if (!seen.add(lower)) continue;
      matches.add(normalized);
      if (matches.length >= 8) break;
    }

    matches.sort((a, b) {
      final aStarts = a.toLowerCase().startsWith(query);
      final bStarts = b.toLowerCase().startsWith(query);
      if (aStarts != bStarts) return aStarts ? -1 : 1;
      return a.length.compareTo(b.length);
    });
    return matches;
  }

  void removeUrl(String value) {
    final normalized = normalizeKey(value);
    history.removeWhere((entry) => normalizeKey(entry) == normalized);
  }

  void clearAll() {
    history.clear();
    navigationCacheIndex.clear();
  }
}
