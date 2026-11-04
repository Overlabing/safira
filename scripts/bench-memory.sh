#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 Antonin Carlin
#
# Memory of about 20 resting Tabs, Safira against Safari (docs/research-tab-discarding.md §5, docs/architecture-v1.md
# §9.4). Unattended: builds the Benchmark configuration, freezes the pages once, then for each run checks the memory
# pressure, opens the 20 pages without interaction 5 s apart, lets them rest, and samples the footprint of the browser
# and of every process it is responsible for every 30 s. Prints OK:/FAILED: lines; the table is printed at the end.
#
#   scripts/bench-memory.sh [--arms safira,safari] [--runs 3] [--rest 600] [--gap 5] [--out <folder>]
#                           [--fixtures <folder>] [--no-build] [--pressure-wait 1800] [--allow-pressure]
#                           [--first-round 1]
#
# Each run waits up to --pressure-wait seconds for normal memory pressure (level 1), then stops with FAILED. With
# --allow-pressure it runs anyway after that wait and records the level it ran under, in pre.json, in every sample, and
# in the table: for a Mac that never gets quiet, a run that says so beats no run.
#
# The arms alternate within each round (safira, safari, safira, ...) so that drift in the machine does not favour one.
# Arm names follow the protocol: safira is A0 (hidden Tabs, WebKit's own suspension, no discarding), safari is S.
#
# Safari is the user's own app. The harness opens the pages in it with `open -g` and never closes them, quits it or
# drives it with a script: close the 20 tabs of each Safari run yourself. Runs after the first start from a Safari that
# holds the earlier tabs, so for several Safari runs close them between rounds or measure Safari once.
#
# Reuse for the final memory and CPU measurement: change pages.txt, --rest and the arms; sample.py and summarize.py
# take any app pid.
set -u
set -o pipefail
cd "$(dirname "$0")/.."

arms=safira,safari runs=3 rest=600 gap=5 build=1 pressure_wait=1800 allow_pressure=0 first_round=1
out="" fixtures=".build/bench-fixtures"
while [ $# -gt 0 ]; do
    case $1 in
        --arms) arms=$2; shift 2 ;;
        --runs) runs=$2; shift 2 ;;
        --rest) rest=$2; shift 2 ;;
        --gap) gap=$2; shift 2 ;;
        --out) out=$2; shift 2 ;;
        --fixtures) fixtures=$2; shift 2 ;;
        --pressure-wait) pressure_wait=$2; shift 2 ;;
        --first-round) first_round=$2; shift 2 ;;
        --allow-pressure) allow_pressure=1; shift ;;
        --no-build) build=0; shift ;;
        *) echo "FAILED: unknown argument $1"; exit 1 ;;
    esac
done
[ -n "$out" ] || out=".build/bench-results/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$out"
out=$(cd "$out" && pwd)

bundle=com.overlabing.safira.bench
app="$PWD/.build/dd/Build/Products/Benchmark/Safira.app"
container="$HOME/Library/Containers/$bundle"
status_file="$container/Data/Library/Application Support/$bundle/bench-status.jsonl"
shared=/private/tmp/safira-bench
server_pid="" app_pid=""

fail() { echo "FAILED: $*"; exit 1; }
cleanup() {
    [ -n "$server_pid" ] && kill "$server_pid" 2>/dev/null
    [ -n "$app_pid" ] && kill "$app_pid" 2>/dev/null
    return 0
}
trap cleanup EXIT

pressure_level() { sysctl -n kern.memorystatus_vm_pressure_level; }

# Memory pressure must be normal (1) before a run: the protocol's first control. Waits for it, then gives up.
wait_for_normal_pressure() {
    waited=0
    while [ "$(pressure_level)" != 1 ]; do
        if [ "$waited" -ge "$pressure_wait" ]; then
            [ "$allow_pressure" = 1 ] || return 1
            echo "WARN: memory pressure level $(pressure_level), not normal, after ${waited} s; running anyway (--allow-pressure)"
            return 0
        fi
        sleep 30; waited=$((waited + 30))
    done
    echo "OK: memory pressure normal before the run (waited ${waited} s)"
}

record_machine() { # <run folder>
    python3 -I - "$1/pre.json" "$(pressure_level)" <<'EOF'
import json, os, subprocess, sys
free = subprocess.run(["memory_pressure"], capture_output=True, text=True).stdout
percent = next((int(l.split(":")[1].strip().rstrip("%")) for l in free.splitlines() if "free percentage" in l), None)
swap = subprocess.run(["sysctl", "-n", "vm.swapusage"], capture_output=True, text=True).stdout.strip()
top = subprocess.run(["ps", "-Axo", "rss=,comm="], capture_output=True, text=True).stdout.splitlines()
top = sorted(((int(l.split(None, 1)[0]), l.split(None, 1)[1].rsplit("/", 1)[-1]) for l in top if l.strip()), reverse=True)[:6]
json.dump({"pressure_level": int(sys.argv[2]), "load_1m": round(os.getloadavg()[0], 2), "cores": os.cpu_count(),
           "memory_free_percent": percent, "swap": swap, "largest_resident": [f"{n} {k // 1024} MiB" for k, n in top]},
          open(sys.argv[1], "w"), indent=2)
EOF
}

start_server() { # <run folder>
    python3 -I scripts/bench/serve.py "$fixtures" "$1/server.csv" > "$1/server.port" &
    server_pid=$!
    for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$1/server.port" ] && break; sleep 0.5; done
    port=$(head -1 "$1/server.port")
    [ -n "$port" ] || fail "the local server did not start"
}

stop_server() { kill "$server_pid" 2>/dev/null; wait "$server_pid" 2>/dev/null; server_pid=""; }

write_urls() { # <file>
    python3 -I - "$fixtures/index.tsv" "$port" > "$1" <<'EOF'
import sys, urllib.parse
for line in open(sys.argv[1]):
    path = line.rstrip("\n").split("\t")[3]
    print(f"http://127.0.0.1:{sys.argv[2]}/" + urllib.parse.quote(path))
EOF
}

# The pages are all fetched and the server has been quiet for 5 s: the end of the last load, and the start of the rest.
wait_for_quiet_server() { # <run folder>
    waited=0
    while [ "$waited" -lt 180 ]; do
        last=$(tail -1 "$1/server.csv" | cut -d, -f1 | cut -d. -f1)
        if [ "$last" -gt 0 ] 2>/dev/null && [ $(( $(date +%s) - last )) -ge 5 ]; then return 0; fi
        sleep 1; waited=$((waited + 1))
    done
    fail "the pages were still being fetched, or never fetched, 180 s after the last one was opened"
}

run_safira() { # <run folder>
    dir=$1
    write_urls "$shared/urls.txt"
    # The container itself is protected; what it holds, including the saved Tabs a relaunch would restore, is not.
    rm -rf "$container/Data"
    [ ! -e "$container/Data/Library/Application Support/$bundle" ] || fail "the container of $bundle could not be emptied"
    open -g -n -a "$app" --args -SafiraBenchURLs "$shared/urls.txt" -SafiraBenchGapSeconds "$gap" || fail "open $app"
    waited=0
    until [ -s "$status_file" ] && grep -q '"event":"launched"' "$status_file"; do
        sleep 1; waited=$((waited + 1)); [ "$waited" -lt 90 ] || fail "Safira did not report launching"
    done
    app_pid=$(python3 -I -c "import json,sys;print(json.loads(open(sys.argv[1]).readline())['pid'])" "$status_file")
    echo "OK: Safira launched in the background (pid $app_pid), registered for http/https: $(head -1 "$status_file" | python3 -I -c "import json,sys;d=json.load(sys.stdin);print(d['registeredForHTTP'],d['registeredForHTTPS'])")"
    waited=0
    until grep -q '"event":"ready"' "$status_file"; do
        sleep 2; waited=$((waited + 2)); [ "$waited" -lt $((gap * 20 + 600)) ] || fail "Safira did not finish loading the pages"
        kill -0 "$app_pid" 2>/dev/null || fail "Safira stopped while loading"
    done
    wait_for_quiet_server "$dir"
    echo "OK: 20 pages loaded, first Tab selected; the rest starts"
    python3 -I scripts/bench/sample.py "$app_pid" "$rest" 30 "$dir/samples.csv" || fail "sampling Safira"
    cp "$status_file" "$dir/status.jsonl"
    kill -0 "$app_pid" 2>/dev/null || fail "Safira stopped during the rest"
    kill "$app_pid" 2>/dev/null; app_pid=""
}

run_safari() { # <run folder>
    dir=$1
    pgrep -x Safari > /dev/null || { open -g -a Safari; sleep 5; }
    safari_pid=$(pgrep -x Safari | head -1)
    python3 -I scripts/bench/sample.py "$safari_pid" baseline > "$dir/baseline.json" || fail "Safari baseline"
    write_urls "$dir/urls.txt"
    while read -r address; do
        open -g -a Safari "$address"
        sleep "$gap"
    done < "$dir/urls.txt"
    wait_for_quiet_server "$dir"
    echo "OK: 20 pages opened in Safari (pid $safari_pid); the rest starts"
    python3 -I scripts/bench/sample.py "$safari_pid" "$rest" 30 "$dir/samples.csv" "$dir/baseline.json" || fail "sampling Safari"
    : > "$dir/status.jsonl"
}

# --- before anything slow -----------------------------------------------------------------------------------------

[ "$(uname -m)" = arm64 ] || fail "arm64 only"
mkdir -p "$shared"
if [ "$build" = 1 ]; then
    xcodegen generate > "$out/build.log" 2>&1 || fail "xcodegen generate (see $out/build.log)"
    xcodebuild -project Safira.xcodeproj -scheme Safira -configuration Benchmark -derivedDataPath .build/dd build \
        >> "$out/build.log" 2>&1 || fail "xcodebuild Benchmark (see $out/build.log)"
    echo "OK: Benchmark configuration built"
fi
[ -d "$app" ] || fail "$app is missing: build without --no-build"
# `grep -c` reads everything: `grep -q` would exit early and, under pipefail, fail the `strings` feeding it.
[ "$(strings -a "$app/Contents/MacOS/Safira" | grep -c BenchmarkRun)" -gt 0 ] || fail "$app has no benchmark mode: not a Benchmark build"
[ -f "$fixtures/index.tsv" ] || scripts/bench/freeze-fixtures.sh "$fixtures" || exit 1
cp "$fixtures/index.tsv" "$fixtures/MANIFEST.sha256" "$out/"
{
    echo "commit: $(git rev-parse --short HEAD)$(git status --porcelain | grep -q . && echo ' (modified)')"
    echo "macOS: $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) GiB"
    echo "Safari: $(defaults read /System/Cryptexes/App/System/Applications/Safari.app/Contents/Info CFBundleShortVersionString 2>/dev/null)"
    echo "arms: $arms, runs: $runs, rest: $rest s, gap: $gap s, fixtures manifest: $(shasum -a 256 "$fixtures/MANIFEST.sha256" | cut -c1-16)"
} >> "$out/environment.txt"
tail -4 "$out/environment.txt"

# --- the runs -----------------------------------------------------------------------------------------------------

round=$first_round
while [ "$round" -le "$runs" ]; do
    for arm in $(echo "$arms" | tr ',' ' '); do
        name="$arm-$(printf '%02d' "$round")"
        dir="$out/$name"
        mkdir -p "$dir"
        echo "--- $name ($(date '+%H:%M:%S'))"
        wait_for_normal_pressure || fail "$name: memory pressure was not normal after ${pressure_wait} s; no run started"
        record_machine "$dir"
        start_server "$dir"
        case $arm in
            safira) run_safira "$dir" ;;
            safari) run_safari "$dir" ;;
            *) fail "unknown arm $arm" ;;
        esac
        stop_server
        python3 -I scripts/bench/summarize.py run "$dir" > /dev/null || fail "$name: summarizing"
        echo "OK: $name $(python3 -I -c "import json,sys;d=json.load(open(sys.argv[1]));print(d['total_mib'],'MiB,',d['processes'],'processes, server errors',d['server_errors'],', pages requested',d['pages_requested'])" "$dir/summary.json")"
    done
    round=$((round + 1))
done

python3 -I scripts/bench/summarize.py report "$out" | tee "$out/report.md"
echo "OK: measurement finished, results in $out"
