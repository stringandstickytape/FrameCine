# The sky and the vista

Part of the environments engine: [`docs/environments.md`](../environments.md) has the design and says where each part is.

Two systems of kind `sky`. Both are cheap: unshaded shaders on a few meshes, no live light, no particles, no
texture from a file. Neither makes a sound. Neither moves the viewer or the horizon.

### `sky`

`scripts/env/systems/sky.gd`. A dome round the viewer: the evening's twilight to full night, the real stars, the Milky
Way, clouds, an aurora, shooting stars, and Earth as seen from the Moon.

| Parameter | Default | What |
|---|---|---|
| `mode` | `sky` | `sky` (air: the gradient), `space` (black, the stars at full: the Moon), `black` (nothing drawn: the Void) |
| `latitude`, `day_of_year` | 40, 200 | where and when the stars stand (degrees north; day 200 is mid July) |
| `hour` | 22 | local mean time. Live: a track can turn the stars over the film. They turn at most an hour of sky a minute (0.25 degrees a second), times the Motion setting |
| `facing` | 180 | the compass bearing the screen faces (180: south). Every other bearing is a compass bearing too |
| `dusk` | 1 | 0 the last light of the evening, 1 full night. Live, a brightness |
| `night_zenith`, `night_horizon`, `twilight_zenith`, `twilight_horizon`, `ground` | dark blues, a warm horizon | the gradient's colours |
| `glow`, `glow_bearing` | orange, 300 | the sunset's glow low over the horizon, where the sun went down; it fades as dusk falls |
| `stars` | 1 | the stars' brightness. Live, a brightness |
| `faint_stars` | 1600 | generated faint stars besides the catalogue's bright ones (0..4000) |
| `twinkle` | 0 | a slow, small twinkle, under 1 Hz; off by default for comfort. Live, a brightness |
| `lines`, `line_colour` | 0, pale blue | the constellations' lines, faint, as a planetarium shows them. Live |
| `milky_way`, `milky_colour` | 0.6, warm white | the Milky Way. Live, a brightness |
| `milky_detail` | 0 | the Milky Way's dust lanes, star clouds, its warm core and cooler arms (read only inside the band). Since 2026-11-08 |
| `afterglow`, `belt_colour` | 0, rose | the twilight's band over the sunset, and opposite it the Earth's shadow with the belt of Venus over it. Since 2026-11-08 |
| `evening_star` | 0 | a bright planet over the sunset's glow (6 degrees to its left, 11 up), bright in the twilight as the stars are not. Since 2026-11-08 |
| `clouds` | 0 | how much of the sky the clouds cover. Live, a brightness |
| `cloud_colour` | dark grey | the clouds' own colour. Live (bind it to `film.colour` with a `strength`) |
| `cloud_screen` | 1 | how much the clouds towards the screen catch its light, in the picture's colour. Live, a brightness |
| `wind`, `wind_from` | 0.3, 270 | how fast the clouds drift (motion, at most 1), and from where |
| `aurora` | 0 | an aurora's brightness. Live, a brightness (bind it to `film.quiet`, smoothed) |
| `aurora_low`, `aurora_high`, `aurora_bearing`, `aurora_speed` | green, violet, 0, 0.4 | its colours low and high, where it hangs, how fast its curtains wave (motion, at most 1) |
| `meteors` | 0 | shooting stars an hour, at random (0..30) |
| `earth`, `earth_bearing`, `earth_altitude`, `earth_size`, `earth_phase` | off, 180, 35, 2, 0.65 | Earth in the sky: where, how high, how big (degrees), how much of it is lit |
| `earth_angle` | 0 | how far Earth has turned on its axis (degrees). Live: a track can turn it over the film |
| `earth_turn` | 1 | Earth's own turning in times its real speed (motion, at most 60: once in 24 minutes) |
| `earth_detail` | off | Earth as itself (`shaders/env_sky_earth_detail.gdshader`, since 2026-11-08 for the Crater): the continents, deserts, ice and cities from a small map drawn from coarse outlines (`kit/earth_map.gd`, 512 x 256, made once), the coasts broken by noise, cloud bands by latitude, the sun's glint on the sea, a terminator with rosy clouds, the cities' lights on the night side, a thin blue atmosphere round the limb (each pixel finds the ball itself, so the limb is exact). It turns west to east. Off: the plain Earth-like world as before |
| `earth_light_angle` | 0 | where the sunlight comes from round Earth's face, degrees from its right (90 above, -90 below) |
| `earth_lights` | 1 | `earth_detail`: the cities' lights. Live, a brightness |
| `moon` | 0 | the Moon seen from the Earth (`mode` `sky`): its brightness. Live, a brightness. 0 draws nothing (the layer is made only when it is over 0) |
| `moon_bearing`, `moon_altitude`, `moon_size`, `moon_phase` | 220, 45, 1.6, 0.22 | where it hangs, how high, how big (degrees; the real Moon is 0.5, drawn larger as the eye sees it low), how much of it is lit (0.22: a crescent). It is lit from the sunset's side (`glow_bearing`), the dark part a faint earthshine; a halo round it; clouds dim it |
| `cloud_glow`, `cloud_glow_level` | warm orange, 0 | a town's lamps lighting the clouds from below, strongest low over the walls; a silver edge near the Moon. Live, a brightness |

Action: `shooting_star` (no args).

- **The stars** are real. `app/environments/sky/bright_stars.json` holds 395 bright stars (their positions, magnitudes
  and colours) and the stick figures of 49 constellations, from the public-domain catalogue (`app/environments/CREDITS.md`).
  The faint stars are generated, more of them along the Milky Way, the same each time. The local sidereal time comes
  from the day and the hour; the stars stand where they would for the latitude. The test checks Polaris at the
  latitude's height in the north, Betelgeuse high in the south on a January midnight, Vega near the zenith on a July
  night.
- **Each star** is a small soft disc, its brightness by magnitude, its colour by its colour index. The twilight, the
  clouds and the air near the horizon hide the faint ones first.
- **The Milky Way** lies where the galaxy really is (the galactic frame), brighter towards the centre, with the dark
  rift through Cygnus and Aquila. To show it as the lights dim: `{"bind": "playback.playing", "range": [0.2, 0.9],
  "smooth": 3}`.
- **Clouds** drift with the wind. Their own colour can follow the film (`film.colour` with a `strength`). The clouds
  towards the screen also catch its spill in the picture's colour (the bias light), as the room's surfaces do.
- **The aurora** hangs over its bearing: curtains with rays, green low and violet high. `{"bind": "film.quiet",
  "range": [0, 1], "smooth": 2}` makes it swell in quiet scenes and fade slowly after.
- **Dusk to stars over the film:** a film-time track, `{"target": "sky.dusk", "by": "film.minutes", "keys": [[0, 0],
  [10, 1]], "smooth": 0.5}`. Away from the sunset the horizon is duller and cooler, as the Earth's shadow rises there.
- **Earth** (from the Moon: `mode` `space`) is lit from the side by its phase. Oceans, land, ice and clouds come from
  the sky's noise: an Earth-like world, not a map. Only its surface turns; it stays where it hangs.
- **Where it is drawn:** every layer round the camera, at 175 to 190 m (the camera's far plane is 200), so walls, the
  screen and the vista always stand in front of it. Its meshes have their vertices there too, so the sight-line check
  never sees them near the seats. They are out of the lightmap bake.
- **Comfort:** the horizon never moves. Clouds, the aurora's curtains and Earth's turning are `motion` parameters (the
  Motion setting scales them). A change of `hour` turns the stars slowly, never in a jump: an hour of sky a minute at
  most.
- **For the vista:** `sky_light()` gives the sky's colours overhead and at the horizon now.
- **For water:** `moon_shine()` gives where the Moon is and how bright its road on water is now (`passing.md`, "The
  shaders"): `moon`, less for the air low down as the Moon's own shader dims it, times `moon_phase`, and 0.3 of that
  under a sky still light (`MOON_ROAD_IN_TWILIGHT`), rising to all of it as `dusk` goes to 1. Nothing without a Moon.

Measured (`test_env_sky.gd`): the dome, the stars (395 and 1600 faint) and the lines: 3 draws, 7 842 triangles, 0.3
MB (the shared noise, 256 x 256). With Earth: 4 draws, under 9 000 triangles.

### `vista`

`scripts/env/systems/vista.gd`. Far scenery round the room, made from simple shapes in code, never from a file.

| Parameter | Default | What |
|---|---|---|
| `items` | `[{"shape": "hills"}]` | up to 12 pieces of scenery: `{shape, azimuth, spread, distance, depth, size, count, seed, floor_y, colour}`; a shape's own defaults fill what an item leaves out |
| `sky_light` | true | lit by the room's `sky` system (its colours overhead and at the horizon, each frame) |
| `light` | dark blue | the light on the scenery without a sky system. Live |
| `spill` | 1 | how much the near scenery catches the screen's light |
| `floodlight`, `flood_colour` | 1, warm | the floodlights on the acropolis's stone. Live, a brightness |
| `town_lights` | 0.6 | the lamps of the town under the acropolis. Live, a brightness |
| `pool_glow`, `pool_colour` | 1, cyan | the pool's underwater lights. Live, a brightness |
| `snow` | 1 | snow on the ground under the trees. Live, a brightness |
| `frost` | 0 | birches in hoar frost: finer twigs, more of them, pale with rime against the sky, a few drooping strands from each branch (since 2026-11-08, the Palace of Culture's) |
| `room_glow`, `room_glow_level`, `room_glow_at` | black, 0, [0, 10, 0] | the room's own light thrown up on the scenery near it (an opening in its roof): its colour, a brightness (live: a cue takes it down with the house lights) and where it comes out, in the room's frame |
| `water_motion` | 0.5 | how fast the light ripples in the pool (motion, at most 1) |

| Shape | Default | What |
|---|---|---|
| `hills` | all round, 160 m | a low dark ridge on the horizon |
| `mesas` | 140 degrees, 165 m, 6 | flat-topped rocks with steep sides |
| `acropolis` | 18 degrees, 150 m, 160 lamps | a hill with a flat top and a wall, a ruined temple of columns and a smaller one, floodlit from below; a town's lamps at its foot |
| `birches` | 120 degrees, 40 m, 40 trees | white trunks with dark marks and bare branches, on snow |
| `cypresses` | 90 degrees, 30 m, 14 trees | tall, narrow, flame-shaped dark trees |
| `pool` | 14 m | a pool glowing from below, its coping, a lawn that takes its glow, a hedge behind |
| `cacti` | 60 degrees, 70 m, 16 plants | desert silhouettes: saguaros with their arms, yucca trees (forked, tufted), low tufts of scrub (since 2026-11-08, the drive-in) |

- **Placing:** `azimuth` is degrees from the room's front (positive to the right), `distance` metres from the room's
  middle (at most 170), `spread` the degrees of the horizon it covers, `depth` how deep a grove is.
- **One draw** for all the scenery: one mesh, each vertex naming its material. Unshaded: lit by the sky's light by
  the way a face looks (up or out), the screen's spill where it is near, the floodlights, the lamps and the pool.
- **The grounds** (under the trees, the pool's lawn) keep 8 m clear of the room's middle: the room's own floor is
  there.
- **Nothing moves** but the light in the pool.

Measured (`test_env_vista.gd`), each shape at its defaults: hills 720 triangles, mesas 934, the acropolis 1 112,
birches 1 828 (about 45 a tree), cypresses 1 176 (84 a tree), the pool 36. All six: 1 draw, 5 806 triangles.

### The film layer

The sky and the vista are far behind the screen and round the room. Nothing of theirs is between the eyes and the
picture, so the film layer (`scripts/play/film_layer.gd`) needs no change for them: where the picture is, the layer
covers them, as the screen would.

### For the rooms

| Room | Use |
|---|---|
| Atmospheric 1928 | `auditorium` with `ceiling_cover` 0; `sky` at a deep blue dusk (`dusk` 0.45, 0.85 in the film), `lines` off, `twinkle` 0.35, a crescent `moon`, clouds lit from below by the town (`cloud_glow`) with `cloud_colour` bound to `film.colour`; the trees over the walls are the kit's (`cypress`, `palm`, `pine`), no `vista` |
| Drive-in 1958 | `sky` with a dusk track by `film.minutes`, `milky_way` bound to `playback.playing`; `vista` mesas all round |
| Rooftop, Athens | `sky` (`latitude` 38, a summer night); `vista` acropolis ahead, a little to one side |
| Palace of Culture | `sky` a January night at latitude 56, `clouds` by the Snow setting, `cloud_glow` warm from the hall; `vista` birches in hoar frost round the roof light (`frost` 1, `room_glow` warm, down for the film by the cues), `snow` bound to the Snow setting |
| Reclaimed | `sky` through the open roof: stars, `clouds` bound to `weather.wet` |
| Ice cinema | `sky` (68 degrees north, a January night, the Moon low in the south-east): `aurora` from the Aurora setting, up for the pre-show and in quiet scenes by cues, `aurora_bearing` over the window and the left skylights |
| Crater | `sky` `mode` `space`, `earth` and `earth_detail` on, `earth_turn` from the Earth's speed setting, `milky_way` bound to `playback.playing`, `milky_detail` 1 |
| Screening room 1962 | `vista` pool behind the window, `pool_glow` 1 |
