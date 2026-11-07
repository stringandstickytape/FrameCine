extends Node

## The audio buses (docs/environments.md, "The audio buses"): the rain must never drown out the film.
##   Master        the Volume slider (main.gd sets bus 0)
##     Film        the player's sound: the stereo stream and the binaural renderer's mix (scripts/play/spatial_audio.gd)
##     Environment the room: the thud, cue sounds, sound beds. A compressor keyed from Film ducks it under the film;
##                 its volume is the Environment sound slider, the room's offset (the common ambience_db setting,
##                 off at its bottom), the room's own level (its document's audio.level_db) and the pause rise
##     Interface   the pane's and the tools' sounds
##
##   ensure_buses()                       static: makes the buses once (the player calls it before it makes its own)
##   environment_db, set_environment_db(v)   [audio] environment_db, MIN_DB (off) .. 0 dB, default DEFAULT_DB
##   play(sound, gain_db, at) -> Node     a synthesised sound (env_synth.gd) on Environment, at a place or not
##   bus_volume_db() -> float             what the Environment bus is set to now
##   measure_level(streams, seconds) -> float   the level check: the bus's RMS (dBFS) while these play
##   rising                               the pause rise is on (paused, the pre-show, the intermission, ended)

const EnvSynth := preload("res://scripts/env/env_synth.gd")

const FILM := "Film"
const ENVIRONMENT := "Environment"
const INTERFACE := "Interface"
## The slider: off .. full (0 dB: the room's sounds at the film's reference level); the default is 18 dB under.
const MIN_DB := -60.0
const DEFAULT_DB := -18.0
## The room's offset at its bottom mutes the room (env_doc.gd COMMON_SETTINGS ambience_db).
const ROOM_OFF_DB := -25.0
## The duck: a compressor on Environment keyed from Film. The engine's compressor reduces by about 2.08 x (the
## sidechain's peak over the threshold, in dB) x (1 - 1 / ratio): chosen from tests/test_env_audio.gd's tones for
## about 8 dB under a film at the reference level (peaks near -17 dBFS), about 20 dB under a loud scene, none in
## silence.
const DUCK_THRESHOLD_DB := -26.0
const DUCK_RATIO := 1.75
const DUCK_ATTACK_US := 20000.0
const DUCK_RELEASE_MS := 300.0
## The pause rise fades over this long.
const RISE_SECONDS := 2.0
## The level check's target: the room's ambience at the slider's default, RMS, no louder than this (dBFS): the film's
## reference minus 18 dB.
const LEVEL_TARGET_DB := EnvSynth.REFERENCE_DB + DEFAULT_DB

var main: Node3D
var environment_db := DEFAULT_DB
var rising := false
var _rise := 0.0
var _applied := INF


## Film, Environment and Interface under Master, Environment with its duck; once.
static func ensure_buses() -> void:
	for n: String in [FILM, ENVIRONMENT, INTERFACE]:
		if AudioServer.get_bus_index(n) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, n)
			AudioServer.set_bus_send(i, &"Master")
	var e := AudioServer.get_bus_index(ENVIRONMENT)
	if AudioServer.get_bus_effect_count(e) == 0 or not (AudioServer.get_bus_effect(e, 0) is AudioEffectCompressor):
		var c := AudioEffectCompressor.new()
		c.sidechain = StringName(FILM)
		c.threshold = DUCK_THRESHOLD_DB
		c.ratio = DUCK_RATIO
		c.attack_us = DUCK_ATTACK_US
		c.release_ms = DUCK_RELEASE_MS
		c.gain = 0.0
		AudioServer.add_bus_effect(e, c, 0)
		AudioServer.set_bus_volume_db(e, DEFAULT_DB)


static func environment_bus() -> int:
	return AudioServer.get_bus_index(ENVIRONMENT)


func _ready() -> void:
	ensure_buses()
	environment_db = clampf(float(main.settings.get_value("audio", "environment_db", DEFAULT_DB)), MIN_DB, 0.0)
	_apply()


func set_environment_db(v: float) -> void:
	environment_db = clampf(v, MIN_DB, 0.0)
	main.settings.set_value("audio", "environment_db", null if is_equal_approx(environment_db, DEFAULT_DB)
			else snappedf(environment_db, 0.5))
	_apply()


## The room's offset (its common ambience_db) and its own level (audio.level_db), in dB; the mute at its bottom.
func _room_db() -> Array:
	var offset := 0.0
	var level := 0.0
	var rs: Node = main.features.get("room_settings") if main.get("features") != null else null
	if rs != null:
		offset = float(rs.value("ambience_db"))
	if main.env != null and main.env.has_method("audio_level_db"):
		level = float(main.env.audio_level_db())
	return [offset, level]


func pause_rise_db() -> float:
	if main.env != null and main.env.has_method("pause_rise_db"):
		return float(main.env.pause_rise_db())
	return 3.0


## What the Environment bus is set to now (dB); -80 when off.
func bus_volume_db() -> float:
	var r := _room_db()
	if environment_db <= MIN_DB + 0.01 or float(r[0]) <= ROOM_OFF_DB + 0.01:
		return -80.0
	return environment_db + float(r[0]) + float(r[1]) + _rise * pause_rise_db()


func _apply() -> void:
	var e := environment_bus()
	if e < 0:
		return
	var v := bus_volume_db()
	AudioServer.set_bus_mute(e, v <= -79.0)
	if not is_equal_approx(v, _applied):
		_applied = v
		AudioServer.set_bus_volume_db(e, maxf(v, -80.0))


func _process(delta: float) -> void:
	rising = _wants_rise()
	_rise = move_toward(_rise, 1.0 if rising else 0.0, delta / RISE_SECONDS)
	_apply()


## The ambience rises a little in the pre-show, while paused, in the intermission and after the end.
func _wants_rise() -> bool:
	var host: Node = main.env.get_node_or_null("Systems") if main.env != null else null
	if host != null and host.get("timeline") != null:
		return str(host.timeline.state) in ["preshow", "paused", "intermission", "ended"]
	return not main.player.is_playing()


## A synthesised sound on Environment: at a place (room frame of the environment on show) or everywhere.
func play(sound: String, gain_db := 0.0, at: Variant = null) -> Node:
	var w := EnvSynth.stream(sound)
	if w == null:
		return null
	var p: Node
	if at is Vector3 and main.env != null:
		var p3 := AudioStreamPlayer3D.new()
		p3.unit_size = 3.0
		p3.max_db = 0.0
		p3.volume_db = gain_db
		p3.bus = ENVIRONMENT
		p3.stream = w
		main.env.add_child(p3)
		p3.position = at
		p3.play()
		p = p3
	else:
		var p2 := AudioStreamPlayer.new()
		p2.volume_db = gain_db
		p2.bus = ENVIRONMENT
		p2.stream = w
		add_child(p2)
		p2.play()
		p = p2
	if not (w.loop_mode == AudioStreamWAV.LOOP_FORWARD):
		p.connect("finished", p.queue_free)
	return p


## The level check (docs/environments.md): plays `streams` ([[AudioStream, gain_db], ...]) on Environment at the
## slider's default for `seconds` and returns the bus's RMS (dBFS) as heard after it, from an AudioEffectCapture.
## Awaitable: it runs in real time.
static func measure_level(tree: SceneTree, streams: Array, seconds := 2.0) -> float:
	ensure_buses()
	var e := environment_bus()
	var was := AudioServer.get_bus_volume_db(e)
	var was_mute := AudioServer.is_bus_mute(e)
	AudioServer.set_bus_volume_db(e, DEFAULT_DB)
	AudioServer.set_bus_mute(e, false)
	var cap := AudioEffectCapture.new()
	cap.buffer_length = 0.5
	AudioServer.add_bus_effect(e, cap)
	var players: Array[AudioStreamPlayer] = []
	for s: Array in streams:
		var p := AudioStreamPlayer.new()
		p.stream = s[0]
		p.volume_db = float(s[1])
		p.bus = ENVIRONMENT
		tree.root.add_child(p)
		p.play()
		players.append(p)
	var sum := 0.0
	var n := 0
	var t0 := Time.get_ticks_msec()
	# The bus volume is applied after the effects: the capture hears the sound before it, so the volume is added.
	while Time.get_ticks_msec() - t0 < int(seconds * 1000.0):
		await tree.process_frame
		var frames := cap.get_frames_available()
		if frames > 0:
			var buf := cap.get_buffer(frames)
			for f: Vector2 in buf:
				sum += (f.x * f.x + f.y * f.y) * 0.5
				n += 1
	for p in players:
		p.queue_free()
	for i in AudioServer.get_bus_effect_count(e):
		if AudioServer.get_bus_effect(e, i) == cap:
			AudioServer.remove_bus_effect(e, i)
			break
	AudioServer.set_bus_volume_db(e, was)
	AudioServer.set_bus_mute(e, was_mute)
	if n == 0:
		return -120.0
	return linear_to_db(sqrt(sum / n)) + DEFAULT_DB
