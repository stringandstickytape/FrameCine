# Showboat 1927

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

`app/environments/showboat_1927.env.json` (Journeys), tested by `app/tests/test_room_showboat.gd`. The second of the
Journeys: a floating theatre on a wide river. Tall windows look out on the near bank's trees and a levee town, with
open water and a steamer at anchor on the left. The hall leaves a wharf at dusk and ties up at a lamp-lit landing
with the credits. The journey is as long as the film (`docs/environments/passing.md`).

## The parts

- **The hall** (`cabin`, id `hall`; `docs/environments/cabin.md`): 7.2 m wide, straight walls 3.2 m high, an arched
  roof rising 0.6 m more (3.8 m at the middle). From the front bulkhead at z -5.6 to the rear at z 4.6: 10.2 m.
  Its centre line is x -0.7, putting the viewer's own seat at the origin. Six windows a side, their middles at
  z -4.0, -2.5, -1.0, 0.5, 2.0 and 3.5, each 0.9 m wide and 1.7 high, the sill 0.95 up, corners of 0.2.
  A dark wooden dado to 0.9 m, ribs 0.12 wide and 0.04 deep, a cornice 0.12 high, wall lamps 2.2 m up between the
  windows at twice a small cabin's size (`lamp_size` 2), a rear door with its light (`door_glow` 0.25). White and
  gold with red plush: ivory painted walls [0.8, 0.76, 0.66] and a paler ceiling; gilt trim (brass, [0.95, 0.68,
  0.25]: the ribs, the cornice, the window frames, the rail, the picture's frame); a painted door; oak planks on the
  floor and hull; red velvet bulkheads; red felt seats on dark metal frames. A ledge 1 m wide outside each wall at
  y -0.02. The picture is
  4.0 m wide and 2.25 high, its bottom 1.2 up, centred at [-0.7, 2.325, -5.57] on the front bulkhead.
- **The seats:** seven rows of eight folding seats (three rows ahead of the viewer's, three behind), four either
  side of a 0.9 m aisle. Rows 0.95 m apart, seats 0.5 m apart; the viewer is in the right block by the aisle
  (`own_side` right, `own_index` 0). There are 56 seat transforms, one at the origin; the occupied seat folds away.
- **The stage** (`kit`, id `fittings`): a low wooden platform with footlights under the picture, and gilt pilasters
  with drawn-back drapes either side of it (below, "Furniture").
- **The light** (`light`): warm lamps, spill 0.6, baked fill 0.1, warm above and darker below.
- **The sky** (`sky`): latitude 36, day 190, heading 180 degrees, 20:00 at the start; sunset glow at 300 degrees,
  the evening star, a little of the Milky Way, a few clouds, the Moon low at 100 degrees, phase 0.9: out of the left windows, a little ahead, its road on the water under it
  (`docs/environments/passing.md`, "The shaders").
- **The river** (`passing`, id `river`): forward at 2.0 m/s, glow 0.5 in `#ffc98a` reaching 14 m out and 6 m ahead
  and astern, mist `#3a424c`, screen spill 0.3.

### The river's cross-section

Metres from the way's line; heights are over the hall's floor (the eyes are at 1.2). The right is the near bank;
open water lies to the left, with a low ridge and lights on the far shore.

| Side | From | To | What |
|---|---|---|---|
| right | 4.0 | 10.0 | water at -1.1 |
| right | 10.0 | 12.0 | grass, the bank rising from -1.1 to 0.2 |
| right | 12.0 | 40.0 | grass rising from 0.2 to 0.8 |
| right | 13.0 | 17.0 | willows, 14 on a 300 m loop, size 1.1, feet at 0.2 |
| right | 19.0 | | a fence on a 240 m loop, feet at 0.35, gone from 0.42 to 0.7 of the route |
| right | 24.0 | 70.0 | broadleaf trees, 34 on a 320 m loop, feet at 0.5 |
| right | 38.0 | 66.0 | cottages, 7 on a 340 m loop, feet at 0.8, present from 0.4 to 0.7, full from 0.47 to 0.62 |
| right | 40.0 | 46.0 | poplars, 8 on a 340 m loop, feet at 0.8, present from 0.28 to 0.46, full from 0.34 to 0.42 |
| right | 40.0 | 175.0 | fields rising from 0.8 to 4.0 |
| right | 45.0 | 80.0 | town lights, 60 on a 320 m loop, seeming twice further, feet at 1.5 |
| right | 85.0 | | ridge on a 336 m loop, size 0.8, seeming 10 times further, feet at 0 |
| left | 5.4 | 175.0 | open water at -1.1 |
| left | 26.0 | 44.0 | channel buoys, 5 on a 340 m loop, red or green with a light, feet at -1.1 |
| left | 60.0 | 68.0 | far-shore lights, 40 on a 320 m loop, size 0.8, seeming 6 times further, feet at 0 |
| left | 70.0 | | low dark ridge on a 336 m loop, size 0.22, seeming 6 times further, feet at -1.1 |

The near town's lights rise from 0 at 0.38 of the route to full at 0.46, stay full to 0.64, and fall to 0.15 at
0.72, held to the end. The far-shore lights rise from 0 at 0.2 to 0.5 at 0.35 and full at 0.6, stay full to 0.8,
and fall to 0.3 at 0.9. The fence fades out from 0.38 to 0.42, and back from 0.7 to 0.75.

### Along the route

| Place | What | Side |
|---|---|---|
| 0.0 | wharf, 10 m off, foot at -0.5 | right |
| 0.0, 5 m ahead | lamp on the wharf, 11.5 m off, foot at 0.2 | right |
| 0.3 | steamer at anchor, 40 m off, water line at -1.1 | left |
| 0.52 | tower, 120 m off, foot at 2.5 | right |
| 1.0, 7 m before | lamp on the landing, 11.5 m off, foot at 0.2 | right |
| 1.0, 5 m ahead | lamp on the landing, 11.5 m off, foot at 0.2 | right |
| 1.0, 6 m before | steamer moored, 34 m off, water line at -1.1, seed 7 | left |
| 1.0 | wharf, 10 m off, foot at -0.5 | right |

The two ends are set out in metres (a landmark's `ahead`), so they are the same in a film of any length. When the
hall stops, the wharf is abeam on the right with a lamp ahead of the seat and one astern, and the steamer lies to
the left, its stacks a little ahead of abeam and the Moon over its bow.

## The film's evening

- **Tracks** (by `film.progress`): `sky.dusk` from 0.1 to 0.8 at 0.35 and full at 0.6 (smoothed 0.5 s);
  `sky.hour` from 20.0 to 23.0 over the film (1 s); `river.mist` none until 0.5, 0.25 at 0.8, 0.2 at the end
  (0.5 s). The timeline has an 8 s start and 6 minutes of credits.
- **Cues:** `dim` as the film starts: lamps to 0.1, door light to 0.08, river glow to 0.25, each over 5 s;
  `lights_up` in the pre-show and at the end: lamps to 1, door light and river glow released to their own values,
  each over 4 s. Each cue stops when the other's states begin.

## Comfort

The nearest any part of each band and landmark comes to the line the eyes go along (`Shapes.nearest()`, as
`passing.gd comfort_for()` asks it: a scattered band at its largest, 1.25 times its size), and the degrees a second
it crosses the eye there at the fastest the journey goes: 2.0 m/s x (1 + `CATCH_UP`) = 2.3 m/s, slowed by `seems`.
Printed by `test_room_showboat.gd`. The limits are 3 m and 20 degrees a second (`docs/environments/checks.md`).

| What | Side | Its foot | Nearest | Degrees a second |
|---|---|---|---|---|
| band 0, willow | right | 13.0 | 7.98 m | 16.5 |
| band 1, fence | right | 19.0 | 18.95 m | 7.0 |
| band 2, tree | right | 24.0 | 16.83 m | 7.8 |
| band 3, poplar | right | 40.0 | 37.90 m | 3.5 |
| band 4, cottage | right | 38.0 | 35.12 m | 3.8 |
| band 5, lights (seems 2) | right | 45.0 | 45.00 m | 1.5 |
| band 6, ridge (seems 10) | right | 85.0 | 85.00 m | 0.2 |
| band 7, ridge (seems 6) | left | 70.0 | 70.00 m | 0.3 |
| band 8, lights (seems 6) | left | 60.0 | 60.00 m | 0.4 |
| band 9, buoy | left | 26.0 | 25.44 m | 5.2 |
| landmark 0, wharf | right | 10.0 | 10.00 m | 13.2 |
| landmark 1, lamp | right | 11.5 | 11.05 m | 11.9 |
| landmark 2, steamer | left | 40.0 | 35.50 m | 3.7 |
| landmark 3, tower | right | 120.0 | 116.50 m | 1.1 |
| landmark 4, lamp | right | 11.5 | 11.05 m | 11.9 |
| landmark 5, lamp | right | 11.5 | 11.05 m | 11.9 |
| landmark 6, steamer | left | 34.0 | 29.50 m | 4.5 |
| landmark 7, wharf | right | 10.0 | 10.00 m | 13.2 |

The test also checks that nothing goes by within `FLOW_CLEAR_DEG` of the picture from the seat (`flow_clear()`).

## Sound

- `acoustics` `shopfront` for the room's beds. The document's film acoustics: reflect [0.4, 0.4, 0.35, 0.5, 0.3, 0.4],
  rt60 0.7 s, wet 0.45, late 1.2.
- `sound_bed` `wheel` (`paddle_wheel`) astern at [-0.7, 0.5, 14.0], `reach` 9, `film_db` -12. Its `level` follows
  `journey.speed` from 0.05 to 1, smoothed 1.5 s: low while stopped, full under way. A 6 s loop of buckets slapping
  the water three times a second, wash and a slow engine.
- `sound_bed` `water` (`water_lap`) everywhere, `gain_db` -3, `film_db` -10.
- `sound_bed` `crickets` (`crickets`) around, `radius` 14, `reach` 10, `gain_db` -4, `film_db` -10.
- `sound_bed` `train` (`train`) far off at [260, 2, -160], `reach` 300, `every` 800 s.
- Measured: the room's sound is -57.8 dBFS RMS in the pre-show and -69.2 under a film at the reference level.

## Furniture

The kit `fittings` follows the cabin; its two pieces are placed in the room's frame, without a slot.

`show_stage` at [-0.7, 0, -5.0], size [7.2, 0.6, 1.2], front facing +Z: a wooden platform 0.45 m high with a
moulding along its front top edge, and seven dark iron footlight hoods. The wood is [0.2, 0.13, 0.08], the moulding
1.4 times it, the iron [0.05, 0.05, 0.055]. A small face behind each hood glows in [1.0, 0.8, 0.5] with the house
lights: bright before the film, all but out during it. One collision box covers the platform.

`show_proscenium` at [-0.7, 0.45, -5.53], size [5.6, 3.0, 0.3], front facing +Z: two gilt pilasters with bases
and capitals, and drawn-back drapes either side of the picture. The pilasters use the kit's `gilt` tinted [0.95, 0.68, 0.25], the
hall's own gilding; the drapes use its `drapes` (velvet that pleats) tinted [0.4, 0.05, 0.06], four folds a side,
every other face at 0.7 of that colour. Two
collision boxes cover the pilasters. The test checks both pieces' boxes stay inside the hall and nothing is within
0.45 m of the seat in x and z.

## Measured

26 draws, 35974 triangles, 0 lights, 10.3 MB of textures (`test_room_showboat`, headless, 2026-11-10).

## Not done yet

On the headset: not run.
