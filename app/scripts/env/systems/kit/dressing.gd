extends RefCounted

## The kit's room dressing for the TV-era rooms (docs/environments.md, "The kit"): small things of a front room, a
## lounge and a living room, a boat's stove, a showboat's stage and proscenium, drawn into the kit's shared meshes in
## its own frame (xf places it: the middle of its foot at local y 0, its front facing local +Z). Low-poly, plain
## shapes of our own: no maker's shape, no badge, no lettering, no crown, flag or arms. pieces.gd calls build(); ctx
## is kit.gd's Ctx.
##
##   bunting       a string of triangular pennants across a room, sagging: size.x the span, size.y the sag; the
##                 pennants red, white and blue in turn (`colour`, white, `accent`). It hangs from local y 0
##   tea_set       a tray with a teapot (`colour`: its glaze), a milk jug, a sugar bowl, four cups on saucers
##   sandwiches    a plate with a pile of triangular sandwiches (`colour`: the filling)
##   stool         a round wooden seat on four splayed legs (`wood`)
##   channel_dial  a rotary channel dial (twelve stops), two small knobs under it, on a set's front: it hangs on a face
##   soundbar      a long low bar: a dark case (`iron`), a cloth front (`fabric` in `accent`, or a dark grey)
##   floor_lamp    a flat round base, a slim pole, a tall column shade that glows (house group)
##   glass_table   a low table: a glass top (the kit's glass, see-through), a steel frame (`tin`)
##   media_unit    a long low cabinet on a recessed plinth, three handleless doors (`wood`)
##   boat_stove    a small solid-fuel stove on a hearth plate, its flue straight up to the roof (`iron`); its door's
##                 window glows (the kit's lit windows)
##   show_stage    a low wooden stage with a front moulding and seven iron footlight hoods; the lamps behind them
##                 glow with the house lights: bright before the film, all but out during it
##   show_proscenium  gilt pilasters and drawn-back drapes either side of a hall's picture
##   liner_proscenium  an Art Deco stepped walnut, brass and cove-lit screen surround, low dais and two torchières
##   liner_drape   a deeply pleated floor-length velvet curtain panel (unbaked, for motion sway)
##   liner_pelmet  a walnut-and-brass Art Deco curtain pelmet cornice box hiding swaying drape tops
##   liner_clock   an Art Deco sunburst bulkhead clock with brass speed wings (working dial in PieceClock)
##   deck_rail     a ship's teak-and-brass promenade deck railing (unbaked, outside the windows)
##
## The china (`china`) and the cloth (`cloth`: bunting, bread and filling) are one material each, coloured per vertex
## (the house shader's instance tint): bunting, a tea set and three plates of sandwiches cost two draws.

const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const Shapes := preload("res://scripts/env/systems/kit/shapes.gd")
const PhysicsShapes := preload("res://scripts/play/physics_shapes.gd")

## Its pieces (pieces.gd lists them with the others, their sizes and which stand on a floor).
const PIECES: Array[String] = ["bunting", "tea_set", "sandwiches", "stool", "channel_dial", "soundbar", "floor_lamp",
		"glass_table", "media_unit", "boat_stove", "show_stage", "show_proscenium", "liner_proscenium",
		"liner_drape", "liner_pelmet", "liner_clock", "deck_rail"]
## The bunting's colours when the entry gives none: a red, a white, a blue (cloth, faded a little).
const RED := Color(0.62, 0.07, 0.09)
const WHITE := Color(0.86, 0.84, 0.8)
const BLUE := Color(0.1, 0.15, 0.42)
## A pennant: its width at the string, its drop, and the string's length between two pennants' middles.
const PENNANT := Vector2(0.17, 0.21)
const PENNANT_STEP := 0.26
## The boat stove: the size it is drawn at (pieces.gd SIZES has the same), its body's and its hearth plate's colours.
const STOVE_SIZE := Vector3(0.4, 2.0, 0.38)
const STOVE_BODY := Color(0.05, 0.05, 0.055)
const STOVE_PLATE := Color(0.16, 0.15, 0.14)
## The show stage: its own size, the platform's wood colour and the footlight hoods' iron colour.
const STAGE_SIZE := Vector3(7.2, 0.6, 1.2)
const STAGE_WOOD := Color(0.2, 0.13, 0.08)
const STAGE_IRON := Color(0.05, 0.05, 0.055)
## The show proscenium: its own size, its gilt pilasters and its drapes' colours.
const SHOW_SIZE := Vector3(5.6, 3.0, 0.3)
const SHOW_GILT := Color(0.95, 0.68, 0.25)
const SHOW_DRAPE := Color(0.4, 0.05, 0.06)
## The ocean liner lounge's pieces: their natural sizes and default colours.
const LINER_PROS_SIZE := Vector3(7.6, 3.8, 0.9)
const LINER_DRAPE_SIZE := Vector3(0.52, 2.72, 0.14)
const DECK_RAIL_SIZE := Vector3(12.0, 1.02, 0.12)
const LINER_WALNUT := Color(0.24, 0.14, 0.08)
const LINER_CREAM := Color(0.86, 0.8, 0.68)
const LINER_GILT := Color(0.9, 0.7, 0.34)
const LINER_DRAPE := Color(0.44, 0.12, 0.15)
const LINER_TORCH := Color(1.0, 0.85, 0.6)


static func build(piece: String, c: Object, xf: Transform3D, size: Vector3, e: Dictionary) -> void:
	match piece:
		"bunting":
			_bunting(c, xf, size, e)
		"tea_set":
			_tea_set(c, xf, size, e)
		"sandwiches":
			_sandwiches(c, xf, size, e)
		"stool":
			_stool(c, xf, size, e)
		"channel_dial":
			_channel_dial(c, xf, size, e)
		"soundbar":
			_soundbar(c, xf, size, e)
		"floor_lamp":
			_floor_lamp(c, xf, size, e)
		"glass_table":
			_glass_table(c, xf, size, e)
		"media_unit":
			_media_unit(c, xf, size, e)
		"boat_stove":
			_boat_stove(c, xf, size, e)
		"show_stage":
			_show_stage(c, xf, size, e)
		"show_proscenium":
			_show_proscenium(c, xf, size, e)
		"liner_proscenium":
			_liner_proscenium(c, xf, size, e)
		"liner_drape":
			_liner_drape(c, xf, size, e)
		"liner_pelmet":
			_liner_pelmet(c, xf, size, e)
		"liner_clock":
			_liner_clock(c, xf, size, e)
		"deck_rail":
			_deck_rail(c, xf, size, e)


# --- Helpers ---------------------------------------------------------------------------------------------------

## A material of the kit's coloured per vertex (white: the material's own colour), made once a key.
static func _tinted(c: Object, key: String) -> Material:
	var k := "tinted %s" % key
	if c._mats.has(k):
		return c._mats[k]
	var d: Dictionary = (c.kit.params[key] as Dictionary).duplicate()
	var m: ShaderMaterial = c.kit._light.from_param(d)
	m.set_shader_parameter("instance_tint", true)
	c._mats[k] = m
	return m


static func _box(b: RoomMesh, xf: Transform3D, centre: Vector3, size: Vector3, basis := Basis()) -> void:
	b.box(xf * centre, size * xf.basis.get_scale().x, xf.basis.orthonormalized() * basis)


static func _lathe(b: RoomMesh, xf: Transform3D, profile: Array, centre: Vector3, sides := 12) -> void:
	var k := xf.basis.get_scale().x
	var scaled: Array = []
	for p: Vector2 in profile:
		scaled.append(p * k)
	Shapes.lathe(b, scaled, xf * centre, sides, xf.basis.orthonormalized())


## A flat disc facing up at height y (a lid, a cup's tea, a plate's well).
static func _disc(b: RoomMesh, xf: Transform3D, centre: Vector3, r: float, sides := 12) -> void:
	var corners: Array = []
	for k in sides:
		var t := TAU * k / sides
		corners.append(xf * (centre + Vector3(sin(t) * r, 0.0, cos(t) * r)))
	b.face(corners, (xf.basis * Vector3.UP).normalized())


static func _solid(c: Object, xf: Transform3D, centre: Vector3, size: Vector3) -> void:
	var s := xf.basis.get_scale().x
	c.shapes.append(PhysicsShapes.box(xf * centre, size * s, xf.basis.orthonormalized()))


static func _colour(e: Dictionary, key: String, fallback: Color) -> Color:
	var v: Variant = e.get(key)
	if v == null or (v is Array and (v as Array).is_empty()):
		return fallback
	if v is Color:
		return v
	if v is String:
		return Color(str(v))
	return Color(float(v[0]), float(v[1]), float(v[2]))


# --- A front room's day ----------------------------------------------------------------------------------------

## Bunting: the string sags in a curve from end to end; a pennant hangs from it every PENNANT_STEP, both faces drawn.
static func _bunting(c: Object, xf: Transform3D, size: Vector3, e: Dictionary) -> void:
	var w := maxf(size.x, 0.5)
	var sag := size.y
	var colours: Array[Color] = [_colour(e, "colour", RED), WHITE, _colour(e, "accent", BLUE)]
	var at := func(x: float) -> Vector3:
		var t := x / (w * 0.5)
		return Vector3(x, -sag * (1.0 - t * t), 0.0)
	var b: RoomMesh = c.u
	b.surface(_tinted(c, "cloth"))
	# The string: short beams along the curve.
	b.colour = Color(0.8, 0.78, 0.72)
	var steps := 12
	for i in steps:
		var x0 := -w * 0.5 + w * i / steps
		var x1 := -w * 0.5 + w * (i + 1) / steps
		Shapes.beam(b, xf * at.call(x0), xf * at.call(x1), Vector2(0.006, 0.006))
	var n := int(floor(w / PENNANT_STEP))
	var x := -(n - 1) * PENNANT_STEP * 0.5
	var fwd := (xf.basis * Vector3.BACK).normalized()
	for i in n:
		b.colour = colours[i % colours.size()]
		var l: Vector3 = at.call(x - PENNANT.x * 0.5)
		var r: Vector3 = at.call(x + PENNANT.x * 0.5)
		var tip: Vector3 = at.call(x) + Vector3(0.0, -PENNANT.y, 0.012 * (1 if i % 2 == 0 else -1))
		b.face([xf * l, xf * r, xf * tip], fwd)
		b.face([xf * r, xf * l, xf * tip], -fwd)
		x += PENNANT_STEP
	b.colour = Color.WHITE


## A tea set on a tray: the teapot in the middle back, the milk jug and the sugar bowl beside it, four cups on their
## saucers along the front.
static func _tea_set(c: Object, xf: Transform3D, size: Vector3, e: Dictionary) -> void:
	var w := size.x
	var d := size.z
	c.s.surface(c.mat("wood"))
	_box(c.s, xf, Vector3(0, 0.008, 0), Vector3(w, 0.016, d))
	for s: float in [-1.0, 1.0]:
		_box(c.s, xf, Vector3(s * (w * 0.5 - 0.006), 0.024, 0), Vector3(0.012, 0.03, d))
		_box(c.s, xf, Vector3(0, 0.024, s * (d * 0.5 - 0.006)), Vector3(w, 0.03, 0.012))
	var b: RoomMesh = c.u
	b.surface(_tinted(c, "china"))
	var glaze := _colour(e, "colour", Color(0.36, 0.2, 0.12))
	var y0 := 0.016
	# The teapot: a round body, a lid and its knob, a spout and a handle.
	b.colour = glaze
	var tp := Vector3(-w * 0.12, y0, -d * 0.18)
	_lathe(b, xf, [Vector2(0.045, 0.0), Vector2(0.07, 0.03), Vector2(0.075, 0.06), Vector2(0.062, 0.1),
			Vector2(0.04, 0.115), Vector2(0.036, 0.12), Vector2(0.012, 0.13), Vector2(0.0, 0.135)], tp, 12)
	Shapes.beam(b, xf * (tp + Vector3(0.06, 0.04, 0)), xf * (tp + Vector3(0.115, 0.1, 0)), Vector2(0.018, 0.018) *
			xf.basis.get_scale().x)
	for seg: Array in [[Vector3(-0.07, 0.095, 0), Vector3(-0.105, 0.085, 0)], [Vector3(-0.105, 0.085, 0),
			Vector3(-0.11, 0.045, 0)], [Vector3(-0.11, 0.045, 0), Vector3(-0.072, 0.03, 0)]]:
		Shapes.beam(b, xf * (tp + seg[0]), xf * (tp + seg[1]), Vector2(0.012, 0.012) * xf.basis.get_scale().x)
	b.colour = Color.WHITE
	# The milk jug and the sugar bowl.
	_lathe(b, xf, [Vector2(0.025, 0.0), Vector2(0.032, 0.03), Vector2(0.026, 0.06), Vector2(0.03, 0.07)],
			Vector3(w * 0.1, y0, -d * 0.2), 10)
	_lathe(b, xf, [Vector2(0.025, 0.0), Vector2(0.04, 0.02), Vector2(0.043, 0.045)], Vector3(w * 0.3, y0, -d * 0.18),
			10)
	b.colour = Color(0.92, 0.9, 0.86)
	_disc(b, xf, Vector3(w * 0.3, y0 + 0.035, -d * 0.18), 0.038, 10)
	# Four cups on their saucers, a band of the glaze's colour on each cup.
	for k in 4:
		var p := Vector3(-w * 0.36 + k * w * 0.24, y0, d * 0.22)
		b.colour = Color.WHITE
		_lathe(b, xf, [Vector2(0.0, 0.0), Vector2(0.06, 0.004), Vector2(0.065, 0.012)], p, 12)
		_lathe(b, xf, [Vector2(0.022, 0.008), Vector2(0.04, 0.03), Vector2(0.044, 0.058)], p, 10)
		b.colour = glaze.lerp(Color.WHITE, 0.3)
		_lathe(b, xf, [Vector2(0.0415, 0.044), Vector2(0.0445, 0.052)], p, 10)
		b.colour = Color(0.45, 0.25, 0.12)
		_disc(b, xf, p + Vector3(0, 0.05, 0), 0.04, 10)
	b.colour = Color.WHITE
	_solid(c, xf, Vector3(0, 0.07, 0), Vector3(w, 0.14, d))


## A plate of paste sandwiches: triangles of white bread, the filling between, piled in two layers.
static func _sandwiches(c: Object, xf: Transform3D, size: Vector3, e: Dictionary) -> void:
	var r := size.x * 0.5
	var b: RoomMesh = c.u
	b.surface(_tinted(c, "china"))
	b.colour = Color.WHITE
	_lathe(b, xf, [Vector2(0.0, 0.0), Vector2(r * 0.6, 0.003), Vector2(r * 0.65, 0.008), Vector2(r, 0.018)],
			Vector3.ZERO, 16)
	b.surface(_tinted(c, "cloth"))
	var filling := _colour(e, "colour", Color(0.72, 0.42, 0.36))
	var bread := Color(0.92, 0.86, 0.72)
	var crust := Color(0.72, 0.56, 0.34)
	var side := r * 0.78
	var layers := [[0.009, 0.0, 6], [0.009 + 0.034, PI / 6.0, 3]]
	for layer: Array in layers:
		var y := float(layer[0])
		for k in int(layer[2]):
			var a := float(layer[1]) + TAU * k / int(layer[2])
			var dir := Vector3(sin(a), 0, cos(a))
			var across := Vector3(dir.z, 0, -dir.x)
			var reach := side * (0.55 if int(layer[2]) == 6 else 0.35)
			# A right triangle: its point at the plate's middle side, its crust outward.
			var p0 := dir * reach * 0.12
			var p1 := dir * reach + across * side * 0.3
			var p2 := dir * reach - across * side * 0.3
			var bands := [[0.0, 0.013, bread], [0.013, 0.021, filling], [0.021, 0.034, bread]]
			for band: Array in bands:
				_prism(b, xf, [p0, p1, p2], y + float(band[0]), y + float(band[1]), band[2], crust)
	b.colour = Color.WHITE
	_solid(c, xf, Vector3(0, 0.03, 0), Vector3(size.x, 0.06, size.x))


## A triangular slab from y0 to y1 over the triangle tri (local, y 0): its top, its three sides (the outer side, p1 to
## p2, in the crust's colour).
static func _prism(b: RoomMesh, xf: Transform3D, tri: Array, y0: float, y1: float, top: Color, crust: Color) -> void:
	var up := Vector3.UP
	b.colour = top
	b.face([xf * (tri[0] + up * y1), xf * (tri[2] + up * y1), xf * (tri[1] + up * y1)], (xf.basis * up).normalized())
	for i in 3:
		var a: Vector3 = tri[i]
		var c2: Vector3 = tri[(i + 1) % 3]
		var out := (c2 - a).cross(up).normalized()
		if out.dot(a - (tri[0] + tri[1] + tri[2]) / 3.0) < 0.0:
			out = -out
		b.colour = crust if i == 1 else top
		b.face([xf * (a + up * y0), xf * (c2 + up * y0), xf * (c2 + up * y1), xf * (a + up * y1)],
				(xf.basis * out).normalized())


## A stool: a round seat, four splayed legs, a rung between each pair.
static func _stool(c: Object, xf: Transform3D, size: Vector3, e: Dictionary) -> void:
	var r := size.x * 0.5
	var h := size.y
	var b: RoomMesh = c.s
	b.surface(c.mat("wood", e.get("colour")))
	_lathe(b, xf, [Vector2(0.0, h - 0.035), Vector2(r * 0.92, h - 0.035), Vector2(r, h - 0.02), Vector2(r * 0.95, h),
			Vector2(0.0, h)], Vector3.ZERO, 14)
	var foot := r * 1.05
	var top := r * 0.62
	for k in 4:
		var a := PI * 0.25 + PI * 0.5 * k
		var d := Vector3(sin(a), 0, cos(a))
		Shapes.beam(b, xf * (d * foot), xf * (d * top + Vector3.UP * (h - 0.035)), Vector2(0.03, 0.03) *
				xf.basis.get_scale().x)
	for k in 4:
		var a0 := PI * 0.25 + PI * 0.5 * k
		var a1 := a0 + PI * 0.5
		var y := h * 0.32
		var rr := lerpf(foot, top, y / (h - 0.035))
		Shapes.beam(b, xf * (Vector3(sin(a0), 0, cos(a0)) * rr + Vector3.UP * y), xf * (Vector3(sin(a1), 0, cos(a1)) * rr
				+ Vector3.UP * y), Vector2(0.018, 0.018) * xf.basis.get_scale().x)
	_solid(c, xf, Vector3(0, h * 0.5, 0), Vector3(r * 1.6, h, r * 1.6))


# --- A set's front and a lounge ---------------------------------------------------------------------------------

## A rotary channel dial: a round plate with twelve stops marked round it, a big knob with a pointer, and two small
## knobs (the volume, the brightness) under it in a column, so it fits a set's side strip beside the picture. It
## hangs on a face (local z 0 is the face; the knobs stand out to +z).
static func _channel_dial(c: Object, xf: Transform3D, size: Vector3, e: Dictionary) -> void:
	var r := size.x * 0.5
	var b: RoomMesh = c.s
	var knob := _colour(e, "colour", Color(0.12, 0.1, 0.08))
	var plate := _colour(e, "accent", Color(0.74, 0.66, 0.5))
	var turn := Basis(Vector3.RIGHT, PI * 0.5)
	b.surface(c.mat("plastic", plate))
	Shapes.cylinder(b, xf * Vector3(0, 0, 0.0), r * xf.basis.get_scale().x, 0.004 * xf.basis.get_scale().x, 16,
			xf.basis.orthonormalized() * turn)
	b.surface(c.mat("iron", knob))
	for k in 12:
		var a := TAU * k / 12.0
		_box(b, xf, Vector3(sin(a) * r * 0.82, cos(a) * r * 0.82, 0.005), Vector3(0.004, 0.009, 0.003),
				Basis(Vector3.BACK, -a))
	Shapes.cylinder(b, xf * Vector3(0, 0, 0.004), r * 0.6 * xf.basis.get_scale().x, size.z * xf.basis.get_scale().x,
			12, xf.basis.orthonormalized() * turn)
	_box(b, xf, Vector3(0, r * 0.3, 0.004 + size.z + 0.002), Vector3(0.006, r * 0.6, 0.004))
	for k in 2:
		Shapes.cylinder(b, xf * Vector3(0, -r * (1.9 + k * 1.3), 0.0), r * 0.42 * xf.basis.get_scale().x,
				size.z * 0.7 * xf.basis.get_scale().x, 10, xf.basis.orthonormalized() * turn)


## A soundbar: a long low case, its front a cloth grille a little inset, on two small feet.
static func _soundbar(c: Object, xf: Transform3D, size: Vector3, e: Dictionary) -> void:
	var w := size.x
	var h := size.y
	var d := size.z
	var b: RoomMesh = c.s
	b.surface(c.mat("iron", e.get("colour")))
	_box(b, xf, Vector3(0, 0.006 + h * 0.5, -0.006), Vector3(w, h, d - 0.012))
	for s: float in [-1.0, 1.0]:
		_box(b, xf, Vector3(s * w * 0.35, 0.003, 0), Vector3(0.05, 0.006, d * 0.6))
	b.surface(c.mat("fabric", _colour(e, "accent", Color(0.09, 0.09, 0.1))))
	_box(b, xf, Vector3(0, 0.006 + h * 0.5, d * 0.5 - 0.008), Vector3(w - 0.02, h - 0.012, 0.004))
	_solid(c, xf, Vector3(0, h * 0.5, 0), Vector3(w, h, d))


## A floor lamp: a flat round base, a slim pole, a tall column shade at the top that glows (house group: the ritual
## dims it) and gives a dim stand-in lamp.
static func _floor_lamp(c: Object, xf: Transform3D, size: Vector3, e: Dictionary) -> void:
	var h := size.y
	var r := clampf(size.x * 0.5, 0.08, 0.25)
	var k := xf.basis.get_scale().x
	var basis := xf.basis.orthonormalized()
	var b: RoomMesh = c.s
	var pole: Variant = e.get("accent")
	b.surface(c.mat("iron", pole))
	_lathe(b, xf, [Vector2(r * 0.9, 0.0), Vector2(r * 0.9, 0.012), Vector2(r * 0.8, 0.02), Vector2(0.015, 0.024)],
			Vector3.ZERO, 16)
	var shade_h := clampf(h * 0.3, 0.25, 0.6)
	Shapes.cylinder(b, xf * Vector3(0, 0.02, 0), 0.01 * k, (h - shade_h - 0.02) * k, 6, basis, false)
	var glow := _colour(e, "colour", c.colour_of("lamp_colour"))
	c.lit.surface(c.shade(glow))
	_lathe(c.lit, xf, [Vector2(r * 0.55, h - shade_h), Vector2(r * 0.6, h - shade_h * 0.5), Vector2(r * 0.55, h)],
			Vector3.ZERO, 16)
	c.lamps.append([xf * Vector3(0, h - shade_h * 0.5, 0), glow, 0.4])
	_solid(c, xf, Vector3(0, h * 0.5, 0), Vector3(r * 1.6, h, r * 1.6))


## A glass coffee table: a steel frame (four legs, the rails round the top, a rail low down each end) and a glass top
## laid in it (the kit's glass mesh, see-through).
static func _glass_table(c: Object, xf: Transform3D, size: Vector3, _e: Dictionary) -> void:
	var w := size.x
	var h := size.y
	var d := size.z
	var t := 0.022
	var b: RoomMesh = c.s
	b.surface(c.mat("tin"))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_box(b, xf, Vector3(sx * (w * 0.5 - t * 0.5), (h - 0.012) * 0.5, sz * (d * 0.5 - t * 0.5)),
					Vector3(t, h - 0.012, t))
		_box(b, xf, Vector3(sx * (w * 0.5 - t * 0.5), 0.06, 0), Vector3(t, t, d - t))
		_box(b, xf, Vector3(sx * (w * 0.5 - t * 0.5), h - 0.022, 0), Vector3(t, t, d - t))
	for sz: float in [-1.0, 1.0]:
		_box(b, xf, Vector3(0, h - 0.022, sz * (d * 0.5 - t * 0.5)), Vector3(w - t, t, t))
	# The glass mesh takes the glass shader as its override: the surface key is only a key.
	c.glass.surface(c.mat("tin"))
	_box(c.glass, xf, Vector3(0, h - 0.006, 0), Vector3(w + 0.02, 0.012, d + 0.02))
	_solid(c, xf, Vector3(0, h - 0.006, 0), Vector3(w, 0.012, d))
	_solid(c, xf, Vector3(0, h * 0.5, 0), Vector3(w, h - 0.03, d) * 0.9)


## A media unit: a long low cabinet on a plinth set back under it, three doors without handles (a gap between them).
static func _media_unit(c: Object, xf: Transform3D, size: Vector3, e: Dictionary) -> void:
	var w := size.x
	var h := size.y
	var d := size.z
	var plinth := minf(0.08, h * 0.25)
	var b: RoomMesh = c.s
	b.surface(c.mat("iron", Color(0.03, 0.03, 0.03)))
	_box(b, xf, Vector3(0, plinth * 0.5, -0.04), Vector3(w - 0.12, plinth, d - 0.1))
	b.surface(c.mat("wood", e.get("colour")))
	_box(b, xf, Vector3(0, plinth + (h - plinth) * 0.5, -0.01), Vector3(w, h - plinth, d - 0.02))
	var dw := (w - 0.02) / 3.0
	for k in 3:
		_box(b, xf, Vector3(-w * 0.5 + 0.01 + dw * (k + 0.5), plinth + (h - plinth) * 0.5, d * 0.5 - 0.01),
				Vector3(dw - 0.006, h - plinth - 0.02, 0.016))
	_solid(c, xf, Vector3(0, h * 0.5, 0), Vector3(w, h, d))


# --- A boat's saloon ---------------------------------------------------------------------------------------------

## A narrowboat's stove: a hearth plate on the floor, a squat body on four short legs, a top plate, a door with a
## small window that glows (the kit's lit windows: PieceWindows, in `window_colour`; it lights nothing), and a round
## flue straight up to the roof with a collar near its top. Plain painted metal (`iron`, tinted). Drawn at its own
## size ([0.4, 2.0, 0.38]); another size stretches it along each axis.
static func _boat_stove(c: Object, xf: Transform3D, size: Vector3, e: Dictionary) -> void:
	# Another size stretches each axis by its share: a taller cabin asks for a taller size and gets a longer flue.
	var k := size / STOVE_SIZE
	var body := _colour(e, "colour", STOVE_BODY)
	var b: RoomMesh = c.s
	b.surface(c.mat("iron", STOVE_PLATE))
	_box(b, xf, Vector3(0, 0.0075, 0.03) * k, Vector3(0.5, 0.015, 0.48) * k)
	# The legs, the top plate and the collar are the body's colour: one casting, blacked all over.
	b.surface(c.mat("iron", body))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_box(b, xf, Vector3(sx * 0.15, 0.055, sz * 0.12) * k, Vector3(0.03, 0.08, 0.03) * k)
	_box(b, xf, Vector3(0, 0.305, 0) * k, Vector3(0.36, 0.42, 0.32) * k)
	_box(b, xf, Vector3(0, 0.525, 0) * k, Vector3(0.4, 0.02, 0.36) * k)
	var flue := Vector3(0, 0.535, -0.08) * k
	var s := xf.basis.get_scale().x
	Shapes.cylinder(b, xf * flue, 0.05 * minf(k.x, k.z) * s, (2.0 - 0.535) * k.y * s, 8, xf.basis.orthonormalized(),
			false)
	# The collar is 0.16 under the flue's top, not at it: the flue's top is given as the highest the roof is, and a
	# roof that arches is lower where a stove stands by the wall (the Narrowboat's is 1.86 there). At 1.93, where it
	# was first drawn, the collar was inside that roof and never seen.
	_box(b, xf, Vector3(0, 1.84, -0.08) * k, Vector3(0.16, 0.02, 0.16) * k)
	b.surface(c.mat("iron", body * 1.3))
	_box(b, xf, Vector3(0, 0.33, 0.166) * k, Vector3(0.22, 0.2, 0.012) * k)
	# The door's window: a glow quad [centre, half across, half up, facing], 0.007 in front of the door.
	# The lit windows' glow ("window": steady, 0.9, in `window_colour`, which the room's kit sets to a fire's
	# colour), not the "display" glow: that one flashes once a second, a video recorder's clock, and a stove that
	# blinks is an alarm.
	var g: Array = c.glows.get("window", [])
	g.append([xf * (Vector3(0, 0.33, 0.179) * k), xf.basis.x * 0.07 * k.x, xf.basis.y * 0.05 * k.y,
			xf.basis.z.normalized()])
	c.glows["window"] = g
	_solid(c, xf, Vector3(0, 0.0075, 0.03) * k, Vector3(0.5, 0.015, 0.48) * k)
	_solid(c, xf, Vector3(0, 0.275, 0) * k, Vector3(0.4, 0.52, 0.36) * k)
	_solid(c, xf, Vector3(0, 1.2675, -0.08) * k, Vector3(0.1, 1.465, 0.1) * k)


## A low stage under a hall's picture: a wooden platform, a front moulding and seven iron footlight hoods.
## The lamps behind the hoods glow with the house lights: bright before the film, all but out during it.
## Another size stretches the stage along each axis.
static func _show_stage(c: Object, xf: Transform3D, size: Vector3, e: Dictionary) -> void:
	var k := size / STAGE_SIZE
	var wood := _colour(e, "colour", STAGE_WOOD)
	var b: RoomMesh = c.s
	b.surface(c.mat("wood", wood))
	_box(b, xf, Vector3(0, 0.225, 0) * k, Vector3(7.2, 0.45, 1.2) * k)
	b.surface(c.mat("wood", wood * 1.4))
	_box(b, xf, Vector3(0, 0.42, 0.615) * k, Vector3(7.2, 0.06, 0.03) * k)
	b.surface(c.mat("iron", STAGE_IRON))
	var lit: RoomMesh = c.lit
	lit.surface(c.shade(Color(1.0, 0.8, 0.5)))
	var normal := (xf.basis * Vector3.BACK).normalized()
	for i in 7:
		var x := -2.7 + 0.9 * i
		_box(b, xf, Vector3(x, 0.51, 0.5) * k, Vector3(0.18, 0.12, 0.14) * k)
		lit.face([xf * (Vector3(x - 0.08, 0.57, 0.42) * k), xf * (Vector3(x + 0.08, 0.57, 0.42) * k),
				xf * (Vector3(x + 0.08, 0.62, 0.42) * k), xf * (Vector3(x - 0.08, 0.62, 0.42) * k)], normal)
	_solid(c, xf, Vector3(0, 0.225, 0) * k, Vector3(7.2, 0.45, 1.2) * k)


## Gilt pilasters and drawn-back drapes either side of a hall's picture, facing local +Z.
## Another size stretches each axis by its share of the piece's own size.
static func _show_proscenium(c: Object, xf: Transform3D, size: Vector3, e: Dictionary) -> void:
	var k := size / SHOW_SIZE
	var gilt := _colour(e, "colour", SHOW_GILT)
	var b: RoomMesh = c.s
	# The kit's own gilding and drapes (kit.gd `gilt`, `drapes`: brass, and velvet that pleats), as a palace gate's.
	b.surface(c.mat("gilt", gilt))
	for s: float in [-1.0, 1.0]:
		_box(b, xf, Vector3(s * 2.5, 1.4, 0.0) * k, Vector3(0.28, 2.8, 0.12) * k)
		_box(b, xf, Vector3(s * 2.5, 0.08, 0.0) * k, Vector3(0.4, 0.16, 0.18) * k)
		_box(b, xf, Vector3(s * 2.5, 2.86, 0.0) * k, Vector3(0.4, 0.12, 0.18) * k)
		_solid(c, xf, Vector3(s * 2.5, 1.4, 0.0) * k, Vector3(0.28, 2.8, 0.12) * k)
	for s: float in [-1.0, 1.0]:
		for j in 4:
			b.surface(c.mat("drapes", SHOW_DRAPE if j % 2 == 0 else SHOW_DRAPE * 0.7))
			var x0 := s * (2.06 + 0.075 * j)
			var x1 := s * (2.06 + 0.075 * (j + 1))
			var z0 := 0.06 if j % 2 == 0 else 0.11
			var z1 := 0.11 if j % 2 == 0 else 0.06
			var p0 := Vector3(x0, 0.0, z0) * k
			var p1 := Vector3(x1, 0.0, z1) * k
			if s < 0.0:
				var swap := p0
				p0 = p1
				p1 = swap
			var up := Vector3(0.0, 2.8, 0.0) * k
			var normal := (xf.basis * (p1 - p0).cross(up)).normalized()
			b.face([xf * p0, xf * p1, xf * (p1 + up), xf * (p0 + up)], normal)


# --- An ocean liner's lounge --------------------------------------------------------------------------------------

## An Art Deco stepped screen surround for an ocean liner's lounge: a low walnut dais with a brass speed-line lip,
## three-tier stepped walnut and cream flanks with chrome speed lines and recessed glowing coves (PieceCove), a
## stepped header with a brass sunburst chevron above the picture, and two fluted brass and opal-glass torchières.
## Back at local z 0, facing local +Z. Stretches cleanly with `size`.
static func _liner_proscenium(c: Object, xf: Transform3D, size: Vector3, e: Dictionary) -> void:
	var k := size / LINER_PROS_SIZE
	var wood := _colour(e, "colour", LINER_WALNUT)
	var gilt := _colour(e, "accent", LINER_GILT)
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var fwd := (xf.basis * Vector3.BACK).normalized()
	# Low stepped walnut dais with a dark plinth and gleaming brass speed-line band along its front lip.
	s.surface(c.mat("iron", Color(0.06, 0.055, 0.05)))
	_box(s, xf, Vector3(0.0, 0.05, 0.4) * k, Vector3(6.4, 0.1, 0.8) * k)
	s.surface(c.mat("wood", wood))
	_box(s, xf, Vector3(0.0, 0.22, 0.43) * k, Vector3(6.6, 0.24, 0.86) * k)
	_solid(c, xf, Vector3(0.0, 0.17, 0.43) * k, Vector3(6.6, 0.34, 0.86) * k)
	# Stepped walnut flanks either side of the screen (three receding tiers, clearing the arched roof).
	for side: float in [-1.0, 1.0]:
		var tiers := [[2.38, 0.34, 3.52, 0.32, 0.22], [2.74, 0.34, 3.42, 0.36, 0.30], [3.08, 0.34, 3.30, 0.32, 0.38]]
		for tr: Array in tiers:
			var h := float(tr[2]) - float(tr[1])
			var d := float(tr[4])
			_box(s, xf, Vector3(side * float(tr[0]), float(tr[1]) + h * 0.5, d * 0.5) * k,
					Vector3(float(tr[3]), h, d) * k)
		_solid(c, xf, Vector3(side * 2.74, 1.84, 0.19) * k, Vector3(1.04, 3.0, 0.38) * k)
	# Stepped header lintel above the screen (y 3.52..3.76).
	_box(s, xf, Vector3(0.0, 3.64, 0.14) * k, Vector3(4.9, 0.24, 0.28) * k)
	# Recessed glowing Art Deco coves (PieceCove: live colour and brightness, dims with house lamps).
	var cove: RoomMesh = c.cove
	cove.surface(c.kit.cove_material())
	var cream_lin := LINER_CREAM.srgb_to_linear()
	cove.colour = Color(cream_lin.r, cream_lin.g, cream_lin.b, 0.96)
	for side: float in [-1.0, 1.0]:
		# Two vertical lit plaster cove strips nested in the stepped setbacks on each side.
		for cx_d: Array in [[2.55, 0.24, 3.44], [2.91, 0.32, 3.32]]:
			var x := side * float(cx_d[0])
			var z := float(cx_d[1])
			var top := float(cx_d[2])
			cove.face([xf * (Vector3(x - 0.06, 0.42, z) * k), xf * (Vector3(x + 0.06, 0.42, z) * k),
					xf * (Vector3(x + 0.06, top, z) * k), xf * (Vector3(x - 0.06, top, z) * k)], fwd)
	# Horizontal lit cove soffit band along the header above the picture.
	cove.face([xf * (Vector3(-2.35, 3.49, 0.29) * k), xf * (Vector3(2.35, 3.49, 0.29) * k),
			xf * (Vector3(2.35, 3.61, 0.29) * k), xf * (Vector3(-2.35, 3.61, 0.29) * k)], fwd)
	cove.colour = Color.WHITE
	# Gleaming reflecting brass trim: dais speed lines, stepped vertical mouldings, header sunburst chevron.
	u.surface(c.shiny("gilt", 0.85, 0.65, 0.16))
	u.colour = gilt.srgb_to_linear()
	_box(u, xf, Vector3(0.0, 0.33, 0.865) * k, Vector3(6.62, 0.035, 0.025) * k)
	_box(u, xf, Vector3(0.0, 0.24, 0.865) * k, Vector3(6.62, 0.02, 0.02) * k)
	for side: float in [-1.0, 1.0]:
		_box(u, xf, Vector3(side * 2.21, 1.93, 0.225) * k, Vector3(0.04, 3.18, 0.03) * k)
		_box(u, xf, Vector3(side * 3.24, 1.82, 0.385) * k, Vector3(0.045, 2.96, 0.03) * k)
	# Sunburst fan of seven gilt rays centered on the header above the picture.
	for r in 7:
		var ang := deg_to_rad(-60.0 + 20.0 * r)
		var ray_len := 0.22 if r % 2 == 0 else 0.16
		var mid := Vector3(sin(ang) * ray_len * 0.5, 3.57 + cos(ang) * ray_len * 0.5, 0.305) * k
		_box(u, xf, mid, Vector3(0.028, ray_len, 0.022) * k, Basis(Vector3.BACK, -ang))
	_box(u, xf, Vector3(0.0, 3.56, 0.31) * k, Vector3(0.18, 0.07, 0.03) * k)
	# Two stepped Art Deco fluted brass & 3-tier opal-glass torchières standing on the dais flanks.
	var lit: RoomMesh = c.lit
	lit.surface(c.shade(LINER_TORCH))
	var sc := xf.basis.get_scale().x
	for side: float in [-1.0, 1.0]:
		var tx := side * 2.78
		var tz := 0.56
		var base_at := Vector3(tx, 0.34, tz) * k
		# Stepped octagonal/fluted brass plinth, slim column, and flared Art Deco tulip cup.
		_lathe(u, xf, [Vector2(0.24, 0.0), Vector2(0.24, 0.045), Vector2(0.18, 0.05), Vector2(0.18, 0.10),
				Vector2(0.115, 0.11), Vector2(0.065, 0.17), Vector2(0.055, 1.14), Vector2(0.16, 1.22),
				Vector2(0.19, 1.25), Vector2(0.17, 1.26)], base_at, 12)
		# Brass collar bands separating the three stepped opal-glass tiers.
		_lathe(u, xf, [Vector2(0.155, 1.41), Vector2(0.175, 1.425), Vector2(0.145, 1.44)], base_at, 12)
		_lathe(u, xf, [Vector2(0.115, 1.565), Vector2(0.132, 1.58), Vector2(0.095, 1.595)], base_at, 12)
		# Three-tier stepped Art Deco opal-glass lantern flame.
		_lathe(lit, xf, [Vector2(0.145, 1.25), Vector2(0.168, 1.28), Vector2(0.158, 1.415),
				Vector2(0.132, 1.435), Vector2(0.122, 1.57),
				Vector2(0.088, 1.59), Vector2(0.072, 1.70), Vector2(0.0, 1.76)], base_at, 12)
		c.lamps.append([xf * (Vector3(tx, 1.82, tz) * k), LINER_TORCH, 0.65])
	# Chrome speed bands flanking the screen's stepped opening.
	u.surface(c.shiny("chrome", 1.0, 0.85, 0.08))
	u.colour = Color(0.86, 0.88, 0.9).srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		_box(u, xf, Vector3(side * 2.57, 1.88, 0.305) * k, Vector3(0.025, 3.08, 0.025) * k)
		_box(u, xf, Vector3(side * 2.93, 1.82, 0.385) * k, Vector3(0.025, 2.96, 0.025) * k)
	_box(u, xf, Vector3(0.0, 3.75, 0.285) * k, Vector3(4.92, 0.028, 0.025) * k)
	u.colour = Color.WHITE
	var _unused := sc


## A deeply pleated floor-length velvet curtain panel for an ocean liner's windows (unbaked, so a motion system can
## sway the group smoothly with the sea swell). Local y 0 is the hem, y = size.y the rod, front faces +Z.
static func _liner_drape(c: Object, xf: Transform3D, size: Vector3, e: Dictionary) -> void:
	var w := size.x
	var h := size.y
	var d := size.z
	var col := _colour(e, "colour", LINER_DRAPE).srgb_to_linear()
	var hem := _colour(e, "accent", LINER_GILT).srgb_to_linear()
	var u: RoomMesh = c.u
	u.surface(c.soft("drapes", true))
	var folds := 6
	var up := Vector3(0.0, h, 0.0)
	var hem_h := minf(0.08, h * 0.06)
	var hem_up := Vector3(0.0, hem_h, 0.0)
	for j in folds:
		var x0 := -w * 0.5 + w * float(j) / folds
		var x1 := -w * 0.5 + w * float(j + 1) / folds
		var xm := (x0 + x1) * 0.5
		var z_back := -d * 0.45
		var z_front := d * 0.55
		# Each pleat: two slanted faces forming a rounded rib towards +Z, shaded deeper in the trough.
		var left_n := (xf.basis * Vector3(-d, 0.0, (x1 - x0) * 0.5)).normalized()
		var right_n := (xf.basis * Vector3(d, 0.0, (x1 - x0) * 0.5)).normalized()
		u.colour = col * 0.68
		u.face([xf * Vector3(x0, hem_h, z_back), xf * Vector3(xm, hem_h, z_front),
				xf * Vector3(xm, h, z_front), xf * Vector3(x0, h, z_back)], left_n)
		u.colour = col
		u.face([xf * Vector3(xm, hem_h, z_front), xf * Vector3(x1, hem_h, z_back),
				xf * Vector3(x1, h, z_back), xf * Vector3(xm, h, z_front)], right_n)
		# Tailored weighted gold hem band at the foot of the curtain, capped cleanly underneath.
		u.colour = hem * 0.72
		u.face([xf * Vector3(x0, 0.0, z_back), xf * Vector3(xm, 0.0, z_front),
				xf * Vector3(xm, hem_h, z_front), xf * Vector3(x0, hem_h, z_back)], left_n)
		u.colour = hem
		u.face([xf * Vector3(xm, 0.0, z_front), xf * Vector3(x1, 0.0, z_back),
				xf * Vector3(x1, hem_h, z_back), xf * Vector3(xm, hem_h, z_front)], right_n)
		u.colour = hem * 0.5
		u.face([xf * Vector3(x0, 0.0, z_back), xf * Vector3(x1, 0.0, z_back), xf * Vector3(xm, 0.0, z_front)],
				(xf.basis * Vector3.DOWN).normalized())
	# Subtle outer return edges so the curtain reads solid from oblique angles.
	u.colour = col * 0.55
	var side_l := (xf.basis * Vector3.LEFT).normalized()
	var side_r := (xf.basis * Vector3.RIGHT).normalized()
	u.face([xf * Vector3(-w * 0.5, 0.0, -d * 0.5), xf * Vector3(-w * 0.5, 0.0, -d * 0.45),
			xf * Vector3(-w * 0.5, h, -d * 0.45), xf * Vector3(-w * 0.5, h, -d * 0.5)], side_l)
	u.face([xf * Vector3(w * 0.5, 0.0, -d * 0.45), xf * Vector3(w * 0.5, 0.0, -d * 0.5),
			xf * Vector3(w * 0.5, h, -d * 0.5), xf * Vector3(w * 0.5, h, -d * 0.45)], side_r)
	u.colour = Color.WHITE
	var _u2 := up + hem_up


## A walnut-and-brass Art Deco curtain pelmet cornice box: open underneath so swaying window drapes hang freely up
## inside it with no visible cut edges. Back at local z 0, foot at local y 0, front facing +Z.
static func _liner_pelmet(c: Object, xf: Transform3D, size: Vector3, e: Dictionary) -> void:
	var w := size.x
	var h := size.y
	var d := size.z
	var wood := _colour(e, "colour", LINER_WALNUT)
	var gilt := _colour(e, "accent", LINER_GILT)
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	s.surface(c.mat("wood", wood))
	# Front valance fascia, top cover and two end returns (open underneath for the drapes).
	_box(s, xf, Vector3(0.0, h * 0.5, d - 0.02), Vector3(w, h, 0.04))
	_box(s, xf, Vector3(0.0, h - 0.015, d * 0.5), Vector3(w, 0.03, d))
	for side: float in [-1.0, 1.0]:
		_box(s, xf, Vector3(side * (w * 0.5 - 0.02), h * 0.5, d * 0.5), Vector3(0.04, h, d))
	# Twin gleaming brass Art Deco speed lines along the lower front lip.
	u.surface(c.shiny("gilt", 0.85, 0.65, 0.16))
	u.colour = gilt.srgb_to_linear()
	_box(u, xf, Vector3(0.0, 0.026, d + 0.008), Vector3(w + 0.01, 0.018, 0.016))
	_box(u, xf, Vector3(0.0, 0.068, d + 0.006), Vector3(w + 0.01, 0.012, 0.012))
	u.colour = Color.WHITE


## An Art Deco sunburst bulkhead clock with stepped walnut backing, gleaming brass bezel, radial rays and horizontal
## chrome/brass speed wings. Its working dial draws into PieceClock. Centered at local (0, 0, 0), back at z 0, facing +Z.
static func _liner_clock(c: Object, xf: Transform3D, size: Vector3, e: Dictionary) -> void:
	var w := size.x
	var h := size.y
	var r := clampf(h * 0.41, 0.16, 0.36)
	var sc := xf.basis.get_scale().x
	var basis := xf.basis.orthonormalized()
	var wood := _colour(e, "colour", LINER_WALNUT)
	var gilt := _colour(e, "accent", LINER_GILT)
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	# Stepped streamlined walnut backing plaque along the bulkhead.
	s.surface(c.mat("wood", wood))
	_box(s, xf, Vector3(0.0, 0.0, 0.02), Vector3(w * 0.82, h * 0.44, 0.04))
	_box(s, xf, Vector3(0.0, 0.0, 0.028), Vector3(r * 2.55, h * 0.78, 0.056))
	# Reflecting brass circular bezel, twelve sunburst rays and horizontal wing speed lines.
	u.surface(c.shiny("gilt", 0.85, 0.65, 0.16))
	u.colour = gilt.srgb_to_linear()
	Shapes.arch(u, xf * Vector3(0.0, 0.0, 0.062), r * sc, (r + 0.048) * sc, 0.056 * sc, 24, basis, 0.0, TAU,
			["front", "inner", "outer"])
	for k in 12:
		var ang := TAU * float(k) / 12.0
		var ray_len := 0.11 if k % 3 == 0 else 0.07
		var mid := Vector3(sin(ang) * (r + 0.044 + ray_len * 0.5), cos(ang) * (r + 0.044 + ray_len * 0.5), 0.056)
		_box(u, xf, mid, Vector3(0.022, ray_len, 0.018), Basis(Vector3.BACK, -ang))
	for side: float in [-1.0, 1.0]:
		var wing_w := w * 0.5 - (r + 0.12)
		if wing_w > 0.08:
			var x_mid := side * (r + 0.12 + wing_w * 0.5)
			_box(u, xf, Vector3(x_mid, 0.075, 0.046), Vector3(wing_w * 0.96, 0.022, 0.018))
			_box(u, xf, Vector3(x_mid - side * wing_w * 0.08, 0.0, 0.048), Vector3(wing_w * 0.8, 0.026, 0.02))
			_box(u, xf, Vector3(x_mid - side * wing_w * 0.16, -0.075, 0.046), Vector3(wing_w * 0.64, 0.022, 0.018))
	# Chrome outer rim accents on the stepped walnut plaque.
	u.surface(c.shiny("chrome", 1.0, 0.85, 0.08))
	u.colour = Color(0.86, 0.88, 0.9).srgb_to_linear()
	_box(u, xf, Vector3(0.0, h * 0.39, 0.058), Vector3(r * 2.58, 0.016, 0.016))
	_box(u, xf, Vector3(0.0, -h * 0.39, 0.058), Vector3(r * 2.58, 0.016, 0.016))
	u.colour = Color.WHITE
	# Live illuminated Art Deco clock face (PieceClock, hands driven by real wall-clock time).
	c.clocks.append([xf * Vector3(0.0, 0.0, 0.078), xf.basis * Vector3(r, 0.0, 0.0), xf.basis * Vector3(0.0, r, 0.0),
			(xf.basis * Vector3.BACK).normalized()])


## A ship's teak-and-brass promenade deck railing along an exterior ledge (unbaked, no interior collision boxes).
## Runs along local X for `size.x`, height `size.y`, foot at local y 0.
static func _deck_rail(c: Object, xf: Transform3D, size: Vector3, e: Dictionary) -> void:
	var w := size.x
	var h := size.y
	var teak := _colour(e, "colour", Color(0.38, 0.22, 0.12)).srgb_to_linear()
	var rail_col := _colour(e, "accent", Color(0.82, 0.78, 0.72)).srgb_to_linear()
	var u: RoomMesh = c.u
	# Polished teak cap handrail along the top.
	u.surface(c.soft("wood", true))
	u.colour = teak
	_box(u, xf, Vector3(0.0, h - 0.025, 0.0), Vector3(w, 0.05, 0.09))
	# Three horizontal painted-white / brass guard bars and evenly spaced vertical stanchions.
	u.surface(c.soft("gilt", true))
	u.colour = rail_col
	for frac: float in [0.26, 0.50, 0.74]:
		_box(u, xf, Vector3(0.0, h * frac, 0.0), Vector3(w, 0.028, 0.028))
	var bays := maxi(roundi(w / 1.5), 2)
	for i in bays + 1:
		var x := -w * 0.5 + w * float(i) / bays
		_box(u, xf, Vector3(x, (h - 0.05) * 0.5, 0.0), Vector3(0.036, h - 0.05, 0.036))
	u.colour = Color.WHITE
