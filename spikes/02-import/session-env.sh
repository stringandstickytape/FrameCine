#!/bin/bash
# Find the display session on the Frame so a Godot window can be opened from an ssh shell.
echo "-- sockets in /run/user/$(id -u)"
ls -la "/run/user/$(id -u)/" | grep -iE 'wayland|gamescope|pipewire|bus'
echo "-- X11 sockets"; ls -l /tmp/.X11-unix/ 2>&1
echo "-- processes"
ps -eo pid,user,args | grep -iE 'gamescope|vrcompositor|vrserver|vrmonitor|Xwayland|steamwebhelper -' | grep -v grep | cut -c1-200
echo "-- display env of gamescope / vrcompositor / steam"
for name in gamescope vrcompositor steam; do
  for p in $(pgrep -x "$name" | head -2); do
    echo "[$name pid $p]"
    tr '\0' '\n' < "/proc/$p/environ" 2>/dev/null | grep -E '^(DISPLAY|WAYLAND_DISPLAY|XDG_RUNTIME_DIR|XDG_SESSION_TYPE|GAMESCOPE_WAYLAND_DISPLAY|XDG_CURRENT_DESKTOP|SDL_VIDEODRIVER)=' | sed 's/^/   /'
  done
done
echo "-- my env"; env | grep -E '^(DISPLAY|WAYLAND_DISPLAY|XDG_RUNTIME_DIR)=' || echo "   (none set in ssh shell)"
echo "-- loginctl"; loginctl list-sessions --no-legend 2>&1 | head -5
