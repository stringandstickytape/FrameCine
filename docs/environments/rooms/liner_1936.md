# Liner 1936

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

`app/environments/liner_1936.env.json` (Journeys, built by **Gemini 4 Neon Extra High**), tested by
`app/tests/test_room_liner_1936.gd`. The third of the Journeys: a 1936 ocean liner's Streamline Moderne lounge crossing
the Atlantic at night. The ship itself never rolls; the tall velvet drapes beside the windows sway gently in unison with
the sea swell instead. Open sea stretches to the horizon on both sides, the Moon lays its road across the port water, a
sister liner passes in mid-Atlantic, and a breakwater lighthouse and lit harbour pier welcome the ship with the credits.
The journey is as long as the film (`docs/environments/passing.md`).

## The parts

- **The lounge** (`cabin`, id `lounge`; `docs/environments/cabin.md`): 8.0 m wide, straight walls 3.4 m high, an arched
  roof rising 0.65 m more (4.05 m at the crown). From the front bulkhead at z -5.8 to the rear at z 4.6: 10.4 m. Its
  centre line is x -1.09, putting the viewer's own seat at the origin. Five tall rounded windows a side, their middles
  at z -3.4, -1.65, 0.10, 1.85 and 3.60, each 1.1 m wide and 1.88 m high, the sill 0.92 m up, corners of 0.16 m, wall
  thickness 0.14 m. A walnut dado to 0.92 m, ribs 0.16 m wide and 0.055 m deep, a cornice 0.16 m high, warm wall lamps
  2.35 m up between the windows (`lamp_size` 1.8), a walnut rear door with its glowing pane (`door_glow` 0.25).
  Warm cream plaster walls and ceiling, walnut dado and bulkheads, brass ribs and frames, deep teal carpet with rising
  sunbursts (`deco_carpet`), claret velvet club armchairs on walnut frames. An exterior teak promenade deck ledge 1.45 m
  wide outside each wall at y -0.04. The picture is 4.1 m wide and 2.30625 m high, its bottom 1.15 m up, centred at
  [-1.09, 2.303125, -5.77] on the front bulkhead.
- **The seats:** five rows of four `club` armchairs (two rows ahead of the viewer's, two behind), two either side of a
  1.2 m aisle. Rows 1.35 m apart, seats 0.98 m apart; the viewer sits in the right block by the aisle (`own_side` right,
  `own_index` 0). There are 20 seat transforms, one at the origin.
- **The Art Deco fittings** (`kit`, id `fittings`): rising-sun carpet (`deco_carpet`), a stepped walnut, brass, chrome
  and cove-lit screen surround with a low dais and two 3-tier opal-glass torchières (`liner_proscenium`), walnut-and-brass
  pelmet boxes above the windows (`liner_pelmet`), a working sunburst bulkhead clock above the aft door (`liner_clock`),
  and teak-and-brass exterior promenade deck railings (`deck_rail`).
- **The swaying drapes** (`kit` ids `drapes_left` and `drapes_right`, driven by `motion` ids `sway_left` and
  `sway_right`): ten floor-length pleated claret velvet curtain panels with weighted gold hems along each window wall
  (`liner_drape`), tucked inside the fixed pelmets at y 2.91. Both sides sway together about the ship's fore-aft Z axis
  with a slow 9.5 s ocean swell period: 2.0 degrees at sea, settling to 0.25 degrees in harbour (`journey.speed`).
- **The light** (`light`): warm lamps `[1.0, 0.82, 0.56]`, spill 0.5, baked fill 0.12, warm cream above and dark walnut
  below.
- **The sky** (`sky`): latitude 46, day 205, heading 270 degrees (due west), 20:30 at departure; sunset afterglow at
  285 degrees, evening star, Milky Way (0.65, detail 0.6), light clouds (0.16), meteors (4), and a near-full Moon
  (phase 0.94, size 1.8) at bearing 198 degrees, altitude 10.5 degrees: framed cleanly through the port window from the
  viewer's seat with its glittering road on the Atlantic beneath it.
- **The sea** (`passing`, id `sea`): forward at 3.5 m/s, glow 0.45 in `#ffcb8e` reaching 16 m out and 6 m ahead and
  astern, mist `#2e394a`, screen spill 0.25.

### The sea's cross-section

Metres from the way's line; heights are over the lounge's floor (the eyes are at 1.2 m, roughly 6.7 m above the
waterline at -5.5 m).

| Side | From | To | What |
|---|---|---|---|
| both | 0.0 | 175.0 | `sea` ground disc out to the 185 m horizon skirt at -5.5 m |
| both | 28.0 | 52.0 | channel buoys, 8 on a 340 m loop, red or green with a light, feet at -5.5; present near departure (0..0.11) and arrival (0.87..1.0) |
| right | 75.0 | 135.0 | starboard harbour lights, 110 on a 320 m loop, seeming 5 times further, feet at -3.5; present near departure (0..0.16) and arrival (0.8..1.0) |
| left | 95.0 | 150.0 | port harbour lights, 75 on a 320 m loop, seeming 6 times further, feet at -3.5; present near departure (0..0.14) and arrival (0.83..1.0) |

### Along the route

| Place | What | Side |
|---|---|---|
| 0.0 | departure pier, 15 m off, waterline at -5.5 | right |
| 0.0, 22 m ahead | moored liner in harbour, 78 m off, waterline at -5.5, seed 2 | left |
| 0.0, 115 m ahead | breakwater lighthouse, 46 m off, waterline at -5.5 | right |
| 0.48 | sister ocean liner passing in mid-Atlantic, 92 m off, waterline at -5.5, seed 7 | left |
| 1.0, 120 m before | arrival breakwater lighthouse, 48 m off, waterline at -5.5 | left |
| 1.0, 20 m before | moored liner in arrival harbour, 74 m off, waterline at -5.5, seed 11 | left |
| 1.0 | arrival pier, 15 m off, waterline at -5.5 | right |

Departure and arrival are set out in metres (`ahead`), so the berth, harbour ship and breakwater lighthouse stand in the
same places for a film of any length.

## The film's evening

- **Tracks** (by `film.progress`): `sky.dusk` from 0.12 to 0.78 at 0.3 and full night at 0.58 (smoothed 0.5 s);
  `sky.hour` from 20.5 to 23.5 over the film (1 s); `sea.mist` from 0.08 down to 0.02 in mid-ocean and rising to
  0.22/0.18 in the arrival harbour (0.5 s). The timeline has an 8 s start and 6 minutes of credits.
- **Cues:** `dim` as the film starts: house lamps to 0.1, door glow to 0.08, sea glow to 0.25 over 5 s; `departure_horn`
  when `starting` (requires the pre-show ritual setting): sounds the deep twin-tone steam whistle (`horn.play`);
  `lights_up` in the pre-show and at the end: house lamps to 1.0, door glow and sea glow released over 4 s;
  `arrival_horn` once `journey.progress` passes 0.92 for 2 s (7200 s cooldown): sounds the harbour whistle on approach.
- **Room setting:** `cove` (`Cove lights`: Champagne, Rose, Jade, Silver blue; default Champagne) sets the proscenium
  coves' colour before the film; while the film plays, the coves soften toward `film.colour` (`cove_film` 0.85).

## Comfort

Measured by `test_room_liner_1936.gd` at the fastest the journey goes: 3.5 m/s x (1 + `CATCH_UP`) = 4.02 m/s, slowed by
`seems`. The limits are 3 m and 20 degrees a second (`docs/environments/checks.md`).

| What | Side | Its foot | Nearest | Degrees a second |
|---|---|---|---|---|
| band 0, buoy | both | 28.0 | 27.44 m | 8.4 |
| band 1, lights (seems 5) | right | 75.0 | 75.00 m | 0.6 |
| band 2, lights (seems 6) | left | 95.0 | 95.00 m | 0.4 |
| landmark 0, pier | right | 15.0 | 15.00 m | 15.4 |
| landmark 1, ship | left | 78.0 | 70.80 m | 3.3 |
| landmark 2, lighthouse | right | 46.0 | 42.40 m | 5.4 |
| landmark 3, ship | left | 92.0 | 84.80 m | 2.7 |
| landmark 4, lighthouse | left | 48.0 | 44.40 m | 5.2 |
| landmark 5, ship | left | 74.0 | 66.80 m | 3.5 |
| landmark 6, pier | right | 15.0 | 15.00 m | 15.4 |

The test also checks that nothing goes by within `FLOW_CLEAR_DEG` of the picture from the seat (`flow_clear()`), that
the hull and floor never tilt or roll, and that the drapes' sway scales with the common `motion` setting.

## Sound

- `acoustics` `cinema` for the room's beds. The document's film acoustics: reflect [0.38, 0.38, 0.18, 0.42, 0.32, 0.35],
  rt60 0.85 s, wet 0.48, late 1.4.
- `sound_bed` `turbines` (`deep_hum`) below the aft deck at [-1.09, -2.5, 5.0], `reach` 7, `gain_db` -2, `film_db` -10.
  Its `level` follows `journey.speed` from 0.35 to 1.0, smoothed 2 s: low idling in berth, full under way.
- `sound_bed` `sea_wash` (`water_lap`) everywhere, `gain_db` -3, `film_db` -10, `pitch` 0.78 (deeper ocean wash).
- `sound_bed` `creak` (`hull_creak`) at [5.5, 0.5, 2.0], `reach` 8, `every` 210 s, `gain_db` -6, `film_db` -14.
- `sound_bed` `horn` (`ship_horn`) high forward on the funnel at [-1.09, 12.0, -14.0], `reach` 20, `gain_db` -4,
  `film_db` -12; played by the `departure_horn` and `arrival_horn` cues.
- Measured: -54.3 dBFS RMS in the pre-show (peak -37.7) and -72.8 dBFS under a film at the reference level (target -38.0).

## Measured

30 draws, 25074 triangles, 0 lights, 9.2 MB of textures, atlas 236x256 (`test_room_liner_1936`, lavapipe, 2026-11-22).

## Not done yet

On the headset: not run.
