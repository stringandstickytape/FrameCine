# Spike 01: V4L2 stateful decode on the Frame

`v4l2dec` is a minimal, standalone V4L2 stateful M2M client for the Frame's hardware decoder
(Valve's iris fork, `/dev/video-dec0`). It feeds a raw Annex-B elementary stream, one access unit
per OUTPUT buffer, and measures what the decoder does. No FFmpeg, no libv4l: one C file and the
kernel uapi headers. Background: `docs/research-device.md` sections 2, 3, 6 and "Implications".

It answers these questions:

- Do 7680x3840@60 and 8192x4096@60 HEVC 8-bit decode in real time, to NV12 and to Q08C?
- Does `VIDIOC_EXPBUF` work on every CAPTURE buffer? Does the decoder accept imported DMABUF CAPTURE buffers?
- Do two concurrent sessions work at 4K (for the stereo case), and at what fps each?
- What does the decoder do with HEVC Main10 (Q10C only?) and on a mid-stream resolution change?
- Does it run for a long time (thermal) without a firmware crash?

## Files

| File | Purpose |
|---|---|
| `v4l2dec.c` | The client. The header comment lists the driver quirks it handles and the access-unit split heuristic. |
| `Makefile` | Builds a static arm64 binary with `aarch64-linux-gnu-gcc`. `make CC=gcc` gives a host build (compile check and `--parse-only`). `make deploy` copies the binary to the Frame. |

## Build

From Windows (WSL Ubuntu has the cross toolchain after `build/wsl-setup-arm64.sh`):

```
wsl -d Ubuntu -- make -C spikes/01-decode
```

The result is `v4l2dec`, a static aarch64 ELF that runs on the read-only SteamOS as it is. `make CC=gcc`
builds for the host. Both builds have no warnings with `-Wall -Wextra`.

## Make test streams (on the PC)

The input must be a raw Annex-B elementary stream (`.h265` / `.h264`). VP9 must be IVF.

From an existing file, with no re-encode:

```
ffmpeg -i in.mp4 -c:v copy -bsf:v hevc_mp4toannexb -an out.h265
ffmpeg -i in.mp4 -c:v copy -bsf:v h264_mp4toannexb -an out.h264
ffmpeg -i in.webm -c:v copy -an out.ivf            # VP9; v4l2dec refuses it without --allow-vp9
```

Synthetic HEVC 8-bit streams at 60 fps and a realistic 80-150 Mbit/s. `testsrc2` alone compresses
too well to reach the bitrate, so add temporal noise. 8K x265 encodes are slow, so use a fast preset
and 10 s clips. The `mandelbrot` source is an alternative with real motion detail, but it renders
slowly at 8K.

```
# 3840x2160@60, ~60 Mbit/s
ffmpeg -f lavfi -i "testsrc2=size=3840x2160:rate=60" -t 10 -vf "noise=alls=12:allf=t" \
  -c:v libx265 -preset superfast -pix_fmt yuv420p -b:v 60M -maxrate 80M -bufsize 160M \
  -x265-params "keyint=120:bframes=3:aud=1" hevc8_3840x2160_60.h265

# 7680x3840@60, ~120 Mbit/s (common 8K VR 2:1 size)
ffmpeg -f lavfi -i "testsrc2=size=7680x3840:rate=60" -t 10 -vf "noise=alls=12:allf=t" \
  -c:v libx265 -preset superfast -pix_fmt yuv420p -b:v 120M -maxrate 150M -bufsize 300M \
  -x265-params "keyint=120:bframes=3:aud=1" hevc8_7680x3840_60.h265

# 8192x4096@60, ~120 Mbit/s (about 1% over the sm8650 mainline MB/s budget)
ffmpeg -f lavfi -i "testsrc2=size=8192x4096:rate=60" -t 10 -vf "noise=alls=12:allf=t" \
  -c:v libx265 -preset superfast -pix_fmt yuv420p -b:v 120M -maxrate 150M -bufsize 300M \
  -x265-params "keyint=120:bframes=3:aud=1" hevc8_8192x4096_60.h265

# Same with a mandelbrot source instead (more spatial detail, slower to render):
#   -f lavfi -i "mandelbrot=size=7680x3840:rate=60" and drop or lower the noise filter

# HEVC Main10, 7680x3840@60
ffmpeg -f lavfi -i "testsrc2=size=7680x3840:rate=60" -t 10 -vf "noise=alls=12:allf=t" \
  -c:v libx265 -preset superfast -pix_fmt yuv420p10le -profile:v main10 -b:v 120M -maxrate 150M \
  -bufsize 300M -x265-params "keyint=120:bframes=3:aud=1" hevc10_7680x3840_60.h265

# Mid-stream resolution change (exercises the second SOURCE_CHANGE): two clips concatenated
ffmpeg -f lavfi -i "testsrc2=size=1920x1080:rate=60" -t 3 -c:v libx265 -preset superfast \
  -x265-params "aud=1" a.h265
ffmpeg -f lavfi -i "testsrc2=size=3840x2160:rate=60" -t 3 -c:v libx265 -preset superfast \
  -x265-params "aud=1" b.h265
copy /b a.h265 + b.h265 reschange.h265           # cmd.exe; on Linux: cat a.h265 b.h265 > reschange.h265
```

x265 picks the level itself: 7680x3840@60 and 8192x4096@60 are both level 6.1. Compare that with the
HEVC level control in the `spikes/00-probe` output.

Check the bitrate and that the access-unit split is right before you copy anything. The AU count
from `--parse-only` must equal the ffprobe packet count:

```
ffprobe -v error -count_packets -select_streams v:0 -show_entries stream=nb_read_packets -of csv=p=0 hevc8_7680x3840_60.h265
wsl -d Ubuntu -- ./v4l2dec --parse-only hevc8_7680x3840_60.h265     # host build (make CC=gcc)
```

## Run on the Frame

```
wsl -d Ubuntu -- make -C spikes/01-decode deploy
ssh frame mkdir -p streams results
scp *.h265 frame:~/streams/
ssh frame                       # user steamos
./v4l2dec streams/hevc8_3840x2160_60.h265 -C NV12 2>&1 | tee results/4k_nv12.txt
```

If `open /dev/video-dec0` fails with "Permission denied", look at `ls -l /dev/video22` and `id`. The
probe in `spikes/00-probe` records both.

### Firmware safety rules

- Run **one test at a time**. Wait about 5 s between runs, because fast open/close cycles can crash the firmware (0x5000003).
- After each run, check `sudo dmesg | tail -50 | grep -iE 'iris|0x5000003|smmu'` and save that output with the results.
- **Never `kill -9`** a `v4l2dec` that is stuck in an ioctl, because that can oops the kernel. Press Ctrl-C once to stop feeding and drain. Press it twice to abort, STREAMOFF and close. If the decoder stops progressing, `v4l2dec` reports `HANG` after `--timeout-ms` (5 s by default), then closes the device and exits with code 3.
- After a firmware crash, reboot the headset before the next test. SteamOS ships `iris-driver-rebind.service`, but we have not checked what it does.

### Test matrix

Run each row unpaced first (maximum throughput). Then run it again with `--realtime --fps 60` to
get latency at the nominal rate. Use `-i 2` for periodic stats.

| # | Command | What to record | Expected |
|---|---|---|---|
| 1 | `./v4l2dec streams/hevc8_3840x2160_60.h265 -C NV12 -w 30` | fps, latency, CAPTURE format/bytesperline/sizeimage, EXPBUF result, dumped frame | Works, much faster than 60 fps |
| 2 | `./v4l2dec streams/hevc8_3840x2160_60.h265 -C Q08C` | same, sizeimage vs NV12 | Works |
| 3 | `./v4l2dec streams/hevc8_7680x3840_60.h265 -C NV12 -w 30` | fps (≥ 60?), latency | Likely ≥ 60 fps |
| 4 | `./v4l2dec streams/hevc8_7680x3840_60.h265 -C Q08C` | fps, compare with NV12 | ≥ NV12 fps (less bandwidth) |
| 5 | `./v4l2dec streams/hevc8_8192x4096_60.h265 -C NV12 -w 30` | fps, any error at S_FMT or SOURCE_CHANGE | Unknown: ~1% over the MB/s budget |
| 6 | `./v4l2dec streams/hevc8_8192x4096_60.h265 -C Q08C` | same | Unknown |
| 7 | `./v4l2dec streams/hevc8_3840x2160_60.h265 -C NV12 -s 2` | fps per session, aggregate, errors on session 1 | Both run, aggregate ≥ 120 fps |
| 8 | `./v4l2dec streams/hevc10_7680x3840_60.h265` | CAPTURE format list after SOURCE_CHANGE, default format | Default and only correct format: `Q10C` |
| 9 | `./v4l2dec streams/hevc10_7680x3840_60.h265 -C NV12 -n 120 -w 30` | does S_FMT accept NV12? | Accepted, but the picture is garbage (low 8 bits) |
| 10 | `./v4l2dec -c vp9 streams/any.ivf` | exit code 2, refusal message | Refused, device not opened |
| 11 | `./v4l2dec streams/reschange.h265 -C NV12 -i 1` | 2 SOURCE_CHANGE events, LAST buffer, reconfig time | Drains, reallocates, continues |
| 12 | `./v4l2dec streams/hevc8_3840x2160_60.h265 -C NV12 --capture-mem dmabuf` | does QBUF accept system-heap dmabufs? (`/dev/dma_heap/system` may need root) | Unknown |
| 13 | `./v4l2dec streams/hevc8_3840x2160_60.h265 -C NV12 --capture-mem dmabuf --dmabuf-src dumb` | same, with msm dumb buffers (what Valve's streaming client is said to do) | Unknown |
| 14 | `./v4l2dec streams/hevc8_7680x3840_60.h265 -C NV12 --loop --realtime --fps 60 --duration 1800 -i 30` | fps and latency over time, `results/thermal.txt`. Note the battery level before and after. | Stays at 60 fps |

Rows 7, 12 and 13 have the highest risk of a firmware crash. Run them last, and reboot after any failure.

## Output

Each session prints the OUTPUT format list and frame-size range (session 0 only), the CAPTURE
`G_FMT` before SOURCE_CHANGE (we expect the 384x256 placeholder) and after it, the CAPTURE format
list, the visible rectangle, and each CAPTURE buffer with its EXPBUF fd and dmabuf size. At the end
it prints a summary:

- result: `ok`, `error`, `HUNG` or `aborted`
- AUs queued, loops, and AUs skipped because they did not fit an OUTPUT buffer
- OUTPUT and CAPTURE formats: fourcc, size, planes, bytesperline and sizeimage per plane, buffer counts
- EXPBUF ok/failed counts
- SOURCE_CHANGE and EOS event counts
- frames decoded, and frames with `V4L2_BUF_FLAG_ERROR`
- wall time (open→close and first→last frame)
- decode fps
- latency min/avg/max: from OUTPUT `QBUF` to the CAPTURE `DQBUF` that carries the same timestamp
- frame interval min/avg/max: between CAPTURE `DQBUF`s
- every ioctl that failed, with its errno name and a count

With `-s N` it also prints the aggregate fps. Exit codes: 0 ok, 1 error, 2 bad arguments or VP9
refused, 3 hang.

`-n N` stops feeding after N access units and then drains with `V4L2_DEC_CMD_STOP`, so N frames
come out. `--fps` also sets the OUTPUT timestamps (seq / fps). The driver may use them to estimate
the frame rate for clock scaling, so set `--fps` to the real rate of the stream.

## Validate a dumped NV12 frame (on the PC)

`-w N` writes decoded frame N (display order, counted from 0) as raw plane data:
`frame_s0_fN_<W>x<H>_NV12.raw`. Next to it is a `.txt` file with the format details and a ready
ffmpeg command. The rows include the driver's stride padding, so give ffmpeg the stride
(bytesperline) as the width and crop to the visible rectangle:

```
scp frame:~/frame_s0_f30_*_NV12.raw* .
ffmpeg -f rawvideo -pix_fmt nv12 -video_size <bytesperline>x<height> -i frame_s0_f30_....raw \
  -vf crop=<visible_w>:<visible_h>:0:0 -frames:v 1 hw.png
ffmpeg -i streams/hevc8_7680x3840_60.h265 -vf "select=eq(n\,30)" -frames:v 1 sw.png
```

If the chroma looks shifted down, the luma plane is padded to a multiple of 32 lines. Use the
second command in the `.txt` file, which uses the aligned height. For a numeric check, HEVC
decoding is bit-exact, so PSNR must be `inf`:

```
ffmpeg -f rawvideo -pix_fmt nv12 -video_size <bpl>x<height> -i frame.raw -i stream.h265 -lavfi \
  "[0:v]crop=<w>:<h>:0:0,format=yuv420p[a];[1:v]select=eq(n\,30),format=yuv420p[b];[a][b]psnr" -f null -
```

Each dump logs its MD5, which equals `md5sum` of the file, and the `.txt` file records it too.
The dump copies each plane out once, between `DMA_BUF_IOCTL_SYNC` START and END on the
buffer's dmabuf fd, then writes and hashes that copy. `--dump-twice MS` keeps the buffer
dequeued for MS ms, dumps it again to `..._again.raw`, and logs whether the two MD5s are
identical. A difference means something wrote into the buffer after DQBUF.

`Q08C` and `Q10C` dumps are UBWC-compressed and cannot be checked this way. Spike 02 checks them
by sampling them in Vulkan.

## Assumptions to check against the device

These are the V4L2 details the client had to guess at. Check each one in the run output, together
with `spikes/00-probe` (`v4l2_enum.py`).

1. **S_FMT(OUTPUT) needs the real coded size.** We pass the SPS size (or `--coded-size`), and a `sizeimage` of 1.125 x the largest AU (at least 1 MiB). The driver can clamp `sizeimage`. If it does, AUs that do not fit are skipped and logged.
2. **One access unit per OUTPUT buffer** is what the fork expects. We have not checked whether it also accepts arbitrary chunks or needs whole frames. For MV-HEVC, layer-1 NALs stay in the layer-0 AU.
3. **SOURCE_CHANGE arrives after the first AUs are queued and OUTPUT is streaming**, with CAPTURE not yet set up, and `POLLPRI` signals it before CAPTURE streams. The client also calls `DQEVENT` directly until CAPTURE is set up, in case `POLLPRI` does not come.
4. **G_FMT(CAPTURE) after the event is the real size.** As a guard against the too-small-buffer SMMU fault, the first setup refuses a CAPTURE format smaller than the SPS display size.
5. **S_FMT(CAPTURE) to another fourcc is allowed after SOURCE_CHANGE** without a STREAMOFF of OUTPUT. We ask for the fourcc with the width and height from G_FMT, and log what the driver keeps.
6. **The visible rectangle comes from `G_SELECTION` (COMPOSE, then CROP)** with the single-planar CAPTURE type. If it fails, the dump uses the SPS display size.
7. **`V4L2_CID_MIN_BUFFERS_FOR_CAPTURE` exists.** If it does not, we use 0 + `--capture-extra` (4).
8. **`VIDIOC_EXPBUF` with `O_RDWR | O_CLOEXEC`.** Some exporters accept only `O_RDONLY`.
9. **NV12 is one plane** (`num_planes` = 1, UV after Y). We print `num_planes` and every plane's `bytesperline` and `sizeimage`. The luma height inside the buffer can be the aligned height, not the G_FMT height.
10. **Timestamps are copied from OUTPUT to CAPTURE** unchanged, so latency can be matched per frame. The summary prints how many frames matched.
11. **`V4L2_DEC_CMD_STOP` gives a CAPTURE buffer with `V4L2_BUF_FLAG_LAST`**, maybe with `bytesused` 0, and then `EPIPE`. Fallbacks: EOS event with no LAST, finish after 1 s; STOP not supported, finish when idle.
12. **Mid-stream SOURCE_CHANGE causes an implicit drain that ends in a LAST buffer.** Confirmed on the device. We pause the input and drain to LAST. Then we STREAMOFF CAPTURE, munmap, close the EXPBUF fds, REQBUFS(0), `G_FMT`, reallocate and STREAMON CAPTURE. Every step is logged. If no LAST comes within half of `--timeout-ms`, we reallocate anyway.
13. **DMABUF import:** sizes come from G_FMT `sizeimage` (page-aligned), one dmabuf per plane, the same fd at the same index every time. The defaults are `/dev/dma_heap/system` and `/dev/dri/card0`. On the Frame the msm node could be another `cardN`; use `--dmabuf-dev` to choose it.
14. **Poll behaviour:** we ask for `POLLOUT` only while the driver holds OUTPUT buffers. A `POLLERR` with nothing to dequeue backs off for 1 ms.

## Fork admission check (ENOMEM from REQBUFS / STREAMON)

Source: `drivers/media/platform/qcom/vcodec/iris/` on branch `sm8650-6.18` of the community mirror
`evlaV/deckard-linux-no-oopsies`.

- `check_session_supported()` runs in `queue_setup` (every REQBUFS with count > 0), in STREAMON OUTPUT and in STREAMON CAPTURE.
- It calls `check_core_mbps_mbpf()`. That returns `-ENOMEM` (dmesg: `current session not supported(-12)`) when `mbpf x fps > MAX_MBPS` = 7833600 (7680x4320@60, `platform_sm8550.c`).
- `fps` is `max(QUEUED_RATE, FRAME_RATE, OPERATING_RATE)`. The default is 30.
- `QUEUED_RATE` is a **wall-clock** rate: the average of the last 30 intervals between OUTPUT QBUFs (`iris_update_input_rate()`). It changes only on an OUTPUT QBUF. STREAMOFF OUTPUT clears the interval list but not the value.
- The loop sums the **calling** session's load once per open session (it uses `inst`, not `instance`). So N sessions count as N times one session's load.

Consequences:

- An unpaced feed (about 1500 fps at 1080p) makes every later CAPTURE re-setup fail. The first setup works only because it happens before 30 QBUFs. This is why `reschange.h265` failed. `v4l2dec` now keeps one OUTPUT buffer free and stops feeding when a resolution change starts. Before the re-setup it waits until the last 30 intervals span 30/`--reconfig-rate` seconds (25 fps by default), then queues one AU.
- If the in-place re-setup still fails, `v4l2dec` restarts the session. It closes the device (STREAMOFF both queues, frees everything), waits 200 ms, reopens, and does S_FMT(OUTPUT) at the new SPS size. Then it resumes at the AU that carries the new SPS (`--parse-only` lists these as `sps_size_change`). The log says `reconfig path: IN-PLACE` or `reconfig path: SESSION RESTART`, and the summary counts both. `--no-restart` turns the fallback off. `--reconfig-rate 0` together with the default restart exercises the fallback path.
- **8192x4096@60 is over the limit even when the input is paced at exactly 60 fps**: 131072 MB x 60 = 7864320 > 7833600. 7680x3840@60 is 6912000 and passes. For 8192x4096@60 the initial setup passes. Any re-setup that comes after 30 QBUFs at 60 fps fails: a resolution change, or a seek that does STREAMOFF/STREAMON OUTPUT. The player must avoid this. It can lower the queue rate before the re-setup (as `rate_reset()` does), or reopen the device.
- Two sessions at 4K paced at 60 fps: 32640 x 60 x 2 = 3916800, well under the limit.
