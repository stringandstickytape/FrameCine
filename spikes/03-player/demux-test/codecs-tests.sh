#!/bin/bash
# Runs codecs_test.gd (every codec of the software path: the clips of make-codec-files.sh, then real files from G:) on
# the host build with a window (xvfb) and lavapipe, and prints the failures and the summary table.
#   wsl -d Ubuntu -- bash spikes/03-player/demux-test/codecs-tests.sh [--only=a,b] [--no-real] [--threads=N]
# GODOT=<binary> overrides the engine (default: the frame/codecs worktree's x86_64 build). Log: /tmp/codecs-test.log.

cd "$(dirname "$0")"
GODOT=${GODOT:-$HOME/src/godot-player-codecs/bin/godot.linuxbsd.template_debug.x86_64}
LOG=${LOG:-/tmp/codecs-test.log}
VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json timeout 1800 xvfb-run -a "$GODOT" --path . --script res://codecs_test.gd -- "$@" > "$LOG" 2>&1
code=$?
grep -E "^==|FAIL|NOTE|^RESULT|^  failed|SCRIPT ERROR" "$LOG"
echo
sed -n '/^file /,/^RESULT/p' "$LOG"
exit $code
