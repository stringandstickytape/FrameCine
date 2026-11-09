# Palace of Culture 1974

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

`app/environments/palace_of_culture_1974.env.json`. *A palace of culture, 1974: board-marked concrete, two great
mosaics that glitter in the screen's light, a field of glowing globes, and snow falling through the open roof.* The
deep pass (2026-11-08) answered "continue working on the environments one-by-one like you did with the bathysphere,
really improving their quality, imagination, delight, detail, lighting and so on. Better to do a smaller number of
incredible superb ones than a large number not so" (the user). Before it the room was the auditorium builder's
cinema in other materials: concrete panels, six flat terrazzo panels a side for the mosaic (no tesserae), ochre
drapes, stadium seats in red, the back three quarters of the roof open. The seats, the eye height and the screen
are where they were; the hall round them is the kit's `culture_hall` piece (`kit/palace_culture.gd`), its mosaics
`kit/mosaics.gd` on the house shader's `MOSAIC` form.

- **The mosaics (the soul):** one on each side wall, 14.4 m long and 7.2 m high (z -13.6 to 0.8, y 1 to 8.2), of
  our own design, no people and no emblem: 320 x 160 tesserae of 4.5 cm each, drawn tessera by tessera
  (`kit/mosaics.gd`) into one map (320 x 320, both murals, 400 KB) whose alpha says what each tessera is: stone, coloured
  glass or gold. The left wall is **the cosmos**: a night laid in rings round a gold sun (the andamento a mosaicist
  lays), its rays in gold and ochre, an atom's three orbits round a red nucleus, a rocket climbing on a trail of
  flame, a crescent moon cut out of the night, a ringed planet, a comet, gold and white stars. The right wall is
  **the earth**: dawn in bands of cream, peach, aqua and blue round a sun rising on the horizon, gulls gliding, a
  sheaf of wheat bound with twine, furrows converging to the horizon in ochre, olive, gold and brown. Along both
  feet a river of waves (scales of turquoise, cobalt and ultramarine with white rims); a black and gold border; a
  bronze frame. The shader (`MOSAIC`): courses with uneven joints and a stagger, each tessera its own shade, tilt
  and edge, dark grout that stays thin at a distance; gold and glass glint as the head moves (the lamp line's and
  the picture's light, gold tinted by its own colour, stone hardly), never a flicker of its own. The lamp line over
  the cornice washes down them (`mosaic_wash`, times the house lamps). In the film they take `film.colour` through
  the screen's spill, softly: `spill` 0.22 against the concrete's 0.45 (the mosaics must never be lit more than the
  picture).
- **The architecture:** board-marked concrete everywhere (`procedural.gd` `board_concrete`: ten boards a repeat, each
  its own tone and depth, butt joints, grain, the fins between boards, tie holes, blowholes) on `smooth_concrete`;
  a moulded cornice at 8.4 m over each mosaic with a lamp line in its underside; a coffered ceiling, 10 x 7 coffers
  on beams 0.7 m deep, each coffer's soffit lit by the globes under it (`PieceCove`: the light worked out per vertex,
  a pool round each globe falling off over half a metre, no light pass); a bold concrete proscenium round the
  screen's drapes: a broad face, two stepped reveals, vertical ribs every 0.42 m, a groove band and a
  bronze edge, the ochre valance inside it.
- **The globes:** a field of 60 opal globes (six rows of ten) on long rods from the coffers' crossings, hung lower in
  the middle (a bell) and never below 6.6 m, all at least 2 m above the picture's top. Each glows warm
  (`room_lamp.gdshader` `rim`: brighter where the view meets the glass square on, so they read round, not flat
  discs), in the `house` group: they dim with the house lamps for the film but never go quite out
  (`follows_house` 0.93).
- **The opening and the winter:** a roof light 4 m deep across the hall's width just behind the default row (z 1.2
  to 5.2), crossed by a grid of concrete beams; a frozen sky (`sky`: latitude 56, mid January, full night, grey
  clouds, a warm glow on their undersides from the hall); birches in hoar frost overhead (`vista` `frost` 1: fine
  white twigs, drooping strands; `room_glow`: the hall's warm light thrown up on the near trees, down with the
  lamps in the film); snow lying on every ledge and beam of the opening (unbaked, draped over the edges so it
  reads from below), snow falling under the opening only (1400 flakes).
- **The rear wall:** oak acoustic slats (7.5 cm pitch, each its own tone) to 5 m, on bronze rails; a concrete band
  with the booth's windows; over it the hall's clock (0.6 m, a bronze ring, `env_clock.gdshader` `style` 1: a dark
  dial, lit bars and minute dots, telling the real time); dark felt between.
- **The seats:** the seats system's new `civic` model, 377 of them (29 a row, 13 rows): woven red upholstery on a
  moulded oak shell, oak arms and standards. 338 triangles a seat against the stadium seat's 646.
- **The light:** warm in the pre-show (the globes, the lamp lines, the wash down the mosaics, the coffers' pools),
  cold from the opening (a pale blue spot from the sky for the bake), dim in the film. Baked: 8 lamps (stand-ins
  until the bake), 5 glows along the cornices, 11 hidden spots (six washing down the mosaics, the sky's spot, two
  footlights on the drapes, two uplights on the proscenium from the pit). The curtains of the pre-show are ochre,
  as the drapes (`room` `curtain_colour`).
- **Systems:** `light` (spill 0.45, `baked_fill` 0.15), `auditorium` (unchanged layout; `seat_model` `civic`,
  `side_walls` false: the kit draws the side and rear walls; `ceiling_cover` 0: the kit draws the ceiling; `house_spots`
  off), `kit` (`builder` the hall, pieces `culture_hall` and `globe_field`, `bake_lamps` 8, `mosaic` on
  `white_marble`), `screen_frame`, `showing`, `sky`, `vista`, `weather`, `acoustics`, three `sound_bed`s.
- **Setting:** Snow (no snow, light, heavy; light by default): `weather.mode` (clear, light, heavy), `sky.clouds`
  (0.2, 0.55, 0.85), `vista.snow` (0.8, 1, 1) and the wind's level (0.5, 0.8, 1), each by `map`.
- **Cues:** `ritual`: the bells, the lamps to half over 2 s, the curtains part over 5 s, then the lamps to 10 %, the
  steps to half and the trees' glow to 0.04 over 6 s. `dim` (the same without the ritual), `lights_up` (all back
  over 4 s). `night_train`: in the pre-show, when paused and at the end, every four minutes a one-in-two chance (at
  most once in eight minutes) of a train far off.
- **The snow and the picture:** the snow falls only under the opening, behind the default seat, so nothing falls
  between the viewer and the picture from there; from the back rows it falls round them.
- **The vista's ground:** the side groves' ground is at -3.1, under the pit's floor: at 0 the vista's snow (8 m
  out from the middle) showed over the side aisles as a pale slab (before the pass too).
- **Default seat:** the middle of row 0.
- **Comfort:** nothing moves but the snow, the clouds and the clock's hands; nothing between a seat and the picture (tested from
  every seat); the globes hang high and clear of the view.
- **Measured** (`tests/test_room_palace_of_culture_1974.gd`, headless, 2026-11-08): 29 draws, 178 958 triangles,
  no live light, 1400 particles, 14.6 MB. Before the pass: 23 draws, 256 688 triangles, 1400 particles, 12.4 MB. By
  part: the seats 127.4k triangles in 2 draws (243.5k before), the vista 14.1k (the frosted birches), the globes
  11.5k, the coves (coffers, cornices) 8.9k, the soft meshes (snow, rods) 5.3k, the stars 4.0k, the hall's static
  meshes 2.9k in 5 draws, the sky 2.4k, the floor 1.6k, the mosaics 4 triangles (all their detail is in the shader).
  The bake: the lightmap 1024 x 1024, one layer (6.3 MB), 11.4 to 11.8 s under lavapipe; 24 hidden lights for it.
  The textures made at load: the board-marked concrete's three maps (256) and the mosaics' map (320 x 320).
- **The costs to watch on the Frame:** fill is one opaque layer (the snow's flakes are the only blended part); the
  mosaic shader costs one more texture fetch and a few hashes a pixel over the house shader, on two walls that fill
  much of the view; the frosted birches add 14k triangles to the vista's one draw; the 60 globes 11.5k in one draw.
  The bake's time on the headset (24 lights) is the thing to judge.
- **The render** (lavapipe, `test_room_palace_of_culture_1974.gd` with `PALACE_BAKE`): from the seat, left, right,
  up, back, back and up, a side seat and its wall, in the pre-show and with a film; close: the left mosaic, the
  proscenium, the ceiling, the rear wall, the opening, the right mosaic, the roof from above, the side aisle.
- **Sound:** an echoing hall (`acoustics` `concrete_hall`: rt60 2.4, a 60 ms predelay); the house bells
  (`three_bells` by the stage, played by the ritual only); the wind over the opening (`wind` 10.5 m up, its level on
  the Snow setting, 12 dB down in the film); a train far off now and then (`train`, about 280 m away, by the cue only).
  Measured (the slider's default): -52.1 dBFS RMS in the pre-show (peak -38.1), -73.5 under a film at the reference
  level. Before the pass the bells' loudest second was -52.2 and nothing else sounded.
- **To judge on the Frame:** the frame time with the mosaics filling the view and the bake's time; whether the
  glint is subtle (gold should catch as the head moves, never sparkle); the mosaics' level in a bright film; the
  globes' level in the film; the ochre curtains of the pre-show; the wind's and the train's levels by ear;
  snowflakes near the eyes in the back rows.
