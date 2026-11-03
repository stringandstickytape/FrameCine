extends RefCounted

## The type of the controller legends: one atlas of multi-channel distance fields, one entry per glyph, shared by every
## legend on both hands (controller_label.gdshader reads it). A legend is then a list of glyph quads and needs no texture
## of its own, no viewport and no renderer, so text changes cost only a little geometry. Godot's font code makes the
## fields on the CPU (a millisecond or so a glyph), once. The usual glyphs are made together on first use, so the atlas
## is normally uploaded once; a glyph outside CHARSET joins it when a legend first needs it.
##
## Sizes are in em (the font size). Text coordinates: x right, y down, from the top left of the block of text, which
## is tight on the capitals: a line of capitals is CAP_HEIGHT tall.

## Atlas pixels per em, and how many of them the distance field spans in all.
const SIZE := 48
const FIELD_RANGE := 10
const ATLAS := 512
## Keeps the glyphs' fields apart in the mipmaps.
const GAP := 2
## The fallback font's capital height.
const CAP_HEIGHT := 0.714
## Baseline to baseline.
const LINE_STEP := 1.2
## Added to each advance: small capitals read better a little apart.
const TRACKING := 0.04
const CHARSET := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 /:+-.,&'()"

static var _font: FontFile
static var _image: Image
static var _texture: ImageTexture
## Glyph index -> {"rect": Rect2 in em from the pen, "uv": Rect2 in the atlas}, {} for a glyph with no shape (a space).
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
			var glyph := _glyph(int(g["index"]))
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
		else:
			_texture.update(image)
	return _texture


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
	_image = Image.create_empty(ATLAS, ATLAS, false, Image.FORMAT_RGBA8)
	var ts := TextServerManager.get_primary_interface()
	var rid: RID = _font.get_rids()[0]
	for c in CHARSET.to_utf8_buffer():
		_glyph(ts.font_get_glyph_index(rid, SIZE, c, 0))


static func _glyph(index: int) -> Dictionary:
	if _glyphs.has(index):
		return _glyphs[index]
	var ts := TextServerManager.get_primary_interface()
	var rid: RID = _font.get_rids()[0]
	var key := Vector2i(SIZE, 0)
	var entry := {}
	var size := ts.font_get_glyph_size(rid, key, index)
	if size.x > 0.0 and size.y > 0.0:
		var source := Rect2i(ts.font_get_glyph_uv_rect(rid, key, index))
		if _pen.x + source.size.x + GAP > ATLAS:
			_pen = Vector2i(GAP, _pen.y + _row_height + GAP)
			_row_height = 0
		if _pen.y + source.size.y + GAP > ATLAS:
			push_error("Controller label atlas is full: a glyph is left out")
		else:
			var page := _font.get_texture_image(0, key, ts.font_get_glyph_texture_idx(rid, key, index))
			_image.blit_rect(page, source, _pen)
			entry = {"rect": Rect2(ts.font_get_glyph_offset(rid, key, index) / SIZE, size / SIZE),
					"uv": Rect2(Vector2(_pen) / ATLAS, Vector2(source.size) / ATLAS)}
			_pen.x += source.size.x + GAP
			_row_height = maxi(_row_height, source.size.y)
			_dirty = true
	_glyphs[index] = entry
	return entry
