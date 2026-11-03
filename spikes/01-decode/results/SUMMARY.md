# Spike 01 results — 2026-10-30, Steam Frame, SteamOS 0.4.5, kernel 6.18.0-ge66bc2ca6f8c

Decoder: `/dev/video-dec0` → `iris_driver` / `iris_decoder`, V4L2 M2M MPLANE. Device on USB power.
Streams: synthetic x265 superfast, 10 s @ 60 fps, ~121 Mbit/s at 8K (`make-streams.ps1`). Full logs in this dir.

## Ceiling (HEVC 8-bit, single session, decode as fast as possible)

| Stream | CAPTURE | fps (first→last) | latency avg / max ms | notes |
|---|---|---|---|---|
| 3840x2160 | NV12 | 258 | 41 / 76 | buffer 3840x2176 (height padded to 32), stride 3840, sizeimage 12,533,760 |
| 3840x2160 | Q08C | 264 | 40 / 74 | |
| 7680x3840 | NV12 | 129 | 88 / 254 | buffer 7680x3840, stride 7680, sizeimage 44,236,800 |
| 7680x3840 | Q08C | 135 | 84 / 221 | |
| 8192x4096 | NV12 | 118 | 97 / 306 | nominally ~1% over the mainline sm8650 MB/s budget; no issue |
| 8192x4096 | Q08C | 123 | 92 / 258 | |

Latency = OUTPUT QBUF → CAPTURE DQBUF with 8 OUTPUT buffers kept full, so it is mostly queue depth, not decoder time.
All runs: 600/600 frames, 0 ERROR flags, 0 ioctl errors, `VIDIOC_EXPBUF` ok on all 7 CAPTURE buffers.

**8K60 is comfortably in range (~2x headroom), including 8192x4096.**

## Other rows

| Test | Result |
|---|---|
| Two concurrent 4K sessions | ok, 145 fps each, no firmware trouble |
| Main10 7680x3840, default | CAPTURE = `Q10C` (TP10 UBWC), 140 fps. Only option the GPU can't sample; P010 not offered on 6.18 |
| Main10 forced `-C NV12` | accepted, 109 fps; picture expected to be low-8-bits garbage (not verified yet) |
| Resolution change 1080p→4K | First run **failed** with `REQBUFS` → ENOMEM. Root cause (from the fork's source, evlaV mirror `sm8650-6.18`, `iris_helpers.c check_core_mbps_mbpf`): an **admission check** on every REQBUFS(n>0) and STREAMON — `mbpf × max(30, queued_rate) × open_sessions ≤ 7,833,600`, where `queued_rate` is the wall-clock average of the last 30 OUTPUT QBUFs. Our unpaced feed (~1500 fps) was 6× over. Fixed in the client: pause input and let the measured rate decay before re-setup (`--reconfig-rate`, ~1.2 s), with a session-restart fallback (close, reopen, resume at the AU carrying the new SPS). All four variants verified on device (`reschange_*.txt`) |
| 8K buffer stability (`--dump-twice 100`) | Buffer held 100 ms after DQBUF: identical MD5 `fb634859…` (= bit-exact frame). Confirms DQBUF'd buffers are stable |

**Player design consequence of the admission check:** 7680x3840@60 (6.9M) and two 4K@60 sessions (3.9M) are within budget;
**8192x4096@60 (7.86M) is over it** — initial setup passes (rate not yet measured) but any re-setup (seek via STREAMOFF/ON,
resolution change) fails with ENOMEM unless the measured rate is reset or the device reopened. Keep one long-lived session,
avoid STREAMOFF/ON on seeks where possible, and reopen on failure.
| CAPTURE = imported dmabufs from `/dev/dma_heap/system` | not testable as `steamos`: heap node is `crw------- root` |
| CAPTURE = imported dmabufs from DRM dumb buffers (`/dev/dri/card0`) | **ok**, 4K NV12 at 258 fps, identical to MMAP. This is the Valve-streaming-client path: GPU-side allocation handed to the decoder |

## Correctness

- 4K NV12 frame 30: **bit-exact** vs ffmpeg software decode (PSNR inf). Layout: stride = width, luma height padded to 32, UV plane immediately after (sizeimage = stride*padded_h*1.5).
- 8K NV12 frame 30: **bit-exact** in 5 runs (paced input, 16 capture buffers, plain repeats, after a Q08C session, after a Main10 session); all dumps MD5 `fb634859…`.
- **Open item:** the very first two 8K dumps after boot did NOT match (one torn: moving element from two frames; one PSNR 29.6 dB ≈ adjacent frame). Not reproducible since. Dump code writes before requeue, so not a client race. Watch for tearing in spike 02's on-screen test; dumps now log MD5.

## Driver facts confirmed (vs docs/research-device.md)

- `G_FMT(CAPTURE)` before SOURCE_CHANGE: 384x256 NV12 placeholder. SOURCE_CHANGE arrives after ~8 AUs queued.
- CAPTURE formats enumerated after SOURCE_CHANGE: `Q08C NV12 NV21` (8-bit stream). `AB24`, `QC24` listed only at idle.
- `MIN_BUFFERS_FOR_CAPTURE` = 0; REQBUFS(4) returns 7.
- `G_SELECTION(COMPOSE)` gives the visible rect (e.g. 3840x2160 inside 3840x2176).
- `V4L2_DEC_CMD_STOP` → LAST buffer with bytesused 0, then clean close.
- Decoder controls are encoder-style (bitrate/QP/H264 level≤6.0); no HEVC level control exposed for decode.
