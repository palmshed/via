// SPDX-License-Identifier: MIT
//
// Copyright 2026 Palmshed. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import '../constants.dart';

class UrlSubmissionDecision {
  const UrlSubmissionDecision({
    required this.normalizedInput,
    required this.shouldLoadUrl,
    required this.shouldShowAiSuggestions,
  });

  final String normalizedInput;
  final bool shouldLoadUrl;
  final bool shouldShowAiSuggestions;
}

UrlSubmissionDecision resolveUrlSubmission({
  required String submittedValue,
  required bool aiSearchSuggestionsEnabled,
}) {
  final normalized = submittedValue.trim();
  if (normalized.isEmpty) {
    return UrlSubmissionDecision(
      normalizedInput: normalized,
      shouldLoadUrl: false,
      shouldShowAiSuggestions: aiSearchSuggestionsEnabled,
    );
  }
  return UrlSubmissionDecision(
    normalizedInput: normalized,
    shouldLoadUrl: true,
    shouldShowAiSuggestions: false,
  );
}

String resolveNavigationEventUrl({
  required String eventUrl,
  required String? controllerUrl,
  String? pendingUrl,
  String? previousUrl,
}) {
  final normalizedEventUrl = eventUrl.trim();
  final normalizedControllerUrl = controllerUrl?.trim();
  final normalizedPendingUrl = pendingUrl?.trim();

  String candidate = '';
  if (normalizedEventUrl.isNotEmpty && normalizedEventUrl != 'about:blank') {
    candidate = normalizedEventUrl;
  } else if (normalizedControllerUrl != null &&
      normalizedControllerUrl.isNotEmpty) {
    candidate = normalizedControllerUrl;
  }

  if (normalizedPendingUrl != null && normalizedPendingUrl.isNotEmpty) {
    if (candidate.isEmpty) {
      return normalizedPendingUrl;
    }
    if (urlsShareSite(candidate, previousUrl)) {
      return normalizedPendingUrl;
    }
  }

  if (candidate.isNotEmpty) {
    return candidate;
  }
  return normalizedPendingUrl ?? normalizedEventUrl;
}

String? siteKeyForUrl(String? rawUrl) {
  if (rawUrl == null) return null;
  final normalized = rawUrl.trim();
  if (normalized.isEmpty) return null;
  final uri = Uri.tryParse(normalized);
  final host = uri?.host.toLowerCase() ?? '';
  if (host.isEmpty) return normalized;
  return host.startsWith('www.') ? host.substring(4) : host;
}

bool urlsShareSite(String? firstUrl, String? secondUrl) {
  final firstKey = siteKeyForUrl(firstUrl);
  final secondKey = siteKeyForUrl(secondUrl);
  if (firstKey == null || secondKey == null) return false;
  return firstKey == secondKey;
}

String? siteFamilyKeyForUrl(String? rawUrl) {
  final siteKey = siteKeyForUrl(rawUrl);
  if (siteKey == null || siteKey.isEmpty) return null;
  if (!siteKey.contains('.')) return siteKey;
  final parts = siteKey.split('.');
  if (parts.length < 2) return siteKey;
  return '${parts[parts.length - 2]}.${parts[parts.length - 1]}';
}

bool shouldReturnHomeOnBack({
  required String currentUrl,
  required String homeUrl,
  required String? homeLaunchedSiteFamily,
}) {
  if (homeUrl.trim() != defaultHomepageUrl) {
    return false;
  }
  final normalizedCurrent = currentUrl.trim();
  if (normalizedCurrent.isEmpty || normalizedCurrent == defaultHomepageUrl) {
    return false;
  }
  if (homeLaunchedSiteFamily == null || homeLaunchedSiteFamily.isEmpty) {
    return false;
  }
  return siteFamilyKeyForUrl(normalizedCurrent) == homeLaunchedSiteFamily;
}
