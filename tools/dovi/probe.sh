#!/bin/bash
# Probes the HEVC / HDR files in a folder for their Dolby Vision profile and colour description (ffmpeg -i, the
# player's tool build). Film names stay on the command line, never in the repository.
#   bash tools/dovi/probe.sh <folder> [name-part]
DIR=${1:?folder}
PART=${2:-}
P="$HOME/src/ffmpeg-tool/bin/ffmpeg"
[ -x "$P" ] || { echo "no ffmpeg at $P"; exit 1; }
cd "$DIR" || exit 1
for f in *.mkv *.mp4; do
  if [ -n "$PART" ]; then
    case "$f" in *"$PART"*) ;; *) continue ;; esac
  else
    case "$f" in
      *2160p*|*DV*|*HDR*|*x265*|*X265*|*H265*|*h265*|*HEVC*) ;;
      *) continue ;;
    esac
  fi
  info=$("$P" -hide_banner -i "$f" 2>&1)
  echo "== $f"
  echo "$info" | grep -E "Stream #|DOVI|Mastering|Content Light|Duration" | sed -E 's/^ +//' | cut -c1-200
done
