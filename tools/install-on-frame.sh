#!/usr/bin/env bash
# Installs a release tarball (tools/package.sh) on the headset over ssh, with no root (docs/packaging.md).
# PC side; run from Git Bash or WSL.
#
#   tools/install-on-frame.sh [TARBALL] [--dir DIR] [--steam] [--uninstall]
#
#   TARBALL      default: the newest build/dist/framecine-*-arm64.tar.gz
#   --dir DIR    install folder on the headset, relative to the home folder or absolute (default framecine)
#   --steam      also add a non-Steam shortcut to the Steam library (tools/steam_shortcuts.py, run on the headset;
#                it backs up shortcuts.vdf first). Untested on the device. Restart Steam to see it.
#   --uninstall  remove the folder, its .old backup, the menu entry and (with --steam) the shortcut
#
# Environment: FRAME_HOST (default "frame", an ssh config entry). FRAME_HOST=local runs the same steps on this
# machine (for a test in WSL or on a Linux PC: HOME decides where it goes).
#
# What it does on the headset: unpacks into DIR (the previous install is kept as DIR.old, one level), writes
# ~/.local/share/applications/framecine.desktop (and a copy on ~/Desktop when that folder exists), and checks
# that the engine starts (--version). Settings and the log are outside DIR, so they survive an update.
set -euo pipefail

HOST=${FRAME_HOST:-frame}
REPO=$(cd "$(dirname "$0")/.." && pwd)
TARBALL=""
DIR=framecine
STEAM=0
UNINSTALL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) DIR=$2; shift ;;
    --steam) STEAM=1 ;;
    --uninstall) UNINSTALL=1 ;;
    -h|--help) sed -n '2,21p' "$0"; exit 0 ;;
    -*) echo "unknown argument: $1" >&2; exit 2 ;;
    *) TARBALL=$1 ;;
  esac
  shift
done
case "$DIR" in *[!A-Za-z0-9._/-]*) echo "--dir: letters, digits, . _ - / only" >&2; exit 2 ;; esac

remote() {  # runs stdin with bash on the headset (or here, for FRAME_HOST=local)
  if [ "$HOST" = local ]; then bash -s -- "$@"; else ssh "$HOST" bash -s -- "$@"; fi
}

if [ "$UNINSTALL" = 0 ]; then
  if [ -z "$TARBALL" ]; then
    TARBALL=$(ls -t "$REPO"/build/dist/framecine-*-arm64.tar.gz 2>/dev/null | head -1 || true)
  fi
  [ -n "$TARBALL" ] && [ -f "$TARBALL" ] || { echo "no tarball; run tools/package.sh first" >&2; exit 1; }
  echo "copying $(basename "$TARBALL") to $HOST"
  if [ "$HOST" = local ]; then
    mkdir -p "$HOME/.cache/framecine-install"
    cp "$TARBALL" "$HOME/.cache/framecine-install/package.tar.gz"
  else
    ssh "$HOST" 'mkdir -p ~/.cache/framecine-install && cat > ~/.cache/framecine-install/package.tar.gz' \
      < "$TARBALL"
  fi
fi

remote "$DIR" "$STEAM" "$UNINSTALL" <<'REMOTE'
set -eu
DIR=$1; STEAM=$2; UNINSTALL=$3
case "$DIR" in /*) ;; *) DIR=$HOME/$DIR ;; esac
APPS=$HOME/.local/share/applications
ENTRY=framecine.desktop
PKG=$HOME/.cache/framecine-install/package.tar.gz

if [ "$UNINSTALL" = 1 ]; then
  if [ "$STEAM" = 1 ]; then
    if [ -f "$DIR/tools/steam_shortcuts.py" ]; then
      python3 "$DIR/tools/steam_shortcuts.py" --remove --exe "$DIR/run.sh" || echo "shortcut not removed"
    else
      echo "no tools/steam_shortcuts.py in $DIR: shortcut not removed"
    fi
  fi
  rm -rf "$DIR" "$DIR.old"
  rm -f "$APPS/$ENTRY" "$HOME/Desktop/$ENTRY"
  echo "removed $DIR and the menu entry (settings in ~/.local/share/godot/app_userdata are kept)"
  exit 0
fi

mkdir -p "$(dirname "$DIR")"
STAGE=$(mktemp -d "$DIR.new.XXXXXX")
trap 'rm -rf "$STAGE"; rm -f "$PKG"' EXIT
tar -xzf "$PKG" -C "$STAGE"
TOP=$(ls "$STAGE")
[ "$(printf '%s\n' "$TOP" | wc -l)" = 1 ] && [ -x "$STAGE/$TOP/run.sh" ] || { echo "not a player package" >&2; exit 1; }

# The engine must start on this machine (right architecture, libraries present) before the old install is moved.
VER=$(timeout 30 "$STAGE/$TOP/bin/framecine-engine" --version 2>/dev/null) && VER=$(printf '%s\n' "$VER" | tail -1)
if [ -z "$VER" ]; then
  echo "the engine does not start here (wrong architecture?): install stopped, nothing changed" >&2
  exit 1
fi

if [ -e "$DIR" ]; then
  rm -rf "$DIR.old"
  mv "$DIR" "$DIR.old"
fi
mv "$STAGE/$TOP" "$DIR"
rm -f "$PKG"

mkdir -p "$APPS"
sed "s|@DIR@|$DIR|g" "$DIR/framecine.desktop.in" > "$APPS/$ENTRY"
chmod +x "$APPS/$ENTRY"
if [ -d "$HOME/Desktop" ]; then
  cp "$APPS/$ENTRY" "$HOME/Desktop/$ENTRY"
  chmod +x "$HOME/Desktop/$ENTRY"
fi
command -v update-desktop-database > /dev/null 2>&1 && update-desktop-database "$APPS" 2>/dev/null || true

if [ "$STEAM" = 1 ]; then
  python3 "$DIR/tools/steam_shortcuts.py" --add --name "FrameCine" --exe "$DIR/run.sh" --start-dir "$DIR" \
    --icon "$DIR/icon.svg" || echo "shortcut not added (see above); the menu entry is in place"
  echo "restart Steam to see the shortcut"
fi
echo "installed in $DIR (engine $VER)"
sed 's/^/  /' "$DIR/VERSION"
[ -e "$DIR.old" ] && echo "previous install kept in $DIR.old"
exit 0
REMOTE
