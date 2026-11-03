#!/bin/bash
# Makes small test files for test.gd with the remux-only tool of build/ffmpeg-build.sh tool (no transcoding), from three
# films of your own in the local test library ($VRVP_LIBRARY, default ~/media-tests/library: links with these names):
#   ~/media-tests/action_90s.ts      H.264 + AAC 5.1 in MPEG-TS (from Action.720p.mp4, from 600 s)
#   ~/media-tests/animated_90s.ts    H.264 + AAC in MPEG-TS (from Animated.1080p.mp4, from 600 s)
#   ~/media-tests/hevc10_90s.ts      HEVC 10-bit + AAC 5.1 in MPEG-TS (from Animated.HEVC10.mp4, from 600 s)
#   ~/media-tests/animated_subs.mkv  90 s of Animated.1080p.mp4 (from 600 s) + a SubRip track + an ASS track (made up here)
# From the repo folder: wsl -d Ubuntu -- bash spikes/03-player/demux-test/make-test-files.sh

set -euo pipefail
FF=${FF:-$HOME/src/ffmpeg-tool/bin/ffmpeg}
M=${VRVP_LIBRARY:-$HOME/media-tests/library}
OUT=$HOME/media-tests
mkdir -p "$OUT"
[ -x "$FF" ] || { echo "Build the tool first: build/ffmpeg-build.sh tool"; exit 1; }
ff() { "$FF" -hide_banner -loglevel error -y "$@"; }

# TS from MP4 sources only: Matroska stores no DTS, and a stream copy of B-frame video from MKV to TS gets broken PTS.
ff -ss 600 -i "$M/Action.720p.mp4" -t 90 -map 0:v:0 -map 0:a:0 -c copy "$OUT/action_90s.ts"
ff -ss 600 -i "$M/Animated.1080p.mp4" -t 90 -map 0:v:0 -map 0:a:0 -c copy "$OUT/animated_90s.ts"
ff -ss 600 -i "$M/Animated.HEVC10.mp4" -t 90 -map 0:v:0 -map 0:a:0 -c copy "$OUT/hevc10_90s.ts"

# Subtitles: one cue every 5 s (2 s for the ASS track, with styling and a line break), times relative to the cut.
srt=$OUT/cues.srt
ass=$OUT/cues.ass
: > "$srt"
cat > "$ass" <<'EOF'
[Script Info]
ScriptType: v4.00+
PlayResX: 1920
PlayResY: 1080

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Arial,48,&H00FFFFFF,&H000000FF,&H00000000,&H64000000,0,0,0,0,100,100,0,0,1,2,1,2,40,40,40,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
EOF
for i in $(seq 0 16); do
  s=$((i * 5 + 1))
  printf '%d\n00:%02d:%02d,000 --> 00:%02d:%02d,500\nCue %d at %d s\n\n' $((i + 1)) $((s / 60)) $((s % 60)) $(((s + 2) / 60)) $(((s + 2) % 60)) "$i" "$s" >> "$srt"
  printf 'Dialogue: 0,0:%02d:%02d.00,0:%02d:%02d.00,Default,,0,0,0,,{\\i1}ASS %d{\\i0}\\Nsecond line\n' $((s / 60)) $((s % 60)) $(((s + 2) / 60)) $(((s + 2) % 60)) "$i" >> "$ass"
done
ff -ss 600 -i "$M/Animated.1080p.mp4" -i "$srt" -i "$ass" -t 90 \
  -map 0:v:0 -map 0:a:0 -map 1:0 -map 2:0 -c:v copy -c:a copy -c:s:0 srt -c:s:1 ass \
  -metadata:s:s:0 language=eng -metadata:s:s:0 title="SRT cues" -metadata:s:s:1 language=eng -metadata:s:s:1 title="ASS cues" \
  "$OUT/animated_subs.mkv"
ls -l "$OUT"
