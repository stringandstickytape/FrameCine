extends SceneTree

## Rooms are made of objects (docs/decisions.md; docs/assistant.md "Rooms", "Objects"; scripts/assistant/room_keep.gd)
## in the real main scene: every part type sent as a shape is kept as a placement of a library object (a primitive's
## size as its scale, a text and a particles area as the generators, an inline model as a user object, the same bytes
## once, a picture as a picture object with its mount); a textured plane shows its picture from the library; text is
## an object (object_place); room_state lists every placement with its object; "<placed>/Box" reaches a primitive's
## part; object_delete is refused while a kept room places the object; a kept room of schema 2 on disk is converted
## when it loads and saved as schema 3; a change that is refused takes the objects it made out again.
## godot --headless --xr-mode off --path app --script res://tests/test_room_objects.gd

const DevCommands := preload("res://scripts/dev/dev_commands.gd")
const CommandHost := preload("res://scripts/dev/command_host.gd")
const AssistantCommands := preload("res://scripts/assistant/assistant_commands.gd")
const ObjectLibrary := preload("res://scripts/assistant/object_library.gd")
const RoomKeep := preload("res://scripts/assistant/room_keep.gd")
const RoomModel := preload("res://scripts/assistant/room_model.gd")
const RoomSchema := preload("res://scripts/assistant/room_schema.gd")
const AssistantRoom := preload("res://scripts/assistant/assistant_room.gd")
const RoomEditor := preload("res://scripts/assistant/room_editor.gd")

const ROOM := "Test made of objects"
const OLD_ROOM := "Test schema two"

var _failures := 0
var _checks := 0
var main: Node3D
var commands: AssistantCommands
## The user objects there before the test: what it keeps in the library is deleted at the end.
var _objects_before: Array = []


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
	_objects_before = ObjectLibrary.list("", "user").map(func(m: Dictionary) -> String: return m["id"])
	_cleanup()
	ObjectLibrary.editor_for(self).set("perf_after_change", false)
	commands = AssistantCommands.new()
	commands.allow_control = func() -> bool: return true
	commands.allow_room = func() -> bool: return true
	commands.room = RoomEditor.new()
	commands.room.perf_after_change = false
	root.add_child(commands.room)

	_test_schema()
	_test_conversion()
	await _test_apply()
	await _test_text_object()
	await _test_delete_refused()
	await _test_migration()
	_cleanup()
	main.queue_free()
	await _frames(2)
	print("test_room_objects: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


# --- The document: schema 3 and the built-ins -------------------------------------------------------------------

func _test_schema() -> void:
	for id: String in ["box", "sphere", "cylinder", "plane", "text", "particles"]:
		_check("built-in %s in the library" % id, not ObjectLibrary.get_object(id).is_empty()
				and ObjectLibrary.get_object(id)["source"] == "builtin")
	var box := ObjectLibrary.get_object("box")
	_check("the box: 1 m, one part named Box (%s)" % [box.get("size")], box.get("size") == [1.0, 1.0, 1.0]
			and (box["parts"] as Array).size() == 1 and box["parts"][0]["name"] == "Box" and box.get("primitive") == true)
	var text := ObjectLibrary.get_object("text")
	_check("text: a generator, no .glb", text.get("generator") == "text" and ObjectLibrary.glb("text").is_empty())
	var ok := RoomSchema.validate({"schema": 3, "parts": [{"name": "A", "object": "box", "scale": [1, 2, 0.5]},
			{"name": "B", "object": "text", "text": "Hi", "scale": 2}]}, "saved")
	_check("placements are a kept room's parts (%s)" % [ok["errors"]], ok["ok"])
	var old := RoomSchema.validate({"schema": 3, "parts": [{"name": "A", "type": "box", "size": [1, 1, 1]}]}, "saved")
	_check("a kept room of schema 3 has no shapes", not old["ok"])
	var picture := RoomSchema.validate({"schema": 3, "parts": [{"name": "A", "object": "plane",
			"material": {"texture_file": "01.img"}}]}, "saved")
	_check("nor a picture on a placement", not picture["ok"])
	var two := RoomSchema.validate({"schema": 2, "parts": [{"name": "A", "object": "box"}]}, "patch")
	_check("a placement needs schema 3 (%s)" % [two["errors"]], not two["ok"] and str(two["errors"]).contains("3"))
	var bad := RoomSchema.validate({"schema": 3, "parts": [{"name": "A", "object": "box", "text": "x"},
			{"name": "B", "object": "text"}, {"name": "C", "object": "Not An Id"}]}, "patch")
	var paths: Array = bad["errors"].map(func(e: Dictionary) -> String: return e["path"])
	_check("a placement's misuse refused with paths (%s)" % [paths], paths.has("$.parts[0].text")
			and paths.has("$.parts[1].text") and paths.has("$.parts[2].object"))
	_check("build_form: a box's scale is its size", RoomSchema.build_form({"name": "A", "object": "box",
			"scale": [1, 2, 3]}).get("size") == [1.0, 2.0, 3.0])
	_check("build_form: a text's scale its line height", is_equal_approx(float(RoomSchema.build_form({"name": "A",
			"object": "text", "text": "x", "scale": 2})["size"][0]), 0.2))


# --- Every part type kept as a placement ---------------------------------------------------------------------------

func _test_conversion() -> void:
	var ball := Marshalls.raw_to_base64(_ball_glb())
	var doc := {"schema": 2, "parts": [
		{"name": "Crate", "type": "box", "size": [1, 0.5, 0.25], "position": [0, 0.25, -2],
			"material": {"color": "#aa3322", "uv": "atlas"}, "widget": "clock"},
		{"name": "Moon", "type": "sphere", "size": [0.5], "scale": 2, "position": [0, 2, -3]},
		{"name": "Drum", "type": "cylinder", "size": [0.4, 0.1]},
		{"name": "Rug", "type": "plane", "size": [2, 3], "material": {"library_material": "oak_planks"}},
		{"name": "Sign", "type": "text", "text": "Hello", "size": [0.2], "text_options": {"color": "#ff0000"}},
		{"name": "Snow", "type": "particles", "size": [3, 2, 1], "particles": {"preset": "snow"}},
		{"name": "Ball", "type": "model", "model": ball, "position": [1, 1, -2], "scale": 0.5},
		{"name": "Ball two", "type": "model", "model": ball},
		{"name": "Shelf", "type": "model", "object": "wall_shelf", "model": ball},
		{"name": "Poster", "type": "plane", "size": [0.6, 0.9], "position": [0, 1.4, -2.9], "rotation": [90, 0, 0],
			"material": {"texture": _png(Color(0.2, 0.4, 0.8)), "emission": "#101010"}},
	]}
	var k := RoomKeep.keep(doc)
	_check("keep: every part type (%s)" % k.get("error", ""), not k.has("error"))
	if k.has("error"):
		return
	var parts := {}
	for p: Dictionary in k["doc"]["parts"]:
		parts[p["name"]] = p
	_check("schema 3, no shape left", int(k["doc"]["schema"]) == 3 and (k["doc"]["parts"] as Array).all(
			func(p: Dictionary) -> bool: return not p.has("type") and not p.has("size") and not p.has("model")))
	_check("a box: the primitive, its size as the scale, its material and widget kept (%s)" % parts["Crate"],
			parts["Crate"]["object"] == "box" and parts["Crate"]["scale"] == [1.0, 0.5, 0.25]
			and parts["Crate"]["material"] == {"color": "#aa3322"} and parts["Crate"]["widget"] == "clock")
	_check("a sphere: its diameter times its scale, 1 m: no scale (%s)" % parts["Moon"], parts["Moon"]["object"]
			== "sphere" and not parts["Moon"].has("scale"))
	_check("a cylinder: [d, h, d] (%s)" % parts["Drum"], parts["Drum"]["object"] == "cylinder"
			and parts["Drum"]["scale"] == [0.4, 0.1, 0.4])
	_check("a plane: [w, 1, d], a library material kept (%s)" % parts["Rug"], parts["Rug"]["object"] == "plane"
			and parts["Rug"]["scale"] == [2.0, 1.0, 3.0] and parts["Rug"]["material"]["library_material"] == "oak_planks")
	_check("a text: the generator, its line as the scale (%s)" % parts["Sign"], parts["Sign"]["object"] == "text"
			and is_equal_approx(float(parts["Sign"]["scale"]), 2.0) and parts["Sign"]["text"] == "Hello"
			and parts["Sign"]["text_options"]["color"] == "#ff0000")
	_check("particles: the generator, the area as the scale (%s)" % parts["Snow"], parts["Snow"]["object"]
			== "particles" and parts["Snow"]["scale"] == [3.0, 2.0, 1.0] and parts["Snow"]["particles"]["preset"] == "snow")
	var ball_id := str(parts["Ball"]["object"])
	var made := ObjectLibrary.get_object(ball_id)
	_check("an inline model: a user object named after the part, its md5 kept (%s)" % made, made.get("source") == "user"
			and made.get("name") == "Ball" and made.get("md5") == ObjectLibrary.md5_of(_ball_glb())
			and is_equal_approx(float(parts["Ball"]["scale"]), 0.5))
	_check("the same bytes twice: one object", parts["Ball two"]["object"] == ball_id)
	_check("a model naming a library object: that object", parts["Shelf"]["object"] == "wall_shelf")
	var poster := ObjectLibrary.get_object(str(parts["Poster"]["object"]))
	_check("a textured plane: a picture object, mount wall (%s)" % poster, poster.get("source") == "user"
			and poster.get("mount") == "wall" and poster.get("picture") == true and "picture" in poster.get("tags", [])
			and poster.get("name") == "Poster")
	_check("its placement keeps the rest of the material, no picture (%s)" % parts["Poster"].get("material"),
			parts["Poster"].get("material") == {"emission": "#101010"})
	# The plane faces +Z in the object: the placement is turned back, so it faces the way the part did.
	var r: Array = parts["Poster"]["rotation"]
	var b := Basis.from_euler(Vector3(deg_to_rad(float(r[0])), deg_to_rad(float(r[1])), deg_to_rad(float(r[2]))))
	_check("it faces where the part faced (%s)" % [r], (b * Vector3.BACK).is_equal_approx(Basis.from_euler(
			Vector3(deg_to_rad(90.0), 0, 0)) * Vector3.UP))
	var said := RoomKeep.summary(k["kept"])
	_check("the summary names what was kept (%s)" % said, said.contains("Ball") and said.contains("Poster")
			and not said.contains("Crate"))
	var again := RoomKeep.keep(doc)
	_check("kept again: the same objects, none new", not again.has("error") and (again["created"] as Array).is_empty()
			and (again["kept"] as Array).all(func(x: Dictionary) -> bool: return not x["new"]))
	# A refused change takes what it made out again.
	RoomKeep.forget(k["created"])
	_check("forget: the objects made are gone", ObjectLibrary.get_object(ball_id).is_empty())


# --- Through the room editor: a poster and a model, kept; room_state; a primitive's part --------------------------

func _test_apply() -> void:
	main.set_environment("dim_room")
	await _frames(3)
	var count := ObjectLibrary.list("", "user").size()
	var a: Dictionary = await commands.run("new_room", {"room": {"schema": 2, "name": ROOM, "base": "dim_room",
			"parts": [{"name": "Poster", "type": "plane", "size": [0.6, 0.9], "position": [-1.5, 1.4, -2.9],
				"rotation": [90, 0, 0], "material": {"texture": _png(Color(0.2, 0.4, 0.8))}},
			{"name": "Cube", "type": "box", "size": [0.4, 0.4, 0.4], "position": [1, 0.2, -2]},
			{"name": "Ball", "type": "model", "model": Marshalls.raw_to_base64(_ball_glb()), "position": [0, 1, -2]}]}})
	_check("a room of shapes and a model (%s)" % a.get("error", ""), a.get("ok") == true)
	if a.get("ok") != true:
		return
	var kept: Array = a["result"].get("kept_objects", [])
	_check("the reply names what it kept (%s, %s)" % [kept, a.get("summary")], kept.size() == 2
			and str(a.get("summary", "")).contains("kept") and str(a.get("summary", "")).contains("Poster"))
	_check("two new user objects", ObjectLibrary.list("", "user").size() == count + 2)
	var doc: Dictionary = main.env.get("doc")
	var text := FileAccess.get_file_as_string(AssistantRoom.json_path(ROOM))
	_check("the kept room: schema 3, placements, no pictures or models in it", text.contains("\"schema\": 3")
			and not text.contains("texture") and not text.contains("\"model") and not text.contains("\"type\"")
			and DirAccess.get_files_at(AssistantRoom.files_dir(ROOM)).is_empty())
	var poster := _part("Poster")
	_check("the poster: a picture object, mount wall", ObjectLibrary.get_object(str(poster.get("object")))
			.get("mount") == "wall")
	var mat := _material_of("Poster")
	_check("the placement shows the picture, self-lit, white (%s)" % mat, mat != null
			and mat.get_shader_parameter("use_texture") == true and mat.get_shader_parameter("self_lit") == true
			and (mat.get_shader_parameter("albedo") as Color).is_equal_approx(Color.WHITE))
	var tex: Texture2D = mat.get_shader_parameter("albedo_texture") if mat != null else null
	var img: Image = tex.get_image() if tex != null else null
	_check("the picture itself (%s)" % [img.get_pixel(1, 1) if img != null else null], img != null
			and absf(img.get_pixel(1, 1).r - 0.2) < 0.02 and absf(img.get_pixel(1, 1).b - 0.8) < 0.02)
	# The same poster again in a change: the same object.
	a = await commands.run("add_shape", {"name": "Poster two", "type": "plane", "size": [0.6, 0.9],
			"position": [1.5, 1.4, -2.9], "rotation": [90, 0, 0], "material": {"texture": _png(Color(0.2, 0.4, 0.8))}})
	_check("the same picture on the same shape: the same object (%s)" % a.get("error", ""), a.get("ok") == true
			and _part("Poster two").get("object") == poster.get("object")
			and ObjectLibrary.list("", "user").size() == count + 2
			and (a["result"].get("kept_objects", []) as Array).all(func(x: Dictionary) -> bool: return not x["new"])
			and not str(a.get("summary", "")).contains("kept"))
	# room_state: every placement with its object's id and name; a primitive's one part.
	var st: Dictionary = (await commands.run("room_state", {}))["result"]
	var cube := {}
	for o: Dictionary in st["objects"]:
		if o["name"] == "Cube":
			cube = o
	_check("room_state lists placements with their object (%s)" % cube, cube.get("object") == "box"
			and cube.get("object_name") == "Box" and (cube.get("parts", []) as Array).size() == 1
			and cube["parts"][0]["name"] == "Box" and (st["objects"] as Array).size() == 4)
	_check("room_state says what a placement is", st.get("placements", {}).get("primitives", []).has("box"))
	a = await commands.run("recolour", {"match": "Cube/Box", "color": "#00ff00"})
	_check("a primitive's part by name (%s)" % a.get("error", ""), a.get("ok") == true
			and (_material_of("Cube").get_shader_parameter("albedo") as Color).is_equal_approx(Color(0, 1, 0)))
	a = await commands.run("recolour", {"match": "Poster", "color": "#ff8080"})
	_check("a whole placement's colour: its material, the picture kept (%s)" % a.get("error", ""), a.get("ok") == true
			and _part("Poster").get("material", {}).get("color") == "#ff8080"
			and _material_of("Poster").get_shader_parameter("use_texture") == true)
	# A change refused after its parts were kept (over the cost cap) takes the object it made out again.
	count = ObjectLibrary.list("", "user").size()
	var parts: Array = [{"name": "Far", "type": "model", "model": Marshalls.raw_to_base64(_ball_glb(24)),
			"position": [0, 1, -2]}]
	for i in ceili(RoomSchema.LIMITS["cost"] / (RoomSchema.COSTS["part"] + RoomSchema.COSTS["blend"])) + 1:
		parts.append({"name": "g%d" % i, "type": "box", "size": [0.1, 0.1, 0.1],
				"position": [float(i % 30) * 0.1 - 1.5, 1.5 + float(i / 30) * 0.15, -3], "material": {"color": "#ffffff80"}})
	a = await commands.run("room_apply", {"room": {"schema": 2, "parts": parts}})
	_check("refused over the cost cap (%s); nothing kept" % a.get("error", ""), a.get("ok") == false
			and a.get("limit") == "cost" and ObjectLibrary.list("", "user").size() == count)


# --- Text is an object ------------------------------------------------------------------------------------------

func _test_text_object() -> void:
	var r := await DevCommands.execute("object_place", {"id": "text", "position": [0, 2, -2.5]}, false)
	_check("object_place text without words: refused (%s)" % r.get("error", ""), not r["ok"]
			and str(r.get("error", "")).contains("text"))
	r = await DevCommands.execute("object_place", {"id": "text", "text": "Now showing", "position": [0, 2, -2.5],
			"scale": 2.0, "text_options": {"color": "#ffcc66"}}, false)
	_check("object_place text (%s)" % r.get("error", ""), r["ok"])
	if not r["ok"]:
		return
	var name: String = r["result"]["placed"]
	var label := main.env.get_node_or_null("%s/%s/Text" % [AssistantRoom.LAYER, name]) as Label3D
	_check("a Label3D, a line 0.2 m high", label != null and label.text == "Now showing"
			and absf(label.pixel_size * label.font.get_height(label.font_size) - 0.2) < 0.001
			and label.modulate.is_equal_approx(Color("#ffcc66")))
	var p := _part(name)
	_check("kept as a placement of text (%s)" % p, p.get("object") == "text" and p.get("text") == "Now showing"
			and not p.has("type"))
	r = await DevCommands.execute("object_place", {"id": "box", "position": [2, 0.5, -2]}, false)
	var box := _part(str(r.get("result", {}).get("placed", "")))
	_check("object_place box: only the id, no model data (%s)" % box, r["ok"] and box.get("object") == "box"
			and not box.has("model"))


# --- object_delete refused while a kept room places the object -----------------------------------------------------

func _test_delete_refused() -> void:
	var id := str(_part("Ball").get("object", ""))
	var r := await DevCommands.execute("object_delete", {"id": id}, false)
	_check("object_delete refused, naming the room (%s)" % r.get("error", ""), not r["ok"]
			and str(r.get("error", "")).contains(ROOM) and not ObjectLibrary.get_object(id).is_empty())
	_check("rooms_using names it (the Objects tab's Delete asks the same)", ObjectLibrary.rooms_using(id).has(ROOM))
	var a: Dictionary = await commands.run("remove", {"name": "Ball"})
	r = await DevCommands.execute("object_delete", {"id": id}, false)
	_check("taken out of the room: deleted (%s)" % r.get("error", ""), a.get("ok") == true and r["ok"]
			and ObjectLibrary.get_object(id).is_empty())


# --- A kept room of schema 2 on disk: converted when it loads, saved as schema 3 ------------------------------------

func _test_migration() -> void:
	var dir := AssistantRoom.files_dir(OLD_ROOM)
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("01.glb"), FileAccess.WRITE)
	f.store_buffer(_ball_glb(20))
	f.close()
	f = FileAccess.open(dir.path_join("02.img"), FileAccess.WRITE)
	f.store_buffer(Marshalls.base64_to_raw(_png(Color(0.9, 0.1, 0.1))))
	f.close()
	var old := {"schema": 2, "name": OLD_ROOM, "base": "dim_room", "light": {"ambient": 0.3},
		"parts": [{"name": "Globe", "type": "model", "model_file": "01.glb", "position": [0, 1, -2]},
			{"name": "Photo", "type": "box", "size": [0.5, 0.4, 0.02], "position": [1, 1.5, -2.9],
				"material": {"texture_file": "02.img", "uv": "front_only", "color": "#202020"}},
			{"name": "Lamp", "type": "cylinder", "size": [0.3, 0.05], "position": [-1, 1.5, -2.5],
				"rotation": [90, 0, 0], "widget": "clock"}],
		"recolour": []}
	f = FileAccess.open(AssistantRoom.json_path(OLD_ROOM), FileAccess.WRITE)
	f.store_string(JSON.stringify(old, " "))
	f.close()
	var count := ObjectLibrary.list("", "user").size()
	var room := AssistantRoom.load_saved(AssistantRoom.json_path(OLD_ROOM))
	_check("a kept room of schema 2 loads", room != null)
	if room == null:
		return
	var layer: Node = room.get_node(AssistantRoom.LAYER)
	_check("its model and its photo built from the library", layer.get_node_or_null("Globe/Model") != null
			and layer.get_node_or_null("Photo/Model") != null and layer.get_node_or_null("Lamp/Widget") != null)
	room.free()
	var j := JSON.new()
	j.parse(FileAccess.get_file_as_string(AssistantRoom.json_path(OLD_ROOM)))
	var saved: Dictionary = j.data
	_check("saved back as schema 3 (%s)" % saved.get("schema"), int(saved.get("schema", 0)) == 3
			and RoomSchema.validate(saved, "saved")["ok"])
	var by := {}
	for p: Dictionary in saved["parts"]:
		by[p["name"]] = p
	_check("its parts placements: a user model, a picture object, the cylinder", ObjectLibrary.get_object(
			str(by["Globe"]["object"])).get("source") == "user" and ObjectLibrary.get_object(str(by["Photo"]["object"]))
			.get("picture") == true and by["Lamp"]["object"] == "cylinder" and by["Lamp"].get("widget") == "clock")
	_check("a thin box with a picture hangs on a wall", ObjectLibrary.get_object(str(by["Photo"]["object"]))
			.get("mount") == "wall")
	_check("two objects kept, the model and picture files gone", ObjectLibrary.list("", "user").size() == count + 2
			and DirAccess.get_files_at(dir).is_empty())
	room = AssistantRoom.load_saved(AssistantRoom.json_path(OLD_ROOM))
	_check("loaded again: nothing more kept", room != null and ObjectLibrary.list("", "user").size() == count + 2)
	if room != null:
		var photo := room.get_node(AssistantRoom.LAYER).find_children("*", "MeshInstance3D", true, false).filter(
				func(n: Node) -> bool: return room.get_node(AssistantRoom.LAYER + "/Photo").is_ancestor_of(n))
		_check("the photo's front shows the picture, its sides the colour", not photo.is_empty()
				and ((photo[0] as MeshInstance3D).get_active_material(0) as ShaderMaterial)
						.get_shader_parameter("use_texture") == true
				and (((photo[0] as MeshInstance3D).get_active_material(1) as ShaderMaterial)
						.get_shader_parameter("albedo") as Color).is_equal_approx(Color("#202020")))
		room.free()
	# One that can't be converted (its model file is not a model) is built as it is, and left as it was.
	f = FileAccess.open(dir.path_join("09.glb"), FileAccess.WRITE)
	f.store_buffer("not a model".to_utf8_buffer())
	f.close()
	var broken := old.duplicate(true)
	broken["parts"] = [{"name": "Broken", "type": "model", "model_file": "09.glb"},
			{"name": "Box", "type": "box", "size": [1, 1, 1]}]
	f = FileAccess.open(AssistantRoom.json_path(OLD_ROOM), FileAccess.WRITE)
	f.store_string(JSON.stringify(broken, " "))
	f.close()
	room = AssistantRoom.load_saved(AssistantRoom.json_path(OLD_ROOM))
	_check("a room that can't be converted still loads as it was", room == null or room.get_node_or_null(
			AssistantRoom.LAYER + "/Box") != null)
	if room != null:
		room.free()
	_check("and is left at schema 2", FileAccess.get_file_as_string(AssistantRoom.json_path(OLD_ROOM)).contains(
			"\"schema\": 2"))


# --- Helpers ------------------------------------------------------------------------------------------------------

func _part(name: String) -> Dictionary:
	var doc: Dictionary = main.env.get("doc") if main.env != null and main.env.get("doc") is Dictionary else {}
	for p: Dictionary in doc.get("parts", []):
		if p["name"] == name:
			return p
	return {}


## A part's material: a shape's Mesh, or the first mesh of a placed object.
func _material_of(part: String) -> ShaderMaterial:
	var node: Node = main.env.get_node_or_null("%s/%s" % [AssistantRoom.LAYER, part])
	if node == null:
		return null
	var found := node.find_children("*", "MeshInstance3D", true, false)
	var mi: MeshInstance3D = node.get_node("Mesh") as MeshInstance3D if node.has_node("Mesh") \
			else (found[0] if not found.is_empty() else null)
	if mi == null:
		return null
	return (mi.material_override if mi.material_override != null else mi.get_active_material(0)) as ShaderMaterial


func _png(c: Color) -> String:
	var img := Image.create_empty(4, 4, false, Image.FORMAT_RGB8)
	img.fill(c)
	return Marshalls.raw_to_base64(img.save_png_to_buffer())


## A small sphere as a .glb (radial segments: another count, other bytes).
func _ball_glb(radial := 12) -> PackedByteArray:
	var root_node := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.name = "Ball"
	var s := SphereMesh.new()
	s.radial_segments = radial
	s.rings = 6
	s.radius = 0.2
	s.height = 0.4
	mi.mesh = s
	root_node.add_child(mi)
	var bytes := ObjectLibrary.to_glb(root_node)
	root_node.free()
	return bytes


func _cleanup() -> void:
	for name: String in [ROOM, OLD_ROOM]:
		var dir := AssistantRoom.files_dir(name)
		if DirAccess.dir_exists_absolute(dir):
			for f in DirAccess.get_files_at(dir):
				DirAccess.remove_absolute(dir.path_join(f))
			DirAccess.remove_absolute(dir)
		DirAccess.remove_absolute(AssistantRoom.json_path(name))
	for m: Dictionary in ObjectLibrary.list("", "user"):
		if not (m["id"] in _objects_before):
			ObjectLibrary.delete(m["id"])
			ObjectLibrary.purge(m["id"])


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL " + what)
