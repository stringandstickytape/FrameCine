extends RefCounted

## Patterns drawn here for the builders and the kit (docs/environments.md, "The builders"): nothing borrowed, nothing
## read from a file. A pattern is three maps for the house shader (scripts/env/material_library.gd's layout: albedo,
## a normal map in its G and A channels, and occlusion, roughness and metal in R, G and B), made once and shared by
## every room. A library material keeps its shader and its settings and takes the pattern's maps instead of its own
## (apply()). Pictures (a rose window, neon letters, the water round a dome) are plain colour textures for the light
## system's lamp material. Static; preload to use.
##
##   PATTERNS                    pressed_tin, ice_blocks, swirl_carpet, corrugated, plasterboard, roof_tiles, ashlar,
##                               lime_wash, quarry_tiles, deco_carpet (rising suns in rows: the Streamline's aisles),
##                               hex_pavers (sintered regolith: the Crater's floor), board_concrete (concrete cast in
##                               timber formwork: the Palace of Culture 1974's walls), tufted (buttoned upholstery:
##                               the Pink Palace's balcony front), shell_carpet (scallop shells in rows: its aisles)
##   maps(pattern) -> {albedo, normal, orm, mean}   the pattern's textures (mean: its albedo's mean, linear)
##   apply(material, pattern, colour)   a house material shows the pattern in this colour (on average)
##   glass(colour, alpha, room) -> ShaderMaterial   see-through glass that dims with the house lights
##   rose_window(), letters(text, colour, back), gradient(top, bottom), abstract(seed, palette), colour_field(aspect),
##   flame()   pictures

const PATTERNS: Array[String] = ["pressed_tin", "ice_blocks", "swirl_carpet", "corrugated", "plasterboard",
		"roof_tiles", "ashlar", "lime_wash", "quarry_tiles", "deco_carpet", "hex_pavers", "board_concrete",
		"tufted", "shell_carpet"]
const SIZE := 128
## Patterns drawn larger than SIZE (many tiles a repeat, each its own: since 2026-11-08, the Athens rooftop's floor).
const SIZES := {"quarry_tiles": 256, "deco_carpet": 256, "hex_pavers": 256, "board_concrete": 256,
		"shell_carpet": 256}
const GLASS_SHADER := preload("res://scripts/env/systems/kit/env_glass.gdshader")
const ProcCache := preload("res://scripts/env/proc_cache.gd")

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
		# The atmospheric courtyard's (since 2026-11-08): kit/courtyard.gd.
		"roof_tiles":
			# Barrel tiles: four rounded columns a repeat (u across the slope), two courses down it (v), each
			# course's lower lip lapping the next; each tile its own fired shade, the grooves darker, a little lichen.
			var col := int(floor(u * 4.0))
			var cu := fposmod(u * 4.0, 1.0)
			var course := int(floor(v * 2.0))
			var cv := fposmod(v * 2.0, 1.0)
			var round_ := sqrt(maxf(1.0 - pow(cu * 2.0 - 1.0, 2.0), 0.0))
			# Each course rises from its top (under the lap) to its lip.
			var h := round_ * (0.55 + 0.45 * cv) - 0.25 * (1.0 - smoothstep(0.0, 0.08, cv))
			var shade := _hash(col, course, 41)
			var c := Color(0.62, 0.3, 0.18).lerp(Color(0.78, 0.46, 0.28), shade).lerp(Color(0.45, 0.22, 0.14),
					0.25 * _hash(col, course, 43))
			c = c.lerp(Color(0.2, 0.12, 0.09), (1.0 - round_) * 0.7 + (1.0 - smoothstep(0.0, 0.1, cv)) * 0.4)
			c = c.lerp(Color(0.52, 0.5, 0.36), smoothstep(0.72, 0.9, _noise(u, v, 8, 17)) * 0.35)
			return [clampf(h, 0.0, 1.0), c, lerpf(0.9, 0.7, round_)]
		"ashlar":
			# Dressed stone in courses: two a repeat, each block its own length and shade, the joints recessed,
			# the faces a little worked.
			var row := int(floor(v * 2.0))
			var rv := fposmod(v * 2.0, 1.0)
			var shift := 0.5 * float(row % 2) + 0.17 * _hash(row, 0, 5)
			var bu := u * 2.0 + shift
			var block := posmod(int(floor(bu)), 2)
			var fu := fposmod(bu, 1.0)
			var edge := minf(minf(fu, 1.0 - fu) * 1.0, minf(rv, 1.0 - rv) * 0.5)
			var h := smoothstep(0.0, 0.03, edge) * (0.92 + 0.08 * _noise(u, v, 32, 21))
			var tone := _hash(block, row, 23)
			var c := Color(0.8, 0.74, 0.62).lerp(Color(0.9, 0.85, 0.74), tone)
			c = c.lerp(Color(0.6, 0.55, 0.47), 0.25 * _noise(u, v, 16, 29))
			c = c.lerp(Color(0.42, 0.38, 0.33), 1.0 - smoothstep(0.0, 0.025, edge))
			return [h, c, 0.85]
		"lime_wash":
			# Lime wash over old plaster: soft blotches of thicker and thinner wash, faint streaks run down by
			# rain, a few patches where it has flaked to the plaster under it.
			var blot := _noise(u, v, 4, 31) * 0.6 + _noise(u, v, 8, 37) * 0.4
			var streak := _noise(u, 0.37, 16, 41)
			var flake := smoothstep(0.84, 0.9, _noise(u, v, 8, 47))
			var s := 0.94 + 0.06 * blot - 0.03 * streak
			var c := Color(s, s * 0.985, s * 0.96).lerp(Color(0.84, 0.78, 0.7), flake * 0.5)
			var h := 0.6 + 0.12 * blot - 0.2 * flake + 0.05 * _noise(u, v, 64, 53)
			return [h, c, 0.9]
		# The Athens rooftop's (since 2026-11-08): kit/athens_roof.gd.
		"quarry_tiles":
			# Square terracotta tiles, eight by eight a repeat, in grey grout: each tile fired its own shade (a few
			# paler, a few darker, now and then one a replacement of another clay), its face a little dished and worn
			# at the edges, a fleck or a chip; salt bloom in faint patches.
			var tx := int(floor(u * 8.0))
			var ty := int(floor(v * 8.0))
			var fx := fposmod(u * 8.0, 1.0)
			var fy := fposmod(v * 8.0, 1.0)
			var edge := minf(minf(fx, 1.0 - fx), minf(fy, 1.0 - fy))
			var grout := 1.0 - smoothstep(0.022, 0.04, edge)
			var shade := _hash(tx, ty, 61)
			var odd := _hash(tx, ty, 67)
			var c := Color(0.66, 0.36, 0.24).lerp(Color(0.76, 0.48, 0.32), shade)
			if odd > 0.93:
				c = Color(0.6, 0.42, 0.32)
			elif odd < 0.06:
				c = Color(0.56, 0.28, 0.2)
			var wear := _noise(u, v, 32, 71)
			c = c.lerp(c * 1.12, smoothstep(0.55, 0.85, wear) * 0.6)
			c = c.lerp(Color(0.8, 0.72, 0.64), smoothstep(0.78, 0.95, _noise(u, v, 8, 73)) * 0.25)
			c = c.lerp(Color(0.32, 0.2, 0.15), smoothstep(0.86, 0.95, _noise(u, v, 64, 79)) * 0.5)
			var dish := 0.92 - 0.06 * pow(1.0 - minf(edge * 4.0, 1.0), 2.0) + 0.04 * wear
			var chip := smoothstep(0.9, 0.97, _hash(tx * 7 + int(fx * 6.0), ty * 7 + int(fy * 6.0), 83)) \
					* (1.0 - smoothstep(0.04, 0.1, edge))
			c = c.lerp(Color(0.5, 0.4, 0.34), chip * 0.6)
			c = c.lerp(Color(0.4, 0.38, 0.36), grout)
			var h := lerpf(dish - chip * 0.25, 0.25, grout)
			return [h, c, lerpf(0.72, 0.95, grout)]
		# Since 2026-11-08, the Streamline 1937's aisles: a moderne carpet.
		"deco_carpet":
			# Rising suns in rows, each row half a sun along from the last: on a jade ground, a sun's half disc of
			# cream, three gold arcs round it and dark rays between, a fine gold line under each row. Woven: a fleck.
			var row := int(floor(v * 2.0))
			var cu := fposmod(u * 2.0 + 0.5 * float(row % 2), 1.0)
			var cv := fposmod(v * 2.0, 1.0)
			var p := Vector2(cu - 0.5, 1.0 - cv - 0.12)
			var r := p.length()
			var ang := atan2(p.x, p.y)
			var c := Color(0.1, 0.3, 0.25)
			var gold := Color(0.78, 0.58, 0.24)
			var h := 0.5
			if p.y > 0.0:
				var rays := smoothstep(0.55, 0.75, cos(ang * 9.0)) * smoothstep(0.16, 0.17, r) \
						* (1.0 - smoothstep(0.38, 0.4, r))
				c = c.lerp(Color(0.05, 0.16, 0.13), rays * 0.85)
				for arc: float in [0.2, 0.28, 0.36]:
					var on := 1.0 - smoothstep(0.012, 0.022, absf(r - arc))
					c = c.lerp(gold, on)
					h += 0.15 * on
				var sun := 1.0 - smoothstep(0.13, 0.145, r)
				c = c.lerp(Color(0.86, 0.78, 0.6), sun)
			var line := 1.0 - smoothstep(0.008, 0.016, absf(cv - 0.88))
			c = c.lerp(gold, line * 0.8)
			var fleck := _noise(u, v, 64, 21)
			c = c * (0.92 + 0.16 * fleck)
			return [h + 0.1 * fleck, c, 0.95]
		# Since 2026-11-08, the Crater's floor: pavers of sintered regolith.
		"hex_pavers":
			# Hexagonal pavers, seven across and eight rows down a repeat (each row half a paver along from the last,
			# so they are near enough regular), in narrow dark joints: each fused its own shade of grey-brown, its face
			# a little domed and its edges softened, pitted here and there, a few glassy flecks.
			var best := 9.0
			var second := 9.0
			var cell := Vector2i.ZERO
			var fy := v * 8.0
			var row0 := int(floor(fy))
			for j in range(row0 - 1, row0 + 2):
				var off := 0.5 * float(posmod(j, 2))
				var col0 := int(floor(u * 7.0 - off))
				for i in range(col0 - 1, col0 + 2):
					var d := Vector2(u * 7.0 - (i + 0.5 + off), (fy - (j + 0.5)) * 0.866).length()
					if d < best:
						second = best
						best = d
						cell = Vector2i(posmod(i, 7), posmod(j, 8))
					elif d < second:
						second = d
			var edge := (second - best) * 0.5
			var joint := 1.0 - smoothstep(0.025, 0.05, edge)
			var shade := _hash(cell.x, cell.y, 91)
			var c := Color(0.36, 0.34, 0.31).lerp(Color(0.46, 0.43, 0.39), shade)
			if _hash(cell.x, cell.y, 97) > 0.9:
				c = c * 0.85
			var pits := smoothstep(0.82, 0.9, _noise(u, v, 64, 101))
			c = c.lerp(c * 0.7, pits * 0.6)
			c = c * (0.94 + 0.12 * _noise(u, v, 32, 103))
			var glint := smoothstep(0.93, 0.97, _noise(u, v, 128, 107))
			c = c.lerp(Color(0.6, 0.6, 0.62), glint * 0.5)
			c = c.lerp(Color(0.12, 0.115, 0.11), joint)
			var h := lerpf(0.88 - 0.25 * pow(1.0 - minf(edge * 6.0, 1.0), 2.0) - pits * 0.1, 0.2, joint)
			return [h, c, lerpf(lerpf(0.75, 0.45, glint), 0.95, joint)]
		# Since 2026-11-08, the Palace of Culture 1974's walls: "board-marked concrete you can read (the timber grain
		# imprinted, tie holes in a grid, panel seams)", the brief.
		"board_concrete":
			# Concrete cast against boards: ten boards down a repeat, each its own depth and tone (each drank the
			# water differently), the grain of its timber printed in streaks along it, a butt joint along most, a
			# fine fin where the cement seeped between boards; the form panel's seam at the repeat's edge; tie holes
			# in a grid (two rows of three: plugged with darker mortar, a little sunk); blowholes here and there.
			var boards := 10.0
			var bi := int(floor(v * boards))
			var bv := fposmod(v * boards, 1.0)
			var tone := _hash(bi, 3, 211)
			var depth := (_hash(bi, 5, 213) - 0.5) * 0.1
			# A butt joint along the board where its timber ended (some boards have none in a repeat).
			var butt := _hash(bi, 7, 217)
			var to_butt := absf(u - butt) if _hash(bi, 9, 219) > 0.3 else 1.0
			var seg := 1 if u > butt else 0
			tone = lerpf(tone, _hash(bi, 11 + seg, 223), 0.6)
			var grain := _noise2(u, v, 5, 160, 227 + seg) * 0.6 + _noise2(u, v, 13, 320, 229) * 0.4
			var rings := smoothstep(0.55, 0.85, _noise2(u + bv * 0.05, v, 3, 80, 233 + bi))
			var h := 0.5 + depth + 0.05 * (grain - 0.5) - 0.05 * rings
			var c := Color(0.6, 0.58, 0.54).lerp(Color(0.5, 0.49, 0.47), tone)
			c = c * (0.95 + 0.1 * grain) * (1.0 - 0.06 * rings)
			# The fin between boards and its shadow line.
			var joint := 1.0 - smoothstep(0.0, 0.05, minf(bv, 1.0 - bv))
			h += 0.18 * joint
			c = c.lerp(c * 0.78, joint * 0.7)
			var bj := 1.0 - smoothstep(0.0, 0.004, to_butt)
			h -= 0.1 * bj
			c = c.lerp(c * 0.8, bj * 0.6)
			# The form panel's seam at the repeat's edge: a sharp step and a dark line.
			var seam := 1.0 - smoothstep(0.0, 0.006, minf(u, 1.0 - u))
			h -= 0.15 * seam
			c = c.lerp(Color(0.32, 0.31, 0.3), seam * 0.8)
			# Tie holes: plugged with a darker mortar disc, sunk a little, a ring where the cone sat.
			# (Their distance in repeats: the holes about 3 cm across at a 1.5 m repeat.)
			var tr := Vector2((fposmod(u * 3.0, 1.0) - 0.5) / 3.0, (fposmod(v * 2.0, 1.0) - 0.5) / 2.0).length()
			var plug := 1.0 - smoothstep(0.008, 0.011, tr)
			var ring := (1.0 - smoothstep(0.012, 0.017, tr)) * (1.0 - plug)
			h -= 0.35 * plug + 0.15 * ring
			c = c.lerp(Color(0.38, 0.37, 0.36), plug)
			c = c.lerp(c * 0.72, ring)
			# Blowholes: small air bubbles left in the face.
			var blow := smoothstep(0.9, 0.93, _noise(u, v, 128, 239)) * smoothstep(0.55, 0.75, _noise(u, v, 16, 241))
			h -= 0.3 * blow
			c = c.lerp(c * 0.55, blow)
			return [h, c, lerpf(0.82, 0.95, minf(joint + plug, 1.0))]
		# Since 2026-11-08, the Pink Palace's balcony front: buttoned upholstery.
		"tufted":
			# A button at each corner and in the middle of a repeat; the velvet puffed up between them in diamonds,
			# drawn in along the creases that run from button to button, dimpled round each button; a faint pile.
			var d1 := absf(u - v)
			d1 = minf(d1, 1.0 - d1)
			var d2 := absf(u + v - 1.0)
			d2 = minf(d2, 1.0 - d2)
			var crease := minf(d1, d2) * 0.7071
			var puff := smoothstep(0.0, 0.2, crease)
			var bc := minf(Vector2(minf(u, 1.0 - u), minf(v, 1.0 - v)).length(), Vector2(u - 0.5, v - 0.5).length())
			var dimple := 1.0 - smoothstep(0.0, 0.17, bc)
			var button := 1.0 - smoothstep(0.03, 0.045, bc)
			var pile := _noise(u, v, 32, 301)
			var h := 0.2 + 0.6 * pow(puff, 0.7) - 0.2 * dimple + 0.3 * button + 0.03 * (pile - 0.5)
			var shade := 0.8 + 0.2 * puff + 0.04 * (pile - 0.5)
			var c := Color(shade, shade, shade)
			c = c.lerp(Color(0.55, 0.55, 0.55), 0.6 * (1.0 - smoothstep(0.0, 0.035, crease)))
			c = c.lerp(Color(0.62, 0.62, 0.62), button)
			return [h, c, 0.9]
		# Since 2026-11-08, the Pink Palace's aisles: scallop shells in rows.
		"shell_carpet":
			# Two rows a repeat, each half a shell along from the last: on a deep rose ground, a rose shell (a fan of
			# eleven ribs with a scalloped rim, its hinge at the foot) outlined in powder blue, a cream pearl between
			# the shells; woven: a fleck.
			var row := int(floor(v * 2.0))
			var cu := fposmod(u * 2.0 + 0.5 * float(row % 2), 1.0)
			var cv := fposmod(v * 2.0, 1.0)
			var p := Vector2(cu - 0.5, 0.8 - cv)
			var r := p.length()
			var ang := atan2(p.x, p.y)
			var ground := Color(0.34, 0.1, 0.17)
			var shell := Color(0.8, 0.4, 0.5)
			var blue := Color(0.56, 0.68, 0.88)
			var c := ground
			var h := 0.45
			if p.y > -0.03 and absf(ang) < 1.5:
				var rib := 0.5 + 0.5 * cos(ang * 7.0)
				var rim := 0.34 + 0.035 * rib
				var inside := 1.0 - smoothstep(rim - 0.012, rim, r)
				c = ground.lerp(shell * (0.82 + 0.25 * rib), inside)
				var line := 1.0 - smoothstep(0.01, 0.022, absf(r - rim - 0.014))
				c = c.lerp(blue, line * (1.0 - inside * 0.8))
				h += 0.12 * inside * rib + 0.1 * line
			var hinge := 1.0 - smoothstep(0.045, 0.06, Vector2(p.x, p.y + 0.02).length())
			c = c.lerp(blue, hinge)
			var pearl := 1.0 - smoothstep(0.03, 0.042, Vector2(minf(cu, 1.0 - cu), minf(cv, 1.0 - cv) - 0.12).length())
			c = c.lerp(Color(0.92, 0.86, 0.76), pearl)
			h += 0.15 * pearl
			var fleck := _noise(u, v, 64, 307)
			c = c * (0.9 + 0.18 * fleck)
			return [h + 0.08 * fleck, c, 0.95]
	return [0.5, Color(0.5, 0.5, 0.5), 0.8]


## Smooth value noise with its own number of cells across (pu) and down (pv), wrapping (grain stretched along u).
static func _noise2(u: float, v: float, pu: int, pv: int, seed_value: int) -> float:
	var x := u * pu
	var y := v * pv
	var xi := int(floor(x))
	var yi := int(floor(y))
	var fx := x - xi
	var fy := y - yi
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var a := _hash(posmod(xi, pu), posmod(yi, pv), seed_value)
	var b := _hash(posmod(xi + 1, pu), posmod(yi, pv), seed_value)
	var c := _hash(posmod(xi, pu), posmod(yi + 1, pv), seed_value)
	var d := _hash(posmod(xi + 1, pu), posmod(yi + 1, pv), seed_value)
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)


## The pattern's maps, made once (SIZE square, or the pattern's own in SIZES; mipmapped).
static func maps(pattern: String) -> Dictionary:
	if _maps.has(pattern):
		return _maps[pattern]
	var drawn := ProcCache.images("procedural.gd:_maps:" + pattern, func() -> Array: return _draw_maps(pattern))
	var out := {"albedo": ImageTexture.create_from_image(drawn[0]), "normal": ImageTexture.create_from_image(drawn[1]),
			"orm": ImageTexture.create_from_image(drawn[2]), "mean": drawn[3].get_pixel(0, 0)}
	_maps[pattern] = out
	return out


## The pattern's albedo, normal and packed maps (mipmapped), and the albedo's mean as one pixel.
static func _draw_maps(pattern: String) -> Array:
	var size: int = SIZES.get(pattern, SIZE)
	var heights := PackedFloat32Array()
	heights.resize(size * size)
	var albedo := Image.create_empty(size, size, false, Image.FORMAT_RGB8)
	var normal := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var orm := Image.create_empty(size, size, false, Image.FORMAT_RGB8)
	var rough := PackedFloat32Array()
	rough.resize(size * size)
	var mean := Color(0, 0, 0)
	for y in size:
		for x in size:
			var s := _sample(pattern, (x + 0.5) / size, (y + 0.5) / size)
			heights[y * size + x] = float(s[0])
			rough[y * size + x] = float(s[2])
			var c: Color = s[1]
			albedo.set_pixel(x, y, c)
			var lin := c.srgb_to_linear()
			mean += Color(lin.r, lin.g, lin.b) / float(size * size)
	# Relief: the height's slope over a texel, a few millimetres deep.
	var depth := 3.0
	for y in size:
		for x in size:
			var hx := heights[y * size + (x + 1) % size] - heights[y * size + (x - 1 + size) % size]
			var hy := heights[((y + 1) % size) * size + x] - heights[((y - 1 + size) % size) * size + x]
			var n := Vector3(-hx * depth, hy * depth, 1.0).normalized()
			normal.set_pixel(x, y, Color(0.5, n.x * 0.5 + 0.5, 0.5, n.y * 0.5 + 0.5))
			var h := heights[y * size + x]
			orm.set_pixel(x, y, Color(clampf(0.65 + 0.35 * h, 0.0, 1.0), rough[y * size + x],
					0.35 if pattern in ["pressed_tin", "corrugated"] else 0.0))
	for img: Image in [albedo, normal, orm]:
		img.generate_mipmaps()
	# The mean is a number, not a picture: kept beside the maps as one float pixel, which reads back exactly.
	var mean_px := Image.create_empty(1, 1, false, Image.FORMAT_RGBAF)
	mean_px.set_pixel(0, 0, mean)
	return [albedo, normal, orm, mean_px]


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
	var t := ImageTexture.create_from_image(ProcCache.image("procedural.gd:_pictures:rose", _draw_rose_window))
	_pictures["rose"] = t
	return t


static func _draw_rose_window() -> Image:
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
	return img


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
	var t := ImageTexture.create_from_image(ProcCache.image("procedural.gd:_pictures:" + key,
			func() -> Image: return _draw_letters(text, colour, back)))
	_pictures[key] = t
	return t


static func _draw_letters(text: String, colour: Color, back: Color) -> Image:
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
	return img


## A vertical gradient (UV.y 0 at the top), for the water round a glass dome.
static func gradient(top: Color, bottom: Color) -> Texture2D:
	var key := "gradient %s %s" % [top, bottom]
	if _pictures.has(key):
		return _pictures[key]
	var t := ImageTexture.create_from_image(ProcCache.image("procedural.gd:_pictures:" + key,
			func() -> Image: return _draw_gradient(top, bottom)))
	_pictures[key] = t
	return t


static func _draw_gradient(top: Color, bottom: Color) -> Image:
	var img := Image.create_empty(4, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		var f := float(y) / 63.0
		for x in 4:
			img.set_pixel(x, y, top.lerp(bottom, pow(f, 0.7)))
	return img


## Caustics' map (the light system's `caustics`, the sea floor's, env_water.gdshaderinc): a seamless cellular pattern,
## the distance to the second-nearest cell less the nearest's (near 0 on the walls between cells; the shaders turn
## the walls into the bright web that light focused by waves lays on a floor), 256 x 256 (64 KB with its mipmaps),
## made once by the engine's noise.
static func caustic_map() -> Texture2D:
	if _pictures.has("caustics"):
		return _pictures["caustics"]
	var t := ImageTexture.create_from_image(ProcCache.image("procedural.gd:_pictures:caustics", _draw_caustic_map))
	_pictures["caustics"] = t
	return t


static func _draw_caustic_map() -> Image:
	var noise := FastNoiseLite.new()
	noise.seed = 1934
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.frequency = 0.03
	noise.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	noise.cellular_jitter = 1.0
	var img := noise.get_seamless_image(256, 256, false, false, 0.15, true)
	img.convert(Image.FORMAT_L8)
	img.generate_mipmaps()
	return img


## An abstract painting of our own: soft blocks of colour on a ground, a few bands across (a mid-century canvas or
## a bedroom poster). seed_value picks the layout; palette: [ground, colours...].
static func abstract(seed_value: int, palette: Array) -> Texture2D:
	var key := "abstract %d %s" % [seed_value, palette]
	if _pictures.has(key):
		return _pictures[key]
	var t := ImageTexture.create_from_image(ProcCache.image("procedural.gd:_pictures:" + key,
			func() -> Image: return _draw_abstract(seed_value, palette)))
	_pictures[key] = t
	return t


static func _draw_abstract(seed_value: int, palette: Array) -> Image:
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
	return img


## A canvas of our own for a 1962 collector (since 2026-11-08, the Screening room 1962's painting): a hard-edged
## composition on a warm ground: a deep teal field, a vermilion sun over its edge, an ochre bar, a black line and a
## small black square; each colour laid on by hand (its edge wavers a little, the paint's strokes show in it), the
## canvas's weave under all. aspect: the picture's width over its height.
static func colour_field(aspect: float) -> Texture2D:
	var key := "colour_field %.3f" % aspect
	if _pictures.has(key):
		return _pictures[key]
	# Drawn from the aspect as the key has it (to 0.001), so the key is all the picture depends on: two callers
	# a hair apart get one picture, the same in every run, whichever asked first.
	var t := ImageTexture.create_from_image(ProcCache.image("procedural.gd:_pictures:" + key,
			func() -> Image: return _draw_colour_field(snappedf(aspect, 0.001))))
	_pictures[key] = t
	return t


static func _draw_colour_field(aspect: float) -> Image:
	var w := 512
	var h := maxi(64, roundi(w / maxf(aspect, 0.2)))
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGB8)
	var ground := Color(0.86, 0.79, 0.64)
	var teal := Color(0.06, 0.29, 0.31)
	var vermilion := Color(0.86, 0.27, 0.1)
	var ochre := Color(0.87, 0.6, 0.16)
	var black := Color(0.07, 0.065, 0.06)
	for y in h:
		for x in w:
			var u := (x + 0.5) / w
			var v := (y + 0.5) / h
			# The edges waver: each shape's boundary pushed by a slow noise.
			var wob := (_noise(u, v, 9, 11) - 0.5) * 0.006
			var strokes := _noise(u * 6.0, v * 0.7, 48, 5) * 0.06 - 0.03
			var c := ground * (0.95 + 0.06 * _noise(u, v, 12, 3)) + Color(strokes, strokes, strokes) * 0.4
			# The teal field.
			var dt := maxf(maxf(0.07 - u, u - 0.47), maxf(0.09 - v, v - 0.91)) + wob
			c = c.lerp(teal * (0.92 + 0.12 * _noise(u * 3.0, v, 20, 7)) + Color(strokes, strokes, strokes) * 0.3,
					1.0 - smoothstep(-0.002, 0.002, dt))
			# The ochre bar, under the sun.
			var db := maxf(maxf(0.5 - u, u - 0.93), maxf(0.7 - v, v - 0.82)) + wob
			c = c.lerp(ochre * (0.94 + 0.1 * _noise(u * 4.0, v, 24, 9)), 1.0 - smoothstep(-0.002, 0.002, db))
			# The sun: round on the canvas (its width in u is its height over the aspect).
			var ds := Vector2((u - 0.555) * aspect, v - 0.4).length() - 0.27 + wob
			c = c.lerp(vermilion * (0.93 + 0.12 * _noise(u * 2.0, v * 2.0, 16, 13)) + Color(strokes, strokes, strokes)
					* 0.3, 1.0 - smoothstep(-0.002, 0.002, ds))
			# The black line and the small square.
			var dl := maxf(maxf(0.8 - u, u - 0.812), maxf(0.1 - v, v - 0.6)) + wob * 0.5
			var dq := maxf(maxf(0.86 - u, u - 0.915), maxf(0.13 - v, v - 0.23)) + wob
			c = c.lerp(black, 1.0 - smoothstep(-0.0015, 0.0015, minf(dl, dq)))
			# The canvas's weave.
			var weave := 0.97 + 0.03 * sin(x * 2.2) * sin(y * 2.2)
			img.set_pixel(x, y, c * weave)
	img.generate_mipmaps()
	return img


## A flame from the side (UV.y 0 at the top): bright yellow at its root, orange, fading to nothing at the tip and the
## sides. Drawn additively by nothing: a lamp picture, black where there is no flame.
static func flame() -> Texture2D:
	if _pictures.has("flame"):
		return _pictures["flame"]
	var t := ImageTexture.create_from_image(ProcCache.image("procedural.gd:_pictures:flame", _draw_flame))
	_pictures["flame"] = t
	return t


static func _draw_flame() -> Image:
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
	return img
