extends Node3D

## The info overlay: a small world-space text panel (main.gd puts it under the flat screen, or low in front in
## 180/360) with file, mode, time / duration, decode fps, dropped frames, battery. A SubViewport refreshed 4 times a
## second while shown, on a quad drawn through the room (no depth test: a seat back or the stage can't hide it) but
## under the panes and the other transparent things in front of it (default render priority; it was 100 and showed
## through the agent's pane, the user, 2026-11-05).
## Its top band says LEFT EYE / RIGHT EYE through eye_overlay.gdshader: each eye sees only its own word (VIEW_INDEX),
## so a glance with one eye closed shows which view reaches which eye.

const OVERLAY_SHADER := preload("res://shaders/eye_overlay.gdshader")
const RESOLUTION := Vector2i(640, 400)
const BAND := 0.22
## Width of the quad at scale 1, metres.
const WIDTH := 0.4
const BATTERY_INTERVAL_MS := 10000

var _viewport: SubViewport
var _text: Label
var _material: ShaderMaterial
var _battery := -1
var _battery_msec := -BATTERY_INTERVAL_MS


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.size = RESOLUTION
	_viewport.disable_3d = true
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.92)
	bg.position = Vector2.ZERO
	bg.size = Vector2(RESOLUTION)
	_viewport.add_child(bg)
	var band_h := RESOLUTION.y * BAND
	var left := _make_label("LEFT EYE", Rect2(0, 0, RESOLUTION.x, band_h), 64, Color(1.0, 0.55, 0.45))
	var right := _make_label("RIGHT EYE", Rect2(RESOLUTION.x * 0.5, 0, RESOLUTION.x, band_h), 64, Color(0.5, 0.7, 1.0))
	# The shader stretches each half of the band over the full width, so draw the words at half width.
	for l: Label in [left, right]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.scale = Vector2(0.5, 1.0)
	_text = _make_label("", Rect2(14, band_h + 6, RESOLUTION.x - 28, RESOLUTION.y - band_h - 12), 24, Color.WHITE)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_material = ShaderMaterial.new()
	_material.shader = OVERLAY_SHADER
	_material.render_priority = 0
	_material.set_shader_parameter("overlay", _viewport.get_texture())
	_material.set_shader_parameter("band", BAND)
	var quad := QuadMesh.new()
	quad.size = Vector2(WIDTH, WIDTH * RESOLUTION.y / RESOLUTION.x)
	var mesh := MeshInstance3D.new()
	mesh.mesh = quad
	mesh.material_override = _material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)


func _make_label(text: String, rect: Rect2, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.position = rect.position
	l.size = rect.size
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	_viewport.add_child(l)
	return l


func get_height() -> float:
	return WIDTH * RESOLUTION.y / RESOLUTION.x


func set_text(text: String) -> void:
	_text.text = text
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func set_force_eye(eye: int) -> void:
	_material.set_shader_parameter("force_eye", eye)


## Battery charge in percent, or -1 if there is none (re-read every 10 s).
func get_battery() -> int:
	var now := Time.get_ticks_msec()
	if now - _battery_msec >= BATTERY_INTERVAL_MS:
		_battery_msec = now
		_battery = read_battery()
	return _battery


## On the headset: the first /sys/class/power_supply/* of type Battery.
static func read_battery() -> int:
	var root := "/sys/class/power_supply"
	if not DirAccess.dir_exists_absolute(root):
		return -1
	# The entries are symlinks; list both kinds in case they are not reported as directories.
	for d in Array(DirAccess.get_directories_at(root)) + Array(DirAccess.get_files_at(root)):
		var type_file := FileAccess.open(root.path_join(d).path_join("type"), FileAccess.READ)
		if type_file == null or type_file.get_line().strip_edges() != "Battery":
			continue
		var cap := FileAccess.open(root.path_join(d).path_join("capacity"), FileAccess.READ)
		if cap != null:
			return cap.get_line().strip_edges().to_int()
	return -1
