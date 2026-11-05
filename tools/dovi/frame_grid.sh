#!/bin/bash
# Block means of one frame of two encodes of the same master at the same times (docs/dolby-vision.md), for fit_dovi.py.
#   P8_OFFSET=-0.959 bash tools/dovi/frame_grid.sh <folder> <name part of encode A> <name part of encode B> <out dir> <seconds>...
# A: the Dolby Vision profile 5 file (IPT planes); B: the HDR10 or profile 8 encode. P8_OFFSET (seconds) is added to
# B's times: the offset align_dovi.py found. Needs build.sh first.
set -euo pipefail
DIR=$1; PA=$2; PB=$3; OUT=$4; shift 4
mkdir -p "$OUT"
[ -x /tmp/frame_grid ] || { echo "run tools/dovi/build.sh first"; exit 1; }
cd "$DIR"
A=$(ls | grep -F -- "$PA" | head -1)
B=$(ls | grep -F -- "$PB" | head -1)
[ -n "$A" ] && [ -n "$B" ] || { echo "no file matches one of the name parts"; exit 1; }
OFF=${P8_OFFSET:-0}
for t in "$@"; do
  tb=$(python3 -c "print($t + ($OFF))")
  timeout 600 /tmp/frame_grid "$A" "$t" 48 27 > "$OUT/p5_$t.txt" 2>/dev/null
  timeout 600 /tmp/frame_grid "$B" "$tb" 48 27 > "$OUT/p8_$t.txt" 2>/dev/null
  echo "t=$t: $(head -1 "$OUT/p5_$t.txt") | $(head -1 "$OUT/p8_$t.txt")"
done
