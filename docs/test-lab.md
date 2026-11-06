# The test lab

Idea #48 in `docs/ideas.md`. Calibration cards that play like video, and a bandwidth meter for files on a share. They
are for checking the headset, the display path and the network, not the film.

## Calibration cards

The cards are video sources with `lab://` paths (`app/scripts/video/lab_video_source.gd`, drawn by
`app/scripts/video/lab_card.gd`). They are built on the test-pattern source, so each card goes through the real path:
NV12 encode, video shader, crop and eye selection. Opening one makes the five cards the playlist, so A and B step
through them.

| Path | Frame | What to look for |
|---|---|---|
| `lab://alignment` | 3840 x 1080, full SBS | Nonius lines: the left eye draws the upper half of a vertical line and the left half of a horizontal one, the right eye the other halves. Fused, they make one straight cross when the two pictures line up. A step shows a misalignment, read against the tick scale (2 px per tick, long ticks every 10 px). Each eye has its own grid colour. |
| `lab://convergence` | 3840 x 1080, full SBS | Seven rings at -64, -32, -16, 0, +16, +32 and +64 px of disparity, from near to far. Each should fuse into one ring. Far rings that stay double ask the eyes to diverge: the IPD or the screen size is off. |
| `lab://judder_24`, `_30`, `_60` | 1280 x 720, mono | A bar that crosses once every 4 s, a ball that turns once every 2 s, and a row of cells that lights one per content frame. One picture is presented per content frame, timed from the playback position like a decoder's frames. The bar should glide evenly. A cell held for two refreshes or skipped shows a repeated or dropped frame. |
| `lab://av_sync` | 1280 x 720, mono, with sound | A/V latency (#24, app-features): the card flashes white for two frames at each whole second while its own audio track beeps (30 ms, 1 kHz). The track is the player's audio and so its clock, as a film's is: move the A/V offset (Sound tab) until flash and beep land together. The offset is then remembered for the display's refresh rate (`scripts/play/av_latency.gd`). |
| `lab://zoneplate` | 3840 x 2160, mono | Sharpness: a zone plate, rings whose spacing shrinks from the centre out to half a cycle a pixel at the corners, so every frequency the frame can hold is on it. Shrunk on the display, a good filter fades the fine rings to grey; a poor one shows false rings (moiré) and shimmer as the head moves. A still: drawn once (`shaders/lab_pattern.gdshader`). |
| `lab://zoneplate_360` | 7680 x 3840, 360° mono | The zone plate as an 8K 360° frame, about twice what the display shows per degree: the case the video shader's filter has to handle. |
| `lab://starfield_360` | 7680 x 3840, 360° mono | Single-pixel stars, a few in a thousand pixels, of random brightness: they should stay steady as you turn the head, not twinkle or drop out. |

Open them from the pane, with `--file=lab://alignment`, or remotely with `open lab://judder_24`. `lab_cards` lists them.

## Bandwidth meter

```
python tools/listener.py send bandwidth_test path=smb://desktop-pc/Movies/film.mkv seconds=8
```

It opens the file with its own MediaSource on a worker thread. It takes the video packets as fast as the demuxer
gives them, and seeks to a new place every 1.5 s so the read-ahead keeps refilling. It samples the bytes read every
0.5 s. It reports:

- `mbps_avg`, `mbps_peak` and the samples;
- `open_ms`, the connection, login and probe time;
- `megabytes` read;
- for smb://: `network` {refill_mbps, stalls, reconnects, requests}.

It needs the player engine (MediaSource). Playback is not touched.

## For the pane's System tab (app-shell)

```
const TestLab := preload("res://scripts/dev/test_lab.gd")
for card in TestLab.cards():              # [{path, label, description}]
	add_row(card.label, func(): main.open_path(card.path))
var r: Dictionary = await TestLab.measure_async(get_tree(), path, 8.0)   # the bandwidth meter; never blocks
```

The bandwidth meter needs a path. The file the user last opened from a share is a good default, with a field to
change it.

## Tested

On the desktop only, on 2026-10-31.

- **The cards** rendered with the stock 4.7.2 Windows build. Screenshots showed the left eye's red nonius half-lines
  and ticks, the seven convergence rings with their labels, and the judder bar, ball, cells and frame counter.
- **Timing.** judder_24 drew 96 pictures in 4.0 s of playback. judder_60 drew 236 of 240 on the 60 Hz desktop,
  which shows the beat between the content and the display.
- **The bandwidth meter** ran in the fork's x86_64 build in WSL on a local 26 MB MKV: 87 Mbit/s average and 120
  peak over 4 s with seeks. On the stock build it refused with the reason.

Not tested on the device: the cards in the headset (the point of them), the judder cadence at 72 and 90 Hz, and the
meter over SMB on Wi-Fi.
