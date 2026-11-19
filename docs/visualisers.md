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
  - `feedback`: `true` gives the shader its own last frame as `previous` (default `false`). Without it a visualiser
    has no memory: every frame is worked out afresh from the sound and the clocks. With it, it can keep things that
    build up and move on (ink, trails, growth). The host keeps a copy of the picture (before the flash limit) in a
    viewport drawn after the visualiser's, so it costs one copy a frame, and only for a visualiser that asks.
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
| `vis_dt` | this frame's seconds; 0 while paused (for `feedback`: change at the same speed at any frame rate, stand still while paused) |
| `drive` | a clock that runs with the music: 0.4 s a second in silence, up to 1.6 with full bass and level (`0.4 + 0.8 bass + 0.4 level`). For motion that speeds up with the sound and never jumps back (a scroll, a spin, a drift); stops while paused |
| `previous`, `fresh` | with `feedback` only: the visualiser's own last frame (same size, 8 bits a channel), and 1 for the first two frames after a start, while `previous` still holds the picture from before |
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
| `halftone` | backdrop | the cover as a cheap colour print: four plates of dots (cyan, magenta, yellow, black, each at its own angle) whose sizes are the picture's inks, swollen by the sound at their place across the card; the magenta plate slips out of line on a beat and settles. Without a cover, a starburst panel (presets Comic, Fine, Newsprint) |
| `tiles` | backdrop | a wall of flat-colour tiles in the manner of modernist posters, each with one bold shape; each tile turns a quarter every few beats at its own phase, so only a few turn on any beat, with a small overshoot over the beat's fall; on the music's clock now and then too; shapes breathe with their band (presets Pastel, Night, Calm) |
| `runner` | tall | a pixel game that plays itself: the runner jumps crates and spikes on parabolas worked out from where it is, hops on every beat between them, collects coins (a sparkle rises), the world scrolling on `drive`; behind it a striped sun and a city whose towers are the spectrum; the score counts the beats (presets Day, Night, Chunky) |
| `sakura` | backdrop | a night sky with the moon, hills, and a branch of blossom; petals drift past in four layers, blown along on `drive`, swayed by the middle notes; the blossom glints with the high notes, the moon glows with the level (presets Dusk, Snow, Storm) |
| `ink` | backdrop | the first with `feedback`: ink in slowly turning water. Its last frame moves along a flow (the curl of a drifting noise, a whirl, a push outwards on a beat) and fades; six pourers circle, each pouring as loud as its sixth of the spectrum; a beat blooms a drop. Dithered half a step so slow motion survives 8 bits; paused, copied exactly. Colours from the cover or chosen (presets Milk, Lagoon, Still) |
| `planet` | backdrop | a ringed gas giant, ray traced: the sphere, the ring plane and three moons, with the planet's shadow on the rings and the rings' and moons' shadows on the clouds, a thin lit atmosphere at the edge. The cloud bands flow in zonal winds (two copies taking turns so the flow never shears into streaks) and churn with the sound, low notes at the equator, high at the poles; the rings are a spectrum from the inner edge out; a storm turns in the south; lightning on the night side on a beat, aurora with the high notes (presets Ice giant, Tempest, Ochre) |
| `rose` | backdrop | a gothic rose window from inside, the sun behind: stone tracery round a six-lobed oculus, twelve lancets, twelve eyes and twenty-four quatrefoils, glazed in pieces (Voronoi cells) between lead lines. Each lancet and roundel is a part of the spectrum going round the wheel; the oculus glows with the bass. The sun moves behind, sweeping the light over the glass; coloured rays spread into the room (each worked out from its angle: the openings on its line, no marching), with dust glinting with the high notes (presets Grisaille, Twilight, Plain light) |
| `clockwork` | backdrop | a watch movement from the back: barrel, centre, third and fourth wheels each turning the next one's pinion with the teeth properly meshed (each wheel's turn worked out from the one before), ending in the escape wheel; the pallet lever rocks on every beat and the train steps half a tooth, turning on `drive` between beats. The balance swings wider when it is loud, its hairspring breathing. Bridges with striped finish and polished bevels; ruby jewels glowing each with a part of the spectrum; blued screws (presets Gilt, Black, Rose gold) |
| `chrome` | backdrop | ray traced in the manner of the early ray tracers: a mirror sphere on a chequered floor (filtered over each pixel's footprint, so far tiles turn grey instead of shimmering), seven coloured metal spheres circling it, each bouncing with its band; up to three bounces, soft shadows, the floor darkened under the spheres. A ring of pillars on the horizon is the spectrum again, seen in every reflection; the camera circles on `drive` (presets Sunset, Night, Gold) |
| `circuit` | backdrop | a circuit board seen close: copper tracks in lanes under a glossy mask, a bus at a time jogging across at 45 degrees, vias where tracks end; chips with legs on the lanes and printed labels, a big lidded processor, small resistors and capacitors. Bursts of light run along the tracks, each lane a part of the spectrum (low notes at the bottom); a column of LEDs is a level meter (presets Black, Blue, Purple) |
| `deep` | backdrop | jellyfish drifting through dark water by their own light, carried across by the current on `drive`, the near ones faster. Each bell is a thin glassy shell (brighter where you look through more of it), with canals running down it like meridians, four horseshoe gonads and a ring of lights round the margin; tentacles trail and sway, frilled mouth arms hang below. Each jellyfish pulls in its bell with its own band (a fast stroke on a hit, a slow relaxing after); each margin light glows with a band of its own; marine snow sinks past in three depths; plankton glints with the high notes (presets Ember, Abyss, Lagoon) |
| `cymatics` | backdrop | Chladni plates: a square plate and a round one, bolted at the middle, under a lamp on dark cloth. Sand lies in ridges of single lit grains on the lines that stand still (worked out from each mode's field and its slope, so the lines keep their width); each plate steps to its next mode on `drive`, the lines sliding and blurring into the new figure, sharper when it is loud. The bass shakes the square plate (the lamp's reflection ripples in the shape of the mode, sand hangs as a haze where it moves most); the round plate goes with the high notes; a signal generator shows each mode's tone on seven-segment digits (presets Brass, Steel, Blue) |
| `vinyl` | backdrop | a record deck from above: the record turns at 33 1/3 with the cover on its label (a printed label without one), the lamp's two bright wedges in its grooves broken by the gaps between tracks; one row of strobe dots stands still under the lamp; the arm tracks inwards over twenty minutes; a magnifier shows the groove under the needle, its walls wiggling with the waveform itself, louder sound cutting wider (presets Red vinyl, Silver, Black) |
| `fireworks` | backdrop | a display over a harbour at night: shells rise from the water and burst into peonies, chrysanthemums (crackling with the high notes at the end), gold willows and tilted rings, each a sphere of stars drawn as three rings (only the star nearest in angle on each ring is evaluated); each shell swells and brightens with its band; the bursts light the smoke over the town and stretch down the rippled water. Shells go up on `drive`, so loud music fills the sky (presets Gold, Winter, Festival) |
| `rain` | backdrop | a city at night through a wet, misted window: out-of-focus windows, street lamps and cars passing both ways glow as discs, each window brighter with the band at its place across (low notes on the left), a neon sign following the middle; beads sit on the glass and grow and dry, drops run down in wandering paths on `drive`, wiping clear trails and leaving beads. Each drop is a lens: inside it the city is sharp and upside down (the city is drawn once per pixel, sharp or blurred by what is in front of it) (presets Neon, Sodium, Downpour) |
| `topo` | backdrop | a printed topographic map, folded and opened out: land tinted in steps by height and shaded from the north-west, brown contour lines kept one width with the height's screen slope (every fifth heavier, faded where they would crowd), sea with water-lines along the coast. Nine summits each rise with their band, so the contours crowd and spread; the tide comes and goes and the land drifts slowly on `drive`. A dashed route from summit to summit, a graticule, a scale border and a compass rose (presets Old chart, Night, Ice) |
| `koi` | backdrop | a garden pond from above: koi of five kinds swim loops over pebbles, each body bent along the curve it swims (worked out from the path's curvature) with its tail beating as hard as its band; shadows on the stones; caustics brighter with the middle notes; drops land on `drive` and their rings bend the view below and catch the sun; lily pads, their flowers opening with the high notes (presets Clear, Evening, Autumn) |
| `candles` | backdrop | pillar candles on a polished table in a dark room: each flame a teardrop (blue root, dark heart, yellow-white, orange edge) that wavers on its own, leans in the draught of the bass and grows with its band; wax glowing through round a pool of melted wax, drips, smoke, the wall lit by the flames, reflections in the table (presets Red wax, Church, Blue) |
| `paper` | backdrop | a paper-cut diorama: six layers of hills, darkest at the front, each throwing a soft shadow on those behind and rising with its band (the front the low notes); pines, a cottage with a window lit by the middle notes, reeds swaying with the bass, a paper sun glowing with the level, clouds and birds on `drive`, the box swaying a little (presets Forest, Winter, Night) |
| `bubbles` | backdrop | soap bubbles drifting across a garden out of focus: each film's colour is interference from its thickness (thinner at the top, swirling), reflecting most at the edge, with the sky's light as two windows and the garden bent through it; each large bubble's outline rings in two and three lobes with its band; small ones glint with the high notes (presets Evening, Dark, Meadow) |

The four old styles were drawn in GDScript; they are now shaders that look the same. None of the twenty-five keeps any
state on the CPU: everything is worked out from the sound, the clocks and their parameters (and for `ink`, its own
last frame), so a seek, a pause or a restart never leaves them in a strange state.

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

A visualiser may not flash. The rules follow photosensitivity guidance: a flash is a pair of opposite changes in
brightness of about 10 % or more, more than 3 a second is the danger, and so are patterns (stripes, checks) that swap
or move. Area matters: the guidance starts at about a quarter of the central field of view. On a screen in a headset
the card is large in the view, so area is measured against the card. Two rules, both on the GPU every frame, nothing
read back to the CPU:

- **The whole picture's brightness.** A floor follows the picture's average relative luminance (linear light;
  see-through parts count as the card) down at once and up at most `RISE` (0.2) a second. The picture may stand at
  most `MARGIN` (0.08) over it; when it would stand higher, the whole picture is scaled down to the limit. A flicker
  of the average at f Hz swings at most `MARGIN + RISE / (2 f)`: 0.11 at 3 Hz, less above. A jump from dark to bright
  is let up to its brightness over a few seconds. This catches whole-screen flashes.
- **Flicker over an area.** 128 x 72 sample points each keep their own slow average (over 0.25 s); a point's distance
  from it is its flicker. A pattern that swaps moves every point though the picture's average stays put, and so does
  flicker in one part of the picture. The points are pooled in 16 x 9 cells, and the cells over the card, weighted by
  the visualiser's share of the card. Over `FLICKER_MAX` (0.02), a cap is found (bisection) such that capping every
  cell's flicker at it brings the total down to the limit; the card dims each cell over the cap by cap / its flicker
  (read smoothly between cells). Only the flickering cells dim, and only as much as needed. The cap drops at once and
  doubles every 0.25 s back towards none. For scale: black and white swapping over the whole card is 0.5; 10 % of
  contrast swapping over a quarter of it (where the guidance starts) is 0.0125; so 0.02 lets a quarter of the card
  swap at about 16 % of contrast, or a smaller area more.
- **Measured** (`test_visualisers.gd`, lavapipe): a black and white checkerboard swapping every third frame changes
  0.333 of luminance a frame in the picture and 0.015 on the card; the old whole-picture rule alone did nothing to it
  (its gain stays 1). With only the left half swapping, the left half shows 0.031 and the right half keeps its
  brightness (0.214). The app's own visualisers on the drums test signal reach at most 0.0168 (halftone), 0.0114
  (sakura), 0.0112 (mirror), 0.0110 (bars), 0.0050 (clockwork), 0.0044 (topo), 0.0043 (koi), 0.0035 (aurora),
  0.0032 (chrome), 0.0029 (deep, line), 0.0025 (fireworks, bubbles), 0.0016 (circuit), 0.0012 (runner), 0.0008
  (rain), 0.0005 (vinyl), 0.0004 (radial, paper), 0.0002 (planet) and about 0 (ink, rose, cymatics, candles). Over
  longer runs topo reached 0.0187 (once dimmed a little) while its tide followed the bass and the land drifted 2.5
  times faster; with the tide on the clock and a slower drift it measures 0.011 to 0.012. The figures vary from run to run (halftone measured
  0.0116 in another). Tiles varies most: 0.0107, 0.0158, 0.0176 and once 0.0202 in four runs (and 0.0003 and 0.0004 in two later ones), when one of its twelve
  samples was dimmed a little and the test failed; the runs before and after passed. Its bold shapes turn a quarter
  in the 0.3 s of a beat's fall, about the length of the limit's average, so how many turn together on a sample
  decides it. Over longer runs, chrome
  reached 0.015 to 0.017 and circuit 0.016 (on the cover clip, before its bursts were dimmed a little): chrome's
  chequered floor sliding as the camera turns, and its horizon pillars reflected in the floor, were most of it; a
  less shiny floor, a slower camera and softer pillars brought it there. Busier music may bring mirror, bars, tiles,
  halftone and chrome near the limit; then their busiest cells dim a little. Halftone and tiles were tuned to get there: at first halftone's starburst
  had hard ray edges (a dot on an edge swapped colour at once; 0.023 to 0.032) and tiles overshot further on each
  turn (0.020).
- **A new visualiser starts at its own brightness.** Both rules start from the picture for the first 3 frames: a
  start is one change, not a flicker.
- **How:** viewports nested so the engine draws them in order each frame (it draws a viewport's child viewports
  before it): the visualiser; `visualiser_taps.gdshader` (128 x 72: each point's luminance, average and flicker);
  `visualiser_cells.gdshader` (16 x 9); `visualiser_limit.gdshader` (2 x 2, the engine's smallest: the floor and gain,
  the cap, the total); copies of the points and of the limit (`visualiser_copy.gdshader`, read next frame); then the
  card, where `visualiser_apply.gdshader` applies the gain and the caps. The averages and the floor are kept in two
  bytes each.
- **Not covered:** saturated red flashes (the guidance treats them separately); a still, high-contrast pattern (no
  change, so no flicker; the guidance also warns about some still patterns); flicker in a patch smaller than a sample
  point's (10 x 10 pixels at full size), which the four samples per point only partly see.

## The GPU budget

- **The first frames.** A visualiser that starts (chosen, or its files changed) first draws 6 frames at about
  256 x 144, timed on the GPU (`RenderingServer.viewport_get_measured_render_time_gpu`; the first two frames have no
  timing yet). From the slowest, the cost at full size is estimated (per pixel). It then starts at the largest scale
  (100, 75, 50, 35 %) within 2 ms. When even 35 % would take more than 4 ms, it is refused: the visualiser before it
  stays (or the default), `visualiser_use` fails with the estimate and why, and `visualiser_status` shows
  `last_refusal`. The visualiser is shown at the small size for those frames (about 0.1 s).
- **While it runs.** More than 2 ms (averaged) for a second steps it down a scale; the log says so. It does not come
  back up until the visualiser starts again.
- The headset draws a frame in 11 ms at 90 Hz, both eyes, so 2 ms is generous for a screen.
- **Not covered:** a shader that never ends (an endless loop) or takes seconds even at 256 x 144 still stalls the GPU
  on its first frame, which can end the app. The probe catches the heavy, not the endless.

## What a visualiser can and cannot do

A visualiser is a shader. It cannot read or write files, use the network, run programs, or see the film, other
windows or the room: it gets only the textures the host gives it (spectrum, waveform, cover) and its own parameters.
`#include` loads shader include files only. Its commands are checked (ids against the folders, values against the
manifest) and follow the assistant's switches. What it can still do: stall or crash the GPU (above), crash the
shader compiler with a malformed shader, show anything at all on the card (including text that looks like the
player's), and get past the flash limit in the ways listed under "Not covered".

That is the boundary for a visualiser, from whoever wrote it. It is not a boundary around an agent on the headset:
Claude Code or Codex there has a shell as the user and can change any file the user can, the app's own included.
What guards that is the agent's permission prompts and the viewer.

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

## In the menu

Picture, **Visualisations**: the first section of the Picture tab, shown only while what plays has no picture (the
music card is on the screen), so it is not in the tab's list during a film. In it:

- one button per visualiser (the app's and the user's, by their manifests' names) and Off;
- the chosen one's description and its parameters, built from its manifest: a slider for a number (whole steps for
  `int`), a switch for `bool`, and for `colour` its current colour and twelve swatches (a colour picker is hard to
  use in a headset; Defaults gives the manifest's own colour back);
- its presets as buttons, and Defaults;
- the user's visualisers that do not load, and why (the first three).

Built again when the list, the chosen one or its parameters' shape change (an agent saving a new manifest included:
`main.features.visualisers_changed`); otherwise only the values are set, so a slider being dragged is not rebuilt
under the finger. Names, labels, descriptions and preset names are the manifests' (content, not translated).
`ui/picture_tab.gd`.

## Sound with no picture

The music card shows for music files (by extension), and now also for a video's container that holds only sound (an
audio-only `.mp4`, `.mkv` or `.webm`, as a download of a music video's sound often is): when the video path fails,
the factory asks the file whether it has a video stream (`MusicSource.has_no_picture()`) and opens it as music. A film
never pays for that: the question is asked only after the video path failed. Network files ask the MediaSource
already open.

## Still pictures

A video at 5 frames a second or fewer (`HWVideoSource.STILL_FPS`; radio programmes put out as video with one picture,
at 1 or 2 frames a second) plays as a video (its audio tracks, subtitles, chapters and gapless next item as usual),
but the screen shows the music card: the video's picture fitted to the card and dimmed to 45 %
(`shaders/still_picture.gdshader`: the decoder's planes, the file's matrix and range; no HDR, no picture controls),
the title from the tags or the file name, the time line, and the visualiser. Picture, Visualisations shows for it,
with the switch **Show videos with a still picture as music** (`[music] still_card`, default on); turning it off
opens the file again as a plain video, and the switch stays in the section to turn it back on.
`HWVideoSource.is_still_video()`, `shows_card()`, `visualiser()`; the card is a `MusicSource.open_card()` with no file
of its own. Real motion is 10 frames a second and more, so nothing else is caught.

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
- The host: `use(id)`, `stats()` (id, area, viewport size, scale, GPU ms, frames, feedback), `feedback()`,
  `vis_time`, `drive`.
- Settings: `[music] visualiser` (default "bars"); `[visualiser.<id>] <param>` for each parameter set away from its
  default.

## Tested

`tests/test_visualisers.gd`, 164 checks, with xvfb and lavapipe (headless: the 74 without the host and the
watcher).

- The registry: the twenty-five in order, no errors, the areas, the parameters read with their types, and every parameter
  a uniform of its shader.
- Ten broken user folders, each left out with its reason; a good one in, its out-of-range default clamped; a user
  folder may not take an app id; a user's shader loads from its text.
- Values made the parameter's type and clamped; wrong types refused.
- The analysis: the dB scale, smoothing, one band alone, beats (the jump, the 0.25 s gap, the fall, too quiet), the
  textures, the effects on and off the bus with two holders (one freed), the delay's range.
- `main.features`: the list, a parameter clamped and kept in the settings, unknown ones refused, a preset, reset,
  choosing by id.
- The host: each of the twenty-five starts and draws; a steady grey picture is untouched and the floor's two bytes give
  back its luminance (0.2159 for 0.214); a black and white strobe changing every frame swings at most 0.078 on the
  card; black to white stays under the rise limit after 1.4 s; a new visualiser shows at its own brightness at once.
  Off, its viewports stop and it is not fed; on again, it starts afresh.
- `feedback`: read from the manifest, and a manifest whose `feedback` is not true or false left out; without it no
  copy is drawn; a test visualiser that adds 3/255 to its own last frame grows by that each frame; `drive` runs
  faster than its rest with sound; paused, `drive` stands and so does a feedback picture.
- Flicker over an area: a swapping checkerboard dimmed (0.333 of change a frame in the picture, 0.015 shown, the
  whole-picture gain untouched); half the card swapping dims that half only. The first frames' timing (test timings
  given to it): cheap at full size, about 3 ms at 75 %, about 62 ms refused with the one before back and the reason.
  The app's twenty-five on the drums test signal on the real card, never dimmed (figures under "The flash limit").
- Making them: a test signal's WAV (header, length, sound or none); the nine commands open to the assistant at their
  levels; the README in the user folder with this machine's paths; the watcher sees a new folder; a compile error
  comes back with its line (5, after the include on line 2) and words; the last good shader kept; a broken manifest
  keeps the last good entry, marked; fixed, usable again; one that never compiled is refused with its error;
  `visualiser_check` through the registry; `visualiser_test` plays the drums as music; `visualiser_use` shows a
  user's one and `visualiser_status` has its flash limit; an edit to the one showing starts it again;
  `visualiser_capture` saves the card.
- The menu: Visualisations shows with the music card, first in Picture; a choice for each visualiser and Off; bars'
  four parameters as controls; its slider, a colour swatch, a preset's button and Defaults each set what they
  should; choosing Aurora builds its controls (a switch among them); Off has none; a change made elsewhere shows on
  the slider; a film hides the section.

`tests/test_music.gd` (25 checks: an `.mp4` holding only sound plays as music; a 1 frame a second video shows as the
card with its picture dimmed behind it, its title and the visualiser, and the switch turns it into a video and back)
checks all twenty-six styles on the card: "off" draws nothing in the area, the others draw, each differently (one with
`feedback` is given 90 frames to build its picture up). Its level check waits up to 3 s for the clip's sound (the clip is quiet for about its first
second; the old fixed 1.5 s wait sat on that edge). `test_env_signals` still passes. `test_react` passes as before:
its flash-size check fails on main too (it expects more than the room schema's swing ceiling allows; not this work).

## Not yet

- **Seeking in a still picture** lands at the next keyframe (up to 10 s on): after the seek the decoder shows the
  right frame, but the audio clock comes back seconds ahead. An engine matter (MediaSource audio with 1 frame a
  second of video), seen in tests; not fixed here.
- **The acceptance test:** a fresh Claude Code session on the headset, told only to make a visualiser.
- **GPU time on the headset of the later twenty.** Halftone, tiles, runner, sakura and ink were put on the headset on
  2026-11-18 and looked right there; their GPU time there has not been read yet. Planet, rose, clockwork, chrome,
  circuit, deep, cymatics, vinyl, fireworks, rain, topo, koi, candles, paper and bubbles have run only under lavapipe
  so far. There, on the drums, a frame
  took 3.3 ms (tiles), 2.6 (runner), 4.5 (halftone), 7.2 (sakura), 9 to 11 (ink), 7.5 (planet), 7 (rose), 6
  (clockwork), 9 (chrome), 8.5 (circuit), 9.7 (deep), 3.8 (cymatics), 4.9 (vinyl), 8.5 (fireworks) and 4.4 (rain),
  against 3.8 for aurora (10 with a cover), which took 0.58 ms on the headset. If the ratio holds, all are under the
  2 ms budget there; the probe scales any that are not. Clockwork first took 20 ms: every pixel drew all twelve
  balance screws and evaluated the bridges four times; it now draws only the nearest screw and takes the bridges'
  slope from screen derivatives. Rose took 18 ms while its rays marched 14 steps through the window. Fireworks took
  13 ms while it went over its shells twice (once for their light, once for their stars) and hashed each shell three
  times; one pass and one hash brought it to 8.5. Deep's tentacles turn each one's place on from the last instead of
  calling sin and cos for each. Lavapipe's figures drift from session to session: in a later one aurora took 4.2
  to 5 ms and chrome 17.6, and there topo took 7 to 8.8, koi 10.4 to 12, candles 8 to 9.3, paper 8.7 to 9.9 and
  bubbles 7.4 to 9.1, so between 1.7 and 2.8 times aurora's time then. Koi skips a fish when the pixel is far from its head (one point on its path) and
  leaves the fins out of its shadows (17 ms to 11); candles works each flame out once into an array (13 to 7.5);
  paper skips the layers hidden behind a nearer one and those wholly below the pixel (14.5 to 12, 7.7 with a
  cover).
- **More of the app's own.** Ideas not yet made: a Game of Life seeded by beats (with `feedback`, stepping slowly: a
  fast one would be dimmed as flicker), trails, reaction-diffusion, a starfield, a kaleidoscope of the cover.
- **Surround.**
- **On the headset:** the five ran there on 2026-11-18 on a synthetic beat track: all draw and react, 0.06 to
  0.12 ms of GPU each (aurora 0.58 ms), the flash limit idle on all of them, aurora's words readable. Not yet: real
  music in the headset's view, the analysis's CPU cost (128 band reads a frame). Radial was small on a card without
  a cover (it got the strip, 302 px high); `tall` now takes the height down to the time line there (374 px).
