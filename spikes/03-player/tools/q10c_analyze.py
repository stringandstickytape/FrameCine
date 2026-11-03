"""Compares a Q10C plane as the GPU decompressed it (main.gd --dump-planes, RGBA8 texels = 32-bit words) with a
reference decode of the same frame (yuv420p10le), to tell whether the words are right but reordered (fixable in the
shader) or wrong (the texture unit decompresses the video core's TP10 differently).

  py q10c_analyze.py DUMP_PLANE0.png REF.yuv WIDTH HEIGHT [DUMP_PLANE1.png]
  py q10c_analyze.py --selftest
"""
import sys
from collections import Counter, defaultdict

import numpy as np
from PIL import Image


def words_from_dump(path):
    rgba = np.asarray(Image.open(path).convert("RGBA")).astype(np.uint32)
    return rgba[..., 0] | (rgba[..., 1] << 8) | (rgba[..., 2] << 16) | (rgba[..., 3] << 24)


def tp10_words(samples):
    """Rows of 10-bit samples -> rows of words, 3 samples per word, sample 0 in bits 0-9 (the assumed TP10 packing)."""
    h, n = samples.shape
    n3 = n // 3
    s = samples[:, : n3 * 3].reshape(h, n3, 3).astype(np.uint32)
    return s[..., 0] | (s[..., 1] << 10) | (s[..., 2] << 20)


def analyze(name, dump, ref, block=(16, 64)):
    """dump, ref: word arrays; ref may be smaller (the picture without padding)."""
    h = min(dump.shape[0], ref.shape[0])
    w = min(dump.shape[1], ref.shape[1])
    d = dump[:h, :w]
    r = ref[:h, :w]
    print(f"== {name}: dump {dump.shape}, reference {ref.shape}, compared {h}x{w} words")
    print(f"   same word at the same place: {100 * (d == r).mean():.2f}%")
    print(f"   top 2 bits zero in the dump: {100 * ((d >> 30) == 0).mean():.2f}% (TP10 leaves them zero)")
    for bits, label in ((0, "sample 0 (bits 0-9)"), (10, "sample 1"), (20, "sample 2")):
        dv = ((d >> bits) & 1023).astype(np.int32)
        rv = ((r >> bits) & 1023).astype(np.int32)
        print(f"   {label}: mean |dump - ref| {np.abs(dv - rv).mean():.1f} (10-bit codes)")

    # Does each dumped word occur in the reference nearby (same block of block[0] x block[1] words)? A permutation keeps
    # the values; a different decompression doesn't.
    bh, bw = block
    rng = np.random.default_rng(1)
    found = total = 0
    offsets = defaultdict(Counter)
    rows = (h // bh) * bh
    cols = (w // bw) * bw
    for _ in range(300):
        by = int(rng.integers(0, rows // bh)) * bh
        bx = int(rng.integers(0, cols // bw)) * bw
        rb = r[by : by + bh, bx : bx + bw]
        db = d[by : by + bh, bx : bx + bw]
        where = defaultdict(list)
        for (y, x), v in np.ndenumerate(rb):
            where[int(v)].append((y, x))
        for (y, x), v in np.ndenumerate(db):
            total += 1
            places = where.get(int(v))
            if places:
                found += 1
                if len(places) == 1:
                    offsets[(y % 4, x % 16)][(places[0][0] - y, places[0][1] - x)] += 1
    print(f"   dumped words found in the same {bh}x{bw}-word block of the reference: {100 * found / max(total, 1):.1f}%")
    if found > total * 0.5:
        print("   most common (dy, dx) from dump position to reference position, per position in a 4x16-word tile:")
        for y in range(4):
            line = []
            for x in range(16):
                c = offsets.get((y, x))
                if c:
                    (off, n), = c.most_common(1)
                    line.append(f"{off[0]:+d},{off[1]:+d}({100 * n / sum(c.values()):.0f}%)")
                else:
                    line.append("?")
            print("     row %d: %s" % (y, " ".join(line)))


def load_reference(path, width, height):
    raw = np.fromfile(path, dtype="<u2")
    y = raw[: width * height].reshape(height, width)
    cw, ch = width // 2, height // 2
    u = raw[width * height : width * height + cw * ch].reshape(ch, cw)
    v = raw[width * height + cw * ch : width * height + 2 * cw * ch].reshape(ch, cw)
    uv = np.empty((ch, cw * 2), dtype=np.uint16)
    uv[:, 0::2] = u
    uv[:, 1::2] = v
    return y, uv


def selftest():
    rng = np.random.default_rng(0)
    y = rng.integers(64, 940, size=(64, 384)).astype(np.uint16)
    ref = tp10_words(y)
    # A made-up permutation inside 4x16 tiles: swap the two halves of each row and reverse the rows.
    dump = ref.copy()
    for ty in range(0, ref.shape[0], 4):
        for tx in range(0, ref.shape[1], 16):
            t = ref[ty : ty + 4, tx : tx + 16]
            dump[ty : ty + 4, tx : tx + 16] = np.roll(t[::-1], 8, axis=1)
    analyze("selftest (expect 100% found, offsets of a row flip and an 8-word roll)", dump, ref)
    analyze("selftest garbage (expect ~0% found)", rng.integers(0, 2**30, size=ref.shape).astype(np.uint32), ref)


if __name__ == "__main__":
    if sys.argv[1:] == ["--selftest"]:
        selftest()
        sys.exit(0)
    dump0, ref_path, width, height = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
    y, uv = load_reference(ref_path, width, height)
    analyze("Y plane", words_from_dump(dump0), tp10_words(y))
    if len(sys.argv) > 5:
        analyze("CbCr plane", words_from_dump(sys.argv[5]), tp10_words(uv))
