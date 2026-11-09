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
| `shape` | enum `Shapes.BANDS` | | what stands in the band |
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

Something that stands once on the route: it comes into view ahead, passes and goes astern.

| Field | Type | Default | What |
|---|---|---|---|
| `shape` | enum `Shapes.LANDMARKS` | | what it is |
| `at` | float 0..1 | | its place on the route, as a fraction |
| `side` | left, right | left | which side of the way |
| `distance` | float 3..170 | 8 | metres from the way's line |
| `height` | float -20..40 | 0 | its foot's height |
| `size` | float 0.1..6 | 1 | times its natural size |
| `colour` | color | the shape's own | its main colour |
| `seed` | int 0..100000 | 0 | another arrangement of the same |

With no route's end (a film with no length), a landmark at 0 (the place the journey starts from) is there; the others
never come.

### A ground strip

| Field | Type | Default | What |
|---|---|---|---|
| `side` | left, right, both | both | which side of the way |
| `from`, `to` | float 0..175 | | metres from the way's line |
| `height_from`, `height_to` | float -20..40 | 0 | its height at each edge |
| `kind` | water, grass, path, field, snow, sand, stone | grass | what it is |
| `colour` | color | the kind's own | water `#0c1218`, grass `#1a2414`, path `#3b362c`, field `#201c16`, snow `#c8ccd6`, sand `#4a4232`, stone `#34322e` |

A strip runs 175 m ahead and astern. It stands still; its pattern goes by.

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
| the fastest anything crosses the eye, at its nearest | `FLOW_MAX_DEG` | `comfort_for()`: a band (`near`, `seems`) or a landmark (`distance`) at the fastest the journey goes (`speed` and `CATCH_UP`) |
| the nearest anything passes the way's line | `FLOW_NEAREST` | `comfort_for()`: a band's `near`, a landmark's `distance`. Ground nearer than this is fine: its shader holds its pattern still there |
| how fast the speed changes | `FLOW_ACCEL` | step 7; an arrival slows at half of it (`BRAKE`) |
| clear of the picture's edges, from the room's own seat | `FLOW_CLEAR_DEG` | `flow_volumes()`: the boxes the moving scenery keeps to, for `flow_clear()` |
| the Motion setting under which nothing goes by | `FLOW_MOTION_FLOOR` | step 2 |

`flow_volumes()` gives, in the room's frame: for each band and side, across from `near` to `far`, along half its loop
(at most 175 m) each way, from 2 m under its feet to 30 m over; for each landmark, 15 m either side of its distance
(never under `FLOW_NEAREST`); for each ground strip, its part beyond `FLOW_NEAREST`.

The scenery's meshes hold each item about its own foot (the shader places it), so a check that reads vertices as they
are sees every item heaped at the origin. The sight-line check looks through them (they are in `env_see_through`).
`flow_clear()` does not yet: its `_view_bodies()` takes them as solid round the eye, which can hide scenery by the
picture where no wall stands in front of it (a room with no side walls, tried 2026-11-09: 4 problems hidden). With
the walls a cabin has, the check is right.

## The shaders

**`env_passing.gdshader`** (the bands and landmarks, one draw). A band's item goes round its loop by the band's phase
(`fposmod(travel / seems, loop)`, on the CPU in 64 bits, so a long film does not lose precision); it grows from
nothing over the last 18 % of the loop's half length each way, and stays at nothing where its band's presence at its
own place on the route is under its threshold (the presence texture: a row a band, 64 texels along the route). A
landmark is placed at its own place on the route less the travel. Nothing is drawn further than 188 m from the
origin. Unshaded: the sky's light by the surface's facing (the sky system's colours, or `night`), the screen's spill,
and the cabin's glow on what is near the way and abreast of the windows. Leaves are mottled and catch more light on
top; stems are paler at the tip; lit windows glow at `windows` and take no light. Mist takes the far scenery, and
everything fades into the horizon from 120 m. Every term of light is multiplied by `shown`, so a blink takes it all
to black.

**`env_passing_lights.gdshader`** (the points of light, one draw). Each light is placed as its item is, then spread
to face the eye as the Crater's lunar lights are: its radius in metres, never under a tenth of a degree, so a far
light stays a few pixels wide and never shimmers. A soft round point added over what is behind, dimmed by mist.

**`env_passing_ground.gdshader`** (the ground, one draw). The strips stand still; their noise pattern goes by with the
travel (it repeats every 64 m). Nearer the way's line than `FLOW_NEAREST` the pattern fades out, so the ground that
passes closest shows nothing moving. Water takes the sky by Fresnel, rippled, a little of the cabin's glow and the
screen's spill. The same mist and horizon as the scenery.

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
