#!/bin/bash
# Makes the media for tests/test_media_features.gd that the app can open on a desktop: VP9 goes through the engine's
# software decoder there (no V4L2 decoder off the headset), so a VP9 clip remuxed with chapters, a stereo tag and a
# subtitle track exercises chapters (#15), container metadata (#25) and subtitles through the app's real open path.
# Remux only (no encoding), with the remux-only ffmpeg from build/ffmpeg-build.sh tool.
# Needs, in $MEDIA_TESTS (default ~/media-tests): vp9_1080p_10s.webm and cues.srt (spikes/03-player/demux-test/
# make-test-files.sh) and features/meta_sbs_chapters.mkv (its chapters are copied).
# Run in WSL: bash app/tests/make-feature-media.sh
set -euo pipefail
MEDIA=${MEDIA_TESTS:-$HOME/media-tests}
FFMPEG=${FFMPEG:-$HOME/src/ffmpeg-tool/bin/ffmpeg}
OUT="$MEDIA/app-features"
mkdir -p "$OUT"
"$FFMPEG" -hide_banner -loglevel error -y \
	-i "$MEDIA/vp9_1080p_10s.webm" -i "$MEDIA/features/meta_sbs_chapters.mkv" -i "$MEDIA/cues.srt" \
	-map 0:v -map 0:a -map 2:s -map_chapters 1 -c copy \
	-metadata:s:v:0 stereo_mode=left_right -metadata:s:s:0 language=eng -metadata:s:a:0 language=deu \
	"$OUT/vp9_sbs_chapters_subs.mkv"
# Subtitle files next to it (#50): a forced German one (shown with subtitles off, as the audio is German) and French.
cp "$MEDIA/cues.srt" "$OUT/vp9_sbs_chapters_subs.de.forced.srt"
cp "$MEDIA/cues.srt" "$OUT/vp9_sbs_chapters_subs.fr.srt"
echo "Wrote $OUT/vp9_sbs_chapters_subs.mkv and two subtitle files"

# High 10 I_PCM H.264 clips (no encoder needed; the desktop decodes 10-bit H.264 in software): exact letterbox and
# pillarbox bars for test_auto_crop.gd (#42), a 10 fps clip with audio for test_trick_play.gd (#46).
HERE=$(cd "$(dirname "$0")" && pwd)
for m in long pillarbox; do python3 "$HERE/pcm10_h264_avi.py" "$OUT/lb10_$m.avi" $m; done
python3 "$HERE/pcm10_h264_avi.py" "$OUT/trick10.avi" trick
# Two 14 s clips, dark and light, for test_gapless.gd (#44), in a folder of their own (the playlist).
mkdir -p "$OUT/gapless"
python3 "$HERE/pcm10_h264_avi.py" "$OUT/gapless/gap_a.avi" gap_a
python3 "$HERE/pcm10_h264_avi.py" "$OUT/gapless/gap_b.avi" gap_b
echo "Wrote $OUT/lb10_long.avi, lb10_pillarbox.avi and trick10.avi"
# The trick play clip as MPEG-TS, video only, for test_live.gd's udp:// stream.
"$FFMPEG" -hide_banner -loglevel error -y -i "$OUT/trick10.avi" -an -c:v copy -f mpegts "$OUT/trick10.ts"
echo "Wrote $OUT/trick10.ts"
