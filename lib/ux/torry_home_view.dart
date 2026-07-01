// SPDX-License-Identifier: MIT
//
// Copyright 2026 Palmshed. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';

import '../models/tab_data.dart';

class TorryHomeView extends StatelessWidget {
  const TorryHomeView({
    super.key,
    required this.tab,
    required this.theme,
    required this.colorScheme,
    required this.useAmbient,
    required this.onSubmitted,
    required this.onTapSearch,
  });

  final TabData tab;
  final ThemeData theme;
  final ColorScheme colorScheme;
  final bool useAmbient;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onTapSearch;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: useAmbient
          ? colorScheme.surface.withValues(alpha: 0.64)
          : colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            const horizontalPadding = 18.0;
            const verticalPadding = 28.0;
            final topBreathingRoom =
                (constraints.maxHeight * 0.12).clamp(48.0, 160.0);

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                topBreathingRoom,
                horizontalPadding,
                verticalPadding,
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(
                          'assets/icons/app_icon.png',
                          width: 52,
                          height: 52,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Icon(
                              Icons.security,
                              size: 52,
                              color: colorScheme.onSurfaceVariant,
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color:
                                colorScheme.outline.withValues(alpha: 0.35),
                          ),
                        ),
                        child: TextField(
                          controller: tab.torrySearchController,
                          focusNode: tab.torrySearchFocusNode,
                          textInputAction: TextInputAction.search,
                          textAlignVertical: TextAlignVertical.center,
                          style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
                          onSubmitted: onSubmitted,
                          decoration: InputDecoration(
                            hintText: 'Search',
                            hintStyle: TextStyle(
                              color: colorScheme.onSurface.withValues(alpha: 0.38),
                            ),
                            isDense: true,
                            border: InputBorder.none,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 12),
                            prefixIcon: Icon(
                              Icons.search,
                              color: colorScheme.onSurface.withValues(alpha: 0.5),
                              size: 18,
                            ),
                            prefixIconConstraints: const BoxConstraints(
                              minHeight: 36,
                              minWidth: 42,
                            ),
                            suffixIcon: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: onTapSearch,
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Icon(
                                    Icons.arrow_forward,
                                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
