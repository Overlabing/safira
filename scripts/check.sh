#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 Antonin Carlin
#
# One command, the gate before every commit and in CI: generate the project, guard against shared singletons, run the
# SafiraKit tests, build the app, and check that it is signed and sandboxed.
# Prints OK:/FAILED: lines and stops at the first failure.
set -u
set -o pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
log=".build/check-$$.log"
trap 'rm -f "$log"' EXIT

step() { # <label> <command...>
    label=$1; shift
    if "$@" > "$log" 2>&1; then
        echo "OK: $label"
    else
        tail -40 "$log"
        grep -E "recorded an issue|error:" "$log" | head -20
        echo "FAILED: $label"
        exit 1
    fi
}

app=.build/dd/Build/Products/Debug/Safira.app
allowed=Packages/SafiraKit/Sources/SafiraWeb/ProfileWebContext.swift

signed_and_sandboxed() {
    codesign --verify --strict "$app" || return 1
    # Captured first: `grep -q` exits early, and under pipefail the codesign it cut off would fail the step.
    signature=$(codesign -dv "$app" 2>&1)
    echo "$signature" | grep -q 'flags=.*runtime' || { echo "hardened runtime missing"; return 1; }
    entitlements=$(codesign -d --entitlements - --xml "$app" 2>/dev/null)
    for key in com.apple.security.app-sandbox com.apple.security.network.client; do
        echo "$entitlements" | grep -q "<key>$key</key><true/>" || { echo "$key missing"; return 1; }
    done
}

step "xcodegen generate" xcodegen generate
step "singleton guard self test (fixtures)" scripts/test-guard-singletons.sh
step "singleton guard (App, Packages)" scripts/guard-singletons.sh "$allowed" App Packages
step "swift test (SafiraKit)" swift test --package-path Packages/SafiraKit
step "xcodebuild Safira (Debug)" \
    xcodebuild -project Safira.xcodeproj -scheme Safira -configuration Debug -derivedDataPath .build/dd build
step "Safira.app signed, hardened runtime, sandboxed" signed_and_sandboxed
echo "OK: all checks passed"
