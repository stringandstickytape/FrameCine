#!/bin/bash
# Downloads the whisper.cpp speech models (ggml format, MIT, converted from OpenAI's Whisper) for on-device
# transcription (build/whisper/README.md) and checks each against its SHA-256. Models are never committed.
# Runs from WSL or Git Bash (needs curl and sha256sum):
#   bash build/whisper-models.sh [--all | MODEL...]
# MODEL is a file stem such as base.en-q8_0. Default: the quantized English models below (q5_1 and q8_0 of tiny.en,
# base.en and small.en; 670 MB together). --all adds the unquantized f16 files (713 MB more).
# Output: build/out/whisper-models/ggml-<model>.bin (or $WHISPER_MODELS_OUT). Files already there with the right
# SHA-256 are kept. The source is pinned to one revision of the Hugging Face repository ggerganov/whisper.cpp.
#
# Sizes (bytes) and SHA-256 (from the repository's LFS pointers at that revision):
#   model            size        use
#   tiny.en-q5_1      32166155   the desktop tests
#   tiny.en-q8_0      43550795
#   base.en-q5_1      59721011
#   base.en-q8_0      81781811   the default in the package ([voice] whisper_model "base.en")
#   small.en-q5_1    190098681
#   small.en-q8_0    264477561   what the PC used (small.en); if the headset's benchmark says it is fast enough
#   tiny.en           77704715   f16 (--all)
#   base.en          147964211   f16 (--all)
#   small.en         487614201   f16 (--all)

set -euo pipefail
REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
OUT=${WHISPER_MODELS_OUT:-$REPO/build/out/whisper-models}
REV=5359861c739e955e79d9a303bcbc70fb988958b1
BASE=https://huggingface.co/ggerganov/whisper.cpp/resolve/$REV

declare -A SHA=(
  [tiny.en-q5_1]=c77c5766f1cef09b6b7d47f21b546cbddd4157886b3b5d6d4f709e91e66c7c2b
  [tiny.en-q8_0]=5bc2b3860aa151a4c6e7bb095e1fcce7cf12c7b020ca08dcec0c6d018bb7dd94
  [base.en-q5_1]=4baf70dd0d7c4247ba2b81fafd9c01005ac77c2f9ef064e00dcf195d0e2fdd2f
  [base.en-q8_0]=a4d4a0768075e13cfd7e19df3ae2dbc4a68d37d36a7dad45e8410c9a34f8c87e
  [small.en-q5_1]=bfdff4894dcb76bbf647d56263ea2a96645423f1669176f4844a1bf8e478ad30
  [small.en-q8_0]=67a179f608ea6114bd3fdb9060e762b588a3fb3bd00c4387971be4d177958067
  [tiny.en]=921e4cf8686fdd993dcd081a5da5b6c365bfde1162e72b08d75ac75289920b1f
  [base.en]=a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002
  [small.en]=c6138d6d58ecc8322097e0f987c32f1be8bb0a18532a3f88f734d1bbf9c41e5d
)
DEFAULT=(tiny.en-q5_1 tiny.en-q8_0 base.en-q5_1 base.en-q8_0 small.en-q5_1 small.en-q8_0)

MODELS=()
case "${1:-}" in
  "") MODELS=("${DEFAULT[@]}") ;;
  --all) MODELS=("${DEFAULT[@]}" tiny.en base.en small.en) ;;
  -h|--help) sed -n '2,23p' "$0"; exit 0 ;;
  *) MODELS=("$@") ;;
esac

mkdir -p "$OUT"
for m in "${MODELS[@]}"; do
  want=${SHA[$m]:-}
  [ -n "$want" ] || { echo "unknown model $m (known: ${!SHA[*]})" >&2; exit 2; }
  f=$OUT/ggml-$m.bin
  if [ -f "$f" ] && [ "$(sha256sum "$f" | cut -d' ' -f1)" = "$want" ]; then
    echo "ok    ggml-$m.bin"
    continue
  fi
  echo "fetch ggml-$m.bin"
  curl -fL --retry 3 --progress-bar -o "$f.part" "$BASE/ggml-$m.bin"
  got=$(sha256sum "$f.part" | cut -d' ' -f1)
  if [ "$got" != "$want" ]; then
    rm -f "$f.part"
    echo "ggml-$m.bin: SHA-256 $got, expected $want" >&2
    exit 1
  fi
  mv -f "$f.part" "$f"
done
(cd "$OUT" && ls -l ggml-*.bin | awk '{printf "%10d  %s\n", $5, $9}')
