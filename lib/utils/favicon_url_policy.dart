import 'dart:io';

class FaviconUrlPolicy {
  static String normalizeJsResult(dynamic result) {
    if (result == null) return '';
    if (result is String) return result.trim();
    return result.toString().trim();
  }

  static String unescapeWrappedJson(String raw) {
    var text = raw.trim();
    if (text.length >= 2 &&
        ((text.startsWith('"') && text.endsWith('"')) ||
            (text.startsWith("'") && text.endsWith("'")))) {
      text = text.substring(1, text.length - 1);
    }
    return text
        .replaceAll(r'\"', '"')
        .replaceAll(r"\'", "'")
        .replaceAll(r'\\', '\\');
  }

  static String? resolveFaviconFromJsResult(dynamic result) {
    final raw = normalizeJsResult(result);
    if (raw.isEmpty) return null;
    var normalized = raw;
    final unescaped = unescapeWrappedJson(raw).trim();
    if (unescaped.isNotEmpty) {
      normalized = unescaped;
    }
    normalized = normalized.replaceAll(r'\/', '/').trim();
    final lower = normalized.toLowerCase();
    if (lower == 'null' || lower == 'undefined' || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  static bool isLikelyRenderableFaviconUrl(String url) {
    final normalized = url.trim();
    final normalizedLower = normalized.toLowerCase();
    if (normalizedLower.isEmpty) return false;
    if (normalizedLower.contains('google.com/s2/favicons')) return true;
    if (normalizedLower.startsWith('data:')) return false;
    return normalizedLower.endsWith('.ico') ||
        normalizedLower.endsWith('.png') ||
        normalizedLower.endsWith('.jpg') ||
        normalizedLower.endsWith('.jpeg') ||
        normalizedLower.endsWith('.gif') ||
        normalizedLower.endsWith('.webp');
  }

  static bool isSafeFaviconUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.host.isEmpty) return false;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return false;
    return !_isBlockedFaviconHost(uri.host);
  }

  static Future<bool> isSafeFaviconUrlWithDns(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.host.isEmpty) return false;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return false;
    if (_isBlockedFaviconHost(uri.host)) return false;
    try {
      final addresses = await InternetAddress.lookup(uri.host);
      if (addresses.isEmpty) return false;
      for (final address in addresses) {
        if (_isBlockedAddress(address)) {
          return false;
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static bool isSafeAndRenderableFaviconUrl(String url) {
    final normalized = url.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return isSafeFaviconUrl(normalized) &&
        isLikelyRenderableFaviconUrl(normalized);
  }

  static bool _isBlockedFaviconHost(String host) {
    final normalizedHost = host.trim().toLowerCase();
    if (normalizedHost.isEmpty) return true;
    if (normalizedHost == 'localhost' ||
        normalizedHost.endsWith('.localhost') ||
        normalizedHost.endsWith('.local')) {
      return true;
    }
    final ip = InternetAddress.tryParse(normalizedHost);
    if (ip == null) return false;
    return _isBlockedAddress(ip);
  }

  static bool _isBlockedAddress(InternetAddress ip) {
    if (ip.type == InternetAddressType.IPv4) {
      final b = ip.rawAddress;
      if (b.length != 4) return true;
      if (b[0] == 10) return true;
      if (b[0] == 127) return true;
      if (b[0] == 0) return true;
      if (b[0] == 169 && b[1] == 254) {
        return true;
      }
      if (b[0] == 172 && b[1] >= 16 && b[1] <= 31) return true;
      if (b[0] == 192 && b[1] == 168) return true;
      if (b[0] == 100 && b[1] >= 64 && b[1] <= 127) return true;
      if (b[0] >= 224) return true;
      return false;
    }
    if (ip.type == InternetAddressType.IPv6) {
      final b = ip.rawAddress;
      if (b.length != 16) return true;
      final isUnspecified = b.every((v) => v == 0);
      if (isUnspecified) return true;
      final isLoopback = b.sublist(0, 15).every((v) => v == 0) && b[15] == 1;
      if (isLoopback) return true;
      final isIpv4Mapped = b.sublist(0, 10).every((v) => v == 0) &&
          b[10] == 0xFF &&
          b[11] == 0xFF;
      if (isIpv4Mapped) return true;
      if ((b[0] & 0xFE) == 0xFC) return true;
      if (b[0] == 0xFE && (b[1] & 0xC0) == 0x80) {
        return true;
      }
      if (b[0] == 0xFF) return true;
      return false;
    }
    return true;
  }
}
