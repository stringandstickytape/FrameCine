# FrameCine

A free, standalone VR video player for the Steam Frame (SteamOS, ARM64, Snapdragon 8 Gen 3 / Adreno via Turnip).
Plays local and network video, flat / SBS / TB / 180 / 360 / fisheye / EAC, in selectable environments.

## Stack (decided)

- **Engine:** our Godot fork, patched directly (no GDExtension indirection). Mobile renderer (Vulkan).
- **XR:** OpenXR only. SteamVR on the Frame (2.19.0) exposes only projection and quad layers, no equirect/cylinder.
  So: 180/360/fisheye/EAC are meshes drawn in the projection layer; flat video and UI go in quad layers.
  Refresh rate is not switchable at runtime; it is set per package in `vrpreferences.json` (`preferMinRefreshRate`).
- **Decode:** hardware only for anything above 1080p. Our own V4L2 stateful M2M client against `/dev/video-dec0`
  (Valve's fork of Qualcomm's `iris` driver). FFmpeg demuxes and decodes audio, never video. Turnip has no Vulkan Video; FFmpeg `v4l2m2m`
  can't export dmabufs; GStreamer `v4l2videodec` crashes on the fork's SOURCE_CHANGE quirk. See `docs/research-device.md`.
- **Frame transport:** decoder → dmabuf → VkImage imported into RenderingDevice, **imported once per buffer and cached**
  (per-frame import oopses the 6.18 kernel). One shader does YUV→RGB, tone-map and projection.
- **Codec limits (confirmed on device, kernel 6.18, 2026-10-30 — see `spikes/01-decode/results/SUMMARY.md`):**
  HEVC 8-bit decodes 7680x3840 at 129 fps and 8192x4096 at 118 fps to NV12 (Q08C ~5% faster), bit-exact. 8K60 has ~2x headroom.
  HEVC 10-bit decodes to Q10C (UBWC), which the GPU reads through a YCbCr sampler (`docs/decisions.md` D14);
  mainline Linux 7.2 also offers P010. VP9 crashes firmware (per reports; not tested). AV1 not exposed. Two concurrent
  sessions work.
- **Containers and audio:** a static LGPL FFmpeg inside the engine module (`MediaSource`): MKV/WebM, MP4, TS, AVI;
  audio decoded and downmixed to stereo into an `AudioStreamMedia`, the master clock. Ambisonics via Steam Audio or
  libspatialaudio later.
- **Files:** local, or straight from a PC or NAS file share (`smb://host/share/file.mkv`, SMB2/3 through a static libsmb2
  with a readahead thread; `MediaBrowser` lists shares and folders).
- **Subtitles:** `MediaSource` delivers the events (text and ASS lines, or raw PGS/VobSub packets); libass → quad layer
  later.
- **Not supported:** DRM streaming, DVD/BD menus.

## Design constraints

Battery-powered, tile-based GPU, LCD panels. Memory bandwidth is the cost to watch, not FLOPs.
See the conversation notes in `docs/decisions.md` once written.

## Documentation

| Page | What |
|---|---|
| [`docs/USAGE.md`](docs/USAGE.md) | Running on a desktop and on the headset, every command-line flag, every setting, the controls, the PC tools |
| [`docs/BUILD.md`](docs/BUILD.md) | Building the engine fork for arm64 and x86_64: toolchain, FFmpeg, libsmb2, binary names |
| [`docs/packaging.md`](docs/packaging.md) | A release tarball, and installing it on the headset without root |
| [`docs/features.md`](docs/features.md) | The playback features, one section each |
| [`docs/ui-design.md`](docs/ui-design.md) | The pane: the interface carried by the left hand |
| [`docs/dev/control-protocol.md`](docs/dev/control-protocol.md) | The dev link: the headset connects out to a listener on a PC |
| [`app/README.md`](app/README.md) | The app's structure, controls in detail, and its tests |
| [`docs/decisions.md`](docs/decisions.md), `docs/research-*.md` | Why the stack is what it is |
| [`docs/morning-checklist.md`](docs/morning-checklist.md) | What still needs a test on the device |

## Layout

```
app/                 the player: a project for the engine fork (scripts, shaders, scenes; no compiled code)
tools/               PC tools: dev listener, cast, voice, audio sink, packaging and install
docs/                documentation (above)
build/               engine cross-build (build-frame.sh, build-player.sh), the static FFmpeg (ffmpeg-build.sh) and
                     libsmb2 (libsmb2-build.sh, patches in libsmb2-patches/)
spikes/00-probe/     device survey script and results (powershell -File spikes/00-probe/run-probe.ps1)
spikes/01-decode/    minimal V4L2 stateful client: HEVC 8-bit up to 8192x4096 at 60, SOURCE_CHANGE, dmabufs
spikes/02-import/    decoder dmabuf to VkImage in the engine (import once, cache by buffer index), NV12 and Q08C
spikes/03-player/    the engine's video module tests (container input, SMB, seeks, HDR)
spikes/04-power/     battery drain and thermals over a sustained session
```

## Status

The player plays local and network files in the headset with hardware decode, in every projection mode, with the
pane, the environments and the playback features. The results behind each part:

- Decoder limits: `spikes/01-decode/results/SUMMARY.md`.
- Zero-copy textures, and the engine's aarch64 strict-aliasing fix: `spikes/02-import/results/FINDINGS.md`.
- Container input, SMB, seeks, subtitles, HDR: `spikes/03-player/README.md`.
- Power (about 9 W, about 2.5 h projected, no throttling): `spikes/04-power/results/SUMMARY.md`.
- What is built but not yet tried on the device: `docs/morning-checklist.md`.

## Licences

- The controller models in `app/models/controllers/` are derived from Valve Corporation's Steam Frame controller CAD
  and are under their own licence, CC BY-NC-SA 4.0 (non-commercial, share-alike; no endorsement by Valve implied):
  see `app/models/controllers/LICENSE-controller.md`. The rest of the repository is not covered by it.
- The room textures in `app/materials/` are CC0 1.0 (public domain), from Poly Haven and ambientCG: each one's source
  and author are in `app/materials/CREDITS.md` (`docs/materials.md`).
- FFmpeg and libsmb2 are linked statically under the LGPL-2.1, and dav1d (AV1) under the BSD-2-Clause licence: see
  `docs/BUILD.md` and `docs/packaging.md`.
- Everything else in this repository is MIT (`LICENSE`).
