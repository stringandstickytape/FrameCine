# Pink Palace

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

`app/environments/pink_palace.env.json`. *A dream palace in sugared almond colours: the hall is the inside of a great
scallop shell.* The deep pass (2026-11-08) answered "continue working on the environments one-by-one like you did with
the bathysphere, really improving their quality, imagination, delight, detail, lighting and so on. Better to do a
smaller number of incredible superb ones than a large number not so" (the user). Before it the room was plain
dusty-pink walls with flat pink and blue `curves` bands on them and across a flat ceiling, a moulded balcony front,
the pre-show's two flat curtain panels, and the whole house's lamps breathing every 10 s. Everything but the hall's
floor, seats, balcony tiers, stage, doors and screen is new (`kit/pink_palace.gd`). Its tests:
`tests/test_room_pink_palace.gd` (the room's own) and `tests/test_room_picture_houses.gd` (with the Shopfront and the
Streamline).

- **The vault** (`pink_hall`): the hall's cross-section a flat crown at 10 m, 9.2 m wide, falling in quarter ellipses
  to the walls at 6.7 m. Over it forty ribs fan out from the dome's rim to the cornices, the proscenium's last ring and
  the rear wall, deepening outward to 0.34 m and easing out at the edges so the vault meets the walls in a clean line:
  pink on every crest, powder blue in every trough, a thin gilt line along each crest (the sunburst's rays). Hidden
  lamps lie on both cornices behind a lip; their light rakes up the vault, so each crest's flank towards the wall
  glows and each trough holds a soft coloured shadow, bright by the cornice and fading towards the crown; a little of
  the chandelier's light round the dome. `PieceCove`: the light per vertex, its colour live.
- **The walls:** a dado of rose marble with a moulded cap and a gilt bead, following the rake; five fluted pilasters a
  side (cream, five flutes, a gilt shell for a capital), a pink glass shell sconce on four of them (bake lights: their
  pools on the pilasters and the walls); between them three tall round-headed mirrors a side (their heads level at
  5.15 m, their feet following the rake: 6.5 m tall by the stage, 3.6 m at the back), old glass that reflects softly
  (the reflecting shader at 0.3 roughness: the dark stalls below the eye's level, the rose hall above, faintly the
  picture in the film), bevelled edges that catch the light, gilt glazing bars, a cream architrave, a gilt shell over
  each head. Over the front exits a cream arch with a gilt shell hood. Under the cornice a frieze of breaking waves
  running towards the screen, white on powder blue in relief (2.5 cm), between gilt beads, from the proscenium to the
  balcony's line; over it a moulded cornice with a ledge and lip the length of the hall. Over the balcony on the rear
  wall a great shell, powder blue with gilt ribs, lit from a lamp behind the back row.
- **The proscenium** (`pink_proscenium`): the shell's growth rings round the picture: five rings 0.4 m apart stepping
  towards the seats, each opening a superellipse round the picture's middle (6.95 m half wide and 5.3 m high at the
  first, 0.6 and 0.88 m more a ring), their inner edges scalloped, their faces fluted with 21 ribs that run on from
  ring to ring, blue and pink in turn; each lit by a lamp hidden behind the next ring's edge (bright there, fading
  towards its own opening, the crests catching it), gilt reveals and a gilt bead round each edge. The fifth reaches
  the walls and the vault; a blue and gilt shell crests it. Thirteen gilt shell footlights stand on the stage's lip,
  each with its glow. Nothing of it is in front of the picture.
- **The festoon** (`motion` `festoon`): pink velvet in seven swags with a gold bullion fringe (`festoon_fringe` 0.16 m),
  from 6.6 m (2.2 m over the screen's top, behind the second ring's head) to the stage (`festoon_size` [13.8, 8.7]),
  0.1 m in front of the screen inside the first ring. Fully up, its lowest swag and fringe hang at 4.56 m, over the
  picture's top, inside the first ring's arch. Lit from below by the footlights (four stand-in lamps in the troughs'
  colour). It rises at the motion limits (0.5 m/s): about 17 s.
- **The balcony** (`pink_balcony`): its front buttoned pink velvet (`tufted`, 0.34 m diamonds) from below the slab's
  edge (4.0 m) to 5.28 m, rolled over the builder's parapet (lowered to 0.8 m: `balcony_parapet`), every point under
  the front row's sight line to the picture's foot; gilt beads along its top and foot; seven pink glass fans on it.
  Under it a rose soffit with ten round downlights and their pools on the rear walkway in the bake (three spots).
- **The dome** (`pink_dome`, its own kit `sunburst`, so its light has its own colour and level): an oval 8.6 x 6.6 m
  in the vault's crown over the stalls (centre 3 m in front of the viewer), a gilt lip round the opening hiding the
  lamps on the ledge behind it, a rose drum, the dome rising to 11.05 m, pale blue at its foot deepening to the apex;
  32 gilt rays, long and short, round a gilt rosette; from it a chandelier of 24 pink glass shells in three tiers on
  gilt rings round a gilt stem and a glass drop (8.4 m at its foot, over every sight line), a stand-in lamp and a bake
  light at its heart. The hall's ceiling is raised to 11.2 m for it (`room_max`); the seats, the eye height and the
  screen are where they were.
- **The carpet:** scallop shells in rows (`shell_carpet`, rose shells outlined in powder blue on deep rose, a cream
  pearl between).
- **The light:** baked, from the sconces (8), the balcony's fans (7), the vault's glow down the walls (cornice lights
  every 3.6 m a side, two down the rear wall), the rear shell's lamp, the downlights (3 spots) and the chandelier; the
  vault, the rings and the dome are `PieceCove` (their light per vertex, live). The fill is rosy and low (`fill_top`
  [0.62, 0.46, 0.5], `baked_fill` 0.2), the spill 0.3 (the coves take 0.6 of it): pale pink walls would otherwise
  glow in the picture's colours. The gilt and the mirrors see a rose hall (`reflect_wall`, `reflect_ground`). The
  walls' plaster is baked at 14 cm a texel. No live light.
- **Cues:** `troughs` (every 48 s in the pre-show, paused, at the end, the intermission): the troughs' light drifts
  from pink to powder blue over 16 s (in and out eased), holds, and back over 16 s; `troughs_settle` lets go of it as
  the film starts. In the film the troughs take the film's colour (`cove_film_colour` on `film.colour`, strength
  0.85) at half their level (`cove` on `playback.playing`) times the house lamps' 15 %: a faint glow. `sunburst`
  (every 16 s in the pre-show only): the dome's lamps (`sunburst.cove`) fall to 60 % over 5 s and rise again; the
  house lamps hold (they no longer breathe). `ritual` (starting, Pre-show on): the house bells, the lamps to half, the
  festoon rises, then the lamps to 15 % over 5 s. `dim` (Pre-show off): the festoon rises, the lamps to 15 % over
  3 s. `lights_up` (the pre-show, the end): the lamps up over 4 s, the festoon down.
- **Sound:** `acoustics` `cinema` (rt60 0.7); `sound_bed` `bells` (`three_bells` by the stage, `at` [0, 3, -12],
  `reach` 12, `film_db` -4), a one-shot in the ritual. Otherwise the hall keeps its quiet (an orchestra tuning far off
  was considered: not something we could make tasteful from the synth's voices).
- **Settings:** none of its own (the common ones).
- **Comfort:** every colour change at least 16 s, the sunburst's swell 5 s each way (0.06 Hz), the festoon at the
  motion limits; nothing crosses the sight line (the festoon is `in_front` until it rises; the balcony's roll keeps
  4 to 9 cm under the front row's line to the picture's foot). In the film the mirrors show the picture at the kit's
  third, soft, and the chrome-and-gilt picture glint likewise.
- **Measured** (`test_room_pink_palace.gd`, headless, 2026-11-08): 29 draws, 282 576 triangles (229 264 of them the
  356 seats: the room's own 53 312), no lights, no particles, 10.4 MB of textures. By part: the vault and rings
  (`PieceCove`) 17 240, the gilt and mirrors (`PieceSoft`) 15 330, the dome 5 184, the walls, frieze, cornice and
  balcony (`PieceStatic`, 4 materials) 4 818, the dome's gilt and chandelier 4 956, the lamps' glass 2 020, the
  festoon 1 680. Before the pass: 22 draws, 234 504 triangles, no lights, no particles, 9.0 MB.
- **Sound measured:** in the pre-show -55.6 dBFS RMS (peak -43.2: the bells as the ritual starts), silent under the
  film. Before: -57.6 as the film started, silent otherwise.
- **The render** (lavapipe, `test_room_pink_palace.gd`; `PINK_BAKE=1` bakes it first): baked, from the seat in the
  film the walls 0.151, the proscenium 0.194, the picture 0.604 (the Streamline's walls 0.143); in the pre-show the
  walls 0.317 and the proscenium 0.460. Before the pass, not baked: the walls 0.389 in the film. The bake: about 10 s
  under lavapipe, a 512 x 512 atlas in 3 layers (4.7 MB).
- **The costs to watch on the Frame** (not measured on the headset): the triangles (282k: the seats are four fifths;
  the room's own 53k); one opaque layer everywhere (the vault, the rings and the dome are `PieceCove`, opaque, one
  noise fetch); the only see-through surface is the projector's beam. The reflecting materials (gilt, mirrors) run the
  reflect shader (no probe): the mirrors are six large surfaces, worth watching. Every frame the two kits set their
  coves' colour and level and the reflections' world; the footlights' stand-ins at most ten times a second.
- **To judge on the Frame:** the frame time; the bake's time; whether the vault's stripes are too busy close to the
  walls (the ribs' contrast is `RIB_DEPTH` and the crest/trough colours); the mirrors (do they read as old glass?);
  the troughs' drift to blue and the sunburst's swell (subtle enough?); the festoon's 17 s rise over the film's first
  seconds; the bells' level by ear.
