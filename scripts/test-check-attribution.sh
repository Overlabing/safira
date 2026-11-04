#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 Antonin Carlin
#
# Proves check-attribution.sh on a scratch repository: clean commits pass; a personal author address, a Claude
# co-author line, a "Generated with Claude Code" footer and a personal address in the title or description each fail.
set -u
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "${work:?}"' EXIT
cd "$work" || exit 1
git init -q .
git config user.name Tester
git config commit.gpgsign false
status=0
# Built in pieces: the public leak scan would flag a personal address written out in this file.
icloud=icloud.com
gmail=gmail.com
proton=proton.me

commit() { # <author email> <message>
    echo "$2" >> file
    git add file
    GIT_AUTHOR_EMAIL=$1 GIT_COMMITTER_EMAIL=${3:-$1} git commit -q -m "$2"
}
check() { # <expected exit> <label> <base> [env…]
    expected=$1 label=$2 base=$3
    shift 3
    env "$@" "$here/check-attribution.sh" "$base" HEAD > out.txt 2>&1
    actual=$?
    [ "$actual" -eq "$expected" ] || { echo "$label: exit $actual, expected $expected"; cat out.txt; status=1; }
    if grep -q -i -E "icloud|gmail|proton|claude@|anthropic\.com" out.txt; then echo "$label: the output names an address"; status=1; fi
}

commit "1+someone@users.noreply.github.com" "root"
root=$(git rev-parse HEAD)
commit "1+someone@users.noreply.github.com" "fine"
check 0 "clean commit, empty text" "$root" PR_TITLE="Add a thing" PR_BODY="Closes #1"

commit "someone@$icloud" "personal author"
check 1 "personal author address" "$root"
git reset -q --hard "$root"
commit "1+someone@users.noreply.github.com" "personal committer" "someone@$gmail"
check 1 "personal committer address" "$root"
git reset -q --hard "$root"
commit "1+someone@users.noreply.github.com" "$(printf 'trailer\n\nCo-Authored-By: Claude <noreply@anthropic.com>')"
check 1 "Claude co-author line" "$root"
git reset -q --hard "$root"
commit "1+someone@users.noreply.github.com" "$(printf 'body\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)')"
check 1 "Claude Code footer" "$root"
git reset -q --hard "$root"
commit "1+someone@users.noreply.github.com" "fine"
check 1 "co-author line in the description" "$root" PR_TITLE="ok" PR_BODY="$(printf 'text\nCo-authored-by: Claude Sonnet <x@y.z>')"
check 1 "personal address in the title" "$root" PR_TITLE="mail someone@$proton" PR_BODY=""
exit $status
