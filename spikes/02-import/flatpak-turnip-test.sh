#!/bin/bash
# Does stock Mesa Turnip (from the Flatpak GL runtime on the device) draw the 3D quad where Valve's
# Mesa 26.3-devel build does not? Points the Vulkan loader at the Flatpak ICD via VK_DRIVER_FILES.
# Usage on the Frame, from ~/spike02:  bash flatpak-turnip-test.sh [binary]
BIN=${1:-./godot_baseline}
export DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000
cd "$(dirname "$0")" || exit 1

i=0
for lib in $(find /var/lib/flatpak/runtime/org.freedesktop.Platform.GL.default -name libvulkan_freedreno.so 2>/dev/null | sort); do
  i=$((i+1))
  libdir=$(dirname "$lib")
  json="$PWD/fp_icd_$i.json"
  printf '{\n  "file_format_version": "1.0.1",\n  "ICD": { "library_path": "%s", "api_version": "1.4.354", "library_arch": "64" }\n}\n' "$lib" > "$json"
  echo "== ICD $i: $lib"
  # Can the host even load it?
  LD_LIBRARY_PATH="$libdir" ldd "$lib" 2>&1 | grep -E -i -e "not found" -e "GLIBC" | head -3
  rm -f ctrl_x.png
  VK_DRIVER_FILES="$json" LD_LIBRARY_PATH="$libdir" LD_PRELOAD="$lib" timeout 120 "$BIN" --path control --display-driver x11 --verbose -- "--screenshot=$PWD/ctrl_x.png" > "run_ctrl_fpturnip_$i.log" 2>&1
  rc=$?; size=$(stat -c %s ctrl_x.png 2>/dev/null || echo 0)
  verdict="no 3D"; [ "$size" -gt 9000 ] && verdict="*** 3D RENDERED ***"
  printf '   exit=%-3s png=%-7s %s\n' "$rc" "$size" "$verdict"
  grep -E -e "driverInfo" -e "Mesa" -e "Using Device" -e "ERROR" -e "error" "run_ctrl_fpturnip_$i.log" | grep -v -i -e "script cache" | head -4
  cp -f ctrl_x.png "ctrl_x_fpturnip_$i.png" 2>/dev/null
done
[ "$i" = 0 ] && echo "no flatpak turnip found"
