# TV tomorrow - the wall

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

12 of 12. Speculative, and kept calm: a bare pale room some day to come, a grey oak floor with a pale felt rug, a low
linen sofa of three (the viewer in its middle), a long window on a night of stars. No set at all: a part of the far
wall, in the walls' own plaster, becomes the picture. As the film starts it wakes, its light rising from half to full
over 4 s; then the film plays untouched.

- Systems: `light` (a cool low fill), `domestic` (`screen` `wall`, `screen_surface` the walls' plaster; `lamps` 0,
  `heater` none), `kit` (a `rug`), `seats` (`settee`), `sky` (night, a few clouds, the Milky Way faint),
  `presentation` (`preset` none: only the waking cue touches the picture).
- Settings: Stars in the window (0 to 100 %: `sky.stars`).
- Cues: `wall_wakes` (Pre-show): `presentation.gain` 0.5, then up to 1 over 4 s, then released.
- Measured: 13 draws, 7 662 triangles, 5.3 MB, no particles.
- Sound: `acoustics` `small_room` (`rt60` 0.3) and nothing else: a quiet room.

**The kit's dressing for these rooms** (`kit/dressing.gd`, since 2026-11-07): `bunting` (a sagging string of
pennants, red, white and blue in turn), `tea_set`, `sandwiches`, `stool`, `channel_dial` (a rotary dial with twelve
stops and two small knobs under it, on a set's front), `soundbar`, `floor_lamp` (a column shade, house group), `glass_table`
(the kit's glass mesh, `PieceGlass`, see-through) and `media_unit`. The china and the cloth (bunting, bread) are one
material each, coloured per vertex: bunting, a tea set and three plates of sandwiches cost two draws.

**What the systems lack for these rooms** (each room took the closest thing there is):

- A tube's own shape for the CRT (above).
- The radio-style cabinet of 1930 is the telly on a walnut chest (a `radiogram` stand is there now; the 1930 room
  keeps its chest).
- The seats system's own places are not listed before the room is built (no static layout), so the seat list before
  the build is the builder's alone.
- Sound: each room's beds and acoustics are in its own section (the recipes: "Sound and music", "For the rooms").
  `test_room_tv.gd` checks them: the sounds, each in the room, each 10 dB or more under the level check's target and
  all together 6 dB or more under it, the loops playing, the one-shots played by their cues.
