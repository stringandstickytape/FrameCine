extends SceneTree

## The audio buses (docs/environments.md, "The audio buses") in the real main scene: Film, Environment and Interface
## under Master; the player (and so the binaural renderer's mix) on Film, the thud and the room's sounds on
## Environment; the Environment sound slider (default 18 dB under, off at its bottom, kept only when changed); the
## room's offset and mute; the pause rise; the duck under the film measured with test tones; and the level check over
## every room's sounds. Prints the measured figures.
## godot --headless --xr-mode off --path app --script res://tests/test_env_audio.gd

const EnvAudio := preload("res://scripts/env/env_audio.gd")
const EnvSynth := preload("res://scripts/env/env_synth.gd")
const EnvDoc := preload("res://scripts/env/env_doc.gd")
const Thud := preload("res://scripts/play/thud.gd")

var _failures := 0
var _checks := 0
var main: Node3D


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	await _frames(5)
	var a: Node = main.features.env_audio
	for n: String in ["Film", "Environment", "Interface"]:
		var i := AudioServer.get_bus_index(n)
		_check("bus %s, to Master" % n, i > 0 and AudioServer.get_bus_send(i) == &"Master")
	_check("the film plays on Film (%s)" % main.player.audio.bus, main.player.audio.bus == &"Film")
	_check("the thud on Environment", Thud._bus() == &"Environment")
	var e := EnvAudio.environment_bus()
	var comp := AudioServer.get_bus_effect(e, 0) as AudioEffectCompressor
	_check("Environment's compressor keyed from Film", comp != null and comp.sidechain == &"Film")

	# The slider.
	main.set_environment("void")
	await _frames(3)
	_check("the slider's default: -18 dB (%s)" % a.environment_db, is_equal_approx(a.environment_db, -18.0)
			and not main.settings.has_value("audio", "environment_db"))
	a.set_environment_db(-30.0)
	_check("a change kept", is_equal_approx(float(main.settings.get_value("audio", "environment_db", 0.0)), -30.0))
	a._rise = 0.0
	_check("the bus follows (%.1f)" % a.bus_volume_db(), is_equal_approx(a.bus_volume_db(), -30.0))
	a.set_environment_db(-18.0)
	_check("back to the default: the key erased", not main.settings.has_value("audio", "environment_db"))
	a.set_environment_db(EnvAudio.MIN_DB)
	await _frames(2)
	_check("at the bottom: off (muted)", AudioServer.is_bus_mute(e))
	a.set_environment_db(-18.0)
	await _frames(2)
	_check("up again: sounding", not AudioServer.is_bus_mute(e))
	# The room's offset and mute (the common ambience_db setting).
	var rs: Node = main.features.room_settings
	rs.set_value("ambience_db", -6.0)
	a._rise = 0.0
	_check("the room 6 dB down: -24 dB (%.1f)" % a.bus_volume_db(), is_equal_approx(a.bus_volume_db(), -24.0))
	rs.set_value("ambience_db", -25.0)
	await _frames(2)
	_check("the room's setting at its bottom: this room muted", AudioServer.is_bus_mute(e))
	rs.set_value("ambience_db", 0.0)
	await _frames(2)
	# The pause rise: nothing plays, so the ambience is up by the room's rise (3 dB) after 2 s.
	await create_timer(2.3).timeout
	_check("paused or in the pre-show: up by 3 dB (%.1f, rising %s)" % [a.bus_volume_db(), a.rising],
			a.rising and absf(a.bus_volume_db() - (-15.0)) < 0.2)

	# The duck, measured: a 220 Hz tone at the reference level on Environment, a 1 kHz tone on Film.
	a.set_process(false)
	AudioServer.set_bus_volume_db(e, 0.0)
	AudioServer.set_bus_mute(e, false)
	var cap := AudioEffectCapture.new()
	cap.buffer_length = 0.5
	AudioServer.add_bus_effect(e, cap)
	var room_tone := _player(_tone(220.0, EnvSynth.REFERENCE_DB), &"Environment")
	room_tone.play()
	var silent := await _rms(cap, 1.0)
	var film := _player(_tone(1000.0, EnvSynth.REFERENCE_DB), &"Film")
	film.play()
	var ref := await _rms(cap, 1.0)
	film.volume_db = 14.0
	var loud := await _rms(cap, 1.0)
	film.stop()
	await create_timer(1.0).timeout
	var after := await _rms(cap, 1.0)
	print("  duck: room tone alone %.1f dBFS; film at the reference (-20 dBFS RMS) %.1f (%.1f dB down); loud film "
			% [silent, ref, silent - ref] + "(-6 dBFS RMS) %.1f (%.1f dB down); film stopped %.1f" % [loud,
			silent - loud, after])
	_check("no film: no duck (%.1f dBFS, the tone's own %.1f)" % [silent, EnvSynth.REFERENCE_DB],
			absf(silent - EnvSynth.REFERENCE_DB) < 1.5)
	_check("under the film at its reference: ducked 5 to 12 dB (%.1f)" % (silent - ref), silent - ref > 5.0
			and silent - ref < 12.0)
	_check("under a loud scene: more (%.1f)" % (silent - loud), silent - loud > silent - ref + 2.0)
	_check("the film stops: back up (%.1f)" % after, absf(after - silent) < 2.0)
	room_tone.queue_free()
	film.queue_free()
	for i in AudioServer.get_bus_effect_count(e):
		if AudioServer.get_bus_effect(e, i) == cap:
			AudioServer.remove_bus_effect(e, i)
			break
	a.set_process(true)

	# The level check: every room's sounds at the slider's default, under the target.
	for f in DirAccess.get_files_at("res://environments"):
		if not f.ends_with(".env.json"):
			continue
		var doc: Dictionary = EnvDoc.load_file("res://environments/" + f)["doc"]
		var streams: Array = []
		for c: Dictionary in doc.get("cues", []):
			for s: Dictionary in c.get("steps", []):
				if s.has("sound"):
					streams.append([EnvSynth.stream(str(s["sound"])), float(s.get("gain_db", 0.0))
							+ float(doc.get("audio", {}).get("level_db", 0.0))])
		if streams.is_empty():
			_check("%s: no sounds of its own (silence passes)" % f, true)
			continue
		var level: float = await EnvAudio.measure_level(self, streams, 1.5)
		print("  %s: its sounds at the default %.1f dBFS RMS (target %.1f)" % [f, level, EnvAudio.LEVEL_TARGET_DB])
		_check("%s: under the target with 2 dB to spare (%.1f)" % [f, level], level < EnvAudio.LEVEL_TARGET_DB - 2.0)
	var too_loud: float = await EnvAudio.measure_level(self, [[_tone(220.0, 0.0), 6.0]], 1.0)
	_check("the check catches a room too loud (%.1f)" % too_loud, too_loud > EnvAudio.LEVEL_TARGET_DB)
	_check("every synthesised sound made at the reference level", EnvSynth.NAMES.all(func(n: String) -> bool:
			return EnvSynth.rms_db(EnvSynth.stream(n)) <= EnvSynth.REFERENCE_DB + 0.5))
	main.queue_free()
	await _frames(2)
	print("test_env_audio: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _player(s: AudioStream, bus: StringName) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.bus = bus
	root.add_child(p)
	return p


## RMS (dBFS) of what reaches the capture over `seconds`, after a short settle.
func _rms(cap: AudioEffectCapture, seconds: float) -> float:
	await create_timer(0.4).timeout
	cap.clear_buffer()
	var sum := 0.0
	var n := 0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(seconds * 1000.0):
		await process_frame
		var k := cap.get_frames_available()
		if k > 0:
			for f: Vector2 in cap.get_buffer(k):
				sum += (f.x * f.x + f.y * f.y) * 0.5
				n += 1
	return linear_to_db(sqrt(sum / maxf(n, 1))) if n > 0 else -120.0


## A looping sine at this RMS level (dBFS).
func _tone(freq: float, rms_db: float) -> AudioStreamWAV:
	var rate := 44100
	var amp := db_to_linear(rms_db) * sqrt(2.0)
	var n := rate
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, clampi(int(sin(TAU * freq * i / rate) * amp * 32767.0), -32767, 32767))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = n
	return w


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)
