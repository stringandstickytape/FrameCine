#!/bin/bash
# Network input (#86, #88) on this machine's loopback, for the device as well as the host: serves an MPEG-TS file with
# tools/stream_server.py and plays it with stream_cpu.gd for SECONDS each as a local file, an HTTP file (Range
# requests), live HTTP (chunked, paced at RATE) and UDP (paced at RATE). Prints one CPU line each. Headless: no
# display, no decoder. Needs python3.
#   bash stream-tests.sh GODOT_BINARY FILE.ts [RATE_BYTES_PER_SECOND [SECONDS]]
# RATE: the file's average rate (animated_90s.ts from make-test-files.sh: 298800). Ports 8761 and 8762.
set -u
GODOT=$(realpath "$1")
FILE=$(realpath "$2")
RATE=${3:-298800}
SECONDS_EACH=${4:-20}
cd "$(dirname "$0")"
DIR=$(dirname "$FILE")
NAME=$(basename "$FILE")
run() { timeout $((SECONDS_EACH + 60)) "$GODOT" --headless --path . --script stream_cpu.gd -- "$@" 2>&1 | grep -E "^CPU|ERROR" | grep -v "global script cache"; }

python3 tools/stream_server.py serve "$DIR" 8761 > /dev/null 2>&1 &
SERVER=$!
sleep 1
run "$FILE" "$SECONDS_EACH"
run "http://127.0.0.1:8761/$NAME" "$SECONDS_EACH"
run "http://127.0.0.1:8761/live/$NAME?rate=$RATE" "$SECONDS_EACH"
kill $SERVER

# The sender starts with the open, as a camera or TV feed would be running already: the open waits for a keyframe.
python3 tools/stream_server.py udp "$FILE" 127.0.0.1 8762 "$RATE" > /dev/null 2>&1 &
SENDER=$!
run "udp://@:8762" "$SECONDS_EACH"
kill $SENDER
