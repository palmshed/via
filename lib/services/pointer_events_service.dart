// SPDX-License-Identifier: MIT
//
// Copyright 2026 Palmshed. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import 'dart:async';
import '../models/tab_data.dart';
import '../assets/page_scripts.dart';

class PointerEventsService {
  Future<void> setTabPointerEventsEnabled(TabData tab, bool enabled) async {
    final controller = tab.webViewController;
    if (controller == null || tab.isClosed) return;
    final script = enabled
        ? restorePagePointerEventsScript
        : disablePagePointerEventsScript;
    try {
      await controller.runJavaScript(script);
    } catch (_) {
      // Best effort only.
    }
  }

  void syncPagePointerEvents(
    TabData tab, {
    required TabData activeTab,
    required bool urlAutocompleteOpen,
    required bool modalInteractionBlockOpen,
    required bool overflowMenuOpen,
  }) {
    if (tab.isClosed) return;
    final shouldBlock = identical(tab, activeTab) &&
        (urlAutocompleteOpen ||
            modalInteractionBlockOpen ||
            overflowMenuOpen);
    unawaited(setTabPointerEventsEnabled(tab, !shouldBlock));
  }

  void syncPointerEventsForAllTabs(
    List<TabData> tabs, {
    required TabData activeTab,
    required bool urlAutocompleteOpen,
    required bool modalInteractionBlockOpen,
    required bool overflowMenuOpen,
  }) {
    for (final tab in tabs) {
      syncPagePointerEvents(
        tab,
        activeTab: activeTab,
        urlAutocompleteOpen: urlAutocompleteOpen,
        modalInteractionBlockOpen: modalInteractionBlockOpen,
        overflowMenuOpen: overflowMenuOpen,
      );
    }
  }
}
