# Building the player

The player is our fork of the Godot engine (4.7) with a video module, `modules/hwvideo`, plus the app in `app/`. The
app is scripts and data only, so only the engine is compiled. It is cross-compiled for the headset (Linux arm64) and
built natively for the desktop tests (Linux x86_64), both in WSL (Ubuntu 24.04) on a Windows PC.

To ship a build, see `docs/packaging.md`. To run it, see `docs/USAGE.md`.

## Overview

| Step | Script | Output | Time |
|---|---|---|---|
| 1. Toolchain, once (sudo) | `build/wsl-setup-arm64.sh` | the aarch64 cross compiler, scons, qemu | minutes |
| 2a. dav1d (AV1), once per architecture | `build/dav1d-build.sh [aarch64\|x86_64\|all]` | `~/src/dav1d-aarch64`, `~/src/dav1d-x86_64` | under a minute |
| 2b. FFmpeg, once per architecture | `build/ffmpeg-build.sh [aarch64\|x86_64\|all\|tool]` | `~/src/ffmpeg-aarch64-all`, `~/src/ffmpeg-x86_64-all` (`PROFILE=minimal`: `~/src/ffmpeg-<arch>`, for branch `frame/player`) | about 1 min each |
| 3. libsmb2, once per architecture | `build/libsmb2-build.sh [aarch64\|x86_64\|all]` | `~/src/libsmb2-aarch64`, `~/src/libsmb2-x86_64` | seconds |
| 4. The player engine | `build/build-player.sh [arm64\|x86_64]` | `~/src/godot-player/bin/godot.linuxbsd.template_debug.<arch>` | 7 min clean, 1 min incremental |
| 5. Speech to text (whisper.cpp, a separate program; `build/whisper/README.md`) | `build/whisper-build.sh [aarch64\|aarch64-vulkan\|x86_64\|all]`, then `build/whisper-models.sh` | `build/out/whisper/<target>/`, `build/out/whisper-models/` | about 1 min per CPU target, 5 min for Vulkan; 670 MB of models |
| (The plain engine, for the early spikes) | `build/build-frame.sh [template_debug\|template_release\|editor]` | `~/src/godot-frame/bin/...`, copied to `build/out/` | about 7 min |

Every script runs from Windows through `wsl -d Ubuntu -- bash build/<script>` and keeps its sources on the WSL file
system (`~/src`), which is much faster than `/mnt/c`. Times are for a 30-core PC. Nothing in `~/src` is committed to
this repository.

## 1. The toolchain

From a real terminal, because sudo asks for a password:

```
wsl -d Ubuntu -- sudo bash build/wsl-setup-arm64.sh
```

It installs:

- the aarch64 GCC cross toolchain (`crossbuild-essential-arm64`, GCC 13);
- arm64 as a foreign dpkg architecture, with the Ubuntu ports mirror as its source;
- `qemu-user-static` and binfmt, to smoke-run arm64 binaries;
- `scons`, `pkg-config`, and Python's pip and venv.

The engine opens X11, Wayland, ALSA, PulseAudio, udev and D-Bus at run time (`use_sowrap=yes`), so no arm64 X11
packages are needed. The binary needs a glibc no newer than the headset's, which current SteamOS has. For a release
built for many systems, use the engine's buildroot SDK instead (`docs/research-godot.md`, section 6).

## 2. dav1d and FFmpeg

```
wsl -d Ubuntu -- bash build/dav1d-build.sh all
wsl -d Ubuntu -- bash build/ffmpeg-build.sh all
```

- **dav1d** (AV1, BSD-2-Clause): tag `1.5.4` into `~/src/dav1d`, built static with meson (a private venv in
  `~/src/meson-venv`), with its NEON assembly on aarch64 and plain C on x86_64.
- **FFmpeg source.** Tag `n8.1.3` into `~/src/ffmpeg`, once.
- **Configuration.** LGPL only: no `--enable-gpl`, no `--enable-nonfree`, and no external library but dav1d. The
  script stops if `CONFIG_GPL` or `CONFIG_NONFREE` is set. Static libraries:
  - every native decoder (video, audio, subtitles; 503 with dav1d), and libdav1d for AV1;
  - every file demuxer (348), without the network ones, the ones that open other files by name (concat, image2
    sequences, IMF, HLS, DASH) and the ones that need an external library;
  - all parsers and bitstream filters; libswscale and libswresample;
  - only the `file` protocol; no programs, no devices, no filters.
  - `build-config.txt` in the prefix records the licence switches and the counts.
- **Prefixes.** `~/src/ffmpeg-<arch>-all`. `PROFILE=minimal` builds the earlier set (H.264, HEVC and VP9 decoders, five
  containers, no swscale) into `~/src/ffmpeg-<arch>`, which branch `frame/player` links.
- **zlib** comes from the engine (`thirdparty/zlib` of `GODOT_SRC`, default `~/src/godot-player`), so the binary has
  one zlib.
- **x86_64** has no assembly, because WSL has no nasm. It is for tests only.
- **`tool`** builds a remux-only `ffmpeg` command into `~/src/ffmpeg-tool`, to make test files. It is not part of
  the player.

`modules/hwvideo/SCsub` (branch `frame/codecs`) picks `~/src/ffmpeg-<arch>-all` and `~/src/dav1d-<arch>` for the
build's architecture. Override them with `HWVIDEO_FFMPEG_PREFIX` and `HWVIDEO_DAV1D_PREFIX`.

## 3. libsmb2

```
wsl -d Ubuntu -- bash build/libsmb2-build.sh all
```

It clones tag `libsmb2-6.3.1` into `~/src/libsmb2` and applies `build/libsmb2-patches/*.patch` in order. The patch
makes SMB 3 signing use the CPU's AES instructions. Without it, signing cost about 9 ms of CPU per MiB read. The
client library is LGPL-2.1-or-later, and its DCE/RPC part is BSD-2. Override the prefix with `HWVIDEO_LIBSMB2_PREFIX`.

## 4. The player engine

```
wsl -d Ubuntu -- bash build/build-player.sh arm64      # the headset
wsl -d Ubuntu -- bash build/build-player.sh x86_64     # the desktop tests in WSL
```

- **Source.** `~/src/godot-player`, a worktree of the fork (`stringandstickytape/godot`) on branch `frame/player`.
  The fork came from tag `4.7.2-stable`. `build-frame.sh` builds branch `frame/4.7` (the engine patches without the
  video module) from `~/src/godot-frame`. Every codec in software (`docs/decisions.md` D18) is on branch
  `frame/codecs`, worktree `~/src/godot-player-codecs`: build it with
  `wsl -d Ubuntu -- bash -c 'SRC=~/src/godot-player-codecs bash build/build-player.sh arm64'`.
- **Options.** `target=template_debug`, `optimize=speed`, Vulkan only (no OpenGL), `use_sowrap=yes`, no Mono, and
  `disable_path_overrides=no`. The last one lets the binary run a project folder with `--path`, which is how the app
  runs (`docs/packaging.md`, "Why the app is a folder"). `OPT=none` gives a build for a debugger.
- **Log.** `~/godot-player-build-<arch>.log`.
- **Check without the device.** WSL's binfmt does not start qemu by itself, so call it:
  `qemu-aarch64-static ~/src/godot-player/bin/godot.linuxbsd.template_debug.arm64 --version`.

### The strict-aliasing bug (fixed in the fork)

Stock Godot 4.7, built for aarch64 with GCC 13 at `-O2`, draws no 3D geometry. The forward renderers'
`InstanceData` setters store `Vector3`, `Vector4` and `Rect2` values into `float[]` members through casts. That is
undefined behaviour under strict aliasing. GCC moves the copy of the struct into the instance buffer before those
stores, so every mesh gets garbage transforms. The fork stores the elements one by one. Full optimisation is safe
again. Details: `spikes/02-import/results/FINDINGS.md`.

The fork also fixes a crash at exit on Mesa: the Vulkan driver was unloaded while worker threads still used it. On a
stock engine, `VK_LOADER_DISABLE_DYNAMIC_LIBRARY_UNLOADING=1` avoids that crash.

If you build another engine branch, keep both fixes.

### Binary names

`build-player.sh` writes `bin/godot.linuxbsd.template_debug.<arch>`. Each build that goes to the headset is copied to
`build/out/` with a tag:

```
build/out/godot.linuxbsd.template_debug.arm64.PLAYER_<TAG>      e.g. PLAYER_SUBS, PLAYER_HDR
```

The tag names the milestone. `spikes/03-player/README.md` records the fork commit and the SHA-256 of each tagged
binary. `build/out/` is not in git. `tools/package.sh --engine <name>` picks a binary by its name, and the package
records the name and SHA-256 in `VERSION`.

### What is kept in build/out (pruned 2026-10-31)

Superseded builds go; `build/out/` keeps the newest cumulative build and one known-good baseline. Check a
copy with `sha256sum`.

| File | What | SHA-256 |
|---|---|---|
| `godot.linuxbsd.template_debug.arm64.PLAYER_FINAL2` | The newest cumulative build (fork `42175b2a3c`): everything of PLAYER_HDR (`015fc1857b`), PLAYER_INPUTS (`8ac5e35f43`: HTTP, HTTPS, live streams, music files), PLAYER_PICTURE (`c318810fdd`: letterbox detection, trick play), PLAYER_NEXT (`347778e84c`: next item on a second decoder session) and PLAYER_REQUESTS (`4b351c7722`: whole subtitle tracks, dual subtitles, audio without a player, field order, `MediaBrowser.read_file()`, the OpenXR extension list), plus software decode where there is no hardware decoder (`HWVIDEO_FORCE_SW=1` forces it; PLAYER_FINAL, `ccf591aa61`) and the release of never-waited WorkerThreadPool tasks before the script languages shut down (the abort at quit; `docs/decisions.md` D6). `tools/morning-deploy.sh` copies it by default. | `c2a645eaae8f40381098323452c375ed748ce15bae7d868d145ab3eeb41841fc` |
| `godot.linuxbsd.template_debug.arm64.PLAYER_VP9` | PLAYER_FINAL2 plus hardware VP9, one session at a time, with a switch to software on VP9 decoder faults, and the IVF demuxer (fork `49574b189c`; `spikes/03-player/README.md`, "Hardware VP9"). Not yet run on the headset: deploy it with `tools/morning-deploy.sh --engine godot.linuxbsd.template_debug.arm64.PLAYER_VP9` for checklist F, "Hardware VP9". | `2f0129b951f43831c78a04cd243717b22d23dfcbd2aba55a75c6a333618f3117` |
| `godot.linuxbsd.template_debug.arm64.PLAYER_Q10C` | PLAYER_VP9 plus 10-bit without P010 as Q10C through the GPU's YCbCr sampler (checked, else software), and VP9 superframes split before the decoder (fork `9e4cbcce7c`; `spikes/03-player/README.md`, "Q10C through a YCbCr sampler (2026-10-31)"). Not yet run on the headset: deploy it with `tools/morning-deploy.sh --engine godot.linuxbsd.template_debug.arm64.PLAYER_Q10C` for checklist F, "10-bit without P010". | `47aecf9f91afb812503eeb99f1962b7ca3eb95c114a2c2d1498e1e5456052d25` |
| `godot.linuxbsd.template_debug.arm64.PLAYER_LIBRARY` | PLAYER_CODECS with the x11window texture fix (fork `952e129cc6`), plus `MediaBrowser.open_read`, `read_next` and `close_read`, which `copy_to_library` needs for files over 64 MiB (fork `ea69564298`, branch `frame/library-copy`, `SRC=~/src/godot-library`; `docs/library.md`). The read is tested on local files; not yet run against a real SMB server. | `7481fe0ddef300cdbe716489990de012db28aae9fdc9028e964898c215ab8d6c` |
| `godot.linuxbsd.template_debug.arm64.PLAYER_STILLFIX` | PLAYER_LIBRARY plus sparse video: the decoder's feed doesn't pause while its pictures are behind the clock, and a seek stops waiting for its frame when audio blocks the video (fork `1ca40f1581`, branch `frame/still-seek`, `SRC=~/src/godot-library`). Tested on the desktop through a fake decoder (`app/tests/test_still_seek.gd`). | `8bfa5a4fe28d10a57ea97670ffd10c45b54eac2d920d0e65300da5483cba51ef` |
| `godot.linuxbsd.template_debug.arm64.PLAYER_ALL2` | The known-good baseline: the player with the window module (`frame/window-on-player`), as run on the device before the batch of features. | `c71ddbbbe246434774bbe0d54f6709bc701318053773f8d5195c2bfd0681b1cb` |

Superseded on 2026-10-31: PLAYER_10BIT, PLAYER_10BIT2, PLAYER_P010, PLAYER_FEATURES, PLAYER_FEATURES2, PLAYER_SUBS,
PLAYER_NIGHT, PLAYER_CHANNELS, PLAYER_HDR, PLAYER_INPUTS (`4c0dc455...`), PLAYER_PICTURE (`1a09db34...`), PLAYER_NEXT
(`8c839380...`), PLAYER_REQUESTS (`593117e9...`) and PLAYER_FINAL (`ef0f1726...`). They are
moved to `build/out/superseded/` (ignored by git), to be deleted with `rm -r build/out/superseded`. Each has its
fork commit in `spikes/03-player/README.md`, so any of them can be rebuilt with `build/build-player.sh`.

Older names:

- `godot.linuxbsd.<target>.arm64` from `build-frame.sh` is the engine without the video module. The early spikes used
  it.
- `PLAYER_ALL` builds include the window-capture module of the `frame/window` branch (`app/docs/window-source.md`).

## Tests without the device

| What | Command |
|---|---|
| The app's tests (any desktop engine 4.7) | see `app/README.md`, "Tests" |
| The module, headless, on real files | `wsl -d Ubuntu -- bash spikes/03-player/demux-test/run-tests.sh` |
| Small TS and subtitle test files | `wsl -d Ubuntu -- bash spikes/03-player/demux-test/make-test-files.sh` (after `ffmpeg-build.sh tool`) |
| Every software codec (clips, then real files from G:) | `wsl -d Ubuntu -- bash spikes/03-player/demux-test/make-codec-files.sh`, then `wsl -d Ubuntu -- bash spikes/03-player/demux-test/codecs-tests.sh` |
| SMB | `wsl -d Ubuntu -- bash spikes/03-player/demux-test/smb-tests.sh` (a share and credentials in `~/.config/frame-player/smb-test.env`, mode 600, never committed) |
| PC tools | `python tools/test_voice.py`, `python tools/test_steam_shortcuts.py` |

In WSL there is no GPU. For a run with a window, use xvfb and the lavapipe Vulkan driver:

```
VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a -s "-screen 0 1280x720x24" \
  ~/src/godot-player/bin/godot.linuxbsd.template_debug.x86_64 --path app --xr-mode off -- --no-xr --quit-after=120
```

## Licences of the build

dav1d is BSD-2-Clause (its notice goes with the package). FFmpeg and libsmb2 are linked statically under the
LGPL-2.1. Users must be able to relink with a changed library. The
fork's source and these scripts are public, so anyone can rebuild the engine. That should be enough, but confirm it
before a release, or switch to shared FFmpeg and libsmb2 libraries. `tools/package.sh` puts every licence and the
versions into the package (`docs/packaging.md`, "Licences").
