# TV today - the present

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

11 of 12. A living room now: charcoal walls, a grey oak floor with a pale grey rug, a very thin OLED panel on the
wall (`telly` `oled`, 3 cm; a 55 inch 16:9 picture, 3.2 m from the seat) over a long low oak media unit, a soundbar
on the unit under the picture, a grey sofa of three and an armchair, a low oak coffee table, a tall floor lamp beside
the sofa, a plant, a night window with rain on it now and then. No wall lamps, no fire: the film looks its best here
(`slimline_present`: true blacks, letterboxed, a sheen only at a glance; the film's own sound, no small speaker).

- Systems: `light` (a low grey fill), `domestic` (`telly` `oled` on the `wall`; `lamps` 0, `heater` none, the
  window's night glow), `kit` (a `media_unit`, a `soundbar`, a `rug`, a `coffee_table`, a `floor_lamp`, ferns),
  `seats` (`settee`, an armchair), `weather` (changing, the pane only: no drops falling), `presentation`
  (`slimline_present`, `starts_off`, `speaker` none).
- Settings: Floor lamp in the film (0 to 100 %, default 15 %: the house group, the floor lamp's shade).
- Cues: `switch_on` (Pre-show, 2 s in), `switch_off` at the end; the floor lamp down to the setting.
- Measured: 22 draws, 2 956 triangles, 7.0 MB, no particles.
- Sound: `acoustics` `small_room` (`rt60` 0.3: soft furnishings); `rain_glass` at the window (`gain_db` -6, `level`
  on `weather.rain`). Measured (`test_room_tv2.gd`, the rain full): -65.3 dBFS RMS in the pre-show, -80.3 under a
  film at the reference level.
