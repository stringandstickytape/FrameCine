# PC audio sync

Idea #9 in `docs/ideas.md`. A PC plays the film's sound. The Frame plays silent and keeps its picture in step with
the PC's speakers. This page covers the stream, the PC sink, the clock reports and the two ways the headset gets
the sound.

## The parts

- **Headset:** `app/scripts/dev/pc_audio.gd`. It connects out to the PC; nothing listens on the headset. It sends
  the sound as 16-bit stereo, by pull or by capture (see "Pull and capture").
- **PC:** `tools/audio_sink.py` listens on port 47820. It plays the sound through `sounddevice` or `pyaudio` if one
  is installed. Otherwise it consumes the frames on the PC's clock, as a speaker would, and with `--wav` writes them to
  a file. Either way the clock reports are real.

```
python tools/audio_sink.py                       # on the PC
python tools/listener.py send pc_audio host=PC   # or start the app with --pc-audio=PC[:PORT]
python tools/listener.py send pc_audio host=PC mode=capture   # or --pc-audio-mode=auto|pull|capture
python tools/listener.py send pc_audio_status
python tools/listener.py send pc_audio on=false  # sound back on the headset
```

## The stream

Over one TCP connection from the headset to the PC:

- **Headset to PC:** one JSON line `{v, rate, channels: 2, format: "s16le"}`. Then frames: `"A"`, a u32 byte
  count, an f64 media time of the first sample, an f64 headset clock, then the PCM. A JSON line `{t: "ping", h}`
  goes once a second.
- **PC to headset:** `{t: "clock", media, buffer_ms, underruns, drift_ppm, dropped, repeated, jumps}` 10 times a
  second, and `{t: "pong", h}`.

Each frame's media time continues from the last frame's. It follows the player again only when the stream jumped by
more than 0.15 s, as after a seek. The player's position moves in mix-sized steps, so stamping each read on its own
would jitter.

## Pull and capture

`mode` picks the way. `auto`, the default, pulls when the engine can and captures otherwise. The choice is made again
for each file. The log line "PC audio: sending to ..." and `pc_audio_status` say which way is in use.

- **Pull**, from PLAYER_REQUESTS on. The headset takes the decoded sound from the engine with
  `MediaSource.read_audio_frames()`, at the source's output rate. That call drains the same buffer as the player's
  audio stream, so the player gives up its stream while PC audio pulls (`player.audio_external`) and the video runs
  on frame time. The headset takes as many frames as real time has passed, at most 0.5 s after a stall. It takes
  none while paused or while a seek settles. The sync error is the PC's media time now minus the video's position:
  - above 80 ms it is fixed at once. When the PC is behind, the sound skips ahead by the error. When it is ahead,
    nothing is sent for that long. The next fix waits a second, until the change has reached the reports;
  - below that, `MediaSource.set_external_clock()` gets the audio position less the error. The engine then resamples
    the sound by up to 0.5 % until the error is gone.

  `pc_audio_status` gives `sync_error_ms`, `jumps` and the engine's `external_clock_error_ms` and
  `external_clock_ratio`. Every 10 s the log has a line with the same numbers. Playback speeds other than 1 are not
  handled in pull mode, so use capture for them.
- **Capture**, with any engine, and for the test tone. The player's AudioStreamPlayer goes to a muted bus,
  "PCAudio", with an AudioEffectCapture. The headset goes silent, and the captured frames are exactly what it would
  have played, at the mix rate. The delay correction below keeps the picture in step.

## The clock and the delay (capture)

- **The PC's jitter buffer** holds 120 ms (`--target-ms`). Near the target it drops or repeats up to 1 % of the
  frames to stay within 20 ms of it. This absorbs the drift between the PC's sound card and the headset's mixer. A
  backlog of more than 250 ms is skipped at once. Audio that does not follow on from the last (a seek on the headset)
  empties the buffer and starts again. `media` is the media time at the speaker now: the last frame handed to the
  device, less the device's latency.
- **The headset's delay** is its own audio clock minus the PC's media time now. The PC's time is the last report,
  aged by the time since it arrived, plus half the ping round trip. The delay is smoothed (20 % per report) and
  sets `player.av_offset` to the user's offset minus the delay, so the video is later by the delay. After the first
  report it moves at most 20 ms per report. Turning PC audio off restores the user's offset and the bus.
- **No external clock in capture mode.** Before pull mode, each report went to `set_external_clock()` as the PC's
  bare media time. The engine compares that clock with the last frame taken, which the PC plays about 150 ms later.
  So the gap never closes, and the engine would have slowed the sound by 0.5 % for the whole film. Capture mode now
  leaves the engine's clock alone.

`pc_audio test_tone=true` sends a 440 Hz tone with a 10 ms click on every whole second, on an exact clock, instead of
the film. It checks the transport, the sink and the delay where no film plays in real time.

## Tested

On the desktop only, on 2026-10-31.

- **The test tone** (stock 4.7.2 Windows, the sink with no audio device): over 18 s the delay held at 114 to 128 ms
  against a PC buffer of 110 to 134 ms. There were no underruns and no jumps, and the drift settled to a few hundred
  ppm. The WAV the sink wrote had 20 clicks, 0.9998 to 1.0003 s apart, so no audio was lost or doubled.
- **A film** (the fork's x86_64 build in WSL, a VP9 file with Opus sound, under a virtual display): the sound reached
  the PC, and the WAV held it. `av_offset` followed the measured delay and went back to 0 when PC audio was turned
  off. That build decodes this file below real time (0.5 s of film in 4 s after a seek), so the delay figures from
  that run mean nothing.

- **Pull and capture on a film** (the fork's x86_64 build with PLAYER_REQUESTS in WSL, an MKV with subtitles, under a
  virtual display, the sink with no audio device). Each run lasted 45 s, with a seek to 5 s at 25 s:

  | Mode | Start | After the seek | PC buffer |
  |---|---|---|---|
  | Pull | -88 ms, one skip, then 2 to 25 ms | -138 ms, one skip, then 19 to 33 ms, the engine resampling at 0.9995 | 92 to 131 ms, 1 underrun at the seek |
  | Capture | delay 160 to 177 ms, followed by `av_offset` | delay 159 ms | 71 to 154 ms, no underruns |

- **`app/tests/test_audio_external.gd`** (stock 4.7.2 Windows, headless and with a renderer): the player has no
  stream while `audio_external` is on, also for a new file and an audio track change, and the video runs on frame
  time. The stream comes back when it is off. Pull asked of a source without `read_audio_frames()` falls back to
  capture.

Not tested: a real sound card on the PC (`sounddevice` or `pyaudio`), the Frame over Wi-Fi, pull mode on the arm64
build, and how the sync looks and sounds to a viewer in the headset. Nothing was tested on the device.
