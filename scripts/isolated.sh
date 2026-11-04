# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 Antonin Carlin
#
# Sourced by check.sh and its self test, after AppTooling's lib/gate.sh. `isolated <command...>` runs a shell function as
# a gate step in a subshell: under `set -u` a function that expands an unset variable ends the shell it runs in, and in
# the main shell that would end check.sh before it printed FAILED: (the output stays in the log). Use it as
# `step "label" isolated some_function`.
isolated() { ( "$@" ); }
