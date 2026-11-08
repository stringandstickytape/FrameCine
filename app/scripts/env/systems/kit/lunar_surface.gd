extends RefCounted

## The Moon round the Crater's dome (terrace.gd's amphitheatre with `lunar` on; since 2026-11-08, the Crater's quality
## pass: "a Moon base cinema that makes people gasp", the brief). Everything outside the glass, made here from code; no
## file, no texture but a small map of craterlets drawn once.
##   Plain      fine grey regolith from the dome's foot to the crater's wall, banked up against the drum, rolling more
##              the farther it goes; small craters with raised rims and their ejecta, a large one ahead to the left
##   Rocks      boulders sitting in dust skirts, each with its own sharp shadow cast away from Earth
##   Rim        the crater's wall all round at 135 to 160 m, its peaks catching the sun (just under the horizon behind
##              the room: only the tops are lit), the rest in earthlight
##   Base       ahead to the left, a cluster of habitat modules half buried in regolith with warm windows, a node, a
##              lattice mast with its dish and a slow red beacon, solar arrays standing to the sun (their tops lit);
##              to the right a cargo lander in gold foil; a pressurised rover parked by the right airlock, its tracks
##              curving away to the base and the lander; footprints from the left airlock to a small instrument
##              station; amber marker lights along the track
## One draw for the ground and everything on it (shaders/env_regolith.gdshader: its own light, Earth's from Earth's
## place, the sun's on what stands above the shadow's line, the dome's lamps on the berm, the film's through the glass),
## one for the lights (shaders/env_lunar_lights.gdshader: points that face the eye, never smaller than a few pixels, so
## they never shimmer). Never baked; nothing moves but the beacon's slow glow. No people, no mark of anyone's.
## The room's frame: the viewer's own seat at the origin facing -Z; the dome's centre `c`, its radius `r`.

const REGOLITH_SHADER := preload("res://shaders/env_regolith.gdshader")
const LIGHTS_SHADER := preload("res://shaders/env_lunar_lights.gdshader")

## The shader's materials (UV2.x).
const M_REGOLITH := 0
const M_ROCK := 1
const M_SHADOW := 2
const M_TRACK := 3
const M_PRINTS := 4
const M_PAINT := 5
const M_FOIL := 6
const M_SOLAR := 7
const M_RIM := 8
const M_GLASS := 9

## How far the plain goes from the dome's centre, and the rim's foot, crest and back (metres): the far plane is
## 200 m and the sky's layers start at 175, so nothing reaches past 160 from the dome's centre (the farthest seat is
## 15 m from it).
const PLAIN_TO := 138.0
const RIM_FOOT := 128.0
const RIM_CREST := 148.0
const RIM_BACK := 160.0
## The plain's grid: metres a ring at the dome, growing outwards by this share of the distance; spokes round.
const RING_STEP := 0.4
const RING_GROWTH := 0.03
const SPOKES := 240

## Craters: [x, z, radius] in the room's frame (the viewer at the origin, the screen ahead at -Z).
const CRATERS := [
	[-56.0, -96.0, 22.0], [50.0, -74.0, 12.0], [-26.0, -38.0, 3.2], [23.0, -40.0, 2.2], [-34.0, -14.0, 4.0],
	[33.0, -22.0, 5.0], [-13.0, -54.0, 2.5], [11.0, -50.0, 1.6], [-42.0, -62.0, 6.0], [74.0, -38.0, 9.0],
	[-80.0, -28.0, 10.0], [36.0, -112.0, 15.0], [-22.0, -124.0, 8.0], [2.0, -78.0, 4.0], [-58.0, -10.0, 5.5],
	[62.0, -8.0, 7.0], [-6.0, -36.0, 1.2], [-30.0, -78.0, 3.0], [18.0, -92.0, 6.0], [92.0, -82.0, 11.0],
	[-98.0, -70.0, 9.0], [-36.0, 22.0, 4.5], [38.0, 30.0, 6.0],
]
## The base: its middle, the lander's, the rover's and the instrument station's (x, z).
const BASE_AT := Vector2(-60.0, -62.0)
const LANDER_AT := Vector2(66.0, -60.0)
const ROVER_AT := Vector2(27.5, -14.5)
const STATION_AT := Vector2(-35.0, -27.0)
## The airlocks' bearings from the dome's centre (degrees from ahead, positive to the right), as dome_hall builds
## them (its `airlocks`: the first pair at +-62), and how far their tubes reach past the glass.
const AIRLOCK_THETA := 62.0
const TUBE_OUT := 5.5

static var _detail: ImageTexture


## Vertex arrays for one mesh: an indexed part (the plain's grid) and flat triangles alike.
class Mesher:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()

	func vert(p: Vector3, nn: Vector3, col: Color, mat: int, extra := 0.0, tex := Vector2.ZERO) -> int:
		v.append(p)
		n.append(nn)
		c.append(col)
		uv.append(tex)
		uv2.append(Vector2(mat, extra))
		return v.size() - 1

	func tri(a: Vector3, b: Vector3, cc: Vector3, col: Color, mat: int, extra := 0.0) -> void:
		var nn := (b - a).cross(cc - a).normalized()
		var i := v.size()
		vert(a, nn, col, mat, extra)
		vert(b, nn, col, mat, extra)
		vert(cc, nn, col, mat, extra)
		idx.append_array([i, i + 1, i + 2])

	func quad(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, col: Color, mat: int, extra := 0.0) -> void:
		tri(a, b, cc, col, mat, extra)
		tri(a, cc, d, col, mat, extra)

	func commit() -> ArrayMesh:
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = v
		a[Mesh.ARRAY_NORMAL] = n
		a[Mesh.ARRAY_COLOR] = c
		a[Mesh.ARRAY_TEX_UV] = uv
		a[Mesh.ARRAY_TEX_UV2] = uv2
		a[Mesh.ARRAY_INDEX] = idx
		var m := ArrayMesh.new()
		if not v.is_empty():
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		return m


## The ground's shape and what stands on it, from the dome (centre c on its floor, radius r) and the room's floor.
class Ground:
	var c: Vector3
	var r: float
	var gy: float
	var noise := FastNoiseLite.new()

	func _init(centre: Vector3, radius: float) -> void:
		c = centre
		r = radius
		gy = centre.y
		noise.seed = 1969
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.018
		noise.fractal_octaves = 3

	## The ground's height at (x, z): the plain at the floor's level, banked against the drum, rolling farther out,
	## rising to the rim's foot; the craters.
	func height(x: float, z: float) -> float:
		var dx := x - c.x
		var dz := z - c.z
		var rho := sqrt(dx * dx + dz * dz)
		var far := sqrt(x * x + z * z)
		var h := 0.5 * (1.0 - smoothstep(r, r + 3.2, rho))
		h += noise.get_noise_2d(x, z) * (0.12 + 1.6 * smoothstep(24.0, 120.0, far))
		h += 0.05 * noise.get_noise_2d(x * 7.0 + 31.0, z * 7.0) * smoothstep(r + 1.0, r + 6.0, rho)
		h += 3.5 * smoothstep(PLAIN_TO - 30.0, RIM_FOOT + 6.0, rho)
		for k: Array in CRATERS:
			var cx := float(k[0])
			var cz := float(k[1])
			var cr := float(k[2])
			var ddx := x - cx
			var ddz := z - cz
			var d2 := ddx * ddx + ddz * ddz
			if d2 > cr * cr * 9.0:
				continue
			var q := sqrt(d2) / cr
			h += crater(q) * cr
		return gy + h

	## A crater's profile at q (distance over its radius), in its radius: a bowl, a raised rim, ejecta falling away.
	static func crater(q: float) -> float:
		if q < 1.0:
			return -0.2 * (1.0 - q * q) + 0.055 * pow(q, 6.0)
		return 0.055 * exp(-(q - 1.0) * 3.2)

	func normal(x: float, z: float) -> Vector3:
		var e := 0.15
		var hx := height(x + e, z) - height(x - e, z)
		var hz := height(x, z + e) - height(x, z - e)
		return Vector3(-hx, 2.0 * e, -hz).normalized()

	func on(x: float, z: float, over := 0.0) -> Vector3:
		return Vector3(x, height(x, z) + over, z)


## Everything outside: {regolith: the ground's material, lights: the lights' material}. `earth`: the direction to
## Earth (room frame); `sun`: to the sun (just under the horizon behind).
static func build(t: Object, c: Vector3, r: float, earth: Vector3, sun: Vector3, lamp_colour: Color) -> Dictionary:
	var g := Ground.new(c, r)
	var m := Mesher.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1972
	var lights: Array = []
	_plain(m, g)
	_rim(m, g, rng)
	var paths := track_paths(g)
	_rocks(m, g, rng, earth, paths)
	_tracks(m, g)
	_prints(m, g, rng)
	_base(m, g, rng, earth, lights)
	_lander(m, g, earth)
	_rover(m, g, earth, lights)
	_station(m, g, earth)
	_airlock_tubes(m, g, lights)
	_markers(m, g, lights)
	var mat := ShaderMaterial.new()
	mat.shader = REGOLITH_SHADER
	mat.set_shader_parameter("detail", detail_texture())
	mat.set_shader_parameter("earth_dir", earth)
	mat.set_shader_parameter("sun_dir", sun)
	# The shadow's line: under it the sun is hidden behind the rim at the back. It rises towards the sun.
	var flat := Vector2(sun.x, sun.z).normalized()
	mat.set_shader_parameter("sun_line", Vector4(flat.x, 0.0, flat.y, 0.0) * 0.018 + Vector4(0, 0, 0, gy_line(c.y)))
	mat.set_shader_parameter("dome_centre", c)
	mat.set_shader_parameter("dome_radius", r)
	mat.set_shader_parameter("lamp_colour", lamp_colour)
	var mesh := m.commit()
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = "Moon"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	t.own(mi)
	var lm := _lights_mesh(lights)
	var lmi := MeshInstance3D.new()
	lmi.name = "MoonLights"
	lmi.mesh = lm[0]
	lmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	lmi.add_to_group(t.SEE_THROUGH)
	# The lights face the eye: their bounds are their points' grown by their size.
	lmi.custom_aabb = (lm[0] as ArrayMesh).get_aabb().grow(4.0)
	t.own(lmi)
	return {"regolith": mat, "lights": lm[1], "triangles": m.idx.size() / 3}


## The sun's shadow line's height at the room's middle: the rim behind stands 18 m over the floor there.
static func gy_line(floor_y: float) -> float:
	return floor_y + 19.0


# --- The ground ---------------------------------------------------------------------------------------------------------

## The plain: rings round the dome from under its drum out to past the rim's foot, finer near.
static func _plain(m: Mesher, g: Ground) -> void:
	var radii: Array[float] = []
	var rr := g.r - 0.15
	while rr < PLAIN_TO:
		radii.append(rr)
		rr += maxf(RING_STEP, rr * RING_GROWTH) * (0.6 if rr < g.r + 4.0 else 1.0)
	radii.append(PLAIN_TO)
	var base := m.v.size()
	var rows: Array[PackedFloat32Array] = []
	for i in radii.size():
		var hs := PackedFloat32Array()
		for k in SPOKES:
			var a := TAU * k / SPOKES
			var x := g.c.x + sin(a) * radii[i]
			var z := g.c.z - cos(a) * radii[i]
			var y := g.height(x, z)
			# Under the drum the ground keeps to the floor (the dome's own floor is there).
			if i == 0:
				y = g.gy - 0.02
			hs.append(y)
		rows.append(hs)
	for i in radii.size():
		for k in SPOKES:
			var a := TAU * k / SPOKES
			var x := g.c.x + sin(a) * radii[i]
			var z := g.c.z - cos(a) * radii[i]
			var nn := g.normal(x, z) if i > 0 else Vector3.UP
			var tone := 0.92 + 0.08 * g.noise.get_noise_2d(x * 3.1 + 7.0, z * 3.1)
			m.vert(Vector3(x, rows[i][k], z), nn, Color(tone, tone, tone, 1.0), M_REGOLITH)
	for i in radii.size() - 1:
		for k in SPOKES:
			var a := base + i * SPOKES + k
			var b := base + i * SPOKES + (k + 1) % SPOKES
			var a2 := a + SPOKES
			var b2 := b + SPOKES
			m.idx.append_array([a, b, b2, a, b2, a2])


## The crater's wall: a ring of ridges from its foot up to the crest and down behind, peaks and saddles from noise.
static func _rim(m: Mesher, g: Ground, rng: RandomNumberGenerator) -> void:
	var n := FastNoiseLite.new()
	n.seed = 1971
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 1.0
	n.fractal_octaves = 4
	var segs := 360
	var crest: Array[float] = []
	for k in segs:
		var a := TAU * k / segs
		# Peaks and saddles: low hills ahead (under the screen's sight), higher to the sides and behind.
		var p := Vector2(cos(a), sin(a)) * 2.2
		var big := n.get_noise_2d(p.x, p.y) * 0.5 + 0.5
		var ahead := absf(wrapf(a, -PI, PI))
		var ridge := 1.0 - absf(n.get_noise_2d(p.x * 2.3 + 5.0, p.y * 2.3))
		var h := 5.0 + 12.0 * pow(big, 1.4) + 14.0 * pow(ridge, 3.0) * big + 2.5 * n.get_noise_2d(p.x * 7.0, p.y * 7.0)
		h *= lerpf(0.75, 1.0, smoothstep(0.2, 0.9, ahead))
		crest.append(h)
	# Rows from the foot (the plain's height there) up the inner face to the crest and down the back.
	var profile := [[RIM_FOOT, 0.0], [RIM_FOOT + 6.0, 0.08], [RIM_FOOT + 11.0, 0.3], [RIM_FOOT + 15.0, 0.6],
			[RIM_CREST - 2.0, 0.88], [RIM_CREST, 1.0], [RIM_CREST + 4.0, 0.92], [RIM_BACK, 0.7]]
	var base := m.v.size()
	for j in profile.size():
		for k in segs + 1:
			var a := TAU * (k % segs) / segs
			var rho := float(profile[j][0])
			var x := g.c.x + sin(a) * rho
			var z := g.c.z - cos(a) * rho
			var foot := g.height(x, z) if j == 0 else g.gy + 3.5
			var jag := n.get_noise_2d(cos(a) * 30.0 + j * 3.0, sin(a) * 30.0) * 2.4 * float(profile[j][1])
			var y := lerpf(foot, g.gy + 3.5 + crest[k % segs], float(profile[j][1])) + jag
			if j == 0:
				y = g.height(x, z)
			m.vert(Vector3(x, y, z), Vector3.UP, Color(1, 1, 1, 1), M_RIM)
	# Normals from the rows' neighbours.
	var w := segs + 1
	for j in profile.size():
		for k in w:
			var i := base + j * w + k
			var right := m.v[base + j * w + mini(k + 1, w - 1)] - m.v[base + j * w + maxi(k - 1, 0)]
			var up := m.v[base + mini(j + 1, profile.size() - 1) * w + k] - m.v[base + maxi(j - 1, 0) * w + k]
			var nn := up.cross(right).normalized()
			if nn.y < 0.0:
				nn = -nn
			m.n[i] = nn
	for j in profile.size() - 1:
		for k in segs:
			var a := base + j * w + k
			var b := a + 1
			var a2 := a + w
			var b2 := b + w
			m.idx.append_array([a, b, b2, a, b2, a2])


# --- Rocks ---------------------------------------------------------------------------------------------------------------

## Boulders on the plain in their dust skirts, each with its shadow cast away from Earth. Most small and near, a few
## large farther out; none in the airlocks' ways.
static func _rocks(m: Mesher, g: Ground, rng: RandomNumberGenerator, earth: Vector3,
		paths: Array[PackedVector2Array]) -> void:
	var placed := 0
	var tries := 0
	while placed < 70 and tries < 400:
		tries += 1
		var a := rng.randf() * TAU
		var dist := g.r + 2.5 + pow(rng.randf(), 1.7) * 95.0
		var x := g.c.x + sin(a) * dist
		var z := g.c.z - cos(a) * dist
		if _in_the_way(g, x, z, paths):
			continue
		var size := clampf(0.18 + pow(rng.randf(), 3.0) * 2.4 * (0.5 + dist / 90.0), 0.15, 3.2)
		_boulder(m, g, Vector3(x, 0, z), size, rng, earth)
		placed += 1


## Whether (x, z) is where something else stands or goes (the tracks, the airlocks' tubes, the base, the lander).
static func _in_the_way(g: Ground, x: float, z: float, paths: Array[PackedVector2Array]) -> bool:
	var p := Vector2(x, z)
	for q: Vector2 in [BASE_AT, LANDER_AT, ROVER_AT, STATION_AT]:
		if p.distance_to(q) < (16.0 if q == BASE_AT else 7.0):
			return true
	for s: float in [-1.0, 1.0]:
		var d := Vector2(sin(deg_to_rad(AIRLOCK_THETA * s)), -cos(deg_to_rad(AIRLOCK_THETA * s)))
		var o := Vector2(g.c.x, g.c.z)
		var along := (p - o).dot(d)
		if along > g.r - 1.0 and along < g.r + TUBE_OUT + 4.0 and absf((p - o).dot(Vector2(-d.y, d.x))) < 4.0:
			return true
	for path: PackedVector2Array in paths:
		for i in path.size() - 1:
			if Geometry2D.get_closest_point_to_segment(p, path[i], path[i + 1]).distance_to(p) < 2.6:
				return true
	return false


## A boulder: a squashed, lumpy ball sunk a little into the ground, a skirt of dust round its foot, and its shadow.
static func _boulder(m: Mesher, g: Ground, at: Vector3, size: float, rng: RandomNumberGenerator, earth: Vector3) -> void:
	var ground := g.height(at.x, at.z)
	var squash := Vector3(rng.randf_range(0.8, 1.25), rng.randf_range(0.5, 0.85), rng.randf_range(0.8, 1.25)) * size
	var turn := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.25, 0.25))
	var centre := Vector3(at.x, ground + squash.y * 0.45, at.z)
	var ico := _ico(1)
	var verts: Array = ico[0]
	var faces: Array = ico[1]
	var seed_v := rng.randf() * 100.0
	var pts: Array[Vector3] = []
	for p: Vector3 in verts:
		var bump := 1.0 + 0.22 * sin(p.x * 3.1 + seed_v) * sin(p.y * 2.7 + seed_v * 0.7) + 0.12 * sin(p.z * 5.3 - seed_v)
		var q := centre + turn * (p * squash * bump)
		# Never under the ground's skin by more than it is sunk.
		q.y = maxf(q.y, ground - 0.15 * size)
		pts.append(q)
	var tone := rng.randf_range(0.6, 1.0)
	var col := Color(tone, tone * 0.98, tone * 0.95, 1.0)
	for f: Array in faces:
		m.tri(pts[f[0]], pts[f[1]], pts[f[2]], col, M_ROCK, seed_v)
	# The skirt: dust banked round its foot, from the rock's waist line out to the ground.
	var sides := 10
	var foot := maxf(squash.x, squash.z)
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var p0 := Vector3(sin(a0), 0, cos(a0))
		var p1 := Vector3(sin(a1), 0, cos(a1))
		var i0 := at + p0 * foot * 0.85
		var i1 := at + p1 * foot * 0.85
		var o0 := at + p0 * foot * 1.7
		var o1 := at + p1 * foot * 1.7
		i0.y = g.height(i0.x, i0.z) + 0.22 * size
		i1.y = g.height(i1.x, i1.z) + 0.22 * size
		o0.y = g.height(o0.x, o0.z) + 0.01
		o1.y = g.height(o1.x, o1.z) + 0.01
		var na := (p0 + Vector3.UP * 2.5).normalized()
		var nb := (p1 + Vector3.UP * 2.5).normalized()
		var j := m.v.size()
		m.vert(i0, na, Color(1, 1, 1, 1), M_REGOLITH)
		m.vert(i1, nb, Color(1, 1, 1, 1), M_REGOLITH)
		m.vert(o1, Vector3.UP, Color(1, 1, 1, 1), M_REGOLITH)
		m.vert(o0, Vector3.UP, Color(1, 1, 1, 1), M_REGOLITH)
		m.idx.append_array([j, j + 1, j + 2, j, j + 2, j + 3])
	_shadow(m, g, pts, earth, at, size)


## A shadow on the ground: the outline of `pts` cast along Earth's light onto the ground, a flat dark patch a hair
## over it (the shader lights it with the sky's faint fill only). Earth stands 30 degrees up: shadows are long.
static func _shadow(m: Mesher, g: Ground, pts: Array[Vector3], earth: Vector3, at: Vector3, size: float) -> void:
	var flat: Array[Vector2] = []
	var ground := g.height(at.x, at.z)
	for q: Vector3 in pts:
		var h := maxf(q.y - ground, 0.0)
		var s := q - earth * (h / maxf(earth.y, 0.05))
		flat.append(Vector2(s.x, s.z))
	var hull := Geometry2D.convex_hull(PackedVector2Array(flat))
	if hull.size() < 4:
		return
	var mid := Vector2.ZERO
	for i in hull.size() - 1:
		mid += hull[i]
	mid /= float(hull.size() - 1)
	var lift := 0.02 + 0.004 * size
	var cy := g.height(mid.x, mid.y) + lift
	var centre := Vector3(mid.x, cy, mid.y)
	for i in hull.size() - 1:
		var a := Vector3(hull[i].x, g.height(hull[i].x, hull[i].y) + lift, hull[i].y)
		var b := Vector3(hull[i + 1].x, g.height(hull[i + 1].x, hull[i + 1].y) + lift, hull[i + 1].y)
		var j := m.v.size()
		m.vert(centre, Vector3.UP, Color(1, 1, 1, 1), M_SHADOW)
		m.vert(b, Vector3.UP, Color(1, 1, 1, 1), M_SHADOW)
		m.vert(a, Vector3.UP, Color(1, 1, 1, 1), M_SHADOW)
		m.idx.append_array([j, j + 1, j + 2])


## An icosphere's points and faces (level 0 or 1).
static func _ico(level: int) -> Array:
	var t := (1.0 + sqrt(5.0)) * 0.5
	var verts: Array = [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t),
			Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1),
			Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	for i in verts.size():
		verts[i] = (verts[i] as Vector3).normalized()
	var faces: Array = [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2],
			[10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11],
			[6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for l in level:
		var next: Array = []
		var mids := {}
		for f: Array in faces:
			var ms: Array[int] = []
			for e in 3:
				var a: int = f[e]
				var b: int = f[(e + 1) % 3]
				var key := "%d_%d" % [mini(a, b), maxi(a, b)]
				if not mids.has(key):
					verts.append(((verts[a] as Vector3) + (verts[b] as Vector3)).normalized())
					mids[key] = verts.size() - 1
				ms.append(mids[key])
			next.append([f[0], ms[0], ms[2]])
			next.append([f[1], ms[1], ms[0]])
			next.append([f[2], ms[2], ms[1]])
			next.append([ms[0], ms[1], ms[2]])
		faces = next
	# Outward winding for the mesher's flat normals: (b - a) x (c - a) points out.
	for f: Array in faces:
		var a: Vector3 = verts[f[0]]
		var b: Vector3 = verts[f[1]]
		var c: Vector3 = verts[f[2]]
		if (b - a).cross(c - a).dot(a + b + c) < 0.0:
			var k: int = f[1]
			f[1] = f[2]
			f[2] = k
	return [verts, faces]


# --- Tracks and prints ---------------------------------------------------------------------------------------------------

## The rover's tracks: from the right airlock's tube past the rover, one way round to the base ahead on the left, the
## other out to the lander on the right. Points (x, z) along each.
static func track_paths(g: Ground) -> Array[PackedVector2Array]:
	var o := Vector2(g.c.x, g.c.z)
	var d := Vector2(sin(deg_to_rad(AIRLOCK_THETA)), -cos(deg_to_rad(AIRLOCK_THETA)))
	var start := o + d * (g.r + TUBE_OUT + 1.2)
	var to_base := _spline([start, start + d * 6.0, Vector2(18.0, -46.0), Vector2(-8.0, -66.0),
			Vector2(-34.0, -66.0), BASE_AT + Vector2(12.0, -2.0)])
	var to_lander := _spline([start, start + d * 6.0 + Vector2(2.0, -2.0), Vector2(44.0, -40.0),
			LANDER_AT + Vector2(-9.0, 4.0)])
	return [to_base, to_lander]


## A smooth path through points (Catmull-Rom), about a metre a step.
static func _spline(pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in pts.size() - 1:
		var p0: Vector2 = pts[maxi(i - 1, 0)]
		var p1: Vector2 = pts[i]
		var p2: Vector2 = pts[i + 1]
		var p3: Vector2 = pts[mini(i + 2, pts.size() - 1)]
		var steps := maxi(int(p1.distance_to(p2) / 1.0), 2)
		for s in steps:
			var t := float(s) / steps
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
					+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(pts[-1])
	return out


## A band laid on the ground along a path (`offset` metres to its side, `width` across): UV.x metres along, UV.y 0 to 1
## across; the path's direction in COLOR.rg (for the shader's tread and prints), its fade-out at the far end in
## COLOR.b.
static func _band(m: Mesher, g: Ground, path: PackedVector2Array, offset: float, width: float, mat: int,
		lift: float) -> void:
	var along := 0.0
	var prev := -1
	for i in path.size():
		var dir := (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).normalized()
		var side := Vector2(-dir.y, dir.x)
		if i > 0:
			along += path[i].distance_to(path[i - 1])
		var fade := 1.0 - smoothstep(0.8, 1.0, float(i) / path.size())
		var col := Color(dir.x * 0.5 + 0.5, dir.y * 0.5 + 0.5, fade, 1.0)
		var j := m.v.size()
		for e: float in [0.0, 1.0]:
			var p := path[i] + side * (offset + (e - 0.5) * width)
			m.vert(Vector3(p.x, g.height(p.x, p.y) + lift, p.y), g.normal(p.x, p.y), col, mat, 0.0, Vector2(along, e))
		if prev >= 0:
			m.idx.append_array([prev, prev + 1, j + 1, prev, j + 1, j])
		prev = j


static func _tracks(m: Mesher, g: Ground) -> void:
	for path: PackedVector2Array in track_paths(g):
		for s: float in [-0.85, 0.85]:
			_band(m, g, path, s, 0.42, M_TRACK, 0.012)


## Footprints from the left airlock out to the instrument station and back by another way, and round the rover.
static func _prints(m: Mesher, g: Ground, rng: RandomNumberGenerator) -> void:
	var o := Vector2(g.c.x, g.c.z)
	var d := Vector2(-sin(deg_to_rad(AIRLOCK_THETA)), -cos(deg_to_rad(AIRLOCK_THETA)))
	var door := o + d * (g.r + TUBE_OUT + 0.6)
	var out := _spline([door, door + d * 2.0, Vector2(-31.5, -23.0), STATION_AT + Vector2(1.2, 0.6)])
	var back := _spline([STATION_AT + Vector2(-0.6, 1.4), Vector2(-36.0, -21.0), Vector2(-30.0, -17.0),
			door + Vector2(0.4, 1.6)])
	var round_rover := _spline([ROVER_AT + Vector2(-2.6, -2.0), ROVER_AT + Vector2(-3.5, 1.5),
			ROVER_AT + Vector2(-1.0, 3.6), ROVER_AT + Vector2(2.5, 3.0), ROVER_AT + Vector2(4.0, 0.5)])
	for path: PackedVector2Array in [out, back, round_rover]:
		_band(m, g, path, 0.0, 0.7, M_PRINTS, 0.008)


# --- The base, the lander, the rover, the station ------------------------------------------------------------------------

## A box (centre, size, turned by `basis`) as flat faces in one colour.
static func _box(m: Mesher, centre: Vector3, size: Vector3, basis: Basis, col: Color, mat: int, extra := 0.0) -> void:
	var h := size * 0.5
	var c: Array[Vector3] = []
	for k in 8:
		c.append(centre + basis * Vector3(h.x * (1 if k & 1 else -1), h.y * (1 if k & 2 else -1),
				h.z * (1 if k & 4 else -1)))
	for f: Array in [[0, 2, 3, 1], [4, 5, 7, 6], [0, 1, 5, 4], [2, 6, 7, 3], [0, 4, 6, 2], [1, 3, 7, 5]]:
		m.quad(c[f[0]], c[f[1]], c[f[2]], c[f[3]], col, mat, extra)


## A cylinder between a and b (radius, sides), smooth round its side, its ends flat.
static func _cyl(m: Mesher, a: Vector3, b: Vector3, radius: float, sides: int, col: Color, mat: int, caps := true,
		r_b := -1.0) -> void:
	var axis := (b - a).normalized()
	var u := axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
	var w := axis.cross(u)
	var rb := radius if r_b < 0.0 else r_b
	var j := m.v.size()
	for k in sides + 1:
		var t := TAU * k / sides
		var dir := u * cos(t) + w * sin(t)
		m.vert(a + dir * radius, dir, col, mat)
		m.vert(b + dir * rb, dir, col, mat)
	for k in sides:
		var i := j + k * 2
		m.idx.append_array([i, i + 2, i + 3, i, i + 3, i + 1])
	if caps:
		for e: Array in [[a, -axis, radius], [b, axis, rb]]:
			var mid := m.vert(e[0], e[1], col, mat)
			var first := m.v.size()
			for k in sides:
				var t := TAU * k / sides
				m.vert(e[0] + (u * cos(t) + w * sin(t)) * float(e[2]), e[1], col, mat)
			for k in sides:
				if e[1] == axis:
					m.idx.append_array([mid, first + k, first + (k + 1) % sides])
				else:
					m.idx.append_array([mid, first + (k + 1) % sides, first + k])


## Half a ball over a centre (a dome, radius, squashed by `rise`), smooth.
static func _half_ball(m: Mesher, centre: Vector3, radius: float, rise: float, basis: Basis, col: Color,
		mat: int) -> void:
	var rings := 5
	var sides := 14
	var j := m.v.size()
	for i in rings + 1:
		var lat := PI * 0.5 * i / rings
		for k in sides + 1:
			var t := TAU * k / sides
			var dir := Vector3(sin(t) * cos(lat), sin(lat), cos(t) * cos(lat))
			var p := Vector3(dir.x * radius, dir.y * radius * rise, dir.z * radius)
			m.vert(centre + basis * p, (basis * Vector3(dir.x, dir.y / maxf(rise, 0.1), dir.z)).normalized(), col, mat)
	for i in rings:
		for k in sides:
			var a := j + i * (sides + 1) + k
			var b := a + sides + 1
			m.idx.append_array([a, b, b + 1, a, b + 1, a + 1])


## The base ahead on the left: three habitat modules on a line and a node, half buried under bagged regolith, their
## ends and windows towards the dome; a lattice mast with a dish and its beacon; two solar arrays standing to the sun.
static func _base(m: Mesher, g: Ground, rng: RandomNumberGenerator, earth: Vector3, lights: Array) -> void:
	var white := Color(0.78, 0.78, 0.76)
	var grey := Color(0.42, 0.42, 0.42)
	var dark := Color(0.12, 0.12, 0.13)
	var mid := g.on(BASE_AT.x, BASE_AT.y)
	# The line of modules runs across the view; its face towards the dome.
	var to_dome := (Vector2(g.c.x, g.c.z) - BASE_AT).normalized()
	var across := Vector3(-to_dome.y, 0, to_dome.x)
	var toward := Vector3(to_dome.x, 0, to_dome.y)
	var floor_y := mid.y + 0.4
	var shadows: Array = []
	for k: int in [-1, 0, 1]:
		var centre := mid + across * (k * 10.5)
		centre.y = floor_y + 2.2
		var a := centre - across * 4.2
		var b := centre + across * 4.2
		if k == 0:
			# The node: a short drum standing up with a domed roof, a hatch to each side.
			_cyl(m, Vector3(centre.x, floor_y, centre.z), Vector3(centre.x, floor_y + 4.0, centre.z), 3.0, 18, white,
					M_PAINT)
			_half_ball(m, Vector3(centre.x, floor_y + 4.0, centre.z), 3.0, 0.45, Basis(), white, M_PAINT)
			_box(m, Vector3(centre.x, floor_y + 5.6, centre.z), Vector3(1.2, 0.6, 1.2), Basis(), grey, M_PAINT)
			for w in 4:
				var ang := deg_to_rad(-30.0 + w * 20.0)
				var dir := (toward * cos(ang) + across * sin(ang)).normalized()
				lights.append([Vector3(centre.x, floor_y + 2.6, centre.z) + dir * 3.05, Color(1.0, 0.72, 0.42), 0.32,
						1.0])
			continue
		_cyl(m, a, b, 2.2, 16, white, M_PAINT)
		# Ribs round the module every 1.4 m, the ends' collars.
		for s in 7:
			var q := a.lerp(b, (s + 0.5) / 7.0)
			_cyl(m, q - across * 0.06, q + across * 0.06, 2.27, 16, grey, M_PAINT, false)
		# Its far end: a domed cap; its near end (towards the node) meets the node.
		var far_end := a if k < 0 else b
		var out := -across if k < 0 else across
		_half_ball(m, far_end, 2.2, 0.35, _facing(out), white, M_PAINT)
		# Windows along the side towards the dome, warm.
		for wdx in 5:
			var q := a.lerp(b, (wdx + 0.5) / 5.0) + toward * 2.18 + Vector3.UP * 0.35
			lights.append([q, Color(1.0, 0.7, 0.4), 0.26, 1.0 if (wdx + k) % 3 != 0 else 0.55])
		# Bagged regolith up the module's back and over its top (a mound, darker where it is newer).
		var mound_a := a - toward * 1.6 - Vector3.UP * 0.3
		var mound_b := b - toward * 1.6 - Vector3.UP * 0.3
		_cyl(m, mound_a, mound_b, 2.6, 10, Color(0.85, 0.85, 0.85),
				M_REGOLITH, true)
		# Legs under it.
		for s in 3:
			var q := a.lerp(b, (s + 0.5) / 3.0)
			for e: float in [-1.0, 1.0]:
				var foot := q + toward * e * 1.4
				foot.y = g.height(foot.x, foot.z)
				_box(m, Vector3(foot.x, (foot.y + floor_y + 0.4) * 0.5, foot.z), Vector3(0.18, floor_y + 0.4 - foot.y,
						0.18), Basis(), dark, M_PAINT)
		shadows.append([a, b])
	# The mast: a lattice of three legs and braces, 16 m, a dish facing up towards Earth, the beacon on top.
	var mast := mid + across * 19.0 - toward * 3.0
	mast.y = g.height(mast.x, mast.z)
	var legs: Array[Vector3] = []
	for k in 3:
		var ang := TAU * k / 3.0
		legs.append(Vector3(cos(ang), 0, sin(ang)) * 0.55)
	var top := 16.0
	for k in 3:
		_cyl(m, mast + legs[k], mast + legs[k] * 0.35 + Vector3.UP * top, 0.05, 4, grey, M_PAINT, false)
	for s in 8:
		var y0 := top * s / 8.0
		var y1 := top * (s + 1) / 8.0
		for k in 3:
			var p0 := mast + legs[k].lerp(legs[k] * 0.35, y0 / top) + Vector3.UP * y0
			var p1 := mast + legs[(k + 1) % 3].lerp(legs[(k + 1) % 3] * 0.35, y1 / top) + Vector3.UP * y1
			_cyl(m, p0, p1, 0.025, 3, grey, M_PAINT, false)
	var dish_at := mast + Vector3.UP * (top - 2.0)
	var to_earth := earth.normalized()
	_half_ball(m, dish_at + to_earth * 0.9, 1.4, 0.32, _facing(-to_earth), Color(0.9, 0.9, 0.88), M_PAINT)
	_cyl(m, dish_at, dish_at + to_earth * 0.9, 0.12, 6, grey, M_PAINT)
	lights.append([mast + Vector3.UP * (top + 0.25), Color(1.0, 0.12, 0.06), 0.5, 1.0, 1.0])
	# The solar arrays: tall panels on masts facing the sun's way (behind the room), so the dome sees their backs'
	# frames and their tops catch the sun.
	for k: int in [-1, 1]:
		var foot := mid - across * (24.0 + k * 4.5) - toward * (5.0 + k * 2.0)
		foot.y = g.height(foot.x, foot.z)
		_cyl(m, foot, foot + Vector3.UP * 10.0, 0.14, 6, grey, M_PAINT)
		var face := _facing(Vector3(0.25, 0.0, 1.0).normalized())
		_box(m, foot + Vector3.UP * 6.8, Vector3(4.2, 7.0, 0.1), face, Color(1, 1, 1), M_SOLAR)
		_box(m, foot + Vector3.UP * 6.8 - face.z * 0.08, Vector3(4.35, 7.15, 0.04), face, grey, M_PAINT)


## A basis whose +Y points along `dir` (for half balls and caps).
static func _facing(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var x := y.cross(Vector3.UP if absf(y.y) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	return Basis(x, y, z)


## A cargo lander to the right: an octagonal descent stage in gold foil on four splayed legs with their pads, two
## white tanks and a box of cargo on its deck, an antenna.
static func _lander(m: Mesher, g: Ground, earth: Vector3) -> void:
	var at := g.on(LANDER_AT.x, LANDER_AT.y)
	var body_y := at.y + 1.9
	var gold := Color(1, 1, 1)
	var white := Color(0.8, 0.8, 0.78)
	var grey := Color(0.38, 0.38, 0.38)
	var r := 2.4
	var turn := 0.4
	var top: Array[Vector3] = []
	var bot: Array[Vector3] = []
	for k in 8:
		var a := turn + TAU * k / 8.0
		top.append(Vector3(at.x + cos(a) * r, body_y + 1.5, at.z + sin(a) * r))
		bot.append(Vector3(at.x + cos(a) * r, body_y, at.z + sin(a) * r))
	for k in 8:
		var j := (k + 1) % 8
		m.quad(bot[k], top[k], top[j], bot[j], gold, M_FOIL, float(k))
	var tc := Vector3(at.x, body_y + 1.5, at.z)
	var bc := Vector3(at.x, body_y, at.z)
	for k in 8:
		var j := (k + 1) % 8
		m.tri(tc, top[j], top[k], grey, M_PAINT)
		m.tri(bc, bot[k], bot[j], Color(0.3, 0.25, 0.15), M_FOIL, 9.0)
	# The engine bell under it.
	_cyl(m, bc, bc - Vector3.UP * 0.9, 0.35, 10, Color(0.25, 0.25, 0.26), M_PAINT, false, 0.7)
	for k in 4:
		var a := turn + TAU * (k + 0.5) / 4.0
		var out := Vector3(cos(a), 0, sin(a))
		var hip := Vector3(at.x, body_y + 0.8, at.z) + out * r * 0.95
		var pad := Vector3(at.x, 0, at.z) + out * (r + 1.9)
		pad.y = g.height(pad.x, pad.z) + 0.08
		_cyl(m, hip, pad + Vector3.UP * 0.1, 0.09, 6, grey, M_PAINT, false)
		_cyl(m, Vector3(at.x, body_y + 0.1, at.z) + out * r * 0.8, pad + Vector3.UP * 0.4 - out * 0.4, 0.05, 5,
				grey, M_PAINT, false)
		_cyl(m, pad, pad + Vector3.UP * 0.12, 0.45, 10, grey, M_PAINT, true, 0.38)
	for s: float in [-1.0, 1.0]:
		var c := tc + Vector3(s * 0.9, 0, 0.3)
		_cyl(m, c, c + Vector3.UP * 1.6, 0.6, 12, white, M_PAINT)
		_half_ball(m, c + Vector3.UP * 1.6, 0.6, 0.6, Basis(), white, M_PAINT)
	_box(m, tc + Vector3(0, 0.45, -1.2), Vector3(1.4, 0.9, 0.9), Basis(Vector3.UP, 0.2), Color(0.55, 0.55, 0.52),
			M_PAINT)
	_cyl(m, tc + Vector3(1.6, 0, -1.0), tc + Vector3(1.6, 2.4, -1.0), 0.03, 4, grey, M_PAINT, false)


## A pressurised rover parked by the right airlock: a long cabin on six wheels, its windscreen dark, a dish and a
## lamp mast on its roof, the cabin's light faint behind the glass.
static func _rover(m: Mesher, g: Ground, earth: Vector3, lights: Array) -> void:
	var at := g.on(ROVER_AT.x, ROVER_AT.y)
	var face := Basis(Vector3.UP, deg_to_rad(-28.0))
	var white := Color(0.8, 0.8, 0.78)
	var grey := Color(0.35, 0.35, 0.36)
	var dark := Color(0.08, 0.08, 0.09)
	var body := at + Vector3.UP * 1.55
	_box(m, body, Vector3(2.4, 1.7, 4.6), face, white, M_PAINT)
	_box(m, body + face * Vector3(0, 0.95, -0.3), Vector3(2.2, 0.2, 3.6), face, grey, M_PAINT)
	# The windscreen: a slanted face at the front (-Z of the rover), dark glass.
	var f0 := body + face * Vector3(-1.1, -0.1, -2.31)
	var f1 := body + face * Vector3(1.1, -0.1, -2.31)
	var f2 := body + face * Vector3(1.0, 0.75, -2.0)
	var f3 := body + face * Vector3(-1.0, 0.75, -2.0)
	m.quad(f0, f1, f2, f3, dark, M_GLASS)
	lights.append([body + face * Vector3(0, 0.3, -2.0), Color(0.6, 0.75, 1.0), 0.22, 0.35])
	for side: float in [-1.0, 1.0]:
		for k in 3:
			var hub := at + face * Vector3(side * 1.35, 0.55, -1.6 + k * 1.6)
			_cyl(m, hub - face.x * 0.22, hub + face.x * 0.22, 0.55, 12, dark, M_PAINT)
	var mast := body + face * Vector3(0.6, 0.85, 1.2)
	_cyl(m, mast, mast + Vector3.UP * 1.4, 0.04, 5, grey, M_PAINT, false)
	_half_ball(m, mast + Vector3.UP * 1.4 + earth * 0.15, 0.45, 0.3, _facing(-earth), white, M_PAINT)


## A small instrument station on the plain to the left, where the footprints go: a box on short legs, a mast with a
## little dish turned to Earth, a cable along the ground.
static func _station(m: Mesher, g: Ground, earth: Vector3) -> void:
	var at := g.on(STATION_AT.x, STATION_AT.y)
	var foil := Color(1, 1, 1)
	var grey := Color(0.4, 0.4, 0.4)
	_box(m, at + Vector3.UP * 0.45, Vector3(0.7, 0.4, 0.55), Basis(Vector3.UP, 0.5), foil, M_FOIL, 3.0)
	for k in 4:
		var a := 0.5 + PI * 0.25 + PI * 0.5 * k
		var leg := at + Vector3(cos(a), 0, sin(a)) * 0.38
		_cyl(m, leg, leg + Vector3.UP * 0.28, 0.02, 4, grey, M_PAINT, false)
	var mast := at + Vector3(0.6, 0, 0.3)
	_cyl(m, mast, mast + Vector3.UP * 1.2, 0.025, 4, grey, M_PAINT, false)
	_half_ball(m, mast + Vector3.UP * 1.2 + earth * 0.05, 0.3, 0.3, _facing(-earth), Color(0.9, 0.9, 0.88), M_PAINT)


## The airlocks' tubes outside the glass: a ribbed cylinder from the dome out, its end a hatch, its
## foot in the regolith banked against the drum. The airlocks themselves (the doors inside) are dome_hall's.
static func _airlock_tubes(m: Mesher, g: Ground, lights: Array) -> void:
	var white := Color(0.76, 0.76, 0.74)
	var grey := Color(0.36, 0.36, 0.37)
	for s: float in [-1.0, 1.0]:
		var d := Vector3(sin(deg_to_rad(AIRLOCK_THETA * s)), 0, -cos(deg_to_rad(AIRLOCK_THETA * s)))
		var a := g.c + d * (g.r + 0.04) + Vector3.UP * 1.45
		var b := g.c + d * (g.r + TUBE_OUT) + Vector3.UP * 1.45
		_cyl(m, a, b, 1.35, 18, white, M_PAINT)
		for k in 4:
			var q := a.lerp(b, (k + 1.0) / 4.5)
			_cyl(m, q - d * 0.08, q + d * 0.08, 1.42, 18, grey, M_PAINT, false)
		_cyl(m, b, b + d * 0.12, 0.85, 14, grey, M_PAINT)


## Amber marker lights along the track to the base, every 7 m, on short posts (their light: lights_mesh).
static func _markers(m: Mesher, g: Ground, lights: Array) -> void:
	var path: PackedVector2Array = track_paths(g)[0]
	var along := 0.0
	var next := 6.0
	for i in range(1, path.size()):
		along += path[i].distance_to(path[i - 1])
		if along >= next:
			var dir := (path[i] - path[i - 1]).normalized()
			var p := path[i] + Vector2(-dir.y, dir.x) * 2.0
			var foot := Vector3(p.x, g.height(p.x, p.y), p.y)
			_cyl(m, foot, foot + Vector3.UP * 0.4, 0.03, 4, Color(0.3, 0.3, 0.3), M_PAINT, false)
			lights.append([Vector3(p.x, g.height(p.x, p.y) + 0.45, p.y), Color(1.0, 0.6, 0.18), 0.09, 0.7])
			next += 7.0


## The lights as quads that face the eye (env_lunar_lights.gdshader): [place, colour, size (m), level, pulse].
## Returns [mesh, material].
static func _lights_mesh(lights: Array) -> Array:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for e: Array in lights:
		var p: Vector3 = e[0]
		var col: Color = e[1]
		col = Color(col.r * float(e[3]), col.g * float(e[3]), col.b * float(e[3]), float(e[2]))
		var pulse := float(e[4]) if e.size() > 4 else 0.0
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for k: int in [0, 1, 2, 0, 2, 3]:
			st.set_color(col)
			st.set_uv(uvs[k])
			st.set_uv2(Vector2(pulse, 0.0))
			st.set_normal(Vector3.UP)
			st.add_vertex(p)
	var mat := ShaderMaterial.new()
	mat.shader = LIGHTS_SHADER
	var mesh := st.commit()
	mesh.surface_set_material(0, mat)
	return [mesh, mat]


# --- The craterlets' map -------------------------------------------------------------------------------------------------

## The regolith's fine relief (tiling, 256 square): many small craters and grains. R, G: the slope (a normal's x and
## z, 0.5 flat); B: the ground's tone; A: a grain's glint (the sparkle). Made once.
static func detail_texture() -> ImageTexture:
	if _detail != null:
		return _detail
	var n := 256
	var h := PackedFloat32Array()
	h.resize(n * n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1966
	var fine := FastNoiseLite.new()
	fine.seed = 7
	fine.frequency = 0.05
	fine.fractal_octaves = 3
	for y in n:
		for x in n:
			h[y * n + x] = fine.get_noise_2d(float(x), float(y)) * 0.25
	for k in 200:
		var cx := rng.randf() * n
		var cy := rng.randf() * n
		var cr := 1.5 + pow(rng.randf(), 3.0) * 22.0
		var depth := cr * rng.randf_range(0.18, 0.26)
		var reach := int(cr * 2.2) + 1
		for dy in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				var q := Vector2(dx + 0.5 - fposmod(cx, 1.0), dy + 0.5 - fposmod(cy, 1.0)).length() / cr
				if q > 2.2:
					continue
				var v := Ground.crater(q) * depth / 0.2 * 0.2
				var i := posmod(int(cy) + dy, n) * n + posmod(int(cx) + dx, n)
				h[i] += v * 0.35
	var tone := FastNoiseLite.new()
	tone.seed = 11
	tone.frequency = 0.03
	var data := PackedByteArray()
	data.resize(n * n * 4)
	for y in n:
		for x in n:
			var i := y * n + x
			var gx := h[y * n + (x + 1) % n] - h[y * n + (x - 1 + n) % n]
			var gy := h[((y + 1) % n) * n + x] - h[((y - 1 + n) % n) * n + x]
			var nn := Vector3(-gx * 0.6, 1.0, -gy * 0.6).normalized()
			data[i * 4] = int(clampf(nn.x * 0.5 + 0.5, 0.0, 1.0) * 255.0)
			data[i * 4 + 1] = int(clampf(nn.z * 0.5 + 0.5, 0.0, 1.0) * 255.0)
			data[i * 4 + 2] = int(clampf(0.5 + tone.get_noise_2d(float(x), float(y)) * 0.5 - h[i] * 0.05, 0.0, 1.0)
					* 255.0)
			data[i * 4 + 3] = 255 if rng.randf() < 0.012 else int(rng.randf() * 90.0)
	var img := Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, data)
	img.generate_mipmaps()
	_detail = ImageTexture.create_from_image(img)
	return _detail
