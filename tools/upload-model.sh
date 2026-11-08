#!/bin/bash
# Publishes the speech model that the player downloads the first time voice is used (docs/framedrop.md "The speech
# model", app/scripts/voice/model_download.gd) as a GitHub release of its own: the model, SHA256SUMS and the model's
# MIT notice. That release never changes, and it must never become the repository's "latest" release, because the
# player's updater reads releases/latest. So it is made a pre-release (GitHub's releases/latest never returns one)
# and also --latest=false, and the script checks releases/latest afterwards.
#
#   bash tools/upload-model.sh [--publish] [--model FILE]
#
# Without --publish it is a dry run: it checks the file and prints what it would do; nothing goes to GitHub.
# --model FILE   the model file (default: build/out/whisper-models/<name> of this checkout, else of the main checkout;
#                build/whisper-models.sh downloads it)
# GH=...         the GitHub CLI to use (default: gh, else gh.exe; from WSL, gh.exe gets Windows paths)
#
# The repository, the tag, the file name, its size and its SHA-256 are read from model_download.gd (RELEASES,
# MODEL_RELEASE, MODEL_FILE, MODEL_SIZE, MODEL_SHA256), so the app and the release cannot disagree. A rename of the
# repository changes RELEASES there and nothing here.

set -euo pipefail
REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
SRC=$REPO/app/scripts/voice/model_download.gd

PUBLISH=0
MODEL=""
while [ $# -gt 0 ]; do
  case $1 in
    --publish) PUBLISH=1 ;;
    --model) MODEL=$2; shift ;;
    --model=*) MODEL=${1#--model=} ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

const() {  # const NAME: the value of `const NAME := ...` in model_download.gd, without quotes
  sed -n "s/^const $1 := \"\{0,1\}\([^\"]*\)\"\{0,1\}\$/\1/p" "$SRC" | head -1
}
RELEASES=$(const RELEASES)
TAG=$(const MODEL_RELEASE)
NAME=$(const MODEL_FILE)
SIZE=$(const MODEL_SIZE)
SHA=$(const MODEL_SHA256)
SLUG=${RELEASES#https://github.com/}
SLUG=${SLUG%/releases/download}
for v in RELEASES TAG NAME SIZE SHA SLUG; do
  [ -n "${!v}" ] || { echo "could not read $v from $SRC" >&2; exit 1; }
done
case $SLUG in */*) ;; *) echo "RELEASES is not a github.com releases address: $RELEASES" >&2; exit 1 ;; esac

if [ -z "$MODEL" ]; then
  MODEL=$REPO/build/out/whisper-models/$NAME
  if [ ! -f "$MODEL" ]; then
    # A linked worktree: build/out is the main checkout's.
    # A linked worktree's .git file names <main>/.git/worktrees/<name> (a Windows path when Windows git made it,
    # which git in WSL cannot follow, so it is read here).
    MAIN=""
    if [ -f "$REPO/.git" ]; then
      gd=$(sed -n 's/^gitdir: //p' "$REPO/.git" | tr -d '\r')
      if [[ $gd =~ ^[A-Za-z]: ]] && command -v wslpath >/dev/null 2>&1; then gd=$(wslpath -u "$gd"); fi
      [[ $gd == */.git/worktrees/* ]] && MAIN=${gd%/.git/worktrees/*}
    fi
    if [ -n "$MAIN" ] && [ -f "$MAIN/build/out/whisper-models/$NAME" ]; then
      MODEL=$MAIN/build/out/whisper-models/$NAME
    fi
  fi
fi
STEM=${NAME#ggml-}
STEM=${STEM%.bin}
[ -f "$MODEL" ] || { echo "no $NAME (bash build/whisper-models.sh $STEM downloads it, or --model FILE)" >&2; exit 1; }
LICENSE=$REPO/build/whisper/LICENSE-models.txt
[ -f "$LICENSE" ] || { echo "no $LICENSE" >&2; exit 1; }

got_size=$(stat -c %s "$MODEL")
[ "$got_size" = "$SIZE" ] || { echo "$MODEL: $got_size bytes, the app expects $SIZE" >&2; exit 1; }
got_sha=$(sha256sum "$MODEL" | cut -d' ' -f1)
[ "$got_sha" = "$SHA" ] || { echo "$MODEL: SHA-256 $got_sha, the app expects $SHA" >&2; exit 1; }

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp "$LICENSE" "$STAGE/LICENSE-models.txt"
( cd "$STAGE" && echo "$SHA  $NAME" > SHA256SUMS && sha256sum LICENSE-models.txt >> SHA256SUMS )
cat > "$STAGE/notes.md" <<EOF
The speech model for on-device voice. The player downloads it once, the first time voice is used, into its data
folder (\`user://whisper-models/\`), and checks its SHA-256. You do not need to download anything here.

- \`$NAME\`: $SIZE bytes, SHA-256 \`$SHA\`
- OpenAI's Whisper small.en weights (MIT), converted to ggml by the whisper.cpp project
  (Hugging Face ggerganov/whisper.cpp, the revision in \`build/whisper-models.sh\`). The MIT notice:
  \`LICENSE-models.txt\`.

This release does not change, and it is not a player release: player releases are the ones marked latest.
EOF

echo "repository  $SLUG"
echo "release     $TAG (pre-release, not latest)"
echo "model       $MODEL"
echo "            $SIZE bytes, SHA-256 $SHA (matches the app)"
echo "assets      $NAME, SHA256SUMS, LICENSE-models.txt"
echo "address     $RELEASES/$TAG/$NAME"

GH=${GH:-}
if [ -z "$GH" ]; then
  if command -v gh >/dev/null 2>&1; then GH=gh; elif command -v gh.exe >/dev/null 2>&1; then GH=gh.exe; fi
fi
p() {  # a path for $GH (Windows form for gh.exe under WSL)
  if [[ $GH == *.exe ]] && command -v wslpath >/dev/null 2>&1; then wslpath -w "$1"; else echo "$1"; fi
}

CREATE=("$GH" release create "$TAG" --repo "$SLUG" --title "Speech model ($TAG)" --notes-file "$(p "$STAGE/notes.md")"
  --prerelease --latest=false
  "$(p "$MODEL")" "$(p "$STAGE/SHA256SUMS")" "$(p "$STAGE/LICENSE-models.txt")")

if [ "$PUBLISH" = 0 ]; then
  echo
  echo "Dry run. With --publish it runs:"
  printf '  %q' "${CREATE[@]}"; echo
  echo "then checks that releases/latest is not $TAG."
  exit 0
fi

[ -n "$GH" ] || { echo "no gh or gh.exe (GitHub CLI); set GH=..." >&2; exit 1; }
if "$GH" release view "$TAG" --repo "$SLUG" >/dev/null 2>&1; then
  have=$("$GH" release view "$TAG" --repo "$SLUG" --json assets --jq '.assets[].name')
  if grep -qx "$NAME" <<<"$have"; then
    echo "$TAG already has $NAME; nothing to do (the release does not change)."
  else
    echo "$TAG exists without $NAME: uploading the assets"
    "$GH" release upload "$TAG" --repo "$SLUG" "$(p "$MODEL")" "$(p "$STAGE/SHA256SUMS")" \
      "$(p "$STAGE/LICENSE-models.txt")"
  fi
else
  "${CREATE[@]}"
fi

# The release must not be the one the updater sees.
flags=$("$GH" release view "$TAG" --repo "$SLUG" --json isPrerelease,isDraft --jq '"\(.isPrerelease) \(.isDraft)"')
latest=$("$GH" api "repos/$SLUG/releases/latest" --jq .tag_name 2>/dev/null || echo "(none)")
echo "$TAG: pre-release/draft = $flags; releases/latest = $latest"
if [ "$latest" = "$TAG" ]; then
  echo "releases/latest is $TAG: the updater would read it. Fix: $GH release edit $TAG --repo $SLUG --prerelease" >&2
  exit 1
fi
url=$RELEASES/$TAG/$NAME
echo "check: curl -sIL $url | grep -i '^content-length'  (expect $SIZE)"
