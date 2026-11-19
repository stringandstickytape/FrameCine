extends SceneTree

## Tests for the visualisers (docs/visualisers.md): the registry and its manifest checks
## (scripts/visualisers/visualiser_registry.gd), the shared analysis's maths and requests
## (scripts/play/audio_analysis.gd), the parameters through main.features, and with a renderer the host
## (scripts/visualisers/visualiser_host.gd): every visualiser of the app compiles and draws, the flash limit holds a
## strobing visualiser down and leaves a calm one alone, and its floor survives the two-byte round trip. Making them
## on the headset (scripts/visualisers/visualiser_service.gd): the README, the test signals' files, the commands and
## their assistant levels, and with a renderer the watcher, compile errors with their lines, the last good version
## kept, a broken manifest kept as before, refusing a shader that never compiled, a test signal played and captured.
## Test visualisers are written to user://test_visualisers_<pid> and deleted after.
## Run: godot --headless --xr-mode off --path app --script res://tests/test_visualisers.gd
## (the host's checks: without --headless, with xvfb and lavapipe; see docs/BUILD.md)

const Registry := preload("res://scripts/visualisers/visualiser_registry.gd")
const AudioAnalysis := preload("res://scripts/play/audio_analysis.gd")
const VisualiserHost := preload("res://scripts/visualisers/visualiser_host.gd")
const TestSignals := preload("res://scripts/visualisers/test_signals.gd")
const DevCommands := preload("res://scripts/dev/dev_commands.gd")
const MusicSource := preload("res://scripts/play/music_source.gd")
const W := preload("res://ui/pane_widgets.gd")
const BUILTIN: Array[String] = ["bars", "mirror", "line", "radial", "aurora", "halftone", "tiles", "runner", "sakura",
		"ink", "planet", "rose", "clockwork", "chrome", "circuit", "deep", "cymatics", "vinyl", "fireworks", "rain"]

var _failures := 0
var _checks := 0
var _tmp := "user://test_visualisers_%d" % OS.get_process_id()
var _main: Node3D


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_registry()
	_bad_manifests()
	_coerce()
	await _analysis()
	await _features()
	_signals()
	_commands()
	if DisplayServer.get_name() == "headless":
		print("SKIP the host's and the watcher's checks (need a renderer)")
	else:
		await _host()
		await _tinkering()
	_rmdir(_tmp)
	Registry.dirs = Registry.DIRS.duplicate()
	Registry.rescan()
	print("test_visualisers: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _registry() -> void:
	Registry.dirs = ["res://visualisers"]
	Registry.rescan()
	_check("the app's visualisers, in order (%s)" % [Registry.ids()], Registry.ids() == BUILTIN)
	_check("none of them has an error (%s)" % [Registry.errors()], Registry.errors().is_empty())
	var bars := Registry.entry("bars")
	_check("bars: a strip, four parameters, two presets", bars["area"] == "strip" and bars["params"].size() == 4
			and bars["presets"].size() == 2 and bool(bars["builtin"]))
	_check("bars: an int and a colour parameter read", bars["params"]["bars"]["default"] == 32
			and bars["params"]["colour_low"]["default"] is Color)
	_check("radial is tall, aurora a backdrop", Registry.entry("radial")["area"] == "tall"
			and Registry.entry("aurora")["area"] == "backdrop")
	for id in BUILTIN:
		var sh := Registry.load_shader(id)
		var uniforms := {}
		if sh != null:
			for u: Dictionary in sh.get_shader_uniform_list(true):
				uniforms[u["name"]] = true
		var missing: Array = Registry.entry(id)["params"].keys().filter(func(k: String) -> bool:
			return not uniforms.has(k))
		_check("%s: every parameter is a uniform, and it has the inputs (missing %s)" % [id, missing],
				sh != null and missing.is_empty() and uniforms.has("spectrum") and uniforms.has("vis_time"))


## Broken folders in a user folder: each is left out with a reason; the good one is in.
func _bad_manifests() -> void:
	DirAccess.make_dir_recursive_absolute(_tmp)
	var shader := "shader_type canvas_item;\nvoid fragment() { COLOR = vec4(1.0); }\n"
	_put("good_one", '{"name": "Good", "order": 5, "params": {"k": {"type": "float", "min": 0, "max": 1, '
			+ '"default": 2}}}', shader)
	_put("bad_json", '{"name": "Bad",\n "area": }', shader)
	_put("no_shader", '{"name": "No shader"}', "")
	_put("bad_area", '{"area": "ceiling"}', shader)
	_put("bad_type", '{"params": {"x": {"type": "vector", "default": 1}}}', shader)
	_put("bad_range", '{"params": {"x": {"type": "int", "min": 5, "max": 1, "default": 2}}}', shader)
	_put("bad_colour", '{"params": {"c": {"type": "colour", "default": "teal-ish"}}}', shader)
	_put("bad_preset", '{"params": {}, "presets": {"P": {"nope": 1}}}', shader)
	_put("Capital", '{}', shader)
	_put("bars", '{"name": "My bars"}', shader)
	Registry.dirs = ["res://visualisers", _tmp]
	Registry.rescan()
	var err := Registry.errors()
	print("  errors: %s" % [err])
	_check("a good user visualiser is in, first by its order", Registry.ids()[0] == "good_one"
			and not bool(Registry.entry("good_one")["builtin"]))
	_check("a default outside the range is clamped (2 -> 1)",
			Registry.entry("good_one")["params"]["k"]["default"] == 1.0)
	_check("bad JSON: left out, with the line", not Registry.has("bad_json")
			and str(err.get("bad_json")).contains("line "))
	for id in ["no_shader", "bad_area", "bad_type", "bad_range", "bad_colour", "bad_preset", "Capital"]:
		_check("%s: left out with a reason" % id, not Registry.has(id) and str(err.get(id, "")) != "")
	_check("a user folder may not take the app's id (bars stays the app's)", bool(Registry.entry("bars")["builtin"])
			and str(err.get("bars", "")).contains("new name"))
	var sh := Registry.load_shader("good_one")
	_check("a user's shader loads from its text", sh != null and sh.code.contains("COLOR = vec4(1.0)"))


func _put(id: String, manifest: String, shader: String) -> void:
	var dir := _tmp.path_join(id)
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join(Registry.MANIFEST), FileAccess.WRITE)
	f.store_string(manifest)
	f.close()
	if shader != "":
		f = FileAccess.open(dir.path_join(Registry.SHADER), FileAccess.WRITE)
		f.store_string(shader)
		f.close()


func _coerce() -> void:
	var fl := {"type": "float", "min": 0.0, "max": 2.0}
	var it := {"type": "int", "min": 8.0, "max": 128.0}
	_check("float: clamped", Registry.coerce(fl, 5) == 2.0 and Registry.coerce(fl, -1.0) == 0.0)
	_check("int: rounded and clamped", Registry.coerce(it, 31.6) == 32 and Registry.coerce(it, 1000) == 128)
	_check("colour: from #hex or a Color", Registry.coerce({"type": "colour"}, "#ff0000") == Color.RED
			and Registry.coerce({"type": "colour"}, Color.BLUE) == Color.BLUE)
	_check("wrong types: null", Registry.coerce(fl, "x") == null and Registry.coerce({"type": "bool"}, 1) == null
			and Registry.coerce({"type": "colour"}, "no") == null)


func _analysis() -> void:
	var a := AudioAnalysis.new()
	root.add_child(a)
	_check("in the tree: the shared one", AudioAnalysis.shared == a)
	# The maths, fed directly.
	a.feed(AudioAnalysis.snapshot(-6.0, -60.0, PackedFloat32Array()), 0.016)
	_check("-6 dBFS everywhere: every band full", is_equal_approx(a.fast[0], 1.0)
			and is_equal_approx(a.smooth[127], 1.0) and is_equal_approx(a.level, 1.0))
	a.feed(AudioAnalysis.snapshot(-60.0, -60.0, PackedFloat32Array()), 0.1)
	_check("silence: fast drops at once, smooth falls (%.2f)" % a.smooth[0], a.fast[0] == 0.0
			and is_equal_approx(a.smooth[0], 0.4) and is_equal_approx(a.bass, 0.4))
	var bins := PackedFloat32Array()
	bins.resize(AudioAnalysis.BINS)
	bins.fill(-60.0)
	bins[10] = -33.0
	a.feed(AudioAnalysis.snapshot(-60.0, -60.0, bins), 1.0)
	_check("one band: only that bin (%.2f)" % a.fast[10], is_equal_approx(a.fast[10], 0.5) and a.fast[11] == 0.0)
	# Beats.
	for i in 120:
		a.feed(AudioAnalysis.snapshot(-60.0, -50.0, PackedFloat32Array()), 1.0 / 60.0)
	var before: int = a.beats
	a.feed(AudioAnalysis.snapshot(-60.0, -20.0, PackedFloat32Array()), 1.0 / 60.0)
	_check("a jump in the bass: a beat", a.beats == before + 1 and a.beat == 1.0)
	a.feed(AudioAnalysis.snapshot(-60.0, -50.0, PackedFloat32Array()), 1.0 / 60.0)
	a.feed(AudioAnalysis.snapshot(-60.0, -10.0, PackedFloat32Array()), 1.0 / 60.0)
	_check("another within 0.25 s: not a beat", a.beats == before + 1)
	for i in 30:
		a.feed(AudioAnalysis.snapshot(-60.0, -50.0, PackedFloat32Array()), 1.0 / 60.0)
	_check("beat falls to 0 within 0.3 s (%.2f)" % a.beat, a.beat == 0.0)
	a.feed(AudioAnalysis.snapshot(-60.0, -45.0, PackedFloat32Array()), 1.0 / 60.0)
	_check("too quiet for a beat (under -40 dBFS)", a.beats == before + 1)
	# The textures carry the bands.
	a.feed(AudioAnalysis.snapshot(-33.0, -60.0, PackedFloat32Array()), 0.016)
	var img := a.spectrum_texture().get_image()
	_check("spectrum texture: %d x %d, r = the level now (%.2f)" % [img.get_width(), img.get_height(),
			img.get_pixel(5, 0).r], img.get_width() == 128 and img.get_height() == 1
			and absf(img.get_pixel(5, 0).r - 0.5) < 0.01)
	_check("waveform texture: 512 x 1", a.wave_texture().get_width() == 512)
	# Requests: the analyser on the bus while anyone holds it; the capture beside it for the waveform.
	var bus := AudioServer.get_bus_index(AudioAnalysis.bus_name())
	var n0 := AudioServer.get_bus_effect_count(bus)
	var one := RefCounted.new()
	var two := Node.new()
	a.request(one, true)
	_check("held: the analyser on the bus", a.active() and AudioServer.get_bus_effect_count(bus) == n0 + 1)
	a.request(two, true, true)
	_check("the waveform asked for: the capture too", AudioServer.get_bus_effect_count(bus) == n0 + 2)
	a.request(one, false)
	_check("one lets go: both stay for the other", a.active() and AudioServer.get_bus_effect_count(bus) == n0 + 2)
	two.free()
	a.request(one, false)
	_check("the other freed: all off the bus", not a.active() and AudioServer.get_bus_effect_count(bus) == n0)
	a.delay_override = -1.0
	_check("the delay: never negative, at most 0.5 s (%.3f)" % a.delay(), a.delay() >= 0.0 and a.delay() <= 0.5)
	a.queue_free()
	await process_frame
	_check("out of the tree: no shared one", AudioAnalysis.shared == null)


## The parameters through the real main scene's features.
func _features() -> void:
	Registry.dirs = ["res://visualisers"]
	Registry.rescan()
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	var main := _main
	main.settings.read_only = true
	root.add_child(main)
	await process_frame
	await process_frame
	var f: Node = main.features
	var list: Array[Dictionary] = f.visualisers()
	_check("features: every visualiser listed with its parameters", list.size() == BUILTIN.size()
			and list[0]["id"] == "bars" and list[0]["params"].size() == 4 and list[0]["presets"].has("Embers"))
	_check("set a parameter: clamped and kept", f.set_visualiser_param("bars", 500)
			and Registry.values("bars")["bars"] == 128 and main.settings.get_value("visualiser.bars", "bars", 0) == 128)
	_check("an unknown parameter or a wrong type: refused", not f.set_visualiser_param("nope", 1)
			and not f.set_visualiser_param("gap", "wide"))
	_check("a preset: its values over the defaults", f.apply_visualiser_preset("Embers")
			and Registry.values("bars")["bars"] == 32
			and Registry.values("bars")["colour_low"] == Color.html("#ff5a1f"))
	_check("an unknown preset: refused", not f.apply_visualiser_preset("Nope"))
	f.reset_visualiser_params()
	_check("reset: the defaults, nothing kept", Registry.values("bars")["colour_low"] == Color.html("#73b3ff")
			and not main.settings.has_value("visualiser.bars", "colour_low"))
	f.set_visualiser("aurora")
	_check("choose a visualiser by id", f.visualiser() == "aurora"
			and main.settings.get_value("music", "visualiser", "") == "aurora")
	f.set_visualiser("nope")
	_check("an unknown id: ignored", f.visualiser() == "aurora")
	f.set_visualiser("bars")
	# The main scene stays (its analysis is the shared one for the host's checks).


## The host on a card of its own, with a flashing test visualiser and the app's.
func _host() -> void:
	_put("strobe", '{"name": "Strobe", "area": "backdrop", "params": {"white": {"type": "float", "min": 0, "max": 1, ' \
			+ '"default": 0}}}', "shader_type canvas_item;\nuniform float white = 0.0;\n" \
			+ "void fragment() { COLOR = vec4(vec3(white), 1.0); }\n")
	_put("grey", '{"name": "Grey", "area": "backdrop"}',
			"shader_type canvas_item;\nvoid fragment() { COLOR = vec4(vec3(0.5), 1.0); }\n")
	Registry.dirs = ["res://visualisers", _tmp]
	Registry.rescan()
	# The main scene's analysis, idle (nothing holds it), so the levels fed here stay.
	var a: Node = AudioAnalysis.shared
	a.feed(AudioAnalysis.snapshot(-20.0, -60.0, PackedFloat32Array()), 0.016)
	var card := SubViewport.new()
	card.size = Vector2i(320, 180)
	card.disable_3d = true
	card.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(card)
	var out := TextureRect.new()
	out.size = Vector2(card.size)
	card.add_child(out)
	var host := VisualiserHost.new()
	host.budget_ms = 0.0
	card.add_child(host)
	host.setup(card, out)
	host.set_area(Vector2(card.size))
	# Each of the app's draws something (strong levels: -20 dBFS in every band).
	for id in BUILTIN:
		_check("%s: starts" % id, host.use(id))
		await _frames(4)
		await RenderingServer.frame_post_draw
		var img := host.picture().get_image()
		var lit := 0
		for y in range(0, img.get_height(), 4):
			for x in range(0, img.get_width(), 4):
				if img.get_pixel(x, y).a > 0.5:
					lit += 1
		_check("%s: draws (%d samples)" % [id, lit], lit > 10)
	# A calm picture: untouched, and the floor's two bytes give back its luminance.
	host.use("grey")
	await _frames(30)
	await RenderingServer.frame_post_draw
	var st := host.limit_texture().get_image().get_pixel(0, 0)
	var floor_now := st.r + st.g / 255.0
	_check("steady grey: gain 1 (%.3f), the floor its luminance (%.4f, want 0.214)" % [st.a, floor_now],
			st.a > 0.99 and absf(floor_now - 0.214) < 0.004)
	# A strobe: white and black on alternate frames for a second.
	host.use("strobe")
	await _frames(6)
	var lums: Array[float] = []
	for i in 60:
		Registry.overrides["strobe"] = {"white": float(i % 2)}
		await RenderingServer.frame_post_draw
		lums.append(_mean_lum(card.get_texture().get_image()))
	var swing := 0.0
	for i in range(1, lums.size()):
		swing = maxf(swing, absf(lums[i] - lums[i - 1]))
	print("  strobe: shown luminance %s" % [lums.slice(0, 12).map(func(v: float) -> String: return "%.3f" % v)])
	_check("a strobe: the shown picture swings at most %.2f a frame (%.3f)" % [VisualiserHost.MARGIN + 0.02, swing],
			swing <= VisualiserHost.MARGIN + 0.02)
	# Black, then white for good: it rises at most RISE a second over the margin.
	Registry.overrides["strobe"] = {"white": 0.0}
	await _frames(10)
	Registry.overrides["strobe"] = {"white": 1.0}
	var t0 := Time.get_ticks_msec()
	await _frames(30)
	await RenderingServer.frame_post_draw
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	var lum := _mean_lum(card.get_texture().get_image())
	var most := VisualiserHost.MARGIN + VisualiserHost.RISE * secs + 0.02
	_check("black to white: %.3f after %.2f s (at most %.3f)" % [lum, secs, most], lum <= most and lum > 0.05)
	# Starting a bright visualiser is one change: shown at once.
	host.use("grey")
	await _frames(3)
	await RenderingServer.frame_post_draw
	lum = _mean_lum(card.get_texture().get_image())
	_check("a new visualiser starts at its own brightness (%.3f)" % lum, absf(lum - 0.214) < 0.01)
	await _feedback(host)
	await _patterns(host, card)
	await _probe(host)
	# Off: nothing drawn or fed; on again: starts afresh.
	host.set_active(false)
	var counted := host.frames
	await _frames(3)
	_check("off: its viewports stop and it is not fed", host._vp.render_target_update_mode
			== SubViewport.UPDATE_DISABLED and host._limit_vp.render_target_update_mode == SubViewport.UPDATE_DISABLED
			and host.frames == counted)
	host.set_active(true)
	await _frames(2)
	_check("on again: drawn, counting from the start (%d)" % host.frames, host._vp.render_target_update_mode
			== SubViewport.UPDATE_ALWAYS and host.frames == 2)
	Registry.overrides.erase("strobe")
	card.queue_free()
	await process_frame


func _signals() -> void:
	var drums := TestSignals.make("drums", 0.5)
	_check("a test signal is a 16-bit mono WAV of the right length (%d bytes)" % drums.size(), drums.size()
			== 44 + 16000 * 2 and drums.slice(0, 4).get_string_from_ascii() == "RIFF"
			and drums.decode_u32(24) == TestSignals.RATE and drums.decode_u16(22) == 1)
	var peak := func(d: PackedByteArray) -> int:
		var most := 0
		for i in range(44, d.size(), 2):
			most = maxi(most, absi(d.decode_s16(i)))
		return most
	_check("drums and sweep have sound, silence has none", peak.call(drums) > 8000
			and peak.call(TestSignals.make("sweep", 0.5)) > 8000 and peak.call(TestSignals.make("silence", 0.5)) == 0)


func _commands() -> void:
	var levels := {}
	for c in ["visualisers", "visualiser_status", "visualiser_check", "visualiser_use", "visualiser_param",
			"visualiser_preset", "visualiser_reset", "visualiser_test", "visualiser_capture"]:
		levels[c] = DevCommands.assistant_level(c)
	print("  assistant levels: %s" % [levels])
	_check("the commands are open to the assistant (and so to the agents' tools)", levels["visualisers"] == "read"
			and levels["visualiser_check"] == "read" and levels["visualiser_capture"] == "read"
			and levels["visualiser_use"] == "settings" and levels["visualiser_param"] == "settings"
			and levels["visualiser_test"] == "control")
	var readme := FileAccess.get_file_as_string("user://visualisers/README.md")
	_check("the README is in the user folder with this machine's paths", readme.contains("visualiser_test")
			and not readme.contains("<<") and readme.contains(ProjectSettings.globalize_path("res://visualisers")))


## The tinkering loop on the main scene's own card: the watcher, compile errors, the last good version, a test signal.
func _tinkering() -> void:
	var svc: Node = _main.features.visualisers_service
	var f: Node = _main.features
	var dir := _tmp.path_join("live")
	DirAccess.make_dir_recursive_absolute(dir)
	svc.user_dir = _tmp
	Registry.dirs = ["res://visualisers", _tmp]
	svc.poll()
	var manifest := '{"name": "Live", "params": {"k": {"type": "float", "min": 0, "max": 1, "default": 0.5}}}'
	var good := "shader_type canvas_item;\n#include \"res://visualisers/visualiser.gdshaderinc\"\n" \
			+ "uniform float k = 0.5;\nvoid fragment() {\n\tCOLOR = vec4(vec3(k), band(UV.x));\n}\n"
	_write(dir.path_join(Registry.MANIFEST), manifest)
	_write(dir.path_join(Registry.SHADER), good)
	var changed: Array[String] = svc.poll()
	_check("the watcher sees a new visualiser (%s)" % [changed], changed.has("live") and Registry.has("live")
			and Registry.check("live")["ok"])
	var first: Shader = Registry.load_shader("live")
	# Line 5 now has the mistake (the include is line 2).
	_write(dir.path_join(Registry.SHADER), good.replace("band(UV.x));", "band(UV.x)) + nope;"))
	changed = svc.poll()
	var res: Dictionary = Registry.check("live")
	print("  broken: %s" % [res["errors"]])
	_check("a change seen; the compile error with its line in the file (5) and its words", changed.has("live")
			and not res["ok"] and int(res["errors"][0]["line"]) == 5
			and str(res["errors"][0]["message"]).contains("nope"))
	_check("the last shader that compiled is kept", Registry.load_shader("live") == first)
	_write(dir.path_join(Registry.MANIFEST), '{"name": "Live", "params": {')
	svc.poll()
	_check("a broken manifest: the last good one stays, marked, with the error", Registry.has("live")
			and bool(Registry.entry("live")["stale"]) and Registry.errors().has("live")
			and not Registry.check("live")["ok"])
	_write(dir.path_join(Registry.MANIFEST), manifest)
	_write(dir.path_join(Registry.SHADER), good)
	svc.poll()
	_check("fixed: usable again", Registry.check("live")["ok"] and not bool(Registry.entry("live")["stale"]))
	var never := _tmp.path_join("never")
	DirAccess.make_dir_recursive_absolute(never)
	_write(never.path_join(Registry.MANIFEST), '{"name": "Never"}')
	_write(never.path_join(Registry.SHADER), "shader_type canvas_item;\nvoid fragment() { COLOR = oops; }\n")
	svc.poll()
	var why: String = f.set_visualiser_checked("never")
	_check("choosing one that never compiled: refused with the error (%s)" % why, why.contains("line 2")
			and f.visualiser() != "never")
	# An include can only bring in a shader include file: not the project, not the settings.
	var peek := _tmp.path_join("peek")
	DirAccess.make_dir_recursive_absolute(peek)
	_write(peek.path_join(Registry.MANIFEST), '{"name": "Peek"}')
	_write(peek.path_join(Registry.SHADER), "shader_type canvas_item;\n#include \"res://project.godot\"\n"
			+ "void fragment() { COLOR = vec4(1.0); }\n")
	svc.poll()
	var peeked: Dictionary = Registry.check("peek")
	print("  include of a non-shader file: %s" % [peeked["errors"]])
	_check("an include of a file that is not a shader include is refused", not peeked["ok"])
	var r: Dictionary = await DevCommands.execute("visualiser_check", {"id": "never"})
	_check("visualiser_check through the registry gives the errors", r["ok"] and not r["result"]["ok"])
	if not MusicSource.available():
		print("SKIP the test signal on the card (needs the fork's MediaSource)")
		return
	var t0 := Time.get_ticks_msec()
	r = await DevCommands.execute("visualiser_test", {"signal": "drums"})
	print("  test signal: %s in %d ms" % [r.get("result", r.get("error")), Time.get_ticks_msec() - t0])
	await _frames(30)
	_check("visualiser_test plays the drums as music", r["ok"] and _main.player.source != null
			and _main.player.source.get_kind() == "music")
	# lavapipe draws on the CPU: its timings would scale the visualisers down here.
	var mh: Node = svc._host()
	mh.budget_ms = 0.0
	r = await DevCommands.execute("visualiser_use", {"id": "live"})
	await _frames(10)
	var st: Dictionary = svc.status()
	_check("visualiser_use shows a user's visualiser; status has its flash limit (%s)" % [st.get("running", {})],
			r["ok"] and st["showing"] == "live" and st.has("running")
			and (st["running"] as Dictionary).has("flash_limit"))
	# A change to the one showing starts it again with the new files.
	var frames_before: int = svc._host().frames
	_write(dir.path_join(Registry.SHADER), good.replace("vec3(k)", "vec3(k, 0.2, 1.0 - k)"))
	svc.poll()
	await _frames(2)
	_check("an edit to the one showing starts it again (%d -> %d frames)" % [frames_before, svc._host().frames],
			svc._host().frames < frames_before)
	r = await DevCommands.execute("visualiser_capture", {})
	var card := Image.load_from_file(str(r["result"]["card"])) if r["ok"] else null
	_check("visualiser_capture saves the card (%s)" % [r.get("result", r.get("error"))], card != null
			and card.get_width() == 1280 and r["result"]["alone"] != null)
	# The app's own on the drums: how much they flicker, against the limit. None may be dimmed.
	_main.player.seek(0.0)
	var figures := {}
	var clean := true
	for vid in BUILTIN:
		f.set_visualiser(vid)
		await _frames(20)
		var most := 0.0
		var dimmed := 0
		for i in 12:
			await _frames(8)
			var lim: Dictionary = mh.limit_state()
			most = maxf(most, lim["flicker"])
			dimmed += 1 if lim["dimming"] else 0
		figures[vid] = "flicker %.4f at most, dimmed %d/12" % [most, dimmed]
		clean = clean and dimmed == 0
	print("  on the drums: %s" % [figures])
	_check("the app's own visualisers on the drums are never dimmed (limit %.3f)" % VisualiserHost.FLICKER_MAX, clean)
	await _picture_tab()
	f.set_visualiser("bars")
	_main.open_path("stub://flat_mono")
	await _frames(3)
	_main.ui.ui.picture.sync()
	_check("a film: no Visualisations in Picture", not _main.ui.ui.picture._vis_box.visible)
	svc.user_dir = svc.USER_DIR


func _write(path: String, text: String) -> void:
	var fa := FileAccess.open(path, FileAccess.WRITE)
	fa.store_string(text)
	fa.close()


## The Picture tab's Visualisations: shown with the music card, its controls built from the manifest and working.
func _picture_tab() -> void:
	var f: Node = _main.features
	var pic: Node = _main.ui.ui.picture
	f.set_visualiser("bars")
	f.reset_visualiser_params("bars")
	pic.sync()
	var rows: Dictionary = pic._vis_rows
	_check("Visualisations shows with the music card, first in Picture", pic._vis_box.visible
			and pic.box.get_child(0) == pic._vis_box)
	var choice: Container = rows["_choice"]
	_check("a choice for each visualiser and Off (%d)" % choice.get_child_count(),
			choice.get_child_count() == Registry.ids().size() + 1)
	_check("bars' four parameters as controls", rows.has("bars") and rows.has("gap") and rows.has("colour_low")
			and rows.has("colour_high"))
	W.slider_of(rows["bars"]).value = 64.0
	_check("the Bars slider sets the parameter (%s)" % Registry.values("bars")["bars"], Registry.values("bars")["bars"]
			== 64)
	var swatch: Button = (rows["colour_low"] as Container).get_child(2)
	swatch.pressed.emit()
	_check("a colour swatch sets the colour", Registry.values("bars")["colour_low"] == Color.html(pic.VIS_COLOURS[0]))
	var embers: Button = _button_in(pic._vis_body, "Embers")
	embers.pressed.emit()
	_check("a preset's button applies it", Registry.values("bars")["colour_low"] == Color.html("#ff5a1f")
			and Registry.values("bars")["bars"] == 32)
	_button_in(pic._vis_body, "Defaults").pressed.emit()
	_check("Defaults", Registry.values("bars")["colour_low"] == Color.html("#73b3ff"))
	(choice.get_child(Registry.ids().find("aurora")) as Button).pressed.emit()
	_check("choosing Aurora: its controls (a switch among them)", f.visualiser() == "aurora"
			and pic._vis_rows.has("use_cover") and pic._vis_rows["use_cover"] is Button
			and not pic._vis_rows.has("gap"))
	(pic._vis_rows["_choice"] as Container).get_child(Registry.ids().size()).pressed.emit()
	_check("Off: no controls", f.visualiser() == "off" and pic._vis_rows.size() == 1)
	f.set_visualiser_param("speed", 1.5, "aurora")
	f.set_visualiser("aurora")
	_check("a change from elsewhere shows on the slider", is_equal_approx(W.slider_of(pic._vis_rows["speed"]).value,
			1.5))
	f.reset_visualiser_params("aurora")


static func _button_in(n: Node, text: String) -> Button:
	for c in n.find_children("*", "Button", true, false):
		if (c as Button).text == text:
			return c
	return null


## Patterns that swap with a steady average: the area rule dims them; half the card swapping dims only that half.
func _patterns(host: Node, card: SubViewport) -> void:
	var swap := "shader_type canvas_item;\nuniform float white = 0.0;\nuniform bool half_only = false;\n" \
			+ "void fragment() {\n\tfloat c = mod(floor(UV.x * 32.0) + floor(UV.y * 18.0) + white, 2.0);\n" \
			+ "\tif (half_only && UV.x > 0.5) { c = 0.5; }\n\tCOLOR = vec4(vec3(c), 1.0);\n}\n"
	_put("checker", '{"name": "Checker", "area": "backdrop", "params": {"white": {"type": "float", "min": 0, ' \
			+ '"max": 1, "default": 0}, "half_only": {"type": "bool", "default": false}}}', swap)
	Registry.rescan()
	for half in [false, true]:
		Registry.overrides["checker"] = {"white": 0.0, "half_only": half}
		host.use("checker")
		await _frames(6)
		var prev := card.get_texture().get_image()
		var raw_prev: Image = host.picture().get_image()
		var shown := 0.0
		var raw := 0.0
		var right := 0.0
		var n := 0
		for i in 60:
			# A swap every third frame: 10 to 20 a second at lavapipe's rates.
			Registry.overrides["checker"] = {"white": float((i / 3) % 2), "half_only": half}
			await RenderingServer.frame_post_draw
			var img := card.get_texture().get_image()
			var raw_img: Image = host.picture().get_image()
			if i >= 30:
				shown += _mean_change(prev, img, 0.0, 0.5 if half else 1.0)
				raw += _mean_change(raw_prev, raw_img, 0.0, 0.5 if half else 1.0)
				if half:
					right += _mean_lum_part(img, 0.6, 1.0)
				n += 1
			prev = img
			raw_prev = raw_img
		shown /= n
		raw /= n
		var lim: Dictionary = host.limit_state()
		print("  checker%s: picture changes %.3f a frame, shown %.4f; %s" % [" (left half)" if half else "", raw,
				shown, lim])
		if not half:
			_check("a swapping checkerboard (steady average) is dimmed: %.4f a frame shown against %.3f" % [shown, raw],
					raw > 0.2 and shown < 0.02 and lim["gain"] > 0.99)
		else:
			right /= n
			_check("half the card swapping: that half dimmed (%.4f), the other half untouched (%.3f, want 0.214)"
					% [shown, right], shown < 0.04 and absf(right - 0.214) < 0.02)
	Registry.overrides.erase("checker")


## The clocks and "feedback": a visualiser that adds a step to its own last frame each frame grows; one without it
## keeps no copy; paused, the clocks and the picture stand still.
func _feedback(host: Node) -> void:
	_put("accum", '{"name": "Accumulate", "area": "backdrop", "feedback": true}',
			"shader_type canvas_item;\n#include \"res://visualisers/visualiser.gdshaderinc\"\n"
			+ "void fragment() {\n\tfloat v = fresh > 0.5 ? 0.0 : texture(previous, UV).r + (vis_dt > 0.0 ? 3.0 / 255.0 : 0.0);\n"
			+ "\tCOLOR = vec4(vec3(v), 1.0);\n}\n")
	_put("bad_feedback", '{"feedback": "yes"}', "shader_type canvas_item;\nvoid fragment() { COLOR = vec4(1.0); }\n")
	Registry.rescan()
	_check("feedback in the manifest: read; not true or false: left out", bool(Registry.entry("accum")["feedback"])
			and not bool(Registry.entry("grey")["feedback"]) and not Registry.has("bad_feedback"))
	_check("without feedback no copy is drawn", host.id == "grey" and not host.feedback())
	host.use("accum")
	await _frames(4)
	await RenderingServer.frame_post_draw
	var v0: float = host.picture().get_image().get_pixel(10, 10).r
	await _frames(20)
	await RenderingServer.frame_post_draw
	var v1: float = host.picture().get_image().get_pixel(10, 10).r
	_check("feedback: previous is its own last frame (%.3f -> %.3f over 20 frames)" % [v0, v1], host.feedback()
			and v1 - v0 > 15.0 * 3.0 / 255.0 and v1 - v0 < 25.0 * 3.0 / 255.0)
	_check("drive runs faster than its rest with sound (%.2f in %.2f s)" % [host.drive, host.vis_time],
			host.drive > host.vis_time * VisualiserHost.DRIVE_REST * 1.2)
	host.playing = false
	var d0: float = host.drive
	await _frames(10)
	await RenderingServer.frame_post_draw
	var v2: float = host.picture().get_image().get_pixel(10, 10).r
	await _frames(10)
	await RenderingServer.frame_post_draw
	var v3: float = host.picture().get_image().get_pixel(10, 10).r
	_check("paused: drive stands, and so does a feedback picture (%.3f, %.3f)" % [v2, v3], host.drive == d0
			and is_equal_approx(v2, v3))
	host.playing = true
	host.use("grey")
	await _frames(2)


## The first frames' timing: within budget at full size, over it scaled down, far over it refused.
func _probe(host: Node) -> void:
	host.budget_ms = VisualiserHost.BUDGET_MS
	var refusals: Array = []
	host.refused.connect(func(rid: String, why: String) -> void: refusals.append([rid, why]))
	var trial := func(vid: String, ms: float) -> void:
		host.probe_ms_override = ms
		host.use(vid)
		for i in VisualiserHost.PROBE_FRAMES + 2:
			await process_frame
	# The test card is 320 x 180; the probe draws 256 x 144, so the full size costs 1.5625 times the probe's.
	await trial.call("grey", 0.05)
	_check("cheap: full size (scale %.2f)" % host.scale, host.id == "grey" and host.scale == 1.0 and not host.probing())
	await trial.call("bars", 2.0)
	_check("about 3.1 ms at full size: 75 %% (scale %.2f)" % host.scale, host.id == "bars" and host.scale == 0.75)
	await trial.call("strobe", 40.0)
	print("  refused: %s" % [host.last_refusal])
	_check("about 62 ms: refused, the one before back, and why", host.id == "bars" and host.scale == 0.75
			and refusals.size() == 1 and refusals[0][0] == "strobe" and str(host.last_refusal["why"]).contains("ms"))
	host.probe_ms_override = -1.0
	host.budget_ms = 0.0


## The mean change of relative luminance per pixel between two pictures, over a band of x (0..1).
static func _mean_change(a: Image, b: Image, x0: float, x1: float) -> float:
	var sum := 0.0
	var n := 0
	for y in range(0, a.get_height(), 4):
		for x in range(int(a.get_width() * x0), int(a.get_width() * x1), 4):
			sum += absf(_lum(a.get_pixel(x, y)) - _lum(b.get_pixel(x, y)))
			n += 1
	return sum / maxi(n, 1)


static func _mean_lum_part(img: Image, x0: float, x1: float) -> float:
	var sum := 0.0
	var n := 0
	for y in range(0, img.get_height(), 4):
		for x in range(int(img.get_width() * x0), int(img.get_width() * x1), 4):
			sum += _lum(img.get_pixel(x, y))
			n += 1
	return sum / maxi(n, 1)


static func _lum(c: Color) -> float:
	var l := c.srgb_to_linear()
	return 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b


## Mean relative luminance of an image (linear light).
static func _mean_lum(img: Image) -> float:
	var sum := 0.0
	var n := 0
	for y in range(0, img.get_height(), 3):
		for x in range(0, img.get_width(), 3):
			var c := img.get_pixel(x, y).srgb_to_linear()
			sum += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			n += 1
	return sum / n


func _rmdir(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for sub in d.get_directories():
		_rmdir(path.path_join(sub))
	for file in d.get_files():
		d.remove(file)
	DirAccess.remove_absolute(path)


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
