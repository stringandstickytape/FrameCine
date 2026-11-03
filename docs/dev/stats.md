# Stats for nerds

Idea #57 in `docs/ideas.md`. One dictionary holds the numbers that say how playback is going. It covers frame times
and their histogram, the video and decoder queue, the bitrate, the GPU clock, battery power, thermals and CPU. It is
available on the dev link and to the pane.

The code is `app/scripts/dev/stats.gd`, with the device readings in `app/scripts/dev/sysfs.gd`.

## On the dev link

```
python tools/listener.py send stats              # one reading
python tools/listener.py send stats every=1      # and a `stats` event every second (0 stops, minimum 0.25 s)
python tools/listener.py events -f -e stats
```

Rates such as decode fps, bitrate and CPU are measured between two readings. The first reading after a start has no
rates.

## What is in it

| Key | Holds | Source |
|---|---|---|
| `render` | fps, process_ms, draw_calls, objects, video_mem_mb, static_mem_mb | the engine's `Performance` monitors |
| `frames` | count, avg_ms, p50_ms, p95_ms, p99_ms, max_ms, `histogram` {edges_ms, counts} since the last reading | each frame's time, recorded while the node is in the tree |
| `video` | kind, path, width, height, codec, decode_path, playing, frames_dropped, dropped_since_last, decode_fps, bitrate_mbps, `queue`, `network` | the source's `get_stats()` and the MediaSource's `get_stats()` |
| `video.queue` | output_in_driver, capture_in_driver, capture_buffers, frames_ready, aus_queued, queued_rate, latency_avg_ms, latency_max_ms, video_queue, video_queue_bytes | the decoder (HWVideoTexture) and the demuxer (MediaSource) |
| `gpu` | clock_mhz, load_percent, node | `/sys/class/devfreq/*gpu*/cur_freq`, or `/sys/class/kgsl/kgsl-3d0/gpuclk` and `gpu_busy_percentage` |
| `battery` | percent, status, power_w, voltage_v, current_a, temp_c | the first `/sys/class/power_supply/*` of type Battery |
| `thermal` | `zones` {name: °C} for the zones the power spike logged, `hottest` {name, c} over all zones | `/sys/class/thermal/thermal_zone*` |
| `cpu` | process_percent_of_core | `/proc/self/stat`, utime + stime |

The histogram's bucket edges are 5.6, 8.3, 11.1, 13.9 and 16.7 ms, the frame times at 180, 120, 90, 72 and 60 Hz.
Then come 20, 25, 33.3, 50 and 100 ms, and an open last bucket. At 90 Hz, everything should land in the third bucket
or below.

**Bitrate** is the video bytes the demuxer read between two readings. If the engine adds a `bitrate_bps` key to
`MediaSource.get_stats()`, that key is used instead. The decoder queue also picks up `decoder_queue_depth` and
`video_packets_queued` if the engine adds them. Every key is read with a fallback, so older engine builds work.

Missing readings are left out or null. On a desktop, `gpu`, `battery` and `thermal` are empty.

## For the pane

The System tab can show the same numbers. Make a stats node while the view is open and free it when the view closes:

```
const Stats := preload("res://scripts/dev/stats.gd")
var stats := Stats.new()
stats.main = main
add_child(stats)
...
var d := stats.collect()                  # 1 to 4 times a second
for line in Stats.summary_lines(d):       # four short lines of text, or use d directly
	...
stats.queue_free()
```

## Cost

- **Out of the tree:** nothing.
- **In the tree:** one float appended per frame.
- **collect():** about 20 small file reads under `/sys` and `/proc`, two stats dictionaries, and a sort of the
  frame times. Keep it to a few times a second.

## Tested

On the desktop only, on 2026-10-31. The stock 4.7.2 Windows build ran rendered at 60 Hz: the histogram filled the
16.7 and 20 ms buckets, and the stats events came every second. The fork's x86_64 build ran in WSL: the CPU reading
from `/proc` worked there.

Not tested on the device: the GPU, battery and thermal paths, and the decoder queue and bitrate with real hardware
decode. The desktop has no hardware decoder, so the source there was the test pattern.
