"""Spike 04: compares the probe's results (yuv420p10le of the visible area) with FFmpeg's decode of the same frame.

    python compare.py REF.yuv RESULT.yuv [RESULT.yuv ...] --size 3832x1596 [--png]

Prints PSNR (10-bit peak) and the share of identical samples per plane; --png writes RESULT.png next to each result
(BT.709, limited range; --bt2020 for BT.2020). Needs numpy (and Pillow for --png). --selftest checks the maths.
"""
import argparse
import sys

import numpy as np


def load(path, w, h):
    data = np.fromfile(path, dtype="<u2")
    want = w * h * 3 // 2
    if data.size != want:
        raise SystemExit(f"{path}: {data.size * 2} bytes, yuv420p10le {w}x{h} has {want * 2}")
    y = data[: w * h].reshape(h, w)
    u = data[w * h : w * h + (w // 2) * (h // 2)].reshape(h // 2, w // 2)
    v = data[w * h + (w // 2) * (h // 2) :].reshape(h // 2, w // 2)
    return y.astype(np.int32), u.astype(np.int32), v.astype(np.int32)


def compare(ref, got):
    out = []
    for name, a, b in zip(("Y", "Cb", "Cr"), ref, got):
        d = (a - b).astype(np.float64)
        mse = float(np.mean(d * d))
        psnr = float("inf") if mse == 0 else 10 * np.log10(1023.0 * 1023.0 / mse)
        same = float(np.mean(d == 0)) * 100
        out.append((name, psnr, same, int(np.max(np.abs(d)))))
    return out


def to_png(planes, path, bt2020):
    from PIL import Image

    y, u, v = planes
    kr, kb = (0.2627, 0.0593) if bt2020 else (0.2126, 0.0722)
    kg = 1 - kr - kb
    u = np.repeat(np.repeat(u, 2, axis=0), 2, axis=1)[: y.shape[0], : y.shape[1]]
    v = np.repeat(np.repeat(v, 2, axis=0), 2, axis=1)[: y.shape[0], : y.shape[1]]
    yy = (y - 64) / 876.0
    cb = (u - 512) / 896.0
    cr = (v - 512) / 896.0
    r = yy + 2 * (1 - kr) * cr
    b = yy + 2 * (1 - kb) * cb
    g = (yy - kr * r - kb * b) / kg
    rgb = np.clip(np.stack([r, g, b], axis=-1), 0, 1)
    Image.fromarray((rgb * 255 + 0.5).astype(np.uint8)).save(path)


def selftest():
    rng = np.random.default_rng(1)
    w, h = 64, 32
    ref = (rng.integers(64, 941, (h, w)), rng.integers(64, 961, (h // 2, w // 2)), rng.integers(64, 961, (h // 2, w // 2)))
    same = compare(ref, ref)
    assert all(s[2] == 100.0 and s[1] == float("inf") for s in same), same
    noisy = (ref[0] + 1, ref[1], ref[2])
    r = compare(ref, noisy)
    assert abs(r[0][1] - 10 * np.log10(1023.0 * 1023.0)) < 1e-6 and r[0][2] == 0.0 and r[1][2] == 100.0, r
    print("selftest PASS")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="*")
    ap.add_argument("--size", default="3832x1596")
    ap.add_argument("--png", action="store_true")
    ap.add_argument("--bt2020", action="store_true")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        selftest()
        return
    if len(a.files) < 2:
        ap.error("give the reference and at least one result")
    w, h = (int(x) for x in a.size.split("x"))
    ref = load(a.files[0], w, h)
    for path in a.files[1:]:
        got = load(path, w, h)
        parts = [f"{n} PSNR {p:.2f} dB, identical {s:.2f}%, max diff {m}" for n, p, s, m in compare(ref, got)]
        print(f"{path}: " + "; ".join(parts))
        if a.png:
            to_png(got, path.rsplit(".", 1)[0] + ".png", a.bt2020)
    if a.png:
        to_png(ref, a.files[0].rsplit(".", 1)[0] + ".png", a.bt2020)


if __name__ == "__main__":
    sys.exit(main())
