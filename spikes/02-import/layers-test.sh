#!/bin/bash
# Is one of the Vulkan layers injected on SteamOS (fossilize, MangoHud, gamescope WSI, vram_report_limit)
# behind the missing 3D geometry? Also capture the *presented* frame with the LunarG screenshot layer,
# independently of Godot's own viewport readback.
# Usage on the Frame, from ~/spike02:  bash layers-test.sh [binary]
BIN=${1:-./godot_baseline}
export DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 LD_PRELOAD=/usr/lib/libvulkan_freedreno.so
cd "$(dirname "$0")" || exit 1

echo "-- layer names"
grep -h -o -E '"name" *: *"[^"]+"' /usr/share/vulkan/implicit_layer.d/*.json /usr/share/vulkan/explicit_layer.d/VkLayer_screenshot.json

run() {  # run <label> <env...>
  local label=$1; shift
  rm -f ctrl_x.png
  env "$@" timeout 120 "$BIN" --path control --display-driver x11 -- "--screenshot=$PWD/ctrl_x.png" > "run_ctrl_$label.log" 2>&1
  local rc=$? size; size=$(stat -c %s ctrl_x.png 2>/dev/null || echo 0)
  local verdict="no 3D"; [ "$size" -gt 9000 ] && verdict="*** 3D RENDERED ***"
  printf '%-16s exit=%-3s png=%-7s %s  %s\n' "$label" "$rc" "$size" "$verdict" "$*"
  cp -f ctrl_x.png "ctrl_x_$label.png" 2>/dev/null
}

run noimplicit   VK_LOADER_LAYERS_DISABLE='~implicit~'
run nofossilize  VK_LOADER_LAYERS_DISABLE='VK_LAYER_fossilize,VK_LAYER_FOSSILIZE'
run nomango      VK_LOADER_LAYERS_DISABLE='VK_LAYER_MANGOHUD_overlay*'
run novram       VK_LOADER_LAYERS_DISABLE='VK_LAYER_MESA_vram_report_limit'
run nogswsi      VK_LOADER_LAYERS_DISABLE='VK_LAYER_FROG_gamescope_wsi*'

echo "-- presented frame via LunarG screenshot layer (frame 100)"
rm -f 100.ppm
VK_INSTANCE_LAYERS=VK_LAYER_LUNARG_screenshot VK_SCREENSHOT_FRAMES=100 timeout 120 "$BIN" --path control --display-driver x11 > run_ctrl_sslayer.log 2>&1
echo "exit=$?"; ls -l 100.ppm 2>&1
grep -i -c screenshot run_ctrl_sslayer.log
