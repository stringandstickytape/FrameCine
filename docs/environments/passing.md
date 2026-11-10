# The passing system

Part of the environments engine: [`docs/environments.md`](../environments.md) has the design and says where each part is.

`scripts/env/systems/passing.gd`, with `scripts/env/systems/passing/shape_mesh.gd` (the mesh the scenery is written
into), `scripts/env/systems/passing/shapes.gd` (the shapes) and three shaders: `shaders/env_passing.gdshader`,
`env_passing_lights.gdshader`, `env_passing_ground.gdshader`. Kind `journey`; it provides `flow`.

## What it is

Scenery that goes by outside a cabin's windows. The viewer never moves (`moves_viewer` false); the scenery does.

- **The journey is as long as the film.** The cabin's place along its way (`travel`) follows the film's position:
  at the journey's speed, a minute into the film is a minute along the way.
- **A pause holds it.** The cabin slows to a stop, no faster than the comfort limit, and stays where it is.
- **A seek goes dark and moves.** The scenery fades to black, the cabin is put where the film now is, and the
  scenery comes back. Nothing jumps in sight.
- **A film of known length arrives.** With `arrive` on, the route is the film's length at the journey's speed, less
  the distance the slowing for the end saves; the cabin slows gently and stops at the route's end as the film ends.
- **A film with no length never arrives.** A live stream has no route's end: the journey goes on, and its progress
  goes by the time watched (half way after an hour), as `film.progress` does.

All the bands and landmarks are one mesh (one draw), their points of light a second, the ground a third. Nothing
is moved on the CPU: each tick sets the shaders' uniforms, and the shaders carry the scenery past.

## The way's frame

The cabin goes along the room's Z axis. With `facing` forward it goes towards -Z (the way the viewer faces); backward,
towards +Z.

| | Forward | Backward |
|---|---|---|
| along | (0, 0, -1) | (0, 0, 1) |
| across (to the right of the way it goes) | (1, 0, 0) | (-1, 0, 0) |
| up | (0, 1, 0) | (0, 1, 0) |

A point (a, y, t) of the way's frame (a across, y up, t along, ahead positive) is `across * a + up * y + along * t` in
the room's frame. The system's nodes have identity transforms in the room. A shape is written in the way's frame
about its item's foot (`shape_mesh.gd` has the vertex format).

## Parameters

| Name | Type | Default | What |
|---|---|---|---|
| `facing` | enum forward, backward | forward | which way the cabin goes |
| `speed` | float 0..12, live, motion (max 12) | 1.0 | metres a second under way |
| `arrive` | bool | true | with a film of known length, slow down and stop at the route's end |
| `bands` | list (max 10) of object | [] | the scenery that comes round (below) |
| `landmarks` | list (max 12) of object | [] | things that stand once on the route (below) |
| `ground` | list (max 12) of object | [] | strips of ground or water (below) |
| `light` | float 0..2, live, brightness | 1.0 | the scenery's light: 1 as the sky lights it |
| `sky_light` | bool | true | lit by the room's sky system (as the vista is) |
| `night` | color, live | `#1b2236` | the light without a sky system |
| `glow` | float 0..2, live, brightness | 0.6 | the cabin's own light on what passes close |
| `glow_colour` | color, live | `#ffc27a` | |
| `glow_reach` | float 1..20 | 6.0 | metres from the way's line at which the glow is gone |
| `glow_half_length` | float 0.5..30 | 3.0 | how far ahead and astern of the origin the cabin's windows reach |
| `windows` | float 0..2, live, brightness | 1.0 | the lit windows of the scenery (`ShapeMesh.M_WINDOW`) |
| `lights` | float 0..2, live, brightness | 1.0 | the scenery's points of light |
| `mist` | float 0..1, live, brightness | 0.0 | mist that takes the far scenery |
| `mist_colour` | color, live | `#3a4250` | |
| `spill` | float 0..4 | 1.0 | how much the near scenery catches the screen's light |

### A band

Many of one shape on a loop that comes round again.

| Field | Type | Default | What |
|---|---|---|---|
| `shape` | enum `Shapes.BANDS`, required | | what stands in the band |
| `side` | left, right, both | both | which side of the way |
| `near` | float 3..170 | 6 | the nearest its feet stand from the way's line |
| `far` | float 3..170 | 12 | the furthest (made at least `near`) |
| `count` | int 1..600 | 40 | how many |
| `length` | float 60..340 | 240 | the loop's length |
| `seems` | float 1..200 | 1 | how many times further off it seems than it is drawn; it goes by that much slower |
| `height` | float -20..40 | 0 | its feet's height |
| `size` | float 0.1..6 | 1 | times its natural size |
| `colour` | color | the shape's own (`Shapes.COLOURS`) | its main colour |
| `seed` | int 0..100000 | 0 | another arrangement of the same |
| `presence` | list (max 8) of [route fraction 0..1, 0..1] | [[0, 1]] | where along the route it stands, and how much of it |

A shape that stands end to end in a row (a key of `Shapes.SEGMENT`: hedge, fence, ridge) has `length` over its segment
items (rounded down; the loop is that many segments long), all at `near`; `count` does not apply. Any other shape has
`count` items, each at its own place along the loop and across from `near` to `far`, a little larger or smaller.
Where a band's presence is under 1, items drop out in their order: at 0.5, half of them show.

### A landmark

Something that stands once on the route: it comes into view ahead, passes and goes astern. `steamer` is a
sternwheel river steamer at anchor, with two deck houses, twin stacks, lit windows facing the way and six lights.

| Field | Type | Default | What |
|---|---|---|---|
| `shape` | enum `Shapes.LANDMARKS`, required | | what it is |
| `at` | float 0..1, required | | its place on the route, as a fraction |
| `side` | left, right | left | which side of the way |
| `distance` | float 3..170 | 8 | metres from the way's line |
| `height` | float -20..40 | 0 | its foot's height |
| `size` | float 0.1..6 | 1 | times its natural size |
| `colour` | color | the shape's own | its main colour |
| `seed` | int 0..100000 | 0 | another arrangement of the same |

With no route's end (a film with no length), a landmark at 0 (the place the journey starts from) is there; the others
never come.

**A landmark's clearing.** No band's item stands on the ground a landmark stands on (a hedge through a wharf's shed,
reeds through a moored boat, a willow on a bridge's road). `Shapes.clearing()` gives that ground as half its length
along the way and its nearest and furthest edge across it (signed as the way's frame is: left negative); a shape
with none gives nothing. The margins past the shape itself are for what reaches (below, `REACH`).

| Landmark | Half its length along | Across |
|---|---|---|
| `bridge` | 4.25 | both sides, out to its distance + 9 |
| `wharf` | 11.5 | its distance - 2 to its distance + 11 |
| `boat` | 8.5 x size | its distance -+ (size + 0.5) |
| `tower` | 20 x size | its distance -+ 8 x size |
| `lamp` | | none |
| `steamer` | 28 x size | its distance -+ (4.5 x size + 1) |

The scenery's shaders get them as `landmark_clear` (one a landmark), and `band_extent` for each band: how far one of
its items runs on along the way from its foot (a row's piece: its `SEGMENT` length; else 0). An item whose run along
the way overlaps a landmark's clearing and whose foot is inside it across is drawn at nothing. A band that goes by at
the landmark's pace (`seems` 1) keeps its place against it, so this holds for the whole time both are in view.

### A ground strip

| Field | Type | Default | What |
|---|---|---|---|
| `side` | left, right, both | both | which side of the way |
| `from`, `to` | float 0..175, required | | metres from the way's line |
| `height_from`, `height_to` | float -20..40 | 0 | its height at each edge |
| `kind` | water, grass, path, field, snow, sand, stone | grass | what it is |
| `colour` | color | the kind's own | water `#0c1218`, grass `#1a2414`, path `#3b362c`, field `#201c16`, snow `#c8ccd6`, sand `#4a4232`, stone `#34322e` |

A strip runs 175 m ahead and astern. It stands still; its pattern goes by.

`shape` (a band's and a landmark's), `at` (a landmark's), `from` and `to` (a strip's) are required: the schema says
`"required": true` and refuses an entry without them (`docs/environments/checks.md`, item 1). A band of scenery with
no shape is a mistake in the document, not a row of whatever the system would draw in its place. A caller that skips
the schema gets the plainest: a band of posts, a lamp at the journey's start, a strip of no width (nothing drawn).

## The journey's rules

Each tick, in this order:

1. **The film.** Its position and duration, from the player (tests: the host's `snapshot_override`), and the
   timeline's state.
2. **The Motion setting.** The host has already scaled `speed` by it; the system keeps the document's speed
   (`own_speed`) beside it. Under `FLOW_MOTION_FLOOR` the journey does not go (its cruise is 0).
3. **The route.** Going, with a film of known length and `arrive` on: the film's length at this speed, less the
   distance the slowing for the end saves (cruise squared over twice `BRAKE`), so the cabin stops at the route's end as
   the film ends. Otherwise no end. While the journey does not go, the route shown keeps its value: what is in view
   stays where it is. The target is the film's position times the speed, never past the route's end.
4. **The first tick** puts the cabin at the target, at full speed if the film is under way, else stopped.
5. **Too far from the film** (more than a minute's travel, and at least 30 m) while the journey goes: a blink starts.
6. **The speed it wants.** The cruise while the film starts, plays or is in its credits, and after it ends while the
   cabin still has its arrival to finish; else 0. Under way it may go up to `CATCH_UP` faster or slower to close on
   the target (over about 20 s of travel). Near the route's end, never faster than it can still stop in at `BRAKE`.
7. **The speed changes** towards what it wants no faster than `FLOW_ACCEL`. The cabin goes on at that speed, never
   back, never past the route's end.
8. **The blink.** The scenery goes dark over `BLINK_OUT`; at dark the cabin is put at the target with the speed it
   wants there (no catch-up); it comes back over `BLINK_IN`. The speed and travel go on as usual while it fades. A
   seek starts a blink while the journey goes (one going dark carries on; one coming back goes dark again from where
   it is).
9. **The channels.** `journey.speed`: the speed now against the document's speed (0..1). `journey.progress`: how
   far along the route, or, with no end, by the time travelled as `film.progress` goes for a film with no length.

Then the shaders' uniforms.

## The comfort limits

From `env_checks.gd` (`docs/environments/checks.md`, item 10), with the reasons beside them there.

| Limit | Constant | Here |
|---|---|---|
| the fastest anything crosses the eye, at its nearest | `FLOW_MAX_DEG` | `comfort_for()`: a band (slowed by its `seems`) or a landmark at its nearest (below) at the fastest the journey goes (`speed` x (1 + `CATCH_UP`)) |
| the nearest anything passes the line the eyes go along | `FLOW_NEAREST` | `comfort_for()`: a band's or a landmark's nearest (below). Ground nearer than this is fine: its shader holds its pattern still there |
| how fast the speed changes | `FLOW_ACCEL` | step 7; an arrival slows at half of it (`BRAKE`) |
| clear of the picture's edges, from the room's own seat | `FLOW_CLEAR_DEG` | `flow_volumes()`: the boxes the moving scenery keeps to, for `flow_clear()` |
| the Motion setting under which nothing goes by | `FLOW_MOTION_FLOOR` | step 2 |

**Comfort is judged by the nearest any part of a shape comes,** not by where its foot stands. A tree whose foot is
9 m off has a crown that reaches to 3; a moored boat's side is a metre nearer than its middle. `Shapes.nearest(shape,
size, distance, foot, eye)` gives the nearest any part of it comes to the line the eyes go along (the eyes at
`EnvChecks.EYE_HEIGHT`, 1.2 m): the least of its stem's distance and its widest part's, that one measured up to the
height it hangs at. `comfort_for()` asks it at the largest the band draws its shape (a scattered band's items are up
to `VARY.y`, 1.25 times its `size`; a row's pieces are all its size). A bridge goes over the way: its nearest is its
arch, measured at nine points from pier to pier. Every other shape's lengths are `Shapes.REACH`, each [metres whatever
the size, metres times the size]:

- `stem`: how far its solid part stands out from its foot at any height (a trunk, a wall, half a hedge)
- `wide`: how far its widest part reaches (a crown, a willow's shoots, a lamp's arm, the eaves)
- `over`: the height over its foot under which that widest part never comes (0: it reaches at the ground)

| Shape | `stem` | `wide` | `over` |
|---|---|---|---|
| `reeds` | [0.25, 0.7] | [0.25, 0.7] | [0, 0] |
| `willow` | [0, 0.8] | [0, 3.75] | [0, 1.8] |
| `tree` | [0, 0.42] | [0, 6.0] | [0, 3.2] |
| `poplar` | [0, 0.24] | [0, 1.7] | [0, 1.4] |
| `hedge` | [0.68, 0] | [0.68, 0] | [0, 0] |
| `fence` | [0.05, 0] | [0.05, 0] | [0, 0] |
| `cottage` | [0, 2.25] | [0, 2.4] | [0, 2.6] |
| `post` | [0.07, 0] | [0.07, 0] | [0, 0] |
| `lamp` | [0.06, 0] | [0.61, 0] | [0, 2.85] |
| `boat` | [0, 1.0] | [0, 1.0] | [0, 0] |
| `tower` | [0, 3.5] | [0, 3.5] | [0, 0] |
| `steamer` | [0, 4.5] | [0, 4.5] | [0, 0] |

A shape not in the table (`ridge`, `lights`, `wharf`) comes no nearer than its foot. The table is worked out from the
drawing functions at the largest each draws: a change to a shape is a change to its line here.

`flow_volumes()` gives, in the room's frame: for each band and side, across from where its largest item reaches (its
`near` less its `REACH` `wide`) to its `far`, along half its loop (at most 175 m) each way, from 2 m under its feet to
30 m over; for each landmark, 15 m either side of its distance (never under `FLOW_NEAREST`); for each ground strip,
its part beyond `FLOW_NEAREST`.

**The scenery's nodes are in the group `env_placed_in_shader`** (`EnvChecks.PLACED_IN_SHADER`). Their meshes hold
each item about its own foot and the vertex shader carries it to its place, so a check that reads the vertices as
they are sees every item heaped at the room's origin, round the viewer's head: it would hide everything behind it
from the sight line, the blended layers and `flow_clear()` alike. No check that casts rays reads a mesh in the group.
What it costs is still counted (draws, triangles); where it can be is `flow_volumes()`'s to say.

## The shaders

**Colours.** Every colour in these meshes is written as sRGB, as it is written: a document's, a shape's own
(`Shapes.COLOURS`, a willow's bark, a roof, a lit window) and a ground kind's alike (`passing.gd _written()`). The
shaders take them all to linear light in one place: `passing_colour()` in `env_passing_place.gdshaderinc` (the
ground's shader does the same sum in its `vertex()`). Converting some on the CPU and not the others would draw a
shape's own colours far lighter than the colour its document gave it.

**`env_passing_place.gdshaderinc`** (the placing the scenery and its points of light share, so a lamp's light is
always on its lamp). `passing_foot(CUSTOM0, CUSTOM1, grow)` returns an item's foot in the way's frame (x across, y up,
z along, ahead positive), and in `grow` how much of the item is there (0 none, 1 whole; the item is scaled about its
foot by it). A band's item goes round its loop by the band's phase (`fposmod(travel / seems, loop)`, on the CPU in 64
bits, so a long film does not lose precision) and grows from nothing over the last 18 % of the loop's half length
each way (`EDGE` 0.82). It stays at nothing where its band's presence at its own place on the route is under its
threshold (the presence texture: a row a band, 64 texels along the route); its own place does not change while it
goes by, so nothing appears or goes while it is in view. It stays at nothing on a landmark's clearing (above). A
landmark is placed at its own place on the route less the travel. Last, everything fades in over the last 6 % before
`FAR` (188 m from the origin: from 176.7 m): a thing comes out of the horizon's haze, it is not switched on.

**The light reaches the scenery only through the windows.** What the cabin's lamps and the screen give the scenery
is weighted by `from_windows`: 1 at the way's line, gone at `glow_reach` across it, and gone from `glow_half_length`
to 2 m past it ahead and astern. So the bank beside the boat flickers with the film, and the far bank and the fields
do not. The sky's light reaches everything.

**`env_passing.gdshader`** (the bands and landmarks, one draw). Unshaded: the sky's light by the surface's facing (the
sky system's colours, or `night`), and the screen's spill and the cabin's glow through the windows. Leaves are
mottled and catch more light on top; stems are paler at the tip; lit windows glow at `windows` and take no light.
Mist takes the far scenery, and everything fades into the horizon from 120 m. Every term of light is multiplied by
`shown`, so a blink takes it all to black.

**`env_passing_lights.gdshader`** (the points of light, one draw). Each light is placed as its item is, and grows
with it (a light that is not there is not drawn at the tenth of a degree either), then spread to face the eye as the
Crater's lunar lights are: its radius in metres, never under a tenth of a degree, so a far light stays a few pixels
wide and never shimmers. A soft round point added over what is behind, dimmed by mist.

**`env_passing_ground.gdshader`** (the ground, one draw). The strips stand still; their noise pattern goes by with the
travel (it repeats every 64 m). Nearer the way's line than `still_within(speed)` the pattern fades out, so the ground
that passes closest shows nothing moving. That distance is where the pattern would cross the eye faster than
`FLOW_MAX_DEG` at the fastest the journey goes, and never under `FLOW_NEAREST`: 3.3 m at 1 m/s, 6.6 m at 2 m/s, 40 m
at 12 m/s. A band or a landmark that near is refused; the ground is everywhere and cannot be, so it is quietened
instead. Ground takes the sky's light from above, and the screen's and the cabin's
through the windows. **Water mirrors:** it does not take light as ground does. It shows its own colour and, by
Fresnel, what it mirrors: looked at steeply, the sky overhead; looked along (the far water), what stands low on the
far side, the bank and its trees, dark (the water's colour at 0.6). The ripples (a noise texture going by) move the
mirrored light where the pattern is not held still. What it mirrors towards someone inside the boat is never the
boat's own windows, so the cabin's glow and the screen's light show on it only as a glint on the ripples' crests and
a trace of scatter. The same mist and horizon as the scenery.

## Choosing a band's loop

What is seen through a side window is never further along the way than about 1.5 times its distance across. An item
grows from nothing over the last 18 % of half its loop. So a band's loop should be at least 3.7 times its `far`: then
nothing is seen growing.

## Measured

`tests/test_env_passing.gd`, headless, 2026-11-09. The test room is the `shopfront` hall (its defaults) with a passing
system: posts (30, 6 to 9 m), a far ridge (150 m, seeming 20 times further), far lights (40, 60 to 120 m, coming in
over the first half of the route), water from 2.9 to 8 m and grass to 170 m, at 1 m/s.

| What | Figure |
|---|---|
| Passing (bands and landmarks) | 356 triangles |
| PassingLights | 80 triangles (40 lights) |
| PassingGround | 8 triangles |
| Draws | 16 with the system, 13 without: 3 more |
| The test room | 16 draws, 12 654 triangles, 7.5 MB of textures |

The journey in the test: 0.6 m/s two seconds after the start (the limit); within 2 m of the film after a minute; a
pause stops it within 4.3 s; a seek of +1000 s goes dark before the cabin moves 5 m and is lit again within 1.8 s;
a film of 600 s arrives within 0.5 m of the route's end as it ends; under the Motion setting's floor it stops and
holds, and nothing jumps.

Not measured yet: the shaders' cost on the Frame. Under lavapipe all three compile and draw.
