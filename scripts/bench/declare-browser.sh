#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 Antonin Carlin
#
# Xcode post-build phase. In the Benchmark configuration only, declares the built app as a handler of http and https:
# WebKit gives a full web browser its browser cache model and its process cache (docs/research-tab-discarding.md §1.5),
# which Safira must have for the measurement to compare like with like. Every other configuration is left untouched.
set -eu
[ "${CONFIGURATION:-}" = "Benchmark" ] || exit 0
plist="$TARGET_BUILD_DIR/$INFOPLIST_PATH"
buddy=/usr/libexec/PlistBuddy
"$buddy" -c "Delete :CFBundleURLTypes" "$plist" 2>/dev/null || true
"$buddy" -c "Add :CFBundleURLTypes array" "$plist"
"$buddy" -c "Add :CFBundleURLTypes:0 dict" "$plist"
"$buddy" -c "Add :CFBundleURLTypes:0:CFBundleURLName string Web address" "$plist"
"$buddy" -c "Add :CFBundleURLTypes:0:CFBundleTypeRole string Viewer" "$plist"
"$buddy" -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes array" "$plist"
"$buddy" -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string http" "$plist"
"$buddy" -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:1 string https" "$plist"
