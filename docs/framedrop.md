# FrameDrop: can the player install through it?

Research notes, 2026-11-05. Not yet tested on the device.

## What FrameDrop is

FrameDrop is a free Windows program from an independent XR developer (CadeXR) that sideloads software onto the
Steam Frame from a PC. Valve did not make it, and Valve has published no statement about it. Website:
<https://framedropvr.com/>. The version seen was 1.0.37 (Windows installer only; a Linux version is planned, a Mac
version is "possibly" planned).

It accepts three types of payload:

| Payload | Runtime on the headset | Notes |
|---|---|---|
| Android APK | Lepton (Android 11, API 30) | Must be `arm64-v8a` or a universal APK that includes it. VR (OpenXR) and flat modes. |
| Linux build (zip or folder) | Steam Linux Runtime 4.0 ARM64 | ARM64 runs natively; x86_64 maps to SLR 4.0 and needs translation. |
| Windows `.exe` | Proton | ARM64 Proton must already be installed on the headset. |

## How it works

- It uses Valve's SteamOS Devkit path and the same tools as the SteamOS Devkit Client: it pairs through the Devkit
  service, then copies with SSH and rsync.
- The headset must be in Developer Mode. Pairing is done once: on the headset, Settings > Developer > Pair new host,
  then Pair in FrameDrop.
- When the user drops a file, FrameDrop finds the runtime that the title needs, writes the start command and
  launch arguments, and registers the title as a Devkit Game in Steam. The user starts it from the Steam library.
- Zips are unpacked **on the PC** before the copy. One wrapper folder in the zip is permitted.
- The PC and the headset must be on the same network. The headset's IP address can be typed in if its name does not
  resolve.

## The install button for developers

A developer can put an "Install with FrameDrop" link on a web page. The link opens FrameDrop on the visitor's PC
(Windows registers `framedrop://` the first time FrameDrop runs). If FrameDrop is not installed, the link goes to the
FrameDrop site. FrameDrop asks the user to confirm before it installs. The visitor must have paired a headset before.

- With a manifest: `https://framedropvr.com/install?manifest=<URL-encoded manifest URL>`
- With a file only: `https://framedropvr.com/install?url=<file URL>`

Manifest:

```json
{
  "schema": "framedrop.install/v1",
  "name": "VR Video Player",
  "files": [ { "url": "https://github.com/<owner>/<repo>/releases/download/<tag>/vr-video-player-<version>-arm64.zip",
               "sha256": "<sha256 of the zip>" } ]
}
```

- `name` is the title that shows in Steam. `sha256` is optional.
- Any static host is permitted, for example GitHub Releases.
- HTTPS is necessary (HTTP only from `localhost`, for tests). The URL must end in a file name. `file://` URLs, LAN
  addresses and credentials in the URL are not permitted.

## Fit with this project

### What fits now

- `tools/package.sh` already makes an ARM64 Linux folder with one launcher, `run.sh`. Only the outer format is
  different (`.tar.gz`, not `.zip`).
- A manifest on GitHub Releases agrees with the plan that the player is free and is all on GitHub (no store).
- Users would not need the ssh setup that `tools/install-on-frame.sh` needs.

### Changes that are necessary

1. **A zip output in `tools/package.sh`** (for example `--zip`). Write it with Python `zipfile` and set the Unix
   mode of each entry in `external_attr`, with the same rules as the tarball (folders, the engine, `*.sh` and the
   whisper programs 755; other files 644). FrameDrop unzips on Windows, so the execute bit can be lost. Its
   troubleshooting page says: if a Linux build does not start, the launch file needs execute permission.
2. **No spaces in the launch file name.** FrameDrop's troubleshooting page says that a space in the name makes Steam
   fail to find the launch file. `run.sh` has no space.
3. **A manifest and a link** in the release and the README, if the test (below) passes.

### Unknowns (test on the device)

1. **Which file FrameDrop launches.** Its documents do not say how it selects the launch file when the folder has more
   than one executable. Our package has `run.sh`, `bin/vr-video-player-engine`, `whisper/whisper-server` and
   `tools/steam_shortcuts.py`. If it selects the wrong file, a change to the package layout or names may correct it
   (not confirmed).
2. **The runtime container (the largest risk).** FrameDrop runs ARM64 Linux builds in Steam Linux Runtime 4.0
   (Debian 13). At present `run.sh` runs outside a container, in the headset session (`DISPLAY=:0`, the X11 display
   driver, the host libraries). In the container, find out:
   - Does the hardware decoder (`/dev/video-dec0`) open? This is question 6 in `docs/research-device.md`.
   - Does the engine start? It is built with Ubuntu's aarch64 cross toolchain. Its glibc must not be newer than the
     container's glibc. This is probably correct, but it is not confirmed.
   - Do OpenXR, passthrough and audio work as they do now?
   - Does each part of the app that uses `sudo` or system services still work? `sudo` is probably not available
     in the container.
   - Network access (SMB, LAN servers, the assistant link), the home folder and the `whisper-server` child process
     usually work in the container. Confirm them.
3. **Where the files go and how updates work.** FrameDrop's documents do not say where Devkit Games are put on the
   headset, or what happens when a second version is installed. Settings and the log are in
   `~/.local/share/godot/app_userdata/VR Video Player/` and `~/.local/state/vr-video-player/`, outside the install
   folder, so they should stay after an update.

## Test plan

1. Add `--zip` to `tools/package.sh` and make a zip.
2. On the PC: drop the zip onto FrameDrop and install it (one manual step, on the developer side only).
3. On the headset (over ssh): read the Devkit Game entry to see the start command and the runtime that FrameDrop
   selected. Read `~/.local/state/vr-video-player/last.log` after a launch from Steam.
4. Play an HEVC file and an AV1 file. Confirm hardware decode, XR, passthrough, audio and the assistant link.
5. Result:
   - If all of it works: publish the zip and the manifest with each release, and add the link to the README.
   - If decode or XR fails in the container: do not use FrameDrop. `tools/install-on-frame.sh` stays the install
     path. Record the result in `docs/decisions.md` and answer question 6 in `docs/research-device.md`.

## Sources

- FrameDrop, About (Devkit path, runtimes, troubleshooting): <https://framedropvr.com/about>
- FrameDrop, Docs (manifest, hosting, install link): <https://framedropvr.com/docs>
- FrameDrop, How to use (pairing, zips, Steam shortcut): <https://framedropvr.com/how-to>
- PC Guide, FrameDrop launch: <https://www.pcguide.com/news/steam-frame-sideloader-is-already-available-as-xr-developer-launches-easy-to-pair-and-use-framedrop/>
- Steam Deck HQ, FrameDrop announced: <https://steamdeckhq.com/framedrop-sideloader-announced/>
- This repository: `tools/package.sh`, `tools/install-on-frame.sh`, `docs/packaging.md`, `docs/research-device.md`
  (section 4 and question 6)
