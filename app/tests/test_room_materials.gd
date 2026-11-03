extends SceneTree

## The material library in the assistant's rooms (docs/assistant.md "Objects" and "recolour", docs/materials.md) in
## the real main scene: the room document's library_material with its options (checked, merged, costed); a part, a
## sphere, a placed object, one part of it and a base room surface taking a library material through recolour, all
## drawn with the library's shared ShaderMaterial; colour, tint, tiling and emission on top, reset, an unknown id's
## warning; room_state reporting the material ids and colours; the kept room saved and built again; a room with real
## lighting drawing the materials lit (its base's too); and the Objects tab's material picker with its kinds and Undo.
## And the effect library connected (docs/effects.md, "Connecting it"): the schema's effects derived from it and
## checked by it, its costs, a part's effect, a reactive one's film path, a layered look over a library material, the
## sizes filled in from a part's extent, a sky effect, room_state naming effects, and the Objects tab's effect picker.
## godot --headless --xr-mode off --path app --script res://tests/test_room_materials.gd

const DevCommands := preload("res://scripts/dev/dev_commands.gd")
const CommandHost := preload("res://scripts/dev/command_host.gd")
const AssistantCommands := preload("res://scripts/assistant/assistant_commands.gd")
const ObjectLibrary := preload("res://scripts/assistant/object_library.gd")
const ObjectCommands := preload("res://scripts/assistant/object_commands.gd")
const RoomModel := preload("res://scripts/assistant/room_model.gd")
const RoomSchema := preload("res://scripts/assistant/room_schema.gd")
const AssistantRoom := preload("res://scripts/assistant/assistant_room.gd")
const RoomEditor := preload("res://scripts/assistant/room_editor.gd")
const MaterialLibrary := preload("res://scripts/env/material_library.gd")
const EffectLibrary := preload("res://scripts/effects/effect_library.gd")

const ROOM := "Test room materials"

var _failures := 0
var _checks := 0
var main: Node3D
var commands: AssistantCommands


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _run() -> void:
	await _frames(5)
	CommandHost.ensure(self)
	await _frames(2)
	_cleanup()
	ObjectLibrary.editor_for(self).set("perf_after_change", false)
	commands = AssistantCommands.new()
	commands.allow_room = func() -> bool: return true
	commands.room = RoomEditor.new()
	commands.room.perf_after_change = false
	root.add_child(commands.room)

	_test_schema()
	_test_command_spec()
	await _test_parts()
	await _test_objects()
	await _test_kept()
	await _test_lit()
	await _test_picker()
	_test_effect_schema()
	await _test_effects()
	await _test_effect_picker()
	_cleanup()
	main.queue_free()
	await _frames(2)
	print("test_room_materials: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


# --- The document --------------------------------------------------------------------------------------------------

func _test_schema() -> void:
	var ok := RoomSchema.validate({"schema": 2, "parts": [{"name": "a", "type": "box", "size": [1, 1, 1],
			"material": {"library_material": "oak_planks", "color": "#806040", "tint": "#ffffff", "tiling": 1.5,
			"triplanar": false, "emission": "#100800"}}]}, "patch")
	_check("a part with a library material and its options (%s)" % [ok["errors"]], ok["ok"])
	var paths := func(d: Dictionary) -> Array:
		return (RoomSchema.validate(d, "patch")["errors"] as Array).map(func(e: Dictionary) -> String:
			return e["path"])
	var bad: Array = paths.call({"schema": 2, "parts": [
		{"name": "a", "type": "box", "size": [1, 1, 1], "material": {"tint": "#ff0000"}},
		{"name": "b", "type": "box", "size": [1, 1, 1], "material": {"library_material": "velvet", "texture": "AAAA"}},
		{"name": "c", "type": "box", "size": [1, 1, 1], "material": {"library_material": "velvet", "tiling": 100}},
		{"name": "d", "type": "box", "size": [1, 1, 1], "material": {"library_material": "Velvet!"}},
		{"name": "e", "type": "box", "size": [1, 1, 1], "material": {"library_material": "felt", "triplanar": "yes"}}]})
	_check("each problem at its path (%s)" % [bad], bad.has("$.parts[0].material.tint")
			and bad.has("$.parts[1].material.library_material") and bad.has("$.parts[2].material.tiling")
			and bad.has("$.parts[3].material.library_material") and bad.has("$.parts[4].material.triplanar"))
	var layered: Array = paths.call({"schema": 2, "recolour": [{"match": "Sofa/Seat", "material": {"tint": "#ff8080"}},
			{"match": "Wall*", "material": {"tiling": 2}}]})
	_check("a part-level entry may tint its object's material; a base surface's entry may not (%s)" % [layered],
			layered == ["$.recolour[1].material.tiling"])
	var v1 := RoomSchema.validate({"schema": 1, "parts": [{"name": "a", "type": "box", "size": [1, 1, 1],
			"material": {"library_material": "felt"}}]}, "patch")
	_check("schema 1 has no library materials", not v1["ok"] and str(v1["errors"]).contains("schema"))

	# merge_material: a new library material shows as itself; colour, tint, tiling change it; a picture replaces it.
	var m := RoomSchema.merge_material({"color": "#ff0000", "texture": "AAAA", "emission": "#101010"},
			{"library_material": "velvet"})
	_check("a library material drops the picture and the old colour, keeps the emission (%s)" % m,
			m == {"library_material": "velvet", "emission": "#101010"})
	m = RoomSchema.merge_material(m, {"color": "#203040", "tiling": 0.5})
	_check("a colour and tiling on it change it", m["library_material"] == "velvet" and m["color"] == "#203040"
			and is_equal_approx(m["tiling"], 0.5))
	m = RoomSchema.merge_material(m, {"library_material": "felt"})
	_check("another library material: its own colour and tiling again", m == {"library_material": "felt",
			"emission": "#101010"})
	m = RoomSchema.merge_material(m, {"texture": "AAAA"})
	_check("a picture replaces it", not m.has("library_material") and m["texture"] == "AAAA")
	var plain := RoomSchema.part_cost({"type": "box", "size": [1, 1, 1], "material": {"color": "#ffffff"}})
	var lib := RoomSchema.part_cost({"type": "box", "size": [1, 1, 1], "material": {"library_material": "felt"}})
	var tri := RoomSchema.part_cost({"type": "box", "size": [1, 1, 1], "material": {"library_material": "felt",
			"triplanar": true}})
	_check("a library material costs more than a colour, triplanar more again (%s, %s, %s)" % [plain, lib, tri],
			lib > plain and tri > lib)


func _test_command_spec() -> void:
	var spec: Dictionary = DevCommands.get_spec("recolour")
	var params := {}
	for p: Dictionary in spec.get("params", []):
		params[p["name"]] = p
	_check("recolour: material, tint, tiling, triplanar, described", params.has("material") and params.has("tint")
			and params.has("tiling") and params.has("triplanar") and str(params["tint"]["description"]) != ""
			and str(params["tiling"]["description"]) != "")
	_check("its material says where the ids are (the materials command) and the kinds",
			str(params["material"]["description"]).contains("materials command")
			and str(params["material"]["description"]).contains("leather"))
	_check("the materials command is there for the assistant", DevCommands.assistant_level("materials") == "read")


# --- Parts, recolour, room_state -------------------------------------------------------------------------------------

func _test_parts() -> void:
	main.set_environment("dim_room")
	await _frames(3)
	var r: Dictionary = await commands.run("new_room", {"room": {"schema": 2, "name": ROOM, "base": "dim_room",
		"parts": [
			{"name": "Crate A", "type": "box", "size": [0.6, 0.6, 0.6], "position": [-1, 0.3, -2],
				"material": {"library_material": "oak_planks"}},
			{"name": "Crate B", "type": "box", "size": [0.6, 0.6, 0.6], "position": [1, 0.3, -2],
				"material": {"library_material": "oak_planks"}},
			{"name": "Ball", "type": "sphere", "size": [0.5], "position": [0, 0.25, -2.5],
				"material": {"library_material": "velvet"}}]}})
	_check("a room with library materials (%s)" % r.get("error", r.get("errors", "")), r.get("ok") == true)
	if r.get("ok") != true:
		return
	var a := _material_of("Crate A")
	var shared := MaterialLibrary.get_material("oak_planks", {})
	_check("a part draws with the library's shared ShaderMaterial", a != null and a == shared
			and a.shader == MaterialLibrary.SHADER)
	_check("two parts with the same material share it", _material_of("Crate B") == a)
	var ball := _material_of("Ball")
	_check("a sphere: its UVs, whole repeats round it (%s)" % [ball.get_shader_parameter("uv_repeat") if ball != null
			else null], ball != null and MaterialLibrary.id_of(ball) == "velvet"
			and ball.get_shader_parameter("use_mesh_uv") == true
			and is_equal_approx(fmod((ball.get_shader_parameter("uv_repeat") as Vector2).x, 1.0), 0.0))
	_check("its mesh casts the key light's shadow as a solid part", (main.env.get_node("%s/Crate A/Mesh"
			% AssistantRoom.LAYER) as MeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON)

	# Colour on top: the material shows that colour on average, its pattern kept; the other crate unchanged.
	r = await commands.run("recolour", {"match": "Crate A", "color": "#a04030"})
	a = _material_of("Crate A")
	_check("recolour color on a library part keeps the material (%s)" % r.get("error", ""), r.get("ok") == true
			and MaterialLibrary.id_of(a) == "oak_planks" and a != shared and _material_of("Crate B") == shared)
	var doc_mat: Dictionary = _doc_part("Crate A").get("material", {})
	_check("the document: the id and the colour (%s)" % doc_mat, doc_mat.get("library_material") == "oak_planks"
			and doc_mat.get("color") == "#a04030")
	var st: Dictionary = (await commands.run("room_state", {}))["result"]
	_check("_colour_of: the colour it shows (%s)" % _colour("Crate A"), Color.html(_colour("Crate A"))
			.is_equal_approx(Color.html("#a04030")) or _close(Color.html(_colour("Crate A")), Color.html("#a04030")))
	r = await commands.run("recolour", {"match": "Crate A", "tint": "#808080", "tiling": 0.5,
			"emission": "#201000", "emission_strength": 2.0})
	a = _material_of("Crate A")
	_check("tint, tiling and emission on top (%s)" % r.get("error", ""), r.get("ok") == true
			and MaterialLibrary.id_of(a) == "oak_planks" and is_equal_approx(a.get_shader_parameter("tiling"), 0.5)
			and (a.get_shader_parameter("emission") as Color).is_equal_approx(Color.html("#201000") * 2.0)
			and _doc_part("Crate A")["material"].get("color") == "#a04030")
	var before := Color.html(_colour("Crate A"))
	_check("the tint darkens what it shows", before.v < Color.html("#a04030").v)
	r = await commands.run("recolour", {"match": "Crate B", "material": "velvet"})
	_check("recolour material on a part: another library material", r.get("ok") == true
			and MaterialLibrary.id_of(_material_of("Crate B")) == "velvet")
	r = await commands.run("recolour", {"match": "Crate B", "texture": _png_b64()})
	_check("a picture replaces it", r.get("ok") == true and MaterialLibrary.id_of(_material_of("Crate B")) == ""
			and not (_doc_part("Crate B")["material"] as Dictionary).has("library_material"))
	r = await commands.run("recolour", {"match": "Crate B", "tint": "#ff0000"})
	_check("tint without a library material is refused (%s)" % r.get("error", r.get("errors", "")),
			r.get("ok") == false and str(r).contains("only with library_material"))
	r = await commands.run("recolour", {"match": "Crate A", "reset": true})
	_check("reset: the library material goes", r.get("ok") == true and MaterialLibrary.id_of(_material_of("Crate A"))
			== "" and not _doc_part("Crate A").has("material"))

	# An unknown id: warned, the rest applies.
	r = await commands.run("recolour", {"match": "Crate A", "material": "no_such_wood", "color": "#3366cc"})
	var kinds: Array = (r.get("result", {}).get("warnings", []) as Array).map(func(w: Dictionary) -> String:
		return w["kind"])
	_check("an unknown id: a warning naming the materials command, the colour applies (%s)" % [kinds],
			r.get("ok") == true and kinds.has("unknown_material")
			and str(r["result"]["warnings"]).contains("materials command")
			and (_material_of("Crate A").get_shader_parameter("albedo") as Color).is_equal_approx(Color.html("#3366cc")))

	# A base room surface: the dim room's plaster is reported, and recolour reaches it.
	var plaster := ""
	for s: Dictionary in st["stock_parts"]:
		if s.get("material", "") == "smooth_plaster":
			plaster = s["name"]
	_check("room_state's stock parts give their library material (%s)" % plaster, plaster != "")
	if plaster != "":
		r = await commands.run("recolour", {"match": plaster, "material": "red_brick", "tiling": 1.2})
		st = (await commands.run("room_state", {}))["result"]
		var now := ""
		for s: Dictionary in st["stock_parts"]:
			if s["name"] == plaster:
				now = str(s.get("material", ""))
		_check("recolour material on a base surface (%s, %s)" % [r.get("error", ""), now], r.get("ok") == true
				and now == "red_brick")
		r = await commands.run("recolour", {"match": plaster, "color": "#c0c0c0"})
		var entry: Dictionary = {}
		for e: Dictionary in main.env.get("doc")["recolour"]:
			if e["match"] == plaster:
				entry = e["material"]
		_check("a colour on it keeps the material and its tiling (%s)" % entry, r.get("ok") == true
				and entry.get("library_material") == "red_brick" and is_equal_approx(float(entry.get("tiling", 0)), 1.2)
				and entry.get("color") == "#c0c0c0")


# --- Placed objects ------------------------------------------------------------------------------------------------

func _test_objects() -> void:
	var r := await DevCommands.execute("object_place", {"id": "pot_plant", "position": [0, 0, -1.5]}, false)
	_check("a pot plant placed (%s)" % r.get("error", ""), r["ok"])
	if not r["ok"]:
		return
	await _wait_room()
	var a: Dictionary = await commands.run("recolour", {"match": "Pot plant/Pot", "material": "terrazzo"})
	var pot := _part_material("Pot plant", "Pot")
	_check("one part of a placed object takes a library material (%s)" % a.get("error", ""), a.get("ok") == true
			and pot == MaterialLibrary.get_material("terrazzo", {}))
	_check("its other parts keep theirs", MaterialLibrary.id_of(_part_material("Pot plant", "Leaves")) == "")
	var objects: Array = (await commands.run("room_state", {}))["result"]["objects"]
	var said := {}
	for o: Dictionary in objects:
		if o["name"] == "Pot plant":
			for q: Dictionary in o["parts"]:
				said[q["name"]] = q
	_check("room_state's objects: the part's material id and colour (%s)" % said.get("Pot"),
			said.get("Pot", {}).get("material") == "terrazzo" and said.get("Leaves", {}).get("material") == ""
			and _close(Color.html(str(said["Pot"]["color"])), Color.html(str(MaterialLibrary.entry("terrazzo")["swatch"]))))
	a = await commands.run("recolour", {"match": "Pot plant/Pot", "color": "#405060"})
	pot = _part_material("Pot plant", "Pot")
	_check("a colour on that part keeps its material (%s)" % a.get("error", ""), a.get("ok") == true
			and MaterialLibrary.id_of(pot) == "terrazzo"
			and _close(MaterialLibrary.shown_colour(pot), Color.html("#405060")))
	a = await commands.run("recolour", {"match": "Pot plant", "material": "wicker"})
	_check("the whole object: every part the material, its part-level entries gone (%s)" % a.get("error", ""),
			a.get("ok") == true and _part_material("Pot plant", "Pot") == MaterialLibrary.get_material("wicker", {})
			and _part_material("Pot plant", "Leaves") == _part_material("Pot plant", "Pot")
			and not _has_entry("Pot plant/Pot"))
	a = await commands.run("recolour", {"match": "Pot plant/Leaves", "tint": "#60a060"})
	_check("a tint on one part of a library object (%s)" % a.get("error", a.get("errors", "")), a.get("ok") == true
			and MaterialLibrary.id_of(_part_material("Pot plant", "Leaves")) == "wicker"
			and _part_material("Pot plant", "Leaves") != _part_material("Pot plant", "Pot"))
	a = await commands.run("recolour", {"match": "Pot plant", "reset": true})
	_check("reset the object: its own colours", a.get("ok") == true
			and MaterialLibrary.id_of(_part_material("Pot plant", "Pot")) == "")


# --- Kept and built again ------------------------------------------------------------------------------------------

func _test_kept() -> void:
	var a: Dictionary = await commands.run("recolour", {"match": "Crate A", "material": "oak_planks"})
	a = await commands.run("recolour", {"match": "Pot plant/Pot", "material": "velvet", "color": "#802030"})
	_check("set up for the kept room", a.get("ok") == true)
	var path := AssistantRoom.json_path(ROOM)
	var text := FileAccess.get_file_as_string(path)
	_check("the kept file names the materials", text.contains("\"library_material\": \"oak_planks\"")
			and text.contains("\"library_material\": \"velvet\""))
	var room := AssistantRoom.load_saved(path)
	_check("built again from the kept file", room != null)
	if room == null:
		return
	root.add_child(room)
	var crate := room.get_node_or_null("%s/Crate A/Mesh" % AssistantRoom.LAYER) as MeshInstance3D
	_check("the part: the same shared library material again", crate != null
			and crate.material_override == MaterialLibrary.get_material("oak_planks", {}))
	var pot: MeshInstance3D = AssistantRoom.part_targets(room.get_node(AssistantRoom.LAYER), "Pot plant/Pot")[0]
	_check("the object's part: its material and colour again", MaterialLibrary.id_of(pot.material_override) == "velvet"
			and _close(MaterialLibrary.shown_colour(pot.material_override), Color.html("#802030")))
	room.queue_free()
	await _frames(2)


# --- Real lighting -------------------------------------------------------------------------------------------------

func _test_lit() -> void:
	var r: Dictionary = await commands.run("room_apply", {"room": {"schema": 2, "light": {
			"key": {"elevation": 50, "shadows": false}, "sky": {"top": "#506080", "energy": 0.4}}}})
	_check("the room lit (%s)" % r.get("error", ""), r.get("ok") == true and RoomSchema.is_lit(main.env.get("doc")))
	var a := _material_of("Crate A")
	_check("a library part in its lit form", a != null and a.shader == MaterialLibrary.SHADER_LIT
			and MaterialLibrary.id_of(a) == "oak_planks" and (a.get_shader_parameter("sky_top") as Color).r > 0.0)
	_check("lit parts share it too", _material_of("Crate A") == MaterialLibrary.get_material("oak_planks",
			{"lit": {"sky_top": a.get_shader_parameter("sky_top"), "sky_bottom": a.get_shader_parameter("sky_bottom"),
			"screen": a.get_shader_parameter("screen_light")}}))
	var pot := _part_material("Pot plant", "Pot")
	_check("an object's part lit (%s)" % [pot.shader.resource_path if pot != null else null], pot != null
			and pot.shader == MaterialLibrary.SHADER_LIT and MaterialLibrary.id_of(pot) == "velvet")
	var base_lit := 0
	for g in (main.env.get_node("Base") as Node).find_children("*", "MeshInstance3D", true, false):
		var m: Material = (g as MeshInstance3D).material_override
		if m is ShaderMaterial and (m as ShaderMaterial).shader == MaterialLibrary.SHADER_LIT:
			base_lit += 1
	_check("the base room's library surfaces lit too (%d)" % base_lit, base_lit > 0)
	_check("room_state still names the materials", ((await commands.run("room_state", {}))["result"]["stock_parts"]
			as Array).any(func(s: Dictionary) -> bool: return s.get("material", "") == "red_brick"))
	r = await commands.run("room_apply", {"room": {"schema": 2, "light": {"key": null, "sky": null}}})
	_check("unlit again: the plain library shader (%s, %s)" % [r.get("error", r.get("errors", "")),
			_material_of("Crate A").shader.resource_path if _material_of("Crate A") != null else null], r.get("ok") == true
			and _material_of("Crate A") == MaterialLibrary.get_material("oak_planks", {}))


# --- The Objects tab's picker ---------------------------------------------------------------------------------------

func _test_picker() -> void:
	var layer: Node = main.ui
	# The tiles' thumbnails made here first, so the tab's worker has nothing to build while the room changes.
	for m: Dictionary in ObjectLibrary.list():
		ObjectLibrary.thumbnail(str(m["id"]))
	layer.show_panel()
	layer.ui.show_tab(layer.ui.Tab.OBJECTS)
	var section: Node = layer.ui.objects.section
	section.sync_objects()
	# The library's tiles are made on a worker thread: let it finish before the room changes again.
	for i in 600:
		await process_frame
		if not section._ids.is_empty() and not section._loading:
			break
	var row: Button = null
	for b: Button in section._placed_box.get_children():
		if b.text == "Pot plant":
			row = b
	_check("the pot plant is listed", row != null)
	if row == null:
		return
	row.emit_signal("pressed")
	var material_button: Button = null
	for b: Button in section._parts_box.find_children("*", "Button", true, false):
		if b.text == "Material":
			material_button = b
			break
	_check("a part has a Material button", material_button != null)
	if material_button == null:
		return
	material_button.emit_signal("pressed")
	var choices := _picker_buttons(section)
	_check("Material opens the picker: every material with its swatch (%d)" % choices.size(),
			choices.size() == MaterialLibrary.list().size() and choices.all(func(b: Button) -> bool:
				return b.icon != null))
	var kinds: Array = section._parts_box.find_children("*", "Button", true, false).filter(func(b: Button) -> bool:
		return b.text in ["All", "Floors", "Walls", "Fabric", "Wood", "Leather", "Metal", "Stone"])
	_check("its kinds (%d)" % kinds.size(), kinds.size() == 8)
	var fabric: Button = kinds.filter(func(b: Button) -> bool: return b.text == "Fabric")[0]
	fabric.emit_signal("pressed")
	choices = _picker_buttons(section)
	_check("Fabric: only fabrics (%d)" % choices.size(), choices.size() > 3 and choices.all(func(b: Button) -> bool:
		return "fabric" in MaterialLibrary.entry(str(b.get_meta("material")))["tags"]))
	var velvet_pressed := choices.filter(func(b: Button) -> bool: return b.get_meta("material") == "velvet")
	_check("the material the part shows is pressed", velvet_pressed.size() == 1 and (velvet_pressed[0] as Button)
			.button_pressed)
	var linen: Button = choices.filter(func(b: Button) -> bool: return b.get_meta("material") == "linen")[0]
	linen.emit_signal("pressed")
	await _wait_room()
	await _frames(2)
	_check("choosing one puts it on the part", MaterialLibrary.id_of(_part_material("Pot plant", "Pot")) == "linen")
	var undo: Button = layer.ui.toast_button()
	_check("the footer offers Undo", undo != null and undo.text == "Undo")
	var labels: Array = section._parts_box.find_children("*", "Label", true, false).map(func(l: Label) -> String:
		return l.text)
	_check("the part's row names its material (%s)" % [labels], labels.any(func(t: String) -> bool:
		return t.begins_with("Pot") and t.contains("Linen")))
	if undo != null:
		undo.emit_signal("pressed")
		await _wait_room()
		await _frames(2)
		_check("Undo: the part's material before", MaterialLibrary.id_of(_part_material("Pot plant", "Pot"))
				== "velvet")
	layer.ui.hide_toast()


# --- The effect library --------------------------------------------------------------------------------------------

func _test_effect_schema() -> void:
	_check("the schema's effects are the library's surface effects (%d)" % RoomSchema.EFFECTS.size(),
			RoomSchema.EFFECTS.keys() == EffectLibrary.schema_effects(false).keys() and RoomSchema.EFFECTS.has("plasma")
			and RoomSchema.EFFECTS.has("rim_glow") and not RoomSchema.EFFECTS.has("sky_aurora"))
	var part := func(fx: Dictionary, extra := {}) -> Dictionary:
		var m := {"effect": fx}
		m.merge(extra)
		return {"schema": 2, "parts": [{"name": "a", "type": "box", "size": [1, 1, 1], "material": m}]}
	_check("a library effect on a part", RoomSchema.validate(part.call({"name": "plasma", "speed": 0.3}), "patch")["ok"])
	var errs: Array = RoomSchema.validate(part.call({"name": "pulse", "rate": 5.0}), "patch")["errors"]
	_check("the ceiling, named (%s)" % [errs], errs.size() == 1 and str(errs).contains("3 times a second"))
	errs = RoomSchema.validate(part.call({"name": "sky_aurora"}), "patch")["errors"]
	_check("a sky effect on a part is refused (%s)" % [errs], str(errs).contains("for the sky"))
	errs = RoomSchema.validate(part.call({"name": "plasma"}, {"library_material": "velvet"}), "patch")["errors"]
	_check("an effect that draws its own surface doesn't go over a library material (%s)" % [errs],
			str(errs).contains("does not layer"))
	_check("one that layers does", RoomSchema.validate(part.call({"name": "caustics"}, {"library_material": "velvet"}),
			"patch")["ok"])
	_check("a sky effect on the sky", RoomSchema.validate({"schema": 2, "sky": {"effect": {"name": "sky_aurora"}}},
			"patch")["ok"])
	errs = RoomSchema.validate({"schema": 2, "sky": {"effect": {"name": "plasma"}}}, "patch")["errors"]
	_check("a part's effect on the sky is refused (%s)" % [errs], str(errs).contains("$.sky.effect.name"))
	var c := func(fx: String) -> float:
		return RoomSchema.part_cost({"type": "box", "size": [1, 1, 1], "material": {"effect": {"name": fx}}})
	_check("costs: the effect's units (rim_glow %s, hologram %s, water %s)" % [c.call("rim_glow"),
			c.call("hologram"), c.call("water")], is_equal_approx(c.call("rim_glow"), RoomSchema.COSTS["part"]
			+ RoomSchema.COSTS["effect"]) and is_equal_approx(c.call("hologram"), RoomSchema.COSTS["part"]
			+ 2 * RoomSchema.COSTS["effect"]) and is_equal_approx(c.call("water"), RoomSchema.COSTS["part"]
			+ EffectLibrary.cost_units("water") * RoomSchema.COSTS["effect"]))
	_check("a sky effect costs its units", RoomSchema.room_cost({"sky": {"effect": {"name": "sky_clouds"}}})
			>= EffectLibrary.cost_units("sky_clouds") * RoomSchema.COSTS["effect"])
	var m := RoomSchema.merge_material({"library_material": "velvet", "color": "#802030"}, {"effect": {"name":
			"caustics"}})
	_check("an effect that layers keeps the library material under it", m.get("library_material") == "velvet"
			and m.has("effect"))
	m = RoomSchema.merge_material(m, {"effect": {"name": "plasma"}})
	_check("one that doesn't replaces it", not m.has("library_material") and m["effect"]["name"] == "plasma")


func _test_effects() -> void:
	var r: Dictionary = await commands.run("room_apply", {"room": {"schema": 2,
		"parts": [
			{"name": "Orb", "type": "sphere", "size": [0.6], "position": [0, 1.2, -2.5],
				"material": {"effect": {"name": "plasma"}}},
			{"name": "Speaker", "type": "box", "size": [0.3, 0.5, 0.3], "position": [1.5, 0.25, -2.5],
				"material": {"effect": {"name": "react_sound"}}},
			{"name": "Pool", "type": "box", "size": [1.2, 0.2, 1.2], "position": [-1.5, 0.1, -2.5],
				"material": {"library_material": "white_marble", "effect": {"name": "caustics"}}},
			{"name": "Gate", "type": "box", "size": [1, 2.4, 0.1], "position": [0, 1.2, -3.5],
				"material": {"effect": {"name": "wipe", "amount": 0.5}}},
			{"name": "Fern", "type": "sphere", "size": [0.4], "position": [0.8, 0.2, -1.8],
				"material": {"effect": {"name": "wind_sway"}}}],
		"sky": {"effect": {"name": "sky_aurora"}}}})
	_check("a room with library effects (%s)" % r.get("error", r.get("errors", "")), r.get("ok") == true)
	if r.get("ok") != true:
		return
	var orb := _material_of("Orb")
	_check("a part's effect: the library's shader", orb != null and orb.shader == EffectLibrary.shader("plasma")
			and orb.get_meta("effect", "") == "plasma")
	_check("a reactive effect's film path goes to the room's React node", _material_of("Speaker").get_meta("react", "")
			== "loudness" and main.env.get_node_or_null("React") != null)
	var pool := _material_of("Pool")
	_check("a layered look: the effect over the library material's picture, in its own space", pool != null
			and pool.shader == EffectLibrary.shader("caustics", false, true)
			and pool.get_shader_parameter("albedo_texture") == MaterialLibrary.textures("white_marble")["albedo"]
			and pool.get_shader_parameter("use_texture") == true)
	var gate := _material_of("Gate")
	_check("wipe's size from the part's extent along its axis (%s)" % gate.get_shader_parameter("fx_scale"),
			is_equal_approx(float(gate.get_shader_parameter("fx_scale")), 2.4))
	var fern := _material_of("Fern")
	_check("wind_sway's foot and height from the part (%s, %s)" % [fern.get_shader_parameter("sway_base"),
			fern.get_shader_parameter("fx_scale")], is_equal_approx(float(fern.get_shader_parameter("sway_base")), -0.2)
			and is_equal_approx(float(fern.get_shader_parameter("fx_scale")), 0.4))
	var sky := main.env.get_node_or_null("%s/Sky" % AssistantRoom.LAYER) as MeshInstance3D
	_check("a sky effect on the sky sphere", sky != null and (sky.material_override as ShaderMaterial).shader
			== EffectLibrary.shader("sky_aurora"))
	var st: Dictionary = (await commands.run("room_state", {}))["result"]
	_check("room_state lists every surface effect", (st["effects"] as Array).size() == RoomSchema.EFFECTS.size())
	_check("the layered part reports both (%s, %s)" % [AssistantRoom.material_id_of(main.env.get_node(
			"%s/Pool/Mesh" % AssistantRoom.LAYER)), AssistantRoom.effect_id_of(main.env.get_node(
			"%s/Pool/Mesh" % AssistantRoom.LAYER))], AssistantRoom.material_id_of(main.env.get_node(
			"%s/Pool/Mesh" % AssistantRoom.LAYER)) == "white_marble" and AssistantRoom.effect_id_of(main.env.get_node(
			"%s/Pool/Mesh" % AssistantRoom.LAYER)) == "caustics")
	r = await commands.run("room_apply", {"room": {"schema": 2, "parts": [{"name": "Orb", "type": "sphere",
			"size": [0.6], "material": {"effect": {"name": "pulse", "rate": 10}}}]}})
	_check("a change past the ceiling is refused", r.get("ok") == false and str(r).contains("3 times a second"))
	r = await commands.run("room_apply", {"room": {"schema": 2, "remove": ["Orb", "Speaker", "Pool", "Gate", "Fern"],
			"sky": {}}})
	_check("taken out again", r.get("ok") == true)


func _test_effect_picker() -> void:
	var layer: Node = main.ui
	var section: Node = layer.ui.objects.section
	section._picked = "Pot plant"
	section._palette_for = "effect:Pot plant/Pot"
	section._sync_parts()
	var buttons: Array = section._parts_box.find_children("*", "Button", true, false)
	_check("a part has an Effect button", buttons.any(func(b: Button) -> bool: return b.text == "Effect"))
	var fx: Array = buttons.filter(func(b: Button) -> bool: return b.has_meta("effect"))
	var any := EffectLibrary.ids().filter(func(id: String) -> bool:
		return str(EffectLibrary.entry(id)["surfaces"]) == "any")
	var with_preview := fx.filter(func(b: Button) -> bool:
		return b.icon != null and b.icon.get_width() == section.EFFECT_SWATCH and b.tooltip_text != "")
	_check("Effect opens the picker: every part effect with its preview (%d of %d)" % [fx.size(), any.size()],
			fx.size() == any.size() and with_preview.size() == fx.size())
	var groups: Array = buttons.filter(func(b: Button) -> bool: return b.has_meta("effect_group"))
	_check("its groups, no skies (%s)" % [groups.map(func(b: Button) -> String: return b.text)],
			groups.size() >= 7 and not groups.any(func(b: Button) -> bool: return b.text == "Skies"))
	var nature: Button = groups.filter(func(b: Button) -> bool: return b.get_meta("effect_group") == "nature")[0]
	nature.emit_signal("pressed")
	fx = section._parts_box.find_children("*", "Button", true, false).filter(func(b: Button) -> bool:
		return b.has_meta("effect"))
	_check("Nature: only nature's (%d)" % fx.size(), fx.size() > 3 and fx.all(func(b: Button) -> bool:
		return EffectLibrary.entry(str(b.get_meta("effect")))["group"] == "nature"))
	var caustics: Button = fx.filter(func(b: Button) -> bool: return b.get_meta("effect") == "caustics")[0]
	caustics.emit_signal("pressed")
	await _wait_room()
	await _frames(2)
	var pot := _part_material("Pot plant", "Pot")
	_check("choosing one puts it on the part, over its material (it layers)", pot != null
			and pot.get_meta("effect", "") == "caustics" and pot.get_meta("library_material", "") == "velvet")
	var undo: Button = layer.ui.toast_button()
	_check("the footer offers Undo", undo != null and undo.text == "Undo")
	if undo != null:
		undo.emit_signal("pressed")
		await _wait_room()
		await _frames(2)
		_check("Undo: no effect", _part_material("Pot plant", "Pot").get_meta("effect", "") == "")
	layer.ui.hide_toast()


# --- Helpers ---------------------------------------------------------------------------------------------------

func _picker_buttons(section: Node) -> Array:
	return section._parts_box.find_children("*", "Button", true, false).filter(func(b: Button) -> bool:
		return b.has_meta("material"))


func _material_of(part: String) -> ShaderMaterial:
	var mi := main.env.get_node_or_null("%s/%s/Mesh" % [AssistantRoom.LAYER, part]) as MeshInstance3D
	return mi.material_override as ShaderMaterial if mi != null else null


func _part_material(placed: String, part: String) -> ShaderMaterial:
	var node: Node = main.env.get_node_or_null("%s/%s/Model" % [AssistantRoom.LAYER, placed])
	var mi: MeshInstance3D = RoomModel.parts_of(node).get(part) if node != null else null
	if mi == null:
		return null
	return (mi.material_override if mi.material_override != null else mi.get_active_material(0)) as ShaderMaterial


func _colour(part: String) -> String:
	var mi := main.env.get_node_or_null("%s/%s/Mesh" % [AssistantRoom.LAYER, part]) as MeshInstance3D
	return AssistantRoom._colour_of(mi) if mi != null else ""


func _doc_part(name: String) -> Dictionary:
	for p: Dictionary in main.env.get("doc").get("parts", []):
		if p["name"] == name:
			return p
	return {}


func _has_entry(match: String) -> bool:
	var doc: Dictionary = main.env.get("doc")
	return (doc.get("recolour", []) as Array).any(func(r: Dictionary) -> bool: return r["match"] == match)


## Colours within one step of 8 bits (sRGB round trips).
func _close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01


func _png_b64() -> String:
	var img := Image.create_empty(8, 8, false, Image.FORMAT_RGB8)
	img.fill(Color(0.2, 0.6, 0.3))
	return Marshalls.raw_to_base64(img.save_png_to_buffer())


## A change through the app's own editor builds the room again: wait for it.
func _wait_room() -> void:
	for i in 120:
		await process_frame
		if not bool(ObjectLibrary.editor_for(self).get("_busy")) and not bool(commands.room.get("_busy")):
			break
	await _frames(2)


func _cleanup() -> void:
	var dir := AssistantRoom.files_dir(ROOM)
	if DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(f))
		DirAccess.remove_absolute(dir)
	DirAccess.remove_absolute(AssistantRoom.json_path(ROOM))


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL " + what)
