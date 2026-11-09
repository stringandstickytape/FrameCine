# The presentation system

Part of the environments engine: [`docs/environments.md`](../environments.md) has the design and says where each part is.

`scripts/env/systems/presentation.gd`, with `shaders/env_presentation.gdshader` and its stages in
`env_presentation.gdshaderinc`. The stages between the film and the eyes, each optional. One per room.

| Stage | Parameters | What |
|---|---|---|
| source | `source`: `none`, `film`, `tape`, `broadcast` | where the picture comes from |
| film | `weave`, `tilt` (degrees), `flicker`, `dust`, `scratches`, `hotspot` | gate weave, a crooked projector (the picture is overscanned a little, so no corner shows), the lamp's flicker, dust specks, scratches that run for a few seconds, the lamp's bright middle |
| tape | `tracking`, `head_switch`, `chroma_bleed`, `tape_noise` | the lines' slow sway, the torn last lines at the bottom, the colour late and smeared, noise and paler colour |
| broadcast | `interlace`, `lines` | the two fields' lines, one after the other |
| transmission | `snow`, `ghost`, `ghost_shift`, `weak` | aerial noise, a faint second picture to the right, a weak signal (paler, flatter, more snow) |
| display | `display`: `none`, `mechanical`, `crt`, `panel`, `rear_projection`, `oled` | the set |
| crt | `curvature`, `corner`, `mask` (`none`, `shadow`, `grille`, `slot`), `mask_pitch`, `mask_strength`, `scanlines`, `glass` | the bulging face, round corners, the phosphors' mask, the gaps between lines, the glass's reflection (a soft light behind the viewer that moves as the head moves) |
| mechanical | `mech_lines` | a 1930 mechanical-scan set: a few lines across, a neon's orange glow, dark edges |
| panel | `panel_grid`, `panel_pixels`, `panel_bleed` | the gaps between the pixels, the backlight through the dark scenes |
| rear_projection | `soft_focus`, `convergence`, `lenticular`, `hotspot` | a 2002 rear projection: the picture a little soft, the red and the blue a little apart (more at the edges), the screen's fine vertical lines, a faint bright patch where the eye looks down the projector's light (it follows the head), a grey-black face |
| oled | | true blacks (no backlight, no lift), a little punch in the colour and the middle tones (black stays black, white white: the film's levels are kept), a sheen only at a glance |
| the window | `tube`, `aspect_mode`, `mirror` | below |
| off axis | `off_axis` | below |
| switching | `switching`, `warm_up`, `off_dot`, `starts_off`, `switch_sounds`, `sound_db` | below |
| colour | `colour`, `tint`, `gain` | saturation (0: black and white), the tube's tint, brightness |
| speaker | `speaker`: `none`, `window`, `telly`, `cabinet`, `panel` | the film's sound through a small speaker |

Every parameter is live but `starts_off`. `weave`, `tilt` and `tracking` are motion parameters (the room's Motion
setting scales them). `flicker` is a brightness that flickers: it wavers by at most 3.5 %, more slowly than 3 times a
second, and stays steady with Flickering lights off. Actions: `glitch` (a moment's trouble: a tape's tracking tears, a
broadcast's snow swells, a print jumps in the gate; `seconds`, default 0.6), `switch_on`, `switch_off`, `channel`
(below).

**The set's window and the film in it.** The app makes the film's quad as wide as the room's screen, its height from
the film's shape. The set's window is as wide, its shape `tube`.
- `tube`: the window's aspect, for every display (1.33 for the tubes before 2000, 1.78 for a 16:9 panel, 1.25 for the
  1937 tube; 0: the film's own). Give the room's screen the same shape: outside the window the shader discards the
  film, so the set's bezel shows there.
- When the window is taller than the film's quad (a wide film in a 4:3 tube), the quad grows to the window in the
  vertex stage (its height only, so a curved screen keeps its curve), and the bars are drawn as the set's black (with
  its glass and round corners). The flat mesh's cull margin grows by a metre while the presentation draws it.
- `aspect_mode`: `letterbox` (as before: all of the film, black bars where its shape differs; a 4:3 film on a 16:9
  panel is pillarboxed), `pan_and_scan` (the film fills the window, its sides cut off: the 1937 and 1966 presets),
  `fourteen_nine` (14:9 of a wide film across the window: a little cut, thin bars), `stretch` (the film stretched to
  the window: a 4:3 film on a 16:9 panel).
- `mirror`: the picture flipped left to right, a mirror-lid set seen the wrong way round. Off by default: the set's
  electronics turn it round.

**Off the axis.** `off_axis` (0 to 1, default 0) changes the picture by the angle from the viewer's eye to the screen's
normal, per eye: a tube a little darker from the side, a rear projection's light in a narrow fan (wide across, narrow
up and down: from 30 degrees above it is half as bright, from the side much less dim), a flat panel's contrast and
colour shifting (most from above and below), an OLED's colour a touch cooler.

**Switching on and off.** `switch_on` and `switch_off` (actions) take the set from and to dark, its own way
(`switching`; `auto` by the display):

| Way | On | Off |
|---|---|---|
| `crt` (auto for `crt`) | 1.6 s (at least 1.5): a small dot, a line opening across, then the raster opening up and down | 1.1 s: the picture collapses to a line, the line to a dot, the dot fades (its afterglow) |
| `valve` (auto for `mechanical`; `fireside_1953`, `colourstar_1972`, the 1937 and 1966 presets) | 8 s (`warm_up`): dark while the heaters warm, then the picture comes up dim and a little small, growing and brightening | 2.4 s: as a tube's, the dot lingering |
| `panel` (auto for `panel` and `oled`) | 0.9 s: it just comes up | 0.35 s: it goes black |
| `projection` (auto for `rear_projection`) | 3 s: a slow fade up | 0.6 s: a fade down |

- `warm_up` gives the seconds to come on (0: the way's own). `switch_on` takes `seconds` too.
- `off_dot` (since 2026-11-07): the seconds a tube's dot lingers after the collapse (-1: the way's own, 0.6 s for a
  `crt` and 1.7 s for a `valve` set; 0: none). Each era has its own: sets before spot suppression burned a dot for
  seconds, later sets barely showed one. `mirrorlid_1937` 8 s, `fireside_1953` 6, `rental_1966` 3, `colourstar_1972`
  1.5, `sirclive_1983` 0.8, `rewinder_1987` 0.5, `nightowl_1993` 0.25. The dot holds, then fades over at least 0.35 s.
  A mechanical set (`glowbox_1930`) has no tube: its glow dies with no dot. The TV rooms switch their set off at the
  end of the film and when the film is closed (the `switch_off` cue in `ended` and `preshow`), and time travel
  switches each era's set off and waits for its dot before it moves on (`stay_off` keeps the set dark meanwhile).
- `starts_off`: the set is dark (its face drawn: a tube's grey glass, a rear projection's grey-black, an OLED's black)
  until a cue switches it on. It comes on by itself when the film plays, so a film never plays on a dark set.
- `channel` (action, `seconds`, default 1, at least 0.9): a channel change. The knob's clunk, the picture dips to about
  half with a moment's snow and comes back; a panel goes black for a moment.
- Comfort: the light and the beam's glow each rise and fall at most once, and each fade takes at least the comfort
  ceiling's fade (`env_checks.gd MIN_FADE`). The squeezed picture and the line are never brighter than 0.85. The dot
  is small: about 3 % of the picture's height across. Tested in `test_env_presentation.gd`.
- Sounds: `switch_sounds` (default on) plays our own sounds at the screen on the room's bus, at their designed levels
  (`sound_bed.gd LEVELS`) plus `sound_db`, 8 dB lower while the film plays: a `crt` set's `switch_clunk` on and
  `switch_clunk` and `crt_off` off; a valve set's `switch_clunk` and `valve_hum` on; a projection's `switch_clunk`; a
  panel is silent. A channel change plays `channel_clunk` (not on a panel). They are made on a worker thread when the
  room is built.
- A cue: `{"do": "presentation.switch_on"}` in `starting` (the Pre-show), `{"do": "presentation.switch_off"}` in
  `ended`.

**Not built: the 1930 set's 12.5 frames a second.** The mechanical set drew 12.5 pictures a second. Holding each
frame for 80 ms needs a history of the film's frames: a copy of the decoder's planes (hardware textures on the Frame)
made 12.5 times a second by a render pass of its own, and both eyes for a 3D film. And the held frames would put a
12.5 Hz change into the picture, in the band (3 to 30 Hz) the comfort rules keep out, even behind the Motion and
Flickering lights settings. So it is left out; the 30 lines and the orange glow carry the era.

**Presets.** `preset` fills every parameter the document leaves out. The document's own values and bindings win. To
move a preset's value by a cue, give it in the document. The names are pastiche.

| Preset | For | Chain |
|---|---|---|
| `worn_print` | Screen 3, 1983 | film: weave, a 0.35 degree tilt, flicker, dust, scratches, a hotspot |
| `starlight_lot_1958` | Drive-in | film: a little weave and dust, a strong hotspot; the window speaker |
| `glowbox_1930` | TV era | a mechanical-scan set: 30 orange lines, a little noise; a radio cabinet's speaker |
| `fireside_1953` | TV era | broadcast, 405 lines, snow and a ghost; a small black and white tube with round corners |
| `colourstar_1972` | TV era | broadcast, interlace, a faint ghost; an early colour tube with a shadow mask, warm and rich |
| `sirclive_1983` | TV era | a home computer's aerial lead: 240 bold lines, a little noise; a portable telly's shadow mask |
| `rewinder_1987` | TV era | a rented tape: wobble, bleed, the bottom's tear; a slot mask |
| `nightowl_1993` | Pillow Fort | a tape watched a few times; a flatter tube with an aperture grille |
| `freedtv_2005` | TV era | a free digital broadcast on an early flat panel: a faint pixel grid, backlight bleed |
| `mirrorlid_1937` | TV era | a pre-war mirror-lid set: 405 lines, a small round 5:4 tube (`tube` 1.25), greenish white, snow and a ghost, the film panned and scanned, a valve warm-up of 10 s |
| `rental_1966` | TV era | a rented black and white console: 405 lines, a 4:3 tube, the film panned and scanned, a valve warm-up of 9 s |
| `projection_2002` | TV era | a 50 inch rear projection playing a disc: 16:9, soft focus, fringes, lenticular lines, a hotspot, a picture that dims from above or below (`off_axis` 0.8) |
| `slimline_present` | TV era | a very thin OLED panel: 16:9, true blacks, a sheen at a glance, a touch of colour shift from the side |

**How the film is drawn.** On the Frame the film is an OpenXR layer, and a layer skips the scene's shaders. So while a
picture stage is on, the screen's flat mesh draws the film with the presentation's material, and the film layer
steps aside: the system asks with `film_layer.gd request_scene()`; no layer is made while any room asks, and the
System tab says why. The material is the screen's own picture (`video_common.gdshaderinc`, its uniforms copied from
the screen's material when they change), then the stages. With every picture stage off (the Drive-in with only its
speaker) nothing changes, and the film layer stays. Leaving the room puts the screen's material back. Flat screens
only: 180, 360 and fisheye films keep the screen's own picture. The floor reflection and the bias light read the
video planes, so they show the film without the stages.

**The sound.** A bus of its own, "Film speaker", made once just before Film (a bus can send only to one before it).
While a speaker is on, Film sends to it and it sends to Master: a high-pass and a low-pass filter, an EQ, a little
drive for the window speaker, and mono. The binaural renderer's code is not touched; it mixes into Film as before,
and the speaker filters what Film sends on. Effects on the Film bus itself were rejected: adding one makes the engine
make every effect on that bus again, so the film's analysis (`film_react.gd`, the music card) would lose its analyser.
The film's analysis and the duck's key stay on Film, so they hear the film as it is. Measured
(`test_env_presentation.gd`, a tone at -20 dBFS RMS on Film): the window speaker takes an 80 Hz tone to -107 dBFS
and leaves 1 kHz at -18.4 dBFS.

**Cost.** The system draws nothing of its own (0 draws). Its cost is the film drawn in the room instead of the
layer: on the Frame the layer saved 1.1 ms of GPU time with a 4K film (`docs/features.md`, "Film layer"), and the
mesh path is resampled twice (softer fine detail). The stages add little: no loop and no texture read of their own,
except one cheap sample each for the ghost and the chroma bleed (and the screen's deband is turned off under noise,
which saves eight). Every pattern (a mask, scanlines, a pixel grid) fades out as its period nears two eye-buffer
pixels, so it never shimmers; a telly's mask shows only when you lean in. Measured under lavapipe (CPU, so ALU counts
more than on a GPU), the screen's quad filling 1920 x 1080, frame time against the screen's own shader (18.8 ms;
the figures move by about 10 % from run to run):

| Preset | x |
|---|---|
| `glowbox_1930` | 0.75 |
| `fireside_1953`, `colourstar_1972`, `sirclive_1983`, `rewinder_1987`, `nightowl_1993` | 0.88 to 0.97 |
| `worn_print`, `starlight_lot_1958` | 1.0 to 1.05 |
| `freedtv_2005` | 1.14 |
| `mirrorlid_1937`, `rental_1966` (2026-11-07) | 0.95 to 1.0 |
| `slimline_present` (2026-11-07) | 0.95 to 1.2 |
| `projection_2002` (2026-11-07) | 1.8 to 2.0 |

The noisy chains cost less than the screen's own shader because its deband (eight reads) is off under them; with the
deband left on they measured 1.45 to 2.2 times. The rear projection costs most: its soft focus widens the footprint
filter (held to two taps a side, so at most eight reads) and its fringes take two more samples. In the test the card
is smaller than the view, so the screen's own filter takes one sample and the rear projection's eight; with a 4K
film on the headset the screen's filter already takes up to eighteen, and the rear projection's eight are fewer. On the Adreno the screen's shader is bound by its texture reads (the footprint filter, the deband); the stages are
ALU of a few dozen operations and at most two more bilinear reads, and a telly covers a small part of the view (a
0.6 m set at 1.5 m is about 6 % of an eye's pixels). Not measured on the headset yet.
