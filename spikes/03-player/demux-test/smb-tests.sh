#!/bin/bash
# Runs the SMB tests on the host build: MediaBrowser against the share (test.gd --browse), the full MediaSource test on
# the full-SBS 3D documentary MKV read over SMB (compared with documentary_sbs.h264, as the local run) with real-time playback and throughput,
# and project/main.gd with the arguments used on the Frame (password file, empty or machine-name domain; --probe and
# playback), which must get through MediaSource.open().
#   wsl -d Ubuntu -- bash spikes/03-player/demux-test/smb-tests.sh [host [share]]
# Credentials: ~/.config/frame-player/smb-test.env (mode 600, never committed), lines SMB_HOST=, SMB_USER=, SMB_PASSWORD=,
# SMB_DOMAIN=. Logs: /tmp/smb-test-*.log (no password in them; checked).

cd "$(dirname "$0")"
GODOT=${GODOT:-$HOME/src/godot-player/bin/godot.linuxbsd.template_debug.x86_64}
ENV_FILE=${SMB_ENV_FILE:-$HOME/.config/frame-player/smb-test.env}
[ -f "$ENV_FILE" ] || { echo "No $ENV_FILE (SMB_HOST, SMB_USER, SMB_PASSWORD, SMB_DOMAIN)"; exit 1; }
set -a
. "$ENV_FILE"
set +a
HOST=${1:-$SMB_HOST}
SHARE=${2:-${SMB_SHARE:-Movies}}
RAW=$(cd ../../01-decode/streams && pwd)/documentary_sbs.h264
FILM="smb://$HOST/$SHARE/Documentary.3D.Full-SBS.mkv"
FAILS=0

no_password() {
  if grep -q -F "$SMB_PASSWORD" "$1"; then
    echo "   FAIL  the password appears in $1"
    FAILS=$((FAILS + 1))
  fi
}

run() {
  local log=$1
  shift
  timeout 300 "$GODOT" --headless --path . -- "$@" > "$log" 2>&1
  local code=$?
  echo "== $* : exit $code"
  grep -E "^  FAIL|^RESULT|^Throughput|^Real time|^  network|^Network|^list_|^MediaSource.open|SCRIPT ERROR|leaked|^AudioStreamPlayer|After the seek:|open\(\) \(|close\(\) took|pulled .* access units|byte-identical" "$log" | sed 's/^/   /' | cut -c1-300
  grep -q "^RESULT: PASS" "$log" || FAILS=$((FAILS + 1))
  no_password "$log"
}

# project/main.gd, run like on the Frame (the password only in a file; SMB_PASSWORD not in the environment).
project() {
  local log=$1
  shift
  (cd ../project && env -u SMB_PASSWORD timeout 120 "$GODOT" --headless --path . -- "$@") > "$log" 2>&1
  no_password "$log"
}

expect() { # name, log, text that must be there
  if grep -q -F -- "$3" "$2"; then
    echo "   PASS  $1"
  else
    echo "   FAIL  $1 (no \"$3\" in $2)"
    FAILS=$((FAILS + 1))
  fi
}

refuse() { # name, log, text that must not be there
  if grep -q -F -- "$3" "$2"; then
    echo "   FAIL  $1 (\"$3\" in $2)"
    FAILS=$((FAILS + 1))
  else
    echo "   PASS  $1"
  fi
}

SMB_SHARE=$SHARE run /tmp/smb-test-browse.log --browse="$HOST"
run /tmp/smb-test-film.log --file="$FILM" --raw="$RAW" --throughput=8

echo "== project/main.gd with the Frame's arguments"
PWFILE=$(mktemp)
chmod 600 "$PWFILE"
printf '%s\n' "$SMB_PASSWORD" > "$PWFILE"
for domain in "" "$SMB_DOMAIN"; do
  label="domain \"$domain\""
  project /tmp/smb-test-main-probe.log --probe --media="$FILM" --smb-user="$SMB_USER" --smb-domain="$domain" --smb-password-file="$PWFILE"
  expect "--probe --media=smb://, $label: credentials registered" /tmp/smb-test-main-probe.log "SMB: $HOST as $SMB_USER"
  expect "--probe --media=smb://, $label: MediaSource.open() succeeds" /tmp/smb-test-main-probe.log "first access units (bytes)"
  refuse "--probe --media=smb://, $label: no access denied" /tmp/smb-test-main-probe.log "Access denied"
  project /tmp/smb-test-main-play.log --no-xr --sbs --media="$FILM" --smb-user="$SMB_USER" --smb-domain="$domain" --smb-password-file="$PWFILE" --quit-after=30
  expect "playback, $label: credentials registered" /tmp/smb-test-main-play.log "SMB: $HOST as $SMB_USER"
  expect "playback, $label: MediaSource.open() succeeds" /tmp/smb-test-main-play.log "Media: matroska"
  expect "playback, $label: the player gets the source (fails only for want of /dev/video-dec0; too big for software)" /tmp/smb-test-main-play.log "no hardware video decoder on this machine"
  refuse "playback, $label: no access denied" /tmp/smb-test-main-play.log "Access denied"
  refuse "playback, $label: no unknown arguments" /tmp/smb-test-main-play.log "unknown argument"
done
project /tmp/smb-test-main-guest.log --no-xr --media="$FILM" --quit-after=5
expect "without --smb-user: the error says no credentials were set" /tmp/smb-test-main-guest.log "no user name and password are set for $HOST"
project /tmp/smb-test-main-nofile.log --no-xr --media="$FILM" --smb-user="$SMB_USER" --smb-password-file=/nonexistent/password --quit-after=5
expect "an unreadable password file stops with an error" /tmp/smb-test-main-nofile.log "can't read the password file /nonexistent/password"
rm -f "$PWFILE"

echo
if [ "$FAILS" -eq 0 ]; then echo "SMB TESTS: PASS"; else echo "SMB TESTS: FAIL ($FAILS)"; fi
exit $(( FAILS > 0 ))
