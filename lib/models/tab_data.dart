// SPDX-License-Identifier: MIT
//
// Copyright 2026 Palmshed. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../browser_state.dart';
import '../features/password_prompt.dart';

class TabData {
  String currentUrl;
  String? pageTitle;
  final TextEditingController urlController;
  final FocusNode urlFocusNode;
  bool isUrlObscured = false;
  bool hasUserInteractedWithPage = false;
  final TextEditingController torrySearchController;
  final FocusNode torrySearchFocusNode;
  WebViewController? webViewController;
  BrowserState state = const BrowserState.idle();
  final List<String> history = [];
  bool isClosed = false;
  String? lastErrorMessage;
  DateTime? lastErrorAt;
  Brightness? detectedBrightness;
  Color? detectedSeedColor;
  Color? ambientSeedColor;
  DateTime? lastAmbientProbeAt;
  double scrollOffset = 0;
  SavePasswordPromptData? pendingPasswordPrompt;
  String? faviconUrl;
  String? pendingNavigationUrl;
  String? pendingNavigationSourceUrl;
  bool isResolvingPageTitle = false;
  String? forwardUrl;
  String? homeLaunchedSiteFamily;
  bool hideStaleWebViewUntilPageFinish = false;
  bool pageRequestedWindowFullscreen = false;
  bool windowWasFullscreenBeforePageRequest = false;
  bool isMuted = false;
  bool hasMediaPlaying = false;

  TabData(this.currentUrl, {String? displayUrl})
      : urlController = TextEditingController(text: displayUrl ?? currentUrl),
        urlFocusNode = FocusNode(),
        torrySearchController = TextEditingController(),
        torrySearchFocusNode = FocusNode();
}
