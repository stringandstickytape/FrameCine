# Streamline 1937

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

`app/environments/streamline_1937.env.json`. A 1937 streamline (moderne) picture house: horizontal speed and curves,
a ceiling of coves glowing in changing colours, a stepped proscenium round a rising sun, a gold festoon, and an
illuminated organ console that rises from the pit. Its tests: `tests/test_room_streamline_1937.gd` (the room's own)
and `tests/test_room_picture_houses.gd` (with the Shopfront and the Pink Palace). The quality pass (2026-11-08)
answered "continue working on the environments one-by-one like you did with the bathysphere, really improving their
quality, imagination, delight, detail, lighting and so on" (the user, 2026-11-08); everything but the hall's floor,
seats, doors and screen is new in it (`kit/streamline.gd`).

- **The ceiling** (`moderne_hall`): five bands across the hall, from 8.8 m over the proscenium down to 6.4 m at the
  back, each stepping 0.6 m over the next (steps at z -8.6, -4.2, 0.2 and 4.0). In each step's slot a lamp lies on
  the lower band's back and washes the higher band's plaster, so from the seats every band glows brightest by its
  slot and fades over a couple of metres towards the screen; a faint broad glow goes on further. Along both walls each
  band rounds down in a quarter round of 0.9 m into a ledge whose lamp washes the round (the coves along the walls).
  Over the proscenium a drop beam with a chrome edge hides a lamp that washes the proscenium's head. A gilt
  ventilator (twenty fins round a boss over a dark throat) in the middle of each of the first four bands.
- **The walls:** speed bands of cream faience, jade and cream between four chrome beads (4.1 to 4.85 m) run from
  over the organ grilles on the proscenium's face along both walls, round the rounded rear corners, along the rear
  wall and across a bowed circle front (a jade faience parapet with a chrome handrail and three downlights in its
  soffit over the rear walkway; the projection box's ports behind it). A walnut dado with a chrome bead and joints
  follows the rake; reeded pilasters (five reeds, a stepped faience capital, a chrome base) stand under the ceiling's
  steps; eight etched glass shell lights (a fan of frosted glass, eleven ribs, on a stepped chrome bracket) between
  them, each a stand-in lamp and a bake light that lays its pool on the wall. The aisles' carpet: rising suns in rows
  (`deco_carpet`, jade, gold and cream).
- **The proscenium** (`ziggurat`): three frames stepping out towards the seats (0.5, 0.8 and 1.1 m in front of the
  screen, each opening 0.4 m wider and higher than the last, shoulders rounded from 1.0 to 1.8 m), each lit by a lamp
  hidden behind the next one's edge, so every face glows at its outer edge and fades towards the picture; gilt
  reveals with a gilt bead on each edge. The outermost face reaches the walls and the ceiling. Over the opening a
  rising sun: a glowing half disc, two gilt half rings, thirteen gilt rays long and short, three chrome speed lines
  either side. Two organ grilles (a chamber lit from below seen through gilt bars, a sunburst in the round head, a
  stepped gilt surround, a dark jade plinth); over the left one a clock whose hands tell the real time (chevrons at
  the quarters, faint rays, a chrome bezel, gilt rays round it: `shaders/env_clock.gdshader`), over the right a
  roundel of glowing glass with three chrome speed lines through it. Nothing of it is in front of the picture.
- **The festoon** (`motion` `festoon`): gold velvet in six swags with folds (`pleats` 2.4), from 2.3 m over the
  screen's top to the stage (`festoon_top`, `festoon_size` [12.8, 8.05]); fully up its lowest swag is at 4.6 m, behind
  the first frame's head (4.45 m) and clear of the picture. Lit from the footlights below and two battens behind the
  head, in the coves' colour. It rises at the motion limits (0.5 m/s): about 15 s, so the first seconds of the film
  land on its rising hem, as they did.
- **The organ console** (kit `console`, `group` "Console"; `motion` `organ`): on a round lift platform (black lacquer,
  a chrome rim, a skirt that fills the well when it is up) an illuminated console: sixteen glass panels between gilt
  fins in the coves' colour, an ivory horseshoe of stop tabs in three tiers (white, red, amber, black), three manuals,
  a lit music desk under a chrome hood (accent group), a pedalboard of thirty-two pedals under a jade bench. It rests 1.3 m under the pit's floor and rises
  1.85 m (0.25 m/s): up, its top (1.22 m over the platform) stays under every seat's sight line to the picture. A
  chrome ring on the pit's floor marks the well.
- **The light:** baked, from the shell lights' pools (8 lamps), the circle's downlights (3 spots), the wall coves (10
  hidden lamps under the rounds, one a band a side, that lay the coves' glow down the upper walls) and the hall's
  house spots; the coves, the frames, the grilles' chambers, the sun and the console's
  glass are `PieceCove` (their light per vertex, live in colour: "The moderne hall's coves" in "The kit"). The fill
  is low (`fill_top` [0.62, 0.5, 0.4], `baked_fill` 0.2) and the spill too (0.35; the coves take 0.6 of it): a pale
  hall would otherwise glow in the picture's colours. No live light.
- **Setting:** Cove colours (`cove`: Changing, Gold, Rose, Jade, Blue; Changing by default). It moves only live
  parameters (the kits' `cove_colour` by `map`), so the room is not built again and the console stays where it is.
  With Changing the coves go gold, rose, jade, blue in turn (`cove_cycle`, every 20 s in the pre-show, paused, at the
  end and in the intermission; each change over 4 s). In the film the coves take the film's colour (`cove_film`,
  `cove_film_colour` on `film.colour`, strength 0.85) at half their level (`cove` on `playback.playing`), times the
  house lamps' 15 %: a glow.
- **Cues:** `prelude` (pre-show, end, intermission; Pre-show on): 3 s after the room opens the console rises over
  10 s, lit, and the organ plays (`pipes.play`, 80 s), then sinks. `ritual` (starting; Pre-show on): the lamps to half
  over 2 s, the organ's closing cadence (`pipes.flourish`), the festoon rises, the console sinks 3 s later, the lamps
  to 15 % over 5 s. `dim` (starting; Pre-show off): the lamps to 15 %, the console down. `lights_up` (pre-show, end):
  the lamps up over 4 s, the festoon down. At the end the console rises again and the organ plays the house out.
  `cove_cycle` and `cove_settles` as above.
- **Sound:** `acoustics` `cinema`; `music` (id `pipes`) `organ` with the `theatre` stop at the console (`at` [0, -1.5,
  -11.35], `reach` 12), `plays_in` the intermission and when the prelude plays it, `on` on the common Pre-show
  setting. No beds: the hall is quiet but for the organ.
- **Comfort:** the colours change over 4 s, the clock's hands as a clock's, the console and the festoon at the motion
  limits (the Motion setting snaps them); nothing crosses the sight line (the festoon is `in_front` until it rises).
  The chrome shows the picture at a third in the film, so it does not glint with every cut at the edge of vision.
- **Default seat:** the middle of row 0 (7 rows in front, 3 behind, 25 seats a row). The seats, the eye height and
  the screen are as before the pass; the stage's top is 0.5 m higher (-1.6 m), so the festoon meets it.
- **Measured** (`test_room_streamline_1937.gd`, headless, 2026-11-08): 27 draws, 201 342 triangles (177 100 of them
  the seats), no lights, no particles, 8.2 MB of textures; 275 seats. Before the pass: 27 draws, 182 676 triangles,
  no lights, no particles, 8.0 MB.
- **The costs to watch on the Frame** (not measured on the headset): the fill is one opaque layer everywhere (the
  coves are `PieceCove`, opaque, over the ceiling; the two fog layers of the old room are gone); the only transparent
  surface is the air's beam haze in the film. Every frame the kit sets the coves' colour and level (two uniforms), the
  clock's hands once a second and the footlights' stand-in lamps ten times a second; the reflections' level only as
  the lamps change. The bake: 6.1 s under lavapipe, a 1024 x 512 atlas (3.1 MB).
- **Sound measured:** in the pre-show -54.4 dBFS RMS (peak -38.7: the organ playing as the console rises), under a
  film at the reference level -68.4. Before the pass: silent in the pre-show, -57.3 as the console rose, -59.4 in the
  film, -68.5 under a film.
- **The render** (lavapipe, `test_room_streamline_1937.gd`; `STREAM_BAKE=1` bakes it first, `STREAM_ONLY` takes one
  phase): baked, from the seat in the film the walls 0.143, the proscenium 0.205, the picture 0.603 (the hall a
  quarter of the picture or less); in the pre-show, not baked (the stand-in lamps only), the walls 0.371 and the
  proscenium 0.485.
- **To judge on the Frame:** the frame time and the bake's time; the organ's level and its tremulant by ear, against
  the film's; whether the festoon's 15 s rise over the film's first seconds pleases or should start in the ritual's
  dark sooner; the film's brightness in the hall (the coves at half of 15 % in the film's colour); the eight stand-in
  lamps (the shell lights at the back have none, so their glass lights only in the bake).
