# Dome car 1955

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

`app/environments/dome_car_1955.env.json` (Journeys, built by **Gemini 4 Neon Extra High**), tested by
`app/tests/test_room_dome_car_1955.gd`. A gleaming 1955 mid-century stainless-steel upper-deck observation dome car
crossing moonlit Southwest canyon country. Twelve desert-coral observation recliners with crisp curved cream headrest
antimacassars sit beneath a tall arched glass dome roof; brushed-chrome speed-bars, atomic saucer dome table lamps, an
illuminated aft stairwell balustrade, lacquered boomerang wall emblems and a chrome sunburst railway clock dress the
deck. Departing at desert twilight as terracotta sunset fades into ink-black night, the full Milky Way, a thin crescent
Moon and shooting stars arch overhead through the curved glass while saguaro cacti, stepped red-rock mesas and lit
wooden railway water towers glide past. The journey is as long as the film (`docs/environments/passing.md`).

## The parts

- **The observation dome** (`cabin`, id `dome`; `docs/environments/cabin.md`): 4.0 m wide, straight walls 1.95 m high,
  and an arched roof rising 0.95 m more (2.90 m at the crown) with `glazed_roof` true, replacing the opaque ceiling with
  curved overhead glass in `Glass` and longitudinal brushed-stainless dome purlins. From the front bulkhead at z -4.2 to
  the rear bulkhead at z 3.4: 7.6 m. Its centre line is x -0.785, putting the viewer's own seat at the origin. Five wide
  panoramic rounded windows a side (`window_from_z` -2.8, `bay_pitch` 1.36, middles at z -2.80, -1.44, -0.08, 1.28 and
  2.64), each 1.12 m wide and 1.06 m high, the sill 0.78 m up, corners of 0.16 m, wall thickness 0.12 m, brushed-steel
  frames (`frame_width` 0.055, `frame_depth` 0.02) and `window_glass` true. A deep desert-turquoise painted dado to
  0.78 m, brushed-stainless structural ribs 0.08 m wide and 0.03 m deep, a 0.06 m cornice, and no builder ceiling lamps
  or rear door. The picture is 1.88 m wide and 1.0575 m high (16:9), its bottom 1.58 m up, stood 0.16 m off the front
  bulkhead (`screen_standoff` 0.16, `screen_frame` false), centred at `[-0.785, 2.10875, -4.04]`.
- **The seats** (`seats`, model `recliner`, `from_builders` true): three rows of four desert-coral woven-upholstery
  observation recliners on satin brushed-steel frames (one row ahead of the viewer's, one behind), two either side of a
  0.85 m aisle. Rows 1.35 m apart, seats 0.72 m apart; the viewer sits in the right block by the aisle (`own_side`
  right, `own_index` 0), where the viewer's own recliner folds away while both shared armrests remain. There are 12 seat
  transforms, one at the origin, all with clear sight lines to the screen.
- **The 1955 dome car fittings** (`kit`, id `fittings`, `bake_lamps` 2; `kit/dome_car_1955.gd`):
  - `carpet` (`midcentury_weave`): mid-century deep-teal geometric woven carpet (`[0.18, 0.3, 0.33]`).
  - `dome_1955_lounge`: swept brushed-stainless forward dome brow cowl (`1.54 m` deep at the crown easing smoothly to
    `2.08 m` at the haunches to shield the glazed arch from screen glare and keep forward peripheral flow clear) with a
    polished chrome arch lip and recessed cove valance (`PieceCove`, `cove_floor` 0.45); streamlined forward screen
    bulkhead housing with turquoise enamel lower louvred air-conditioning console, charcoal screen mask bezel, chrome
    pin-frame, desert-coral accent strip and three horizontal chrome speed-bars sweeping out across both flanks;
    continuous brushed-chrome fluted window-sill shelf ledges with under-sill heater grilles and eight alternating
    desert-coral and turquoise mid-century atomic saucer dome table lamps (`PieceLamps`, house group, two middle-bay
    lamps registered for baking) tucked cleanly at the window piers; aft stainless-steel perimeter handrail and
    illuminated step-well balustrade with tinted safety-glass modesty panels (`PieceGlass`), ribbed stainless stair
    treads, angled descending handrails and glowing courtesy strips leading down to the lower car; rear bulkhead
    lower-deck stairwell portal arch with a warm vestibule transom bar, twin lacquered coral-and-turquoise boomerang
    decorative wall emblems with chrome four-point starburst pins (pure geometry, no text), and a working chrome
    sunburst 1955 railway bulkhead clock (`PieceClock`) ringed by 16 alternating radial spears tipped with coral and
    turquoise orbs.
  - `dome_1955_rows`: sculpted charcoal and brushed-chrome shared armrests (`Seats.RECLINER_ARM`, both kept around the
    viewer's folded seat) with curved chrome waterfall front bullnose bumpers, twin inlaid chrome side speed-stripes,
    recline buttons and flip-lid ash-receivers; crisp curved mid-century cream woven headrest antimacassars hugging
    `seats.gd`'s exact recliner headrest curve (`bend` -0.35, `radius` 0.062); tubular chrome rear seatback grab-bars;
    and low aisle floor-guide light strips (`PieceCove`).
- **The light** (`light`): warm incandescent dome lamps `[1.0, 0.84, 0.6]`, spill 0.42, baked fill 0.12, fill top
  `[0.46, 0.48, 0.54]`, fill bottom `[0.15, 0.16, 0.18]`.
- **The sky** (`sky`): Southwest latitude 35.0, summer day 205, facing 250 degrees, sunset glow bearing 292 degrees,
  departing at 20:36 (`hour` 20.6) in rich terracotta-purple desert twilight (`dusk` 0.2, `afterglow` 0.85,
  `evening_star` 0.9, twilight horizon `#e07a48`, glow `#ff7232`, Belt of Venus `#b55a74`), deepening over the first
  30% of the film into clear ink-black desert night (`dusk` 1.0, night zenith `#03050d`), revealing the full Milky Way
  overhead (`milky_way` 0.95 default, `milky_detail` 1.0, `#efe5d4`), 2800 faint stars, zero clouds, a thin crescent
  Moon (`moon` 0.72, phase 0.18, bearing 315 degrees, altitude 34 degrees, size 1.6), and `12.0` shooting stars a minute
  streaking across the curved dome glass.
- **The desert** (`passing`, id `desert`): forward at 5.4 m/s, glow 0.45 in `#ffd8a6` reaching 12 m out and 4.5 m ahead
  and astern, mist 0.07 in `#2c1d24` clearing to 0.03 under deep night, screen spill 0.28.

### The desert's cross-section

Metres from the track's line; heights are over the upper dome deck's floor (the eyes are at 1.2 m, roughly 3.8 m above
the desert floor at -2.6 m).

| Side | From | To | What |
|---|---|---|---|
| both | 0.0 | 4.5 | `stone` track ballast shoulder (`#2c2622`), -2.55 to -2.6 m |
| both | 4.5 | 175.0 | `sand` moonlit desert plain (`#524234`) out to 175 m at -2.6 m |
| both | 26.0 | 62.0 | silhouette saguaro `cactus` band, 72 on a 320 m loop, seeming 1.5 times further, feet at -2.6 |
| both | 68.0 | 152.0 | stepped red-rock `mesa` formations, 26 on a 340 m loop, seeming 4.5 times further, feet at -2.6 |
| both | 82.0 | 155.0 | distant desert highway and town `lights`, 90 on a 320 m loop, seeming 6 times further, feet at -2.0; busiest near stations (`0.0` and `1.0`), sparse mid-desert (`0.18`) |
| both | 162.0 | 162.0 | far canyon `ridge` skyline on a 336 m loop, seeming 9 times further, feet at -2.6 |

### Along the route

| Place | What | Side |
|---|---|---|
| 0.0 | departure desert `station`, 21 m off, ground at -2.6 | right |
| 0.0, 85 m ahead | departure trackside `signal`, 22 m off, ground at -2.6 | left |
| 0.35 | lit wooden railway `water_tower` siding, 25 m off, ground at -2.6 | left |
| 0.72 | lit wooden railway `water_tower` siding, 26 m off, ground at -2.6 | right |
| 1.0, 85 m before | approach trackside `signal`, 22 m off, ground at -2.6 | left |
| 1.0 | arrival desert `station`, 21 m off, ground at -2.6 | right |

Departure and arrival trackside signals are set out in metres (`ahead`), so the station approaches stay in proportion
for a film of any length.

## The crossing's evening

- **Tracks** (by `film.progress`): `sky.dusk` from 0.2 to 1.0 at 0.30 (smoothed 0.6 s); `sky.hour` from 20.6 to 23.6
  over the film (1.0 s); `desert.mist` clearing from 0.07 at twilight to 0.03 under deep desert stars, then 0.04 and
  0.06 into the arrival station (0.6 s). The timeline has an 8 s start and 6 minutes of credits.
- **Cues:**
  - `dim` when `starting`: house lamps to 0.10, desert car glow to 0.18 over 5 s (recessed dome coves and aisle guides
    stay softly glowing via `cove_floor` 0.45).
  - `departure` when `starting` (requires the pre-show ritual setting): sounds the distant diesel locomotive horn
    (`horn.play`).
  - `lights_up` in the pre-show and at the end: house lamps to 1.0 and desert car glow released over 4 s.
  - `arrival_horn` once `journey.progress` passes 0.93 for 2 s (7200 s cooldown): sounds the diesel horn on approach to
    the arrival station.
- **Room settings:**
  - `cove` (`Dome coves`: Turquoise, Desert coral, Warm chrome, Off; default Turquoise — tints the dome brow valance,
    screen coves, side cornice ribbons, stairwell coves and aisle floor-guide strips).
  - `starlight` (`Starlight`: Milky Way & meteors, Quiet stars, Constellations; default Milky Way & meteors — controls
    `sky.milky_way`, `sky.meteors` and `sky.lines` live).

## Comfort

Measured by `test_room_dome_car_1955.gd` at the fastest the journey goes: 5.4 m/s x (1 + `CATCH_UP`) = 6.21 m/s, slowed
by `seems`. The limits are 3 m and 20 degrees a second (`docs/environments/checks.md`).

| What | Side | Its foot | Nearest | Degrees a second |
|---|---|---|---|---|
| band 0, mesa (seems 4.5) | both | 68.0 | 44.38 m | 1.8 |
| band 1, ridge (seems 9.0) | both | 162.0 | 162.00 m | 0.2 |
| band 2, cactus (seems 1.5) | both | 26.0 | 24.20 m | 9.8 |
| band 3, lights (seems 6.0) | both | 82.0 | 82.00 m | 0.7 |
| landmark 0, station | right | 21.0 | 21.00 m | 16.9 |
| landmark 1, signal | left | 22.0 | 20.38 m | 17.5 |
| landmark 2, water_tower | left | 25.0 | 21.69 m | 16.4 |
| landmark 3, water_tower | right | 26.0 | 22.83 m | 15.6 |
| landmark 4, signal | left | 22.0 | 20.38 m | 17.5 |
| landmark 5, station | right | 21.0 | 21.00 m | 16.9 |

The test also checks that nothing goes by within `FLOW_CLEAR_DEG` of the picture from the seat (`flow_clear()`), that
the curved dome and window glass stays well under the blend-layer budget, and that the observation deck never rolls or
sways.

## Sound

- `acoustics` `small_room` (`rt60` 0.45, `damping` 0.55, `wet` 0.16) for the room's beds. The document's film acoustics:
  reflect `[0.5, 0.5, 0.2, 0.56, 0.44, 0.44]`, `rt60` 0.42 s, `wet` 0.30, `late` 1.05 (`C80` 38.8 dB, reverb/direct
  -22.1 dB, `T20` 0.32 s, `alpha` 0.26).
- `sound_bed` `rails` (`rail_joints`) beneath the deck at `[-0.785, -1.8, 0.5]`, `reach` 8, `pitch` 1.12 (brisk desert
  streamliner cadence), `gain_db` -1, `film_db` -10; `level` follows `journey.speed` from 0.0 to 1.0, smoothed 1.5 s.
- `sound_bed` `horn` (`diesel_horn`) far forward at the locomotive `[-0.785, 2.0, -28.0]`, `reach` 35, `gain_db` -3,
  `film_db` -12; played by `departure` and `arrival_horn`.
- `sound_bed` `crickets` (`crickets`) around the deck at `[-0.785, 0.4, 0.0]`, `radius` 4.2, `reach` 6, `gain_db` -4,
  `film_db` -12; `level` follows `journey.speed` inverted (`0.85` stopped at desert stations, `0.08` under way),
  smoothed 2.5 s.
- `sound_bed` `wind` (`wind`) high around the glass canopy at `[-0.785, 2.4, 0.0]`, `radius` 3.5, `reach` 6, `pitch`
  0.92, `gain_db` -5, `film_db` -10; `level` follows `journey.speed` from 0.35 to 0.95, smoothed 2.0 s.
- Measured: -56.0 dBFS RMS in the pre-show (peak -41.7) and -67.6 dBFS under a film at the reference level (target
  -38.0).

## Measured

24 draws, 32964 triangles, 0 lights, 0 particles, 6.2 MB of textures, atlas 196x188 (`test_room_dome_car_1955`,
lavapipe, 2026-11-23).

## Not done yet

On the headset: not run.
