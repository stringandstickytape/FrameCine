# Back seat 2004

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

`app/environments/back_seat_2004.env.json` (Journeys, Road, built by **Gemini 4 Neon Extra High**), tested by
`app/tests/test_room_back_seat_2004.gd`. The twelfth of the Journeys: the cozy, rain-streaked back seat of a 2004 family
car cruising down a late-night motorway. Two empty slate-grey velour front bucket seats flank the centre corridor,
framing a glowing 2004 dashboard with ice-blue and amber dials, a 3-spoke steering wheel, a hooded `23:14` digital
stereo clock, illuminated circular climate control knobs and a leather-booted gearstick. Overhead hangs a brushed-silver
clamshell flip-down portable LCD screen with courtesy dome map lights; beside the viewer on the rear bench sits a
draped wool tartan blanket, soft travel cushions, a zipped disc carry-case and classic wired headphones. All four side
car windows carry wind-driven raindrops that crawl sideways aft at motorway speed and drip vertically when stopped at
motorway services. The journey is as long as the film (`docs/environments/passing.md`).

## The parts

- **The car cabin** (`cabin`, id `car`; `docs/environments/cabin.md`): 1.78 m wide at the floor, side walls 1.46 m high
  leaning inward 11.0 degrees for an authentic automotive greenhouse taper, an arched headliner roof rising 0.16 m
  (1.62 m at the crown), running from the front cowl bulkhead at z -2.15 to the rear tailgate at z 0.95 (3.10 m long,
  centred at x 0.0 so the viewer sits snugly in the middle of the back seat). Two rounded car windows a side at z -1.10
  and z 0.10 (`bay_pitch` 1.20), each 0.86 m wide and 0.52 m high, sill 0.78 m up, corner radius 0.12 m, 0.16 m door
  reveal thickness, dark rubber window gasket frames (`frame_width` 0.045, `frame_depth` 0.018), and `window_glass`
  false so `weather.panes` draws the drifting rain glass in a single draw without double blend layers. Dark charcoal
  lower door cards (`dado_height` 0.78), woven grey headliner and pillars (`melange_fabric`), deep charcoal carpet
  floor (`plush_carpet`), and `seating` none (`seat_model` none). The flip-down 16:9 portable LCD screen is 0.72 m wide
  and 0.405 m high, centred at [0.0, 1.2675, -0.98] (`screen_frame` false).
- **The 2004 family car fittings** (`kit`, id `fittings`; `kit/back_seat_2004.gd`):
  - `car_2004_cabin`: brushed-silver clamshell roof-mounted flip-down portable LCD housing with twin barrel hinges,
    ceiling console pod, recessed side disc slot, five tactile silver lower transport buttons, speaker grilles, glowing
    standby LED (`PieceWindows`), twin courtesy map lights and rear dome lamp (`PieceLamps`, house group, two warm
    halogen bake lights), ceiling grab handles, and B-/C-pillar trim with seatbelt straps; two empty contoured slate-grey
    velour front bucket seats with chrome headrest stalks, tall headrests and seatback map pockets holding a paperback
    and a folded road atlas; curved soft-touch 2004 dashboard with hooded driver instrument binnacle, chrome-ringed
    backlit speedometer and rev-counter dials (`PieceCove`, live `Dash glow` setting, `cove_floor` 0.86) with amber
    needles (`PieceWindows`), 3-spoke leather steering wheel and column stalks, brushed-silver centre console stack with
    hooded `23:14` digital LCD clock (`PieceDisplay`), twin air vents, backlit CD/radio head unit, red-amber hazard
    button, three illuminated circular HVAC climate knobs, centre tunnel with leather-booted gearstick, handbrake,
    cupholders and travel mug, raked dark glossy night windscreen with silhouetted wipers, hanging interior rear-view
    mirror, folded sun visors, and moulded two-tone door cards with armrests, silver levers, glowing amber
    electric-window switches (`PieceWindows`) and stowed water bottles.
  - `car_2004_props`: contoured plush rear bench seat and reclined backrest with three headrests (no physics box within
    0.45 m of the seat at the origin), undulating draped woven wool tartan blanket (`tartan_blanket` procedural texture)
    with warm fringe over the left rear seat beside an oatmeal travel cushion, a navy corner pillow, zipped portable
    disc carry-case and classic silver-and-black over-ear headphones on the right seat, and a rear carpeted parcel shelf
    holding a folded rain umbrella and spare tartan throw under dark tailgate glass with heated defroster lines.
- **The presentation** (`presentation`): early-2004 portable LCD panel (`display` panel, subtle pixel grid, mild
  backlight bleed and off-axis tint, `tube` 1.7778, `starts_off` true), switching on smoothly with the film and
  live-bound to `Car audio` (`speaker` none or `telly`).
- **The weather** (`weather`): `mode` bound to `Rain` (`Steady rain` / `Drizzle` / `Passing showers` / `Dry night`),
  700 falling raindrops in two areas strictly outside the car body (`|x| >= 1.55 m`, wind `[0.0, 2.8]` blowing aft with
  zero crosswind so zero drops enter the cabin), and 4 merged side-window `panes` in one draw with `pane_drift` bound
  to `journey.speed` (`0.0..1.85`, smoothed 2 s) so raindrops crawl sideways aft on the motorway and drip vertically
  when stopped.
- **The light** (`light`): warm halogen interior dome lamps `[1.0, 0.86, 0.64]`, spill 0.48, baked fill 0.14.
- **The sky** (`sky`): latitude 52.5, day 305, facing 210 degrees, 21:48 into midnight, rain-night clouds (`clouds`
  0.55) lit warmly from below by motorway sodium skyglow (`cloud_glow` `#ff8c3a`, `cloud_glow_level` 0.42), and a
  veiled gibbous Moon (`moon` 0.46) peeking through breaks out the left windows.
- **The motorway** (`passing`, id `motorway`): forward at 6.0 m/s, damp dark `asphalt` carriageway (`0..16 m`) and wet
  countryside `grass` (`16..175 m`) at -0.35 m, distant warm sodium `highway_lamp` columns, dark-blue reflective
  direction `gantry` signs, silhouetted verge `tree` lines, distant village `lights`, dark horizon `ridge` hills, and
  floodlit motorway `services` at departure (`0.0`), mid-way (`0.5`) and arrival (`1.0`).

## The motorway's night

- **Tracks** (by `film.progress`): `sky.dusk` from 0.96 to 1.0 at 0.20 (smoothed 0.5 s); `sky.hour` from 21.8 to 23.9
  over the film (1 s); `motorway.mist` shifting gently between 0.16 and 0.26 through rainy motorway patches (0.5 s).
- **Cues:**
  - `dim` when `starting`: house lamps to 0.10, road glow to 0.18 over 5 s, and `presentation.switch_on` (dashboard
    dials and climate controls stay glowing via `cove_floor` 0.86).
  - `lights_up` in the pre-show and at the end: house lamps to 1.0, road glow released over 4 s, and
    `presentation.switch_off`.
- **Room settings:**
  - `rain` (`Rain`: Steady rain, Drizzle, Passing showers, Dry night; default Steady rain).
  - `dash_glow` (`Dash glow`: Ice blue & amber, Warm emerald, Dim; default Ice blue & amber).
  - `car_audio` (`Car audio`: Full cinema, Small screen speaker; default Full cinema).

## Comfort

Measured by `test_room_back_seat_2004.gd` at the fastest the journey goes: 6.0 m/s x (1 + `CATCH_UP`) = 6.90 m/s,
slowed by `seems`. The limits are 3 m and 20 degrees a second (`docs/environments/checks.md`).

| What | Side | Its foot | Nearest | Degrees a second |
|---|---|---|---|---|
| band 0, highway_lamp | both | 25.0 | 24.13 m | 16.4 |
| band 1, gantry | both | 27.0 | 22.14 m | 17.9 |
| band 2, tree (seems 1.5) | both | 38.0 | 30.25 m | 8.7 |
| band 3, lights (seems 5.5) | both | 78.0 | 78.00 m | 0.9 |
| band 4, ridge (seems 11) | both | 132.0 | 132.00 m | 0.3 |
| landmark 0, services | left | 24.0 | 24.00 m | 16.5 |
| landmark 1, services | right | 25.0 | 25.00 m | 15.8 |
| landmark 2, services | left | 24.0 | 24.00 m | 16.5 |

The test also checks that nothing goes by within `FLOW_CLEAR_DEG` of the picture from the seat (`flow_clear()`), that
the car never pitches or rolls, that `pane_drift` scales with `journey.speed`, and that falling rain areas stay
strictly outside the cabin.

## Sound

- `acoustics` `vehicle` (`rt60` 0.16, `wet` 0.08) for the room's beds. The document's film acoustics: reflect
  [0.22, 0.22, 0.12, 0.24, 0.20, 0.18], rt60 0.18 s, wet 0.10, late 0.35.
- `sound_bed` `engine` (`car_motorway`) forward at [0.0, 0.35, -2.0], `reach` 4.5, `gain_db` -2, `film_db` -10; `level`
  follows `journey.speed` from 0.22 (soft idle) to 1.0 (motorway cruise and wet tarmac), smoothed 2 s.
- `sound_bed` `rain` (`rain_glass`) around the windows at [0.0, 1.08, -0.3], `radius` 1.5, `reach` 3.5, `gain_db` -2,
  `film_db` -10; `level` follows `weather.rain`, smoothed 1.5 s.
- `sound_bed` `wind` (`wind`) at the roof header [0.0, 1.65, -1.2], `reach` 3.5, `gain_db` -5, `film_db` -12, `pitch`
  1.08; `level` follows `journey.speed` from 0.25 to 0.85, smoothed 2 s.
- Measured by `test_room_back_seat_2004.gd`: pre-show -50.6 dBFS RMS (peak -28.1), under a film at the reference -64.6
  dBFS RMS (`test_room_acoustics.gd`: C80 74.2 dB, reverb/direct -42.6 dB, T20 0.15 s, alpha 0.30).

## Measured

By `test_room_back_seat_2004.gd` under Vulkan Forward Mobile (`lavapipe`, `61 checks, all passed`):

- Draws: 26 (limit 38).
- Triangles: 33,156 (limit 120,000).
- Live lights: 0.
- Particles: 700.
- Textures: 8.2 MB, lightmap atlas 136 x 120.

## Not done yet

On the headset: not run.
