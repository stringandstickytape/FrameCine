"""Fits the linear LMS -> BT.2020 RGB matrix of a Dolby Vision profile 5 base layer against an HDR10 (or profile 8)
encode of the same master (docs/dolby-vision.md): block means of the same frames of both, from frame_grid.sh.

    python3 tools/dovi/fit_dovi.py <grids folder>

p5_<t>.txt: the profile 5 file's I'P'T' planes; p8_<t>.txt: the HDR10 file's Y'CbCr planes, frame-aligned
(align_dovi.py for the offset). Prints the fitted matrix, its error, and the error of the published candidates."""
import glob
import os
import sys

import numpy as np

np.set_printoptions(precision=5, suppress=True, linewidth=120)
D = sys.argv[1] if len(sys.argv) > 1 else "grids"

M1, M2, C1, C2, C3 = 0.1593017578125, 78.84375, 0.8359375, 18.8515625, 18.6875


def pq_eotf(e):
    e = np.clip(e, 0.0, 1.0)
    p = e ** (1.0 / M2)
    return 10000.0 * (np.maximum(p - C1, 0.0) / (C2 - C3 * p)) ** (1.0 / M1)


def load(path):
    rows = [l.split() for l in open(path) if not l.startswith("#")]
    return np.array([[float(v) for v in r[2:5]] for r in rows])


# The RPU's ycc_to_rgb_matrix (I'P'T' -> L'M'S') and its rgb_to_lms_matrix (the inverse of a 2 % crosstalk).
NL = np.array([[1, 0.09753418, 0.20520020], [1, -0.11389160, 0.13317871], [1, 0.03259277, -0.67687988]])
CT_INV = np.array([[1.04254150, -0.02130127, -0.02130127], [-0.02130127, 1.04254150, -0.02130127],
                   [-0.02130127, -0.02130127, 1.04254150]])
IPT_RGB2LMS = np.array([[0.3592, 0.6976, -0.0358], [-0.1922, 1.1004, 0.0755], [0.0070, 0.0749, 0.8434]])
BT2100_RGB2LMS = np.array([[1688, 2146, 262], [683, 2951, 99], [99, 309, 3688]]) / 4096.0

lms_all, rgb_all = [], []
for p5 in sorted(glob.glob(os.path.join(D, "p5_*.txt"))):
    a5, a8 = load(p5), load(p5.replace("p5_", "p8_"))
    # HDR10: limited-range 10-bit Y'CbCr BT.2020 (non-constant luminance) -> PQ R'G'B' -> nits
    y = (a8[:, 0] - 64.0) / 876.0
    cb = (a8[:, 1] - 512.0) / 896.0
    cr = (a8[:, 2] - 512.0) / 896.0
    r = y + 1.4746 * cr
    b = y + 1.8814 * cb
    g = (y - 0.2627 * r - 0.0593 * b) / 0.6780
    rgb = pq_eotf(np.stack([r, g, b], 1))
    # profile 5: the same range step, then I'P'T' -> L'M'S' -> nits
    i = (a5[:, 0] - 64.0) / 876.0
    p = (a5[:, 1] - 512.0) / 896.0
    t = (a5[:, 2] - 512.0) / 896.0
    lms = pq_eotf((NL @ np.stack([i, p, t], 0)).T)
    lms_all.append(lms)
    rgb_all.append(rgb)
    print(os.path.basename(p5), "luma correlation with the HDR10 frame: %.4f" % np.corrcoef(i, y)[0, 1],
          "(aligned frames correlate above 0.999)")

if not lms_all:
    sys.exit("no p5_*.txt in " + D)
lms = np.concatenate(lms_all)
rgb = np.concatenate(rgb_all)
keep = (rgb.max(1) > 1.0) & (rgb.max(1) < 3000.0)  # not near black (noise), not clipped
lms, rgb = lms[keep], rgb[keep]
print("blocks used:", len(lms))
MT, *_ = np.linalg.lstsq(lms, rgb, rcond=None)
M = MT.T
print("fitted LMS -> RGB (row-major; the shader's DOVI_LMS_TO_RGB is this, column-major):\n", M)


def report(name, cand):
    pred = lms @ cand.T
    err = np.abs(pred - rgb) / np.maximum(rgb.max(1, keepdims=True), 5.0)
    print("%-44s median rel err %.3f  90th %.3f" % (name, np.median(err), np.percentile(err, 90)))


report("fitted", M)
report("IPT 0.3592 LMS, crosstalk out", np.linalg.inv(IPT_RGB2LMS) @ CT_INV)
report("IPT 0.3592 LMS, no crosstalk step", np.linalg.inv(IPT_RGB2LMS))
report("BT.2100 LMS, crosstalk out", np.linalg.inv(BT2100_RGB2LMS) @ CT_INV)
report("BT.2100 LMS, no crosstalk step", np.linalg.inv(BT2100_RGB2LMS))
print("mean luminance ratio HDR10 / fit: %.3f (a different grade would show here)" % (rgb.mean() / (lms @ M.T).mean()))
