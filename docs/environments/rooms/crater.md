# Crater

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

`app/environments/crater.env.json`. A Moon base's cinema under a geodesic glass dome: Earth as itself over the
screen in a black sky full of stars, the crater's wall all round with its peaks catching a sun that has just gone
under the horizon behind, a small base and a lander out on the plain. Silent: no sound bed, no sound at all; only the
film is heard. The deep pass (2026-11-08: "Better to do a smaller number of incredible superb ones than a large number
not so", the user) replaced the plain tiers on a flat grey plain under sixteen ribs.

- **The amphitheatre** (`terrace`, style `amphitheatre`, `lunar` on; `kit/lunar_base.gd`): seven tiers on arcs of 120
  degrees round the screen (rows 2 in front, 5 behind, 0.95 m deep, 0.42 m rise), the pit 1.26 m under the room's own
  seat, the screen (8 x 4.5 m) 11.4 m ahead: all as before (seats, eye height and screen unchanged). Now the tiers are
  precast blocks of sintered regolith about 2 m long, each its own shade, with a chamfered nose and a warm strip of
  light hidden under it that washes the tread in front (`steps`); a slate pad on every seat and a back pad on the riser
  behind it; stairs up both ends (two steps a tier, a lamp in each riser, a steel handrail); a guard rail along the back
  of the top tier, over its drop. The floor is hexagonal pavers (`hex_pavers`) the whole round of the dome. The screen
  stands on a low stage with a line of footlights (`stage`) between two tapered pylons that carry its frame on steel
  brackets, a short slot of cool light high on each (`house`): no more legs and braces.
- **The dome** (`dome_hall` as a cover, `lattice` `geodesic`, `frequency` 6): radius 18 m centred 9 m ahead, 12 m
  high on a 0.8 m concrete drum: steel struts and bolted hubs, flat glass in every triangle (one layer, tinted almost
  black; `glass_reflect` 0.5 puts a faint ghost of the picture in the panes behind and above, `glass_dust` 0.5 dusts
  their feet), a compression ring on the drum, 16 cool lamps round it (`house`). Two airlocks either side of the
  screen (`airlocks` 2): steel portals, doors with a warm round window, green status lamps, blue panels; their tubes
  run out across the plain. A cable tray runs round the drum (`trays`).
- **Outside** (`kit/lunar_surface.gd`, one draw on `env_regolith.gdshader`, its lights one more): the regolith banked
  against the drum and rolling out to the crater's wall at 128 to 160 m from the dome's centre, 23 craters with raised
  rims (a big one ahead on the left), 70 boulders in dust skirts with their sharp shadows cast away from Earth, a
  rover's tracks curving from the right airlock to the base and to the lander, footprints from the left airlock to an
  instrument station and back; ahead on the left the base (three habitat modules half buried under bagged regolith
  with warm windows, a node, a lattice mast with a dish turned to Earth and a red beacon that swells and fades once in
  4 s, two solar arrays), on the right a cargo lander in gold foil, by the right airlock a parked rover; amber marker
  lights every 7 m along the track. The light: Earth's, from where the sky puts it (the regolith scatters it back:
  the plain ahead, lit from beyond it, is dim, its rocks' shadows reaching towards the dome); the sun's only over a
  shadow line just under the wall's crest (the peaks catch it); the dome's lamps on the berm. In the film the plain
  keeps 0.6 of its light (the eye adapts to the dimmed room) and the berm's glow goes with the lamps. All pastiche: no
  agency, no flag, no mark of anyone's; no people.
- **The sky** (`sky`, mode `space`): latitude -30, a July night; 4000 faint stars; the Milky Way with its dust lanes
  and star clouds (`milky_detail` 1), `milky_way` 0.25 before the film and 0.6 in it (bound to `playback.playing`,
  over 3 s). Earth (`earth_detail`): 5 degrees across, 30 degrees up, a little right of the screen's middle, 80 % lit
  from below (`earth_light_angle` -70: the sun under the horizon behind the room, as the lit peaks say), so a thin
  night side shows its cities' lights; Africa and the Atlantic face the room at the start.
- **Setting:** Earth's speed (`earth_speed`, 0.5 to 4 times, default 1): bound to `sky.earth_turn` by `range`
  [6, 48], so 1 x is twelve times Earth's real speed, a turn in two hours (about one a film), and 4 x a turn in 30
  minutes. The Motion setting scales it (half Motion, half the speed).
- **Cues:** `dim` (the dome's lamps out and the strips to 0.4 over 5 s with the film), `lights_up` (both back over 4
  s in the pre-show and at the end). `pause_rise_db` 0.
- **Measured** (`test_room_crater.gd`, headless): before, 12 draws, 15 836 triangles, no lights, no particles,
  4.3 MB; now 23 draws, 161 170 triangles, no live light, no particles, 9.2 MB (the pavers' and the concrete's maps,
  the craterlets' map, Earth's map). The bake under lavapipe: about 7 s, a 512 x 512 atlas in 2 layers (3.1 MB); the
  floor, the tiers, the stage, the pylons and the frame are baked, the lattice, the drum, the steel, the pads and the
  whole Moon are not.
- **Costs (judge on the device):** the dome's one layer of glass covers the whole view (blended, a cheap shader: one
  overdraw); the plain and the wall are opaque, unshaded, with two texture reads a pixel near and one far; the lights
  are a handful of small additive quads. The lattice is about 18k triangles of thin struts (aliasing, not fill, is its
  risk). No particles, no live light.
- **The renders** (lavapipe, `CRATER_BAKE=1`): from the seat the picture between its pylons on the stage, the lattice
  closing overhead against the stars, Earth in a triangle of it up and right, the wall's sunlit peaks low either side,
  the base's windows to the left; in the film the struts take the picture's colours, the Milky Way comes out and the
  floor and tiers go dark but for the strips.
- **Sound:** none, by design: `sound_bed` `silence` (it plays nothing) and `acoustics` `vacuum` (dry); no cue
  sound, no life, no pause rise (the test measures nothing on Environment). Acoustics for the film's spatial sound:
  a large glass dome, rt60 1.6, wet 0.65, late 1.95 (since 2026-11-09; before rt60 1.1, wet 0.35, with the
  terrace's open-air walls).

Twelve rooms are the history of television: `app/environments/tv_<year>.env.json` (`tv_today`, `tv_future`), in
the Room tab's Television group (`room.category` "tv"). Their names start "TV <year> - " ("TV today - " for the
present and "TV tomorrow - " for the future, which sort last in that order), so the group reads as a timeline. (A
room's name takes letters, digits, space, - and _ only. "Television, 1930: ..." is refused, and the longer
"Television 1930 - ..." names made the Room tab's card too wide in the pseudo-locale.) Each is a `domestic` room
(style `plain`, or `bedroom_1993`) with `screen` "telly" (tomorrow's: "wall") and the era's preset on it, the `seats`
system for the chairs, and cues for the lamps: down when the film starts or plays (`lamps_down`), up in the pre-show
and after the end (`lamps_up`). Tested by `tests/test_room_tv.gd` (headless: every check of `test_environments.gd`,
the preset, the telly's shape and size, each setting and what it does, the cues) and `tests/test_room_tv2.gd` (the
rooms of 1937, 1966, 2002, today and tomorrow the same way, and the whole group's names in the order time travel
takes them).

**The telly's shape.** The film is drawn on the screen's own mesh, which is the document's width at the film's
aspect (`video_screen.gd get_flat_size()`); a document cannot give it another shape. So the domestic telly's tube (the
cabinet's opening and the dark glass behind the picture) is 4:3 for the sets before 2000, and a 16:9 film sits in it
letterboxed, as a wide film did on a 4:3 set. A 4:3 film fills the tube. The CRT's bulge and round corners are the
tube's (`presentation.tube` 1.33 in the presets before 2000, since 2026-11-07): the corners lie mostly in the bars
above and below a wide film and clip its corners a little, and its edges bow as a 4:3 face's would.

**The telly's size.** The headset shows about 20 pixels a degree, so a set as small as it really was, across a room,
would be a postage stamp. The viewer's chair is pulled up to the set instead: every picture is 17 to 23 degrees across
from the viewer's own seat (the test holds it), its centre 0.25 to 0.3 m under the eyes. The smallest width a document
screen may have is 0.3 m.

| Room | The tube (w x h) | From the viewer's eyes | Across | Why |
|---|---|---|---|---|
| 1930 | 0.30 x 0.225 m | 0.9 m | 19 degrees | the smallest screen a document may give; the set's own window was smaller, so the chair is close, as a family huddled round one |
| 1937 | 0.40 x 0.32 m (the mirror's picture, 5:4) | 1.1 m | 21 degrees | a mirror-lid set: the chair close to the cabinet, as the family's was |
| 1953 | 0.36 x 0.27 m (a 17 inch tube) | 1.1 m | 19 degrees | coronation day: every chair in the house round it, and the viewer's the best one |
| 1966 | 0.48 x 0.36 m (23 inch) | 1.35 m | 20 degrees | the rented console, the settee across from it |
| 1972 | 0.46 x 0.345 m (22 inch) | 1.4 m | 19 degrees | the colour set in the corner, the chairs in a row |
| 1983 | 0.30 x 0.225 m (14 inch portable) | 0.8 m | 21 degrees | at a desk: the portable is near, as a screen for a home computer was |
| 1987 | 0.54 x 0.405 m (26 inch) | 1.5 m | 20 degrees | the family set, the settee across from it |
| 1993 | 0.40 x 0.30 m (20 inch) | 1.1 m | 21 degrees | a bedroom set seen from a bean bag on the floor |
| 2002 | 1.12 x 0.63 m (50 inch rear projection, 16:9) | 3.1 m | 20 degrees | the big set across the lounge |
| 2005 | 0.72 x 0.405 m (32 inch, 16:9) | 1.9 m | 21 degrees | the first flat panel: wider, and the sofa further back |
| today | 1.20 x 0.675 m (55 inch, 16:9) | 3.2 m | 21 degrees | a thin panel on the wall, the sofa across the room |
| tomorrow | 1.44 x 0.81 m (a part of the wall, 16:9) | 3.8 m | 22 degrees | no set: the wall is the picture, across a bare room |
