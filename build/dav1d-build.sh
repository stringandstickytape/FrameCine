#!/bin/bash
# Builds dav1d (AV1 decoder, BSD-2-Clause, VideoLAN) as a static library for the engine's FFmpeg (libdav1d decoder of
# build/ffmpeg-build.sh). FFmpeg's own "av1" decoder only drives hardware; on the Steam Frame AV1 is decoded on the CPU.
# Run from Windows (no sudo needed):
#   wsl -d Ubuntu -- bash build/dav1d-build.sh [aarch64|x86_64|all]
# Source:   ~/src/dav1d (cloned once, tag $DAV1D_TAG; not committed anywhere).
# Prefixes: ~/src/dav1d-aarch64 (Steam Frame, NEON assembly), ~/src/dav1d-x86_64 (WSL tests; plain C, there is no nasm in
#           WSL). Each has lib/libdav1d.a and lib/pkgconfig/dav1d.pc.
# Meson:    a private venv in ~/src/meson-venv (pip install meson), made once.

set -euo pipefail
WHICH=${1:-all}
DAV1D_TAG=${DAV1D_TAG:-1.5.4}
SRC=$HOME/src/dav1d
VENV=$HOME/src/meson-venv

if [ ! -x "$VENV/bin/meson" ]; then
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet meson
fi
export PATH=$VENV/bin:$PATH
if [ ! -d "$SRC/.git" ]; then
  git clone --depth 1 --branch "$DAV1D_TAG" https://code.videolan.org/videolan/dav1d.git "$SRC"
fi
echo "dav1d source: $(git -C "$SRC" describe --tags 2>/dev/null || echo "$DAV1D_TAG")"

build() {
  local name=$1
  local prefix=$HOME/src/dav1d-$name
  local dir=$HOME/src/dav1d-build-$name
  local extra=()
  case $name in
    aarch64)
      cat > "$HOME/src/dav1d-cross-aarch64.txt" <<'EOF'
[binaries]
c = 'aarch64-linux-gnu-gcc'
cpp = 'aarch64-linux-gnu-g++'
ar = 'aarch64-linux-gnu-ar'
strip = 'aarch64-linux-gnu-strip'
pkg-config = 'pkg-config'

[host_machine]
system = 'linux'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
EOF
      extra=(--cross-file "$HOME/src/dav1d-cross-aarch64.txt") ;;
    x86_64) extra=(-Denable_asm=false) ;;
    *) echo "unknown target $name"; exit 1 ;;
  esac
  rm -rf "$dir" "$prefix"
  # -fPIC: linked into the engine with -fPIE like the rest of FFmpeg (--enable-pic). Tools and tests off: only the library.
  meson setup "$dir" "$SRC" "${extra[@]}" --prefix="$prefix" --libdir=lib --buildtype=release --default-library=static \
    -Db_staticpic=true -Denable_tools=false -Denable_tests=false -Denable_examples=false -Dlogging=false > /dev/null
  ninja -C "$dir" install > "$dir/install.log" 2>&1 || { tail -30 "$dir/install.log"; exit 1; }
  echo "== $name: $prefix"
  ls -l "$prefix/lib/libdav1d.a"
}

case $WHICH in
  all) build aarch64; build x86_64 ;;
  *) build "$WHICH" ;;
esac
