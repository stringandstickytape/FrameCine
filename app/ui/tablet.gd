extends Node3D

## Tablet: the app's menu (the user, 2026-11-06: the front panel, the first UI, is gone; this is the one). A landscape
## panel where you would hold a tablet in both hands, below and in front of the eyes, tilted up towards them, close
## enough to lean in to small detail and to touch its controls (the laser stays too). It shows and hides with the
## panel (ui_layer.gd show_panel(), hide_panel()), placed from the head when the menu button opens the panel and then
## fixed in the room, and it fades in and out.
##
## Two panes, one above the other with a small gap (the user, 2026-11-04):
##   now playing   short, on top: a small line with the chapter on the left and the status on the right (the
##                 clock, time left and end, battery, low controllers, Listening: set_header(), from the menu; the
##                 user, 2026-11-06: the menu's own header made it taller than its pane), then the title on the left,
##                 "played / total" on the right (LIVE before it for a live stream, the trick play speed after it), and the time bar along the bottom with a tick at each
##                 chapter. The seek bar's picture (features.thumbs, System "Seek bar pictures") shows over the bar,
##                 with its time, where the laser is on the bar (hover_bar()) or where it is dragged. bar_fraction(point)
##                 gives the place in the film for a point on or near the bar, for touching it or the laser. Under it a
##                 band (CONTROLS_HEIGHT) where the menu's transport and picture toggles sit (the user, 2026-11-06):
##                 the menu's panel reaches up over the gap into it (panel_rect(), menu_band()).
##   main          below it, for everything else, 25 % deeper than at first (the user: the top stays, the bottom
##                 comes down). The old menu sits on it (the user, 2026-11-04: moved here, reshaped, its lists
##                 dragged): ui_layer.gd puts the panel (ui/pane.gd, in pane_ui.gd's tablet layout) at
##                 panel_transform(), panel_rect() in size, panel_pixels() in resolution; the tabs and their parts as
##                 lists down its left, the tab in the rest of the width.
##
## Its look is one JSON document, all of it themable from outside (the assistant, in time). The defaults are
## ui/themes/tablet.json; set_style() merges a partial document over them, checked against SCHEMA (nothing changes
## if any of it is wrong), and keeps the changes in [pane] tablet_style; null puts a value back to the default.
##   fade          in, out: seconds
##   palette       the name of the palette in use (one of palettes); palettes: {name: {name (shown), plate, edge,
##                 ink, ink2, accent, accent_ink}} (colours: "#rrggbb" or "#rrggbbaa", the last pair the opacity).
##                 The palette colours the panes (plate, edge), the now playing text and bar (ink, ink2, accent) and
##                 the menu (menu_colours(): the theme's text, muted, accent and fills, PaneStyle.tablet_theme()).
##                 The user, 2026-11-04: plum and gold first, the other dark ones a choice in System.
##   pane          corner_radius, border_width: metres; fill, border: colours, when given they beat the palette's
##                 plate and edge. Each pane is a rounded rectangle (shaders/tablet.gdshader), nothing drawn outside
##                 its border. Frosted glass will be another kind of fill here.
##   now_playing   padding (metres, at the sides); spacing (metres between the lines and the bar: they are all
##                 centred together, top to bottom); status (the small line's text), title and time: size (the font's size, metres), font (one of
##                 the theme's: FONTS), color (when given, else the palette's ink and ink2); bar: height,
##                 corner_radius (metres), track, played (colours, when given, else from the palette)
##   panel         inset (metres between the main pane's edge and the menu on it), px_per_m (the menu's layout pixels
##                 per metre: its theme is in pixels, so this sets how big it all is; the front panel's is 3080 at
##                 scale 1, the tablet's 2053, half as big again, the user 2026-11-04), render_scale (drawn pixels per
##                 layout pixel: keeps the bigger text sharp), text_scale (its font sizes times this: the text
##                 half as big again once more, the user 2026-11-04, without making the rows and lists bigger)
##
## Placement, from the head's position and its heading (yaw only, so looking down when pressing doesn't sink it):
## FORWARD metres ahead and DOWN metres below the eyes, the centre about 44° below the horizon, about half a metre
## away; its face tilted TILT degrees back from vertical (the user, 2026-11-04: a little more upright than 45°, a
## little smaller, 5 cm closer).
##
##   toggle(head), show_at(head), hide_tablet(), is_shown(); hover_bar(fraction) (the laser on the bar, -1 off it)
##   style() -> Dictionary, set_style(changes, save := true) -> Array (errors), reset_style()
##   now_playing, main_pane    the two panes (MeshInstance3D); title_label, time_label (Label3D)
##   bar_rect() -> Rect2 (now playing pane's space), bar_fraction(global_point) -> float (-1: not on the bar)
##   panel_rect() -> Rect2 (tablet space), panel_pixels() -> Vector2i, panel_transform() -> Transform3D, place(head);
##   signal layout_changed (on, off, or a style change: the menu on it is placed again)
##   ray_hit(origin, direction) -> {point, distance, pane, fraction} or {};
##   poke_probe(point) -> {depth, point (on the plane), fraction}
##   grab(point) -> bool, grab_move(point), release() -> bool, is_grabbing(): the bar, by the trigger or a touch
##   (ui_layer.gd)
##   plane_point(origin, direction) -> Variant (the ray on the tablet's plane, or null); along_bar(point) -> 0..1
##   seek_to(fraction) -> bool; begin_scrub(fraction) -> bool, scrub(fraction), end_scrub(), scrubbing
## Input (ui_layer.gd): the pointer controller's laser shows on either pane. The time bar is dragged: the trigger held
## on it, or a controller's tip pushed through it, then moved along it, and let go (the trigger released, the tip
## pulled back out) where the film should be. While dragging, the bar and the time follow at once, the film skips
## there at most every SCRUB_SEEK seconds, and exactly where it is let go. The menu takes its own input (ui/pane.gd);
## anywhere else on the tablet the trigger is taken (nothing happens), so it doesn't pause the film by accident.
##   static pane_rects() -> {name: Rect2} in metres, static validate(doc, partial) -> Array (errors)
##   static pose(head) -> Transform3D

signal layout_changed

## Metres: the now playing pane's height, the gap below it, and the main pane's height (0.19 at first, then 25 %
## deeper, downwards).
## The band at the bottom of the now playing pane for the transport and the toggles (the menu's), metres.
const CONTROLS_HEIGHT := 0.028
const NOW_PLAYING_HEIGHT := 0.06 + CONTROLS_HEIGHT
const GAP := 0.01
const MAIN_HEIGHT := 0.2375
## Metres: the whole tablet's size (landscape), and its top edge above the point it is placed at (pose()).
const SIZE := Vector2(0.48, NOW_PLAYING_HEIGHT + GAP + MAIN_HEIGHT)
## Grown by the band, so the main pane stays where it was (the user's place for it).
const TOP_EDGE := 0.13 + CONTROLS_HEIGHT
const FORWARD := 0.35
const DOWN := 0.34
## Degrees the face tilts back from vertical: 45 would face a point 45° below the horizon.
const TILT := 35.0
const PaneStyle := preload("res://ui/pane_style.gd")
const W := preload("res://ui/pane_widgets.gd")
const SHADER := preload("res://shaders/tablet.gdshader")
const MakeTheme := preload("res://tools/make_pane_theme.gd")
const STYLE_PATH := "res://ui/themes/tablet.json"
const FONTS := ["light", "regular", "medium", "semibold", "label"]
## The style's shape: a leaf is "color", "font" or [min, max] (a number).
const SCHEMA := {
	"fade": {"in": [0.0, 2.0], "out": [0.0, 2.0]},
	"palette": "string",
	"palettes": {"*": {"name": "string", "plate": "color", "edge": "color", "ink": "color", "ink2": "color",
			"accent": "color", "accent_ink": "color"}},
	"pane": {"fill": "color", "border": "color", "corner_radius": [0.0, 0.13], "border_width": [0.0, 0.03]},
	"now_playing": {
		"padding": [0.0, 0.025],
		"spacing": [0.0, 0.03],
		"status": {"color": "color", "size": [0.003, 0.02], "font": "font"},
		"title": {"color": "color", "size": [0.004, 0.03], "font": "font"},
		"time": {"color": "color", "size": [0.004, 0.03], "font": "font"},
		"bar": {"track": "color", "played": "color", "height": [0.001, 0.02], "corner_radius": [0.0, 0.01]},
	},
	"panel": {"inset": [0.0, 0.03], "px_per_m": [1000, 8000], "render_scale": [1.0, 3.0], "text_scale": [0.5, 3.0]},
}
## Label3D: the font's pixels per em (pixel_size makes it the style's size in metres).
const FONT_PX := 96
## Metres the text and the bar sit in front of the pane, so they never fight it for depth.
const LIFT := 0.0008
## Metres round the bar that still count as on it: the bar is thin, a finger or a laser is not.
const BAR_HIT := Vector2(0.006, 0.012)
## Metres between the title and the time.
const TEXT_GAP := 0.02
## Metres: the seek bar's picture (16:9; the picture keeps its own shape inside), the gap under it, and a chapter
## tick (its width, and its height as the bar's times this).
const THUMB_SIZE := Vector2(0.096, 0.054)
const THUMB_GAP := 0.006
const TICK_WIDTH := 0.0012
const TICK_HEIGHT := 2.5
## Seconds between skips while the bar is dragged.
const SCRUB_SEEK := 0.25
## The visual middle of capitals and figures above the baseline, as a share of the font's size (Label3D centres the
## line box, ascent over descent, which puts the letters off the middle).
const CAP_MIDDLE := 0.36

var app: Node3D
var now_playing: MeshInstance3D
var main_pane: MeshInstance3D
var title_label: Label3D
var time_label: Label3D
## The small line over the title: the chapter (left) and the status (right).
var chapter_label: Label3D
var status_label: Label3D
var _chapter_full := ""
var _labels: Array[Label3D] = []
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
## Dragging the bar: where it is (0..1), where the film last skipped to, and when.
var scrubbing := false
var _scrub := 0.0
var _scrub_sought := -1.0
var _scrub_at := 0.0
## The chapters' places on the bar (0..1) and their ticks.
var _ticks := PackedFloat32Array()
var _tick_meshes: Array[MeshInstance3D] = []
## The laser on the bar (0..1; -1 off it), and the seek bar's picture over the bar and its time.
var _hover := -1.0
var thumb: MeshInstance3D
var thumb_label: Label3D


func _ready() -> void:
	_defaults = _load_defaults()
	var rects := pane_rects()
	now_playing = _pane("NowPlaying", rects["now_playing"])
	main_pane = _pane("Main", rects["main"])
	title_label = make_label("Title", HORIZONTAL_ALIGNMENT_LEFT, now_playing)
	time_label = make_label("Time", HORIZONTAL_ALIGNMENT_RIGHT, now_playing)
	chapter_label = make_label("Chapter", HORIZONTAL_ALIGNMENT_LEFT, now_playing)
	status_label = make_label("Status", HORIZONTAL_ALIGNMENT_RIGHT, now_playing)
	_bar_track = _bar("BarTrack", "track", 1)
	_bar_played = _bar("BarPlayed", "played", 2)
	thumb = MeshInstance3D.new()
	thumb.name = "Thumb"
	var quad := QuadMesh.new()
	quad.size = THUMB_SIZE
	thumb.mesh = quad
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.cull_mode = BaseMaterial3D.CULL_DISABLED
	tm.no_depth_test = true
	tm.render_priority = PRIORITY_BASE + 3
	thumb.material_override = tm
	thumb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	thumb.visible = false
	now_playing.add_child(thumb)
	thumb_label = make_label("ThumbTime", HORIZONTAL_ALIGNMENT_CENTER, now_playing)
	thumb_label.visible = false
	visible = false
	if app != null:
		var saved: Variant = app.settings.get_value("pane", "tablet_style", {})
		if saved is Dictionary and validate(saved, true).is_empty():
			_overrides = (saved as Dictionary).duplicate(true)
	_apply_style()
	_set_opacity(0.0)


func _process(_delta: float) -> void:
	if scrubbing and app != null and not is_equal_approx(_scrub, _scrub_sought):
		var now := Time.get_ticks_msec() / 1000.0
		if now - _scrub_at >= SCRUB_SEEK:
			_scrub_at = now
			_scrub_sought = _scrub
			_seek(_scrub)
	if visible and app != null:
		_update_now_playing()
		_update_thumb()


# --- Showing ------------------------------------------------------------------------------------------------------

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
	release()
	_shown = false
	_hover = -1.0
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
	for l in _labels:
		l.modulate.a = _alpha(l)
	if thumb != null:
		(thumb.material_override as StandardMaterial3D).albedo_color.a = v


# --- Now playing --------------------------------------------------------------------------------------------------

func _update_now_playing() -> void:
	var player: Object = app.player
	var has := bool(player.has_source())
	var title: String = app.display_title() if has else ""
	if title != _title_full:
		_title_full = title
		_title_fit = -1.0
	var dur: float = player.get_duration() if has else 0.0
	var pos: float = (_scrub * dur if scrubbing else player.get_position()) if has else 0.0
	var t := ""
	if has:
		t = "%s / %s" % [W.clock(pos), W.clock(dur)] if dur > 0.0 else (W.clock(pos) if pos > 0.0 else "")
		var f: Node = app.get("features")
		var live: Node = f.get("live") if f != null else null
		if live != null and bool(live.live):
			t = tr("LIVE") + (("  " + t) if t != "" else "")
		var trick: Node = f.get("trick") if f != null else null
		if trick != null and float(trick.speed) > 0.0:
			t += "  ·  %dx" % roundi(float(trick.speed))
		var chapters: Node = f.get("chapters") if f != null else null
		_set_ticks(chapters.tick_positions() if chapters != null else PackedFloat32Array())
	else:
		_set_ticks(PackedFloat32Array())
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
	title_label.text = _cut(title_label, text, room)


## Text cut with an ellipsis to fit a width (metres) in a label's font and size.
func _cut(l: Label3D, text: String, room: float) -> String:
	if _text_width(l, text) <= room:
		return text
	while text.length() > 1 and _text_width(l, text + "…") > room:
		text = text.left(-1)
	return text.strip_edges() + "…"


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


## The small line over the title: the chapter (left, cut to the room the status leaves) and the status (right), from
## the menu (ui_layer.gd, a few times a second).
func set_header(chapter: String, status: String) -> void:
	if chapter == _chapter_full and status == status_label.text:
		return
	_chapter_full = chapter
	status_label.text = status
	var r: Rect2 = pane_rects()["now_playing"]
	var pad := float(_get(style(), "now_playing/padding"))
	var room := maxf(r.size.x - 2.0 * pad - _text_width(status_label, status) - TEXT_GAP, 0.0)
	chapter_label.text = _cut(chapter_label, chapter, room)


## The chapters' ticks on the bar (fractions 0..1), made again when they change.
func _set_ticks(ticks: PackedFloat32Array) -> void:
	if ticks == _ticks:
		return
	_ticks = ticks
	for mi in _tick_meshes:
		_mats.erase(mi.material_override)
		mi.queue_free()
	_tick_meshes.clear()
	var bar := bar_rect()
	var colour := _colour(style(), "now_playing/bar/tick", palette()["ink2"])
	for f in ticks:
		var mi := _rounded("Tick", Vector2(TICK_WIDTH, bar.size.y * TICK_HEIGHT), "tick", 3)
		(mi.material_override as ShaderMaterial).set_shader_parameter("fill_color", colour)
		(mi.material_override as ShaderMaterial).set_shader_parameter("border_width", 0.0)
		mi.position = Vector3(bar.position.x + bar.size.x * f, bar.get_center().y, LIFT * 3.0)
		now_playing.add_child(mi)
		_tick_meshes.append(mi)


## The chapter ticks on show (tests).
func tick_count() -> int:
	return _tick_meshes.size()


## The laser on the time bar (ui_layer.gd, each frame): its place 0..1, -1 off it. The seek bar's picture shows there.
func hover_bar(fraction: float) -> void:
	_hover = fraction


## The seek bar's picture: where the bar is dragged, else where the laser is on it; only with features.thumbs on and
## a picture to show (asked for here; the newest asked wins).
func _update_thumb() -> void:
	var f := _scrub if scrubbing else _hover
	var features: Node = app.get("features")
	var thumbs: Node = features.get("thumbs") if features != null else null
	var dur: float = app.player.get_duration() if app.player.has_source() else 0.0
	var tex: Texture2D = null
	var t := f * dur
	if f >= 0.0 and thumbs != null and bool(thumbs.enabled) and dur > 0.0:
		thumbs.request(t)
		tex = thumbs.thumbnail_for(t)
	thumb.visible = tex != null
	thumb_label.visible = tex != null
	if tex == null:
		return
	var tm := thumb.material_override as StandardMaterial3D
	tm.albedo_texture = tex
	# The picture's own shape inside THUMB_SIZE.
	var aspect := float(tex.get_width()) / maxf(float(tex.get_height()), 1.0)
	var size := Vector2(THUMB_SIZE.y * aspect, THUMB_SIZE.y)
	if size.x > THUMB_SIZE.x:
		size = Vector2(THUMB_SIZE.x, THUMB_SIZE.x / aspect)
	(thumb.mesh as QuadMesh).size = size
	var bar := bar_rect()
	var half := NOW_PLAYING_HEIGHT * 0.5
	var r: Rect2 = pane_rects()["now_playing"]
	var x := clampf(bar.position.x + bar.size.x * f, -r.size.x * 0.5 + size.x * 0.5, r.size.x * 0.5 - size.x * 0.5)
	var y := half + THUMB_GAP + size.y * 0.5
	thumb.position = Vector3(x, y, LIFT * 4.0)
	var time_style: Dictionary = (_get(style(), "now_playing/time") as Dictionary).duplicate()
	time_style["color"] = _colour(style(), "now_playing/time/color", palette()["ink"]).to_html()
	place_text(thumb_label, time_style, Vector2(x, y + size.y * 0.5 + THUMB_GAP + float(time_style["size"]) * 0.5))
	thumb_label.text = W.clock(t)


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


## For touching: how far the point is in front of the tablet (negative behind it), the point on the tablet's plane
## under it, and the bar fraction there (-1 off the bar).
func poke_probe(point: Vector3) -> Dictionary:
	var p := global_transform.affine_inverse() * point
	var on := global_transform * Vector3(p.x, p.y, 0.0)
	return {"depth": p.z, "point": on, "fraction": bar_fraction(on) if _shown else -1.0}


# --- Grabbing -----------------------------------------------------------------------------------------------------

## A grab at a point (global, on the plane): on the time bar it starts a drag of the time. False when there is
## nothing there to grab (or the film can't skip).
func grab(point: Vector3) -> bool:
	if not _shown or is_grabbing():
		return false
	var f := bar_fraction(point)
	return f >= 0.0 and begin_scrub(f)


func grab_move(point: Vector3) -> void:
	if scrubbing:
		scrub(along_bar(point))


## Lets go of a grab. True when it ended a drag of the time.
func release() -> bool:
	if scrubbing:
		end_scrub()
		return true
	return false


func is_grabbing() -> bool:
	return scrubbing


# --- The menu on the main pane --------------------------------------------------------------------------------------

## The menu's rectangle in the tablet's space: the main pane, inset.
func panel_rect() -> Rect2:
	var inset := float(_get(style(), "panel/inset"))
	var main: Rect2 = (pane_rects()["main"] as Rect2).grow(-inset)
	var np: Rect2 = pane_rects()["now_playing"]
	# Up over the gap into the now playing pane's band, half an inset short of the band's top.
	return Rect2(main.position, Vector2(main.size.x, np.position.y + CONTROLS_HEIGHT - inset * 0.5 - main.position.y))


## The menu's top, in its pixels: {band: the band's height (the transport and toggles' row), gap: from the band's
## bottom to where the main pane's inside begins}. ui/pane_ui.gd lays its first rows out on these.
func menu_band() -> Dictionary:
	var inset := float(_get(style(), "panel/inset"))
	var px := float(_get(style(), "panel/px_per_m"))
	return {"band": roundi((CONTROLS_HEIGHT - inset * 0.5) * px), "gap": roundi((GAP + inset) * px)}


func panel_pixels() -> Vector2i:
	var px := float(_get(style(), "panel/px_per_m"))
	var size := panel_rect().size
	return Vector2i(roundi(size.x * px), roundi(size.y * px))


func panel_render_scale() -> float:
	return float(_get(style(), "panel/render_scale"))


func panel_text_scale() -> float:
	return float(_get(style(), "panel/text_scale"))


## Where the menu goes: on the main pane, a little in front of it.
func panel_transform() -> Transform3D:
	var c := panel_rect().get_center()
	return global_transform * Transform3D(Basis(), Vector3(c.x, c.y, LIFT * 3.0))


## Puts the tablet in its place for a head pose (shown or not).
func place(head: Transform3D) -> void:
	global_transform = pose(head)


## Skips the film to a fraction of its length. False when it can't (nothing playing, a live stream).
func seek_to(fraction: float) -> bool:
	if not can_seek():
		return false
	_seek(fraction)
	_update_now_playing()
	return true


func can_seek() -> bool:
	return app != null and app.player.has_source() and app.player.can_seek() and app.player.get_duration() > 0.0


func _seek(fraction: float) -> void:
	app.player.seek(clampf(fraction, 0.0, 1.0) * float(app.player.get_duration()))


## Where a ray meets the tablet's plane (global), or null when it points away from it.
func plane_point(origin: Vector3, direction: Vector3) -> Variant:
	var inv := global_transform.affine_inverse()
	var o := inv * origin
	var d := inv.basis * direction
	if absf(d.z) < 1e-6 or (o.z > 0.0) == (d.z > 0.0):
		return null
	return global_transform * (o + d * (-o.z / d.z))


## How far along the bar a point (global) is, 0 to 1, wherever it is beside the bar: for dragging.
func along_bar(point: Vector3) -> float:
	var bar := bar_rect()
	return clampf((now_playing.to_local(point).x - bar.position.x) / bar.size.x, 0.0, 1.0)


## Dragging the bar: begin_scrub() where it was pressed, scrub() as it moves, end_scrub() where it is let go (the film
## goes there). begin_scrub() is false when the film can't skip.
func begin_scrub(fraction: float) -> bool:
	if not can_seek():
		return false
	scrubbing = true
	_scrub_sought = -1.0
	_scrub_at = 0.0
	scrub(fraction)
	return true


func scrub(fraction: float) -> void:
	if not scrubbing:
		return
	_scrub = clampf(fraction, 0.0, 1.0)
	if app != null:
		_update_now_playing()


func end_scrub() -> void:
	if not scrubbing:
		return
	scrubbing = false
	if can_seek() and not is_equal_approx(_scrub, _scrub_sought):
		_seek(_scrub)
	if app != null:
		_update_now_playing()


## The time bar's rectangle in the now playing pane's space (metres from its centre).
func bar_rect() -> Rect2:
	var s := style()
	var r: Rect2 = pane_rects()["now_playing"]
	var pad := float(_get(s, "now_playing/padding"))
	var h := float(_get(s, "now_playing/bar/height"))
	return Rect2(-r.size.x * 0.5 + pad, -_block_height(s) * 0.5 + INFO_SHIFT, r.size.x - 2.0 * pad, h)


## The text row's height (its capitals), metres.
static func _text_height(s: Dictionary) -> float:
	return maxf(float(_get(s, "now_playing/title/size")), float(_get(s, "now_playing/time/size"))) * CAP_MIDDLE * 2.0


## The lines and the bar are centred in the now playing pane above its band: their middle this far above the pane's.
const INFO_SHIFT := CONTROLS_HEIGHT * 0.5


## The small status line's height (its capitals), metres.
static func _status_height(s: Dictionary) -> float:
	return float(_get(s, "now_playing/status/size")) * CAP_MIDDLE * 2.0


## The status line, the text row and the bar together, top to bottom: they are centred in the pane as one.
static func _block_height(s: Dictionary) -> float:
	return _status_height(s) + _text_height(s) + 2.0 * float(_get(s, "now_playing/spacing")) \
			+ float(_get(s, "now_playing/bar/height"))


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
		if not schema.has(key) and not schema.has("*"):
			errors.append({"path": at, "error": "one of " + ", ".join(schema.keys())})
			continue
		var v: Variant = doc[k]
		var want: Variant = schema[key] if schema.has(key) else schema["*"]
		if v == null:
			if not partial:
				errors.append({"path": at, "error": "a value"})
		elif want is Dictionary:
			errors.append_array(validate(v, partial, want, at))
		elif want is String and want == "string":
			if not (v is String) or (v as String).strip_edges() == "":
				errors.append({"path": at, "error": "a name"})
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


## The palette in use ({name, plate, edge, ink, ink2, accent, accent_ink} as Colors): style()'s "palette" among its
## "palettes", or the first of them.
func palette() -> Dictionary:
	var s := style()
	var all: Variant = _get(s, "palettes")
	if not (all is Dictionary) or (all as Dictionary).is_empty():
		# Changed away from outside: the shipped ones.
		all = _get(_defaults, "palettes")
	var want := str(_get(s, "palette"))
	var doc: Dictionary = all[want] if all.has(want) else all[all.keys()[0]]
	var out := {}
	for k: String in doc:
		out[k] = Color.html(doc[k]) if k != "name" else doc[k]
	return out


## The palettes on offer, in the document's order: [{id, name}].
func palette_names() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var all: Variant = _get(style(), "palettes")
	if all is Dictionary:
		for id: String in all:
			out.append({"id": id, "name": str((all[id] as Dictionary).get("name", id))})
	return out


func palette_id() -> String:
	var all: Variant = _get(style(), "palettes")
	var want := str(_get(style(), "palette"))
	if all is Dictionary and (all as Dictionary).has(want):
		return want
	return str((all as Dictionary).keys()[0]) if all is Dictionary and not (all as Dictionary).is_empty() else ""


## The menu's colour tokens for the palette (tools/make_pane_theme.gd palette_colours()).
func menu_colours() -> Dictionary:
	return MakeTheme.palette_colours(palette())


## A colour from the style at path when it is given, else the palette's.
func _colour(s: Dictionary, path: String, fallback: Color) -> Color:
	var v: Variant = _get(s, path)
	return Color.html(v) if v is String and Color.html_is_valid(v) else fallback


func _apply_style() -> void:
	if now_playing == null:
		return
	var s := style()
	var pal := palette()
	var menu := menu_colours()
	for m in _mats:
		var role := str(m.get_meta("role", "pane"))
		if role == "pane":
			m.set_shader_parameter("fill_color", _colour(s, "pane/fill", pal["plate"]))
			m.set_shader_parameter("border_color", _colour(s, "pane/border", pal["edge"]))
			m.set_shader_parameter("corner_radius", float(_get(s, "pane/corner_radius")))
			m.set_shader_parameter("border_width", float(_get(s, "pane/border_width")))
		else:
			var fallback: Color = pal["accent"] if role == "played" else (pal["ink2"] if role == "tick" else menu["bar_track"])
			m.set_shader_parameter("fill_color", _colour(s, "now_playing/bar/" + role, fallback))
			m.set_shader_parameter("corner_radius", float(_get(s, "now_playing/bar/corner_radius")))
			m.set_shader_parameter("border_width", 0.0)
	var r: Rect2 = pane_rects()["now_playing"]
	var pad := float(_get(s, "now_playing/padding"))
	# The middle of each line: the capitals' middle goes there. The status line on top, then the title and time.
	var status_mid := _block_height(s) * 0.5 - _status_height(s) * 0.5 + INFO_SHIFT
	var text_mid := _block_height(s) * 0.5 - _status_height(s) - float(_get(s, "now_playing/spacing")) \
			- _text_height(s) * 0.5 + INFO_SHIFT
	for row: Array in [[chapter_label, -r.size.x * 0.5 + pad], [status_label, r.size.x * 0.5 - pad]]:
		var st: Dictionary = (_get(s, "now_playing/status") as Dictionary).duplicate()
		st["color"] = _colour(s, "now_playing/status/color", pal["ink2"]).to_html()
		place_text(row[0], st, Vector2(float(row[1]), status_mid))
	for row: Array in [[title_label, "title", -r.size.x * 0.5 + pad, pal["ink"]],
			[time_label, "time", r.size.x * 0.5 - pad, pal["ink2"]]]:
		var key: String = row[1]
		var text_style: Dictionary = (_get(s, "now_playing/" + key) as Dictionary).duplicate()
		text_style["color"] = _colour(s, "now_playing/%s/color" % key, row[3]).to_html()
		place_text(row[0], text_style, Vector2(float(row[2]), text_mid))
	var bar := bar_rect()
	(_bar_track.mesh as QuadMesh).size = bar.size
	(_bar_track.material_override as ShaderMaterial).set_shader_parameter("size", bar.size)
	_bar_track.position = Vector3(bar.get_center().x, bar.get_center().y, LIFT)
	_fraction = -1.0
	_title_fit = -1.0
	# The ticks placed on the bar again (its size may have changed).
	var ticks := _ticks
	_ticks = PackedFloat32Array([-1.0])
	_set_ticks(ticks)
	if app != null:
		_update_now_playing()
	layout_changed.emit()


## A label's font, size and colour from a text style ({color, size, font}), its capitals' middle at at.y and its
## start (or end, aligned right) at at.x, just in front of its pane.
func place_text(l: Label3D, text_style: Dictionary, at: Vector2) -> void:
	_font(l, text_style)
	tint(l, Color.html(text_style["color"]))
	# Label3D centres its line box (ascent over descent): moved so the capitals' middle is on at.y.
	var box_mid := 0.0
	if l.font != null:
		box_mid = (l.font.get_ascent(FONT_PX) - l.font.get_descent(FONT_PX)) * 0.5 * l.pixel_size
	l.position = Vector3(at.x, at.y - (box_mid - float(text_style["size"]) * CAP_MIDDLE), LIFT * 2.0)


func _font(l: Label3D, text_style: Dictionary) -> void:
	l.font = PaneStyle.font(StringName(str(text_style["font"])))
	l.pixel_size = float(text_style["size"]) / FONT_PX


## A label's colour, its own opacity kept apart from the fade's.
func tint(l: Label3D, c: Color) -> void:
	l.set_meta("alpha", c.a)
	l.modulate = c
	l.modulate.a = _alpha(l)


func _alpha(l: Label3D) -> float:
	return _opacity * float(l.get_meta("alpha", 1.0))


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

## Each pane's rectangle on the tablet, in metres from the point it is placed at (+y towards the top edge, away
## from the eyes): the top edge at TOP_EDGE, the main pane below the now playing one.
static func pane_rects() -> Dictionary:
	var np_bottom := TOP_EDGE - NOW_PLAYING_HEIGHT
	return {"now_playing": Rect2(-SIZE.x * 0.5, np_bottom, SIZE.x, NOW_PLAYING_HEIGHT),
			"main": Rect2(-SIZE.x * 0.5, np_bottom - GAP - MAIN_HEIGHT, SIZE.x, MAIN_HEIGHT)}


func _pane(p_name: String, r: Rect2) -> MeshInstance3D:
	var mi := _rounded(p_name, r.size, "pane", 0)
	mi.position = Vector3(r.get_center().x, r.get_center().y, 0.0)
	add_child(mi)
	return mi


func _bar(p_name: String, role: String, priority: int) -> MeshInstance3D:
	var mi := _rounded(p_name, Vector2(0.01, 0.004), role, priority)
	now_playing.add_child(mi)
	return mi


## The tablet's draw order starts here, above the room's see-through effects (0, 1) and the windows to the real room
## (scripts/play/real_windows.gd PRIORITY, 2): a window drawn after the tablet would take it away.
const PRIORITY_BASE := 4


func _rounded(p_name: String, size: Vector2, role: String, priority: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = p_name
	var mesh := QuadMesh.new()
	mesh.size = size
	mi.mesh = mesh
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.render_priority = PRIORITY_BASE + priority
	m.set_shader_parameter("size", size)
	m.set_shader_parameter("opacity", _opacity)
	m.set_meta("role", role)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mats.append(m)
	return mi


## A label of the now playing pane. Its text shows as given (W.content(), docs/i18n.md): the title is the film's own,
## the times are numbers, LIVE and the header (chapter, status: ui/pane_ui.gd) come translated.
func make_label(p_name: String, align: HorizontalAlignment, parent: Node3D) -> Label3D:
	var l := Label3D.new()
	l.name = p_name
	W.content(l)
	l.font_size = FONT_PX
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.outline_size = 0
	l.render_priority = PRIORITY_BASE + 3
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(l)
	_labels.append(l)
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
