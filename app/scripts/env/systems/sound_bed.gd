extends "res://scripts/env/systems/env_system.gd"

## A sound bed (docs/environments.md, "Sound and music"): one looped bed or one-shot of the room, from our own
## synthesiser (scripts/env/env_synth.gd), placed in the room: everywhere, at a place, or around the viewer; a
## one-shot can come back every so often and travel (a moped passing). A room has one sound_bed per sound, each with
## its own id. All of it plays on the room's bus (acoustics.gd BUS, under Environment): ducked under the film, at the
## Environment sound slider and the room's Ambience.
##
## Levels: each sound has its designed level (LEVELS: dBFS RMS at the slider's default, with no film; a one-shot's
## loudest second), 10 dB or more under the level check's target (env_audio.gd LEVEL_TARGET_DB). The player is set
## from the stream's own measured level, so the bed sits there whatever its peaks. gain_db moves it from there; level
## (0..1, live: film.bass for the wall's rumble, weather.rain for rain) scales it; the bed sits film_db lower while
## the film plays (starting, playing, credits) and comes back up in the pre-show, paused, the intermission and after
## the end, over `fade` seconds. "silence" plays nothing: a room that is meant to be silent (the crater) says so.
##
## The streams are made on a worker thread the first time (a few hundred ms each on a desktop), then cached.
##   playing() -> bool, players() -> Array, volume_db() -> float (the player's, before 3D attenuation)
##   designed_db() -> float     where it sits now at the slider's default (no film, before the duck)

const EnvSynth := preload("res://scripts/env/env_synth.gd")
const EnvAudio := preload("res://scripts/env/env_audio.gd")
const Acoustics := preload("res://scripts/env/systems/acoustics.gd")

const SOUNDS: Array[String] = ["silence", "projector", "wall_rumble", "cicadas", "moped", "train", "huskies",
		"hull_creak", "radiator", "rain_glass", "rain_leaves", "gas_hiss", "noise", "rumble", "tick", "creak", "whale",
		"chime", "gong", "bird", "purr", "crickets", "fire", "drips", "wind", "hum", "deep_hum", "fountain", "clock",
		"tube_whine", "three_bells", "candle", "ice_creak", "vcr", "tape_load", "switch_clunk", "valve_hum", "crt_off",
		"channel_clunk", "sonar", "bubbles", "scops_owl"]
## Each sound's designed level: dBFS RMS on Environment at the slider's default (-18 dB), full level, no film; a
## one-shot's loudest second. The level check's target is -38 dBFS; every bed is 12 dB or more under it.
const LEVELS := {"projector": -51.0, "wall_rumble": -50.0, "cicadas": -54.0, "moped": -52.0, "train": -52.0,
		"huskies": -54.0, "hull_creak": -52.0, "radiator": -55.0, "rain_glass": -52.0, "rain_leaves": -52.0,
		"gas_hiss": -58.0, "noise": -54.0, "rumble": -52.0, "tick": -55.0, "creak": -54.0, "whale": -52.0,
		"chime": -50.0, "gong": -52.0, "bird": -54.0, "purr": -56.0, "crickets": -55.0, "fire": -54.0, "drips": -56.0,
		"wind": -55.0, "hum": -58.0, "deep_hum": -54.0, "fountain": -56.0, "clock": -56.0, "tube_whine": -62.0,
		"three_bells": -50.0, "candle": -58.0, "ice_creak": -55.0, "vcr": -54.0, "tape_load": -58.0,
		"switch_clunk": -54.0, "valve_hum": -58.0, "crt_off": -60.0, "channel_clunk": -55.0, "sonar": -56.0,
		"bubbles": -57.0, "scops_owl": -58.0}
## The states in which the film plays: the bed sits film_db lower.
const FILM_STATES: Array[String] = ["starting", "playing", "credits"]
## Under this linear gain a bed stops its players.
const OFF := 0.001


static func spec() -> Dictionary:
	return {
		"kind": "sound",
		"description": "A looped bed or a one-shot from our own synthesiser, placed in the room: projector clatter, "
				+ "rumble through a wall, cicadas, a passing moped, a far freight train, far huskies, hull creaks, a "
				+ "ticking radiator, rain on glass or leaves, gas lamp hiss, crickets, a fire's crackle, drips, wind, "
				+ "a motor's hum, the deep's hum, a fountain, a clock, a picture tube's whine, a three-tone house bell, "
				+ "a candle's gutter, ice creaking, a video recorder taking a tape, a cassette loading, a telly's power "
				+ "switch, its valves' hum warming up, its tube's tick as it goes off, a channel knob's clunk, a "
				+ "sonar's ping, a vent's bubbles, a scops owl's call over the roofs, a bird, a purr or silence. It sits "
				+ "well under the film (its designed level, ducked under the film, lower while the film plays) and can "
				+ "follow a channel by its level "
				+ "(film.bass, weather.rain, weather.wet).",
		"params": {
			"sound": {"type": "enum", "values": SOUNDS, "default": "silence",
					"description": "the sound; silence plays nothing"},
			"gain_db": {"type": "float", "min": -30.0, "max": 6.0, "default": 0.0, "live": true, "loudness": true,
					"description": "dB from the sound's designed level (12 dB or more under the level check's target)"},
			"level": {"type": "float", "min": 0.0, "max": 1.0, "default": 1.0, "live": true, "loudness": true,
					"description": "how much of it (linear; 0: off); bind it to film.bass, weather.rain or a setting"},
			"film_db": {"type": "float", "min": -40.0, "max": 0.0, "default": -8.0, "live": true,
					"description": "dB lower while the film plays (starting, playing, credits); up again in the "
					+ "pre-show, paused, the intermission and after the end"},
			"fade": {"type": "float", "min": 0.1, "max": 20.0, "default": 3.0,
					"description": "seconds a change of state takes"},
			"place": {"type": "enum", "values": ["everywhere", "at", "around"], "default": "everywhere",
					"description": "everywhere (no direction), at a place, or around the viewer (voices round at)"},
			"at": {"type": "vec3", "min": -500.0, "max": 500.0, "default": [0.0, 1.2, 0.0],
					"description": "where it is, in the room's frame (the seat at the origin, the screen to -Z)"},
			"to": {"type": "vec3", "min": -500.0, "max": 500.0, "default": null, "nullable": true,
					"description": "a one-shot travels from at to here over its length (a moped passing)"},
			"radius": {"type": "float", "min": 0.5, "max": 50.0, "default": 3.0,
					"description": "around: metres from at"},
			"voices": {"type": "int", "min": 1, "max": 4, "default": 4,
					"description": "around: how many places round the viewer (each starts the loop elsewhere)"},
			"reach": {"type": "float", "min": 0.5, "max": 500.0, "default": 4.0,
					"description": "metres within which a placed sound is at its level; it falls off beyond"},
			"every": {"type": "float", "min": 0.0, "max": 7200.0, "default": 0.0,
					"description": "a one-shot: seconds between plays (0: only when a cue plays it); a loop ignores it"},
			"jitter": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.3,
					"description": "how much each gap varies (a share of every)"},
			"pitch": {"type": "float", "min": 0.5, "max": 2.0, "default": 1.0,
					"description": "playback pitch (and speed)"},
			"vary": {"type": "float", "min": 0.0, "max": 0.3, "default": 0.05,
					"description": "a one-shot's pitch varies this much each time"},
		},
		"actions": {"play": "plays the one-shot now (args: gain_db)", "stop": "fades the bed out (args: seconds)",
				"start": "fades it back in (args: seconds)"},
		"cost": {"draws": 0, "triangles": 0, "lights": 0, "particles": 0, "texture_mb": 0, "voices": 4},
	}


var _stream: AudioStreamWAV
var _stream_level := 0.0
var _task := -1
var _made: AudioStreamWAV
var _made_level := 0.0
var _players: Array[Node] = []
var _state_db := 0.0
var _state_target := 0.0
## The stop / start actions: 1 sounding, 0 faded out.
var _on := 1.0
var _on_target := 1.0
var _on_seconds := 1.0
var _until := 0.0
## A travelling one-shot: [player, from, to, seconds, t]
var _travel: Array = []
var _rng := RandomNumberGenerator.new()
var _pending_play := false
## One-shots played (tests).
var plays := 0


func _sound() -> String:
	return str(params.get("sound", "silence"))


func is_loop() -> bool:
	return _sound() in EnvSynth.LOOPS


func setup() -> void:
	_rng.seed = hash(id + _sound())
	if _sound() == "silence":
		return
	Acoustics.ensure_bus()
	_state_db = _film_db() if _in_film() else 0.0
	_state_target = _state_db
	var every := float(params["every"])
	_until = every * _rng.randf_range(0.2, 1.0) if every > 0.0 else 0.0
	if EnvSynth.cached(_sound()):
		_ready_stream(EnvSynth.stream(_sound()))
	else:
		_task = WorkerThreadPool.add_task(_make_job, false, "sound_bed " + _sound())


func _make_job() -> void:
	_made = EnvSynth.make(_sound())
	_made_level = EnvSynth.level_db(_made)


## The streams' measured levels, by sound (the main thread).
static var _levels := {}


func _ready_stream(w: AudioStreamWAV) -> void:
	_stream = w
	if _made == w:
		_levels[_sound()] = _made_level
	elif not _levels.has(_sound()):
		_levels[_sound()] = EnvSynth.level_db(w)
	_stream_level = float(_levels[_sound()])
	if is_loop():
		_start_loop()
	elif _pending_play:
		_pending_play = false
		_play_once(0.0)


func _in_film() -> bool:
	return host != null and host.get("timeline") != null and str(host.timeline.state) in FILM_STATES


func _film_db() -> float:
	return float(params["film_db"])


## The player's volume for the bed's level now (before 3D attenuation), per voice.
func volume_db() -> float:
	return designed_db() - EnvAudio.DEFAULT_DB - _stream_level - 10.0 * log(float(_voices())) / log(10.0)


## Where the bed sits now at the slider's default (dBFS RMS, no film): its level, gain, level, state and fades.
func designed_db() -> float:
	var g := float(params["level"]) * _on
	return float(LEVELS.get(_sound(), -60.0)) + float(params["gain_db"]) + _state_db + linear_to_db(maxf(g, 1e-6))


func _gain() -> float:
	return float(params["level"]) * _on


func _voices() -> int:
	return int(params["voices"]) if str(params["place"]) == "around" and is_loop() else 1


func _new_player(at: Variant) -> Node:
	var p: Node
	if at is Vector3:
		var p3 := AudioStreamPlayer3D.new()
		p3.unit_size = float(params["reach"])
		p3.max_db = 0.0
		p3.attenuation_filter_db = 0.0
		p3.position = at
		p = p3
	else:
		p = AudioStreamPlayer.new()
	p.name = "%s_%d" % [id, _players.size()]
	p.set("bus", Acoustics.BUS)
	p.set("stream", _stream)
	p.set("pitch_scale", float(params["pitch"]))
	own(p)
	_players.append(p)
	return p


func _places() -> Array:
	var at := RoomSchemaRef.vec3(params["at"])
	match str(params["place"]):
		"at":
			return [at]
		"around":
			var out: Array = []
			var n := _voices()
			var r := float(params["radius"])
			for k in n:
				var a := TAU * (k + 0.5) / n
				out.append(at + Vector3(sin(a) * r, 0.0, cos(a) * r))
			return out
	return [null]


func _start_loop() -> void:
	if _stream == null or not _players.is_empty() or _gain() < OFF:
		return
	var places := _places()
	var length := _stream.get_length()
	for k in places.size():
		var p := _new_player(places[k])
		p.set("volume_db", volume_db())
		p.call("play", fmod(length * (float(k) / places.size() + _rng.randf_range(0.0, 0.2)), length))


func _stop_players() -> void:
	for p in _players:
		if is_instance_valid(p):
			_owned.erase(p)
			p.queue_free()
	_players.clear()
	_travel.clear()


func _play_once(extra_db: float) -> void:
	if _stream == null:
		_pending_play = true
		return
	if _gain() < OFF:
		return
	var places := _places()
	var to: Variant = params.get("to")
	var at: Variant = places[0]
	if to != null and at == null:
		at = RoomSchemaRef.vec3(params["at"])
	var p := _new_player(at)
	p.set("volume_db", volume_db() + extra_db)
	p.set("pitch_scale", float(params["pitch"]) * (1.0 + float(params["vary"]) * _rng.randf_range(-1.0, 1.0)))
	p.set_meta("extra_db", extra_db)
	p.connect("finished", _on_finished.bind(p))
	plays += 1
	p.call("play")
	if to != null:
		_travel.append([p, at, RoomSchemaRef.vec3(to), _stream.get_length() / float(p.get("pitch_scale")), 0.0])


func _on_finished(p: Node) -> void:
	_players.erase(p)
	_owned.erase(p)
	for i in range(_travel.size() - 1, -1, -1):
		if _travel[i][0] == p:
			_travel.remove_at(i)
	p.queue_free()


func act(action: String, args: Dictionary) -> void:
	match action:
		"play":
			if not is_loop() and _sound() != "silence":
				_play_once(float(args.get("gain_db", 0.0)))
		"stop":
			_on_target = 0.0
			_on_seconds = maxf(float(args.get("seconds", 2.0)), 0.01)
		"start":
			_on_target = 1.0
			_on_seconds = maxf(float(args.get("seconds", 2.0)), 0.01)


func on_state(state: String, _previous: String) -> void:
	_state_target = _film_db() if state in FILM_STATES else 0.0


func _param_changed(param: String, _value: Variant) -> void:
	if param == "film_db":
		_state_target = _film_db() if _in_film() else 0.0


func tick(delta: float) -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		EnvSynth.put(_sound(), _made)
		_ready_stream(_made)
	if _stream == null:
		return
	var rate := absf(_film_db()) / float(params["fade"]) if absf(_film_db()) > 0.0 else 100.0
	_state_db = move_toward(_state_db, _state_target, rate * delta)
	_on = move_toward(_on, _on_target, delta / _on_seconds)
	if is_loop():
		if _gain() < OFF:
			if not _players.is_empty():
				_stop_players()
		elif _players.is_empty():
			_start_loop()
	else:
		var every := float(params["every"])
		if every > 0.0:
			_until -= delta
			if _until <= 0.0:
				_until = every * (1.0 + float(params["jitter"]) * _rng.randf_range(-1.0, 1.0))
				_play_once(0.0)
		for tr: Array in _travel:
			tr[4] = float(tr[4]) + delta
			var p: Node3D = tr[0]
			if is_instance_valid(p):
				p.position = (tr[1] as Vector3).lerp(tr[2], clampf(float(tr[4]) / float(tr[3]), 0.0, 1.0))
	var v := volume_db()
	for p in _players:
		if is_instance_valid(p):
			p.set("volume_db", v + float(p.get_meta("extra_db", 0.0)))


func playing() -> bool:
	return _players.any(func(p: Node) -> bool: return is_instance_valid(p) and bool(p.call("is_playing")))


func players() -> Array[Node]:
	return _players


func stream() -> AudioStreamWAV:
	return _stream


## Tests: wait for the worker (the stream ready now).
func finish_loading() -> void:
	if _task >= 0:
		tick(0.0)
		if _task >= 0:
			WorkerThreadPool.wait_for_task_completion(_task)
			_task = -1
			EnvSynth.put(_sound(), _made)
			_ready_stream(_made)


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
