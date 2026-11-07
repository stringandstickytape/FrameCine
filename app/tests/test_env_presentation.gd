extends SceneTree

## The presentation system (docs/environments.md, "The presentation system"): its spec and presets (every preset's
## values valid, pastiche names only); a small test room over the Void's floor passes the checks; in the real main
## scene the screen's flat mesh draws the film with the presentation's material while a picture stage is on, the
## film layer steps aside (and comes back without one), the screen's uniforms follow; a preset fills what the
## document leaves out and the document wins; the Motion and Flickering lights settings hold; the flicker stays under
## the photosensitivity ceiling; a glitch comes and goes; the window speaker filters the film's sound on a bus of its
## own (the low end gone, the middle kept) and goes when the room does. Switching: a tube collapses to a line and a
## small dot that fades, a valve set warms up from dark, a CRT opens out from a dot, a panel just goes black and comes
## up, a channel change dips and comes back; never a flicker (one rise and one fall at most, each fade no faster than
## the comfort ceiling's), the dot small, the sounds at their designed levels; a set that starts off comes on when the
## film plays. With a renderer (lavapipe): with every stage off the picture is the screen's own, pixel for pixel; each
## preset draws and changes it as it should; the set's window and the film in it (letterbox, pan and scan, 14:9,
## stretch, a pillarbox, the mirror's flip, the bezel showing outside the window); the dot, the line and the dark
## face; an OLED's true black against a backlit panel; a rear projection's fringes and its light falling off from
## above more than from the side; and the cost per frame against the screen's own shader. Pictures in
## user://env_presentation/.
## godot --headless --xr-mode off --path app --script res://tests/test_env_presentation.gd
## VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a godot --xr-mode off --path app --script
## res://tests/test_env_presentation.gd   (adds the render checks and the cost)

const Presentation := preload("res://scripts/env/systems/presentation.gd")
const Registry := preload("res://scripts/env/systems/registry.gd")
const EnvDoc := preload("res://scripts/env/env_doc.gd")
const EnvChecks := preload("res://scripts/env/env_checks.gd")
const EnvRoom := preload("res://scripts/env/env_room.gd")
const EnvAudio := preload("res://scripts/env/env_audio.gd")
const RoomSchema := preload("res://scripts/assistant/room_schema.gd")
const VIDEO_SHADER := preload("res://shaders/video.gdshader")
const EnvSynth := preload("res://scripts/env/env_synth.gd")
const SoundBed := preload("res://scripts/env/systems/sound_bed.gd")
const Acoustics := preload("res://scripts/env/systems/acoustics.gd")
const OUT := "user://env_presentation"

const DOC := {"schema": 4, "name": "Presentation test",
	"screen": {"center": [0, 1.4, -3.0], "size": [1.6, 0.9]},
	"systems": [{"system": "mirror_floor", "params": {"reflect": false}},
		{"system": "presentation", "params": {"preset": "rewinder_1987", "mask": "grille",
			"speaker": {"bind": "setting.tinny", "map": {"true": "window", "false": "none"}},
			"weave": {"bind": "setting.weave", "range": [0.0, 1.0]}}}],
	"settings": [
		{"name": "tinny", "type": "bool", "default": false, "label": "Tinny speaker",
			"description": "The film's sound through the window speaker."},
		{"name": "weave", "type": "range", "min": 0.0, "max": 1.0, "step": 0.1, "default": 0.5, "format": "percent",
			"label": "Weave", "description": "Gate weave."}]}

var _failures := 0
var _checks := 0
var main: Node3D


func _init() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	_spec()
	await _room_checks()
	await _in_main()
	await _switching()
	await _era_dots()
	if DisplayServer.get_name() != "headless":
		await _render()
	else:
		print("  (headless: the render checks and the cost need a renderer)")
	print("test_env_presentation: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


# --- The spec and the presets ---------------------------------------------------------------------------------------

func _spec() -> void:
	_check("registered, a screen system", Registry.has("presentation")
			and Registry.spec("presentation")["kind"] == "screen")
	var ps: Dictionary = Registry.spec("presentation")["params"]
	var bad := []
	for k: String in Presentation.PRESETS:
		var p: Dictionary = Presentation.PRESETS[k]
		_check("%s: an id and a title" % k, RoomSchema.id_ok(k) and str(p.get("title", "")).length() > 3)
		for param: String in p["params"]:
			var errs: Array = []
			if not ps.has(param):
				bad.append("%s.%s: no such parameter" % [k, param])
				continue
			EnvDoc.check_value(ps[param], p["params"][param], "%s.%s" % [k, param], errs, {"no_bind": true})
			bad.append_array(errs)
	_check("every preset's values are parameters and valid %s" % [bad], bad.is_empty())
	_check("the presets are choices of preset", (ps["preset"]["values"] as Array).size()
			== Presentation.PRESETS.size() + 1)
	_check("the TV eras: 1930 to 2005, and the two cinema screens", Presentation.PRESETS.has("glowbox_1930")
			and Presentation.PRESETS.has("sirclive_1983") and Presentation.PRESETS.has("freedtv_2005")
			and Presentation.PRESETS.has("worn_print") and Presentation.PRESETS.has("starlight_lot_1958"))
	# Pastiche only: the spec's every text (the presets' names and descriptions in it) through the names check.
	var marks := EnvChecks.names(Registry.spec("presentation"))
	_check("no real mark in the spec or the presets %s" % [marks], marks.is_empty())
	_check("the names check catches a real mark", not EnvChecks.names({"t": "a %s tube" % EnvChecks.MARKS[0]})
			.is_empty())
	_check("speakers: none and four", (ps["speaker"]["values"] as Array) == ["none", "window", "telly", "cabinet",
			"panel"])
	_check("weave, tilt and tracking are motion; flicker flickers and is a brightness", ps["weave"].has("motion")
			and ps["tilt"].has("motion") and ps["tracking"].has("motion") and bool(ps["flicker"]["flicker"])
			and bool(ps["flicker"]["brightness"]))
	_check("the eras' presets: 1937, 1966, 2002 and the present", Presentation.PRESETS.has("mirrorlid_1937")
			and Presentation.PRESETS.has("rental_1966") and Presentation.PRESETS.has("projection_2002")
			and Presentation.PRESETS.has("slimline_present"))
	_check("displays: a rear projection and an OLED", "rear_projection" in ps["display"]["values"]
			and "oled" in ps["display"]["values"])
	_check("aspect modes: letterbox, pan and scan, 14:9, stretch", ps["aspect_mode"]["values"] == ["letterbox",
			"pan_and_scan", "fourteen_nine", "stretch"] and ps["aspect_mode"]["default"] == "letterbox")
	_check("off_axis 0 and mirror off by default", is_zero_approx(float(ps["off_axis"]["default"]))
			and ps["mirror"]["default"] == false)
	var actions: Dictionary = Registry.spec("presentation")["actions"]
	_check("actions: switch_on, switch_off, channel", actions.has("switch_on") and actions.has("switch_off")
			and actions.has("channel"))
	_check("the switch sounds are the synthesiser's and sound beds'", Presentation.SWITCH_SOUNDS.all(
			func(n: String) -> bool: return n in EnvSynth.NAMES and n in SoundBed.SOUNDS and SoundBed.LEVELS.has(n)))


# --- The test room through the checks -----------------------------------------------------------------------------

func _room_checks() -> void:
	var doc: Dictionary = DOC.duplicate(true)
	var s := EnvChecks.static_checks(doc)
	for k: String in s:
		_check("test room: %s %s" % [k, s[k]], (s[k] as Array).is_empty())
	var room: Node3D = EnvRoom.new()
	room.doc = doc
	root.add_child(room)
	await process_frame
	var stats := EnvChecks.measure(room)
	print("  test room: %s" % [stats])
	_check("test room: within the budget %s" % [EnvChecks.budget(stats)], EnvChecks.budget(stats).is_empty())
	_check("the presentation adds no draw of its own (%d: the floor's)" % stats["draws"], int(stats["draws"]) == 1)
	var blocked: Array = await EnvChecks.sight_line(self, room)
	_check("test room: a clear sight line %s" % [blocked], blocked.is_empty())
	var too_much := doc.duplicate(true)
	too_much["systems"][1]["params"]["tilt"] = 2.5
	_check("a tilt past its limit is refused", not EnvChecks.schema(too_much).is_empty())
	var swaying := doc.duplicate(true)
	swaying["systems"][1]["params"]["flicker"] = {"bind": "film.transient", "range": [0.0, 1.0]}
	_check("a flicker following a film signal unsmoothed fails comfort", not EnvChecks.comfort(swaying).is_empty())
	var real := doc.duplicate(true)
	real["name"] = "%s corner" % EnvChecks.MARKS[1]
	_check("a room named for a real mark fails the names", not EnvChecks.names(real).is_empty())
	room.queue_free()
	await process_frame


# --- In the main scene ------------------------------------------------------------------------------------------------

func _in_main() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	await _frames(5)
	main.open_path("stub://flat_mono")
	await _frames(3)
	var flat := main.screen.get_node("Flat") as MeshInstance3D
	var layer: Node = main.features.film_layer
	layer.enabled = true
	layer.force = true
	var before: String = layer.wanted_kind()
	layer.force = false
	_check("without a presentation the film layer would show the flat film (%s)" % before, before == "quad")
	_check("and the flat mesh has the screen's own material", flat.material_override == main.screen.material)
	var room: Node3D = EnvRoom.new()
	room.doc = DOC.duplicate(true)
	main.use_environment(room, "presentation_test")
	await _frames(3)
	var p: Node = room.host.system("presentation")
	_check("the room's presentation is built", p != null and p.get_script() == Presentation)
	_check("a picture stage is on: the flat mesh draws with its material", p.picture_on() and p.attached
			and flat.material_override == p.material())
	layer.force = true
	var during: String = layer.wanted_kind()
	var status: String = layer.status()
	layer.force = false
	_check("the film layer steps aside (%s, %s)" % [during, layer.scene_requests], during == ""
			and layer.scene_requests.size() == 1)
	_check("its status says why (%s)" % status, status.contains("draws the film itself"))
	# The preset fills, the document wins.
	_check("the preset's source (tape) and display (crt)", p.value("source") == "tape" and p.value("display") == "crt")
	_check("the document's mask over the preset's (grille, not slot)", p.value("mask") == "grille"
			and int(p.material().get_shader_parameter("pr_mask")) == 2)
	_check("the preset's head-switch tear (0.7)", is_equal_approx(float(p.value("head_switch")), 0.7))
	# The screen's uniforms follow.
	main.screen.material.set_shader_parameter("brightness", 0.6)
	main.screen.material.set_shader_parameter("pc_contrast", 1.3)
	await _frames(2)
	_check("the screen's own uniforms copied (brightness %s, contrast %s)" % [p.material().get_shader_parameter(
			"brightness"), p.material().get_shader_parameter("pc_contrast")], is_equal_approx(float(
			p.material().get_shader_parameter("brightness")), 0.6) and is_equal_approx(float(
			p.material().get_shader_parameter("pc_contrast")), 1.3))
	_check("the deband off under the tape's noise", is_zero_approx(float(p.material().get_shader_parameter("pc_deband"))))
	main.screen.material.set_shader_parameter("brightness", 1.0)
	main.screen.material.set_shader_parameter("pc_contrast", 1.0)
	_check("the picture's aspect from the screen (%.3f)" % float(p.material().get_shader_parameter("pr_aspect")),
			absf(float(p.material().get_shader_parameter("pr_aspect")) - main.screen.get_flat_size().aspect()) < 0.01)
	# Comfort: the Motion setting scales the preset's tracking and the bound weave.
	var rs: Node = main.features.room_settings
	_check("tracking at the preset's 0.5, weave at the setting's 0.5", is_equal_approx(float(p.value("tracking")), 0.5)
			and is_equal_approx(float(p.value("weave")), 0.5))
	rs.set_value("motion", 0.0)
	await _frames(2)
	_check("Motion 0: no tracking wobble, no weave (%s, %s)" % [p.value("tracking"), p.value("weave")],
			is_zero_approx(float(p.value("tracking"))) and is_zero_approx(float(p.value("weave")))
			and is_zero_approx(float(p.material().get_shader_parameter("pr_tracking"))))
	rs.set_value("motion", 1.0)
	await _frames(2)
	_check("Motion back: the wobble back", is_equal_approx(float(p.value("tracking")), 0.5))
	# A glitch: the tracking tears for a moment.
	p.act("glitch", {"seconds": 0.3})
	await _frames(1)
	var torn := float(p.material().get_shader_parameter("pr_tracking"))
	await create_timer(0.5).timeout
	_check("a glitch tears the tracking and passes (%.2f, then %.2f)" % [torn, float(p.material().get_shader_parameter(
			"pr_tracking"))], torn > 1.0 and is_equal_approx(float(p.material().get_shader_parameter("pr_tracking")), 0.5))
	# The worn print: weave in the gate, flicker under the ceiling, off with Flickering lights off.
	p.set_param("preset", "worn_print")
	await _frames(2)
	_check("worn print: a film source, tilted (%.2f degrees)" % float(p.value("tilt")), p.value("source") == "film"
			and is_equal_approx(float(p.value("tilt")), 0.35)
			and absf((p.material().get_shader_parameter("pr_turn") as Vector4).y) > 0.001)
	var gains := PackedFloat32Array()
	var weaves: Array[Vector2] = []
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 3000:
		await process_frame
		gains.append(p.flicker_gain())
		weaves.append(p.material().get_shader_parameter("pr_weave"))
	var seconds := (Time.get_ticks_msec() - t0) / 1000.0
	var lo := 10.0
	var hi := 0.0
	for g in gains:
		lo = minf(lo, g)
		hi = maxf(hi, g)
	_check("the flicker wavers within 3.5 %% (%.4f..%.4f)" % [lo, hi], hi - lo > 0.002 and lo >= 1.0
			- Presentation.FLICKER_DEPTH * 0.5 - 1e-4 and hi <= 1.0 + Presentation.FLICKER_DEPTH * 0.5 + 1e-4)
	var rate := _rate(gains, seconds)
	_check("and slowly: under the photosensitivity ceiling (%.2f Hz)" % rate, rate <= RoomSchema.MAX_HZ)
	var reach := 0.0
	for w in weaves:
		reach = maxf(reach, absf(w.y))
	_check("the gate weave drifts, within its limit (%.5f)" % reach, reach > 0.0
			and reach <= Presentation.WEAVE_MAX * 1.2)
	rs.set_value("flicker", false)
	await _frames(4)
	_check("Flickering lights off: steady (%.4f)" % p.flicker_gain(), is_equal_approx(p.flicker_gain(), 1.0))
	rs.set_value("flicker", true)
	# The window speaker: its own bus, the film's low end gone, the middle kept.
	var film := AudioServer.get_bus_index(EnvAudio.FILM)
	_check("no speaker: the film goes to Master", AudioServer.get_bus_send(film) == &"Master" and p.speaker_now == "none")
	rs.set_value("tinny", true)
	await _frames(2)
	film = AudioServer.get_bus_index(EnvAudio.FILM)
	var sb := AudioServer.get_bus_index(Presentation.SPEAKER_BUS)
	_check("Tinny speaker: the film through the window speaker (%s, send %s)" % [p.speaker_now,
			AudioServer.get_bus_send(film)], p.speaker_now == "window" and AudioServer.get_bus_send(film)
			== Presentation.SPEAKER_BUS and sb >= 0 and sb < film and AudioServer.get_bus_effect_count(sb) >= 4)
	_check("the Film bus's own effects untouched (the analysis, the duck's key)", not _has_filter(film))
	var levels := await _speaker_levels(p, rs)
	print("  window speaker: 80 Hz %.1f -> %.1f dBFS, 1 kHz %.1f -> %.1f dBFS" % levels)
	_check("the low end gone (80 Hz down %.1f dB)" % (levels[0] - levels[1]), levels[0] - levels[1] > 20.0)
	_check("the middle kept (1 kHz %.1f dB)" % (levels[3] - levels[2]), absf(levels[3] - levels[2]) < 6.0)
	# No picture stage: the screen's own material, the film layer back.
	p.set_param("preset", "none")
	await _frames(2)
	_check("no picture stage: the screen's own material again, the film layer back", not p.attached
			and flat.material_override == main.screen.material and layer.scene_requests.is_empty())
	p.set_param("preset", "glowbox_1930")
	await _frames(2)
	_check("a preset again: attached", p.attached and flat.material_override == p.material())
	# Another room: everything as it was.
	main.set_environment("void")
	await _frames(3)
	film = AudioServer.get_bus_index(EnvAudio.FILM)
	_check("another room: the screen's material, no request, the film to Master", flat.material_override
			== main.screen.material and layer.scene_requests.is_empty() and AudioServer.get_bus_send(film) == &"Master")
	rs.reset()
	main.queue_free()
	await _frames(2)


# --- Switching on and off, the channel -----------------------------------------------------------------------------

const SWITCH_DOC := {"schema": 4, "name": "Switching test",
	"screen": {"center": [0, 1.0, -1.5], "size": [0.48, 0.36]},
	"systems": [{"system": "presentation", "id": "set", "params": {"preset": "fireside_1953"}}]}
const STEP := 1.0 / 60.0


func _switching() -> void:
	var room: Node3D = EnvRoom.new()
	room.doc = SWITCH_DOC.duplicate(true)
	root.add_child(room)
	await process_frame
	room.host.auto = false
	var p: Node = room.host.system("set")
	_check("a set is on to begin with", p.power == "on" and not bool(p.material().get_shader_parameter("pr_switching")))
	# A valve set (1953): off to a line and a dot, then a slow warm-up from dark.
	p.call("_finish_sounds")
	p.sounds_played.clear()
	p.act("switch_off", {})
	var tr := _trace(room, p, float(p.get("_power_len")) + 0.2)
	_check("valve, off: dark at the end (%s)" % p.power, p.power == "off" and _last(tr, 2) == 0.0)
	_collapse("valve, off", tr)
	_calm("valve, off", tr)
	_sounds("valve, off", p, ["switch_clunk", "crt_off"])
	_check("off: the set still draws (its dark face)", p.picture_on())
	p.sounds_played.clear()
	p.act("switch_on", {})
	tr = _trace(room, p, float(Presentation.SWITCH["valve"]["on"]) + 0.2)
	var early: Array = tr[int(tr.size() * 0.1)]
	var mid: Array = tr[int(tr.size() * 0.5)]
	_check("valve, on: dark while the heaters warm, dim and a little small half way, full at the end (%.2f, %.2f "
			% [early[2], mid[2]] + "%s, %s)" % [mid[1], p.power], early[2] < 0.01 and mid[2] > 0.05 and mid[2] < 0.7
			and (mid[1] as Vector2).x < 1.0 and (mid[1] as Vector2).x > 0.85 and p.power == "on")
	_calm("valve, on", tr)
	_sounds("valve, on", p, ["switch_clunk", "valve_hum"])
	_check("on again: the steady picture (no switching stage)", not bool(p.material().get_shader_parameter(
			"pr_switching")))
	# A later CRT (1983): it opens out from a dot.
	p.set_param("preset", "sirclive_1983")
	room.host.step(STEP)
	p.call("_finish_sounds")
	p.act("switch_off", {})
	tr = _trace(room, p, float(p.get("_power_len")) + 0.2)
	_collapse("crt, off", tr)
	_calm("crt, off", tr)
	p.sounds_played.clear()
	p.act("switch_on", {})
	tr = _trace(room, p, float(Presentation.SWITCH_MIN_ON["crt"]) + 0.6)
	var dot := false
	var line := false
	for e: Array in tr:
		var r: Vector2 = e[1]
		dot = dot or (r.x < 0.05 and r.y < 0.05 and float(e[3]) > 0.3)
		line = line or (r.x > 0.95 and r.y < 0.05)
	_check("crt, on: a dot, a line across, then the raster opening (%s, %s, %s)" % [dot, line, p.power], dot and line
			and p.power == "on")
	_calm("crt, on", tr)
	_sounds("crt, on", p, ["switch_clunk"])
	# A channel change on a tube: the clunk, a dip and a moment's snow, and back.
	p.sounds_played.clear()
	var snow := float(p.material().get_shader_parameter("pr_snow"))
	p.act("channel", {})
	tr = _trace(room, p, 1.2)
	var low := 1.0
	var most_snow := 0.0
	for e: Array in tr:
		low = minf(low, float(e[2]))
	p.act("channel", {})
	for i in 20:
		room.host.step(STEP)
		most_snow = maxf(most_snow, float(p.material().get_shader_parameter("pr_snow")))
	tr = _trace(room, p, 1.2)
	_check("channel: the picture dips and comes back (%.2f), a moment's snow (%.2f over %.2f)" % [low, most_snow,
			snow], low < 0.6 and low > 0.3 and _last(tr, 2) == 1.0 and most_snow > snow + 0.2 and is_equal_approx(float(
			p.material().get_shader_parameter("pr_snow")), snow))
	_calm("channel", tr)
	_sounds("channel", p, ["channel_clunk", "channel_clunk"])
	# A panel (2005): black and back, no sounds, no dot.
	p.set_param("preset", "freedtv_2005")
	room.host.step(STEP)
	p.sounds_played.clear()
	p.act("switch_off", {})
	tr = _trace(room, p, 0.6)
	var plain := true
	for e: Array in tr:
		plain = plain and (e[1] as Vector2) == Vector2.ONE and float(e[3]) == 0.0
	_check("panel, off: black, no raster's collapse, no dot", p.power == "off" and plain)
	_calm("panel, off", tr)
	p.act("switch_on", {})
	tr = _trace(room, p, 1.2)
	_check("panel, on: up again, silently (%s)" % [p.sounds_played], p.power == "on" and p.sounds_played.is_empty())
	_calm("panel, on", tr)
	p.act("channel", {})
	tr = _trace(room, p, 1.2)
	var lowest := 1.0
	for e: Array in tr:
		lowest = minf(lowest, float(e[2]))
	_check("panel, channel: black for a moment (%.2f), and back" % lowest, lowest < 0.05 and _last(tr, 2) == 1.0)
	_calm("panel, channel", tr)
	room.queue_free()
	await process_frame
	# A set that starts off: dark (and drawn) until the film plays, then it comes on by itself.
	var doc: Dictionary = SWITCH_DOC.duplicate(true)
	doc["systems"][0]["params"]["starts_off"] = true
	room = EnvRoom.new()
	room.doc = doc
	root.add_child(room)
	await process_frame
	room.host.auto = false
	p = room.host.system("set")
	room.host.step(STEP)
	_check("starts_off: dark until a cue", p.power == "off" and p.picture_on())
	room.host.snapshot_override = {"open": true, "playing": true, "position": 0.0, "duration": 5400.0}
	var t := 0.0
	while t < 25.0 and p.power != "on":
		room.host.step(0.1)
		t += 0.1
	_check("starts_off: on by itself when the film plays (%s, %s, after %.1f s)" % [room.host.timeline.state, p.power,
			t], p.power == "on")
	room.queue_free()
	await process_frame


## [time, raster, light, glow, power] every step for `seconds`.
## Each era's tube going off: the collapse, then its dot for the era's seconds, longest before spot suppression (1937)
## and barely there by 1993; a mechanical set (1930) has no tube and no dot.
func _era_dots() -> void:
	var room: Node3D = EnvRoom.new()
	room.doc = SWITCH_DOC.duplicate(true)
	root.add_child(room)
	await process_frame
	room.host.auto = false
	var p: Node = room.host.system("set")
	var eras := ["mirrorlid_1937", "fireside_1953", "rental_1966", "colourstar_1972", "sirclive_1983", "rewinder_1987",
			"nightowl_1993"]
	var lingers: Array[float] = []
	for preset: String in eras:
		p.set_param("preset", preset)
		room.host.step(STEP)
		p.set("power", "on")
		p.act("switch_off", {})
		var k := float(p.get("_off_collapse"))
		var tr := _trace(room, p, float(p.get("_power_len")) + 0.2)
		var lit := 0.0
		for e: Array in tr:
			if float(e[0]) > k and float(e[3]) > 0.05:
				lit += STEP
		lingers.append(lit)
		_check("%s: dark at the end (%s)" % [preset, p.power], p.power == "off" and _last(tr, 3) < 0.01)
		_collapse(preset + ", off", tr)
		_calm(preset + ", off", tr)
	var ordered := true
	for i in range(1, lingers.size()):
		ordered = ordered and lingers[i] <= lingers[i - 1]
	_check("each era's dot (%s s): the oldest longest, shorter as the sets got spot suppression" % [lingers.map(
			func(x: float) -> String: return "%.1f" % x)], ordered and lingers[0] > 5.0 and lingers[-1] < 0.6)
	p.set_param("preset", "glowbox_1930")
	room.host.step(STEP)
	p.set("power", "on")
	p.act("switch_off", {})
	var tr := _trace(room, p, float(p.get("_power_len")) + 0.2)
	_check("a mechanical set (1930): its glow dies, no dot", tr.all(func(e: Array) -> bool: return float(e[3]) == 0.0)
			and p.power == "off")
	room.queue_free()


func _trace(room: Node3D, p: Node, seconds: float) -> Array:
	var out: Array = []
	var t := 0.0
	while t < seconds:
		room.host.step(STEP)
		t += STEP
		var n: Array = p.power_now()
		out.append([t, n[0], n[1], n[2], p.power])
	return out


func _last(tr: Array, k: int) -> float:
	return float((tr[-1] as Array)[k])


## A tube going off: the height first (a line across), then the width (a dot), a small dot, no brighter than 0.85.
func _collapse(label: String, tr: Array) -> void:
	var line := tr.any(func(e: Array) -> bool: return (e[1] as Vector2).y < 0.05 and (e[1] as Vector2).x > 0.9)
	var dots := tr.filter(func(e: Array) -> bool: return (e[1] as Vector2).x < 0.02 and float(e[3]) > 0.05)
	var widest := 0.0
	var brightest := 0.0
	for e: Array in dots:
		# The dot's half width in the picture's heights (a 16:9 window's half width is 0.89), and its glow's edge.
		widest = maxf(widest, (e[1] as Vector2).x * 0.89 + 0.006)
		brightest = maxf(brightest, float(e[3]))
	_check("%s: a line, then a dot that fades (%s, %d steps of dot)" % [label, line, dots.size()], line
			and dots.size() > 10 and _last(tr, 3) < 0.01)
	_check("%s: the dot small (%.3f of the picture's height across) and no brighter than 0.85 (%.2f)" % [label,
			widest * 2.0, brightest], widest * 2.0 < 0.05 and brightest <= 0.85)


## Comfort: the light and the glow each rise and fall at most once (no flicker), and each fade from 10 % to 90 % takes
## at least the comfort ceiling's fade (env_checks.gd MIN_FADE).
func _calm(label: String, tr: Array) -> void:
	for k: int in [2, 3]:
		var vals := PackedFloat32Array()
		for e: Array in tr:
			vals.append(float(e[k]))
		var turns := 0
		var dir := 0
		for i in range(1, vals.size()):
			var d := vals[i] - vals[i - 1]
			if absf(d) < 1e-5:
				continue
			var s := 1 if d > 0.0 else -1
			if dir != 0 and s != dir:
				turns += 1
			dir = s
		var fastest := _fastest_fade(vals)
		_check("%s: %s turns %d times, its quickest fade %.2f s (at least %.2f)" % [label, ["light", "glow"][k - 2],
				turns, fastest, EnvChecks.MIN_FADE], turns <= 1 and fastest >= EnvChecks.MIN_FADE - STEP)


## The shortest time a value takes between 10 % and 90 % of its range on one run up or down.
func _fastest_fade(vals: PackedFloat32Array) -> float:
	var lo: float = 10.0
	var hi: float = -10.0
	for v in vals:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	if hi - lo < 0.05:
		return 99.0
	var a := lo + (hi - lo) * 0.1
	var b := lo + (hi - lo) * 0.9
	var best := 99.0
	var start := -1
	for i in vals.size():
		var inside := vals[i] > a and vals[i] < b
		if inside and start < 0:
			start = i
		elif not inside and start >= 0:
			best = minf(best, (i - start) * STEP)
			start = -1
	return best


## The sounds played, in order, each at its designed level on the room's bus (sound_bed.gd LEVELS).
func _sounds(label: String, p: Node, want: Array) -> void:
	var names: Array = []
	var levelled := true
	for e: Array in p.sounds_played:
		names.append(str(e[0]))
		var w := EnvSynth.stream(str(e[0]))
		var at := float(e[1]) + EnvAudio.DEFAULT_DB + EnvSynth.level_db(w)
		if absf(at - float(SoundBed.LEVELS[str(e[0])])) > 0.1:
			levelled = false
	var on_bus := true
	for n: Node in p.owned():
		if n is AudioStreamPlayer3D and (n as AudioStreamPlayer3D).bus != Acoustics.BUS:
			on_bus = false
	_check("%s: the sounds %s (%s), at their designed levels, on the room's bus" % [label, want, names],
			names == want and levelled and on_bus)


## Crossings of the mean per second, halved: the flicker's rate, roughly (a sine of f Hz crosses 2f times a second).
func _rate(g: PackedFloat32Array, seconds: float) -> float:
	var mean := 0.0
	for x in g:
		mean += x
	mean /= g.size()
	var n := 0
	for i in range(1, g.size()):
		if (g[i - 1] - mean) * (g[i] - mean) < 0.0:
			n += 1
	return n * 0.5 / maxf(seconds, 0.001)


func _has_filter(bus: int) -> bool:
	for i in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, i) is AudioEffectFilter:
			return true
	return false


## [80 Hz without, with the speaker, 1 kHz without, with] at Master (dBFS RMS).
func _speaker_levels(_p: Node, rs: Node) -> Array:
	var cap := AudioEffectCapture.new()
	cap.buffer_length = 0.5
	AudioServer.add_bus_effect(0, cap)
	var out: Array = []
	for f: float in [80.0, 1000.0]:
		var tone := AudioStreamPlayer.new()
		tone.stream = _tone(f, -20.0)
		tone.bus = EnvAudio.FILM
		root.add_child(tone)
		tone.play()
		for on: bool in [false, true]:
			rs.set_value("tinny", on)
			await _frames(2)
			out.append(await _rms(cap, 0.6))
		tone.queue_free()
	for i in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, i) == cap:
			AudioServer.remove_bus_effect(0, i)
			break
	return out


func _rms(cap: AudioEffectCapture, seconds: float) -> float:
	await create_timer(0.3).timeout
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


func _tone(freq: float, rms_db: float) -> AudioStreamWAV:
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


# --- With a renderer ------------------------------------------------------------------------------------------------

const VIEW := Vector2i(640, 360)
const COST_VIEW := Vector2i(1920, 1080)


## A test card as NV12 planes (BT.709, limited range): colour bars above, a grey ramp, fine lines and a dark
## gradient below. [y, uv] textures.
func _card(w: int, h: int) -> Array:
	var bars: Array[Color] = [Color(0.75, 0.75, 0.75), Color(0.75, 0.75, 0), Color(0, 0.75, 0.75), Color(0, 0.75, 0),
			Color(0.75, 0, 0.75), Color(0.75, 0, 0), Color(0, 0, 0.75)]
	var y := Image.create_empty(w, h, false, Image.FORMAT_L8)
	var uv := Image.create_empty(w / 2, h / 2, false, Image.FORMAT_LA8)
	for j in h:
		for i in w:
			var c: Color
			var v := float(j) / h
			var u := float(i) / w
			if v < 0.5:
				c = bars[mini(int(u * 7.0), 6)]
			elif v < 0.7:
				c = Color(u, u, u)
			elif v < 0.85:
				c = Color.WHITE if (i / 2) % 2 == 0 else Color.BLACK
			else:
				c = Color(u * 0.2, u * 0.15, u * 0.25)
			var yy := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			y.set_pixel(i, j, Color(16.0 / 255.0 + yy * 219.0 / 255.0, 0, 0))
			if i % 2 == 0 and j % 2 == 0:
				var cb := (c.b - yy) / 1.8556
				var cr := (c.r - yy) / 1.5748
				uv.set_pixel(i / 2, j / 2, Color(128.0 / 255.0 + cb * 224.0 / 255.0, 0, 0,
						128.0 / 255.0 + cr * 224.0 / 255.0))
	return [ImageTexture.create_from_image(y), ImageTexture.create_from_image(uv)]


## A view of a quad (the film's) with this material: the camera on its axis sees `seen` metres above and below its
## middle (60 degrees). [viewport, quad, camera].
func _view(size: Vector2i, material: Material, quad_size := Vector2(3.2, 1.8), seen := 0.9, bg := Color.BLACK) -> Array:
	var vp := SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = bg
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var quad := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = quad_size
	quad.mesh = qm
	quad.material_override = material
	vp.add_child(quad)
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.position = Vector3(0, 0, seen / tan(deg_to_rad(30.0)))
	vp.add_child(cam)
	cam.current = true
	root.add_child(vp)
	return [vp, quad, cam]


## A presentation on its own (no room, no main): its material with the card's planes.
func _presentation(preset: String, tex: Array, extra := {}) -> Node:
	var p: Node = Presentation.new()
	p.id = "presentation"
	var given := {"preset": preset}
	given.merge(extra, true)
	p.params = EnvDoc.with_defaults(Presentation.spec()["params"], given)
	root.add_child(p)
	p.setup()
	p.tick(0.016)
	var m: ShaderMaterial = p.material()
	m.set_shader_parameter("y_tex", tex[0])
	m.set_shader_parameter("uv_tex", tex[1])
	m.set_shader_parameter("pr_aspect", 16.0 / 9.0)
	# As in the app: the deband off under the picture's own noise.
	m.set_shader_parameter("pc_deband", 0.0 if p.noisy() else 0.5)
	return p


func _plain(tex: Array) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = VIDEO_SHADER
	m.set_shader_parameter("y_tex", tex[0])
	m.set_shader_parameter("uv_tex", tex[1])
	return m


func _shot(vp: SubViewport) -> Image:
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	return img


func _render() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var tex := _card(960, 540)
	var base := _view(VIEW, _plain(tex))
	var plain: Image = await _shot(base[0])
	plain.save_png(OUT.path_join("plain.png"))
	var mean := 0.0
	for j in range(0, VIEW.y, 4):
		for i in range(0, VIEW.x, 4):
			mean += plain.get_pixel(i, j).get_luminance()
	_check("the card drawn (%.3f)" % (mean / (VIEW.x * VIEW.y / 16.0)), mean / (VIEW.x * VIEW.y / 16.0) > 0.2)
	# Every stage off: the screen's own picture (both without the deband's dither, new noise every frame).
	var undithered := _plain(tex)
	undithered.set_shader_parameter("pc_deband", 0.0)
	(base[1] as MeshInstance3D).material_override = undithered
	var own: Image = await _shot(base[0])
	var off := _presentation("none", tex)
	off.material().set_shader_parameter("pc_deband", 0.0)
	(base[1] as MeshInstance3D).material_override = off.material()
	var same: Image = await _shot(base[0])
	var d := _diff(own, same)
	_check("every stage off: the screen's own picture (mean %.5f, max %.3f)" % d, d[0] < 0.002 and d[1] < 0.03)
	off.queue_free()
	var shots := {}
	for preset: String in Presentation.PRESETS:
		var p := _presentation(preset, tex)
		(base[1] as MeshInstance3D).material_override = p.material()
		var img: Image = await _shot(base[0])
		img.save_png(OUT.path_join("%s.png" % preset))
		shots[preset] = img
		var dd := _diff(plain, img)
		_check("%s: draws and changes the picture (mean %.4f)" % [preset, dd[0]], dd[0] > 0.004 and _mean(img) > 0.03)
		p.queue_free()
	# What each display looks like.
	var corner := (shots["fireside_1953"] as Image).get_pixel(2, 2)
	var middle := (shots["fireside_1953"] as Image).get_pixel(VIEW.x / 2, VIEW.y * 3 / 5)
	_check("a round-cornered tube: its corner black (%s), its middle lit" % corner, corner.get_luminance() < 0.02
			and middle.get_luminance() > 0.2)
	# The tube's shape (tube 1.33 in the sets before 2000): a 16:9 film letterboxed in a 4:3 tube has the tube's round
	# corners, which lie mostly in the bars above and below, so less of the picture's corner is cut than when the
	# corners are the picture's own.
	_check("the sets before 2000 have a 4:3 tube, the flat panel none", is_equal_approx(float(Presentation.PRESETS[
			"fireside_1953"]["params"]["tube"]), 1.3333) and not Presentation.PRESETS["freedtv_2005"]["params"].has("tube"))
	var own_p := _presentation("fireside_1953", tex)
	var om: ShaderMaterial = own_p.material()
	om.set_shader_parameter("pr_tube", 0.0)
	(base[1] as MeshInstance3D).material_override = om
	var own_img: Image = await _shot(base[0])
	own_p.queue_free()
	var at := Vector2i(VIEW.x * 3 / 100, VIEW.y * 8 / 100)
	var cut := own_img.get_pixel(at.x, at.y).get_luminance()
	var kept := (shots["fireside_1953"] as Image).get_pixel(at.x, at.y).get_luminance()
	_check("a 4:3 tube round a wide film: its corner cut less (%.3f against %.3f with the picture's own corners)"
			% [kept, cut], kept > cut + 0.1 and cut < 0.05)
	var bar := (shots["fireside_1953"] as Image).get_pixel(VIEW.x * 3 / 14, VIEW.y / 4)
	_check("black and white: the yellow bar grey (%s)" % bar, absf(bar.r - bar.b) < 0.08 and absf(bar.r - bar.g) < 0.08)
	var glow := (shots["glowbox_1930"] as Image).get_pixel(VIEW.x / 2, VIEW.y / 2)
	_check("a mechanical-scan set: orange (%s)" % glow, glow.r > glow.g * 1.4 and glow.g > glow.b)
	var edge := (shots["glowbox_1930"] as Image).get_pixel(8, VIEW.y / 2)
	_check("and dark at its edges (%s)" % edge, edge.get_luminance() < 0.05)
	var bleed := _mean_rect(shots["rewinder_1987"], Rect2i(VIEW.x * 2 / 7, 20, 4, 100)).distance_to(
			_mean_rect(plain, Rect2i(VIEW.x * 2 / 7, 20, 4, 100)))
	_check("tape: the colour bleeds over the bar's edge (%.3f)" % bleed, bleed > 0.02)
	var bottom := _diff_rect(plain, shots["rewinder_1987"], Rect2i(0, VIEW.y - 6, VIEW.x, 4))
	var top := _diff_rect(plain, shots["rewinder_1987"], Rect2i(0, VIEW.y / 2 + 10, VIEW.x, 4))
	_check("tape: the bottom lines torn more than the rest (%.3f against %.3f)" % [bottom, top], bottom > top)
	# An OLED's black is black; a backlit panel's glows a little.
	var dark := Vector2i(VIEW.x / 20, VIEW.y * 19 / 20)
	var oled := (shots["slimline_present"] as Image).get_pixel(dark.x, dark.y).get_luminance()
	var lcd := (shots["freedtv_2005"] as Image).get_pixel(dark.x, dark.y).get_luminance()
	_check("an OLED's black is black (%.4f), a backlit panel's not (%.4f)" % [oled, lcd], oled < 0.012 and lcd > oled
			+ 0.01)
	# A rear projection's three tubes not quite converged: the bars' edges fringed.
	var sharp := _presentation("projection_2002", tex, {"convergence": 0.0})
	(base[1] as MeshInstance3D).material_override = sharp.material()
	var converged: Image = await _shot(base[0])
	sharp.queue_free()
	var fringe := _diff_rect(converged, shots["projection_2002"], Rect2i(0, 20, VIEW.x, 100))
	_check("rear projection: colour fringes at the bars' edges (%.4f)" % fringe, fringe > 0.003)
	(base[0] as Node).queue_free()
	await process_frame
	await _window(tex)
	await _switch_pictures(tex)
	await _off_axis(tex)
	await _cost(tex)


## The set's window and the film in it: a 16:9 film in a 4:3 window (letterbox: black bars above and below; pan and
## scan: it fills the window, its sides cut; 14:9: thin bars and a little cut; stretch: the window filled, nothing
## cut), the mirror's flip, a 4:3 film pillarboxed in a 16:9 panel; outside the window the bezel (here the dark blue
## background) shows.
func _window(tex: Array) -> void:
	var size := Vector2i(640, 480)
	var bg := Color(0.0, 0.0, 0.35)
	var v := _view(size, _plain(tex), Vector2(3.2, 1.8), 1.35, bg)
	var scale := size.y / 2.7
	var cx := size.x * 0.5
	var cy := size.y * 0.5
	var at := func(x: float, y: float) -> Vector2i: return Vector2i(int(cx + x * scale), int(cy - y * scale))
	var pics := {}
	for mode: String in ["letterbox", "pan_and_scan", "fourteen_nine", "stretch", "mirror"]:
		var extra := {"tube": 1.3333, "aspect_mode": mode if mode != "mirror" else "letterbox", "mirror": mode == "mirror"}
		var p := _presentation("none", tex, extra)
		(v[1] as MeshInstance3D).material_override = p.material()
		var img: Image = await _shot(v[0])
		img.save_png(OUT.path_join("window_%s.png" % mode))
		pics[mode] = img
		p.queue_free()
	var px := func(mode: String, x: float, y: float) -> Color:
		var q: Vector2i = at.call(x, y)
		return (pics[mode] as Image).get_pixel(q.x, q.y)
	var is_bg := func(c: Color) -> bool: return c.b > 0.25 and c.r < 0.05 and c.g < 0.05
	var lit := func(c: Color) -> bool: return c.get_luminance() > 0.2
	var black := func(c: Color) -> bool: return c.get_luminance() < 0.03 and c.b < 0.1
	var grey := func(c: Color) -> bool: return lit.call(c) and absf(c.r - c.b) < 0.08
	var yellow := func(c: Color) -> bool: return c.r > 0.3 and c.g > 0.3 and c.b < 0.1
	var blue := func(c: Color) -> bool: return c.b > 0.3 and c.r < 0.1 and c.g < 0.1
	_check("letterbox: black bars in the window over and under the film, the film whole (%s, %s, %s)" % [px.call(
			"letterbox", 0.0, 1.05), px.call("letterbox", -1.28, 0.5), px.call("letterbox", 1.7, 0.0)],
			black.call(px.call("letterbox", 0.0, 1.05)) and grey.call(px.call("letterbox", -1.28, 0.5))
			and is_bg.call(px.call("letterbox", 1.7, 0.0)) and is_bg.call(px.call("letterbox", 0.0, 1.3)))
	_check("pan and scan: the window filled, the sides cut (%s, %s)" % [px.call("pan_and_scan", 0.0, 1.05),
			px.call("pan_and_scan", -1.28, 0.5)], lit.call(px.call("pan_and_scan", 0.0, 1.05))
			and yellow.call(px.call("pan_and_scan", -1.28, 0.5)))
	_check("14:9: thin bars, a little cut (%s, %s)" % [px.call("fourteen_nine", 0.0, 1.15), px.call("fourteen_nine",
			0.0, 0.98)], black.call(px.call("fourteen_nine", 0.0, 1.15)) and lit.call(px.call("fourteen_nine", 0.0,
			0.98)))
	_check("stretch: the window filled, nothing cut (%s, %s)" % [px.call("stretch", 0.0, 1.15), px.call("stretch",
			-1.28, 0.5)], lit.call(px.call("stretch", 0.0, 1.15)) and grey.call(px.call("stretch", -1.28, 0.5)))
	_check("mirror: the picture the wrong way round (%s)" % px.call("mirror", -1.28, 0.5), blue.call(px.call("mirror",
			-1.28, 0.5)))
	(v[0] as Node).queue_free()
	await process_frame
	# A 4:3 film on a 16:9 panel: pillarboxed; the film's quad is taller than the panel, and outside it the bezel.
	v = _view(size, _plain(tex), Vector2(3.2, 2.4), 1.35, bg)
	var pb := _presentation("none", tex, {"tube": 1.7778})
	pb.material().set_shader_parameter("pr_aspect", 4.0 / 3.0)
	(v[1] as MeshInstance3D).material_override = pb.material()
	var img: Image = await _shot(v[0])
	img.save_png(OUT.path_join("window_pillarbox.png"))
	pb.queue_free()
	var side: Vector2i = at.call(-1.45, 0.0)
	var mid: Vector2i = at.call(0.0, 0.5)
	var over: Vector2i = at.call(0.0, 1.05)
	_check("a 4:3 film on a 16:9 panel: bars at the sides, the bezel over the panel (%s, %s, %s)" % [img.get_pixelv(
			side), img.get_pixelv(mid), img.get_pixelv(over)], black.call(img.get_pixelv(side)) and lit.call(
			img.get_pixelv(mid)) and is_bg.call(img.get_pixelv(over)))
	(v[0] as Node).queue_free()
	await process_frame


## The switching stages drawn: the dark face, a line across, a small bright dot.
func _switch_pictures(tex: Array) -> void:
	var v := _view(VIEW, _plain(tex))
	var p := _presentation("sirclive_1983", tex)
	var m: ShaderMaterial = p.material()
	(v[1] as MeshInstance3D).material_override = m
	var stages := {"off": [Vector2.ONE, 0.0, 0.0], "line": [Vector2(1.0, 0.01), 1.0, 0.75],
			"dot": [Vector2(0.012, 0.01), 0.0, 0.75]}
	var imgs := {}
	for k: String in stages:
		m.set_shader_parameter("pr_switching", true)
		m.set_shader_parameter("pr_raster", stages[k][0])
		m.set_shader_parameter("pr_power", stages[k][1])
		m.set_shader_parameter("pr_spot", stages[k][2])
		var img: Image = await _shot(v[0])
		img.save_png(OUT.path_join("switch_%s.png" % k))
		imgs[k] = img
	p.queue_free()
	(v[0] as Node).queue_free()
	var off_mean := _mean(imgs["off"])
	_check("off: the tube's dark face (%.3f)" % off_mean, off_mean > 0.005 and off_mean < 0.08)
	var centre: Color = (imgs["line"] as Image).get_pixel(VIEW.x / 2, VIEW.y / 2)
	var above: Color = (imgs["line"] as Image).get_pixel(VIEW.x / 2, VIEW.y / 4)
	var across: Color = (imgs["line"] as Image).get_pixel(VIEW.x / 5, VIEW.y / 2)
	_check("a line across the middle (%.2f, %.2f across, %.3f above)" % [centre.get_luminance(), across.get_luminance(),
			above.get_luminance()], centre.get_luminance() > 0.3 and across.get_luminance() > 0.3
			and above.get_luminance() < 0.15)
	var bright := 0
	var dimg: Image = imgs["dot"]
	for j in range(0, VIEW.y, 2):
		for i in range(0, VIEW.x, 2):
			if dimg.get_pixel(i, j).get_luminance() > 0.3:
				bright += 1
	var share := bright / float(VIEW.x * VIEW.y / 4)
	_check("a small dot (%.4f of the picture bright), bright in the middle (%.2f)" % [share, dimg.get_pixel(VIEW.x / 2,
			VIEW.y / 2).get_luminance()], share > 0.0 and share < 0.003 and dimg.get_pixel(VIEW.x / 2, VIEW.y / 2)
			.get_luminance() > 0.3)


## Off the screen's axis: a rear projection much darker from above, less from the side; an LCD's colour shifting.
func _off_axis(tex: Array) -> void:
	var v := _view(VIEW, _plain(tex))
	var cam: Camera3D = v[2]
	var d := 0.9 / tan(deg_to_rad(30.0))
	var light := {}
	for preset: String in ["projection_2002", "freedtv_2005"]:
		var extra := {"off_axis": 1.0} if preset == "freedtv_2005" else {}
		var p := _presentation(preset, tex, extra)
		(v[1] as MeshInstance3D).material_override = p.material()
		for k: String in ["front", "above", "side"]:
			var dir := Vector3(0, 0, 1)
			if k == "above":
				dir = Vector3(0, sin(deg_to_rad(30.0)), cos(deg_to_rad(30.0)))
			elif k == "side":
				dir = Vector3(sin(deg_to_rad(30.0)), 0, cos(deg_to_rad(30.0)))
			cam.look_at_from_position(dir * d, Vector3.ZERO)
			var img: Image = await _shot(v[0])
			img.save_png(OUT.path_join("%s_%s.png" % [preset, k]))
			light["%s_%s" % [preset, k]] = _mean_rect(img, Rect2i(VIEW.x / 2 - 8, VIEW.y / 2 + 20, 16, 16))
		p.queue_free()
	(v[0] as Node).queue_free()
	var lum := func(k: String) -> float: return (light[k] as Vector3).dot(Vector3(0.2126, 0.7152, 0.0722))
	var above: float = lum.call("projection_2002_above") / maxf(lum.call("projection_2002_front"), 0.001)
	var side: float = lum.call("projection_2002_side") / maxf(lum.call("projection_2002_front"), 0.001)
	_check("rear projection: much darker from 30 degrees above (x %.2f) than from the side (x %.2f)" % [above, side],
			above < 0.6 and side > above + 0.15)
	var shift := (light["freedtv_2005_above"] as Vector3).distance_to(light["freedtv_2005_front"])
	_check("an LCD with off_axis: the picture shifts from above (%.3f)" % shift, shift > 0.03)


## Frame time with the quad filling a 1920 x 1080 view: the screen's own shader against each preset.
func _cost(tex: Array) -> void:
	var v := _view(COST_VIEW, _plain(tex))
	var vp: SubViewport = v[0]
	RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
	var plain_ms: float = await _time(vp)
	var rows := ["  cost at %d x %d (lavapipe, CPU ms per frame; GPU ms where the driver tells): video.gdshader %s"
			% [COST_VIEW.x, COST_VIEW.y, _ms(plain_ms, vp)]]
	var worst := 0.0
	for preset: String in Presentation.PRESETS:
		var p := _presentation(preset, tex)
		(v[1] as MeshInstance3D).material_override = p.material()
		var ms: float = await _time(vp)
		worst = maxf(worst, ms / maxf(plain_ms, 0.001))
		rows.append("    %s: %s (x %.2f)" % [preset, _ms(ms, vp), ms / maxf(plain_ms, 0.001)])
		p.queue_free()
	print("\n".join(rows))
	_check("no preset costs more than three times the screen's own shader (x %.2f)" % worst, worst < 3.0)
	vp.queue_free()


func _time(vp: SubViewport) -> float:
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var t0 := Time.get_ticks_usec()
	var n := 12
	for i in n:
		await RenderingServer.frame_post_draw
	return (Time.get_ticks_usec() - t0) / 1000.0 / n


func _ms(ms: float, vp: SubViewport) -> String:
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid())
	return "%.1f ms" % ms + (" (GPU %.2f ms)" % gpu if gpu > 0.0 else "")


func _diff(a: Image, b: Image) -> Array:
	var sum := 0.0
	var top := 0.0
	var n := 0
	for j in range(0, a.get_height(), 2):
		for i in range(0, a.get_width(), 2):
			var ca := a.get_pixel(i, j)
			var cb := b.get_pixel(i, j)
			var dd := maxf(maxf(absf(ca.r - cb.r), absf(ca.g - cb.g)), absf(ca.b - cb.b))
			sum += dd
			top = maxf(top, dd)
			n += 1
	return [sum / n, top]


func _diff_rect(a: Image, b: Image, r: Rect2i) -> float:
	var sum := 0.0
	for j in range(r.position.y, r.end.y):
		for i in range(r.position.x, r.end.x):
			var ca := a.get_pixel(i, j)
			var cb := b.get_pixel(i, j)
			sum += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
	return sum / (r.size.x * r.size.y)


func _mean(img: Image) -> float:
	var s := 0.0
	for j in range(0, img.get_height(), 4):
		for i in range(0, img.get_width(), 4):
			s += img.get_pixel(i, j).get_luminance()
	return s / (img.get_width() * img.get_height() / 16.0)


func _mean_rect(img: Image, r: Rect2i) -> Vector3:
	var s := Vector3.ZERO
	for j in range(r.position.y, r.end.y):
		for i in range(r.position.x, r.end.x):
			var c := img.get_pixel(i, j)
			s += Vector3(c.r, c.g, c.b)
	return s / (r.size.x * r.size.y)


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)
