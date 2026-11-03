#!/bin/bash
# Run the plain-3D control project under different Turnip debug modes and report whether the quad rendered.
# A screenshot of 8611 bytes is the known "clear colour + 2D square only" image; anything larger has 3D content.
# Usage on the Frame, from ~/spike02:  bash turnip-bisect.sh [binary]   (default ./godot_sym)
BIN=${1:-./godot_sym}
export DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000
cd "$(dirname "$0")" || exit 1

run() {  # run <label> <env assignments...>
  local label=$1; shift
  rm -f "ctrl_$label.png"
  env "$@" timeout 120 "$BIN" --path control --display-driver x11 -- "--screenshot=$PWD/ctrl_$label.png" > "run_ctrl_$label.log" 2>&1
  local rc=$?
  local size; size=$(stat -c %s "ctrl_$label.png" 2>/dev/null || echo 0)
  local verdict="no 3D"; [ "$size" -gt 9000 ] && verdict="*** 3D RENDERED ***"
  printf '%-14s exit=%-3s png=%-7s %s  %s\n' "$label" "$rc" "$size" "$verdict" "$*"
  sleep 1
}

run plain
run sysmem     TU_DEBUG=sysmem
run gmem       TU_DEBUG=gmem
run noubwc     TU_DEBUG=noubwc
run nolrz      TU_DEBUG=nolrz
run forcebin   TU_DEBUG=forcebin
run nobin      TU_DEBUG=nobin
run noconform  TU_DEBUG=noconform
run preload    LD_PRELOAD=/usr/lib/libvulkan_freedreno.so
