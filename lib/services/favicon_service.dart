import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../assets/page_scripts.dart';
import '../constants.dart';
import '../models/tab_data.dart';
import '../utils/favicon_url_policy.dart';
import '../main.dart' show profileManager;

class FaviconService {
  final Map<String, String> faviconCacheByHost = {};
  final Map<String, bool> faviconHostSafetyCache = {};
  bool tabFaviconBadgeEnabled = false;

  String? hostFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return null;
    return uri.host.toLowerCase();
  }

  String? defaultFaviconUrlFor(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return Uri.https(
      'www.google.com',
      '/s2/favicons',
      <String, String>{
        'domain_url': '${uri.scheme}://${uri.host}',
        'sz': '64',
      },
    ).toString();
  }

  String? hostFaviconIcoUrlFor(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return uri.replace(path: '/favicon.ico', queryParameters: null).toString();
  }

  String? cachedFaviconForUrl(String url) {
    final host = hostFromUrl(url);
    if (host == null || host.isEmpty) return null;
    final cached = faviconCacheByHost[host];
    return (cached == null || cached.isEmpty) ? null : cached;
  }

  Future<bool> isSafeFaviconUrl(String url) async {
    final normalized = url.trim();
    final uri = Uri.tryParse(normalized);
    final host = uri?.host.toLowerCase() ?? '';
    if (host.isNotEmpty) {
      final cached = faviconHostSafetyCache[host];
      if (cached == false) return false;
    }
    final safe = await FaviconUrlPolicy.isSafeFaviconUrlWithDns(normalized);
    if (host.isNotEmpty && !safe) {
      faviconHostSafetyCache[host] = false;
    }
    return safe;
  }

  Future<bool> faviconUrlReturns200(String url) async {
    try {
      final client = HttpClient();
      client.autoUncompress = true;
      final request = await client.headUrl(Uri.parse(url));
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isSafeAndRenderableFaviconUrl(String url) async {
    final normalized = url.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    if (!FaviconUrlPolicy.isLikelyRenderableFaviconUrl(normalized)) {
      return false;
    }
    return isSafeFaviconUrl(normalized);
  }

  Future<void> updateTabFavicon(
    TabData tab, {
    required bool mounted,
    required void Function(VoidCallback fn) setState,
  }) async {
    final controller = tab.webViewController;
    if (controller == null || tab.isClosed) return;
    final sourceUrl = tab.currentUrl;
    final host = hostFromUrl(sourceUrl);
    if (host != null) {
      final cached = faviconCacheByHost[host];
      if (cached != null && cached.isNotEmpty) {
        if (cached != tab.faviconUrl && mounted && !tab.isClosed) {
          setState(() {
            tab.faviconUrl = cached;
          });
        }
        return;
      }
    }

    String? resolvedFavicon;
    try {
      final result = await controller.runJavaScriptReturningResult(
        faviconDetectionScript,
      );
      resolvedFavicon = FaviconUrlPolicy.resolveFaviconFromJsResult(result);
    } catch (_) {
    }
    if (tab.currentUrl != sourceUrl || tab.isClosed) return;
    resolvedFavicon ??= hostFaviconIcoUrlFor(sourceUrl);
    resolvedFavicon ??= defaultFaviconUrlFor(sourceUrl);
    final isResolvedFaviconSafeAndRenderable =
        resolvedFavicon != null && resolvedFavicon.isNotEmpty
            ? await isSafeAndRenderableFaviconUrl(resolvedFavicon)
            : false;
    if (resolvedFavicon != null &&
        resolvedFavicon.isNotEmpty &&
        !isResolvedFaviconSafeAndRenderable) {
      final hostIco = hostFaviconIcoUrlFor(sourceUrl);
      final hostIcoRenderable = hostIco != null && hostIco.isNotEmpty
          ? await isSafeAndRenderableFaviconUrl(hostIco)
          : false;
      resolvedFavicon = hostIcoRenderable
          ? hostIco
          : (tab.faviconUrl ?? defaultFaviconUrlFor(sourceUrl));
    }
    final isResolvedFaviconSafe =
        resolvedFavicon != null && resolvedFavicon.isNotEmpty
            ? await isSafeFaviconUrl(resolvedFavicon)
            : false;
    final faviconReturns200 = resolvedFavicon != null &&
            resolvedFavicon.isNotEmpty &&
            resolvedFavicon.contains('google.com/s2/favicons')
        ? await faviconUrlReturns200(resolvedFavicon)
        : true;
    if (resolvedFavicon != null &&
        resolvedFavicon.isNotEmpty &&
        isResolvedFaviconSafe &&
        faviconReturns200 &&
        host != null &&
        host.isNotEmpty) {
      faviconCacheByHost[host] = resolvedFavicon;
    }
    final useResolvedFavicon = resolvedFavicon != null &&
        resolvedFavicon.isNotEmpty &&
        isResolvedFaviconSafe &&
        faviconReturns200;
    if (resolvedFavicon == null || resolvedFavicon.isEmpty) return;
    if (resolvedFavicon == tab.faviconUrl || !mounted || tab.isClosed) return;
    if (!useResolvedFavicon) return;
    if (tab.currentUrl != sourceUrl) return;
    setState(() {
      tab.faviconUrl = resolvedFavicon;
    });
  }

  Future<void> loadTabFaviconBadgeEnabled({
    required bool mounted,
    required void Function(VoidCallback fn) setState,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final resolved = prefs.getBool(
          profileManager.getScopedStorageKey(tabFaviconBadgeEnabledKey),
        ) ??
        false;
    if (!mounted) return;
    setState(() {
      tabFaviconBadgeEnabled = resolved;
    });
  }

  void reloadSettings(SharedPreferences prefs, String Function(String) scopedKey) {
    tabFaviconBadgeEnabled =
        prefs.getBool(scopedKey(tabFaviconBadgeEnabledKey)) ?? false;
  }
}
