# Cinema coach 1935

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

`app/environments/cinema_coach_1935.env.json` (Journeys, built by **Gemini 4 Neon Extra High**), tested by
`app/tests/test_room_cinema_coach_1935.gd`. A golden-age 1935 express newsreel railway cinema carriage rolling through
an autumn night. Twenty plush claret velvet tip-up cinema seats line a narrow mahogany-panelled carriage with an
arched elliptical cream ceiling and an Art Deco runner carpet. A streamlined mahogany-and-brass rear-projection screen
surround glows softly beneath a curved brass-hooded cove valance, ornate polished-brass luggage racks with diamond
netting run above ten rounded-corner windows with partly drawn holland blinds, and eight hanging brass-and-opal-glass
carriage lamps sway gently in unison with the train's speed while the carriage itself stays level. Mid-journey the
express plunges smoothly into a pitch-dark railway tunnel while the warm interior cove and newsreel glow inside, then
emerges back into starlit countryside past semaphore signals and telegraph poles before pulling up at a warm terminus
station with the credits. The journey is as long as the film (`docs/environments/passing.md`).

## The parts

- **The carriage** (`cabin`, id `carriage`; `docs/environments/cabin.md`): 3.30 m wide, straight walls 2.32 m high, an
  arched elliptical roof rising 0.46 m more (2.78 m at the crown). From the front bulkhead at z -4.90 to the rear at
  z 4.60: 9.50 m long. Its centre line is x -0.57, putting the viewer's own seat at the origin. Five rounded-corner
  carriage windows a side, their middles at z -2.40, -0.95, 0.50, 1.95 and 3.40, each 1.04 m wide and 1.00 m high, the
  sill 0.90 m up, corners of 0.14 m, wall thickness 0.12 m, mahogany frames (`frame_width` 0.055, `frame_depth` 0.02).
  A rich mahogany dado to 0.90 m, mahogany walls and bulkheads, curved ribs 0.08 m wide and 0.032 m deep, a cornice
  0.09 m high, warm cream smooth-plaster arched ceiling, and a mahogany aft vestibule door with its backlit frosted
  pane (`door_glow` 0.32). The rear-projection screen is 2.16 m wide and 1.215 m high (16:9), its bottom 1.08 m up,
  stood 0.16 m forward of the front bulkhead (`screen_standoff` 0.16, `screen_frame` false), centred at
  [-0.57, 1.6875, -4.74].
- **The seats:** five rows of four `plush` claret velvet tip-up cinema seats on mahogany frames (two rows ahead of the
  viewer's, two behind), two either side of a 0.46 m central aisle. Rows 1.15 m apart, seats 0.68 m apart; the viewer
  sits in the right pair by the aisle (`own_side` right, `own_index` 0), where the viewer's own seat folds away. There
  are 20 seat transforms, one at the origin, with clear sight lines from every seat to the screen.
- **The 1935 carriage fittings** (`kit`, id `fittings`; `kit/cinema_coach_1935.gd`):
  - `carpet` (`art_deco_runner`): deep claret railway wool carpet with stepped Art Deco gold diamond trellis and cream
    medallions.
  - `coach_1935_interior`: Art Deco streamlined mahogany & brass rear-projection screen surround with a curved glowing
    brass-hooded cove valance and recessed flanking cove slots (`PieceCove`, `cove` 1.75, `cove_floor` 0.55 so the warm
    cinema glow remains alive during the dark tunnel), pleated claret velvet proscenium tabs, slotted brass loudspeaker
    apron and brass sunburst crest; continuous polished-brass overhead luggage racks with Art Deco cantilever brackets,
    diamond woven-cord netting and brass-lipped cornice uplight coves (`PieceCove`); mahogany top roller boxes and
    partly drawn warm holland-cloth blinds with brass bottom battens, pull rings and crimson pull tassels in every
    window; turned brass coat hooks on mahogany wall plaques and a continuous brass emergency communication cord chain
    with signal-red pull tags above the windows; cast-iron floor-edge steam heater pipe shrouds and four crown brass
    ceiling ventilators; wood-panelled aft vestibule door with a frosted-glass Art Deco brass security grille,
    kick-plate and push-bar, flanking framed geometric railway route-map plaques, and a working 1935 railway brass
    bulkhead clock (`PieceClock`).
- **The swaying carriage lamps** (`kit` ids `lamps_left` and `lamps_right` with groups `rack_lamps` and
  `rack_lamps_right`, driven by `motion` ids `sway_left` and `sway_right`): eight hanging brass-and-opal-glass tulip
  carriage lamps (`coach_1935_lamps`), four a side suspended directly from the luggage rack lower brass rails at
  [-1.95, 2.02] and [0.81, 2.02]. Both sides sway gently in unison about the fore-aft Z axis with a slow 6.2 s bogie
  sway period: 1.8 degrees under way, settling to 0.15 degrees in the station (`journey.speed`, scaled by `Motion`, zero
  cabin or floor tilt).
- **The presentation** (`presentation`): vintage 1935 back-projection newsreel film look (`worn_print` preset with
  tuned weave 0.45, tilt 0.15, flicker 0.35, dust 0.22, scratches 0.28, hotspot 0.45), live-controlled by the `Picture`
  setting (`Newsreel print` / `Clean picture`).
- **The light** (`light`): warm 1935 tungsten lamps `[1.0, 0.80, 0.52]`, spill 0.52, baked fill 0.14.
- **The sky** (`sky`): latitude 52, day 275, heading 350 degrees, 20:48 at departure; autumn amber sunset afterglow at
  278 degrees outside the left carriage windows, evening star, Milky Way (0.60, detail 0.50), light clouds (0.14),
  meteors (3), 2000 faint stars, and a bright gibbous Moon (phase 0.82, size 1.7) at bearing 274 degrees, altitude
  8.8 degrees framed cleanly through the left windows.
- **The track** (`passing`, id `track`): forward at 4.8 m/s, glow 0.48 in `#ffcb86` reaching 14 m out and 4.5 m ahead
  and astern, mist `#263040`, screen spill 0.32.

### The line's cross-section

Metres from the way's line; heights are over the carriage's floor (the eyes are at 1.2 m, roughly 2.55 m over the
track ballast at -1.35 m).

| Side | From | To | What |
|---|---|---|---|
| both | 0.0 | 6.5 | trackside `stone` gravel ballast at -1.35 m |
| both | 6.5 | 16.0 | `grass` railway embankment sloping from -1.35 to -2.1 m |
| both | 16.0 | 175.0 | night countryside `field` at -2.1 m |
| left | 18.5 | 19.2 | vintage railway `telegraph` poles, 20 on a 280 m loop, size 1.05, feet at -1.65; present in open countryside (0.025..0.975) |
| both | 26.0 | 52.0 | tall `poplar` silhouettes, 24 on a 300 m loop, feet at -2.1 |
| both | 30.0 | 68.0 | countryside broadleaf `tree` bands, 75 on a 300 m loop, feet at -2.1 |
| both | 36.0 | 78.0 | rural `cottage` farmhouses with warm lit windows, 14 on a 320 m loop, feet at -2.1 |
| both | 62.0 | 82.0 | distant village `lights`, 120 on a 320 m loop, seeming 5.5 times further, feet at -1.5 |
| both | 84.0 | 84.0 | rolling far countryside `ridge` skyline, 336 m loop, seeming 12 times further, size 0.68, feet at -2.1 |

### Along the route

| Place | What | Side |
|---|---|---|
| 0.0 | departure `station`, 17.5 m off, railhead at -1.35 | right |
| 0.0, 58 m ahead | departure starter semaphore `signal`, 18.5 m off, at -1.35 | right |
| 0.0, 95 m ahead | steam yard `water_tower`, 26 m off, at -1.35 | left |
| 0.22 | countryside block semaphore `signal`, 24 m off, size 0.85 | left |
| 0.415 | tunnel-approach semaphore `signal`, 18.5 m off | right |
| 0.42..0.56 | **the railway tunnel stretch** (`track.tunnel` and `sky.blackout` sweep smoothly to 1.0 across 0.45..0.53) | both |
| 0.575 | tunnel-exit home semaphore `signal`, 18.5 m off | right |
| 0.74 | distant village church `tower`, 62 m off, at -2.1 | left |
| 1.0, 62 m before | arrival home semaphore `signal`, 18.5 m off | right |
| 1.0 | arrival terminus `station`, 17.5 m off, railhead at -1.35 | right |

## The express's evening

- **Tracks** (by `film.progress`): `sky.dusk` from 0.35 to 1.0 at 0.26 (smoothed 0.5 s); `sky.hour` from 20.8 to 23.2
  over the film (1 s); `track.mist` shifting from 0.08 to 0.04, rising to 0.14 across the autumn valley after the
  tunnel and settling to 0.08 at the terminus (0.5 s); `track.tunnel` and `sky.blackout` both sweeping
  `[[0.0, 0.0], [0.42, 0.0], [0.45, 1.0], [0.53, 1.0], [0.56, 0.0], [1.0, 0.0]]` (smoothed 1.2 s) for the mid-reel
  railway tunnel. The timeline has an 8 s start and 6 minutes of credits.
- **Cues:**
  - `dim` when `starting`: house lamps to 0.16, vestibule door glow to 0.12, trackside window glow to 0.25 over 5 s
    (brass-hooded screen cove and cornice wash stay warmly lit via `cove_floor` 0.55).
  - `departure` when `starting` (requires the pre-show ritual setting): blows the three-chime steam locomotive whistle
    (`whistle.play`).
  - `lights_up` in the pre-show and at the end: house lamps to 1.0, door glow and trackside glow released over 4 s.
  - `arrival` once `journey.progress` passes 0.93 for 2 s (7200 s cooldown): blows the steam whistle approaching the
    terminus.
- **Room settings:**
  - `lighting` (`Lighting`: Warm amber, Ruby cove, Off; default Warm amber — sets the screen cove and cornice wash
    during the film and inside the railway tunnel).
  - `picture` (`Picture`: Newsreel print, Clean picture; default Newsreel print — toggles the 1935 back-projection
    film print stage and behind-bulkhead projector hum).

## Comfort

Measured by `test_room_cinema_coach_1935.gd` at the fastest the journey goes: 4.8 m/s x (1 + `CATCH_UP`) = 5.52 m/s,
slowed by `seems`. The limits are 3 m and 20 degrees a second (`docs/environments/checks.md`).

| What | Side | Nearest (m) | At 5.52 m/s (deg/s) |
|---|---|---|---|
| `telegraph` band | left | 18.11 | 17.5 |
| `tree` band | both | 22.88 | 13.8 |
| `poplar` band | both | 24.09 | 13.1 |
| `cottage` band | both | 33.00 | 9.6 |
| `ridge` band (`seems` 12.0) | both | 84.00 | 0.3 |
| `lights` band (`seems` 5.5) | both | 62.00 | 0.9 |
| `station` landmarks (0.0, 1.0) | right | 17.50 | 18.1 |
| `signal` landmarks (0.0, 0.415, 0.575, 1.0) | right | 17.16 | 18.4 |
| `water_tower` landmark (0.0) | left | 22.93 | 13.8 |
| `signal` landmark (0.220) | left | 22.67 | 14.0 |
| `tower` landmark (0.740) | left | 57.97 | 5.5 |

`flow_clear()` passes with zero passing scenery within 10 degrees of the picture edges; glass `blend_layers` stays
well within half the blend budget; cabin and floor stay completely level (only the hanging carriage lamps sway gently
in unison with `journey.speed`, scaled by `Motion`).

## Sound

- `acoustics` `small_room` (`rt60` 0.42, `damping` 0.65, `wet` 0.16) for the room's beds. The document's film
  acoustics: reflect [0.36, 0.36, 0.24, 0.40, 0.34, 0.34], rt60 0.34 s, wet 0.28, late 0.95. Measured by
  `test_room_acoustics.gd` (`box 3.3 x 2.8 x 9.5`): C80 44.2 dB, reverb/direct -27.4 dB, T20 0.28 s, Sabine mean
  absorption `alpha` 0.31.
- `sound_bed` `bogies` (`rail_joints`) below the carriage floor at [-0.57, -1.0, 0.0], `reach` 6, `gain_db` -2,
  `film_db` -10; `level` follows `journey.speed` from 0.0 to 1.0 (smoothed 1.8 s): silent when parked at the station,
  rhythmic clickety-clack under way.
- `sound_bed` `whistle` (`train_whistle`) ahead at the locomotive [-0.57, 2.5, -18.0], `reach` 24, `gain_db` -3,
  `film_db` -12; played by the `departure` and `arrival` cues.
- `sound_bed` `projector` (`projector`) behind the front bulkhead at [-0.57, 1.55, -5.2], `reach` 3.5, `gain_db` -5,
  `film_db` -10; `level` follows `setting.picture` (0.75 on Newsreel print, 0.0 on Clean picture).
- `sound_bed` `wind` (`wind`) around the carriage windows at [-0.57, 1.4, 0.0], `radius` 3.2, `reach` 4.5, `gain_db`
  -5, `film_db` -11; `level` follows `journey.speed` from 0.25 to 0.9 (smoothed 2 s).
- Measured room bed level (`RoomSound.check_level`): pre-show **-57.9 dBFS RMS** (peak **-41.9**), under a film at the
  reference **-68.1 dBFS** (target -38.0, film -20.0).

## Measured

2026-11-23 (`test_room_cinema_coach_1935.gd`, 59/59 checks passed both headless and under Vulkan 1.4.318 Forward Mobile
/ lavapipe; `test_room_acoustics.gd` 141/141 checks passed):

- **26 draws** (budget <= 38)
- **54,346 triangles** (budget <= 120,000)
- **0 live lights**, **0 particles**
- **6.2 MB of textures** (budget <= 80 MB), lightmap atlas **200 x 244**

Visually checked under Vulkan Forward Mobile / lavapipe across pre-show (forward cabin, aft bulkhead clock and brass
vestibule grille, seated sight line, close-up luggage racks and curved brass-hooded cove, parked departure station and
twilight sky), station departure, starlit countryside with telegraph poles and semaphore signal, mid-reel dark railway
tunnel (both Warm amber and Ruby cove settings), post-tunnel emerald semaphore signal through the carriage window, and
terminus station arrival.

## Not done yet

On the headset: not run.
