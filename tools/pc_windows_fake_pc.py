#!/usr/bin/env python3
"""A fake PC for the headset's PC windows service (docs/pc-windows.md), for app/tests/test_pc_windows.gd.

Speaks the protocol as the PC app does: discovery over UDP, TLS checked against the pin from discovery, pairing with
the code (or the token kept from an earlier run), the window list with a thumbnail, and on `open` a stream connection
sending a test clip's access units in PCW1 packets, paced at the clip's rate on one clock; on `sound` stream 0 with
AAC frames of a tone. Everything the headset sends is written to --log as JSON lines (mouse, key, text, focus,
quality, open, close, ...), so the test can check what reached the PC.

The windows it lists (each says how it streams):
  w:1a2b   HEVC 640x360, a moving test pattern with a frame counter
  w:c0ffee HEVC 640x360, then a config change to 480x270 after CONFIG_AFTER frames
  w:264    H.264 640x360
  w:e0d    HEVC, the stream connection closes after END_AFTER seconds
  m:0      a monitor, HEVC 640x360

Clips: --make-clips makes them once with ffmpeg (WSL's, else Windows' ffmpeg.exe through interop) into --clips.
Python 3 standard library only.

  python3 tools/pc_windows_fake_pc.py --make-clips
  python3 tools/pc_windows_fake_pc.py --host 127.0.0.1 --port 47913 --discover-only --log /tmp/pc.jsonl
  python3 tools/pc_windows_fake_pc.py --host 127.0.0.1 --port 47913 --code 123456 --token-file /tmp/tok --log ...
"""

import argparse
import base64
import hashlib
import json
import os
import shutil
import socket
import ssl
import struct
import subprocess
import sys
import threading
import time

CONFIG_AFTER = 45
END_AFTER = 1.5
FPS = 30.0
AAC_FRAME = 1024
RATE = 48000

WINDOWS = [
    {"id": "w:1a2b", "kind": "window", "title": "Test pattern", "app": "fake.exe", "w": 640, "h": 360, "clip": "a.hevc"},
    {"id": "w:c0ffee", "kind": "window", "title": "Resizing window", "app": "fake.exe", "w": 640, "h": 360,
     "clip": "a.hevc", "then": "b.hevc"},
    {"id": "w:264", "kind": "window", "title": "H.264 window", "app": "fake.exe", "w": 640, "h": 360, "clip": "a.h264"},
    {"id": "w:e0d", "kind": "window", "title": "Short stream", "app": "fake.exe", "w": 640, "h": 360, "clip": "a.hevc",
     "end": END_AFTER},
    {"id": "m:0", "kind": "monitor", "title": "Monitor 1", "app": "", "w": 640, "h": 360, "clip": "a.hevc"},
]

def pc_now():
    """The fake PC's one clock (QueryPerformanceCounter on the real one), in microseconds: far from the headset's."""
    return time.monotonic_ns() // 1000 + 123_456_789_000


# --- Clips ----------------------------------------------------------------------------------------------------------

def find_ffmpeg():
    return shutil.which("ffmpeg") or shutil.which("ffmpeg.exe")


def make_clips(folder):
    os.makedirs(folder, exist_ok=True)
    ff = find_ffmpeg()
    if ff is None:
        print("no ffmpeg: can't make the clips", file=sys.stderr)
        return 1
    x265 = "log-level=error:keyint=30:min-keyint=30:bframes=0:repeat-headers=1:scenecut=0"
    jobs = [
        ("a.hevc", ["-f", "lavfi", "-i", "testsrc=size=640x360:rate=30", "-t", "4", "-c:v", "libx265",
                    "-preset", "ultrafast", "-x265-params", x265, "-pix_fmt", "yuv420p", "-f", "hevc"]),
        ("b.hevc", ["-f", "lavfi", "-i", "testsrc=size=480x270:rate=30", "-t", "4", "-c:v", "libx265",
                    "-preset", "ultrafast", "-x265-params", x265, "-pix_fmt", "yuv420p", "-f", "hevc"]),
        ("a.h264", ["-f", "lavfi", "-i", "testsrc=size=640x360:rate=30", "-t", "4", "-c:v", "libx264",
                    "-preset", "ultrafast", "-bf", "0", "-g", "30", "-x264-params", "repeat-headers=1:scenecut=0",
                    "-pix_fmt", "yuv420p", "-f", "h264"]),
        ("tone.aac", ["-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000:duration=4", "-ac", "2",
                      "-c:a", "aac", "-b:a", "160k", "-f", "adts"]),
        ("thumb.jpg", ["-f", "lavfi", "-i", "testsrc=size=256x144:rate=1", "-frames:v", "1"]),
    ]
    for name, args in jobs:
        if os.path.exists(os.path.join(folder, name)):
            continue
        # Relative names with the folder as the working directory: Windows' ffmpeg.exe can't take a WSL path.
        r = subprocess.run([ff, "-hide_banner", "-loglevel", "error", "-y"] + args + [name], cwd=folder)
        if r.returncode != 0:
            print("ffmpeg failed on %s" % name, file=sys.stderr)
            return 1
    return 0


def nal_units(data):
    """(start, end) of each NAL unit's bytes (after its start code)."""
    out = []
    i = 0
    n = len(data)
    starts = []
    while i + 3 <= n:
        if data[i] == 0 and data[i + 1] == 0 and data[i + 2] == 1:
            starts.append(i + 3)
            i += 3
        else:
            i += 1
    for k, s in enumerate(starts):
        e = starts[k + 1] - 3 if k + 1 < len(starts) else n
        while e > s and data[e - 1] == 0:
            e -= 1
        out.append((s, e))
    return out


def access_units(data, hevc):
    """[(bytes, key)]: Annex B access units (4-byte start codes), split at each picture's first slice."""
    aus = []
    cur = []
    cur_vcl = False
    cur_key = False
    prefix = []
    for s, e in nal_units(data):
        nal = data[s:e]
        if hevc:
            t = (nal[0] >> 1) & 0x3F
            vcl = t < 32
            first = vcl and len(nal) > 2 and (nal[2] & 0x80) != 0
            key = 16 <= t <= 21
        else:
            t = nal[0] & 0x1F
            vcl = 1 <= t <= 5
            first = vcl and len(nal) > 1 and (nal[1] & 0x80) != 0
            key = t == 5
        if not vcl:
            if t == (35 if hevc else 9):
                continue  # access unit delimiters: our framing marks the units
            prefix.append(nal)
            continue
        if first and cur_vcl:
            aus.append((b"".join(b"\x00\x00\x00\x01" + x for x in cur), cur_key))
            cur = []
            cur_key = False
        cur += prefix + [nal]
        prefix = []
        cur_vcl = True
        cur_key = cur_key or key
    if cur:
        aus.append((b"".join(b"\x00\x00\x00\x01" + x for x in cur + prefix), cur_key))
    return aus


def adts_frames(data):
    out = []
    i = 0
    while i + 7 <= len(data):
        if data[i] != 0xFF or (data[i + 1] & 0xF0) != 0xF0:
            break
        length = ((data[i + 3] & 0x03) << 11) | (data[i + 4] << 3) | (data[i + 5] >> 5)
        if length < 7:
            break
        out.append(data[i:i + length])
        i += length
    return out


# --- The protocol ---------------------------------------------------------------------------------------------------

def packet(kind, flags, time_usec, payload):
    return b"PCW1" + struct.pack("<BBHqI", kind, flags, 0, time_usec, len(payload)) + payload


class Log:
    def __init__(self, path):
        self.path = path
        self.lock = threading.Lock()

    def write(self, obj):
        if not self.path:
            return
        obj = dict(obj)
        obj["at"] = time.time()
        with self.lock, open(self.path, "a", encoding="utf-8") as f:
            f.write(json.dumps(obj) + "\n")


def tls_connect(host, port, pin):
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE  # the pin below is the check
    ctx.minimum_version = ssl.TLSVersion.TLSv1_2
    raw = socket.create_connection((host, port), timeout=10)
    raw.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    s = ctx.wrap_socket(raw)
    der = s.getpeercert(binary_form=True)
    got = hashlib.sha256(der).hexdigest()
    if pin and got != pin:
        s.close()
        raise RuntimeError("pin mismatch")
    return s, got


def discover(host, port, name, log, tries=10):
    u = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    u.settimeout(0.4)
    msg = json.dumps({"t": "pcw_find", "v": 1, "pc": name}).encode()
    for _ in range(tries):
        u.sendto(msg, (host, port))
        try:
            data, _ = u.recvfrom(4096)
            reply = json.loads(data.decode())
            log.write({"t": "discovered", "reply": reply})
            return reply
        except socket.timeout:
            continue
    log.write({"t": "discovered", "reply": None})
    return None


class Fake:
    def __init__(self, args, log, pin, token):
        self.args = args
        self.log = log
        self.pin = pin
        self.token = token
        self.ctl = None
        self.wlock = threading.Lock()
        self.streams = {}
        self.stop = False
        clips = args.clips
        self.clips = {}
        for name in ("a.hevc", "b.hevc", "a.h264", "tone.aac", "thumb.jpg"):
            p = os.path.join(clips, name)
            if os.path.exists(p):
                with open(p, "rb") as f:
                    self.clips[name] = f.read()

    def send(self, obj):
        with self.wlock:
            self.ctl.sendall((json.dumps(obj) + "\n").encode())

    def windows(self):
        thumb = base64.b64encode(self.clips["thumb.jpg"]).decode() if "thumb.jpg" in self.clips else ""
        return [{"id": w["id"], "kind": w["kind"], "title": w["title"], "app": w["app"], "w": w["w"], "h": w["h"],
                 "thumb": thumb} for w in WINDOWS]

    def run(self):
        buf = b""
        self.ctl.settimeout(0.5)
        while not self.stop:
            try:
                d = self.ctl.recv(65536)
            except socket.timeout:
                continue
            except (ssl.SSLError, OSError):
                break
            if not d:
                break
            buf += d
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                if not line.strip():
                    continue
                m = json.loads(line.decode())
                self.handle(m)
        self.log.write({"t": "control_closed"})
        self.stop = True

    def handle(self, m):
        t = m.get("t")
        if t == "ping":
            self.send({"t": "pong", "n": m.get("n", 0)})
            return
        self.log.write({"t": "got", "msg": m})
        if t == "list":
            self.send({"t": "windows", "list": self.windows()})
        elif t == "open":
            w = next((x for x in WINDOWS if x["id"] == m.get("id")), None)
            if w is None:
                self.send({"t": "error", "what": "no such window", "id": m.get("id")})
                return
            n = int(m["stream"])
            th = threading.Thread(target=self.stream_video, args=(n, w), daemon=True)
            self.streams[n] = {"stop": False}
            th.start()
        elif t == "close":
            n = int(m.get("stream", -1))
            if n in self.streams:
                self.streams[n]["stop"] = True
        elif t == "sound":
            if m.get("on"):
                self.streams[0] = {"stop": False}
                threading.Thread(target=self.stream_sound, daemon=True).start()
            elif 0 in self.streams:
                self.streams[0]["stop"] = True

    def open_stream(self, n):
        s, _ = tls_connect(self.args.host, self.args.port, self.pin)
        s.sendall((json.dumps({"t": "stream", "v": 1, "token": self.token, "stream": n}) + "\n").encode())
        return s

    def stream_video(self, n, w):
        try:
            s = self.open_stream(n)
        except Exception as e:  # noqa: BLE001
            self.log.write({"t": "stream_failed", "stream": n, "why": str(e)})
            return
        hevc = w["clip"].endswith(".hevc")
        self.send({"t": "stream", "stream": n, "id": w["id"], "codec": "hevc" if hevc else "h264", "bits": 8,
                   "w": w["w"], "h": w["h"]})
        aus = access_units(self.clips[w["clip"]], hevc)
        then = access_units(self.clips[w["then"]], True) if "then" in w else None
        self.log.write({"t": "streaming", "stream": n, "id": w["id"], "aus": len(aus)})
        start = time.monotonic()
        k = 0
        switched = False
        try:
            while not self.stop and not self.streams.get(n, {}).get("stop"):
                if "end" in w and time.monotonic() - start > w["end"]:
                    self.log.write({"t": "stream_end", "stream": n})
                    break
                flags = 0
                if then is not None and not switched and k >= CONFIG_AFTER and aus[k % len(aus)][1]:
                    # The window got smaller: from this key frame on, the other clip, flagged as a config change.
                    aus = then
                    switched = True
                    k = 0
                    flags |= 2
                    self.send({"t": "resized", "id": w["id"], "w": 480, "h": 270})
                    self.log.write({"t": "config_change", "stream": n})
                data, key = aus[k % len(aus)]
                if key:
                    flags |= 1
                s.sendall(packet(1, flags, pc_now(), data))
                k += 1
                due = start + k / FPS
                time.sleep(max(0.0, due - time.monotonic()))
        except (ssl.SSLError, OSError):
            pass
        try:
            s.close()
        except OSError:
            pass
        self.log.write({"t": "stream_closed", "stream": n})

    def stream_sound(self):
        try:
            s = self.open_stream(0)
        except Exception as e:  # noqa: BLE001
            self.log.write({"t": "stream_failed", "stream": 0, "why": str(e)})
            return
        frames = adts_frames(self.clips.get("tone.aac", b""))
        self.log.write({"t": "sound_streaming", "frames": len(frames)})
        start = time.monotonic()
        k = 0
        try:
            while frames and not self.stop and not self.streams.get(0, {}).get("stop"):
                s.sendall(packet(2, 0, pc_now(), frames[k % len(frames)]))
                k += 1
                due = start + k * AAC_FRAME / RATE
                time.sleep(max(0.0, due - time.monotonic()))
        except (ssl.SSLError, OSError):
            pass
        try:
            s.close()
        except OSError:
            pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--make-clips", action="store_true")
    ap.add_argument("--clips", default=os.path.expanduser("~/media-tests/pc-windows"))
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=47803)
    ap.add_argument("--name", default="FAKE-PC")
    ap.add_argument("--code", default="")
    ap.add_argument("--token-file", default="")
    ap.add_argument("--log", default="")
    ap.add_argument("--discover-only", action="store_true")
    ap.add_argument("--seconds", type=float, default=600.0, help="how long to stay connected at most")
    args = ap.parse_args()
    if args.make_clips:
        return make_clips(args.clips)
    log = Log(args.log)
    reply = discover(args.host, args.port, args.name, log, tries=4 if args.discover_only else 10)
    if args.discover_only:
        return 0 if reply else 3
    pin = reply["pin"] if reply else ""
    token = ""
    if args.token_file and os.path.exists(args.token_file):
        with open(args.token_file, encoding="utf-8") as f:
            token = f.read().strip()
    try:
        ctl, got = tls_connect(args.host, args.port, pin)
    except Exception as e:  # noqa: BLE001
        log.write({"t": "tls_failed", "why": str(e)})
        return 4
    log.write({"t": "tls", "pin_ok": bool(pin) and got == pin})
    hello = {"t": "hello", "v": 1, "pc": args.name}
    if token:
        hello["token"] = token
    else:
        hello["code"] = args.code
    ctl.sendall((json.dumps(hello) + "\n").encode())
    buf = b""
    ctl.settimeout(10)
    while b"\n" not in buf:
        d = ctl.recv(65536)
        if not d:
            break
        buf += d
    line, _, rest = buf.partition(b"\n")
    first = json.loads(line.decode()) if line.strip() else {}
    log.write({"t": "answer", "type": first.get("t"), "why": first.get("why", ""), "has_token": "token" in first})
    if first.get("t") != "welcome":
        return 2
    if "token" in first:
        token = first["token"]
        if args.token_file:
            with open(args.token_file, "w", encoding="utf-8") as f:
                f.write(token)
            os.chmod(args.token_file, 0o600)
    fake = Fake(args, log, pin, token)
    fake.ctl = ctl
    for ln in rest.split(b"\n"):
        if ln.strip():
            fake.handle(json.loads(ln.decode()))
    th = threading.Thread(target=fake.run, daemon=True)
    th.start()
    end = time.monotonic() + args.seconds
    while th.is_alive() and time.monotonic() < end:
        time.sleep(0.1)
    fake.stop = True
    return 0


if __name__ == "__main__":
    sys.exit(main())
