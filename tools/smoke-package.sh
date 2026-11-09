#!/usr/bin/env bash
# Starts the app folder of a release package (tools/package.sh) with the desktop engine, headless, for some seconds,
# and fails on any script that does not load. Catches a package that leaves out a file the app needs (2026-11-09:
# app/tools/make_pane_theme.gd was left out, so main.gd did not compile on the headset).
#
#   tools/smoke-package.sh PACKAGE.tar.gz [ENGINE]
#
# Runs where the x86_64 engine runs (WSL or Linux). ENGINE defaults to the pc-windows fork build in ~/src.
# tools/release.sh runs it through WSL.
set -euo pipefail
PKG=$1
ENGINE=${2:-$HOME/src/godot-pcwindows/bin/godot.linuxbsd.template_debug.x86_64}
[ -f "$PKG" ] || { echo "smoke: no package $PKG" >&2; exit 2; }
[ -x "$ENGINE" ] || { echo "smoke: no engine $ENGINE" >&2; exit 2; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
tar -xzf "$PKG" -C "$TMP"
APP=$(find "$TMP" -mindepth 2 -maxdepth 2 -type d -name app | head -1)
[ -n "$APP" ] || { echo "smoke: no app/ in the package" >&2; exit 1; }
# Its own data folder, so the run neither reads nor changes this machine's settings.
export XDG_DATA_HOME=$TMP/data XDG_STATE_HOME=$TMP/state XDG_CONFIG_HOME=$TMP/config
LOG=$TMP/smoke.log
timeout 120 "$ENGINE" --headless --xr-mode off --path "$APP" --quit-after 900 > "$LOG" 2>&1 || true
if grep -E "Parse Error|Failed to load script|Compilation failed|Preload file .* does not exist|Cannot open file" "$LOG" \
    | grep -v "global script cache" > "$TMP/bad"; then
  echo "smoke: the packaged app does not load:" >&2
  head -20 "$TMP/bad" >&2
  exit 1
fi
grep -q -E "main\.gd|FrameCine|OpenXR|Recentered|Dev link|HW video" "$LOG" || {
  echo "smoke: the app printed nothing it normally prints; the log:" >&2
  tail -20 "$LOG" >&2
  exit 1
}
echo "smoke: the packaged app starts and every script loads ($(grep -c . "$LOG") log lines)"
