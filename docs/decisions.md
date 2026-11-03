# Design decisions

Each entry: what was decided, why, and what would change it. Dates are when the decision was made on evidence from the
device (Steam Frame, SteamOS 0.4.5, kernel 6.18, Mesa 26.3-devel Turnip, SteamVR 2.19).

## D1. Engine: our Godot fork, patched directly (2026-10-30)

Godot 4.7 Mobile renderer on Vulkan, built from `stringandstickytape/godot` branch `frame/4.7` (from 4.7.2-stable) with the
new `modules/hwvideo`. No GDExtension: the zero-copy path needs engine internals (`texture_create_from_extension` with a
plane, queue-family ownership transfer in the render graph, YCbCr sampler support) that the extension API does not reach.
We can already build and ship a patched engine (the x86 game does). Would change if: a GDExtension-reachable path to import
a multi-planar `VkImage` appeared upstream.

## D2. XR: OpenXR only, projection layer + quad layers (2026-10-30)

SteamVR on the Frame exposes projection and quad composition layers only (no equirect, cylinder or cube). So 180/360/fisheye
/EAC are meshes drawn in the projection layer, flat video and UI can go in quad layers (sharper, composited by the runtime).
OpenXR 1.1 instance creation fails on this runtime; Godot falls back to 1.0, which is fine. Refresh rate is fixed per package
via `vrpreferences.json`, not switchable at runtime. Launching from ssh inside the gamescope session works with
`DISPLAY=:0 --display-driver x11`.

## D3. Decode: our own V4L2 stateful M2M client, hardware only above 1080p (2026-10-30)

`/dev/video-dec0` is Valve's fork of Qualcomm's `iris` driver. Characterised in spike 01: H.264/HEVC/VP9 input up to
8192x8192; NV12 or Q08C (UBWC) output for 8-bit; 10-bit only to Q10C, which Turnip cannot sample (P010 needs the 7.2
preview kernel). HEVC 8-bit decodes 8192x4096 at 118 fps. An admission check (`mbpf × max(30, queued_rate) × sessions ≤
7,833,600`) rejects re-setup with ENOMEM if input is fed faster than real time, so input is paced. FFmpeg's `v4l2m2m`
cannot export dmabufs and GStreamer's `v4l2videodec` crashes on the fork's SOURCE_CHANGE behaviour, so the client is ours;
FFmpeg never decodes video (D9). Software decode (dav1d/ffmpeg) is the fallback for AV1 and for anything the firmware
rejects.

## D4. Frame transport: dmabuf → VkImage, imported once per buffer and cached (2026-10-30)

Decoder CAPTURE buffers are exported once (EXPBUF) and each imported once as a two-plane NV12 `VkImage` with the DRM
modifier. Both are verified on the device: `0x0` linear (NV12), and `0x0500000000000001` UBWC (Q08C), whose planes read
back byte-identical to NV12 at a lower GPU time. Q08C is the default since PLAYER_P010; NV12 is the automatic fallback
when the import fails, and `--capture-format=NV12` in the spike. Per-frame import oopses the 6.18
kernel (`msm_gem_import` error path; fixed upstream in 7.3). Ownership moves FOREIGN ↔ graphics through the render graph so
no transition discards externally written contents. One shader does YUV→RGB (BT.709 limited), crop to the visible rect and
stereo eye selection. Verified flat and in VR (spike 02, spike 03).

## D5. A/V sync: audio is the master clock (2026-10-31)

Godot's audio output position (+ time since last mix − output latency + user offset) drives frame selection; the newest
frame at or before the clock is shown, late frames dropped. Measured +1…+40 ms, no drift, over a 6 min XR run. Display
latency in XR is not compensated yet; a user-adjustable offset exists.

## D6. Build: Ubuntu aarch64 cross toolchain, full optimisation (2026-10-31)

`build/build-frame.sh` cross-builds from WSL with Ubuntu's `aarch64-linux-gnu-g++` 13.3 (`use_sowrap=yes`, Vulkan only).
Stock Godot 4.7 drew no 3D at `-O2` with this toolchain because of strict-aliasing UB in the forward renderers'
`InstanceData` setters; fixed in the fork (`baa246e765`), see `spikes/02-import/results/FINDINGS.md`. For shipping, Godot's
buildroot SDK (gcc 15) remains an option for glibc compatibility. The Vulkan loader's dlclose of the Turnip ICD at exit
(crash under live worker threads) is worked around in the fork by pinning the ICD. A `WorkerThreadPool` task that is
never waited for kept its Callable until after the script languages shut down, and freeing a GDScript lambda then
corrupted the heap at quit ("corrupted size vs. prev_size"). The fork releases those Callables just before the languages
finish and warns with the count (`42175b2a3c`). Scripts should still wait for every task.

## D7. Nothing goes upstream (2026-10-31)

Fixes and evidence live in the fork and in this public repo only.

## D8. Power budget: measure worn, with real content (2026-10-31)

First worn run (5 min, 3840x1080 SBS H.264 + stereo audio, 72 Hz): 7.9 W average, ~3 h projected, GPU ~300 MHz, no
throttling. The CPU is the cost; the GPU is nearly idle for 2D-per-eye video. SteamVR's tracking threads are a large
fixed share. See `spikes/04-power/results/`.

## D9. Containers and audio: a static LGPL FFmpeg in the engine module (2026-10-31)

`MediaSource` (modules/hwvideo) opens MKV/WebM, MP4/MOV, MPEG-TS and AVI with libavformat on one worker thread, hands the
video's access units (Annex-B, parameter sets in band after every seek, PTS in seconds) to the V4L2 decoder, and decodes
the selected audio track with libavcodec + libswresample to stereo float at the mix rate, into the `AudioStreamMedia` that
is the master clock (D5). FFmpeg `n8.1.3`, static, LGPL configuration, only the needed components (`build/ffmpeg-build.sh`):
no video decoders, no network; zlib from the engine's own copy; +3.1 MB on the arm64 binary, no new shared libraries. Static linking keeps the
binary self-contained on SteamOS. The LGPL asks that users can relink against a modified FFmpeg; the engine fork's public
source should provide that (to confirm before a release). Would change if: we need network protocols (then shared
FFmpeg, or more components), or the LGPL terms of a release require shared libraries. Tested headless on x86_64 with
13 files (MKV, MP4, TS, AVI); the first build played a full-SBS 3D MKV on the Frame.

After every seek, an end-of-sequence NAL unit goes in front of the keyframe by default (`V4L2Decoder.seek_eos`), so a
keyframe that isn't an IDR picture (HEVC CRA, H.264 recovery point) is treated as a random access point. On the device it
goes in an OUTPUT buffer of its own (default 2): in the keyframe's buffer iris rejects it, one decoder error per seek;
on its own, no error and the same settle time. MPEG-TS plays through iris. Subtitle events come from the same demux thread (text decoded by FFmpeg,
bitmaps as raw packets); rendering is a later layer.

## D10. Network files: libsmb2 in the engine, read ahead on its own thread (2026-10-31)

Films are played straight from SMB shares (a PC or NAS on the LAN): `MediaSource.open("smb://host/share/path")`, with
`MediaBrowser` listing shares and folders. libsmb2 (SMB2/3, NTLMSSP), static like FFmpeg, feeds FFmpeg through a custom
AVIOContext over a 16 MiB readahead ring filled by a thread of its own (1 MiB requests, 4 in flight), so Wi-Fi latency
never reaches the demuxer; lost connections are reopened and reading resumes. Credentials live in a static registry
(`set_smb_credentials`), never in paths or logs. Rejected: FFmpeg's `smb` protocol (libsmbclient, Samba, GPL) and mounting
the share (needs root in a shipped app). libsmb2's client library is LGPL 2.1 or later, not BSD-2 as first thought; the
same static-linking note as D9 applies. SMB3 signing, which the PC requires, cost a whole host core at 900 Mbit/s in
libsmb2's own AES-CMAC; our patch (`build/libsmb2-patches/`) uses the CPU's AES instructions and no copy (0.43 ms per
MiB on the host). Would change if: Kerberos-only servers matter (libsmb2 can use libkrb5/GSSAPI), or NFS is wanted.

## D11. UI: one front panel, opened and pointed at with either controller (2026-10-31, revised the same day)

The menu is a single borderless panel in front of the headset. The menu button on either controller opens it about
0.6 m in front of the head at eye height, facing the head, wherever the head points; it then stays world-locked. It
is always level (no roll, its top edge horizontal); only when looking nearly straight up or down (lying back) does it
take the head's up. A short press closes it; a 0.6 s hold recentres it. The controller that opened it is the pointer
(laser, trigger click, stick scroll and slider nudge, stick focus without aiming); the other controller's position
never matters, and one controller is enough. The header carries the clock, time left and battery. Inside it is a
normal tabbed application (Files / Picture / Sound / Subtitles / Room / System) with the existing list browser; no
library menu, no metadata scraping (revised by D19: the user asked for a local Library with artwork, inside Files). Styled from one token set so themes come later without touching code.
Settings: `[pane] distance` (0.6 m), `scale` (1.6, 38 cm wide: what read well in the headset; 0.9 m did not),
`recentre_hold`, `world_locked` (false: a lazy head follow). Full spec: `docs/ui-design.md`, "Revision 2"; the first
design and its mockups are kept there as history.

Changed because the headset run showed the hand-held pane and glance state unusable; one controller must suffice.
The first version was a pane carried by the left controller, with hidden / glance / open states chosen by a reading
pose (view and face cones with hysteresis), a freeze while the right laser pointed at it, and a docked state on the
menu button. The docked state is now the only state, as this entry anticipated. Would change if: the device run shows
the world-locked panel is in the way of the film often enough that a smaller or dimmed panel is needed.
## D12. The P010 decoder module: a signed, self-updating install the app does once (2026-10-31)

The patched `iris.ko` (P010) passed every device test when loaded in memory (P010 bit-exact with software decode,
8-bit NV12 unchanged, 8K P010 at 93 fps, 720p/2160p/HDR10 played in the engine). It is installed persistently by
`build/iris-module/iris-setup.sh`, which the app runs: the user types the headset password once in the app, and from
then on every step is automatic, also after a SteamOS kernel update (a later player release brings the module for the
new kernel, and the app installs it with no question). Nothing in the OS image changes: the files go to a root-owned
`/home/.vr-video-player-iris` (persistent; `/var` is per slot), plus a systemd unit, a sudoers rule and a keep list in
`/etc` that atomic updates keep. A start-up service swaps the module before user sessions start; a marker on disk
skips the swap after a start-up that crashed or hung during it. A live swap kills only the processes that hold the
decoder (Steam's web helper, which restarts by itself), because stopping `steam.service` would kill the player in its
cgroup. Updates through `sudo` need no password but take only modules signed with the key recorded at install (RSA,
private key on the build PC only). The signed modules are committed in `build/iris-module/dist`, so a package can be
built without WSL. Rejected: loading with `load-temporary.sh` at every app start (a password every time, or a much
wider sudo rule); `/etc/modprobe.d` or files under `/lib/modules` (lost at the next atomic update, and the rootfs is
read-only); stopping `steam.service` for the swap. Would change if: Valve's kernel ships P010 (the 7.2 driver may),
or SteamOS adds a supported way to add kernel modules. Tested on the PC only so far (`tests/test-iris-setup.sh`);
the device test is in `docs/morning-checklist.md` F.

Superseded by D21 (2026-11-02): the module and its setup are removed.

## D13. VP9 in hardware, one session at a time (2026-10-31)

On the device, sequential VP9 sessions decode cleanly (8-bit and 10-bit, about 1000 fps, VP9 and HEVC sessions in
turn), but two VP9 sessions at once crashed the decoder firmware, and killing the process afterwards oopsed the kernel
and needed a reboot (SteamOS #2865). The engine therefore decodes VP9 in hardware with at most one VP9 session per
process: a second VP9 video (gapless next item, picture in picture, thumbnails, crossfade) decodes in software up to
about 1080p, or fails with the reason, and never opens a second session. A VP9 session that shows decoder faults
(DQBUF failures, a run of error buffers, no picture for its input, a hang) closes the device itself and the player goes
on in software from the same position; hardware VP9 then stays off until the player restarts. A setting
(`[hwvideo] hw_vp9`, `HWVIDEO_HW_VP9=0/1`) turns hardware VP9 off. Rejected: refusing VP9 in hardware altogether (the
earlier policy; it wastes the CPU on the most common web format, and 2160p VP9 can't decode in software at all);
serialising sessions across processes with a lock file (other programs that decode VP9 wouldn't take it). Would change
if: Valve fixes the concurrent-session crash, or the device run shows that seeks or long sessions also crash it.

## D14. 10-bit without the patched module: Q10C through the GPU's YCbCr sampler, checked, else software (2026-10-31)

The stock iris module writes 10-bit video only as Q10C (UBWC-compressed TP10). Another player on the same headset
imports Q10C into Vulkan as a multi-planar image with a DRM format modifier and samples it through a YCbCr sampler, so
Valve's Turnip must decompress it; upstream Mesa can't (no TP10 code, and its `G10X6` 2-plane UBWC layout is P010).
The engine now does the same: each Q10C buffer is one multi-planar image read only through a sampler with a YCbCr
conversion (RGB_IDENTITY, full range: the raw codes), by a compute pass recorded in the RenderingDevice graph that writes
P010-like R16 and R16G16 textures. So the app's shader (matrix, range, PQ/HLG tone mapping, BT.2020) stays the one
source of truth and needs no change. The format, modifier and plane layout come from what the driver lists, with
environment overrides, and the first candidate that imports is kept. Order: P010 when the decoder offers it, then
Q10C, then software. A wrong guess must not show noise: the first frames are read back once (no stall) and judged (a
decoded picture is smooth, a misread one is noise); an import or check failure goes on in software and turns Q10C off
for the run. Rejected: patching RenderingDevice to bind YCbCr samplers in materials (invasive: immutable samplers would be
needed on combined image samplers, and views with conversions, in every material); unpacking TP10 in our shader (the
texture unit returns wrong data, closed earlier). The spike-04 probe settles which candidate is right in one device run.
Would change if: the probe shows none works (then 10-bit without the module stays software), or Valve ships P010.

## D15. Assistant on a PC: a consumer link on 47801, paired with a code, the headset dialling out (2026-10-31)

The dev link (47800) stays a developer tool: no authentication, code with `--dev-code`, every command. Consumers get a
separate link on 47801 (`docs/assistant.md`): off by default, a fixed command whitelist (read; playback control and
room changes each behind their own switch; cards), no code, and its own protocol version. The headset dials out to
the PC and never listens (the standing rule: Claude listens, the headset talks). Pairing needs no typing in the
headset: the headset shows a 6-digit code derived from an RSA key exchange with committed nonces, the user types it
on the PC, and the user confirms in the headset that the PC says "Paired". After that, every session is an HMAC
challenge both ways and every line is signed with a sequence number, so no secret crosses the wire and no TLS is
needed on the LAN. The PC side is one port for the headset and a local HTTP API (127.0.0.1 unless the user allows
the LAN with a token), self-describing (a guide at `GET /` for an AI agent, OpenAPI), with server-sent events; MCP is
one adapter over it, not the product. Room changes are data (a versioned room document), shown as a preview with
Keep and Undo, and kept as recipes. Rejected: reusing the dev link with a permission mode (too wide, and its
unauthenticated port would still be open); TLS with certificates (a trust store to manage, and nothing secret is
sent); a password typed in VR; a PIN check without a key exchange (the PIN would leak to a passive listener); an
MCP-only PC side (it can't push to the model, and only MCP clients could use it); assistant-supplied scripts in rooms
(the assistant runs its code on its own machine and sends the result). Would change if: an MCP client gains a way for
a server to start a turn (then the adapter can push), or the headset gains a system-wide pairing service.

## D16. The assistant service lives on the headset: HTTPS on 47801, paired with a code, nothing on the PC (2026-10-31)

Supersedes D15's transport. The acceptance test is a new Claude Code or Codex session that knows nothing about the
project and is told only the headset's address: it must pull the guide from the headset, pair, keep listening to the
viewer, answer on the card, and control playback or the room when allowed, with no program installed and nothing run
by hand. A PC server can't meet that (someone has to start it), so the headset serves the API itself
(`docs/assistant.md`). Off by default; the port opens only while "Let an assistant find me" runs (60 minutes, the
user's number; the guide and pairing need no token then) or once an assistant is paired (then only paired assistants
get past the guide). Pairing: the assistant asks with its name, the headset shows a 6-digit code, the viewer reads it
out; three wrong codes end the attempt, nine close the window, one attempt at a time. The token is 32 random bytes;
the headset keeps only its SHA-256. HTTPS with a self-signed certificate made once on the headset; its public-key pin
comes with the token, so after pairing curl (`--pinnedpubkey`) and Python check they talk to this headset. Only
private source addresses are served, as the phone remote. The whitelist, permissions and room documents stay as D15
had them (Keep/Undo was dropped later the same night, at the user's word "just assume keep; the AI can always change
it back": every room change is kept at once); speech to text moves to the headset (D17), and a message without text carries an audio link
the assistant can transcribe itself. The guide is markdown for an AI reading cold and avoids JSON on the command line
so it works with curl.exe in PowerShell. Rejected: keeping the PC server (a program to run); a cloud relay (WAN, never);
no TLS (the token would cross the LAN in clear); pairing that binds the code to the TLS channel (needs a PAKE; the
residual risk is an active attacker on the LAN during the minute of pairing). Would change if: the engine's TLS
client learns to read TLS 1.3 replies from its own server (then the in-engine test can use HTTPS too).

## D17. Speech to text on the headset: whisper.cpp's server as a child process, CPU first (2026-10-31)

The assistant moves onto the headset (D16), so push-to-talk speech is transcribed there too, not on a PC. whisper.cpp
(MIT; tag v1.9.5, pinned by commit in `build/whisper-build.sh`) is built for aarch64 with NEON, dotprod, i8mm and fp16,
libstdc++ static and nothing newer than glibc 2.38 (as the engine), and ships in the package's `whisper/` folder with
one model (`small.en` q8_0, 264 MB; MIT weights; chosen after the device benchmark: an 11 s clip in 2.3 s with 6
threads, and a 2160p film dropped no frames meanwhile). The app starts `whisper-server` only when the assistant needs it
(`scripts/voice/whisper_backend.gd`), on 127.0.0.1, a free port and a random route prefix, with the model loaded once;
clips go to it as WAV over HTTP from a worker thread, so a frame never waits. Finals use beam 5 and the vocabulary
prompt (as on the PC), live partials are greedy and dropped while a request runs. The server restarts once if it dies; a
missing binary, model or CPU feature leaves `Transcriber.available()` false with one log line. A Vulkan build (the GPU
through Turnip) is built and deployed for comparison, not used by default: the GPU renders the film and the compositor's
frames, while hardware decoding leaves CPU cores free (the benchmark checks both). Rejected: linking whisper.cpp into
the engine (a crash, or a model of up to 264 MB, in the player's process; a rebuild of the engine for each model or flag
change); a GDExtension (the same, plus the ABI); a resident process started with the app (memory for a feature used now
and then); faster-whisper on the headset (Python, CTranslate2 and its wheels in the package); sending audio to a PC or a
cloud service (the point is that it runs on the device). Would change if: the headset benchmark
(`tools/whisper-bench.sh`) shows `base.en` finals too slow or `small.en` fast enough with a 4K film playing (then the
default model changes), or the Vulkan build is faster without costing the film frames.

## D18. Every format: every FFmpeg decoder in software, LGPL only, dav1d for AV1, no licence fees (2026-11-01)

The engine's FFmpeg (`build/ffmpeg-build.sh`, prefixes `~/src/ffmpeg-<arch>-all`) now has every native decoder
(video, audio, subtitles), every file demuxer, all parsers and bitstream filters, and libswscale; AV1 is decoded by
dav1d (`build/dav1d-build.sh`). The hardware path is unchanged: H.264, HEVC and VP9 go to the iris decoder (the
only formats `/dev/video-dec0` takes). Everything else goes to `SoftwareVideoDecoder` on the CPU: FFmpeg's decoder
with frame threads (where it has them; dav1d its own), each picture converted to 8-bit NV12 (4:2:0 copied, the rest
through swscale to the matrix and range the shader uses), shown by the same shader. Engine branch `frame/codecs`.

Why: a real library (2359 videos) is 62 % formats the hardware can't decode: MPEG-4 part 2
(DivX/Xvid, 1016 files, nearly all 576 lines or fewer), MS-MPEG4 v3 (264), MPEG-2 (123, mostly DVD VOBs), MPEG-1
(34), WMV 8 (17), Flash H.263 (9), RealVideo 4 (8) and VC-1 (2, 1080p). They are SD and old: an 8-core ARM CPU
decodes them with room to spare.

| Goes to | Formats |
|---|---|
| Hardware (iris, V4L2) | H.264, HEVC, VP9 (8-bit; 10-bit as in D14), as before |
| Software, up to 1920 x 1088 (`software_max_pixels`) | MPEG-4 part 2 (DivX 4/5, Xvid, MP4V, 3ivx), MS-MPEG4 v1/v2/v3 (DivX 3), MPEG-1, MPEG-2 (DVD, SVCD, 1080i TV), H.263 / H.263+, H.261, Flash H.263 (FLV1), VP6, WMV 7/8/9, VC-1, RealVideo 1-4, Theora, VP3, VP8, MJPEG, DV, ProRes, DNxHD, Cinepak, Indeo, Sorenson, HuffYUV, FFV1, ... (every FFmpeg video decoder); and H.264/HEVC/VP9 the hardware path can't show (as before) |
| Software, more pixels | AV1 (dav1d): up to 3840 x 2160 at 30 fps, 2560 x 1440 at 60 (a pixel rate of 4K30) |
| Audio (always software) | every FFmpeg audio decoder: MP3, MP2, AAC, AC-3, E-AC-3, DTS, TrueHD, Vorbis, Opus, FLAC, WMA 1/2/Pro/Lossless/Voice, Cook (RealAudio), ATRAC, AMR-NB/WB, ADPCM variants, Nellymoser, PCM of every kind, ... |

- **Licences.** FFmpeg is configured LGPL-2.1: no `--enable-gpl`, no `--enable-nonfree`, no external library but
  dav1d (BSD-2-Clause); the build script refuses a configuration with GPL or nonfree on. No decoder we need is
  GPL-only or nonfree: those switches add encoders and filters (x264, x265, fdk-aac, some filters), and this player
  only decodes. dav1d rather than libaom (also BSD) because it is several times faster, with NEON; FFmpeg's own
  `av1` decoder only drives hardware decoders. The notices: `LICENSES/` and `THIRD-PARTY.md` in the package
  (`docs/packaging.md`).
- **Patents, briefly (not legal advice).** No licence fees are paid. The patents on most of these formats have
  expired: MPEG-1, MPEG-2, MP3, H.263, AC-3, and MPEG-4 part 2 for the most part. Several are royalty-free by design:
  VP8, VP9, AV1, Theora, Vorbis, Opus and FLAC. H.264 and HEVC were already in the build (decoded by the headset's
  hardware, and FFmpeg's decoders for the fallback).
- **Size limits.** 1920 x 1088 for every codec, as before for H.264/HEVC/VP9 (`HWVideoTexture.software_max_pixels`
  changes it): SD, 720p and 1080p of the old codecs are cheap. AV1 gets more because dav1d is the fastest software
  decoder there is (NEON assembly, tiles and frame threads across all cores), AV1 is what 4K web and VR video
  increasingly uses, and the hardware can't take it: up to a pixel rate of 3840 x 2160 at 30 fps (2560 x 1440 at 60).
  4K60 AV1 is refused with the reason. That limit is an estimate from x86 speeds and published ARM figures, to
  check on the headset (the overlay shows dropped frames). What is beyond a limit shows the stand-in with the reason
  ("1920x1080 AV1 at 120 fps is too much to decode in software on the Frame (...)").
- **Old-container timing.** AVI gives video no PTS (a frame counter as DTS), and MPEG-PS gives one on some frames
  only. `MediaSource` now says which timestamps the container gave (`VideoPacket.pts_valid`, `dts_valid`), and the
  software decoder passes only those, so FFmpeg's `best_effort_timestamp` reorders B-frames from the DTS. DivX 5's
  "packed B-frames" (two pictures in one AVI chunk) go through `mpeg4_unpack_bframes`. Variable frame rate keeps the
  container's times. Some AVIs lose their keyframe flags after a seek in FFmpeg's demuxer (an index in
  milliseconds, frames counted differently): after 300 packets without one, the file is seeked again and the first
  packet taken as the keyframe, its pictures hidden until one is. Files without an index or a timestamp search (FLV
  without its keyframe table) are seeked by bytes at the average bitrate. Damaged pictures are concealed and
  decoding goes on (100 errors in a row end it).
- **Aspect and interlacing.** The sample aspect ratio (anamorphic DVD 64:45 and 16:15, SVCD 4:3, MPEG-1 49:33) comes
  from the container or the codec as before, and the app already folds it into the screen's width. MPEG-2's field
  order comes from the parser (`field_order` tt or bb for DVDs and TV recordings), so the deinterlace feature's
  "auto" engages; the decoder's own count is `software_field_order` in the stats.
- **Size of the binary.** The arm64 engine (template_debug, no symbols) grows by 11.1 MB, from 96.1 to 107.1 MB;
  nearly all of it is FFmpeg's 500 decoders (libavcodec.a alone is 18.3 MB of objects for aarch64; the linker keeps
  what is referenced). dav1d's library is 1.3 MB. Still no shared libraries.

Would change if: the device run shows a codec too slow at its limit (lower that codec's limit), or Valve's iris
firmware exposes more codecs (MPEG-2, VC-1, AV1) to V4L2. Rejected: a GPL build (would make the engine GPL, and
gives the decoders nothing); shared FFmpeg libraries (see D9); transcoding on the PC (not standalone).

## D19. A local Library, inside Files (2026-11-01)

The user's decision, reversing the "no library, no artwork" of D11: a beautiful local library on the headset rather than
cataloguing the network archives. `~/Videos/Library`, in the layout Kodi and Jellyfin expect, shows as posters, seasons
and episodes (`docs/library.md`).

What D11 protected stays. The menu keeps its tabs: the Library is a place in the Files tab, and its rows open like any
other. It is a view of one local folder, not a database: nothing is indexed or scanned in the background, and network
shares are never scanned. The app scrapes nothing and fetches nothing from the web. Agents and assistants fill the folder,
which is why the app's part is small: it reads NFO files and draws them.

`copy_to_library` is how a file gets there from a share, because the headset has no SMB mount and an agent must not see the
login. It needed a read of any size from the engine (`MediaBrowser.open_read`), since `read_file` holds a whole file in
memory and stops at 64 MiB.

Would change if: the library outgrows what a folder read can do when a view opens, or the user wants the shares
catalogued after all.

## D20. The command registry is the assistant's one list; MCP is the agents' main client, HTTP stays the core (2026-11-02)

The goal: an assistant can do everything the viewer can do with the controllers and the menus, and nothing a
developer's tools can. Until now the assistant API had its own hand-written list of 41 commands
(`assistant_commands.gd` SPECS), beside the registry of the dev link and the phone remote (`dev_commands.gd`), and the
guide, `/describe`, the OpenAPI and the MCP adapter each repeated parts of it. Every new feature had to be added in
four places or the assistant could not reach it.

Now the registry is the one source. A command is open to the assistant when its spec carries `"assistant": "<level>"`;
`/describe`, the guide's tables, the OpenAPI and the MCP adapter's tools are made from those tags while the app runs.
The levels are read and card (always), and control, room, settings, files and apps, each behind its own switch in the
System tab, off by default (`docs/assistant.md`, "Levels and switches"). A command at the dev level `code` can't carry
a tag (`register()` drops it), so running code, hot reload and scene editing stay off the API. The dev level and the
consumer level are separate keys because the two permission systems are separate: the dev link's ring trusts a
developer for a while, the assistant's switches stay as the viewer set them.

MCP is how the agents on the headset use the player: each gets the adapter as its own server, and the adapter builds a
tool for every command in `/describe` and follows the `permissions` and `commands` events. HTTP stays the core: the
adapter is a client of it like curl, every check is in the service, and an assistant with only a shell needs nothing
else. Rejected: putting MCP in the engine (a second protocol to secure on the headset, for one kind of client); a
separate consumer registry (the same drift as before); a list of allowed names kept beside the registry (a renamed
command would drop off it without a word).

Would change if: two clients need different views of one command (then a per-client tag), or MCP clients can reach
the headset without the adapter.

## D21. No decoder module: 10-bit plays on Valve's stock driver, P010 waits for the kernel (2026-11-02)

D12's patched `iris.ko` and its one-time setup are removed: `build/iris-module/` (the P010 and AV1 patches, the
targets, the signing key, the signed `kernel-modules` bundle, `iris-setup.sh` with its sudoers rule and boot service,
the tests), the app's setup card with the headset password, the System row's Set up and Remove the setup, the
update, uninstall and restart runs, and the packaging and deploy steps for them. The owner's headset install was
removed first.

Why: on 2026-11-02 the headset played 10-bit HEVC and HDR10 in hardware with Valve's stock driver through Q10C and the
GPU's YCbCr sampler (D14; the log says "Q10C through a YCbCr sampler" and "the Q10C picture looks right"). So the
module bought nothing the stock driver doesn't give, and it was the heaviest part to keep: a GPL subtree, a signing
key, a build per SteamOS kernel, root-owned files in `/home`, and the app's only password prompt. Mainline Linux 7.2
offers P010 natively, so a later SteamOS kernel brings it with no work from us.

Kept: the engine's P010 path and the app's handling of a P010 capture format. When the driver offers both, the engine
takes P010 first (`V4L2Decoder` asks for it when it is offered, and `HWVideoTexture` tries Q10C only without it), so
a kernel with P010 is used as soon as it ships. The System tab's Hardware video row and the read command
`hwvideo_status` (was `hwsetup_status`) say which path 10-bit takes: P010, Q10C or software. Old settings files may
still hold `[hwvideo] iris_bundle` and `iris_setup_prompt`; they are ignored. `tools/morning-deploy.sh --no-kernel`
and `tools/package.sh --no-kernel-modules` are accepted and do nothing.

Would change if: a SteamOS update breaks Q10C through the sampler before its kernel offers P010 (then 10-bit up to
1080p plays in software until it does; a module would come back only if that gap is long).

## D22. Foveated rendering at Low, eye-tracked, without subsampled images (2026-11-03)

The headset renders the eye images with eye-tracked foveation at level Low (`[xr]` in project.godot), and the main
viewport uses VRS XR. The engine fork carries one line from upstream PR 124811 (branch `frame/foveation`): subpass
dependencies by region. Without it the Frame's Mesa driver leaves tiled mode and ignores the density map, so foveation
had no effect.

Measured on 2026-11-03 with a fill-heavy test sphere around the viewer (GPU time per frame, both eyes, median of 360
frames): off 8.4 ms, Low 3.6 ms, Medium 3.6 ms, High 3.1 ms. The viewer could not see Low; High showed blocks at the
edges of the view, on our flat high-contrast surfaces. Low takes almost all of the saving. At Low the edges of the
panel's text still softened, so foveation is off while the panel or the agent pane shows (text is cheap to draw).
The viewer can change both in System, Rendering (`[view] foveation`, default "low", and `foveation_sharp_panel`, default
on; the `foveation` command): project.godot keeps level 1 so the swapchain is made foveated, and the app sets
`OpenXRInterface.foveation_level` from the setting at run time.

Rejected: subsampled images (Godot's default), which the Frame doesn't support yet: with them the whole picture warps
as the head turns (Godot issue 124520); dynamic foveation, which the runtime ignores. Would change if: the Frame adds
subsampled images, or a later engine merges PR 124811 (then the fork's line goes).

## D23. Spatial audio: our own binaural renderer in the engine, not Steam Audio (2026-11-03)

The film's channels and the sound field of 360 videos are rendered binaurally by `BinauralRenderer` in the fork's
hwvideo module (branch `frame/binaural`, `docs/features.md` #21). Godot's own 3D audio only pans with volume and has
no HRTF: front and back, up and down sound alike, and the sound sits inside the head.

- **How:** each virtual speaker gets a fractional delay per ear and a 128-tap FIR, direct convolution with no FFT.
  Both come from an HRTF grid of 48 x 14 directions, interpolated bilinearly and crossfaded when the head moves.
  - The renderer runs inside `MediaSource`'s mix, as the audio is taken, so it adds no latency and the audio clock
    stays the A/V master (D5).
  - Ambisonics are decoded to virtual speakers through the same path.
  - The room is first-order image-source reflections and an 8-line FDN.
  - HRTFs come from SOFA files through a vendored libmysofa (BSD-3-Clause), converted to a 350 KB grid pack.
  - CPU on the desktop: 3.9 % of a core for 12 channels with the head moving, 6.3 % for third-order ambisonics.
- **Rejected: Steam Audio** (Apache 2.0, so the licence was fine).
  - No Linux arm64 build is published. It would be a new CMake dependency (with its own FFT and flatbuffers) to
    cross-build and keep.
  - It processes fixed frames, so it adds a block of latency and needs a second clock path beside the media ring.
  - Its reflections need scene geometry and ray tracing on the CPU that decodes the video.
  - It has no hooks for tuning to a listener (the ITD scale, the pinna warp, the concha gain of phase 2).
- **Rejected: partitioned FFT convolution** (the "libmysofa plus FFT" plan). At 128 taps, direct convolution
  vectorises well (NEON, 4 lanes). It has no block latency and crossfades per 64 frames, for a few percent of a core.
- **Bundled data:** SADIE II (Apache 2.0), six sets, 2 MB. Sets under other licences (CC BY, CC BY-SA, CIPIC's own
  terms) are fetched on request with the licence shown, never committed. Object-based audio (Atmos, DTS:X objects)
  has no open decoder; its channel bed plays.
- **Would change if:** the headset's CPU proves short (then partitioned FFT convolution, or the sources summed into
  a third-order sound field and decoded once); or Steam Audio ships arm64 Linux, if its reflections were wanted.

## Open

- Quad layer for flat video vs. drawing in the projection layer: sharpness and bandwidth comparison (spike 03-layer).
- 120 Hz panel mode vs. 72 Hz: power cost for video.
- Subtitle rendering (libass and PGS/VobSub → quad layer), environments: not started. Ambisonic audio: D23.
