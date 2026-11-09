# FrameCine

A free VR video player for the Steam Frame, cinema first: your films on a big screen in a real room, with
spatial sound. It plays files on the headset and on your PC or NAS, flat or 3D, and 180 and 360 video too.

[![Latest release](https://img.shields.io/github/v/release/stringandstickytape/FrameCine?style=flat&label=release)](https://github.com/stringandstickytape/FrameCine/releases/latest)
[![Licence: MIT](https://img.shields.io/badge/licence-MIT-blue?style=flat)](LICENSE)

<p align="center">
  <a href="https://stringandstickytape.github.io/FrameCine/frame-control.html"><img src="docs/images/install-frame-control.svg" alt="Install with Frame Control" width="260"></a>
  <!-- FrameDrop's install link names a GitHub download after the storage address's ID, not the file, and refuses it
       (tested 2026-11-10). Back once FrameDrop is fixed:
  <a href="https://framedropvr.com/install?manifest=https%3A%2F%2Fgithub.com%2Fstringandstickytape%2FFrameCine%2Freleases%2Flatest%2Fdownload%2Finstall-manifest.json"><img src="docs/images/install-framedrop.svg" alt="Install with FrameDrop" width="260"></a>
  -->
</p>

> **No AI unless you ask for it.** FrameCine has no AI of its own. Its AI assistant features do nothing until you
> install Claude Code or Codex yourself (on the headset or on a PC) and turn them on; the assistant service is off
> by default. Voice typing uses speech recognition that runs on the headset, offline; your voice leaves the headset
> only if you pair an AI assistant and speak to it.
> (The menu translations other than English were made with AI, and say so.)

## What it does

- **Rooms to watch in.** Cinemas from several eras, a screening room, a drive-in, a planetarium, a home theatre,
  outdoor terraces and stranger places, or your own room through the cameras. The room's light follows the film.
- **Sound that stays put.** Spatial audio on by default: the sound comes from the screen and the room's speakers,
  and stays there when you turn your head. Each room sounds like itself (its echo can be turned down).
- **Every kind of video.** Flat, side-by-side and top-bottom 3D, 180 and 360 (also fisheye and dual fisheye),
  HEVC up to 8K and 10-bit HDR in hardware, MKV, MP4, TS, AVI and WebM, with subtitles, chapters,
  resume, playlists and live streams.
- **Your library where it is.** Files on the headset, shares on your PC or NAS (SMB), and media servers on your
  network (UPnP/DLNA). Nothing is uploaded anywhere.
- **Your PC's windows in the headset** (optional): a small Windows app sends a window or a whole screen to the
  headset, and a mouse and keyboard paired with the headset use it.
- **Updates itself** from this page's releases, and asks before it installs one.

## Install

You need a Steam Frame and, once, a PC on the same network.

1. **On the headset:** Steam Settings > System > turn on **Developer Mode**.
2. **On the PC:** install [Frame Control](https://github.com/saphid/frame-control) (Windows, macOS, Linux; open
   source) or [FrameDrop](https://framedropvr.com/) (Windows), start it, and pair the headset with it (on the
   headset: Settings > Developer > **Pair new host**).
3. **Press the button above** on the PC (Frame Control asks before it installs), or download
   `framecine-<version>-arm64.zip` from the [latest release](https://github.com/stringandstickytape/FrameCine/releases/latest)
   and drop it on Frame Control or FrameDrop.
   > **FrameDrop:** its one-click install links can't download from GitHub at the moment (it names the download
   > after GitHub's storage ID instead of the file, then refuses it), so it has no button here yet. Dropping the
   > downloaded zip on FrameDrop is the way meanwhile.
4. **On the headset:** FrameCine is in the Steam library under **Non-Steam**. The first start shows a short
   introduction: eye calibration, the controls, and a one-time download of the speech model for voice typing.

After that it updates itself; the PC program isn't needed again. [docs/install.md](docs/install.md) has the details,
installing over ssh, how updates work, and how to uninstall.

### Your PC's windows in the headset (optional)

Download `framecine-pc-<version>-windows-x64.zip` from the [latest release](https://github.com/stringandstickytape/FrameCine/releases/latest),
unzip it and run `pc-windows.exe`. It sits in the tray and pairs with the headset once; then choose a window or a
screen from the headset's menu. [docs/install.md](docs/install.md#pc-windows-your-pcs-windows-in-the-headset) has
the pairing, privacy and how to stop it.

## Documentation

| Page | What |
|---|---|
| [`docs/install.md`](docs/install.md) | Installing, updating, uninstalling; the PC windows app |
| [`docs/USAGE.md`](docs/USAGE.md) | Every setting, the controls, command-line flags, the PC tools |
| [`docs/features.md`](docs/features.md) | The playback features, one section each |
| [`docs/environments.md`](docs/environments.md) | The rooms |
| [`docs/assistant.md`](docs/assistant.md) | The optional AI assistant link (off by default) |

## For developers

The player is a project for our fork of the Godot engine (OpenXR, hardware video decode through V4L2, FFmpeg for
containers and audio). [`docs/dev/architecture.md`](docs/dev/architecture.md) has the stack, the constraints, the
repository's layout and the results behind each part; [`docs/BUILD.md`](docs/BUILD.md) builds the engine;
[`docs/packaging.md`](docs/packaging.md) makes a release; [`docs/dev/README.md`](docs/dev/README.md) has the tools
for working on the app in the headset; [`app/README.md`](app/README.md) the app's structure and its tests.

## Licences

- The controller models in `app/models/controllers/` are derived from Valve Corporation's Steam Frame controller CAD
  and are under their own licence, CC BY-NC-SA 4.0 (non-commercial, share-alike; no endorsement by Valve implied):
  see `app/models/controllers/LICENSE-controller.md`. The rest of the repository is not covered by it.
- The room textures in `app/materials/` are CC0 1.0 (public domain), from Poly Haven and ambientCG: each one's source
  and author are in `app/materials/CREDITS.md` (`docs/materials.md`).
- FFmpeg and libsmb2 are linked statically under the LGPL-2.1, and dav1d (AV1) under the BSD-2-Clause licence: see
  `docs/BUILD.md` and `docs/packaging.md`.
- Everything else in this repository is MIT (`LICENSE`).
