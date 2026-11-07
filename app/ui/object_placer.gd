extends Node3D

## Placing an object with the laser (the Objects tab's Place and Move, ui/object_section.gd; docs/USAGE.md "Objects"). The
## panel goes out of the way and the object shows where the pointer controller's ray meets the room: on a wall with its
## back to the wall, on the floor standing and facing the viewer, in the air 2 m along the ray when the ray meets
## nothing. The pointer controller's stick turns it (left and right) and sizes it (up and down); the trigger sets it
## there; B or menu cancels. One controller does it all. ui_layer.gd hands it the input while it is active.
##
## Apply (paint by part, scripts/assistant/part_apply.gd; docs/features.md "Apply to a part"): a material or a picture
## chosen in the Objects tab goes on the part the laser points at (a wall, the floor, a seat, an object's part),
## shown there while it points; the stick sizes the pattern (up and down: metres per repeat) and turns it (left and
## right); the trigger applies it (kept in the room, with Undo; the panel comes back); B or menu cancels. On a placed
## model it paints by material: every surface of that object with the material the laser is on (a sofa's fabric, not
## its legs; PartApply.target_of()), and the preview shows on those surfaces only.
##
##   start_place(id) / start_move(name) / start_apply(what) -> bool      update(hand) -> the laser's length
##   on_stick()  commit()

const ObjectLibrary := preload("res://scripts/assistant/object_library.gd")
const ObjectCommands := preload("res://scripts/assistant/object_commands.gd")
const RoomModel := preload("res://scripts/assistant/room_model.gd")
const RoomEditor := preload("res://scripts/assistant/room_editor.gd")
const PartApply := preload("res://scripts/assistant/part_apply.gd")
const MaterialLibrary := preload("res://scripts/env/material_library.gd")
const PictureLibrary := preload("res://scripts/pictures/picture_library.gd")

## Degrees a second at full stick, and how fast the size changes (e-folds a second).
const TURN_RATE := 90.0
const SIZE_RATE := 0.8
const STICK_DEAD := 0.2
const SIZE_RANGE := Vector2(0.2, 5.0)
## Where the object waits when the ray meets no wall or floor, and how far a wall or floor may be.
const FREE_DISTANCE := 2.0
const REACH := 10.0

## scripts/main.gd
var app: Node
## A library object being placed, or "".
var placing_id := ""
## A placed object being moved, or "".
var moving := ""
## Applying: {"material": id} or {"picture": id}, or {} when not.
var applying := {}
## The part the laser is on while applying (PartApply.pick()), or {}.
var aimed := {}
## The pattern while applying a material: metres per repeat and degrees turned.
var apply_tiling := 1.0
var apply_turn := 0.0
var _apply_base_tiling := 1.0
var _shown_on: GeometryInstance3D
## What the preview changed, to put back: [{node, override, surfaces: [each surface's override before]}].
var _shown: Array = []
## The match the preview shows on (PartApply.target_of()).
var _shown_match := ""
var _picture_material: Material
var _preview: Node3D
var _hidden: Node3D
var _bounds := AABB()
var _start_scale := 1.0
var _scale := 1.0
var _turn := 0.0
var _inside := {}
## The last pose: {position, rotation, scale} for the room document.
var _pose := {}
var _busy := false


func active() -> bool:
	return placing_id != "" or moving != "" or not applying.is_empty()


## Apply: what = {"material": id} (a library material) or {"picture": id} (a kept picture). The panel goes; the laser
## points at parts.
func start_apply(what: Dictionary) -> bool:
	if app.env == null:
		return false
	_end()
	if what.has("material"):
		var id := str(what["material"])
		if not MaterialLibrary.has(id):
			return false
		_apply_base_tiling = float(MaterialLibrary.entry(id).get("tiling", 1.0))
		apply_tiling = _apply_base_tiling
		apply_turn = 0.0
		applying = {"material": id}
	elif what.has("picture"):
		var img := PictureLibrary.image(str(what["picture"]))
		if img == null:
			return false
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_texture = ImageTexture.create_from_image(img)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR if img.detect_alpha() != Image.ALPHA_NONE \
				else BaseMaterial3D.TRANSPARENCY_DISABLED
		_picture_material = m
		applying = {"picture": str(what["picture"])}
	else:
		return false
	aimed = {}
	return true


## What the trigger puts on the aimed part now (a recolour's material object).
func apply_change() -> Dictionary:
	if applying.has("material"):
		var tiling := apply_tiling if absf(apply_tiling - _apply_base_tiling) > 0.005 else 0.0
		return PartApply.library_change(str(applying["material"]), tiling, apply_turn)
	if applying.has("picture"):
		return PictureLibrary.texture_change(str(applying["picture"]))
	return {}


## The aimed part shows what is being applied (its own material back when the laser leaves it): the whole part, or on
## a placed model the surfaces with the material the laser is on (PartApply.target_of(), preview_targets()).
func _show_on(hit: Dictionary) -> void:
	var g: GeometryInstance3D = hit.get("node") if not hit.is_empty() else null
	var match := PartApply.target_of(hit) if g != null else ""
	if g == _shown_on and g != null and match == _shown_match and applying.has("picture"):
		return
	_unshow()
	if g == null:
		return
	_shown_on = g
	_shown_match = match
	var targets := PartApply.preview_targets(app, match) if match != "" else []
	if targets.is_empty():
		targets = [[g, -1]]
	var surfaces := {}
	for t: Array in targets:
		var node: GeometryInstance3D = t[0]
		if not surfaces.has(node):
			surfaces[node] = []
		(surfaces[node] as Array).append(int(t[1]))
	for node: GeometryInstance3D in surfaces:
		var before := {"node": node, "override": node.material_override, "surfaces": [], "only": []}
		if not (-1 in surfaces[node]) and node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			var mi := node as MeshInstance3D
			for si in mi.mesh.get_surface_count():
				(before["surfaces"] as Array).append(mi.get_surface_override_material(si))
			before["only"] = surfaces[node]
		_shown.append(before)
	_paint_preview(_preview_material())


## What the preview shows: the material with the stick's pattern, or the picture.
func _preview_material() -> Material:
	if applying.has("material"):
		return MaterialLibrary.get_material(str(applying["material"]), {"tiling": apply_tiling, "turn": apply_turn})
	return _picture_material


## The preview on what _show_on() took: a whole part's override, or the chosen surfaces (the part's override, when it
## has one, moves onto its other surfaces meanwhile, so the chosen ones show).
func _paint_preview(m: Material) -> void:
	for before: Dictionary in _shown:
		var node: GeometryInstance3D = before["node"]
		if not is_instance_valid(node):
			continue
		var only: Array = before["only"]
		if only.is_empty():
			node.material_override = m
			continue
		var mi := node as MeshInstance3D
		var whole: Material = before["override"]
		mi.material_override = null
		for si in mi.mesh.get_surface_count():
			if si in only:
				mi.set_surface_override_material(si, m)
			elif whole != null:
				mi.set_surface_override_material(si, whole)


func _unshow() -> void:
	for before: Dictionary in _shown:
		var node: GeometryInstance3D = before["node"]
		if not is_instance_valid(node):
			continue
		var was: Array = before["surfaces"]
		if node is MeshInstance3D and not was.is_empty():
			for si in mini(was.size(), (node as MeshInstance3D).mesh.get_surface_count()):
				(node as MeshInstance3D).set_surface_override_material(si, was[si])
		node.material_override = before["override"]
	_shown.clear()
	_shown_on = null
	_shown_match = ""


func start_place(id: String) -> bool:
	var m := ObjectLibrary.get_object(id)
	var bytes := ObjectLibrary.glb(id)
	if m.is_empty() or bytes.is_empty() or app.env == null:
		return false
	var r := RoomModel.load_glb(bytes)
	if r.has("error"):
		return false
	_begin(r["node"], ObjectLibrary.bounds_of(m), 1.0)
	placing_id = id
	return true


func start_move(name: String) -> bool:
	var node := app.env.get_node_or_null("AssistantLayer/" + name) as Node3D if app.env != null else null
	# A model's nodes, or a built-in primitive's one mesh (rooms are made of objects: a box is placed like a shelf).
	var shape: Node3D = node.get_node_or_null("Model") as Node3D if node != null else null
	if shape == null and node != null:
		shape = node.get_node_or_null("Mesh") as Node3D
	if shape == null:
		return false
	var s := node.scale.x
	var copy := shape.duplicate() as Node3D
	_begin(copy, node.get_meta("local_aabb", ObjectLibrary.bounds_of({})), s)
	moving = name
	_hidden = node
	node.visible = false
	return true


func _begin(model: Node3D, bounds: AABB, scale: float) -> void:
	_end()
	_preview = Node3D.new()
	_preview.name = "ObjectPreview"
	_preview.add_child(model)
	app.env.add_child(_preview)
	_bounds = bounds
	_start_scale = scale
	_scale = scale
	_turn = 0.0
	_pose = {}
	_inside = ObjectCommands.room_inside(app)


## B or menu: nothing changes. True when it was placing (the button is used up).
func cancel() -> bool:
	if not active():
		return false
	_end()
	return true


func _end() -> void:
	_unshow()
	applying = {}
	aimed = {}
	_picture_material = null
	if _preview != null and is_instance_valid(_preview):
		_preview.queue_free()
	_preview = null
	if _hidden != null and is_instance_valid(_hidden):
		_hidden.visible = true
	_hidden = null
	placing_id = ""
	moving = ""


## Each frame while active: the object follows the ray (applying: the part it meets shows the material). Returns how
## long the laser is.
func update(hand: Node3D) -> float:
	if not applying.is_empty():
		var hit := PartApply.pick(app, hand.call("get_ray_origin"), hand.call("get_ray_direction"), REACH)
		aimed = hit
		var g: GeometryInstance3D = hit.get("node") if not hit.is_empty() else null
		if g != _shown_on or (PartApply.target_of(hit) if g != null else "") != _shown_match:
			_show_on(hit)
		return float(hit.get("distance", FREE_DISTANCE))
	if _preview == null or not is_instance_valid(_preview):
		_end()
		return 3.0
	var to_room := RoomEditor.to_room(app)
	var origin: Vector3 = to_room * (hand.call("get_ray_origin") as Vector3)
	var dir: Vector3 = (to_room.basis * (hand.call("get_ray_direction") as Vector3)).normalized()
	var head: Vector3 = to_room * (app.camera as Node3D).global_position
	var hit := ObjectLibrary.aim(origin, dir, _inside)
	var length := FREE_DISTANCE
	if hit.is_empty() or float(hit["distance"]) > REACH or hit["surface"] == "ceiling":
		_pose = ObjectLibrary.pose(_bounds, "free", origin + dir * FREE_DISTANCE, Vector3.ZERO, head, _turn, _scale)
	else:
		_pose = ObjectLibrary.pose(_bounds, hit["surface"], hit["point"], hit["normal"], head, _turn, _scale)
		length = float(hit["distance"])
	var rot: Array = _pose["rotation"]
	var pos: Array = _pose["position"]
	_preview.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(rot[0]), deg_to_rad(rot[1]),
			deg_to_rad(rot[2]))).scaled(Vector3.ONE * _scale), Vector3(pos[0], pos[1], pos[2]))
	return length


## The pointer controller's stick: left and right turn it, up and down size it. Applying a material: the pattern.
func on_stick(stick: Vector2, delta: float) -> void:
	if applying.has("material"):
		var changed := false
		if absf(stick.x) > STICK_DEAD:
			apply_turn = wrapf(apply_turn - stick.x * TURN_RATE * delta, -180.0, 180.0)
			changed = true
		if absf(stick.y) > STICK_DEAD:
			apply_tiling = clampf(apply_tiling * exp(stick.y * SIZE_RATE * delta), 0.05, 20.0)
			changed = true
		if changed and not _shown.is_empty():
			_paint_preview(_preview_material())
		return
	if not applying.is_empty():
		return
	if absf(stick.x) > STICK_DEAD:
		_turn = wrapf(_turn - stick.x * TURN_RATE * delta, -180.0, 180.0)
	if absf(stick.y) > STICK_DEAD:
		_scale = clampf(_scale * exp(stick.y * SIZE_RATE * delta), _start_scale * SIZE_RANGE.x,
				_start_scale * SIZE_RANGE.y)


## The trigger: the object is set where it shows (a room change, kept, with an undo). {ok, summary, undo} or {error}.
func commit() -> Dictionary:
	if not applying.is_empty() and not _busy:
		var part := PartApply.target_of(aimed)
		if part == "":
			return {"ok": false, "error": TranslationServer.translate("Point at a part first")} # i18n
		_busy = true
		var change := apply_change()
		_unshow()
		var ar: Dictionary = await PartApply.apply(get_tree(), null, part, change)
		_busy = false
		_end()
		return ar
	if not active() or _busy or _pose.is_empty():
		return {"ok": false, "error": "nothing to place"}
	_busy = true
	var opts := {"position": _pose["position"], "rotation": _pose["rotation"], "scale": _pose["scale"]}
	var id := placing_id
	var name := moving
	_preview.visible = false
	var r: Dictionary
	if id != "":
		r = await ObjectCommands.place(get_tree(), null, id, opts)
	else:
		r = await ObjectCommands.move(get_tree(), null, name, opts)
	_busy = false
	_end()
	return r
