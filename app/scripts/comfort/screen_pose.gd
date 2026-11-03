extends Node

## Lying down (ideas #12) and a head-following screen with a pin (#33): the flat screen's pose beyond main's yaw,
## distance and height, through main.screen_pose_override (main._place_screen() asks it).
##
## Lying down (one action): the screen goes up to where your head points, up to the ceiling, and keeps following
## your head's pitch slowly (a few seconds, and only after it moves more than LYING_DEAD_ZONE) so you can settle on the
## pillow; it never follows roll (the picture stays level with the room, not with a tilted head). 180 / 360 / fisheye
## turn up the same way (the horizon feature's extra pitch). Off: the screen comes back to its usual place.
##
## Head follow (unpinned): the flat screen follows your head's yaw and pitch lazily, when you look more than
## FOLLOW_DEAD_ZONE away from it, so it is always ahead (walking about, a swivel chair). Pin it (the usual state) and
## it stays where it is in the room: pinning keeps the place it followed to.
##
##   lying, set_lying(on), toggle_lying()
##   follow, set_follow(on) (false = pinned), toggle_pin()
##   yaw, pitch                  the screen's direction now (radians) while either is active
##   is_active() -> bool
##   signal changed
## Desktop keys (menu hidden): Y lying down, F follow / pin.
## Settings: [comfort] head_follow (lying down is for the session: you won't always be in bed).

signal changed

const LYING_TAU := 3.0
const LYING_DEAD_ZONE := deg_to_rad(8.0)
const LYING_MAX := deg_to_rad(90.0)
const FOLLOW_TAU := 0.45
const FOLLOW_DEAD_ZONE := deg_to_rad(15.0)
const FOLLOW_PITCH_MIN := deg_to_rad(-20.0)
const FOLLOW_PITCH_MAX := deg_to_rad(40.0)
## Moving stops once within this of the target.
const SETTLE := deg_to_rad(1.5)

var main: Node3D
var lying := false
var follow := false
var yaw := 0.0
var pitch := 0.0
var _moving_yaw := false
var _moving_pitch := false


func _ready() -> void:
	follow = bool(main.settings.get_value("comfort", "head_follow", false))
	yaw = main.screen_yaw
	main.screen_pose_override = _override
	main.environment_changed.connect(func(_id: String, _l: float) -> void: yaw = main.screen_yaw)


func is_active() -> bool:
	return lying or follow or not is_zero_approx(pitch)


func set_lying(on: bool) -> void:
	if on == lying:
		return
	lying = on
	if on:
		yaw = main.screen_yaw if not follow else yaw
		pitch = clampf(_head_pitch(), 0.0, LYING_MAX)
	else:
		pitch = 0.0
	_moving_pitch = false
	_apply()


func toggle_lying() -> void:
	set_lying(not lying)


func set_follow(on: bool) -> void:
	if on == follow:
		return
	follow = on
	main.settings.set_value("comfort", "head_follow", on)
	if on:
		yaw = main.screen_yaw
	else:
		# Pinned where it followed to: that becomes the screen's place in this room.
		main.screen_yaw = yaw
		main.set_screen(main.screen_width, main.screen_distance, main.screen_height_offset)
		if not lying:
			pitch = 0.0
	_apply()


func toggle_pin() -> void:
	set_follow(not follow)


## main._place_screen()'s pose for the flat screen: the default one unless lying down or following.
func _override(t: Transform3D) -> Transform3D:
	if not is_active():
		return t
	var b := Basis(Vector3.UP, -yaw) * Basis(Vector3.RIGHT, pitch)
	var eye := Vector3(0.0, main.eye_height, 0.0)
	return Transform3D(b, eye + b * Vector3(0.0, main.screen_height_offset, -main.screen_distance))


func _head_forward() -> Vector3:
	var cam: Camera3D = main.camera
	return -cam.global_basis.z if cam != null else Vector3.FORWARD


func _head_pitch() -> float:
	return asin(clampf(_head_forward().y, -1.0, 1.0))


func _head_yaw() -> float:
	var f := _head_forward()
	return atan2(f.x, -f.z)


func _process(delta: float) -> void:
	if not (lying or follow):
		return
	var before := Vector2(yaw, pitch)
	if follow and not main.mode.is_spherical():
		var dy := wrapf(_head_yaw() - yaw, -PI, PI)
		if absf(dy) > FOLLOW_DEAD_ZONE:
			_moving_yaw = true
		if _moving_yaw:
			yaw += dy * (1.0 - exp(-delta / FOLLOW_TAU))
			_moving_yaw = absf(dy) > SETTLE
	var lo := 0.0 if lying else FOLLOW_PITCH_MIN
	var hi := LYING_MAX if lying else FOLLOW_PITCH_MAX
	var dp := clampf(_head_pitch(), lo, hi) - pitch
	if absf(dp) > (LYING_DEAD_ZONE if lying else FOLLOW_DEAD_ZONE):
		_moving_pitch = true
	if _moving_pitch:
		pitch += dp * (1.0 - exp(-delta / (LYING_TAU if lying else FOLLOW_TAU)))
		_moving_pitch = absf(dp) > SETTLE
	if Vector2(yaw, pitch) != before:
		_apply(false)


func _apply(emit := true) -> void:
	main.features.horizon.set_extra_pitch(rad_to_deg(pitch) if lying else 0.0)
	main._place_screen()
	if emit:
		changed.emit()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or main.menu_shown or main.window_pointer.is_active():
		return
	if key.keycode == KEY_Y:
		toggle_lying()
		print("Lying down: %s" % ("on" if lying else "off"))
	elif key.keycode == KEY_F:
		toggle_pin()
		print("Screen: %s" % ("follows your head" if follow else "pinned"))
