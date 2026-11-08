extends RefCounted

## A drive-in's lot in the desert (terrace.gd's lot with `drive_in` on; since 2026-11-08, the drive-in's quality pass).
## The real layout: the rows are arcs round a point behind the screen, so every car faces the picture, the lot a fan
## that narrows to the screen tower; the viewer's car in the middle of a row (at the origin, facing -Z).
##   Ground     the fan of gravel bays and darker lanes, a hump under each row's front wheels, worn tracks, the shadow
##              under each car, oil; the desert plain round it out to the horizon (one draw, vertex colours)
##   Posts      a speaker post between each two bays: a pipe, a junction box, a speaker hung either side (or its cable
##              run into the car parked there), a ramp light's amber collar (one draw; the collars one more)
##   Cars       other cars parked in the bays round the viewer's, dark glass, lacquer and chrome that show the sky and
##              the picture (kit/car_shape.gd, kit/reflect.gd; one MultiMesh, two draws). No people in them
##   Snack bar  the concession and projection booth behind the rows: stucco, a fascia in colour with an upswept end, the
##              booth's ports with the projector's glow, the counter's windows lit warm, SNACK BAR in neon tube with
##              its halo (signs group), a stand-in lamp for its light on the lot
##   Tower      the screen's tower: the face round the picture, a coral wall under it with Deco ribs, stepped wings,
##              the timber frame behind, a red lamp on top
##   Marquee    the sign at the entrance by the road: the name in neon on a box, a neon crescent moon over it, a lit
##              letter board (our letters) framed in bulbs that chase slowly before the film and hold still in it
##   Fence      post and rail along the fan's sides and its back
##   Highway    a road far behind; now and then a car's lights go by (act "car_passes")
## Static; preload to use. `t` is the terrace system (its materials, lamps and nodes).

const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const Shapes := preload("res://scripts/env/systems/kit/shapes.gd")
const CarShape := preload("res://scripts/env/systems/kit/car_shape.gd")
const Reflect := preload("res://scripts/env/systems/kit/reflect.gd")
const Strokes := preload("res://scripts/env/systems/kit/strokes.gd")
const BULB_SHADER := preload("res://shaders/env_bulbs.gdshader")
const GLOW_SHADER := preload("res://scripts/env/systems/kit/env_flame.gdshader")

## The rows' arcs' centre (behind the screen), the rows apart, the bays apart along a row.
const CENTRE_Z := -70.0
const ROW_PITCH := 7.0
const BAY := 3.5
## The fan's half angle (degrees), its near edge (by the tower) and its back (radii from the centre).
const FAN_DEG := 30.0
const R_FRONT := 23.0
const R_BACK := 112.0
## The rows: 0 the viewer's, 1 the next towards the screen, -1 behind.
const ROWS: Array[int] = [-1, 0, 1, 2, 3, 4]
## The snack bar's front (towards the screen) and size.
const SNACK_Z := 15.0
const SNACK_W := 15.0
const SNACK_D := 7.0
const SNACK_H := 3.3
## The marquee by the entrance, and the road behind the lot.
const MARQUEE_AT := Vector3(27.0, 0.0, 47.0)
const ROAD_Z := 78.0
## Linear colours.
const GRAVEL := Color(1.0, 0.94, 0.86)
const ASPHALT := Color(0.42, 0.42, 0.44)
const SAND := Color(0.9, 0.72, 0.55)
## The parked cars' paint (linear): the period's colours, kept dark ("dark shapes with chrome glints", the brief): at
## night a car shows as its outline, its chrome and the sky and the picture in its lacquer.
const CAR_COLOURS: Array[Color] = [Color(0.03, 0.11, 0.11), Color(0.2, 0.04, 0.035), Color(0.15, 0.13, 0.095),
		Color(0.012, 0.012, 0.014), Color(0.04, 0.07, 0.17), Color(0.24, 0.12, 0.11), Color(0.06, 0.12, 0.06),
		Color(0.09, 0.09, 0.1), Color(0.2, 0.13, 0.03), Color(0.1, 0.035, 0.07)]
const NEON_PINK := Color(1.0, 0.22, 0.45)
const NEON_TEAL := Color(0.2, 0.95, 0.85)
const NEON_GOLD := Color(1.0, 0.75, 0.25)


static func row_radius(k: int) -> float:
	return -CENTRE_Z - ROW_PITCH * k


## A point of the lot by its radius from the rows' centre and its angle (radians, + to the viewer's right).
static func polar(r: float, a: float, y: float) -> Vector3:
	return Vector3(r * sin(a), y, CENTRE_Z + r * cos(a))


## A car's frame in a bay: on the row's arc, facing the rows' centre.
static func bay_frame(k: int, a: float, gy: float) -> Transform3D:
	var r := row_radius(k)
	return Transform3D(Basis(Vector3.UP, a), polar(r, a, gy + 0.5))


## The bays of a row: their angles, within the fan.
static func bays(k: int) -> Array[float]:
	var out: Array[float] = []
	var r := row_radius(k)
	var step := BAY / r
	var most := deg_to_rad(FAN_DEG) - 2.5 / r
	var j := -int(floor(most / step))
	while j * step <= most:
		out.append(j * step)
		j += 1
	return out


## Which bays have a car: [[row, angle], ...] (seeded: the same lot every time). The viewer's bay, and the bays beside
## it and straight ahead, stay empty.
static func parked(count: int, seed_value: int) -> Array:
	var all: Array = []
	for k in ROWS:
		for a in bays(k):
			var j := int(round(a * row_radius(k) / BAY))
			if k == 0 and absi(j) <= 1:
				continue
			if k == 1 and j == 0:
				continue
			all.append([k, a])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# Nearer bays fill first, as a lot fills from the middle.
	all.sort_custom(func(p: Array, q: Array) -> bool:
		return absf(float(p[1])) * row_radius(int(p[0])) + absi(int(p[0])) * 2.0 \
				< absf(float(q[1])) * row_radius(int(q[0])) + absi(int(q[0])) * 2.0)
	var out: Array = []
	for e: Array in all:
		if out.size() >= count:
			break
		if rng.randf() < 0.62:
			out.append(e)
	return out


# --- The ground --------------------------------------------------------------------------------------------------------

## Value noise for the ground's colour (smooth, 0..1).
static func _n(x: float, z: float, s: float, seed_value: int) -> float:
	var u := x / s
	var v := z / s
	var xi := floori(u)
	var zi := floori(v)
	var fx := u - xi
	var fz := v - zi
	fx = fx * fx * (3.0 - 2.0 * fx)
	fz = fz * fz * (3.0 - 2.0 * fz)
	var h := func(a: int, b: int) -> float:
		var q := (a * 374761393 + b * 668265263 + seed_value * 1442695041) & 0x7fffffff
		q = ((q ^ (q >> 13)) * 1274126177) & 0x7fffffff
		return float(q & 0xffff) / 65535.0
	return lerpf(lerpf(h.call(xi, zi), h.call(xi + 1, zi), fx), lerpf(h.call(xi, zi + 1), h.call(xi + 1, zi + 1), fx), fz)


## The hump under a row's front wheels: its height at radius r (0 off it).
static func hump(r: float) -> float:
	var h := 0.0
	for k in ROWS:
		var c := row_radius(k) - 2.2
		var d := absf(r - c)
		if d < 0.8:
			h = maxf(h, 0.17 * pow(cos(d / 0.8 * PI * 0.5), 2.0))
	return h


## The lot's ground and the plain round it, into b (its current surface: the ground material, vertex colours).
## cars: the parked bays (their shadows), viewer: the viewer's car's frame (its shadow).
static func ground(b: RoomMesh, gy: float, cars: Array) -> void:
	var fan := deg_to_rad(FAN_DEG + 1.5)
	# Radii: a metre apart, closer over the humps.
	var rs := PackedFloat32Array()
	var r := R_FRONT - 2.0
	while r < R_BACK + 1.0:
		rs.append(r)
		var near_hump := false
		for k in ROWS:
			if absf(r - (row_radius(k) - 2.2)) < 1.0:
				near_hump = true
		r += 0.2 if near_hump else 1.0
	rs.append(R_BACK + 1.0)
	var cols := 56
	var shadows: Array = []
	for e: Array in cars:
		shadows.append(bay_frame(int(e[0]), float(e[1]), gy))
	shadows.append(Transform3D(Basis(), Vector3(0, gy + 0.5, 0)))
	var rows: Array = []
	var norms: Array = []
	var colours: Array = []
	for ri in rs.size():
		var rr := rs[ri]
		var row := PackedVector3Array()
		var nrow := PackedVector3Array()
		var crow := PackedColorArray()
		for ci in cols + 1:
			var a := lerpf(-fan, fan, float(ci) / cols)
			var edge := smoothstep(fan, fan - deg_to_rad(1.5), absf(a)) * smoothstep(R_BACK + 1.0, R_BACK - 0.5, rr) \
					* smoothstep(R_FRONT - 2.0, R_FRONT - 0.5, rr)
			var h := hump(rr) * edge
			var p := polar(rr, a, gy + h - 0.04 * (1.0 - edge))
			row.append(p)
			var slope := (hump(rr + 0.05) - hump(rr - 0.05)) / 0.1 * edge
			var radial := Vector3(sin(a), 0, cos(a))
			nrow.append((Vector3.UP - radial * slope).normalized())
			crow.append(_ground_colour(p, rr, a, h, edge, shadows))
		rows.append(row)
		norms.append(nrow)
		colours.append(crow)
	b.grid(rows, norms, colours)
	_plain(b, gy)


static func _ground_colour(p: Vector3, r: float, a: float, h: float, edge: float, shadows: Array) -> Color:
	# Bays in gravel (the hump and in front of it), lanes of oiled dirt behind each row's cars.
	var lane := 0.0
	for k in ROWS:
		var rear := row_radius(k) + 3.4
		lane = maxf(lane, smoothstep(2.2, 1.0, absf(r - (rear + 1.6))))
	var c := GRAVEL.lerp(ASPHALT, lane * 0.75)
	# Tyre tracks along the lanes, two dark ruts.
	for k in ROWS:
		var mid := row_radius(k) + 5.0
		for off: float in [-0.75, 0.75]:
			c = c.lerp(ASPHALT * 0.7, 0.35 * smoothstep(0.35, 0.0, absf(r - (mid + off))))
	c = c.lerp(Color(1.08, 1.05, 1.0), clampf(h / 0.17, 0.0, 1.0) * 0.4)
	var n := _n(p.x, p.z, 7.0, 3) * 0.6 + _n(p.x, p.z, 2.3, 5) * 0.4
	c *= lerpf(0.78, 1.12, n)
	# The shadows of the cars, an oil stain under each engine.
	for t: Transform3D in shadows:
		var q := t.affine_inverse() * Vector3(p.x, t.origin.y, p.z)
		var e := Vector2(q.x / 1.25, (q.z + 0.1) / 3.3).length()
		c *= lerpf(0.45, 1.0, smoothstep(0.75, 1.15, e))
		var oil := Vector2(q.x / 0.6, (q.z + 2.0) / 0.7).length()
		c *= lerpf(0.75, 1.0, smoothstep(0.5, 1.0, oil))
	# Off the lot: the desert's sand.
	c = SAND.lerp(c, edge)
	return Color(c.r, c.g, c.b)


## The desert plain round the lot, a little under it, in rings out to the horizon, a slow swell far off.
static func _plain(b: RoomMesh, gy: float) -> void:
	var radii := [6.0, 14.0, 24.0, 36.0, 50.0, 66.0, 84.0, 104.0, 128.0, 156.0, 186.0]
	var cols := 72
	var rows: Array = []
	var norms: Array = []
	var colours: Array = []
	for r: float in radii:
		var row := PackedVector3Array()
		var nrow := PackedVector3Array()
		var crow := PackedColorArray()
		for ci in cols + 1:
			var a := TAU * float(ci) / cols
			var x := sin(a) * r
			var z := -cos(a) * r
			var swell := 1.2 * smoothstep(60.0, 150.0, r) * (_n(x, z, 40.0, 9) - 0.4)
			row.append(Vector3(x, gy - 0.07 + swell, z))
			nrow.append(Vector3.UP)
			var n := _n(x, z, 11.0, 13)
			var c := SAND * lerpf(0.7, 1.05, n) * lerpf(1.0, 0.75, smoothstep(80.0, 180.0, r))
			crow.append(Color(c.r, c.g, c.b))
		rows.append(row)
		norms.append(nrow)
		colours.append(crow)
	b.grid(rows, norms, colours)


# --- Posts and speakers ------------------------------------------------------------------------------------------------

## The speaker posts: [foot, row, angle] between each two bays of each row (the post on a bay's left at its angle less
## half a bay).
static func posts(gy: float) -> Array:
	var out: Array = []
	for k in ROWS:
		var r := row_radius(k) - 0.3
		var step := BAY / row_radius(k)
		for a in bays(k):
			out.append([polar(r, a - step * 0.5, gy), k, a - step * 0.5])
		var last: float = bays(k)[bays(k).size() - 1]
		out.append([polar(r, last + step * 0.5, gy), k, last + step * 0.5])
	return out


## A post: the pipe, its junction box, a speaker on each side (or, where a car is parked to its right, that speaker
## in the car's window with its cable run there), into b (the metal, vertex colours). collar: the ramp light's ring.
static func post(b: RoomMesh, lamp_b: RoomMesh, foot: Vector3, a: float, in_car: Variant) -> void:
	var turn := Basis(Vector3.UP, a)
	var right := turn * Vector3.RIGHT
	var pipe := Color(0.55, 0.57, 0.55)
	b.colour = pipe
	Shapes.lathe(b, [Vector2(0.05, 0.0), Vector2(0.045, 0.05), Vector2(0.036, 0.08), Vector2(0.036, 1.12)], foot, 8)
	b.colour = Color(0.4, 0.46, 0.42)
	b.box(foot + Vector3(0, 1.2, 0), Vector3(0.2, 0.17, 0.14), turn)
	b.box(foot + Vector3(0, 1.3, 0), Vector3(0.24, 0.03, 0.18), turn)
	for s: float in [-1.0, 1.0]:
		if s > 0.0 and in_car != null:
			# The speaker is in the car on the right: its cable from the box, sagging, to the car's left door (INF: the
			# car draws its own cable, the viewer's).
			var to: Vector3 = in_car
			if not to.is_finite():
				continue
			var from := foot + Vector3(0, 1.16, 0) + right * 0.1
			var prev := from
			b.colour = Color(0.03, 0.03, 0.03)
			for k in range(1, 9):
				var t := float(k) / 8.0
				var p := from.lerp(to, t) + Vector3(0, -0.28 * sin(t * PI), 0)
				Shapes.beam(b, prev, p, Vector2(0.012, 0.012))
				prev = p
			continue
		# A speaker hung on its hook at the box's side, its grille towards the lane.
		var at := foot + right * s * 0.16 + Vector3(0, 1.1, 0)
		b.colour = Color(0.5, 0.52, 0.5)
		b.box(at, Vector3(0.07, 0.15, 0.21), turn)
		b.colour = Color(0.06, 0.06, 0.06)
		b.box(at + turn * Vector3(s * 0.037, -0.01, 0.0), Vector3(0.004, 0.1, 0.16), turn)
	# The ramp light's collar, low on the pipe.
	Shapes.lathe(lamp_b, [Vector2(0.05, 0.0), Vector2(0.052, 0.04)], foot + Vector3(0, 0.42, 0), 8)


# --- The parked cars -----------------------------------------------------------------------------------------------------

## The parked car's mesh: a closed hardtop on the convertible's lines, coarse (paint with dark glass and the dark
## inside in its vertex colours; chrome), for a MultiMesh.
static func parked_mesh(paint: Material, chrome: Material, gy: float) -> ArrayMesh:
	var d := CarShape.dims({"ground_y": gy, "coarse": true, "fins": 0.26})
	var pb := RoomMesh.new()
	pb.surface(paint)
	var cb := RoomMesh.new()
	cb.surface(chrome)
	var white := Color(1, 1, 1)
	var dark := Color(0.02, 0.02, 0.022)
	CarShape.body(pb, d, white, Color(0.85, 0.82, 0.75), dark, cb, false)
	CarShape.glasshouse(pb, d, Color(0.012, 0.013, 0.016), Color(0.92, 0.9, 0.85))
	CarShape.wheels(pb, cb, d, Color(0.02, 0.02, 0.02), Color(0.7, 0.68, 0.62))
	# The tail lamps, unlit red.
	pb.colour = Color(0.35, 0.02, 0.02)
	for s: float in [-1.0, 1.0]:
		var z := float(d["rear"]) - 0.05
		Shapes.lathe(pb, [Vector2(0.05, 0.0), Vector2(0.0, 0.02)], Vector3(s * (CarShape.half_width(d, z) - 0.085),
				CarShape.belt(d, z) - 0.07, float(d["rear"]) + 0.02), 8, Basis(Vector3.RIGHT, PI * 0.5))
	pb.colour = white
	var ao := func(p: Vector3, n: Vector3) -> float:
		var k := lerpf(0.45, 1.0, smoothstep(-0.35, 0.6, p.y))
		return k * (lerpf(1.0, 0.6, smoothstep(-0.3, -0.9, n.y)))
	pb.shade(ao)
	cb.shade(ao)
	var mesh := pb.commit(false)
	var cm := cb.commit(false)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, cm.surface_get_arrays(0))
	mesh.surface_set_material(1, chrome)
	return mesh


# --- The snack bar and the projection booth --------------------------------------------------------------------------

## The building: walls, the fascia with its upswept end, the roof, the booth's ports, the windows' frames; into b (the
## plaster, vertex colours). Lit parts are returned: {windows: [quads], ports: [quads], neon: [[polyline, colour]],
## lamps: [[at, colour]]} (the room's frame).
static func snack_bar(b: RoomMesh, gy: float, sign_text: String) -> Dictionary:
	var hw := SNACK_W * 0.5
	var z0 := SNACK_Z
	var z1 := SNACK_Z + SNACK_D
	var top := gy + SNACK_H
	var stucco := Color(0.82, 0.76, 0.64)
	var fascia := Color(0.12, 0.42, 0.4)
	var trim := Color(0.72, 0.2, 0.16)
	var out := {"windows": [], "ports": [], "neon": [], "lamps": []}
	# The walls: the front with the booth's ports and the windows each side, the sides and the back.
	b.colour = stucco
	var holes: Array = [Rect2(hw - 0.45, 2.3, 0.4, 0.32), Rect2(hw + 0.05, 2.3, 0.4, 0.32),
			Rect2(1.0, 0.9, 4.6, 1.4), Rect2(SNACK_W - 5.6, 0.9, 4.6, 1.4), Rect2(hw - 0.5, 0.0, 1.0, 2.05)]
	Shapes.wall(b, Vector3(-hw, gy, z0), Vector3.RIGHT, Vector3.FORWARD, SNACK_W, SNACK_H, holes)
	for s: float in [-1.0, 1.0]:
		b.face([Vector3(s * hw, gy, z0), Vector3(s * hw, gy, z1), Vector3(s * hw, top, z1), Vector3(s * hw, top, z0)],
				Vector3(s, 0, 0))
	b.face([Vector3(-hw, gy, z1), Vector3(hw, gy, z1), Vector3(hw, top, z1), Vector3(-hw, top, z1)], Vector3.BACK)
	# The openings' reveals, dark inside.
	b.colour = Color(0.08, 0.07, 0.06)
	for h: Rect2 in holes:
		var x0 := -hw + h.position.x
		var x1 := x0 + h.size.x
		var y0 := gy + h.position.y
		var y1 := y0 + h.size.y
		b.face([Vector3(x0, y0, z0), Vector3(x0, y0, z0 + 0.25), Vector3(x0, y1, z0 + 0.25), Vector3(x0, y1, z0)],
				Vector3.RIGHT)
		b.face([Vector3(x1, y0, z0), Vector3(x1, y0, z0 + 0.25), Vector3(x1, y1, z0 + 0.25), Vector3(x1, y1, z0)],
				Vector3.LEFT)
		b.face([Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z0 + 0.25), Vector3(x0, y1, z0 + 0.25)],
				Vector3.DOWN)
		b.face([Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z0 + 0.25), Vector3(x0, y0, z0 + 0.25)],
				Vector3.UP)
	# The door (the booth's), dark red; the counter's ledge under each window.
	b.colour = trim
	b.face([Vector3(-0.5, gy, z0 + 0.25), Vector3(0.5, gy, z0 + 0.25), Vector3(0.5, gy + 2.05, z0 + 0.25),
			Vector3(-0.5, gy + 2.05, z0 + 0.25)], Vector3.FORWARD)
	b.colour = Color(0.85, 0.83, 0.78)
	for s: float in [-1.0, 1.0]:
		var cx := s * (hw - 3.3)
		b.box(Vector3(cx, gy + 0.88, z0 - 0.18), Vector3(4.9, 0.06, 0.42))
		b.colour = trim
		b.box(Vector3(cx, gy + 0.43, z0 - 0.03), Vector3(4.7, 0.86, 0.06))
		b.colour = Color(0.85, 0.83, 0.78)
		out["windows"].append([Vector3(cx, gy + 1.6, z0 + 0.2), Vector3(2.3, 0, 0), Vector3(0, 0.7, 0), Vector3.FORWARD])
	for x: float in [-0.25, 0.25]:
		out["ports"].append([Vector3(x, gy + 2.46, z0 + 0.2), Vector3(0.2, 0, 0), Vector3(0, 0.16, 0), Vector3.FORWARD])
	# The fascia: a deep band round the roof's edge, its front kicking up at the right end into a wedge.
	var fz := z0 - 0.6
	b.colour = fascia
	var lip := [Vector3(-hw - 0.6, top - 0.15, fz), Vector3(hw + 0.6, top - 0.15, fz), Vector3(hw + 2.2, top + 1.7, fz - 0.4),
			Vector3(hw + 1.5, top + 1.7, fz - 0.4), Vector3(hw + 0.2, top + 0.65, fz), Vector3(-hw - 0.6, top + 0.65, fz)]
	b.face(lip, Vector3.FORWARD)
	b.face([Vector3(-hw - 0.6, top - 0.15, fz), Vector3(-hw - 0.6, top - 0.15, z1 + 0.3),
			Vector3(-hw - 0.6, top + 0.65, z1 + 0.3), Vector3(-hw - 0.6, top + 0.65, fz)], Vector3.LEFT)
	b.face([Vector3(hw + 0.6, top - 0.15, fz), Vector3(hw + 0.6, top - 0.15, z1 + 0.3),
			Vector3(hw + 0.6, top + 0.65, z1 + 0.3), Vector3(hw + 0.2, top + 0.65, fz)], Vector3.RIGHT)
	b.colour = Color(0.3, 0.3, 0.3)
	b.face([Vector3(-hw - 0.6, top - 0.15, fz), Vector3(hw + 0.6, top - 0.15, fz), Vector3(hw + 0.6, top - 0.15, z1 + 0.3),
			Vector3(-hw - 0.6, top - 0.15, z1 + 0.3)], Vector3.DOWN)
	b.face([Vector3(-hw - 0.6, top + 0.5, fz), Vector3(hw + 0.6, top + 0.5, fz), Vector3(hw + 0.6, top + 0.5, z1 + 0.3),
			Vector3(-hw - 0.6, top + 0.5, z1 + 0.3)], Vector3.UP)
	# Coral piping along the fascia's foot.
	b.colour = trim
	b.box(Vector3(0, top - 0.17, fz - 0.03), Vector3(SNACK_W + 1.2, 0.06, 0.06))
	# The sign's neon on the fascia: the words, a tube along the wedge's edges.
	var h := 0.48
	var w := Strokes.width(sign_text, h)
	# It reads from the lot (looking towards +Z, the reader's right is -X).
	var origin := Vector3(w * 0.5 - 1.2, top + 0.0, fz - 0.06)
	for poly: PackedVector2Array in Strokes.lines(sign_text, h):
		var line := PackedVector3Array()
		for q in poly:
			line.append(origin + Vector3(-q.x, q.y, 0))
		out["neon"].append([line, NEON_PINK])
	out["neon"].append([PackedVector3Array([Vector3(hw + 0.75, top - 0.05, fz - 0.06), Vector3(hw + 2.1, top + 1.6,
			fz - 0.46)]), NEON_TEAL])
	out["neon"].append([PackedVector3Array([Vector3(-hw - 0.5, top + 0.58, fz - 0.06), Vector3(hw + 0.15, top + 0.58,
			fz - 0.06), Vector3(hw + 1.45, top + 1.62, fz - 0.44)]), NEON_TEAL])
	out["lamps"].append([Vector3(0, gy + 2.6, z0 - 3.0), NEON_PINK.lerp(Color(1.0, 0.75, 0.5), 0.5)])
	# The roof's vents and the booth's chimney over it.
	b.colour = Color(0.5, 0.5, 0.5)
	b.box(Vector3(0.0, top + 0.9, z0 + 1.8), Vector3(0.5, 0.9, 0.5))
	b.box(Vector3(-4.0, top + 0.6, z1 - 1.5), Vector3(1.2, 0.5, 0.8))
	return out


# --- The screen's tower --------------------------------------------------------------------------------------------------

## The tower round the screen (its centre and size in the room's frame): the painted face round the picture behind
## its plane, a coral wall under it with ribs, stepped wings either side, the timber frame behind; into b (plaster,
## vertex colours) and wood_b. Returns the red lamp's place.
static func tower(b: RoomMesh, wood_b: RoomMesh, gy: float, centre: Vector3, size: Vector2) -> Vector3:
	var z := centre.z - 0.15
	var bottom := centre.y - size.y * 0.5
	var top := centre.y + size.y * 0.5
	var hw := size.x * 0.5 + 1.3
	var face := Color(0.7, 0.7, 0.68)
	var coral := Color(0.62, 0.3, 0.24)
	var cream := Color(0.78, 0.72, 0.6)
	b.colour = face
	b.box(Vector3(0, (bottom - 1.0 + top + 1.3) * 0.5, z - 0.1), Vector3(hw * 2.0, top - bottom + 2.3, 0.2),
			Basis(), [RoomMesh.BACK])
	# The wall under the face, coral with cream ribs.
	b.colour = coral
	var wall_top := bottom - 1.0
	b.box(Vector3(0, (gy + wall_top) * 0.5, z + 0.05), Vector3(hw * 2.0 - 2.0, wall_top - gy, 0.5), Basis(),
			[RoomMesh.BACK, RoomMesh.DOWN])
	b.colour = cream
	var ribs := 13
	for k in ribs:
		var x := lerpf(-hw + 2.0, hw - 2.0, float(k) / (ribs - 1))
		b.box(Vector3(x, (gy + wall_top) * 0.5 - 0.2, z + 0.34), Vector3(0.22, wall_top - gy - 0.4, 0.18), Basis(),
				[RoomMesh.BACK, RoomMesh.DOWN])
	b.box(Vector3(0, wall_top + 0.12, z + 0.2), Vector3(hw * 2.0 - 1.6, 0.24, 0.5), Basis(), [RoomMesh.BACK])
	# Stepped wings either side: three setbacks.
	for s: float in [-1.0, 1.0]:
		for k in 3:
			var w := 1.6 - k * 0.4
			var h := (top + 1.3 - gy) * (1.0 - k * 0.22)
			b.colour = coral if k % 2 == 0 else cream
			b.box(Vector3(s * (hw + w * 0.5 + k * 0.05), gy + h * 0.5, z - 0.3 - k * 0.3), Vector3(w, h, 0.6 + k * 0.3),
					Basis(), [RoomMesh.DOWN])
	# The cap: a cream band stepping up in the middle.
	b.colour = cream
	b.box(Vector3(0, top + 1.45, z - 0.05), Vector3(hw * 2.0 + 0.4, 0.3, 0.5), Basis(), [RoomMesh.DOWN])
	b.box(Vector3(0, top + 1.85, z - 0.05), Vector3(8.0, 0.5, 0.45), Basis(), [RoomMesh.DOWN])
	b.box(Vector3(0, top + 2.3, z - 0.05), Vector3(3.0, 0.4, 0.4), Basis(), [RoomMesh.DOWN])
	# The timber frame behind: posts, braces to the ground, two girts.
	var posts := 7
	for k in posts:
		var x := lerpf(-hw + 0.5, hw - 0.5, float(k) / (posts - 1))
		wood_b.box(Vector3(x, (gy + top + 1.3) * 0.5, z - 0.5), Vector3(0.35, top + 1.3 - gy, 0.35), Basis(),
				[RoomMesh.DOWN])
		Shapes.beam(wood_b, Vector3(x, top - 1.0, z - 0.6), Vector3(x, gy, z - 7.0), Vector2(0.28, 0.28))
		for y: float in [gy + (top - gy) * 0.35, gy + (top - gy) * 0.7]:
			if k < posts - 1:
				var x2 := lerpf(-hw + 0.5, hw - 0.5, float(k + 1) / (posts - 1))
				Shapes.beam(wood_b, Vector3(x, y, z - 0.75), Vector3(x2, y, z - 0.75), Vector2(0.18, 0.12))
	return Vector3(0, top + 2.6, z - 0.05)


# --- The marquee -------------------------------------------------------------------------------------------------------

## The entrance's sign: two legs, a box with the name in neon and a crescent moon over it, the letter board under it
## framed in bulbs. Returns {neon: [[polyline, colour]], board: quad, bulbs: [[at, index]], lamp: [at, colour]}.
static func marquee(b: RoomMesh, gy: float, name: String, lines: Array) -> Dictionary:
	var at := MARQUEE_AT + Vector3(0, gy, 0)
	# It faces the lot's middle (the viewer looks back over the right shoulder at it).
	var face := Basis(Vector3.UP, atan2(at.x, at.z))
	var xf := Transform3D(face, at)
	var out := {"neon": [], "board": [], "bulbs": [], "lamp": []}
	var steel := Color(0.35, 0.36, 0.36)
	var box_c := Color(0.07, 0.16, 0.2)
	var cream := Color(0.85, 0.8, 0.68)
	b.colour = steel
	for s: float in [-1.0, 1.0]:
		b.box(xf * Vector3(s * 2.4, 3.6, 0), Vector3(0.3, 7.2, 0.3), face)
	# The name's box.
	b.colour = box_c
	b.box(xf * Vector3(0, 6.6, 0), Vector3(6.6, 1.5, 0.5), face)
	b.colour = cream
	b.box(xf * Vector3(0, 7.38, 0), Vector3(6.8, 0.08, 0.56), face)
	b.box(xf * Vector3(0, 5.82, 0), Vector3(6.8, 0.08, 0.56), face)
	# The letter board's box under it.
	b.colour = cream
	b.box(xf * Vector3(0, 4.15, 0), Vector3(5.4, 1.7, 0.4), face)
	# The name in neon on both faces of its box, the crescent over it.
	var h := 0.85
	var w := Strokes.width(name, h, 0.95)
	# Both faces read the right way round: the lot's (local -Z, its reader's right is local -X) and the road's.
	for side: float in [-1.0, 1.0]:
		for poly: PackedVector2Array in Strokes.lines(name, h, 0.95):
			var line := PackedVector3Array()
			for q in poly:
				line.append(xf * Vector3(side * (q.x - w * 0.5), 6.18 + q.y, 0.29 * side))
			out["neon"].append([line, NEON_TEAL])
	var moon := PackedVector3Array()
	var inner := PackedVector3Array()
	for k in 15:
		var t := lerpf(-2.2, 2.2, float(k) / 14.0)
		moon.append(xf * Vector3(-2.2 + 0.62 * sin(t) * 1.0, 8.35 + 0.62 * cos(t), -0.05))
		inner.append(xf * Vector3(-2.2 + 0.42 * sin(t) + 0.2, 8.35 + 0.5 * cos(t), -0.05))
	var cres := PackedVector3Array()
	cres.append_array(moon)
	inner.reverse()
	cres.append_array(inner)
	cres.append(moon[0])
	out["neon"].append([cres, NEON_GOLD])
	b.colour = steel
	b.box(xf * Vector3(-2.2, 7.6, 0.0), Vector3(0.08, 0.5, 0.08), face)
	# The board's quad (both faces), and its frame of bulbs.
	out["board"] = [[xf * Vector3(0, 4.15, -0.205), face * Vector3(-2.5, 0, 0), face * Vector3(0, 0.7, 0),
			face * Vector3(0, 0, -1)], [xf * Vector3(0, 4.15, 0.205), face * Vector3(2.5, 0, 0), face * Vector3(0, 0.7, 0),
			face * Vector3(0, 0, 1)]]
	var idx := 0
	for side: float in [-1.0, 1.0]:
		var zf := -0.22 if side < 0.0 else 0.22
		var ring: Array[Vector3] = []
		var n := 30
		for k in n:
			var t := float(k) / n
			var p: Vector2
			if t < 0.25:
				p = Vector2(lerpf(-2.6, 2.6, t / 0.25), 3.25)
			elif t < 0.5:
				p = Vector2(2.6, lerpf(3.25, 5.05, (t - 0.25) / 0.25))
			elif t < 0.75:
				p = Vector2(lerpf(2.6, -2.6, (t - 0.5) / 0.25), 5.05)
			else:
				p = Vector2(-2.6, lerpf(5.05, 3.25, (t - 0.75) / 0.25))
			ring.append(xf * Vector3(p.x, p.y, zf))
		for p in ring:
			out["bulbs"].append([p, idx, face * Vector3(0, 0, -1.0 if side < 0.0 else 1.0)])
			idx += 1
	out["lamp"] = [xf * Vector3(0, 4.5, -2.0), Color(1.0, 0.85, 0.6)]
	out["lines"] = lines
	return out


## The letter board's picture: black letters of our own on a warm white ground, two lines.
static func board_picture(lines: Array) -> ImageTexture:
	var img := Image.create_empty(512, 144, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 0.95, 0.85, 1.0))
	for k in lines.size():
		Strokes.draw(img, str(lines[k]), Vector2(256, 58 + k * 58), 38.0, Color(0.05, 0.04, 0.04, 1.0), 6.0, true, 1.05)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# --- The fence ----------------------------------------------------------------------------------------------------------

## Post and rail along the fan's two sides and its back (a gap for the entrance by the marquee), into b (wood).
static func fence(b: RoomMesh, gy: float) -> void:
	var fan := deg_to_rad(FAN_DEG + 1.0)
	var lines: Array = []
	for s: float in [-1.0, 1.0]:
		var line: Array[Vector3] = []
		var r := R_FRONT
		while r <= R_BACK + 0.5:
			line.append(polar(r, s * fan, gy))
			r += 3.0
		lines.append(line)
	var back: Array[Vector3] = []
	var steps := int(ceil(2.0 * fan * R_BACK / 3.0))
	for k in steps + 1:
		var p := polar(R_BACK + 0.5, lerpf(-fan, fan, float(k) / steps), gy)
		if Vector2(p.x - MARQUEE_AT.x, p.z - MARQUEE_AT.z).length() < 7.0:
			if back.size() > 1:
				lines.append(back)
			back = []
			continue
		back.append(p)
	if back.size() > 1:
		lines.append(back)
	for line: Array[Vector3] in lines:
		for k in line.size():
			var p: Vector3 = line[k]
			b.box(p + Vector3(0, 0.6, 0), Vector3(0.14, 1.2, 0.14))
			if k > 0:
				var q: Vector3 = line[k - 1]
				for y: float in [0.45, 0.95]:
					Shapes.beam(b, q + Vector3(0, y, 0), p + Vector3(0, y, 0), Vector2(0.06, 0.12))


# --- Lit things ---------------------------------------------------------------------------------------------------------

## Neon tubes along polylines: thin round-ish tubes (6 sides), their colours in the vertex colours.
static func tubes(b: RoomMesh, lines: Array, radius := 0.016) -> void:
	for e: Array in lines:
		var line: PackedVector3Array = e[0]
		b.colour = e[1]
		for k in line.size() - 1:
			var a := line[k]
			var c := line[k + 1]
			if a.distance_to(c) < 0.001:
				continue
			var dir := (c - a).normalized()
			var basis := Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.95 else Vector3.FORWARD)
			Shapes.lathe(b, [Vector2(radius, -radius * 0.6), Vector2(radius, a.distance_to(c) + radius * 0.6)], a, 6,
					basis * Basis(Vector3.RIGHT, -PI * 0.5))
	b.colour = Color.WHITE


## The tubes' halo: a soft band along each stroke (additive), facing `normal`.
static func halo_quads(lines: Array, normal: Vector3, width: float) -> Array:
	var out: Array = []
	for e: Array in lines:
		var line: PackedVector3Array = e[0]
		for k in line.size() - 1:
			var a := line[k]
			var c := line[k + 1]
			var len := a.distance_to(c)
			if len < 0.001:
				continue
			var along := (c - a) / len
			var across := normal.cross(along).normalized()
			out.append([(a + c) * 0.5 + normal * 0.02, along * (len * 0.5 + width * 0.5), across * width, normal, e[1]])
	return out


## A soft band's picture: bright along its middle, fading to its edges and ends.
static func halo_picture() -> ImageTexture:
	var img := Image.create_empty(32, 32, false, Image.FORMAT_RGB8)
	for y in 32:
		for x in 32:
			var u := absf((x + 0.5) / 32.0 - 0.5) * 2.0
			var v := absf((y + 0.5) / 32.0 - 0.5) * 2.0
			var k := pow(1.0 - smoothstep(0.0, 1.0, v), 2.2) * (1.0 - smoothstep(0.55, 1.0, u))
			img.set_pixel(x, y, Color(k, k, k))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## A bulb's picture: a round glow with a hot middle.
static func bulb_picture() -> ImageTexture:
	var img := Image.create_empty(32, 32, false, Image.FORMAT_RGB8)
	for y in 32:
		for x in 32:
			var r := Vector2((x + 0.5) / 32.0 - 0.5, (y + 0.5) / 32.0 - 0.5).length() * 2.0
			var k := (1.0 - smoothstep(0.0, 0.35, r)) * 0.9 + pow(maxf(1.0 - r, 0.0), 2.5) * 0.35
			img.set_pixel(x, y, Color(k, k * 0.92, k * 0.75))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## The snack bar's windows: the counter's warm light, shelves, a popcorn case glowing; the booth's ports (cool).
static func window_picture() -> ImageTexture:
	var w := 128
	var h := 64
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			var u := (x + 0.5) / w
			var v := (y + 0.5) / h
			var c := Color(1.0, 0.78, 0.48) * lerpf(1.0, 0.55, v)
			# Shelves across the back wall.
			if fposmod(v * 4.0, 1.0) < 0.07 and v < 0.6:
				c *= 0.45
			# Boxes on the shelves.
			if v < 0.6 and fposmod(u * 11.0, 1.0) < 0.55 and fposmod(v * 4.0, 1.0) > 0.45:
				c = c.lerp(Color(0.9, 0.25, 0.2) if int(u * 11.0) % 3 == 0 else Color(0.95, 0.85, 0.3), 0.55)
			# The popcorn case, bright, in one window's corner; the counter's top.
			if u > 0.72 and u < 0.92 and v > 0.35 and v < 0.85:
				c = Color(1.0, 0.92, 0.6) * 1.2
			if v > 0.86:
				c = Color(0.35, 0.22, 0.16)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
