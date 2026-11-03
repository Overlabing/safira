#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 Antonin Carlin
#
# Fails when a Swift file names a shared network singleton, or a website data store, outside the one allowed file
# (docs/architecture-v1.md §2.2): such a singleton would share data between Profiles.
# Usage: scripts/guard-singletons.sh <allowed file> <directory or file>...
set -u
allowed=$1
shift

found=$(find "$@" -name '*.swift' -type f ! -path '*/.build/*' ! -path "$allowed" -print0 \
    | xargs -0 grep -n -F \
        -e 'WKWebsiteDataStore.default()' \
        -e 'WKWebsiteDataStore(forIdentifier:' \
        -e 'URLSession.shared' \
        -e 'HTTPCookieStorage.shared' \
        -e 'URLCache.shared' \
        /dev/null)
if [ -n "$found" ]; then
    echo "$found"
    echo "Shared singletons are allowed only in $allowed"
    exit 1
fi
