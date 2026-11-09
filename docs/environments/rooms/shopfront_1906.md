# Shopfront 1906

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

`app/environments/shopfront_1906.env.json`. *A shopfront picture house, 1906: a draper's shop made a cinema, pressed
tin in relief over a varnished dado, gas lamps, a player piano by a gilt-framed sheet, the wet street outside the
window.* The deep pass (2026-11-08) answered "continue working on the environments one-by-one like you did with the
bathysphere, really improving their quality, imagination, delight, detail, lighting and so on. Better to do a smaller
number of incredible superb ones than a large number not so" (the user). Before it the room was the `shopfront`
builder's plain hall: flat tin, a cove, a framed sheet, four lamps a side, a tin booth from the kit, the street a glow
in the window, and no piano drawn though one played. The seats, the eye height and the screen are where they were;
the hall round them is the builder's new `edwardian` style (`kit/shopfront_edwardian.gd`, its pictures
`kit/shopfront_pictures.gd`). Its tests: `tests/test_room_shopfront_1906.gd` and `tests/test_room_picture_houses.gd`.

- **The shop:** the ceiling in pressed tin plates (0.61 m: a beaded border, a ribbed medallion, a rosette of twelve
  petals, fans in the corners), a border and a rib round the field, two ceiling roses over the pendants; the walls
  above the dado in a smaller tin lattice (small diamonds with quatrefoils and beads, 0.305 m), all in relief (the
  maps' normals, drawn in code) and in an aged cream; a cornice of mouldings with a bead-and-reel band, mitred at the
  corners; a dark varnished matchboard dado with its rail and skirting; a worn plank floor (paler down the aisles and
  before the stage, darker by the walls). Soot above each lamp and yellowing high up, in the vertex colours.
- **The screen end:** the sheet's linen margin in a gilt ogee frame with bosses at the corners, a pelmet board over
  it (THE NONPAREIL in gilt between fleurons on deep red, ANIMATED PICTURES at its ends), crimson drapes gathered back
  each side, a low stage with a painted front and a velvet skirt with a gilt fringe. The lecturer's lectern on the
  stage's right: a turned column, a sloping desk with papers, a pointer leaning on it, a brass reading lamp with a
  green shade (its glow in the house group: down with the gas).
- **The player piano:** a walnut upright against the left wall by the stage, clear of the front row: its case and
  cheeks, a lid, the spool box with brass spools and the tracker bar, the roll's paper scrolling between them while it
  plays (3.5 cm a second, our own perforations), 65 keys in one MultiMesh that go down (3 degrees) with the music
  system's notes (`music.held_notes()`), brass pedals, two candles in brass sconces (their flames flickering slowly,
  in the bake as two warm lights), three roll boxes on the top.
- **The front:** the plate-glass window to the street with its mullions and transom, ANIMATED PICTURES / CONTINUOUS
  PERFORMANCE in gilt letters on the glass (read backwards from inside, as painted for the street), green curtains at
  its sides; the door with its bell on a spring and a green portiere. Over the door the projection booth on a timber
  platform: a riveted sheet-iron box with the lens port and two peepholes glowing, shutters over them in their guides,
  a vent, a ladder up, a red fire bucket on the post. Under the platform a hat shelf with a bowler, brass coat hooks,
  an overcoat and a furled umbrella. On the walls: invented bills (THE MAGIC KETTLE, A RIDE ON THE EXPRESS, VOYAGE TO
  THE ARCTIC, THE RUNAWAY PERAMBULATOR, THE HAUNTED INN, the house's programme), a hand-lettered price board, a
  LADIES ARE KINDLY REQUESTED TO REMOVE THEIR HATS board and a drop-dial clock whose hands keep the viewer's own time.
  All lettering in Fira Sans Condensed (the app's own font), drawn into one atlas in code.
- **The street:** through the window a wet road of setts and flags, our own gas lamp on its post outside with its
  lantern lit, and across the road a brick terrace: a lit confectioner's window full of jars (J. HARGREAVE,
  CONFECTIONER: invented), shuttered shops, a lit upper window, their lamp on its bracket; the lamps' glows and
  streaks on the wet stones. Now and then before the film (the `cart` cue) a horse and covered cart passes left to
  right as the room sees it, a dark shape against the lit shop, its two lamps gliding by with their streak on the
  road, the horse walking (legs swinging at a walk, wheels turning), with the hooves' sound going the same way.
- **The light:** the gas: six brass brackets with swan necks and opal tulip globes, two double pendants from the roses;
  slow flicker (`flicker` 0.6, the room's Flickering lights setting holds them). Before the film the room is warm and
  low; the street is cool through the glass. In the film the gas is turned down to 12 % and its globes go a deeper
  orange (`glow_colour` and `glow_mix` by the cues), still glowing as gas does; the street dims (`street_glow` 0.2);
  the picture lights the room through the spill (`light` `spill` 0.6: the linen 1, the paint 0.5, the gilt 0.6, the
  wood 0.25, the tin 0.16 and its ceiling 0.12: the film is the star). Baked (13 hidden lights): the six brackets and
  the two pendants, the candles, the reading lamp, the booth's port, the street lamp through the window (cool).
- **Systems:** `light` (a warm low fill, `baked_fill` 0.1); `shopfront` (id `hall`, `style` `edwardian`: the same
  5.6 m hall 4.2 m high, 5 rows in front of the viewer's and 3 behind, the tin aged cream, the trim walnut);
  `seats` (folding chairs in the builder's slots); `screen_frame` (no masking; the beam's `lens` in the booth's port,
  [-1.95, 3.27, 4.8]); `atmosphere` (`beam_haze` 0.4, `beam_dust` 0.7). The kit's booth is gone: the hall draws its
  own.
- **Sound:** `acoustics` `shopfront` (pressed tin, rt60 0.9); `sound_bed` `projector` inside the booth (`at`
  [-1.95, 3.2, 5.3], `reach` 5); `sound_bed` `gas` (`gas_hiss`, everywhere); `sound_bed` `hooves` (a horse and cart on
  setts, `at` [14.2, 0.5, 12.1] `to` [-13, 0.5, 12.1], `reach` 9, played by the `cart` cue); `music` `piano` at the
  drawn piano (`at` [-2.45, 1, -5.48], `reach` 7): it starts its piece in `starting` and plays on through the film,
  `drive` on `film.transient` (an agitato after a jump), `on` on the setting.
- **Setting:** `piano` (Player piano, on): `piano.on`; off, the keys and the roll rest.
- **Cues:** `ritual` (starting, Pre-show on): the gas to 55 % over 2 s, then to 12 % over 5 s with the globes' glow
  to a deeper orange and the street's glow down. `dim` (Pre-show off): the same over 3 s. `cart` (every 45 s in the
  pre-show, paused or ended; a chance of a half, at most once in 80 s): `hall.cart` (16 s) and `hooves.play`.
  `lights_up` (pre-show, end): the gas up over 4 s, the glow's colour, the street's glow back.
- **Comfort:** nothing in front of the picture (tested: no vertex of the hall between the sheet and the front row
  inside the picture's rectangle); the piano and the lectern beside the stage; the cart only outside the glass behind
  the seats, slow (its legs under 1.5 rad/s), never in the film; the gas's flicker slow and small; the clock's hands
  move once a second.
- **Measured** (`tests/test_room_shopfront_1906.gd`, headless, 2026-11-08): 32 draws, 28 961 triangles, no live
  light, no particles, 21.9 MB. Before the pass: 17 draws, 10 168 triangles, 8.4 MB. By part: the chairs 9.3k
  triangles in 2 draws, the shell (floor, tin, dado, cornice, ceiling) 7.4k in 6, the joinery (stage, frame, drapes,
  piano, booth, lectern, coat) 5.4k in 4, the fittings (brass, gilt and the small painted things) 4.3k in 3, the
  globes 1.3k in 2, the keys 0.8k, the cart 0.2k in 2 (made again each frame while it passes), and 12 small draws
  (the candles' wax and flames, the bills, the street, its lamp's post and the lanterns, the clock's hands, the booth's ports, the glass,
  the lettering, the reading lamp, the roll). The bake: 512 x 512, two layers, about 3.5 s under lavapipe, 13 hidden
  lights. The textures: the tin's maps (the ceiling's plate, the walls' lattice, the beads, the matchboard, the
  riveted iron; albedo and normal), the bills' atlas (1024 x 1024), the street (1024 x 1024), the window's lettering
  (1024 x 256), the roll; all drawn in code at the build (about 1.4 s on a desktop, the bills' text 0.7 s of it).
  Sound at the slider's default (dBFS RMS): -53.2 in the pre-show, -54.7 as the film starts, -56.5 in the film, -63.5
  under a film at the reference level.
- **The costs to watch on the Frame:** fill is one opaque layer but for the window's glass (one large quad, nearly
  clear), the lettering (alpha scissor), the beam and its haze, the candle flames and the cart's lamps (small). The
  draws are 32 (the budget's 40); the textures' memory (21.9 MB) and the time to draw them at the build.
- **The render** (lavapipe, `test_room_shopfront_1906.gd` with `SHOPFRONT_BAKE=1`; a film of typical brightness, warm
  left, cool right): from the seat, left, right, up, back, back and up, a side seat, the front row, in the pre-show
  and in the film; close: the piano, the keys, the stage, the ceiling, a wall, the window (and the cart passing), the
  booth, the lectern, a lamp, the door.
- **To judge on the Frame:** the frame time (32 draws, the tin's normal maps over the whole room); the gas's level in
  the pre-show and in the film (a glow, not a light); the street's brightness through the window, and whether the
  cart's pass reads (and is not a distraction: it never comes in the film); the hooves' level and travel by ear, the
  piano's level at its new place by the screen; the bills' and the clock's legibility from the seats and close; the
  tin's relief (no shimmer at a distance); the keys moving with the notes.
