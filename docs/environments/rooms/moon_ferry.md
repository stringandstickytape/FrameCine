# Moon ferry

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

`app/environments/moon_ferry.env.json` (Journeys, built by **Gemini 4 Neon Extra High**), tested by
`app/tests/test_room_moon_ferry.gd`. A classic retro-futuristic cislunar passenger liner gliding silently through black
star-filled space from an orbital transfer dock to the Moon Crater base. Twelve vermilion-crimson space-age lounge
recliners sit inside an ivory-composite and brushed-titanium arched cabin beneath a panoramic glazed roof canopy;
recessed orbital cove valances, forward flight-status telemetry displays, tubular zero-G handrail loops, a circular
pressure airlock hatch, a mission chronometer and an aft cislunar trajectory console dress the lounge. Departing from
an orbital transfer station with a glowing Earth filling the port viewports, the crossing shrinks Earth astern while
growing the procedural cratered Moon ahead across the starboard glass, culminating in a gentle powered descent onto the
lunar regolith plain beside the illuminated geodesic domes of the Crater base. The journey is as long as the film
(`docs/environments/passing.md`).

## The parts

- **The cislunar cabin** (`cabin`, id `ferry`; `docs/environments/cabin.md`): 4.4 m wide at the floor, side walls 2.25 m
  high leaning inward at 6 degrees, and an arched roof rising 0.62 m more (2.87 m at the crown) with `glazed_roof` true,
  replacing the opaque ceiling with curved overhead glass in `Glass` and longitudinal brushed-titanium dome purlins. From
  the front bulkhead at z -4.2 to the rear bulkhead at z 3.4: 7.6 m. Its centre line is x -0.82, putting the viewer's own
  seat at the origin. Four wide rounded-corner aerospace viewports a side (`window_from_z` -2.28, `bay_pitch` 1.56,
  middles at z -2.28, -0.72, 0.84 and 2.40), each 1.32 m wide and 1.15 m high, the sill 0.82 m up, corners of 0.24 m,
  wall thickness 0.15 m, brushed-titanium frames (`frame_width` 0.06, `frame_depth` 0.025) and `window_glass` true. An
  ivory composite dado to 0.82 m, brushed-titanium structural ribs 0.09 m wide and 0.032 m deep, a 0.05 m cornice, and no
  builder lamps or rear door. The picture is 1.84 m wide and 1.035 m high (16:9), its bottom 1.58 m up, stood 0.18 m off
  the front bulkhead (`screen_standoff` 0.18, `screen_frame` false), centred at `[-0.82, 2.0975, -4.02]`.
- **The seats** (`seats`, model `recliner`, `from_builders` true): three rows of four vermilion-crimson woven-upholstery
  space-age recliners in satin brushed-titanium shells (one row ahead of the viewer's, one behind), two either side of a
  0.90 m aisle. Rows 1.42 m apart, seats 0.74 m apart; the viewer sits in the right block by the aisle (`own_side` right,
  `own_index` 0), where the viewer's own recliner folds away while both shared armrests remain. There are 12 seat
  transforms, one at the origin, all with clear sight lines to the screen.
- **The cislunar liner fittings** (`kit`, id `fittings`, `bake_lamps` 2; `kit/moon_ferry.gd`):
  - `carpet` (`midcentury_weave`): deep aerospace charcoal-indigo woven grip carpet (`[0.18, 0.2, 0.25]`).
  - `moonferry_cabin`: swept ivory-composite forward flight-deck brow cowl (`1.78 m` deep at the crown easing smoothly to
    `2.24 m` at the haunches to shield the glazed arch from screen glare and keep forward peripheral flow clear) with a
    brushed-titanium arch lip and recessed live orbital cove valance (`PieceCove`, `cove_floor` 0.42); streamlined
    forward screen bulkhead with matte-obsidian picture mask bezel, brushed-titanium pin-frame, twin angled ivory cheek
    fairings, glowing ice-cyan geometric flight-status telemetry monitors (`PieceWindows`, pure orbital rings, attitude
    bars and velocity pips, zero text), lower life-support console with louvred intake bays, crimson trim stripe and a
    continuous tubular titanium zero-G handrail; leaning-wall brushed-titanium viewport sill ledges, floor thermal
    diffusers, cornice cove ribbons (`PieceCove`), chamfered brushed-titanium pier sconce pods (`PieceLamps`, house
    group, two middle-bay sconces registered for baking) and vertical zero-G tubular handrail loops with dark grip
    sleeves; aft circular pressure airlock hatch with bolted titanium collar ring, 8 radial clamp lugs, vermilion
    alignment tabs, domed ivory hatch leaf, circular manual locking wheel, glowing ice-cyan docking viewport
    (`PieceWindows`), circular cove halo, flanking zero-G grab-handles, and a working mission chronometer (`PieceClock`)
    with horizontal titanium wing-bars.
  - `moonferry_console`: sculpted ivory-composite and brushed-titanium shared recliner armrests (`Seats.RECLINER_ARM`,
    both kept around the viewer's folded seat) with dark padded arm-caps, personal control rocker pips, curved bullnose
    front fairings and low aisle floor-guide strips (`PieceCove`); solid contoured inner-shell cradle liners closing off
    the recliner back shells, contoured ivory headrest pads hugging `seats.gd`'s exact recliner curve (`bend` -0.35,
    `radius` 0.062) and tubular titanium zero-G seatback grab-handles; aft-port cislunar trajectory map console with
    glowing backlit display (`PieceWindows`) and 3D sculpted Earth-to-Moon free-return transit loop; and aft-starboard
    zero-G cabin service credenza with titanium retaining gallery rails and twin lathed thermal beverage carafes.
- **The light** (`light`): warm orbital cabin lamps `[1.0, 0.9, 0.74]`, spill 0.42, baked fill 0.14, fill top
  `[0.54, 0.56, 0.62]`, fill bottom `[0.16, 0.17, 0.2]`.
- **The sky** (`sky`): `mode` `space`, `all_sky` true (360-degree starfield and Milky Way above and below the horizon),
  latitude -26.0, day 200, hour 21.2 to 23.0, facing 180 degrees, 4000 faint stars, full Milky Way detail (`milky_detail`
  1.0, `#ece6db`, default brightness 0.78). Earth (`earth` true, `earth_detail` true, `earth_lights` 1.1, `earth_turn`
  4.0, `earth_phase` 0.78, `earth_light_angle` -35.0) sits out the port-aft viewports at bearing 74 degrees and shrinks
  over the film from `28.0` degrees down to `2.2` degrees while rising from `6.5` to `11.0` degrees altitude above the
  lunar crater rim. The procedural cratered Moon (`moon` 1.0, `moon_phase` 0.90, `glow_bearing` 318 degrees) sits out the
  forward-starboard viewports at bearing 238 degrees, growing from `2.4` degrees to `34.0` degrees by 76% of the film as
  its altitude lowers from `14.0` to `6.0` degrees, then smoothly dips beneath the emerging lunar horizon (`-24.0`
  degrees, fading out between 77% and 87%) as the ferry descends onto the lunar surface.
- **The cislunar crossing** (`passing`, id `cislunar`): forward at 3.6 m/s, `sky_light` false (crisp orbital and lunar
  sunlight `#72767e` at `light` 1.85 so the transfer station, regolith plain and Crater base catch direct sunlight under
  the black `space` sky), glow 0.35 in `#ffe2b8` reaching 10 m out and 4.2 m ahead and astern, dark-space horizon fade
  (`mist` 0.88, `mist_colour` `#050608`), screen spill 0.2, `ground_vis` starting at 0.0 during deep cislunar coast.

### The cislunar cross-section

Metres from the flight path; heights are over the cabin's floor (the eyes are at 1.2 m).

| Side | From | To | What |
|---|---|---|---|
| both | 0.0 | 175.0 | lunar `regolith` plain (`#686662`), -4.5 to -3.2 m; hidden in deep space (`ground_vis` 0.0 until 0.76), emerging smoothly to 1.0 by 0.88 on final lunar descent |
| both | 28.0 | 52.0 | sparse orbital `tether_ring` navigation relay buoys, 10 on a 340 m loop, seeming 1.5 times further, feet at -1.5; active near Earth-orbit departure (`0.0` at 0.8, gone by `0.12`) |
| both | 156.0 | 156.0 | crater-rim `ridge` skyline on a 336 m loop, seeming 8 times further, feet at -4.5, size 0.72; hidden in deep space, rising from 0.78 to 1.0 by 0.88 |

### Along the route

| Place | What | Side |
|---|---|---|
| 0.0, 10 m ahead | Earth-orbit departure `orbital_station` transfer dock, 30 m off, feet at -7.5 | right |
| 1.0, 6 m ahead | Moon Crater arrival `lunar_base` geodesic domes, comms mast & pad strobes, 24 m off, feet at -4.5 | right |

## The crossing's voyage

- **Tracks** (by `film.progress`): `sky.earth_size` shrinking from `28.0` to `13.0` (0.35), `5.0` (0.70) and `2.2`
  degrees (1.0, smooth 1.2 s); `sky.earth_altitude` rising from `6.5` to `11.0` degrees (1.2 s); `sky.moon_size` growing
  from `2.4` to `12.5` (0.38), `26.0` (0.64) and `34.0` degrees (0.76..1.0, 1.2 s); `sky.moon_altitude` lowering from
  `14.0` to `6.0` degrees by 0.76 and dipping beneath the lunar horizon to `-24.0` by 0.88 (1.2 s); `sky.moon` easing
  from `1.0` to `0.0` across 0.77..0.87 (1.5 s); `sky.hour` drifting from `21.2` to `23.0` (1.5 s); and
  `cislunar.ground_vis` rising from `0.0` to `1.0` across 0.76..0.88 (1.2 s). The timeline has an 8 s start and 6 minutes
  of credits.
- **Cues:**
  - `dim` when `starting`: house lamps to 0.08, cislunar cabin glow to 0.15 over 5 s (orbital coves and aisle guides
    stay softly glowing via `cove_floor` 0.42).
  - `departure` when `starting` (requires the pre-show ritual setting): sounds the orbital boarding chime (`chime.play`),
    waits 1.4 s, and fires a gentle trans-lunar injection thruster pulse (`thruster.play`).
  - `lights_up` in the pre-show and at the end: house lamps to 1.0 and cislunar glow released over 4 s.
  - `descent_burn` once `journey.progress` passes 0.88 for 1.5 s (7200 s cooldown): sounds a gentle lunar descent
    retro-burn pulse (`thruster.play`).
  - `touchdown_chime` once `journey.progress` passes 0.95 for 1.5 s (7200 s cooldown): sounds the arrival cabin chime at
    the Moon Crater base (`chime.play`).
- **Room settings:**
  - `cabin_light` (`Cabin light`: Warm amber, Ice blue, Off; default Warm amber — tints the brow valance, picture coves,
    side cornice ribbons, airlock halo and aisle floor-guide strips).
  - `starlight` (`Starlight`: Deep Milky Way, Quiet stars, Constellations; default Deep Milky Way — controls
    `sky.milky_way` and `sky.lines` live).

## Comfort

Measured by `test_room_moon_ferry.gd` at the fastest the journey goes: 3.6 m/s x (1 + `CATCH_UP`) = 4.14 m/s, slowed by
`seems`. The limits are 3 m and 20 degrees a second (`docs/environments/checks.md`).

| What | Side | Its foot | Nearest | Degrees a second |
|---|---|---|---|---|
| band 0, tether_ring (seems 1.5) | both | 28.0 | 24.88 m | 6.4 |
| band 1, ridge (seems 8.0) | both | 156.0 | 156.00 m | 0.2 |
| landmark 0, orbital_station | right | 30.0 | 16.00 m | 14.8 |
| landmark 1, lunar_base | right | 24.0 | 24.00 m | 9.9 |

The test also checks that nothing goes by within `FLOW_CLEAR_DEG` of the picture from the seat (`flow_clear()`), that
the glazed canopy and viewport glass stay well under the blend-layer budget, and that the cabin never rolls or tilts.

## Sound

- `acoustics` `vacuum` for the quiet cislunar crossing's room beds. The document's film acoustics: reflect
  `[0.44, 0.44, 0.18, 0.52, 0.38, 0.38]`, `rt60` 0.34 s, `wet` 0.22, `late` 0.85 (`C80` 46.2 dB, reverb/direct -26.6 dB,
  `T20` 0.26 s, `alpha` 0.33).
- `sound_bed` `life_support` (`hum`) around the upper cabin at `[-0.82, 2.2, 0.0]`, `radius` 2.8, `reach` 6,
  `gain_db` -5, `film_db` -12, `level` 0.75 (quiet cabin air circulation).
- `sound_bed` `drive` (`climber_hum`) aft beneath the deck at `[-0.82, -0.5, 2.8]`, `reach` 6, `pitch` 0.85,
  `gain_db` -8, `film_db` -12; `level` follows `journey.speed` from 0.25 to 1.0, smoothed 2.0 s.
- `sound_bed` `thruster` (`rumble`) aft at `[-0.82, 0.3, 3.2]`, `reach` 8, `pitch` 0.78, `gain_db` -4, `film_db` -10;
  played on departure and lunar descent braking burn.
- `sound_bed` `chime` (`cabin_chime`) forward overhead at `[-0.82, 2.45, -2.6]`, `reach` 8, `pitch` 1.08, `gain_db` -3,
  `film_db` -10; played on departure and lunar touchdown.
- Measured: -51.0 dBFS RMS in the pre-show (peak -38.2) and -78.9 dBFS under a film at the reference level (target
  -38.0).

## Measured

24 draws (23 in deep space with the lunar regolith hidden), 31922 triangles, 0 lights, 0 particles, 6.8 MB of textures,
atlas 196x188 (`test_room_moon_ferry`, lavapipe, 2026-11-24).

## Not done yet

On the headset: not run.
