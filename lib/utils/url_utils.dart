// SPDX-License-Identifier: MIT
//
// Copyright 2026 Palmshed. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

class UrlUtils {
  static String processUrl(String url) {
    if (url.startsWith('file://')) {
      return url;
    }
    if (!url.contains('://')) {
      if (url.contains(' ') ||
          (!url.contains('.') &&
              !url.contains(':') &&
              url.toLowerCase() != 'localhost')) {
        url = 'https://www.google.com/search?q=${Uri.encodeComponent(url)}';
      } else {
        url = 'https://$url';
      }
    }
    return url;
  }

  static bool isValidUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri != null && const {'http', 'https', 'file'}.contains(uri.scheme);
  }
}
