#!/usr/bin/env bash
# Builds a release tarball of the player, for installing without a store (docs/packaging.md).
# Runs from Git Bash or WSL. The engine's licence files and the x86_64 engine are read from the WSL build tree
# (~/src/...); from Git Bash they are fetched with wsl.exe.
#
#   tools/package.sh [--engine NAME] [--engine-src DIR] [--arch arm64|x86_64] [--out DIR] [--version V] [--zip]
#                    [--no-whisper] [--whisper-model STEM] [--whisper-vulkan] [--whisper-bench]
#
#   --engine NAME          an engine binary in build/out (default: the newest godot.linuxbsd.*.arm64*); for x86_64,
#                          a build in the WSL tree's bin/ (default godot.linuxbsd.template_debug.x86_64)
#   --engine-src DIR       the engine's source tree in the WSL home, for its licence files and revision (default
#                          src/godot-pcwindows for a *PCWIN engine, else src/godot-player)
#   --version V            the version (releases: MAJOR.MINOR.PATCH, tools/release.sh passes it); default git describe
#   --zip                  also write the zip (same files, folder and modes) for FrameDrop and Frame Control
#   --no-whisper           leave out whisper/, on-device speech to text (below). whisper-server is in by default.
#   --whisper-model STEM   also put a speech model in whisper/models (for example small.en-q8_0; build/whisper-models.sh
#                          fetches them). By default there is none: the player downloads one the first time voice is
#                          used (docs/framedrop.md, "The speech model"). For offline installs.
#   --whisper-vulkan       also the Vulkan build of the server, in whisper/vulkan/ (50 MB)
#   --whisper-bench        the benchmark kit: whisper-cli and whisper-bench (both builds), every model in
#                          build/out/whisper-models, the speech samples, tools/whisper-bench.sh
#   --no-kernel-modules    accepted and ignored, for old command lines: there is no decoder module (docs/decisions.md D21)
#
# Build paths: the builder's user name in /home/<name>/ (from __FILE__ in FFmpeg's and ggml's asserts) is replaced in
# the engine and the whisper programs by a neutral one of the same length (tools/neutralise_paths.py), so no user name
# ships. VERSION keeps the engine's hash before (engine_build_sha256) and after (engine_sha256).
#
# Output: build/dist/framecine-<version>-<arch>.tar.gz (and .zip with --zip), one top folder
# framecine-<version>-<arch>/ holding
#   bin/framecine-engine   the engine fork (template build with path overrides: it runs the app folder as is)
#   app/                         the project, as committed (no tests, docs or editor tools)
#   run.sh                       the launcher (the known-good recipe: x11 display driver, XR on, DISPLAY / runtime dir)
#   framecine.desktop.in   the desktop entry; install-on-frame.sh fills in the folder
#   tools/steam_shortcuts.py     the library shortcut helper (install-on-frame.sh --steam)
#   whisper/                     speech to text for the assistant (build/whisper/README.md): whisper-server from
#                                build/out/whisper/<aarch64|x86_64> (build/whisper-build.sh); models/ggml-<model>.bin
#                                only with --whisper-model; the app starts the server on 127.0.0.1 when it is needed
#   icon.svg, README.txt, VERSION, LICENSES/ (this app MIT; the engine; FFmpeg LGPL-2.1; dav1d BSD-2; libsmb2 LGPL-2.1; whisper.cpp
#   and the speech models MIT; the controller models CC BY-NC-SA 4.0; THIRD-PARTY.md with versions and sources)
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
ARCH=arm64
ENGINE=""
ENGINE_SRC=""
OUT="$REPO/build/dist"
VERSION=""
ZIP=0
WHISPER=1
WHISPER_MODEL=""
WHISPER_VULKAN=0
WHISPER_BENCH=0
while [ $# -gt 0 ]; do
  case "$1" in
    --engine) ENGINE=$2; shift ;;
    --engine-src) ENGINE_SRC=${2#"~/"}; shift ;;
    --arch) ARCH=$2; shift ;;
    --out) OUT=$2; shift ;;
    --version) VERSION=$2; shift ;;
    --zip) ZIP=1 ;;
    --with-kernel-module) echo "--with-kernel-module: the decoder module was removed (docs/decisions.md D21)" >&2; exit 2 ;;
    --no-kernel-modules) ;;  # accepted for old command lines: there is no module bundle any more
    --no-whisper) WHISPER=0 ;;
    --whisper-model) WHISPER_MODEL=$2; shift ;;
    --whisper-vulkan) WHISPER_VULKAN=1 ;;
    --whisper-bench) WHISPER_BENCH=1; WHISPER_VULKAN=1 ;;
    -h|--help) sed -n '2,39p' "$0"; exit 0 ;;
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

PY=""
for c in python3 python py; do "$c" -c "" > /dev/null 2>&1 && { PY=$c; break; }; done
[ -n "$PY" ] || { echo "needs Python 3 to write the archives" >&2; exit 1; }

# The builder's user name out of a binary's build paths (__FILE__), same length (tools/neutralise_paths.py).
neutralise() { "$PY" "$REPO/tools/neutralise_paths.py" "$@"; }

cd "$REPO"
[ -n "$VERSION" ] || VERSION=$(git describe --tags --always --dirty 2>/dev/null || git rev-parse --short HEAD)
case "$VERSION" in ""|*[!A-Za-z0-9._+-]*) echo "--version: letters, digits and . _ + - only" >&2; exit 2 ;; esac
NAME="framecine-$VERSION-$ARCH"
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
  case "$ENGINE" in *PCWIN*) ENGINE_SRC=${ENGINE_SRC:-src/godot-pcwindows} ;; esac
  ENGINE_SRC=${ENGINE_SRC:-src/godot-player}
  cp "$ENGINE_DIR/$ENGINE" "$STAGE/bin/framecine-engine"
else
  ENGINE=${ENGINE:-godot.linuxbsd.template_debug.x86_64}
  ENGINE_SRC=${ENGINE_SRC:-src/godot-player}
  wsl_cat "$ENGINE_SRC/bin/$ENGINE" > "$STAGE/bin/framecine-engine"
fi
chmod +x "$STAGE/bin/framecine-engine"
ENGINE_BUILD_SHA=$(sha256sum "$STAGE/bin/framecine-engine" | cut -d' ' -f1)
neutralise "$STAGE/bin/framecine-engine"
ENGINE_SHA=$(sha256sum "$STAGE/bin/framecine-engine" | cut -d' ' -f1)

# --- The app, as committed ------------------------------------------------------------------------------------------
# With LF line ends whatever this checkout uses (Git for Windows' autocrlf would give CRLF JSON and SVG files), so the
# package is the same from any PC.
git -c core.autocrlf=false -c core.eol=lf archive HEAD app | tar -x -C "$STAGE"
# app/tools is dev tools, except the files the app loads at run time (tools/smoke-package.sh catches a miss).
KEEP_TOOLS=(make_pane_theme.gd)
mkdir -p "$STAGE/keep-tools"
for f in "${KEEP_TOOLS[@]}"; do cp "$STAGE/app/tools/$f" "$STAGE/keep-tools/"; done
rm -rf "$STAGE/app/tests" "$STAGE/app/docs" "$STAGE/app/tools"
mv "$STAGE/keep-tools" "$STAGE/app/tools"

# The shortcut helper for install-on-frame.sh --steam (runs on the headset).
mkdir -p "$STAGE/tools"
cp tools/steam_shortcuts.py "$STAGE/tools/"

# --- Speech to text: whisper-server, and a model only on request (build/whisper/README.md) ---------------------------
# build/out is not in git: in a linked worktree, fall back to the main checkout's (as for the engine).
# Without --whisper-model there is no model: the player downloads one into its data folder the first time voice is
# used (docs/framedrop.md, "The speech model"), so the package and each update stay small.
WHISPER_VERSION="not included"
if [ "$WHISPER" = 1 ]; then
  WTARGET=$([ "$ARCH" = arm64 ] && echo aarch64 || echo x86_64)
  WOUT=build/out/whisper
  WMODELS=build/out/whisper-models
  MAIN_OUT="$(cd "$(git rev-parse --git-common-dir)/.." && pwd)/build/out"
  [ -f "$WOUT/$WTARGET/whisper-server" ] || WOUT=$MAIN_OUT/whisper
  ls "$WMODELS"/ggml-*.bin > /dev/null 2>&1 || WMODELS=$MAIN_OUT/whisper-models
  [ -f "$WOUT/$WTARGET/whisper-server" ] ||
    { echo "no whisper-server in build/out/whisper/$WTARGET (build/whisper-build.sh $WTARGET, or --no-whisper)" >&2; exit 1; }
  if [ -n "$WHISPER_MODEL" ]; then
    [ -f "$WMODELS/ggml-$WHISPER_MODEL.bin" ] ||
      { echo "no model ggml-$WHISPER_MODEL.bin in build/out/whisper-models (build/whisper-models.sh)" >&2; exit 1; }
  fi
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
  elif [ -n "$WHISPER_MODEL" ]; then
    cp "$WMODELS/ggml-$WHISPER_MODEL.bin" "$W/models/"
  fi
  for b in "${BINS[@]}"; do
    neutralise "$W/$b"
    [ ! -d "$W/vulkan" ] || neutralise "$W/vulkan/$b"
  done
  (cd "$W" && find . -type f ! -name SHA256SUMS -printf '%P\n' | sort | xargs sha256sum > SHA256SUMS)
  cp "$WOUT/$WTARGET/LICENSE-whisper.cpp.txt" "$STAGE/LICENSES/whisper.cpp-MIT.txt"
  cp build/whisper/LICENSE-models.txt "$STAGE/LICENSES/whisper-models-MIT.txt"
  WHISPER_VERSION="$(head -1 "$W/BUILDINFO" | cut -d' ' -f2-)"
  if [ "$WHISPER_BENCH" = 1 ]; then WHISPER_VERSION="$WHISPER_VERSION, every model, bench kit"
  elif [ -n "$WHISPER_MODEL" ]; then WHISPER_VERSION="$WHISPER_VERSION, model $WHISPER_MODEL"
  else WHISPER_VERSION="$WHISPER_VERSION, no model in the package"; fi
  [ "$WHISPER_VULKAN" = 1 ] && WHISPER_VERSION="$WHISPER_VERSION, Vulkan build"
fi

# --- Launcher, desktop entry, icon ------------------------------------------------------------------------------------
# The launcher, with the update swap and rollback (tools/player-run.sh; tested by tools/test_player_run.sh).
cp tools/player-run.sh "$STAGE/run.sh"
chmod +x "$STAGE/run.sh"

cat > "$STAGE/framecine.desktop.in" <<'EOF'
[Desktop Entry]
Type=Application
Name=FrameCine
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
cp LICENSE "$STAGE/LICENSES/framecine-MIT.txt"
cp app/models/controllers/LICENSE-controller.md "$STAGE/LICENSES/controller-models-CC-BY-NC-SA-4.0.md"
cp app/materials/CREDITS.md "$STAGE/LICENSES/material-textures-CC0-credits.md"
cp app/keyboard/LICENSE-words.txt "$STAGE/LICENSES/keyboard-words.txt"
wsl_cat "$ENGINE_SRC/LICENSE.txt" > "$STAGE/LICENSES/engine-LICENSE.txt"
wsl_cat "$ENGINE_SRC/COPYRIGHT.txt" > "$STAGE/LICENSES/engine-COPYRIGHT.txt"
wsl_cat src/ffmpeg/COPYING.LGPLv2.1 > "$STAGE/LICENSES/FFmpeg-LGPL-2.1.txt"
wsl_cat src/libsmb2/COPYING > "$STAGE/LICENSES/libsmb2-COPYING.txt"
wsl_cat src/dav1d/COPYING > "$STAGE/LICENSES/dav1d-BSD-2-Clause.txt"
GODOT_REV=$(wsl_out "git -C ~/$ENGINE_SRC log -1 --format='%H %s'" 2>/dev/null | tr -d '\r' || echo unknown)
GODOT_BRANCH=$(wsl_out "git -C ~/$ENGINE_SRC rev-parse --abbrev-ref HEAD" 2>/dev/null | tr -d '\r' || echo unknown)
FFMPEG_REV=$(wsl_out 'git -C ~/src/ffmpeg describe --tags --always' 2>/dev/null | tr -d '\r' || echo unknown)
SMB_REV=$(wsl_out 'git -C ~/src/libsmb2 describe --tags --always' 2>/dev/null | tr -d '\r' || echo unknown)
DAV1D_REV=$(wsl_out 'git -C ~/src/dav1d describe --tags --always' 2>/dev/null | tr -d '\r' || echo unknown)
cat > "$STAGE/LICENSES/THIRD-PARTY.md" <<EOF
# Third-party parts of this package

| Part | Licence | Version | Source |
|---|---|---|---|
| FrameCine (app/, run.sh) | MIT (framecine-MIT.txt) | $VERSION | this project's repository |
| Engine (bin/framecine-engine): a fork of the Godot engine with a video module | MIT and the notices in engine-COPYRIGHT.txt | source tree at packaging: $GODOT_REV | https://github.com/stringandstickytape/godot, branch $GODOT_BRANCH; built with build/build-player.sh |
| FFmpeg (linked statically into the engine) | LGPL-2.1-or-later (FFmpeg-LGPL-2.1.txt); built without --enable-gpl or --enable-nonfree | $FFMPEG_REV | https://ffmpeg.org; configured by build/ffmpeg-build.sh |
| dav1d, the AV1 decoder (linked statically into the engine, through FFmpeg) | BSD-2-Clause (dav1d-BSD-2-Clause.txt) | $DAV1D_REV | https://code.videolan.org/videolan/dav1d; built by build/dav1d-build.sh |
| libsmb2 (linked statically into the engine) | LGPL-2.1-or-later (libsmb2-COPYING.txt) | $SMB_REV | https://github.com/sahlberg/libsmb2; patches in build/libsmb2-patches, built by build/libsmb2-build.sh |
| whisper.cpp (whisper/whisper-server, a separate program the app starts) | MIT (whisper.cpp-MIT.txt) | $WHISPER_VERSION | https://github.com/ggml-org/whisper.cpp; built by build/whisper-build.sh |
| Whisper speech models (ggml format; in whisper/models only when packaged with one, else fetched separately) | MIT (whisper-models-MIT.txt) | pinned in build/whisper-models.sh | OpenAI's Whisper (https://github.com/openai/whisper), converted to ggml: https://huggingface.co/ggerganov/whisper.cpp |
| Controller models (app/models/controllers) | CC BY-NC-SA 4.0 (controller-models-CC-BY-NC-SA-4.0.md); non-commercial | see that file | see that file |
| Room textures (app/materials) | CC0 1.0, public domain (material-textures-CC0-credits.md) | see that file | Poly Haven and ambientCG; each asset's page in that file |
| Keyboard words (app/keyboard/words.tsv.gz) | permissive notices and public domain (keyboard-words.txt) | SCOWL 2020.12.07, modified levels 10-50 | https://wordlist.aspell.net/; tools/build_keyboard_words.py |

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
engine_build_sha256 $ENGINE_BUILD_SHA
engine_source $GODOT_BRANCH ${GODOT_REV%% *}
app_commit $(git rev-parse HEAD)
whisper $WHISPER_VERSION
EOF
cat > "$STAGE/README.txt" <<'EOF'
FrameCine, for the Steam Frame. Full install guide: docs/install.md in the project's repository
(https://github.com/stringandstickytape/FrameCine).

Install with Frame Control or FrameDrop (on a PC): turn on Developer Mode on the headset (Steam Settings > System),
  pair the headset once in the PC tool, then use the install link or drop the .zip on the tool. The player shows in
  the Steam library under Non-Steam. The tool puts this folder in ~/devkit-game/<id>/ on the headset.
Install over ssh: tools/install-on-frame.sh <the .tar.gz> (from the repository, on the PC). It copies this folder to
  ~/framecine and adds "FrameCine" to the desktop session's menu.
By hand, on the headset: unpack anywhere, then run ./run.sh (arguments for the app after it; see USAGE.md).
Updates: the player checks the project's GitHub releases and updates itself (System has a setting to stop this).
Uninstall: remove the title in the PC tool (or delete its folder); for the ssh install, delete ~/framecine
  and ~/.local/share/applications/framecine.desktop.
Log: ~/.local/state/framecine/last.log. Settings: ~/.local/share/godot/app_userdata/FrameCine/.
Licences: LICENSES/ (third-party parts in LICENSES/THIRD-PARTY.md).
Speech to text: whisper/ holds whisper.cpp's server. The player starts it on this device only (127.0.0.1) when the
  assistant needs it; no audio leaves the headset for transcription.
EOF
if [ "$WHISPER" = 1 ] && [ -z "$WHISPER_MODEL" ] && [ "$WHISPER_BENCH" = 0 ]; then
  echo "  The speech model is not in this package; voice needs one (whisper/models, or the player's data folder)." \
    >> "$STAGE/README.txt"
fi

mkdir -p "$OUT"
# Python writes the archives: on a Windows disk, chmod is lost and tar would mark the engine 644. Modes are set
# explicitly (folders, the engine, *.sh and the whisper programs 755; the rest 644) and the owner is neutral (0/0, no
# user name). The zip holds the same entries under the same top folder, with the same modes in external_attr (made
# on "Unix", so unzip and Python's zipfile apply them), for FrameDrop and Frame Control.
"$PY" - "$OUT" "$NAME" "$ZIP" <<'PYEOF'
import os, stat, sys, tarfile, time, zipfile
out, name, want_zip = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
root = os.path.join(out, name)

def mode_for(arcname, is_dir):
    ex = (is_dir or arcname.endswith(".sh") or arcname == name + "/bin/framecine-engine"
          or arcname.rsplit("/", 1)[-1] in ("whisper-server", "whisper-cli", "whisper-bench"))
    return 0o755 if ex else 0o644

def fix(ti):
    ti.uid = ti.gid = 0
    ti.uname = ti.gname = ""
    ti.mode = mode_for(ti.name, ti.isdir())
    return ti

with tarfile.open(os.path.join(out, name + ".tar.gz"), "w:gz") as t:
    t.add(root, arcname=name, filter=fix)

if want_zip:
    path = os.path.join(out, name + ".zip")
    with zipfile.ZipFile(path + ".part", "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        def add(full, arc, is_dir):
            when = time.localtime(max(os.stat(full).st_mtime, 315532800 + 86400))[:6]  # zip dates start in 1980
            zi = zipfile.ZipInfo(arc + "/" if is_dir else arc, date_time=when)
            zi.create_system = 3  # Unix: the mode below is read
            kind = stat.S_IFDIR if is_dir else stat.S_IFREG
            zi.external_attr = ((kind | mode_for(arc, is_dir)) << 16) | (0x10 if is_dir else 0)
            if is_dir:
                z.writestr(zi, b"")
            else:
                zi.compress_type = zipfile.ZIP_DEFLATED
                zi.file_size = os.path.getsize(full)  # zip64 only where a file needs it
                with open(full, "rb") as src, z.open(zi, "w") as dst:
                    while True:
                        chunk = src.read(1 << 20)
                        if not chunk:
                            break
                        dst.write(chunk)
        def walk(full, arc):  # the same order as tarfile.add: the folder, then its entries sorted
            add(full, arc, True)
            for entry in sorted(os.listdir(full)):
                f, a = os.path.join(full, entry), arc + "/" + entry
                if os.path.isdir(f):
                    walk(f, a)
                else:
                    add(f, a, False)
        walk(root, name)
    os.replace(path + ".part", path)
PYEOF
rm -rf "$STAGE"
echo "$OUT/$NAME.tar.gz ($(du -h "$OUT/$NAME.tar.gz" | cut -f1)), engine $ENGINE"
[ "$ZIP" = 1 ] && echo "$OUT/$NAME.zip ($(du -h "$OUT/$NAME.zip" | cut -f1))"
exit 0
