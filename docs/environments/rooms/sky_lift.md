# Sky lift

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

`app/environments/sky_lift.env.json` (Journeys, built by **Gemini 4 Neon Extra High**), tested by
`app/tests/test_room_sky_lift.gd`. A near-future equatorial orbital elevator climber car ascending smoothly from an
equatorial ocean tether platform through the cloud deck into black star-filled orbit, with Earth's glowing curved limb
opening out beneath you by the credits. Eight pearl-white and brushed-titanium aerospace observation recliners sit in
two rows beneath outward-canted panoramic windows and a curved glazed roof canopy braced by open-lattice titanium
truss hoops; a floating dark-slate screen chassis with cyan telemetry edge bars anchors the front bulkhead, while an
aft circular pressurised docking airlock hatch, flanking orbital altitude and tether-tension telemetry desks, and a
working brushed-titanium mission chronometer dress the observation promenade. The vertical climb is as long as the
film (`docs/environments/passing.md`).

## The parts

- **The orbital climber cabin** (`cabin`, id `climber`; `docs/environments/cabin.md`): 4.8 m wide at the floor, side
  walls 2.35 m high canted outward at -6.0 degrees (`top_half` 2.647 m) for unobstructed downward planetary viewing,
  and an arched roof rising 0.78 m more (3.13 m at the crown) with `glazed_roof` true, replacing the opaque ceiling
  with curved overhead glass in `Glass` and longitudinal brushed-titanium purlins. From the front bulkhead at z -4.2
  to the rear bulkhead at z 3.4: 7.6 m. Its centre line is x -0.85, putting the viewer's own seat at the origin. Four
  wide panoramic rounded windows a side (`window_from_z` -3.14, `bay_pitch` 1.74, middles at z -3.14, -1.40, 0.34 and
  2.08), each 1.48 m wide and 1.45 m high, the sill 0.62 m up, corners of 0.14 m, wall thickness 0.14 m, brushed-steel
  frames (`frame_width` 0.055, `frame_depth` 0.02) and `window_glass` true. A deep aerospace slate lower hull dado to
  0.62 m, brushed-titanium structural ribs 0.09 m wide and 0.04 m deep, a 0.055 m cornice, and no builder ceiling
  lamps or rear door. The picture is 2.24 m wide and 1.26 m high (16:9), its bottom 1.50 m up, stood 0.22 m off the
  front bulkhead (`screen_standoff` 0.22, `screen_frame` false), centred at `[-0.85, 2.13, -3.98]`.
- **The seats** (`seats`, model `recliner`, `from_builders` true): two rows of four sculpted aerospace recliners in
  pearl-white woven upholstery (`[0.86, 0.89, 0.93]`) on satin brushed-titanium shells (`[0.38, 0.43, 0.50]`, one row
  ahead of the viewer's, none behind), two either side of a 0.96 m central aisle. Rows 1.42 m apart, seats 0.74 m
  apart; the viewer sits in the right block by the aisle (`own_side` right, `own_index` 0), where the viewer's own
  recliner folds away while both shared armrests remain. There are 8 seat transforms, one at the origin, all with
  clear sight lines to the screen.
- **The orbital climber fittings** (`kit`, id `fittings`, `bake_lamps` 2; `kit/sky_lift.gd`):
  - `carpet` (`hex_pavers`): sculpted deep-slate hexagonal composite aerospace deck flooring (`[0.24, 0.28, 0.34]`).
  - `skylift_cabin`: swept brushed-titanium and dark-slate forward canopy brow cowl (`1.42 m` deep at the crown
    sweeping back smoothly to `1.93 m` at the haunches to shield the glazed dome from screen spill and keep forward
    peripheral flow clear) with a polished titanium trailing lip and recessed live status cove valance (`PieceCove`,
    `cove_floor` 0.45); open-lattice curved overhead brushed-titanium observation truss hoops with diagonal struts
    and twin longitudinal tension spine rails beneath the glass dome; floating dark-slate screen chassis framed in
    brushed titanium with corner clamp collars, slim vertical cyan telemetry edge-status bars (`PieceWindows`),
    indirect bulkhead halo cove (`PieceCove`), horizontally ribbed low-glare dark-slate flanking acoustic bays with
    gold thermal-foil trim dashes, and a low cantilevered forward avionics deck with thermal louvre grilles; continuous
    outward-canted window-sill bolsters, tubular brushed-titanium perimeter safety hand-rails stanchioned strictly at
    the window piers, and recessed indirect under-sill cabin sconces (`PieceLamps`, house group, two middle-bay lamps
    registered for baking); two rows of sculpted pearl-white and deep-slate shared recliner armrests
    (`Seats.RECLINER_ARM`, both kept around the viewer's folded seat), contoured slate-blue headrest bolster cradles,
    tubular titanium rear seatback zero-g grab-bars with twin vertical spine trim ribs, and continuous backlit
    floor-level aisle pathway strips (`PieceCove`).
  - `skylift_console`: monumental aft circular pressurised docking airlock hatch with a 24-segment brushed-titanium
    collar ring, eight radially machined pressure-lock dog lugs, a central tri-spoke mechanical locking wheel, gold
    thermal-foil threshold accents, an upper circular pressurised viewport (`PieceGlass`) over a glowing cyan
    vestibule status ring (`PieceLamps`), flanking vertical airlock-seal telemetry bars (`PieceWindows`) and a soft
    circular collar halo (`PieceCove`); port and starboard cantilevered orbital altitude-ladder and tether-tension
    telemetry consoles with tilted multi-segment geometric bar-graph display panels (`PieceWindows`, zero text); a
    working circular brushed-titanium mission chronometer (`PieceClock`, live wall time) with 12 radial machined hour
    lugs, an outer orbital halo ring and a 12-o'clock gold thermal-foil pin centered high above the docking hatch;
    and aft tubular titanium observation deck guard-rails with tinted safety-glass modesty panels (`PieceGlass`).
- **The light** (`light`): cool pearl-white aerospace cabin lamps `[0.86, 0.94, 1.0]`, spill 0.42, baked fill 0.13,
  fill top `[0.46, 0.52, 0.62]`, fill bottom `[0.15, 0.17, 0.21]`.
- **The sky** (`sky`): equatorial latitude 0.0, summer day 205, facing 180 degrees, sun-glint bearing 248 degrees,
  starting at `hour` 22.0 in bright sunlit cobalt-cerulean equatorial daylight (`dusk` 0.0, `space_mix` 0.0,
  `afterglow` 0.0, zenith `#174eae`, horizon `#72b8ec`, glow `#ffe0ad`), darkening through upper-stratosphere indigo
  (`night_zenith` `#03071c`, `night_horizon` `#1646a0`) into velvet-black 360-degree orbit (`space_mix` 1.0,
  `all_sky` true) with 4000 faint stars and the full detailed Milky Way (`milky_way` 0.95 default, `milky_detail` 1.0,
  `#f0e8da`) wrapping all around and below. Live detailed Earth (`earth` true, `earth_detail` true, `earth_bearing`
  244.0 broadside out the starboard panoramic windows, `earth_phase` 0.74, `earth_light_angle` 28.0, `earth_lights`
  1.35, `earth_turn` 3.0, `earth_angle` 42.0) emerges cleanly once above the cloud deck (`earth_alpha` 0.0 to 1.0)
  and opens out from a 78-degree planetary limb at -38 degrees altitude to a sweeping 62-degree glowing blue curve at
  -22 degrees altitude by docking.
- **The vertical ascent** (`passing`, id `ascent`): `facing` `"up"` at a serene 2.7 m/s, crisp sunlit orbital
  illumination (`sky_light` false, `night` `#80aad6`, `light` 1.05), cabin glow 0.35 in `#b8e4ff` reaching 10 m out
  and 4 m fore/aft, atmospheric horizon mist 0.08 in `#62a8de` clearing to 0.0 in vacuum, screen spill 0.25.

### The ascent's vertical bands and ocean

Metres from the vertical tether line; in `facing: "up"` mode each band's `height` offsets its depth along the cabin
Z axis (positive ahead, negative astern) while items glide upright downward past the windows.

| Side | From | To | What |
|---|---|---|---|
| both | 0.0 | 175.0 | `sea` equatorial tropical ocean (`#073160`) at y -11.5 m; `ground_vis` fades 1.0 to 0.0 over 0.18..0.35 so Earth and 360-degree stars shine unobstructed below in orbit |
| both | 42.0 | 122.0 | three `cloud_bank` cumulus layers (`height` -30, 4 and 38 m, 16 puffs each on 250 m loops, seeming 1.6 times further); `presence` peaks across the cloud deck (`0.10..0.36`) |
| left | 28.0 | 29.0 | vertical column of 12 gold-and-cyan `tether_ring` carbon-tether repeater pylons on a 160 m loop, seeming 1.5 times further; active between launch and docking (`0.04..0.99`) |

### Along the climb

| Place | What | Side |
|---|---|---|
| 0.0, -8.2 m base | departure equatorial semi-submersible `ocean_platform`, 33 m off, Z offset 4.5 m | right |
| 1.0, -9.2 m base | arrival gleaming white-and-gold `orbital_station` terminus, 34 m off, Z offset 1.5 m | left |

## The climb's timeline

- **Tracks** (by `film.progress`): `sky.dusk` from 0.0 to 0.28 at 0.22 and 1.0 by 0.44 (smoothed 0.8 s);
  `sky.space_mix` from 0.0 through 0.45 at 0.40 to 1.0 by 0.56 (0.8 s); `sky.earth_alpha` from 0.0 at 0.30 to 1.0 by
  0.52 (0.8 s); `sky.earth_size` from 78.0 degrees to 62.0 degrees and `sky.earth_altitude` from -38.0 degrees to
  -22.0 degrees (1.0 s); `sky.hour` from 22.0 to 24.0 (1.0 s); `ascent.ground_vis` from 1.0 at 0.18 to 0.0 by 0.35
  (0.8 s); `ascent.mist` from 0.08 through 0.12 in the cloud deck to 0.0 in vacuum by 0.42 (0.8 s); `ascent.light`
  between 1.05 and 1.0 (0.8 s); and `wind.level` from 0.65 at sea level through 0.48 in the cloud deck to 0.0 vacuum
  silence by 0.44 (1.2 s). The timeline has an 8 s start and 6 minutes of credits.
- **Cues:**
  - `dim` when `starting`: house lamps to 0.10, cabin exterior glow to 0.14 over 5 s (canopy coves, screen halo,
    docking halo and floor pathway strips remain softly lit via `cove_floor` 0.45).
  - `launch` when `starting` (requires the pre-show ritual setting): sounds the aerospace cabin chime (`chime.play`).
  - `lights_up` in the pre-show and at the end: house lamps to 1.0 and exterior glow released over 4 s.
  - `docking_chime` once `journey.progress` passes 0.93 for 2 s (7200 s cooldown): sounds the cabin chime on final
    approach to the orbital docking station.
- **Room settings:**
  - `cove` (`Cabin light`: Orbital cyan, Warm ivory, Amber night, Off; default Orbital cyan — tints the canopy brow
    valance, eave cornices, floating screen halo, docking airlock halo and aisle floor pathway strips).
  - `starlight` (`Starlight`: Milky Way, Quiet stars, Constellations; default Milky Way — controls `sky.milky_way`
    and `sky.lines` live).

## Comfort

Measured by `test_room_sky_lift.gd` at the fastest the climb goes: 2.7 m/s x (1 + `CATCH_UP`) = 3.10 m/s, slowed by
`seems`. The limits are 3 m and 20 degrees a second (`docs/environments/checks.md`), and every band and landmark stays
serenely under 10 degrees a second.

| What | Side | Its foot | Nearest | Degrees a second |
|---|---|---|---|---|
| band 0, cloud_bank (seems 1.6) | both | 42.0 | 24.75 m | 4.5 |
| band 1, cloud_bank (seems 1.6) | both | 42.0 | 24.91 m | 4.5 |
| band 2, cloud_bank (seems 1.6) | both | 42.0 | 33.38 m | 3.3 |
| band 3, tether_ring (seems 1.5) | left | 28.0 | 24.25 m | 4.9 |
| landmark 0, ocean_platform | right | 33.0 | 19.28 m | 9.2 |
| landmark 1, orbital_station | left | 34.0 | 19.30 m | 9.2 |

The test also checks that nothing goes by within `FLOW_CLEAR_DEG` of the picture from the seat (`flow_clear()`), that
the curved dome and window glass stays well under the blend-layer budget, and that the cabin never tilts or sways.

## Sound

- `acoustics` `small_room` (`rt60` 0.48, `damping` 0.52, `wet` 0.16) for the room's beds. The document's film
  acoustics: reflect `[0.56, 0.56, 0.24, 0.58, 0.46, 0.48]`, `rt60` 0.46 s, `wet` 0.32, `late` 1.08 (`C80` 37.0 dB,
  reverb/direct -20.5 dB, `T20` 0.35 s, `alpha` 0.27).
- `sound_bed` `drive` (`climber_hum`) beneath the cabin floor at `[-0.85, -1.6, 0.0]`, `reach` 8, `gain_db` -1,
  `film_db` -10; `level` follows `journey.speed` from 0.0 to 1.0, smoothed 1.5 s (silky electromagnetic tether
  linear-motor shimmer under way, silent when stopped at launch or docked).
- `sound_bed` `wind` (`wind`) around the upper glazed canopy at `[-0.85, 2.5, 0.0]`, `radius` 3.6, `reach` 6,
  `pitch` 1.05, `gain_db` -5, `film_db` -10; tracked by `film.progress` from 0.65 at sea level to 0.0 vacuum silence
  by 0.44.
- `sound_bed` `chime` (`cabin_chime`) high near the forward brow at `[-0.85, 2.55, -2.6]`, `reach` 10, `gain_db` -3,
  `film_db` -12; played by `launch` and `docking_chime`.
- Measured: -53.4 dBFS RMS in the pre-show (peak -38.3) and -68.3 dBFS under a film at the reference level (target
  -38.0).

## Measured

25 draws, 27620 triangles (26628 with constellation lines off), 0 lights, 0 particles, 5.8 MB of textures (5.2 MB
with constellation lines off), atlas 204x192 (`test_room_sky_lift`, lavapipe, 2026-11-24).

## Not done yet

On the headset: not run.
