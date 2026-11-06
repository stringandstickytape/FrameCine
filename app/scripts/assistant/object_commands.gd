extends RefCounted

## The object library's commands (object_library.gd; docs/assistant.md "Objects"), registered for every client of the
## registry (scripts/dev/command_host.gd) with their assistant levels: object_library and object_info read; object_import,
## object_place, object_move and object_delete change the room or the library (level room). A part's colour is
## `recolour` with "<placed name>/<part name>" (scripts/assistant/assistant_commands.gd).
##
## Object physics (docs/physics.md, scripts/play/object_physics.gd): object_put_back and object_tidy_up return objects
## to where they were placed, object_attach makes a text or particles area follow an object (level room),
## object_throw drops or throws one (the dev link, tests; level room), object_physics reads what is moving and the
## cost (read).
##
## The Room tab (ui/object_section.gd, ui/object_placer.gd) calls the same functions: place(), move(), remove_placed(),
## recolour_part(), put_back(), attach(). Each change goes through a room editor (room_editor.gd: an assistant's own, else
## this app's ObjectLibrary.EDITOR_NODE), shows at once, is kept, and comes back with an undo: the room as it was (a kept
## room built again from its document, or the stock room shown again).

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
				+ "floor in front of them, on the ceiling, or in front at eye height. It shows at once and is kept; "
				+ "the room keeps only the object's id (its model and pictures stay in the library).",
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
				{"name": "scale", "type": "float", "default": 1.0, "description": "Its size, 1 as made (0.05 to 20): a "
				+ "primitive (box, sphere, cylinder, plane) is 1 m, a text a line 0.1 m high."},
				{"name": "text", "type": "string", "default": "", "description": "The text object only: the words to "
				+ "show (\\n starts a line)."},
				{"name": "text_options", "type": "object", "default": {}, "description": "The text object only: "
				+ "color, background, weight, align, max_width."}],
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
			if r.has("rooms"):
				# A kept room places it: rooms are made of objects, so it stays until they no longer do.
				ctx.reply["refused"] = true
				ctx.reply["rooms"] = r["rooms"]
			return ctx.fail(str(r["error"]))
		ctx.summary = "deleted %s from the library" % m.get("name", id)
		ctx.undo = func() -> void: ObjectLibrary.restore(id)
		ctx.cleanup = func() -> void: ObjectLibrary.purge(id)
		_sync_tab()
		return {"deleted": id, "name": m.get("name", id)}, {
		"description": "Deletes an imported object from the library (built-in ones stay). Refused while a kept room "
				+ "places it (the reply names the rooms): remove it from them first.",
		"params": [{"name": "id", "type": "string", "required": true, "description": "The user object's id "
				+ "(object_library source user)."}],
		"level": "change", "assistant": "room", "destructive": true, "title": "Delete an imported object",
		"returns": "{deleted, name}; refused: {error, rooms}"})
	R.register("object_put_back", func(a: Dictionary, ctx: DevCommands.Call) -> Variant:
		return _give(ctx, await put_back(_tree(), ctx.caller, [str(a["name"])])), {
		"description": "Puts an object that was picked up, dropped or thrown back where it was placed (a wall object "
				+ "on its wall again). Object physics keeps where it was placed as its home.",
		"params": [{"name": "name", "type": "string", "required": true, "description": "Its name in the room "
				+ "(room_state's objects; object_physics says which have moved)."}],
		"level": "change", "assistant": "room", "title": "Put an object back",
		"returns": "{state: kept, put_back: [names], ...}"})
	R.register("object_tidy_up", func(_a: Dictionary, ctx: DevCommands.Call) -> Variant:
		return _give(ctx, await put_back(_tree(), ctx.caller, [])), {
		"description": "Puts every object that was picked up, dropped or thrown back where it was placed.",
		"params": [], "level": "change", "assistant": "room", "title": "Tidy up the room",
		"returns": "{state: kept, put_back: [names], ...}"})
	R.register("object_attach", func(a: Dictionary, ctx: DevCommands.Call) -> Variant:
		return _give(ctx, await attach(_tree(), ctx.caller, str(a["name"]), str(a["to"]), a["offset"],
				a["rotation"])), {
		"description": "Makes a text or a particles area follow another object: it moves with it when that is "
				+ "picked up or thrown (as a light with attach does). Empty to: it stays where it is now, on its own.",
		"params": [{"name": "name", "type": "string", "required": true, "description": "The text or particles area "
				+ "(room_state's objects)."},
				{"name": "to", "type": "string", "default": "", "description": "The object it follows (not a text or "
				+ "particles area); empty: detach."},
				{"name": "offset", "type": "array", "default": [], "description": "[x, y, z] metres in that object's "
				+ "frame; empty: where it is now."},
				{"name": "rotation", "type": "array", "default": [], "description": "[x, y, z] degrees relative to "
				+ "that object, with offset; empty: as it is turned now."}],
		"level": "change", "assistant": "room", "title": "Attach a text or particles to an object",
		"returns": "{state: kept, ...}"})
	R.register("object_throw", func(a: Dictionary, ctx: DevCommands.Call) -> Variant:
		var main := _main()
		var ph: Node = _physics(main)
		var name := str(a["name"])
		if ph == null or not (name in ph.names()):
			return ctx.fail("%s can't be picked up (object_physics lists what can: solid objects in a kept room)"
					% name)
		var v := _vec(a["velocity"])
		var to_world: Basis = main.env.global_basis if main.env != null else Basis()
		if not ph.throw(name, to_world * v, to_world * _vec(a["spin"])):
			return ctx.fail("%s is held" % name)
		ctx.summary = "threw %s" % name if v.length() > 0.01 else "dropped %s" % name
		return {"name": name, "speed": snappedf(v.length(), 0.01)}, {
		"description": "Drops or throws an object as a hand would: it falls, bounces off the room, the seats and the "
				+ "screen, comes to rest and is kept where it lands (object_put_back returns it).",
		"params": [{"name": "name", "type": "string", "required": true, "description": "Its name in the room."},
				{"name": "velocity", "type": "array", "default": [0, 0, 0], "description": "[x, y, z] m/s in the "
				+ "room frame (room_state); [0, 0, 0]: dropped."},
				{"name": "spin", "type": "array", "default": [0, 0, 0], "description": "[x, y, z] radians a second."}],
		"level": "change", "assistant": "room", "title": "Drop or throw an object",
		"returns": "{name, speed}"})
	R.register("object_physics", func(_a: Dictionary, ctx: DevCommands.Call) -> Variant:
		var main := _main()
		var ph: Node = _physics(main)
		if ph == null:
			return ctx.fail("no object physics in this app")
		var out: Dictionary = ph.state()
		var doc: Dictionary = main.env.get("doc") if main.env != null and main.env.get("doc") is Dictionary else {}
		var objects: Array = []
		for p: Dictionary in doc.get("parts", []):
			var n := str(p.get("name", ""))
			if n in ph.names() or p.has("attach"):
				objects.append({"name": n, "moving": ph.is_moving(n), "held": ph.is_held(n),
						"mounted": ph.is_mounted(n), "moved": p.has("home"), "attach": p.get("attach", "")})
		out["objects"] = objects
		var last: Dictionary = out.get("last_thud", {})
		if last.get("position") is Vector3:
			last = last.duplicate()
			last["position"] = _arr(last["position"])
			out["last_thud"] = last
		return out, {
		"description": "Object physics now: the objects that can be picked up (moving, held, still on their wall, "
				+ "moved from where they were placed, attached), the room's collision shapes, and the physics frame's "
				+ "cost in milliseconds (mean and most over the last two seconds).",
		"params": [], "assistant": "read", "title": "Object physics",
		"returns": "{bodies, moving, held, room_shapes, screen, cost_ms {mean, max}, thuds, objects: [{name, moving, "
				+ "held, mounted, moved, attach}]}"})


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
	var generator := str(m.get("generator", ""))
	if generator == "text" and str(opts.get("text", "")).strip_edges() == "":
		return {"ok": false, "error": "text: give text, the words to show (and text_options)"}
	if generator == "particles":
		return {"ok": false, "error": "particles: send a particles part with room_apply (its preset, rate and area)"}
	if generator == "" and ObjectLibrary.glb(id).is_empty():
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
	# A placement: the object's id only; its model and pictures come from the library when the room is built.
	var part := {"name": name, "object": id, "position": spot["position"], "rotation": spot["rotation"],
			"scale": spot["scale"]}
	if m.has("widget"):
		part["widget"] = m["widget"]
		part["widget_options"] = m.get("widget_options", {})
	if generator == "text":
		part["text"] = str(opts["text"])
		if opts.get("text_options") is Dictionary and not (opts["text_options"] as Dictionary).is_empty():
			part["text_options"] = opts["text_options"]
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
		if s is Array:
			# A primitive's scale is its size ([w, h, d]): a number resizes it, keeping its shape.
			part["scale"] = (s as Array).map(func(x: Variant) -> float: return snappedf(float(x) * scale, 0.0001))
		else:
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


# --- Object physics ---------------------------------------------------------------------------------------------

static func _physics(main: Node) -> Node:
	var f: Node = main.get("features") if main != null else null
	return f.get("physics") if f != null else null


## Puts objects back where they were placed (their `home`; names: these, [] all that moved). What is still moving
## comes to rest first. One change, with the room's undo.
static func put_back(tree: SceneTree, caller: Object, names: Array) -> Dictionary:
	var main := tree.current_scene
	var ph: Node = _physics(main)
	if ph != null:
		ph.settle_all()
	var editor := ObjectLibrary.editor_for(tree, caller)
	var doc: Dictionary = editor.current_doc()
	var parts: Array = []
	var known := false
	for p: Dictionary in doc.get("parts", []):
		if not names.is_empty() and not (str(p.get("name", "")) in names):
			continue
		known = true
		if not (p.get("home") is Dictionary):
			continue
		var q := p.duplicate(true)
		var home: Dictionary = q["home"]
		q["position"] = home["position"]
		q["rotation"] = home["rotation"]
		if home.has("mounted"):
			q["mounted"] = home["mounted"]
		else:
			q.erase("mounted")
		q.erase("home")
		parts.append(q)
	if not names.is_empty() and not known:
		return {"ok": false, "error": "nothing in the room is called %s (room_state's objects lists them)" % names[0]}
	if parts.is_empty():
		return {"ok": false, "error": ("%s is where it was placed" % names[0]) if not names.is_empty()
				else "everything is where it was placed"}
	var undo := undo_for(editor, main)
	var put: Array = parts.map(func(q: Dictionary) -> String: return str(q["name"]))
	var said := "put back %s" % ", ".join(put) if names.size() == 1 else "tidied up %d" % put.size()
	var r: Dictionary = await editor.apply("patch", {"schema": RoomSchema.VERSION, "parts": parts}, said)
	if r.get("ok") == true:
		r["undo"] = undo
		r["result"]["put_back"] = put
	return r


## Whether placement `name` was moved from where it was placed (object physics kept its home).
static func moved(env: Node, name: String) -> bool:
	var doc: Dictionary = env.get("doc") if env != null and env.get("doc") is Dictionary else {}
	for p: Dictionary in doc.get("parts", []):
		if str(p.get("name", "")) == name:
			return p.get("home") is Dictionary
	return false


## A text or particles area `name` follows placement `to` (empty: detached, staying where it is now). offset and
## rotation: its place in that object's frame; empty: where it is now.
static func attach(tree: SceneTree, caller: Object, name: String, to: String, offset: Variant = [],
		rotation: Variant = []) -> Dictionary:
	var main := tree.current_scene
	var editor := ObjectLibrary.editor_for(tree, caller)
	var doc: Dictionary = editor.current_doc()
	var part := {}
	var target := {}
	for p: Dictionary in doc.get("parts", []):
		if p["name"] == name:
			part = p.duplicate(true)
		elif to != "" and p["name"] == to:
			target = p
	if part.is_empty():
		return {"ok": false, "error": "nothing in the room is called %s (room_state's objects lists them)" % name}
	if not (RoomSchema.kind_of(part) in RoomSchema.GENERATORS):
		return {"ok": false, "error": "only a text or a particles area attaches; %s is a %s" % [name,
				RoomSchema.kind_of(part)]}
	if to != "" and target.is_empty():
		return {"ok": false, "error": "nothing in the room is called %s" % to}
	if to != "" and RoomSchema.kind_of(target) in RoomSchema.GENERATORS:
		return {"ok": false, "error": "%s is a text or particles area too: attach to an object" % to}
	var layer: Node = main.env.get_node_or_null("AssistantLayer") if main.env != null else null
	var node := layer.get_node_or_null(name) as Node3D if layer != null else null
	if to == "":
		if not part.has("attach"):
			return {"ok": false, "error": "%s isn't attached" % name}
		if node != null:
			part["position"] = _arr(node.transform.origin)
			part["rotation"] = _deg(node.transform.basis)
		part.erase("attach")
		part.erase("offset")
	else:
		var tnode := layer.get_node_or_null(to) as Node3D if layer != null else null
		var rel := Transform3D()
		if tnode != null and node != null:
			var rigid := Transform3D(tnode.transform.basis.orthonormalized(), tnode.transform.origin)
			rel = rigid.affine_inverse() * node.transform
		part["attach"] = to
		part["offset"] = offset if offset is Array and (offset as Array).size() == 3 else _arr(rel.origin)
		part["rotation"] = rotation if rotation is Array and (rotation as Array).size() == 3 else _deg(rel.basis)
	var undo := undo_for(editor, main)
	var said := "attach %s to %s" % [name, to] if to != "" else "detach %s" % name
	var r: Dictionary = await editor.apply("patch", {"schema": RoomSchema.VERSION, "parts": [part]}, said)
	if r.get("ok") == true:
		r["undo"] = undo
	return r


static func _arr(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]


static func _deg(b: Basis) -> Array:
	var e := b.orthonormalized().get_euler()
	return [snappedf(rad_to_deg(e.x), 0.01), snappedf(rad_to_deg(e.y), 0.01), snappedf(rad_to_deg(e.z), 0.01)]


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
