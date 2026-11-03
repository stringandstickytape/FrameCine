"""Stage 2: segment the fused PV solid into named parts (by B-rep face), export high-res + low-poly GLBs.
Usage: build.py L|R
"""
import sys, os, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, trimesh
import fast_simplification

ROOT = os.path.expanduser("~/cad/steam-frame-controller/")
WORK, OUT = ROOT + "work/", ROOT + "out/"
os.makedirs(OUT, exist_ok=True)
hand = sys.argv[1]
S = 1.0 if hand == "L" else -1.0       # mirror factor: rules are written in the LEFT controller's frame
HANDNAME = {"L": "left", "R": "right"}[hand]

b = np.load(WORK + f"{hand}_body.npz")
V, F, fid, shell = b["V"], b["F"], b["fid"], b["shell"]
nface = fid.max() + 1

# --- drop internal void shell(s): keep only the shell with the most B-rep faces
main_shell = np.bincount(shell).argmax()
keep_face = shell == main_shell
print("void-shell B-rep faces dropped:", int((~keep_face[:len(shell)]).sum()))

tm = trimesh.Trimesh(V, F, process=False)
areas = tm.area_faces; tn = tm.face_normals; tc = tm.triangles_center

# --- per B-rep face stats (in left-hand frame: x -> S*x)
st = {}
for i in range(nface):
    sel = fid == i
    if not sel.any() or not keep_face[i]:
        continue
    vv = V[np.unique(F[sel])].copy(); vv[:, 0] *= S
    a = areas[sel]; n = tn[sel].copy(); n[:, 0] *= S; c = tc[sel].copy(); c[:, 0] *= S
    st[i] = dict(lo=vv.min(0), hi=vv.max(0), vv=vv, n=n, a=a, c=c, area=a.sum())

def within_r(s, ctr, r):
    return np.linalg.norm(s["vv"][:, :2] - ctr, axis=1).max() <= r

def in_box(s, lo, hi):
    return (s["lo"] >= np.array(lo)).all() and (s["hi"] <= np.array(hi)).all()

def radial_dot(s, ctr):
    d = s["c"][:, :2] - ctr; d /= np.linalg.norm(d, axis=1, keepdims=True) + 1e-9
    return float(((s["n"][:, :2] * d).sum(1) * s["a"]).sum() / s["a"].sum())

def nz(s):
    return float((s["n"][:, 2] * s["a"]).sum() / s["a"].sum())

assign = {}
def take(name, pred):
    got = [i for i, s in st.items() if i not in assign and pred(s)]
    for i in got:
        assign[i] = name
    print(f"  {name:16s} B-rep faces: {len(got)}")
    return got

# thumbstick: cap + shaft + dome, everything near the stick axis that rises above the bowl lip
STICK = np.array([13.1, -10.2])
take("thumbstick", lambda s: within_r(s, STICK, 12.5) and s["hi"][2] >= 0.5)

if hand == "L":
    take("dpad", lambda s: in_box(s, [-27, -16, -5.5], [-3, 9.5, 5]) and s["hi"][2] > -0.5)
else:
    # ABXY in a diamond; Xbox/Steam convention assumed: Y=top(+Y, forward), A=bottom, X=inner(-X for right hand), B=outer
    # centres in the LEFT frame (x mirrored): right-hand +X maps to -X here
    for nm, (cx, cy) in {"button_y": (-15.0, 5.6), "button_a": (-15.0, -12.0), "button_x": (-8.0, -3.2),
                         "button_b": (-23.0, -3.2)}.items():
        # refine centre from the raised cap faces
        caps = [s for s in st.values() if within_r(s, np.array([cx, cy]), 6.0) and s["hi"][2] > 0.0]
        if caps:
            allv = np.vstack([s["vv"] for s in caps]); c = (allv.min(0) + allv.max(0)) / 2
            cx, cy = c[0], c[1]
        ctr = np.array([cx, cy])
        take(nm, lambda s, ctr=ctr: within_r(s, ctr, 5.6) and s["hi"][2] > -0.9 and radial_dot(s, ctr) > -0.2)

# oblong button above the d-pad/ABXY-stick gap (menu/view style)
take("button_oblong", lambda s: in_box(s, [-5, 6.5, -5.5], [6, 12.2, 2]) and s["hi"][2] > -0.9)
# round button below (towards the grip)
RB = np.array([-3.75, -23.7])
take("button_round", lambda s: within_r(s, RB, 5.0) and s["hi"][2] > -4.9 and (radial_dot(s, RB) > -0.2 or within_r(s, RB, 3.0) or nz(s) > 0.9))
# trigger paddle (index finger), hangs below the front of the head
take("trigger", lambda s: s["hi"][2] <= -29.1 and s["lo"][1] >= -1.0 and s["hi"][1] <= 18.6
     and np.abs(s["vv"][:, 0]).max() <= 18 and s["lo"][2] >= -52)
# grip button (middle finger), inner side of the grip under the head
take("grip_button", lambda s: in_box(s, [5, -47, -43], [21, -19.0, -19.5]) and s["hi"][0] >= 15)

# battery door: PV faces that coincide with the separate door part's outer skin
d = np.load(WORK + f"{hand}_door.npz")
door = trimesh.Trimesh(d["V"], d["F"])
pq = trimesh.proximity.ProximityQuery(door)
def on_door(i):
    s = st[i]
    if s["hi"][1] > -4 or s["lo"][2] > 3:  # quick reject outside door bbox
        return False
    sel = np.nonzero(fid == i)[0]
    pts = tc[sel]
    _, dist, _ = pq.on_surface(pts)
    return np.average(dist < 0.08, weights=areas[sel]) > 0.9
dl = [i for i in st if i not in assign and on_door(i)]
for i in dl: assign[i] = "battery_door"
print(f"  {'battery_door':16s} B-rep faces: {len(dl)}")
for i in st:
    assign.setdefault(i, "body")

ORDER = ["body", "battery_door", "thumbstick", "trigger", "grip_button", "button_oblong", "button_round"] + \
        (["dpad"] if hand == "L" else ["button_a", "button_b", "button_x", "button_y"])
# low-poly triangle budget per part
# The stick and buttons sit under the eye on the face: they get enough to look round; the shell gives up some.
BUDGET = {"body": 2400, "battery_door": 400, "thumbstick": 640, "trigger": 360, "grip_button": 240,
          "button_oblong": 120, "button_round": 160, "dpad": 400,
          "button_a": 160, "button_b": 160, "button_x": 160, "button_y": 160}
COLOR = {"body": [150, 155, 165], "battery_door": [130, 135, 145], "thumbstick": [90, 90, 95],
         "trigger": [110, 110, 115], "grip_button": [110, 110, 115], "button_oblong": [70, 70, 75],
         "button_round": [70, 70, 75], "dpad": [80, 80, 85], "button_a": [80, 80, 85], "button_b": [80, 80, 85],
         "button_x": [80, 80, 85], "button_y": [80, 80, 85]}

face_part = np.array([assign.get(int(i), None) for i in fid], dtype=object)

def part_mesh(name):
    sel = face_part == name
    m = trimesh.Trimesh(V, F[sel], process=False)
    m.remove_unreferenced_vertices()
    m.merge_vertices(digits_vertex=5)
    m.update_faces(m.nondegenerate_faces())
    m.remove_unreferenced_vertices()
    return m

def to_metres(m):
    m = m.copy(); m.apply_scale(0.001); return m

def smooth_split(m, angle_deg=30.0):
    """Split vertices along edges sharper than angle so hard edges stay hard; recompute vertex normals."""
    out = trimesh.graph.smooth_shade(m, angle=np.radians(angle_deg), facet_minarea=None)
    _ = out.vertex_normals  # cache normals so the exporter writes them
    return out

DECIMATOR = os.environ.get("DECIMATOR", "meshlab")

def decimate(m, target):
    """Quadric edge-collapse decimation. pymeshlab (needs libOpenGL.so.0 on LD_LIBRARY_PATH, see get_libopengl.sh)
    with boundary preservation so seams between parts stay closed; fast-simplification as fallback."""
    if len(m.faces) <= target:
        return m.copy()
    if DECIMATOR == "meshlab":
        import pymeshlab
        ms = pymeshlab.MeshSet()
        ms.add_mesh(pymeshlab.Mesh(vertex_matrix=m.vertices.astype(np.float64), face_matrix=m.faces.astype(np.int32)))
        ms.meshing_decimation_quadric_edge_collapse(targetfacenum=int(target), qualitythr=0.5, preserveboundary=True,
                                                    boundaryweight=3.0, preservenormal=True, preservetopology=True,
                                                    optimalplacement=True, planarquadric=True, autoclean=True)
        o = ms.current_mesh(); vo, fo = o.vertex_matrix(), o.face_matrix()
    else:
        vo, fo = fast_simplification.simplify(m.vertices.astype(np.float64), m.faces.astype(np.int64),
                                              target_count=int(target), agg=int(os.environ.get("AGG", 2)))
    r = trimesh.Trimesh(vo, fo, process=False)
    r.update_faces(r.nondegenerate_faces()); r.remove_unreferenced_vertices()
    return r

def material(name):
    c = COLOR[name]
    return trimesh.visual.material.PBRMaterial(name=f"mat_{name}", baseColorFactor=c + [255], metallicFactor=0.0,
                                               roughnessFactor=0.7)

def export(parts, path):
    sc = trimesh.Scene()
    for name in ORDER:
        if name not in parts:
            continue
        m = parts[name]
        m.visual = trimesh.visual.TextureVisuals(material=material(name))
        sc.add_geometry(m, node_name=name, geom_name=name)
    sc.export(path)

report = {"hand": HANDNAME, "parts": {}}
hi_parts, lo_parts = {}, {}
for name in ORDER:
    m = part_mesh(name)
    if len(m.faces) == 0:
        print("WARNING: empty part", name); continue
    lo = decimate(m, BUDGET[name])
    hi_parts[name] = smooth_split(to_metres(m))
    lo_parts[name] = smooth_split(to_metres(lo))
    bmin, bmax = lo_parts[name].bounds
    report["parts"][name] = dict(tris_high=int(len(m.faces)), tris_low=int(len(lo.faces)),
                                 bbox_centre_m=((bmin + bmax) / 2).round(4).tolist(), bbox_size_m=(bmax - bmin).round(4).tolist(),
                                 brep_faces=int(sum(1 for v in assign.values() if v == name)))
export(hi_parts, OUT + f"{HANDNAME}_controller_highres.glb")
export(lo_parts, OUT + f"{HANDNAME}_controller_lowpoly.glb")
allv = np.vstack([m.vertices for m in lo_parts.values()])
report["bbox_min_m"] = allv.min(0).round(4).tolist(); report["bbox_max_m"] = allv.max(0).round(4).tolist()
report["tris_low_total"] = sum(p["tris_low"] for p in report["parts"].values())
report["tris_high_total"] = sum(p["tris_high"] for p in report["parts"].values())
json.dump(report, open(OUT + f"{HANDNAME}_controller_report.json", "w"), indent=1)
np.save(WORK + f"{hand}_face_part.npy", face_part.astype(str))
print(json.dumps(report, indent=1))
