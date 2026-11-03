"""Bakes our controller models: the low-poly meshes derived from Valve's controller CAD (cad/build.py), registered to
the runtime render model's space, UV-unwrapped into one atlas, with dark plastic and the printed legends baked into
the texture at the positions of xr/controller_labels_layout.tres.

Inputs (none of them committed):
  --cad DIR        <side>_controller_lowpoly.glb from cad/build.py (Valve's CAD, tessellated and decimated)
  --runtime DIR    <side>_controller.glb + .json dumped on the device (--dump-render-models; Valve's runtime model)
  --legends DIR    legends.json + PNGs from export_legends.gd
Output (committed, CC BY-NC-SA 4.0, see app/models/controllers/LICENSE-controller.md):
  --out DIR        <side>_controller.glb (texture: normal state), <side>_controller_menu.png,
                   <side>_controller_window.png (same UVs: the menu-open and window states), controllers.json
                   (each model's pose in the aim pose's space, registration residuals)

Run with the CAD venv: python -I bake.py --cad ... --runtime ... --legends ... --out ...
"""
import argparse
import json
import os

import numpy as np
import trimesh
import xatlas
from PIL import Image

SIZE = 2048
PADDING = 6
# Runtime node names for the CAD parts (the runtime model's names; labels and animation key on them).
NAMES = {
    "right": {"body": "body", "battery_door": "battery_door", "thumbstick": "thumbstick", "trigger": "trigger",
              "grip_button": "button_grip", "button_oblong": "button_menu", "button_round": "button_system",
              "button_a": "button_a", "button_b": "button_b", "button_x": "button_x", "button_y": "button_y"},
    "left": {"body": "body", "battery_door": "battery_door", "thumbstick": "thumbstick", "trigger": "trigger",
             "grip_button": "button_grip", "button_oblong": "button_view", "button_round": "button_system",
             "dpad": "dpad"},
}
# Parts used to register CAD to runtime (surface centroids), then ICP on the body shell.
PAIRS = {"right": ["button_a", "button_b", "button_x", "button_y", "thumbstick", "trigger", "button_grip",
                   "button_menu", "button_system"],
         "left": ["dpad", "thumbstick", "trigger", "button_grip", "button_view", "button_system"]}
# sRGB base colours: near-black plastic, controls a touch lighter so they read in the unlit shader.
COLOURS = {"body": (34, 35, 38), "battery_door": (30, 31, 34), "thumbstick": (44, 45, 48), "trigger": (40, 41, 44),
           "button_grip": (40, 41, 44), "dpad": (48, 49, 52)}
BUTTON_COLOUR = (52, 53, 57)
# Legends print only on the fixed shell (as the layout places them), never on a moving part.
PRINTABLE = {"body", "battery_door"}
# Godot's decal normal_fade 0.6: surfaces facing away more than about this are left out.
MIN_FACING = 0.4
# Share of the texture the charts should cover (xatlas leaves the rest for padding and packing gaps).
COVERAGE = 0.6


def load_parts(path):
    scene = trimesh.load(path, force="scene")
    out = {}
    for node in scene.graph.nodes_geometry:
        transform, geom = scene.graph[node]
        mesh = scene.geometry[geom].copy()
        mesh.apply_transform(transform)
        out[node] = mesh
    return out


def centroid(mesh):
    w = mesh.area_faces
    return (mesh.triangles_center * w[:, None]).sum(0) / w.sum()


def kabsch(a, b):
    ca, cb = a.mean(0), b.mean(0)
    u, _, vt = np.linalg.svd((a - ca).T @ (b - cb))
    d = np.sign(np.linalg.det(vt.T @ u.T))
    r = vt.T @ np.diag([1, 1, d]) @ u.T
    m = np.eye(4)
    m[:3, :3] = r
    m[:3, 3] = cb - r @ ca
    return m


def register(side, cad, runtime):
    """CAD -> runtime model space: Kabsch on part centroids, then ICP on the body shell."""
    names = [n for n in PAIRS[side] if n in cad and n in runtime]
    a = np.array([centroid(cad[n]) for n in names])
    b = np.array([centroid(runtime[n]) for n in names])
    m = kabsch(a, b)
    samples = cad["body"].sample(4000)
    m2, _, _ = trimesh.registration.icp(samples, runtime["body"], initial=m, max_iterations=60, threshold=1e-7,
                                        reflection=False, scale=False)
    moved = (m2[:3, :3] @ samples.T).T + m2[:3, 3]
    d = trimesh.proximity.closest_point(runtime["body"], moved)[1]
    parts_off = np.linalg.norm((m2[:3, :3] @ a.T).T + m2[:3, 3] - b, axis=1)
    stats = {"body_mean_mm": round(float(d.mean()) * 1000, 2), "body_p95_mm": round(float(np.percentile(d, 95)) * 1000, 2),
             "parts_rms_mm": round(float(np.sqrt((parts_off ** 2).mean())) * 1000, 2)}
    print(f"{side}: registered; body {stats['body_mean_mm']} mm mean, {stats['body_p95_mm']} mm 95%; part centres "
          f"{stats['parts_rms_mm']} mm rms")
    return m2, stats


def model_in_aim(runtime_dir, side):
    """The runtime model's pose in the aim pose's space, from the dump; an untracked hand's from the other, mirrored."""
    def read(s):
        with open(os.path.join(runtime_dir, f"{s}_controller.json")) as f:
            info = json.load(f)
        if np.allclose(info["aim_in_origin"]["origin"], 0) and np.allclose(info["aim_in_origin"]["x"], [1, 0, 0]):
            return None
        t = info["model_in_aim"]
        m = np.eye(4)
        m[:3, 0], m[:3, 1], m[:3, 2], m[:3, 3] = t["x"], t["y"], t["z"], t["origin"]
        return m
    m = read(side)
    if m is None:
        other = read("left" if side == "right" else "right")
        mirror = np.diag([-1.0, 1, 1, 1])
        m = mirror @ other @ mirror
        print(f"{side}: aim pose not tracked in its dump; the other hand's, mirrored")
    return m


def rasterize(parts, uvs, size):
    """Per texel: model-space position, normal, part index (-1 = empty)."""
    pos = np.zeros((size, size, 3), np.float32)
    nrm = np.zeros((size, size, 3), np.float32)
    part = np.full((size, size), -1, np.int16)
    for pi, (mesh, uv) in enumerate(zip(parts, uvs)):
        px = uv * size - 0.5
        px[:, 1] = (1.0 - uv[:, 1]) * size - 0.5  # image rows go down
        fn = mesh.face_normals
        for fi, face in enumerate(mesh.faces):
            t = px[face]
            lo = np.floor(t.min(0)).astype(int)
            hi = np.ceil(t.max(0)).astype(int)
            lo = np.clip(lo, 0, size - 1)
            hi = np.clip(hi, 0, size - 1)
            xs, ys = np.meshgrid(np.arange(lo[0], hi[0] + 1), np.arange(lo[1], hi[1] + 1))
            p = np.stack([xs.ravel(), ys.ravel()], 1).astype(np.float64)
            v0, v1, v2 = t
            d = (v1[1] - v2[1]) * (v0[0] - v2[0]) + (v2[0] - v1[0]) * (v0[1] - v2[1])
            if abs(d) < 1e-12:
                continue
            w0 = ((v1[1] - v2[1]) * (p[:, 0] - v2[0]) + (v2[0] - v1[0]) * (p[:, 1] - v2[1])) / d
            w1 = ((v2[1] - v0[1]) * (p[:, 0] - v2[0]) + (v0[0] - v2[0]) * (p[:, 1] - v2[1])) / d
            w2 = 1.0 - w0 - w1
            inside = (w0 >= -1e-4) & (w1 >= -1e-4) & (w2 >= -1e-4)
            if not inside.any():
                continue
            w = np.stack([w0, w1, w2], 1)[inside]
            q = p[inside].astype(int)
            verts = mesh.vertices[face]
            pos[q[:, 1], q[:, 0]] = w @ verts
            nrm[q[:, 1], q[:, 0]] = fn[fi]
            part[q[:, 1], q[:, 0]] = pi
    return pos, nrm, part


def sample(img, u, v):
    """Bilinear RGBA in 0..1 from a float image (h, w, 4) at normalised u, v."""
    h, w = img.shape[:2]
    x = np.clip(u * w - 0.5, 0, w - 1)
    y = np.clip(v * h - 0.5, 0, h - 1)
    x0, y0 = np.floor(x).astype(int), np.floor(y).astype(int)
    x1, y1 = np.minimum(x0 + 1, w - 1), np.minimum(y0 + 1, h - 1)
    fx, fy = (x - x0)[:, None], (y - y0)[:, None]
    return (img[y0, x0] * (1 - fx) * (1 - fy) + img[y0, x1] * fx * (1 - fy) + img[y1, x0] * (1 - fx) * fy
            + img[y1, x1] * fx * fy)


def print_box(img, p, n, ys, xs, origin, axes, size, tex):
    """Prints tex through a decal box (Godot's convention: projects along -Y, u along +X, v along +Z) onto the texels
    at model-space points p with normals n; returns how many texels took it."""
    w, depth, h = size
    rel = p - origin
    lx, ly, lz = rel @ axes[0], rel @ axes[1], rel @ axes[2]
    inside = (np.abs(lx) <= w / 2) & (np.abs(ly) <= depth / 2) & (np.abs(lz) <= h / 2) & (n @ axes[1] >= MIN_FACING)
    if inside.any():
        c = sample(tex, lx[inside] / w + 0.5, lz[inside] / h + 0.5)
        a = c[:, 3:4]
        yy, xx = ys[inside], xs[inside]
        img[yy, xx] = img[yy, xx] * (1 - a) + c[:, :3] * a
    return int(inside.sum())


def load_tex(legend_dir, png):
    return np.asarray(Image.open(os.path.join(legend_dir, png)).convert("RGBA"), np.float32) / 255.0


def paint_caps(img, pos, nrm, part, names, meshes, caps, legend_dir, up, front):
    """The letters on the face buttons: on top of each button, upright like the legends."""
    right = np.cross(front, up)
    right /= np.linalg.norm(right)
    axes = [right, up, np.cross(right, up)]
    for cap in caps:
        if cap["part"] not in names:
            continue
        pi = names.index(cap["part"])
        v = meshes[pi].vertices
        h = v @ up
        top = v[h >= h.max() - 0.0007].mean(0)
        ys, xs = np.nonzero(part == pi)
        got = print_box(img, pos[ys, xs].astype(np.float64), nrm[ys, xs].astype(np.float64), ys, xs, top, axes,
                        cap["size"], load_tex(legend_dir, cap["png"]))
        if got == 0:
            print(f"  cap {cap['text']}: no surface")


def paint(pos, nrm, part, names, legends, legend_dir):
    size = part.shape[0]
    img = np.zeros((size, size, 3), np.float32)
    for pi, name in enumerate(names):
        img[part == pi] = np.array(COLOURS.get(name, BUTTON_COLOUR), np.float32) / 255.0
    printable = np.isin(part, [i for i, n in enumerate(names) if n in PRINTABLE])
    ys, xs = np.nonzero(printable)
    p = pos[ys, xs].astype(np.float64)
    n = nrm[ys, xs].astype(np.float64)
    printed = 0
    for leg in legends:
        axes = [np.array(leg[k]) / np.linalg.norm(leg[k]) for k in ("x", "y", "z")]
        if print_box(img, p, n, ys, xs, np.array(leg["origin"]), axes, leg["size"], load_tex(legend_dir, leg["png"])):
            printed += 1
        else:
            print(f"  {leg['side']} {leg['state']} {leg['input']}: no surface in its box")
    return img, printed


def dilate(img, filled, steps=PADDING + 2):
    """Spreads chart colours into the gutters so mipmaps and filtering don't pull in black."""
    img = img.copy()
    filled = filled.copy()
    for _ in range(steps):
        acc = np.zeros_like(img)
        cnt = np.zeros(filled.shape, np.float32)
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            sh = np.roll(np.roll(filled, dy, 0), dx, 1)
            acc += np.roll(np.roll(img, dy, 0), dx, 1) * sh[..., None]
            cnt += sh
        grow = (~filled) & (cnt > 0)
        img[grow] = acc[grow] / cnt[grow][:, None]
        filled |= grow
    return img


def to_image(img):
    return Image.fromarray((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB")


def main():
    ap = argparse.ArgumentParser()
    for k in ("cad", "runtime", "legends", "out"):
        ap.add_argument("--" + k, required=True)
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    with open(os.path.join(args.legends, "legends.json")) as f:
        sheet = json.load(f)
    legends = sheet["legends"]
    info = {"note": "Our controller models: model space = the runtime render model's space; model_in_aim places it "
                    "relative to the aim pose. Derived from Valve's controller CAD, CC BY-NC-SA 4.0.", "sides": {}}
    for side in ("right", "left"):
        cad = {NAMES[side][k]: v for k, v in load_parts(os.path.join(args.cad, f"{side}_controller_lowpoly.glb")).items()
               if k in NAMES[side]}
        runtime = load_parts(os.path.join(args.runtime, f"{side}_controller.glb"))
        m, stats = register(side, cad, runtime)
        names = list(cad)
        parts = []
        atlas = xatlas.Atlas()
        for name in names:
            mesh = cad[name].copy()
            mesh.apply_transform(m)
            parts.append(mesh)
            atlas.add_mesh(mesh.vertices.astype(np.float32), mesh.faces.astype(np.uint32),
                           mesh.vertex_normals.astype(np.float32))
        pack = xatlas.PackOptions()
        pack.resolution = SIZE
        pack.padding = PADDING
        pack.bilinear = True
        pack.bruteForce = False
        # Texels per metre so the charts cover about COVERAGE of the texture (default sizing left 3/4 empty).
        area = sum(p.area for p in parts)
        pack.texels_per_unit = float(np.sqrt(COVERAGE * SIZE * SIZE / area))
        atlas.generate(pack_options=pack)
        unwrapped, uvs = [], []
        for i, mesh in enumerate(parts):
            vmap, faces, uv = atlas[i]
            u = trimesh.Trimesh(mesh.vertices[vmap], faces, vertex_normals=mesh.vertex_normals[vmap], process=False)
            unwrapped.append(u)
            uvs.append(uv)
        pos, nrm, part = rasterize(unwrapped, uvs, SIZE)
        filled = part >= 0
        print(f"{side}: atlas {SIZE}px, {filled.mean() * 100:.0f}% covered, {sum(len(p.faces) for p in unwrapped)} "
              f"triangles")
        aim = model_in_aim(args.runtime, side)
        aim_in_model = np.linalg.inv(aim)
        up = aim_in_model[:3, :3] @ np.array([0.0, 1.0, 0.0])
        front = aim_in_model[:3, :3] @ np.array([0.0, 0.0, -1.0])
        caps = [c for c in sheet.get("caps", []) if c["side"] == side]
        print(f"{side}: {1000.0 / pack.texels_per_unit:.3f} mm per texel; legend line "
              f"{0.0042 * pack.texels_per_unit:.0f} texels")
        textures = {}
        for state in ("normal", "menu", "window"):
            mine = [l for l in legends if l["side"] == side and l["state"] == state]
            img, printed = paint(pos, nrm, part, names, mine, args.legends)
            paint_caps(img, pos, nrm, part, names, unwrapped, caps, args.legends, up, front)
            textures[state] = to_image(dilate(img, filled))
            print(f"  {state}: {printed} of {len(mine)} legends printed")
        for state in ("menu", "window"):
            textures[state].save(os.path.join(args.out, f"{side}_controller_{state}.png"), optimize=True)
        material = trimesh.visual.material.PBRMaterial(name=f"{side}_controller", baseColorTexture=textures["normal"],
                                                       metallicFactor=0.0, roughnessFactor=0.6)
        scene = trimesh.Scene()
        for name, mesh, uv in zip(names, unwrapped, uvs):
            mesh.visual = trimesh.visual.TextureVisuals(uv=uv, material=material)
            _ = mesh.vertex_normals
            scene.add_geometry(mesh, node_name=name, geom_name=name)
        path = os.path.join(args.out, f"{side}_controller.glb")
        scene.export(path)
        info["sides"][side] = {"model_in_aim": aim.tolist(), "registration": stats, "parts": names,
                               "triangles": int(sum(len(p.faces) for p in unwrapped))}
        print(f"{side}: wrote {path} ({os.path.getsize(path) // 1024} KB)")
    with open(os.path.join(args.out, "controllers.json"), "w") as f:
        json.dump(info, f, indent=1)


main()
