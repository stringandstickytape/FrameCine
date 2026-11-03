#!/bin/bash
# Fetch libOpenGL.so.0 (and libGLdispatch) as user-space libs for pymeshlab plugins; no sudo needed.
set -e
mkdir -p ~/cad/syslibs/deb && cd ~/cad/syslibs/deb
apt-get download libopengl0 libglvnd0 libglx0 libgl1 2>&1 | tail -3
for d in *.deb; do dpkg -x "$d" ~/cad/syslibs/root; done
ls ~/cad/syslibs/root/usr/lib/x86_64-linux-gnu/
cd /tmp
LD_LIBRARY_PATH=~/cad/syslibs/root/usr/lib/x86_64-linux-gnu ~/cad/venv/bin/python -I -c "
import pymeshlab; ms=pymeshlab.MeshSet(); print('has qec:', hasattr(ms,'meshing_decimation_quadric_edge_collapse'))" 2>&1 | grep -v "Qt Plugin\|Cannot load\|^$" | tail -5
