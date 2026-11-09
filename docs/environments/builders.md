# The builders

Part of the environments engine: [`docs/environments.md`](../environments.md) has the design and says where each part is.

## The auditorium builder

`scripts/env/systems/auditorium.gd`. Its defaults are the cinema: the cinema's document sets only what it names.

| Parameter | Default | What |
|---|---|---|
| `room_min`, `room_max` | [-9.6, -3, -14.5], [9.6, 9, 6.2] | the hall's walls, floor of the pit, ceiling |
| `rows_front`, `rows_back` | 7, 3 | rows in front of and behind the viewer's own (row 0) |
| `row_depth`, `row_rise` | 1.3, 0.35 | the rake: each row this deep and this much higher than the one in front |
| `seats_per_row`, `seat_pitch` | 27, 0.58 | seats along a row, centre to centre |
| `row_radius` | 45 | rows curve round a point this far ahead; 0 is straight rows |
| `block_x` | 8.1 | the seats reach this far either side; the side aisles go from there to the walls |
| `seat_model` | `stadium` | the seat: `stadium` (drawn by the auditorium), or a single seat of the seats system: `plush`, `multiplex`, `folding_chair`, `club_chair`, `director`, `cushion`, `bean_bag`, `civic`, `recliner` (set `seat_pitch` to fit) |
| `seat_upholstery`, `seat_shell` | velvet, black leather | materials |
| `seat_tint_spread` | 0.12 | how much the seats differ, one from the next |
| `wall_treatment` | `panels` | `panels` (fabric panels with wooden rails) or `plain` |
| `proscenium` | `drapes` | `drapes` (velvet either side and a valance) or `none`; slots to come: castle gate, festoon |
| `stage_depth`, `stage_top` | 1.9, -2.1 | the stage in front of the screen wall |
| `ceiling_cover` | 1 | the ceiling's share from the front; under 1 opens it to the sky (the Atmospheric, the Reclaimed's broken roof) |
| `shell` | `built` | `built`: the walls, the ceiling, the stage, the drapes, the pit, the doors and the lamps drawn here; `kit`: only the tiers, the side aisles, the rear walkway and the seats, a kit drawing the rest (Reclaimed's ruin, since 2026-11-08) |
| `balcony_rows` | 0 | a balcony over the rear with this many rows (its seats are among the room's seats from the document alone too: `seat_transforms_for()`, since 2026-11-08) |
| `balcony_parapet` | 1 | the balcony's parapet, metres over its floor (0.8 in the Pink Palace, under its buttoned front's roll; since 2026-11-08) |
| `boxes_per_side` | 0 | boxes on the side walls |
| `partition_z` | 0 | a plain wall across the hall here (a subdivided hall, Screen 3); 0: none |
| `booth` | true | the projection booth's windows in the rear wall; `lens` is its lens |
| `house_spots` | true | the bake's four house lights high over the seats (a ceiling's cans); off for a hall open to the sky (since 2026-11-08) |
| `handrails` | true | brass handrails along the side walls; off where a kit's house fronts stand along the walls (since 2026-11-08) |
| `doors` | true | the four exits with signs |
| `side_walls` | true | the side and rear walls; false: a kit draws them (the Palace of Culture's board-marked concrete round its mosaics; since 2026-11-08). The wall behind the screen stays |
| materials | the cinema's | `floor`, `walls`, `front_wall`, `ceiling`, `panel_fabric`, `panel_wood`, `stage`, `curtains`, `door_leaf`, `door_metal`, `brass` |

## The builders

Six more builders of kind `builder`, and the `kit`. They keep the auditorium's conventions. They extend
`scripts/env/systems/kit/builder.gd`, and they share the helpers in `scripts/env/systems/kit/` (`build_util.gd`,
`shapes.gd`, `procedural.gd`, `seat_models.gd`, `pieces.gd`, `furniture.gd`, the glass and glow shaders).

- **The viewer's seat** is at the origin, facing -Z. The floor under it is at y 0 (a lot's ground and an
  amphitheatre's pit can be lower).
- **Static parts** are meshes with their own UV2, baked by the light system's hooks. Rounded parts (seats, statues,
  leaves) are not baked.
- **Materials** are library materials on the house shader, from the light system. Patterns (pressed tin, ice blocks,
  a swirling carpet, corrugated tin, plasterboard, quarry tiles) are our own maps, drawn in `procedural.gd` and put on
  a library material. The library material is CC0, so the licence check still holds. `quarry_tiles` (since
  2026-11-08): square terracotta tiles in mortar, each its own shade and wear, at 256 x 256 (`SIZES`: a pattern can
  have its own size; the others keep theirs). `board_concrete` (since 2026-11-08, the Palace of Culture): concrete
  cast against boards, ten to a repeat, each its own tone and depth, butt joints, grain, the fins between boards,
  tie holes and blowholes, at 256 x 256. `tufted` (since 2026-11-08, the Pink Palace's balcony front): buttoned
  upholstery, a button at each corner and the middle of a repeat, the cloth puffed up between them in diamonds and
  drawn in along the creases. `shell_carpet` (since 2026-11-08, its aisles): rose scallop shells outlined in powder
  blue on a deep rose ground, two rows a repeat, a cream pearl between them, at 256 x 256.
- **Text** is our own stroke font (`kit/strokes.gd`): Latin capitals and figures, and since 2026-11-08 the Greek
  capitals that differ from Latin ones (Γ Δ Θ Λ Ξ Π Σ Φ Ψ Ω; the others, Α Β Ε and so on, draw as their Latin
  look-alikes through `ALIASES`).
- **Lamps** use the light system's groups: `house` (the ritual takes them down), `accent`, `signs`, `booth`. A flame
  or a candle flickers with the builder's `flicker` parameter. Every frequency is under 3 Hz. The room's Flickering
  lights setting holds it steady.
- **A lamp colour a cue moves** (since 2026-11-07): the light system's live `glow_colour` and `glow_mix` (0 by
  default: the lamps' own colours) take the `house`, `steps` and `stage` lamps' glow toward one colour. A builder's
  lamp colour parameters are not live (the room builds again), so a cue that changes the lamps' colour fades these:
  the Streamline's Changing cove (`cove_cycle`, and `cove_settles` when the film starts). The stand-in lamps and a
  baked lightmap keep the builder's colour.
- **Glass** (a window, a dome's panes, a windscreen) is in the group `env_see_through`. The sight-line check looks
  through it. It blends; it never multiplies.
- **The sight line:** a flat-floored builder keeps the picture's bottom at 1.1 m or more over the floor, so chair
  backs never block it.
- **Physics:** `collision_shapes()` gives cheap boxes. Seat boxes come only when the builder draws its own seats.
- **The screen:** each builder's static `screen_for(params)` gives the default screen ({center, size}). A room
  document's `screen` should match it.

### Seat slots (the interface with `seats`)

Each builder's static `seat_slots_for(params)` gives its seats as slots, from the parameters alone. A slot is
`{transform, row, style, width, builder}`.

- `transform`: the floor point under the seated eyes, facing -Z in its own frame.
- `row`: 0 is the viewer's row. Rows in front count up. Rows behind are negative.
- `style`: `chair`, `pew`, `bench`, `cushion`, `club`, `ring` or `tier`.
- `width`: metres along the row. A row's slots go left to right. A pew's or a bench's slots are `width` apart. An
  aisle leaves a gap wider than 1.5 widths.

With a `seats` system in the room, the builder draws no seats and gives no seat boxes; the seats system draws them in
the slots. Without one, the builder draws plain default seats (`seat_models.gd`). Single seats (chair, club, ring)
are one MultiMesh, with the viewer's own seat folded away. Pews, benches and cushions are one static mesh.

### Slots for the kit

Each builder's `slots()` gives named places for kit pieces: `{name: [{transform, size}]}`. A piece's front faces its
local +Z (into the room). Common names: `side_walls`, `screen`, `proscenium`, `rear_wall`, `floor`, `ceiling`,
`corners`. Each builder adds its own (below).

### `shopfront`

A narrow picture house of about 1906 in a shop. A wooden dado, pressed tin above it and on the ceiling, a small
raised end with a framed sheet, the shop window and door behind the seats with the street's glow, gas lamps that
flicker, folding chairs in rows.

- Size: `width`, `height`, `screen_wall_z`, `front_z`. Rows: `rows_front`, `rows_back`, `row_pitch`,
  `chairs_per_row`, `chair_pitch`, `seat_model`.
- The end: `stage_depth`, `stage_height`, `screen_size`, `screen_bottom`, `sheet_frame`.
- Walls: `dado_height`, `tin_pattern` (`pressed_tin` or `plain`), `tin_walls`.
- Live: `street_glow`, `flicker`. Lamps: `lamps_per_side`, `lamp_height`, `lamp_colour`.
- Slots: `booth` (the back corner's floor), `side_walls`, `screen`, `proscenium`, `rear_wall`, `ceiling`, `floor`.
- Measured: 13 draws, 12k triangles, 7 MB.
- **`style`** (since 2026-11-08, Shopfront 1906's deep pass): `plain` (the default: the hall above, unchanged) or
  `edwardian` (`kit/shopfront_edwardian.gd`, its maps and pictures `kit/shopfront_pictures.gd`): pressed tin in relief
  (the ceiling's plates, the walls' lattice, a cornice, roses), a matchboard dado, a worn floor, a gilt-framed sheet
  under a pelmet and drapes, a stage with a lectern, a drawn player piano (its keys and roll follow the room's
  `music` piano), its own tin booth over the door (the lens at `lens()`), gas brackets and pendants, bills and a clock,
  the shop window onto a street drawn in code, and a horse and cart. Its seats, screen, sound room and collision are
  the plain style's. The parts: "Room: Shopfront 1906". Action: `cart` (args: `seconds`): the cart passes outside the
  window (the room's `cart` cue plays the `hooves` sound_bed with it); ignored while one is passing.

### `nave`

A church-like nave. Two arcades of round columns, side aisles, clerestory walls with dim windows, a barrel vault, a
chancel up three steps with the screen under the chancel arch, a rose window over it, candle stands that flicker,
pews.

- Size: `nave_width`, `aisle_width`, `rear_z`, `chancel_z`, `chancel_depth`, `chancel_rise`, `bay`,
  `column_height`, `column_radius`, `wall_height`, `vault`.
- Pews: `rows_front`, `rows_back`, `row_pitch`, `places_per_pew`, `place_width` (one slot a place, style `pew`).
- Live: `rose_glow`, `flicker`. Also `rose_window`, `rose_radius`, `clerestory_windows`, `candles`.
- Slots: `niches` (the aisles' walls), `columns`, `screen`, `proscenium` (the chancel arch), `rear_wall`, `floor`.
- Measured: 11 draws, 4.4k triangles, 8 MB.
- **`style`** (since 2026-11-08, the Nave's deep pass): `plain` (the default: the nave above, unchanged) or `gothic`
  (`kit/nave_gothic.gd`): clustered piers with dark polished shafts and foliage capitals, pointed arcades of two
  orders, a triforium, a clerestory of two-light windows with bar tracery, quadripartite rib vaults over the nave, the
  chancel and the aisles (`vault` `rib`), coloured glass of our own drawing, a rose window over the screen, a chancel
  arch on continuous mouldings, flagstones with ledger stones, carved pews it draws itself (no `seats` system: they
  are baked), a reredos round the screen, a hymn board, candles on iron stands, iron coronae, a votive stand, the
  west doors. Its own parameters: `chancel_width` (0: the nave's and 1.2 m), `window_glow` (live), `moonlight` (the
  Moon's spots for the bake through the south windows), `coronae` (how many hang, one a bay), `coronae_lit`,
  `votive`, and materials `webs`, `cloth`, `iron`. The plain style ignores them. Its stone is our own maps (ashlar,
  a plain grain for the carving, a paving face; `_stone_maps`), its glass our own pictures. Every lightmap atlas is
  laid out at a coarser texel than the builders' 0.1 m (`RoomMesh.texel`, since 2026-11-08: 0.2 m on the walls and
  floor, 0.3 m on the vaults' webs, 0.4 m on the carving), so its nine baked meshes total about 0.7 M texels.

### `dome_hall`

A round hall under a dome, glass or solid. A low drum wall, lamps round it, a low stage, seats on arcs round the
screen (style `ring`). Beyond glass: nothing (a sky system's sky), deep water, or a dark night. With `has_floor` and
`seating` off, it covers another builder (the crater: an amphitheatre under a glass dome).

- `radius`, `centre_z`, `floor_y`, `drum_height`, `dome_height`, `dome` (`glass` or `solid`), `ribs`, `rings`.
- `outside` (`none`, `water`, `night`), `water_top`, `water_deep`; live: `outside_glow`.
- `glass_colour` and `glass_alpha` (0.05; lower is clearer): a pale tint at a low alpha keeps the view out clear,
  where before a room needed a near-black tint to stop the glass hazing what lies outside.
- Seats: `rows_front`, `rows_back`, `row_depth`, `seat_pitch`, `arc_deg`, `seat_model`.
- `rib_phase` (0..1): the ribs turned by that share of the gap between two (0.5: none straight behind the screen).
- Slots: `drum`, `screen`, `proscenium`, `floor`, `ceiling`.
- Measured (glass, about 120 seats): 8 draws, 88k triangles, 4 MB.

#### The water and the sea floor (since 2026-11-08)

With `outside` water the water is its own shader (`shaders/env_water_outside.gdshader`), and everything in the water
shares its uniforms (`shaders/env_water.gdshaderinc`: the colour along a view, the murk, caustics, the floodlights'
light, the film's light through the glass). Each part is built only when the document asks for it. The geometry is
`scripts/env/systems/kit/seabed.gd`; nothing is read from a file.

| Parameter | Default | What |
|---|---|---|
| `depth` | 0.5 | live, a brightness: 0 the sunlit shallows (Snell's window overhead with the surface's waves in it, shafts round it, caustics on the sea floor), 0.5 `water_top` and `water_deep` as given, 1 the abyss (black; a few specks glow now and then) |
| `murk` | 0.07 | how quickly the water hides what lies in it, per metre |
| `water_motion` | 1 | live, `motion` (at most 1): the shafts' sway, the caustics' drift, the fronds' sway, the snow's sinking, the bubbles' rise |
| `seabed` | false | a bowl of sea floor: banks rising to the sides and behind, a trench behind the screen, two ledges near the glass that lift what grows on them over the drum |
| `rocks`, `coral`, `fronds` | 24, 0, 0 | boulders; coral on the right ledge and round it (branching coral, heads, fans, anemones); kelp on the left ledge and in beds |
| `wreck`, `vent`, `bubbles` | false, false, 140 | an old diving bell on its skid, a fallen derrick, an anchor; a vent's chimney and its bubbles rising past the glass |
| `snow` | 0 | marine snow: quads sinking slowly round the dome, never inside it (moved in the vertex shader: no particle system) |
| `floodlights`, `flood`, `flood_colour` | 0, 1, warm white | lamps on the drum's top outside aimed at the features, their beams in the murk (`flood` live, a brightness) |

#### The fittings (since 2026-11-08)

`scripts/env/systems/kit/dome_fittings.gd`: `portholes` (round ports in the drum, none in front), `rivets` (along a
glass dome's ribs and the drum's ledge), `gauges` and live `gauge` (each needle swings from its own rest by its own
share; bind `gauge` to `film.bass`), `console` (an instrument desk behind the seats with a sonar scope,
`shaders/env_sonar.gdshader`; live `sonar` its glow, a brightness) and `hatch`. Unbaked (small faces), lit as the
seats. The console is a physics box. `needle_readings()` gives the needles' readings (tests: headless, a MultiMesh
keeps no transforms).

#### A Moon base's dome (since 2026-11-08)

`scripts/env/systems/kit/lunar_dome.gd`, each off by default (the dome as before): `lattice` `geodesic` (an
icosahedron with a point at the top split `frequency` times, even, so a ring of edges stands on the drum; steel struts
of a box section, a hub at every node, bolt heads on the lowest two rings, a compression ring on the drum; flat glass in
every triangle, one layer; `rib_phase` turns it by a share of a fifth of a turn; the struts and the drum unbaked: their
thousands of small faces, and the drum's one long strip, would multiply the lightmap's atlas), `airlocks` (0..4: a door
set into the dome's foot at 62 degrees either side of the screen, then at 118: a steel portal, the door leaf with a
round window lit warm from the vestibule, a green status lamp over it, a lit panel beside it, all `signs`; a hidden
bake light over each), `trays` (a cable tray along the drum on brackets, cables in it, broken at the doors).
`glass_reflect` (the picture's colour mirrored faintly where a pane faces the screen: one dot product a pixel) and
`glass_dust` (dust on the glass, thickest at its foot, gone 2.2 m up) are uniforms of the one glass layer
(`kit/env_glass.gdshader`, both 0 by default). Measured in the Crater (radius 18, `frequency` 6): the lattice 1 draw
and about 18k triangles, the glass 1 draw (one layer over the whole view: the dome's whole cost in fill rate).

Measured, the Bathysphere's set (`test_room_bathysphere.gd`): the sea floor with its rocks, coral, bell and chimney 1
draw and 8.7k triangles, the fronds 1 and 4.1k, the snow (1800) 1 and 3.6k, the bubbles 1, the beams 1 (480), the
lenses 1, the ports' glass 1, the scope 1, the gauges' faces 1 and needles 1, the console's lamps 3, the brass and the
dark fittings 2, the rivets 1 and 4.4k: 17 draws and about 25k triangles on top of the hall.

### `terrace`

Open air, under a sky system's sky. Three styles. `terrace.gd STYLES` holds the parameters each style needs; a room
document sets them.

| Style | What | Its parameters |
|---|---|---|
| `rooftop` (default) | a tiled roof terrace, a low parapet, the screen painted on the next building's blind wall, strings of bulbs, chairs in rows | the defaults |
| `lot` | a drive-in's lot: low humps across each row of bays, speaker posts beside the cars' front seats, the screen on a frame (or `screen` `none` and the kit's tower). No seats of its own: the car's | `half_width` 20, `front_z` -50, `back_z` 12, `ground_y` -0.5, `ground_extent` 120, `parapet` false, `screen` frame, `screen_size` [24, 10], `screen_bottom` 4, `seating` false, `string_lights` false |
| `amphitheatre` | stone tiers on arcs round the screen, rising behind the viewer (style `tier`), rocks on a dusty plain: a lunar amphitheatre | `half_width` 14, `front_z` -14, `back_z` 10, `ground_extent` 150, `parapet` false, `screen` frame, `screen_size` [8, 4.5], `screen_bottom` 1.6, `rows_front` 3, `rows_back` 6, `row_pitch` 0.95, `seat_pitch` 0.6, `string_lights` false |

- The ground beyond the terrace (`ground_extent`, up to 400 m) is not baked, so the lightmap stays small.
- Other parameters: `parapet_height`, `wall_height`, `tier_rise`, `arc_deg`, `rocks`, `bays`, `bay_pitch`,
  `bulb_colour`, materials.
- Slots: `parapet` (along the parapets' tops), `screen`, `proscenium`, `floor`, `corners`.
- Measured: rooftop 8 draws, 12k triangles, 7 MB; lot 5 draws, 3k triangles; amphitheatre 4 draws, 2k triangles.
- **The Moon base** (`amphitheatre` with `lunar` on, since 2026-11-08; `kit/lunar_base.gd` inside,
  `kit/lunar_surface.gd` outside; off, the amphitheatre is as it was). Under a glass `dome_hall` in the room (its centre
  and radius are read from it): hexagonal pavers of sintered regolith (`procedural.gd` `hex_pavers`) the whole round of
  the dome; the tiers in precast blocks of about two metres, each its own shade, a chamfered nose with a strip of warm
  light under it (`steps`); a pad on every seat and a back pad on the riser behind; stairs up each end of the tiers,
  two steps a tier, a lamp in each riser and a handrail; a guard rail behind the top tier; a stage under the screen
  with footlights (`stage`), two tapered pylons carrying the frame on steel brackets, a slot of cool light high on
  each (`house`). Earth's light falls through the glass in the bake (a hidden directional light from where the sky
  puts Earth). Outside, one mesh on its own unshaded shader (`shaders/env_regolith.gdshader`: Earth's light with the
  regolith's way of scattering it back, the sun only over its shadow's line, the dome's lamps on the berm, the film's a
  little): the plain banked against the drum, craters with raised rims, boulders in dust skirts each with its own sharp
  shadow, the rover's tracks and the footprints (bands of ground drawn by the same shader, so their edges vanish), the
  crater's wall at 128 to 160 m from the dome's centre with its peaks in the sun, a base of habitat modules with warm
  windows, a lattice mast and its slow beacon, solar arrays, a cargo lander, a rover, the airlocks' tubes, an
  instrument station; and one for its lights (`shaders/env_lunar_lights.gdshader`: points that face the eye, never under
  a tenth of a degree, so a far light never shimmers). Live: `earthlight`, `base_lights`. The plain dims to 0.6 of its
  light with the house lights (never out).
- **The Athens roof and its city** (`rooftop` with `city` on, since 2026-11-08; `kit/athens_roof.gd`,
  `kit/athens_city.gd`; off, the rooftop is as it was). The roof made by hand: quarry tiles, the parapet with its
  coping and spouts, the screen building's weathered wall with ghost signs, the projection hut, the kiosk, the plants,
  the bulb strings. Its pieces share a few materials, one mesh each (ironwork, wood, painted wood, plaster, pots,
  leaves, canvas, three lamp glows by group), their own colours in vertex colours: 16 draws for the whole roof. The
  city round it is one mesh on one unshaded shader (`shaders/env_city.gdshader`): streets, blocks of flats with
  balconies, water tanks, solar heaters and aerials on the roofs, a church with a dome and two bell towers, a floodlit
  temple on a hill, a chapel on another, far hills with their lights. Its windows are drawn in the shader from each
  wall's bay and seed (lit, shuttered, curtained, louvred; faded to their average far off, so they do not shimmer);
  the Moon lights the walls from its side in the sky, the haze thickens with distance. The bulbs' halos are one
  mesh of quads that face the eye (`shaders/env_halo.gdshader`), dimmed with the house lights. Live parameters:
  `windows` (0..1, the share of lit windows' brightness; a film-time track turns it down through the night),
  `floodlight` (0..2, the temple's floodlights; a setting), `city_lights` (0..2, the streets' lamps and the church's
  light). The kiosk, the hut and the lemon tree's pot have collision boxes.
- **The whole drive-in** (`lot` with `drive_in` on, since 2026-11-08; `kit/drive_in_lot.gd`; off, the lot is as it
  was). Rows of bays on arcs fanned round the screen (`DriveInLot.bays()`), the ground as one fan grid with the
  lanes, ruts, oil and the parked cars' shadows in its vertex colours (unbaked, so it costs no lightmap), the posts
  (two speakers each, cables, an amber ramp light at the foot), `cars` parked cars (one coarse hardtop, a MultiMesh
  with its instances' colours; `parked()` keeps the viewer's bay, its neighbours and the bay straight ahead empty),
  the screen tower's back and frame, the snack bar with its booth (neon `snack_sign`, lit windows), the entrance
  marquee (`name`, the `board`'s two lines, a ring of chaser bulbs), a fence, and the highway behind. Live:
  `neon`, `chase` (the bulbs' run: 0 stops it), `ramp_lights`. Action `car_passes` (args `way`: 1 from -X to +X, -1
  back, none either): a car's head and tail lights cross the highway over 34 s. The parked cars' paint and chrome
  reflect as the car's do (`kit/reflect.gd`). The MultiMesh carries meta `env_placed` (its instances' transforms),
  so the sight-line check tests the cars where they stand. About 14 draws and 112k triangles with 30 cars (the
  parked cars 72k in one draw).

### `domestic`

A room in a house: walls, a window, a door, a fireplace or a radiator, wall lamps, and a screen. Four styles. Every
parameter left on "auto" takes the style's value (`domestic.gd STYLE_DEFAULTS`): an enum's `auto`, 0 for a size, -1
for a count that can be 0, `{}` for a material, `[0, 0]` for the screen's size. A document sets only what it changes.

| Style | What |
|---|---|
| `plain` | a sitting room: club chairs, a pull-down screen, a radiator under the window |
| `walnut_1962` | a private screening room: walnut panelling, a deep carpet, two rows of club chairs, a picture window (a pool beyond it: a vista), a brick fireplace, brass wall lamps, a painting over the screen |
| `bedroom_1993` | a child's bedroom: a pillow fort of cushions and a bedsheet on broom handles round the viewer's cushion, fairy lights along its front, a telly on a chest of drawers, a bed, a radiator under the window |
| `ice` | a room of ice blocks under a low vault, hides on the floor, candles in the walls, the picture on a smoothed panel of ice, the doorway open to the night |

- Size: `half_width`, `front_z`, `back_z`, `height`, `vault_rise`.
- The screen (`screen`): `projected` (a pull-down screen), `wall` (a panel on the wall), `painting` (a framed
  painting covers the screen and rises into a slot in the ceiling), `telly` (a set on a stand: below). Also
  `screen_size`, `screen_bottom`.
- `painting_open` (live, 0 to 1): 1 is risen (the screen shows), 0 is down over the screen. A cue fades it for the
  ritual (the `motion` system can move the `Painting` node too).
- `painting_art` (`abstract`, the default: soft blocks of colour; or `colour_field`: a hard-edged canvas of our own,
  a deep teal field, a vermilion sun over its edge, an ochre bar, a black line and a small square on a warm ground,
  the paint's strokes and the canvas's weave in it; since 2026-11-08) and `painting_frame` (true: the painting's own
  walnut frame; false: the kit frames the screen). With `shell` `kit` the builder still draws the painting and its
  ceiling slot (the Screening room 1962).
- `opening_screen` (not live: the room builds again): the telly fills the pillow fort's opening. The picture is as
  big as fits in the opening, just beyond it.
- The telly (`telly`): `cabinet` (a deep box, wider at the bottom for its buttons; the default), `portable` (a small
  deep case, its knobs and a speaker's slots on a panel to the right of the picture, a carry handle, a rod aerial) or
  `flat_panel` (a thin frame, a speaker strip under the picture, 7 cm deep; its picture is always 16:9, its height
  from its width). Left on auto, `screen_size` is the form's own: a portable 0.3 x 0.225 m, a flat panel 0.8 x 0.45 m.
- The eras' sets (`telly`), for the history of television:
  - `mirror_lid` (1937): a tall cabinet whose tube faces up in its top, and a lid hinged along the back of the top,
    open at 45 degrees, a mirror on its underside. The picture you see is the tube's reflection: upright, behind the
    mirror (7 cm out from the front wall), its bottom 5 cm over the cabinet's top. So `screen_for()` gives the
    reflection's place and the app's screen sits there. The tube's face lies under the top board (`TUBE_SINK`, 28 mm
    down), the hinge and the face 28 mm further out to match, so the face's reflection is still the picture's place.
    The mirror is a true one (`Mirror`, `scripts/env/mirror_view.gd`, 2026-11-08): for each eye a camera at the eye's
    mirror image renders what the mirror shows (its near plane on the mirror, its frustum the mirror's rectangle, off
    axis), into a small SubViewport the mirror's glass shows that eye (`shaders/env_mirror.gdshader`, old silvering:
    a little dim and warm, the edges slightly tarnished). The film lies on the tube's face (`TubePicture`: the
    screen's flat mesh and its material, so the presentation's tube, scan lines, switching and Wrong way round carry
    over, at the screen's mirror image), and the app's upright screen is hidden from every camera while the mirror
    shows (its render layers 0, given back when the room goes or hides). So the mirror shows the room in front of
    the set (the top board, the rug, the floor), and looking down into the cabinet the picture is on the tube, upside
    down as a real set's was; from the side or above nothing floats behind the lid. The mirror's glass is on its own
    render layer (19), which its cameras leave out, as they leave out the private layer (20): an agents' terminal on
    the screen shows on the tube but not in the mirror, so a room snapshot never sees it there. Cost: two more renders
    of the room a frame (no shadows, no MSAA), each `MirrorView.PIXELS_WIDE` (720) pixels across, the knob; no render
    while the mirror is out of view (80 degrees off the head's forward), seen from behind, or hidden (a 180 / 360
    film). The lid is its own mesh (`Lid`: see-through for the sight line, its back lies across the line of sight; in
    `env_in_front`, so the film layer steps aside). The cabinet is at least 0.7 m wide, so seats well to the side
    still see every corner in the mirror (tested from every seat). 0.3 x 0.24 m (5:4), its bottom 0.98 m. The lid is
    not a physics shape. Use the presentation's `tube` 1.25 (`mirrorlid_1937`).
  - `console` (1960s): a wooden cabinet on four splayed legs, the 4:3 tube over a speaker's cloth grille, two knobs.
    `telly_doors`: two doors, open and folded back beside it. 0.48 x 0.36 m, its bottom 0.62 m.
  - `rear_projection` (2002): a big deep cabinet from the floor (0.62 m deep below the picture, 0.36 m behind it,
    the back sloping between), a narrow frame round a grey-black screen, two speaker grilles under it. About 50
    inches: 1.016 x 0.762 m (4:3), or 1.107 x 0.623 m with `telly_aspect` `wide`. Its bottom 0.55 m.
  - `oled` (the present): a very thin panel (3 cm with its electronics), a hair's bezel, a true black glass, a slim
    pedestal on the stand or flat on the wall. Always 16:9; 1.21 x 0.68 m (55 inches).
  - The first three stand on the floor: `telly_stand` does not apply, and the screen is the set's depth and 5 cm out
    from the front wall. Left on 0, `screen_bottom` is the form's own.
- `telly_aspect` (`auto`, `standard`, `wide`): the picture's height from its width, 4:3 or 16:9. Auto: as
  `screen_size` gives it (a flat panel and an OLED always 16:9).
- `telly_doors` (bool): a console's doors.
- Its stand (`telly_stand`): `chest` (a chest of drawers, as before), `radiogram` (a long low cabinet on splayed
  legs, a grille of slats, two sliding doors), `desk` (a top, a pedestal of three drawers, legs, a modesty panel),
  `tv_unit` (a low cabinet with an open shelf under its top, 14 cm high, for a video recorder, and doors below) or
  `wall` (a flat panel hangs on it, its back at the wall; a cabinet or a portable sits on a shelf on two brackets).
  The picture stays where `screen_size` and `screen_bottom` put it; the stand is as tall as the space under the set
  (a flat panel stands on a 10 cm pedestal). A stand's back is at the front wall and its front at the set's (a
  flat panel's foot set back 12 cm on it). `stand_width` (0: its own, a little wider than the set) and
  `stand_shift` (metres sideways; the picture does not move) leave room beside the set. The stands are in the trim's
  material and drawn by `kit/furniture.gd`, as the kit's furniture is.
- On the wall, the picture is the set's depth and 3 cm out from the front wall; otherwise it is 0.5 m out, as before.
  `screen_for()` follows every form and stand, so the room's screen sits on the set's glass (tested for each form on
  each stand).
- `window` (`none`, `left`, `right`, `back`), `window_width`; `outside` (`glow` or `none`: a vista's or a sky's view
  shows through), `outside_top`, `outside_bottom`; live: `outside_glow`.
- `door` (`none`, `left`, `right`, `back`). In ice it is an open doorway with the night's glow beyond.
- `shell` (`drawn` by default, or `kit`, since 2026-11-08): with `kit` the builder lays out the room (its box, the
  window, the doorway, the screen, the seats' places and slots) and draws only the seats, the lamps and the fairy
  lights; the walls, floor, ceiling, window and doorway are a kit piece's (the Ice cinema's `ice_shell`, the
  Screening room 1962's `screening_room`). A `painting` screen is still the builder's (it rises on `painting_open`).
- `heater` (`none`, `fireplace`, `radiator`). The fireplace is on the wall across from the window. The radiator is
  under the window. Live: `fire`, `flicker`.
- `lamps` (on each side wall), `lamp_colour`; `fort`, `fairy_lights` (`auto`, `on`, `off`), `fairy_colour`; live:
  `fairy_glow` (0 to 1.5: the fairy lights' bulbs and the light they give, and nothing else).
- Seats: `seat_model` (`club`, `cushion`, `plush`, `director`, `folding`), `rows_front`, `rows_back`,
  `seats_per_row`, `seat_pitch`, `row_pitch`. Cushions are style `cushion`.
- `wall_pattern` (`plain`, `ice_blocks`, `plasterboard`) and materials: `walls`, `floor`, `ceiling`, `trim`,
  `surround`, `radiator_material`, `screen_surface`, `telly_material`, `cushions`, `sheet`, `seat_cover`,
  `seat_frame`.
- Slots: `side_walls`, `screen`, `proscenium`, `floor`, `ceiling`, `corners`, `window` (the pane: a weather system's
  `pane_center`, `pane_size`, `pane_yaw`), `vista` (beyond the window, facing in), `mantel`, `fort_opening`; with a
  telly, `telly_stand` (the stand's top at its front middle, facing the room: a piece on it goes at a negative z; on
  the wall, the floor under the set) and `telly_shelf` (a video recorder's place: the tv unit's shelf; a desk's or a
  radiogram's top beside the set when there is half a metre; else the floor in front of the stand). A console's and
  a rear projection's `telly_stand` is the set's own top; for a set on the floor `telly_shelf` is the floor in front.
- Measured: plain 13 draws, 4k triangles; walnut 16 draws; bedroom 18 draws, 6k triangles; ice 11 draws, 12k
  triangles. 4 to 10 MB. A telly on its stand adds no draw of its own (the set is one mesh, the stand is in the trim):
  each form on each stand in a plain room is 12 draws and 3.8k to 4.2k triangles. In a small plain room
  (`test_env_domestic.gd`): an OLED 12 draws, a console and a rear projection 13 (their cloth), the mirror-lid set 14
  (its lid and its mirror), 2.2k to 2.4k triangles.

### `vehicle`

The inside of a generic 1950s convertible with its top down, facing the screen (on the terrace's lot). No mirror, no
badge, no maker's shape.

- A front bench and a rear bench, three places each (style `bench`). The viewer is in the middle of the front bench,
  at the origin. The left place has the steering wheel in front of it; the wheel's top is under 1.05 m.
- The wraparound windscreen's top is under the eyes (1.12 m), so the view of a screen up on a lot's frame or tower
  goes over it. Its glass is see-through.
- Parameters: `ground_y` (the ground under the car; the wheels show when it is under the body), `rear_seat`, `top`
  (`folded` or `none`), `fins`; live: `headlamps`, `dial_glow`; `dial_colour`; materials `body`, `chrome`,
  `upholstery`, `piping`, `carpet`, `tyres`, `hood_cover`.
- Since the drive-in's quality pass (2026-11-08) the body is lofted from sections (`kit/car_shape.gd`: the bonnet's
  crown, the belt line into the fins, the arches, the side spear), with a jet ornament, bumpers and grille, a lit
  dash (`shaders/env_dash.gdshader`: speedometer, radio, gauges, and a clock whose hands follow the sky's `hour`), a
  big thin wheel, tuck-and-roll benches and the lot's speaker on the door. More parameters: `dash_light` (the dial
  light's stand-in lamp on the benches), `trim` (the dash pad's colour), `speaker`; live: `reflect_screen` (how much
  of the screen the paint and chrome show), `glint_at`, `glint_colour`, `glint_energy` (a light seen in the chrome:
  the snack bar's neon). Paint and chrome use the house shader's `REFLECT` (`kit/reflect.gd`): the sky's colours,
  the skyline, the ground, the screen with its picture and the glint, refreshed each frame from the `sky` system and
  the screen; no probe. `reflective_materials()` gives them (the tests).
- It brings no screen. `screen_for()` gives the lot's, so a test room has one.
- Slots: `dash`, `bonnet`, `rear_shelf`, `floor`.
- Measured: 9 draws, 24k triangles. Not baked: its occlusion (the cabin's floor, the footwells) is in its vertex
  colours.
- **Shared pieces the drive-in added** (each off by default, so every other room is as it was): `RoomMesh.grid()`
  (a grid of rows of points with normals and colours) and `RoomMesh.shade(f)` (darkens the vertex colours by a
  function of position: baked occlusion); `room_lamp.gdshader` and `kit/env_flame.gdshader` `use_vertex_colour`
  (many lamps of different colours in one draw); `kit/env_glass.gdshader` `sky_colour`, `sky_mix` (glass at a
  grazing angle shows the sky, not grey); the house shader's `REFLECT` define
  (`shaders/room_material_house_reflect.gdshader`, through `kit/reflect.gd`).

### The film layer and the builders

On the Frame the film is a layer drawn over everything between the eyes and the picture
(`scripts/play/film_layer.gd`). The builders keep everything solid out of that space (the sight-line check holds
it). Glass in front of the picture (a windscreen) would simply not show over the picture there. Two parts can come
in front of the picture on purpose: the domestic painting when it is down (`painting_open` under 1), and the pillow
fort's hem and fairy lights if a seat's eyes are lower than the check's 1.2 m. The film layer hides them while a film
plays unless it steps aside. It steps aside today only for physics objects, the controllers and the laser
(`_covered()`). The painting's ritual happens before the film, so the picture under the painting is usually black,
but the layer still draws there. This needs a hook from the film layer (a room's parts that cover the screen); it is
an open question below.

## A room's screen and its builder

A document gives the screen (`screen`: centre, size, curve). Two things follow from it in `env_room.gd`:

- **Its curve.** `get_home_curve()` gives `screen.curve` (0..1), and the app's screen starts with it until the viewer
  sets a curve of their own (`scripts/play/curved_screen.gd`). A flat screen in a room that curves by itself is kept
  as 0, so it stays flat.
- **A builder that moves it.** A builder with a static `screen_for(params)` (shopfront, nave, dome_hall, domestic)
  says where it puts the picture. The room takes that place for the document's parameters (with every room setting at
  its default) as the document's own; when a setting rebuilds the room (`env_host.gd` signal `rebuilt`), the screen
  moves and resizes by the builder's change, and the app places the film there again (the seat's `home_screen()`).
  Tested in `app/tests/test_env_screen_follow.gd`.
