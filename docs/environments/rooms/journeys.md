# Journeys: the fifteen rooms

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

The Journeys category as it was proposed on 2026-11-09: fifteen rooms that travel, where the journey takes as long
as the film. You board in the pre-show, leave when the film starts, and arrive with the credits. Nine are built; this
page keeps the other six, so the list is not only in a conversation. The built rooms have pages of their own.

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
| 8 | The Salon, 1870 | not built | a Victorian submarine's velvet salon. A great iris window opens as the film starts, and kelp forests glide by | the Bathysphere's whole sea (`fish`, `ray`, `whale`, seabed, caustics) | an iris window; kelp and rocks as passing shapes; the sea's life going by with the journey |

### Air

| # | Room | State | What it is | Reuses | Still needs |
|---|---|---|---|---|---|
| 9 | Airship, 1931 | **built** ([`airship_1931.md`](airship_1931.md), Gemini 4 Neon Extra High) | as built: a 1931 rigid airship promenade lounge with `-12°` outward-leaning panoramic windows, exposed brushed-duralumin triangular lattice ring-girders and trusses, Art Deco proscenium with torchières, aft navigation chart table and modernist clock, forward-port self-playing featherweight brushed-aluminium baby grand piano with 61 animated keys, endless moonlit cloud sea, cloud banks, sleeping coastal town lights and illuminated mooring masts | `cabin` (`lean`), `kit`, `music` (`piano`), `passing` (`cloud_deck`), `sky` | nothing |
| 10 | Jet, 1964 | **built** ([`jet_1964.md`](jet_1964.md), Gemini 4 Neon Extra High) | as built: a 1964 first-class transpolar narrow-body jet cabin — small high oval fuselage windows, ceiling-mounted 16 mm twin-reel projector with beam haze onto a pull-down bulkhead screen, backlit seatbelt sign, burnt-orange recliners with flip-up tray tables and air-tube headset armrests, optional tinny air-tube audio (`speaker: "window"`), moonlit cloud sea, 1960s jetport terminals and emerald-violet Aurora Borealis blooming in quiet scenes | `cabin`, `seats`, `kit`, `atmosphere`, `passing` (`cloud_deck`), `presentation`, `sky` (`aurora` on `film.quiet`) | nothing |

### Road

| # | Room | State | What it is | Reuses | Still needs |
|---|---|---|---|---|---|
| 11 | Coach trip, 1988 | not built | an overnight coach: swirly moquette, a telly behind the driver's drawn curtain, a rented tape, a services stop at the intermission | `rewinder_1987`, `vcr`, `tape_load`, `cabin` rows | a stop at the intermission (the journey only holds on a pause today); road lamps and signs that pass close (see "The limit on speed") |
| 12 | Back seat, 2004 | not built | the back of the family car on a night motorway: a flip-down screen, the dash glowing between tall headrests, rain crawling sideways on the glass, a blanket. The Pillow Fort's cousin | the `vehicle` dash, the rain pane | a car's cabin (the `cabin` builder makes rooms, not a car's inside); the same close lamps |

### Space

| # | Room | State | What it is | Reuses | Still needs |
|---|---|---|---|---|---|
| 13 | Sky lift | not built | a climber car from an ocean platform to orbit. The film is the climb: through the cloud deck, blue to black, Earth's curve by the end. Only far scenery: the biggest view with the least flow | `sky`, `earth_detail` | a journey that goes up, not along: the sky and Earth changing by `film.progress`, not the `passing` system |
| 14 | Moon ferry | not built | Earth shrinking astern and the Moon growing ahead, landing at the Crater | `earth_detail`, `vacuum` acoustics, the Crater's ground | `earth_size` and `moon_size` as live parameters; the landing |
| 15 | Mars train | not built | a pressurised rover-train across a rust plain: the blue sunset Mars really has, far dust devils, a domed base at night | `lunar_surface` and `lunar_dome` in new colours, sand and stone as ground kinds | a sky for Mars (its colours, its small Sun); dust devils and the base as shapes |

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
6. Next: The Salon, 1870 (submarine iris window and gliding marine life) or the Road rooms once the headset comfort test settles the near-scenery speed limit.
7. The space rooms last: they need a different kind of journey.

## Shared test helper

`app/tests/room_journey.gd` holds the shared checks for journey rooms (`test_room_narrowboat.gd`,
`test_room_showboat.gd`, `test_room_liner_1936.gd`, `test_room_night_ferry_1994.gd`,
`test_room_cinema_coach_1935.gd`, `test_room_night_sleeper_1929.gd`, `test_room_dome_car_1955.gd`,
`test_room_airship_1931.gd`, `test_room_jet_1964.gd`).
