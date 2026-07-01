// SPDX-License-Identifier: MIT
//
// Copyright 2026 Palmshed. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';

import 'clickable_icon.dart';

class BrowserNavigationControls extends StatelessWidget {
  const BrowserNavigationControls({
    super.key,
    required this.toolbarForeground,
    required this.isMobilePlatform,
    required this.onBackTap,
    required this.onForwardTap,
    required this.onRefreshTap,
    required this.onHomeTap,
    this.showHomeButton = false,
  });

  final Color toolbarForeground;
  final bool isMobilePlatform;
  final VoidCallback onBackTap;
  final VoidCallback onForwardTap;
  final VoidCallback onRefreshTap;
  final VoidCallback onHomeTap;
  final bool showHomeButton;

  @override
  Widget build(BuildContext context) {
    final buttonPadding = EdgeInsets.all(isMobilePlatform ? 7 : 8);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClickableIcon(
          icon: Icons.arrow_back_ios,
          size: 16,
          color: toolbarForeground,
          padding: buttonPadding,
          onTap: onBackTap,
        ),
        ClickableIcon(
          icon: Icons.arrow_forward_ios,
          size: 16,
          color: toolbarForeground,
          padding: buttonPadding,
          onTap: onForwardTap,
        ),
        ClickableIcon(
          icon: Icons.refresh,
          size: 18,
          color: toolbarForeground,
          padding: buttonPadding,
          onTap: onRefreshTap,
        ),
        if (showHomeButton)
          ClickableIcon(
            icon: Icons.home_outlined,
            size: 18,
            color: toolbarForeground,
            padding: buttonPadding,
            onTap: onHomeTap,
          ),
      ],
    );
  }
}
