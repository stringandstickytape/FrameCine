# Atmosphere and weather

Part of the environments engine: [`docs/environments.md`](../environments.md) has the design and says where each part is.

Two systems of kind `atmosphere`. Both are cheap: shader cards and GPU particles, no volumetric fog, no depth texture,
no live light. Neither makes a sound. Neither moves the viewer.

### `atmosphere`

`scripts/env/systems/atmosphere.gd`. The room's air. Each part is built only when the document gives it (a value over
0, or a binding), so a room pays only for what it uses.

| Parameter | Default | What |
|---|---|---|
| `beam_haze` | 0 | haze in the projector's beam. Live, a brightness |
| `beam_dust` | 0 | dust motes that twinkle in the beam. Live, a brightness |
| `beam_smoke` | 0 | the haze billows into slow rising smoke. Live, a brightness |
| `beam_colour` | warm white | the beam's light. Live (it can follow `film.colour`) |
| `follow_picture` | true | the haze takes the picture's colour and brightness from the bias light |
| `lens` | null | the beam's lens; null: the `screen_frame` system's (else the cinema's booth) |
| `fog` | 0 | ground fog or mist: how thick. Live (it can follow `weather.wet`: mist after rain) |
| `fog_height`, `fog_center`, `fog_size`, `fog_layers`, `fog_speed`, `fog_walls`, `fog_colour` | 0.6 m, the origin, 16 x 16 m, 4, 0.3, false, pale grey | the fog's reach, place, size, layers (one draw each), drift, edges and colour |
| `breath` | 0 | breath fog in a cold room: how much a puff shows. Live |
| `breath_seconds`, `breath_colour` | 5 s, pale blue-white | seconds between puffs (each a little more or less) and the colour |

- **The haze** (`shaders/env_haze_beam.gdshader`) is a beam-shaped volume: the cone's four sides from the lens to the
  screen's corners, and a cross of two planes through its axis. Each surface samples a slowly drifting noise field.
  It is drawn additively. It is brightest near the lens and gone before the screen, so the picture stays clean. It
  shows while the `screen_frame` beam would: a flat film playing, not the projector feature's own beam. It is
  stronger as the house lights go down. `beam_haze` can also follow `film.brightness`, and `beam_colour`
  `film.colour`.
- **The fog** is the assistant room's fog (`shaders/room_fog.gdshader`): soft layers up to `fog_height`, denser low
  down. Low and thick is ground fog; high and thin is mist.
- **Breath** (`shaders/env_haze_breath.gdshader`, 16 GPU particles): now and then a puff starts 14 cm under the eyes
  and 10 cm ahead, drifts forward and down, and fades in 2.4 s. It never rises to the eyes' level: its top stays more
  than 20 degrees under the eye line (the test checks it), so it never hides the screen. The puff follows the head's
  turn, not its tilt.

Measured (`test_env_atmosphere.gd`): beam, four fog layers and breath: 6 draws, 14 triangles, 16 particles.

### `weather`

`scripts/env/systems/weather.gd`.

| Parameter | Default | What |
|---|---|---|
| `mode` | `changing` | `clear`, `light` (a drizzle or flurries), `heavy` (rain or snow), or `changing`: the cycle. Live |
| `falls` | `rain` | `rain` or `snow` (built once) |
| `intensity` | 1 | how much falls at the heaviest. Live |
| `cycle_minutes`, `cycle_start` | 24, 0.3 | the cycle's length, and where in it the room starts |
| `change_seconds`, `dry_minutes` | 40, 4 | how long a change of weather takes; how long the wet takes to dry |
| `areas` | none | up to 3 boxes `{min, max}` the rain or snow falls through, top to floor: an open roof, the view outside a window |
| `particles` | 1200 | drops or flakes over all the areas, shared by their floor area (the room's budget is 4000) |
| `wind`, `colour` | 0.2 m/s along x, pale blue-grey | the drift; the drops' colour (lit by the room and the film) |
| `pane`, `pane_center`, `pane_size`, `pane_yaw` | off | drops on a window pane |
| `puddle`, `puddle_center`, `puddle_size`, `puddle_reflect` | off | a puddle on the floor that reflects the film; `puddle_reflect` is live |

Actions: `shower` (args `seconds`, `amount`: a passing shower whatever the mode) and `clear_up` (args `seconds`: the
rain eases off now and holds off).

- **The cycle:** clear, drizzle, rain, clearing, clear, over `cycle_minutes`. The amount eases to its target over
  `change_seconds`, so a change of mode is never sudden. The wet follows the rain and dries over `dry_minutes`.
- **The state:** `weather_state()` is `clear`, `drizzle`, `rain` or `clearing` (snow: `clear`, `flurries`, `snow`,
  `clearing`). The signal `weather_changed(state)` fires on a change.
- **For other systems and cues:** the weather writes the channels `weather.rain`, `weather.snow` and `weather.wet`
  into the host's signals each frame. A sound bed follows them by a binding (rain on glass:
  `{"bind": "weather.rain", "smooth": 1}`; drips on leaves: `weather.wet`). A cue can wait for them:
  `{"when": {"signal": "weather.rain", "above": 0.5}}`. Without a weather system they read 0. The methods
  `rain_amount()`, `snow_amount()`, `wet_amount()` give the same.
- **Falling** (`shaders/env_rain_fall.gdshader`): GPU particles, one emitter per area. A drop is a thin upright streak;
  a flake a soft disc that sways. The share that shows follows the amount (`amount_ratio`), so the particle count
  never rises over the declared one.
- **The pane** (`shaders/env_rain_pane.gdshader`): beads that come and go while it rains and stay a while after, and
  drops that run down in wavering paths with trails. All procedural; no screen texture.
- **The puddle** (`shaders/env_rain_puddle.gdshader`): dark water with a ragged edge, and in it the part of the picture a
  mirror there would show (the screen's own uniforms, copied each frame as the floor reflection does). Rings spread
  where drops land while it rains. With no film it takes the film's colours from the bias light.
- **Turning it off:** a room setting mapped onto `mode`, for example
  `{"bind": "setting.weather", "map": {"changing": "changing", "rain": "heavy", "clear": "clear"}}`.

Measured (`test_env_weather.gd`, a hall with half its ceiling open): two areas, a pane and a puddle, 1500 drops: 4
draws, 4 triangles, 1500 particles. The hall and the weather together: 24 draws.

### The film layer

On the Frame the film is an OpenXR layer drawn over everything between the eyes and the picture
(`scripts/play/film_layer.gd`). Haze, rain or fog in front of the picture is hidden there; around the picture it
shows. These systems do not make the layer step aside: it would cost the layer's sharpness for the whole film. The
choice keeps the picture clean, which is also why the haze fades out before the screen. What is drawn: the beam above
and round the picture, rain in the room and outside windows, the puddle on the floor (it lies below the picture as
seen from any seat), breath under the eye line. On the desktop, and with the layer off, rain in front of the picture
shows over it.

### For the rooms

| Room | Use |
|---|---|
| Shopfront 1906 | `atmosphere`: `beam_haze` 0.4, `beam_dust` 0.7 |
| Screen 3, 1983 | `atmosphere`: `beam_haze` 0.6, `beam_smoke` 0.8 |
| Palace of Culture | `weather`: `falls` snow, `mode` heavy or light, an area outside the windows |
| Reclaimed | `weather`: `mode` from the Weather setting, an area under the open roof, `puddle` in front of the screen; `atmosphere.fog` bound to `weather.wet` for mist after rain |
| Ice cinema | `atmosphere`: `breath` 0.6, a little low `fog`; `weather`: `falls` snow, `mode` light, 260 flakes in two areas outside (the doorway's and the window's) |
| Pillow Fort | `weather`: `pane` on the window, `mode` light or changing, no areas (or one outside the window) |
