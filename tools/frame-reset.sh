#!/usr/bin/env bash
# Removes this app and everything it left on the headset, so that an install test starts from a clean headset.
# PC side; run from Git Bash or WSL. A dry run unless --yes: it lists what it would remove, with sizes.
#
#   tools/frame-reset.sh          # list only
#   tools/frame-reset.sh --yes    # stop the player, remove, then restart Steam so the library entry goes
#
# Removed: the installs (release, dev and spike folders), the player's data (settings, resume, bakes, models,
# logs), its library entries (non-Steam shortcuts and Devkit Games that start it), its menu entries, the share
# login (~/.smb-password), the Android side (~/Android, ~/.android, Lepton contexts), Claude Code and Codex.
# Kept: ~/Videos (the library), ~/Downloads, ssh access, Steam and other apps, and command-line tools the agent
# terminal can use (yt-dlp, deno, get_iplayer): they are not part of an install.
#
# Environment: FRAME_HOST (default "frame", an ssh config entry).
set -euo pipefail

HOST=${FRAME_HOST:-frame}
YES=0
case "${1:-}" in
  --yes) YES=1 ;;
  "") ;;
  -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
  *) echo "unknown argument: $1" >&2; exit 2 ;;
esac

ssh "$HOST" "YES=$YES bash -s" <<'REMOTE'
set -uo pipefail
cd "$HOME"
shopt -s nullglob

paths=(
  # installs
  vr-video-player vr-video-player.old vr-video-player.new vr-video-player.new.part
  spike01 spike02 spike03 spike04 spike05 iris-module
  # the player's data, logs and dev leftovers
  .local/share/godot/app_userdata/"VR Video Player"
  .local/share/godot/app_userdata/"Frame VR Player"
  .local/share/godot/app_userdata/"Spike "*
  .local/share/godot/app_userdata/fovtest
  .local/share/vrvp-user-objects
  .local/state/vr-video-player
  q10c-out q10c-out-p010 vr-player-dump vr-player-snaps turn.start turn.wav whisper-bench-*.tsv
  Claude
  # menu entries
  .local/share/applications/vr-video-player.desktop Desktop/vr-video-player.desktop
  # the share login
  .smb-password
  # the Android side
  Android .android .local/share/lepton/contexts
  # Claude Code
  .local/bin/claude .local/share/claude .claude .claude.json .local/state/claude .cache/claude
  .cache/claude-cli-nodejs .local/share/applications/claude-code-url-handler.desktop
  # Codex
  .local/bin/codex .codex
)
# Devkit Games that start the player (FrameDrop installs land here), with their argv/env/settings files.
for d in devkit-game/*/; do
  if [ -e "$d/run.sh" ] || [ -e "$d/bin/vr-video-player-engine" ]; then
    g=$(basename "$d"); paths+=("devkit-game/$g" devkit-game/"$g"-*.json)
  fi
done
paths+=(.local/share/Steam/userdata/*/config/shortcuts.vdf.bak-*)

found=()
for p in "${paths[@]}"; do [ -e "$p" ] || [ -L "$p" ] && found+=("$p"); done

echo "== to remove"
for p in "${found[@]}"; do printf '%8s  ~/%s\n' "$(du -sh -- "$p" 2>/dev/null | cut -f1)" "$p"; done
[ ${#found[@]} -eq 0 ] && echo "  (nothing)"

# Library entries: non-Steam shortcuts whose Exe is one of ours.
SC=$(cat <<'PY'
import glob, os, re, sys
ours = re.compile(r'(spike0\d/|vr-video-player|devkit-game/.*/run\.sh|godot_player)')
for f in glob.glob(os.path.expanduser('~/.local/share/Steam/userdata/*/config/shortcuts.vdf')):
    b = open(f, 'rb').read()
    for name, exe in zip(re.findall(rb'\x01(?:AppName|appname)\x00([^\x00]*)\x00', b),
                         re.findall(rb'\x01(?:Exe|exe)\x00([^\x00]*)\x00', b)):
        e = exe.decode(errors='replace').strip('"')
        if ours.search(e):
            print(e)
PY
)
mapfile -t exes < <(python3 -c "$SC")
echo "== library shortcuts to remove: ${#exes[@]}"
for e in "${exes[@]}"; do echo "  -> ${e/#$HOME/~}"; done

if [ "$YES" != 1 ]; then echo "(dry run: --yes removes these)"; exit 0; fi

echo "== stopping the player"
pkill -f -- '--path app --display-driver' 2>/dev/null; pkill -f 'spike0[0-9]/' 2>/dev/null; pkill -f 'vr-video-player' 2>/dev/null
pkill -f 'whisper-server' 2>/dev/null; sleep 2

for p in "${found[@]}"; do rm -rf -- "$p"; done
rmdir .local/share/godot/app_userdata .local/share/godot 2>/dev/null

if [ ${#exes[@]} -gt 0 ]; then
  RM=$(cat <<'PY'
import glob, os, re, struct, sys
# Minimal binary-KeyValues edit: drop the shortcut maps whose Exe matches, renumber the rest.
def rd(b, i):
    out = []
    while True:
        t = b[i]; i += 1
        if t == 8: return out, i
        j = b.index(0, i); k = b[i:j].decode('utf-8', 'replace'); i = j + 1
        if t == 0: v, i = rd(b, i)
        elif t == 1: j = b.index(0, i); v = b[i:j]; i = j + 1
        elif t in (2, 3): v = b[i:i+4]; i += 4
        elif t in (7, 10): v = b[i:i+8]; i += 8
        else: raise ValueError(t)
        out.append((t, k, v))
def wr(items):
    o = bytearray()
    for t, k, v in items:
        o.append(t); o += k.encode() + b'\0'
        o += (wr(v) + b'\x08') if t == 0 else (v + b'\0' if t == 1 else v)
    return bytes(o)
ours = re.compile(r'(spike0\d/|vr-video-player|devkit-game/.*/run\.sh|godot_player)')
for f in glob.glob(os.path.expanduser('~/.local/share/Steam/userdata/*/config/shortcuts.vdf')):
    b = open(f, 'rb').read()
    root, _ = rd(b, 0)
    (t, k, sc), = root
    keep = [e for e in sc if not any(kk.lower() == 'exe' and ours.search(vv.decode('utf-8', 'replace'))
                                     for tt, kk, vv in e[2])]
    if len(keep) == len(sc): continue
    keep = [(0, str(n), e[2]) for n, e in enumerate(keep)]
    data = wr([(0, k, keep)]) + b'\x08'
    rd(data, 0)  # parses back
    tmp = f + '.tmp'; open(tmp, 'wb').write(data); os.replace(tmp, f)
    print('removed', len(sc) - len(keep), 'from', f.replace(os.path.expanduser('~'), '~'))
PY
)
  python3 -c "$RM"
  echo "== restarting Steam (it reads the library entries at start)"
  XDG_RUNTIME_DIR=/run/user/$(id -u) DISPLAY=:0 steam -shutdown >/dev/null 2>&1 || true
  sleep 15
  pgrep -x steam >/dev/null || (XDG_RUNTIME_DIR=/run/user/$(id -u) DISPLAY=:0 nohup steam >/dev/null 2>&1 &)
  sleep 5
  mapfile -t left < <(python3 -c "$SC")
  echo "== library shortcuts left: ${#left[@]}"
fi
echo "== done"
REMOTE
