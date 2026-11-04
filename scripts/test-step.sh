#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 Antonin Carlin
#
# Proves how check.sh uses AppTooling's `step`: a passing check prints OK:, and a failing one prints a FAILED: line and
# stops the script, also when a function step dies on an unset variable or calls exit itself (`isolated`, isolated.sh).
# AppTooling's own tests cover `step` with commands; they do not cover a function that ends its shell.
set -u
set -o pipefail
cd "$(dirname "$0")"
tools=$(./tools.sh) || exit 1
log_dir=$(mktemp -d)
trap 'rm -rf "${log_dir:?}"' EXIT
GATE_LOG_DIR=$log_dir
. "$tools/lib/gate.sh"
. ./isolated.sh
status=0

passes() { echo "fine"; }
fails() { echo "boom"; return 1; }
uses_unset_variable() { echo "${SAFIRA_TEST_STEP_NEVER_SET}"; }
exits_by_itself() { exit 3; }

expect_failed() { # <function>
    # A subshell, because a failed step ends the shell it runs in.
    output=$( (step "$1 step" isolated "$1"; echo "CONTINUED") 2>&1 )
    case $output in
        *"FAILED: $1 step"*) ;;
        *) echo "no FAILED line for $1: $output"; status=1 ;;
    esac
    case $output in
        *CONTINUED*) echo "the script went on after $1 failed"; status=1 ;;
    esac
}

output=$(step "passes step" isolated passes 2>&1)
[ "$output" = "OK: passes step" ] || { echo "a passing step printed: $output"; status=1; }
expect_failed fails
expect_failed uses_unset_variable
expect_failed exits_by_itself
exit $status
