# The cabin builder

Part of the environments engine: [`docs/environments.md`](../environments.md) has the design and says where each
part is.

`scripts/env/systems/cabin.gd`, kind `builder`; tested in `app/tests/test_env_cabin.gd`.

The inside of a vehicle, for the Journeys rooms: a narrowboat's saloon, a railway carriage, a coach. One parametric
builder that every such room dresses, instead of one hand-made shell a room.

## The frame

- The viewer's own seat is at the origin and faces -Z. The floor is y = 0.
- The cabin's long axis is Z: the front bulkhead (the screen's) is at `front_z` (negative), the rear bulkhead at
  `back_z` (positive). The centre line is at x = cx (below, "Resolved values").
- "Side s" is -1 for the left wall and +1 for the right.
- A side wall is a plane. A point of it by (u, v), u along Z and v up the slope from the floor:
  P(s, u, v) = (cx + s * hw, 0, 0) + V * v + (0, 0, u), where V = (-s * sin L, cos L, 0). Its inward normal is
  N = (-s * cos L, -sin L, 0). A height y on the wall is v = y / cos L.
- The roof joins the walls' tops at x = cx -+ top_half, y = wall_height. Flat: one face at y = wall_height. Arched:
  an arc through both tops, `rise` above them at the middle, in `ROOF_STEPS` (10) equal steps of angle:
  R = (top_half² + rise²) / (2 * rise), its centre at y0 = wall_height + rise - R, a = asin(top_half / R), the points
  (cx + R sin t, y0 + R cos t) for t from -a to a, the normal at t (-sin t, -cos t). Under 1 mm of rise it is flat.
- The section's outline (the bulkheads): the floor's left corner, the roof's points (which begin and end at the walls'
  tops), the floor's right corner.

## Parameters

| Name | Type | Range | Default | What |
|---|---|---|---|---|
| `width` | float | 1.6..12 | 2.6 | the inside width at the floor |
| `wall_height` | float | 1.2..3.5 | 1.9 | the height at which the side walls end and the roof begins |
| `lean` | float | -15..15 | 0 | degrees the side walls lean in towards their tops (negative: out) |
| `roof` | enum | flat, arched | arched | the roof's shape |
| `roof_rise` | float | 0..1.5 | 0.25 | how far an arched roof rises over the walls' tops at its middle |
| `front_z` | float | -30..-1.5 | -3.0 | z of the front bulkhead (the screen's) |
| `back_z` | float | 0.6..30 | 2.4 | z of the rear bulkhead |
| `centre_x` | float | -3..3 | 0 | the cabin's centre line (used with seating none) |
| `window_sides` | enum | both, left, right, none | both | the walls that have windows |
| `window_count` | int | 0..24 | 3 | windows along each windowed side |
| `window_from_z` | float | -30..30 | -1.2 | z of the middle of the window nearest the screen |
| `bay_pitch` | float | 0.4..6 | 1.5 | from one window's middle to the next |
| `window_width` | float | 0.25..4 | 0.9 | a window's width |
| `window_height` | float | 0.25..2.5 | 0.6 | a window's height |
| `window_sill` | float | 0.2..2.5 | 1.0 | the window's bottom edge over the floor |
| `window_round` | float | 0..1.25 | 0.08 | the windows' corners' radius |
| `wall_thickness` | float | 0.02..0.4 | 0.06 | the side walls' thickness (the windows' reveals) |
| `frame_width` | float | 0.01..0.2 | 0.04 | the window frames' width round the opening |
| `frame_depth` | float | 0..0.08 | 0.015 | how far the window frames stand out from the wall |
| `dado_height` | float | 0..2 | 0.9 | the dado's height (0: none) |
| `ribs` | bool | | true | ribs between the bays, up the walls and under the roof |
| `rib_width` | float | 0.03..0.3 | 0.05 | a rib's width along Z |
| `rib_depth` | float | 0.01..0.2 | 0.025 | how far a rib stands out from the wall |
| `cornice` | float | 0..0.3 | 0 | a moulding along each wall's top, this high, in the trim (0: none) |
| `lamps` | enum | none, ceiling, wall | ceiling | lamps under the roof's middle, on the walls between the windows, or none |
| `lamp_height` | float | 1.0..3 | 1.5 | the wall lamps' height |
| `lamp_size` | float | 0.5..3 | 1.0 | the lamps' size: 1 is a small cabin's (a wall lamp's glass 0.07 wide, 0.1 high) |
| `lamp_colour` | color | | [1.0, 0.82, 0.58] | the lamps' glow |
| `rear_door` | enum | none, centre | centre | a door in the rear bulkhead |
| `door_glow` | float | 0..2 | 0.3 | live, a brightness: the light in the door's window |
| `door_colour` | color | | [1.0, 0.85, 0.6] | the colour of the door's light |
| `screen_size` | vec2 | 0..8 | [0, 0] | the picture's width and height ([0, 0]: its own; one 0: 16:9 from the other) |
| `screen_bottom` | float | 0..3 | 0 | the picture's bottom edge over the floor (0: its own) |
| `screen_frame` | bool | | true | a narrow frame round the picture |
| `seating` | enum | none, rows | none | none: the viewer's own seat alone; rows: seats in rows either side of an aisle |
| `rows_front` | int | 0..30 | 2 | rows in front of the viewer's |
| `rows_back` | int | 0..30 | 1 | rows behind the viewer's |
| `row_pitch` | float | 0.7..2 | 0.9 | metres a row |
| `seats_left` | int | 0..4 | 2 | seats in a row left of the aisle |
| `seats_right` | int | 0..4 | 2 | seats in a row right of the aisle |
| `seat_pitch` | float | 0.42..1 | 0.5 | seat centres, metres |
| `aisle` | float | 0.3..2 | 0.5 | the aisle's width |
| `own_side` | enum | left, right | right | which block the viewer's own seat is in |
| `own_index` | int | 0..3 | 0 | the viewer's own seat's place in that block, 0 by the aisle |
| `seat_model` | enum | none, folding, director, club, plush | plush | the plain seat drawn when the room has no seats system |
| `ledge` | float | 0..1.5 | 0 | a ledge outside each windowed wall, this wide (0: none) |
| `ledge_y` | float | -1..2.5 | 0.7 | the ledge's height |

Materials: `walls` (rough plaster, [0.78, 0.74, 0.64]), `dado` (wood panelling, [0.28, 0.17, 0.1]), `ceiling` (rough
plaster, [0.8, 0.78, 0.72]), `floor` (rustic planks, [0.3, 0.2, 0.13]), `trim` (walnut veneer, [0.22, 0.13, 0.08]),
`bulkhead` (wood panelling, [0.3, 0.19, 0.11]), `hull` (dark metal, [0.06, 0.06, 0.07]), `seat_cover` (felt, [0.35,
0.1, 0.1]), `seat_frame` (dark metal, [0.12, 0.12, 0.12]).

`door` is a material too, empty by default: the rear door is then in the trim's material and costs nothing. Given a
material of its own, the door and its handle are a second surface of `Trim`, one draw more: a hall with gilt trim has
a painted door (the Showboat's).

The spec: requires `light`; provides `seats`, `collision`, `sound_room`, `bake`, `slots`; cost 12 draws, 6000
triangles, 30 MB; no actions.

## Resolved values

`resolved(p)` gives a copy of the parameters with these filled in; every other static function starts from it.

- L = the lean in radians. hw = width / 2. wall_len = wall_height / cos L (the wall's length up its slope).
- top_half = hw - wall_height * tan L (half the width at the walls' tops).
- rise = roof_rise with an arched roof, else 0. headroom = wall_height + rise.
- Rows with no seat in either block (seating rows, seats_left + seats_right 0) are no rows: seating is none, the
  viewer's own seat alone on `centre_x`.
- cx: with seating none, `centre_x`. With seating rows the viewer's own seat is at x = 0: its offset from the centre
  line is o = aisle / 2 + seat_pitch * (own_index + 0.5), positive in the right block, and cx = -o. own_index is
  clamped to the block's last seat; a block with no seats gives its place to the other.
- The windows: z_k = window_from_z + k * bay_pitch. A window is kept only when it stays 0.15 m clear of both
  bulkheads. Its top (window_sill + window_height) is at most wall_height - 0.05; window_height is reduced to fit.
  Where that leaves less than `MIN_WINDOW` (0.1 m) over the sill, the cabin has no windows at all: not slits, and
  not openings with nothing in them. r = min(window_round, window_width / 2, window_height / 2).
- dado = min(dado_height, window_sill) when there are windows, else dado_height.
- The screen, with `screen_size` [0, 0]: w = clamp(top_half * 2 - 0.5, 0.6, 3.2), h = w * 9 / 16; if h > headroom -
  0.95, h = headroom - 0.95 and w = h * 16 / 9. With one 0 in `screen_size`, that one is 16:9 from the other (h = w *
  9 / 16, or w = h * 16 / 9), so a room can ask for a width and let the height follow. With `screen_bottom` 0: bottom
  = clamp(1.3 - h / 2, 0.75, headroom - 0.12 - h). `screen_for()`: centre (cx, bottom + h / 2, front_z + 0.03), size
  (w, h).
- The bays' marks (ribs, wall lamps, `side_walls` slots): half a bay_pitch before the first kept window, half way
  between each pair, half a bay_pitch after the last; with no windows, the cabin's middle. A mark is kept only where
  it is at least `MARK_MARGIN` (0.1 m) inside both bulkheads: the first and the last can fall in a bulkhead or beyond
  it, and nothing stands there.

The static functions, from parameters alone: `resolved`, `_box` (cx - hw, 0, front_z to cx + hw, headroom, back_z),
`seat_slots_for`, `layout`, `screen_for`, `collision_shapes_for` (the shell's boxes, and the seats' when drawn),
`slots_for`, `window_boxes_for` ({side, center: the opening's middle on the wall's inner plane, size, normal}).
`sound_room()`: the box, surround height min(1.6, headroom - 0.3), one array 2 m apart.

## The nodes

| Node | What |
|---|---|
| `Floor` | static: one face, `floor` |
| `Lining` | static: `dado` (both walls up to the dado), `walls` (above it, cut round the windows), `ceiling` (the roof: a face, or a strip along the arc), `bulkhead` (front and rear, each a polygon of the section) |
| `Trim` | static, `trim`: each window's frame (a strip from the opening out by frame_width, frame_depth into the room) and its reveal (a strip through the wall's thickness); the dado's rail; the ribs (at the bays' marks, up both walls and under the roof); the cornice (`cornice`: along each wall's top in two steps, the upper standing 0.6 of its height out from the wall and the lower 0.3; the ribs run into it); the screen's frame (four boxes 0.04 wide and 0.03 deep, at the picture's edge); the rear door (0.62 wide, up to 1.85 high) and its handle; the ceiling lamps' roses and the wall lamps' arms |
| `Glass` | each window's pane at the wall's outer face; in `env_see_through`. Tinted `GLASS_TINT` (0.62, 0.74, 0.8), `GLASS_ALPHA` 0.02 square on and `GLASS_RIM` 0.06 more where the view grazes it |
| `DoorGlow` | the light in the door's window (0.3 x 0.4, its middle 1.5 m up), group `accent`; follows `door_glow` |
| `Lamps` | ceiling: a lamp under the roof's middle at each window (the cabin's middle without windows); wall: on both walls at the bays' marks, `lamp_height` up, on an arm; the glass, its fitting and how far it stands out all times `lamp_size`; group `house`, a hidden bake light each |
| `Hull` | not baked, `hull`, with `ledge`: outside each windowed wall a ledge at `ledge_y` from front_z - 2 to back_z + 2, an upstand at its outer edge |
| `Seats` | the plain seats (one MultiMesh), unless `seat_model` is none or the room has a seats system |

The glass is fainter than a hall's (0.06, and 0.22 more where the view grazes it): a cabin's windows are an arm's
length from a bright picture and are looked through at night. At a hall's strength the picture's light on the panes
was a grey veil over everything outside (2026-11-09, the Narrowboat's wharf at night).

A wall with windows is cut into cells at the midpoints between neighbouring windows (the first from front_z, the
last to back_z). Each cell has a face below the window, one above, one either side, and, with round corners, a
polygon in each corner between the square corner and the round one (`CORNER_STEPS` 4: five points on the arc).

Seats: with seating rows, rows at z = -row * row_pitch from -rows_back to rows_front, the left block's seats at
cx - aisle / 2 - seat_pitch * (i + 0.5) and the right's at cx + aisle / 2 + seat_pitch * (i + 0.5), style `chair`,
listed left to right; a row within 0.5 m of a bulkhead is left out. With seating none, one `club` slot at the origin.

## Slots

| Name | Where | Size |
|---|---|---|
| `side_walls` | both walls, at the bays' marks, the wall's inner face at the dado's height | [bay_pitch - window_width, wall_height - dado, 0.3]; with no windows [1.0, wall_height - dado, 0.3] |
| `window_sills` | each window: the middle of its bottom edge on the wall's inner plane | [window_width, window_height, wall_thickness] |
| `windows` | each window: the middle of its glass | [window_width, window_height, 0] |
| `screen`, `proscenium`, `rear_wall`, `floor`, `ceiling` | as the shopfront's | |
| `corners` | the four floor corners, each facing the cabin's middle | [0.4, headroom, 0.4] |

A piece's front faces its local +Z, into the cabin; on a wall its Y goes up the wall's slope.

## Measured

`test_env_cabin.gd`, 2026-11-09:

| Room | Draws | Triangles | Texture | Largest atlas |
|---|---|---|---|---|
| The default | 11 | 1650 | 6 MB | 132 x 144 |
| A narrow boat (width 1.9, lean 6, roof_rise 0.12, round windows, ledge 0.12) | 12 | 1614 | 6 MB | 124 x 136 |
| A coach (width 2.4, 10 m long, 8 rows of 4, 6 windows a side, folding seats) | 11 | 6730 | 6 MB | 168 x 224 |
| A flat roof, windows on the left, wall lamps | 11 | 1326 | 6 MB | 136 x 144 |

No live lights in any (the lamps' lights are the bake's).

## Rows and the picture

The picture the rules give is for a cabin with one seat or low ones. With rows of tall seats the rows behind do not
see its bottom edge: such a room sets screen_bottom itself.

The picture hangs flat on the front bulkhead: `screen_for()` gives it `facing` [0, 0, 1], and a room's document
that writes its own `screen` with rows must give the same. A screen with no `facing` turns towards the room's own
seat, which with rows is beside the aisle, off the cabin's centre line; turned, one edge of the picture goes
through the bulkhead (the Showboat's did, by 0.17 m). The viewer sees the picture a little from the side, as from
an aisle seat.
