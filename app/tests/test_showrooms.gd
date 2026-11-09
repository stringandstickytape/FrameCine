extends SceneTree

## The showrooms (docs/showrooms.md): what tools/showrooms.gd makes (every document valid, as a kept room and against
## the room's limits, within the showroom budget; every effect, sky, library material, built-in object, part type,
## widget and motion in one of them; no particles; the labels' lines kept and level with their samples), the files in
## the app the same as it would make them now, each showroom built by the room builder in the real main scene, the Room
## tab's Showrooms group, and the perf_rooms command (headless: the rows, the restore, the refusals).
## godot --headless --xr-mode off --path app --script res://tests/test_showrooms.gd

const ShowroomTool := preload("res://tools/showrooms.gd")
const Showrooms := preload("res://scripts/env/showrooms.gd")
const RoomSchema := preload("res://scripts/assistant/room_schema.gd")
const RoomMotion := preload("res://scripts/assistant/room_motion.gd")
const RoomEditor := preload("res://scripts/assistant/room_editor.gd")
const AssistantRoom := preload("res://scripts/assistant/assistant_room.gd")
const EffectLibrary := preload("res://scripts/effects/effect_library.gd")
const MaterialLibrary := preload("res://scripts/env/material_library.gd")
const ObjectBuiltins := preload("res://scripts/assistant/object_builtins.gd")
const DevCommands := preload("res://scripts/dev/dev_commands.gd")
const EnvLibrary := preload("res://scripts/env/env_library.gd")
const EnvDoc := preload("res://scripts/env/env_doc.gd")
const CommandHost := preload("res://scripts/dev/command_host.gd")

var _failures := 0
var _checks := 0
var main: Node3D
var rooms: Array = []


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
	rooms = ShowroomTool.build()
	_test_documents()
	_test_coverage()
	_test_labels()
	_test_files()
	await _test_built()
	await _test_room_tab()
	await _test_perf_rooms()
	main.queue_free()
	await _frames(2)
	print("test_showrooms: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


# --- The documents ---------------------------------------------------------------------------------------------------

func _test_documents() -> void:
	_check("showrooms: some made (%d)" % rooms.size(), rooms.size() >= 4)
	var ids := {}
	var editor := RoomEditor.new()
	for r: Dictionary in rooms:
		var doc: Dictionary = r["doc"]
		var what := str(r["id"])
		_check("%s: a new id" % what, not ids.has(what))
		ids[what] = true
		var v := RoomSchema.validate(doc, "saved")
		_check("%s: valid as a kept room %s" % [what, v["errors"].slice(0, 3)], v["ok"])
		_check("%s: seats and screen fine" % what, RoomSchema.layout_errors(doc).is_empty())
		_check("%s: on a stock room" % what, str(doc.get("base", "")) in RoomEditor.bases().map(
				func(e: Array) -> String: return str(e[0])))
		var b: Dictionary = r["budget"]
		_check("%s: within the budget %s" % [what, b], ShowroomTool.fits(doc))
		# The room editor's own count (models without their triangles: a floor for the estimate's).
		var used: Dictionary = editor._used(doc)
		for k: String in ["parts", "widgets", "texts", "emitters", "recolours"]:
			_check("%s: %s %s within the room's limit" % [what, k, used[k]], int(used[k]) <= int(RoomSchema.LIMITS[k]))
		_check("%s: the editor's cost %s at most the estimate's %s" % [what, used["cost"], b["cost"]],
				float(used["cost"]) <= float(b["cost"]) + 0.05)
		_check("%s: cost within the room's cap" % what, float(b["cost"]) <= float(RoomSchema.LIMITS["cost"]))
		_check("%s: lights within the limit" % what, (doc.get("lights", []) as Array).size()
				<= int(RoomSchema.LIMITS["lights"]))
		for p: Dictionary in doc["parts"]:
			for f in ["model_file", "texture_file"]:
				var file := str(p.get(f, (p.get("material", {}) as Dictionary).get(f, "")))
				if file != "":
					_check("%s: %s %s is written with it" % [what, p["name"], file], (r["files"] as Dictionary).has(file))
	editor.free()


func _test_coverage() -> void:
	var effects := {}
	var skies := {}
	var materials := {}
	var objects := {}
	var types := {}
	var widgets := {}
	var motions := {}
	for r: Dictionary in rooms:
		var doc: Dictionary = r["doc"]
		var sky: Dictionary = doc.get("sky", {})
		if sky.get("effect") is Dictionary:
			skies[str(sky["effect"]["name"])] = true
		for p: Dictionary in doc["parts"]:
			types[str(p["type"])] = true
			var m: Dictionary = p.get("material", {}) if p.get("material") is Dictionary else {}
			if m.get("effect") is Dictionary:
				var id := str(m["effect"]["name"])
				effects[id] = int(effects.get(id, 0)) + 1
			if m.has("library_material"):
				var id := str(m["library_material"])
				materials[id] = (materials.get(id, []) as Array) + [str(p["type"])]
			if p.has("object"):
				objects[str(p["object"])] = true
			if p.has("widget"):
				widgets[str(p["widget"])] = true
			if p.has("motion"):
				for mo: Dictionary in (p["motion"] if p["motion"] is Array else [p["motion"]]):
					motions[str(mo["type"])] = true
	for id in EffectLibrary.ids():
		if str(EffectLibrary.entry(id)["surfaces"]) == "sky":
			_check("sky %s has a showroom" % id, skies.has(id))
		else:
			_check("effect %s on one sample (%s)" % [id, effects.get(id, 0)], int(effects.get(id, 0)) == 1)
	for id in MaterialLibrary.ids():
		var on: Array = materials.get(id, [])
		_check("material %s on a panel and a sphere %s" % [id, on], "box" in on and "sphere" in on)
	for e: Dictionary in ObjectBuiltins.ENTRIES:
		if e.get("primitive", false) or e.has("generator"):
			continue  # the shapes and the text (rooms are made of objects): shown as the part types below
		_check("built-in object %s shown" % e["id"], objects.has(e["id"]))
	for t: String in RoomSchema.PART_TYPES:
		if t == "particles":
			_check("no particles (a room starting with them is being fixed)", not types.has(t))
		else:
			_check("part type %s shown" % t, types.has(t))
	for w: String in RoomSchema.WIDGETS:
		_check("widget %s shown" % w, widgets.has(w))
	for m: String in RoomMotion.SPEC:
		if m != "move_to":
			_check("motion %s shown" % m, motions.has(m))
	var lit := rooms.filter(func(r: Dictionary) -> bool: return RoomSchema.is_lit(r["doc"]))
	_check("one lit room, with a key light, shadows and both kinds of light", lit.size() == 1
			and lit[0]["doc"]["light"].get("key") is Dictionary
			and (lit[0]["doc"]["lights"] as Array).map(func(l: Dictionary) -> String: return l["type"]) == ["point",
			"spot"])


## Every label line is kept (the engine drops empty lines: the blanks hold a word joiner), all one height, and each
## sample's name is level with the sample.
func _test_labels() -> void:
	var font := AssistantRoom.text_font(false)
	var ts := TextServerManager.get_primary_interface()
	var px := ShowroomTool.LINE / font.get_height(AssistantRoom.TEXT_FONT_PX)
	var columns := 0
	for r: Dictionary in rooms:
		var heights := []
		for p: Dictionary in r["doc"]["parts"]:
			if p["type"] != "text":
				heights.append(float(p["position"][1]))
		for p: Dictionary in r["doc"]["parts"]:
			if not str(p["name"]).begins_with("Labels"):
				continue
			columns += 1
			var text := str(p["text"])
			var lines := text.split("\n")
			# As Label3D lays them out (scene/3d/label_3d.cpp): mandatory breaks, edge spaces trimmed.
			var rid := ts.create_shaped_text()
			ts.shaped_text_add_string(rid, text, font.get_rids(), AssistantRoom.TEXT_FONT_PX)
			var breaks := ts.shaped_text_get_line_breaks(rid, -1, 0, TextServer.BREAK_MANDATORY
					| TextServer.BREAK_TRIM_START_EDGE_SPACES | TextServer.BREAK_TRIM_END_EDGE_SPACES)
			var hs: Array = []
			for i in range(0, breaks.size(), 2):
				var line := ts.shaped_text_substr(rid, breaks[i], breaks[i + 1] - breaks[i])
				hs.append(ts.shaped_text_get_size(line).y)
				ts.free_rid(line)
			ts.free_rid(rid)
			_check("%s %s: every line kept (%d of %d)" % [r["id"], p["name"], hs.size(), lines.size()],
					hs.size() == lines.size())
			_check("%s %s: lines one height" % [r["id"], p["name"]], hs.all(func(h: float) -> bool: return h == hs[0]))
			if hs.is_empty():
				continue
			var line_h: float = hs[0] * px
			var top := float(p["position"][1]) + line_h * lines.size() * 0.5
			for i in lines.size():
				var l := lines[i]
				if l == ShowroomTool.BLANK or (i == 0 and l == l.to_upper()):
					continue
				var y := top - (i + 0.5) * line_h
				_check("%s: \"%s\" level with its sample (%.3f)" % [r["id"], l, y], heights.any(func(h: float) -> bool:
						return absf(h - y) < 0.02))
	_check("label columns found (%d)" % columns, columns >= 10)


func _test_files() -> void:
	var diff := ShowroomTool.differences(rooms)
	_check("the app's showrooms are as tools/showrooms.gd makes them now %s" % [diff], diff.is_empty())
	var envs := Showrooms.environments()
	_check("the index lists every showroom", envs.map(func(e: Array) -> String: return e[0]) == rooms.map(
			func(r: Dictionary) -> String: return Showrooms.PREFIX + str(r["id"])))
	for e: Array in envs:
		_check("%s: its file is there" % e[0], FileAccess.file_exists(e[2]))
		_check("%s: a showroom id" % e[0], Showrooms.is_showroom(e[0]))


# --- In the app ------------------------------------------------------------------------------------------------------

func _test_built() -> void:
	var all: Array = main.all_environments()
	var n := Showrooms.environments().size()
	_check("the showrooms are the list's last rows", all.slice(all.size() - n).map(func(e: Array) -> String:
			return e[0]) == Showrooms.environments().map(func(e: Array) -> String: return e[0]))
	var before: String = main.env_id
	for r: Dictionary in rooms:
		var id: String = Showrooms.PREFIX + str(r["id"])
		main.set_environment(id)
		await _frames(2)
		var env: Node = main.env
		_check("%s: built by the room builder" % id, main.env_id == id and env.get_script() == AssistantRoom)
		if env.get_script() != AssistantRoom:
			continue
		_check("%s: called %s" % [id, r["name"]], str(env.get("display_name")) == str(r["name"]))
		var layer: Node = env.get_node_or_null(AssistantRoom.LAYER)
		var parts := 0
		for c in layer.get_children() if layer != null else []:
			if c.has_meta("assistant_part"):
				parts += 1
		_check("%s: every part built (%d of %d)" % [id, parts, (r["doc"]["parts"] as Array).size()],
				parts == (r["doc"]["parts"] as Array).size())
		for p: Dictionary in r["doc"]["parts"]:
			if p["type"] == "model":
				_check("%s: %s's model read" % [id, p["name"]], layer.has_node("%s/Model" % p["name"]))
		if r["doc"].has("lights"):
			_check("%s: its lights" % id, env.find_children("*", "Light3D", true, false).size()
					>= (r["doc"]["lights"] as Array).size() + 1)
		if (r["doc"].get("sky", {}) as Dictionary).has("effect"):
			_check("%s: its sky" % id, layer.has_node("Sky"))
			# Inside both cameras' far plane, or the sky is clipped away (black).
			var sphere: SphereMesh = (layer.get_node("Sky") as MeshInstance3D).mesh if layer.has_node("Sky") else null
			_check("%s: the sky within the far plane" % id, sphere != null and sphere.radius < main.flat_camera.far
					and sphere.radius < main.xr_camera.far)
	main.set_environment(before)
	await _frames(2)


func _test_room_tab() -> void:
	var tab: Node = _tab("room")
	_check("the Room tab is there", tab != null)
	if tab == null:
		return
	tab.sync()
	await _frames(1)
	var box: VBoxContainer = tab._showroom_box
	var rows: Array = tab._showrooms.get_children()
	# The group's head is a button now (the Room tab's groups fold), its title in the "label" meta.
	_check("a Showrooms group", box.visible and str(tab._groups["Showrooms"]["head"].get_meta("label", "")) == "Showrooms")
	_check("one row per showroom", rows.map(func(b: Button) -> String: return b.text) == rooms.map(
			func(r: Dictionary) -> String: return str(r["name"])))
	_check("no showroom among the rooms' own rows", (tab._envs.get_children() as Array).all(func(b: Button) -> bool:
			return not str(b.text) in rooms.map(func(r: Dictionary) -> String: return str(r["name"]))))
	var in_categories := 0
	for holder: Node in tab._category_rows.values():
		in_categories += holder.get_child_count()
	_check("the rooms' rows come first", in_categories + tab._envs.get_child_count() + tab._yours.get_child_count()
			+ rows.size() == tab._env_ids.size())
	# One table of categories (EnvDoc.ROOM_GROUPS): a group for each, in its order, and the library reads the same.
	_check("a group for every category, in the table's order %s" % [tab._category_boxes.keys()],
			tab._category_boxes.keys() == EnvDoc.ROOM_GROUPS.keys() and EnvDoc.ROOM_GROUPS.keys().all(
			func(c: String) -> bool: return tab._groups.has(EnvDoc.ROOM_GROUPS[c])))
	_check("a category with no room shows no heading", EnvDoc.ROOM_GROUPS.keys().all(func(c: String) -> bool:
			return (tab._category_boxes[c] as Control).visible == ((tab._category_rows[c] as Node).get_child_count() > 0)))
	_check("a document may name every category of the table, and no other", EnvDoc.ROOM_GROUPS.keys().all(
			func(c: String) -> bool: return EnvDoc.validate({"schema": 4, "name": "x", "room": {"category": c}})["ok"]))
	# The cinemas and the television rooms (a document's room.category) in their own groups.
	var cinema_rows: Array = (tab._cinemas.get_children() as Array).map(func(b: Button) -> String: return b.text)
	_check("the cinema under Cinemas (%s)" % [cinema_rows], tab._cinema_box.visible and EnvLibrary.category_of("cinema")
			== "cinema" and cinema_rows.has(tr("Cinema")) and not (tab._envs.get_children() as Array).any(
			func(b: Button) -> bool: return b.text == tr("Cinema")))
	_check("the Void stays with the other rooms", EnvLibrary.category_of("void") == "other"
			and EnvLibrary.category_of("no_such_room") == "other")
	_check("Television shows only with a TV room", tab._tv_box.visible == (tab._tvs.get_child_count() > 0))
	_check("a category the rooms don't know is refused", not EnvDoc.validate({"schema": 4, "name": "x",
			"room": {"category": "radio"}})["ok"])
	# Every room that ships says what it is, under This room (room.description, a key).
	var no_line: Array = []
	for id: String in tab._env_ids:
		if not tab.is_yours(id) and not Showrooms.is_showroom(id) and EnvLibrary.description_of(id) == "":
			no_line.append(id)
	_check("every shipped room has a line about itself (none: %s)" % [no_line], no_line.is_empty())
	_check("a description over 200 characters is refused", not EnvDoc.validate({"schema": 4, "name": "x",
			"room": {"description": "x".repeat(201)}})["ok"])
	var was_env: String = main.env_id
	main.set_environment("nave")
	await _frames(2)
	tab.sync()
	_check("the Nave's line shows under This room (%s)" % tab._about.text, tab._this_room_box.visible
			and tab._about.visible and tab._about.text == tr(EnvLibrary.description_of("nave")))
	main.set_environment(was_env)
	await _frames(2)
	tab.sync()
	_check("the viewer's own rooms apart (%d)" % tab._yours.get_child_count(), (tab._yours.get_children() as Array).size()
			== tab._env_ids.filter(func(id: String) -> bool: return tab.is_yours(id)).size()
			and tab._yours_box.visible == (tab._yours.get_child_count() > 0))
	var before: String = main.env_id
	(rows[0] as Button).pressed.emit()
	await _frames(2)
	tab.sync()
	_check("a row shows its showroom", main.env_id == Showrooms.PREFIX + str(rooms[0]["id"]))
	_check("and is marked", (rows[0] as Button).button_pressed and not (tab._envs.get_children() as Array).any(
			func(b: Button) -> bool: return b.button_pressed))
	main.set_environment(before)
	await _frames(2)
	tab.sync()
	_check("back: the room's row marked, not the showroom's", not (rows[0] as Button).button_pressed)


func _test_perf_rooms() -> void:
	var before: String = main.env_id
	var fov: String = main.foveation
	var sky := Showrooms.PREFIX + "sky_aurora"
	var r: Dictionary = await DevCommands.execute("perf_rooms", {"rooms": sky, "foveation": "off,high",
			"settle": 0.2, "seconds": 0.3})
	_check("perf_rooms: ok %s" % r.get("error", ""), r.get("ok") == true)
	var res: Dictionary = r.get("result", {})
	var rows: Array = res.get("rows", [])
	_check("perf_rooms: the baseline and the room at both levels (%d rows)" % rows.size(), rows.size() == 4
			and rows.map(func(x: Dictionary) -> String: return "%s %s" % [x["room"], x["foveation"]]) == [
			"void off", "void high", "%s off" % sky, "%s high" % sky])
	_check("perf_rooms: a line per room", (res.get("table", []) as Array).size() == 2)
	_check("perf_rooms: headless says so", str(res.get("notes", [])).contains("headless"))
	_check("perf_rooms: the room and the foveation as they were", main.env_id == before and main.foveation == fov
			and main.foveation_sharp_panel == true)
	var all: Dictionary = await DevCommands.execute("perf_rooms", {"rooms": ["showrooms"], "foveation": ["off"],
			"baseline": "", "settle": 0.2, "seconds": 0.2})
	_check("perf_rooms: showrooms is every showroom", (all.get("result", {}).get("rows", []) as Array).size()
			== rooms.size())
	var bad: Dictionary = await DevCommands.execute("perf_rooms", {"rooms": "showroom:nope"})
	_check("perf_rooms: an unknown room refused", bad.get("ok") == false
			and str(bad.get("error", "")).contains("no room"))
	var level: Dictionary = await DevCommands.execute("perf_rooms", {"rooms": sky, "foveation": "max"})
	_check("perf_rooms: an unknown level refused", level.get("ok") == false
			and str(level.get("error", "")).contains("foveation"))


func _tab(which: String) -> Node:
	var layer: Node = main.ui
	var pane: Node = layer.get("ui") if layer != null else null
	return pane.get(which) if pane != null else null


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL " + what)
