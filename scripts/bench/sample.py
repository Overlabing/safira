#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 Antonin Carlin
"""Samples the memory footprint and CPU time of an app and of every process it is responsible for, at a fixed interval.

    python3 -I scripts/bench/sample.py <app pid> <duration s> <interval s> <samples csv> [baseline json]

A web browser's WebKit helpers (WebContent, Networking, GPU) have launchd as their parent, so the process tree does not
link them to the app. The responsible process (`responsibility_get_pid_responsible_for_pid`, what Activity Monitor
groups by) does. The symbol is undocumented: it is used here as a measurement tool, never in the app
(docs/architecture-v1.md §9.4).

Footprint is `phys_footprint` from `footprint -j`, which includes compressed memory. A process that already existed
when the baseline was taken counts only for what it grew since (an app that was already running, such as Safari);
a new process counts in full. Rows: t_s, pid, role, footprint_bytes, cpu_s. Each sample also appends to
`<samples csv>.ticks`: t_s, memory pressure level (1 normal, 2 warning, 4 critical), 1 minute load average.

With `baseline` as the only argument after the app pid, prints the baseline JSON for the app and exits.
"""
import csv
import ctypes
import json
import os
import subprocess
import sys
import tempfile
import time

_responsible = ctypes.CDLL(None).responsibility_get_pid_responsible_for_pid
_responsible.restype, _responsible.argtypes = ctypes.c_int, [ctypes.c_int]


def run(*args):
    return subprocess.run(args, capture_output=True, text=True).stdout


def role_of(command, pid, app):
    name = command.rsplit("/", 1)[-1]
    if pid == app:
        return "main"
    for key, role in (("WebKit.WebContent", "webcontent"), ("WebKit.Networking", "networking"), ("WebKit.GPU", "gpu")):
        if key in command:
            return role
    return "other:" + name


def attributed(app):
    """pid -> (role, command) of the app and every process it is responsible for."""
    found = {}
    for line in run("ps", "-axo", "pid=,comm=").splitlines():
        pid_text, _, command = line.strip().partition(" ")
        pid = int(pid_text)
        if pid == os.getpid():
            continue
        if pid == app or _responsible(pid) == app:
            found[pid] = (role_of(command, pid, app), command)
    return found


def footprint(pid, scratch):
    path = os.path.join(scratch, f"{pid}.json")
    subprocess.run(["footprint", "-p", str(pid), "-j", path], capture_output=True)
    try:
        with open(path) as f:
            return int(json.load(f)["total footprint"])
    except (OSError, ValueError, KeyError):
        return None


def cpu_seconds(pid):
    text = run("ps", "-o", "time=", "-p", str(pid)).strip()
    try:
        minutes, rest = text.split(":")
        return int(minutes) * 60 + float(rest)
    except ValueError:
        return None


def pressure_level():
    return int(run("sysctl", "-n", "kern.memorystatus_vm_pressure_level").strip() or 0)


def baseline(app):
    with tempfile.TemporaryDirectory() as scratch:
        return {str(pid): {"role": role, "footprint": footprint(pid, scratch) or 0, "cpu_s": cpu_seconds(pid) or 0.0}
                for pid, (role, _) in attributed(app).items()}


def sample(app, duration, interval, out, base):
    start = time.time()
    with tempfile.TemporaryDirectory() as scratch, open(out, "w", newline="") as rows, open(out + ".ticks", "w") as ticks:
        writer = csv.writer(rows)
        writer.writerow(["t_s", "pid", "role", "footprint_bytes", "cpu_s"])
        ticks.write("t_s,pressure_level,load_1m\n")
        while True:
            now = round(time.time() - start)
            for pid, (role, _) in attributed(app).items():
                fp, cpu = footprint(pid, scratch), cpu_seconds(pid)
                if fp is None or cpu is None:
                    continue
                before = base.get(str(pid), {"footprint": 0, "cpu_s": 0.0})
                writer.writerow([now, pid, role, fp - before["footprint"], f"{cpu - before['cpu_s']:.2f}"])
            rows.flush()
            ticks.write(f"{now},{pressure_level()},{os.getloadavg()[0]:.2f}\n")
            ticks.flush()
            if now >= duration:
                return
            time.sleep(max(0.0, interval - ((time.time() - start) % interval)))


def main():
    app = int(sys.argv[1])
    if sys.argv[2:] == ["baseline"]:
        print(json.dumps(baseline(app)))
        return
    duration, interval, out = float(sys.argv[2]), float(sys.argv[3]), sys.argv[4]
    base = json.load(open(sys.argv[5])) if len(sys.argv) > 5 else {}
    sample(app, duration, interval, out, base)


main()
