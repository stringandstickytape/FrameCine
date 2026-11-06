extends Node

## Object physics (docs/physics.md): any object placed from the object library can be picked up, held, dropped or
## thrown (scripts/play/object_grab.gd takes the controllers), and bounces off the seats, steps, walls, the floor and
## the film's screen. Jolt (project.godot) steps it; everything here goes through PhysicsServer3D, no nodes.
##
## Placed objects stay static: each solid placement of a kept room (a model, a box, a sphere, a cylinder, a plane; not
## a text, a particles area, a screen glow or a part with motion) is a static body of its shapes
## (scripts/play/physics_shapes.gd), made when the room comes on. Physics acts only once an object is picked up: its
## body turns rigid (continuous collision on, so a 20 m/s throw doesn't pass through a seat back), and when it has
## come to rest (or after MAX_FREE_SECONDS) it is static again where it lies. That place goes into the room document
## (its position and rotation; `home` keeps where it was placed, for Put back and Tidy up, object_commands.gd), and the
## kept room is saved SAVE_DELAY later. A wall object (its manifest's mount "wall") stays fixed on the wall while held,
## until it is pulled PULL_OFF from it; then it is a normal object (`mounted`: false in the document).
## A text or a particles area has no body: with `attach` (a placement's name) and `offset` it follows that object
## (as the room's lights do); unattached it stays where it is placed.
##
## The room collides as simple shapes: the base room's collision_shapes() or shapes from its meshes (physics_shapes.gd
## room_shapes), built ROOM_SHAPES_AFTER after a room with objects comes on (at rest they cost next to nothing); the
## screen as it shows, built again when it changes; in the passthrough room the Mixed reality tab's areas as boxes too.
##
## Judder: the headset shows 72 frames a second (more, at other refresh rates; fewer when a frame drops) and physics
## ticks 60 times. A moving object is drawn between its last two ticks (the engine's interpolation fraction), here, in
## _process: the engine's own physics interpolation stays off, as it would delay every node the app moves in _process.
##
## Impacts: a moving object's velocity change in one tick, beyond gravity's, is its impact speed; above
## Thud.THRESHOLD it plays the thud (scripts/play/thud.gd) where it is, louder and lower for faster and bigger ones.
##
##   available() -> bool                  the room on show has objects to pick up
##   aim(origin, dir, reach) -> {name, point, distance} or {}       what a ray (world) meets first
##   near(point, reach) -> name or ""     an object within reach of a point (world)
##   pick_up(name) -> bool, hold_to(name, xf), let_go(name, velocity, spin), cancel(name)   (object_grab.gd)
##   throw(name, velocity) -> bool        picked up and let go at once (the dev link, tests)
##   settle_all()                         everything moving comes to rest where it is now (before Put back)
##   is_moving(name), is_held(name), is_mounted(name), state() -> {...}
##   signal changed                       the objects to pick up, or the room document, changed
##   signal pulled_off(name)              a wall object came off its wall

const PhysicsShapes := preload("res://scripts/play/physics_shapes.gd")
const ObjectLibrary := preload("res://scripts/assistant/object_library.gd")
const RoomSchema := preload("res://scripts/assistant/room_schema.gd")
const Recipes := preload("res://scripts/dev/recipes.gd")
const Thud := preload("res://scripts/play/thud.gd")
const ASSISTANT_ROOM := "res://scripts/assistant/assistant_room.gd"
const LAYER := "AssistantLayer"
const SOLID: Array[String] = ["box", "sphere", "cylinder", "plane", "model"]

signal changed
signal pulled_off(name: String)

## An object's mass from its box: this many kg a cubic metre of it (half its box is taken as filled).
const DENSITY := 400.0
const MASS_RANGE := Vector2(0.05, 40.0)
const BOUNCE := 0.35
const FRICTION := 0.6
const ROOM_BOUNCE := 0.25
const ROOM_FRICTION := 0.7
const SCREEN_BOUNCE := 0.5
const LINEAR_DAMP := 0.05
const ANGULAR_DAMP := 0.8
## At rest: slower than REST_SPEED (m/s) and REST_SPIN (rad/s) for REST_SECONDS.
const REST_SPEED := 0.06
const REST_SPIN := 0.25
const REST_SECONDS := 0.4
## Still moving after this long (rolling round a bowl): it rests where it is.
const MAX_FREE_SECONDS := 15.0
## Held: the body is driven to the hand's target, no faster than these.
const HOLD_MAX_SPEED := 30.0
const HOLD_MAX_SPIN := 25.0
## A wall object comes off its wall when the hand's target is this far from it.
const PULL_OFF := 0.08
## Lost (fell through, or flew off): this far below the room's floor or from its middle; it goes back to where it was
## picked up.
const LOST_BELOW := 12.0
const LOST_FAR := 120.0
const SAVE_DELAY := 1.5
## The room's own shapes are built this long after a room with objects comes on (about 50 ms for the cinema on a
## desktop: not at the first pick-up, where it would be a hitch).
const ROOM_SHAPES_AFTER := 0.5
## A put-back pose this close to where it was placed is placed again (no home kept).
const HOME_SNAP := 0.005
## The cost, over the last this many ticks: the step's wall time (from this node's _physics_process, the last of the
## tick, to its _process, the first of the frame; ticks alone in their frame only) and this node's own share of the
## tick. Performance.TIME_PHYSICS_PROCESS is no measure: it counts the main loop's wait too.
const COST_TICKS := 120


class Body:
	var name := ""
	var node: Node3D
	var rid := RID()
	## Shape3D resources, kept alive while the body has them.
	var shapes: Array = []
	## The node's basis is the body's rotation times this (its scale).
	var rest := Basis()
	var kind := ""
	var mounted := false
	var moving := false
	var held := false
	var target := Transform3D()
	var prev := Transform3D()
	var cur := Transform3D()
	var last_v := Vector3.ZERO
	var still := 0.0
	var free_time := 0.0
	var last_thud := -1.0
	## Its biggest side, metres (the thud's pitch), and its mass.
	var size := 0.3
	var mass := 1.0
	## Where it was when it was picked up (cancel and lost put it back there), and whether it was on its wall then.
	var picked_from := Transform3D()
	var was_mounted := false


var main: Node3D
var thud: Thud
var enabled := true
var _env: Node3D
var _layer: Node3D
var _space := RID()
var _bodies := {}
var _by_rid := {}
var _room_rid := RID()
var _room_shapes: Array = []
var _room_xf := Transform3D()
var _room_built := false
var _screen_rid := RID()
var _screen_key := ""
var _screen_shapes: Array = []
var _mr_rid := RID()
var _mr_key := ""
var _mr_shapes: Array = []
var _env_xf := Transform3D()
## [{node, to, offset (Transform3D in the target's rigid frame)}]
var _followers: Array = []
var _save_at := -1.0
var _ticks := 0
## The step's wall time (ms) while something moved, and at rest; this node's own share of each tick.
var _step: Array[float] = []
var _step_rest: Array[float] = []
var _script: Array[float] = []
var _tick_end := 0
var _ticks_since := 0
var _tick_moved := false
var _gravity := Vector3(0, -9.8, 0)
var _last_build_ms := 0.0


func _ready() -> void:
	# Last in each tick, first in each frame: between the two is the physics step (state()).
	process_physics_priority = 100000
	process_priority = -100000
	_gravity = ProjectSettings.get_setting("physics/3d/default_gravity_vector", Vector3.DOWN) \
			* float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	thud = Thud.new()
	thud.name = "Thud"
	thud.main = main
	add_child(thud)
	main.environment_changed.connect(func(_id: String, _l: float) -> void: _rebuild.call_deferred())
	_rebuild.call_deferred()


func _exit_tree() -> void:
	_clear()


func available() -> bool:
	return enabled and not _bodies.is_empty()


func is_moving(name: String) -> bool:
	return _bodies.has(name) and (_bodies[name] as Body).moving


func is_held(name: String) -> bool:
	return _bodies.has(name) and (_bodies[name] as Body).held


func is_mounted(name: String) -> bool:
	return _bodies.has(name) and (_bodies[name] as Body).mounted


func names() -> Array:
	return _bodies.keys()


# --- The room on show -----------------------------------------------------------------------------------------------

## The room changed: the bodies of its placed objects (a kept room's), the followers; the room's own shapes wait for
## the first pick-up. The same room node again (a kept room adopted under its name) keeps what it has.
func _rebuild() -> void:
	var env: Node3D = main.env
	if env != null and env == _env and is_instance_valid(_env):
		return
	_clear()
	if env == null or env.get_script() != load(ASSISTANT_ROOM) or not env.is_inside_tree():
		changed.emit()
		return
	var t0 := Time.get_ticks_usec()
	_env = env
	_layer = env.get_node_or_null(LAYER) as Node3D
	_space = env.get_world_3d().space
	_env_xf = env.global_transform
	var doc: Dictionary = env.get("doc")
	if _layer != null:
		for p: Dictionary in doc.get("parts", []):
			_add_body(p)
		_find_followers(doc)
	_last_build_ms = (Time.get_ticks_usec() - t0) / 1000.0
	changed.emit()
	if not _bodies.is_empty():
		# The room's own shapes a moment after it came on (while it settles in), not at the first pick-up.
		get_tree().create_timer(ROOM_SHAPES_AFTER).timeout.connect(func() -> void:
			if _env == env:
				_ensure_room())


func _clear() -> void:
	for b: Body in _bodies.values():
		if b.rid.is_valid():
			PhysicsServer3D.free_rid(b.rid)
	_bodies.clear()
	_by_rid.clear()
	for rid: RID in [_room_rid, _screen_rid, _mr_rid]:
		if rid.is_valid():
			PhysicsServer3D.free_rid(rid)
	_room_rid = RID()
	_screen_rid = RID()
	_mr_rid = RID()
	_room_shapes = []
	_screen_shapes = []
	_mr_shapes = []
	_room_built = false
	_screen_key = ""
	_mr_key = ""
	_followers = []
	_env = null
	_layer = null
	if _save_at >= 0.0:
		_save_at = -1.0


## A placement's body: static, its shapes from what it is built as.
func _add_body(p: Dictionary) -> void:
	var name := str(p.get("name", ""))
	var kind := RoomSchema.kind_of(p)
	if not p.has("object") or not (kind in SOLID) or p.has("motion") or str(p.get("widget", "")) == "screen_glow":
		return
	var node := _layer.get_node_or_null(name) as Node3D
	if node == null:
		return
	var gx := node.global_transform
	var parts := PhysicsShapes.split(gx.basis)
	var hulls: Array = []
	var model_xf := Transform3D()
	if kind == "model":
		var model := node.get_node_or_null("Model") as Node3D
		if model == null:
			return
		hulls = ObjectLibrary.collision(str(p["object"]), model)
		model_xf = model.transform
	var shapes := PhysicsShapes.placement_shapes(kind, RoomSchema.build_form(p), parts[1], hulls, model_xf)
	if shapes.is_empty():
		return
	var b := Body.new()
	b.name = name
	b.node = node
	b.kind = kind
	b.rest = parts[1]
	b.cur = Transform3D(parts[0], gx.origin)
	b.prev = b.cur
	var m := ObjectLibrary.get_object(str(p["object"]))
	b.mounted = str(m.get("mount", "")) == "wall" and p.get("mounted", true) != false
	var local: AABB = node.get_meta("local_aabb", AABB(Vector3.ONE * -0.1, Vector3.ONE * 0.2))
	var scaled := Vector3(parts[1].x.length(), parts[1].y.length(), parts[1].z.length()) * local.size
	b.size = maxf(maxf(scaled.x, scaled.y), maxf(scaled.z, 0.02))
	b.mass = clampf(DENSITY * 0.5 * maxf(scaled.x, 0.02) * maxf(scaled.y, 0.02) * maxf(scaled.z, 0.02),
			MASS_RANGE.x, MASS_RANGE.y)
	b.rid = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(b.rid, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(b.rid, _space)
	for sh: Array in shapes:
		PhysicsServer3D.body_add_shape(b.rid, (sh[0] as Shape3D).get_rid(), sh[1])
		b.shapes.append(sh[0])
	PhysicsServer3D.body_set_collision_layer(b.rid, PhysicsShapes.LAYER_PLACED)
	PhysicsServer3D.body_set_collision_mask(b.rid, 0)
	PhysicsServer3D.body_set_param(b.rid, PhysicsServer3D.BODY_PARAM_BOUNCE, BOUNCE)
	PhysicsServer3D.body_set_param(b.rid, PhysicsServer3D.BODY_PARAM_FRICTION, FRICTION)
	PhysicsServer3D.body_set_state(b.rid, PhysicsServer3D.BODY_STATE_TRANSFORM, b.cur)
	_bodies[name] = b
	_by_rid[b.rid] = name


## Texts and particles areas with attach: they follow their object, `offset` in its frame (metres, unscaled) and
## their rotation relative to it.
func _find_followers(doc: Dictionary) -> void:
	for p: Dictionary in doc.get("parts", []):
		var to := str(p.get("attach", ""))
		if to == "" or not (RoomSchema.kind_of(p) in ["text", "particles"]):
			continue
		var node := _layer.get_node_or_null(str(p["name"])) as Node3D
		if node == null or _layer.get_node_or_null(to) == null:
			continue
		_followers.append({"node": node, "to": to, "offset": RoomSchema.attach_offset(p)})


## The room's own shapes (the base room's), in a static body that moves with the room.
func _ensure_room() -> void:
	if _room_built or _env == null:
		return
	_room_built = true
	var t0 := Time.get_ticks_usec()
	var base := _env.get_node_or_null("Base") as Node3D
	_room_shapes = PhysicsShapes.room_shapes(base) if base != null else []
	_room_rid = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(_room_rid, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(_room_rid, _space)
	for sh: Array in _room_shapes:
		PhysicsServer3D.body_add_shape(_room_rid, (sh[0] as Shape3D).get_rid(), sh[1])
	PhysicsServer3D.body_set_collision_layer(_room_rid, PhysicsShapes.LAYER_ROOM)
	PhysicsServer3D.body_set_collision_mask(_room_rid, 0)
	PhysicsServer3D.body_set_param(_room_rid, PhysicsServer3D.BODY_PARAM_BOUNCE, ROOM_BOUNCE)
	PhysicsServer3D.body_set_param(_room_rid, PhysicsServer3D.BODY_PARAM_FRICTION, ROOM_FRICTION)
	_room_xf = base.global_transform if base != null else _env.global_transform
	PhysicsServer3D.body_set_state(_room_rid, PhysicsServer3D.BODY_STATE_TRANSFORM, _room_xf)
	_update_screen()
	_update_real_areas()
	_last_build_ms = (Time.get_ticks_usec() - t0) / 1000.0


## The screen as it shows now: built again when its shape or place changed.
func _update_screen() -> void:
	var s := PhysicsShapes.screen_shapes(main.screen)
	var key := str(s.get("key", ""))
	if key == _screen_key:
		return
	_screen_key = key
	if _screen_rid.is_valid():
		PhysicsServer3D.free_rid(_screen_rid)
		_screen_rid = RID()
	_screen_shapes = s.get("shapes", [])
	if _screen_shapes.is_empty():
		return
	_screen_rid = _static_body(_screen_shapes, SCREEN_BOUNCE, ROOM_FRICTION)


## The passthrough room: the Mixed reality tab's areas (upright boxes in the real room's frame) as solid boxes.
func _update_real_areas() -> void:
	var rw: Node3D = main.features.get("real_windows") if main.get("features") != null else null
	var base := _env.get_node_or_null("Base") if _env != null else null
	var on: bool = rw != null and base != null and base.get_script() == load("res://environments/passthrough.gd")
	var key := ""
	if on:
		key = "%s %s" % [str(rw.get("windows")), str(rw.global_transform)]
	if key == _mr_key:
		return
	_mr_key = key
	if _mr_rid.is_valid():
		PhysicsServer3D.free_rid(_mr_rid)
		_mr_rid = RID()
	_mr_shapes = []
	if not on:
		return
	for w: Dictionary in rw.get("windows"):
		var c: Array = w.get("center", [0, 0, 0])
		var sz: Array = w.get("size", [0.1, 0.1, 0.1])
		var xf: Transform3D = rw.global_transform * Transform3D(Basis(Vector3.UP, float(w.get("yaw", 0.0))),
				Vector3(float(c[0]), float(c[1]), float(c[2])))
		_mr_shapes.append(PhysicsShapes.box(xf.origin, Vector3(float(sz[0]), float(sz[1]), float(sz[2])),
				xf.basis.orthonormalized()))
	if not _mr_shapes.is_empty():
		_mr_rid = _static_body(_mr_shapes, ROOM_BOUNCE, ROOM_FRICTION)


## A static body of world-frame shapes, on the room's layer.
func _static_body(shapes: Array, bounce: float, friction: float) -> RID:
	var rid := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(rid, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(rid, _space)
	for sh: Array in shapes:
		PhysicsServer3D.body_add_shape(rid, (sh[0] as Shape3D).get_rid(), sh[1])
	PhysicsServer3D.body_set_collision_layer(rid, PhysicsShapes.LAYER_ROOM)
	PhysicsServer3D.body_set_collision_mask(rid, 0)
	PhysicsServer3D.body_set_param(rid, PhysicsServer3D.BODY_PARAM_BOUNCE, bounce)
	PhysicsServer3D.body_set_param(rid, PhysicsServer3D.BODY_PARAM_FRICTION, friction)
	return rid


# --- Aiming ---------------------------------------------------------------------------------------------------------

## What a ray (world) meets first within reach, when that is an object: {name, point, distance}; {} for nothing, or
## for the room or the screen in front of it.
func aim(origin: Vector3, dir: Vector3, reach: float) -> Dictionary:
	if not available() or not _space.is_valid():
		return {}
	var state := PhysicsServer3D.space_get_direct_state(_space)
	if state == null:
		return {}
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir.normalized() * reach,
			PhysicsShapes.LAYER_ROOM | PhysicsShapes.LAYER_PLACED | PhysicsShapes.LAYER_MOVING)
	var hit := state.intersect_ray(q)
	if hit.is_empty() or not _by_rid.has(hit.get("rid", RID())):
		return {}
	var p: Vector3 = hit["position"]
	return {"name": _by_rid[hit["rid"]], "point": p, "distance": origin.distance_to(p)}


## An object whose shape is within `reach` of a point (world): the nearest by its middle, or "".
func near(point: Vector3, reach: float) -> String:
	if not available() or not _space.is_valid():
		return ""
	var state := PhysicsServer3D.space_get_direct_state(_space)
	if state == null:
		return ""
	var ball := SphereShape3D.new()
	ball.radius = reach
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = ball
	q.transform = Transform3D(Basis(), point)
	q.collision_mask = PhysicsShapes.LAYER_PLACED | PhysicsShapes.LAYER_MOVING
	var best := ""
	var best_d := INF
	for r: Dictionary in state.intersect_shape(q, 8):
		var name: String = _by_rid.get(r.get("rid", RID()), "")
		if name == "":
			continue
		var d := (_bodies[name] as Body).cur.origin.distance_to(point)
		if d < best_d:
			best_d = d
			best = name
	return best


## The body's frame now (world: its rotation and the node's origin), as hold_to() takes it.
func body_transform(name: String) -> Transform3D:
	return (_bodies[name] as Body).cur if _bodies.has(name) else Transform3D()


# --- Holding, letting go ----------------------------------------------------------------------------------------------

## Picks an object up (object_grab.gd). A wall object stays on its wall until pulled off (hold_to() decides).
func pick_up(name: String) -> bool:
	if not _bodies.has(name):
		return false
	var b: Body = _bodies[name]
	if b.held:
		return false
	_ensure_room()
	b.held = true
	b.picked_from = b.cur
	b.was_mounted = b.mounted
	b.target = b.cur
	_hide_contact(b)
	_update_screen()
	if not b.mounted:
		_make_moving(b)
	PhysicsServer3D.body_set_param(b.rid, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 0.0)
	return true


## Where the hand wants a held object (world: the body's rotation and the node's origin).
func hold_to(name: String, xf: Transform3D) -> void:
	if _bodies.has(name):
		(_bodies[name] as Body).target = xf


## Lets go: dropped, or thrown at `velocity` (world, m/s) with `spin` (rad/s). A wall object still on its wall stays.
func let_go(name: String, velocity := Vector3.ZERO, spin := Vector3.ZERO) -> void:
	if not _bodies.has(name):
		return
	var b: Body = _bodies[name]
	if not b.held:
		return
	b.held = false
	if b.mounted:
		return
	PhysicsServer3D.body_set_param(b.rid, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 1.0)
	PhysicsServer3D.body_set_state(b.rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, velocity)
	PhysicsServer3D.body_set_state(b.rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, spin)
	PhysicsServer3D.body_set_state(b.rid, PhysicsServer3D.BODY_STATE_SLEEPING, false)
	b.last_v = velocity
	b.still = 0.0
	b.free_time = 0.0


## B while holding: back where it was picked up (on its wall again, if it was), nothing changed.
func cancel(name: String) -> void:
	if not _bodies.has(name):
		return
	var b: Body = _bodies[name]
	b.held = false
	b.mounted = b.was_mounted
	_make_static(b, b.picked_from)


## Picked up and let go at once at `velocity` (world): a wall object comes off its wall.
func throw(name: String, velocity: Vector3, spin := Vector3.ZERO) -> bool:
	if not _bodies.has(name):
		return false
	var b: Body = _bodies[name]
	if b.held:
		return false
	pick_up(name)
	if b.mounted:
		b.mounted = false
		_make_moving(b)
	let_go(name, velocity, spin)
	return true


## Everything moving or held comes to rest where it is now (and is recorded): Put back and Tidy up start from that.
func settle_all() -> void:
	for b: Body in _bodies.values():
		if b.held:
			b.held = false
			if b.mounted:
				continue
		if b.moving:
			_settle(b)


func _make_moving(b: Body) -> void:
	if b.moving:
		return
	b.moving = true
	b.prev = b.cur
	b.last_v = Vector3.ZERO
	b.still = 0.0
	b.free_time = 0.0
	PhysicsServer3D.body_set_mode(b.rid, PhysicsServer3D.BODY_MODE_RIGID)
	PhysicsServer3D.body_set_collision_layer(b.rid, PhysicsShapes.LAYER_MOVING)
	PhysicsServer3D.body_set_collision_mask(b.rid, PhysicsShapes.LAYER_ROOM | PhysicsShapes.LAYER_PLACED
			| PhysicsShapes.LAYER_MOVING)
	PhysicsServer3D.body_set_param(b.rid, PhysicsServer3D.BODY_PARAM_MASS, b.mass)
	PhysicsServer3D.body_reset_mass_properties(b.rid)
	PhysicsServer3D.body_set_param(b.rid, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP_MODE,
			PhysicsServer3D.BODY_DAMP_MODE_REPLACE)
	PhysicsServer3D.body_set_param(b.rid, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP_MODE,
			PhysicsServer3D.BODY_DAMP_MODE_REPLACE)
	PhysicsServer3D.body_set_param(b.rid, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP, LINEAR_DAMP)
	PhysicsServer3D.body_set_param(b.rid, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP, ANGULAR_DAMP)
	PhysicsServer3D.body_set_enable_continuous_collision_detection(b.rid, true)
	PhysicsServer3D.body_set_state(b.rid, PhysicsServer3D.BODY_STATE_CAN_SLEEP, true)
	PhysicsServer3D.body_set_state(b.rid, PhysicsServer3D.BODY_STATE_TRANSFORM, b.cur)
	PhysicsServer3D.body_set_state(b.rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
	PhysicsServer3D.body_set_state(b.rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)


func _make_static(b: Body, xf: Transform3D) -> void:
	b.moving = false
	b.held = false
	b.cur = xf
	b.prev = xf
	PhysicsServer3D.body_set_mode(b.rid, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_collision_layer(b.rid, PhysicsShapes.LAYER_PLACED)
	PhysicsServer3D.body_set_collision_mask(b.rid, 0)
	PhysicsServer3D.body_set_param(b.rid, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 1.0)
	PhysicsServer3D.body_set_state(b.rid, PhysicsServer3D.BODY_STATE_TRANSFORM, xf)
	_show(b, xf)


## The node drawn at the body's frame (its scale kept), and what follows it.
func _show(b: Body, xf: Transform3D) -> void:
	if is_instance_valid(b.node):
		b.node.global_transform = Transform3D(xf.basis * b.rest, xf.origin)


func _hide_contact(b: Body) -> void:
	var c := _layer.get_node_or_null("Contact_" + b.name) as Node3D if _layer != null else null
	if c != null:
		c.visible = false


# --- Each tick --------------------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_ticks += 1
	_ticks_since += 1
	if _env != null:
		var t0 := Time.get_ticks_usec()
		_physics_tick(delta)
		_push(_script, (Time.get_ticks_usec() - t0) / 1000.0)
	_tick_moved = _bodies.values().any(func(b: Body) -> bool: return b.moving)
	_tick_end = Time.get_ticks_usec()


static func _push(a: Array[float], v: float) -> void:
	if a.size() >= COST_TICKS:
		a.pop_front()
	a.append(v)


func _physics_tick(delta: float) -> void:
	if not is_instance_valid(_env) or not _env.is_inside_tree():
		_clear()
		return
	if not _env.global_transform.is_equal_approx(_env_xf):
		_room_moved()
	var moving := false
	for b: Body in _bodies.values():
		if b.moving or (b.held and b.mounted):
			moving = true
			_tick(b, delta)
	if moving and _room_built and _ticks % 6 == 0:
		_update_screen()
		if _ticks % 30 == 0:
			_update_real_areas()
	if _save_at >= 0.0 and Time.get_ticks_msec() / 1000.0 >= _save_at:
		_save_now()


func _tick(b: Body, delta: float) -> void:
	if b.held and b.mounted:
		# On its wall: it stays until the hand's target is PULL_OFF away.
		if b.target.origin.distance_to(b.cur.origin) > PULL_OFF:
			b.mounted = false
			_make_moving(b)
			PhysicsServer3D.body_set_param(b.rid, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 0.0)
			pulled_off.emit(b.name)
		return
	var st := PhysicsServer3D.body_get_direct_state(b.rid)
	if st == null:
		return
	b.prev = b.cur
	b.cur = st.transform
	var v: Vector3 = st.linear_velocity
	var w: Vector3 = st.angular_velocity
	if b.held:
		# Driven to the hand's target in one tick (it collides on the way: a held object doesn't go into a wall).
		var to := ((b.target.origin - b.cur.origin) / delta).limit_length(HOLD_MAX_SPEED)
		PhysicsServer3D.body_set_state(b.rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, to)
		var dq := b.target.basis.get_rotation_quaternion() * b.cur.basis.get_rotation_quaternion().inverse()
		dq = dq.normalized()
		if dq.w < 0.0:
			dq = -dq
		var angle := 2.0 * acos(clampf(dq.w, -1.0, 1.0))
		var axis := Vector3(dq.x, dq.y, dq.z)
		var spin := axis.normalized() * angle / delta if axis.length() > 1e-6 else Vector3.ZERO
		PhysicsServer3D.body_set_state(b.rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY,
				spin.limit_length(HOLD_MAX_SPIN))
		PhysicsServer3D.body_set_state(b.rid, PhysicsServer3D.BODY_STATE_SLEEPING, false)
		b.last_v = v
		return
	# The impact: the velocity's change this tick beyond gravity's.
	var dv := (v - (b.last_v + _gravity * delta)).length()
	var now := Time.get_ticks_msec() / 1000.0
	if dv > Thud.THRESHOLD and now - b.last_thud > Thud.GAP:
		b.last_thud = now
		thud.play(b.cur.origin, dv, b.size)
	b.last_v = v
	b.free_time += delta
	if (v.length() < REST_SPEED and w.length() < REST_SPIN) or st.sleeping:
		b.still += delta
	else:
		b.still = 0.0
	var floor_y := _env.global_position.y
	if b.cur.origin.y < floor_y - LOST_BELOW or b.cur.origin.distance_to(_env.global_position) > LOST_FAR:
		# Lost: back where it was picked up.
		b.mounted = b.was_mounted
		_make_static(b, b.picked_from)
		return
	if b.still >= REST_SECONDS or b.free_time >= MAX_FREE_SECONDS:
		_settle(b)


## The room node moved (the viewer chose another seat): every body with it.
func _room_moved() -> void:
	var delta := _env.global_transform * _env_xf.affine_inverse()
	_env_xf = _env.global_transform
	for b: Body in _bodies.values():
		if b.moving:
			b.cur = delta * b.cur
			b.prev = b.cur
			PhysicsServer3D.body_set_state(b.rid, PhysicsServer3D.BODY_STATE_TRANSFORM, b.cur)
		elif is_instance_valid(b.node):
			b.cur = Transform3D(PhysicsShapes.split(b.node.global_transform.basis)[0], b.node.global_position)
			b.prev = b.cur
			PhysicsServer3D.body_set_state(b.rid, PhysicsServer3D.BODY_STATE_TRANSFORM, b.cur)
	if _room_rid.is_valid():
		var base := _env.get_node_or_null("Base") as Node3D
		_room_xf = base.global_transform if base != null else _env.global_transform
		PhysicsServer3D.body_set_state(_room_rid, PhysicsServer3D.BODY_STATE_TRANSFORM, _room_xf)


## Each frame: the moving objects drawn between their last two ticks, and what follows them.
func _process(_delta: float) -> void:
	if _ticks_since == 1 and _env != null and _room_built:
		_push(_step if _tick_moved else _step_rest, (Time.get_ticks_usec() - _tick_end) / 1000.0)
	_ticks_since = 0
	if _env == null or _bodies.is_empty():
		return
	var f := Engine.get_physics_interpolation_fraction()
	var any := false
	for b: Body in _bodies.values():
		if b.moving:
			any = true
			_show(b, b.prev.interpolate_with(b.cur, f))
	if any or not _followers.is_empty():
		_follow()


func _follow() -> void:
	for fl: Dictionary in _followers:
		var node: Node3D = fl["node"]
		var to: String = fl["to"]
		if not is_instance_valid(node) or not _bodies.has(to):
			continue
		var b: Body = _bodies[to]
		if not b.moving and not b.held and node.has_meta("followed"):
			continue
		node.set_meta("followed", true)
		var target := b.node.global_transform
		var rigid := Transform3D(PhysicsShapes.split(target.basis)[0], target.origin)
		node.global_transform = rigid * (fl["offset"] as Transform3D)


# --- At rest ----------------------------------------------------------------------------------------------------------

## At rest: static where it lies, and that place in the room document (its home kept), saved soon.
func _settle(b: Body) -> void:
	var xf := b.cur
	_make_static(b, xf)
	_follow()
	_record(b)


func _record(b: Body) -> void:
	if _env == null or not is_instance_valid(b.node):
		return
	var part := _part_of(b.name)
	if part.is_empty():
		return
	var local := b.node.transform
	var rot := (PhysicsShapes.split(local.basis)[0] as Basis).get_euler()
	var pos := [snappedf(local.origin.x, 0.001), snappedf(local.origin.y, 0.001), snappedf(local.origin.z, 0.001)]
	var deg := [snappedf(rad_to_deg(rot.x), 0.01), snappedf(rad_to_deg(rot.y), 0.01), snappedf(rad_to_deg(rot.z), 0.01)]
	if not part.has("home"):
		part["home"] = {"position": part.get("position", [0, 0, 0]), "rotation": part.get("rotation", [0, 0, 0])}
		if part.has("mounted"):
			part["home"]["mounted"] = part["mounted"]
	part["position"] = pos
	part["rotation"] = deg
	if b.was_mounted and not b.mounted:
		part["mounted"] = false
	var home: Dictionary = part["home"]
	var at_home := RoomSchema.vec3(home.get("position")).distance_to(RoomSchema.vec3(pos)) < HOME_SNAP \
			and RoomSchema.vec3(home.get("rotation")).distance_to(RoomSchema.vec3(deg)) < 0.5
	if at_home and part.get("mounted") == home.get("mounted"):
		part.erase("home")
	_save_at = Time.get_ticks_msec() / 1000.0 + SAVE_DELAY
	changed.emit()
	# The Objects tab shows it moved (Put back, Tidy up).
	var layer: Node = main.get("ui")
	var pane: Node = layer.get("ui") if layer != null else null
	var tab: Node = pane.get("objects") if pane != null else null
	if tab != null and tab.has_method("sync_objects"):
		tab.sync_objects()


func _part_of(name: String) -> Dictionary:
	var doc: Dictionary = _env.get("doc") if _env != null else {}
	for p: Dictionary in doc.get("parts", []):
		if str(p.get("name", "")) == name:
			return p
	return {}


## The kept room written with the objects where they lie (a showroom becomes a kept room of its own, as any change
## to it does).
func _save_now() -> void:
	_save_at = -1.0
	if _env == null:
		return
	var doc: Dictionary = _env.get("doc")
	var name := Recipes.clean_name(str(doc.get("name", "")))
	if name == "":
		name = "Assistant room"
	doc["name"] = name
	var err: String = (load(ASSISTANT_ROOM) as GDScript).call("save", doc, name)
	if err != "":
		push_warning("Object physics: the room isn't saved: %s" % err)
		return
	if str(main.env_id) != Recipes.PREFIX + name:
		main.adopt_environment_id(Recipes.PREFIX + name)


## Saved now, not SAVE_DELAY later (tests, before the room changes).
func save_now() -> void:
	if _save_at >= 0.0:
		_save_now()


# --- What it costs ------------------------------------------------------------------------------------------------

## {bodies, moving, held, room_shapes, room_built, screen, followers, cost_ms {step, step_max (while something moves),
## rest (the step with everything at rest), script (this node's share of a tick)}, build_ms, thuds, last_thud}.
func state() -> Dictionary:
	var moving := 0
	var held := 0
	for b: Body in _bodies.values():
		moving += 1 if b.moving else 0
		held += 1 if b.held else 0
	var step := _mean_max(_step)
	var cost := {"step": step.x, "step_max": step.y, "rest": _mean_max(_step_rest).x, "script": _mean_max(_script).x}
	return {"bodies": _bodies.size(), "moving": moving, "held": held, "room_shapes": _room_shapes.size(),
			"room_built": _room_built, "screen": _screen_key.get_slice(" ", 0) if _screen_key != "" else "none",
			"followers": _followers.size(), "cost_ms": cost, "build_ms": snappedf(_last_build_ms, 0.01),
			"thuds": thud.count, "last_thud": thud.last}


## Forget the measured cost (a test starts its count).
func reset_cost() -> void:
	_step.clear()
	_step_rest.clear()
	_script.clear()


static func _mean_max(a: Array[float]) -> Vector2:
	if a.is_empty():
		return Vector2.ZERO
	var sum := 0.0
	var most := 0.0
	for c in a:
		sum += c
		most = maxf(most, c)
	return Vector2(snappedf(sum / a.size(), 0.001), snappedf(most, 0.001))
