#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 Antonin Carlin
#
# Organisation rule, enforced here because the GitHub plan cannot enforce it on the server: the commits of a pull request
# and its title and description carry no Claude or Anthropic attribution and no personal email address.
#
#   PR_TITLE=… PR_BODY=… scripts/check-attribution.sh <base commit> <head commit>
#
# Looks at: the author and committer address of every commit in base..head, every commit message, the title and the
# description. Prints the commit and the kind of finding, never the address. Exit 1 when something is found.
set -u
base=${1:?usage: check-attribution.sh <base commit> <head commit>}
head=${2:?usage: check-attribution.sh <base commit> <head commit>}

personal='@(icloud\.com|me\.com|mac\.com|gmail\.com|googlemail\.com|outlook\.com|hotmail\.com|live\.com|yahoo\.[a-z.]+|proton\.me|protonmail\.com)([^A-Za-z0-9-]|$)'
attribution='^[[:space:]]*Co-Authored-By:.*(claude|anthropic)|Generated with \[?Claude Code'
status=0

report() { echo "FOUND: $1"; status=1; }

commits=$(git rev-list "$base..$head") || { echo "FAILED: cannot list $base..$head" >&2; exit 2; }
for commit in $commits; do
    short=$(printf '%s' "$commit" | cut -c1-12)
    git log -1 --format='%ae%n%ce' "$commit" | grep -q -i -E "$personal" && report "commit $short: a personal email address as author or committer"
    git log -1 --format=%B "$commit" | grep -q -i -E "$attribution" && report "commit $short: a Claude or Anthropic attribution line in the message"
    git log -1 --format=%B "$commit" | grep -q -i -E "$personal" && report "commit $short: a personal email address in the message"
done
for text in PR_TITLE PR_BODY; do
    eval "value=\${$text:-}"
    printf '%s\n' "$value" | grep -q -i -E "$attribution" && report "$text: a Claude or Anthropic attribution line"
    printf '%s\n' "$value" | grep -q -i -E "$personal" && report "$text: a personal email address"
done
if [ "$status" -eq 0 ]; then
    echo "OK: attribution check: $(printf '%s\n' "$commits" | grep -c .) commit(s), title and description are clean"
else
    echo "FAILED: attribution check: no Claude attribution and no personal email address in commits or pull request text"
fi
exit $status
