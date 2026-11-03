#!/bin/bash
# Builds a static libsmb2 (SMB2/3 client, NTLMSSP, no Kerberos) for the engine fork's hwvideo module: MediaSource opens
# smb://host/share/path files through it, MediaBrowser lists shares and folders. Run from Windows (no sudo needed):
#   wsl -d Ubuntu -- bash build/libsmb2-build.sh [aarch64|x86_64|all]
# Source:   ~/src/libsmb2 (cloned once, tag $LIBSMB2_TAG; not committed anywhere).
# Prefixes: ~/src/libsmb2-aarch64 (Steam Frame), ~/src/libsmb2-x86_64 (WSL tests). modules/hwvideo/SCsub picks one by
#           arch (override: HWVIDEO_LIBSMB2_PREFIX). A few seconds each.
#
# Licence: the client library (lib/, include/) is LGPL 2.1 or later; the DCE/RPC part (share enumeration) is BSD-2.
# Statically linked like FFmpeg; see the README's licence note.
# No dependencies: libsmb2 has its own MD4/MD5/HMAC/SHA/AES for NTLMSSP, SMB3 signing and encryption.
#
# Patches (build/libsmb2-patches, applied to a clean checkout of the tag):
#   0001-signing-fast-aes-cmac.patch: SMB 3.x signing (AES-CMAC) expands the key once per message, reads the iovecs in
#     place, and uses ARMv8 Crypto Extensions / AES-NI when present. Windows 11 requires signing, and libsmb2 checks the
#     signature of every response, READ data included: unpatched, that cost ~9 ms of CPU per MiB on x86 (0.43 patched).

set -euo pipefail
WHICH=${1:-all}
LIBSMB2_TAG=${LIBSMB2_TAG:-libsmb2-6.3.1}
SRC=$HOME/src/libsmb2
JOBS=$(( $(nproc) - 2 ))

if [ ! -d "$SRC/.git" ]; then
  mkdir -p "$(dirname "$SRC")"
  git clone https://github.com/sahlberg/libsmb2.git "$SRC"
fi
git -C "$SRC" fetch -q --tags || true
# A clean checkout of the tag, then our patches (build/libsmb2-patches, in order).
git -C "$SRC" checkout -q -f "$LIBSMB2_TAG"
git -C "$SRC" clean -fdq
PATCHES=$(dirname "$(readlink -f "$0")")/libsmb2-patches
for p in "$PATCHES"/*.patch; do
  git -C "$SRC" apply "$p"
  echo "applied $(basename "$p")"
done
echo "libsmb2 source: $(git -C "$SRC" describe --tags)"

build() {
  local name=$1
  local prefix=$HOME/src/libsmb2-$name
  local dir=$HOME/src/libsmb2-build-$name
  local cross=()
  if [ "$name" = aarch64 ]; then
    cross=(-DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSTEM_PROCESSOR=aarch64 -DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc
      -DCMAKE_AR=/usr/bin/aarch64-linux-gnu-ar -DCMAKE_RANLIB=/usr/bin/aarch64-linux-gnu-ranlib)
  fi
  rm -rf "$dir" "$prefix"
  cmake -S "$SRC" -B "$dir" -G Ninja "${cross[@]}" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DBUILD_SHARED_LIBS=OFF -DENABLE_EXAMPLES=OFF -DENABLE_LIBKRB5=OFF -DENABLE_GSSAPI=OFF > "$dir.log" 2>&1 ||
    { tail -30 "$dir.log"; exit 1; }
  cmake --build "$dir" -j "$JOBS" >> "$dir.log" 2>&1 || { tail -30 "$dir.log"; exit 1; }
  cmake --install "$dir" >> "$dir.log" 2>&1 || { tail -30 "$dir.log"; exit 1; }
  echo "== $name: $prefix"
  ls -l "$prefix"/lib*/libsmb2.a
}

case "$WHICH" in
  aarch64|x86_64) build "$WHICH" ;;
  all) build aarch64; build x86_64 ;;
  *) echo "usage: $0 [aarch64|x86_64|all]"; exit 1 ;;
esac
