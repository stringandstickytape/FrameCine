# Visualisers

A visualiser draws the sound of a music file on the music card (#64), the flat screen's picture while music plays.
Each one is a small plug-in: a folder with a shader and a manifest. The app's own are in `app/visualisers/`. The
viewer's own go in `user://visualisers/`, where a person, or a Claude Code session on the headset, can add and change
them without rebuilding anything.

Code: `app/scripts/play/audio_analysis.gd` (the shared analysis), `app/scripts/visualisers/visualiser_registry.gd`
(the folders and manifests), `app/scripts/visualisers/visualiser_host.gd` (runs one, with the flash limit and the GPU
budget), `app/scripts/visualisers/visualiser_service.gd` (making them on the headset),
`app/scripts/visualisers/test_signals.gd`, `app/visualisers/README.md` (the guide an agent reads),
`app/scripts/play/music_source.gd` (the card), `app/shaders/visualiser_*.gdshader` (the flash limit). Tests: `app/tests/test_visualisers.gd`, `app/tests/test_music.gd`.

## Design

- **Screen first.** A visualiser draws on the music card, on the screen. Surround (a dome round the viewer) is a
  later step and will use the same plug-ins. It needs comfort rules of its own (no large-field turning or zooming),
  which the screen does not.
- **A plug-in is a shader, not a script.** A shader cannot read files, use the network or stop playback, so any
  visualiser is safe to load. A broken one can only draw wrongly. Shaders are also what a screen visualiser needs.
  Scripted visualisers (real 3D, the room) may come later, for surround.
- **The host keeps the rules, not the plug-in.** The flash limit and the GPU budget are applied to every visualiser
  from outside it. A careless or experimental one cannot break them.
- **One analysis of the sound.** The music card and the room's reactions (#81, and the rooms' film signals) share
  one analyser on the Film bus. Before this there was one each.
- **Parameters are data.** The manifest declares them with types and ranges, so a menu can build its controls from
  them, and an assistant can list and set them, with no code per visualiser.

## A visualiser

A folder whose name is its id (lower case letters, digits and `_`), holding:

- `visualiser.json`, the manifest:

  ```json
  {
  	"name": "Bars",
  	"description": "Bars from the low notes on the left to the high on the right.",
  	"area": "strip",
  	"order": 10,
  	"params": {
  		"bars": {"type": "int", "min": 8, "max": 128, "default": 32, "label": "Bars"},
  		"colour_low": {"type": "colour", "default": "#73b3ff", "label": "Low colour"}
  	},
  	"presets": {"Embers": {"colour_low": "#ff5a1f"}}
  }
  ```

  - `area`: where on the card it draws. `strip` (the default): a wide strip under the words. `tall`: a taller area
    there (for round shapes). `backdrop`: the whole card, behind the words, which then get dark panels behind them.
    Without a cover, `strip` takes the card's middle and `tall` all the height between the words and the time line.
  - `params`: each is a uniform of the same name in the shader. Types: `float` and `int` (`min`, `max`, `default`),
    `bool` (`default`), `colour` (`default` as `"#rrggbb"`; a `vec4` uniform with `source_color`). A default outside
    its range is clamped.
  - `presets`: named sets of parameter values, over the defaults.
  - `order`: the place in the list (lower first; then by name).
- `visualiser.gdshader`, a `canvas_item` shader. UV runs 0..1 over the area, (0, 0) at the top left. The area is
  see-through: alpha 0 shows the card behind.

A folder with a mistake is left out, and the registry says why (`errors()`): bad JSON (with the line), no shader, an
unknown area or type, a range the wrong way round, a preset naming a parameter that does not exist, a folder name
that is not an id. A user folder with the id of one of the app's is left out too: copy it under a new name.

### What a visualiser is given

`#include "res://visualisers/visualiser.gdshaderinc"` declares these. The host sets them every frame.

| Uniform | What |
|---|---|
| `spectrum` | 128 x 1 texture: the sound in 128 bands, 30 Hz (x = 0) to 16 kHz (x = 1), log-spaced. `r` the level now, 0..1; `g` the same rising at once and falling slowly |
| `waveform` | 512 x 1 texture: the last 512 samples (mono), -1..1 in `r`, from a rising zero crossing when there is one (a steady tone stands still) |
| `bass`, `mid`, `treble`, `level` | 0..1, smoothed like `g`: 20-250 Hz, 250 Hz-2 kHz, 2-12 kHz, all |
| `beat`, `beats` | 1 on a beat (a jump in the low end), falling to 0 over 0.3 s; the count of beats |
| `vis_time` | seconds of playing; stops while paused (use it, not `TIME`) |
| `size` | the area in pixels |
| `cover`, `has_cover` | the track's cover (a grey square without one; `has_cover` is then 0) |

The include also has `band(x)`, `band_now(x)`, `band_between(x0, x1)`, `wave_at(x)` and `fill_px(d)` (1 inside a
shape whose signed distance in pixels is `d`, smooth over one pixel).

The dB scale: -60 dBFS is 0 and -6 dBFS is 1 (the old music bars' scale). A beat is the 40-150 Hz level 6 dB over
its 0.5 s average, louder than -40 dBFS, at least 0.25 s after the last. It is a simple onset, not a tempo tracker.

### The app's visualisers

| Id | Area | What |
|---|---|---|
| `bars` | strip | the old bars, now with a bar count, a gap and two colours (presets Embers, Many) |
| `mirror` | strip | the old mirror: bars both ways from the middle |
| `line` | strip | the old line with its faint fill; thickness and fill |
| `radial` | tall | the old spokes round a circle; spoke count and circle size |
| `aurora` | backdrop | new: curtains of colour behind the words, lifted by the bass, shimmering with the treble; colours from the cover or chosen (presets Dusk, Calm) |

The four old styles were drawn in GDScript; they are now shaders that look the same.

## The analysis

`scripts/play/audio_analysis.gd`, `main.features.audio_analysis` (also `AudioAnalysis.shared`).

- One `AudioEffectSpectrumAnalyzer` (1024-point FFT) on the Film bus (Master when there is none) while anyone holds
  it (`request(who, true)`), and an `AudioEffectCapture` beside it while anyone wants the waveform. Both come off the
  bus when the last one lets go or is freed. The room's own sounds are on another bus and never move anything.
- **The instance is found again every frame.** Adding or removing any effect on a bus makes the engine build every
  effect instance on it afresh; an instance kept from before reads silence. The capture going on was enough to do
  it.
- **The sound and the picture together.** The analysis hears the sound when it is mixed; the ears hear it after the
  output latency, and later still with slow earbuds. Each frame's snapshot is kept and the one published is
  `output latency - [audio] av_offset` old (at most 0.5 s): the same A/V offset the viewer set for films. No setting
  of its own.
- film_react (#81) reads its two levels (`bass_db`, `broad_db`) from it; its API and behaviour are unchanged.

## The flash limit

A visualiser may not flash. The rule follows photosensitivity guidance: a flash is a pair of opposite changes in
brightness of about 10 % or more, and more than 3 a second is the danger. On a screen in a headset the picture is
large in the view, so the limit applies to the whole area.

- **What is measured:** the average relative luminance of the visualiser's picture (linear light; see-through parts
  count as the card), from 32 x 32 samples, every frame, on the GPU.
- **The rule:** a floor follows the average down at once and up at most `RISE` (0.2) a second. The picture may stand
  at most `MARGIN` (0.08) over the floor. When it would stand higher, the card scales the whole picture down to the
  limit (a gain in linear light).
- **What that gives:** a flicker of the average at f Hz swings at most `MARGIN + RISE / (2 f)`: 0.11 at 3 Hz, less
  above. A picture that brightens slowly is not touched. One that jumps from dark to bright is let up to its
  brightness over a few seconds. Bars and lines on a dark card never come near it: their average moves far less.
- **A new visualiser starts at its own brightness.** The floor starts from the picture for the first 3 frames: a
  start is one change, not a flicker.
- **How:** three viewports nested so the engine draws them in order each frame (it draws a viewport's child
  viewports before it): the visualiser, then `visualiser_limit.gdshader` (measures and keeps the floor, in two
  bytes), then `visualiser_copy.gdshader` (keeps this frame's floor for the next), then the card, where
  `visualiser_apply.gdshader` applies the gain. The engine makes no viewport smaller than 2 x 2, so the small two
  are 2 x 2 with every pixel the same. Nothing is read back to the CPU.
- **Not covered:** saturated red flashes (the guidance treats them separately) and patterns (stripes, checks).
  Small areas flickering are averaged with the rest.

## The GPU budget

The visualiser's own viewport is timed on the GPU (`RenderingServer.viewport_get_measured_render_time_gpu`). When it
takes more than 2 ms (averaged) for a second, it draws at the next lower scale (100, 75, 50, 35 %), stretched to its
area, and the log says so once. It does not come back up until the visualiser is chosen again. The headset draws a
frame in 11 ms at 90 Hz, both eyes, so 2 ms is generous for a screen.

## Tinkering on the headset

The aim: Claude Code (or Codex) in the headset's terminal, or a person over ssh, writes a visualiser and sees it on
the screen at once, with nothing built or restarted. The acceptance test is a fresh session told only "make me a
visualiser that ...". Code: `scripts/visualisers/visualiser_service.gd` (`main.features.visualisers_service`).

- **The folder.** `user://visualisers/` (on the headset `~/.local/share/godot/app_userdata/FrameCine/visualisers/`)
  is made at start, with `README.md`: `app/visualisers/README.md` with this headset's paths filled in, rewritten when
  the app's text changes. It is the whole guide for an agent: the quick loop, the manifest, the shader's inputs, the
  rules the app keeps, what to do when something is wrong. The agents' `CLAUDE.md` and `AGENTS.md` block has one line
  pointing at it.
- **The watcher.** Every second the user folders' manifests and shaders are looked at (times and sizes; a few stats).
  A change reads the folders again, checks each changed visualiser and, when the one on the card changed and
  compiles, starts it again with its new files. Always on, not only in dev mode. One log line per change.
- **Compile errors, with lines.** The engine compiles a shader on its first use, on the main thread. The check
  (`VisualiserRegistry.check(id)`) sets the code, asks for its uniforms (which compiles it at once), and catches what
  the compiler reports with a `Logger` (`OS.add_logger`; shader errors are error type 3, with the line and the words).
  The lines are those of `visualiser.gdshader`: the include does not shift them. It also lists parameters with no
  uniform of their name. Cached until the file changes.
- **The last good version stays.** A user's shader that does not compile keeps the one that last did, on the card and
  for `load_shader()`; drawing a broken shader would only log errors every frame. A user's manifest that breaks keeps
  the entry read before (`stale`, with the error in `errors()`). A visualiser whose shader has never compiled cannot
  be chosen (`set_visualiser_checked()` says why), and the card keeps what it showed.
- **Test signals** (`scripts/visualisers/test_signals.gd`), so there is something to react to: `drums` (120 a minute,
  a kick, hats, a bass line, a pad; no drums from 20 to 30 s), `sweep` (30 Hz to 15 kHz and back), `tones` (an
  octave higher every 2 s) and `silence`. 40 s WAVs at 32 kHz, made once on a worker thread (1.7 s on the PC) in
  `user://visualisers/.test-signals-1/`, opened as music.
- **The commands**, in the one command registry, so on the dev link, the phone remote, the assistant API and the
  agents' MCP tools at once:

| Command | Assistant level | What |
|---|---|---|
| `visualisers` | read | every visualiser with its parameters and presets, the one showing, broken folders and why, the folders and the README |
| `visualiser_status` | read | the one on the card: GPU ms, scale, the flash limit (gain, average, floor, dimming), its check, the last change seen |
| `visualiser_check` | read | read the folders again and compile one now: ok, errors with lines, parameters with no uniform |
| `visualiser_capture` | read | the card (1280 x 720) and the visualiser alone (before the flash limit) as PNGs on the headset, for an agent to look at |
| `visualiser_use` | settings | choose one (refused with its errors if it never compiled) |
| `visualiser_param`, `visualiser_preset`, `visualiser_reset` | settings | its parameters |
| `visualiser_test` | control | play a test signal |

## API and settings

- `main.features`: `visualiser()`, `set_visualiser(id)` (an id or "off"), `visualisers()` (each with its parameter
  specs and values, and preset names), `set_visualiser_param(name, value, id := showing)` (clamped; false when there
  is no such parameter or the type is wrong), `apply_visualiser_preset(name, id := showing)`,
  `reset_visualiser_params(id := showing)`.
- `MusicSource`: `styles()` (the ids, then "off"), `style_names()`, static `style`, `visualiser()` (the host),
  `area_rect(area, with_cover)`, `levels()` (32 bands, for the overlay and tests).
- `VisualiserRegistry`: `ids()`, `entry(id)`, `errors()`, `rescan()`, `check(id)`, `values(id)`,
  `coerce(spec, value)`, `load_shader(id)`.
- `main.features.set_visualiser_checked(id)` ("" or why not). `main.features.visualisers_service`: `poll()`,
  `status()`, `capture()`, `open_test(signal)`, `last_change`, `user_dir`.
- The host: `use(id)`, `stats()` (id, area, viewport size, scale, GPU ms, frames).
- Settings: `[music] visualiser` (default "bars"); `[visualiser.<id>] <param>` for each parameter set away from its
  default.

## Tested

`tests/test_visualisers.gd`, 81 checks, with WSLg and lavapipe (headless: the 54 without the host and the
watcher).

- The registry: the five in order, no errors, the areas, the parameters read with their types, and every parameter
  a uniform of its shader.
- Ten broken user folders, each left out with its reason; a good one in, its out-of-range default clamped; a user
  folder may not take an app id; a user's shader loads from its text.
- Values made the parameter's type and clamped; wrong types refused.
- The analysis: the dB scale, smoothing, one band alone, beats (the jump, the 0.25 s gap, the fall, too quiet), the
  textures, the effects on and off the bus with two holders (one freed), the delay's range.
- `main.features`: the list, a parameter clamped and kept in the settings, unknown ones refused, a preset, reset,
  choosing by id.
- The host: each of the five starts and draws; a steady grey picture is untouched and the floor's two bytes give
  back its luminance (0.2159 for 0.214); a black and white strobe changing every frame swings at most 0.078 on the
  card; black to white stays under the rise limit after 1.4 s; a new visualiser shows at its own brightness at once.
  Off, its viewports stop and it is not fed; on again, it starts afresh.
- Making them: a test signal's WAV (header, length, sound or none); the nine commands open to the assistant at their
  levels; the README in the user folder with this machine's paths; the watcher sees a new folder; a compile error
  comes back with its line (5, after the include on line 2) and words; the last good shader kept; a broken manifest
  keeps the last good entry, marked; fixed, usable again; one that never compiled is refused with its error;
  `visualiser_check` through the registry; `visualiser_test` plays the drums as music; `visualiser_use` shows a
  user's one and `visualiser_status` has its flash limit; an edit to the one showing starts it again;
  `visualiser_capture` saves the card.

`tests/test_music.gd` (16 checks) now checks all six styles on the card: "off" draws nothing in the area, the others
draw, each differently. Its level check waits up to 3 s for the clip's sound (the clip is quiet for about its first
second; the old fixed 1.5 s wait sat on that edge). `test_env_signals` still passes. `test_react` passes as before:
its flash-size check fails on main too (it expects more than the room schema's swing ceiling allows; not this work).

## Not yet

- **The menu.** The visualiser and its parameters are set through `main.features` (the dev link, an assistant). No
  panel row exists yet; the manifest has what one needs (labels, types, ranges, presets).
- **The acceptance test:** a fresh Claude Code session on the headset, told only to make a visualiser.
- **More of the app's own.**
- **Surround.**
- **On the headset:** the five ran there on 2026-11-18 on a synthetic beat track: all draw and react, 0.06 to
  0.12 ms of GPU each (aurora 0.58 ms), the flash limit idle on all of them, aurora's words readable. Not yet: real
  music in the headset's view, the analysis's CPU cost (128 band reads a frame). Radial was small on a card without
  a cover (it got the strip, 302 px high); `tall` now takes the height down to the time line there (374 px).
