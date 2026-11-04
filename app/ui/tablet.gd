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
##   main          below it, for everything else, 25 % deeper than at first (the user: the top stays, the bottom
##                 comes down). Three columns of lists (ui/tablet_list.gd; lists, not buttons, the user: they take
##                 less room), a hairline between them:
##                   categories   CATEGORIES (as the front panel's tabs, Files called Source), one selected
##                   options      the selected category's parts: for Source the places (source_options(): the
##                                library and the lists first, folders, test patterns last), else OPTIONS
##                   content      the rest of the width, under a heading: for Source the files tab's rows (the same
##                                browser as the front panel: a folder opens, a file plays), else empty for now
##                 A list that doesn't fit scrolls: grabbed (the trigger held, or a tip pushed through it), dragged,
##                 and let go (the trigger released, the tip pulled back out), and a grab that hardly moves is a tap.
##
## Its look is one JSON document, all of it themable from outside (the assistant, in time). The defaults are
## ui/themes/tablet.json; set_style() merges a partial document over them, checked against SCHEMA (nothing changes
## if any of it is wrong), and keeps the changes in [pane] tablet_style; null puts a value back to the default.
##   fade          in, out: seconds
##   pane          fill, border: colours ("#rrggbb" or "#rrggbbaa", the last pair the opacity); corner_radius,
##                 border_width: metres. Each pane is a rounded rectangle (shaders/tablet.gdshader), nothing drawn
##                 outside its border. Frosted glass will be another kind of fill here.
##   now_playing   padding (metres, at the sides); spacing (metres between the text and the bar: the two are
##                 centred together, top to bottom); title and time: color, size (the font's size, metres), font (one
##                 of the theme's: FONTS); bar: track, played (colours), height, corner_radius (metres)
##   main          padding, gap (metres between the columns, the divider in its middle), categories_width,
##                 options_width, heading_height (metres); divider (colour)
##   list          row_height, corner_radius, text_inset, marker_width, thumb_width (metres); text: color, size,
##                 font; fill, hover_fill, selected_fill, selected_color (the selected row's text), marker (a slim
##                 mark at the selected row's left), thumb (where a list that scrolls is): colours
##   content       title: color, size, font (the heading over the content list)
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
##   categories_list, options_list, content_list (TabletList), content_title (Label3D); list_rects() (main pane's
##   space); category, select_category(i), option, select_option(i), options_for(category) -> [{label, path}],
##   signal category_changed(i); hover(point) (null: none) lights the row under the laser
##   ray_hit(origin, direction) -> {point, distance, pane, fraction, list} or {};
##   poke_probe(point) -> {depth, point (on the plane), fraction, list}
##   grab(point) -> bool, grab_move(point), release() -> bool, is_grabbing(): the bar or a list, by the trigger or a
##   touch (ui_layer.gd)
##   plane_point(origin, direction) -> Variant (the ray on the tablet's plane, or null); along_bar(point) -> 0..1
##   seek_to(fraction) -> bool; begin_scrub(fraction) -> bool, scrub(fraction), end_scrub(), scrubbing
## Input (ui_layer.gd): the pointer controller's laser shows on either pane. The time bar is dragged: the trigger held
## on it, or a controller's tip pushed through it, then moved along it, and let go (the trigger released, the tip
## pulled back out) where the film should be. While dragging, the bar and the time follow at once, the film skips
## there at most every SCRUB_SEEK seconds, and exactly where it is let go. The lists are grabbed the same way.
## Anywhere else on the tablet the trigger is taken (nothing happens), so it doesn't pause the film by accident.
##   static pane_rects() -> {name: Rect2} in metres, static validate(doc, partial) -> Array (errors)
##   static pose(head) -> Transform3D

signal category_changed(index: int)

## Metres: the now playing pane's height, the gap below it, and the main pane's height (0.19 at first, then 25 %
## deeper, downwards).
const NOW_PLAYING_HEIGHT := 0.06
const GAP := 0.01
const MAIN_HEIGHT := 0.2375
## Metres: the whole tablet's size (landscape), and its top edge above the point it is placed at (pose()).
const SIZE := Vector2(0.48, NOW_PLAYING_HEIGHT + GAP + MAIN_HEIGHT)
const TOP_EDGE := 0.13
const CATEGORIES: Array[String] = ["Source", "Picture", "Sound", "Subtitles", "Room", "Objects", "System"]
## Each category's parts (the front panel's sections, most used first); Source's are the places (source_options()).
const OPTIONS := {
	"Picture": ["Screen", "Picture", "Mode", "3D", "HDR", "Horizon", "Corner film", "Frame", "Slideshow"],
	"Sound": ["Audio track", "Level and timing", "Spatial sound", "Night mode", "Speed", "Play on a PC"],
	"Subtitles": ["Track", "Second track", "Look and timing", "Subtitle files", "Script"],
	"Room": ["Environment", "Showrooms", "Seat", "Placement", "Effects", "The showing", "Sleep timer", "Watch party"],
	"Objects": ["Library", "In this room"],
	"System": ["Views", "Panel", "Controllers", "Accessibility", "Rendering", "Hardware video", "Phone remote",
			"Share files", "Assistant", "Test and setup", "Dev tools", "About"],
}
const FORWARD := 0.35
const DOWN := 0.34
## Degrees the face tilts back from vertical: 45 would face a point 45° below the horizon.
const TILT := 35.0
const PaneStyle := preload("res://ui/pane_style.gd")
const W := preload("res://ui/pane_widgets.gd")
const SHADER := preload("res://shaders/tablet.gdshader")
const TabletList := preload("res://ui/tablet_list.gd")
const FilesTab := preload("res://ui/files_tab.gd")
const STYLE_PATH := "res://ui/themes/tablet.json"
const FONTS := ["light", "regular", "medium", "semibold", "label"]
## The style's shape: a leaf is "color", "font" or [min, max] (a number).
const SCHEMA := {
	"fade": {"in": [0.0, 2.0], "out": [0.0, 2.0]},
	"pane": {"fill": "color", "border": "color", "corner_radius": [0.0, 0.13], "border_width": [0.0, 0.03]},
	"now_playing": {
		"padding": [0.0, 0.025],
		"spacing": [0.0, 0.03],
		"title": {"color": "color", "size": [0.004, 0.03], "font": "font"},
		"time": {"color": "color", "size": [0.004, 0.03], "font": "font"},
		"bar": {"track": "color", "played": "color", "height": [0.001, 0.02], "corner_radius": [0.0, 0.01]},
	},
	"main": {
		"padding": [0.0, 0.03], "gap": [0.0, 0.03], "categories_width": [0.04, 0.2], "options_width": [0.04, 0.2],
		"heading_height": [0.0, 0.05], "divider": "color",
	},
	"list": {
		"row_height": [0.012, 0.05], "corner_radius": [0.0, 0.025], "text_inset": [0.0, 0.03],
		"marker_width": [0.0, 0.006], "thumb_width": [0.0005, 0.008],
		"text": {"color": "color", "size": [0.004, 0.03], "font": "font"},
		"fill": "color", "hover_fill": "color", "selected_fill": "color", "selected_color": "color", "marker": "color",
		"thumb": "color",
	},
	"content": {"title": {"color": "color", "size": [0.004, 0.04], "font": "font"}},
}
## Label3D: the font's pixels per em (pixel_size makes it the style's size in metres).
const FONT_PX := 96
## Metres the text and the bar sit in front of the pane, so they never fight it for depth.
const LIFT := 0.0008
## Metres round the bar that still count as on it: the bar is thin, a finger or a laser is not.
const BAR_HIT := Vector2(0.006, 0.012)
## Metres between the title and the time.
const TEXT_GAP := 0.02
## Seconds between skips while the bar is dragged.
const SCRUB_SEEK := 0.25
## The visual middle of capitals and figures above the baseline, as a share of the font's size (Label3D centres the
## line box, ascent over descent, which puts the letters off the middle).
const CAP_MIDDLE := 0.36

var app: Node3D
var enabled := false
var now_playing: MeshInstance3D
var main_pane: MeshInstance3D
var title_label: Label3D
var time_label: Label3D
## The selected category (CATEGORIES) and its selected option (the place, for Source); each category's last.
var category := 0
var option := 0
var _options := {}
var categories_list: TabletList
var options_list: TabletList
var content_list: TabletList
var content_title: Label3D
var _dividers: Array[MeshInstance3D] = []
## The list being grabbed (null: none), and the files tab's folder the content list shows.
var _grab_list: TabletList
var _content_folder := ""
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


func _ready() -> void:
	_defaults = _load_defaults()
	var rects := pane_rects()
	now_playing = _pane("NowPlaying", rects["now_playing"])
	main_pane = _pane("Main", rects["main"])
	title_label = make_label("Title", HORIZONTAL_ALIGNMENT_LEFT, now_playing)
	time_label = make_label("Time", HORIZONTAL_ALIGNMENT_RIGHT, now_playing)
	categories_list = _list("Categories")
	options_list = _list("Options")
	content_list = _list("Content")
	for i in 2:
		_dividers.append(make_quad("Divider%d" % i, "divider", main_pane, 1))
	content_title = make_label("ContentTitle", HORIZONTAL_ALIGNMENT_LEFT, main_pane)
	categories_list.picked.connect(select_category)
	options_list.picked.connect(select_option)
	content_list.picked.connect(_on_content_picked)
	_bar_track = _bar("BarTrack", "track", 1)
	_bar_played = _bar("BarPlayed", "played", 2)
	visible = false
	if app != null:
		enabled = bool(app.settings.get_value("pane", "tablet", false))
		var saved: Variant = app.settings.get_value("pane", "tablet_style", {})
		if saved is Dictionary and validate(saved, true).is_empty():
			_overrides = (saved as Dictionary).duplicate(true)
		var files := _files()
		if files != null:
			files.listing_changed.connect(func() -> void:
				if category == 0:
					option = _source_option(options_for(0))
					options_list.select(option)
					_fill_content())
	_apply_style()
	categories_list.set_items(CATEGORIES)
	categories_list.select(category)
	_fill_options()
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
	release()
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
	for l in _labels:
		l.modulate.a = _alpha(l)


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
					"fraction": bar_fraction(world) if key == "now_playing" else -1.0,
					"list": _list_name(list_at(world)) if key == "main" else ""}
	return {}


## For touching: how far the point is in front of the tablet (negative behind it), the point on the tablet's plane
## under it, and the bar fraction (-1 off the bar) and list ("" none) there.
func poke_probe(point: Vector3) -> Dictionary:
	var p := global_transform.affine_inverse() * point
	var on := global_transform * Vector3(p.x, p.y, 0.0)
	return {"depth": p.z, "point": on, "fraction": bar_fraction(on) if _shown else -1.0,
			"list": _list_name(list_at(on)) if _shown else ""}


# --- Grabbing -----------------------------------------------------------------------------------------------------

## A grab at a point (global, on the plane): the time bar starts a drag of the time, a list a drag of its rows.
## False when there is nothing there to grab (or the film can't skip).
func grab(point: Vector3) -> bool:
	if not _shown or is_grabbing():
		return false
	var f := bar_fraction(point)
	if f >= 0.0:
		return begin_scrub(f)
	var l := list_at(point)
	if l != null and l.grab(_main_point(point)):
		_grab_list = l
		return true
	return false


func grab_move(point: Vector3) -> void:
	if scrubbing:
		scrub(along_bar(point))
	elif _grab_list != null:
		_grab_list.drag(_main_point(point))


## Lets go of a grab. True when it picked a row (a tap) or ended a drag of the time.
func release() -> bool:
	if scrubbing:
		end_scrub()
		return true
	if _grab_list != null:
		var l := _grab_list
		_grab_list = null
		return l.release()
	return false


func is_grabbing() -> bool:
	return scrubbing or _grab_list != null


## The laser on the tablet (global, null: off it): the row under it lights up.
func hover(point: Variant) -> void:
	for l: TabletList in [categories_list, options_list, content_list]:
		l.set_hover(_main_point(point) if point is Vector3 and _shown else null)


# --- The lists ----------------------------------------------------------------------------------------------------

## The list at a point (global) on the main pane, or null.
func list_at(point: Vector3) -> TabletList:
	var p := _main_point(point)
	for l: TabletList in [categories_list, options_list, content_list]:
		if l.rect.has_point(p):
			return l
	return null


## The lists' rectangles in the main pane's space: the categories, the options, and the content under its heading;
## and "heading" (the content's).
func list_rects(s: Dictionary = style()) -> Dictionary:
	var r: Rect2 = pane_rects()["main"]
	var pad := float(_get(s, "main/padding"))
	var gap := float(_get(s, "main/gap"))
	var top := r.size.y * 0.5 - pad
	var h := r.size.y - pad * 2.0
	var x := -r.size.x * 0.5 + pad
	var cw := float(_get(s, "main/categories_width"))
	var ow := float(_get(s, "main/options_width"))
	var cats := Rect2(x, top - h, cw, h)
	var opts := Rect2(cats.end.x + gap, top - h, ow, h)
	var content_x := opts.end.x + gap
	var heading := float(_get(s, "main/heading_height"))
	var content_w := r.size.x * 0.5 - pad - content_x
	return {"categories": cats, "options": opts, "heading": Rect2(content_x, top - heading, content_w, heading),
			"content": Rect2(content_x, top - h, content_w, h - heading)}


func select_category(i: int) -> void:
	if i < 0 or i >= CATEGORIES.size():
		return
	var changed := i != category
	category = i
	categories_list.select(i)
	if changed:
		_fill_options()
		category_changed.emit(i)


## An option of the selected category: for Source, its place opens in the files tab (and the content lists it).
func select_option(i: int) -> void:
	var opts := options_for(category)
	if i < 0 or i >= opts.size():
		return
	option = i
	_options[category] = i
	options_list.select(i)
	var files := _files()
	if category == 0 and files != null:
		files.open_folder(str(opts[i]["path"]))
	_fill_content()


## A category's options, [{label, path}] (path only for Source's places).
func options_for(i: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if i == 0:
		return source_options(FilesTab.get_places())
	for label: String in OPTIONS.get(CATEGORIES[i], []):
		out.append({"label": label, "path": ""})
	return out


## The places in the order the tablet offers them: the library and the lists first, then the network, then folders
## on the headset, the agents, and the test patterns last.
static func source_options(places: Array[Dictionary]) -> Array[Dictionary]:
	var first: Array[String] = [FilesTab.LibraryIndex.root(), FilesTab.FAVOURITES_FOLDER, FilesTab.QUEUE_FOLDER,
			FilesTab.SEARCH_FOLDER, FilesTab.NETWORK_FOLDER, FilesTab.MEDIA_SERVERS_FOLDER, FilesTab.ANDROID_FOLDER,
			FilesTab.BROWSER_FOLDER]
	var top: Array[Dictionary] = []
	var folders: Array[Dictionary] = []
	var agents: Array[Dictionary] = []
	var last: Array[Dictionary] = []
	for p: Dictionary in places:
		var path := str(p["path"])
		if path in first:
			top.append(p)
		elif path.begins_with(FilesTab.AGENT_PREFIX):
			agents.append(p)
		elif path == FilesTab.PATTERNS_FOLDER:
			last.append(p)
		else:
			folders.append(p)
	top.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return first.find(str(a["path"])) < first.find(str(b["path"])))
	return top + folders + agents + last


func _fill_options() -> void:
	var opts := options_for(category)
	var labels: Array[String] = []
	for o: Dictionary in opts:
		labels.append(str(o["label"]))
	options_list.set_items(labels)
	option = int(_options.get(category, 0))
	var files := _files()
	if category == 0 and files != null:
		option = _source_option(opts)
	options_list.select(option)
	_fill_content()


## The place the files tab is in, the nearest that holds it (Videos, not Home; the front panel may have moved it;
## -1: none of them).
func _source_option(opts: Array[Dictionary]) -> int:
	var files := _files()
	if files == null:
		return -1
	var best := -1
	for k in opts.size():
		var p := str(opts[k]["path"])
		if p != "" and (files.current == p or files.current.begins_with(p.trim_suffix("/") + "/")) \
				and (best < 0 or p.length() > str(opts[best]["path"]).length()):
			best = k
	return best


## The content list: the files tab's rows for Source (a folder's, the library's, the queue's ...), else nothing yet.
func _fill_content() -> void:
	var texts: Array[String] = []
	var heading := ""
	var opts := options_for(category)
	if option >= 0 and option < opts.size():
		heading = str(opts[option]["label"])
	var files := _files()
	var marked := -1
	if category == 0 and files != null:
		var rows: Array[Dictionary] = files.rows()
		for k in rows.size():
			texts.append(str(rows[k].get("text", "")))
			if str(rows[k].get("kind", "")) == "file" and str(rows[k].get("path", "")) == files.active_path:
				marked = k
		if files.path_text() != "":
			heading = files.path_text()
		var same: bool = files.current == _content_folder
		_content_folder = files.current
		content_list.set_items(texts, same)
	else:
		_content_folder = ""
		content_list.set_items(texts)
	content_list.select(marked)
	content_title.text = _cut(content_title, heading, list_rects()["heading"].size.x)


func _on_content_picked(i: int) -> void:
	var files := _files()
	if category == 0 and files != null:
		files.press_row(i)


func _files() -> Node:
	if app == null or app.get("ui") == null or app.ui.get("ui") == null:
		return null
	return app.ui.ui.files


func _list_name(l: TabletList) -> String:
	return "" if l == null else str(l.name).to_snake_case()


## A global point in the main pane's space (the lists' space).
func _main_point(point: Vector3) -> Vector2:
	var p := main_pane.to_local(point)
	return Vector2(p.x, p.y)


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
	return Rect2(-r.size.x * 0.5 + pad, -_block_height(s) * 0.5, r.size.x - 2.0 * pad, h)


## The text row's height (its capitals), metres.
static func _text_height(s: Dictionary) -> float:
	return maxf(float(_get(s, "now_playing/title/size")), float(_get(s, "now_playing/time/size"))) * CAP_MIDDLE * 2.0


## The text row and the bar together, top to bottom: they are centred in the pane as one.
static func _block_height(s: Dictionary) -> float:
	return _text_height(s) + float(_get(s, "now_playing/spacing")) + float(_get(s, "now_playing/bar/height"))


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
	var rects := list_rects(s)
	for l: TabletList in [categories_list, options_list, content_list]:
		l.layout(rects[_list_name(l)], s["list"])
	for m in _mats:
		var role := str(m.get_meta("role", "pane"))
		if role == "pane":
			m.set_shader_parameter("fill_color", Color.html(_get(s, "pane/fill")))
			m.set_shader_parameter("border_color", Color.html(_get(s, "pane/border")))
			m.set_shader_parameter("corner_radius", float(_get(s, "pane/corner_radius")))
			m.set_shader_parameter("border_width", float(_get(s, "pane/border_width")))
		elif role.begins_with("list_") or role == "divider":
			var radius := {"list_row": float(_get(s, "list/corner_radius")),
					"list_marker": float(_get(s, "list/marker_width")) * 0.5,
					"list_thumb": float(_get(s, "list/thumb_width")) * 0.5, "divider": 0.0}
			m.set_shader_parameter("corner_radius", radius[role])
			m.set_shader_parameter("border_width", 0.0)
			if role == "list_marker" or role == "list_thumb":
				m.set_shader_parameter("fill_color", Color.html(_get(s, "list/" + role.trim_prefix("list_"))))
			elif role == "divider":
				m.set_shader_parameter("fill_color", Color.html(_get(s, "main/divider")))
		else:
			m.set_shader_parameter("fill_color", Color.html(_get(s, "now_playing/bar/" + role)))
			m.set_shader_parameter("corner_radius", float(_get(s, "now_playing/bar/corner_radius")))
			m.set_shader_parameter("border_width", 0.0)
	var r: Rect2 = pane_rects()["now_playing"]
	var pad := float(_get(s, "now_playing/padding"))
	# The middle of the text row: the capitals' middle goes there.
	var text_mid := _block_height(s) * 0.5 - _text_height(s) * 0.5
	for row: Array in [[title_label, "title", -r.size.x * 0.5 + pad], [time_label, "time", r.size.x * 0.5 - pad]]:
		var key: String = row[1]
		place_text(row[0], _get(s, "now_playing/" + key), Vector2(float(row[2]), text_mid))
	# The dividers: hairlines down the middle of the gaps between the columns.
	var gap := float(_get(s, "main/gap"))
	for k in _dividers.size():
		var col: Rect2 = rects["categories" if k == 0 else "options"]
		var d := _dividers[k]
		var size := Vector2(0.0008, col.size.y)
		(d.mesh as QuadMesh).size = size
		(d.material_override as ShaderMaterial).set_shader_parameter("size", size)
		d.position = Vector3(col.end.x + gap * 0.5, col.get_center().y, LIFT)
	var heading: Rect2 = rects["heading"]
	place_text(content_title, _get(s, "content/title"), Vector2(heading.position.x + float(_get(s, "list/text_inset")),
			heading.get_center().y))
	var bar := bar_rect()
	(_bar_track.mesh as QuadMesh).size = bar.size
	(_bar_track.material_override as ShaderMaterial).set_shader_parameter("size", bar.size)
	_bar_track.position = Vector3(bar.get_center().x, bar.get_center().y, LIFT)
	_fraction = -1.0
	_title_fit = -1.0
	if app != null:
		_update_now_playing()


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


## Text cut with an ellipsis to a width (metres) in a text style's font and size.
func fit_text(l: Label3D, text: String, room: float, text_style: Dictionary) -> String:
	_font(l, text_style)
	return _cut(l, text, room)


func _font(l: Label3D, text_style: Dictionary) -> void:
	l.font = PaneStyle.font(StringName(str(text_style["font"])))
	l.pixel_size = float(text_style["size"]) / FONT_PX


## A label's colour, its own opacity kept apart from the fade's (and a list's clip, meta "clip").
func tint(l: Label3D, c: Color) -> void:
	l.set_meta("alpha", c.a)
	l.modulate = c
	l.modulate.a = _alpha(l)


func _alpha(l: Label3D) -> float:
	return _opacity * float(l.get_meta("alpha", 1.0)) * float(l.get_meta("clip", 1.0))


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


func _list(p_name: String) -> TabletList:
	var l := TabletList.new()
	l.name = p_name
	l.tablet = self
	l.cap_middle = CAP_MIDDLE
	main_pane.add_child(l)
	return l


## A rounded quad (shaders/tablet.gdshader) on a parent, a little in front of it by its priority; the style sets it
## by its role (_apply_style()).
func make_quad(p_name: String, role: String, parent: Node3D, priority: int) -> MeshInstance3D:
	var mi := _rounded(p_name, Vector2(0.01, 0.01), role, priority)
	mi.position.z = LIFT * priority
	parent.add_child(mi)
	return mi


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
	m.set_shader_parameter("opacity", _opacity)
	m.set_meta("role", role)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mats.append(m)
	return mi


func make_label(p_name: String, align: HorizontalAlignment, parent: Node3D) -> Label3D:
	var l := Label3D.new()
	l.name = p_name
	l.font_size = FONT_PX
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.outline_size = 0
	l.render_priority = 3
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
