#!/bin/bash
# Makes the clips of tests/test_still_seek.gd. Needs an ffmpeg with libx264, aac, truehd and libmp3lame: the remux-only one
# of build/ffmpeg-build.sh won't do, the one on the Windows side will. Run it in Git Bash, then copy the clips to WSL:
#   bash app/tests/make-still-media.sh out-dir
#   wsl -e bash -lc 'mkdir -p ~/media-tests/still && cp /mnt/c/.../out-dir/* ~/media-tests/still/'
#
# To test the headset's feed on a desktop (in WSL, from the app's folder):
#   gcc -shared -fPIC -O1 -o fake_v4l2.so app/tests/fake_v4l2.c -ldl -lpthread
#   git -C ~/src/<fork worktree> apply <this repo>/app/tests/fake-import.patch      and build x86_64: test builds only
#   HWVIDEO_TEST_FAKE_IMPORT=1 FAKE_V4L2_DELAY=4 LD_PRELOAD=$PWD/fake_v4l2.so <that godot> --xr-mode off --path app \
#     --script res://tests/test_still_seek.gd
set -euo pipefail
OUT=${1:?output directory}
FFMPEG=${FFMPEG:-ffmpeg}
mkdir -p "$OUT"
cd "$OUT"
ff() { "$FFMPEG" -hide_banner -loglevel error -y "$@"; }
GOP10="keyint=10:min-keyint=10:scenecut=0:bframes=3:b-pyramid=normal:b-adapt=0:ref=4"
GOP4="keyint=4:min-keyint=4:scenecut=0:bframes=3:b-pyramid=normal:b-adapt=0"
X264=(-c:v libx264 -preset veryfast -crf 32 -pix_fmt yuv420p)

# 1 fps with B-frames (packets 0, 4, 2, 1, 3...), a keyframe every 10 s, AAC.
ff -f lavfi -i "testsrc2=size=1920x1080:rate=1" -f lavfi -i "sine=frequency=440:sample_rate=48000" -t 600 \
	-map 0:v -map 1:a "${X264[@]}" -x264-params "$GOP10" -c:a aac -b:a 64k still_1fps.mkv
# 1200 audio packets for each video packet's second: the compressed audio queue is full after 7 s of media.
ff -f lavfi -i "testsrc2=size=1280x720:rate=1" -f lavfi -i "sine=frequency=660:sample_rate=48000" -t 120 \
	-map 0:v -map 1:a "${X264[@]}" -x264-params "$GOP10" -strict -2 -c:a truehd -ac 2 still_truehd.mkv
# A film for comparison.
ff -f lavfi -i "testsrc2=size=1280x720:rate=24" -f lavfi -i "sine=frequency=880:sample_rate=48000" -t 60 \
	-map 0:v -map 1:a -c:v libx264 -preset veryfast -crf 30 -pix_fmt yuv420p -x264-params "keyint=48:bframes=3:b-pyramid=normal" \
	-c:a aac -b:a 96k normal_24fps.mkv
# As the muxer interleaves them when the streams end far apart or are this sparse: all the audio before the video, and
# the video in lumps.
ff -f lavfi -t 20 -i "testsrc2=size=1920x1080:rate=1" -f lavfi -t 240 -i "sine=frequency=330:sample_rate=48000" \
	-map 0:v -map 1:a "${X264[@]}" -x264-params "$GOP10" -c:a aac -b:a 64k audio_first.mkv
ff -f lavfi -i "testsrc2=size=1280x720:rate=0.1" -f lavfi -i "sine=frequency=550:sample_rate=48000" -t 600 \
	-map 0:v -map 1:a "${X264[@]}" -x264-params "$GOP4" -c:a aac -b:a 64k chunky_0p1fps.mkv
# Well interleaved (-max_interleave_delta 0): a video track that ends at 20 s of 240, and a picture every 10 s.
ff -f lavfi -t 240 -i "sine=frequency=330:sample_rate=48000" -c:a aac -b:a 64k a240.m4a
ff -f lavfi -t 600 -i "sine=frequency=550:sample_rate=48000" -c:a aac -b:a 64k a600.m4a
ff -f lavfi -t 20 -i "testsrc2=size=1920x1080:rate=1" "${X264[@]}" -x264-params "$GOP10" v20.mkv
ff -f lavfi -t 600 -i "testsrc2=size=1280x720:rate=0.1" "${X264[@]}" -x264-params "$GOP4" v60.mkv
ff -i v20.mkv -i a240.m4a -map 0:v -map 1:a -c copy -max_interleave_delta 0 video_ends_early.mkv
ff -i v60.mkv -i a600.m4a -map 0:v -map 1:a -c copy -max_interleave_delta 0 slideshow_0p1fps.mkv
rm a240.m4a a600.m4a v20.mkv v60.mkv
# An MP3 with a cover.
ff -f lavfi -i "color=c=red:s=300x300:d=1" -frames:v 1 cover.jpg
ff -f lavfi -i "sine=frequency=440:sample_rate=44100" -i cover.jpg -t 120 -map 0:a -map 1:v -c:a libmp3lame -q:a 6 -c:v copy \
	-id3v2_version 3 -metadata:s:v title="Album cover" -disposition:v attached_pic cover.mp3
rm cover.jpg
