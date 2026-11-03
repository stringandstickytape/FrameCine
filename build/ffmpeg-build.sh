#!/bin/bash
# Builds the static FFmpeg of the engine fork's hwvideo module (MediaSource, SoftwareVideoDecoder): every native decoder
# (video, audio, subtitles), every file demuxer, all parsers and bitstream filters, libswscale and libswresample, and
# dav1d for AV1. LGPL configuration: no --enable-gpl, no --enable-nonfree, and no external library but dav1d (BSD-2).
# Run from Windows (no sudo needed):
#   wsl -d Ubuntu -- bash build/ffmpeg-build.sh [aarch64|x86_64|all|tool]
# Source:   ~/src/ffmpeg (cloned once, tag $FFMPEG_TAG; not committed anywhere).
# Prefixes: ~/src/ffmpeg-aarch64-all (Steam Frame), ~/src/ffmpeg-x86_64-all (WSL tests). modules/hwvideo/SCsub of the
#           fork branch frame/codecs picks one by arch. PROFILE=minimal builds the earlier H.264/HEVC/VP9-only set into
#           ~/src/ffmpeg-aarch64 and ~/src/ffmpeg-x86_64 (what the branch frame/player links).
# dav1d:    build/dav1d-build.sh first (~/src/dav1d-aarch64, ~/src/dav1d-x86_64).
# tool:     ~/src/ffmpeg-tool/bin/ffmpeg, an x86_64 command-line ffmpeg that can only remux (no codecs), to make test files
#           (for example MPEG-TS from an MP4: ffmpeg -i in.mp4 -t 60 -c copy out.ts). Not part of the player.
# Each is built out of tree in ~/src/ffmpeg-build-<name>[-all]. About 1 min each on 30 cores (the full profile: about 3).
# The prefix gets build-config.txt: the licence switches and how many decoders, demuxers, parsers and filters it has.
#
# zlib (compressed Matroska tracks, compressed MP4 headers, PNG, some old codecs) comes from the engine: FFmpeg is compiled
# against the zlib headers bundled with Godot ($GODOT_SRC/thirdparty/zlib, 1.3.2) and its zlib calls resolve to the
# engine's own zlib at link time, so the binary has one zlib. A throwaway libz.a from the same sources only satisfies
# configure's link test.

set -euo pipefail
WHICH=${1:-all}
PROFILE=${PROFILE:-full}
FFMPEG_TAG=${FFMPEG_TAG:-n8.1.3}
SRC=$HOME/src/ffmpeg
GODOT_SRC=${GODOT_SRC:-$HOME/src/godot-player}
ZLIB_SRC=$GODOT_SRC/thirdparty/zlib
JOBS=$(( $(nproc) - 2 ))

if [ ! -d "$SRC/.git" ]; then
  mkdir -p "$(dirname "$SRC")"
  git clone --depth 1 --branch "$FFMPEG_TAG" https://git.ffmpeg.org/ffmpeg.git "$SRC" ||
    git clone --depth 1 --branch "$FFMPEG_TAG" https://github.com/FFmpeg/FFmpeg.git "$SRC"
fi
echo "FFmpeg source: $(git -C "$SRC" describe --tags 2>/dev/null || echo "$FFMPEG_TAG")"
[ -f "$ZLIB_SRC/zlib.h" ] || { echo "No zlib in $ZLIB_SRC (set GODOT_SRC)"; exit 1; }

BASE=(
  --disable-everything --disable-autodetect
  --disable-programs --disable-doc --disable-avdevice --disable-avfilter
  --disable-network --disable-debug
  --enable-static --disable-shared --enable-pic
  --enable-avformat --enable-avcodec --enable-avutil --enable-swresample
  --enable-zlib
  --enable-protocol=file
)

# full: everything a film library can hold. The Frame's hardware decoder takes H.264, HEVC and VP9; the rest is decoded
# on the CPU (SoftwareVideoDecoder). Demuxers: every file format (AVI incl. old DivX/Xvid, ASF/WMV, RealMedia, FLV,
# MPEG-PS/VOB, MPEG-TS, MXF, NUT, Ogg, Matroska/WebM, MOV/MP4/3GP, WTV, NSV, DV, ...), without the network ones (RTSP,
# RTP, SDP, SAP, HLS, DASH), the ones that open other files by name (concat, image2 sequences, IMF) and the ones that
# need an external library. Decoders: every native one (configure leaves out the few that need a library we don't
# build), plus libdav1d for AV1 (FFmpeg's own av1 decoder only drives hardware). swscale converts any decoded picture
# format (palette, RGB, 4:2:2, 4:4:4, gray, 10-bit, ...) to the 8-bit 4:2:0 the software path uploads.
FULL=(
  --enable-swscale
  --enable-demuxers
  --disable-demuxer=rtp,rtsp,sdp,sap,hls,dash,webm_dash_manifest,imf,concat,image2,image2_alias_pix,image2_brender_pix
  --disable-demuxer=avisynth,vapoursynth,libgme,libmodplug,libopenmpt,dvdvideo
  --enable-parsers --enable-bsfs --enable-decoders
  --enable-libdav1d
)

# minimal (frame/player): Matroska/WebM, MP4/MOV, MPEG-TS, AVI, IVF, music files and subtitle files; the H.264, HEVC
# and VP9 software decoders of the fallback path, audio and subtitle decoders, no swscale.
MINIMAL=(
  --disable-swscale
  --enable-demuxer=matroska,mov,mpegts,avi,ivf,srt,ass,webvtt,mp3,flac,ogg,wav,aac,ac3,eac3,dts,truehd
  --enable-parser=h264,hevc,vp9,av1,aac,ac3,dca,opus,vorbis,flac,mpegaudio,mlp
  --enable-bsf=h264_mp4toannexb,hevc_mp4toannexb,extract_extradata,vp9_superframe_split
  --enable-decoder=aac,aac_latm,ac3,eac3,dca,truehd,mlp,opus,vorbis,flac,alac,mp3,mp3float,mp2,mp2float,'pcm_*'
  --enable-decoder=subrip,srt,ass,ssa,movtext,webvtt,text
  --enable-decoder=pgssub,dvdsub,dvbsub,xsub
  --enable-decoder=h264,hevc,vp9
)

# A libz.a for configure's link test only (the engine links its own copy of the same zlib).
make_zlib() {
  local cc=$1 dir=$2
  rm -rf "$dir"
  mkdir -p "$dir"
  for f in adler32 compress crc32 deflate inffast inflate inftrees trees uncompr zutil; do
    "$cc" -O2 -fPIC -c "$ZLIB_SRC/$f.c" -o "$dir/$f.o"
  done
  "${cc%gcc}ar" rcs "$dir/libz.a" "$dir"/*.o
}

build() {
  local name=$1
  local suffix=-all
  local profile=("${FULL[@]}")
  if [ "$PROFILE" = minimal ]; then
    suffix=
    profile=("${MINIMAL[@]}")
  fi
  local prefix=$HOME/src/ffmpeg-$name$suffix
  local dir=$HOME/src/ffmpeg-build-$name$suffix
  local options=("${BASE[@]}" "${profile[@]}")
  local pkgconfig=$HOME/src/dav1d-$name/lib/pkgconfig
  local cc=gcc
  local extra=()
  case $name in
    aarch64) cc=aarch64-linux-gnu-gcc; extra=(--enable-cross-compile --arch=aarch64 --target-os=linux --cross-prefix=aarch64-linux-gnu-
               --pkg-config=pkg-config --pkg-config-flags=--static) ;;
    # No nasm in WSL; the x86_64 build is only for the tests, so plain C is fine.
    x86_64) extra=(--disable-x86asm --pkg-config-flags=--static) ;;
    # A remux-only command-line tool for making test files.
    tool) prefix=$HOME/src/ffmpeg-tool; dir=$HOME/src/ffmpeg-build-tool; options=(
            --disable-everything --disable-autodetect --disable-doc --disable-network --disable-debug --disable-x86asm
            --disable-avdevice --disable-ffplay --disable-ffprobe --enable-ffmpeg
            --enable-protocol=file --enable-demuxer=matroska,mov,mpegts,avi,srt,ass,image2,wav,ac3
            --enable-muxer=mpegts,matroska,mp4,mov,ipod,srt,ass,flac,ogg,wav,ac3
            --enable-parser=h264,hevc,aac,ac3,dca,mpegaudio,opus,vorbis,flac,png,mjpeg
            --enable-bsf=h264_mp4toannexb,hevc_mp4toannexb,aac_adtstoasc,extract_extradata,dump_extradata,setts
            --enable-decoder=subrip,srt,ass,ssa,pcm_s16le,png --enable-encoder=subrip,srt,ass,ssa,flac,pcm_s16le
            --enable-filter=abuffer,abuffersink,aformat,anull,aresample --enable-zlib) ;;
    *) echo "unknown target $name"; exit 1 ;;
  esac
  if [ "$PROFILE" != minimal ] && [ "$name" != tool ] && [ ! -f "$pkgconfig/dav1d.pc" ]; then
    echo "No dav1d in $HOME/src/dav1d-$name: run build/dav1d-build.sh $name first"; exit 1
  fi
  rm -rf "$dir"
  mkdir -p "$dir"
  make_zlib "$cc" "$dir/zlib"
  cd "$dir"
  PKG_CONFIG_LIBDIR=$pkgconfig "$SRC/configure" --prefix="$prefix" "${options[@]}" "${extra[@]}" \
    --extra-cflags="-I$ZLIB_SRC" --extra-ldflags="-L$dir/zlib" > configure.log 2>&1 || { tail -30 configure.log; exit 1; }
  grep -q "^zlib\b.*yes\|CONFIG_ZLIB 1" config.h configure.log 2>/dev/null || grep -q "#define CONFIG_ZLIB 1" config.h || { echo "zlib not enabled"; exit 1; }
  if grep -qE "#define CONFIG_(GPL|NONFREE) 1" config.h; then
    echo "GPL or nonfree got enabled: refusing"; exit 1
  fi
  make -j"$JOBS" > make.log 2>&1 || { tail -40 make.log; exit 1; }
  rm -rf "$prefix"
  make install > install.log 2>&1
  {
    grep -E "#define CONFIG_(GPL|NONFREE|VERSION3|LIBDAV1D|SWSCALE) " config.h || true
    for kind in decoder demuxer parser bsf; do
      echo "${kind}s: $(grep -cE "^#define CONFIG_[A-Z0-9_]+_${kind^^} 1" config_components.h || true)"
    done
  } > "$prefix/build-config.txt"
  echo "== $name: $prefix"
  cat "$prefix/build-config.txt"
  ls -l "$prefix/lib"/*.a "$prefix/bin" 2>/dev/null || true
}

case $WHICH in
  all) build aarch64; build x86_64 ;;
  *) build "$WHICH" ;;
esac
