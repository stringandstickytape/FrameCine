#!/usr/bin/env bash
# Copies the app folder to the headset, for a run or for hot-reload (--dev). PC side; run from Git Bash or WSL.
#
#   tools/push-app.sh            copy everything (rsync when both ends have it, else tar over ssh)
#   tools/push-app.sh --watch    copy everything once, then every changed file within about a second
#   tools/push-app.sh --dry-run  list what would be copied
#
# Environment: FRAME_HOST (default "frame", an ssh config entry), FRAME_APP_DIR (default "spike03/app", relative to
# the device user's home). Skips .godot/ and docs/ (screenshots and reference models are not needed on the device).
# Never deletes anything on the device. Times are kept, so the app's watcher sees each change once.
set -euo pipefail

HOST=${FRAME_HOST:-frame}
DEST=${FRAME_APP_DIR:-spike03/app}
REPO=$(cd "$(dirname "$0")/.." && pwd)
SRC="$REPO/app"
WATCH=0
DRY=0
for a in "$@"; do
  case "$a" in
    --watch) WATCH=1 ;;
    --dry-run) DRY=1 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "unknown argument: $a" >&2; exit 2 ;;
  esac
done

# Files of app/ (relative, ./x/y.gd), skipping the excluded folders; with an argument, only those newer than it.
list_files() {
  (cd "$SRC" && find . \( -path ./.godot -o -path ./docs \) -prune -o -type f ${1:+-newer "$1"} -print)
}

# tar the given relative paths (stdin, one per line) to the device; tar keeps their times.
send_tar() {
  local files
  files=$(cat)
  [ -n "$files" ] || return 0
  if [ "$DRY" = 1 ]; then
    printf '%s\n' "$files"
    return 0
  fi
  printf '%s\n' "$files" | (cd "$SRC" && tar -cf - -T -) | ssh "$HOST" "mkdir -p '$DEST' && tar -xf - -C '$DEST'"
  printf '%s\n' "$files" | sed "s|^\./|pushed $DEST/|"
}

push_all() {
  if command -v rsync > /dev/null && ssh "$HOST" 'command -v rsync' > /dev/null 2>&1; then
    local dry=()
    [ "$DRY" = 1 ] && dry=(--dry-run)
    ssh "$HOST" "mkdir -p '$DEST'"
    rsync -rt --itemize-changes "${dry[@]}" --exclude=/.godot --exclude=/docs "$SRC/" "$HOST:$DEST/"
  else
    list_files | send_tar
  fi
}

# Changes made while the first copy runs are caught by the first watch round.
MARK=$(mktemp)
NEXT=$(mktemp)
trap 'rm -f "$MARK" "$NEXT"' EXIT
push_all
[ "$WATCH" = 1 ] || exit 0
echo "Watching $SRC (Ctrl+C to stop)"
while true; do
  sleep 1
  touch "$NEXT"
  list_files "$MARK" | send_tar || echo "push failed; retrying on the next change" >&2
  mv "$NEXT" "$MARK"
  NEXT=$(mktemp)
done
