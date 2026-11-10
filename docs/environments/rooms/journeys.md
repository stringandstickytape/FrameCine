# Journeys: the fifteen rooms

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

The Journeys category as it was proposed on 2026-11-09: fifteen rooms that travel, where the journey takes as long
as the film. You board in the pre-show, leave when the film starts, and arrive with the credits. Two are built; this
page keeps the other thirteen, so the list is not only in a conversation. The built rooms have pages of their own.

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
| 1 | Cinema coach, 1935 | not built | an express carriage fitted as a newsreel cinema: paired tip-up seats, a back-projection screen at the end, swaying rack lamps, a tunnel | `worn_print`, the `train` sound, plush `seats`, `cabin` | rail-joint sound; telegraph poles and a signal as shapes; a tunnel (the scenery has no way to go dark for a stretch) |
| 2 | Night sleeper, 1929 | not built | a marquetry compartment with a blue night lamp and a home projector on the folding table. Moonlit snow, a sleeping station gliding by, mountains at dawn | `birches` with `frost`, `weather` snow, the Moon, snow as a ground kind | a compartment (one window wall, a door to the corridor); a station as a landmark; dawn (the sky's tracks only go from dusk to night so far) |
| 3 | Dome car, 1955 | not built | a glass-roofed observation car crossing the desert under the Milky Way | the drive-in's `mesas`, `cacti`, `milky_detail`, sand as a ground kind | a glazed roof in the `cabin`; mesas and cacti as passing shapes |

### Water

| # | Room | State | What it is | Reuses | Still needs |
|---|---|---|---|---|---|
| 4 | Liner, 1936 | not built | an ocean liner's moderne lounge, the Moon's path on the sea, harbour lights at the end. The ship never rolls; the drapes sway instead | the Streamline kit, `motion` sway, the Moon's road (built for the Showboat) | open sea to the horizon on both sides (water is a strip beside the way today); a harbour as landmarks |
| 5 | Showboat, 1927 | **built** ([`showboat_1927.md`](showboat_1927.md)) | as built: a floating theatre in white and gold on a wide river, the near bank's trees and a levee town, a steamer at anchor, a lamp-lit landing | `cabin`, `passing`, `kit` | nothing. The proposal's swamp banks with fireflies and its steam organ that plays itself were not built |
| 6 | Narrowboat | **built** ([`narrowboat.md`](narrowboat.md)) | as built: a canal boat at walking pace, a stove, reeds, willows, bridges, mist, a wharf. The gentlest one, and the comfort baseline | `cabin`, `passing`, `kit` | nothing. The proposal's lock and tunnel were not built |
| 7 | Night ferry, 1994 | not built | the video lounge: reclining seats, a telly on a bracket, salt-streaked windows, a lighthouse's slow beam | `nightowl_1993`, `hull_creak`, `deep_hum`, the rain pane | open sea, as the Liner; a lighthouse as a landmark whose light turns; a television for the picture in a `cabin` |
| 8 | The Salon, 1870 | not built | a Victorian submarine's velvet salon. A great iris window opens as the film starts, and kelp forests glide by | the Bathysphere's whole sea (`fish`, `ray`, `whale`, seabed, caustics) | an iris window; kelp and rocks as passing shapes; the sea's life going by with the journey |

### Air

| # | Room | State | What it is | Reuses | Still needs |
|---|---|---|---|---|---|
| 9 | Airship, 1931 | not built | a promenade lounge with slanted windows over moonlit cloud and a sleeping coast, a featherweight piano that plays itself | `sky` clouds, `music` piano, `cabin` walls that lean out | scenery far below the way (cloud tops, a coast's lights): the ground is at the way's height today |
| 10 | Jet, 1964 | not built | the first inflight films: a 16 mm projector in the ceiling, a pull-down screen at the bulkhead, air-tube headset sound as a "tinny" setting, aurora over the pole in quiet scenes | `worn_print`, `presentation.speaker`, `aurora` on `film.quiet` | cloud below, as the Airship; small high windows; an engine drone |

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
3. Next, by the proposal: the Night sleeper (the fastest near scenery, so the hardest test of the limits). The Liner
   is the cheapest next room: the Moon's road and the moderne kit exist, and it needs only open sea.
4. The space rooms last: they need a different kind of journey.

## Before a third room

`test_room_narrowboat.gd` and `test_room_showboat.gd` are copies of each other. Make the shared part a helper first.
