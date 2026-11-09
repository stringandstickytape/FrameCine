# Reclaimed

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

`app/environments/reclaimed.env.json`. *An old picture house taken back by nature: half its roof gone to the stars,
ivy on the walls, ferns in the corners, rain into a puddle that gives back the film, birds on the broken roof,
fireflies and now and then a deer.* The deep pass (2026-11-08) answered "continue working on the environments
one-by-one like you did with the bathysphere, really improving their quality, imagination, delight, detail, lighting
and so on. Better to do a smaller number of incredible superb ones than a large number not so" (the user). Before it
the room was the auditorium's own hall with half its ceiling taken away: plain painted brick, dark drapes, the
picture on the black front wall, clumps of the kit's ivy and ferns, and the film's spill lighting it all. The seats,
the eye height and the screen are where they were. The auditorium now draws only the tiers and the seats (`shell`
`kit`); the ruin round them is `kit/reclaimed.gd`, in four pieces (`ruin_shell`, `ruin_roof`, `ruin_stalls`,
`ruin_growth`). A second pass the same day answered the coordinator's look at the renders: the plaster's holes
read as pale paper on a dark wall, the upper walls as flat polygons; the floor stayed bright in the film; the film's
warm and cool halves lit the walls; the rear wall was plain.

- **The walls:** brick (laid in courses, each brick its own shade) under cream plaster fallen away in ragged holes.
  The plaster is the lighter surface and the brick in a hole the darker (a hole reads as a hole, not as paper stuck
  on): the brick darkens towards the plaster's edge (its lip shades it, dirt collects), and the edge itself is a lip
  3.5 cm thick in paler broken plaster (`PLASTER_BREAK`), its face fading into the paint. Damp runs down from the open
  roof with tide marks and green stains; an oxblood dado, pilasters (broken off where the roof went), a cornice; the
  walls' broken tops ragged against the sky, with their thickness. A doorway in the left wall by the stage (a leaf
  hanging open, the night outside). The rear wall decays as the side walls do (plaster fallen in sheets from the top,
  rising damp and a tide mark at the foot, blooms, green runs, a dado rail broken where the plaster fell); the rear
  door to the foyer with a stopped clock over it (a brass bezel, its glass gone, bars for the hours, twenty to four);
  three projection ports, each in a moulded plaster surround with a sill, soot over it where the lamp's heat came out,
  and its steel fire shutter on rusted runners (the left one down halfway, the right one fallen askew, the middle one
  up: its lens still lit).
- **The proscenium:** a plastered arch with faded gilt mouldings, a cartouche and swags over the opening (no
  figures), two lattice grilles either side where the organ spoke once, plaster fallen to brick here too. The screen:
  an old sheet behind the picture, stained at its edges, in black masking whose top right end has come down; the
  stains and the masking never cover the picture (the picture's frame is checked from every seat). A torn red curtain
  on the left in tatters to the floor, a strip of it on the right with its heap below, the valance hanging in rags.
  The stage of boards, some gone (joists and the dark below), a panelled riser, the pit's boards with holes.
- **The roof:** the front half's ceiling, plaster on laths, coffered, with holes through to the dark roof space and
  one right through the roof (stars show through it from the seats); its broken edge over the stalls: snapped joists,
  some hanging, laths dangling, lumps of plaster. Over the open half three king-post trusses against the sky (the
  rear one broken, a rafter down), purlins and the ridge, a patch of rafters and battens with slates on the right
  slope, slates slid and caught, the gables' coping.
- **The stalls:** the plush seats faded (velvet, walnut-veneer backs), 13 tipped up and 8 broken (the seats
  system's `up` and `broken`, never the viewer's own), leaves and moss on some; the aisles' carpet rotted to the
  boards in patches; rubble and fallen bricks along the walls, a heap under the left wall's break. The chandelier
  lies where it fell, off to the right of the pit: a brass column, three rings, eight arms, a basket and festoons of
  crystal drops and prisms scattered round it, catching the moonlight (fixed glints in their vertex colours).
- **Nature:** ivy in heavy masses on the walls under the open roof and in cascades from the ceiling's edge; a young
  birch through the stalls on the right (a white trunk with dark marks, weeping branches, its leaves above head
  height turning); ferns in the pit's corners, by the stage, in the floor's holes and the doorways; hart's-tongue in
  the brick's joints; patches of grass with wildflowers (white, pale yellow) and willowherb under the open sky; moss on
  the boards, the steps and the seats; leaf litter everywhere it can lie, a few leaves floating on the puddle.
- **The light:** the Moon, high in the west-south-west (`sky` `moon_bearing` 246, `moon_altitude` 45), comes through
  the open roof as a cold pool on the stalls: the left wall's ragged top throws its shadow across the pit, the
  trusses theirs across the right wall and the floor; a narrow shaft through the roof's hole makes a small pool on
  the pit's floor under the front roof. The run-time lightmapper threw no shadows (a box under a spot, tested under
  lavapipe), so the Moon's light is traced in code as the room is built: for each vertex of the baked meshes, the
  ray to the Moon against the walls' tops, the gables, the trusses' members, the front roof (only through its hole)
  and the slates; its light goes in the vertex colour's alpha and the house shader adds it (`vertex_light`, new,
  additive: 0 in every other room). The trusses' and the slates' shadows are soft bands, their penumbra widening
  with the distance (wider than the Moon's own), so they fall across the vertices smoothly, never in steps. The bake
  takes the Moon's light as an emitter, so it bounces softly into the shadow; the sky's light from the opening is a
  share beside it, on the rear wall as on the side walls. The unbaked parts (the leaves, the brass, the seats'
  instance colours) take the same light in their vertex colours. All of it is house light: the film takes it to the
  house lights' floor (`dimmed_level` 0.02 gives 0.0004, held at the shader's `house_floor`, 4 %). The film's light
  only tints the ruin (`spill` 0.35 on the tiers and the seats; the brick 0.06, the plaster 0.09, the timber 0.08,
  the cloth 0.12 of it: at twice these the test picture's warm and cool halves split the hall in two), and the
  projector's beam is a faint haze (`beam_haze` 0.12; at 0.25 it was a bright slab past the side seats). No live
  light, no bake light; the house lamps, step lights and signs dead; the booth's lit port and the crystals' glints are
  emission.
- **Systems:** `light` (a cold fill, `baked_fill` 0.3, `bake` on), `auditorium` (`shell` `kit`, 16 x 15.6 m,
  `ceiling_cover` 0.5, 3 rows of 21 plush seats behind the viewer's front row, `stage_depth` 1.5), `screen_frame`
  (no masking: the ruin draws its own; the projector's beam), `kit` (the four ruin pieces), `seats` (`broken`, `up`),
  `sky` (a September night at 52 degrees north, a Moon nearly full; clouds on `weather.wet`), `weather` (rain
  through the open roof and a leak over the pit, the puddle), `atmosphere` (a little haze in the beam; one low mist
  layer on `weather.wet`), `life` (`birds` on the trusses and the walls' tops, `fireflies`, `deer` from the rear
  door down the left aisle and out by the side door), `acoustics` `outdoors`, `sound_bed` (rain, rain on the boards,
  drips, wind, crickets, owl).
- **Setting:** Weather (`weather`: changing, rain, mist, clear) maps onto `weather.mode` (changing, heavy, light,
  clear); mist is a drizzle, and the mist rises with the wet.
- **Cues:** `birds_start` (a loud bang while playing: the birds scatter; chance 0.6, at most every 3 minutes),
  `deer_in_quiet` (6 s of a quiet scene: the deer comes; chance 0.5, at most every 15 minutes).
- **Comfort:** the creatures stay at the edges (the deer down the side aisle, never in the sight line; the birds
  high on the trusses); the chandelier, the birch and the meadow stand clear of every seat's sight line (tested);
  nothing in the ruin moves but the rain, the fireflies and the creatures; the Moon's pools never move.
- **The puddle:** the viewer sits in the front row so nothing hides the pit; the eye mirrored in the puddle's plane
  sees the picture's middle 3.6 m ahead, in the puddle (the test works it out).
- **Measured** (`tests/test_room_reclaimed.gd`, headless, 2026-11-08, after the second pass): 25 draws, 256 149
  triangles, no live light, 1 200 particles, 7.3 MB. Before the deep pass (`test_room_set5.gd`): 30 draws, 116 858
  triangles, 1 600 particles, 10.4 MB. By part: the leaves (ivy, the birch, ferns, the meadow, moss, litter) 92.9k
  triangles in 1 draw, the seats 54.1k (2 draws), the plaster 44.5k, the timber 17.4k, the brick 12.4k, the
  tipped-up seats 8.4k, the cloth 5.8k, the broken seats 5.2k, the crystal 4.2k, the stars 4.0k, the brass 3.9k, the
  sky 2.4k, the rest a few hundred. The bake: five static meshes, 0.86 M texels in their atlases, the largest 688 x
  584; the lightmap 1024 x 1024, two layers (12.6 MB); about 16 s under lavapipe (before the texels were coarsened,
  26 s).
- **Measured in the render** (`test_room_reclaimed.gd` with `RECL_BAKE`, at the headset's room light: the room's
  ambient before the film, times `dimmed_level` in it; luminance of the shown colours as `test_room_atmospheric_1928.gd`
  measures its houses): the walls beside the picture 0.047 before the film and 0.044 in it, the floor before the
  viewer 0.201 and 0.071 (the puddle's reflection of the picture most of it), the picture 0.57. Before the second
  pass: the walls 0.064 and 0.099 (the film lit them more than the Moon did), the floor 0.204 and 0.104.
- **The costs to watch on the Frame:** fill is small: everything opaque on the house shader but the rain, the
  fireflies, the beam's haze and one mist layer; the leaves are double-sided quads in one draw. Geometry is the most
  of any room so far (256k triangles, the leaves 94k of it). The bake's time on the headset is the thing to judge,
  then the frame time with the rain at full.
- **The render** (lavapipe, `test_room_reclaimed.gd` with `RECL_BAKE`): from the seat, left, right, up, back, a
  side seat and up behind, in the pre-show and with a film; close in the pre-show (`RECL_CLOSE`): the chandelier,
  the proscenium, the ceiling's edge, the birch, the curtain, the meadow, the shaft's pool, the roof's hole, the
  right wall and the left wall's plaster, the rear wall with the clock, the booth's ports.
- **Sound:** open air (`acoustics` `outdoors`); rain on the leaves round the viewer (`sound_bed` `rain_leaves`, four
  voices under the open roof) and on the boards behind (`rain_leaves` at `pitch` 0.7, `gain_db` -6), both with their
  `level` on `weather.rain`; drips into the puddle after it (`drips`, `level` on `weather.wet`); a soft wind high
  over the open roof (`wind`, two voices 8.5 m up, `gain_db` -6); crickets outside the side door by the stage when it
  is dry (`crickets`, `gain_db` -12, 10 dB lower in the film, `level` on `weather.rain` inverted); a tawny owl far off
  in the trees behind (`tawny_owl`, `every` 170, 32 m off, 14 dB lower in the film). The birds' calls are the birds'
  own (`life`). Measured (`test_room_set5.gd`, the slider's default, rain and wet at full): -49.8 dBFS RMS in
  the pre-show, -64.5 under a film at the reference level (before the pass -49.9 and -64.0).
- **To judge on the Frame:** the bake's time and the frame time (256k triangles; the rain at full); the Moon's level
  (`MOON_LIGHT` in `kit/reclaimed.gd`) and the film's 4 % of it (the house floor); whether the film's tint on the
  walls is enough to feel the picture in the room; whether the lightmapper on the headset does throw
  shadows (it should not matter: no light is baked, the Moon is emission); the crickets', the owl's and the wind's
  levels by ear.
