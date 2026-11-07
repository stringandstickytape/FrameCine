extends "res://scripts/env/systems/env_system.gd"

## An instrument that plays itself (docs/environments.md, "Sound and music"): a player piano or a pipe organ, from our
## own synthesiser (scripts/env/env_synth.gd: the piano's two detuned strings, the organ's stops by additive
## synthesis). No one plays it: the keys move by themselves. What it plays is written here as it goes, from simple
## rules and the room's seed: a key, a progression of common chords, a form (A A' B A) and a tune of our own over it.
## Never a melody we don't own; no samples.
##
##   piano  a silent-film accompaniment: an oom-pah left hand and a tune in the right, starting when the film starts
##          (the starting state); drive (bind it to film.transient) makes it faster and louder, and a sudden jump in
##          the film turns it to an agitato (tremolo chords) until it calms
##   organ  slow chords in four voices (a chorale), held and voiced smoothly, for the pre-show, the interval and the
##          end; flourish plays a closing cadence (the ritual)
##
## It plays on the room's bus (acoustics.gd BUS, under Environment) at its designed level (LEVELS, 12 dB or more under
## the level check's target), film_db lower while the film plays, ducked under the film.
##   sounding() -> bool, resting() -> bool, notes_played, voices_sounding() -> int, bar_kind,
##   piece() -> {key, mode, form, progressions}

const EnvSynth := preload("res://scripts/env/env_synth.gd")
const EnvAudio := preload("res://scripts/env/env_audio.gd")
const EnvDoc := preload("res://scripts/env/env_doc.gd")
const Acoustics := preload("res://scripts/env/systems/acoustics.gd")

const INSTRUMENTS: Array[String] = ["piano", "organ"]
## Designed level: dBFS RMS on Environment at the slider's default, full level, no film (measured over its playing).
const LEVELS := {"piano": -51.0, "organ": -52.0}
## A note's player volume against its designed level: the notes overlap (measured, test_env_music.gd).
const NOTE_DB := {"piano": -0.9, "organ": -3.9}
const OWN_STATES := {"piano": ["starting", "playing", "credits"], "organ": ["preshow", "intermission", "ended"]}
const OWN_TEMPO := {"piano": 104.0, "organ": 56.0}
const FILM_STATES: Array[String] = ["starting", "playing", "credits"]
const VOICES := 12
const MAJOR := [0, 2, 4, 5, 7, 9, 11]
const MINOR := [0, 2, 3, 5, 7, 8, 11]
const MAJOR_KEYS := [0, 5, 7, 2, 10, 3]
const MINOR_KEYS := [9, 2, 4, 7]
## Common progressions (scale degrees, 8 bars): the harmony everyone shares.
const PROGRESSIONS := [[1, 6, 4, 5, 1, 6, 2, 5], [1, 4, 1, 5, 1, 4, 5, 1], [1, 1, 4, 4, 1, 5, 5, 1],
		[6, 2, 5, 1, 6, 2, 5, 5], [1, 5, 6, 4, 1, 4, 5, 1], [4, 1, 2, 5, 4, 1, 5, 1]]
## The tune's rhythms in a bar of 4/4, in eighths.
const CELLS := [[2, 2, 2, 2], [2, 1, 1, 2, 2], [1, 1, 2, 1, 1, 2], [3, 1, 2, 2], [2, 2, 4], [1, 1, 1, 1, 2, 2],
		[4, 2, 2], [3, 3, 2]]
## Drive over this: agitato; under QUIET: a sparse accompaniment.
const AGITATO := 0.65
const QUIET := 0.12
const OFF := 0.001


static func spec() -> Dictionary:
	return {
		"kind": "music",
		"description": "An instrument that plays itself, from our own synthesiser: a player piano (a silent-film "
				+ "accompaniment that starts with the film and follows its jumps) or a pipe organ (slow chords for "
				+ "the pre-show, the interval and the end; a closing cadence for the ritual). It writes its own "
				+ "simple music as it goes; never a melody we don't own. Well under the film.",
		"params": {
			"instrument": {"type": "enum", "values": INSTRUMENTS, "default": "piano", "description": "which one"},
			"on": {"type": "bool", "default": true, "live": true,
					"description": "it plays (bind it to a room setting: piano on or off)"},
			"gain_db": {"type": "float", "min": -30.0, "max": 6.0, "default": 0.0, "live": true, "loudness": true,
					"description": "dB from its designed level (12 dB or more under the level check's target)"},
			"level": {"type": "float", "min": 0.0, "max": 1.0, "default": 1.0, "live": true, "loudness": true,
					"description": "how loud (linear; 0: silent)"},
			"drive": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.3, "live": true,
					"description": "how lively: tempo, touch and, over 0.65, an agitato; bind it to film.transient"},
			"plays_in": {"type": "list", "of": {"type": "enum", "values": EnvDoc.STATES}, "max": 7, "default": [],
					"description": "the states it plays in; empty: its own (piano: starting, playing, credits; "
					+ "organ: preshow, intermission, ended)"},
			"film_db": {"type": "float", "min": -40.0, "max": 0.0, "default": -6.0, "live": true,
					"description": "dB lower while the film plays"},
			"tempo": {"type": "float", "min": 0.0, "max": 200.0, "default": 0.0,
					"description": "beats a minute at drive 0.5; 0: its own (piano 104, organ 56)"},
			"seed": {"type": "int", "min": 0, "max": 9999, "default": 0,
					"description": "which piece it writes (0: from its id)"},
			"mode": {"type": "enum", "values": ["major", "minor"], "default": "major", "description": "major or minor"},
			"stop": {"type": "enum", "values": EnvSynth.STOPS.keys(), "default": "theatre",
					"description": "the organ's stop: flute, principal, full or theatre"},
			"tremulant": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.35, "live": true,
					"description": "the organ's tremulant (a slow waver)"},
			"detune_cents": {"type": "float", "min": 0.0, "max": 25.0, "default": 7.0,
					"description": "the piano's strings out of tune with each other (an upright's honky-tonk)"},
			"at": {"type": "vec3", "min": -500.0, "max": 500.0, "default": null, "nullable": true,
					"description": "where it stands in the room's frame; none: everywhere"},
			"reach": {"type": "float", "min": 0.5, "max": 100.0, "default": 6.0,
					"description": "metres within which it is at its level"},
		},
		"actions": {"play": "plays now, whatever the state (args: seconds; 0: until stop)",
				"stop": "stops (args: seconds to fade)", "flourish": "a closing cadence, then rest (the ritual)"},
		"cost": {"draws": 0, "triangles": 0, "lights": 0, "particles": 0, "texture_mb": 0, "voices": VOICES},
	}


var notes_played := 0
var _task := -1
var _made := {}
var _loaded := false
var _rng := RandomNumberGenerator.new()
## Voices: {player, off, releasing, release, fade, gain_db, midi, pitch}
var _voices: Array = []
var _players: Array[Node] = []
var _time := 0.0
var _beat := 0.0
## Events to come: [beat, midi, velocity, beats]
var _events: Array = []
var _bar := 0
var _key := 0
var _scale: Array = MAJOR
var _form: Array = []
var _melody := {}
var _last_top := 72
var _organ_voices := [43, 55, 64, 72]
var _organ_held := {}
var _flourish := false
## The beat the flourish ends on: then it rests (-1: none).
var _rest_at := -1.0
## The last bar written: "oompah", "quiet", "agitato", "chorale" or "flourish" (tests).
var bar_kind := ""
var _state_db := 0.0
var _state_target := 0.0
## 0..1: the instrument faded in (it plays) or out.
var _fade := 0.0
var _fade_seconds := 1.5
var _forced := 0.0
var _forced_on := false
## The stop action: silent until the next play or the next state.
var _stopped := false


func _instrument() -> String:
	return str(params.get("instrument", "piano"))


func _states() -> Array:
	var given: Array = params.get("plays_in", [])
	return given if not given.is_empty() else OWN_STATES[_instrument()]


func _state() -> String:
	return str(host.timeline.state) if host != null and host.get("timeline") != null else "preshow"


func setup() -> void:
	Acoustics.ensure_bus()
	var sd := int(params["seed"])
	_rng.seed = sd if sd > 0 else hash(id + _instrument())
	_compose()
	_state_db = float(params["film_db"]) if _state() in FILM_STATES else 0.0
	_state_target = _state_db
	var at: Variant = params.get("at")
	for i in VOICES:
		var p: Node
		if at != null:
			var p3 := AudioStreamPlayer3D.new()
			p3.position = RoomSchemaRef.vec3(at)
			p3.unit_size = float(params["reach"])
			p3.max_db = 0.0
			p3.attenuation_filter_db = 0.0
			p = p3
		else:
			p = AudioStreamPlayer.new()
		p.name = "%s_voice%d" % [id, i]
		p.set("bus", Acoustics.BUS)
		own(p)
		_players.append(p)
	var missing := _needed().filter(func(k: Array) -> bool: return EnvSynth.note(str(k[0])) == null)
	if missing.is_empty():
		_loaded = true
	else:
		_task = WorkerThreadPool.add_task(_make_job.bind(missing), false, "music " + _instrument())


## The notes it needs: [[key, kind, pitch]].
func _needed() -> Array:
	var out: Array = []
	if _instrument() == "piano":
		var d := float(params["detune_cents"])
		for b in range(EnvSynth.PIANO_LOW, EnvSynth.PIANO_HIGH + 1, EnvSynth.PIANO_STEP):
			out.append([EnvSynth.piano_key(b, d), "piano", b])
	else:
		for m in range(24, 90):
			out.append([EnvSynth.organ_key(m, str(params["stop"])), "organ", m])
	return out


func _make_job(missing: Array) -> void:
	for k: Array in missing:
		if k[1] == "piano":
			_made[k[0]] = EnvSynth.make_piano_note(int(k[2]), float(params["detune_cents"]))
		else:
			_made[k[0]] = EnvSynth.make_organ_note(int(k[2]), str(params["stop"]))


func finish_loading() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_store()


func _store() -> void:
	for k: String in _made:
		EnvSynth.put_note(k, _made[k])
	_made.clear()
	_loaded = true


# --- The piece ---------------------------------------------------------------------------------------------------------

## A key, a mode and a form of 8-bar sections (A A' B A) on two progressions.
func _compose() -> void:
	var minor := str(params["mode"]) == "minor"
	_scale = MINOR if minor else MAJOR
	var keys: Array = MINOR_KEYS if minor else MAJOR_KEYS
	_key = int(keys[_rng.randi_range(0, keys.size() - 1)])
	var a: Array = PROGRESSIONS[_rng.randi_range(0, PROGRESSIONS.size() - 1)]
	var b: Array = PROGRESSIONS[_rng.randi_range(0, PROGRESSIONS.size() - 1)]
	var a_end: Array = a.duplicate()
	a_end[7] = 1
	a_end[6] = 5
	_form = [["A", a], ["A2", a_end], ["B", b], ["A", a_end]]
	_melody.clear()


func piece() -> Dictionary:
	return {"key": _key, "mode": str(params["mode"]), "form": _form.map(func(s: Array) -> String: return str(s[0])),
			"progressions": _form.map(func(s: Array) -> Array: return s[1])}


## The chord of a bar: its scale degree and its tones as pitch classes (root first).
func _chord(bar: int) -> Array:
	var sec: Array = _form[(bar / 8) % _form.size()]
	var deg := int(sec[1][bar % 8]) - 1
	var tones: Array = []
	for k in [0, 2, 4]:
		tones.append((_key + int(_scale[(deg + k) % 7])) % 12)
	return tones


func _nearest(pcs: Array, near: int, lo: int, hi: int) -> int:
	var best := near
	var dist := 1000
	for m in range(lo, hi + 1):
		if (m % 12) in pcs and absi(m - near) < dist:
			dist = absi(m - near)
			best = m
	return best


func _in_scale(m: int) -> bool:
	return ((m - _key + 120) % 12) in _scale


func _step(m: int, dir: int) -> int:
	var n := m + dir
	while not _in_scale(n):
		n += dir
	return n


## A bar of the tune (right hand): [[beat in bar, midi, beats]]. The A sections repeat their tune.
func _tune(bar: int) -> Array:
	var sec: Array = _form[(bar / 8) % _form.size()]
	var key := "%s:%d" % [sec[0], bar % 8]
	if _melody.has(key):
		return _melody[key]
	var pcs := _chord(bar)
	var cell: Array = CELLS[_rng.randi_range(0, CELLS.size() - 1)]
	if bar % 8 == 7:
		cell = [2, 2, 4]
	var out: Array = []
	var pos := 0.0
	var m := _nearest(pcs, _last_top, 67, 84)
	for k in cell.size():
		var beats := float(cell[k]) / 2.0
		if k > 0:
			if beats >= 1.0 or _rng.randf() < 0.4:
				m = _nearest(pcs, m + _rng.randi_range(-3, 3), 67, 84)
			else:
				m = _step(m, 1 if (_rng.randf() < 0.5 or m < 69) and m < 82 else -1)
		out.append([pos, m, beats])
		pos += beats
	if bar % 8 == 7:
		out[-1][1] = _nearest([pcs[0]], m, 67, 84)
	_last_top = m
	_melody[key] = out
	return out


## The next bar's events, from the drive now.
func _write_bar() -> void:
	var start := float(_bar * 4)
	var drive := float(params["drive"])
	var pcs := _chord(_bar)
	if _flourish:
		_write_flourish(start)
		_flourish = false
		_rest_at = start + 12.0
		_bar += 3
		bar_kind = "flourish"
		return
	if _instrument() == "organ":
		_write_organ(start, pcs)
		bar_kind = "chorale"
	elif drive > AGITATO:
		bar_kind = "agitato"
		# Agitato: the left hand's octaves on every eighth, a diminished chord trembling in the right.
		var root := 36 + (int(pcs[0]) % 12)
		var dim: Array = [int(pcs[0]) % 12, (int(pcs[0]) + 3) % 12, (int(pcs[0]) + 6) % 12, (int(pcs[0]) + 9) % 12]
		for e in 8:
			_events.append([start + e * 0.5, root + (12 if e % 2 == 1 else 0), 0.85, 0.45])
		var low := _nearest(dim, 64, 60, 72)
		var high := _nearest(dim, low + 7, low + 1, low + 12)
		for s in 16:
			_events.append([start + s * 0.25, low if s % 2 == 0 else high, 0.8, 0.22])
	else:
		bar_kind = "oompah" if drive >= QUIET else "quiet"
		var bass := 36 + (int(pcs[0]) % 12)
		var fifth := 36 + ((int(pcs[0]) + 7) % 12)
		_events.append([start, bass, 0.75, 0.9])
		_events.append([start + 2.0, fifth if _bar % 2 == 0 else bass + 12, 0.7, 0.9])
		if drive >= QUIET:
			for b: float in [1.0, 3.0]:
				for pc: int in pcs:
					_events.append([start + b, _nearest([pc], 57, 52, 64), 0.5, 0.7])
		for n: Array in _tune(_bar):
			if drive < QUIET and float(n[2]) < 1.0:
				continue
			_events.append([start + float(n[0]), int(n[1]), 0.85, float(n[2]) * 0.9])
	_bar += 1


## The organ: four voices on the chord, each to its nearest tone; a held tone is not struck again.
func _write_organ(start: float, pcs: Array) -> void:
	var ranges := [[36, 50], [48, 62], [55, 69], [62, 77]]
	var next: Array = []
	next.append(_nearest([pcs[0]], _organ_voices[0], 36, 50))
	for v in range(1, 4):
		next.append(_nearest(pcs, int(_organ_voices[v]) + (_rng.randi_range(-2, 2) if v == 3 else 0),
				int(ranges[v][0]), int(ranges[v][1])))
	for v in 4:
		var m := int(next[v])
		_events.append([start, m, 0.9 if v == 3 else 0.75, 4.0, v])
	# The soprano's passing note half way when it moves a third.
	var top := int(next[3])
	var later := _nearest(_chord(_bar + 1), top, 62, 77)
	if absi(later - top) in [3, 4]:
		_events.append([start + 2.0, _step(top, 1 if later > top else -1), 0.8, 2.0, 3])
	_organ_voices = next


## A closing cadence: an arpeggio up the home chord, the dominant, the home chord held.
func _write_flourish(start: float) -> void:
	var home: Array = [_key, (_key + int(_scale[2])) % 12, (_key + 7) % 12]
	var dom: Array = [(_key + 7) % 12, (_key + 11) % 12, (_key + 2) % 12]
	var m := 55
	for k in 8:
		m = _nearest(home, m + 3, m + 1, m + 8)
		_events.append([start + k * 0.5, m, 0.8, 4.0 - k * 0.5, -1])
	for pc: int in dom:
		_events.append([start + 4.0, _nearest([pc], 62, 55, 70), 0.85, 4.0, -1])
	_events.append([start + 4.0, 43, 0.85, 4.0, -1])
	for pc: int in home:
		_events.append([start + 8.0, _nearest([pc], 64, 57, 72), 0.9, 4.0, -1])
	_events.append([start + 8.0, 36 + _key, 0.9, 4.0, -1])
	_events.append([start + 8.0, 72 + _key if 72 + _key <= 79 else 60 + _key, 0.9, 4.0, -1])


# --- Playing -------------------------------------------------------------------------------------------------------------

func _wants() -> bool:
	if not bool(params["on"]) or float(params["level"]) < OFF:
		return false
	if _stopped:
		return false
	if _forced_on:
		return true
	return _state() in _states()


func on_state(state: String, previous: String) -> void:
	_state_target = float(params["film_db"]) if state in FILM_STATES else 0.0
	_stopped = false
	if state == "starting" and previous != "starting" and _instrument() == "piano":
		# The film starts from its start: the piano starts its piece.
		_restart()


func _restart() -> void:
	_release_all(0.1)
	_events.clear()
	_bar = 0
	_beat = 0.0


func _param_changed(param: String, _value: Variant) -> void:
	if param == "film_db":
		_state_target = float(params["film_db"]) if _state() in FILM_STATES else 0.0


func act(action: String, args: Dictionary) -> void:
	match action:
		"play":
			_forced_on = true
			_stopped = false
			_forced = float(args.get("seconds", 0.0))
			_fade_seconds = 0.5
		"stop":
			_forced_on = false
			_stopped = true
			_fade_seconds = maxf(float(args.get("seconds", 2.0)), 0.05)
		"flourish":
			# After the bar that plays now: the cadence.
			var next_bar := ceili(_beat / 4.0)
			_events = _events.filter(func(e: Array) -> bool: return float(e[0]) < float(next_bar * 4))
			_bar = next_bar
			_flourish = true
			# It plays whatever the state, then rests.
			_forced_on = true
			_forced = 0.0
			_stopped = false
			_fade_seconds = 0.5


func _tempo() -> float:
	var t := float(params["tempo"])
	if t <= 0.0:
		t = float(OWN_TEMPO[_instrument()])
	return t * (0.85 + 0.3 * float(params["drive"]))


## The designed level now (dBFS RMS at the slider's default, no film), with gain, level, state and fade.
func designed_db() -> float:
	return float(LEVELS[_instrument()]) + float(params["gain_db"]) + _state_db \
			+ linear_to_db(maxf(float(params["level"]) * _fade, 1e-6))


func _base_db() -> float:
	return designed_db() - EnvAudio.DEFAULT_DB - EnvSynth.REFERENCE_DB + float(NOTE_DB[_instrument()])


func tick(delta: float) -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_store()
	_time += delta
	_state_db = move_toward(_state_db, _state_target, delta * 3.0)
	if _forced_on and _forced > 0.0:
		_forced -= delta
		if _forced <= 0.0:
			_forced_on = false
	var want := _wants() and _loaded
	if want and _fade <= 0.0 and _voices.is_empty():
		# From silence: its next bar starts now, not at the next bar line.
		_events.clear()
		_beat = float(_bar * 4)
	_fade = move_toward(_fade, 1.0 if want else 0.0, delta / _fade_seconds)
	if not want and _fade <= 0.0:
		_release_all(0.3)
		_fade_seconds = 1.5
	if _fade > 0.0 and _loaded:
		var beats := delta * _tempo() / 60.0
		var end := _beat + beats
		if _events.is_empty() or float(_events[-1][0]) < end + 4.0:
			while _events.is_empty() or float(_events[-1][0]) < end + 4.0:
				_write_bar()
			_events.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
		while not _events.is_empty() and float(_events[0][0]) < end:
			var e: Array = _events.pop_front()
			if float(e[0]) >= _beat - 1.0 and want:
				_note_on(int(e[1]), float(e[2]), float(e[3]) * 60.0 / _tempo(), int(e[4]) if e.size() > 4 else -1)
		_beat = end
		if _rest_at >= 0.0 and _beat >= _rest_at:
			# The cadence is over: it rests until it is played again or the state changes.
			_rest_at = -1.0
			_forced_on = false
			_stopped = true
			_fade_seconds = 1.5
	_update_voices(delta)


func _note_on(midi: int, velocity: float, seconds: float, organ_voice: int) -> void:
	var stream: AudioStreamWAV
	var pitch := 1.0
	if _instrument() == "piano":
		var base := EnvSynth.piano_base(midi)
		stream = EnvSynth.note(EnvSynth.piano_key(base, float(params["detune_cents"])))
		pitch = pow(2.0, (midi - base) / 12.0)
	else:
		midi = clampi(midi, 24, 89)
		# Held a little past its bar, so the next chord finds it still sounding.
		seconds += 0.2
		if organ_voice >= 0 and _organ_held.has(organ_voice):
			var held: Dictionary = _organ_held[organ_voice]
			if int(held["midi"]) == midi and not bool(held["releasing"]) \
					and _voices.any(func(x: Dictionary) -> bool: return is_same(x, held)):
				# The same tone in this voice: held on, not struck again.
				held["off"] = _time + seconds
				return
			held["off"] = minf(float(held["off"]), _time)
		stream = EnvSynth.note(EnvSynth.organ_key(midi, str(params["stop"])))
		pitch = EnvSynth.organ_pitch_scale(midi)
	if stream == null:
		return
	var v := _free_voice()
	var p: Node = v["player"]
	p.set("stream", stream)
	p.set("pitch_scale", pitch)
	v["pitch"] = pitch
	v["midi"] = midi
	v["gain_db"] = linear_to_db(velocity)
	v["off"] = _time + seconds
	v["releasing"] = false
	v["release"] = 0.0
	v["fade"] = 1.0
	p.set("volume_db", _base_db() + float(v["gain_db"]))
	p.call("play")
	_voices.append(v)
	if _instrument() == "organ" and organ_voice >= 0:
		_organ_held[organ_voice] = v
	notes_played += 1


func _free_voice() -> Dictionary:
	for p in _players:
		var busy := false
		for v: Dictionary in _voices:
			if v["player"] == p:
				busy = true
				break
		if not busy:
			return {"player": p}
	# All busy: the oldest.
	var oldest: Dictionary = _voices.pop_front()
	return {"player": oldest["player"]}


func _release_all(seconds: float) -> void:
	for v: Dictionary in _voices:
		if not bool(v["releasing"]):
			v["releasing"] = true
			v["release"] = seconds


func _update_voices(delta: float) -> void:
	var base := _base_db()
	var trem := float(params["tremulant"]) if _instrument() == "organ" else 0.0
	var wave := sin(TAU * 6.2 * _time)
	for i in range(_voices.size() - 1, -1, -1):
		var v: Dictionary = _voices[i]
		var p: Node = v["player"]
		if not bool(v["releasing"]) and _time >= float(v["off"]):
			v["releasing"] = true
			v["release"] = 0.09 if _instrument() == "piano" else 0.15
		if bool(v["releasing"]):
			v["fade"] = float(v["fade"]) - delta / maxf(float(v["release"]), 0.01)
		var playing: bool = p.call("is_playing")
		if float(v.get("fade", 1.0)) <= 0.0 or not playing:
			p.call("stop")
			_voices.remove_at(i)
			continue
		p.set("volume_db", base + float(v["gain_db"]) + linear_to_db(maxf(float(v["fade"]), 1e-4))
				+ wave * 2.0 * trem)
		if trem > 0.0:
			p.set("pitch_scale", float(v["pitch"]) * (1.0 + wave * 0.004 * trem))


func sounding() -> bool:
	return not _voices.is_empty()


## After a flourish or a stop: silent until it is played again or the state changes.
func resting() -> bool:
	return _stopped and _voices.is_empty()


func voices_sounding() -> int:
	return _voices.size()


func is_ready() -> bool:
	return _loaded


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
