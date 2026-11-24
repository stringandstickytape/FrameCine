# Airship 1931

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

`app/environments/airship_1931.env.json` (Journeys, built by **Gemini 4 Neon Extra High**), tested by
`app/tests/test_room_airship_1931.gd`. A golden-age 1931 rigid airship's airy promenade lounge crossing at night above
an endless moonlit sea of clouds. Walls leaning outwards by 12 degrees tilt ten tall panoramic observation windows
downwards towards the billowing cloud deck far below, framed by exposed brushed-duralumin triangular lattice girders and
delicate tubular safety guardrails. In the forward-port bay stands a featherweight brushed-aluminium and cream-lacquered
baby grand piano whose 61 keys move in real time while it plays salon music in the pre-show and interval; at departure
and arrival, an illuminated 1930s steel-lattice mooring mast aligns its glazed Art Deco boarding gallery right outside
the starboard windows. The journey is as long as the film (`docs/environments/passing.md`).

## The parts

- **The promenade** (`cabin`, id `promenade`; `docs/environments/cabin.md`): 7.0 m wide at the floor, walls 2.90 m high
  leaning outwards (`lean` -12.0 degrees, flaring to 8.23 m at the eaves), under an arched taut-fabric ceiling rising
  0.48 m more (3.38 m at the crown). From the front bulkhead at z -5.2 to the rear at z 4.2: 9.4 m long, centre line at
  x -1.15 putting the viewer's own seat at the origin. Five wide slanted panoramic windows a side centred at z -3.54,
  -1.92, -0.30, 1.32 and 2.94 (1.28 m wide, 1.88 m high, low sill at 0.68 m, rounded corners 0.14 m) in brushed-steel
  frames (`frame_width` 0.055), pale birch dado to 0.68 m, champagne-cream `linen` upper walls and ceiling, no exterior
  ledge (`ledge` 0.0), and a centre rear companionway door (`door_glow` 0.28). The picture is 3.60 m wide and 2.025 m
  high (16:9), its bottom 1.10 m up, centred at [-1.15, 2.1125, -5.17].
- **The seats** (`seats`, model `lounge`, `from_builders` true): three rows of four burnt-russet woven lounge chairs on
  brushed-steel legs (one row ahead of the viewer's, one behind), two either side of a 1.3 m centre aisle with a generous
  promenade walkway along both observation walls. Rows 1.50 m apart, seats 1.0 m apart; viewer in the right block by the
  aisle (`own_side` right, `own_index` 0). 12 seat transforms, one at the origin.
- **The 1931 airship fittings** (`kit`, id `fittings`; `kit/airship_1931.gd`):
  - `carpet` (`deco_carpet`): deep midnight-navy and champagne-gold woven Art Deco rising-sun wool carpet.
  - `airship_1931_promenade`: exposed brushed-duralumin triangular lattice ring-girders with zig-zag diagonal web
    cross-bracing and mitered knee-joints at all six bay stations up both outward-leaning walls and across the arched
    deckhead, tied fore-and-aft by longitudinal purlins and a ridge spine; pale birch window-sill ledges, tubular
    aluminium observation safety guardrails, and a pair of brass-and-leather binoculars resting on the starboard middle
    sill; streamlined cream-and-aluminium Art Deco screen proscenium on a low dais with continuing outer-wing birch dado,
    tucked eave cove valances washing champagne/silver indirect light (`PieceCove`, `cove_floor` 0.35), winged brass
    header crest, three ceiling luminaire fins and two slim modernist aluminium & 3-tier frosted-glass torchière floor
    lamps (`PieceLamps`, `bake_lamps` 2); aft bulkhead wrap-around birch dado, twin aluminium pilasters & transom framing
    the companionway door, modernist brushed-aluminium clock (`PieceClock`), starboard tubular navigation chart table
    with brass-rimmed aerial compass rose, dividers, folded route chart and a framed transoceanic great-circle route map
    panel above, and port-side credenza with carafe, route logbook and framed geometric altitude profile plaque.
  - `airship_1931_piano`: featherweight brushed-aluminium & cream-lacquered baby grand piano at [-3.58, 0.0, -3.50]
    (yaw 28 degrees) in the forward-port bay, strictly clear of every seat's sight line, with S-curved rim, 34-degree
    propped lid showing a pale birch underside braced by brushed-duralumin acoustic ribs, spruce soundboard, cast
    champagne-bronze harp and gilded strings, tubular aluminium legs with brass casters, brass pedal lyre, pierced music
    desk with open score sheets, matching tubular bench, and 61 animated moving keys in a single `MultiMeshInstance3D`
    (`AirshipPianoKeys`, 1 draw, 0 lights) driven live via `c.halls` from `music.held_notes()`.
- **The light** (`light`): warm champagne `[1.0, 0.87, 0.64]`, spill 0.45, baked fill 0.14.
- **The sky** (`sky`): latitude 48, day 190, heading 260 degrees, 21:00 at departure, evening twilight (`dusk` 0.25)
  deepening into starlit ocean night (`dusk` 1.0, `night_horizon` `#1c2b4a`), subtle wispy clouds (0.18), Milky Way
  (0.72), and a gibbous Moon (`moon` 0.9, `moon_size` 2.0, `moon_phase` 0.82, `moon_altitude` 16.0, `moon_bearing`
  342.0) shining outside the starboard observation windows and silvering the cloud ocean below.
- **The skyway** (`passing`, id `skyway`): forward at 4.8 m/s, glow 0.38 in `#ffdca8` reaching 14 m out and 5.5 m ahead
  and astern, mist 0.34 in `#283a5c`, screen spill 0.22.

### The skyway's cross-section

Metres from the way's line; heights are over the promenade's floor (eyes at 1.2 m, roughly 25 m above the cloud deck at
-24.0 m).

| Side | From | To | What |
|---|---|---|---|
| both | 0.0 | 170.0 | `cloud_deck` endless moonlit sea of clouds sloping gently from -24.0 m to -18.0 m (`#24314a`) with silver Moon sheen and faint town rifts |
| both | 76.0 | 138.0 | moonlit 3D `cloud_bank` puffs, 14 on a 340 m loop, seeming 3.5 times further, feet at -27.5 m (size 0.72) |
| both | 118.0 | 162.0 | distant layered `cloud_bank` tops, 14 on a 340 m loop, seeming 6 times further, feet at -23.5 m (size 0.95) |
| both | 58.0 | 155.0 | distant sleeping town `lights`, 190 on a 340 m loop, seeming 8 times further, feet at -21.5 m (size 1.6) |

### Along the route

| Place | What | Side |
|---|---|---|
| 0.0 | departure 1930s steel-lattice `airship_mast` (boarding gallery aligned at y -1.8..+1.6 m), 26 m off, base at -30.0 m | right |
| 0.0, 68 m ahead | far airfield `airship_mast`, 66 m off, base at -30.0 m | left |
| 1.0, 68 m before | arrival far airfield `airship_mast`, 66 m off, base at -30.0 m | left |
| 1.0 | arrival 1930s steel-lattice `airship_mast`, 26 m off, base at -30.0 m | right |

## The crossing's evening

- **Tracks** (by `film.progress`): `sky.dusk` from 0.25 to 0.82 at 0.32 and 1.0 at 0.58 (smoothed 0.5 s); `sky.hour` from
  21.0 to 23.8 over the film (1 s); `skyway.mist` shifting subtly between 0.32, 0.28, 0.32, 0.36 and 0.34 (0.5 s).
  Timeline: 8 s start, 6 minutes of credits.
- **Cues:**
  - `dim` when `starting`: house lamps to 0.16, door glow to 0.10, skyway glow to 0.20 over 5 s (proscenium and deckhead
    coves retain a 0.35 floor).
  - `departure_bell` when `starting` (requires the pre-show ritual setting): sounds the salon chime (`chime.play`).
  - `lights_up` in the pre-show and at the end: house lamps to 1.0, door glow and skyway glow released over 4 s.
  - `arrival_bell` once `journey.progress` passes 0.92 for 2 s (7200 s cooldown): sounds the salon chime on approach.
- **Room settings:**
  - `piano` (`Lounge piano`: on/off; default on — toggles the self-playing featherweight grand piano and its animated
    keys).
  - `cove` (`Cove glow`: Champagne, Moonlight silver, Off; default Champagne — tints the indirect proscenium and deckhead
    cove wash).

## Comfort

Measured by `test_room_airship_1931.gd` at the fastest the journey goes: 4.8 m/s x (1 + `CATCH_UP`) = 5.52 m/s, slowed
by `seems`. Limits: 3 m and 20 degrees a second (`docs/environments/checks.md`).

| What | Nearest | Rate |
|---|---|---|
| band 0 `cloud_bank` both | 65.20 m | 1.4 deg/s |
| band 1 `cloud_bank` both | 103.75 m | 0.5 deg/s |
| band 2 `lights` both | 58.00 m | 0.7 deg/s |
| landmark 0 `airship_mast` right (departure) | 20.50 m | 15.4 deg/s |
| landmark 1 `airship_mast` left (departure far) | 60.50 m | 5.2 deg/s |
| landmark 2 `airship_mast` left (arrival far) | 60.50 m | 5.2 deg/s |
| landmark 3 `airship_mast` right (arrival) | 20.50 m | 15.4 deg/s |

## Sound

- `acoustics` `small_room` (`rt60` 0.62, `damping` 0.62, `wet` 0.16) for the room's beds and piano. Document film
  acoustics: reflect [0.34, 0.34, 0.16, 0.28, 0.32, 0.30], rt60 0.58 s, wet 0.38, late 1.18.
- `sound_bed` `engines` (`airship_engines`) aft below the promenade at [-1.15, -3.5, 5.5], `reach` 9, `gain_db` -1,
  `film_db` -10; `level` follows `journey.speed` from 0.25 to 1.0, smoothed 2 s.
- `sound_bed` `breeze` (`wind`) everywhere, `gain_db` -6, `film_db` -10.
- `sound_bed` `chime` (`chime`) overhead at [-1.15, 2.8, -1.0], `reach` 8, `gain_db` -5, `film_db` -10; played on
  departure and arrival.
- `music` `piano` (`piano`) at the featherweight grand piano [-3.58, 0.85, -3.5], `reach` 8, `detune_cents` 1.5, `tempo`
  84, `drive` 0.25, `gain_db` -2, `film_db` -14, `plays_in` preshow/intermission/ended, `on` bound to `setting.piano`.
- Measured by `test_room_airship_1931.gd`: pre-show `-49.3 dBFS RMS` (peak `-32.9` to `-34.4`), under a film at the
  reference `-71.8` to `-72.2 dBFS RMS` (target `-38.0`, film `-20.0`).

## Measured

Measured by `test_room_airship_1931.gd` (headless and Vulkan Forward Mobile / lavapipe, `2026-11-23`): 27 draws, 38,916
triangles, 0 lights, 0 particles, 6.2 MB of textures, lightmap atlas 256 x 244; 54 checks, all passed.

## Not done yet

On the headset: not run.
