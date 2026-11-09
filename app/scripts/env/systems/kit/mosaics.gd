extends RefCounted

## Wall mosaics of our own design (docs/environments.md, "Room: Palace of Culture 1974"; since 2026-11-08: "The
## mosaics are the soul: large monumental wall mosaics of our own design with no people (cosmos, atoms and orbits,
## sunbursts, stylised birds, wheat, rockets, waves, abstract geometry)", the brief). Each is drawn here, tessera by
## tessera, into a map of one texel per tessera for the mosaic shader (shaders/room_material_house_mosaic.gdshader):
## rgb the tessera's colour (sRGB), alpha what it is (0 stone, 128 coloured glass, 255 gold). Drawn from shapes in the
## mural's own metres (x across from its left as seen, y up from its foot): discs, rings, ellipses, rays, polygons and
## lines, painted in order over a background whose courses swirl round the mural's centre of interest (the andamento
## a mosaicist lays round a sun). Nothing borrowed; no figure, no emblem of any state. Static; preload to use.
##
##   atlas(width_m, height_m, tessera_m) -> ImageTexture   both murals, the cosmos above the earth (rows 0 .. h-1
##                                                        the cosmos, h .. 2h-1 the earth; v down)
##   COSMOS, EARTH   which half of the atlas

## The palette: smalti and stone [sRGB colour, kind (0 stone, 0.5 glass, 1 gold)].
const NIGHT := [Color(0.05, 0.06, 0.13), 0.5]
const ULTRA := [Color(0.09, 0.14, 0.4), 0.5]
const COBALT := [Color(0.14, 0.27, 0.6), 0.5]
const SKY := [Color(0.36, 0.56, 0.76), 0.5]
const TURQ := [Color(0.12, 0.52, 0.55), 0.5]
const WHITE := [Color(0.9, 0.89, 0.84), 0.0]
const CREAM := [Color(0.88, 0.8, 0.62), 0.0]
const GOLD := [Color(0.88, 0.68, 0.3), 1.0]
const PALE_GOLD := [Color(0.95, 0.82, 0.5), 1.0]
const PEACH := [Color(0.93, 0.66, 0.5), 0.5]
const AQUA := [Color(0.58, 0.76, 0.79), 0.5]
const OCHRE := [Color(0.76, 0.5, 0.17), 0.5]
const ORANGE := [Color(0.86, 0.38, 0.11), 0.5]
const RED := [Color(0.66, 0.13, 0.1), 0.5]
const BROWN := [Color(0.34, 0.2, 0.12), 0.0]
const GREEN := [Color(0.2, 0.42, 0.26), 0.5]
const OLIVE := [Color(0.46, 0.48, 0.24), 0.5]
const GREY := [Color(0.52, 0.51, 0.5), 0.0]
const BLACK := [Color(0.07, 0.07, 0.08), 0.0]

const COSMOS := 0
const EARTH := 1

const ProcCache := preload("res://scripts/env/proc_cache.gd")

static var _atlas := {}


## A mural being painted: its size in tesserae, the tessera's size, and the atlas's bytes it writes into.
class Canvas:
	var w: int
	var h: int
	var t: float
	var row0: int
	var data: PackedByteArray
	var atlas_w: int

	func _init(width: int, height: int, tessera: float, first_row: int, bytes: PackedByteArray, aw: int) -> void:
		w = width
		h = height
		t = tessera
		row0 = first_row
		data = bytes
		atlas_w = aw

	## The tessera at column i, row j (j 0 at the mural's foot).
	func put(i: int, j: int, c: Array) -> void:
		if i < 0 or j < 0 or i >= w or j >= h:
			return
		var k := ((row0 + (h - 1 - j)) * atlas_w + i) * 4
		var col: Color = c[0]
		data[k] = int(clampf(col.r, 0.0, 1.0) * 255.0)
		data[k + 1] = int(clampf(col.g, 0.0, 1.0) * 255.0)
		data[k + 2] = int(clampf(col.b, 0.0, 1.0) * 255.0)
		data[k + 3] = int(clampf(float(c[1]), 0.0, 1.0) * 255.0)

	## The middle of tessera (i, j) in the mural's metres.
	func at(i: int, j: int) -> Vector2:
		return Vector2((i + 0.5) * t, (j + 0.5) * t)

	## Every tessera whose middle is inside the box [lo, hi] (metres) and for which f(p) gives a colour (an Array) or
	## null (left as it is).
	func paint(lo: Vector2, hi: Vector2, f: Callable) -> void:
		var i0 := maxi(0, int(floor(lo.x / t)))
		var i1 := mini(w - 1, int(ceil(hi.x / t)))
		var j0 := maxi(0, int(floor(lo.y / t)))
		var j1 := mini(h - 1, int(ceil(hi.y / t)))
		for j in range(j0, j1 + 1):
			for i in range(i0, i1 + 1):
				var c: Variant = f.call(at(i, j))
				if c != null:
					put(i, j, c)

	func disc(centre: Vector2, r: float, c: Array) -> void:
		paint(centre - Vector2(r, r), centre + Vector2(r, r), func(p: Vector2) -> Variant:
			return c if p.distance_to(centre) <= r else null)

	func ring(centre: Vector2, r0: float, r1: float, c: Array) -> void:
		paint(centre - Vector2(r1, r1), centre + Vector2(r1, r1), func(p: Vector2) -> Variant:
			var d := p.distance_to(centre)
			return c if d >= r0 and d <= r1 else null)

	## An ellipse's outline: half axes a, b, turned by `turn` radians, `width` metres wide.
	func ellipse(centre: Vector2, a: float, b: float, turn: float, width: float, c: Array) -> void:
		var r := maxf(a, b) + width
		var cs := cos(turn)
		var sn := sin(turn)
		paint(centre - Vector2(r, r), centre + Vector2(r, r), func(p: Vector2) -> Variant:
			var d := p - centre
			var q := Vector2(d.x * cs + d.y * sn, -d.x * sn + d.y * cs)
			# The distance to the outline, near enough: the ellipse's implicit value over its gradient's length.
			var f := (q.x * q.x) / (a * a) + (q.y * q.y) / (b * b) - 1.0
			var g := Vector2(2.0 * q.x / (a * a), 2.0 * q.y / (b * b)).length()
			return c if absf(f) / maxf(g, 0.0001) <= width * 0.5 else null)

	func poly(points: PackedVector2Array, c: Array) -> void:
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for p: Vector2 in points:
			lo = lo.min(p)
			hi = hi.max(p)
		paint(lo, hi, func(p: Vector2) -> Variant:
			return c if Geometry2D.is_point_in_polygon(p, points) else null)

	func line(a: Vector2, b: Vector2, width: float, c: Array) -> void:
		var lo := a.min(b) - Vector2(width, width)
		var hi := a.max(b) + Vector2(width, width)
		paint(lo, hi, func(p: Vector2) -> Variant:
			return c if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) <= width * 0.5 else null)

	## A star of `points` points (4: a twinkle), its tips r out, its waist r * waist.
	func star(centre: Vector2, r: float, c: Array, points := 4, waist := 0.32, turn := 0.0) -> void:
		var pts := PackedVector2Array()
		for k in points * 2:
			var a := turn + PI * k / points + PI * 0.5
			var rr := r if k % 2 == 0 else r * waist
			pts.append(centre + Vector2(cos(a), sin(a)) * rr)
		poly(pts, c)


## Both murals in one map (cached): the cosmos in the upper half, the earth in the lower.
static func atlas(width_m: float, height_m: float, tessera_m: float) -> ImageTexture:
	var key := "%s %s %s" % [width_m, height_m, tessera_m]
	if _atlas.has(key):
		return _atlas[key]
	var img := ProcCache.image("mosaics.gd:_atlas:" + key,
			func() -> Image: return _draw_atlas(width_m, height_m, tessera_m))
	var tex := ImageTexture.create_from_image(img)
	_atlas[key] = tex
	return tex


static func _draw_atlas(width_m: float, height_m: float, tessera_m: float) -> Image:
	var w := int(round(width_m / tessera_m))
	var h := int(round(height_m / tessera_m))
	var data := PackedByteArray()
	data.resize(w * h * 2 * 4)
	var cosmos := Canvas.new(w, h, tessera_m, 0, data, w)
	_cosmos(cosmos, width_m, height_m)
	var earth := Canvas.new(w, h, tessera_m, h, cosmos.data, w)
	_earth(earth, width_m, height_m)
	return Image.create_from_data(w, h * 2, false, Image.FORMAT_RGBA8, earth.data)


## A hash in 0..1 for a tessera (the background's speckle: no two tesserae of a field quite alike).
static func _h(p: Vector2, s: int) -> float:
	var x := int(floor(p.x * 100.0))
	var y := int(floor(p.y * 100.0))
	var k := (x * 374761393 + y * 668265263 + s * 1442695041) & 0x7fffffff
	k = ((k ^ (k >> 13)) * 1274126177) & 0x7fffffff
	return float(k & 0xffff) / 65535.0


static func _mixc(a: Array, b: Array, f: float) -> Array:
	return [(a[0] as Color).lerp(b[0], f), lerpf(float(a[1]), float(b[1]), f)]


# --- The cosmos (the left wall: its left end at the back of the hall, its right end towards the screen) ---------------

## Night: the courses swirl round the sun, every third ring a shade apart; a comet, a crescent moon, a ringed planet,
## an atom's three orbits round its nucleus, a rocket climbing on its trail, the sun in gold with its rays, stars of
## gold and white; waves along the foot; a border of black and gold.
static func _cosmos(cv: Canvas, wm: float, hm: float) -> void:
	var sun := Vector2(wm * 0.73, hm * 0.6)
	var t := cv.t
	# The ground: night deepening upwards, laid in rings round the sun.
	cv.paint(Vector2.ZERO, Vector2(wm, hm), func(p: Vector2) -> Variant:
		var ring := int(floor(p.distance_to(sun) / (t * 3.0)))
		var up := clampf(p.y / hm, 0.0, 1.0)
		var base: Array = _mixc(COBALT, ULTRA, smoothstep(0.1, 0.55, up))
		base = _mixc(base, NIGHT, smoothstep(0.55, 1.0, up))
		var shade := 0.93 if ring % 2 == 0 else 1.04
		var c: Color = base[0]
		c = c * (shade + 0.06 * (_h(p, 3) - 0.5))
		# A few lost tesserae of a brighter blue in the night (the mosaicist's sparkle).
		if _h(p, 5) > 0.985:
			return SKY
		return [c, base[1]])
	# The sun: rays in gold and ochre, long and short, a white ring, an orange ring, the gold disc with a pale core.
	for k in 24:
		var a := TAU * k / 24.0
		var long := k % 2 == 0
		var r0 := 1.25
		var r1 := 2.9 if long else 2.15
		var half := 0.17 if long else 0.12
		var dir := Vector2(cos(a), sin(a))
		var side := Vector2(-dir.y, dir.x)
		cv.poly(PackedVector2Array([sun + dir * r0 + side * half, sun + dir * r1, sun + dir * r0 - side * half]),
				GOLD if long else OCHRE)
	cv.ring(sun, 1.12, 1.24, WHITE)
	cv.disc(sun, 1.12, ORANGE)
	cv.disc(sun, 0.95, GOLD)
	cv.disc(sun, 0.45, PALE_GOLD)
	cv.ring(sun, 0.62, 0.68, OCHRE)
	# The atom: three orbits round a nucleus, an electron on each.
	var atom := Vector2(wm * 0.33, hm * 0.56)
	for k in 3:
		var turn := PI * k / 3.0 + 0.3
		cv.ellipse(atom, 1.85, 0.62, turn, 0.09, WHITE)
		var e := atom + Vector2(cos(turn), sin(turn)) * 1.85 * (1.0 if k != 1 else -1.0)
		cv.disc(e, 0.14, GOLD)
	for k in 7:
		var a := TAU * k / 7.0
		cv.disc(atom + Vector2(cos(a), sin(a)) * 0.17, 0.13, RED if k % 2 == 0 else WHITE)
	cv.disc(atom, 0.12, RED)
	# The rocket: climbing to the right between the atom and the sun, its trail curving down to the waves.
	var base_r := Vector2(wm * 0.47, hm * 0.2)
	var tip := Vector2(wm * 0.56, hm * 0.84)
	var axis := (tip - base_r).normalized()
	var across := Vector2(-axis.y, axis.x)
	var body_from := base_r.lerp(tip, 0.45)
	# The trail: three tongues of flame, red outside, orange, gold at the heart.
	for f: Array in [[0.32, RED], [0.22, ORANGE], [0.11, GOLD]]:
		var wdt: float = f[0]
		var pts := PackedVector2Array()
		var back := PackedVector2Array()
		for s in 13:
			var u := float(s) / 12.0
			var p := body_from.lerp(base_r - axis * 0.4, u) + across * sin(u * 2.4) * 0.35
			var ww := wdt * (1.0 - u * 0.75)
			pts.append(p + across * ww)
			back.append(p - across * ww)
		back.reverse()
		pts.append_array(back)
		cv.poly(pts, f[1])
	var body := PackedVector2Array([body_from + across * 0.23, body_from.lerp(tip, 0.72) + across * 0.25,
			tip, body_from.lerp(tip, 0.72) - across * 0.25, body_from - across * 0.23])
	cv.poly(body, WHITE)
	cv.poly(PackedVector2Array([body_from.lerp(tip, 0.72) + across * 0.25, tip, body_from.lerp(tip, 0.72)
			- across * 0.25]), RED)
	# Fins, a window and two bands.
	for s: float in [-1.0, 1.0]:
		cv.poly(PackedVector2Array([body_from + across * 0.23 * s, body_from + axis * 0.55 + across * 0.25 * s,
				body_from - axis * 0.12 + across * 0.55 * s]), RED)
	cv.disc(body_from.lerp(tip, 0.55), 0.12, COBALT)
	cv.ring(body_from.lerp(tip, 0.55), 0.12, 0.17, GREY)
	cv.line(body_from.lerp(tip, 0.2) + across * 0.23, body_from.lerp(tip, 0.2) - across * 0.23, 0.07, GREY)
	# The crescent moon (back end, high), a ringed planet (low), a comet with its tail.
	var moon := Vector2(wm * 0.1, hm * 0.78)
	cv.paint(moon - Vector2(0.62, 0.62), moon + Vector2(0.62, 0.62), func(p: Vector2) -> Variant:
		return CREAM if p.distance_to(moon) <= 0.62 and p.distance_to(moon + Vector2(0.3, 0.17)) > 0.55 else null)
	var planet := Vector2(wm * 0.12, hm * 0.36)
	cv.ellipse(planet, 0.95, 0.24, -0.25, 0.08, OCHRE)
	cv.disc(planet, 0.42, TURQ)
	cv.disc(planet + Vector2(-0.1, 0.12), 0.18, SKY)
	cv.ellipse(planet, 0.95, 0.24, -0.25, 0.04, GOLD)
	var comet := Vector2(wm * 0.24, hm * 0.9)
	for k in 5:
		var off := float(k) * 0.12
		cv.line(comet + Vector2(0.1, -0.06 * k + 0.12), comet + Vector2(-1.6 + off, 0.4 - 0.08 * k), 0.06,
				WHITE if k % 2 == 0 else SKY)
	cv.disc(comet, 0.16, PALE_GOLD)
	# Stars: four-pointed in gold and white, single tesserae of white between.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1974
	var placed: Array[Vector2] = [sun, atom, moon, planet, comet, body_from.lerp(tip, 0.5)]
	var keep_off: Array[float] = [3.1, 2.2, 0.9, 1.1, 0.9, 1.0]
	for k in 46:
		var p := Vector2(rng.randf_range(0.4, wm - 0.4), rng.randf_range(1.2, hm - 0.4))
		var ok := true
		for q in placed.size():
			if p.distance_to(placed[q]) < keep_off[q]:
				ok = false
				break
		if not ok:
			continue
		var big := rng.randf() < 0.3
		cv.star(p, rng.randf_range(0.22, 0.34) if big else rng.randf_range(0.1, 0.16),
				GOLD if rng.randf() < 0.55 else WHITE, 4, 0.3, rng.randf_range(-0.2, 0.2))
	for k in 260:
		var p := Vector2(rng.randf_range(0.3, wm - 0.3), rng.randf_range(1.0, hm - 0.3))
		if p.distance_to(sun) < 3.0:
			continue
		cv.put(int(p.x / t), int(p.y / t), WHITE if rng.randf() < 0.7 else PALE_GOLD)
	_waves(cv, wm, 0.95, [TURQ, COBALT, ULTRA])
	_border(cv, wm, hm)


# --- The earth (the right wall: its left end towards the screen, its right end at the back) -----------------------------

## Dawn over the fields: a sky in bands from blue to cream, the sun rising on the horizon in rings of gold and orange,
## a flight of birds gliding, a sheaf of wheat, furrows running away to the horizon, a river of waves along the foot,
## the border.
static func _earth(cv: Canvas, wm: float, hm: float) -> void:
	var horizon := hm * 0.46
	var sun := Vector2(wm * 0.27, horizon)
	var t := cv.t
	# The sky: bands from blue overhead to cream at the horizon, laid in arcs round the rising sun.
	cv.paint(Vector2(0.0, horizon), Vector2(wm, hm), func(p: Vector2) -> Variant:
		var d := p.distance_to(sun)
		var ring := int(floor(d / (t * 3.0)))
		var k := clampf((d - 1.6) / (hm * 1.1), 0.0, 1.0)
		var base: Array
		if k < 0.12:
			base = _mixc(CREAM, PALE_GOLD, 0.35)
		elif k < 0.24:
			base = CREAM
		elif k < 0.36:
			base = PEACH
		elif k < 0.5:
			base = AQUA
		elif k < 0.7:
			base = SKY
		else:
			base = _mixc(SKY, COBALT, smoothstep(0.7, 1.0, k))
		var c: Color = base[0]
		c = c * ((0.95 if ring % 2 == 0 else 1.03) + 0.05 * (_h(p, 7) - 0.5)) * 0.86
		return [c, base[1]])
	# The sun's rings and rays over the horizon.
	for k in 15:
		var a := PI * (k + 0.5) / 15.0
		var dir := Vector2(cos(a), sin(a))
		var side := Vector2(-dir.y, dir.x)
		var long := k % 2 == 0
		cv.poly(PackedVector2Array([sun + dir * 1.45 + side * 0.12, sun + dir * (2.7 if long else 2.1),
				sun + dir * 1.45 - side * 0.12]), OCHRE if long else ORANGE)
	cv.disc(sun, 1.35, ORANGE)
	cv.disc(sun, 1.12, GOLD)
	cv.ring(sun, 0.7, 0.78, ORANGE)
	cv.disc(sun, 0.45, PALE_GOLD)
	# The fields: furrows running to a point on the horizon, in bands of ochre, gold, olive and brown.
	var vanish := Vector2(wm * 0.56, horizon + 0.6)
	var field_cols := [OCHRE, GOLD, OLIVE, OCHRE, BROWN, GOLD, OLIVE, OCHRE]
	cv.paint(Vector2(0.0, 0.0), Vector2(wm, horizon), func(p: Vector2) -> Variant:
		var d := p - vanish
		var a := atan2(d.x, -d.y)
		var band := int(floor((a + PI) / (PI / 22.0)))
		var c: Array = field_cols[posmod(band, field_cols.size())]
		var col: Color = c[0]
		# Further fields paler (the air), a furrow's dark line between bands.
		col = col.lerp(Color(0.86, 0.78, 0.6), smoothstep(horizon * 0.4, horizon, p.y) * 0.45)
		var edge := fposmod((a + PI) / (PI / 22.0), 1.0)
		if edge < 0.08:
			col = col * 0.72
		return [col * (0.96 + 0.08 * _h(p, 9)) * 0.9, c[1]])
	# The horizon line: a row of green hedges and a thin line of gold.
	cv.paint(Vector2(0.0, horizon - 0.12), Vector2(wm, horizon + 0.02), func(p: Vector2) -> Variant:
		if p.distance_to(sun) < 1.35:
			return null
		return GREEN if p.y < horizon - 0.04 else GOLD)
	# Wheat: a sheaf standing in the field, its stalks bound with a red band and fanning out into five great ears.
	_sheaf(cv, Vector2(wm * 0.74, 1.05), 1.5)
	# A flight of birds across the dawn, gliding towards the screen, smaller and higher towards the back.
	var birds := [[0.4, 0.78, 2.4, 0.05], [0.5, 0.68, 2.0, -0.08], [0.53, 0.88, 1.7, 0.1], [0.88, 0.84, 1.5, 0.06],
			[0.94, 0.72, 1.2, -0.1], [0.96, 0.92, 1.0, 0.0]]
	for b: Array in birds:
		_bird(cv, Vector2(wm * float(b[0]), hm * float(b[1])), float(b[2]), float(b[3]))
	# A second sun's echo: a few gold stars of morning in the high blue.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1975
	for k in 18:
		var p := Vector2(rng.randf_range(wm * 0.45, wm - 0.4), rng.randf_range(hm * 0.88, hm - 0.35))
		cv.star(p, rng.randf_range(0.08, 0.14), PALE_GOLD, 4, 0.3)
	_waves(cv, wm, 0.95, [TURQ, COBALT, ULTRA])
	_border(cv, wm, hm)


## A sheaf of wheat: stalks from the ground to a band of twine at `tie` metres up, fanning out over it to five ears.
## The twine is brown, not red: a sheaf with a red ribbon is close to a state's emblem, and the brief says none.
static func _sheaf(cv: Canvas, foot: Vector2, tie: float) -> void:
	var band := foot + Vector2(0.0, tie)
	for k in 5:
		var a := (k - 2) * 0.24
		var low := foot + Vector2((k - 2) * 0.22, 0.0)
		cv.line(low, band, 0.09, OCHRE)
		var dir := Vector2(sin(a), cos(a))
		var top := band + dir * (2.1 - 0.2 * absf(k - 2))
		var bend := Vector2(dir.y, -dir.x) * 0.25 * signf(a)
		var mid := band.lerp(top, 0.5) + bend * 0.5
		cv.line(band, mid, 0.08, OCHRE)
		cv.line(mid, top, 0.08, GOLD)
		_ear(cv, top, (top - mid).normalized(), 1.55)
	# Two leaves curling out at the band.
	for s2: float in [-1.0, 1.0]:
		cv.poly(PackedVector2Array([band + Vector2(0.0, -0.3), band + Vector2(s2 * 0.9, 0.6),
				band + Vector2(s2 * 1.6, 1.4), band + Vector2(s2 * 0.6, 0.35)]), OLIVE)
	cv.paint(band - Vector2(0.55, 0.16), band + Vector2(0.55, 0.16), func(p: Vector2) -> Variant:
		return BROWN if absf(p.y - band.y) < 0.12 else null)


## A wheat ear from `at` along `dir`, `length` metres: kernels in pairs either side of the stem, each turned out a
## little, long awns of gold rising from them.
static func _ear(cv: Canvas, at: Vector2, dir: Vector2, length: float) -> void:
	var side := Vector2(-dir.y, dir.x)
	cv.line(at - dir * 0.1, at + dir * length, 0.06, GOLD)
	for k in 9:
		var u := 0.08 + 0.105 * k
		var c := at + dir * length * u
		var size := 0.25 * (1.0 - 0.05 * k)
		for s: float in [-1.0, 1.0]:
			var out := (dir * 0.55 + side * s).normalized()
			var kc := c + out * size * 0.55
			var pts := PackedVector2Array()
			for m in 12:
				var a := TAU * m / 12.0
				var r := Vector2(cos(a) * size * 0.32, sin(a) * size * 0.62)
				var axis := (out + dir).normalized()
				var nrm := Vector2(-axis.y, axis.x)
				pts.append(kc + nrm * r.x + axis * r.y)
			cv.poly(pts, GOLD if (k + int(s > 0.0)) % 2 == 0 else PALE_GOLD)
			cv.line(kc + (out + dir).normalized() * size * 0.5, kc + (dir * 1.6 + side * s * 0.35).normalized() * 0.9,
					0.035, OCHRE)
	cv.disc(at + dir * length * 1.02, 0.1, PALE_GOLD)


## A bird gliding, seen from below and a little behind: wings spread in a shallow M (a gull's crook at the wrist),
## black at their tips, a fanned tail, its head turned towards the screen (left). `size`: metres from tip to tip.
static func _bird(cv: Canvas, at: Vector2, size: float, tilt: float) -> void:
	var cs := cos(tilt)
	var sn := sin(tilt)
	var k := size * 0.5
	var f := func(v: Vector2) -> Vector2: return at + Vector2(v.x * cs - v.y * sn, v.x * sn + v.y * cs) * k
	for side: float in [-1.0, 1.0]:
		# The wing from the shoulder up to the wrist, then down and out to the tip; its trailing edge back in.
		var wing := [Vector2(0.0, 0.06), Vector2(0.28, 0.3), Vector2(0.5, 0.36), Vector2(0.98, 0.12),
				Vector2(0.62, 0.16), Vector2(0.44, 0.14), Vector2(0.24, 0.06), Vector2(0.08, -0.06)]
		var pts := PackedVector2Array()
		for v: Vector2 in wing:
			pts.append(f.call(Vector2(v.x * side, v.y)))
		cv.poly(pts, WHITE if side < 0.0 else CREAM)
		cv.poly(PackedVector2Array([f.call(Vector2(0.72 * side, 0.27)), f.call(Vector2(0.98 * side, 0.12)),
				f.call(Vector2(0.66 * side, 0.15))]), BLACK)
	var body := PackedVector2Array()
	for m in 12:
		var a := TAU * m / 12.0
		body.append(f.call(Vector2(cos(a) * 0.09, sin(a) * 0.2 - 0.04)))
	cv.poly(body, WHITE)
	cv.poly(PackedVector2Array([f.call(Vector2(-0.05, -0.18)), f.call(Vector2(0.05, -0.18)),
			f.call(Vector2(0.11, -0.36)), f.call(Vector2(-0.11, -0.36))]), CREAM)
	cv.disc(f.call(Vector2(-0.03, 0.17)), 0.07 * k, WHITE)
	cv.line(f.call(Vector2(-0.07, 0.18)), f.call(Vector2(-0.17, 0.16)), 0.03 * k, OCHRE)


## Waves along the mural's foot: scales of concentric arcs in rows (each row half a scale along from the last and
## laid over the one above it), in the waves' colours, under a gold line.
static func _waves(cv: Canvas, wm: float, top: float, cols: Array) -> void:
	var t := cv.t
	var r := 0.34
	var rh := r * 0.5
	cv.paint(Vector2(0.0, 0.0), Vector2(wm, top), func(p: Vector2) -> Variant:
		var lo := int(ceil((p.y - r) / rh))
		var hi := int(floor((p.y + r) / rh))
		for row in range(lo, hi + 1):
			var off := 0.5 * float(posmod(row, 2))
			var cx: float = (round(p.x / (2.0 * r) - off) + off) * 2.0 * r
			var d := p.distance_to(Vector2(cx, row * rh))
			if d < r:
				# From the rim in: a white line, then the colours ring by ring.
				if d > r - t * 1.1:
					return WHITE
				var ring := int(floor((r - d) / (t * 1.6)))
				return cols[ring % cols.size()]
		return cols[0])
	cv.paint(Vector2(0.0, top - t), Vector2(wm, top + t), func(p: Vector2) -> Variant:
		return GOLD if absf(p.y - top) < t * 0.75 else null)


## The border: a course of black, one of gold, one of black round the mural.
static func _border(cv: Canvas, wm: float, hm: float) -> void:
	var t := cv.t
	cv.paint(Vector2.ZERO, Vector2(wm, hm), func(p: Vector2) -> Variant:
		var e := minf(minf(p.x, wm - p.x), minf(p.y, hm - p.y))
		if e < t:
			return BLACK
		if e < t * 2.0:
			return GOLD
		if e < t * 3.0:
			return BLACK
		return null)
