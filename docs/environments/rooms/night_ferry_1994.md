# Night ferry 1994

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

`app/environments/night_ferry_1994.env.json` (Journeys, built by **Gemini 4 Neon Extra High**), tested by
`app/tests/test_room_night_ferry_1994.gd`. The fourth of the Journeys: a 1994 cross-Channel passenger ferry's video
lounge crossing at night. Twelve Pullman recliners with crisp woven white linen antimacassars and flip-up laminate tray
tables sit under a ceiling-bracketed 4:3 CRT television and locked steel VCR cage flashing `12:00`. Eight rounded marine
storm windows hold wind-driven rain streaks and dried sea-salt edge rime in a single draw call; outside, a headland
lighthouse's twin volumetric beam sweeps slowly over the dark Channel water, container freighters pass in mid-crossing
under the Moon's road, and a floodlit Ro-Ro ferry terminal welcomes the ship with the credits. The journey is as long as
the film (`docs/environments/passing.md`).

## The parts

- **The lounge** (`cabin`, id `lounge`; `docs/environments/cabin.md`): 6.4 m wide, straight walls 2.82 m high, an arched
  roof rising 0.30 m more (3.12 m at the crown). From the front bulkhead at z -3.75 to the rear at z 2.85: 6.6 m. Its
  centre line is x -0.91, putting the viewer's own seat at the origin. Four rounded storm windows a side, their middles
  at z -2.25, -0.75, 0.75 and 2.25, each 1.12 m wide and 1.05 m high, the sill 0.94 m up, corners of 0.18 m, wall
  thickness 0.16 m, black gasket frames (`frame_width` 0.075, `frame_depth` 0.025), and `window_glass` false so
  `weather.panes` draws the wet salt-streaked glass without double blend overdraw. A slate-teal marine painted dado to
  0.94 m, ribs 0.10 m wide and 0.035 m deep, a cornice 0.08 m high, a painted companionway rear door with its glowing
  pane (`door_glow` 0.35), and an exterior concrete-grey promenade deck ledge 1.3 m wide outside each wall at y -0.02.
  The picture is 1.56 m wide and 1.17 m high (4:3), its bottom 1.58 m up, stood 0.65 m forward of the front bulkhead
  (`screen_standoff` 0.65, `screen_frame` false), centred at [-0.91, 2.165, -3.10].
- **The seats** (`seats`, model `recliner`, `from_builders` true): three rows of four deep marine-teal Pullman recliners
  (one row ahead of the viewer's, one behind), two either side of a 1.1 m aisle. Rows 1.40 m apart, seats 0.72 m apart;
  the viewer sits in the right block by the aisle (`own_side` right, `own_index` 0), where the viewer's own recliner
  folds away while both its moulded armrests remain. There are 12 seat transforms, one at the origin.
- **The 1994 ferry fittings** (`kit`, id `fittings`; `kit/ferry_1994.gd`):
  - `carpet` (`moquette_94`): 1994 deep-navy geometric marine wool carpet with teal, magenta, gold and coral confetti
    ticks and mini triangles.
  - `ferry_lounge`: ceiling-bracketed 4:3 CRT television on twin bolted steel marine drop-struts with speaker grilles,
    brushed-chrome chin trim, green standby LED, deep cathode-ray casing, armoured cable umbilical and a locked steel
    VCR shelf cage holding a video deck flashing `12:00` (`PieceDisplay`); four louvred overhead fluorescent ceiling
    panels (`PieceLamps`, house group, two bake lights) and night-crossing pelmet cove strips (`PieceCove`, `cove_floor`
    0.58 so they glow warmly while the film plays); bolted brushed-steel storm grab-rails and convector heater boxes under
    the windows; two laminate window-bay corner tables with anti-roll lips, takeaway paper coffee cups and folded crossing
    timetables; aft bulkhead stainless door push-bar and kick-plate, backlit green geometric EXIT sign (`PieceWindows`),
    working brushed-steel ship's bulkhead clock (`PieceClock`), glass-fronted red marine fire-hose reel cabinet
    (`PieceGlass`), lifebuoy safety placard, and white exterior promenade deck rails with international-orange lifebuoy
    rings and watertight bulkhead lamps.
  - `ferry_rows`: shared moulded dark-grey armrests between seats and at row ends with brushed-steel recline buttons and
    flip-lid ashtrays, curved woven white `linen` antimacassar headrest covers hugging the recliners' exact profile,
    flush curved flip-up pale-grey laminate seatback tray tables with latches, and low night-crossing aisle step strips
    (`PieceCove`).
- **The presentation** (`presentation`): defaults to `nightowl_1993` + `tape` source (`starts_off` true), switching on
  with the departure cue and live-controlled by the `Television` and `Telly speaker` settings.
- **The weather** (`weather`): `mode` bound to `Weather at sea` (`squalls` / `rain` / `clear`), 900 falling raindrops in
  two deck areas outside the port and starboard windows, and 8 merged storm-window `panes` in a single draw call with
  dried sea-salt edge rime (`pane_salt` 0.72) and wind-driven sideways aft rain streaks (`pane_drift` bound to
  `journey.speed` 0..1.35, smoothed 2 s).
- **The light** (`light`): cool-white fluorescent lamps `[0.92, 0.96, 1.0]`, spill 0.42, baked fill 0.12.
- **The sky** (`sky`): latitude 51, day 310, heading 140 degrees, 21:24 at departure, late Channel dusk (0.88) into full
  night, broken Channel clouds (0.58), faint Milky Way (0.25), and a gibbous Moon (phase 0.72, size 1.5) at bearing 62
  degrees, altitude 11.5 degrees laying its silver road across the dark port water.
- **The Channel** (`passing`, id `channel`): forward at 4.0 m/s, glow 0.4 in `#d4e6ff` reaching 14 m out and 5 m ahead
  and astern, mist `#24303e`, screen spill 0.3, `beam_spin` 1.0 (rotating volumetric twin-cone lighthouse beams at
  ~11.4 s/rev, scaled by `Motion`, 1 additive draw, 0 live lights).

### The Channel's cross-section

Metres from the way's line; heights are over the lounge's floor (the eyes are at 1.2 m, roughly 7.7 m above the
waterline at -6.5 m).

| Side | From | To | What |
|---|---|---|---|
| both | 0.0 | 175.0 | `sea` ground disc out to the 185 m horizon skirt at -6.5 m |
| both | 28.0 | 54.0 | channel buoys, 10 on a 340 m loop, red or green with a light, feet at -6.5; present near departure (0..0.12) and arrival (0.86..1.0) |
| right | 80.0 | 145.0 | starboard coastal port lights, 120 on a 320 m loop, seeming 5 times further, feet at -3.5; present near departure (0..0.16) and arrival (0.80..1.0) |
| left | 95.0 | 155.0 | port headland lights, 85 on a 320 m loop, seeming 6 times further, feet at -3.5; present near departure (0..0.15) and arrival (0.82..1.0) |

### Along the route

| Place | What | Side |
|---|---|---|
| 0.0 | departure Ro-Ro `ferry_port`, 17 m off, waterline at -6.5 | right |
| 0.0, 110 m ahead | departure headland `lighthouse` with sweeping volumetric beam, 44 m off, waterline at -6.5 | left |
| 0.36 | passing container `freighter`, 76 m off, waterline at -6.5, seed 4 | left |
| 0.68 | passing container `freighter`, 84 m off, waterline at -6.5, seed 11 | right |
| 1.0, 115 m before | arrival headland `lighthouse` with sweeping volumetric beam, 44 m off, waterline at -6.5 | right |
| 1.0 | arrival Ro-Ro `ferry_port`, 17 m off, waterline at -6.5 | right |

Departure and arrival are set out in metres (`ahead`), so the Ro-Ro ferry port and headland lighthouse stand in the same
places for a film of any length.

## The crossing's evening

- **Tracks** (by `film.progress`): `sky.dusk` from 0.88 to 1.0 at 0.22 (smoothed 0.5 s); `sky.hour` from 21.4 to 23.9
  over the film (1 s); `channel.mist` shifting through sea-fog banks from 0.16 to 0.26, 0.18, 0.30 and 0.22 on arrival
  (0.5 s). The timeline has an 8 s start and 6 minutes of credits.
- **Cues:**
  - `dim` when `starting`: house lamps to 0.12, door glow to 0.12, sea glow to 0.20 over 5 s (night-crossing cove strips
    stay softly glowing via `cove_floor` 0.58).
  - `departure` when `starting` (requires the pre-show ritual setting): plays the three-note synthetic maritime PA
    boarding chime (`chime.play`), switches on the CRT (`presentation.switch_on`), loads the tape (`vcr.play`), waits
    2.5 s, and sounds the deep ship's horn (`horn.play`).
  - `lights_up` in the pre-show and at the end: house lamps to 1.0, door glow and sea glow released over 4 s, CRT off.
  - `arrival_horn` once `journey.progress` passes 0.92 for 2 s (7200 s cooldown): sounds the harbour whistle on approach.
- **Room settings:**
  - `weather` (`Weather at sea`: Squalls, Raining, Clear night; default Squalls).
  - `picture` (`Television`: 1994 CRT & tape, 1994 CRT, Clean picture; default 1994 CRT & tape).
  - `speaker` (`Telly speaker`: off/on; default off — routes film audio through the overhead CRT's mono speaker).
  - `night_strips` (`Night strips`: Soft amber, Marine teal, Off; default Soft amber — tints the aisle and pelmet
    night-crossing strips).

## Comfort

Measured by `test_room_night_ferry_1994.gd` at the fastest the journey goes: 4.0 m/s x (1 + `CATCH_UP`) = 4.60 m/s,
slowed by `seems`. The limits are 3 m and 20 degrees a second (`docs/environments/checks.md`).

| What | Side | Its foot | Nearest | Degrees a second |
|---|---|---|---|---|
| band 0, buoy | both | 28.0 | 27.44 m | 9.6 |
| band 1, lights (seems 5) | right | 80.0 | 80.00 m | 0.7 |
| band 2, lights (seems 6) | left | 95.0 | 95.00 m | 0.5 |
| landmark 0, ferry_port | right | 17.0 | 17.00 m | 15.5 |
| landmark 1, lighthouse | left | 44.0 | 40.40 m | 6.5 |
| landmark 2, freighter | left | 76.0 | 69.00 m | 3.8 |
| landmark 3, freighter | right | 84.0 | 77.00 m | 3.4 |
| landmark 4, lighthouse | right | 44.0 | 40.40 m | 6.5 |
| landmark 5, ferry_port | right | 17.0 | 17.00 m | 15.5 |

The test also checks that nothing goes by within `FLOW_CLEAR_DEG` of the picture from the seat (`flow_clear()`), that
the hull never tilts or rolls, that `pane_drift` scales with `journey.speed` and `motion`, and that the lighthouse beam
turns smoothly at a photosensitivity-safe pace (~11.4 s/rev).

## Sound

- `acoustics` `hull` (`rt60` 0.65, `wet` 0.22) for the room's beds. The document's film acoustics: reflect
  [0.46, 0.46, 0.22, 0.44, 0.48, 0.48], rt60 0.52 s, wet 0.36, late 1.15.
- `sound_bed` `engines` (`ferry_diesel`) below the aft deck at [-0.91, -2.5, 2.5], `reach` 8, `gain_db` -2, `film_db`
  -10; `level` follows `journey.speed` from 0.35 to 1.0, smoothed 2 s.
- `sound_bed` `sea_wash` (`water_lap`) everywhere, `gain_db` -3, `film_db` -10, `pitch` 0.72.
- `sound_bed` `rain` (`rain_glass`) around the lounge at [-0.91, 1.45, 0.0], `radius` 3.5, `reach` 5, `gain_db` -2,
  `film_db` -10; `level` follows `weather.rain`, smoothed 2 s.
- `sound_bed` `creak` (`hull_creak`) at [4.5, 0.5, 1.0], `reach` 8, `every` 185 s, `gain_db` -6, `film_db` -14.
- `sound_bed` `vcr` (`vcr`) at the VCR cage [-0.91, 1.35, -3.3], `reach` 4, `gain_db` -2; played by `departure`.
- `sound_bed` `whine` (`tube_whine`) at the CRT [-0.91, 2.16, -3.1], `reach` 3.5, `gain_db` -6, `film_db` -8; `level`
  0.6 on `tape`/`crt` and 0.0 on `clean`.
- `sound_bed` `chime` (`ferry_chime`) overhead at [-0.91, 2.8, -0.5], `reach` 8, `gain_db` -3; played by `departure`.
- `sound_bed` `horn` (`ship_horn`) forward high up at [-0.91, 12.0, -14.0], `reach` 20, `gain_db` -4, `film_db` -12;
  played by `departure` and `arrival_horn`.
- Measured: -45.9 dBFS RMS in the pre-show (peak -29.5) and -67.4 dBFS under a film at the reference level (target
  -38.0).

## Measured

34 draws, 21064 triangles, 0 lights, 900 particles, 6.2 MB of textures, atlas 212x200 (`test_room_night_ferry_1994`,
lavapipe, 2026-11-23).

## Not done yet

On the headset: not run.
