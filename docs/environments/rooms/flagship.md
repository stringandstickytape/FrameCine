# Flagship

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

`app/environments/flagship.env.json`. *A big modern cinema: a steep rake, folded acoustic walls washed in amber,
recliners, a starlit ceiling of baffles and a huge curved screen in velvet.* The user's reference room for watching:
the "serious" room. The deep pass (2026-11-08) answered "continue working on the environments one-by-one like you did
with the bathysphere, really improving their quality, imagination, delight, detail, lighting and so on. Better to do
a smaller number of incredible superb ones than a large number not so" (the user). Before it the room was the
auditorium builder's hall in black: black felt walls that vanished, a black foam ceiling with a few white cans, red
stadium seats, the screen in a black void. Its brief: the finest modern hall in a capital city, understated luxury,
delight from restraint and craft. The seats, the eye height, the rake, the screen (its size, curve and place) and the
room's dark quiet are where they were; the hall round them is the kit's `flagship_hall` and `flagship_rows`
(`kit/flagship.gd`), the seats the seats system's new `recliner`.

- **The walls:** folded acoustic panels in charcoal felt, a sawtooth in plan (1.24 m bays: a broad face turned to the
  seats, a short return turned to the screen, the ridge 22 cm out), a champagne-bronze fin on every ridge from the slot
  to the cove ledge, over a walnut dado that follows the rake 1.05 m over the steps' noses. Between dado and panels a
  warm light slot runs the length of each wall, stepping over the front exits' signs; its light on the folds is worked
  out per vertex (brightest low and in the folds by the wall, thinner at the ridges, half on the returns, dark by the
  top), shown by the house shader's `vertex_light` in the kit's `cove_colour` at the house lamps' level. So the walls
  read as folds of light and shadow in the pre-show and vanish in the film, where only the returns catch the
  picture's light behind the viewer. A brushed-steel handrail on brackets runs up each stepped aisle with a warm line
  under it on the steps.
- **The ceiling:** 34 long felt baffles, 0.55 m deep, run from the proscenium to the rear ledge (the eye follows them
  to the screen), a 1.1 m band clear along each wall. Over the walls a cove ledge (a fascia and soffit 0.4 m out)
  hides a cool line washing the ceiling's edges and the wall above it (per vertex, the `plaster` material's cool
  `vertex_light`); a little of that light is on the baffles so they read as fins. Between them, 1100 pinholes of
  starlight (`Starlight`: a soft point each, 1.8 to 3.5 cm, never smaller: under two pixels in the headset a point
  would crawl as the head moves; mostly cool white, one in seven warm; static, never twinkling).
- **The screen:** the picture's curve carried into the room: black velvet masking (0.65 m round the picture, on the
  picture's own arc 8 cm behind it, `Flagship.arc()`: the document's curve over the seat's distance, as
  `curved_screen.gd` makes it), a slim frame round it (7 cm, standing 12 cm out, dark bronze: a bright one read as a
  television's bezel round the film), and beyond the frame to the walls and the ceiling a proscenium of bold walnut
  slats (28 cm pitch: thin ones close together shimmered in a moire from the seats) on dark walnut, washed from the
  stage's lip up the wings and from a line hidden in the frame's head. The stage's front is a perforated grille (the
  speakers behind the screen) over a dark toe, the builder's blue apron line above it. The stage is 2.2 m deep now
  (was 1.4): the curved picture's edges come 0.8 m forward, and the stage's front must stay in front of them.
- **The rows:** the `recliner` (428 triangles: a deep cushion on a closed base, a back reclined 15 degrees in two pads,
  a shell to the floor in darker oxblood leather; the headrest 0.22 m behind the seated eyes; the back row clears
  the rear wall). Its arms are the room's (`flagship_rows`): 364 fixed leather armrests between the seats and at the
  rows' ends, each with a brushed-steel cupholder ring (dark inside) at its front and, behind it, the number of the
  seat on its right engraved on a steel plate (`SeatNumbers`: 1 to 25 from the left, in a 5 x 7 face of our own on
  the house shader, lit as the room is), so the viewer's own seat folds away and both its arms stay. Row letters A
  (the front) to N glow on the end arms towards the aisles (`RowLetters`, the steps' group: at a whisper in the film).
  Brushed-steel nosings on every aisle step over the builder's blue lines. At the front row a frameless glass
  balustrade (`Balustrade`, nearly clear) with a steel shoe and cap rail and a warm line under the cap.
- **Other fittings:** eight surround speakers on the side walls and two on the rear wall (cabinets with perforated
  fronts, tipped down to the seats, on brackets); the rear wall in walnut slats on felt with a walnut band round the
  projection port and the booth's windows (the port glowing faintly), the rear exits clear; the doors in walnut and
  brushed steel.
- **The light:** the pre-show is warm low and cool high: amber up the folds and the proscenium's wings, the warm lines
  of the slots, the rails and the balustrade, the blue step lines, the cool coves along the ceiling, the stars. In the
  film everything of the house goes out with the house lamps (the wash's `vertex_light`, the lines, the stars by
  default) but the steps and the row letters at a whisper (35 %) and the exit signs; the picture's light reaches the
  seats and walls through the spill (`light` `spill` 2, the walnut 0.5, the grilles 0.4, the frame 0.5, the ceiling 0.3,
  the masking 0.2). The fill is low and neutral (the wash, not the fill, shows the walls). No projector's beam: the
  clean air of a modern hall (it also drew a large blended pyramid over the seats, moving with every cut). Baked: 8
  warm lamps by the walls (stand-ins until the bake: they light the seats too), 13 glows (the slots' light every 5.5 m
  along each wall, the coves' cool light), 2 spots up the proscenium's wings from the stage's lip, and the builder's
  step and exit lights.
- **Systems:** `light` (a low neutral fill, `baked_fill` 0.12, spill 2); `auditorium` (unchanged layout: 26 x 27 m;
  7 rows in front and 6 behind, 1.25 m deep and 0.55 m higher each: a 24 degree rake; rows curving round a point 30 m
  ahead; 25 seats a row, 0.62 m apart; `seat_model` `recliner`; `side_walls` false, `ceiling_cover` 0, `proscenium`
  none, `handrails` false, `house_spots` false: the kit draws them; the stage 2.2 m deep; `step_colour` blue); `kit`
  (id `fittings`: `flagship_hall`, `flagship_rows`, `bake_lamps` 8, `cove_colour` amber); `screen_frame` (masking, no
  beam); `showing`; `acoustics`.
- **Screen:** 20 x 8.4 m, its middle at the seated eyes' height, 18.2 m from the default seat (0.9 of its width),
  `curve` 0.3: as before.
- **Setting:** Starlight ceiling (off, before the film, always; "before the film" by default): the kit's `starlight`
  and `starlight_film` by `map` (0/0, 1/0, 1/0.18): always keeps 18 % of the stars in the film. The stars ease to their
  level over about a second.
- **Cues:** `ritual`: the lamps to 40 % over 2 s, the curtains part over 6 s, then the lamps out and the steps to
  35 % over 5 s (the wash, the lines and the stars go with the lamps). `dim` and `lights_up` as above.
- **Seat choice:** the default seat is the middle (row 0, with 7 rows in front and 6 behind). The front-middle
  and the back are the other good seats; the viewer picks them by pointing.
- **The curve (since 2026-11-07):** `env_room.gd get_home_curve()` gives the document's `screen.curve`, and the
  screen starts with it until the viewer sets a curve of their own (`curved_screen.gd`; flattening it keeps 0, so the
  room stays flat). A setting still cannot choose the default seat: the room starts at its origin seat.
- **Comfort:** nothing moves; nothing between a seat and the picture (tested from every seat, and no vertex of the
  hall in front of the picture's arc); the stars never change faster than an ease of a second.
- **Measured** (`tests/test_room_flagship.gd`, headless, 2026-11-08): 28 draws, 220 134 triangles, no live light, no
  particles, 11.5 MB. Before the pass: 17 draws, 228 806 triangles, 6.0 MB. By part: the recliners 149.8k triangles in
  2 draws (the stadium seats were 226.1k), the soft meshes 57.3k in 3 draws (the 364 arms with their rings 48k, the
  walnut slats 9k), the hall's baked meshes 5.4k in 8 draws, the stars 4.4k, the floor 1.7k, the seat numbers 0.7k. The
  bake: the lightmap 1024 x 1024, one layer (6.3 MB), 13.8 s under lavapipe (12 s before the pass, 512 x 512 in 5
  layers); 23 hidden lights of the kit's and 10 of the builder's. The textures: the new library maps (oxblood leather,
  walnut, brass, perforated metal, brushed steel) and the glyph atlas (384 x 150).
- **The costs to watch on the Frame:** fill is one opaque layer but for the stars (tiny), the balustrade's glass (a
  thin strip) and the picture; no beam now (it was a large additive pyramid). The arms (48k triangles) are the price of
  armrests that stay when the viewer's seat folds away. The bake's time with 33 lights.
- **The render** (lavapipe, `test_room_flagship.gd` with `FLAGSHIP_BAKE`; the picture curved as the app curves it):
  from the seat, left, right, up, back, back and up, down the rows, a side seat and its wall, the front row, in the
  pre-show and with a film; close: the proscenium's left, the stage, the ceiling, the rear wall, the side wall, the
  aisle, the armrest, a row's end.
- **Sound:** no beds: a modern hall is quiet but for the film. Its acoustics are drier than the `cinema` preset (rt60
  0.5, damping 0.8, wet 0.12: black felt and foam), for any room sound to come; the film keeps its own mix. Measured
  silent (-120 dBFS) in the pre-show and the film.
- **To judge on the Frame:** the frame time (the arms' triangles, the bake's 33 lights); the wash's level up the folds
  and the wings (amber, not orange: it should feel warm and calm, never bright); whether the stars read as pinholes
  (not sparkle) and their level; the slats of the proscenium from the seats (no shimmer); the seat numbers' size by the
  hand; the row letters' level in the film; the spill on the walls in a bright film.
