# Ice cinema

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

`app/environments/ice_cinema.env.json`. *An ice hotel's cinema of sawn blocks and carvings under a vault of ice:
candles glowing inside the ice, hides on ice benches, the polar night through the window and the doorway, the
northern lights overhead.* The deep pass (2026-11-08) answered "continue working on the environments one-by-one like
you did with the bathysphere, really improving their quality, imagination, delight, detail, lighting and so on" (the
user); the room before it was the domestic builder's ice style, a box of drawn blocks lit by the film's spill. A
second pass the same day answered the coordinator's look at the renders ("good bones ... but from the seat it is not
yet 'wow'"): real candles, reindeer pelts, the vault in blocks of ice, a dimmer room in the film, a floor of packed
snow.

- **The ice** (`ice_shell`, `kit/ice_hall.gd`, the house shader's `ICE`): walls of sawn blocks, 0.44 m courses laid
  in a stagger with snow in the joints, each block a slab of its own standing 3.5 cm proud with frosted sawn edges;
  inside each, at two depths that move against the face as the head moves, bubbles (single and in strings), a few
  cracks and a milky cloud, each block its own seed; the light that reaches the ice shows inside it, the clear faces
  take little. The vault is ice too, on five ribs of clear ice (none against the front wall, so the owl has its
  lunette whole): its blocks are the shader's (`ice_vault`: courses 0.46 m along the arch, each course's blocks their
  own length and set off from the last's, the joints packed with snow, the edges frosted, each block its own seed,
  shade and tilt), so the mesh stays five bays of smooth strips.
- **The floor** (`IceFloor`, the ice shader's `ice_snow`): packed snow on a sheet of 25 cm cells, banked a few
  centimetres against the walls (not in the doorway), gently uneven, trodden greyer and lower along the path from the
  doorway into the left aisle; boot prints pressed in here and there (their slopes shaded from the screen's side) and
  a sparkle near the eye where a crystal catches it (it changes only as the head moves; none past 4.5 m).
- **Candles:** 12, each in a niche cut into the blocks (an ice box with its sill: three in the left wall, four in the
  right, two behind, two in the front wall either side of the picture) and one on the window's sill. Each a pillar of
  ivory wax in a small dish, lit by its own flame: the foot in shadow, the shoulders lit through near the flame, an
  uneven rim, a drip or two down the side, the molten pool glowing (all emission in vertex colours on the lamp
  material, so they follow their group and waver with the flame); the flame a white-yellow core over a blue foot, an
  orange body and a warm halo round it, in one picture (crossed quads, wavering slowly: the kit's `flicker` 0.5, under
  3 Hz). Their glow blooms inside the ice round them, lights the niche's faces (`ice_glow_face`) and glints in the
  wet faces (the shader's twelve glows, by group level each frame); they light the bake (the kit's lamps, hidden).
  The front wall's two are in `house`, the others in `accent`.
- **The picture's wall** (`ice_screen`): the screen (unchanged, 3.2 x 1.8 m) on a smoothed panel of snow, a carved
  frame of three frosted steps round it, and animals in frosted relief with their lines cut in: a polar bear and a
  whale on the left, a fox and a hare on the right, a snowy owl over the picture with its wings spread. In the film
  the picture's colours seep through the front wall round the screen (`ice_film`, fading over 0.7 m) and show
  faintly in the side walls' faces at a glancing look (`ice_shine` 0.3).
- **The view out** (`ice_outside`, its own unshaded shader): through the clear pane of the left wall's window and
  the open doorway behind, a snowfield under the polar night with drifts, snow banked against the walls and a
  trodden path from the doorway; spruces under snow, the forest's edge 55 to 85 m out, the fells low in the
  south-east under a low gibbous Moon; a cabin far off with its windows lit warm. The snow glitters a little where
  a facet catches the Moon (still in the world, no twinkle). The skylights: three in each haunch of the vault, over
  the back three bays, clear glass (a faint rim, the night's colour in it at a slant, not the film's), so the aurora
  (`aurora_bearing` 90, the left) is seen overhead from the seats. Snow falls gently outside the doorway and the
  window (`weather`, 260 flakes, never inside).
- **The seats:** the seats system's `hide` on an ice bench for each row (`ice_benches`): since the second pass a
  reindeer's pelt, flat on the bench with its front hanging over the edge, its outline ragged and narrower at the
  neck, the dark back down the spine shading to grey-brown flanks and a cream belly, the hair lying in patches, and
  a fringe of tufts all round (random lengths, longer in clumps, darker at the tips); a little sheen. Two pelts on
  the floor, domed a little, the same colours and a fringe lying out over the snow.
- **Systems:** `light` (spill 0.2, a cold low fill, baked fill 0.9, the candles' warm colour), `domestic` (style
  `ice`, `shell` `kit`: the builder lays out the 6 x 9 m room, its window, doorway and seats, the kit draws the
  ice), `seats` (`hide`, cream fur, spill 0.03), `kit` (the four pieces, 12 bake lamps, `flicker` 0.5), `sky` (68
  degrees north, a January night at 23:00, the Moon 9 degrees up at bearing 124, the Milky Way faint), `atmosphere`
  (breath 0.6, a thin low fog), `weather` (light snow outside), `acoustics` `ice`, `sound_bed`.
- **The film's light:** each surface takes its own share of the film's spill, small, so the far room stays dim in
  the film and only tinted (the coordinator: "the far vault and floor should stay dim, just tinted"): the walls' ice
  0.15, the vault 0.03 (its gloss 0.3), the floor 0.02, the pelts 0.03 to 0.04; the colour round the screen is the
  seep's. Measured from the seat under the test's bright picture (0.59), baked: the vault 0.14 and the floor 0.14
  (before the second pass about 0.25 and 0.24; Atmospheric 1928's houses 0.12); in the pre-show the vault 0.22, the
  floor 0.23; the right wall beside its candle niche 0.44 in the pre-show and 0.33 in the film.
- **Setting:** Aurora (`aurora`: in quiet scenes, always, off) maps onto `sky.aurora` (0.15, 0.8, 0).
- **Cues:** `candles_down` (with the film: the front wall's candles to 10 % over 6 s, the others to 40 % over 9 s,
  the aurora back to the setting's level over 12 s), `candles_up` (the pre-show and the end: the candles up),
  `aurora_preshow` (the setting on "in quiet scenes", before the film and after it: the aurora lively at 0.75 over
  15 s), `aurora_swells` (2 s of a quiet scene: the aurora to full over 8 s), `aurora_settles` (the quiet ends, in
  the film, the credits or paused: back to the setting's level over 12 s).
- **Comfort:** the flames waver under 3 Hz and only a little; the aurora's changes take 8 to 15 s; the snow falls
  slowly and only outside; the floor's sparkle changes only with the head, near the eye; nothing stands between a
  seat and the picture (the sight line from every seat is tested); no candle within the picture's frame.
- **Measured** (`tests/test_room_ice_cinema.gd`, headless, 2026-11-08, after the second pass): 20 draws, 75 495
  triangles, no live light, 276 particles (the snow and the breath), 4.7 MB. After the first pass: 19 draws, 56 673
  triangles. Before the passes: 17 draws, 15 976 triangles, 16 particles, 6.5 MB. By part: the outside 34.3k
  triangles (1 draw), the seats 15.1k (2: the pelts with their fringes, 15 of them), the ice blocks and carvings
  8.8k (1), the candles 5.6k (2), the stars 4.0k, the pelts on the floor 2.5k, the sky dome 2.4k, the floor 1.7k,
  the vault 0.9k, the joints 0.1k, the flames 48 (2), the glass 14. The bake: five static meshes (the blocks, the
  vault, the joints, the floor, the floor's pelts), each atlas at most the test's limit, the largest 628 x 476; 12
  candle lamps and the Moon's spot, all hidden; 4 s under lavapipe.
- **The costs to watch on the Frame** (not measured on the headset yet): fill, not geometry. The ice covers most of
  the view and its shader does more than the house shader: two more texture reads (the inner map at two depths), a
  loop over the twelve glows (a distance, an exponential and, since the second pass, a dot for the light on the
  face, each), the glints, the seep and a fresnel; the vault adds a few hashes for its courses. The floor's snow form
  skips the inner map and the glow loop (a few hashes, two derivatives). If the frame time is short, the glow loop
  is the first thing to cut (fewer glows, or only the nearest few); it stays for now because the niches' warmth is
  the room's light. The outside is unshaded and opaque; the glass panes are small (the only transparent layers
  besides the flames, the snow and the breath).
- **The render** (lavapipe, `test_room_ice_cinema.gd` with `ICE_SHOTS`, `ICE_BAKE` for the bake): from the seat,
  left (the window, the left niches), right, up (the vault, the skylights), from the back, a side seat; close: the
  window, the doorway, the frame, the bear, the owl, the fox, a niche, the hides.
- **Sound:** the ice's bright ring (`acoustics` `ice`); far huskies beyond the doorway now and then (`sound_bed`
  `huskies`, `every` 300, 120 m out); a soft wind at the doorway (`wind`, `gain_db` -3, reach 4 m); the ice creaking
  in the wall now and then (`ice_creak`, `every` 240). No aurora sound. Measured (`test_room_ice_cinema.gd`, the
  slider's default): -54.8 dBFS RMS in the pre-show, -72.0 under a film at the reference level.
- **To judge on the Frame:** the frame time with the ice shader over the whole view; the hides' brightness (they
  are seats, lit live and by the probes, not the lightmap, and render darker than their colours under lavapipe); the
  candles' level in the film (40 %, the front wall's 10 %) and whether the film's seep round the screen is too much;
  the floor's sparkle in the headset (it should read as crystals, not as noise); the aurora's brightness in the
  skylights during the film; the huskies' and the wind's levels by ear.
