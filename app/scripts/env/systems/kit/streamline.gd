extends RefCounted

## The streamline picture house's pieces (docs/environments.md, "The kit" and "Room: Streamline 1937"; since 2026-11-08,
## "continue working on the environments one-by-one ... really improving their quality, imagination, delight, detail,
## lighting and so on. Better to do a smaller number of incredible superb ones than a large number not so", the user,
## 2026-11-08). A 1937 moderne cinema: horizontal speed and curves. The ceiling rises towards the screen in stepped
## bands, each stepping over the next with a hidden lamp in the slot between, so the plaster glows in a soft graded
## colour from every step and along both walls (the coves: shaders/env_cove.gdshader); a stepped proscenium of three
## receding frames with rounded shoulders, each lit from behind the next, gilt in their reveals, a glowing rising sun
## over the picture with gilt rays; organ grilles lit from the chambers behind, a clock with chevrons and a speed-line
## roundel; bands of cream and jade faience and chrome that run the length of both walls, round the back and across a
## curved circle front; reeded pilasters under the steps, etched glass shell lights, a walnut dado; and the organ
## console that rises from the pit on its lift, ivory and gilt with illuminated glass. Everything is ours, drawn here
## from strips, grids and boxes; no figure anywhere, nothing borrowed.
##
## Pieces (pieces.gd dispatches here):
##   moderne_hall    the walls and the ceiling of an auditorium builder's hall: no slot, at [0, 0, 0]
##   ziggurat        the proscenium round the room's screen, its grilles, clock, roundel and sunburst: no slot
##   organ_console   the console on its lift platform, its foot at `at` (put it in a kit of its own with `group`, so a
##                   motion system lifts it whole)
##
## Cost: the parts go into the kit's shared meshes by material: baked (PieceStatic) the plaster of the pilasters,
## ledges, fillets and the dado's walnut; unbaked (PieceSoft) the faience and chrome (they reflect: kit/reflect.gd) and
## the gilt; PieceLamps the shell lights' glass and the downlights; PieceCove every surface a cove lights (the ceiling,
## the frames, the grilles' chambers, the sun, the console's glass); PieceClock the clock's face.
## Colours: per vertex (linear), so cream, jade and ivory share one draw.

const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const Shapes := preload("res://scripts/env/systems/kit/shapes.gd")
const PhysicsShapes := preload("res://scripts/play/physics_shapes.gd")
const Auditorium := preload("res://scripts/env/systems/auditorium.gd")

## The ceiling: where it steps (z, from the screen back) and each band's height, front to back. It rises 0.6 m a
## step towards the screen, so every slot faces the seats and shows the lit plaster beyond it.
const STEPS: Array[float] = [-8.6, -4.2, 0.2, 4.0]
const BAND_Y: Array[float] = [8.8, 8.2, 7.6, 7.0, 6.4]
## The bands round down into the side walls in a quarter round this big; a ledge under it hides its lamp.
const WALL_ROUND := 0.9
## The rear corners are rounded this much (a fillet of plaster the bands run round).
const CORNER := 0.35
## The circle front: half its width, how far it bows out from the rear wall, its soffit and its top.
const BOW_HALF := 6.6
const BOW_DEPTH := 1.3
const BOW_LOW := 3.7
const BOW_TOP := 5.0
## The speed bands' height on the walls (the faience, jade and chrome stack's foot).
const BAND_FOOT := 4.1
## The proscenium: its three frames' depths in front of the screen, the first opening round the picture (a margin
## past its sides and over its top) and how much each frame steps out.
const FRAME_Z: Array[float] = [0.5, 0.8, 1.1]
const OPEN_SIDE := 0.55
const OPEN_TOP := 0.35
const FRAME_STEP := 0.4
const SHOULDER := 1.0

const CREAM := Color(0.86, 0.79, 0.64)
const FAIENCE := Color(0.93, 0.87, 0.72)
const JADE := Color(0.1, 0.33, 0.27)
const IVORY := Color(0.93, 0.89, 0.8)
const PLASTER := Color(0.66, 0.53, 0.41)
const WALNUT := Color(0.24, 0.14, 0.08)
const SHELL_GLOW := Color(1.0, 0.8, 0.56)


static func build(piece: String, c: Object, xf: Transform3D, size: Vector3, e: Dictionary) -> void:
	match piece:
		"moderne_hall":
			_hall(c, e)
		"ziggurat":
			_ziggurat(c, e)
		"organ_console":
			_console(c, xf, e)
	_white(c)


# --- Helpers ----------------------------------------------------------------------------------------------------------

static func _white(c: Object) -> void:
	for b: RoomMesh in [c.s, c.u, c.lit, c.cove]:
		b.colour = Color.WHITE


static func _lin(colour: Color, alpha := 1.0) -> Color:
	var l := colour.srgb_to_linear()
	return Color(l.r, l.g, l.b, clampf(alpha, 0.0, 1.0))


static func _layout(c: Object) -> Auditorium.Layout:
	return Auditorium.layout(c.builder_params)


## The light a lamp along a line (through `lamp`, along `axis`) gives a point facing n: the cosine (softened: plaster
## scatters) over the distance's fall-off, `reach` metres to half.
static func _lamp_w(p: Vector3, n: Vector3, lamp: Vector3, axis: Vector3, reach: float) -> float:
	var d := lamp - p
	d -= axis * d.dot(axis)
	var l := d.length()
	if l < 0.001:
		return 1.0
	var k := maxf(n.dot(d / l), 0.0)
	return pow(k, 0.6) / (1.0 + (l / reach) * (l / reach))


## A sweep along a path: rows of the profile's points, each row the path offset by (out, up) amounts; normals per
## point. path: points; outs: the outward direction at each point (mitre-scaled at a sharp corner); profile: [Vector2
## (out, up)], pnormals: [Vector2 (out, up)] one per profile point. colours: one per profile point (or none).
static func _sweep(b: RoomMesh, path: PackedVector3Array, outs: Array, profile: Array, pnormals: Array,
		colours: Array = []) -> void:
	var rows: Array = []
	var norms: Array = []
	var cols: Array = []
	for k in profile.size():
		var pr: Vector2 = profile[k]
		var pn: Vector2 = pnormals[k]
		var row := PackedVector3Array()
		var nrow := PackedVector3Array()
		var crow := PackedColorArray()
		for j in path.size():
			var o: Vector3 = outs[j]
			var on := Vector3(o.x, 0.0, o.z).normalized()
			row.append(path[j] + o * pr.x + Vector3.UP * pr.y)
			nrow.append((on * pn.x + Vector3.UP * pn.y).normalized())
			if not colours.is_empty():
				crow.append(colours[k])
		rows.append(row)
		norms.append(nrow)
		cols.append(crow)
	b.grid(rows, norms, cols if not colours.is_empty() else [])


## A flat face swept along a path, from (out, up) a to c, facing n (out, up).
static func _sweep_face(b: RoomMesh, path: PackedVector3Array, outs: Array, a: Vector2, c2: Vector2, n: Vector2) -> void:
	_sweep(b, path, outs, [a, c2], [n, n])


## A round bead swept along a path: its centre at (out, up), from angle a0 to a1 (0: straight out, PI/2: up).
static func _sweep_round(b: RoomMesh, path: PackedVector3Array, outs: Array, centre: Vector2, r: float, a0: float,
		a1: float, segs := 4) -> void:
	var prof: Array = []
	var nrm: Array = []
	for k in segs + 1:
		var a := lerpf(a0, a1, float(k) / segs)
		var d := Vector2(cos(a), sin(a))
		prof.append(centre + d * r)
		nrm.append(d)
	_sweep(b, path, outs, prof, nrm)


static func _box(b: RoomMesh, xf: Transform3D, centre: Vector3, size: Vector3, skip: Array = []) -> void:
	b.box(xf * centre, size, xf.basis, skip)


static func _solid(c: Object, xf: Transform3D, centre: Vector3, size: Vector3) -> void:
	c.shapes.append(PhysicsShapes.box(xf * centre, size, xf.basis.orthonormalized()))


## A wall's frame: x along the wall, y up, z out of it into the room; origin at p.
static func _wall_xf(p: Vector3, out: Vector3) -> Transform3D:
	return Transform3D(Basis(Vector3.UP.cross(out), Vector3.UP, out), p)


## The ceiling's drop at x: 0 over the middle, down a quarter round into each side wall.
static func _drop(x: float, w: float) -> float:
	var e := absf(x) - (w - WALL_ROUND)
	if e <= 0.0:
		return 0.0
	e = minf(e, WALL_ROUND)
	return -WALL_ROUND + sqrt(WALL_ROUND * WALL_ROUND - e * e)


## The ceiling's normal (into the room) at x.
static func _drop_normal(x: float, w: float) -> Vector3:
	var e := absf(x) - (w - WALL_ROUND)
	if e <= 0.0:
		return Vector3.DOWN
	var s := signf(x)
	return Vector3(s * (w - WALL_ROUND) - x, -WALL_ROUND - _drop(x, w), 0.0).normalized()


## Across the hall: the quarter rounds closely, the middle more sparsely (the light's gradient is near the walls).
static func _xs(w: float) -> Array[float]:
	var out: Array[float] = []
	for k in 7:
		out.append(-(w - WALL_ROUND) - WALL_ROUND * cos(PI * 0.5 * k / 6.0))
	for x: float in [-8.2, -7.3, -6.0, -4.0, -2.0, 0.0, 2.0, 4.0, 6.0, 7.3, 8.2]:
		out.append(x * w / 9.6)
	for k in range(5, -1, -1):
		out.append(w - WALL_ROUND + WALL_ROUND * cos(PI * 0.5 * k / 6.0))
	return out


## The ledge under band i along the side walls: its top (the lamp lies on it, behind its lip).
static func _ledge_y(i: int) -> float:
	return BAND_Y[i] - WALL_ROUND - 0.1


## The rake's line along the side aisles: the pit's floor, then up the steps to the rear walkway (the dado follows it).
static func _rake(l: Auditorium.Layout, z: float) -> float:
	var z0 := l.arc_z(l.row_radius(l.rows_front) - l.depth * 0.5, l.block_x)
	var z1 := l.arc_z(l.row_radius(-l.rows_back) + l.depth * 0.5, l.block_x)
	var y1 := l.row_floor(-l.rows_back)
	if z <= z0:
		return l.lo.y
	if z >= z1:
		return y1
	return lerpf(l.lo.y, y1, (z - z0) / (z1 - z0))


## The proscenium's outer face (the frontmost frame), in the room's z.
static func _pros_z(c: Object) -> float:
	var xf: Transform3D = c.screen.get("xf", Transform3D())
	return xf.origin.z + FRAME_Z[2]


# --- The hall: walls, ceiling, circle front -------------------------------------------------------------------------

static func _hall(c: Object, _e: Dictionary) -> void:
	var l := _layout(c)
	var w := l.hi.x
	var pros := _pros_z(c)
	_ceiling(c, l, w, pros)
	_ventilators(c, pros)
	_ledges(c, l, w, pros)
	_bands(c, l, w, pros)
	_circle_front(c, l, w)
	_fillets(c, l, w)
	_dado(c, l, w, pros)
	_pilasters(c, l, w)
	_shell_lights(c, l, w, pros)


## The ceiling's bands, each stepping 0.6 m over the next towards the screen. In each slot a lamp lies on the lower
## band's back and washes the higher band's plaster: brightest at the slot, gone in two metres. Along the walls each
## band rounds down into a ledge whose lamp washes the round. Over the proscenium a drop beam hides a lamp that washes
## the proscenium's head. All of it PieceCove, the light worked out here per vertex.
static func _ceiling(c: Object, l: Auditorium.Layout, w: float, pros: float) -> void:
	var b: RoomMesh = c.cove
	b.surface(c.kit.cove_material())
	var xs := _xs(w)
	var rz := l.hi.z
	var n_bands := BAND_Y.size()
	for i in n_bands:
		var y := BAND_Y[i]
		var z_front := pros if i == 0 else STEPS[i - 1]
		var z_rear := STEPS[i] + 0.4 if i < n_bands - 1 else rz
		var zs: Array[float] = []
		var z := z_front
		var dense: Array[float] = []
		if i == 0:
			dense.append_array([pros + 0.25, pros + 0.5, pros + 0.8, pros + 1.2, pros + 1.8])
		if i < n_bands - 1:
			var s := STEPS[i]
			dense.append_array([s - 2.6, s - 1.8, s - 1.2, s - 0.75, s - 0.4, s - 0.15, s, s + 0.2])
		zs.append(z_front)
		var step := 0.9
		while z + step < z_rear - 0.05:
			z += step
			zs.append(z)
		for d: float in dense:
			if d > z_front + 0.05 and d < z_rear - 0.05:
				zs.append(d)
		zs.append(z_rear)
		zs.sort()
		var clean: Array[float] = []
		for v in zs:
			if clean.is_empty() or v - clean[-1] > 0.04:
				clean.append(v)
		var rows: Array = []
		var norms: Array = []
		var cols: Array = []
		for zz in clean:
			var row := PackedVector3Array()
			var nrow := PackedVector3Array()
			var crow := PackedColorArray()
			for x in xs:
				var p := Vector3(x, y + _drop(x, w), zz)
				var n := _drop_normal(x, w)
				row.append(p)
				nrow.append(n)
				crow.append(_lin(CREAM, _band_light(i, p, n, w, pros)))
			rows.append(row)
			norms.append(nrow)
			cols.append(crow)
		b.grid(rows, norms, cols)
		if i > 0:
			# The lower band's lip at the step in front of it (faces the screen: the front rows see it).
			_x_face(b, xs, w, STEPS[i - 1], y, y + 0.22, Vector3.FORWARD, _lin(CREAM, 0.04))
		if i < n_bands - 1:
			var s := STEPS[i]
			var lower := BAND_Y[i + 1]
			# The slot: the trough's floor on the lower band and its back, both close to the lamp.
			var fa := PackedVector3Array()
			var fb := PackedVector3Array()
			for x in xs:
				fa.append(Vector3(x, lower + 0.22 + _drop(x, w), s))
				fb.append(Vector3(x, lower + 0.22 + _drop(x, w), s + 0.4))
			b.colour = _lin(CREAM, 0.35)
			_pair(b, fa, fb, Vector3.UP)
			_x_face(b, xs, w, s + 0.4, lower + 0.22, y, Vector3.FORWARD, _lin(CREAM, 0.85))
	# The drop beam over the proscenium: it hides the lamp that washes the proscenium's head.
	var beam_z := pros + 0.5
	_x_face(b, xs, w, beam_z, BAND_Y[0] - 0.42, BAND_Y[0], Vector3.BACK, _lin(CREAM, 0.03))
	var ua := PackedVector3Array()
	var ub := PackedVector3Array()
	for x in xs:
		ua.append(Vector3(x, BAND_Y[0] - 0.42 + _drop(x, w), beam_z))
		ub.append(Vector3(x, BAND_Y[0] - 0.42 + _drop(x, w), beam_z - 0.14))
	b.colour = _lin(CREAM, 0.05)
	_pair(b, ua, ub, Vector3.DOWN)
	# The beam's chrome edge.
	var chrome: Material = c.shiny("chrome", 1.0, 1.0, 0.08)
	c.u.surface(chrome)
	c.u.colour = _lin(Color(0.86, 0.86, 0.88))
	var edge := PackedVector3Array()
	var outs: Array = []
	for x in xs:
		edge.append(Vector3(x, BAND_Y[0] - 0.42 + _drop(x, w), beam_z))
		outs.append(Vector3.BACK)
	_sweep_round(c.u, edge, outs, Vector2(0.0, 0.0), 0.03, -PI * 0.5, PI * 0.5, 4)
	b.colour = Color.WHITE


## A ventilator in the middle of each band but the last: a round gilt grille, twenty fins round a boss, over a dark
## throat (the hall's air drawn up through the ceiling, as every picture house of the time had it).
static func _ventilators(c: Object, pros: float) -> void:
	var gilt: Material = c.soft("gilt")
	for i in STEPS.size():
		var z0 := pros if i == 0 else STEPS[i - 1]
		var at := Vector3(0.0, BAND_Y[i] - 0.004, (z0 + STEPS[i]) * 0.5 - 0.3)
		c.u.surface(gilt)
		c.u.colour = _lin(Color(0.04, 0.035, 0.03))
		var disc: Array = []
		for k in 24:
			var a := TAU * k / 24.0
			disc.append(at + Vector3(cos(a), 0.0, sin(a)) * 0.72)
		c.u.face(disc, Vector3.DOWN)
		c.u.colour = _lin(Color(1.0, 0.9, 0.72))
		var inner := PackedVector3Array()
		var outer := PackedVector3Array()
		var lip := PackedVector3Array()
		var nn := PackedVector3Array()
		var side := PackedVector3Array()
		for k in 33:
			var a := TAU * k / 32.0
			var d := Vector3(cos(a), 0.0, sin(a))
			inner.append(at + d * 0.7 + Vector3.DOWN * 0.05)
			outer.append(at + d * 0.82 + Vector3.DOWN * 0.05)
			lip.append(at + d * 0.82)
			nn.append(Vector3.DOWN)
			side.append(d)
		c.u.grid([inner, outer], [nn, nn])
		c.u.grid([outer, lip], [side, side])
		for k in 20:
			var a := TAU * (k + 0.5) / 20.0
			var d := Vector3(cos(a), 0.0, sin(a))
			Shapes.beam(c.u, at + d * 0.2 + Vector3.DOWN * 0.03, at + d * 0.7 + Vector3.DOWN * 0.03, Vector2(0.03, 0.05),
					Vector3.DOWN)
		var boss: Array = []
		for k in 16:
			var a := TAU * k / 16.0
			boss.append(at + Vector3(cos(a), 0.0, sin(a)) * 0.2 + Vector3.DOWN * 0.06)
		c.u.face(boss, Vector3.DOWN)


## A band's light at a point: its slot's lamp behind it, the drop beam's over the proscenium (band 0), and the ledges'
## along the walls.
static func _band_light(i: int, p: Vector3, n: Vector3, w: float, pros: float) -> float:
	var k := 0.0
	if i < BAND_Y.size() - 1:
		var lamp := Vector3(0.0, BAND_Y[i + 1] + 0.3, STEPS[i] + 0.12)
		k += 1.25 * _lamp_w(p, n, lamp, Vector3.RIGHT, 1.5)
		# The plaster's own scatter: a broad, faint glow a few metres on from the slot.
		k += 0.16 * exp(-maxf(STEPS[i] - p.z, 0.0) / 2.2) * float(p.z < STEPS[i] + 0.45)
	if i == 0:
		var lamp := Vector3(0.0, BAND_Y[0] - 0.1, pros + 0.3)
		k += 0.9 * _lamp_w(p, n, lamp, Vector3.RIGHT, 1.0)
	var ly := _ledge_y(i) + 0.06
	for s: float in [-1.0, 1.0]:
		k += 1.1 * _lamp_w(p, n, Vector3(s * (w - 0.14), ly, 0.0), Vector3.BACK, 0.8)
	return clampf(k, 0.0, 1.0)


## A vertical face across the hall at z, from y0 to y1 over the ceiling's line (it follows the round at the walls).
static func _x_face(b: RoomMesh, xs: Array[float], w: float, z: float, y0: float, y1: float, facing: Vector3,
		colour: Color) -> void:
	var ra := PackedVector3Array()
	var rb := PackedVector3Array()
	for x in xs:
		var d := _drop(x, w)
		ra.append(Vector3(x, y0 + d, z))
		rb.append(Vector3(x, y1 + d, z))
	b.colour = colour
	_pair(b, ra, rb, facing)


## Two rows of points as a smooth surface facing n (the mesh's colour now).
static func _pair(b: RoomMesh, ra: PackedVector3Array, rb: PackedVector3Array, n: Vector3) -> void:
	var na := PackedVector3Array()
	na.resize(ra.size())
	na.fill(n)
	b.grid([ra, rb], [na, na])


## The ledges along the side walls under each band: plaster underneath, a faience lip with a chrome bead (the lamp lies
## behind the lip).
static func _ledges(c: Object, l: Auditorium.Layout, w: float, pros: float) -> void:
	var faience: Material = c.shiny("faience", 0.0, 0.3, 0.12)
	var chrome: Material = c.shiny("chrome", 1.0, 1.0, 0.08)
	var plaster: Material = c.tinted("plaster")
	for i in BAND_Y.size():
		var z0 := pros if i == 0 else STEPS[i - 1]
		var z1 := STEPS[i] if i < BAND_Y.size() - 1 else l.hi.z - CORNER
		var y := _ledge_y(i)
		for s: float in [-1.0, 1.0]:
			var out := Vector3(-s, 0, 0)
			var path := PackedVector3Array([Vector3(s * w, y, z0), Vector3(s * w, y, z1)])
			var outs := [out, out]
			c.s.surface(plaster)
			c.s.colour = _lin(CREAM)
			c.s.face([Vector3(s * w, y - 0.14, z0), Vector3(s * (w - 0.3), y - 0.14, z0),
					Vector3(s * (w - 0.3), y - 0.14, z1), Vector3(s * w, y - 0.14, z1)], Vector3.DOWN)
			for zz: float in [z0, z1]:
				c.s.face([Vector3(s * w, y - 0.14, zz), Vector3(s * (w - 0.3), y - 0.14, zz),
						Vector3(s * (w - 0.3), y + 0.1, zz), Vector3(s * w, y + 0.1, zz)],
						Vector3.FORWARD if zz == z0 else Vector3.BACK)
			c.u.surface(faience)
			c.u.colour = _lin(FAIENCE)
			_sweep_face(c.u, path, outs, Vector2(0.3, -0.14), Vector2(0.3, 0.1), Vector2(1, 0))
			_sweep_face(c.u, path, outs, Vector2(0.3, 0.1), Vector2(0.2, 0.1), Vector2(0, 1))
			c.u.surface(chrome)
			c.u.colour = _lin(Color(0.86, 0.86, 0.88))
			_sweep_round(c.u, path, outs, Vector2(0.3, -0.14), 0.025, -PI * 0.5, PI * 0.5, 4)
			c.shapes.append(PhysicsShapes.box(Vector3(s * (w - 0.15), y - 0.02, (z0 + z1) * 0.5),
					Vector3(0.3, 0.24, absf(z1 - z0)), Basis()))
			# For the bake: the glowing round over the ledge throws a soft light down the upper wall.
			c.glow_lights.append([Vector3(s * (w - 0.9), y - 0.5, (z0 + z1) * 0.5), Color(1.0, 0.8, 0.56), 0.35, 4.0])


## The speed bands' path: from over the organ grille on the proscenium's face, along the side wall, round the rear
## corner, along the rear wall to the circle front, across its bow, and back the other side. [points, outs].
static func _band_path(w: float, pros: float, rz: float, face_end: float) -> Array:
	var pts := PackedVector3Array()
	var outs: Array = []
	var arc := 8
	# Left: the proscenium's face, mitred into the side wall.
	pts.append(Vector3(-face_end, 0, pros + 0.0))
	outs.append(Vector3(0, 0, 1))
	pts.append(Vector3(-w, 0, pros))
	outs.append(Vector3(1, 0, 1))
	pts.append(Vector3(-w, 0, rz - CORNER))
	outs.append(Vector3(1, 0, 0))
	for k in range(1, arc):
		var a := PI * 0.5 * k / arc
		pts.append(Vector3(-w + CORNER - cos(a) * CORNER, 0, rz - CORNER + sin(a) * CORNER))
		outs.append(Vector3(cos(a), 0, -sin(a)))
	pts.append(Vector3(-w + CORNER, 0, rz))
	outs.append(Vector3(0, 0, -1))
	# The circle front: a cosine bow, tangent to the rear wall at its ends.
	var bow := 28
	for k in bow + 1:
		var x := lerpf(-BOW_HALF, BOW_HALF, float(k) / bow)
		pts.append(Vector3(x, 0, _bow_z(x, rz)))
		outs.append(_bow_out(x))
	pts.append(Vector3(w - CORNER, 0, rz))
	outs.append(Vector3(0, 0, -1))
	for k in range(1, arc):
		var a := PI * 0.5 * (arc - k) / arc
		pts.append(Vector3(w - CORNER + cos(a) * CORNER, 0, rz - CORNER + sin(a) * CORNER))
		outs.append(Vector3(-cos(a), 0, -sin(a)))
	pts.append(Vector3(w, 0, rz - CORNER))
	outs.append(Vector3(-1, 0, 0))
	pts.append(Vector3(w, 0, pros))
	outs.append(Vector3(-1, 0, 1))
	pts.append(Vector3(face_end, 0, pros))
	outs.append(Vector3(0, 0, 1))
	return [pts, outs]


static func _bow_z(x: float, rz: float) -> float:
	if absf(x) >= BOW_HALF:
		return rz
	return rz - BOW_DEPTH * (0.5 + 0.5 * cos(PI * x / BOW_HALF))


static func _bow_out(x: float) -> Vector3:
	var dz := BOW_DEPTH * 0.5 * PI / BOW_HALF * sin(PI * x / BOW_HALF) if absf(x) < BOW_HALF else 0.0
	return Vector3(dz, 0.0, -1.0).normalized()


## The speed bands: cream faience, jade and cream again between four chrome beads, all round the hall at one level
## ("walls that sweep in long horizontal ribs and speed lines towards the screen", the brief).
static func _bands(c: Object, l: Auditorium.Layout, w: float, pros: float) -> void:
	var r := _band_path(w, pros, l.hi.z, w - 1.75)
	var base: PackedVector3Array = r[0]
	var outs: Array = r[1]
	var path := PackedVector3Array()
	for p in base:
		path.append(p + Vector3.UP * BAND_FOOT)
	var faience: Material = c.shiny("faience", 0.0, 0.3, 0.12)
	var chrome: Material = c.shiny("chrome", 1.0, 1.0, 0.08)
	c.u.surface(faience)
	# Each band: its front, top and underside ([foot, top, how far out, colour]).
	for band: Array in [[0.045, 0.3, 0.12, FAIENCE], [0.34, 0.5, 0.14, JADE], [0.54, 0.7, 0.12, FAIENCE]]:
		var y0 := float(band[0])
		var y1 := float(band[1])
		var o := float(band[2])
		c.u.colour = _lin(band[3])
		_sweep_face(c.u, path, outs, Vector2(o, y0), Vector2(o, y1), Vector2(1, 0))
		_sweep_face(c.u, path, outs, Vector2(0.0, y1), Vector2(o, y1), Vector2(0, 1))
		_sweep_face(c.u, path, outs, Vector2(0.0, y0), Vector2(o, y0), Vector2(0, -1))
	c.u.surface(chrome)
	c.u.colour = _lin(Color(0.86, 0.86, 0.88))
	for y: float in [0.02, 0.32, 0.52, 0.725]:
		_sweep_round(c.u, path, outs, Vector2(0.125, y), 0.026, -PI * 0.5, PI * 0.5, 4)


## The circle front: a bowed parapet of glazed faience over the rear walkway, the projection box's ports over it; a
## chrome handrail on top, downlights in its soffit. The speed bands run across it.
static func _circle_front(c: Object, l: Auditorium.Layout, _w: float) -> void:
	var rz := l.hi.z
	var path := PackedVector3Array()
	var outs: Array = []
	var bow := 28
	for k in bow + 1:
		var x := lerpf(-BOW_HALF, BOW_HALF, float(k) / bow)
		path.append(Vector3(x, 0.0, _bow_z(x, rz)))
		outs.append(_bow_out(x))
	var faience: Material = c.shiny("faience", 0.0, 0.3, 0.12)
	var chrome: Material = c.shiny("chrome", 1.0, 1.0, 0.08)
	c.u.surface(faience)
	c.u.colour = _lin(JADE)
	_sweep_face(c.u, path, outs, Vector2(0.0, BOW_LOW), Vector2(0.0, BOW_TOP), Vector2(1, 0))
	# The soffit, from the bow back to the wall (plaster: the downlights' glow round it).
	var sa := PackedVector3Array()
	var sb := PackedVector3Array()
	var ta := PackedVector3Array()
	var tb := PackedVector3Array()
	for p in path:
		sa.append(Vector3(p.x, BOW_LOW, p.z))
		sb.append(Vector3(p.x, BOW_LOW, rz))
		ta.append(Vector3(p.x, BOW_TOP, p.z))
		tb.append(Vector3(p.x, BOW_TOP, rz))
	c.cove.surface(c.kit.cove_material())
	c.cove.colour = _lin(CREAM, 0.03)
	_pair(c.cove, sa, sb, Vector3.DOWN)
	c.cove.colour = Color.WHITE
	# The top: from the bow back to the wall, and its chrome rail.
	c.u.surface(faience)
	c.u.colour = _lin(FAIENCE * 0.8)
	_pair(c.u, ta, tb, Vector3.UP)
	c.u.surface(chrome)
	c.u.colour = _lin(Color(0.86, 0.86, 0.88))
	var rail := PackedVector3Array()
	for p in path:
		rail.append(p + Vector3.UP * (BOW_TOP + 0.07))
	_sweep_round(c.u, rail, outs, Vector2(0.0, 0.0), 0.045, -PI, PI, 8)
	var low := PackedVector3Array()
	for p in path:
		low.append(p + Vector3.UP * BOW_LOW)
	_sweep_round(c.u, low, outs, Vector2(0.0, 0.0), 0.03, -PI * 0.5, PI * 0.5, 4)
	# Three downlights in the soffit, lighting the walkway (the bake's spots).
	c.lit.surface(_shell_glass(c))
	c.lit.colour = Color(1.0, 1.0, 1.0)
	for x: float in [-3.6, 0.0, 3.6]:
		var z := (_bow_z(x, rz) + rz) * 0.5
		var ring: Array = []
		for k in 12:
			var a := TAU * k / 12.0
			ring.append(Vector3(x + cos(a) * 0.09, BOW_LOW - 0.004, z + sin(a) * 0.09))
		c.lit.face(ring, Vector3.DOWN)
		c.spots.append([Vector3(x, BOW_LOW - 0.05, z), Vector3(x, BOW_LOW - 3.0, z), Color(1.0, 0.82, 0.6), 1.4, 6.0,
				38.0])
	for k in 4:
		var x := lerpf(-BOW_HALF * 0.7, BOW_HALF * 0.7, k / 3.0)
		var z := (_bow_z(x, rz) + rz) * 0.5
		c.shapes.append(PhysicsShapes.box(Vector3(x, (BOW_LOW + BOW_TOP) * 0.5, z), Vector3(BOW_HALF * 0.45,
				BOW_TOP - BOW_LOW, rz - _bow_z(x, rz)), Basis()))


## The rear corners rounded: a quarter round of plaster from the walkway up past the ceiling's band.
static func _fillets(c: Object, l: Auditorium.Layout, w: float) -> void:
	var rz := l.hi.z
	var y0 := l.row_floor(-l.rows_back)
	var y1 := BAND_Y[BAND_Y.size() - 1] + 0.1
	c.s.surface(c.tinted("plaster"))
	c.s.colour = _lin(PLASTER)
	for s: float in [-1.0, 1.0]:
		var centre := Vector3(s * (w - CORNER), 0.0, rz - CORNER)
		var start := -PI * 0.5 if s < 0.0 else 0.0
		Shapes.lathe(c.s, [Vector2(CORNER, y1), Vector2(CORNER, y0)], centre, 6, Basis(), PI * 0.5, start)


## The dado: walnut veneer along the rake, 1.1 m over the steps' line, a chrome bead on top and chrome joints; on the
## rear wall between the exits. The front exits interrupt it.
static func _dado(c: Object, l: Auditorium.Layout, w: float, pros: float) -> void:
	var p: Dictionary = c.builder_params
	var ds: Array = p.get("door_size", [1.8, 2.35])
	var front_door := (l.lo.z + float(p.get("stage_depth", 1.9)) + l.arc_z(l.row_radius(l.rows_front) - l.depth * 0.5,
			l.block_x)) * 0.5
	var door_end := front_door + float(ds[0]) * 0.5 + 0.15
	var z0 := l.arc_z(l.row_radius(l.rows_front) - l.depth * 0.5, l.block_x)
	var z1 := l.arc_z(l.row_radius(-l.rows_back) + l.depth * 0.5, l.block_x)
	var zs: Array[float] = [maxf(door_end, pros + 0.1)]
	for z: float in [z0, z1]:
		if z > zs[0] + 0.05:
			zs.append(z)
	zs.append(l.hi.z - CORNER)
	var wood: Material = c.tinted("wood")
	var chrome: Material = c.shiny("chrome", 1.0, 1.0, 0.08)
	for s: float in [-1.0, 1.0]:
		var out := Vector3(-s, 0, 0)
		var low := PackedVector3Array()
		var high := PackedVector3Array()
		var ns := PackedVector3Array()
		var cap := PackedVector3Array()
		var cap_outs: Array = []
		for z in zs:
			var y := _rake(l, z)
			low.append(Vector3(s * (w - 0.03), y - 0.5, z))
			high.append(Vector3(s * (w - 0.03), y + 1.1, z))
			ns.append(out)
			cap.append(Vector3(s * (w - 0.03), y + 1.1, z))
			cap_outs.append(out)
		c.s.surface(wood)
		c.s.colour = _lin(WALNUT)
		c.s.strip(low, high, ns)
		c.s.colour = _lin(WALNUT * 0.8)
		for k in zs.size() - 1:
			c.s.face([high[k], high[k + 1], high[k + 1] - out * 0.03, high[k] - out * 0.03], Vector3.UP)
		c.u.surface(chrome)
		c.u.colour = _lin(Color(0.86, 0.86, 0.88))
		_sweep_round(c.u, cap, cap_outs, Vector2(0.0, 0.0), 0.022, -PI * 0.5, PI * 0.5, 4)
		# Chrome joints between the veneer's panels.
		var z := zs[0] + 1.6
		while z < zs[-1] - 0.5:
			var y := _rake(l, z)
			c.u.box(Vector3(s * (w - 0.035), y + 0.3, z), Vector3(0.012, 1.6, 0.02), Basis(), [Vector3(s, 0, 0)])
			z += 2.4
	# The rear wall, between the exits.
	var walk := l.row_floor(-l.rows_back)
	var half := l.hi.x - 1.6 - float(ds[0]) * 0.5 - 0.2
	var rz := l.hi.z - 0.03
	c.s.surface(wood)
	c.s.colour = _lin(WALNUT)
	c.s.face([Vector3(-half, walk - 0.05, rz), Vector3(half, walk - 0.05, rz), Vector3(half, walk + 1.1, rz),
			Vector3(-half, walk + 1.1, rz)], Vector3.FORWARD)
	c.u.surface(chrome)
	c.u.colour = _lin(Color(0.86, 0.86, 0.88))
	_sweep_round(c.u, PackedVector3Array([Vector3(-half, walk + 1.1, rz), Vector3(half, walk + 1.1, rz)]),
			[Vector3.FORWARD, Vector3.FORWARD], Vector2.ZERO, 0.022, -PI * 0.5, PI * 0.5, 4)


## Reeded pilasters under each step of the ceiling: from the dado to the ledge, five faience reeds, a stepped capital
## and a chrome base.
static func _pilasters(c: Object, l: Auditorium.Layout, w: float) -> void:
	var plaster: Material = c.tinted("plaster")
	var faience: Material = c.shiny("faience", 0.0, 0.3, 0.12)
	var chrome: Material = c.shiny("chrome", 1.0, 1.0, 0.08)
	for k in STEPS.size():
		var z := STEPS[k]
		var top := _ledge_y(k + 1) - 0.14
		var foot := _rake(l, z) + 1.1
		for s: float in [-1.0, 1.0]:
			var xf := _wall_xf(Vector3(s * w, 0.0, z), Vector3(-s, 0, 0))
			var h := top - foot
			c.s.surface(plaster)
			c.s.colour = _lin(CREAM * 0.92)
			_box(c.s, xf, Vector3(0, foot + h * 0.5, 0.05), Vector3(0.6, h, 0.1), [RoomMesh.FRONT])
			# Five reeds of matt plaster, baked with the shaft (the shell lights' pools fall on them too).
			c.s.colour = _lin(CREAM)
			for r in 5:
				var x := (r - 2) * 0.1
				# A half round standing out of the face (a lathe's half turn about the reed's own upright).
				Shapes.lathe(c.s, [Vector2(0.045, foot + 0.18), Vector2(0.045, top - 0.3)], xf * Vector3(x, 0.0, 0.1), 6,
						xf.basis, PI, -PI * 0.5)
			c.u.surface(faience)
			c.u.colour = _lin(FAIENCE)
			# The capital: three steps out under the ledge.
			for t in 3:
				_box(c.u, xf, Vector3(0, top - 0.04 - 0.08 * t, 0.06 + 0.025 * (2 - t)), Vector3(0.64 + 0.06 * (2 - t),
						0.08, 0.12 + 0.05 * (2 - t)), [RoomMesh.FRONT])
			c.u.surface(chrome)
			c.u.colour = _lin(Color(0.86, 0.86, 0.88))
			_box(c.u, xf, Vector3(0, foot + 0.05, 0.065), Vector3(0.66, 0.1, 0.13), [RoomMesh.FRONT])
			_solid(c, xf, Vector3(0, foot + h * 0.5, 0.05), Vector3(0.6, h, 0.1))


## Etched glass shell lights between the pilasters: a fan of frosted glass on a chrome bracket, its ribs catching the
## lamp inside; each lays its scallops of light up and down the wall (a stand-in lamp and a bake light).
static func _shell_lights(c: Object, l: Auditorium.Layout, w: float, pros: float) -> void:
	var zs: Array[float] = []
	var bays: Array[float] = [pros]
	bays.append_array(STEPS)
	for k in STEPS.size():
		var a := bays[k]
		var b2 := bays[k + 1]
		if k == 0:
			a = -10.4
		zs.append((a + b2) * 0.5 if k > 0 else (a + b2) * 0.5 + 0.2)
	var glass := _shell_glass(c)
	var chrome: Material = c.shiny("chrome", 1.0, 1.0, 0.08)
	for z in zs:
		var y := _rake(l, z) + 2.55
		for s: float in [-1.0, 1.0]:
			var xf := _wall_xf(Vector3(s * w, y, z), Vector3(-s, 0, 0))
			_shell(c.lit, glass, xf)
			c.u.surface(chrome)
			c.u.colour = _lin(Color(0.86, 0.86, 0.88))
			_box(c.u, xf, Vector3(0, -0.15, 0.045), Vector3(0.2, 0.05, 0.09), [RoomMesh.FRONT])
			_box(c.u, xf, Vector3(0, -0.2, 0.035), Vector3(0.12, 0.05, 0.07), [RoomMesh.FRONT])
			_box(c.u, xf, Vector3(0, -0.245, 0.025), Vector3(0.06, 0.04, 0.05), [RoomMesh.FRONT])
			c.lamps.append([xf * Vector3(0, 0.08, 0.16), SHELL_GLOW, 1.3])


## The frosted glass of the hall's lamps (the shells, the downlights): the light system's lamp material, house group,
## coloured per vertex; made once.
static func _shell_glass(c: Object) -> ShaderMaterial:
	var mats: Dictionary = c._mats
	if not mats.has("streamline shell glass"):
		var glass: ShaderMaterial = c.kit._lamp(SHELL_GLOW, 1.5, 1.0, "house")
		glass.set_shader_parameter("use_vertex_colour", true)
		mats["streamline shell glass"] = glass
	return mats["streamline shell glass"]


## One shell: a fan of glass from its hinge at the bracket, bulging out, eleven ribs; the vertex colour shades the ribs
## and brightens the glass near the lamp.
static func _shell(b: RoomMesh, glass: Material, xf: Transform3D) -> void:
	b.surface(glass)
	var radius := 0.34
	var bulge := 0.13
	var rings := [0.0, 0.07, 0.14, 0.21, 0.27, 0.32, 0.34]
	var segs := 22
	var pts: Array = []
	for rho: float in rings:
		var row: Array = []
		for k in segs + 1:
			var phi := PI * k / segs
			var rib := 0.5 + 0.5 * cos(phi * 11.0)
			var z := bulge * pow(sin(PI * clampf(rho / radius, 0.0, 1.0)), 0.75) * (0.88 + 0.12 * rib) + 0.004
			row.append(Vector3(cos(phi) * rho, sin(phi) * rho - 0.12, z))
		pts.append(row)
	var rows: Array = []
	var norms: Array = []
	var cols: Array = []
	for i in rings.size():
		var row := PackedVector3Array()
		var nrow := PackedVector3Array()
		var crow := PackedColorArray()
		for k in segs + 1:
			var p: Vector3 = pts[i][k]
			var dr: Vector3 = pts[mini(i + 1, rings.size() - 1)][k] - pts[maxi(i - 1, 0)][k]
			var dp: Vector3 = pts[i][mini(k + 1, segs)] - pts[i][maxi(k - 1, 0)]
			var n := dp.cross(dr).normalized()
			if n.z < 0.0:
				n = -n
			if n.length() < 0.5:
				n = Vector3.BACK
			var phi := PI * k / segs
			var rib := 0.5 + 0.5 * cos(phi * 11.0)
			var bright := (0.55 + 0.45 * rib) * (1.15 - 0.55 * float(rings[i]) / radius)
			row.append(xf * p)
			nrow.append((xf.basis * n).normalized())
			crow.append(Color(bright, bright, bright))
		rows.append(row)
		norms.append(nrow)
		cols.append(crow)
	b.grid(rows, norms, cols)


# --- The proscenium ---------------------------------------------------------------------------------------------------

## An opening's outline (a rounded arch open at the foot): [points (x, y), inward normals]. All the frames' outlines
## share their corners' centres, so each step is an even band.
static func _contour(hw: float, top: float, r: float, foot: float) -> Array:
	var cx := hw - r
	var cy := top - r
	var pts := PackedVector2Array()
	var ns := PackedVector2Array()
	var legs := 6
	var arc := 9
	var across := 8
	for k in legs:
		pts.append(Vector2(-hw, lerpf(foot, cy, float(k) / legs)))
		ns.append(Vector2(1, 0))
	for k in arc + 1:
		var a := PI - PI * 0.5 * k / arc
		pts.append(Vector2(-cx + cos(a) * r, cy + sin(a) * r))
		ns.append(Vector2(-cos(a), -sin(a)))
	for k in range(1, across):
		pts.append(Vector2(lerpf(-cx, cx, float(k) / across), top))
		ns.append(Vector2(0, -1))
	for k in arc + 1:
		var a := PI * 0.5 - PI * 0.5 * k / arc
		pts.append(Vector2(cx + cos(a) * r, cy + sin(a) * r))
		ns.append(Vector2(-cos(a), -sin(a)))
	for k in range(legs - 1, -1, -1):
		pts.append(Vector2(hw, lerpf(foot, cy, float(k) / legs)))
		ns.append(Vector2(-1, 0))
	return [pts, ns]


## The ziggurat: three frames stepping out towards the seats round the picture, each lit by a lamp hidden behind the
## next one's edge (its face glows at its outer edge and fades towards the opening), gilt in the reveals; the
## outermost face reaches the walls and the ceiling, washed from the drop beam over it. On it: the organ grilles, the
## clock and its roundel, and a rising sun over the opening.
static func _ziggurat(c: Object, _e: Dictionary) -> void:
	var l := _layout(c)
	var w := l.hi.x
	var foot := float(c.builder_params.get("stage_top", -2.1))
	var sxf: Transform3D = c.screen.get("xf", Transform3D())
	var size: Vector2 = c.screen.get("size", Vector2(12, 5))
	var sc := sxf.origin
	var hw0 := size.x * 0.5 + OPEN_SIDE
	var top0 := sc.y + size.y * 0.5 + OPEN_TOP
	var outlines: Array = []
	for k in 3:
		outlines.append(_contour(hw0 + FRAME_STEP * k, top0 + FRAME_STEP * k, SHOULDER + FRAME_STEP * k, foot))
	var b: RoomMesh = c.cove
	b.surface(c.kit.cove_material())
	var gilt: Material = c.soft("gilt")
	# The frames' faces: 0 and 1 between their outline and the next; each glows at its outer edge.
	for k in 2:
		var inner: PackedVector2Array = outlines[k][0]
		var outer: PackedVector2Array = outlines[k + 1][0]
		var z := sc.z + FRAME_Z[k]
		var rows: Array = []
		var norms: Array = []
		var cols: Array = []
		for t: float in [0.0, 0.3, 0.62, 1.0]:
			var row := PackedVector3Array()
			var nrow := PackedVector3Array()
			var crow := PackedColorArray()
			var lit := 0.1 + 0.85 * pow(t, 1.7)
			for j in inner.size():
				var p := inner[j].lerp(outer[j], t)
				row.append(Vector3(p.x, p.y, z))
				nrow.append(Vector3.BACK)
				crow.append(_lin(CREAM, lit))
			rows.append(row)
			norms.append(nrow)
			cols.append(crow)
		b.grid(rows, norms, cols)
	# The outermost face: from its outline to the walls and the ceiling; washed from above, and a little from below by
	# the footlights.
	var pros := sc.z + FRAME_Z[2]
	var o2: PackedVector2Array = outlines[2][0]
	var n2: PackedVector2Array = outlines[2][1]
	var far := PackedVector2Array()
	for j in o2.size():
		far.append(_to_edge(o2[j], -n2[j], w, hw0 + FRAME_STEP * 2.0 - (SHOULDER + FRAME_STEP * 2.0),
				top0 + FRAME_STEP * 2.0 - (SHOULDER + FRAME_STEP * 2.0)))
	var rows2: Array = []
	var norms2: Array = []
	var cols2: Array = []
	for t: float in [0.0, 0.05, 0.14, 0.28, 0.46, 0.66, 0.84, 1.0]:
		var row := PackedVector3Array()
		var nrow := PackedVector3Array()
		var crow := PackedColorArray()
		for j in o2.size():
			var p := o2[j].lerp(far[j], t)
			var q := Vector3(p.x, p.y, pros)
			var lit := 0.85 * _lamp_w(q, Vector3.BACK, Vector3(0, BAND_Y[0] - 0.1, pros + 0.3), Vector3.RIGHT, 1.1)
			lit += 0.22 * exp(-(BAND_Y[0] - p.y) / 1.2)
			lit += 0.12 * exp(-(p.y - foot) / 0.8)
			# Round the opening the next frame's lamp reaches it too (the step's glow).
			lit += 0.3 * exp(-t * 14.0)
			row.append(q)
			nrow.append(Vector3.BACK)
			crow.append(_lin(CREAM, lit))
		rows2.append(row)
		norms2.append(nrow)
		cols2.append(crow)
	b.grid(rows2, norms2, cols2)
	# The reveals: gilt, from each frame's face back to the one behind (the first back to the screen).
	c.u.surface(gilt)
	c.u.colour = _lin(Color(1.0, 0.92, 0.78))
	for k in 3:
		var pts: PackedVector2Array = outlines[k][0]
		var ns: PackedVector2Array = outlines[k][1]
		var z_front := sc.z + FRAME_Z[k]
		var z_back := sc.z + (FRAME_Z[k - 1] if k > 0 else 0.07)
		var front := PackedVector3Array()
		var back := PackedVector3Array()
		var nn := PackedVector3Array()
		for j in pts.size():
			front.append(Vector3(pts[j].x, pts[j].y, z_front))
			back.append(Vector3(pts[j].x, pts[j].y, z_back))
			nn.append(Vector3(ns[j].x, ns[j].y, 0.0))
		c.u.grid([front, back], [nn, nn])
		# A gilt bead on each frame's edge.
		_edge_bead(c.u, pts, ns, z_front, 0.028)
	_footlights(c, pros, foot, hw0, top0, sc.z)
	_sunburst(c, Vector3(0.0, top0 + FRAME_STEP * 2.0, pros))
	# Speed lines either side of the sun: three chrome rods across the proscenium's head, ending short of the clock.
	c.u.surface(c.shiny("chrome", 1.0, 1.0, 0.08))
	c.u.colour = _lin(Color(0.86, 0.86, 0.88))
	for s: float in [-1.0, 1.0]:
		for k in 3:
			var y := top0 + FRAME_STEP * 2.0 + 1.0 + 0.17 * k
			var x0 := s * (3.3 + 0.25 * k)
			var x1 := s * 7.3
			_sweep_round(c.u, PackedVector3Array([Vector3(x0, y, pros), Vector3(x1, y, pros)]),
					[Vector3.BACK, Vector3.BACK], Vector2(0.0, 0.0), 0.028, -PI * 0.5, PI * 0.5, 4)
	for s: float in [-1.0, 1.0]:
		_grille(c, Vector3(s * 8.55, foot, pros))
	_clock(c, Vector3(-8.55, 5.55, pros))
	_roundel(c, Vector3(8.55, 5.55, pros))
	# The lift's well in the pit: a chrome ring flush with the floor round where the console comes up.
	_lift_ring(c, l)


## From a point of the outermost outline out along dir to the room's edge (the side walls, the ceiling's line).
static func _to_edge(p: Vector2, dir: Vector2, w: float, cx: float, cy: float) -> Vector2:
	if absf(dir.y) < 0.01:
		return Vector2(signf(dir.x) * w, p.y)
	if absf(dir.x) < 0.01:
		return Vector2(p.x, BAND_Y[0] + _drop(p.x, w))
	# A shoulder: from its centre out, to whichever edge comes first.
	var centre := Vector2(signf(p.x) * cx, cy)
	var d := (p - centre).normalized()
	var t := 0.0
	var q := p
	while t < 12.0:
		t += 0.02
		q = p + d * t
		if absf(q.x) >= w or q.y >= BAND_Y[0] + _drop(q.x, w):
			break
	return Vector2(clampf(q.x, -w, w), minf(q.y, BAND_Y[0] + _drop(q.x, w)))


## A bead round an opening's edge (gilt).
static func _edge_bead(b: RoomMesh, pts: PackedVector2Array, ns: PackedVector2Array, z: float, r: float) -> void:
	var rows: Array = []
	var norms: Array = []
	for k in 5:
		var a := lerpf(0.0, PI, float(k) / 4.0)
		var row := PackedVector3Array()
		var nrow := PackedVector3Array()
		for j in pts.size():
			var inward := Vector3(ns[j].x, ns[j].y, 0.0)
			var d := inward * cos(a) + Vector3.BACK * sin(a)
			row.append(Vector3(pts[j].x, pts[j].y, z) + inward * 0.0 + d * r)
			nrow.append(d)
		rows.append(row)
		norms.append(nrow)
	b.grid(rows, norms)


## The festoon's light: footlights at the stage's lip shining up and two battens hidden behind the first frame's head
## shining down, stand-in lamps in the cove's colour (they light the festoon's folds and the console; never baked: the
## festoon and the console are not).
static func _footlights(c: Object, pros: float, foot: float, hw: float, top: float, screen_z: float) -> void:
	# Two and two: the light system has eight stand-in lamps, and the shell lights take the other four in pairs.
	for x: float in [-hw * 0.42, hw * 0.42]:
		c.footlights.append([Vector3(x, foot + 0.12, pros + 0.15), 0.35, 1.25])
	for x: float in [-hw * 0.45, hw * 0.45]:
		c.footlights.append([Vector3(x, top + 0.35, screen_z + FRAME_Z[0] - 0.05), -1.0, 0.35])


## A rising sun over the opening: a glowing half disc (a cove's light behind ground glass), two gilt half rings and
## thirteen gilt rays, long and short.
static func _sunburst(c: Object, at: Vector3) -> void:
	var b: RoomMesh = c.cove
	var z := at.z + 0.03
	var rows: Array = []
	var norms: Array = []
	var cols: Array = []
	for ring: float in [0.0, 0.35, 0.62, 0.75]:
		var row := PackedVector3Array()
		var nrow := PackedVector3Array()
		var crow := PackedColorArray()
		for k in 17:
			var a := PI * k / 16.0
			row.append(Vector3(at.x + cos(a) * ring, at.y + sin(a) * ring, z))
			nrow.append(Vector3.BACK)
			crow.append(_lin(Color(1.0, 0.95, 0.85), 1.0 - 0.35 * ring / 0.75))
		rows.append(row)
		norms.append(nrow)
		cols.append(crow)
	b.grid(rows, norms, cols)
	c.u.surface(c.soft("gilt"))
	c.u.colour = _lin(Color(1.0, 0.92, 0.78))
	for ring: Vector2 in [Vector2(0.78, 0.88), Vector2(1.02, 1.08)]:
		var outer := PackedVector3Array()
		var inner := PackedVector3Array()
		var nn := PackedVector3Array()
		for k in 25:
			var a := PI * k / 24.0
			inner.append(Vector3(at.x + cos(a) * ring.x, at.y + sin(a) * ring.x, z + 0.03))
			outer.append(Vector3(at.x + cos(a) * ring.y, at.y + sin(a) * ring.y, z + 0.03))
			nn.append(Vector3.BACK)
		c.u.grid([inner, outer], [nn, nn])
	for k in 13:
		var a := deg_to_rad(15.0 + 150.0 * k / 12.0)
		var long := k % 2 == 0
		var r0 := 1.22
		var r1 := 2.85 if long else 2.25
		var dir := Vector3(cos(a), sin(a), 0.0)
		var side := Vector3(-sin(a), cos(a), 0.0)
		var w0 := 0.075 if long else 0.055
		var base := at + Vector3(0, 0, 0.035)
		var p0 := base + dir * r0
		var p1 := base + dir * r1
		# A ridge: two faces leaning out from its spine to its edges, tapering to the tip.
		var spine0 := p0 + Vector3.BACK * 0.045
		var spine1 := p1 + Vector3.BACK * 0.015
		for s: float in [-1.0, 1.0]:
			var e0 := p0 + side * s * w0
			var e1 := p1 + side * s * w0 * 0.25
			c.u.face([e0, e1, spine1, spine0], (Vector3.BACK + side * s * 0.6).normalized())


## An organ grille: the chamber behind lit in the cove's colour, seen through gilt fretwork (horizontal speed bars, a
## spine, a sunburst in the round head), in a stepped gilt surround on a dark faience plinth.
static func _grille(c: Object, foot_at: Vector3) -> void:
	var x0 := foot_at.x
	var z := foot_at.z
	var y0 := foot_at.y + 0.9
	var y1 := y0 + 4.0
	var hw := 0.58
	var b: RoomMesh = c.cove
	# The chamber's glow: brightest low (its lamps), its head dimmer.
	var rows: Array = []
	var norms: Array = []
	var cols: Array = []
	var ys := [y0, y0 + 0.8, y0 + 1.8, y0 + 2.9, y1]
	for y: float in ys:
		var row := PackedVector3Array()
		var nrow := PackedVector3Array()
		var crow := PackedColorArray()
		for k in 5:
			var x := lerpf(-hw, hw, k / 4.0)
			row.append(Vector3(x0 + x, y, z + 0.02))
			nrow.append(Vector3.BACK)
			crow.append(_lin(Color(0.55, 0.42, 0.3), 0.95 - 0.4 * (y - y0) / (y1 - y0) - 0.15 * absf(x) / hw))
		rows.append(row)
		norms.append(nrow)
		cols.append(crow)
	b.grid(rows, norms, cols)
	var head_rows: Array = []
	var head_n: Array = []
	var head_c: Array = []
	for ring: float in [0.0, hw * 0.5, hw]:
		var row := PackedVector3Array()
		var nrow := PackedVector3Array()
		var crow := PackedColorArray()
		for k in 13:
			var a := PI * k / 12.0
			row.append(Vector3(x0 + cos(a) * ring, y1 + sin(a) * ring, z + 0.02))
			nrow.append(Vector3.BACK)
			crow.append(_lin(Color(0.55, 0.42, 0.3), 0.5 - 0.1 * ring / hw))
		head_rows.append(row)
		head_n.append(nrow)
		head_c.append(crow)
	b.grid(head_rows, head_n, head_c)
	# The fretwork.
	c.u.surface(c.soft("gilt"))
	c.u.colour = _lin(Color(1.0, 0.9, 0.72))
	var y := y0 + 0.12
	while y < y1 - 0.05:
		c.u.box(Vector3(x0, y, z + 0.07), Vector3(hw * 2.0, 0.045, 0.05), Basis(), [RoomMesh.FRONT])
		y += 0.19
	for x: float in [-0.29, 0.0, 0.29]:
		c.u.box(Vector3(x0 + x, (y0 + y1) * 0.5, z + 0.09), Vector3(0.05 if x == 0.0 else 0.035, y1 - y0, 0.05),
				Basis(), [RoomMesh.FRONT])
	for k in 9:
		var a := PI * (k + 0.5) / 9.0
		var p0 := Vector3(x0 + cos(a) * 0.14, y1 + sin(a) * 0.14, z + 0.07)
		var p1 := Vector3(x0 + cos(a) * (hw - 0.02), y1 + sin(a) * (hw - 0.02), z + 0.07)
		Shapes.beam(c.u, p0, p1, Vector2(0.035, 0.04), Vector3.BACK)
	var hub: Array = []
	for k in 13:
		var a := PI * k / 12.0
		hub.append(Vector3(x0 + cos(a) * 0.14, y1 + sin(a) * 0.14, z + 0.1))
	c.u.face(hub, Vector3.BACK)
	# The surround: two gilt steps round the panel and its round head.
	for st: Array in [[0.05, 0.1], [0.13, 0.06]]:
		var off := float(st[0])
		var proud := float(st[1])
		var r := hw + off
		for sx: float in [-1.0, 1.0]:
			c.u.box(Vector3(x0 + sx * r, (y0 + y1) * 0.5 - 0.05, z + proud * 0.5), Vector3(0.07, y1 - y0 + 0.1, proud),
					Basis(), [RoomMesh.FRONT])
		Shapes.arch(c.u, Vector3(x0, y1, z + proud * 0.5), r - 0.035, r + 0.035, proud, 12, Basis(), 0.0, PI,
				["front", "outer", "inner"])
	# The plinth: dark jade faience.
	c.u.surface(c.shiny("faience", 0.0, 0.3, 0.12))
	c.u.colour = _lin(Color(0.05, 0.12, 0.1))
	c.u.box(Vector3(x0, (foot_at.y + y0) * 0.5 - 0.05, z + 0.14), Vector3(hw * 2.0 + 0.5, y0 - foot_at.y - 0.1, 0.28),
			Basis(), [RoomMesh.FRONT])
	c.u.colour = _lin(Color(0.86, 0.86, 0.88))
	c.u.surface(c.shiny("chrome", 1.0, 1.0, 0.08))
	c.u.box(Vector3(x0, y0 - 0.12, z + 0.15), Vector3(hw * 2.0 + 0.56, 0.04, 0.3), Basis(), [RoomMesh.FRONT])
	c.shapes.append(PhysicsShapes.box(Vector3(x0, (foot_at.y + y1) * 0.5, z + 0.1), Vector3(hw * 2.0 + 0.5,
			y1 - foot_at.y, 0.2), Basis()))


## The clock: its face (PieceClock: the hands from the real time), a chrome bezel, gilt rays round it.
static func _clock(c: Object, at: Vector3) -> void:
	var r := 0.42
	c.clocks.append([at + Vector3(0, 0, 0.07), Vector3(r, 0, 0), Vector3(0, r, 0), Vector3.BACK])
	_bezel(c, at, r)
	_rays(c, at, r + 0.1, r + 0.42, 16)


## The roundel opposite: glowing glass with three chrome speed lines across it.
static func _roundel(c: Object, at: Vector3) -> void:
	var r := 0.42
	var b: RoomMesh = c.cove
	var rows: Array = []
	var norms: Array = []
	var cols: Array = []
	for ring: float in [0.0, r * 0.6, r]:
		var row := PackedVector3Array()
		var nrow := PackedVector3Array()
		var crow := PackedColorArray()
		for k in 25:
			var a := TAU * k / 24.0
			row.append(at + Vector3(cos(a) * ring, sin(a) * ring, 0.06))
			nrow.append(Vector3.BACK)
			crow.append(_lin(Color(1.0, 0.95, 0.86), 0.95 - 0.3 * ring / r))
		rows.append(row)
		norms.append(nrow)
		cols.append(crow)
	b.grid(rows, norms, cols)
	c.u.surface(c.shiny("chrome", 1.0, 1.0, 0.08))
	c.u.colour = _lin(Color(0.86, 0.86, 0.88))
	for k in 3:
		var y := (k - 1) * 0.12
		var half := sqrt(maxf(r * r - y * y, 0.0)) + 0.12
		var line := PackedVector3Array([at + Vector3(-half, y, 0.08), at + Vector3(half + 0.25, y, 0.08)])
		_sweep_round(c.u, line, [Vector3.BACK, Vector3.BACK], Vector2.ZERO, 0.022, -PI * 0.5, PI * 0.5, 4)
	_bezel(c, at, r)
	_rays(c, at, r + 0.1, r + 0.42, 16)


static func _bezel(c: Object, at: Vector3, r: float) -> void:
	c.u.surface(c.shiny("chrome", 1.0, 1.0, 0.08))
	c.u.colour = _lin(Color(0.86, 0.86, 0.88))
	# A round tube: its normals from the ring's own radial direction and the face's.
	var rows: Array = []
	var norms: Array = []
	for k in 7:
		var t := lerpf(-PI * 0.5, PI, float(k) / 6.0)
		var row := PackedVector3Array()
		var nrow := PackedVector3Array()
		for j in 33:
			var a := TAU * j / 32.0
			var radial := Vector3(cos(a), sin(a), 0.0)
			var d := radial * cos(t) + Vector3.BACK * sin(t)
			row.append(at + radial * (r + 0.03) + Vector3(0, 0, 0.06) + d * 0.035)
			nrow.append(d)
		rows.append(row)
		norms.append(nrow)
	c.u.grid(rows, norms)


## Gilt rays round a disc, long and short by turns.
static func _rays(c: Object, at: Vector3, r0: float, r1: float, count: int) -> void:
	c.u.surface(c.soft("gilt"))
	c.u.colour = _lin(Color(1.0, 0.92, 0.78))
	for k in count:
		var a := TAU * k / count
		var dir := Vector3(cos(a), sin(a), 0.0)
		var side := Vector3(-sin(a), cos(a), 0.0)
		var len := r1 if k % 2 == 0 else lerpf(r0, r1, 0.6)
		var p0 := at + dir * r0 + Vector3(0, 0, 0.02)
		var p1 := at + dir * len + Vector3(0, 0, 0.02)
		for s: float in [-1.0, 1.0]:
			c.u.face([p0 + side * s * 0.045, p1 + side * s * 0.008, p1 + Vector3.BACK * 0.01, p0 + Vector3.BACK * 0.04],
					(Vector3.BACK + side * s * 0.5).normalized())


## The lift's well: a chrome ring on the pit's floor where the console comes up.
static func _lift_ring(c: Object, l: Auditorium.Layout) -> void:
	var at := Vector3(0.0, l.lo.y + 0.004, -11.35)
	c.u.surface(c.shiny("chrome", 1.0, 1.0, 0.08))
	c.u.colour = _lin(Color(0.86, 0.86, 0.88))
	var inner := PackedVector3Array()
	var outer := PackedVector3Array()
	var nn := PackedVector3Array()
	for k in 41:
		var a := TAU * k / 40.0
		inner.append(at + Vector3(cos(a), 0, sin(a)) * 1.2)
		outer.append(at + Vector3(cos(a), 0, sin(a)) * 1.27)
		nn.append(Vector3.UP)
	c.u.grid([inner, outer], [nn, nn])


# --- The organ console --------------------------------------------------------------------------------------------------

## The console's plan: an ellipse (half width, half depth, its centre's z), open at the front between the horseshoe's
## ends (t: the angle round from the back, so the ends are at plus and minus HORSESHOE).
const CONSOLE_RX := 0.95
const CONSOLE_RZ := 0.75
const CONSOLE_CZ := -0.1
const HORSESHOE := 2.234021  # 128 degrees
## The horseshoe's inner edge, as a share of the plan; the glass skirt's top and the horseshoe's two heights.
const INNER := 0.64
const SKIRT_TOP := 0.66
const RIM_Y := 0.7
const INNER_Y := 0.98


## A point of the console's plan at angle t (0 at the back) and share k of its size, at height y.
static func _plan(t: float, k: float, y: float) -> Vector3:
	return Vector3(sin(t) * CONSOLE_RX * k, y, CONSOLE_CZ - cos(t) * CONSOLE_RZ * k)


## The plan's outward normal at angle t.
static func _plan_n(t: float) -> Vector3:
	return Vector3(sin(t) / CONSOLE_RX, 0.0, -cos(t) / CONSOLE_RZ).normalized()


## The console on its lift, as the illuminated consoles of the time were: a round platform with a chrome rim and a skirt
## deep enough to fill the well when it is up; a skirt of illuminated glass panels between gilt fins all round (the
## cove's colour: the console changes colour with the coves); over it an ivory lacquered horseshoe carrying three tiers
## of stop tabs in their colours round the keydesk; three manuals, an illuminated music desk under a chrome hood, a jade
## bench. Its top stays under the front row's sight line to the picture when it is up (the room's test checks).
static func _console(c: Object, xf: Transform3D, _e: Dictionary) -> void:
	var ivory: Material = c.shiny("faience", 0.0, 0.55, 0.06)
	var chrome: Material = c.shiny("chrome", 1.0, 1.0, 0.08)
	var gilt: Material = c.soft("gilt")
	# The platform and its skirt: black lacquer.
	c.u.surface(ivory)
	c.u.colour = _lin(Color(0.05, 0.048, 0.045))
	Shapes.lathe(c.u, [Vector2(1.14, -1.95), Vector2(1.14, -0.04), Vector2(1.1, 0.0), Vector2(0.0, 0.0)], xf.origin, 32,
			xf.basis)
	c.u.surface(chrome)
	c.u.colour = _lin(Color(0.86, 0.86, 0.88))
	Shapes.lathe(c.u, [Vector2(1.15, -0.09), Vector2(1.17, -0.06), Vector2(1.17, -0.02), Vector2(1.15, 0.005)],
			xf.origin, 32, xf.basis)
	# The glass skirt: sixteen panels, each brightest low (the lamps inside) and across its middle (the glass's ribs).
	var b: RoomMesh = c.cove
	b.surface(c.kit.cove_material())
	var panels := 16
	for k in panels:
		var t0 := lerpf(-HORSESHOE, HORSESHOE, float(k) / panels)
		var t1 := lerpf(-HORSESHOE, HORSESHOE, float(k + 1) / panels)
		var rows: Array = []
		var norms: Array = []
		var cols: Array = []
		for y: float in [0.06, 0.34, SKIRT_TOP]:
			var row := PackedVector3Array()
			var nrow := PackedVector3Array()
			var crow := PackedColorArray()
			for j in 5:
				var u := float(j) / 4.0
				var t := lerpf(t0, t1, u)
				# The "jelly mould": the glass bellies out a little at mid height.
				var bulge := 1.0 + 0.035 * sin(PI * y / SKIRT_TOP)
				row.append(xf * _plan(t, bulge, y))
				nrow.append((xf.basis * _plan_n(t)).normalized())
				var rib := 0.7 + 0.3 * sin(PI * u)
				crow.append(_lin(Color(1.0, 0.97, 0.92), (1.0 - 0.4 * y / SKIRT_TOP) * rib))
			rows.append(row)
			norms.append(nrow)
			cols.append(crow)
		b.grid(rows, norms, cols)
	# Gilt fins between the panels, a gilt plinth under them.
	c.u.surface(gilt)
	c.u.colour = _lin(Color(1.0, 0.9, 0.7))
	for k in panels + 1:
		var t := lerpf(-HORSESHOE, HORSESHOE, float(k) / panels)
		var basis := Basis(Vector3.UP, atan2(_plan_n(t).x, _plan_n(t).z))
		c.u.box(xf * _plan(t, 1.03, SKIRT_TOP * 0.5 + 0.03), Vector3(0.035, SKIRT_TOP - 0.02, 0.05),
				xf.basis * basis)
	var plinth := PackedVector3Array()
	var rim := PackedVector3Array()
	var outs: Array = []
	for k in 41:
		var t := lerpf(-HORSESHOE, HORSESHOE, float(k) / 40.0)
		plinth.append(xf * _plan(t, 1.0, 0.04))
		rim.append(xf * _plan(t, 1.0, RIM_Y))
		outs.append((xf.basis * _plan_n(t)).normalized())
	_sweep_round(c.u, plinth, outs, Vector2(0.01, 0.0), 0.045, -PI * 0.5, PI * 0.5, 4)
	# The horseshoe: ivory, sloping up from its rounded rim to its inner edge, then down into the keydesk.
	c.u.surface(ivory)
	c.u.colour = _lin(IVORY)
	_sweep_round(c.u, rim, outs, Vector2(0.0, 0.0), 0.055, -PI * 0.5, PI * 0.75, 6)
	var slope: Array = []
	var slope_n: Array = []
	var lip: Array = []
	for row_k: float in [1.0, 0.82, INNER]:
		var row := PackedVector3Array()
		var nrow := PackedVector3Array()
		for k in 41:
			var t := lerpf(-HORSESHOE, HORSESHOE, float(k) / 40.0)
			var y := lerpf(RIM_Y + 0.05, INNER_Y, (1.0 - row_k) / (1.0 - INNER))
			row.append(xf * _plan(t, row_k, y))
			nrow.append((xf.basis * (Vector3.UP * 0.8 + _plan_n(t) * 0.6).normalized()).normalized())
		slope.append(row)
		slope_n.append(nrow)
	c.u.grid(slope, slope_n)
	for y: float in [INNER_Y, 0.04]:
		var row := PackedVector3Array()
		for k in 41:
			var t := lerpf(-HORSESHOE, HORSESHOE, float(k) / 40.0)
			row.append(xf * _plan(t, INNER, y))
		lip.append(row)
	var lip_n := PackedVector3Array()
	for k in 41:
		var t := lerpf(-HORSESHOE, HORSESHOE, float(k) / 40.0)
		lip_n.append((xf.basis * -_plan_n(t)).normalized())
	c.u.grid(lip, [lip_n, lip_n])
	# The ivory lining inside the glass, and the horseshoe's two ends.
	var lining: Array = []
	var lining_n := PackedVector3Array()
	for y: float in [0.06, RIM_Y]:
		var row := PackedVector3Array()
		for k in 41:
			var t := lerpf(-HORSESHOE, HORSESHOE, float(k) / 40.0)
			row.append(xf * _plan(t, 0.95, y))
		lining.append(row)
	for k in 41:
		var t := lerpf(-HORSESHOE, HORSESHOE, float(k) / 40.0)
		lining_n.append((xf.basis * -_plan_n(t)).normalized())
	c.u.grid(lining, [lining_n, lining_n])
	for s: float in [-1.0, 1.0]:
		var t := s * HORSESHOE
		var side := (xf.basis * Vector3(cos(t) * s, 0.0, sin(t) * s).normalized()).normalized()
		c.u.face([xf * _plan(t, 1.0, 0.04), xf * _plan(t, INNER, 0.04), xf * _plan(t, INNER, INNER_Y),
				xf * _plan(t, 1.0, RIM_Y + 0.05)], side)
	# Three tiers of stop tabs on the horseshoe's slope, in groups of colour: white, red, amber, black.
	var tab_colours := [Color(0.95, 0.92, 0.84), Color(0.78, 0.12, 0.1), Color(0.96, 0.7, 0.24), Color(0.07, 0.06, 0.05)]
	for tier in 3:
		var share := lerpf(0.93, 0.72, tier / 2.0)
		var y := lerpf(RIM_Y + 0.05, INNER_Y, (1.0 - share) / (1.0 - INNER)) + 0.012
		var count := 40 - 6 * tier
		for k in count:
			var t := lerpf(-HORSESHOE + 0.12, HORSESHOE - 0.12, (k + 0.5) / count)
			var group := int(floor(float(k) / count * 10.0)) % 4
			c.u.colour = _lin(tab_colours[group])
			var n := _plan_n(t)
			var basis := Basis(Vector3.UP, atan2(n.x, n.z)) * Basis(Vector3.RIGHT, deg_to_rad(-37.0))
			c.u.box(xf * _plan(t, share, y), Vector3(0.024, 0.012, 0.06), xf.basis * basis, [RoomMesh.DOWN])
	# The keydesk: an ivory body inside the horseshoe, three manuals stepping back and up, gilt key slips, cheeks.
	c.u.colour = _lin(IVORY)
	_box(c.u, xf, Vector3(0.0, 0.37, -0.17), Vector3(0.94, 0.74, 0.86), [RoomMesh.DOWN])
	_box(c.u, xf, Vector3(0.0, 0.88, -0.48), Vector3(0.94, 0.28, 0.24), [RoomMesh.DOWN])
	for s: float in [-1.0, 1.0]:
		_box(c.u, xf, Vector3(s * 0.465, 0.86, 0.04), Vector3(0.05, 0.26, 0.5))
	var keys := 61
	var width := 0.88
	for m in 3:
		var y := 0.76 + 0.085 * m
		var zf := 0.27 - 0.12 * m
		c.u.colour = _lin(Color(0.96, 0.93, 0.85))
		_box(c.u, xf, Vector3(0.0, y, zf - 0.07), Vector3(width, 0.022, 0.14))
		c.u.colour = _lin(Color(0.03, 0.025, 0.02))
		for k in keys:
			if k % 12 in [1, 3, 6, 8, 10]:
				var x := -width * 0.5 + (float(k) + 0.5) * width / keys
				_box(c.u, xf, Vector3(x, y + 0.017, zf - 0.1), Vector3(width / keys * 0.62, 0.014, 0.085), [RoomMesh.DOWN])
	c.u.surface(gilt)
	c.u.colour = _lin(Color(1.0, 0.9, 0.7))
	for m in 3:
		_box(c.u, xf, Vector3(0.0, 0.76 + 0.085 * m - 0.028, 0.27 - 0.12 * m + 0.004), Vector3(width + 0.02, 0.036, 0.012))
	# The music desk, lit, under a chrome hood.
	c.lit.surface(c.kit._lamp(Color(1.0, 0.9, 0.72), 1.3, 1.0, "accent"))
	var desk := Transform3D(xf.basis * Basis(Vector3.RIGHT, deg_to_rad(-16.0)), xf * Vector3(0.0, 1.02, -0.33))
	c.lit.face([desk * Vector3(-0.3, 0.0, 0.0), desk * Vector3(0.3, 0.0, 0.0), desk * Vector3(0.3, 0.17, 0.0),
			desk * Vector3(-0.3, 0.17, 0.0)], (desk.basis * Vector3.BACK).normalized())
	c.u.surface(chrome)
	c.u.colour = _lin(Color(0.86, 0.86, 0.88))
	_box(c.u, desk, Vector3(0.0, 0.185, 0.05), Vector3(0.66, 0.022, 0.12))
	_box(c.u, desk, Vector3(0.0, 0.085, -0.015), Vector3(0.64, 0.21, 0.02), [RoomMesh.BACK])
	# The pedalboard in the horseshoe's open front, under the bench: a walnut frame, thirty-two pedals (the sharps
	# black and raised), so the console's front reads as an organ's and not as a hole into the lift.
	c.u.surface(ivory)
	c.u.colour = _lin(WALNUT)
	_box(c.u, xf, Vector3(0.0, 0.03, 0.5), Vector3(0.9, 0.06, 0.5), [RoomMesh.DOWN])
	var pedals := 32
	for k in pedals:
		var x := -0.4 + (float(k) + 0.5) * 0.8 / pedals
		var sharp: bool = k % 12 in [1, 3, 6, 8, 10]
		c.u.colour = _lin(Color(0.04, 0.035, 0.03) if sharp else Color(0.72, 0.56, 0.36))
		_box(c.u, xf, Vector3(x, 0.075 if sharp else 0.065, 0.48 if sharp else 0.52),
				Vector3(0.014, 0.03 if sharp else 0.012, 0.18 if sharp else 0.42), [RoomMesh.DOWN])
	# The bench: jade leather on an ivory base, chrome feet.
	c.u.colour = _lin(Color(0.1, 0.32, 0.26))
	_box(c.u, xf, Vector3(0.0, 0.5, 0.84), Vector3(1.0, 0.07, 0.36), [RoomMesh.DOWN])
	c.u.colour = _lin(IVORY)
	_box(c.u, xf, Vector3(0.0, 0.25, 0.84), Vector3(0.9, 0.42, 0.3), [RoomMesh.DOWN])
	c.u.surface(chrome)
	c.u.colour = _lin(Color(0.86, 0.86, 0.88))
	_box(c.u, xf, Vector3(0.0, 0.02, 0.84), Vector3(0.96, 0.04, 0.34))
