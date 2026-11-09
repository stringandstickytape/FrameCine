# Cinema

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

`app/environments/cinema.env.json` with `cinema.tscn` and a thin `cinema.gd`. It looks the same: the render test
(`tests/test_env_cinema_render.gd`, lavapipe) draws the old cinema (`tests/fixtures/cinema_v3.gd`, the room as code
before the conversion) and the new from the seat and from the aisle and compares them pixel by pixel. The bake hooks
(`static_meshes`, `bake_lights`, `set_baking`, `set_baked`) come from the light system, so the headset's bake path is
as before. Settings: the pre-show ritual (common), the house lights in the film. Sound: the ritual's chime as it was
(a cue's `sound` step at -6 dB, -46.2 dBFS RMS at the slider's default), and the hall's `acoustics` (`cinema`, rt60
0.7) on the room's bus; the film keeps its own mix.
