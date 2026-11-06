extends Node3D

## Windows to the real room (the user, 2026-11-06: "mark an area in 3d space using the controller then track that and
## reveal it"; docs/features.md "Windows to the real room"). The viewer marks a real place (the coffee table, the arm
## of the sofa) by sweeping a controller over it with the trigger held; the app keeps an upright box round what was
## swept, fixed to the real room, and through it the headset's cameras show, in whatever room is on.
##
## Fixed to the real room: a window is kept in the runtime's own tracking space (the Stage reference space, set by the
## headset's room setup), not the scene's. This node's transform is XROrigin3D's times XRServer's reference frame each
## frame, so recentring the screen (which moves the reference frame) leaves the windows where the table is, and they
## are there again next time.
##
## Showing the cameras: while a window is on (or marking), the OpenXR environment blend mode is ALPHA_BLEND and the
## viewport keeps its alpha (as the passthrough room, environments/passthrough.gd, does for the whole view). A black
## backstop far out keeps everything else opaque (the room's gaps would show the cameras otherwise); each window draws
## shaders/real_window.gdshader, which takes the eye buffer's alpha down where it is. Off again (none on): opaque, as
## before. In the passthrough room it leaves the blend mode to that room.
##
## Marking: the whole view is the cameras (a window round the viewer), so the real things can be seen; the swept box
## shows tinted as it grows. The ray origin of the pointer controller (its tip) is sampled while the trigger is held;
## release adds the window. The box is upright, turned to the way the viewer faced when the sweep began, MARGIN round.
##
## The room light dims the cameras' view as in the passthrough room, but never under LIGHT_MIN: a window is there to
## find the cup in the dark.
##
##   windows                          [{id, name, center [x, y, z], size [w, h, d], yaw (radians), on}] (tracking space)
##   start_mark() -> bool             false without the cameras' view (no XR, no ALPHA_BLEND), unless `force`
##   sweep(on), add_point(p_scene)    the trigger held / released; a point (scene coordinates) while held
##   finish() -> window or {}         the swept box as a window (kept); cancel_mark()
##   set_on(id, on), remove(id) -> the window removed (for undo), restore(window), names()
##   status() -> String
## Kept in user://real_windows.json.

signal changed

const SHADER := preload("res://shaders/real_window.gdshader")
const FILE := "user://real_windows.json"
## Metres added round what was swept, and the least and most a side can be.
const MARGIN := 0.04
const MIN_SIDE := 0.08
const MAX_SIDE := 4.0
const MAX_WINDOWS := 16
## Samples closer than this to the last one are not kept.
const STEP := 0.01
const LIGHT_MIN := 0.4
const BACKSTOP_RADIUS := 900.0
const PREVIEW_COLOR := Color(0.35, 0.65, 1.0, 0.22)

var main: Node3D
## Builds and blend-mode handling without an XR session (tests).
var force := false
var windows: Array = []
var marking := false
var sweeping := false
var _points := PackedVector3Array()
var _yaw := 0.0
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
	_mat.render_priority = Material.RENDER_PRIORITY_MIN
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


# --- Marking ---------------------------------------------------------------------------------------------------------

func start_mark() -> bool:
	if not available() or windows.size() >= MAX_WINDOWS:
		return false
	marking = true
	sweeping = false
	_points.clear()
	_preview.visible = false
	_full.visible = true
	return true


func sweep(on: bool) -> void:
	if not marking:
		return
	if on and not sweeping:
		_yaw = _facing_yaw()
	sweeping = on


## A point the controller's tip passed, in scene coordinates.
func add_point(p: Vector3) -> void:
	if not (marking and sweeping):
		return
	var raw := global_transform.affine_inverse() * p
	if not _points.is_empty() and _points[-1].distance_to(raw) < STEP:
		return
	_points.append(raw)
	var box := box_of(_points, _yaw)
	_preview.transform = _box_transform(box)
	_preview.visible = true


## The swept box as a window, kept and shown; {} when nothing was swept.
func finish() -> Dictionary:
	if not marking:
		return {}
	var w := {}
	if not _points.is_empty():
		var box := box_of(_points, _yaw)
		w = {"id": _new_id(), "name": "Area %d" % _next_number(), "center": _v(box["center"]),
				"size": _v(box["size"]), "yaw": snappedf(_yaw, 0.0001), "on": true}
		windows.append(w)
		_save()
	cancel_mark()
	_rebuild()
	return w


func cancel_mark() -> void:
	marking = false
	sweeping = false
	_points.clear()
	if _preview != null:
		_preview.visible = false
	if _full != null:
		_full.visible = false


## An upright box round `points` (tracking space), turned by yaw, MARGIN round, each side within MIN_SIDE..MAX_SIDE:
## {center: Vector3, size: Vector3}.
static func box_of(points: PackedVector3Array, yaw: float) -> Dictionary:
	var turn := Basis(Vector3.UP, -yaw)
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for p in points:
		var q := turn * p
		lo = lo.min(q)
		hi = hi.max(q)
	var size := (hi - lo + Vector3.ONE * MARGIN * 2.0).clamp(Vector3.ONE * MIN_SIDE, Vector3.ONE * MAX_SIDE)
	var center := Basis(Vector3.UP, yaw) * ((lo + hi) * 0.5)
	return {"center": center, "size": size}


# --- The windows -----------------------------------------------------------------------------------------------------

func set_on(id: String, on: bool) -> void:
	for w: Dictionary in windows:
		if w["id"] == id:
			w["on"] = on
	_save()
	_rebuild()


func remove(id: String) -> Dictionary:
	for i in windows.size():
		if windows[i]["id"] == id:
			var w: Dictionary = windows[i]
			windows.remove_at(i)
			_save()
			_rebuild()
			return w
	return {}


func restore(w: Dictionary) -> void:
	if w.is_empty() or windows.any(func(o: Dictionary) -> bool: return o["id"] == w["id"]):
		return
	windows.append(w)
	_save()
	_rebuild()


func any_on() -> bool:
	return windows.any(func(w: Dictionary) -> bool: return bool(w.get("on", true)))


func status() -> String:
	if not available():
		return "The headset's cameras can't show here."
	var n := windows.filter(func(w: Dictionary) -> bool: return bool(w.get("on", true))).size()
	if windows.is_empty():
		return "None marked."
	return "%d of %d on." % [n, windows.size()]


# --- Each frame ------------------------------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if main == null:
		return
	var origin: Node3D = main.get("xr_origin")
	var frame := XRServer.get_reference_frame() if (main.get("use_xr") == true or force) else Transform3D()
	global_transform = (origin.global_transform if origin != null else Transform3D()) * frame
	var light := LIGHT_MIN
	var rl: Node = main.get("features").get("room_light") if main.get("features") != null else null
	if rl != null and rl.has_method("effective"):
		light = clampf(float(rl.effective()), LIGHT_MIN, 1.0)
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

	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.albedo_color = PREVIEW_COLOR
	pm.no_depth_test = true
	pm.cull_mode = BaseMaterial3D.CULL_DISABLED
	pm.render_priority = Material.RENDER_PRIORITY_MIN + 1
	_preview = MeshInstance3D.new()
	_preview.name = "MarkPreview"
	_preview.mesh = BoxMesh.new()
	_preview.material_override = pm
	_preview.visible = false
	_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_preview)

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


func _rebuild() -> void:
	for b: Node in _boxes.values():
		b.queue_free()
	_boxes.clear()
	for w: Dictionary in windows:
		if not bool(w.get("on", true)):
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Window_%s" % w["id"]
		mi.mesh = BoxMesh.new()
		mi.material_override = _mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.transform = _box_transform({"center": _vec(w["center"]), "size": _vec(w["size"])}, float(w.get("yaw", 0.0)))
		add_child(mi)
		_boxes[w["id"]] = mi
	changed.emit()


## The box's size along its own axes, then turned: Basis.scaled() would stretch along the room's axes instead, which
## swapped the sides of a box turned 90 degrees (a keyboard came out short side on, the user, 2026-11-06).
static func box_transform(box: Dictionary, yaw: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(box["size"]), box["center"])


func _box_transform(box: Dictionary, yaw := NAN) -> Transform3D:
	return box_transform(box, _yaw if is_nan(yaw) else yaw)


## The way the viewer faces (tracking space), as a turn about up.
func _facing_yaw() -> float:
	var cam: Node3D = main.get("xr_camera") if main != null else null
	if cam == null:
		return 0.0
	var f := global_transform.basis.inverse() * -cam.global_transform.basis.z
	f.y = 0.0
	if f.length_squared() < 1e-6:
		return 0.0
	f = f.normalized()
	return atan2(-f.x, -f.z)


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
