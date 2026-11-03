#!/bin/bash
# Builds tools/materials/mtex_pack (the material library's texture packer, docs/materials.md) against the ASTC
# encoder in the engine fork's source tree, so no other download is needed. Runs in WSL or any Linux with g++.
#   tools/materials/make-packer.sh            output: ~/src/mtex_pack/mtex_pack
# GODOT_SRC picks the engine tree (default ~/src/godot-library; any 4.7 tree with thirdparty/astcenc works).
set -euo pipefail
GODOT_SRC=${GODOT_SRC:-$HOME/src/godot-library}
OUT=${OUT:-$HOME/src/mtex_pack}
ASTC=$GODOT_SRC/thirdparty/astcenc
[ -f "$ASTC/astcenc.h" ] || { echo "no $ASTC/astcenc.h: set GODOT_SRC" >&2; exit 2; }
mkdir -p "$OUT"
HERE=$(cd "$(dirname "$0")" && pwd)
# x86_64 with AVX2 (every PC of the last ten years); the encoder picks its vector code from these flags.
ISA="-mavx2 -mfma -mf16c -mpopcnt -msse4.2"
[ "$(uname -m)" = "x86_64" ] || ISA=""
g++ -O2 -std=c++17 $ISA -I"$ASTC" -o "$OUT/mtex_pack" "$HERE/mtex_pack.cpp" "$ASTC"/astcenc_*.cpp -lpthread
echo "$OUT/mtex_pack"
