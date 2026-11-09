# Screening room 1962

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

`app/environments/screening_room_1962.env.json` (Cinemas). *A collector's private cinema in the hills, 1962: walnut
and brass, a slow fire on a floating hearth, the pool glowing outside the glass, the city's lights below, a painting
that rises off the screen.* The deep pass (2026-11-08) answered "continue working on the environments one-by-one like
you did with the bathysphere, really improving their quality, imagination, delight, detail, lighting and so on.
Better to do a smaller number of incredible superb ones than a large number not so" (the user). Before it the room
was the domestic builder's `walnut_1962` box: flat walnut walls, a plaster ceiling, a brick breast, a framed window
onto a vista's pool, six blocky club chairs.

- **The room** (`screening_room`, `kit/screening_1962.gd`; the domestic builder keeps the 6.4 x 8.2 x 2.7 m box, the
  seats' places, the painting and its slot, and gives its shell to the kit with `shell` `kit`): walnut panels about
  0.62 m wide standing 2 cm off the walls, 8 mm shadow gaps between them, floating over a dark gap at the floor and
  under one at the ceiling; every other panel the veneer's other cut (another part of the flitch, turned), each its own
  shade. The screen wall is walnut slats (4.2 cm, 7.2 cm apart) over black felt from corner to corner; the picture
  sits 6 cm back in a deep walnut frame with a brass bead round its opening. A coffered ceiling: walnut beams 13 cm
  deep on a 5 x 6 grid over narrow cedar boards (`wood_slats`), a flat soffit over the screen wall where the painting
  rises into its slot, brass downlights in eight coffers and two wall-washers in the soffit. The left wall is glass
  from the floor to the beam between slim bronze mullions, its own faint glass (`WindowGlass`, no bright rim, so the
  garden is not veiled), linen curtains in deep folds stacked at its ends (their troughs shaded in the vertex
  colours: the folds are finer than the lightmap). At the back: a flush walnut door with a long brass pull, and
  shelves from the door to the right wall, floor to ceiling, of books (each its own height, depth, colour and a title
  band) and stacks of film cans, a ceramic or two, cupboards under them; in their fascia the projection port, a
  bronze-framed opening onto the booth, its lens a warm glow (the booth group). Three brass sconces (open cylinders)
  throw their light up and down the walnut. A dark carpet, a burnt-orange wool rug with a cream border under the
  chairs.
- **The hearth** (`screening_hearth`): a brick chimney breast to the ceiling on the right wall; a floating slate
  hearth 3.1 m long running past it either side, logs stacked under its ends; the firebox low in the breast
  (firebrick, a grate, three charred logs with pale ends, a bed of embers, eleven slow tongues of flame licking up
  between them, their glow on the firebrick, the hearth and the floor; a steel lintel); fire tools on a brass stand.
  Over it a sunburst clock: a walnut disc, 24 brass rays long and short in turn, hour marks, brass hands that keep the
  real time (`ClockHour`, `ClockMinute`, set each second).
- **The furniture** (`screening_furniture`): a floating walnut credenza under the screen, four doors with brass pulls,
  film cans, a tall teal bottle, an orange vase and a walnut bowl on it, all under every seat's view of the picture; a
  brass bar cart by the right wall under a sconce (walnut trays with brass galleries, two wheels: two crystal
  decanters with whisky and brandy in them, tumblers, a soda siphon, an ice bucket, a bowl of lemons, bottles lying);
  a surfboard coffee table on splayed legs before the front row's right (a cigar box, a bowl, a book); a tripod lamp
  with a linen drum shade in the corner by the window; a sheepskin before the hearth.
- **The chairs:** the seats system's new `lounge` (a 1962 club chair in saddle leather: a low, deep body, rolled arms,
  piped loose cushions, a curved back, tapered splayed walnut legs), cognac brown leather on walnut.
- **The garden** (`screening_garden`, one unshaded mesh, `shaders/env_screening_outside.gdshader`): the eaves running
  on over the terrace (the beams pass through the glass), big concrete pavers, the pool right outside the glass (3.2
  x 6.2 m, 1.45 m out) glowing turquoise from two lamps in its far wall, a pale stone coping, agaves in concrete bowls,
  a low wall at the terrace's edge, five palms down the slope against the sky, and the city's lights far below in the
  valley to the horizon (a band 150 m out from 6 degrees under the horizon, its own picture: streets of lamps,
  sodium and white, denser and finer towards the horizon, a warm haze over them). Its light is worked out as it is
  built (the night's cool light, the room's warm light through the glass, the pool's glow by distance). The pool's
  light ripples (a web drifting slowly, `water_motion` 0.6: the Motion setting slows it) on the coping, the eaves'
  underside and, faintly, the ceiling inside by the glass. The sky (`sky`): a clear August night at latitude 34, a
  waxing gibbous Moon low in the east-south-east (11 degrees up), seen through the window; `vista`: the hills.
- **The beam** (`screen_frame`, `beam_style` `volume`, `beam_strength` 0.001, from the port's lens [0, 2.25, 2.98]):
  a cone of the picture's light from the port over the seats, seen looking up or back; from the seat it does not
  show over the picture.
- **Light:** in the bake only, none live: the downlights' pools (eight spots, two of them washing the shelves), the
  wall-washers down the slats either side of the frame, the sconces' scallops up and down (six spots), the tripod
  lamp, the fire (two omnis), the pool's cool light up through the glass onto the ceiling and the window's reveal, a
  faint cold light from the night; eight stand-in lamps for the chairs and the soft parts (the fire, the sconces, the
  lamp, over each row, by the shelves). `light`: `spill` 0.2, a low warm fill (0.16, 0.13, 0.1; `baked_fill` 0.5).
  The lamps' glow is the house group's, the fire and the city's the accent's and the kit's.
- **The ritual** (cues on `room.painting_open`, `light.house_lamps`, `light.accent`, `kit.glow`): in the pre-show and
  after the end the lamps come up over 4 s, the fire and the pool up over 6 s (`fire_up`) and the painting comes down
  over 6 s (`painting_down`, with the Pre-show on). As the film starts from its start (`ritual`), the house bells, the
  lamps to half over 1.5 s, the painting rises over 7 s (1.84 m, at most about 0.4 m/s, under the motion limit), the
  lamps go down to the setting over 4 s; with the film (`embers`) the fire settles to an ember glow (accent 0.25 over
  8 s) and the pool's lamps to 12 % (over 10 s): "the pool still faintly there". A film resumed later
  (`painting_away`) takes the painting up over 4 s whatever the Pre-show. With the Pre-show off the painting stays up
  and `dim` takes the lamps down over 3 s.
- **Settings:** `house_level`, "Wall lamps in the film" (0..1, 15 %).
- **Default seat:** the middle of the front row (the origin), 5.1 m from a 2.6 m picture (unchanged).
- **Sound:** `acoustics` `small_room` (rt60 0.45); `sound_bed` `fire` at the hearth ([2.98, 0.62, -1.9], `reach`
  2.5); `pump` (`hum`: the pool's filter pump beyond the glass, [-4.9, 0, -3], `reach` 3); `crickets` in the garden
  ([-9, 0.3, -4], `reach` 7, `gain_db` -4); `owl` (`scops_owl` every 280 s, far down the slope); `bells`
  (`three_bells`, `film_db` -4), first in the ritual. Measured (`test_room_screening_room_1962.gd`, the slider's
  default, dBFS RMS): -58.9 in the pre-show, -53.9 as the film starts (the bells), -65.9 in the film, -73.8 under a
  film at the reference level.
- **Comfort:** the fire wavers under 3 Hz and only a little (`flicker` 0.5, 12 % at most); the flames lick at a walking
  pace; the ripples change about once in four seconds at the Motion setting's pace; the painting rises under the
  motion limit; nothing stands between a seat and the picture (the sight line from every seat is tested); the
  painting is in front of the picture on purpose (`env_in_front`) only while it is down.
- **Measured** (`tests/test_room_screening_room_1962.gd`, headless, 2026-11-08): 28 draws (29 with the beam, which is
  built with the app's screen), 33 632 triangles, no live light, no particles, 14.5 MB. Before the pass: 18 draws,
  9 600 triangles, 10.4 MB. By part: the six chairs 4.4k triangles (2 draws), the baked room 11.0k (9 draws: two cuts
  of walnut, the felt and the books' cloth, the cedar, the brick, the slate, the carpet and rug, the tins, the bronze),
  the soft parts 5.9k (3: the brass, the ceramics and spirits, the sheepskin), the garden 5.1k (1), the stars 2.6k, the
  sky dome 2.4k, the glows 0.9k (1), the vista 0.7k, the lamps' glow 0.3k (2), the glass 0.3k (2), the clock's hands
  (2), the painting and its slot (2). The bake: one static mesh atlas, 1024 x 1024 (6.3 MB), 4.7 s under lavapipe; 17
  spots and 3 omnis, all hidden. From the seat under the test's picture (lavapipe, baked): the walls 0.14 in the
  pre-show and 0.13 in the film (the picture 0.41).
- **The costs to watch on the Frame:** fill. The glass is one faint layer over the window (a fifth of the view
  looking left); the glows are one added mesh (the flames, small; the ripples on the ceiling by the window, about a
  square metre and a half seen at a slant; the city's band, far and thin); the beam's volume covers the picture's
  area from the seat (it adds nothing there but its cost). The garden is unshaded and opaque (a few multiplies, two
  texture reads near the pool). If the frame time is short: the beam first (`beam` false), then the ceiling's ripples.
- **The render** (lavapipe, `test_room_screening_room_1962.gd` with `SR62_BAKE`, `SR62_RENDER_ONLY`, `SR62_ONLY`):
  from the seat, left, right, up, back, a side seat, the back row towards the window; close: the hearth, the bar cart,
  the pool, the shelves, the credenza, the valley, the port, the ceiling by the window; in the pre-show and in the
  film.
- **To judge on the Frame:** the frame time (the glass, the beam, the glows); the pool's brightness in the film (12 %)
  and whether its ripples on the ceiling read as light or as a stain; the beam's strength looking back; the chairs'
  brightness (lit live by the stand-in lamps, not the lightmap); the fire's level in the film; the crickets', the
  pump's and the owl's levels by ear.
