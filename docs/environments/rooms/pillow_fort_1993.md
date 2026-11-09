# Pillow Fort 1993

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

`app/environments/pillow_fort_1993.env.json` (Television). A child's bedroom on a rainy night: a pillow fort of
cushions and a bedsheet on broom handles round three floor cushions, fairy lights along its front, rain on the
window, and the telly filling the fort's opening, showing the film as a tube shows a tape watched a few times.

- **Systems:** `light`; `domestic` (`bedroom_1993`, `opening_screen` on: a 1.33 x 1.0 m picture just beyond the
  opening); `kit` (a `video_recorder` in the `telly_shelf` slot: on the floor in front of the telly's chest, its
  clock flashing 12:00); `seats` (`cushion` in the fort's three slots); `weather` (the pane on the window, facing in;
  300 drops outside it; the Rain setting on `mode`); `presentation` (`nightowl_1993`: a tape, a CRT with an aperture
  grille; the speaker by the setting).
- **Settings:** `rain`, "Rain on the window" (rain, drizzle, coming and going, none; rain): `weather.mode` by `map`;
  `telly_sound`, "The telly's own speaker" (off): `presentation.speaker` `telly` or `none`, so the film keeps its
  own sound unless asked.
- **Flicker:** the fairy lights waver slowly (the builder's `flicker`), the video recorder's clock flashes; Flickering
  lights holds them.
- **Default seat:** the middle cushion (the origin), 1.25 m from the picture.
- **Measured:** 23 draws, 5 444 triangles, 0 lights, 300 particles, 6.0 MB.
- **The telly fills the opening (a setting since 2026-11-07):** `telly_fills` (on by default) is bound to
  `domestic.opening_screen`. Turning it off rebuilds the room with the telly on its chest of drawers across the
  room, and the film goes with it (`env_room.gd _follow_builder_screen()`, below); the video recorder goes with it
  too (its slot follows the set). No tree or tin of sweets.
- **Sound:** `acoustics` `small_room` (`rt60` 0.3); `sound_bed`s: `radiator` at the radiator, `rain_glass` at the
  window with `level` on `weather.rain` (it goes quiet as the Rain setting dries the night), `vcr` by the video
  recorder, played by the cue `tape_in` as the film starts (the tape goes in). Each at its designed level: together
  about -49 dBFS in the pre-show, 11 dB under the level check's target, 8 dB lower while the film plays.
