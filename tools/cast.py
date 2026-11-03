#!/usr/bin/env python3
"""Cast from the PC (idea #43): play a file on the headset from the PC. Python 3.8+, standard library only.

It sends `open` over the dev link, through a running `python tools/listener.py serve` (docs/dev/control-protocol.md),
so the headset must be connected to the listener (--listener=<PC address>). A file on the PC is played straight from
the PC's file share: its path is mapped to smb://<host>/<share>/... through the PC's own shares (Windows: Get-SmbShare)
or --map. The host name is the one the headset already has saved under Network, so its credentials are used.

    python tools/cast.py D:/Videos/film.mkv            # a PC file in a shared folder -> smb://<host>/Videos/film.mkv
    python tools/cast.py smb://nas/films/a.mkv         # an smb:// URL as it is
    python tools/cast.py /home/steamos/films/a.mkv     # a path on the headset as it is
    python tools/cast.py https://example.com/page      # a web page on the screen (Browser source)
    python tools/cast.py film.mkv --seek 600           # and start at 10 minutes
    python tools/cast.py --watch D:/Videos/_cast       # cast each video file that appears in a folder
    python tools/cast.py --install-sendto              # "Play on headset" in Explorer's Send to menu
    python tools/cast.py --install-desktop             # a desktop icon to drop files on

Options: --host NAME (the SMB host as the headset knows it), --map LOCAL=smb://host/share (repeatable; checked before
the PC's shares), --control-port (default 47802), --dry-run (print the URL, send nothing).
"""

import argparse
import json
import ntpath
import os
import socket
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import listener  # noqa: E402  (same folder; stdlib only)

VIDEO_EXTENSIONS = {"mkv", "mp4", "m4v", "mov", "webm", "avi", "ts", "m2ts", "mts", "wmv", "mpg", "mpeg", "h264",
                    "264", "avc", "h265", "265", "hevc"}
LAUNCHER_NAME = "Play on headset.cmd"


def is_video(path):
    return path.rsplit(".", 1)[-1].lower() in VIDEO_EXTENSIONS if "." in path else False


def norm_local(path):
    """Absolute, forward slashes, no trailing slash (except a drive root): C:/Films/a.mkv."""
    p = os.path.abspath(path).replace("\\", "/")
    return p.rstrip("/") if len(p) > 3 else p


def windows_shares():
    """{share name: local folder} of this PC (Windows), without the hidden admin shares; {} elsewhere."""
    if os.name != "nt":
        return {}
    cmd = ["powershell", "-NoProfile", "-NonInteractive", "-Command",
           "Get-SmbShare | Where-Object { -not $_.Special } | Select-Object Name, Path | ConvertTo-Json"]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=20).stdout.strip()
        data = json.loads(out) if out else []
    except (OSError, ValueError, subprocess.SubprocessError):
        return {}
    if isinstance(data, dict):
        data = [data]
    return {d["Name"]: d["Path"] for d in data if d.get("Path")}


def map_path(local, maps, shares, host):
    """smb:// URL for a local file, or None. maps: [(local folder, smb://host/share)] tried first; shares: {name: local
    folder} on `host`. The most specific (longest) folder wins."""
    p = norm_local(local)
    candidates = []
    for folder, url in maps:
        candidates.append((norm_local(folder), url.rstrip("/")))
    if host:
        for name, folder in shares.items():
            candidates.append((norm_local(folder), "smb://%s/%s" % (host, name)))
    best = None
    for folder, url in candidates:
        f = folder.rstrip("/")
        if p.lower() == f.lower() or p.lower().startswith(f.lower() + "/"):
            if best is None or len(f) > len(best[0]):
                best = (f, url)
    if best is None:
        return None
    rest = p[len(best[0]):].lstrip("/")
    return best[1] + ("/" + rest if rest else "")


def pc_names():
    """Names and addresses this PC is known by (lower case)."""
    names = {socket.gethostname().lower(), socket.getfqdn().lower()}
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None):
            names.add(info[4][0].lower())
    except OSError:
        pass
    return names


def control(req, port):
    try:
        return listener.control(req, port)
    except OSError:
        return {"ok": False, "error": "no listener on 127.0.0.1:%d; start one with: python tools/listener.py serve"
                % port}


def saved_hosts(port):
    """The hosts saved on the headset (Network place): ["desktop-pc", "nas"] as written there."""
    r = control({"op": "send", "cmd": "list_dir", "args": {"path": "network://"}, "timeout": 10}, port)
    if not r.get("ok"):
        return []
    return [e["path"].replace("smb://", "").split("/")[0] for e in r["result"].get("entries", [])]


def pick_host(port, explicit):
    """The SMB host string to use for this PC: --host, else the saved host on the headset that names this PC."""
    if explicit:
        return explicit, None
    mine = pc_names()
    for h in saved_hosts(port):
        if h.lower() in mine or h.lower().split(".")[0] in mine:
            return h, None
    return socket.gethostname(), ("this PC (%s) is not a saved host on the headset; add it under Network > Add host "
                                  "so the headset has the user name and password" % socket.gethostname())


def resolve(target, args, port):
    """(kind, value, note): kind "url" (web page) or "path" (open)."""
    t = target.strip()
    if t.startswith(("http://", "https://")):
        return "url", t, None
    if t.startswith(("smb://", "stub://", "browser://", "window://")) or (t.startswith("/") and not os.path.exists(t)):
        return "path", t, None
    if not os.path.exists(t):
        return None, None, "no such file on the PC: %s" % t
    maps = []
    for m in args.map or []:
        folder, eq, url = m.partition("=")
        if eq:
            maps.append((folder, url))
    host, note = pick_host(port, args.host)
    url = map_path(t, maps, windows_shares(), host)
    if url is None:
        return None, None, ("%s is not in a shared folder; share the folder (or a parent) on the PC, or give "
                            "--map LOCAL=smb://host/share" % norm_local(t))
    return "path", url, note


def cast(target, args):
    kind, value, note = resolve(target, args, args.control_port)
    if kind is None:
        print(note, file=sys.stderr)
        return 1
    if note:
        print("note: " + note, file=sys.stderr)
    if args.dry_run:
        print(value)
        return 0
    if kind == "url":
        req = {"op": "send", "cmd": "open_url", "args": {"url": value}, "timeout": 15}
    else:
        req = {"op": "send", "cmd": "open", "args": {"path": value}, "timeout": 30}
    print("casting %s" % value)
    r = control(req, args.control_port)
    if not r.get("ok"):
        print("failed: %s" % r.get("error"), file=sys.stderr)
        return 1
    res = r.get("result") or {}
    if res.get("opening"):
        print("the headset is still connecting to %s" % res["opening"])
    else:
        print("playing: %s" % (res.get("title") or value) + ("  (%s)" % res["note"] if res.get("note") else ""))
    if args.seek is not None and kind == "path":
        s = control({"op": "send", "cmd": "seek", "args": {"seconds": args.seek}, "timeout": 10}, args.control_port)
        if not s.get("ok"):
            print("seek failed: %s" % s.get("error"), file=sys.stderr)
    return 0


def watch(folder, args):
    """Casts each video file that appears in `folder` once its size has been stable for 2 s."""
    folder = os.path.abspath(folder)
    os.makedirs(folder, exist_ok=True)
    seen = {f: None for f in os.listdir(folder)}
    pending = {}
    print("watching %s for new video files (Ctrl+C to stop)" % folder)
    try:
        while True:
            time.sleep(1)
            for f in os.listdir(folder):
                path = os.path.join(folder, f)
                if f in seen or not os.path.isfile(path) or not is_video(f):
                    continue
                size = os.path.getsize(path)
                last = pending.get(f)
                if last is None or last[0] != size:
                    pending[f] = (size, time.time())
                elif time.time() - last[1] >= 2:
                    seen[f] = size
                    pending.pop(f, None)
                    cast(path, args)
    except KeyboardInterrupt:
        return 0


def install_launcher(where):
    """Writes a "Play on headset" launcher into Send to or onto the desktop (Windows)."""
    if os.name != "nt":
        print("only on Windows", file=sys.stderr)
        return 1
    if where == "sendto":
        folder = os.path.join(os.environ["APPDATA"], "Microsoft", "Windows", "SendTo")
    else:
        folder = os.path.join(os.path.expanduser("~"), "Desktop")
    path = os.path.join(folder, LAUNCHER_NAME)
    script = ntpath.normpath(os.path.abspath(__file__))
    with open(path, "w", encoding="utf-8", newline="\r\n") as f:
        f.write("@echo off\n")
        f.write("rem Plays the dropped or sent file on the headset (tools/cast.py; needs listener.py serve).\n")
        f.write('"%s" "%s" %%*\n' % (sys.executable, script))
        f.write("if errorlevel 1 pause\n")
    print("wrote %s" % path)
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("targets", nargs="*", help="files, smb:// URLs, headset paths or web pages (the first plays)")
    ap.add_argument("--seek", type=float, help="start at this many seconds")
    ap.add_argument("--host", help="the SMB host name as the headset has it saved")
    ap.add_argument("--map", action="append", metavar="LOCAL=smb://host/share")
    ap.add_argument("--watch", metavar="DIR", help="cast each video file that appears in DIR")
    ap.add_argument("--install-sendto", action="store_true")
    ap.add_argument("--install-desktop", action="store_true")
    ap.add_argument("--dry-run", action="store_true", help="print the URL, send nothing")
    ap.add_argument("--control-port", type=int, default=listener.CONTROL_PORT)
    a = ap.parse_args(argv)
    # Line by line, so a log of --watch shows each cast as it happens.
    sys.stdout.reconfigure(line_buffering=True)
    if a.install_sendto:
        return install_launcher("sendto")
    if a.install_desktop:
        return install_launcher("desktop")
    if a.watch:
        return watch(a.watch, a)
    if not a.targets:
        ap.error("give a file, URL or --watch DIR")
    # Several files (a multi-select Send to): the first plays; the headset makes its folder the playlist.
    return cast(a.targets[0], a)


if __name__ == "__main__":
    sys.exit(main())
