extends SceneTree

## Film signals and bindings (docs/environments.md, "Bindings and film signals") with fake film input: a parameter
## follows film.brightness through a range, film.bass smoothed, playback.state by map, film.minutes by keys (a
## film-time track), film.colour on a colour, a setting by range; the bass, transient and quiet maths from fed levels;
## the colour read back from a viewport's bytes; and, in the real main scene, film_react's analyser on the Film bus
## for the signals with [react] off.
## godot --headless --xr-mode off --path app --script res://tests/test_env_signals.gd

const EnvRoom := preload("res://scripts/env/env_room.gd")
const EnvSignals := preload("res://scripts/env/env_signals.gd")
const FilmReact := preload("res://scripts/env/film_react.gd")

var _failures := 0
var _checks := 0


func _init() -> void:
	_run.call_deferred()


func _room(doc: Dictionary) -> Node3D:
	var r: Node3D = EnvRoom.new()
	r.doc = doc
	root.add_child(r)
	r.host.auto = false
	return r


func _run() -> void:
	var doc := {"schema": 4, "name": "Signals",
		"settings": [{"name": "glow", "type": "range", "min": 0.0, "max": 2.0, "default": 1.0, "label": "Glow",
				"description": "How much it glows."}],
		"systems": [
			{"system": "light", "params": {
				"house_lamps": {"bind": "film.brightness", "range": [0.2, 1.0]},
				"step_lights": {"bind": "film.bass", "smooth": 1.0},
				"signs": {"bind": "playback.state", "map": {"playing": 0.1, "paused": 0.8}},
				"accent": {"bind": "setting.glow", "range": [0.0, 2.0]}}},
			{"system": "mirror_floor", "params": {"ring_colour": {"bind": "film.colour", "strength": 0.5,
					"base": "#ffffff"}}}],
		"timeline": {"tracks": [{"target": "light.dimmed_level", "by": "film.minutes", "keys": [[0, 0.0], [10, 1.0]]}]}}
	var v: Dictionary = preload("res://scripts/env/env_doc.gd").validate(doc)
	_check("the test document is valid (%s)" % [v["errors"]], v["ok"])
	var room := _room(doc)
	var h: Node = room.host
	var sig: EnvSignals = h.signals
	h.snapshot_override = {"open": true, "playing": true, "position": 300.0, "duration": 6000.0}
	sig.fake("film.colour", Color.WHITE)
	h.step(0.016)
	_check("brightness 1: the lamps at the range's top (%.2f)" % h.param("light.house_lamps"),
			is_equal_approx(float(h.param("light.house_lamps")), 1.0))
	sig.fake("film.colour", Color.BLACK)
	h.step(0.016)
	_check("brightness 0: at its bottom (%.2f)" % h.param("light.house_lamps"),
			is_equal_approx(float(h.param("light.house_lamps")), 0.2))
	sig.fake("film.colour", Color(1.0, 0.0, 0.0))
	h.step(0.016)
	var ring: Color = h.param("mirror_floor.ring_colour")
	_check("film.colour on a colour, half way from white (%s)" % ring, ring.is_equal_approx(Color(1.0, 0.5, 0.5)))
	sig.fake("film.bass", 1.0)
	h.step(0.1)
	var b1 := float(h.param("light.step_lights"))
	for i in 100:
		h.step(0.1)
	var b2 := float(h.param("light.step_lights"))
	_check("film.bass smoothed over 1 s: %.3f after 0.1 s, %.3f after 10 s" % [b1, b2], b1 > 0.05 and b1 < 0.15
			and b2 > 0.99)
	h.step(0.016)
	_check("playback.state mapped: playing (%s, %.2f)" % [h.timeline.state, h.param("light.signs")],
			h.timeline.state == "playing" and is_equal_approx(float(h.param("light.signs")), 0.1))
	h.snapshot_override = {"open": true, "playing": false, "position": 300.0, "duration": 6000.0}
	h.step(0.016)
	_check("paused (%s, %.2f)" % [h.timeline.state, h.param("light.signs")], h.timeline.state == "paused"
			and is_equal_approx(float(h.param("light.signs")), 0.8))
	sig.fake("film.minutes", 5.0)
	h.step(0.016)
	_check("a film-time track: 5 minutes, half way (%.2f)" % h.param("light.dimmed_level"),
			is_equal_approx(float(h.param("light.dimmed_level")), 0.5))
	sig.fake("film.minutes", 30.0)
	h.step(0.016)
	_check("past its last key: held there (%.2f)" % h.param("light.dimmed_level"),
			is_equal_approx(float(h.param("light.dimmed_level")), 1.0))
	h.set_setting("glow", 0.5)
	_check("a setting by range: 0.5 of 0..2 to 0..2 (%.2f)" % h.param("light.accent"),
			is_equal_approx(float(h.param("light.accent")), 0.5))
	room.queue_free()

	# The bass, the transient and quiet from levels, as film_react's analyser gives them.
	var s := EnvSignals.new()
	s.fake("playback.playing", 1.0)
	s.fake_audio(-10.0, -60.0)
	s.update(null, 0.016, {"film.bass": true})
	_check("bass at full: 1 (%.2f)" % s.value("film.bass"), is_equal_approx(float(s.value("film.bass")), 1.0))
	s.fake_audio(-20.0, -60.0)
	s.update(null, 0.016, {"film.bass": true})
	_check("bass half way between floor and full (%.2f)" % s.value("film.bass"),
			is_equal_approx(float(s.value("film.bass")), 0.5))
	for i in 200:
		s.fake_audio(-60.0, -50.0)
		s.update(null, 0.016, {"film.transient": true})
	s.fake_audio(-60.0, -8.0)
	s.update(null, 0.016, {"film.transient": true})
	_check("a loud jump: film.transient 1 (%.2f)" % s.value("film.transient"),
			float(s.value("film.transient")) > 0.95)
	for i in 40:
		s.fake_audio(-60.0, -50.0)
		s.update(null, 0.016, {"film.transient": true})
	_check("it falls to 0 in half a second (%.2f)" % s.value("film.transient"), float(s.value("film.transient")) < 0.01)
	var q := EnvSignals.new()
	q.fake("playback.playing", 1.0)
	var t := 0.0
	var rose_at := -1.0
	while t < 8.0:
		q.fake_audio(-80.0, -70.0)
		q.update(null, 0.05, {"film.quiet": true})
		t += 0.05
		if rose_at < 0.0 and float(q.value("film.quiet")) > 0.99:
			rose_at = t
	_check("quiet: held for 3 s, then 1 (at %.2f s)" % rose_at, rose_at > 3.0 and rose_at < 5.5)
	q.fake_audio(-20.0, -10.0)
	for i in 3:
		q.update(null, 0.05, {"film.quiet": true})
	_check("a loud moment: quiet falls at once (%.2f)" % q.value("film.quiet"), float(q.value("film.quiet")) == 0.0)
	var bytes := PackedByteArray()
	for i in 8:
		bytes.append_array(PackedByteArray([255, 0, 0, 255]) if i < 4 else PackedByteArray([0, 0, 255, 255]))
	var mean: Variant = EnvSignals.mean_colour(bytes, RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM)
	_check("the read-back colour: the mean of the cells (%s)" % [mean], mean is Color
			and (mean as Color).is_equal_approx(Color(0.5, 0.0, 0.5)))
	_check("an unknown format: no colour", EnvSignals.mean_colour(bytes, RenderingDevice.DATA_FORMAT_R8_UNORM) == null)

	# film_react's analysis for the signals, with [react] off, on the Film bus.
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.settings.read_only = true
	root.add_child(main)
	await process_frame
	await process_frame
	var react: Node = main.features.react
	var film := AudioServer.get_bus_index("Film")
	var before := AudioServer.get_bus_effect_count(film)
	_check("[react] off, nothing asked: no analyser", not react.enabled and react._analyzer == null)
	var who := RefCounted.new()
	react.request_analysis(who, true)
	_check("asked for by a room's signals: an analyser on the Film bus, no pulses",
			react._analyzer != null and AudioServer.get_bus_effect_count(film) == before + 1 and react.pulses == 0)
	_check("levels() gives [bass_db, broad_db]", (react.levels() as Array).size() == 2)
	react.request_analysis(who, false)
	_check("let go: the analyser off again", react._analyzer == null and AudioServer.get_bus_effect_count(film) == before)
	main.queue_free()
	await process_frame
	print("test_env_signals: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)
