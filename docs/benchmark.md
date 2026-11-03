# Self-benchmark

Idea #82 in `docs/ideas.md`. The app decodes a big video file for 10 s as fast as the decoder goes. Then it reports
what the device can do. It is in `app/scripts/dev/benchmark.gd`.

## When it runs

- **Once, by itself, on the first run.** It waits until the app has been idle for 8 s, which means no file is open.
  It looks for the biggest container file in the last file's folder. If there is none, it looks in the local places:
  Videos, Downloads, the home folders and removable media, each with one level of subfolders. It does not look on
  shares. When the user opens a file, it stops at once and does not save. It tries again at the next start, 3 times
  at most. Runs with `--no-save` (tests, screenshot tours) never start it. `[benchmark] auto = false` in the settings
  turns it off.
- **With `--benchmark`** or `--benchmark=FOLDER_OR_FILE`, 2 s after the start. It runs even when a result is saved,
  and prints the result to the log as JSON.
- **With the `benchmark` command** (the PC link and the phone), with `path` (a file or folder, `smb://` too, empty
  to pick one) and `seconds` (default 10):

```
python tools/listener.py send -t 60 benchmark path=/home/steamos/Videos
```

- **From the pane** (app-shell):

```
const Benchmark := preload("res://scripts/dev/benchmark.gd")
var b := Benchmark.start(main, folder_or_file)    # "" picks a file; Benchmark.running() while it runs
b.progress.connect(func(fraction: float, text: String) -> void: ...)
var r: Dictionary = await b.finished              # r.summary is one line; r.error when it could not run
Benchmark.saved(main.settings)                    # the saved result, {} if none
```

## How it measures

It uses its own MediaSource, with the audio off, and its own HWVideoTexture. It does not use the player's. It starts
a fifth of the way into the file, after the titles, because black openings decode faster than the film. It keeps
the texture's clock 2 s ahead of the newest frame shown. The decoder is then fed with no pacing. Each rendered frame
shows the newest decoded frame, and the frames before it count as dropped, as late frames do in playback. So it
measures the decode and import work of playback without the display's cadence.

The window starts at the first frame shown, so the open and the decoder start are not in it. A file that ends
before the 10 s goes back to the start, and the count goes on. If the biggest file does not open, for example
because of an unsupported codec, it tries the next biggest, 3 files at most.

## The result

The result is saved as `[benchmark] result` in the settings. The stats dictionary (`stats` command and event, the
pane's stats view) carries it under the key `benchmark`. While a run is busy, the key also has `running` with
`{fraction, text, path}`. These are the main values:

| Key | Meaning |
|---|---|
| `summary` | one line, for example "HEVC 3840x2160 hardware: 142 fps decoded, 5.9x real time for its 23.976 fps (1178 Mpixel/s). Same codec: 1080p 60, 4K 30, 4K 60, 5.7K 180/360 30." |
| `decode_fps`, `fps_min`, `fps_samples` | decoded frames per second over the run, the slowest 0.5 s sample, and every sample |
| `realtime_x` | decode_fps divided by the file's frame rate |
| `mpix_per_s` | decoded pixels per second; the basis of the estimate |
| `can_play` | `[{label, fps_estimate, ok}]` for 1080p 60, 4K 30 and 60, 5.7K 30, 8K 30 and 60. These are estimates from the pixel rate, for the same codec and decode path. `ok` means at least 10 % over the frame rate. |
| `codec`, `width`, `height`, `bit_depth`, `content_fps`, `decode_path` | the file, and hardware or software |
| `frames_shown`, `frames_dropped`, `loops` | frames shown and dropped, and how many times a short file went back to the start |
| `open_ms`, `first_frame_ms` | the open (on a share, also the connection) and the time to the first frame |
| `cpu_percent_of_core`, `gpu_mhz_max`, `hottest_c`, `power_w` | the process CPU, the GPU clock, the hottest thermal zone and the power, where the device has them |
| `network` | for `smb://`: the read rate and stalls. The share may be the limit. |
| `skipped` | the files that did not open, with the reason |

The estimate scales with pixels only. A file with a different codec, bit depth or bit rate decodes at a different
rate. The hardware decoder also has its own limits by size and level, which the estimate does not know.

## Tested

On the desktop only, on 2026-10-31. The engine was the fork's x86_64 build in WSL, with software Vulkan under a
virtual X display. That machine has no V4L2 decoder, so the hardware path refuses and only the software path decodes.

- **A 10 s VP9 1080p file** decoded at about 260 fps in software, which is 8.6x real time. It went back to the start
  8 times in the 10 s.
- **A folder:** the biggest file (H.264) found no hardware decoder and was skipped with the reason. The next one
  (10-bit HEVC, software) gave 220 fps.
- **The first run** (settings in a separate folder) started after the idle wait and saved the result. The `stats`
  command carried it. The second start did not run it again.
- **Opening a file** while it waited stopped it without counting a try. Opening a file during the measurement
  stopped it and counted one try.
- **The `benchmark` command** ran on a given file, and returned the reason when the file did not open.
- **The stock 4.7.2 Windows build** (no player engine): `--benchmark` refuses with the reason. The menu input test
  (42 checks) passed.

Not tested on the device: the hardware decoder's rates, the 8 s idle wait in the headset, the first-run folder
choice on SteamOS, and a share.
