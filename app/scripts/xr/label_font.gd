extends RefCounted

## The type of the controller legends: one atlas of multi-channel distance fields, one entry per glyph, shared by every
## legend on both hands (controller_label.gdshader reads it). A legend is then a list of glyph quads and needs no texture
## of its own, no viewport and no renderer, so text changes cost only a little geometry. Godot's font code makes the
## fields on the CPU (a millisecond or so a glyph), once. The usual glyphs are made together on first use, so the atlas
## is normally uploaded once; a glyph outside CHARSET joins it when a legend first needs it.
##
## Other languages (docs/i18n.md): the Simplified Chinese font (scripts/i18n.gd) is the fallback, in fields too, so a
## translated legend shapes and prints the same way. A CJK glyph is about 58 px square here, so a 512 px atlas holds
## only some 60 of them: when it is full it doubles (512, 1024, 2048: about 1100 CJK glyphs), keeping what it has
## where it is. The quads' UVs are fractions of ATLAS_SPAN, not of the atlas as it is now, so legends laid before a
## growth stay right; the shader scales them by ATLAS_SPAN over the texture's size. Latin legends never grow it.
##
## Sizes are in em (the font size). Text coordinates: x right, y down, from the top left of the block of text, which
## is tight on the capitals: a line of capitals is CAP_HEIGHT tall.

## Atlas pixels per em, and how many of them the distance field spans in all.
const SIZE := 48
const FIELD_RANGE := 10
const ATLAS := 512
## The largest the atlas grows to, and what the UVs are fractions of (controller_label.gdshader atlas_span).
const ATLAS_SPAN := 2048
## Keeps the glyphs' fields apart in the mipmaps.
const GAP := 2
## The fallback font's capital height.
const CAP_HEIGHT := 0.714
## Baseline to baseline.
const LINE_STEP := 1.2
## Added to each advance: small capitals read better a little apart.
const TRACKING := 0.04
const CHARSET := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 /:+-.,&'()"
const I18n := preload("res://scripts/i18n.gd")

static var _font: FontFile
## The fallback for scripts the main font lacks (CJK), as fields.
static var _cjk: FontFile
static var _image: Image
static var _texture: ImageTexture
## Vector2i(font: 0 main, 1 CJK, glyph index) -> {"rect": Rect2 in em from the pen, "uv": Rect2 in the atlas, as
## fractions of ATLAS_SPAN}, {} for a glyph with no shape (a space).
static var _glyphs := {}
static var _pen := Vector2i(GAP, GAP)
static var _row_height := 0
static var _dirty := false


## {"quads": [[Rect2 in em, Rect2 in the atlas], ...], "size": Vector2 in em} for a legend; "\n" breaks lines, and lines
## are centred.
static func shape(text: String) -> Dictionary:
	_load()
	var ts := TextServerManager.get_primary_interface()
	var rows: Array = []
	var width := 0.0
	for row_text in text.split("\n"):
		var line := TextLine.new()
		line.add_string(row_text, _font, SIZE)
		var pen := 0.0
		var row: Array = []
		for g: Dictionary in ts.shaped_text_get_glyphs(line.get_rid()):
			var glyph := _glyph(int(g["index"]), g.get("font_rid", RID()))
			if not glyph.is_empty():
				row.append([pen, glyph])
			pen += float(g["advance"]) / SIZE + TRACKING
		pen = maxf(pen - TRACKING, 0.0)
		width = maxf(width, pen)
		rows.append([pen, row])
	var quads: Array = []
	for i in rows.size():
		var left := (width - float(rows[i][0])) * 0.5
		var baseline := CAP_HEIGHT + i * LINE_STEP
		for item: Array in rows[i][1]:
			var glyph: Dictionary = item[1]
			var rect: Rect2 = glyph["rect"]
			quads.append([Rect2(rect.position + Vector2(left + float(item[0]), baseline), rect.size), glyph["uv"]])
	return {"quads": quads, "size": Vector2(width, CAP_HEIGHT + (rows.size() - 1) * LINE_STEP)}


static func texture() -> Texture2D:
	_load()
	if _dirty:
		_dirty = false
		var image := _image.duplicate() as Image
		image.generate_mipmaps()
		if _texture == null:
			_texture = ImageTexture.create_from_image(image)
		elif _texture.get_size() != Vector2(image.get_size()):
			# Grown: the same texture, so every material that has it sees the new one.
			_texture.set_image(image)
		else:
			_texture.update(image)
	return _texture


## The atlas's side now, in pixels (it grows when full).
static func atlas_size() -> int:
	_load()
	return _image.get_width()


static func _load() -> void:
	if _font != null:
		return
	_font = FontFile.new()
	_font.data = (ThemeDB.fallback_font as FontFile).data
	_font.multichannel_signed_distance_field = true
	_font.msdf_pixel_range = FIELD_RANGE
	_font.msdf_size = SIZE
	_font.generate_mipmaps = false
	_font.hinting = TextServer.HINTING_NONE
	_font.allow_system_fallback = false
	var cjk := I18n.cjk_font()
	if cjk.data.size() > 0:
		_cjk = FontFile.new()
		_cjk.data = cjk.data
		_cjk.multichannel_signed_distance_field = true
		_cjk.msdf_pixel_range = FIELD_RANGE
		_cjk.msdf_size = SIZE
		_cjk.generate_mipmaps = false
		_cjk.hinting = TextServer.HINTING_NONE
		_cjk.allow_system_fallback = false
		_font.fallbacks = [_cjk]
	_image = Image.create_empty(ATLAS, ATLAS, false, Image.FORMAT_RGBA8)
	var ts := TextServerManager.get_primary_interface()
	var rid: RID = _font.get_rids()[0]
	for c in CHARSET.to_utf8_buffer():
		_glyph(ts.font_get_glyph_index(rid, SIZE, c, 0))


## A glyph of the main font, or of the CJK fallback when `font_rid` is the fallback's (shaped text says which).
static func _glyph(index: int, font_rid := RID()) -> Dictionary:
	var font := _font
	var slot := 0
	if _cjk != null and font_rid.is_valid() and font_rid == _cjk.get_rids()[0]:
		font = _cjk
		slot = 1
	var id := Vector2i(slot, index)
	if _glyphs.has(id):
		return _glyphs[id]
	var ts := TextServerManager.get_primary_interface()
	var rid: RID = font.get_rids()[0]
	var key := Vector2i(SIZE, 0)
	var entry := {}
	var size := ts.font_get_glyph_size(rid, key, index)
	if size.x > 0.0 and size.y > 0.0:
		var source := Rect2i(ts.font_get_glyph_uv_rect(rid, key, index))
		var side := _image.get_width()
		if _pen.x + source.size.x + GAP > side:
			_pen = Vector2i(GAP, _pen.y + _row_height + GAP)
			_row_height = 0
		if _pen.y + source.size.y + GAP > side and side < ATLAS_SPAN:
			_grow()
		if _pen.y + source.size.y + GAP > _image.get_width():
			push_error("Controller label atlas is full: a glyph is left out")
		else:
			var page := font.get_texture_image(0, key, ts.font_get_glyph_texture_idx(rid, key, index))
			_image.blit_rect(page, source, _pen)
			entry = {"rect": Rect2(ts.font_get_glyph_offset(rid, key, index) / SIZE, size / SIZE),
					"uv": Rect2(Vector2(_pen) / ATLAS_SPAN, Vector2(source.size) / ATLAS_SPAN)}
			_pen.x += source.size.x + GAP
			_row_height = maxi(_row_height, source.size.y)
			_dirty = true
	_glyphs[id] = entry
	return entry


## Doubles the atlas, what it has kept at the same pixels (so the same UVs). The rows go on to the new width.
static func _grow() -> void:
	var side := _image.get_width() * 2
	var bigger := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
	bigger.blit_rect(_image, Rect2i(Vector2i.ZERO, _image.get_size()), Vector2i.ZERO)
	_image = bigger
	# The free room is to the right of every row and below them all: start a row below what is there.
	_pen = Vector2i(GAP, _pen.y)
	_dirty = true
