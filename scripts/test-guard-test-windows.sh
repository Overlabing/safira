#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 Antonin Carlin
#
# Proves the test-window guard (AppTooling's guard-pattern.sh with test-window-patterns.txt): each file under
# fixtures/test-window-guard/forbidden must fail it, the clean and allowed fixtures must pass it.
set -u
cd "$(dirname "$0")"
tools=$(./tools.sh) || exit 1
fixtures=fixtures/test-window-guard
allowed=$fixtures/Allowed.swift
status=0

guard() { "$tools/bin/guard-pattern.sh" --patterns test-window-patterns.txt --allow "$allowed" "$@"; }

for file in "$fixtures"/forbidden/*.swift; do
    if guard "$file" > /dev/null; then
        echo "guard missed $file"
        status=1
    fi
done
if ! guard "$fixtures/Clean.swift" "$allowed"; then
    echo "guard refused a clean or allowed file"
    status=1
fi
exit $status
