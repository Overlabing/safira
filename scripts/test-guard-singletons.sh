#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 Antonin Carlin
#
# Proves the singleton guard: each file under fixtures/singleton-guard/forbidden must fail it, the clean and allowed
# fixtures must pass it.
set -u
cd "$(dirname "$0")"
fixtures=fixtures/singleton-guard
allowed=$fixtures/Allowed.swift
status=0

for file in "$fixtures"/forbidden/*.swift; do
    if ./guard-singletons.sh "$allowed" "$file" > /dev/null; then
        echo "guard missed $file"
        status=1
    fi
done
if ! ./guard-singletons.sh "$allowed" "$fixtures/Clean.swift" "$allowed"; then
    echo "guard refused a clean or allowed file"
    status=1
fi
exit $status
