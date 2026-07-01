// SPDX-License-Identifier: MIT
//
// Copyright 2026 Palmshed. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

import '../assets/page_scripts.dart';
import '../models/tab_data.dart';
import '../logging/logger.dart';

class FullscreenService {
  bool get isDesktopPlatform =>
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;

  Future<void> toggleFullscreen() async {
    if (!isDesktopPlatform) return;
    final isFullscreen = await windowManager.isFullScreen();
    await windowManager.setFullScreen(!isFullscreen);
  }

  Future<void> exitFullscreenIfNeeded() async {
    if (!isDesktopPlatform) return;
    final isFullscreen = await windowManager.isFullScreen();
    if (isFullscreen) {
      await windowManager.setFullScreen(false);
    }
  }

  Future<void> setPageRequestedWindowFullscreen(
    TabData tab,
    bool enabled,
  ) async {
    if (!isDesktopPlatform) return;
    final isFullscreen = await windowManager.isFullScreen();
    if (enabled) {
      if (tab.pageRequestedWindowFullscreen) {
        return;
      }
      tab.windowWasFullscreenBeforePageRequest = isFullscreen;
      tab.pageRequestedWindowFullscreen = true;
      if (!isFullscreen) {
        await windowManager.setFullScreen(true);
      }
      return;
    }
    final shouldExitFullscreen = tab.pageRequestedWindowFullscreen;
    final shouldRestoreWindowedState =
        !tab.windowWasFullscreenBeforePageRequest;
    tab.pageRequestedWindowFullscreen = false;
    tab.windowWasFullscreenBeforePageRequest = false;
    if (shouldExitFullscreen && shouldRestoreWindowedState && isFullscreen) {
      await windowManager.setFullScreen(false);
    }
  }

  Future<void> handlePageFullscreenMessage(
    TabData tab,
    String message, {
    required TabData activeTab,
    required bool mounted,
  }) async {
    if (!mounted || tab.isClosed) {
      return;
    }
    final normalized = message.trim().toLowerCase();
    if (normalized == 'enter') {
      if (!identical(tab, activeTab)) {
        return;
      }
      await setPageRequestedWindowFullscreen(tab, true);
    } else if (normalized == 'exit') {
      await setPageRequestedWindowFullscreen(tab, false);
    }
  }

  Future<void> exitPageFullscreen(TabData tab) async {
    final controller = tab.webViewController;
    if (controller == null) return;
    try {
      await controller.runJavaScript(exitFullscreenScript);
    } catch (e) {
      logger.w('Failed to exit page fullscreen: $e');
    }
  }

  Future<void> installFullscreenBridge(TabData tab) async {
    final controller = tab.webViewController;
    if (controller == null) return;
    await controller.runJavaScript(installFullscreenBridgeScript);
  }
}
