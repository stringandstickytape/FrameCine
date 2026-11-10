# The kit

Part of the environments engine: [`docs/environments.md`](../environments.md) has the design and says where each part is.

`scripts/env/systems/kit.gd`, kind `kit`, with the pieces in `scripts/env/systems/kit/pieces.gd`. A document lists
the pieces. The kit must come after its builder in the document. A room may have two kits, each with its own id
(their nodes keep apart: see `own()` above).

```json
{"system": "kit", "params": {"pieces": [
  {"piece": "niche", "slot": "side_walls", "index": 4, "holds": "lion", "at": [0, 1, 0]},
  {"piece": "bougainvillea", "slot": "parapet", "index": -1},
  {"piece": "snack_bar", "at": [0, -0.5, 16], "yaw": 180, "text": "SNACKS"}]}}
```

| Key | What |
|---|---|
| `piece` | which piece (below) |
| `slot`, `index` | a slot of the builder and which of its places; `index` -1 is every place. No slot: `at` is in the room's frame |
| `at`, `yaw`, `scale` | an offset in the slot's frame, a turn about the vertical (degrees), a scale |
| `size` | width, height, depth; 0 takes the slot's size (for façades, curves, ivy, bougainvillea, balcony fronts, partitions) or the piece's own |
| `holds` | what a niche holds: `urn`, `lion`, `obelisk` or `none`; a computer with `none` has no monitor |
| `colour`, `accent` | the piece's main colour, and a second one (a rug's border, a lamp's pole) |
| `text` | a neon sign's words in our own letters: A B C D E F I K L N O P R S T U W and the space |
| `target` | the node the carpet goes on (the builder's `Floor` by default) |
| `pattern` | the carpet's pattern, one of `procedural.gd`'s (`swirl_carpet` by default; `deco_carpet`: rising suns in rows, since 2026-11-08; `shell_carpet`: scallop shells in rows, since 2026-11-08) |

Other parameters: `builder` (the builder's id; empty: the room's first builder); materials `stone`, `plaster`,
`wood`, `tin`, `roof`, `iron`, `plastic` (a computer), `fabric` (a rug), `china` (a tea set, plates), `cloth`
(bunting, sandwiches; the last two coloured per vertex), `gilt` (a palace gate's mouldings, the organ's grilles),
`drapes` (a palace gate's drapes and swags); `glass_colour` (a glass table's top); colours `leaves`, `flowers`, `neon`,
`window_colour`, `lamp_colour` (a standard lamp's shade), `display_colour` (a video recorder's clock); `bake_lamps`
(how many of the pieces' lamps light the room, 4 by default: a stand-in lamp while there is room for one, a hidden
light in the bake); live: `glow` (lit windows, the booth's window, neon, the clocks), `night` and `ember` (the
courtyard's windows going out one by one, and what one that has gone out still shows), `water_motion` (a fountain's
water; the Motion setting scales it), `flicker` (how much the pieces' candle flames waver, slowly; 0 by default,
Flickering lights holds them). Two more entry keys for the courtyard's pieces: `features` (a house's
features, below) and `seed` (its own variation). For the moderne hall's pieces (since 2026-11-08): materials
`faience` (glazed tiles: it shines, a clear glaze) and `chrome` (it reflects the room: `kit/reflect.gd`), `group` (the
pieces' meshes under one node of that name, so a motion system moves them together: an organ console on its lift),
and live: `cove` (the coves' lamps, times the house lamps' level), `cove_colour` (their light: a setting or a cue
moves it), `cove_film_colour` (their light in the film: bind it to `film.colour`) and `cove_film` (0: `cove_colour`,
1: `cove_film_colour`). For the Palace of Culture's hall (since 2026-11-08): material `mosaic` (the bed under a wall
mosaic's tesserae; `white_marble` by default), `mosaic_glint` (how much gold and glass glint, 1) and `mosaic_wash`
(the lamp line's wash down the mosaics, times the house lamps, 1.6). For the Flagship's hall (since 2026-11-08), live:
`starlight` (a starlight ceiling's pinholes before the film; 0, the default: none) and `starlight_film` (the share of it
kept while the film plays, the house lamps out; 0 by default); the hall eases the stars to their level over about a
second, so a setting never makes them jump. The Flagship's wash uses `cove`, `cove_colour` (and `cove_film`) as the
moderne hall's coves do. For the Pink Palace (since 2026-11-08): `reflect_wall` and `reflect_ground`, what the
reflecting materials (gilt, chrome, glaze, mirrors) see round their horizon and below at full house light (the
Streamline's walnut [0.16, 0.12, 0.09] and jade-black by default; the Pink Palace's a rose hall, so its gilt reads
gold and its mirrors rose).

| Piece | What |
|---|---|
| `balcony_front` | a moulded parapet panel with a rail, bands and round bosses |
| `niche` | pilasters, an arch, a shell hood, a darker back and a shelf, holding an urn, a lion or an obelisk. Never a figure or a torso |
| `urn`, `lion`, `obelisk`, `column` | on the floor; the lion lies on a plinth, its head up |
| `facade` | a courtyard's plastered wall with a cornice, a tiled eave, two arched windows lit from inside, shutters, an iron balcony |
| `castle_gate` | towers with battlements and arrow slits either side of the screen, a wall over it, a raised portcullis whose teeth hang just above the picture. Sized to the room's screen |
| `booth` | a projection booth of corrugated tin, its window lit towards the screen (`booth` group) |
| `snack_bar` | a counter, shelves, a canopy, a neon sign (`signs` group) |
| `screen_tower` | a drive-in's tower behind the room's screen: the face, posts and braces |
| `bougainvillea`, `ivy`, `ferns` | leaves (unbaked): bougainvillea over a parapet's top and down its face, ivy up a wall, ferns in a clump on the floor |
| `carpet` | the builder's floor takes a carpet's pattern (`pattern`; the swirls by default) |
| `partition` | a plasterboard wall with taped joints and a skirting |
| `curves` | two bands in waves along a wall (pink and blue by default) |
| `desk` | a top, a pedestal of three drawers on its right, legs on its left, a modesty panel (`wood`, handles in `iron`). 1.2 x 0.74 x 0.65 m |
| `computer` | a flat beige case with two drive slots, a CRT monitor on it, a keyboard with its rows of keys in front (`plastic`, the glass and slots in `iron`). `holds` `none`: no monitor (a telly is its screen) |
| `video_recorder` | a slim case (`iron` in the entry's colour), the cassette's door, five buttons, a display window whose clock flashes 12:00 (below). 0.43 x 0.09 x 0.3 m |
| `sideboard` | doors either side, three drawers between, short legs, the top overhanging (`wood`, handles in `iron`) |
| `standard_lamp` | a round base and a thin pole (`iron`, or the entry's `accent`), a drum shade that glows in the entry's colour (`house` group) and gives a dim stand-in lamp |
| `rug` | a field (`fabric` in the entry's colour), a border a little raised (its `accent`, or the field's darker), a fringe at either end |
| `coffee_table` | a top on four legs, a shelf under it (`wood`) |
| `bunting` | a string across a room sagging by the size's height, a pennant every 0.26 m, red, white and blue in turn (`colour`, white, `accent`); it hangs from its point (`cloth`) |
| `tea_set` | a tray (`wood`), a teapot in the entry's colour, a milk jug, a sugar bowl, four cups on saucers (`china`) |
| `sandwiches` | a plate (`china`), triangles of bread with the filling between (`cloth`, the filling in the entry's colour), two layers |
| `stool` | a round seat on four splayed legs with rungs (`wood`). 0.36 x 0.46 m |
| `channel_dial` | a rotary channel dial: a plate (`plastic` in the `accent`), twelve stops, the knob and its pointer, two small knobs under it (`iron`); it hangs on a set's front, in the strip beside the picture |
| `soundbar` | a long low case (`iron`), its cloth front (`fabric` in the `accent`). 0.9 x 0.065 x 0.09 m |
| `floor_lamp` | a flat base, a slim pole, a tall column shade that glows in the entry's colour (`house` group) and gives a dim stand-in lamp |
| `glass_table` | a low coffee table: a steel frame (`tin`), a glass top (the kit's glass mesh `PieceGlass`, `glass_colour`, in `env_see_through`) |
| `media_unit` | a long low cabinet on a dark plinth set back under it, three doors without handles (`wood`) |
| `boat_stove` | a narrowboat's stove (since 2026-11-09, the Narrowboat's saloon): a hearth plate on the floor, a body on four short legs, a top plate, a door with a small window, a round flue of 8 sides straight up to 2 m with a collar near its top (`iron` tinted: the body [0.05, 0.05, 0.055] or the entry's `colour`, the door 1.3 times it, the plate [0.16, 0.15, 0.14]). The window glows steady with the lit windows (`PieceWindows`, `window_colour`); it lights nothing. 0.4 x 2.0 x 0.38 m; another size stretches it along each axis |
| `show_stage` | a low stage under a hall's picture: a wooden platform, a moulding along its front top edge, seven iron footlight hoods. The hoods do not glow. `wood` tinted [0.2, 0.13, 0.08] or the entry's `colour`, the moulding 1.4 times it; `iron` tinted [0.05, 0.05, 0.055]. 7.2 x 0.6 x 1.2 m; another size stretches each axis. One collision box for the platform |
| `house` | a courtyard's house front along a wall (`kit/courtyard.gd`): `size` [width, the eave's height, how far its face stands out]; its wash `colour`, its shutters' `accent`, `seed`, `features`. Two or three storeys of windows lit from inside, a socle on the ground, string courses, quoins, an eave of tiles on rafters |
| `palace_gate` | round the room's screen: two towers (a rusticated base, an organ's grille in a tall arch, a belfry with a bell, a pyramid roof with a gilt finial), a great segmental arch over the picture with a balustrade and urns against the sky, gilt mouldings, a keystone cartouche, velvet drapes and three swags with gilt fringe; four floodlights for the bake. `size` [the room's width, 0, depth] |
| `cypress`, `palm`, `pine` | trees beyond the walls: `size` [spread, height, spread]. A cypress of jittered rings, a palm with feather fronds, a stone pine's umbrella of clumps |
| `lantern` | a wall lantern on an iron bracket, its glass glowing (`house` group; a stand-in lamp and a bake light) |
| `pedestal` | a stone pedestal; `holds` `lion` (lying, head up) or `urn` |
| `ice_shell` | an ice hall over a domestic builder with `shell` `kit` (`kit/ice_hall.gd`): the floor of packed snow, walls of sawn ice blocks in courses cut round the window, the doorway and the candle niches, the vault of ice blocks on ribs of clear ice with skylights in its haunches, the window's and the doorway's reveals, a candle in each niche and one on the window's sill |
| `ice_screen` | round the room's screen on the front wall: a smoothed panel, a carved frame of three frosted steps, animals in relief (a polar bear, a whale, a fox, a hare, a snowy owl with its wings spread over the picture) with their lines cut in, a candle niche either side |
| `ice_benches` | a bench of ice under each row of the room's seats (the seats system's `hide` lays the pelts on it) |
| `ice_outside` | the night outside an ice hall: a snowfield with drifts, snow banked against the walls, the path from the doorway, spruces under snow, the forest's edge, the fells, a cabin far off with its windows lit |
| `moderne_hall` | an auditorium builder's hall as a 1930s moderne one (`kit/streamline.gd`, no slot): a ceiling of coves stepping up to the screen, ledges with their coves along the walls, speed bands of faience, jade and chrome round the hall and across a bowed circle front, rounded rear corners, a walnut dado, reeded pilasters, etched glass shell lights (stand-in lamps and bake lights), ventilators |
| `ziggurat` | round the room's screen (no slot): three frames stepping out towards the seats, each lit from behind the next, gilt reveals, a glowing rising sun with gilt rays and chrome speed lines, two organ grilles lit from their chambers, a clock telling the real time (`PieceClock`), a speed-line roundel, footlights (stand-in lamps in the coves' colour) and the lift's chrome ring in the pit |
| `culture_hall` | an auditorium builder's hall as a 1970s palace of culture (`kit/palace_culture.gd`, no slot; set the auditorium's `side_walls` false and `ceiling_cover` 0): board-marked concrete walls, a wall mosaic either side (`kit/mosaics.gd`, the cosmos and the earth, on the house shader's `MOSAIC`) in a bronze frame under a cornice with its lamp line, a coffered ceiling with a roof light over the back rows (snow on its ledges), a stepped concrete proscenium with ribs and a bronze edge, oak slats on the rear wall, the booth's band and a 1970s clock (`PieceClock` `style` 1) |
| `globe_field` | 60 opal globes on rods from a `culture_hall`'s coffers, hung in a bell (`PieceLamps`, `house` group, `rim`); each lights the coffer over it (`PieceCove`) |
| `pink_hall` | an auditorium builder's hall as the inside of a great scallop shell (`kit/pink_palace.gd`, no slot; set the auditorium's `side_walls` false and `ceiling_cover` 0): rose marble dado, tall round-headed mirrors with gilt glazing bars and bevels, fluted pilasters with gilt shell capitals and pink glass shell sconces (bake lights), a frieze of breaking waves white on blue, a cornice whose hidden lamps light the shell vault (`PieceCove`: forty ribs fanning from the dome's rim, pink crests, blue troughs, a gilt line on each crest), gilt shell hoods over the front exits, a great blue and gilt shell on the rear wall |
| `pink_proscenium` | round the room's screen (no slot): five fluted, scalloped rings stepping towards the seats (a superellipse round the picture's middle, each wider and higher), each lit from behind the next, blue and pink in turn, gilt reveals and beads; a blue and gilt shell crest; thirteen gilt shell footlights on the stage's lip and four stand-in lamps in the coves' colour for the festoon |
| `pink_balcony` | the balcony's front (`balcony_rows`): buttoned pink velvet (`fabric` with `tufted`) rolled over the parapet under the front row's sight line, gilt beads, seven pink glass fans; a soffit with ten downlights and their pools (three bake spots) |
| `pink_dome` | an oval dome in the vault's crown over the stalls (put it in a kit of its own: its coves have their own colour): a gilt lip hiding the lamps that light the drum and the dome from its foot (rose by the rim, deepening blue to the apex), a gilt sunburst of 32 rays, a rosette, and a chandelier of 24 pink glass shells in three tiers round a glass drop (a stand-in lamp and a bake light) |
| `screening_room` | the Screening room 1962's room round a domestic builder with `shell` `kit` (`kit/screening_1962.gd`, no slot): walnut panels standing off the walls with shadow gaps between them (two cuts of the veneer in turn, each its own shade), a screen wall of walnut slats over black felt with the picture in a deep walnut frame and a brass bead, a coffered ceiling of walnut beams over cedar boards with brass downlights and two wall-washers, a floor-to-ceiling window in slim bronze frames (its own faint glass, `WindowGlass`), linen curtains in deep folds at its ends, a flush door with a brass pull, floor-to-ceiling shelves of books and film cans round the projection port, three brass up-and-down sconces, a dark carpet and a burnt-orange rug |
| `screening_hearth` | the chimney breast in brick on the right wall, a floating slate hearth running past it either side with logs stacked under its ends, the firebox (firebrick, a grate, three logs, embers, slow flames: the hall's `Glows`), a steel lintel, fire tools, a sunburst clock with walnut and brass whose hands keep the real time (`ClockHour`, `ClockMinute`) |
| `screening_furniture` | a floating walnut credenza under the screen (film cans, a glazed bottle, a walnut bowl on it), a brass bar cart with two crystal decanters, tumblers, a siphon, an ice bucket, lemons and bottles, a surfboard coffee table (a cigar box, a bowl, a book), a tripod floor lamp with a linen drum shade, a sheepskin before the hearth |
| `screening_garden` | outside the window (one unshaded mesh, `Garden`, `shaders/env_screening_outside.gdshader`, its light worked out per vertex): the eaves running on over the terrace, big concrete pavers, a pool glowing turquoise right outside the glass (its light rippling on the coping, the eaves and, in `Glows`, the ceiling inside), agaves in concrete bowls, palms down the slope, a low wall at the terrace's edge, the city's lights far below to the horizon (in `Glows`) |
| `flagship_hall` | an auditorium builder's hall as a modern premium auditorium (`kit/flagship.gd`, no slot; set the auditorium's `side_walls` false, `ceiling_cover` 0, `proscenium` none, `handrails` false): folded acoustic walls in charcoal felt with bronze fins over a walnut dado, a light slot between them washing up the folds (per vertex, the house shader's `vertex_light`), a handrail with a warm line under it, cove ledges with a cool wash on the ceiling's edges, long baffles with starlight between them (`starlight`), black velvet masking on the picture's curve in a slim bronze frame, a proscenium of walnut slats, a perforated grille on the stage's front, surround speakers, walnut slats and a band round the projection port on the rear wall |
| `flagship_rows` | the rows' furniture round the `recliner` seats: fixed leather armrests between the seats and at the rows' ends, a brushed-steel cupholder ring on each, the seat's number engraved on a plate (`SeatNumbers`), lit row letters A to N on the end arms (`RowLetters`, the steps' group), steel nosings on the aisle steps, a frameless glass balustrade with a lit cap rail at the front row |
| `organ_console` | an illuminated organ console on its lift platform, its foot at `at`: a skirt of glass panels in the coves' colour between gilt fins, an ivory horseshoe of stop tabs, three manuals, a lit music desk under a chrome hood, a bench. Put it in a kit of its own with `group` |
| `ruin_shell` | a ruined picture house round an auditorium builder with `shell` `kit` (`kit/reclaimed.gd`, no slot): brick walls under fallen plaster with damp, pilasters and a cornice, the proscenium with faded gilt and lattice grilles, the stage, the stained sheet and its fallen masking, a torn curtain, the pit's broken boards, the booth's ports, two doorways |
| `ruin_roof` | the ruin's roof: the front half's coffered plaster ceiling with holes, its broken edge (snapped joists, dangling laths), the trusses over the open half, purlins, rafters and slates, a hole through the front roof |
| `ruin_stalls` | the ruin's stalls: the fallen chandelier and its crystals, rubble and fallen bricks, the aisles' rotted carpet, leaves on the seats |
| `ruin_growth` | the ruin's nature: ivy masses and cascades, a birch, ferns and hart's-tongue, grass and wildflowers, moss, leaf litter |

The furniture is drawn by `scripts/env/systems/kit/furniture.gd` (plain boxes and turned shapes of our own: no maker's
shape, no badge, no lettering), which the domestic builder's telly stands use too. A piece stands with its foot at the
slot's point and its front towards the slot's +z; the domestic builder's `telly_stand` and `telly_shelf` slots are
made for it (the computer on a desk beside a portable, the video recorder in a tv unit's shelf).

**The courtyard's houses** (`kit/courtyard.gd`, since 2026-11-08). Each house samples the ground under it (the
stage, the aisle's rake), so its socle meets the floor and its storeys stand level. Its `features`: `balcony` (an
iron balcony with real depth on brackets), `balconettes` (one at each upper window), `loggia` (an open top storey on
columns), `tower` (a belvedere with arches and a pyramid roof), `pergola` (beams and leaves for a roof), `gable`
(a pediment instead of an eave), `oriel` (a Moorish bay on corbels, its lattice lit), `exit` (an arched way out with
the room's sign), `door`, `niche` (an urn in a shell niche), `lion_niche`, `fountain` (a wall fountain: blue and
white tiles, a lion's mask, a basin with moving water), `lanterns`, `vines` (bougainvillea up the wall and over the
balconies), `rug` (a rug hung over a balcony rail), `geraniums` (pots on the sills), `grilles` (iron grilles on the
ground floor's windows), `booth` (the projection ports with the lens glowing), `arcade` (an open ground floor of
arches) and `dark` (no one home: every window dark). Each window is one of six rooms behind (a curtain drawn left,
right, both with a lamp, a plant on the sill, inner shutters half closed, an organ's pipes) drawn by
`shaders/env_courtyard_window.gdshader` from the window's own coordinates, never from a picture; a few are dark.
The windows' material is the light system's lamp material (house group), so they dim with the house lamps; `night`
puts them out one by one, each at its own moment (each over a twentieth of `night`'s travel), down to `ember`. The
windows bake as emitters: their glow lights the reveals, sills and shutters round them.

**The ruin** (`kit/reclaimed.gd`, since 2026-11-08, for Reclaimed). Its four pieces read the auditorium's layout
and draw into meshes of their own: `RuinBrick`, `RuinPlaster`, `RuinWood` and `RuinCloth` (baked, on the house
shader with `vertex_light`: the Moon's light, traced per vertex as the room is built, in the vertex colours' alpha),
`RuinBrass` and `RuinLeaves` (unbaked, the Moon in their vertex colours), `RuinCrystal` and `RuinPort` (emission).
It also tints the auditorium's `Floor` and `Seats` by the same Moon. See "Room: Reclaimed".

**The ice hall** (`kit/ice_hall.gd`, since 2026-11-08, for the Ice cinema). Its pieces read the room's domestic
builder (its box, window, doorway, screen and seats) and draw into meshes of their own: `IceBlocks` (the walls' ice,
baked), `IceVault` (the vault: smooth strips on the ice shader, its courses drawn by `ice_vault`, baked), `IceSnow`
(the joints, baked), `IceFloor` (the floor on the ice shader's snow form, `ice_snow`, baked), `IceFurs` (pelts on the
floor, baked), `IceCandles` and `IceFlames` (the candles: wax and dish lit by their own flames, all emission in vertex
colours on the lamp material; the flame and its halo in one picture; in the light system's `accent` group, the front
wall's in `house`), `IceGlass` (the skylights' and the window's clear panes, see-through) and `IceOutside` (the night, its own
unshaded shader `shaders/env_ice_outside.gdshader`: lit by the sky's colours, the Moon and the aurora, never by the
house lights; the snow glitters a little where a facet catches the Moon, still in the world). The ice is the light
system's house material on `shaders/room_material_house_ice.gdshader` (`ICE` in `room_material.gdshaderinc`): what is
frozen inside a block (bubbles in strings, cracks, a milky cloud: one tileable map made in code) is drawn at two depths
along the view, so it moves against the face as the head moves; the light that reaches the ice (a lightmap's) shows on
those, at depth, while the clear face takes little; the candles' glow is scattered inside the ice round each candle
(`ice_glow_*`, the room's frame, their group's level each frame); the film's colours seep through the front wall round
the screen (`ice_film`); the candles glint and the picture shows softly in the wet faces at a glancing look. The vertex
colour's alpha says what a surface is: 0.5 to 1 a block, milky to clear (and its own seed for what is inside it); under
0.5 frosted: the carvings, the frame, every block's sawn edges. The candles light the bake (the kit's lamps, hidden)
and the Moon comes in through the window for it (a hidden spot from the sky's Moon). More of `ICE`, each off by
default (since the second pass, 2026-11-08): `ice_glow_face` (the candles' light on the faces round them: a niche lit
warm inside), `ice_vault` and `ice_vault_block` (a vault laid in courses: joints packed with snow, frosted edges,
each block its own seed, shade and tilt, all from the point's place on the arch), `ice_snow` (packed snow instead of
ice: boot prints pressed in, shaded by the normal they tilt, and a sparkle near the eye that changes only as the head
moves; no candle loop), `ice_shine` (the picture's share of the gloss).
**The moderne hall's coves** (`kit/streamline.gd`, `shaders/env_cove.gdshader`, since 2026-11-08: "the coves are the
star: soft graded colour washing up curved surfaces, not flat fog quads", the brief). Every surface a hidden lamp
washes (the ceiling's bands, the ledges' rounds, the proscenium's frames, the organ grilles' chambers, the rising
sun, the console's glass) is one mesh, `PieceCove`, on its own opaque shader. The light on it is worked out when the
mesh is built, per vertex (the alpha of its colour): each lamp a line along its trough, its light the cosine
(softened: plaster scatters) over a fall-off to half at a metre or so. The shader adds it in the cove's colour (and
a whiter core where it is strongest) to the house shader's own light (the fill at the house level, the screen's
spill at 0.6 of the room's) and a faint mottle of the plaster; one noise fetch, no loop, no light pass, nothing
transparent. Its colour and energy are live (`cove_colour` toward `cove_film_colour` by `cove_film`; `cove` times
the house lamps), so a setting, a cue or the film moves it without building the room again. It is not baked: the
bake takes the slots' light from a hidden lamp in each (`KitGlow*`). Footlights at the stage's lip and two battens
behind the first frame's head are stand-in lamps in the coves' colour (they light the festoon's folds and the
console, which are never baked). `cove_state()`, `cove_colour_now()` and `clock_hands()` give the coves and the
clock now (tests).

**The palace of culture's hall** (`kit/palace_culture.gd`, `kit/mosaics.gd`, since 2026-11-08). A piece may add a
hall to the ctx's `halls`: an object with `finish(kit)`, called once every piece has drawn (the hall puts its own
meshes in, here `Mosaic`, and sets the clock's face), and `tick(delta)`. The mosaics are one static mesh on
`shaders/room_material_house_mosaic.gdshader` (`MOSAIC` in `room_material.gdshaderinc`, off in every other form):
`mosaic_map` holds one texel a tessera (rgb its colour, alpha its kind: 0 stone, 0.5 glass, 1 gold); the shader lays
the courses in the mesh's UV (metres), each tessera fetched at its middle, with uneven joints of `mosaic_grout`
(antialiased by the pixel's footprint, thinning to `mosaic_joint` far off), a shade, a tilt (`mosaic_tilt`) and a
worn edge of its own (`mosaic_wander`). The glint is a sharp lobe (`mosaic_glint_sharp`) of the light from
`mosaic_glint_pos` (the room's frame) and of the screen's spill (`mosaic_film_glint`), weighted by the kind cubed
(gold glints, glass a little, stone hardly) and tinted by the tessera; it moves only as the head moves.
`mosaic_wash` (rgb, w the fall in metres) washes down from `mosaic_wash_y` at the house lamps' level. The lamp shader
`room_lamp.gdshader` has `rim` (0 by default: off): a glowing ball brighter where it is seen square on. The clock
shader `env_clock.gdshader` has `style` (0 by default: the moderne face; 1 a dark dial with lit bars).

**The video recorder's clock.** 12:00 in seven segments of our own (quads, no font, no texture of letters), in
`display_colour`, all the room's clocks one mesh (`PieceDisplay`, accent group). It flashes once a second: lit half a
second, dark half a second, each change eased over about 0.2 s (slower than the photosensitivity ceiling's fade). The
room's Flickering lights off holds it lit. `clock_level()` gives its level now (tests).

- **Cost by material:** all the pieces share a baked mesh (`PieceStatic`) and an unbaked one (`PieceSoft`), one
  surface a material, plus the lamp shades (`PieceLamps`, one draw a shade colour), one draw for the lit windows, one
  for booth windows, one for the clocks and one a neon sign. Thirteen pieces in the atmospheric test take 10 draws.
  Triangles: desk 108, tv unit 100, radiogram 182, sideboard 162, coffee table 64, computer 132, video recorder 112
  and its clock 42, standard lamp 128, rug 22.
- **The auditorium's slots:** the auditorium has no `slots()`, so the kit works them out from its parameters:
  `side_walls` (every 2.5 m on both walls, at the side aisle's floor), `proscenium` (the stage's top), `rear_wall`,
  `corners` (the pit's front corners), `floor`, `ceiling`, and `balcony` when it has one.
- **Physics:** the pieces' boxes follow the builder's slots, so they exist once the room is built
  (`collision_shapes()`); there is no static form.
- **Problems:** a slot the builder lacks, or an index past its places, is reported by `problems()` and the piece is
  not placed.
- Measured: bougainvillea along the rooftop's 14 parapet places: 2 draws, 23k triangles. The Atmospheric 1928's
  courtyard (since 2026-11-08): 16 draws, about 77k triangles (its room section has the parts).
