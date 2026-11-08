extends RefCounted

## The pictures and the surface maps of Shopfront 1906's picture house (kit/shopfront_edwardian.gd; docs/
## environments.md, "Room: Shopfront 1906"), all drawn here in code: nothing borrowed, nothing read from a file but the
## app's own UI face (Fira Sans Condensed, SIL OFL 1.1, ui/fonts/) for the printed bills. Made once a session and kept.
##   maps(kind) -> {albedo, normal, orm, mean}   house-shader maps (procedural.gd's layout): "ceiling" (a 2 ft plate
##        of pressed tin: a beaded border, a ribbed medallion with a rosette, fans in the corners, a stippled ground),
##        "wall" (a small diamond lattice with a flower in each diamond), "beads" (bead and reel, the cornice's band),
##        "matchboard" (the dado's narrow boards, V-jointed, the grain run up them), "riveted" (the booth's sheet iron:
##        lapped seams and rows of rivets)
##   bills() -> Texture2D       the bills on the walls, the price board, the hats notice, the pelmet's name, in one atlas;
##        BILL_RECTS names the cells (pixels; uv_rect() as UVs)
##   street() -> Texture2D      the street through the window: the shops opposite, the wet setts, the night sky
##        (STREET_RECTS)
##   lettering() -> Texture2D   the window's gilt letters as seen from inside (mirrored; alpha: the letters)
##   roll() -> Texture2D        a player piano's roll: its paper, the perforations, the printed tempo line

const Strokes := preload("res://scripts/env/systems/kit/strokes.gd")

const FONT_DIR := "res://ui/fonts/FiraSansCondensed-%s.ttf"
const BILLS_SIZE := Vector2i(1024, 1024)
## The bills' cells in the atlas (pixels): six bills (0.5 x 0.75 m), the price board (0.9 x 0.6 m), the hats notice
## (0.84 x 0.28 m), the pelmet's name (5.6 x 0.38 m: one row of the atlas, its height the board's share).
const BILL_RECTS := {
	"kettle": Rect2i(0, 0, 256, 384), "express": Rect2i(256, 0, 256, 384), "arctic": Rect2i(512, 0, 256, 384),
	"perambulator": Rect2i(768, 0, 256, 384), "programme": Rect2i(0, 384, 256, 384), "inn": Rect2i(256, 384, 256, 384),
	"prices": Rect2i(512, 384, 384, 256), "hats": Rect2i(512, 640, 384, 128), "pelmet": Rect2i(0, 776, 1024, 70),
	"roll_boxes": Rect2i(896, 384, 128, 128), "clock": Rect2i(896, 512, 128, 128),
}
const STREET_SIZE := Vector2i(1024, 1024)
## The street's cells: the shops opposite (12.8 x 6.4 m), the ground from our window to their step (12.8 x 11 m), the
## sky over the roofs.
const STREET_RECTS := {
	"facade": Rect2i(0, 0, 1024, 512), "ground": Rect2i(0, 512, 1024, 448), "sky": Rect2i(0, 960, 1024, 64),
}

static var _cache := {}


## A cell's UVs in its atlas: [top-left, size].
static func uv_rect(cell: Rect2i, atlas: Vector2i) -> Rect2:
	return Rect2(Vector2(cell.position) / Vector2(atlas), Vector2(cell.size) / Vector2(atlas))


# --- Surface maps --------------------------------------------------------------------------------------------------

## The maps for the house shader: the height's slope as the normal map (G, A), occlusion, roughness and metal packed
## (R, G, B), and the albedo's mean (linear) for the tint.
static func maps(kind: String) -> Dictionary:
	var key := "maps " + kind
	if _cache.has(key):
		return _cache[key]
	var size := 256 if kind in ["ceiling"] else 128
	var heights := PackedFloat32Array()
	heights.resize(size * size)
	var rough := PackedFloat32Array()
	rough.resize(size * size)
	var albedo := Image.create_empty(size, size, false, Image.FORMAT_RGB8)
	var cols: Array[Color] = []
	cols.resize(size * size)
	for y in size:
		for x in size:
			var s: Array = _sample(kind, (x + 0.5) / size, (y + 0.5) / size)
			heights[y * size + x] = float(s[0])
			cols[y * size + x] = s[1]
			rough[y * size + x] = float(s[2])
	var depth: float = {"ceiling": 5.0, "wall": 3.0, "beads": 4.0, "matchboard": 2.5, "riveted": 2.0}.get(kind, 3.0)
	var metal: float = {"riveted": 0.25}.get(kind, 0.0)
	var normal := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var orm := Image.create_empty(size, size, false, Image.FORMAT_RGB8)
	var mean := Color(0, 0, 0)
	for y in size:
		for x in size:
			var i := y * size + x
			var hx := heights[y * size + (x + 1) % size] - heights[y * size + (x - 1 + size) % size]
			var hy := heights[((y + 1) % size) * size + x] - heights[((y - 1 + size) % size) * size + x]
			var n := Vector3(-hx * depth, hy * depth, 1.0).normalized()
			normal.set_pixel(x, y, Color(0.5, n.x * 0.5 + 0.5, 0.5, n.y * 0.5 + 0.5))
			# Grime in the hollows: the cavity (lower than round about) darker, and in the occlusion.
			var around := (heights[y * size + (x + 2) % size] + heights[y * size + (x - 2 + size) % size]
					+ heights[((y + 2) % size) * size + x] + heights[((y - 2 + size) % size) * size + x]) * 0.25
			var cavity := clampf((around - heights[i]) * 6.0, 0.0, 1.0)
			var c: Color = cols[i]
			c = c.darkened(0.35 * cavity)
			albedo.set_pixel(x, y, c)
			var lin := c.srgb_to_linear()
			mean += Color(lin.r, lin.g, lin.b) / float(size * size)
			orm.set_pixel(x, y, Color(clampf(0.7 + 0.3 * heights[i] - 0.4 * cavity, 0.0, 1.0), rough[i], metal))
	for img: Image in [albedo, normal, orm]:
		img.generate_mipmaps()
	var out := {"albedo": ImageTexture.create_from_image(albedo), "normal": ImageTexture.create_from_image(normal),
			"orm": ImageTexture.create_from_image(orm), "mean": mean}
	_cache[key] = out
	return out


## The house material `m` shows the maps of `kind`, `colour` on average (procedural.gd apply()'s way).
static func apply(m: ShaderMaterial, kind: String, colour: Color, tiling: float) -> void:
	var p := maps(kind)
	m.set_shader_parameter("albedo_map", p["albedo"])
	m.set_shader_parameter("normal_map", p["normal"])
	m.set_shader_parameter("orm_map", p["orm"])
	m.set_shader_parameter("normal_strength", 1.0)
	m.set_shader_parameter("tiling", tiling)
	var mean: Color = p["mean"]
	var c := colour.srgb_to_linear()
	m.set_shader_parameter("tint", Color(c.r / maxf(mean.r, 0.01), c.g / maxf(mean.g, 0.01),
			c.b / maxf(mean.b, 0.01)).linear_to_srgb())


static func _hash(x: int, y: int, s: int) -> float:
	var h := (x * 374761393 + y * 668265263 + s * 1442695041) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h & 0xffff) / 65535.0


static func _noise(u: float, v: float, pu: int, pv: int, s: int) -> float:
	var x := u * pu
	var y := v * pv
	var xi := int(floor(x))
	var yi := int(floor(y))
	var fx := x - xi
	var fy := y - yi
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var a := _hash(posmod(xi, pu), posmod(yi, pv), s)
	var b := _hash(posmod(xi + 1, pu), posmod(yi, pv), s)
	var c := _hash(posmod(xi, pu), posmod(yi + 1, pv), s)
	var d := _hash(posmod(xi + 1, pu), posmod(yi + 1, pv), s)
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)


static func _step(edge: float, x: float) -> float:
	return 1.0 if x >= edge else 0.0


## A raised bead: 1 on its middle line, round to 0 at half_width.
static func _bead(d: float, half_width: float) -> float:
	var t := clampf(absf(d) / half_width, 0.0, 1.0)
	return sqrt(1.0 - t * t)


## The height (0..1), colour (sRGB, as a mean before the tint) and roughness at u, v (one repeat).
static func _sample(kind: String, u: float, v: float) -> Array:
	match kind:
		"ceiling":
			# A 24 in plate: a beaded border, a flat margin, a fillet, the field with a ribbed medallion and a rosette
			# of twelve petals round a boss, quarter fans in the corners, a fine stipple on the ground.
			var x := (u - 0.5) * 2.0
			var y := (v - 0.5) * 2.0
			var m := maxf(absf(x), absf(y))
			var h := 0.35
			h += 0.4 * _bead(m - 0.955, 0.035)
			h += 0.15 * smoothstep(0.885, 0.875, m)
			h -= 0.12 * smoothstep(0.87, 0.86, m) * smoothstep(0.83, 0.84, m)
			var r := Vector2(x, y).length()
			var a := atan2(y, x)
			# The medallion: two ribs and a cove between them.
			h += 0.35 * _bead(r - 0.62, 0.03) + 0.25 * _bead(r - 0.54, 0.022)
			h -= 0.08 * smoothstep(0.5, 0.52, r) * smoothstep(0.66, 0.64, r)
			# Twelve petals, each a raised lens with a midrib.
			var pa := fposmod(a * 12.0 / TAU, 1.0) - 0.5
			var petal_w := 0.42 * sin(clampf((r - 0.1) / 0.36, 0.0, 1.0) * PI)
			var in_petal := smoothstep(petal_w, petal_w - 0.12, absf(pa)) * _step(0.1, r) * _step(r, 0.47)
			h += 0.3 * in_petal * (0.75 + 0.25 * _bead(pa, 0.08))
			h += 0.4 * _bead(r, 0.1)
			# Quarter fans in the corners: ribs radiating from each corner, between the fillet and the medallion.
			var cx := Vector2(1.0 - absf(x), 1.0 - absf(y)) * 1.0
			var cr := cx.length()
			var ca := atan2(cx.y, cx.x)
			var fan := smoothstep(0.17, 0.2, cr) * smoothstep(0.44, 0.41, cr)
			h += 0.22 * fan * _bead(fposmod(ca * 14.0 / PI, 1.0) - 0.5, 0.35)
			h += 0.25 * _bead(cr - 0.46, 0.02) * _step(0.12, minf(cx.x, cx.y) + 0.12)
			# Stipple on the flat ground.
			var flat := smoothstep(0.86, 0.84, m) * smoothstep(0.66, 0.7, r) * (1.0 - fan)
			h += 0.05 * flat * (_noise(u, v, 96, 96, 11) - 0.5)
			h = clampf(h, 0.0, 1.0)
			var shade := lerpf(0.7, 0.9, h) + 0.04 * (_noise(u, v, 6, 6, 3) - 0.5)
			return [h, Color(shade, shade * 0.97, shade * 0.88), lerpf(0.62, 0.45, h)]
		"wall":
			# A small lattice: four diamonds across the repeat (7.6 cm), fine beads along their sides, a raised dot
			# where they cross, a small quatrefoil in each diamond; a faint stipple on the ground. Quiet at a distance.
			var k := 4.0
			var du := u * k
			var dv := v * k
			var gu := fposmod(du + dv, 1.0)
			var gv := fposmod(du - dv, 1.0)
			var line := minf(minf(gu, 1.0 - gu), minf(gv, 1.0 - gv))
			var h := 0.4 + 0.22 * _bead(line, 0.07)
			# In the diamonds' own frame (p, q along their sides) their middles are at half steps.
			var cu := gu - 0.5
			var cv := gv - 0.5
			var r := Vector2(cu, cv).length() * 2.0
			var a := atan2(cv, cu)
			var petals := 0.5 + 0.5 * cos(a * 4.0)
			h += 0.22 * smoothstep(0.16 + 0.22 * petals, 0.1 + 0.22 * petals, r)
			h += 0.12 * _bead(r, 0.1)
			var xu := fposmod(du + dv + 0.5, 1.0) - 0.5
			var xv := fposmod(du - dv + 0.5, 1.0) - 0.5
			h += 0.22 * _bead(Vector2(xu, xv).length() * 2.0, 0.16)
			h += 0.03 * (_noise(u, v, 64, 64, 13) - 0.5)
			h = clampf(h, 0.0, 1.0)
			var shade := lerpf(0.76, 0.88, h)
			return [h, Color(shade, shade * 0.97, shade * 0.88), lerpf(0.6, 0.45, h)]
		"beads":
			# Bead and reel across the repeat: an oval bead, then two small discs; a fillet above and below.
			var y := absf(v - 0.5) * 2.0
			var h := 0.3 + 0.3 * smoothstep(0.86, 0.82, y)
			var bu := fposmod(u, 1.0)
			var bead := Vector2((bu - 0.36) / 0.3, (v - 0.5) / 0.32)
			h += 0.4 * _bead(bead.length(), 1.0)
			for c: float in [0.78, 0.92]:
				h += 0.3 * _bead(Vector2((bu - c) / 0.05, (v - 0.5) / 0.24).length(), 1.0)
			h += 0.3 * _bead(y - 0.92, 0.06)
			h = clampf(h, 0.0, 1.0)
			var shade := lerpf(0.7, 0.92, h)
			return [h, Color(shade, shade * 0.97, shade * 0.88), lerpf(0.6, 0.42, h)]
		"matchboard":
			# Four boards a repeat, 9.5 cm each, V-jointed with a bead beside each joint; the grain up the boards.
			var bu := fposmod(u * 4.0, 1.0)
			var board := int(floor(u * 4.0))
			var joint := minf(bu, 1.0 - bu)
			var h := 0.6 - 0.5 * smoothstep(0.06, 0.0, joint)
			h += 0.12 * _bead(bu - 0.12, 0.04)
			var grain := _noise(u * 4.0 + board * 0.37, v, 64, 6, 5 + board) * 0.6 + _noise(u, v, 128, 3, 9) * 0.4
			var tone := 0.82 + 0.18 * _hash(board, 0, 17)
			var c := Color(0.55, 0.36, 0.2).lerp(Color(0.36, 0.22, 0.12), grain) * tone
			c = c.darkened(0.5 * smoothstep(0.05, 0.0, joint))
			return [clampf(h + 0.04 * grain, 0.0, 1.0), c, lerpf(0.42, 0.3, h)]
		"riveted":
			# Sheet iron panels lapped every half a repeat across and the whole repeat up, rivets along the laps.
			var pu := fposmod(u * 2.0, 1.0)
			var lap_u := smoothstep(0.035, 0.0, pu) + smoothstep(0.965, 1.0, pu)
			var lap_v := smoothstep(0.035, 0.0, v) + smoothstep(0.965, 1.0, v)
			var h := 0.45 + 0.15 * clampf(lap_u + lap_v, 0.0, 1.0)
			var rv := fposmod(v * 10.0, 1.0) - 0.5
			var ru := fposmod(u * 20.0, 1.0) - 0.5
			h += 0.4 * _bead(Vector2((pu - 0.02 if pu < 0.5 else pu - 1.02) * 20.0, rv).length(), 0.28)
			h += 0.4 * _bead(Vector2(ru, (v - 0.02 if v < 0.5 else v - 1.02) * 10.0).length(), 0.28)
			var blot := _noise(u, v, 8, 8, 21)
			var c := Color(0.34, 0.36, 0.33).lerp(Color(0.26, 0.24, 0.21), blot)
			return [clampf(h, 0.0, 1.0), c, lerpf(0.75, 0.5, blot)]
	return [0.5, Color(0.5, 0.5, 0.5), 0.8]


# --- Text ----------------------------------------------------------------------------------------------------------

static var _fonts := {}


## A face of Fira Sans Condensed (light, regular, medium, semibold), stretched across by `stretch`.
static func _font(weight: String, stretch: float) -> FontFile:
	var key := "%s %.2f" % [weight, stretch]
	if _fonts.has(key):
		return _fonts[key]
	var f := FontFile.new()
	f.load_dynamic_font(FONT_DIR % weight.capitalize().replace("Semibold", "SemiBold"))
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.hinting = TextServer.HINTING_NONE
	if not is_equal_approx(stretch, 1.0):
		f.set_transform(0, Transform2D(Vector2(stretch, 0.0), Vector2(0.0, 1.0), Vector2.ZERO))
	_fonts[key] = f
	return f


## Text's width in pixels at `px` (the em size). A stretched face's transform widens its outlines but not its glyphs'
## advances, so they are widened here by the stretch.
static func text_width(s: String, px: int, weight := "semibold", stretch := 1.0, tracking := 0.0) -> float:
	var f := _font(weight, stretch)
	var ts := TextServerManager.get_primary_interface()
	var rid: RID = f.get_rids()[0]
	var w := 0.0
	for i in s.length():
		var g := ts.font_get_glyph_index(rid, px, s.unicode_at(i), 0)
		w += ts.font_get_glyph_advance(rid, px, g).x * stretch + tracking
	return w - tracking


## The largest size up to `px` at which the text fits `width` pixels.
static func fit(s: String, px: int, width: float, weight := "semibold", stretch := 1.0, tracking := 0.0) -> int:
	var size := px
	while size > 6 and text_width(s, size, weight, stretch, tracking) > width:
		size -= 1
	return size


## Text drawn into `img` (blended by the glyphs' coverage): its baseline at y, x its left (align 0), middle (1) or
## right (2). Returns its width.
static func text(img: Image, s: String, x: float, y: float, px: int, colour: Color, weight := "semibold",
		stretch := 1.0, align := 1, tracking := 0.0) -> float:
	var f := _font(weight, stretch)
	var ts := TextServerManager.get_primary_interface()
	var rid: RID = f.get_rids()[0]
	var sz := Vector2i(px, 0)
	var w := text_width(s, px, weight, stretch, tracking)
	var pen := x - (w * 0.5 if align == 1 else (w if align == 2 else 0.0))
	# The face's glyphs at this size rendered once, and its cache's pictures read once (each read is a copy).
	var key := "%s %.2f %d" % [weight, stretch, px]
	if not _glyph_pages.has(key):
		ts.font_render_range(rid, sz, 32, 126)
		var pages: Array[Image] = []
		for k in ts.font_get_texture_count(rid, sz):
			pages.append(ts.font_get_texture_image(rid, sz, k))
		_glyph_pages[key] = pages
	var pages: Array = _glyph_pages[key]
	for i in s.length():
		var g := ts.font_get_glyph_index(rid, px, s.unicode_at(i), 0)
		var uv := ts.font_get_glyph_uv_rect(rid, sz, g)
		var off := ts.font_get_glyph_offset(rid, sz, g)
		var idx := ts.font_get_glyph_texture_idx(rid, sz, g)
		if uv.size.x > 0.0 and idx >= 0 and idx < pages.size():
			_blit_glyph(img, pages[idx], Rect2i(uv.position, uv.size), Vector2i(roundi(pen + off.x),
					roundi(y + off.y)), colour)
		pen += ts.font_get_glyph_advance(rid, px, g).x * stretch + tracking
	return w


static var _glyph_pages := {}


static func _blit_glyph(img: Image, cache: Image, src: Rect2i, at: Vector2i, colour: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var la := cache.get_format() == Image.FORMAT_LA8
	for yy in src.size.y:
		var ty := at.y + yy
		if ty < 0 or ty >= h:
			continue
		for xx in src.size.x:
			var tx := at.x + xx
			if tx < 0 or tx >= w:
				continue
			var c := cache.get_pixel(src.position.x + xx, src.position.y + yy)
			var cover := c.a if la else c.r
			if cover <= 0.004:
				continue
			var was := img.get_pixel(tx, ty)
			img.set_pixel(tx, ty, was.lerp(Color(colour.r, colour.g, colour.b, maxf(was.a, colour.a)),
					cover * colour.a))


# --- Drawing -------------------------------------------------------------------------------------------------------

## A filled polygon (pixels), antialiased by 4 x 4 samples a pixel near its edges.
static func poly(img: Image, pts: PackedVector2Array, colour: Color) -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	var x0 := maxi(int(floor(lo.x)), 0)
	var x1 := mini(int(ceil(hi.x)), img.get_width() - 1)
	var y0 := maxi(int(floor(lo.y)), 0)
	var y1 := mini(int(ceil(hi.y)), img.get_height() - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var cover := 0.0
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), pts):
				cover = 1.0
			# Edge pixels: four samples.
			var edge := false
			for k in 4:
				var q := Vector2(x + (0.25 if k % 2 == 0 else 0.75), y + (0.25 if k < 2 else 0.75))
				if Geometry2D.is_point_in_polygon(q, pts) != (cover > 0.5):
					edge = true
					break
			if edge:
				cover = 0.0
				for k in 4:
					var q := Vector2(x + (0.25 if k % 2 == 0 else 0.75), y + (0.25 if k < 2 else 0.75))
					if Geometry2D.is_point_in_polygon(q, pts):
						cover += 0.25
			if cover > 0.0:
				var was := img.get_pixel(x, y)
				img.set_pixel(x, y, was.lerp(Color(colour.r, colour.g, colour.b, maxf(was.a, colour.a)),
						cover * colour.a))


## A filled ellipse (or a ring of this thickness when ring > 0), antialiased.
static func ellipse(img: Image, c: Vector2, r: Vector2, colour: Color, ring := 0.0) -> void:
	var x0 := maxi(int(floor(c.x - r.x - 1.0)), 0)
	var x1 := mini(int(ceil(c.x + r.x + 1.0)), img.get_width() - 1)
	var y0 := maxi(int(floor(c.y - r.y - 1.0)), 0)
	var y1 := mini(int(ceil(c.y + r.y + 1.0)), img.get_height() - 1)
	var k := minf(r.x, r.y)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var q := Vector2((x + 0.5 - c.x) / r.x, (y + 0.5 - c.y) / r.y)
			var d := (q.length() - 1.0) * k
			var cover := clampf(0.5 - d, 0.0, 1.0)
			if ring > 0.0:
				cover = minf(cover, clampf(0.5 + d + ring, 0.0, 1.0))
			if cover > 0.0:
				var was := img.get_pixel(x, y)
				img.set_pixel(x, y, was.lerp(Color(colour.r, colour.g, colour.b, maxf(was.a, colour.a)),
						cover * colour.a))


static func rect(img: Image, r: Rect2, colour: Color) -> void:
	poly(img, PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
			colour)


static func line(img: Image, a: Vector2, b: Vector2, colour: Color, thickness: float) -> void:
	Strokes.line(img, a, b, colour, thickness)


## A five-pointed star.
static func star(img: Image, c: Vector2, r: float, colour: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + i * PI / 5.0
		var rr := r if i % 2 == 0 else r * 0.42
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	poly(img, pts, colour)


## Old paper in a cell: its colour mottled, foxed here and there, darker towards its edges, a fold or two.
static func paper(img: Image, cell: Rect2i, colour: Color, seed_value: int, folds := 1) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.02
	noise.fractal_octaves = 3
	var fox := FastNoiseLite.new()
	fox.seed = seed_value + 7
	fox.frequency = 0.09
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var fold_y: Array[float] = []
	for i in folds:
		fold_y.append(cell.size.y * rng.randf_range(0.3, 0.7))
	for y in cell.size.y:
		for x in cell.size.x:
			var m := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var f := smoothstep(0.55, 0.75, fox.get_noise_2d(x, y))
			var e := minf(minf(x, cell.size.x - 1 - x), minf(y, cell.size.y - 1 - y))
			var edge := smoothstep(0.0, 14.0, e)
			var c := colour * (0.9 + 0.12 * m)
			c = c.lerp(Color(0.62, 0.45, 0.25), 0.35 * f)
			c = c.lerp(Color(0.5, 0.4, 0.28), 0.35 * (1.0 - edge))
			for fy in fold_y:
				c = c.darkened(0.12 * smoothstep(2.0, 0.0, absf(y - fy)))
			c.a = 1.0
			img.set_pixel(cell.position.x + x, cell.position.y + y, c)


## A printed rule across: a thick line over a thin one (or one line).
static func rule(img: Image, x0: float, x1: float, y: float, colour: Color, double := true) -> void:
	rect(img, Rect2(x0, y, x1 - x0, 2.5), colour)
	if double:
		rect(img, Rect2(x0, y + 4.5, x1 - x0, 1.0), colour)


# --- The bills -----------------------------------------------------------------------------------------------------

const INK := Color(0.09, 0.075, 0.07)
const RED := Color(0.66, 0.13, 0.09)
const BLUE := Color(0.14, 0.22, 0.44)
const BUFF := Color(0.9, 0.83, 0.66)
const GOLD := Color(0.86, 0.66, 0.3)
const CREAM := Color(0.92, 0.88, 0.76)


static func bills() -> Texture2D:
	if _cache.has("bills"):
		return _cache["bills"]
	var img := Image.create_empty(BILLS_SIZE.x, BILLS_SIZE.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.3, 0.25, 0.2))
	_bill(img, BILL_RECTS["kettle"], 11, RED, "A MOST AMUSING TRICK PICTURE", ["THE MAGIC", "KETTLE"],
			"IT BOILS OVER WITH FUN!", _kettle)
	_bill(img, BILL_RECTS["express"], 12, BLUE, "THRILLING! REALISTIC!", ["A RIDE ON", "THE EXPRESS"],
			"THE TRAIN COMES STRAIGHT AT YOU", _express)
	_bill(img, BILL_RECTS["arctic"], 13, BLUE, "ANIMATED VIEWS OF THE FROZEN NORTH", ["VOYAGE TO", "THE ARCTIC"],
			"ICEBERGS * WALRUS * MIDNIGHT SUN", _arctic)
	_bill(img, BILL_RECTS["perambulator"], 14, RED, "SCREAMINGLY FUNNY", ["THE RUNAWAY", "PERAMBULATOR"],
			"DOWN THE HILL AT A FRIGHTFUL PACE", _pram)
	_programme(img, BILL_RECTS["programme"])
	_bill(img, BILL_RECTS["inn"], 16, RED, "A WEIRD AND MYSTERIOUS SUBJECT", ["THE HAUNTED", "INN"],
			"POSITIVELY SPOOKY", _inn)
	_prices(img, BILL_RECTS["prices"])
	_hats(img, BILL_RECTS["hats"])
	_pelmet(img, BILL_RECTS["pelmet"])
	_roll_boxes(img, BILL_RECTS["roll_boxes"])
	_clock_face(img, BILL_RECTS["clock"])
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_cache["bills"] = t
	return t


## A bill: the house's line at the top, a red or blue line, the title in two lines, a picture in the second colour
## and ink, the tagline, the prices at the foot.
static func _bill(img: Image, cell: Rect2i, seed_value: int, second: Color, over: String, title: Array, under: String,
		picture: Callable) -> void:
	paper(img, cell, BUFF, seed_value)
	var o := Vector2(cell.position)
	var w := float(cell.size.x)
	var cx := o.x + w * 0.5
	text(img, "NONPAREIL ANIMATED PICTURES", cx, o.y + 22, fit("NONPAREIL ANIMATED PICTURES", 15, w - 30,
			"medium"), INK, "medium")
	rule(img, o.x + 14, o.x + w - 14, o.y + 28, INK)
	var sub := fit(over, 15, w - 28, "semibold")
	text(img, over, cx, o.y + 54, sub, second, "semibold")
	var y := o.y + 100.0
	for line_text: String in title:
		var px := fit(line_text, 46, w - 24, "semibold", 1.25)
		text(img, line_text, cx, y, px, INK, "semibold", 1.25)
		y += 44.0
	var box := Rect2(o.x + 22, o.y + 170, w - 44, 140)
	rect(img, box, Color(BUFF.r * 0.97, BUFF.g * 0.95, BUFF.b * 0.92))
	picture.call(img, box, second)
	# The picture's frame: a ruled box.
	for e: Rect2 in [Rect2(box.position.x, box.position.y, box.size.x, 2), Rect2(box.position.x, box.end.y - 2,
			box.size.x, 2), Rect2(box.position.x, box.position.y, 2, box.size.y), Rect2(box.end.x - 2,
			box.position.y, 2, box.size.y)]:
		rect(img, e, INK)
	text(img, under, cx, o.y + 334, fit(under, 16, w - 26, "medium"), second, "medium")
	rule(img, o.x + 14, o.x + w - 14, o.y + 344, INK)
	text(img, "ADMISSION 2d & 3d  ~  CHILDREN 1d", cx, o.y + 366, fit("ADMISSION 2d & 3d  ~  CHILDREN 1d", 13,
			w - 30, "regular"), INK, "regular")


static func _kettle(img: Image, box: Rect2, second: Color) -> void:
	var c := box.get_center() + Vector2(0, 18)
	# The kettle: its body, lid and knob, spout and handle; steam rising in curls, stars about it.
	ellipse(img, c, Vector2(44, 34), INK)
	ellipse(img, c + Vector2(-8, -8), Vector2(18, 12), Color(0.35, 0.3, 0.28))
	rect(img, Rect2(c.x - 22, c.y - 40, 44, 8), INK)
	ellipse(img, c + Vector2(0, -44), Vector2(6, 5), INK)
	poly(img, PackedVector2Array([c + Vector2(36, -6), c + Vector2(70, -30), c + Vector2(74, -26),
			c + Vector2(44, 8)]), INK)
	ellipse(img, c + Vector2(-44, -10), Vector2(16, 20), INK, 4.0)
	for k in 4:
		ellipse(img, c + Vector2(80 - k * 4, -40 - k * 14), Vector2(7 + k * 2, 6 + k), second, 2.5)
	for s: Vector2 in [Vector2(-70, -50), Vector2(-40, -58), Vector2(60, 30), Vector2(-75, 30), Vector2(30, -58)]:
		star(img, box.get_center() + s, 7.0, second)


static func _express(img: Image, box: Rect2, second: Color) -> void:
	var c := box.get_center()
	# Rails running to the engine; the engine head on: smokebox door, chimney, buffers, lamps; speed lines.
	var foot := box.end.y - 4
	poly(img, PackedVector2Array([Vector2(c.x - 6, c.y + 20), Vector2(c.x - 2, c.y + 20), Vector2(c.x - 60, foot),
			Vector2(c.x - 74, foot)]), INK)
	poly(img, PackedVector2Array([Vector2(c.x + 2, c.y + 20), Vector2(c.x + 6, c.y + 20), Vector2(c.x + 74, foot),
			Vector2(c.x + 60, foot)]), INK)
	for k in 5:
		var t := float(k + 1) / 6.0
		var yy := lerpf(c.y + 22, foot - 2, t * t)
		var hw := lerpf(4, 66, t * t)
		rect(img, Rect2(c.x - hw, yy, hw * 2.0, 2.0 + 3.0 * t), Color(0.3, 0.25, 0.2))
	rect(img, Rect2(c.x - 34, c.y - 12, 68, 44), INK)
	ellipse(img, c + Vector2(0, -6), Vector2(30, 30), INK)
	ellipse(img, c + Vector2(0, -6), Vector2(21, 21), second)
	ellipse(img, c + Vector2(0, -6), Vector2(4, 4), INK)
	rect(img, Rect2(c.x - 7, c.y - 62, 14, 26), INK)
	rect(img, Rect2(c.x - 10, c.y - 64, 20, 5), INK)
	for s: float in [-1.0, 1.0]:
		ellipse(img, c + Vector2(s * 30, 36), Vector2(8, 6), INK)
		ellipse(img, c + Vector2(s * 22, -38), Vector2(5, 5), Color(0.95, 0.85, 0.5))
	for k in 6:
		var yy := box.position.y + 18 + k * 18
		line(img, Vector2(box.position.x + 8, yy), Vector2(box.position.x + 40 + (k % 3) * 8, yy), second, 2.0)
		line(img, Vector2(box.end.x - 8, yy), Vector2(box.end.x - 40 - (k % 3) * 8, yy), second, 2.0)


static func _arctic(img: Image, box: Rect2, second: Color) -> void:
	var sea := box.position.y + box.size.y * 0.66
	rect(img, Rect2(box.position.x + 2, box.position.y + 2, box.size.x - 4, sea - box.position.y), Color(0.82, 0.8,
			0.72))
	ellipse(img, Vector2(box.end.x - 44, sea - 36), Vector2(16, 16), second, 3.0)
	poly(img, PackedVector2Array([Vector2(box.position.x + 8, sea), Vector2(box.position.x + 34, sea - 58),
			Vector2(box.position.x + 52, sea - 44), Vector2(box.position.x + 70, sea - 84), Vector2(box.position.x + 104,
			sea)]), second)
	poly(img, PackedVector2Array([Vector2(box.position.x + 40, sea - 52), Vector2(box.position.x + 52, sea - 44),
			Vector2(box.position.x + 70, sea - 84), Vector2(box.position.x + 60, sea)]), Color(0.95, 0.95, 0.9, 0.6))
	# A steamer: hull, funnel, masts.
	var sx := box.position.x + 128
	poly(img, PackedVector2Array([Vector2(sx, sea - 10), Vector2(sx + 62, sea - 10), Vector2(sx + 54, sea),
			Vector2(sx + 6, sea)]), INK)
	rect(img, Rect2(sx + 24, sea - 30, 9, 20), INK)
	line(img, Vector2(sx + 12, sea - 10), Vector2(sx + 12, sea - 44), INK, 2.0)
	line(img, Vector2(sx + 46, sea - 10), Vector2(sx + 46, sea - 40), INK, 2.0)
	for k in 5:
		var yy := sea + 8 + k * 9
		for j in 7:
			var xx := box.position.x + 10 + j * 30 + (k % 2) * 15
			line(img, Vector2(xx, yy), Vector2(xx + 14, yy), INK, 1.5)


static func _pram(img: Image, box: Rect2, second: Color) -> void:
	# A hill falling to the right, the perambulator flying down it, its hood up; dashes behind it.
	poly(img, PackedVector2Array([Vector2(box.position.x + 2, box.position.y + 50), Vector2(box.end.x - 2,
			box.end.y - 20), Vector2(box.end.x - 2, box.end.y - 2), Vector2(box.position.x + 2, box.end.y - 2)]),
			Color(0.55, 0.5, 0.4))
	var c := box.get_center() + Vector2(14, -6)
	var tilt := 0.32
	var body := PackedVector2Array()
	for q: Vector2 in [Vector2(-34, -16), Vector2(30, -16), Vector2(26, 10), Vector2(-30, 10)]:
		body.append(c + q.rotated(tilt))
	poly(img, body, second)
	var hood := PackedVector2Array()
	for k in 9:
		var a := PI + k * PI / 8.0 * 0.6
		hood.append(c + (Vector2(-14, -16) + Vector2(cos(a), sin(a)) * 22).rotated(tilt))
	hood.append(c + Vector2(-14, -16).rotated(tilt))
	poly(img, hood, INK)
	for w: Vector2 in [Vector2(-22, 22), Vector2(20, 22)]:
		ellipse(img, c + w.rotated(tilt), Vector2(11, 11), INK, 3.0)
	line(img, c + Vector2(30, -16).rotated(tilt), c + Vector2(48, -36).rotated(tilt), INK, 3.0)
	for k in 4:
		var a := c + Vector2(-60 - k * 10, -20 + k * 10).rotated(tilt)
		line(img, a, a + Vector2(-16, 0).rotated(tilt), INK, 2.0)


static func _inn(img: Image, box: Rect2, second: Color) -> void:
	rect(img, Rect2(box.position.x + 2, box.position.y + 2, box.size.x - 4, box.size.y - 4), Color(0.25, 0.24, 0.3))
	ellipse(img, Vector2(box.end.x - 46, box.position.y + 40), Vector2(22, 22), Color(0.93, 0.88, 0.62))
	var gx := box.position.x + 40
	var gy := box.end.y - 4
	poly(img, PackedVector2Array([Vector2(gx, gy), Vector2(gx, gy - 70), Vector2(gx + 40, gy - 108),
			Vector2(gx + 86, gy - 66), Vector2(gx + 86, gy)]), INK)
	rect(img, Rect2(gx + 60, gy - 122, 10, 30), INK)
	for wdw: Vector2 in [Vector2(14, -54), Vector2(54, -54), Vector2(34, -26)]:
		rect(img, Rect2(gx + wdw.x, gy + wdw.y, 14, 16), Color(0.95, 0.75, 0.3))
	# The inn's sign on its bracket, and bats.
	line(img, Vector2(gx + 86, gy - 60), Vector2(gx + 112, gy - 60), INK, 3.0)
	rect(img, Rect2(gx + 100, gy - 58, 22, 26), second)
	for b: Vector2 in [Vector2(-40, -30), Vector2(10, -48), Vector2(40, -20)]:
		var p := box.get_center() + b
		poly(img, PackedVector2Array([p, p + Vector2(-10, -6), p + Vector2(-5, 0), p + Vector2(0, -3),
				p + Vector2(5, 0), p + Vector2(10, -6)]), INK)


## The programme: the house's bill of the week's pictures, all type.
static func _programme(img: Image, cell: Rect2i) -> void:
	paper(img, cell, Color(0.92, 0.88, 0.74), 15, 2)
	var o := Vector2(cell.position)
	var w := float(cell.size.x)
	var cx := o.x + w * 0.5
	text(img, "THE", cx, o.y + 30, 18, RED, "semibold", 1.2)
	text(img, "NONPAREIL", cx, o.y + 68, fit("NONPAREIL", 46, w - 20, "semibold", 1.3), INK, "semibold", 1.3)
	rule(img, o.x + 14, o.x + w - 14, o.y + 78, INK)
	text(img, "ANIMATED PICTURES", cx, o.y + 104, fit("ANIMATED PICTURES", 24, w - 24, "semibold"), RED,
			"semibold")
	text(img, "TWICE NIGHTLY  7 & 9", cx, o.y + 130, fit("TWICE NIGHTLY  7 & 9", 18, w - 24, "medium"), INK,
			"medium")
	rule(img, o.x + 30, o.x + w - 30, o.y + 140, INK, false)
	var y := o.y + 166.0
	for item: Array in [["THE MAGIC KETTLE", RED], ["A RIDE ON THE EXPRESS", INK], ["VOYAGE TO THE ARCTIC", RED],
			["THE RUNAWAY PERAMBULATOR", INK], ["THE HAUNTED INN", RED], ["AND MANY OTHERS", INK]]:
		text(img, item[0], cx, y, fit(item[0], 17, w - 30, "medium"), item[1], "medium")
		y += 27.0
	rule(img, o.x + 14, o.x + w - 14, o.y + 336, INK)
	text(img, "THE PIANO PLAYS THROUGHOUT", cx, o.y + 360, fit("THE PIANO PLAYS THROUGHOUT", 14, w - 30, "regular"),
			INK, "regular")


## The price board: signwritten in cream and gold on black, shaded.
static func _prices(img: Image, cell: Rect2i) -> void:
	var o := Vector2(cell.position)
	var w := float(cell.size.x)
	rect(img, Rect2(o, Vector2(cell.size)), Color(0.05, 0.05, 0.045))
	for k in 2:
		var inset := 9.0 + k * 6.0
		for e: Rect2 in [Rect2(o.x + inset, o.y + inset, w - 2 * inset, 2), Rect2(o.x + inset,
				o.y + cell.size.y - inset - 2, w - 2 * inset, 2), Rect2(o.x + inset, o.y + inset, 2,
				cell.size.y - 2 * inset), Rect2(o.x + w - inset - 2, o.y + inset, 2, cell.size.y - 2 * inset)]:
			rect(img, e, GOLD if k == 0 else Color(0.5, 0.38, 0.18))
	var cx := o.x + w * 0.5
	var lines := [["PRICES OF ADMISSION", 30, GOLD, 52], ["FRONT SEATS  3d", 34, CREAM, 104],
			["BACK SEATS  2d", 34, CREAM, 148], ["CHILDREN  1d", 34, CREAM, 192],
			["CONTINUOUS FROM 6 TILL 10", 20, GOLD, 230]]
	for l: Array in lines:
		var px := fit(l[0], int(l[1]), w - 50, "medium", 1.1)
		text(img, l[0], cx + 2, o.y + float(l[3]) + 2, px, Color(0.3, 0.12, 0.06), "medium", 1.1)
		text(img, l[0], cx, o.y + float(l[3]), px, l[2], "medium", 1.1)


static func _hats(img: Image, cell: Rect2i) -> void:
	var o := Vector2(cell.position)
	var w := float(cell.size.x)
	rect(img, Rect2(o, Vector2(cell.size)), Color(0.1, 0.2, 0.15))
	for e: Rect2 in [Rect2(o.x + 6, o.y + 6, w - 12, 2), Rect2(o.x + 6, o.y + cell.size.y - 8, w - 12, 2),
			Rect2(o.x + 6, o.y + 6, 2, cell.size.y - 12), Rect2(o.x + w - 8, o.y + 6, 2, cell.size.y - 12)]:
		rect(img, e, GOLD)
	var cx := o.x + w * 0.5
	for l: Array in [["LADIES ARE KINDLY REQUESTED", 54], ["TO REMOVE THEIR HATS", 96]]:
		var px := fit(l[0], 34, w - 36, "medium")
		text(img, l[0], cx + 1.5, float(l[1]) + o.y + 1.5, px, Color(0.02, 0.05, 0.03), "medium")
		text(img, l[0], cx, float(l[1]) + o.y, px, CREAM, "medium")


## The pelmet board over the sheet: the house's name in gilt letters, shaded, between fleurons, on deep red.
static func _pelmet(img: Image, cell: Rect2i) -> void:
	var o := Vector2(cell.position)
	var w := float(cell.size.x)
	var h := float(cell.size.y)
	rect(img, Rect2(o, Vector2(cell.size)), Color(0.34, 0.06, 0.05))
	for e: Rect2 in [Rect2(o.x, o.y + 5, w, 2), Rect2(o.x, o.y + h - 7, w, 2)]:
		rect(img, e, GOLD)
	var cx := o.x + w * 0.5
	var px := fit("THE  NONPAREIL", 44, w * 0.46, "semibold", 1.35, 3.0)
	text(img, "THE  NONPAREIL", cx + 2, o.y + 53, px, Color(0.12, 0.02, 0.01), "semibold", 1.35, 1, 3.0)
	text(img, "THE  NONPAREIL", cx, o.y + 51, px, GOLD, "semibold", 1.35, 1, 3.0)
	var half := text_width("THE  NONPAREIL", px, "semibold", 1.35, 3.0) * 0.5
	for s: float in [-1.0, 1.0]:
		var at := Vector2(cx + s * (half + 26), o.y + h * 0.5)
		star(img, at, 10.0, GOLD)
		line(img, at + Vector2(s * 15, 0), at + Vector2(s * 60, 0), GOLD, 2.0)
		ellipse(img, at + Vector2(s * 66, 0), Vector2(4, 4), GOLD)
		# The side words centred in what is left between the fleuron's line and the board's end.
		var inner := at.x + s * 80.0
		var outer := o.x + (w - 14.0 if s > 0.0 else 14.0)
		var room := absf(outer - inner)
		var spx := fit("ANIMATED PICTURES", 22, room, "medium", 1.1)
		text(img, "ANIMATED PICTURES", (inner + outer) * 0.5, o.y + 45, spx, Color(0.9, 0.8, 0.6), "medium", 1.1)


## Roll boxes' end labels (a player piano's music rolls in their cardboard boxes).
static func _roll_boxes(img: Image, cell: Rect2i) -> void:
	var o := Vector2(cell.position)
	rect(img, Rect2(o, Vector2(cell.size)), Color(0.52, 0.4, 0.26))
	for k in 4:
		var y := o.y + 6 + k * 30
		rect(img, Rect2(o.x + 6, y, 116, 24), Color(0.9, 0.86, 0.72))
		rect(img, Rect2(o.x + 6, y + 18, 116, 3), RED)
		text(img, ["MARCH", "WALTZ", "GALOP", "AGITATO"][k], o.x + 64, y + 16, 13, INK, "medium")


## A drop-dial clock's face: a cream dial, Roman hours, a minute track (the hands are the room's).
static func _clock_face(img: Image, cell: Rect2i) -> void:
	var o := Vector2(cell.position)
	var c := o + Vector2(cell.size) * 0.5
	rect(img, Rect2(o, Vector2(cell.size)), Color(0.18, 0.11, 0.06))
	ellipse(img, c, Vector2(62, 62), Color(0.9, 0.86, 0.74))
	ellipse(img, c, Vector2(56, 56), INK, 1.2)
	ellipse(img, c, Vector2(48, 48), INK, 1.0)
	for k in 60:
		var a := k * TAU / 60.0
		var d := Vector2(sin(a), -cos(a))
		line(img, c + d * (52 if k % 5 == 0 else 54), c + d * 56, INK, 1.6 if k % 5 == 0 else 1.0)
	var numerals := ["XII", "I", "II", "III", "IIII", "V", "VI", "VII", "VIII", "IX", "X", "XI"]
	for k in 12:
		var a := k * TAU / 12.0
		var at := c + Vector2(sin(a), -cos(a)) * 39
		text(img, numerals[k], at.x, at.y + 5, 12, INK, "medium")


# --- The street ----------------------------------------------------------------------------------------------------

## The street at night, as the window sees it: the shops opposite with a lit window and a lamp's glow on the brick,
## the wet setts with the lamps' streaks, the sky over the roofs. Colours as seen (the light painted in).
static func street() -> Texture2D:
	if _cache.has("street"):
		return _cache["street"]
	var img := Image.create_empty(STREET_SIZE.x, STREET_SIZE.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.02, 0.02, 0.03))
	_facade(img, STREET_RECTS["facade"])
	_ground(img, STREET_RECTS["ground"])
	_sky(img, STREET_RECTS["sky"])
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_cache["street"] = t
	return t


## Metres to the façade cell's pixels: x across (0 at the street's middle, our window's x), y up from the pavement.
const FACADE_M := Vector2(12.8, 6.4)
## Where the lamps stand, in the façade's metres: ours (outside our window, nearer, its glow on their brick a little)
## and theirs (on their kerb).
const LAMP_THEIRS := Vector2(-3.4, 3.3)
const SHOP_WINDOW := Rect2(-1.6, 0.55, 3.6, 2.1)


static func _facade_px(cell: Rect2i, m: Vector2) -> Vector2:
	return Vector2(cell.position) + Vector2((m.x / FACADE_M.x + 0.5) * cell.size.x, (1.0 - m.y / FACADE_M.y)
			* cell.size.y)


static func _facade(img: Image, cell: Rect2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1906
	# Brick in Flemish bond, dark at night; mortar lines.
	var px_m := cell.size.x / FACADE_M.x
	var course := 0.075 * px_m
	var brick := 0.225 * px_m
	img.fill_rect(cell, Color(0.06, 0.045, 0.04))
	var y := 0.0
	var row := 0
	while y < cell.size.y:
		var x := -(row % 2) * brick * 0.25
		while x < cell.size.x:
			var w := brick if (int(x / brick * 2.0) + row) % 2 == 0 else brick * 0.5
			var shade := rng.randf_range(0.75, 1.15)
			var c := Color(0.16, 0.085, 0.065) * shade
			img.fill_rect(Rect2i(cell.position.x + int(x) + 1, cell.position.y + cell.size.y - int(y + course),
					maxi(int(w) - 1, 1), maxi(int(course) - 1, 1)), Color(c.r, c.g, c.b, 1.0))
			x += w
		y += course
		row += 1
	# Their shop: a fascia, the lit window with its stall riser, shelves of jars against the light, the door.
	var fascia := Rect2(-2.6, 2.9, 6.2, 0.55)
	_fill_m(img, cell, Rect2(-2.7, 0.0, 6.4, 3.55), Color(0.07, 0.1, 0.08))
	_fill_m(img, cell, fascia, Color(0.08, 0.16, 0.11))
	var f0 := _facade_px(cell, Vector2(fascia.get_center().x, fascia.position.y + 0.12))
	text(img, "J. HARGREAVE  CONFECTIONER", f0.x + 1, f0.y + 1, 24, Color(0.05, 0.03, 0.01), "semibold", 1.2)
	text(img, "J. HARGREAVE  CONFECTIONER", f0.x, f0.y, 24, Color(0.85, 0.66, 0.32), "semibold", 1.2)
	var win := SHOP_WINDOW
	for yy in int(win.size.y / FACADE_M.y * cell.size.y):
		var f := float(yy) / (win.size.y / FACADE_M.y * cell.size.y)
		var c := Color(1.0, 0.78, 0.42).lerp(Color(0.85, 0.52, 0.22), f) * 0.95
		var a := _facade_px(cell, Vector2(win.position.x, win.end.y))
		var b := _facade_px(cell, Vector2(win.end.x, win.end.y))
		img.fill_rect(Rect2i(int(a.x), int(a.y) + yy, int(b.x - a.x), 1), Color(c.r, c.g, c.b, 1.0))
	# Shelves and jars.
	for shelf: float in [0.95, 1.5, 2.05]:
		_fill_m(img, cell, Rect2(win.position.x, shelf - 0.03, win.size.x, 0.03), Color(0.25, 0.14, 0.06))
		var xm := win.position.x + 0.12
		while xm < win.end.x - 0.15:
			var jw := rng.randf_range(0.14, 0.22)
			var jh := rng.randf_range(0.2, 0.36)
			var tint: Color = [Color(0.45, 0.2, 0.08), Color(0.6, 0.38, 0.12), Color(0.35, 0.18, 0.15),
					Color(0.55, 0.45, 0.2)][rng.randi() % 4]
			_fill_m(img, cell, Rect2(xm, shelf, jw, jh), tint)
			_fill_m(img, cell, Rect2(xm + jw * 0.2, shelf + jh, jw * 0.6, 0.04), Color(0.2, 0.12, 0.06))
			xm += jw + rng.randf_range(0.04, 0.1)
	# Glazing bars, the riser, the door with its fanlight.
	for gx: float in [win.position.x, win.position.x + win.size.x / 3.0, win.position.x + win.size.x * 2.0 / 3.0,
			win.end.x]:
		_fill_m(img, cell, Rect2(gx - 0.03, win.position.y, 0.06, win.size.y), Color(0.05, 0.07, 0.05))
	_fill_m(img, cell, Rect2(win.position.x - 0.05, win.end.y, win.size.x + 0.1, 0.08), Color(0.05, 0.07, 0.05))
	_fill_m(img, cell, Rect2(win.position.x - 0.1, 0.0, win.size.x + 0.2, win.position.y), Color(0.06, 0.08, 0.06))
	_fill_m(img, cell, Rect2(2.25, 0.0, 1.0, 2.5), Color(0.06, 0.07, 0.05))
	_fill_m(img, cell, Rect2(2.33, 1.25, 0.84, 1.1), Color(0.5, 0.32, 0.14))
	_fill_m(img, cell, Rect2(2.3, 2.55, 0.9, 0.3), Color(0.75, 0.5, 0.22))
	# The upper floor: sash windows, one lit behind a blind, the others dark with a glint.
	for wx: float in [-4.6, -1.5, 1.6, 4.7]:
		var wr := Rect2(wx - 0.5, 4.3, 1.0, 1.55)
		_fill_m(img, cell, Rect2(wr.position - Vector2(0.06, 0.06), wr.size + Vector2(0.12, 0.12)),
				Color(0.12, 0.1, 0.08))
		var lit := is_equal_approx(wx, 1.6)
		_fill_m(img, cell, wr, Color(0.85, 0.55, 0.25) if lit else Color(0.03, 0.035, 0.05))
		if lit:
			_fill_m(img, cell, Rect2(wr.position.x, wr.position.y + 0.65, wr.size.x, 0.9), Color(0.95, 0.68, 0.32))
		_fill_m(img, cell, Rect2(wr.position.x, wr.get_center().y - 0.03, wr.size.x, 0.06), Color(0.1, 0.08, 0.06))
		_fill_m(img, cell, Rect2(wx - 0.02, wr.position.y, 0.04, wr.size.y), Color(0.1, 0.08, 0.06))
		_fill_m(img, cell, Rect2(wr.position.x - 0.1, wr.position.y - 0.12, wr.size.x + 0.2, 0.1),
				Color(0.2, 0.18, 0.15))
	# The ground floor beside the shop: another shop, shuttered for the night; an entry.
	for sx: float in [-6.4, 3.7]:
		_fill_m(img, cell, Rect2(sx, 0.0, 2.7, 3.0), Color(0.05, 0.05, 0.04))
		for k in 14:
			_fill_m(img, cell, Rect2(sx + 0.1, 0.4 + k * 0.17, 2.5, 0.02), Color(0.09, 0.08, 0.07))
	# Their lamp's glow on the brick and the light of the window spilling on the pavement's edge.
	_glow(img, cell, LAMP_THEIRS, 2.6, Color(1.0, 0.72, 0.38), 0.55)
	_glow(img, cell, Vector2(win.get_center().x, 0.3), 2.4, Color(1.0, 0.7, 0.35), 0.35)
	_glow(img, cell, Vector2(0.0, 3.6), 5.0, Color(0.9, 0.62, 0.35), 0.18)
	# Their lamp itself: the post and the lantern (its flame is the room's glow, drawn apart).
	_fill_m(img, cell, Rect2(LAMP_THEIRS.x - 0.05, 0.0, 0.1, LAMP_THEIRS.y - 0.25), Color(0.03, 0.03, 0.03))
	_fill_m(img, cell, Rect2(LAMP_THEIRS.x - 0.17, LAMP_THEIRS.y - 0.25, 0.34, 0.5), Color(1.0, 0.86, 0.58))
	_fill_m(img, cell, Rect2(LAMP_THEIRS.x - 0.22, LAMP_THEIRS.y + 0.25, 0.44, 0.08), Color(0.04, 0.04, 0.04))
	# The eaves and the roofs' line: the sky shows over them.
	_fill_m(img, cell, Rect2(-6.4, 6.05, 12.8, 0.35), Color(0.03, 0.03, 0.035))


static func _fill_m(img: Image, cell: Rect2i, r: Rect2, colour: Color) -> void:
	var a := _facade_px(cell, Vector2(r.position.x, r.end.y))
	var b := _facade_px(cell, Vector2(r.end.x, r.position.y))
	var ri := Rect2i(Vector2i(floori(a.x), floori(a.y)), Vector2i(maxi(ceili(b.x - a.x), 1), maxi(ceili(b.y - a.y), 1)))
	ri = ri.intersection(cell)
	if ri.size.x > 0 and ri.size.y > 0:
		img.fill_rect(ri, Color(colour.r, colour.g, colour.b, 1.0))


## A soft glow added on the façade round a point (metres), `reach` metres out.
static func _glow(img: Image, cell: Rect2i, at: Vector2, reach: float, colour: Color, strength: float) -> void:
	var c := _facade_px(cell, at)
	var r := reach / FACADE_M.x * cell.size.x
	var x0 := maxi(int(c.x - r), cell.position.x)
	var x1 := mini(int(c.x + r), cell.end.x - 1)
	var y0 := maxi(int(c.y - r), cell.position.y)
	var y1 := mini(int(c.y + r), cell.end.y - 1)
	for y in range(y0, y1 + 1, 1):
		for x in range(x0, x1 + 1, 1):
			var d := Vector2(x - c.x, y - c.y).length() / r
			if d >= 1.0:
				continue
			var k := strength * pow(1.0 - d, 2.2)
			var was := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(was.r + colour.r * k * (0.3 + was.r * 4.0), was.g + colour.g * k * (0.3
					+ was.g * 4.0), was.b + colour.b * k * (0.3 + was.b * 4.0), 1.0))


## Metres of the ground cell: x across (0 at our window's middle), z out from our window (0) to their step (11).
const GROUND_M := Vector2(12.8, 11.0)
## The kerbs (z from our window) and our lamp's foot (x, z).
const KERB_NEAR := 2.2
const KERB_FAR := 9.2
const LAMP_OURS := Vector2(1.6, 1.9)


static func _ground_px(cell: Rect2i, m: Vector2) -> Vector2:
	return Vector2(cell.position) + Vector2((m.x / GROUND_M.x + 0.5) * cell.size.x, (1.0 - m.y / GROUND_M.y)
			* cell.size.y)


static func _ground(img: Image, cell: Rect2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1907
	img.fill_rect(cell, Color(0.03, 0.03, 0.035))
	var ppm := cell.size.x / GROUND_M.x
	# Setts: rows across the road, each stone its own shade, wet: dark with a sheen.
	var z := KERB_NEAR + 0.3
	while z < KERB_FAR:
		var x := -GROUND_M.x * 0.5 + rng.randf_range(0.0, 0.1)
		while x < GROUND_M.x * 0.5:
			var w := rng.randf_range(0.18, 0.26)
			var p := _ground_px(cell, Vector2(x, z + 0.12))
			var shade := rng.randf_range(0.6, 1.2)
			var c := Color(0.06, 0.06, 0.07) * shade
			img.fill_rect(Rect2i(int(p.x) + 1, int(p.y) + 1, maxi(int(w * ppm) - 1, 1), maxi(int(0.12 * ppm) - 1, 1)),
					Color(c.r, c.g, c.b, 1.0))
			x += w
		z += 0.13
	# The pavements: big flags, the kerbs of granite.
	for band: Vector2 in [Vector2(0.0, KERB_NEAR), Vector2(KERB_FAR + 0.3, GROUND_M.y)]:
		var zz := band.x
		while zz < band.y:
			var xx := -GROUND_M.x * 0.5
			var d := rng.randf_range(0.6, 0.9)
			while xx < GROUND_M.x * 0.5:
				var w := rng.randf_range(0.6, 1.0)
				var p := _ground_px(cell, Vector2(xx, minf(zz + d, band.y)))
				var shade := rng.randf_range(0.8, 1.15)
				var c := Color(0.075, 0.07, 0.068) * shade
				img.fill_rect(Rect2i(int(p.x) + 1, int(p.y) + 1, maxi(int(w * ppm) - 1, 1),
						maxi(int(minf(d, band.y - zz) * ppm) - 1, 1)), Color(c.r, c.g, c.b, 1.0))
				xx += w
			zz += d
	for kz: float in [KERB_NEAR, KERB_FAR]:
		var a := _ground_px(cell, Vector2(-GROUND_M.x * 0.5, kz + 0.3))
		img.fill_rect(Rect2i(int(a.x), int(a.y), cell.size.x, int(0.3 * ppm)), Color(0.11, 0.105, 0.1))
	# The light: our lamp's pool on the near pavement, the window opposite's on theirs; the wet road's streaks of
	# both drawn towards us (a reflection on a wet road runs from the light towards the eye).
	_ground_glow(img, cell, LAMP_OURS, Vector2(2.6, 2.6), Color(1.0, 0.72, 0.38), 0.75)
	_ground_glow(img, cell, Vector2(0.2, 10.4), Vector2(3.0, 1.2), Color(1.0, 0.7, 0.35), 0.6)
	_ground_glow(img, cell, Vector2(LAMP_THEIRS.x, 9.9), Vector2(1.8, 1.8), Color(1.0, 0.72, 0.38), 0.5)
	_ground_glow(img, cell, Vector2(LAMP_OURS.x, 3.9), Vector2(0.35, 2.2), Color(1.0, 0.75, 0.42), 0.9)
	_ground_glow(img, cell, Vector2(0.2, 6.0), Vector2(1.6, 3.2), Color(1.0, 0.7, 0.36), 0.55)
	_ground_glow(img, cell, Vector2(LAMP_THEIRS.x, 6.8), Vector2(0.3, 2.6), Color(1.0, 0.75, 0.42), 0.7)
	# Puddles in the setts: a few smooth dark pools that take the light more.
	for k in 6:
		var at := Vector2(rng.randf_range(-5.0, 5.0), rng.randf_range(KERB_NEAR + 0.8, KERB_FAR - 0.6))
		_ground_glow(img, cell, at, Vector2(rng.randf_range(0.4, 0.9), rng.randf_range(0.2, 0.4)),
				Color(0.5, 0.45, 0.5), 0.25)


## A soft elliptical glow on the ground (metres: centre, half sizes).
static func _ground_glow(img: Image, cell: Rect2i, at: Vector2, half: Vector2, colour: Color, strength: float) -> void:
	var c := _ground_px(cell, at)
	var r := half / GROUND_M * Vector2(cell.size)
	var x0 := maxi(int(c.x - r.x), cell.position.x)
	var x1 := mini(int(c.x + r.x), cell.end.x - 1)
	var y0 := maxi(int(c.y - r.y), cell.position.y)
	var y1 := mini(int(c.y + r.y), cell.end.y - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var d := Vector2((x - c.x) / r.x, (y - c.y) / r.y).length()
			if d >= 1.0:
				continue
			var k := strength * pow(1.0 - d, 2.0)
			var was := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(minf(was.r + colour.r * k * (0.15 + was.r * 6.0), 1.0),
					minf(was.g + colour.g * k * (0.15 + was.g * 6.0), 1.0),
					minf(was.b + colour.b * k * (0.15 + was.b * 6.0), 1.0), 1.0))


static func _sky(img: Image, cell: Rect2i) -> void:
	for y in cell.size.y:
		var f := float(y) / cell.size.y
		var c := Color(0.025, 0.03, 0.06).lerp(Color(0.09, 0.075, 0.08), f)
		img.fill_rect(Rect2i(cell.position.x, cell.position.y + y, cell.size.x, 1), c)


# --- The window's letters --------------------------------------------------------------------------------------------

const LETTERING_SIZE := Vector2i(1024, 256)


## The shop window's lettering from inside: gilt letters, their black-lined backs seen in reverse (mirrored), in an
## arc over the glass and a line under it. Alpha: the letters (cut out).
static func lettering() -> Texture2D:
	if _cache.has("lettering"):
		return _cache["lettering"]
	var img := Image.create_empty(LETTERING_SIZE.x, LETTERING_SIZE.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var back := Color(0.08, 0.05, 0.03, 1.0)
	var edge := Color(0.55, 0.4, 0.18, 1.0)
	# The arc: each letter on its own, turned along a circle.
	var word := "ANIMATED PICTURES"
	var px := 64
	var radius := 900.0
	var centre := Vector2(LETTERING_SIZE.x * 0.5, 40.0 + radius)
	var total := text_width(word, px, "semibold", 1.15, 6.0)
	var a := -total * 0.5 / radius
	for i in word.length():
		var ch := word[i]
		var cw := text_width(ch, px, "semibold", 1.15)
		var glyph := Image.create_empty(px + 16, px + 24, false, Image.FORMAT_RGBA8)
		glyph.fill(Color(0, 0, 0, 0))
		text(glyph, ch, glyph.get_width() * 0.5, px + 6, px, edge, "semibold", 1.15)
		var ang := a + (cw * 0.5) / radius
		var at := centre + Vector2(sin(ang), -cos(ang)) * radius
		_stamp(img, glyph, at, ang, back)
		a += (cw + 6.0) / radius
	text(img, "CONTINUOUS PERFORMANCE", LETTERING_SIZE.x * 0.5, 200, 34, edge, "medium", 1.2, 1, 4.0)
	_backing(img, back)
	img.flip_x()
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_cache["lettering"] = t
	return t


## A glyph image drawn into img, turned by `angle` round its middle, centred at `at`.
static func _stamp(img: Image, glyph: Image, at: Vector2, angle: float, _back: Color) -> void:
	var gw := glyph.get_width()
	var gh := glyph.get_height()
	var r := int(ceil(Vector2(gw, gh).length() * 0.5))
	var ca := cos(angle)
	var sa := sin(angle)
	for y in range(int(at.y) - r, int(at.y) + r + 1):
		if y < 0 or y >= img.get_height():
			continue
		for x in range(int(at.x) - r, int(at.x) + r + 1):
			if x < 0 or x >= img.get_width():
				continue
			var d := Vector2(x + 0.5 - at.x, y + 0.5 - at.y)
			var q := Vector2(d.x * ca + d.y * sa, -d.x * sa + d.y * ca) + Vector2(gw, gh) * 0.5
			if q.x < 0.0 or q.y < 0.0 or q.x >= gw - 1 or q.y >= gh - 1:
				continue
			var c := glyph.get_pixel(int(q.x), int(q.y))
			if c.a > 0.0:
				var was := img.get_pixel(x, y)
				img.set_pixel(x, y, was.lerp(Color(c.r, c.g, c.b, 1.0), c.a) if was.a > 0.0 else c)


## The letters' backs: the gilt shows only at their edges, the black backing inside (a gilder's letters from behind).
static func _backing(img: Image, back: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var src := img.duplicate() as Image
	for y in range(2, h - 2):
		for x in range(2, w - 2):
			var c := src.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var inner := src.get_pixel(x - 2, y).a > 0.5 and src.get_pixel(x + 2, y).a > 0.5 \
					and src.get_pixel(x, y - 2).a > 0.5 and src.get_pixel(x, y + 2).a > 0.5
			if inner:
				img.set_pixel(x, y, Color(back.r, back.g, back.b, c.a))


# --- The roll ----------------------------------------------------------------------------------------------------------

const ROLL_SIZE := Vector2i(128, 512)


## A music roll's paper: cream, 65 tracks of perforations (slots of their notes' lengths: chords in the bass, a tune
## above), the printed tempo line wandering in red, a margin each side. Repeats down (the shader scrolls it).
static func roll() -> Texture2D:
	if _cache.has("roll"):
		return _cache["roll"]
	var img := Image.create_empty(ROLL_SIZE.x, ROLL_SIZE.y, false, Image.FORMAT_RGB8)
	img.fill(Color(0.86, 0.82, 0.7))
	var rng := RandomNumberGenerator.new()
	rng.seed = 65
	var left := 10
	var pitch := (ROLL_SIZE.x - 2 * left) / 65.0
	var hole := Color(0.12, 0.1, 0.08)
	var y := 0
	var bar := 0
	while y < ROLL_SIZE.y - 8:
		# A chord in the bass on the beat, a few notes of the tune between.
		for t in [6 + (bar % 3), 12 + (bar % 4), 16]:
			img.fill_rect(Rect2i(left + int(t * pitch), y, maxi(int(pitch) - 1, 1), 5), hole)
		for k in 3:
			var t2 := rng.randi_range(30, 58)
			var slot := rng.randi_range(3, 14)
			var yy := y + k * 6
			if yy + slot < ROLL_SIZE.y:
				img.fill_rect(Rect2i(left + int(t2 * pitch), yy, maxi(int(pitch) - 1, 1), slot), hole)
		y += 18
		bar += 1
	for yy in ROLL_SIZE.y:
		var x := left + int((0.5 + 0.35 * sin(yy * TAU / ROLL_SIZE.y * 2.0)) * (ROLL_SIZE.x - 2 * left))
		img.fill_rect(Rect2i(x, yy, 2, 1), Color(0.7, 0.2, 0.15))
	img.fill_rect(Rect2i(0, 0, 3, ROLL_SIZE.y), Color(0.7, 0.66, 0.55))
	img.fill_rect(Rect2i(ROLL_SIZE.x - 3, 0, 3, ROLL_SIZE.y), Color(0.7, 0.66, 0.55))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_cache["roll"] = t
	return t
