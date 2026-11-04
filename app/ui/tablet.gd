extends Node3D

## Tablet (a prototype for a new UI, [pane] tablet, off by default): a landscape panel where you would hold a tablet
## in both hands, below and in front of the eyes, tilted up towards them, close enough to lean in to small detail
## and to touch its controls (the laser stays too). For now its backdrop only, beside the front panel, which stays
## for the time being: it shows and hides with the panel (ui_layer.gd show_panel(), hide_panel()), placed from the
## head when the menu button opens the panel and then fixed in the room.
##
## Its look is a style, all of it themable from outside (the assistant, in time): a rounded rectangle
## (shaders/tablet.gdshader) with a fill and a border, each colour with its own opacity, nothing drawn outside the
## border. The defaults come from the theme (tokens tablet_fill, tablet_border, tablet_radius_mm, tablet_border_mm);
## set_style() replaces any part of them and is kept in [pane] tablet_style. Frosted glass will be another kind of
## fill in the same style.
##   STYLE keys: fill, border (colours: "#rrggbbaa" or Color), corner_radius, border_width (metres)
##
## Placement, from the head's position and its heading (yaw only, so looking down when pressing doesn't sink it):
## FORWARD metres ahead and DOWN metres below the eyes, the centre about 44° below the horizon, about half a metre
## away; its face tilted TILT degrees back from vertical (the user, 2026-11-04: a little more upright than 45°, a
## little smaller, 5 cm closer).
##
##   enabled, set_enabled(on, save := true), toggle(head), show_at(head), hide_tablet(), is_shown()
##   style() -> Dictionary, set_style(changes, save := true) -> Array (errors), reset_style()
##   static pose(head) -> Transform3D

## Metres: the panel's size (landscape), and where its centre sits from the eyes.
const SIZE := Vector2(0.48, 0.26)
const FORWARD := 0.35
const DOWN := 0.34
## Degrees the face tilts back from vertical: 45 would face a point 45° below the horizon.
const TILT := 35.0
const PaneStyle := preload("res://ui/pane_style.gd")
const SHADER := preload("res://shaders/tablet.gdshader")
## Style bounds: metres.
const RADIUS_MAX := 0.13
const BORDER_MAX := 0.03

var app: Node3D
var enabled := false
var _quad: MeshInstance3D
var _mat: ShaderMaterial
## What set_style() changed from the theme's defaults.
var _overrides := {}


func _ready() -> void:
	_quad = MeshInstance3D.new()
	_quad.name = "Quad"
	var mesh := QuadMesh.new()
	mesh.size = SIZE
	_quad.mesh = mesh
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("size", SIZE)
	_quad.material_override = _mat
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_quad)
	visible = false
	if app != null:
		enabled = bool(app.settings.get_value("pane", "tablet", false))
		var saved: Variant = app.settings.get_value("pane", "tablet_style", {})
		if saved is Dictionary:
			set_style(saved, false)
	_apply_style()
	PaneStyle.holder().changed.connect(_apply_style)


## The style in use: the theme's defaults with set_style()'s changes over them.
func style() -> Dictionary:
	var s := {"fill": PaneStyle.color(&"tablet_fill"), "border": PaneStyle.color(&"tablet_border"),
			"corner_radius": PaneStyle.constant(&"tablet_radius_mm") / 1000.0,
			"border_width": PaneStyle.constant(&"tablet_border_mm") / 1000.0}
	s.merge(_overrides, true)
	return s


## Changes part of the style (the rest stays); a key set to null goes back to the theme's. Returns the errors
## ([{path, error}]); nothing changes when there are any.
func set_style(changes: Dictionary, save := true) -> Array:
	var errors: Array = []
	var next := _overrides.duplicate()
	for k: Variant in changes:
		var key := str(k)
		var v: Variant = changes[k]
		if v == null:
			next.erase(key)
			continue
		match key:
			"fill", "border":
				var c: Variant = _to_color(v)
				if c == null:
					errors.append({"path": key, "error": "a colour: \"#rrggbb\" or \"#rrggbbaa\""})
				else:
					next[key] = c
			"corner_radius", "border_width":
				var most := RADIUS_MAX if key == "corner_radius" else BORDER_MAX
				if not (v is float or v is int) or float(v) < 0.0 or float(v) > most:
					errors.append({"path": key, "error": "metres, 0..%s" % most})
				else:
					next[key] = float(v)
			_:
				errors.append({"path": key, "error": "one of fill, border, corner_radius, border_width"})
	if not errors.is_empty():
		return errors
	_overrides = next
	if save and app != null:
		var keep := {}
		for k: String in _overrides:
			var v: Variant = _overrides[k]
			keep[k] = "#" + (v as Color).to_html(true) if v is Color else v
		app.settings.set_value("pane", "tablet_style", keep if not keep.is_empty() else null)
	_apply_style()
	return errors


func reset_style() -> void:
	_overrides = {}
	if app != null:
		app.settings.set_value("pane", "tablet_style", null)
	_apply_style()


func _apply_style() -> void:
	if _mat == null:
		return
	var s := style()
	_mat.set_shader_parameter("fill_color", s["fill"])
	_mat.set_shader_parameter("border_color", s["border"])
	_mat.set_shader_parameter("corner_radius", s["corner_radius"])
	_mat.set_shader_parameter("border_width", s["border_width"])


static func _to_color(v: Variant) -> Variant:
	if v is Color:
		return v
	if v is String and Color.html_is_valid(v):
		return Color.html(v)
	return null


## save false: for this run only.
func set_enabled(on: bool, save := true) -> void:
	enabled = on
	if save and app != null:
		app.settings.set_value("pane", "tablet", true if on else null)
	if not on:
		hide_tablet()


func toggle(head: Transform3D) -> void:
	if visible:
		hide_tablet()
	else:
		show_at(head)


func show_at(head: Transform3D) -> void:
	global_transform = pose(head)
	visible = true


func hide_tablet() -> void:
	visible = false


func is_shown() -> bool:
	return visible


## The tablet's place for a head pose: see the header. The quad's face (+Z) points back up at the eyes.
static func pose(head: Transform3D) -> Transform3D:
	var forward := -head.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	var right := forward.cross(Vector3.UP).normalized()
	var t := deg_to_rad(TILT)
	var face := (-forward * cos(t) + Vector3.UP * sin(t)).normalized()
	var up := face.cross(right).normalized()
	var origin := head.origin + forward * FORWARD + Vector3.DOWN * DOWN
	return Transform3D(Basis(right, up, face), origin)
