extends SceneTree

## The controllers' look (scripts/xr/controller_look.gd): every preset is complete and builds its shell material for
## each model (null only for the default); its effects are opaque single-pass part effects whose shader prints our
## model's legends (FX_PRINT), and its metals are in the material library; options validate against the effect
## library's bounds (the photosensitivity ceiling among them); the print stays legible on every preset (an ink that
## stands out from the shell's darkest and brightest, else a backing it stands out from); the look goes on the shell
## only, on the runtime's model, our model and the hand-built body, and the default puts each model's own material
## back; the setting round-trips through the settings; the controller_look command validates, applies, syncs the
## System tab and undoes. With a renderer, also: every preset's shaders compile and draw.
##   godot --headless --xr-mode off --path app --script res://tests/test_controller_look.gd
## With a renderer (WSL: lavapipe): VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a godot
##     --xr-mode off --path app --script res://tests/test_controller_look.gd

const ControllerLook := preload("res://scripts/xr/controller_look.gd")
const ControllerVisual := preload("res://scripts/xr/controller_visual.gd")
const EffectLibrary := preload("res://scripts/effects/effect_library.gd")
const EffectLab := preload("res://scripts/effects/effect_lab.gd")
const MaterialLibrary := preload("res://scripts/env/material_library.gd")
const ObjectSection := preload("res://ui/object_section.gd")
const DevCommands := preload("res://scripts/dev/dev_commands.gd")
const CommandHost := preload("res://scripts/dev/command_host.gd")
const LABEL_SHADER := preload("res://shaders/controller_label.gdshader")

## The shader files whose effects print our model's legends (they call fx_print).
const PRINTING_SHADERS: Array[String] = ["res://shaders/fx/fx_energy.gdshader", "res://shaders/fx/fx_nature.gdshader",
		"res://shaders/fx/fx_materials.gdshader"]

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


func _initialize() -> void:
	var log := ShaderLog.new()
	OS.add_logger(log)
	await process_frame
	_test_presets()
	_test_validate()
	_test_materials()
	_test_print_style()
	await _test_runtime_model()
	await _test_our_model()
	await _test_fallback()
	if EffectLab.has_renderer():
		await _test_render(log)
	else:
		print("No renderer: the shaders' compile check is skipped (run under xvfb-run with lavapipe)")
	await _test_settings_and_command()
	print("test_controller_look: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL " + what)


# --- The presets ----------------------------------------------------------------------------------------------------

func _test_presets() -> void:
	var ids := ControllerLook.ids()
	_check("the default is first and is black", ids[0] == "black" and ControllerLook.DEFAULT == "black")
	_check("a dozen or more looks (%d)" % ids.size(), ids.size() >= 12)
	var kinds := {}
	var printing := ""
	for path in PRINTING_SHADERS:
		printing += (load(path) as Shader).code
	for id in ids:
		var e := ControllerLook.entry(id)
		kinds[e["kind"]] = true
		_check("%s: named and described" % id, str(e.get("name", "")) != "" and str(e.get("description", "")).length() > 10)
		_check("%s: a known kind" % id, str(e["kind"]) in ["plastic", "metal", "effect"])
		_check("%s: its own options validate" % id, ControllerLook.validate(id, {}).is_empty())
		for word in ["valve", "steam", "index", "quest", "oculus", "xbox", "playstation", "switch", "joy-con"]:
			_check("%s: no product name (%s)" % [id, word], not word in (str(e["name"]) + " " + str(e["description"])).to_lower())
		match str(e["kind"]):
			"plastic":
				_check("%s: a colour" % id, Color.html_is_valid(str(e["color"])))
			"metal":
				_check("%s: %s is in the material library" % [id, e["material"]], MaterialLibrary.has(str(e["material"])))
				_check("%s: a repeat on the scale of a hand (%s m)" % [id, e["tiling"]],
						float(e["tiling"]) >= 0.03 and float(e["tiling"]) <= 0.3)
			"effect":
				var fx := EffectLibrary.entry(str(e["effect"]))
				_check("%s: %s is in the effect library" % [id, e["effect"]], not fx.is_empty())
				if fx.is_empty():
					continue
				_check("%s: a part effect, opaque, one pass (%s, %s, %d)" % [id, fx["surfaces"], fx["blend"], fx["passes"]],
						fx["surfaces"] == "any" and fx["blend"] == "opaque" and int(fx["passes"]) == 1)
				_check("%s: not heavy (%s)" % [id, fx["cost"]], fx["cost"] in ["light", "medium"])
				_check("%s: its preset options are within the library's bounds" % id,
						EffectLibrary.validate(str(e["effect"]), e["options"], "$").is_empty())
				_check("%s: its shader prints our model's legends" % id, str(fx["shader"]) in PRINTING_SHADERS)
				var spec: Dictionary = fx["options"]
				if spec.has("size"):
					_check("%s: sized for a hand-held shell (%s m)" % [id, ControllerLook.options_of(id, {}).get("size")],
							float(ControllerLook.options_of(id, {}).get("size", 1.0)) <= 0.15)
		var c := ControllerLook.cost(id)
		_check("%s: a cost (%s)" % [id, c], c["tier"] in ["light", "medium"] and int(c["passes"]) == 1)
	_check("plastics, metals and effects", kinds.has("plastic") and kinds.has("metal") and kinds.has("effect"))
	_check("plasma is among them", ids.has("plasma") and ControllerLook.entry("plasma")["effect"] == "plasma")
	_check("each printing shader calls fx_print once", PRINTING_SHADERS.all(func(p: String) -> bool:
			return (load(p) as Shader).code.count("fx_print(") == 1))
	var listing := ControllerLook.listing()
	_check("the listing has every look", listing.size() == ids.size())
	var plasma: Dictionary = listing.filter(func(l: Dictionary) -> bool: return l["id"] == "plasma")[0]
	_check("the listing gives an effect's options with bounds and the preset's defaults",
			plasma["options"]["speed"]["max"] == 1.0 and is_equal_approx(float(plasma["options"]["size"]["default"]), 0.12)
			and not (plasma["options"]["speed"] as Dictionary).has("uniform"))


func _test_validate() -> void:
	_check("an unknown look", _paths(ControllerLook.validate("chartreuse", {})) == ["$.look"])
	_check("options must be an object", _paths(ControllerLook.validate("plasma", "fast")) == ["$.options"])
	_check("plasma: speed within 0..1", ControllerLook.validate("plasma", {"speed": 0.2}).is_empty()
			and _paths(ControllerLook.validate("plasma", {"speed": 2.0})) == ["$.options.speed"])
	_check("plasma: an unknown option", _paths(ControllerLook.validate("plasma", {"glow": 1})) == ["$.options.glow"])
	_check("plasma: a colour", ControllerLook.validate("plasma", {"color": "#40c0ff", "color2": [0.1, 0.0, 0.3]}).is_empty()
			and _paths(ControllerLook.validate("plasma", {"color": "bright"})) == ["$.options.color"])
	var embers := ControllerLook.validate("embers", {"rate": 5.0})
	_check("embers: a rate past the photosensitivity ceiling says so (%s)" % [embers],
			_paths(embers) == ["$.options.rate"] and "photosensitivity" in str(embers[0]["error"]))
	_check("embers: a swing past the ceiling", not ControllerLook.validate("embers", {"swing": 0.6}).is_empty())
	_check("a plastic: any colour", ControllerLook.validate("colour", {"color": "#c0392b"}).is_empty()
			and _paths(ControllerLook.validate("colour", {"color": "#zz0000"})) == ["$.options.color"]
			and _paths(ControllerLook.validate("white", {"speed": 1})) == ["$.options.speed"])
	_check("a metal takes no options", _paths(ControllerLook.validate("steel", {"color": "#ffffff"})) == ["$.options.color"])


func _paths(errors: Array) -> Array:
	return errors.map(func(e: Dictionary) -> String: return str(e["path"]))


func _test_materials() -> void:
	var tex := ImageTexture.create_from_image(Image.create_empty(8, 8, true, Image.FORMAT_RGBA8))
	for id in ControllerLook.ids():
		for target in ["ours", "runtime", "fallback"]:
			var m := ControllerLook.material(id, {}, target, tex if target == "ours" else null)
			if id == ControllerLook.DEFAULT:
				_check("black: no material of its own (%s)" % target, m == null)
				continue
			_check("%s: a material for %s" % [id, target], m != null and m.shader != null)
			if m == null:
				continue
			_check("%s: marked as a look" % id, m.get_meta(&"controller_look", "") == id)
			var e := ControllerLook.entry(id)
			if e["kind"] == "effect":
				var printed := m.shader.code.contains("#define FX_PRINT")
				_check("%s: %s prints the legends: %s" % [id, target, printed], printed == (target == "ours"))
				_check("%s: self-lit, as the default" % id, m.get_shader_parameter("self_lit") == true)
			else:
				_check("%s: a finish on the model shader" % id, m.get_shader_parameter("use_finish") == true)
			if target == "ours":
				_check("%s: our model's legends read from its texture" % id, m.get_shader_parameter("use_print") == true
						and m.get_shader_parameter("print_texture") == tex)
	var steel := ControllerLook.material("steel", {}, "runtime")
	_check("steel: the library's picture, reflecting", steel.get_shader_parameter("use_pattern") == true
			and steel.get_shader_parameter("pattern") is Texture2D and float(steel.get_shader_parameter("reflection")) > 0.0)
	var given := ControllerLook.material("plasma", {"speed": 0.2, "color": "#40c0ff"}, "runtime")
	_check("plasma: the given options reach the shader", is_equal_approx(float(given.get_shader_parameter("fx_speed")), 0.2)
			and (given.get_shader_parameter("fx_color") as Color).is_equal_approx(Color("#40c0ff")))
	var mm := ControllerLook.material("plasma", {}, "runtime", null, 0.001)
	_check("a model in millimetres keeps the size in metres", is_equal_approx(float(mm.get_shader_parameter("fx_scale")), 120.0))


# --- Print legibility -----------------------------------------------------------------------------------------------

func _test_print_style() -> void:
	var black := ControllerLook.print_style("black")
	_check("black: white print, no backing, as always", black["ink"] == ControllerLook.INK_LIGHT and not black["backing_on"])
	for id in ControllerLook.ids():
		_legible(id, {})
	# Any colour a plastic can take: the palette's and a sweep of greys.
	for hex: String in ObjectSection.PALETTE:
		_legible("colour", {"color": hex})
	for i in 11:
		_legible("colour", {"color": Color(i / 10.0, i / 10.0, i / 10.0)})
	_check("white plastic: dark print without a backing", ControllerLook.print_style("white")["ink"] == ControllerLook.INK_DARK
			and not ControllerLook.print_style("white")["backing_on"])
	_check("plain dark plastics need no backing", ["graphite", "red", "blue"].all(func(id: String) -> bool:
			return not ControllerLook.print_style(id)["backing_on"]))
	_check("every effect gets the backing", ControllerLook.ids().filter(func(id: String) -> bool:
			return ControllerLook.entry(id)["kind"] == "effect").all(func(id: String) -> bool:
			return ControllerLook.print_style(id)["backing_on"]))
	var grey := ControllerLook.print_style("colour", {"color": "#7d7d7d"})
	_check("mid grey: a backing", grey["backing_on"])


## The print on a look stands out: without a backing, the ink against the shell's darkest and brightest; with one, the
## ink against the backing.
func _legible(id: String, options: Dictionary) -> void:
	var s := ControllerLook.print_style(id, options)
	var what := "%s %s" % [id, options]
	if bool(s["backing_on"]):
		_check("%s: ink against its backing %.1f" % [what, ControllerLook.contrast(s["ink"], s["backing"])],
				ControllerLook.contrast(s["ink"], s["backing"]) >= ControllerLook.INK_CONTRAST)
	else:
		var span := ControllerLook.body_range(id, ControllerLook.options_of(id, options))
		var ink := ControllerLook.luminance(s["ink"])
		var worst := minf(ControllerLook._contrast_lum(ink, span.x), ControllerLook._contrast_lum(ink, span.y))
		_check("%s: ink against the shell at least %.1f (%.2f)" % [what, ControllerLook.MIN_CONTRAST, worst],
				worst >= ControllerLook.MIN_CONTRAST)


# --- On the models --------------------------------------------------------------------------------------------------

func _flat(size: Vector2) -> PlaneMesh:
	var p := PlaneMesh.new()
	p.size = size
	return p


## A runtime-like model: a body (the shell), a battery door and a button. The print lies on the body; the look goes on
## the shell, the button keeps its own, and its print stays white. Black puts the body's own material back.
func _test_runtime_model() -> void:
	var model := Node3D.new()
	model.name = "Model"
	root.add_child(model)
	var own := StandardMaterial3D.new()
	var body := _part("body", _flat(Vector2(0.1, 0.1)), model)
	body.material_override = own
	var door := _part("battery_door", _flat(Vector2(0.02, 0.02)), model)
	door.position = Vector3(0.0, -0.01, 0.03)
	var button := _part("button_a", _flat(Vector2(0.01, 0.01)), model)
	button.position = Vector3(0.0, 0.002, -0.02)
	var hand := Node3D.new()
	root.add_child(hand)
	var visual: Node3D = ControllerVisual.new()
	hand.add_child(visual)
	visual.configure("right")
	visual.use_layout = false
	visual.attach_render_model(model)
	visual.set_texts({"system": "HOME"})
	await process_frame
	var unlit_body := body.material_override
	var button_mat := button.get_active_material(0)
	_check("the body is made unlit as before", unlit_body is ShaderMaterial)
	visual.set_look("white")
	var print_mesh := body.find_child("Print", false, false) as MeshInstance3D
	_check("white: the body takes the look", body.material_override != unlit_body
			and body.material_override.get_meta(&"controller_look", "") == "white")
	_check("white: the battery door too", door.material_override == body.material_override)
	_check("white: the button keeps its own", button.material_override == null and button.get_active_material(0) == button_mat)
	_check("the print lies on the body", print_mesh != null)
	if print_mesh != null:
		var pm := print_mesh.material_override as ShaderMaterial
		_check("white: the print is dark, no backing", (pm.get_shader_parameter("ink") as Color) == ControllerLook.INK_DARK
				and float(pm.get_shader_parameter("backing_width")) == 0.0)
		_check("the print's shader is the label shader", pm.shader == LABEL_SHADER)
	visual.set_look("plasma", {"speed": 0.2})
	_check("plasma: the body takes the effect", (body.material_override as ShaderMaterial).shader.code.contains("FX_PLASMA"))
	if print_mesh != null:
		var pm := print_mesh.material_override as ShaderMaterial
		_check("plasma: white print with a dark backing", (pm.get_shader_parameter("ink") as Color) == ControllerLook.INK_LIGHT
				and float(pm.get_shader_parameter("backing_width")) > 0.0)
	# The runtime may hand over its scene again: the look stays.
	visual.attach_render_model(model)
	await process_frame
	_check("plasma: kept when the model is attached again", (body.material_override as ShaderMaterial).shader.code.contains("FX_PLASMA"))
	# The print is laid again on the model attached again: new meshes, in the look's ink at once.
	var laid := body.get_children().filter(func(n: Node) -> bool:
			return n.has_meta(&"controller_print") and not n.is_queued_for_deletion())
	print_mesh = laid[0] as MeshInstance3D if laid.size() == 1 else null
	_check("the new print takes the look's backing", print_mesh != null and float((print_mesh.material_override
			as ShaderMaterial).get_shader_parameter("backing_width")) > 0.0)
	visual.set_look("black")
	_check("black: the body's own material back", body.material_override == unlit_body)
	if print_mesh != null and is_instance_valid(print_mesh):
		_check("black: the print as always", print_mesh.material_override == ControllerVisual._label_material())
	_check("the look reads back", visual.look()["id"] == "black")
	hand.free()
	model.free()


func _part(part_name: String, mesh: Mesh, parent: Node) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = mesh
	parent.add_child(mi)
	return mi


## Our model: the shell takes the look with its legends from the texture on show; the other parts keep theirs.
func _test_our_model() -> void:
	var hand := Node3D.new()
	root.add_child(hand)
	var visual: Node3D = ControllerVisual.new()
	hand.add_child(visual)
	visual.configure("right")
	if not visual.use_our_model():
		print("Our model isn't there: skipped")
		hand.free()
		return
	var ours: Node3D = visual._ours
	var shell: Array = visual._shell_meshes(ours)
	_check("our model has a shell (%d meshes)" % shell.size(), not shell.is_empty())
	var body := ours.find_child("body", true, false) as MeshInstance3D
	_check("its body is the shell", body != null and shell.has(body))
	visual.set_look("cold_plasma")
	var look := body.material_override as ShaderMaterial if body != null else null
	_check("cold plasma on our shell, printing its legends", look != null and look.shader.code.contains("FX_PRINT")
			and look.get_shader_parameter("use_print") == true
			and look.get_shader_parameter("print_texture") == visual._print_texture())
	var others := ours.find_children("*", "MeshInstance3D", true, false).filter(func(mi: Node) -> bool:
			return not shell.has(mi))
	_check("the other parts keep the model's own", others.all(func(mi: MeshInstance3D) -> bool:
			return mi.material_override == visual._ours_material))
	visual.set_print_state("menu")
	if look != null:
		_check("the menu's legends follow", look.get_shader_parameter("print_texture") == visual._ours_textures.get("menu",
				visual._ours_textures["normal"]))
	var normal: Texture2D = visual._ours_textures["normal"]
	_check("the texture has its mip levels (the backing reads them)", normal.get_image().has_mipmaps())
	visual.set_look("white")
	_check("white on our shell: dark ink", body != null and ((body.material_override as ShaderMaterial).get_shader_parameter(
			"print_ink") as Color) == ControllerLook.INK_DARK)
	visual.set_look("black")
	_check("black: our model's own material back", body != null and body.material_override == visual._ours_material)
	_check("the print meshes stay off on our model", visual.find_children("Print", "MeshInstance3D", true, false).is_empty())
	hand.free()


func _test_fallback() -> void:
	var hand := Node3D.new()
	root.add_child(hand)
	var visual: Node3D = ControllerVisual.new()
	hand.add_child(visual)
	visual.configure("left")
	var own: Material = visual._body.material_override
	visual.set_look("starfield")
	_check("the hand-built body takes the look", visual._body.material_override != own
			and visual._body.material_override.get_meta(&"controller_look", "") == "starfield")
	_check("and is its shell", visual._is_shell(visual._body))
	visual.set_look("black")
	_check("and gets its own back", visual._body.material_override == own)
	visual.set_look("no_such_look")
	_check("an unknown look is the default", visual.look()["id"] == "black")
	hand.free()


# --- With a renderer ------------------------------------------------------------------------------------------------

## Every preset's material on a sphere for each model, and the print with a backing: no shader error, something drawn.
func _test_render(log: ShaderLog) -> void:
	EffectLab.set_room(self)
	var tex := ImageTexture.create_from_image(Image.create_empty(16, 16, true, Image.FORMAT_RGBA8))
	var stages: Array[SubViewport] = []
	var names: Array[String] = []
	for id in ControllerLook.ids():
		for target in ["ours", "runtime"]:
			var m := ControllerLook.material(id, {}, target, tex if target == "ours" else null)
			if m == null:
				continue
			var vp := EffectLab.stage(Vector2i(48, 48), m)
			root.add_child(vp)
			stages.append(vp)
			names.append("%s/%s" % [id, target])
	var label := ControllerVisual._label_material().duplicate() as ShaderMaterial
	label.set_shader_parameter("backing_width", ControllerLook.BACKING_WIDTH)
	var lvp := EffectLab.stage(Vector2i(48, 48), label)
	root.add_child(lvp)
	stages.append(lvp)
	names.append("label")
	for i in 4:
		await RenderingServer.frame_post_draw
	var errors := log.take()
	_check("no shader errors (%s)" % [errors], errors.is_empty())
	for i in stages.size() - 1:
		var img := stages[i].get_texture().get_image()
		var c := img.get_pixel(24, 24)
		_check("%s draws (%s)" % [names[i], c], c.a > 0.5 and not c.is_equal_approx(Color(0.1, 0.105, 0.12)))
	for vp in stages:
		vp.queue_free()


# --- The setting and the command ------------------------------------------------------------------------------------

func _test_settings_and_command() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	current_scene = main
	for i in 5:
		await process_frame
	_check("a new install starts with red liquid chrome", main.controller_look == "liquid_chrome"
			and main.controller_look_options == {"color": "#c0392b"})
	_check("a bad look is refused and changes nothing", main.set_controller_look("plasma", {"speed": 9}) != ""
			and main.controller_look == "liquid_chrome")
	_check("a look is set", main.set_controller_look("cold_plasma", {"speed": 0.2}) == "")
	_check("it is kept in the settings", main.settings.get_value("controllers", "look", "") == "cold_plasma"
			and main.settings.get_value("controllers", "look_options", {}) == {"speed": 0.2})
	_check("both hands show it", main.hands.all(func(h: Node) -> bool: return h.visual.look()["id"] == "cold_plasma"))
	main.controller_look = "black"
	main.controller_look_options = {}
	main.load_controller_look()
	_check("it reads back from the settings", main.controller_look == "cold_plasma"
			and main.controller_look_options == {"speed": 0.2})
	main.settings.set_value("controllers", "look", "plasma")
	main.settings.set_value("controllers", "look_options", {"speed": 7.0})
	main.load_controller_look()
	_check("a saved look out of bounds reads as the default", main.controller_look == "black")
	_check("black is kept when chosen", main.set_controller_look("black") == ""
			and main.settings.get_value("controllers", "look", "") == "black")
	_check("the initial look leaves nothing in the settings",
			main.set_controller_look("liquid_chrome", {"color": "#c0392b"}) == ""
			and not main.settings.has_value("controllers", "look")
			and not main.settings.has_value("controllers", "look_options"))

	CommandHost.ensure(self)
	for i in 2:
		await process_frame
	for c in ["controller_looks", "controller_look"]:
		_check("%s is registered for the assistant" % c, DevCommands.has_command(c)
				and DevCommands.get_spec(c).get("assistant") == ("read" if c == "controller_looks" else "settings"))
	var r: Dictionary = await DevCommands.execute("controller_looks", {}, true)
	_check("controller_looks lists them", r["ok"] and (r["result"]["looks"] as Array).size() == ControllerLook.ids().size())
	r = await DevCommands.execute("controller_look", {"look": "plasma", "options": {"color": "#40c0ff", "speed": 0.2}}, true)
	_check("controller_look: applied (%s)" % [r.get("error", "")], r["ok"] and main.controller_look == "plasma"
			and main.hands.all(func(h: Node) -> bool: return h.visual.look()["id"] == "plasma"))
	_check("controller_look: says how the print is kept", r["ok"] and r["result"]["print"]["backing"] == true)
	var tab: Node = _system_tab(main)
	if tab != null:
		var pressed: Array = tab._look_grid.get_children().filter(func(b: Button) -> bool: return b.button_pressed)
		_check("the System tab follows", pressed.size() == 1 and pressed[0].get_meta("look") == "plasma")
		_check("the tab offers plasma's colour and speed", tab._look_colours.visible and tab._look_speed.visible)
	var st: Dictionary = (await DevCommands.execute("system_settings", {}, true))["result"]
	_check("system_settings names it", st["controller_look"]["look"] == "plasma")
	var bad: Dictionary = await DevCommands.execute("controller_look", {"look": "plasma", "options": {"speed": 3}}, true)
	_check("controller_look: out of bounds refused with its path (%s)" % [bad.get("error")], not bad["ok"]
			and "$.options.speed" in str(bad["error"]) and main.controller_look == "plasma")
	bad = await DevCommands.execute("controller_look", {"look": "gold_sparkle"}, true)
	_check("controller_look: an unknown look refused", not bad["ok"])
	(r["call"] as DevCommands.Call).undo.call()
	_check("controller_look: undo (back to the initial look)", main.controller_look == "liquid_chrome")
	main.queue_free()
	for i in 2:
		await process_frame


func _system_tab(main: Node) -> Node:
	var layer: Node = main.get("ui")
	var pane: Node = layer.get("ui") if layer != null else null
	return pane.get("system") if pane != null else null
