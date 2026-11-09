# Bathysphere

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

`app/environments/bathysphere.env.json`. A round hall under a glass dome on the sea floor. Through the glass: a bowl
of sea floor with kelp on a ledge to the left, coral on a ledge to the right, an old diving bell half silted behind,
a vent whose bubbles stream past the glass, floodlights reaching out into the murk, marine snow drifting through
their beams, schools of fish and glowing bells round the screen, now and then a manta gliding overhead, and in a
quiet scene a whale. Inside: brass ribs with their rivets, portholes, pressure gauges whose needles swing with the
film's bass, and behind the seats an instrument console with a sonar scope sweeping. The second pass (2026-11-08)
answered "go nuts on the bathysphere - I think that has a lot of potential that isn't realised yet" (the user).

- **The hall** (`dome_hall`): radius 9 m, a 1.3 m drum of dark metal with 12 warm lamps (group `house`), a glass
  dome 7.5 m high on 12 brass ribs turned half a step (`rib_phase` 0.5, so no rib stands straight behind the
  picture), an oak floor, a low stage. The screen (6.4 x 3.6 m, its bottom 1.45 m up) stands 8.3 m ahead, inside the
  glass. Plush seats in teal velvet on arcs round it (six rows, 100 degrees); the room's own seat is at the origin,
  in the third row. Seat picking is the builder's (`ring` seats; the chosen one folds away).
- **The fittings** (`dome_hall`, `kit/dome_fittings.gd`): `rivets` (two heads every half metre down each rib's inner
  face, one every 0.4 m round the drum's ledge), 10 `portholes` round the drum (none in front; brass rims with eight
  bolts; the water's own shader in the glass, so a port shows the water as the dome does), 6 `gauges` round the drum
  and two on the console (backlit cream faces with ticks round three quarters and a red arc; each needle rests at
  its own reading and swings by its own share with `gauge`, bound to `film.bass` with 0.3 s smoothing), the
  `console` against the drum behind the seats (a sloped panel with brass trim, two rows of toggles, small steady
  green, amber and blue lamps, and the sonar scope: `shaders/env_sonar.gdshader`, a sweep once in 6 s, range rings,
  echoes that light as the sweep passes, three of them a school drifting), and the `hatch` in the floor behind the
  last row (a brass ring, a steel lid, a wheel on four spokes). The fittings are unbaked (their many small faces would
  each be a lightmap chart) and lit as the seats are.
- **The water** (`outside` water, `shaders/env_water_outside.gdshader`, `env_water.gdshaderinc`): the colour by
  where the eye looks, the deep below and the lit water above; at the shallow end the surface's light: Snell's
  window overhead (the sky squeezed into a disc 49 degrees round the zenith, the surface's waves rippling in it, its
  rim wavering) and shafts slanting down round it. `outside_glow` follows `playback.playing` (0.7 before the film,
  0.45 in it, over 3 s). The glass is tinted almost black, so it adds little haze.
- **The sea floor** (`seabed`, `kit/seabed.gd`, `shaders/env_seabed.gdshader`): a bowl round the hall whose banks rise
  to the sides and behind (4 to 7 m up 24 m out, so they show over the drum) and fall away behind the screen into a
  trench; 30 `rocks`; two ledges near the glass that lift what grows on them over the drum; 28 `coral` (branching
  coral, coral heads, sea fans, anemones) on the right ledge and round it; 90 `fronds` (kelp: a stalk and long blades
  at the nodes, swaying slowly) on the left ledge and in beds behind; the `wreck` (an old diving bell on its skid,
  tilted, its portholes dark, a fallen lattice derrick, an anchor) on the left behind; the `vent` (a rough chimney
  on the right behind) with 140 `bubbles` rising past the glass to the surface. Lit by the water's light from above,
  the surface's light and caustics in the shallows, the floodlights' pools and the film's light through the glass
  (only on the screen's room side); then the murk (`murk` 0.07 a metre) takes it into the water's own colour, so the
  far banks melt into the blue.
- **In the water:** 1800 flakes of marine `snow` sinking slowly round the dome (never inside it), glittering where the
  floodlights or the film's light catch them, a few glowing now and then in the abyss; 4 `floodlights` on the drum's
  top outside, aimed at the kelp, the coral, the bell and the vent, their beams soft cones in the murk
  (`shaders/env_water_beam.gdshader`: each fragment takes the eye's ray's chord through the cone, so a beam reads from
  the side and along it from the seats behind its lamp).
- **The light** (`light`): a cool blue-green fill from above, warm lamps, and caustics on the floor, the seats and
  the drum (`caustics` by the Depth setting, `caustic_scale` 1.3).
- **Life** (`life`, five systems, all outside the glass): `fish`, 40 silver fish to the left, schooling 0.8;
  `shoal`, 28 smaller grey-green ones to the right, schooling 0.6 (a turn starts at the leaders and ripples back
  through the school); `glow`, 16 glowing bells round the picture (`size` 2, their colour half the film's, their glow
  rising in quiet scenes: `film.quiet` to 0.8..1.6, smoothed 3 s); `manta`, a manta ray gliding high over the dome on
  a long curve, about every 150 s, its wings beating slowly and gliding, pale below; `whale`, its way high behind the
  screen (13 m up, 17 to 19 m out), now with twelve rings, long pectoral fins and a paler throat. The fish's and the
  bells' `attraction` follows `film.brightness`. The regions are boxes outside the dome's ellipsoid and inside the
  water's sphere, to the sides of the picture, so no school hides behind it.
- **Settings:**

  | Setting | Choices | Default | What it moves |
  |---|---|---|---|
  | Depth (`depth`) | Sunlit shallows, Twilight, Abyss | Twilight | `hall.depth` 0, 0.5, 1 (smoothed 3 s): the water's colours, the surface's light, the specks' glow; `light.caustics` 1, 0.3, 0 |
  | Lights outside in the film (`flood_level`) | 0 to 100 % | 30 % | the floodlights' level once the film has started (the `dim` cue); before the film they are full |
  | Whale (`whale`) | Never, Rarely, Sometimes | Rarely | the whale cues' and the far song's `requires` |

  The water's colours at the ends of `depth` are `dome_hall.gd SHALLOW_TOP` / `SHALLOW_DEEP` and `ABYSS_TOP` /
  `ABYSS_DEEP`; the document's `water_top` and `water_deep` are its middle (twilight).
- **Cues:** `dim` (with the film: the house lamps to 12 % over 4 s, then the floodlights to the setting's level over
  6 s), `lights_up` (pre-show and the end: lamps and floodlights up), `ping` (a sonar ping every 12 s in the pre-show,
  paused and after the end), `first_ping` (with the Pre-show setting, as the film starts: a ping, the scope dims to
  35 % over 6 s), `scope_up`, the two whale cues (on `film.quiet` above 0.9 for 4 s, while playing: rarely a chance of
  0.3 and a cooldown of 30 minutes, sometimes 0.7 and 15 minutes), and `far_song` / `far_song_rare` (a whale's song
  far off in a quiet scene, 22 m away behind and to the left: sometimes a chance of 0.5 and 10 minutes, rarely 0.3
  and 20 minutes).
- **Comfort:** nothing moves fast or crosses the sight line. The shafts, the caustics and the fronds' sway change at
  well under 1 Hz at any point; the sonar's sweep brightens a point once in 6 s; the manta glides at 1.4 m/s at most,
  more than 11 m up; the floodlights' level changes over 5 and 6 s. The Motion setting scales `water_motion` (shafts,
  caustics in the water, fronds, snow, bubbles) and `light.caustic_speed`; at 0 the water stands still.
- **Measured** (`test_room_bathysphere.gd`, headless, 2026-11-08): 29 draws, 105 755 triangles, no live lights, no
  particles (the specks are vertex-animated quads), 6.1 MB. Before the second pass: 12 draws, 79 078 triangles. By
  part: the seats 79k triangles (2 draws), the sea floor with its rocks, coral, bell and chimney 8.7k (1), the fronds
  4.1k (1), the rivets 4.4k (1), the marine snow 3.6k (1), the brass fittings 2.5k (1), the water sphere 2.3k (1;
  24 rings of 48 sides, where it was 12 of 24, so its rim is round against the banks), the whale 240, the manta 35.
- **The costs to watch on the Frame** (not measured on the headset yet): fill, not geometry. The water sphere
  covers the whole view behind the glass, as before, its shader now a few dozen ALU and one texture read for the
  window's waves (shallows only); the sea floor is opaque and drawn behind the glass (early depth rejects most of it);
  the house shader takes two more texture reads where `caustics` is on; the beams are additive cones (about 10 % of
  the view from the seat, a quadratic each fragment); the snow's quads are tiny. No new transparent layer is large.
- **The render** (lavapipe, `test_room_bathysphere.gd`): from the seat (the screen, the schools either side, the
  bells round it, the Snell's window over the dome), left (kelp on its ledge in the floodlight, the bell behind),
  right (the coral ledge, the vent's bubbles), up (the window, the shafts, the manta), a side seat, the console (the
  scope sweeping, the gauges, the hatch), from the back, and from the seat in the shallows and the abyss.
- **Sound:** a small hard room of metal and glass (`acoustics` `hull`, rt60 0.9); the hull creaking now and then to
  either side (`sound_bed` `hull_creak` twice, at the drum left and right, `every` 180 each: one about every 90 s);
  the deep's low hum (`deep_hum`, `gain_db` -4); the vent's `bubbles` outside behind on the right (`gain_db` -3,
  `reach` 8); the console's `sonar` ping (`gain_db` -2, by the `ping` cue); a far whale's song (`far_song`, the
  synthesiser's `whale`, `gain_db` -6, 22 m off); the passing whale's song is `life`'s (`voice_db` -4). Measured
  (`test_room_bathysphere.gd`, the slider's default): -51.4 dBFS RMS in the pre-show, -72.3 under a film at the
  reference level.
- **To judge on the Frame:** the frame time with the water, the beams and the caustics (fill); whether the
  floodlights' beams and the Snell's window are too bright beside the film at 30 %; the shallows' brightness in the
  film; the sonar ping's and the bubbles' levels by ear.
