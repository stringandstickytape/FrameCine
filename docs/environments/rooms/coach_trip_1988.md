# Coach trip 1988

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

`app/environments/coach_trip_1988.env.json` (Journeys, Road, built by **Gemini 4 Neon Extra High**), tested by
`app/tests/test_room_coach_trip_1988.gd`. The eleventh of the Journeys: a 1988 overnight express touring coach cruising a
sodium-lit autumn motorway at night. Deep-pile swirly `moquette_88` carpet lines the cabin; a heavy pleated burgundy
driver's curtain hangs drawn behind the cab; an overhead ceiling-mounted 4:3 CRT television hangs above the centre aisle
beside a top-shelf video recorder flashing `12:00` and a stack of rented video tape cases. Mid-film, the coach makes a
warm-lit intermission stop beside glowing motorway services before rolling on into the night. The journey is as long as
the film (`docs/environments/passing.md`).

## The parts

- **The coach cabin** (`cabin`, id `coach`; `docs/environments/cabin.md`): 2.55 m wide at the floor, side walls 2.15 m
  high leaning inwards 4.5 degrees, under an arched cream roof rising 0.22 m (2.37 m at the crown), running from the
  forward cab bulkhead at z -4.8 to the rear vestibule at z 3.4 (8.2 m long, centre line at x -0.45 so the viewer sits in
  the right-hand inner aisle seat at the origin). Five wide touring windows a side (`bay_pitch` 1.36, 1.28 x 0.94 m, sill
  0.92 m, corner radius 0.12 m, `window_glass` false so `weather.panes` draws the wind-drifting rain panes in one draw),
  brown corduroy dado to 0.92 m, cream painted upper walls and ceiling, dark steel window frames and ribs, walnut rear
  vestibule door with warm transom glow. Five rows of four seats (two left, two right, 0.44 m centre aisle, 1.2 m row
  pitch, 0.46 m seat pitch; viewer in `own_side` right, `own_index` 0). The overhead 4:3 CRT screen is 0.88 m wide and
  0.66 m high, centred at [-0.45, 1.93, -3.95] (`screen_frame` false).
- **The seats** (`seats`, model `recliner`, `from_builders` true): 20 reclining touring-coach seats in warm chestnut-rust
  `woven_upholstery` with dark `brown_leather` shells; the viewer's own seat at the origin folds away cleanly.
- **The 1988 touring coach fittings** (`kit`, id `fittings`; `kit/coach_trip_1988.gd`):
  - `carpet` (`moquette_88`): 1988 swirly burgundy, ochre and retro-teal moquette touring carpet.
  - `coach_1988_cabin`:
    - Heavy pleated burgundy cab curtain drawn tightly behind the driver's compartment, hiding the cab cleanly.
    - Ceiling-mounted 4:3 dark-grey CRT television casing on bolted steel drop brackets above the front aisle, and a
      matching top-shelf video recorder flashing `12:00` (`PieceDisplay`) beside stacked colourful rental video tape cases
      and moulded front grab rails.
    - Continuous left and right overhead luggage parcel racks with walnut trim, padded brown bumper lips, chrome grab
      rails, per-row passenger service units (eyeball air vents and recessed reading lamps), warm-white fluorescent
      ceiling diffuser troughs (`PieceLamps`, `bake_lamps` 3), and low night-travel aisle & rack courtesy strips
      (`PieceCove`, `cove_floor` 0.5).
    - Cream pleated side-window curtains gathered cleanly with chocolate-brown tiebacks at the pillars, two glass-fronted
      signal-red break-glass emergency hammer boxes (`PieceGlass`), and floor perimeter heater convector ducts.
    - Aft WC/vestibule bulkhead with stainless kick-plate and push-bar, backlit green geometric EXIT placard
      (`PieceWindows`), working 1988 quartz bulkhead clock (`PieceClock`), geometric safety pictogram plaque and chrome
      coat hooks.
  - `coach_1988_rows`: moulded brown coach armrests with chrome flip-lid ashtrays and recline push buttons, curved woven
    cream-linen headrest antimacassars with stitched terracotta hem bands, full-height inner shell closures behind each
    recliner, fold-down cream laminate seatback tray tables with turn latches, and lower criss-cross net magazine pockets
    tucked with folded route leaflets.
- **The presentation** (`presentation`): 1988 rental video tape on the overhead 4:3 CRT (`rewinder_1987` + `tape` by
  default, `starts_off` true), switching on cleanly with the film and live-bound to `Tape wear` and `Coach speaker`
  (`telly` mono speaker or full spatial cinema).
- **The weather** (`weather`): `mode` bound to `Motorway weather` (`Light drizzle` / `Steady rain` / `Clear night`), 750
  outside falling raindrops in two areas strictly clear of the coach body (`x <= -2.55` and `x >= 1.65`, aft wind
  `[0.0, 2.8]`), and 10 merged side-window `panes` with `pane_drift` bound to `journey.speed` (`0.0..1.55`, smoothed 2 s).
- **The light** (`light`): warm fluorescent interior `[1.0, 0.92, 0.78]`, spill 0.44, baked fill 0.17.
- **The sky** (`sky`): latitude 52.5, day 302, facing 345 degrees, 21:36 into near midnight, autumn broken clouds (`clouds`
  0.35) lit warmly from below by motorway sodium skyglow (`cloud_glow` `#ff8c38`, `cloud_glow_level` 0.35), crescent Moon
  (`moon` 0.72, `moon_phase` 0.26).
- **The motorway** (`passing`, id `motorway`): forward at 6.0 m/s, wet dark `asphalt` carriageway (`0..16 m`) and autumn
  verge `grass` (`16..175 m`) at -1.35 m, distant sodium `highway_lamp` columns, illuminated motorway direction `gantry`
  signs, verge `tree` lines, distant town `lights`, dark horizon `ridge` hills, and floodlit motorway `services` at
  departure (`0.0`), both sides at the mid-film intermission (`0.5`), and arrival (`1.0`).

## The motorway's night and intermission stop

- **Tracks** (by `film.progress`): `sky.dusk` from 0.94 to 1.0 by 0.20 (0.5 s); `sky.hour` from 21.6 to 23.8 across the
  film (1 s); `motorway.mist` shifting gently between 0.12 and 0.24 (0.5 s).
- **Cues:**
  - `dim` when `starting` or `playing`: house lamps to 0.10, rear door glow to 0.10, motorway glow to 0.22 over 4 s
    (overhead and aisle night strips stay softly glowing via `cove_floor` 0.5).
  - `departure` when `starting` (requires the pre-show ritual setting): `presentation.switch_on` and `vcr.play`.
  - `intermission_stop` when `intermission`: house lamps gently up to 0.55, rear door glow to 0.45, motorway glow to 0.55
    over 3.5 s while the coach pauses beside the lit motorway services at `0.5`.
  - `lights_up` in the pre-show and at the end: house lamps to 1.0, door and motorway glow released over 4 s, and
    `presentation.switch_off`.
- **Room settings:**
  - `picture` (`Tape wear`: 1988 rental tape, 1988 CRT, Clean picture; default 1988 rental tape).
  - `speaker` (`Coach speaker`: on/off; default off — routes film sound through the overhead telly's small mono speaker).
  - `night_strips` (`Night strips`: Warm amber, Retro teal, Off; default Warm amber).
  - `weather` (`Motorway weather`: Light drizzle, Steady rain, Clear night; default Light drizzle).

## Comfort

Measured by `test_room_coach_trip_1988.gd` at the fastest the journey goes: 6.0 m/s x (1 + `CATCH_UP`) = 6.90 m/s, slowed
by `seems`. Limits: 3 m and 20 degrees a second (`docs/environments/checks.md`).

| What | Side | Nearest | Degrees a second |
|---|---|---|---|
| band 0, highway_lamp | both | 22.79 m | 16.5 |
| band 1, gantry | both | 22.72 m | 15.1 |
| band 2, tree | both | 26.90 m | 10.5 |
| band 3, lights | both | 85.00 m | 0.8 |
| band 4, ridge | both | 145.00 m | 0.3 |
| landmark 0, services (0.0) | right | 22.50 m | 17.6 |
| landmark 1, services (0.5) | right | 22.50 m | 17.6 |
| landmark 2, services (0.5) | left | 22.50 m | 17.6 |
| landmark 3, services (1.0) | right | 22.50 m | 17.6 |

## Sound

- `acoustics` `vehicle` (`rt60` 0.32, `wet` 0.12) for the room's beds. Document film acoustics: reflect
  [0.36, 0.36, 0.16, 0.34, 0.32, 0.32], rt60 0.28 s, wet 0.22, late 0.85.
- `sound_bed` `engines` (`coach_diesel`) astern at [-0.45, -0.6, 3.2], `reach` 6, `gain_db` -2, `film_db` -10; `level`
  follows `journey.speed` from 0.32 to 1.0, smoothed 2 s.
- `sound_bed` `vcr` (`vcr`) at the forward video shelf [-0.45, 1.4, -4.02], `reach` 5, `gain_db` -2; plays on departure.
- `sound_bed` `whine` (`tube_whine`) at the overhead CRT [-0.45, 1.93, -3.95], `reach` 4, `gain_db` -5, `film_db` -8;
  follows `setting.picture` (`tape`/`crt` 0.6, `clean` 0.0).
- `sound_bed` `rain` (`rain_glass`) around the side windows at [-0.45, 1.4, 0.0], `radius` 2, `reach` 4, `gain_db` -3,
  `film_db` -10; follows `weather.rain`, smoothed 2 s.
- `sound_bed` `wind` (`wind`) around the roof at [-0.45, 1.5, 0.0], `radius` 3, `reach` 5, `gain_db` -5, `film_db` -10,
  `pitch` 1.15; follows `journey.speed` from 0.15 to 0.85, smoothed 2.5 s.
- Measured by `test_room_coach_trip_1988.gd`: pre-show -51.0 dBFS RMS (peak -28.7), under a film at the reference -66.8
  dBFS RMS (`test_room_acoustics.gd`: C80 50.2 dB, reverb/direct -27.8 dB, T20 0.22 s, alpha 0.31).

## Measured

By `test_room_coach_trip_1988.gd` under Vulkan Forward Mobile (`lavapipe`, `60 checks, all passed`):

- Draws: 34 (limit 38).
- Triangles: 54,514 (limit 120,000).
- Live lights: 0.
- Particles: 750.
- Textures: 9.2 MB, lightmap atlas 224 x 212.

## Not done yet

On the headset: not run.
