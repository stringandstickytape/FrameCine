# Mars train

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

`app/environments/mars_train.env.json` (Journeys, built by **Gemini 4 Neon Extra High**), tested by
`app/tests/test_room_mars_train.gd`. A rugged, warm-lit pressurised Martian rover-train rolling across a vast
rust-ochre plain under the real haunting blue Martian sunset. Twelve warm terracotta-and-slate technical expedition
recliners sit inside an inward-canting aerospace pressure hull floored in sintered hexagonal pavers; heavy chamfered
aluminium ring-frames with bolted rib flanges, overhead pressurised oxygen and thermal conduits, glowing telemetry
status consoles, aft geological sample canisters, a topographic Martian traverse map, a circular pressure airlock
hatch framed in yellow-and-charcoal hazard striping, and a working Martian Sol chronometer dress the cabin. Departing
a Martian outpost as the small distant Sun sinks inside its authentic forward-scattered pale ice-blue dust halo,
whirling ochre dust devils subside with dusk and crystal-clear starlight and the Milky Way take the sky before
arrival at a glowing amber domed Martian night colony with the credits. The journey is as long as the film
(`docs/environments/passing.md`).

## The parts

- **The pressurised rover hull** (`cabin`, id `rover`; `docs/environments/cabin.md`): 3.8 m wide at the floor, side
  walls 2.35 m high leaning inward at 8.5 degrees (3.10 m across the top), and an arched pressure roof rising 0.42 m
  more (2.77 m at the crown). From the front bulkhead at z -4.4 to the rear airlock bulkhead at z 3.4: 7.8 m. Its
  centre line is x -0.72, placing the viewer's own seat at the origin. Four wide rounded pressure viewports a side
  (`window_from_z` -2.92, `bay_pitch` 1.52, middles at z -2.92, -1.40, 0.12 and 1.64), each 1.24 m wide and 0.96 m
  high, sill 0.88 m up, corner radius 0.18 m, thick 0.18 m triple-glazed wall reveals, brushed-steel frames
  (`frame_width` 0.065, `frame_depth` 0.025) and `window_glass` true. A dark-metal lower dado to 0.88 m, warm
  titanium-sand composite upper lining, brushed-aluminium structural ribs 0.09 m wide and 0.04 m deep, deep slate
  pressure bulkheads, and no builder lamps or rear door. The cinema screen is 1.68 m wide and 0.945 m high (16:9),
  bottom 1.56 m up, stood 0.16 m off the front bulkhead (`screen_standoff` 0.16, `screen_frame` false), centred at
  `[-0.72, 2.0325, -4.24]`.
- **The seats** (`seats`, model `recliner`, `from_builders` true): three rows of four warm Martian terracotta woven
  technical recliners on dark-metal frames (one row ahead of the viewer's, one behind), two either side of a 0.76 m
  aisle. Rows 1.35 m apart, seats 0.68 m apart; the viewer sits in the right block by the aisle (`own_side` right,
  `own_index` 0), where the viewer's own seat folds away while both shared armrests remain. There are 12 seat
  transforms, one at the origin, all with clear sight lines to the picture.
- **The Mars rover-train fittings** (`kit`, id `fittings`, `bake_lamps` 2; `kit/mars_train.gd`):
  - `carpet` (`hex_pavers`): industrial sintered hexagonal paver expedition floor (`[0.24, 0.22, 0.21]`).
  - `marstrain_cabin`: heavy chamfered aerospace-aluminium pressure ring-frames with machined inner flange caps,
    angled shoulder knee gussets, floor anchor shoes and hex bolt bosses at every structural bay mark; continuous
    brushed-aluminium pressure-window sill ledges, under-sill thermal convector louvres, perimeter viewport clamp
    lugs and vertical brushed-steel pier grab-bars; overhead longitudinal service raceways and clamped pressurised
    oxygen (teal-banded) and thermal-coolant (terracotta-banded) ceiling conduits flanking four recessed warm
    expedition LED ceiling troughs (`PieceLamps`, house group, two middle troughs registered for baking) and live
    indirect architectural cove ribbons segmented cleanly between the ring-frames beneath machined valance hoods
    (`PieceCove`, `cove_floor` 0.45); rugged forward cinema bulkhead with deep charcoal screen mask, chamfered
    titanium outer frame with corner gusset plates, lower instrumentation console, bracing hand-rail, twin backlit
    cyan/amber telemetry status displays (`PieceWindows` and `PieceLamps`) and overhead pressure-seal indicator
    header; aft side equipment lockers behind the rear windows — a starboard geological sample locker holding four
    illuminated glass-sleeved Martian regolith core canisters (`PieceGlass`) with yellow safety collars, and a port
    pressure-manifold cabinet crowned by a framed topographic Martian geology and traverse map plaque (pure geometry,
    zero text); and the iconic aft circular pressure airlock hatch framed by crisp bordered yellow-and-charcoal
    hazard striping, a heavy bolted aluminium coaming ring, central 4-spoke dogging wheel, glowing airlock
    pressure-green viewport and seal status bars (`PieceWindows`), vertical entry grab-bars, and a working Martian
    Sol chronometer (`PieceClock`) centered above the hatch.
  - `marstrain_rows`: faceted dark-slate and brushed-aluminium shared armrests (`Seats.RECLINER_ARM`, both kept around
    the viewer's folded seat; outboard armrests slimmed and tucked cleanly inside the 8.5 degree leaning hull) with
    forearm control bezels, comms pips and recline switches; tailored warm-sand woven technical headrest wraps hugging
    `seats.gd`'s exact recliner curve (`bend` -0.35, `radius` 0.062); solid slate inner seatback closures, rugged
    tubular brushed-aluminium seatback grab-bar handles and cargo stowage straps; and recessed low aisle deck-guide
    strips (`PieceCove`).
- **The light** (`light`): warm expedition LED lamps `[1.0, 0.86, 0.64]`, spill 0.44, baked fill 0.13, fill top
  `[0.48, 0.44, 0.42]`, fill bottom `[0.16, 0.14, 0.13]`.
- **The sky** (`sky`): southern Martian tropics (`latitude` -18.0, `day_of_year` 272.0, `facing` 190.0), western blue
  Martian sunset positioned squarely out the starboard pressure windows (`glow_bearing` 270.0), departing at `hour`
  20.4 (`dusk` 0.0, `afterglow` 0.9, `twilight_zenith` `#3d2219`, `twilight_horizon` `#b55c34`, blue forward-scattered
  halo `glow` `#78beff`, `belt_colour` `#7a3b2c`) with the small setting Sun disc (`sun_disc` 1.0, `sun_altitude` 7.5
  degrees). Over the first 28–34% of the film the Sun sinks below the Martian horizon (`sun_altitude` -3.0, `sun_disc`
  0.0) and `dusk` sweeps to 1.0 (`night_zenith` `#050712`, `night_horizon` `#1b141e`, `ground` `#24130d`), unveiling
  3000 faint stars and the full detailed Milky Way (`milky_way` 0.85 default, `milky_detail` 1.0, `#f2e7d8`) sweeping
  across the starboard pressure viewports.
- **The Martian plain** (`passing`, id `plain`): forward at 5.0 m/s, light 1.75, cabin glow 0.48 in `#ffcf96` reaching
  12 m out and 4.2 m ahead and astern, lit windows and beacons at 1.3, dusty Martian haze `mist` 0.14 in `#522b1e`
  clearing to 0.05 under starlight, screen spill 0.26.

### The Martian plain's cross-section

Metres from the rover trackway's line; heights are over the cabin floor (the eyes are at 1.2 m, roughly 3.4 m above
the Martian plain at -2.2 m).

| Side | From | To | What |
|---|---|---|---|
| both | 0.0 | 5.5 | dark basalt `stone` wheel-track verge (`#3a241c`), at -2.2 m |
| both | 5.5 | 175.0 | Martian iron-oxide rust `regolith` plain (`#7c3d24`), rising gently from -2.2 to -1.6 m |
| both | 23.0 | 54.0 | wind-carved basalt ventifact `mars_rock` boulders (`#5e2d1e`), 68 on a 320 m loop, feet at -2.2 |
| both | 26.0 | 34.0 | sparse mid-plain `tether_ring` telemetry relay pylons, 4 on a 340 m loop, seeming 1.5 times further, active mid-route (`0.08..0.92`) |
| both | 48.0 | 135.0 | tall ochre-rust `dust_devil` vortices (`#c47144`), 14 on a 340 m loop, seeming 4 times further, active during sunset and early dusk (`0.9` -> `0.7` -> `0.15` -> `0.0` as the surface cools) |
| both | 74.0 | 152.0 | distant colony and outpost `lights` (`#ffae62`), 96 on a 320 m loop, seeming 6 times further, concentrated near departure and arrival |
| both | 76.0 | 150.0 | far rust canyon `mesa` silhouettes (`#6e3220`), 24 on a 340 m loop, seeming 5 times further, feet at -2.0 |
| both | 162.0 | 162.0 | far crater-rim `ridge` skyline (`#381a14`) on a 336 m loop, seeming 10 times further, feet at -1.8 |

### Along the route

| Place | What | Side |
|---|---|---|
| 0.0 | departure pressurised domed Martian outpost (`mars_base`), 23.0 m off, size 0.92, ground at -2.2 | left |
| 0.0, 90 m ahead | departure trackway route `signal`, 21.0 m off, ground at -2.2 | left |
| 0.50 | mid-plain automated relay `signal`, 22.0 m off, ground at -2.2 | right |
| 1.0, 90 m before | arrival approach route `signal`, 21.0 m off, ground at -2.2 | right |
| 1.0 | arrival glowing domed Martian night colony (`mars_base`), 21.5 m off, size 1.05, ground at -2.2 | right |

## The crossing's evening

- **Tracks** (by `film.progress`): `sky.sun_altitude` from 7.5 degrees down to -3.0 by 0.28 (smoothed 0.6 s);
  `sky.sun_disc` from 1.0 down to 0.0 by 0.28 (0.6 s); `sky.dusk` from 0.0 to 1.0 by 0.34 (0.6 s); `sky.hour` from
  20.4 to 23.4 over the film (1.0 s); `plain.mist` settling from 0.14 dusty sunset haze to 0.05 under clear Martian
  night, then 0.08 into the colony (0.6 s). The timeline has an 8 s start and 6 minutes of credits.
- **Cues:**
  - `dim` when `starting`: house lamps to 0.08, plain car glow to 0.16 over 5 s (expedition coves and aisle guides
    stay softly glowing via `cove_floor` 0.45, while pressure-green airlock and telemetry panels hold steady).
  - `departure` when `starting` (requires the pre-show ritual setting): sounds the airlock departure chime
    (`chime.play`).
  - `lights_up` in the pre-show and at the end: house lamps to 1.0 and plain glow released over 4 s.
  - `arrival_chime` once `journey.progress` passes 0.93 for 2 s (7200 s cooldown): sounds the airlock chime on approach
    to the Martian night colony.
- **Room settings:**
  - `lighting` (`Cabin lighting`: Habitat amber, Telemetry teal, Off; default Habitat amber — tints the overhead
    raceway coves, upper wall graze strips, screen surround wash and aisle deck guides live).
  - `sky_mode` (`Martian sky`: Blue sunset to stars, Clear starlight, Constellations; default Blue sunset to stars —
    controls `sky.milky_way`, `sky.lines` and `sky.meteors` live).

## Comfort

Measured by `test_room_mars_train.gd` at the fastest the journey goes: 5.0 m/s x (1 + `CATCH_UP`) = 5.75 m/s, slowed
by `seems`. The limits are 3 m and 20 degrees a second (`docs/environments/checks.md`).

| What | Side | Its foot | Nearest | Degrees a second |
|---|---|---|---|---|
| band 0, dust_devil (seems 4.0) | both | 48.0 | 41.44 m | 2.0 |
| band 1, mars_rock (seems 1.0) | both | 23.0 | 19.50 m | 16.9 |
| band 2, tether_ring (seems 1.5) | both | 26.0 | 23.75 m | 9.2 |
| band 3, mesa (seems 5.0) | both | 76.0 | 53.25 m | 1.2 |
| band 4, ridge (seems 10.0) | both | 162.0 | 162.00 m | 0.2 |
| band 5, lights (seems 6.0) | both | 74.0 | 74.00 m | 0.7 |
| landmark 0, mars_base | left | 23.0 | 23.00 m | 14.3 |
| landmark 1, signal | left | 21.0 | 19.53 m | 16.9 |
| landmark 2, signal | right | 22.0 | 20.53 m | 16.0 |
| landmark 3, signal | right | 21.0 | 19.53 m | 16.9 |
| landmark 4, mars_base | right | 21.5 | 21.50 m | 15.3 |

The test also checks that nothing goes by within `FLOW_CLEAR_DEG` of the picture from the seat (`flow_clear()`), that
the triple-glazed pressure window glass and sample canister sleeves stay well under the blend-layer budget, and that
the rover cabin never rolls or sways.

## Sound

- `acoustics` `hull` (`rt60` 0.44, `damping` 0.52, `wet` 0.16) for the room's beds. The document's film acoustics:
  reflect `[0.48, 0.48, 0.22, 0.52, 0.42, 0.42]`, `rt60` 0.38 s, `wet` 0.28, `late` 1.00 (`C80` 40.5 dB, reverb/direct
  -22.3 dB, `T20` 0.29 s, `alpha` 0.28).
- `sound_bed` `drive` (`rover_drive`) beneath the deck at `[-0.72, -1.4, 0.4]`, `reach` 8, `gain_db` -1, `film_db`
  -10; `level` follows `journey.speed` from 0.0 to 1.0, smoothed 1.5 s.
- `sound_bed` `wind` (`wind`) around the upper pressure hull at `[-0.72, 2.2, 0.0]`, `radius` 3.4, `reach` 6, `pitch`
  1.18 (thin Martian atmosphere), `gain_db` -5, `film_db` -10; `level` follows `journey.speed` from 0.35 to 0.95,
  smoothed 2.0 s.
- `sound_bed` `chime` (`cabin_chime`) overhead forward at `[-0.72, 2.4, -2.8]`, `reach` 8, `gain_db` -2, `film_db`
  -10; played by `departure` and `arrival_chime`.
- Measured: -54.9 dBFS RMS in the pre-show (peak -40.0) and -67.2 dBFS under a film at the reference level (target
  -38.0).

## Measured

25 draws, 35232 triangles, 0 lights, 0 particles, 6.2 MB of textures, atlas 204x200 (`test_room_mars_train`,
lavapipe, 2026-11-24).

## Not done yet

On the headset: not run.
