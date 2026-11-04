# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 Antonin Carlin
#
# Sourced by check.sh. `step <label> <command...>` runs one check and prints OK: or FAILED:; on failure it shows the
# tail of the output and exits. The caller sets `log` to a scratch file.
#
# The command runs in a subshell. Under `set -u`, a function that expands an unset variable ends the shell it runs
# in, and in the main shell that would end check.sh before it printed FAILED: with its output hidden in the log.
step() { # <label> <command...>
    label=$1; shift
    if ( "$@" ) > "$log" 2>&1; then
        echo "OK: $label"
    else
        tail -40 "$log"
        grep -E "recorded an issue|error:" "$log" | head -20
        echo "FAILED: $label"
        exit 1
    fi
}
