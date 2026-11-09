# Architecture

How FrameCine is built: the stack and why, the constraints, the repository's layout and the results behind each part.
Moved here from the README for the 0.1.0 release (2026-11-10); the README is for people who use the player.

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
