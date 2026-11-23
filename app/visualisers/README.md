# Writing a music visualiser for FrameCine

FrameCine is the video player on this headset. While a music file plays, the flat screen shows a card: the cover,
title, artist, a time line, and a **visualiser**, a picture of the sound. A visualiser is a small plug-in you can write
here. The player watches this folder and shows your change within a second. Nothing to build, nothing to restart.

- Your visualisers go in: `<<USER>>` (this folder; one sub-folder each)
- The player's own, to read and copy: `<<APP>>` (`bars`, `mirror`, `line`, `radial`, `aurora`, `halftone`, `tiles`,
  `runner`, `sakura`, `ink`, `planet`, `rose`, `clockwork`, `chrome`, `circuit`, `deep`, `cymatics`, `vinyl`,
  `fireworks`, `rain`, `topo`, `koi`, `candles`, `paper`, `bubbles`, `carousel`, `microscope`, `volcano`, `web`,
  `starlings`, `lighthouse`, `fractal`, `balloons`, `crystals`, `stage`,
  `stadium`, `city`, `clouds`, `organ`, `kaleidoscope`,
  `blackhole`, `musicbox`, `pinball`, `fountains`, `snowglobe`,
  `piano`, `lavalamp`, `cradle`, `tapedeck`, `zen`,
  `speakers`, `engine`, `wheat`, `neon`, `honeycomb`)

This file is rewritten by the player when it changes. Keep your notes elsewhere.

## The quick way

1. `visualiser_test` with `drums` plays a test track, so there is music to react to. Or open any music file.
2. Make a folder here, say `glow/`, with `visualiser.json` and `visualiser.gdshader` (below). Copy one of the player's
   own folders to start, under a new name: a folder with the name of one of the player's is skipped.
3. `visualiser_use` with id `glow`.
4. `visualiser_check` (compile errors, with line numbers) and `visualiser_capture` (PNGs of the card and of your
   picture alone; read them to see what you made). `visualiser_status` says if the flash limit is dimming it and what
   it costs on the GPU.
5. Edit and save; repeat 4. A save with a mistake keeps the last version that compiled on the screen.
6. Expose the knobs a viewer would want as parameters, with presets for good combinations.

These are the player's tools (MCP server `vr-player`, or `POST /command` with curl: see the player's guide). Folder
names: lower case letters, digits and `_`. The folder name is the id.

## visualiser.json

```json
{
	"name": "Glow",
	"description": "A soft glow that breathes with the bass.",
	"area": "strip",
	"order": 100,
	"params": {
		"size": {"type": "float", "min": 0.1, "max": 1.0, "default": 0.5, "label": "Size"},
		"rings": {"type": "int", "min": 1, "max": 8, "default": 3, "label": "Rings"},
		"spin": {"type": "bool", "default": false, "label": "Spin"},
		"tint": {"type": "colour", "default": "#ff9a40", "label": "Colour"}
	},
	"presets": {"Cool": {"tint": "#40a0ff", "rings": 5}}
}
```

- `area`: where it draws on the 1280 x 720 card. `strip` (default): a wide strip under the words (about 650 x 145
  with a cover, 1075 x 300 without). `tall`: a taller area there (about 650 x 300 with a cover, 1075 x 374 without). `backdrop`: the whole
  card, behind the words (they get dark panels). Use `backdrop` for full-screen art.
- `params`: each one is a `uniform` of the same name in the shader, set by the player. Types: `float`, `int`
  (`min`, `max`, `default`), `bool` (`default`), `colour` (`default` `"#rrggbb"`; declare it
  `uniform vec4 tint : source_color;`). `visualiser_param` sets one.
- `presets`: named values over the defaults. `order`: place in the list (lower first).
- `category` (optional): a heading the menu groups it under. The player's own say which model wrote them
  (`"Opus 5.5"`, `"Fable 5.2"`); put your own model's name on yours.
- `feedback`: `true` gives your shader its own last frame as `previous` (default `false`), for things that build up
  and move on: ink, trails, growth. Without it every frame is drawn afresh from the sound and the clocks.
- `picture`: `true` gives your shader the picture of what plays as `screen_pic` (default `false`), when the visualiser
  shows on the screen in place of a film or a web page: put it on a surface of your own, or on several.

## visualiser.gdshader

A Godot 4 `canvas_item` shader (GLSL-like). The smallest that works:

```glsl
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform vec4 tint : source_color = vec4(1.0, 0.6, 0.25, 1.0);

void fragment() {
	float d = length((UV - 0.5) * size) / size.y;   // distance from the middle, in heights
	float glow = exp(-d * 6.0) * (0.3 + bass);
	COLOR = vec4(tint.rgb, clamp(glow, 0.0, 1.0));
}
```

`UV` runs 0..1 over the area, (0, 0) top left. Set `COLOR` (rgb and alpha). Alpha 0 shows the card behind (dark
grey), so a `strip` visualiser draws only its shapes. The include gives you, set every frame:

| Name | What |
|---|---|
| `spectrum` | 128 x 1 texture: 128 bands, 30 Hz (x = 0) to 16 kHz (x = 1), log-spaced. `.r` level now 0..1, `.g` the same rising at once and falling slowly (steadier) |
| `waveform` | 512 x 1 texture: the last 512 samples, `.r` -1..1, from a rising zero crossing (a steady tone stands still) |
| `bass`, `mid`, `treble`, `level` | 0..1, smoothed: 20-250 Hz, 250 Hz-2 kHz, 2-12 kHz, everything |
| `beat` | 1 on a beat (a jump in the bass), falling to 0 over 0.3 s |
| `beats` | how many beats so far (for taking turns: `mod(beats, 2.0)`) |
| `vis_time` | seconds of playing; stops while paused. Use it rather than `TIME` |
| `drive` | a clock that runs with the music: 0.4 s a second in silence, up to 1.6 with loud bass. Scroll, spin or drift on it: motion speeds up with the sound and never jumps back (`sin(bass)` would) |
| `vis_dt` | this frame's seconds, 0 while paused |
| `previous`, `fresh` | with `"feedback": true` only: your last frame (sample it at `UV`), and 1 for the first frames after a start (draw a clean background then) |
| `size` | the area in pixels |
| `cover`, `has_cover` | the track's cover texture; `has_cover` is 0 without one (`cover` is then plain grey) |
| `screen_pic`, `has_screen_pic`, `screen_pic_aspect` | with `"picture": true` only: the picture of the film or window the visualiser replaces on the screen (`screen_pic_at(uv)` samples it, black outside 0..1); `has_screen_pic` is 0 without one |

And functions: `band(x)` (smoothed level at x, 0 low .. 1 high), `band_now(x)`, `band_between(x0, x1)` (average),
`wave_at(x)` (-1..1), `fill_px(d)` (1 inside a shape whose signed distance in pixels is `d`, smooth over one pixel).

Godot shader notes: no `#version`, no `main()`, no `gl_FragCoord` (use `UV` and `size`, or `FRAGCOORD`); functions
must be defined before use; `float` literals need a point (`1.0`); `mod`, `fract`, `mix`, `smoothstep`, `atan(y, x)`
work as in GLSL. `PI`, `TAU` and `E` are built in (defining your own, even a local variable `E`, is an error), and so
is `dot()` (do not name a uniform `dot`). The include's names (`cover`, `size`, `level`, `beat`, `mid` and the rest
in the table) are taken too, for your functions as well as your variables; keep clear of GLSL's own function names
(`round`, `step`) as well. Read `visualiser.gdshaderinc` in `<<APP>>` for the exact declarations.

With `feedback`: `previous` has 8 bits a channel, so a slow fade or a slow drift rounds away to nothing. Add a little
noise (half a step, `(hash - 0.5) / 255.0`) to what you write and it survives on average; `ink` does. Multiply changes
by `vis_dt` so they run at the same speed at 60 and 90 frames a second and stop while paused; when `vis_dt` is 0,
write `previous` back unchanged.

## Rules the player keeps for you

- **The flash limit.** No visualiser may flash: it can be dangerous for people with photosensitive epilepsy, and the
  screen is large in a headset. Two rules, applied to your picture on the GPU:
  - Whole-picture brightness: when the average jumps more than about 8 % above where it has been lately, the whole
    picture is dimmed; it may rise only slowly (about 20 % a second). Whole-screen flashes on beats come out as
    gentle swells.
  - Flicker over an area: every part of the picture is compared with its own recent average. Patterns that swap or
    flicker (checkerboards, stripes, strobing regions) are dimmed where they flicker, more the larger the area.
    Moving shapes and bars are fine; the player's own fifty-five are never dimmed on the test drums.
  Design for that: move shapes, change colour, pulse sizes; avoid swapping or strobing patterns. `visualiser_status`
  shows `flash_limit`: `dimming`, and `flicker` against `flicker_max`.
- **The GPU budget.** A new or changed visualiser first draws a few frames small, timed: if it would take more than
  3 ms a frame it starts at a lower resolution, and if far more (over 4 ms even at 35 %) it is refused and the one
  before stays (`visualiser_use` says so, with the estimate). While it runs, over 3 ms for a second steps it down.
  `visualiser_status` shows `gpu_ms` and `scale`. Long loops per pixel (many octaves of noise, ray-marching) cost the
  most. Never write a loop that might not end: it would stall the headset's GPU. Draw a small part only near it (test
  the distance first and skip the rest), and draw the nearest of a ring of things rather than all of them: `clockwork`
  went from 20 ms to 6 under lavapipe that way.
- **Comfort.** It is a screen in a room, so motion is fine; no strobing, no text that pretends to be the player.

## When something is wrong

- `visualiser_check` with the id: `ok`, `errors` (`line` in your `visualiser.gdshader`; the include does not shift
  the numbers), `missing` (parameters with no uniform of their name: they do nothing).
- A broken `visualiser.json` (bad JSON, unknown type, a preset naming a parameter that does not exist) is listed under
  `broken` by `visualisers`; the last good one stays in use meanwhile.
- `visualiser_use` refuses a visualiser whose shader has never compiled, and says why.
- Nothing moves? Check something is playing (`visualiser_status`: `music_card`), and that you use `vis_time`, not a
  constant.

## Ideas

Oscilloscope from `waveform`; circles that grow with `bass`; a starfield that speeds up with `level`; colour from the
cover (`texture(cover, uv)`); a grid of cells each lit by its own band; a slow kaleidoscope turned by `vis_time` and
pushed by `beat`. Look at `aurora` in `<<APP>>` for a full-card one, `halftone` for the cover reworked, `tiles` for
taking turns on beats (each tile its own number of beats), `runner` for a scene worked out from `drive` alone (a game
that plays itself, no memory needed), `sakura` for many falling things at one per cell, and `ink` for `feedback`.
For 3D: `planet` and `chrome` ray trace spheres and planes exactly (no marching): shadows, reflections, a ring plane.
`rose` builds shapes in polar sectors (one shape, repeated round a wheel) and glass pieces from Voronoi cells;
`clockwork` meshes gears (each wheel's turn worked out from the one before) and steps on beats; `circuit` lays out
tracks in lanes with light running along them, and prints labels with a 3 x 5 pixel font. `deep` draws translucent
shapes that glow (jellyfish) and lines that sway along their length; `cymatics` keeps lines an even width with a
field's value over its slope, and draws single grains of sand one per cell; `vinyl` uses the cover as a turning
label and draws `waveform` as the walls of a groove; `fireworks` draws many particles by working out only the
nearest one on each ring; `rain` draws its background once per pixel, sharp or soft depending on what is in front
(a drop is a lens). `topo` draws contour lines of an even width from `fwidth` of a height; `koi` bends each fish
along the curve of its path; `candles` works out what several loops share once, into an array; `paper` stacks
layers that each throw a shadow on the ones behind (test the same shape at a point moved towards the light), and
skips layers that cannot show; `bubbles` colours thin films by their thickness. `carousel` maps things onto a
turning cylinder (a pixel's angle round it from its x alone) and draws its horses back to front, starting from the
one nearest the back; `microscope` draws each thing as a filter over the lamp (what it absorbs, where it bends light),
so the same values give bright field and dark field; `volcano` works each pixel below the horizon back into the ground
(a plane in perspective) and drifts plates over it; `web` finds the pixel's sector between two spokes, where every
chord of the spiral is parallel, so the nearest chord is one division; `starlings` draws a flock from a density field,
one bird per cell from layers turning at different speeds. For ray marching within the budget: `lighthouse` (a
height field of waves; beams of light worked out exactly, not marched), `fractal` (a folded fractal with an orbit
trap), `balloons` (a short march inside each bounding sphere), `crystals` (one object per grid cell, glow gathered
along the ray) and `stage` (planes, boxes and beams, all exact). `city` walks a grid cell by cell along the ray (exact boxes
however far); `clouds` refines a height field's hit between the last two steps; `stadium` draws crowds of dots
and players as capsules; `kaleidoscope` folds the picture across mirrors and uses the cover; `organ` is flat but
built field by field with one function. Two lessons from them: a camera that pans over fine, high-contrast detail
counts as flicker, and so does anything random that changes every frame. `blackhole` steps each ray through
gravity (72 steps, the disc crossing found between two steps); `musicbox` traces its scene a second time for a
mirror; `snowglobe` refracts into a sphere and marches a small scene inside it; `fountains` reflects the ray in
water and finds the jets again; `pinball` repeats one machine along a row by folding the hit point. `cradle` follows each ray through four
reflections with a loop and a running tint; `lavalamp` marches only inside an exact bound; `piano` draws a
sounding string as its blur (wider and fainter), not as a line that moves; `tapedeck` shows a flat instrument
panel can be all signed distances; `zen` gets its relief from a normal made of a phase and its direction. `speakers` and `honeycomb` are flat too: their depth is a height lit from its slope, and a shadow found by asking whether a point moved towards the lamp is still inside its cell; `engine` is a machine in section, every part placed from one angle; `neon` draws its wall as a function and calls it again upside down for the wet ground; `wheat` is a plane in true perspective under a ceiling of noise.
