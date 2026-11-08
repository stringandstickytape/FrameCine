#!/usr/bin/env bash
# Builds a release tarball of the player, for installing without a store (docs/packaging.md).
# Runs from Git Bash or WSL. The engine's licence files and the x86_64 engine are read from the WSL build tree
# (~/src/...); from Git Bash they are fetched with wsl.exe.
#
#   tools/package.sh [--engine NAME] [--arch arm64|x86_64] [--out DIR] [--version V]
#                    [--no-whisper] [--whisper-model STEM] [--whisper-vulkan] [--whisper-bench]
#
#   --engine NAME          an engine binary in build/out (default: the newest godot.linuxbsd.*.arm64*); for x86_64,
#                          the WSL build ~/src/godot-player/bin/godot.linuxbsd.template_debug.x86_64
#   --no-whisper           leave out whisper/, on-device speech to text (below). In by default.
#   --whisper-model STEM   the model in whisper/models (default small.en-q8_0; build/whisper-models.sh fetches them)
#   --whisper-vulkan       also the Vulkan build of the server, in whisper/vulkan/ (50 MB)
#   --whisper-bench        the benchmark kit: whisper-cli and whisper-bench (both builds), every model in
#                          build/out/whisper-models, the speech samples, tools/whisper-bench.sh
#   --no-kernel-modules    accepted and ignored, for old command lines: there is no decoder module (docs/decisions.md D21)
#
# Output: build/dist/vr-video-player-<version>-<arch>.tar.gz with
#   bin/vr-video-player-engine   the engine fork (template build with path overrides: it runs the app folder as is)
#   app/                         the project, as committed (no tests, docs or editor tools)
#   run.sh                       the launcher (the known-good recipe: x11 display driver, XR on, DISPLAY / runtime dir)
#   vr-video-player.desktop.in   the desktop entry; install-on-frame.sh fills in the folder
#   tools/steam_shortcuts.py     the library shortcut helper (install-on-frame.sh --steam)
#   whisper/                     speech to text for the assistant (build/whisper/README.md): whisper-server from
#                                build/out/whisper/<aarch64|x86_64> (build/whisper-build.sh), models/ggml-<model>.bin;
#                                the app starts the server on 127.0.0.1 when the assistant needs it
#   icon.svg, README.txt, VERSION, LICENSES/ (this app MIT; the engine; FFmpeg LGPL-2.1; dav1d BSD-2; libsmb2 LGPL-2.1; whisper.cpp
#   and the speech models MIT; the controller models CC BY-NC-SA 4.0; THIRD-PARTY.md with versions and sources)
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
ARCH=arm64
ENGINE=""
OUT="$REPO/build/dist"
VERSION=""
WHISPER=1
WHISPER_MODEL=small.en-q8_0
WHISPER_VULKAN=0
WHISPER_BENCH=0
while [ $# -gt 0 ]; do
  case "$1" in
    --engine) ENGINE=$2; shift ;;
    --arch) ARCH=$2; shift ;;
    --out) OUT=$2; shift ;;
    --version) VERSION=$2; shift ;;
    --with-kernel-module) echo "--with-kernel-module: the decoder module was removed (docs/decisions.md D21)" >&2; exit 2 ;;
    --no-kernel-modules) ;;  # accepted for old command lines: there is no module bundle any more
    --no-whisper) WHISPER=0 ;;
    --whisper-model) WHISPER_MODEL=$2; shift ;;
    --whisper-vulkan) WHISPER_VULKAN=1 ;;
    --whisper-bench) WHISPER_BENCH=1; WHISPER_VULKAN=1 ;;
    -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done
case "$ARCH" in arm64|x86_64) ;; *) echo "--arch: arm64 or x86_64" >&2; exit 2 ;; esac

# A file from the WSL home (~/src/...): directly when we are in WSL, else through wsl.exe.
wsl_cat() {
  local rel=$1
  if [ -f "$HOME/$rel" ] && grep -qi microsoft /proc/version 2>/dev/null; then
    cat "$HOME/$rel"
  elif command -v wsl.exe > /dev/null 2>&1; then
    wsl.exe -e bash -c "cat \"\$HOME/$rel\""
  else
    echo "can't read ~/$rel from the WSL build tree" >&2
    return 1
  fi
}
wsl_out() {
  if grep -qi microsoft /proc/version 2>/dev/null; then bash -c "$1"; else wsl.exe -e bash -lc "$1"; fi
}

cd "$REPO"
[ -n "$VERSION" ] || VERSION=$(git describe --tags --always --dirty 2>/dev/null || git rev-parse --short HEAD)
NAME="vr-video-player-$VERSION-$ARCH"
STAGE="$OUT/$NAME"
rm -rf "$STAGE"
mkdir -p "$STAGE/bin" "$STAGE/LICENSES"

# --- The engine ---------------------------------------------------------------------------------------------------
# build/out is not in git: in a linked worktree, use the main checkout's build/out.
ENGINE_DIR=build/out
if ! ls build/out/godot.linuxbsd.* > /dev/null 2>&1; then
  MAIN=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
  ENGINE_DIR="$MAIN/build/out"
fi
if [ "$ARCH" = arm64 ]; then
  if [ -z "$ENGINE" ]; then
    ENGINE=$(ls -t "$ENGINE_DIR"/godot.linuxbsd.*.arm64* 2>/dev/null | head -1 | xargs -r basename)
  fi
  [ -n "$ENGINE" ] && [ -f "$ENGINE_DIR/$ENGINE" ] || { echo "no engine $ENGINE_DIR/${ENGINE:-godot.linuxbsd.*.arm64*}" >&2; exit 1; }
  cp "$ENGINE_DIR/$ENGINE" "$STAGE/bin/vr-video-player-engine"
else
  ENGINE=${ENGINE:-godot.linuxbsd.template_debug.x86_64}
  wsl_cat "src/godot-player/bin/$ENGINE" > "$STAGE/bin/vr-video-player-engine"
fi
chmod +x "$STAGE/bin/vr-video-player-engine"
ENGINE_SHA=$(sha256sum "$STAGE/bin/vr-video-player-engine" | cut -d' ' -f1)

# --- The app, as committed ------------------------------------------------------------------------------------------
git archive HEAD app | tar -x -C "$STAGE"
rm -rf "$STAGE/app/tests" "$STAGE/app/docs" "$STAGE/app/tools"

# The shortcut helper for install-on-frame.sh --steam (runs on the headset).
mkdir -p "$STAGE/tools"
cp tools/steam_shortcuts.py "$STAGE/tools/"

# --- Speech to text: whisper-server and a model (build/whisper/README.md) -------------------------------------------
# build/out is not in git: in a linked worktree, fall back to the main checkout's (as for the engine).
WHISPER_VERSION="not included"
if [ "$WHISPER" = 1 ]; then
  WTARGET=$([ "$ARCH" = arm64 ] && echo aarch64 || echo x86_64)
  WOUT=build/out/whisper
  WMODELS=build/out/whisper-models
  MAIN_OUT="$(cd "$(git rev-parse --git-common-dir)/.." && pwd)/build/out"
  [ -f "$WOUT/$WTARGET/whisper-server" ] || WOUT=$MAIN_OUT/whisper
  [ -f "$WMODELS/ggml-$WHISPER_MODEL.bin" ] || WMODELS=$MAIN_OUT/whisper-models
  [ -f "$WOUT/$WTARGET/whisper-server" ] ||
    { echo "no whisper-server in build/out/whisper/$WTARGET (build/whisper-build.sh $WTARGET, or --no-whisper)" >&2; exit 1; }
  [ -f "$WMODELS/ggml-$WHISPER_MODEL.bin" ] ||
    { echo "no model ggml-$WHISPER_MODEL.bin in build/out/whisper-models (build/whisper-models.sh, or --no-whisper)" >&2; exit 1; }
  (cd "$WOUT/$WTARGET" && sha256sum --quiet -c SHA256SUMS) || { echo "$WOUT/$WTARGET: SHA256SUMS mismatch" >&2; exit 1; }
  W="$STAGE/whisper"
  mkdir -p "$W/models"
  BINS=(whisper-server)
  [ "$WHISPER_BENCH" = 1 ] && BINS=(whisper-server whisper-cli whisper-bench)
  for b in "${BINS[@]}"; do cp "$WOUT/$WTARGET/$b" "$W/"; done
  cp "$WOUT/$WTARGET/BUILDINFO" "$W/"
  if [ "$WHISPER_VULKAN" = 1 ] && [ "$ARCH" = arm64 ]; then
    [ -f "$WOUT/aarch64-vulkan/whisper-server" ] ||
      { echo "no Vulkan build in $WOUT/aarch64-vulkan (build/whisper-build.sh aarch64-vulkan)" >&2; exit 1; }
    mkdir -p "$W/vulkan"
    for b in "${BINS[@]}"; do cp "$WOUT/aarch64-vulkan/$b" "$W/vulkan/"; done
    cp "$WOUT/aarch64-vulkan/BUILDINFO" "$W/vulkan/"
  fi
  if [ "$WHISPER_BENCH" = 1 ]; then
    cp "$WMODELS"/ggml-*.bin "$W/models/"
    mkdir -p "$W/samples"
    cp build/whisper/samples/*.wav "$W/samples/"
    cp tools/whisper-bench.sh "$STAGE/tools/"
  else
    cp "$WMODELS/ggml-$WHISPER_MODEL.bin" "$W/models/"
  fi
  (cd "$W" && find . -type f ! -name SHA256SUMS -printf '%P\n' | sort | xargs sha256sum > SHA256SUMS)
  cp "$WOUT/$WTARGET/LICENSE-whisper.cpp.txt" "$STAGE/LICENSES/whisper.cpp-MIT.txt"
  cp build/whisper/LICENSE-models.txt "$STAGE/LICENSES/whisper-models-MIT.txt"
  WHISPER_VERSION="$(head -1 "$W/BUILDINFO" | cut -d' ' -f2-), model $WHISPER_MODEL"
  [ "$WHISPER_VULKAN" = 1 ] && WHISPER_VERSION="$WHISPER_VERSION, Vulkan build"
  [ "$WHISPER_BENCH" = 1 ] && WHISPER_VERSION="$WHISPER_VERSION, bench kit"
fi

# --- Launcher, desktop entry, icon ------------------------------------------------------------------------------------
# The launcher, with the update swap and rollback (tools/player-run.sh; tested by tools/test_player_run.sh).
cp tools/player-run.sh "$STAGE/run.sh"
chmod +x "$STAGE/run.sh"

cat > "$STAGE/vr-video-player.desktop.in" <<'EOF'
[Desktop Entry]
Type=Application
Name=VR Video Player
Comment=Play flat, 3D, 180 and 360 video in the headset
Exec=@DIR@/run.sh
Path=@DIR@
Icon=@DIR@/icon.svg
Terminal=false
Categories=AudioVideo;Video;Player;
EOF

cat > "$STAGE/icon.svg" <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><rect width="64" height="64" rx="12" fill="#1c2430"/>
<path d="M10 22c0-3 2-5 5-5h34c3 0 5 2 5 5v20c0 3-2 5-5 5H38l-6-6-6 6H15c-3 0-5-2-5-5z" fill="#5fb3ff"/>
<path d="M27 26v12l10-6z" fill="#1c2430"/></svg>
EOF

# --- Licences ------------------------------------------------------------------------------------------------------
cp LICENSE "$STAGE/LICENSES/vr-video-player-MIT.txt"
cp app/models/controllers/LICENSE-controller.md "$STAGE/LICENSES/controller-models-CC-BY-NC-SA-4.0.md"
cp app/materials/CREDITS.md "$STAGE/LICENSES/material-textures-CC0-credits.md"
wsl_cat src/godot-player/LICENSE.txt > "$STAGE/LICENSES/engine-LICENSE.txt"
wsl_cat src/godot-player/COPYRIGHT.txt > "$STAGE/LICENSES/engine-COPYRIGHT.txt"
wsl_cat src/ffmpeg/COPYING.LGPLv2.1 > "$STAGE/LICENSES/FFmpeg-LGPL-2.1.txt"
wsl_cat src/libsmb2/COPYING > "$STAGE/LICENSES/libsmb2-COPYING.txt"
wsl_cat src/dav1d/COPYING > "$STAGE/LICENSES/dav1d-BSD-2-Clause.txt"
GODOT_REV=$(wsl_out 'git -C ~/src/godot-player log -1 --format="%H %s"' 2>/dev/null | tr -d '\r' || echo unknown)
FFMPEG_REV=$(wsl_out 'git -C ~/src/ffmpeg describe --tags --always' 2>/dev/null | tr -d '\r' || echo unknown)
SMB_REV=$(wsl_out 'git -C ~/src/libsmb2 describe --tags --always' 2>/dev/null | tr -d '\r' || echo unknown)
DAV1D_REV=$(wsl_out 'git -C ~/src/dav1d describe --tags --always' 2>/dev/null | tr -d '\r' || echo unknown)
cat > "$STAGE/LICENSES/THIRD-PARTY.md" <<EOF
# Third-party parts of this package

| Part | Licence | Version | Source |
|---|---|---|---|
| VR Video Player (app/, run.sh) | MIT (vr-video-player-MIT.txt) | $VERSION | this project's repository |
| Engine (bin/vr-video-player-engine): a fork of the Godot engine with a video module | MIT and the notices in engine-COPYRIGHT.txt | source tree at packaging: $GODOT_REV | the fork's branch frame/player; built with build/build-player.sh |
| FFmpeg (linked statically into the engine) | LGPL-2.1-or-later (FFmpeg-LGPL-2.1.txt); built without --enable-gpl or --enable-nonfree | $FFMPEG_REV | https://ffmpeg.org; configured by build/ffmpeg-build.sh |
| dav1d, the AV1 decoder (linked statically into the engine, through FFmpeg) | BSD-2-Clause (dav1d-BSD-2-Clause.txt) | $DAV1D_REV | https://code.videolan.org/videolan/dav1d; built by build/dav1d-build.sh |
| libsmb2 (linked statically into the engine) | LGPL-2.1-or-later (libsmb2-COPYING.txt) | $SMB_REV | https://github.com/sahlberg/libsmb2; patches in build/libsmb2-patches, built by build/libsmb2-build.sh |
| whisper.cpp (whisper/whisper-server, a separate program the app starts) | MIT (whisper.cpp-MIT.txt) | $WHISPER_VERSION | https://github.com/ggml-org/whisper.cpp; built by build/whisper-build.sh |
| Whisper speech models (whisper/models, ggml format) | MIT (whisper-models-MIT.txt) | pinned in build/whisper-models.sh | OpenAI's Whisper (https://github.com/openai/whisper), converted to ggml: https://huggingface.co/ggerganov/whisper.cpp |
| Controller models (app/models/controllers) | CC BY-NC-SA 4.0 (controller-models-CC-BY-NC-SA-4.0.md); non-commercial | see that file | see that file |
| Room textures (app/materials) | CC0 1.0, public domain (material-textures-CC0-credits.md) | see that file | Poly Haven and ambientCG; each asset's page in that file |

The LGPL parts are linked statically. To relink the engine with a modified FFmpeg or libsmb2, use the build scripts
named above with the same engine source revision; the source of every part is available as listed. Ask the
distributor for the exact sources of this package if a link above has moved.
EOF

# --- README and version --------------------------------------------------------------------------------------------
cat > "$STAGE/VERSION" <<EOF
version $VERSION
arch $ARCH
engine $ENGINE
engine_sha256 $ENGINE_SHA
app_commit $(git rev-parse HEAD)
whisper $WHISPER_VERSION
EOF
cat > "$STAGE/README.txt" <<'EOF'
VR Video Player

Install (from a PC, no root needed on the headset): tools/install-on-frame.sh <this tarball>
  It copies this folder to ~/vr-video-player and adds "VR Video Player" to the desktop session's menu.
By hand, on the headset: unpack anywhere, then run ./run.sh (arguments for the app after it; see USAGE.md).
Uninstall: delete ~/vr-video-player and ~/.local/share/applications/vr-video-player.desktop.
Log: ~/.local/state/vr-video-player/last.log. Settings: ~/.local/share/godot/app_userdata/VR Video Player/.
Licences: LICENSES/ (third-party parts in LICENSES/THIRD-PARTY.md).
Speech to text: whisper/ holds whisper.cpp's server and a speech model. The player starts it on this device only
  (127.0.0.1) when the assistant needs it; no audio leaves the headset for transcription.
EOF

mkdir -p "$OUT"
# Python writes the archive: on a Windows disk, chmod is lost and tar would mark the engine 644. Modes are set
# explicitly (folders, the engine and *.sh 755; the rest 644) and the owner is neutral (0/0, no user name).
PY=""
for c in python3 python py; do "$c" -c "" > /dev/null 2>&1 && { PY=$c; break; }; done
[ -n "$PY" ] || { echo "needs Python 3 to write the tarball" >&2; exit 1; }
"$PY" - "$OUT" "$NAME" <<'PYEOF'
import os, sys, tarfile
out, name = sys.argv[1], sys.argv[2]
def fix(ti):
    ti.uid = ti.gid = 0
    ti.uname = ti.gname = ""
    ex = (ti.isdir() or ti.name.endswith(".sh") or ti.name == name + "/bin/vr-video-player-engine"
          or ti.name.rsplit("/", 1)[-1] in ("whisper-server", "whisper-cli", "whisper-bench"))
    ti.mode = 0o755 if ex else 0o644
    return ti
with tarfile.open(os.path.join(out, name + ".tar.gz"), "w:gz") as t:
    t.add(os.path.join(out, name), arcname=name, filter=fix)
PYEOF
rm -rf "$STAGE"
echo "$OUT/$NAME.tar.gz ($(du -h "$OUT/$NAME.tar.gz" | cut -f1)), engine $ENGINE"
