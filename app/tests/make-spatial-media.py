#!/usr/bin/env python3
"""Makes the audio files of tests/test_spatial_audio.gd's engine checks (spatial audio, docs/features.md #21): one
short WAV per channel layout, each channel a tone of its own (channel k: 1500 + 400 k Hz, high enough for clear level
differences between the ears), with the WAVE_FORMAT_EXTENSIBLE channel mask that tells FFmpeg the layout; and a
first-order ambisonic file (AmbiX) as MP4 with the SA3D box that 360 video carries, remuxed by the remux-only ffmpeg
of build/ffmpeg-build.sh tool. No encoder, no recorded sound.

Run in WSL: python3 app/tests/make-spatial-media.py   (writes $MEDIA_TESTS/app-features/spatial, default
~/media-tests)."""
import math
import os
import struct
import subprocess
import sys

RATE = 48000
SECONDS = 1.5
OUT = os.path.join(os.environ.get("MEDIA_TESTS", os.path.expanduser("~/media-tests")), "app-features", "spatial")
FFMPEG = os.environ.get("FFMPEG", os.path.expanduser("~/src/ffmpeg-tool/bin/ffmpeg"))

# WAVE_FORMAT_EXTENSIBLE speaker bits.
FL, FR, FC, LFE, BL, BR, FLC, FRC, BC, SL, SR, TC, TFL, TFC, TFR, TBL, TBC, TBR = [1 << i for i in range(18)]
LAYOUTS = {
    "mono": FC,
    "stereo": FL | FR,
    "3.0": FL | FR | FC,
    "quad": FL | FR | BL | BR,
    "5.0": FL | FR | FC | SL | SR,
    "5.1": FL | FR | FC | LFE | SL | SR,
    "5.1back": FL | FR | FC | LFE | BL | BR,
    "6.1": FL | FR | FC | LFE | BC | SL | SR,
    "7.1": FL | FR | FC | LFE | BL | BR | SL | SR,
    "5.1.2": FL | FR | FC | LFE | SL | SR | TFL | TFR,
    "7.1.4": FL | FR | FC | LFE | BL | BR | SL | SR | TFL | TFR | TBL | TBR,
}


def tone(k, i):
    return 0.2 * math.sin(2.0 * math.pi * (1500.0 + 400.0 * k) * i / RATE)


def write_wav(path, channels, mask, sample):
    frames = int(RATE * SECONDS)
    data = bytearray()
    for i in range(frames):
        for c in range(channels):
            data += struct.pack("<h", max(-32767, min(32767, int(round(sample(c, i) * 32767)))))
    fmt = struct.pack("<HHIIHHHHI16s", 0xFFFE, channels, RATE, RATE * channels * 2, channels * 2, 16, 22, 16, mask,
                      bytes.fromhex("0100000000001000800000aa00389b71"))
    with open(path, "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", 4 + 8 + len(fmt) + 8 + len(data)) + b"WAVE")
        f.write(b"fmt " + struct.pack("<I", len(fmt)) + fmt)
        f.write(b"data" + struct.pack("<I", len(data)) + data)


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, mask in LAYOUTS.items():
        n = bin(mask).count("1")
        write_wav(os.path.join(OUT, "layout_%s.wav" % name), n, mask, tone)
    # First-order AmbiX of a 500 Hz tone from the listener's left (W = 1, Y = 1, Z = 0, X = 0: ACN order, SN3D),
    # then the same with the head-locked stereo pair after it (a 900 Hz tone on the left of the pair only).
    foa = os.path.join(OUT, "foa_left.wav")
    write_wav(foa, 4, 0, lambda c, i: 0.2 * math.sin(2.0 * math.pi * 500.0 * i / RATE) * (1.0 if c in (0, 1) else 0.0))
    foa_hl = os.path.join(OUT, "foa_left_headlocked.wav")
    write_wav(foa_hl, 6, 0, lambda c, i: (0.2 * math.sin(2.0 * math.pi * 500.0 * i / RATE) if c in (0, 1) else 0.0)
              + (0.2 * math.sin(2.0 * math.pi * 900.0 * i / RATE) if c == 4 else 0.0))
    for src, layout, out in [(foa, "ambisonic 1", "foa_left.mp4"), (foa_hl, "ambisonic 1+stereo", "foa_left_headlocked.mp4")]:
        r = subprocess.run([FFMPEG, "-hide_banner", "-loglevel", "error", "-y", "-i", src, "-c:a", "copy",
                            "-metadata:s:a:0", "SA3D=" + layout, os.path.join(OUT, out)])
        if r.returncode != 0:
            print("ffmpeg could not write %s (a remux-only build with the mp4 muxer and the wav demuxer is needed)"
                  % out, file=sys.stderr)
            return 1
    print("Wrote %d files to %s" % (len(LAYOUTS) + 4, OUT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
