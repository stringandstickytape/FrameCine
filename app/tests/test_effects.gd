extends SceneTree

## The effect library (scripts/effects/effect_library.gd, docs/effects.md): the catalogue is complete (a description,
## tags, surfaces, blend, cost tier and every option with its bounds, default, meaning and uniform); options validate
## against their bounds in the room schema's words; every animated effect's declared rate and swing keep under the
## photosensitivity ceiling and no option can pass it; the first eight are room_schema.gd's EFFECTS exactly and their
## materials are assistant_room.gd's; the noise textures are there and small; the effects and effect_info commands
## answer, tagged for the assistant.
## With a renderer, also: every effect compiles (no shader error, the sphere draws); every animated effect at its
## fastest options, its clock stepped by hand, changes no pixel faster than the ceiling allows, and every still one
## not at all; the first eight draw the same pixels through the library as through the room builder.
## godot --headless --xr-mode off --path app --script res://tests/test_effects.gd
## With a renderer (WSL: lavapipe): VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a godot
##     --xr-mode off --path app --script res://tests/test_effects.gd

const EffectLibrary := preload("res://scripts/effects/effect_library.gd")
const EffectLab := preload("res://scripts/effects/effect_lab.gd")
const RoomSchema := preload("res://scripts/assistant/room_schema.gd")
const AssistantRoom := preload("res://scripts/assistant/assistant_room.gd")
const DevCommands := preload("res://scripts/dev/dev_commands.gd")

## The catalogue's size: never fewer than this without a reason.
const MIN_EFFECTS := 48
## Noise textures: what they must be (size) and stay under (bytes).
const NOISE := {"res://textures/fx/fx_value.png": [64, 32 * 1024], "res://textures/fx/fx_fbm.png": [256, 192 * 1024]}

var _failures := 0
var _checks := 0
var _shader_errors: Array[String] = []


## Collects shader errors (compiling happens on the render thread; the logger is called from any thread).
class ShaderLog extends Logger:
	var errors: Array[String] = []
	var _mutex := Mutex.new()

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_SHADER or "SHADER" in code.to_upper() or "shader" in rationale:
			_mutex.lock()
			errors.append("%s:%d %s %s" % [file, line, code, rationale])
			_mutex.unlock()

	func take() -> Array[String]:
		_mutex.lock()
		var out := errors.duplicate()
		errors.clear()
		_mutex.unlock()
		return out


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var log := ShaderLog.new()
	OS.add_logger(log)
	_catalogue_checks()
	_photosensitivity_declared()
	_validation_checks()
	_classic_checks()
	_noise_checks()
	await _command_checks()
	_layered_checks()
	if EffectLab.has_renderer():
		EffectLab.set_room(self)
		await _render_checks(log)
		await _layered_pixels()
		await _photosensitivity_measured()
		await _classic_pixels()
	else:
		print("(headless: compiling, the measured ceiling and the pixels need a renderer)")
	OS.remove_logger(log)
	print("test_effects: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _catalogue_checks() -> void:
	var ids := EffectLibrary.ids()
	_check("the catalogue has %d effects (at least %d)" % [ids.size(), MIN_EFFECTS], ids.size() >= MIN_EFFECTS)
	var common := FileAccess.get_file_as_string("res://shaders/fx/fx_common.gdshaderinc")
	var defines := {}
	for id in ids:
		var e := EffectLibrary.entry(id)
		var why: Array[String] = []
		if not (id.is_valid_identifier() and id == id.to_lower()):
			why.append("id not lower_snake_case")
		if str(e.get("name", "")).is_empty():
			why.append("no name")
		var d := str(e.get("description", ""))
		if d.length() < 30 or d.length() > 220 or "\n" in d:
			why.append("description: one line of 30..220 characters (%d)" % d.length())
		if not (e.get("tags") is Array) or (e["tags"] as Array).is_empty():
			why.append("no tags")
		if not str(e["surfaces"]) in EffectLibrary.SURFACES:
			why.append("surfaces %s" % e["surfaces"])
		if not str(e["blend"]) in EffectLibrary.BLENDS:
			why.append("blend %s" % e["blend"])
		if not (e["layers"] is bool):
			why.append("layers not true or false")
		if not EffectLibrary.TIERS.has(str(e.get("cost", ""))):
			why.append("cost tier %s" % e.get("cost"))
		if not (e.get("cost_ratio") is float or e.get("cost_ratio") is int):
			why.append("no measured cost_ratio")
		var define := str(e.get("define", ""))
		if not define.begins_with("FX_"):
			why.append("define %s" % define)
		if defines.has(define + str(e["shader"])):
			why.append("define %s used twice" % define)
		defines[define + str(e["shader"])] = id
		var code := FileAccess.get_file_as_string(str(e["shader"]))
		if code.is_empty():
			why.append("no shader %s" % e["shader"])
		elif not ("defined(%s)" % define in code):
			why.append("%s not in its shader" % define)
		var second := FileAccess.get_file_as_string(str(e.get("second_pass", ""))) if e.has("second_pass") else ""
		if int(e["passes"]) == 2 and second.is_empty():
			why.append("two passes, no second pass shader")
		for k: String in e["options"]:
			var o: Dictionary = e["options"][k]
			var t := str(o.get("type", ""))
			if not t in ["float", "int", "color", "enum", "bool"]:
				why.append("%s: type %s" % [k, t])
				continue
			if str(o.get("description", "")).is_empty():
				why.append("%s: no description" % k)
			if not o.has("default"):
				why.append("%s: no default" % k)
				continue
			if t in ["float", "int"] and not (float(o["min"]) < float(o["max"]) and float(o["default"]) >= float(o["min"])
					and float(o["default"]) <= float(o["max"])):
				why.append("%s: min < max, default within" % k)
			if t == "enum" and not ((o.get("values", []) as Array).size() >= 2 and o["default"] in o["values"]):
				why.append("%s: two values or more, the default one of them" % k)
			if t == "color" and not EffectLibrary._is_color(o["default"]):
				why.append("%s: default not a colour" % k)
			var u := str(o.get("uniform", ""))
			var where := second if int(o.get("pass", 0)) == 1 else code + common
			if u.is_empty() or not RegEx.create_from_string("uniform\\s+\\w+\\s+%s\\b" % u).search(where):
				why.append("%s: uniform %s not declared" % [k, u])
		_check("%s is complete%s" % [id, (": " + ", ".join(why)) if not why.is_empty() else ""], why.is_empty())
	var sky := EffectLibrary.schema_effects(true)
	var surf := EffectLibrary.schema_effects(false)
	_check("schema_effects splits the sky's from the surfaces' (%d + %d)" % [sky.size(), surf.size()],
			sky.size() + surf.size() == ids.size() and not surf.has("sky_aurora") and surf.has("rim_glow"))
	var opts: Dictionary = surf["rim_glow"]["options"]
	_check("schema_effects leaves out the shader's wiring", not opts["color"].has("uniform"))


## The declared rates and swings, and the options' bounds, against the ceiling.
func _photosensitivity_declared() -> void:
	var ceiling := EffectLibrary.MAX_HZ * EffectLibrary.MAX_SWING
	for id in EffectLibrary.ids():
		var e := EffectLibrary.entry(id)
		var a: Dictionary = e["animation"]
		var why: Array[String] = []
		if not a.is_empty():
			var hz: Array = a.get("hz", [])
			var swing := float(a.get("swing", -1.0))
			if hz.size() != 2 or not (float(hz[0]) <= float(hz[1]) and float(hz[0]) >= 0.0):
				why.append("hz: [slowest, fastest]")
			elif float(hz[1]) > EffectLibrary.MAX_HZ:
				why.append("fastest %s Hz over %s" % [hz[1], EffectLibrary.MAX_HZ])
			elif not (swing > 0.0 and swing <= 1.0):
				why.append("swing 0..1")
			elif float(hz[1]) * swing > ceiling + 1e-6:
				why.append("%s Hz x swing %s steeper than %s Hz x %s" % [hz[1], swing, EffectLibrary.MAX_HZ,
						EffectLibrary.MAX_SWING])
		for k: String in e["options"]:
			var o: Dictionary = e["options"][k]
			if k == "rate" and float(o.get("max", 0.0)) > EffectLibrary.MAX_HZ:
				why.append("rate up to %s" % o["max"])
			if k in ["swing", "twinkle"] and float(o.get("max", 0.0)) > EffectLibrary.MAX_SWING:
				why.append("%s up to %s" % [k, o["max"]])
			if k == "speed" and float(o.get("max", 0.0)) > 1.0:
				why.append("speed is 0..1 (the shader sets its own rate)")
		_check("%s keeps under the ceiling as declared%s" % [id, (": " + ", ".join(why)) if not why.is_empty()
				else (" (%s)" % [a] if not a.is_empty() else " (still)")], why.is_empty())


func _validation_checks() -> void:
	var all_ok := true
	var bad: Array[String] = []
	for id in EffectLibrary.ids():
		var e := EffectLibrary.entry(id)
		if not EffectLibrary.validate(id, {}).is_empty() or not EffectLibrary.validate(id,
				EffectLibrary.with_defaults(id, {})).is_empty():
			all_ok = false
			bad.append(id + " defaults")
		for k: String in e["options"]:
			var o: Dictionary = e["options"][k]
			var wrong: Array = []
			match str(o["type"]):
				"float", "int":
					wrong = [float(o["max"]) + 1.0, float(o["min"]) - 1.0, "a lot"]
				"color":
					wrong = ["not a colour", [2, 0, 0]]
				"enum":
					wrong = ["none of them", 3]
				"bool":
					wrong = ["yes"]
			for w: Variant in wrong:
				var errs := EffectLibrary.validate(id, {k: w}, "$.x")
				if errs.size() != 1 or str(errs[0]["path"]) != "$.x.%s" % k:
					all_ok = false
					bad.append("%s.%s = %s" % [id, k, w])
		if EffectLibrary.validate(id, {"no_such_option": 1}).size() != 1:
			all_ok = false
			bad.append(id + " unknown option")
	_check("every option is checked against its bounds and type%s" % (" (%s)" % ", ".join(bad) if not bad.is_empty()
			else ""), all_ok)
	var errs := EffectLibrary.validate("pulse", {"rate": 5, "swing": 0.9}, "$.parts[0].material.effect")
	var text := str(errs)
	_check("the ceiling is named when passed (%s)" % text, errs.size() == 2 and "3 times a second" in text
			and "no larger brightness swings" in text and "$.parts[0].material.effect.rate" in text)
	errs = EffectLibrary.validate("strobe", {})
	_check("an unknown effect lists the known ones", errs.size() == 1 and "rim_glow" in str(errs[0]["error"])
			and str(errs[0]["path"]).ends_with(".name"))


## The first eight: room_schema.gd's EFFECTS, derived; their materials as the room builder makes them.
func _classic_checks() -> void:
	var derived := EffectLibrary.schema_effects(false)
	var same := true
	var diff: Array[String] = []
	for id: String in RoomSchema.EFFECTS:
		var theirs: Dictionary = RoomSchema.EFFECTS[id]["options"]
		if not derived.has(id):
			same = false
			diff.append(id + " missing")
			continue
		var ours: Dictionary = derived[id]["options"]
		if ours.keys() != theirs.keys():
			same = false
			diff.append("%s options %s, schema %s" % [id, ours.keys(), theirs.keys()])
			continue
		for k: String in theirs:
			for f in ["type", "min", "max", "default", "values"]:
				if theirs[k].get(f) != ours[k].get(f):
					same = false
					diff.append("%s.%s.%s" % [id, k, f])
	_check("the first eight are room_schema's EFFECTS: names, options, bounds, defaults%s" % (
			" (%s)" % ", ".join(diff) if not diff.is_empty() else ""), same)
	same = true
	diff.clear()
	for id: String in RoomSchema.EFFECTS:
		var opts := {}
		for k: String in RoomSchema.EFFECTS[id]["options"]:
			var o: Dictionary = RoomSchema.EFFECTS[id]["options"][k]
			if str(o["type"]) == "float":
				opts[k] = lerpf(float(o["min"]), float(o["max"]), 0.3)
			elif str(o["type"]) == "color":
				opts[k] = "#336699"
		var a := ShaderMaterial.new()
		var fx := opts.duplicate()
		fx["name"] = id
		AssistantRoom._effect(a, fx, "part:" + id)
		var b := ShaderMaterial.new()
		EffectLibrary.apply(b, id, opts, EffectLibrary.seed_of("part:" + id))
		var why := _same_material(a, b)
		if why != "":
			same = false
			diff.append("%s: %s" % [id, why])
	_check("the first eight's materials are the room builder's (shader, uniforms, second pass)%s" % (
			" (%s)" % ", ".join(diff) if not diff.is_empty() else ""), same)


func _same_material(a: ShaderMaterial, b: ShaderMaterial) -> String:
	if a.shader.code != b.shader.code:
		return "shader code"
	for u in ["fx_color", "fx_strength", "fx_rate", "fx_depth", "fx_amount", "fx_seed"]:
		var x: Variant = a.get_shader_parameter(u)
		var y: Variant = b.get_shader_parameter(u)
		if typeof(x) != typeof(y) or (x is float and not is_equal_approx(x, y)) or (x is Color and not
				(x as Color).is_equal_approx(y)):
			return "%s: %s against %s" % [u, x, y]
	if (a.next_pass == null) != (b.next_pass == null):
		return "second pass"
	if a.next_pass != null:
		var pa := a.next_pass as ShaderMaterial
		var pb := b.next_pass as ShaderMaterial
		if pa.shader != pb.shader or pa.get_shader_parameter("width") != pb.get_shader_parameter("width") \
				or not (pa.get_shader_parameter("outline_color") as Color).is_equal_approx(
				pb.get_shader_parameter("outline_color")):
			return "second pass's shader or uniforms"
	return ""


## A layered look: an effect over a colour or a library material's picture.
func _layered_checks() -> void:
	var own := ""
	for id in EffectLibrary.ids():
		if not bool(EffectLibrary.entry(id)["layers"]):
			own = id
			break
	var mat := ShaderMaterial.new()
	_check("an effect that draws its own surface does not layer (%s)" % own, own == ""
			or EffectLibrary.apply_layered(mat, own, {}, 0.0, {"color": "#808080"}) != "")
	_check("the first eight map a picture by UV only", EffectLibrary.apply_layered(mat, "rim_glow", {}, 0.0,
			{"texture": _checker(), "triplanar": 0.5}) != "")
	var why := EffectLibrary.apply_layered(mat, "react_caustics", {}, 0.0, {"texture": _checker(), "triplanar": 0.5,
			"color": "#ffeedd"})
	_check("a layered look sets the picture and its mapping (%s)" % why, why == ""
			and mat.shader.code.contains("#define FX_BASE_TRIPLANAR") and mat.get_shader_parameter("use_texture") == true
			and is_equal_approx(float(mat.get_shader_parameter("base_scale")), 0.5))


## A black and white checker, 8 squares across.
func _checker() -> ImageTexture:
	var img := Image.create_empty(64, 64, true, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			img.set_pixel(x, y, Color.WHITE if (x / 8 + y / 8) % 2 == 0 else Color(0.1, 0.1, 0.1))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## The picture shows under a layered effect, by UV and on three axes: the sphere's middle varies far more than with
## the plain colour.
func _layered_pixels() -> void:
	var spread := {}
	for kind in ["colour", "uv", "triplanar"]:
		var mat := ShaderMaterial.new()
		var base := {"color": "#c0c0c0"}
		if kind != "colour":
			base["texture"] = _checker()
			base["triplanar"] = 0.4 if kind == "triplanar" else 0.0
			base["uv_scale"] = Vector2(4, 2)
		EffectLibrary.apply_layered(mat, "react_caustics", {"strength": 0.2}, 0.3, base)
		var vp := EffectLab.stage(Vector2i(64, 64), mat)
		root.add_child(vp)
		for i in 3:
			await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		vp.queue_free()
		var lo := 1.0
		var hi := 0.0
		for y in range(24, 40):
			for x in range(24, 40):
				var l := img.get_pixel(x, y).get_luminance()
				lo = minf(lo, l)
				hi = maxf(hi, l)
		spread[kind] = hi - lo
	_check("a library material's picture shows under a layered effect, by UV and on three axes (%s)" % [spread],
			spread["uv"] > spread["colour"] + 0.2 and spread["triplanar"] > spread["colour"] + 0.2)


func _noise_checks() -> void:
	for path: String in NOISE:
		var bytes := FileAccess.get_file_as_bytes(path)
		var img := Image.new()
		var ok := img.load_png_from_buffer(bytes) == OK
		var size: int = NOISE[path][0]
		_check("%s is there, %d x %d, %d bytes (at most %d)" % [path.get_file(), img.get_width(), img.get_height(),
				bytes.size(), NOISE[path][1]], ok and img.get_width() == size and img.get_height() == size
				and bytes.size() <= int(NOISE[path][1]))
	var t := EffectLibrary.noise_texture(EffectLibrary.NOISE_FBM)
	_check("the fbm texture loads mipmapped", t != null and t.get_image().has_mipmaps())
	# fx_value's G is its R moved by (37, 17) texels, as fx_noise3x2 reads it.
	var v := Image.new()
	v.load_png_from_buffer(FileAccess.get_file_as_bytes(EffectLibrary.NOISE_VALUE))
	var moved := true
	for p in [Vector2i(0, 0), Vector2i(5, 60), Vector2i(40, 30), Vector2i(63, 63)]:
		var q := Vector2i((p.x + 37) % 64, (p.y + 17) % 64)
		if not is_equal_approx(v.get_pixelv(p).g, v.get_pixelv(q).r) or not is_equal_approx(v.get_pixelv(p).a,
				v.get_pixelv(q).b):
			moved = false
	_check("fx_value's next slice is its first moved by (37, 17)", moved)


func _command_checks() -> void:
	# The command host registers them with the rest (it needs the main scene; test_assistant.gd runs it whole).
	_check("the command host registers the effect commands", "EffectLibrary.register_commands(self)"
			in FileAccess.get_file_as_string("res://scripts/dev/command_host.gd"))
	EffectLibrary.register_commands(null)
	_check("effects and effect_info are registered, for the assistant to read",
			DevCommands.assistant_level("effects") == "read" and DevCommands.assistant_level("effect_info") == "read")
	var described := true
	for c in ["effects", "effect_info"]:
		for p: Dictionary in DevCommands.get_spec(c)["params"]:
			if str(p.get("description", "")).is_empty():
				described = false
	_check("their parameters are described", described)
	var r: Dictionary = await DevCommands.execute("effects", {}, true)
	var list: Array = r.get("result", {}).get("effects", [])
	_check("effects lists every effect (%d)" % list.size(), r.get("ok") == true
			and list.size() == EffectLibrary.ids().size()
			and r["result"]["photosensitivity"]["max_hz"] == EffectLibrary.MAX_HZ)
	r = await DevCommands.execute("effects", {"group": "classic"}, true)
	_check("effects filters by group", r["result"]["effects"].size() == 8)
	r = await DevCommands.execute("effects", {"surface": "sky"}, true)
	_check("effects filters by surface", r["result"]["effects"].all(func(x: Dictionary) -> bool:
			return x["surfaces"] == "sky"))
	r = await DevCommands.execute("effect_info", {"id": "pulse"}, true)
	var info: Dictionary = r.get("result", {})
	_check("effect_info gives the options, without the shader's wiring (%s)" % [info.keys()], r.get("ok") == true
			and info["options"]["rate"]["max"] == 3.0 and not info["options"]["rate"].has("uniform")
			and not info.has("define") and info["animates"] == true and info["preview"].ends_with("pulse.png"))
	r = await DevCommands.execute("effect_info", {"id": "strobe"}, true)
	_check("effect_info: an unknown id fails (%s)" % r.get("error", ""), r.get("ok") == false
			and "effects lists" in str(r.get("error", "")))


## Every effect compiles and draws: the sphere's middle is not the backdrop, and no shader error was logged.
func _render_checks(log: ShaderLog) -> void:
	await RenderingServer.frame_post_draw
	log.take()
	# The check itself: a shader with a mistake in it is caught.
	var broken := ShaderMaterial.new()
	broken.shader = Shader.new()
	broken.shader.code = "shader_type spatial;\nvoid fragment() { ALBEDO = vec3(no_such_thing); }\n"
	var vp := EffectLab.stage(Vector2i(16, 16), broken)
	root.add_child(vp)
	for i in 3:
		await RenderingServer.frame_post_draw
	vp.queue_free()
	_check("a shader with a mistake is caught", not log.take().is_empty())
	for id in EffectLibrary.ids():
		var img: Image = await EffectLab.preview(self, id, Vector2i(48, 48))
		var errors := log.take()
		var mid := img.get_pixel(24, 24) if img != null else Color.BLACK
		var drawn := img != null and not mid.is_equal_approx(img.get_pixel(0, 0))
		_check("%s compiles and draws%s" % [id, (": " + "; ".join(errors)) if not errors.is_empty() else ""],
				errors.is_empty() and (drawn or str(EffectLibrary.entry(id)["blend"]) in ["add", "alpha", "cutout"]))


## Each effect at its fastest options, 4 s at 30 pictures a second with its clock stepped: no pixel changes faster
## than a 3 Hz wave of the full swing would; a still effect not at all.
func _photosensitivity_measured() -> void:
	for id in EffectLibrary.ids():
		var e := EffectLibrary.entry(id)
		var animated := not (e["animation"] as Dictionary).is_empty()
		var opts := EffectLab.fastest_options(id)
		var frames: Array[Image] = await EffectLab.clip(self, id, opts, 4.0 if animated else 0.5)
		if frames.is_empty():
			continue
		var r := EffectLab.photo_check(frames)
		if animated:
			_check("%s at its fastest changes no faster than the ceiling (%d %%: %.2f of %.2f a second, swing %.2f, "
					% [id, int(r["of_ceiling"] * 100), r["slope"], r["max_slope"], r["swing"]]
					+ "%d pixels)" % r["pixels"], r["pixels"] > 50 and float(r["of_ceiling"]) <= 1.0)
		else:
			_check("%s is still (%.3f)" % [id, r["slope"]], float(r["slope"]) < 0.05)


## The first eight draw the same through the library as through the room builder: side by side in the same frame
## (the same clock), pixel for pixel.
func _classic_pixels() -> void:
	var bad: Array[String] = []
	for id: String in RoomSchema.EFFECTS:
		var a := ShaderMaterial.new()
		AssistantRoom._effect(a, {"name": id}, "part:" + id)
		a.set_shader_parameter("albedo", EffectLab.BASE_COLOR)
		var b := EffectLab.material(id, {}, EffectLab.BASE_COLOR)
		b.set_shader_parameter("fx_seed", EffectLibrary.seed_of("part:" + id))
		var va := EffectLab.stage(Vector2i(64, 64), a)
		var vb := EffectLab.stage(Vector2i(64, 64), b)
		root.add_child(va)
		root.add_child(vb)
		for i in 3:
			await RenderingServer.frame_post_draw
		var ia := va.get_texture().get_image()
		var ib := vb.get_texture().get_image()
		va.queue_free()
		vb.queue_free()
		if ia.get_data() != ib.get_data():
			bad.append(id)
	_check("the first eight draw as before, pixel for pixel%s" % (" (not: %s)" % ", ".join(bad) if not bad.is_empty()
			else ""), bad.is_empty())


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL " + what)
	else:
		print("PASS " + what)
