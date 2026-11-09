extends XRController3D

## One controller. Posed at the aim pose: the action map's "aim_pose" action, which the engine's XR interface puts on
## the tracker under the name "aim" (and "grip_pose" under "grip"), so `pose` must be "aim"; with "aim_pose" the
## node never becomes active. The laser points along -Z. Reads the app's action map (xr/openxr_action_map.tres):
## trigger and squeeze as floats with hysteresis, the thumbstick, the menu, overlay, next_file, prev_file, agent and enter buttons;
## draws the menu laser and its hit dot when told to. main.gd and the UI layer decide what the inputs do.
## Button input does not depend on the pose: a controller whose pose isn't tracked still plays / pauses.
## The controller itself, with its input labels, is `visual` (controller_visual.gd): the runtime's render model when
## setup_render_model() finds the extension active, else a hand-built mesh shaped like the headset's controller.
##
## Diagnostics (always): the interaction profile the runtime bound for this hand, and when the aim pose becomes
## available / tracked. With `verbose` (--debug or --verbose-input): every button, trigger, squeeze and stick change.

signal trigger_changed(hand: XRController3D, pressed: bool)
signal grip_changed(hand: XRController3D, pressed: bool)
signal menu_pressed(hand: XRController3D)
## The menu button let go (a hold of it recentres the panel, ui/ui_layer.gd).
signal menu_released(hand: XRController3D)
## The stick click (headset profile: the right one) pressed or let go: main.gd lets the picture keeper have it on an
## image in the browser (scripts/pictures/picture_keeper.gd), else it is the menu.
signal stick_clicked(hand: XRController3D, pressed: bool)
signal overlay_pressed(hand: XRController3D)
signal next_pressed(hand: XRController3D)
signal prev_pressed(hand: XRController3D)
## The "labels" button (headset profile: bumper) pressed / released.
signal labels_held(hand: XRController3D, held: bool)
## The "agent" button (headset profile: Y, on the right controller).
signal agent_pressed(hand: XRController3D)
## The "enter" button (headset profile: X, on the right controller): Enter in the agent's terminal while it shows.
signal enter_pressed(hand: XRController3D)
## The runtime bound another interaction profile for this hand ("": none).
signal bound_profile_changed(hand: XRController3D, profile: String)
## Tracking started for the first time, or again after a gap of more than RETRACK_SECONDS.
signal tracking_started(hand: XRController3D)

const PRESS := 0.6
const RELEASE := 0.4
const LASER_COLOR := Color(0.35, 0.65, 1.0)
const LASER_HIT_COLOR := Color(1.0, 1.0, 1.0)
const STUB_COLOR := Color(0.55, 0.75, 1.0)
## The always-visible pointer stub from the aim pose (menu hidden), metres.
const STUB_LENGTH := 0.15
const BEAM_WIDTH := 0.004
const RETRACK_SECONDS := 3.0
const ControllerVisual := preload("res://scripts/xr/controller_visual.gd")
## Tracker name of the action map's "aim_pose" action.
const AIM_POSE := &"aim"
const NO_PROFILE_WARNING_MSEC := 5000

var trigger_down := false
var grip_down := false
## Print every input change.
var verbose := false
var _laser: MeshInstance3D
var _dot: MeshInstance3D
var _laser_mat: StandardMaterial3D
var _dot_mat: StandardMaterial3D
var _laser_on := false
var _laser_hit := false
var _laser_length := STUB_LENGTH
## The controller and its labels (a child of this node, in aim-pose space).
var visual: ControllerVisual
## The interaction profile the runtime bound for this hand ("": none yet).
var profile := ""
var _profile := "?"
var _lost_msec := -1
var _active := false
var _tracking := false
var _stick_out := false
var _no_profile_warned := false
## Ticks (ms) when the XR session became focused, or -1 (set by main.gd).
var focused_msec := -1


func _ready() -> void:
	pose = AIM_POSE
	# Hidden while the runtime has no pose for this hand (and on a desktop): no stray laser at the origin.
	show_when_tracked = true
	button_pressed.connect(_on_button_pressed)
	button_released.connect(func(action: String) -> void:
		if verbose:
			print("XR %s: %s released" % [tracker, action])
		if action == "labels":
			labels_held.emit(self, false)
		elif action == "menu":
			menu_released.emit(self)
		elif action == "stick_click":
			stick_clicked.emit(self, false))
	_laser_mat = StandardMaterial3D.new()
	_laser_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_laser_mat.albedo_color = STUB_COLOR
	var beam := BoxMesh.new()
	beam.size = Vector3(BEAM_WIDTH, BEAM_WIDTH, 1.0)
	_laser = MeshInstance3D.new()
	_laser.name = "Laser"
	_laser.mesh = beam
	_laser.material_override = _laser_mat
	_laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_laser.scale = Vector3(1, 1, STUB_LENGTH)
	_laser.position = Vector3(0, 0, -STUB_LENGTH * 0.5)
	_laser.visible = false
	add_child(_laser)
	_dot_mat = StandardMaterial3D.new()
	_dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dot_mat.albedo_color = LASER_HIT_COLOR
	var dot := SphereMesh.new()
	dot.radius = 0.006
	dot.height = 0.012
	dot.radial_segments = 8
	dot.rings = 4
	_dot = MeshInstance3D.new()
	_dot.name = "Dot"
	_dot.mesh = dot
	_dot.material_override = _dot_mat
	_dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dot.visible = false
	add_child(_dot)
	visual = ControllerVisual.new()
	visual.name = "Visual"
	visual.configure("left" if tracker == &"left_hand" else "right")
	add_child(visual)


func _process(_delta: float) -> void:
	if not get_viewport().use_xr:
		return
	_report_state()
	var t := get_float(&"trigger")
	if not trigger_down and t > PRESS:
		trigger_down = true
		_log("trigger pressed (%.2f)" % t)
		trigger_changed.emit(self, true)
	elif trigger_down and t < RELEASE:
		trigger_down = false
		_log("trigger released")
		trigger_changed.emit(self, false)
	var g := get_float(&"squeeze")
	if not grip_down and g > PRESS:
		grip_down = true
		_log("squeeze pressed (%.2f)" % g)
		grip_changed.emit(self, true)
	elif grip_down and g < RELEASE:
		grip_down = false
		_log("squeeze released")
		grip_changed.emit(self, false)
	var s := get_stick()
	if not _stick_out and s.length() > 0.5:
		_stick_out = true
		_log("thumbstick %s" % s)
	elif _stick_out and s.length() < 0.3:
		_stick_out = false
		_log("thumbstick centred")
	# Our controller model moves its trigger, grip, stick and buttons from the same actions.
	if visual.uses_our_model():
		visual.animate_from(self)


func _log(text: String) -> void:
	if verbose:
		print("XR %s: %s" % [tracker, text])


## Prints what the runtime bound for this hand, once per change.
func _report_state() -> void:
	var t := XRServer.get_tracker(tracker) as XRPositionalTracker
	var bound := t.profile if t != null else ""
	if bound != _profile:
		_profile = bound
		profile = "" if bound == "/interaction_profiles/none" else bound
		# Same wording as the engine's own --verbose line.
		print("XR %s: Interaction profile for /user/hand/%s changed to %s" % [tracker,
				"left" if tracker == &"left_hand" else "right", bound if t != null else "(no tracker)"])
		bound_profile_changed.emit(self, profile)
	# The runtime binds a profile only once the session is focused (headset worn), so wait from then.
	if not _no_profile_warned and focused_msec >= 0 and Time.get_ticks_msec() - focused_msec > NO_PROFILE_WARNING_MSEC \
			and profile == "":
		_no_profile_warned = true
		print("XR %s: no interaction profile bound %d s after focus: the runtime accepted none of the action map's profiles for this hand" % [
				tracker, NO_PROFILE_WARNING_MSEC / 1000])
	var active := get_is_active()
	if active != _active:
		_active = active
		print("XR %s: pose '%s' %s" % [tracker, pose, "available" if active else "not available"])
	var tracking := get_has_tracking_data()
	if tracking != _tracking:
		_tracking = tracking
		print("XR %s: %s" % [tracker, "tracking" if tracking else "not tracking"])
		if tracking and (_lost_msec < 0 or Time.get_ticks_msec() - _lost_msec > RETRACK_SECONDS * 1000.0):
			tracking_started.emit(self)
		if not tracking:
			_lost_msec = Time.get_ticks_msec()


func get_stick() -> Vector2:
	return get_vector2(&"thumbstick")


func get_ray_origin() -> Vector3:
	return global_position


func get_ray_direction() -> Vector3:
	return -global_basis.z


## The laser, `length` metres long; `hit` adds the dot at its end. on = false hides it (docs/ui-design.md: the laser
## appears only while it is aimed at something it works). The pane passes its token colours; the window pointer uses
## the defaults. Only touches the nodes when something changed (called every frame).
func set_laser(on: bool, length := 3.0, hit := false, beam := LASER_COLOR, dot := LASER_HIT_COLOR) -> void:
	if not on:
		hit = false
	var colour := (dot if hit else beam) if on else STUB_COLOR
	if on == _laser_on and hit == _laser_hit and absf(length - _laser_length) < 0.001 \
			and colour == _laser_mat.albedo_color and (not hit or _dot_mat.albedo_color == dot):
		return
	_laser_on = on
	_laser_hit = hit
	_laser_length = length
	_laser.visible = on
	_laser.scale = Vector3(1, 1, length)
	_laser.position = Vector3(0, 0, -length * 0.5)
	_dot.visible = hit
	_dot.position = Vector3(0, 0, -length + 0.003)
	_laser_mat.albedo_color = colour
	_dot_mat.albedo_color = dot


func pulse() -> void:
	trigger_haptic_pulse(&"haptic", 0.0, 0.35, 0.03, 0.0)


func _on_button_pressed(action: String) -> void:
	_log("%s pressed" % action)
	match action:
		"labels":
			labels_held.emit(self, true)
		"menu":
			menu_pressed.emit(self)
		"stick_click":
			stick_clicked.emit(self, true)
		"overlay":
			overlay_pressed.emit(self)
		"next_file":
			next_pressed.emit(self)
		"prev_file":
			prev_pressed.emit(self)
		"agent":
			agent_pressed.emit(self)
		"enter":
			enter_pressed.emit(self)


## When the runtime offers render models (XR_EXT_render_model + XR_EXT_interaction_render_model, project setting
## xr/openxr/extensions/render_model), an OpenXRRenderModelManager for this hand puts the runtime's controller model
## here (local to the aim pose); `visual` then hides its own mesh and anchors the labels to the model's nodes.
## Returns false (and prints why) when there are no render models: the hand-built mesh stays.
func setup_render_model() -> bool:
	if not Engine.has_singleton("OpenXRRenderModelExtension") or not ClassDB.class_exists("OpenXRRenderModelManager"):
		print("XR %s: no render model support in this engine build; hand-built controller" % tracker)
		return false
	var ext: Object = Engine.get_singleton("OpenXRRenderModelExtension")
	if not ext.call("is_active"):
		print("XR %s: runtime render models not active (extension off or not offered); hand-built controller" % tracker)
		return false
	var manager: Node3D = ClassDB.instantiate("OpenXRRenderModelManager")
	manager.name = "RenderModels"
	manager.set("make_local_to_pose", "aim")
	add_child(manager)
	# 2 = left hand, 3 = right hand. The manager looks up the tracker and the top-level path when this changes.
	manager.set("tracker", 2 if tracker == &"left_hand" else 3)
	manager.connect("render_model_added", func(model: Node3D) -> void:
		print("XR %s: runtime render model added" % tracker)
		# Next frame: the model's glTF scene is in the tree by then.
		visual.attach_render_model.call_deferred(model))
	manager.connect("render_model_removed", func(_model: Node3D) -> void:
		print("XR %s: runtime render model removed" % tracker)
		visual.detach_render_model())
	print("XR %s: render model manager added; waiting for the runtime's model" % tracker)
	return true
