#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 Antonin Carlin
#
# Proves `step` (step.sh): a passing check prints OK:, and a failing one prints a FAILED: line and stops the script, also
# when the check dies on an unset variable or calls exit itself.
set -u
set -o pipefail
cd "$(dirname "$0")"
log=$(mktemp)
trap 'rm -f "$log"' EXIT
. ./step.sh
status=0

passes() { echo "fine"; }
fails() { echo "boom"; return 1; }
uses_unset_variable() { echo "${SAFIRA_TEST_STEP_NEVER_SET}"; }
exits_by_itself() { exit 3; }

expect_failed() { # <function>
    # A subshell, because a failed step ends the shell it runs in.
    output=$( (step "$1 step" "$1"; echo "CONTINUED") 2>&1 )
    case $output in
        *"FAILED: $1 step"*) ;;
        *) echo "no FAILED line for $1: $output"; status=1 ;;
    esac
    case $output in
        *CONTINUED*) echo "the script went on after $1 failed"; status=1 ;;
    esac
}

output=$(step "passes step" passes 2>&1)
[ "$output" = "OK: passes step" ] || { echo "a passing step printed: $output"; status=1; }
expect_failed fails
expect_failed uses_unset_variable
expect_failed exits_by_itself
exit $status
