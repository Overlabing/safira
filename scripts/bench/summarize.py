#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 Antonin Carlin
"""Turns the files of a run into numbers, and the runs of a measurement into a table.

    python3 -I scripts/bench/summarize.py run <run folder>      writes <run folder>/summary.json
    python3 -I scripts/bench/summarize.py report <out folder>   prints the table of every arm

A run folder holds samples.csv (+ .ticks), server.csv, status.jsonl and pre.json, written by scripts/bench-memory.sh.
"""
import csv
import json
import os
import statistics
import sys

MIB = 1024 * 1024


def read_rows(path):
    with open(path) as f:
        return [(int(r["t_s"]), int(r["pid"]), r["role"], int(r["footprint_bytes"]), float(r["cpu_s"]))
                for r in csv.DictReader(f)]


def summarize_run(folder):
    rows = read_rows(os.path.join(folder, "samples.csv"))
    last = max(t for t, *_ in rows)
    at_end = [r for r in rows if r[0] == last]
    by_role = {}
    for _, _, role, footprint, _ in at_end:
        by_role[role] = by_role.get(role, 0) + footprint
    total = sum(by_role.values())
    # Idle CPU: the CPU time the processes present at both ends spent over the last five minutes, as a share of one core.
    earlier = max((t for t, *_ in rows if t <= last - 300), default=0)
    cpu = {pid: c for t, pid, _, _, c in rows if t == earlier}
    spent = sum(c - cpu[pid] for _, pid, _, _, c in at_end if pid in cpu)
    span = max(last - earlier, 1)
    with open(os.path.join(folder, "samples.csv.ticks")) as f:
        ticks = list(csv.DictReader(f))
    with open(os.path.join(folder, "server.csv")) as f:
        requests = list(csv.DictReader(f))
    statuses = {}
    for r in requests:
        statuses[r["status"]] = statuses.get(r["status"], 0) + 1
    status = [json.loads(line) for line in open(os.path.join(folder, "status.jsonl")) if line.strip()]
    pre = json.load(open(os.path.join(folder, "pre.json")))
    summary = {
        "total_mib": round(total / MIB, 1),
        "by_role_mib": {k: round(v / MIB, 1) for k, v in sorted(by_role.items())},
        "processes": sum(1 for _ in at_end),
        "webcontent_processes": sum(1 for r in at_end if r[2] == "webcontent"),
        "samples": len({t for t, *_ in rows}),
        "last_sample_s": last,
        "idle_cpu_percent_of_one_core": round(100 * spent / span, 2),
        "pressure_levels_during_run": sorted({int(t["pressure_level"]) for t in ticks}),
        "max_load_1m_during_run": max(float(t["load_1m"]) for t in ticks),
        "server_requests": len(requests),
        "server_status_counts": statuses,
        "server_errors": sum(n for s, n in statuses.items() if int(s) >= 400),
        "pages_requested": len({r["path"] for r in requests if r["path"].endswith((".html", "/"))}),
        "pre": pre,
        "status_events": [e.get("event") for e in status],
        "registered_for_http": next((e.get("registeredForHTTP") for e in status if e.get("event") == "launched"), None),
        "registered_for_https": next((e.get("registeredForHTTPS") for e in status if e.get("event") == "launched"), None),
        "tabs_with_title": sum(1 for e in status if e.get("event") == "ready" for t in e["tabs"] if t["title"]),
        "tabs_still_loading": sum(1 for e in status if e.get("event") == "ready" for t in e["tabs"] if t["isLoading"]),
    }
    with open(os.path.join(folder, "summary.json"), "w") as f:
        json.dump(summary, f, indent=2, sort_keys=True)
    return summary


def report(out):
    arms = {}
    for name in sorted(os.listdir(out)):
        path = os.path.join(out, name, "summary.json")
        if os.path.isfile(path):
            arm = name.split("-")[0]
            arms.setdefault(arm, []).append((name, json.load(open(path))))
    print("| arm | runs | median MiB | min | max | processes (median) | idle CPU % (median) |")
    print("|---|---|---|---|---|---|---|")
    medians = {}
    for arm, runs in arms.items():
        totals = [s["total_mib"] for _, s in runs]
        medians[arm] = statistics.median(totals)
        print(f"| {arm} | {len(runs)} | {medians[arm]:.1f} | {min(totals):.1f} | {max(totals):.1f} | "
              f"{statistics.median(s['processes'] for _, s in runs):.0f} | "
              f"{statistics.median(s['idle_cpu_percent_of_one_core'] for _, s in runs):.2f} |")
    if "safira" in medians and "safari" in medians:
        gap = 100 * (medians["safira"] / medians["safari"] - 1)
        print(f"\nsafira / safari - 1 = {gap:+.1f} % ({'above' if gap > 15 else 'at or below'} the 15 % target)")
    print("\nper run:")
    for arm, runs in arms.items():
        for name, s in runs:
            print(f"- {name}: {s['total_mib']} MiB {s['by_role_mib']}, pressure {s['pressure_levels_during_run']}, "
                  f"max load {s['max_load_1m_during_run']}, server errors {s['server_errors']}/{s['server_requests']}, "
                  f"pre pressure {s['pre']['pressure_level']} load {s['pre']['load_1m']}")


if sys.argv[1] == "run":
    print(json.dumps(summarize_run(sys.argv[2]), indent=2, sort_keys=True))
else:
    report(sys.argv[2])
