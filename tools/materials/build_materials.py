#!/usr/bin/env python3
"""Builds the app's material library (app/materials, docs/materials.md) from CC0 texture sets.

Each app/materials/<id>.json names its source (site and asset). For each, this script:
  1. downloads the maps (base colour, OpenGL normal, roughness, ambient occlusion, metallic) at the size needed,
     into a folder outside the repository (--downloads, default ~/.cache/vrvp-materials);
  2. reads the asset's page and stops unless it says CC0; records the page, the authors the site gives, the licence
     and the date;
  3. resizes the maps, packs ambient occlusion, roughness and metallic into one picture (R, G, B), and hands each
     map to the packer (tools/materials/mtex_pack, built by make-packer.sh), which writes the mip levels as ASTC 8 x 8
     into app/materials/textures/<id>_<map>.mtex;
  4. writes back the entry's maps, swatch (the mean colour), tiling (the source's real size when the entry gives
     none) and source; then app/materials/CREDITS.md from every entry.

  python tools/materials/build_materials.py                 every entry
  python tools/materials/build_materials.py --only velvet   some entries (comma-separated ids)
  python tools/materials/build_materials.py --credits       only CREDITS.md

Needs Python 3 with Pillow and NumPy. On Windows the packer runs in WSL (wsl -e); elsewhere it runs directly.
"""
import argparse
import datetime
import io
import json
import os
import re
import subprocess
import sys
import urllib.parse
import urllib.request
import zipfile

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MATERIALS = os.path.join(ROOT, "app", "materials")
TEXTURES = os.path.join(MATERIALS, "textures")
UA = {"User-Agent": "framevrvideo-material-library"}
# The packed map (ambient occlusion, roughness, metallic) is always this size: it carries less detail.
ORM_SIZE = 1024
SITES = {
    "polyhaven": {"name": "Poly Haven", "page": "https://polyhaven.com/a/{asset}"},
    "ambientcg": {"name": "ambientCG", "page": "https://ambientcg.com/view?id={asset}"},
}


def get(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120).read()


def cached(path, url):
    if not os.path.exists(path):
        data = get(url)
        with open(path + ".part", "wb") as f:
            f.write(data)
        os.replace(path + ".part", path)
    with open(path, "rb") as f:
        return f.read()


def res_name(size):
    return "%dk" % (size // 1024)


# --- Sources: each returns {map: PIL image or None} for albedo, normal, ao, roughness, metallic, plus info. ---

def fetch_polyhaven(asset, size, folder):
    files = json.loads(get("https://api.polyhaven.com/files/" + asset))
    info = json.loads(get("https://api.polyhaven.com/info/" + asset))
    keys = {k.lower(): k for k in files}

    def load(name, res):
        k = keys.get(name.lower())
        if k is None:
            return None
        entry = files[k].get(res, {}).get("jpg") or files[k].get(res, {}).get("png")
        if entry is None:
            return None
        url = entry["url"]
        data = cached(os.path.join(folder, "%s_%s_%s%s" % (asset, name, res, os.path.splitext(url)[1])), url)
        return Image.open(io.BytesIO(data))

    maps = {"albedo": load("Diffuse", res_name(size)), "normal": load("nor_gl", res_name(size))}
    arm = load("arm", res_name(ORM_SIZE))
    if arm is not None:
        r, g, b = arm.convert("RGB").split()
        maps.update({"ao": r, "roughness": g, "metallic": b})
    else:
        maps.update({"ao": load("AO", res_name(ORM_SIZE)), "roughness": load("Rough", res_name(ORM_SIZE)),
                     "metallic": load("Metal", res_name(ORM_SIZE))})
    authors = ", ".join("%s (%s)" % (n, role.strip().lower()) for n, role in info.get("authors", {}).items())
    dims = info.get("dimensions") or []
    tiling = round(dims[0] / 1000.0, 2) if dims else None
    return maps, {"title": info.get("name", asset), "author": authors, "tiling": tiling}


def fetch_ambientcg(asset, size, folder):
    meta = json.loads(get("https://ambientcg.com/api/v2/full_json?" + urllib.parse.urlencode(
        {"id": asset, "include": "downloadData,displayData"})))["foundAssets"][0]
    zips = {}
    for res in {size, ORM_SIZE}:
        attr = "%dK-JPG" % (res // 1024)
        url = None
        for folder_info in meta["downloadFolders"].values():
            for d in folder_info["downloadFiletypeCategories"].get("zip", {}).get("downloads", []):
                if d["attribute"] == attr:
                    url = d["downloadLink"]
        if url is None:
            raise RuntimeError("%s: no %s download" % (asset, attr))
        zips[res] = zipfile.ZipFile(io.BytesIO(cached(os.path.join(folder, "%s_%s.zip" % (asset, attr)), url)))

    def load(suffix, res):
        # Read members by name only: nothing is extracted to disk.
        for n in zips[res].namelist():
            if n.endswith("_" + suffix + ".jpg") or n.endswith("_" + suffix + ".png"):
                return Image.open(io.BytesIO(zips[res].read(n)))
        return None

    maps = {"albedo": load("Color", size), "normal": load("NormalGL", size), "ao": load("AmbientOcclusion", ORM_SIZE),
            "roughness": load("Roughness", ORM_SIZE), "metallic": load("Metalness", ORM_SIZE)}
    return maps, {"title": meta.get("displayName", asset), "author": "", "tiling": None}


FETCH = {"polyhaven": fetch_polyhaven, "ambientcg": fetch_ambientcg}


def check_licence(site, asset):
    url = SITES[site]["page"].format(asset=asset)
    page = get(url).decode("utf-8", "replace")
    if "CC0" not in page:
        raise RuntimeError("%s does not say CC0: not used" % url)
    return url


# --- Processing ---

def to_rgb_array(img, size):
    if img.mode in ("I;16", "I;16B", "I"):
        img = Image.fromarray((np.asarray(img, dtype=np.float32) / 257.0).clip(0, 255).astype(np.uint8))
    img = img.convert("RGB")
    if img.size != (size, size):
        img = img.resize((size, size), Image.LANCZOS)
    return np.asarray(img, dtype=np.uint8)


def to_channel(img, size, default):
    if img is None:
        return np.full((size, size), default, dtype=np.uint8)
    if img.mode in ("I;16", "I;16B", "I"):
        img = Image.fromarray((np.asarray(img, dtype=np.float32) / 257.0).clip(0, 255).astype(np.uint8))
    img = img.convert("L")
    if img.size != (size, size):
        img = img.resize((size, size), Image.LANCZOS)
    return np.asarray(img, dtype=np.uint8)


def wsl_path(p):
    p = os.path.abspath(p)
    return "/mnt/" + p[0].lower() + p[2:].replace("\\", "/")


# tools/privacy-check.sh reads binary files as their runs of 6 or more printable bytes; compressed blocks can by chance
# hold one that looks like an e-mail address or a home path.
PRINTABLE = re.compile(rb"[\x20-\x7e]{6,}")
LOOKS_PERSONAL = re.compile(rb"[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}|/home/|/Users/|Users\\")


def looks_personal(path):
    with open(path, "rb") as f:
        data = f.read()
    return any(LOOKS_PERSONAL.search(m.group(0)) for m in PRINTABLE.finditer(data))


def pack(packer, kind, rgb, out_path, work, effort):
    h, w = rgb.shape[:2]
    raw = os.path.join(work, os.path.basename(out_path) + ".rgba")
    args = [kind, str(w), str(h)]
    # Such a chance string goes away when the blocks hold other texels: the tiling picture shifted by a texel or two
    # (a millimetre or so against the other maps; invisible).
    for attempt in range(4):
        rgba = np.dstack([np.roll(rgb, attempt, axis=1), np.full((h, w), 255, dtype=np.uint8)])
        rgba.tofile(raw)
        if os.name == "nt":
            cmd = ["wsl", "-e", "bash", "-c", 'exec %s "$@"' % packer, "mtex_pack"] + args + [
                wsl_path(raw), wsl_path(out_path), str(effort)]
        else:
            cmd = [os.path.expanduser(packer)] + args + [raw, out_path, str(effort)]
        subprocess.run(cmd, check=True)
        if not looks_personal(out_path):
            break
        print("%s: a run of bytes looks like personal data; packing again" % os.path.basename(out_path))
    os.remove(raw)


def mean_colour(rgb):
    lin = (rgb.astype(np.float32) / 255.0) ** 2.2
    m = lin.reshape(-1, 3).mean(axis=0) ** (1 / 2.2)
    return "#%02x%02x%02x" % tuple(int(round(c * 255)) for c in m)


def build(entry, args, today):
    mid = entry["id"]
    site, asset = entry["source"]["site"], entry["source"]["asset"]
    size = int(entry.get("size", 1024))
    folder = os.path.join(args.downloads, "%s_%s" % (site, asset))
    os.makedirs(folder, exist_ok=True)
    url = check_licence(site, asset)
    maps, info = FETCH[site](asset, size, folder)
    if maps["albedo"] is None or maps["normal"] is None:
        raise RuntimeError("%s: no base colour or normal map" % mid)
    albedo = to_rgb_array(maps["albedo"], size)
    normal = to_rgb_array(maps["normal"], size)
    orm = np.dstack([to_channel(maps["ao"], ORM_SIZE, 255), to_channel(maps["roughness"], ORM_SIZE, 200),
                     to_channel(maps["metallic"], ORM_SIZE, 0)])
    out = {}
    for name, kind, pic in (("albedo", "albedo", albedo), ("normal", "normal", normal), ("orm", "data", orm)):
        rel = "textures/%s_%s.mtex" % (mid, name)
        pack(args.packer, kind, pic, os.path.join(MATERIALS, rel), args.work, args.effort)
        out[name] = rel
    entry["maps"] = out
    entry["swatch"] = mean_colour(albedo)
    if "tiling" not in entry or entry["tiling"] is None:
        entry["tiling"] = info["tiling"] or 1.0
    entry["source"] = {"site": site, "asset": asset, "title": info["title"], "url": url, "author": info["author"],
                       "licence": "CC0 1.0", "checked": today}
    return entry


def entries():
    out = []
    for f in sorted(os.listdir(MATERIALS)):
        if f.endswith(".json"):
            with open(os.path.join(MATERIALS, f), encoding="utf-8") as fh:
                out.append(json.load(fh))
    return out


def save(entry):
    order = ["id", "name", "tags", "size", "tiling", "tint", "roughness_scale", "normal_strength", "specular", "sheen",
             "swatch", "maps", "source"]
    data = {k: entry[k] for k in order if k in entry}
    data.update({k: v for k, v in entry.items() if k not in data})
    with open(os.path.join(MATERIALS, entry["id"] + ".json"), "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(data, indent="\t", ensure_ascii=False) + "\n")


def write_credits():
    lines = [
        "# Material library credits",
        "",
        "Every texture set in this folder is under the Creative Commons CC0 1.0 Universal public domain dedication",
        "(https://creativecommons.org/publicdomain/zero/1.0/). No attribution is required; we give it anyway. The",
        "maps were downloaded from the pages below, resized, packed and compressed for the headset by",
        "`tools/materials/build_materials.py` (docs/materials.md). The licence was read on each page on the date given.",
        "",
        "| Material | Source | Asset | Author | Licence | Checked |",
        "|---|---|---|---|---|---|",
    ]
    for e in entries():
        s = e.get("source", {})
        site = SITES.get(s.get("site", ""), {}).get("name", s.get("site", ""))
        lines.append("| `%s` %s | %s | [%s](%s) | %s | %s | %s |" % (
            e["id"], e.get("name", ""), site, s.get("title", s.get("asset", "")), s.get("url", ""),
            s.get("author") or "not given", s.get("licence", ""), s.get("checked", "")))
    lines.append("")
    with open(os.path.join(MATERIALS, "CREDITS.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--only", default="", help="comma-separated ids")
    ap.add_argument("--downloads", default=os.path.join(os.path.expanduser("~"), ".cache", "vrvp-materials"))
    ap.add_argument("--work", default="", help="scratch folder for raw pictures (default: under --downloads)")
    ap.add_argument("--packer", default="~/src/mtex_pack/mtex_pack", help="the packer (a WSL path on Windows)")
    ap.add_argument("--effort", type=float, default=98.0, help="the encoder's effort, 0..100")
    ap.add_argument("--credits", action="store_true", help="only write CREDITS.md")
    args = ap.parse_args()
    if not args.credits:
        args.work = args.work or os.path.join(args.downloads, "work")
        os.makedirs(args.work, exist_ok=True)
        os.makedirs(TEXTURES, exist_ok=True)
        only = set(filter(None, args.only.split(",")))
        today = datetime.date.today().isoformat()
        for e in entries():
            if only and e["id"] not in only:
                continue
            print("==", e["id"], flush=True)
            save(build(e, args, today))
    write_credits()


if __name__ == "__main__":
    sys.exit(main())
