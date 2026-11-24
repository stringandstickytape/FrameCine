# Journeys: the fifteen rooms

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

The Journeys category as it was proposed on 2026-11-09: fifteen rooms that travel, where the journey takes as long
as the film. You board in the pre-show, leave when the film starts, and arrive with the credits. All fifteen are built;
each room has a page of its own.

Every room is empty, as the Coronation room is: no people. Curtains and headrests hide a driver's place. No real
place is named, and no maker's name or badge.

## How a journey maps to the film

| The film | The journey |
|---|---|
| pre-show | standing at the platform, the wharf, the gate |
| starting | departure |
| paused | held at a signal |
| intermission | a stop |
| credits | slowing in |
| ended | arrived, lamps up |

The speed outside does not depend on the film's length: a short episode and a three-hour film go at the same pace,
and the route's stages (dusk, towns, mountains, dawn) are placed by `film.progress`. What must stand together at an
end is set out in metres (a landmark's `ahead`, [`passing.md`](../passing.md)).

## The list

State on 2026-11-10. "Reuses" is what the proposal counted on from the engine as it then was. "Still needs" is the
lead's estimate of what the engine does not have yet; it is an estimate until the room is designed.

### Rail

| # | Room | State | What it is | Reuses | Still needs |
|---|---|---|---|---|---|
| 1 | Cinema coach, 1935 | **built** ([`cinema_coach_1935.md`](cinema_coach_1935.md), Gemini 4 Neon Extra High) | as built: a 1935 mahogany newsreel express carriage — 20 claret seats on Art Deco runner carpet, curved brass-hooded screen cove with sunburst crest, slotted brass speaker apron, diamond-netting luggage racks, holland blinds with crimson tassels, 8 swaying opal tulip rack lamps, telegraph poles, semaphore signals, stations and a pitch-dark mid-reel railway tunnel | `cabin`, `kit`, `motion`, `passing`, `presentation`, `sky` | nothing |
| 2 | Night sleeper, 1929 | **built** ([`night_sleeper_1929.md`](night_sleeper_1929.md), Gemini 4 Neon Extra High) | as built: an intimate Art Deco walnut-and-mahogany marquetry sleeping compartment with a single left panoramic window, glowing frosted sliding corridor door, claret lower berth and stowed upper berth, sapphire ceiling night lamp, folding table with twin-reel 16 mm home projector and dusty beam onto a roller screen, falling snow, snowbound alpine pines, birches and stations, turning to golden-rose alpine dawn with the credits | `cabin`, `kit`, `atmosphere`, `weather`, `passing`, `presentation`, `sky` | nothing |
| 3 | Dome car, 1955 | **built** ([`dome_car_1955.md`](dome_car_1955.md), Gemini 4 Neon Extra High) | as built: an upper-deck stainless-steel observation dome car with a curved glazed roof open to desert sunset, the full Milky Way, meteors and crescent Moon overhead, sculpted coral observation recliners, atomic saucer table lamps, turquoise dome valances, red-rock desert mesas, saguaro cacti, water towers and desert stations | `cabin` (`glazed_roof`), `seats`, `kit`, `passing`, `sky` | nothing |

### Water

| # | Room | State | What it is | Reuses | Still needs |
|---|---|---|---|---|---|
| 4 | Liner, 1936 | **built** ([`liner_1936.md`](liner_1936.md), Gemini 4 Neon Extra High) | as built: an ocean liner's Art Deco lounge crossing at night — stepped cove-lit proscenium with torchières, walnut pelmets, working sunburst aft clock, swaying velvet drapes (the ship never rolls), open sea to the horizon on both sides, the Moon's road, a passing sister liner, breakwater lighthouses and lit piers | `cabin`, `passing`, `kit`, `motion` | nothing |
| 5 | Showboat, 1927 | **built** ([`showboat_1927.md`](showboat_1927.md)) | as built: a floating theatre in white and gold on a wide river, the near bank's trees and a levee town, a steamer at anchor, a lamp-lit landing | `cabin`, `passing`, `kit` | nothing. The proposal's swamp banks with fireflies and its steam organ that plays itself were not built |
| 6 | Narrowboat | **built** ([`narrowboat.md`](narrowboat.md)) | as built: a canal boat at walking pace, a stove, reeds, willows, bridges, mist, a wharf. The gentlest one, and the comfort baseline | `cabin`, `passing`, `kit` | nothing. The proposal's lock and tunnel were not built |
| 7 | Night ferry, 1994 | **built** ([`night_ferry_1994.md`](night_ferry_1994.md), Gemini 4 Neon Extra High) | as built: a 1994 cross-Channel ferry's video lounge — Pullman recliners with linen antimacassars and tray tables, a ceiling-bracketed 4:3 CRT television and locked VCR cage flashing `12:00`, salt-streaked storm windows with wind-driven rain, a slow rotating volumetric lighthouse beam, passing container freighters and floodlit Ro-Ro ferry terminals | `cabin`, `seats`, `kit`, `passing`, `weather`, `presentation` | nothing |
| 8 | The Salon, 1870 | **built** ([`salon_1870.md`](salon_1870.md), Gemini 4 Neon Extra High) | as built: a 1870 Victorian submarine velvet salon in crimson velvet and mahogany with two monumental bolted-brass circular viewports housing animated 10-blade mechanical brass iris shutters (`c.halls`), diamond-lattice bookcases, specimen credenzas, brass chronometer, compass binnacle, ballast manifold, and a 21-pipe aft salon organ; irides spiral wide open as the engine-room telegraph double-rings, revealing caustics-lit `seabed`, swaying `kelp`, `sea_rock`, schooling `fish`, bioluminescent `jelly`, `ray`, rare `whale`, a `sunken_wreck` and glowing `hydro_vent` chimneys | `cabin`, `seats`, `kit`, `passing`, `life`, `music` (`organ`), `sky` | nothing |

### Air

| # | Room | State | What it is | Reuses | Still needs |
|---|---|---|---|---|---|
| 9 | Airship, 1931 | **built** ([`airship_1931.md`](airship_1931.md), Gemini 4 Neon Extra High) | as built: a 1931 rigid airship promenade lounge with `-12°` outward-leaning panoramic windows, exposed brushed-duralumin triangular lattice ring-girders and trusses, Art Deco proscenium with torchières, aft navigation chart table and modernist clock, forward-port self-playing featherweight brushed-aluminium baby grand piano with 61 animated keys, endless moonlit cloud sea, cloud banks, sleeping coastal town lights and illuminated mooring masts | `cabin` (`lean`), `kit`, `music` (`piano`), `passing` (`cloud_deck`), `sky` | nothing |
| 10 | Jet, 1964 | **built** ([`jet_1964.md`](jet_1964.md), Gemini 4 Neon Extra High) | as built: a 1964 first-class transpolar narrow-body jet cabin — small high oval fuselage windows, ceiling-mounted 16 mm twin-reel projector with beam haze onto a pull-down bulkhead screen, backlit seatbelt sign, burnt-orange recliners with flip-up tray tables and air-tube headset armrests, optional tinny air-tube audio (`speaker: "window"`), moonlit cloud sea, 1960s jetport terminals and emerald-violet Aurora Borealis blooming in quiet scenes | `cabin`, `seats`, `kit`, `atmosphere`, `passing` (`cloud_deck`), `presentation`, `sky` (`aurora` on `film.quiet`) | nothing |

### Road

| # | Room | State | What it is | Reuses | Still needs |
|---|---|---|---|---|---|
| 11 | Coach trip, 1988 | **built** ([`coach_trip_1988.md`](coach_trip_1988.md), Gemini 4 Neon Extra High) | as built: a 1988 overnight express touring coach with swirly `moquette_88` carpet, drawn burgundy driver's curtain, overhead ceiling-mounted 4:3 CRT television and top-shelf video recorder flashing `12:00` beside rented tape cases, recliners with cream linen antimacassars and tray tables, cream tied-back curtains, red break-glass hammers, wind-drifting rain panes, wet `asphalt` motorway, distant `highway_lamp` and `gantry` silhouettes, and a mid-film intermission stop beside lit motorway `services` | `cabin`, `seats`, `kit`, `passing`, `weather`, `presentation`, `sky` | nothing |
| 12 | Back seat, 2004 | **built** ([`back_seat_2004.md`](back_seat_2004.md), Gemini 4 Neon Extra High) | as built: the rain-streaked back seat of a 2004 family car on a night motorway — roof clamshell flip-down portable LCD screen, glowing ice-blue and amber 2004 dashboard dials, `23:14` clock and climate knobs framed between empty front headrests with map pockets, draped `tartan_blanket`, cushions, disc case and wired headphones on the rear bench, sideways-drifting raindrops on all four side panes, damp `asphalt`, distant motorway lamps/gantries and floodlit `services` | `cabin`, `kit`, `passing`, `weather`, `presentation`, `sky` | nothing |

### Space

| # | Room | State | What it is | Reuses | Still needs |
|---|---|---|---|---|---|
| 13 | Sky lift | **built** ([`sky_lift.md`](sky_lift.md), Gemini 4 Neon Extra High) | as built: a sleek orbital elevator climber car with curved glazed roof ascending vertically (`passing.facing: "up"`) along its glowing carbon-ribbon tether from an equatorial `ocean_platform` through a billowing `cloud_bank` deck into black 360° star-filled space (`sky.space_mix`, `sky.all_sky`), as Earth's curved blue limb (`earth_detail` live `earth_size`/`earth_altitude`/`earth_alpha`) emerges beneath you before docking at the glowing `orbital_station` | `cabin` (`glazed_roof`), `seats`, `kit`, `passing` (`facing: "up"`), `sky` (`space_mix`, `all_sky`, `earth_detail`) | nothing |
| 14 | Moon ferry | **built** ([`moon_ferry.md`](moon_ferry.md), Gemini 4 Neon Extra High) | as built: a retro-future 1968 cislunar passenger liner with wrap-around glazed canopy, crimson contour seats and twin-aisle console gliding silently (`vacuum` acoustics) through 360° starlight (`mode: "space"`, `all_sky: true`): Earth shrinks astern (`28° -> 2.2°`) while the cratered Moon grows ahead (`2.4° -> 34°`), descending onto lunar `regolith` (`ground_vis: 0 -> 1`) beside the glowing Crater `lunar_base` | `cabin` (`glazed_roof`), `seats`, `kit`, `passing` (`ground_vis`, `regolith`), `sky` (`space`, `all_sky`, live Earth & Moon) | nothing |
| 15 | Mars train | **built** ([`mars_train.md`](mars_train.md), Gemini 4 Neon Extra High) | as built: a pressurised Martian rover-train cabin crossing an iron-oxide rust `regolith` plain under the authentic pale-blue Martian sunset (`sky.sun_disc`, `sky.sun_altitude`, blue `glow`) with expedition sample rack, core canisters, airlock door and geology display; ochre `dust_devil` vortices and `mars_rock` boulders fade into clear Martian starlight before arriving at a glowing domed night colony (`mars_base`) | `cabin`, `seats`, `kit`, `passing` (`regolith`, `dust_devil`, `mars_rock`, `mars_base`), `sky` (`sun_disc`, `sun_altitude`) | nothing |

## The limit on speed

Scenery that goes by gives the feeling of moving, which is what the engine's "never the viewer" rule guards against.
The limits in `env_checks.gd` (`docs/environments/checks.md`) are: nothing crosses the eye faster than 20 degrees a
second (`FLOW_MAX_DEG`), nothing passes nearer than 3 m (`FLOW_NEAREST`), the speed changes by no more than
0.3 m/s2 (`FLOW_ACCEL`), and the Motion setting under 25 % stops the journey. A journey goes at 12 m/s at most.

So the faster a room goes, the further off its nearest scenery must be: 3.3 m at the Narrowboat's 1 m/s, 6.6 m at
the Showboat's 2 m/s, 40 m at 12 m/s. A train, a coach and a car cannot have lamps, posts or a hard shoulder
streaming by the glass; they are far scenery, weather on the pane and the cabin's own light. That shapes rooms 1, 2,
3, 11 and 12 more than anything else.

**These limits are the lead's reasoning, not measurements.** Nobody has watched a film in either built room on the
headset. That test comes before the rooms above: if 20 degrees a second is too much or too little, the limits
change first and the rooms second.

## The order

1. The Narrowboat (slowest): built.
2. The Showboat (a larger hall, twice the speed): built.
3. The Liner, 1936 (open sea, swaying drapes, maritime landmarks): built (Gemini 4 Neon Extra High).
4. Night ferry, 1994 (reuses open sea and lighthouse; adds rotating volumetric lighthouse beams, multi-pane salt-streaked rain glass, ceiling-bracketed CRT in a cabin, Ro-Ro ferry ports and freighters): built (Gemini 4 Neon Extra High).
5. Rail & Air set — Cinema coach 1935, Night sleeper 1929, Dome car 1955, Airship 1931, Jet 1964 (completes Rail and Air; adds `cabin.glazed_roof`, `sky.blackout` and live `glow_bearing`, `passing.tunnel`, `cloud_deck`, 11 rail/desert/snow/air shapes and 6 synths): built (Gemini 4 Neon Extra High).
6. Final six — The Salon 1870, Coach trip 1988, Back seat 2004, Sky lift, Moon ferry, Mars train (completes Water, Road, Space and all 15/15 Journeys; adds `sky.space_mix`, `sky.all_sky`, `sky.sun_disc`, `sky.sun_altitude`, live Earth & Moon sizing/positioning and space-mode cratered Moon, `passing.facing: "up"`, `passing.ground_vis`, `seabed`/`asphalt`/`regolith` ground kinds, 14 ocean/road/space shapes, `moquette_88`/`tartan_blanket` procedural textures and 5 synths): built (Gemini 4 Neon Extra High).

## Shared test helper

`app/tests/room_journey.gd` holds the shared checks for journey rooms (`test_room_narrowboat.gd`,
`test_room_showboat.gd`, `test_room_liner_1936.gd`, `test_room_night_ferry_1994.gd`,
`test_room_cinema_coach_1935.gd`, `test_room_night_sleeper_1929.gd`, `test_room_dome_car_1955.gd`,
`test_room_airship_1931.gd`, `test_room_jet_1964.gd`, `test_room_salon_1870.gd`,
`test_room_coach_trip_1988.gd`, `test_room_back_seat_2004.gd`, `test_room_sky_lift.gd`,
`test_room_moon_ferry.gd`, `test_room_mars_train.gd`).
