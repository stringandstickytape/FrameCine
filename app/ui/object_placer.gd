extends Node3D

## Placing an object with the laser (the Objects tab's Place and Move, ui/object_section.gd; docs/USAGE.md "Objects"). The
## panel goes out of the way and the object shows where the pointer controller's ray meets the room: on a wall with its
## back to the wall, on the floor standing and facing the viewer, in the air 2 m along the ray when the ray meets
## nothing. The pointer controller's stick turns it (left and right) and sizes it (up and down); the trigger sets it
## there; B or menu cancels. One controller does it all. ui_layer.gd hands it the input while it is active.
##
##   start_place(id) / start_move(name) -> bool      update(hand) -> the laser's length      on_stick()  commit()

const ObjectLibrary := preload("res://scripts/assistant/object_library.gd")
const ObjectCommands := preload("res://scripts/assistant/object_commands.gd")
const RoomModel := preload("res://scripts/assistant/room_model.gd")
const RoomEditor := preload("res://scripts/assistant/room_editor.gd")

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
	return placing_id != "" or moving != ""


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
	if node == null or not node.has_node("Model"):
		return false
	var s := node.scale.x
	var copy := node.get_node("Model").duplicate() as Node3D
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
	if _preview != null and is_instance_valid(_preview):
		_preview.queue_free()
	_preview = null
	if _hidden != null and is_instance_valid(_hidden):
		_hidden.visible = true
	_hidden = null
	placing_id = ""
	moving = ""


## Each frame while active: the object follows the ray. Returns how long the laser is.
func update(hand: Node3D) -> float:
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


## The pointer controller's stick: left and right turn it, up and down size it.
func on_stick(stick: Vector2, delta: float) -> void:
	if absf(stick.x) > STICK_DEAD:
		_turn = wrapf(_turn - stick.x * TURN_RATE * delta, -180.0, 180.0)
	if absf(stick.y) > STICK_DEAD:
		_scale = clampf(_scale * exp(stick.y * SIZE_RATE * delta), _start_scale * SIZE_RANGE.x,
				_start_scale * SIZE_RANGE.y)


## The trigger: the object is set where it shows (a room change, kept, with an undo). {ok, summary, undo} or {error}.
func commit() -> Dictionary:
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
