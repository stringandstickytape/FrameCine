# Narrowboat

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

`app/environments/narrowboat.env.json` (Journeys), tested by `app/tests/test_room_narrowboat.gd`. The first of the
Journeys: a canal boat's saloon at walking pace. The boat leaves from under a lamp at dusk; reeds, willows, a hedge
and two brick bridges go by the windows; a village's lights come up across the fields; it ties up at a lamp-lit wharf
as the film ends. The journey is as long as the film (the passing system: `docs/environments/passing.md`).

## The parts

- **The saloon** (`cabin`, id `saloon`; `docs/environments/cabin.md`): 1.9 m wide at the floor, the walls 1.85 m
  high and leaning in 5 degrees, an arched roof rising 0.15 m more (2.0 m at the middle). From the front bulkhead at
  z -2.0 to the rear one at z 2.6: 4.6 m. Three windows a side, their middles at z -0.95, 0.25 and 1.45, each 0.75
  wide and 0.5 high with corners of 0.1, the sill 1.05 up. A dado of oak to 0.9 m, ribs between the bays, wall lamps
  1.4 m up at the bays' marks (z -1.55, -0.35, 0.85, 2.05, both walls), a door in the rear bulkhead with its light
  (`door_glow` 0.25), a ledge 0.12 wide outside each wall at 0.95. Painted walls and ceiling, oak planks, a dark
  hull. The picture is 1.4 m wide (its height 16:9 from it: 0.7875), its bottom 0.92 m up, on the front bulkhead.
  The viewer's own seat is at the origin; no seat is drawn there (below, "Furniture").
- **The light** (`light`): warm lamps, a low baked fill, warm above and darker below.
- **The sky** (`sky`): latitude 52.5, day 250, the boat heading 20 degrees, 20:15 at the start; the sunset's glow at
  290 degrees, the evening star, a little of the Milky Way, a few clouds, the Moon (0.8 full) low at 110 degrees.
- **The canal** (`passing`, id `canal`): forward (the way goes towards the picture) at 1.0 m/s, the cabin's glow 0.6
  in `#ffbe78` reaching 9 m out and 3 m ahead and astern, the mist `#39424f`, the screen's spill 0.4.

### The canal's cross-section

Metres from the way's line; the ground's heights are over the room's floor (the eyes are at 1.2).

| Side | From | To | What |
|---|---|---|---|
| left | 1.0 | 7.5 | water (at 0.55) |
| left | 6.6 | 7.6 | reeds, 150 on a 240 m loop |
| left | 7.5 | 8.2 | grass, the bank rising from 0.55 to 0.92 |
| left | 8.2 | 60 | grass rising to 1.5 |
| left | 8.6 | 10.5 | willows, 12 on a 264 m loop |
| left | 11.5 | | a post-and-rail fence (gone from 0.42 to 0.62 of the route) |
| left | 30 | 33 | poplars, 10 (from 0.08 to 0.34 of the route) |
| left | 36 | 58 | cottages, 6 (all of them from 0.66 to 0.82 of the route, coming and going over 0.06: the village) |
| left | 60 | 175 | fields rising to 5.0 |
| right | 1.0 | 4.95 | water (at 0.55) |
| right | 4.75 | 5.0 | reeds, 70, smaller (0.8), thinning in places, gone at the end |
| right | 4.95 | 5.1 | the stone edge of the towpath, 0.55 to 0.85 |
| right | 5.1 | 6.7 | the towpath (at 0.85) |
| right | 6.7 | 8.6 | grass to 1.0 |
| right | 7.4 | | a hedge (a third of it from 0.34 to 0.5 of the route, half of it at the end) |
| right | 8.6 | 175 | fields rising to 5.0 |
| both | 16 | 44 | trees, 30 (a wood from 0.42 to 0.58 of the route, a quarter to a third of them elsewhere) |
| both | 46 | 60 | a village's lights, 70, seeming 5 times further (coming up from 0.25 of the route, all by 0.66) |
| both | 64 | | a low ridge, seeming 18 times further |

### Along the route

| Fraction | What | Side |
|---|---|---|
| 0 | a lamp on a post (5.6 m) | right |
| 0.004 | a narrowboat moored (6 m) | left |
| 0.14 | a brick bridge over the way (6.8 m, size 1.3) | right |
| 0.48 | a narrowboat moored, red | left |
| 0.61 | a brick bridge, grey | right |
| 0.75 | a church tower far off (110 m) | left |
| 0.984 | a lamp on a post | right |
| 0.99 | a narrowboat moored, blue | left |
| 1.0 | the wharf (4.95 m) | right |

With a film of two hours the route is 7 197 m: the film's length at 1 m/s, less the 3.3 m the slowing for the end
saves.

## The film's evening

- **Tracks** (by `film.progress`): `sky.dusk` from 0.15 to 0.75 at 0.3 and full at 0.6 (smoothed 0.5 s); `sky.hour`
  from 20.25 to 23.0 over the film (1 s); `canal.mist` none until 0.45, 0.35 at 0.7, 0.2 at the end (0.5 s).
- **Cues:** `dim` (as the film starts: the lamps to 0.1, the door's light to 0.08, the cabin's glow outside to 0.3,
  each over 4 s); `lights_up` (the pre-show and the end: the lamps up, the door's light and the glow back to their
  own, over 4 s); `owl` (every 200 s while playing, paused or in the credits, a chance of 0.4: the owl calls);
  `bell` (when `journey.progress` has been over 0.74 for 2 s while playing, at most once in two hours: the church
  bell as the tower comes by).

## Comfort

The nearest any part of each band and landmark comes to the line the eyes go along (`Shapes.nearest()`, as
`passing.gd comfort_for()` asks it: a scattered band at its largest, 1.25 times its size), and the degrees a second it
crosses the eye there at the fastest the journey goes: 1.0 m/s x (1 + `CATCH_UP`) = 1.15 m/s, slowed by `seems`.
Printed by `test_room_narrowboat.gd`. The limits: 3 m and 20 degrees a second (`docs/environments/checks.md`).

| What | Side | Its foot | Nearest | Degrees a second |
|---|---|---|---|---|
| band 0, reeds | left | 6.6 | 5.47 | 12.0 |
| band 1, hedge | right | 7.4 | 6.72 | 9.8 |
| band 2, willow | left | 8.6 | 4.37 | 15.1 |
| band 3, tree | both | 16 | 9.29 | 7.1 |
| band 4, poplar | left | 30 | 27.93 | 2.4 |
| band 5, fence | left | 11.5 | 11.45 | 5.8 |
| band 6, cottage | left | 36 | 33.17 | 2.0 |
| band 7, lights (seems 5) | both | 46 | 46.00 | 0.3 |
| band 8, ridge (seems 18) | both | 64 | 64.00 | 0.1 |
| band 9, reeds | right | 4.75 | 3.80 | 17.3 |
| landmark 0, lamp | right | 5.6 | 5.54 | 11.9 |
| landmark 1, boat | left | 6.0 | 5.00 | 13.2 |
| landmark 2, bridge | right | 6.8 | 4.55 | 14.5 |
| landmark 3, boat | left | 6.0 | 5.00 | 13.2 |
| landmark 4, bridge | right | 6.8 | 4.55 | 14.5 |
| landmark 5, tower | left | 110 | 106.50 | 0.6 |
| landmark 6, lamp | right | 5.6 | 5.54 | 11.9 |
| landmark 7, boat | left | 6.0 | 5.00 | 13.2 |
| landmark 8, wharf | right | 4.95 | 4.95 | 13.3 |

The nearest is the right bank's reeds, 3.8 m off at 17.3 degrees a second. Nothing goes by within 10 degrees of the
picture from the seat (`flow_clear()`).

## Sound

- `acoustics` `small_room`; the document's own `acoustics` section for the film's room: walls 0.3 and 0.35, rt60
  0.25, wet 0.1, late 0.4.
- `sound_bed` `owl` (`tawny_owl`) in the trees far off on the left ([-38, 9, -12], `reach` 30), played by the `owl`
  cue.
- `sound_bed` `bell` (`church_bell`) at the church far off on the left ([-110, 18, -20], `reach` 110), played by the
  `bell` cue.
- `sound_bed` `engine` (`boat_engine`): the diesel under the stern deck behind the rear bulkhead ([0, 0.4, 4.2],
  `reach` 3), `film_db` -10; its `level` follows `journey.speed` from 0.4 to 1 (smoothed 1.5 s), so it idles while
  the boat is stopped and runs full under way.
- `sound_bed` `water` (`water_lap`): water on the hull, everywhere, `gain_db` -2, `film_db` -10.
- Measured (`test_room_narrowboat.gd`, the slider's default): -55.8 dBFS RMS in the pre-show (peak -37.8), -71.5
  under a film at the reference level.

## Furniture

The kit `fittings` (after the cabin; every piece placed in the room's frame, no slot):

- `boat_stove` at [-0.66, 0, 2.2], turned 90 degrees so its front faces +X, into the cabin: the left wall behind it,
  by the rear door. Its flue goes up through the roof's edge. Its door's window glows in the kit's `window_colour`,
  set to [1.0, 0.45, 0.15]; it lights nothing.
- `rug` on the floor, its middle at [0, 0, -0.75], 0.8 wide and 1.7 long, [0.32, 0.08, 0.07].
- `sideboard` against the front bulkhead under the picture: its back at z -1.97 (its foot at z -1.82), its middle at
  x 0, 1.3 wide, 0.7 high and 0.3 deep. The picture's bottom edge is at 0.92.

Left out: the `stool` at [0.56, 0, -0.15] and the `tea_set` on it. Nothing but the rug may come within 0.45 m of the
seat, and both would: the stool's legs reach to x 0.37 and its box to 0.42, and the tea set (0.5 wide) to 0.31.

No club chair is drawn at the origin, though the cabin draws its seat (`seating` none, `seat_model` club): the seat
the viewer sits in is folded away (`kit/builder.gd _hide_occupied_seat()` scales the seat under the viewer to
nothing), and the cabin's only seat is the one at the origin.

## Measured

`test_room_narrowboat.gd`, headless, 2026-11-09: 26 draws, 36 723 triangles, no live lights, no particles, 9.3 MB of
textures. The windows' glass is at most half a layer over the view on average (`blend_layers()`).

## Not done yet

On the headset: not run. The comfort limits (docs/environments/checks.md, FLOW_*) are judgments until someone has
watched a film in it.
