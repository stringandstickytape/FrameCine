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
| `room` | the room as a whole: `ambient` (0..1, its surfaces' light with a dark screen), `screen_glow` (0..2), `curtains` (the pre-show's curtains may close here), `reacts_to_film` (the film's transients may flash the light), `reflection` (the floor reflection's default here), `reflection_floor` (its height; null: none), `curtain_colour` (the pre-show's curtains' colour; null, the
default: the app's red velvet; since 2026-11-08, the Palace of Culture's ochre) and `category` (where the Room tab lists it: `cinema` under Cinemas, `tv` under Television, `other` with the other rooms, the default; `env_library.gd category_of()`) and `description` (a line about the room under the Room tab's "This room", at most 200 characters; a key, so a room that ships translates it) |
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
  comfort check holds it to that limit, and the room's Motion setting scales it. `"when": "<param>"` names the
  parameter that switches the motion on: a room offers the Motion setting for it only where that parameter is on
  (the house light's `caustic_speed` with `caustics` above 0, so the cinema shows no Motion setting).
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
| `light` | light | the house materials (the library on the house shader: fill, the film's spill, stand-in lamps before a bake), the lamp glows by group (house, steps, stage, signs), the hidden bake lights, the bake hooks. The screen is the main light: every lit surface takes the film's spill. `caustics` (live, a brightness; since 2026-11-08): the light of a water's surface above, a slowly drifting web on whatever faces up, not dimmed by the house lights; `caustic_colour`, `caustic_scale` (metres a cell), `caustic_speed` (`motion`). Two more texture reads on the house shader where it is on (`procedural.gd caustic_map()`, 256 x 256, 64 KB) | built |
| `auditorium` | builder | stadium rows on a rake, seats, aisles, side walls and panels, proscenium and screen wall, ceiling, step and house lights, curved rows, balcony, boxes, open ceiling, a partition wall | built |
| `screen_frame` | screen | the black masking round the screen, the projector's beam from a lens (`beam_style` `flat`, or `volume`: light summed through the beam's pyramid, `beam_strength`; since 2026-11-08) | built |
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
   by ray. A seat's own back and anything behind the eyes do not count. A MultiMesh stands at the seats unless it has
   meta `env_placed` (an Array of its instances' transforms, since 2026-11-08: the drive-in's parked cars), which
   places it there instead (a headless MultiMesh keeps no transforms of its own).
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
| `seat_model` | `stadium` | the seat: `stadium` (drawn by the auditorium), or a single seat of the seats system: `plush`, `multiplex`, `folding_chair`, `club_chair`, `director`, `cushion`, `bean_bag`, `civic`, `recliner` (set `seat_pitch` to fit) |
| `seat_upholstery`, `seat_shell` | velvet, black leather | materials |
| `seat_tint_spread` | 0.12 | how much the seats differ, one from the next |
| `wall_treatment` | `panels` | `panels` (fabric panels with wooden rails) or `plain` |
| `proscenium` | `drapes` | `drapes` (velvet either side and a valance) or `none`; slots to come: castle gate, festoon |
| `stage_depth`, `stage_top` | 1.9, -2.1 | the stage in front of the screen wall |
| `ceiling_cover` | 1 | the ceiling's share from the front; under 1 opens it to the sky (the Atmospheric, the Reclaimed's broken roof) |
| `shell` | `built` | `built`: the walls, the ceiling, the stage, the drapes, the pit, the doors and the lamps drawn here; `kit`: only the tiers, the side aisles, the rear walkway and the seats, a kit drawing the rest (Reclaimed's ruin, since 2026-11-08) |
| `balcony_rows` | 0 | a balcony over the rear with this many rows |
| `boxes_per_side` | 0 | boxes on the side walls |
| `partition_z` | 0 | a plain wall across the hall here (a subdivided hall, Screen 3); 0: none |
| `booth` | true | the projection booth's windows in the rear wall; `lens` is its lens |
| `house_spots` | true | the bake's four house lights high over the seats (a ceiling's cans); off for a hall open to the sky (since 2026-11-08) |
| `handrails` | true | brass handrails along the side walls; off where a kit's house fronts stand along the walls (since 2026-11-08) |
| `doors` | true | the four exits with signs |
| `side_walls` | true | the side and rear walls; false: a kit draws them (the Palace of Culture's board-marked concrete round its mosaics; since 2026-11-08). The wall behind the screen stays |
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
| `civic` | 338 | | yes | a 1970s civic hall's seat: woven upholstery on a moulded oak shell, oak arms and standards (the Palace of Culture; since 2026-11-08) |
| `recliner` | 428 | | yes | a premium recliner without arms: a deep cushion, a reclined back in two pads (lumbar and headrest), a shell to the floor; the room draws the armrests between the seats (the Flagship's kit, `flagship_rows`), so the viewer's own seat folds away and both its arms stay (since 2026-11-08) |
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
  `up` does the same with the tipped-up form (since 2026-11-08, for Reclaimed's empty stalls).

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
| `up` | [] | room seats drawn tipped up, a builder's own too (at most 24; tip-up models only) |
| `fold_own` | true | the viewer's own chair folded away |

## The motion system

`scripts/env/systems/motion.gd`. Slow moves of the room's things. It never moves the viewer or their horizon
(`moves_viewer` false in its spec).

One motion system moves one thing. Give each its own id: the id names its actions (`organ.rise`). The thing is:

- a node the document names: `node` (its name, or the plain name it had before `own()` gave it its system's id),
  among the nodes of the system `system` (an id), or anywhere in the room when `system` is empty;
- or a festoon curtain it builds itself: `build` "festoon". It hangs over the screen (`festoon_size` 0: the
  screen's size with a margin) in `festoon_swags` swags, `festoon_depth` in front, its top `festoon_top` over the
  screen's top (0.5 m by default), in the `curtain` material. Fully up, its swags hang about a seventh of its drop
  and up to 0.66 m more under its top: hung higher, behind a proscenium's head, it clears the picture (since
  2026-11-08, the Streamline 1937: `festoon_top` 2.3, a drop of 8.05 m from over the proscenium's head to the stage).

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
  a swirling carpet, corrugated tin, plasterboard, quarry tiles) are our own maps, drawn in `procedural.gd` and put on
  a library material. The library material is CC0, so the licence check still holds. `quarry_tiles` (since
  2026-11-08): square terracotta tiles in mortar, each its own shade and wear, at 256 x 256 (`SIZES`: a pattern can
  have its own size; the others keep theirs). `board_concrete` (since 2026-11-08, the Palace of Culture): concrete
  cast against boards, ten to a repeat, each its own tone and depth, butt joints, grain, the fins between boards,
  tie holes and blowholes, at 256 x 256.
- **Text** is our own stroke font (`kit/strokes.gd`): Latin capitals and figures, and since 2026-11-08 the Greek
  capitals that differ from Latin ones (Γ Δ Θ Λ Ξ Π Σ Φ Ψ Ω; the others, Α Β Ε and so on, draw as their Latin
  look-alikes through `ALIASES`).
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
- **`style`** (since 2026-11-08, the Nave's deep pass): `plain` (the default: the nave above, unchanged) or `gothic`
  (`kit/nave_gothic.gd`): clustered piers with dark polished shafts and foliage capitals, pointed arcades of two
  orders, a triforium, a clerestory of two-light windows with bar tracery, quadripartite rib vaults over the nave, the
  chancel and the aisles (`vault` `rib`), coloured glass of our own drawing, a rose window over the screen, a chancel
  arch on continuous mouldings, flagstones with ledger stones, carved pews it draws itself (no `seats` system: they
  are baked), a reredos round the screen, a hymn board, candles on iron stands, iron coronae, a votive stand, the
  west doors. Its own parameters: `chancel_width` (0: the nave's and 1.2 m), `window_glow` (live), `moonlight` (the
  Moon's spots for the bake through the south windows), `coronae` (how many hang, one a bay), `coronae_lit`,
  `votive`, and materials `webs`, `cloth`, `iron`. The plain style ignores them. Its stone is our own maps (ashlar,
  a plain grain for the carving, a paving face; `_stone_maps`), its glass our own pictures. Every lightmap atlas is
  laid out at a coarser texel than the builders' 0.1 m (`RoomMesh.texel`, since 2026-11-08: 0.2 m on the walls and
  floor, 0.3 m on the vaults' webs, 0.4 m on the carving), so its nine baked meshes total about 0.7 M texels.

### `dome_hall`

A round hall under a dome, glass or solid. A low drum wall, lamps round it, a low stage, seats on arcs round the
screen (style `ring`). Beyond glass: nothing (a sky system's sky), deep water, or a dark night. With `has_floor` and
`seating` off, it covers another builder (the crater: an amphitheatre under a glass dome).

- `radius`, `centre_z`, `floor_y`, `drum_height`, `dome_height`, `dome` (`glass` or `solid`), `ribs`, `rings`.
- `outside` (`none`, `water`, `night`), `water_top`, `water_deep`; live: `outside_glow`.
- `glass_colour` and `glass_alpha` (0.05; lower is clearer): a pale tint at a low alpha keeps the view out clear,
  where before a room needed a near-black tint to stop the glass hazing what lies outside.
- Seats: `rows_front`, `rows_back`, `row_depth`, `seat_pitch`, `arc_deg`, `seat_model`.
- `rib_phase` (0..1): the ribs turned by that share of the gap between two (0.5: none straight behind the screen).
- Slots: `drum`, `screen`, `proscenium`, `floor`, `ceiling`.
- Measured (glass, about 120 seats): 8 draws, 88k triangles, 4 MB.

#### The water and the sea floor (since 2026-11-08)

With `outside` water the water is its own shader (`shaders/env_water_outside.gdshader`), and everything in the water
shares its uniforms (`shaders/env_water.gdshaderinc`: the colour along a view, the murk, caustics, the floodlights'
light, the film's light through the glass). Each part is built only when the document asks for it. The geometry is
`scripts/env/systems/kit/seabed.gd`; nothing is read from a file.

| Parameter | Default | What |
|---|---|---|
| `depth` | 0.5 | live, a brightness: 0 the sunlit shallows (Snell's window overhead with the surface's waves in it, shafts round it, caustics on the sea floor), 0.5 `water_top` and `water_deep` as given, 1 the abyss (black; a few specks glow now and then) |
| `murk` | 0.07 | how quickly the water hides what lies in it, per metre |
| `water_motion` | 1 | live, `motion` (at most 1): the shafts' sway, the caustics' drift, the fronds' sway, the snow's sinking, the bubbles' rise |
| `seabed` | false | a bowl of sea floor: banks rising to the sides and behind, a trench behind the screen, two ledges near the glass that lift what grows on them over the drum |
| `rocks`, `coral`, `fronds` | 24, 0, 0 | boulders; coral on the right ledge and round it (branching coral, heads, fans, anemones); kelp on the left ledge and in beds |
| `wreck`, `vent`, `bubbles` | false, false, 140 | an old diving bell on its skid, a fallen derrick, an anchor; a vent's chimney and its bubbles rising past the glass |
| `snow` | 0 | marine snow: quads sinking slowly round the dome, never inside it (moved in the vertex shader: no particle system) |
| `floodlights`, `flood`, `flood_colour` | 0, 1, warm white | lamps on the drum's top outside aimed at the features, their beams in the murk (`flood` live, a brightness) |

#### The fittings (since 2026-11-08)

`scripts/env/systems/kit/dome_fittings.gd`: `portholes` (round ports in the drum, none in front), `rivets` (along a
glass dome's ribs and the drum's ledge), `gauges` and live `gauge` (each needle swings from its own rest by its own
share; bind `gauge` to `film.bass`), `console` (an instrument desk behind the seats with a sonar scope,
`shaders/env_sonar.gdshader`; live `sonar` its glow, a brightness) and `hatch`. Unbaked (small faces), lit as the
seats. The console is a physics box. `needle_readings()` gives the needles' readings (tests: headless, a MultiMesh
keeps no transforms).

#### A Moon base's dome (since 2026-11-08)

`scripts/env/systems/kit/lunar_dome.gd`, each off by default (the dome as before): `lattice` `geodesic` (an
icosahedron with a point at the top split `frequency` times, even, so a ring of edges stands on the drum; steel struts
of a box section, a hub at every node, bolt heads on the lowest two rings, a compression ring on the drum; flat glass in
every triangle, one layer; `rib_phase` turns it by a share of a fifth of a turn; the struts and the drum unbaked: their
thousands of small faces, and the drum's one long strip, would multiply the lightmap's atlas), `airlocks` (0..4: a door
set into the dome's foot at 62 degrees either side of the screen, then at 118: a steel portal, the door leaf with a
round window lit warm from the vestibule, a green status lamp over it, a lit panel beside it, all `signs`; a hidden
bake light over each), `trays` (a cable tray along the drum on brackets, cables in it, broken at the doors).
`glass_reflect` (the picture's colour mirrored faintly where a pane faces the screen: one dot product a pixel) and
`glass_dust` (dust on the glass, thickest at its foot, gone 2.2 m up) are uniforms of the one glass layer
(`kit/env_glass.gdshader`, both 0 by default). Measured in the Crater (radius 18, `frequency` 6): the lattice 1 draw
and about 18k triangles, the glass 1 draw (one layer over the whole view: the dome's whole cost in fill rate).

Measured, the Bathysphere's set (`test_room_bathysphere.gd`): the sea floor with its rocks, coral, bell and chimney 1
draw and 8.7k triangles, the fronds 1 and 4.1k, the snow (1800) 1 and 3.6k, the bubbles 1, the beams 1 (480), the
lenses 1, the ports' glass 1, the scope 1, the gauges' faces 1 and needles 1, the console's lamps 3, the brass and the
dark fittings 2, the rivets 1 and 4.4k: 17 draws and about 25k triangles on top of the hall.

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
- **The Moon base** (`amphitheatre` with `lunar` on, since 2026-11-08; `kit/lunar_base.gd` inside,
  `kit/lunar_surface.gd` outside; off, the amphitheatre is as it was). Under a glass `dome_hall` in the room (its centre
  and radius are read from it): hexagonal pavers of sintered regolith (`procedural.gd` `hex_pavers`) the whole round of
  the dome; the tiers in precast blocks of about two metres, each its own shade, a chamfered nose with a strip of warm
  light under it (`steps`); a pad on every seat and a back pad on the riser behind; stairs up each end of the tiers,
  two steps a tier, a lamp in each riser and a handrail; a guard rail behind the top tier; a stage under the screen
  with footlights (`stage`), two tapered pylons carrying the frame on steel brackets, a slot of cool light high on
  each (`house`). Earth's light falls through the glass in the bake (a hidden directional light from where the sky
  puts Earth). Outside, one mesh on its own unshaded shader (`shaders/env_regolith.gdshader`: Earth's light with the
  regolith's way of scattering it back, the sun only over its shadow's line, the dome's lamps on the berm, the film's a
  little): the plain banked against the drum, craters with raised rims, boulders in dust skirts each with its own sharp
  shadow, the rover's tracks and the footprints (bands of ground drawn by the same shader, so their edges vanish), the
  crater's wall at 128 to 160 m from the dome's centre with its peaks in the sun, a base of habitat modules with warm
  windows, a lattice mast and its slow beacon, solar arrays, a cargo lander, a rover, the airlocks' tubes, an
  instrument station; and one for its lights (`shaders/env_lunar_lights.gdshader`: points that face the eye, never under
  a tenth of a degree, so a far light never shimmers). Live: `earthlight`, `base_lights`. The plain dims to 0.6 of its
  light with the house lights (never out).
- **The Athens roof and its city** (`rooftop` with `city` on, since 2026-11-08; `kit/athens_roof.gd`,
  `kit/athens_city.gd`; off, the rooftop is as it was). The roof made by hand: quarry tiles, the parapet with its
  coping and spouts, the screen building's weathered wall with ghost signs, the projection hut, the kiosk, the plants,
  the bulb strings. Its pieces share a few materials, one mesh each (ironwork, wood, painted wood, plaster, pots,
  leaves, canvas, three lamp glows by group), their own colours in vertex colours: 16 draws for the whole roof. The
  city round it is one mesh on one unshaded shader (`shaders/env_city.gdshader`): streets, blocks of flats with
  balconies, water tanks, solar heaters and aerials on the roofs, a church with a dome and two bell towers, a floodlit
  temple on a hill, a chapel on another, far hills with their lights. Its windows are drawn in the shader from each
  wall's bay and seed (lit, shuttered, curtained, louvred; faded to their average far off, so they do not shimmer);
  the Moon lights the walls from its side in the sky, the haze thickens with distance. The bulbs' halos are one
  mesh of quads that face the eye (`shaders/env_halo.gdshader`), dimmed with the house lights. Live parameters:
  `windows` (0..1, the share of lit windows' brightness; a film-time track turns it down through the night),
  `floodlight` (0..2, the temple's floodlights; a setting), `city_lights` (0..2, the streets' lamps and the church's
  light). The kiosk, the hut and the lemon tree's pot have collision boxes.
- **The whole drive-in** (`lot` with `drive_in` on, since 2026-11-08; `kit/drive_in_lot.gd`; off, the lot is as it
  was). Rows of bays on arcs fanned round the screen (`DriveInLot.bays()`), the ground as one fan grid with the
  lanes, ruts, oil and the parked cars' shadows in its vertex colours (unbaked, so it costs no lightmap), the posts
  (two speakers each, cables, an amber ramp light at the foot), `cars` parked cars (one coarse hardtop, a MultiMesh
  with its instances' colours; `parked()` keeps the viewer's bay, its neighbours and the bay straight ahead empty),
  the screen tower's back and frame, the snack bar with its booth (neon `snack_sign`, lit windows), the entrance
  marquee (`name`, the `board`'s two lines, a ring of chaser bulbs), a fence, and the highway behind. Live:
  `neon`, `chase` (the bulbs' run: 0 stops it), `ramp_lights`. Action `car_passes` (args `way`: 1 from -X to +X, -1
  back, none either): a car's head and tail lights cross the highway over 34 s. The parked cars' paint and chrome
  reflect as the car's do (`kit/reflect.gd`). The MultiMesh carries meta `env_placed` (its instances' transforms),
  so the sight-line check tests the cars where they stand. About 14 draws and 112k triangles with 30 cars (the
  parked cars 72k in one draw).

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
- The eras' sets (`telly`), for the history of television:
  - `mirror_lid` (1937): a tall cabinet whose tube faces up in its top, and a lid hinged along the back of the top,
    open at 45 degrees, a mirror on its underside. The picture you see is the tube's reflection: upright, behind the
    mirror (7 cm out from the front wall), its bottom 5 cm over the cabinet's top. So `screen_for()` gives the
    reflection's place and the app's screen sits there. The tube's face lies under the top board (`TUBE_SINK`, 28 mm
    down), the hinge and the face 28 mm further out to match, so the face's reflection is still the picture's place.
    The mirror is a true one (`Mirror`, `scripts/env/mirror_view.gd`, 2026-11-08): for each eye a camera at the eye's
    mirror image renders what the mirror shows (its near plane on the mirror, its frustum the mirror's rectangle, off
    axis), into a small SubViewport the mirror's glass shows that eye (`shaders/env_mirror.gdshader`, old silvering:
    a little dim and warm, the edges slightly tarnished). The film lies on the tube's face (`TubePicture`: the
    screen's flat mesh and its material, so the presentation's tube, scan lines, switching and Wrong way round carry
    over, at the screen's mirror image), and the app's upright screen is hidden from every camera while the mirror
    shows (its render layers 0, given back when the room goes or hides). So the mirror shows the room in front of
    the set (the top board, the rug, the floor), and looking down into the cabinet the picture is on the tube, upside
    down as a real set's was; from the side or above nothing floats behind the lid. The mirror's glass is on its own
    render layer (19), which its cameras leave out, as they leave out the private layer (20): an agents' terminal on
    the screen shows on the tube but not in the mirror, so a room snapshot never sees it there. Cost: two more renders
    of the room a frame (no shadows, no MSAA), each `MirrorView.PIXELS_WIDE` (720) pixels across, the knob; no render
    while the mirror is out of view (80 degrees off the head's forward), seen from behind, or hidden (a 180 / 360
    film). The lid is its own mesh (`Lid`: see-through for the sight line, its back lies across the line of sight; in
    `env_in_front`, so the film layer steps aside). The cabinet is at least 0.7 m wide, so seats well to the side
    still see every corner in the mirror (tested from every seat). 0.3 x 0.24 m (5:4), its bottom 0.98 m. The lid is
    not a physics shape. Use the presentation's `tube` 1.25 (`mirrorlid_1937`).
  - `console` (1960s): a wooden cabinet on four splayed legs, the 4:3 tube over a speaker's cloth grille, two knobs.
    `telly_doors`: two doors, open and folded back beside it. 0.48 x 0.36 m, its bottom 0.62 m.
  - `rear_projection` (2002): a big deep cabinet from the floor (0.62 m deep below the picture, 0.36 m behind it,
    the back sloping between), a narrow frame round a grey-black screen, two speaker grilles under it. About 50
    inches: 1.016 x 0.762 m (4:3), or 1.107 x 0.623 m with `telly_aspect` `wide`. Its bottom 0.55 m.
  - `oled` (the present): a very thin panel (3 cm with its electronics), a hair's bezel, a true black glass, a slim
    pedestal on the stand or flat on the wall. Always 16:9; 1.21 x 0.68 m (55 inches).
  - The first three stand on the floor: `telly_stand` does not apply, and the screen is the set's depth and 5 cm out
    from the front wall. Left on 0, `screen_bottom` is the form's own.
- `telly_aspect` (`auto`, `standard`, `wide`): the picture's height from its width, 4:3 or 16:9. Auto: as
  `screen_size` gives it (a flat panel and an OLED always 16:9).
- `telly_doors` (bool): a console's doors.
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
- `shell` (`drawn` by default, or `kit`, since 2026-11-08): with `kit` the builder lays out the room (its box, the
  window, the doorway, the screen, the seats' places and slots) and draws only the seats, the lamps and the fairy
  lights; the walls, floor, ceiling, window and doorway are a kit piece's (the Ice cinema's `ice_shell`).
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
  radiogram's top beside the set when there is half a metre; else the floor in front of the stand). A console's and
  a rear projection's `telly_stand` is the set's own top; for a set on the floor `telly_shelf` is the floor in front.
- Measured: plain 13 draws, 4k triangles; walnut 16 draws; bedroom 18 draws, 6k triangles; ice 11 draws, 12k
  triangles. 4 to 10 MB. A telly on its stand adds no draw of its own (the set is one mesh, the stand is in the trim):
  each form on each stand in a plain room is 12 draws and 3.8k to 4.2k triangles. In a small plain room
  (`test_env_domestic.gd`): an OLED 12 draws, a console and a rear projection 13 (their cloth), the mirror-lid set 14
  (its lid and its mirror), 2.2k to 2.4k triangles.

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
- Since the drive-in's quality pass (2026-11-08) the body is lofted from sections (`kit/car_shape.gd`: the bonnet's
  crown, the belt line into the fins, the arches, the side spear), with a jet ornament, bumpers and grille, a lit
  dash (`shaders/env_dash.gdshader`: speedometer, radio, gauges, and a clock whose hands follow the sky's `hour`), a
  big thin wheel, tuck-and-roll benches and the lot's speaker on the door. More parameters: `dash_light` (the dial
  light's stand-in lamp on the benches), `trim` (the dash pad's colour), `speaker`; live: `reflect_screen` (how much
  of the screen the paint and chrome show), `glint_at`, `glint_colour`, `glint_energy` (a light seen in the chrome:
  the snack bar's neon). Paint and chrome use the house shader's `REFLECT` (`kit/reflect.gd`): the sky's colours,
  the skyline, the ground, the screen with its picture and the glint, refreshed each frame from the `sky` system and
  the screen; no probe. `reflective_materials()` gives them (the tests).
- It brings no screen. `screen_for()` gives the lot's, so a test room has one.
- Slots: `dash`, `bonnet`, `rear_shelf`, `floor`.
- Measured: 9 draws, 24k triangles. Not baked: its occlusion (the cabin's floor, the footwells) is in its vertex
  colours.
- **Shared pieces the drive-in added** (each off by default, so every other room is as it was): `RoomMesh.grid()`
  (a grid of rows of points with normals and colours) and `RoomMesh.shade(f)` (darkens the vertex colours by a
  function of position: baked occlusion); `room_lamp.gdshader` and `kit/env_flame.gdshader` `use_vertex_colour`
  (many lamps of different colours in one draw); `kit/env_glass.gdshader` `sky_colour`, `sky_mix` (glass at a
  grazing angle shows the sky, not grey); the house shader's `REFLECT` define
  (`shaders/room_material_house_reflect.gdshader`, through `kit/reflect.gd`).

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
| `pattern` | the carpet's pattern, one of `procedural.gd`'s (`swirl_carpet` by default; `deco_carpet`: rising suns in rows, since 2026-11-08) |

Other parameters: `builder` (the builder's id; empty: the room's first builder); materials `stone`, `plaster`,
`wood`, `tin`, `roof`, `iron`, `plastic` (a computer), `fabric` (a rug), `china` (a tea set, plates), `cloth`
(bunting, sandwiches; the last two coloured per vertex), `gilt` (a palace gate's mouldings, the organ's grilles),
`drapes` (a palace gate's drapes and swags); `glass_colour` (a glass table's top); colours `leaves`, `flowers`, `neon`,
`window_colour`, `lamp_colour` (a standard lamp's shade), `display_colour` (a video recorder's clock); `bake_lamps`
(how many of the pieces' lamps light the room, 4 by default: a stand-in lamp while there is room for one, a hidden
light in the bake); live: `glow` (lit windows, the booth's window, neon, the clocks), `night` and `ember` (the
courtyard's windows going out one by one, and what one that has gone out still shows), `water_motion` (a fountain's
water; the Motion setting scales it), `flicker` (how much the pieces' candle flames waver, slowly; 0 by default,
Flickering lights holds them). Two more entry keys for the courtyard's pieces: `features` (a house's
features, below) and `seed` (its own variation). For the moderne hall's pieces (since 2026-11-08): materials
`faience` (glazed tiles: it shines, a clear glaze) and `chrome` (it reflects the room: `kit/reflect.gd`), `group` (the
pieces' meshes under one node of that name, so a motion system moves them together: an organ console on its lift),
and live: `cove` (the coves' lamps, times the house lamps' level), `cove_colour` (their light: a setting or a cue
moves it), `cove_film_colour` (their light in the film: bind it to `film.colour`) and `cove_film` (0: `cove_colour`,
1: `cove_film_colour`). For the Palace of Culture's hall (since 2026-11-08): material `mosaic` (the bed under a wall
mosaic's tesserae; `white_marble` by default), `mosaic_glint` (how much gold and glass glint, 1) and `mosaic_wash`
(the lamp line's wash down the mosaics, times the house lamps, 1.6). For the Flagship's hall (since 2026-11-08), live:
`starlight` (a starlight ceiling's pinholes before the film; 0, the default: none) and `starlight_film` (the share of it
kept while the film plays, the house lamps out; 0 by default); the hall eases the stars to their level over about a
second, so a setting never makes them jump. The Flagship's wash uses `cove`, `cove_colour` (and `cove_film`) as the
moderne hall's coves do.

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
| `carpet` | the builder's floor takes a carpet's pattern (`pattern`; the swirls by default) |
| `partition` | a plasterboard wall with taped joints and a skirting |
| `curves` | two bands in waves along a wall (pink and blue by default) |
| `desk` | a top, a pedestal of three drawers on its right, legs on its left, a modesty panel (`wood`, handles in `iron`). 1.2 x 0.74 x 0.65 m |
| `computer` | a flat beige case with two drive slots, a CRT monitor on it, a keyboard with its rows of keys in front (`plastic`, the glass and slots in `iron`). `holds` `none`: no monitor (a telly is its screen) |
| `video_recorder` | a slim case (`iron` in the entry's colour), the cassette's door, five buttons, a display window whose clock flashes 12:00 (below). 0.43 x 0.09 x 0.3 m |
| `sideboard` | doors either side, three drawers between, short legs, the top overhanging (`wood`, handles in `iron`) |
| `standard_lamp` | a round base and a thin pole (`iron`, or the entry's `accent`), a drum shade that glows in the entry's colour (`house` group) and gives a dim stand-in lamp |
| `rug` | a field (`fabric` in the entry's colour), a border a little raised (its `accent`, or the field's darker), a fringe at either end |
| `coffee_table` | a top on four legs, a shelf under it (`wood`) |
| `bunting` | a string across a room sagging by the size's height, a pennant every 0.26 m, red, white and blue in turn (`colour`, white, `accent`); it hangs from its point (`cloth`) |
| `tea_set` | a tray (`wood`), a teapot in the entry's colour, a milk jug, a sugar bowl, four cups on saucers (`china`) |
| `sandwiches` | a plate (`china`), triangles of bread with the filling between (`cloth`, the filling in the entry's colour), two layers |
| `stool` | a round seat on four splayed legs with rungs (`wood`). 0.36 x 0.46 m |
| `channel_dial` | a rotary channel dial: a plate (`plastic` in the `accent`), twelve stops, the knob and its pointer, two small knobs under it (`iron`); it hangs on a set's front, in the strip beside the picture |
| `soundbar` | a long low case (`iron`), its cloth front (`fabric` in the `accent`). 0.9 x 0.065 x 0.09 m |
| `floor_lamp` | a flat base, a slim pole, a tall column shade that glows in the entry's colour (`house` group) and gives a dim stand-in lamp |
| `glass_table` | a low coffee table: a steel frame (`tin`), a glass top (the kit's glass mesh `PieceGlass`, `glass_colour`, in `env_see_through`) |
| `media_unit` | a long low cabinet on a dark plinth set back under it, three doors without handles (`wood`) |
| `house` | a courtyard's house front along a wall (`kit/courtyard.gd`): `size` [width, the eave's height, how far its face stands out]; its wash `colour`, its shutters' `accent`, `seed`, `features`. Two or three storeys of windows lit from inside, a socle on the ground, string courses, quoins, an eave of tiles on rafters |
| `palace_gate` | round the room's screen: two towers (a rusticated base, an organ's grille in a tall arch, a belfry with a bell, a pyramid roof with a gilt finial), a great segmental arch over the picture with a balustrade and urns against the sky, gilt mouldings, a keystone cartouche, velvet drapes and three swags with gilt fringe; four floodlights for the bake. `size` [the room's width, 0, depth] |
| `cypress`, `palm`, `pine` | trees beyond the walls: `size` [spread, height, spread]. A cypress of jittered rings, a palm with feather fronds, a stone pine's umbrella of clumps |
| `lantern` | a wall lantern on an iron bracket, its glass glowing (`house` group; a stand-in lamp and a bake light) |
| `pedestal` | a stone pedestal; `holds` `lion` (lying, head up) or `urn` |
| `ice_shell` | an ice hall over a domestic builder with `shell` `kit` (`kit/ice_hall.gd`): the floor of packed snow, walls of sawn ice blocks in courses cut round the window, the doorway and the candle niches, the vault of ice blocks on ribs of clear ice with skylights in its haunches, the window's and the doorway's reveals, a candle in each niche and one on the window's sill |
| `ice_screen` | round the room's screen on the front wall: a smoothed panel, a carved frame of three frosted steps, animals in relief (a polar bear, a whale, a fox, a hare, a snowy owl with its wings spread over the picture) with their lines cut in, a candle niche either side |
| `ice_benches` | a bench of ice under each row of the room's seats (the seats system's `hide` lays the pelts on it) |
| `ice_outside` | the night outside an ice hall: a snowfield with drifts, snow banked against the walls, the path from the doorway, spruces under snow, the forest's edge, the fells, a cabin far off with its windows lit |
| `moderne_hall` | an auditorium builder's hall as a 1930s moderne one (`kit/streamline.gd`, no slot): a ceiling of coves stepping up to the screen, ledges with their coves along the walls, speed bands of faience, jade and chrome round the hall and across a bowed circle front, rounded rear corners, a walnut dado, reeded pilasters, etched glass shell lights (stand-in lamps and bake lights), ventilators |
| `ziggurat` | round the room's screen (no slot): three frames stepping out towards the seats, each lit from behind the next, gilt reveals, a glowing rising sun with gilt rays and chrome speed lines, two organ grilles lit from their chambers, a clock telling the real time (`PieceClock`), a speed-line roundel, footlights (stand-in lamps in the coves' colour) and the lift's chrome ring in the pit |
| `culture_hall` | an auditorium builder's hall as a 1970s palace of culture (`kit/palace_culture.gd`, no slot; set the auditorium's `side_walls` false and `ceiling_cover` 0): board-marked concrete walls, a wall mosaic either side (`kit/mosaics.gd`, the cosmos and the earth, on the house shader's `MOSAIC`) in a bronze frame under a cornice with its lamp line, a coffered ceiling with a roof light over the back rows (snow on its ledges), a stepped concrete proscenium with ribs and a bronze edge, oak slats on the rear wall, the booth's band and a 1970s clock (`PieceClock` `style` 1) |
| `globe_field` | 60 opal globes on rods from a `culture_hall`'s coffers, hung in a bell (`PieceLamps`, `house` group, `rim`); each lights the coffer over it (`PieceCove`) |
| `flagship_hall` | an auditorium builder's hall as a modern premium auditorium (`kit/flagship.gd`, no slot; set the auditorium's `side_walls` false, `ceiling_cover` 0, `proscenium` none, `handrails` false): folded acoustic walls in charcoal felt with bronze fins over a walnut dado, a light slot between them washing up the folds (per vertex, the house shader's `vertex_light`), a handrail with a warm line under it, cove ledges with a cool wash on the ceiling's edges, long baffles with starlight between them (`starlight`), black velvet masking on the picture's curve in a slim bronze frame, a proscenium of walnut slats, a perforated grille on the stage's front, surround speakers, walnut slats and a band round the projection port on the rear wall |
| `flagship_rows` | the rows' furniture round the `recliner` seats: fixed leather armrests between the seats and at the rows' ends, a brushed-steel cupholder ring on each, the seat's number engraved on a plate (`SeatNumbers`), lit row letters A to N on the end arms (`RowLetters`, the steps' group), steel nosings on the aisle steps, a frameless glass balustrade with a lit cap rail at the front row |
| `organ_console` | an illuminated organ console on its lift platform, its foot at `at`: a skirt of glass panels in the coves' colour between gilt fins, an ivory horseshoe of stop tabs, three manuals, a lit music desk under a chrome hood, a bench. Put it in a kit of its own with `group` |
| `ruin_shell` | a ruined picture house round an auditorium builder with `shell` `kit` (`kit/reclaimed.gd`, no slot): brick walls under fallen plaster with damp, pilasters and a cornice, the proscenium with faded gilt and lattice grilles, the stage, the stained sheet and its fallen masking, a torn curtain, the pit's broken boards, the booth's ports, two doorways |
| `ruin_roof` | the ruin's roof: the front half's coffered plaster ceiling with holes, its broken edge (snapped joists, dangling laths), the trusses over the open half, purlins, rafters and slates, a hole through the front roof |
| `ruin_stalls` | the ruin's stalls: the fallen chandelier and its crystals, rubble and fallen bricks, the aisles' rotted carpet, leaves on the seats |
| `ruin_growth` | the ruin's nature: ivy masses and cascades, a birch, ferns and hart's-tongue, grass and wildflowers, moss, leaf litter |

The furniture is drawn by `scripts/env/systems/kit/furniture.gd` (plain boxes and turned shapes of our own: no maker's
shape, no badge, no lettering), which the domestic builder's telly stands use too. A piece stands with its foot at the
slot's point and its front towards the slot's +z; the domestic builder's `telly_stand` and `telly_shelf` slots are
made for it (the computer on a desk beside a portable, the video recorder in a tv unit's shelf).

**The courtyard's houses** (`kit/courtyard.gd`, since 2026-11-08). Each house samples the ground under it (the
stage, the aisle's rake), so its socle meets the floor and its storeys stand level. Its `features`: `balcony` (an
iron balcony with real depth on brackets), `balconettes` (one at each upper window), `loggia` (an open top storey on
columns), `tower` (a belvedere with arches and a pyramid roof), `pergola` (beams and leaves for a roof), `gable`
(a pediment instead of an eave), `oriel` (a Moorish bay on corbels, its lattice lit), `exit` (an arched way out with
the room's sign), `door`, `niche` (an urn in a shell niche), `lion_niche`, `fountain` (a wall fountain: blue and
white tiles, a lion's mask, a basin with moving water), `lanterns`, `vines` (bougainvillea up the wall and over the
balconies), `rug` (a rug hung over a balcony rail), `geraniums` (pots on the sills), `grilles` (iron grilles on the
ground floor's windows), `booth` (the projection ports with the lens glowing), `arcade` (an open ground floor of
arches) and `dark` (no one home: every window dark). Each window is one of six rooms behind (a curtain drawn left,
right, both with a lamp, a plant on the sill, inner shutters half closed, an organ's pipes) drawn by
`shaders/env_courtyard_window.gdshader` from the window's own coordinates, never from a picture; a few are dark.
The windows' material is the light system's lamp material (house group), so they dim with the house lamps; `night`
puts them out one by one, each at its own moment (each over a twentieth of `night`'s travel), down to `ember`. The
windows bake as emitters: their glow lights the reveals, sills and shutters round them.

**The ruin** (`kit/reclaimed.gd`, since 2026-11-08, for Reclaimed). Its four pieces read the auditorium's layout
and draw into meshes of their own: `RuinBrick`, `RuinPlaster`, `RuinWood` and `RuinCloth` (baked, on the house
shader with `vertex_light`: the Moon's light, traced per vertex as the room is built, in the vertex colours' alpha),
`RuinBrass` and `RuinLeaves` (unbaked, the Moon in their vertex colours), `RuinCrystal` and `RuinPort` (emission).
It also tints the auditorium's `Floor` and `Seats` by the same Moon. See "Room: Reclaimed".

**The ice hall** (`kit/ice_hall.gd`, since 2026-11-08, for the Ice cinema). Its pieces read the room's domestic
builder (its box, window, doorway, screen and seats) and draw into meshes of their own: `IceBlocks` (the walls' ice,
baked), `IceVault` (the vault: smooth strips on the ice shader, its courses drawn by `ice_vault`, baked), `IceSnow`
(the joints, baked), `IceFloor` (the floor on the ice shader's snow form, `ice_snow`, baked), `IceFurs` (pelts on the
floor, baked), `IceCandles` and `IceFlames` (the candles: wax and dish lit by their own flames, all emission in vertex
colours on the lamp material; the flame and its halo in one picture; in the light system's `accent` group, the front
wall's in `house`), `IceGlass` (the skylights' and the window's clear panes, see-through) and `IceOutside` (the night, its own
unshaded shader `shaders/env_ice_outside.gdshader`: lit by the sky's colours, the Moon and the aurora, never by the
house lights; the snow glitters a little where a facet catches the Moon, still in the world). The ice is the light
system's house material on `shaders/room_material_house_ice.gdshader` (`ICE` in `room_material.gdshaderinc`): what is
frozen inside a block (bubbles in strings, cracks, a milky cloud: one tileable map made in code) is drawn at two depths
along the view, so it moves against the face as the head moves; the light that reaches the ice (a lightmap's) shows on
those, at depth, while the clear face takes little; the candles' glow is scattered inside the ice round each candle
(`ice_glow_*`, the room's frame, their group's level each frame); the film's colours seep through the front wall round
the screen (`ice_film`); the candles glint and the picture shows softly in the wet faces at a glancing look. The vertex
colour's alpha says what a surface is: 0.5 to 1 a block, milky to clear (and its own seed for what is inside it); under
0.5 frosted: the carvings, the frame, every block's sawn edges. The candles light the bake (the kit's lamps, hidden)
and the Moon comes in through the window for it (a hidden spot from the sky's Moon). More of `ICE`, each off by
default (since the second pass, 2026-11-08): `ice_glow_face` (the candles' light on the faces round them: a niche lit
warm inside), `ice_vault` and `ice_vault_block` (a vault laid in courses: joints packed with snow, frosted edges,
each block its own seed, shade and tilt, all from the point's place on the arch), `ice_snow` (packed snow instead of
ice: boot prints pressed in, shaded by the normal they tilt, and a sparkle near the eye that changes only as the head
moves; no candle loop), `ice_shine` (the picture's share of the gloss).
**The moderne hall's coves** (`kit/streamline.gd`, `shaders/env_cove.gdshader`, since 2026-11-08: "the coves are the
star: soft graded colour washing up curved surfaces, not flat fog quads", the brief). Every surface a hidden lamp
washes (the ceiling's bands, the ledges' rounds, the proscenium's frames, the organ grilles' chambers, the rising
sun, the console's glass) is one mesh, `PieceCove`, on its own opaque shader. The light on it is worked out when the
mesh is built, per vertex (the alpha of its colour): each lamp a line along its trough, its light the cosine
(softened: plaster scatters) over a fall-off to half at a metre or so. The shader adds it in the cove's colour (and
a whiter core where it is strongest) to the house shader's own light (the fill at the house level, the screen's
spill at 0.6 of the room's) and a faint mottle of the plaster; one noise fetch, no loop, no light pass, nothing
transparent. Its colour and energy are live (`cove_colour` toward `cove_film_colour` by `cove_film`; `cove` times
the house lamps), so a setting, a cue or the film moves it without building the room again. It is not baked: the
bake takes the slots' light from a hidden lamp in each (`KitGlow*`). Footlights at the stage's lip and two battens
behind the first frame's head are stand-in lamps in the coves' colour (they light the festoon's folds and the
console, which are never baked). `cove_state()`, `cove_colour_now()` and `clock_hands()` give the coves and the
clock now (tests).

**The palace of culture's hall** (`kit/palace_culture.gd`, `kit/mosaics.gd`, since 2026-11-08). A piece may add a
hall to the ctx's `halls`: an object with `finish(kit)`, called once every piece has drawn (the hall puts its own
meshes in, here `Mosaic`, and sets the clock's face), and `tick(delta)`. The mosaics are one static mesh on
`shaders/room_material_house_mosaic.gdshader` (`MOSAIC` in `room_material.gdshaderinc`, off in every other form):
`mosaic_map` holds one texel a tessera (rgb its colour, alpha its kind: 0 stone, 0.5 glass, 1 gold); the shader lays
the courses in the mesh's UV (metres), each tessera fetched at its middle, with uneven joints of `mosaic_grout`
(antialiased by the pixel's footprint, thinning to `mosaic_joint` far off), a shade, a tilt (`mosaic_tilt`) and a
worn edge of its own (`mosaic_wander`). The glint is a sharp lobe (`mosaic_glint_sharp`) of the light from
`mosaic_glint_pos` (the room's frame) and of the screen's spill (`mosaic_film_glint`), weighted by the kind cubed
(gold glints, glass a little, stone hardly) and tinted by the tessera; it moves only as the head moves.
`mosaic_wash` (rgb, w the fall in metres) washes down from `mosaic_wash_y` at the house lamps' level. The lamp shader
`room_lamp.gdshader` has `rim` (0 by default: off): a glowing ball brighter where it is seen square on. The clock
shader `env_clock.gdshader` has `style` (0 by default: the moderne face; 1 a dark dial with lit bars).

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
- Measured: bougainvillea along the rooftop's 14 parapet places: 2 draws, 23k triangles. The Atmospheric 1928's
  courtyard (since 2026-11-08): 16 draws, about 77k triangles (its room section has the parts).

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
| Ice cinema | `atmosphere`: `breath` 0.6, a little low `fog`; `weather`: `falls` snow, `mode` light, 260 flakes in two areas outside (the doorway's and the window's) |
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
| `sound` | `silence` | loops: `projector`, `wall_rumble`, `cicadas`, `radiator`, `rain_glass`, `rain_leaves`, `gas_hiss`, `noise`, `crickets`, `fire`, `drips`, `wind`, `hum`, `deep_hum`, `fountain`, `clock`, `tube_whine`, `bubbles`, `city`; one-shots: `moped`, `train`, `huskies`, `hull_creak`, `rumble`, `tick`, `creak`, `whale`, `chime`, `gong`, `bird`, `purr`, `three_bells`, `candle`, `ice_creak`, `vcr`, `tape_load`, `sonar`, `church_bell`, `tawny_owl`; `silence` plays nothing (the sounds: below) |
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
| `bubbles` | loop 6 | a vent's bubbles in deep water: bursts of low bubbles (tones that rise as they ring) between quiet spells, the water's soft hiss (since 2026-11-08) | a vent outside the glass |
| `sonar` | one-shot 3 | a sonar's ping: a soft round tone at 1.18 kHz with a faint beat, swelling in over 15 ms and ringing down, a lower octave under it, and 1.25 s later its echo off the sea floor, duller and a third as loud (since 2026-11-08) | a bathysphere's pre-show (a cue's `do`); a cue sound too |
| `moped` | one-shot 8 | a small two-stroke passing, 15 m away at its closest; with `to` it travels | a street below |
| `far_car` | one-shot 34 | a big old car on a highway 78 m off at its closest, 25 m/s: tyres on concrete (the slabs' joints a soft double knock), a V8's low, uneven burble, its pitch riding the passing, duller when far; the level by distance is the 3D player's (`reach` the closest distance), only the far ends fade in it (since 2026-11-08; designed level -56) | the drive-in's highway, with `to` and a cue (`far_car.play` with `car_passes`) |
| `train` | one-shot 40 | a freight train far off: the roll, the rail joints, the horn's two notes early on | far off, `every` |
| `huskies` | one-shot 7 | three far howls and a few yips, an echo | snow |
| `scops_owl` | one-shot 9 | a scops owl's call over the roofs: four soft whistled "tew"s 2.5 s apart, each gliding down from 1.25 to 1.17 kHz, a breath of air, softened by distance (since 2026-11-08) | a warm night, `every` |
| `tawny_owl` | one-shot 7 | a tawny owl in the trees round a church: a hollow "hooo" sliding down from about 420 Hz, a pause, a short "hu", then a long wavering "hoo-oo-oo-oo" (the voice trembling about eight times a second), a breath of air, softened by distance (since 2026-11-08; designed level -58) | a churchyard at night, `every`, far off |
| `hull_creak` | one-shot 3.5 | steel under pressure: stick-slip pulses through a low groan and bright partials | a hull |
| `church_bell` | one-shot 14 | a parish church's bell across the roofs: three strokes 3.2 s apart, each a struck bell's partials (hum, prime, minor third, fifth, octave; damped oscillators, the hum ringing longest), a faint echo off the houses, softened by distance (since 2026-11-08) | before the show (a cue's `do`), far off |
| `city` | loop 12 | a summer city at night from a roof: a low murmur of traffic that swells and settles, a faint hiss, three far engines passing in the loop (since 2026-11-08) | round a roof, from the streets below |
| `ice_creak` | one-shot 2.6 | a crack that sings down, then a low groan | ice, `every` |
| `candle` | one-shot 0.9 | a candle's flame puffs and wavers, three or four sputters of wax | `every`, very low |
| `three_bells` | one-shot 3.2 | a soft house bell: three struck-bar tones, up a fifth, down a minor third (our own call) | before the show |
| `vcr` | one-shot 4.5 | a video recorder takes a tape: the clunk, the motor threading the tape with its clicks, the heads engaging, the drum's whirr | a cue: the tape goes in |
| `tape_load` | one-shot 8 | a home computer loads from cassette: a pilot tone, a gap, the data's two-tone warble, the tape's hiss | a cue, very low |
| `switch_clunk` | one-shot 0.6 | a telly's power switch: the toggle's snap, the contacts' bounce, the cabinet's knock, the speaker's soft thump | the presentation's `switch_on` and `switch_off` |
| `valve_hum` | one-shot 8 | a valve set warming up: the transformer's hum and a little buzz and the speaker's rush rising over five seconds, settling and fading | a valve set's `switch_on` |
| `crt_off` | one-shot 1.4 | a tube switched off: a soft thunk, a tiny tick, the glass's static crackling faintly | a tube's `switch_off`, very low |
| `channel_clunk` | one-shot 0.45 | a rotary channel knob: the detent's ratchet, the spring's snap into the notch, a knock through the cabinet | the presentation's `channel` |
| `bird`, `purr`, `whale` | one-shot 1.2, 4, 5 | a songbird's call, a cat's purr (two breaths), a whale's song | ambient life's calls (below) |
| `chime`, `gong`, `rumble`, `tick`, `creak` | one-shot | the foundation's sounds | cues |

Cue sounds (`EnvDoc.SOUNDS`, for a cue's `sound` step and ambient life's calls): the foundation's seven, `moped`,
`train`, `huskies`, `hull_creak`, `bird`, `purr`, `three_bells`, `candle`, `ice_creak`, `switch_clunk`, `crt_off`,
`channel_clunk`, `sonar` (not `valve_hum`: 8 s, too long to make on the main thread). A cue's `sound` step plays at
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
| `bubbles` (2026-11-08) | -57 | -57.0 | -64.7 | -72.4 | -36.2 |
| `city` (2026-11-08) | -58 | -58.0 | -66.6 | -73.6 | -45.3 |
| `clock` | -56 | -56.0 | -64.0 | -71.1 | -19.9 |
| `tube_whine` | -62 | -62.0 | -70.0 | -77.2 | -55.0 |
| `noise` | -54 | -54.0 | -62.0 | -69.1 | -41.2 |
| `sonar` (2026-11-08) | -56 | -56.0 | -64.0 | | -39.7 |
| `moped` | -52 | -52.0 | -60.0 | | -42.9 |
| `train` | -52 | -52.0 | -60.0 | | -40.6 |
| `huskies` | -54 | -54.0 | -62.0 | | -46.0 |
| `scops_owl` (2026-11-08) | -58 | -58.0 | -66.0 | | -41.2 |
| `church_bell` (2026-11-08) | -54 | -54.0 | -62.0 | | -42.5 |
| `hull_creak` | -52 | -52.0 | -60.0 | | -39.3 |
| `ice_creak` | -55 | -55.0 | -63.0 | | -31.0 |
| `candle` | -58 | -58.0 | -66.0 | | -37.5 |
| `three_bells` | -50 | -50.0 | -58.0 | | -40.1 |
| `vcr` | -54 | -54.0 | -62.0 | | -41.3 |
| `tape_load` | -58 | -58.0 | -66.0 | | -56.5 |
| `switch_clunk`, `channel_clunk` | -54, -55 | -54.0, -55.0 | -62.0, -63.0 | | -26.4, -25.5 |
| `valve_hum`, `crt_off` | -58, -60 | -58.0, -60.0 | -66.0, -68.0 | | -49.7, -33.7 |
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
| Atmospheric 1928 | `acoustics` `cinema`; `sound_bed` `fountain` `at` the wall fountain, `reach` 8, `gain_db` -4; `crickets` around the courtyard (three voices, `film_db` -18); a `scops_owl` from the stone pine, `every` 55, `film_db` -40; the theatre organ (`music`) before the film |
| Screen 3, 1983 | `acoustics` `small_room` (`rt60` 0.6); `sound_bed` `wall_rumble`, `level` on `film.bass`, `film_db` 0 |
| Drive-in | `acoustics` `outdoors`; `sound_bed` `crickets` around (`radius` 8); `train` far off, `every` 900, `reach` 300 (its horn is in it) |
| Rooftop, Athens | `acoustics` `outdoors` (`rt60` 0.25, `wet` 0.15); `sound_bed` `cicadas` around, `film_db` -14 (they fade as the film starts); `city` around from 6 m below, `gain_db` -2, `film_db` -10; `moped` with `to` and `every`; `church_bell` at the church, `film_db` -30, played by the pre-show's cue; the cat's purr from `life` (`voice_db` -15 within 2 m) |
| Palace of Culture | `acoustics` `concrete_hall`; `sound_bed` `three_bells` before the show |
| Nave | `acoustics` `stone_nave` (`rt60` 3); `sound_bed` `wind` high up, `gain_db` -4; `candle`, `every` 120, `gain_db` -4. No organ, no bells |
| Reclaimed | `acoustics` `outdoors`; `sound_bed` `rain_leaves` around, `level` on `weather.rain`; `drips`, `level` on `weather.wet`; `wind`, `gain_db` -6; the birds' calls from `life` |
| Ice cinema | `acoustics` `ice`; `sound_bed` `huskies`, `every` 300; `wind` by the doorway; `ice_creak`, `every` 240 |
| Bathysphere | `acoustics` `hull` (`rt60` 0.9); `sound_bed` `hull_creak`, `every` 180, to either side; `deep_hum`, `gain_db` -4; `bubbles` at the vent outside; `sonar` pinging in the pre-show (a cue); a far `whale` song in a quiet scene (a cue); the passing whale from `life` at `voice_db` -4 |
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
| TV 1937 | `acoustics` `small_room`; `sound_bed` `fire` (on the Fire setting); `clock`; `tube_whine` `pitch` 0.648, `gain_db` -4 |
| TV 1966 | `acoustics` `small_room`; `sound_bed` `radiator`; `clock`; `tube_whine` `pitch` 0.648 |
| TV 2002 | `acoustics` `small_room`; `sound_bed` `hum` at the set (its fan), `gain_db` -3 |
| TV today | `acoustics` `small_room` (`rt60` 0.3); `sound_bed` `rain_glass` on `weather.rain`, `gain_db` -6 |
| TV tomorrow | `acoustics` `small_room` (`rt60` 0.3); no beds: a quiet room |

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
| `creature` | `moth` | `moth`, `bird`, `firefly`, `cat`, `deer`, `fish`, `jelly` (glowing deep-sea creatures), `ray` (a manta gliding over), `whale`, `plane` (a plane's lights). Built once |
| `count` | 0 | how many; 0: the creature's own (below). The cat, the deer, the ray and the whale are one at most |
| `schooling` | 0 | fish: how tightly they school (since 2026-11-08). Over 0 the school draws in (to 60 % at 1) and stretches along its way (1.9 times), and each fish keeps its place relative to where the school was a moment before, the later the further back it swims (up to 2.4 s at 1): a turn starts at the leaders and ripples back. One lookup in a short history a fish, no neighbour search |
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
| `ray` | 1 | a manta ray 4 m across its wings, dark above and pale below (the body shader's `belly`). Every 90 s on average (`every`), or on `pass`, it comes out of the gloom on one side, glides high over the room on a long gentle curve (the `path`, or a chord across the `region` at its height), banking a little into the turn, its wings beating slowly half the time and gliding the rest, and fades on the other side. 1.4 m/s at most; kept out of the sight line |
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
| the ray | 35 | 0.01 |
| the whale | 240 (102 before 2026-11-08) | 0.00 |

All nine (before the ray) at once: 9 draws, about 3600 triangles, under 1 ms a frame on the desktop. The spec declares the largest (fish,
1700 triangles); 200 fish would be 6800. The time on the Frame is not measured yet.

### For the rooms

| Room | Use |
|---|---|
| Drive-in | `moth` in the beam; `plane` with `activity` bound to `time.of_day` inverted |
| Rooftop Athens | `cat` with a `path` along the wall top, clear of the sight line; `plane` |
| Reclaimed | `bird` with perches on the broken roof's edge; `firefly` low over the floor, `glow` bound to `film.brightness`; `deer` with a path along a side aisle |
| Bathysphere | `fish` (two schools, `schooling` 0.8 and 0.6) and `jelly` outside the glass, `attraction` bound to `film.brightness`, the bells' `glow` to `film.quiet`; a `ray` gliding over every 150 s; `whale` on the quiet-scene cue, its `chance` set by the room's whale setting |

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
as before. Settings: the pre-show ritual (common), the house lights in the film. Sound: the ritual's chime as it was
(a cue's `sound` step at -6 dB, -46.2 dBFS RMS at the slider's default), and the hall's `acoustics` (`cinema`, rt60
0.7) on the room's bus; the film keeps its own mix.

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
| display | `display`: `none`, `mechanical`, `crt`, `panel`, `rear_projection`, `oled` | the set |
| crt | `curvature`, `corner`, `mask` (`none`, `shadow`, `grille`, `slot`), `mask_pitch`, `mask_strength`, `scanlines`, `glass` | the bulging face, round corners, the phosphors' mask, the gaps between lines, the glass's reflection (a soft light behind the viewer that moves as the head moves) |
| mechanical | `mech_lines` | a 1930 mechanical-scan set: a few lines across, a neon's orange glow, dark edges |
| panel | `panel_grid`, `panel_pixels`, `panel_bleed` | the gaps between the pixels, the backlight through the dark scenes |
| rear_projection | `soft_focus`, `convergence`, `lenticular`, `hotspot` | a 2002 rear projection: the picture a little soft, the red and the blue a little apart (more at the edges), the screen's fine vertical lines, a faint bright patch where the eye looks down the projector's light (it follows the head), a grey-black face |
| oled | | true blacks (no backlight, no lift), a little punch in the colour and the middle tones (black stays black, white white: the film's levels are kept), a sheen only at a glance |
| the window | `tube`, `aspect_mode`, `mirror` | below |
| off axis | `off_axis` | below |
| switching | `switching`, `warm_up`, `off_dot`, `starts_off`, `switch_sounds`, `sound_db` | below |
| colour | `colour`, `tint`, `gain` | saturation (0: black and white), the tube's tint, brightness |
| speaker | `speaker`: `none`, `window`, `telly`, `cabinet`, `panel` | the film's sound through a small speaker |

Every parameter is live but `starts_off`. `weave`, `tilt` and `tracking` are motion parameters (the room's Motion
setting scales them). `flicker` is a brightness that flickers: it wavers by at most 3.5 %, more slowly than 3 times a
second, and stays steady with Flickering lights off. Actions: `glitch` (a moment's trouble: a tape's tracking tears, a
broadcast's snow swells, a print jumps in the gate; `seconds`, default 0.6), `switch_on`, `switch_off`, `channel`
(below).

**The set's window and the film in it.** The app makes the film's quad as wide as the room's screen, its height from
the film's shape. The set's window is as wide, its shape `tube`.
- `tube`: the window's aspect, for every display (1.33 for the tubes before 2000, 1.78 for a 16:9 panel, 1.25 for the
  1937 tube; 0: the film's own). Give the room's screen the same shape: outside the window the shader discards the
  film, so the set's bezel shows there.
- When the window is taller than the film's quad (a wide film in a 4:3 tube), the quad grows to the window in the
  vertex stage (its height only, so a curved screen keeps its curve), and the bars are drawn as the set's black (with
  its glass and round corners). The flat mesh's cull margin grows by a metre while the presentation draws it.
- `aspect_mode`: `letterbox` (as before: all of the film, black bars where its shape differs; a 4:3 film on a 16:9
  panel is pillarboxed), `pan_and_scan` (the film fills the window, its sides cut off: the 1937 and 1966 presets),
  `fourteen_nine` (14:9 of a wide film across the window: a little cut, thin bars), `stretch` (the film stretched to
  the window: a 4:3 film on a 16:9 panel).
- `mirror`: the picture flipped left to right, a mirror-lid set seen the wrong way round. Off by default: the set's
  electronics turn it round.

**Off the axis.** `off_axis` (0 to 1, default 0) changes the picture by the angle from the viewer's eye to the screen's
normal, per eye: a tube a little darker from the side, a rear projection's light in a narrow fan (wide across, narrow
up and down: from 30 degrees above it is half as bright, from the side much less dim), a flat panel's contrast and
colour shifting (most from above and below), an OLED's colour a touch cooler.

**Switching on and off.** `switch_on` and `switch_off` (actions) take the set from and to dark, its own way
(`switching`; `auto` by the display):

| Way | On | Off |
|---|---|---|
| `crt` (auto for `crt`) | 1.6 s (at least 1.5): a small dot, a line opening across, then the raster opening up and down | 1.1 s: the picture collapses to a line, the line to a dot, the dot fades (its afterglow) |
| `valve` (auto for `mechanical`; `fireside_1953`, `colourstar_1972`, the 1937 and 1966 presets) | 8 s (`warm_up`): dark while the heaters warm, then the picture comes up dim and a little small, growing and brightening | 2.4 s: as a tube's, the dot lingering |
| `panel` (auto for `panel` and `oled`) | 0.9 s: it just comes up | 0.35 s: it goes black |
| `projection` (auto for `rear_projection`) | 3 s: a slow fade up | 0.6 s: a fade down |

- `warm_up` gives the seconds to come on (0: the way's own). `switch_on` takes `seconds` too.
- `off_dot` (since 2026-11-07): the seconds a tube's dot lingers after the collapse (-1: the way's own, 0.6 s for a
  `crt` and 1.7 s for a `valve` set; 0: none). Each era has its own: sets before spot suppression burned a dot for
  seconds, later sets barely showed one. `mirrorlid_1937` 8 s, `fireside_1953` 6, `rental_1966` 3, `colourstar_1972`
  1.5, `sirclive_1983` 0.8, `rewinder_1987` 0.5, `nightowl_1993` 0.25. The dot holds, then fades over at least 0.35 s.
  A mechanical set (`glowbox_1930`) has no tube: its glow dies with no dot. The TV rooms switch their set off at the
  end of the film and when the film is closed (the `switch_off` cue in `ended` and `preshow`), and time travel
  switches each era's set off and waits for its dot before it moves on (`stay_off` keeps the set dark meanwhile).
- `starts_off`: the set is dark (its face drawn: a tube's grey glass, a rear projection's grey-black, an OLED's black)
  until a cue switches it on. It comes on by itself when the film plays, so a film never plays on a dark set.
- `channel` (action, `seconds`, default 1, at least 0.9): a channel change. The knob's clunk, the picture dips to about
  half with a moment's snow and comes back; a panel goes black for a moment.
- Comfort: the light and the beam's glow each rise and fall at most once, and each fade takes at least the comfort
  ceiling's fade (`env_checks.gd MIN_FADE`). The squeezed picture and the line are never brighter than 0.85. The dot
  is small: about 3 % of the picture's height across. Tested in `test_env_presentation.gd`.
- Sounds: `switch_sounds` (default on) plays our own sounds at the screen on the room's bus, at their designed levels
  (`sound_bed.gd LEVELS`) plus `sound_db`, 8 dB lower while the film plays: a `crt` set's `switch_clunk` on and
  `switch_clunk` and `crt_off` off; a valve set's `switch_clunk` and `valve_hum` on; a projection's `switch_clunk`; a
  panel is silent. A channel change plays `channel_clunk` (not on a panel). They are made on a worker thread when the
  room is built.
- A cue: `{"do": "presentation.switch_on"}` in `starting` (the Pre-show), `{"do": "presentation.switch_off"}` in
  `ended`.

**Not built: the 1930 set's 12.5 frames a second.** The mechanical set drew 12.5 pictures a second. Holding each
frame for 80 ms needs a history of the film's frames: a copy of the decoder's planes (hardware textures on the Frame)
made 12.5 times a second by a render pass of its own, and both eyes for a 3D film. And the held frames would put a
12.5 Hz change into the picture, in the band (3 to 30 Hz) the comfort rules keep out, even behind the Motion and
Flickering lights settings. So it is left out; the 30 lines and the orange glow carry the era.

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
| `mirrorlid_1937` | TV era | a pre-war mirror-lid set: 405 lines, a small round 5:4 tube (`tube` 1.25), greenish white, snow and a ghost, the film panned and scanned, a valve warm-up of 10 s |
| `rental_1966` | TV era | a rented black and white console: 405 lines, a 4:3 tube, the film panned and scanned, a valve warm-up of 9 s |
| `projection_2002` | TV era | a 50 inch rear projection playing a disc: 16:9, soft focus, fringes, lenticular lines, a hotspot, a picture that dims from above or below (`off_axis` 0.8) |
| `slimline_present` | TV era | a very thin OLED panel: 16:9, true blacks, a sheen at a glance, a touch of colour shift from the side |

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
| `mirrorlid_1937`, `rental_1966` (2026-11-07) | 0.95 to 1.0 |
| `slimline_present` (2026-11-07) | 0.95 to 1.2 |
| `projection_2002` (2026-11-07) | 1.8 to 2.0 |

The noisy chains cost less than the screen's own shader because its deband (eight reads) is off under them; with the
deband left on they measured 1.45 to 2.2 times. The rear projection costs most: its soft focus widens the footprint
filter (held to two taps a side, so at most eight reads) and its fringes take two more samples. In the test the card
is smaller than the view, so the screen's own filter takes one sample and the rear projection's eight; with a 4K
film on the headset the screen's filter already takes up to eighteen, and the rear projection's eight are fewer. On the Adreno the screen's shader is bound by its texture reads (the footprint filter, the deband); the stages are
ALU of a few dozen operations and at most two more bilinear reads, and a telly covers a small part of the view (a
0.6 m set at 1.5 m is about 6 % of an eye's pixels). Not measured on the headset yet.

## The cinema set

Every room keeps the cross-cutting rules: a "dim during the film" setting, seat picking by pointing, its own
acoustics, music only from our synthesiser or CC0 samples (many sample sets are CC-BY and cannot be bundled), no
people.

| # | Room | Builders and kits | Light, sky, atmosphere | Life, sound, music | Timeline and cues | Screen | Settings |
|---|---|---|---|---|---|---|---|
| 1 | Shopfront picture house, 1906 | `shopfront` (pressed tin), folding chairs (`seats`), a tin booth (`kit`) | gas lamps (`light`, flicker), a dusty beam (`screen_frame`, `atmosphere`) | projector clatter behind (`sound_bed`), a player piano that plays along (`music`, `film.transient`) | the piano starts in `starting` | a framed sheet | piano on or off |
| 2 | Atmospheric, 1928 | `auditorium` with `ceiling_cover` 0, thirteen courtyard houses (balconies, towers, a loggia, an oriel, an arcade, lit windows), a palace gate with organ grilles and drapes, lions, cypresses, palms, a stone pine (`kit`) | an open dusk `sky` with real stars, a crescent moon, clouds lit by the town and the screen (`film.colour`); lanterns and floods baked | a wall fountain, crickets, a scops owl (`sound_bed`), a theatre organ before the film (`music`) | the courtyard goes to bed with the film (windows out one by one), curtains part (`showing`) | | clouds, organ |
| 3 | Streamline, 1937 | `auditorium` dressed by the moderne kit (`kit/streamline.gd`): a stepped ceiling of coves, faience, jade and chrome bands round the hall and a bowed circle front, reeded pilasters, shell lights, a rising-sun carpet; a stepped proscenium round a rising sun, organ grilles, a clock | coves that cycle colours and then follow the film at a glow (`kit` `cove_*`, `film.colour`) | an organ (`music`) | the console rises lit from the pit and the organ plays as the room opens and at the end, a cadence and the console down as the film starts (`motion`) | a festoon curtain up behind the proscenium's head (`motion`) | cove colours |
| 4 | Screen 3, 1983 | `auditorium` with `partition_z` (a subdivided balcony), plasterboard, swirly carpet, one broken seat, a water stain (picture) | smoke haze in the beam (`atmosphere`), a flickering exit sign (`flicker`) | rumble through the wall (`sound_bed`, `film.bass`) | | gate weave, a slight tilt (`presentation`) | weave and tilt |
| 5 | Drive-in, 1958 | `terrace` (the lot), a convertible's bench seat (`vehicle`), a screen tower, a neon snack bar (`kit`) | dusk to stars over the film (`sky`, film-time tracks), mesas (`vista`) | moths in the beam (`life`), a far freight train (`sound_bed`, `every`) | | the window speaker (`presentation`) | tinny speaker |
| 6 | Screening room, 1962 | `domestic` (walnut), club chairs (`seats`), a bar cart (objects) | a pool glowing through the window (`vista`) | | a painting slides up to show the screen (`motion`, ritual) | | |
| 7 | Rooftop summer cinema, Athens | `terrace` (`city`: the roof by hand), director's chairs | the city all round and a floodlit temple on its hill (`terrace` `city`), plane lights, moths (`life`) | cicadas, the city's murmur, mopeds, a church bell (`sound_bed`), a cat on the wall (`life`) | | a screen painted on a wall | |
| 8 | Pink Palace | `auditorium` with pink and blue curves (`kit`), a plush balcony (`balcony_rows`) | a sunburst ceiling with cycling lights, chandeliers (`light`) | | a ceremonial curtain (`showing`) | | |
| 9 | Palace of Culture, 1974 | `auditorium`, board-marked concrete, ochre curtains | a mosaic wall that glitters in the screen's light (material, `film.colour`), snow and birches outside (`vista`, `weather`) | an echoey hall (`acoustics`) | | | snow |
| 10 | Flagship | `auditorium`: steep rake, black walls | blue step lights (`light`) | | the ritual | a huge curved screen | seat choice |
| 11 | Nave | `nave`, pews (`seats`) | a dim rose window, candles (`light`, flicker), the film's light climbing the stone | reverb (`acoustics`) | | in the chancel | candles |
| 12 | Reclaimed | `auditorium` with `ceiling_cover` 0.5 and `shell` `kit`; the ruin, ivy, a birch, ferns and wildflowers (`kit`, `ruin_*`) | stars (`sky`), dynamic `weather` (rain into a puddle that reflects the film) | birds, fireflies, an occasional deer (`life`) | | a patched sheet | weather |
| 13 | Ice cinema | `domestic` (`shell` `kit`) with the ice hall's pieces (`kit`: blocks, carvings, a vault with skylights, a snowfield outside), hides (`seats`) | candles inside the ice, the film's colours through the front wall, the aurora in the window and the skylights (`sky`), breath fog (`atmosphere`), snow outside (`weather`) | far huskies, ice creaks (`sound_bed`) | candles down and the aurora settles with the film | | aurora |
| 14 | Bathysphere | `dome_hall` (glass; the sea floor, kelp, coral, a sunken bell, a vent, marine snow, floodlights; portholes, rivets, gauges, a sonar console) | the water by depth, Snell's window and shafts, caustics (`light`) | schools of fish, glowing creatures drawn to the screen, a manta overhead, a rare whale in a quiet scene (`life`, cue with `cooldown`), hull creaks, the vent's bubbles, a sonar ping, a far song (`sound_bed`) | floodlights down with the film, the scope dims, pings in the pre-show | | depth, lights outside, whale |
| 15 | Crater | `terrace` (`lunar`: a Moon base's amphitheatre, the plain, the crater's wall, a base, a lander, a rover) under a `dome_hall` (`geodesic`, airlocks, trays) | Earth as itself turning over the screen (`sky` `earth_detail`), the Milky Way when the lights dim, the crater's peaks in the sun | silence (no bed) | the dome's lamps out, the strips low | | Earth's speed |
| 16 | Void | `mirror_floor` | black | | | | ripple |
| 17 | Pillow Fort, 1993 | `domestic` (cushions, a bedsheet), a tree, a tin of sweets (objects) | fairy lights (`light`, flicker), rain on the window (`weather`) | a ticking radiator (`sound_bed`) | the VCR flashes 12:00 (object widget) | a CRT telly (`presentation`, TV-era display) | the telly fills the opening |

### Room: Atmospheric 1928

`app/environments/atmospheric_1928.env.json`. A picture palace built as a Mediterranean town square at dusk, as the
atmospheric theatres of the late 1920s were: the seats stand in a courtyard of plastered houses under an open sky,
and the screen is in a palace's gate. The quality pass (2026-11-08) answered "you may be able to do a large number of
superb ones, see how it goes, but aim for incredible quality plz!" (the user, 2026-11-08); the houses, the gate, the
trees, the windows, the Moon, the owl and the organ are new in it.

- **The houses** (`kit` `house`, `kit/courtyard.gd`): thirteen fronts, five along each side wall and three across
  the back, each its own wash (rose, ochre, cream, sage, terracotta; lime over plaster with a faint blotch), shutter
  colour, height (7 to 9.6 m to the eave) and depth (0.005 to 0.9 m out from the wall). Each stands on the stepped
  floor (its socle follows the aisle's rake) and rises in two or three storeys of windows to a tiled eave or a gable.
  Between them: long iron balconies with real depth on stone consoles (one with a striped rug over its rail),
  balconettes, a loggia, two belvedere towers, two pergola terraces, two Moorish oriels with their lattices lit, an
  arcade on the left wall and another across the back (the projection booth's ports over it, the projector's lens
  glowing), a front door, niches with an urn and a lion, a wall fountain behind the seats on the left (blue and white
  tiles, a lion's mask, a basin with moving water), geraniums on the sills, bougainvillea climbing to the balconies,
  iron grilles on the ground floors. The four exits are arched ways out in the houses at the corners.
- **The windows** (`PieceRoomWindows`, `shaders/env_courtyard_window.gdshader`): 54 lit rooms behind the glass,
  each one of six kinds (a curtain drawn left or right, both drawn with a lamp, a plant on the sill, inner shutters
  half closed with light through the slats, the organ's pipes), and 10 dark. They are lamps of the `house` group, so
  they dim with the house lamps, and with the film the courtyard goes to bed: `kit.night` to 0.7 puts each window out
  at its own moment, down to `ember` 0.2 (a lamp turned low), 37 of the 54 over 9 s. They bake as
  emitters: their glow lights their reveals, sills and shutters.
- **The palace gate** (`kit` `palace_gate`): two towers reach from the screen to the walls, each with a rusticated
  base, the organ's grille (a tall arch with a gilt lattice over the pipes' warm chamber, a gilt balconette), a lit
  window, a belfry with its bell and a pyramid roof with a gilt finial. Between them a great segmental arch over the
  picture with gilt mouldings, a keystone's cartouche under a shell, rosettes in the soffit, medallions in the
  spandrels, a frieze, and a balustrade with five urns against the sky. Velvet drapes tied back in the jambs with
  gilt cords and three swags with gilt fringe along the arch. Nothing of it is in front of the picture. Two stone
  lions lie on pedestals at the stage's corners (`kit` `pedestal`, `scale` 1.3).
- **Beyond the walls:** six cypresses, three palms and a stone pine (`kit` `cypress`, `palm`, `pine`) over the roofs.
  No `vista`: the trees are the kit's, drawn round the room's own corners.
- **The sky** (`sky`): latitude 37, mid July, 21:30, `dusk` 0.45 (a deep blue vault, the sunset's last glow low in
  the west-south-west), the real stars with a slow `twinkle` 0.35, the Milky Way at 0.5, no constellation lines, a
  crescent `moon` (bearing 218, 47 degrees up, phase 0.28, lit from the sunset's side), clouds lit warm from below by
  the town (`cloud_glow`), their own colour after `film.colour` (strength 0.4) and the ones towards the screen
  catching its light (`cloud_screen` 1.2).
- **The light** (`light`): a cool blue fill from above, a warm one from below (`fill_top` [0.13, 0.16, 0.27],
  `fill_bottom` [0.11, 0.08, 0.06]), `baked_fill` 0.6, `spill` 0.5 (the default is 3, on dark walls: these pale
  washes near the screen took too much of a bright scene). 15 lanterns on iron brackets (`PieceLamps`, the `house` group); with the
  organ chambers' glow that is 17 lamps, of which the first 16 (`bake_lamps` 16) are stand-in lamps and hidden bake
  lights, so each lays a warm pool on its wall. Four hidden floodlights at the stage's lip light the towers and the
  arch in the bake. The hall's own house spots are off (`house_spots` false: there is no ceiling), and so are its
  handrails (`handrails` false: they would run through the house fronts). No live light.
- **Settings:**

  | Setting | Choices | Default | What it moves |
  |---|---|---|---|
  | Clouds (`clouds`) | 0 to 100 % | 40 % | `sky.clouds` by `range` [0, 0.8] |
  | Organ before the film (`organ`) | on, off | on | the organ's `on`; the `prelude` and `postlude` cues' `requires` |

- **Cues:** `ritual` (starting, Pre-show on): the house lamps to half over 1.5 s, the curtains part over 4 s, the
  dusk deepens to 0.85 over 10 s, the courtyard goes to bed (`kit.night` 0.7 over 9 s), the clouds lose the town's
  glow (0.25 over 8 s), the Moon pales to 0.6 over 8 s; then the lamps to 12 % and the steps to half over 5 s.
  `dim` (Pre-show off): the same without the curtains, over 3 to 6 s. `lights_up` (pre-show, ended): all of it back,
  over 4 to 8 s. `prelude` (pre-show, ended; Organ on): 5 s after the room opens, the organ plays for 80 s.
  `postlude` (starting; Organ on): the organ plays its cadence and rests as the film starts.
- **Sound:** `acoustics` `cinema` (rt60 0.7); the wall fountain (`sound_bed` `fountain` at its basin, [-9.05, 2.4,
  4.3], `reach` 8, `gain_db` -4); crickets round the courtyard (`crickets`, three voices on a 9 m ring, `gain_db` -9,
  `film_db` -18); a scops owl in the stone pine over the right-hand roofs (`scops_owl`, a new synthesised call,
  [11.5, 11, -3], `every` 55 s with `jitter` 0.45, `gain_db` -3, `film_db` -40: it all but stops in the film); the
  theatre organ behind the left tower's grille (`music` `organ`, stop `theatre`, [-8.1, 1.2, -13.7], `gain_db` -7,
  major), heard only before the film and between films (`plays_in` intermission; the `prelude` cue plays it).
- **Comfort:** nothing moves fast or crosses the sight line. The windows go out each over a twentieth of `night`'s
  travel (0.45 s at the ritual's 9 s), slower than the photosensitivity ceiling's fade; the twinkle and the water are
  under 1 Hz at any point; the clouds drift at `wind` 0.2. The Motion setting scales the clouds and `kit.water_motion`
  (at 0 the fountain's water stands still).
- **Default seat:** the middle of row 0 (7 rows in front, 3 behind). The seats, the eye height and the screen are as
  before the pass.
- **Measured** (`test_room_atmospheric_1928.gd`, headless, 2026-11-08): 31 draws, 262 756 triangles, no live light,
  no particles, 11.0 MB. Before the pass: 26 draws, 199 724 triangles, 9.4 MB. By part: the seats 177 100 triangles
  (2 draws, the hall's, unchanged), the kit's unbaked parts 71 390 (7 draws: stone, gilt, iron, leaves, wood,
  cloth, velvet), its baked parts 5 426 (4: plaster, stone, roofs, joinery), the windows 329 (1), the lanterns' glass
  180 (1), the water 41 (1), the booth's ports (2), the Moon (1); the sky's dome and stars 6 390 (2). The triangles
  are 13k over the brief's ~250k; the seats are two thirds of them. By piece: the gate 10.4k, a house about 1.7k to
  7k (the fountain's is the most), a lion about 3k, the pine 3.4k, a palm 0.8k, a cypress 0.3k. The bake under
  lavapipe: about 13 s, one 1024² atlas, 6.3 MB.
- **The costs to watch on the Frame** (not measured on the headset): the draws (31, from 26) and the triangles (the
  seats' 177k as before); the bake's time on the Frame (13 s under lavapipe on the desktop). Fill: nothing large is
  transparent; the sky is the same dome and stars as before plus one small quad for the Moon; the windows' shader is
  a few dozen ALU on small faces.
- **Sound measured** (`test_room_atmospheric_1928.gd`, the slider's default): -59.0 dBFS RMS in the pre-show with
  the organ playing and the owl calling (peak -42.1), -75.3 under a film at the reference level. Before the pass:
  -64.5 in the pre-show, -79.8 under a film.
- **The render** (lavapipe, `test_room_atmospheric_1928.gd`; `ATMO_BAKE=1` bakes it first): from the seat, left,
  right, up, back, a side seat and its wall, in the pre-show and in the film; closer: the gate, the left houses, the
  Moon, the rear, the lions, the right houses, a lion, the fountain. From the seat, baked (mean luminance of the
  image, 0 to 1): in the pre-show the houses beside the screen 0.22 and the gate 0.24; in the film, under the test's
  bright picture (0.60), the houses 0.12 and the gate 0.14, of which 0.05 and 0.08 without the picture's spill.
- **To judge on the Frame:** the frame time with 31 draws and 263k triangles; the bake's time; the organ's, the
  owl's, the crickets' and the fountain's levels by ear; the Moon's brightness beside the film; whether the
  courtyard is dim enough in the film (the façades take the film's spill: `spill` 0.5 on washes about four times as
  pale as a dark-walled cinema's walls at 3, so about two thirds of its light).

### Room: Palace of Culture 1974

`app/environments/palace_of_culture_1974.env.json`. *A palace of culture, 1974: board-marked concrete, two great
mosaics that glitter in the screen's light, a field of glowing globes, and snow falling through the open roof.* The
deep pass (2026-11-08) answered "continue working on the environments one-by-one like you did with the bathysphere,
really improving their quality, imagination, delight, detail, lighting and so on. Better to do a smaller number of
incredible superb ones than a large number not so" (the user). Before it the room was the auditorium builder's
cinema in other materials: concrete panels, six flat terrazzo panels a side for the mosaic (no tesserae), ochre
drapes, stadium seats in red, the back three quarters of the roof open. The seats, the eye height and the screen
are where they were; the hall round them is the kit's `culture_hall` piece (`kit/palace_culture.gd`), its mosaics
`kit/mosaics.gd` on the house shader's `MOSAIC` form.

- **The mosaics (the soul):** one on each side wall, 14.4 m long and 7.2 m high (z -13.6 to 0.8, y 1 to 8.2), of
  our own design, no people and no emblem: 320 x 160 tesserae of 4.5 cm each, drawn tessera by tessera
  (`kit/mosaics.gd`) into one map (320 x 320, both murals, 400 KB) whose alpha says what each tessera is: stone, coloured
  glass or gold. The left wall is **the cosmos**: a night laid in rings round a gold sun (the andamento a mosaicist
  lays), its rays in gold and ochre, an atom's three orbits round a red nucleus, a rocket climbing on a trail of
  flame, a crescent moon cut out of the night, a ringed planet, a comet, gold and white stars. The right wall is
  **the earth**: dawn in bands of cream, peach, aqua and blue round a sun rising on the horizon, gulls gliding, a
  sheaf of wheat bound with twine, furrows converging to the horizon in ochre, olive, gold and brown. Along both
  feet a river of waves (scales of turquoise, cobalt and ultramarine with white rims); a black and gold border; a
  bronze frame. The shader (`MOSAIC`): courses with uneven joints and a stagger, each tessera its own shade, tilt
  and edge, dark grout that stays thin at a distance; gold and glass glint as the head moves (the lamp line's and
  the picture's light, gold tinted by its own colour, stone hardly), never a flicker of its own. The lamp line over
  the cornice washes down them (`mosaic_wash`, times the house lamps). In the film they take `film.colour` through
  the screen's spill, softly: `spill` 0.22 against the concrete's 0.45 (the mosaics must never be lit more than the
  picture).
- **The architecture:** board-marked concrete everywhere (`procedural.gd` `board_concrete`: ten boards a repeat, each
  its own tone and depth, butt joints, grain, the fins between boards, tie holes, blowholes) on `smooth_concrete`;
  a moulded cornice at 8.4 m over each mosaic with a lamp line in its underside; a coffered ceiling, 10 x 7 coffers
  on beams 0.7 m deep, each coffer's soffit lit by the globes under it (`PieceCove`: the light worked out per vertex,
  a pool round each globe falling off over half a metre, no light pass); a bold concrete proscenium round the
  screen's drapes: a broad face, two stepped reveals, vertical ribs every 0.42 m, a groove band and a
  bronze edge, the ochre valance inside it.
- **The globes:** a field of 60 opal globes (six rows of ten) on long rods from the coffers' crossings, hung lower in
  the middle (a bell) and never below 6.6 m, all at least 2 m above the picture's top. Each glows warm
  (`room_lamp.gdshader` `rim`: brighter where the view meets the glass square on, so they read round, not flat
  discs), in the `house` group: they dim with the house lamps for the film but never go quite out
  (`follows_house` 0.93).
- **The opening and the winter:** a roof light 4 m deep across the hall's width just behind the default row (z 1.2
  to 5.2), crossed by a grid of concrete beams; a frozen sky (`sky`: latitude 56, mid January, full night, grey
  clouds, a warm glow on their undersides from the hall); birches in hoar frost overhead (`vista` `frost` 1: fine
  white twigs, drooping strands; `room_glow`: the hall's warm light thrown up on the near trees, down with the
  lamps in the film); snow lying on every ledge and beam of the opening (unbaked, draped over the edges so it
  reads from below), snow falling under the opening only (1400 flakes).
- **The rear wall:** oak acoustic slats (7.5 cm pitch, each its own tone) to 5 m, on bronze rails; a concrete band
  with the booth's windows; over it the hall's clock (0.6 m, a bronze ring, `env_clock.gdshader` `style` 1: a dark
  dial, lit bars and minute dots, telling the real time); dark felt between.
- **The seats:** the seats system's new `civic` model, 377 of them (29 a row, 13 rows): woven red upholstery on a
  moulded oak shell, oak arms and standards. 338 triangles a seat against the stadium seat's 646.
- **The light:** warm in the pre-show (the globes, the lamp lines, the wash down the mosaics, the coffers' pools),
  cold from the opening (a pale blue spot from the sky for the bake), dim in the film. Baked: 8 lamps (stand-ins
  until the bake), 5 glows along the cornices, 11 hidden spots (six washing down the mosaics, the sky's spot, two
  footlights on the drapes, two uplights on the proscenium from the pit). The curtains of the pre-show are ochre,
  as the drapes (`room` `curtain_colour`).
- **Systems:** `light` (spill 0.45, `baked_fill` 0.15), `auditorium` (unchanged layout; `seat_model` `civic`,
  `side_walls` false: the kit draws the side and rear walls; `ceiling_cover` 0: the kit draws the ceiling; `house_spots`
  off), `kit` (`builder` the hall, pieces `culture_hall` and `globe_field`, `bake_lamps` 8, `mosaic` on
  `white_marble`), `screen_frame`, `showing`, `sky`, `vista`, `weather`, `acoustics`, three `sound_bed`s.
- **Setting:** Snow (no snow, light, heavy; light by default): `weather.mode` (clear, light, heavy), `sky.clouds`
  (0.2, 0.55, 0.85), `vista.snow` (0.8, 1, 1) and the wind's level (0.5, 0.8, 1), each by `map`.
- **Cues:** `ritual`: the bells, the lamps to half over 2 s, the curtains part over 5 s, then the lamps to 10 %, the
  steps to half and the trees' glow to 0.04 over 6 s. `dim` (the same without the ritual), `lights_up` (all back
  over 4 s). `night_train`: in the pre-show, when paused and at the end, every four minutes a one-in-two chance (at
  most once in eight minutes) of a train far off.
- **The snow and the picture:** the snow falls only under the opening, behind the default seat, so nothing falls
  between the viewer and the picture from there; from the back rows it falls round them.
- **The vista's ground:** the side groves' ground is at -3.1, under the pit's floor: at 0 the vista's snow (8 m
  out from the middle) showed over the side aisles as a pale slab (before the pass too).
- **Default seat:** the middle of row 0.
- **Comfort:** nothing moves but the snow, the clouds and the clock's hands; nothing between a seat and the picture (tested from
  every seat); the globes hang high and clear of the view.
- **Measured** (`tests/test_room_palace_of_culture_1974.gd`, headless, 2026-11-08): 29 draws, 178 958 triangles,
  no live light, 1400 particles, 14.6 MB. Before the pass: 23 draws, 256 688 triangles, 1400 particles, 12.4 MB. By
  part: the seats 127.4k triangles in 2 draws (243.5k before), the vista 14.1k (the frosted birches), the globes
  11.5k, the coves (coffers, cornices) 8.9k, the soft meshes (snow, rods) 5.3k, the stars 4.0k, the hall's static
  meshes 2.9k in 5 draws, the sky 2.4k, the floor 1.6k, the mosaics 4 triangles (all their detail is in the shader).
  The bake: the lightmap 1024 x 1024, one layer (6.3 MB), 11.4 to 11.8 s under lavapipe; 24 hidden lights for it.
  The textures made at load: the board-marked concrete's three maps (256) and the mosaics' map (320 x 320).
- **The costs to watch on the Frame:** fill is one opaque layer (the snow's flakes are the only blended part); the
  mosaic shader costs one more texture fetch and a few hashes a pixel over the house shader, on two walls that fill
  much of the view; the frosted birches add 14k triangles to the vista's one draw; the 60 globes 11.5k in one draw.
  The bake's time on the headset (24 lights) is the thing to judge.
- **The render** (lavapipe, `test_room_palace_of_culture_1974.gd` with `PALACE_BAKE`): from the seat, left, right,
  up, back, back and up, a side seat and its wall, in the pre-show and with a film; close: the left mosaic, the
  proscenium, the ceiling, the rear wall, the opening, the right mosaic, the roof from above, the side aisle.
- **Sound:** an echoing hall (`acoustics` `concrete_hall`: rt60 2.4, a 60 ms predelay); the house bells
  (`three_bells` by the stage, played by the ritual only); the wind over the opening (`wind` 10.5 m up, its level on
  the Snow setting, 12 dB down in the film); a train far off now and then (`train`, about 280 m away, by the cue only).
  Measured (the slider's default): -52.1 dBFS RMS in the pre-show (peak -38.1), -73.5 under a film at the reference
  level. Before the pass the bells' loudest second was -52.2 and nothing else sounded.
- **To judge on the Frame:** the frame time with the mosaics filling the view and the bake's time; whether the
  glint is subtle (gold should catch as the head moves, never sparkle); the mosaics' level in a bright film; the
  globes' level in the film; the ochre curtains of the pre-show; the wind's and the train's levels by ear;
  snowflakes near the eyes in the back rows.

### Room: Flagship

`app/environments/flagship.env.json`. *A big modern cinema: a steep rake, folded acoustic walls washed in amber,
recliners, a starlit ceiling of baffles and a huge curved screen in velvet.* The user's reference room for watching:
the "serious" room. The deep pass (2026-11-08) answered "continue working on the environments one-by-one like you did
with the bathysphere, really improving their quality, imagination, delight, detail, lighting and so on. Better to do
a smaller number of incredible superb ones than a large number not so" (the user). Before it the room was the
auditorium builder's hall in black: black felt walls that vanished, a black foam ceiling with a few white cans, red
stadium seats, the screen in a black void. Its brief: the finest modern hall in a capital city, understated luxury,
delight from restraint and craft. The seats, the eye height, the rake, the screen (its size, curve and place) and the
room's dark quiet are where they were; the hall round them is the kit's `flagship_hall` and `flagship_rows`
(`kit/flagship.gd`), the seats the seats system's new `recliner`.

- **The walls:** folded acoustic panels in charcoal felt, a sawtooth in plan (1.24 m bays: a broad face turned to the
  seats, a short return turned to the screen, the ridge 22 cm out), a champagne-bronze fin on every ridge from the slot
  to the cove ledge, over a walnut dado that follows the rake 1.05 m over the steps' noses. Between dado and panels a
  warm light slot runs the length of each wall, stepping over the front exits' signs; its light on the folds is worked
  out per vertex (brightest low and in the folds by the wall, thinner at the ridges, half on the returns, dark by the
  top), shown by the house shader's `vertex_light` in the kit's `cove_colour` at the house lamps' level. So the walls
  read as folds of light and shadow in the pre-show and vanish in the film, where only the returns catch the
  picture's light behind the viewer. A brushed-steel handrail on brackets runs up each stepped aisle with a warm line
  under it on the steps.
- **The ceiling:** 34 long felt baffles, 0.55 m deep, run from the proscenium to the rear ledge (the eye follows them
  to the screen), a 1.1 m band clear along each wall. Over the walls a cove ledge (a fascia and soffit 0.4 m out)
  hides a cool line washing the ceiling's edges and the wall above it (per vertex, the `plaster` material's cool
  `vertex_light`); a little of that light is on the baffles so they read as fins. Between them, 1100 pinholes of
  starlight (`Starlight`: a soft point each, 1.2 to 3.2 cm, mostly cool white, one in seven warm; static, never
  twinkling).
- **The screen:** the picture's curve carried into the room: black velvet masking (0.65 m round the picture, on the
  picture's own arc 8 cm behind it, `Flagship.arc()`: the document's curve over the seat's distance, as
  `curved_screen.gd` makes it), a slim frame round it (7 cm, standing 12 cm out, dark bronze: a bright one read as a
  television's bezel round the film), and beyond the frame to the walls and the ceiling a proscenium of bold walnut
  slats (28 cm pitch: thin ones close together shimmered in a moire from the seats) on dark walnut, washed from the
  stage's lip up the wings and from a line hidden in the frame's head. The stage's front is a perforated grille (the
  speakers behind the screen) over a dark toe, the builder's blue apron line above it. The stage is 2.2 m deep now
  (was 1.4): the curved picture's edges come 0.8 m forward, and the stage's front must stay in front of them.
- **The rows:** the `recliner` (428 triangles: a deep cushion on a closed base, a back reclined 15 degrees in two pads,
  a shell to the floor in darker oxblood leather; the headrest 0.22 m behind the seated eyes; the back row clears
  the rear wall). Its arms are the room's (`flagship_rows`): 364 fixed leather armrests between the seats and at the
  rows' ends, each with a brushed-steel cupholder ring (dark inside) at its front and, behind it, the number of the
  seat on its right engraved on a steel plate (`SeatNumbers`: 1 to 25 from the left, in a 5 x 7 face of our own on
  the house shader, lit as the room is), so the viewer's own seat folds away and both its arms stay. Row letters A
  (the front) to N glow on the end arms towards the aisles (`RowLetters`, the steps' group: at a whisper in the film).
  Brushed-steel nosings on every aisle step over the builder's blue lines. At the front row a frameless glass
  balustrade (`Balustrade`, nearly clear) with a steel shoe and cap rail and a warm line under the cap.
- **Other fittings:** eight surround speakers on the side walls and two on the rear wall (cabinets with perforated
  fronts, tipped down to the seats, on brackets); the rear wall in walnut slats on felt with a walnut band round the
  projection port and the booth's windows (the port glowing faintly), the rear exits clear; the doors in walnut and
  brushed steel.
- **The light:** the pre-show is warm low and cool high: amber up the folds and the proscenium's wings, the warm lines
  of the slots, the rails and the balustrade, the blue step lines, the cool coves along the ceiling, the stars. In the
  film everything of the house goes out with the house lamps (the wash's `vertex_light`, the lines, the stars by
  default) but the steps and the row letters at a whisper (35 %) and the exit signs; the picture's light reaches the
  seats and walls through the spill (`light` `spill` 2, the walnut 0.5, the grilles 0.4, the frame 0.5, the ceiling 0.3,
  the masking 0.2). The fill is low and neutral (the wash, not the fill, shows the walls). No projector's beam: the
  clean air of a modern hall (it also drew a large blended pyramid over the seats, moving with every cut). Baked: 8
  warm lamps by the walls (stand-ins until the bake: they light the seats too), 13 glows (the slots' light every 5.5 m
  along each wall, the coves' cool light), 2 spots up the proscenium's wings from the stage's lip, and the builder's
  step and exit lights.
- **Setting:** Starlight ceiling (off, before the film, always; "before the film" by default): the kit's `starlight`
  and `starlight_film` by `map` (0/0, 1/0, 1/0.18): always keeps 18 % of the stars in the film. The stars ease to their
  level over about a second.
- **Cues:** `ritual`: the lamps to 40 % over 2 s, the curtains part over 6 s, then the lamps out and the steps to
  35 % over 5 s (the wash, the lines and the stars go with the lamps). `dim` and `lights_up` as above.
- **Seat choice:** the default seat is the middle (row 0, with 7 rows in front and 6 behind). The front-middle
  and the back are the other good seats; the viewer picks them by pointing.
- **The curve (since 2026-11-07):** `env_room.gd get_home_curve()` gives the document's `screen.curve`, and the
  screen starts with it until the viewer sets a curve of their own (`curved_screen.gd`; flattening it keeps 0, so the
  room stays flat). A setting still cannot choose the default seat: the room starts at its origin seat.
- **Comfort:** nothing moves; nothing between a seat and the picture (tested from every seat, and no vertex of the
  hall in front of the picture's arc); the stars never change faster than an ease of a second.
- **Measured** (`tests/test_room_flagship.gd`, headless, 2026-11-08): 28 draws, 220 134 triangles, no live light, no
  particles, 11.5 MB. Before the pass: 17 draws, 228 806 triangles, 6.0 MB. By part: the recliners 149.8k triangles in
  2 draws (the stadium seats were 226.1k), the soft meshes 57.3k in 3 draws (the 364 arms with their rings 48k, the
  walnut slats 9k), the hall's baked meshes 5.4k in 8 draws, the stars 4.4k, the floor 1.7k, the seat numbers 0.7k. The
  bake: the lightmap 1024 x 1024, one layer (6.3 MB), 13.8 s under lavapipe (12 s before the pass, 512 x 512 in 5
  layers); 23 hidden lights of the kit's and 10 of the builder's. The textures: the new library maps (oxblood leather,
  walnut, brass, perforated metal, brushed steel) and the glyph atlas (384 x 150).
- **The costs to watch on the Frame:** fill is one opaque layer but for the stars (tiny), the balustrade's glass (a
  thin strip) and the picture; no beam now (it was a large additive pyramid). The arms (48k triangles) are the price of
  armrests that stay when the viewer's seat folds away. The bake's time with 33 lights.
- **The render** (lavapipe, `test_room_flagship.gd` with `FLAGSHIP_BAKE`; the picture curved as the app curves it):
  from the seat, left, right, up, back, back and up, down the rows, a side seat and its wall, the front row, in the
  pre-show and with a film; close: the proscenium's left, the stage, the ceiling, the rear wall, the side wall, the
  aisle, the armrest, a row's end.
- **Sound:** no beds: a modern hall is quiet but for the film. Its acoustics are drier than the `cinema` preset (rt60
  0.5, damping 0.8, wet 0.12: black felt and foam), for any room sound to come; the film keeps its own mix. Measured
  silent (-120 dBFS) in the pre-show and the film.
- **To judge on the Frame:** the frame time (the arms' triangles, the bake's 33 lights); the wash's level up the folds
  and the wings (amber, not orange: it should feel warm and calm, never bright); whether the stars read as pinholes
  (not sparkle) and their level; the slats of the proscenium from the seats (no shimmer); the seat numbers' size by the
  hand; the row letters' level in the film; the spill on the walls in a bright film.

### Room: Shopfront 1906

`app/environments/shopfront_1906.env.json`. A narrow picture house in a shop: pressed tin, folding chairs and gas
lamps, the film on a framed sheet. Its test: `tests/test_room_picture_houses.gd`.

- **Systems:** `light`; `shopfront` (id `hall`): a 5.6 m hall 4.2 m high, the sheet 4.4 x 2.5 m at 7.4 m, 5 rows in
  front of the viewer's and 3 behind, the tin an aged cream, gas lamps with `flicker` 0.6; `seats` (folding chairs
  in the builder's slots); `kit` (a tin booth in the back corner's `booth` slot); `screen_frame` (no black masking:
  the sheet's frame; the beam from the booth's window); `atmosphere` (`beam_haze` 0.4, `beam_dust` 0.7).
- **Sound:** `acoustics` `shopfront` (pressed tin, rt60 0.9); `sound_bed` `projector` at the booth's window behind
  (`reach` 5); `sound_bed` `gas` (`gas_hiss`, everywhere); `music` `piano` (a player piano by the screen's left,
  `at` [-2.4, 0.8, -6.6], `reach` 7): it starts its piece in `starting` and plays on through the film, `drive` on
  `film.transient` (`range` [0.3, 1], smooth 0.5 s: an agitato after a jump, its oom-pah again when the film calms),
  `on` on the setting. All at their designed levels. No piano is drawn (the kit has none).
- **Setting:** `piano` (Player piano, on): `piano.on`.
- **Cues:** `ritual` (starting, Pre-show on): the gas down to half over 2 s, then to 18 % over 5 s, the street's glow
  through the shop window down with it. `dim` (Pre-show off): the gas to 18 % over 3 s. `lights_up` (pre-show, end):
  the gas up over 4 s, the street's glow back.
- **Measured** (headless): 17 draws, 10 168 triangles, no lights, no particles, 8.4 MB; 63 seats. Sound at the
  slider's default (dBFS RMS): -52.3 in the pre-show, -54.7 as the film starts, -57.1 in the film, -64.1 under a film
  at the reference level.

### Room: Streamline 1937

`app/environments/streamline_1937.env.json`. A 1937 streamline (moderne) picture house: horizontal speed and curves,
a ceiling of coves glowing in changing colours, a stepped proscenium round a rising sun, a gold festoon, and an
illuminated organ console that rises from the pit. Its tests: `tests/test_room_streamline_1937.gd` (the room's own)
and `tests/test_room_picture_houses.gd` (with the Shopfront and the Pink Palace). The quality pass (2026-11-08)
answered "continue working on the environments one-by-one like you did with the bathysphere, really improving their
quality, imagination, delight, detail, lighting and so on" (the user, 2026-11-08); everything but the hall's floor,
seats, doors and screen is new in it (`kit/streamline.gd`).

- **The ceiling** (`moderne_hall`): five bands across the hall, from 8.8 m over the proscenium down to 6.4 m at the
  back, each stepping 0.6 m over the next (steps at z -8.6, -4.2, 0.2 and 4.0). In each step's slot a lamp lies on
  the lower band's back and washes the higher band's plaster, so from the seats every band glows brightest by its
  slot and fades over a couple of metres towards the screen; a faint broad glow goes on further. Along both walls each
  band rounds down in a quarter round of 0.9 m into a ledge whose lamp washes the round (the coves along the walls).
  Over the proscenium a drop beam with a chrome edge hides a lamp that washes the proscenium's head. A gilt
  ventilator (twenty fins round a boss over a dark throat) in the middle of each of the first four bands.
- **The walls:** speed bands of cream faience, jade and cream between four chrome beads (4.1 to 4.85 m) run from
  over the organ grilles on the proscenium's face along both walls, round the rounded rear corners, along the rear
  wall and across a bowed circle front (a jade faience parapet with a chrome handrail and three downlights in its
  soffit over the rear walkway; the projection box's ports behind it). A walnut dado with a chrome bead and joints
  follows the rake; reeded pilasters (five reeds, a stepped faience capital, a chrome base) stand under the ceiling's
  steps; eight etched glass shell lights (a fan of frosted glass, eleven ribs, on a stepped chrome bracket) between
  them, each a stand-in lamp and a bake light that lays its pool on the wall. The aisles' carpet: rising suns in rows
  (`deco_carpet`, jade, gold and cream).
- **The proscenium** (`ziggurat`): three frames stepping out towards the seats (0.5, 0.8 and 1.1 m in front of the
  screen, each opening 0.4 m wider and higher than the last, shoulders rounded from 1.0 to 1.8 m), each lit by a lamp
  hidden behind the next one's edge, so every face glows at its outer edge and fades towards the picture; gilt
  reveals with a gilt bead on each edge. The outermost face reaches the walls and the ceiling. Over the opening a
  rising sun: a glowing half disc, two gilt half rings, thirteen gilt rays long and short, three chrome speed lines
  either side. Two organ grilles (a chamber lit from below seen through gilt bars, a sunburst in the round head, a
  stepped gilt surround, a dark jade plinth); over the left one a clock whose hands tell the real time (chevrons at
  the quarters, faint rays, a chrome bezel, gilt rays round it: `shaders/env_clock.gdshader`), over the right a
  roundel of glowing glass with three chrome speed lines through it. Nothing of it is in front of the picture.
- **The festoon** (`motion` `festoon`): gold velvet in six swags with folds (`pleats` 2.4), from 2.3 m over the
  screen's top to the stage (`festoon_top`, `festoon_size` [12.8, 8.05]); fully up its lowest swag is at 4.6 m, behind
  the first frame's head (4.45 m) and clear of the picture. Lit from the footlights below and two battens behind the
  head, in the coves' colour. It rises at the motion limits (0.5 m/s): about 15 s, so the first seconds of the film
  land on its rising hem, as they did.
- **The organ console** (kit `console`, `group` "Console"; `motion` `organ`): on a round lift platform (black lacquer,
  a chrome rim, a skirt that fills the well when it is up) an illuminated console: sixteen glass panels between gilt
  fins in the coves' colour, an ivory horseshoe of stop tabs in three tiers (white, red, amber, black), three manuals,
  a lit music desk under a chrome hood (accent group), a pedalboard of thirty-two pedals under a jade bench. It rests 1.3 m under the pit's floor and rises
  1.85 m (0.25 m/s): up, its top (1.22 m over the platform) stays under every seat's sight line to the picture. A
  chrome ring on the pit's floor marks the well.
- **The light:** baked, from the shell lights' pools (8 lamps), the circle's downlights (3 spots), the wall coves (10
  hidden lamps under the rounds, one a band a side, that lay the coves' glow down the upper walls) and the hall's
  house spots; the coves, the frames, the grilles' chambers, the sun and the console's
  glass are `PieceCove` (their light per vertex, live in colour: "The moderne hall's coves" in "The kit"). The fill
  is low (`fill_top` [0.62, 0.5, 0.4], `baked_fill` 0.2) and the spill too (0.35; the coves take 0.6 of it): a pale
  hall would otherwise glow in the picture's colours. No live light.
- **Setting:** Cove colours (`cove`: Changing, Gold, Rose, Jade, Blue; Changing by default). It moves only live
  parameters (the kits' `cove_colour` by `map`), so the room is not built again and the console stays where it is.
  With Changing the coves go gold, rose, jade, blue in turn (`cove_cycle`, every 20 s in the pre-show, paused, at the
  end and in the intermission; each change over 4 s). In the film the coves take the film's colour (`cove_film`,
  `cove_film_colour` on `film.colour`, strength 0.85) at half their level (`cove` on `playback.playing`), times the
  house lamps' 15 %: a glow.
- **Cues:** `prelude` (pre-show, end, intermission; Pre-show on): 3 s after the room opens the console rises over
  10 s, lit, and the organ plays (`pipes.play`, 80 s), then sinks. `ritual` (starting; Pre-show on): the lamps to half
  over 2 s, the organ's closing cadence (`pipes.flourish`), the festoon rises, the console sinks 3 s later, the lamps
  to 15 % over 5 s. `dim` (starting; Pre-show off): the lamps to 15 %, the console down. `lights_up` (pre-show, end):
  the lamps up over 4 s, the festoon down. At the end the console rises again and the organ plays the house out.
  `cove_cycle` and `cove_settles` as above.
- **Sound:** `acoustics` `cinema`; `music` (id `pipes`) `organ` with the `theatre` stop at the console (`at` [0, -1.5,
  -11.35], `reach` 12), `plays_in` the intermission and when the prelude plays it, `on` on the common Pre-show
  setting. No beds: the hall is quiet but for the organ.
- **Comfort:** the colours change over 4 s, the clock's hands as a clock's, the console and the festoon at the motion
  limits (the Motion setting snaps them); nothing crosses the sight line (the festoon is `in_front` until it rises).
  The chrome shows the picture at a third in the film, so it does not glint with every cut at the edge of vision.
- **Default seat:** the middle of row 0 (7 rows in front, 3 behind, 25 seats a row). The seats, the eye height and
  the screen are as before the pass; the stage's top is 0.5 m higher (-1.6 m), so the festoon meets it.
- **Measured** (`test_room_streamline_1937.gd`, headless, 2026-11-08): 27 draws, 201 342 triangles (177 100 of them
  the seats), no lights, no particles, 8.2 MB of textures; 275 seats. Before the pass: 27 draws, 182 676 triangles,
  no lights, no particles, 8.0 MB.
- **The costs to watch on the Frame** (not measured on the headset): the fill is one opaque layer everywhere (the
  coves are `PieceCove`, opaque, over the ceiling; the two fog layers of the old room are gone); the only transparent
  surface is the air's beam haze in the film. Every frame the kit sets the coves' colour and level (two uniforms), the
  clock's hands once a second and the footlights' stand-in lamps ten times a second; the reflections' level only as
  the lamps change. The bake: 6.1 s under lavapipe, a 1024 x 512 atlas (3.1 MB).
- **Sound measured:** in the pre-show -54.4 dBFS RMS (peak -38.7: the organ playing as the console rises), under a
  film at the reference level -68.4. Before the pass: silent in the pre-show, -57.3 as the console rose, -59.4 in the
  film, -68.5 under a film.
- **The render** (lavapipe, `test_room_streamline_1937.gd`; `STREAM_BAKE=1` bakes it first, `STREAM_ONLY` takes one
  phase): baked, from the seat in the film the walls 0.143, the proscenium 0.205, the picture 0.603 (the hall a
  quarter of the picture or less); in the pre-show, not baked (the stand-in lamps only), the walls 0.371 and the
  proscenium 0.485.
- **To judge on the Frame:** the frame time and the bake's time; the organ's level and its tremulant by ear, against
  the film's; whether the festoon's 15 s rise over the film's first seconds pleases or should start in the ritual's
  dark sooner; the film's brightness in the hall (the coves at half of 15 % in the film's colour); the eight stand-in
  lamps (the shell lights at the back have none, so their glass lights only in the bake).

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
  `ritual` (starting): the house bells (`bells.play`), the lamps to half, the curtains part over 5 s, then after 6.5 s
  (after any `sunburst` still running) the lamps to 15 % over 5 s. `dim` (Pre-show off): the same wait, then 15 %
  over 3 s. `lights_up`.
- **Sound:** `acoustics` `cinema` (rt60 0.7); `sound_bed` `bells` (`three_bells` by the stage, `at` [0, 3, -12],
  `reach` 12, `film_db` -4), a one-shot the ritual plays in place of the cue's chime (it was a `sound` step at -6).
- **Settings:** none of its own (the common ones).
- **Measured** (headless): 22 draws, 234 504 triangles, no lights, no particles, 9.0 MB; 356 seats. Sound at the
  slider's default (dBFS RMS): -57.6 as the film starts (the bells), silent in the pre-show and the film.

### Room: Nave

`app/environments/nave.env.json`. *A Gothic nave at night, the screen in the chancel: piers rising into rib vaults,
candles on iron stands and coronae, coloured glass and a rose window in the moonlight.* The deep pass (2026-11-08)
answered "continue working on the environments one-by-one like you did with the bathysphere, really improving their
quality, imagination, delight, detail, lighting and so on. Better to do a smaller number of incredible superb ones
than a large number not so" (the user). Before it the room was the plain nave: round columns, a barrel vault, flat
quads for windows, the seats system's pews, the film's spill (4.5) lighting every wall. The seats, the eye height and
the screen are where they were; the church is drawn by the nave builder's `gothic` style (`kit/nave_gothic.gd`).

- **The architecture** (from the seat, 16.6 m to the vault's crown over a nave 7.6 m between its piers): four bays
  of 3.5 m. Clustered piers of pale limestone, each a round core with four dark polished shafts (a Purbeck-like
  marble, ringed halfway, on their own bases), an octagonal plinth, moulded bases, a capital in stiff-leaf foliage
  (eight three-lobed clumps curling out under a round abacus). Pointed arcade arches of two chamfered orders under a
  hood mould. Over them a string course, a triforium of four small pointed openings a bay into the dark passage
  behind, on dark colonnettes, a second string course, and a clerestory of two-light windows (a mullion, two pointed
  lights, a circle in the head: bar tracery at the glass, splayed reveals, sloping sills). Vaulting shafts rise from
  each pier's capital, ringed at the string courses, to small foliage capitals where the vault springs.
- **The vaults:** quadripartite rib vaults over the nave, the chancel and both aisles: webs of lime-washed stone
  (darker towards the crown), moulded diagonal and transverse ribs, wall ribs over the clerestory's lunettes, a
  foliage boss at each crossing. The crown is lost in shadow above the candles.
- **The aisles:** two-light windows of coloured glass in every bay (three designs in turn: flowers in roundels, a
  diaper of quatrefoils on ruby, a vine winding on blue), wall shafts, a stone bench along the wall's foot; a lancet
  of warm glass in each aisle's east wall beside the chancel.
- **The chancel:** a chancel arch of two orders on continuous mouldings with dark shafts in the angles and a hood,
  cut through a wall that rises to the vault; three worn steps with rounded nosings; a wider chancel (8.8 m) with a
  two-light window either side and its own vault. Over the screen, in the east wall, the rose window (4.2 m): stone
  tracery at the glass (a hub, twelve spokes, the lights' pointed heads, a ring, twelve circles in the outer band) in a
  moulded ring, over a picture of our own glass (a gold flower at the hub, twelve lights of blue with a jewel each and
  ruby borders, roundels of green and gold), brighter to the upper right where the Moon is.
- **The reredos:** the screen framed as an altarpiece in dark oak picked out in gilt, no figures: a buttress either
  side in three stages with sunk panels, gablets, pinnacles with crockets and finials; over the picture a frieze of
  twenty-two small pointed arches under a moulded cornice and a cresting of gilt leaves; under it a panelled dado of
  blind tracery. The picture and its masking stay clear by 0.17 m.
- **The floor:** flagstones laid in courses, each its own size, shade and tilt (a few millimetres), in mortar, the
  aisles' worn paler; larger flags in the chancel. Six ledger stones of dark polished marble let into it (the aisles,
  and two across the nave before the chancel step), each with a border line, a roundel and rows of worn letters no one
  can read now (our own: random letters, nearly half their strokes worn away).
- **The pews:** the church draws them (so the bake lights them): a seat board, an apron, a panelled back leaning
  back under a moulded top rail, a book ledge for the row behind with a few hymn books lying on it (dark cloth), carved
  ends with poppy-head finials (three lobes, at most 1.21 m: every seat's sight line is checked) and a sunk panel; a
  hassock worked in wool at most places, each its own muted colour.
- **Fittings:** a hymn board on the south pier nearest the chancel, turned to the pews, with four numbers painted on
  black slips (117, 364, 52, 408: our own); the west doors of oak boards with iron strap hinges and a ring in a
  pointed doorway under a three-light west window; the stone bench along the aisles.
- **The light:** candlelight against moonlight in deep shadow, baked. Iron pricket stands in the chancel either side
  of the screen (two a side, or four), each a tripod, a turned stem, a drip pan and a thick candle (ivory wax lit
  through near the flame, a drip, the pool glowing: emission in vertex colours) with its flame (the Ice cinema's flame
  picture on crossed quads); three iron coronae over the nave (a hoop with a cresting of leaves, twelve candles each,
  hung on chains from the bosses), the front one high over the screen's view; a votive stand of twenty small lights in
  cups of ruby, amber and blue glass in the north aisle's east end. Each stand, corona and the votive stand is a
  hidden light for the bake only (and a stand-in lamp until the bake). The Moon: high in the south, its light through
  each south window as a narrow spot for the bake, a soft cool patch on the floor, the pews and the piers opposite;
  the south aisle's glass carried along the moonlight onto the aisle's floor as a faint wash of its own colours
  (`MoonPool`, additive, small). The north windows' glass shows dimmer than the moonlit south. The film's spill is
  soft (0.6): the stone near the screen takes the film's colour, the far church stays dim and only tinted.
- **Systems:** `light` (spill 0.6, a dim warm fill, `baked_fill` 0.5), `nave` (`style` `gothic`, `vault` `rib`,
  the chancel at z -6.5 and 4 m deep, 4 pews in front and 5 behind, 9 places each, bay 3.5, piers 5 m to their
  capitals, the vault springing at 12 m, rose radius 2.1, three coronae), `screen_frame` (masking, no beam),
  `acoustics` `stone_nave`, `sound_bed` (wind, candle, owl, bell). No `seats` system.
- **Setting:** Candles (`candles`: none, a few, many): none, the church by moonlight and the film alone (the
  coronae hang unlit, no flames, no candle light in the bake); a few (the default), two stands a side, the coronae
  and the votive lights; many, four stands a side. The nave builds again; the headset bakes again. The flames flicker
  under 3 Hz, a tenth of their light at most (the builders' flicker; common Flickering lights holds them).
- **Cues:** `candles_down` (with the film: the chancel's candles to 20 % over 7 s, the coronae to 30 % and the
  votives to 35 % over 9 s, the rose to 0.12 over 6 s, the windows to 0.2 over 8 s; the house lights' level takes the
  bake down with them), `candles_up` (the pre-show and the end: all back over 5 to 6 s), `bell_preshow` (every five
  minutes before the film, the bell in the tower), `bell_after` (6 s after the end, the bell).
- **Comfort:** the flames waver gently under 3 Hz; nothing moves in the film; nothing stands between a seat and the
  picture (tested from every seat, with many candles too); no candle within the picture's frame from the seat (the
  stands beside it, the coronae high over the nave); the moonlight's pools never move.
- **Measured** (`tests/test_room_nave.gd`, headless, 2026-11-08): 19 draws, 112 510 triangles, no live light, no
  particles, 7.5 MB. Before the pass: 14 draws, 8 290 triangles, 7.0 MB. By part: the carving (piers, capitals,
  mouldings, ribs, tracery, bosses) 64.8k triangles in 1 draw, the walls 10.2k, the corona candles 7.9k, the vaults'
  webs 7.3k, the iron 6.9k, the dark shafts 3.9k, the gilt 3.5k, the oak 3.4k, the cloth 1.3k, the floor 0.8k, the
  chancel candles 0.9k, the votives 0.6k, the glass 0.4k, the flames, the rose, the pool and the masking a few hundred.
  The bake: nine static meshes, 0.70 M texels in their atlases, the largest 588 x 440; the lightmap 1024 x 1024, one
  layer (6.3 MB); about 11 s under lavapipe (a CPU; the headset's GPU should bake faster, but that is
  to be timed there). The textures made at load: the stone's three sets of maps (256 and two 128), the
  windows' atlas (one 96 x 256 cell for each kind of window) and the rose (320 x 320).
- **The costs to watch on the Frame:** fill is small: every surface is opaque on the house shader (the stone's maps,
  no loops), the only blended layers are the flames (small quads), the masking and the moonlight's pools on the
  aisle's floor (a few square metres, seen at a slant). Geometry is moderate (112k triangles, mostly the carving in
  one draw). The bake's time on the headset is the thing to judge (0.7 M texels, 13 lights for it with a few candles;
  15 with many); the load's texture making (a few hundred thousand pixels in GDScript) is the second.
- **The render** (lavapipe, `test_room_nave.gd` with `NAVE_BAKE`): from the seat, left, right, up, back and a side
  seat, in the pre-show and with a film; close in the pre-show: the chancel and the reredos, the rose, a corona, the
  hymn board, a pew's end, a ledger stone, the moonlight's pool, the votive stand. (The render takes the stand-in
  picture out of the bake: on the headset the screen is not under the room.)
- **Sound:** a long stone reverb on the room's own sounds (`acoustics` `stone_nave`, rt60 3); a faint wind high in
  the vault (`wind`, two voices 13 m up, `gain_db` -4, 12 dB lower in the film); now and then a candle's gutter by the
  chancel's stands (`candle`, `every` 120, its `level` on the Candles setting); a tawny owl in the churchyard's trees
  (`tawny_owl`, new, `every` 150, 29 m off to the north, 14 dB lower in the film: a whisper); the bell in the tower
  over the west end (`church_bell` at `pitch` 0.82, deeper than the Athens rooftop's), only by the cues before the
  film and after it. No organ. The film's own `acoustics` section stays modest (rt60 1.6, wet 0.4) so speech in the
  film stays clear. Measured (`test_room_nave.gd`, the slider's default): -56.0 dBFS RMS in the pre-show, -76.5 under
  a film at the reference level (before the pass -55.3 and -70.5).
- **To judge on the Frame:** the bake's time and the frame time; the candles' level in the film (20 %, the coronae
  30 %); whether the moonlight reads (cool patches on the north piers and the south aisle's floor, the pools' colour);
  the hymn board's place (it hangs to the right of the picture's view); the owl's and the bell's levels by ear.

### Room: Reclaimed

`app/environments/reclaimed.env.json`. *An old picture house taken back by nature: half its roof gone to the stars,
ivy on the walls, ferns in the corners, rain into a puddle that gives back the film, birds on the broken roof,
fireflies and now and then a deer.* The deep pass (2026-11-08) answered "continue working on the environments
one-by-one like you did with the bathysphere, really improving their quality, imagination, delight, detail, lighting
and so on. Better to do a smaller number of incredible superb ones than a large number not so" (the user). Before it
the room was the auditorium's own hall with half its ceiling taken away: plain painted brick, dark drapes, the
picture on the black front wall, clumps of the kit's ivy and ferns, and the film's spill lighting it all. The seats,
the eye height and the screen are where they were. The auditorium now draws only the tiers and the seats (`shell`
`kit`); the ruin round them is `kit/reclaimed.gd`, in four pieces (`ruin_shell`, `ruin_roof`, `ruin_stalls`,
`ruin_growth`). A second pass the same day answered the coordinator's look at the renders: the plaster's holes
read as pale paper on a dark wall, the upper walls as flat polygons; the floor stayed bright in the film; the film's
warm and cool halves lit the walls; the rear wall was plain.

- **The walls:** brick (laid in courses, each brick its own shade) under cream plaster fallen away in ragged holes.
  The plaster is the lighter surface and the brick in a hole the darker (a hole reads as a hole, not as paper stuck
  on): the brick darkens towards the plaster's edge (its lip shades it, dirt collects), and the edge itself is a lip
  3.5 cm thick in paler broken plaster (`PLASTER_BREAK`), its face fading into the paint. Damp runs down from the open
  roof with tide marks and green stains; an oxblood dado, pilasters (broken off where the roof went), a cornice; the
  walls' broken tops ragged against the sky, with their thickness. A doorway in the left wall by the stage (a leaf
  hanging open, the night outside). The rear wall decays as the side walls do (plaster fallen in sheets from the top,
  rising damp and a tide mark at the foot, blooms, green runs, a dado rail broken where the plaster fell); the rear
  door to the foyer with a stopped clock over it (a brass bezel, its glass gone, bars for the hours, twenty to four);
  three projection ports, each in a moulded plaster surround with a sill, soot over it where the lamp's heat came out,
  and its steel fire shutter on rusted runners (the left one down halfway, the right one fallen askew, the middle one
  up: its lens still lit).
- **The proscenium:** a plastered arch with faded gilt mouldings, a cartouche and swags over the opening (no
  figures), two lattice grilles either side where the organ spoke once, plaster fallen to brick here too. The screen:
  an old sheet behind the picture, stained at its edges, in black masking whose top right end has come down; the
  stains and the masking never cover the picture (the picture's frame is checked from every seat). A torn red curtain
  on the left in tatters to the floor, a strip of it on the right with its heap below, the valance hanging in rags.
  The stage of boards, some gone (joists and the dark below), a panelled riser, the pit's boards with holes.
- **The roof:** the front half's ceiling, plaster on laths, coffered, with holes through to the dark roof space and
  one right through the roof (stars show through it from the seats); its broken edge over the stalls: snapped joists,
  some hanging, laths dangling, lumps of plaster. Over the open half three king-post trusses against the sky (the
  rear one broken, a rafter down), purlins and the ridge, a patch of rafters and battens with slates on the right
  slope, slates slid and caught, the gables' coping.
- **The stalls:** the plush seats faded (velvet, walnut-veneer backs), 13 tipped up and 8 broken (the seats
  system's `up` and `broken`, never the viewer's own), leaves and moss on some; the aisles' carpet rotted to the
  boards in patches; rubble and fallen bricks along the walls, a heap under the left wall's break. The chandelier
  lies where it fell, off to the right of the pit: a brass column, three rings, eight arms, a basket and festoons of
  crystal drops and prisms scattered round it, catching the moonlight (fixed glints in their vertex colours).
- **Nature:** ivy in heavy masses on the walls under the open roof and in cascades from the ceiling's edge; a young
  birch through the stalls on the right (a white trunk with dark marks, weeping branches, its leaves above head
  height turning); ferns in the pit's corners, by the stage, in the floor's holes and the doorways; hart's-tongue in
  the brick's joints; patches of grass with wildflowers (white, pale yellow) and willowherb under the open sky; moss on
  the boards, the steps and the seats; leaf litter everywhere it can lie, a few leaves floating on the puddle.
- **The light:** the Moon, high in the west-south-west (`sky` `moon_bearing` 246, `moon_altitude` 45), comes through
  the open roof as a cold pool on the stalls: the left wall's ragged top throws its shadow across the pit, the
  trusses theirs across the right wall and the floor; a narrow shaft through the roof's hole makes a small pool on
  the pit's floor under the front roof. The run-time lightmapper threw no shadows (a box under a spot, tested under
  lavapipe), so the Moon's light is traced in code as the room is built: for each vertex of the baked meshes, the
  ray to the Moon against the walls' tops, the gables, the trusses' members, the front roof (only through its hole)
  and the slates; its light goes in the vertex colour's alpha and the house shader adds it (`vertex_light`, new,
  additive: 0 in every other room). The trusses' and the slates' shadows are soft bands, their penumbra widening
  with the distance (wider than the Moon's own), so they fall across the vertices smoothly, never in steps. The bake
  takes the Moon's light as an emitter, so it bounces softly into the shadow; the sky's light from the opening is a
  share beside it, on the rear wall as on the side walls. The unbaked parts (the leaves, the brass, the seats'
  instance colours) take the same light in their vertex colours. All of it is house light: the film takes it to the
  house lights' floor (`dimmed_level` 0.02 gives 0.0004, held at the shader's `house_floor`, 4 %). The film's light
  only tints the ruin (`spill` 0.35 on the tiers and the seats; the brick 0.06, the plaster 0.09, the timber 0.08,
  the cloth 0.12 of it: at twice these the test picture's warm and cool halves split the hall in two), and the
  projector's beam is a faint haze (`beam_haze` 0.12; at 0.25 it was a bright slab past the side seats). No live
  light, no bake light; the house lamps, step lights and signs dead; the booth's lit port and the crystals' glints are
  emission.
- **Systems:** `light` (a cold fill, `baked_fill` 0.3, `bake` on), `auditorium` (`shell` `kit`, 16 x 15.6 m,
  `ceiling_cover` 0.5, 3 rows of 21 plush seats behind the viewer's front row, `stage_depth` 1.5), `screen_frame`
  (no masking: the ruin draws its own; the projector's beam), `kit` (the four ruin pieces), `seats` (`broken`, `up`),
  `sky` (a September night at 52 degrees north, a Moon nearly full; clouds on `weather.wet`), `weather` (rain
  through the open roof and a leak over the pit, the puddle), `atmosphere` (a little haze in the beam; one low mist
  layer on `weather.wet`), `life` (`birds` on the trusses and the walls' tops, `fireflies`, `deer` from the rear
  door down the left aisle and out by the side door), `acoustics` `outdoors`, `sound_bed` (rain, rain on the boards,
  drips, wind, crickets, owl).
- **Setting:** Weather (`weather`: changing, rain, mist, clear) maps onto `weather.mode` (changing, heavy, light,
  clear); mist is a drizzle, and the mist rises with the wet.
- **Cues:** `birds_start` (a loud bang while playing: the birds scatter; chance 0.6, at most every 3 minutes),
  `deer_in_quiet` (6 s of a quiet scene: the deer comes; chance 0.5, at most every 15 minutes).
- **Comfort:** the creatures stay at the edges (the deer down the side aisle, never in the sight line; the birds
  high on the trusses); the chandelier, the birch and the meadow stand clear of every seat's sight line (tested);
  nothing in the ruin moves but the rain, the fireflies and the creatures; the Moon's pools never move.
- **The puddle:** the viewer sits in the front row so nothing hides the pit; the eye mirrored in the puddle's plane
  sees the picture's middle 3.6 m ahead, in the puddle (the test works it out).
- **Measured** (`tests/test_room_reclaimed.gd`, headless, 2026-11-08, after the second pass): 25 draws, 256 149
  triangles, no live light, 1 200 particles, 7.3 MB. Before the deep pass (`test_room_set5.gd`): 30 draws, 116 858
  triangles, 1 600 particles, 10.4 MB. By part: the leaves (ivy, the birch, ferns, the meadow, moss, litter) 92.9k
  triangles in 1 draw, the seats 54.1k (2 draws), the plaster 44.5k, the timber 17.4k, the brick 12.4k, the
  tipped-up seats 8.4k, the cloth 5.8k, the broken seats 5.2k, the crystal 4.2k, the stars 4.0k, the brass 3.9k, the
  sky 2.4k, the rest a few hundred. The bake: five static meshes, 0.86 M texels in their atlases, the largest 688 x
  584; the lightmap 1024 x 1024, two layers (12.6 MB); about 16 s under lavapipe (before the texels were coarsened,
  26 s).
- **Measured in the render** (`test_room_reclaimed.gd` with `RECL_BAKE`, at the headset's room light: the room's
  ambient before the film, times `dimmed_level` in it; luminance of the shown colours as `test_room_atmospheric_1928.gd`
  measures its houses): the walls beside the picture 0.047 before the film and 0.044 in it, the floor before the
  viewer 0.201 and 0.071 (the puddle's reflection of the picture most of it), the picture 0.57. Before the second
  pass: the walls 0.064 and 0.099 (the film lit them more than the Moon did), the floor 0.204 and 0.104.
- **The costs to watch on the Frame:** fill is small: everything opaque on the house shader but the rain, the
  fireflies, the beam's haze and one mist layer; the leaves are double-sided quads in one draw. Geometry is the most
  of any room so far (256k triangles, the leaves 94k of it). The bake's time on the headset is the thing to judge,
  then the frame time with the rain at full.
- **The render** (lavapipe, `test_room_reclaimed.gd` with `RECL_BAKE`): from the seat, left, right, up, back, a
  side seat and up behind, in the pre-show and with a film; close in the pre-show (`RECL_CLOSE`): the chandelier,
  the proscenium, the ceiling's edge, the birch, the curtain, the meadow, the shaft's pool, the roof's hole, the
  right wall and the left wall's plaster, the rear wall with the clock, the booth's ports.
- **Sound:** open air (`acoustics` `outdoors`); rain on the leaves round the viewer (`sound_bed` `rain_leaves`, four
  voices under the open roof) and on the boards behind (`rain_leaves` at `pitch` 0.7, `gain_db` -6), both with their
  `level` on `weather.rain`; drips into the puddle after it (`drips`, `level` on `weather.wet`); a soft wind high
  over the open roof (`wind`, two voices 8.5 m up, `gain_db` -6); crickets outside the side door by the stage when it
  is dry (`crickets`, `gain_db` -12, 10 dB lower in the film, `level` on `weather.rain` inverted); a tawny owl far off
  in the trees behind (`tawny_owl`, `every` 170, 32 m off, 14 dB lower in the film). The birds' calls are the birds'
  own (`life`). Measured (`test_room_set5.gd`, the slider's default, rain and wet at full): -49.8 dBFS RMS in
  the pre-show, -64.5 under a film at the reference level (before the pass -49.9 and -64.0).
- **To judge on the Frame:** the bake's time and the frame time (256k triangles; the rain at full); the Moon's level
  (`MOON_LIGHT` in `kit/reclaimed.gd`) and the film's 4 % of it (the house floor); whether the film's tint on the
  walls is enough to feel the picture in the room; whether the lightmapper on the headset does throw
  shadows (it should not matter: no light is baked, the Moon is emission); the crickets', the owl's and the wind's
  levels by ear.

### Room: Ice cinema

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
  particles, 10.4 MB of textures; a clear sight line from all 117 seats. Sound at the slider's default (dBFS RMS,
  `film.bass` held at 0.8): -57.9 in the pre-show, -56.7 in the film, -61.8 under a film at the reference level.
- **Sound:** `acoustics` `small_room` (rt60 0.6); `sound_bed` `next_screen` (`wall_rumble` through the left wall,
  `at` [-5.4, 1.5, -2], `reach` 5.5): `level` on `film.bass` (smooth 0.3 s), `film_db` 0, so it swells with the
  film's low end and is silent when there is none; the duck keeps it under the film.

### Room: Drive-in - 1958

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
- **Sound:** `acoustics` `small_room` (rt60 0.45); `sound_bed` `fire` at the hearth (`reach` 2.5); `sound_bed`
  `pump` (`hum`: the pool's filter pump beyond the window, `at` [-3.6, 0.6, -2.2], `reach` 3); `sound_bed` `bells`
  (`three_bells`, `film_db` -4), played first in the ritual (`bells.play`) before the painting rises.
- **Measured:** 18 draws, 9 600 triangles, 0 lights, 0 particles, 10.4 MB. Sound at the slider's default (dBFS RMS):
  -58.1 in the pre-show, -53.9 as the film starts (the bells), -65.2 in the film, -72.9 under a film at the reference
  level.
- **Not yet:** a bar cart (the object library has none, and a room that ships as a document places no objects).

### Room: Athens rooftop

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

### Room: Crater

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
  a large glass dome, rt60 1.1, wet 0.35.

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

### Time travel

One film, and while it plays the room moves forward through the history of television, an era at a time
(`scripts/env/time_travel.gd`, `main.features.time_travel`; the Room tab's Television group: Time travel, and Over
the film or every 5, 10 or 15 minutes; the assistant's `time_travel`). The eras are the TV rooms whose ids start
`tv_`, in the order of their year (`tv_today` and `tv_future` last); the Pillow Fort is not an era. Turned on in a
room that is not an era, it goes to the first at once. Over the film, the rest of the film is shared by the eras
still to come (at least a minute each). The countdown runs only while the film plays; it stops itself at the last
era, at the end of the film, on a new file, and when the viewer picks a room that is not an era. The film plays on
through each change: only the room changes.

### Room: TV 1930 - glowing box

1 of 12. A small dark parlour with a coal fire. A mechanical-scan set in a walnut cabinet on a walnut chest glows
orange with thirty lines (`glowbox_1930`, its sound through the radio cabinet's speaker). Three club chairs in
velvet, two angled in beside the viewer's. A wall lamp, a night window.

- Systems: `light` (a low, warm fill), `domestic` (2 x 1.4 m in front, 2.6 m behind; fireplace on the right, the
  window on the left with a dark night glow), `seats` (two club chairs as places), `presentation`.
- Settings: Lines in the picture (30 as it was, 60, 120: `presentation.mech_lines` by `map`); Fire in the grate
  (`domestic.fire`).
- Cues: `tuning_in` (Pre-show): the set switched on (`starts_off`: dark before; `switch_on`), the signal weak at the
  start, the picture coming in over 6 s; `switch_off` at the end. The lamp down to 15 % in the film.
- Measured: 18 draws, 2 216 triangles, 10 MB, no particles.
- Sound: `acoustics` `small_room`; the coal fire (`sound_bed` `fire` in the grate, `gain_db` -3, on the Fire setting);
  a clock on the mantel (`clock`); the disc's motor (`hum` at the set, `gain_db` -4). No tube whine: thirty lines on a
  spinning disc, no tube. Measured (`test_room_tv.gd`, the slider's default): -55.0 dBFS RMS in the pre-show, -69.0
  under a film at the reference level.

**Switching on and off** (since 2026-11-07, every TV room but tomorrow's): the set is dark in the pre-show
(`presentation.starts_off`), switches on its own way as the film starts (a cue's `presentation.switch_on`, with the
Pre-show setting on; with it off, the set comes on by itself when the film plays: a valve set's slow warm-up, a
tube's dot opening out, a panel coming up, a projector's lamp) with its own sounds (`switch_clunk`, `valve_hum`), and
off when the film ends (`presentation.switch_off`). The 1966 and 1972 sets then change channel once, with the knob's
clunk (`presentation.channel`). `test_room_tv.gd` `switches()` checks each room.

### Room: TV 1937 - mirror lid

2 of 12. A well-to-do drawing room: pale green walls, a herringbone parquet floor with a deep red rug, a white marble
fireplace with a coal fire, two velvet armchairs angled in beside the viewer's, a standard lamp, a walnut sideboard
with the tea tray on it, a fern. The set is a walnut cabinet whose lid holds a mirror (`telly` `mirror_lid`): the
tube faces up in the cabinet's top and the picture is seen in the mirror in the open lid (`mirrorlid_1937`: 405 lines,
black and white, a small round 5:4 tube, the film panned and scanned to fill it, a ten-second warm-up). The mirror is
a true one (see `mirror_lid` under the domestic builder): it reflects the room for each eye, and the film is on the
tube's face, so looking down into the set shows the tube itself. `test_mirror_view.gd` checks it.

- Systems: `light`, `domestic` (2.9 m high; the picture 0.40 x 0.32 m, 1.1 m from the seat, its bottom 0.98 m up;
  the window on the left with a dark night glow, the fireplace on the right, `surround` `white_marble`), `kit` (a
  `rug`, a `standard_lamp`, a `sideboard`, a `tea_set` on it, ferns), `seats` (two armchairs as places),
  `presentation` (`starts_off`).
- Settings: Snow from the aerial (0 to 50 %); Wrong way round (`presentation.mirror`: the picture as the mirror shows
  it, left and right swapped; off by default, as the set's own electronics turned it round); Fire in the grate.
- Cues: `switch_on` (Pre-show): the valves warm up over 10 s (`starting_seconds` 10); `switch_off` at the end. The
  lamps (the standard lamp with them) down to 25 %.
- Measured: 26 draws, 4 134 triangles, 12.0 MB, no particles.
- Sound: `acoustics` `small_room`; `sound_bed`s `fire` in the grate (on the Fire setting), `clock` on the mantel,
  `tube_whine` at 405 lines (`pitch` 0.648, `gain_db` -4); the switch's clunk and the valves' hum are the set's.
  Measured (`test_room_tv2.gd`): -56.5 dBFS RMS in the pre-show, -68.4 under a film at the reference level.
- The size table's 17 degrees would put the cabinet's front 0.15 m from the armchair; the mirror's picture is wider
  than a real one (0.40 m), so the chair can sit back.

### Room: TV 1953 - coronation day

3 of 12. Coronation day, June 1953: a terraced front room crammed for the day. Every chair in the house is pulled
round one small set in a walnut cabinet (`fireside_1953`: 405 lines, snow and a ghost): the viewer's armchair
straight in front of it (the best seat), two more armchairs angled in, six kitchen chairs behind, three stools, two
cushions on the rug in front where the children would sit. All empty. Bunting in red, white and blue across the
ceiling in three strings, a tea set on the sideboard, plates of paste sandwiches on the sideboard and on a side table,
the coal fire lit, the cat on the hearth. It rained that day: a grey sky in the window and rain on the glass. No
crown, no flag, no arms, no broadcaster's mark: the bunting's colours are all there is of the day.

- Systems: `light`, `domestic` (2.3 m half width, 3.3 m behind; `outside` `glow` grey), `kit` (ferns, a `rug`,
  three `bunting`, a `sideboard` with a `tea_set` and `sandwiches`, a `coffee_table` with two plates of `sandwiches`,
  three `stool`s), `seats` (two armchairs, six kitchen chairs (`folding_chair`) and two `cushion`s as places; the
  viewer's armchair the builder's, `seat_pitch` 0.96 so it draws with the others), `weather` (changing, mostly rain:
  `cycle_start` 0.5, 500 drops outside the window, the pane), `life` (`cat`, along the hearth), `presentation`.
- Settings: Snow from the aerial (0 to 60 %: `presentation.snow`); Fire in the grate.
- Cues: `switch_on` (Pre-show): the set dark until then, the valves warming up over 8 s; `switch_off` at the end. The
  lamps down to 25 %.
- The set stays 19 degrees across from the viewer's chair (the size table): the room is crowded round a small set,
  and the viewer has the good chair.
- Measured: 29 draws, 7 665 triangles, 12.0 MB, 500 particles (the sky and the hills gave way to a grey glow, which
  paid for the chairs and the dressing).
- Sound: `acoustics` `small_room`; the fire's crackle in the grate (`sound_bed` `fire`, on the Fire setting); a clock
  on the mantel (`clock`); rain on the window (`rain_glass` at the pane, `level` on `weather.rain`); the tube's faint
  whine at a 405-line set's 10 125 Hz (`tube_whine`, `pitch` 0.648, `gain_db` -4); the cat's purr is `life`'s.
  Measured (`test_room_tv.gd`, the slider's default, the rain full): -52.7 dBFS RMS in the pre-show, -65.1 under a
  film at the reference level.

### Room: TV 1966 - rented set

4 of 12. A 1960s living room in orange and teak: a pale wall, a deep orange carpet with a rug, the rented set in a
teak console on splayed legs (`telly` `console`, its doors folded back, `rental_1966`: 405 lines, the film panned and
scanned to fill the 4:3 tube), a rotary channel dial and two small knobs in the strip beside the picture, a long teak
sideboard on the left wall, a low teak coffee table, an orange settee (the viewer in its middle) and an orange
armchair, a standard lamp with an orange shade, a dusk sky and hills in the window on the right.

- Systems: `light`, `domestic` (the picture 0.48 x 0.36 m, its bottom 0.7 m up, 1.35 m from the seat; `telly_doors`;
  a radiator under the window), `kit` (a `channel_dial` on the console's front beside the picture, a `sideboard`, a
  `rug`, a `coffee_table`, a `standard_lamp`, ferns), `seats` (`model` `settee` in the builder's three slots, an
  armchair as a place), `sky` (dusk 0.55), `vista` (hills), `presentation` (`starts_off`).
- Settings: Snow from the aerial (0 to 50 %); Wall lamps in the film (0 to 100 %, default 30 %).
- Cues: `switch_on` (Pre-show): the valves warm up over 9 s, then the channel knob turns once (`presentation.channel`,
  1.2 s, its clunk; `starting_seconds` 12); `switch_off` at the end. The lamps down to the setting.
- Measured: 28 draws, 10 390 triangles, 14.3 MB, no particles.
- Sound: `acoustics` `small_room`; `sound_bed`s `radiator` under the window (`gain_db` -2), `clock` on the sideboard,
  `tube_whine` at 405 lines (`pitch` 0.648, `gain_db` -3: a dual-standard set, on the older channels' 405 lines).
  Measured (`test_room_tv2.gd`): -63.3 dBFS RMS in the pre-show, -71.7 under a film at the reference level.

### Room: TV 1972 - first colour

5 of 12. Mustard walls with orange and brown bands sweeping behind the set, a swirling carpet with a mustard rug on
it, three club chairs in orange velour and a bean bag. An early colour set in a teak-look cabinet on a radiogram
(`colourstar_1972`: a shadow mask, warm rich colour), a teak sideboard on the right wall, a standard lamp in the
corner. A summer dusk in the window.

- Systems: `light`, `domestic` (a radiator under the window; `telly_stand` `radiogram`), `kit` (carpet, curves on the
  front wall, a velvet `rug`, a `sideboard`, a `standard_lamp` with an orange shade), `seats` (a bean bag as a
  place), `sky` (dusk 0.45), `vista` (hills), `presentation`.
- Settings: Snow from the aerial (0 to 40 %); Colour (the set's colour knob, 0.5 to 1.5 times: `presentation.colour`).
- Cues: `switch_on` (Pre-show): the valves warm up over 5 s, then the channel knob turns once with its clunk;
  `switch_off` at the end. The lamps (and the standard lamp's shade: house group) down to 30 %.
- Measured: 24 draws, 9 694 triangles, 7.5 MB (before the furniture: 19 draws, 9 252 triangles, 7.5 MB).
- Sound: `acoustics` `small_room`; `sound_bed`s `radiator` at the radiator, `clock` on the sideboard, `tube_whine` at
  the set (about -52 dBFS together, 14 dB under the target).

### Room: TV 1983 - desk portable

6 of 12. A small room at night: a light grey portable telly (a carry handle, a rod aerial, its knobs at the side) on
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

7 of 12. The family living room on a wet night: a black telly on a wooden tv unit with a video recorder in its shelf,
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

8 of 12. A teenager's bedroom (not the pillow fort): blue walls, fairy lights along the wall over the telly, the bed,
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

### Room: TV 2002 - rear projection

9 of 12. A beige lounge with a cream carpet: a big deep rear projection set filling the end of the room (`telly`
`rear_projection`, `telly_aspect` wide: a charcoal cabinet from the floor, 0.62 m deep, a 50 inch 16:9 picture;
`projection_2002`: soft focus, colour fringes, a hotspot, fine lines on the screen, the picture dimming seen from off
its axis, a slow fade up as it switches on); a black leather sofa of three (the viewer in its middle) and a leather
armchair, a glass coffee table on a steel frame, a tall floor lamp, a plant, a dusk window.

- Systems: `light`, `domestic` (the picture 1.12 x 0.63 m, its bottom 0.6 m up, 3.1 m from the seat), `kit` (a
  `glass_table`: its top in the kit's glass, see-through; a `floor_lamp`, ferns), `seats` (`settee` in black
  leather, an armchair), `sky`, `vista`, `presentation` (`starts_off`).
- Settings: Wall lamps in the film; Lamp in the set (0.8 to 1.1 times: `presentation.gain`, an old projection lamp's
  dimmer picture).
- Cues: `switch_on` (Pre-show; the lamp comes up over 3 s with the switch's clunk), `switch_off` at the end; the
  lamps down to the setting.
- Measured: 25 draws, 9 832 triangles, 9.3 MB, no particles.
- Sound: `acoustics` `small_room`; the set's cooling fan (`sound_bed` `hum` at the set, `gain_db` -3). Measured
  (`test_room_tv2.gd`): -68.7 dBFS RMS in the pre-show, -83.8 under a film at the reference level.

### Room: TV 2005 - flat screen

10 of 12. A pale living room with a laminate floor, a grey three-seat settee and an armchair, a coffee table, a plant,
a wide window on a sunset. A 32 inch flat panel on its pedestal on a low pale wooden tv unit (`freedtv_2005`: a free
digital broadcast, a faint pixel grid, the backlight through the dark scenes).

- Systems: `light`, `domestic` (`telly` `flat_panel`, 7 cm deep, on a `tv_unit` 1.4 m wide; seat pitch 0.6 m), `kit`
  (ferns, a `coffee_table`), `seats` (`model` `settee` in the builder's slots; the armchair), `sky` (dusk 0.6),
  `vista` (hills), `presentation`.
- Settings: Wall lamps in the film; Backlight bleed (`presentation.panel_bleed`).
- Cues: `switch_on` (Pre-show, 2 s in: the panel just comes up), `switch_off` at the end; the lamps down to the
  setting.
- Measured: 21 draws, 9 690 triangles, 10.3 MB (before the furniture: 19 draws, 10 232 triangles, 10.3 MB).
- Sound: `acoustics` `small_room` only; no beds (a flat panel is silent).

### Room: TV today - the present

11 of 12. A living room now: charcoal walls, a grey oak floor with a pale grey rug, a very thin OLED panel on the
wall (`telly` `oled`, 3 cm; a 55 inch 16:9 picture, 3.2 m from the seat) over a long low oak media unit, a soundbar
on the unit under the picture, a grey sofa of three and an armchair, a low oak coffee table, a tall floor lamp beside
the sofa, a plant, a night window with rain on it now and then. No wall lamps, no fire: the film looks its best here
(`slimline_present`: true blacks, letterboxed, a sheen only at a glance; the film's own sound, no small speaker).

- Systems: `light` (a low grey fill), `domestic` (`telly` `oled` on the `wall`; `lamps` 0, `heater` none, the
  window's night glow), `kit` (a `media_unit`, a `soundbar`, a `rug`, a `coffee_table`, a `floor_lamp`, ferns),
  `seats` (`settee`, an armchair), `weather` (changing, the pane only: no drops falling), `presentation`
  (`slimline_present`, `starts_off`, `speaker` none).
- Settings: Floor lamp in the film (0 to 100 %, default 15 %: the house group, the floor lamp's shade).
- Cues: `switch_on` (Pre-show, 2 s in), `switch_off` at the end; the floor lamp down to the setting.
- Measured: 22 draws, 2 956 triangles, 7.0 MB, no particles.
- Sound: `acoustics` `small_room` (`rt60` 0.3: soft furnishings); `rain_glass` at the window (`gain_db` -6, `level`
  on `weather.rain`). Measured (`test_room_tv2.gd`, the rain full): -65.3 dBFS RMS in the pre-show, -80.3 under a
  film at the reference level.

### Room: TV tomorrow - the wall

12 of 12. Speculative, and kept calm: a bare pale room some day to come, a grey oak floor with a pale felt rug, a low
linen sofa of three (the viewer in its middle), a long window on a night of stars. No set at all: a part of the far
wall, in the walls' own plaster, becomes the picture. As the film starts it wakes, its light rising from half to full
over 4 s; then the film plays untouched.

- Systems: `light` (a cool low fill), `domestic` (`screen` `wall`, `screen_surface` the walls' plaster; `lamps` 0,
  `heater` none), `kit` (a `rug`), `seats` (`settee`), `sky` (night, a few clouds, the Milky Way faint),
  `presentation` (`preset` none: only the waking cue touches the picture).
- Settings: Stars in the window (0 to 100 %: `sky.stars`).
- Cues: `wall_wakes` (Pre-show): `presentation.gain` 0.5, then up to 1 over 4 s, then released.
- Measured: 13 draws, 7 662 triangles, 5.3 MB, no particles.
- Sound: `acoustics` `small_room` (`rt60` 0.3) and nothing else: a quiet room.

**The kit's dressing for these rooms** (`kit/dressing.gd`, since 2026-11-07): `bunting` (a sagging string of
pennants, red, white and blue in turn), `tea_set`, `sandwiches`, `stool`, `channel_dial` (a rotary dial with twelve
stops and two small knobs under it, on a set's front), `soundbar`, `floor_lamp` (a column shade, house group), `glass_table`
(the kit's glass mesh, `PieceGlass`, see-through) and `media_unit`. The china and the cloth (bunting, bread) are one
material each, coloured per vertex: bunting, a tea set and three plates of sandwiches cost two draws.

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
