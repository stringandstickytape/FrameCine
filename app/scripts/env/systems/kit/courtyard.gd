extends RefCounted

## The atmospheric courtyard's pieces (docs/environments.md, "The kit" and "Room: Atmospheric 1928"; since 2026-11-08,
## "continue working on the environments one-by-one ... really improving their quality, imagination, delight, detail,
## lighting and so on", the user, 2026-11-08). A picture palace dressed as a Mediterranean town square at dusk: houses
## along the walls, each its own (a wash of colour, windows lit from inside with a glimpse of the room behind,
## shutters, balconies, a loggia, a belvedere tower, a pergola, a Moorish oriel, lanterns on brackets, geraniums,
## bougainvillea, a fountain), a palace gate round the screen (towers with belfries and organ grilles, a gilt arch,
## velvet drapes, a balustrade against the sky), cypresses, palms and a stone pine beyond the walls.
## Everything is ours, drawn here from boxes, strips and lathes; nothing borrowed. No figure anywhere: the statues are
## lions and urns.
##
## Pieces (pieces.gd dispatches here; a piece works in its own frame as pieces.gd's do: front +Z, foot at y 0):
##   house        a house front along a wall: size [width, the eave's height (room y), how far its face stands out];
##                colour (its wash), accent (its shutters), seed, features (FEATURES)
##   palace_gate  round the room's screen: size [the room's width, 0, depth]
##   cypress, palm, pine   trees beyond the walls: size [spread, height, spread]
##   lantern      a wall lantern on its bracket (its glass glows, house group; a stand-in lamp and a bake light)
##   pedestal     a stone pedestal; holds lion (lying, head up) or urn
##
## Cost: the parts go into the kit's shared meshes by material, so the pieces cost draws by material, not by count:
## baked (PieceStatic) the façades' plaster, the stone, the roofs, the joinery; unbaked (PieceSoft) the ironwork, the
## gilding, the small stone and the terracotta, cloth, the drapes, leaves and flowers; PieceLamps the lanterns'
## glass, PieceRoomWindows the lit windows (baked, so their glow falls on the reveals), PieceWater a fountain's water.
## Small parts are unbaked: each baked face is a lightmap chart, and thousands of tiny charts would swell the atlas.
## Colours: per vertex (the kit's tinted materials, RoomMesh.colour in linear light), so a street of houses in many
## washes is still one draw.

const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const Shapes := preload("res://scripts/env/systems/kit/shapes.gd")
const PhysicsShapes := preload("res://scripts/play/physics_shapes.gd")
const Auditorium := preload("res://scripts/env/systems/auditorium.gd")

const FEATURES: Array[String] = ["balcony", "balconettes", "loggia", "tower", "pergola", "gable", "oriel", "exit",
		"door", "niche", "lion_niche", "fountain", "lanterns", "vines", "rug", "geraniums", "grilles", "booth",
		"arcade", "dark"]

## The washes' terracotta, iron and gilt where an entry gives none.
const TERRACOTTA := Color(0.66, 0.34, 0.2)
const GERANIUM := Color(0.86, 0.12, 0.14)
const BRACT := Color(0.78, 0.1, 0.42)
const LANTERN := Color(1.0, 0.7, 0.38)
const DARK_WOOD := Color(0.16, 0.1, 0.06)
const SOFFIT := Color(0.32, 0.22, 0.14)
const STONE := Color(0.82, 0.76, 0.64)
## The lanterns' glass: how bright, and how much of it stays in the film (the house group's level does the rest).
const LANTERN_ENERGY := 1.6


static func build(piece: String, c: Object, xf: Transform3D, size: Vector3, e: Dictionary) -> void:
	match piece:
		"house":
			_house(c, xf, size, e)
		"palace_gate":
			_palace_gate(c, xf, size, e)
		"cypress":
			_cypress(c, xf, size, e)
		"palm":
			_palm(c, xf, size, e)
		"pine":
			_pine(c, xf, size, e)
		"lantern":
			_lantern(c, xf, Vector3(0, size.y, 0), 1.0)
		"pedestal":
			_pedestal(c, xf, size, e)
	_white(c)


# --- Helpers ----------------------------------------------------------------------------------------------------------

## Every mesh back to white (the colour the other pieces expect).
static func _white(c: Object) -> void:
	for b: RoomMesh in [c.s, c.u, c.lit, c.windows, c.water]:
		b.colour = Color.WHITE


## A colour (sRGB) as the tinted materials take it: linear, per vertex.
static func _tint(b: RoomMesh, colour: Color) -> void:
	b.colour = colour.srgb_to_linear()


static func _box(b: RoomMesh, xf: Transform3D, centre: Vector3, size: Vector3, basis := Basis(), skip: Array = []) -> void:
	b.box(xf * centre, size, xf.basis * basis, skip)


static func _face(b: RoomMesh, xf: Transform3D, corners: Array, n: Vector3) -> void:
	var w: Array = []
	for p: Vector3 in corners:
		w.append(xf * p)
	b.face(w, (xf.basis * n).normalized())


static func _beam(b: RoomMesh, xf: Transform3D, a: Vector3, d: Vector3, size: Vector2) -> void:
	Shapes.beam(b, xf * a, xf * d, size, xf.basis * Vector3.UP)


static func _lathe(b: RoomMesh, xf: Transform3D, profile: Array, centre: Vector3, sides := 10, basis := Basis(),
		arc := TAU, start := 0.0) -> void:
	Shapes.lathe(b, profile, xf * centre, sides, xf.basis * basis, arc, start)


static func _solid(c: Object, xf: Transform3D, centre: Vector3, size: Vector3) -> void:
	c.shapes.append(PhysicsShapes.box(xf * centre, size, xf.basis.orthonormalized()))


static func _colour(e: Dictionary, key: String, fallback: Color) -> Color:
	var v: Variant = e.get(key)
	if v == null or (v is Array and (v as Array).is_empty()):
		return fallback
	if v is Color:
		return v
	if v is String:
		return Color(str(v))
	return Color(float(v[0]), float(v[1]), float(v[2]))


## The floor under local x of a piece along a wall (its face's foot), as a local y.
static func _ground(c: Object, xf: Transform3D, x: float, z: float) -> float:
	var p := xf * Vector3(x, 0.0, z)
	return c.ground_at(p, xf.origin.y) - xf.origin.y


# --- Windows, doors and their dress --------------------------------------------------------------------------------

## A window: a hole in the façade at local x, its sill at y0, w wide, h to the springing (an arched one rises w / 2
## more), its face at z0. The reveal goes rd into the wall; at its back the lit room (or dark glass); glazing bars,
## a stone surround and sill, shutters folded open against the wall. Returns the hole for the façade (Rect2 in
## (x from the façade's left end, y)). opts: arched, lit (kind 0..5 or -1 dark), shutters (a colour or null), grille,
## moment (when it goes out), surround.
static func _window(c: Object, xf: Transform3D, x: float, y0: float, w: float, h: float, z0: float, left: float,
		opts: Dictionary) -> Rect2:
	var arched := bool(opts.get("arched", false))
	var rd := 0.24
	var r := w * 0.5
	var top := y0 + h + (r if arched else 0.0)
	var zb := z0 - rd
	var stone: Material = c.tinted("stone", "ashlar")
	var stone_soft: Material = c.soft("stone")
	var wall: Material = c.tinted("plaster", "lime_wash")
	var wash: Color = opts.get("wash", Color(0.8, 0.7, 0.55))
	# The reveal: the jambs, the sill's top, the head (flat or the arch's soffit), in the wall's wash, a little darker.
	c.s.surface(wall)
	_tint(c.s, wash * 0.86)
	for s: float in [-1.0, 1.0]:
		_face(c.s, xf, [Vector3(x + s * r, y0, z0), Vector3(x + s * r, y0, zb), Vector3(x + s * r, y0 + h, zb),
				Vector3(x + s * r, y0 + h, z0)], Vector3(-s, 0, 0))
	if arched:
		Shapes.arch(c.s, xf * Vector3(x, y0 + h, z0 - rd * 0.5), r, r, rd, 8, xf.basis, 0.0, PI, ["inner"])
		# The façade's corners round the arch's head: a fan from each corner of the hole.
		_tint(c.s, wash)
		for s: float in [-1.0, 1.0]:
			var pts: Array = [Vector3(x + s * r, top, z0)]
			for k in 9:
				var t := PI * 0.5 * (1.0 - k / 8.0) if s > 0.0 else PI * 0.5 * (1.0 + k / 8.0)
				pts.append(Vector3(x + cos(t) * r, y0 + h + sin(t) * r, z0))
			_face(c.s, xf, pts, Vector3.BACK)
	else:
		_face(c.s, xf, [Vector3(x - r, top, z0), Vector3(x + r, top, z0), Vector3(x + r, top, zb),
				Vector3(x - r, top, zb)], Vector3.DOWN)
	# The room behind (or dark glass): one face, its size, kind and moment in its vertex colour.
	var kind := int(opts.get("lit", 0))
	c.windows.surface(c.kit.window_material())
	c.windows.colour = Color(w / 4.0, (top - y0) / 4.0, 0.99 if kind < 0 else (kind + 0.5) / 8.0,
			float(opts.get("moment", 0.5)))
	var glass: Array = [Vector3(x - r, y0, zb), Vector3(x + r, y0, zb)]
	if arched:
		for k in 9:
			var t := PI * k / 8.0
			glass.append(Vector3(x + cos(t) * r, y0 + h + sin(t) * r, zb))
	else:
		glass.append_array([Vector3(x + r, top, zb), Vector3(x - r, top, zb)])
	_face(c.windows, xf, glass, Vector3.BACK)
	# Glazing bars: a mullion and a transom (the arch's springing, or two thirds up).
	c.u.surface(c.soft("wood"))
	_tint(c.u, DARK_WOOD)
	var zg := zb + 0.03
	_box(c.u, xf, Vector3(x, (y0 + top) * 0.5, zg), Vector3(0.04, top - y0, 0.04), Basis(), [RoomMesh.FRONT])
	var ty := y0 + h if arched else y0 + h * 0.68
	_box(c.u, xf, Vector3(x, ty, zg), Vector3(w, 0.04, 0.04), Basis(), [RoomMesh.FRONT])
	for s: float in [-1.0, 1.0]:
		_box(c.u, xf, Vector3(x + s * (r - 0.03), (y0 + top) * 0.5, zg), Vector3(0.06, top - y0, 0.05), Basis(),
				[RoomMesh.FRONT])
	_box(c.u, xf, Vector3(x, y0 + 0.03, zg), Vector3(w, 0.06, 0.05), Basis(), [RoomMesh.FRONT])
	# The sill: a stone slab standing out under the window.
	c.s.surface(stone)
	_tint(c.s, opts.get("stone", STONE))
	_box(c.s, xf, Vector3(x, y0 - 0.04, z0 + 0.06), Vector3(w + 0.24, 0.08, 0.2 + rd * 0.0), Basis(), [RoomMesh.FRONT])
	# The surround: a moulded band round the opening (unbaked: small), a keystone over an arch.
	if bool(opts.get("surround", true)):
		c.u.surface(stone_soft)
		_tint(c.u, opts.get("stone", STONE))
		for s: float in [-1.0, 1.0]:
			_box(c.u, xf, Vector3(x + s * (r + 0.07), (y0 + y0 + h) * 0.5, z0 + 0.02), Vector3(0.14, h, 0.05), Basis(),
					[RoomMesh.FRONT])
		if arched:
			Shapes.arch(c.u, xf * Vector3(x, y0 + h, z0 + 0.02), r, r + 0.14, 0.05, 8, xf.basis, 0.0, PI,
					["front", "outer"])
			_box(c.u, xf, Vector3(x, top + 0.06, z0 + 0.04), Vector3(0.16, 0.22, 0.08), Basis(), [RoomMesh.FRONT])
		else:
			_box(c.u, xf, Vector3(x, top + 0.07, z0 + 0.02), Vector3(w + 0.28, 0.14, 0.05), Basis(), [RoomMesh.FRONT])
			_box(c.u, xf, Vector3(x, top + 0.17, z0 + 0.06), Vector3(w + 0.4, 0.06, 0.13), Basis(), [RoomMesh.FRONT])
	# Shutters folded open against the wall, painted.
	var shutters: Variant = opts.get("shutters")
	if shutters != null:
		c.u.surface(c.soft("wood"))
		var sh := y0 + h - 0.02
		for s: float in [-1.0, 1.0]:
			var sx := x + s * (r + 0.16 + w * 0.25)
			_tint(c.u, shutters as Color)
			_box(c.u, xf, Vector3(sx, (y0 + sh) * 0.5, z0 + 0.035),
					Vector3(w * 0.5, sh - y0, 0.035), Basis(), [RoomMesh.FRONT])
			# Its louvres: darker bands across the panel's two fields.
			_tint(c.u, (shutters as Color) * 0.62)
			for k in 2:
				var fy := y0 + (sh - y0) * (0.27 + 0.48 * k)
				_face(c.u, xf, [Vector3(sx - w * 0.19, fy - (sh - y0) * 0.19, z0 + 0.054),
						Vector3(sx + w * 0.19, fy - (sh - y0) * 0.19, z0 + 0.054),
						Vector3(sx + w * 0.19, fy + (sh - y0) * 0.19, z0 + 0.054),
						Vector3(sx - w * 0.19, fy + (sh - y0) * 0.19, z0 + 0.054)], Vector3.BACK)
	# A ground floor's iron grille, standing out from the wall.
	if bool(opts.get("grille", false)):
		c.u.surface(c.soft("iron", false))
		var bars := maxi(int(w / 0.12), 3)
		for k in bars + 1:
			var bx := x - r - 0.05 + (w + 0.1) * k / bars
			_box(c.u, xf, Vector3(bx, (y0 + top) * 0.5, z0 + 0.1), Vector3(0.022, top - y0 + 0.1, 0.022), Basis(),
					[RoomMesh.FRONT])
		for fy: float in [y0 + 0.08, (y0 + top) * 0.5, top - 0.05]:
			_box(c.u, xf, Vector3(x, fy, z0 + 0.1), Vector3(w + 0.14, 0.03, 0.03), Basis(), [RoomMesh.FRONT])
		for s: float in [-1.0, 1.0]:
			_box(c.u, xf, Vector3(x + s * (r + 0.06), y0 + 0.02, z0 + 0.06), Vector3(0.03, 0.03, 0.09))
			_box(c.u, xf, Vector3(x + s * (r + 0.06), top - 0.05, z0 + 0.06), Vector3(0.03, 0.03, 0.09))
	return Rect2(x - r, y0, w, top - y0)


## A doorway's arch round the auditorium's exit (its leaves and sign are the builder's, in front of the wall): rusticated
## jambs, a ring of voussoirs with a keystone, the tympanum over the door dark, an iron fan in it.
static func _exit_arch(c: Object, xf: Transform3D, x: float, y0: float, z0: float, wash: Color) -> void:
	var dw := 1.8
	var dh := 2.35
	var r_in := dw * 0.5 + 0.2
	var spring := y0 + dh + 0.2
	c.s.surface(c.tinted("stone", "ashlar"))
	_tint(c.s, STONE)
	for s: float in [-1.0, 1.0]:
		for k in 5:
			var bh := (spring - y0) / 5.0
			var wide := 0.42 if k % 2 == 0 else 0.32
			_box(c.s, xf, Vector3(x + s * (r_in + wide * 0.5 - 0.02), y0 + bh * (k + 0.5), z0 + 0.07),
					Vector3(wide, bh - 0.025, 0.14), Basis(), [RoomMesh.FRONT])
	Shapes.arch(c.s, xf * Vector3(x, spring, z0 + 0.07), r_in, r_in + 0.4, 0.14, 12, xf.basis, 0.0, PI,
			["front", "inner", "outer"])
	_box(c.s, xf, Vector3(x, spring + r_in + 0.12, z0 + 0.1), Vector3(0.3, 0.5, 0.2), Basis(), [RoomMesh.FRONT])
	# The tympanum: dark wood over the door's head, an iron fan of bars in it.
	c.s.surface(c.tinted("wood"))
	_tint(c.s, DARK_WOOD)
	var pts: Array = [Vector3(x + r_in, y0 + dh + 0.06, z0 + 0.012)]
	for k in 13:
		var t := PI * k / 12.0
		pts.append(Vector3(x + cos(t) * r_in, spring + sin(t) * r_in, z0 + 0.012))
	pts.append(Vector3(x - r_in, y0 + dh + 0.06, z0 + 0.012))
	_face(c.s, xf, pts, Vector3.BACK)
	c.u.surface(c.soft("iron", false))
	for k in 7:
		var t := PI * (k + 0.5) / 7.0
		_beam(c.u, xf, Vector3(x, spring - 0.05, z0 + 0.03), Vector3(x + cos(t) * (r_in - 0.05),
				spring + sin(t) * (r_in - 0.05), z0 + 0.03), Vector2(0.025, 0.025))
	Shapes.arch(c.u, xf * Vector3(x, spring - 0.05, z0 + 0.03), 0.26, 0.3, 0.03, 6, xf.basis, 0.0, PI,
			["front", "outer"])


## A lantern on a bracket: an iron arm from the wall at `at` (local; the arm's root), a scroll under it, the lantern
## hanging from its tip: a cap, six panes of glowing glass in an iron frame, a finial. Its light: a stand-in lamp and
## a hidden light for the bake (kit.gd, by bake_lamps).
static func _lantern(c: Object, xf: Transform3D, at: Vector3, strength: float) -> void:
	var iron: Material = c.soft("iron", false)
	c.u.surface(iron)
	var reach := 0.5
	var tip := at + Vector3(0, 0, reach)
	_beam(c.u, xf, at + Vector3(0, 0, 0.02), tip + Vector3(0, 0, 0.04), Vector2(0.035, 0.035))
	_box(c.u, xf, at + Vector3(0, -0.05, 0.03), Vector3(0.12, 0.3, 0.04))
	# The brace under the arm, from the wall up to it, a ring at its middle.
	_beam(c.u, xf, at + Vector3(0, -0.3, 0.02), at + Vector3(0, -0.01, reach * 0.62), Vector2(0.025, 0.025))
	Shapes.arch(c.u, xf * (at + Vector3(0, -0.12, 0.17)), 0.06, 0.08, 0.02, 8, xf.basis * Basis(Vector3.UP, -PI * 0.5),
			0.0, TAU, ["front", "back", "outer"])
	var hang := tip + Vector3(0, -0.12, 0)
	_beam(c.u, xf, tip, hang, Vector2(0.02, 0.02))
	var body_top := hang.y - 0.06
	var body_h := 0.32
	var cap: Array = [Vector2(0.17, 0.0), Vector2(0.15, 0.03), Vector2(0.03, 0.14), Vector2(0.0, 0.16)]
	_lathe(c.u, xf, cap, Vector3(hang.x, body_top, hang.z), 6)
	var bottom: Array = [Vector2(0.0, -0.1), Vector2(0.03, -0.08), Vector2(0.1, -0.02), Vector2(0.11, 0.0)]
	_lathe(c.u, xf, bottom, Vector3(hang.x, body_top - body_h, hang.z), 6)
	for k in 6:
		var t := TAU * k / 6.0
		var a := Vector3(hang.x + sin(t) * 0.15, body_top, hang.z + cos(t) * 0.15)
		var d := Vector3(hang.x + sin(t) * 0.1, body_top - body_h, hang.z + cos(t) * 0.1)
		_beam(c.u, xf, a, d, Vector2(0.018, 0.018))
	c.lit.surface(_lantern_glass(c))
	_lathe(c.lit, xf, [Vector2(0.1, 0.0), Vector2(0.148, body_h)], Vector3(hang.x, body_top - body_h, hang.z), 6)
	c.lamps.append([xf * Vector3(hang.x, body_top - body_h * 0.5, hang.z), LANTERN, strength])


## The lanterns' glass (house group, its own level: it sinks to the group's level in the film, not under it), made once.
static func _lantern_glass(c: Object) -> Material:
	if not c._mats.has("courtyard lantern"):
		c._mats["courtyard lantern"] = c.kit._lamp(LANTERN, LANTERN_ENERGY, 0.0, "house")
	return c._mats["courtyard lantern"]


## A pot of red geraniums (or another plant) standing at `at` (local): a terracotta pot, leaves in a mound, flowers.
static func _geranium(c: Object, xf: Transform3D, at: Vector3, k: float, flower: Color) -> void:
	c.u.surface(c.soft("stone"))
	_tint(c.u, TERRACOTTA)
	_lathe(c.u, xf, [Vector2(0.08 * k, 0.0), Vector2(0.12 * k, 0.17 * k), Vector2(0.135 * k, 0.19 * k),
			Vector2(0.135 * k, 0.21 * k)], at, 7)
	var rng: RandomNumberGenerator = c.rng
	c.u.surface(c.soft("leaves"))
	for i in 9:
		var is_flower := i % 3 == 2
		_tint(c.u, flower if is_flower else Color(0.18, 0.34, 0.12))
		var a := rng.randf() * TAU
		var centre := at + Vector3(sin(a) * 0.08 * k, 0.24 * k + rng.randf() * 0.12 * k, cos(a) * 0.08 * k)
		var dir := Vector3(sin(a), rng.randf_range(0.2, 0.9), cos(a)).normalized()
		var size := (0.09 if is_flower else 0.12) * k
		var across := dir.cross(Vector3.UP).normalized() * size * 0.6
		if across.length() < 0.001:
			across = Vector3.RIGHT * size * 0.6
		Shapes.leaf(c.u, xf * centre, xf.basis * (dir * size), xf.basis * across,
				(xf.basis * dir.cross(across)).normalized())


## A climbing bougainvillea: a twisting stem from the foot of the wall at x up to `top`, then spreading along under
## the eave (or a balcony) `spread` metres either way: clusters of leaves and magenta bracts.
static func _vine(c: Object, xf: Transform3D, x: float, y0: float, top: float, spread: float, z0: float) -> void:
	var rng: RandomNumberGenerator = c.rng
	c.u.surface(c.soft("wood"))
	_tint(c.u, Color(0.3, 0.22, 0.15))
	var p := Vector3(x, y0, z0 + 0.06)
	var steps := maxi(int((top - y0) / 0.4), 2)
	for i in steps:
		var q := Vector3(x + sin(i * 1.7) * 0.12, y0 + (top - y0) * (i + 1) / steps, z0 + 0.06)
		_beam(c.u, xf, p, q, Vector2(0.05, 0.05))
		p = q
	c.u.surface(c.soft("leaves"))
	var clusters := int(spread * 14.0 + (top - y0) * 2.5)
	for i in clusters:
		var along_top := rng.randf() < 0.75
		var centre: Vector3
		if along_top:
			centre = Vector3(x + rng.randf_range(-spread, spread), top - pow(rng.randf(), 2.0) * 1.1, z0 + 0.12)
		else:
			centre = Vector3(x + rng.randf_range(-0.3, 0.3), rng.randf_range(y0 + 0.6, top), z0 + 0.1)
		var bloom := rng.randf() < 0.65
		for j in 9:
			var is_flower := bloom and rng.randf() < 0.7
			_tint(c.u, BRACT * rng.randf_range(0.85, 1.1) if is_flower else Color(0.16, 0.3, 0.1) * rng.randf_range(0.8, 1.2))
			var at := centre + Vector3(rng.randf_range(-0.26, 0.26), rng.randf_range(-0.22, 0.22), rng.randf_range(0.0, 0.16))
			var leaf_len := rng.randf_range(0.08, 0.13)
			var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1.0, 0.4), rng.randf_range(0.2, 1.0)).normalized()
			var across := dir.cross(Vector3.BACK).normalized() * leaf_len * 0.5
			if across.length() < 0.001:
				across = Vector3.RIGHT * leaf_len * 0.5
			Shapes.leaf(c.u, xf * at, xf.basis * (dir * leaf_len), xf.basis * across,
					(xf.basis * dir.cross(across)).normalized())


## A balcony: a stone slab on consoles, an iron railing (rails, balusters, corner posts and returns to the wall),
## pots of geraniums, and maybe a rug hung over the rail.
static func _balcony(c: Object, xf: Transform3D, x: float, y: float, w: float, depth: float, z0: float, stone: Color,
		rug: Variant, pots: int, flower: Color) -> void:
	c.s.surface(c.tinted("stone", "ashlar"))
	_tint(c.s, stone)
	_box(c.s, xf, Vector3(x, y - 0.06, z0 + depth * 0.5), Vector3(w, 0.12, depth), Basis(), [RoomMesh.FRONT])
	c.u.surface(c.soft("stone"))
	_tint(c.u, stone)
	var consoles := maxi(int(w / 1.2) + 1, 2)
	for k in consoles:
		var cx := x - w * 0.5 + 0.15 + (w - 0.3) * k / (consoles - 1)
		_box(c.u, xf, Vector3(cx, y - 0.2, z0 + depth * 0.35), Vector3(0.12, 0.16, depth * 0.7), Basis(), [RoomMesh.FRONT])
		_box(c.u, xf, Vector3(cx, y - 0.34, z0 + depth * 0.2), Vector3(0.1, 0.14, depth * 0.4), Basis(), [RoomMesh.FRONT])
	c.u.surface(c.soft("iron", false))
	var front := z0 + depth - 0.05
	var rail_h := 0.95
	_box(c.u, xf, Vector3(x, y + rail_h, front), Vector3(w, 0.04, 0.05))
	_box(c.u, xf, Vector3(x, y + 0.08, front), Vector3(w, 0.03, 0.03))
	_box(c.u, xf, Vector3(x, y + rail_h - 0.16, front), Vector3(w, 0.025, 0.025))
	var n := maxi(int(w / 0.13), 4)
	for k in n + 1:
		var bx := x - w * 0.5 + w * k / n
		_box(c.u, xf, Vector3(bx, y + rail_h * 0.5, front), Vector3(0.018, rail_h, 0.018), Basis(),
				[RoomMesh.UP, RoomMesh.DOWN])
	# A scroll in each panel between the rails.
	var panels := maxi(int(w / 0.9), 1)
	for k in panels:
		var px := x - w * 0.5 + w * (k + 0.5) / panels
		for s: float in [-1.0, 1.0]:
			Shapes.arch(c.u, xf * Vector3(px + s * 0.09, y + rail_h - 0.27, front), 0.07, 0.09, 0.02, 6,
					xf.basis * Basis(Vector3.BACK, PI * 0.5 * (1.0 - s)), -PI * 0.5, PI * 0.5, ["front", "back"])
	for s: float in [-1.0, 1.0]:
		var ex := x + s * w * 0.5
		_box(c.u, xf, Vector3(ex, y + rail_h * 0.5, front), Vector3(0.04, rail_h, 0.04))
		_box(c.u, xf, Vector3(ex, y + rail_h, z0 + depth * 0.5), Vector3(0.04, 0.04, depth))
		for k in 3:
			_box(c.u, xf, Vector3(ex, y + rail_h * 0.5, z0 + depth * (k + 0.5) / 3.0), Vector3(0.018, rail_h, 0.018),
					Basis(), [RoomMesh.UP, RoomMesh.DOWN])
	if rug != null:
		_rug(c, xf, Vector3(x + (c.rng.randf() - 0.5) * maxf(w - 1.4, 0.0), y + rail_h, front + 0.03), rug as Array)
	for k in pots:
		var px := x - w * 0.5 + 0.3 + (w - 0.6) * (k + 0.5) / pots
		_geranium(c, xf, Vector3(px, y, z0 + depth * 0.45), 1.0, flower)


## A rug over a balcony's rail: hung from the rail (`at`: the rail's top, local), down its face in stripes of colour,
## a fringe at the bottom.
static func _rug(c: Object, xf: Transform3D, at: Vector3, colours: Array) -> void:
	c.u.surface(c.soft("cloth"))
	var w := 1.1
	var drop := 0.85
	var bands := 9
	for k in bands:
		var y1 := at.y - drop * k / bands
		var y2 := at.y - drop * (k + 1) / bands
		var col: Color = colours[[0, 1, 0, 2, 1, 2, 0, 1, 0][k] % colours.size()]
		_tint(c.u, col)
		var z := at.z + 0.02 + 0.015 * sin(k * 1.3)
		_face(c.u, xf, [Vector3(at.x - w * 0.5, y2, z), Vector3(at.x + w * 0.5, y2, z), Vector3(at.x + w * 0.5, y1, z),
				Vector3(at.x - w * 0.5, y1, z)], Vector3.BACK)
	_tint(c.u, colours[0])
	_face(c.u, xf, [Vector3(at.x - w * 0.5, at.y + 0.03, at.z - 0.06), Vector3(at.x + w * 0.5, at.y + 0.03, at.z - 0.06),
			Vector3(at.x + w * 0.5, at.y + 0.03, at.z + 0.03), Vector3(at.x - w * 0.5, at.y + 0.03, at.z + 0.03)],
			Vector3.UP)
	_tint(c.u, Color(0.85, 0.8, 0.66))
	for k in 12:
		var fx := at.x - w * 0.5 + w * (k + 0.5) / 12.0
		_face(c.u, xf, [Vector3(fx - 0.02, at.y - drop - 0.08, at.z + 0.03), Vector3(fx + 0.02, at.y - drop - 0.08,
				at.z + 0.03), Vector3(fx + 0.02, at.y - drop, at.z + 0.03), Vector3(fx - 0.02, at.y - drop, at.z + 0.03)],
				Vector3.BACK)


## An urn on a little plinth (soft stone).
static func _urn(c: Object, xf: Transform3D, at: Vector3, k: float, colour: Color) -> void:
	c.u.surface(c.soft("stone"))
	_tint(c.u, colour)
	_box(c.u, xf, at + Vector3(0, 0.07 * k, 0), Vector3(0.3, 0.14, 0.3) * k, Basis(), [RoomMesh.DOWN])
	var prof: Array = []
	for p: Vector2 in [Vector2(0.1, 0.0), Vector2(0.12, 0.03), Vector2(0.05, 0.1), Vector2(0.07, 0.15),
			Vector2(0.17, 0.28), Vector2(0.16, 0.38), Vector2(0.09, 0.47), Vector2(0.085, 0.5), Vector2(0.13, 0.53),
			Vector2(0.11, 0.56), Vector2(0.0, 0.55)]:
		prof.append(p * k)
	_lathe(c.u, xf, prof, at + Vector3(0, 0.14 * k, 0), 10)


## A lion lying with its head up, as the stone lions at a palace's steps (soft stone), modelled in ellipsoids: a long
## body with the ribs' fall behind the chest, the haunches of the folded hind legs, the forelegs stretched out with
## their paws, a full mane in locks round the face and down the chest, the face (brow, eyes, a broad nose, the muzzle),
## small ears in the mane, the tail round the haunch with its tuft. (2026-11-08: the first lion, of rounded boxes, read
## as a block from the seats.) About 0.95 m long and 0.6 high at k 1.
static func _lion(c: Object, xf: Transform3D, at: Vector3, k: float, colour: Color) -> void:
	c.u.surface(c.soft("stone"))
	var lx := xf * Transform3D(Basis().scaled(Vector3.ONE * k), at)
	_tint(c.u, colour)
	# Body: the chest, the barrel, the loins; the haunches over the folded hind legs; the hind paws by the belly.
	_blob(c.u, lx, Vector3(0, 0.21, 0.16), Vector3(0.165, 0.2, 0.17))
	_blob(c.u, lx, Vector3(0, 0.19, -0.06), Vector3(0.155, 0.165, 0.27))
	_blob(c.u, lx, Vector3(0, 0.17, -0.27), Vector3(0.15, 0.15, 0.15))
	for s: float in [-1.0, 1.0]:
		_blob(c.u, lx, Vector3(s * 0.1, 0.16, -0.25), Vector3(0.085, 0.14, 0.17), Basis(Vector3.RIGHT, 0.25))
		_blob(c.u, lx, Vector3(s * 0.15, 0.035, -0.08), Vector3(0.05, 0.035, 0.11))
		# The forelegs stretched out, the paws on the plinth, a hint of toes.
		_blob(c.u, lx, Vector3(s * 0.095, 0.075, 0.3), Vector3(0.055, 0.07, 0.17), Basis(Vector3.RIGHT, 0.12))
		_blob(c.u, lx, Vector3(s * 0.095, 0.035, 0.46), Vector3(0.068, 0.038, 0.075))
		for toe in 3:
			_blob(c.u, lx, Vector3(s * 0.095 + (toe - 1) * 0.03, 0.03, 0.525), Vector3(0.017, 0.02, 0.02), Basis(), 5, 3)
	# The mane: a ruff round the neck, locks in a ring round the face, locks down the chest.
	_tint(c.u, colour * 0.93)
	_blob(c.u, lx, Vector3(0, 0.4, 0.22), Vector3(0.2, 0.22, 0.15), Basis(Vector3.RIGHT, -0.3))
	for i in 13:
		var a := -PI * 0.08 + TAU * i / 13.0
		var lock := Basis(Vector3.BACK, a - PI * 0.5) * Basis(Vector3.RIGHT, -0.35)
		_blob(c.u, lx, Vector3(cos(a) * 0.15, 0.44 + sin(a) * 0.15, 0.3), Vector3(0.045, 0.085, 0.045), lock, 6, 4)
	for i in 4:
		_blob(c.u, lx, Vector3((i % 2 - 0.5) * 0.08, 0.31 - i * 0.045, 0.31 - i * 0.012), Vector3(0.05, 0.07, 0.04),
				Basis(Vector3.RIGHT, 0.4), 6, 4)
	# The face: the head, the brow, the muzzle with its pads, the broad nose, the jaw; the ears in the mane.
	_tint(c.u, colour)
	_blob(c.u, lx, Vector3(0, 0.45, 0.34), Vector3(0.105, 0.115, 0.1))
	_blob(c.u, lx, Vector3(0, 0.5, 0.41), Vector3(0.085, 0.032, 0.04), Basis(), 7, 4)
	_blob(c.u, lx, Vector3(0, 0.41, 0.43), Vector3(0.07, 0.06, 0.07))
	for s: float in [-1.0, 1.0]:
		_blob(c.u, lx, Vector3(s * 0.032, 0.4, 0.48), Vector3(0.035, 0.03, 0.03), Basis(), 6, 4)
		_blob(c.u, lx, Vector3(s * 0.085, 0.575, 0.3), Vector3(0.035, 0.035, 0.022), Basis(), 6, 4)
	_blob(c.u, lx, Vector3(0, 0.36, 0.42), Vector3(0.05, 0.03, 0.045), Basis(), 6, 4)
	_tint(c.u, colour * 0.55)
	_blob(c.u, lx, Vector3(0, 0.44, 0.495), Vector3(0.03, 0.022, 0.022), Basis(), 6, 4)
	_tint(c.u, colour * 0.35)
	for s: float in [-1.0, 1.0]:
		_blob(c.u, lx, Vector3(s * 0.045, 0.475, 0.432), Vector3(0.016, 0.011, 0.01), Basis(), 5, 3)
	# The tail: from the rump round the haunch along the plinth, its tuft by the hind paw.
	_tint(c.u, colour)
	var tail: Array[Vector3] = [Vector3(0.03, 0.1, -0.41), Vector3(0.14, 0.04, -0.4), Vector3(0.21, 0.03, -0.26),
			Vector3(0.22, 0.03, -0.1)]
	for i in tail.size() - 1:
		Shapes.beam(c.u, lx * tail[i], lx * tail[i + 1], Vector2(0.032, 0.032) * k)
	_blob(c.u, lx, Vector3(0.22, 0.04, -0.05), Vector3(0.035, 0.032, 0.06), Basis(), 6, 4)


## An ellipsoid of radii r (in xf's frame, turned by rot) at centre: `sides` round, `rings` from pole to pole; its
## normals the ellipsoid's own (the sphere's scaled by 1 / r), so the light falls on it truly.
static func _blob(b: RoomMesh, xf: Transform3D, centre: Vector3, r: Vector3, rot := Basis(), sides := 8,
		rings := 6) -> void:
	var m := xf.basis * rot * Basis.from_scale(r)
	var nm := m.inverse().transposed()
	var o := xf * centre
	var prev := PackedVector3Array()
	for i in rings + 1:
		var lat := PI * (float(i) / rings - 0.5)
		# A strip takes one normal a column for both its rows: the band's middle.
		var mid := lat - PI * 0.5 / rings
		var ring := PackedVector3Array()
		var rn := PackedVector3Array()
		for k in sides + 1:
			var t := TAU * float(k % sides) / sides
			ring.append(o + m * Vector3(cos(lat) * sin(t), sin(lat), cos(lat) * cos(t)))
			rn.append((nm * Vector3(cos(mid) * sin(t), sin(mid), cos(mid) * cos(t))).normalized())
		if i > 0:
			b.strip(prev, ring, rn)
		prev = ring


# --- The house ------------------------------------------------------------------------------------------------------------

## A house front along a wall: its wash of lime over plaster from below the floor to the eave, a stone socle that
## follows the stepped floor, string courses, windows by storey (lit rooms behind, some dark), shutters, and its
## features (FEATURES): a long balcony or balconettes, a top-storey loggia, a belvedere tower, a pergola roof terrace
## or a gable, a Moorish oriel, the arch round an exit or a door, a niche with an urn or a lion, a wall fountain,
## lanterns, a bougainvillea, rugs, geraniums, ground-floor grilles; then its eave: a cornice, rafters under the
## overhang, a tile roof with its row of round tile ends and a ridge.
static func _house(c: Object, xf: Transform3D, size: Vector3, e: Dictionary) -> void:
	var w := size.x
	var eave := size.y - xf.origin.y
	var z0 := size.z
	var f: Array = e.get("features", [])
	var rng := RandomNumberGenerator.new()
	rng.seed = int(e.get("seed", 7)) * 7919 + 13
	var wash := _colour(e, "colour", Color(0.85, 0.66, 0.46))
	var shutter := _colour(e, "accent", Color(0.24, 0.38, 0.32))
	var stone := STONE.lerp(wash, 0.15)
	var left := -w * 0.5
	# The floor along its foot: the façade starts below the lowest, the ground storey's height above the highest.
	var g_lo := INF
	var g_hi := -INF
	var samples: Array[float] = []
	for k in 13:
		var g := _ground(c, xf, left + w * k / 12.0, z0 + 0.3)
		samples.append(g)
		g_lo = minf(g_lo, g)
		g_hi = maxf(g_hi, g)
	var base := g_lo - 0.6
	var storey0 := g_hi + 3.3
	var upper := maxi(int(round((eave - 0.7 - storey0) / 3.0)), 1)
	var storey_h := (eave - 0.7 - storey0) / upper
	var gable := "gable" in f
	var pergola := "pergola" in f
	var loggia := "loggia" in f
	var bays := maxi(int(round(w / 1.75)), 1)
	var bay_w := w / bays
	var holes: Array = []
	# Which window is which: lit rooms of several kinds, a few dark; each its own moment of going out.
	var dark_all := "dark" in f
	var moment := func() -> float: return rng.randf_range(0.04, 0.96)
	var kind := func() -> int: return -1 if dark_all or rng.randf() < 0.18 else rng.randi_range(0, 4)
	var win_opts := {"wash": wash, "stone": stone}
	# --- The ground storey.
	var has_exit := "exit" in f
	var ground_mid := "fountain" in f or "niche" in f or "lion_niche" in f or "door" in f or has_exit
	for b in bays:
		var bx := left + bay_w * (b + 0.5)
		var gy := _ground(c, xf, bx, z0 + 0.3)
		var middle := b == bays / 2
		if ground_mid and (middle or has_exit):
			continue
		if "arcade" in f:
			continue
		var o := win_opts.duplicate()
		o.merge({"arched": rng.randf() < 0.5, "lit": kind.call(), "moment": moment.call(), "grille": true,
				"shutters": null, "surround": false})
		holes.append(_window(c, xf, bx, gy + 1.05, minf(0.85, bay_w - 0.6), 1.25, z0, left, o))
	# --- The upper storeys.
	for s in upper:
		var y := storey0 + storey_h * s
		var top_storey := s == upper - 1
		if top_storey and loggia:
			_loggia(c, xf, y, storey_h, w, z0, wash, stone, rng)
			holes.append(Rect2(left, y, w, storey_h))
			continue
		var piano := s == 0
		var arched := piano and rng.randf() < 0.6
		for b in bays:
			var bx := left + bay_w * (b + 0.5)
			var ww := minf(0.95 if piano else 0.8, bay_w - 0.75)
			var hh := maxf(minf(storey_h - 1.2, 1.75 if piano else 1.35), 0.7)
			if arched:
				hh = maxf(hh - ww * 0.5, 0.6)
			if "oriel" in f and piano and b == bays / 2:
				continue
			if "booth" in f and piano and absf(bx - _lens_local(c, xf).x) < 2.3:
				continue
			var o := win_opts.duplicate()
			o.merge({"arched": arched, "lit": kind.call(), "moment": moment.call(),
					"shutters": shutter * rng.randf_range(0.85, 1.1)})
			holes.append(_window(c, xf, bx, y + 0.85, ww, hh, z0, left, o))
	if "arcade" in f:
		holes.append(Rect2(left, base, w, storey0 - base))
	# --- The façade: the wash round the holes, from below the floor to the eave (or the gable's foot). The holes in
	# the wall's own coordinates: along from its left end, up from its foot.
	var wall_top := eave
	var wall_holes: Array = []
	for hole: Rect2 in holes:
		wall_holes.append(Rect2(hole.position.x - left, hole.position.y - base, hole.size.x, hole.size.y))
	c.s.surface(c.tinted("plaster", "lime_wash"))
	_tint(c.s, wash)
	Shapes.wall(c.s, xf * Vector3(left, base, z0), xf.basis.x, (xf.basis.z).normalized(), w, wall_top - base,
			wall_holes)
	# Its ends, back to the wall behind (they show where a neighbour stands further back or lower).
	for sd: float in [-1.0, 1.0]:
		_face(c.s, xf, [Vector3(sd * w * 0.5, base, z0), Vector3(sd * w * 0.5, base, -0.3),
				Vector3(sd * w * 0.5, wall_top, -0.3), Vector3(sd * w * 0.5, wall_top, z0)], Vector3(sd, 0, 0))
	if gable:
		_tint(c.s, wash)
		var rise := w * 0.5 * tan(deg_to_rad(24.0))
		_face(c.s, xf, [Vector3(left, wall_top, z0), Vector3(-left, wall_top, z0), Vector3(0, wall_top + rise, z0)],
				Vector3.BACK)
	# The socle: dressed stone along the foot, following the floor's steps.
	c.s.surface(c.tinted("stone", "ashlar"))
	_tint(c.s, stone * 0.92)
	for k in 12:
		var x0 := left + w * k / 12.0
		var x1 := left + w * (k + 1) / 12.0
		var g := minf(samples[k], samples[k + 1])
		_box(c.s, xf, Vector3((x0 + x1) * 0.5, (base + g + 0.55) * 0.5, z0 + 0.04), Vector3(x1 - x0 + 0.002,
				g + 0.55 - base, 0.08), Basis(), [RoomMesh.FRONT, RoomMesh.DOWN])
	# String courses: a band of stone over the ground storey and under each upper storey's sills.
	c.u.surface(c.soft("stone"))
	_tint(c.u, stone)
	_box(c.u, xf, Vector3(0, storey0 - 0.05, z0 + 0.05), Vector3(w, 0.16, 0.1), Basis(), [RoomMesh.FRONT])
	_box(c.u, xf, Vector3(0, storey0 + 0.06, z0 + 0.08), Vector3(w, 0.06, 0.16), Basis(), [RoomMesh.FRONT])
	# Quoins at the corners: stones in turn long and short.
	for sd: float in [-1.0, 1.0]:
		var qy := g_hi + 0.55
		var qk := 0
		while qy < wall_top - 0.4:
			var long_one := qk % 2 == 0
			var qw := 0.42 if long_one else 0.26
			_box(c.u, xf, Vector3(sd * (w * 0.5 - qw * 0.5), qy + 0.15, z0 + 0.025), Vector3(qw, 0.28, 0.05), Basis(),
					[RoomMesh.FRONT])
			qy += 0.32
			qk += 1
	# --- The features.
	var mid_x := left + bay_w * (bays / 2 + 0.5)
	var mid_g := _ground(c, xf, mid_x, z0 + 0.3)
	if has_exit:
		_exit_arch(c, xf, 0.0, _ground(c, xf, 0.0, 0.4), z0, wash)
	if "door" in f:
		_door(c, xf, mid_x, mid_g, z0, stone)
	if "fountain" in f:
		_fountain(c, xf, mid_x, mid_g, z0, stone)
	if "niche" in f or "lion_niche" in f:
		_niche(c, xf, mid_x, mid_g, z0, wash, stone, "lion_niche" in f)
	if "arcade" in f:
		_arcade(c, xf, w, g_hi, storey0, z0, wash, stone, rng)
	var flower := GERANIUM if rng.randf() < 0.7 else Color(0.92, 0.42, 0.62)
	if "balcony" in f:
		var rug: Variant = null
		if "rug" in f:
			rug = [[Color(0.62, 0.12, 0.1), Color(0.86, 0.66, 0.3), Color(0.15, 0.22, 0.42)],
					[Color(0.2, 0.36, 0.42), Color(0.85, 0.78, 0.6), Color(0.66, 0.2, 0.14)]][rng.randi() % 2]
		_balcony(c, xf, 0.0, storey0 + 0.75, w - 0.5, 0.8, z0, stone, rug, maxi(bays - 1, 2), flower)
	if "balconettes" in f:
		for b in bays:
			var bx := left + bay_w * (b + 0.5)
			if "oriel" in f and b == bays / 2:
				continue
			_balcony(c, xf, bx, storey0 + 0.75, minf(1.35, bay_w - 0.2), 0.42, z0, stone, null, 1 if b % 2 == 0 else 0,
					flower)
	if "oriel" in f:
		_oriel(c, xf, mid_x, storey0 + 0.35, minf(1.7, bay_w + 0.2), storey_h - 0.1, z0, shutter, rng)
	if "geraniums" in f:
		for b in bays:
			if rng.randf() < 0.6:
				_geranium(c, xf, Vector3(left + bay_w * (b + 0.5) + rng.randf_range(-0.2, 0.2), storey0 + 0.85,
						z0 + 0.12), 0.85, flower)
	if "lanterns" in f:
		var lx: Array = []
		if bays >= 2:
			for b in range(1, bays):
				lx.append(left + bay_w * b)
		else:
			lx.append(0.0)
		if ground_mid:
			lx = [-w * 0.32, w * 0.32] if w > 3.0 else [0.0]
		if has_exit:
			lx = [0.0]
		for x: float in lx:
			var gy := _ground(c, xf, x, z0 + 0.3)
			var hy := gy + (4.25 if has_exit else 2.75)
			_lantern(c, xf, Vector3(x, hy, z0), 1.0)
	if "vines" in f:
		var vx := left + 0.45 if rng.randf() < 0.5 else w * 0.5 - 0.45
		_vine(c, xf, vx, _ground(c, xf, vx, z0 + 0.3), storey0 + storey_h * minf(upper, 1.0) + 0.6, minf(w * 0.35, 1.6),
				z0)
	if "tower" in f:
		_tower(c, xf, w, eave, z0, wash, stone, shutter, rng)
	if "booth" in f:
		_booth_ports(c, xf, z0, wash, stone)
	# --- The top: a pergola terrace, or the eave and its roof.
	if pergola:
		_pergola(c, xf, w, eave, z0, stone, rng)
	elif gable:
		_gable_roof(c, xf, w, eave, z0, stone)
	else:
		_eave(c, xf, w, eave, z0, stone, rng)
	_solid(c, xf, Vector3(0, (base + eave) * 0.5, z0 * 0.5 - 0.15), Vector3(w, eave - base, maxf(z0, 0.0) + 0.3))


## The eave: a moulded cornice, the overhang's soffit with rafter ends under it, the roof's slope of tiles back to a
## ridge, a row of round tile ends along its edge, and the ridge's capping.
static func _eave(c: Object, xf: Transform3D, w: float, eave: float, z0: float, stone: Color,
		rng: RandomNumberGenerator) -> void:
	var over := 0.7
	var y := eave
	c.u.surface(c.soft("stone"))
	_tint(c.u, stone)
	_box(c.u, xf, Vector3(0, y - 0.32, z0 + 0.05), Vector3(w, 0.14, 0.1), Basis(), [RoomMesh.FRONT])
	_box(c.u, xf, Vector3(0, y - 0.18, z0 + 0.1), Vector3(w + 0.04, 0.12, 0.2), Basis(), [RoomMesh.FRONT])
	# The soffit and the rafters' ends.
	c.s.surface(c.tinted("wood"))
	_tint(c.s, SOFFIT)
	_face(c.s, xf, [Vector3(-w * 0.5, y, z0), Vector3(w * 0.5, y, z0), Vector3(w * 0.5, y, z0 + over),
			Vector3(-w * 0.5, y, z0 + over)], Vector3.DOWN)
	c.u.surface(c.soft("wood"))
	_tint(c.u, SOFFIT * 0.8)
	var n := maxi(int(w / 0.42), 2)
	for k in n:
		var rx := -w * 0.5 + w * (k + 0.5) / n
		_box(c.u, xf, Vector3(rx, y - 0.05, z0 + over * 0.5 + 0.08), Vector3(0.08, 0.1, over - 0.04), Basis(),
				[RoomMesh.UP, RoomMesh.FRONT])
	# The fascia under the tiles' edge.
	_tint(c.u, SOFFIT * 0.7)
	_box(c.u, xf, Vector3(0, y + 0.06, z0 + over + 0.02), Vector3(w + 0.06, 0.12, 0.04))
	# The slope: tiles back and up to the ridge (behind the wall: it shows against the sky).
	var pitch := deg_to_rad(24.0)
	var back := -2.4
	var y_edge := y + 0.14
	var ridge := y_edge + (z0 + over - back) * tan(pitch)
	c.s.surface(c.tinted("roof", "roof_tiles"))
	_tint(c.s, Color(0.95, 0.9, 0.86) * rng.randf_range(0.88, 1.05))
	_face(c.s, xf, [Vector3(-w * 0.5 - 0.06, y_edge, z0 + over + 0.04), Vector3(w * 0.5 + 0.06, y_edge, z0 + over + 0.04),
			Vector3(w * 0.5 + 0.06, ridge, back), Vector3(-w * 0.5 - 0.06, ridge, back)],
			Vector3(0, cos(pitch), sin(pitch)))
	# The ends of the roof: closed, in the wash's shadow.
	c.s.surface(c.tinted("plaster", "lime_wash"))
	_tint(c.s, stone * 0.55)
	for sd: float in [-1.0, 1.0]:
		_face(c.s, xf, [Vector3(sd * (w * 0.5 + 0.06), y, z0 + over), Vector3(sd * (w * 0.5 + 0.06), y_edge,
				z0 + over + 0.04), Vector3(sd * (w * 0.5 + 0.06), ridge, back), Vector3(sd * (w * 0.5 + 0.06), y, back)],
				Vector3(sd, 0, 0))
	# The tiles' round ends along the edge, and the ridge's capping.
	c.u.surface(c.soft("stone"))
	var tiles := maxi(int(w / 0.2), 2)
	for k in tiles:
		_tint(c.u, TERRACOTTA * rng.randf_range(0.82, 1.12))
		var tx := -w * 0.5 + w * (k + 0.5) / tiles
		Shapes.arch(c.u, xf * Vector3(tx, y_edge + 0.01, z0 + over + 0.06), 0.065, 0.085, 0.16, 4, xf.basis, 0.0, PI,
				["front", "outer"])
	_tint(c.u, TERRACOTTA * 0.85)
	_beam(c.u, xf, Vector3(-w * 0.5 - 0.06, ridge + 0.05, back), Vector3(w * 0.5 + 0.06, ridge + 0.05, back),
			Vector2(0.16, 0.12))


## A gable facing the room: the wash's triangle (drawn with the façade), raking cornices up to the apex, round tile ends
## along each rake, the roof's slopes back from them.
static func _gable_roof(c: Object, xf: Transform3D, w: float, eave: float, z0: float, stone: Color) -> void:
	var pitch := deg_to_rad(24.0)
	var rise := w * 0.5 * tan(pitch)
	var apex := Vector3(0, eave + rise, z0)
	c.u.surface(c.soft("stone"))
	_tint(c.u, stone)
	_box(c.u, xf, Vector3(0, eave - 0.06, z0 + 0.08), Vector3(w + 0.1, 0.12, 0.16), Basis(), [RoomMesh.FRONT])
	for sd: float in [-1.0, 1.0]:
		var foot := Vector3(sd * (w * 0.5 + 0.12), eave - 0.02, z0 + 0.1)
		_beam(c.u, xf, foot, apex + Vector3(0, 0.12, 0.1), Vector2(0.2, 0.14))
	# A round window in the gable, dark.
	c.u.surface(c.soft("stone"))
	Shapes.arch(c.u, xf * Vector3(0, eave + rise * 0.42, z0 + 0.03), 0.2, 0.28, 0.06, 12, xf.basis, 0.0, TAU,
			["front", "inner", "outer"])
	c.windows.surface(c.kit.window_material())
	c.windows.colour = Color(0.4 / 4.0, 0.4 / 4.0, 0.99, 0.5)
	var disc: Array = []
	for k in 12:
		var t := -PI * 0.5 - PI * 0.25 + TAU * k / 12.0
		disc.append(Vector3(cos(t) * 0.2, eave + rise * 0.42 + sin(t) * 0.2, z0 + 0.0))
	_face(c.windows, xf, disc, Vector3.BACK)
	# The slopes behind the rakes.
	var back := -2.4
	c.s.surface(c.tinted("roof", "roof_tiles"))
	_tint(c.s, Color(0.92, 0.88, 0.84))
	for sd: float in [-1.0, 1.0]:
		var foot := Vector3(sd * (w * 0.5 + 0.2), eave + 0.06, z0 + 0.22)
		var top := apex + Vector3(0, 0.2, 0.22)
		_face(c.s, xf, [foot, top, Vector3(top.x, top.y, back), Vector3(foot.x, foot.y, back)],
				Vector3(sd * sin(pitch), cos(pitch), 0))
	c.u.surface(c.soft("stone"))
	for sd: float in [-1.0, 1.0]:
		var n := int(w * 0.5 / cos(pitch) / 0.22)
		for k in n:
			var t := (k + 0.5) / n
			_tint(c.u, TERRACOTTA * (0.85 + 0.25 * fposmod(k * 0.37, 1.0)))
			var p := Vector3(sd * (w * 0.5 + 0.2) * (1.0 - t), eave + 0.1 + rise * t + 0.12, z0 + 0.3)
			Shapes.arch(c.u, xf * p, 0.06, 0.08, 0.14, 4, xf.basis * Basis(Vector3.BACK, sd * pitch), 0.0, PI,
					["front", "outer"])


## A pergola on a roof terrace: a balustrade along the eave, timber posts and beams over it, a vine on top.
static func _pergola(c: Object, xf: Transform3D, w: float, eave: float, z0: float, stone: Color,
		rng: RandomNumberGenerator) -> void:
	c.u.surface(c.soft("stone"))
	_tint(c.u, stone)
	_box(c.u, xf, Vector3(0, eave - 0.1, z0 + 0.1), Vector3(w + 0.1, 0.2, 0.3), Basis(), [RoomMesh.FRONT])
	_balustrade(c, xf, -w * 0.5, w * 0.5, eave, z0 + 0.1, 0.85, stone)
	c.u.surface(c.soft("wood"))
	_tint(c.u, Color(0.34, 0.24, 0.16))
	var posts := maxi(int(w / 1.6), 1) + 1
	var ph := 2.3
	for k in posts:
		var px := -w * 0.5 + 0.2 + (w - 0.4) * k / (posts - 1)
		for pz: float in [z0 - 0.1, -1.8]:
			_box(c.u, xf, Vector3(px, eave + ph * 0.5, pz), Vector3(0.12, ph, 0.12))
		_box(c.u, xf, Vector3(px, eave + ph + 0.06, (z0 - 1.8) * 0.5), Vector3(0.1, 0.14, z0 + 2.3))
	for pz: float in [z0 - 0.1, -1.8]:
		_box(c.u, xf, Vector3(0, eave + ph - 0.06, pz), Vector3(w, 0.14, 0.1))
	var slats := int(w / 0.4)
	for k in slats:
		_box(c.u, xf, Vector3(-w * 0.5 + w * (k + 0.5) / slats, eave + ph + 0.16, (z0 - 1.8) * 0.5), Vector3(0.05, 0.06,
				z0 + 2.4))
	# A vine over the top and down one post, in leaf and in flower.
	c.u.surface(c.soft("leaves"))
	for i in int(w * 22):
		var bloom := rng.randf() < 0.3
		_tint(c.u, Color(0.62, 0.22, 0.5) if bloom else Color(0.17, 0.3, 0.1) * rng.randf_range(0.8, 1.2))
		var at := Vector3(rng.randf_range(-w * 0.5, w * 0.5), eave + ph + 0.2 + rng.randf_range(-0.15, 0.25),
				rng.randf_range(-1.9, z0 + 0.1))
		if rng.randf() < 0.18:
			at = Vector3(-w * 0.5 + 0.2 + rng.randf_range(-0.2, 0.2), eave + rng.randf_range(0.3, ph), z0 - 0.05)
		var len := rng.randf_range(0.1, 0.18)
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.8, 0.6), rng.randf_range(-1, 1)).normalized()
		var across := dir.cross(Vector3.UP).normalized() * len * 0.5
		if across.length() < 0.001:
			across = Vector3.RIGHT * len * 0.5
		Shapes.leaf(c.u, xf * at, xf.basis * (dir * len), xf.basis * across, (xf.basis * dir.cross(across)).normalized())
	_lantern(c, xf, Vector3(w * 0.25, eave + ph - 0.05 + 0.5, z0 - 0.6), 0.5)


## A stone balustrade from x0 to x1 at y (its foot), along local z = z: a base, turned balusters, a rail, piers at
## the ends.
static func _balustrade(c: Object, xf: Transform3D, x0: float, x1: float, y: float, z: float, h: float,
		stone: Color) -> void:
	c.u.surface(c.soft("stone"))
	_tint(c.u, stone)
	var w := x1 - x0
	_box(c.u, xf, Vector3((x0 + x1) * 0.5, y + 0.06, z), Vector3(w, 0.12, 0.26))
	_box(c.u, xf, Vector3((x0 + x1) * 0.5, y + h - 0.06, z), Vector3(w, 0.12, 0.3))
	var n := maxi(int(w / 0.24), 2)
	for k in n:
		var bx := x0 + w * (k + 0.5) / n
		_lathe(c.u, xf, [Vector2(0.06, 0.0), Vector2(0.09, 0.14), Vector2(0.05, 0.32), Vector2(0.04, 0.5),
				Vector2(0.06, h - 0.24)], Vector3(bx, y + 0.12, z), 6)
	for x: float in [x0, x1]:
		_box(c.u, xf, Vector3(x, y + h * 0.5, z), Vector3(0.3, h, 0.32))


## A loggia across the top storey: arches on piers, the room behind dark and warm, a lantern hanging in it, a low
## balustrade in each arch.
static func _loggia(c: Object, xf: Transform3D, y: float, h: float, w: float, z0: float, wash: Color, stone: Color,
		rng: RandomNumberGenerator) -> void:
	var bays := maxi(int(round(w / 1.6)), 2)
	var bay := w / bays
	var depth := 0.9
	var pier := 0.32
	var r := (bay - pier) * 0.5
	var spring := y + h - r - 0.35
	var zb := z0 - depth
	# The wall round the arches (the wash), the arches' soffits and the piers' sides (a little darker).
	c.s.surface(c.tinted("plaster", "lime_wash"))
	for b in bays:
		var bx := -w * 0.5 + bay * (b + 0.5)
		_tint(c.s, wash)
		for s: float in [-1.0, 1.0]:
			var pts: Array = [Vector3(bx + s * bay * 0.5, y + h, z0), Vector3(bx + s * bay * 0.5, y, z0),
					Vector3(bx + s * r, y, z0)]
			for k in 9:
				var t := PI * 0.5 * k / 8.0 if s > 0.0 else PI - PI * 0.5 * k / 8.0
				pts.append(Vector3(bx + cos(t) * r, spring + sin(t) * r, z0))
			pts.append(Vector3(bx, y + h, z0))
			_face(c.s, xf, [pts[0], pts[1], pts[2]], Vector3.BACK)
			var fan: Array = [pts[0]]
			fan.append_array(pts.slice(2))
			_face(c.s, xf, fan, Vector3.BACK)
		_tint(c.s, wash * 0.8)
		Shapes.arch(c.s, xf * Vector3(bx, spring, z0 - depth * 0.5), r, r, depth, 8, xf.basis, 0.0, PI, ["inner"])
		for s: float in [-1.0, 1.0]:
			_face(c.s, xf, [Vector3(bx + s * r, y, z0), Vector3(bx + s * r, y, zb), Vector3(bx + s * r, spring, zb),
					Vector3(bx + s * r, spring, z0)], Vector3(-s, 0, 0))
		# Inside: the back wall dark and warm, the floor.
		_tint(c.s, wash * 0.32)
		_face(c.s, xf, [Vector3(bx - r, y, zb), Vector3(bx + r, y, zb), Vector3(bx + r, y + h - 0.2, zb),
				Vector3(bx - r, y + h - 0.2, zb)], Vector3.BACK)
		_tint(c.s, wash * 0.45)
		_face(c.s, xf, [Vector3(bx - r, y, z0), Vector3(bx + r, y, z0), Vector3(bx + r, y, zb), Vector3(bx - r, y, zb)],
				Vector3.UP)
		_face(c.s, xf, [Vector3(bx - r, y + h - 0.2, zb), Vector3(bx + r, y + h - 0.2, zb),
				Vector3(bx + r, y + h - 0.2, z0), Vector3(bx - r, y + h - 0.2, z0)], Vector3.DOWN)
		# A door at the back of the middle bay, its room lit.
		if b == bays / 2:
			c.windows.surface(c.kit.window_material())
			c.windows.colour = Color(0.7 / 4.0, 1.8 / 4.0, (rng.randi_range(0, 2) + 0.5) / 8.0, rng.randf_range(0.3, 0.9))
			_face(c.windows, xf, [Vector3(bx - 0.35, y + 0.02, zb + 0.01), Vector3(bx + 0.35, y + 0.02, zb + 0.01),
					Vector3(bx + 0.35, y + 1.82, zb + 0.01), Vector3(bx - 0.35, y + 1.82, zb + 0.01)], Vector3.BACK)
		_balustrade(c, xf, bx - r, bx + r, y, z0 - 0.1, 0.8, stone)
	c.u.surface(c.soft("stone"))
	_tint(c.u, stone)
	for b in bays + 1:
		var px := -w * 0.5 + bay * b
		_box(c.u, xf, Vector3(px, spring - 0.06, z0 + 0.03), Vector3(pier + 0.08, 0.12, 0.08), Basis(), [RoomMesh.FRONT])
	_lantern(c, xf, Vector3(-w * 0.5 + bay * (bays / 2 + 0.5), spring + r - 0.1, zb), 0.6)


## A belvedere tower over one end of the house: its shaft up from the eave, an open storey of arches with the dark
## room inside, a cornice, a pyramid roof of tiles with a finial.
static func _tower(c: Object, xf: Transform3D, w: float, eave: float, z0: float, wash: Color, stone: Color,
		shutter: Color, rng: RandomNumberGenerator) -> void:
	var tw := minf(2.5, w * 0.5)
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	var cx := side * (w * 0.5 - tw * 0.5)
	var front := z0 + 0.12
	var back := front - tw
	var foot := eave - 0.6
	var floor_y := eave + 1.3
	var top := floor_y + 2.3
	c.s.surface(c.tinted("plaster", "lime_wash"))
	_tint(c.s, wash * 1.04)
	for s: float in [-1.0, 1.0]:
		_face(c.s, xf, [Vector3(cx + s * tw * 0.5, foot, front), Vector3(cx + s * tw * 0.5, foot, back),
				Vector3(cx + s * tw * 0.5, floor_y, back), Vector3(cx + s * tw * 0.5, floor_y, front)], Vector3(s, 0, 0))
	_face(c.s, xf, [Vector3(cx - tw * 0.5, foot, front), Vector3(cx + tw * 0.5, foot, front),
			Vector3(cx + tw * 0.5, floor_y, front), Vector3(cx - tw * 0.5, floor_y, front)], Vector3.BACK)
	# The open storey: corner piers, an arch on each face, the dark room behind.
	var r := tw * 0.5 - 0.32
	var spring := top - r - 0.25
	for face: int in 3:
		var basis := Basis(Vector3.UP, [0.0, PI * 0.5, -PI * 0.5][face])
		var centre := Vector3(cx, 0, (front + back) * 0.5)
		var fxf := xf * Transform3D(Basis(), centre) * Transform3D(basis, Vector3(0, 0, tw * 0.5))
		_tint(c.s, wash * 1.04)
		for s: float in [-1.0, 1.0]:
			var pts: Array = [Vector3(s * tw * 0.5, top, 0), Vector3(s * tw * 0.5, floor_y, 0), Vector3(s * r, floor_y, 0)]
			for k in 9:
				var t := PI * 0.5 * k / 8.0 if s > 0.0 else PI - PI * 0.5 * k / 8.0
				pts.append(Vector3(cos(t) * r, spring + sin(t) * r, 0))
			pts.append(Vector3(0, top, 0))
			_face(c.s, fxf, [pts[0], pts[1], pts[2]], Vector3.BACK)
			var fan: Array = [pts[0]]
			fan.append_array(pts.slice(2))
			_face(c.s, fxf, fan, Vector3.BACK)
		_tint(c.s, wash * 0.75)
		Shapes.arch(c.s, fxf * Vector3(0, spring, -0.16), r, r, 0.32, 8, fxf.basis, 0.0, PI, ["inner"])
		for s: float in [-1.0, 1.0]:
			_face(c.s, fxf, [Vector3(s * r, floor_y, 0), Vector3(s * r, floor_y, -0.32), Vector3(s * r, spring, -0.32),
					Vector3(s * r, spring, 0)], Vector3(-s, 0, 0))
	_tint(c.s, wash * 0.22)
	_face(c.s, xf, [Vector3(cx - tw * 0.5 + 0.32, floor_y, back + 0.32), Vector3(cx + tw * 0.5 - 0.32, floor_y,
			back + 0.32), Vector3(cx + tw * 0.5 - 0.32, top, back + 0.32), Vector3(cx - tw * 0.5 + 0.32, top, back + 0.32)],
			Vector3.BACK)
	_face(c.s, xf, [Vector3(cx - tw * 0.5, top - 0.02, front), Vector3(cx + tw * 0.5, top - 0.02, front),
			Vector3(cx + tw * 0.5, top - 0.02, back), Vector3(cx - tw * 0.5, top - 0.02, back)], Vector3.DOWN)
	_face(c.s, xf, [Vector3(cx - tw * 0.5, floor_y + 0.01, front), Vector3(cx + tw * 0.5, floor_y + 0.01, front),
			Vector3(cx + tw * 0.5, floor_y + 0.01, back), Vector3(cx - tw * 0.5, floor_y + 0.01, back)], Vector3.UP)
	# A window in the shaft, lit.
	c.windows.surface(c.kit.window_material())
	c.windows.colour = Color(0.5 / 4.0, 0.8 / 4.0, (rng.randi_range(0, 4) + 0.5) / 8.0, rng.randf_range(0.5, 0.98))
	_face(c.windows, xf, [Vector3(cx - 0.25, eave + 0.05, front + 0.003), Vector3(cx + 0.25, eave + 0.05, front + 0.003),
			Vector3(cx + 0.25, eave + 0.85, front + 0.003), Vector3(cx - 0.25, eave + 0.85, front + 0.003)], Vector3.BACK)
	# Cornices at the open storey's floor and top, and the roof.
	c.u.surface(c.soft("stone"))
	_tint(c.u, stone)
	for cy: float in [floor_y, top]:
		_box(c.u, xf, Vector3(cx, cy, (front + back) * 0.5), Vector3(tw + 0.24, 0.16, tw + 0.24))
	var apex := Vector3(cx, top + 1.5, (front + back) * 0.5)
	c.s.surface(c.tinted("roof", "roof_tiles"))
	_tint(c.s, Color(0.95, 0.9, 0.86))
	var hw := tw * 0.5 + 0.3
	var ctr := Vector3(cx, top + 0.1, (front + back) * 0.5)
	var corners := [Vector3(-hw, 0, hw), Vector3(hw, 0, hw), Vector3(hw, 0, -hw), Vector3(-hw, 0, -hw)]
	for k in 4:
		var a: Vector3 = ctr + corners[k]
		var b2: Vector3 = ctr + corners[(k + 1) % 4]
		var n := (b2 - a).cross(apex - a).normalized()
		if n.y < 0.0:
			n = -n
		_face(c.s, xf, [a, b2, apex], n)
	c.u.surface(c.soft("stone"))
	_tint(c.u, TERRACOTTA * 0.9)
	_lathe(c.u, xf, [Vector2(0.06, 0.0), Vector2(0.1, 0.15), Vector2(0.0, 0.32)], apex - Vector3(0, 0.05, 0), 6)


## A Moorish oriel: a wooden box on brackets out from the wall, its front and sides latticed with warm light behind,
## a little tiled roof.
static func _oriel(c: Object, xf: Transform3D, x: float, y: float, w: float, h: float, z0: float, paint: Color,
		rng: RandomNumberGenerator) -> void:
	var d := 0.62
	var front := z0 + d
	var wood: Material = c.soft("wood")
	c.u.surface(wood)
	var dark := paint.lerp(DARK_WOOD, 0.55)
	_tint(c.u, dark)
	_box(c.u, xf, Vector3(x, y, z0 + d * 0.5), Vector3(w + 0.1, 0.14, d + 0.05), Basis(), [RoomMesh.FRONT])
	for s: float in [-1.0, 0.0, 1.0]:
		_beam(c.u, xf, Vector3(x + s * (w * 0.5 - 0.1), y - 0.75, z0), Vector3(x + s * (w * 0.5 - 0.1), y - 0.07,
				z0 + d * 0.9), Vector2(0.08, 0.1))
	# Posts and rails, lattice panels glowing between them.
	_tint(c.u, paint)
	for s: float in [-1.0, 1.0]:
		for zz: float in [z0 + 0.02, front]:
			_box(c.u, xf, Vector3(x + s * w * 0.5, y + h * 0.5, zz), Vector3(0.07, h, 0.07))
	_box(c.u, xf, Vector3(x, y + 0.95, front), Vector3(w, 0.06, 0.06))
	_box(c.u, xf, Vector3(x, y + h - 0.35, front), Vector3(w, 0.06, 0.06))
	var moment := rng.randf_range(0.1, 0.9)
	c.windows.surface(c.kit.window_material())
	c.windows.colour = Color((w - 0.1) / 4.0, (h - 1.4) / 4.0, 4.5 / 8.0, moment)
	_face(c.windows, xf, [Vector3(x - w * 0.5 + 0.05, y + 1.0, front - 0.02), Vector3(x + w * 0.5 - 0.05, y + 1.0,
			front - 0.02), Vector3(x + w * 0.5 - 0.05, y + h - 0.4, front - 0.02), Vector3(x - w * 0.5 + 0.05, y + h - 0.4,
			front - 0.02)], Vector3.BACK)
	for s: float in [-1.0, 1.0]:
		c.windows.colour = Color((d - 0.1) / 4.0, (h - 1.4) / 4.0, 4.5 / 8.0, moment)
		var sx := x + s * w * 0.5
		var pts: Array = [Vector3(sx, y + 1.0, z0 + 0.05), Vector3(sx, y + 1.0, front - 0.05),
				Vector3(sx, y + h - 0.4, front - 0.05), Vector3(sx, y + h - 0.4, z0 + 0.05)]
		if s < 0.0:
			pts = [pts[1], pts[0], pts[3], pts[2]]
		_face(c.windows, xf, pts, Vector3(s, 0, 0))
	# The panels under the lattice, solid and painted, and the lattice's grid over the light.
	_tint(c.u, paint * 0.9)
	_box(c.u, xf, Vector3(x, y + 0.5, front), Vector3(w, 0.9, 0.04))
	for s: float in [-1.0, 1.0]:
		_box(c.u, xf, Vector3(x + s * w * 0.5, y + 0.5, z0 + d * 0.5), Vector3(0.04, 0.9, d))
	_tint(c.u, dark)
	var cols := int(w / 0.16)
	for k in cols:
		_box(c.u, xf, Vector3(x - w * 0.5 + w * (k + 0.5) / cols, y + (h + 0.6) * 0.5, front + 0.01),
				Vector3(0.02, h - 1.4, 0.02), Basis(), [RoomMesh.UP, RoomMesh.DOWN, RoomMesh.FRONT])
	# The roof: a little slope of tiles.
	c.s.surface(c.tinted("roof", "roof_tiles"))
	_tint(c.s, Color(0.95, 0.9, 0.86))
	_face(c.s, xf, [Vector3(x - w * 0.5 - 0.15, y + h, front + 0.18), Vector3(x + w * 0.5 + 0.15, y + h, front + 0.18),
			Vector3(x + w * 0.5 + 0.15, y + h + 0.45, z0), Vector3(x - w * 0.5 - 0.15, y + h + 0.45, z0)],
			Vector3(0, 0.8, 0.6).normalized())
	c.u.surface(c.soft("wood"))
	_tint(c.u, dark)
	_box(c.u, xf, Vector3(x, y + h - 0.02, z0 + d * 0.5 + 0.08), Vector3(w + 0.3, 0.06, d + 0.2), Basis(), [RoomMesh.UP])


## A front door: a stone surround with a cornice over it, two leaves of dark wood with studs, a step.
static func _door(c: Object, xf: Transform3D, x: float, g: float, z0: float, stone: Color) -> void:
	var dw := 1.2
	var dh := 2.4
	c.s.surface(c.tinted("wood"))
	_tint(c.s, DARK_WOOD * 1.3)
	_face(c.s, xf, [Vector3(x - dw * 0.5, g, z0 - 0.12), Vector3(x + dw * 0.5, g, z0 - 0.12),
			Vector3(x + dw * 0.5, g + dh, z0 - 0.12), Vector3(x - dw * 0.5, g + dh, z0 - 0.12)], Vector3.BACK)
	c.u.surface(c.soft("stone"))
	_tint(c.u, stone)
	for s: float in [-1.0, 1.0]:
		_box(c.u, xf, Vector3(x + s * (dw * 0.5 + 0.1), g + dh * 0.5, z0 + 0.03), Vector3(0.2, dh, 0.06 + 0.24), Basis(),
				[RoomMesh.FRONT])
	_box(c.u, xf, Vector3(x, g + dh + 0.12, z0 + 0.03), Vector3(dw + 0.5, 0.24, 0.3), Basis(), [RoomMesh.FRONT])
	_box(c.u, xf, Vector3(x, g + dh + 0.3, z0 + 0.08), Vector3(dw + 0.7, 0.1, 0.4), Basis(), [RoomMesh.FRONT])
	c.u.surface(c.soft("iron", false))
	for s: float in [-1.0, 1.0]:
		for k in 4:
			for j in 2:
				_box(c.u, xf, Vector3(x + s * (0.15 + 0.25 * j), g + 0.4 + k * 0.5, z0 - 0.1), Vector3(0.03, 0.03, 0.03))


## A niche at the ground: a recess with a round head and a shell's half dome, a shelf, an urn or a lion on it.
static func _niche(c: Object, xf: Transform3D, x: float, g: float, z0: float, wash: Color, stone: Color,
		lion: bool) -> void:
	var w := 1.05
	var r := w * 0.5
	var y0 := g + 0.9
	var spring := y0 + 1.3
	var d := 0.35
	c.u.surface(c.soft("stone"))
	_tint(c.u, stone)
	for s: float in [-1.0, 1.0]:
		_box(c.u, xf, Vector3(x + s * (r + 0.1), (g + spring) * 0.5 + 0.2, z0 + 0.06), Vector3(0.2, spring - g - 0.4,
				0.12 + 0.12), Basis(), [RoomMesh.FRONT])
	Shapes.arch(c.u, xf * Vector3(x, spring, z0 + 0.06), r, r + 0.2, 0.12, 10, xf.basis, 0.0, PI, ["front", "outer"])
	_box(c.u, xf, Vector3(x, y0 - 0.04, z0 + 0.04), Vector3(w + 0.3, 0.08, 0.3), Basis(), [RoomMesh.FRONT])
	# The recess: its back darker, the hood a half dome with ribs of light and shade.
	_tint(c.u, wash * 0.5)
	_face(c.u, xf, [Vector3(x - r, y0, z0 - d), Vector3(x + r, y0, z0 - d), Vector3(x + r, spring, z0 - d),
			Vector3(x - r, spring, z0 - d)], Vector3.BACK)
	for s: float in [-1.0, 1.0]:
		_face(c.u, xf, [Vector3(x + s * r, y0, z0), Vector3(x + s * r, y0, z0 - d), Vector3(x + s * r, spring, z0 - d),
				Vector3(x + s * r, spring, z0)], Vector3(-s, 0, 0))
	var prof: Array = []
	for i in 7:
		var lat := PI * 0.5 * i / 6.0
		prof.append(Vector2(cos(lat) * r, sin(lat) * r))
	prof.reverse()
	_tint(c.u, wash * 0.62)
	_lathe(c.u, xf, prof, Vector3(x, spring, z0 - d + 0.0), 8, Basis(), PI, -PI * 0.5)
	if lion:
		_lion(c, xf * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(x, y0, z0 - d * 0.5)), Vector3.ZERO, 0.7, stone)
	else:
		_urn(c, xf, Vector3(x, y0, z0 - d * 0.45), 1.3, stone)


## A wall fountain at the ground: a panel of glazed tiles in a stone frame under a round pediment, a lion's mask
## spouting a jet into a half-round basin, the water (PieceWater) in it.
static func _fountain(c: Object, xf: Transform3D, x: float, g: float, z0: float, stone: Color) -> void:
	var pw := 1.5
	var ph := 1.9
	# The tiles: glazed white, each with a blue lozenge whose points meet the next tile's, so four tiles make a star;
	# a yellow heart in each; a border of plain blue round the panel.
	c.u.surface(c.soft("stone"))
	var nx := 6
	var ny := 8
	var tw := pw / nx
	var th := ph / ny
	for i in nx:
		for j in ny:
			var tx := x - pw * 0.5 + tw * (i + 0.5)
			var ty := g + 0.4 + th * (j + 0.5)
			var edge := i == 0 or j == 0 or i == nx - 1 or j == ny - 1
			_tint(c.u, Color(0.16, 0.26, 0.55) if edge else Color(0.9, 0.88, 0.8))
			_face(c.u, xf, [Vector3(tx - tw * 0.48, ty - th * 0.48, z0 + 0.012), Vector3(tx + tw * 0.48, ty - th * 0.48,
					z0 + 0.012), Vector3(tx + tw * 0.48, ty + th * 0.48, z0 + 0.012), Vector3(tx - tw * 0.48, ty + th * 0.48,
					z0 + 0.012)], Vector3.BACK)
			if edge:
				continue
			_tint(c.u, Color(0.2, 0.32, 0.64))
			_face(c.u, xf, [Vector3(tx, ty - th * 0.46, z0 + 0.015), Vector3(tx + tw * 0.46, ty, z0 + 0.015),
					Vector3(tx, ty + th * 0.46, z0 + 0.015), Vector3(tx - tw * 0.46, ty, z0 + 0.015)], Vector3.BACK)
			_tint(c.u, Color(0.92, 0.9, 0.82))
			_face(c.u, xf, [Vector3(tx, ty - th * 0.24, z0 + 0.017), Vector3(tx + tw * 0.24, ty, z0 + 0.017),
					Vector3(tx, ty + th * 0.24, z0 + 0.017), Vector3(tx - tw * 0.24, ty, z0 + 0.017)], Vector3.BACK)
			_tint(c.u, Color(0.88, 0.62, 0.16))
			_face(c.u, xf, [Vector3(tx, ty - th * 0.1, z0 + 0.019), Vector3(tx + tw * 0.1, ty, z0 + 0.019),
					Vector3(tx, ty + th * 0.1, z0 + 0.019), Vector3(tx - tw * 0.1, ty, z0 + 0.019)], Vector3.BACK)
	_tint(c.u, Color(0.1, 0.12, 0.2))
	_face(c.u, xf, [Vector3(x - pw * 0.5 - 0.02, g + 0.38, z0 + 0.008), Vector3(x + pw * 0.5 + 0.02, g + 0.38, z0 + 0.008),
			Vector3(x + pw * 0.5 + 0.02, g + 0.42 + ph, z0 + 0.008), Vector3(x - pw * 0.5 - 0.02, g + 0.42 + ph, z0 + 0.008)],
			Vector3.BACK)
	# The stone frame: pilasters, an entablature, a round pediment, the basin.
	_tint(c.u, stone)
	for s: float in [-1.0, 1.0]:
		_box(c.u, xf, Vector3(x + s * (pw * 0.5 + 0.13), g + (ph + 0.4) * 0.5, z0 + 0.08), Vector3(0.26, ph + 0.4, 0.16),
				Basis(), [RoomMesh.FRONT])
	_box(c.u, xf, Vector3(x, g + ph + 0.52, z0 + 0.1), Vector3(pw + 0.7, 0.2, 0.22), Basis(), [RoomMesh.FRONT])
	Shapes.arch(c.u, xf * Vector3(x, g + ph + 0.62, z0 + 0.08), pw * 0.42, pw * 0.42 + 0.14, 0.16, 10, xf.basis, 0.0, PI,
			["front", "outer", "inner"])
	_urn(c, xf, Vector3(x, g + ph + 0.62 + pw * 0.42 + 0.05, z0 + 0.08), 0.7, stone)
	var bowl_y := g + 0.72
	var rb := 0.62
	_lathe(c.u, xf, [Vector2(rb * 0.5, 0.0), Vector2(rb * 0.62, 0.2), Vector2(rb, bowl_y - g - 0.05),
			Vector2(rb + 0.06, bowl_y - g), Vector2(rb + 0.06, bowl_y - g + 0.06), Vector2(rb - 0.06, bowl_y - g + 0.06)],
			Vector3(x, g, z0), 10, Basis(), PI, -PI * 0.5)
	# The lion's mask on the tiles, its mouth over the basin.
	var mouth := Vector3(x, g + 1.45, z0 + 0.16)
	var mxf := xf * Transform3D(Basis(), mouth)
	_lion_mask(c, mxf, stone * 0.95)
	c.u.surface(c.soft("gilt", false))
	_beam(c.u, xf, mouth + Vector3(0, -0.05, 0.02), mouth + Vector3(0, -0.05, 0.12), Vector2(0.035, 0.035))
	# The water: the basin's surface and the jet falling into it.
	c.water.surface(c.kit.water_material())
	var land := Vector3(x, bowl_y - 0.02, z0 + 0.36)
	var pts: Array = []
	for k in 11:
		var t := PI * k / 10.0
		pts.append(Vector3(x + cos(t) * (rb - 0.02), bowl_y - 0.02, z0 + sin(t) * (rb - 0.02)))
	# The landing point in the face's own coordinates (RoomMesh: u along the first edge, v = normal x u).
	var a: Vector3 = xf * pts[0]
	var u_axis: Vector3 = (xf * Vector3(pts[1]) - a).normalized()
	var n_w := (xf.basis * Vector3.UP).normalized()
	var v_axis := n_w.cross(u_axis).normalized()
	var lo := Vector2(INF, INF)
	for p: Vector3 in pts:
		var q := xf * p - a
		lo = lo.min(Vector2(q.dot(u_axis), q.dot(v_axis)))
	var lq := xf * land - a
	var luv := Vector2(lq.dot(u_axis), lq.dot(v_axis)) - lo
	c.water.colour = Color(0.0, luv.x / 4.0, luv.y / 4.0, 1.0)
	_face(c.water, xf, pts, Vector3.UP)
	c.water.colour = Color(1.0, 0.0, 0.0, 1.0)
	var fall_a := PackedVector3Array()
	var fall_b := PackedVector3Array()
	var fall_n := PackedVector3Array()
	var start := mouth + Vector3(0, -0.05, 0.13)
	for k in 9:
		var t := k / 8.0
		var p := start.lerp(land, t)
		p.y = lerpf(start.y, land.y, t * t)
		p.z = start.z + (land.z - start.z) * sqrt(t)
		var wdt := lerpf(0.011, 0.02, t)
		fall_a.append(xf * (p + Vector3(-wdt, 0, 0)))
		fall_b.append(xf * (p + Vector3(wdt, 0, 0)))
		fall_n.append((xf.basis * Vector3(0, 0.3, 1).normalized()).normalized())
	c.water.strip(fall_a, fall_b, fall_n)
	c.water.strip(fall_b, fall_a, fall_n)


## A lion's mask on a wall, its mouth at mxf's origin (facing +Z): a mane of locks in a ring, the face, brows, eyes,
## a broad nose, a muzzle, the open mouth's dark.
static func _lion_mask(c: Object, mxf: Transform3D, colour: Color) -> void:
	_tint(c.u, colour * 0.9)
	c.u.rounded_box(Vector3.ZERO, Vector3(0.5, 0.5, 0.08), 0.04, mxf * Transform3D(Basis(), Vector3(0, 0.1, -0.12)), 1)
	for k in 12:
		var t := TAU * k / 12.0 + 0.13
		var p := Vector3(cos(t) * 0.24, 0.1 + sin(t) * 0.24, -0.07)
		c.u.rounded_box(Vector3.ZERO, Vector3(0.16, 0.09, 0.08), 0.035,
				mxf * Transform3D(Basis(Vector3.BACK, t), p), 1)
	_tint(c.u, colour)
	c.u.rounded_box(Vector3.ZERO, Vector3(0.28, 0.32, 0.12), 0.07, mxf * Transform3D(Basis(), Vector3(0, 0.1, -0.02)), 1)
	for s: float in [-1.0, 1.0]:
		c.u.rounded_box(Vector3.ZERO, Vector3(0.1, 0.04, 0.05), 0.015,
				mxf * Transform3D(Basis(Vector3.BACK, -s * 0.25), Vector3(s * 0.065, 0.19, 0.04)), 1)
		c.u.rounded_box(Vector3.ZERO, Vector3(0.09, 0.07, 0.06), 0.025, mxf * Transform3D(Basis(), Vector3(s * 0.055, 0.0, 0.06)), 1)
	c.u.rounded_box(Vector3.ZERO, Vector3(0.09, 0.14, 0.07), 0.03, mxf * Transform3D(Basis(), Vector3(0, 0.08, 0.06)), 1)
	_tint(c.u, colour * 0.25)
	c.u.rounded_box(Vector3.ZERO, Vector3(0.08, 0.04, 0.03), 0.012, mxf * Transform3D(Basis(), Vector3(0, -0.05, 0.05)), 1)
	for s: float in [-1.0, 1.0]:
		c.u.rounded_box(Vector3.ZERO, Vector3(0.035, 0.02, 0.02), 0.008, mxf * Transform3D(Basis(), Vector3(s * 0.065, 0.15, 0.065)), 1)


## A ground storey of arches on columns before a shallow loggia: the arcade across the house, the room behind it dark,
## a lantern in its middle arch.
static func _arcade(c: Object, xf: Transform3D, w: float, g_hi: float, storey0: float, z0: float, wash: Color,
		stone: Color, rng: RandomNumberGenerator) -> void:
	var bays := maxi(int(round(w / 2.2)), 2)
	var bay := w / bays
	var r := bay * 0.5 - 0.18
	var spring := storey0 - r - 0.35
	# The recess's back stands just in front of the wall behind (no two faces in one plane).
	var depth := clampf(z0 - 0.03, 0.05, 0.9)
	var zb := z0 - depth
	c.s.surface(c.tinted("plaster", "lime_wash"))
	for b in bays:
		var bx := -w * 0.5 + bay * (b + 0.5)
		var gy := _ground(c, xf, bx, z0 + 0.3)
		_tint(c.s, wash)
		for s: float in [-1.0, 1.0]:
			var pts: Array = [Vector3(bx + s * bay * 0.5, storey0, z0), Vector3(bx + s * bay * 0.5, spring, z0)]
			for k in 9:
				var t := PI * 0.5 * k / 8.0 if s > 0.0 else PI - PI * 0.5 * k / 8.0
				pts.append(Vector3(bx + cos(t) * r, spring + sin(t) * r, z0))
			pts.append(Vector3(bx, storey0, z0))
			_face(c.s, xf, pts, Vector3.BACK)
		_tint(c.s, wash * 0.7)
		Shapes.arch(c.s, xf * Vector3(bx, spring, z0 - depth * 0.5), r, r, depth, 8, xf.basis, 0.0, PI, ["inner"])
		_tint(c.s, wash * 0.3)
		_face(c.s, xf, [Vector3(bx - bay * 0.5, gy - 0.6, zb), Vector3(bx + bay * 0.5, gy - 0.6, zb),
				Vector3(bx + bay * 0.5, spring + r, zb), Vector3(bx - bay * 0.5, spring + r, zb)], Vector3.BACK)
		if b == bays / 2:
			c.windows.surface(c.kit.window_material())
			c.windows.colour = Color(0.9 / 4.0, 2.0 / 4.0, (rng.randi_range(0, 2) + 0.5) / 8.0, rng.randf_range(0.2, 0.8))
			_face(c.windows, xf, [Vector3(bx - 0.45, gy, zb + 0.01), Vector3(bx + 0.45, gy, zb + 0.01),
					Vector3(bx + 0.45, gy + 2.0, zb + 0.01), Vector3(bx - 0.45, gy + 2.0, zb + 0.01)], Vector3.BACK)
	# The columns: a base, a shaft, a capital.
	c.u.surface(c.soft("stone"))
	_tint(c.u, stone)
	for b in bays + 1:
		var px := -w * 0.5 + bay * b
		var gy := _ground(c, xf, px, z0 + 0.3)
		if b == 0 or b == bays:
			_box(c.u, xf, Vector3(px - signf(px) * 0.18, (gy + spring) * 0.5, z0 - 0.1), Vector3(0.36, spring - gy, 0.4))
			continue
		_lathe(c.u, xf, [Vector2(0.17, 0.0), Vector2(0.15, 0.12), Vector2(0.12, 0.2), Vector2(0.105, spring - gy - 0.3),
				Vector2(0.12, spring - gy - 0.25), Vector2(0.2, spring - gy - 0.05), Vector2(0.2, spring - gy)],
				Vector3(px, gy - 0.3, z0 - 0.15), 10)
	_lantern(c, xf, Vector3(-w * 0.5 + bay * (bays / 2 + 0.5), spring + r - 0.05, zb), 0.7)


## The projector's lens (the builder's `lens`) in a piece's frame.
static func _lens_local(c: Object, xf: Transform3D) -> Vector3:
	var lens: Vector3 = Vector3(0.0, 3.45, 6.15)
	var bp: Dictionary = c.builder_params
	if bp.has("lens"):
		var l: Array = bp["lens"]
		lens = Vector3(float(l[0]), float(l[1]), float(l[2]))
	return xf.affine_inverse() * lens


## The projection booth behind the back wall, as a house's windows: the projector's port and the two viewing ports
## at the lens's height (the builder's `lens`), each in a stone frame with a grille, the booth's glow in them.
static func _booth_ports(c: Object, xf: Transform3D, z0: float, wash: Color, stone: Color) -> void:
	var local := _lens_local(c, xf)
	var ports := [[local.x, Vector2(1.3, 0.75)], [local.x - 1.5, Vector2(0.55, 0.4)], [local.x + 1.5, Vector2(0.55, 0.4)]]
	for p: Array in ports:
		var px: float = p[0]
		var ps: Vector2 = p[1]
		var key := "port" if p == ports[0] else "port_dim"
		var g: Array = c.glows.get(key, [])
		g.append([xf * Vector3(px, local.y, z0 + 0.004), xf.basis.x * ps.x * 0.5, xf.basis.y * ps.y * 0.5,
				(xf.basis.z).normalized()])
		c.glows[key] = g
		c.u.surface(c.soft("stone"))
		_tint(c.u, stone)
		for s: float in [-1.0, 1.0]:
			_box(c.u, xf, Vector3(px + s * (ps.x * 0.5 + 0.08), local.y, z0 + 0.05), Vector3(0.16, ps.y + 0.32, 0.1),
					Basis(), [RoomMesh.FRONT])
			_box(c.u, xf, Vector3(px, local.y + s * (ps.y * 0.5 + 0.08), z0 + 0.05), Vector3(ps.x + 0.32, 0.16, 0.1),
					Basis(), [RoomMesh.FRONT])
		_box(c.u, xf, Vector3(px, local.y + ps.y * 0.5 + 0.22, z0 + 0.1), Vector3(ps.x + 0.5, 0.08, 0.2), Basis(),
				[RoomMesh.FRONT])


# --- The palace gate ---------------------------------------------------------------------------------------------------

## A palace gate round the screen: a tower either side (a rusticated base, an organ's grille in a tall arch with a
## gilt lattice over the pipes' warm chamber and a gilt balconette under it, a cornice, a lit window, a belfry with
## its bell, a pyramid roof of tiles with a gilt finial), and between them a great arch over the picture: the arch's
## band with gilt mouldings and a keystone's cartouche, gilt rosettes in its soffit, medallions in the spandrels, a
## frieze and cornice, a balustrade with urns against the sky. Velvet drapes tied back in the arch's jambs and swags
## along its top. Nothing of it in front of the picture. size.x: the room's width (the towers reach the walls).
static func _palace_gate(c: Object, _xf: Transform3D, size: Vector3, e: Dictionary) -> void:
	var sc: Dictionary = c.screen
	var sxf: Transform3D = sc["xf"]
	var ss: Vector2 = sc["size"]
	var floor_y: float = sc.get("floor", sxf.origin.y - ss.y * 0.5 - 1.0)
	var xf := Transform3D(sxf.basis.orthonormalized(), Vector3(sxf.origin.x, floor_y, sxf.origin.z))
	var stone_c := _colour(e, "colour", Color(0.84, 0.76, 0.62))
	var bottom := sxf.origin.y - ss.y * 0.5 - floor_y
	var pic_top := bottom + ss.y
	var ox := ss.x * 0.5 + 0.6
	var room_w := size.x if size.x > 0.0 else ss.x + 7.0
	var tx1 := maxf(room_w * 0.5, ox + 2.0)
	var tw := tx1 - ox
	var front := 0.8
	var back := -0.8
	var spring := pic_top + 0.45
	var rise := 1.5
	var radius := (ox * ox + rise * rise) / (2.0 * rise)
	var centre_y := spring + rise - radius
	var band := 0.75
	var a0 := asin(clampf(ox / radius, -1.0, 1.0))
	var ent := spring + rise + band + 0.25
	var ent_top := ent + 0.95
	var shaft_top := ent_top + 2.6
	var bell_top := shaft_top + 2.3
	var stone: Material = c.tinted("stone", "ashlar")
	var stone_soft: Material = c.soft("stone")
	var gilt: Material = c.soft("gilt", false)
	# --- The towers.
	for s: float in [-1.0, 1.0]:
		var cx := s * (ox + tw * 0.5)
		c.s.surface(stone)
		_tint(c.s, stone_c)
		# The front face round the organ's arch, the inner face (the arch's jamb), up to the belfry.
		var gx := cx
		var gw := minf(1.7, tw - 0.9)
		var g0 := bottom + 1.6
		var gs := ent - 1.0
		var gr := gw * 0.5
		var holes := [Rect2(gx - gr - (cx - tw * 0.5), g0, gw, gs + gr - g0)]
		Shapes.wall(c.s, xf * Vector3(cx - tw * 0.5, 0.0, front), xf.basis.x, (xf.basis.z).normalized(), tw, shaft_top,
				holes)
		for k: float in [-1.0, 1.0]:
			var pts: Array = [Vector3(gx + k * gr, gs + gr, front)]
			for j in 9:
				var t := PI * 0.5 * (1.0 - j / 8.0) if k > 0.0 else PI * 0.5 * (1.0 + j / 8.0)
				pts.append(Vector3(gx + cos(t) * gr, gs + sin(t) * gr, front))
			_face(c.s, xf, pts, Vector3.BACK)
		var inner := s * ox
		_face(c.s, xf, [Vector3(inner, 0, front), Vector3(inner, 0, back), Vector3(inner, shaft_top, back),
				Vector3(inner, shaft_top, front)], Vector3(-s, 0, 0))
		# The organ's chamber: the reveal, the pipes' warm glow, a gilt lattice before it, a balconette under it.
		_tint(c.s, stone_c * 0.8)
		for k: float in [-1.0, 1.0]:
			_face(c.s, xf, [Vector3(gx + k * gr, g0, front), Vector3(gx + k * gr, g0, front - 0.35),
					Vector3(gx + k * gr, gs, front - 0.35), Vector3(gx + k * gr, gs, front)], Vector3(-k, 0, 0))
		_face(c.s, xf, [Vector3(gx - gr, g0, front), Vector3(gx + gr, g0, front), Vector3(gx + gr, g0, front - 0.35),
				Vector3(gx - gr, g0, front - 0.35)], Vector3.UP)
		Shapes.arch(c.s, xf * Vector3(gx, gs, front - 0.175), gr, gr, 0.35, 8, xf.basis, 0.0, PI, ["inner"])
		c.windows.surface(c.kit.window_material())
		c.windows.colour = Color(gw / 4.0, (gs + gr - g0) / 4.0, 5.5 / 8.0, 0.97 if s < 0.0 else 0.985)
		var glass: Array = [Vector3(gx - gr, g0, front - 0.35), Vector3(gx + gr, g0, front - 0.35)]
		for j in 9:
			var t := PI * j / 8.0
			glass.append(Vector3(gx + cos(t) * gr, gs + sin(t) * gr, front - 0.35))
		_face(c.windows, xf, glass, Vector3.BACK)
		_grille(c, xf, gx, g0, gw, gs, front - 0.12)
		c.u.surface(gilt)
		_tint(c.u, Color.WHITE)
		Shapes.arch(c.u, xf * Vector3(gx, gs, front + 0.03), gr, gr + 0.1, 0.06, 10, xf.basis, 0.0, PI, ["front", "outer"])
		for k: float in [-1.0, 1.0]:
			_box(c.u, xf, Vector3(gx + k * (gr + 0.05), (g0 + gs) * 0.5, front + 0.03), Vector3(0.1, gs - g0, 0.06), Basis(),
					[RoomMesh.FRONT])
		_gilt_rail(c, xf, gx, g0, gw + 0.5, front)
		c.lamps.append([xf * Vector3(gx, (g0 + gs) * 0.5, front + 0.3), Color(1.0, 0.62, 0.32), 0.55])
		# The rusticated base's bands, the cornices at the arch's entablature and the belfry's floor.
		c.u.surface(stone_soft)
		_tint(c.u, stone_c)
		for by: float in [0.0, 0.55, 1.1]:
			_box(c.u, xf, Vector3(cx, by + 0.25, front + 0.04), Vector3(tw, 0.48, 0.08), Basis(), [RoomMesh.FRONT])
		_box(c.u, xf, Vector3(cx, g0 - 0.12, front + 0.06), Vector3(tw + 0.04, 0.12, 0.14), Basis(), [RoomMesh.FRONT])
		for cy: float in [ent_top, shaft_top]:
			_box(c.u, xf, Vector3(cx, cy - 0.1, (front + back) * 0.5 + 0.05), Vector3(tw + 0.3, 0.2, front - back + 0.3),
					Basis(), [RoomMesh.FRONT])
			_box(c.u, xf, Vector3(cx, cy + 0.04, (front + back) * 0.5 + 0.1), Vector3(tw + 0.42, 0.1, front - back + 0.42))
		# A small lit window in the shaft.
		c.windows.surface(c.kit.window_material())
		c.windows.colour = Color(0.55 / 4.0, 0.95 / 4.0, (0.5 if s < 0.0 else 2.5) / 8.0, 0.9)
		_face(c.windows, xf, [Vector3(cx - 0.275, ent_top + 0.75, front + 0.002), Vector3(cx + 0.275, ent_top + 0.75,
				front + 0.002), Vector3(cx + 0.275, ent_top + 1.7, front + 0.002), Vector3(cx - 0.275, ent_top + 1.7,
				front + 0.002)], Vector3.BACK)
		c.u.surface(stone_soft)
		_tint(c.u, stone_c)
		for k: float in [-1.0, 1.0]:
			_box(c.u, xf, Vector3(cx + k * 0.36, ent_top + 1.22, front + 0.03), Vector3(0.12, 1.1, 0.06), Basis(), [RoomMesh.FRONT])
		_box(c.u, xf, Vector3(cx, ent_top + 1.82, front + 0.04), Vector3(0.9, 0.12, 0.08), Basis(), [RoomMesh.FRONT])
		_box(c.u, xf, Vector3(cx, ent_top + 0.7, front + 0.06), Vector3(0.85, 0.08, 0.14), Basis(), [RoomMesh.FRONT])
		# The belfry: piers, an arch on the front and the inner face, the dark inside, the bell.
		_belfry(c, xf, cx, shaft_top, bell_top, tw, front, back, stone_c, s)
		# The roof: a pyramid of tiles, a gilt ball and spike.
		var ctr := Vector3(cx, bell_top + 0.15, (front + back) * 0.5)
		var hw := tw * 0.5 + 0.35
		var hd := (front - back) * 0.5 + 0.35
		var apex := ctr + Vector3(0, 1.9, 0)
		c.s.surface(c.tinted("roof", "roof_tiles"))
		_tint(c.s, Color(0.95, 0.9, 0.86))
		var corners := [Vector3(-hw, 0, hd), Vector3(hw, 0, hd), Vector3(hw, 0, -hd), Vector3(-hw, 0, -hd)]
		for k in 4:
			var a: Vector3 = ctr + corners[k]
			var b2: Vector3 = ctr + corners[(k + 1) % 4]
			var n := (b2 - a).cross(apex - a).normalized()
			if n.y < 0.0:
				n = -n
			_face(c.s, xf, [a, b2, apex], n)
		c.u.surface(stone_soft)
		_tint(c.u, stone_c)
		_box(c.u, xf, Vector3(cx, bell_top + 0.07, (front + back) * 0.5), Vector3(tw + 0.75, 0.16, front - back + 0.75))
		c.u.surface(gilt)
		_tint(c.u, Color.WHITE)
		_lathe(c.u, xf, [Vector2(0.0, -0.02), Vector2(0.09, 0.03), Vector2(0.12, 0.13), Vector2(0.09, 0.23),
				Vector2(0.02, 0.27), Vector2(0.015, 0.7), Vector2(0.0, 0.72)], apex - Vector3(0, 0.03, 0), 8)
		_solid(c, xf, Vector3(cx, bell_top * 0.5, (front + back) * 0.5), Vector3(tw, bell_top, front - back))
	# --- The arch, its spandrels, the entablature and the balustrade.
	var arch_c := Vector3(0, centre_y, 0)
	c.s.surface(stone)
	_tint(c.s, stone_c)
	Shapes.arch(c.s, xf * Vector3(0, centre_y, back + (front - back + 0.05) * 0.5), radius, radius + band,
			front - back + 0.05, 16, xf.basis, PI * 0.5 - a0, PI * 0.5 + a0, ["front", "inner"])
	# The spandrels: from the band's outer edge up to the entablature, between the towers.
	var line_a := PackedVector3Array()
	var line_b := PackedVector3Array()
	var ns := PackedVector3Array()
	for k in 17:
		var t := PI * 0.5 + a0 - 2.0 * a0 * k / 16.0
		var p := arch_c + Vector3(cos(t), sin(t), 0) * (radius + band)
		p.x = clampf(p.x, -ox, ox)
		line_a.append(xf * Vector3(p.x, p.y, front - 0.1))
		line_b.append(xf * Vector3(p.x, ent, front - 0.1))
		ns.append((xf.basis * Vector3.BACK).normalized())
	c.s.strip(line_a, line_b, ns)
	# The entablature's face (frieze and cornice) and its top.
	_box(c.s, xf, Vector3(0, (ent + ent_top) * 0.5, front - 0.02), Vector3(ox * 2.0, ent_top - ent, 0.16), Basis(),
			[RoomMesh.FRONT, RoomMesh.LEFT, RoomMesh.RIGHT])
	c.u.surface(stone_soft)
	_tint(c.u, stone_c)
	_box(c.u, xf, Vector3(0, ent_top - 0.1, front + 0.1), Vector3(ox * 2.0, 0.2, 0.3), Basis(), [RoomMesh.FRONT])
	_box(c.u, xf, Vector3(0, ent_top + 0.04, front + 0.16), Vector3(ox * 2.0, 0.1, 0.42), Basis(), [RoomMesh.FRONT])
	_box(c.u, xf, Vector3(0, ent + 0.06, front + 0.06), Vector3(ox * 2.0, 0.12, 0.08), Basis(), [RoomMesh.FRONT])
	# The voussoirs' joints: darker lines across the band, a keystone standing out.
	_tint(c.u, stone_c * 0.82)
	for k in 15:
		var t := PI * 0.5 + a0 - 2.0 * a0 * (k + 0.5) / 15.0
		var dir := Vector3(cos(t), sin(t), 0)
		var p0 := arch_c + dir * radius
		var p1 := arch_c + dir * (radius + band)
		_beam(c.u, xf, p0 + Vector3(0, 0, front - 0.08), p1 + Vector3(0, 0, front - 0.08), Vector2(0.025, 0.012))
	_balustrade(c, xf, -ox, ox, ent_top + 0.1, front - 0.25, 1.0, stone_c)
	for k: float in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		var ux := k * (ox - 0.3)
		_urn(c, xf, Vector3(ux, ent_top + 1.1, front - 0.25), 1.6, stone_c)
	# --- The gilding: mouldings at the band's edges, the keystone's cartouche, rosettes in the soffit, medallions in
	# the spandrels, a fillet along the frieze.
	c.u.surface(gilt)
	_tint(c.u, Color.WHITE)
	Shapes.arch(c.u, xf * Vector3(0, centre_y, front + 0.07), radius - 0.02, radius + 0.1, 0.08, 24, xf.basis,
			PI * 0.5 - a0, PI * 0.5 + a0, ["front", "inner"])
	# The outer moulding broad and standing out, its inner edge catching the floods (a thin one read as a wire).
	Shapes.arch(c.u, xf * Vector3(0, centre_y, front + 0.08), radius + band - 0.14, radius + band + 0.04, 0.1, 24,
			xf.basis, PI * 0.5 - a0, PI * 0.5 + a0, ["front", "outer", "inner"])
	_box(c.u, xf, Vector3(0, ent + 0.35, front + 0.07), Vector3(ox * 2.0 - 0.2, 0.05, 0.03))
	_box(c.u, xf, Vector3(0, ent + 0.6, front + 0.07), Vector3(ox * 2.0 - 0.2, 0.05, 0.03))
	var key := arch_c + Vector3(0, radius + band * 0.5, front)
	c.u.rounded_box(Vector3.ZERO, Vector3(0.62, 1.0, 0.14), 0.07, xf * Transform3D(Basis(), key + Vector3(0, 0.08, 0.02)), 1)
	# A shell over the cartouche: a fan of ribs.
	for k in 9:
		var t := PI * k / 8.0
		_beam(c.u, xf, key + Vector3(0, 0.62, 0.05), key + Vector3(cos(t) * 0.48, 0.62 + sin(t) * 0.42, 0.05),
				Vector2(0.06, 0.04))
	for k in 7:
		var t := PI * 0.5 + a0 * 0.92 - 2.0 * a0 * 0.92 * k / 6.0
		var p := arch_c + Vector3(cos(t), sin(t), 0) * (radius + 0.005)
		var axis := Vector3(cos(t), sin(t), 0)
		c.u.rounded_box(Vector3.ZERO, Vector3(0.3, 0.06, 0.3), 0.03, xf * Transform3D(Basis(Vector3.BACK, t - PI * 0.5),
				p + axis * 0.02 + Vector3(0, 0, (front + back) * 0.5 - 0.1)), 1)
	for k: float in [-1.0, 1.0]:
		var mx := k * (ox * 0.62)
		var my := (arch_c.y + sqrt(maxf(pow(radius + band, 2.0) - mx * mx, 0.0)) + ent) * 0.5
		Shapes.arch(c.u, xf * Vector3(mx, my, front - 0.06), 0.24, 0.34, 0.08, 14, xf.basis, 0.0, TAU,
				["front", "outer", "inner"])
		var petals: Array = []
		for j in 12:
			var t := TAU * j / 12.0
			petals.append(Vector3(mx + cos(t) * (0.2 if j % 2 == 0 else 0.1), my + sin(t) * (0.2 if j % 2 == 0 else 0.1),
					front - 0.02))
		_face(c.u, xf, petals, Vector3.BACK)
	# --- Floodlights from the stage's lip, hidden below it: warm light up each tower's face and across the arch
	# (for the bake; the house lamps' level takes them down with the film).
	for s: float in [-1.0, 1.0]:
		c.spots.append([xf * Vector3(s * (ox + tw * 0.5), 0.1, front + 0.4), xf * Vector3(s * (ox + tw * 0.5),
				ent_top - 1.0, front - 0.4), Color(1.0, 0.76, 0.5), 6.0, 18.0, 28.0])
		c.spots.append([xf * Vector3(s * ox * 0.55, 0.1, front + 0.4), xf * Vector3(s * ox * 0.45, ent, front - 0.3),
				Color(1.0, 0.8, 0.58), 3.5, 14.0, 32.0])
	# --- The drapes: tied back in the jambs, swags along the arch's top.
	_drapes(c, xf, ox, spring, arch_c, radius, a0, pic_top, front)
	# --- Lions before the towers, at the stage's corners... placed by the document (pedestal pieces).
	_solid(c, xf, Vector3(0, (spring + ent_top) * 0.5 + 0.5, (front + back) * 0.5), Vector3(ox * 2.0, ent_top - spring,
			front - back))


## An organ's grille: a gilt lattice of diagonal bars over the opening, a fan of bars in its round head.
static func _grille(c: Object, xf: Transform3D, gx: float, g0: float, gw: float, gs: float, z: float) -> void:
	c.u.surface(c.soft("gilt", false))
	_tint(c.u, Color(0.85, 0.85, 0.85))
	var gr := gw * 0.5
	var step := 0.22
	# Diagonals each way, clipped to the rectangle under the springing.
	var h := gs - g0
	var n := int((gw + h) / step) + 1
	for sgn: float in [-1.0, 1.0]:
		for k in n:
			# The line x - sgn * y = const through the rectangle [-gr, gr] x [0, h].
			var cst := -gr - h + k * step if sgn > 0.0 else -gr + k * step
			var pts: Array[Vector2] = []
			for y: float in [0.0, h]:
				var x := cst + sgn * y if sgn > 0.0 else cst - y
				if x >= -gr and x <= gr:
					pts.append(Vector2(x, y))
			for x: float in [-gr, gr]:
				var y := (x - cst) / sgn if sgn > 0.0 else (cst - x)
				if y >= 0.0 and y <= h:
					pts.append(Vector2(x, y))
			if pts.size() < 2:
				continue
			var a := pts[0]
			var b := pts[1]
			for p in pts:
				if p.distance_to(a) > b.distance_to(a):
					b = p
			if a.distance_to(b) < 0.05:
				continue
			_beam(c.u, xf, Vector3(gx + a.x, g0 + a.y, z), Vector3(gx + b.x, g0 + b.y, z), Vector2(0.035, 0.025))
	for k in 9:
		var t := PI * (k + 0.5) / 9.0
		_beam(c.u, xf, Vector3(gx, gs, z), Vector3(gx + cos(t) * gr, gs + sin(t) * gr, z), Vector2(0.03, 0.025))
	_box(c.u, xf, Vector3(gx, gs, z), Vector3(gw, 0.05, 0.04))


## A gilt balconette's rail at y (its foot), centred on x, standing out from the face at z.
static func _gilt_rail(c: Object, xf: Transform3D, x: float, y: float, w: float, z: float) -> void:
	c.u.surface(c.soft("stone"))
	_tint(c.u, Color(0.84, 0.76, 0.62))
	_box(c.u, xf, Vector3(x, y - 0.05, z + 0.25), Vector3(w, 0.1, 0.5), Basis(), [RoomMesh.FRONT])
	for s: float in [-1.0, 1.0]:
		_box(c.u, xf, Vector3(x + s * (w * 0.5 - 0.15), y - 0.25, z + 0.18), Vector3(0.14, 0.3, 0.36), Basis(), [RoomMesh.FRONT])
	c.u.surface(c.soft("gilt", false))
	_tint(c.u, Color.WHITE)
	_box(c.u, xf, Vector3(x, y + 0.7, z + 0.47), Vector3(w, 0.05, 0.05))
	_box(c.u, xf, Vector3(x, y + 0.08, z + 0.47), Vector3(w, 0.04, 0.04))
	var n := int(w / 0.12)
	for k in n + 1:
		var bx := x - w * 0.5 + w * k / n
		_lathe(c.u, xf, [Vector2(0.018, 0.0), Vector2(0.03, 0.15), Vector2(0.018, 0.3), Vector2(0.03, 0.45),
				Vector2(0.018, 0.62)], Vector3(bx, y + 0.08, z + 0.47), 4)


## A belfry atop a tower: four piers, open arches to the front and to the arch's side, the dark room in it, a bell.
static func _belfry(c: Object, xf: Transform3D, cx: float, y0: float, y1: float, tw: float, front: float, back: float,
		stone_c: Color, s: float) -> void:
	var d := front - back
	c.s.surface(c.tinted("stone", "ashlar"))
	var r := minf(tw, d) * 0.5 - 0.35
	var spring := y1 - r - 0.35
	for face: int in 3:
		# 0 the front, 1 the side towards the arch, 2 the side towards the wall.
		var basis := Basis()
		var origin := Vector3(cx, 0, front)
		var half := tw * 0.5
		if face == 1:
			basis = Basis(Vector3.UP, -s * PI * 0.5)
			origin = Vector3(cx - s * tw * 0.5, 0, (front + back) * 0.5)
			half = d * 0.5
		elif face == 2:
			basis = Basis(Vector3.UP, s * PI * 0.5)
			origin = Vector3(cx + s * tw * 0.5, 0, (front + back) * 0.5)
			half = d * 0.5
		var fxf := xf * Transform3D(basis, origin)
		_tint(c.s, stone_c)
		for k: float in [-1.0, 1.0]:
			var pts: Array = [Vector3(k * half, y1, 0), Vector3(k * half, y0, 0), Vector3(k * r, y0, 0)]
			for j in 9:
				var t := PI * 0.5 * j / 8.0 if k > 0.0 else PI - PI * 0.5 * j / 8.0
				pts.append(Vector3(cos(t) * r, spring + sin(t) * r, 0))
			pts.append(Vector3(0, y1, 0))
			_face(c.s, fxf, [pts[0], pts[1], pts[2]], Vector3.BACK)
			var fan: Array = [pts[0]]
			fan.append_array(pts.slice(2))
			_face(c.s, fxf, fan, Vector3.BACK)
		_tint(c.s, stone_c * 0.7)
		Shapes.arch(c.s, fxf * Vector3(0, spring, -0.2), r, r, 0.4, 8, fxf.basis, 0.0, PI, ["inner"])
		for k: float in [-1.0, 1.0]:
			_face(c.s, fxf, [Vector3(k * r, y0, 0), Vector3(k * r, y0, -0.4), Vector3(k * r, spring, -0.4),
					Vector3(k * r, spring, 0)], Vector3(-k, 0, 0))
	# The dark inside: a back wall, the floor, the ceiling.
	_tint(c.s, stone_c * 0.18)
	_face(c.s, xf, [Vector3(cx - tw * 0.5 + 0.4, y0, back + 0.4), Vector3(cx + tw * 0.5 - 0.4, y0, back + 0.4),
			Vector3(cx + tw * 0.5 - 0.4, y1, back + 0.4), Vector3(cx - tw * 0.5 + 0.4, y1, back + 0.4)], Vector3.BACK)
	_face(c.s, xf, [Vector3(cx - tw * 0.5, y1 - 0.01, front), Vector3(cx + tw * 0.5, y1 - 0.01, front),
			Vector3(cx + tw * 0.5, y1 - 0.01, back), Vector3(cx - tw * 0.5, y1 - 0.01, back)], Vector3.DOWN)
	_face(c.s, xf, [Vector3(cx - tw * 0.5, y0 + 0.01, front), Vector3(cx + tw * 0.5, y0 + 0.01, front),
			Vector3(cx + tw * 0.5, y0 + 0.01, back), Vector3(cx - tw * 0.5, y0 + 0.01, back)], Vector3.UP)
	# The bell, dark bronze, on its beam.
	c.u.surface(c.soft("iron", false))
	var bc := Vector3(cx, spring + r * 0.55, (front + back) * 0.5)
	_lathe(c.u, xf, [Vector2(0.42, -0.62), Vector2(0.38, -0.55), Vector2(0.3, -0.4), Vector2(0.26, -0.1),
			Vector2(0.22, 0.05), Vector2(0.12, 0.12), Vector2(0.0, 0.14)], bc, 10)
	_beam(c.u, xf, bc + Vector3(-tw * 0.5 + 0.3, 0.2, 0), bc + Vector3(tw * 0.5 - 0.3, 0.2, 0), Vector2(0.12, 0.12))


## The drapes in the great arch: velvet falling from under the arch's band either side of the picture, gathered by a
## gilt cord and spreading again to the stage; swags along the arch's top, each a curve of velvet with a gilt fringe.
static func _drapes(c: Object, xf: Transform3D, ox: float, spring: float, arch_c: Vector3, radius: float, a0: float,
		pic_top: float, front: float) -> void:
	c.u.surface(c.soft("drapes", false))
	var z := front - 0.65
	var edge := ox - 0.02
	for s: float in [-1.0, 1.0]:
		var outer := PackedVector3Array()
		var inner := PackedVector3Array()
		var ns := PackedVector3Array()
		var top := spring + 0.05
		var tie := 0.0 + (spring) * 0.42
		var n := 14
		for k in n + 1:
			var t := float(k) / n
			var y := lerpf(top, 0.0, t)
			# The drape's width: full at the top, pinched at the cord, spreading a little to the floor.
			var wid := 0.62
			if y > tie:
				wid = lerpf(0.26, 0.62, smoothstep(tie, top, y))
			else:
				wid = lerpf(0.26, 0.44, smoothstep(tie, 0.0, y))
			outer.append(xf * Vector3(s * edge, y, z))
			inner.append(xf * Vector3(s * (edge - wid), y, z + 0.1 * (1.0 - absf(y - tie) / top)))
			ns.append((xf.basis * Vector3.BACK).normalized())
		if s < 0.0:
			c.u.strip(outer, inner, ns)
		else:
			c.u.strip(inner, outer, ns)
		# The cord: a gilt roll round the waist, a tassel.
		c.u.surface(c.soft("gilt", false))
		_tint(c.u, Color.WHITE)
		_beam(c.u, xf, Vector3(s * edge, tie, z + 0.05), Vector3(s * (edge - 0.3), tie, z + 0.14), Vector2(0.07, 0.07))
		_lathe(c.u, xf, [Vector2(0.0, -0.3), Vector2(0.06, -0.26), Vector2(0.05, -0.05), Vector2(0.025, 0.0)],
				Vector3(s * (edge - 0.3), tie - 0.02, z + 0.16), 6)
		c.u.surface(c.soft("drapes", false))
	# The swags: three along the arch's soffit, each hanging in a curve below it.
	var swags := 3
	var x0 := -ox + 0.1
	var x1 := ox - 0.1
	var drop_min := pic_top + 0.25
	for k in swags:
		var a := lerpf(x0, x1, float(k) / swags)
		var b := lerpf(x0, x1, float(k + 1) / swags)
		var top_line := PackedVector3Array()
		var low_line := PackedVector3Array()
		var ns := PackedVector3Array()
		var n := 10
		for j in n + 1:
			var x := lerpf(a, b, float(j) / n)
			var arch_y := arch_c.y + sqrt(maxf(radius * radius - x * x, 0.0)) - 0.02
			var sag := sin(PI * float(j) / n)
			var low := maxf(arch_y - 0.35 - 0.75 * sag, drop_min)
			top_line.append(xf * Vector3(x, arch_y + 0.03, z + 0.05))
			low_line.append(xf * Vector3(x, low, z + 0.05 + 0.12 * sag))
			ns.append((xf.basis * Vector3(0, -0.3 * sag, 1).normalized()).normalized())
		c.u.strip(low_line, top_line, ns)
		c.u.surface(c.soft("gilt", false))
		_tint(c.u, Color.WHITE)
		for j in n:
			_beam(c.u, xf, xf.affine_inverse() * low_line[j] + Vector3(0, -0.02, 0.01),
					xf.affine_inverse() * low_line[j + 1] + Vector3(0, -0.02, 0.01), Vector2(0.05, 0.05))
		c.u.surface(c.soft("drapes", false))
	# A tassel where the swags meet.
	c.u.surface(c.soft("gilt", false))
	for k in swags + 1:
		var x := lerpf(x0, x1, float(k) / swags)
		var arch_y := arch_c.y + sqrt(maxf(radius * radius - x * x, 0.0)) - 0.35
		_lathe(c.u, xf, [Vector2(0.0, -0.38), Vector2(0.07, -0.32), Vector2(0.05, -0.08), Vector2(0.03, 0.0)],
				Vector3(x, arch_y, z + 0.1), 6)


# --- Pedestals and trees ------------------------------------------------------------------------------------------------

## A stone pedestal (a base, a die with a panel, a cornice) holding a lion lying with its head up, or an urn.
static func _pedestal(c: Object, xf: Transform3D, size: Vector3, e: Dictionary) -> void:
	var colour := _colour(e, "colour", Color(0.84, 0.76, 0.62))
	var w := size.x
	var h := size.y
	var d := size.z
	c.s.surface(c.tinted("stone", "ashlar"))
	_tint(c.s, colour)
	_box(c.s, xf, Vector3(0, 0.1, 0), Vector3(w + 0.16, 0.2, d + 0.16), Basis(), [RoomMesh.DOWN])
	_box(c.s, xf, Vector3(0, h * 0.5, 0), Vector3(w, h - 0.2, d), Basis(), [RoomMesh.DOWN])
	_box(c.s, xf, Vector3(0, h - 0.06, 0), Vector3(w + 0.14, 0.12, d + 0.14))
	c.u.surface(c.soft("stone"))
	_tint(c.u, colour * 0.9)
	_face(c.u, xf, [Vector3(-w * 0.32, 0.35, d * 0.5 + 0.005), Vector3(w * 0.32, 0.35, d * 0.5 + 0.005),
			Vector3(w * 0.32, h - 0.3, d * 0.5 + 0.005), Vector3(-w * 0.32, h - 0.3, d * 0.5 + 0.005)], Vector3.BACK)
	if str(e.get("holds", "lion")) == "urn":
		_urn(c, xf, Vector3(0, h, 0), 2.0, colour)
	else:
		_lion(c, xf, Vector3(0, h, -0.05), 1.15, colour)
	_solid(c, xf, Vector3(0, h * 0.5 + 0.3, 0), Vector3(w, h + 0.6, d))


## A cypress: a tall flame of dark foliage, its edge broken into clumps, a little trunk at its foot.
static func _cypress(c: Object, xf: Transform3D, size: Vector3, e: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(e.get("seed", 3)) * 31 + 5
	var h := size.y
	var r := size.x * 0.5
	var green := _colour(e, "colour", Color(0.1, 0.17, 0.09))
	c.u.surface(c.soft("leaves"))
	var rings := 16
	var sides := 9
	var prev := PackedVector3Array()
	var prev_n := PackedVector3Array()
	for i in rings + 1:
		var t := float(i) / rings
		var rr := r * pow(sin(PI * clampf(t * 0.92 + 0.04, 0.0, 1.0)), 0.75) * (1.0 - 0.55 * t) * (0.85 + 0.3 * rng.randf())
		var y := 0.6 + (h - 0.6) * t
		var ring := PackedVector3Array()
		var rn := PackedVector3Array()
		for k in sides + 1:
			var a := TAU * (k % sides) / sides + i * 0.37
			var jitter := 0.75 + 0.5 * rng.randf() if k < sides else 0.0
			if k == sides:
				ring.append(ring[0])
				rn.append(rn[0])
				continue
			var p := Vector3(sin(a) * rr * jitter, y + rng.randf_range(-0.1, 0.1), cos(a) * rr * jitter)
			ring.append(xf * p)
			rn.append((xf.basis * Vector3(sin(a), 0.25, cos(a))).normalized())
		if i > 0:
			_tint(c.u, green * (0.75 + 0.5 * t) * rng.randf_range(0.9, 1.1))
			c.u.strip(prev, ring, rn)
		prev = ring
		prev_n = rn
	c.u.surface(c.soft("wood"))
	_tint(c.u, Color(0.22, 0.16, 0.11))
	_lathe(c.u, xf, [Vector2(0.14, -1.0), Vector2(0.1, 0.8)], Vector3.ZERO, 6)


## A palm: a tall, slightly leaning, ringed trunk and a crown of arching feather fronds.
static func _palm(c: Object, xf: Transform3D, size: Vector3, e: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(e.get("seed", 5)) * 17 + 3
	var h := size.y
	var lean := Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6))
	c.u.surface(c.soft("wood"))
	var segs := 10
	var prev := Vector3.ZERO
	for i in range(1, segs + 1):
		var t := float(i) / segs
		var p := Vector3(lean.x * t * t, h * t, lean.z * t * t)
		_tint(c.u, Color(0.36, 0.3, 0.22) * (0.8 + 0.25 * float(i % 2)))
		var r0 := lerpf(0.26, 0.17, float(i - 1) / segs)
		var r1 := lerpf(0.26, 0.17, t)
		_lathe(c.u, xf, [Vector2(r0, 0.0), Vector2(r1 * 1.08, (p - prev).length() * 0.85), Vector2(r1, (p - prev).length())],
				prev, 7, _towards(p - prev))
		prev = p
	var top := prev
	c.u.surface(c.soft("leaves"))
	var fronds := 15
	for f in fronds:
		var az := TAU * f / fronds + rng.randf_range(-0.15, 0.15)
		var up := rng.randf_range(-0.15, 0.75)
		var length := size.x * 0.5 * rng.randf_range(0.8, 1.1)
		var out := Vector3(sin(az), 0, cos(az))
		var side := out.cross(Vector3.UP).normalized()
		var n := 8
		var last := top
		for j in range(1, n + 1):
			var t := float(j) / n
			var p := top + out * length * t + Vector3.UP * (length * (up * t - 0.55 * t * t))
			var along := p - last
			var leaflet := length * 0.22 * sin(PI * clampf(t * 0.9 + 0.1, 0.0, 1.0))
			_tint(c.u, Color(0.2, 0.32, 0.12) * rng.randf_range(0.8, 1.15))
			for s: float in [-1.0, 1.0]:
				var tip := last.lerp(p, 0.5) + side * s * leaflet + Vector3.DOWN * leaflet * 0.55
				var nn := (along.cross(tip - last)).normalized()
				for flip: float in [1.0, -1.0]:
					_face(c.u, xf, [last, p, tip], nn * flip)
			last = p
	c.u.surface(c.soft("wood"))
	_tint(c.u, Color(0.3, 0.24, 0.16))
	_lathe(c.u, xf, [Vector2(0.2, -0.1), Vector2(0.3, 0.15), Vector2(0.12, 0.45)], top - Vector3(0, 0.15, 0), 7)


## A stone pine: a bare, leaning trunk forking into limbs, and a broad flat crown of dark clumps.
static func _pine(c: Object, xf: Transform3D, size: Vector3, e: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(e.get("seed", 9)) * 13 + 1
	var h := size.y
	var spread := size.x * 0.5
	c.u.surface(c.soft("wood"))
	_tint(c.u, Color(0.3, 0.22, 0.17))
	var fork := Vector3(rng.randf_range(-0.5, 0.5), h * 0.62, rng.randf_range(-0.5, 0.5))
	_lathe(c.u, xf, [Vector2(0.32, -1.0), Vector2(0.24, fork.length())], Vector3.ZERO, 7, _towards(fork))
	var heads: Array[Vector3] = []
	for k in 4:
		var a := TAU * k / 4.0 + rng.randf_range(-0.4, 0.4)
		var head := fork + Vector3(sin(a) * spread * 0.55, h * 0.26 + rng.randf_range(-0.4, 0.4), cos(a) * spread * 0.55)
		_lathe(c.u, xf, [Vector2(0.12, 0.0), Vector2(0.06, (head - fork).length())], fork, 5, _towards(head - fork))
		heads.append(head)
	c.u.surface(c.soft("leaves"))
	heads.append(fork + Vector3(0, h * 0.36, 0))
	# Each limb's head a canopy of small flattened lumps of foliage (closed: their undersides show from below), so the
	# crown's edge and underside break up as a stone pine's do; lighter on top, where the sky's light falls.
	for head: Vector3 in heads:
		var rr := spread * rng.randf_range(0.42, 0.56)
		for j in 7:
			var a := TAU * j / 7.0 + rng.randf() * 0.6
			var off := Vector3(sin(a), 0, cos(a)) * rr * rng.randf_range(0.25, 0.62) + Vector3(0, rng.randf_range(-0.3, 0.35), 0)
			if j == 0:
				off = Vector3(0, 0.25, 0)
			var cr := rr * rng.randf_range(0.42, 0.58)
			var prof: Array = []
			for i in 7:
				var t := float(i) / 6.0
				var ang := lerpf(-PI * 0.5, PI * 0.5, t)
				var rim := 0.82 + 0.36 * rng.randf() if i > 0 and i < 6 else 1.0
				prof.append(Vector2(cos(ang) * cr * rim, sin(ang) * cr * (0.3 if ang < 0.0 else 0.42)))
			_tint(c.u, Color(0.13, 0.21, 0.1) * rng.randf_range(0.8, 1.2))
			_lathe(c.u, xf, prof, head + off, 8, Basis(Vector3.UP, rng.randf() * TAU))


## A basis whose Y is along `dir` (a trunk's segment, a limb).
static func _towards(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var x := Vector3.FORWARD.cross(y)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)
