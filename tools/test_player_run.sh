#!/usr/bin/env bash
# Tests the launcher's update swap and rollback (tools/player-run.sh, the package's run.sh; docs/framedrop.md).
# Runs in WSL or on any Linux: fake installs in a temporary home folder (with a space in its name), fake engines that
# record what ran and write the started marker as the app does. No network, no headset.
#
#   bash tools/test_player_run.sh
#
# Cases: a plain start; a swap, then the next start keeps it; a crash before the first frame, rolled back at the
# next start and recorded as bad; a new/ without new.complete; a staged version that is in bad-versions; the run.sh
# file rewritten in place while the swap moves its folder; a start from inside the folder with a relative ./run.sh;
# a rollback with no old/; only forwards (an older stage, 0.10.0 after 0.9.0, an install named by a commit).
set -u
REPO=$(cd "$(dirname "$0")/.." && pwd)
LAUNCHER=$REPO/tools/player-run.sh
FAILS=0
CHECKS=0
TMPS=()
trap 'rm -rf "${TMPS[@]}"' EXIT

check() {  # what, then a command that must succeed
  local what=$1
  shift
  CHECKS=$((CHECKS + 1))
  if ! "$@"; then
    FAILS=$((FAILS + 1))
    echo "FAIL $what"
  fi
}

# A fake install: run.sh (the launcher), VERSION, app/, and an engine that records itself. ok: as the app, it writes
# the started marker when a swap record is there. crash: exits at once, no marker.
make_install() {  # dir version ok|crash
  local dir=$1 v=$2 how=$3
  mkdir -p "$dir/bin" "$dir/app"
  cp "$LAUNCHER" "$dir/run.sh"
  chmod +x "$dir/run.sh"
  printf 'version %s\narch x86_64\n' "$v" > "$dir/VERSION"
  cat > "$dir/bin/vr-video-player-engine" <<EOF
#!/bin/bash
echo "$v \$*" >> "\$HOME/runs.log"
ST=\${XDG_STATE_HOME:-\$HOME/.local/state}/vr-video-player
if [ "$how" = ok ] && [ -f "\$ST/swapped" ]; then echo "$v" > "\$ST/started"; fi
[ "$how" = ok ] || exit 134
EOF
  chmod +x "$dir/bin/vr-video-player-engine"
}

stage() {  # version ok|crash [no-marker]
  make_install "$UPD/new" "$1" "$2"
  [ "${3:-}" = no-marker ] || printf '%s\n' "$1" > "$UPD/new.complete"
}

fresh() {
  TMP=$(mktemp -d)
  TMPS+=("$TMP")
  export HOME="$TMP/my home"
  unset XDG_STATE_HOME XDG_DATA_HOME
  INSTALL="$HOME/devkit-game/probe1"
  ST="$HOME/.local/state/vr-video-player"
  UPD="$HOME/.local/share/vr-video-player/update"
  mkdir -p "$HOME" "$UPD"
  make_install "$INSTALL" 1.0.0 ok
}

last_run() { tail -1 "$HOME/runs.log" 2>/dev/null; }
runs() { [ -f "$HOME/runs.log" ] && wc -l < "$HOME/runs.log" || echo 0; }
version_in() { sed -n 's/^version //p' "$1/VERSION"; }
launch() { "$INSTALL/run.sh" "$@" > /dev/null 2>&1; }

# 1. A plain start: the engine with the app folder, XR on, and the arguments after --.
fresh
launch --file=/x/film.mkv
check "plain: the engine ran once with the app path and the arguments" \
  [ "$(last_run)" = "1.0.0 --path $INSTALL/app --display-driver x11 --xr-mode on -- --file=/x/film.mkv" ]
check "plain: the log is in the state folder" [ -f "$ST/last.log" ]
check "plain: no swap record" [ ! -e "$ST/swapped" ]

# 2. A swap: the install moves to old/, new/ takes its place, the new run.sh starts the new engine.
fresh
stage 1.1.0 ok
launch --file=/x/film.mkv
check "swap: the new engine ran, from the same folder, with the arguments" \
  [ "$(last_run)" = "1.1.0 --path $INSTALL/app --display-driver x11 --xr-mode on -- --file=/x/film.mkv" ]
check "swap: one engine run" [ "$(runs)" -eq 1 ]
check "swap: the install folder holds 1.1.0" [ "$(version_in "$INSTALL")" = 1.1.0 ]
check "swap: old/ holds 1.0.0" [ "$(version_in "$UPD/old")" = 1.0.0 ]
check "swap: new/ is gone" [ ! -e "$UPD/new" ]
check "swap: new.complete is gone" [ ! -e "$UPD/new.complete" ]
check "swap: the record says new, old and launched" \
  [ "$(cat "$ST/swapped")" = "$(printf 'new 1.1.0\nold 1.0.0\nlaunched')" ]
check "swap: the new version wrote started" [ -f "$ST/started" ]
launch
check "swap, next start: 1.1.0 runs" [ "$(last_run)" = "1.1.0 --path $INSTALL/app --display-driver x11 --xr-mode on --" ]
check "swap, next start: the record is removed" [ ! -e "$ST/swapped" ]
check "swap, next start: the marker is removed" [ ! -e "$ST/started" ]
check "swap, next start: nothing is bad" [ ! -e "$ST/bad-versions" ]
check "swap, next start: old/ kept for one level" [ "$(version_in "$UPD/old")" = 1.0.0 ]
check "swap: update.log has the lines" grep -q "swapped in 1.1.0 (was 1.0.0)" "$ST/update.log"

# 3. A crash before the first frame: the next start puts 1.0.0 back and records 1.2.0 as bad.
fresh
stage 1.2.0 crash
launch
check "crash: 1.2.0 ran once" [ "$(last_run)" = "1.2.0 --path $INSTALL/app --display-driver x11 --xr-mode on --" ]
check "crash: no started marker" [ ! -e "$ST/started" ]
launch --file=/x/b.mkv
check "crash, next start: 1.0.0 runs with the arguments" \
  [ "$(last_run)" = "1.0.0 --path $INSTALL/app --display-driver x11 --xr-mode on -- --file=/x/b.mkv" ]
check "crash, next start: two runs in all" [ "$(runs)" -eq 2 ]
check "crash: the install folder holds 1.0.0 again" [ "$(version_in "$INSTALL")" = 1.0.0 ]
check "crash: 1.2.0 is in bad-versions" [ "$(cat "$ST/bad-versions")" = 1.2.0 ]
check "crash: no record" [ ! -e "$ST/swapped" ]
check "crash: no old/ (it is the install again)" [ ! -e "$UPD/old" ]
check "crash: no failed/" [ ! -e "$UPD/failed" ]
launch
check "crash, third start: 1.0.0" [ "$(last_run)" = "1.0.0 --path $INSTALL/app --display-driver x11 --xr-mode on --" ]
check "crash, third start: bad-versions unchanged" [ "$(cat "$ST/bad-versions")" = 1.2.0 ]
check "crash: update.log says it" grep -q "1.2.0 showed no first frame: rolled back to 1.0.0" "$ST/update.log"

# 4. A new/ without new.complete (a stage that stopped half way) is deleted, and the old version starts.
fresh
stage 1.1.0 ok no-marker
launch
check "no marker: 1.0.0 runs" [ "$(last_run)" = "1.0.0 --path $INSTALL/app --display-driver x11 --xr-mode on --" ]
check "no marker: new/ deleted" [ ! -e "$UPD/new" ]
check "no marker: nothing swapped" [ ! -e "$UPD/old" ]
check "no marker: no record" [ ! -e "$ST/swapped" ]

# 5. A staged version that was rolled back before is not swapped in.
fresh
mkdir -p "$ST"
echo 1.1.0 > "$ST/bad-versions"
stage 1.1.0 ok
launch
check "bad version: 1.0.0 runs" [ "$(last_run)" = "1.0.0 --path $INSTALL/app --display-driver x11 --xr-mode on --" ]
check "bad version: new/ deleted" [ ! -e "$UPD/new" ]
check "bad version: new.complete deleted" [ ! -e "$UPD/new.complete" ]

# 6. The run.sh file is rewritten in place (same inode) at the moment its folder moves: bash has read all of it.
fresh
stage 1.1.0 ok
mkdir -p "$TMP/fakebin"
REAL_MV=$(command -v mv)
cat > "$TMP/fakebin/mv" <<EOF
#!/bin/bash
if [ "\$1" = "$INSTALL" ]; then
  printf 'echo CORRUPT >> "\$HOME/corrupt.log"; exit 7\n%0500d\n' 0 > "$INSTALL/run.sh"
fi
exec "$REAL_MV" "\$@"
EOF
chmod +x "$TMP/fakebin/mv"
PATH="$TMP/fakebin:$PATH" "$INSTALL/run.sh" --x > /dev/null 2>&1
check "moved while running: the new engine ran" [ "$(last_run)" = "1.1.0 --path $INSTALL/app --display-driver x11 --xr-mode on -- --x" ]
check "moved while running: nothing of the rewritten file ran" [ ! -e "$HOME/corrupt.log" ]

# 7. Started from inside the folder with a relative path (as Steam does: the title's folder is the working folder).
fresh
stage 1.1.0 ok
(cd "$INSTALL" && ./run.sh --y > /dev/null 2>&1)
check "relative start: the new engine" [ "$(last_run)" = "1.1.0 --path $INSTALL/app --display-driver x11 --xr-mode on -- --y" ]
check "relative start: old/ holds 1.0.0" [ "$(version_in "$UPD/old")" = 1.0.0 ]

# 8. No old install to roll back to (it was removed by hand): the bad version is recorded and it runs on.
fresh
stage 1.2.0 crash
launch
rm -rf "$UPD/old"
launch
check "no old/: recorded as bad" [ "$(cat "$ST/bad-versions")" = 1.2.0 ]
check "no old/: the record cleared" [ ! -e "$ST/swapped" ]
check "no old/: 1.2.0 started again" [ "$(runs)" -eq 2 ]

# 9. Only forwards: a stage older than the install (it was installed again by hand since) is deleted, not swapped in.
fresh
make_install "$INSTALL" 1.3.0 ok
stage 1.1.0 ok
launch
check "older stage: the install runs" [ "$(last_run)" = "1.3.0 --path $INSTALL/app --display-driver x11 --xr-mode on --" ]
check "older stage: deleted" [ ! -e "$UPD/new" ]
check "older stage: nothing swapped" [ ! -e "$UPD/old" ]
# 0.10.0 is after 0.9.0 (numbers, not text).
fresh
make_install "$INSTALL" 0.9.0 ok
stage 0.10.0 ok
launch
check "0.10.0 after 0.9.0: swapped" [ "$(last_run)" = "0.10.0 --path $INSTALL/app --display-driver x11 --xr-mode on --" ]
# A build named by its commit is never replaced.
fresh
printf 'version abc1234\n' > "$INSTALL/VERSION"
stage 1.1.0 ok
launch
check "commit build: kept" [ "$(last_run)" = "1.0.0 --path $INSTALL/app --display-driver x11 --xr-mode on --" ]
check "commit build: the stage deleted" [ ! -e "$UPD/new" ]

echo "player-run: $((CHECKS - FAILS))/$CHECKS checks passed"
[ "$FAILS" -eq 0 ]
