#!/usr/bin/env python3
"""A fake headset for testing the PC app (pc/, docs/pc-windows.md) on one Windows PC. Python 3.8+, standard library
only (ssl, socket, json, ctypes). It plays the headset's half of the protocol exactly: the discovery reply, TLS on
47803 with a throwaway certificate (pc/tests/data, test only), pairing with a code, the control connection and the
stream connections; and it drives test windows of its own (pc/build/pcw-testwin.exe), never the PC's real ones:
pc-windows.exe runs with --only-titles, so the PC's own windows are not even listed.

    python tools/pc_windows_fake_headset.py                 the end-to-end test (HEVC, then a short H.264 run)
    python tools/pc_windows_fake_headset.py --bench         latency, bitrate and CPU: 1 and 3 windows of 1920x1080
    options: --build DIR (pc/build)  --out DIR (a temporary folder)  --tls 1.2|1.3  --keep (keep the recordings)

Needs ffmpeg/ffprobe on the PATH (Windows) or in WSL to check the recorded streams; without them the decode checks
are skipped and said so. The mouse and key test moves the real cursor and brings the test window to the front for
a few seconds. Exit code: 0 when every check passed.
"""

import argparse
import base64
import ctypes
import ctypes.wintypes as wt
import hashlib
import json
import math
import os
import queue
import secrets
import shutil
import socket
import ssl
import struct
import subprocess
import sys
import tempfile
import threading
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "pc", "tests", "data")
CERT = os.path.join(DATA, "test_only_headset.crt")
KEY = os.path.join(DATA, "test_only_headset.key")
PORT = 47803
CODE = "123456"

k32 = ctypes.windll.kernel32
u32 = ctypes.windll.user32
# Physical pixels, as pc-windows and the test window use.
u32.SetProcessDpiAwarenessContext(ctypes.c_void_p(-4))


def qpc_us() -> int:
    """The PC's one clock (QueryPerformanceCounter), as pc-windows writes it into each packet."""
    c, f = ctypes.c_int64(), ctypes.c_int64()
    k32.QueryPerformanceCounter(ctypes.byref(c))
    k32.QueryPerformanceFrequency(ctypes.byref(f))
    return c.value // f.value * 1_000_000 + c.value % f.value * 1_000_000 // f.value


RESULTS = []


def check(ok: bool, what: str) -> bool:
    RESULTS.append((bool(ok), what))
    print(("  ok    " if ok else "  FAIL  ") + what, flush=True)
    return bool(ok)


def even(size):
    """A picture size as the encoder takes it: each side rounded down to even."""
    return (size[0] & ~1, size[1] & ~1)


def pct(values, p):
    if not values:
        return 0.0
    s = sorted(values)
    return s[min(len(s) - 1, int(p * (len(s) - 1) + 0.5))]


# ---- The fake headset ----


class StreamRecord:
    def __init__(self, n, out_dir, tag):
        self.n = n
        self.out_dir = out_dir
        self.tag = tag
        self.packets = []  # (received us, time us, flags, kind, length)
        self.segments = []  # file names, a new one at each config change
        self.errors = []
        self.closed = threading.Event()
        self.first_flags = None
        self._f = None

    def file_for(self, kind, flags, codec):
        ext = ".aac" if kind == 2 else (".h264" if codec == "h264" else ".h265")
        if self._f is None or (kind == 1 and flags & 2):
            if self._f:
                self._f.close()
            name = os.path.join(self.out_dir, "%s_s%d_%d%s" % (self.tag, self.n, len(self.segments), ext))
            self.segments.append(name)
            self._f = open(name, "wb")
        return self._f

    def finish(self):
        if self._f:
            self._f.close()
            self._f = None
        self.closed.set()


class FakeHeadset:
    def __init__(self, out_dir, tls="1.3", pairing=True, name="Fake headset"):
        self.out_dir = out_dir
        self.name = name
        self.pairing = pairing
        self.codes_wrong = 0
        self.token_hashes = set()
        self.pin = hashlib.sha256(ssl.PEM_cert_to_DER_cert(open(CERT).read())).hexdigest()
        self.ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        self.ctx.load_cert_chain(CERT, KEY)
        self.ctx.minimum_version = ssl.TLSVersion.TLSv1_2
        self.ctx.maximum_version = ssl.TLSVersion.TLSv1_2 if tls == "1.2" else ssl.TLSVersion.TLSv1_3
        self.msgs = queue.Queue()
        self.all_msgs = []
        self.hellos = []
        self.control = None
        self.control_lock = threading.Lock()
        self.streams = {}
        self.stream_codec = {}
        self.tag = "run"
        self.stop = threading.Event()
        self.discovery_from = set()
        self.ping_n = 0
        self.pongs = set()
        self.udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.udp.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.udp.bind(("0.0.0.0", PORT))
        self.udp.settimeout(0.2)
        self.tcp = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.tcp.bind(("0.0.0.0", PORT))
        self.tcp.listen(16)
        self.tcp.settimeout(0.2)
        for target in (self._discovery, self._accept, self._pinger):
            threading.Thread(target=target, daemon=True).start()

    def close(self):
        self.stop.set()
        self.drop_control()
        for s in (self.udp, self.tcp):
            try:
                s.close()
            except OSError:
                pass

    # Discovery: reply to pcw_find from private addresses.
    def _discovery(self):
        while not self.stop.is_set():
            try:
                data, addr = self.udp.recvfrom(2048)
            except (socket.timeout, OSError):
                continue
            try:
                m = json.loads(data.decode("utf-8"))
            except ValueError:
                continue
            if m.get("t") != "pcw_find":
                continue
            self.discovery_from.add(m.get("pc", ""))
            reply = {"t": "pcw_here", "v": 1, "name": self.name, "port": PORT, "pin": self.pin,
                     "pairing": self.pairing}
            try:
                self.udp.sendto(json.dumps(reply).encode(), addr)
            except OSError:
                pass

    def _accept(self):
        while not self.stop.is_set():
            try:
                raw, addr = self.tcp.accept()
            except (socket.timeout, OSError):
                continue
            threading.Thread(target=self._connection, args=(raw,), daemon=True).start()

    def _pinger(self):
        while not self.stop.wait(5):
            self.ping_n += 1
            self.send({"t": "ping", "n": self.ping_n})

    def _connection(self, raw):
        raw.settimeout(10)
        try:
            c = self.ctx.wrap_socket(raw, server_side=True)
        except (ssl.SSLError, OSError) as e:
            print("  (TLS handshake failed: %s)" % e)
            return
        f = c.makefile("rb")
        try:
            first = json.loads(f.readline().decode("utf-8"))
        except (ValueError, OSError):
            c.close()
            return
        if first.get("t") == "hello":
            self._control(c, f, first)
        elif first.get("t") == "stream":
            self._stream(c, f, first)
        else:
            c.close()

    def _control(self, c, f, hello):
        self.hellos.append(hello)
        if "code" in hello:
            if not self.pairing or hello.get("code") != CODE:
                self.codes_wrong += 1
                c.sendall(b'{"t":"refused","why":"wrong code"}\n')
                c.close()
                return
            token = secrets.token_hex(32)
            self.token_hashes.add(hashlib.sha256(token.encode()).hexdigest())
            welcome = {"t": "welcome", "v": 1, "headset": self.name, "token": token}
        else:
            if hashlib.sha256(hello.get("token", "").encode()).hexdigest() not in self.token_hashes:
                c.sendall(b'{"t":"refused","why":"unknown token"}\n')
                c.close()
                return
            welcome = {"t": "welcome", "v": 1, "headset": self.name}
        c.sendall((json.dumps(welcome) + "\n").encode())
        c.settimeout(None)
        with self.control_lock:
            self.control = c
        self.msgs.put({"t": "_connected", "hello": hello})
        try:
            for line in f:
                m = json.loads(line.decode("utf-8"))
                m["_at"] = time.monotonic()
                if m.get("t") == "pong":
                    self.pongs.add(m.get("n"))
                self.all_msgs.append(m)
                self.msgs.put(m)
        except (OSError, ValueError):
            pass
        with self.control_lock:
            if self.control is c:
                self.control = None
        self.msgs.put({"t": "_disconnected"})

    def _stream(self, c, f, first):
        n = first.get("stream")
        if hashlib.sha256(first.get("token", "").encode()).hexdigest() not in self.token_hashes or not isinstance(n, int):
            c.close()
            return
        rec = StreamRecord(n, self.out_dir, self.tag)
        rec.sock = c
        self.streams.setdefault(n, []).append(rec)
        try:
            while True:
                h = f.read(20)
                if len(h) < 20:
                    break
                magic, kind, flags, reserved, t, length = struct.unpack("<4sBBHqI", h)
                if magic != b"PCW1" or reserved != 0 or kind not in (1, 2):
                    rec.errors.append("bad header %r" % h)
                    break
                payload = f.read(length)
                if len(payload) < length:
                    break
                if rec.first_flags is None:
                    rec.first_flags = flags
                rec.packets.append((qpc_us(), t, flags, kind, length))
                if kind == 1 and not payload.startswith((b"\x00\x00\x00\x01", b"\x00\x00\x01")):
                    rec.errors.append("video payload without a start code")
                if kind == 2 and not (payload[0] == 0xFF and payload[1] & 0xF6 == 0xF0):
                    rec.errors.append("sound payload without ADTS")
                rec.file_for(kind, flags, self.stream_codec.get(n, "hevc")).write(payload)
        except OSError:
            pass
        rec.finish()

    def send(self, m):
        with self.control_lock:
            c = self.control
        if not c:
            return False
        try:
            c.sendall((json.dumps(m) + "\n").encode())
            return True
        except OSError:
            return False

    def drop_stream(self, n):
        """Cuts a stream connection the way a lost network does (no close message)."""
        for r in self.streams.get(n, []):
            if not r.closed.is_set():
                try:
                    r.sock.shutdown(socket.SHUT_RDWR)
                    r.sock.close()
                except OSError:
                    pass

    def drop_control(self):
        with self.control_lock:
            c, self.control = self.control, None
        if c:
            try:
                c.shutdown(socket.SHUT_RDWR)
                c.close()
            except OSError:
                pass

    def wait(self, t, timeout=10.0, pred=lambda m: True):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            try:
                m = self.msgs.get(timeout=max(0.01, end - time.monotonic()))
            except queue.Empty:
                break
            if m.get("t") == t and pred(m):
                return m
        return None


# ---- Test windows and the app ----


class TestWindow:
    def __init__(self, exe, out_dir, title, size, pos, popup=False, tone=False, fps=60, busy=False, vsync=False):
        self.events_path = os.path.join(out_dir, title + "_events.jsonl")
        if os.path.exists(self.events_path):
            os.remove(self.events_path)  # an earlier window's "ready" must not be read as this one's
        args = [exe, "--title", title, "--size", "%dx%d" % size, "--pos", "%d,%d" % pos, "--fps", str(fps),
                "--events", self.events_path]
        if popup:
            args.append("--popup")
        if busy:
            args.append("--busy")
        if vsync:
            args.append("--vsync")
        if tone:
            args.append("--tone")
        self.p = subprocess.Popen(args)
        self.ready = None
        end = time.monotonic() + 10
        while time.monotonic() < end and not self.ready:
            for e in self.events():
                if e.get("e") == "ready":
                    self.ready = e
            time.sleep(0.05)
        if not self.ready:
            raise RuntimeError("the test window did not start")
        self.id = self.ready["id"]
        self.hwnd = int(self.id[2:], 16)

    def events(self):
        try:
            with open(self.events_path, encoding="utf-8") as f:
                return [json.loads(l) for l in f if l.strip()]
        except (OSError, ValueError):
            return []

    def latest(self, kind):
        ev = [e for e in self.events() if e.get("e") in kind]
        return ev[-1] if ev else self.ready

    def close(self):
        if self.p.poll() is None:
            u32.PostMessageW(wt.HWND(self.hwnd), 0x0010, 0, 0)  # WM_CLOSE
            try:
                self.p.wait(5)
            except subprocess.TimeoutExpired:
                self.p.kill()


def start_app(exe, out_dir, cfg, log, code=None, codec=None, extra=()):
    # --no-local-yield: the person at this PC typing while the test runs must not hold back the headset's input.
    args = [exe, "--config-dir", cfg, "--log", log, "--headset", "127.0.0.1", "--only-titles", "pcw-test",
            "--no-local-yield",
            "--hidden", "--stats-every", "2"]
    if code:
        args += ["--code", code]
    if codec:
        args += ["--codec", codec]
    args += list(extra)
    return subprocess.Popen(args)


def stop_app(p):
    if p and p.poll() is None:
        p.kill()
        p.wait(5)


# ---- Checking the recordings ----


def find_ffmpeg():
    if shutil.which("ffprobe") and shutil.which("ffmpeg"):
        return "win"
    try:
        r = subprocess.run(["wsl", "-d", "Ubuntu", "--", "which", "ffprobe"], capture_output=True, timeout=20)
        if r.returncode == 0:
            return "wsl"
    except (OSError, subprocess.TimeoutExpired):
        pass
    return None


def wsl_path(p):
    p = os.path.abspath(p).replace("\\", "/")
    return "/mnt/" + p[0].lower() + p[2:]


def ff(tool, args, mode):
    if mode == "wsl":
        args = [wsl_path(a) if os.path.isabs(a) and os.path.exists(os.path.dirname(a)) else a for a in args]
        cmd = ["wsl", "-d", "Ubuntu", "--", tool] + args
    else:
        cmd = [tool] + args
    return subprocess.run(cmd, capture_output=True, timeout=300)


def probe(path, mode, audio=False):
    r = ff("ffprobe", ["-v", "error", "-count_frames", "-select_streams", "a:0" if audio else "v:0", "-show_entries",
                       "stream=codec_name,profile,width,height,nb_read_frames,has_b_frames,sample_rate,channels,"
                       "pix_fmt,color_range,color_space", "-of", "json", path], mode)
    try:
        return json.loads(r.stdout.decode())["streams"][0]
    except (ValueError, KeyError, IndexError):
        return {}


def frame_rgb(path, index, w, h, mode, png=None):
    """Decodes frame `index` as raw RGB (and a PNG beside it)."""
    raw = path + ".frame.rgb"
    sel = "select=eq(n\\,%d)" % index
    ff("ffmpeg", ["-v", "error", "-y", "-i", path, "-vf", sel, "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb24",
                  raw], mode)
    if png:
        ff("ffmpeg", ["-v", "error", "-y", "-i", path, "-vf", sel, "-frames:v", "1", png], mode)
    try:
        data = open(raw, "rb").read()
    finally:
        if os.path.exists(raw):
            os.remove(raw)
    return data if len(data) == w * h * 3 else None


def pixel_avg(rgb, w, x0, y0, size=8):
    s = [0, 0, 0]
    for y in range(y0, y0 + size):
        for x in range(x0, x0 + size):
            i = (y * w + x) * 3
            for c in range(3):
                s[c] += rgb[i + c]
    return [v / (size * size) for v in s]


def check_pattern(rgb, w, h, off_x, off_y, client_w, client_h, scale_x, scale_y, label):
    """The test window's quadrants, sampled in their middles (away from the moving bar and the text)."""
    expect = {"red": ((0.25, 0.22), (255, 0, 0)), "green": ((0.75, 0.22), (0, 255, 0)),
              "blue": ((0.25, 0.78), (0, 0, 255)), "grey": ((0.75, 0.78), (128, 128, 128))}
    ok = True
    worst = 0
    for name, ((fx, fy), want) in expect.items():
        x = int((off_x + fx * client_w) * scale_x) - 4
        y = int((off_y + fy * client_h) * scale_y) - 4
        got = pixel_avg(rgb, w, x, y)
        err = max(abs(a - b) for a, b in zip(got, want))
        worst = max(worst, err)
        ok = ok and err < 24
    return check(ok, "%s: the pattern's colours are right in the decoded frame (worst channel off by %.0f of 255)"
                 % (label, worst))


def goertzel(samples, rate, freq):
    k = 2 * math.cos(2 * math.pi * freq / rate)
    s1 = s2 = 0.0
    for x in samples:
        s0 = x + k * s1 - s2
        s2, s1 = s1, s0
    return s1 * s1 + s2 * s2 - k * s1 * s2


def check_stream_packets(rec, label, kind=1, max_key_gap_s=2.6):
    pk = [p for p in rec.packets if p[3] == kind]
    check(not rec.errors, "%s: every packet framed right (PCW1, reserved 0, %s)" %
          (label, "Annex B start codes" if kind == 1 else "ADTS headers") + ("" if not rec.errors else ": " + rec.errors[0]))
    if not pk:
        return check(False, "%s: packets came" % label)
    times = [p[1] for p in pk]
    check(all(b > a for a, b in zip(times, times[1:])), "%s: packet times always rise" % label)
    if kind == 1:
        check(rec.first_flags is not None and rec.first_flags & 1,
              "%s: the first packet is a key frame (flags %s)" % (label, rec.first_flags))
        keys = [p[1] for p in pk if p[2] & 1]
        gaps = [(b - a) / 1e6 for a, b in zip(keys, keys[1:])]
        where = ""
        if gaps and max(gaps) > max_key_gap_s:
            i = gaps.index(max(gaps))
            inside = [p for p in pk if keys[i] < p[1] < keys[i + 1]]
            where = "; from %.2f s in, %d frames in the gap" % ((keys[i] - pk[0][1]) / 1e6, len(inside))
        check(not gaps or max(gaps) <= max_key_gap_s,
              "%s: a key frame at least every 2 s (%d key frames, longest gap %.2f s%s)" %
              (label, len(keys), max(gaps) if gaps else 0, where))
        allg = [(b - a) / 1e6 for a, b in zip(times, times[1:])]
        check(not allg or max(allg) <= 2.6, "%s: a frame at least every 2 s (longest gap %.2f s)" %
              (label, max(allg) if allg else 0))
    return True


# ---- The end-to-end test ----


def run_e2e(a, out):
    exe = os.path.join(a.build, "pc-windows.exe")
    twin = os.path.join(a.build, "pcw-testwin.exe")
    cfg = os.path.join(out, "cfg")
    os.makedirs(cfg, exist_ok=True)
    mode = find_ffmpeg()
    print("ffmpeg: %s" % ({"win": "Windows (PATH)", "wsl": "WSL"}.get(mode, "not found: decode checks skipped")))
    hs = FakeHeadset(out, tls=a.tls)
    print("fake headset on %d, pin %s..." % (PORT, hs.pin[:12]))
    win = TestWindow(twin, out, "pcw-test-main", (1280, 720), (120, 120), tone=True)
    app = None
    try:
        print("\n[pairing]")
        app = start_app(exe, out, cfg, os.path.join(out, "pc_wrong.log"), code="000000")
        end = time.monotonic() + 15
        while time.monotonic() < end and hs.codes_wrong == 0:
            time.sleep(0.1)
        check(hs.codes_wrong == 1, "a wrong code is refused")
        check(bool(hs.discovery_from), "discovery: pcw_find came")
        stop_app(app)
        check(not os.path.exists(os.path.join(cfg, "pairing.dat")), "nothing kept after a wrong code")
        app = start_app(exe, out, cfg, os.path.join(out, "pc.log"), code=CODE)
        m = hs.wait("_connected", 20)
        check(m is not None and m["hello"].get("code") == CODE and m["hello"].get("v") == 1,
              "hello with the code, version 1")
        time.sleep(0.5)
        check(os.path.exists(os.path.join(cfg, "pairing.dat")), "the pairing is kept (DPAPI, pairing.dat)")
        blob = open(os.path.join(cfg, "pairing.dat"), "rb").read() if os.path.exists(os.path.join(cfg, "pairing.dat")) else b""
        check(b"token" not in blob and hs.pin.encode() not in blob, "pairing.dat is encrypted (no token or pin in clear)")

        print("\n[list]")
        hs.send({"t": "list"})
        m = hs.wait("windows", 10)
        lst = m["list"] if m else []
        mine = [w for w in lst if w.get("id") == win.id]
        others = [w for w in lst if w.get("kind") == "window" and not w.get("title", "").startswith("pcw-test")]
        check(bool(mine), "windows: the test window is listed")
        check(not others, "windows: only the test's windows (--only-titles)")
        mons = [w for w in lst if w.get("kind") == "monitor"]
        check(bool(mons) and all(w.get("id", "").startswith("m:") and w.get("w", 0) > 0 for w in mons),
              "windows: %d monitor(s) listed with sizes" % len(mons))
        if mine:
            w0 = mine[0]
            check(w0.get("app") == "pcw-testwin.exe" and w0.get("kind") == "window", "windows: kind and app name")
            check(w0["w"] == win.ready["frame"][0] and w0["h"] == win.ready["frame"][1],
                  "windows: size is the captured frame (%dx%d)" % (w0["w"], w0["h"]))
            jpg = base64.b64decode(w0.get("thumb", "")) if w0.get("thumb") else b""
            tw = th = 0
            i = 2
            while i + 9 < len(jpg):
                if jpg[i] == 0xFF and jpg[i + 1] in (0xC0, 0xC2):
                    th, tw = struct.unpack(">HH", jpg[i + 5:i + 9])
                    break
                i += 2 + struct.unpack(">H", jpg[i + 2:i + 4])[0] if jpg[i] == 0xFF else 1
            check(jpg[:2] == b"\xff\xd8" and 0 < max(tw, th) <= 256,
                  "windows: thumbnail is a JPEG of at most 256 px (%dx%d, %d bytes)" % (tw, th, len(jpg)))

        print("\n[stream]")
        hs.tag = "hevc" if not a.h264_only else "h264"
        hs.stream_codec[1] = "hevc"
        hs.send({"t": "open", "id": win.id, "stream": 1, "max": [1920, 1080], "fps": 60, "kbps": 8000})
        hs.send({"t": "sound", "on": True})
        m = hs.wait("stream", 10, lambda m: m.get("stream") == 1)
        check(m is not None and m.get("codec") in ("hevc", "h264") and m.get("bits") == 8 and m.get("id") == win.id,
              "stream message: %s" % (json.dumps({k: m[k] for k in ("codec", "bits", "w", "h")}) if m else None))
        sw, sh = (m["w"], m["h"]) if m else (0, 0)
        hs.stream_codec[1] = m.get("codec", "hevc") if m else "hevc"
        check((sw, sh) == even(win.ready["frame"]), "stream size is the window's, rounded down to even (%dx%d of %s)"
              % (sw, sh, win.ready["frame"]))
        time.sleep(4)
        recs = hs.streams.get(1, [])
        check(bool(recs) and len(recs[0].packets) > 60, "video packets are coming (%d in 4 s)" %
              (len(recs[0].packets) if recs else 0))
        snd = hs.streams.get(0, [])
        check(bool(snd) and len(snd[0].packets) > 120, "sound packets are coming (%d in 4 s)" %
              (len(snd[0].packets) if snd else 0))
        check(1 in hs.pongs or hs.ping_n == 0 or bool(hs.pongs), "pong answers ping (%s)" % sorted(hs.pongs))

        print("\n[quality]")
        hs.send({"t": "quality", "stream": 1, "fps": 15, "kbps": 2000})
        t0 = qpc_us()
        time.sleep(4)
        recent = [p for p in recs[0].packets if p[0] > t0 + 1_000_000] if recs else []
        span = (recent[-1][0] - recent[0][0]) / 1e6 if len(recent) > 1 else 1
        fps = (len(recent) - 1) / span if span > 0 else 0
        check(8 <= fps <= 17, "quality: about 15 fps after the change (%.1f)" % fps)
        hs.send({"t": "quality", "stream": 1, "fps": 60, "kbps": 8000})

        print("\n[input]")
        input_test(hs, win, sw, sh)

        print("\n[resize]")
        before = len(hs.all_msgs)
        frame0 = win.ready["frame"]
        u32.SetWindowPos(wt.HWND(win.hwnd), None, 0, 0, 1000, 600, 0x0002 | 0x0004 | 0x0010)  # NOMOVE|NOZORDER|NOACTIVATE
        m = hs.wait("resized", 10, lambda m: m.get("id") == win.id)
        time.sleep(1.5)
        win_now = win.latest(("size",))
        check(m is not None and (m["w"], m["h"]) == even(win_now["frame"]) and tuple(win_now["frame"]) != tuple(frame0),
              "resized: %s (the window's frame now %s, was %s)" % ((m["w"], m["h"]) if m else None,
                                                                   win_now["frame"], frame0))
        cfg_packets = [p for p in recs[0].packets if p[2] & 2] if recs else []
        check(len(cfg_packets) >= 2 and all(p[2] & 1 for p in cfg_packets),
              "resized: the next key frame carries the config-change flag (%d config packets)" % len(cfg_packets))

        print("\n[minimised]")
        u32.ShowWindow(wt.HWND(win.hwnd), 6)  # SW_MINIMIZE
        m = hs.wait("error", 6, lambda m: m.get("what") == "minimised" and m.get("id") == win.id)
        check(m is not None, "minimised: the headset is told")
        t0 = qpc_us()
        time.sleep(4.5)
        t1 = qpc_us()
        during = [p for p in recs[0].packets if t0 + 300_000 < p[0] < t1] if recs else []
        check(1 <= len(during) <= 3, "minimised: the last picture goes on, a frame every 2 s (%d in %.1f s)" %
              (len(during), (t1 - t0 - 300_000) / 1e6))
        u32.ShowWindow(wt.HWND(win.hwnd), 4)  # SW_SHOWNOACTIVATE
        time.sleep(1.5)

        print("\n[close and reopen]")
        hs.send({"t": "close", "stream": 1})
        time.sleep(1)
        check(recs[0].closed.is_set() if recs else False, "close: the stream connection ends")
        hs.stream_codec[2] = hs.stream_codec[1]
        hs.send({"t": "open", "id": win.id, "stream": 2, "max": [640, 640], "fps": 30, "kbps": 3000})
        m = hs.wait("stream", 10, lambda m: m.get("stream") == 2)
        check(m is not None and m["w"] <= 640 and m["h"] <= 640 and m["w"] % 2 == 0,
              "a smaller max scales the stream down (%s)" % (str((m["w"], m["h"])) if m else None))
        s2w, s2h = (m["w"], m["h"]) if m else (0, 0)
        time.sleep(2)
        # The mouse in a scaled stream: the middle of the client area in the stream's pixels.
        cur = win.latest(("size", "ready"))
        sx, sy = s2w / cur["frame"][0], s2h / cur["frame"][1]
        cx, cy = cur["client_offset"][0] + 100, cur["client_offset"][1] + 80
        hs.send({"t": "focus", "id": win.id})
        time.sleep(0.4)
        n_ev = len(win.events())
        hs.send({"t": "mouse", "id": win.id, "event": "down", "x": (cx + 0.5) * sx, "y": (cy + 0.5) * sy,
                 "button": "left"})
        hs.send({"t": "mouse", "id": win.id, "event": "up", "x": (cx + 0.5) * sx, "y": (cy + 0.5) * sy,
                 "button": "left"})
        time.sleep(0.5)
        downs = [e for e in win.events()[n_ev:] if e.get("e") == "mouse" and e["msg"] == "down"]
        tol = math.ceil(1 / min(sx, sy))
        check(bool(downs) and abs(downs[0]["x"] - 100) <= tol and abs(downs[0]["y"] - 80) <= tol,
              "scaled stream: a click lands where aimed (%s, want (100, 80) +-%d)" %
              ((downs[0]["x"], downs[0]["y"]) if downs else None, tol))

        print("\n[reconnect]")
        hs.drop_control()
        m = hs.wait("_connected", 15)
        check(m is not None and "token" in m["hello"] and "code" not in m["hello"],
              "after the control connection drops, the PC dials again with its token")
        time.sleep(1)
        check(all(r.closed.is_set() for r in hs.streams.get(2, [])), "streams end with the control connection")
        hs.send({"t": "list"})
        check(hs.wait("windows", 10) is not None, "the list again after reconnecting")
        hs.stream_codec[3] = hs.stream_codec[1]
        hs.send({"t": "open", "id": win.id, "stream": 3, "max": [1920, 1080], "fps": 30, "kbps": 4000})
        check(hs.wait("stream", 10, lambda m: m.get("stream") == 3) is not None, "a stream opens again after it")
        time.sleep(2)

        print("\n[a stream connection drops]")
        hs.drop_stream(3)
        end = time.monotonic() + 10
        while time.monotonic() < end and len(hs.streams.get(3, [])) < 2:
            time.sleep(0.1)
        time.sleep(1)
        again = hs.streams.get(3, [])
        check(len(again) >= 2 and len(again[-1].packets) > 0 and again[-1].first_flags == 3,
              "the PC dials the stream again and starts with a key frame and config change (flags %s)" %
              (again[-1].first_flags if len(again) >= 2 else None))
        hs.send({"t": "close", "stream": 3})

        print("\n[opening a minimised window]")
        u32.ShowWindow(wt.HWND(win.hwnd), 6)  # SW_MINIMIZE
        time.sleep(1)
        hs.stream_codec[4] = hs.stream_codec[1]
        hs.send({"t": "open", "id": win.id, "stream": 4, "max": [1920, 1080], "fps": 30, "kbps": 4000})
        m = hs.wait("error", 5, lambda m: m.get("what") == "minimised" and m.get("id") == win.id)
        check(m is not None, "opened while minimised: the headset is told")
        check(hs.wait("stream", 2, lambda m: m.get("stream") == 4) is None,
              "opened while minimised: no picture to announce yet")
        u32.ShowWindow(wt.HWND(win.hwnd), 4)  # SW_SHOWNOACTIVATE
        m = hs.wait("stream", 8, lambda m: m.get("stream") == 4)
        check(m is not None and m["w"] > 0, "restored: the stream starts (%s)" % (str((m["w"], m["h"])) if m else None))
        time.sleep(1)

        print("\n[window closes]")
        win.close()
        m = hs.wait("closed", 10, lambda m: m.get("id") == win.id)
        check(m is not None, "closed: the headset is told when the window goes")
        time.sleep(1)
        check(all(r.closed.is_set() for r in hs.streams.get(4, [])), "closed: its stream connection ends")
        hs.send({"t": "sound", "on": False})
        time.sleep(1)
        check(all(r.closed.is_set() for r in hs.streams.get(0, [])), "sound off: the sound stream ends")
    finally:
        stop_app(app)
        win.close()
        hs.close()

    print("\n[recordings]")
    recs = hs.streams.get(1, [])
    if recs:
        check_stream_packets(recs[0], "stream 1")
    for n in (2, 3, 4):
        for i, r in enumerate(hs.streams.get(n, [])):
            check_stream_packets(r, "stream %d%s" % (n, " (connection %d)" % (i + 1) if i else ""))
    snd = hs.streams.get(0, [])
    if snd:
        check_stream_packets(snd[0], "sound", kind=2)
        frames = len(snd[0].packets)
        span = (snd[0].packets[-1][1] - snd[0].packets[0][1]) / 1e6 if frames > 1 else 0
        rate = (frames - 1) / span if span else 0
        check(abs(rate - 46.875) < 1.0, "sound: %.2f AAC frames a second by their times (48000/1024 = 46.875)" % rate)
    if mode and recs:
        decode_checks(recs[0], win, mode, out, hs.stream_codec.get(1, "hevc"), frame0)
    if mode and snd:
        audio_checks(snd[0], mode)

    print("\n[H.264, over TLS 1.2]")
    h264_run(a, out, mode)

    print("\n[a PC with no hardware encoder]")
    no_encoder_run(a, out)


def no_encoder_run(a, out):
    exe = os.path.join(a.build, "pc-windows.exe")
    twin = os.path.join(a.build, "pcw-testwin.exe")
    cfg = os.path.join(out, "cfgnone")
    os.makedirs(cfg, exist_ok=True)
    hs = FakeHeadset(out, tls=a.tls)
    win = TestWindow(twin, out, "pcw-test-none", (320, 240), (300, 300), popup=True)
    app = start_app(exe, out, cfg, os.path.join(out, "pcnone.log"), code=CODE, codec="none")
    try:
        check(hs.wait("_connected", 20) is not None, "no encoder: paired")
        hs.send({"t": "open", "id": win.id, "stream": 1, "max": [1920, 1080], "fps": 30, "kbps": 4000})
        m = hs.wait("error", 10, lambda m: m.get("id") == win.id)
        check(m is not None and m.get("what") == "no encoder", "no encoder: error %s" % (json.dumps(m) if m else None))
        time.sleep(1)
        check(not hs.streams.get(1), "no encoder: no stream connection, no software fall-back")
    finally:
        stop_app(app)
        win.close()
        hs.close()


def input_test(hs, win, sw, sh):
    cur = win.latest(("size", "ready"))
    sx, sy = sw / cur["frame"][0], sh / cur["frame"][1]
    off = cur["client_offset"]
    hs.send({"t": "focus", "id": win.id})
    time.sleep(0.5)
    check(u32.GetForegroundWindow() == win.hwnd, "focus: the test window is brought to the front")
    n0 = len(win.events())
    # Points of the client area, sent in the stream's pixels (the title bar is part of the picture).
    pts = [(10, 10), (200, 150), (cur["client"][0] - 5, cur["client"][1] - 5)]
    for (x, y) in pts:
        px, py = (off[0] + x + 0.5) * sx, (off[1] + y + 0.5) * sy
        hs.send({"t": "mouse", "id": win.id, "event": "move", "x": px, "y": py})
        hs.send({"t": "mouse", "id": win.id, "event": "down", "x": px, "y": py, "button": "left"})
        hs.send({"t": "mouse", "id": win.id, "event": "up", "x": px, "y": py, "button": "left"})
    px, py = (off[0] + 300.5) * sx, (off[1] + 200.5) * sy
    hs.send({"t": "mouse", "id": win.id, "event": "down", "x": px, "y": py, "button": "right"})
    hs.send({"t": "mouse", "id": win.id, "event": "up", "x": px, "y": py, "button": "right"})
    hs.send({"t": "mouse", "id": win.id, "event": "wheel", "x": px, "y": py, "dx": 0, "dy": 1})
    time.sleep(0.2)  # Windows adds up wheel messages still waiting in a queue
    hs.send({"t": "mouse", "id": win.id, "event": "wheel", "x": px, "y": py, "dx": 0, "dy": -0.5})
    time.sleep(0.8)
    ev = win.events()[n0:]
    downs = [e for e in ev if e.get("e") == "mouse" and e["msg"] == "down" and e["button"] == "left"]
    # Only the clicks sent here are compared: the PC's own mouse may click too while the test runs.
    got = [(e["x"], e["y"]) for e in downs][: len(pts)]
    check(got == pts, "mouse: left clicks land on the exact pixels (%s, want %s)" % (got, pts))
    rights = [e for e in ev if e.get("e") == "mouse" and e["button"] == "right"]
    check(len(rights) == 2 and (rights[0]["x"], rights[0]["y"]) == (300, 200), "mouse: right button down and up")
    wheels = [e["delta"] for e in ev if e.get("e") == "wheel"]
    check(wheels == [120, -60], "mouse: the wheel, a notch up and half a notch down (%s)" % wheels)

    n0 = len(win.events())
    keys = [("A", 0x41, 0x1E, False), ("Left", 0x25, 0x4B, True), ("F5", 0x74, 0x3F, False),
            ("Kp Enter", 0x0D, 0x1C, True), ("Delete", 0x2E, 0x53, True), ("Kp Divide", 0x6F, 0x35, True),
            ("BracketLeft", None, 0x1A, False), ("Kp 5", None, 0x4C, False)]
    for name, _, _, _ in keys:
        hs.send({"t": "key", "id": win.id, "key": name, "down": True})
        hs.send({"t": "key", "id": win.id, "key": name, "down": False})
    time.sleep(0.8)
    ev = [e for e in win.events()[n0:] if e.get("e") == "key"]
    ok = True
    detail = []
    for i, (name, vk, scan, ext) in enumerate(keys):
        d = ev[2 * i] if 2 * i < len(ev) else None
        u = ev[2 * i + 1] if 2 * i + 1 < len(ev) else None
        good = d and u and d["down"] and not u["down"] and d["scan"] == scan and d["ext"] == ext and \
            (vk is None or d["vk"] == vk)
        ok = ok and bool(good)
        if not good:
            detail.append("%s: %s" % (name, d))
    check(ok and len(ev) == 2 * len(keys), "keys: scan codes, extended flags and virtual keys right (%d events)%s" %
          (len(ev), "; " + "; ".join(detail) if detail else ""))

    # A shortcut: Ctrl held while C goes down and up.
    n0 = len(win.events())
    for k, d in (("Ctrl", True), ("C", True), ("C", False), ("Ctrl", False)):
        hs.send({"t": "key", "id": win.id, "key": k, "down": d})
    time.sleep(0.5)
    ev = [(e["vk"], e["down"]) for e in win.events()[n0:] if e.get("e") == "key"]
    check(ev == [(0x11, True), (0x43, True), (0x43, False), (0x11, False)], "keys: Ctrl+C in order (%s)" % ev)

    n0 = len(win.events())
    text = "héllo ✓ \U0001F600\n"
    hs.send({"t": "text", "id": win.id, "text": text})
    time.sleep(0.8)
    chars = [e["c"] for e in win.events()[n0:] if e.get("e") == "char"]
    want = [ord(c) for c in "héllo ✓ "] + [0xD83D, 0xDE00, 13]
    check(chars == want, "text: Unicode typed as characters, emoji as a surrogate pair, a new line as Enter (%s)" %
          chars)


def decode_checks(rec, win, mode, out, codec, frame0):
    seg = rec.segments[0] if rec.segments else None
    if not seg:
        return
    info = probe(seg, mode)
    n_seg0 = 0
    for p in rec.packets:
        if p[2] & 2 and n_seg0:
            break
        n_seg0 += 1
    check((info.get("width"), info.get("height")) == even(frame0),
          "decoded: %s %s %sx%s" % (info.get("codec_name"), info.get("profile"), info.get("width"), info.get("height")))
    check(str(info.get("nb_read_frames")) == str(n_seg0),
          "decoded: every packet is a frame (%s frames, %d packets)" % (info.get("nb_read_frames"), n_seg0))
    check(info.get("has_b_frames") in (0, "0", None), "decoded: no B-frames")
    check(info.get("color_range") in ("tv", None) and info.get("pix_fmt") == "yuv420p",
          "decoded: 4:2:0 8-bit, limited range (%s, %s, %s)" % (info.get("pix_fmt"), info.get("color_range"),
                                                                info.get("color_space")))
    w, h = info.get("width", 0), info.get("height", 0)
    png = os.path.join(SHOT_DIR, "pc_windows_frame.png")
    os.makedirs(SHOT_DIR, exist_ok=True)
    rgb = frame_rgb(seg, max(0, n_seg0 // 2), w, h, mode, png)
    if check(rgb is not None, "decoded: a frame from the middle (saved as %s)" % png):
        off = win.ready["client_offset"]
        check_pattern(rgb, w, h, off[0], off[1], win.ready["client"][0], win.ready["client"][1], 1, 1, "stream 1")
    if len(rec.segments) > 1:
        info2 = probe(rec.segments[1], mode)
        check(info2.get("width", 0) > 0 and (info2.get("width"), info2.get("height")) != (w, h),
              "decoded: after the resize the stream starts again at %sx%s" % (info2.get("width"), info2.get("height")))


def audio_checks(rec, mode):
    seg = rec.segments[0] if rec.segments else None
    if not seg:
        return
    info = probe(seg, mode, audio=True)
    check(info.get("codec_name") == "aac" and str(info.get("sample_rate")) == "48000" and info.get("channels") == 2,
          "sound decoded: %s %s, %s Hz, %s channels, %s frames" % (info.get("codec_name"), info.get("profile"),
                                                                  info.get("sample_rate"), info.get("channels"),
                                                                  info.get("nb_read_frames")))
    raw = seg + ".pcm"
    ff("ffmpeg", ["-v", "error", "-y", "-i", seg, "-f", "s16le", "-ac", "1", "-ar", "48000", raw], mode)
    try:
        pcm = open(raw, "rb").read()
    finally:
        if os.path.exists(raw):
            os.remove(raw)
    n = len(pcm) // 2
    s = struct.unpack("<%dh" % n, pcm[: n * 2])
    mid = s[n // 3: n // 3 + 9600]  # 0.2 s from the middle
    if len(mid) < 9600:
        check(False, "sound: enough decoded")
        return
    p1k = goertzel(mid, 48000, 1000)
    side = (goertzel(mid, 48000, 700) + goertzel(mid, 48000, 1400)) / 2 + 1e-9
    rms = math.sqrt(sum(x * x for x in mid) / len(mid))
    check(p1k / side > 20, "sound: the test window's 1 kHz tone is in the stream (%.0f times the band beside it, "
          "RMS %.0f)" % (p1k / side, rms))


def h264_run(a, out, mode):
    exe = os.path.join(a.build, "pc-windows.exe")
    twin = os.path.join(a.build, "pcw-testwin.exe")
    cfg = os.path.join(out, "cfg264")
    os.makedirs(cfg, exist_ok=True)
    hs = FakeHeadset(out, tls="1.2")  # the other TLS version than the main run's (1.3 by default)
    hs.tag = "h264"
    win = TestWindow(twin, out, "pcw-test-264", (800, 450), (200, 200), popup=True)
    app = start_app(exe, out, cfg, os.path.join(out, "pc264.log"), code=CODE, codec="h264")
    try:
        check(hs.wait("_connected", 20) is not None, "H.264: paired")
        hs.stream_codec[1] = "h264"
        hs.send({"t": "open", "id": win.id, "stream": 1, "max": [1920, 1080], "fps": 60, "kbps": 6000})
        m = hs.wait("stream", 10, lambda m: m.get("stream") == 1)
        check(m is not None and m.get("codec") == "h264" and (m["w"], m["h"]) == (800, 450),
              "H.264: stream message (%s)" % (json.dumps(m) if m else None))
        time.sleep(4)
    finally:
        stop_app(app)
        win.close()
        hs.close()
    recs = hs.streams.get(1, [])
    if not recs:
        check(False, "H.264: packets came")
        return
    check_stream_packets(recs[0], "H.264 stream")
    if mode and recs[0].segments:
        info = probe(recs[0].segments[0], mode)
        check(info.get("codec_name") == "h264" and info.get("width") == 800 and
              str(info.get("nb_read_frames")) == str(len(recs[0].packets)) and info.get("has_b_frames") in (0, "0"),
              "H.264 decoded: %s %s %sx%s, %s frames of %d packets, B-frames %s" %
              (info.get("codec_name"), info.get("profile"), info.get("width"), info.get("height"),
               info.get("nb_read_frames"), len(recs[0].packets), info.get("has_b_frames")))
        rgb = frame_rgb(recs[0].segments[0], len(recs[0].packets) // 2, 800, 450, mode,
                        os.path.join(SHOT_DIR, "pc_windows_frame_h264.png"))
        if check(rgb is not None, "H.264: a frame decoded"):
            check_pattern(rgb, 800, 450, 0, 0, 800, 450, 1, 1, "H.264")


# ---- The benchmark ----


class LoadSampler:
    """The whole PC's load while a measurement runs, so numbers taken on a busy PC can be read as such: total CPU
    from GetSystemTimes, and the GPU's engines (3D, video encode, copy...) from Windows' performance counters."""

    PS = ("Get-Counter '\\GPU Engine(*)\\Utilization Percentage' -SampleInterval 2 -MaxSamples %d | ForEach-Object {"
          " $g=@{}; foreach($c in $_.CounterSamples){ if($c.InstanceName -match 'engtype_(\\w+)'){"
          " $k=$matches[1]; $g[$k]=[double]$g[$k]+$c.CookedValue } }; $g | ConvertTo-Json -Compress }")

    def __init__(self, seconds):
        self.cpu0 = self._times()
        self.p = subprocess.Popen(["powershell", "-NoProfile", "-Command", self.PS % max(1, int(seconds // 2))],
                                  stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)

    @staticmethod
    def _times():
        idle, kern, user = wt.FILETIME(), wt.FILETIME(), wt.FILETIME()
        k32.GetSystemTimes(ctypes.byref(idle), ctypes.byref(kern), ctypes.byref(user))
        v = lambda f: (f.dwHighDateTime << 32) | f.dwLowDateTime
        return v(idle), v(kern), v(user)

    def finish(self):
        i1, k1, u1 = self._times()
        i0, k0, u0 = self.cpu0
        total = (k1 - k0) + (u1 - u0)  # kernel time includes idle time
        cpu = 100.0 * (total - (i1 - i0)) / total if total else 0.0
        try:
            text, _ = self.p.communicate(timeout=60)
        except subprocess.TimeoutExpired:
            self.p.kill()
            text = ""
        gpu = {}
        n = 0
        for line in text.splitlines():
            try:
                d = json.loads(line)
            except ValueError:
                continue
            if any(not 0 <= float(val) <= 800 for val in d.values()):
                continue  # Windows' counters now and then give a nonsense value: that sample is left out
            n += 1
            for k, val in d.items():
                gpu[k] = gpu.get(k, 0.0) + float(val)
        gpu = {k: v / n for k, v in gpu.items()} if n else {}
        return cpu, gpu


def log_numbers(log, after_clock):
    """The app's own numbers from its log, from the stats lines written after `after_clock` (HH:MM:SS)."""
    out = {"lat50": [], "lat95": [], "captured": [], "cpu": []}
    for line in open(log, encoding="utf-8", errors="replace"):
        if line[:8] < after_clock:
            continue
        try:
            if "stats: stream" in line:
                out["lat50"].append(float(line.split("p50 ")[1].split(" ms")[0]))
                out["lat95"].append(float(line.split("p95 ")[1].split(" ms")[0]))
                out["captured"].append(float(line.split("captured ")[1].split(")")[0]))
            elif "stats: cpu" in line:
                out["cpu"].append(float(line.split("stats: cpu ")[1].split(" %")[0]))
        except (IndexError, ValueError):
            pass
    return out


def engine(gpu, name):
    """A GPU engine's load by its name in any case (the counters say "3D" or "3d" by driver)."""
    return sum(v for k, v in gpu.items() if k.lower() == name)


def spread(values, fmt="%.1f"):
    """Median and range of a list, for numbers repeated over rounds."""
    if not values:
        return "-"
    s = sorted(values)
    med = s[len(s) // 2] if len(s) % 2 else (s[len(s) // 2 - 1] + s[len(s) // 2]) / 2
    return (fmt + " (" + fmt + " to " + fmt + ")") % (med, s[0], s[-1])


def bench_round(a, out, count, round_no):
    exe = os.path.join(a.build, "pc-windows.exe")
    twin = os.path.join(a.build, "pcw-testwin.exe")
    tag = "bench%d_r%d" % (count, round_no)
    cfg = os.path.join(out, "cfg" + tag)
    os.makedirs(cfg, exist_ok=True)
    log = os.path.join(out, tag + ".log")
    hs = FakeHeadset(out, tls=a.tls)
    hs.tag = tag
    wins = [TestWindow(twin, out, "pcw-test-bench%d" % i, (1920, 1080), (40 * i, 40 * i), popup=True,
                       busy=a.busy, vsync=True) for i in range(count)]
    app = start_app(exe, out, cfg, log, code=CODE, codec=a.codec)
    r = None
    try:
        if not hs.wait("_connected", 20):
            check(False, "bench: paired")
            return None
        for i, w in enumerate(wins):
            hs.stream_codec[i + 1] = a.codec or "hevc"
            hs.send({"t": "open", "id": w.id, "stream": i + 1, "max": [1920, 1080], "fps": a.fps, "kbps": 20000})
        time.sleep(3)  # settle
        clock = time.strftime("%H:%M:%S")
        load = LoadSampler(a.seconds)
        t0 = qpc_us()
        time.sleep(a.seconds)
        t1 = qpc_us()
        sys_cpu, gpu = load.finish()
        r = {"sys_cpu": sys_cpu, "gpu": gpu, "fps": [], "kbps": [], "e2e50": [], "e2e95": [], "stalls": []}
    finally:
        stop_app(app)
        for w in wins:
            w.close()
        hs.close()
    painted = []
    for w in wins:
        c = [e for e in w.events() if e.get("e") == "closed"]
        if c and c[0].get("seconds"):
            painted.append(c[0]["frames"] / c[0]["seconds"])
    r["painted"] = painted
    for n in range(1, count + 1):
        for rec in hs.streams.get(n, []):
            pk = [p for p in rec.packets if t0 <= p[0] <= t1]
            if len(pk) < 2:
                continue
            secs = (pk[-1][0] - pk[0][0]) / 1e6
            r["fps"].append((len(pk) - 1) / secs)
            r["kbps"].append(sum(p[4] for p in pk) * 8 / 1000 / secs)
            # From Windows' composition time of each frame (the same clock, this PC) to its arrival here. Windows
            # stamps a frame with the vblank it is meant for, a few ms ahead, so small values can be negative.
            e2e = [(p[0] - p[1]) / 1000 for p in pk]
            r["e2e50"].append(pct(e2e, 0.5))
            r["e2e95"].append(pct(e2e, 0.95))
            # Stalls: gaps of more than 100 ms between packets. On this PC they came with other heavy work (seen at
            # the time), so they are reported, never failed on.
            gaps = [(b[0] - a[0]) / 1000 for a, b in zip(pk, pk[1:]) if b[0] - a[0] > 100_000]
            r["stalls"].append(gaps)
    r.update(log_numbers(log, clock))
    stalls = [g for s in r["stalls"] for g in s]
    print("  round %d: %s fps, %s kbit/s; composed to received p50 %s ms p95 %s ms; arrived to sent p50 %s ms "
          "p95 %s ms; Windows delivered %s fps (window painted %s); pc-windows CPU %s %% of the PC; whole PC: CPU "
          "%.0f %%, GPU %s; stalls over 100 ms: %d%s" %
          (round_no, spread(r["fps"]), spread(r["kbps"], "%.0f"), spread(r["e2e50"]), spread(r["e2e95"]),
           spread(r["lat50"]), spread(r["lat95"]), spread(r["captured"]), spread(painted), spread(r["cpu"], "%.2f"),
           sys_cpu, ", ".join("%s %.0f %%" % (k, v) for k, v in sorted(gpu.items()) if v >= 0.5) or "idle",
           len(stalls), " (%s ms)" % ", ".join("%.0f" % g for g in sorted(stalls, reverse=True)[:6]) if stalls else ""))
    return r


def run_bench(a, out):
    for count in (1, 3):
        print("\n[bench: %d window(s), 1920x1080 at %d fps, 20000 kbit/s each, %d rounds of %.0f s%s]" %
              (count, a.fps, a.rounds, a.seconds, ", a quarter of each window noise" if a.busy else ""))
        rounds = [r for r in (bench_round(a, out, count, i + 1) for i in range(a.rounds)) if r]
        if not rounds:
            continue
        allv = lambda k: [v for r in rounds for v in (r[k] if isinstance(r[k], list) else [r[k]])]
        stalls = [g for r in rounds for s in r["stalls"] for g in s]
        print("  stalls over 100 ms in all rounds: %d%s (informative: on this PC they came with other heavy work)" %
              (len(stalls), ", longest %.0f ms, %.1f s in all" % (max(stalls), sum(stalls) / 1000) if stalls else ""))
        print("  over %d rounds (median, range): %s fps; %s kbit/s; composed to received p50 %s ms, p95 %s ms; "
              "arrived to sent p50 %s ms, p95 %s ms; pc-windows CPU %s %% of the PC; whole PC CPU %s %%; "
              "GPU video encode %s %%, 3D %s %%" %
              (len(rounds), spread(allv("fps")), spread(allv("kbps"), "%.0f"), spread(allv("e2e50")), spread(allv("e2e95")),
               spread(allv("lat50")), spread(allv("lat95")), spread(allv("cpu"), "%.2f"), spread(allv("sys_cpu"), "%.0f"),
               spread([engine(r["gpu"], "videoencode") for r in rounds], "%.0f"),
               spread([engine(r["gpu"], "3d") for r in rounds], "%.0f")))
        # Tolerant on purpose: the PC may be busy with other work. This catches a broken pipeline (a stream at a
        # few frames a second, or far off its bitrate), not a loaded PC.
        fps = allv("fps")
        check(fps and sorted(fps)[len(fps) // 2] > 40, "bench %d window(s): the median stream above 40 fps" % count)


SHOT_DIR = os.environ.get("PCW_SHOT_DIR", tempfile.gettempdir())


def main():
    global SHOT_DIR
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--build", default=os.path.join(ROOT, "pc", "build"))
    ap.add_argument("--out", default=None)
    ap.add_argument("--shots", default=None, help="where to save a decoded frame as PNG")
    ap.add_argument("--tls", choices=("1.2", "1.3"), default="1.3")
    ap.add_argument("--bench", action="store_true")
    ap.add_argument("--codec", choices=("hevc", "h264"), default=None)
    ap.add_argument("--seconds", type=float, default=15)
    ap.add_argument("--busy", action="store_true", help="bench: a quarter of each window is new noise every frame")
    ap.add_argument("--rounds", type=int, default=3, help="bench: rounds of each measurement (median and range)")
    ap.add_argument("--fps", type=int, default=60, help="bench: the fps asked for (the headset asks its refresh rate)")
    ap.add_argument("--keep", action="store_true", help="keep the recordings")
    ap.add_argument("--h264-only", action="store_true", help=argparse.SUPPRESS)
    a = ap.parse_args()
    out = a.out or tempfile.mkdtemp(prefix="pcw_fake_headset_")
    os.makedirs(out, exist_ok=True)
    SHOT_DIR = a.shots or out
    print("recordings in %s" % out)
    try:
        if a.bench:
            run_bench(a, out)
        else:
            run_e2e(a, out)
    finally:
        if not a.keep:
            # The sound recording holds whatever the PC played during the test: never kept unless asked.
            for f in os.listdir(out):
                if f.endswith(".aac"):
                    os.remove(os.path.join(out, f))
    failed = [w for ok, w in RESULTS if not ok]
    print("\n%d checks, %d failed" % (len(RESULTS), len(failed)))
    for w in failed:
        print("  FAILED: " + w)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
