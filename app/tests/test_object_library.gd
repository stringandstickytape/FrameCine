extends SceneTree

## The object library (scripts/assistant/object_library.gd, docs/assistant.md "Objects") in the real main scene: the
## catalogue (built-ins, a user .glb, survives a restart, delete asks nothing of the library itself and can be undone,
## user objects never under res://); the SVG import (svg_extrude.gd: letters with holes, evenodd and nonzero, arcs,
## transforms, relative commands, gradients and pictures warned about, clip paths ignored, the solid's winding, UVs);
## part addressing ("<placed>/<part>") and recolour of a part against the whole; the room document keeping part-level
## colours and building them again from the kept file; the commands through DevCommands.execute, with their undo.
## godot --headless --xr-mode off --path app --script res://tests/test_object_library.gd

const DevCommands := preload("res://scripts/dev/dev_commands.gd")
const CommandHost := preload("res://scripts/dev/command_host.gd")
const AssistantCommands := preload("res://scripts/assistant/assistant_commands.gd")
const ObjectLibrary := preload("res://scripts/assistant/object_library.gd")
const ObjectCommands := preload("res://scripts/assistant/object_commands.gd")
const SvgExtrude := preload("res://scripts/assistant/svg_extrude.gd")
const RoomModel := preload("res://scripts/assistant/room_model.gd")
const RoomSchema := preload("res://scripts/assistant/room_schema.gd")
const AssistantRoom := preload("res://scripts/assistant/assistant_room.gd")
const RoomEditor := preload("res://scripts/assistant/room_editor.gd")
const ObjectThumb := preload("res://scripts/assistant/object_thumb.gd")
const ObjectBuiltins := preload("res://scripts/assistant/object_builtins.gd")
const RoomKeep := preload("res://scripts/assistant/room_keep.gd")

const ROOM := "Dim room with objects"
const TEST_NAME := "Test object chair"

var _failures := 0
var _checks := 0
var main: Node3D
var commands: AssistantCommands
var allow_room := true


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
	commands.allow_room = func() -> bool: return allow_room
	commands.room = RoomEditor.new()
	commands.room.perf_after_change = false
	root.add_child(commands.room)

	_test_schema()
	_test_catalogue()
	_test_svg()
	await _test_commands()
	await _test_parts()
	await _test_kept()
	await _test_objects_tab()
	_cleanup()
	main.queue_free()
	await _frames(2)
	print("test_object_library: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


# --- The room document's version and its new keys -------------------------------------------------------------------

func _test_schema() -> void:
	var v1 := RoomSchema.validate({"schema": 1, "parts": [{"name": "a", "type": "box", "size": [1, 1, 1]}]}, "patch")
	_check("schema 1 is still read", v1["ok"])
	var v1_new := RoomSchema.validate({"schema": 1, "recolour": [{"match": "Shelf/Board", "material": {"color":
			"#ff0000"}}]}, "patch")
	_check("schema 1 with a part-level match: needs schema 2 (%s)" % [v1_new["errors"]], not v1_new["ok"]
			and str(v1_new["errors"]).contains("schema"))
	_check("schema 4 refused", not RoomSchema.validate({"schema": 4}, "patch")["ok"])
	var v2 := RoomSchema.validate({"schema": 2, "recolour": [{"match": "Shelf/Board", "material": {"color": "#ff0000",
			"library_material": "oak"}}, {"match": "Lamp/Shade", "material": null}]}, "patch")
	_check("schema 2: a part-level match, a library material, null to take one out (%s)" % [v2["errors"]], v2["ok"])
	var bad := RoomSchema.validate({"schema": 2, "recolour": [{"match": "a/b/c", "material": {}},
			{"match": "x/", "material": {}}]}, "patch")
	_check("a malformed part match refused with its path (%s)" % [bad["errors"]], not bad["ok"]
			and str(bad["errors"]).contains("$.recolour[0].match") and str(bad["errors"]).contains("$.recolour[1].match"))
	var obj := RoomSchema.validate({"schema": 2, "parts": [{"name": "s", "type": "box", "size": [1, 1, 1],
			"object": "wall_shelf"}]}, "patch")
	_check("object only on a model part", not obj["ok"] and str(obj["errors"]).contains("object"))
	var merged := RoomSchema.merge({"recolour": [{"match": "Shelf/Board", "material": {"color": "#ff0000"}},
			{"match": "Wall*", "material": {"color": "#00ff00"}}]}, {"recolour": [{"match": "Shelf/Board",
			"material": null}]})
	_check("null takes a part-level entry out, the rest stays", (merged["recolour"] as Array).size() == 1
			and merged["recolour"][0]["match"] == "Wall*")
	merged = RoomSchema.merge({"parts": [{"name": "Shelf"}], "recolour": [{"match": "Shelf/Board", "material": {}}]},
			{"remove": ["Shelf"]})
	_check("removing a part takes its part-level entries with it", (merged["recolour"] as Array).is_empty())
	_check("the limits name model_parts and recolours", RoomSchema.LIMITS.has("model_parts")
			and RoomSchema.LIMITS.has("recolours"))


# --- The catalogue -----------------------------------------------------------------------------------------------

func _test_catalogue() -> void:
	var all := ObjectLibrary.list()
	var ids: Array = all.map(func(m: Dictionary) -> String: return m["id"])
	_check("built-ins listed (%s)" % [ids], ids.has("picture_frame") and ids.has("wall_shelf") and ids.has("pot_plant")
			and ids.has("wall_clock"))
	var want := {"picture_frame": ["Frame", "Mount", "Picture"], "wall_shelf": ["Board", "Brackets"],
			"pot_plant": ["Pot", "Soil", "Leaves"], "wall_clock": ["Rim", "Face"]}
	for id: String in want:
		var m := ObjectLibrary.get_object(id)
		var parts: Array = m.get("parts", []).map(func(p: Dictionary) -> String: return p["name"])
		parts.sort()
		var w: Array = want[id].duplicate()
		w.sort()
		_check("%s: its parts by name (%s)" % [id, parts], parts == w and m["source"] == "builtin")
		var img := ObjectLibrary.thumbnail(id)
		_check("%s: a thumbnail with something on it" % id, img != null and img.get_width() == ObjectLibrary.THUMB_SIZE
				and _opaque(img) > 200)
	var shelf := ObjectLibrary.get_object("wall_shelf")
	_check("the shelf's board keeps its colour (%s)" % [shelf["parts"]], (shelf["parts"] as Array).any(
			func(p: Dictionary) -> bool: return p["name"] == "Board" and p["color"] == "#c8a27a"))
	_check("the clock carries the clock widget", ObjectLibrary.get_object("wall_clock").get("widget") == "clock")
	_check("mounts: wall and floor", shelf["mount"] == "wall" and ObjectLibrary.get_object("pot_plant")["mount"] == "floor")

	# A user .glb: one named part, one with no name (part_1), and one named like a built-in's id.
	var glb := _two_part_glb()
	var r := ObjectLibrary.import_glb(glb, TEST_NAME, ["Chair", "seat", "chair"], "")
	_check("a .glb imports (%s)" % r.get("error", ""), r.get("ok") == true)
	if r.get("ok") != true:
		return
	var m: Dictionary = r["manifest"]
	var id: String = m["id"]
	var part_names: Array = m["parts"].map(func(p: Dictionary) -> String: return p["name"])
	_check("its parts: the named node, then part_1 for the unnamed (%s)" % [part_names], part_names.has("Seat")
			and part_names.has("part_1"))
	_check("tags cleaned and unique (%s)" % [m["tags"]], m["tags"] == ["chair", "seat"])
	_check("mount guessed: a deep thing stands on the floor (%s)" % m["mount"], m["mount"] == "floor")
	var dir := ObjectLibrary.USER_DIR.path_join(id)
	_check("kept under user://objects (%s)" % dir, dir.begins_with("user://") and FileAccess.file_exists(
			dir.path_join("object.glb")) and FileAccess.file_exists(dir.path_join("manifest.json"))
			and FileAccess.file_exists(dir.path_join("thumb.png")))
	_check("never under res://", not _res_has(id) and not ObjectLibrary.USER_DIR.begins_with("res://"))
	# A restart: nothing kept in memory.
	ObjectLibrary._thumbs.clear()
	ObjectLibrary._builtin.clear()
	var again := ObjectLibrary.get_object(id)
	_check("the catalogue survives a restart (%s)" % again.get("name"), again.get("name") == TEST_NAME
			and ObjectLibrary.list("", "user").any(func(x: Dictionary) -> bool: return x["id"] == id)
			and ObjectLibrary.thumbnail(id) != null)
	_check("found by tag", ObjectLibrary.list("chair").any(func(x: Dictionary) -> bool: return x["id"] == id)
			and not ObjectLibrary.list("chair").any(func(x: Dictionary) -> bool: return x["id"] == "wall_shelf"))
	_check("a name like a built-in's gets an id of its own", ObjectLibrary.new_id("Wall shelf") == "wall_shelf_2")
	_check("a built-in can't be deleted", ObjectLibrary.delete("wall_shelf")["ok"] == false)
	_check("delete takes it out of the catalogue", ObjectLibrary.delete(id)["ok"] and ObjectLibrary.get_object(id).is_empty())
	_check("and restore brings it back", ObjectLibrary.restore(id) and not ObjectLibrary.get_object(id).is_empty())
	ObjectLibrary.delete(id)
	ObjectLibrary.purge(id)
	_check("purged: gone for good", not DirAccess.dir_exists_absolute(ObjectLibrary.TRASH_DIR.path_join(id))
			and not ObjectLibrary.restore(id))

	# Too many parts: refused, naming the limit.
	var many := Node3D.new()
	for i in int(RoomSchema.LIMITS["model_parts"]) + 2:
		var mi := MeshInstance3D.new()
		mi.name = "P%d" % i
		var b := BoxMesh.new()
		b.size = Vector3.ONE * 0.01
		mi.mesh = b
		mi.position = Vector3(i * 0.02, 0, 0)
		many.add_child(mi)
	r = ObjectLibrary.import_glb(ObjectLibrary.to_glb(many), "Too many")
	many.free()
	_check("too many parts refused, naming model_parts (%s)" % r.get("error"), r.get("ok") == false
			and r.get("limit") == "model_parts")
	r = ObjectLibrary.import_glb("not a model".to_utf8_buffer(), "Junk")
	_check("not a .glb refused", r.get("ok") == false)


# --- SVG -----------------------------------------------------------------------------------------------------------

func _test_svg() -> void:
	# An O: two circles in one path, the inner one the other way round (nonzero leaves a hole).
	var o := _svg('<path id="O" d="M50 10 A40 40 0 1 1 49.99 10 Z M50 30 A20 20 0 1 0 50.01 30 Z" fill="#202020"/>')
	var r := SvgExtrude.build(o, {"width": 0.8, "depth": 0.05, "bevel": 0.0})
	_check("an O builds (%s)" % r.get("error", ""), r.has("node"))
	if r.has("node"):
		var area := _front_area(r["node"])
		var want := PI * (0.4 * 0.4 - 0.2 * 0.2)
		_check("the O has its hole (front area %.4f, want %.4f)" % [area, want], absf(area - want) / want < 0.02)
		_check("named by its id (%s)" % [r["parts"]], r["parts"] == ["O"])
		_check("its width is the width asked (%s)" % [r["size"]], absf(float(r["size"][0]) - 0.8) < 1e-3)
		_check("the depth: back at 0, front at 0.05", _z_range(r["node"]).is_equal_approx(Vector2(0.0, 0.05)))
		(r["node"] as Node).free()
	# A B: one outline, two holes (the bowls) drawn the other way round, as a font draws them.
	var b := _svg('<path d="M0 0 H60 V100 H0 Z M15 15 V40 H45 V15 Z M15 60 V85 H45 V60 Z"/>')
	r = SvgExtrude.build(b, {"width": 0.6, "depth": 0.02, "bevel": 0.0})
	if r.has("node"):
		var area := _front_area(r["node"])
		var want := (60.0 * 100.0 - 2.0 * 30.0 * 25.0) * 0.0001
		_check("a letter with two holes (front %.4f, want %.4f)" % [area, want], absf(area - want) / want < 0.01)
		(r["node"] as Node).free()
	else:
		_check("a letter with two holes builds (%s)" % r.get("error"), false)
	# Two squares drawn the same way round: evenodd a frame, nonzero a full square.
	var squares := "M0 0 H100 V100 H0 Z M25 25 H75 V75 H25 Z"
	for rule: String in ["evenodd", "nonzero"]:
		r = SvgExtrude.build(_svg('<path d="%s" fill-rule="%s"/>' % [squares, rule]), {"width": 1.0, "bevel": 0.0})
		if not r.has("node"):
			_check("%s builds (%s)" % [rule, r.get("error")], false)
			continue
		var area := _front_area(r["node"])
		var want := 0.75 if rule == "evenodd" else 1.0
		_check("fill-rule %s: front area %.3f (want %.3f)" % [rule, area, want], absf(area - want) < 0.01)
		(r["node"] as Node).free()
	# The rule from a style block's class, and relative commands with implicit repeats and packed arc flags.
	var styled := '<style>.ring{fill:#3366cc;fill-rule:evenodd}</style><path class="ring" d="m0 0h100v100h-100z m25 25h50v50h-50z"/>'
	r = SvgExtrude.build(_svg(styled), {"width": 1.0, "bevel": 0.0})
	if r.has("node"):
		_check("a class rule's fill-rule and colour", absf(_front_area(r["node"]) - 0.75) < 0.01
				and _colours(r["node"]).has("3366cc"))
		(r["node"] as Node).free()
	var arcs := _svg('<path d="M10 50a40 40 0 1180 0a40 40 0 11-80 0z"/>')
	r = SvgExtrude.build(arcs, {"width": 0.8, "bevel": 0.0})
	if r.has("node"):
		var area := _front_area(r["node"])
		_check("a circle of two arcs with packed flags (area %.4f, want %.4f)" % [area, PI * 0.16],
				absf(area - PI * 0.16) / (PI * 0.16) < 0.01)
		(r["node"] as Node).free()
	else:
		_check("arcs build (%s)" % r.get("error"), false)
	# Transforms on groups and paths: a 10 x 40 bar turned 90 degrees in a scaled group is 80 wide and 20 high.
	var turned := _svg('<g id="Bar" transform="scale(2)"><rect x="0" y="0" width="10" height="40" '
			+ 'transform="rotate(90 5 20)"/></g><g transform="translate(200 0)"><circle cx="0" cy="0" r="10"/></g>')
	r = SvgExtrude.build(turned, {"width": 1.0, "bevel": 0.0})
	if r.has("node"):
		var bar := (r["node"] as Node).get_node_or_null("Bar") as MeshInstance3D
		var box := bar.mesh.get_aabb() if bar != null else AABB()
		_check("parts: the group's id, then part_2 (%s)" % [r["parts"]], r["parts"] == ["Bar", "part_2"])
		_check("the bar turned and scaled (%s)" % box.size, absf(box.size.x / box.size.y - 4.0) < 0.05)
		(r["node"] as Node).free()
		r = SvgExtrude.build(turned, {"part_names": ["Logo", "Logo"]})
		_check("part_names join two elements into one part (%s)" % [r.get("parts")], r.get("parts") == ["Logo"])
		if r.has("node"):
			(r["node"] as Node).free()
	# Gradients and pictures: a flat colour and warnings; a clip path's shapes are not drawn.
	var extras := _svg('<defs><linearGradient id="g"><stop offset="0" stop-color="#ff8800"/><stop offset="1" '
			+ 'stop-color="#000"/></linearGradient><clipPath id="c"><rect width="500" height="500"/></clipPath></defs>'
			+ '<rect width="100" height="50" fill="url(#g)" clip-path="url(#c)"/><image href="x.png" width="10" '
			+ 'height="10"/>')
	r = SvgExtrude.build(extras, {"width": 1.0, "bevel": 0.0})
	if r.has("node"):
		_check("a gradient becomes its first stop (%s)" % [_colours(r["node"])], _colours(r["node"]) == ["ff8800"])
		_check("warnings: gradient and picture (%s)" % [r["warnings"]], str(r["warnings"]).contains("gradient")
				and str(r["warnings"]).contains("<image>"))
		_check("the clip path's rect is not drawn (front %.3f)" % _front_area(r["node"]),
				absf(_front_area(r["node"]) - 0.5) < 0.01)
		(r["node"] as Node).free()
	# An editor's layer: one wrapping group; its children are the parts.
	var layered := _svg('<g id="layer1"><path id="Left" d="M0 0H10V10H0Z" fill="red"/><path id="Right" '
			+ 'd="M20 0H30V10H20Z" fill="blue"/></g>')
	r = SvgExtrude.build(layered, {})
	_check("one wrapping group: its children are the parts (%s)" % [r.get("parts")], r.get("parts") == ["Left", "Right"])
	if r.has("node"):
		(r["node"] as Node).free()
	# The solid: closed with Godot's winding (the reader turns nothing over), the bevel's chamfer, UVs on the front.
	var bevelled := _svg('<path id="Star" d="M50 0 L61 35 L98 35 L68 57 L79 91 L50 70 L21 91 L32 57 L2 35 L39 35 Z"/>')
	r = SvgExtrude.build(bevelled, {"width": 0.5, "depth": 0.03})
	if r.has("node"):
		var mi := (r["node"] as Node).get_node("Star") as MeshInstance3D
		_check("the solid's winding is the engine's (volume %.6f < 0)" % _volume(mi.mesh), _volume(mi.mesh) < 0.0)
		var t: Array = RoomModel.turn_inside_out_shapes(mi.mesh as ArrayMesh)
		_check("nothing for the reader to turn over (%d)" % int(t[1]), int(t[1]) == 0)
		_check("the chamfer: faces leaning forward", _leaning(mi.mesh) > 0)
		_check("front UVs within the picture", _front_uvs_ok(mi.mesh))
		var bytes := ObjectLibrary.to_glb(r["node"])
		var back := RoomModel.load_glb(bytes)
		_check("written and read back: same part, nothing turned (%s)" % [back.get("parts")], back.get("turned") == 0
				and (back.get("parts", []) as Array).size() == 1 and back["parts"][0]["name"] == "Star")
		if back.has("node"):
			(back["node"] as Node).free()
		(r["node"] as Node).free()
	_check("not an SVG refused", SvgExtrude.build("<html></html>").has("error"))
	_check("an SVG with only lines says why", str(SvgExtrude.build(_svg('<path d="M0 0L10 10" fill="none" '
			+ 'stroke="black"/>')).get("error", "")).contains("stroke"))


# --- The commands ----------------------------------------------------------------------------------------------

func _test_commands() -> void:
	for c: String in ["object_library", "object_info", "object_import", "object_place", "object_move",
			"object_delete", "object_put_back", "object_tidy_up", "object_attach", "object_throw", "object_physics"]:
		var spec := DevCommands.get_spec(c)
		_check("%s registered with an assistant level (%s)" % [c, spec.get("assistant")], spec.get("assistant") in
				["read", "room"] and (spec.get("assistant") == "read") == (c in ["object_library", "object_info",
				"object_physics"]))
		for p: Dictionary in spec.get("params", []):
			_check("%s: %s described" % [c, p["name"]], str(p.get("description", "")) != "")
	_check("recolour takes material and reset", DevCommands.get_spec("recolour")["params"].any(
			func(p: Dictionary) -> bool: return p["name"] == "material") and DevCommands.get_spec("recolour")["params"].any(
			func(p: Dictionary) -> bool: return p["name"] == "reset"))
	var r := await DevCommands.execute("object_library", {"source": "builtin"}, false)
	_check("object_library lists the built-ins, the primitives and generators too (%s)" % r.get("error", ""), r["ok"]
			and int(r["result"]["count"]) == ObjectBuiltins.ENTRIES.size() and (r["result"]["objects"] as Array).any(
			func(o: Dictionary) -> bool: return o["id"] == "box"))
	r = await DevCommands.execute("object_info", {"id": "wall_clock"}, false)
	_check("object_info: parts and the widget", r["ok"] and r["result"]["widget"] == "clock"
			and (r["result"]["parts"] as Array).size() == 2)

	# Import an SVG through the registry, read it, delete it, undo the delete.
	var svg := _svg('<path id="Plate" d="M0 0H80V40H0Z" fill="#aa3322"/><circle id="Dot" cx="40" cy="20" r="8" '
			+ 'fill="#eeeeee"/>')
	r = await DevCommands.execute("object_import", {"name": "Test sign", "data": Marshalls.utf8_to_base64(svg),
			"tags": ["sign"], "width": 0.5}, false)
	_check("object_import (svg): an id and parts (%s)" % r.get("error", r.get("result")), r["ok"]
			and r["result"]["parts"] == ["Plate", "Dot"] and r["result"]["mount"] == "wall")
	if not r["ok"]:
		return
	var id: String = r["result"]["id"]
	_check("an undo for the import", (r["call"] as DevCommands.Call).undo.is_valid())
	r = await DevCommands.execute("object_delete", {"id": id}, false)
	_check("object_delete: gone, with an undo", r["ok"] and ObjectLibrary.get_object(id).is_empty())
	(r["call"] as DevCommands.Call).undo.call()
	_check("undo brings it back", not ObjectLibrary.get_object(id).is_empty())
	r = await DevCommands.execute("object_delete", {"id": "wall_shelf"}, false)
	_check("a built-in can't be deleted", not r["ok"])
	# The assistant: a path on the headset is the dev link's only; the room switch off refuses.
	var a: Dictionary = await commands.run("object_import", {"name": "From path", "path": "/etc/hostname"})
	_check("path refused for the assistant (%s)" % a.get("error"), a.get("ok") == false
			and str(a.get("error")).contains("dev link"))
	allow_room = false
	a = await commands.run("object_place", {"id": "wall_shelf"})
	_check("object_place refused with the room switch off", a.get("ok") == false and a.get("refused") == true)
	allow_room = true
	a = await commands.run("object_library", {})
	_check("object_library reachable by the assistant", a.get("ok") == true)
	ObjectLibrary.delete(id)
	ObjectLibrary.purge(id)


# --- Placing, part addressing, part against whole ------------------------------------------------------------------

func _test_parts() -> void:
	main.set_environment("dim_room")
	await _frames(3)
	var r := await DevCommands.execute("object_place", {"id": "wall_shelf", "at": "front"}, false)
	_check("object_place in a stock room (%s)" % r.get("error", ""), r["ok"] and r["result"]["placed"] == "Wall shelf"
			and main.env_id == "recipe:" + ROOM)
	if not r["ok"]:
		return
	_check("its summary", (r["call"] as DevCommands.Call).summary == "add Wall shelf")
	_check("the parts are there by name", _part_mesh("Wall shelf", "Board") != null
			and _part_mesh("Wall shelf", "Brackets") != null)
	var st := await DevCommands.execute("object_info", {"placed": "Wall shelf"}, false)
	_check("object_info placed: its parts (%s)" % st.get("result"), st["ok"]
			and (st["result"]["parts"] as Array).size() == 2)
	r = await DevCommands.execute("object_place", {"id": "wall_shelf", "position": [1, 1, -2]}, false)
	_check("a second one is numbered (%s)" % r.get("error", ""), r["ok"] and r["result"]["placed"] == "Wall shelf 2")
	_check("the two share the board's mesh", _part_mesh("Wall shelf", "Board") != null
			and _part_mesh("Wall shelf 2", "Board") != null
			and _part_mesh("Wall shelf", "Board").mesh == _part_mesh("Wall shelf 2", "Board").mesh)

	# One part.
	var bracket_before := _albedo("Wall shelf", "Brackets")
	var a: Dictionary = await commands.run("recolour", {"match": "Wall shelf/Board", "color": "#ff0000"})
	_check("recolour one part (%s)" % a.get("error", ""), a.get("ok") == true)
	_check("the board is red", _albedo("Wall shelf", "Board").is_equal_approx(Color(1, 0, 0)))
	_check("the brackets keep their colour", _albedo("Wall shelf", "Brackets").is_equal_approx(bracket_before))
	_check("the other shelf's board is untouched", not _albedo("Wall shelf 2", "Board").is_equal_approx(Color(1, 0, 0)))
	var placed: Array = (await commands.run("room_state", {}))["result"]["objects"]
	var board_set := ""
	for p: Dictionary in placed:
		if p["name"] == "Wall shelf":
			for q: Dictionary in p["parts"]:
				if q["name"] == "Board":
					board_set = str(q["recolour"])
	_check("room_state's objects say what set the board (%s)" % board_set, board_set == "Wall shelf/Board")
	a = await commands.run("recolour", {"match": "Wall shelf*/B*", "emission": "#101010"})
	_check("a pattern on both sides reaches both shelves' parts", a.get("ok") == true
			and _material("Wall shelf 2", "Brackets").get_shader_parameter("emission") != null)
	a = await commands.run("recolour", {"match": "Wall shelf/Nothing", "color": "#00ff00"})
	_check("a part that isn't there is refused, naming object_info", a.get("ok") == false
			and str(a.get("error")).contains("object_info"))
	a = await commands.run("recolour", {"match": "Wall shelf 2/Board", "color": "#ffffff", "material": "no_such_oak"})
	var kinds: Array = (a.get("result", {}).get("warnings", []) as Array).map(func(w: Dictionary) -> String:
		return w["kind"])
	_check("an unknown library material: applied without it, with a warning (%s)" % [kinds], a.get("ok") == true
			and kinds.has("unknown_material") and _albedo("Wall shelf 2", "Board").is_equal_approx(Color.WHITE))
	# The whole object: every part, and its part-level colours go.
	a = await commands.run("recolour", {"match": "Wall shelf 2", "color": "#0000ff"})
	_check("recolour the whole object (%s)" % a.get("error", ""), a.get("ok") == true
			and _albedo("Wall shelf 2", "Board").is_equal_approx(Color(0, 0, 1))
			and _albedo("Wall shelf 2", "Brackets").is_equal_approx(Color(0, 0, 1)))
	_check("its own part-level entries went, the other shelf's stay", not _has_entry("Wall shelf 2/Board")
			and _has_entry("Wall shelf/Board"))
	# Reset one part.
	a = await commands.run("recolour", {"match": "Wall shelf/Board", "reset": true})
	_check("reset a part: its own colour again", a.get("ok") == true and not _has_entry("Wall shelf/Board")
			and _albedo("Wall shelf", "Board").is_equal_approx(Color.html("#c8a27a")))
	# The Room tab's own path (no assistant): a part's colour with an undo.
	r = await ObjectCommands.recolour_part(self, null, "Wall shelf/Brackets", {"color": "#00aa00"})
	_check("recolour_part with an undo (%s)" % r.get("error", ""), r.get("ok") == true and r.get("undo") is Callable)
	_check("the brackets are green", _albedo("Wall shelf", "Brackets").is_equal_approx(Color.html("#00aa00")))

	# Move: scale and position; undo.
	r = await DevCommands.execute("object_move", {"name": "Wall shelf 2", "position": [0.5, 1.5, -2.5], "scale": 2.0},
			false)
	var node := main.env.get_node_or_null("AssistantLayer/Wall shelf 2") as Node3D
	_check("object_move (%s)" % r.get("error", ""), r["ok"] and node != null
			and node.position.is_equal_approx(Vector3(0.5, 1.5, -2.5)) and is_equal_approx(node.scale.x, 2.0))
	(r["call"] as DevCommands.Call).undo.call()
	await _wait_room()
	node = main.env.get_node_or_null("AssistantLayer/Wall shelf 2") as Node3D
	_check("its undo puts it back", node != null and node.position.is_equal_approx(Vector3(1, 1, -2)))
	r = await DevCommands.execute("object_move", {"name": "Wall shelf 2", "at": "floor"}, false)
	node = main.env.get_node_or_null("AssistantLayer/Wall shelf 2") as Node3D
	_check("object_move at floor: its bottom on the floor (%s)" % r.get("error", ""), r["ok"] and node != null
			and absf((node.transform * (node.get_meta("local_aabb") as AABB)).position.y - ObjectLibrary.GAP) < 0.01)

	# The kept room: no model files (the library is the one source), the shelves placements of its id; removed with
	# its part colours.
	var files := DirAccess.get_files_at(AssistantRoom.files_dir(ROOM))
	var kept_text := FileAccess.get_file_as_string(AssistantRoom.json_path(ROOM))
	_check("the two shelves are placements of the library's shelf, no model files (%s)" % [files],
			Array(files).filter(func(f: String) -> bool: return f.ends_with(".glb")).is_empty()
			and kept_text.count("\"object\": \"wall_shelf\"") == 2 and not kept_text.contains("model"))
	a = await commands.run("remove", {"name": "Wall shelf 2"})
	_check("remove takes a placed object out", a.get("ok") == true
			and main.env.get_node_or_null("AssistantLayer/Wall shelf 2") == null)


func _test_kept() -> void:
	# The kept file has the part-level entry; building it again shows the part's colour.
	var path := AssistantRoom.json_path(ROOM)
	var text := FileAccess.get_file_as_string(path)
	_check("the kept room has the part's recolour (schema 3)", text.contains("Wall shelf/Brackets")
			and text.contains("\"schema\": 3") and text.contains("\"object\": \"wall_shelf\""))
	var room := AssistantRoom.load_saved(path)
	_check("built again from the kept file", room != null)
	if room != null:
		var mi: MeshInstance3D = AssistantRoom.part_targets(room.get_node(AssistantRoom.LAYER), "Wall shelf/Brackets")[0]
		_check("the part's colour comes back", (mi.material_override as ShaderMaterial).get_shader_parameter("albedo")
				.is_equal_approx(Color.html("#00aa00")))
		room.free()
	# Placing in a stock room and undoing: the stock room again.
	main.set_environment("cinema")
	await _frames(3)
	var r := await DevCommands.execute("object_place", {"id": "pot_plant", "at": "floor"}, false)
	_check("a pot plant on the floor of the cinema (%s)" % r.get("error", ""), r["ok"]
			and main.env_id == "recipe:Cinema with objects")
	if r["ok"]:
		var node := main.env.get_node_or_null("AssistantLayer/Pot plant") as Node3D
		_check("its bottom on the floor", node != null)
		(r["call"] as DevCommands.Call).undo.call()
		await _frames(2)
		_check("undo: the stock room again (%s)" % main.env_id, main.env_id == "cinema")
	_cleanup_room("Cinema with objects")


# --- The Room tab: the library's tiles, Place with the laser, a part's colour from the palette ---------------------

## A pointer stand-in: a ray from a point along a direction (world frame).
class FakeHand extends Node3D:
	var from := Vector3.ZERO
	var dir := Vector3.FORWARD

	func get_ray_origin() -> Vector3:
		return from

	func get_ray_direction() -> Vector3:
		return dir


func _test_objects_tab() -> void:
	var layer: Node = main.ui
	if layer == null:
		_check("the panel layer is there", false)
		return
	main.set_environment("dim_room")
	await _frames(3)
	layer.show_panel()
	layer.ui.show_tab(layer.ui.Tab.OBJECTS)
	var section: Node = layer.ui.objects.section
	section.sync_objects()
	for i in 600:
		await process_frame
		if not section._ids.is_empty() and not section._loading:
			break
	var placeable := ObjectLibrary.list().filter(func(m: Dictionary) -> bool: return not m.has("generator"))
	var tiles: int = section._grid.get_child_count() + section._yours_grid.get_child_count()
	_check("the Objects tab: a tile for each but text and particles (%d)" % section._ids.size(), section._ids.size()
			== placeable.size() and tiles == section._ids.size() and section._tiles.has("box") and not section._tiles.has("text"))
	var built_in: int = placeable.filter(func(m: Dictionary) -> bool: return str(m["source"]) == "builtin").size()
	_check("built in and yours apart (%d + %d)" % [section._grid.get_child_count(), section._yours_grid.get_child_count()],
			section._grid.get_child_count() == built_in and section._yours_grid.visible == (section._yours_grid.get_child_count() > 0))
	var tile: Button = section._tiles.get("pot_plant")
	_check("a tile has its thumbnail and name", tile != null and tile.find_children("*", "TextureRect", true,
			false).size() == 1)
	_check("Place waits for a pick", section._place.disabled)
	tile.emit_signal("pressed")
	_check("a pick: its line and Place (%s)" % section._chosen.text, not section._place.disabled
			and section._chosen.text.begins_with("Pot plant") and not section._delete.visible)

	# Place: the panel goes; the laser from the eyes' height down at the floor 1.5 m ahead puts it there.
	_check("Place starts placing", layer.start_object_place("pot_plant") and layer.is_placing_object()
			and not layer.is_open())
	var hand := FakeHand.new()
	root.add_child(hand)
	var to_world: Transform3D = main.env.global_transform
	hand.from = to_world * Vector3(0, 1.2, 0)
	hand.dir = (to_world.basis * Vector3(0, -1.2, -1.5)).normalized()
	var placer: Node = layer._placer
	var length: float = placer.update(hand)
	var pos: Array = placer._pose["position"]
	_check("it follows the ray to the floor (%s, laser %.2f m)" % [pos, length], absf(float(pos[2]) + 1.5) < 0.05
			and absf(float(pos[1]) - ObjectLibrary.GAP) < 0.01 and absf(length - 1.92) < 0.05)
	var rot_before: float = placer._pose["rotation"][1]
	placer.on_stick(Vector2(1, 0), 0.5)
	placer.on_stick(Vector2(0, 1), 0.5)
	placer.update(hand)
	_check("the stick turns it and sizes it (%s, %.2f)" % [placer._pose["rotation"], placer._pose["scale"]],
			absf(wrapf(float(placer._pose["rotation"][1]) - rot_before + 45.0, -180.0, 180.0)) < 0.5
			and float(placer._pose["scale"]) > 1.3)
	_check("B cancels: nothing placed", layer.on_back(null) and not layer.is_placing_object()
			and main.env_id == "dim_room")
	layer.start_object_place("pot_plant")
	placer.update(hand)
	var r: Dictionary = await placer.commit()
	_check("the trigger sets it (%s)" % r.get("error", ""), r.get("ok") == true and main.env_id == "recipe:" + ROOM
			and main.env.get_node_or_null("AssistantLayer/Pot plant") != null and not layer.is_placing_object())
	hand.queue_free()

	# In this room: pick it, open a part's palette, take a colour.
	section.sync_objects()
	await _frames(2)
	var row: Button = null
	for b: Button in section._placed_box.get_children():
		if b.text == "Pot plant":
			row = b
	_check("it is listed in this room", row != null and not section._empty.visible)
	if row == null:
		return
	row.emit_signal("pressed")
	var labels: Array = section._parts_box.find_children("*", "Label", true, false).map(func(l: Label) -> String:
		return l.text)
	_check("its parts with swatches (%s)" % [labels], labels.has("Pot") and labels.has("Leaves") and labels.has("Soil")
			and section._parts_box.find_children("*", "ColorRect", true, false).size() == 3)
	section._palette_for = "Pot plant/Pot"
	section._sync_parts()
	var swatches: Array = section._parts_box.find_children("*", "ColorRect", true, false)
	_check("Colour opens the palette under the part", swatches.size() == 3 + section.PALETTE.size())
	await section._apply("Pot plant/Pot", {"color": "#3366cc"})
	_check("a palette colour on the pot (%s)" % _albedo("Pot plant", "Pot"), _albedo("Pot plant", "Pot")
			.is_equal_approx(Color.html("#3366cc")) and _albedo("Pot plant", "Leaves").is_equal_approx(Color.html("#4f8a3c")))
	_check("the footer offers Undo", layer.ui.toast_button() != null and layer.ui.toast_button().text == "Undo")
	# Remove asks first.
	section._ask_remove("Pot plant")
	_check("Remove asks first: nothing gone yet", layer.ui.toast_button() != null
			and layer.ui.toast_button().text == "Remove" and main.env.get_node_or_null("AssistantLayer/Pot plant") != null)
	layer.ui.hide_toast()


# --- Helpers ---------------------------------------------------------------------------------------------------

func _svg(body: String) -> String:
	return '<?xml version="1.0"?><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 100">%s</svg>' % body


## The area of the faces turned to +Z at the front (the largest z).
func _front_area(n: Node) -> float:
	var total := 0.0
	var front := _z_range(n).y
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var a := mi.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var nn: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			for i in range(0, v.size(), 3):
				if nn[i].z > 0.99 and absf(v[i].z - front) < 1e-4:
					total += 0.5 * ((v[i + 1] - v[i]).cross(v[i + 2] - v[i])).length()
	return total


func _z_range(n: Node) -> Vector2:
	var r := Vector2(INF, -INF)
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		var b := mi.mesh.get_aabb()
		r = Vector2(minf(r.x, b.position.z), maxf(r.y, b.end.z))
	return Vector2(snappedf(r.x, 1e-5), snappedf(r.y, 1e-5))


func _colours(n: Node) -> Array:
	var out: Array = []
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			out.append((mi.mesh.surface_get_material(s) as BaseMaterial3D).albedo_color.to_html(false))
	return out


func _volume(mesh: Mesh) -> float:
	var vol := 0.0
	for s in mesh.get_surface_count():
		var v: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		for i in range(0, v.size(), 3):
			vol += v[i].dot(v[i + 1].cross(v[i + 2]))
	return vol / 6.0


func _leaning(mesh: Mesh) -> int:
	var n := 0
	var nn: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	for x in nn:
		if x.z > 0.3 and x.z < 0.95:
			n += 1
	return n


func _front_uvs_ok(mesh: Mesh) -> bool:
	var a := mesh.surface_get_arrays(0)
	var nn: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var any := false
	for i in nn.size():
		if nn[i].z > 0.99:
			any = true
			if uv[i].x < -1e-3 or uv[i].x > 1.001 or uv[i].y < -1e-3 or uv[i].y > 1.001:
				return false
	return any


func _opaque(img: Image) -> int:
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.5:
				n += 1
	return n


## A .glb with a node "Seat" and one with no name on it or its mesh.
func _two_part_glb() -> PackedByteArray:
	var n := Node3D.new()
	var seat := MeshInstance3D.new()
	seat.name = "Seat"
	var b := BoxMesh.new()
	b.size = Vector3(0.5, 0.1, 0.5)
	seat.mesh = b
	seat.position = Vector3(0, 0.45, 0)
	n.add_child(seat)
	var back := MeshInstance3D.new()
	back.name = "Back"
	var b2 := BoxMesh.new()
	b2.size = Vector3(0.5, 0.5, 0.05)
	back.mesh = b2
	back.position = Vector3(0, 0.75, -0.225)
	n.add_child(back)
	var glb := ObjectLibrary.to_glb(n)
	n.free()
	return _with_json(glb, func(g: Dictionary) -> void:
		for node: Dictionary in g["nodes"]:
			if node.get("name") == "Back":
				node.erase("name")
				g["meshes"][int(node["mesh"])].erase("name"))


func _with_json(glb: PackedByteArray, f: Callable) -> PackedByteArray:
	var json_len := glb.decode_u32(12)
	var j := JSON.new()
	j.parse(glb.slice(20, 20 + json_len).get_string_from_utf8())
	var g: Dictionary = j.data
	f.call(g)
	var text := JSON.stringify(g).to_utf8_buffer()
	while text.size() % 4 != 0:
		text.append(32)
	var rest := glb.slice(20 + json_len)
	var out := PackedByteArray()
	out.resize(20)
	out.encode_u32(0, 0x46546C67)
	out.encode_u32(4, 2)
	out.encode_u32(8, 20 + text.size() + rest.size())
	out.encode_u32(12, text.size())
	out.encode_u32(16, 0x4E4F534A)
	out.append_array(text)
	out.append_array(rest)
	return out


func _part_mesh(placed: String, part: String) -> MeshInstance3D:
	var node: Node = main.env.get_node_or_null("%s/%s/Model" % [AssistantRoom.LAYER, placed])
	return RoomModel.parts_of(node).get(part) if node != null else null


func _material(placed: String, part: String) -> ShaderMaterial:
	var mi := _part_mesh(placed, part)
	if mi == null:
		return null
	return (mi.material_override if mi.material_override != null else mi.get_active_material(0)) as ShaderMaterial


func _albedo(placed: String, part: String) -> Color:
	var m := _material(placed, part)
	return m.get_shader_parameter("albedo") if m != null else Color(-1, -1, -1)


func _has_entry(match: String) -> bool:
	var doc: Dictionary = main.env.get("doc")
	return (doc.get("recolour", []) as Array).any(func(r: Dictionary) -> bool: return r["match"] == match)


## An undo builds the room again: wait for the editor.
func _wait_room() -> void:
	for i in 120:
		await process_frame
		if not bool(ObjectLibrary.editor_for(self).get("_busy")):
			break
	await _frames(2)


## res:// has nothing of this object.
func _res_has(id: String) -> bool:
	var dirs: Array = ["res://"]
	while not dirs.is_empty():
		var d: String = dirs.pop_back()
		for sub in DirAccess.get_directories_at(d):
			if not sub.begins_with("."):
				dirs.append(d.path_join(sub))
		for f in DirAccess.get_files_at(d):
			if f.contains(id):
				return true
		if d.contains(id):
			return true
	return false


func _cleanup() -> void:
	_cleanup_room(ROOM)
	_cleanup_room("Cinema with objects")
	for m: Dictionary in ObjectLibrary.list("", "user"):
		if str(m["name"]).begins_with("Test ") or m["name"] in ["Too many", "From path"]:
			ObjectLibrary.delete(m["id"])
			ObjectLibrary.purge(m["id"])


func _cleanup_room(name: String) -> void:
	var dir := AssistantRoom.files_dir(name)
	if DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(f))
		DirAccess.remove_absolute(dir)
	DirAccess.remove_absolute(AssistantRoom.json_path(name))


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL " + what)
