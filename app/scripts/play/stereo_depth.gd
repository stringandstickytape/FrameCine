extends Node

## 3D depth slider (ideas #4): a horizontal shift between the two eyes' pictures (video.gdshader's stereo_shift), the
## most-asked comfort control for 3D. Positive pushes the picture further away, negative brings it nearer. Applies to
## stereo layouts only; mono pictures are untouched.
##
## Remembered globally and per file: a file's own value, when it has one, wins over the global one.
##   value              the depth in effect (fraction of one eye's width, -MAX..MAX)
##   has_file_value()   whether this file has its own value
##   set_depth(v, for_file)  for_file: remember for this file only; else the global value (and the file's own value,
##                      if any, is kept)
##   nudge(step)        +/- STEP on whichever value is in effect (the file's if it has one, else the global)
##   clear_file()       forget this file's value (back to the global one)
##   changed(value, for_file) signal
## Desktop keys (menu hidden): [ and ] nudge; Shift+[ / Shift+] nudge this file's own value.
## Settings: [stereo] depth (global), [stereo_depth_files] <file key> (scripts/play/file_key.gd).

const FileKey := preload("res://scripts/play/file_key.gd")

signal changed(value: float, for_file: bool)

## A shift of 4 % of the eye's width is already strong on a large screen.
const MAX := 0.04
const STEP := 0.002

var main: Node3D
var value := 0.0
var global_value := 0.0
var _file_key := ""


func _ready() -> void:
	global_value = clampf(float(main.settings.get_value("stereo", "depth", 0.0)), -MAX, MAX)
	main.file_opened.connect(_on_file_opened)
	_on_file_opened(main.current_path)


func _on_file_opened(path: String) -> void:
	_file_key = FileKey.key(path) if path != "" else ""
	_apply()


func has_file_value() -> bool:
	return _file_key != "" and main.settings.has_value("stereo_depth_files", _file_key)


func set_depth(v: float, for_file := false) -> void:
	v = clampf(snappedf(v, 0.0001), -MAX, MAX)
	if for_file and _file_key != "":
		main.settings.set_value("stereo_depth_files", _file_key, v)
	else:
		global_value = v
		main.settings.set_value("stereo", "depth", v)
	_apply()
	changed.emit(value, for_file)


func nudge(step: float, for_file := false) -> void:
	var own := for_file or has_file_value()
	set_depth((value if own else global_value) + step, own)


func clear_file() -> void:
	if _file_key == "":
		return
	main.settings.set_value("stereo_depth_files", _file_key, null)
	_apply()
	changed.emit(value, false)


func _apply() -> void:
	value = global_value
	if has_file_value():
		value = clampf(float(main.settings.get_value("stereo_depth_files", _file_key, 0.0)), -MAX, MAX)
	main.screen.material.set_shader_parameter("stereo_shift", value)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or main.menu_shown or main.window_pointer.is_active():
		return
	match key.keycode:
		KEY_BRACKETLEFT:
			nudge(-STEP, key.shift_pressed)
		KEY_BRACKETRIGHT:
			nudge(STEP, key.shift_pressed)
		_:
			return
	print("3D depth %+.1f %% (%s)" % [value * 100.0, "this file" if has_file_value() else "all files"])
