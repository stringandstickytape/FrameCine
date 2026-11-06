extends Node3D

## Windows to the real room (the user, 2026-11-06: "mark an area in 3d space using the controller then track that and
## reveal it"; docs/features.md "Windows to the real room"; the Mixed reality tab, ui/mixed_reality_tab.gd). The viewer
## marks a real place (the coffee table, the keyboard) with a controller; the app keeps an upright box round it, fixed
## to the real room, and through it the headset's cameras show, in whatever room is on.
##
## Fixed to the real room: a window is kept in the runtime's own tracking space (the Stage reference space, set by the
## headset's room setup), not the scene's. This node's transform is XROrigin3D's times XRServer's reference frame each
## frame, so recentring the screen (which moves the reference frame) leaves the windows where the table is, and they
## are there again next time.
##
## Showing the cameras: while a window is on (or a mode below runs), the OpenXR environment blend mode is ALPHA_BLEND
## and the viewport keeps its alpha (as the passthrough room, environments/passthrough.gd, does for the whole view). A
## black backstop far out keeps everything else opaque (the room's gaps would show the cameras otherwise); each window
## draws shaders/real_window.gdshader, which takes the eye buffer's alpha down where it is. None on: opaque, as before.
## In the passthrough room it leaves the blend mode to that room.
##
## Modes (`mode`; `marking` is true in any): the whole view is the cameras' (a window round the viewer), so the real
## things can be seen, and the box being made or changed shows tinted.
##   sweep    the trigger held sweeps the pointer controller's tip (its ray origin) over the place; letting go keeps an
##            upright box round it, turned to the way the viewer faced, MARGIN round
##   corners  the trigger touched to three corners of a flat thing (a table, a keyboard): the first two give its edge
##            and so its turn, the third its depth; the stick sets the height above it; the trigger again keeps it,
##            CORNER_MARGIN round
##   edit     an area already kept, a face at a time (the user, 2026-11-06): the chosen face shows bright and the stick
##            moves it along its own axis, the way the stick is pushed as the viewer sees it (up: a top face up, a face
##            towards the viewer away; right: a face on the right to the right); the trigger goes to the next face,
##            and after the six to Turn, where left and right turn the box about up. finish() keeps it, cancel puts
##            it back. Moving the box is moving its faces.
##
## The room light dims the cameras' view as in the passthrough room, but never under `light_min` ([real_room]
## light_min, 0.4): a window is there to find the cup in the dark.
##
##   windows                          [{id, name, center [x, y, z], size [w, h, d], yaw (radians), on}] (tracking space)
##   start_mark() / start_corners() / start_edit(id) -> bool   false without the cameras' view, unless `force`
##   sweep(on), add_point(p)          the sweep: trigger held / let go; a point (scene coordinates) while held
##   corner(p) -> "more" | "height" | "done"    the corners: one touched (scene coordinates)
##   next_face() -> its name, face_name(), face_hint()     edit: the trigger
##   on_stick(stick, delta)           corners: the height; edit: the face, or the turn
##   finish() -> window or {}         sweep, corners or edit kept; cancel_mark() puts things back
##   set_on(id, on), set_all(on), set_size(id, size), remove(id) -> removed, restore(window), mark_again(id)
##   status() -> String
## Kept in user://real_windows.json.

signal changed

const SHADER := preload("res://shaders/real_window.gdshader")
const FILE := "user://real_windows.json"
## Metres added round what was swept or touched, and the least and most a side can be.
const MARGIN := 0.04
const CORNER_MARGIN := 0.015
const MIN_SIDE := 0.05
const MAX_SIDE := 4.0
const MAX_WINDOWS := 16
## Samples closer than this to the last one are not kept.
const STEP := 0.01
const LIGHT_MIN := 0.4
## The corners' height to start with, and how fast the stick changes it (metres a second at full stick).
const CORNER_HEIGHT := 0.1
const HEIGHT_RATE := 0.3
## Adjust: degrees a second at full stick, and the size's rate (e-folds a second).
## Edit: metres a second for a face and degrees a second for the turn at full stick (squared: fine near the middle).
const FACE_RATE := 0.25
const TURN_RATE := 45.0
## The faces as the box's own axis and side: [axis 0 x, 1 y, 2 z, sign].
const FACES := [[0, 1], [0, -1], [1, 1], [1, -1], [2, 1], [2, -1]]
const FACE_THICKNESS := 0.004
const FACE_COLOR := Color(1.0, 0.8, 0.3, 0.55)
const STICK_DEAD := 0.2
## fit_yaw(): footprints within this fraction of the least count as the same.
const FIT_TIE := 0.03
const BACKSTOP_RADIUS := 900.0
## Draw order: after the room's own see-through effects (the cinema's projector beam, 0; the floor reflection, 1),
## which drawn after a window put their alpha back (the top of a window by the screen went black while the film
## played, the user, 2026-11-06); before the menu (the tablet from 4, the panel 11, 12), subtitles and toasts (10).
const PRIORITY := 2
const PREVIEW_COLOR := Color(0.35, 0.65, 1.0, 0.22)

var main: Node3D
## Builds and blend-mode handling without an XR session (tests).
var force := false
var windows: Array = []
## "", "sweep", "corners" or "edit".
var mode := ""
var marking: bool:
	get:
		return mode != ""
var sweeping := false
## The area chosen in the tab ("" none): drawn brighter while the menu is open.
var selected := ""
var light_min := LIGHT_MIN
## Corners: the touched points (tracking space) and the height above them.
var corners := PackedVector3Array()
var height := CORNER_HEIGHT
## Sweep: the points so far.
var _points := PackedVector3Array()
var _yaw := 0.0
## The sweep: the way the viewer faced when it began.
var _facing := 0.0
## Mark again / edit: the area being changed, and how it was.
var _target := ""
var _before := {}
## Adjust: the box now ({center, size} tracking space, _yaw), the grab's start (hand and box).
var _box := {}
## Edit: the faces in the order the trigger goes through them (nearest the viewer first), and where it is
## (FACES.size(): Turn).
var _face_order: Array = []
var _face := 0
var _face_mark: MeshInstance3D
var _boxes := {}
var _mat: ShaderMaterial
var _full: MeshInstance3D
var _preview: MeshInstance3D
var _backstop: MeshInstance3D
var _xr: XRInterface
## The blend mode and viewport alpha were switched here (and what the viewport had before).
var _ours := false
var _saved_transparent := false


func _ready() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.render_priority = PRIORITY
	if main != null and main.get("settings") != null:
		light_min = clampf(float(main.settings.get_value("real_room", "light_min", LIGHT_MIN)), 0.0, 1.0)
	_load()
	_build_helpers()
	_rebuild()


## True when the headset can show its cameras behind the app (the ALPHA_BLEND environment blend mode).
func available() -> bool:
	if force:
		return true
	_xr = XRServer.find_interface("OpenXR")
	return _xr != null and _xr.is_initialized() \
			and XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND in _xr.get_supported_environment_blend_modes()


# --- Making ----------------------------------------------------------------------------------------------------------

## The sweep. mark_again(id) does the same for an area already kept (its box replaced, its name and On kept).
func start_mark() -> bool:
	return _start("sweep", "")


func mark_again(id: String) -> bool:
	return _find(id) >= 0 and _start("sweep", id)


func start_corners() -> bool:
	return _start("corners", "")


func start_edit(id: String) -> bool:
	var i := _find(id)
	if i < 0 or not _start("edit", id):
		return false
	var w: Dictionary = windows[i]
	_box = {"center": _vec(w["center"]), "size": _vec(w["size"])}
	_yaw = float(w.get("yaw", 0.0))
	_face_order = _faces_by_view()
	_face = 0
	_show_preview(_box)
	return true


func _start(m: String, target: String) -> bool:
	if not available() or (target == "" and windows.size() >= MAX_WINDOWS):
		return false
	cancel_mark()
	mode = m
	_target = target
	_before = (windows[_find(target)] as Dictionary).duplicate(true) if target != "" else {}
	sweeping = false
	_points.clear()
	corners.clear()
	height = CORNER_HEIGHT
	_preview.visible = false
	_full.visible = true
	return true


func sweep(on: bool) -> void:
	if mode != "sweep":
		return
	if on and not sweeping:
		_yaw = _facing_yaw()
		_facing = _yaw
	sweeping = on


## A point the controller's tip passed, in scene coordinates.
func add_point(p: Vector3) -> void:
	if not (mode == "sweep" and sweeping):
		return
	var raw := global_transform.affine_inverse() * p
	if not _points.is_empty() and _points[-1].distance_to(raw) < STEP:
		return
	_points.append(raw)
	_yaw = fit_yaw(_points, _facing)
	_show_preview(box_of(_points, _yaw))


## A corner touched (scene coordinates): "more" after the first and second, "height" after the third (the stick sets
## it; touch again to keep), "done" on the touch after that.
func corner(p: Vector3) -> String:
	if mode != "corners":
		return ""
	if corners.size() >= 3:
		return "done"
	corners.append(global_transform.affine_inverse() * p)
	_show_preview(corner_box(corners, height))
	return "height" if corners.size() == 3 else "more"


## The box on touched corners: turned along the first edge (first to second), round the corners and the same points
## `h` higher, CORNER_MARGIN round. With one corner: a small box on it; with two, a thin one along the edge.
static func corner_box(pts: PackedVector3Array, h: float) -> Dictionary:
	var yaw := corner_yaw(pts)
	var all := PackedVector3Array()
	for p in pts:
		all.append(p)
		all.append(p + Vector3.UP * h)
	var b := box_of(all, yaw, CORNER_MARGIN)
	b["yaw"] = yaw
	return b


## The turn that puts the box's X axis along the first edge (0 with fewer than two corners).
static func corner_yaw(pts: PackedVector3Array) -> float:
	if pts.size() < 2:
		return 0.0
	var e := pts[1] - pts[0]
	e.y = 0.0
	if e.length_squared() < 1e-6:
		return 0.0
	return atan2(-e.z, e.x)


## Edit: the trigger. The next face (or Turn after the last); its name.
func next_face() -> String:
	if mode != "edit":
		return ""
	_face = (_face + 1) % (FACES.size() + 1)
	_show_preview(_box)
	return face_name()


## "front", "back", "left", "right", "top", "bottom" as the viewer sees the face now; "turn".
func face_name() -> String:
	if _face >= FACES.size() or _face_order.is_empty():
		return "turn"
	var n := _view_dir(_face_normal(_face_order[_face]))
	if absf(n.y) >= maxf(absf(n.x), absf(n.z)):
		return "top" if n.y > 0.0 else "bottom"
	if absf(n.x) >= absf(n.z):
		return "right" if n.x > 0.0 else "left"
	return "front" if n.z > 0.0 else "back"


## What the stick does now, for the notice.
func face_hint() -> String:
	match face_name():
		"turn":
			return "Turn: stick left and right. Trigger: the faces again. Menu keeps it; B puts it back."
		"top", "bottom":
			return "The %s face: stick up and down moves it. Trigger: next face. Menu keeps it." % face_name()
		"left", "right":
			return "The %s face: stick left and right moves it. Trigger: next face. Menu keeps it." % face_name()
		_:
			return "The %s face: stick up moves it away, down nearer. Trigger: next face. Menu keeps it." % face_name()


## Corners: up and down set the height. Edit: the face moves the way the stick is pushed (as the viewer sees it), or,
## on Turn, left and right turn the box.
func on_stick(stick: Vector2, delta: float) -> void:
	if mode == "corners" and corners.size() >= 3 and absf(stick.y) > STICK_DEAD:
		height = clampf(height + stick.y * HEIGHT_RATE * delta, 0.0, MAX_SIDE)
		_show_preview(corner_box(corners, height))
	elif mode == "edit":
		if _face >= FACES.size():
			if absf(stick.x) > STICK_DEAD:
				_yaw -= deg_to_rad(stick.x * absf(stick.x) * TURN_RATE * delta)
		else:
			var push := _push(_face_order[_face], stick)
			if absf(push) > STICK_DEAD:
				move_face(_face_order[_face], push * absf(push) * FACE_RATE * delta)
		_show_preview(_box)


## Moves face f (an index into FACES) `d` metres outwards (negative: inwards); the opposite face stays.
func move_face(f: int, d: float) -> void:
	var axis: int = FACES[f][0]
	var size: Vector3 = _box["size"]
	var old := size[axis]
	size[axis] = clampf(old + d, MIN_SIDE, MAX_SIDE)
	_box["size"] = size
	_box["center"] = (_box["center"] as Vector3) + _face_normal(f) * ((size[axis] - old) * 0.5)


## The stick's push along face f's normal as the viewer sees it: up for a face up or away, right for a face on the
## right (and their opposites, negative).
func _push(f: int, stick: Vector2) -> float:
	var n := _view_dir(_face_normal(f))
	if absf(n.y) >= maxf(absf(n.x), absf(n.z)):
		return stick.y * signf(n.y)
	if absf(n.x) >= absf(n.z):
		return stick.x * signf(n.x)
	return stick.y * -signf(n.z)


## Face f's outward normal (tracking space).
func _face_normal(f: int) -> Vector3:
	var n := Vector3.ZERO
	n[FACES[f][0]] = float(FACES[f][1])
	return Basis(Vector3.UP, _yaw) * n


## A direction (tracking space) as the viewer sees it: x right, y up, z towards the viewer.
func _view_dir(d: Vector3) -> Vector3:
	var cam: Node3D = main.get("xr_camera") if main != null else null
	var world := global_transform.basis * d
	if cam == null or not cam.is_inside_tree():
		return world
	return cam.global_transform.basis.inverse() * world


## The faces nearest the viewer first: the front, then the sides, top and bottom, the back last.
func _faces_by_view() -> Array:
	var order := range(FACES.size())
	order.sort_custom(func(a: int, b: int) -> bool: return _view_dir(_face_normal(a)).z > _view_dir(_face_normal(b)).z)
	return order


## What the mode made, kept: a new area (sweep, corners), or the area changed (mark again, edit). {} when nothing
## was made (nothing swept, fewer than three corners).
func finish() -> Dictionary:
	var box := {}
	match mode:
		"sweep":
			if not _points.is_empty():
				box = box_of(_points, _yaw)
		"corners":
			if corners.size() >= 3:
				box = corner_box(corners, height)
				_yaw = float(box["yaw"])
		"edit":
			box = _box
	var w := {}
	if not box.is_empty():
		var i := _find(_target)
		if i >= 0:
			w = windows[i]
		else:
			w = {"id": _new_id(), "name": "Area %d" % _next_number(), "on": true}
			windows.append(w)
		w["center"] = _v(box["center"])
		w["size"] = _v(box["size"])
		w["yaw"] = snappedf(_yaw, 0.0001)
		_save()
	_target = ""
	_before = {}
	_end_mode()
	_rebuild()
	return w


## Leaves the mode; an area being edited or marked again keeps what it had.
func cancel_mark() -> void:
	if _target != "" and not _before.is_empty():
		var i := _find(_target)
		if i >= 0:
			windows[i] = _before
	_target = ""
	_before = {}
	_end_mode()
	_rebuild()


## The area a change began from ({} none): undo after finish() (the caller keeps it).
func before() -> Dictionary:
	return _before.duplicate(true)


func _end_mode() -> void:
	mode = ""
	sweeping = false
	_points.clear()
	corners.clear()
	_face_order = []
	if _preview != null:
		_preview.visible = false
	if _face_mark != null:
		_face_mark.visible = false
	if _full != null:
		_full.visible = false


## The turn for a swept box: the one, within 45 degrees either side of the way the viewer faced, that gives the least
## floor area round the points (a monitor at 45 degrees, swept along, gets a box along it, not one across it with the
## monitor diagonal inside; the user, 2026-11-06). Within FIT_TIE of the least, the turn nearest the facing one wins,
## so a table in front stays square to the viewer.
static func fit_yaw(points: PackedVector3Array, facing: float) -> float:
	if points.size() < 2:
		return facing
	var areas := {}
	var least := INF
	for step in range(-45, 45):
		# The footprint's own extent (box_of's least side would make thin sweeps tie over several degrees).
		var turn := Basis(Vector3.UP, -(facing + deg_to_rad(step)))
		var lo := Vector2.INF
		var hi := -Vector2.INF
		for p in points:
			var q := turn * p
			lo = lo.min(Vector2(q.x, q.z))
			hi = hi.max(Vector2(q.x, q.z))
		areas[step] = (hi.x - lo.x + 0.001) * (hi.y - lo.y + 0.001)
		least = minf(least, areas[step])
	var best := 0
	for step: int in areas:
		if areas[step] <= least * (1.0 + FIT_TIE) and (absi(step) < absi(best) or areas[best] > least * (1.0 + FIT_TIE)):
			best = step
	return facing + deg_to_rad(best)


## An upright box round `points` (tracking space), turned by yaw, `margin` round, each side within MIN_SIDE..MAX_SIDE:
## {center: Vector3, size: Vector3}.
static func box_of(points: PackedVector3Array, yaw: float, margin := MARGIN) -> Dictionary:
	var turn := Basis(Vector3.UP, -yaw)
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for p in points:
		var q := turn * p
		lo = lo.min(q)
		hi = hi.max(q)
	var size := (hi - lo + Vector3.ONE * margin * 2.0).clamp(Vector3.ONE * MIN_SIDE, Vector3.ONE * MAX_SIDE)
	var center := Basis(Vector3.UP, yaw) * ((lo + hi) * 0.5)
	return {"center": center, "size": size}


# --- The windows -----------------------------------------------------------------------------------------------------

func set_on(id: String, on: bool) -> void:
	var i := _find(id)
	if i >= 0:
		windows[i]["on"] = on
		_save()
		_rebuild()


func set_all(on: bool) -> void:
	for w: Dictionary in windows:
		w["on"] = on
	_save()
	_rebuild()


## A side's size in metres (the tab's sliders), the box's centre kept.
func set_size(id: String, size: Vector3) -> void:
	var i := _find(id)
	if i < 0:
		return
	windows[i]["size"] = _v(size.clamp(Vector3.ONE * MIN_SIDE, Vector3.ONE * MAX_SIDE))
	_save()
	_rebuild()


func remove(id: String) -> Dictionary:
	var i := _find(id)
	if i < 0:
		return {}
	var w: Dictionary = windows[i]
	windows.remove_at(i)
	if selected == id:
		selected = ""
	_save()
	_rebuild()
	return w


## Puts a removed area back, or an area back as it was (undo of a change).
func restore(w: Dictionary) -> void:
	if w.is_empty():
		return
	var i := _find(str(w["id"]))
	if i >= 0:
		windows[i] = w.duplicate(true)
	else:
		windows.append(w.duplicate(true))
	_save()
	_rebuild()


func any_on() -> bool:
	return windows.any(func(w: Dictionary) -> bool: return bool(w.get("on", true)))


func window_by_id(id: String) -> Dictionary:
	var i := _find(id)
	return windows[i] if i >= 0 else {}


func set_light_min(v: float) -> void:
	light_min = clampf(v, 0.0, 1.0)
	if main != null and main.get("settings") != null:
		main.settings.set_value("real_room", "light_min", light_min)


func status() -> String:
	if not available():
		return "The headset's cameras can't show here."
	if windows.is_empty():
		return "None marked."
	var n := windows.filter(func(w: Dictionary) -> bool: return bool(w.get("on", true))).size()
	return "%d of %d on." % [n, windows.size()]


# --- Each frame ------------------------------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if main == null:
		return
	var origin: Node3D = main.get("xr_origin")
	var frame := XRServer.get_reference_frame() if (main.get("use_xr") == true or force) else Transform3D()
	global_transform = (origin.global_transform if origin != null else Transform3D()) * frame
	var light := light_min
	var rl: Node = main.get("features").get("room_light") if main.get("features") != null else null
	if rl != null and rl.has_method("effective"):
		light = clampf(float(rl.effective()), light_min, 1.0)
	_mat.set_shader_parameter("light", 1.0 if marking else light)
	if _full.visible:
		var cam: Node3D = main.get("xr_camera")
		if cam != null:
			_full.global_position = cam.global_position
	_blend(marking or any_on())


## The blend mode and the viewport's alpha for the windows (see the top); the passthrough room's own when it is on.
func _blend(want: bool) -> void:
	if main.get("env_id") == "passthrough":
		_backstop.visible = false
		return
	_backstop.visible = want
	if not (force or available()):
		return
	var vp := get_viewport()
	if want:
		if not _ours:
			_ours = true
			_saved_transparent = vp.transparent_bg
		if not vp.transparent_bg:
			vp.transparent_bg = true
		if _xr != null and _xr.environment_blend_mode != XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND:
			_xr.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
			print("Real-room windows: the cameras show through %d window(s)" % windows.size())
	elif _ours:
		_ours = false
		vp.transparent_bg = _saved_transparent
		if _xr != null:
			_xr.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_OPAQUE
		print("Real-room windows: none on, opaque again")


func _exit_tree() -> void:
	if _ours:
		_blend(false)


# --- Building --------------------------------------------------------------------------------------------------------

func _tint(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	m.no_depth_test = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.render_priority = PRIORITY + 1
	return m


func _build_helpers() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 3.0
	sphere.height = 6.0
	sphere.radial_segments = 16
	sphere.rings = 8
	_full = MeshInstance3D.new()
	_full.name = "MarkView"
	_full.mesh = sphere
	_full.material_override = _mat
	_full.top_level = true
	_full.visible = false
	_full.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_full)

	_preview = MeshInstance3D.new()
	_preview.name = "MarkPreview"
	_preview.mesh = BoxMesh.new()
	_preview.material_override = _tint(PREVIEW_COLOR)
	_preview.visible = false
	_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_preview)

	var fm := _tint(FACE_COLOR)
	fm.render_priority = PRIORITY + 2
	_face_mark = MeshInstance3D.new()
	_face_mark.name = "FaceMark"
	_face_mark.mesh = BoxMesh.new()
	_face_mark.material_override = fm
	_face_mark.visible = false
	_face_mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_face_mark)

	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_color = Color.BLACK
	bm.cull_mode = BaseMaterial3D.CULL_FRONT
	bm.disable_fog = true
	var back := SphereMesh.new()
	back.radius = BACKSTOP_RADIUS
	back.height = BACKSTOP_RADIUS * 2.0
	back.radial_segments = 12
	back.rings = 6
	_backstop = MeshInstance3D.new()
	_backstop.name = "Backstop"
	_backstop.mesh = back
	_backstop.material_override = bm
	_backstop.visible = false
	_backstop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_backstop)


func _show_preview(box: Dictionary) -> void:
	_preview.transform = box_transform(box, float(box.get("yaw", _yaw)))
	_preview.visible = true
	# Edit: the chosen face, a thin bright slab on it (none on Turn).
	var on_face := mode == "edit" and _face < FACES.size() and not _face_order.is_empty()
	_face_mark.visible = on_face
	if on_face:
		var f: int = _face_order[_face]
		var axis: int = FACES[f][0]
		var size: Vector3 = box["size"]
		var slab := size
		slab[axis] = FACE_THICKNESS
		_face_mark.transform = box_transform({"center": (box["center"] as Vector3) + _face_normal(f) * (size[axis] * 0.5),
				"size": slab}, _yaw)


func _rebuild() -> void:
	for b: Node in _boxes.values():
		b.queue_free()
	_boxes.clear()
	for w: Dictionary in windows:
		var t := box_transform({"center": _vec(w["center"]), "size": _vec(w["size"])}, float(w.get("yaw", 0.0)))
		if not bool(w.get("on", true)):
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Window_%s" % w["id"]
		mi.mesh = BoxMesh.new()
		mi.material_override = _mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.transform = t
		add_child(mi)
		_boxes[w["id"]] = mi
	changed.emit()


## The box's size along its own axes, then turned: Basis.scaled() would stretch along the room's axes instead, which
## swapped the sides of a box turned 90 degrees (a keyboard came out short side on, the user, 2026-11-06).
static func box_transform(box: Dictionary, yaw: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(box["size"]), box["center"])


## The way the viewer faces (tracking space), as a turn about up.
func _facing_yaw() -> float:
	var cam: Node3D = main.get("xr_camera") if main != null else null
	if cam == null:
		return 0.0
	return _yaw_of(global_transform.basis.inverse() * cam.global_transform.basis)


## A basis's forward (-Z) as a turn about up.
static func _yaw_of(b: Basis) -> float:
	var f := -b.z
	f.y = 0.0
	if f.length_squared() < 1e-6:
		return 0.0
	f = f.normalized()
	return atan2(-f.x, -f.z)


func _find(id: String) -> int:
	for i in windows.size():
		if windows[i]["id"] == id:
			return i
	return -1


# --- Kept --------------------------------------------------------------------------------------------------------------

func _load() -> void:
	windows = []
	if not FileAccess.file_exists(FILE):
		return
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
	if not (j is Dictionary) or not ((j as Dictionary).get("windows") is Array):
		return
	for w: Variant in j["windows"]:
		if w is Dictionary and (w as Dictionary).has_all(["id", "center", "size"]) and w["center"] is Array \
				and w["size"] is Array and (w["center"] as Array).size() == 3 and (w["size"] as Array).size() == 3:
			windows.append({"id": str(w["id"]), "name": str(w.get("name", "Area")), "center": w["center"],
					"size": w["size"], "yaw": float(w.get("yaw", 0.0)), "on": bool(w.get("on", true))})


func _save() -> void:
	var f := FileAccess.open(FILE, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"windows": windows}, " "))
	f.close()


func _new_id() -> String:
	return "%x" % (Time.get_unix_time_from_system() * 1000.0 + randi() % 1000)


func _next_number() -> int:
	var n := 1
	while windows.any(func(w: Dictionary) -> bool: return w["name"] == "Area %d" % n):
		n += 1
	return n


static func _v(p: Vector3) -> Array:
	return [snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)]


static func _vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
