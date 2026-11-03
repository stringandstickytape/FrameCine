#!/bin/bash
# Sample battery, thermal and clock state on the Steam Frame into a CSV, for worn playback sessions.
# Run on the device, in the background, before starting the player:
#   nohup bash powerlog.sh results/session-$(date +%Y%m%d-%H%M).csv 5 > /dev/null 2>&1 &
# Stop with: pkill -f powerlog.sh
# Columns: time, battery (status, capacity %, voltage V, current A, power W, charge mAh, battery temp C),
#          thermal zones of interest (C), cpu policy clocks (MHz), gpu clock (MHz).
# Throttling shows as clocks dropping while temperatures plateau. Keep the device OFF USB power.

OUT=${1:-powerlog.csv}
INTERVAL=${2:-5}
BAT=$(ls -d /sys/class/power_supply/*bat* 2>/dev/null | head -1)
[ -n "$BAT" ] || { echo "no battery sysfs node"; exit 1; }

# Thermal zones: map name -> path once.
declare -A TZ
for z in /sys/class/thermal/thermal_zone*; do
  n=$(cat "$z/type" 2>/dev/null)
  case "$n" in
    video-thermal|ddr-thermal|gpuss-0-thermal|gpuss-2-thermal|gpuss-4-thermal|cpuss0-thermal|cpu7-top-thermal|cpu2-top-thermal|aoss0-thermal|pm8550-thermal|modem3-thermal|max1720x*)
      TZ[$n]=$z ;;
  esac
done
ZONES=$(printf '%s\n' "${!TZ[@]}" | sort)
CPUPOL=$(ls -d /sys/devices/system/cpu/cpufreq/policy* 2>/dev/null | sort)
GPU=$(ls -d /sys/class/devfreq/*gpu* /sys/class/kgsl/kgsl-3d0 2>/dev/null | head -1)

mkdir -p "$(dirname "$OUT")"
{
  printf 'time,status,capacity_pct,voltage_v,current_a,power_w,charge_mah,bat_temp_c'
  for n in $ZONES; do printf ',%s_c' "${n%-thermal}"; done
  for p in $CPUPOL; do printf ',%s_mhz' "$(basename "$p")"; done
  [ -n "$GPU" ] && printf ',gpu_mhz'
  printf '\n'
} > "$OUT"

rd() { cat "$1" 2>/dev/null || echo 0; }

while true; do
  v=$(rd "$BAT/voltage_now"); i=$(rd "$BAT/current_now")
  # sysfs units: uV, uA (negative = discharging on this battery), uAh, 0.1 C
  line=$(printf '%s,%s,%s,%.3f,%.3f,%.3f,%d,%.1f' "$(date +%H:%M:%S)" "$(rd "$BAT/status")" "$(rd "$BAT/capacity")" \
         "$(echo "$v/1000000" | bc -l)" "$(echo "$i/1000000" | bc -l)" "$(echo "$v*$i/1000000000000" | bc -l)" \
         "$(( $(rd "$BAT/charge_now") / 1000 ))" "$(echo "$(rd "$BAT/temp")/10" | bc -l)")
  for n in $ZONES; do line+=$(printf ',%.1f' "$(echo "$(rd "${TZ[$n]}/temp")/1000" | bc -l)"); done
  for p in $CPUPOL; do line+=",$(( $(rd "$p/scaling_cur_freq") / 1000 ))"; done
  if [ -n "$GPU" ]; then
    g=$(rd "$GPU/cur_freq"); [ "$g" = 0 ] && g=$(rd "$GPU/gpuclk")
    line+=",$(( g / 1000000 ))"
  fi
  echo "$line" >> "$OUT"
  sleep "$INTERVAL"
done
