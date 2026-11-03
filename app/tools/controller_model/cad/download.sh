#!/bin/bash
set -u
mkdir -p ~/cad/steam-frame-controller/src && cd ~/cad/steam-frame-controller/src
B=https://gitlab.steamos.cloud/SteamHardware/SteamFrame/-/raw/master
for p in documents-controller/Valve_Steam_Frame_Controller_20260925.zip \
         documents-controller/Steam_Frame_Controller_LED_Locations.pdf \
         license.txt README.md \
         image/Steam_Frame_Controller_ISO_Expl.png \
         image/Steam_Frame_Controller_ISO_Grip_Side.png \
         image/Steam_Frame_Controller_ISO_Head_Side.png \
         image/Steam_Frame_Controller_LED_Locations.png; do
  curl -sSfL -o "$(basename "$p")" "$B/$p" || echo "FAIL $p"
done
ls -la
file *
# list + extract zip with python (no unzip installed); reject path traversal
mkdir -p unzipped
python3 -I - <<'EOF'
import zipfile, os
z = zipfile.ZipFile('Valve_Steam_Frame_Controller_20260925.zip')
for i in z.infolist():
    print(f"{i.file_size:>12} {i.filename}")
dst = os.path.realpath('unzipped')
for i in z.infolist():
    t = os.path.realpath(os.path.join(dst, i.filename))
    assert t.startswith(dst + os.sep), i.filename
z.extractall(dst)
EOF
find unzipped -type f -exec ls -la {} \;
