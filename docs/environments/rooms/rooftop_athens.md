# Athens rooftop

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

`app/environments/rooftop_athens.env.json` (Cinemas). An open-air summer cinema on a roof in Athens (the name is short:
a longer one, "Athens rooftop summer cinema", made its button wider than the Room tab in the pseudo-locale): director's
chairs in rows on the tiles, a low whitewashed wall with bougainvillea over it, strings of bulbs, the screen painted on
the next building's blind wall. Beside the wall a temple stands floodlit on its hill under a summer night's stars;
planes cross now and then, and a cat walks along the wall top.

The deep pass (2026-11-08) made the city round the roof and the roof itself by hand (the terrace's `city`: above).

- **The city:** blocks of four to seven floors on a grid of streets 12 m below, white, cream, ochre and rose, with
  balconies, shutters, shops at street level; on the roofs water tanks, solar heaters, aerials, a pergola, washing.
  Their windows are lit in the shader: some warm, some blue with a television, some shuttered, curtained or louvred,
  fewer as the night goes on. Near the roof the buildings are made one by one: the screen's building (tanks on a stand
  over its top), two lower neighbours to the left with heaters and washing, a tall block front left, a roof garden
  with fairy lights to the right. A church 40 m off on the left: a cross-in-square with its dome on a drum and two
  bell towers, lit from the square below. A chapel on a far hill behind with zig-zag lamps up its path. Far hills
  166 m out with a thousand lights. A warm haze thickens with distance.
- **The hill:** an invented temple on a rock beside the screen building (52 degrees, 150 m; its plateau 13 m up):
  its walls with buttresses, a ruined temple of six by thirteen columns, a smaller one, a gateway, pines, white
  houses round its foot; floodlit honey-gold from below (stylised: not a copy of any real building).
- **The roof:** terracotta quarry tiles (`quarry_tiles`), the whitewashed parapet with its coping, stains and spouts;
  the screen painted on the next building's weathered wall, the ghost of an older roof's gable on it, two ghost
  signs for invented shops (a coffee house, a soap maker) in Greek letters, the speakers, a drainpipe, a fire
  escape's ladder with its cage, tanks over the top; the projection hut behind the seats (whitewashed, a blue door, a
  vent, its port glowing cool, the projectionist's small window warm; tonight's poster in a case; jasmine up its
  corner); the kiosk in the back right corner ("ΚΥΛΙΚΕΙΟ", a striped awning, bottles, cups, basil, a lit fridge,
  next week's poster on its side); bougainvillea over the right parapet from three big pots; a lemon tree in the
  back left corner; geraniums in old oil tins; the bulb strings sagging between steel poles on both sides, across
  behind the seats and on to the hut and the kiosk. The posters are our own: a moon over the sea, a sun over hills.
- **Light:** the bulbs (house group, down to 0.12 for the film) with their halos, five stand-in lamps
  before a bake and bake lights along each string; the kiosk's bulb and fridge (accent, to 0.3 for the film); the
  hut's ports (booth). The sky's light and the Moon on the city; the floodlit temple.
- **Systems:** `light`; `terrace` (`rooftop`, `city`, a wall 8 m high, seven rows of nine); `seats` (`director`,
  navy linen on oak); `sky` (latitude 38, day 200, 21:30, the screen facing 200 degrees, the sunset's glow at 300, a
  nearly full Moon low at 112 degrees); `life` `planes` (plane lights), `moths` (nine, round the bulbs behind the
  seats) and `cat` (its way along the left wall's top, 6.65 m out: never in the sight line, measured over 4
  minutes). The `vista` and the `kit` (bougainvillea) went: the city and the roof draw their own.
- **Cues:** `evening` (the pre-show and the end): the bulbs and the kiosk up over 4 s; 20 s later the church bell.
  `lights_down` (starting, playing): the kiosk to 0.3 over 5 s, the bulbs to 0.12 over 7 s.
- **Film-time tracks:** `sky.dusk` from 0.75 to full night over the first 20 minutes; `terrace.windows` from 1 to 0.85
  at 45 minutes and 0.55 at two hours (the city goes to bed).
- **Settings:** `floodlights`, "Floodlights on the hill" (0..1, full): `terrace.floodlight`.
- **Default seat:** the middle of the third row from the back (the origin), 11.9 m from a 6.4 m picture.
- **Sound:** `acoustics` `outdoors` (rt60 0.25, wet 0.15); `sound_bed` `cicadas` around the roof (four voices,
  `radius` 9, `reach` 9), `film_db` -14: they fade as the film starts; `city` (new) around the roof from 6 m below
  (four voices, `radius` 16, `reach` 14, `gain_db` -2, `film_db` -10); `moped` passing in the street 12 m below
  (`at` [-45, -12, 12] `to` [45, -12, 12], `reach` 20, `every` 240, `jitter` 0.5); `bell` (`church_bell`, new) at
  the church, `reach` 30, `gain_db` -4, `film_db` -30, played by the `evening` cue; the cat's purr as it sits, from
  `life` at `voice_db` -15.
- **Measured** (before the pass, then after): 15 draws, 29 086 triangles, 0 lights, 0 particles, 9.3 MB; now 25 draws
  (the roof 16, the city 1, the seats 2, the sky 3, the cat, the moths, the planes), 139 894 triangles (the city
  67k, the plants 31k), 0 lights, 0 particles, 8.4 MB. Sound at the slider's default (dBFS RMS): before -54.4 in the
  pre-show, -61.1 as the film starts, -70.0 in the film, -77.4 under a film at the reference level; now -54.2,
  -58.9, -69.1, -76.4.
- **Fill rate:** the city is unshaded (no lights, no shadows) and drawn front to back by its mesh order only roughly;
  its windows are a few hash lookups a pixel, faded to an average where they would shimmer. The halos are additive
  quads, small. The sky dome fills what the city does not.
- **To judge on the headset:** the frame time with the city (140k triangles), the levels of the city's murmur and
  the bell by ear, the halos' size, the windows' shimmer at a distance.
