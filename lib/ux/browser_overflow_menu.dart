// SPDX-License-Identifier: MIT
//
// Copyright 2026 Palmshed. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/material.dart';

class BrowserOverflowMenu extends StatelessWidget {
  const BrowserOverflowMenu({
    super.key,
    required this.controller,
    required this.aiAvailable,
    required this.onOpenChanged,
    required this.onSelection,
    required this.onTriggerHoverChanged,
    required this.onMenuHoverChanged,
    required this.menuOpen,
    this.iconSize = 20,
    this.padding = const EdgeInsets.all(8),
  });

  final MenuController controller;
  final bool aiAvailable;
  final ValueChanged<bool> onOpenChanged;
  final Future<void> Function(String value) onSelection;
  final ValueChanged<bool> onTriggerHoverChanged;
  final ValueChanged<bool> onMenuHoverChanged;
  final bool menuOpen;
  final double iconSize;
  final EdgeInsetsGeometry padding;

  List<Widget> _buildMenuEntries(BuildContext context) {
    final entries = <_OverflowMenuEntry>[
      const _OverflowMenuEntry(
        value: 'add_bookmark',
        icon: Icons.bookmark_add,
        label: 'Add Bookmark',
      ),
      const _OverflowMenuEntry(
        value: 'view_bookmarks',
        icon: Icons.bookmarks,
        label: 'Bookmarks',
      ),
      const _OverflowMenuEntry(
        value: 'history',
        icon: Icons.history,
        label: 'History',
      ),
      if (aiAvailable)
        const _OverflowMenuEntry(
          value: 'ai_chat',
          icon: Icons.smart_toy,
          label: 'AI Chat',
        ),
      const _OverflowMenuEntry(
        value: 'page_font',
        icon: Icons.font_download,
        label: 'Page Font',
      ),
      const _OverflowMenuEntry(
        value: 'settings',
        icon: Icons.settings,
        label: 'Settings',
      ),
      const _OverflowMenuEntry(
        value: 'whats_new',
        icon: Icons.new_releases_outlined,
        label: "What's New",
      ),
      const _OverflowMenuEntry(
        value: 'onion_directory',
        icon: Icons.list,
        label: 'Onion directory',
      ),
      const _OverflowMenuEntry(
        value: 'anonymous_view',
        icon: Icons.visibility,
        label: 'Anonymous view',
      ),
      const _OverflowMenuEntry(
        value: 'network_debug',
        icon: Icons.network_check,
        label: 'Network Debug',
      ),
    ];

    return entries.map((entry) => _MenuItem(entry: entry, onSelection: onSelection)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      controller: controller,
      consumeOutsideTap: true,
      style: MenuStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        minimumSize: const WidgetStatePropertyAll(Size(184, 0)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 6),
        ),
        elevation: const WidgetStatePropertyAll(8),
        shadowColor: WidgetStatePropertyAll(
          Colors.black.withValues(alpha: 0.18),
        ),
      ),
      onClose: () {
        onTriggerHoverChanged(false);
        onMenuHoverChanged(false);
        onOpenChanged(false);
      },
      // Wrap the menu children in a MouseRegion so hover events over the
      // menu surface (not just individual items) are reported. This prevents
      // the menu from being closed when moving the mouse from the trigger to
      // the menu (small gaps between widgets).
      menuChildren: [
        MouseRegion(
          onEnter: (_) => onMenuHoverChanged(true),
          onExit: (_) => onMenuHoverChanged(false),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _buildMenuEntries(context),
          ),
        ),
      ],
      builder: (context, menuController, child) {
        return MouseRegion(
          onEnter: (_) => onTriggerHoverChanged(true),
          onExit: (_) => onTriggerHoverChanged(false),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () {
                if (menuController.isOpen) {
                  menuController.close();
                  onOpenChanged(false);
                  return;
                }
                menuController.open();
                onOpenChanged(true);
              },
              child: Padding(
                padding: padding,
                child: Icon(
                  Icons.more_vert,
                  size: iconSize,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OverflowMenuEntry {
  const _OverflowMenuEntry({
    required this.value,
    required this.icon,
    required this.label,
  });

  final String value;
  final IconData icon;
  final String label;
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.entry,
    required this.onSelection,
  });

  final _OverflowMenuEntry entry;
  final Future<void> Function(String value) onSelection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          unawaited(onSelection(entry.value));
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(entry.icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Text(
                entry.label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
