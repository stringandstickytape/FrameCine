# Packaging and installing without a store

`tools/package.sh` builds a release tarball. `tools/install-on-frame.sh` copies it to the headset over ssh and adds a
menu entry for the desktop session. Neither needs root on the headset. Compatible with Steam Frame (SteamOS); an
optional shortcut in the Steam library is behind `--steam`.

**Not yet tested on the device.** The packaging, the install, the update and the uninstall are tested in WSL
(x86_64 build, a fake home folder, a fake Steam user folder). See the morning checklist, section "Packaging".

## Build a tarball

```
tools/package.sh                                   # arm64, the newest engine in build/out
tools/package.sh --engine godot.linuxbsd.template_debug.arm64.PLAYER_HDR --version 0.4.0
tools/package.sh --arch x86_64                     # a desktop Linux build (the WSL fork build)
```

The result is `build/dist/vr-video-player-<version>-<arch>.tar.gz` (about 38 MB). The version defaults to
`git describe`. Run it from Git Bash or WSL. It needs Python 3 (to write the archive with the right file modes) and
the WSL build tree at `~/src` for the licence files and the x86_64 engine. In a linked git worktree it takes the
engine from the main checkout's `build/out`.

| In the tarball | What it is |
|---|---|
| `bin/vr-video-player-engine` | The engine fork, renamed. `VERSION` gives its build name and SHA-256. |
| `app/` | The project as committed in `HEAD`, without `app/tests`, `app/docs` and `app/tools`. |
| `run.sh` | The launcher. Arguments after it go to the app (`./run.sh --file=/path/film.mkv`). |
| `vr-video-player.desktop.in` | The menu entry. The installer puts in the install folder. |
| `icon.svg` | A neutral icon (a screen with a play mark). |
| `tools/steam_shortcuts.py` | The library shortcut helper, for `--steam`. |
| `LICENSES/` | This app (MIT), the engine (MIT and its COPYRIGHT notices), FFmpeg (LGPL-2.1), dav1d (BSD-2-Clause), libsmb2 (LGPL-2.1), the controller models (CC BY-NC-SA 4.0), and `THIRD-PARTY.md`. |
| `README.txt`, `VERSION` | Install notes; version, architecture, engine name and hash, app commit. |

### Why the app is a folder and not a PCK

The engine builds in `build/out` are `template_debug` builds with path overrides on, so `--path app` runs the project
folder as is. That is the recipe every device test so far used. A PCK export needs an editor build of the fork,
which we do not build for arm64, and it adds a step that can differ from what was tested. The folder needs no
`.godot` import cache: the app loads its assets at run time. The engine prints "Could not load global script cache"
once at start. That is harmless.

### The launcher

`run.sh` is the known-good launch line from `app/README.md`:

```
DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/$(id -u) bin/vr-video-player-engine --path app --display-driver x11 --xr-mode on -- <app arguments>
```

It keeps `DISPLAY` and `XDG_RUNTIME_DIR` when they are already set (as in the desktop session). The log goes to
`~/.local/state/vr-video-player/last.log`. The log of the run before is `previous.log`.

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

## Install on the headset

```
tools/install-on-frame.sh                          # the newest arm64 tarball in build/dist
tools/install-on-frame.sh build/dist/vr-video-player-0.4.0-arm64.tar.gz --steam
tools/install-on-frame.sh --uninstall [--steam]
```

`FRAME_HOST` names the ssh host (default `frame`, as for `tools/push-app.sh`). `FRAME_HOST=local` runs the same
steps on this machine, for a test in WSL. The script sends the tarball over ssh (no `scp`), then runs one remote
script with `bash -s`, so no quoting goes through PowerShell.

On the headset it:

1. unpacks into a temporary folder next to the install folder (default `~/vr-video-player`);
2. runs the engine with `--version` and stops, with nothing changed, if it does not start (wrong architecture or a
   missing library);
3. moves the old install to `~/vr-video-player.old` (one level) and puts the new one in its place;
4. writes `~/.local/share/applications/vr-video-player.desktop`, and a copy on `~/Desktop` if that folder exists;
5. with `--steam`, adds the library shortcut (below).

Settings (`~/.local/share/godot/app_userdata/VR Video Player/`) and logs are outside the install folder, so an update
keeps them, and so does `--uninstall`.

### The sudo-free path

Everything the player needs is in the user's home folder:

| Path | What |
|---|---|
| `~/vr-video-player/` | The engine, the app, the launcher |
| `~/.local/share/applications/vr-video-player.desktop` | The menu entry (and the copy on `~/Desktop`) |
| `~/.local/share/godot/app_userdata/VR Video Player/` | Settings, recents, bookmarks |
| `~/.local/state/vr-video-player/` | Logs |
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
python3 ~/vr-video-player/tools/steam_shortcuts.py --list
python3 ~/vr-video-player/tools/steam_shortcuts.py --add --exe ~/vr-video-player/run.sh --dry-run
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

To check on the device (read-only): `python3 ~/vr-video-player/tools/steam_shortcuts.py --list`.
