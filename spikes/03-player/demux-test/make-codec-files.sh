#!/bin/bash
# Makes the test clips of codecs_test.gd in ~/src/codec-tests: one short clip per codec the software path decodes, made
# with the PC's full ffmpeg (a Windows ffmpeg.exe on the PATH, through WSL interop: WSL has no encoding ffmpeg). Each picture is a flat colour
# (0x3060C0) with a white box moving along the top and a test pattern in the bottom-left quarter, so the bottom-right
# quarter has a known colour; the sound is a 440 Hz tone (mono or stereo).
#   wsl -d Ubuntu -- bash spikes/03-player/demux-test/make-codec-files.sh
# FFMPEG=<path to ffmpeg.exe> overrides the encoder. Nothing here is committed; the real files come from the local test library.

set -euo pipefail
FFMPEG=${FFMPEG:-$(command -v ffmpeg.exe || echo ffmpeg.exe)}
OUT=${OUT:-$HOME/src/codec-tests}
mkdir -p "$OUT"
rm -f "$OUT"/*.log
WOUT=$(wslpath -w "$OUT")
VF=
[ -x "$FFMPEG" ] || { echo "No ffmpeg at $FFMPEG (set FFMPEG)"; exit 1; }

# make <name> <WxH> <fps> <seconds> <output args...>
make() {
  local name=$1 size=$2 fps=$3 secs=$4
  shift 4
  local w=${size%x*} h=${size#*x}
  local hw=$(( (w / 2) & ~1 )) hh=$(( (h / 2) & ~1 ))
  local graph="color=c=0x3060C0:s=${size}:r=${fps}:d=${secs}[bg];testsrc2=s=${hw}x${hh}:r=${fps}:d=${secs}[ts];"
  graph+="[bg][ts]overlay=x=0:y=${h}-${hh}[o];[o]drawbox=x='mod(t*160,${w}-64)':y=0:w=64:h=64:color=white:t=fill${VF:+,$VF}[v]"
  printf '%-22s' "$name"
  if "$FFMPEG" -hide_banner -loglevel error -y -filter_complex "$graph" -f lavfi -i "sine=f=440:d=${secs}:sample_rate=48000" \
      -map '[v]' -map 0:a "$@" "$WOUT\\$name" 2>"$OUT/$name.log"; then
    echo "ok $(stat -c %s "$OUT/$name") bytes"
    rm -f "$OUT/$name.log"
  else
    echo "FAILED: $(head -c 300 "$OUT/$name.log")"
  fi
}

S=640x480
# MPEG-4 part 2 as Xvid writes it: B-frames, in AVI (no PTS: the DTS is a frame counter).
make xvid_bframes.avi $S 25 8 -c:v mpeg4 -vtag XVID -bf 2 -g 50 -q:v 3 -c:a libmp3lame -b:a 128k -ac 2
# MS-MPEG4 v3 ("DivX 3"), no B-frames.
make div3.avi $S 25 8 -c:v msmpeg4 -vtag DIV3 -q:v 3 -c:a libmp3lame -b:a 128k -ac 2
# MS-MPEG4 v2 and v1.
make mp42.avi 320x240 25 6 -c:v msmpeg4v2 -q:v 3 -c:a libmp3lame -ac 2
# MPEG-1 with MP2 in MPEG-PS.
make mpeg1.mpg 352x288 25 8 -c:v mpeg1video -bf 2 -b:v 1500k -c:a mp2 -b:a 192k -ac 2 -f mpeg
# DVD: interlaced MPEG-2 (top field first), 16:9 anamorphic (SAR 64:45), AC-3, in a VOB.
make dvd_interlaced.vob 720x576 25 8 -c:v mpeg2video -b:v 5M -maxrate 8M -bufsize 1835k -flags +ilme+ildct -top 1 -aspect 16:9 -bf 2 \
  -c:a ac3 -b:a 192k -ac 2 -f vob
# H.263 with AMR-NB (8 kHz mono) in 3GP.
make h263_amr.3gp 352x288 25 8 -c:v h263 -q:v 4 -c:a libopencore_amrnb -ar 8000 -ac 1 -b:a 12.2k
# Windows Media 7 and 8 with WMA 1 and 2.
make wmv1.wmv 320x240 25 8 -c:v wmv1 -q:v 3 -c:a wmav1 -b:a 96k -ac 2
make wmv2.wmv 320x240 25 8 -c:v wmv2 -q:v 3 -c:a wmav2 -b:a 96k -ac 2
# MPEG-4 part 2 in ASF.
make mpeg4.asf 320x240 25 6 -c:v mpeg4 -vtag M4S2 -q:v 3 -c:a wmav2 -ac 2
# Sorenson H.263 (FLV1) with MP3, and with Nellymoser.
make flv1.flv 320x240 25 8 -c:v flv -q:v 3 -c:a libmp3lame -ar 44100 -ac 2
make flv1_nelly.flv 320x240 25 6 -c:v flv -q:v 3 -c:a nellymoser -ar 22050 -ac 1
# RealVideo 1 and 2 (RealVideo 4 and Cook come from the library's .rm files).
make rv10.rm 320x240 25 6 -c:v rv10 -q:v 3 -c:a ac3 -ac 2
make rv20.rm 320x240 25 6 -c:v rv20 -q:v 3 -c:a ac3 -ac 2
# Theora with Vorbis in Ogg.
make theora.ogv $S 25 8 -c:v libtheora -q:v 7 -c:a libvorbis -ac 2
# VP8 with Opus in WebM.
make vp8.webm $S 25 8 -c:v libvpx -pix_fmt yuv420p -b:v 1500k -c:a libopus -ac 2
# AV1 (dav1d): 1080p 8-bit at 30 fps, and 720p 10-bit.
make av1_1080p.mkv 1920x1080 30 10 -c:v libsvtav1 -preset 10 -crf 35 -g 60 -c:a libopus -ac 2
make av1_720p_10bit.mkv 1280x720 24 6 -c:v libsvtav1 -preset 10 -crf 35 -pix_fmt yuv420p10le -c:a libopus -ac 2
# Motion JPEG 4:2:2 (full range) with IMA ADPCM in AVI.
make mjpeg422.avi $S 25 6 -c:v mjpeg -pix_fmt yuvj422p -q:v 3 -c:a adpcm_ima_wav -ac 2
# Cinepak (decodes to RGB) with mu-law in MOV.
make cinepak.mov 320x240 15 6 -c:v cinepak -c:a pcm_mulaw -ar 8000 -ac 1
# Microsoft Video 1 (RGB555) with 8-bit PCM in AVI.
make msvideo1.avi 320x240 15 6 -c:v msvideo1 -c:a pcm_u8 -ac 1 -ar 22050
# HuffYUV 4:2:2 with PCM in AVI.
make huffyuv422.avi 320x240 25 4 -c:v huffyuv -pix_fmt yuv422p -c:a pcm_s16le -ac 2
# ProRes 422 (10-bit 4:2:2) with 24-bit PCM in MOV.
make prores422.mov 1280x720 25 4 -c:v prores_ks -profile:v 2 -c:a pcm_s24le -ac 2
# FFV1 gray at an odd size, FLAC, in NUT.
make ffv1_gray_odd.nut 351x239 25 4 -c:v ffv1 -pix_fmt gray -c:a flac -ac 2
# PNG with a palette (pal8) in MOV (the palette makes the colour approximate).
make png_pal8.mov 320x240 10 4 -c:v png -pix_fmt pal8 -c:a aac -ac 2
# DV PAL (4:2:0, interlaced, 4:3) with PCM.
make dv_pal.dv 720x576 25 4 -c:v dvvideo -pix_fmt yuv420p -aspect 4:3 -c:a pcm_s16le -ar 48000 -ac 2 -f dv
# MPEG-2 with PCM in MXF.
make mpeg2.mxf 720x576 25 6 -c:v mpeg2video -b:v 8M -c:a pcm_s16le -ar 48000 -ac 2 -f mxf
# Variable frame rate: MPEG-4 part 2 in Matroska with every fifth frame missing (gaps of 80 ms among 40 ms).
VF="select='not(eq(mod(n\,5)\,2))'" make vfr_mpeg4.mkv $S 25 8 -fps_mode vfr -c:v mpeg4 -q:v 3 -c:a libmp3lame -ac 2
ls -l "$OUT"
