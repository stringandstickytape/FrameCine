#!/bin/bash
# Runs the MediaSource test (test.gd) on the host build of the player engine over a set of files, and prints a summary.
#   wsl -d Ubuntu -- bash spikes/03-player/demux-test/run-tests.sh [file [args...]]   (from the repo folder)
# Default: the full-SBS 3D documentary MKV (compared with documentary_sbs.h264), other films of other containers and
# codecs, all from the local test library ($VRVP_LIBRARY, default ~/media-tests/library: links with these names to films
# of your own; missing ones fail to open), and the small files of make-test-files.sh in ~/media-tests (MPEG-TS, made-up
# subtitles) if they exist.
# Logs: /tmp/demux-test-<n>.log. Build the engine first: build/build-player.sh x86_64.

cd "$(dirname "$0")"
GODOT=${GODOT:-$HOME/src/godot-player/bin/godot.linuxbsd.template_debug.x86_64}
M=${VRVP_LIBRARY:-$HOME/media-tests/library}
T=$HOME/media-tests
# One entry per line: path, then extra test.gd arguments.
if [ $# -gt 0 ]; then
  ENTRIES=("$*")
else
  ENTRIES=(
    "$M/Documentary.3D.Full-SBS.mkv"
    "$M/Animated.Feature.2.3D.2019.MULTi.1080p.Half-SBS.mkv"
    "$M/Action.720p.mp4"
    "$M/Animated.1080p.mp4"
    "$M/Animated.HEVC10.mp4"
    "$M/Feature.HEVC10.CRA.mp4"
    "$M/Feature.2160p.HDR.mkv"
    "$M/Animated.Feature.3.3D.Half-SBS.mkv"
    "$M/Comedy.1980.XviD.avi"
  )
  for f in action_90s.ts animated_90s.ts hevc10_90s.ts animated_subs.mkv; do
    [ -f "$T/$f" ] && ENTRIES+=("$T/$f --seek=45")
  done
fi
n=0
for entry in "${ENTRIES[@]}"; do
  n=$((n + 1))
  log=/tmp/demux-test-$n.log
  # Paths may contain spaces but not " --".
  f=${entry%% --*}
  args=()
  [ "$f" != "$entry" ] && read -r -a args <<< "--${entry#* --}"
  case "$f" in
    */Documentary.3D.Full-SBS.mkv) ;; # test.gd compares the default file with documentary_sbs.h264
    *) args=(--file="$f" --raw= "${args[@]}") ;;
  esac
  timeout 600 "$GODOT" --headless --path . -- "${args[@]}" > "$log" 2>&1
  code=$?
  echo "== $(basename "$f") ${args[*]:2}: exit $code"
  grep -E "^  (video|audio|subtitle) \{|^  FAIL|^RESULT|After the seek:|^Audio:|^Subtitle track|leaked|SCRIPT ERROR" "$log" | sed 's/^/   /' | cut -c1-260
done
