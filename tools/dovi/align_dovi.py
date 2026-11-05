"""The frame offset between two encodes of one master (docs/dolby-vision.md), from runs of consecutive frames
(frame_seq.sh): for each frame of encode A, the frame of encode B whose luma layout correlates best.

    python3 tools/dovi/align_dovi.py <seq folder>

Prints the offset per time; a constant offset with correlation 1.000 means the same cut. Give it to frame_grid.sh as
P8_OFFSET."""
import glob
import os
import sys

import numpy as np

D = sys.argv[1] if len(sys.argv) > 1 else "seq"


def load_seq(path):
    frames, cur, pts = [], None, None
    for l in open(path):
        if l.startswith("#"):
            if cur is not None:
                frames.append((pts, np.array(cur)))
            cur, pts = [], float(l.split("(")[1].split()[0])
        else:
            cur.append([float(v) for v in l.split()[2:5]])
    if cur is not None:
        frames.append((pts, np.array(cur)))
    return frames


for p5 in sorted(glob.glob(os.path.join(D, "p5_*.txt"))):
    s5 = load_seq(p5)
    s8 = load_seq(p5.replace("p5_", "p8_"))
    y8 = np.array([f[1][:, 0] for f in s8])
    t8 = np.array([f[0] for f in s8])
    offsets = []
    for pts5, g in s5:
        c = np.array([np.corrcoef(g[:, 0], y)[0, 1] for y in y8])
        j = int(np.argmax(c))
        offsets.append((pts5, t8[j], c[j], np.sort(c)[-2]))
    print(os.path.basename(p5))
    for pts5, best, c, second in offsets[:3] + offsets[-2:]:
        print("  A %.3f -> B %.3f (offset %+.3f s, %+.1f frames at 23.976) corr %.3f, runner-up %.3f"
              % (pts5, best, best - pts5, (best - pts5) * 24000 / 1001, c, second))
    d = np.array([b - a for a, b, _, _ in offsets])
    print("  offset median %+.3f s (%+.2f frames), spread %.3f" % (np.median(d), np.median(d) * 24000 / 1001, d.std()))
