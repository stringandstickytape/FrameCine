extends RefCounted

## The sea floor round a glass dome in water (dome_hall.gd, `seabed` and the parameters after it; docs/environments.md
## "dome_hall"). All shapes are made here from code: no file, no texture but the caustics' cellular map.
##   The floor   a bowl round the hall: banks rising to the sides and behind (4 to 7 m up at 24 m out, so they show
##               over the drum from the seats), a trench falling away behind the screen into the dark
##   Rocks       boulders on the banks, two ledges near the glass that lift the coral and the fronds into view
##   Coral       branching coral, round coral heads, sea fans and anemones on the right ledge and here and there
##   Fronds      tall swaying ribbons in beds on the left bank and behind (kelp in the shallows, sea whips deeper)
##   Wreck       an old diving bell on its skid, half silted and tilted, a fallen lattice derrick and an anchor
##   Vent        a rough chimney whose bubbles rise past the glass to the surface
##   Snow        marine snow: specks sinking slowly through the water round the dome, never inside it
##   Floodlights lamps on the drum's top outside, aimed at the ledges, the wreck and the vent; their beams in the murk
## One draw each: the floor with its rocks, coral, wreck and vent (env_seabed.gdshader, vertex colours); the fronds
## (the same shader, swaying); the snow and the bubbles (env_water_motes.gdshader); the beams (env_water_beam
## .gdshader). The water's uniforms are the same on every one (dome_hall.gd _water_uniforms()).
## Angles: theta 0 points from the hall's centre towards the screen (-Z), 90 degrees to the viewer's right (+X).

const SEABED_SHADER := preload("res://shaders/env_seabed.gdshader")
const MOTES_SHADER := preload("res://shaders/env_water_motes.gdshader")
const BEAM_SHADER := preload("res://shaders/env_water_beam.gdshader")
const Procedural := preload("res://scripts/env/systems/kit/procedural.gd")

## The features' places: [theta degrees, metres from the hall's centre].
const CORAL_LEDGE := [76.0, 12.6]
const FROND_LEDGE := [-82.0, 13.2]
const WRECK_AT := [-138.0, 15.5]
const VENT_AT := [122.0, 14.0]
## The floodlights' aims: what each lights (theta, metres out, height over the floor there).
const FLOOD_TARGETS := [[-80.0, 15.0, 2.2], [76.0, 12.8, 2.4], [-136.0, 15.5, 1.6], [122.0, 14.0, 2.6]]
## Linear colours.
const SAND := Color(0.33, 0.3, 0.24)
const ROCK := Color(0.19, 0.18, 0.17)
const RUST := Color(0.3, 0.15, 0.08)
const CORALS := [Color(0.85, 0.35, 0.18), Color(0.8, 0.3, 0.45), Color(0.85, 0.7, 0.3), Color(0.5, 0.3, 0.7),
		Color(0.9, 0.55, 0.5), Color(0.75, 0.75, 0.6)]
const FROND := Color(0.26, 0.28, 0.08)


## Vertex arrays for one mesh: positions, normals, colours, UV (x the phase), UV2 (x the sway).
class Mesher:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()

	func vert(p: Vector3, nn: Vector3, col: Color, phase := 0.0, sway := 0.0) -> void:
		v.append(p)
		n.append(nn)
		c.append(col)
		uv.append(Vector2(phase, 0.0))
		uv2.append(Vector2(sway, 0.0))

	## A flat triangle (its own normal, wound so it faces `out` when given).
	func tri(a: Vector3, b: Vector3, cc: Vector3, col: Color, sway := Vector3.ZERO, phase := 0.0) -> void:
		var nn := (b - a).cross(cc - a).normalized()
		vert(a, nn, col, phase, sway.x)
		vert(b, nn, col, phase, sway.y)
		vert(cc, nn, col, phase, sway.z)

	func quad(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, col: Color, sway := Vector4.ZERO, phase := 0.0) -> void:
		tri(a, b, cc, col, Vector3(sway.x, sway.y, sway.z), phase)
		tri(a, cc, d, col, Vector3(sway.x, sway.z, sway.w), phase)

	func triangles() -> int:
		return v.size() / 3

	func commit() -> ArrayMesh:
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = v
		a[Mesh.ARRAY_NORMAL] = n
		a[Mesh.ARRAY_COLOR] = c
		a[Mesh.ARRAY_TEX_UV] = uv
		a[Mesh.ARRAY_TEX_UV2] = uv2
		var m := ArrayMesh.new()
		if v.size() > 0:
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		return m


# --- The floor's shape ---------------------------------------------------------------------------------------------

## The direction of theta (degrees) in the room's frame.
static func dir_of(theta: float) -> Vector3:
	var a := deg_to_rad(theta)
	return Vector3(sin(a), 0.0, -cos(a))


## A place by theta and metres from the hall's centre, on the floor (or `over` metres above it).
static func at(p: Dictionary, theta: float, dist: float, over := 0.0) -> Vector3:
	var c := centre(p)
	var q := c + dir_of(theta) * dist
	q.y = height(p, q.x, q.z) + over
	return q


static func centre(p: Dictionary) -> Vector3:
	return Vector3(0.0, float(p["floor_y"]), float(p["centre_z"]))


## The floor's height at (x, z), the room's frame: a bowl round the hall, banks to the sides and behind, a trench behind
## the screen. Smooth, so the rocks and the fronds can sit on it.
static func height(p: Dictionary, x: float, z: float) -> float:
	var c := centre(p)
	var dx := x - c.x
	var dz := z - c.z
	var r := sqrt(dx * dx + dz * dz)
	var theta := rad_to_deg(atan2(dx, -dz))
	var r0 := float(p["radius"]) + 0.3
	var front := 1.0 - smoothstep(38.0, 78.0, absf(theta))
	var bank_h := 4.6 + 1.6 * sin(deg_to_rad(theta) * 3.0 + 0.8) + 0.9 * sin(deg_to_rad(theta) * 7.0 + 2.1)
	var rise := pow(smoothstep(r0 + 0.5, r0 + 15.0, r), 1.35)
	var drop := smoothstep(r0 + 1.5, r0 + 13.0, r) * 10.0
	var bumps := (0.35 * sin(x * 0.61 + 0.4) * sin(z * 0.53 - 1.1) + 0.16 * sin(x * 1.7 + z * 1.3)
			+ 0.08 * sin(x * 3.3 - z * 2.9)) * smoothstep(r0, r0 + 3.0, r)
	return c.y - 0.25 + (1.0 - front) * rise * bank_h - front * drop + bumps


## The floor's slope at (x, z): its normal.
static func normal_at(p: Dictionary, x: float, z: float) -> Vector3:
	var e := 0.25
	var hx := height(p, x + e, z) - height(p, x - e, z)
	var hz := height(p, x, z + e) - height(p, x, z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()


## Metres from the hall's centre to the water's edge (dome_hall.gd _build_outside: the big sphere).
static func water_radius(p: Dictionary) -> float:
	return maxf(float(p["radius"]) * 3.0, (float(p["drum_height"]) + float(p["dome_height"])) * 2.0)


# --- Building --------------------------------------------------------------------------------------------------------

## The floor, its rocks, coral, the wreck and the vent: one mesh.
static func floor_mesh(p: Dictionary, rng: RandomNumberGenerator) -> ArrayMesh:
	var m := Mesher.new()
	_floor(m, p)
	_ledges(m, p, rng)
	_rocks(m, p, rng, int(p["rocks"]))
	if int(p["coral"]) > 0:
		_coral(m, p, rng, int(p["coral"]))
	if bool(p["wreck"]):
		_wreck(m, p, rng)
	if bool(p["vent"]):
		_chimney(m, p, rng)
	return m.commit()


static func _floor(m: Mesher, p: Dictionary) -> void:
	var c := centre(p)
	var r0 := float(p["radius"]) - 0.3
	var r1 := water_radius(p) - 2.5
	var sides := 96
	var radii: Array[float] = []
	var rr := r0
	while rr < r1:
		radii.append(rr)
		rr += lerpf(0.55, 2.4, clampf((rr - r0) / (r1 - r0), 0.0, 1.0))
	radii.append(r1)
	var grid: Array = []
	for r in radii:
		var ring: Array = []
		for k in sides:
			var a := TAU * k / sides
			var x := c.x + sin(a) * r
			var z := c.z - cos(a) * r
			var q := Vector3(x, height(p, x, z), z)
			var nn := normal_at(p, x, z)
			# Sand on the flat, rock where it is steep, a little mottling.
			var steep := 1.0 - smoothstep(0.55, 0.85, nn.y)
			var mot := 0.85 + 0.15 * sin(x * 2.3 + z * 1.7) * sin(x * 0.9 - z * 2.1)
			ring.append([q, nn, SAND.lerp(ROCK, steep) * mot])
		grid.append(ring)
	for i in grid.size() - 1:
		for k in sides:
			var j := (k + 1) % sides
			var a: Array = grid[i][k]
			var b: Array = grid[i][j]
			var d: Array = grid[i + 1][k]
			var e: Array = grid[i + 1][j]
			# Seen from above: a (inner, k), d (outer, k), e (outer, k+1), b (inner, k+1).
			for t: Array in [[a, e, d], [a, b, e]]:
				for vv: Array in t:
					m.vert(vv[0], vv[1], vv[2])


## A rough boulder: an icosahedron split once, its points pushed in and out, squashed, sunk into the floor.
static func _boulder(m: Mesher, at_p: Vector3, size: Vector3, turn: float, rng: RandomNumberGenerator, col: Color,
		flat_top := false) -> void:
	var pts := _ico()
	var basis := Basis(Vector3.UP, turn)
	var seed_v := rng.randf() * 100.0
	for t: Array in pts:
		var q: Array = []
		for d: Vector3 in t:
			var bump := 1.0 + 0.18 * sin(d.x * 5.1 + seed_v) * sin(d.z * 4.3 - seed_v) + 0.1 * sin(d.y * 7.0 + seed_v)
			var s := d * bump
			if flat_top and s.y > 0.45:
				s.y = 0.45 + (s.y - 0.45) * 0.15
			q.append(at_p + basis * Vector3(s.x * size.x, s.y * size.y, s.z * size.z))
		var mid: Vector3 = (q[0] + q[1] + q[2]) / 3.0
		# Lighter, encrusted tops; darker under.
		var up := clampf(((mid - at_p).normalized()).y, -1.0, 1.0)
		var tint := col * (0.75 + 0.35 * up) * (0.9 + 0.2 * rng.randf())
		m.tri(q[0], q[1], q[2], tint)


static var _ico_cache: Array = []


## An icosahedron split once into 80 triangles on the unit sphere, wound outwards.
static func _ico() -> Array:
	if not _ico_cache.is_empty():
		return _ico_cache
	var t := (1.0 + sqrt(5.0)) / 2.0
	var vs := [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t),
			Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1),
			Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var faces := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2],
			[10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11],
			[6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for f: Array in faces:
		var a: Vector3 = (vs[f[0]] as Vector3).normalized()
		var b: Vector3 = (vs[f[1]] as Vector3).normalized()
		var c: Vector3 = (vs[f[2]] as Vector3).normalized()
		var ab := (a + b).normalized()
		var bc := (b + c).normalized()
		var ca := (c + a).normalized()
		for tri: Array in [[a, ab, ca], [ab, b, bc], [ca, bc, c], [ab, bc, ca]]:
			var n := ((tri[1] - tri[0]) as Vector3).cross(tri[2] - tri[0])
			if n.dot(tri[0]) < 0.0:
				tri = [tri[0], tri[2], tri[1]]
			_ico_cache.append(tri)
	return _ico_cache


## Two ledges near the glass that lift what grows on them over the drum: the coral's on the right, the fronds' on the
## left.
static func _ledges(m: Mesher, p: Dictionary, rng: RandomNumberGenerator) -> void:
	for spot: Array in [CORAL_LEDGE, FROND_LEDGE]:
		var q := at(p, spot[0], spot[1], 0.6)
		_boulder(m, q, Vector3(3.4, 3.4, 2.4), deg_to_rad(-float(spot[0])), rng, ROCK, true)
		for k in 3:
			var off := dir_of(float(spot[0]) + rng.randf_range(-14.0, 14.0)) * rng.randf_range(1.0, 2.5)
			var b := at(p, spot[0], spot[1]) + off
			b.y = height(p, b.x, b.z) - 0.3
			_boulder(m, b, Vector3(1.4, 1.5, 1.2) * rng.randf_range(0.8, 1.3), rng.randf() * TAU, rng, ROCK)


static func ledge_top(p: Dictionary, spot: Array) -> Vector3:
	return at(p, spot[0], spot[1], 0.6) + Vector3(0.0, 3.4 * 0.47, 0.0)


static func _rocks(m: Mesher, p: Dictionary, rng: RandomNumberGenerator, n: int) -> void:
	var r0 := float(p["radius"])
	for i in n:
		var theta := rng.randf_range(-180.0, 180.0)
		if absf(theta) < 30.0:
			theta += 60.0 * signf(theta + 0.001)
		var dist := r0 + 2.0 + pow(rng.randf(), 0.8) * (water_radius(p) - r0 - 7.0)
		var s := rng.randf_range(0.5, 2.2) * (1.0 + (dist - r0) / 20.0)
		# Clear of the glass by a metre (a bumped boulder reaches about 1.3 times its size).
		dist = clampf(dist, r0 + 1.0 + s * 1.4, water_radius(p) - 4.0 - s * 1.4)
		var q := at(p, theta, dist, -0.25)
		_boulder(m, q, Vector3(s, s * rng.randf_range(0.45, 0.8), s * rng.randf_range(0.7, 1.1)), rng.randf() * TAU,
				rng, ROCK * rng.randf_range(0.8, 1.15))


static func _coral(m: Mesher, p: Dictionary, rng: RandomNumberGenerator, n: int) -> void:
	var top := ledge_top(p, CORAL_LEDGE)
	for i in n:
		var q: Vector3
		if i < n * 2 / 3:
			# On the ledge's top.
			var off := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)) * Vector3(2.0, 0, 1.4)
			q = top + Basis(Vector3.UP, deg_to_rad(-CORAL_LEDGE[0])) * off
			q.y = top.y - 0.15 + 0.1 * rng.randf()
		else:
			var theta := float(CORAL_LEDGE[0]) + rng.randf_range(-40.0, 60.0)
			q = at(p, theta, rng.randf_range(11.0, 17.0), -0.05)
		var col: Color = CORALS[rng.randi() % CORALS.size()]
		match i % 4:
			0:
				_branching(m, q, rng, col)
			1:
				_head(m, q, rng, col.lerp(Color(0.8, 0.75, 0.6), 0.5))
			2:
				_fan(m, q, rng, col)
			_:
				_anemone(m, q, rng, col)


## A tapered four-sided limb from a to b (widths wa, wb), swaying by the given weights at its ends.
static func _limb(m: Mesher, a: Vector3, b: Vector3, wa: float, wb: float, col: Color, sa := 0.0, sb := 0.0,
		phase := 0.0) -> void:
	var d := (b - a).normalized()
	var side := d.cross(Vector3.FORWARD if absf(d.z) < 0.9 else Vector3.RIGHT).normalized()
	var up := side.cross(d).normalized()
	var ring_a: Array[Vector3] = []
	var ring_b: Array[Vector3] = []
	for k in 4:
		var ang := TAU * k / 4.0
		var o := side * cos(ang) + up * sin(ang)
		ring_a.append(a + o * wa)
		ring_b.append(b + o * wb)
	for k in 4:
		var j := (k + 1) % 4
		m.quad(ring_a[k], ring_a[j], ring_b[j], ring_b[k], col, Vector4(sa, sa, sb, sb), phase)


static func _branching(m: Mesher, q: Vector3, rng: RandomNumberGenerator, col: Color) -> void:
	var s := rng.randf_range(1.0, 1.6)
	for k in rng.randi_range(4, 6):
		var lean := Vector3(rng.randf_range(-0.5, 0.5), 1.0, rng.randf_range(-0.5, 0.5)).normalized()
		var mid := q + lean * 0.35 * s
		_limb(m, q, mid, 0.05 * s, 0.035 * s, col * 0.8)
		for j in 2:
			var tip := mid + Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(0.25, 0.45), rng.randf_range(-0.3, 0.3)) * s
			_limb(m, mid, tip, 0.03 * s, 0.012 * s, col)


static func _head(m: Mesher, q: Vector3, rng: RandomNumberGenerator, col: Color) -> void:
	var s := rng.randf_range(0.6, 1.0)
	_boulder(m, q, Vector3(s, s * 0.7, s), rng.randf() * TAU, rng, col)


static func _fan(m: Mesher, q: Vector3, rng: RandomNumberGenerator, col: Color) -> void:
	# A flat fan on a short stalk, facing across the slope; it sways a little.
	var s := rng.randf_range(0.8, 1.3)
	var turn := rng.randf() * TAU
	var right := Vector3(cos(turn), 0.0, sin(turn))
	var base := q + Vector3(0, 0.12 * s, 0)
	var steps := 7
	var phase := rng.randf()
	_limb(m, q, base, 0.03, 0.025, col * 0.7)
	for k in steps:
		var a0 := PI * (0.1 + 0.8 * k / steps)
		var a1 := PI * (0.1 + 0.8 * (k + 1) / steps)
		var p0 := base + (right * cos(a0) + Vector3.UP * sin(a0)) * s
		var p1 := base + (right * cos(a1) + Vector3.UP * sin(a1)) * s
		m.tri(base, p1, p0, col, Vector3(0.0, 0.25, 0.25), phase)


static func _anemone(m: Mesher, q: Vector3, rng: RandomNumberGenerator, col: Color) -> void:
	var s := rng.randf_range(0.3, 0.45)
	var phase := rng.randf()
	_limb(m, q, q + Vector3(0, s * 0.6, 0), s * 0.35, s * 0.4, col * 0.6)
	var top := q + Vector3(0, s * 0.6, 0)
	for k in 9:
		var a := TAU * k / 9.0
		var tip := top + Vector3(cos(a) * s * 0.7, s * 0.9, sin(a) * s * 0.7)
		var w := Vector3(cos(a + 1.57), 0, sin(a + 1.57)) * s * 0.07
		m.tri(top - w, top + w, tip, col.lerp(Color(1, 0.9, 0.8), 0.3), Vector3(0.0, 0.0, 0.18), phase)


## The fronds: beds of tall ribbons on the left ledge and bank, behind, and a few on the right.
static func fronds_mesh(p: Dictionary, rng: RandomNumberGenerator, n: int) -> ArrayMesh:
	var m := Mesher.new()
	var top := ledge_top(p, FROND_LEDGE)
	var beds := [[FROND_LEDGE[0], 0.45], [-112.0, 0.2], [165.0, 0.2], [100.0, 0.15]]
	var made := 0
	for bed: Array in beds:
		var share := int(round(n * float(bed[1])))
		for i in share:
			if made >= n:
				break
			made += 1
			var q: Vector3
			if bed[0] == FROND_LEDGE[0] and i < share / 2:
				var off := Vector3(rng.randf_range(-1.8, 1.8), 0.0, rng.randf_range(-1.2, 1.2))
				q = top + Basis(Vector3.UP, deg_to_rad(-float(FROND_LEDGE[0]))) * off
				q.y = top.y - 0.1
			else:
				q = at(p, float(bed[0]) + rng.randf_range(-16.0, 16.0), rng.randf_range(11.5, 19.0), -0.05)
			_frond(m, q, rng, rng.randf_range(3.0, 6.5) * float(p.get("frond_height", 1.0)))
	return m.commit()


## A frond as kelp grows: a thin stalk from a holdfast, and long blades off it, one at each node, turning round the
## stalk by the golden angle and rising from it; each point sways by its height up the frond.
static func _frond(m: Mesher, q: Vector3, rng: RandomNumberGenerator, h: float) -> void:
	var phase := rng.randf()
	var segs := 7
	var bend := Vector3(rng.randf_range(-0.35, 0.35), 0.0, rng.randf_range(-0.35, 0.35))
	var col := FROND * rng.randf_range(0.8, 1.25)
	var stalk := func(f: float) -> Vector3: return q + Vector3(0.0, h * f, 0.0) + bend * f * f * h * 0.3
	# The stalk: a narrow ribbon either way.
	for ribbon in 2:
		var across := Vector3(1, 0, 0) if ribbon == 0 else Vector3(0, 0, 1)
		for s in segs:
			var f0 := float(s) / segs
			var f1 := float(s + 1) / segs
			var w0 := 0.035 * (1.0 - 0.5 * f0)
			var w1 := 0.035 * (1.0 - 0.5 * f1)
			var a: Vector3 = stalk.call(f0)
			var b: Vector3 = stalk.call(f1)
			m.quad(a - across * w0, a + across * w0, b + across * w1, b - across * w1, col * 0.8,
					Vector4(f0, f0, f1, f1), phase)
	# The blades: a long leaf at each node, wider in its middle, rippled at its edge.
	var turn := rng.randf() * TAU
	var nodes := 9
	for k in nodes:
		var f := (float(k) + 0.6) / nodes
		var base: Vector3 = stalk.call(f)
		turn += 2.39996
		var out := Vector3(cos(turn), 0.0, sin(turn))
		var length := rng.randf_range(0.7, 1.2) * (1.0 - 0.35 * f) * clampf(h / 4.5, 0.6, 1.3)
		var rise := rng.randf_range(0.9, 1.6)
		var tip := base + (out + Vector3.UP * rise).normalized() * length
		var mid := base.lerp(tip, 0.45) + out * 0.06
		var side := out.cross(Vector3.UP).normalized() * rng.randf_range(0.09, 0.15)
		var ft := clampf(f + (tip.y - base.y) / h, 0.0, 1.0)
		var fm := (f + ft) * 0.5
		var leaf := col.lerp(Color(0.5, 0.42, 0.12), 0.35 + 0.4 * f)
		m.quad(base, mid - side, tip, mid + side, leaf, Vector4(f, fm, ft, fm), phase)


## The wreck on the left bank behind: an old diving bell on its skid, tilted, half silted; a fallen lattice derrick
## and an anchor.
static func _wreck(m: Mesher, p: Dictionary, rng: RandomNumberGenerator) -> void:
	var base := at(p, WRECK_AT[0], WRECK_AT[1], 0.0)
	var face := dir_of(float(WRECK_AT[0]) + 180.0)
	var tilt := Basis(face.cross(Vector3.UP).normalized(), deg_to_rad(14.0)) * Basis(Vector3.UP, 0.6)
	var bell_c := base + Vector3(0.0, 0.75, 0.0)
	var rr := 1.15
	# The bell: a sphere of 8 rings, rusted and crusted.
	var rings := 8
	var sides := 14
	var pts: Array = []
	for i in rings + 1:
		var lat := PI * (float(i) / rings - 0.5)
		var ring: Array[Vector3] = []
		for k in sides:
			var a := TAU * k / sides
			ring.append(bell_c + tilt * (Vector3(cos(lat) * cos(a), sin(lat), cos(lat) * sin(a)) * rr))
		pts.append(ring)
	for i in rings:
		for k in sides:
			var j := (k + 1) % sides
			var crust := 0.75 + 0.4 * absf(sin(k * 1.7 + i * 2.3))
			m.quad(pts[i][k], pts[i + 1][k], pts[i + 1][j], pts[i][j], RUST * crust)
	# Three portholes facing out (towards the dome), each a dark disc in a raised rim.
	for k in 3:
		var a := deg_to_rad(-40.0 + 40.0 * k)
		var out := tilt * Vector3(sin(a), 0.1, cos(a)).normalized()
		out = (Basis(Vector3.UP, atan2(face.x, face.z)) * out).normalized()
		var centre_p := bell_c + out * (rr + 0.02)
		_disc(m, centre_p, out, 0.26, Color(0.55, 0.42, 0.2), 0.06)
		_disc(m, centre_p + out * 0.02, out, 0.2, Color(0.02, 0.05, 0.06), 0.0)
	# The hatch on top and its lifting eye.
	var top := bell_c + tilt * Vector3(0.0, rr, 0.0)
	_limb(m, top - tilt * Vector3(0, 0.05, 0), top + tilt * Vector3(0, 0.18, 0), 0.42, 0.4, RUST * 0.9)
	var eye_c := top + tilt * Vector3(0, 0.42, 0)
	for k in 8:
		var a0 := TAU * k / 8.0
		var a1 := TAU * (k + 1) / 8.0
		_limb(m, eye_c + tilt * Vector3(cos(a0) * 0.2, sin(a0) * 0.2, 0), eye_c + tilt * Vector3(cos(a1) * 0.2,
				sin(a1) * 0.2, 0), 0.04, 0.04, RUST)
	# The skid: two runners and three cross beams, sunk in the silt.
	var sk := Basis(Vector3.UP, atan2(face.x, face.z))
	for sx: float in [-0.8, 0.8]:
		_limb(m, base + sk * Vector3(sx, 0.05, -1.4), base + sk * Vector3(sx, 0.05, 1.4), 0.12, 0.12, RUST * 0.8)
	for sz: float in [-1.1, 0.0, 1.1]:
		_limb(m, base + sk * Vector3(-0.8, 0.15, sz), base + sk * Vector3(0.8, 0.15, sz), 0.08, 0.08, RUST * 0.7)
	# Silt heaped round its foot.
	_boulder(m, base + Vector3(0, -0.35, 0), Vector3(2.0, 0.6, 2.0), 0.0, rng, SAND * 0.95)
	# The derrick: a lattice mast lying across the bank, broken off, its foot in the silt.
	var d0 := at(p, float(WRECK_AT[0]) + 12.0, float(WRECK_AT[1]) + 2.5, 0.3)
	var d1 := at(p, float(WRECK_AT[0]) - 8.0, float(WRECK_AT[1]) + 6.0, 1.8)
	var along := (d1 - d0)
	var side := along.cross(Vector3.UP).normalized() * 0.45
	var up := Vector3.UP * 0.45
	var corners := [side, -side, side + up, -side + up]
	for cc: Vector3 in corners:
		_limb(m, d0 + cc, d1 + cc * 0.5, 0.05, 0.04, RUST * 0.85)
	var bays := 7
	for b in bays:
		var f0 := float(b) / bays
		var f1 := float(b + 1) / bays
		var a0 := d0.lerp(d1, f0)
		var a1 := d0.lerp(d1, f1)
		var s0 := lerpf(1.0, 0.5, f0)
		var s1 := lerpf(1.0, 0.5, f1)
		_limb(m, a0 + side * s0, a1 - side * s1, 0.03, 0.03, RUST * 0.8)
		_limb(m, a0 + (side + up) * s0, a1 + (-side + up) * s1, 0.03, 0.03, RUST * 0.8)
	# The anchor: a shank, a stock across its top, two curved arms.
	var an := at(p, float(WRECK_AT[0]) - 14.0, float(WRECK_AT[1]) - 1.5, 0.15)
	var dirx := Vector3(0.94, 0.25, 0.2).normalized()
	_limb(m, an, an + dirx * 1.6, 0.07, 0.06, RUST * 0.75)
	_limb(m, an + dirx * 1.5 + Vector3(0, -0.1, -0.6), an + dirx * 1.5 + Vector3(0, 0.1, 0.6), 0.05, 0.05, RUST * 0.7)
	for sz: float in [-1.0, 1.0]:
		_limb(m, an, an + Vector3(-0.3, 0.45, sz * 0.55), 0.07, 0.04, RUST * 0.75)


## A flat disc facing `out`, with a short rim back from it (depth metres).
static func _disc(m: Mesher, c: Vector3, out: Vector3, r: float, col: Color, depth: float) -> void:
	var side := out.cross(Vector3.UP if absf(out.y) < 0.9 else Vector3.RIGHT).normalized()
	var up := side.cross(out).normalized()
	var n := 10
	for k in n:
		var a0 := TAU * k / n
		var a1 := TAU * (k + 1) / n
		var p0 := c + (side * cos(a0) + up * sin(a0)) * r
		var p1 := c + (side * cos(a1) + up * sin(a1)) * r
		m.tri(c, p0, p1, col)
		if depth > 0.0:
			m.quad(p0 - out * depth, p1 - out * depth, p1, p0, col * 0.8)


## The vent's chimney: a rough tapering stack of rock.
static func _chimney(m: Mesher, p: Dictionary, rng: RandomNumberGenerator) -> void:
	var q := vent_foot(p)
	var levels := [[0.0, 1.0], [0.8, 0.75], [1.6, 0.55], [2.4, 0.4], [2.9, 0.32]]
	var sides := 9
	var rings: Array = []
	for lv: Array in levels:
		var ring: Array[Vector3] = []
		for k in sides:
			var a := TAU * k / sides
			var w := float(lv[1]) * (0.85 + 0.3 * rng.randf())
			ring.append(q + Vector3(cos(a) * w, float(lv[0]), sin(a) * w))
		rings.append(ring)
	for i in rings.size() - 1:
		for k in sides:
			var j := (k + 1) % sides
			var col := Color(0.12, 0.11, 0.1) * (0.8 + 0.4 * rng.randf())
			if i == rings.size() - 2:
				col = Color(0.42, 0.36, 0.22)
			m.quad(rings[i][k], rings[i + 1][k], rings[i + 1][j], rings[i][j], col)
	for k in 4:
		var b := q + Vector3(rng.randf_range(-1.6, 1.6), -0.2, rng.randf_range(-1.6, 1.6))
		_boulder(m, b, Vector3(0.7, 0.5, 0.6) * rng.randf_range(0.7, 1.3), rng.randf() * TAU, rng, ROCK * 0.7)


static func vent_foot(p: Dictionary) -> Vector3:
	return at(p, VENT_AT[0], VENT_AT[1], -0.2)


static func vent_top(p: Dictionary) -> Vector3:
	return vent_foot(p) + Vector3(0.0, 2.95, 0.0)


## Specks: n quads, each its four corners at one place (the shader spreads them), with seeds.
static func motes_mesh(p: Dictionary, rng: RandomNumberGenerator, n: int, snow: bool) -> ArrayMesh:
	var c := centre(p)
	var r0 := float(p["radius"]) + 0.3
	var r1 := minf(r0 + 13.0, water_radius(p) - 2.0)
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()
	for i in n:
		var q := Vector3.ZERO
		if snow:
			var a := rng.randf() * TAU
			var r := r0 + pow(rng.randf(), 1.5) * (r1 - r0)
			q = c + Vector3(sin(a) * r, rng.randf_range(-2.0, 20.0), -cos(a) * r)
		var s1 := rng.randf()
		var s2 := rng.randf()
		var s3 := rng.randf()
		var base := v.size()
		for corner: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
			v.append(q)
			uv.append(corner)
			uv2.append(Vector2(s1, s2))
			col.append(Color(s3, 0, 0, 1))
		idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = v
	a[Mesh.ARRAY_TEX_UV] = uv
	a[Mesh.ARRAY_TEX_UV2] = uv2
	a[Mesh.ARRAY_COLOR] = col
	a[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	if n > 0:
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	# The shader moves them anywhere in the water: never culled by their bounds.
	m.custom_aabb = AABB(c - Vector3(30, 10, 30), Vector3(60, 45, 60))
	return m


## The floodlights: [position, aim] each, on the drum's top outside, aimed at FLOOD_TARGETS.
static func floods(p: Dictionary, n: int) -> Array:
	var out: Array = []
	var c := centre(p)
	var r := float(p["radius"]) + 0.15
	for i in mini(n, FLOOD_TARGETS.size()):
		var t: Array = FLOOD_TARGETS[i]
		var lamp := c + dir_of(float(t[0])) * r + Vector3(0.0, float(p["drum_height"]) + 0.2, 0.0)
		var target := at(p, t[0], t[1], t[2])
		out.append([lamp, (target - lamp).normalized()])
	return out


## The beams: an open cone for each lamp, `reach` metres long, its half angle `deg`, 0.1 m across at the lens (the
## shader draws the soft beam inside it, env_water_beam.gdshader).
static func beams_mesh(lamps: Array, reach: float, deg: float) -> ArrayMesh:
	var m := Mesher.new()
	var sides := 12
	var rings := 5
	for li in lamps.size():
		var l: Array = lamps[li]
		var o: Vector3 = l[0]
		var d: Vector3 = l[1]
		var side := d.cross(Vector3.UP).normalized()
		var up := side.cross(d).normalized()
		var spread := tan(deg_to_rad(deg))
		for i in rings:
			var f0 := float(i) / rings
			var f1 := float(i + 1) / rings
			for k in sides:
				var a0 := TAU * k / sides
				var a1 := TAU * (k + 1) / sides
				var pts := []
				for e: Array in [[f0, a0], [f0, a1], [f1, a1], [f1, a0]]:
					var f: float = e[0]
					var a: float = e[1]
					var rad := 0.1 + spread * reach * f
					var radial := side * cos(a) + up * sin(a)
					pts.append([o + d * reach * f + radial * rad, radial, f])
				for t: Array in [[0, 1, 2], [0, 2, 3]]:
					for j: int in t:
						m.v.append(pts[j][0])
						m.n.append(pts[j][1])
						m.c.append(Color.WHITE)
						m.uv.append(Vector2(float(li), pts[j][2]))
						m.uv2.append(Vector2.ZERO)
	return m.commit()


## The caustics' map (procedural.gd), shared with the light system's caustics.
static func caustic_map() -> Texture2D:
	return Procedural.caustic_map()
