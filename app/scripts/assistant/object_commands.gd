extends RefCounted

## The object library's commands (object_library.gd; docs/assistant.md "Objects"), registered for every client of the
## registry (scripts/dev/command_host.gd) with their assistant levels: object_library and object_info read; object_import,
## object_place, object_move and object_delete change the room or the library (level room). A part's colour is
## `recolour` with "<placed name>/<part name>" (scripts/assistant/assistant_commands.gd).
##
## The Room tab (ui/object_section.gd, ui/object_placer.gd) calls the same functions: place(), move(), remove_placed(),
## recolour_part(). Each change goes through a room editor (room_editor.gd: an assistant's own, else this app's
## ObjectLibrary.EDITOR_NODE), shows at once, is kept, and comes back with an undo: the room as it was (a kept room
## built again from its document, or the stock room shown again).

const DevCommands := preload("res://scripts/dev/dev_commands.gd")
const ObjectLibrary := preload("res://scripts/assistant/object_library.gd")
const RoomSchema := preload("res://scripts/assistant/room_schema.gd")
const RoomBounds := preload("res://scripts/assistant/room_bounds.gd")
const WorkerTask := preload("res://scripts/dev/worker_task.gd")

## "on the floor in front": this far ahead of the viewer's head; a free object: this far, at eye height.
const FLOOR_AHEAD := 1.3
const FRONT_AHEAD := 1.5
const IMPORT_TIMEOUT := 60.0
const AT := ["", "wall", "floor", "ceiling", "front"]


static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


static func _main() -> Node:
	var tree := _tree()
	return tree.current_scene if tree != null else null


static func register_commands(_host: Node = null) -> void:
	var R := DevCommands
	R.register("object_library", func(a: Dictionary, _ctx: DevCommands.Call) -> Variant:
		var out: Array = []
		for m: Dictionary in ObjectLibrary.list(str(a["tag"]), str(a["source"])):
			out.append({"id": m["id"], "name": m["name"], "tags": m.get("tags", []), "source": m["source"],
					"mount": m["mount"], "size": m["size"], "parts": (m.get("parts", []) as Array).size()})
		return {"objects": out, "count": out.size(), "mounts": ObjectLibrary.MOUNTS}, {
		"description": "The object library: things to put in the room, built in or imported (a .glb or an SVG), each "
				+ "with parts that can be recoloured one by one once placed.",
		"params": [{"name": "tag", "type": "string", "default": "", "description": "Only objects with this tag "
				+ "(empty: all)."},
				{"name": "source", "type": "string", "default": "all", "enum": ["all", "builtin", "user"],
				"description": "all, builtin (made with the app) or user (imported)."}],
		"assistant": "read", "title": "List the object library", "returns": "{objects: [{id, name, tags, source, "
				+ "mount, size, parts}], count, mounts}"})
	R.register("object_info", func(a: Dictionary, ctx: DevCommands.Call) -> Variant:
		if str(a["placed"]) != "":
			var main := _main()
			var placed: Array = (load("res://scripts/assistant/assistant_room.gd") as GDScript).call(
					"placed_objects", main.env if main != null else null)
			for p: Dictionary in placed:
				if p["name"] == a["placed"]:
					return p
			return ctx.fail("nothing placed is called %s (room_state's objects lists them)" % a["placed"])
		var m := ObjectLibrary.get_object(str(a["id"]))
		if m.is_empty():
			return ctx.fail("no object %s (object_library lists them)" % a["id"])
		return m, {
		"description": "One library object (its parts with their colours, size, mount) or one placed in the room "
				+ "(its parts as they show now and which recolour sets each).",
		"params": [{"name": "id", "type": "string", "default": "", "description": "A library object's id "
				+ "(object_library)."},
				{"name": "placed", "type": "string", "default": "", "description": "Instead: the name of an object "
				+ "placed in the room (room_state's objects)."}],
		"assistant": "read", "title": "An object's parts", "returns": "{id, name, mount, size, parts: [{name, color, "
				+ "texture}]} or {name, object, parts: [{name, color, recolour}]}"})
	R.register("object_import", func(a: Dictionary, ctx: DevCommands.Call) -> Variant:
		return await _cmd_import(a, ctx), {
		"description": "Adds an object to the library from a .glb (taken as it is) or an SVG drawing (made solid: "
				+ "each top-level path or group a part). Kept in the headset's own data, never in the app.",
		"params": [{"name": "name", "type": "string", "required": true, "description": "What it is called "
				+ "(letters, digits, space, - and _)."},
				{"name": "data", "type": "string", "default": "", "description": "The file, base64."},
				{"name": "path", "type": "string", "default": "", "description": "Instead of data: a file on the "
				+ "headset (the dev link only)."},
				{"name": "format", "type": "string", "default": "", "enum": ["", "glb", "svg"],
				"description": "glb or svg; empty: from the data."},
				{"name": "tags", "type": "array", "default": [], "description": "Words to find it by."},
				{"name": "mount", "type": "string", "default": "", "enum": ["", "wall", "floor", "table", "ceiling",
				"free"], "description": "How it sits: wall, floor, table, ceiling or free; empty: guessed (an SVG: "
				+ "wall)."},
				{"name": "width", "type": "float", "default": 0.4, "description": "SVG: its width in metres."},
				{"name": "depth", "type": "float", "default": 0.02, "description": "SVG: how far it stands out, "
				+ "metres."},
				{"name": "bevel", "type": "float", "default": -1.0, "description": "SVG: the chamfer on its edges, "
				+ "metres; -1 a small one to suit."},
				{"name": "part_names", "type": "array", "default": [], "description": "SVG: names for its top-level "
				+ "elements in order; the same name twice joins them into one part."}],
		"level": "change", "assistant": "room", "title": "Import an object",
		"returns": "{id, name, parts, triangles, mount, size, warnings}"})
	R.register("object_place", func(a: Dictionary, ctx: DevCommands.Call) -> Variant:
		return _give(ctx, await place(_tree(), ctx.caller, str(a["id"]), a)), {
		"description": "Puts a library object in the room: at a position, on the wall the viewer looks at, on the "
				+ "floor in front of them, on the ceiling, or in front at eye height. It shows at once and is kept.",
		"params": [{"name": "id", "type": "string", "required": true, "description": "The object's id "
				+ "(object_library)."},
				{"name": "name", "type": "string", "default": "", "description": "Its name in the room (its parts are "
				+ "<name>/<part>); empty: the object's name, numbered when taken."},
				{"name": "at", "type": "string", "default": "", "enum": AT, "description": "wall (the one the viewer "
				+ "looks at), floor (in front of the viewer), ceiling, front (at eye height); empty: position, else "
				+ "where its mount says."},
				{"name": "position", "type": "array", "default": [], "description": "[x, y, z] metres in the room "
				+ "frame (room_state), instead of at."},
				{"name": "rotation", "type": "array", "default": [], "description": "[x, y, z] degrees, with "
				+ "position."},
				{"name": "turn", "type": "float", "default": 0.0, "description": "Degrees round the wall's normal or "
				+ "round up, with at."},
				{"name": "scale", "type": "float", "default": 1.0, "description": "Its size, 1 as made (0.05 to 20)."}],
		"level": "change", "assistant": "room", "title": "Place an object",
		"returns": "{state: kept, placed, name, warnings, perf, ...}"})
	R.register("object_move", func(a: Dictionary, ctx: DevCommands.Call) -> Variant:
		return _give(ctx, await move(_tree(), ctx.caller, str(a["name"]), a)), {
		"description": "Moves, turns or resizes something placed in the room; what is left out stays as it is.",
		"params": [{"name": "name", "type": "string", "required": true, "description": "Its name in the room "
				+ "(room_state's objects)."},
				{"name": "at", "type": "string", "default": "", "enum": AT, "description": "wall, floor, ceiling or "
				+ "front: as in object_place."},
				{"name": "position", "type": "array", "default": [], "description": "[x, y, z] metres in the room "
				+ "frame."},
				{"name": "rotation", "type": "array", "default": [], "description": "[x, y, z] degrees."},
				{"name": "turn", "type": "float", "default": 0.0, "description": "Degrees round the wall's normal or "
				+ "round up, with at."},
				{"name": "scale", "type": "float", "default": 0.0, "description": "Its size, 1 as made; 0: as it is."}],
		"level": "change", "assistant": "room", "title": "Move a placed object",
		"returns": "{state: kept, name, warnings, perf, ...}"})
	R.register("object_delete", func(a: Dictionary, ctx: DevCommands.Call) -> Variant:
		var id := str(a["id"])
		var m := ObjectLibrary.get_object(id)
		var r := ObjectLibrary.delete(id)
		if not r["ok"]:
			return ctx.fail(str(r["error"]))
		ctx.summary = "deleted %s from the library" % m.get("name", id)
		ctx.undo = func() -> void: ObjectLibrary.restore(id)
		ctx.cleanup = func() -> void: ObjectLibrary.purge(id)
		_sync_tab()
		return {"deleted": id, "name": m.get("name", id), "note": "copies placed in rooms stay (remove takes them out)"}, {
		"description": "Deletes an imported object from the library (built-in ones stay). Copies already placed in "
				+ "rooms stay; remove takes one out of the room.",
		"params": [{"name": "id", "type": "string", "required": true, "description": "The user object's id "
				+ "(object_library source user)."}],
		"level": "change", "assistant": "room", "destructive": true, "title": "Delete an imported object",
		"returns": "{deleted, name}"})


## A shared operation's reply ({ok, result | error, summary, undo, ...}) handed to the registry.
static func _give(ctx: DevCommands.Call, r: Dictionary) -> Variant:
	for k: String in r:
		if not (k in ["ok", "result", "error", "summary", "undo"]):
			ctx.reply[k] = r[k]
	if not bool(r.get("ok", false)):
		return ctx.fail(str(r.get("error", "")))
	ctx.summary = str(r.get("summary", ""))
	if r.get("undo") is Callable:
		ctx.undo = r["undo"]
	_sync_tab()
	return r.get("result")


static func _cmd_import(a: Dictionary, ctx: DevCommands.Call) -> Variant:
	var bytes := PackedByteArray()
	if str(a["path"]) != "":
		# A file on the headset: the dev link's (it reads any file anyway), never the assistant's.
		if ctx.caller != null and ctx.caller.has_method("_own"):
			return ctx.fail("path is for the dev link only: send the file as data (base64)")
		if not FileAccess.file_exists(str(a["path"])):
			return ctx.fail("no file %s" % a["path"])
		bytes = FileAccess.get_file_as_bytes(str(a["path"]))
	elif str(a["data"]) != "":
		if str(a["data"]).length() / 4 * 3 > int(RoomSchema.LIMITS["model_bytes"]):
			return ctx.fail("model_bytes: at most %d" % RoomSchema.LIMITS["model_bytes"])
		bytes = Marshalls.base64_to_raw(str(a["data"]))
	if bytes.is_empty():
		return ctx.fail("give data (the file, base64)")
	var format := str(a["format"])
	if format == "":
		format = "glb" if bytes.size() >= 4 and bytes.decode_u32(0) == 0x46546C67 else "svg"
	var name := str(a["name"])
	var tags: Array = a["tags"]
	var mount := str(a["mount"])
	var job: Callable
	if format == "glb":
		job = func() -> Variant: return ObjectLibrary.import_glb(bytes, name, tags, mount)
	else:
		var text := bytes.get_string_from_utf8()
		var options := {"width": float(a["width"]), "depth": float(a["depth"]), "bevel": float(a["bevel"]),
				"part_names": a["part_names"]}
		job = func() -> Variant: return ObjectLibrary.import_svg(text, name, tags, mount if mount != "" else "wall",
				options)
	var w: Dictionary = await WorkerTask.run(_tree(), job, IMPORT_TIMEOUT)
	if not w["done"]:
		return ctx.fail("the import took over %d s; send a smaller file" % int(IMPORT_TIMEOUT))
	var r: Dictionary = w["result"]
	if not r["ok"]:
		if r.has("limit"):
			ctx.reply["refused"] = true
			ctx.reply["limit"] = r["limit"]
		return ctx.fail(str(r["error"]))
	var m: Dictionary = r["manifest"]
	var id := str(m["id"])
	ctx.summary = "imported %s" % m["name"]
	ctx.undo = func() -> void:
		ObjectLibrary.delete(id)
		ObjectLibrary.purge(id)
		_sync_tab()
	_sync_tab()
	return {"id": id, "name": m["name"], "mount": m["mount"], "size": m["size"], "triangles": m["triangles"],
			"parts": (m["parts"] as Array).map(func(p: Dictionary) -> String: return p["name"]),
			"warnings": r.get("warnings", [])}


# --- The changes (shared with the Room tab) -------------------------------------------------------------------------

## Puts library object `id` in the room. opts: name, at, position, rotation, turn, scale.
static func place(tree: SceneTree, caller: Object, id: String, opts: Dictionary) -> Dictionary:
	var m := ObjectLibrary.get_object(id)
	if m.is_empty():
		return {"ok": false, "error": "no object %s (object_library lists them)" % id}
	var bytes := ObjectLibrary.glb(id)
	if bytes.is_empty():
		return {"ok": false, "error": "%s has no model file" % id}
	var main := tree.current_scene
	var editor := ObjectLibrary.editor_for(tree, caller)
	var doc: Dictionary = editor.current_doc()
	var names: Array = (doc.get("parts", []) as Array).map(func(p: Dictionary) -> String: return str(p["name"]))
	var name := ObjectLibrary.clean_name(str(opts.get("name", "")))
	if name != "" and name in names:
		return {"ok": false, "error": "something called %s is in the room already (object_move moves it)" % name}
	if name == "":
		name = unique_name(str(m["name"]), names)
	var spot := spot_for(main, ObjectLibrary.bounds_of(m), str(m.get("mount", "free")), opts)
	if spot.has("error"):
		return {"ok": false, "error": spot["error"]}
	var part := {"name": name, "type": "model", "object": id, "model": Marshalls.raw_to_base64(bytes),
			"position": spot["position"], "rotation": spot["rotation"], "scale": spot["scale"]}
	if m.has("widget"):
		part["widget"] = m["widget"]
		part["widget_options"] = m.get("widget_options", {})
	var patch := {"schema": RoomSchema.VERSION, "parts": [part]}
	if not _assistant_room(main):
		patch["name"] = room_name(main)
	var undo := undo_for(editor, main)
	var r: Dictionary = await editor.apply("patch", patch, "add %s" % name)
	if r.get("ok") == true:
		r["undo"] = undo
		r["result"]["placed"] = name
	return r


## Moves, turns or resizes part `name` of the room. opts: at, position, rotation, turn, scale (0 or absent: as is).
static func move(tree: SceneTree, caller: Object, name: String, opts: Dictionary) -> Dictionary:
	var main := tree.current_scene
	var editor := ObjectLibrary.editor_for(tree, caller)
	var doc: Dictionary = editor.current_doc()
	var part := {}
	for p: Dictionary in doc.get("parts", []):
		if p["name"] == name:
			part = p.duplicate(true)
	if part.is_empty():
		return {"ok": false, "error": "nothing in the room is called %s (room_state's objects lists them)" % name}
	var has_position: bool = opts.get("position") is Array and (opts["position"] as Array).size() == 3
	var has_rotation: bool = opts.get("rotation") is Array and (opts["rotation"] as Array).size() == 3
	var scale := float(opts.get("scale", 0.0))
	var at := str(opts.get("at", ""))
	if not has_position and not has_rotation and scale <= 0.0 and at == "":
		return {"ok": false, "error": "give at, position, rotation or scale"}
	var s: Variant = part.get("scale", 1.0)
	var k: float = scale if scale > 0.0 else (float(s) if s is float or s is int else 1.0)
	if at != "":
		var node: Node = main.env.get_node_or_null("AssistantLayer/" + name) if main.env != null else null
		var bounds: AABB = node.get_meta("local_aabb") if node != null and node.has_meta("local_aabb") \
				else ObjectLibrary.bounds_of(ObjectLibrary.get_object(str(part.get("object", ""))))
		var mount := str(ObjectLibrary.get_object(str(part.get("object", ""))).get("mount", "free"))
		var spot := spot_for(main, bounds, mount, {"at": at, "turn": opts.get("turn", 0.0), "scale": k})
		if spot.has("error"):
			return {"ok": false, "error": spot["error"]}
		part["position"] = spot["position"]
		part["rotation"] = spot["rotation"]
	if has_position:
		part["position"] = opts["position"]
	if has_rotation:
		part["rotation"] = opts["rotation"]
	if scale > 0.0:
		if scale < 0.05 or scale > 20.0:
			return {"ok": false, "error": "scale: 0.05 to 20"}
		part["scale"] = scale
	var undo := undo_for(editor, main)
	var r: Dictionary = await editor.apply("patch", {"schema": RoomSchema.VERSION, "parts": [part]}, "move %s" % name)
	if r.get("ok") == true:
		r["undo"] = undo
	return r


## Takes part `name` out of the room (its part-level recolours with it).
static func remove_placed(tree: SceneTree, caller: Object, name: String) -> Dictionary:
	var main := tree.current_scene
	var editor := ObjectLibrary.editor_for(tree, caller)
	var undo := undo_for(editor, main)
	var r: Dictionary = await editor.apply("patch", {"schema": RoomSchema.VERSION, "remove": [name]}, "remove %s"
			% name)
	if r.get("ok") == true:
		r["undo"] = undo
	return r


## A part-level colour: `match` "<placed>/<part>" (patterns), `material` a material object, or null: back to the
## part's own colours (every entry the pattern covers goes).
static func recolour_part(tree: SceneTree, caller: Object, match: String, material: Variant) -> Dictionary:
	var main := tree.current_scene
	var editor := ObjectLibrary.editor_for(tree, caller)
	if RoomSchema.split_match(match).is_empty():
		return {"ok": false, "error": "a part is \"<placed name>/<part name>\""}
	var layer: Node = main.env.get_node_or_null("AssistantLayer") if main.env != null else null
	var assistant_room := load("res://scripts/assistant/assistant_room.gd") as GDScript
	if (assistant_room.call("part_targets", layer, match) as Array).is_empty():
		return {"ok": false, "error": "%s matches no part of anything placed (object_info with placed lists the "
				% match + "parts)"}
	var entries := recolour_entries(editor.current_doc(), match, material)
	if entries.is_empty():
		return {"ok": false, "error": "%s has no colour of its own to undo" % match}
	var undo := undo_for(editor, main)
	var r: Dictionary = await editor.apply("patch", {"schema": RoomSchema.VERSION, "recolour": entries},
			"recolour %s" % match)
	if r.get("ok") == true:
		r["undo"] = undo
	return r


## The recolour entries a part-level change needs: the pattern with its material (entry_material()); or, to reset
## (material null), a removal of every entry the pattern covers.
static func recolour_entries(doc: Dictionary, match: String, material: Variant) -> Array:
	if material is Dictionary:
		return [{"match": match, "material": entry_material(doc, match, material)}]
	var out: Array = []
	for r: Dictionary in doc.get("recolour", []):
		var m := str(r["match"])
		if not RoomSchema.split_match(m).is_empty() and (m == match or m.match(match)):
			out.append({"match": m, "material": null})
	return out


## The material a recolour entry for `match` gets: the change itself (it replaces the entry with the same match), or,
## when that entry shows a library material or an effect, or the change brings one, the change on top of it
## (RoomSchema.merge_material()): a colour, tint, tiling or emission then changes the material instead of replacing
## it, and an effect keeps the colour (or the library material, when it layers) under it.
static func entry_material(doc: Dictionary, match: String, change: Dictionary) -> Dictionary:
	for r: Dictionary in doc.get("recolour", []):
		if str(r["match"]) == match and r.get("material") is Dictionary:
			var old: Dictionary = r["material"]
			if old.has("library_material") or old.has("effect") or change.has("library_material") \
					or change.has("effect"):
				return RoomSchema.merge_material(old, change)
	return change


# --- Where, names, undo ----------------------------------------------------------------------------------------------

## Where an object goes: {position, rotation, scale} or {error}. opts: position (+ rotation), or at (wall, floor,
## ceiling, front; empty: by its mount) with turn, and scale.
static func spot_for(main: Node, bounds: AABB, mount: String, opts: Dictionary) -> Dictionary:
	var k := float(opts.get("scale", 1.0))
	if k <= 0.0:
		k = 1.0
	if k < 0.05 or k > 20.0:
		return {"error": "scale: 0.05 to 20"}
	var pos: Variant = opts.get("position")
	if pos is Array and (pos as Array).size() == 3:
		var rot: Variant = opts.get("rotation")
		return {"position": pos, "rotation": rot if rot is Array and (rot as Array).size() == 3 else [0, 0, 0],
				"scale": k}
	var at := str(opts.get("at", ""))
	if at == "":
		at = {"wall": "wall", "floor": "floor", "table": "floor", "ceiling": "ceiling"}.get(mount, "front")
	var room_editor := load("res://scripts/assistant/room_editor.gd") as GDScript
	var v: Dictionary = room_editor.call("viewer_state", main)
	var head := _vec(v.get("head", v["eye"]))
	var facing := _vec(v.get("head_facing", [0, 0, -1]))
	var level := Vector3(facing.x, 0.0, facing.z)
	level = level.normalized() if level.length() > 0.01 else Vector3.FORWARD
	var inside := room_inside(main)
	var turn := float(opts.get("turn", 0.0))
	match at:
		"wall":
			var hit := ObjectLibrary.aim(head, level, inside)
			if str(hit.get("surface", "")) != "wall":
				return {"error": "no wall where the viewer looks (this room has open sides there): give a position, "
						+ "or at floor or front"}
			return ObjectLibrary.pose(bounds, "wall", hit["point"], hit["normal"], head, turn, k)
		"ceiling":
			var hit := ObjectLibrary.aim(head, (level + Vector3.UP * 1.5).normalized(), inside)
			if str(hit.get("surface", "")) != "ceiling":
				return {"error": "no ceiling above, in front of the viewer: give a position, or at floor or front"}
			return ObjectLibrary.pose(bounds, "ceiling", hit["point"], hit["normal"], head, turn, k)
		"floor":
			var floor_y := 0.0
			if inside.get("min") is Array and not ("floor" in inside.get("open", [])):
				floor_y = float(inside["min"][1])
			var p := head + level * FLOOR_AHEAD
			return ObjectLibrary.pose(bounds, "floor", Vector3(p.x, floor_y, p.z), Vector3.UP, head, turn, k)
	return ObjectLibrary.pose(bounds, "free", head + level * FRONT_AHEAD, Vector3.ZERO, head, turn, k)


## The room's interior box in the room frame (RoomBounds.interior: measured once per base, then cached).
static func room_inside(main: Node) -> Dictionary:
	var room_editor := load("res://scripts/assistant/room_editor.gd") as GDScript
	var key: String = room_editor.call("base_key", main)
	var known: Variant = RoomBounds.cached(key)
	if known is Dictionary:
		return known
	var base: Node3D = room_editor.call("_base", main.env)
	return RoomBounds.interior(RoomBounds.geometry(base, room_editor.call("to_room", main)), key, base)


## "Shelf", else "Shelf 2", "Shelf 3", ...: a name nothing in the room has.
static func unique_name(base: String, taken: Array) -> String:
	var clean := ObjectLibrary.clean_name(base)
	if clean == "":
		clean = "Object"
	if not (clean in taken):
		return clean
	var n := 2
	while ("%s %d" % [clean.left(36), n]) in taken:
		n += 1
	return "%s %d" % [clean.left(36), n]


## A stock room changed by an object becomes a kept room of its own: "Dim room with objects".
static func room_name(main: Node) -> String:
	var label := "Room"
	for e: Array in main.get_environment_list():
		if str(e[0]) == str(main.env_id):
			label = str(e[1])
	return ObjectLibrary.clean_name("%s with objects" % ObjectLibrary.clean_name(label).left(26))


static func _assistant_room(main: Node) -> bool:
	return main.env != null and main.env.get_script() == load("res://scripts/assistant/assistant_room.gd")


## Puts the room back as it is now: a kept room is built again from its document; a stock room is shown again.
static func undo_for(editor: Node, main: Node) -> Callable:
	if _assistant_room(main):
		var old_doc: Dictionary = editor.current_doc()
		return func() -> void:
			if is_instance_valid(editor):
				editor.apply("new", old_doc, "undo")
	var old_id := str(main.env_id)
	return func() -> void:
		var m := _main()
		if m != null:
			m.set_environment(old_id)


static func _vec(a: Variant) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2])) if a is Array and (a as Array).size() == 3 else Vector3.ZERO


## The Objects tab shows the change (it reads the room again).
static func _sync_tab() -> void:
	var m := _main()
	var layer: Node = m.get("ui") if m != null else null
	var pane: Node = layer.get("ui") if layer != null else null
	var tab: Node = pane.get("objects") if pane != null else null
	if tab != null and tab.has_method("sync_objects"):
		tab.sync_objects()
