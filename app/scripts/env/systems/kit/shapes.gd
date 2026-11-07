extends RefCounted

## Geometry for the builders and the kit (docs/environments.md, "The builders"), drawn into a RoomMesh
## (scripts/env/room_mesh.gd) in the room's frame. Every shape is made of faces and strips, so each is a lightmap chart
## and a static mesh of them can be baked. Static; preload to use.
##
##   lathe(b, profile, centre, sides, basis, arc)   a profile [Vector2(radius, height)] turned round the local Y axis
##   cylinder(b, base, radius, height, sides, basis, caps)
##   arch(b, centre, r_in, r_out, depth, segments, basis, from, to)   a ring's part (a semicircle by default)
##   dome(b, centre, radius, rings, sides, inside, from_lat)   a hemisphere (seen from inside or out)
##   leaf(b, at, along, across, normal)   a double-sided leaf (two triangles a side)
##   quad(b, centre, half_u, half_v, normal)

const RoomMesh := preload("res://scripts/env/room_mesh.gd")


## The profile's points, from bottom to top, turned round the axis: one strip a step of the profile (a chart each).
## arc: the turn in radians (TAU: all round). Smooth normals round the turn, the profile's own slope in them.
static func lathe(b: RoomMesh, profile: Array, centre: Vector3, sides := 12, basis := Basis(), arc := TAU,
		start := 0.0) -> void:
	var closed := is_equal_approx(arc, TAU)
	var count := sides + 1
	for i in profile.size() - 1:
		var p0: Vector2 = profile[i]
		var p1: Vector2 = profile[i + 1]
		if p0.distance_to(p1) < 0.0001:
			continue
		var a := PackedVector3Array()
		var c := PackedVector3Array()
		var ns := PackedVector3Array()
		var slope := Vector2(p1.y - p0.y, -(p1.x - p0.x)).normalized()
		for k in count:
			var t := start + arc * float(k if not closed or k < sides else 0) / sides
			var dir := Vector3(sin(t), 0.0, cos(t))
			a.append(centre + basis * (dir * p0.x + Vector3.UP * p0.y))
			c.append(centre + basis * (dir * p1.x + Vector3.UP * p1.y))
			ns.append((basis * (dir * slope.x + Vector3.UP * slope.y)).normalized())
		b.strip(a, c, ns)


static func cylinder(b: RoomMesh, base: Vector3, radius: float, height: float, sides := 12, basis := Basis(),
		caps := true) -> void:
	lathe(b, [Vector2(radius, 0.0), Vector2(radius, height)], base, sides, basis)
	if caps:
		for top: bool in [false, true]:
			var corners: Array = []
			for k in sides:
				var t := TAU * k / sides
				corners.append(base + basis * Vector3(sin(t) * radius, height if top else 0.0, cos(t) * radius))
			b.face(corners, (basis * (Vector3.UP if top else Vector3.DOWN)).normalized())


## A ring's part in the local XY plane (an arch over local Y), depth along local Z: the face either side as a strip
## between the inner and outer arcs, the soffit (inside) and the extrados (outside). Angles from local +X.
static func arch(b: RoomMesh, centre: Vector3, r_in: float, r_out: float, depth: float, segments := 12,
		basis := Basis(), from := 0.0, to := PI, sides: Array = ["front", "back", "inner", "outer"]) -> void:
	var half := depth * 0.5
	for side: String in sides:
		var a := PackedVector3Array()
		var c := PackedVector3Array()
		var ns := PackedVector3Array()
		for k in segments + 1:
			var t := lerpf(from, to, float(k) / segments)
			var dir := Vector3(cos(t), sin(t), 0.0)
			match side:
				"front", "back":
					var z := half if side == "front" else -half
					a.append(centre + basis * (dir * r_in + Vector3(0, 0, z)))
					c.append(centre + basis * (dir * r_out + Vector3(0, 0, z)))
					ns.append((basis * Vector3(0, 0, 1.0 if side == "front" else -1.0)).normalized())
				"inner", "outer":
					var r := r_in if side == "inner" else r_out
					a.append(centre + basis * (dir * r + Vector3(0, 0, half)))
					c.append(centre + basis * (dir * r + Vector3(0, 0, -half)))
					ns.append((basis * (-dir if side == "inner" else dir)).normalized())
		b.strip(a, c, ns)


## A dome over centre (its base ring at centre's height): rings of latitude from from_lat (0: the base) to the top.
## inside: the faces look in (a hall's dome seen from its floor).
static func dome(b: RoomMesh, centre: Vector3, radius: float, rings := 8, sides := 24, inside := true,
		from_lat := 0.0, to_lat := PI * 0.5) -> void:
	var profile: Array = []
	for i in rings + 1:
		var lat := lerpf(from_lat, to_lat, float(i) / rings)
		profile.append(Vector2(cos(lat) * radius, sin(lat) * radius))
	if inside:
		# The profile's slope gives an outward normal; reversed, the strips face in.
		profile.reverse()
	lathe(b, profile, centre, sides)


## One leaf: a diamond along `along` (its length) and `across` (its half width), both sides.
static func leaf(b: RoomMesh, at: Vector3, along: Vector3, across: Vector3, normal: Vector3) -> void:
	var tip := at + along
	var mid := at + along * 0.45
	for s: float in [1.0, -1.0]:
		b.face([at, mid + across, tip, mid - across], normal * s)


static func quad(b: RoomMesh, centre: Vector3, half_u: Vector3, half_v: Vector3, normal: Vector3) -> void:
	b.face([centre - half_u - half_v, centre + half_u - half_v, centre + half_u + half_v, centre - half_u + half_v],
			normal)


## A box along a line from a to c (a beam, a rail, a pipe), `size` across it (x) and up (y).
static func beam(b: RoomMesh, a: Vector3, c: Vector3, size: Vector2, up := Vector3.UP) -> void:
	var dir := (c - a).normalized()
	var u := up if absf(dir.dot(up)) < 0.99 else Vector3.RIGHT
	var across := u.cross(dir).normalized()
	var up2 := dir.cross(across).normalized()
	b.box((a + c) * 0.5, Vector3(size.x, size.y, a.distance_to(c)), Basis(across, up2, dir))


## A flat wall with rectangular holes (windows, doors, a fireplace's opening): origin is its bottom corner, u its
## direction along the wall, up is up; holes are Rect2s in (along, up) metres. Faces in bands between the holes'
## edges, each a chart.
static func wall(b: RoomMesh, origin: Vector3, u: Vector3, normal: Vector3, length: float, height: float,
		holes: Array = []) -> void:
	var xs: Array[float] = [0.0, length]
	for h: Rect2 in holes:
		for x: float in [h.position.x, h.end.x]:
			if x > 0.0 and x < length and not (x in xs):
				xs.append(x)
	xs.sort()
	for i in xs.size() - 1:
		var x0 := xs[i]
		var x1 := xs[i + 1]
		var mid := (x0 + x1) * 0.5
		var cuts: Array = []
		for h: Rect2 in holes:
			if h.position.x < mid and h.end.x > mid:
				cuts.append(h)
		cuts.sort_custom(func(a: Rect2, c: Rect2) -> bool: return a.position.y < c.position.y)
		var y := 0.0
		for h: Rect2 in cuts:
			if h.position.y > y:
				_wall_face(b, origin, u, normal, x0, x1, y, minf(h.position.y, height))
			y = maxf(y, h.end.y)
		if y < height:
			_wall_face(b, origin, u, normal, x0, x1, y, height)


static func _wall_face(b: RoomMesh, origin: Vector3, u: Vector3, normal: Vector3, x0: float, x1: float, y0: float,
		y1: float) -> void:
	if x1 - x0 < 0.001 or y1 - y0 < 0.001:
		return
	b.face([origin + u * x0 + Vector3.UP * y0, origin + u * x1 + Vector3.UP * y0, origin + u * x1 + Vector3.UP * y1,
			origin + u * x0 + Vector3.UP * y1], normal)
