extends Node3D

## Eye gaze (XR_EXT_eye_gaze_interaction; the action map's eye_gaze_pose on /user/eyes_ext): where the viewer looks,
## corrected by a personal calibration, and two tools for it.
##
## Measured on the Frame (2026-11-01, nine dots at 2 m, +-15 x +-10 degrees, uncalibrated): every reading at high
## confidence, a median error of 1.8 degrees (0.45 to 3.9), each dot off in its own direction by up to 2 degrees, and
## about 0.5 degrees of jitter while holding a look. A per-viewer fit removes most of the direction-dependent error.
##
## Calibration (calibrate()): CAL_POINTS dots appear one at a time CAL_DISTANCE ahead, fixed in the room where the head
## faced at the start. The pip shows where the gaze reads now (with the calibration so far); the viewer looks at the
## dot and, if the pip isn't where they look, moves it there with the pointer hand's thumbstick (the user's idea: they
## can see where it is off each time), then pulls the trigger on either controller. What counts as true is where the
## pip was put: the dot is only somewhere to look. The nudge carries over to the next dot (the error is much alike from
## one to the next). The gaze over the last HOLD_MSEC before the pull is averaged; a look that moved more than
## HOLD_SPREAD_DEG in that time is refused (a buzz) and the dot stays. All of it is yaw and pitch from the head at that
## moment, so the head may move. A least-squares fit maps raw yaw / pitch to true (affine: an offset, a scale and a shear per axis) and is
## kept in [gaze] calibration. While it runs the trigger belongs to it (main's trigger handler is disconnected and put
## back after: play / pause doesn't fire), and so does the stick (ui_layer.on_stick() gives it up: no seeking).
##
## The pip (set_pip(on)): a small dot where the calibrated gaze meets the scene: the screen, the panel, the card,
## anything with a collider, the floor, else PIP_FAR metres out. Smoothed over PIP_SMOOTH seconds.
##
##   available() -> bool                       the runtime gives a gaze pose with tracking data now
##   raw_ray() -> [origin, dir] or []          world space, as the runtime gives it
##   ray() -> [origin, dir] or []              with the calibration applied
##   calibrated() -> bool, calibrate(), cancel_calibration(), calibrating
##   set_pip(on), pip
##   status() -> {available, calibrated, residual_deg, before_deg, points, calibrating, pip}
## Commands (dev registry): gaze_status (read), gaze_calibrate (control), gaze_pip {on} (control).
## Settings: [gaze] calibration (6 floats: yaw = a0 + a1 * yaw + a2 * pitch, pitch = b0 + b1 * yaw + b2 * pitch, in
## degrees), residual_deg, before_deg, points, calibrated_at.

const DevCommands := preload("res://scripts/dev/dev_commands.gd")

const TRACKER := "/user/eyes_ext"
const POSE := "eye_gaze_pose"
const CAL_DISTANCE := 2.0
## Yaw, pitch (degrees, from the head at the start): the centre, an outer ring that covers a near screen, an inner one.
const CAL_POINTS: Array[Vector2] = [Vector2(0, 0), Vector2(-25, 15), Vector2(0, 15), Vector2(25, 15), Vector2(25, 0),
		Vector2(25, -15), Vector2(0, -15), Vector2(-25, -15), Vector2(-25, 0), Vector2(-12, 8), Vector2(12, 8),
		Vector2(12, -8), Vector2(-12, -8)]
const HOLD_MSEC := 300
const HOLD_SPREAD_DEG := 1.5
const DOT_DEG := 1.0
const PIP_DEG := 0.6
const PIP_SMOOTH := 0.05
const PIP_FAR := 3.0
## The calibration's nudge: degrees a second at full stick (squared, for fine moves near the centre), and the dead zone.
const NUDGE_RATE := 5.0
const NUDGE_DEAD := 0.12

var main: Node3D
var calibrating := false
var pip := false
## [msec, yaw, pitch] of the raw gaze, head-relative, for the last second.
var _recent: Array = []
var _coef := PackedFloat32Array()
var _pip_node: MeshInstance3D
var _pip_dir := Vector3.ZERO
var _cal_holder: Node3D
var _cal_index := 0
var _cal_raw: Array = []
var _cal_true: Array = []
var _cal_basis := Basis()
var _cal_origin := Vector3.ZERO
var _taken_triggers: Array = []
var _dot_mat: StandardMaterial3D
var _hot_mat: StandardMaterial3D
## The calibration's nudge (yaw, pitch degrees) added to the pip.
var _nudge := Vector2.ZERO
## The calibration's instructions, under the dots (on the card alone the user didn't see them: they look at the dots).
var _cal_label: Label3D


func _ready() -> void:
	var saved: Variant = main.settings.get_value("gaze", "calibration", [])
	if saved is Array and (saved as Array).size() == 6 or saved is PackedFloat32Array and saved.size() == 6:
		_coef = PackedFloat32Array(saved)
	_dot_mat = _unlit(Color(0.4, 0.4, 0.4))
	_hot_mat = _unlit(Color(1.0, 0.85, 0.0))
	register_commands()


func _exit_tree() -> void:
	_give_back_triggers()


static func _unlit(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.no_depth_test = true
	m.render_priority = 10
	return m


func available() -> bool:
	return not raw_ray().is_empty()


func raw_ray() -> Array:
	var tracker := XRServer.get_tracker(TRACKER) as XRPositionalTracker
	var p: XRPose = tracker.get_pose(POSE) if tracker != null else null
	if p == null or not p.has_tracking_data:
		return []
	var origin: Node3D = main.get_node_or_null("XROrigin3D")
	var g: Transform3D = (origin.global_transform if origin != null else Transform3D()) * p.get_adjusted_transform()
	return [g.origin, -g.basis.z.normalized()]


func calibrated() -> bool:
	return _coef.size() == 6


func ray() -> Array:
	var r := raw_ray()
	if r.is_empty() or not calibrated():
		return r
	var hb: Basis = main.camera.global_transform.basis
	var yp := _yaw_pitch(hb, r[1])
	return [r[0], _dir(hb, _apply(yp))]


func _apply(yp: Vector2) -> Vector2:
	return Vector2(_coef[0] + _coef[1] * yp.x + _coef[2] * yp.y, _coef[3] + _coef[4] * yp.x + _coef[5] * yp.y)


## Yaw (right positive) and pitch (up positive) of a world direction from a head basis, degrees.
static func _yaw_pitch(hb: Basis, dir: Vector3) -> Vector2:
	var l := hb.inverse() * dir.normalized()
	return Vector2(rad_to_deg(atan2(l.x, -l.z)), rad_to_deg(asin(clampf(l.y, -1.0, 1.0))))


static func _dir(hb: Basis, yp: Vector2) -> Vector3:
	var y := deg_to_rad(yp.x)
	var p := deg_to_rad(yp.y)
	return (hb * Vector3(sin(y) * cos(p), sin(p), -cos(y) * cos(p))).normalized()


func _process(delta: float) -> void:
	var r := raw_ray()
	var now := Time.get_ticks_msec()
	if not r.is_empty():
		var yp := _yaw_pitch(main.camera.global_transform.basis, r[1])
		_recent.append([now, yp.x, yp.y])
	while not _recent.is_empty() and now - int(_recent[0][0]) > 1000:
		_recent.pop_front()
	if calibrating:
		_update_nudge(delta)
	_update_pip(delta)


func _update_nudge(delta: float) -> void:
	var hand: XRController3D = main.ui.pointer_hand if main.get("ui") != null else null
	if hand == null or not hand.has_method("get_stick"):
		return
	var s: Vector2 = hand.call("get_stick")
	if s.length() < NUDGE_DEAD:
		return
	s = s * s.length()
	_nudge += Vector2(s.x, s.y) * NUDGE_RATE * delta


## Where the pip says the viewer looks, yaw / pitch from the head: the raw gaze, the calibration so far, the nudge.
func _pip_yp(raw_yp: Vector2) -> Vector2:
	return (_apply(raw_yp) if calibrated() else raw_yp) + (_nudge if calibrating else Vector2.ZERO)


# --- Calibration ------------------------------------------------------------------------------------------------

func calibrate() -> void:
	if calibrating:
		return
	if not available():
		_say("Eye gaze isn't available right now.", 6.0)
		return
	calibrating = true
	var head: Transform3D = main.camera.global_transform
	var fwd := -head.basis.z
	fwd.y = 0.0
	_cal_basis = Basis.looking_at(fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD, Vector3.UP)
	_cal_origin = head.origin
	_cal_holder = Node3D.new()
	_cal_holder.name = "GazeCalibration"
	add_child(_cal_holder)
	var mesh := SphereMesh.new()
	mesh.radius = CAL_DISTANCE * tan(deg_to_rad(DOT_DEG * 0.5))
	mesh.height = mesh.radius * 2.0
	for a in CAL_POINTS:
		var d := MeshInstance3D.new()
		d.mesh = mesh
		d.material_override = _dot_mat
		_cal_holder.add_child(d)
		d.global_position = _cal_origin + _dir(_cal_basis, a) * CAL_DISTANCE
	_cal_index = 0
	_cal_raw.clear()
	_cal_true.clear()
	_nudge = Vector2.ZERO
	_cal_label = Label3D.new()
	_cal_label.font_size = 40
	_cal_label.pixel_size = CAL_DISTANCE * tan(deg_to_rad(0.6)) / 40.0  # 40 px text 0.6 degrees tall
	_cal_label.width = 1400.0
	_cal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cal_label.no_depth_test = true
	_cal_label.render_priority = 10
	_cal_label.outline_size = 8
	_cal_holder.add_child(_cal_label)
	_cal_label.global_transform = Transform3D(_cal_basis, _cal_origin + _dir(_cal_basis, Vector2(0, -21)) * CAL_DISTANCE)
	_take_triggers()
	_show_pip_node(true)
	_show_dot()


func cancel_calibration() -> void:
	if not calibrating:
		return
	_end_calibration()
	_say("Eye calibration cancelled; the old one stays.", 6.0)


func _show_dot() -> void:
	for i in _cal_holder.get_child_count():
		var d := _cal_holder.get_child(i) as MeshInstance3D
		d.material_override = _hot_mat if i == _cal_index else _dot_mat
		d.scale = Vector3.ONE * (1.6 if i == _cal_index else 0.6)
	_instruct(("Look at the yellow dot. If the red pip isn't where you're looking, move it there with the thumbstick, "
			+ "then pull the trigger (%d of %d). Menu cancels.") % [_cal_index + 1, CAL_POINTS.size()])


func _on_cal_trigger(hand: XRController3D, pressed: bool) -> void:
	if not pressed or not calibrating:
		return
	var now := Time.get_ticks_msec()
	var ys: Array[float] = []
	var ps: Array[float] = []
	for s in _recent:
		if now - int(s[0]) <= HOLD_MSEC:
			ys.append(float(s[1]))
			ps.append(float(s[2]))
	if ys.size() < 5 or _spread(ys) > HOLD_SPREAD_DEG or _spread(ps) > HOLD_SPREAD_DEG:
		if hand.has_method("pulse"):
			hand.call("pulse")
		_instruct("Hold your eyes on the dot, then pull the trigger (%d of %d)." % [_cal_index + 1, CAL_POINTS.size()])
		return
	var raw := Vector2(_mean(ys), _mean(ps))
	_cal_raw.append(raw)
	_cal_true.append(_pip_yp(raw))
	_cal_index += 1
	if _cal_index < CAL_POINTS.size():
		_show_dot()
	else:
		_finish()


static func _mean(a: Array[float]) -> float:
	var s := 0.0
	for v in a:
		s += v
	return s / maxf(a.size(), 1)


static func _spread(a: Array[float]) -> float:
	var lo := INF
	var hi := -INF
	for v in a:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	return hi - lo


func _finish() -> void:
	var coef := fit(_cal_raw, _cal_true)
	var before := 0.0
	var after := 0.0
	for i in _cal_raw.size():
		var raw: Vector2 = _cal_raw[i]
		var want: Vector2 = _cal_true[i]
		before += raw.distance_to(want)
		var got := Vector2(coef[0] + coef[1] * raw.x + coef[2] * raw.y, coef[3] + coef[4] * raw.x + coef[5] * raw.y)
		after += got.distance_to(want)
	before /= _cal_raw.size()
	after /= _cal_raw.size()
	_coef = coef
	main.settings.set_value("gaze", "calibration", Array(coef))
	main.settings.set_value("gaze", "residual_deg", snappedf(after, 0.01))
	main.settings.set_value("gaze", "before_deg", snappedf(before, 0.01))
	main.settings.set_value("gaze", "points", _cal_raw.size())
	main.settings.set_value("gaze", "calibrated_at", Time.get_datetime_string_from_system())
	print("Gaze: calibrated on %d points; average error %.2f degrees before, %.2f after" % [_cal_raw.size(), before,
			after])
	_end_calibration()
	_say("Eye calibration done: average error %.1f degrees before, %.1f after." % [before, after], 12.0)


## Least squares: true = c0 + c1 * raw.x + c2 * raw.y for each axis. [a0, a1, a2, b0, b1, b2]; identity if singular.
static func fit(raw: Array, truth: Array) -> PackedFloat32Array:
	var xtx := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
	var xty := Vector3.ZERO
	var xtp := Vector3.ZERO
	for i in raw.size():
		var r: Vector2 = raw[i]
		var t: Vector2 = truth[i]
		var row := [1.0, r.x, r.y]
		for a in 3:
			for b in 3:
				xtx[a][b] += row[a] * row[b]
		xty += Vector3(row[0], row[1], row[2]) * t.x
		xtp += Vector3(row[0], row[1], row[2]) * t.y
	var m := Basis(Vector3(xtx[0][0], xtx[1][0], xtx[2][0]), Vector3(xtx[0][1], xtx[1][1], xtx[2][1]),
			Vector3(xtx[0][2], xtx[1][2], xtx[2][2]))
	if absf(m.determinant()) < 1e-6:
		return PackedFloat32Array([0, 1, 0, 0, 0, 1])
	var inv := m.inverse()
	var a := inv * xty
	var b := inv * xtp
	return PackedFloat32Array([a.x, a.y, a.z, b.x, b.y, b.z])


func _end_calibration() -> void:
	calibrating = false
	_nudge = Vector2.ZERO
	_show_pip_node(pip)
	if is_instance_valid(_cal_holder):
		_cal_holder.queue_free()
	_cal_holder = null
	_give_back_triggers()


## The trigger is the calibration's while it runs: main's handler off, ours on; the menu button cancels.
func _take_triggers() -> void:
	for hand in [main.get("left_hand"), main.get("right_hand")]:
		if hand == null:
			continue
		var h := hand as XRController3D
		if h.has_signal("trigger_changed"):
			if main.has_method("_on_trigger") and h.trigger_changed.is_connected(main._on_trigger):
				h.trigger_changed.disconnect(main._on_trigger)
				_taken_triggers.append(h)
			if not h.trigger_changed.is_connected(_on_cal_trigger):
				h.trigger_changed.connect(_on_cal_trigger)
		if h.has_signal("menu_pressed") and not h.menu_pressed.is_connected(_on_cal_menu):
			h.menu_pressed.connect(_on_cal_menu)


func _give_back_triggers() -> void:
	for hand in [main.get("left_hand"), main.get("right_hand")] if main != null else []:
		if hand == null:
			continue
		var h := hand as XRController3D
		if h.has_signal("trigger_changed") and h.trigger_changed.is_connected(_on_cal_trigger):
			h.trigger_changed.disconnect(_on_cal_trigger)
		if h.has_signal("menu_pressed") and h.menu_pressed.is_connected(_on_cal_menu):
			h.menu_pressed.disconnect(_on_cal_menu)
	for h: XRController3D in _taken_triggers:
		if is_instance_valid(h) and not h.trigger_changed.is_connected(main._on_trigger):
			h.trigger_changed.connect(main._on_trigger)
	_taken_triggers.clear()


func _on_cal_menu(_hand: XRController3D) -> void:
	cancel_calibration.call_deferred()


## Under the dots and on the card.
func _instruct(text: String) -> void:
	if is_instance_valid(_cal_label):
		_cal_label.text = text
	_say(text, 0.0)


func _say(text: String, seconds: float) -> void:
	var ui: Node = main.get("ui")
	if ui != null and ui.get("card") != null:
		ui.card.show_card({"text": text, "title": "Eye gaze", "seconds": seconds, "id": "gaze"})


# --- Pip --------------------------------------------------------------------------------------------------------

func set_pip(on: bool) -> void:
	pip = on
	_show_pip_node(on or calibrating)


func _show_pip_node(on: bool) -> void:
	if on and _pip_node == null:
		_pip_node = MeshInstance3D.new()
		_pip_node.name = "GazePip"
		var mesh := SphereMesh.new()
		mesh.radius = 0.5
		mesh.height = 1.0
		_pip_node.mesh = mesh
		var m := _unlit(Color(1.0, 0.25, 0.1))
		m.render_priority = 11  # over the calibration's dots
		_pip_node.material_override = m
		_pip_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_pip_node)
	if _pip_node != null:
		_pip_node.visible = on
	_pip_dir = Vector3.ZERO


func _update_pip(delta: float) -> void:
	if not (pip or calibrating) or _pip_node == null:
		return
	var r := raw_ray()
	if r.is_empty():
		_pip_node.visible = false
		return
	var hb: Basis = main.camera.global_transform.basis
	var dir: Vector3 = _dir(hb, _pip_yp(_yaw_pitch(hb, r[1])))
	_pip_dir = dir if _pip_dir == Vector3.ZERO else _pip_dir.slerp(dir, 1.0 - exp(-delta / PIP_SMOOTH)).normalized()
	var origin: Vector3 = r[0]
	# On the dots' sphere while calibrating, so the pip and the dot are seen at one depth.
	var dist := CAL_DISTANCE if calibrating else hit_distance(origin, _pip_dir)
	_pip_node.visible = true
	_pip_node.global_position = origin + _pip_dir * dist
	_pip_node.scale = Vector3.ONE * 2.0 * dist * tan(deg_to_rad(PIP_DEG * 0.5))


## How far along the ray the scene is: the nearest of the screen, the panel, the card, a collider, the floor.
func hit_distance(origin: Vector3, dir: Vector3) -> float:
	var best := PIP_FAR
	var screen: Node3D = main.get("screen")
	if screen != null and screen.is_visible_in_tree() and screen.has_method("get_flat_size"):
		var inv := screen.global_transform.affine_inverse()
		var lo := inv * origin
		var ld := inv.basis * dir
		if absf(ld.z) > 1e-5:
			var t := -lo.z / ld.z
			var p := lo + ld * t
			var size: Vector2 = screen.get_flat_size()
			if t > 0.0 and absf(p.x) <= size.x * 0.5 and absf(p.y) <= size.y * 0.5:
				best = minf(best, (screen.global_transform * p).distance_to(origin))
	var ui: Node = main.get("ui")
	if ui != null:
		for node: Variant in [ui.get("panel"), ui.get("card")]:
			if node != null and node.has_method("ray_hit"):
				var h: Dictionary = node.ray_hit(origin, dir)
				if h.has("distance"):
					best = minf(best, float(h["distance"]))
	var space := get_world_3d().direct_space_state if get_world_3d() != null else null
	if space != null:
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * best)
		var hit := space.intersect_ray(q)
		if hit.has("position"):
			best = minf(best, (hit["position"] as Vector3).distance_to(origin))
	if dir.y < -1e-3:
		var floor_y: float = (main.get_node("XROrigin3D") as Node3D).global_position.y \
				if main.has_node("XROrigin3D") else 0.0
		var t := (floor_y - origin.y) / dir.y
		if t > 0.0:
			best = minf(best, t)
	return best


# --- Status and commands ----------------------------------------------------------------------------------------

func status() -> Dictionary:
	return {"available": available(), "calibrated": calibrated(), "calibrating": calibrating, "pip": pip,
			"residual_deg": main.settings.get_value("gaze", "residual_deg", -1.0)
					if main.settings.has_value("gaze", "residual_deg") else null,
			"before_deg": main.settings.get_value("gaze", "before_deg", -1.0)
					if main.settings.has_value("gaze", "before_deg") else null,
			"points": main.settings.get_value("gaze", "points", 0)}


func register_commands() -> void:
	DevCommands.register("gaze_status", func(_args: Dictionary, _ctx: DevCommands.Call) -> Variant:
		return status(), {"description": "Eye gaze: available, calibrated (and its errors), calibrating, pip shown.",
		"returns": "{available, calibrated, calibrating, pip, residual_deg, before_deg, points}", "assistant": "read"})
	DevCommands.register("gaze_calibrate", func(_args: Dictionary, ctx: DevCommands.Call) -> Variant:
		if not available():
			return ctx.fail("no eye gaze from the headset now")
		calibrate()
		ctx.summary = "eye calibration"
		return status(), {"level": "control", "assistant": "control",
		"description": "Starts the eye calibration in the headset: the viewer looks at each dot and pulls the trigger "
				+ "(the menu button cancels)."})
	DevCommands.register("gaze_pip", func(args: Dictionary, ctx: DevCommands.Call) -> Variant:
		var was := pip
		set_pip(bool(args.get("on", true)))
		ctx.summary = "gaze dot %s" % ("on" if pip else "off")
		ctx.undo = func() -> void: set_pip(was)
		return status(), {"level": "control", "description": "Shows or hides a small dot where the viewer looks.",
		"params": [{"name": "on", "type": "bool", "default": true,
				"description": "Shows the dot (true) or hides it (false)."}], "assistant": "control"})
