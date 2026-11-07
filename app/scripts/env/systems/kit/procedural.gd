extends RefCounted

## Patterns drawn here for the builders and the kit (docs/environments.md, "The builders"): nothing borrowed, nothing
## read from a file. A pattern is three maps for the house shader (scripts/env/material_library.gd's layout: albedo,
## a normal map in its G and A channels, and occlusion, roughness and metal in R, G and B), made once and shared by
## every room. A library material keeps its shader and its settings and takes the pattern's maps instead of its own
## (apply()). Pictures (a rose window, neon letters, the water round a dome) are plain colour textures for the light
## system's lamp material. Static; preload to use.
##
##   PATTERNS                    pressed_tin, ice_blocks, swirl_carpet, corrugated, plasterboard
##   maps(pattern) -> {albedo, normal, orm, mean}   the pattern's textures (mean: its albedo's mean, linear)
##   apply(material, pattern, colour)   a house material shows the pattern in this colour (on average)
##   glass(colour, alpha, room) -> ShaderMaterial   see-through glass that dims with the house lights
##   rose_window(), letters(text, colour, back), gradient(top, bottom), abstract(seed, palette), flame()   pictures

const PATTERNS: Array[String] = ["pressed_tin", "ice_blocks", "swirl_carpet", "corrugated", "plasterboard"]
const SIZE := 128
const GLASS_SHADER := preload("res://scripts/env/systems/kit/env_glass.gdshader")

static var _maps := {}
static var _pictures := {}


## A hash in 0..1 for an integer lattice point (value noise).
static func _hash(x: int, y: int, seed_value: int) -> float:
	var h := (x * 374761393 + y * 668265263 + seed_value * 1442695041) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h & 0xffff) / 65535.0


## Smooth value noise, wrapping every `period` cells.
static func _noise(u: float, v: float, period: int, seed_value: int) -> float:
	var x := u * period
	var y := v * period
	var xi := int(floor(x))
	var yi := int(floor(y))
	var fx := x - xi
	var fy := y - yi
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var a := _hash(posmod(xi, period), posmod(yi, period), seed_value)
	var b := _hash(posmod(xi + 1, period), posmod(yi, period), seed_value)
	var c := _hash(posmod(xi, period), posmod(yi + 1, period), seed_value)
	var d := _hash(posmod(xi + 1, period), posmod(yi + 1, period), seed_value)
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)


## The pattern's height (0..1), colour and roughness at u, v in 0..1 (one repeat of the tiling).
static func _sample(pattern: String, u: float, v: float) -> Array:
	match pattern:
		"pressed_tin":
			# A square tile: a raised border bead, a sunk field, a raised square, a rosette of eight petals in it,
			# beads in the corners.
			var x := absf(u - 0.5) * 2.0
			var y := absf(v - 0.5) * 2.0
			var m := maxf(x, y)
			var h := 0.5
			h += 0.35 * smoothstep(0.86, 0.9, m) * (1.0 - smoothstep(0.95, 0.99, m))
			h -= 0.2 * smoothstep(0.62, 0.66, m) * (1.0 - smoothstep(0.84, 0.88, m))
			h += 0.15 * (1.0 - smoothstep(0.56, 0.6, m))
			var r := Vector2(u - 0.5, v - 0.5).length() * 2.0
			var a := atan2(v - 0.5, u - 0.5)
			var petal := pow(absf(cos(a * 4.0)), 2.0)
			h += 0.3 * (1.0 - smoothstep(0.18 + 0.3 * petal, 0.24 + 0.3 * petal, r))
			h += 0.15 * (1.0 - smoothstep(0.06, 0.1, r))
			var cx := Vector2(x - 0.76, y - 0.76).length()
			h += 0.25 * (1.0 - smoothstep(0.05, 0.08, cx))
			var shade := lerpf(0.62, 0.86, clampf(h, 0.0, 1.0))
			return [h, Color(shade, shade, shade * 0.97), 0.45]
		"ice_blocks":
			# Blocks two across and three high a repeat, every other course moved half a block; deep seams, faint
			# cloudy veins inside.
			var row := int(floor(v * 3.0))
			var bu := fposmod(u * 2.0 + (0.5 if row % 2 == 1 else 0.0), 1.0)
			var bv := fposmod(v * 3.0, 1.0)
			var edge := minf(minf(bu, 1.0 - bu) * 2.0 * 0.5 / 0.3, minf(bv, 1.0 - bv) * 2.0)
			var h := smoothstep(0.0, 0.12, edge)
			var cloud := _noise(u, v, 8, 7) * 0.6 + _noise(u, v, 16, 9) * 0.4
			h -= 0.06 * cloud
			var c := Color(0.78, 0.88, 0.95).lerp(Color(0.93, 0.97, 1.0), cloud)
			c = c.lerp(Color(0.55, 0.7, 0.82), 1.0 - h)
			return [h, c, lerpf(0.4, 0.12, h)]
		"swirl_carpet":
			# Swirls on a dark ground: loops round four centres a repeat, in three colours, with a fleck.
			var best := 10.0
			var which := 0
			var centres := [Vector2(0.25, 0.25), Vector2(0.75, 0.3), Vector2(0.3, 0.78), Vector2(0.78, 0.76)]
			var p := Vector2(u, v)
			var ang := 0.0
			for i in centres.size():
				var d: Vector2 = p - (centres[i] as Vector2)
				d = Vector2(d.x - roundf(d.x), d.y - roundf(d.y))
				if d.length() < best:
					best = d.length()
					which = i
					ang = atan2(d.y, d.x)
			var spiral := sin(best * 60.0 - ang * 2.0 + which * 1.7)
			var band := smoothstep(0.2, 0.6, spiral)
			var palette := [Color(0.62, 0.12, 0.2), Color(0.1, 0.42, 0.45), Color(0.82, 0.58, 0.18), Color(0.45, 0.2, 0.55)]
			var ground := Color(0.12, 0.06, 0.12)
			var c: Color = ground.lerp(palette[which], band * (1.0 - smoothstep(0.2, 0.3, best)))
			var fleck := _noise(u, v, 64, 3)
			c = c.lerp(Color(0.85, 0.75, 0.5), smoothstep(0.85, 0.95, fleck) * 0.6)
			return [0.5 + 0.1 * fleck, c, 0.95]
		"corrugated":
			var h := 0.5 + 0.5 * sin(u * TAU * 6.0)
			var rust := _noise(u, v, 8, 11)
			var c := Color(0.7, 0.7, 0.72).lerp(Color(0.5, 0.36, 0.25), smoothstep(0.6, 0.9, rust) * 0.5)
			return [h, c, lerpf(0.45, 0.8, rust)]
		"plasterboard":
			# A sheet's taped joint at the repeat's edge, faint screw heads along it.
			var joint := minf(u, 1.0 - u)
			var h := 1.0 - 0.3 * (1.0 - smoothstep(0.0, 0.04, joint))
			for k in 6:
				var d := Vector2(joint - 0.02, v - (k + 0.5) / 6.0).length()
				h -= 0.15 * (1.0 - smoothstep(0.004, 0.008, d))
			var s := 0.9 - 0.04 * _noise(u, v, 16, 5)
			return [h, Color(s, s * 0.99, s * 0.96), 0.85]
	return [0.5, Color(0.5, 0.5, 0.5), 0.8]


## The pattern's maps, made once (SIZE square, mipmapped).
static func maps(pattern: String) -> Dictionary:
	if _maps.has(pattern):
		return _maps[pattern]
	var heights := PackedFloat32Array()
	heights.resize(SIZE * SIZE)
	var albedo := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var normal := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var orm := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var rough := PackedFloat32Array()
	rough.resize(SIZE * SIZE)
	var mean := Color(0, 0, 0)
	for y in SIZE:
		for x in SIZE:
			var s := _sample(pattern, (x + 0.5) / SIZE, (y + 0.5) / SIZE)
			heights[y * SIZE + x] = float(s[0])
			rough[y * SIZE + x] = float(s[2])
			var c: Color = s[1]
			albedo.set_pixel(x, y, c)
			var lin := c.srgb_to_linear()
			mean += Color(lin.r, lin.g, lin.b) / float(SIZE * SIZE)
	# Relief: the height's slope over a texel, a few millimetres deep.
	var depth := 3.0
	for y in SIZE:
		for x in SIZE:
			var hx := heights[y * SIZE + (x + 1) % SIZE] - heights[y * SIZE + (x - 1 + SIZE) % SIZE]
			var hy := heights[((y + 1) % SIZE) * SIZE + x] - heights[((y - 1 + SIZE) % SIZE) * SIZE + x]
			var n := Vector3(-hx * depth, hy * depth, 1.0).normalized()
			normal.set_pixel(x, y, Color(0.5, n.x * 0.5 + 0.5, 0.5, n.y * 0.5 + 0.5))
			var h := heights[y * SIZE + x]
			orm.set_pixel(x, y, Color(clampf(0.65 + 0.35 * h, 0.0, 1.0), rough[y * SIZE + x],
					0.35 if pattern in ["pressed_tin", "corrugated"] else 0.0))
	for img: Image in [albedo, normal, orm]:
		img.generate_mipmaps()
	var out := {"albedo": ImageTexture.create_from_image(albedo), "normal": ImageTexture.create_from_image(normal),
			"orm": ImageTexture.create_from_image(orm), "mean": mean}
	_maps[pattern] = out
	return out


## The house material `m` (a library material from the light system) shows the pattern, `colour` on average.
static func apply(m: ShaderMaterial, pattern: String, colour: Color) -> void:
	if not (pattern in PATTERNS) or m == null:
		return
	var p := maps(pattern)
	m.set_shader_parameter("albedo_map", p["albedo"])
	m.set_shader_parameter("normal_map", p["normal"])
	m.set_shader_parameter("orm_map", p["orm"])
	m.set_shader_parameter("normal_strength", 1.0)
	var mean: Color = p["mean"]
	var c := colour.srgb_to_linear()
	m.set_shader_parameter("tint", Color(c.r / maxf(mean.r, 0.01), c.g / maxf(mean.g, 0.01),
			c.b / maxf(mean.b, 0.01)).linear_to_srgb())


## See-through glass: a faint tint, a brighter rim at a glancing view, dimming with the house lights. Blended, never
## multiplied (the Mobile renderer's luminance multiplier).
static func glass(colour: Color, alpha: float, house_reference: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = GLASS_SHADER
	m.set_shader_parameter("colour", Vector3(colour.r, colour.g, colour.b))
	m.set_shader_parameter("alpha", alpha)
	m.set_shader_parameter("house_reference", house_reference)
	return m


## A rose window from inside: coloured glass in twelve petals round a hub, dark tracery, a ring of roundels.
static func rose_window() -> Texture2D:
	if _pictures.has("rose"):
		return _pictures["rose"]
	var n := 128
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGB8)
	var glass := [Color(0.12, 0.2, 0.62), Color(0.62, 0.1, 0.12), Color(0.75, 0.55, 0.15), Color(0.15, 0.45, 0.25)]
	for y in n:
		for x in n:
			var p := Vector2((x + 0.5) / n - 0.5, (y + 0.5) / n - 0.5) * 2.0
			var r := p.length()
			var a := fposmod(atan2(p.y, p.x), TAU)
			var c := Color(0.02, 0.02, 0.025)
			if r < 0.97:
				var petal := fposmod(a * 12.0 / TAU, 1.0)
				var k := int(a * 12.0 / TAU)
				c = glass[k % 4]
				var lead := minf(petal, 1.0 - petal) * r * 6.0
				if r < 0.22:
					c = glass[2] if r > 0.08 else glass[1]
				elif r > 0.78:
					var cell := Vector2(fposmod(a * 24.0 / TAU, 1.0) - 0.5, (r - 0.875) * 10.0)
					c = glass[(k + 1) % 4] if cell.length() < 0.42 else Color(0.03, 0.03, 0.035)
				elif lead < 0.06 or absf(r - 0.5) < 0.012:
					c = Color(0.03, 0.03, 0.035)
				else:
					c = c * (0.75 + 0.25 * _noise(p.x * 0.5 + 0.5, p.y * 0.5 + 0.5, 32, 4))
				if absf(r - 0.22) < 0.015 or absf(r - 0.78) < 0.015:
					c = Color(0.03, 0.03, 0.035)
			img.set_pixel(x, y, c)
	var t := ImageTexture.create_from_image(img)
	_pictures["rose"] = t
	return t


## Upper-case letters and a space in a 5 x 7 face, colour on back (a sign's lettering; nothing borrowed).
const GLYPHS := {
	"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
	"B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
	"C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
	"D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
	"E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
	"F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
	"I": ["111", "010", "010", "010", "010", "010", "111"],
	"K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
	"L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
	"N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
	"O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
	"P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
	"R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
	"S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
	"T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
	"U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
	"W": ["10001", "10001", "10001", "10101", "10101", "11011", "10001"],
	" ": ["000", "000", "000", "000", "000", "000", "000"],
}


static func letters(text: String, colour: Color, back: Color) -> Texture2D:
	var key := "%s %s %s" % [text, colour, back]
	if _pictures.has(key):
		return _pictures[key]
	var w := 2
	for ch in text:
		w += (GLYPHS.get(ch, GLYPHS[" "])[0] as String).length() + 1
	var img := Image.create_empty(w + 1, 11, false, Image.FORMAT_RGB8)
	img.fill(back)
	var x := 2
	for ch in text:
		var rows: Array = GLYPHS.get(ch, GLYPHS[" "])
		for y in rows.size():
			var line: String = rows[y]
			for i in line.length():
				if line[i] == "1":
					img.set_pixel(x + i, 2 + y, colour)
		x += (rows[0] as String).length() + 1
	var t := ImageTexture.create_from_image(img)
	_pictures[key] = t
	return t


## A vertical gradient (UV.y 0 at the top), for the water round a glass dome.
static func gradient(top: Color, bottom: Color) -> Texture2D:
	var key := "gradient %s %s" % [top, bottom]
	if _pictures.has(key):
		return _pictures[key]
	var img := Image.create_empty(4, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		var f := float(y) / 63.0
		for x in 4:
			img.set_pixel(x, y, top.lerp(bottom, pow(f, 0.7)))
	var t := ImageTexture.create_from_image(img)
	_pictures[key] = t
	return t


## An abstract painting of our own: soft blocks of colour on a ground, a few bands across (a mid-century canvas or
## a bedroom poster). seed_value picks the layout; palette: [ground, colours...].
static func abstract(seed_value: int, palette: Array) -> Texture2D:
	var key := "abstract %d %s" % [seed_value, palette]
	if _pictures.has(key):
		return _pictures[key]
	var w := 96
	var h := 64
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var ground: Color = palette[0]
	var blocks: Array = []
	for k in 6:
		var c: Color = palette[1 + k % (palette.size() - 1)]
		var r := Rect2(rng.randf_range(0.05, 0.7), rng.randf_range(0.05, 0.7), rng.randf_range(0.15, 0.4),
				rng.randf_range(0.12, 0.35))
		blocks.append([r, c])
	for y in h:
		for x in w:
			var p := Vector2((x + 0.5) / w, (y + 0.5) / h)
			var c := ground * (0.92 + 0.08 * _noise(p.x, p.y, 16, seed_value))
			for bl: Array in blocks:
				var r: Rect2 = bl[0]
				var d := maxf(maxf(r.position.x - p.x, p.x - r.end.x), maxf(r.position.y - p.y, p.y - r.end.y))
				var a := 1.0 - smoothstep(-0.01, 0.01, d + 0.01 * _noise(p.x, p.y, 24, seed_value + 3))
				c = c.lerp(bl[1], a * 0.85)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_pictures[key] = t
	return t


## A flame from the side (UV.y 0 at the top): bright yellow at its root, orange, fading to nothing at the tip and the
## sides. Drawn additively by nothing: a lamp picture, black where there is no flame.
static func flame() -> Texture2D:
	if _pictures.has("flame"):
		return _pictures["flame"]
	var w := 32
	var h := 48
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			var u := (x + 0.5) / w - 0.5
			var v := 1.0 - (y + 0.5) / h
			var half := 0.42 * pow(1.0 - v, 0.6) * (1.0 - smoothstep(0.85, 1.0, v)) * (0.6 + 0.4 * sin(v * 3.0))
			var a := 1.0 - smoothstep(half * 0.6, half, absf(u))
			var c := Color(1.0, 0.85, 0.4).lerp(Color(0.9, 0.35, 0.08), smoothstep(0.1, 0.6, v))
			img.set_pixel(x, y, c * a * (1.0 - smoothstep(0.6, 1.0, v)))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_pictures["flame"] = t
	return t
