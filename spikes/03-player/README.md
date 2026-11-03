# Spike 03: a real video, zero copy, on the Frame

Goal: play a real film through the path spikes 01 and 02 proved piece by piece: hardware decode (V4L2, `/dev/video-dec0`)
→ CAPTURE dmabufs → imported once as Vulkan images (DmabufImage) → two RenderingDevice plane textures → a quad, in our
Godot fork, as an engine module. Audio (OGG, Godot's AudioStreamPlayer) is the master clock.

Test film: `documentary_sbs.h264`, H.264 3840x1080 full side-by-side 3D, 23.976 fps, 2640 s (63,311 access units, max 1.77 MB,
18 Mbit/s), with `documentary.ogg` as its audio. Both are in `spikes/01-decode/streams/` on the PC and `~/spike01/streams/` on
the Frame.

## Engine side (`~/src/godot-player`, branch `frame/player`, on top of `frame/4.7` ffe09b3d8f)

New files in `modules/hwvideo/` (Linux + Vulkan only, through `config.py`):

| File | What |
|---|---|
| `annexb_splitter.{h,cpp}` | The access-unit split and SPS parse of `v4l2dec.c` (`--parse-only`), made incremental: one access unit per call, `seek()` to a known offset. A 6 GB film is not scanned before it plays. |
| `v4l2_decoder.{h,cpp}` | `V4L2Decoder` (RefCounted, script-visible): the session logic of `v4l2dec.c` on a worker thread. |
| `hw_video_texture.{h,cpp}` | `HWVideoTexture` (RefCounted): decoder buffers → DmabufImage → plane textures, frame choice by clock, buffer return. `HWVideoPlaneTexture` (Texture2D): one plane of the frame on screen. |
| `media_source.{h,cpp}` | `MediaSource` (RefCounted, 2026-10-31): FFmpeg demux of a container file on a worker thread, video access-unit queue for the decoder, audio decode + resample into a ring. See "Container input" below. |
| `audio_stream_media.{h,cpp}` | `AudioStreamMedia` / `AudioStreamPlaybackMedia`: that ring as an AudioStream; its playback position is the master clock. |
| `doc_classes/*.xml` | Class reference. |

### V4L2Decoder

`open(path, codec, fps)` maps the file, reads the coded size from the first SPS, opens the device and runs QUERYCAP on the
calling thread (so a missing decoder is a synchronous `ERR_CANT_OPEN` with a clear message), then starts the worker.
The worker does what `v4l2dec.c` does, in the same order: S_FMT OUTPUT (codec fourcc, SPS coded size), REQBUFS OUTPUT
mmap, subscribe SOURCE_CHANGE and EOS, queue access units, STREAMON OUTPUT, wait for SOURCE_CHANGE (DQEVENT polled
directly until CAPTURE exists), G_FMT CAPTURE, S_FMT CAPTURE to NV12 (`capture_format`; `"Q08C"` since PLAYER_UBWC), the
too-small-format guard, G_SELECTION for the visible rectangle, REQBUFS CAPTURE mmap, VIDIOC_EXPBUF on every buffer (the fds
are kept until the CAPTURE queue is torn down; no CPU mapping at all), QBUF all, STREAMON CAPTURE, then the poll loop.

What differs from `v4l2dec.c`, and why:

- **Pacing by the playback clock.** The consumer sets the clock (`set_clock()`, every frame). Access units are fed while
  `media_index / fps <= clock + lead_time` (0.25 s by default), and never more than all OUTPUT buffers but one in the
  driver (as in `v4l2dec.c`). So the driver's measured QUEUED_RATE is the playback rate, and the admission check
  (`mbpf × max(30, rate) ≤ 7,833,600`) sees the real load. Exception: until the first frame of an epoch (start, seek,
  loop, restart) is out, the feed is unpaced, because SOURCE_CHANGE needs ~8 access units and B-frame reordering a few
  more. Paused = the clock stops = the feed stops. A decoder that falls behind is also held back by CAPTURE buffers:
  the consumer owns every decoded buffer until it returns it.
- **Decoded buffers are not re-queued by the decoder.** A dequeued CAPTURE buffer goes to the consumer
  (`pop_frame()`), with its generation (CAPTURE setup count), index, seek serial and time. It is re-queued when the
  consumer calls `return_buffer()`. An eventfd wakes the worker for returns, clock changes and seeks.
- **Frame times.** Annex-B has no timestamps and pictures leave the decoder in display order, so a frame's time is its
  display-order index in its epoch / fps (frame N at N / fps). The V4L2 timestamps are still the real `seq / fps` (the
  driver may estimate the frame rate from them); they map each frame back to the epoch (run of access units since a
  jump) it was fed in.
- **Seek to start** without STREAMOFF: the next access unit fed is the first one (SPS + PPS + IDR), under a new serial;
  frames of the old serial are returned unseen. After the end of the stream was drained (`V4L2_DEC_CMD_STOP` → LAST,
  state `ENDED`), a seek restarts the session instead (close, ≥ 1 s, reopen).
- **Resolution change**: the `v4l2dec.c` logic unchanged: input paused at SOURCE_CHANGE, drain to LAST, `_rate_reset()`
  (pause until the last 30 QBUF intervals span 30 / `reconfig_rate` s, then one access unit), teardown, in-place re-setup;
  if that fails, session restart at the access unit carrying the new SPS (a ring of the last 64 access units fed).
- **Device opens are at least 1 s apart** (static across instances), for the firmware's open/close sensitivity.
- **Hang**: no progress for `timeout_ms` (5 s) while the decoder holds input and has a CAPTURE buffer, or during a drain
  → state `ERROR` with the message from `v4l2dec.c`, STREAMOFF and close. Nothing is ever killed. `close()` waits for the
  worker to finish its current poll slice (100 ms).
- `loop`: at the end of the file, continue at the first access unit with the times continuing (no gap). For runs
  without audio.

OUTPUT buffer size: the largest access unit is unknown without a full scan, so `clamp(w × h × 3/4, 1 MiB, 16 MiB)`
(3.1 MB for 3840x1088; the film's largest is 1.77 MB). Larger access units are skipped and logged;
`output_buffer_size` overrides it.

### HWVideoTexture

- **Import once.** When the first frame of a new CAPTURE generation arrives, every buffer of that generation is imported
  as a `DmabufImage` (`import_nv12(fd, G_FMT width, G_FMT height, DRM_FORMAT_MOD_LINEAR, [0, chroma_offset],
  [pitch, pitch])`, from a dup of the EXPBUF fd) and wrapped in two RenderingServer textures (`texture_rd_create`). They
  are cached until the generation ends (resolution change, session restart or close). Never per frame: per-frame dmabuf
  import can oops the 6.18 kernel. The chroma offset is `pitch × align(height, 32)` (spike 01: luma padded to 32 lines,
  chroma right after), checked against `sizeimage`.
- **Buffer states**: DECODER → READY (dequeued, waiting for its time) → SHOWN (acquired) → RETIRING (released) →
  DECODER. A READY frame that is overtaken by a later due frame is dropped and returned at once (never acquired).
- **Frame choice**: `update(delta, master_clock)` sets the clock (master clock if ≥ 0, else `+= delta` while playing),
  shows the newest ready frame with `time <= clock` and drops the older ones (late).
- **Render thread**: the release of the previous buffer and the acquire of the new one (`DmabufImage.release()` /
  `acquire()`: the FOREIGN ↔ graphics queue family transfer recorded in the RD graph) run through
  `RenderingServer.call_on_render_thread()`, before the frame's draws. Frees of images (and their pending
  `free_image()`, which defers the VkImage destruction) go the same way.
- **Re-queue only when the GPU is done**: a released buffer is returned to the decoder once
  `frames_drawn >= release_frame + frame_delay + 2` (one frame more than `DmabufImage` itself waits, to cover a render
  thread that runs a frame behind the main thread).
- **Plane textures**: `get_plane_texture(0|1)` returns a `HWVideoPlaneTexture`, a Texture2D whose RID is a
  RenderingServer *proxy* (as `AnimatedTexture` does). Each shown frame repoints the proxy (`texture_proxy_update`) at
  the buffer's plane texture; the material never changes. The material's uniform set is rebuilt when the proxy's view
  changes (the same path `AnimatedTexture` uses). Before the first frame the proxies show limited-range black.
  `get_plane_rd_rid(p)` gives the raw RD RID of the shown buffer's plane (changes every frame) for `Texture2DRD` users.
- `get_decoded_size()` (e.g. 3840x1088), `get_visible_rect()` (3840x1080+0+0), `get_visible_uv_rect()` for the shader,
  signal `format_changed` when a generation is imported. `get_stats()`: the decoder's counters plus
  `frames_shown`, `frames_dropped`, `frames_stale`, `position`, `frame_time`.

### A/V sync (simple, audio master)

`main.gd` waits until the first frame is on screen, then starts `AudioStreamPlayer.play()` and `HWVideoTexture.play()`
together. Each frame the clock is `get_playback_position() + AudioServer.get_time_since_last_mix() -
AudioServer.get_output_latency() + --av-offset` (the formula from Godot's "Sync the gameplay with audio" page); the video
shows the newest frame with `time <= clock` and drops later-than-that frames. The A/V offset printed every 2 s is
`clock - time of the frame on screen` (0 to one frame duration, 42 ms, is in sync).

Limits:
- The frame chosen in `_process` is displayed one or more frames later (render queue, and in XR the runtime's
  predicted display time). That constant lag isn't compensated; `--av-offset` can be used to tune it by eye/ear.
- `get_playback_position()` advances in mix-buffer steps; the `time_since_last_mix` term smooths that, but the clock can
  still jitter by a few ms, which can move a frame boundary by one display refresh.
- No resampling or clock drift correction: the video follows the audio, never the other way. If the decoder falls
  behind, frames are dropped; the audio never waits.
- Frame times assume a constant frame rate (`--fps`). Variable frame rate or field (PAFF) streams would drift.
- Without audio the clock is the sum of `_process` deltas.

### Shader (`project/video.gdshader`)

NV12 → RGB like spike 02 (BT.709, limited range, sRGB curve to linear). Uniforms: `visible_rect` (UV offset/size of the
visible area, from `get_visible_uv_rect()`), `stereo_mode` (1 = full SBS: `VIEW_INDEX` 0 samples the left half, 1 the
right half; the flat camera is view 0, so it shows the left half). UVs are clamped half a chroma texel inside the
(per-eye) rectangle, so neither the 8 padding lines nor the other eye's half bleed in through bilinear filtering.

## Container input: MediaSource (2026-10-31)

Fork commits `ca57514ecf`, `e4b4769810` on `frame/player`; Frame binary `build/out/godot.linuxbsd.template_debug.arm64.PLAYER_DEMUX`
(sha256 `53eefd8b3b8f9621860492d989438c8ffe8526fe5d9fb9b4143ca626f13d0307`, version string ends in `e4b476981`). It played
the full-SBS 3D documentary MKV on the Frame first time.

Second round (MPEG-TS seeks, end-of-sequence NAL unit after a seek, zlib, subtitles): fork commit `6d48ab6812`; Frame binary
`build/out/godot.linuxbsd.template_debug.arm64.PLAYER_DEMUX2` (sha256 `eefcf13144bea824be90c21b85256e20ff2ad95b358fef0db7afdbfb3819395e`, version string ends in `6d48ab681`).

Plays ordinary files (Matroska/WebM, MP4/MOV, MPEG-TS, AVI) instead of a raw Annex-B stream plus a separate OGG. FFmpeg
demuxes and decodes the audio; the video still goes through `V4L2Decoder` and `HWVideoTexture`, zero copy as before.

```
var source := MediaSource.new()
source.open(path)                          # stream info: source.get_info()
video.open_source(source)                  # HWVideoTexture → V4L2Decoder.open_source()
$Audio.stream = source.get_audio_stream()  # AudioStreamMedia: the master clock, as with the OGG
source.seek(600.0)                         # audio and video; HWVideoTexture follows by the source's serial
```

### FFmpeg

Static, LGPL configuration (no `--enable-gpl`/`--enable-nonfree`), tag `n8.1.3`, built by `build/ffmpeg-build.sh` into
`~/src/ffmpeg-aarch64` and `~/src/ffmpeg-x86_64` (source in `~/src/ffmpeg`, not committed). `--disable-everything
--disable-autodetect`, then: libavformat, libavcodec, libswresample, libavutil; demuxers matroska (also WebM), mov (MP4),
mpegts, avi; parsers h264, hevc, vp9, av1, aac, ac3 (also E-AC-3), dca, opus, vorbis, flac, mpegaudio; bitstream filters
h264_mp4toannexb, hevc_mp4toannexb, extract_extradata; audio decoders aac, aac_latm, ac3, eac3, dca, truehd, mlp, opus,
vorbis, flac, mp3, mp2, pcm_*; subtitle decoders subrip, srt, ass, ssa, movtext, webvtt, text; zlib; protocol file. No
video decoders, no network. `modules/hwvideo/SCsub` adds the
include path (`-isystem`) and the four archives (plus `-lm -latomic`) for `env["arch"]`; `HWVIDEO_FFMPEG_PREFIX`
overrides the prefix. The arm64 binary needs no new shared library and the same glibc (2.38) as before, and is 3.1 MB
larger than `PLAYER_O2` (91.7 MB vs 88.6 MB).

zlib: Matroska tracks with zlib content compression (the documentary MKV's VobSub tracks) need it, or FFmpeg logs
`Unsupported encoding type` and can't read them. FFmpeg is configured against the headers of the engine's bundled zlib
(`thirdparty/zlib`, 1.3.2; `GODOT_SRC`, default `~/src/godot-player`), and its calls resolve to the zlib that is already
in the engine binary: no second copy, no `libz.so`.

`build/ffmpeg-build.sh tool` also builds a remux-only `ffmpeg` command (x86_64, `~/src/ffmpeg-tool`, never shipped) for
`demux-test/make-test-files.sh`.

### Threads and queues

One demux thread per source. It reads (`av_read_frame`) while the video queue holds less than `video_queue_seconds` (1 s,
at least 8 access units) or the decoded audio less than `audio_queue_seconds` (1 s): ffplay's rule, a stream that has
enough doesn't hold up the others. Otherwise it waits on a condition variable and is woken by the consumers: the decoder
when the queue drops below 3/4 of its target, the audio mixer below 0.75 s (or when a pending decoded chunk fits), and
seek / track change / close. It never spins. Hard limits: 512 access units or 96 MB of video, and 8192 packets or 32 MB of
compressed audio. Audio read while the 4 s ring is full (not played yet, or ahead of the video in the file) waits
compressed in a FIFO and is decoded once there is room, so the video keeps flowing.

No lock is held while reading or decoding. The mixer takes only the audio lock on its path. Allocations: AVPacket structs
come from a pool; the resampler's scratch buffer grows to the largest packet once; the ring is allocated at open.
FFmpeg allocates each packet's payload (demuxer) and the bitstream filter's output, which is the one copy of an access
unit before the decoder's own copy into its OUTPUT buffer.

### Video path

- Annex-B: length-prefixed H.264/HEVC (avcC/hvcC in MP4 and Matroska) goes through `h264_mp4toannexb` /
  `hevc_mp4toannexb`, which also put the SPS/PPS (and VPS) in front of every IDR picture. Annex-B input (TS) passes.
- After open and after every seek, video is dropped until a keyframe; if that keyframe has no SPS in band (a recovery-point
  I picture or a CRA, which the filters don't touch, or TS), the latest in-band parameter sets (else the codec
  configuration's) are put in front of it. Only the bytes before the first slice are scanned, and only for keyframes, to
  find the SPS: its coded size goes with the access unit (`sps_width/height`) for S_FMT and session restarts.
- Times are media seconds: the stream timestamp minus the file's start time. The PTS comes from the container. Matroska has
  no DTS (FFmpeg reports the PTS, which jumps around with B-frames), so nothing uses the DTS.
- MPEG-TS has no codec configuration: `open()` reads up to the first SPS (the coded size is needed for S_FMT OUTPUT); what
  it reads is queued as usual.

### MPEG-TS

- TS has no keyframe index, so FFmpeg's timestamp seek lands on a packet near the target, not on a keyframe at or before
  it. The source drops video up to the next keyframe as usual. If that keyframe is after the target, it seeks again 2, 4,
  8... s earlier than the target (at most 6 times, counted as `seek_retries`). The audio read meanwhile is held in the
  compressed FIFO, and decoded once the keyframe is found, so the audio still starts exactly at the target.
- A seek to 0 is a byte seek to the start of the file (a timestamp seek to 0 found the second keyframe).
- Test files: `demux-test/make-test-files.sh` cuts 90 s from three MP4 films into TS with a stream copy (no transcode).
  A stream copy from Matroska to TS gives broken PTS for B-frame video (Matroska has no DTS), so the sources are MP4.

### Seek: end-of-sequence NAL unit (`V4L2Decoder.seek_eos`)

A seek can land on a keyframe that isn't an IDR picture: an HEVC CRA (open GOP; `Animated.HEVC10.mp4` and `Feature.HEVC10.CRA.mp4` land on
CRA pictures, see the table below) or an H.264 I picture with a recovery point. The pictures that follow it in decode
order but come before it in display order (leading pictures) reference pictures from before the seek. The decoder can't
know that it is a random access point: to it, the stream simply continues. An end-of-sequence NAL unit (H.264 type 10,
HEVC EOS_NUT) in front of the keyframe tells it: in HEVC the CRA after an EOS gets NoRaslOutputFlag, so its RASL leading
pictures are dropped; in both codecs the pictures held for reordering are output first.

`V4L2Decoder.seek_eos`: `SEEK_EOS_SEPARATE` (2, the default since the device A/B below) puts the NAL unit in an OUTPUT
buffer of its own before the first access unit after a seek, `SEEK_EOS_PREPEND` (1) in the same OUTPUT buffer as that
access unit, `SEEK_EOS_OFF` (0) adds nothing. Not at a session start. Counted as `eos_inserted`; the decoder logs the first access unit after each seek (time, IDR/CRA/BLA/I,
SPS or not, EOS or not). `read_video_packet()` reports the same as `nal_type` and `random_access`. In HEVC, EOS then
CRA is a conforming stream. In H.264, the access unit after an end of sequence must be IDR, so EOS before a
recovery-point I picture is strictly out of spec (decoders such as FFmpeg's accept it); before an IDR it only flushes.

Device A/B (PLAYER_DEMUX2, the documentary MKV, H.264 with IDR keyframes, `--seek-every=10 --seek-by=37`, 3 seeks per run; logs in
`results/run_eos{0,1,2}.log`):

| `seek_eos` | Settle time per seek | Decoder errors |
|---|---|---|
| 0 off | 411 / 467 / 388 ms | 0 |
| 1 same buffer | 400 / 467 / 366 ms | exactly 1 per seek (3) |
| 2 own buffer | 399 / 466 / 378 ms | 0 |

iris rejects the end-of-sequence NAL unit when it shares the keyframe's OUTPUT buffer and accepts it in a buffer of its
own; the settle time doesn't change. So the default is 2, with 0 and 1 still selectable. Whether it helps after a CRA or
a recovery-point I picture still needs an 8-bit open-GOP file on the device (the CRA files here are 10-bit).

### Subtitles (groundwork)

- `get_subtitle_tracks()`: codec, `text` (SubRip, ASS/SSA, MP4 timed text, WebVTT: decoded by FFmpeg) or `bitmap` (PGS,
  VobSub, DVB, XSUB: passed through as packets), language, title, default, forced.
- `select_subtitle_track(i)` (-1: none) adds that stream to the ones the demux thread keeps. `read_subtitle_event()` takes
  the next event: `start`, `end` (-1 when unknown), `text` (plain, override tags removed, `\n` between lines), `ass`
  (FFmpeg's ASS event line, for libass), `data` (bitmap tracks: the raw packet), `serial`. `get_subtitle_header()`: the
  ASS header of a text track.
- Events come in file order, about the queue length (1 s) ahead of the playback position, so the consumer keeps them until
  their time. At most 512 are queued; the oldest are dropped.
- Limits: selecting a track doesn't seek, so the events of packets read before (up to 1 s ahead) are missed. After a seek,
  an event that started before the keyframe isn't delivered (Matroska cues could find it; not done). Bitmap events aren't
  decoded (PGS/VobSub decoders and a texture path are the next step, with libass for text).

### V4L2Decoder with a MediaSource (`open_source()`)

- Pops access units from the source instead of the splitter; the session logic is unchanged.
- Pacing: access unit k of an epoch is due at `min(epoch start PTS + k / fps, its PTS)`, fed while that is within
  `lead_time` of the clock (unpaced until the epoch's first frame is out). The same rule as the file path's `index / fps`.
- Frame times: the V4L2 timestamps stay `seq / fps` (unique, what the driver saw before). The PTS of each access unit is
  kept in a ring by `seq`, and a CAPTURE buffer's timestamp maps it back to the PTS of the access unit its picture came
  from. This relies on the stateful-decoder rule that the CAPTURE buffer carries the OUTPUT buffer's timestamp, which the
  epoch logic already relied on.
- Seeks follow the source's serial. A held access unit of an older serial is dropped; the first one of a new serial starts
  a new epoch. No STREAMOFF, as in `seek_to_start()`: the keyframe carries its parameter sets, and frames of the old serial
  still in the driver come out under the old serial and are dropped as stale. After the end was drained (STOP sent), a new
  serial restarts the session (close, at least 1 s, reopen).
- Resolution change: in-place re-setup unchanged. The session-restart fallback can't re-read the access units fed since
  the new SPS from the queue, so it seeks the source back to that access unit's PTS (audio included: a jump back of about
  0.3 s) and restarts.
- `loop` is ignored (seek to 0 at the end instead).

### HWVideoTexture with a MediaSource

- `open_source(source)`, `seek(seconds)` (= `source.seek()`), `get_media_source()`.
- `update()` picks up any seek on the source (by this object, the audio player or directly) from its serial: ready frames
  go back as stale, the clock jumps to the target, and nothing new is shown until the frame for the target is known: the
  newest at or before it, once a later one has arrived (or the first one if it is after the target). The frames decoded on
  the way count as `frames_skipped`. The same applies after open, so a stream whose first frame is at 0.083 s shows that
  frame before `play()`.

### Audio

- One FFmpeg decoder for the selected track (one thread), libswresample to stereo float at the AudioServer mix rate. The
  downmix is ITU-R BS.775: centre and surrounds at -3 dB, LFE dropped, not normalised (mpv's default; dialogue keeps its
  level). `downmix_normalize` scales the matrix so no sum can exceed full scale (about 7.7 dB quieter for 5.1). The source
  layout stays available (`get_audio_tracks()`, `channel_layout`) for spatial audio later.
- Ring of 4 s of AudioFrames, plus markers (ring frame → media time) wherever the time doesn't continue (start, seek, gap).
  The playback position is the media time of the next frame to be mixed (Godot's convention), updated in `mix()`, so
  `main.gd`'s clock formula is unchanged. Underrun: silence, and the position holds (the video waits).
- Seek: the ring is flushed in `seek()` itself (the position is the target at once); decoded audio before the target is
  dropped; a gap of less than 1 s before the first decoded sample is filled with silence. So the clock restarts exactly at
  the target.
- `select_audio_track()` seeks to the current position (the queues hold the old track's audio).
- `audio_decoder_options`: FFmpeg AVOptions for the audio decoder. FFmpeg's DTS decoder decodes DTS-HD MA (XLL lossless)
  by default and falls back to the core by itself when an extension is damaged; `{"core_only": "1"}` forces the core, a
  cheaper option if XLL decode turns out costly on the Frame.
- `AudioStreamPlayer.play(t)` / `seek(t)` seek the source unless its audio is already within 50 ms of `t`, so the usual
  "seek, then play the player at the same time" costs one seek, not two. `play()` (0) never seeks.
- The playback stops playing when the source's audio is drained, so AudioStreamPlayer emits `finished`. `pitch_scale` is
  ignored. One player per stream: playbacks share the ring.

### Tests without the device (`demux-test/`)

`demux-test/test.gd` runs headless on the x86_64 build of the same engine (`build/build-player.sh x86_64`):
`demux-test/run-tests.sh` runs it on the documentary MKV (compared with `documentary_sbs.h264`), eight other local films, and the
four small files of `demux-test/make-test-files.sh` (three TS, one MKV with made-up SRT and ASS tracks; seek to 45 s). Checks:
stream info; the first 200 access units (keyframe first, parameter sets in band, Annex-B, PTS spacing; for the documentary
byte-identical to the access units the splitter cuts from `documentary_sbs.h264`, and contiguous); 10 s of audio (not silent,
the clock advances by exactly what was mixed, no underrun); seek to 600 s (the next access unit is a keyframe at or before
600 s with the parameter sets, no other keyframe between it and the target, the audio clock is 600.000 at once and runs on
without a gap); seek to 3 s before the end (read to the end, the audio finishes) and back to 0; 2 s through a real
AudioStreamPlayer (headless: the dummy driver mixes in real time); `HWVideoTexture.open_source()` without a decoder fails
with a message and leaves the source usable; every subtitle track from the seek target for 120 s (events in order, in
range, text events with text and an ASS line, the ASS header there).

Results (2026-10-31, all 13 pass; "lands on" is the keyframe and its type):

| File | Container, video, audio | Seek to 600 s lands on | Notes |
|---|---|---|---|
| `Documentary.3D.Full-SBS.mkv` | MKV, H.264 3840x1080 SBS, DTS 5.1, 2 × VobSub | IDR 594.344 (next 604.771) | 200 AUs byte-identical to `documentary_sbs.h264` (15,855,661 bytes); 200 AUs in 113 ms; VobSub (zlib): 19 and 20 events in 120 s |
| `Animated.Feature.2.3D.2019.MULTi.1080p.Half-SBS.mkv` | MKV, H.264 1920x1080 Half-SBS, 2 × DTS-HD MA 5.1 (fre default, eng), 2 × PGS (fre "Forced", fre) | IDR 598.932 (next 601.351) | XLL lossless decodes (`s16p`); `audio_decoder_options = {"core_only": "1"}` decodes the core only (`fltp`); track 1 (eng) selected: passes; PGS: 0 (forced) and 63 events |
| `Action.720p.mp4` | MP4, H.264 720p, AAC 5.1 | IDR 599.599 | the file has no frame at 0.042 s (one PTS gap) |
| `Animated.1080p.mp4` | MP4, H.264 1920x800, AAC stereo | IDR 591.792 | |
| `Animated.HEVC10.mp4` | MP4, HEVC 10-bit, AAC 5.1 | CRA 596.049 | `hw_decodable` false (10-bit) |
| `Feature.HEVC10.CRA.mp4` | MP4, HEVC 10-bit, AAC 5.1 | CRA 598.181 | |
| `Feature.2160p.HDR.mkv` | MKV, HEVC 10-bit 3840x1608, TrueHD 7.1 (+ AC-3, E-AC-3), 4 × PGS | IDR 591.925 | track 2 (E-AC-3 7.1) selected: passes too; PGS: 50 to 92 events |
| `Animated.Feature.3.3D.Half-SBS.mkv` | MKV, H.264 Half-SBS, E-AC-3 7.1, PGS | IDR 595.970 | PGS: 68 events |
| `Comedy.1980.XviD.avi` | AVI, MPEG-4 Part 2, MP3 | 598.720 (not parsed) | video not hardware-decodable; demux and audio pass |

The small files (seek to 45 s):

| File | Container, video, audio | Seek to 45 s lands on | Notes |
|---|---|---|---|
| `action_90s.ts` | TS, H.264 720p, AAC 5.1 | IDR 43.798 (next 45.884) | 1 retry |
| `animated_90s.ts` | TS, H.264 1920x800, AAC stereo | IDR 44.424 (next 46.132) | 1 retry |
| `hevc10_90s.ts` | TS, HEVC 10-bit, AAC 5.1 | CRA 43.686 (next 47.481) | 1 retry |
| `animated_subs.mkv` | MKV, H.264, AAC, SubRip + ASS | IDR 44.424 | 17 events per track, text and ASS line, ASS header present |

Other TS seeks in a debug run: `action_90s.ts` 5 s → 3.132 (1 retry), 20 → 18.773, 60 → 58.396, 0 → 0.004; `hevc10_90s.ts` 20 → 17.785, 60 → 59.159.

The demux thread used 3 to 12 % of one x86 core over the 2 s after a seek to 0, which includes refilling both queues and
reading (and copying) the video for the script; the steady state wasn't measured. `get_stats()["thread_cpu_seconds"]` of
the source and of the decoder give the per-thread CPU time on the Frame.

### Not verified (needs the device)

- The decode path with `open_source()`: the documentary MKV through iris. Its access units are byte-identical to
  `documentary_sbs.h264`'s, so the bitstream is the one that already plays.
- The PTS mapping through the driver's timestamp copy, the pacing by `epoch start + k / fps`, seeks without STREAMOFF,
  the restart after the end, and the seek-back fallback after a failed in-place resolution change.
- A/V sync with `AudioStreamMedia` as the clock, and the CPU cost on the Frame (DTS and TrueHD decode on the little
  cores, the demux thread, the extra copy by the bitstream filter).
- MPEG-TS through iris works (device, PLAYER_DEMUX2: `action_90s.ts` with `--start=45`, playing 0.77 s after launch, A/V
  +1 to +39 ms, 0 decoder errors; `results/run_ts.log`). WebM is not verified (VP9/AV1 are enumerated only: no hardware
  path).
- The end-of-sequence NAL unit after a CRA or recovery-point seek: iris accepts it in its own buffer (A/B above, IDR
  file), but whether it changes anything after an open-GOP keyframe needs an 8-bit file with CRA or recovery-point I
  pictures (the CRA files here are 10-bit HEVC, not decodable yet).

### Open questions (container input)

1. Open-GOP seeks: iris accepts the end-of-sequence NAL unit only in a buffer of its own (default now); whether it is
   needed after a CRA or recovery-point keyframe is still open (needs an 8-bit open-GOP file).
2. 10-bit HEVC files demux fine but aren't hardware-decodable until P010 or Q10C import works.
3. Subtitle rendering: libass for text, PGS/VobSub decode to a texture; and finding the events in progress at a seek
   target.

## Network files: SMB (2026-10-31)

Fork commit `893d2d87a8` on `frame/player`; Frame binary `build/out/godot.linuxbsd.template_debug.arm64.PLAYER_SMB` (sha256
`d58465f702f4389f32e6769a2a05602d808811135227689e24dc05c577691dbd`, version string ends in `893d2d87a`).

Second build: fork commit `2b35386ef0`; `build/out/godot.linuxbsd.template_debug.arm64.PLAYER_SMB2` (sha256
`9b23b63954ef2ed4db9fcc910b9a2782a66ee67dd3023392ebf2297feccd66bd`, version string ends in `2b35386ef`), with `seek_eos`
defaulting to 2 and the guest-login message below.

Third build: fork commit `a88f2f1a35`; `build/out/godot.linuxbsd.template_debug.arm64.PLAYER_SMB3` (sha256
`5054631104b8d268341a7a0980ae2d480e2b2244693a4d9c045eb10d252559b8`, version string ends in `a88f2f1a3`): refills and
steady-state stalls counted apart, audio waits after seeks apart from underruns, `network_requests` (see the device results
below).

First device run (PLAYER_SMB, Wi-Fi): playback got "Access denied: 192.168.1.21 refused the user name or password." while
`--probe` seemed to work. `--probe` didn't touch SMB at all (it splits `--file`, by default the local
`documentary_sbs.h264`: its 63311 access units). The same arguments log in from x86 (password file, empty or machine-name
domain) and libsmb2 built for aarch64 logs in under qemu, so the likely cause is a `project/main.gd` on the device older
than the SMB options: it ignores `--smb-user` and the rest, and MediaSource logs in as guest. Changes: the engine now says
so ("no user name and password are set for HOST ..., and it refused a guest login"); `main.gd` prints
"SMB: HOST as USER (password from ..., N characters)" before opening, warns about arguments it doesn't know, stops if the
password file can't be read or is empty, and `--probe --media=...` opens through MediaSource like playback;
`smb-tests.sh` runs `main.gd` with the Frame's arguments (both domain forms, probe and playback) and checks that `open()`
gets through. From the Frame, the lead logged in with smbclient using an empty domain.

`MediaSource.open("smb://host/share/path/file.mkv")` reads a film straight from a file share on the PC or a NAS: no mount
(that needs root), no copy. `MediaBrowser` lists the shares and folders for the app's file browser.

```
MediaSource.set_smb_credentials("192.168.1.10", user, password, "PC-NAME")  # static; shared with MediaBrowser
var browser := MediaBrowser.new()                   # blocking calls: run them on a worker thread
browser.list_shares("192.168.1.10")                 # ["Movies", ...]
browser.list_dir("smb://192.168.1.10/Movies")       # [{name, is_dir, size, mtime}, ...], folders first
browser.get_last_error()                            # "Access denied: ...", "Not found: ...", "Can't reach ..."
source.open("smb://192.168.1.10/Movies/film.mkv")   # then as with a local file
```

### libsmb2

- libsmb2 `libsmb2-6.3.1`, static, built by `build/libsmb2-build.sh` into `~/src/libsmb2-aarch64` and `~/src/libsmb2-x86_64`
  (source in `~/src/libsmb2`, not committed; no Kerberos). SMB2 and SMB3, NTLMSSP (user name and password). `SCsub` links it
  like FFmpeg (`HWVIDEO_LIBSMB2_PREFIX` overrides the prefix). The arm64 binary still needs only libc, libm and the loader.
- Licence: the client library is LGPL 2.1 or later (not BSD-2); only its DCE/RPC part (used to list shares) is BSD-2. Linked
  statically, so the same note as for FFmpeg applies.
- Not FFmpeg's `smb` protocol (libsmbclient: Samba, GPL), and nothing is mounted.
- SIGPIPE: libsmb2 writes with `writev()`, which raises SIGPIPE on a connection the server dropped; Godot doesn't ignore
  it on Linux. The first SMB connection sets it to ignored if nobody handles it (as network programs do).

### Signing cost, and a patch

The share negotiates SMB 3.1.1 with signing (the host requires it). libsmb2 checks the AES-CMAC signature of every response,
the read data included, and its implementation expands the AES key again for every 16-byte block and signs a malloc'd copy
of each message: reading at 918 Mbit/s took 98 % of a host core (9.0 ms of CPU per MiB). Several times that on the Frame's
cores would have cost 10 to 25 % of a core at film bit rates.

`build/libsmb2-patches/0001-signing-fast-aes-cmac.patch` (applied by the build script): the key is expanded once per
message, the CMAC runs over the message's pieces in place (no allocation, no copy), and the block cipher uses the CPU's AES
instructions: ARMv8 Crypto Extensions on aarch64, AES-NI on x86-64 (checked once at run time; else the old code). The
open log line names the one in use ("AES-CMAC signing with ARMv8 Crypto Extensions"). Checked against the RFC 4493 test
vectors and against the old code on 2000 random messages split at random points, on x86-64 (AES-NI and, under qemu
without AES, the fallback) and aarch64 under qemu (Crypto Extensions). Real signatures from the host verify. Result on the
host: 0.43 ms per MiB for the CMAC; reading the share takes 1.2 ms of CPU per MiB in all (socket reads included).

### Reading: SmbFile

- `MediaSource` gives FFmpeg a custom `AVIOContext` (256 KiB buffer, read and seek callbacks) over an `SmbFile`.
- `SmbFile` owns the connection and a thread of its own that reads ahead into a ring (`network_buffer_size`, 16 MiB by
  default): requests of 1 MiB (aligned, so none wraps), up to 4 in flight, read by libsmb2 straight into the ring. The demux
  thread's read callback copies from the ring into FFmpeg's buffer (the one copy) and blocks on a condition variable only
  when the data isn't there yet.
- 1/8 of the ring stays behind the read position for short backward seeks. A seek outside the ring drops the requests in
  flight (it waits for them to come back, since they write into the ring) and reads from there; the readahead then starts at
  256 KiB and doubles as the file is read on, so the demuxer's probing seeks at open don't fetch megabytes each.
- The thread waits in `poll()` on the socket and an eventfd (seek, space freed, close). It is woken about once per 1 MiB
  consumed, and wakes once a second when idle. No allocation per read.
- A lost connection: reconnect and reopen, 5 tries 0.5 s to 8 s apart, then read on where it stopped. After the last try
  the source goes to the error state with the reason. Test hook: `HWVIDEO_SMB_DROP_AFTER_MB=N` shuts the socket down once
  after N MiB.
- `close()` aborts every wait at once (the demux thread may be blocked in a read).
- Stats in `MediaSource.get_stats()`: `net_buffered_bytes` (ahead of the demuxer), `net_read_mbps` (while requests were in
  flight: the link's rate), `net_average_mbps`, `net_stalls` (waits while reading on: the network didn't keep up),
  `net_resets`, `net_reconnects`, `net_errors`, `net_thread_cpu_seconds`, and more; `main.gd` prints them every 2 s.

### Credentials and errors

- `set_smb_credentials(host, user, password, domain = "")`, static on `MediaSource` and `MediaBrowser` (one registry, keyed
  by host). Kept in memory only; not in paths, logs or errors (the tests check their logs for the password). Without an
  entry, libsmb2 logs in as guest. For a local account on the PC, the domain is the computer name, or empty, or the
  workgroup: all three worked here.
- Errors are sentences for the user: "Access denied: HOST refused the user name or password.", "HOST has no share named
  "X".", "Not found: share/path on HOST.", "Can't reach HOST: connection refused (is file sharing on, and port 445 open?).",
  "No answer from HOST within 8 s.", "Can't find the host NAME: the name doesn't resolve.".
- Connecting waits at most 8 s per step (`MediaBrowser.timeout`); a host name is resolved with `getaddrinfo()`, which can
  block for the resolver's own timeout.

### MediaBrowser

`list_shares(host)` (disk shares only: no printers, IPC$, `C$`, `ADMIN$`) over DCE/RPC on IPC$; `list_dir(path)` for
`smb://host` (its shares as folders), `smb://host/share/folder` and local folders, entries `{name, is_dir, size, mtime}`,
folders first, natural order; `get_last_error()`. One connection per object, kept while the host and share stay the same
(and replaced once, silently, if the server dropped it). The app's `scripts/net/directory_lister.gd` and
`fake_media_browser.gd` already use these calls.

### Results (2026-10-31; WSL x86-64 build, this PC's share over the WSL virtual network, not the Frame's Wi-Fi)

`demux-test/smb-tests.sh` (credentials from `~/.config/frame-player/smb-test.env`, never committed):

| Test | Result |
|---|---|
| MediaBrowser | all checks pass: 4 shares in 3 ms, the 92 films of Movies in 3 ms (1 ms on the kept connection), each error case with its sentence, a wrong password ("Access denied") and the right one again, `close()` during readahead 1 ms |
| The documentary MKV over SMB, full test | all checks pass: open 8 ms, the first 200 access units byte-identical to `documentary_sbs.h264`, the seek to 600 s on the same keyframe as the local file, audio, end of file, subtitles |
| Real time, 20 s from 120 s (audio through the AudioStreamPlayer, video taken by the audio clock) | 61.4 MiB read (25.8 Mbit/s), 0 network stalls, 0 audio underruns, never less than 12.4 MiB read ahead; readahead thread 0.38 % of a host core (1.25 ms per MiB), demux thread 0.56 % |
| Throughput, 8 s from 0 as fast as possible | 1347 MiB, 1412 Mbit/s (75 x the film's rate); readahead thread 1.32 ms of CPU per MiB, demux thread 0.33 ms per MiB |
| `project/main.gd` with the Frame's arguments (password file, `--smb-domain=` empty and the machine name; `--probe --media` and playback) | credentials registered, `open()` succeeds, no "Access denied", no unknown argument; without `--smb-user` the guest message; an unreadable password file stops with an error |
| Audio clock after `seek(30)` + `play(30)` (clock running) | 291 to 484 ms over SMB, 242 to 270 ms from the local file |
| Connection dropped after 400 MiB (`HWVIDEO_SMB_DROP_AFTER_MB=400`, during the throughput run) | reconnected after 0.5 s (first try) and read on from the same byte: 1 error, 1 reconnect, 0 demuxer read errors, the run went on at 930 Mbit/s; `close()` 6 ms |

### On the Frame (PLAYER_SMB2, Wi-Fi 6E to the PC's share; `results/run_smb_seeks.log`)

The device had kept the pre-SMB `main.gd`; with the current project the headless `--probe --media=smb://...` logs in
("16 characters", empty domain) and plays. The open log line says "AES-CMAC signing with ARMv8 Crypto Extensions".

| Measure | Result |
|---|---|
| Open, start | `open()` 75 ms; playback started 0.81 s after launch |
| 3 seeks of +600 s (`--seek-every=10 --seek-by=600`) | settled in 566, 1334 and 333 ms, 0 decoder errors (end-of-sequence NAL unit in its own buffer) |
| A/V offset | +2 to +40 ms |
| Network | 49 Mbit/s on average, 255 Mbit/s while reading; 14.4 to 14.7 MB read ahead in steady playback; 0 reconnects, 0 errors |
| CPU over the 40 s run | demux thread 0.5 s, decoder thread 0.2 s, readahead thread 0.4 s (about 1.7 ms per MiB read, 1 % of a core) |
| Stalls (old count) | 78 (2.3 s): 1 at the start, then 18, 51 and 8 in the 2 s windows of the three seeks, and none in about 30 s of steady playback |
| Audio underruns (old count) | 3, one per seek |

- The stalls were all refills after the start and after the seeks. The counters are split now: `net_stalls` and
  `net_stall_seconds` count only waits once the buffer has refilled (4 MiB ahead), `net_seek_waits` the waits in a refill,
  and `net_refill_mbps` is the read rate during refills.
- The underruns came at the seek itself, while the player was paused. `seek()` empties the ring, and the AudioServer applies
  `stream_paused` at its next mix, which can come just after that. A headless run with `main.gd`'s pattern over SMB
  (pause, seek, hold 570 ms, release) counted the underrun in the first 100 ms after the seek, none after the release (1 s
  of audio buffered by then). It was silent anyway (paused) and the position holds at the target, so it can't be heard,
  neither here nor in the app's seek path. An empty ring before the first frame after open or a seek now counts as
  `audio_seek_waits`, not as an underrun.
- Seek settle time follows the bytes from the keyframe before the target to the target, at the Wi-Fi read rate: seek 1 had
  124 frames before its target, seek 2 236 (9.8 s of video), seek 3 79, and they settled in 566, 1334 and 333 ms. The
  decoder needs all of those bytes, so reading ahead from the target can't shorten it. The ramp after a reset (from 256
  KiB) and waiting for the old requests (about one 1 MiB request in steady playback) cost tens of milliseconds at most.
  What would help is a higher read rate: 255 Mbit/s is below what the link should carry. `network_requests` (and
  `main.gd --net-requests=8`, `--net-buffer-mb=32`) is there to try more reads in flight.

### Not verified (needs the Frame)

- Whether more reads in flight raise the Wi-Fi read rate (and so shorten seeks).
- Real Wi-Fi drops and long pauses (a server may close an idle session; the reconnect covers it, but only the test hook
  exercised it).
- Other servers (Samba, NAS): share listing over DCE/RPC can be refused; then the user types the share name.

## UBWC capture (Q08C), an experiment (2026-10-31)

Fork commit `b9f0db12ce` on `frame/player`; Frame binary `build/out/godot.linuxbsd.template_debug.arm64.PLAYER_UBWC`
(sha256 `d6fe3e057a3c34921a9a845144e330b7ef9abe6264a51bbbe37a0a41e866c0ea`). It has everything PLAYER_SMB3 has. NV12
stays the default, so without the new option it plays exactly as before.

Why: with `Q08C` the decoder writes UBWC-compressed NV12 and the GPU samples it compressed, so both sides move fewer bytes.
Spike 01 measured the decoder ceiling: 264 against 258 fps at 3840x2160, 135 against 129 at 7680x3840, 123 against 118 at
8192x4096 (2 to 5 % more). The player had to refuse Q08C because the import didn't know the layout.

Layout. A Q08C CAPTURE buffer holds four regions, each padded to 4 KiB (iris `iris_yuv_buffer_size_qc08c()`):

| Region | Size (W x H = G_FMT width and height) |
|---|---|
| Y metadata | align(ceil(W/32), 64) x align(ceil(H/8), 16) bytes: one byte per 32x8 tile |
| Y | align(W, 128) x align(H, 32) |
| UV metadata | align(ceil(W/2/16), 64) x align(ceil(H/2/8), 16): one byte per 16x8 tile of CbCr pairs |
| UV | align(W, 128) x align(H/2, 32) |

The sum equals the device's `sizeimage` for all three spike 01 logs (3840x2176: 12,591,104; 7680x3840: 44,421,120;
8192x4096: 50,528,256). For `DRM_FORMAT_MOD_QCOM_COMPRESSED` Turnip wants two memory planes, each starting at its metadata
with its pixels after it (fdl6_layout: same tile sizes, same 64-byte and 16-row metadata alignment, metadata padded to
4 KiB, 128-byte pitch, 32-row height alignment). So V4L2Decoder gives plane 0 at offset 0 and plane 1 at the UV metadata,
both with pitch align(W, 128). It logs the four sizes and says MISMATCH if their sum isn't `sizeimage`.

The Turnip problem, and the workaround. The plane views (R8 for Y, R8G8 for CbCr) need `MUTABLE_FORMAT`. Turnip keeps UBWC
on a mutable image only if all its view formats compress alike, and R8 and R8G8 don't: with the format list
{NV12, R8, R8G8} it reports the modifier as unsupported (`tu_formats.cc`), and an NV12 image would fall back to linear
(`tu_image.cc`). With a single view format it keeps UBWC. So `DmabufImage.import_nv12()` first asks for the one image as
before; if the driver refuses it and the modifier isn't linear, it imports the dmabuf twice, as two images with the same
2-plane layout: one with the format list {R8} for the Y view (Turnip then samples plane 0 as `Y8_UNORM`, the Y plane's own
compression), one with {R8G8} for the CbCr view. Acquire and release make one ownership transfer per image.
`get_image_count()` says which happened.

Verified in WSL (lavapipe, x86_64 build): the two-image path with a host-memory test pattern (spike 02,
`--device=host-split --cycle`): the screenshot is byte-identical to the one-image path, and 149 release/acquire cycles
gave no errors in either. Lavapipe has no DRM modifiers, so the dmabuf import and UBWC itself were not run.

On the Frame (PLAYER_UBWC, the documentary MKV, 20 s each, logs `results/ubwc-NV12.log` and `results/ubwc-Q08C.log`): Turnip
accepts the two imports, and the Q08C screenshot is byte-identical to the NV12 one at the same frame (same MD5). Main
viewport GPU time 0.59 ms average / 0.60 ms max with Q08C against 0.63 / 1.46 ms with NV12; decode 24 fps and 0
decoder errors in both.

Q08C is the default `capture_format` since PLAYER_P010 (fork `e3694cc68e`). `--capture-format=NV12` still asks for linear
NV12. If the Q08C import fails, `HWVideoTexture` logs `Q08C (UBWC) import failed; reopening the decoder with NV12 at
T s`, reopens the decoder with NV12 once and seeks back to the same time. If the driver doesn't offer Q08C, it picks
NV12 itself (logged). Not yet run on the device: a long run with seeks and a resolution change on Q08C.

### Device A/B

Copy `project/main.gd` to the device with the binary: the option is new. Same file, same duration, once per format. With
`--audio-track=-1` the video runs on the frame clock, so both screenshots show nearly the same video frame. The screenshot
line prints the frame time of each:

```
for f in NV12 Q08C; do
  DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 ./godot.linuxbsd.template_debug.arm64.PLAYER_UBWC --path project --display-driver x11 --xr-mode off --verbose -- --no-xr --sbs --media=/path/to/Documentary.3D.Full-SBS.mkv --audio-track=-1 --capture-format=$f --gpu-time --screenshot=/tmp/ubwc-$f.png --screenshot-frame=600 --quit-after=1800 > ubwc-$f.log 2>&1
done
grep -E "QC08C layout|CAPTURE generation|imported .* decoder buffers|DmabufImage|ERROR|decode .* fps" ubwc-Q08C.log | head -30
```

What to look for:

- `QC08C layout: ...` without MISMATCH, then `HWVideoTexture: imported N decoder buffers ... Q08C (UBWC) ..., 2 Vulkan
  image(s) per buffer`. With `--verbose`, each import prints both images, with their memory plane offsets and pitches.
- Errors instead: `NV12 + modifier 0x500000000000001 + mutable format ... is not supported` means even the single-format
  images were refused. `VK_ERROR_INVALID_DRM_FORMAT_MODIFIER_PLANE_LAYOUT_EXT` means Turnip disagrees with the offsets or
  pitches. `The dmabuf holds N bytes, but the image needs M` means Turnip's layout is larger than iris's.
- The picture, against the NV12 screenshot at the same frame: identical or nearly so (the GPU decompresses losslessly).
  Blocky noise in 32x8 or 16x8 tiles means the metadata is misread. Right luma with wrong colours means the CbCr plane is
  wrong. A shift means the plane 1 offset is wrong.
- The 2 s lines, NV12 against Q08C: decoder CPU and latency, decode fps when it can't keep up, and `GPU x ms avg` (the
  main viewport's GPU time, which includes sampling the video). The power spike (`spikes/04-power`) can compare battery
  drain.

## 10-bit, VP9 and other formats the hardware path can't show (2026-10-31)

Fork commit `50e9a68f38`; Frame binary `build/out/godot.linuxbsd.template_debug.arm64.PLAYER_10BIT` (sha256
`fb9a21f9e26261f1a45ad13f1f7b2b1bc32a5f051d51cc33610ac7ab5294339f`). Includes the merged `modules/x11window`.

The user's 10-bit HEVC files (for example a 3832x1596 `yuv420p10le` Main 10 file) played with wrong colours: the decoder
was asked for NV12, which iris accepts for 10-bit and fills with the low 8 bits of each sample (spike 01). Now:

- `MediaSource.get_video_info()` has `hw_unsupported_reason`, one sentence for the user, next to `hw_decodable`. VP9:
  refused by policy, not by the driver (the device isn't opened): SteamOS #2865 reports that the second and later VP9
  sessions after boot crash the decoder firmware, and that killing the stuck process can restart the headset. AV1: not
  exposed by the kernel. 10-bit: "not supported yet on this kernel". 4:2:2 and 4:4:4: not decoded. (Since PLAYER_VP9,
  VP9 plays in hardware, one session at a time: "Hardware VP9" below.)
- `V4L2Decoder.open_source()` refuses with the same sentence before opening the device, and at CAPTURE setup it fails
  on any format `HWVideoTexture` can't show instead of showing garbage. For a 10-bit stream it logs the CAPTURE formats
  the driver offers. Spike 01's Main10 log lists only `Q10C`, so P010 isn't offered on 6.18; the log line re-checks it.
- Verified in WSL (x86 build, `MediaSource` + `V4L2Decoder.open_source()`): the 2160p and 720p 10-bit HEVC files and a
  VP9 WebM are refused with the reason and `hw_decodable` false; an 8-bit H.264 file passes the check (and then fails only
  for want of `/dev/video-dec0`).

### Q10C, an experiment (`V4L2Decoder.experimental_10bit`, `main.gd --10bit`)

Turnip has no TP10 format (the hardware has `FMT6_TP10`, Mesa doesn't use it), and its P010 is 16-bit samples, not TP10.
But each plane of a Q10C buffer is laid out exactly like a UBWC image of a 32-bit format, a third of the width: TP10
packs three 10-bit samples in a 32-bit word, iris's tiles are 48x4 samples (16x4 words, the 32-bit UBWC tile), metadata
rows are 64 bytes in 16-row units, the pitch is W x 4/3 aligned to 256 and heights are aligned to 16 (fdl6 for 32-bit:
the same). The layout formula matches the device's `sizeimage` for 7680x3840 (59,260,928). And the A750 is
`ubwc_all_formats_compatible`: Mesa notes that it "added a special flag that allows HW to correctly interpret UBWC ... when
casting image to a different format" (the descriptors' MUTABLEEN bit, set for mutable images). So whether the texture
unit decompresses video-written TP10 correctly when it reads it as a 32-bit format is worth one device run.

`DmabufImage.import_planes()` imports each plane as its own single-plane image (one memory plane: metadata, then
pixels). `HWVideoTexture.q10c_view` picks the format: `rgb10a2` (the three samples are r, g, b), `rgba8` (the shader
rebuilds the word from the bytes), each optionally `_mutable` (mutable to R32_UINT, another UBWC class, which sets
MUTABLEEN; Turnip's format query refuses that list with the UBWC modifier, so it's created anyway). `get_packing()` tells
the shader; `video.gdshader` unpacks with `texelFetch` (nearest, BT.709; enough to judge correctness, not final quality).

Device run (copy `project/main.gd` and `project/video.gdshader` too). One run per variant; a wrong guess can show garbage
or, at worst, fault the GPU (the image stays inside the buffer, so no out-of-bounds access):

```
F=/path/to/Comedy.2160p.10bit.SDR.mkv
# 1. The refusal (no --10bit): expect "10-bit video is not supported yet on this kernel ..." and no picture.
DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 ./godot.linuxbsd.template_debug.arm64.PLAYER_10BIT --path project --display-driver x11 --xr-mode off -- --no-xr --media=$F --quit-after=200 2>&1 | grep -iE "10-bit|error" | head
# 2. The four Q10C variants, a screenshot each.
for v in rgb10a2_mutable rgb10a2 rgba8_mutable rgba8; do
  DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 ./godot.linuxbsd.template_debug.arm64.PLAYER_10BIT --path project --display-driver x11 --xr-mode off --verbose -- --no-xr --media=$F --start=600 --audio-track=-1 --10bit --q10c-view=$v --screenshot=/tmp/q10c-$v.png --screenshot-frame=300 --quit-after=400 > q10c-$v.log 2>&1
  grep -E "CAPTURE formats offered|QC10C layout|imported .* decoder buffers|DmabufImage|ERROR|decode .* fps" q10c-$v.log | head -12
done
```

Device result (PLAYER_10BIT, the 3840x1600 file over SMB, `results/q10c-*.log` and `.png`):

- `CAPTURE formats offered for this 10-bit stream: Q10C`: P010 isn't offered on the 6.18 kernel. The layout formula
  matched `sizeimage` (12,369,920), and Turnip accepted every import (also the mutable ones its query refuses).
- `rgb10a2*`: never sampled. Godot's `texture_rd_create()` has no `Image` format for A2B10G10R10, so the plane textures
  weren't made ("Unsupported image format"); the screenshot is a flat colour. RGBA8 is the only 32-bit format it wraps.
- `rgba8*`: decodes at 24 fps without errors, but the picture is fine-grained colour noise in which the coarse shapes
  of the scene can be made out. Either the words are right and reordered inside each tile (fixable in the shader), or
  the texture unit decompresses the video core's TP10 differently (a dead end). The plane dump below tells which.

Verdict (screenshots inspected on the PC, 6x zoom and pixel correlations, `results/q10c-rgba8*.png`): the noise is per
texel, not per tile. Neighbouring pixels correlate weakly at every distance from 1 to 64 pixels, horizontally and
vertically, and no 48x4 or 16x4 structure shows. Only flat areas of the scene come out coherent. Words that were right
but reordered inside a tile would keep each tile's local statistics and show the tile grid; this doesn't. So the texture
unit most likely decompresses the video core's TP10 differently from how it was written, and Q10C is a dead end with
Turnip's formats. 10-bit goes to P010 (a patched iris module, below) or to software decode. The experiment stays in the
code behind `--10bit`.

The plane dump confirms it. `--dump-planes=PREFIX` saves both planes exactly as the GPU reads them; the dump is
lossless and was checked bit-exact against an FFmpeg decode on the software path. `tools/q10c_analyze.py` compares
the words with a reference decode of the same frame; it runs on the PC, needs numpy and Pillow, and `--selftest`
checks it. The device run used PLAYER_10BIT2, the 3832x1596 Main 10 file from 600 s, and the frame at 602.811 s, with
`rgba8` planes of 1280x1600 and 1280x800 words. The reference came from FFmpeg's hevc decoder on the PC
(`tools/decode_frame.c`, yuv420p10le, the same frame time):

| Plane | Same word, same place | Top 2 bits zero | Found in the same 16x64-word block |
|---|---|---|---|
| Y | 0.00 % | 23.4 % | 0.0 % |
| CbCr | 0.00 % | 9.7 % | 0.0 % |

TP10 words always have their top 2 bits zero; random words have them zero 25 % of the time. So what the texture unit
returns is not TP10 data in any order: the values are wrong, not permuted, and no shader change can fix them. Q10C is
closed. The self-test finds 100 % of a permuted test frame and 0 % of a garbage one.

Expect `CAPTURE formats offered for this 10-bit stream: Q10C` (anything else, P010 especially, is news),
`QC10C layout: ...` without MISMATCH (3840x1600: the width is rounded up to 192), then the import line per variant. In
the screenshots: a correct picture means that variant works; blocky noise in 48x4-sample tiles means the texture unit
reads the compressed data differently from how the video core wrote it; a clean but scrambled picture (stripes, wrong
order of samples) means the decompression works and only the unpacking in the shader is wrong (fixable here).

## Software decode fallback (2026-10-31)

Fork commit `d24cc90744`; Frame binary `build/out/godot.linuxbsd.template_debug.arm64.PLAYER_10BIT2` (sha256
`47aef4cd505ebe3f2b0043795a12f511dc2e1378e01a27fd63205ce45ed2e8f9`). FFmpeg now also has the h264, hevc and vp9 decoders
(`build/ffmpeg-build.sh`; NEON, dotprod and i8mm on aarch64; still LGPL).

`HWVideoTexture.open_source()` decodes in software what the hardware path can't show, if it is H.264, HEVC or VP9 of at
most 1920x1088 (`software_max_pixels`): VP9 (firmware crashes; since PLAYER_VP9 only a second VP9 session, see "Hardware
VP9"), 10-bit HEVC (Q10C), H.264 High 10, 4:2:2. Larger ones
are refused with both reasons. `SoftwareVideoDecoder` runs FFmpeg with 4 frame/slice threads (`software_threads`) on a
thread of its own that blocks on an eventfd (the source's packets, returned slots, close), converts each frame to 8-bit
NV12 into one of 8 fixed slots, and `HWVideoTexture` uploads only the frame it shows into one R8 and one R8G8 texture.
Clock, settle after seeks, drops, plane textures, `format_changed` and the stats keys are those of the hardware path,
so the app and the NV12 shader need no change; `get_stats()["decode_path"]` is `"software"` and
`get_video_info()["software_decodable"]` says so before opening. 10-bit is rounded to 8 bits; HDR (PQ) isn't tone-mapped.

Verified in WSL (x86_64, FFmpeg without asm, lavapipe): a 1080p VP9 WebM and the 720p 10-bit HEVC file `Feature.720p.10bit.mkv` play
(decode 30 fps), with the right picture; 3 seeks settled in 77-160 ms with 0 errors; the end of the stream is reported
(state `ended`). The plane dump of a software frame is bit-exact against an FFmpeg decode of the same frame. Not measured:
the Frame's CPU cost, which is the point of the device run.

Device run (copy `project/main.gd` too; the 2 s line now has `process CPU N% of a core` and `SOFTWARE decode (...)`):

```
for f in "/path/to/a 1080p 10-bit HEVC.mkv" "/path/to/Feature.720p.10bit.mkv" "/path/to/a VP9 file.webm"; do
  DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 ./godot.linuxbsd.template_debug.arm64.PLAYER_10BIT2 --path project --display-driver x11 --xr-mode off -- --no-xr --media="$f" --start=600 --seek-every=20 --seek-by=60 --quit-after=3600 2>&1 | grep -E "software|SOFTWARE|Seek .* settled|decode .* fps|ERROR" | cut -c1-420
done
```

For a baseline, the same line for an 8-bit hardware file gives the process CPU without software decode.

Device result (PLAYER_10BIT2, `results/run_sw_10bit_cpu.log`): `Comedy.1080p.10bit.DTS-HD.mkv` (1080p 10-bit HEVC over SMB) played 60 s at
a steady 24 fps with 0 dropped after the first 2 s and 0 decoder errors. The 720p 10-bit file played too, and the user
judged both pictures right. The CPU field was cut off in the log; that rerun is on the morning list.

Seeks: the first seek in the 1080p file took 1767 ms, the second 501 ms. The "skipped so far" counts are cumulative, so the
first seek decoded 189 frames for nothing (7.9 s from the keyframe to the target) and the second 49. Both work out at
about 100 fps of catch-up, while the SMB refills ran at 185 to 200 Mbit/s against a file of about 10 Mbit/s. So the
decoder was the limit, not the network. Since PLAYER_FEATURES2 (fork `e080a5edfb`), the software decoder skips the
pictures nothing refers to (FFmpeg's `skip_frame = AVDISCARD_NONREF`, mostly B-frames) until two frames before the
target. On x86 with the same file, a seek 7 s past a keyframe settled in 1656 ms instead of 2877 ms, and others in
113 to 192 ms instead of 539 to 996 ms. Pictures decoded for nothing fell from 459 to 108 over six seeks.
`HWVIDEO_SW_SEEK_NONREF=0` turns it off for an A/B run on the device.

## 10-bit in hardware: P010 (2026-10-31)

Fork commit `e3694cc68e`; Frame binary `build/out/godot.linuxbsd.template_debug.arm64.PLAYER_P010` (sha256
`2c3e2f7ab2bdebc3169fc8003e29411f559e1a88b1d4b820b0b416f3f0b23c2f`). It also carries everything before it: the
`modules/x11window` merge, SMB, the software fallback and Q08C as the default.

For a patched iris module that offers linear P010 CAPTURE (16-bit samples, the 10 bits in the high bits, chroma after
luma in one buffer). `V4L2Decoder` asks for P010 for a 10-bit stream when the driver lists it. The pitch is
`bytesperline`, and the chroma offset is `bytesperline` times the height rounded up to 32 lines, as mainline iris lays
it out. `capture_chroma_offset` (`main.gd --chroma-offset=N`) overrides the offset. The decoder logs `P010 layout:
pitch P (luma row B bytes), chroma at C, sizeimage S`, with `DOESN'T FIT` if that layout overruns `sizeimage`.
`DmabufImage.import_p010()` imports the buffer as `G10X6_B10X6R10X6_2PLANE_420_UNORM_3PACK16` with the LINEAR modifier
(UBWC too, if a compressed 10-bit format ever turns up), with R16 and R16G16 plane views. `HWVideoTexture` reports
`PACKING_P010`. The shader reads `.r` and `.rg` and picks BT.709, BT.2020 or BT.601 from `MediaSource.get_video_info()`
(new keys `color_matrix`, `color_range`, `color_transfer`, `matrix_bt2020`, `full_range`, `hdr`). HDR (PQ, HLG) is not
tone-mapped yet.

Routing. `V4L2Decoder.is_p010_available()` opens the device once at idle, sets an HEVC OUTPUT format and lists the
CAPTURE formats. The answer goes into `hw_decodable`. With P010, 10-bit HEVC goes to the hardware path; without it, to
software decode (up to about 1080p). A 10-bit stream's own format list corrects the cached answer, because the idle list
may not show 10-bit formats at all. `HWVIDEO_P010=1` or `0` in the environment forces the answer.

Verified in WSL (x86_64, lavapipe): spike 02's `--device=host-p010` and `host-p010-split` import the P010 test
pattern as one and as two images, with 149 release/acquire cycles and no errors. The screenshots match the NV12 ones
(off by at most 1 in flat areas; up to 7 only on bar edges, where 16-bit filtering is finer). The 720p 10-bit file goes
to software without P010 and with `HWVIDEO_P010=0`, and to the hardware path with `HWVIDEO_P010=1`. Not run: the
P010 import of a real dmabuf, which needs the Frame and the patched module.

Device test plan. First, with the stock module, run the 8-bit documentary file once (expect `imported N decoder buffers ...
Q08C (UBWC)` with no flag) and a 10-bit file once (expect `linear 10-bit (P010) not available` and `software decode`).
Then load the patched module and run the 720p 10-bit file three ways, a screenshot each at the same frame. First with no
variable: expect `P010 available` at idle, `CAPTURE formats offered for this 10-bit stream: ... P010`, the P010 layout
line without `DOESN'T FIT`, and `imported N decoder buffers ... P010`. Second with `HWVIDEO_P010=0`, the software
reference. Third with `HWVIDEO_P010=1`, only if the first run said not available at idle. The P010 screenshot should
match the software one closely (the software path rounds to 8 bits). A vertical shift or wrong colours below a line
means the chroma offset is wrong: rerun with `--chroma-offset=` set from the kernel agent's layout. Finally, play the
2160p 10-bit file, which is too big for software decode, and watch the 2 s lines for decode fps and GPU time.

```
F=/path/to/Feature.720p.10bit.mkv
for p in "" 0 1; do
  env ${p:+HWVIDEO_P010=$p} DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 ./godot.linuxbsd.template_debug.arm64.PLAYER_P010 --path project --display-driver x11 --xr-mode off --verbose -- --no-xr --media="$F" --start=600 --audio-track=-1 --gpu-time --screenshot=/tmp/p010-${p:-auto}.png --screenshot-frame=300 --quit-after=400 > p010-${p:-auto}.log 2>&1
  grep -E "CAPTURE formats|P010 layout|imported .* decoder buffers|software decode|Colour:|ERROR|decode .* fps" p010-${p:-auto}.log | cut -c1-300 | head -12
done
```

## Engine features for the app (2026-10-31)

Fork commit `6b7f34ddbc`; Frame binary `build/out/godot.linuxbsd.template_debug.arm64.PLAYER_FEATURES` (it also
carries everything of PLAYER_P010). The engine side of ideas from `docs/ideas.md`; the app wires them up. The class
reference (`modules/hwvideo/doc_classes`) has the details.

- **Chapters (#15).** `MediaSource.get_chapters()` gives index, start, end and title per chapter, in media seconds.
  `get_chapter_at(t)` gives the chapter playing at t. `get_info()` has them too. Of the local films, the Blu-ray rips
  have 12 to 55 chapters each, and the web rips have none.
- **Container stereo and spherical metadata (#25).** `get_video_info()` has `stereo_mode` ("sbs", "tb", "2d", ...),
  `stereo_inverted`, `projection` ("equirectangular", ...), `projection_fov` (360x180, or 180x180 for VR180),
  `projection_bounds` and `projection_yaw_pitch_roll`. Empty means the container says nothing, and the app falls back
  to the file name. The half-SBS animated MKV reports "sbs" from its StereoMode; the documentary MKV says nothing.
  FFmpeg's MP4 muxer writes Apple's vexu box next to st3d and sv3d, and its reader lets vexu win. Such files report
  "unspecified" (two views, packing not given) and lose the yaw of a full sphere. MP4s with only st3d/sv3d, as Google's
  tools write them, read fine.
- **Subtitle files next to the video (#50).** `MediaBrowser.find_subtitles(video)` lists the files, local or over
  SMB: those named after the video, all of them in a folder with one video, and those in a Subs folder.
  `parse_subtitle_name()` reads the language, forced and SDH from a name such as `Film.en.forced.srt`, `2_English.srt`
  or `Film.pt-BR.srt`. `MediaSource.add_external_subtitle(path)` loads a file as one more subtitle track; SubRip, ASS
  and WebVTT are supported. The text may be UTF-8, UTF-16 with a byte order mark, or Windows-1252. Its events come all
  at once, and again from the target after a seek.
- **Subtitle delay (#61).** The app applies the delay when it shows the lines, as `scripts/play/subtitles.gd` does.
  A negative delay needs lines earlier than the demuxer reads them, which is about 1 s ahead.
  `MediaSource.subtitle_read_ahead` reads the video that much further ahead while a subtitle track of the file is
  selected. The limit is about 20 s at 24 fps, because the queue holds at most 512 packets. Subtitle files don't need it.
- **Language memory (#28).** `MediaSource.normalize_language()` maps "ger", "deu", "German" and "de" to "de", and
  keeps regions ("pt-br"). `pick_audio_track(languages)` and `pick_subtitle_track(languages, forced_only)` return the
  best track for a preference list, or -1. Commentary and audio description lose ties. For subtitles, text beats
  bitmap, and full tracks beat forced ones. Track dictionaries gain `language_code`, `commentary`, `visual_impaired`,
  `hearing_impaired` and `external`.
- **Playback speed with the pitch kept (#69).** `MediaSource.playback_speed` takes 0.5 to 2. A WSOLA time stretch in
  the mixer (`AudioTempo`) reads the audio ring faster or slower. The audio clock follows, and the video follows the
  audio. On x86 it costs about 3 ms per second of output, and speed 1 costs nothing extra.
  `HWVideoTexture.playback_speed` sets the frame clock when there is no audio.
- **Stats for the overlay (#57).** `HWVideoTexture.get_overlay_stats()` returns a dictionary meant for once or twice a
  second. It has the decode path and stream, the bitrate now and for the last 60 s, and the queue depths from the
  network buffer to the screen. It also has decode, shown and dropped rates, process CPU, and
  `get_system_stats()`: GPU clock, temperatures and battery power from sysfs. `MediaSource.get_video_bitrate_history()`
  gives the bitrate graph alone. A frame-time histogram stays in the app (`Performance`).

Verified in WSL (x86_64): `demux-test/features_test.gd` passes all 265 checks, on files from
`demux-test/make-feature-files.sh`. Those are 30 s cuts with stereo, VR180, 360 and chapter metadata written by
`demux-test/tools/meta_remux.c`, subtitle folders in five encodings and formats, and a stepped-tone AVI. The checks
cover chapters, metadata, file finding and name parsing, events and seeks of subtitle files, language picks,
read-ahead, bitrate, overlay keys, system stats from a fake sysfs tree, and speed. The speed test plays 1.0, 1.5, 0.75
and 2.0. It checks the clock to within 30 ms, and checks that the tone heard is the one at the input position at its
own pitch. The 13 files of `run-tests.sh` still pass. The spike prints the overlay dictionary with `--overlay-stats`;
on lavapipe it showed decode at 24.5 fps, shown at 24.0 fps, and the bitrate history filling.

```
wsl -d Ubuntu -- bash spikes/03-player/demux-test/make-feature-files.sh
cd spikes/03-player/demux-test && godot --headless --path . --script features_test.gd [-- --films]
```

Needs the device: `get_system_stats()` on the Frame's real sysfs (which devfreq entry is the GPU, the zone names, and
whether the battery has power_now), playback speed with the hardware decoder at 1.5x on a 4K file, and the overlay
numbers during hardware playback.

### Subtitle pictures and styles (#67)

Fork commit `153727c6ce`; Frame binary `build/out/godot.linuxbsd.template_debug.arm64.PLAYER_SUBS`. FFmpeg now has
the pgssub, dvdsub, dvbsub and xsub decoders (`build/ffmpeg-build.sh`). There is no libass.

- **Bitmap tracks** (PGS from Blu-ray rips, VobSub, DVB, XSUB) are decoded to pictures. Each event of
  `read_subtitle_event()` has `images`: a rect, an RGBA8 `Image` of that size and a forced flag. `canvas_size` is the
  space the rects are in, usually the video's size. An event without images clears the screen from its start. PGS
  sends one after each picture, and gives no end times. Track dictionaries gain `bitmap_decoded`.
- **Text tracks** gain `styled`: one dictionary per ASS line of the event. Each has runs of text with font, size,
  colour, outline, bold, italic, underline and strike-out, plus the alignment (numpad 1-9), `\pos`, the margins and the
  script resolution they are in. SubRip's `<b>`, `<i>` and `<font color>` arrive as ASS tags, so SubRip gets the same
  treatment. Karaoke, transforms, moves, clips and drawings are dropped. `MediaSource.parse_ass_event(line, header)`
  parses one line the same way.

On the 3D rips the pictures hold both eyes' captions, side by side, because the discs carry them that way. Draw the
picture over the whole video frame before the eye split, and each eye gets its own caption. Over 90 s from 600 s:

| File | Track | Events | With pictures | Clearing |
|---|---|---|---|---|
| Animated Feature 2 (PGS) | 1 | 47 | 24 | 23 |
| Animated Feature 3 (PGS) | 0 | 51 | 25 | 26 |
| Documentary (VobSub) | 0 | 14 | 14 | 0 |

All three had a 1920x1080 canvas and no decode errors. `features_test.gd` now runs 321 checks and all pass. The new
ones cover the three films, `parse_ass_event()` on SSA and ASS headers and on lines without a header, and
`demux-test/make-feature-files.sh`'s `styled/` SubRip and ASS files through `read_subtitle_event()`.

Needs the device: the conversion cost on the Frame. It is one pass over each picture's pixels, when its event is
read, about once a second at most.

### Night mode and dialogue boost (#26)

Fork commit `0178dc9a02`; Frame binary `build/out/godot.linuxbsd.template_debug.arm64.PLAYER_NIGHT`.

- **`MediaSource.night_mode`** turns loud passages down and quiet ones up. AC-3 and E-AC-3 tracks use the decoder's
  own DRC from the stream (`drc_scale`). Every track also goes through a compressor after the downmix
  (`audio_dynamics.cpp`). It learns the film's typical level over about 5 s and levels it towards -24 dBFS. It
  compresses 5:1 above that level and gently lifts passages well below it. A limiter keeps peaks under -1 dBFS.
  `night_mode_strength` (0 to 1) scales the decoder's DRC, the ratio and the boost.
- **`MediaSource.dialogue_boost`** (0 to 12 dB) raises the centre channel in the stereo downmix. It works only for
  audio with a centre channel; the stats say so in `dialogue_boost_applies`.
- All three can change while playing. A change is heard after the audio queue (about 1 s), or at once after a seek.

The decoder's DRC alone is not enough. Of ten AC-3 and E-AC-3 films here, six carry no DRC data at all. In the other
four of the films tried, full DRC lowers the average level by 0.7 to 3.5 dB. That was measured
with a small C program on the same FFmpeg build. That is why the compressor runs on every codec.

A bug found on the way: FFmpeg's AC-3 decoder clears its whole context when flushed, options included. So the
`drc_scale`, `target_level` and any `audio_decoder_options` were lost at the first seek. MediaSource now sets them again
after every flush. Without night mode `drc_scale` is now 0 everywhere (the full range, as mpv plays it). Before, it was
FFmpeg's 1 until the first seek and 0 after.

The spread between the 10th and 95th percentile of 400 ms levels, over 60 s from 600 s, in the stereo downmix:

| Film | Off | Night mode | Peak off | Peak on |
|---|---|---|---|---|
| Film D (DD 5.1) | 24.0 dB | 14.5 dB | -8.6 dBFS | -7.1 dBFS |
| HDR film A (DD 5.1) | 15.3 dB | 7.8 dB | -18.3 dBFS | -8.5 dBFS |
| Film B (DD+ 5.1) | 23.5 dB | 8.2 dB | +2.4 dBFS | -11.2 dBFS |
| Film C (AC-3 5.1) | 33.8 dB | 14.0 dB | -1.8 dBFS | -6.1 dBFS |
| Animated Feature 2 (DTS-HD MA 5.1) | 23.2 dB | 11.2 dB | +2.1 dBFS | -11.0 dBFS |

The demux thread's CPU time did not change measurably on x86. The compressor does a few multiply-adds per sample, and
two logs and an exp per 32 frames. `features_test.gd` now runs 338 checks and all pass. The new checks use
`dyn_steps.avi` (2 s at -6 dBFS and 2 s at -36 dBFS in turn) and `centre_51.avi` (a tone in the centre, another in
the fronts). They show the following:

- **Night mode:** loud and quiet end up 17.7 dB apart instead of 30, and no peak exceeds -1 dBFS.
- **Switching on while playing:** it works.
- **Dialogue boost:** a boost of 6 dB or 12 dB raises the centre by 6.0 dB or 12.0 dB against the fronts.
- **AC-3 options:** they survive a seek.

Needs the device: listen at low volume. Dialogue must stay clear and explosions must not jump out. There must be no
pumping on music.

### Discrete channels (#21, #47 groundwork)

Fork commit `59676f3368`; Frame binary `build/out/godot.linuxbsd.template_debug.arm64.PLAYER_CHANNELS`.

- **`MediaSource.discrete_channels = true`** (before `open()`) keeps the audio as 7.1 float as well as stereo.
- **`get_audio_channel_stream(n)`** returns an `AudioStreamMedia` that plays channel n as mono, for one
  `AudioStreamPlayer3D` per virtual speaker.
- **`get_audio_channels()`** lists the eight slots and which ones the track has.

The channel order is FFmpeg's 7.1 order:

| Index | Name | Channel |
|---|---|---|
| 0 | FL | front left |
| 1 | FR | front right |
| 2 | FC | front centre |
| 3 | LFE | low frequency |
| 4 | BL | back left |
| 5 | BR | back right |
| 6 | SL | side left |
| 7 | SR | side right |

A 5.1 track fills either the back pair (FFmpeg's "5.1") or the side pair ("5.1(side)", most Blu-rays). An app that
places five speakers should take whichever pair is present. Layouts with other channels, such as 7.1(wide), are mixed
into the nearest of the eight.

How it works:

- **One resampler.** It makes 7.1 into a second ring beside the stereo one. The stereo mix is the engine's downmix of
  the same frames, so nothing is resampled twice.
- **Matching gain.** The dialogue boost raises FC itself. Night mode's gain is applied to the channels frame by frame.
- **Shared reads.** The stereo stream and any channel streams can play together. All readers in one audio mix step
  read the same frames, and the clock moves once per step.
- **Speed.** At a playback speed other than 1, only the stereo stream plays.

Desktop results:

- **Tests.** `features_test.gd` now runs 373 checks and all pass. Each of the six channels of `channels_51.avi` (one
  tone per channel) comes out alone and at its level. The stereo mix equals the downmix of the channel streams to
  within 2e-8, with and without night mode, and matches the stereo of a source without discrete channels. Channel
  streams alone keep the clock and play continuously. The 13 files of `run-tests.sh` still pass.
- **Cost.** On Animated Feature 2 (DTS-HD MA 5.1), the demux thread used 0.51-0.54 s per minute of audio with discrete channels
  and 0.46-0.47 s without, on x86.

Needs the device: eight `AudioStreamPlayer3D` speakers on a 5.1 film. Check that the voices come from the centre and
the surrounds from behind. Check the CPU use of the audio server with eight 3D players.

### HDR metadata and tone mapping (#85)

Fork commit `015fc1857b`; Frame binary `build/out/godot.linuxbsd.template_debug.arm64.PLAYER_HDR`.

- **`get_video_info()`** gains `hdr_transfer` ("pq", "hlg"), `max_cll`, `max_fall`, `mastering_display_primaries`,
  `mastering_display_luminance`, `hdr_metadata_source`, `dolby_vision_profile` and `hdr10plus`.
- **Where the metadata comes from.** Nine of ten HDR films here carry it only in the HEVC bitstream (SEI), not in the
  Matroska header. So for PQ and HLG video without it, `open()` reads up to the first keyframe and parses its SEI.
  That took 5 to 37 ms on the local films.
- **`MediaSource.get_tone_mapping(video_info, target_nits = 203)`** returns what a shader needs: the gamut matrix to
  BT.709, the PQ and HLG constants, and the BT.2390 EETF parameters (source peak from MaxCLL or the mastering
  display). The class reference spells out the per-pixel steps.
- **`tone_map_color()`** does the same on the CPU, for tests.
- **The spike's shader** (`project/video.gdshader`) does it in GLSL. Its options are `--hdr-target=NITS` and
  `--no-tone-map`.

What `get_video_info()` reports, checked against FFmpeg's HEVC decoder on the first frame:

| Film | Source | Mastering display | MaxCLL / MaxFALL | Tone mapped from |
|---|---|---|---|---|
| `HDR.A.1080p.mkv` | SEI | P3, 0.005-1000 nits | not given | 1000 nits |
| `HDR.B.1080p.mkv` | SEI | P3, 0-1000 nits | 482 / 224 | 482 nits |
| `HDR.C.2160p.mkv` | SEI | P3, 0.005-1000 nits | 989 / 135 | 989 nits |
| `HDR.DV.1080p.mkv` (Dolby Vision 8) | container | P3, 0.005-4000 nits | 3471 / 99 | 3471 nits |
| `HDR.D.2160p.mkv` | SEI | BT.2020, 0.0001-1000 nits | not given | 1000 nits |

HDR films A and B were played through the software path on lavapipe at 1080p, with and without tone
mapping. With it, skin tones and the film's grade look right. Without it, the PQ code values shown as SDR are grey and
flat (the screenshots are not kept: they are frames of a commercial film). HDR film C is 2160p, too
big for the software path, so only its metadata was checked. Dolby Vision and HDR10+ are reported but not used: the
base layer plays as HDR10.

`features_test.gd` now runs 412 checks and all pass. The helper checks are:

- **Gamut matrices.** BT.2020 and P3 to BT.709 match ITU-R BT.2087 to within 0.001.
- **PQ.** The test's own copy of SMPTE ST 2084 agrees with the engine's.
- **Curve shape.** The curve rises everywhere, keeps greys below the knee, and maps the source peak to 1.0.
- **Hue.** The EETF keeps the hue.
- **Other transfers.** HLG and SDR give the expected values.

The 13 files of `run-tests.sh` still pass.

Needs the device: the shader cost of the PQ curve per pixel at 4K on the Frame's GPU, and how bright 203 nits looks in
the headset. The app may want a brightness setting that changes the target.

### Inputs: HTTP, HTTPS, live streams, music files (#86, #88, #64)

Fork commits `5997ea5369` and `8ac5e35f43`; Frame binary `build/out/godot.linuxbsd.template_debug.arm64.PLAYER_INPUTS`.

- **URLs in `MediaSource.open()`.** It now takes `http://`, `https://` and `udp://` as well as `smb://`. A new reader
  (`net_stream.cpp`) reads them on its own thread into a ring, as the SMB reader does. FFmpeg stays built without
  network code.
- **HTTP and HTTPS files.** Range requests make them seekable like a local file. Redirects, chunked replies and lost
  connections are handled. A server without Range support plays from the start and can't seek. HTTPS uses Godot's
  TLS with the system's CA store. `network_tls_verify = false` accepts a self-signed server on the local network.
- **Live streams.** These are MPEG-TS over UDP (unicast or multicast) and HTTP without a length. `is_live()` is true
  and `seek()` refuses. `live_latency` (default 0.5 s, at most 2.5 s) is the audio buffered before playing, at the
  start and after an underrun. A reader more than twice that behind skips ahead to the newest data.
- **Music files.** MP3, FLAC, Ogg, WAV, AAC/M4A, ALAC, AC-3, DTS and TrueHD play without video; the audio is the
  clock. A cover picture is never taken for the video. `get_album_art()`, `get_attached_pictures()` and `get_tags()`
  return the cover and the tags.

`features_test.gd` now runs 490 checks and all pass. It serves the test files with `tools/stream_server.py` and checks:

- **HTTP and HTTPS.** The packets are the same as from the local file, before and after a seek. Redirect and 404
  work. HTTPS with a self-signed certificate is refused with verification on and plays with it off.
- **Live HTTP and UDP.** About 4 s of media arrive in 4 s. Playback starts at a keyframe. A stream left unread for
  4 s skips ahead. The clock holds until the pre-roll is buffered.
- **Music.** M4A and FLAC with a cover and tags, WAV, and a raw AC-3 clip. MP3 and Ogg are not tested: the tool build
  of FFmpeg has no encoder for them.

The 13 files of `run-tests.sh` and the SMB tests still pass.

Cost on the host, 20 s at real time with `stream-tests.sh` (the reader thread is the new one):

| Input | Open | Reader thread CPU | Reader wake-ups |
|---|---|---|---|
| Local file, 2.4 Mbit/s | 11 ms | none | none |
| HTTP file, 2.4 Mbit/s | 14 ms | 0.010 s | 516 |
| HTTP file, 22 Mbit/s | 66 ms | 0.040 s | 897 |
| Live HTTP, 2.4 Mbit/s | 727 ms | 0.073 s | 1033 |
| UDP, 2.4 Mbit/s | 1478 ms | 0.088 s | 2048 |

The UDP thread takes all queued datagrams per wake-up, then waits 10 ms. At 19 Mbit/s that cut wake-ups from 29894
to 1720 in 15 s, with no datagram lost. A live reader that ran dry is woken for 32 KiB or after 20 ms, not for each
datagram.

Opening a live stream mid-way waits for the next keyframe, because the decoder can't start without one. Live TV sends
one every 0.5 to 2 s. The test file has one every 10 s, so joining it can take up to 11 s.

The test server paces bytes evenly, so a large keyframe arrives late. With the pre-roll, audio underruns in 30 s fell
from 5 to between 0 and 1. A real feed is paced by its own clock, so it should do better.

Needs the device:

- **CPU on the Frame.** Run `stream-tests.sh` there.
- **A real network.** A UDP or multicast feed over Wi-Fi, and an HTTPS server with a public certificate.
- **Socket buffer.** The UDP description gives the buffer the kernel granted. 416 KiB holds 10 ms at well over
  100 Mbit/s.

### Picture tools: letterbox detection and trick play (#42, #46)

Fork commit `c318810fdd`; Frame binary `build/out/godot.linuxbsd.template_debug.arm64.PLAYER_PICTURE`.

**Letterbox detection.** Set `MediaSource.letterbox_detection` before `open()`. `get_letterbox()` then gives the
picture's rectangle in the frame, also as a UV rectangle, with its aspect ratio.

- **Why a software decode.** The hardware decoder's frames are UBWC-compressed, so the CPU can't read them. A thread at
  nice 10 decodes one keyframe every 4 s of media with FFmpeg: one thread, no loop filter. After 16 keyframes it
  slows to one every 15 s, and it stops at 40.
- **The scan.** Luma rows, then columns, in from each edge until one has more than 2 % of its samples above black.
- **What doesn't count.** Black frames, and frames whose picture is dark on average: a dark scene's edges look like
  bars.
- **Combining frames.** Each edge is the outermost of the frames', except that one outlier is left out from 4 frames
  on (a logo or a flash over the bars). Bars under 1 % are ignored, and so are unequal bars on one axis, because real
  bars are centred.

Results on local films, with the video read as fast as it comes:

| Film | Frame | Picture found | Keyframes decoded (dark) | CPU on x86 |
|---|---|---|---|---|
| Animated Feature 2, half side-by-side 3D | 1920x1080 | 1920x804 at row 138 (2.39) | 8 (2) | 0.21 s |
| Animated Feature 3, half side-by-side 3D | 1920x1080 | 1920x804 at row 138 | 8 (2) | 0.14 s |
| A 1080p film (2.35) | 1920x1080 | 1920x816 at row 132 (2.35) | 9 (3) | 0.11 s |
| A 2160p HEVC film | 3840x2160 | 3840x2076 at row 42 (1.85) | 11 (5) | 0.67 s |
| `Action.720p.mp4` | 1280x720 | 1280x544 at row 88 (2.35) | 14 (8) | 0.04 s |
| A 1080p film that opens in dark space | 1920x1080 | 1920x1038 at row 21 (1.85), after 3.5 min | 27 (21) | 0.44 s |
| `Feature.HEVC10.CRA.mp4`, opening | 1920x1012 | 1920x805 at row 104 (2.39) | 11 (5) | 0.15 s |
| Nine other films (1080p and 2160p, flat and 3D) | cropped | no bars | 7 to 11 | 0.02 to 0.29 s |

Before the dark-frame rule, `Action.720p.mp4`'s night opening gave false side bars. The rule fixed it. A 2160p HEVC
keyframe takes 60 to 100 ms on x86; on the Frame's cores expect two to three times that, at nice 10.

Two films use codecs this build can't decode in software (VC-1, MPEG-4 Part 2). Their `error` says so, and the
picture is reported as the whole frame.

Films whose ratio changes between scenes, as some releases do, get the ratio of the scenes sampled.
The detector looks only at the first minutes.

The features test uses two synthetic clips from `tools/pcm_h264_avi.py`, which writes I_PCM H.264. The letterbox
clip has 40-row bars, black and dark frames, and a flash over the bars. The pillarbox clip has 80-column bars. Both
come out exact. A cropped film comes out without bars.

**Trick play.** `MediaSource.trick_play(speed, from)` with a speed of 2 to 64 reads and queues keyframes only. It
starts from the keyframe at or before `from` and shows at most one keyframe per 0.25 s of wall time. There is no
audio.

- **With an index.** Matroska, MP4 and AVI jump from keyframe to keyframe and read nothing in between. In the AVI test
  clip at 8x, 12 keyframes cost 14 packets read; Animated Feature 2 at 8x read 3.4 MB for 12 keyframes.
- **Without an index.** MPEG-TS reads on and drops the rest.
- **The clock.** `HWVideoTexture` runs its clock at the trick speed meanwhile and ignores the audio clock.
- **Back to normal.** `trick_play(0, texture.get_position())` resumes normal playback with audio.

On the host's software path, `Feature.HEVC10.CRA.mp4` at 8x moved 30.5 s in 4 s and HDR film A at 16x moved 63.5 s. Both showed
about two keyframes a second. Back at normal speed with audio, the A/V offset was +32 ms and +11 ms within 2 s.

The spike's new options are `--letterbox` and `--trick=X` with `--trick-for=S`. `features_test.gd` now runs 518 checks
and all pass. The 13 files of `run-tests.sh` and the SMB tests still pass.

Needs the device:

- **Trick play on the hardware decoder.** It is fed keyframes that are seconds apart. Check that each one comes out,
  and that the change back to normal settles.
- **Detector CPU.** Check its CPU next to a 2160p hardware decode.

### Next item on a second decoder session (#44 groundwork)

Fork commit `347778e84c`; Frame binary `build/out/godot.linuxbsd.template_debug.arm64.PLAYER_NEXT`.

This gives a playlist a change without a gap.

1. **Preroll.** The app opens the next item on a second `HWVideoTexture` with `open_source()`, without playing it, and
   calls `current.set_next(next)`.
2. **Waiting.** From then on, `current.update()` also updates the next texture. It decodes and holds its first frame,
   then waits; its demuxer fills its queues and stops.
3. **Boundary.** When `current.is_finished()` (the last frame has been up for its duration, or the audio ended), the
   two textures swap plane textures. A material keeps the texture objects it has, which now show the next item's
   frames at the next draw.
4. **Handover.** The next texture starts playing and `next_started(next)` is emitted. The app then plays the next
   source's audio stream, updates the next texture from then on, and closes the old one.

`swap_planes_with()` does the swap on its own, for a change somewhere other than the end.

Measured on the host's software path, with the spike's new `--next=PATH --next-before=20`. The first item was the
last 40 s of `Feature.HEVC10.CRA.mp4` (10-bit HEVC); the next was HDR film A (10-bit HEVC), opened 20 s before the end.

| Measure | Run 1 | Run 2 |
|---|---|---|
| Next item opened (source and decoder) | 103 ms | 27 ms |
| From `set_next()` to its first frame held | 40 ms | 21 ms |
| Memory when prerolled | +51 MB | +41 MB |
| Memory after 5 s waiting | +12 MB more | +22 MB more |
| The next item's threads while waiting | 0.32 % of a core | 0.24 % of a core |
| Swap after the end of the last frame's duration | 3 ms | 5 ms |

After the swap, HDR film A played with its audio as the clock, at an A/V offset of +3 to +41 ms. Process CPU is not
comparable on the host, because lavapipe renders on the CPU; the next item's own threads are.

The spike now stops its audio a few frames before it quits. Before, every spike run warned of two leaked objects (the
source and its audio playback) at exit.

Needs the device:

- **A second iris session.** Does the firmware take two decoder sessions at once, and does the second one stay idle
  once it has its first frame?
- **Memory.** A second set of CAPTURE buffers is held while waiting: 12 by default, about 150 MB at 2160p.
- **The swap.** No black or stale frame at the boundary, on the hardware path.

### Requests from the app: subtitle lines, dual subtitles, audio without a player, field order

Fork commits `6b89be9995` and `4b351c7722`; Frame binary `build/out/godot.linuxbsd.template_debug.arm64.PLAYER_REQUESTS`.

- **`get_video_info()["field_order"]`.** FFmpeg's names: "progressive", or "tt", "bb", "tb", "bt" for interlaced
  video. It is empty if the file doesn't say.
- **`MediaSource.get_subtitle_lines(track)`.** Every line of a text track as `{start, end, text, ass}`, sorted, with
  missing ends filled in. A track of the file's own is read with a demux context of its own, so playback isn't
  touched. But the subtitle packets are spread through the whole file, so the whole file is read. `close()` stops a
  read in progress. Lines of an added subtitle file are copied at once.
- **Dual subtitles.** `select_secondary_subtitle_track(track)` reads a second text track of the file's own alongside
  the first. Every event from `read_subtitle_event()` now has `track`.
- **`read_audio_frames(count)` and `set_external_clock(seconds, ticks_usec)`.** The decoded audio without an
  `AudioStreamPlayer`, for example to send it to a PC. Against an external clock, the audio is resampled by up to
  0.5 % so `get_audio_position()` follows that clock. The rate changes by 5 % of the gap per second.
- **`MediaBrowser.read_file(path)`.** A whole file of up to 64 MiB, local or smb://.
- **`OpenXRAPIExtension.get_supported_extensions()`.** The extensions the runtime offers, enabled or not.

Measured on the host:

| Measure | Result |
|---|---|
| `get_subtitle_lines()`, 800 MB film, local | 1238 lines in 7.7 s |
| `get_subtitle_lines()`, 2.1 GB film, local | 1487 lines in 23.1 s |
| `get_subtitle_lines()`, 2.1 GB film, smb:// | 1487 lines in 12.6 s, about 23 % of a core |
| `close()` during a whole-track read | the read returns 4 ms later |
| External clock 0.1 s ahead, simulated output | gap 95, 82, 70, 61 ms after 1, 4, 7, 10 s |
| Same, during playback with `--pull-audio=0.1` | gap 98 ms, then 72 ms, then 67 ms; A/V offset +1 to +33 ms |

The gap closes exponentially, by half in about 14 s. A bigger gap is for `seek()`. During a whole-track read in
playback (the 800 MB film), the spike dropped 3 frames and had no audio underruns.

The spike has new options: `--subtitle-lines=N`, `--subtitle-track2=M` and `--pull-audio[=S]`. In runs of only 60
frames on the host, two leaked objects are still reported at exit, with or without the new options. Longer runs exit
clean.

Needs the device:

- **The cost of a whole-track read.** Its CPU and its effect on playback over smb:// on the Frame.
- **The pull on ARM.** Its CPU with `--pull-audio=0.1`, and that the gap closes as on the host.

### Software decode where there is no hardware decoder (PLAYER_FINAL)

Fork commit `ccf591aa61`; Frame binary `build/out/godot.linuxbsd.template_debug.arm64.PLAYER_FINAL`.

When the decoder device (`V4L2Decoder.device_path`, `/dev/video-dec0`) doesn't exist, as on a desktop,
`open_source()` takes the software path for every stream it can decode: H.264, HEVC and VP9 up to
`software_max_pixels`. Before, only what the hardware can't show went that way, so a desktop never showed an 8-bit film.
The reason is "There is no hardware video decoder on this machine (no /dev/video-dec0)." A bigger stream fails with that
reason and the size limit. `HWVIDEO_FORCE_SW=1` decodes in software anywhere, the Frame included, for A/B comparisons.
What software can't take then still goes to the hardware. The Frame, with its decoder, is unaffected.

On the host, an 8-bit H.264 file and an 8-bit 1080p HEVC film now play with a real picture on lavapipe. `test.gd` and
`smb-tests.sh` expect this now.

PLAYER_FINAL2 (fork `42175b2a3c`) adds one engine fix outside the module. A `WorkerThreadPool` task that a script
never waited for kept its GDScript lambda until after the script languages shut down. Freeing it then corrupted the
heap at quit: the app's abort with "corrupted size vs. prev_size". The pool now releases those Callables just before the
languages finish, and warns with the count and the first task descriptions. A script with four such tasks aborted in 10
of 10 runs under `MALLOC_CHECK_=3` without the fix, and in none of 10 with it (`docs/decisions.md`, D6).

## Hardware VP9 (2026-10-31)

Fork commits `3705e22cf6` and `49574b189c`; Frame binary `build/out/godot.linuxbsd.template_debug.arm64.PLAYER_VP9`
(sha256 `2f0129b951f43831c78a04cd243717b22d23dfcbd2aba55a75c6a333618f3117`, built at `49574b189c`). It holds
everything of PLAYER_FINAL2. FFmpeg
now also has the IVF demuxer (`build/ffmpeg-build.sh`), so spike 01's `.ivf` test streams open with `--media=`.

### What the device showed (spike 01's `v4l2dec -c vp9 --allow-vp9`; kernel 6.18.0-ge66bc2ca6f8c, Valve's stock iris)

- The decoder offers `VP90` on OUTPUT (frame sizes 128x128 to 8192x8192), profiles 0 and 2.
- Sequential VP9 sessions work. The 8-bit clip `vp9p0_720p_10s` is 1280x696 (the name says 720p): CAPTURE NV12
  1280x704, visible 1280x696. The 10-bit profile 2 clip: CAPTURE Q10C 1344x704. 120 and 240 frames each, 0 ERROR
  flags, about 1000 fps. VP9, then HEVC, then VP9, then HEVC 2160p: all fine. Five full-clip VP9 runs in a row: fine.
- **Two VP9 sessions at once crashed the decoder firmware.** Valve's `iris-driver-rebind.service` reloaded it within a
  second, and both sessions got `DQBUF` `EINVAL`. When the test process was killed afterwards, the kernel oopsed
  ("v4l2dec exited with preempt_count 1"), and the headset stopped answering until a reboot. This is the failure of
  SteamOS issue #2865.
- So: hardware VP9 with **one session at a time, never two**. A decoder error must lead to software decode, not to a
  hang or to a process that exits with the decoder wedged.

### What the engine does

- **`V4L2Decoder.open_source()` decodes VP9.** OUTPUT is `VP90`, one container packet per buffer: a frame or a
  superframe, as FFmpeg's WebM, Matroska, IVF and MP4 demuxers deliver it. There is no Annex-B split and no SPS. The
  OUTPUT format's size is the container's frame size. The uncompressed header of each keyframe gives the frame size and
  bit depth (`V4L2Decoder.probe_vp9_packet()` for scripts), which also marks where a session restart can resume. CAPTURE
  comes from SOURCE_CHANGE as for HEVC: Q08C or NV12 for 8-bit, P010 for 10-bit when the driver offers it. The decoder
  logs `CAPTURE formats offered for this VP9 stream: ...` (`... 10-bit VP9 stream` for profile 2).
- **Seeks.** The source starts at a keyframe after a seek (the container's keyframe flag). A VP9 keyframe resets every
  reference, and VP9 holds no pictures for reordering, so the session goes on with it: no end-of-sequence NAL unit, no
  flush, no STREAMOFF. That is the same discipline as the HEVC path, which also just goes on. The log line is
  `seek (serial N): first VP9 packet at T s, keyframe WxH; no flush needed.` Whether the firmware is happy with that on
  every seek is for the device run; if it is not, the decoder errors trip the fallback below.
- **One hardware VP9 session per process.** `V4L2Decoder` holds a process-wide slot from `open_source()` of VP9 until
  `close()` (`V4L2Decoder.is_vp9_session_live()`). A second `open_source()` of VP9 fails with `ERR_BUSY`.
  `HWVideoTexture` checks first: a second VP9 texture (the gapless next item, picture in picture, seek thumbnails, a
  crossfade, the benchmark) goes to software up to `software_max_pixels`, with `HWVideoTexture: software decode (...):
  Another video is decoding VP9 in hardware: ...` in the log. If software can't take it (above about 1080p), it fails
  with both reasons. It never opens a second hardware session.
- **Decoder faults stop the session cleanly.** A VP9 session ends itself, with state `error`, after 3 failed DQBUFs in
  a row (not EAGAIN or EPIPE), 8 buffers in a row flagged `V4L2_BUF_FLAG_ERROR` with no picture, no picture 4 s after
  3 access units were fed (not counted while every CAPTURE buffer is held by the player, during a resolution change, or
  after the end), or the usual 5 s hang check. The worker closes the device itself (STREAMOFF, buffers freed, close;
  the process is not killed). `HWVideoTexture.update()` then sees the error and goes on in software from the current
  position (`HWVideoTexture: switching to software decode at T s: The hardware decoder failed on VP9 (...)`), keeping
  play or pause and the next item. Until that `update()`, `HWVideoTexture.get_stats()` reports state `reconfiguring`
  with `switching_to_software` true, not `error`, so the app doesn't take it for a fatal error. After a decoder fault, hardware VP9 stays off until the process ends
  (`V4L2Decoder.get_vp9_disabled_reason()`), because the firmware may just have been reloaded.
  `HWVideoTexture.switch_to_software(reason)` does the same switch on request.
- **10-bit VP9.** Without P010 (the stock module) it goes to software with the usual 10-bit reason, as before. With the
  patched module, P010 is offered for HEVC; for VP9 that is untested. A 10-bit VP9 stream is tried in hardware, and if
  its CAPTURE list has no P010 the session fails as a format error. The texture then switches to software with the
  10-bit reason, and later 10-bit VP9 files go straight to software (`hw_decodable` false). The HEVC answer is not
  touched.
- **`MediaSource.get_hw_unsupported_reason()`** returns "" for VP9 profiles 0 and 2 at 8 bits, the 10-bit reason for
  10-bit without P010, and a refusal for profiles 1 and 3 (4:2:2, 4:4:4). The policy is no longer in it.
- **Switches.** `HWVideoTexture.hw_vp9` (default true); `HWVIDEO_HW_VP9=0` or `1` in the environment overrides it. The
  app's `[hwvideo] hw_vp9` sets it on every texture it makes.
- **Paths for people.** `HWVideoTexture.get_decode_path_text()` and `decode_path_text` in `get_stats()` and
  `get_overlay_stats()`: `hardware (VP9)`, `hardware (VP9, 10-bit)`, `hardware (10-bit)`, `hardware`, `software`. The
  test project's 2 s line ends with `, hardware (VP9)`; the app's overlay says `hardware (VP9)`.
- Also fixed: the seek log line had six arguments for five placeholders, which logged `ERROR: ... not all arguments
  converted` on every seek.
- **Superframes are split (PLAYER_Q10C).** On the device, the third VP9 session of a boot crashed the firmware
  (`received system error of type 0x5000003`) while the first two closed cleanly. Packets went in as the container
  delivers them, superframes included (a hidden alt-ref frame and a shown frame in one packet). The firmware may not
  take that. Since PLAYER_Q10C, every packet whose last byte is a superframe marker goes through FFmpeg's
  `vp9_superframe_split` first. Each frame then goes in its own OUTPUT buffer, hidden frames too, all with the packet's
  timestamp; the shown frame is the last. Single frames go in unchanged. Hidden frames don't count for the
  no-picture watchdog, and the feed pacing waits until all parts of a packet are in. The first split is logged
  (`VP9 superframes are split with vp9_superframe_split (the first at T s: 2 frames, 1 hidden), one frame per OUTPUT
  buffer.`), and at the end of the session one line has the totals (`VP9: N packets fed; M superframes split into K
  frames (H hidden) by vp9_superframe_split.`, also `vp9_packets`, `vp9_superframes`, `vp9_split_frames`,
  `vp9_hidden_frames` in `V4L2Decoder.get_stats()`). If the filter is missing from the FFmpeg build, a warning is
  logged and superframes go in whole, as before. `V4L2Decoder.split_vp9_packet(packet)` gives scripts the same split.
  The one-session rule and the fault fallback are unchanged. Whether the split stops the crash is for the device
  (`docs/morning-checklist.md`, section F, Q5).

### Limits

- **Within one process only.** Another process that opens a VP9 session on `/dev/video-dec0` at the same time (a
  second player, `v4l2dec`, anything else on the headset that decodes VP9 in hardware) is not seen. Do not run two
  VP9 players at once.
- **A gapless next item opened while a VP9 file plays in hardware stays in software for its whole run.** It does not
  move to the hardware when the first closes. In a VP9 playlist, the items therefore alternate between hardware and
  software.
- The picture is black for the moment of a switch to software (tens of milliseconds on the PC).

### Verified on the PC (x86_64 build, no decoder)

`demux-test/vp9_test.gd` (headless, and with xvfb and lavapipe for the playback part), on the device's clips and on
clips made with `ffmpeg -c:v libvpx-vp9 -deadline realtime -cpu-used 6`:

- WebM and IVF open; 8-bit VP9 is `hw_decodable` with no reason; 10-bit gets the 10-bit reason.
- The keyframe header parser agrees with the container on size, bit depth and profile for all of them (1280x696,
  1280x720; profiles 0 and 2); superframes are found (4 and 13 in the first 120 packets of the device's clips).
- With a stand-in device (`/dev/null`): `HWVIDEO_HW_VP9=0` and `hw_vp9 = false` go to software with their reason;
  `HWVIDEO_HW_VP9=1` overrides `hw_vp9 = false`; VP9 on goes to the hardware path, and its failure (at QUERYCAP here)
  holds no VP9 session and doesn't turn VP9 off; a 2160p VP9 with VP9 off fails with both reasons.
- `switch_to_software()` during playback at 3 s: playback goes on at the next frame (3.125 s) 38 ms later, still
  playing, the next item kept, and a later seek settles in 17 ms.
- The test project plays a VP9 WebM with `--seek-every`, the 10-bit IVF and `--next` (all on the software path here).
- Unchanged paths: `run-tests.sh` (H.264, HEVC 8- and 10-bit, MPEG-TS, AVI) all PASS; the app's `test_hw_setup`,
  `test_media_features`, `test_hw_source_helpers` and `--ui-test` (180 checks) pass.
- The arm64 PLAYER_VP9 under `qemu-aarch64-static`, headless: the file and rule checks above on the device's three
  clips, all PASS.

Nothing of the hardware path can run on the PC. The device steps are in `docs/morning-checklist.md`, section F,
"Hardware VP9".

## Q10C through a YCbCr sampler (2026-10-31)

Fork commits `e85248e0de` and `9e4cbcce7c` (branch `frame/q10c`, fast-forwarded into `frame/player`); Frame binary
`build/out/godot.linuxbsd.template_debug.arm64.PLAYER_Q10C` (sha256
`47aecf9f91afb812503eeb99f1962b7ca3eb95c114a2c2d1498e1e5456052d25`, built at `9e4cbcce7c`). It holds everything of
PLAYER_VP9. Decision: `docs/decisions.md`, D14.

Valve's stock iris module offers only Q10C for 10-bit: UBWC-compressed TP10 (three 10-bit samples in 32 bits). It has
no view format of its own, so the earlier experiment ("Q10C, an experiment" above) could not show it. Another player
on the same headset shows it, which means Valve's Turnip reads it through some format and modifier. Upstream Mesa can't
(`spikes/04-q10c-probe/README.md`, "Background"). The engine now tries what the driver lists, and checks the picture.

### What the engine does

- **Import.** `DmabufImage.import_ycbcr(fd, vk_format, modifier, w, h, offsets, pitches, plane_count, out_y,
  out_cbcr)` imports the dmabuf as one multi-planar image with an explicit DRM format modifier and plane layout
  (`VK_IMAGE_TILING_DRM_FORMAT_MODIFIER_EXT`, dedicated import, foreign queue family). The image is only read through
  a sampler with a `VkSamplerYcbcrConversion`, as the spec requires for such formats: model `RGB_IDENTITY`, range
  `ITU_FULL` (the raw codes, no colour maths), NEAREST, midpoint chroma when the format supports it, else cosited. The
  sampler is immutable in its own descriptor set layout. An image larger than the dmabuf is refused before any bind.
- **Conversion to P010.** When a frame is shown, `acquire()` records a compute pass through
  `RenderingDevice::driver_callback_add()` (with the queue family transfers in the callback; the Vulkan driver got
  `command_buffer_get_vk()` and `command_buffer_get_queue_family()` for that). The pass reads each luma sample and
  each chroma pair through the sampler and writes the codes, as P010 holds them (code << 6), into R16 and R16G16
  textures. So `HWVideoTexture` reports `PACKING_P010`, and the shaders (the test project's and the app's) take it
  as they take P010: the colour maths stays in the app's shader, with no change. Normalisation: Mesa returns 10-bit
  samples on the 16-bit scale; `floor(s x 65535/64 + 0.0005)` gives the code either way (and the spec's v/1023).
- **Candidates.** `DmabufImage.get_q10c_candidates()` asks the driver, once per run, for the DRM format modifiers of
  `G10X6_B10X6R10X6_2PLANE_420_UNORM_3PACK16` that can be sampled, and whether a dmabuf import with each is possible.
  QCOM modifiers come in the order 7, 5, 4, 3, 6, 2, 1 (Android's TP10 UBWC is `COMPRESSED|DX|TIGHT` = 7; plain
  COMPRESSED, which upstream Turnip lays out as P010, comes last). The plane layout follows the modifier's memory
  plane count: 2 planes at the Y and UV metadata (`meta`, Turnip's UBWC convention, as for Q08C), 4 planes (pixels,
  then metadata), or 1. The log line at the first 10-bit file: `DmabufImage: Q10C through a YCbCr sampler: <format>
  lists <modifiers>. Candidates: ...`. `DmabufImage.get_q10c_report()` has the same text.
- **Overrides** (`docs/USAGE.md`): `HWVIDEO_Q10C=0` (off), `HWVIDEO_Q10C_FORMAT` (a VkFormat number, or `G12`,
  `G16`), `HWVIDEO_Q10C_MODIFIER` (one modifier, listed or not), `HWVIDEO_Q10C_LAYOUT` (`meta`, `data`, `4plane`,
  `1plane`), `HWVIDEO_Q10C_CHECK=0` (no picture check). `HWVIDEO_P010=0` now also makes the decoder ignore an offered
  P010, so Q10C can be tried on the patched module.
- **First buffer picks.** `HWVideoTexture` tries the candidates in order on the first CAPTURE buffer; the first that
  imports is kept for all buffers and for the rest of the run (`DmabufImage.get_q10c_chosen()`). Log: `imported N
  decoder buffers (generation G): Q10C through a YCbCr sampler (<format> <modifier> <layout>) WxH, ...; shown as P010.`
- **The picture check.** A wrong layout imports fine and shows noise. So the luma of a shown frame is read back
  (`texture_get_data_async()`, no stall) and judged: the mean difference between neighbouring samples is under 100
  codes for a decoded picture and about 340 for noise. A flat frame (range under 24 codes) is inconclusive and the
  check is repeated, 24 frames later, up to 8 times. `the Q10C picture looks right (...)`, or `... looks like noise
  (...)`.
- **Routing for a 10-bit file.** P010 if the decoder offers it; else Q10C if a candidate exists and Q10C hasn't failed
  in this run; else software, with the reason (`HWVideoTexture: 10-bit without P010; Q10C through a YCbCr sampler:
  <report>.`). An import failure or a noise verdict calls `DmabufImage.disable_q10c(reason)` and switches the texture
  to software at the current position (`switching to software decode at T s: ... ; decoding in software.`); later
  10-bit files go to software from the start. A file too large for software (2160p) stops then, with `the software
  path couldn't take over: ...`.
- **Paths for people.** `decode_path_text`: `hardware (10-bit, Q10C)` and `hardware (VP9, 10-bit, Q10C)`;
  `get_stats()` has `q10c` (the chosen candidate) and `q10c_check` (the verdict). `MediaSource.get_video_info()` has
  `hw_10bit_path`: `p010`, `q10c` or "" (software), and 10-bit is `hw_decodable` when either path exists.
- **For the app:** nothing to change. It sets the shader's `p010` from `get_packing() == PACKING_P010` already, and
  its overlay says `hardware (10-bit)` (from `decode_path` and the bit depth). To tell Q10C from P010 there, it can
  show `get_stats()["q10c"]` (empty for P010).

### Verified on the PC (x86_64, lavapipe; no decoder, no DRM format modifiers)

- `demux-test/q10c_test.gd` (`xvfb-run -a godot --path spikes/03-player/demux-test --script res://q10c_test.gd`):
  `DmabufImage.import_ycbcr_test_pattern()` puts a 10-bit 320x180 and an 8-bit 256x144 pattern in a host-memory
  multi-planar image and runs the same pass. Every sample of both outputs equals its P010 form, on two frames, and
  the image frees cleanly. lavapipe lists no modifiers, so there is no candidate, the report says so, and 10-bit files
  are described and played as software (`--files=`), as before.
- `demux-test/vp9_test.gd`: every superframe splits into its frames, each a valid VP9 frame, the last one shown;
  single frames come back unchanged (x86_64, and the arm64 build under `qemu-aarch64-static`).
- Unchanged paths: `run-tests.sh` all PASS; the app's tests (`test_video_mode`, `test_hw_source_helpers`,
  `test_media_features`, `test_hw_setup`, `test_features`, `test_end_time`, `--ui-test`) all pass.
- The probe's own pass on lavapipe: PASS, 0 wrong samples (`spikes/04-q10c-probe/README.md`).

Which candidate Valve's Turnip takes, and whether its picture is bit-exact, is for the device:
`docs/morning-checklist.md`, section F, "10-bit without P010" (Q1 is the probe, Q2 to Q4 the engine).

## Every codec in software (2026-11-01)

Branch `frame/codecs` (worktree `~/src/godot-player-codecs`), commit `0fe0c5f04b` on `frame/player` at `9e4cbcce7c`. Decision:
`docs/decisions.md` D18. User view: `docs/features.md`, "Every format".

### What the engine does

- **FFmpeg** (`~/src/ffmpeg-<arch>-all`, `build/ffmpeg-build.sh`): every native decoder, every file demuxer, all
  parsers and bitstream filters, swscale; dav1d (`~/src/dav1d-<arch>`, `build/dav1d-build.sh`). LGPL, no GPL, no
  nonfree. `SCsub` links `avformat avcodec swscale swresample avutil dav1d`.
- **MediaSource:** `VideoInfo` gets `codec_id`, `codec_long_name`, `codec_tag` (FourCC), `software_decoder` (this
  build decodes it); `get_video_codec_parameters()` hands a software decoder the extradata (after the bitstream
  filter). MPEG-4 part 2 goes through `mpeg4_unpack_bframes`. `VideoPacket.pts_valid` / `dts_valid` say which
  timestamps the container gave. A seek that neither the index nor a timestamp search can do is done by bytes;
  MPEG-PS seeks to the start by bytes, like MPEG-TS. After 300 packets without a keyframe flag, a software codec's file
  is marked `keyframes_unreliable`: seeked again, and the first packet after each seek is taken as the keyframe
  (`keyframe_guessed`). `avg_frame_rate` above 240 (raw DV's guessed duration) falls back to `r_frame_rate`.
  More text subtitle codecs count as text (MicroDVD, SubViewer, SAMI, RealText, MPL2, PJS, JACOsub, VPlayer, STL,
  EIA-608).
- **SoftwareVideoDecoder:** any decoder (`libdav1d` for AV1), `avcodec_parameters_to_context()` for everything but
  H.264/HEVC (Annex-B with in-band parameter sets, as before). Only the container's timestamps go in, so
  `best_effort_timestamp` reorders. Output: yuv420p/yuvj420p copied and 10-bit 4:2:0 rounded when the range matches
  the video info's; anything else through swscale (`sws_getContext` at the same size, `sws_setColorspaceDetails`
  with the matrix the app's shader picks: BT.2020, BT.601 by name or for 576 lines and fewer, else BT.709; the range
  the info says). Decode errors are concealed (100 in a row end it). After a guessed keyframe, pictures stay hidden
  until one is a keyframe (3 s at most). Stats: `software_pixel_format`, `software_conversion`,
  `software_field_order`, `software_frames_*`.
- **Limits:** `get_max_pixels()`: `software_max_pixels` (1920 x 1088) for every codec; AV1 up to a 4K30 pixel rate
  (3840 x 2176 at 30 fps or less, 2560 x 1440 at 60).
- **HWVideoTexture:** software textures are `CAN_COPY_FROM` (tests read them back). Nothing else changes.

### Verified on the PC (x86_64 build, xvfb, lavapipe; no decoder)

`demux-test/codecs-tests.sh` (`codecs_test.gd`): 27 clips from `make-codec-files.sh` and 21 real files of the
library, listed in `docs/features.md`. All pass but one known case: libtheora 1.2's inter frames, which FFmpeg's
Theora decoder rejects (keyframes only). Table of that run (decoded flat out on x86 without FFmpeg's assembly,
lavapipe drawing too):

| File | Codec | Picture | Conversion | Decoder fields | fps |
|---|---|---|---|---|---|
| xvid_bframes.avi | mpeg4 (XVID) | 640x480 | yuv420p copied | progressive | 1089 |
| div3.avi | msmpeg4v3 | 640x480 | copied | progressive | 1134 |
| dvd_interlaced.vob | mpeg2video | 720x576, SAR 64:45 | copied | tt | 741 |
| wmv2.wmv | wmv2 | 320x240 | copied | progressive | 1091 |
| rv20.rm | rv20 | 320x240 | copied | progressive | 945 |
| vp8.webm | vp8 | 640x480 | copied | progressive | 785 |
| av1_1080p.mkv | av1 (dav1d, C only) | 1920x1080 | copied | progressive | 555 |
| av1_720p_10bit.mkv | av1 | 1280x720 | yuv420p10le rounded | progressive | 763 |
| mjpeg422.avi | mjpeg | 640x480 | swscale yuvj422p, full range | progressive | 392 |
| cinepak.mov | cinepak | 320x240 | swscale rgb24, BT.601 limited | progressive | 736 |
| prores422.mov | prores | 1280x720 | swscale yuv444p10le, BT.709 | progressive | 150 |
| ffv1_gray_odd.nut | ffv1 | 351x239 shown 350x238 | swscale gray | progressive | 782 |
| png_pal8.mov | png | 320x240 | swscale pal8 | progressive | 492 |
| dv_pal.dv | dvvideo | 720x576 | copied | bb | 1215 |
| `divx5_dx50.avi` (DX50) | mpeg4 | 680x560 | copied | progressive | 1285 |
| `div3_wma.avi` (DIV3 + WMA) | msmpeg4v3 | 384x284 | copied | progressive | 654 |
| `flv1_in.avi` (FLV1 in AVI) | flv1 | 384x216 | copied | progressive | 641 |
| `rv40_cook.rm` | rv40 + cook | 384x216 | copied | progressive | 743 |
| VTS_01_1.VOB | mpeg2video + ac3 | 720x576 | copied | bb | 602 |
| `mpeg2_1080i.ts` | mpeg2video, container says tt | 1920x1080 | copied | progressive (most pictures) | 254 |
| `Animated.VC-1.Remux.mkv` (Blu-ray remux) | vc1 | 1920x1080 | copied | progressive | 85 |

Unchanged paths: `run-tests.sh` all PASS on this build, `vp9_test.gd` PASS, `features_test.gd` 550 checks, 0 failed.
The arm64 build (`cc3f4cd9...`, 107,130,816 bytes against PLAYER_Q10C's 96,050,928) opens AV1, Xvid, RealVideo and
WMV clips under `qemu-aarch64-static`.

Found on the way: the FLV1-in-AVI file (FLV1, time base 1/1000) loses every keyframe flag after a seek in FFmpeg's AVI
demuxer, which waited for one to the end of the file; the fallback above plays it. Raw DV reported 60000 fps.

### Limits and to do

- The speeds above are the PC's. The headset's CPU decides whether VC-1 1080p (FFmpeg's VC-1 has no frame threads)
  and AV1 at 4K keep up; the overlay's dropped frames show it.
- MPEG-2 whose pictures are mostly progressive (film in a 1080i broadcast) can report a field order (tt) from its
  first picture, and deinterlace "auto" then engages on progressive pictures. The decoder's `software_field_order`
  knows better; the app could prefer it.
- No WMV3 (WMV 9) file in the library or from an encoder; VC-1 is tested (the same decoder).

## Binary lineage

Every build after PLAYER_ALL2 is on `frame/player`, whose history is linear apart from one merge. Each build therefore
holds everything of the builds above it. PLAYER_ALL2 was built from `frame/window-on-player`: PLAYER_SMB2 plus the
window module, without SMB3 and UBWC. `frame/player` merged that branch at `64adbcd70e`, so the window module is in
every build from PLAYER_10BIT on. `docs/BUILD.md` lists the builds kept in `build/out/` with their SHA-256.

| Build | Fork commit | What it added | Cumulative |
|---|---|---|---|
| PLAYER_DEMUX | `e4b4769810` | MediaSource: FFmpeg demux and audio decode feeding the V4L2 decoder | yes |
| PLAYER_DEMUX2 | `6d48ab6812` | MPEG-TS seeks, end-of-sequence NAL unit after a seek, subtitle events | yes |
| PLAYER_SMB | `893d2d87a8` | Files from SMB shares (libsmb2), MediaBrowser | yes |
| PLAYER_SMB2 | `2b35386ef0` | Clearer refused-login errors; `seek_eos` separate by default | yes |
| PLAYER_SMB3 | `a88f2f1a35` | SMB refill and stall stats, audio waits after seeks, `network_requests` | yes |
| PLAYER_UBWC | `b9f0db12ce` | Q08C (UBWC NV12) CAPTURE import | yes |
| PLAYER_ALL2 | `0ecbc5407b` | PLAYER_SMB2 plus the window module; the known-good baseline | no: a side branch |
| PLAYER_10BIT | `50e9a68f38` | The window merge; refusal of 10-bit, VP9, AV1, 4:2:2 with a reason; the Q10C experiment | yes |
| PLAYER_10BIT2 | `d24cc90744` | Software decode fallback (H.264, HEVC, VP9 up to 1080p) | yes |
| PLAYER_P010 | `e3694cc68e` | P010 CAPTURE and import, Q08C by default, colour description | yes |
| PLAYER_FEATURES | `6b7f34ddbc` | Chapters, stereo and spherical metadata, subtitle files, language picks, overlay stats, playback speed | yes |
| PLAYER_FEATURES2 | `e080a5edfb` | Faster software seeks, `bitrate_bps`, `stereo_mode_tag` | yes |
| PLAYER_SUBS | `153727c6ce` | Bitmap subtitles as images, styled runs for text subtitles | yes |
| PLAYER_NIGHT | `0178dc9a02` | Night mode and dialogue boost | yes |
| PLAYER_CHANNELS | `59676f3368` | Discrete 7.1 channels, one AudioStream per channel | yes |
| PLAYER_HDR | `015fc1857b` | HDR metadata, tone mapping helper | yes |
| PLAYER_INPUTS | `8ac5e35f43` | HTTP, HTTPS and UDP input, live streams, music files | yes |
| PLAYER_PICTURE | `c318810fdd` | Letterbox detection, trick play | yes |
| PLAYER_NEXT | `347778e84c` | Next item on a second decoder session | yes |
| PLAYER_REQUESTS | `4b351c7722` | Whole subtitle tracks, dual subtitles, audio without a player, field order, `read_file()`, OpenXR extension list | yes |
| PLAYER_FINAL | `ccf591aa61` | Software decode where there is no hardware decoder, `HWVIDEO_FORCE_SW=1` | yes |
| PLAYER_FINAL2 | `42175b2a3c` | Never-waited WorkerThreadPool tasks released before the script languages shut down | yes |
| PLAYER_VP9 | `49574b189c` | Hardware VP9, one session at a time; mid-stream switch to software on VP9 decoder faults; IVF demuxer; seek log fix | yes |
| PLAYER_Q10C | `9e4cbcce7c` (and `e85248e0de`) | 10-bit as Q10C through a YCbCr sampler, checked, else software; VP9 superframes split before the decoder | yes: the newest on `frame/player` |
| PLAYER_CODECS | `0fe0c5f04b` (branch `frame/codecs`) | Every codec FFmpeg decodes, in software; dav1d for AV1; full LGPL FFmpeg with swscale (`~/src/ffmpeg-<arch>-all`) | yes: PLAYER_Q10C plus this |

## Known issues (PLAYER_FINAL2, PLAYER_VP9, PLAYER_Q10C)

- **`vp9_test.gd --play` fails two checks on `vp9_1080p_10s.webm`** ("picks up at the position it had", "seek to 12 s
  settles"). That 10 s clip has one keyframe, so a seek lands at 0, and 12 s is past its end. PLAYER_VP9 fails them
  in the same way: the test's expectations, not the engine.

- **Hardware VP9 is one session per process, not per headset.** Another process decoding VP9 in hardware at the same
  time can still crash the firmware ("Hardware VP9", Limits). A gapless next VP9 item stays in software for its run.

- **The first trick play on a fresh session can land late.** app-features found this with the thumbnails feature.
  - **What happens.** A second session is opened with `select_audio_track(-1)` and `open_source()`, then updated once.
    The first `trick_play(2.0, 3.0)` on the I_PCM test AVI then shows a frame at `frame_time` 7.0 while the position
    is 3.02. No frame at or before 3.0 follows within 4 s. Later `trick_play()` calls on the same session land exactly
    (7.5 and 55.0).
  - **Likely cause (not yet reproduced here).** The texture is still settling on the seek target of `open_source()`
    when trick play moves the source to 3.0. Its first-frame logic may still act on the open's serial and take a later
    keyframe as the first frame, and nothing then moves it back.
  - **Workaround (in the app).** Play the new session until its first frame shows, then call `trick_play()`.
  - **Repro.** `app/tests/test_thumbnails.gd`, with the warm-up step taken out of `seek_thumbnails.gd`.
- **The "ended" state comes one frame before `is_finished()`.** This is by design, not a bug. The state goes to "ended"
  when the decoder has drained. `is_finished()` is true once the last frame has been up for its duration, and that is
  the boundary for the next-item swap. An app that chains a next item should keep its end state until the swap.

## Test project (`project/`)

Mobile renderer, OpenXR on with the flat fallback of spike 02. Screen: a 16:9 quad, `--screen-width` metres wide
(4.0 by default), 3 m in front at eye height. User arguments (after `--`): `--file=`, `--codec=h264|hevc`, `--fps=`,
`--audio=` (empty = none), `--av-offset=`, `--sbs`, `--screen-width=`, `--loop`, `--capture-buffers=`,
`--capture-format=NV12|Q08C` (Q08C by default), `--chroma-offset=N` (P010/NV12 layout override), `--overlay-stats`
(print `HWVideoTexture.get_overlay_stats()` every 2 s), `--gpu-time` (adds the main viewport's GPU time to the 2 s line), `--10bit` and
`--q10c-view=` (the Q10C experiment), `--dump-planes=PREFIX` (save both plane textures as the GPU reads them, at the
screenshot frame), `--lead=`,
`--verbose-decoder`, `--probe` (split only, print, quit), `--no-xr`, `--quit-after=`, `--screenshot=`,
`--screenshot-frame=` (default 300). Every 2 s it prints the decode fps, shown fps, dropped frames, A/V offset, render fps,
decoder latency, the driver's queued-rate estimate and buffer counts.

With `--media=PATH` it plays a container file through a MediaSource instead (video, audio track and frame times from the
file; `--file`, `--codec`, `--fps` and `--audio` are ignored), with `--audio-track=N` (-1: none) and `--start=S` (seek
before playing). The 2 s line then also shows the demux queue, the buffered audio, audio underruns, decoder errors and
the CPU time of the demux and decoder threads. On the Frame, with
`godot.linuxbsd.template_debug.arm64.PLAYER_DEMUX2` (built by `build/build-player.sh arm64`):

```
DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 ./godot.linuxbsd.template_debug.arm64.PLAYER_DEMUX2 --path project --display-driver x11 --xr-mode off -- --no-xr --sbs --media=/path/to/Documentary.3D.Full-SBS.mkv --quit-after=600
```

More options with `--media`:

- `smb://host/share/path/file.mkv` as the path, with `--smb-user=NAME`, `--smb-domain=NAME` (optional) and the password
  from `--smb-password-file=PATH` (its first line) or the `SMB_PASSWORD` environment variable. The 2 s line then adds the
  network rate, the buffer ahead, stalls, reconnects and the readahead thread's CPU time. On the Frame, with
  `PLAYER_SMB` (the password in a file only the deck user can read; HOST, USER and PC-NAME are placeholders):

  ```
  ./godot.linuxbsd.template_debug.arm64.PLAYER_SMB --path project --display-driver x11 --xr-mode off -- --no-xr --sbs --media=smb://HOST/Movies/Documentary.3D.Full-SBS.mkv --smb-user=USER --smb-domain=PC-NAME --smb-password-file=~/.smb-password --quit-after=1800
  ```

- `--seek-eos=0|1|2`: `V4L2Decoder.seek_eos` (off, same buffer, own buffer; default 2).
- `--seek-every=S` and `--seek-by=D`: seek D seconds forward (default 37; back to 30 s near the end) every S seconds of
  playback. Audio and video pause until the frame at the target is on screen. Each seek prints how long it took to settle,
  the frame it settled on, and the decoder errors during the seek.
- `--subtitle-track=N`: print each event of subtitle track N when it is due (text, or the size of a bitmap packet).

The end-of-sequence A/B run: the same file, seeks and duration, once per value; compare the decoder errors per seek, the
settle times and the picture after each seek (the decoder logs the keyframe type at each seek):

```
for e in 0 1 2; do
  DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 ./godot.linuxbsd.template_debug.arm64.PLAYER_DEMUX2 --path project --display-driver x11 --xr-mode off -- --no-xr --media=/path/to/file --seek-eos=$e --seek-every=10 --seek-by=37 --quit-after=1800 2>&1 | grep -E "^Seek|errors|seek \(serial" > eos-$e.log
done
```

## Run on the Frame

Build in WSL, unoptimised (our -O2 cross-build doesn't draw 3D; `~/build-player.sh` in WSL runs exactly this and logs
to `~/godot-player-build.log`):

```
cd ~/src/godot-player && ~/.venv/godot/bin/scons platform=linuxbsd arch=arm64 target=template_debug dev_build=yes optimize=none CC=aarch64-linux-gnu-gcc CXX=aarch64-linux-gnu-g++ LINK=aarch64-linux-gnu-g++ use_sowrap=yes vulkan=yes opengl3=no accesskit=no sdl=no module_mono_enabled=no deprecated=no debug_symbols=no disable_path_overrides=no -j12
cp bin/godot.linuxbsd.template_debug.dev.arm64 /mnt/c/path/to/steam-frame-vr-video-player/build/out/godot.linuxbsd.template_debug.arm64.PLAYER
```

Then from Windows:

```
ssh frame mkdir -p spike03
scp build/out/godot.linuxbsd.template_debug.arm64.PLAYER frame:spike03/
scp -r spikes/03-player/project frame:spike03/
ssh frame chmod +x spike03/godot.linuxbsd.template_debug.arm64.PLAYER
```

On the Frame (`ssh frame`, `cd ~/spike03`). The streams are already in `~/spike01/streams/`.

```
# 0. No decoder, no GPU: the access-unit split on the device (expect 63311 access units, 3840x1088 / 3840x1080).
./godot.linuxbsd.template_debug.arm64.PLAYER --headless --path project -- --probe

# 1. Flat check: 600 frames, screenshot of the left half at frame 300.
DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 ./godot.linuxbsd.template_debug.arm64.PLAYER --path project --display-driver x11 --xr-mode off -- --no-xr --sbs --quit-after=600 --screenshot=/home/steamos/spike03/shot.png --screenshot-frame=300

# 2. The same without --sbs: the whole 3840x1080 frame (both eyes side by side) squeezed onto the 16:9 screen.
#    Use it to check the crop and the seam: two images side by side, no green or purple line at the bottom.
DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 ./godot.linuxbsd.template_debug.arm64.PLAYER --path project --display-driver x11 --xr-mode off -- --no-xr --quit-after=600 --screenshot=/home/steamos/spike03/shot_full.png --screenshot-frame=300

# 3. XR, in the headset, SteamVR running: 3D, audio, 2 minutes.
DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 ./godot.linuxbsd.template_debug.arm64.PLAYER --path project --display-driver x11 -- --sbs --quit-after=10800

# Variants: --verbose-decoder (every V4L2 step), --audio= (no audio, frame clock), --loop, --av-offset=0.05.
```

`--quit-after` counts rendered frames: 600 is 10 s in flat mode at 60 Hz; 10800 is 2 min at 90 Hz in XR.

Firmware rules from spike 01 still hold: one run at a time, ~5 s between runs, check
`sudo dmesg | tail -50 | grep -iE 'iris|0x5000003|smmu'` after each run, never `kill -9` a player stuck in a decoder
ioctl (a `HANG` message and state `error` come after 5 s by themselves). Quit with `--quit-after` or by closing the window.

## What to look for

Console, in order:
- `V4L2Decoder: .../documentary_sbs.h264: 5979727214 bytes, H.264 3840x1088 (display 3840x1080), 8-bit, 23.976 fps.`
- `V4L2Decoder: opened /dev/video-dec0: driver 'iris_driver' ...`, `S_FMT OUTPUT H264 3840x1088: sizeimage ...`
- `SOURCE_CHANGE #1`, then `CAPTURE generation 1: NV12 3840x1088, pitch 3840, chroma at 4177920, ..., visible 3840x1080+0+0, N buffers`.
  If the pitch isn't a multiple of 256 or the chroma offset isn't 3840 × 1088, note it (Turnip's linear import).
- `HWVideoTexture: imported N decoder buffers (generation 1)` and `Video format: buffers (3840, 1088), visible ...`.
  An `ERROR:` here from `import_nv12` names the Vulkan step that refused the decoder's buffer.
- `Playback started at frame ...`, then every 2 s:
  `decoding: decode 24.0 fps, shown 24.0 fps, dropped 0, A/V offset +20 ms, ..., queued rate ~24`.
  Decode fps should equal 23.976 after the start; queued rate ~24 (the pacing works); dropped 0 in steady state;
  A/V offset between 0 and +42 ms.
- On exit: `Final: ... frames decoded, ... shown, ... dropped`, `decoder closed (session end)`, exit code 0.

Screenshot `shot.png`: the left-eye picture of the film, correct colours (not green/pink: chroma swapped or wrong
offset), no grey band at the bottom (padding lines), no image from the right eye at the right edge.

In the headset: the screen in 3D (close one eye, then the other: each sees its own half), no tearing or flashes of old
frames (a sign of a buffer re-queued too early), lips in sync.

## Verified vs not verified

Verified in WSL (no device):
- The module compiles into the arm64 `template_debug` (dev, `-O0`) build with no warnings in the new files.
- The access-unit splitter port gives exactly `v4l2dec --parse-only`'s results (count, max, average, SPS size changes)
  on `hevc8_3840x2160_60.h265` (600), `reschange.h265` (360, size change at 180) and `documentary_sbs.h264`
  (63,311 = 2640.6 s at 23.976 fps, SPS 3840x1088, display 3840x1080, max 1,767,816 bytes); `seek()` resumes on the same
  boundaries (host build of the same source).
- Under `qemu-aarch64-static`, headless: `V4L2Decoder`, `HWVideoTexture` and `HWVideoPlaneTexture` are registered, the
  project's scripts and shader load, `--probe` prints the numbers above through the engine, and without a decoder
  `open()` fails at once with `Can't open the decoder /dev/video-dec0: No such file or directory ...`, the project
  keeps running to `--quit-after` and exits cleanly.

Not verified (needs the device):
- Everything after the device open: the H.264 session on the iris decoder (only HEVC was run in spike 01), the pacing
  and the measured rate, the frame times vs display order, the CAPTURE layout for 3840x1080 H.264 (pitch, padding to
  1088, chroma offset), and Turnip importing the decoder's own EXPBUF dmabufs (spike 02 imported DRM dumb buffers).
- The acquire/release ownership protocol and the requeue delay under real decoding (tearing or stale frames would show it).
- The proxy-texture switch per frame on the Mobile renderer, and `VIEW_INDEX` eye selection in the XR eye buffers.
- A/V sync quality, and how long it runs (thermal, 44 min).
- Seek to start, the restart after the end, resolution change and the session-restart fallback in this code (the logic is
  `v4l2dec.c`'s, which was verified, but this port was not).

## Open questions

1. **Orphaned buffers at re-setup.** On a resolution change or session restart, the decoder tears down CAPTURE
   (STREAMOFF, close EXPBUF fds, REQBUFS(0)) while Vulkan may still hold imports of the old buffers (they are freed
   `frame_delay + 1` frames later). vb2 keeps the memory alive while a dmabuf reference exists, but the iris driver's
   handling of orphaned, still-imported buffers is unverified. If it misbehaves, the decoder must wait for the consumer
   to drop the old generation before REQBUFS(0).
2. **Hang detection vs pacing.** When paused with the decoder holding input and a free CAPTURE buffer, it should finish
   the input within 5 s. If iris keeps an OUTPUT buffer until the next one arrives, a long pause would trip the hang
   detector. Watch for a `HANG` after pausing.
3. **XR display latency** is not in the A/V clock. The XR runtime's predicted display time
   (`XRInterface` / OpenXR `predictedDisplayTime`) could replace the guess.
4. **Q08C (UBWC)** CAPTURE: imported since PLAYER_UBWC, as two Vulkan images over the same dmabuf (see "UBWC capture
   (Q08C), an experiment"). Not yet run on the device. NV12 stays the default until it is.
5. Whether `lead_time` 0.25 s and 12 CAPTURE buffers are the right defaults (memory: 12 × 6.3 MB at 3840x1088; at 8K
   44 MB each).
6. Render thread model: written for the default (`rendering/driver/threads/thread_model` single-threaded). The
   multi-threaded model should work (all RD work goes through `call_on_render_thread`, one frame of extra margin), but
   wasn't run.
