# Drive-in - 1958

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

`app/environments/drive_in_1958.env.json`, apart from the older drive-in scene (`drive_in.tscn`). The front bench of
a 1950s convertible on a full drive-in's lot in the desert, the sunset fading to the Milky Way as the film runs. The
quality pass (2026-11-08) answered "you may be able to do a large number of superb ones, see how it goes, but aim
for incredible quality plz!" (the user): the car, the lot, the desert and the sky were made anew; the seats, the eye
height and the screen did not move.

- **The car** (`vehicle`, id `car`, `kit/car_shape.gd`): a lofted body (sections along its length: a long bonnet with
  a crown, a belt line that sweeps up into fins, wheel arches cut in, a side spear in chrome), a jet ornament on the
  bonnet, wing bullets, chrome headlamp rims, bumpers with a grille, whitewall tyres. Inside: a padded dash with a
  lit speedometer (a sweep of ticks, a needle), a clock whose hands keep the sky's own `hour`, a radio's band and
  push buttons, fuel and temperature gauges (`shaders/env_dash.gdshader`: the picture glows as a lamp does, and the
  dial light is a stand-in lamp on the benches); a big thin steering wheel with a horn ring; a chrome-framed
  wraparound windscreen; tuck-and-roll benches (rolls with their seams, piping); the lot's speaker hung on the
  driver's door, its cable to the post. Occlusion is baked into the vertex colours (the cabin's floor and footwells
  darker), so the car is unbaked and costs no lightmap.
- **Chrome and paint that show the night** (`kit/reflect.gd`, `room_material.gdshaderinc` `REFLECT`): no live probe.
  The house shader reflects a cheap world: the sky's zenith, horizon and glow (from the `sky` system, so it darkens
  with the dusk), a dark skyline, the ground, the screen (its plane and its picture: the bias light's copy, so the
  film moves on the bonnet), and a glint ellipse (the snack bar's neon on the chrome, `glint_*`). Lacquer is a
  Fresnel coat over the paint; chrome is metal. `reflect_screen` follows `playback.playing` (0.25 to 1).
- **The lot** (`terrace`, id `lot`, `drive_in` on, `kit/drive_in_lot.gd`): rows of bays on arcs that fan round the
  screen (30 degrees, 7 m apart), each row on its hump; 30 parked cars (one coarse hardtop shape, a MultiMesh, dark
  period colours with chrome glints, no people; the viewer's neighbours and the bay straight ahead stay empty);
  a speaker post with two speakers by each bay, cables to the cars, an amber ramp light at its foot; gravel lanes and
  asphalt bays with ruts, oil and the cars' shadows in the ground's vertex colours, the plain beyond out to 186 m;
  the screen tower's back and frame; the snack bar and projection booth 15 m behind (a swept roof, neon "SNACK BAR"
  tubes with their halo, lit windows, its own warm stand-in lamp); the entrance marquee at the right behind ("MESA
  MOON", its board "TWO FEATURES / SHOW AT DUSK", a ring of chaser bulbs: `shaders/env_bulbs.gdshader`, slow, 0.6 a
  second, never in the flicker band); a fence round the lot; the highway 78 m behind, where a car's head and tail
  lights cross now and then (`car_passes`). All the text is our own stroke font (`kit/strokes.gd`).
- **The beam** (`screen_frame` `beam_style` `volume`, `shaders/env_beam_volume.gdshader`): one closed pyramid from the
  booth's lens to the screen. Each pixel sums the light along the eye's ray's chord through it (exactly: the light per
  metre falls with the square of the distance from the lens), takes the picture's colours across the beam and a slow
  haze. It reads as a shaft from the side and as a soft glow overhead from inside (the car sits under it).
  `beam_strength` 0.0002.
- **The desert** (`vista`): the mesas and hills as before, and `cacti`: saguaros and yucca trees (Joshua-tree-like
  silhouettes) in five groups round the lot, all beyond the fence, none in front of the screen.
- **The sky** (`sky`): latitude 35, mid July, the screen facing west-south-west with the sunset's glow to its right.
  Tracks by `film.minutes`: `dusk` from the last light (0) to night (0.75 at 12 minutes, 1 at 25), and `hour` from
  20:45 on, so the stars turn through the film. The twilight's colours are the desert's (`twilight_*`, `glow`); the
  `afterglow` and `belt_colour` draw the band over the sunset and the Earth's shadow with the belt of Venus opposite;
  the `evening_star` stands over the glow and stays bright in the twilight; `milky_detail` gives the Milky Way its
  dust lanes and star clouds. `milky_way` follows `playback.playing` (0.35 to 0.9).
- **Light:** no live light. Stand-in lamps for the dash, the snack bar's neon and the marquee; the lot's lights by
  live params (`lot.neon`, `lot.chase`, `lot.ramp_lights`); the film's light on the cars and the ground (the
  spill, `film.colour`). During the film the lot goes night-dark.
- **Life:** 30 moths in the projector's beam; a plane's lights about every 5 minutes.
- **Cues:** as the film starts or plays (`lamps_off`): the headlamps off, the dials dimmed, the marquee's chase
  stops over 4 s, the ramp lights go to 35 % and the neon to 65 %. In the pre-show (`arrive`) all of it full. After
  the end (`time_to_go`): the lot's lights back up, then the dials and the headlamps. `road` (every 70 s, chance
  0.45): a car on the highway, its lights and its sound together (`lot.car_passes` with `way` 1, `far_car.play`).
- **Setting:** Window speaker (`tinny`, bool, default off): `presentation.speaker` by map (`window` or `none`). It
  is off by default: a whole film through a band-limited mono speaker is a big loss of the film's sound, which the
  room must never spoil; the viewer turns it on for the effect. No picture stage, so the film layer stays.
- **Sound:** `acoustics` `outdoors` (rt60 0.2); `sound_bed` `crickets` around the car (four voices, `radius` 8);
  `sound_bed` `train` (a freight train about 380 m off, `at` [-260, 2, -280], `reach` 300, `every` 900: now and
  then, its two-note horn early on); `sound_bed` `wind` (everywhere, `gain_db` -5, `film_db` -10: a soft breath over
  the lot); `sound_bed` `far_car` (`far_car`: a big old car on the highway, tyres on the slabs' joints and a V8's low
  burble, its pitch riding the passing; travels from [-420, 1, 78] to [420, 1, 78] over its 34 s, with the lights,
  `reach` 80, `vary` 0 so it keeps time with them). The window speaker stays the Window speaker setting.
- **Measured** (`tests/test_room_drive_in_1958.gd`, headless; before the pass / after):

  | | Draws | Triangles | Lights | Particles | Textures | Lightmap atlas |
  |---|---|---|---|---|---|---|
  | Before | 30 | 17 288 | 0 | 0 | 11.3 MB | 604 x 628 |
  | After | 27 | 151 134 | 0 | 0 | 7.4 MB | 816 x 752 |

  The triangles are mostly the parked cars (30 x 2 390, one MultiMesh draw), the car (24k), the ground (17k) and
  the posts (14k). Sound at the slider's default (dBFS RMS, with the train passing): before -57.8 in the pre-show,
  -60.3 as it starts, -63.0 in the film, -69.8 under a film; after -56.7, -59.1, -62.6, -69.1. A clear sight line
  from all 6 places.
- **Fill rate (to judge on the Frame):** the beam is one large additive surface (from inside it covers the upper
  view; one pass, five plane tests, two haze reads a pixel); the sky dome's Milky Way detail reads its noise twice
  more, only inside the band.
