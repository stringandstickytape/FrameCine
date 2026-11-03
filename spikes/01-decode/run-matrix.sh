#!/bin/bash
# Run a set of spike-01 decode tests on the Frame, one decoder session at a time (firmware rules).
# Usage on the device, from ~/spike01:   bash run-matrix.sh <set>
#   set = ceiling   rows 2-6: 4K Q08C, 8K NV12 (+dump), 8K Q08C, 8192x4096 NV12/Q08C
#   set = extra     rows 7-9, 11: two sessions, Main10 default + forced NV12, resolution change
#   set = dmabuf    rows 12-13: CAPTURE with imported dmabufs (system heap, DRM dumb)
# Per-test full logs go to results/<name>.txt; a summary is printed for each.
set -u
cd "$(dirname "$0")"
mkdir -p results

run() {  # run <name> <args...>
  local name=$1; shift
  echo "######## $name: v4l2dec $*"
  ./v4l2dec "$@" > "results/$name.txt" 2>&1
  echo "exit=$?"
  grep -E '^  (result|OUTPUT|CAPTURE|    plane 0|visible|VIDIOC_EXPBUF|SOURCE_CHANGE|frames|decode fps|latency|ioctl errors)|S_FMT CAPTURE|kept|driver keeps|hang|timeout|ERROR|rror' "results/$name.txt" | head -30
  sleep 2   # let the firmware settle between sessions
}

case "${1:-ceiling}" in
  ceiling)
    run 4k_q08c        streams/hevc8_3840x2160_60.h265 -C Q08C
    run 8k_nv12        streams/hevc8_7680x3840_60.h265 -C NV12 -w 30
    run 8k_q08c        streams/hevc8_7680x3840_60.h265 -C Q08C
    run 8192_nv12      streams/hevc8_8192x4096_60.h265 -C NV12
    run 8192_q08c      streams/hevc8_8192x4096_60.h265 -C Q08C
    ;;
  extra)
    run 4k_2sessions   streams/hevc8_3840x2160_60.h265 -C NV12 -s 2
    run main10_default streams/hevc10_7680x3840_60.h265 -n 120
    run main10_nv12    streams/hevc10_7680x3840_60.h265 -C NV12 -n 120 -w 30
    run reschange      streams/reschange.h265 -C NV12 -i 1
    ;;
  dmabuf)
    run 4k_dmabuf_heap streams/hevc8_3840x2160_60.h265 -C NV12 --capture-mem dmabuf
    run 4k_dmabuf_dumb streams/hevc8_3840x2160_60.h265 -C NV12 --capture-mem dmabuf --dmabuf-src dumb
    ;;
  reschange)   # fork admission check (mbpf x queued rate x sessions <= 7833600): rate reset vs session restart
    for v in "default:" "rate0:--reconfig-rate 0" "norestart:--reconfig-rate 0 --no-restart" "rt:--realtime --fps 60"; do
      name=${v%%:*}; flags=${v#*:}
      echo "######## reschange_$name: v4l2dec streams/reschange.h265 -C NV12 -i 1 $flags"
      # shellcheck disable=SC2086
      ./v4l2dec streams/reschange.h265 -C NV12 -i 1 $flags > "results/reschange_$name.txt" 2>&1
      echo "exit=$?"
      grep -E -e 'rate reset' -e 'reconfig path' -e ENOMEM -e 'resolution change' -e '^  result' -e '^  frames' -e 'admission' "results/reschange_$name.txt" | head -10
      sleep 2
    done
    ;;
  dumptwice)   # is a dequeued 8K buffer stable while we hold it?
    run 8k_dumptwice streams/hevc8_7680x3840_60.h265 -C NV12 -w 30 --dump-twice 100
    grep -E -i -e md5 -e identical -e DIFFERENT results/8k_dumptwice.txt | head -6
    ;;
  *) echo "unknown set $1"; exit 1 ;;
esac
