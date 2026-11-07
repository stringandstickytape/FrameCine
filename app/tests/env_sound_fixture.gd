extends RefCounted

## For the sound tests (test_env_sound_bed.gd, test_env_acoustics.gd, test_env_music.gd): a room document built alone
## (no main scene) with a listener at the seat, its timeline's state set by hand, and the level check: what reaches
## the Environment bus (after its duck) at the slider's default, as env_audio.gd measure_level() measures it, with the
## room's own systems playing. Static; preload to use.

const EnvAudio := preload("res://scripts/env/env_audio.gd")
const EnvSynth := preload("res://scripts/env/env_synth.gd")
const EnvRoom := preload("res://scripts/env/env_room.gd")
const EnvChecks := preload("res://scripts/env/env_checks.gd")
const Acoustics := preload("res://scripts/env/systems/acoustics.gd")

## The timeline's input for each state (env_timeline.gd).
const SNAPSHOTS := {
	"preshow": {"open": false},
	"starting": {"open": true, "playing": true, "position": 0.5, "duration": 5400.0},
	"playing": {"open": true, "playing": true, "position": 600.0, "duration": 5400.0},
	"paused": {"open": true, "playing": false, "position": 600.0, "duration": 5400.0},
}


static func build(tree: SceneTree, doc: Dictionary) -> Node3D:
	EnvAudio.ensure_buses()
	Acoustics.ensure_bus()
	var e := EnvAudio.environment_bus()
	AudioServer.set_bus_volume_db(e, EnvAudio.DEFAULT_DB)
	AudioServer.set_bus_mute(e, false)
	if tree.root.get_node_or_null("SoundListener") == null:
		var cam := Camera3D.new()
		cam.name = "SoundListener"
		tree.root.add_child(cam)
		cam.position = Vector3(0, 1.2, 0)
		cam.current = true
	var room: Node3D = EnvRoom.new()
	room.doc = doc
	tree.root.add_child(room)
	return room


static func set_state(room: Node3D, state: String) -> void:
	room.host.snapshot_override = SNAPSHOTS[state]


## Every sound system's streams and notes made now (they are made on worker threads).
static func finish_loading(room: Node3D) -> void:
	for s: Node in room.host.order:
		if s.has_method("finish_loading"):
			s.call("finish_loading")


## The Environment bus's RMS and peak (dBFS, as heard at the slider's default) over `seconds`, after `settle`; with
## film_db, a 1 kHz tone at that RMS on Film meanwhile (the duck).
static func measure(tree: SceneTree, seconds: float, settle := 0.3, film_db: Variant = null) -> Dictionary:
	var e := EnvAudio.environment_bus()
	AudioServer.set_bus_volume_db(e, EnvAudio.DEFAULT_DB)
	var film: AudioStreamPlayer = null
	if film_db != null:
		film = AudioStreamPlayer.new()
		film.stream = tone(1000.0, float(film_db))
		film.bus = &"Film"
		tree.root.add_child(film)
		film.play()
	var cap := AudioEffectCapture.new()
	cap.buffer_length = 0.5
	AudioServer.add_bus_effect(e, cap)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(settle * 1000.0):
		await tree.process_frame
		cap.clear_buffer()
	var sum := 0.0
	var n := 0
	var peak := 0.0
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(seconds * 1000.0):
		await tree.process_frame
		var k := cap.get_frames_available()
		if k > 0:
			for f: Vector2 in cap.get_buffer(k):
				sum += (f.x * f.x + f.y * f.y) * 0.5
				peak = maxf(peak, maxf(absf(f.x), absf(f.y)))
				n += 1
	for i in AudioServer.get_bus_effect_count(e):
		if AudioServer.get_bus_effect(e, i) == cap:
			AudioServer.remove_bus_effect(e, i)
			break
	if film != null:
		film.queue_free()
	var rms := linear_to_db(sqrt(sum / n)) + EnvAudio.DEFAULT_DB if n > 0 and sum > 0.0 else -120.0
	var pk := linear_to_db(peak) + EnvAudio.DEFAULT_DB if peak > 0.0 else -120.0
	return {"rms": rms, "peak": pk}


## The envelope of what reaches Environment (dBFS per window of `window` s) over `seconds` (a reverb's tail).
static func envelope(tree: SceneTree, seconds: float, window := 0.05) -> PackedFloat32Array:
	var e := EnvAudio.environment_bus()
	var cap := AudioEffectCapture.new()
	cap.buffer_length = maxf(seconds + 0.5, 1.0)
	AudioServer.add_bus_effect(e, cap)
	var t0 := Time.get_ticks_msec()
	var frames := PackedVector2Array()
	while Time.get_ticks_msec() - t0 < int(seconds * 1000.0):
		await tree.process_frame
		var k := cap.get_frames_available()
		if k > 0:
			frames.append_array(cap.get_buffer(k))
	for i in AudioServer.get_bus_effect_count(e):
		if AudioServer.get_bus_effect(e, i) == cap:
			AudioServer.remove_bus_effect(e, i)
			break
	var rate := AudioServer.get_mix_rate()
	var w := maxi(int(rate * window), 1)
	var out := PackedFloat32Array()
	var i := 0
	while i + w <= frames.size():
		var sum := 0.0
		for j in range(i, i + w):
			sum += (frames[j].x * frames[j].x + frames[j].y * frames[j].y) * 0.5
		out.append(linear_to_db(sqrt(sum / w)) if sum > 0.0 else -120.0)
		i += w
	return out


## A looping sine at this RMS level (dBFS).
static func tone(freq: float, rms_db: float) -> AudioStreamWAV:
	var rate := 44100
	var amp := db_to_linear(rms_db) * sqrt(2.0)
	var data := PackedByteArray()
	data.resize(rate * 2)
	for i in rate:
		data.encode_s16(i * 2, clampi(int(sin(TAU * freq * i / rate) * amp * 32767.0), -32767, 32767))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = rate
	return w


## The checks that need no built room, and the budget of the built one: [problems].
static func checks(tree: SceneTree, room: Node3D) -> Array:
	var out: Array = []
	var s := EnvChecks.static_checks(room.doc)
	for k: String in s:
		for p: Variant in s[k]:
			out.append("%s: %s" % [k, p])
	out.append_array(EnvChecks.budget(EnvChecks.measure(room)))
	out.append_array(await EnvChecks.sight_line(tree, room))
	return out
