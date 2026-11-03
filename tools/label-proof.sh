#!/bin/bash
# Proves the controller labels on the PC (app/tools/label_proof.gd): exits non-zero when a legend breaks a limit, so it can
# gate a deploy. Runs in WSL, with no GPU, on the lavapipe Vulkan driver. Put the output outside the repository: it shows
# the runtime's model.
#   tools/label-proof.sh MODEL_DIR OUT_DIR [--eye=N --tan=W,H, from the --labels-debug log on the device]
set -u
if [ $# -lt 2 ]; then
  echo "usage: $0 MODEL_DIR OUT_DIR [--eye=N] [--tan=W,H] [--states=...] [--frames=N]" >&2
  exit 2
fi
MODELS=$1
OUT=$2
shift 2
GODOT=${GODOT:-$HOME/src/godot-player/bin/godot.linuxbsd.template_debug.x86_64}
cd "$(dirname "$0")/.." || exit 2
mkdir -p "$OUT"
VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a -s "-screen 0 1280x720x24" \
  "$GODOT" --xr-mode off --path app --script res://tools/label_proof.gd -- --model-dir="$MODELS" --out="$OUT" "$@" \
  2>&1 | tee "$OUT/proof.log" | grep -E "^Proof|^FAIL|^Sheet|^[a-z]+ (right|left) |SCRIPT ERROR|Parse Error"
status=${PIPESTATUS[0]}
echo "label proof: exit $status"
exit "$status"
