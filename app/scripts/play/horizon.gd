extends Node

## Horizon correction (ideas #77): pitch and roll trim for 180 / 360 / fisheye files shot off-level. Turns the sphere
## in the picture's own frame (VideoScreen.sphere_tilt), before the yaw that grip-dragging sets. Remembered per file:
## the camera was crooked for that recording.
##
##   pitch, roll     degrees, -MAX..MAX (pitch > 0 tips the picture's front up, roll > 0 turns it clockwise as seen)
##   set_trim(pitch, roll), nudge(d_pitch, d_roll), reset()
##   extra_pitch, set_extra_pitch(deg)   added for the session, not saved: lying down (scripts/comfort/screen_pose.gd)
##   signal changed(pitch, roll)
## Desktop keys (menu hidden): numpad 7 / 9 roll, numpad 1 / 3 pitch, numpad 0 resets.
## Settings: [horizon_files] <file key> = [pitch, roll].

const FileKey := preload("res://scripts/play/file_key.gd")

signal changed(pitch: float, roll: float)

const MAX := 20.0
const STEP := 0.5

var main: Node3D
var pitch := 0.0
var roll := 0.0
var extra_pitch := 0.0
var _key := ""


func _ready() -> void:
	main.file_opened.connect(_on_file_opened)
	_on_file_opened(main.current_path)


func _on_file_opened(path: String) -> void:
	_key = FileKey.key(path) if path != "" else ""
	pitch = 0.0
	roll = 0.0
	if _key != "" and main.settings.has_value("horizon_files", _key):
		var v: Array = main.settings.get_value("horizon_files", _key, [0.0, 0.0])
		if v.size() >= 2:
			pitch = clampf(float(v[0]), -MAX, MAX)
			roll = clampf(float(v[1]), -MAX, MAX)
	_apply()


func set_trim(p: float, r: float) -> void:
	pitch = clampf(snappedf(p, 0.1), -MAX, MAX)
	roll = clampf(snappedf(r, 0.1), -MAX, MAX)
	if _key != "":
		var level := is_zero_approx(pitch) and is_zero_approx(roll)
		main.settings.set_value("horizon_files", _key, null if level else [pitch, roll])
	_apply()


func nudge(d_pitch: float, d_roll: float) -> void:
	set_trim(pitch + d_pitch, roll + d_roll)


func reset() -> void:
	set_trim(0.0, 0.0)


func set_extra_pitch(deg: float) -> void:
	if is_equal_approx(deg, extra_pitch):
		return
	extra_pitch = deg
	main.screen.sphere_tilt = Vector2(deg_to_rad(pitch + extra_pitch), deg_to_rad(roll))


func _apply() -> void:
	# VideoScreen puts the sphere on the head every frame with this tilt.
	main.screen.sphere_tilt = Vector2(deg_to_rad(pitch + extra_pitch), deg_to_rad(roll))
	changed.emit(pitch, roll)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or main.menu_shown or main.window_pointer.is_active():
		return
	match key.keycode:
		KEY_KP_7:
			nudge(0.0, -STEP)
		KEY_KP_9:
			nudge(0.0, STEP)
		KEY_KP_1:
			nudge(-STEP, 0.0)
		KEY_KP_3:
			nudge(STEP, 0.0)
		KEY_KP_0:
			reset()
		_:
			return
	print("Horizon: pitch %.1f°, roll %.1f°" % [pitch, roll])
