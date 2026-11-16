#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 Antonin Carlin
#
# Vendors DuckDuckGo's autoconsent (MPL-2.0), which rejects cookie consent prompts, at an exact version. Run at release
# time only: Safira itself never fetches rules.
#
#   scripts/update-autoconsent.sh <version> <sha256 of the npm tarball>   fetch, check, vendor, rewrite the pin
#   scripts/update-autoconsent.sh verify                                    check the vendored files against the pin
#
# The sha256 is the one of https://registry.npmjs.org/@duckduckgo/autoconsent/-/autoconsent-<version>.tgz.
# AUTOCONSENT_ARCHIVE=<file> uses this tarball instead of downloading it (the checksum still has to match).
set -u
here=$(cd "$(dirname "$0")" && pwd)
repository=$(cd "$here/.." && pwd)
pin=$here/autoconsent.pin
vendor=$repository/Packages/SafiraKit/Sources/SafiraWeb/Resources/Autoconsent
# Archive path inside the npm tarball, then the vendored name.
files="package/dist/autoconsent.playwright.js:autoconsent.js package/rules/compact-rules.json:autoconsent-rules.json package/LICENSE:autoconsent-LICENSE.txt"

hash() { shasum -a 256 "$1" | cut -d ' ' -f 1; }
field() { sed -n "s/^$1=//p" "$pin" | head -n 1; }

if [ "${1:-}" = verify ]; then
    [ -r "$pin" ] || { echo "FAILED: no pin file $pin" >&2; exit 1; }
    for pair in $files; do
        name=${pair#*:}
        expected=$(field "$name")
        [ -f "$vendor/$name" ] || { echo "FAILED: $name is not vendored" >&2; exit 1; }
        [ "$(hash "$vendor/$name")" = "$expected" ] || { echo "FAILED: $name does not match the pin" >&2; exit 1; }
    done
    echo "OK: autoconsent $(field version) matches its pin"
    exit 0
fi

[ $# -eq 2 ] || { echo "usage: update-autoconsent.sh <version> <sha256> | verify" >&2; exit 2; }
version=$1
sha256=$2
work=$(mktemp -d "${TMPDIR:-/tmp}/autoconsent.XXXXXX") || exit 1
trap 'rm -rf "${work:?}"' EXIT
archive=$work/autoconsent-$version.tgz
if [ -n "${AUTOCONSENT_ARCHIVE:-}" ]; then
    cp "$AUTOCONSENT_ARCHIVE" "$archive" || exit 1
else
    curl --fail --silent --show-error --location --retry 3 \
        "https://registry.npmjs.org/@duckduckgo/autoconsent/-/autoconsent-$version.tgz" -o "$archive" \
        || { echo "FAILED: cannot download autoconsent $version" >&2; exit 1; }
fi
actual=$(hash "$archive")
[ "$actual" = "$sha256" ] || { echo "FAILED: autoconsent $version has checksum $actual, expected $sha256" >&2; exit 1; }
mkdir "$work/tree" && tar -xzf "$archive" -C "$work/tree" || exit 1
packaged=$(sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' "$work/tree/package/package.json" | head -n 1)
[ "$packaged" = "$version" ] || { echo "FAILED: the archive is autoconsent $packaged, not $version" >&2; exit 1; }

mkdir -p "$vendor"
{
    echo "version=$version"
    echo "sha256=$sha256"
} > "$work/pin"
for pair in $files; do
    source=${pair%%:*}
    name=${pair#*:}
    [ -f "$work/tree/$source" ] || { echo "FAILED: $source is missing from autoconsent $version" >&2; exit 1; }
    cp "$work/tree/$source" "$vendor/$name" || exit 1
    echo "$name=$(hash "$vendor/$name")" >> "$work/pin"
done
cp "$work/pin" "$pin" || exit 1
swift=$repository/Packages/SafiraKit/Sources/SafiraWeb/AutoconsentBundle.swift
sed "s/static let version = \"[^\"]*\"/static let version = \"$version\"/" "$swift" > "$work/swift" \
    && cp "$work/swift" "$swift" || exit 1
echo "OK: autoconsent $version vendored into $vendor"
echo "Then: its version in THIRD_PARTY_NOTICES.md, and the rule count in AutoconsentBundleTests."
