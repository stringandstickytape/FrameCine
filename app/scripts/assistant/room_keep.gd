extends RefCounted

## Rooms are made of objects (docs/decisions.md, "Rooms are made of objects"; docs/assistant.md "Rooms"): every part
## of a kept room is a placement of an object from the object library (object_library.gd), so the library is the one
## source of a room's models and pictures. An assistant may still send a part as a shape (type, size, an inline model,
## a picture); when the change is applied (room_editor.gd), or a kept room of schema 1 or 2 is loaded
## (assistant_room.gd load_saved), keep() turns each such part into a placement:
##
##   an untextured box, sphere, cylinder or plane   the built-in primitive (object_builtins.gd), its size as the
##                                                  placement's scale, its material as the placement's material
##   a text, a particles area                       the built-in generator, its words or area kept on the placement
##   an inline model (base64 .glb)                  a user object named after the part (ObjectLibrary.import_glb);
##                                                  the same bytes (the md5 its manifest keeps) are the same object
##   a shape or a model with a picture              a user object: the mesh with the picture as its unlit material,
##   (material.texture: a poster, a photo, a sign)  written as a .glb (RoomModel.with_picture), tags ["picture"],
##                                                  mount wall for a plane or a box under 5 cm deep, else free
##
## A placement sent with a picture on its material (recolour with texture) becomes a picture object the same way. The
## rest of the part's material (self_lit, emission, alpha, effect, a library material) stays on the placement as an
## override. User objects go under user://objects (never res://). keep() can run on a worker thread.
##
##   keep(doc) -> {doc (schema 3), kept: [{part, id, name, new}], created: [ids]} or {error, limit?}
##   forget(created)          the objects a refused change made, deleted again
##   summary(kept) -> "kept Poster and Ball in the object library" or ""

const RoomSchema := preload("res://scripts/assistant/room_schema.gd")
const RoomModel := preload("res://scripts/assistant/room_model.gd")
const ObjectLibrary := preload("res://scripts/assistant/object_library.gd")
const ObjectBuiltins := preload("res://scripts/assistant/object_builtins.gd")

## A box thinner than this (its depth, metres) hangs on a wall, as a plane does.
const WALL_DEPTH := 0.05
## The material named in a picture object's .glb that carries the picture.
const PICTURE := "Picture"
## A picture object's other faces (a front_only box's sides).
const PLAIN := "Plain"
## What a part's material keeps besides the picture it gave the object: an override on the placement.
const PICTURE_KEYS: Array[String] = ["texture", "texture_file", "uv", "color"]


static func keep(doc: Dictionary) -> Dictionary:
	var out := doc.duplicate(true)
	out["schema"] = RoomSchema.VERSION
	var kept: Array = []
	var created: Array = []
	var parts: Array = out.get("parts", []) if out.get("parts") is Array else []
	for i in parts.size():
		var r := keep_part(parts[i], created)
		if r.has("error"):
			forget(created)
			var e := {"error": "$.parts[%d] (%s): %s" % [i, parts[i].get("name", ""), r["error"]]}
			if r.has("limit"):
				e["limit"] = r["limit"]
			return e
		parts[i] = r["part"]
		if r.has("kept"):
			kept.append(r["kept"])
	out["parts"] = parts
	return {"doc": out, "kept": kept, "created": created}


## One part as a placement: {part, kept?} or {error, limit?}. created: the ids of new user objects, appended.
static func keep_part(p: Dictionary, created: Array) -> Dictionary:
	var f := RoomSchema.build_form(p)
	var kind := str(f.get("type", ""))
	var m: Dictionary = f.get("material", {}) if f.get("material") is Dictionary else {}
	var picture: bool = m.has("texture")
	if not p.has("type") and not picture:
		# A placement already.
		return {"part": p}
	if kind in RoomSchema.PRIMITIVES and not picture:
		var s := RoomSchema.placement_scale(f)
		var q := _placement(p, kind, s["scale"])
		if not m.is_empty():
			var mm := m.duplicate(true)
			mm.erase("uv")
			mm.erase("texture_file")
			if not mm.is_empty():
				q["material"] = mm
		return {"part": q}
	if kind in RoomSchema.GENERATORS:
		var s := RoomSchema.placement_scale(f)
		var q := _placement(p, kind, s["scale"])
		for k in ["text", "text_options", "particles"]:
			if p.has(k):
				q[k] = p[k]
		return {"part": q}
	if kind in RoomSchema.PRIMITIVES:
		return _keep_shape_picture(p, f, m, created)
	if kind == "model":
		return _keep_model(p, f, m, created)
	return {"error": "a part of type %s can't be kept as an object" % kind}


## The placement's own keys from a part (where, how it turns and moves, its widget), with an object and a scale.
static func _placement(p: Dictionary, object: String, scale: Variant) -> Dictionary:
	var q := {"name": p["name"], "object": object}
	for k in ["position", "rotation"]:
		if p.has(k):
			q[k] = p[k]
	if not (scale is float and is_equal_approx(scale, 1.0)) and not (scale is int and scale == 1):
		q["scale"] = scale
	for k in ["widget", "widget_options", "motion"]:
		if p.has(k):
			q[k] = p[k]
	return q


## The material a picture object's placement keeps: the part's without the picture and its colour (in the object now).
static func _override(m: Dictionary) -> Dictionary:
	var out := m.duplicate(true)
	for k: String in PICTURE_KEYS:
		out.erase(k)
	return out


## A box, sphere, cylinder or plane with a picture: the shape at its size, the picture on it as on the part, as a user
## object; the placement keeps the part's own scale. A plane is turned to face +Z (an object's front; the placement
## turned back), so it hangs on a wall like any wall object.
static func _keep_shape_picture(p: Dictionary, f: Dictionary, m: Dictionary, created: Array) -> Dictionary:
	var kind := str(f["type"])
	var picture := Marshalls.base64_to_raw(str(m["texture"]))
	var check := RoomModel.decode_image(picture)
	if check.has("error"):
		return {"error": "material.texture: %s" % check["error"]}
	var size: Array = f.get("size", [1.0, 1.0, 1.0])
	var v := Vector3.ONE
	match kind:
		"box":
			v = Vector3(float(size[0]), float(size[1]), float(size[2]))
		"sphere":
			v = Vector3.ONE * float(size[0])
		"cylinder":
			v = Vector3(float(size[0]), float(size[1]), float(size[0]))
		"plane":
			v = Vector3(float(size[0]), 0.0, float(size[1]))
	var uv := str(m.get("uv", "atlas"))
	var root := Node3D.new()
	root.name = "PictureObject"
	var mi := MeshInstance3D.new()
	mi.name = ObjectBuiltins.part_name(kind)
	var front_only := kind == "box" and uv == "front_only"
	var pic := _picture_material(Color.WHITE if front_only else RoomSchema.to_color(m.get("color", "#ffffff")))
	if kind == "box" and uv != "atlas":
		var plain := StandardMaterial3D.new()
		plain.resource_name = PLAIN
		plain.albedo_color = RoomSchema.to_color(m.get("color", "#b0b0b0"))
		var assistant_room := load("res://scripts/assistant/assistant_room.gd") as GDScript
		mi.mesh = assistant_room.call("box_mesh", v, uv, pic, plain)
		for s in mi.mesh.get_surface_count():
			mi.set_surface_override_material(s, mi.mesh.surface_get_material(s))
	else:
		var mesh := ObjectBuiltins.shape_mesh(kind, v)
		mesh.material = pic
		mi.mesh = mesh
		mi.set_surface_override_material(0, pic)
	if kind == "plane":
		mi.transform = Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3.ZERO)
	root.add_child(mi)
	var bytes := ObjectLibrary.to_glb(root)
	root.free()
	bytes = RoomModel.with_picture(bytes, PICTURE, picture)
	if bytes.is_empty():
		return {"error": "the picture could not be written into an object"}
	var mount := "wall" if kind == "plane" or (kind == "box" and v.z < WALL_DEPTH) else "free"
	var r := _object_of(bytes, str(p["name"]), ["picture"], mount, {"picture": true}, created)
	if r.has("error"):
		return r
	# The size is in the object now: the placement keeps the part's own scale (a placement's, what its size left).
	var q := _placement(p, r["id"], f.get("scale", 1.0))
	if kind == "plane":
		# The object's plane faces +Z: the placement turns it back to where the part's faced.
		var rot: Array = p.get("rotation", [0, 0, 0])
		var b := Basis.from_euler(Vector3(deg_to_rad(float(rot[0])), deg_to_rad(float(rot[1])),
				deg_to_rad(float(rot[2])))) * Basis(Vector3.RIGHT, -PI / 2.0)
		var e := b.get_euler()
		q["rotation"] = [snappedf(rad_to_deg(e.x), 0.001), snappedf(rad_to_deg(e.y), 0.001),
				snappedf(rad_to_deg(e.z), 0.001)]
	var mm := _override(m)
	if not mm.is_empty():
		q["material"] = mm
	return {"part": q, "kept": r["kept"]}


## A model part: its object when it names one the library has; else its .glb as a user object (the same bytes are the
## same object). With a picture on its material, the model with the picture over it, as a picture object.
static func _keep_model(p: Dictionary, f: Dictionary, m: Dictionary, created: Array) -> Dictionary:
	var id := str(p.get("object", ""))
	var known := id != "" and not ObjectLibrary.get_object(id).is_empty()
	if known and not m.has("texture"):
		var q := _placement(p, id, p.get("scale", 1.0))
		if not m.is_empty():
			q["material"] = m.duplicate(true)
		return {"part": q}
	var bytes := PackedByteArray()
	if p.has("model"):
		bytes = Marshalls.base64_to_raw(str(p["model"]))
		if bytes.is_empty():
			return {"error": "model: not base64"}
	elif known:
		bytes = ObjectLibrary.glb(id)
	elif id != "":
		return {"error": "no object %s in the library (object_library lists them)" % id}
	else:
		return {"error": "a model part needs model: the .glb file, base64"}
	if not m.has("texture"):
		var r := _object_of(bytes, str(p["name"]), [], "", {}, created)
		if r.has("error"):
			return r
		var q := _placement(p, r["id"], p.get("scale", 1.0))
		if not m.is_empty():
			q["material"] = m.duplicate(true)
		return {"part": q, "kept": r["kept"]}
	var picture := Marshalls.base64_to_raw(str(m["texture"]))
	var check := RoomModel.decode_image(picture)
	if check.has("error"):
		return {"error": "material.texture: %s" % check["error"]}
	var read := RoomModel.load_glb(bytes)
	if read.has("error"):
		return {"error": "model: %s" % read["error"]}
	var node: Node3D = read["node"]
	var pic := _picture_material(RoomSchema.to_color(m.get("color", "#ffffff")))
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			mi.set_surface_override_material(s, pic)
	var glb := ObjectLibrary.to_glb(node)
	node.free()
	glb = RoomModel.with_picture(glb, PICTURE, picture)
	if glb.is_empty():
		return {"error": "the picture could not be written into the model"}
	var r := _object_of(glb, str(p["name"]), ["picture"], "", {"picture": true}, created)
	if r.has("error"):
		return r
	var q := _placement(p, r["id"], p.get("scale", 1.0))
	var mm := _override(m)
	if not mm.is_empty():
		q["material"] = mm
	return {"part": q, "kept": r["kept"]}


## A picture's material in a picture object: unlit (KHR_materials_unlit, so the room shows it as a part's picture),
## its colour multiplying the picture; RoomModel.with_picture() puts the picture in.
static func _picture_material(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = PICTURE
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = colour
	return m


## The user object with these bytes (the md5 its manifest keeps), else a new one named `name`: {id, kept} or
## {error, limit?}.
static func _object_of(bytes: PackedByteArray, name: String, tags: Array, mount: String, extra: Dictionary,
		created: Array) -> Dictionary:
	var same := ObjectLibrary.find_by_md5(ObjectLibrary.md5_of(bytes))
	if same != "":
		var m := ObjectLibrary.get_object(same)
		return {"id": same, "kept": {"part": name, "id": same, "name": m.get("name", same), "new": false}}
	var r := ObjectLibrary.import_glb(bytes, name, tags, mount, extra)
	if not r.get("ok", false):
		var e := {"error": str(r.get("error", "the object could not be kept"))}
		if r.has("limit"):
			e["limit"] = r["limit"]
		return e
	var id := str(r["manifest"]["id"])
	created.append(id)
	return {"id": id, "kept": {"part": name, "id": id, "name": r["manifest"]["name"], "new": true}}


## The objects a refused change made: out of the library again.
static func forget(created: Array) -> void:
	for id: String in created:
		ObjectLibrary.delete(id)
		ObjectLibrary.purge(id)


## What a change kept into the library, in words for its summary: "kept Poster and Ball in the object library".
static func summary(kept: Array) -> String:
	var names: Array = []
	for k: Dictionary in kept:
		if bool(k.get("new", false)) and not (str(k["name"]) in names):
			names.append(str(k["name"]))
	if names.is_empty():
		return ""
	var list: String = names[0] if names.size() == 1 else "%s and %s" % [", ".join(names.slice(0, -1)), names[-1]]
	return "kept %s in the object library" % list