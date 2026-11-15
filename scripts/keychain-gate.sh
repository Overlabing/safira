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
#
# sh scripts/keychain-gate.sh --load-only [folder] touches no keychain and may run anywhere: it signs the same app
# ad hoc, loads Verrou and the probe into a Profile kept in memory, stores nothing, and expects "RESULT: loaded".
set -u
cd "$(dirname "$0")/.."

fail() { echo "FAILED: $*"; exit 1; }

# sh scripts/keychain-gate.sh --native-check <host manifest> '<message JSON>' [folder] touches no keychain either: the
# sandboxed app, signed ad hoc, starts the host that manifest registers (in Safira's hosts folder, for this run only),
# as the probe
# extension carrying the manifest key of [folder], and prints the host's first answer to the message.
load_only=false
native_manifest=
if [ "${1:-}" = "--load-only" ]; then load_only=true; shift; fi
if [ "${1:-}" = "--native-check" ]; then
    load_only=true
    native_manifest=${2:?usage: --native-check <host manifest> <message JSON> [folder]}
    native_message=${3:?usage: --native-check <host manifest> <message JSON> [folder]}
    shift 3
fi
config=${SAFIRA_RELEASE_CONFIG:-Config/Release.local.xcconfig}
verrou=${1:-/Applications/Verrou.app/Contents/Resources/extension}
name=SafiraKeychainGate
label="$name WebCrypto Master Key"
bundle=com.overlabing.safira.keychaingate.$(date +%s)
work=$(mktemp -d /tmp/safira-keychain-gate.XXXXXX) || fail "no temporary folder"
app="$work/$name.app"

if ! $load_only; then
[ -f "$config" ] || fail "$config is missing (copy Config/Release.local.xcconfig.example and fill in the Team ID)"
team=$(sed -n "s/^[[:space:]]*DEVELOPER_ID_TEAM_ID[[:space:]]*=[[:space:]]*\([^[:space:]/]*\).*/\1/p" "$config" | head -1)
[ -n "$team" ] && [ "$team" != "XXXXXXXXXX" ] || fail "DEVELOPER_ID_TEAM_ID is not set in $config"
identity=$(security find-identity -v -p codesigning | grep "Developer ID Application" | grep "($team)" | awk '{print $2}' | head -1)
[ -n "$identity" ] || fail "no valid Developer ID Application certificate for the configured Team ID"
echo "OK: Developer ID Application certificate found"
fi
[ -f "$verrou/manifest.json" ] || fail "no manifest.json in $verrou (pass Verrou's extension folder)"
echo "OK: Verrou's extension folder found"

if ! $load_only; then
    # A master key left by an earlier run belongs to another signature: start without one.
    security delete-generic-password -l "$label" > /dev/null 2>&1
    security find-generic-password -l "$label" > /dev/null 2>&1 && fail "an old \"$label\" item could not be removed"
    echo "OK: no \"$label\" item before the run"
fi

echo "... building the gate app with SafiraKit (one job, a few minutes)"
swift build --package-path scripts/keychain-gate -j 1 > "$work/build.log" 2>&1 || { tail -30 "$work/build.log"; fail "swift build"; }
bin=$(swift build --package-path scripts/keychain-gate --show-bin-path)
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" || fail "app folder"
cp "$bin/$name" "$app/Contents/MacOS/$name" || fail "copy the executable"
for resources in "$bin"/*.bundle; do cp -R "$resources" "$app/Contents/Resources/" || fail "copy $resources"; done
cp -R "$verrou" "$app/Contents/Resources/verrou" || fail "copy Verrou's extension"
cp -R scripts/keychain-gate/probe "$app/Contents/Resources/probe" || fail "copy the probe extension"
if [ -n "$native_manifest" ]; then
    probe="$app/Contents/Resources/probe"
    host_name=$(plutil -extract name raw -o - "$native_manifest") || fail "no name in $native_manifest"
    key=$(plutil -extract key raw -o - "$verrou/manifest.json") || fail "no key in $verrou/manifest.json"
    plutil -replace key -string "$key" "$probe/manifest.json" && plutil -convert json "$probe/manifest.json" \
        || fail "give the probe the extension's key"
    printf '{"name":"%s","message":%s}' "$host_name" "$native_message" > "$probe/native.json"
    plutil -convert xml1 -o /dev/null "$probe/native.json" || fail "the message is not JSON"
    # Registered where Safira reads hosts, in the real home, for this run only.
    hosts="$HOME/Library/Application Support/Safira/NativeMessagingHosts"
    registered="$hosts/$host_name.json"
    [ -e "$registered" ] && fail "$registered already exists; this check does not replace it"
    support=$(dirname "$hosts")
    [ -d "$support" ] || created_support=true
    [ -d "$hosts" ] || created_hosts=true
    mkdir -p "$hosts" || fail "create $hosts"
    cp "$native_manifest" "$registered" || fail "register the host manifest"
    # Leaves the folders as they were: only what this run created goes.
    trap 'rm -f "$registered"; [ "${created_hosts:-}" = true ] && rmdir "$hosts"; [ "${created_support:-}" = true ] && rmdir "$support"' EXIT
    echo "OK: host manifest $host_name registered for this run in $hosts"
fi
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
if $load_only; then
    signing="ad hoc"
    codesign --force --deep --options runtime --entitlements "$work/gate.entitlements" --sign - "$app" \
        > "$work/sign.log" 2>&1 || { cat "$work/sign.log"; fail "codesign"; }
else
    signing="Developer ID"
    codesign --force --deep --options runtime --timestamp --entitlements "$work/gate.entitlements" --sign "$identity" \
        "$app" > "$work/sign.log" 2>&1 || { cat "$work/sign.log"; fail "codesign"; }
fi
codesign --verify --strict "$app" || fail "the signature does not verify"
codesign -d --entitlements - --xml "$app" 2>/dev/null | grep -q "<key>com.apple.security.app-sandbox</key><true/>" \
    || fail "the gate app is not sandboxed"
echo "OK: $name.app signed $signing, hardened runtime, sandboxed, bundle id $bundle"

run() { # <mode> <expected result>
    # A sandboxed app must start through LaunchServices: run directly from a shell, macOS cannot set up its sandbox
    # and kills it (SIGKILL, "sandbox_extension_issue_file_to_process failed"). -g keeps it in the background.
    : > "$work/$1.log"
    open -W -n -g "$app" --stdout "$work/$1.log" --stderr "$work/$1.log" --args "$1"
    grep -E "^(OK|RESULT):" "$work/$1.log"
    grep -qx "RESULT: $2" "$work/$1.log"
}
if [ -n "$native_manifest" ]; then
    : > "$work/native.log"
    open -W -n -g "$app" --stdout "$work/native.log" --stderr "$work/native.log" --args native
    grep -E "^(OK|RESULT):" "$work/native.log"
    grep -q "^RESULT: native {" "$work/native.log" || fail "the host gave no answer (log: $work/native.log)"
    echo "OK: the sandboxed app started the host and relayed its answer (logs and app in $work)"
    exit 0
fi
if $load_only; then
    run load loaded || fail "the gate app did not load Verrou and the probe (log: $work/load.log)"
    echo "OK: Verrou and the probe loaded in the sandboxed gate app; nothing was stored (logs and app in $work)"
    exit 0
fi
echo "... first launch: store a CryptoKey (if a keychain prompt appears, click Deny)"
run write written || fail "first launch did not store the key (log: $work/write.log)"
echo "OK: first launch stored a non-extractable CryptoKey from the service worker"
security find-generic-password -l "$label" > /dev/null 2>&1 \
    && echo "OK: WebKit created \"$label\"" \
    || echo "NOTE: no \"$label\" item was found after the first launch"
echo "... relaunch: read the key back (if a keychain prompt appears, click Deny)"
run read "read back" || fail "relaunch did not read the key back with no prompt (log: $work/read.log)"
echo "OK: no keychain prompt, key read back after a relaunch"

security delete-generic-password -l "$label" > /dev/null 2>&1
security find-generic-password -l "$label" > /dev/null 2>&1 && fail "\"$label\" could not be deleted; run the ROLLBACK line"
echo "OK: \"$label\" deleted"
echo "OK: keychain gate passed (logs and app in $work)"
