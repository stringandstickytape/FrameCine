extends Node3D

## Tablet (a prototype for a new UI, [pane] tablet, off by default): a landscape panel where you would hold a tablet
## in both hands, below and in front of the eyes, tilted up towards them, close enough to lean in to small detail
## and to touch its controls (the laser stays too). Beside the front panel, which stays for the time being: it shows
## and hides with the panel (ui_layer.gd show_panel(), hide_panel()), placed from the head when the menu button opens
## the panel and then fixed in the room, and it fades in and out.
##
## Two panes, one above the other with a small gap (the user, 2026-11-04):
##   now playing   short, on top: the title on the left, "played / total" on the right (as the front panel shows
##                 them), and the time bar along the bottom. Nothing else. bar_fraction(point) gives the place in the
##                 film for a point on or near the bar, for touching it or the laser and trigger (to come).
##   main          below it, for everything else: the backdrop only for now.
##
## Its look is one JSON document, all of it themable from outside (the assistant, in time). The defaults are
## ui/themes/tablet.json; set_style() merges a partial document over them, checked against SCHEMA (nothing changes
## if any of it is wrong), and keeps the changes in [pane] tablet_style; null puts a value back to the default.
##   fade          in, out: seconds
##   pane          fill, border: colours ("#rrggbb" or "#rrggbbaa", the last pair the opacity); corner_radius,
##                 border_width: metres. Each pane is a rounded rectangle (shaders/tablet.gdshader), nothing drawn
##                 outside its border. Frosted glass will be another kind of fill here.
##   now_playing   padding (metres); title and time: color, size (the font's size, metres), font (one of the theme's:
##                 FONTS); bar: track, played (colours), height, corner_radius (metres)
##
## Placement, from the head's position and its heading (yaw only, so looking down when pressing doesn't sink it):
## FORWARD metres ahead and DOWN metres below the eyes, the centre about 44° below the horizon, about half a metre
## away; its face tilted TILT degrees back from vertical (the user, 2026-11-04: a little more upright than 45°, a
## little smaller, 5 cm closer).
##
##   enabled, set_enabled(on, save := true), toggle(head), show_at(head), hide_tablet(), is_shown()
##   style() -> Dictionary, set_style(changes, save := true) -> Array (errors), reset_style()
##   now_playing, main_pane    the two panes (MeshInstance3D); title_label, time_label (Label3D)
##   bar_rect() -> Rect2 (now playing pane's space), bar_fraction(global_point) -> float (-1: not on the bar)
##   ray_hit(origin, direction) -> {point, distance, pane, fraction} or {}; poke_probe(point) -> {depth, fraction}
##   seek_to(fraction) -> bool
## Input (ui_layer.gd): the pointer controller's laser shows on either pane, and the trigger on the time bar skips
## there; touching the bar with either controller's tip skips there too. Anywhere else on the tablet the trigger is
## taken (nothing happens), so it doesn't pause the film by accident.
##   static pane_rects() -> {name: Rect2} in metres, static validate(doc, partial) -> Array (errors)
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
const W := preload("res://ui/pane_widgets.gd")
const SHADER := preload("res://shaders/tablet.gdshader")
const STYLE_PATH := "res://ui/themes/tablet.json"
const FONTS := ["light", "regular", "medium", "semibold", "label"]
## The style's shape: a leaf is "color", "font" or [min, max] (a number).
const SCHEMA := {
	"fade": {"in": [0.0, 2.0], "out": [0.0, 2.0]},
	"pane": {"fill": "color", "border": "color", "corner_radius": [0.0, 0.13], "border_width": [0.0, 0.03]},
	"now_playing": {
		"padding": [0.0, 0.025],
		"title": {"color": "color", "size": [0.004, 0.03], "font": "font"},
		"time": {"color": "color", "size": [0.004, 0.03], "font": "font"},
		"bar": {"track": "color", "played": "color", "height": [0.001, 0.02], "corner_radius": [0.0, 0.01]},
	},
}
## Label3D: the font's pixels per em (pixel_size makes it the style's size in metres).
const FONT_PX := 96
## Metres the text and the bar sit in front of the pane, so they never fight it for depth.
const LIFT := 0.0008
## Metres round the bar that still count as on it: the bar is thin, a finger or a laser is not.
const BAR_HIT := Vector2(0.006, 0.012)
## Metres between the title and the time.
const TEXT_GAP := 0.02

var app: Node3D
var enabled := false
var now_playing: MeshInstance3D
var main_pane: MeshInstance3D
var title_label: Label3D
var time_label: Label3D
var _bar_track: MeshInstance3D
var _bar_played: MeshInstance3D
var _mats: Array[ShaderMaterial] = []
var _defaults := {}
## What set_style() changed from the defaults (the same shape, values as given).
var _overrides := {}
var _shown := false
var _opacity := 0.0
var _tween: Tween
var _title_full := ""
var _title_fit := -1.0
var _fraction := -1.0


func _ready() -> void:
	_defaults = _load_defaults()
	var rects := pane_rects()
	now_playing = _pane("NowPlaying", rects["now_playing"])
	main_pane = _pane("Main", rects["main"])
	title_label = _label("Title", HORIZONTAL_ALIGNMENT_LEFT)
	time_label = _label("Time", HORIZONTAL_ALIGNMENT_RIGHT)
	_bar_track = _bar("BarTrack", "track", 1)
	_bar_played = _bar("BarPlayed", "played", 2)
	visible = false
	if app != null:
		enabled = bool(app.settings.get_value("pane", "tablet", false))
		var saved: Variant = app.settings.get_value("pane", "tablet_style", {})
		if saved is Dictionary and validate(saved, true).is_empty():
			_overrides = (saved as Dictionary).duplicate(true)
	_apply_style()
	_set_opacity(0.0)


func _process(_delta: float) -> void:
	if visible and app != null:
		_update_now_playing()


# --- Showing ------------------------------------------------------------------------------------------------------

## save false: for this run only.
func set_enabled(on: bool, save := true) -> void:
	enabled = on
	if save and app != null:
		app.settings.set_value("pane", "tablet", true if on else null)
	if not on:
		hide_tablet()


func toggle(head: Transform3D) -> void:
	if _shown:
		hide_tablet()
	else:
		show_at(head)


func show_at(head: Transform3D) -> void:
	global_transform = pose(head)
	_shown = true
	visible = true
	if app != null:
		_update_now_playing()
	_fade_to(1.0, float(_get(style(), "fade/in")))


func hide_tablet() -> void:
	if not _shown:
		return
	_shown = false
	_fade_to(0.0, float(_get(style(), "fade/out")))


## True from show_at() to hide_tablet() (it may still be fading in, or fading out after).
func is_shown() -> bool:
	return _shown


func _fade_to(target: float, seconds: float) -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	if seconds <= 0.0 or not is_inside_tree():
		_set_opacity(target)
		visible = target > 0.0
		return
	_tween = create_tween()
	_tween.tween_method(_set_opacity, _opacity, target, seconds * absf(target - _opacity))
	if target <= 0.0:
		_tween.tween_callback(func() -> void: visible = false)


func _set_opacity(v: float) -> void:
	_opacity = v
	for m in _mats:
		m.set_shader_parameter("opacity", v)
	for l: Label3D in [title_label, time_label]:
		l.modulate.a = v * float(l.get_meta("alpha", 1.0))


# --- Now playing --------------------------------------------------------------------------------------------------

func _update_now_playing() -> void:
	var player: Object = app.player
	var has := bool(player.has_source())
	var title: String = app.display_title() if has else ""
	if title != _title_full:
		_title_full = title
		_title_fit = -1.0
	var pos: float = player.get_position() if has else 0.0
	var dur: float = player.get_duration() if has else 0.0
	var t := ""
	if has:
		t = "%s / %s" % [W.clock(pos), W.clock(dur)] if dur > 0.0 else (W.clock(pos) if pos > 0.0 else "")
	if time_label.text != t:
		time_label.text = t
		_title_fit = -1.0
	_fit_title()
	_set_fraction(clampf(pos / dur, 0.0, 1.0) if dur > 0.0 else 0.0)


## The title, cut with an ellipsis to the room the time leaves it.
func _fit_title() -> void:
	if _title_fit >= 0.0:
		return
	var r: Rect2 = pane_rects()["now_playing"]
	var pad := float(_get(style(), "now_playing/padding"))
	var room := maxf(r.size.x - 2.0 * pad - _text_width(time_label, time_label.text) - TEXT_GAP, 0.0)
	_title_fit = room
	var text := _title_full
	if _text_width(title_label, text) > room:
		while text.length() > 1 and _text_width(title_label, text + "…") > room:
			text = text.left(-1)
		text = text.strip_edges() + "…"
	title_label.text = text


func _text_width(l: Label3D, text: String) -> float:
	if text == "" or l.font == null:
		return 0.0
	return l.font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_PX).x * l.pixel_size


func _set_fraction(f: float) -> void:
	if is_equal_approx(f, _fraction):
		return
	_fraction = f
	var bar := bar_rect()
	var w := bar.size.x * f
	_bar_played.visible = w > 0.0005
	var mesh := _bar_played.mesh as QuadMesh
	mesh.size = Vector2(maxf(w, 0.0005), bar.size.y)
	(_bar_played.material_override as ShaderMaterial).set_shader_parameter("size", mesh.size)
	_bar_played.position = Vector3(bar.position.x + w * 0.5, bar.get_center().y, LIFT * 2.0)


## A ray against the panes while shown: the nearer pane it hits, with the bar fraction (-1 off the bar), or {}.
func ray_hit(origin: Vector3, direction: Vector3) -> Dictionary:
	if not _shown:
		return {}
	var inv := global_transform.affine_inverse()
	var o := inv * origin
	var d := inv.basis * direction
	if o.z <= 0.0 or d.z >= -1e-6:
		return {}
	var p := o + d * (-o.z / d.z)
	for key: String in ["now_playing", "main"]:
		var r: Rect2 = pane_rects()[key]
		var on_bar := key == "now_playing" and bar_fraction(global_transform * p) >= 0.0
		if r.has_point(Vector2(p.x, p.y)) or on_bar:
			var world := global_transform * p
			return {"point": world, "distance": world.distance_to(origin), "pane": key,
					"fraction": bar_fraction(world) if key == "now_playing" else -1.0}
	return {}


## For touching: how far the point is in front of the tablet (negative behind it), and the bar fraction under it
## (-1 off the bar).
func poke_probe(point: Vector3) -> Dictionary:
	var p := global_transform.affine_inverse() * point
	return {"depth": p.z, "fraction": bar_fraction(global_transform * Vector3(p.x, p.y, 0.0)) if _shown else -1.0}


## Skips the film to a fraction of its length. False when it can't (nothing playing, a live stream).
func seek_to(fraction: float) -> bool:
	if app == null or not app.player.has_source() or not app.player.can_seek():
		return false
	var dur: float = app.player.get_duration()
	if dur <= 0.0:
		return false
	app.player.seek(clampf(fraction, 0.0, 1.0) * dur)
	_update_now_playing()
	return true


## The time bar's rectangle in the now playing pane's space (metres from its centre).
func bar_rect() -> Rect2:
	var r: Rect2 = pane_rects()["now_playing"]
	var pad := float(_get(style(), "now_playing/padding"))
	var h := float(_get(style(), "now_playing/bar/height"))
	return Rect2(-r.size.x * 0.5 + pad, -r.size.y * 0.5 + pad, r.size.x - 2.0 * pad, h)


## Where in the film a point (global) on or near the time bar is, 0 to 1; -1 when it isn't on the bar (BAR_HIT round
## it counts). For touching the bar, or the laser and the trigger.
func bar_fraction(point: Vector3) -> float:
	var p := now_playing.to_local(point)
	var bar := bar_rect()
	if not bar.grow_individual(BAR_HIT.x, BAR_HIT.y, BAR_HIT.x, BAR_HIT.y).has_point(Vector2(p.x, p.y)):
		return -1.0
	return clampf((p.x - bar.position.x) / bar.size.x, 0.0, 1.0)


# --- Style --------------------------------------------------------------------------------------------------------

## The style in use: the defaults (ui/themes/tablet.json) with set_style()'s changes merged over them.
func style() -> Dictionary:
	var s := _defaults.duplicate(true)
	_merge(s, _overrides)
	return s


## Merges a partial style document over the current one; a value set to null goes back to the default. Returns the
## errors ([{path, error}]); nothing changes when there are any.
func set_style(changes: Dictionary, save := true) -> Array:
	var errors := validate(changes, true)
	if not errors.is_empty():
		return errors
	var next := _overrides.duplicate(true)
	_merge(next, changes, true)
	_overrides = next
	if save and app != null:
		app.settings.set_value("pane", "tablet_style", _overrides if not _overrides.is_empty() else null)
	_apply_style()
	return errors


func reset_style() -> void:
	_overrides = {}
	if app != null:
		app.settings.set_value("pane", "tablet_style", null)
	_apply_style()


## The errors in a style document against SCHEMA ([{path, error}]); partial: nulls allowed (back to the default).
static func validate(doc: Variant, partial := false, schema: Dictionary = SCHEMA, path := "") -> Array:
	if not (doc is Dictionary):
		return [{"path": path if path != "" else "$", "error": "an object"}]
	var errors: Array = []
	for k: Variant in doc:
		var key := str(k)
		var at := key if path == "" else path + "/" + key
		if not schema.has(key):
			errors.append({"path": at, "error": "one of " + ", ".join(schema.keys())})
			continue
		var v: Variant = doc[k]
		var want: Variant = schema[key]
		if v == null:
			if not partial:
				errors.append({"path": at, "error": "a value"})
		elif want is Dictionary:
			errors.append_array(validate(v, partial, want, at))
		elif want is String and want == "color":
			if not (v is String and Color.html_is_valid(v)):
				errors.append({"path": at, "error": "a colour: \"#rrggbb\" or \"#rrggbbaa\""})
		elif want is String and want == "font":
			if not (v is String and v in FONTS):
				errors.append({"path": at, "error": "one of " + ", ".join(FONTS)})
		elif want is Array:
			if not (v is float or v is int) or float(v) < float(want[0]) or float(v) > float(want[1]):
				errors.append({"path": at, "error": "a number, %s..%s" % [want[0], want[1]]})
	return errors


func _apply_style() -> void:
	if now_playing == null:
		return
	var s := style()
	for m in _mats:
		var role := str(m.get_meta("role", "pane"))
		if role == "pane":
			m.set_shader_parameter("fill_color", Color.html(_get(s, "pane/fill")))
			m.set_shader_parameter("border_color", Color.html(_get(s, "pane/border")))
			m.set_shader_parameter("corner_radius", float(_get(s, "pane/corner_radius")))
			m.set_shader_parameter("border_width", float(_get(s, "pane/border_width")))
		else:
			m.set_shader_parameter("fill_color", Color.html(_get(s, "now_playing/bar/" + role)))
			m.set_shader_parameter("corner_radius", float(_get(s, "now_playing/bar/corner_radius")))
			m.set_shader_parameter("border_width", 0.0)
	var r: Rect2 = pane_rects()["now_playing"]
	var pad := float(_get(s, "now_playing/padding"))
	var top := r.size.y * 0.5 - pad
	for row: Array in [[title_label, "title", -r.size.x * 0.5 + pad], [time_label, "time", r.size.x * 0.5 - pad]]:
		var l: Label3D = row[0]
		var key: String = row[1]
		var size := float(_get(s, "now_playing/%s/size" % key))
		l.font = PaneStyle.font(StringName(str(_get(s, "now_playing/%s/font" % key))))
		l.pixel_size = size / FONT_PX
		var c := Color.html(_get(s, "now_playing/%s/color" % key))
		l.set_meta("alpha", c.a)
		l.modulate = c
		l.modulate.a = c.a * _opacity
		l.position = Vector3(float(row[2]), top - size * 0.5, LIFT)
	var bar := bar_rect()
	(_bar_track.mesh as QuadMesh).size = bar.size
	(_bar_track.material_override as ShaderMaterial).set_shader_parameter("size", bar.size)
	_bar_track.position = Vector3(bar.get_center().x, bar.get_center().y, LIFT)
	_fraction = -1.0
	_title_fit = -1.0
	if app != null:
		_update_now_playing()


## a/b/c of a nested dictionary (null when it isn't there).
static func _get(d: Dictionary, path: String) -> Variant:
	var v: Variant = d
	for part in path.split("/"):
		if not (v is Dictionary) or not (v as Dictionary).has(part):
			return null
		v = v[part]
	return v


## Deep merge of src into dst; with drop_nulls a null in src removes the key from dst (and an emptied object).
static func _merge(dst: Dictionary, src: Dictionary, drop_nulls := false) -> void:
	for k: Variant in src:
		var v: Variant = src[k]
		if v == null:
			if drop_nulls:
				dst.erase(k)
		elif v is Dictionary:
			if not (dst.get(k) is Dictionary):
				dst[k] = {}
			_merge(dst[k], v, drop_nulls)
			if drop_nulls and (dst[k] as Dictionary).is_empty():
				dst.erase(k)
		else:
			dst[k] = v


static func _load_defaults() -> Dictionary:
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(STYLE_PATH))
	if not (doc is Dictionary):
		push_error("Tablet: %s is not a JSON object" % STYLE_PATH)
		return {}
	var errors := validate(doc)
	if not errors.is_empty():
		push_error("Tablet: %s: %s" % [STYLE_PATH, errors])
	return doc


# --- Building -----------------------------------------------------------------------------------------------------

## Each pane's rectangle on the tablet, in metres from its centre (+y towards the top edge, away from the eyes).
static func pane_rects() -> Dictionary:
	var top := SIZE.y * 0.5
	var main_h := SIZE.y - NOW_PLAYING_HEIGHT - GAP
	return {"now_playing": Rect2(-SIZE.x * 0.5, top - NOW_PLAYING_HEIGHT, SIZE.x, NOW_PLAYING_HEIGHT),
			"main": Rect2(-SIZE.x * 0.5, -top, SIZE.x, main_h)}


func _pane(p_name: String, r: Rect2) -> MeshInstance3D:
	var mi := _rounded(p_name, r.size, "pane", 0)
	mi.position = Vector3(r.get_center().x, r.get_center().y, 0.0)
	add_child(mi)
	return mi


func _bar(p_name: String, role: String, priority: int) -> MeshInstance3D:
	var mi := _rounded(p_name, Vector2(0.01, 0.004), role, priority)
	now_playing.add_child(mi)
	return mi


func _rounded(p_name: String, size: Vector2, role: String, priority: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = p_name
	var mesh := QuadMesh.new()
	mesh.size = size
	mi.mesh = mesh
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.render_priority = priority
	m.set_shader_parameter("size", size)
	m.set_meta("role", role)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mats.append(m)
	return mi


func _label(p_name: String, align: HorizontalAlignment) -> Label3D:
	var l := Label3D.new()
	l.name = p_name
	l.font_size = FONT_PX
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.outline_size = 0
	l.render_priority = 3
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	now_playing.add_child(l)
	return l


## The tablet's place for a head pose: see the header. The panes' faces (+Z) point back up towards the eyes.
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
