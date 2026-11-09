#!/usr/bin/env bash
# Cuts a release: the packages, their checksums, the signed update file and the install manifest
# (docs/packaging.md, "Releases"). Run from Git Bash on the Windows PC that has the signing key.
#
#   tools/release.sh VERSION [--publish] [--notes TEXT] [--engine NAME] [--whisper-model STEM]
#                            [--pc-zip PATH | --no-pc]
#
#   VERSION              MAJOR.MINOR.PATCH (for example 0.1.0). Without --publish a suffix is allowed for a trial
#                        (0.1.0-test): everything is built and checked, nothing is published.
#   --publish            after the checks: tag v<VERSION>, push the tag, create the GitHub release with every asset
#                        (as a draft, then published as the latest release), and check the published latest.json.
#                        Only after the user agreed. Without it: build, check, print what would be published, stop.
#   --notes TEXT         the one line for the update prompt (latest.json "notes") and the release notes' first line
#   --engine NAME        the arm64 engine in build/out (default godot.linuxbsd.template_debug.arm64.PLAYER_PCWIN)
#   --whisper-model STEM put a speech model in the package (default: none; tools/package.sh)
#   --pc-zip PATH        use this zip of the PC windows app instead of building it (layout below)
#   --no-pc              no PC windows app in this release
#
# Refuses to run with changes to tracked files (or new files in app/, pc/ or tools/), when tools/privacy-check.sh
# finds anything, or without the signing key (tools/release-key.sh). The packages are scanned too
# (privacy-check.sh --archive: every entry's name and contents).
#
# Writes build/dist/release-<VERSION>/:
#   framecine-<V>-arm64.tar.gz        the package (one top folder, framecine-<V>-arm64/); the updater's
#   framecine-<V>-arm64.zip           the same files, for Frame Control and FrameDrop
#   framecine-pc-<V>-windows-x64.zip  the PC windows app: framecine-pc-<V>-windows-x64/ with
#                                           pc-windows.exe, README.txt, LICENSES/
#   latest.json, latest.json.sig            the update file and its RSA-3072 PKCS#1 v1.5 SHA-256 signature
#   install-manifest.json                   framedrop.install/v1 (FrameDrop and Frame Control): the zip
#   SHA256SUMS                              every asset above (sha256sum -c SHA256SUMS)
#   release-notes.md                        the release's text
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
GH_REPO=stringandstickytape/FrameCine
BASE_URL="https://github.com/$GH_REPO/releases"
KEY=${VRVP_RELEASE_KEY:-$HOME/.config/vrvp-release/release-key.pem}
PUB="$REPO/app/update/release-key.pub.pem"

VERSION=""
PUBLISH=0
NOTES=""
ENGINE=godot.linuxbsd.template_debug.arm64.PLAYER_PCWIN
WHISPER_MODEL=""
PC_ZIP=""
PC=1
while [ $# -gt 0 ]; do
  case "$1" in
    --publish) PUBLISH=1 ;;
    --notes) NOTES=$2; shift ;;
    --engine) ENGINE=$2; shift ;;
    --whisper-model) WHISPER_MODEL=$2; shift ;;
    --pc-zip) PC_ZIP=$2; shift ;;
    --no-pc) PC=0 ;;
    -h|--help) sed -n '2,31p' "$0"; exit 0 ;;
    -*) echo "unknown argument: $1" >&2; exit 2 ;;
    *) [ -z "$VERSION" ] || { echo "one VERSION only" >&2; exit 2; }; VERSION=$1 ;;
  esac
  shift
done
[ -n "$VERSION" ] || { echo "usage: tools/release.sh VERSION [--publish] (see --help)" >&2; exit 2; }
if [[ "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  :
elif [ "$PUBLISH" = 0 ] && [[ "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)-[a-z0-9]+$ ]]; then
  echo "trial version $VERSION: built and checked, never published"
else
  echo "VERSION must be MAJOR.MINOR.PATCH, for example 0.1.0 (a -suffix only without --publish)" >&2
  exit 2
fi
[ -z "$PC_ZIP" ] || [ -f "$PC_ZIP" ] || { echo "--pc-zip: no file $PC_ZIP" >&2; exit 2; }
[ -z "$PC_ZIP" ] || PC_ZIP=$(cd "$(dirname "$PC_ZIP")" && pwd)/$(basename "$PC_ZIP")
TAG="v$VERSION"
[ -n "$NOTES" ] || NOTES="FrameCine $VERSION."
case "$NOTES" in *$'\n'*) echo "--notes: one line" >&2; exit 2 ;; esac

PY=""
for c in python3 python py; do "$c" -c "" > /dev/null 2>&1 && { PY=$c; break; }; done
[ -n "$PY" ] || { echo "needs Python 3" >&2; exit 1; }
command -v openssl > /dev/null || { echo "needs openssl (Git Bash has it)" >&2; exit 1; }

cd "$REPO"
step() { printf '\n== %s\n' "$*"; }

# --- Checks before anything is built -----------------------------------------------------------------------------
step "checks"
DIRTY=$(git status --porcelain --untracked-files=no)
NEW=$(git status --porcelain --untracked-files=all -- app pc tools | grep '^??' || true)
if [ -n "$DIRTY" ] || [ -n "$NEW" ]; then
  echo "the working tree is not clean (commit or remove these first):" >&2
  printf '%s\n%s\n' "$DIRTY" "$NEW" | sed '/^$/d; s/^/  /' >&2
  exit 1
fi
bash tools/privacy-check.sh || { echo "tools/privacy-check.sh found something: fix it first" >&2; exit 1; }
echo "privacy check of the tree: clean"
git ls-files --error-unmatch app/update/release-key.pub.pem > /dev/null 2>&1 ||
  { echo "app/update/release-key.pub.pem is not committed (tools/release-key.sh, then commit it)" >&2; exit 1; }
VRVP_RELEASE_KEY=$KEY bash tools/release-key.sh --check
COMMIT=$(git rev-parse HEAD)
if git rev-parse -q --verify "refs/tags/$TAG" > /dev/null; then
  [ "$(git rev-parse "$TAG^{commit}")" = "$COMMIT" ] ||
    { echo "tag $TAG exists here and is not HEAD" >&2; exit 1; }
fi
if [ "$PUBLISH" = 1 ]; then
  command -v gh > /dev/null || { echo "needs gh (GitHub CLI)" >&2; exit 1; }
  gh auth status > /dev/null 2>&1 || { echo "gh is not logged in (gh auth login)" >&2; exit 1; }
  git fetch -q origin main
  git merge-base --is-ancestor "$COMMIT" origin/main ||
    { echo "HEAD ($COMMIT) is not on origin/main: push main first, then release" >&2; exit 1; }
  [ -z "$(git ls-remote --tags origin "refs/tags/$TAG")" ] || { echo "tag $TAG is already on GitHub" >&2; exit 1; }
  ! gh release view "$TAG" --repo "$GH_REPO" > /dev/null 2>&1 || { echo "release $TAG already exists" >&2; exit 1; }
fi

# --- The packages ------------------------------------------------------------------------------------------------
DIST="$REPO/build/dist"
REL="$DIST/release-$VERSION"
PKG="framecine-$VERSION-arm64"
PCNAME="framecine-pc-$VERSION-windows-x64"
rm -rf "$REL"
mkdir -p "$REL"

step "the headset package"
WM=()
[ -z "$WHISPER_MODEL" ] || WM=(--whisper-model "$WHISPER_MODEL")
bash tools/package.sh --version "$VERSION" --zip --engine "$ENGINE" --out "$DIST" "${WM[@]}"
mv -f "$DIST/$PKG.tar.gz" "$DIST/$PKG.zip" "$REL/"

if [ "$PC" = 1 ]; then
  step "the PC windows app"
  if [ -n "$PC_ZIP" ]; then
    cp "$PC_ZIP" "$REL/$PCNAME.zip"
  else
    command -v cmd.exe > /dev/null || { echo "building the PC app needs Windows (or pass --pc-zip / --no-pc)" >&2; exit 1; }
    # A clean Release build of the committed sources, with its unit tests (pc/build.cmd).
    PCW_BUILD_DIR="$(cygpath -w "$REPO/pc/build-release")" MSYS2_ARG_CONV_EXCL='*' cmd.exe /c "$(cygpath -w "$REPO/pc/build.cmd")" clean
    EXE="$REPO/pc/build-release/pc-windows.exe"
    [ -f "$EXE" ] || { echo "no $EXE after the build" >&2; exit 1; }
    PCSTAGE="$DIST/$PCNAME"
    rm -rf "$PCSTAGE"
    mkdir -p "$PCSTAGE/LICENSES"
    cp "$EXE" "$PCSTAGE/pc-windows.exe"
    "$PY" tools/neutralise_paths.py "$PCSTAGE/pc-windows.exe"
    cp LICENSE "$PCSTAGE/LICENSES/framecine-MIT.txt"
    cat > "$PCSTAGE/LICENSES/THIRD-PARTY.txt" <<'EOF'
Third-party parts of pc-windows.exe

pc-windows.exe uses only what Windows has (Windows.Graphics.Capture, Direct3D 11, Media Foundation, WASAPI,
Schannel, DPAPI, WIC). It is built with Microsoft Visual C++ (the C and C++ runtime linked statically, which
Microsoft's Visual Studio licence permits for distribution) and the Windows SDK, whose C++/WinRT headers are
compiled in under this licence:

  C++/WinRT, Copyright (c) Microsoft Corporation. MIT License.
  Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
  documentation files (the "Software"), to deal in the Software without restriction, including without limitation
  the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
  permit persons to whom the Software is furnished to do so, subject to the following conditions:
  The above copyright notice and this permission notice shall be included in all copies or substantial portions of
  the Software.
  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO
  THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
  CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
  IN THE SOFTWARE.

The rest of pc-windows.exe is this project's own code: MIT (framecine-MIT.txt).
EOF
    { sed "s/@VERSION@/$VERSION/g" tools/release-pc-readme.txt; } > "$PCSTAGE/README.txt"
    "$PY" - "$DIST" "$PCNAME" <<'PYEOF'
import os, sys, time, zipfile
dist, name = sys.argv[1], sys.argv[2]
root = os.path.join(dist, name)
with zipfile.ZipFile(os.path.join(dist, name + ".zip"), "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for folder, dirs, files in os.walk(root):
        dirs.sort()
        rel = os.path.relpath(folder, dist).replace(os.sep, "/")
        z.writestr(zipfile.ZipInfo(rel + "/", date_time=time.localtime()[:6]), b"")
        for f in sorted(files):
            z.write(os.path.join(folder, f), rel + "/" + f)
PYEOF
    rm -rf "$PCSTAGE"
    mv -f "$DIST/$PCNAME.zip" "$REL/"
  fi
fi

# --- Checks on what was built ------------------------------------------------------------------------------------
step "checks on the packages"
ASSETS=("$PKG.tar.gz" "$PKG.zip")
[ "$PC" = 0 ] || ASSETS+=("$PCNAME.zip")
(cd "$REL" && bash "$REPO/tools/privacy-check.sh" --archive "${ASSETS[@]}") ||
  { echo "the packages hold personal data (above): nothing published" >&2; exit 1; }
echo "privacy check of the packages: clean"
"$PY" - "$REL" "$PKG" "$VERSION" "$PC" "$PCNAME" <<'PYEOF'
import os, sys, tarfile, zipfile
rel, pkg, version, pc, pcname = sys.argv[1:6]
tar = tarfile.open(os.path.join(rel, pkg + ".tar.gz"))
zf = zipfile.ZipFile(os.path.join(rel, pkg + ".zip"))
t = {m.name.rstrip("/"): (m.mode, m.size, m.isdir()) for m in tar.getmembers()}
z = {i.filename.rstrip("/"): ((i.external_attr >> 16) & 0o7777, i.file_size, i.is_dir()) for i in zf.infolist()}
problems = []
if t != z:
    problems.append("the tarball and the zip differ: %s" % sorted(set(t.items()) ^ set(z.items()))[:5])
if {n.split("/")[0] for n in t} != {pkg}:
    problems.append("not one top folder %s/" % pkg)
for name, mode in ((pkg + "/run.sh", 0o755), (pkg + "/bin/framecine-engine", 0o755), (pkg + "/VERSION", 0o644)):
    if name not in t or t[name][0] != mode:
        problems.append("%s missing or not mode %o" % (name, mode))
bad = [n for n, (m, s, d) in t.items() if m not in (0o644, 0o755)]
if bad:
    problems.append("odd modes: %s" % bad[:5])
if zf.testzip() is not None:
    problems.append("the zip has a bad entry")
engine = tar.extractfile(pkg + "/bin/framecine-engine").read(20)
if engine[:4] != b"\x7fELF" or int.from_bytes(engine[18:20], "little") != 183:  # EM_AARCH64
    problems.append("the engine is not an arm64 ELF")
first = tar.extractfile(pkg + "/VERSION").read().decode().splitlines()[0]
if first != "version " + version:
    problems.append("VERSION says %r" % first)
if pc == "1":
    p = zipfile.ZipFile(os.path.join(rel, pcname + ".zip"))
    names = set(p.namelist())
    for need in ("pc-windows.exe", "README.txt", "LICENSES/framecine-MIT.txt"):
        if pcname + "/" + need not in names:
            problems.append("the PC zip has no %s/%s" % (pcname, need))
    exe = p.read(pcname + "/pc-windows.exe")
    if exe[:2] != b"MZ":
        problems.append("pc-windows.exe is not a Windows program")
if problems:
    print("\n".join(problems), file=sys.stderr)
    sys.exit(1)
print("packages: %d entries, one top folder, tarball and zip alike, modes 644/755, arm64 engine" % len(t))
PYEOF
# The packaged app/ started with the desktop engine (WSL): every script must load.
SMOKE_PKG=$(printf '%s' "$REL/$PKG.tar.gz" | sed -E 's#^/([a-z])/#/mnt/\1/#')
SMOKE_SH=$(printf '%s' "$REPO/tools/smoke-package.sh" | sed -E 's#^/([a-z])/#/mnt/\1/#')
if command -v wsl.exe > /dev/null 2>&1; then
  MSYS_NO_PATHCONV=1 wsl.exe bash -l "$SMOKE_SH" "$SMOKE_PKG" || { echo "the packaged app does not start: nothing published" >&2; exit 1; }
else
  bash "$REPO/tools/smoke-package.sh" "$REL/$PKG.tar.gz" || { echo "the packaged app does not start: nothing published" >&2; exit 1; }
fi

# --- latest.json, its signature, the install manifest, SHA256SUMS, the notes --------------------------------------
step "the update file and the manifest"
"$PY" - "$REL" "$PKG" "$VERSION" "$TAG" "$BASE_URL" "$NOTES" <<'PYEOF'
import hashlib, json, os, sys
rel, pkg, version, tag, base, notes = sys.argv[1:7]
def info(name):
    h = hashlib.sha256()
    with open(os.path.join(rel, name), "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return {"url": "%s/download/%s/%s" % (base, tag, name), "size": os.path.getsize(os.path.join(rel, name)),
            "sha256": h.hexdigest()}
tgz = info(pkg + ".tar.gz")
latest = {"version": version, "tag": tag,
          "package": {"url": tgz["url"], "size": tgz["size"], "sha256": tgz["sha256"]},
          "notes": notes}
zp = info(pkg + ".zip")
# "name" becomes the Devkit id, which is the title Steam shows (no spaces: Frame Control turns them into "_").
manifest = {"schema": "framedrop.install/v1", "name": "FrameCine",
            "files": [{"url": zp["url"], "sha256": zp["sha256"], "size": zp["size"], "exe": "run.sh"}]}
# UTF-8, no BOM, LF; signed byte for byte as written.
for name, obj in (("latest.json", latest), ("install-manifest.json", manifest)):
    with open(os.path.join(rel, name), "wb") as f:
        f.write((json.dumps(obj, indent=2, ensure_ascii=False) + "\n").encode("utf-8"))
PYEOF
openssl dgst -sha256 -sign "$KEY" -out "$REL/latest.json.sig" "$REL/latest.json"
openssl dgst -sha256 -verify "$PUB" -signature "$REL/latest.json.sig" "$REL/latest.json" > /dev/null ||
  { echo "latest.json.sig does not verify with app/update/release-key.pub.pem" >&2; exit 1; }
echo "latest.json.sig: verified with app/update/release-key.pub.pem"
ASSETS+=(latest.json latest.json.sig install-manifest.json)
(cd "$REL" && sha256sum "${ASSETS[@]}" > SHA256SUMS && sha256sum --quiet -c SHA256SUMS)
ASSETS+=(SHA256SUMS)

FPR=$(openssl pkey -pubin -in "$PUB" -outform DER 2> /dev/null | sha256sum | cut -d' ' -f1)
{
  echo "$NOTES"
  echo
  echo "FrameCine for the Steam Frame. Install guide: [docs/install.md](https://github.com/$GH_REPO/blob/$TAG/docs/install.md)."
  echo
  echo "| File | What |"
  echo "|---|---|"
  echo "| \`$PKG.zip\` | The player, for Frame Control or FrameDrop (\`install-manifest.json\` is its install manifest) |"
  echo "| \`$PKG.tar.gz\` | The same files, for \`tools/install-on-frame.sh\` (ssh) and the player's own updates |"
  [ "$PC" = 0 ] || echo "| \`$PCNAME.zip\` | PC windows: sends windows from a Windows PC to the headset (optional) |"
  echo "| \`latest.json\`, \`latest.json.sig\` | The update check's file and its signature |"
  echo "| \`SHA256SUMS\` | Checksums of every file: \`sha256sum -c SHA256SUMS\` |"
  echo
  echo "Built from $COMMIT. Update signing key: RSA-3072, SHA-256 of the public key (DER) \`$FPR\`"
  echo "(\`app/update/release-key.pub.pem\`)."
} > "$REL/release-notes.md"

# --- Summary, and publish ------------------------------------------------------------------------------------------
step "release $TAG in ${REL#"$REPO/"}/"
(cd "$REL" && for a in "${ASSETS[@]}"; do printf '  %-45s %12s bytes\n' "$a" "$(stat -c %s "$a")"; done)
echo
echo "latest.json:"
sed 's/^/  /' "$REL/latest.json"
echo "install-manifest.json:"
sed 's/^/  /' "$REL/install-manifest.json"

# gh runs in the release folder, with the assets by name.
GH_ARGS=(release create "$TAG" --repo "$GH_REPO" --verify-tag --draft --title "FrameCine $VERSION"
         --notes-file release-notes.md "${ASSETS[@]}")
show() { local s; s=$(printf ' %q' "$@"); echo "  ${s# }"; }
if [ "$PUBLISH" = 0 ]; then
  echo
  if [[ "$VERSION" == *-* ]]; then
    echo "Not published: $VERSION is a trial version. A release runs: tools/release.sh ${VERSION%%-*} --publish"
  else
    echo "Not published (no --publish). To publish, after the user agrees: tools/release.sh $VERSION --publish"
  fi
  echo "which, after the checks and the build above, runs in the repository:"
  show git tag -a "$TAG" -m "FrameCine $VERSION" "$COMMIT"
  show git push origin "refs/tags/$TAG"
  echo "  and in ${REL#"$REPO/"}/:"
  show gh "${GH_ARGS[@]}"
  show gh release edit "$TAG" --repo "$GH_REPO" --draft=false --latest
  echo "  then checks that $BASE_URL/latest/download/latest.json is this latest.json, byte for byte"
  exit 0
fi

step "publish $TAG"
git rev-parse -q --verify "refs/tags/$TAG" > /dev/null || git tag -a "$TAG" -m "FrameCine $VERSION" "$COMMIT"
git push origin "refs/tags/$TAG"
(cd "$REL" && gh "${GH_ARGS[@]}")
# Published only once every asset is up, so no player sees a latest.json without its package.
gh release edit "$TAG" --repo "$GH_REPO" --draft=false --latest
CHECK=$(mktemp)
trap 'rm -f "$CHECK"' EXIT
for i in 1 2 3 4 5 6; do
  if curl -fsSL --max-time 30 -o "$CHECK" "$BASE_URL/latest/download/latest.json" && cmp -s "$CHECK" "$REL/latest.json"; then
    echo "published: $BASE_URL/tag/$TAG; latest/download/latest.json is this release's"
    exit 0
  fi
  sleep 10
done
echo "published, but $BASE_URL/latest/download/latest.json is not this release's latest.json yet: check by hand" >&2
exit 1
