// SPDX-License-Identifier: MIT
//
// Copyright 2026 Palmshed. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';

import '../models/tab_data.dart';

class BrowserAddressBar extends StatelessWidget {
  const BrowserAddressBar({
    super.key,
    required this.tab,
    required this.toolbarForeground,
    required this.leadingInset,
    required this.aiSearchSuggestionsEnabled,
    required this.useAmbient,
    required this.onSearchTap,
    required this.onRefreshTap,
    required this.onToggleMuteTap,
    required this.onUrlChanged,
    required this.onUrlTap,
    required this.onUrlSubmitted,
    required this.onAddressBarHoverChanged,
    required this.hasMediaPlaying,
    required this.isMuted,
    required this.urlFieldLayerLink,
    required this.urlFieldTargetKey,
    this.refreshTurns,
  });

  final TabData tab;
  final Color toolbarForeground;
  final double leadingInset;
  final bool aiSearchSuggestionsEnabled;
  final bool useAmbient;
  final VoidCallback onSearchTap;
  final VoidCallback onRefreshTap;
  final VoidCallback onToggleMuteTap;
  final ValueChanged<String> onUrlChanged;
  final VoidCallback onUrlTap;
  final ValueChanged<String> onUrlSubmitted;
  final ValueChanged<bool> onAddressBarHoverChanged;
  final bool hasMediaPlaying;
  final bool isMuted;
  final Animation<double>? refreshTurns;
  final LayerLink urlFieldLayerLink;
  final GlobalKey urlFieldTargetKey;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: leadingInset),
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onSearchTap,
            child: Icon(
              Icons.search,
              color: toolbarForeground.withValues(alpha: 0.45),
              size: 16,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: MouseRegion(
            onEnter: (_) => onAddressBarHoverChanged(true),
            onExit: (_) => onAddressBarHoverChanged(false),
            child: Align(
              alignment: Alignment.centerLeft,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SizeTransition(
                      sizeFactor: animation,
                      axis: Axis.horizontal,
                      // ignore: deprecated_member_use
                      axisAlignment: -1.0,
                      child: child,
                    ),
                  );
                },
                child: tab.isUrlObscured
                    ? SizedBox(
                        key: const ValueKey('url_obscured'),
                        height: 34,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: Image.asset(
                                'assets/icons/app_icon.png',
                                width: 20,
                                height: 20,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                      )
                    : KeyedSubtree(
                        key: const ValueKey('url_field'),
                        child: CompositedTransformTarget(
                          link: urlFieldLayerLink,
                          child: Builder(
                            builder: (context) {
                              return Container(
                                key: urlFieldTargetKey,
                                child: TextField(
                                  key: const Key('browser.url_field'),
                                  controller: tab.urlController,
                                  focusNode: tab.urlFocusNode,
                                  onChanged: (value) => onUrlChanged(value),
                                  style: TextStyle(
                                    color: toolbarForeground,
                                    fontSize: 13,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Search',
                                    hintStyle: TextStyle(
                                      color: toolbarForeground.withValues(alpha: 0.38),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w400,
                                    ),
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 6,
                                    ),
                                  ),
                                  onTap: onUrlTap,
                                  onSubmitted: (value) => onUrlSubmitted(value),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(right: leadingInset),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onRefreshTap,
              child: RotationTransition(
                turns: refreshTurns ?? const AlwaysStoppedAnimation(0.0),
                child: Icon(
                  Icons.refresh,
                  color: toolbarForeground,
                  size: 18,
                ),
              ),
            ),
          ),
        ),
        if (hasMediaPlaying)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: onToggleMuteTap,
                child: Icon(
                  isMuted ? Icons.volume_off : Icons.volume_up,
                  color: isMuted
                      ? toolbarForeground.withValues(alpha: 0.5)
                      : toolbarForeground,
                  size: 18,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
