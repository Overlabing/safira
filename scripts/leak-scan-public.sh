#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 Antonin Carlin
#
# AppTooling's leak scan with the committed public patterns (what CI can run without the private terms file), minus the
# files whose matches are known and harmless. Only the public scan skips them: the private-terms scan reads every file.
#
#   scripts/leak-scan-public.sh tree | history | staged | message FILE
#
# Why each file is listed:
#   - the test files hold invented identifiers shaped like a Slack workspace id (a letter, a digit, then capitals), the placeholder
#     home directory /Users/me, and example mail addresses on reserved domains;
#   - THIRD_PARTY_NOTICES.md carries the copyright line of an upstream author, whose address is public in the upstream.
set -u
cd "$(dirname "$0")/.."
tools=$(scripts/tools.sh) || exit 1
exec "$tools/bin/leak-scan" --public \
    --exclude 'Packages/SafiraKit/Tests/DiagnosticsTests/MaskingTests.swift' \
    --exclude 'Packages/SafiraKit/Tests/LinkRoutingTests/ExternalLinkCoordinatorTests.swift' \
    --exclude 'Packages/SafiraKit/Tests/LinkRoutingTests/IncomingLinkTests.swift' \
    --exclude 'Packages/SafiraKit/Tests/LinkRoutingTests/LinkChoiceLogTests.swift' \
    --exclude 'Packages/SafiraKit/Tests/LinkRoutingTests/LinkRouterTests.swift' \
    --exclude 'Packages/SafiraKit/Tests/LinkRoutingTests/NativeAppLinksTests.swift' \
    --exclude 'Packages/SafiraKit/Tests/SafiraSessionTests/ExternalLinkTests.swift' \
    --exclude 'Packages/SafiraKit/Tests/SafiraStoreTests/HistoryTests.swift' \
    --exclude 'THIRD_PARTY_NOTICES.md' \
    "$@"
