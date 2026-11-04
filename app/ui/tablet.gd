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
## Two panes, one above the other with a small gap (the user, 2026-11-04): a short one on top for the now playing
## controls, and below it the main one for everything else. Each is the backdrop only for now.
##
## Placement, from the head's position and its heading (yaw only, so looking down when pressing doesn't sink it):
## FORWARD metres ahead and DOWN metres below the eyes, the centre about 44° below the horizon, about half a metre
## away; its face tilted TILT degrees back from vertical (the user, 2026-11-04: a little more upright than 45°, a
## little smaller, 5 cm closer).
##
##   enabled, set_enabled(on, save := true), toggle(head), show_at(head), hide_tablet(), is_shown()
##   now_playing, main_pane    the two panes (MeshInstance3D); static pane_rects() -> {name: Rect2} in metres
##   style() -> Dictionary, set_style(changes, save := true) -> Array (errors), reset_style()
##   static pose(head) -> Transform3D

## Metres: the whole tablet's size (landscape), and where its centre sits from the eyes.
const SIZE := Vector2(0.48, 0.26)
## Metres: the now playing pane's height, and the gap between it and the main pane below.
const NOW_PLAYING_HEIGHT := 0.06
const GAP := 0.01
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
var now_playing: MeshInstance3D
var main_pane: MeshInstance3D
var _mats: Array[ShaderMaterial] = []
## What set_style() changed from the theme's defaults.
var _overrides := {}


func _ready() -> void:
	var rects := pane_rects()
	now_playing = _pane("NowPlaying", rects["now_playing"])
	main_pane = _pane("Main", rects["main"])
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
	var s := style()
	for m in _mats:
		m.set_shader_parameter("fill_color", s["fill"])
		m.set_shader_parameter("border_color", s["border"])
		m.set_shader_parameter("corner_radius", s["corner_radius"])
		m.set_shader_parameter("border_width", s["border_width"])


## Each pane's rectangle on the tablet, in metres from its centre (+y towards the top edge, away from the eyes).
static func pane_rects() -> Dictionary:
	var top := SIZE.y * 0.5
	var main_h := SIZE.y - NOW_PLAYING_HEIGHT - GAP
	return {"now_playing": Rect2(-SIZE.x * 0.5, top - NOW_PLAYING_HEIGHT, SIZE.x, NOW_PLAYING_HEIGHT),
			"main": Rect2(-SIZE.x * 0.5, -top, SIZE.x, main_h)}


func _pane(p_name: String, r: Rect2) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = p_name
	var mesh := QuadMesh.new()
	mesh.size = r.size
	mi.mesh = mesh
	mi.position = Vector3(r.get_center().x, r.get_center().y, 0.0)
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("size", r.size)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_mats.append(m)
	return mi


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
