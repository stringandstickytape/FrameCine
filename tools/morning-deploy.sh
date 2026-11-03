#!/usr/bin/env bash
# One sudo-free command for the morning: copies everything the runbook (docs/morning-checklist.md) needs to the
# headset, checks the SHA-256 of every copied file on the headset, and prints the runbook's next step.
# PC side; run from Git Bash or WSL.
#
#   tools/morning-deploy.sh [--engine NAME] [--no-whisper] [--whisper-models "STEM ..."] [--dry-run]
#
# Engine: build/out/godot.linuxbsd.template_debug.arm64.PLAYER_FINAL2, the newest cumulative build engine-demux has
# posted (fork 42175b2a3c; it holds everything of PLAYER_HDR, PLAYER_INPUTS, PLAYER_PICTURE, PLAYER_NEXT,
# PLAYER_REQUESTS and PLAYER_FINAL; lineage in spikes/03-player/README.md). --engine NAME picks
# another build/out file, e.g. the baseline --engine godot.linuxbsd.template_debug.arm64.PLAYER_ALL2.
#
# What goes where (FRAME_HOST, default "frame", an ssh config entry; paths relative to the headset user's home):
#   build/out/<engine>                                   spike03/<engine>, and spike03/godot_player links to it
#   app/ (tools/push-app.sh: no .godot/, no docs/)       spike03/app/
#   spikes/03-player/project/*                           spike03/project/
#   spikes/03-player/demux-test (as committed)           spike03/demux-test/  (stream-tests.sh, runbook C7)
#   the stream test clip ~/media-tests/animated_90s.ts      spike03/            (WSL home; runbook C7)
#   build/out/whisper/aarch64 (whisper-server, -cli, -bench) spike03/whisper/     (speech to text; the app finds it
#   build/out/whisper/aarch64-vulkan (server, cli)       spike03/whisper/vulkan/  next to the engine;
#   build/out/whisper-models/ggml-*.bin                  spike03/whisper/models/  build/whisper/README.md)
#   build/whisper/samples/*.wav                          spike03/whisper/samples/
#   tools/whisper-bench.sh                               spike03/tools/whisper-bench.sh
# --no-kernel is accepted and ignored, for old command lines (the decoder module is gone, docs/decisions.md D21).
# --no-whisper leaves out speech to text;
# --whisper-models limits the models (default: every one in build/out/whisper-models, 670 MB for the six quantized
# ones). Without a whisper build the section is skipped with a note (build/whisper-build.sh, build/whisper-models.sh).
#
# FRAME_HOST=local does the same on this machine under $HOME (a test in WSL; push-app.sh is replaced by a tar copy).
# Nothing runs with sudo, nothing is deleted on the headset, and no credentials are read or sent.
set -euo pipefail

HOST=${FRAME_HOST:-frame}
REPO=$(cd "$(dirname "$0")/.." && pwd)
ENGINE=godot.linuxbsd.template_debug.arm64.PLAYER_FINAL2
STREAM_CLIP=animated_90s.ts
WHISPER=1
WHISPER_MODELS=""
DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --engine) ENGINE=$2; shift ;;
    --no-kernel) ;;  # accepted for old command lines: there is no kernel module step any more
    --no-whisper) WHISPER=0 ;;
    --whisper-models) WHISPER_MODELS=$2; shift ;;
    --dry-run) DRY=1 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done
cd "$REPO"

# --- Sources ----------------------------------------------------------------------------------------------------------
ENGINE_DIR=${ENGINE_DIR:-build/out}
if [ ! -f "$ENGINE_DIR/$ENGINE" ]; then  # a linked worktree: build/out is in the main checkout
  ENGINE_DIR="$(cd "$(git rev-parse --git-common-dir)/.." && pwd)/build/out"
fi
[ -f "$ENGINE_DIR/$ENGINE" ] || { echo "no engine $ENGINE in build/out" >&2; exit 1; }

# The WSL home: here when we run in WSL, else through \\wsl.localhost from Git Bash.
WH=${WSL_HOME:-}
if [ -z "$WH" ]; then
  if grep -qi microsoft /proc/version 2>/dev/null; then
    WH=$HOME
  elif command -v wsl.exe > /dev/null 2>&1; then
    WU=$(MSYS_NO_PATHCONV=1 wsl.exe -e whoami 2>/dev/null | tr -d '\r')
    WH=//wsl.localhost/Ubuntu/home/$WU
  fi
fi
CLIP=${STREAM_CLIP_PATH:-$WH/media-tests/$STREAM_CLIP}
[ -f "$CLIP" ] || { echo "no stream test clip $CLIP (STREAM_CLIP_PATH)" >&2; exit 1; }

# --- Transfer helpers -------------------------------------------------------------------------------------------------
MANIFEST=$(mktemp)
trap 'rm -f "$MANIFEST"' EXIT
COUNT=0
BYTES=0

remote() {  # a command on the headset (or here, for FRAME_HOST=local)
  if [ "$HOST" = local ]; then (cd "$HOME" && bash -c "$1"); else ssh "$HOST" "$1"; fi
}

# put SRC DEST: DEST relative to the headset home. Records the hash for the check at the end.
put() {
  local src=$1 dst=$2
  printf '%s  %s\n' "$(sha256sum "$src" | cut -d' ' -f1)" "$dst" >> "$MANIFEST"
  COUNT=$((COUNT + 1)); BYTES=$((BYTES + $(wc -c < "$src")))
  if [ "$DRY" = 1 ]; then
    printf '  %-60s %s\n' "$dst" "$(du -h "$src" | cut -f1)"
    return
  fi
  if [ "$HOST" = local ]; then
    mkdir -p "$(dirname "$HOME/$dst")"
    cp "$src" "$HOME/$dst"
  else
    ssh "$HOST" "mkdir -p \"\$(dirname ~/$dst)\" && cat > ~/$dst" < "$src"
  fi
}

echo "== Engine: $ENGINE"
put "$ENGINE_DIR/$ENGINE" "spike03/$ENGINE"
[ "$DRY" = 1 ] || remote "chmod +x ~/spike03/$ENGINE && ln -sfn $ENGINE ~/spike03/godot_player"

echo "== App: app/ to spike03/app"
APP_FILES=$(cd app && find . \( -path ./.godot -o -path ./docs \) -prune -o -type f -print | sed 's|^\./||' | sort)
if [ "$DRY" = 1 ]; then
  echo "  $(printf '%s\n' "$APP_FILES" | wc -l) files (tools/push-app.sh)"
elif [ "$HOST" = local ]; then
  mkdir -p "$HOME/spike03/app"
  (cd app && printf '%s\n' "$APP_FILES" | tar -cf - -T -) | tar -xf - -C "$HOME/spike03/app"
else
  FRAME_APP_DIR=spike03/app bash tools/push-app.sh > /dev/null
fi
while IFS= read -r f; do
  printf '%s  %s\n' "$(sha256sum "app/$f" | cut -d' ' -f1)" "spike03/app/$f" >> "$MANIFEST"
  COUNT=$((COUNT + 1))
done <<< "$APP_FILES"

echo "== Engine test project: spikes/03-player/project to spike03/project"
for f in spikes/03-player/project/*; do
  [ -f "$f" ] && put "$f" "spike03/project/$(basename "$f")"
done

echo "== Stream tests: spikes/03-player/demux-test to spike03/demux-test, and the clip"
while IFS= read -r f; do
  put "$f" "spike03/demux-test/${f#spikes/03-player/demux-test/}"
done < <(git ls-files spikes/03-player/demux-test)
put "$CLIP" "spike03/$STREAM_CLIP"
[ "$DRY" = 1 ] || remote "chmod +x ~/spike03/demux-test/*.sh"

if [ "$WHISPER" = 1 ]; then
  echo "== Speech to text: build/out/whisper to spike03/whisper, tools/whisper-bench.sh to spike03/tools"
  WOUT=build/out/whisper
  [ -f "$WOUT/aarch64/whisper-server" ] || WOUT="$(cd "$(git rev-parse --git-common-dir)/.." && pwd)/build/out/whisper"
  WMOD=$(dirname "$WOUT")/whisper-models
  if [ ! -f "$WOUT/aarch64/whisper-server" ]; then
    echo "  no build/out/whisper/aarch64: skipped (build/whisper-build.sh, build/whisper-models.sh)"
  else
    (cd "$WOUT/aarch64" && sha256sum -c --quiet SHA256SUMS) || { echo "$WOUT/aarch64: SHA256SUMS mismatch" >&2; exit 1; }
    for f in whisper-server whisper-cli whisper-bench BUILDINFO LICENSE-whisper.cpp.txt; do
      put "$WOUT/aarch64/$f" "spike03/whisper/$f"
    done
    if [ -f "$WOUT/aarch64-vulkan/whisper-server" ]; then
      (cd "$WOUT/aarch64-vulkan" && sha256sum -c --quiet SHA256SUMS) || { echo "$WOUT/aarch64-vulkan: SHA256SUMS mismatch" >&2; exit 1; }
      for f in whisper-server whisper-cli BUILDINFO; do
        put "$WOUT/aarch64-vulkan/$f" "spike03/whisper/vulkan/$f"
      done
    else
      echo "  no Vulkan build (build/whisper-build.sh aarch64-vulkan): the bench runs the CPU build only"
    fi
    if [ -n "$WHISPER_MODELS" ]; then
      for m in $WHISPER_MODELS; do
        [ -f "$WMOD/ggml-$m.bin" ] || { echo "no model $WMOD/ggml-$m.bin (build/whisper-models.sh $m)" >&2; exit 1; }
        put "$WMOD/ggml-$m.bin" "spike03/whisper/models/ggml-$m.bin"
      done
    else
      for f in "$WMOD"/ggml-*.bin; do
        [ -f "$f" ] && put "$f" "spike03/whisper/models/$(basename "$f")"
      done
    fi
    for f in build/whisper/samples/*.wav; do
      put "$f" "spike03/whisper/samples/$(basename "$f")"
    done
    put tools/whisper-bench.sh spike03/tools/whisper-bench.sh
    [ "$DRY" = 1 ] || remote "chmod +x ~/spike03/whisper/whisper-* ~/spike03/tools/whisper-bench.sh; [ -d ~/spike03/whisper/vulkan ] && chmod +x ~/spike03/whisper/vulkan/whisper-*; true"
  fi
fi

if [ "$DRY" = 1 ]; then
  echo "dry run: $COUNT files, $((BYTES / 1048576)) MB (app files not counted in MB); nothing copied"
  exit 0
fi

# --- Check every file on the headset ---------------------------------------------------------------------------------
echo "== Checking $COUNT files on $HOST (SHA-256)"
if [ "$HOST" = local ]; then
  FAILED=$( (cd "$HOME" && sha256sum -c --quiet - 2>&1) < "$MANIFEST" || true)
else
  FAILED=$(ssh "$HOST" 'cd ~ && sha256sum -c --quiet - 2>&1' < "$MANIFEST" || true)
fi
if [ -n "$FAILED" ]; then
  echo "$FAILED"
  echo "SHA-256 check FAILED: copy again before you go on" >&2
  exit 1
fi
echo "All $COUNT files match."
echo
cat <<'EOF'
Next (docs/morning-checklist.md, section C; the stock module): in ssh frame, cd ~/spike03, then the commands of C1.
EOF
