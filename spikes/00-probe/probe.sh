#!/bin/bash
# Steam Frame device survey. Read-only; no sudo prompts; tolerates missing tools.
#
# Run from the dev machine with run-probe.ps1 (copies this dir to the Frame, runs it, saves results).
# Expects v4l2_enum.py next to it; PROBE_DIR may be overridden.
#
# Answers, in one pass:
#   - which video decoder driver is loaded (venus / iris / none) and what V4L2 formats it exposes
#   - which Vulkan extensions Turnip exposes (video decode, dmabuf import, ycbcr, VRS/FDM, external sync)
#   - which OpenXR runtime is active and what SteamVR logged about extensions / refresh rates
#   - display modes, backlight, battery and thermal sysfs paths
#   - which media libraries and dev tools are already on the device

set +e
export LC_ALL=C
PROBE_DIR=${PROBE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}

section() { printf '\n=== %s ===\n' "$1"; }
have()    { command -v "$1" >/dev/null 2>&1; }
try()     { echo "\$ $*"; "$@" 2>&1; }
catf()    { for f in "$@"; do [ -r "$f" ] && printf '%s = %s\n' "$f" "$(tr '\n' ' ' < "$f")"; done; }

section "system"
try uname -a
try cat /etc/os-release
grep -m1 -iE 'model name|hardware' /proc/cpuinfo
echo "cpus: $(nproc)"
try free -h
try cat /proc/device-tree/model
try cat /proc/device-tree/compatible
echo

section "video decoder: kernel"
# Expected (per SteamOS issue reports): Valve's fork of Qualcomm's iris driver, kernel 6.18
# "linux-618-deckard" (7.2 preview adds P010/AV1), node /dev/video-dec0, firmware vpu33_4v.mbn.
echo "kernel: $(uname -r)"
lsmod 2>/dev/null | grep -iE 'venus|iris|v4l|videobuf|videodev|msm|qcom' || echo "(no matching modules in lsmod; may be built-in)"
try ls -l /dev/video* /dev/media* /dev/dri/
id
echo "groups owning video nodes: $(stat -c '%G' /dev/video* 2>/dev/null | sort -u | tr '\n' ' ')"
for d in /sys/class/video4linux/*; do
  [ -e "$d" ] || continue
  printf '%s: name=%s dev=%s driver=%s\n' "$(basename "$d")" "$(cat "$d/name" 2>/dev/null)" "$(cat "$d/dev" 2>/dev/null)" "$(basename "$(readlink -f "$d/device/driver")" 2>/dev/null)"
done
grep -rl . /sys/bus/platform/drivers/*venus* /sys/bus/platform/drivers/*iris* /sys/bus/platform/drivers/*vidc* 2>/dev/null | head

section "video decoder: v4l2 formats, sizes, controls (python ioctl prober)"
if have python3 && [ -r "$PROBE_DIR/v4l2_enum.py" ]; then
  python3 "$PROBE_DIR/v4l2_enum.py" 2>&1
else
  echo "python3 or $PROBE_DIR/v4l2_enum.py missing"
fi

section "video decoder: v4l2-ctl (if present)"
if have v4l2-ctl; then
  try v4l2-ctl --list-devices
  for d in /dev/video*; do
    echo "---- $d"
    v4l2-ctl -d "$d" --info 2>&1
    v4l2-ctl -d "$d" --list-formats 2>&1
    v4l2-ctl -d "$d" --list-formats-out 2>&1
    v4l2-ctl -d "$d" --list-formats-ext 2>&1 | head -60
  done
else
  echo "v4l2-ctl missing (v4l-utils). Formats will need a small C/Python ioctl probe."
fi

section "video decoder: firmware"
find /lib/firmware /usr/lib/firmware \( -iname '*venus*' -o -iname '*vpu*' -o -iname '*iris*' -o -iname '*vidc*' \) 2>/dev/null
echo "firmware dir listing (qcom):"; ls /lib/firmware/qcom/ 2>/dev/null | head -40

section "dmesg (video/gpu/firmware) - may be restricted"
dmesg 2>&1 | grep -iE 'venus|iris|vidc|v4l|msm_drm|adreno|firmware' | tail -60

section "gpu / mesa / vulkan"
try ls /usr/share/vulkan/icd.d/
cat /usr/share/vulkan/icd.d/*.json 2>/dev/null
for p in mesa vulkan-freedreno vulkan-icd-loader vulkan-tools mesa-utils libva libva-utils; do pacman -Q "$p" 2>/dev/null; done
if have vulkaninfo; then
  try vulkaninfo --summary
  echo "---- extensions of interest"
  vulkaninfo 2>/dev/null | grep -oE 'VK_(KHR_video[a-z0-9_]*|EXT_external_memory_dma_buf|EXT_image_drm_format_modifier|KHR_sampler_ycbcr_conversion|KHR_fragment_shading_rate|EXT_fragment_density_map[a-z0-9_]*|KHR_external_semaphore_fd|KHR_external_memory_fd|KHR_external_fence_fd|EXT_queue_family_foreign|EXT_external_memory_host|KHR_timeline_semaphore|EXT_physical_device_drm|EXT_multi_draw|KHR_multiview)' | sort -u
  echo "---- video codec operations"
  vulkaninfo 2>/dev/null | grep -iE 'videoCodecOperation|VK_VIDEO_CODEC' | sort -u
  echo "---- queue families"
  vulkaninfo 2>/dev/null | grep -A4 -E 'queueFamilies|VkQueueFamilyProperties' | head -60
  echo "---- drm format modifiers for NV12 / P010 (if listed)"
  vulkaninfo 2>/dev/null | grep -B2 -A12 -E 'FORMAT_G8_B8R8_2PLANE_420_UNORM|FORMAT_G10X6_B10X6R10X6_2PLANE_420' | head -80
else
  echo "vulkaninfo missing"
fi
have glxinfo && try glxinfo -B
have eglinfo && eglinfo 2>&1 | head -40

section "iris driver service (its existence suggests firmware crashes are expected)"
systemctl status iris-driver-rebind.service --no-pager 2>&1 | head -12
systemctl cat iris-driver-rebind.service --no-pager 2>&1 | head -30

section "openxr"
try ls -l /etc/xdg/openxr/1/ "$HOME/.config/openxr/1/" /usr/share/openxr/1/
for f in /etc/xdg/openxr/1/active_runtime*.json "$HOME"/.config/openxr/1/active_runtime*.json /usr/share/openxr/1/*.json; do [ -r "$f" ] && { echo "---- $f"; cat "$f"; echo; }; done
echo "---- SteamVR perf logs / CSVs (spike 04 instrumentation)"
ls -la "$HOME/.local/share/Steam/logs/" 2>/dev/null | grep -iE 'perf|csv|compositor' | head -20
try ls "$HOME/.steam/steam/steamapps/common/"
SVR="$HOME/.steam/steam/steamapps/common/SteamVR"
[ -d "$SVR" ] && { echo "---- SteamVR dir"; ls "$SVR"; ls "$SVR/bin" 2>/dev/null; file "$SVR"/bin/*/vrcompositor* 2>/dev/null; }
echo "---- steamvr.vrsettings"
cat "$HOME/.steam/steam/config/steamvr.vrsettings" 2>/dev/null
echo "---- vrpreferences.json (refresh rate is set here on the Frame, not via OpenXR)"
for f in $(find "$HOME/.steam" "$HOME/.config" "$HOME/.local" /etc -name 'vrpreferences.json' 2>/dev/null); do echo "-- $f"; cat "$f"; echo; done
echo "---- SteamVR logs: extensions / refresh / layers (last 80 matching lines)"
for L in "$HOME"/.steam/steam/logs/vrserver.txt "$HOME"/.steam/steam/logs/vrcompositor.txt "$HOME"/.steam/steam/logs/vrclient_*.txt; do
  [ -r "$L" ] || continue
  echo "-- $L"
  grep -iE 'XR_[A-Z]+_[a-z_0-9]+|refresh|composition layer|equirect|cylinder|foveat|passthrough' "$L" | sort -u | tail -80
done

section "display"
for c in /sys/class/drm/card*-*; do
  [ -e "$c" ] || continue
  printf '%s: status=%s enabled=%s\n' "$(basename "$c")" "$(cat "$c/status" 2>/dev/null)" "$(cat "$c/enabled" 2>/dev/null)"
  cat "$c/modes" 2>/dev/null | sed 's/^/   mode: /'
done
for b in /sys/class/backlight/*; do [ -e "$b" ] && catf "$b/brightness" "$b/max_brightness" "$b/actual_brightness"; done
have wlr-randr && try wlr-randr
have xrandr && xrandr 2>&1 | head -20

section "power / battery"
for p in /sys/class/power_supply/*; do
  [ -e "$p" ] || continue
  echo "-- $p"
  catf "$p/type" "$p/status" "$p/capacity" "$p/voltage_now" "$p/current_now" "$p/power_now" "$p/charge_now" "$p/charge_full" "$p/energy_now" "$p/energy_full" "$p/temp"
done
echo "-- thermal zones"
for t in /sys/class/thermal/thermal_zone*; do [ -e "$t" ] && printf '%s: %s %s\n' "$(basename "$t")" "$(cat "$t/type" 2>/dev/null)" "$(cat "$t/temp" 2>/dev/null)"; done
echo "-- cpufreq"
for pol in /sys/devices/system/cpu/cpufreq/policy*; do
  [ -e "$pol" ] || continue
  printf '%s cpus=%s gov=%s cur=%s min=%s max=%s\n' "$(basename "$pol")" "$(cat "$pol/affected_cpus" 2>/dev/null)" "$(cat "$pol/scaling_governor" 2>/dev/null)" "$(cat "$pol/scaling_cur_freq" 2>/dev/null)" "$(cat "$pol/cpuinfo_min_freq" 2>/dev/null)" "$(cat "$pol/cpuinfo_max_freq" 2>/dev/null)"
done
echo "-- gpu devfreq"
for g in /sys/class/devfreq/*; do [ -e "$g" ] && printf '%s: cur=%s min=%s max=%s gov=%s\n' "$(basename "$g")" "$(cat "$g/cur_freq" 2>/dev/null)" "$(cat "$g/min_freq" 2>/dev/null)" "$(cat "$g/max_freq" 2>/dev/null)" "$(cat "$g/governor" 2>/dev/null)"; done

section "media libraries on device"
pacman -Q 2>/dev/null | grep -iE 'ffmpeg|gstreamer|gst-|libva|v4l|libass|pipewire|openxr|libdrm'
if have ffmpeg; then
  ffmpeg -version 2>&1 | head -2
  try ffmpeg -hide_banner -hwaccels
  ffmpeg -hide_banner -decoders 2>/dev/null | grep -iE 'v4l2|vulkan|hevc|h264|av1|vp9'
fi
have gst-inspect-1.0 && gst-inspect-1.0 2>/dev/null | grep -iE 'v4l2|vulkan|va|codec|dec' | head -60
ls /usr/lib/libavcodec* /usr/lib/libgst* /usr/lib/libva* /usr/lib/libv4l* 2>/dev/null
ls /usr/lib/gstreamer-1.0/ 2>/dev/null | head -80

section "audio"
have pw-cli && try pw-cli info 0 | head -20
have pactl && pactl list short sinks 2>&1

section "dev tooling on device"
for t in gcc clang cmake make python3 podman distrobox flatpak docker perf perfetto renderdoccmd mangohud; do
  if have "$t"; then echo "$t: $(command -v "$t")"; else echo "$t: (missing)"; fi
done
have flatpak && flatpak list 2>&1 | head -20
echo "-- Steam Linux Runtime dirs"
ls "$HOME/.steam/steam/steamapps/common/" 2>/dev/null | grep -iE 'runtime|sniper|soldier|steamlinux'
echo "-- rootfs writable?"
touch /usr/.probe_rw 2>/dev/null && { echo "yes (unexpected)"; rm -f /usr/.probe_rw; } || echo "no (immutable, as expected)"
steamos-readonly status 2>&1

section "sudo / storage / network"
if sudo -n true 2>/dev/null; then echo "sudo: passwordless"; else echo "sudo: needs password (dmesg/v4l2 raw access may be limited)"; fi
try df -h / /home
lsblk 2>&1 | head -30
ip -brief addr 2>&1
iw dev 2>/dev/null | grep -E 'Interface|channel|txpower'

section "done"
date
