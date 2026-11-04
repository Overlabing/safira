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
updates_opt_in() {
    plist="$app/Contents/Info.plist"
    [ "$(/usr/libexec/PlistBuddy -c 'Print :SUEnableAutomaticChecks' "$plist")" = "false" ] || { echo "SUEnableAutomaticChecks is not explicitly false"; return 1; }
    [ "$(/usr/libexec/PlistBuddy -c 'Print :SUAutomaticallyUpdate' "$plist")" = "false" ] || { echo "SUAutomaticallyUpdate is not false"; return 1; }
    /usr/libexec/PlistBuddy -c 'Print :SUEnableSystemProfiling' "$plist" > /dev/null 2>&1 && { echo "SUEnableSystemProfiling must be absent"; return 1; }
    return 0
}

# The benchmark mode (docs/architecture-v1.md §9.4) is compiled only into the Benchmark configuration: the binary of
# that configuration has it and declares http and https, and the Release binary has neither, nor the folder the
# Benchmark entitlements open for reading. `grep -c` reads everything: `grep -q` would exit early and, under pipefail,
# fail the `strings` feeding it.
benchmark_only_in_benchmark() {
    products=.build/dd/Build/Products
    mode() { strings -a "$1/Contents/MacOS/Safira" | grep -c BenchmarkRun; }
    schemes() { /usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes' "$1/Contents/Info.plist" 2>/dev/null | grep -c -E '^ +(http|https)$'; }
    [ "$(mode "$products/Benchmark/Safira.app")" -gt 0 ] || { echo "the Benchmark build has no benchmark mode"; return 1; }
    [ "$(schemes "$products/Benchmark/Safira.app")" -eq 2 ] || { echo "the Benchmark build does not declare http and https"; return 1; }
    [ "$(mode "$products/Release/Safira.app")" -eq 0 ] || { echo "the Release build contains the benchmark mode"; return 1; }
    [ "$(schemes "$products/Release/Safira.app")" -eq 0 ] || { echo "the Release build declares http or https"; return 1; }
    [ "$(codesign -d --entitlements - "$products/Release/Safira.app" 2>&1 | grep -c safira-bench)" -eq 0 ] \
        || { echo "the Release build opens the benchmark folder"; return 1; }
    return 0
}

allowed=Packages/SafiraKit/Sources/SafiraWeb/ProfileWebContext.swift

signed_and_sandboxed() {
    codesign --verify --strict "$app" || return 1
    # Captured first: `grep -q` exits early, and under pipefail the codesign it cut off would fail the step.
    signature=$(codesign -dv "$app" 2>&1)
    echo "$signature" | grep -q 'flags=.*runtime' || { echo "hardened runtime missing"; return 1; }
    entitlements=$(codesign -d --entitlements - --xml "$app" 2>/dev/null)
    # The device keys are what camera, microphone and location grants need under the sandbox and hardened runtime
    # (docs/architecture-v1.md §8.2); nothing else is added.
    for key in com.apple.security.app-sandbox com.apple.security.network.client com.apple.security.device.camera \
        com.apple.security.device.audio-input com.apple.security.personal-information.location; do
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
step "xcodebuild Safira (Benchmark)" \
    xcodebuild -project Safira.xcodeproj -scheme Safira -configuration Benchmark -derivedDataPath .build/dd build
step "xcodebuild Safira (Release)" \
    xcodebuild -project Safira.xcodeproj -scheme Safira -configuration Release -derivedDataPath .build/dd build
step "benchmark mode only in the Benchmark build, absent from Release" benchmark_only_in_benchmark
step "Sparkle opt-in: automatic checks off, no system profiling" updates_opt_in
echo "OK: all checks passed"
