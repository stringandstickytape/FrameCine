extends RefCounted

## The city round the Athens rooftop (terrace.gd's rooftop with `city` on; since 2026-11-08, the room's quality pass:
## "continue working on the environments one-by-one ... really improving their quality, imagination, delight, detail,
## lighting", the user, 2026-11-08). Everything outside the terrace, in one mesh and one draw (shaders/env_city.gdshader,
## unshaded, never baked):
##   Blocks     a grid of streets 7.4 m wide; each block filled with buildings side by side, four to eight storeys of
##              whitewash, cream, ochre and pale pink: the apartment blocks' balconies one above another, older houses
##              with shuttered windows, a few neoclassical fronts. The windows are drawn by the shader from each wall's
##              own coordinates: lit rooms, dark ones, shutters closed with light through the louvres
##   Roofs      flat, inside a low parapet: stair heads, solar water heaters (a tilted panel, a tank), black tanks, TV
##              aerials on the nearer ones, a pergola or a washing line now and then
##   Near       the buildings round the terrace by hand: the screen building (its roof, tank and aerial over the wall),
##              the neighbours' roofs just under the parapet with their clutter, a roof garden with a pergola and a
##              string of small lights to the right, a taller block to the front left whose balconies face the seats
##   Streets    asphalt and pavements on the ground, which rises gently away from the roof (a city in its basin), the
##              lamps' pools along them and the lamps on the walls
##   Church     a big Byzantine church in its square to the left, its dome on a drum, two bell towers, softly floodlit
##   Citadel    an invented temple on a hill to the right of the screen wall: cliffs and walls round a plateau, a ruined
##              temple of columns, a smaller one, a gateway, all honey-gold in the floodlights (`floodlight`), trees and
##              small white houses on the slopes under it. Stylised, no replica
##   Chapel     a steep pine-dark hill behind on the left with a white chapel floodlit on its top and a path of lamps
##   Hills      the hills round the basin on the horizon, the city's lights climbing them
## Nothing here is anyone's mark; no people. Static; preload to use.

const SHADER := preload("res://shaders/env_city.gdshader")
const SkySystem := preload("res://scripts/env/systems/sky.gd")

const M_WALL := 0
const M_ROOF := 1
const M_METAL := 2
const M_PANEL := 3
const M_ROCK := 4
const M_FLOOD := 5
const M_FOLIAGE := 6
const M_LAMP := 7
const M_STREET := 8
const M_CLOTH := 9
const M_TILE := 10
const M_DARK := 11
const M_CHURCH := 12
const M_GLASS := 13
const M_WATER := 14

## The street grid: the x of the streets that run along z, the z of those that run along x; the width with pavements.
const STREET_W := 7.4
const XS: Array[float] = [-149.0, -107.0, -65.0, -23.0, 23.0, 65.0, 107.0, 149.0]
const ZS: Array[float] = [-159.5, -117.5, -75.5, -33.5, 12.0, 54.0, 96.0, 138.0]
## How far the city reaches (the camera sees 200 m; the sky is drawn from 175 m).
const REACH := 150.0
## The street under the roof: the roof's terrace is at 0, the street 12 m below.
const STREET_Y := -12.0
## The citadel: its bearing from the room's front (degrees, + right), its distance, its plateau's height.
const CITADEL_AZ := 52.0
const CITADEL_D := 150.0
const CITADEL_TOP := 13.0
## The chapel's hill behind on the left.
const CHAPEL_AZ := -128.0
const CHAPEL_D := 140.0
const CHAPEL_TOP := 40.0
## The church's square on the left.
const CHURCH := Vector3(-38.0, 0.0, -20.0)
## Linear colours.
const WASHES: Array[Color] = [Color(0.78, 0.76, 0.71), Color(0.8, 0.77, 0.7), Color(0.74, 0.66, 0.5),
		Color(0.72, 0.56, 0.34), Color(0.74, 0.58, 0.5), Color(0.6, 0.58, 0.55), Color(0.78, 0.7, 0.46),
		Color(0.82, 0.8, 0.76), Color(0.66, 0.62, 0.56)]
const STONE := Color(0.86, 0.72, 0.52)
const ROCK := Color(0.42, 0.36, 0.3)
const PINE := Color(0.05, 0.08, 0.05)
const OLIVE := Color(0.1, 0.12, 0.08)
const ASPHALT := Color(0.09, 0.09, 0.1)
const PAVING := Color(0.36, 0.34, 0.31)
const SODIUM := Color(1.0, 0.58, 0.24)
const LED := Color(0.95, 0.9, 0.8)
const AWNINGS: Array[Color] = [Color(0.62, 0.55, 0.38), Color(0.2, 0.36, 0.22), Color(0.66, 0.36, 0.14),
		Color(0.55, 0.52, 0.48), Color(0.25, 0.34, 0.5), Color(0.6, 0.2, 0.14)]


## The mesh being built: one surface, the city shader's vertex layout.
class Builder:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var cu := PackedFloat32Array()
	var idx := PackedInt32Array()
	## The colour (linear) and occlusion (alpha) of what follows, its material, the material's number, the wall data.
	var colour := Color(1, 1, 1, 1)
	var mat := 0
	var extra := 1.0
	var custom := Color(0, 0, 0, 0)
	## A blob's UV.y (the floodlight's share on leaves near the citadel).
	var uv_flood := 0.0

	func vert(p: Vector3, nn: Vector3, t: Vector2) -> int:
		v.append(p)
		n.append(nn)
		c.append(colour)
		uv.append(t)
		uv2.append(Vector2(mat, extra))
		cu.append(custom.r)
		cu.append(custom.g)
		cu.append(custom.b)
		cu.append(custom.a)
		return v.size() - 1

	## A quad, its corners in order round it, facing nn (drawn on that side).
	func quad(a: Vector3, b: Vector3, d: Vector3, e: Vector3, nn: Vector3, ta := Vector2(0, 0), tb := Vector2(1, 0),
			td := Vector2(1, 1), te := Vector2(0, 1)) -> void:
		var k := vert(a, nn, ta)
		vert(b, nn, tb)
		vert(d, nn, td)
		vert(e, nn, te)
		if (d - a).cross(b - a).dot(nn) >= 0.0:
			idx.append_array([k, k + 1, k + 2, k, k + 2, k + 3])
		else:
			idx.append_array([k, k + 2, k + 1, k, k + 3, k + 2])

	## Both sides of a quad (leaves, cloth, an aerial's elements).
	func quad2(a: Vector3, b: Vector3, d: Vector3, e: Vector3, nn: Vector3) -> void:
		quad(a, b, d, e, nn)
		quad(a, b, d, e, -nn)

	func tri(a: Vector3, b: Vector3, d: Vector3, nn: Vector3, ta := Vector2.ZERO, tb := Vector2.ZERO,
			td := Vector2.ZERO) -> void:
		var k := vert(a, nn, ta)
		vert(b, nn, tb)
		vert(d, nn, td)
		if (d - a).cross(b - a).dot(nn) >= 0.0:
			idx.append_array([k, k + 1, k + 2])
		else:
			idx.append_array([k, k + 2, k + 1])

	## A vertical wall over the line from a to b (x and z; y ignored), from y0 up to y1, facing out (the side to the
	## left going from a to b, seen from above, is inside). UV: metres along from a (plus u0) and up from `foot`.
	func wall(a: Vector3, b: Vector3, y0: float, y1: float, foot: float, u0 := 0.0) -> void:
		var along := Vector3(b.x - a.x, 0, b.z - a.z)
		var length := along.length()
		if length < 0.01 or y1 - y0 < 0.01:
			return
		var out := Vector3(along.z, 0, -along.x).normalized()
		quad(Vector3(a.x, y0, a.z), Vector3(b.x, y0, b.z), Vector3(b.x, y1, b.z), Vector3(a.x, y1, a.z), out,
				Vector2(u0, y0 - foot), Vector2(u0 + length, y0 - foot), Vector2(u0 + length, y1 - foot),
				Vector2(u0, y1 - foot))

	## A box's faces (all but those in skip: "t" top, "b" bottom, "n" -z, "s" +z, "w" -x, "e" +x), in its basis.
	## UV in metres per face, up from `foot`.
	func box(centre: Vector3, size: Vector3, basis := Basis(), skip := "", foot := -INF) -> void:
		var h := size * 0.5
		var x := basis.x * h.x
		var y := basis.y * h.y
		var z := basis.z * h.z
		var f := centre.y - h.y if foot == -INF else foot
		var lo := centre.y - h.y - f
		var hi := centre.y + h.y - f
		if not ("n" in skip):
			quad(centre - x - y - z, centre + x - y - z, centre + x + y - z, centre - x + y - z, -basis.z,
					Vector2(0, lo), Vector2(size.x, lo), Vector2(size.x, hi), Vector2(0, hi))
		if not ("s" in skip):
			quad(centre + x - y + z, centre - x - y + z, centre - x + y + z, centre + x + y + z, basis.z,
					Vector2(0, lo), Vector2(size.x, lo), Vector2(size.x, hi), Vector2(0, hi))
		if not ("w" in skip):
			quad(centre - x - y + z, centre - x - y - z, centre - x + y - z, centre - x + y + z, -basis.x,
					Vector2(0, lo), Vector2(size.z, lo), Vector2(size.z, hi), Vector2(0, hi))
		if not ("e" in skip):
			quad(centre + x - y - z, centre + x - y + z, centre + x + y + z, centre + x + y - z, basis.x,
					Vector2(0, lo), Vector2(size.z, lo), Vector2(size.z, hi), Vector2(0, hi))
		if not ("t" in skip):
			quad(centre - x + y - z, centre + x + y - z, centre + x + y + z, centre - x + y + z, basis.y,
					Vector2(0, 0), Vector2(size.x, 0), Vector2(size.x, size.z), Vector2(0, size.z))
		if not ("b" in skip):
			quad(centre - x - y - z, centre + x - y - z, centre + x - y + z, centre - x - y + z, -basis.y)

	## A beam (a box along a line), `w` across and `t` thick.
	func beam(a: Vector3, b: Vector3, w: float, t: float, skip := "") -> void:
		var dir := (b - a).normalized()
		var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
		var across := up.cross(dir).normalized()
		var up2 := dir.cross(across).normalized()
		box((a + b) * 0.5, Vector3(w, t, a.distance_to(b)), Basis(across, up2, dir), skip)

	## A cylinder round `axis` from base, r, length; sides; caps: "a" at the far end, "b" at the base.
	func cyl(base: Vector3, axis: Vector3, r: float, length: float, sides := 6, caps := "a") -> void:
		var ax := axis.normalized()
		var u := (Vector3.UP if absf(ax.y) < 0.9 else Vector3.RIGHT).cross(ax).normalized()
		var w := ax.cross(u).normalized()
		var top := base + ax * length
		for s in sides:
			var a0 := TAU * s / sides
			var a1 := TAU * (s + 1) / sides
			var d0 := u * cos(a0) + w * sin(a0)
			var d1 := u * cos(a1) + w * sin(a1)
			var nn := (d0 + d1).normalized()
			quad(base + d0 * r, base + d1 * r, top + d1 * r, top + d0 * r, nn, Vector2(r * a0, 0),
					Vector2(r * a1, 0), Vector2(r * a1, length), Vector2(r * a0, length))
			if "a" in caps:
				tri(top, top + d0 * r, top + d1 * r, ax)
			if "b" in caps:
				tri(base, base + d1 * r, base + d0 * r, -ax)

	## A lamp seen from anywhere: two crossed quads of its colour (M_LAMP).
	func lamp(at: Vector3, size: float, col: Color) -> void:
		var keep_m := mat
		var keep_c := colour
		mat = M_LAMP
		colour = Color(col.r, col.g, col.b, 1.0)
		var h := size * 0.5
		quad2(at + Vector3(-h, -h, 0), at + Vector3(h, -h, 0), at + Vector3(h, h, 0), at + Vector3(-h, h, 0),
				Vector3.BACK)
		quad2(at + Vector3(0, -h, -h), at + Vector3(0, -h, h), at + Vector3(0, h, h), at + Vector3(0, h, -h),
				Vector3.RIGHT)
		mat = keep_m
		colour = keep_c

	## A lump of leaves (a tree's crown, a shrub): a squashed octahedron-ish blob of eight faces, jittered.
	func blob(centre: Vector3, r: Vector3, rng: RandomNumberGenerator, sides := 6) -> void:
		var top := centre + Vector3(0, r.y, 0)
		var bottom := centre - Vector3(0, r.y * 0.7, 0)
		var ring: Array[Vector3] = []
		var spin := rng.randf() * TAU
		for s in sides:
			var a := spin + TAU * s / sides
			ring.append(centre + Vector3(cos(a) * r.x, rng.randf_range(-0.15, 0.15) * r.y, sin(a) * r.z)
					* rng.randf_range(0.85, 1.12))
		for s in sides:
			var p0: Vector3 = ring[s]
			var p1: Vector3 = ring[(s + 1) % sides]
			var mid := (p0 + p1) * 0.5 - centre
			var nu := (mid.normalized() + Vector3.UP * 0.6).normalized()
			var nd := (mid.normalized() - Vector3.UP * 0.4).normalized()
			var t := Vector2(0, uv_flood)
			tri(top, p1, p0, nu, t, t, t)
			tri(bottom, p0, p1, nd, t, t, t)

	func commit(material: Material) -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_COLOR] = c
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
		arrays[Mesh.ARRAY_CUSTOM0] = cu
		arrays[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
				Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		mesh.surface_set_material(0, material)
		return mesh


# --- The lie of the land -------------------------------------------------------------------------------------------

static func dir_of(az_deg: float) -> Vector3:
	var a := deg_to_rad(az_deg)
	return Vector3(sin(a), 0.0, -cos(a))


static func az_of(x: float, z: float) -> float:
	return rad_to_deg(atan2(x, -z))


static func citadel_centre() -> Vector3:
	return dir_of(CITADEL_AZ) * CITADEL_D


static func chapel_centre() -> Vector3:
	return dir_of(CHAPEL_AZ) * CHAPEL_D


## The ground's height: the street under the roof, rising gently away from it as the basin does, less towards the
## citadel (its foot stays low, so the hill stands clear), up the chapel's hill behind.
static func ground(x: float, z: float) -> float:
	var d := Vector2(x, z).length()
	var az := az_of(x, z)
	var rise := 0.055 * maxf(d - 28.0, 0.0)
	var towards := 1.0 - smoothstep(14.0, 34.0, absf(az - CITADEL_AZ))
	rise *= 1.0 - 0.9 * towards
	var ch := chapel_centre()
	var r := Vector2(x - ch.x, z - ch.z).length()
	rise += 10.0 * exp(-pow(r / 55.0, 2.0))
	return STREET_Y + rise


## Value noise in 0..1 (smooth), for profiles.
static func _n1(x: float, seed_value: int) -> float:
	var i := floori(x)
	var f := x - i
	f = f * f * (3.0 - 2.0 * f)
	return lerpf(_h(i, seed_value), _h(i + 1, seed_value), f)


static func _h(i: int, seed_value: int) -> float:
	var q := (i * 374761393 + seed_value * 668265263) & 0x7fffffff
	q = ((q ^ (q >> 13)) * 1274126177) & 0x7fffffff
	return float(q & 0xffff) / 65535.0


# --- The city ---------------------------------------------------------------------------------------------------------

## The city's mesh and its material (the terrace keeps the material for its live parameters).
static func build(seed_value: int) -> Array:
	var b := Builder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_streets(b)
	_blocks(b, rng)
	_near(b, rng)
	_church(b, rng)
	_citadel(b, rng)
	_chapel_hill(b, rng)
	_far_hills(b, rng)
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("noise_tex", SkySystem.noise_texture())
	return [b.commit(m), m]


## The street rectangles (x0, z0, x1, z1) of the grid, clipped to the city's reach, and the blocks between them.
static func _cuts(values: Array[float]) -> Array:
	var out: Array = []
	var edges: Array[float] = [-REACH - 20.0]
	for s in values:
		edges.append(s - STREET_W * 0.5)
		edges.append(s + STREET_W * 0.5)
	edges.append(REACH + 20.0)
	for i in range(0, edges.size(), 2):
		out.append([edges[i], edges[i + 1]])
	return out


static func _streets(b: Builder) -> void:
	# Along z (constant x) and along x (constant z): asphalt between pavements, following the ground; a lamp every 26 m
	# on alternate sides (the pools in the shader at the same places).
	for axis in 2:
		var lines: Array[float] = XS if axis == 0 else ZS
		var cross: Array[float] = ZS if axis == 0 else XS
		for s in lines:
			# Breaks every 6 m and at the crossings' edges: a crossing is drawn once (by the street along z), so two
			# streets never lie on one another.
			var breaks: Array[float] = []
			var t := -REACH
			while t < REACH:
				breaks.append(t)
				t += 6.0
			breaks.append(REACH)
			for cs in cross:
				breaks.append(cs - STREET_W * 0.5)
				breaks.append(cs + STREET_W * 0.5)
			breaks.sort()
			for bi in breaks.size() - 1:
				var ta := breaks[bi]
				var tb := breaks[bi + 1]
				if tb - ta < 0.01 or ta < -REACH or tb > REACH:
					continue
				var in_cross := false
				for cs in cross:
					if absf((ta + tb) * 0.5 - cs) < STREET_W * 0.5:
						in_cross = true
				if in_cross and axis == 1:
					continue
				var pa := Vector3(s, 0, ta) if axis == 0 else Vector3(ta, 0, s)
				var pb := Vector3(s, 0, tb) if axis == 0 else Vector3(tb, 0, s)
				if Vector2(pa.x, pa.z).length() > REACH + 4.0 and Vector2(pb.x, pb.z).length() > REACH + 4.0:
					continue
				if _in_hill(pa) and _in_hill(pb):
					continue
				var side := Vector3(1, 0, 0) if axis == 0 else Vector3(0, 0, 1)
				var ya := ground(pa.x, pa.z)
				var yb := ground(pb.x, pb.z)
				for lane: Array in [[-STREET_W * 0.5, -2.5, PAVING, 0.15], [-2.5, 2.5, ASPHALT, 0.0],
						[2.5, STREET_W * 0.5, PAVING, 0.15]]:
					if in_cross and float(lane[3]) > 0.0:
						continue
					b.mat = M_STREET
					b.colour = lane[2]
					b.custom = Color(26.0, 0.0 if axis == 0 else 0.37, 0, 0)
					var o0: Vector3 = side * float(lane[0])
					var o1: Vector3 = side * float(lane[1])
					var lift := float(lane[3])
					b.quad(pa + o0 + Vector3(0, ya + lift, 0), pa + o1 + Vector3(0, ya + lift, 0),
							pb + o1 + Vector3(0, yb + lift, 0), pb + o0 + Vector3(0, yb + lift, 0), Vector3.UP,
							Vector2(ta, 0), Vector2(ta, 1), Vector2(tb, 1), Vector2(tb, 0))
				# Lamps on the walls by the street.
				var offset := 0.0 if axis == 0 else 0.37 * 26.0
				var first := ceili((ta + offset - 13.0) / 26.0)
				var k := first
				while k * 26.0 - offset + 13.0 < tb:
					var u := k * 26.0 - offset + 13.0
					if u >= ta:
						var p := Vector3(s, 0, u) if axis == 0 else Vector3(u, 0, s)
						var sgn := 1.0 if posmod(k, 2) == 0 else -1.0
						var at := p + side * sgn * (STREET_W * 0.5 - 0.35)
						at.y = ground(at.x, at.z) + 5.2
						if Vector2(at.x, at.z).length() < REACH and not _in_hill(at) and not _in_terrace(at):
							b.lamp(at, maxf(0.32, Vector2(at.x, at.z).length() * 0.0028),
									(SODIUM * 2.4) if posmod(k, 3) != 0 else (LED * 1.8))
					k += 1


## Inside a hill's footprint (the citadel's, the chapel's): no street or building there.
static func _in_hill(p: Vector3) -> bool:
	var c := citadel_centre()
	var q := Vector2(p.x - c.x, p.z - c.z)
	var along := Vector2(cos(deg_to_rad(CITADEL_AZ)), sin(deg_to_rad(CITADEL_AZ)))
	var e := Vector2(q.dot(along) / 62.0, q.dot(Vector2(-along.y, along.x)) / 40.0)
	if e.length() < 1.0:
		return true
	var ch := chapel_centre()
	return Vector2(p.x - ch.x, p.z - ch.z).length() < 34.0


## The roof's own block and the street right under it (the near buildings are made by hand).
static func _in_terrace(p: Vector3) -> bool:
	return p.x > -19.3 and p.x < 19.3 and p.z > -29.8 and p.z < 8.3


## Every block of the grid filled with buildings (not the roof's own block, not the hills, not the church's square).
static func _blocks(b: Builder, rng: RandomNumberGenerator) -> void:
	var xs := _cuts(XS)
	var zs := _cuts(ZS)
	for xb: Array in xs:
		for zb: Array in zs:
			var x0 := float(xb[0])
			var x1 := float(xb[1])
			var z0 := float(zb[0])
			var z1 := float(zb[1])
			var centre := Vector3((x0 + x1) * 0.5, 0, (z0 + z1) * 0.5)
			if _in_terrace(centre):
				continue
			# Lots: across the block in widths of 8 to 15 m, two rows deep (front and back) when deep enough.
			var rows := 2 if z1 - z0 > 24.0 else 1
			var depth := (z1 - z0) / rows
			for r in rows:
				var za := z0 + r * depth
				var zb2 := za + depth
				var x := x0
				while x < x1 - 0.5:
					var w := rng.randf_range(8.0, 15.0)
					if x1 - (x + w) < 6.0:
						w = x1 - x
					var lot := Rect2(x, za, w, zb2 - za)
					x += w
					var mid := Vector3(lot.get_center().x, 0, lot.get_center().y)
					var d := Vector2(mid.x, mid.z).length()
					if d > REACH or _in_hill(mid) or _church_square(lot):
						continue
					# Faces on the block's edge look onto a street; the others are party walls.
					var open := [absf(lot.position.y - z0) < 0.1, absf(lot.end.x - x1) < 0.1,
							absf(lot.end.y - z1) < 0.1, absf(lot.position.x - x0) < 0.1]
					_lot(b, rng, lot, open, d)


static func _church_square(lot: Rect2) -> bool:
	return lot.intersects(Rect2(CHURCH.x - 17.0, CHURCH.z - 14.0, 30.0, 26.0))


## A building on its lot: how tall by where it stands (lower towards the citadel; taller further out where the ground
## rises), its wash, its style; its roof's clutter.
static func _lot(b: Builder, rng: RandomNumberGenerator, lot: Rect2, open: Array, d: float) -> void:
	var mid := lot.get_center()
	var az := az_of(mid.x, mid.y)
	# Low towards the citadel, so its cliffs and the houses on its slope show over the roofs from the seats.
	var towards := 1.0 - smoothstep(16.0, 32.0, absf(az - CITADEL_AZ))
	var floors := rng.randi_range(4, 7)
	if rng.randf() < 0.15:
		floors = rng.randi_range(2, 3)
	if towards > 0.0:
		floors = mini(floors, int(lerpf(7.0, 3.0, towards)))
	var style := 1
	var r := rng.randf()
	if r < 0.22:
		style = 0
	elif r < 0.32:
		style = 2
		floors = mini(floors, 3)
	if d < 60.0 and style == 1:
		style = 4
	var foot := minf(minf(ground(lot.position.x, lot.position.y), ground(lot.end.x, lot.position.y)),
			minf(ground(lot.position.x, lot.end.y), ground(lot.end.x, lot.end.y)))
	var top := foot + 3.6 + (floors - 1) * 3.1 + 1.1
	var inset := 0.0
	building(b, rng, Rect2(lot.position + Vector2(inset, inset), lot.size - Vector2(inset, inset) * 2.0), foot, top,
			WASHES[rng.randi() % WASHES.size()], style, open, d)


## One building: walls (windows where they face a street), its roof inside a parapet, its roof's things.
## near: within 60 m (aerials, balconies in relief, awnings); further, plainer.
static func building(b: Builder, rng: RandomNumberGenerator, rect: Rect2, foot: float, top: float, wash: Color,
		style: int, open: Array, d: float, clutter := true, roof := true, quiet := false) -> void:
	var seed_value := rng.randf()
	var bay0 := rng.randf_range(2.7, 3.5) if style != 2 else rng.randf_range(2.4, 2.8)
	var corners := [Vector3(rect.position.x, 0, rect.position.y), Vector3(rect.end.x, 0, rect.position.y),
			Vector3(rect.end.x, 0, rect.end.y), Vector3(rect.position.x, 0, rect.end.y)]
	var parapet := 1.0 if d < 95.0 else 0.0
	b.colour = Color(wash.r, wash.g, wash.b, 1.0)
	b.mat = M_WALL
	for k in 4:
		# Corners in order -z, +x, +z, -x faces: a -> b with the outside on the right.
		var a: Vector3 = corners[k]
		var e: Vector3 = corners[(k + 1) % 4]
		var length := Vector2(e.x - a.x, e.z - a.z).length()
		# A wall onto a street: its windows; a party wall (showing over a lower neighbour): blind but for a few small
		# windows (the shader's negative bay).
		var bay := length / maxf(roundf(length / bay0), 1.0)
		if not bool(open[k]):
			bay = -bay
		# quiet: most of its windows dark (style + 10; the near ones facing the screen).
		b.custom = Color(bay, top - foot - parapet - 0.4, seed_value + k * 0.13,
				float(style) + (10.0 if quiet else 0.0))
		# The wall: its foot under the ground (a slope never leaves it standing on air).
		b.wall(a, e, foot - 3.0, top, foot)
	var roof_y := top - parapet
	b.custom = Color(0, 0, 0, 0)
	if not roof:
		if style == 4:
			_balconies(b, rng, rect, foot, top, wash, open, seed_value)
		return
	b.mat = M_ROOF
	var roof_c := Color(0.5, 0.48, 0.45) if rng.randf() < 0.6 else Color(0.72, 0.72, 0.7)
	b.colour = Color(roof_c.r, roof_c.g, roof_c.b, 1.0)
	b.quad(Vector3(rect.position.x, roof_y, rect.position.y), Vector3(rect.end.x, roof_y, rect.position.y),
			Vector3(rect.end.x, roof_y, rect.end.y), Vector3(rect.position.x, roof_y, rect.end.y), Vector3.UP)
	if parapet > 0.0:
		# The parapet's inside faces and its top.
		b.mat = M_WALL
		b.colour = Color(wash.r, wash.g, wash.b, 0.85)
		var t := 0.2
		var inner := [Vector3(rect.position.x + t, 0, rect.position.y + t), Vector3(rect.end.x - t, 0, rect.position.y + t),
				Vector3(rect.end.x - t, 0, rect.end.y - t), Vector3(rect.position.x + t, 0, rect.end.y - t)]
		for k in 4:
			var a: Vector3 = inner[k]
			var e: Vector3 = inner[(k + 1) % 4]
			b.wall(e, a, roof_y, top, roof_y)
			var oa: Vector3 = corners[k]
			var oe: Vector3 = corners[(k + 1) % 4]
			b.quad(Vector3(oa.x, top, oa.z), Vector3(oe.x, top, oe.z), Vector3(e.x, top, e.z), Vector3(a.x, top, a.z),
					Vector3.UP)
	if style == 4:
		_balconies(b, rng, rect, foot, top - parapet, wash, open, seed_value)
	if clutter:
		_roof_things(b, rng, rect, roof_y, d)


## Balconies in relief on the walls that face a street (the apartment blocks near the roof): a slab on each floor
## along most of the wall, its solid front or its railing, an awning down over some, an air conditioner, plants.
static func _balconies(b: Builder, rng: RandomNumberGenerator, rect: Rect2, foot: float, roof: float, wash: Color,
		open: Array, _seed: float) -> void:
	var corners := [Vector3(rect.position.x, 0, rect.position.y), Vector3(rect.end.x, 0, rect.position.y),
			Vector3(rect.end.x, 0, rect.end.y), Vector3(rect.position.x, 0, rect.end.y)]
	var floors := int((roof - foot - 3.6) / 3.1) + 1
	var solid := rng.randf() < 0.5
	var awning_c: Color = AWNINGS[rng.randi() % AWNINGS.size()]
	for k in 4:
		if not bool(open[k]):
			continue
		var a: Vector3 = corners[k]
		var e: Vector3 = corners[(k + 1) % 4]
		var along := Vector3(e.x - a.x, 0, e.z - a.z)
		var length := along.length()
		var u := along / length
		var out := Vector3(u.z, 0, -u.x)
		var from := 0.6
		var to := length - 0.6
		for f in range(1, floors):
			var y := foot + 3.6 + (f - 1) * 3.1
			if y > roof - 2.0:
				break
			var depth := 1.15
			var p0 := a + u * from + Vector3(0, y, 0)
			var p1 := a + u * to + Vector3(0, y, 0)
			# The slab.
			b.mat = M_WALL
			b.custom = Color(0, 9.0, 0, 0)
			b.colour = Color(wash.r, wash.g, wash.b, 1.0) * 1.05
			b.colour.a = 1.0
			var c := (p0 + p1) * 0.5 + out * depth * 0.5
			b.box(c - Vector3(0, 0.08, 0), Vector3(to - from, 0.16, depth), Basis(u, Vector3.UP, out), "", foot)
			# Its front: solid and plastered, or a dark railing.
			if solid:
				b.colour = Color(wash.r, wash.g, wash.b, 0.95)
				b.box(c + out * (depth * 0.5 - 0.06) + Vector3(0, 0.45, 0), Vector3(to - from, 0.9, 0.12),
						Basis(u, Vector3.UP, out), "b", foot)
			else:
				b.mat = M_METAL
				b.colour = Color(0.08, 0.08, 0.08, 1.0)
				var rail := c + out * (depth * 0.5 - 0.03)
				b.box(rail + Vector3(0, 0.95, 0), Vector3(to - from, 0.05, 0.06), Basis(u, Vector3.UP, out), "b")
				b.box(rail + Vector3(0, 0.2, 0), Vector3(to - from, 0.03, 0.04), Basis(u, Vector3.UP, out), "b")
				var posts := int((to - from) / 1.4)
				for j in posts + 1:
					var px := a + u * lerpf(from, to, float(j) / maxf(posts, 1)) + out * (depth - 0.03) + Vector3(0, y, 0)
					b.box(px + Vector3(0, 0.48, 0), Vector3(0.04, 0.95, 0.04), Basis(u, Vector3.UP, out), "tb")
			# An awning down from the slab over it (the next floor's), on some floors; an air conditioner; plants.
			if rng.randf() < 0.45 and f + 1 < floors:
				b.mat = M_CLOTH
				var ac := awning_c * rng.randf_range(0.85, 1.1)
				b.colour = Color(ac.r, ac.g, ac.b, 1.0)
				var top_y := y + 3.1 - 0.2
				var x0 := rng.randf_range(from, from + (to - from) * 0.3)
				var x1 := rng.randf_range(from + (to - from) * 0.6, to)
				var t0 := a + u * x0
				var t1 := a + u * x1
				var drop := rng.randf_range(1.2, 2.0)
				b.quad2(t0 + Vector3(0, top_y, 0) + out * 0.05, t1 + Vector3(0, top_y, 0) + out * 0.05,
						t1 + Vector3(0, top_y - drop, 0) + out * (depth - 0.05),
						t0 + Vector3(0, top_y - drop, 0) + out * (depth - 0.05), (out + Vector3.UP).normalized())
				b.custom = Color(0, 0, 0, 0)
			if rng.randf() < 0.35:
				b.mat = M_METAL
				b.colour = Color(0.62, 0.62, 0.6, 1.0)
				var ap := a + u * rng.randf_range(from + 0.5, to - 0.5) + out * 0.35 + Vector3(0, y + 0.3, 0)
				b.box(ap, Vector3(0.8, 0.55, 0.3), Basis(u, Vector3.UP, out))
			if rng.randf() < 0.5:
				b.mat = M_FOLIAGE
				b.extra = 1.0
				var g := OLIVE * rng.randf_range(1.0, 2.2)
				b.colour = Color(g.r, g.g, g.b, 1.0)
				for j in rng.randi_range(1, 3):
					var pp := a + u * rng.randf_range(from + 0.3, to - 0.3) + out * (depth - 0.35) + Vector3(0, y + 0.5, 0)
					b.blob(pp, Vector3(0.35, 0.45, 0.35) * rng.randf_range(0.7, 1.3), rng)
			b.custom = Color(0, 0, 0, 0)


## A roof's things: a stair head (its door, now and then lit), solar heaters facing south, black tanks, TV aerials
## on the nearer roofs, now and then a pergola or a washing line.
static func _roof_things(b: Builder, rng: RandomNumberGenerator, rect: Rect2, y: float, d: float) -> void:
	b.custom = Color(0, 0, 0, 0)
	var inner := rect.grow(-0.6)
	if inner.size.x < 3.0 or inner.size.y < 3.0:
		return
	var pick := func(size: Vector2) -> Vector3:
		var px := rng.randf_range(inner.position.x + size.x * 0.5, maxf(inner.end.x - size.x * 0.5,
				inner.position.x + size.x * 0.5))
		var pz := rng.randf_range(inner.position.y + size.y * 0.5, maxf(inner.end.y - size.y * 0.5,
				inner.position.y + size.y * 0.5))
		return Vector3(px, y, pz)
	if rng.randf() < 0.8:
		var p: Vector3 = pick.call(Vector2(2.8, 3.0))
		b.mat = M_WALL
		var wc := WASHES[rng.randi() % WASHES.size()]
		b.colour = Color(wc.r, wc.g, wc.b, 1.0)
		b.custom = Color(0, 0, 0, 0)
		b.box(p + Vector3(0, 1.25, 0), Vector3(2.6, 2.5, 2.8), Basis(), "b", y)
		b.mat = M_ROOF
		b.colour = Color(0.5, 0.48, 0.45, 1.0)
		b.box(p + Vector3(0, 2.55, 0), Vector3(2.9, 0.1, 3.1), Basis(), "")
		# Its door, facing the room's side or not; lit through its glass now and then.
		var face := rng.randi() % 4
		var dn: Vector3 = [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT][face]
		var dc := p + dn * (1.41 if face % 2 == 0 else 1.31) + Vector3(0, 1.0, 0)
		var across := Vector3.UP.cross(dn)
		b.mat = M_GLASS if rng.randf() < 0.25 else M_DARK
		b.colour = Color(1.0, 0.72, 0.4, 1.0) * 0.5 if b.mat == M_GLASS else Color(0.25, 0.22, 0.2, 1.0)
		b.colour.a = 1.0
		b.quad(dc - across * 0.42 - Vector3(0, 0.95, 0), dc + across * 0.42 - Vector3(0, 0.95, 0),
				dc + across * 0.42 + Vector3(0, 1.0, 0), dc - across * 0.42 + Vector3(0, 1.0, 0), dn)
	# Solar water heaters: a panel tilted to the south (the room's +z is north-north-east: the sky's facing 200) and
	# a white tank over its top.
	var heaters := rng.randi_range(0, 3) if d < 140.0 else 0
	var south := Basis(Vector3.UP, deg_to_rad(20.0))
	for i in heaters:
		var p: Vector3 = pick.call(Vector2(2.4, 2.4))
		var fwd := south * Vector3.FORWARD
		var right := south * Vector3.RIGHT
		var tilt := 0.7
		var low := p + fwd * 0.6 + Vector3(0, 0.35, 0)
		var high := p - fwd * 0.35 + Vector3(0, 0.35 + 1.0 * sin(tilt) * 1.3, 0)
		b.mat = M_PANEL
		b.colour = Color(1, 1, 1, 1)
		var pn := (fwd * sin(tilt) + Vector3.UP * cos(tilt)).normalized()
		b.quad(low - right, low + right, high + right, high - right, pn)
		b.mat = M_METAL
		b.colour = Color(0.5, 0.5, 0.52, 1.0)
		b.quad(low - right, high - right, high + right, low + right, -pn)
		b.beam(low - right + Vector3(0, -0.35, 0), low - right, 0.05, 0.05, "tb")
		b.beam(low + right + Vector3(0, -0.35, 0), low + right, 0.05, 0.05, "tb")
		b.beam(high - right + Vector3(0, -high.y + y, 0), high - right, 0.05, 0.05, "tb")
		b.beam(high + right + Vector3(0, -high.y + y, 0), high + right, 0.05, 0.05, "tb")
		b.colour = Color(0.78, 0.78, 0.76, 1.0)
		b.cyl(high - right * 0.95 - fwd * 0.3 + Vector3(0, 0.25, 0), right, 0.3, 1.9, 7, "ab")
	# Black tanks.
	for i in (rng.randi_range(0, 2) if d < 140.0 else 0):
		var p: Vector3 = pick.call(Vector2(1.2, 1.2))
		b.mat = M_METAL
		b.colour = Color(0.05, 0.05, 0.05, 1.0)
		b.cyl(p, Vector3.UP, rng.randf_range(0.45, 0.6), rng.randf_range(0.9, 1.3), 8, "a")
	# Aerials on the nearer roofs: a mast, a boom with its elements.
	if d < 75.0:
		for i in rng.randi_range(0, 2):
			var p: Vector3 = pick.call(Vector2(0.5, 0.5))
			var h := rng.randf_range(2.6, 4.2)
			b.mat = M_METAL
			b.colour = Color(0.12, 0.12, 0.12, 1.0)
			b.beam(p, p + Vector3(0, h, 0), 0.05, 0.05, "b")
			var yaw := rng.randf() * TAU
			var bdir := Vector3(cos(yaw), 0, sin(yaw))
			var side := Vector3(-bdir.z, 0, bdir.x)
			for level in rng.randi_range(1, 2):
				var at := p + Vector3(0, h - 0.15 - level * 0.7, 0)
				b.beam(at - bdir * 0.9, at + bdir * 0.9, 0.035, 0.035)
				for j in 6:
					var q := at + bdir * lerpf(-0.8, 0.8, j / 5.0)
					var el := lerpf(0.55, 0.3, j / 5.0)
					b.beam(q - side * el, q + side * el, 0.025, 0.025)
	# A pergola with leaves, or a washing line, on some near roofs.
	if d < 70.0 and rng.randf() < 0.25:
		var p: Vector3 = pick.call(Vector2(3.0, 3.0))
		b.mat = M_METAL
		b.colour = Color(0.18, 0.14, 0.1, 1.0)
		for s: Vector2 in [Vector2(-1.4, -1.4), Vector2(1.4, -1.4), Vector2(1.4, 1.4), Vector2(-1.4, 1.4)]:
			b.beam(p + Vector3(s.x, 0, s.y), p + Vector3(s.x, 2.3, s.y), 0.07, 0.07, "b")
		b.mat = M_FOLIAGE
		b.extra = 0.5
		var g := OLIVE * 1.8
		b.colour = Color(g.r, g.g, g.b, 1.0)
		for j in 6:
			b.blob(p + Vector3(rng.randf_range(-1.3, 1.3), 2.35, rng.randf_range(-1.3, 1.3)),
					Vector3(0.9, 0.3, 0.9), rng)
	elif d < 70.0 and rng.randf() < 0.3:
		_washing(b, rng, pick.call(Vector2(3.0, 0.5)), rng.randf() * PI)


## A washing line between two posts, with things pegged on it.
static func _washing(b: Builder, rng: RandomNumberGenerator, p: Vector3, yaw: float) -> void:
	var dir := Vector3(cos(yaw), 0, sin(yaw))
	var nn := Vector3(-dir.z, 0, dir.x)
	b.mat = M_METAL
	b.colour = Color(0.4, 0.4, 0.4, 1.0)
	var a := p - dir * 1.6
	var e := p + dir * 1.6
	b.beam(a, a + Vector3(0, 1.8, 0), 0.05, 0.05, "b")
	b.beam(e, e + Vector3(0, 1.8, 0), 0.05, 0.05, "b")
	b.beam(a + Vector3(0, 1.75, 0), e + Vector3(0, 1.75, 0), 0.015, 0.015)
	b.mat = M_CLOTH
	var x := -1.4
	var cloths: Array[Color] = [Color(0.8, 0.8, 0.78), Color(0.6, 0.12, 0.1), Color(0.2, 0.3, 0.55),
			Color(0.75, 0.7, 0.4), Color(0.85, 0.85, 0.85)]
	while x < 1.3:
		var w := rng.randf_range(0.25, 0.6)
		var h := rng.randf_range(0.3, 0.8)
		var cc: Color = cloths[rng.randi() % cloths.size()]
		b.colour = Color(cc.r, cc.g, cc.b, 1.0)
		var t0 := p + dir * x + Vector3(0, 1.74, 0)
		b.quad2(t0, t0 + dir * w, t0 + dir * w - Vector3(0, h, 0), t0 - Vector3(0, h, 0), nn)
		x += w + rng.randf_range(0.05, 0.25)


# --- The roof's own block, by hand ---------------------------------------------------------------------------------

## The buildings round the terrace: the roof's own building under it, the screen building, the neighbours either side
## and in the row behind the screen building. The terrace (x -6.8..6.8, z -12..back) is the roof of the first.
static func _near(b: Builder, rng: RandomNumberGenerator) -> void:
	var back := 8.3
	# The roof's own building: its back wall onto the street behind (lit windows, balconies), down to the street.
	building(b, rng, Rect2(-6.8, -12.0, 13.6, back + 12.0), STREET_Y, -0.02, Color(0.8, 0.78, 0.73), 4,
			[false, false, true, false], 10.0, false, false)
	# The screen building: taller, its blind wall the screen (the terrace draws that wall's front); here its sides, its
	# back and its roof with a tank and an aerial over the wall's top.
	building(b, rng, Rect2(-8.5, -24.0, 17.0, 11.95), STREET_Y, 8.0, Color(0.74, 0.66, 0.52), 0,
			[false, true, false, true], 20.0, false)
	# Tanks on a steel stand just behind the wall's top on the left: their tops show over it from the seats.
	b.mat = M_METAL
	b.colour = Color(0.2, 0.2, 0.21, 1.0)
	for x: float in [-7.0, -4.8]:
		for z: float in [-12.5, -13.7]:
			b.beam(Vector3(x, 7.0, z), Vector3(x, 8.05, z), 0.06, 0.06, "b")
	b.box(Vector3(-5.9, 8.08, -13.1), Vector3(2.5, 0.06, 1.4), Basis(), "")
	b.colour = Color(0.05, 0.05, 0.05, 1.0)
	b.cyl(Vector3(-6.4, 8.1, -13.1), Vector3.UP, 0.55, 1.25, 8, "a")
	b.cyl(Vector3(-5.2, 8.1, -13.1), Vector3.UP, 0.5, 1.05, 8, "a")
	b.colour = Color(0.12, 0.12, 0.12, 1.0)
	var mast := Vector3(6.6, 7.0, -14.0)
	b.beam(mast, mast + Vector3(0, 3.6, 0), 0.05, 0.05, "b")
	for level in 2:
		var at := mast + Vector3(0, 3.4 - level * 0.75, 0)
		b.beam(at - Vector3(0.9, 0, 0.3), at + Vector3(0.9, 0, 0.3), 0.035, 0.035)
		for j in 6:
			var q := at + Vector3(0.9, 0, 0.3) * lerpf(-0.9, 0.9, j / 5.0)
			var el := lerpf(0.55, 0.3, j / 5.0)
			b.beam(q - Vector3(-0.3, 0, 0.9).normalized() * el, q + Vector3(-0.3, 0, 0.9).normalized() * el, 0.025,
					0.025)
	# A solar heater on the screen building's roof, its tank just showing over the wall's top on the right.
	b.mat = M_METAL
	b.colour = Color(0.78, 0.78, 0.76, 1.0)
	b.cyl(Vector3(4.6, 9.0, -12.8), Vector3.RIGHT, 0.3, 1.9, 7, "ab")
	b.colour = Color(0.4, 0.4, 0.42, 1.0)
	b.beam(Vector3(4.8, 7.0, -12.8), Vector3(4.8, 8.75, -12.8), 0.05, 0.05, "tb")
	b.beam(Vector3(6.3, 7.0, -12.8), Vector3(6.3, 8.75, -12.8), 0.05, 0.05, "tb")
	# The left neighbours: a roof just under the terrace's (heaters, tanks, an aerial over the parapet), a lower one
	# behind it with washing.
	building(b, rng, Rect2(-19.3, -12.0, 12.5, 11.0), STREET_Y, -0.4, Color(0.78, 0.72, 0.6), 0,
			[false, false, false, true], 12.0, false)
	_roof_heater(b, Vector3(-10.2, -1.4, -6.0))
	_roof_heater(b, Vector3(-13.4, -1.4, -6.5))
	b.mat = M_METAL
	b.colour = Color(0.05, 0.05, 0.05, 1.0)
	b.cyl(Vector3(-16.0, -1.4, -9.0), Vector3.UP, 0.55, 1.2, 8, "a")
	_aerial(b, Vector3(-8.6, -1.4, -3.0), 3.4, 0.4)
	building(b, rng, Rect2(-19.3, -1.0, 12.5, back + 1.0), STREET_Y, -1.6, Color(0.82, 0.8, 0.76), 4,
			[false, false, true, true], 12.0, false)
	_washing(b, rng, Vector3(-12.5, -2.6, 3.0), 0.1)
	b.mat = M_METAL
	b.colour = Color(0.05, 0.05, 0.05, 1.0)
	b.cyl(Vector3(-17.0, -2.6, 5.5), Vector3.UP, 0.5, 1.0, 8, "a")
	_roof_heater(b, Vector3(-9.6, -2.6, 6.0))
	# The taller block to the front left: its balconies face the seats over the neighbour's roof.
	building(b, rng, Rect2(-19.3, -29.8, 10.8, 17.8), STREET_Y, 7.4, Color(0.88, 0.78, 0.62), 4,
			[true, false, true, true], 18.0, true, true, true)
	# The right neighbours: a roof a little lower with a roof garden (a pergola, plants, a string of small lights) and
	# a low block in front of it (the citadel's view stays open over it).
	building(b, rng, Rect2(6.8, -12.0, 12.5, back + 12.0), STREET_Y, -0.9, Color(0.86, 0.8, 0.68), 4,
			[false, true, true, false], 12.0, false)
	_roof_garden(b, rng, Vector3(12.6, -1.9, -2.0))
	building(b, rng, Rect2(8.5, -29.8, 10.8, 17.8), STREET_Y, -1.5, Color(0.76, 0.7, 0.58), 0,
			[true, true, false, false], 22.0, true)
	# The row behind the screen building.
	building(b, rng, Rect2(-8.5, -29.8, 17.0, 5.8), STREET_Y, 10.5, Color(0.7, 0.68, 0.64), 1,
			[true, false, false, false], 26.0, true)


static func _roof_heater(b: Builder, p: Vector3) -> void:
	var south := Basis(Vector3.UP, deg_to_rad(20.0))
	var fwd := south * Vector3.FORWARD
	var right := south * Vector3.RIGHT
	var tilt := 0.7
	var low := p + fwd * 0.6 + Vector3(0, 0.35, 0)
	var high := p - fwd * 0.35 + Vector3(0, 0.35 + sin(tilt) * 1.3, 0)
	b.mat = M_PANEL
	b.colour = Color(1, 1, 1, 1)
	var pn := (fwd * sin(tilt) + Vector3.UP * cos(tilt)).normalized()
	b.quad(low - right, low + right, high + right, high - right, pn)
	b.mat = M_METAL
	b.colour = Color(0.5, 0.5, 0.52, 1.0)
	b.quad(low - right, high - right, high + right, low + right, -pn)
	for s: float in [-1.0, 1.0]:
		b.beam(low + right * s + Vector3(0, -0.35, 0), low + right * s, 0.05, 0.05, "tb")
		b.beam(high + right * s + Vector3(0, -high.y + p.y, 0), high + right * s, 0.05, 0.05, "tb")
	b.colour = Color(0.78, 0.78, 0.76, 1.0)
	b.cyl(high - right * 0.95 - fwd * 0.3 + Vector3(0, 0.25, 0), right, 0.3, 1.9, 7, "ab")


static func _aerial(b: Builder, p: Vector3, h: float, yaw: float) -> void:
	b.mat = M_METAL
	b.colour = Color(0.12, 0.12, 0.12, 1.0)
	b.beam(p, p + Vector3(0, h, 0), 0.05, 0.05, "b")
	var bdir := Vector3(cos(yaw), 0, sin(yaw))
	var side := Vector3(-bdir.z, 0, bdir.x)
	for level in 2:
		var at := p + Vector3(0, h - 0.15 - level * 0.7, 0)
		b.beam(at - bdir * 0.9, at + bdir * 0.9, 0.035, 0.035)
		for j in 6:
			var q := at + bdir * lerpf(-0.8, 0.8, j / 5.0)
			var el := lerpf(0.55, 0.3, j / 5.0)
			b.beam(q - side * el, q + side * el, 0.025, 0.025)


## The right neighbour's roof garden: a pergola of beams with a vine over it, plants in pots along its parapet, a
## table, and a string of small warm lights along the pergola.
static func _roof_garden(b: Builder, rng: RandomNumberGenerator, p: Vector3) -> void:
	b.mat = M_METAL
	b.colour = Color(0.2, 0.15, 0.1, 1.0)
	var w := 4.8
	var dd := 6.0
	for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(-1, 0), Vector2(1, 0)]:
		b.beam(p + Vector3(s.x * w * 0.5, 0, s.y * dd * 0.5), p + Vector3(s.x * w * 0.5, 2.5, s.y * dd * 0.5), 0.09,
				0.09, "b")
	for k in 7:
		var z := lerpf(-dd * 0.5, dd * 0.5, k / 6.0)
		b.beam(p + Vector3(-w * 0.5 - 0.2, 2.55, z), p + Vector3(w * 0.5 + 0.2, 2.55, z), 0.06, 0.1)
	for s: float in [-1.0, 1.0]:
		b.beam(p + Vector3(s * w * 0.5, 2.45, -dd * 0.5 - 0.2), p + Vector3(s * w * 0.5, 2.45, dd * 0.5 + 0.2), 0.08,
				0.12)
	b.mat = M_FOLIAGE
	b.extra = 0.6
	var g := OLIVE * 2.2
	b.colour = Color(g.r, g.g, g.b, 1.0)
	for j in 14:
		b.blob(p + Vector3(rng.randf_range(-w * 0.5, w * 0.5), 2.7, rng.randf_range(-dd * 0.5, dd * 0.5)),
				Vector3(0.8, 0.28, 0.8) * rng.randf_range(0.7, 1.2), rng)
	# A vine up one post.
	for j in 5:
		b.blob(p + Vector3(-w * 0.5, 0.4 + j * 0.45, dd * 0.5), Vector3(0.35, 0.3, 0.35), rng)
	# Pots along the parapet (the terrace's side) and a table.
	for j in 6:
		var pp := p + Vector3(-5.2, 0, lerpf(-7.5, 8.0, j / 5.0))
		b.mat = M_CLOTH
		b.colour = Color(0.55, 0.26, 0.15, 1.0)
		b.cyl(pp, Vector3.UP, 0.25, 0.4, 6, "")
		b.mat = M_FOLIAGE
		var gc := OLIVE * rng.randf_range(1.6, 2.6)
		b.colour = Color(gc.r, gc.g, gc.b, 1.0)
		b.blob(pp + Vector3(0, 0.75, 0), Vector3(0.4, 0.45, 0.4) * rng.randf_range(0.8, 1.3), rng)
	b.mat = M_METAL
	b.colour = Color(0.7, 0.68, 0.64, 1.0)
	b.cyl(p + Vector3(0.4, 0, 0.5), Vector3.UP, 0.05, 0.72, 5, "")
	b.cyl(p + Vector3(0.4, 0.72, 0.5), Vector3.UP, 0.45, 0.03, 10, "a")
	# The small lights along the pergola's edges, sagging between its posts.
	for s: float in [-1.0, 1.0]:
		for k in 12:
			var t := k / 11.0
			var z := lerpf(-dd * 0.5, dd * 0.5, t)
			var sag := sin(fposmod(t * 2.0, 1.0) * PI) * 0.18
			b.lamp(p + Vector3(s * w * 0.5 + s * 0.05, 2.38 - sag, z), 0.07, Color(1.0, 0.72, 0.4) * 2.2)


# --- The church -------------------------------------------------------------------------------------------------------

## A big Byzantine church in its square: a cross-in-square of ochre stone banded with brick, the dome on its drum with
## arched windows, tiled roofs over the arms, two bell towers either side of the west front, cypresses and a plane
## tree in the square. Floodlit softly (the church_light); a few windows warm with candles.
static func _church(b: Builder, rng: RandomNumberGenerator) -> void:
	var g := ground(CHURCH.x, CHURCH.z)
	# The square: paving, its trees.
	b.mat = M_STREET
	b.colour = PAVING * 1.1
	b.custom = Color(14.0, 0.2, 0, 0)
	var sq := Rect2(CHURCH.x - 17.0, CHURCH.z - 14.0, 30.0, 26.0)
	b.quad(Vector3(sq.position.x, g + 0.1, sq.position.y), Vector3(sq.end.x, g + 0.1, sq.position.y),
			Vector3(sq.end.x, g + 0.1, sq.end.y), Vector3(sq.position.x, g + 0.1, sq.end.y), Vector3.UP,
			Vector2(0, 0), Vector2(30, 0), Vector2(30, 1), Vector2(0, 1))
	b.custom = Color(0, 0, 0, 0)
	# Its axis: east-west (the apse to the east; the sky's facing 200: east is 110 degrees to the left of the front).
	var basis := Basis(Vector3.UP, deg_to_rad(20.0))
	var c := Vector3(CHURCH.x, g, CHURCH.z)
	var along := basis * Vector3.RIGHT
	var across := basis * Vector3.BACK
	var ochre := Color(0.72, 0.56, 0.38)
	var brick := Color(0.55, 0.28, 0.17)
	b.mat = M_CHURCH
	b.extra = 0.7
	b.colour = Color(ochre.r, ochre.g, ochre.b, 1.0)
	var h := 11.0
	var lw := 22.0
	var ww := 13.0
	# The body: the cross's arms (a nave along the axis, a transept across) and the corners lower.
	_church_box(b, c, along, across, Vector3(lw, h, 8.0), h)
	_church_box(b, c, along, across, Vector3(8.0, h, ww + 4.0), h)
	_church_box(b, c, along, across, Vector3(lw - 2.0, h - 3.0, ww), h)
	# Bands of brick round it (three courses).
	b.colour = Color(brick.r, brick.g, brick.b, 1.0)
	for y: float in [3.2, 6.4]:
		_church_box(b, c + Vector3(0, y, 0), along, across, Vector3(lw - 1.98, 0.35, ww + 0.04), h, y)
	# The apse: a half drum to the east.
	b.colour = Color(ochre.r, ochre.g, ochre.b, 1.0)
	var apse := c + along * (lw * 0.5)
	for s in 8:
		var a0 := -PI * 0.5 + PI * s / 8.0
		var a1 := -PI * 0.5 + PI * (s + 1) / 8.0
		var d0 := along * cos(a0) + across * sin(a0)
		var d1 := along * cos(a1) + across * sin(a1)
		b.quad(apse + d0 * 3.2, apse + d1 * 3.2, apse + d1 * 3.2 + Vector3(0, 8.0, 0), apse + d0 * 3.2 + Vector3(0,
				8.0, 0), (d0 + d1).normalized(), Vector2(0, 0), Vector2(1, 0), Vector2(1, 8.0 / h), Vector2(0, 8.0 / h))
	# Tiled roofs over the arms: low pitched, terracotta.
	b.mat = M_TILE
	b.extra = 0.6
	b.colour = Color(0.5, 0.24, 0.14, 1.0)
	for arm: Array in [[along, across, lw * 0.5, 4.0], [across, along, (ww + 4.0) * 0.5, 4.0]]:
		var ax: Vector3 = arm[0]
		var sd: Vector3 = arm[1]
		var half_l := float(arm[2])
		var half_w := float(arm[3])
		var ridge := c + Vector3(0, h + 1.6, 0)
		for s: float in [-1.0, 1.0]:
			var eave := c + sd * s * (half_w + 0.3) + Vector3(0, h - 0.1, 0)
			b.quad(ridge - ax * half_l, ridge + ax * half_l, eave + ax * half_l, eave - ax * half_l,
					(sd * s * 1.6 + Vector3.UP * (half_w + 0.3)).normalized(), Vector2(0, 0), Vector2(half_l * 2.0, 0),
					Vector2(half_l * 2.0, 1), Vector2(0, 1))
		# The gables at the arms' ends.
		b.mat = M_CHURCH
		b.colour = Color(ochre.r, ochre.g, ochre.b, 1.0)
		for e: float in [-1.0, 1.0]:
			var gb := c + ax * e * half_l
			b.tri(gb + sd * (half_w + 0.3) + Vector3(0, h - 0.1, 0), gb - sd * (half_w + 0.3) + Vector3(0, h - 0.1, 0),
					gb + Vector3(0, h + 1.6, 0), ax * e, Vector2(0, 1), Vector2(0, 1), Vector2(0, 1))
		b.mat = M_TILE
		b.colour = Color(0.5, 0.24, 0.14, 1.0)
	# The drum and the dome over the crossing.
	b.mat = M_CHURCH
	b.colour = Color(ochre.r, ochre.g, ochre.b, 1.0)
	var drum := c + Vector3(0, h + 1.2, 0)
	var dr := 3.4
	var sides := 12
	for s in sides:
		var a0 := TAU * s / sides
		var a1 := TAU * (s + 1) / sides
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		b.quad(drum + d0 * dr, drum + d1 * dr, drum + d1 * dr + Vector3(0, 4.2, 0), drum + d0 * dr + Vector3(0, 4.2, 0),
				(d0 + d1).normalized(), Vector2(0, 0.6), Vector2(1, 0.6), Vector2(1, 1), Vector2(0, 1))
		# An arched window in each face: warm, dim (candles within) or dark.
		var mid := drum + (d0 + d1).normalized() * (dr * cos(PI / sides) + 0.03) + Vector3(0, 1.9, 0)
		var t := (d1 - d0).normalized()
		b.mat = M_GLASS
		b.colour = Color(1.0, 0.62, 0.3, 1.0) * (0.55 if s % 3 != 1 else 0.12)
		b.colour.a = 1.0
		b.quad(mid - t * 0.32 - Vector3(0, 1.0, 0), mid + t * 0.32 - Vector3(0, 1.0, 0), mid + t * 0.32 + Vector3(0, 0.8,
				0), mid - t * 0.32 + Vector3(0, 0.8, 0), (d0 + d1).normalized())
		b.tri(mid - t * 0.32 + Vector3(0, 0.8, 0), mid + t * 0.32 + Vector3(0, 0.8, 0), mid + Vector3(0, 1.12, 0),
				(d0 + d1).normalized())
		b.mat = M_CHURCH
		b.colour = Color(ochre.r, ochre.g, ochre.b, 1.0)
	b.mat = M_TILE
	b.extra = 0.8
	b.colour = Color(0.42, 0.22, 0.14, 1.0)
	var rings := 5
	var dome := drum + Vector3(0, 4.2, 0)
	for r in rings:
		var l0 := PI * 0.5 * r / rings
		var l1 := PI * 0.5 * (r + 1) / rings
		for s in sides:
			var a0 := TAU * s / sides
			var a1 := TAU * (s + 1) / sides
			var p00 := dome + Vector3(cos(a0) * cos(l0), sin(l0), sin(a0) * cos(l0)) * (dr + 0.15)
			var p10 := dome + Vector3(cos(a1) * cos(l0), sin(l0), sin(a1) * cos(l0)) * (dr + 0.15)
			var p11 := dome + Vector3(cos(a1) * cos(l1), sin(l1), sin(a1) * cos(l1)) * (dr + 0.15)
			var p01 := dome + Vector3(cos(a0) * cos(l1), sin(l1), sin(a0) * cos(l1)) * (dr + 0.15)
			var nn := ((p00 + p11) * 0.5 - dome).normalized()
			b.quad(p00, p10, p11, p01, nn, Vector2(s, 0), Vector2(s + 1, 0), Vector2(s + 1, 1), Vector2(s, 1))
	# The cross on top (iron, dark).
	b.mat = M_METAL
	b.colour = Color(0.3, 0.26, 0.2, 1.0)
	var top := dome + Vector3(0, dr + 0.15, 0)
	b.beam(top, top + Vector3(0, 1.9, 0), 0.12, 0.12, "b")
	b.beam(top + Vector3(0, 1.35, 0) - along * 0.55, top + Vector3(0, 1.35, 0) + along * 0.55, 0.1, 0.1)
	# Two bell towers at the west front: square, an open belfry of arches, a small dome, a cross.
	for s: float in [-1.0, 1.0]:
		var tc := c - along * (lw * 0.5 + 1.6) + across * s * (ww * 0.5 - 1.0)
		_bell_tower(b, tc, along, across)
	# The square's trees: cypresses and a plane tree.
	b.mat = M_FOLIAGE
	b.extra = 1.0
	for k in 5:
		var tp := Vector3(CHURCH.x + rng.randf_range(-15.0, 11.0), g, CHURCH.z + rng.randf_range(4.0, 11.0))
		var gc := OLIVE * rng.randf_range(1.0, 1.6)
		b.colour = Color(gc.r, gc.g, gc.b, 1.0)
		if k < 3:
			for j in 4:
				b.blob(tp + Vector3(0, 2.5 + j * 2.4, 0), Vector3(1.2 - j * 0.22, 1.6, 1.2 - j * 0.22), rng)
		else:
			b.mat = M_METAL
			b.colour = Color(0.25, 0.22, 0.18, 1.0)
			b.cyl(tp, Vector3.UP, 0.3, 4.0, 5, "")
			b.mat = M_FOLIAGE
			b.colour = Color(gc.r, gc.g, gc.b, 1.0) * 1.3
			b.colour.a = 1.0
			for j in 5:
				b.blob(tp + Vector3(rng.randf_range(-2.5, 2.5), rng.randf_range(4.5, 7.0), rng.randf_range(-2.5, 2.5)),
						Vector3(2.4, 1.8, 2.4), rng)


static func _church_box(b: Builder, c: Vector3, along: Vector3, across: Vector3, size: Vector3, h: float,
		y0 := 0.0) -> void:
	var hx := along * size.x * 0.5
	var hz := across * size.z * 0.5
	var lo := c + Vector3(0, -2.0 if y0 == 0.0 else 0.0, 0)
	var hi := c + Vector3(0, size.y, 0)
	var corners := [-hx - hz, hx - hz, hx + hz, -hx + hz]
	for k in 4:
		var a: Vector3 = corners[k]
		var e: Vector3 = corners[(k + 1) % 4]
		var nn := ((a + e) * 0.5).normalized()
		b.quad(lo + a, lo + e, hi + e, hi + a, nn, Vector2(0, (lo.y - c.y + y0) / h), Vector2(1, (lo.y - c.y + y0) / h),
				Vector2(1, (size.y + y0) / h), Vector2(0, (size.y + y0) / h))
	b.quad(hi + corners[0], hi + corners[1], hi + corners[2], hi + corners[3], Vector3.UP, Vector2(0, 1), Vector2(1, 1),
			Vector2(1, 1), Vector2(0, 1))


static func _bell_tower(b: Builder, tc: Vector3, along: Vector3, across: Vector3) -> void:
	var w := 3.2
	var h := 19.0
	var ochre := Color(0.74, 0.58, 0.4)
	b.mat = M_CHURCH
	b.extra = 0.8
	b.colour = Color(ochre.r, ochre.g, ochre.b, 1.0)
	_church_box(b, tc, along, across, Vector3(w, h - 4.0, w), h)
	# The belfry: four corner piers and a lintel, open between (the bell inside), then a small dome and a cross.
	var by := tc.y + h - 4.0
	for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var p := tc + along * s.x * (w * 0.5 - 0.3) + across * s.y * (w * 0.5 - 0.3)
		_church_box(b, Vector3(p.x, by, p.z), along, across, Vector3(0.6, 3.0, 0.6), h, h - 4.0)
	_church_box(b, Vector3(tc.x, by + 3.0, tc.z), along, across, Vector3(w + 0.2, 0.6, w + 0.2), h, h - 1.0)
	b.mat = M_METAL
	b.colour = Color(0.35, 0.26, 0.14, 1.0)
	b.cyl(Vector3(tc.x, by + 1.2, tc.z), Vector3.UP, 0.55, 1.2, 8, "b")
	b.mat = M_TILE
	b.extra = 0.7
	b.colour = Color(0.42, 0.22, 0.14, 1.0)
	var dome := Vector3(tc.x, by + 3.6, tc.z)
	for s in 8:
		var a0 := TAU * s / 8.0
		var a1 := TAU * (s + 1) / 8.0
		b.tri(dome + Vector3(0, 1.6, 0), dome + Vector3(cos(a1), 0, sin(a1)) * 1.7, dome + Vector3(cos(a0), 0, sin(a0)) * 1.7,
				Vector3(cos((a0 + a1) * 0.5), 0.8, sin((a0 + a1) * 0.5)).normalized(), Vector2(s, 1), Vector2(s + 1, 0),
				Vector2(s, 0))
	b.mat = M_METAL
	b.colour = Color(0.3, 0.26, 0.2, 1.0)
	b.beam(dome + Vector3(0, 1.5, 0), dome + Vector3(0, 2.9, 0), 0.09, 0.09, "b")
	b.beam(dome + Vector3(0, 2.45, 0) - along * 0.4, dome + Vector3(0, 2.45, 0) + along * 0.4, 0.08, 0.08)


# --- The citadel ------------------------------------------------------------------------------------------------------

## An invented citadel on its hill, beside the screen wall to the right: a plateau ringed by cliffs and walls, the
## slopes under them dark with trees and a scatter of small white houses, a ruined temple of columns whose long side
## faces the roof, a smaller temple with a porch, a gateway of columns at the plateau's end. Floodlit honey-gold.
static func _citadel(b: Builder, rng: RandomNumberGenerator) -> void:
	var c := citadel_centre()
	var foot := ground(c.x, c.z)
	var long := Vector3(cos(deg_to_rad(CITADEL_AZ)), 0, sin(deg_to_rad(CITADEL_AZ)))
	var deep := Vector3(-long.z, 0, long.x)
	if deep.dot(c) < 0.0:
		deep = -deep
	# The hill: rings round the plateau from its edge down to the city's ground; cliffs under the walls.
	var sides := 40
	var rings := [[1.0, CITADEL_TOP, M_ROCK, 1.0], [1.04, CITADEL_TOP - 1.0, M_ROCK, 1.0],
			[1.12, CITADEL_TOP - 9.0, M_ROCK, 0.55], [1.32, CITADEL_TOP - 15.0, M_FOLIAGE, 0.2],
			[1.62, foot + 6.0, M_FOLIAGE, 0.05], [1.95, foot - 1.0, M_FOLIAGE, 0.0]]
	var rx := 44.0
	var rz := 20.0
	var pts: Array = []
	for r: Array in rings:
		var row := PackedVector3Array()
		for s in sides:
			var a := TAU * s / sides
			var jit := 1.0 + 0.08 * (_n1(s * 0.7, 3) - 0.5) + 0.05 * (_n1(s * 2.3, 5) - 0.5)
			var k := float(r[0]) * jit
			var y := float(r[1]) + (_n1(s * 1.3, 7) - 0.5) * (2.5 if float(r[0]) > 1.05 else 0.0)
			row.append(c + long * cos(a) * rx * k + deep * sin(a) * rz * k + Vector3(0, y, 0))
		pts.append(row)
	for ri in rings.size() - 1:
		var r0: PackedVector3Array = pts[ri]
		var r1: PackedVector3Array = pts[ri + 1]
		var m := int(rings[ri + 1][2])
		b.mat = m
		var tone := ROCK if m == M_ROCK else PINE * 1.4
		b.colour = Color(tone.r, tone.g, tone.b, 1.0)
		for s in sides:
			var p00 := r0[s]
			var p01 := r0[(s + 1) % sides]
			var p10 := r1[s]
			var p11 := r1[(s + 1) % sides]
			var out := ((p10 + p11) * 0.5 - c)
			out.y = 0.0
			var slope := ((p00 + p01) * 0.5 - (p10 + p11) * 0.5)
			var nn := (out.normalized() * absf(slope.y) + Vector3.UP * Vector2(slope.x, slope.z).length()).normalized()
			b.extra = 1.0
			var f0 := float(rings[ri][3])
			var f1 := float(rings[ri + 1][3])
			b.quad(p10, p11, p01, p00, nn, Vector2(0, f1), Vector2(1, f1), Vector2(1, f0), Vector2(0, f0))
	# The plateau's top.
	b.mat = M_ROCK
	b.colour = Color(0.36, 0.32, 0.27, 1.0)
	b.extra = 0.25
	var top_ring: PackedVector3Array = pts[0]
	var centre_top := c + Vector3(0, CITADEL_TOP, 0)
	for s in sides:
		b.tri(centre_top, top_ring[s], top_ring[(s + 1) % sides], Vector3.UP, Vector2(0, 0.6), Vector2(0, 0.6),
				Vector2(0, 0.6))
	# The walls round the plateau's edge (the side towards the roof most): battered, with buttresses, floodlit.
	b.mat = M_FLOOD
	b.colour = Color(STONE.r, STONE.g, STONE.b, 1.0) * 0.9
	b.colour.a = 1.0
	b.extra = 0.8
	for s in sides:
		var a := TAU * s / sides
		if sin(a) > 0.35:
			continue
		var p0: Vector3 = (pts[1] as PackedVector3Array)[s]
		var p1: Vector3 = (pts[1] as PackedVector3Array)[(s + 1) % sides]
		var out := ((p0 + p1) * 0.5 - c)
		out.y = 0.0
		out = out.normalized()
		# Each stretch its own height and its own share of the light (the lamps stand apart along the foot).
		var rise := 2.0 + 2.5 * _n1(s * 0.9, 11) + (1.5 if s % 7 == 2 else 0.0)
		var lit := 0.55 + 0.45 * _n1(s * 0.6 + 4.0, 12)
		b.extra = 0.8 * lit
		var base0 := p0 - Vector3(0, 7.0, 0)
		var base1 := p1 - Vector3(0, 7.0, 0)
		var top0 := p0 + Vector3(0, rise, 0) - out * 0.8
		var top1 := p1 + Vector3(0, rise, 0) - out * 0.8
		var hgt := rise + 7.0
		b.quad(base0, base1, top1, top0, (out + Vector3.UP * 0.12).normalized(), Vector2(0, 0), Vector2(1, 0),
				Vector2(1, hgt), Vector2(0, hgt))
		b.quad(top0, top1, top1 - out * 1.6, top0 - out * 1.6, Vector3.UP, Vector2(0, hgt), Vector2(1, hgt),
				Vector2(1, hgt), Vector2(0, hgt))
		if s % 4 == 1:
			# A buttress against the wall, its top sloping back.
			var bc := (base0 + base1) * 0.5 + out * 0.7
			var bh := hgt * 0.8
			b.box(bc + Vector3(0, bh * 0.5, 0), Vector3(1.8, bh, 1.4), Basis(out.cross(Vector3.UP), Vector3.UP, out),
					"b", bc.y)
	# The temple: on the plateau, its long side to the roof, a little back from the edge.
	var tc := c + deep * 3.0 + long * 4.0 + Vector3(0, CITADEL_TOP, 0)
	_temple(b, tc, long, deep, 31.0, 14.0, 8, 17, 10.2, rng, true)
	# A smaller temple with a porch at one side, a gateway at the plateau's west end.
	_temple(b, c - long * 24.0 + deep * 4.0 + Vector3(0, CITADEL_TOP, 0), long, deep, 14.0, 8.0, 6, 0, 7.0, rng,
			false)
	_temple(b, c - long * 39.0 - deep * 1.0 + Vector3(0, CITADEL_TOP - 1.0, 0), deep, -long, 16.0, 6.0, 6, 0, 7.5,
			rng, false)
	# Trees on the slopes (dark crowns) and small white houses climbing the lower slope under the cliffs.
	for k in 70:
		var a := rng.randf() * TAU
		var rr := rng.randf_range(1.2, 1.85)
		var p := c + long * cos(a) * rx * rr + deep * sin(a) * rz * rr
		var y := _hill_y(rings, rr) + 0.5
		b.mat = M_FOLIAGE
		b.extra = 0.0
		b.uv_flood = clampf(1.6 - rr, 0.0, 1.0)
		var gc := PINE * rng.randf_range(1.0, 2.0)
		b.colour = Color(gc.r, gc.g, gc.b, 1.0)
		var s := rng.randf_range(1.6, 3.2)
		b.blob(p + Vector3(0, y + s * 0.8, 0), Vector3(s, s * 1.1, s), rng)
	b.uv_flood = 0.0
	for k in 36:
		var a := rng.randf_range(PI * 0.95, PI * 1.6)
		var rr := rng.randf_range(1.22, 1.6)
		var p := c + long * cos(a) * rx * rr + deep * sin(a) * rz * rr
		var y := _hill_y(rings, rr)
		b.mat = M_WALL
		var wc := WASHES[0] * rng.randf_range(0.9, 1.05)
		b.colour = Color(wc.r, wc.g, wc.b, 1.0)
		var size := Vector3(rng.randf_range(3.0, 5.0), rng.randf_range(2.8, 3.6), rng.randf_range(3.0, 4.5))
		b.custom = Color(2.2, size.y - 0.6, rng.randf(), 0.0)
		b.box(p + Vector3(0, y + size.y * 0.5 - 1.0, 0), size + Vector3(0, 2.0, 0), Basis(Vector3.UP, rng.randf() * 0.4
				- 0.2 - deg_to_rad(CITADEL_AZ)), "b", p.y + y - 1.0)
		b.custom = Color(0, 0, 0, 0)


static func _hill_y(rings: Array, rr: float) -> float:
	for i in rings.size() - 1:
		var a := float(rings[i][0])
		var e := float(rings[i + 1][0])
		if rr >= a and rr <= e:
			return lerpf(float(rings[i][1]), float(rings[i + 1][1]), (rr - a) / (e - a))
	return float(rings[-1][1])


## A temple: a stepped platform, its columns (front `ends` across, `sides` along; 0 sides: a porch of `ends` at the
## front only, a walled cell behind), the beams over them, pediments at the ends, the roof gone. Floodlit, brighter
## low down; the cell inside dark. ruined: some columns gone on the long side away from the roof.
static func _temple(b: Builder, c: Vector3, long: Vector3, deep: Vector3, length: float, width: float, ends: int,
		sides: int, col_h: float, rng: RandomNumberGenerator, ruined: bool) -> void:
	b.mat = M_FLOOD
	b.extra = 1.0
	b.colour = Color(STONE.r, STONE.g, STONE.b, 1.0)
	var basis := Basis(long, Vector3.UP, deep)
	# The steps.
	for k in 3:
		var y := c.y + 0.27 + k * 0.54
		var grow := (2 - k) * 0.6
		b.box(Vector3(c.x, y, c.z), Vector3(length + 2.4 + grow, 0.54, width + 2.4 + grow), basis, "b", c.y)
	var cy := c.y + 1.62
	var r := width * 0.065
	var spots: Array[Vector2] = []
	if sides > 0:
		for i in sides:
			var x := lerpf(-length * 0.5, length * 0.5, float(i) / (sides - 1))
			spots.append(Vector2(x, -width * 0.5))
			if not ruined or (i < 4 or i > 9 or i % 3 == 0):
				spots.append(Vector2(x, width * 0.5))
		for j in range(1, ends - 1):
			var z := lerpf(-width * 0.5, width * 0.5, float(j) / (ends - 1))
			spots.append(Vector2(-length * 0.5, z))
			spots.append(Vector2(length * 0.5, z))
	else:
		for j in ends:
			spots.append(Vector2(-length * 0.5, lerpf(-width * 0.5, width * 0.5, float(j) / (ends - 1))))
	for s: Vector2 in spots:
		var p := c + long * s.x + deep * s.y
		p.y = cy
		b.colour = Color(STONE.r, STONE.g, STONE.b, 1.0) * rng.randf_range(0.9, 1.05)
		b.colour.a = 1.0
		_column(b, p, r, col_h, cy - c.y)
	# The cell inside: walls, dark within (the floodlights are outside).
	b.mat = M_FLOOD
	b.extra = 0.35
	b.colour = Color(STONE.r, STONE.g, STONE.b, 1.0) * 0.7
	b.colour.a = 1.0
	var cell_l := length * (0.72 if sides > 0 else 0.8)
	var cell_c := c + (long * length * 0.12 if sides == 0 else Vector3.ZERO)
	var wall_h := col_h * (0.55 if ruined else 1.0)
	b.box(Vector3(cell_c.x, cy + wall_h * 0.5, cell_c.z), Vector3(cell_l, wall_h, width * 0.62), basis, "b", c.y)
	# The beams over the columns, the pediments; on a ruin only over the ends and part of the near side.
	b.mat = M_FLOOD
	b.extra = 1.0
	b.colour = Color(STONE.r, STONE.g, STONE.b, 1.0)
	var ey := cy + col_h
	if sides > 0:
		b.box(Vector3(c.x, ey + 1.5, c.z) - deep * width * 0.5, Vector3(length + r * 2.6, 3.0, r * 2.6), basis, "", c.y)
		if not ruined:
			b.box(Vector3(c.x, ey + 1.5, c.z) + deep * width * 0.5, Vector3(length + r * 2.6, 3.0, r * 2.6), basis, "",
					c.y)
		else:
			for part: Vector2 in [Vector2(-0.5, -0.32), Vector2(0.36, 0.5)]:
				var x0 := part.x * length
				var x1 := part.y * length
				b.box(c + long * (x0 + x1) * 0.5 + deep * width * 0.5 + Vector3(0, ey + 1.5 - c.y, 0),
						Vector3(x1 - x0, 3.0, r * 2.6), basis, "", c.y)
		for e: float in [-1.0, 1.0]:
			b.box(Vector3(c.x, ey + 1.5, c.z) + long * e * length * 0.5, Vector3(r * 2.6, 3.0, width + r * 2.6), basis,
					"", c.y)
			# The pediment: a low gable over the end.
			var gc := Vector3(c.x, ey + 3.0, c.z) + long * e * (length * 0.5 + r * 1.3)
			b.tri(gc - deep * (width * 0.5 + r * 1.3), gc + deep * (width * 0.5 + r * 1.3), gc + Vector3(0, 3.0, 0),
					long * e, Vector2(0, ey + 3.0 - c.y), Vector2(0, ey + 3.0 - c.y), Vector2(0, ey + 6.0 - c.y))
			b.box(Vector3(c.x, ey + 3.05, c.z) + long * e * length * 0.5, Vector3(r * 2.6, 0.1, width + r * 2.6), basis,
					"b", c.y)
	else:
		var front := c - long * length * 0.5
		b.box(Vector3(front.x, ey + 1.0, front.z), Vector3(r * 2.4, 2.0, width + r * 2.4), basis, "", c.y)
		b.tri(Vector3(front.x, ey + 2.0, front.z) - deep * (width * 0.5 + r), Vector3(front.x, ey + 2.0, front.z) + deep
				* (width * 0.5 + r), Vector3(front.x, ey + 4.0, front.z), -long, Vector2(0, ey + 2.0 - c.y),
				Vector2(0, ey + 2.0 - c.y), Vector2(0, ey + 4.0 - c.y))


## A column: a shaft of eight faces tapering a little, a capital's slab. UV.y: metres up from the temple's foot.
static func _column(b: Builder, p: Vector3, r: float, h: float, lift: float) -> void:
	var sides := 8
	var top := p + Vector3(0, h - 0.5, 0)
	for s in sides:
		var a0 := TAU * s / sides
		var a1 := TAU * (s + 1) / sides
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var nn := (d0 + d1).normalized()
		b.quad(p + d0 * r, p + d1 * r, top + d1 * r * 0.82, top + d0 * r * 0.82, nn, Vector2(0, lift),
				Vector2(0, lift), Vector2(0, lift + h), Vector2(0, lift + h))
	b.box(top + Vector3(0, 0.25, 0), Vector3(r * 2.5, 0.5, r * 2.5), Basis(), "b", p.y - lift)


# --- The chapel's hill and the hills round the basin ---------------------------------------------------------------

## A steep hill behind on the left, dark with pines; a path of lamps zigzagging up the side towards the roof; a white
## chapel floodlit on the top, a lit terrace just under it.
static func _chapel_hill(b: Builder, rng: RandomNumberGenerator) -> void:
	var c := chapel_centre()
	var foot := ground(c.x, c.z) - 2.0
	var sides := 18
	var profile := [[0.0, CHAPEL_TOP], [5.0, CHAPEL_TOP - 1.0], [10.0, CHAPEL_TOP - 8.0], [17.0, CHAPEL_TOP - 20.0],
			[25.0, foot + 12.0], [36.0, foot]]
	var rows: Array = []
	for pr: Array in profile:
		var row := PackedVector3Array()
		for s in sides:
			var a := TAU * s / sides
			var k := 1.0 + 0.12 * (_n1(s * 0.8, 13) - 0.5)
			row.append(c + Vector3(cos(a) * float(pr[0]) * k, float(pr[1]) + (_n1(s * 1.7, 17) - 0.5) * 1.5 * minf(
					float(pr[0]) / 10.0, 1.0), sin(a) * float(pr[0]) * k))
		rows.append(row)
	b.mat = M_FOLIAGE
	b.extra = 0.0
	b.colour = Color(PINE.r, PINE.g, PINE.b, 1.0) * 1.3
	b.colour.a = 1.0
	for ri in rows.size() - 1:
		var r0: PackedVector3Array = rows[ri]
		var r1: PackedVector3Array = rows[ri + 1]
		for s in sides:
			var p00 := r0[s]
			var p01 := r0[(s + 1) % sides]
			var p10 := r1[s]
			var p11 := r1[(s + 1) % sides]
			var out := (p10 + p11) * 0.5 - c
			out.y = 0.0
			var nn := (out.normalized() + Vector3.UP * 0.6).normalized()
			if ri == 0:
				b.mat = M_ROCK
				b.extra = 0.0
				b.colour = Color(0.3, 0.27, 0.24, 1.0)
			else:
				b.mat = M_FOLIAGE
				b.colour = Color(PINE.r, PINE.g, PINE.b, 1.0) * 1.3
				b.colour.a = 1.0
			b.quad(p10, p11, p01, p00, nn)
	# Pines' crowns on the slopes.
	for k in 40:
		var a := rng.randf() * TAU
		var rr := rng.randf_range(9.0, 32.0)
		var y := _profile_y(profile, rr)
		var gc := PINE * rng.randf_range(1.2, 2.2)
		b.mat = M_FOLIAGE
		b.colour = Color(gc.r, gc.g, gc.b, 1.0)
		var s := rng.randf_range(1.5, 2.8)
		b.blob(c + Vector3(cos(a) * rr, y + s, sin(a) * rr), Vector3(s * 1.2, s, s * 1.2), rng)
	# The path's lamps, zigzagging up the side that faces the roof.
	var towards := -Vector3(c.x, 0, c.z).normalized()
	var side := Vector3(-towards.z, 0, towards.x)
	for k in 26:
		var t := k / 25.0
		var rr := lerpf(33.0, 7.0, t)
		var zig := sin(t * PI * 5.0) * lerpf(14.0, 4.0, t)
		var dirv := (towards * rr + side * zig)
		var p := c + dirv.normalized() * minf(dirv.length(), rr + 2.0)
		p.y = _profile_y(profile, Vector2(p.x - c.x, p.z - c.z).length()) + 1.2
		b.lamp(p, 0.55, Color(1.0, 0.82, 0.55) * 2.0)
	# The chapel on the top: white, a tiled roof, a small bell gable; floodlit white.
	var cp := c + Vector3(0, CHAPEL_TOP - 0.2, 0) + towards * 1.0
	b.mat = M_CHURCH
	b.extra = 1.6
	b.colour = Color(0.86, 0.85, 0.82, 1.0)
	var basis := Basis(Vector3.UP, atan2(towards.x, towards.z))
	b.box(cp + Vector3(0, 2.0, 0), Vector3(6.0, 4.0, 9.0), basis, "b", cp.y)
	b.box(cp + basis * Vector3(0, 5.0, 4.3), Vector3(2.2, 2.4, 0.6), basis, "b", cp.y)
	b.mat = M_TILE
	b.extra = 1.0
	b.colour = Color(0.5, 0.26, 0.16, 1.0)
	for s: float in [-1.0, 1.0]:
		b.quad(cp + basis * Vector3(0, 5.4, -4.7), cp + basis * Vector3(0, 5.4, 4.7), cp + basis * Vector3(s * 3.3, 3.9,
				4.7), cp + basis * Vector3(s * 3.3, 3.9, -4.7), (basis * Vector3(s * 0.6, 1.0, 0)).normalized(),
				Vector2(0, 0), Vector2(9, 0), Vector2(9, 1), Vector2(0, 1))
	# A lit terrace and its building a little down the slope.
	var rp := c + towards * 8.0
	rp.y = _profile_y(profile, 8.0)
	b.mat = M_WALL
	b.colour = Color(0.82, 0.8, 0.74, 1.0)
	b.custom = Color(2.4, 2.8, 0.37, 0.0)
	b.box(rp + Vector3(0, 1.6, 0), Vector3(10.0, 3.2, 5.0), basis, "b", rp.y)
	b.custom = Color(0, 0, 0, 0)
	for k in 10:
		b.lamp(rp + basis * Vector3(lerpf(-5.0, 5.0, k / 9.0), 2.9, 3.0), 0.22, Color(1.0, 0.75, 0.45) * 2.0)


static func _profile_y(profile: Array, r: float) -> float:
	for i in profile.size() - 1:
		var a := float(profile[i][0])
		var e := float(profile[i + 1][0])
		if r >= a and r <= e:
			return lerpf(float(profile[i][1]), float(profile[i + 1][1]), (r - a) / (e - a))
	return float(profile[-1][1])


## The hills round the basin, on the horizon past the city; its lights climbing them, thinning towards the tops.
static func _far_hills(b: Builder, rng: RandomNumberGenerator) -> void:
	var steps := 180
	var dist := 166.0
	var prev_lo := Vector3.ZERO
	var prev_hi := Vector3.ZERO
	var tops: Array[float] = []
	for i in steps + 1:
		var az := -180.0 + 360.0 * i / steps
		var h := 6.0 + 16.0 * _n1(az / 23.0 + 50.0, 21) + 8.0 * _n1(az / 9.0 + 50.0, 23)
		# Lower behind the citadel (it stands against the sky) and where the sea would be.
		h *= 1.0 - 0.75 * (1.0 - smoothstep(10.0, 30.0, absf(az - CITADEL_AZ)))
		tops.append(h)
		var dirv := dir_of(az)
		var lo := dirv * dist + Vector3(0, -12.0, 0)
		var hi := dirv * dist + Vector3(0, -12.0 + h, 0)
		if i > 0:
			b.mat = M_FOLIAGE
			b.extra = 0.0
			b.colour = Color(0.035, 0.04, 0.045, 1.0)
			b.quad(prev_lo, lo, hi, prev_hi, (-dirv + Vector3.UP * 0.3).normalized())
		prev_lo = lo
		prev_hi = hi
	# Their lights: many, warm and a few white, denser low down; small (a few pixels), never in the citadel's sky.
	for k in 1100:
		var az := rng.randf_range(-180.0, 180.0)
		var i := clampi(int((az + 180.0) / 360.0 * steps), 0, steps)
		var top := tops[i]
		var f := pow(rng.randf(), 1.7)
		var y := -12.0 + top * f * 0.92
		if absf(az - CITADEL_AZ) < 32.0:
			continue
		var p := dir_of(az) * (dist - 1.0) + Vector3(0, y, 0)
		var warm := rng.randf() < 0.78
		var col := (Color(1.0, 0.66, 0.34) if warm else Color(0.9, 0.92, 1.0)) * rng.randf_range(0.7, 1.6)
		b.lamp(p, 0.42, col)
