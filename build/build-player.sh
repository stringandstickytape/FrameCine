#!/bin/bash
# Builds the player engine (worktree ~/src/godot-player, fork branch frame/player) with the hwvideo module.
#   wsl -d Ubuntu -- bash build/build-player.sh [arm64|x86_64]
# arm64:  the Steam Frame binary (cross-built, template_debug, optimize=speed), bin/godot.linuxbsd.template_debug.arm64
# x86_64: a host build for the headless tests in WSL (spikes/03-player/demux-test), bin/godot.linuxbsd.template_debug.x86_64
# Needs the static FFmpeg of build/ffmpeg-build.sh: branch frame/player links ~/src/ffmpeg-<arch> (PROFILE=minimal);
# branch frame/codecs (SRC=~/src/godot-player-codecs) links ~/src/ffmpeg-<arch>-all and ~/src/dav1d-<arch>
# (build/dav1d-build.sh first).
# Log: ~/godot-player-build-<arch>.log. OPT=none for a debuggable build.

set -euo pipefail
ARCH=${1:-arm64}
SRC=${SRC:-$HOME/src/godot-player} # SRC=~/src/<another worktree of the fork> builds that one.
LOG=$HOME/$(basename "$SRC")-build-$ARCH.log
export PATH=$HOME/.venv/godot/bin:$PATH
cd "$SRC"

CROSS=()
if [ "$ARCH" = arm64 ]; then
  CROSS=(CC=aarch64-linux-gnu-gcc CXX=aarch64-linux-gnu-g++ LINK=aarch64-linux-gnu-g++)
fi
# disable_path_overrides=no: the spike and test projects are run with --path.
scons platform=linuxbsd arch="$ARCH" target=template_debug optimize="${OPT:-speed}" "${CROSS[@]}" \
  use_sowrap=yes vulkan=yes opengl3=no accesskit=no sdl=no module_mono_enabled=no deprecated=no \
  debug_symbols=no disable_path_overrides=no -j"$(( $(nproc) - 2 ))" > "$LOG" 2>&1 || { tail -40 "$LOG"; exit 1; }
tail -3 "$LOG"
ls -l "bin/godot.linuxbsd.template_debug.$ARCH"
