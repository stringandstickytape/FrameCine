#!/bin/bash
# Speech-to-text benchmark on the headset (build/whisper/README.md, "Benchmark"). Runs whisper-cli from the package's
# whisper/ folder on the bundled speech samples with each model, thread count and build (CPU, and Vulkan when
# whisper/vulkan/ is there), and prints one line per run: load time, processing time, real-time factor (processing /
# audio length; below 1 is faster than real time), peak memory, and the text.
# Run from the deployed folder (the package, or ~/spike03 after tools/morning-deploy.sh):
#   bash tools/whisper-bench.sh [--quick] [--models "base.en-q8_0 small.en-q8_0"] [--threads "4 6 8"]
#                               [--builds "cpu vulkan"] [--modes "final partial"] [--samples "jfk-11s radio-29s"]
#                               [--tag TEXT] [--whisper-dir DIR]
# Defaults: every model in whisper/models, threads 4 6 8, both builds, both modes, both samples. --quick: base.en-q8_0
# and small.en-q8_0, 4 and 6 threads, finals only. --tag adds a column (e.g. --tag film while a film plays).
# Modes as the app uses them: final = beam 5 with the vocabulary prompt; partial = greedy, no temperature fallback.
# The table also goes to ~/whisper-bench-<date>-<tag>.tsv. Needs nothing installed; peak memory comes from
# /usr/bin/time -v when it exists, else from polling /proc/<pid>/status (VmHWM).
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
WDIR=""
MODELS=""
THREADS="4 6 8"
BUILDS="cpu vulkan"
MODES="final partial"
SAMPLES="jfk-11s radio-29s"
TAG="-"
while [ $# -gt 0 ]; do
  case "$1" in
    --quick) MODELS="base.en-q8_0 small.en-q8_0"; THREADS="4 6"; MODES="final" ;;
    --models) MODELS=$2; shift ;;
    --threads) THREADS=$2; shift ;;
    --builds) BUILDS=$2; shift ;;
    --modes) MODES=$2; shift ;;
    --samples) SAMPLES=$2; shift ;;
    --tag) TAG=$2; shift ;;
    --whisper-dir) WDIR=$2; shift ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done
if [ -z "$WDIR" ]; then
  for d in "$PWD/whisper" "$HERE/../whisper" "$HERE/whisper"; do
    [ -x "$d/whisper-cli" ] && { WDIR=$(cd "$d" && pwd); break; }
  done
fi
[ -n "$WDIR" ] && [ -x "$WDIR/whisper-cli" ] || { echo "no whisper/whisper-cli here (--whisper-dir DIR)" >&2; exit 1; }
if [ -z "$MODELS" ]; then
  MODELS=$(cd "$WDIR/models" && ls ggml-*.bin 2>/dev/null | sed 's/^ggml-//; s/\.bin$//' | sort | tr '\n' ' ')
fi
[ -n "$MODELS" ] || { echo "no models in $WDIR/models" >&2; exit 1; }

# The app's vocabulary prompt (app/scripts/voice/whisper_backend.gd, from tools/voice.py).
VOCAB="Talking to Claude about the VR video player on the Steam Frame headset: the listener on port 47800, the pane, the dev link, SMB, HEVC, HDR, pairing."
TIMEV=""
[ -x /usr/bin/time ] && /usr/bin/time -v true > /dev/null 2>&1 && TIMEV=/usr/bin/time
OUT=$HOME/whisper-bench-$(date +%Y%m%d-%H%M%S)-${TAG//[^A-Za-z0-9_-]/_}.tsv
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "# whisper bench $(date -Is) on $(uname -nrm), $(nproc) CPUs, load $(cut -d' ' -f1-3 /proc/loadavg), tag $TAG"
echo "# $WDIR: $(head -1 "$WDIR/BUILDINFO" 2>/dev/null || echo '?')"
for c in /sys/devices/system/cpu/cpufreq/policy*; do
  [ -r "$c/scaling_governor" ] && echo "# $(basename "$c"): cpus $(cat "$c/affected_cpus"), $(cat "$c/scaling_governor"), max $(( $(cat "$c/scaling_max_freq") / 1000 )) MHz"
done
printf 'tag\tbuild\tmodel\tthreads\tsample\tmode\taudio_s\tload_ms\tproc_ms\trtf\tpeak_mb\ttext\n' | tee "$OUT"

# Peak resident memory (MB) of a command, its stdout to $TMP/out and stderr to $TMP/err.
run_measured() {
  if [ -n "$TIMEV" ]; then
    "$TIMEV" -v -o "$TMP/time" "$@" > "$TMP/out" 2> "$TMP/err"
    local rc=$?
    PEAK=$(awk -F': ' '/Maximum resident set size/ {printf "%d", $2 / 1024}' "$TMP/time")
    return $rc
  fi
  "$@" > "$TMP/out" 2> "$TMP/err" &
  local pid=$! hwm=0 v
  while kill -0 "$pid" 2>/dev/null; do
    v=$(awk '/^VmHWM:/ {print $2}' "/proc/$pid/status" 2>/dev/null)
    [ -n "$v" ] && [ "$v" -gt "$hwm" ] && hwm=$v
    sleep 0.05
  done
  wait "$pid"
  local rc=$?
  PEAK=$(( hwm / 1024 ))
  return $rc
}

for build in $BUILDS; do
  bin=$WDIR/whisper-cli
  if [ "$build" = vulkan ]; then
    bin=$WDIR/vulkan/whisper-cli
    [ -x "$bin" ] || { echo "# no vulkan build ($bin); skipped"; continue; }
  fi
  for model in $MODELS; do
    mfile=$WDIR/models/ggml-$model.bin
    [ -f "$mfile" ] || { echo "# no model $mfile; skipped"; continue; }
    for t in $THREADS; do
      for sample in $SAMPLES; do
        wav=$WDIR/samples/$sample.wav
        [ -f "$wav" ] || { echo "# no sample $wav; skipped"; continue; }
        audio=$(awk -v s="$(stat -c %s "$wav")" 'BEGIN {printf "%.1f", (s - 44) / 32000}')
        for mode in $MODES; do
          if [ "$mode" = final ]; then
            opts=(-bs 5 -bo 5 --prompt "$VOCAB")
          else
            opts=(-bs 1 -nf --prompt "$VOCAB")
          fi
          if ! run_measured "$bin" -m "$mfile" -f "$wav" -t "$t" -l en -nt "${opts[@]}"; then
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\tFAILED: %s\n' "$TAG" "$build" "$model" "$t" "$sample" "$mode" "$audio" \
              "$(tail -1 "$TMP/err")" | tee -a "$OUT"
            continue
          fi
          load=$(awk '/load time =/ {printf "%d", $(NF-1)}' "$TMP/err")
          total=$(awk '/total time =/ {printf "%d", $(NF-1)}' "$TMP/err")
          proc=$(( total - load ))
          rtf=$(awk -v p="$proc" -v a="$audio" 'BEGIN {printf "%.3f", p / 1000 / a}')
          text=$(tr '\n' ' ' < "$TMP/out" | sed 's/  */ /g; s/^ //; s/ $//')
          printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$TAG" "$build" "$model" "$t" "$sample" "$mode" \
            "$audio" "$load" "$proc" "$rtf" "$PEAK" "$text" | tee -a "$OUT"
          [ "$build" = vulkan ] && [ -z "${VKDEV:-}" ] && VKDEV=$(grep -m1 -o 'ggml_vulkan: 0 = .*' "$TMP/err") &&
            echo "# $VKDEV"
        done
      done
    done
  done
done
echo "# saved $OUT"
