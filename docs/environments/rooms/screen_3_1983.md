# Screen 3 - 1983

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

`app/environments/screen_3_1983.env.json`. The old circle of a picture palace, walled off in 1983 into a small
multiplex screen: a steep rake of multiplex seats, a plasterboard wall with the screen on it, a swirly carpet and a
worn print.

- **The hall** (`auditorium`, id `hall`): 11.2 m wide, 9 rows of 13 multiplex seats on a steep rake (0.42 m a row),
  straight rows, the viewer in the middle of the fifth row from the front (the room's own seat, at the origin). The
  old fabric panels and sconces run on along the side walls and stop at the partition (`partition_z` -7.4), so the
  hall reads as cut in two. No drapes, no acoustic clouds; four exits with signs, the booth's windows in the rear
  wall.
- **The kit:** the swirling carpet on the floor; a plasterboard partition (taped joints, a skirting) over the
  hall's own; a water stain where the roof leaks down the new wall, in its top left corner (three patches of
  stained board, the dark tide line at their feet).
- **Seats** (`seats`): seat 69, in the row in front a little to the left, is broken (its back slumped).
- **Light:** the house lamps go down to 8 % over 4 s when the film starts or plays (cue `dim`, with the common Dim
  during the film on) and come back up in the pre-show and after the end (`lights_up`). The exit sign stutters now
  and then (cue `exit_sign`: every 20 s, a chance of 0.4, two dips of `light.signs` with fades of 0.2 s, under
  2 Hz); it needs the common Flickering lights on.
- **Screen:** 7 x 3.94 m on the partition, its masking (`screen_frame`) and the beam from the booth; smoke and haze
  in the beam (`atmosphere`: `beam_haze` 0.6, `beam_smoke` 0.8); the worn print (`presentation` preset
  `worn_print`: weave, tilt, flicker, dust, scratches, a hotspot). The film is drawn in the room (a picture stage).
- **Setting:** Weave and tilt (`weave`, 0..1, default 0.7): `presentation.weave` by range [0, 1] and
  `presentation.tilt` by range [0, 0.5] degrees. The common Motion setting scales both; Flickering lights holds the
  lamp's flicker and the exit sign steady.
- **Measured** (`tests/test_room_screen_3_1983.gd`, headless): 25 draws, 79 946 triangles, no live light, no
  particles, 10.4 MB of textures; a clear sight line from all 117 seats. Sound at the slider's default (dBFS RMS,
  `film.bass` held at 0.8): -57.9 in the pre-show, -56.7 in the film, -61.8 under a film at the reference level.
- **Sound:** `acoustics` `small_room` (rt60 0.6); `sound_bed` `next_screen` (`wall_rumble` through the left wall,
  `at` [-5.4, 1.5, -2], `reach` 5.5): `level` on `film.bass` (smooth 0.3 s), `film_db` 0, so it swells with the
  film's low end and is silent when there is none; the duck keeps it under the film.
