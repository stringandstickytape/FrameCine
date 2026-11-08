#!/bin/bash
# Starts the player in the headset. Arguments after the launcher go to the app (see USAGE.md), e.g.
#   ./run.sh --file=/home/steamos/Videos/film.mkv --env=cinema
# The display and runtime folder default to the headset's session; the log goes to ~/.local/state/vr-video-player.
# (tools/package.sh copies this file into the package as run.sh; tools/test_player_run.sh tests it.)
#
# Updates (docs/framedrop.md, "Our own updates"). The player stages a new version in
# ${XDG_DATA_HOME:-~/.local/share}/vr-video-player/update/new and writes new.complete last. Before the engine
# starts, this script swaps it in: this folder (wherever it is) moves to update/old (one level) and new/ takes its
# place; then the new run.sh runs. The new version writes ~/.local/state/vr-video-player/started when its first
# frame shows. A swapped version that was launched once and never wrote it is rolled back at the next start, and its
# version goes into bad-versions, so the player does not fetch it again. A new/ without new.complete is deleted.
# No network here: only local moves. Each step is one line in update.log.
#
# The whole script is functions, read in full before the last line runs them, so moving this folder (and this
# file with it) during the swap cannot change what bash reads next.

update_log() {
  printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$ST/update.log"
}

version_of() {
  sed -n 's/^version v\{0,1\}\([0-9][0-9.]*\).*/\1/p' "$1/VERSION" 2>/dev/null | head -1
}

# Rolls back or swaps in, then runs the right run.sh (exec); returns when this folder is the one to start.
updates() {
  if [ -f "$ST/swapped" ]; then
    if [ -f "$ST/started" ]; then
      update_log "$(sed -n 's/^new //p' "$ST/swapped") started: kept"
      rm -f "$ST/swapped" "$ST/started"
    elif grep -qx launched "$ST/swapped"; then
      local bad
      bad=$(sed -n 's/^new //p' "$ST/swapped")
      [ -n "$bad" ] && printf '%s\n' "$bad" >> "$ST/bad-versions"
      if [ -x "$UPD/old/run.sh" ]; then
        rm -rf "$UPD/failed"
        if mv "$HERE" "$UPD/failed"; then
          if mv "$UPD/old" "$HERE"; then
            rm -f "$ST/swapped"
            update_log "$bad showed no first frame: rolled back to $(version_of "$HERE")"
            rm -rf "$UPD/failed"
            exec "$HERE/run.sh" "$@"
          fi
          mv "$UPD/failed" "$HERE"
        fi
        update_log "$bad showed no first frame; the rollback failed"
      else
        update_log "$bad showed no first frame; no old install to go back to"
      fi
      rm -f "$ST/swapped"
    else
      # The first launch of the version just swapped in: it must show a frame before the next start.
      printf 'launched\n' >> "$ST/swapped"
      return 0
    fi
  fi
  if [ -d "$UPD/new" ] && [ ! -f "$UPD/new.complete" ]; then
    rm -rf "$UPD/new"
    update_log "a staged update without new.complete: deleted"
  fi
  [ -f "$UPD/new.complete" ] || return 0
  local newv oldv
  newv=$(head -1 "$UPD/new.complete")
  oldv=$(version_of "$HERE")
  if [ ! -x "$UPD/new/run.sh" ] || [ ! -x "$UPD/new/bin/vr-video-player-engine" ] \
      || grep -qxF "$newv" "$ST/bad-versions" 2>/dev/null; then
    rm -rf "$UPD/new" "$UPD/new.complete"
    update_log "staged $newv is not complete or was rolled back before: deleted"
    return 0
  fi
  # Only forwards, and only over a release: a folder installed again by hand since the stage (a newer version, or a
  # build named by its commit) is not replaced.
  if [ -z "$oldv" ] || [ "$newv" = "$oldv" ] \
      || [ "$(printf '%s\n%s\n' "$oldv" "$newv" | sort -V | tail -1)" != "$newv" ]; then
    rm -rf "$UPD/new" "$UPD/new.complete"
    update_log "staged $newv is not newer than ${oldv:-this build}: deleted"
    return 0
  fi
  rm -rf "$UPD/old"
  rm -f "$ST/started"
  if ! mv "$HERE" "$UPD/old"; then
    update_log "swap to $newv failed: $HERE did not move"
    return 0
  fi
  if ! mv "$UPD/new" "$HERE"; then
    mv "$UPD/old" "$HERE"
    update_log "swap to $newv failed: new/ did not move; $oldv stays"
    return 0
  fi
  rm -f "$UPD/new.complete"
  printf 'new %s\nold %s\n' "$newv" "$oldv" > "$ST/swapped"
  update_log "swapped in $newv (was $oldv)"
  exec "$HERE/run.sh" "$@"
}

main() {
  HERE=$(cd "$(dirname "$0")" && pwd -P)
  export DISPLAY=${DISPLAY:-:0}
  export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
  ST=${XDG_STATE_HOME:-$HOME/.local/state}/vr-video-player
  UPD=${XDG_DATA_HOME:-$HOME/.local/share}/vr-video-player/update
  LOGDIR=$ST
  mkdir -p "$LOGDIR"
  updates "$@"
  [ -f "$LOGDIR/last.log" ] && mv -f "$LOGDIR/last.log" "$LOGDIR/previous.log"
  # --hands (a spike, docs/xr-spikes.md): hand tracking is an engine start-up setting, so it is switched on here, in
  # the app's override file, before the engine starts. The app removes the file on a start without --hands. A file
  # with other settings in it is left alone.
  local ovr="${XDG_DATA_HOME:-$HOME/.local/share}/godot/app_userdata/VR Video Player/xr_override.cfg"
  case " $* " in
    *" --hands "*)
      if [ ! -f "$ovr" ] || ! grep -qvE '^(\[xr\]|openxr/extensions/hand_tracking[a-z_]*=true)?$' "$ovr"; then
        mkdir -p "$(dirname "$ovr")"
        printf '[xr]\n\nopenxr/extensions/hand_tracking=true\nopenxr/extensions/hand_tracking_unobstructed_data_source=true\nopenxr/extensions/hand_tracking_controller_data_source=true\n' > "$ovr"
      fi ;;
  esac
  cd "$HERE" || exit 1
  exec "$HERE/bin/vr-video-player-engine" --path "$HERE/app" --display-driver x11 --xr-mode on -- "$@" \
    > "$LOGDIR/last.log" 2>&1
}

main "$@"; exit $?
