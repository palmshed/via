// SPDX-License-Identifier: MIT
//
// Copyright 2026 Palmshed. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';

class TorryHomeView extends StatelessWidget {
  const TorryHomeView({
    super.key,
    required this.theme,
    required this.colorScheme,
    required this.useAmbient,
  });

  final ThemeData theme;
  final ColorScheme colorScheme;
  final bool useAmbient;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: useAmbient
          ? colorScheme.surface.withValues(alpha: 0.64)
          : colorScheme.surface,
      child: Center(
        child: ClipRRect(
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
      ),
    );
  }
}
