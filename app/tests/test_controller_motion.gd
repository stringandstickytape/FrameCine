extends SceneTree

## Our controller model's moving parts (scripts/xr/controller_visual.gd, pose_inputs()): the trigger turns back, the
## stick tilts the way it is pushed and sinks on a click, buttons sink, the grip moves in, and all go back at rest.
##
##   godot --headless --xr-mode off --path app --script res://tests/test_controller_motion.gd

const ControllerVisual := preload("res://scripts/xr/controller_visual.gd")
const N := Vector3(0.0, 0.766, -0.643)
const F := Vector3(0.0, -0.643, -0.766)

var _failures := 0
var _checks := 0


func _initialize() -> void:
	for side in ["right", "left"]:
		var v := ControllerVisual.new()
		v.configure(side)
		root.add_child(v)
		await process_frame
		if not v.use_our_model():
			_check("%s: our model loads" % side, false)
			continue
		var parts := v.moving_parts()
		_check("%s: moving parts %s" % [side, parts], parts.get("trigger") == "trigger" and parts.get("thumbstick") == "stick"
				and parts.get("button_grip") == "grip")
		v.set_input_bindings([["a", "next_file", false], ["menu", "menu", false], ["view", "overlay", false],
				["thumbstick", "menu", true]])
		var trigger := _centre(v, "trigger")
		var stick := _top(v, "thumbstick")
		var grip := _centre(v, "button_grip")
		v.pose_inputs({"trigger": 1.0})
		var moved := _centre(v, "trigger") - trigger
		_check("%s: a full trigger pull moves it back (%.1f mm toward the grip)" % [side, -moved.dot(F) * 1000.0],
				moved.dot(F) < -0.001)
		v.pose_inputs({"thumbstick": Vector2(1, 0)})
		var tilt := _top(v, "thumbstick") - stick
		_check("%s: stick right tilts its top to +X (%.1f mm)" % [side, tilt.x * 1000.0], tilt.x > 0.002)
		v.pose_inputs({"thumbstick": Vector2(0, 1)})
		tilt = _top(v, "thumbstick") - stick
		_check("%s: stick up tilts its top forward (%.1f mm)" % [side, tilt.dot(F) * 1000.0], tilt.dot(F) > 0.002)
		v.pose_inputs({"stick_click": true})
		_check("%s: a stick click sinks it" % side, (_top(v, "thumbstick") - stick).dot(N) < -0.0005)
		v.pose_inputs({"squeeze": 1.0})
		_check("%s: the squeeze moves the grip button" % side, (_centre(v, "button_grip") - grip).length() > 0.001)
		var button := "button_a" if side == "right" else "button_view"
		var input := "a" if side == "right" else "view"
		var at := _centre(v, button)
		v.pose_inputs({"pressed": {input: true}})
		_check("%s: a press sinks %s" % [side, button], (_centre(v, button) - at).dot(N) < -0.001)
		v.pose_inputs({})
		_check("%s: at rest everything is back" % side, _centre(v, "trigger").is_equal_approx(trigger)
				and _top(v, "thumbstick").is_equal_approx(stick) and _centre(v, button).is_equal_approx(at))
		v.queue_free()
	print("Controller motion test: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _part(v: Node, part: String) -> MeshInstance3D:
	for mi: MeshInstance3D in v.find_children(part, "MeshInstance3D", true, false):
		return mi
	return null


## The part's mesh centre in the model's space.
func _centre(v: Node, part: String) -> Vector3:
	var mi := _part(v, part)
	return v._in_model(mi) * mi.mesh.get_aabb().get_center() if mi != null else Vector3.ZERO


## The point of the part's bounds furthest along the face normal (the stick's top).
func _top(v: Node, part: String) -> Vector3:
	var mi := _part(v, part)
	if mi == null:
		return Vector3.ZERO
	var aabb := mi.mesh.get_aabb()
	var t: Transform3D = v._in_model(mi)
	var c := aabb.get_center()
	return t * (c + N * (aabb.size.length() * 0.5))


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", what])
