"""Stage 1: tessellate every STEP solid (high-res), store per-B-rep-face ids + shell ids in work/*.npz."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, trimesh, json
from OCP.TopExp import TopExp_Explorer
from OCP.TopAbs import TopAbs_SHELL, TopAbs_FACE
from OCP.TopTools import TopTools_IndexedMapOfShape
from OCP.TopExp import TopExp
from cadlib import read_step, tessellate, faces_of

SRC = os.path.expanduser("~/cad/steam-frame-controller/src/unzipped/")
WORK = os.path.expanduser("~/cad/steam-frame-controller/work/"); os.makedirs(WORK, exist_ok=True)
LIN, ANG = float(os.environ.get("LIN", 0.05)), float(os.environ.get("ANG", 0.3))
jobs = {}
for h in "LR":
    jobs[f"{h}_body"] = f"Valve_Steam_Frame_Controller_{h}_20260926.stp"
    jobs[f"{h}_door"] = f"Valve_Steam_Frame_Cntrl_Batt_Door_{h}_20260925.stp"
    jobs[f"{h}_strap"] = f"Valve_Steam_Frame_Cntrl_Batt_Door_Strap_{h}_20260927.stp"
meta = {}
for key, fn in jobs.items():
    (name, shp), = read_step(SRC + fn)
    fs = faces_of(shp)
    # shell id per face (index in TopExp order of shells)
    shell_of = np.zeros(len(fs), int)
    ex = TopExp_Explorer(shp, TopAbs_SHELL); si = 0
    while ex.More():
        e2 = TopExp_Explorer(ex.Current(), TopAbs_FACE)
        while e2.More():
            f = e2.Current()
            for i, g in enumerate(fs):
                if g.IsSame(f):
                    shell_of[i] = si
            e2.Next()
        si += 1; ex.Next()
    V, F, fid = tessellate(shp, LIN, ANG)
    np.savez(WORK + f"{key}.npz", V=V, F=F, fid=fid, shell=shell_of)
    tm = trimesh.Trimesh(V, F)
    meta[key] = dict(file=fn, product=name, faces=len(fs), shells=int(si), tris=int(len(F)),
                     bounds=tm.bounds.round(3).tolist(), volume=round(float(tm.volume), 1))
    print(key, meta[key], flush=True)
json.dump(meta, open(WORK + "tess_meta.json", "w"), indent=1)
