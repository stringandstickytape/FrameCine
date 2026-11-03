# Spike 04 — worn playback / power runs

## Run 2: 31 min, optimised build, worn / on the forehead (2026-10-31 00:41–01:12)

Same content and player as run 1, `-O2` engine (fork `frame/player` 771004a63f), `--xr-mode on`, 72 Hz, SteamVR. Unplugged
at 00:41:29; worn for the first ~8 min, then balanced on the forehead with the display still on. `session-full-20261031-0041.csv`
(5 s), `threads-full-20261031-0041.log` (10 s, top 20 threads), `spikes/03-player/results/run_xr_full.log`. Stopped at 1869 s.

Playback: **0 frames dropped in 31 min**, decode/display 24 fps, render 72 fps, A/V offset +10…+40 ms, no drift,
no decoder errors.

| | |
|---|---|
| Battery draw, average / peak | **9.05 W** / 14.7 W |
| Charge used | 582 mAh in 31 min (2868 → 2286 mAh, 99 → 79 %) |
| Projected from full | **~2.5 h** of this content |
| Battery temperature | 25.0 → 29.9 °C |
| Hottest zones, peak (≈01:05) | cpuss0 61 °C, cpu7-top 61 °C, decoder 61 °C, DDR 57 °C, GPU 54 °C |
| At the end | 56 / 55 / 55 / 52 / 50 °C — plateaued after ~25 min |
| Clocks | little cluster 2265 MHz the entire run (367/368 samples); mid clusters mostly at max; prime 1.6–1.9 GHz; GPU 310 MHz (55 %), 366 (23 %), 231 (16 %) |

No throttling: clocks did not drop as temperatures plateaued. The draw rises with temperature (7.9 W in the first 5 min →
9.05 W average over 31 min), which is leakage, not workload.

Busiest threads (average % of one core over 151 samples):

| % | Process / thread |
|---|---|
| 16.5 | SteamVR `XRServiceLoopTh` / HmdTrackerQ (inside-out tracking) |
| 11.9 | **our player main thread** (Godot main loop + render submit) |
| 7.5 | vrcompositor / RenderThread |
| 7.4 | eyetracking / ETComputeThread |
| 4.0 | vrserver / posePreDriverCV |
| 3.0 | XRServiceLoopTh / CompShFrameUpda |
| 2.9 | XRServiceLoopTh / TrackingCamPoll |
| 2.2 | XRServiceLoopTh / PreprocessorWor, SparseKFInsert |
| 1.9 | XRServiceLoopTh / RoomViewProcess, PassthroughPoll |

Reading: the decoder feed thread never appears in the top 20, so the hardware path is as cheap as hoped. Our one visible
cost is the Godot main loop at ~12 % of a core. The little cluster pinned at max is the governor's response to SteamVR's
tracking/eye-tracking/passthrough services, which run regardless of the app. Levers to try later: Godot low-processor mode /
max fps = refresh, a lighter main loop, and whether eye tracking, passthrough and room view can be left idle while a video
plays (a SteamVR setting, not ours).

## Run 1: first worn run, 5 min, `-O0` build (2026-10-31 00:20–00:26)

Content: a full-SBS 3D documentary, H.264 High 8-bit 3840x1080 full-SBS 23.976 fps (`documentary_sbs.h264`, ~18 Mbit/s) + OGG Vorbis stereo.
Player: `spikes/03-player/project` on the `-O0` PLAYER engine build (hardware decode → dmabuf → per-plane textures, one
quad 4 m wide 3 m ahead, SBS per eye, audio master clock), `--xr-mode on`, SteamVR session, panels at 72 Hz.
Logger: `powerlog.sh`, 5 s interval, `session-documentary-20261031-0020.csv`. Device unplugged at 00:21:00, worn until ~00:26:08,
then unworn (display blanks) for 30 s, then stopped. Short run: the viewer could not stay for the film.

## Playback (`spikes/03-player/results/run_xr_documentary.log`)

- 6 min 7 s played, **0 frames dropped**, decode and display both at 24 fps, render 72 fps throughout.
- A/V offset (audio clock − shown frame time) +1…+39 ms, no drift. Decode latency avg 120 ms, max 489 ms (start-up).
- Decoder input pacing: 0 OUTPUT buffers held in the driver between feeds, 6–7 CAPTURE buffers queued, 3 frames ready.
- Playback started 2.7 s after launch. Clean so far; a full-length run is still needed for sustained behaviour.

## Power and thermals (worn, 60 samples over 5 min)

| | |
|---|---|
| Battery draw, average / peak | **7.9 W** / 11.9 W |
| Charge used | 76 mAh in 5 min 4 s (2812 → 2736 mAh, 98 → 95 %) |
| Projected runtime from full (2812 mAh at ~8.7 V) | ~3.1 h of this content |
| Unworn (display off, still decoding + rendering), 6 samples | 4.9 W average |
| Battery temperature | 24.3 → 25.9 °C |
| Hottest zones at the end | cpuss0 50.2 °C, cpu2-top 49.8 °C, video (decoder) 47.5 °C, ddr 45.5 °C, gpuss 43.6 °C |
| Temperature rise over 5 min | CPU +3, DDR +4, GPU +4, decoder +1 °C — still climbing slowly, no plateau yet |

Clocks (no throttling seen):

| Cluster | Range during the run |
|---|---|
| policy0 (little cores) | **pinned at 2265 MHz the whole time** |
| policy2 / policy5 (mid) | 1920–2630 / 1824–2438 MHz |
| policy7 (prime) | 1363–2169 MHz |
| GPU | 231–366 MHz (mostly 310) |

## Reading

- The GPU is nearly idle at this load (one 4K NV12 quad per eye at 72 Hz): ~300 MHz. The draw is CPU + system. The little
  cluster sitting at its maximum for the entire run is the first thing to look at: our decoder thread / frame-pacing loop,
  Godot's main loop, or SteamVR's compositor. `top`/`perf` per thread next run.
- 7.9 W for 2D-per-eye video with hardware decode is the baseline to beat; the headset's idle in SteamVR home should be
  measured for comparison, as should 8K HEVC and the 120 Hz panel mode.
- Thermals are far from any limit after 5 min; a 45+ min worn run (with the `-O2` build) is still required.
