extends Node

## Manual zoom and pan (ideas #35): for odd aspects and burnt-in bars. Magnifies the picture about its centre and moves
## it, inside the same screen (video.gdshader's zoom / pan). Flat projections only; 180 / 360 / fisheye ignore it.
## Remembered per file, because the bars belong to the file.
##
##   zoom (1..MAX_ZOOM), pan (Vector2, fractions of the picture; limited so the screen stays inside the picture)
##   set_zoom(z), set_pan(p), nudge_zoom(step), nudge_pan(delta), reset()
##   signal changed(zoom, pan)
## Desktop keys (menu hidden): = / - zoom, numpad 4 6 8 2 pan, numpad 5 reset.
## Settings: [zoom_files] <file key> = [zoom, pan x, pan y] (absent: 1, 0, 0).

const FileKey := preload("res://scripts/play/file_key.gd")

signal changed(zoom: float, pan: Vector2)

const MAX_ZOOM := 3.0
const ZOOM_STEP := 0.05
const PAN_STEP := 0.01

var main: Node3D
var zoom := 1.0
var pan := Vector2.ZERO
var _key := ""


func _ready() -> void:
	main.file_opened.connect(_on_file_opened)
	main.mode_changed.connect(func(_m: Variant, _a: String) -> void: _apply())
	_on_file_opened(main.current_path)


func _on_file_opened(path: String) -> void:
	_key = FileKey.key(path) if path != "" else ""
	zoom = 1.0
	pan = Vector2.ZERO
	if _key != "" and main.settings.has_value("zoom_files", _key):
		var v: Array = main.settings.get_value("zoom_files", _key, [1.0, 0.0, 0.0])
		if v.size() >= 3:
			zoom = clampf(float(v[0]), 1.0, MAX_ZOOM)
			pan = Vector2(float(v[1]), float(v[2]))
	_apply()


func set_zoom(z: float) -> void:
	zoom = clampf(z, 1.0, MAX_ZOOM)
	_store()


func set_pan(p: Vector2) -> void:
	pan = p
	_store()


func nudge_zoom(step: float) -> void:
	set_zoom(zoom + step)


func nudge_pan(delta: Vector2) -> void:
	set_pan(pan + delta)


func reset() -> void:
	zoom = 1.0
	pan = Vector2.ZERO
	_store()


## The largest pan that keeps the screen inside the picture at this zoom.
func pan_limit() -> float:
	return 0.5 - 0.5 / zoom


func _store() -> void:
	var lim := pan_limit()
	pan = pan.clamp(Vector2(-lim, -lim), Vector2(lim, lim))
	if _key != "":
		var plain := is_equal_approx(zoom, 1.0) and pan.is_zero_approx()
		main.settings.set_value("zoom_files", _key, null if plain else [snappedf(zoom, 0.001), snappedf(pan.x, 0.0001),
				snappedf(pan.y, 0.0001)])
	_apply()


func _apply() -> void:
	var flat: bool = not main.mode.is_spherical()
	var m: ShaderMaterial = main.screen.material
	m.set_shader_parameter("zoom", zoom if flat else 1.0)
	m.set_shader_parameter("pan", pan if flat else Vector2.ZERO)
	changed.emit(zoom, pan)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or main.menu_shown or main.window_pointer.is_active():
		return
	match key.keycode:
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			nudge_zoom(ZOOM_STEP)
		KEY_MINUS, KEY_KP_SUBTRACT:
			nudge_zoom(-ZOOM_STEP)
		KEY_KP_4:
			nudge_pan(Vector2(-PAN_STEP, 0))
		KEY_KP_6:
			nudge_pan(Vector2(PAN_STEP, 0))
		KEY_KP_8:
			nudge_pan(Vector2(0, -PAN_STEP))
		KEY_KP_2:
			nudge_pan(Vector2(0, PAN_STEP))
		KEY_KP_5:
			reset()
		_:
			return
	print("Zoom %.2f, pan (%.2f, %.2f)" % [zoom, pan.x, pan.y])
