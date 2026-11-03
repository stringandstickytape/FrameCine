#!/usr/bin/env python3
"""The PC end of PC audio sync (idea #9; docs/pc-audio.md). Python 3.8+, standard library only; plays sound when the
optional `sounddevice` or `pyaudio` package is installed, else consumes the samples on this PC's clock as a speaker
would (and can write them to a WAV file), so the clock reports are real either way.

    python tools/audio_sink.py [--port 47820] [--target-ms 120] [--wav out.wav] [--output auto|null]

The headset connects out to this port (it listens on the PC; nothing listens on the headset). It sends a JSON line
{v, rate, channels, format} and then frames "A" [u32 bytes][f64 media time of the first sample][f64 headset clock][PCM
s16le stereo]. This program keeps a jitter buffer of --target-ms, plays from it, and sends back 10 times a second
{t: "clock", media: the media time at the speaker now, buffer_ms, underruns, drift_ppm}; it answers {t: "ping", h}
with {t: "pong", h}. The headset holds its video back by the measured delay.

Clock drift (the PC's sound card and the headset's mixer never run at exactly the same rate) is absorbed by dropping
or repeating one sample when the buffer strays 20 ms from the target; drift_ppm reports the difference.
"""

import argparse
import collections
import json
import socket
import struct
import sys
import threading
import time
import wave



def tcp_server_socket():
    """A TCP socket for a server. On Windows, SO_REUSEADDR lets a second process bind a port in use (both then get
    connections), so a stale listener would answer instead of the new one: there it binds exclusively."""
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    if hasattr(socket, "SO_EXCLUSIVEADDRUSE"):
        s.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
    else:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    return s

class Buffer:
    """Audio frames with their media times; read by the output at its own pace."""

    def __init__(self, rate, target_s):
        self.rate = rate
        self.target = target_s
        self.chunks = collections.deque()   # [media_t_first, bytes, offset_in_bytes]
        self.frames = 0
        self.lock = threading.Lock()
        self.played_media = None             # the media time of the last frame handed to the output
        self.underruns = 0
        self.jumps = 0
        self.skipped_ms = 0.0
        self.dropped = 0
        self.repeated = 0
        self.started = False

    def push(self, media_t, pcm):
        with self.lock:
            # A seek on the headset: the new audio does not follow on from the last; drop what is queued.
            if self.chunks:
                last_t, last_pcm, _ = self.chunks[-1]
                if abs(media_t - (last_t + len(last_pcm) / 4 / self.rate)) > 0.1:
                    self.chunks.clear()
                    self.frames = 0
                    self.started = False
                    self.jumps += 1
            self.chunks.append([media_t, pcm, 0])
            self.frames += len(pcm) // 4

    def level_s(self):
        return self.frames / self.rate

    def pull(self, n):
        """n stereo frames as bytes (silence when short), adjusting by one frame to hold the target level."""
        out = bytearray()
        with self.lock:
            if not self.started:
                if self.level_s() < self.target:
                    return bytes(4 * n)
                self.started = True
            level = self.level_s()
            if level > self.target + 0.25:
                # Far behind (a backlog at the start): skip to the target at once.
                self._skip(int((level - self.target) * self.rate))
                level = self.level_s()
            want = n
            # Near the target: one frame in 100 at most (1 %), towards it.
            k = min(max(n // 100, 1), int(abs(level - self.target) * self.rate))
            if level > self.target + 0.02 and self.frames > n + k:
                want = n + k          # behind: drop frames
                self.dropped += k
            elif self.target - 0.02 > level > 0:
                want = n - k          # ahead: repeat
                self.repeated += k
            while want > 0 and self.chunks:
                media_t, pcm, off = self.chunks[0]
                take = min(want * 4, len(pcm) - off)
                out += pcm[off:off + take]
                self.chunks[0][2] += take
                frames = take // 4
                self.frames -= frames
                want -= frames
                self.played_media = media_t + (off + take) / 4 / self.rate
                if self.chunks[0][2] >= len(pcm):
                    self.chunks.popleft()
            if want > 0:
                self.underruns += 1
                self.started = False
        short = 4 * n - len(out)
        if short > 0:
            # Repeated frames (ahead), or silence (an underrun).
            out += (out[-4:] * (short // 4)) if len(out) >= 4 and short <= 4 * max(n // 100, 1) else bytes(short)
        return bytes(out[:4 * n])

    def _skip(self, frames):
        """Drops `frames` from the front (lock held)."""
        self.skipped_ms += frames / self.rate * 1000
        while frames > 0 and self.chunks:
            media_t, pcm, off = self.chunks[0]
            take = min(frames * 4, len(pcm) - off)
            self.chunks[0][2] += take
            self.frames -= take // 4
            frames -= take // 4
            if self.chunks[0][2] >= len(pcm):
                self.chunks.popleft()


class NullOutput:
    """Consumes frames on this PC's clock in 10 ms blocks; optionally writes them to a WAV file."""
    latency = 0.0

    def __init__(self, rate, buf, wav_path):
        self.rate, self.buf = rate, buf
        self.wav = None
        if wav_path:
            self.wav = wave.open(wav_path, "wb")
            self.wav.setnchannels(2)
            self.wav.setsampwidth(2)
            self.wav.setframerate(rate)
        self.stop = False
        threading.Thread(target=self.run, daemon=True).start()

    def run(self):
        block = self.rate // 100
        t = time.monotonic()
        while not self.stop:
            data = self.buf.pull(block)
            if self.wav:
                self.wav.writeframes(data)
            t += block / self.rate
            delay = t - time.monotonic()
            if delay > 0:
                time.sleep(delay)

    def close(self):
        self.stop = True
        if self.wav:
            self.wav.close()


def open_output(kind, rate, buf, wav_path):
    if kind in ("auto", "sounddevice"):
        try:
            import sounddevice  # type: ignore

            def cb(outdata, frames, _time, _status):
                outdata[:] = buf.pull(frames)
            s = sounddevice.RawOutputStream(samplerate=rate, channels=2, dtype="int16", callback=cb, blocksize=0)
            s.start()
            s.latency_s = float(s.latency)
            print("output: sounddevice, %.0f ms device latency" % (s.latency_s * 1000), flush=True)
            return s, s.latency_s
        except Exception:  # noqa: BLE001 - optional package
            pass
    if kind in ("auto", "pyaudio"):
        try:
            import pyaudio  # type: ignore
            pa = pyaudio.PyAudio()
            s = pa.open(format=pyaudio.paInt16, channels=2, rate=rate, output=True,
                        stream_callback=lambda _in, frames, _t, _s: (buf.pull(frames), pyaudio.paContinue))
            s.start_stream()
            lat = float(s.get_output_latency())
            print("output: pyaudio, %.0f ms device latency" % (lat * 1000), flush=True)
            return s, lat
        except Exception:  # noqa: BLE001
            pass
    print("output: none (no sounddevice or pyaudio): samples consumed on the PC clock%s"
          % (", written to " + wav_path if wav_path else ""), flush=True)
    return NullOutput(rate, buf, wav_path), 0.0


def serve_one(conn, addr, a):
    f = conn.makefile("rb")
    head = json.loads(f.readline().decode())
    rate = int(head["rate"])
    print("headset %s:%d: %s, %d Hz %s" % (addr[0], addr[1], head.get("app"), rate, head.get("format")), flush=True)
    buf = Buffer(rate, a.target_ms / 1000.0)
    out, latency = open_output(a.output, rate, buf, a.wav)
    send_lock = threading.Lock()
    stop = threading.Event()
    stats = {"frames": 0, "first_rx": None, "first_media": None}

    def send(obj):
        with send_lock:
            conn.sendall((json.dumps(obj) + "\n").encode())

    def reporter():
        last_print = 0.0
        while not stop.is_set():
            time.sleep(0.1)
            if buf.played_media is None:
                continue
            # The media time at the speaker: the last frame handed out, less what is still in the device.
            media = buf.played_media - latency
            # Drift: frames received against this PC's clock, from a baseline taken 3 s in (after the start burst).
            drift = 0.0
            now = time.monotonic()
            if stats["first_rx"] is not None and now - stats["first_rx"] > 3 and stats.get("base") is None:
                stats["base"] = (now, stats["frames"])
            if stats.get("base") is not None and now - stats["base"][0] > 5:
                wall = now - stats["base"][0]
                drift = ((stats["frames"] - stats["base"][1]) / rate - wall) / wall * 1e6
            try:
                send({"t": "clock", "media": round(media, 4), "buffer_ms": round(buf.level_s() * 1000, 1),
                      "underruns": buf.underruns, "drift_ppm": round(drift, 1), "dropped": buf.dropped,
                      "repeated": buf.repeated, "jumps": buf.jumps, "skipped_ms": round(buf.skipped_ms)})
            except OSError:
                return
            if time.monotonic() - last_print > 1.0:
                last_print = time.monotonic()
                print(json.dumps({"media": round(media, 3), "buffer_ms": round(buf.level_s() * 1000, 1),
                                  "received_s": round(stats["frames"] / rate, 2), "underruns": buf.underruns,
                                  "dropped": buf.dropped, "repeated": buf.repeated, "jumps": buf.jumps,
                                  "skipped_ms": round(buf.skipped_ms)}), flush=True)

    threading.Thread(target=reporter, daemon=True).start()
    try:
        while True:
            # A JSON line (ping) starts with "{"; a frame with "A".
            first = f.read(1)
            if not first:
                break
            if first == b"{":
                msg = json.loads((first + f.readline()).decode())
                if msg.get("t") == "ping":
                    send({"t": "pong", "h": msg.get("h")})
                continue
            if first != b"A":
                print("bad stream byte %r; closing" % first, flush=True)
                break
            rest = f.read(20)
            if len(rest) < 20:
                break
            n = struct.unpack("<I", rest[:4])[0]
            media_t, _hclock = struct.unpack("<dd", rest[4:20])
            pcm = f.read(n)
            if len(pcm) < n:
                break
            if stats["first_rx"] is None:
                stats["first_rx"] = time.monotonic()
            stats["frames"] += n // 4
            buf.push(media_t, pcm)
    except (ConnectionError, OSError, ValueError):
        pass
    finally:
        stop.set()
        out.close() if hasattr(out, "close") else None
        print("headset gone (%.1f s received, %d underruns)" % (stats["frames"] / rate, buf.underruns), flush=True)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", type=int, default=47820)
    ap.add_argument("--bind", default="0.0.0.0")
    ap.add_argument("--target-ms", type=float, default=120.0, help="jitter buffer")
    ap.add_argument("--wav", help="also write what is played to this WAV file")
    ap.add_argument("--output", default="auto", choices=["auto", "sounddevice", "pyaudio", "null"])
    ap.add_argument("--once", action="store_true", help="exit after the first headset leaves")
    a = ap.parse_args(argv)
    srv = tcp_server_socket()
    srv.bind((a.bind, a.port))
    srv.listen(1)
    print("audio sink: waiting for the headset on %s:%d" % (a.bind, a.port), flush=True)
    try:
        while True:
            conn, addr = srv.accept()
            conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            serve_one(conn, addr, a)
            if a.once:
                return 0
    except KeyboardInterrupt:
        return 0


if __name__ == "__main__":
    sys.exit(main())
