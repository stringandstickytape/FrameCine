extends Node3D

## A small card in the world for playback moments (up next #34, intermission #39, the jog wheel's time #63): a dark
## panel with a title line and a smaller line, kept at a constant angular size. Placed under the flat screen's right
## half ("below"), or in front of the screen's centre ("centre"); for 180 / 360, low ahead. It follows the screen while
## it shows. Fonts and colours are the pane's tokens (ui/pane_style.gd) when that file is there.
##
##   show_card(title, line, placement := "below"), set_line(line), hide_card(), is_showing(), title, line

const STYLE_PATH := "res://ui/pane_style.gd"
## Title text height as a fraction of the distance (about 1.6 degrees).
const TITLE_ANGLE := 0.028
const SPHERE_DISTANCE := 2.2
const SPHERE_DROP := 0.35

var main: Node3D
var title := ""
var line := ""
var placement := "below"
var _title: Label3D
var _line: Label3D
var _back: MeshInstance3D


func _ready() -> void:
	top_level = true
	var style: GDScript = load(STYLE_PATH) if ResourceLoader.exists(STYLE_PATH) else null
	_title = _label(style, &"medium", 48)
	_line = _label(style, &"regular", 32)
	_back = MeshInstance3D.new()
	_back.mesh = QuadMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	m.render_priority = 9
	var bg := Color(0.05, 0.05, 0.07, 0.86)
	if style != null:
		var c: Color = style.color(&"surface")
		bg = Color(c.r, c.g, c.b, 0.9)
	m.albedo_color = bg
	_back.material_override = m
	_back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_back)
	add_child(_title)
	add_child(_line)
	visible = false


func _label(style: GDScript, font_token: StringName, size: int) -> Label3D:
	var l := Label3D.new()
	l.font_size = size
	l.outline_size = 0
	l.shaded = false
	l.double_sided = false
	l.no_depth_test = true
	l.render_priority = 10
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.modulate = Color(0.95, 0.95, 0.97)
	if style != null:
		var f: Font = style.font(font_token)
		if f != null:
			l.font = f
		l.modulate = style.color(&"text")
	return l


func show_card(p_title: String, p_line := "", p_placement := "below") -> void:
	title = p_title
	line = p_line
	placement = p_placement
	_title.text = title
	_line.text = line
	visible = true
	_place()


func set_line(p_line: String) -> void:
	if p_line == line:
		return
	line = p_line
	_line.text = line
	_place()


func hide_card() -> void:
	visible = false


func is_showing() -> bool:
	return visible


func _process(_delta: float) -> void:
	if visible:
		_place()


func _place() -> void:
	var cam: Node3D = main.camera
	var eye: Vector3 = cam.global_position if cam != null else Vector3(0, main.eye_height, 0)
	var anchor: Transform3D
	var distance: float
	if main.mode.is_spherical():
		var yaw: float = main.screen_yaw
		anchor = Transform3D(Basis(Vector3.UP, -yaw), Vector3(sin(yaw) * SPHERE_DISTANCE,
				main.eye_height - SPHERE_DROP, -cos(yaw) * SPHERE_DISTANCE))
		distance = SPHERE_DISTANCE
	else:
		var screen: Node3D = main.screen
		var size: Vector2 = screen.get_flat_size()
		distance = maxf(screen.global_position.distance_to(eye), 0.5)
		var title_h := distance * TITLE_ANGLE
		var local := Vector3(0.0, 0.0, 0.05)
		if placement == "below":
			local = Vector3(size.x * 0.25, -size.y * 0.5 - title_h * 2.4, 0.05)
		anchor = screen.global_transform * Transform3D(Basis.IDENTITY, local)
		anchor.basis = anchor.basis.orthonormalized()
	# In front of the screen (intermission) it is the only thing to read: larger.
	var h := distance * TITLE_ANGLE * (1.8 if placement == "centre" and not main.mode.is_spherical() else 1.0)
	_title.pixel_size = h / _title.font_size
	_line.pixel_size = h * 0.66 / _line.font_size
	var has_line := line != ""
	_title.position = Vector3(0, h * 0.45 if has_line else 0.0, 0.002)
	_line.position = Vector3(0, -h * 0.65, 0.002)
	_line.visible = has_line
	var w := maxf(_title.get_aabb().size.x, _line.get_aabb().size.x if has_line else 0.0) + h * 1.2
	(_back.mesh as QuadMesh).size = Vector2(w, h * (2.6 if has_line else 1.6))
	_back.position = Vector3(0, -h * 0.1 if has_line else 0.0, 0.0)
	global_transform = anchor
