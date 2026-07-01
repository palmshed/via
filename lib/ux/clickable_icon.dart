// SPDX-License-Identifier: MIT
//
// Copyright 2026 Palmshed. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';

class ClickableIcon extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double? size;
  final Color? color;
  final EdgeInsetsGeometry padding;

  const ClickableIcon({
    super.key,
    required this.icon,
    this.onTap,
    this.size,
    this.color,
    this.padding = const EdgeInsets.all(8.0),
  });

  @override
  State<ClickableIcon> createState() => _ClickableIconState();
}

class _ClickableIconState extends State<ClickableIcon> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: widget.padding,
          decoration: BoxDecoration(
            color: _isHovered
                ? scheme.onSurface.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            widget.icon,
            size: widget.size,
            color: widget.color ?? scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
