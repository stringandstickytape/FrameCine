# The environments engine

An environment is **data over trusted systems**. A room is a version 4 room document. The document names systems
from a **registry** and gives them parameters. The systems are GDScript in the app, reviewed like the rest of the
code. A document never holds code: no expressions, no scripts, no shaders. Everything a document can say is checked
against the registry before anything is built.

This file is the design. The agents that build the systems and the rooms are briefed from it. D30 in
`docs/decisions.md` is the decision.

## The pieces

```
 room document (JSON, version 4)
   room, screen, acoustics, audio          the room as a whole
   systems: [{system, id, params}]         ---> registry (scripts/env/systems/registry.gd) ---> system scripts
   settings: [{name, type, ...}]           ---> room settings (scripts/env/room_settings.gd) ---> the Room tab
   cues, timeline                          ---> timeline (scripts/env/env_timeline.gd)
   parts, seats, sky, ...                  the version 3 keys, as before (objects, materials, pictures)

 env_room.gd (the environment node)  builds  env_host.gd ("Systems": the systems, the signals, the timeline)
 film signals (scripts/env/env_signals.gd)   film.colour, film.bass, ...  --->  bindings on system parameters
 audio buses (scripts/env/env_audio.gd)      Film, Environment (ducked under Film), Interface
 checks (scripts/env/env_checks.gd)          schema, headset budget, sight line, comfort, licences, names, no people
```

- `app/environments/<id>.env.json` is a room that ships. `app/environments/<id>.tscn` holds only the node: its
  script is `env_room.gd` (or a thin script that extends it, as `cinema.gd`) and its `document` path.
- An assistant can send a version 4 document too (`docs/assistant.md`, "Rooms from systems"). It is built on its
  base room like any assistant's room, with the systems added.

## The version 4 document

Version 4 is version 3 (`docs/assistant.md`, "The room document") with sections for the systems. Versions 1 to 3 are
still read, without change. Every key of version 3 keeps its meaning.

```json
{"schema": 4,
 "name": "Cinema",
 "room": {"ambient": 0.05, "screen_glow": 1.0, "curtains": true},
 "screen": {"center": [0, 1.6, -13.8], "size": [12.0, 5.0]},
 "acoustics": {"reflect": [0.3, 0.3, 0.25, 0.35, 0.2, 0.3], "rt60": 0.7, "wet": 0.55},
 "systems": [
   {"system": "light", "params": {"house_lamps": 1.0}},
   {"system": "auditorium", "id": "hall", "params": {"rows_front": 7, "rows_back": 3}},
   {"system": "screen_frame"},
   {"system": "showing"}],
 "settings": [
   {"name": "house_level", "type": "range", "min": 0.0, "max": 0.6, "step": 0.05, "default": 0.12,
    "format": "percent", "label": "House lights in the film",
    "description": "How bright the house lights stay while the film plays."}],
 "cues": [{"name": "ritual", "when": {"state": "starting"}, "requires": [{"setting": "ritual"}],
           "steps": [{"do": "showing.open_curtains", "args": {"seconds": 5}},
                     {"set": "light.house_lamps", "to": 0.0, "seconds": 6}]}],
 "timeline": {"starting_seconds": 8, "credits_minutes": 6},
 "audio": {"level_db": 0.0, "pause_rise_db": 3.0}}
```

| Key | What |
|---|---|
| `schema` | 4 |
| `name` | the room's name; a room that ships has its name as a translation key |
| `room` | the room as a whole: `ambient` (0..1, its surfaces' light with a dark screen), `screen_glow` (0..2), `curtains` (the pre-show's curtains may close here), `reacts_to_film` (the film's transients may flash the light), `reflection` (the floor reflection's default here), `reflection_floor` (its height; null: none) and `category` (where the Room tab lists it: `cinema` under Cinemas, `tv` under Television, `other` with the other rooms, the default; `env_library.gd category_of()`) and `description` (a line about the room under the Room tab's "This room", at most 200 characters; a key, so a room that ships translates it) |
| `screen` | as version 3: the default screen's `center` and `size` |
| `acoustics` | the room's sound for spatial audio (`get_sound_room()`, `scripts/play/spatial_audio.gd`): `box` ({min, max}; default: the builder's walls), `reflect`, `rt60`, `wet`, `surround_height`, `array`, `array_spacing`, `ring`, `distance` |
| `systems` | the systems, in build order: `{system, id, params}`. `id` defaults to the system's name; two of one system need their own ids. Cues and bindings address a parameter as `<id>.<param>` |
| `settings` | the room's own settings (below, "Room settings") |
| `cues` | sequences the timeline runs (below, "Timeline and cues") |
| `timeline` | `starting_seconds`, `credits_minutes`, `tracks` (film-time tracks) |
| `audio` | `level_db` (the room's sounds against the Environment bus, -24..6), `pause_rise_db` (0..6: how much the ambience rises while paused or in the pre-show) |
| `credits` | every bundled asset the room uses that is not a library material or object: `{asset, title, source, licence}` (licence CC0 only) |
| `parts`, `seats`, `sky`, `light`, `lights`, `atmosphere`, `recolour`, `default_seat` | version 3, unchanged |

Validation: `room_schema.gd validate()` reads a version 4 document as version 3 and hands the new sections to
`scripts/env/env_doc.gd`. Every problem comes back with its JSON path, as before:
`{"path": "$.systems[1].params.rows_front", "error": "at most 30"}`.

## Systems and the registry

`scripts/env/systems/registry.gd` maps a name to a script. A system is a `Node` that extends
`scripts/env/systems/env_system.gd`.

### What a system declares

```gdscript
static func spec() -> Dictionary:
	return {
		"name": "auditorium",
		"kind": "builder",          # builder, kit, light, sky, atmosphere, life, sound, music, screen, seats,
		                            # motion, showing (the table below)
		"description": "Stadium rows on a rake, ...",
		"params": {
			"rows_front": {"type": "int", "min": 0, "max": 30, "default": 7,
					"description": "rows in front of the viewer's own"},
			"house_lamps": {"type": "float", "min": 0.0, "max": 1.0, "default": 1.0, "live": true,
					"brightness": true, "description": "the house lights' glow"},
		},
		"actions": {"open_curtains": "the curtains part (args: seconds)"},
		"cost": {"draws": 18, "triangles": 120000, "lights": 0, "particles": 0, "texture_mb": 40},
		"provides": ["seats", "collision", "bake", "sound_room"],
		"requires": ["light"],
	}
```

- **Parameter types:** `float`, `int` (with `min` and `max`), `bool`, `color` (`"#rrggbb"` or `[r, g, b]`),
  `enum` (`values`), `vec2`, `vec3`, `string` (`max`), `list` (`of`: an element's spec, `max`), `material` (a
  library material: `{library, color, tiling, ...}`), `object` (`fields`: a spec per field).
- **`live`:** the parameter can change while the room shows. Only a live parameter can follow a film signal or be
  moved by a cue. A setting bound to a parameter that is not live makes the system build again (geometry).
- **`brightness`:** the parameter changes how bright something is. The comfort check keeps every change to it under
  the photosensitivity ceiling (`room_schema.gd MAX_HZ`).
- **`motion`:** `{"max": x}` on a parameter that moves something the viewer sees (a sway, a tilt, gate weave): the
  comfort check holds it to that limit, and the room's Motion setting scales it.
- **`cost`:** an estimate, for the assistant. The budget check measures the built room.
- **The assistant's schema and the docs come from the registry:** the `room_systems` command lists every spec.

### What a system does

```gdscript
var host      # env_host.gd: signals, timeline, the room's settings, other systems (host.system(id))
var room      # the environment node it builds into (env_room.gd, or an assistant's room)
var id        # its id in the document
var params    # its parameters, defaults filled in, bindings at their current values

func setup() -> void                      # build: add nodes to the room with own(node)
func set_param(name, value) -> void       # a live parameter changed (a binding, a cue, a setting)
func act(action, args) -> void            # a cue's "do"
func tick(delta) -> void                  # every frame the room shows
func on_state(state, previous) -> void    # the timeline's state changed
func on_screen_changed(local: Transform3D, size: Vector2) -> void
# Optional hooks, each used when the system provides it:
func seats() -> Array[Transform3D]        # floor points under the seated eyes, facing -Z
func collision_shapes() -> Array          # [[Shape3D, Transform3D]] for object physics
func sound_room() -> Dictionary           # walls for spatial audio
func static_meshes(), bake_lights(), set_baking(on), set_baked(on)   # the lightmap bake (light systems)
```

A system never reads a file a document names, never loads a script and never evaluates text. It reads its own
parameters only.

`own(node)` keeps node names steady when a room has two systems of one kind (two kits, two builders): a name the room
already has takes the system's id after it (the second kit's `PieceStatic` is `PieceStatic_furniture`), never the
engine's `@...@` name, and the node keeps its plain name in the meta `env_name`. A motion system's `node` finds a
system's node by either name. Tested in `test_env_kit.gd` (two kits in one room).

### The systems

| System | Kind | Role | State |
|---|---|---|---|
| `light` | light | the house materials (the library on the house shader: fill, the film's spill, stand-in lamps before a bake), the lamp glows by group (house, steps, stage, signs), the hidden bake lights, the bake hooks. The screen is the main light: every lit surface takes the film's spill | built |
| `auditorium` | builder | stadium rows on a rake, seats, aisles, side walls and panels, proscenium and screen wall, ceiling, step and house lights, curved rows, balcony, boxes, open ceiling, a partition wall | built |
| `screen_frame` | screen | the black masking round the screen, the projector's beam from a lens | built |
| `showing` | showing | the curtains' part in the ritual: actions `open_curtains`, `close_curtains` (the pre-show's curtains, `scripts/env/preshow.gd`) | built |
| `mirror_floor` | builder | a black floor that takes the film's reflection, a ripple where the viewer moves | built |
| `shopfront`, `nave`, `dome_hall`, `terrace`, `domestic`, `vehicle` | builder | the other parametric structures (shopfront hall, nave, dome, open-air terrace or lot, domestic room, vehicle interior; below, "The builders") | built |
| `kit` | kit | modular pieces placed along a builder's slots (balcony fronts, niches, columns, façades; below, "The kit") | built |
| objects, materials, pictures | | as now: `parts` placements, library materials, pictures (an assistant's room). A shipped room's things are kit pieces (below, "The kit"): the kit builds them on the house shader, lit as the room is, and its pieces are original, so a document room places no library objects | as now |
| `sky`, `vista` | sky | a sky dome (twilight to night, the real stars and constellations, the Milky Way, clouds lit by the screen, an aurora, Earth from the Moon), far scenery from simple shapes (hills, mesas, a floodlit acropolis, birches in snow, cypresses, a glowing pool); below, "The sky and the vista" | built |
| `atmosphere`, `weather` | atmosphere | haze, dust and smoke in the beam, ground fog and mist, breath; rain and snow through open roofs and outside windows, rain on a pane, a puddle that reflects the film, a weather cycle (below, "Atmosphere and weather") | built |
| `life` | life | non-human ambient life: moths, birds, fish, fireflies, a cat, a deer, glowing deep-sea creatures, a whale, plane lights. Never people (below, "Ambient life") | built |
| `sound_bed`, `acoustics` | sound | looped beds and one-shots from our own synthesiser, placed in the room, on the Environment bus; the room's reverb (below, "Sound and music") | built |
| `music` | music | instruments that play themselves (a player piano, an organ), from our own synthesiser | built |
| timeline and cues | | below; part of the host, not a registered system | built |
| film signals | | below; part of the host | built |
| `presentation` | screen | the chain of stages from source to display: source (film, tape, broadcast), transmission (aerial noise, ghosting), display (CRT, mask, curvature, a telly's glass), the sound through a small speaker. TV-era presets | built |
| `seats` | seats | seat models outside the builders (folding chairs, plush tip-up seats, multiplex seats and a broken one, pews, club chairs, director's chairs, a bench seat, cushions, hides, a bean bag), drawn in the builders' seat slots, in rows of its own, or as broken seats over a builder's own | built |
| `motion` | motion | slow moves of the room's things (a curtain's sway, an organ rising, a painting sliding up, a festoon rising in swags, Earth turning), held to the comfort limits. Never the viewer | built |

## Bindings and film signals

A live parameter can follow a channel. The binding is data:

```json
"house_lamps": {"bind": "film.brightness", "range": [0.2, 1.0], "smooth": 0.5}
```

| Key | What |
|---|---|
| `bind` | the channel (below) |
| `range` | `[a, b]`: the channel's value (0..1) mapped onto a..b. Colours: `["#rrggbb", "#rrggbb"]` |
| `keys` | `[[x, y], ...]`: a piecewise-linear curve on the channel's raw value (film-time: `film.minutes`) |
| `map` | `{value: result}`: for a choice setting, `playback.state`, a bool (`"true"`, `"false"`) |
| `smooth` | seconds: the time constant of a low-pass on the result |
| `invert` | `true`: 1 - the value, before `range` |
| `strength` | for `film.colour` on a colour: how far the colour goes from `base` towards the film's (0..1) |
| `base` | the colour `strength` starts from |

One of `range`, `keys` and `map`, or none (the value as it is). A binding is checked against the parameter's type
and range: a binding whose range leaves the parameter's range is refused.

| Channel | What | Range |
|---|---|---|
| `film.colour` | the picture's dominant colour: the mean of the bias light's 4 x 2 copy of the video planes (`scripts/env/bias_light.gd`), read back without a stall | colour |
| `film.brightness` | the luminance of that colour | 0..1 |
| `film.bass` | the low end (20-120 Hz) between `film_react.gd`'s floor and full levels; available with `[react]` off (the analyser runs while a room asks for it) | 0..1 |
| `film.transient` | a sudden loud jump: 1 at the jump, falling to 0 over 0.5 s | 0..1 |
| `film.quiet` | low sound energy (under -38 dBFS) and little picture change, held for 3 s; falls at once when either ends | 0..1 |
| `film.progress` | position over duration | 0..1 |
| `film.minutes` | position in minutes | raw |
| `time.of_day` | daylight from the time of day (`scripts/env/time_of_day.gd`): 0 at -12 degrees of sun, 1 at +12 | 0..1 |
| `playback.state` | the timeline's state (`map` it) | a name |
| `playback.playing` | 1 while playing | 0..1 |
| `setting.<name>` | a room setting: a range normalised over its own range, a bool 0 or 1, a choice by `map` | 0..1 |
| `comfort.motion` | the room's Motion setting | 0..1 |
| `weather.rain`, `weather.snow` | what falls now (the weather system; 0 without one) | 0..1 |
| `weather.wet` | how wet the room is: it follows the rain and dries slowly after it | 0..1 |

Tests feed the channels with `signals.fake(channel, value)`.

## Timeline and cues

### States

| State | When |
|---|---|
| `preshow` | nothing open, or a film open at its start and not started |
| `starting` | the first `starting_seconds` (default 8) after a film starts from its start |
| `playing` | playing |
| `paused` | paused after it started |
| `intermission` | `scripts/play/intermission.gd` is active |
| `credits` | the last `credits_minutes` (default 6, at most a tenth of the film) of a film over 20 minutes |
| `ended` | the film ended, until the next play or file |

The states come from playback: the player's `ended` signal, the intermission's `active`, the position and duration.
The pre-show's curtains (`preshow.gd`) close at the end as before; in a room whose cue opens them (`showing`), the
pre-show waits up to 4 s for the cue before it opens them itself.

### Cues

```json
{"name": "whale", "when": {"signal": "film.quiet", "above": 0.9, "for": 4},
 "states": ["playing"], "chance": 0.5, "cooldown": 900,
 "steps": [{"do": "whale.pass", "args": {"side": "left"}}]}
```

`whale.pass` is the action `pass` of the system with the id `whale` (a `life` system whose creature is the whale). The
whale sings as it passes, so the cue needs no `sound` step.

| Key | What |
|---|---|
| `name` | the cue's name |
| `when` | the trigger: `{"state": "starting"}` or a list of states (on entering one); `{"signal": "<channel>", "above" or "below": x, "for": seconds}` (once each time it crosses); `{"every": seconds}` |
| `requires` | `[{"setting": "<name>", "is": value}]`: settings that must hold (`is` left out: the setting is on). The common `ritual` setting is one |
| `states` | the states it may fire in |
| `chance` | 0..1, rolled each time it would fire |
| `cooldown` | seconds before it may fire again (the whale: at most once in 15 minutes) |
| `stop_in` | states that stop it while it runs: `["playing"]` stops a slow pre-show cue when the film starts. Its later steps don't run; what it set stays until a `release` or another cue |
| `steps` | run in order: `{"set": "<id>.<param>", "to": v, "seconds": s, "ease": "linear" or "in" or "out" or "in_out"}` (starts a fade and goes on), `{"wait": s}`, `{"release": "<id>.<param>", "seconds": s}` (back to its base value or binding), `{"do": "<id>.<action>", "args": {...}}`, `{"sound": "<synth>", "gain_db": g, "at": [x, y, z]}`, `{"stop": "<cue>"}` (stops another cue of the room while it runs) |

A cue's `set` holds the parameter until a `release`; a binding on the same parameter waits under it. A cue does not
start again while it runs.

### Film-time tracks

```json
"timeline": {"tracks": [{"target": "sky.dusk", "by": "film.minutes", "keys": [[0, 0.0], [10, 1.0]]},
                        {"target": "sky.stars", "by": "film.progress", "keys": [[0.05, 0.0], [0.3, 1.0]]}]}
```

A track is a binding on a live parameter by `film.minutes` or `film.progress`: dusk falling over the first 10 minutes,
the stars coming out.

### The ritual in the converted cinema

`ritual` (a cue of `cinema.env.json`): when the film starts from its start, a soft chime from the synthesiser plays
on the Environment bus near the stage, the house lamps come down to half over 1.5 s, the curtains part over 3.5 s,
and after 2 s the lamps go down to the room's "House lights in the film" setting (20 % by default) over 5 s. The
room light dims as before (light follows playback). In the pre-show and after the end (`lights_up`) the lamps come
back up over 4 s. With the common "Pre-show" setting off there are no curtains and `dim` takes the lamps down over
3 s instead. A change to the House lights setting during the film moves the lamps at once (a cue held at a setting's
value follows it).

## Room settings

Every room has settings: the common ones from the shared systems, and the room's own from its document.

### Common settings

| Name | Type | Default | What |
|---|---|---|---|
| `dim` | bool | true | dim during the film (the room light follows playback, `light_follow.gd`) |
| `ambience_db` | range -25..6 dB | 0 | the room's ambience against the global Environment slider; -25 is off (the room's mute) |
| `life` | bool | true | ambient life on or off (rooms with a `life` system) |
| `ritual` | bool | true | the pre-show: the curtains and the ritual cue (rooms with curtains or a cue that requires it) |
| `flicker` | bool | true | lights that flicker (an exit sign, a candle): off holds them steady |
| `motion` | range 0..1 | 1 | motion comfort: scales every `motion` parameter (gate weave, a tilt, a sway) |
| the seat | | the room's own | the chosen seat, as the Seat section keeps it (`[seats] <id>`); Back to defaults goes back to the room's own seat |

A common setting shows where it has an effect: `life` with a `life` system, `ritual` with curtains or a cue that
requires it, `flicker` with a parameter that flickers, `motion` with a `motion` parameter.

### A room's own settings

```json
"settings": [
  {"name": "weather", "type": "choice", "choices": ["rain", "mist", "clear", "changing"],
   "labels": ["Rain", "Mist", "Clear", "Changing"], "default": "changing",
   "label": "Weather", "description": "Rain on the roof, mist in the ferns, a clear night, or each in turn."}]
```

| Key | What |
|---|---|
| `name` | its id: lower-case letters, digits and _ |
| `type` | `bool`, `range` (`min`, `max`, `step`, `format`: `percent`, `db`, `seconds`, `minutes`, `times`, `number`), `choice` (`choices` and their `labels`) |
| `default` | within its range or choices |
| `label`, `description` | English; translation keys (`tools/i18n.py` reads them from `app/environments/*.env.json`) |

A setting reaches the systems through bindings: `{"bind": "setting.weather", "map": {"rain": 1.0, "clear": 0.0}}`, and
through cues' `requires`. Examples from the set:

| Room | Setting | Binding |
|---|---|---|
| Reclaimed | `weather`: rain, mist, clear, changing | `weather.mode` by `map` |
| Drive-in | `tinny`: the window speaker (bool) | `presentation.speaker` by `map` |
| Pillow Fort | `telly_fills`: the telly fills the fort's opening (bool) | `domestic.opening_screen` (not live: the fort builds again) |
| Screen 3 | `weave`: gate weave and tilt (range 0..1) | `presentation.weave` and `.tilt` by `range` |
| Bathysphere | `whale`: how often the whale comes (choice: never, rare, sometimes) | the whale cue's `chance` by `requires` per choice |
| Crater | `earth_speed`: Earth's turning speed (range 0.5..4 times) | `sky.earth_turn` by `range` |
| Cinema | `house_level`: house lights in the film (range 0..0.6) | the room light's dimmed level |
| Void | `ripple`: ripple strength (range 0..1) | `mirror_floor.ripple` by `range` |

### Storage, the menu and the assistant

- Stored as `[room:<id>] <name>` in `user://settings.cfg`, only a change from the default; back to the default
  erases the key, as elsewhere.
- The Room tab's "This room" section builds itself from the declarations: a toggle for a bool, a slider for a range,
  a row of choices for a choice, and the description under it. "Back to defaults" puts every setting of the room back.
- The assistant: `room_settings` (read) gives `this_room`: every declaration as a JSON Schema, its value and its
  default. `room_setting` (level room) sets one, or puts all back (`reset`). Both come from the same declarations.

## The audio buses

```
 Master (the Volume slider)
   Film          the player's sound: the stereo stream and the binaural renderer's mix (spatial_audio.gd)
   Environment   the room: the thud, cue sounds; ducked under Film; the Environment sound slider
     Environment room   sound beds and music, through the room's reverb (acoustics.gd)
   Interface     the pane's and the tools' sounds (the spatial tuning's tones)
```

- **The Environment sound slider** (Sound tab): off to full, default -18 dB under the film. Full is 0 dB on the
  Environment bus: a room's sounds are made at the film's reference level (-20 dBFS RMS), so the default puts them
  18 dB under it. `[audio] environment_db`.
- **The room's offset:** the common `ambience_db` setting adds to it; at -25 the room is muted.
- **Ducking:** a compressor on Environment keyed from Film (the engine's sidechain). It ducks the room by about 8 dB
  under a film at the reference level, by about 15 dB under a loud scene and not at all in silence (measured below).
- **The pause rise:** in the pre-show, while paused, in the intermission and after the end, the Environment bus rises by
  the room's `pause_rise_db` (default 3 dB) over 2 s.
- **The film's analysis** (`film_react.gd`, the music card's bars, an assistant room's loudness glows) listens to
  Film, so a room's own sound never drives them.
- **The level check:** `env_audio.gd measure_level()` plays a room's sounds for a few seconds on the Environment bus
  at the slider's default and measures the bus's RMS (`AudioEffectCapture`). `test_env_audio.gd` holds every room under
  `LEVEL_TARGET_DB` (-38 dBFS, the film's reference minus 18 dB) with 2 dB to spare.

Measured (`test_env_audio.gd`, 2026-11-07, desktop: a 220 Hz tone at -20 dBFS RMS on Environment with the bus at
0 dB, a 1 kHz tone on Film; the compressor's threshold -26 dB, ratio 1.75, attack 20 ms, release 300 ms):

| Film | Environment out | Ducked by |
|---|---|---|
| silent | -20.0 dBFS | 0 dB |
| -20 dBFS RMS (the reference) | -27.1 dBFS | 7.1 dB |
| -6 dBFS RMS (loud) | -39.3 dBFS | 19.3 dB |
| stopped again (after 1 s) | -20.1 dBFS | 0 dB |

The engine's compressor reduces by about 2.08 x (the sidechain's peak over the threshold) x (1 - 1 / ratio), much
more than its ratio suggests; the settings were chosen from these tones. The test holds the reference duck between 5
and 12 dB. The cinema's sounds (its chime) measure -46.2 dBFS RMS at the slider's default, under the -38 dBFS target.

## The checks

`scripts/env/env_checks.gd`, run by `tests/test_environments.gd` over every `app/environments/*.env.json`, and by
`tests/test_env_checks.gd` against a bad document for each check.

1. **Schema:** `RoomSchema.validate(doc, "new")`, with the version 4 sections.
2. **Headset budget:** the room is built headless and measured: draw calls (one a mesh surface), triangles, live
   lights (the bake's hidden lights do not count), particles, and texture memory (the images' bytes with mip levels).
   Texture memory is the headset's: a library map counts its ASTC blocks as loaded from its `.mtex`
   (`MaterialLibrary.FRAME_BYTES_META`), so the figure is the same headless, under lavapipe and on the Frame. Before
   2026-11-07 a rendered measure counted the maps as a GPU without ASTC holds them, decompressed (the cinema read
   144 MB under lavapipe against 9 MB on the Frame).

   | Budget | Per room | The cinema | The Void |
   |---|---|---|---|
   | draw calls | 40 | 19 | 1 |
   | triangles | 400 000 | 194 856 | 2 |
   | live lights | 2 | 0 | 0 |
   | particles | 4 000 | 0 | 0 |
   | texture memory | 96 MB | 9.0 MB | 0 |

   The budget leaves room for a sky, weather and life on top of a hall like the cinema. Measured headless
   (`test_environments.gd`); the GPU time on the Frame is the showrooms' measure (`docs/showrooms.md`).

3. **Clear sight line:** from every seat's eyes (1.2 m over its floor point) to nine points of the default screen
   (its corners, edges and centre, 5 % in), nothing static is hit: the room's meshes and seats as physics shapes, ray
   by ray. A seat's own back and anything behind the eyes do not count.
4. **Comfort:** no system moves the viewer; every `motion` parameter within its limit; every binding on a
   `brightness` parameter smoothed by at least 1 / (2 pi MAX_HZ) seconds; every cue fade on one at least
   1 / (2 MAX_HZ) seconds.
5. **Licences:** every library material the room uses is CC0 (its catalogue entry) and in `app/materials/CREDITS.md`;
   every asset in `credits` is CC0 and in `app/environments/CREDITS.md`; synthesised sounds are ours.
6. **Names:** no real mark in any text of the document (`env_checks.gd MARKS`, whole words, any case). Pastiche is
   fine; the real mark never: "Sirclive", not the computer maker's name; "FreeDTV", not the broadcast platform's.
7. **No people:** no system of a people kind, no object whose id or name says person, people, crowd, audience,
   human, mannequin or figure.

## The auditorium builder

`scripts/env/systems/auditorium.gd`. Its defaults are the cinema: the cinema's document sets only what it names.

| Parameter | Default | What |
|---|---|---|
| `room_min`, `room_max` | [-9.6, -3, -14.5], [9.6, 9, 6.2] | the hall's walls, floor of the pit, ceiling |
| `rows_front`, `rows_back` | 7, 3 | rows in front of and behind the viewer's own (row 0) |
| `row_depth`, `row_rise` | 1.3, 0.35 | the rake: each row this deep and this much higher than the one in front |
| `seats_per_row`, `seat_pitch` | 27, 0.58 | seats along a row, centre to centre |
| `row_radius` | 45 | rows curve round a point this far ahead; 0 is straight rows |
| `block_x` | 8.1 | the seats reach this far either side; the side aisles go from there to the walls |
| `seat_model` | `stadium` | the seat: `stadium` (drawn by the auditorium), or a single seat of the seats system: `plush`, `multiplex`, `folding_chair`, `club_chair`, `director`, `cushion`, `bean_bag` (set `seat_pitch` to fit) |
| `seat_upholstery`, `seat_shell` | velvet, black leather | materials |
| `seat_tint_spread` | 0.12 | how much the seats differ, one from the next |
| `wall_treatment` | `panels` | `panels` (fabric panels with wooden rails) or `plain` |
| `proscenium` | `drapes` | `drapes` (velvet either side and a valance) or `none`; slots to come: castle gate, festoon |
| `stage_depth`, `stage_top` | 1.9, -2.1 | the stage in front of the screen wall |
| `ceiling_cover` | 1 | the ceiling's share from the front; under 1 opens it to the sky (the Atmospheric, the Reclaimed's broken roof) |
| `balcony_rows` | 0 | a balcony over the rear with this many rows |
| `boxes_per_side` | 0 | boxes on the side walls |
| `partition_z` | 0 | a plain wall across the hall here (a subdivided hall, Screen 3); 0: none |
| `booth` | true | the projection booth's windows in the rear wall; `lens` is its lens |
| `doors` | true | the four exits with signs |
| materials | the cinema's | `floor`, `walls`, `front_wall`, `ceiling`, `panel_fabric`, `panel_wood`, `stage`, `curtains`, `door_leaf`, `door_metal`, `brass` |

## The seats system

`scripts/env/systems/seats.gd`. Seat models outside the builders, and the seats a room draws with them.

### The models

Each model is low-poly (boxes and rounded boxes) in its own frame: the floor point under the seated eyes at the
origin, facing -Z. Each has two library materials (CC0), `upholstery` and `frame`, with its own defaults.

| Model | Triangles | Forms | Folds away | Use |
|---|---|---|---|---|
| `stadium` | 646 | up, broken | yes | the cinema's seat (the auditorium draws it itself) |
| `folding_chair` | 148 | | yes | slatted wooden chair, 1906 |
| `plush` | 644 | up, broken | yes | velvet tip-up seat on cast standards, palaces |
| `multiplex` | 656 | up, broken | yes | moulded shell, fabric insert, cup holder, 1980s |
| `pew` | 48 a place | | no | a segment a place wide; the ends are drawn apart |
| `club_chair` | 556 | | yes | deep leather armchair |
| `director` | 188 | | yes | crossed legs, canvas seat and back |
| `bench_seat` | 384 a place | | no | a convertible's tuck-and-roll bench; side trim drawn apart |
| `cushion` | 322 | | no | a buttoned floor cushion |
| `hide` | 462 | | no | a pelt over a low block (of ice) |
| `bean_bag` | 196 | | no | a squat sack with a dent |
| `settee` | 276 a place, 106 an end | | no | a segment a place wide: the base, a seat cushion and a back cushion each; the padded arms and the feet are its ends. Two or three places in a row make a settee; its places take no tint of their own, so they match |

Forms: `up` is a tip-up seat tipped up (the hall is empty). `broken` is a seat with its back slumped and its cushion
hanging.

### Three ways in

- **The builders' seat slots.** A builder with `seat_slots()` (shopfront, nave, terrace, domestic, vehicle,
  dome_hall) draws no seats of its own when the room has a seats system. The seats system draws a seat in every slot.
  With `model` "auto" the slot's style chooses: chair: folding_chair, pew: pew, bench: bench_seat, cushion and tier:
  cushion, club: club_chair, ring: plush. The builder lists these seats (its `seats()`), so they are listed once.
  A slot is `{transform, row, style, width, builder}`. Slots of one row run left to right; a gap of more than 1.5
  widths starts a new pew. The pews' ends, the benches' trim and the settees' arms go into one static mesh,
  `SeatEnds`. With `model` `settee`, a builder's row of three slots is one settee (set the builder's seat pitch to
  about 0.6 m: the slot's width is the place's).
- **Its own seats.** Rows round `origin` (`per_row`, `rows_front`, `rows_back`, `pitch`, `row_depth`, `row_rise`,
  `aisle`, `facing`), and single `places` (`{at, turn, model}`). These are its `seats()`: seat choice, seat
  picking and the sight-line check use them.
- **Broken seats over a builder's own.** `broken` names room seats by their index in the room's seat list. Over a
  builder that draws its own seats (the auditorium, Screen 3), the seats system folds that seat away in the builder's
  MultiMesh "Seats" and draws a broken one of the builder's `seat_model` in its place. It does this again after every
  room move, so the seat stays away when the viewer has sat there and moved on. The broken seat takes the builder's
  seat materials (unless `upholstery` or `frame` is set). So it matches the seats next to it and adds no textures.

A builder can also draw any model itself: `seats.gd model_mesh(model, upholstery, frame, width, form)`. The
auditorium's `seat_mesh()` does, for every `seat_model` but the stadium seat.

### Drawing

- One MultiMesh a model and form: `Seats`, `SeatsUp`, `SeatsBroken`. The upholstery takes a slight tint seat by
  seat (`variation`, `seed`), as in the cinema.
- The viewer's own seat folds away (`fold_own`): chairs only. A pew, a bench, a settee, a cushion, a hide or a bean
  bag stays.
- `tipped`: the share of tip-up seats left tipped up.
- `collision_shapes()`: each seat's model boxes (one or two), for object physics.

Measured headless (`test_env_seats.gd`): 15 plush seats are 2 draws and 9 660 triangles. A tipped or broken form
adds two draws. Pews' ends add one or two. Texture memory is the headset's, rendered or not ("The checks").

| Parameter | Default | What |
|---|---|---|
| `model` | auto | the seat; auto: by each slot's style (its own rows: folding chairs) |
| `from_builders` | true | a seat in every seat slot of the room's builders |
| `per_row`, `rows_front`, `rows_back` | 0, 0, 0 | its own rows |
| `pitch`, `row_depth`, `row_rise`, `aisle` | 0 (the model's width), 1.1, 0, 0 | their spacing |
| `origin`, `facing` | [0, 0, 0], 0 | the middle of the row at origin; the rows' turn |
| `places` | [] | single seats: `{at, turn, model}` |
| `upholstery`, `frame` | null (the model's own) | library materials |
| `variation`, `seed` | 1, 1906 | the tint seat by seat |
| `tipped` | 0 | the share of tip-up seats tipped up |
| `broken` | [] | room seats drawn broken (at most 8) |
| `fold_own` | true | the viewer's own chair folded away |

## The motion system

`scripts/env/systems/motion.gd`. Slow moves of the room's things. It never moves the viewer or their horizon
(`moves_viewer` false in its spec).

One motion system moves one thing. Give each its own id: the id names its actions (`organ.rise`). The thing is:

- a node the document names: `node` (its name, or the plain name it had before `own()` gave it its system's id),
  among the nodes of the system `system` (an id), or anywhere in the room when `system` is empty;
- or a festoon curtain it builds itself: `build` "festoon". It hangs over the screen (`festoon_size` 0: the
  screen's size with a margin) in `festoon_swags` swags, `festoon_depth` in front, in the `curtain` material.

### Modes

| Mode | What | Parameters |
|---|---|---|
| `travel` | along `path` (offsets from where it stands, in its parent's frame) and to `turn_to` (degrees, about `pivot` in its own frame). `at` 0 is where it stands, 1 the path's end | `path`, `turn_to`, `pivot`, `at` (live), `speed`, `accel`, `turn_speed` |
| `sway` | to and fro about `sway_axis` and along `shift_dir`, one swing every `sway_period` seconds | `sway_angle` (live), `sway_shift` (live), `sway_period`, `pivot` |
| `turn` | round `turn_axis` | `turn_rate` (live) |

A festoon travels too: `at` 1 is fully up. The hem rises, the cloth above it gathers into tiers of folds, and
between the lift cords it falls in swags that deepen as it rises.

Actions: `rise` (to at 1), `lower` (to at 0), `go` (args `at`), each with `seconds` as a wish; `snap` (at once,
args `at`); `start` and `stop` (a sway or a turn eases in or out). A cue can also `set` `<id>.at`.

### Comfort

| Limit | Value |
|---|---|
| speed | 0.5 m/s |
| acceleration | 0.3 m/s² |
| turning speed (travel) | 20 degrees/s, speeding up at 8 degrees/s² |
| sway | 5 degrees, 0.1 m, a swing at least every 3 s |
| turn | 15 degrees/s, speeding up at 8 degrees/s² |

- Each limit is a `motion` flag in the spec, and the parameter's range ends there. The comfort check and the
  schema refuse more.
- Whatever drives `at` (an action, a cue's fade, a binding), the thing follows it no faster than its limits. It
  speeds up and slows down smoothly. An action's `seconds` is a wish: when it asks for more than the limits, the
  move takes longer. A sway or a turn starts from still and eases in.
- **The Motion setting** (common) scales every motion parameter: half Motion is half the sway, half the speed.
  Under 25 % a travel does not move at all: it snaps to the end it heads for, or (`reduced` "fade") fades out,
  jumps and fades back in. A cue's fade on `at` then snaps to its end too.
- **In front of the screen.** A thing that stands between the viewer and the screen until it moves (`in_front`: a
  painting over the screen; the festoon always) does not count against the sight-line check. It is in the group
  `env_in_front`. It never stays in the way through the film: 4 s after the film starts (no cue took it away), it
  goes to its end by itself. A room whose Pre-show is off needs no cue for it.

Measured (`test_env_motion.gd`): an organ console rising 2.8 m at 0.3 m/s and 0.15 m/s² takes 11.3 s and never goes
faster. A festoon of 5 swags is 1 draw and 840 triangles; the mesh is made again only while it moves.

### Examples

```json
{"system": "motion", "id": "organ", "params": {"system": "kit", "node": "OrganConsole",
 "path": [[0, 2.8, 0]], "speed": 0.3, "accel": 0.15}}
{"system": "motion", "id": "painting", "params": {"node": "Painting", "path": [[0, 3.0, 0]], "in_front": true,
 "reduced": "fade"}}
{"system": "motion", "id": "festoon", "params": {"build": "festoon", "festoon_swags": 6}}
{"system": "motion", "id": "earth", "params": {"system": "sky", "node": "Earth", "mode": "turn",
 "turn_rate": {"bind": "setting.earth_speed", "range": [0.5, 4.0]}}}
```

The ritual raises them: `{"do": "organ.rise", "args": {"seconds": 12}}`, `{"do": "festoon.rise", "args":
{"seconds": 8}}`.

## The builders

Six more builders of kind `builder`, and the `kit`. They keep the auditorium's conventions. They extend
`scripts/env/systems/kit/builder.gd`, and they share the helpers in `scripts/env/systems/kit/` (`build_util.gd`,
`shapes.gd`, `procedural.gd`, `seat_models.gd`, `pieces.gd`, `furniture.gd`, the glass and glow shaders).

- **The viewer's seat** is at the origin, facing -Z. The floor under it is at y 0 (a lot's ground and an
  amphitheatre's pit can be lower).
- **Static parts** are meshes with their own UV2, baked by the light system's hooks. Rounded parts (seats, statues,
  leaves) are not baked.
- **Materials** are library materials on the house shader, from the light system. Patterns (pressed tin, ice blocks,
  a swirling carpet, corrugated tin, plasterboard) are our own maps, drawn in `procedural.gd` and put on a library
  material. The library material is CC0, so the licence check still holds.
- **Lamps** use the light system's groups: `house` (the ritual takes them down), `accent`, `signs`, `booth`. A flame
  or a candle flickers with the builder's `flicker` parameter. Every frequency is under 3 Hz. The room's Flickering
  lights setting holds it steady.
- **A lamp colour a cue moves** (since 2026-11-07): the light system's live `glow_colour` and `glow_mix` (0 by
  default: the lamps' own colours) take the `house`, `steps` and `stage` lamps' glow toward one colour. A builder's
  lamp colour parameters are not live (the room builds again), so a cue that changes the lamps' colour fades these:
  the Streamline's Changing cove (`cove_cycle`, and `cove_settles` when the film starts). The stand-in lamps and a
  baked lightmap keep the builder's colour.
- **Glass** (a window, a dome's panes, a windscreen) is in the group `env_see_through`. The sight-line check looks
  through it. It blends; it never multiplies.
- **The sight line:** a flat-floored builder keeps the picture's bottom at 1.1 m or more over the floor, so chair
  backs never block it.
- **Physics:** `collision_shapes()` gives cheap boxes. Seat boxes come only when the builder draws its own seats.
- **The screen:** each builder's static `screen_for(params)` gives the default screen ({center, size}). A room
  document's `screen` should match it.

### Seat slots (the interface with `seats`)

Each builder's static `seat_slots_for(params)` gives its seats as slots, from the parameters alone. A slot is
`{transform, row, style, width, builder}`.

- `transform`: the floor point under the seated eyes, facing -Z in its own frame.
- `row`: 0 is the viewer's row. Rows in front count up. Rows behind are negative.
- `style`: `chair`, `pew`, `bench`, `cushion`, `club`, `ring` or `tier`.
- `width`: metres along the row. A row's slots go left to right. A pew's or a bench's slots are `width` apart. An
  aisle leaves a gap wider than 1.5 widths.

With a `seats` system in the room, the builder draws no seats and gives no seat boxes; the seats system draws them in
the slots. Without one, the builder draws plain default seats (`seat_models.gd`). Single seats (chair, club, ring)
are one MultiMesh, with the viewer's own seat folded away. Pews, benches and cushions are one static mesh.

### Slots for the kit

Each builder's `slots()` gives named places for kit pieces: `{name: [{transform, size}]}`. A piece's front faces its
local +Z (into the room). Common names: `side_walls`, `screen`, `proscenium`, `rear_wall`, `floor`, `ceiling`,
`corners`. Each builder adds its own (below).

### `shopfront`

A narrow picture house of about 1906 in a shop. A wooden dado, pressed tin above it and on the ceiling, a small
raised end with a framed sheet, the shop window and door behind the seats with the street's glow, gas lamps that
flicker, folding chairs in rows.

- Size: `width`, `height`, `screen_wall_z`, `front_z`. Rows: `rows_front`, `rows_back`, `row_pitch`,
  `chairs_per_row`, `chair_pitch`, `seat_model`.
- The end: `stage_depth`, `stage_height`, `screen_size`, `screen_bottom`, `sheet_frame`.
- Walls: `dado_height`, `tin_pattern` (`pressed_tin` or `plain`), `tin_walls`.
- Live: `street_glow`, `flicker`. Lamps: `lamps_per_side`, `lamp_height`, `lamp_colour`.
- Slots: `booth` (the back corner's floor), `side_walls`, `screen`, `proscenium`, `rear_wall`, `ceiling`, `floor`.
- Measured: 13 draws, 12k triangles, 7 MB.

### `nave`

A church-like nave. Two arcades of round columns, side aisles, clerestory walls with dim windows, a barrel vault, a
chancel up three steps with the screen under the chancel arch, a rose window over it, candle stands that flicker,
pews.

- Size: `nave_width`, `aisle_width`, `rear_z`, `chancel_z`, `chancel_depth`, `chancel_rise`, `bay`,
  `column_height`, `column_radius`, `wall_height`, `vault`.
- Pews: `rows_front`, `rows_back`, `row_pitch`, `places_per_pew`, `place_width` (one slot a place, style `pew`).
- Live: `rose_glow`, `flicker`. Also `rose_window`, `rose_radius`, `clerestory_windows`, `candles`.
- Slots: `niches` (the aisles' walls), `columns`, `screen`, `proscenium` (the chancel arch), `rear_wall`, `floor`.
- Measured: 11 draws, 4.4k triangles, 8 MB.

### `dome_hall`

A round hall under a dome, glass or solid. A low drum wall, lamps round it, a low stage, seats on arcs round the
screen (style `ring`). Beyond glass: nothing (a sky system's sky), deep water, or a dark night. With `has_floor` and
`seating` off, it covers another builder (the crater: an amphitheatre under a glass dome).

- `radius`, `centre_z`, `floor_y`, `drum_height`, `dome_height`, `dome` (`glass` or `solid`), `ribs`, `rings`.
- `outside` (`none`, `water`, `night`), `water_top`, `water_deep`; live: `outside_glow`.
- `glass_colour` and `glass_alpha` (0.05; lower is clearer): a pale tint at a low alpha keeps the view out clear,
  where before a room needed a near-black tint to stop the glass hazing what lies outside.
- Seats: `rows_front`, `rows_back`, `row_depth`, `seat_pitch`, `arc_deg`, `seat_model`.
- Slots: `drum`, `screen`, `proscenium`, `floor`, `ceiling`.
- Measured (glass, about 120 seats): 8 draws, 88k triangles, 4 MB.

### `terrace`

Open air, under a sky system's sky. Three styles. `terrace.gd STYLES` holds the parameters each style needs; a room
document sets them.

| Style | What | Its parameters |
|---|---|---|
| `rooftop` (default) | a tiled roof terrace, a low parapet, the screen painted on the next building's blind wall, strings of bulbs, chairs in rows | the defaults |
| `lot` | a drive-in's lot: low humps across each row of bays, speaker posts beside the cars' front seats, the screen on a frame (or `screen` `none` and the kit's tower). No seats of its own: the car's | `half_width` 20, `front_z` -50, `back_z` 12, `ground_y` -0.5, `ground_extent` 120, `parapet` false, `screen` frame, `screen_size` [24, 10], `screen_bottom` 4, `seating` false, `string_lights` false |
| `amphitheatre` | stone tiers on arcs round the screen, rising behind the viewer (style `tier`), rocks on a dusty plain: a lunar amphitheatre | `half_width` 14, `front_z` -14, `back_z` 10, `ground_extent` 150, `parapet` false, `screen` frame, `screen_size` [8, 4.5], `screen_bottom` 1.6, `rows_front` 3, `rows_back` 6, `row_pitch` 0.95, `seat_pitch` 0.6, `string_lights` false |

- The ground beyond the terrace (`ground_extent`, up to 400 m) is not baked, so the lightmap stays small.
- Other parameters: `parapet_height`, `wall_height`, `tier_rise`, `arc_deg`, `rocks`, `bays`, `bay_pitch`,
  `bulb_colour`, materials.
- Slots: `parapet` (along the parapets' tops), `screen`, `proscenium`, `floor`, `corners`.
- Measured: rooftop 8 draws, 12k triangles, 7 MB; lot 5 draws, 3k triangles; amphitheatre 4 draws, 2k triangles.

### `domestic`

A room in a house: walls, a window, a door, a fireplace or a radiator, wall lamps, and a screen. Four styles. Every
parameter left on "auto" takes the style's value (`domestic.gd STYLE_DEFAULTS`): an enum's `auto`, 0 for a size, -1
for a count that can be 0, `{}` for a material, `[0, 0]` for the screen's size. A document sets only what it changes.

| Style | What |
|---|---|
| `plain` | a sitting room: club chairs, a pull-down screen, a radiator under the window |
| `walnut_1962` | a private screening room: walnut panelling, a deep carpet, two rows of club chairs, a picture window (a pool beyond it: a vista), a brick fireplace, brass wall lamps, a painting over the screen |
| `bedroom_1993` | a child's bedroom: a pillow fort of cushions and a bedsheet on broom handles round the viewer's cushion, fairy lights along its front, a telly on a chest of drawers, a bed, a radiator under the window |
| `ice` | a room of ice blocks under a low vault, hides on the floor, candles in the walls, the picture on a smoothed panel of ice, the doorway open to the night |

- Size: `half_width`, `front_z`, `back_z`, `height`, `vault_rise`.
- The screen (`screen`): `projected` (a pull-down screen), `wall` (a panel on the wall), `painting` (a framed
  painting covers the screen and rises into a slot in the ceiling), `telly` (a set on a stand: below). Also
  `screen_size`, `screen_bottom`.
- `painting_open` (live, 0 to 1): 1 is risen (the screen shows), 0 is down over the screen. A cue fades it for the
  ritual (the `motion` system can move the `Painting` node too).
- `opening_screen` (not live: the room builds again): the telly fills the pillow fort's opening. The picture is as
  big as fits in the opening, just beyond it.
- The telly (`telly`): `cabinet` (a deep box, wider at the bottom for its buttons; the default), `portable` (a small
  deep case, its knobs and a speaker's slots on a panel to the right of the picture, a carry handle, a rod aerial) or
  `flat_panel` (a thin frame, a speaker strip under the picture, 7 cm deep; its picture is always 16:9, its height
  from its width). Left on auto, `screen_size` is the form's own: a portable 0.3 x 0.225 m, a flat panel 0.8 x 0.45 m.
- Its stand (`telly_stand`): `chest` (a chest of drawers, as before), `radiogram` (a long low cabinet on splayed
  legs, a grille of slats, two sliding doors), `desk` (a top, a pedestal of three drawers, legs, a modesty panel),
  `tv_unit` (a low cabinet with an open shelf under its top, 14 cm high, for a video recorder, and doors below) or
  `wall` (a flat panel hangs on it, its back at the wall; a cabinet or a portable sits on a shelf on two brackets).
  The picture stays where `screen_size` and `screen_bottom` put it; the stand is as tall as the space under the set
  (a flat panel stands on a 10 cm pedestal). A stand's back is at the front wall and its front at the set's (a
  flat panel's foot set back 12 cm on it). `stand_width` (0: its own, a little wider than the set) and
  `stand_shift` (metres sideways; the picture does not move) leave room beside the set. The stands are in the trim's
  material and drawn by `kit/furniture.gd`, as the kit's furniture is.
- On the wall, the picture is the set's depth and 3 cm out from the front wall; otherwise it is 0.5 m out, as before.
  `screen_for()` follows every form and stand, so the room's screen sits on the set's glass (tested for each form on
  each stand).
- `window` (`none`, `left`, `right`, `back`), `window_width`; `outside` (`glow` or `none`: a vista's or a sky's view
  shows through), `outside_top`, `outside_bottom`; live: `outside_glow`.
- `door` (`none`, `left`, `right`, `back`). In ice it is an open doorway with the night's glow beyond.
- `heater` (`none`, `fireplace`, `radiator`). The fireplace is on the wall across from the window. The radiator is
  under the window. Live: `fire`, `flicker`.
- `lamps` (on each side wall), `lamp_colour`; `fort`, `fairy_lights` (`auto`, `on`, `off`), `fairy_colour`; live:
  `fairy_glow` (0 to 1.5: the fairy lights' bulbs and the light they give, and nothing else).
- Seats: `seat_model` (`club`, `cushion`, `plush`, `director`, `folding`), `rows_front`, `rows_back`,
  `seats_per_row`, `seat_pitch`, `row_pitch`. Cushions are style `cushion`.
- `wall_pattern` (`plain`, `ice_blocks`, `plasterboard`) and materials: `walls`, `floor`, `ceiling`, `trim`,
  `surround`, `radiator_material`, `screen_surface`, `telly_material`, `cushions`, `sheet`, `seat_cover`,
  `seat_frame`.
- Slots: `side_walls`, `screen`, `proscenium`, `floor`, `ceiling`, `corners`, `window` (the pane: a weather system's
  `pane_center`, `pane_size`, `pane_yaw`), `vista` (beyond the window, facing in), `mantel`, `fort_opening`; with a
  telly, `telly_stand` (the stand's top at its front middle, facing the room: a piece on it goes at a negative z; on
  the wall, the floor under the set) and `telly_shelf` (a video recorder's place: the tv unit's shelf; a desk's or a
  radiogram's top beside the set when there is half a metre; else the floor in front of the stand).
- Measured: plain 13 draws, 4k triangles; walnut 16 draws; bedroom 18 draws, 6k triangles; ice 11 draws, 12k
  triangles. 4 to 10 MB. A telly on its stand adds no draw of its own (the set is one mesh, the stand is in the trim):
  each form on each stand in a plain room is 12 draws and 3.8k to 4.2k triangles.

### `vehicle`

The inside of a generic 1950s convertible with its top down, facing the screen (on the terrace's lot). No mirror, no
badge, no maker's shape.

- A front bench and a rear bench, three places each (style `bench`). The viewer is in the middle of the front bench,
  at the origin. The left place has the steering wheel in front of it; the wheel's top is under 1.05 m.
- The wraparound windscreen's top is under the eyes (1.12 m), so the view of a screen up on a lot's frame or tower
  goes over it. Its glass is see-through.
- Parameters: `ground_y` (the ground under the car; the wheels show when it is under the body), `rear_seat`, `top`
  (`folded` or `none`), `fins`; live: `headlamps`, `dial_glow`; `dial_colour`; materials `body`, `chrome`,
  `upholstery`, `piping`, `carpet`, `tyres`, `hood_cover`.
- It brings no screen. `screen_for()` gives the lot's, so a test room has one.
- Slots: `dash`, `bonnet`, `rear_shelf`, `floor`.
- Measured: 16 draws, 6k triangles. The car's parts share one baked and one unbaked mesh.

### The film layer and the builders

On the Frame the film is a layer drawn over everything between the eyes and the picture
(`scripts/play/film_layer.gd`). The builders keep everything solid out of that space (the sight-line check holds
it). Glass in front of the picture (a windscreen) would simply not show over the picture there. Two parts can come
in front of the picture on purpose: the domestic painting when it is down (`painting_open` under 1), and the pillow
fort's hem and fairy lights if a seat's eyes are lower than the check's 1.2 m. The film layer hides them while a film
plays unless it steps aside. It steps aside today only for physics objects, the controllers and the laser
(`_covered()`). The painting's ritual happens before the film, so the picture under the painting is usually black,
but the layer still draws there. This needs a hook from the film layer (a room's parts that cover the screen); it is
an open question below.

## The kit

`scripts/env/systems/kit.gd`, kind `kit`, with the pieces in `scripts/env/systems/kit/pieces.gd`. A document lists
the pieces. The kit must come after its builder in the document. A room may have two kits, each with its own id
(their nodes keep apart: see `own()` above).

```json
{"system": "kit", "params": {"pieces": [
  {"piece": "niche", "slot": "side_walls", "index": 4, "holds": "lion", "at": [0, 1, 0]},
  {"piece": "bougainvillea", "slot": "parapet", "index": -1},
  {"piece": "snack_bar", "at": [0, -0.5, 16], "yaw": 180, "text": "SNACKS"}]}}
```

| Key | What |
|---|---|
| `piece` | which piece (below) |
| `slot`, `index` | a slot of the builder and which of its places; `index` -1 is every place. No slot: `at` is in the room's frame |
| `at`, `yaw`, `scale` | an offset in the slot's frame, a turn about the vertical (degrees), a scale |
| `size` | width, height, depth; 0 takes the slot's size (for façades, curves, ivy, bougainvillea, balcony fronts, partitions) or the piece's own |
| `holds` | what a niche holds: `urn`, `lion`, `obelisk` or `none`; a computer with `none` has no monitor |
| `colour`, `accent` | the piece's main colour, and a second one (a rug's border, a lamp's pole) |
| `text` | a neon sign's words in our own letters: A B C D E F I K L N O P R S T U W and the space |
| `target` | the node the carpet goes on (the builder's `Floor` by default) |

Other parameters: `builder` (the builder's id; empty: the room's first builder); materials `stone`, `plaster`,
`wood`, `tin`, `roof`, `iron`, `plastic` (a computer), `fabric` (a rug); colours `leaves`, `flowers`, `neon`,
`window_colour`, `lamp_colour` (a standard lamp's shade), `display_colour` (a video recorder's clock); live: `glow`
(lit windows, the booth's window, neon, the clocks).

| Piece | What |
|---|---|
| `balcony_front` | a moulded parapet panel with a rail, bands and round bosses |
| `niche` | pilasters, an arch, a shell hood, a darker back and a shelf, holding an urn, a lion or an obelisk. Never a figure or a torso |
| `urn`, `lion`, `obelisk`, `column` | on the floor; the lion lies on a plinth, its head up |
| `facade` | a courtyard's plastered wall with a cornice, a tiled eave, two arched windows lit from inside, shutters, an iron balcony |
| `castle_gate` | towers with battlements and arrow slits either side of the screen, a wall over it, a raised portcullis whose teeth hang just above the picture. Sized to the room's screen |
| `booth` | a projection booth of corrugated tin, its window lit towards the screen (`booth` group) |
| `snack_bar` | a counter, shelves, a canopy, a neon sign (`signs` group) |
| `screen_tower` | a drive-in's tower behind the room's screen: the face, posts and braces |
| `bougainvillea`, `ivy`, `ferns` | leaves (unbaked): bougainvillea over a parapet's top and down its face, ivy up a wall, ferns in a clump on the floor |
| `carpet` | the builder's floor takes the swirling carpet pattern |
| `partition` | a plasterboard wall with taped joints and a skirting |
| `curves` | two bands in waves along a wall (pink and blue by default) |
| `desk` | a top, a pedestal of three drawers on its right, legs on its left, a modesty panel (`wood`, handles in `iron`). 1.2 x 0.74 x 0.65 m |
| `computer` | a flat beige case with two drive slots, a CRT monitor on it, a keyboard with its rows of keys in front (`plastic`, the glass and slots in `iron`). `holds` `none`: no monitor (a telly is its screen) |
| `video_recorder` | a slim case (`iron` in the entry's colour), the cassette's door, five buttons, a display window whose clock flashes 12:00 (below). 0.43 x 0.09 x 0.3 m |
| `sideboard` | doors either side, three drawers between, short legs, the top overhanging (`wood`, handles in `iron`) |
| `standard_lamp` | a round base and a thin pole (`iron`, or the entry's `accent`), a drum shade that glows in the entry's colour (`house` group) and gives a dim stand-in lamp |
| `rug` | a field (`fabric` in the entry's colour), a border a little raised (its `accent`, or the field's darker), a fringe at either end |
| `coffee_table` | a top on four legs, a shelf under it (`wood`) |

The furniture is drawn by `scripts/env/systems/kit/furniture.gd` (plain boxes and turned shapes of our own: no maker's
shape, no badge, no lettering), which the domestic builder's telly stands use too. A piece stands with its foot at the
slot's point and its front towards the slot's +z; the domestic builder's `telly_stand` and `telly_shelf` slots are
made for it (the computer on a desk beside a portable, the video recorder in a tv unit's shelf).

**The video recorder's clock.** 12:00 in seven segments of our own (quads, no font, no texture of letters), in
`display_colour`, all the room's clocks one mesh (`PieceDisplay`, accent group). It flashes once a second: lit half a
second, dark half a second, each change eased over about 0.2 s (slower than the photosensitivity ceiling's fade). The
room's Flickering lights off holds it lit. `clock_level()` gives its level now (tests).

- **Cost by material:** all the pieces share a baked mesh (`PieceStatic`) and an unbaked one (`PieceSoft`), one
  surface a material, plus the lamp shades (`PieceLamps`, one draw a shade colour), one draw for the lit windows, one
  for booth windows, one for the clocks and one a neon sign. Thirteen pieces in the atmospheric test take 10 draws.
  Triangles: desk 108, tv unit 100, radiogram 182, sideboard 162, coffee table 64, computer 132, video recorder 112
  and its clock 42, standard lamp 128, rug 22.
- **The auditorium's slots:** the auditorium has no `slots()`, so the kit works them out from its parameters:
  `side_walls` (every 2.5 m on both walls, at the side aisle's floor), `proscenium` (the stage's top), `rear_wall`,
  `corners` (the pit's front corners), `floor`, `ceiling`, and `balcony` when it has one.
- **Physics:** the pieces' boxes follow the builder's slots, so they exist once the room is built
  (`collision_shapes()`); there is no static form.
- **Problems:** a slot the builder lacks, or an index past its places, is reported by `problems()` and the piece is
  not placed.
- Measured: bougainvillea along the rooftop's 14 parapet places: 2 draws, 23k triangles. The atmospheric hall's
  pieces: 11 draws.

## Atmosphere and weather

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
| Ice cinema | `atmosphere`: `breath` 0.6, a little low `fog` |
| Pillow Fort | `weather`: `pane` on the window, `mode` light or changing, no areas (or one outside the window) |

## Sound and music

Three systems: `sound_bed` and `acoustics` (kind `sound`) and `music`. Every sound is our own, made by
`scripts/env/env_synth.gd` from noise, oscillators and filters. No samples are bundled. Nothing is drawn, so the
film layer does not matter here. The film must always win: every sound plays on the Environment bus, sits at a
designed level far under the film, sits lower again while the film plays, and is ducked under the film.

### The room's bus

`sound_bed` and `music` play on the bus "Environment room". It sends to Environment, so the ducking, the Environment
sound slider and the room's Ambience all act on it. `acoustics` puts a reverb on it. Without `acoustics` it is dry.
Cue sounds (`env_audio.play`, the chime) and the thud still go straight to Environment, dry, as before.

### `sound_bed`

`scripts/env/systems/sound_bed.gd`. One sound per system, each with its own id. A room has as many as it needs.

| Param | Default | What |
|---|---|---|
| `sound` | `silence` | loops: `projector`, `wall_rumble`, `cicadas`, `radiator`, `rain_glass`, `rain_leaves`, `gas_hiss`, `noise`, `crickets`, `fire`, `drips`, `wind`, `hum`, `deep_hum`, `fountain`, `clock`, `tube_whine`; one-shots: `moped`, `train`, `huskies`, `hull_creak`, `rumble`, `tick`, `creak`, `whale`, `chime`, `gong`, `bird`, `purr`, `three_bells`, `candle`, `ice_creak`, `vcr`, `tape_load`; `silence` plays nothing (the sounds: below) |
| `gain_db` | 0 | dB from the designed level (-30 to +6) |
| `level` | 1 | 0 to 1, live. Bind it: `film.bass` for a rumble through the wall, `weather.rain` or `weather.wet` for rain, a setting |
| `film_db` | -8 | dB lower in `starting`, `playing` and `credits`. Up again in the pre-show, paused, the intermission and the end |
| `fade` | 3 | seconds a change of state takes |
| `place` | `everywhere` | `everywhere` (no direction), `at` (one place), `around` (`voices` places on a circle of `radius` round `at`, each at another point in the loop) |
| `at`, `to`, `reach` | | where; a one-shot with `to` travels there over its length (a moped passing); metres at full level |
| `every`, `jitter` | 0, 0.3 | a one-shot comes back every so many seconds (a far train); 0: only when a cue plays it |
| `pitch`, `vary` | 1, 0.05 | playback pitch; a one-shot's pitch varies each time |

Actions: `play` (a one-shot now), `stop` and `start` (fade the bed out and in). Rain reads the weather only through
the `weather.rain` and `weather.wet` channels, by a binding.

Streams are made on a worker thread the first time, then cached (0.03 to 0.5 s each on a desktop; the train 1.1 s).
A cue that plays a new one-shot with `env_audio.play` makes it on the main thread: use a `sound_bed` with `every`
or its `play` action for the long one-shots.

#### The sounds

All made by `env_synth.gd` from noise, tones and filters. None copies a real sound, jingle or call. Every loop's
tones and swells divide its length, so it has no seam.

| Sound | Loop or one-shot (s) | What it is | For |
|---|---|---|---|
| `projector` | loop 4 | the claw's pull-down 24 times a second, the shutter's whir, the motor's hum | a booth behind |
| `wall_rumble` | loop 8 | low noise and two low tones that swell; bind `level` to `film.bass` | the next screen through a wall |
| `cicadas` | loop 6 | three buzzing voices that swell in turn | a warm night |
| `crickets` | loop 6 | four field crickets, each at its own pitch and steady rate | a summer night, a drive-in |
| `radiator` | loop 16 | metal ticks at odd moments, water trickling | a bedroom, a sitting room |
| `rain_glass` | loop 6 | drops on a pane, now and then a big one, the rain beyond | a window; `level` on `weather.rain` |
| `rain_leaves` | loop 6 | a dense patter on leaves, drips from above | open roofs; `level` on `weather.rain`. For rain on boards, try `pitch` 0.7 |
| `drips` | loop 8 | drops into puddles at odd moments, two steady leaks | after rain; `level` on `weather.wet` |
| `wind` | loop 12 | a broad band that drifts with the gusts, a faint low roar, a thin whistle in the strongest gusts | a clerestory, a doorway, a night wind |
| `fire` | loop 8 | the flames' soft roar and flicker, small crackles, now and then a pop | a wood or coal fire |
| `gas_hiss` | loop 4 | a gas lamp's hiss and a soft roar | gas light |
| `hum` | loop 4 | a motor's hum through glass: the mains' hum, the motor's turning, water in a pipe | a pool's filter pump, a fridge |
| `deep_hum` | loop 8 | low tones beating slowly, with harmonics small speakers can play, low noise, a slow swell | the deep, on a hull |
| `fountain` | loop 6 | many small bubbles over the soft splash of falling water | a courtyard's fountain |
| `clock` | loop 4 | a tick and a slightly duller, slightly early tock each second, through a wooden case | a mantel, a shelf |
| `tube_whine` | loop 2 | a picture tube's line whine at 15 625 Hz and its valves' faint hum. `pitch` 0.648: a 405-line set's 10 125 Hz; 1.007: 15 734 Hz | a CRT telly, very low |
| `noise` | loop 4 | pink noise | under other beds |
| `moped` | one-shot 8 | a small two-stroke passing, 15 m away at its closest; with `to` it travels | a street below |
| `train` | one-shot 40 | a freight train far off: the roll, the rail joints, the horn's two notes early on | far off, `every` |
| `huskies` | one-shot 7 | three far howls and a few yips, an echo | snow |
| `hull_creak` | one-shot 3.5 | steel under pressure: stick-slip pulses through a low groan and bright partials | a hull |
| `ice_creak` | one-shot 2.6 | a crack that sings down, then a low groan | ice, `every` |
| `candle` | one-shot 0.9 | a candle's flame puffs and wavers, three or four sputters of wax | `every`, very low |
| `three_bells` | one-shot 3.2 | a soft house bell: three struck-bar tones, up a fifth, down a minor third (our own call) | before the show |
| `vcr` | one-shot 4.5 | a video recorder takes a tape: the clunk, the motor threading the tape with its clicks, the heads engaging, the drum's whirr | a cue: the tape goes in |
| `tape_load` | one-shot 8 | a home computer loads from cassette: a pilot tone, a gap, the data's two-tone warble, the tape's hiss | a cue, very low |
| `bird`, `purr`, `whale` | one-shot 1.2, 4, 5 | a songbird's call, a cat's purr (two breaths), a whale's song | ambient life's calls (below) |
| `chime`, `gong`, `rumble`, `tick`, `creak` | one-shot | the foundation's sounds | cues |

Cue sounds (`EnvDoc.SOUNDS`, for a cue's `sound` step and ambient life's calls): the foundation's seven, `moped`,
`train`, `huskies`, `hull_creak`, `bird`, `purr`, `three_bells`, `candle`, `ice_creak`. A cue's `sound` step plays at
the reference level less its `gain_db`: at 0 dB it reaches the level check's target, so give it -10 or lower. A
`sound_bed` with `play` is the levelled way: it plays at the sound's designed level.

### `acoustics`

`scripts/env/systems/acoustics.gd`. The room's sound character, a reverb on the room's bus.

| Preset | rt60 (s) | damping | wet | predelay (ms) | echo |
|---|---|---|---|---|---|
| `neutral` | 0.3 | 0.6 | 0 (dry) | 20 | 0 |
| `small_room` | 0.35 | 0.7 | 0.12 | 20 | 0 |
| `cinema` | 0.7 | 0.6 | 0.18 | 25 | 0 |
| `shopfront` (pressed tin) | 0.9 | 0.3 | 0.25 | 20 | 0 |
| `concrete_hall` | 2.4 | 0.25 | 0.32 | 60 | 0.35 |
| `stone_nave` | 5.0 | 0.45 | 0.4 | 80 | 0.1 |
| `ice` | 1.1 | 0.1 | 0.25 | 20 | 0 |
| `hull` | 1.4 | 0.2 | 0.3 | 20 | 0.15 |
| `vehicle` | 0.15 | 0.85 | 0.06 | 20 | 0 |
| `outdoors` | 0.2 | 0.5 | 0.04 | 90 | 0 |
| `vacuum` | 0.05 | 1 | 0 (dry) | 20 | 0 |

`rt60`, `damping`, `wet`, `predelay_ms` and `echo` are live; -1 takes the preset's. The engine's reverb is
measured: `TAIL_SECONDS` holds its tail at each room size, and `room_size_for()` picks the size for an rt60. Its
tail is never shorter than about 0.5 s or longer than about 6 s. The short presets use its smallest room with a
little wet.

**The film keeps its own mix.** `film` is off by default. Only with `film` on does `sound_room()` give spatial audio
(`scripts/play/spatial_audio.gd`) the room's rt60, its `film_wet` and its walls' `reflect`, so the film's speakers
ring in the room too. The binaural renderer's code is not changed. The document's own `acoustics` section still goes
over it.

### `music`

`scripts/env/systems/music.gd`. An instrument that plays itself. No player is shown: the keys move by themselves.
It writes its own music as it goes, from the room's seed: a key, two common chord progressions, the form A A2 B A,
and a tune of its own from short rhythms. Never a melody we don't own.

- **`piano`**: a player piano for silent films. The left hand plays oom-pah, the right hand the tune. Each note is two
  slightly detuned strings (`detune_cents`, an upright's honky-tonk). It plays in `starting`, `playing` and
  `credits`, and starts its piece again when the film starts from its start. `drive` (bind it to `film.transient`
  with a `range` such as [0.3, 1]) makes it faster; over 0.65 it plays an agitato (tremolo on a diminished chord)
  until the film calms; under 0.12 it plays sparse.
- **`organ`**: slow chords in four voices, held across bars, with passing notes and a tremulant. Its stops are
  `flute`, `principal`, `full` and `theatre`. It plays in the pre-show, the intermission and the end. `flourish`
  plays a closing cadence and then rests.

Params: `instrument`, `on` (live; bind it to a setting), `gain_db`, `level`, `drive`, `plays_in` (empty: its own
states), `film_db` (-6), `tempo` (0: piano 104, organ 56), `seed`, `mode` (major or minor), `stop`, `tremulant`,
`detune_cents`, `at`, `reach`. Actions: `play` (args: seconds), `stop` (args: seconds to fade), `flourish`. Twelve
voices. The notes are made on a worker thread (the piano's 17 in 0.8 s, the organ's 66 in about 0.4 s on a desktop).

### Levels

Measured (`test_env_sound_bed.gd`, `test_env_music.gd`, 2026-11-07, desktop, headless) on Environment at the
slider's default, in dBFS RMS. The film's reference is -20; the level check's target is -38. "In film" is with
`film_db`; "under a film" adds a 1 kHz tone on Film at the reference level (the duck). A one-shot is its loudest
second.

| Sound | Designed | Alone | In film | Under a film | Peak |
|---|---|---|---|---|---|
| `projector` | -51 | -51.0 | -59.0 | -66.1 | -29.7 |
| `wall_rumble` | -50 | -50.0 | -57.4 | -65.8 | -36.9 |
| `cicadas` | -54 | -53.9 | -61.5 | -70.7 | -33.0 |
| `crickets` | -55 | -55.1 | -62.9 | -70.4 | -36.9 |
| `radiator` | -55 | -55.0 | -62.3 | -73.3 | -21.4 |
| `rain_glass` | -52 | -52.0 | -60.1 | -67.1 | -26.2 |
| `rain_leaves` | -52 | -52.0 | -59.9 | -67.1 | -31.0 |
| `drips` | -56 | -56.0 | -63.3 | -71.8 | -33.6 |
| `wind` | -55 | -55.0 | -65.3 | -72.1 | -39.0 |
| `fire` | -54 | -54.0 | -62.2 | -69.0 | -28.5 |
| `gas_hiss` | -58 | -58.0 | -66.0 | -73.1 | -48.5 |
| `hum` | -58 | -58.0 | -66.0 | -73.1 | -47.7 |
| `deep_hum` | -54 | -54.0 | -63.1 | -68.4 | -41.0 |
| `fountain` | -56 | -56.0 | -64.2 | -71.1 | -41.8 |
| `clock` | -56 | -56.0 | -64.0 | -71.1 | -19.9 |
| `tube_whine` | -62 | -62.0 | -70.0 | -77.2 | -55.0 |
| `noise` | -54 | -54.0 | -62.0 | -69.1 | -41.2 |
| `moped` | -52 | -52.0 | -60.0 | | -42.9 |
| `train` | -52 | -52.0 | -60.0 | | -40.6 |
| `huskies` | -54 | -54.0 | -62.0 | | -46.0 |
| `hull_creak` | -52 | -52.0 | -60.0 | | -39.3 |
| `ice_creak` | -55 | -55.0 | -63.0 | | -31.0 |
| `candle` | -58 | -58.0 | -66.0 | | -37.5 |
| `three_bells` | -50 | -50.0 | -58.0 | | -40.1 |
| `vcr` | -54 | -54.0 | -62.0 | | -41.3 |
| `tape_load` | -58 | -58.0 | -66.0 | | -56.5 |
| `rumble`, `gong`, `whale` | -52 | -52.0 | -60.0 | | -41.6, -41.4, -48.4 |
| `tick`, `creak` | -55, -54 | -55.0, -54.0 | -63.0, -62.0 | | -25.4, -35.4 |
| `chime` | -50 | -50.0 | -58.0 | | -40.1 |
| `bird`, `purr` | -54, -56 | -54.0, -56.0 | -62.0, -64.0 | | -40.7, -38.8 |
| `piano` | -51 | -51.0 | -57.0 | -63.9 | -37.6 |
| `organ` | -52 | -52.0 | -56.6 | -62.8 | -35.3 |

Every bed and instrument sits 29 dB or more under the film's reference on its own, and 42 dB or more under it with a
film playing. The test room with its beds at once (the projector, rain on glass, the wall's rumble, ticks, a moped and
a train) measures -47.1 in the pre-show, 9 dB under the target. The peaks that look high (the clock's and the
radiator's ticks, the fire's crackles, the rain's drops) are short clicks; their RMS is low. A one-shot's "in film" is
its designed level less `film_db`, and the duck takes it lower again under a loud scene.

Measured tails (`test_env_acoustics.gd`, a tick through the room's bus, wet only, T30): cinema 0.71 s (set 0.7),
shopfront 0.88 (0.9), concrete hall 2.41 (2.4), stone nave 4.66 (5.0), ice 1.09 (1.1), hull 1.40 (1.4); the
short presets 0.52 to 0.56 (the engine's shortest).

### Ambient life's calls

`life` plays a creature's call through the host (`play_sound`, then `env_audio.play`) at its `voice_db` (default
-12) on Environment, dry: a 3D player with a unit size of 3 m (full level within 3 m, then down 6 dB each time the
distance doubles) and the engine's distance filter (it dulls the highs). `bird` (three falling whistles and a trill,
1.2 s) and `purr` (a pulse about 25 times a second through a low throat, two breaths, 4 s) are in `EnvDoc.SOUNDS`,
so the birds' calls and the cat's purr sound with no change to `life`. Each is made the first time it plays (about
0.05 to 0.1 s on a desktop).

Measured as `life` plays them (`test_env_sound_bed.gd`, 2026-11-07), the loudest second at the slider's default,
in dBFS. "Designed" is the sound's level in `sound_bed`; a call in the film should sit near its "in film" level.

| Call | `voice_db` | Distance | Heard | Designed | In film |
|---|---|---|---|---|---|
| `bird` | -12 | 3 m | -68.5 | -54 | -62 |
| `bird` | -12 | 8 m (a roof's edge) | -81.0 | -54 | -62 |
| `bird`, no distance filter | -12 | 3 m, 8 m | -58.9, -67.4 | -54 | -62 |
| `purr` | -12 | 1.5 m, 4 m | -53.5, -62.0 | -56 | -64 |
| `whale` | -12 | 3 m | -51.2 | -52 | -60 |
| `whale` | -12 | 22 m (the Bathysphere's song) | -68.4 | -52 | -60 |
| `whale` | -14 (the Bathysphere's now) | 22 m | -70.4 | -52 | -60 |
| `whale` | -6, -4 | 22 m | -62.4, -60.4 | -52 | -60 |

The whale sings only in a quiet scene of the film, about 22 m away in the Bathysphere. At -12 it arrives 8 dB under
its "in film" level, at the room's -14 10 dB under. Give the Bathysphere's whale `voice_db` -4: it then sits at
-60, 40 dB under the film's reference and 22 dB under the target. (The level check in `test_env_life.gd`, -53.8 at
-12, measures the stream's first 1.5 s with no distance.) The cat by the seat is 2.5 dB over its designed level at
-12; a cat that sits within 2 m takes -15. The birds lose about 10 dB to the engine's distance filter (they are high);
at 8 m they are 19 dB under their "in film" level even at -12. Without the filter (`attenuation_filter_db` 0 in
`env_audio.play`, as `sound_bed` and `music` have it) a bird at 8 m at `voice_db` -6 arrives at about -61.

### For the rooms

| Room | Use |
|---|---|
| Shopfront 1906 | `acoustics` `shopfront`; `sound_bed` `projector` behind, `gas_hiss`; `music` `piano`, `drive` on `film.transient`, `on` on a setting |
| Streamline 1937 | `acoustics` `cinema`; `music` `organ`, `flourish` in the ritual |
| Pink Palace | `acoustics` `cinema`; `sound_bed` `three_bells` (`play` in the ritual) or the foundation's `chime` |
| Atmospheric 1928 | `acoustics` `cinema`; `sound_bed` `fountain` `at` a niche, `reach` 3, `gain_db` -4 |
| Screen 3, 1983 | `acoustics` `small_room` (`rt60` 0.6); `sound_bed` `wall_rumble`, `level` on `film.bass`, `film_db` 0 |
| Drive-in | `acoustics` `outdoors`; `sound_bed` `crickets` around (`radius` 8); `train` far off, `every` 900, `reach` 300 (its horn is in it) |
| Rooftop, Athens | `acoustics` `outdoors` (`rt60` 0.25, `wet` 0.15); `sound_bed` `cicadas` around, `film_db` -14 (they fade as the film starts); `moped` with `to` and `every`; the cat's purr from `life` (`voice_db` -15 within 2 m) |
| Palace of Culture | `acoustics` `concrete_hall`; `sound_bed` `three_bells` before the show |
| Nave | `acoustics` `stone_nave` (`rt60` 3); `sound_bed` `wind` high up, `gain_db` -4; `candle`, `every` 120, `gain_db` -4. No organ, no bells |
| Reclaimed | `acoustics` `outdoors`; `sound_bed` `rain_leaves` around, `level` on `weather.rain`; `drips`, `level` on `weather.wet`; `wind`, `gain_db` -6; the birds' calls from `life` |
| Ice cinema | `acoustics` `ice`; `sound_bed` `huskies`, `every` 300; `wind` by the doorway; `ice_creak`, `every` 240 |
| Bathysphere | `acoustics` `hull` (`rt60` 0.9); `sound_bed` `hull_creak`, `every` 90, to the sides; `deep_hum`, `gain_db` -4; the whale from `life` at `voice_db` -4 |
| Pillow Fort | `acoustics` `small_room` (`rt60` 0.3); `sound_bed` `radiator`, `rain_glass` on `weather.rain` |
| Screening room 1962 | `acoustics` `small_room` (`rt60` 0.45); `sound_bed` `fire` at the hearth; `hum` at the window (the pool's pump); `three_bells` before the ritual |
| Crater | `sound_bed` `silence`; `acoustics` `vacuum` |
| TV 1930 | `acoustics` `small_room`; `sound_bed` `clock`; `hum`, `gain_db` -4 (the disc's motor). No `tube_whine`: thirty lines on a spinning disc, no tube |
| TV 1953 | `acoustics` `small_room`; `sound_bed` `fire` at the grate (on the Fire setting); `clock`; `rain_glass` on `weather.rain`; `tube_whine` `pitch` 0.648, `gain_db` -4; the cat's purr from `life` |
| TV 1972 | `acoustics` `small_room`; `sound_bed` `radiator`; `clock`; `tube_whine` |
| TV 1983 | `acoustics` `small_room`; `sound_bed` `rain_glass` on `weather.rain`; `tape_load` (`play` in the pre-show: the computer loads); `tube_whine` |
| TV 1987 | `acoustics` `small_room`; `sound_bed` `vcr` (`play` in `starting`: the tape goes in); `clock`; `tube_whine` |
| TV 1993 | `acoustics` `small_room`; `sound_bed` `radiator`, `rain_glass` on `weather.rain`; `vcr` in `starting`; `tube_whine` |
| TV 2005 | `acoustics` `small_room`; no beds (a flat panel is silent) |

## Ambient life

`scripts/env/systems/life.gd`, kind `life`. Animals only, never people. One system is one kind of creature. A room
with moths and a cat has two `life` systems, each with its own id (for example `moths` and `cat`). A cue calls a
creature by that id: `whale.pass`, `cat.settle`.

Each creature is a script in `scripts/env/systems/life/` (the base is `creature.gd`). All are procedural low-poly
meshes on two shaders: `shaders/env_life.gdshader` (unlit with the room's spill; wings, legs, the body's wave and the
head move in the vertex shader) and `shaders/env_life_glow.gdshader` (additive: glowing points and bells). There are
no textures, no live lights and no particles.

| Parameter | Default | What |
|---|---|---|
| `creature` | `moth` | `moth`, `bird`, `firefly`, `cat`, `deer`, `fish`, `jelly` (glowing deep-sea creatures), `whale`, `plane` (a plane's lights). Built once |
| `count` | 0 | how many; 0: the creature's own (below). The cat, the deer and the whale are one at most |
| `region` | null | the box `{min, max}` they keep to, in the room's frame; null: the creature's own |
| `path` | [] | points in the room's frame: the cat's wall top, the deer's and the whale's way (first to last), the birds' perches |
| `size` | 1 | times the creature's own size |
| `speed` | 1 | times its own speed. Live |
| `colour` | null | the body's colour, or the glow's (fireflies, jellies); null: its own. Live, a brightness (it can follow `film.colour`) |
| `glow` | 1 | how bright the lights are (fireflies, jellies, planes). Live, a brightness |
| `attraction` | 0.5 | how strongly they go to the light: moths to the beam, fish and jellies to the screen. Live |
| `activity` | 1 | the share out and about; the rest fade away. For birds: how often they flit. Live |
| `every` | null | seconds between visits on average (the deer, planes, a bird across the roof); 0: only on a cue; null: its own |
| `keep_out` | 0.4 m | how far they keep from the sight line to the picture |
| `personal` | 1.5 m | how far they keep from the viewer's eyes |
| `blink` | true | fireflies flash and a plane's strobe blinks; off: a steady glow. Live. A `flicker` parameter: the common "Flickering lights" setting holds it steady |
| `voice`, `voice_db` | true, -12 dB | a call where the synthesiser has one (now only the whale's song), on the Environment bus |

Actions (each creature does what fits it; args in brackets):

| Action | What |
|---|---|
| `pass` | one goes by now: the whale or the deer crosses, a plane flies over, a bird flies the length of the roof, the cat walks its wall, the school sweeps past (`side`: left or right; `seconds`) |
| `scatter` | they start away and settle again: birds take off and circle, fish dart, moths and fireflies spread, the cat trots off (`from`: [x, y, z]) |
| `settle` | they rest now: birds to their perches, the cat sits, fish and moths slow |
| `call` | one call: a bird's, the cat's purr, the whale's song |

### The creatures

| Creature | Own count | What it does |
|---|---|---|
| `moth` | 40 | pale, 7 cm. They flutter in the projector's beam, between a tenth and three fifths of the way from the lens, lit by the beam. `attraction` is the share that keep to the beam. Without a beam they wander the region |
| `bird` | 6 (40 at most) | dark, 32 cm across the wings. They roost on perches (the path, or the region's top edges), turn now and then, and one at a time flit to another perch on an arc through the open air |
| `firefly` | 60 | yellow-green points low in the region. Each flashes every 1.5 to 6 s (a 0.6 s swell and fall), faint between |
| `cat` | 1 | dark, 42 cm. It walks its wall, sits a while, walks on and turns at the ends. Sitting down it purrs |
| `deer` | 1 | every 300 s on average it comes out of the dark at one end of its path, grazes once or twice, and fades at the far end. By default its way runs past the viewer's left |
| `fish` | 48 | a silver school, 28 cm each. The school's centre wanders the region; `attraction` pulls it to the region's point nearest the screen. They take the screen's light on their flanks |
| `jelly` | 18 | bells of 35 cm that glow at the rim and pulse every 2 to 3 s. Each has a place on a ring round the picture, just clear of the sight line, in front of the screen or behind it |
| `whale` | 1 | 14 m, dark, slow. It comes only when called (`every` 0 by default): a cue on `film.quiet` with a long cooldown. By default its way runs high behind the screen. A third of the way along it sings |
| `plane` | 2 at once | a red, a green and a white light and a soft white strobe every 1.5 s, on a great circle 160 m out, 17 to 52 degrees up. A crossing takes a minute or two. One every 75 s on average |

The flashes and the strobe are slow swells, far under the photosensitivity limit. With `blink` off or the room's
"Flickering lights" setting off, they glow steady.

### Out of the viewer's face and the sight line

- **The sight line** is the pyramid from the viewer's eyes to the picture's edges, widened by `keep_out`, from the
  eyes to the screen's plane. The eyes are the camera's; without a camera, the room's seat nearest the origin, 1.2 m
  up. It follows the screen when the viewer moves or resizes it.
- **Fliers and swimmers** (moths, birds, fireflies, fish, jellies) are pushed out of the pyramid every frame, and out
  of a `personal` sphere round the eyes.
- **Walkers** (the cat, the deer, the whale) follow their path. In the sight line they never stop, and go 2.5 times
  faster. The test holds each walker's longest time in the sight line under 4 s.
- **Moths in the beam** use the part of the beam over the viewer's head, outside the pyramid.
- **The Ambient life setting** (common, `life`): off, every creature fades away over 1.5 s; on, they fade back.

### Film reactions

The system reads no film signal itself. A room binds the live parameters in its document, so the host computes only
the channels a room uses. Suggested bindings:

| Creature | Binding |
|---|---|
| fireflies | `glow`: `{"bind": "film.brightness", "range": [1.0, 0.2], "smooth": 1}`: they dim while the film is bright |
| fish, jellies | `attraction`: `{"bind": "film.brightness", "smooth": 2}`: they come closer in a bright scene |
| jellies | `colour`: `{"bind": "film.colour", "strength": 0.5, "base": "#59bfff", "smooth": 1}` |
| birds | `activity`: `{"bind": "time.of_day"}`: they roost at night |
| planes | `activity`: `{"bind": "time.of_day", "invert": true}`: lights at night only |
| the whale | a cue: `{"when": {"signal": "film.quiet", "above": 0.9, "for": 4}, "states": ["playing"], "cooldown": 900, "steps": [{"do": "whale.pass"}]}` |

### Sounds

The whale's song, a bird's call and the cat's purr are sounds: the synthesiser's `whale`, `bird` and `purr`, from
where the creature is, on the Environment bus. Each is also an event (the signal `creature_event(what, at)` and the
list `events`). At the default `voice_db` (-12) the whale's song measures -53.8 dBFS RMS over its first 1.5 s, with
no distance, under the -38 dBFS target. As heard at a distance, and the `voice_db` to give each: "Sound and music",
"Ambient life's calls".

### The film layer

On the Frame the film layer is drawn over anything between the eyes and the picture. Ambient life does not make the
layer step aside. Instead, no creature goes into the sight line, so nothing of it is hidden and the film stays sharp.
Only a walker whose path crosses the sight line can be in it, and only while it trots through; on the Frame it is
hidden there for that moment. Rooms should give walkers paths clear of the sight line.

### Cost

Each creature is one draw: a MultiMesh for the many, one mesh for the cat, the deer and the whale (the sight-line check
puts a MultiMesh's base mesh at every seat). Measured at the own counts (`test_env_life.gd`):

| Creature | Triangles | Ticks (desktop, ms a frame) |
|---|---|---|
| moths | 240 | 0.37 |
| birds | 186 | 0.01 |
| fireflies | 120 | 0.24 |
| fish | 1632 | 0.22 |
| jellies | 1080 | 0.11 |
| planes | 16 | 0.01 |
| the cat | 86 | 0.01 |
| the deer | 98 | 0.01 |
| the whale | 102 | 0.00 |

All nine at once: 9 draws, about 3600 triangles, under 1 ms a frame on the desktop. The spec declares the largest (fish,
1700 triangles); 200 fish would be 6800. The time on the Frame is not measured yet.

### For the rooms

| Room | Use |
|---|---|
| Drive-in | `moth` in the beam; `plane` with `activity` bound to `time.of_day` inverted |
| Rooftop Athens | `cat` with a `path` along the wall top, clear of the sight line; `plane` |
| Reclaimed | `bird` with perches on the broken roof's edge; `firefly` low over the floor, `glow` bound to `film.brightness`; `deer` with a path along a side aisle |
| Bathysphere | `fish` and `jelly` outside the glass, `attraction` bound to `film.brightness`; `whale` on the quiet-scene cue, its `chance` set by the room's whale setting |

## The sky and the vista

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
| `water_motion` | 0.5 | how fast the light ripples in the pool (motion, at most 1) |

| Shape | Default | What |
|---|---|---|
| `hills` | all round, 160 m | a low dark ridge on the horizon |
| `mesas` | 140 degrees, 165 m, 6 | flat-topped rocks with steep sides |
| `acropolis` | 18 degrees, 150 m, 160 lamps | a hill with a flat top and a wall, a ruined temple of columns and a smaller one, floodlit from below; a town's lamps at its foot |
| `birches` | 120 degrees, 40 m, 40 trees | white trunks with dark marks and bare branches, on snow |
| `cypresses` | 90 degrees, 30 m, 14 trees | tall, narrow, flame-shaped dark trees |
| `pool` | 14 m | a pool glowing from below, its coping, a lawn that takes its glow, a hedge behind |

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
| Atmospheric 1928 | `auditorium` with `ceiling_cover` 0; `sky` at twilight (`dusk` 0.4..0.6), `lines` off, `clouds` 0.3 with `cloud_colour` bound to `film.colour`; `vista` cypresses over the walls (as `test_env_vista.gd`'s courtyard) |
| Drive-in 1958 | `sky` with a dusk track by `film.minutes`, `milky_way` bound to `playback.playing`; `vista` mesas all round |
| Rooftop, Athens | `sky` (`latitude` 38, a summer night); `vista` acropolis ahead, a little to one side |
| Palace of Culture | `vista` birches in snow outside the windows; `snow` bound to the room's snow setting |
| Reclaimed | `sky` through the open roof: stars, `clouds` bound to `weather.wet` |
| Ice cinema | `sky` with `aurora` bound to `film.quiet` (smooth 2), `aurora_bearing` where the room opens to the sky |
| Crater | `sky` `mode` `space`, `earth` on, `earth_turn` from the Earth's speed setting, `milky_way` bound to `playback.playing` |
| Screening room 1962 | `vista` pool behind the window, `pool_glow` 1 |

## A room's screen and its builder

A document gives the screen (`screen`: centre, size, curve). Two things follow from it in `env_room.gd`:

- **Its curve.** `get_home_curve()` gives `screen.curve` (0..1), and the app's screen starts with it until the viewer
  sets a curve of their own (`scripts/play/curved_screen.gd`). A flat screen in a room that curves by itself is kept
  as 0, so it stays flat.
- **A builder that moves it.** A builder with a static `screen_for(params)` (shopfront, nave, dome_hall, domestic)
  says where it puts the picture. The room takes that place for the document's parameters (with every room setting at
  its default) as the document's own; when a setting rebuilds the room (`env_host.gd` signal `rebuilt`), the screen
  moves and resizes by the builder's change, and the app places the film there again (the seat's `home_screen()`).
  Tested in `app/tests/test_env_screen_follow.gd`.

## The converted cinema

`app/environments/cinema.env.json` with `cinema.tscn` and a thin `cinema.gd`. It looks the same: the render test
(`tests/test_env_cinema_render.gd`, lavapipe) draws the old cinema (`tests/fixtures/cinema_v3.gd`, the room as code
before the conversion) and the new from the seat and from the aisle and compares them pixel by pixel. The bake hooks
(`static_meshes`, `bake_lights`, `set_baking`, `set_baked`) come from the light system, so the headset's bake path is
as before. Settings: the pre-show ritual (common), the house lights in the film.

## The Void

`app/environments/void.env.json`: a black sky (nothing drawn), a mirror-black floor that takes the film's reflection
(on by default), and a small ripple where the viewer's head moves more than 15 cm a second over the floor. Setting:
the ripple's strength. Sound: none but the film's, and it says so (`sound_bed` `silence`, `acoustics` `vacuum`: dry).

## The presentation system

`scripts/env/systems/presentation.gd`, with `shaders/env_presentation.gdshader` and its stages in
`env_presentation.gdshaderinc`. The stages between the film and the eyes, each optional. One per room.

| Stage | Parameters | What |
|---|---|---|
| source | `source`: `none`, `film`, `tape`, `broadcast` | where the picture comes from |
| film | `weave`, `tilt` (degrees), `flicker`, `dust`, `scratches`, `hotspot` | gate weave, a crooked projector (the picture is overscanned a little, so no corner shows), the lamp's flicker, dust specks, scratches that run for a few seconds, the lamp's bright middle |
| tape | `tracking`, `head_switch`, `chroma_bleed`, `tape_noise` | the lines' slow sway, the torn last lines at the bottom, the colour late and smeared, noise and paler colour |
| broadcast | `interlace`, `lines` | the two fields' lines, one after the other |
| transmission | `snow`, `ghost`, `ghost_shift`, `weak` | aerial noise, a faint second picture to the right, a weak signal (paler, flatter, more snow) |
| display | `display`: `none`, `mechanical`, `crt`, `panel` | the set |
| crt | `curvature`, `corner`, `tube` (the tube's aspect: 1.33 in the sets before 2000; 0 the picture's own), `mask` (`none`, `shadow`, `grille`, `slot`), `mask_pitch`, `mask_strength`, `scanlines`, `glass` | the bulging face, round corners, the phosphors' mask, the gaps between lines, the glass's reflection (a soft light behind the viewer that moves as the head moves) |
| mechanical | `mech_lines` | a 1930 mechanical-scan set: a few lines across, a neon's orange glow, dark edges |
| panel | `panel_grid`, `panel_pixels`, `panel_bleed` | the gaps between the pixels, the backlight through the dark scenes |
| colour | `colour`, `tint`, `gain` | saturation (0: black and white), the tube's tint, brightness |
| speaker | `speaker`: `none`, `window`, `telly`, `cabinet`, `panel` | the film's sound through a small speaker |

Every parameter is live. `weave`, `tilt` and `tracking` are motion parameters (the room's Motion setting scales
them). `flicker` is a brightness that flickers: it wavers by at most 3.5 %, more slowly than 3 times a second, and
stays steady with Flickering lights off. Action: `glitch` (a moment's trouble: a tape's tracking tears, a broadcast's
snow swells, a print jumps in the gate; `seconds`, default 0.6).

**Presets.** `preset` fills every parameter the document leaves out. The document's own values and bindings win. To
move a preset's value by a cue, give it in the document. The names are pastiche.

| Preset | For | Chain |
|---|---|---|
| `worn_print` | Screen 3, 1983 | film: weave, a 0.35 degree tilt, flicker, dust, scratches, a hotspot |
| `starlight_lot_1958` | Drive-in | film: a little weave and dust, a strong hotspot; the window speaker |
| `glowbox_1930` | TV era | a mechanical-scan set: 30 orange lines, a little noise; a radio cabinet's speaker |
| `fireside_1953` | TV era | broadcast, 405 lines, snow and a ghost; a small black and white tube with round corners |
| `colourstar_1972` | TV era | broadcast, interlace, a faint ghost; an early colour tube with a shadow mask, warm and rich |
| `sirclive_1983` | TV era | a home computer's aerial lead: 240 bold lines, a little noise; a portable telly's shadow mask |
| `rewinder_1987` | TV era | a rented tape: wobble, bleed, the bottom's tear; a slot mask |
| `nightowl_1993` | Pillow Fort | a tape watched a few times; a flatter tube with an aperture grille |
| `freedtv_2005` | TV era | a free digital broadcast on an early flat panel: a faint pixel grid, backlight bleed |

**How the film is drawn.** On the Frame the film is an OpenXR layer, and a layer skips the scene's shaders. So while a
picture stage is on, the screen's flat mesh draws the film with the presentation's material, and the film layer
steps aside: the system asks with `film_layer.gd request_scene()`; no layer is made while any room asks, and the
System tab says why. The material is the screen's own picture (`video_common.gdshaderinc`, its uniforms copied from
the screen's material when they change), then the stages. With every picture stage off (the Drive-in with only its
speaker) nothing changes, and the film layer stays. Leaving the room puts the screen's material back. Flat screens
only: 180, 360 and fisheye films keep the screen's own picture. The floor reflection and the bias light read the
video planes, so they show the film without the stages.

**The sound.** A bus of its own, "Film speaker", made once just before Film (a bus can send only to one before it).
While a speaker is on, Film sends to it and it sends to Master: a high-pass and a low-pass filter, an EQ, a little
drive for the window speaker, and mono. The binaural renderer's code is not touched; it mixes into Film as before,
and the speaker filters what Film sends on. Effects on the Film bus itself were rejected: adding one makes the engine
make every effect on that bus again, so the film's analysis (`film_react.gd`, the music card) would lose its analyser.
The film's analysis and the duck's key stay on Film, so they hear the film as it is. Measured
(`test_env_presentation.gd`, a tone at -20 dBFS RMS on Film): the window speaker takes an 80 Hz tone to -107 dBFS
and leaves 1 kHz at -18.4 dBFS.

**Cost.** The system draws nothing of its own (0 draws). Its cost is the film drawn in the room instead of the
layer: on the Frame the layer saved 1.1 ms of GPU time with a 4K film (`docs/features.md`, "Film layer"), and the
mesh path is resampled twice (softer fine detail). The stages add little: no loop and no texture read of their own,
except one cheap sample each for the ghost and the chroma bleed (and the screen's deband is turned off under noise,
which saves eight). Every pattern (a mask, scanlines, a pixel grid) fades out as its period nears two eye-buffer
pixels, so it never shimmers; a telly's mask shows only when you lean in. Measured under lavapipe (CPU, so ALU counts
more than on a GPU), the screen's quad filling 1920 x 1080, frame time against the screen's own shader (18.8 ms;
the figures move by about 10 % from run to run):

| Preset | x |
|---|---|
| `glowbox_1930` | 0.75 |
| `fireside_1953`, `colourstar_1972`, `sirclive_1983`, `rewinder_1987`, `nightowl_1993` | 0.88 to 0.97 |
| `worn_print`, `starlight_lot_1958` | 1.0 to 1.05 |
| `freedtv_2005` | 1.14 |

The noisy chains cost less than the screen's own shader because its deband (eight reads) is off under them; with the
deband left on they measured 1.45 to 2.2 times. On the Adreno the screen's shader is bound by its texture reads (the footprint filter, the deband); the stages are
ALU of a few dozen operations and at most two more bilinear reads, and a telly covers a small part of the view (a
0.6 m set at 1.5 m is about 6 % of an eye's pixels). Not measured on the headset yet.

## The cinema set

Every room keeps the cross-cutting rules: a "dim during the film" setting, seat picking by pointing, its own
acoustics, music only from our synthesiser or CC0 samples (many sample sets are CC-BY and cannot be bundled), no
people.

| # | Room | Builders and kits | Light, sky, atmosphere | Life, sound, music | Timeline and cues | Screen | Settings |
|---|---|---|---|---|---|---|---|
| 1 | Shopfront picture house, 1906 | `shopfront` (pressed tin), folding chairs (`seats`), a tin booth (`kit`) | gas lamps (`light`, flicker), a dusty beam (`screen_frame`, `atmosphere`) | projector clatter behind (`sound_bed`), a player piano that plays along (`music`, `film.transient`) | the piano starts in `starting` | a framed sheet | piano on or off |
| 2 | Atmospheric, 1928 | `auditorium` with `ceiling_cover` 0, courtyard façades, niches with statues, a castle gate (`kit`, `proscenium` slot) | open twilight `sky` with real constellations, clouds lit by the screen (`film.colour`), cypresses (`vista`) | | curtains part (`showing`) | | clouds |
| 3 | Streamline, 1937 | `auditorium` with cream faience bands (`wall_treatment` slot), brass ashtrays (objects) | cove lights that cycle colours and then follow the film (`light`, `film.colour`) | an organ (`music`) | the organ rises from the pit (`motion`) as the ritual | a festoon curtain (`proscenium` slot) | cove colours |
| 4 | Screen 3, 1983 | `auditorium` with `partition_z` (a subdivided balcony), plasterboard, swirly carpet, one broken seat, a water stain (picture) | smoke haze in the beam (`atmosphere`), a flickering exit sign (`flicker`) | rumble through the wall (`sound_bed`, `film.bass`) | | gate weave, a slight tilt (`presentation`) | weave and tilt |
| 5 | Drive-in, 1958 | `terrace` (the lot), a convertible's bench seat (`vehicle`), a screen tower, a neon snack bar (`kit`) | dusk to stars over the film (`sky`, film-time tracks), mesas (`vista`) | moths in the beam (`life`), a far freight train (`sound_bed`, `every`) | | the window speaker (`presentation`) | tinny speaker |
| 6 | Screening room, 1962 | `domestic` (walnut), club chairs (`seats`), a bar cart (objects) | a pool glowing through the window (`vista`) | | a painting slides up to show the screen (`motion`, ritual) | | |
| 7 | Rooftop summer cinema, Athens | `terrace`, director's chairs, bougainvillea (`kit`) | a floodlit acropolis on its hill (`vista`), plane lights (`life`) | cicadas and mopeds (`sound_bed`), a cat on the wall (`life`) | | a screen painted on a wall | |
| 8 | Pink Palace | `auditorium` with pink and blue curves (`kit`), a plush balcony (`balcony_rows`) | a sunburst ceiling with cycling lights, chandeliers (`light`) | | a ceremonial curtain (`showing`) | | |
| 9 | Palace of Culture, 1974 | `auditorium`, board-marked concrete, ochre curtains | a mosaic wall that glitters in the screen's light (material, `film.colour`), snow and birches outside (`vista`, `weather`) | an echoey hall (`acoustics`) | | | snow |
| 10 | Flagship | `auditorium`: steep rake, black walls | blue step lights (`light`) | | the ritual | a huge curved screen | seat choice |
| 11 | Nave | `nave`, pews (`seats`) | a dim rose window, candles (`light`, flicker), the film's light climbing the stone | reverb (`acoustics`) | | in the chancel | candles |
| 12 | Reclaimed | `auditorium` with `ceiling_cover` 0.5, ivy and ferns (`kit`) | stars (`sky`), dynamic `weather` (rain into a puddle that reflects the film) | birds, fireflies, an occasional deer (`life`) | | a patched sheet | weather |
| 13 | Ice cinema | `domestic` of ice blocks, hides (`seats`) | the room glowing in the film's colours, an aurora that swells in quiet scenes (`sky`, `film.quiet`), breath fog (`atmosphere`) | far huskies (`sound_bed`) | | | aurora |
| 14 | Bathysphere | `dome_hall` (glass) | caustics (`light`) | fish, glowing creatures drawn to the screen, a rare whale in a quiet scene (`life`, cue with `cooldown`), hull creaks (`sound_bed`) | | | whale |
| 15 | Crater | `terrace` (a lunar amphitheatre) under a `dome_hall` | Earth turning over the film (`sky`, film-time track), the Milky Way when the lights dim | silence (no bed) | | | Earth's speed |
| 16 | Void | `mirror_floor` | black | | | | ripple |
| 17 | Pillow Fort, 1993 | `domestic` (cushions, a bedsheet), a tree, a tin of sweets (objects) | fairy lights (`light`, flicker), rain on the window (`weather`) | a ticking radiator (`sound_bed`) | the VCR flashes 12:00 (object widget) | a CRT telly (`presentation`, TV-era display) | the telly fills the opening |

### Room: Atmospheric 1928

`app/environments/atmospheric_1928.env.json`. A picture palace built as a courtyard under a twilight sky: plaster
houses with lit windows and iron balconies along both walls, niches with lions, urns and obelisks between them, a
castle gate round the screen, cypresses over the walls.

- **Systems:** `light`; `auditorium` (`ceiling_cover` 0, walls 7.5 m, `proscenium` none, plain plaster walls, plush
  seats 0.6 m apart, 25 a row); `screen_frame`; `showing`; `kit` (the castle gate, columns in the front corners, and
  on the 14 side-wall places, in turn: niches with lions, façades the walls' full height, niches with urns,
  façades, niches with obelisks, façades, niches with urns); `sky` (latitude 37, mid July, 21:30, `dusk` 0.4, no
  constellation lines, the Milky Way at 0.5); `vista` (cypresses 15 m out at the front corners and behind, hills).
- **Setting:** Clouds (0 to 100 %, 40 % by default): `sky.clouds` by `range` [0, 0.8]. The clouds' own colour
  follows `film.colour` (strength 0.4, smooth 1 s), and `cloud_screen` 1.2 lets the ones towards the screen catch
  its light.
- **Cues:** `ritual` (starting, Pre-show on): the house lamps to half over 1.5 s, the curtains part over 4 s, the
  dusk deepens from 0.4 to 0.8 over 10 s, then the lamps to 12 % and the steps to half over 5 s. `dim` (Pre-show
  off): the same without the curtains. `lights_up` (pre-show, ended): the lamps, the steps and the twilight back.
- **Default seat:** the middle of row 0 (7 rows in front, 3 behind).
- **Measured** (`test_room_set2.gd`): 26 draws, 199 724 triangles, no live light, no particles, 9.4 MB.

### Room: Palace of Culture 1974

`app/environments/palace_of_culture_1974.env.json`. The cinema hall of a civic palace of culture: board-marked
concrete, mosaic panels on the side walls that take the screen's light, ochre curtains, straight rows on a parquet
rake, and the back of the roof open to a winter night with birches and falling snow.

- **Systems:** `light`; `auditorium` (22 x 22.6 m, 10 m high, 8 rows in front and 4 behind, straight, 29 seats a
  row in woven red with oak arms; `concrete_panels` walls and ceiling; six panels a side of `terrazzo` in muted gold
  with `spill` 5 (the concrete's is the light's 3), steel rails; ochre velvet drapes; `ceiling_cover` 0.76: open
  from just behind the viewer's row); `screen_frame`; `showing`; `sky` (latitude 56, mid January, full night,
  grey clouds); `vista` (birches 14 to 18 m out behind and to both sides, hills); `weather` (`falls` snow, 1400
  flakes, one area under the open roof, from z 2.2 to the rear wall).
- **Setting:** Snow (no snow, light, heavy; light by default): `weather.mode` (clear, light, heavy), `sky.clouds`
  (0.2, 0.55, 0.85) and `vista.snow` (0.8, 1, 1), each by `map`.
- **Cues:** `ritual`: the lamps to half over 2 s, the curtains part over 5 s, then the lamps to 10 % and the steps
  to half over 6 s. `dim` and `lights_up` as in the Atmospheric.
- **The mosaic:** no library material or shader option sparkles yet; the mosaic is terrazzo that takes more of
  the film's light (its colours) than the walls round it.
- **The snow and the picture:** the snow falls only under the open roof, behind the default seat, so nothing falls
  between the viewer and the picture from there; from the back rows it falls round them.
- **Default seat:** the middle of row 0.
- **Measured:** 23 draws, 256 688 triangles, 1400 particles, 12.4 MB.
- **Sound:** an echoey hall (`acoustics` `concrete_hall`: rt60 2.4, a 60 ms predelay and its echo); the house bells
  (`sound_bed` `three_bells` by the stage, played by the ritual's first step: once as the film starts, none with the
  Pre-show off). Measured (`test_room_set2.gd`): the bells' loudest second -52.2 dBFS at the slider's default,
  14 dB under the level check's target; nothing else sounds.

### Room: Flagship

`app/environments/flagship.env.json`. A large modern cinema: black walls and ceiling, a steep stadium rake, blue
step lights, deep red seats, and a 20 m curved screen.

- **Systems:** `light` (a cool fill); `auditorium` (26 x 27 m; 7 rows in front and 6 behind, 1.25 m deep and
  0.55 m higher each: a 24 degree rake; rows curving round a point 30 m ahead; 25 seats a row, 0.62 m apart; black
  felt walls and stage, black foam ceiling, black drapes, dark metal rails; `step_colour` blue; no sconces);
  `screen_frame`; `showing`.
- **Screen:** 20 x 8.4 m, its middle at the seated eyes' height, 18.2 m from the default seat (0.9 of its width),
  `curve` 0.3.
- **Cues:** `ritual`: the lamps to 40 % over 2 s, the curtains part over 6 s, then the lamps out and the steps to
  35 % over 5 s. `dim` and `lights_up` as above.
- **Seat choice:** the default seat is the middle (row 0, with 7 rows in front and 6 behind). The front-middle
  and the back are the other good seats; the viewer picks them by pointing.
- **The curve (since 2026-11-07):** `env_room.gd get_home_curve()` gives the document's `screen.curve`, and the
  screen starts with it until the viewer sets a curve of their own (`curved_screen.gd`; flattening it keeps 0, so the
  room stays flat). A setting still cannot choose the default seat: the room starts at its origin seat.
- **Measured:** 17 draws, 228 806 triangles, 6.0 MB.
- **Sound:** no beds: a modern hall is quiet but for the film. Its acoustics are drier than the `cinema` preset (rt60
  0.5, damping 0.8, wet 0.12: black felt and foam), for any room sound to come; the film keeps its own mix.

### Room: Shopfront 1906

`app/environments/shopfront_1906.env.json`. A narrow picture house in a shop: pressed tin, folding chairs and gas
lamps, the film on a framed sheet. Its test: `tests/test_room_picture_houses.gd`.

- **Systems:** `light`; `shopfront` (id `hall`): a 5.6 m hall 4.2 m high, the sheet 4.4 x 2.5 m at 7.4 m, 5 rows in
  front of the viewer's and 3 behind, the tin an aged cream, gas lamps with `flicker` 0.6; `seats` (folding chairs
  in the builder's slots); `kit` (a tin booth in the back corner's `booth` slot); `screen_frame` (no black masking:
  the sheet's frame; the beam from the booth's window); `atmosphere` (`beam_haze` 0.4, `beam_dust` 0.7).
- **Setting:** `piano` (Player piano, on). Declared now; it binds to the `music` system's player piano when sound is
  merged.
- **Cues:** `ritual` (starting, Pre-show on): the gas down to half over 2 s, then to 18 % over 5 s, the street's glow
  through the shop window down with it. `dim` (Pre-show off): the gas to 18 % over 3 s. `lights_up` (pre-show, end):
  the gas up over 4 s, the street's glow back.
- **Measured** (headless): 17 draws, 10 168 triangles, no lights, no particles, 8.4 MB; 63 seats.
- **Sound to come:** the projector's clatter from the booth behind (a bed, low); a player piano by the screen that
  starts in `starting` and plays along, answering `film.transient`, under the film.

### Room: Streamline 1937

`app/environments/streamline_1937.env.json`. A streamline cinema: warm plaster with cream faience bands, jade drapes,
a gold festoon curtain, an organ console that rises from the pit, and cove lights that change colour. Its test:
`tests/test_room_picture_houses.gd`.

- **Systems:** `light`; `auditorium` (id `hall`): the cinema's hall with plain walls, plush seats (25 a row, 0.6 m),
  a jade-green carpet, jade drapes, a black marble stage, the house lamps and the step and stage lights in the cove
  colour; `kit` (id `console`): three moulded panels below the pit's floor, the organ console; `kit` (id `bands`):
  three `curves` pieces a wall, flattened into long bands of cream with jade and gold, 3 to 4.4 m up; `motion` (id
  `organ`): the console 2.15 m up out of the pit (0.25 m/s); `motion` (id `festoon`): a gold festoon of 6 swags over
  the screen, at the motion limits (0.5 m/s, 0.3 m/s²); `screen_frame`; `atmosphere` (id `cove`): `beam_haze` 0.2 and
  two thin fog layers under the ceiling, the cove's glow in the setting's colour, shown out of the film; `atmosphere`
  (id `cove_film`): the same layers in the film's colour (`film.colour`, strength 0.85), shown in the film.
- **The console** is the `console` kit's mesh, so this kit comes before `bands` in the document: the kit's mesh is
  named `PieceStatic`, and a second kit's mesh of that name is renamed when it is added. The console's top stays
  under the sight line to the picture's bottom from the front row when it is up (the test checks the sight line with
  it up).
- **Setting:** `cove` (Cove colours: Changing, Gold, Rose, Jade, Blue). It sets the house lamps' and the step lights'
  colour (the room builds again) and the cove's glow. With Changing, the glow goes gold, rose, jade, blue in turn
  (`cove_cycle`, every 20 s in the pre-show, paused, at the end and in the intermission).
- **Cues:** `ritual` (starting): the lamps to half, the console rises over 10 s, the festoon rises, the lamps to 15 %
  over 5 s. `organ_down` (playing): 30 s on, the console goes back into the pit. `dim` (Pre-show off). `lights_up`
  (pre-show, end): lamps up, the festoon and the console down. With Pre-show off the festoon rises by itself 4 s into
  the film (the motion system's in-front rule).
- **Measured** (headless): 27 draws, 182 676 triangles, no lights, no particles, 8.0 MB; 275 seats.
- **Sound to come:** an organ (`music`) that plays as the console rises and stops as it sinks, under the film.

### Room: Pink Palace

`app/environments/pink_palace.env.json`. A picture palace in pink: pink and blue waves on the walls and across the
ceiling, a plush balcony, lamps that swell and fall before the film, and a ceremonial curtain. Its test:
`tests/test_room_picture_houses.gd`.

- **Systems:** `light`; `auditorium` (id `hall`): plain dusty-pink walls, a pale pink ceiling with its panels, a rose
  carpet, pink drapes, plush seats in rose velvet (25 a row), rows 0.85 m deep, a balcony of 3 rows; `kit`: a long
  `curves` piece on each side wall (pink and blue), four across the ceiling between its panels, a pink `balcony_front`
  on the balcony; `screen_frame`; `showing` (the pre-show's curtains).
- **The screen** is 0.3 m higher than the cinema's (centre 1.9 m) and the rows 0.85 m deep: the balcony's front row
  then sees the bottom of the picture over the balcony's parapet. The `balcony_front` piece is 0.8 m high for the
  same reason.
- **Cues:** `sunburst` (every 10 s in the pre-show): the ceiling's lamps fall to 55 % over 4 s and rise again over 4 s.
  `ritual` (starting): the chime, the lamps to half, the curtains part over 5 s, then after 6.5 s (after any `sunburst`
  still running) the lamps to 15 % over 5 s. `dim` (Pre-show off): the same wait, then 15 % over 3 s. `lights_up`.
- **Settings:** none of its own (the common ones).
- **Measured** (headless): 22 draws, 234 504 triangles, no lights, no particles, 9.0 MB; 356 seats.

### Room: Nave

`app/environments/nave.env.json`. *A stone nave at night: pews, candles either side of the screen in the chancel, a
dim rose window, and the film's light on the columns.*

- **Systems:** `light` (spill 4.5, so the stone and the columns take the film's light; a low warm fill), `nave`
  (the chancel at z -6.5, 4 m deep; 4 pews in front of the viewer's and 5 behind, 9 places each; the screen 6.4 x 3.6
  m under the chancel arch, its bottom 1.6 m over the nave's floor; rose glow 0.25; darker stone and columns),
  `seats` (the pews in the nave's slots), `screen_frame` (masking, no beam).
- **The viewer:** the middle place of the fifth pew, at the origin; four pews' backs in front, under the picture.
- **Setting:** Candles (`candles`: none, a few, many) maps onto `nave.candles` (0, 2 or 4 stands a side; the nave
  builds again). The candles flicker (common Flickering lights).
- **Cues:** `rose_dims` (starting: the rose window to 0.15 over 6 s), `rose_up` (pre-show and end: back over 5 s).
- **Measured** (`tests/test_room_set5.gd`, headless): 14 draws, 8 290 triangles, no live light, 7.0 MB.
- **Sound:** a long stone reverb on the room's own sounds (`acoustics` `stone_nave`, rt60 3); a faint wind high in
  the clerestory (`sound_bed` `wind`, two voices 9 m up, `gain_db` -4); now and then a candle's gutter by the chancel
  (`candle`, `every` 120, `gain_db` -4, its `level` on the Candles setting: none with no candles). No organ, no bells.
  The film's own `acoustics` section stays modest (rt60 1.6, wet 0.4) so speech in the film stays clear. Measured
  (`test_room_set5.gd`, the slider's default, a candle playing): -55.3 dBFS RMS in the pre-show, -70.5 under a film
  at the reference level.

### Room: Reclaimed

`app/environments/reclaimed.env.json`. *An old picture house taken back by nature: half its roof gone to the stars,
ivy on the walls, ferns in the corners, rain into a puddle that gives back the film, birds on the broken roof,
fireflies and now and then a deer.*

- **Systems:** `light` (a cold moonlit fill; the house lamps, step lights and signs dead; no bake: its lamps are
  dead), `auditorium` (16 x 15.6 m, `ceiling_cover` 0.5: the roof open from z -2.2 back, over the viewer; the viewer
  in the front row, 3 rows behind, 21 plush seats a row, faded and uneven; plain painted brick walls; no sconces, no
  acoustic clouds; a low stage with dark drapes), `screen_frame` (no masking; the projector's beam from the booth),
  `kit` (ivy on six places of the side walls, ferns in the pit's corners, by the stage and in the side aisles),
  `seats` (8 broken seats over the hall's own), `sky` (a September night at 52 degrees north; clouds bound to
  `weather.wet`), `weather` (the mode from the Weather setting; rain through the open roof and a few leaks over the
  pit; a puddle in the pit in front of the viewer, its reflection bound to `weather.wet`), `atmosphere` (a little
  haze in the beam; mist bound to `weather.wet`), `life` `birds` (8, perched on the broken roof's edge and the
  walls' tops), `fireflies` (30, low; they dim while the film is bright and hide in the rain), `deer` (down the left
  side aisle from the back, about every 8 minutes).
- **The puddle:** the viewer sits in the front row so nothing hides the pit; the eye mirrored in the puddle's plane
  sees the picture's middle 3.6 m ahead, in the puddle (the test works it out).
- **Setting:** Weather (`weather`: changing, rain, mist, clear) maps onto `weather.mode` (changing, heavy, light,
  clear); mist is a drizzle, and the mist rises with the wet.
- **Cues:** `birds_start` (a loud bang while playing: the birds scatter; chance 0.6, at most every 3 minutes),
  `deer_in_quiet` (6 s of a quiet scene: the deer comes; chance 0.5, at most every 15 minutes).
- **Measured** (`tests/test_room_set5.gd`, headless): 30 draws, 116 858 triangles (the ivy and the plush seats),
  no live light, 1 600 particles, 10.4 MB. Its update: about 0.2 ms a frame on the desktop.
- **Sound:** open air (`acoustics` `outdoors`); rain on the leaves round the viewer (`sound_bed` `rain_leaves`, four
  voices under the open roof) and on the boards behind (`rain_leaves` at `pitch` 0.7, `gain_db` -6), both with their
  `level` on `weather.rain`; drips into the puddle after it (`drips`, `level` on `weather.wet`); a soft night wind
  (`wind`, `gain_db` -6). The birds' calls are the birds' own (`life`). Measured (`test_room_set5.gd`, the slider's
  default, rain and wet at full): -49.9 dBFS RMS in the pre-show, -64.0 under a film at the reference level.
- **Gaps:** the auditorium has no screen surface of its own, so there is no patched sheet: the picture hangs on the
  black front wall with no masking (a sheet like the shopfront's `sheet_frame` would need a parameter on the
  auditorium). Its walls have no damp or stain parameter.

### Room: Ice cinema

`app/environments/ice_cinema.env.json`. *A small room of ice blocks under a low vault: hides on ice benches,
candles in the walls, the film's colours in the ice, and the northern lights in the window in quiet scenes.*

- **Systems:** `light` (spill 4.5, so the ice glows in the film's colours; a cold low fill), `domestic` (style
  `ice`: 6 x 9 m, the picture 3.2 x 1.8 m on a smoothed panel of the front wall; a 2 m window in the left wall and
  the open doorway behind, both to the night sky), `seats` (`hide` on every place: 5 a row, a row in front, two
  behind), `sky` (68 degrees north, a January night, the aurora over the east, where the window looks out),
  `atmosphere` (breath 0.6, a thin ground fog).
- **Setting:** Aurora (`aurora`: in quiet scenes, always, off) maps onto `sky.aurora` (0.15, 0.8, 0).
- **Cues:** `aurora_swells` (2 s of a quiet scene, the setting on "in quiet scenes": the aurora to full over 8 s),
  `aurora_settles` (the quiet ends: back to the setting's level over 12 s). The swell is a cue rather than a binding
  on `film.quiet`, so the setting can still give the aurora's level.
- **Measured** (`tests/test_room_set5.gd`, headless): 17 draws, 15 976 triangles, no live light, 16 particles, 6.5
  MB.
- **Sound:** the ice's bright ring (`acoustics` `ice`); far huskies beyond the doorway now and then (`sound_bed`
  `huskies`, `every` 300, 120 m out); a soft wind past the doorway (`wind` at the doorway, `gain_db` -3); the ice
  creaking in the wall now and then (`ice_creak`, `every` 240). Measured (`test_room_set5.gd`, the slider's default,
  both one-shots playing): -54.6 dBFS RMS in the pre-show, -69.7 under a film at the reference level.
- **Gaps:** the ice room opens only to the sides and behind, so the aurora shows in the window and the doorway,
  not over the screen; a skylight or an opening in the vault would need a parameter on `domestic`.

### TV-era rooms

The same `presentation` chain makes the TV-era rooms: source (a broadcast, a tape, a disc), transmission (aerial
noise, ghosting, a weak signal), display (a mechanical-scan set's orange glow, 1930; a round-cornered CRT; a
shadow mask; a flat panel). Each era is a preset of the chain plus a `domestic` room. Names are pastiche, never the
real mark (the names check).

### Room: Screen 3 - 1983

`app/environments/screen_3_1983.env.json`. The old circle of a picture palace, walled off in 1983 into a small
multiplex screen: a steep rake of multiplex seats, a plasterboard wall with the screen on it, a swirly carpet and a
worn print.

- **The hall** (`auditorium`, id `hall`): 11.2 m wide, 9 rows of 13 multiplex seats on a steep rake (0.42 m a row),
  straight rows, the viewer in the middle of the fifth row from the front (the room's own seat, at the origin). The
  old fabric panels and sconces run on along the side walls and stop at the partition (`partition_z` -7.4), so the
  hall reads as cut in two. No drapes, no acoustic clouds; four exits with signs, the booth's windows in the rear
  wall.
- **The kit:** the swirling carpet on the floor; a plasterboard partition (taped joints, a skirting) over the
  hall's own; a water stain where the roof leaks down the new wall, in its top left corner (three patches of
  stained board, the dark tide line at their feet).
- **Seats** (`seats`): seat 69, in the row in front a little to the left, is broken (its back slumped).
- **Light:** the house lamps go down to 8 % over 4 s when the film starts or plays (cue `dim`, with the common Dim
  during the film on) and come back up in the pre-show and after the end (`lights_up`). The exit sign stutters now
  and then (cue `exit_sign`: every 20 s, a chance of 0.4, two dips of `light.signs` with fades of 0.2 s, under
  2 Hz); it needs the common Flickering lights on.
- **Screen:** 7 x 3.94 m on the partition, its masking (`screen_frame`) and the beam from the booth; smoke and haze
  in the beam (`atmosphere`: `beam_haze` 0.6, `beam_smoke` 0.8); the worn print (`presentation` preset
  `worn_print`: weave, tilt, flicker, dust, scratches, a hotspot). The film is drawn in the room (a picture stage).
- **Setting:** Weave and tilt (`weave`, 0..1, default 0.7): `presentation.weave` by range [0, 1] and
  `presentation.tilt` by range [0, 0.5] degrees. The common Motion setting scales both; Flickering lights holds the
  lamp's flicker and the exit sign steady.
- **Measured** (`tests/test_room_screen_3_1983.gd`, headless): 25 draws, 79 946 triangles, no live light, no
  particles, 10.4 MB of textures; a clear sight line from all 117 seats.
- **Sound to come:** the next screen's film rumbling through the wall (a low bed following `film.bass`, well under
  the film); a small hall's acoustics.

### Room: Drive-in - 1958

`app/environments/drive_in_1958.env.json`, apart from the older drive-in scene (`drive_in.tscn`). The front bench of
a convertible on a drive-in's lot in the desert, dusk falling to a starry night as the film runs.

- **The lot** (`terrace`, id `lot`, style `lot`): humps and speaker posts in rows of bays, the ground out to 120 m;
  the screen (24 x 10 m, 4 m up, 50 m ahead) on the kit's tower; a neon snack bar 16 m behind the car ("SNACK BAR").
- **The car** (`vehicle`, id `car`): the viewer in the middle of the front bench (the room's own seat), a rear bench
  behind; six places to pick.
- **The sky** (`sky`): latitude 35, mid July, the screen facing west-south-west with the sunset's glow to its right.
  Tracks by `film.minutes`: `dusk` from the last light (0) to night (0.75 at 12 minutes, 1 at 25), and `hour` from
  20:45 on, so the stars turn through the film. `milky_way` follows `playback.playing` (0.25 to 0.85, smoothed 3 s).
  Mesas round the horizon (`vista`).
- **Life:** 30 moths in the projector's beam (the beam from the snack bar's roof, `screen_frame` without masking);
  a plane's lights about every 5 minutes.
- **Cues:** the headlamps off and the dials dimmed as the film starts or plays (`lamps_off`); in the pre-show the
  dials lit, the headlamps off (`arrive`); 3 s after the end the headlamps come on (`time_to_go`).
- **Setting:** Window speaker (`tinny`, bool, default off): `presentation.speaker` by map (`window` or `none`). It
  is off by default: a whole film through a band-limited mono speaker is a big loss of the film's sound, which the
  room must never spoil; the viewer turns it on for the effect. No picture stage, so the film layer stays.
- **Measured** (`tests/test_room_drive_in_1958.gd`, headless): 30 draws, 17 288 triangles, no live light, no
  particles, 11.3 MB of textures; a clear sight line from all 6 places.
- **Sound to come:** crickets (a soft bed), a far freight train now and then (a one-shot, its horn far off), the
  open air's acoustics (little reverb).

### Room: Screening room 1962

`app/environments/screening_room_1962.env.json` (Cinemas). A private screening room in a house: walnut panelling, a
deep carpet, a brick fireplace with a slow fire, brass wall lamps, six club chairs in two rows, and a pool glowing in
the garden beyond the picture window. Before the film a painting hangs over the screen; it slides up into the ceiling
as the film starts.

- **Systems:** `light`; `domestic` (`walnut_1962`, `outside` none so the vista shows through the window); `seats`
  (`club_chair` in the builder's six slots, brown leather on walnut); `sky` (a clear night, latitude 34, `dusk` 0.9);
  `vista` (the pool 11 m out at -58 degrees, seen through the window from the viewer's seat; hills on the horizon).
- **The ritual** (cues on `room.painting_open` and `light.house_lamps`): in the pre-show and after the end the lamps
  come up over 4 s and the painting comes down over 6 s (`painting_down`, with the Pre-show on). As the film starts
  from its start (`ritual`), the lamps go to half over 1.5 s, the painting rises over 7 s (1.84 m, at most about 0.4 m/s,
  under the motion limit), and the lamps go down to the setting over 4 s. A film resumed later (`painting_away`, on
  playing, intermission, credits) takes the painting up over 4 s whatever the Pre-show. With the Pre-show off the
  painting stays up and `dim` takes the lamps down over 3 s.
- **Settings:** `house_level`, "Wall lamps in the film" (0..1, 15 %).
- **Default seat:** the middle of the front row (the origin), 5.1 m from a 2.6 m picture.
- **Measured:** 18 draws, 9 600 triangles, 0 lights, 0 particles, 10.4 MB.
- **Not yet:** a bar cart (the object library has none, and a room that ships as a document places no objects).
  Sound wanted: a crackle from the fire, a faint pool filter's hum through the glass, a soft chime before the
  ritual; a small, dry room (rt60 0.45).

### Room: Athens rooftop

`app/environments/rooftop_athens.env.json` (Cinemas). An open-air summer cinema on a roof in Athens (the name is short:
a longer one, "Athens rooftop summer cinema", made its button wider than the Room tab in the pseudo-locale): director's
chairs in rows on the tiles, a low whitewashed wall with bougainvillea over it, strings of bulbs, the screen painted on
the next building's blind wall. Beside the wall the acropolis stands floodlit on its hill under a summer night's
stars; planes cross now and then, and a cat walks along the wall top.

- **Systems:** `light`; `terrace` (`rooftop`, a wall 8 m high, seven rows of nine); `seats` (`director`); `kit`
  (bougainvillea on four of the right wall's places, clear of the cat's way); `sky` (latitude 38, day 200, 21:30, the
  screen facing 200 degrees, the sunset's glow at 300); `vista` (the acropolis at 52 degrees, 150 m, size 2: clear
  of the screen wall's edge and over the low wall from the seat; hills); `life` `planes` (plane lights) and `cat`
  (its way along the left wall's top, 6.65 m out: never in the sight line, measured over 4 minutes).
- **Film-time track:** `sky.dusk` from 0.75 to full night over the first 20 minutes of the film.
- **Settings:** `floodlights`, "Floodlights on the hill" (0..1, full): `vista.floodlight`.
- **Default seat:** the middle of the third row from the back (the origin), 11.9 m from a 6.4 m picture.
- **Measured:** 15 draws, 29 086 triangles, 0 lights, 0 particles, 9.3 MB.
- **Sound wanted:** cicadas (a bed, fading as the film starts), mopeds far off now and then, the cat's purr when it
  sits; open air (rt60 0.25, wet 0.15).

### Room: Pillow Fort 1993

`app/environments/pillow_fort_1993.env.json` (Television). A child's bedroom on a rainy night: a pillow fort of
cushions and a bedsheet on broom handles round three floor cushions, fairy lights along its front, rain on the
window, and the telly filling the fort's opening, showing the film as a tube shows a tape watched a few times.

- **Systems:** `light`; `domestic` (`bedroom_1993`, `opening_screen` on: a 1.33 x 1.0 m picture just beyond the
  opening); `kit` (a `video_recorder` in the `telly_shelf` slot: on the floor in front of the telly's chest, its
  clock flashing 12:00); `seats` (`cushion` in the fort's three slots); `weather` (the pane on the window, facing in;
  300 drops outside it; the Rain setting on `mode`); `presentation` (`nightowl_1993`: a tape, a CRT with an aperture
  grille; the speaker by the setting).
- **Settings:** `rain`, "Rain on the window" (rain, drizzle, coming and going, none; rain): `weather.mode` by `map`;
  `telly_sound`, "The telly's own speaker" (off): `presentation.speaker` `telly` or `none`, so the film keeps its
  own sound unless asked.
- **Flicker:** the fairy lights waver slowly (the builder's `flicker`), the video recorder's clock flashes; Flickering
  lights holds them.
- **Default seat:** the middle cushion (the origin), 1.25 m from the picture.
- **Measured:** 23 draws, 5 444 triangles, 0 lights, 300 particles, 6.0 MB.
- **The telly fills the opening (a setting since 2026-11-07):** `telly_fills` (on by default) is bound to
  `domestic.opening_screen`. Turning it off rebuilds the room with the telly on its chest of drawers across the
  room, and the film goes with it (`env_room.gd _follow_builder_screen()`, below); the video recorder goes with it
  too (its slot follows the set). No tree or tin of sweets.
- **Sound:** `acoustics` `small_room` (`rt60` 0.3); `sound_bed`s: `radiator` at the radiator, `rain_glass` at the
  window with `level` on `weather.rain` (it goes quiet as the Rain setting dries the night), `vcr` by the video
  recorder, played by the cue `tape_in` as the film starts (the tape goes in). Each at its designed level: together
  about -49 dBFS in the pre-show, 11 dB under the level check's target, 8 dB lower while the film plays.

### Room: Bathysphere

`app/environments/bathysphere.env.json`. A round hall under a glass dome in deep water. Fish and glowing creatures
gather round the screen outside the glass; now and then, in a quiet scene, a whale swims past above it.

- **The hall** (`dome_hall`): radius 9 m, a 1.3 m drum of dark metal with 12 warm lamps (group `house`), a glass
  dome 7.5 m high on 12 brass ribs, an oak floor, a low stage. The screen (6.4 x 3.6 m, its bottom 1.45 m up) stands
  8.3 m ahead, inside the glass. Plush seats in teal velvet on arcs round it (six rows, 100 degrees); the room's own seat is at the
  origin, in the third row. Seat picking is the builder's (`ring` seats; the chosen one folds away).
- **The water** (`outside` water): blue-black, lit faintly from above. `outside_glow` follows `playback.playing`
  (0.7 before the film, 0.45 in it, over 3 s). The glass is tinted almost black, so it adds little haze and the water
  stays dark.
- **The light** (`light`): a cool blue-green fill from above, warm lamps.
- **Life** (`life`, four systems, all outside the glass): `fish`, 40 silver fish to the left; `shoal`, 28 smaller
  grey-green ones to the right; `glow`, 16 glowing bells behind and round the picture (`size` 2, their colour half
  the film's); `whale`, its way high behind the screen (13 m up, 17 to 19 m out). The fish's and the bells'
  `attraction` follows `film.brightness`: they come nearer the screen in a bright scene. The regions are boxes outside
  the dome's ellipsoid and inside the water's sphere, to the sides of the picture, so no school hides behind it.
- **Settings:** Whale (`whale`): never, rarely (the default), sometimes. Two cues on `film.quiet` (above 0.9 for 4 s,
  while playing) call `whale.pass`, one per choice: rarely has a chance of 0.3 and a cooldown of 30 minutes,
  sometimes 0.7 and 15 minutes; never fires neither. The whale sings as it passes.
- **Cues:** `dim` (with the film: the house lamps to 12 % over 4 s), `lights_up` (pre-show and the end).
- **Measured** (`test_room_bathysphere.gd`, headless): 12 draws, 79 078 triangles, no lights, no particles, 6 MB.
- **The render** (lavapipe, from the seat): a dark blue dome on brass ribs over rows of teal seats, a school to each
  side of the picture, faint bells at its edges, the whale's shape crossing above it.
- **Sound:** a small hard room of metal and glass (`acoustics` `hull`, rt60 0.9); the hull creaking now and then to
  either side (`sound_bed` `hull_creak` twice, at the drum left and right, `every` 180 each: one about every 90 s);
  the deep's low hum (`deep_hum`, `gain_db` -4); the whale's song is `life`'s (`voice_db` -4). Measured
  (`test_room_bathysphere.gd`, the slider's default, both creaks playing): -52.0 dBFS RMS in the pre-show, -73.0
  under a film at the reference level.
- **Gap:** caustics. The light system has no moving light pattern; the room has a cool fill from above instead.

### Room: Crater

`app/environments/crater.env.json`. A lunar amphitheatre of stone tiers under a glass dome, Earth over the screen
in a black sky full of stars. Silent: the room has no sound bed and makes no sound at all; only the film is heard.

- **The amphitheatre** (`terrace`, style `amphitheatre`): seven tiers on arcs of 120 degrees round the screen
  (rows 2 in front, 5 behind, 0.95 m deep, 0.42 m rise), the pit 1.26 m under the room's own seat, the screen (8 x
  4.5 m) on a dark frame 11.4 m ahead, 18 rocks on a grey plain that runs 150 m out. The room's own seat is in the
  third tier at the origin; seat picking uses the tiers' places (`tier`).
- **The dome** (`dome_hall` as a cover: `has_floor` and `seating` off, `outside` none): glass, radius 18 m centred
  9 m ahead, on a 0.8 m drum with 16 cool lamps (group `house`), 12 m high, 16 ribs of brushed steel. Every seat's
  eyes and the screen are under it with a metre to spare. The glass is tinted almost black, so space shows black
  through it.
- **Why both:** the two combine cleanly. The terrace gives the tiers, the plain and the screen; the dome adds only its
  drum, panes, ribs and lamps over them (no floor, no seats, no water). The screen is the terrace's.
- **The sky** (`sky`, mode `space`): latitude -30, a July night, so the Milky Way's bright middle stands high.
  `milky_way` follows `playback.playing` (0.35 before the film, 1 in it, over 3 s): the Milky Way comes out as the
  lights dim. Earth 4 degrees across, 30 degrees up, a little to the right of the screen, 70 % lit.
- **The rim** (`vista`): low grey hills 160 m out all round, the crater's wall.
- **Setting:** Earth's speed (`earth_speed`, 0.5 to 4 times, default 1): bound to `sky.earth_turn` by `range`
  [6, 48], so 1 x is twelve times Earth's real speed, a turn in two hours (about one a film), and 4 x a turn in 30
  minutes. The Motion setting scales it (half Motion, half the speed).
- **Cues:** `dim` (the dome's lamps out over 5 s with the film), `lights_up`. `pause_rise_db` 0.
- **Measured** (`test_room_crater.gd`, headless): 12 draws, 15 836 triangles, no lights, no particles, 4.3 MB.
- **The render** (lavapipe, from the seat): the framed screen on the pit floor, pale tiers either side, the dome's
  ribs meeting overhead, stars and the Milky Way through the glass, Earth up and to the right of the picture.
- **Sound:** none, by design: `sound_bed` `silence` (it plays nothing) and `acoustics` `vacuum` (dry); no cue
  sound, no life, no pause rise (the test measures nothing on Environment). Acoustics for the film's spatial sound:
  a large glass dome, rt60 1.1, wet 0.35.

Seven rooms, one for each TV preset, are the history of television: `app/environments/tv_<year>.env.json`, in the
Room tab's Television group (`room.category` "tv"). Their names start "TV <year> - ", so the group reads as a
timeline. (A room's name takes letters, digits, space, - and _ only. "Television, 1930: ..." is refused, and the
longer "Television 1930 - ..." names made the Room tab's card too wide in the pseudo-locale.) Each is a `domestic`
room (style `plain`, or `bedroom_1993`) with `screen` "telly" and the era's preset on it, the `seats` system for the
chairs, and cues for the lamps: down when the film starts or plays (`lamps_down`), up in the pre-show and after the
end (`lamps_up`). Tested by `tests/test_room_tv.gd` (headless: every check of `test_environments.gd`, the preset,
the telly's shape and size, each setting and what it does, the cues).

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
| 1953 | 0.36 x 0.27 m (a 17 inch tube) | 1.1 m | 19 degrees | a big set for its day; the armchairs gathered round |
| 1972 | 0.46 x 0.345 m (22 inch) | 1.4 m | 19 degrees | the colour set in the corner, the chairs in a row |
| 1983 | 0.30 x 0.225 m (14 inch portable) | 0.8 m | 21 degrees | at a desk: the portable is near, as a screen for a home computer was |
| 1987 | 0.54 x 0.405 m (26 inch) | 1.5 m | 20 degrees | the family set, the settee across from it |
| 1993 | 0.40 x 0.30 m (20 inch) | 1.1 m | 21 degrees | a bedroom set seen from a bean bag on the floor |
| 2005 | 0.72 x 0.405 m (32 inch, 16:9) | 1.9 m | 21 degrees | the first flat panel: wider, and the sofa further back |

### Room: TV 1930 - glowing box

1 of 7. A small dark parlour with a coal fire. A mechanical-scan set in a walnut cabinet on a walnut chest glows
orange with thirty lines (`glowbox_1930`, its sound through the radio cabinet's speaker). Three club chairs in
velvet, two angled in beside the viewer's. A wall lamp, a night window.

- Systems: `light` (a low, warm fill), `domestic` (2 x 1.4 m in front, 2.6 m behind; fireplace on the right, the
  window on the left with a dark night glow), `seats` (two club chairs as places), `presentation`.
- Settings: Lines in the picture (30 as it was, 60, 120: `presentation.mech_lines` by `map`); Fire in the grate
  (`domestic.fire`).
- Cues: `tuning_in` (Pre-show): the signal weak at the start, the picture coming in over 6 s. The lamp down to 15 %
  in the film.
- Measured: 18 draws, 2 216 triangles, 10 MB, no particles.
- Sound: `acoustics` `small_room`; the coal fire (`sound_bed` `fire` in the grate, `gain_db` -3, on the Fire setting);
  a clock on the mantel (`clock`); the disc's motor (`hum` at the set, `gain_db` -4). No tube whine: thirty lines on a
  spinning disc, no tube. Measured (`test_room_tv.gd`, the slider's default): -55.1 dBFS RMS in the pre-show, -69.6
  under a film at the reference level.

### Room: TV 1953 - by the fire

2 of 7. A sitting room with a lit coal fire and a cat on the hearth. A small black and white set in a walnut cabinet
on a chest (`fireside_1953`: 405 lines, snow and a ghost). Four empty armchairs gathered round it. Rain on the window
from time to time; through it, an evening sky over hills. A potted fern in the corner.

- Systems: `light`, `domestic`, `kit` (ferns), `seats` (three armchairs as places), `sky` (dusk 0.85, clouds 0.7),
  `vista` (hills to the left), `weather` (changing, 500 drops outside the window, the pane), `life` (`cat`, its path
  along the hearth), `presentation`.
- Settings: Snow from the aerial (0 to 60 %: `presentation.snow`); Fire in the grate.
- Cues: `warm_up` (Pre-show): the valves warm up, the picture dim at first and full over 6 s. The lamps down to 25 %.
- Measured: 24 draws, 10 168 triangles, 10.3 MB, 500 particles.
- Sound: `acoustics` `small_room`; the fire's crackle in the grate (`sound_bed` `fire`, on the Fire setting); a clock
  on the mantel (`clock`); rain on the window (`rain_glass` at the pane, `level` on `weather.rain`); the tube's faint
  whine at a 405-line set's 10 125 Hz (`tube_whine`, `pitch` 0.648, `gain_db` -4); the cat's purr is `life`'s.
  Measured (`test_room_tv.gd`, the slider's default, the rain full): -52.8 dBFS RMS in the pre-show, -66.3 under a
  film at the reference level.

### Room: TV 1972 - first colour

3 of 7. Mustard walls with orange and brown bands sweeping behind the set, a swirling carpet with a mustard rug on
it, three club chairs in orange velour and a bean bag. An early colour set in a teak-look cabinet on a radiogram
(`colourstar_1972`: a shadow mask, warm rich colour), a teak sideboard on the right wall, a standard lamp in the
corner. A summer dusk in the window.

- Systems: `light`, `domestic` (a radiator under the window; `telly_stand` `radiogram`), `kit` (carpet, curves on the
  front wall, a velvet `rug`, a `sideboard`, a `standard_lamp` with an orange shade), `seats` (a bean bag as a
  place), `sky` (dusk 0.45), `vista` (hills), `presentation`.
- Settings: Snow from the aerial (0 to 40 %); Colour (the set's colour knob, 0.5 to 1.5 times: `presentation.colour`).
- Cues: `warm_up` (Pre-show), the lamps (and the standard lamp's shade: house group) down to 30 %.
- Measured: 24 draws, 9 694 triangles, 7.5 MB (before the furniture: 19 draws, 9 252 triangles, 7.5 MB).
- Sound: `acoustics` `small_room`; `sound_bed`s `radiator` at the radiator, `clock` on the sideboard, `tube_whine` at
  the set (about -52 dBFS together, 14 dB under the target).

### Room: TV 1983 - desk portable

4 of 7. A small room at night: a light grey portable telly (a carry handle, a rod aerial, its knobs at the side) on
a desk with a pedestal of drawers, a beige home computer and its keyboard on the desk beside it, a wooden chair.
Drizzle on the window, the street lamp's orange glow beyond it. `sirclive_1983`: the computer's aerial lead, 240 bold
lines. A bean bag at the back for a second seat.

- Systems: `light`, `domestic` (no lamps; the outside glow sodium orange; `telly` `portable` on a `desk` 1.35 m
  wide, moved 0.2 m left: 0.74 m high, the portable's foot), `kit` (a `computer` on the `telly_stand` slot, left of
  the set, `holds` `none`: the telly is its screen), `seats` (the bean bag), `weather` (light rain on the pane only),
  `presentation`.
- Settings: Aerial lead noise (`presentation.snow`); Bold lines (`presentation.scanlines` 0.65 or 0.2).
- Cues: `tuning_in` (Pre-show): a `glitch` as the set finds the computer's channel.
- Measured: 16 draws, 1 110 triangles, 8.0 MB (before the furniture: 17 draws, 952 triangles, 8.2 MB). The picture
  is 5 cm lower than before (its centre 0.90 m), so the desk is a desk's height.
- Sound: `acoustics` `small_room`; `sound_bed`s `rain_glass` at the window, `level` on `weather.rain`; `tape_load`
  by the computer, played 2 s into the pre-show by the cue `loading` (the computer loads from its cassette, very
  low); `tube_whine` at the portable.

### Room: TV 1987 - rented tape

5 of 7. The family living room on a wet night: a black telly on a wooden tv unit with a video recorder in its shelf,
its clock flashing 12:00, a three-seat settee and an armchair, a white-painted brick fireplace, a fern.
`rewinder_1987`: a rented tape, tracking wobble, smeared colour, the tear at the bottom.

- Systems: `light`, `domestic` (`telly_stand` `tv_unit`; seat pitch 0.58 m), `kit` (a `video_recorder` in the
  `telly_shelf` slot, ferns), `seats` (`model` `settee` in the builder's three slots: one settee, the viewer in its
  middle; the armchair as a place), `sky` (night, clouds), `vista` (hills), `weather` (changing, 500 drops, the
  pane), `presentation`.
- Settings: The tape (fresh, rented, worn out: `tape_noise`, `chroma_bleed` and `head_switch` by `map`); Wall lamps in
  the film (0 to 100 %, default 30 %).
- Cues: `tape_start` (Pre-show): the tape tears for a moment as it starts (`glitch`, 1.5 s). The lamps follow the
  setting. The clock flashes all the time (Flickering lights off holds it lit).
- Measured: 27 draws, 9 646 triangles, 9.3 MB, 500 particles (before the furniture: 25 draws, 10 108 triangles,
  9.5 MB).
- Sound: `acoustics` `small_room`; `sound_bed`s `vcr` at the tv unit (the cue `tape_start` plays it as the film
  starts, then the tear 2.5 s later), `clock` on the mantel, `tube_whine` at the set, `fire` at the grate (`gain_db`
  -4: the fire is lit), `rain_glass` at the window (`gain_db` -3, `level` on `weather.rain`: the rain comes and goes).
  About -49 dBFS together at full rain, 11 dB under the target.

### Room: TV 1993 - bedroom telly

6 of 7. A teenager's bedroom (not the pillow fort): blue walls, fairy lights along the wall over the telly, the bed,
a radiator under the window, rain in the night outside. A bean bag on the floor; a second place sitting on the bed.
`nightowl_1993`: a tape watched a few times on a flatter tube with an aperture grille.

- Systems: `light`, `domestic` (`bedroom_1993`, `fort` off, `fairy_lights` on, `fairy_glow` bound to the fairy
  lights' setting), `seats` (bean bags; a cushion on the bed), `sky` (night), `weather` (by the setting, 400 drops,
  the pane), `presentation`.
- Settings: Weather at the window (raining, a dry night, showers: `weather.mode`); Fairy lights over the telly (0 to
  100 %: `domestic.fairy_glow`, 0 to 1.5; the accent group, the window's glow with it, stays as it is).
- Measured: 20 draws, 8 470 triangles, 6.3 MB, 400 particles.
- Sound: `acoustics` `small_room`; the radiator ticking under the window (`sound_bed` `radiator`); rain on the glass
  (`rain_glass` at the pane, `level` on `weather.rain`); the tube's whine (`tube_whine`, 15 625 Hz); the tape going in
  as the film starts (`vcr` under the telly, played by the cue `tape_in` in `starting`, with the Pre-show on).
  Measured (`test_room_tv.gd`, the slider's default, the rain full, the tape going in): -52.6 dBFS RMS in the
  pre-show, -66.7 under a film at the reference level.

### Room: TV 2005 - flat screen

7 of 7. A pale living room with a laminate floor, a grey three-seat settee and an armchair, a coffee table, a plant,
a wide window on a sunset. A 32 inch flat panel on its pedestal on a low pale wooden tv unit (`freedtv_2005`: a free
digital broadcast, a faint pixel grid, the backlight through the dark scenes).

- Systems: `light`, `domestic` (`telly` `flat_panel`, 7 cm deep, on a `tv_unit` 1.4 m wide; seat pitch 0.6 m), `kit`
  (ferns, a `coffee_table`), `seats` (`model` `settee` in the builder's slots; the armchair), `sky` (dusk 0.6),
  `vista` (hills), `presentation`.
- Settings: Wall lamps in the film; Backlight bleed (`presentation.panel_bleed`).
- Measured: 21 draws, 9 690 triangles, 10.3 MB (before the furniture: 19 draws, 10 232 triangles, 10.3 MB).
- Sound: `acoustics` `small_room` only; no beds (a flat panel is silent).

**What the systems lack for these rooms** (each room took the closest thing there is):

- A tube's own shape for the CRT (above).
- The radio-style cabinet of 1930 is the telly on a walnut chest (a `radiogram` stand is there now; the 1930 room
  keeps its chest).
- The seats system's own places are not listed before the room is built (no static layout), so the seat list before
  the build is the builder's alone.
- Sound: each room's beds and acoustics are in its own section (the recipes: "Sound and music", "For the rooms").
  `test_room_tv.gd` checks them: the sounds, each in the room, each 10 dB or more under the level check's target and
  all together 6 dB or more under it, the loops playing, the one-shots played by their cues.

## Files

| File | What |
|---|---|
| `app/scripts/env/env_doc.gd` | the version 4 sections' validation, bindings, settings declarations |
| `app/scripts/env/systems/registry.gd`, `env_system.gd` | the registry and the system base |
| `app/scripts/env/systems/*.gd` | the systems |
| `app/scripts/env/systems/kit/` | the builders' common base (`builder.gd`) and helpers, the kit's pieces (`pieces.gd`), the furniture (`furniture.gd`), the glass and glow shaders |
| `app/scripts/env/env_host.gd` | the host: builds the systems, runs the signals, bindings, timeline and cues |
| `app/scripts/env/env_room.gd` | the environment node of a room that ships as a document |
| `app/scripts/env/env_signals.gd`, `env_timeline.gd` | film signals; states and cues |
| `app/scripts/env/room_settings.gd` | room settings: declarations, storage, applying them |
| `app/scripts/env/env_audio.gd`, `env_synth.gd` | the buses, the slider, ducking, the level check; synthesised sounds |
| `app/scripts/env/env_checks.gd` | the checks |
| `app/environments/*.env.json` | the rooms as documents |
| `app/scripts/env/env_library.gd` | lists a document with no scene of its own as a room (`document_rooms()`) |
| `app/ui/room_tab.gd` | "This room" |

## The next phase

Systems first, in parallel, then rooms. Each agent owns its files below, adds one line per system to `registry.gd`
(and the kind to `KINDS` if new), and its own `app/tests/test_env_<system>.gd`. Nobody else edits a file another
agent owns; the shared files take additive changes only (`registry.gd`, `env_doc.gd` constants such as `SOUNDS`,
`zh_CN.po` appended). Each system passes the checks through a small test room in its test, not a shipped room.

**Phase 1: systems** (seven agents at once)

| Agent | Systems | Owns |
|---|---|---|
| A sky and vista | `sky`, `vista` | `systems/sky.gd`, `systems/vista.gd`, `app/shaders/env_sky*.gdshader`, star catalogue data (public domain) |
| B atmosphere and weather | `atmosphere`, `weather` | `systems/atmosphere.gd`, `systems/weather.gd`, `app/shaders/env_haze*`, `env_rain*` |
| C ambient life | `life` | `systems/life.gd`, `systems/life/*.gd` (one creature each), `app/shaders/env_life*` |
| D sound and music | `sound_bed`, `acoustics`, `music` | `systems/sound_bed.gd`, `systems/acoustics.gd`, `systems/music.gd`; takes over `env_synth.gd` |
| E presentation | `presentation` | `systems/presentation.gd`, `app/shaders/env_presentation*`; TV-era presets |
| F builders | `shopfront`, `nave`, `dome_hall`, `terrace`, `domestic`, `vehicle`, `kit` | `systems/<name>.gd` each, `systems/kit/*` |
| G seats and motion | `seats`, `motion` | `systems/seats.gd`, `systems/motion.gd`, the seat model slot of `auditorium.gd` (`seat_model`, `seat_mesh()` only) |

The foundation's own files (`env_host.gd`, `env_timeline.gd`, `env_signals.gd`, `env_audio.gd`, `env_checks.gd`,
`room_settings.gd`, `env_room.gd`, `auditorium.gd` apart from G's slot) stay with one agent, if any change is
needed at all: a system that needs a new host hook asks for it rather than editing the host.

**Phase 2: rooms** (after phase 1 is merged; as many agents as rooms, two or three rooms each)

A room is its document alone: `app/environments/<id>.env.json`, with no scene. `scripts/env/env_library.gd`
lists every document without a `.tscn` beside it, so a room agent touches no list in `main.gd`,
`env_library.gd` or `room_tab.gd`; `tools/i18n.py extract` takes the room's name and settings' words from the
document. Each room agent owns its documents, its CC0 assets under `app/environments/<id>/`, its rows in
`app/environments/CREDITS.md` (one block per room, appended) and its Chinese entries appended to `zh_CN.po`.
`test_environments.gd` checks every document without change.

## Open questions

- **The command name.** `room_settings` already named the Room tab's state for the assistant; its result now has
  `this_room` (the declarations and values), and `room_setting` sets one. A separate `room_settings` with both was
  not possible without breaking existing clients.
- **`film.colour` on the headset.** The colour is read back from the bias light's 4 x 2 copy with the rendering
  device's asynchronous read (no stall). Its cost on the Frame is not measured yet; it runs only while a binding uses
  the colour or the brightness.
- **Credits for long films.** `credits` is the last six minutes (at most a tenth). Chapters named "Credits" would be
  better where the file has them.
- **The ducking curve** is the engine's compressor, keyed from Film: its settings are chosen from the test tone, not
  from listening in the headset.
- **The Void's reflection** is now on by default (it was off): the Void's design is a mirror floor. It costs a
  quad that samples the video.
- **Room sound levels by ear.** Every bed and instrument is measured on the desktop, not heard in the headset. The
  designed levels are 12 dB or more under the level check's target, so a room can lift one with `gain_db` after a
  listen.
- **A cue's long one-shot.** `env_audio.play` makes a sound it has not made before on the main thread (the train:
  about 1 s on a desktop). Rooms play long one-shots through a `sound_bed` (`every` or its `play` action), which makes
  them on a worker thread.
- **The shortest reverb.** The engine's reverb has no tail under about 0.5 s. `small_room`, `vehicle` and `outdoors`
  use its smallest room with a little wet; a shorter tail would need another effect.
- **A telly's shape** (settled 2026-11-07). The presentation still draws on the screen's own mesh at the film's
  aspect, but `tube` gives the CRT's corners and bulge the tube's shape round it.
- **The presentation in the layer.** A source-only chain (weave and grain) could stay in the film layer, as the
  projector feature's weave does; the presentation draws in the room for every picture stage, for one path. Its cost
  on the Frame is not measured yet.
- **Ambient life on the Frame.** The creatures' ticks are measured on the desktop only (under 1 ms for all nine). A
  room with many fliers should be timed on the headset.
- **Parts of a room in front of the picture (settled 2026-11-07).** The domestic painting (while down) and the
  pillow fort's hem are in the group `env_in_front`, as motion's in-front things are, so on the Frame the film
  layer steps aside while they cover the picture and the film draws in the room behind them. A fort hem over the
  picture keeps the film in the room for the whole showing (the layer's sharpness is lost there).
- **Auto parameters in `domestic`.** Its parameters left on auto take the style's values, so the licences check
  reads only the materials a document names. Every style's material is a bundled CC0 library material, so the check
  still holds, but it does not see them.
