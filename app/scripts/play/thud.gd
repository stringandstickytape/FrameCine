extends Node

## The one sound of object physics (docs/physics.md, "Sound"): a generic thud for every impact, made here (no sample
## files): a short low knock, a sine falling a little in pitch with a dull click of filtered noise on its front. Its
## loudness comes from the impact's speed and the object's size, its pitch from the size (bigger is lower; a faster
## impact a little higher). It is heard where it happened, through the spatial audio (scripts/play/spatial_audio.gd):
## a BinauralRenderer of its own with the output profile's HRTF set, tuning and EQ, the room's walls and reverb, the
## listener at the head each block. Up to VOICES at once; without the engine's renderer (or until its set has loaded,
## on a worker thread), an AudioStreamPlayer3D at the place.
##
##   play(position, speed, size) -> {position, speed, size, gain, pitch} ({} under THRESHOLD)
##   last, count         the last thud and how many there were (tests, object_physics state())
##   gain_for(speed, size), pitch_for(speed, size), samples(speed, size, rate)   (static)

## Impacts slower than this (m/s) are silent; FULL_SPEED is as loud as it gets. GAP: an object's thuds this far apart
## at least (s).
const THRESHOLD := 0.5
const FULL_SPEED := 12.0
const GAP := 0.08
## The loudest thud's peak (a 0.3 m object at FULL_SPEED).
const LEVEL := 0.45
const LENGTH := 0.24
const VOICES := 4
const BLOCK := 512
const BUFFER_SECONDS := 0.15
## After the last thud the room's reverb rings this long; then the stream stops.
const TAIL_SECONDS := 0.8
## Pitch: this (Hz) for a 0.3 m object, as the square root of its size, within PITCH_RANGE.
const PITCH_AT_30CM := 150.0
const PITCH_RANGE := Vector2(45.0, 600.0)
const SpatialAudio := preload("res://scripts/play/spatial_audio.gd")

var main: Node3D
var last := {}
var count := 0
var _rate := 48000.0
var _renderer: Object
var _task := -1
var _loaded := false
var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
## Playing: [{samples, at, position}]
var _voices: Array = []
var _idle := 0.0
## The waveform at gain 1 for a pitch (its semitone) and decay: key -> PackedFloat32Array.
static var _waves := {}


func _ready() -> void:
	_rate = AudioServer.get_mix_rate() if AudioServer.get_mix_rate() > 0.0 else 48000.0


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	if _renderer != null and not (_renderer is RefCounted):
		_renderer.free()
	_renderer = null


## How loud (the peak, 0..1): the square root of the speed over the threshold (as loudness grows), times the size's.
static func gain_for(speed: float, size: float) -> float:
	var s := clampf((speed - THRESHOLD) / (FULL_SPEED - THRESHOLD), 0.0, 1.0)
	var big := clampf(sqrt(maxf(size, 0.01) / 0.3), 0.4, 1.6)
	return clampf(LEVEL * sqrt(s) * big, 0.0, 1.0)


static func pitch_for(speed: float, size: float) -> float:
	return clampf(PITCH_AT_30CM * sqrt(0.3 / maxf(size, 0.02)) * (1.0 + 0.015 * speed), PITCH_RANGE.x, PITCH_RANGE.y)


## The thud's samples at `rate`: the waveform for its pitch (made once a semitone) at its gain.
static func samples(speed: float, size: float, rate: float) -> PackedFloat32Array:
	var f := pitch_for(speed, size)
	var semitone := roundi(12.0 * log(f) / log(2.0))
	var key := "%d %d" % [semitone, roundi(rate)]
	if not _waves.has(key):
		_waves[key] = _wave(pow(2.0, semitone / 12.0), rate)
	var wave: PackedFloat32Array = _waves[key]
	var g := gain_for(speed, size)
	var out := PackedFloat32Array()
	out.resize(wave.size())
	for i in wave.size():
		out[i] = wave[i] * g
	return out


## One knock at gain 1: a 1 ms rise, a fall faster for higher (smaller) ones, the pitch dropping from 1.5 times.
static func _wave(f: float, rate: float) -> PackedFloat32Array:
	var n := int(LENGTH * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var decay := 14.0 + f * 0.09
	var phase := 0.0
	var lp := 0.0
	var peak := 0.0
	for i in n:
		var t := float(i) / rate
		var env := (1.0 - exp(-t * 1000.0)) * exp(-t * decay)
		phase += TAU * f * (1.0 + 0.5 * exp(-t * 50.0)) / rate
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.2
		out[i] = env * (0.85 * sin(phase) + 0.9 * lp * exp(-t * 80.0))
		peak = maxf(peak, absf(out[i]))
	if peak > 0.0:
		for i in n:
			out[i] /= peak
	return out


## A thud where an impact happened (world), `speed` m/s, an object `size` metres across.
func play(at: Vector3, speed: float, size: float) -> Dictionary:
	if speed < THRESHOLD:
		return {}
	var g := gain_for(speed, size)
	last = {"position": at, "speed": snappedf(speed, 0.01), "size": snappedf(size, 0.001), "gain": snappedf(g, 0.0001),
			"pitch": snappedf(pitch_for(speed, size), 0.1)}
	count += 1
	var s := samples(speed, size, _rate)
	if _binaural():
		if _voices.size() >= VOICES:
			_voices.pop_front()
		_voices.append({"samples": s, "at": 0, "position": at})
		_set_sources()
		_start_stream()
	else:
		_play_3d(s, at)
	return last


## The spatial audio's renderer can be used: the engine has it, a set is chosen, and ours has loaded it.
func _binaural() -> bool:
	if _loaded:
		return true
	var sp: Node = main.features.get("speakers") if main != null and main.get("features") != null else null
	if sp == null or not ClassDB.class_exists("BinauralRenderer"):
		return false
	if _task < 0 and _renderer == null:
		var file: String = sp.hrtf_file(str(sp.get("hrtf")))
		if file == "":
			return false
		_renderer = ClassDB.instantiate("BinauralRenderer")
		_renderer.set_sample_rate(_rate)
		var r: Object = _renderer
		_task = WorkerThreadPool.add_task(func() -> void: r.load_hrtf(file))
		return false
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_loaded = _renderer.is_ready()
		if _loaded:
			var ps: Dictionary = sp.profile_settings()
			var t: Dictionary = ps.get("tuning", {})
			_renderer.set_tuning(float(t.get("itd_scale", 1.0)), float(t.get("pinna_warp", 1.0)),
					float(t.get("concha_db", 0.0)))
			_renderer.set_eq(ps.get("eq", []))
			_renderer.set_gain(SpatialAudio.GAIN)
	return _loaded


func _set_sources() -> void:
	var given: Array = []
	for i in VOICES:
		var p: Vector3 = _voices[i]["position"] if i < _voices.size() else Vector3.FORWARD
		given.append({"input": i, "kind": "point", "position": p, "gain": 1.0, "at_infinity": false,
				"reflections": true})
	_renderer.set_sources(given)
	var sp: Node = main.features.get("speakers")
	if sp != null and sp.has_method("_room"):
		_renderer.set_room(sp.call("_room", false))


func _start_stream() -> void:
	_idle = 0.0
	if _player != null and _player.playing:
		return
	if _player == null:
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = _rate
		gen.buffer_length = BUFFER_SECONDS
		_player = AudioStreamPlayer.new()
		_player.name = "ThudStream"
		_player.stream = gen
		add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback()
	_renderer.reset()


func _process(delta: float) -> void:
	if _player == null or not _player.playing or _playback == null:
		return
	var cam: Node3D = main.camera if main != null else null
	if cam != null:
		_renderer.set_listener(cam.global_transform)
	while _playback.get_frames_available() >= BLOCK:
		_playback.push_buffer(_block())
	if _voices.is_empty():
		_idle += delta
		if _idle > TAIL_SECONDS:
			_player.stop()


## The next BLOCK frames: each voice's samples on its own input, the renderer's binaural mix of them.
func _block() -> PackedVector2Array:
	var input := PackedFloat32Array()
	input.resize(BLOCK * VOICES)
	for v in _voices.size():
		var s: PackedFloat32Array = _voices[v]["samples"]
		var at: int = _voices[v]["at"]
		for i in mini(BLOCK, s.size() - at):
			input[i * VOICES + v] = s[at + i]
		_voices[v]["at"] = at + BLOCK
	var before := _voices.size()
	_voices = _voices.filter(func(x: Dictionary) -> bool:
		return int(x["at"]) < (x["samples"] as PackedFloat32Array).size())
	if _voices.size() != before and not _voices.is_empty():
		_set_sources()
	var st: PackedFloat32Array = _renderer.render(input, VOICES)
	var out := PackedVector2Array()
	out.resize(BLOCK)
	for i in mini(BLOCK, st.size() / 2):
		out[i] = Vector2(st[2 * i], st[2 * i + 1])
	return out


## Without the renderer: the engine's own 3D sound at the place.
func _play_3d(s: PackedFloat32Array, at: Vector3) -> void:
	var data := PackedByteArray()
	data.resize(s.size() * 2)
	for i in s.size():
		data.encode_s16(i * 2, clampi(roundi(s[i] * 32767.0), -32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = int(_rate)
	wav.stereo = false
	wav.data = data
	var p := AudioStreamPlayer3D.new()
	p.name = "Thud3D"
	p.stream = wav
	p.unit_size = 3.0
	p.max_db = 0.0
	add_child(p)
	p.global_position = at
	p.finished.connect(p.queue_free)
	p.play()
