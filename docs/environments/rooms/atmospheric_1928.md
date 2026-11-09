# Atmospheric 1928

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

`app/environments/atmospheric_1928.env.json`. A picture palace built as a Mediterranean town square at dusk, as the
atmospheric theatres of the late 1920s were: the seats stand in a courtyard of plastered houses under an open sky,
and the screen is in a palace's gate. The quality pass (2026-11-08) answered "you may be able to do a large number of
superb ones, see how it goes, but aim for incredible quality plz!" (the user, 2026-11-08); the houses, the gate, the
trees, the windows, the Moon, the owl and the organ are new in it.

- **The houses** (`kit` `house`, `kit/courtyard.gd`): thirteen fronts, five along each side wall and three across
  the back, each its own wash (rose, ochre, cream, sage, terracotta; lime over plaster with a faint blotch), shutter
  colour, height (7 to 9.6 m to the eave) and depth (0.005 to 0.9 m out from the wall). Each stands on the stepped
  floor (its socle follows the aisle's rake) and rises in two or three storeys of windows to a tiled eave or a gable.
  Between them: long iron balconies with real depth on stone consoles (one with a striped rug over its rail),
  balconettes, a loggia, two belvedere towers, two pergola terraces, two Moorish oriels with their lattices lit, an
  arcade on the left wall and another across the back (the projection booth's ports over it, the projector's lens
  glowing), a front door, niches with an urn and a lion, a wall fountain behind the seats on the left (blue and white
  tiles, a lion's mask, a basin with moving water), geraniums on the sills, bougainvillea climbing to the balconies,
  iron grilles on the ground floors. The four exits are arched ways out in the houses at the corners.
- **The windows** (`PieceRoomWindows`, `shaders/env_courtyard_window.gdshader`): 54 lit rooms behind the glass,
  each one of six kinds (a curtain drawn left or right, both drawn with a lamp, a plant on the sill, inner shutters
  half closed with light through the slats, the organ's pipes), and 10 dark. They are lamps of the `house` group, so
  they dim with the house lamps, and with the film the courtyard goes to bed: `kit.night` to 0.7 puts each window out
  at its own moment, down to `ember` 0.2 (a lamp turned low), 37 of the 54 over 9 s. They bake as
  emitters: their glow lights their reveals, sills and shutters.
- **The palace gate** (`kit` `palace_gate`): two towers reach from the screen to the walls, each with a rusticated
  base, the organ's grille (a tall arch with a gilt lattice over the pipes' warm chamber, a gilt balconette), a lit
  window, a belfry with its bell and a pyramid roof with a gilt finial. Between them a great segmental arch over the
  picture with gilt mouldings, a keystone's cartouche under a shell, rosettes in the soffit, medallions in the
  spandrels, a frieze, and a balustrade with five urns against the sky. Velvet drapes tied back in the jambs with
  gilt cords and three swags with gilt fringe along the arch. Nothing of it is in front of the picture. Two stone
  lions lie on pedestals at the stage's corners (`kit` `pedestal`, `scale` 1.3).
- **Beyond the walls:** six cypresses, three palms and a stone pine (`kit` `cypress`, `palm`, `pine`) over the roofs.
  No `vista`: the trees are the kit's, drawn round the room's own corners.
- **The sky** (`sky`): latitude 37, mid July, 21:30, `dusk` 0.45 (a deep blue vault, the sunset's last glow low in
  the west-south-west), the real stars with a slow `twinkle` 0.35, the Milky Way at 0.5, no constellation lines, a
  crescent `moon` (bearing 218, 47 degrees up, phase 0.28, lit from the sunset's side), clouds lit warm from below by
  the town (`cloud_glow`), their own colour after `film.colour` (strength 0.4) and the ones towards the screen
  catching its light (`cloud_screen` 1.2).
- **The light** (`light`): a cool blue fill from above, a warm one from below (`fill_top` [0.13, 0.16, 0.27],
  `fill_bottom` [0.11, 0.08, 0.06]), `baked_fill` 0.6, `spill` 0.5 (the default is 3, on dark walls: these pale
  washes near the screen took too much of a bright scene). 15 lanterns on iron brackets (`PieceLamps`, the `house` group); with the
  organ chambers' glow that is 17 lamps, of which the first 16 (`bake_lamps` 16) are stand-in lamps and hidden bake
  lights, so each lays a warm pool on its wall. Four hidden floodlights at the stage's lip light the towers and the
  arch in the bake. The hall's own house spots are off (`house_spots` false: there is no ceiling), and so are its
  handrails (`handrails` false: they would run through the house fronts). No live light.
- **Settings:**

  | Setting | Choices | Default | What it moves |
  |---|---|---|---|
  | Clouds (`clouds`) | 0 to 100 % | 40 % | `sky.clouds` by `range` [0, 0.8] |
  | Organ before the film (`organ`) | on, off | on | the organ's `on`; the `prelude` and `postlude` cues' `requires` |

- **Cues:** `ritual` (starting, Pre-show on): the house lamps to half over 1.5 s, the curtains part over 4 s, the
  dusk deepens to 0.85 over 10 s, the courtyard goes to bed (`kit.night` 0.7 over 9 s), the clouds lose the town's
  glow (0.25 over 8 s), the Moon pales to 0.6 over 8 s; then the lamps to 12 % and the steps to half over 5 s.
  `dim` (Pre-show off): the same without the curtains, over 3 to 6 s. `lights_up` (pre-show, ended): all of it back,
  over 4 to 8 s. `prelude` (pre-show, ended; Organ on): 5 s after the room opens, the organ plays for 80 s.
  `postlude` (starting; Organ on): the organ plays its cadence and rests as the film starts.
- **Sound:** `acoustics` `cinema` (rt60 0.7); the wall fountain (`sound_bed` `fountain` at its basin, [-9.05, 2.4,
  4.3], `reach` 8, `gain_db` -4); crickets round the courtyard (`crickets`, three voices on a 9 m ring, `gain_db` -9,
  `film_db` -18); a scops owl in the stone pine over the right-hand roofs (`scops_owl`, a new synthesised call,
  [11.5, 11, -3], `every` 55 s with `jitter` 0.45, `gain_db` -3, `film_db` -40: it all but stops in the film); the
  theatre organ behind the left tower's grille (`music` `organ`, stop `theatre`, [-8.1, 1.2, -13.7], `gain_db` -7,
  major), heard only before the film and between films (`plays_in` intermission; the `prelude` cue plays it).
- **Comfort:** nothing moves fast or crosses the sight line. The windows go out each over a twentieth of `night`'s
  travel (0.45 s at the ritual's 9 s), slower than the photosensitivity ceiling's fade; the twinkle and the water are
  under 1 Hz at any point; the clouds drift at `wind` 0.2. The Motion setting scales the clouds and `kit.water_motion`
  (at 0 the fountain's water stands still).
- **Default seat:** the middle of row 0 (7 rows in front, 3 behind). The seats, the eye height and the screen are as
  before the pass.
- **Measured** (`test_room_atmospheric_1928.gd`, headless, 2026-11-08): 31 draws, 262 756 triangles, no live light,
  no particles, 11.0 MB. Before the pass: 26 draws, 199 724 triangles, 9.4 MB. By part: the seats 177 100 triangles
  (2 draws, the hall's, unchanged), the kit's unbaked parts 71 390 (7 draws: stone, gilt, iron, leaves, wood,
  cloth, velvet), its baked parts 5 426 (4: plaster, stone, roofs, joinery), the windows 329 (1), the lanterns' glass
  180 (1), the water 41 (1), the booth's ports (2), the Moon (1); the sky's dome and stars 6 390 (2). The triangles
  are 13k over the brief's ~250k; the seats are two thirds of them. By piece: the gate 10.4k, a house about 1.7k to
  7k (the fountain's is the most), a lion about 3k, the pine 3.4k, a palm 0.8k, a cypress 0.3k. The bake under
  lavapipe: about 13 s, one 1024² atlas, 6.3 MB.
- **The costs to watch on the Frame** (not measured on the headset): the draws (31, from 26) and the triangles (the
  seats' 177k as before); the bake's time on the Frame (13 s under lavapipe on the desktop). Fill: nothing large is
  transparent; the sky is the same dome and stars as before plus one small quad for the Moon; the windows' shader is
  a few dozen ALU on small faces.
- **Sound measured** (`test_room_atmospheric_1928.gd`, the slider's default): -59.0 dBFS RMS in the pre-show with
  the organ playing and the owl calling (peak -42.1), -75.3 under a film at the reference level. Before the pass:
  -64.5 in the pre-show, -79.8 under a film.
- **The render** (lavapipe, `test_room_atmospheric_1928.gd`; `ATMO_BAKE=1` bakes it first): from the seat, left,
  right, up, back, a side seat and its wall, in the pre-show and in the film; closer: the gate, the left houses, the
  Moon, the rear, the lions, the right houses, a lion, the fountain. From the seat, baked (mean luminance of the
  image, 0 to 1): in the pre-show the houses beside the screen 0.22 and the gate 0.24; in the film, under the test's
  bright picture (0.60), the houses 0.12 and the gate 0.14, of which 0.05 and 0.08 without the picture's spill.
- **To judge on the Frame:** the frame time with 31 draws and 263k triangles; the bake's time; the organ's, the
  owl's, the crickets' and the fountain's levels by ear; the Moon's brightness beside the film; whether the
  courtyard is dim enough in the film (the façades take the film's spill: `spill` 0.5 on washes about four times as
  pale as a dark-walled cinema's walls at 3, so about two thirds of its light).
