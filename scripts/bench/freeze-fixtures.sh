#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 Antonin Carlin
#
# Copies the pages of pages.txt once, with the files they need, into a folder that serve.py serves from
# 127.0.0.1, so that no run depends on the network. The copies are not committed (they are other people's pages); the
# folder holds a manifest with the SHA-256 of every file so a later run can show it used the same copies.
#
#   scripts/bench/freeze-fixtures.sh <fixtures folder>
#
# Writes <folder>/index.tsv: number, category, source address, path to open under the server. Prints OK:/FAILED: lines.
set -u
set -o pipefail
cd "$(dirname "$0")/../.."
out=${1:-}
[ -n "$out" ] || { echo "FAILED: usage: scripts/bench/freeze-fixtures.sh <fixtures folder>"; exit 1; }
list=scripts/bench/pages.txt
mkdir -p "$out"
: > "$out/index.tsv"
agent="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

n=0
grep -v '^#' "$list" | while read -r category address; do
    n=$((n + 1))
    id=$(printf '%02d' "$n")
    dir="$out/$id"
    rm -rf "$dir"; mkdir -p "$dir"
    if [ "$category" = video ]; then
        # A constructed page: the video is real (CC0), the page around it is ours. The video is not started.
        wget -q -e netrc=off -T 60 -t 2 -U "$agent" -O "$dir/clip.mp4" "$address" || { echo "FAILED: $id $address"; exit 1; }
        cat > "$dir/index.html" <<HTML
<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Video page $id</title></head>
<body><h1>Video page $id</h1><p>A page whose video is loaded but never started.</p>
<video controls preload="metadata" width="640" src="clip.mp4"></video></body></html>
HTML
        main="$id/index.html"
    else
        saved=$(wget -nv -e netrc=off -E -H -k -K -p -e robots=off -T 60 -t 2 -U "$agent" -P "$dir" "$address" 2>&1 \
            | sed -n 's/.*URL:.* -> "\(.*\)" \[.*/\1/p' | head -1)
        main=${saved#"$out/"}
        [ -n "$saved" ] && [ -f "$saved" ] || { echo "FAILED: $id nothing saved for $address"; exit 1; }
    fi
    printf '%s\t%s\t%s\t%s\n' "$id" "$category" "$address" "$main" >> "$out/index.tsv"
    echo "OK: $id $category $address ($(du -sk "$dir" | cut -f1) KiB)"
done || exit 1
[ "$(wc -l < "$out/index.tsv")" -eq 20 ] || { echo "FAILED: the list froze $(wc -l < "$out/index.tsv") pages, not 20"; exit 1; }
( cd "$out" && find . -type f ! -name MANIFEST.sha256 -print0 | sort -z | xargs -0 shasum -a 256 > MANIFEST.sha256 )
echo "OK: 20 pages frozen in $out, $(du -sh "$out" | cut -f1), manifest $(shasum -a 256 "$out/MANIFEST.sha256" | cut -c1-12)"
