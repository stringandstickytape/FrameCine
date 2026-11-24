# Night sleeper 1929

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

`app/environments/night_sleeper_1929.env.json` (Journeys, built by **Gemini 4 Neon Extra High**), tested by
`app/tests/test_room_night_sleeper_1929.gd`. An intimate 1929 Art Deco marquetry sleeping compartment crossing a snowy
winter alpine night into rosy morning dawn. Walnut and honey-mahogany wood panelling with inlaid brass diamond
medallions lines the private compartment; a recessed sliding frosted-glass corridor door sits on the right wall beneath
a brass luggage rack and a working railway compartment clock. On the left, drawn-back claret velvet curtains frame a
wide panoramic window looking out onto falling snow, snow-dusted pines, silver birches, moonlit alpine peaks and
glowing wayside stations. A folding walnut window-side table holds a vintage 1929 16 mm home film projector casting a
soft dusty beam onto a portable brass-capped roller linen screen on the front bulkhead, while a sapphire-blue ceiling
night lamp glows gently through the darkened film and rosy eastern dawn rises with the credits. The journey is as long
as the film (`docs/environments/passing.md`).

## The parts

- **The compartment** (`cabin`, id `compartment`; `docs/environments/cabin.md`): 2.6 m wide, straight walls 2.35 m high,
  arched cream-plaster roof rising 0.24 m more (2.59 m at the crown). From the front bulkhead at z -2.4 to the rear at
  z 1.8: 4.2 m long, centred at x 0.0 with a single private claret velvet club seat at the origin (`seating` none,
  `seat_model` club). One wide rounded-corner panoramic picture window on the left wall only (`window_sides` left,
  centred at z -0.25, 1.65 m wide, 1.04 m high, sill at 0.88 m, corners of 0.14 m, wall thickness 0.14 m, plain glass in
  one draw). Rich walnut walls and panelling dado to 0.88 m, cornice 0.075 m, no rear door (the compartment's entrance
  is the sliding corridor door on the right wall), no exterior ledge. The portable linen picture is 1.68 m wide by
  0.945 m high (16:9), bottom at 0.94 m, stood 0.06 m off the front bulkhead (`screen_frame` false), centred at
  [0.0, 1.4125, -2.34].
- **The 1929 sleeper fittings & props** (`kit`, id `fittings`; `kit/night_sleeper_1929.gd`):
  - `carpet` (`art_deco_runner`): claret-and-gold 1929 geometric diamond-trellis wool runner.
  - `sleeper_1929_cabin`: book-matched walnut and mahogany marquetry wall bays with inlaid brass diamond medallions and
    trim lines along the right corridor wall and left piers; recessed sliding wood-and-frosted-glass corridor door
    (glowing warmly from the corridor via `PieceWindows`) with brass muntins, track rail, curved latch handle and
    frosted transom pane; overhead brass luggage rack with a strapped tan leather valise; working Art Deco brass railway
    compartment clock above the corridor door (`PieceClock`); claret velvet lower sleeper berth sofa with rolled
    bolsters, folded ivory linen and navy wool travel blanket across the rear bulkhead; folded-up walnut, brass and
    ivory-linen upper sleeping berth stowed high on the rear bulkhead with brass folding strap brackets, latch handles,
    ladder hooks and a stowed slim brass bunk ladder; walnut-and-brass window pelmet box, deeply pleated drawn-back
    claret velvet curtains with brass tie-back clasps and gold hem trim, and an under-sill walnut-and-brass radiator
    grille; arched walnut ceiling ribs; a **glowing sapphire-blue night lamp** glass globe framed by a stepped
    walnut-and-brass circular ceiling medallion (`PieceCove`, `cove_floor` 0.65 so it glows steadily once the house
    lights dim, live-controlled by the `Night lamp` setting); and four warm brass-and-opal-glass Art Deco reading
    sconces (`PieceLamps`, house group, two bake lights).
  - `sleeper_1929_props`: bespoke walnut-and-brass spring-roller portable projection screen housing on the front
    bulkhead with turned brass end-caps, wall hooks, slim side borders, weighted lower tension dowel and brass pull ring
    above a low marquetry console cabinet; folding walnut window-side table tucked neatly left-front (> 0.9 m clear of
    the seat) with brass edge banding and diagonal folding leg, holding a vintage 1929 16 mm home film projector (black
    enamel body, vented lamphouse, twin spoked brass reels, tilted optical lens barrel and glowing lens aperture in
    `PiecePort` aimed straight at the screen), a bone-china porcelain teacup and saucer with brass teaspoon, and a
    burgundy leatherbound travel timetable with brass corner clasps.
- **The atmosphere** (`atmosphere`): warm projector beam haze (`0.0 -> 0.35`) and twinkling dust motes (`0.0 -> 0.55`,
  smoothed 1.5 s by `playback.playing`, `follow_picture` true) emerging from the tabletop 16 mm projector lens at
  `[-0.885, 0.915, -1.202]` onto the portable linen screen.
- **The weather** (`weather`): `falls` snow, 850 drifting snowflakes outside the left window (`x` -9.5..-2.35, wind
  `[-0.28, 2.2]` so every flake stays strictly outside the hull), bound to the live `Snowfall` setting (`Light snow` /
  `Heavy snow` / `Clear night`, 12 s transition).
- **The presentation** (`presentation`): subtle 1929 16 mm home-print film stage (`source` film, `weave` 0.35, `dust`
  0.18, `flicker` 0.25, `hotspot` 0.3), live-controlled by the `Film print` setting (`1929 home print` / `Clean picture`).
- **The light** (`light`): warm incandescent reading sconces `[1.0, 0.82, 0.54]`, spill 0.36, baked fill 0.14.
- **The sky** (`sky`): latitude 46.5, winter day 18, southbound (`facing` 180) so the left panoramic window looks directly
  east (`glow_bearing` 96). Starts at deep starry winter midnight (`hour` 1.5, `dusk` 1.0) with a bright gibbous winter
  Moon (`moon` 0.92, bearing 108, altitude 18.5, phase 0.82, size 1.85), subtle Milky Way (`0.45`) and thin high winter
  clouds (`0.16`). Over the final third of the film (`0.66 -> 1.0`), `dusk` lifts smoothly to `0.12`, bathing the snow,
  trees and ridges in golden-rose eastern alpine dawn (`twilight_zenith` `#1c2e5a`, `twilight_horizon` `#e08e72`, `glow`
  `#ff9e5e`, `afterglow` 0.8, `belt_colour` `#c46c88`).
- **The alpine line** (`passing`, id `alps`): forward at 3.8 m/s, `light` 1.2, cabin glow 0.55 in `#ffca85` reaching
  12 m out, mist `#3a4c68`, spill 0.28.

### The alpine line's cross-section

Metres to the left of the track (the right corridor wall has no exterior windows); heights are over the compartment
floor (eyes at 1.2 m, snow trackbed at -1.45 m).

| Side | From | To | What |
|---|---|---|---|
| left | 0.0 | 32.0 | flat trackside & valley-floor `snow` strip (`#cad4e6`, -1.45 to -1.35 m) |
| left | 32.0 | 175.0 | rising alpine valley `snow` slope (`#bcc9de`, -1.35 to 2.4 m) |
| left | 18.0 | 38.0 | frosted silver `birch` trees, 42 on a 260 m loop, feet at -1.4 |
| left | 19.0 | 44.0 | snow-capped alpine `pine` trees, 72 on a 280 m loop, size 1.05, feet at -1.4 |
| left | 44.0 | 76.0 | warm-windowed mountain `cottage` chalets, 8 on a 340 m loop, seeming 1.5 times further |
| left | 46.0 | 88.0 | dense mid-valley spruce `pine` belt, 90 on a 320 m loop, seeming 1.8 times further, size 1.3 |
| left | 72.0 | 128.0 | distant twinkling valley `lights`, 90 on a 320 m loop, seeming 6 times further |
| left | 108.0 | 108.0 | foreground alpine foothill `ridge` (`#495a78`), 300 m loop, seeming 8 times further, size 0.72 |
| left | 146.0 | 146.0 | high snow-blue alpine peak `ridge` (`#7e8fab`), 336 m loop, seeming 14 times further, size 1.55 |

### Along the route

| Place | What | Side |
|---|---|---|
| 0.0 | departure snow-roofed alpine `station`, 14.5 m off, foot at -1.45 | left |
| 0.0, 48 m ahead | outbound emerald-lit semaphore `signal`, 15.5 m off, foot at -1.45 | left |
| 0.48 | sleeping snowbound wayside `station`, 15.0 m off, foot at -1.45 | left |
| 1.0, 52 m before | approach emerald-lit semaphore `signal`, 15.5 m off, foot at -1.45 | left |
| 1.0 | rosy dawn-lit arrival alpine `station`, 14.5 m off, foot at -1.45 | left |

## Night into dawn

- **Tracks** (by `film.progress`): `sky.dusk` held at 1.0 through midnight until 0.66, then lifting smoothly through
  0.62 (0.80) and 0.28 (0.92) to 0.12 at arrival (smoothed 0.5 s); `sky.hour` turning from 1.5 to 5.5 (1 s); `alps.mist`
  shifting gently from 0.14 to 0.10, 0.16, 0.22 at pre-dawn and 0.15 on arrival (0.5 s). Timeline: 8 s start, 6 minutes
  of credits.
- **Cues:**
  - `dim` when `starting`: house reading sconces to 0.10, corridor door frosted glow (`fittings.glow`) to 0.35, exterior
    cabin glow (`alps.glow`) to 0.22 over 5 s; the sapphire ceiling night lamp holds its glow via `cove_floor` 0.65.
  - `departure_whistle` when `starting` (requires the pre-show ritual setting): sounds the distant steam train whistle.
  - `lights_up` in the pre-show and at the end: reading sconces to 1.0, corridor and exterior glow released over 4 s.
  - `arrival_whistle` once `journey.progress` passes 0.92 for 2 s (7200 s cooldown): sounds the arrival whistle as dawn
    breaks over the station.
- **Room settings:**
  - `night_lamp` (`Night lamp`: Sapphire blue, Warm amber, Off; default Sapphire blue — drives `fittings.cove_colour`
    and `fittings.cove`).
  - `snowfall` (`Snowfall`: Light snow, Heavy snow, Clear night; default Light snow — drives `weather.mode`).
  - `film_print` (`Film print`: 1929 home print, Clean picture; default 1929 home print — drives `presentation`).

## Comfort

Measured by `test_room_night_sleeper_1929.gd` at the fastest the journey goes: 3.8 m/s x (1 + `CATCH_UP`) = 4.37 m/s,
slowed by `seems`. The limits are 3 m and 20 degrees a second (`docs/environments/checks.md`).

| What | Side | Its foot | Nearest | Degrees a second |
|---|---|---|---|---|
| band 0, pine | left | 19.0 | 15.85 m | 15.8 |
| band 1, birch | left | 18.0 | 15.76 m | 15.9 |
| band 2, pine (seems 1.8) | left | 46.0 | 42.10 m | 3.3 |
| band 3, cottage (seems 1.5) | left | 44.0 | 40.87 m | 4.1 |
| band 4, lights (seems 6) | left | 72.0 | 72.00 m | 0.6 |
| band 5, ridge (seems 8) | left | 108.0 | 108.00 m | 0.3 |
| band 6, ridge (seems 14) | left | 146.0 | 146.00 m | 0.1 |
| landmark 0, station | left | 14.5 | 14.50 m | 17.3 |
| landmark 1, signal | left | 15.5 | 14.23 m | 17.6 |
| landmark 2, station | left | 15.0 | 15.00 m | 16.7 |
| landmark 3, signal | left | 15.5 | 14.23 m | 17.6 |
| landmark 4, station | left | 14.5 | 14.50 m | 17.3 |

The single left panoramic window stands over 20 degrees clear of `FLOW_CLEAR_DEG` around the picture (`flow_clear()`), the
compartment never tilts or sways, and the snowfall and 16 mm beam stay comfortably inside the blend-layer and particle
budgets.

## Sound

- `acoustics` `small_room` (`rt60` 0.32, `wet` 0.12) for the room's beds. The document's film acoustics: reflect
  [0.34, 0.34, 0.18, 0.32, 0.28, 0.26], rt60 0.28 s, wet 0.14, late 0.48.
- `sound_bed` `rails` (`rail_joints`) below the compartment floor at [0.0, -0.8, 0.4], `reach` 4.5, `gain_db` -1,
  `film_db` -10, `pitch` 0.88; `level` follows `journey.speed` from 0.0 to 1.0, smoothed 2 s.
- `sound_bed` `projector` (`projector`) at the tabletop 16 mm projector [-0.98, 0.9, -1.08], `reach` 2.8, `gain_db` -5,
  `film_db` -10, `pitch` 0.92; `level` follows `playback.playing` from 0.0 to 0.85, smoothed 1.5 s.
- `sound_bed` `wind` (`wind`) outside the left window at [-2.6, 1.35, -0.2], `reach` 4.5, `gain_db` -3, `film_db` -10,
  `pitch` 0.86.
- `sound_bed` `whistle` (`train_whistle`) ahead along the locomotive line at [-1.5, 2.5, -18.0], `reach` 25, `gain_db`
  -2, `film_db` -12; played by `departure_whistle` and `arrival_whistle`.
- Measured by `test_room_night_sleeper_1929.gd`: pre-show -56.1 dBFS RMS (peak -42.6), under a film at the reference
  -67.7 dBFS (the target -38.0, the film -20.0).
- Measured by `test_room_acoustics.gd`: box 2.6 x 2.6 x 4.2, rt60 0.28, wet 0.14, late 0.48 | C80 58.6 dB,
  reverb/direct -37.2 dB, T20 0.23 s, alpha 0.28.

## Measured

By `test_room_night_sleeper_1929.gd` (63/63 checks passed, headless and Vulkan Forward Mobile / lavapipe): 27 draws,
39,196 triangles, 0 live lights, 850 snow particles, 8.2 MB of textures, lightmap atlas (252, 204). All within budget
(38 draws, 120,000 triangles, 0 lights, 80 MB textures).

## Not done yet

On the headset: not run.
