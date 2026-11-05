#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 Antonin Carlin
#
# One command, the gate before every commit and in CI: scan for leaks, generate the project, guard against shared
# singletons, run the SafiraKit tests, build the app, and check that it is signed and sandboxed.
# Prints OK:/FAILED: lines and stops at the first failure. `step` and the scanners come from AppTooling, fetched at the
# version and checksum pinned in scripts/apptooling.pin.
set -u
set -o pipefail
cd "$(dirname "$0")/.."

tools=$(scripts/tools.sh) || exit 1
. "$tools/lib/gate.sh"
. scripts/isolated.sh
trap gate_clean_log EXIT

app=.build/dd/Build/Products/Debug/Safira.app
updates_opt_in() {
    plist="$app/Contents/Info.plist"
    [ "$(/usr/libexec/PlistBuddy -c 'Print :SUEnableAutomaticChecks' "$plist")" = "false" ] || { echo "SUEnableAutomaticChecks is not explicitly false"; return 1; }
    [ "$(/usr/libexec/PlistBuddy -c 'Print :SUAutomaticallyUpdate' "$plist")" = "false" ] || { echo "SUAutomaticallyUpdate is not false"; return 1; }
    /usr/libexec/PlistBuddy -c 'Print :SUEnableSystemProfiling' "$plist" > /dev/null 2>&1 && { echo "SUEnableSystemProfiling must be absent"; return 1; }
    return 0
}

# The benchmark mode (docs/architecture-v1.md §9.4) is compiled only into the Benchmark configuration: the binary of
# that configuration has it, and the Release binary has neither it nor the folder the Benchmark entitlements open for
# reading. `grep -c` reads everything: `grep -q` would exit early and, under pipefail, fail the `strings` feeding it.
benchmark_only_in_benchmark() {
    products=.build/dd/Build/Products
    mode() { strings -a "$1/Contents/MacOS/Safira" | grep -c BenchmarkRun; }
    [ "$(mode "$products/Benchmark/Safira.app")" -gt 0 ] || { echo "the Benchmark build has no benchmark mode"; return 1; }
    [ "$(mode "$products/Release/Safira.app")" -eq 0 ] || { echo "the Release build contains the benchmark mode"; return 1; }
    [ "$(codesign -d --entitlements - "$products/Release/Safira.app" 2>&1 | grep -c safira-bench)" -eq 0 ] \
        || { echo "the Release build opens the benchmark folder"; return 1; }
    return 0
}

# Safira is a registered browser (docs/architecture-v1.md §5.2): every configuration declares http and https and the HTML
# document types, which is what lets the user pick it as the default browser.
registered_as_browser() {
    for configuration in Debug Benchmark Release; do
        plist=".build/dd/Build/Products/$configuration/Safira.app/Contents/Info.plist"
        schemes=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes:0:CFBundleURLSchemes' "$plist" 2>/dev/null | grep -c -E '^ +(http|https)$')
        [ "$schemes" -eq 2 ] || { echo "$configuration does not declare http and https"; return 1; }
        types=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDocumentTypes:0:LSItemContentTypes' "$plist" 2>/dev/null | grep -c -E '^ +public\.(html|xhtml)$')
        [ "$types" -eq 2 ] || { echo "$configuration does not declare HTML documents"; return 1; }
    done
    return 0
}

allowed=Packages/SafiraKit/Sources/SafiraWeb/ProfileWebContext.swift

signed_and_sandboxed() {
    local app=$1
    codesign --verify --strict "$app" || return 1
    # Captured first: `grep -q` exits early, and under pipefail the codesign it cut off would fail the step.
    signature=$(codesign -dv "$app" 2>&1)
    echo "$signature" | grep -q 'flags=.*runtime' || { echo "hardened runtime missing"; return 1; }
    entitlements=$(codesign -d --entitlements - --xml "$app" 2>/dev/null)
    # The device keys are what camera, microphone and location grants need under the sandbox and hardened runtime
    # (docs/architecture-v1.md §8.2); nothing else is added.
    for key in com.apple.security.app-sandbox com.apple.security.network.client com.apple.security.device.camera \
        com.apple.security.device.audio-input com.apple.security.personal-information.location \
        com.apple.security.files.bookmarks.app-scope com.apple.security.files.downloads.read-write; do
        echo "$entitlements" | grep -q "<key>$key</key><true/>" || { echo "$key missing"; return 1; }
    done
}

terms=${OVERLABING_PRIVATE_TERMS:-$HOME/.config/overlabing/private-terms}

step "leak scan, public patterns (working tree)" scripts/leak-scan-public.sh tree
if [ -r "$terms" ]; then
    step "leak scan, private terms (working tree)" "$tools/bin/leak-scan" tree
else
    echo "SKIPPED: leak scan, private terms (no terms file here; CI has none, a Mac that has it runs this step)"
fi
step "xcodegen generate" xcodegen generate
step "step helper self test (a failing or unset-variable step prints FAILED)" scripts/test-step.sh
step "singleton guard self test (fixtures)" scripts/test-guard-singletons.sh
step "attribution check self test" scripts/test-check-attribution.sh
step "singleton guard (App, Packages)" "$tools/bin/guard-pattern.sh" --patterns scripts/singleton-patterns.txt \
    --allow "$allowed" --message "Shared singletons are allowed only in $allowed" App Packages
# AppSupportKit's own strings follow OVERLABING_TEST_LANGUAGE, as the kit documents: the tests that read them get English.
step "swift test (SafiraKit)" env OVERLABING_TEST_LANGUAGE=en swift test --package-path Packages/SafiraKit
step "xcodebuild Safira (Debug)" \
    xcodebuild -project Safira.xcodeproj -scheme Safira -configuration Debug -derivedDataPath .build/dd build
step "Safira.app signed, hardened runtime, sandboxed" isolated signed_and_sandboxed "$app"
# The build wrote the strings the compiler localizes (scripts/sync-strings.json). No translation may be lost or
# unreachable, and every key needs its English and French: sync-strings only notes a key without them, so that note
# fails here. `"$tools/bin/sync-strings" --config scripts/sync-strings.json .build/dd` merges new keys into the catalogs.
strings_in_sync() {
    report=$("$tools/bin/sync-strings" --check --config scripts/sync-strings.json .build/dd) || { echo "$report"; return 1; }
    echo "$report"
    if echo "$report" | grep -q 'without English'; then
        echo "a string is in no catalog yet: merge it with sync-strings, then add its English and French"
        return 1
    fi
    return 0
}
step "string catalogs in sync with the sources, every key translated" isolated strings_in_sync
step "xcodebuild Safira (Benchmark)" \
    xcodebuild -project Safira.xcodeproj -scheme Safira -configuration Benchmark -derivedDataPath .build/dd build
step "xcodebuild Safira (Release)" \
    xcodebuild -project Safira.xcodeproj -scheme Safira -configuration Release -derivedDataPath .build/dd build
step "Release Safira.app signed, hardened runtime, sandboxed" isolated signed_and_sandboxed .build/dd/Build/Products/Release/Safira.app
step "benchmark mode only in the Benchmark build, absent from Release" isolated benchmark_only_in_benchmark
step "registered for http, https and HTML files in every configuration" isolated registered_as_browser
step "Sparkle opt-in: automatic checks off, no system profiling" isolated updates_opt_in
echo "OK: all checks passed"
