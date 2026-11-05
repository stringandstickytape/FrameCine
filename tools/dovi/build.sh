#!/bin/bash
# Builds dovi_dump and frame_grid (docs/dolby-vision.md) against the static FFmpeg of build/ffmpeg-build.sh, in WSL:
#   bash tools/dovi/build.sh            -> /tmp/dovi_dump, /tmp/frame_grid
#   /tmp/dovi_dump <file> [frames]      the RPU of the first frames that carry one: colour block and reshaping curves
#   /tmp/frame_grid <file> <seconds> [cols rows frames]   block means of the planes, "x y Y U V" per block
# Needs the x86_64 "all" FFmpeg (~/src/ffmpeg-x86_64-all) and dav1d (~/src/dav1d-x86_64); zlib is linked by its
# soname because the WSL image has no zlib headers package.
set -euo pipefail
S=$(cd "$(dirname "$0")" && pwd)
FF=$HOME/src/ffmpeg-x86_64-all
PCS=$(find "$FF" "$HOME/src/dav1d-x86_64" -name '*.pc' -printf '%h\n' 2>/dev/null | sort -u | tr '\n' ':')
export PKG_CONFIG_PATH="$PCS"
CFLAGS=$(pkg-config --static --cflags libavformat libavcodec libavutil)
LIBS=$(pkg-config --static --libs libavformat libavcodec libavutil)
LIBS=${LIBS/-lz/-l:libz.so.1}
for prog in dovi_dump frame_grid; do
  gcc -O1 -o "/tmp/$prog" "$S/$prog.c" $CFLAGS $LIBS 2>&1 | grep -v -i warning | grep -v "^ " || true
  [ -x "/tmp/$prog" ] && echo "built /tmp/$prog" || { echo "$prog: build failed"; exit 1; }
done
