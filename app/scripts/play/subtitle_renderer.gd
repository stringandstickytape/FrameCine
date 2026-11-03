extends Node3D

## Subtitle renderer (ideas #67, and the second line of #65): one quad in the world below the picture (not on the
## pane), showing a transparent SubViewport that draws the lines showing now. The viewport renders once per change of
## lines, not per frame; the quad is hidden while nothing shows.
##
## What it draws, top to bottom: the second track's lines (smaller, tinted), then the main track's; within each,
## top-aligned ASS lines (\an7-9) first. Text lines are RichTextLabels with the style from subtitle_style.gd (bold,
## italic, underline, strike-out, colour, outline colour, relative size), left / centre / right by the line's
## alignment. Bitmap lines (PGS, VobSub, DVB: the engine's `images` [{rect, image}] on a `canvas_size`) keep their
## size relative to the picture and their positions relative to each other, set in the same band; their place on the
## frame is not kept (a top-of-frame sign shows in the band like the rest).
##
## Place and size:
##   flat       the band is the picture's width; text height is TEXT_HEIGHT of the picture's height times `scale_factor`.
##              position "below": the band's top edge is GAP under the picture, and it grows down; "inside": its bottom
##              edge is INSIDE_MARGIN above the picture's bottom edge, and it grows up. `offset` moves it up (+) or
##              down (-) in picture heights.
##   180 / 360  low in front at SPHERE_DISTANCE, facing the screen's yaw; grows up from SPHERE_DROP below the eyes.
##   depth      metres toward the viewer (3D films: in front of what comes out of the screen). The quad moves along
##              the line from the eyes and shrinks with the distance, so it looks the same size in the same place.
## Canvas pixels follow the band's angular width (PX_PER_DEGREE, MIN_CANVAS..MAX_CANVAS): sharp without wasting fill.
##
## API (main.features.subtitles.display):
##   show_events(primary: Array[Dictionary], secondary: Array[Dictionary])   the events showing now (subtitles.gd)
##   set_text(text)                       plain text only (older callers)
##   set_scale_factor(f) 0.5..3, set_position_mode("below" | "inside"), set_offset(v) -0.5..0.5,
##   set_depth(m) 0..MAX_DEPTH, set_background(a) 0..1 (a dark box behind each line)
##   scale_factor, position_mode, offset, depth, background
##   is_showing() -> bool, get_canvas_size() -> Vector2i, get_band_size() -> Vector2 (metres), place()
## Settings: [subtitles] size, position, offset, depth, background.

const Style := preload("res://scripts/play/subtitle_style.gd")
const VideoMode := preload("res://scripts/video_mode.gd")

const TEXT_HEIGHT := 0.05
const SPHERE_DISTANCE := 2.5
## Spherical: text height in metres at SPHERE_DISTANCE (about 1.7 degrees), and the band's width (about 48 degrees).
const SPHERE_TEXT_HEIGHT := 0.075
const SPHERE_WIDTH := 2.25
const SPHERE_DROP := 0.45
## Width text wraps at, as a fraction of the band.
const WRAP := 0.8
const GAP := 0.03
const INSIDE_MARGIN := 0.05
const MAX_DEPTH := 2.0
const PX_PER_DEGREE := 30.0
const MIN_CANVAS := 512
const MAX_CANVAS := 2048
const SECONDARY_SCALE := 0.85
const SECONDARY_COLOR := Color(1.0, 0.9, 0.55)
const OUTLINE := 0.14
const POSITIONS := ["below", "inside"]

var main: Node3D
var scale_factor := 1.0
var position_mode := "below"
var offset := 0.0
var depth := 0.0
var background := 0.0

var _viewport: SubViewport
var _canvas: Control
var _quad: MeshInstance3D
var _mesh: QuadMesh
var _primary: Array = []
var _secondary: Array = []
var _fonts := {}
var _canvas_w := 1024
var _band := Vector2.ZERO
## The screen's pose when last placed: a screen that moves by itself (lying down, head follow) is followed.
var _placed_for := Transform3D()


func _ready() -> void:
	scale_factor = clampf(float(main.settings.get_value("subtitles", "size", 1.0)), 0.5, 3.0)
	position_mode = str(main.settings.get_value("subtitles", "position", "below"))
	if not position_mode in POSITIONS:
		position_mode = "below"
	offset = clampf(float(main.settings.get_value("subtitles", "offset", 0.0)), -0.5, 0.5)
	depth = clampf(float(main.settings.get_value("subtitles", "depth", 0.0)), 0.0, MAX_DEPTH)
	background = clampf(float(main.settings.get_value("subtitles", "background", 0.0)), 0.0, 1.0)
	_viewport = SubViewport.new()
	_viewport.name = "Canvas"
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.gui_disable_input = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.size = Vector2i(16, 16)
	add_child(_viewport)
	_canvas = Control.new()
	_canvas.name = "Lines"
	_viewport.add_child(_canvas)
	_mesh = QuadMesh.new()
	_quad = MeshInstance3D.new()
	_quad.name = "Quad"
	_quad.mesh = _mesh
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# 2D drawing into a transparent target leaves colour multiplied by alpha.
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_PREMULT_ALPHA
	mat.no_depth_test = true
	mat.disable_receive_shadows = true
	mat.disable_fog = true
	mat.render_priority = 10
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mat.albedo_texture = _viewport.get_texture()
	_quad.material_override = mat
	_quad.visible = false
	add_child(_quad)
	_make_fonts()
	main.screen_changed.connect(func(_w: float, _d: float, _h: float) -> void: _rebuild())
	main.mode_changed.connect(func(_m: Variant, _a: String) -> void: _rebuild())


func show_events(primary: Array, secondary: Array = []) -> void:
	_primary = primary
	_secondary = secondary
	_rebuild()


func set_text(t: String) -> void:
	show_events([{"text": t}] if t != "" else [], [])


func is_showing() -> bool:
	return _quad != null and _quad.visible


func get_canvas_size() -> Vector2i:
	return _viewport.size


func get_band_size() -> Vector2:
	return _band


func set_scale_factor(f: float) -> void:
	scale_factor = clampf(f, 0.5, 3.0)
	main.settings.set_value("subtitles", "size", scale_factor)
	_rebuild()


func set_position_mode(m: String) -> void:
	position_mode = m if m in POSITIONS else "below"
	main.settings.set_value("subtitles", "position", position_mode)
	_rebuild()


func set_offset(v: float) -> void:
	offset = clampf(v, -0.5, 0.5)
	main.settings.set_value("subtitles", "offset", offset)
	place()


func set_depth(v: float) -> void:
	depth = clampf(v, 0.0, MAX_DEPTH)
	main.settings.set_value("subtitles", "depth", depth)
	place()


func set_background(a: float) -> void:
	background = clampf(a, 0.0, 1.0)
	main.settings.set_value("subtitles", "background", background)
	_rebuild()


## Band width and text height in metres, and the distance it is seen from.
func _geometry() -> Dictionary:
	if main.mode.is_spherical():
		return {"width": SPHERE_WIDTH, "text": SPHERE_TEXT_HEIGHT * scale_factor, "distance": SPHERE_DISTANCE}
	var size: Vector2 = main.screen.get_flat_size()
	return {"width": size.x, "text": size.y * TEXT_HEIGHT * scale_factor, "distance": float(main.screen_distance)}


func _rebuild() -> void:
	if _canvas == null:
		return
	for c in _canvas.get_children():
		_canvas.remove_child(c)
		c.queue_free()
	if _primary.is_empty() and _secondary.is_empty():
		_quad.visible = false
		return
	var g := _geometry()
	var width: float = g["width"]
	# Depth keeps the angular size, so it doesn't change the pixels needed.
	var angle := rad_to_deg(2.0 * atan(width * 0.5 / maxf(float(g["distance"]), 0.3)))
	_canvas_w = clampi(roundi(angle * PX_PER_DEGREE), MIN_CANVAS, MAX_CANVAS)
	var px_per_m := _canvas_w / width
	var font_px := maxi(roundi(float(g["text"]) * px_per_m), 8)
	var pad := roundi(font_px * 0.3)
	var y := pad
	for group: Array in [[_secondary, true], [_primary, false]]:
		for e: Dictionary in _ordered(group[0]):
			var h := _add_event(e, y, font_px, group[1])
			if h > 0:
				y += h + roundi(font_px * 0.15)
	if y <= pad:
		_quad.visible = false
		return
	var canvas := Vector2i(_canvas_w, y + pad)
	_viewport.size = canvas
	_canvas.size = canvas
	_band = Vector2(width, canvas.y / px_per_m)
	_mesh.size = _band
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_quad.visible = true
	place()


## Top-aligned events first, then middle, then bottom (stable).
func _ordered(events: Array) -> Array:
	var out: Array = []
	for row in [[7, 8, 9], [4, 5, 6], [1, 2, 3]]:
		for e: Dictionary in events:
			if _alignment(e) in row:
				out.append(e)
	return out


func _alignment(e: Dictionary) -> int:
	if bool(e.get("bitmap", false)):
		return 2
	if not e.has("_style"):
		e["_style"] = Style.from_event(e)
	return int(e["_style"]["alignment"])


## Adds one event's controls at y; returns their height in canvas pixels (0: nothing to draw).
func _add_event(e: Dictionary, y: int, font_px: int, secondary: bool) -> int:
	if bool(e.get("bitmap", false)):
		return _add_bitmap(e, y)
	var style: Dictionary = e["_style"] if e.has("_style") else Style.from_event(e)
	var px := roundi(font_px * (SECONDARY_SCALE if secondary else 1.0))
	var bbcode := Style.to_bbcode(style["lines"], px)
	if bbcode == "":
		return 0
	var col := (int(style["alignment"]) - 1) % 3
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for kind: String in ["normal", "bold", "italics", "bold_italics"]:
		label.add_theme_font_override(kind + "_font", _fonts[kind])
		label.add_theme_font_size_override(kind + "_font_size", px)
	label.add_theme_color_override("default_color", SECONDARY_COLOR if secondary else Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", maxi(roundi(px * OUTLINE), 2))
	var margin := Vector2(px * 0.35, px * 0.12) if background > 0.0 else Vector2.ZERO
	var box: StyleBox = StyleBoxEmpty.new()
	if background > 0.0:
		var flat := StyleBoxFlat.new()
		flat.bg_color = Color(0, 0, 0, background)
		flat.set_corner_radius_all(roundi(px * 0.15))
		box = flat
	box.content_margin_left = margin.x
	box.content_margin_right = margin.x
	box.content_margin_top = margin.y
	box.content_margin_bottom = margin.y
	label.add_theme_stylebox_override("normal", box)
	var tag: String = ["left", "center", "right"][col]
	label.text = "[%s]%s[/%s]" % [tag, bbcode, tag]
	var column := roundi(_canvas_w * WRAP)
	_canvas.add_child(label)
	label.size = Vector2(column, 0)
	var content := Vector2(label.get_content_width(), label.get_content_height())
	var w := mini(ceili(content.x + margin.x * 2.0) + 4, column)
	var h := ceili(content.y + margin.y * 2.0)
	label.size = Vector2(w, h)
	var left := (_canvas_w - column) / 2
	var x: int = [left, (_canvas_w - w) / 2, left + column - w][col]
	label.position = Vector2(x, y)
	return h


## The engine's bitmap event: images [{rect: Rect2i, image: Image}] on canvas_size (the video's picture size).
## On a 3D rip (side by side or top and bottom) the canvas is the whole frame and each eye's half carries its own
## copy of the caption: only the first half's images are drawn, on that half (stretched back to the eye's aspect
## for half-width or half-height rips). The caption's depth is then this quad's (set_depth), not the rip's.
static func eye_images(images: Array, canvas: Vector2i, layout: int, half: bool) -> Dictionary:
	var eye := Rect2i(Vector2i.ZERO, canvas)
	var stretch := Vector2.ONE
	if layout == VideoMode.Layout.SBS:
		eye.size.x = canvas.x / 2
		stretch.x = 2.0 if half else 1.0
	elif layout == VideoMode.Layout.TB:
		eye.size.y = canvas.y / 2
		stretch.y = 2.0 if half else 1.0
	var out: Array = []
	for im: Dictionary in images:
		var r: Rect2i = im.get("rect", Rect2i())
		if eye.has_point(r.get_center()):
			var c := im.duplicate()
			c["rect"] = Rect2i(Vector2i(Vector2(r.position) * stretch), Vector2i(Vector2(r.size) * stretch))
			out.append(c)
	return {"images": out, "canvas": Vector2i(Vector2(eye.size) * stretch)}


func _add_bitmap(e: Dictionary, y: int) -> int:
	var cs: Vector2i = e.get("canvas_size", Vector2i.ZERO)
	if cs.x <= 0:
		return 0
	# Textures made once per image, kept on the event's own image entries.
	for im: Dictionary in e.get("images", []):
		if not im.has("_texture"):
			var img: Image = im.get("image")
			im["_texture"] = ImageTexture.create_from_image(img) if img != null and not img.is_empty() else null
	var mode: Object = main.mode
	var picked := eye_images(e.get("images", []), cs, int(mode.layout), bool(mode.half))
	var images: Array = picked["images"]
	cs = picked["canvas"]
	if images.is_empty() or cs.x <= 0:
		return 0
	var k := float(_canvas_w) / cs.x * scale_factor
	var top := INF
	var bottom := -INF
	for im: Dictionary in images:
		var r: Rect2i = im.get("rect", Rect2i())
		top = minf(top, r.position.y)
		bottom = maxf(bottom, r.end.y)
	for i in images.size():
		var tex: Texture2D = images[i].get("_texture")
		if tex == null:
			continue
		var r: Rect2i = images[i].get("rect", Rect2i())
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.position = Vector2(_canvas_w * 0.5 + (r.position.x - cs.x * 0.5) * k, y + (r.position.y - top) * k)
		tr.size = Vector2(r.size) * k
		_canvas.add_child(tr)
	return ceili((bottom - top) * k)


func _process(_delta: float) -> void:
	if _quad != null and _quad.visible and main.screen.global_transform != _placed_for:
		place()


## Puts the quad below (or inside) the picture, or low in front for 180 / 360, then brings it `depth` closer.
func place() -> void:
	if _quad == null or not _quad.visible:
		return
	_placed_for = main.screen.global_transform
	var t: Transform3D
	if main.mode.is_spherical():
		var yaw: float = main.screen_yaw
		var bottom: float = main.eye_height - SPHERE_DROP
		t = Transform3D(Basis(Vector3.UP, -yaw), Vector3(sin(yaw) * SPHERE_DISTANCE, bottom + _band.y * 0.5,
				-cos(yaw) * SPHERE_DISTANCE))
	else:
		var size: Vector2 = main.screen.get_flat_size()
		var edge := -size.y * 0.5 + offset * size.y
		var cy := edge - size.y * GAP - _band.y * 0.5 if position_mode == "below" \
				else edge + size.y * INSIDE_MARGIN + _band.y * 0.5
		t = main.screen.global_transform * Transform3D(Basis.IDENTITY, Vector3(0.0, cy, 0.01))
	if depth > 0.0:
		var eye := Vector3(0.0, float(main.eye_height), 0.0)
		var to := t.origin - eye
		var k := clampf((to.length() - depth) / maxf(to.length(), 0.001), 0.1, 1.0)
		t = Transform3D(t.basis.scaled_local(Vector3(k, k, k)), eye + to * k)
	global_transform = Transform3D.IDENTITY
	_quad.global_transform = t


func _make_fonts() -> void:
	var base: Font = ThemeDB.fallback_font
	var bold := FontVariation.new()
	bold.base_font = base
	bold.variation_embolden = 0.9
	var italic := FontVariation.new()
	italic.base_font = base
	italic.variation_transform = Transform2D(Vector2(1, 0), Vector2(0.2, 1), Vector2.ZERO)
	var bold_italic := FontVariation.new()
	bold_italic.base_font = base
	bold_italic.variation_embolden = 0.9
	bold_italic.variation_transform = italic.variation_transform
	_fonts = {"normal": base, "bold": bold, "italics": italic, "bold_italics": bold_italic}
