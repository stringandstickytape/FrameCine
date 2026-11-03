#!/bin/bash
# Sample the busiest threads on the Steam Frame during a playback session, to see what keeps the CPU clusters busy.
# Run on the device, in the background, next to powerlog.sh:
#   nohup bash threadlog.sh results/threads-$(date +%Y%m%d-%H%M).log 10 > /dev/null 2>&1 &
# Each sample: timestamp, load average, per-CPU busy % since the previous sample, then the top 20 threads by %CPU
# over a 2 s window (tid, %CPU, process, thread name).

OUT=${1:-threadlog.log}
INTERVAL=${2:-10}
mkdir -p "$(dirname "$OUT")"

declare -A PREV_BUSY PREV_TOTAL
CPU_LINE=""
# Sets CPU_LINE (not echoed: a $(...) subshell would lose the PREV_* state between samples).
cpu_usage() {
  local cpu user nice sys idle iow irq sirq steal busy total
  CPU_LINE=""
  while read -r cpu user nice sys idle iow irq sirq steal _; do
    [[ $cpu == cpu[0-9]* ]] || continue
    busy=$((user + nice + sys + irq + sirq + steal)); total=$((busy + idle + iow))
    if [ -n "${PREV_TOTAL[$cpu]}" ]; then
      local dt=$((total - PREV_TOTAL[$cpu])) db=$((busy - PREV_BUSY[$cpu]))
      [ "$dt" -gt 0 ] && CPU_LINE+="$cpu=$((100 * db / dt))% "
    fi
    PREV_BUSY[$cpu]=$busy; PREV_TOTAL[$cpu]=$total
  done < /proc/stat
}

top_threads() {
  # Second frame of top -H (the first frame of a batch run is not a real measurement).
  top -b -H -n 2 -d 2 -o %CPU -w 200 2>/dev/null \
    | awk '/^ *PID/ {f=1; n=0; buf=""; next} f && NF {buf = buf $1 " " $9 " " $12 "\n"; if (++n >= 20) f=0} END {printf "%s", buf}' \
    | while read -r tid pcpu tname; do
        tgid=$(awk '/^Tgid/ {print $2}' "/proc/$tid/status" 2>/dev/null)
        pname=$(cat "/proc/${tgid:-$tid}/comm" 2>/dev/null)
        printf '%7s %6s %-20s %s\n' "$tid" "$pcpu" "${pname:-?}" "$tname"
      done
}

cpu_usage
while true; do
  sleep "$INTERVAL"
  cpu_usage
  {
    echo "=== $(date +%H:%M:%S) load $(cut -d' ' -f1-3 /proc/loadavg)"
    echo "cpu: $CPU_LINE"
    top_threads
  } >> "$OUT"
done
