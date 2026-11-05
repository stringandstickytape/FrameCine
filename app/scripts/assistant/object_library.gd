extends RefCounted

## The object library (docs/assistant.md, "Objects"): things to put in a room, each a .glb and a small manifest. However
## an object was made, its parts are the meshes inside it (room_model.gd names them), so a placed copy's parts can be
## recoloured one by one ("Shelf/Board"). Two sources:
##   built-in  made here from primitives (object_builtins.gd): nothing in the repository that anyone else made
##   user      imported by the viewer or an assistant: user://objects/<id>/ (object.glb, manifest.json, thumb.png),
##             never under res://. They may hold anything the viewer gave, logos too, so they stay in the user's data.
## The catalogue is the built-ins and the user folder as it is on disk, so it survives restarts. A deleted user object
## goes to user://objects/.deleted/ until its undo is dropped.
##
## A manifest: {id, name, tags, source, mount (wall, floor, table, ceiling or free), size [w, h, d] metres,
## bounds {min, max} (the model's own frame), triangles, parts: [{name, color, texture, triangles}], widget?,
## widget_options?, md5 (a user object: its .glb's, so the same bytes are kept once), picture? (a picture object kept
## from a room's part: its picture shows as the part's did), primitive? or generator? (built-ins)}.
##
## Rooms are made of objects (docs/decisions.md): a kept room's parts are placements of these, so the library is the
## one source of a room's models and pictures. An object a kept room places can't be deleted (rooms_using()).
##
##   list(tag, source) -> [manifest]       get_object(id) -> manifest or {}       glb(id) -> PackedByteArray
##   import_glb(bytes, name, tags, mount, extra) -> {ok, manifest, warnings} or {ok: false, error, limit?}
##   import_svg(text, name, options) -> the same                       delete(id), restore(id), purge(id)
##   find_by_md5(md5) -> id or ""          rooms_using(id) -> [kept room names]
##   thumbnail(id) -> Image or null          aim(), pose(): where a placed object goes (object_commands.gd)

const RoomModel := preload("res://scripts/assistant/room_model.gd")
const RoomSchema := preload("res://scripts/assistant/room_schema.gd")
const ObjectBuiltins := preload("res://scripts/assistant/object_builtins.gd")
const ObjectThumb := preload("res://scripts/assistant/object_thumb.gd")
const SvgExtrude := preload("res://scripts/assistant/svg_extrude.gd")

const USER_DIR := "user://objects"
## The kept rooms (assistant_room.gd RECIPE_DIR, scripts/dev/recipes.gd ROOM_SUFFIX): what places an object.
const RECIPE_DIR := "user://recipes"
const ROOM_SUFFIX := ".room.json"
const TRASH_DIR := "user://objects/.deleted"
const MANIFEST := "manifest.json"
const GLB := "object.glb"
const THUMB := "thumb.png"
const THUMB_SIZE := 128
const MOUNTS: Array[String] = ["wall", "floor", "table", "ceiling", "free"]
const NAME_MAX := 40
const TAGS_MAX := 8
## A placed object stands this far off its wall or floor (no flicker where the two meet).
const GAP := 0.002
## The node a viewer's (or the dev link's) object changes go through; an assistant's go through its own editor.
const EDITOR_NODE := "ObjectRoomEditor"

## Built-ins made this session: id -> {glb, manifest}.
static var _builtin := {}
## Thumbnails made or read this session: id -> Image.
static var _thumbs := {}
## User objects' manifests read this session: id -> manifest.
static var _manifests := {}
## The Room tab reads the catalogue on a worker thread while a command may read it here: one at a time. Held only to
## read and store the caches, never while a model is built or drawn: that reads meshes back from the renderer, which
## from a worker waits for the main thread, and the main thread may be waiting here (the Objects tab hung the app so).
static var _lock := Mutex.new()


# --- The catalogue -------------------------------------------------------------------------------------------------

## Every object, built-ins first, then the user's by name; `tag` keeps those carrying it, `source` builtin or user.
static func list(tag := "", source := "all") -> Array:
	var out: Array = []
	if source in ["all", "builtin"]:
		for e: Dictionary in ObjectBuiltins.ENTRIES:
			var m := get_object(str(e["id"]))
			if not m.is_empty():
				out.append(m)
	if source in ["all", "user"]:
		var users: Array = []
		for id: String in _user_ids():
			var m := _read_manifest(id)
			if not m.is_empty():
				users.append(m)
		users.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0)
		out.append_array(users)
	if tag != "":
		out = out.filter(func(m: Dictionary) -> bool: return tag.to_lower() in (m.get("tags", []) as Array))
	return out


static func is_builtin(id: String) -> bool:
	return ObjectBuiltins.ENTRIES.any(func(e: Dictionary) -> bool: return e["id"] == id)


## An object's manifest, or {}.
static func get_object(id: String) -> Dictionary:
	if is_builtin(id):
		return (_make_builtin(id).get("manifest", {}) as Dictionary).duplicate(true)
	if not RoomSchema.id_ok(id):
		return {}
	return _read_manifest(id)


## An object's .glb, or empty.
static func glb(id: String) -> PackedByteArray:
	if is_builtin(id):
		return _make_builtin(id).get("glb", PackedByteArray())
	if not RoomSchema.id_ok(id):
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(USER_DIR.path_join(id).path_join(GLB))


## Its thumbnail (made once, kept for a user object beside it), or null.
static func thumbnail(id: String) -> Image:
	_lock.lock()
	var known: Variant = _thumbs.get(id)
	_lock.unlock()
	if known is Image:
		return known
	var img := _thumbnail(id)
	if img != null:
		_lock.lock()
		if _thumbs.get(id) is Image:
			img = _thumbs[id]
		else:
			_thumbs[id] = img
		_lock.unlock()
	return img


## Read or drawn, without the lock.
static func _thumbnail(id: String) -> Image:
	var img: Image = null
	if not is_builtin(id):
		var path := USER_DIR.path_join(id).path_join(THUMB)
		if FileAccess.file_exists(path):
			img = Image.load_from_file(path)
	if img == null:
		var bytes := glb(id)
		if bytes.is_empty():
			return null
		var r := RoomModel.load_glb(bytes)
		if r.has("error"):
			return null
		img = ObjectThumb.render(r["node"], THUMB_SIZE)
		(r["node"] as Node).free()
	return img


static func _user_ids() -> Array:
	var out: Array = []
	if DirAccess.dir_exists_absolute(USER_DIR):
		for d in DirAccess.get_directories_at(USER_DIR):
			if not d.begins_with(".") and FileAccess.file_exists(USER_DIR.path_join(d).path_join(MANIFEST)):
				out.append(d)
	return out


static func _read_manifest(id: String) -> Dictionary:
	# Read once (a room asks for its objects' manifests at each change); the library's own changes drop it.
	_lock.lock()
	var known: Variant = _manifests.get(id)
	_lock.unlock()
	if known is Dictionary:
		return (known as Dictionary).duplicate(true)
	var path := USER_DIR.path_join(id).path_join(MANIFEST)
	if not FileAccess.file_exists(path):
		return {}
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(path)) != OK or not (j.data is Dictionary):
		return {}
	var m: Dictionary = j.data
	m["id"] = id
	m["source"] = "user"
	_lock.lock()
	_manifests[id] = m.duplicate(true)
	_lock.unlock()
	return m


static func _forget_manifest(id: String) -> void:
	_lock.lock()
	_manifests.erase(id)
	_lock.unlock()


## A built-in: its nodes written as a .glb and read back as any import is (the same parts and checks).
## Built without the lock (two threads may both build one the first time: the first kept).
static func _make_builtin(id: String) -> Dictionary:
	_lock.lock()
	var known: Variant = _builtin.get(id)
	_lock.unlock()
	if known is Dictionary:
		return known
	var out := _build_builtin(id)
	if out.is_empty():
		return out
	_lock.lock()
	if _builtin.get(id) is Dictionary:
		out = _builtin[id]
	else:
		_builtin[id] = out
	_lock.unlock()
	return out


static func _build_builtin(id: String) -> Dictionary:
	var entry: Dictionary = {}
	for e: Dictionary in ObjectBuiltins.ENTRIES:
		if e["id"] == id:
			entry = e
	if entry.has("generator"):
		# Made per placement (a text's words, a particles area): a manifest, no .glb.
		return {"glb": PackedByteArray(), "manifest": {"id": id, "name": entry["name"],
				"tags": (entry.get("tags", []) as Array).duplicate(), "mount": entry["mount"], "size": [1.0, 1.0, 1.0],
				"bounds": {"min": [-0.5, -0.5, -0.5], "max": [0.5, 0.5, 0.5]}, "triangles": 0, "parts": [],
				"source": "builtin", "generator": entry["generator"], "credit": "made for this app"}}
	var node := ObjectBuiltins.build(id)
	if node == null:
		return {}
	var bytes := to_glb(node)
	node.free()
	var r := RoomModel.load_glb(bytes)
	if r.has("error"):
		push_warning("Object library: built-in %s does not read back: %s" % [id, r["error"]])
		return {}
	var m := manifest_of(r, id, str(entry["name"]), entry.get("tags", []), str(entry["mount"]))
	(r["node"] as Node).free()
	m["source"] = "builtin"
	m["credit"] = "made for this app from simple shapes"
	if entry.get("primitive", false):
		m["primitive"] = true
	if entry.has("widget"):
		m["widget"] = entry["widget"]
		m["widget_options"] = (entry.get("widget_options", {}) as Dictionary).duplicate(true)
	return {"glb": bytes, "manifest": m}


## Nodes (not in a tree) as a binary glTF.
static func to_glb(node: Node3D) -> PackedByteArray:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_scene(node, state) != OK:
		return PackedByteArray()
	return doc.generate_buffer(state)


## The manifest of a read model (RoomModel.load_glb's result).
static func manifest_of(r: Dictionary, id: String, name: String, tags: Array, mount: String) -> Dictionary:
	var box := _aabb(r["node"])
	return {"id": id, "name": name, "tags": tags.duplicate(), "mount": mount,
			"size": [snappedf(box.size.x, 0.001), snappedf(box.size.y, 0.001), snappedf(box.size.z, 0.001)],
			"bounds": {"min": _v(box.position), "max": _v(box.end)}, "triangles": int(r["triangles"]),
			"parts": (r.get("parts", []) as Array).duplicate(true)}


# --- Import and delete ----------------------------------------------------------------------------------------------

## A .glb as a user object: checked as a room's models are (no scripts, no outside files, the limits), its parts
## named, a thumbnail made, written under user://objects/<id>/ with the md5 of its bytes. extra: more manifest fields
## (picture). Safe on a worker thread.
static func import_glb(bytes: PackedByteArray, name: String, tags: Array = [], mount := "", extra := {}) -> Dictionary:
	var lim := RoomSchema.LIMITS
	if bytes.size() > int(lim["model_bytes"]):
		return {"ok": false, "error": "model_bytes: %d, at most %d" % [bytes.size(), lim["model_bytes"]],
				"limit": "model_bytes"}
	var clean := clean_name(name)
	if clean == "":
		return {"ok": false, "error": "a name: letters, digits, space, - and _"}
	if mount != "" and not (mount in MOUNTS):
		return {"ok": false, "error": "mount: one of %s" % ", ".join(MOUNTS)}
	var r := RoomModel.load_glb(bytes)
	if r.has("error"):
		return {"ok": false, "error": str(r["error"])}
	var why := ""
	var limit := ""
	if int(r["triangles"]) > int(lim["model_triangles"]):
		limit = "model_triangles"
		why = "model_triangles: %d, at most %d" % [r["triangles"], lim["model_triangles"]]
	elif (r["parts"] as Array).size() > int(lim["model_parts"]):
		limit = "model_parts"
		why = "model_parts: %d, at most %d" % [(r["parts"] as Array).size(), lim["model_parts"]]
	elif int(r["texture_size"]) > int(lim["texture_size"]):
		limit = "texture_size"
		why = "texture_size: %d px, at most %d" % [r["texture_size"], lim["texture_size"]]
	elif (r["parts"] as Array).is_empty():
		why = "the model has no meshes"
	if why != "":
		(r["node"] as Node).free()
		var out := {"ok": false, "error": why}
		if limit != "":
			out["limit"] = limit
		return out
	var box := _aabb(r["node"])
	if mount == "":
		# Thin and upright: it hangs on a wall; else it stands.
		mount = "wall" if box.size.z < 0.25 * minf(box.size.x, box.size.y) else "floor"
	var id := new_id(clean)
	var m := manifest_of(r, id, clean, clean_tags(tags), mount)
	m["md5"] = md5_of(bytes)
	for k: String in extra:
		m[k] = extra[k]
	var thumb := ObjectThumb.render(r["node"], THUMB_SIZE)
	(r["node"] as Node).free()
	var dir := USER_DIR.path_join(id)
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join(GLB), FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "can't write %s" % dir}
	f.store_buffer(bytes)
	f.close()
	thumb.save_png(dir.path_join(THUMB))
	var saved := m.duplicate(true)
	saved.erase("id")
	f = FileAccess.open(dir.path_join(MANIFEST), FileAccess.WRITE)
	f.store_string(JSON.stringify(saved, " "))
	f.close()
	_lock.lock()
	_thumbs[id] = thumb
	_lock.unlock()
	_forget_manifest(id)
	m["source"] = "user"
	return {"ok": true, "manifest": m, "warnings": r.get("removed", [])}


## An SVG drawing extruded (svg_extrude.gd) and imported as a .glb. options: width, depth, bevel, part_names.
static func import_svg(text: String, name: String, tags: Array = [], mount := "wall", options := {}) -> Dictionary:
	var r := SvgExtrude.build(text, options)
	if r.has("error"):
		return {"ok": false, "error": str(r["error"])}
	var bytes := to_glb(r["node"])
	(r["node"] as Node).free()
	if bytes.is_empty():
		return {"ok": false, "error": "the drawing could not be written as a model"}
	var out := import_glb(bytes, name, tags, mount)
	if out.get("ok") == true:
		out["warnings"] = r["warnings"] + (out.get("warnings", []) as Array)
	return out


## The md5 of a file's bytes (hex), as a user object's manifest keeps it.
static func md5_of(bytes: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_MD5)
	h.update(bytes)
	return h.finish().hex_encode()


## The user object whose .glb has these bytes (its manifest's md5), or "".
static func find_by_md5(md5: String) -> String:
	for id: String in _user_ids():
		if str(_read_manifest(id).get("md5", "")) == md5:
			return id
	return ""


## The kept rooms (user://recipes/<name>.room.json) whose parts place object `id`: their names.
static func rooms_using(id: String) -> Array:
	var out: Array = []
	var dir: String = RECIPE_DIR
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(ROOM_SUFFIX):
			continue
		var text := FileAccess.get_file_as_string(dir.path_join(f))
		if not text.contains("\"%s\"" % id):
			continue
		var j := JSON.new()
		if j.parse(text) != OK or not (j.data is Dictionary) or not (j.data.get("parts") is Array):
			continue
		for p: Variant in j.data["parts"]:
			if p is Dictionary and str(p.get("object", "")) == id:
				out.append(str(j.data.get("name", f.trim_suffix(ROOM_SUFFIX))))
				break
	return out


## Deletes a user object (built-ins can't go, nor one a kept room places): moved aside, so restore() can bring it back
## until purge().
static func delete(id: String) -> Dictionary:
	if is_builtin(id):
		return {"ok": false, "error": "%s is built in: it can't be deleted" % id}
	if not RoomSchema.id_ok(id) or not DirAccess.dir_exists_absolute(USER_DIR.path_join(id)):
		return {"ok": false, "error": "no user object %s (object_library lists them)" % id}
	var using := rooms_using(id)
	if not using.is_empty():
		return {"ok": false, "refused": true, "rooms": using, "error": "%s is placed in kept room%s %s: take it out "
				% [id, "" if using.size() == 1 else "s", ", ".join(using)] + "of them first (remove)"}
	DirAccess.make_dir_recursive_absolute(TRASH_DIR)
	purge(id)
	if DirAccess.rename_absolute(USER_DIR.path_join(id), TRASH_DIR.path_join(id)) != OK:
		return {"ok": false, "error": "can't delete %s" % id}
	_lock.lock()
	_thumbs.erase(id)
	_lock.unlock()
	_forget_manifest(id)
	return {"ok": true}


## Brings a deleted user object back (its id still free).
static func restore(id: String) -> bool:
	if not DirAccess.dir_exists_absolute(TRASH_DIR.path_join(id)) or DirAccess.dir_exists_absolute(USER_DIR.path_join(id)):
		return false
	_forget_manifest(id)
	return DirAccess.rename_absolute(TRASH_DIR.path_join(id), USER_DIR.path_join(id)) == OK


## A deleted object gone for good.
static func purge(id: String) -> void:
	var dir := TRASH_DIR.path_join(id)
	if not RoomSchema.id_ok(id) or not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


## A user object's id from its name: lower case, words joined by _, unique among the built-ins and the user's.
static func new_id(name: String) -> String:
	var base := ""
	for c in name.to_lower().strip_edges():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "-":
			base += c
		elif not base.ends_with("_") and base != "":
			base += "_"
	base = base.trim_suffix("_").left(RoomSchema.ID_MAX - 4)
	if base == "":
		base = "object"
	var id := base
	var n := 2
	while is_builtin(id) or DirAccess.dir_exists_absolute(USER_DIR.path_join(id)) \
			or DirAccess.dir_exists_absolute(TRASH_DIR.path_join(id)):
		id = "%s_%d" % [base, n]
		n += 1
	return id


## A name as the room keeps names: letters, digits, space, - and _, at most NAME_MAX.
static func clean_name(text: String) -> String:
	var out := ""
	for c in text.strip_edges():
		if c.is_valid_identifier() or c.is_valid_int() or c in " -_":
			out += c
	return out.strip_edges().left(NAME_MAX)


static func clean_tags(tags: Array) -> Array:
	var out: Array = []
	for t: Variant in tags:
		var s := clean_name(str(t)).to_lower().left(24)
		if s != "" and not (s in out) and out.size() < TAGS_MAX:
			out.append(s)
	return out


static func _aabb(n: Node3D) -> AABB:
	return (load("res://scripts/assistant/assistant_room.gd") as GDScript).call("_aabb", n)


static func _v(p: Vector3) -> Array:
	return [snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)]


# --- Where a placed object goes -------------------------------------------------------------------------------------

## A ray (the room frame) against the room's walls, floor and ceiling (its interior box, RoomBounds.interior; open
## sides have nothing, and the floor is at y = 0 when it isn't known): {surface: wall | floor | ceiling, point, normal
## (into the room), distance}, or {} when it hits nothing within 30 m.
static func aim(origin: Vector3, dir: Vector3, inside: Dictionary) -> Dictionary:
	var lo := Vector3(-INF, 0.0, -INF)
	var hi := Vector3(INF, INF, INF)
	var open: Array = ["left", "right", "front", "back", "ceiling"]
	if inside.get("min") is Array:
		lo = Vector3(inside["min"][0], inside["min"][1], inside["min"][2])
		hi = Vector3(inside["max"][0], inside["max"][1], inside["max"][2])
		open = inside.get("open", [])
		if "floor" in open:
			lo.y = 0.0
	var best := {}
	var planes := [["floor", 1, lo.y, Vector3.UP, dir.y < -1e-4], ["ceiling", 1, hi.y, Vector3.DOWN, dir.y > 1e-4],
			["left", 0, lo.x, Vector3.RIGHT, dir.x < -1e-4], ["right", 0, hi.x, Vector3.LEFT, dir.x > 1e-4],
			["front", 2, lo.z, Vector3.BACK, dir.z < -1e-4], ["back", 2, hi.z, Vector3.FORWARD, dir.z > 1e-4]]
	for pl: Array in planes:
		var side: String = pl[0]
		if not bool(pl[4]) or (side != "floor" and side in open) or not is_finite(float(pl[2])):
			continue
		var t := (float(pl[2]) - origin[int(pl[1])]) / dir[int(pl[1])]
		if t <= 0.05 or t > 30.0 or t >= float(best.get("distance", INF)):
			continue
		best = {"surface": "floor" if side == "floor" else ("ceiling" if side == "ceiling" else "wall"),
				"point": origin + dir * t, "normal": pl[3], "distance": t}
	return best


## Where a placed object goes, as a room document part's position, rotation (degrees) and scale: its back on a wall
## (front out, `turn` degrees about the wall's normal), its bottom on a floor or table and its top on a ceiling (facing
## `viewer`, turned by `turn` about up), its middle at a free point (facing the viewer). bounds: the model's own box.
static func pose(bounds: AABB, surface: String, point: Vector3, normal: Vector3, viewer: Vector3, turn := 0.0,
		scale := 1.0) -> Dictionary:
	var c := bounds.get_center()
	var anchor := c
	var rot := Vector3.ZERO
	var toward := viewer - point
	toward.y = 0.0
	var yaw := rad_to_deg(atan2(toward.x, toward.z)) if toward.length() > 0.01 else 0.0
	match surface:
		"wall":
			rot = Vector3(0.0, rad_to_deg(atan2(normal.x, normal.z)), turn)
			anchor = Vector3(c.x, c.y, bounds.position.z)
		"floor", "table":
			rot = Vector3(0.0, yaw + turn, 0.0)
			anchor = Vector3(c.x, bounds.position.y, c.z)
		"ceiling":
			rot = Vector3(0.0, yaw + turn, 0.0)
			anchor = Vector3(c.x, bounds.end.y, c.z)
		_:
			rot = Vector3(0.0, yaw + turn, 0.0)
			normal = Vector3.ZERO
	var basis := Basis.from_euler(Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z)))
	var pos := point - basis * (anchor * scale) + normal * GAP
	return {"position": _v(pos), "rotation": [snappedf(rot.x, 0.01), snappedf(fposmod(rot.y + 180.0, 360.0) - 180.0,
			0.01), snappedf(rot.z, 0.01)], "scale": snappedf(scale, 0.001)}


## A manifest's bounds as an AABB.
static func bounds_of(m: Dictionary) -> AABB:
	var b: Dictionary = m.get("bounds", {})
	if not (b.get("min") is Array) or not (b.get("max") is Array):
		return AABB(Vector3(-0.1, -0.1, -0.1), Vector3(0.2, 0.2, 0.2))
	var lo := Vector3(b["min"][0], b["min"][1], b["min"][2])
	return AABB(lo, Vector3(b["max"][0], b["max"][1], b["max"][2]) - lo)


## The room editor an object change goes through: the caller's (an assistant's), else this app's own (made once).
static func editor_for(tree: SceneTree, caller: Object = null) -> Node:
	if caller != null and caller.get("room") is Node and is_instance_valid(caller.get("room")):
		return caller.get("room")
	var ed := tree.root.get_node_or_null(EDITOR_NODE)
	if ed == null:
		ed = (load("res://scripts/assistant/room_editor.gd") as GDScript).new()
		ed.name = EDITOR_NODE
		tree.root.add_child(ed)
	return ed
