extends Node

## 2D from 3D (ideas #59): one eye's picture to both views, for eye strain or a damaged eye. Works for every stereo
## layout and projection (flat, 180, 360, fisheye); mono files are unaffected. "Left" is the left eye as the file
## intends (after any swap the mode applies). The 3D depth shift is off while it is on. Also the accessibility pack's
## monocular setting (#74).
##
##   eye             -1 off, 0 left, 1 right
##   set_eye(e), cycle() (off -> left -> right -> off)
##   signal changed(eye)
## Desktop key (menu hidden): 2 cycles.
## Settings: [stereo] mono_eye (global: it is about the viewer, not the file).

signal changed(eye: int)

var main: Node3D
var eye := -1


func _ready() -> void:
	eye = clampi(int(main.settings.get_value("stereo", "mono_eye", -1)), -1, 1)
	_apply()


func set_eye(e: int) -> void:
	eye = clampi(e, -1, 1)
	main.settings.set_value("stereo", "mono_eye", eye if eye >= 0 else null)
	_apply()


func cycle() -> void:
	set_eye(eye + 1 if eye < 1 else -1)


func describe() -> String:
	return ["3D", "2D (left eye)", "2D (right eye)"][eye + 1]


func _apply() -> void:
	main.screen.material.set_shader_parameter("mono_eye", eye)
	changed.emit(eye)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or main.menu_shown or main.window_pointer.is_active():
		return
	if key.keycode == KEY_2:
		cycle()
		print("Stereo: %s" % describe())
