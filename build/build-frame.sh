#!/bin/bash
# Cross-compile the engine fork for the Steam Frame (Linux arm64) from WSL.
# No sudo. Run from Windows:
#   wsl -d Ubuntu -- bash build/build-frame.sh [target]
# target: template_debug (default, fast, has asserts/prints) | template_release | editor
#
# Source lives on the WSL native filesystem (much faster than /mnt/c):
#   ~/src/godot-frame   fork stringandstickytape/godot, branch frame/4.7 (from tag 4.7.2-stable)
# Output: ~/src/godot-frame/bin/godot.linuxbsd.<target>.arm64, copied to build/out/.

set -euo pipefail
TARGET=${1:-template_debug}
SRC=$HOME/src/godot-frame
OUT=$(cd "$(dirname "$0")" && pwd)/out
export PATH=$HOME/.venv/godot/bin:$PATH

if [ ! -d "$SRC/.git" ]; then
  mkdir -p "$(dirname "$SRC")"
  git clone --branch 4.7 https://github.com/stringandstickytape/godot.git "$SRC"
  git -C "$SRC" checkout -b frame/4.7 4.7.2-stable
fi

cd "$SRC"
# Godot dlopens X11/Wayland/audio/udev/dbus (use_sowrap=yes) so the cross build needs only
# the toolchain (Ubuntu's aarch64-linux-gnu-gcc; binary needs glibc <= the device's, which
# recent SteamOS satisfies; switch to Godot's buildroot SDK for shipping, see docs/research-godot.md §6).
# OpenXR is module_openxr_enabled (default on). Vulkan only; no GL fallback on the Frame.
# Keep wayland/x11 on: Godot still needs a DisplayServer window under gamescope.
# template_debug: no LTO, fast turnaround for the spikes. Shipping: template_release production=yes (lto=auto).
PROD=no; [ "$TARGET" = template_release ] && PROD=yes
# Spike runs use `--path <project dir>`, which export templates reject unless path overrides are compiled in.
# Spike runs also want symbolised crash backtraces from the template_debug binary.
PATHS=yes; SYMBOLS=no; [ "$TARGET" = template_debug ] && PATHS=no && SYMBOLS=yes
# NOTE (2026-10-31): stock Godot 4.7's SceneState::InstanceData setters (render_forward_mobile.h / render_forward_clustered.h)
# type-pun float[] members through Vector3*/Vector4*/Rect2* stores (strict-aliasing UB). gcc 13 aarch64 at -O2 copies the
# struct into the instance SSBO before those stores land, so every 3D mesh vertex decompresses with garbage and nothing is
# rasterised. Fixed in the fork (element-wise stores); see spikes/02-import/results/FINDINGS.md. Full optimisation is fine
# again. Override with OPT=none for a debuggable build.
OPT=${OPT:-speed}
scons platform=linuxbsd arch=arm64 target="$TARGET" production=$PROD disable_path_overrides=$PATHS optimize=$OPT \
  CC=aarch64-linux-gnu-gcc CXX=aarch64-linux-gnu-g++ LINK=aarch64-linux-gnu-g++ \
  use_sowrap=yes vulkan=yes opengl3=no use_volk=yes accesskit=no sdl=no \
  disable_physics_2d=yes disable_navigation_2d=yes disable_navigation_3d=yes \
  module_mono_enabled=no deprecated=no debug_symbols=$SYMBOLS \
  -j"$(( $(nproc) - 2 ))"

mkdir -p "$OUT"
BIN=$(ls -t bin/godot.linuxbsd."$TARGET".arm64* | head -1)
cp "$BIN" "$OUT/"
file "$OUT/$(basename "$BIN")"
ls -lh "$OUT/$(basename "$BIN")"
