#!/bin/bash
# SPDX-License-Identifier: MIT
#
# Copyright 2026 Palmshed. All rights reserved.
# Use of this source code is governed by a MIT license that can be
# found in the LICENSE file.

# Local development setup helper.

echo "setting up development environment..."

if ! command -v flutter &> /dev/null; then
    echo "flutter not found. install Flutter 3.44.0: https://docs.flutter.dev/get-started/install"
    exit 1
fi

echo "flutter version: $(flutter --version)"

flutter pub get

flutter test

echo "setup complete. run './scripts/e2e.sh' for e2e tests."
