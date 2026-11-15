#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 Antonin Carlin
#
# WHY: Verrou keeps its pairing key as a non-extractable CryptoKey in IndexedDB, and WebKit wraps such keys with a
#      "<app> WebCrypto Master Key" it keeps in the login keychain; an ad hoc build was prompted for it (ADR 0006).
#      This shows whether a Developer ID-signed, sandboxed app running Safira's extension host reads the key back
#      after a relaunch with no prompt.
# RISK: one keychain item, "SafiraKeychainGate WebCrypto Master Key", is created in the login keychain, then deleted
#      at the end. If macOS shows a keychain password prompt, click Deny: the run then fails, which is the answer.
# ROLLBACK: security delete-generic-password -l "SafiraKeychainGate WebCrypto Master Key"
#      (the container ~/Library/Containers/com.overlabing.safira.keychaingate.<time> can be moved to the Trash).
#
# Operator-run only, never in CI or by an agent: it signs with the Developer ID certificate and uses the login
# keychain. Usage: sh scripts/keychain-gate.sh [Verrou's extension folder]
# The Team ID is read from Config/Release.local.xcconfig (git-ignored), or the file SAFIRA_RELEASE_CONFIG names.
set -u
cd "$(dirname "$0")/.."

fail() { echo "FAILED: $*"; exit 1; }

config=${SAFIRA_RELEASE_CONFIG:-Config/Release.local.xcconfig}
verrou=${1:-/Applications/Verrou.app/Contents/Resources/extension}
name=SafiraKeychainGate
label="$name WebCrypto Master Key"
bundle=com.overlabing.safira.keychaingate.$(date +%s)
work=$(mktemp -d /tmp/safira-keychain-gate.XXXXXX) || fail "no temporary folder"
app="$work/$name.app"

[ -f "$config" ] || fail "$config is missing (copy Config/Release.local.xcconfig.example and fill in the Team ID)"
team=$(sed -n "s/^[[:space:]]*DEVELOPER_ID_TEAM_ID[[:space:]]*=[[:space:]]*\([^[:space:]/]*\).*/\1/p" "$config" | head -1)
[ -n "$team" ] && [ "$team" != "XXXXXXXXXX" ] || fail "DEVELOPER_ID_TEAM_ID is not set in $config"
identity=$(security find-identity -v -p codesigning | grep "Developer ID Application" | grep "($team)" | awk '{print $2}' | head -1)
[ -n "$identity" ] || fail "no valid Developer ID Application certificate for the configured Team ID"
echo "OK: Developer ID Application certificate found"
[ -f "$verrou/manifest.json" ] || fail "no manifest.json in $verrou (pass Verrou's extension folder)"
echo "OK: Verrou's extension folder found"

# A master key left by an earlier run belongs to another signature: start without one.
security delete-generic-password -l "$label" > /dev/null 2>&1
security find-generic-password -l "$label" > /dev/null 2>&1 && fail "an old \"$label\" item could not be removed"
echo "OK: no \"$label\" item before the run"

echo "... building the gate app with SafiraKit (one job, a few minutes)"
swift build --package-path scripts/keychain-gate -j 1 > "$work/build.log" 2>&1 || { tail -30 "$work/build.log"; fail "swift build"; }
bin=$(swift build --package-path scripts/keychain-gate --show-bin-path)
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" || fail "app folder"
cp "$bin/$name" "$app/Contents/MacOS/$name" || fail "copy the executable"
for resources in "$bin"/*.bundle; do cp -R "$resources" "$app/Contents/Resources/" || fail "copy $resources"; done
cp -R "$verrou" "$app/Contents/Resources/verrou" || fail "copy Verrou's extension"
cp -R scripts/keychain-gate/probe "$app/Contents/Resources/probe" || fail "copy the probe extension"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$bundle</string>
<key>CFBundleName</key><string>$name</string>
<key>CFBundleExecutable</key><string>$name</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>27.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
# Safira's own entitlements, with its bundle id replaced by the throwaway one.
sed "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/$bundle/g" App/macOS/Safira.entitlements > "$work/gate.entitlements" || fail "entitlements"
codesign --force --deep --options runtime --timestamp --entitlements "$work/gate.entitlements" --sign "$identity" "$app" \
    > "$work/sign.log" 2>&1 || { cat "$work/sign.log"; fail "codesign"; }
codesign --verify --strict "$app" || fail "the signature does not verify"
codesign -d --entitlements - --xml "$app" 2>/dev/null | grep -q "<key>com.apple.security.app-sandbox</key><true/>" \
    || fail "the gate app is not sandboxed"
echo "OK: $name.app signed with Developer ID, hardened runtime, sandboxed, bundle id $bundle"

run() { # <mode>
    "$app/Contents/MacOS/$name" "$1" > "$work/$1.log" 2>&1
    status=$?
    grep -E "^(OK|RESULT):" "$work/$1.log"
    return $status
}
echo "... first launch: store a CryptoKey (if a keychain prompt appears, click Deny)"
run write || fail "first launch did not store the key (log: $work/write.log)"
echo "OK: first launch stored a non-extractable CryptoKey from the service worker"
security find-generic-password -l "$label" > /dev/null 2>&1 \
    && echo "OK: WebKit created \"$label\"" \
    || echo "NOTE: no \"$label\" item was found after the first launch"
echo "... relaunch: read the key back (if a keychain prompt appears, click Deny)"
run read || fail "relaunch did not read the key back with no prompt (log: $work/read.log)"
echo "OK: no keychain prompt, key read back after a relaunch"

security delete-generic-password -l "$label" > /dev/null 2>&1
security find-generic-password -l "$label" > /dev/null 2>&1 && fail "\"$label\" could not be deleted; run the ROLLBACK line"
echo "OK: \"$label\" deleted"
echo "OK: keychain gate passed (logs and app in $work)"
