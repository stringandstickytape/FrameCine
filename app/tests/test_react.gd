extends SceneTree

## Tests for scripts/env/film_react.gd (ideas #81) in the real main scene: the analyzer added and removed with the
## setting, bass pulses (threshold, scale, rate, the haptics setting), flashes only in rooms that opt in (the jump over
## the running average, the fade back, the cooldown), and a real 50 Hz tone read as bass through the analyzer.
## Settings are read-only. Run: godot --xr-mode off --path app --script res://tests/test_react.gd

const FilmReact := preload("res://scripts/env/film_react.gd")

var _failures := 0
var _checks := 0
var main: Node3D


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	_run.call_deferred()


func _effects() -> int:
	return AudioServer.get_bus_effect_count(AudioServer.get_bus_index("Master"))


func _run() -> void:
	await _frames(5)
	var r: Node = main.features.react
	var before := _effects()
	_check("off by default, no analyzer", not r.enabled and r._analyzer == null)
	r.set_enabled(true)
	_check("on: an analyzer on Master", _effects() == before + 1 and r._analyzer != null)
	main.open_path("stub://flat_mono")
	await _frames(3)

	# Bass pulses.
	var amps: Array = []
	r.pulsed.connect(func(a: float) -> void: amps.append(a))
	r._since_pulse = 1.0
	r.feed(-40.0, -60.0, 0.016)
	_check("quiet bass: no pulse", amps.is_empty())
	r.feed(-15.0, -60.0, 0.016)
	var want: float = 0.75 * FilmReact.MAX_PULSE * 0.5
	_check("bass at -15 dB: a pulse of %.3f (%s)" % [want, amps], amps.size() == 1 and is_equal_approx(amps[0], want))
	r.feed(-15.0, -60.0, 0.05)
	_check("at most 8 a second", amps.size() == 1)
	r.feed(-15.0, -60.0, 0.1)
	_check("the next after 1/8 s", amps.size() == 2)
	main.features.haptics.enabled = false
	r.feed(-15.0, -60.0, 0.2)
	_check("haptics off: no pulse", amps.size() == 2)
	main.features.haptics.enabled = true

	# Flashes: only where the room opts in.
	var rl: Node = main.features.room_light
	main.set_environment("void")
	await _frames(2)
	for i in 300:
		r.feed(-60.0, -40.0, 0.016)
	r.feed(-60.0, -8.0, 0.016)
	_check("the void does not opt in: no flash", r.flashes == 0)
	main.set_environment("drive_in")
	await _frames(2)
	_check("the drive-in opts in", r.room_opts_in())
	for i in 300:
		r.feed(-60.0, -40.0, 0.016)
	r.feed(-60.0, -30.0, 0.016)
	_check("a small rise: no flash", r.flashes == 0)
	r.feed(-60.0, -8.0, 0.016)
	_check("a loud jump: a flash (factor %.2f)" % rl.get_factor(FilmReact.FACTOR), r.flashes == 1
			and rl.get_factor(FilmReact.FACTOR) > 1.5)
	r.feed(-60.0, -40.0, 0.016)
	r.feed(-60.0, -6.0, 0.016)
	_check("cooldown: no second flash at once", r.flashes == 1)
	await create_timer(0.6).timeout
	_check("faded back (%.2f)" % rl.get_factor(FilmReact.FACTOR), is_equal_approx(rl.get_factor(FilmReact.FACTOR), 1.0))

	# A real tone through the analyzer.
	if DisplayServer.get_name() != "headless":
		var p := AudioStreamPlayer.new()
		p.stream = _sine(50.0, 0.5)
		root.add_child(p)
		p.play()
		await create_timer(0.6).timeout
		var bass: float = FilmReact._db(r._analyzer.get_magnitude_for_frequency_range(20.0, 120.0))
		var broad: float = FilmReact._db(r._analyzer.get_magnitude_for_frequency_range(120.0, 8000.0))
		_check("a 50 Hz tone reads as bass (%.1f dB, broadband %.1f dB)" % [bass, broad], bass > -30.0
				and bass > broad + 15.0)
		p.queue_free()
	else:
		print("SKIP the real tone (headless)")

	r.set_enabled(false)
	_check("off: the analyzer removed", _effects() == before and r._analyzer == null)
	print("test_react: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _sine(f: float, amp: float) -> AudioStreamWAV:
	var rate := 44100
	var data := PackedByteArray()
	data.resize(rate * 2)
	for i in rate:
		data.encode_s16(i * 2, int(amp * 32767.0 * sin(TAU * f * i / rate)))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = rate
	return w


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL ", what)
	else:
		print("PASS ", what)
