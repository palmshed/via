// SPDX-License-Identifier: MIT
//
// Copyright 2026 Palmshed. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import 'dart:async';
import 'package:flutter/material.dart';

import '../assets/page_scripts.dart';
import '../browser_state.dart';
import '../constants.dart';
import '../features/theme_color_parser.dart';
import '../features/theme_utils.dart';
import '../models/tab_data.dart';

class ThemeProbeService {
  Future<void> updateThemeFromTab(
    TabData tab, {
    required AppThemeMode themeMode,
    required bool strictMode,
    required void Function(ThemeMode mode, Color? color)? onPageThemeChanged,
    required bool mounted,
    required void Function(VoidCallback fn) setState,
  }) async {
    if (themeMode != AppThemeMode.adjust) return;
    if (strictMode) {
      onPageThemeChanged?.call(ThemeMode.system, null);
      return;
    }
    final controller = tab.webViewController;
    if (controller == null) return;
    try {
      final previousBrightness = tab.detectedBrightness;
      final previousSeed = tab.detectedSeedColor;
      final result =
          await controller.runJavaScriptReturningResult(themeProbeScript);
      final probe = parseThemeProbe(result);
      final tone = probe == null ? null : resolveThemeProbeDecision(probe);
      if (tone != null) {
        tab.detectedBrightness = tone.brightness;
        tab.detectedSeedColor = tone.seedColor;
        onPageThemeChanged?.call(
          tone.brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
          tone.seedColor,
        );
      } else {
        tab.detectedBrightness = null;
        tab.detectedSeedColor = null;
        onPageThemeChanged?.call(ThemeMode.system, null);
      }
      if (mounted &&
          (previousBrightness != tab.detectedBrightness ||
              previousSeed != tab.detectedSeedColor)) {
        setState(() {});
      }
    } catch (_) {
      tab.detectedBrightness = null;
      tab.detectedSeedColor = null;
      onPageThemeChanged?.call(ThemeMode.system, null);
    }
  }

  Future<void> updateAmbientFromTab(
    TabData tab, {
    required bool ambientToolbarEnabled,
    required bool strictMode,
    required TabData activeTab,
    required bool mounted,
    required void Function(VoidCallback fn) setState,
  }) async {
    if (!ambientToolbarEnabled) return;
    if (strictMode) return;
    if (tab.currentUrl == defaultHomepageUrl || tab.state is BrowserError) {
      if (tab.ambientSeedColor != null) {
        tab.ambientSeedColor = null;
        if (mounted && identical(tab, activeTab)) {
          setState(() {});
        }
      }
      return;
    }
    // Run theme probe only once per page, not repeatedly
    if (tab.lastAmbientProbeAt != null) {
      return;
    }
    tab.lastAmbientProbeAt = DateTime.now();

    final controller = tab.webViewController;
    if (controller == null) return;
    try {
      final previousSeed = tab.ambientSeedColor;
      final result =
          await controller.runJavaScriptReturningResult(themeProbeScript);
      final probe = parseThemeProbe(result);
      final decision = probe == null ? null : resolveThemeProbeDecision(probe);
      tab.ambientSeedColor = decision?.seedColor;
      if (tab.ambientSeedColor == null) {
        tab.lastAmbientProbeAt = null;
      }
      if (mounted &&
          identical(tab, activeTab) &&
          previousSeed != tab.ambientSeedColor) {
        setState(() {});
      }
    } catch (_) {
      tab.lastAmbientProbeAt = null;
    }
  }

  void resetAmbientProbeState(
    List<TabData> tabs, {
    required bool mounted,
    required void Function(VoidCallback fn) setState,
  }) {
    var shouldRebuild = false;
    for (final tab in tabs) {
      if (tab.ambientSeedColor != null || tab.lastAmbientProbeAt != null) {
        shouldRebuild = true;
      }
      tab.ambientSeedColor = null;
      tab.lastAmbientProbeAt = null;
    }
    if (shouldRebuild && mounted) {
      setState(() {});
    }
  }
}
