#!/bin/bash
# Our controller models from Valve's controller CAD, in WSL (or any Linux), no sudo. Valve's files and every
# intermediate stay in ~/cad (CAD=...); nothing here is written into the repo except app/models/controllers/.
#   1. python3 -m venv ~/cad/venv && ~/cad/venv/bin/pip install cadquery trimesh fast-simplification pymeshlab \
#      xatlas pillow scipy
#   2. bash get_libopengl.sh          (user-space libOpenGL for pymeshlab)
#   3. bash download.sh               (Valve's public repo -> ~/cad/steam-frame-controller/src, CC BY-NC-SA 4.0)
#   4. bash run.sh                    (tessellate, segment into parts, decimate -> ~/cad/steam-frame-controller/out)
#   5. the legends: godot --path app --script res://tools/controller_model/export_legends.gd -- --out=DIR
#   6. ../bake.py with the device dump (app/docs/reference-models) -> app/models/controllers/
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
P=~/cad/venv/bin/python
export LD_LIBRARY_PATH=~/cad/syslibs/root/usr/lib/x86_64-linux-gnu
W=~/cad/steam-frame-controller/work
mkdir -p $W
[ -f $W/R_body.npz ] || (cd /tmp && $P -I "$HERE/tess_all.py")
for H in L R; do
  (cd /tmp && $P -I "$HERE/build.py" $H > $W/build_$H.log 2>&1) || { tail -30 $W/build_$H.log; exit 1; }
done
grep -E "B-rep faces|dropped|WARN|tris_low_total" $W/build_*.log
