extends RefCounted

## Apply to a part (docs/features.md "Apply to a part", docs/assistant.md "Materials and pictures on parts"): a
## material or a picture put on one part of the room, chosen by pointing: a wall, the floor, a seat (the room's own
## surfaces, by their names) or a part of something placed ("Poster/Picture"). Shared by the Objects tab's apply mode
## (ui/object_placer.gd) and the commands (material_apply, picture_apply, pointed_part, part_reset).
##
## Nothing new is saved: a room surface takes a `recolour` entry with the material (library_material and its options,
## or a picture as texture), a placed object's part a part-level one ("Name/Part"), through ObjectCommands, so the
## kept room, its undo and its checks are the usual ones. Put back (reset()) takes that entry out again, and the part
## shows what the room built it with.
##
##   pick(main, origin, direction) -> {part, kind: room | object, placed, name, node, point, normal, distance,
##                                     material, picture, surface, surface_material, same} or {}
##                                     a ray (world frame) against the room's parts
##   target_of(hit) -> what painting the picked part reaches: its same-material match, else the part
##
## Paint by material: a model's part is often one mesh with several materials (a sofa's fabric and its wooden legs),
## and several parts may share one (four legs). pick() names the file material of the surface the ray meets
## (surface_material) and the match that reaches every surface of that object showing it ("Sofa/@Fabric": same), and
## the apply mode paints that, so the fabric changes and the legs stay. A part with no file material (a built-in
## object's, a room surface) is painted whole, as before.
##   apply(tree, caller, part, change) -> {ok, summary, undo, ...} or {ok: false, error}
##   reset(tree, caller, part)          the same
##   library_change(id, tiling, turn, tint) -> the material object for a library material

const ObjectCommands := preload("res://scripts/assistant/object_commands.gd")
const ObjectLibrary := preload("res://scripts/assistant/object_library.gd")
const RoomSchema := preload("res://scripts/assistant/room_schema.gd")
const MaterialLibrary := preload("res://scripts/env/material_library.gd")
const RoomModel := preload("res://scripts/assistant/room_model.gd")
const DevCommands := preload("res://scripts/dev/dev_commands.gd")

const REACH := 30.0
const LAYER := "AssistantLayer"

## mesh instance id -> TriangleMesh (the engine's, for intersect_ray), made once per mesh.
static var _tris := {}


static func _assistant_room() -> GDScript:
	return load("res://scripts/assistant/assistant_room.gd") as GDScript


static func _room_editor() -> GDScript:
	return load("res://scripts/assistant/room_editor.gd") as GDScript


static func _main() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.current_scene if tree != null else null


# --- Pointing --------------------------------------------------------------------------------------------------------

## The nearest part a ray meets (world frame), or {}.
static func pick(main: Node, origin: Vector3, direction: Vector3, reach := REACH) -> Dictionary:
	var env: Node = main.get("env") if main != null else null
	if env == null or not (env is Node3D) or not (env as Node3D).is_inside_tree():
		return {}
	var dir := direction.normalized()
	var best := {}
	var layer := env.get_node_or_null(LAYER)
	var base: Node3D = _room_editor().call("_base", env)
	# The room's own surfaces, by node name (recolour's match).
	if base != null:
		for n in base.find_children("*", "GeometryInstance3D", true, false):
			if layer != null and layer.is_ancestor_of(n):
				continue
			var hit := _hit(n as GeometryInstance3D, origin, dir, float(best.get("distance", reach)))
			if not hit.is_empty():
				best = hit
				best["kind"] = "room"
				best["part"] = str(n.name)
				best["name"] = str(n.name)
				best["placed"] = ""
	# The parts of what is placed (a primitive's one mesh, a model's meshes).
	if layer != null:
		var doc: Dictionary = env.get("doc") if env.get("doc") is Dictionary else {}
		var placed := {}
		for p: Dictionary in doc.get("parts", []):
			if p.has("object"):
				placed[str(p["name"])] = true
		for child in layer.get_children():
			if not placed.has(str(child.name)) or not (child is Node3D) or not (child as Node3D).visible:
				continue
			var parts: Dictionary = _assistant_room().call("parts_of_placed", child)
			for pn: String in parts:
				var hit := _hit(parts[pn] as GeometryInstance3D, origin, dir, float(best.get("distance", reach)))
				if not hit.is_empty():
					best = hit
					best["kind"] = "object"
					best["placed"] = str(child.name)
					best["name"] = pn
					best["part"] = "%s/%s" % [child.name, pn]
	if best.is_empty():
		return {}
	var g := best["node"] as GeometryInstance3D
	var surface := int(best.get("surface", 0))
	best["surface_material"] = ""
	best["same"] = ""
	if best["kind"] == "object" and g is MeshInstance3D:
		var named := RoomModel.surface_material(g as MeshInstance3D, surface)
		if named != "":
			best["surface_material"] = named
			best["same"] = "%s/@%s" % [best["placed"], named]
	best["material"] = _assistant_room().call("material_id_of", g, surface)
	var shown: Material = _assistant_room().call("shown_material_at", g, surface)
	best["picture"] = shown is ShaderMaterial and (shown as ShaderMaterial).get_shader_parameter("use_texture") == true
	return best


## What painting the picked part reaches: its same-material match when it has one, else the part.
static func target_of(hit: Dictionary) -> String:
	var same := str(hit.get("same", ""))
	return same if same != "" else str(hit.get("part", ""))


## The surfaces a match lights up while the apply mode shows it: [[GeometryInstance3D, surface (-1: all of it)], ...]
## (AssistantRoom.surface_targets() for a placed object's; the room surfaces of that name, whole).
static func preview_targets(main: Node, match: String) -> Array:
	var env: Node = main.get("env") if main != null else null
	if env == null or match == "":
		return []
	if match.contains("/"):
		return _assistant_room().call("surface_targets", env.get_node_or_null(LAYER), match)
	var base: Node3D = _room_editor().call("_base", env)
	var out: Array = []
	if base != null:
		for n in base.find_children(match, "GeometryInstance3D", true, false):
			out.append([n, -1])
	return out


## Where a ray meets one surface (nearer than `nearer`): {node, point, normal, distance} or {}.
static func _hit(g: GeometryInstance3D, origin: Vector3, dir: Vector3, nearer: float) -> Dictionary:
	if g == null or not g.is_visible_in_tree():
		return {}
	var xfs: Array[Transform3D] = []
	var mesh: Mesh = null
	if g is MeshInstance3D:
		mesh = (g as MeshInstance3D).mesh
		xfs.append(g.global_transform)
	elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh != null:
		var mm := (g as MultiMeshInstance3D).multimesh
		mesh = mm.mesh
		var count := mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
		for i in count:
			xfs.append(g.global_transform * mm.get_instance_transform(i))
	if mesh == null or xfs.is_empty():
		return {}
	var aabb := mesh.get_aabb()
	var best := {}
	for xf: Transform3D in xfs:
		var inv := xf.affine_inverse()
		var o := inv * origin
		var d := inv.basis * dir
		if aabb.grow(0.01).intersects_ray(o, d) == null:
			continue
		var tm := _triangles(mesh)
		if tm == null:
			continue
		var r: Dictionary = tm.intersect_ray(o, d)
		if r.is_empty():
			continue
		var p: Vector3 = xf * (r["position"] as Vector3)
		var dist := origin.distance_to(p)
		if dist >= nearer or (dir.dot(p - origin) <= 0.0):
			continue
		nearer = dist
		best = {"node": g, "point": p, "normal": (xf.basis.inverse().transposed() * (r["normal"] as Vector3))
				.normalized(), "distance": dist, "surface": _surface_of(mesh, int(r.get("face_index", -1)))}
	return best


## Which surface of a mesh a triangle (its index in mesh.get_faces()'s order: the surfaces' triangles one after the
## other) belongs to; 0 when it can't tell.
static func _surface_of(mesh: Mesh, face: int) -> int:
	if face < 0 or mesh == null or mesh.get_surface_count() <= 1:
		return 0
	var start := 0
	for s in mesh.get_surface_count():
		if mesh is ArrayMesh and (mesh as ArrayMesh).surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var idx: int = mesh.surface_get_array_index_len(s)
		var n: int = (idx if idx > 0 else mesh.surface_get_array_len(s)) / 3
		if face < start + n:
			return s
		start += n
	return 0


static func _triangles(mesh: Mesh) -> Object:
	var key := mesh.get_instance_id()
	if _tris.has(key) and is_instance_valid(_tris[key][0]):
		return _tris[key][1]
	var tm: Object = ClassDB.instantiate("TriangleMesh")
	if tm == null:
		return null
	var faces := mesh.get_faces()
	if faces.is_empty():
		return null
	tm.call("create_from_faces", faces)
	# The mesh kept with it, so its id isn't reused while the entry lives.
	_tris[key] = [mesh, tm]
	return tm


## The parts the pointer hand's laser meets now, for pointed_part.
static func pointed(main: Node) -> Dictionary:
	var ui: Node = main.get("ui") if main != null else null
	var hand: Node3D = ui.get("pointer_hand") if ui != null else null
	if hand == null or not hand.has_method("get_ray_origin"):
		return {}
	return pick(main, hand.call("get_ray_origin"), hand.call("get_ray_direction"))


# --- Applying --------------------------------------------------------------------------------------------------------

## A library material as a recolour's material object: the id, metres per repeat, the pattern's turn (degrees) and a
## tint, each only when given.
static func library_change(id: String, tiling := 0.0, turn := 0.0, tint: Variant = null) -> Dictionary:
	var m := {"library_material": id}
	if tiling > 0.0:
		m["tiling"] = clampf(snappedf(tiling, 0.01), RoomSchema.TILING_MIN, RoomSchema.TILING_MAX)
	if absf(turn) > 0.01:
		m["turn"] = snappedf(wrapf(turn, -180.0, 180.0), 0.1)
	if tint != null and str(tint) != "":
		m["tint"] = tint
	return m


## Puts `change` (a material object: a library material, or a picture as texture) on a part: "Name/Part" a placed
## object's, else a room surface's name. The room on show changes, is kept and has an undo.
static func apply(tree: SceneTree, caller: Object, part: String, change: Dictionary) -> Dictionary:
	if part.contains("/"):
		return await ObjectCommands.recolour_part(tree, caller, part, change)
	return await recolour_surface(tree, caller, part, change)


## Takes the part's own entry out again: it shows what the room built it with.
static func reset(tree: SceneTree, caller: Object, part: String) -> Dictionary:
	if part.contains("/"):
		return await ObjectCommands.recolour_part(tree, caller, part, null)
	return await recolour_surface(tree, caller, part, null)


## A room surface's recolour entry (match: its node name): the change over what the entry had (a tiling keeps the
## material), or null to take it out. A stock room becomes a kept room of its own, as a placed object makes it.
static func recolour_surface(tree: SceneTree, caller: Object, part: String, change: Variant) -> Dictionary:
	var main := tree.current_scene
	var base: Node3D = _room_editor().call("_base", main.env) if main != null else null
	if base == null or base.find_children(part, "GeometryInstance3D", true, false).is_empty():
		return {"ok": false, "error": "nothing in the room is called %s (pointed_part names what the laser is on; "
				% part + "room_state lists the parts)"}
	var editor := ObjectLibrary.editor_for(tree, caller)
	var doc: Dictionary = editor.current_doc()
	var entries: Array = []
	if change is Dictionary:
		entries.append({"match": part, "material": ObjectCommands.entry_material(doc, part, change)})
	else:
		for r: Dictionary in doc.get("recolour", []):
			if str(r["match"]) == part:
				entries.append({"match": part, "material": null})
		if entries.is_empty():
			return {"ok": false, "error": "%s shows what the room built it with already" % part}
	var patch := {"schema": RoomSchema.VERSION, "recolour": entries}
	if not ObjectCommands._assistant_room(main):
		patch["name"] = ObjectCommands.room_name(main)
	var undo := ObjectCommands.undo_for(editor, main)
	var said := ("put %s back" if change == null else "changed %s") % part
	var r: Dictionary = await editor.apply("patch", patch, said)
	if r.get("ok") == true:
		r["undo"] = undo
	return r


# --- The commands ----------------------------------------------------------------------------------------------------

## pointed_part (read), material_apply and part_reset (room). picture_apply is the picture library's
## (scripts/pictures/picture_library.gd).
static func register_commands(_host: Node = null) -> void:
	var R := DevCommands
	R.register("pointed_part", func(_a: Dictionary, ctx: DevCommands.Call) -> Variant:
		var p := pointed(_main())
		if p.is_empty():
			return {"part": "", "message": "the laser is on no part of the room (the user points with the pointer "
					+ "controller; the menu closed)"}
		var room: Transform3D = _room_editor().call("to_room", _main())
		var at: Vector3 = room * (p["point"] as Vector3)
		return {"part": p["part"], "kind": p["kind"], "placed": p["placed"], "name": p["name"],
				"surface_material": p["surface_material"], "same": p["same"],
				"material": p["material"], "picture": p["picture"], "distance": snappedf(float(p["distance"]), 0.01),
				"point": [snappedf(at.x, 0.01), snappedf(at.y, 0.01), snappedf(at.z, 0.01)]}, {
		"description": "What the user's laser (the pointer controller's ray) is on now: a room surface (a wall, the "
				+ "floor, the seats: its name, recolour's match) or a part of something placed (\"Poster/Picture\"), "
				+ "so \"make this wall brick\" can be material_apply with that part. Empty part: it points at nothing. "
				+ "A placed model's part may have several materials (a sofa's fabric and its legs): same "
				+ "(\"Sofa/@Fabric\") reaches every surface of that object with the material the laser is on, and is "
				+ "what the user's own apply mode paints; give it as the part for \"make this fabric velvet\".",
		"params": [], "assistant": "read", "title": "What the laser points at",
		"returns": "{part (the name material_apply, picture_apply and part_reset take), kind: room | object, placed, "
				+ "name, surface_material (the model file's material the laser is on, or empty), same (\"<placed>/@"
				+ "<material>\": every surface of the object with it, or empty), material (the library material it "
				+ "shows, or empty), picture, distance, point [x, y, z] (room frame)} or {part: \"\", message}"})
	R.register("material_apply", func(a: Dictionary, ctx: DevCommands.Call) -> Variant:
		var id := str(a["material"])
		if not MaterialLibrary.has(id):
			return ctx.fail("no material %s (the materials command lists them; material_import adds one)" % id)
		var part := str(a["part"])
		var change := library_change(id, float(a["tiling"]), float(a["turn"]), a["tint"] if str(a["tint"]) != ""
				else null)
		return ObjectCommands._give(ctx, await apply(Engine.get_main_loop() as SceneTree, ctx.caller, part, change)), {
		"description": "Puts a library material (bundled or the user's own: the materials command) on one part: a "
				+ "room surface by name (pointed_part, room_state) or a placed object's part (\"Shelf/Board\"), or on "
				+ "every surface of a placed object with one of its model's materials (\"Sofa/@Fabric\": pointed_part's "
				+ "same; object_info with placed lists the materials). Kept in the room like a recolour, with an "
				+ "undo; part_reset puts it back.",
		"params": [{"name": "part", "type": "string", "required": true, "description": "The part: pointed_part's "
				+ "part or same, a room surface's name, \"<placed>/<part>\" or \"<placed>/@<material>\"."},
				{"name": "material", "type": "string", "required": true, "description": "The material's id."},
				{"name": "tiling", "type": "float", "default": 0.0, "description": "Metres per repeat of the pattern "
				+ "(0.02 to 20); 0: the material's own (its real size where known)."},
				{"name": "turn", "type": "float", "default": 0.0, "description": "Degrees the pattern is turned on "
				+ "the surface."},
				{"name": "tint", "type": "string", "default": "", "description": "#rrggbb multiplying its colour; "
				+ "empty: none."}],
		"level": "change", "assistant": "room", "title": "Put a material on a part",
		"returns": "{state: kept, ...}"})
	R.register("part_reset", func(a: Dictionary, ctx: DevCommands.Call) -> Variant:
		return ObjectCommands._give(ctx, await reset(Engine.get_main_loop() as SceneTree, ctx.caller,
				str(a["part"]))), {
		"description": "Puts a part back as the room built it: the material, picture or colour given to it "
				+ "(material_apply, picture_apply, recolour) goes. With an undo.",
		"params": [{"name": "part", "type": "string", "required": true, "description": "The part (pointed_part's "
				+ "part or same, a room surface's name, \"<placed>/<part>\" or \"<placed>/@<material>\")."}],
		"level": "change", "assistant": "room", "title": "Put a part back",
		"returns": "{state: kept, ...}"})
