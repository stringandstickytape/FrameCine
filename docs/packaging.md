# Packaging and installing without a store

`tools/package.sh` builds the package (a tarball, and a zip with the same files). `tools/release.sh` builds a whole
release: the packages, the PC windows app, `SHA256SUMS`, the signed `latest.json` for the player's updates and the
install manifest for Frame Control and FrameDrop (section "Releases"). `tools/install-on-frame.sh` copies a tarball
to the headset over ssh and adds a menu entry for the desktop session. None needs root on the headset. The user's
install guide is `docs/install.md`; the plan behind it is `docs/framedrop.md` and `docs/decisions.md` D32.

**Not yet tested on the device.** The packaging, the install, the update and the uninstall are tested in WSL
(x86_64 build, a fake home folder, a fake Steam user folder). See the morning checklist, section "Packaging".

## Build a package

```
tools/package.sh                                   # arm64, the newest engine in build/out
tools/package.sh --engine godot.linuxbsd.template_debug.arm64.PLAYER_PCWIN --version 0.1.0 --zip
tools/package.sh --arch x86_64 --engine-src src/godot-pcwindows   # a desktop Linux build (the WSL fork build)
```

The result is `build/dist/framecine-<version>-<arch>.tar.gz`, and with `--zip` also `.zip` beside it (both
about 94 MB for 0.1.0; the engine is 108 MB unpacked and the room textures 55 MB). The version defaults to
`git describe`; releases pass it (`tools/release.sh`, below). Run it from Git Bash or WSL. It needs Python 3 (to write
the archives with the right file modes) and the WSL build tree at `~/src` for the licence files, the engine's revision
and the x86_64 engine. In a linked git worktree it takes the engine and whisper from the main checkout's `build/out`.

Both archives hold one top folder, `framecine-<version>-<arch>/`, with the same entries and modes: folders,
`bin/framecine-engine`, `*.sh` and the whisper programs 755, everything else 644, owner 0/0. The zip is made on
"Unix" with the modes in each entry's `external_attr`, so `unzip`, Python's `zipfile` and Frame Control apply them.
Frame Control and FrameDrop step into the one top folder; the launch file is `run.sh` (no space in the name).

| In the package | What it is |
|---|---|
| `bin/framecine-engine` | The engine fork, renamed. `VERSION` gives its build name, source branch and revision, and SHA-256. |
| `app/` | The project as committed in `HEAD` (LF line ends from any PC), without `app/tests`, `app/docs` and `app/tools`. |
| `run.sh` | The launcher. Arguments after it go to the app (`./run.sh --file=/path/film.mkv`). |
| `whisper/` | `whisper-server` (speech to text, CPU build) and `BUILDINFO`; `models/` is empty unless `--whisper-model STEM` (the player is to download the model on first use, `docs/framedrop.md`). `--no-whisper` leaves the folder out; `--whisper-bench` adds the benchmark kit and every model. |
| `framecine.desktop.in` | The menu entry. The installer puts in the install folder. |
| `icon.svg` | A neutral icon (a screen with a play mark). |
| `tools/steam_shortcuts.py` | The library shortcut helper, for `--steam`. |
| `LICENSES/` | This app (MIT), the engine (MIT and its COPYRIGHT notices), FFmpeg (LGPL-2.1), dav1d (BSD-2-Clause), libsmb2 (LGPL-2.1), whisper.cpp and the models (MIT), the controller models (CC BY-NC-SA 4.0), the room textures (CC0), and `THIRD-PARTY.md`. |
| `README.txt`, `VERSION` | Install notes; `version`, `arch`, `engine`, `engine_sha256`, `engine_build_sha256`, `engine_source`, `app_commit`, `whisper`, one per line (the first line is always `version <V>`). |

**Build paths.** FFmpeg's and ggml's asserts keep their source paths (`__FILE__`), so a build in `/home/<name>/src`
carries the builder's user name. `tools/neutralise_paths.py` replaces the name in `/home/<name>/` and
`C:\Users\<name>\` in each packaged binary by a neutral one of the same length (`build`, cut or padded), so no
offset moves. `engine_build_sha256` is the hash of the engine as built, `engine_sha256` as packaged. The lasting fix
is `-ffile-prefix-map` in the build scripts (not done yet).

### Why the app is a folder and not a PCK

The engine builds in `build/out` are `template_debug` builds with path overrides on, so `--path app` runs the project
folder as is. That is the recipe every device test so far used. A PCK export needs an editor build of the fork,
which we do not build for arm64, and it adds a step that can differ from what was tested. The folder needs no
`.godot` import cache: the app loads its assets at run time. The engine prints "Could not load global script cache"
once at start. That is harmless.

### The launcher

`run.sh` is the known-good launch line from `app/README.md`:

```
DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/$(id -u) bin/framecine-engine --path app --display-driver x11 --xr-mode on -- <app arguments>
```

It keeps `DISPLAY` and `XDG_RUNTIME_DIR` when they are already set (as in the desktop session). The log goes to
`~/.local/state/framecine/last.log`. The log of the run before is `previous.log`.

### Licences

- The app is MIT. The engine is the Godot engine (MIT) with our video module, plus the third-party notices in
  `engine-COPYRIGHT.txt`.
- FFmpeg and libsmb2 are linked statically under the LGPL-2.1. FFmpeg is configured without `--enable-gpl` and
  without `--enable-nonfree`. `THIRD-PARTY.md` gives the versions, the sources and the build scripts, so that a user
  can relink with a changed library.
- dav1d (the AV1 decoder, from VideoLAN) is linked statically under the BSD-2-Clause licence; its notice is
  `LICENSES/dav1d-BSD-2-Clause.txt` and its row in `THIRD-PARTY.md`. The decoders are open source; no codec licence
  fees are paid (`docs/decisions.md` D18).
- The controller models are CC BY-NC-SA 4.0, which is non-commercial. A commercial release must replace them.

## Releases

A release is one command on the Windows PC that has the signing key, from Git Bash:

```
tools/release.sh 0.1.0-test                        # a trial: build and check everything, publish nothing
tools/release.sh 0.1.0                             # the same for the real version: prints what it would publish
tools/release.sh 0.1.0 --publish --notes "One line for the update prompt."   # only after the user agrees
```

Versions are `MAJOR.MINOR.PATCH`; the tag is `v<version>`. A `-suffix` is accepted only without `--publish`.

**Before it builds,** it refuses: changes to tracked files or new files in `app/`, `pc/` or `tools/`; any hit from
`tools/privacy-check.sh`; no signing key, or an `app/update/release-key.pub.pem` that is not committed or not the
key's public half. With `--publish` also: `gh` not logged in, `HEAD` not on `origin/main` (push main first), or the
tag or the release already on GitHub.

**It builds** `tools/package.sh --version V --zip` with the PC-windows engine
(`godot.linuxbsd.template_debug.arm64.PLAYER_PCWIN` in `build/out`; `--engine` for another) and no speech model
(`--whisper-model STEM` to put one in), and the PC windows app with `pc\build.cmd clean` (a Release build with its
unit tests). `--pc-zip PATH` takes a zip made elsewhere instead; `--no-pc` leaves it out.

**It checks** the packages: `tools/privacy-check.sh --archive` over every entry's name and contents (the tarball, the
zip and the PC zip), the tarball and the zip alike (names, modes, sizes), one top folder, `run.sh` and the engine 755,
the engine an arm64 ELF, `VERSION` the version, the PC zip's files. Third-party text that a private pattern happens
to match (a name in the engine's credits) goes in `~/.config/vrvp/private-allow`, which is never in the repository.

**It writes** `build/dist/release-<version>/`:

| File | What |
|---|---|
| `framecine-<V>-arm64.tar.gz` | The package. The player's updater downloads this one. |
| `framecine-<V>-arm64.zip` | The same files, for Frame Control and FrameDrop. |
| `framecine-pc-<V>-windows-x64.zip` | `framecine-pc-<V>-windows-x64/`: `pc-windows.exe` (build paths neutralised), `README.txt` (from `tools/release-pc-readme.txt`), `LICENSES/` (this project's MIT, and `THIRD-PARTY.txt` for C++/WinRT and the static MSVC runtime). |
| `latest.json`, `latest.json.sig` | The update file (below) and its signature. |
| `install-manifest.json` | For Frame Control and FrameDrop (below). |
| `SHA256SUMS` | Every file above, `sha256sum` format. |
| `release-notes.md` | The release's text: the notes line, the files, the commit, the key's fingerprint. |

**With `--publish`** it tags `HEAD` (`git tag -a v<V>`), pushes the tag, creates the release as a draft with every
file, then publishes it as the latest release (so no player sees a `latest.json` before its package is there), and
checks that `releases/latest/download/latest.json` is the new file byte for byte. Without `--publish` it prints those
exact commands. The release is a normal release, not a pre-release: GitHub's `releases/latest` skips drafts and
pre-releases, and the updater reads `releases/latest/download/latest.json`.

### The update file: `latest.json` and its signature

The contract with the player's updater (`docs/framedrop.md`, "Our own updates"). UTF-8 without a BOM, LF, written
once and signed byte for byte as written:

```json
{
  "version": "0.1.0",
  "tag": "v0.1.0",
  "package": {
    "url": "https://github.com/stringandstickytape/FrameCine/releases/download/v0.1.0/framecine-0.1.0-arm64.tar.gz",
    "size": 98123456,
    "sha256": "<64 lowercase hex>"
  },
  "notes": "One line for the update prompt."
}
```

`latest.json.sig` is the raw RSA PKCS#1 v1.5 signature over the SHA-256 of `latest.json`'s bytes
(`openssl dgst -sha256 -sign`). The player checks it with `Crypto.verify(HashingContext.HASH_SHA256, sha256, sig,
key)`, the key loaded from `app/update/release-key.pub.pem` (`CryptoKey.load(path, true)`). `release.sh` verifies the
signature with that file before it finishes. The tarball unpacks to one folder, `framecine-<V>-arm64/`.

### The signing key

`tools/release-key.sh` made it (2026-11-09): RSA-3072, the private key in `~/.config/vrvp-release/release-key.pem`
(Windows: `%USERPROFILE%\.config\vrvp-release\`), owner-only (mode 600 and an ACL for the user alone), never in the
repository and never printed; the public key in `app/update/release-key.pub.pem` (committed). `tools/release-key.sh
--check` checks the pair. **Keep an offline copy of the private key**: without it no later release can be signed,
and the players installed refuse a `latest.json` signed with another key. To change the key, ship the new public key
in a release signed with the old one.

### The install manifest

`install-manifest.json` serves both Frame Control and FrameDrop:

```json
{
  "schema": "framedrop.install/v1",
  "name": "FrameCine",
  "files": [ { "url": "https://github.com/stringandstickytape/FrameCine/releases/download/v0.1.0/framecine-0.1.0-arm64.zip",
               "sha256": "<sha256 of the zip>", "size": 98234567, "exe": "run.sh" } ]
}
```

`size` and `exe` are Frame Control's extensions (FrameDrop ignores them). In Frame Control (`docs/web-install.md` and
`ui/frame_titles.py` there, read 2026-11-09) `exe` is a path relative to the title's root after it has stepped into
the zip's one top folder; a path that starts with that folder works too. So `run.sh`. Frame Control names the title
folder from `name`: `~/devkit-game/VR_Video_Player/`. Its rules: HTTPS, public hosts, at most 5 redirects, at most
4 GiB, the sha256 and size checked. The links (in `docs/install.md`) point at
`releases/latest/download/install-manifest.json`, so they always install the newest release.

### Cutting v0.1.0

1. Merge the release work into main (the updater, `run.sh`, this tooling), commit, and push main
   (`tools/privacy-check.sh` first, or the pre-push hook from `tools/pre-push.sample`).
2. `tools/release.sh 0.1.0-test`: the trial. Install its zip on the headset (Frame Control, or `FRAME_HOST`
   with `tools/install-on-frame.sh`) and play a file.
3. `tools/release.sh 0.1.0 --notes "First release."`: read what it would publish.
4. With the user's agreement: `tools/release.sh 0.1.0 --publish --notes "First release."`.

## Install on the headset

```
tools/install-on-frame.sh                          # the newest arm64 tarball in build/dist
tools/install-on-frame.sh build/dist/framecine-0.4.0-arm64.tar.gz --steam
tools/install-on-frame.sh --uninstall [--steam]
```

`FRAME_HOST` names the ssh host (default `frame`, as for `tools/push-app.sh`). `FRAME_HOST=local` runs the same
steps on this machine, for a test in WSL. The script sends the tarball over ssh (no `scp`), then runs one remote
script with `bash -s`, so no quoting goes through PowerShell.

On the headset it:

1. unpacks into a temporary folder next to the install folder (default `~/framecine`);
2. runs the engine with `--version` and stops, with nothing changed, if it does not start (wrong architecture or a
   missing library);
3. moves the old install to `~/framecine.old` (one level) and puts the new one in its place;
4. writes `~/.local/share/applications/framecine.desktop`, and a copy on `~/Desktop` if that folder exists;
5. with `--steam`, adds the library shortcut (below).

Settings (`~/.local/share/godot/app_userdata/FrameCine/`) and logs are outside the install folder, so an update
keeps them, and so does `--uninstall`.

### The sudo-free path

Everything the player needs is in the user's home folder:

| Path | What |
|---|---|
| `~/framecine/` | The engine, the app, the launcher |
| `~/.local/share/applications/framecine.desktop` | The menu entry (and the copy on `~/Desktop`) |
| `~/.local/share/godot/app_userdata/FrameCine/` | Settings, recents, bookmarks |
| `~/.local/state/framecine/` | Logs |
| `~/.local/share/Steam/userdata/<id>/config/shortcuts.vdf` | Only with `--steam`; backed up first |

The root file system of SteamOS is read-only and updates replace it. Nothing here writes to it, so a system update
does not remove the player. No part of the player needs root: 10-bit video plays in hardware on the stock driver
(`docs/decisions.md` D21).

The user must be able to read the video hardware (`/dev/video*`, group `video`) and the GPU, as for every earlier
device test. The default user can.

## The Steam library shortcut (`--steam`, untested on the device)

`tools/steam_shortcuts.py` adds, updates or removes a "non-Steam" entry in each Steam user's
`userdata/<id>/config/shortcuts.vdf`, under `~/.local/share/Steam` and `~/.steam/steam`. It runs on the headset with
the standard library of Python 3.

```
python3 ~/framecine/tools/steam_shortcuts.py --list
python3 ~/framecine/tools/steam_shortcuts.py --add --exe ~/framecine/run.sh --dry-run
```

- **Backup.** Before each write it copies the file to `shortcuts.vdf.bak-<date-time>`. It writes to a temporary file
  and renames it, and it parses what it wrote before the rename.
- **Update, not duplicate.** An entry with the same `Exe` is replaced in its slot, and keeps its `appid`, so library
  art stays.
- **Steam must be restarted.** Steam reads the file at start, and it can write it back when it quits. Restart Steam
  after the change; if the shortcut does not show, close Steam, run the command again, then start Steam.
- **VR flag.** `--openvr` marks the entry as a VR app. It is off by default, because the player starts its own
  OpenXR session. Whether the flag helps on the headset is an open question for the device test.

### The file format

The file is binary KeyValues. Each item is a type byte, a NUL-terminated key, then the value:

| Byte | Type | Value |
|---|---|---|
| `0x00` | map | items, then `0x08` |
| `0x01` | string | NUL-terminated UTF-8 |
| `0x02` | int32 | 4 bytes, little-endian |
| `0x03` | float32 | 4 bytes |
| `0x07` | uint64 | 8 bytes |
| `0x0A` | int64 | 8 bytes |
| `0x08` | end of map | |

The root map `shortcuts` holds maps keyed `"0"`, `"1"`, and so on. A read-only check of a current desktop Steam
client's file (a copy, parsed in the scratch folder and then deleted) found these keys, in this order:

`appid` (int32), `AppName`, `Exe` (quoted path), `StartDir` (quoted), `icon`, `ShortcutPath`, `LaunchOptions`,
`IsHidden`, `AllowDesktopConfig`, `AllowOverlay`, `OpenVR`, `Devkit`, `DevkitGameID`, `DevkitOverrideAppID`,
`LastPlayTime`, `FlatpakAppID`, `sortas`, `tags` (map).

The parser wrote that file back byte for byte. Older files use `appname` in lower case; the helper reads both. Steam
gives a shortcut it makes itself an id of its own. The helper uses the id that other tools use: the CRC-32 of the
quoted exe and the name, with the top bit set. `tools/test_steam_shortcuts.py` tests the round trip, all value
types, add, update, remove, renumbering, the backup and `--dry-run` on synthetic files.

To check on the device (read-only): `python3 ~/framecine/tools/steam_shortcuts.py --list`.
