#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 Antonin Carlin
#
# Local release: archive, Developer ID export, signature checks, DMG, notarization, staple, Gatekeeper check, SHA-256.
# Runs on the maintainer's Mac only. The Developer ID Team ID and the notarytool keychain profile name come from the
# git-ignored Config/Release.local.xcconfig (template: Config/Release.local.xcconfig.example); the notarization
# credentials live in the login keychain. Nothing is uploaded or published: the DMG lands in .build/release/.
# Prints OK:/FAILED: lines and stops at the first failure.
#
#   scripts/release.sh               full release
#   scripts/release.sh --no-notarize stop after the signed DMG (file name says "unnotarized"; never distribute it)
set -u
set -o pipefail
cd "$(dirname "$0")/.."

notarize=1
case "${1:-}" in
    "") ;;
    --no-notarize) notarize=0 ;;
    *) echo "FAILED: unknown argument $1 (usage: scripts/release.sh [--no-notarize])"; exit 1 ;;
esac

out=.build/release
config=Config/Release.local.xcconfig
mkdir -p .build
log=".build/release-$$.log"
mount_point=""
cleanup() {
    [ -n "$mount_point" ] && hdiutil detach "$mount_point" -quiet 2>/dev/null
    rm -f "$log"
}
trap cleanup EXIT

step() { # <label> <command...>
    label=$1; shift
    if "$@" > "$log" 2>&1; then
        echo "OK: $label"
    else
        tail -40 "$log"
        echo "FAILED: $label"
        exit 1
    fi
}

fail() { echo "FAILED: $*"; exit 1; }

xcconfig_value() { # <key>
    sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\([^[:space:]/]*\).*/\1/p" "$config" | head -1
}

project_value() { # <key>
    sed -n "s/^[[:space:]]*$1:[[:space:]]*\"\{0,1\}\([^\"[:space:]]*\)\"\{0,1\}.*/\1/p" project.yml | head -1
}

# --- configuration and credentials, before any slow step ---------------------------------------------------------

[ -f "$config" ] || fail "$config is missing: copy $config.example and fill in the Team ID and the notarytool profile name"
team=$(xcconfig_value DEVELOPER_ID_TEAM_ID)
profile=$(xcconfig_value NOTARY_KEYCHAIN_PROFILE)
[ -n "$team" ] && [ "$team" != "XXXXXXXXXX" ] || fail "DEVELOPER_ID_TEAM_ID is not set in $config"
[ -n "$profile" ] || fail "NOTARY_KEYCHAIN_PROFILE is not set in $config"
echo "OK: read $config"

identity=$(security find-identity -v -p codesigning | grep "Developer ID Application" | grep "($team)" | awk '{print $2}' | head -1)
[ -n "$identity" ] || fail "no valid 'Developer ID Application' certificate for the configured Team ID in the login keychain"
echo "OK: Developer ID Application certificate found"

if [ "$notarize" = 1 ]; then
    if ! xcrun notarytool history --keychain-profile "$profile" > "$log" 2>&1; then
        tail -5 "$log"
        fail "notarytool keychain profile '$profile' is missing or rejected: create it once with 'xcrun notarytool store-credentials $profile' (Apple ID, app-specific password, Team ID), or fix NOTARY_KEYCHAIN_PROFILE in $config"
    fi
    echo "OK: notarytool keychain profile '$profile' works"
fi

# --- version ------------------------------------------------------------------------------------------------------

version=$(project_value MARKETING_VERSION)
build=$(project_value CURRENT_PROJECT_VERSION)
echo "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || fail "MARKETING_VERSION '$version' in project.yml is not SemVer (X.Y.Z)"
echo "$build" | grep -Eq '^[0-9]+$' || fail "CURRENT_PROJECT_VERSION '$build' in project.yml is not an integer"
echo "OK: version $version (build $build)"

rm -rf "$out"
mkdir -p "$out"

step "xcodegen generate" xcodegen generate

# Developer ID signing is passed on the command line only: project.yml stays ad hoc and carries no Team ID.
step "xcodebuild archive Safira (Release, arm64)" \
    xcodebuild -project Safira.xcodeproj -scheme Safira -configuration Release -destination 'generic/platform=macOS' \
        -archivePath "$out/Safira.xcarchive" -derivedDataPath "$out/dd" ARCHS=arm64 \
        CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" DEVELOPMENT_TEAM="$team" \
        "OTHER_CODE_SIGN_FLAGS=--options=runtime --timestamp" archive

cat > "$out/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>developer-id</string>
	<key>teamID</key><string>$team</string>
	<key>signingStyle</key><string>manual</string>
	<key>signingCertificate</key><string>Developer ID Application</string>
</dict>
</plist>
EOF
step "xcodebuild -exportArchive (Developer ID)" \
    xcodebuild -exportArchive -archivePath "$out/Safira.xcarchive" -exportPath "$out/export" \
        -exportOptionsPlist "$out/ExportOptions.plist"

app="$out/export/Safira.app"

# --- signature checks ---------------------------------------------------------------------------------------------

plist_value() { /usr/libexec/PlistBuddy -c "Print :$1" "$app/Contents/Info.plist" 2>/dev/null; }

verify_app() {
    codesign --verify --strict --verbose=2 "$app" || return 1
    details=$(codesign -dv --verbose=4 "$app" 2>&1)
    echo "$details" | grep -q 'flags=.*runtime' || { echo "hardened runtime missing"; return 1; }
    echo "$details" | grep -q "TeamIdentifier=$team" || { echo "app is not signed with the configured Team ID"; return 1; }
    echo "$details" | grep -q 'Timestamp=' || { echo "no secure timestamp"; return 1; }
    # Notarization rejects get-task-allow, on the app and on every Sparkle component.
    find "$app" \( -name '*.app' -o -name '*.xpc' -o -name '*.framework' -o -name Autoupdate -o -path "$app" \) -print0 |
        while IFS= read -r -d '' component; do
            if codesign -d --entitlements - --xml "$component" 2>/dev/null | grep -q 'get-task-allow'; then
                echo "get-task-allow present in $component"; return 1
            fi
        done || return 1
    entitlements=$(codesign -d --entitlements - --xml "$app" 2>/dev/null)
    echo "$entitlements" | grep -q "<key>com.apple.security.app-sandbox</key><true/>" || { echo "App Sandbox missing"; return 1; }
    echo "$entitlements" | grep -q 'disable-library-validation' && { echo "library validation is disabled in a release build"; return 1; }
    return 0
}
step "export signed with Developer ID, hardened runtime, secure timestamp, sandboxed, no get-task-allow" verify_app

verify_plist() {
    [ "$(plist_value CFBundleShortVersionString)" = "$version" ] || { echo "CFBundleShortVersionString differs from project.yml"; return 1; }
    [ "$(plist_value CFBundleVersion)" = "$build" ] || { echo "CFBundleVersion differs from project.yml"; return 1; }
    [ "$(plist_value SUEnableAutomaticChecks)" = "false" ] || { echo "SUEnableAutomaticChecks is not false"; return 1; }
    [ "$(plist_value SUAutomaticallyUpdate)" = "false" ] || { echo "SUAutomaticallyUpdate is not false"; return 1; }
    [ "$(plist_value SUEnableInstallerLauncherService)" = "true" ] || { echo "SUEnableInstallerLauncherService is not true"; return 1; }
    [ -z "$(plist_value SUEnableSystemProfiling)" ] || { echo "SUEnableSystemProfiling must be absent"; return 1; }
    [ -n "$(plist_value SUPublicEDKey)" ] || { echo "SUPublicEDKey missing"; return 1; }
    case "$(plist_value SUFeedURL)" in https://*) ;; *) echo "SUFeedURL is not https"; return 1 ;; esac
}
step "archived Info.plist: version matches project.yml, Sparkle opt-in keys" verify_plist

# --- DMG ----------------------------------------------------------------------------------------------------------

if [ "$notarize" = 1 ]; then name="Safira-$version"; else name="Safira-$version-unnotarized"; fi
dmg="$out/$name.dmg"

make_dmg() {
    rm -rf "$out/dmg-root"
    mkdir "$out/dmg-root"
    cp -R "$app" "$out/dmg-root/Safira.app"
    ln -s /Applications "$out/dmg-root/Applications"
    hdiutil create -volname Safira -srcfolder "$out/dmg-root" -fs HFS+ -format UDZO -ov "$dmg" &&
        codesign --sign "$identity" --timestamp "$dmg" &&
        codesign --verify --strict --verbose=2 "$dmg"
}
step "DMG built and signed ($name.dmg)" make_dmg

if [ "$notarize" = 0 ]; then
    echo "OK: stopped before notarization (--no-notarize); $dmg must not be distributed"
    exit 0
fi

# --- notarization -------------------------------------------------------------------------------------------------

notarize_dmg() {
    xcrun notarytool submit "$dmg" --keychain-profile "$profile" --wait --output-format plist > "$out/notarytool.plist" || return 1
    status=$(/usr/libexec/PlistBuddy -c "Print :status" "$out/notarytool.plist")
    if [ "$status" != "Accepted" ]; then
        id=$(/usr/libexec/PlistBuddy -c "Print :id" "$out/notarytool.plist")
        xcrun notarytool log "$id" --keychain-profile "$profile"
        echo "notarization status: $status"
        return 1
    fi
}
step "notarytool submit --wait: Accepted" notarize_dmg
step "stapler staple" xcrun stapler staple "$dmg"
step "stapler validate" xcrun stapler validate "$dmg"

# --- Gatekeeper and checksum --------------------------------------------------------------------------------------

gatekeeper() {
    spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg" || return 1
    mount_point=$(mktemp -d)
    hdiutil attach "$dmg" -mountpoint "$mount_point" -nobrowse -readonly -quiet || return 1
    spctl --assess --type execute --verbose=2 "$mount_point/Safira.app" || return 1
    hdiutil detach "$mount_point" -quiet && mount_point=""
}
step "spctl accepts the DMG and the app inside it" gatekeeper

step "SHA-256" sh -c "cd '$out' && shasum -a 256 '$name.dmg' > '$name.dmg.sha256'"
cat "$out/$name.dmg.sha256"
echo "OK: release $version (build $build) ready in $out, nothing published"
