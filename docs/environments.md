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
| `room` | the room as a whole: `ambient` (0..1, its surfaces' light with a dark screen), `screen_glow` (0..2), `curtains` (the pre-show's curtains may close here), `reacts_to_film` (the film's transients may flash the light), `reflection` (the floor reflection's default here) and `reflection_floor` (its height; null: none) |
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

### The systems

| System | Kind | Role | State |
|---|---|---|---|
| `light` | light | the house materials (the library on the house shader: fill, the film's spill, stand-in lamps before a bake), the lamp glows by group (house, steps, stage, signs), the hidden bake lights, the bake hooks. The screen is the main light: every lit surface takes the film's spill | built |
| `auditorium` | builder | stadium rows on a rake, seats, aisles, side walls and panels, proscenium and screen wall, ceiling, step and house lights, curved rows, balcony, boxes, open ceiling, a partition wall | built |
| `screen_frame` | screen | the black masking round the screen, the projector's beam from a lens | built |
| `showing` | showing | the curtains' part in the ritual: actions `open_curtains`, `close_curtains` (the pre-show's curtains, `scripts/env/preshow.gd`) | built |
| `mirror_floor` | builder | a black floor that takes the film's reflection, a ripple where the viewer moves | built |
| `shopfront`, `nave`, `dome_hall`, `terrace`, `domestic`, `vehicle` | builder | the other parametric structures (shopfront hall, nave, dome, open-air terrace or lot, domestic room, vehicle interior) | next |
| `kit` | kit | modular pieces placed along a builder's slots (balcony fronts, niches, columns, façades) | next |
| objects, materials, pictures | | as now: `parts` placements, library materials, pictures | as now |
| `sky`, `vista` | sky | a sky dome (gradient, stars with real constellations, clouds lit by the screen, aurora), far scenery cards (mesas, an acropolis, birches) | next |
| `atmosphere`, `weather` | atmosphere | haze, dust and smoke in the beam, ground fog and mist, breath; rain and snow through open roofs and outside windows, rain on a pane, a puddle that reflects the film, a weather cycle (below, "Atmosphere and weather") | built |
| `life` | life | non-human ambient life: moths, birds, fish, fireflies, a cat, a deer, a whale. Never people | next |
| `sound_bed`, `acoustics` | sound | looped beds and one-shots from our own synthesiser or CC0 samples, placed in the room, on the Environment bus | next |
| `music` | music | instruments that play themselves (a player piano, an organ), from our own synthesiser | next |
| timeline and cues | | below; part of the host, not a registered system | built |
| film signals | | below; part of the host | built |
| `presentation` | screen | the chain of stages from source to display: source (film, tape, broadcast), transmission (aerial noise, ghosting), display (CRT, mask, curvature, a telly's glass). TV-era presets | next |
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
 "steps": [{"do": "life.whale", "args": {"side": "left"}}, {"sound": "whale", "gain_db": -6}]}
```

| Key | What |
|---|---|
| `name` | the cue's name |
| `when` | the trigger: `{"state": "starting"}` or a list of states (on entering one); `{"signal": "<channel>", "above" or "below": x, "for": seconds}` (once each time it crosses); `{"every": seconds}` |
| `requires` | `[{"setting": "<name>", "is": value}]`: settings that must hold (`is` left out: the setting is on). The common `ritual` setting is one |
| `states` | the states it may fire in |
| `chance` | 0..1, rolled each time it would fire |
| `cooldown` | seconds before it may fire again (the whale: at most once in 15 minutes) |
| `steps` | run in order: `{"set": "<id>.<param>", "to": v, "seconds": s, "ease": "linear" or "in" or "out" or "in_out"}` (starts a fade and goes on), `{"wait": s}`, `{"release": "<id>.<param>", "seconds": s}` (back to its base value or binding), `{"do": "<id>.<action>", "args": {...}}`, `{"sound": "<synth>", "gain_db": g, "at": [x, y, z]}` |

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
   Environment   the room: the thud, cue sounds, sound beds; ducked under Film; the Environment sound slider
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

Forms: `up` is a tip-up seat tipped up (the hall is empty). `broken` is a seat with its back slumped and its cushion
hanging.

### Three ways in

- **The builders' seat slots.** A builder with `seat_slots()` (shopfront, nave, terrace, domestic, vehicle,
  dome_hall) draws no seats of its own when the room has a seats system. The seats system draws a seat in every slot.
  With `model` "auto" the slot's style chooses: chair: folding_chair, pew: pew, bench: bench_seat, cushion and tier:
  cushion, club: club_chair, ring: plush. The builder lists these seats (its `seats()`), so they are listed once.
  A slot is `{transform, row, style, width, builder}`. Slots of one row run left to right; a gap of more than 1.5
  widths starts a new pew. The pews' ends and the benches' trim go into one static mesh, `SeatEnds`.
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
- The viewer's own seat folds away (`fold_own`): chairs only. A pew, a bench, a cushion, a hide or a bean bag stays.
- `tipped`: the share of tip-up seats left tipped up.
- `collision_shapes()`: each seat's model boxes (one or two), for object physics.

Measured headless (`test_env_seats.gd`): 15 plush seats are 2 draws and 9 660 triangles. A tipped or broken form
adds two draws. Pews' ends add one or two. Texture memory is a budget figure measured headless. Under lavapipe a PC
holds the textures decompressed (the headset keeps them ASTC), so the cinema alone reads 144 MB there.

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

- a node the document names: `node` (its name), among the nodes of the system `system` (an id), or anywhere in the
  room when `system` is empty;
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

## The converted cinema

`app/environments/cinema.env.json` with `cinema.tscn` and a thin `cinema.gd`. It looks the same: the render test
(`tests/test_env_cinema_render.gd`, lavapipe) draws the old cinema (`tests/fixtures/cinema_v3.gd`, the room as code
before the conversion) and the new from the seat and from the aisle and compares them pixel by pixel. The bake hooks
(`static_meshes`, `bake_lights`, `set_baking`, `set_baked`) come from the light system, so the headset's bake path is
as before. Settings: the pre-show ritual (common), the house lights in the film.

## The Void

`app/environments/void.env.json`: a black sky (nothing drawn), a mirror-black floor that takes the film's reflection
(on by default), and a small ripple where the viewer's head moves more than 15 cm a second over the floor. Setting:
the ripple's strength.

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

### TV-era rooms

The same `presentation` chain makes the TV-era rooms: source (a broadcast, a tape, a disc), transmission (aerial
noise, ghosting, a weak signal), display (a mechanical-scan set's orange glow, 1930; a round-cornered CRT; a
shadow mask; a flat panel). Each era is a preset of the chain plus a `domestic` room. Names are pastiche, never the
real mark (the names check).

## Files

| File | What |
|---|---|
| `app/scripts/env/env_doc.gd` | the version 4 sections' validation, bindings, settings declarations |
| `app/scripts/env/systems/registry.gd`, `env_system.gd` | the registry and the system base |
| `app/scripts/env/systems/*.gd` | the systems |
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
- **Seat boxes in the auditorium.** The auditorium's `collision_shapes()` gives every seat the stadium seat's two
  boxes, whatever `seat_model` is. The other models are about that size, but a club chair or a bean bag is wider.
  `seats.gd model_boxes()` has each model's boxes; the auditorium could use them.
- **The film layer and things in front of the screen.** On the Frame the film layer is drawn over everything in front
  of it. A painting or a festoon in front of the screen (motion's `in_front`, the group `env_in_front`) is hidden
  under the film unless `film_layer.gd _covered()` also steps aside for nodes in that group. Until then, such a
  thing is seen only while no film is open, or with the film layer off.
