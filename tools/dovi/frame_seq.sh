#!/bin/bash
# Runs of consecutive frames of two encodes around the same times (docs/dolby-vision.md), for align_dovi.py: 24 frames
# of encode A from each time, 16 x 9 blocks, and 168 frames of encode B from 3 s earlier.
#   bash tools/dovi/frame_seq.sh <folder> <name part of encode A> <name part of encode B> <out dir> <seconds>...
# Needs build.sh first.
set -euo pipefail
DIR=$1; PA=$2; PB=$3; OUT=$4; shift 4
mkdir -p "$OUT"
[ -x /tmp/frame_grid ] || { echo "run tools/dovi/build.sh first"; exit 1; }
cd "$DIR"
A=$(ls | grep -F -- "$PA" | head -1)
B=$(ls | grep -F -- "$PB" | head -1)
[ -n "$A" ] && [ -n "$B" ] || { echo "no file matches one of the name parts"; exit 1; }
for t in "$@"; do
  tb=$(python3 -c "print($t - 3.0)")
  timeout 900 /tmp/frame_grid "$A" "$t" 16 9 24 > "$OUT/p5_$t.txt" 2>/dev/null
  timeout 900 /tmp/frame_grid "$B" "$tb" 16 9 168 > "$OUT/p8_$t.txt" 2>/dev/null
  echo "t=$t: A $(grep -c '^#' "$OUT/p5_$t.txt") frames, B $(grep -c '^#' "$OUT/p8_$t.txt") frames"
done
