extends "res://scripts/env/primitive_room.gd"

## A geodesic dome at dusk (ideas #52): an open frame of struts overhead on a wide plain, the sky fading from a warm
## horizon to night, the first stars, a low platform you sit on (wooden planks and a steel rail: library materials,
## docs/materials.md). The screen hangs inside the frame.

const RADIUS := 16.0
const SKY_RADIUS := 120.0


func _build() -> void:
	var ground := PlaneMesh.new()
	ground.size = Vector2(260, 260)
	add_mesh("Ground", ground, Transform3D(), material(Color(0.3, 0.24, 0.18), 0.4, 0.0))
	var sky := SphereMesh.new()
	sky.radius = SKY_RADIUS
	sky.height = SKY_RADIUS * 2.0
	sky.flip_faces = true
	add_mesh("Sky", sky, Transform3D(), material(Color(0.6, 0.6, 1.2), 0.0, 0.0))
	# Horizon glow: two stacked bands, warm below, paler above.
	for band: Array in [[6.0, 3.0, Color(3.0, 1.4, 0.8)], [10.0, 11.0, Color(1.6, 1.1, 1.2)]]:
		var c := CylinderMesh.new()
		c.top_radius = SKY_RADIUS - 2.0
		c.bottom_radius = SKY_RADIUS - 2.0
		c.height = band[0]
		c.flip_faces = true
		c.cap_top = false
		c.cap_bottom = false
		add_mesh("HorizonBand", c, Transform3D(Basis(), Vector3(0, band[1], 0)), material(band[2], 0.0, 0.0))
	var star := SphereMesh.new()
	star.radius = 0.3
	star.height = 0.6
	star.radial_segments = 4
	star.rings = 2
	var stars: Array[Transform3D] = []
	for p in sky_points(200, 0.45):
		stars.append(Transform3D(Basis(), p * (SKY_RADIUS - 4.0)))
	add_multimesh("Stars", star, stars, glow(Color(0.8, 0.8, 0.9)))

	# The geodesic frame: an icosahedron subdivided once, the edges above the ground as struts.
	var strut := BoxMesh.new()
	strut.size = Vector3(0.12, 0.12, 1.0)
	var struts: Array[Transform3D] = []
	for e in geodesic_edges(RADIUS):
		var a: Vector3 = e[0]
		var b: Vector3 = e[1]
		if a.y < -0.5 or b.y < -0.5:
			continue
		var mid := (a + b) * 0.5
		var length := a.distance_to(b)
		var basis := Basis.looking_at((b - a).normalized(), Vector3.UP if absf((b - a).normalized().y) < 0.99 else Vector3.RIGHT)
		struts.append(Transform3D(basis.scaled_local(Vector3(1, 1, length)), mid))
	add_multimesh("Struts", strut, struts, material(Color(0.55, 0.55, 0.6), 1.0, 0.0))

	# A low platform with a rail in front; spots to stand on it.
	seats = [Vector3(-2, 0.3, 0.5), Vector3(0, 0.3, 0.5), Vector3(2, 0.3, 0.5), Vector3(0, 0.3, 2.0)]
	add_box("Platform", Vector3(6, 0.3, 4), Vector3(0, 0.15, 0.5),
			textured("rustic_planks", Color(0.25, 0.2, 0.16), 1.0, 0.0))
	add_box("Rail", Vector3(5, 0.06, 0.06), Vector3(0, 0.95, -1.4),
			textured("brushed_steel", Color(0.4, 0.4, 0.42), 1.0, 0.0))


## Edges [a, b] of an icosahedron subdivided once, on a sphere of radius r (each edge once).
static func geodesic_edges(r: float) -> Array:
	var t := (1.0 + sqrt(5.0)) * 0.5
	var v: Array[Vector3] = [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
			Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
			Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var faces := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2],
			[10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11],
			[6, 2, 10], [8, 6, 7], [9, 8, 1]]
	var seen := {}
	var out: Array = []
	for f: Array in faces:
		var a := v[f[0]].normalized()
		var b := v[f[1]].normalized()
		var c := v[f[2]].normalized()
		var ab := (a + b).normalized()
		var bc := (b + c).normalized()
		var ca := (c + a).normalized()
		for e: Array in [[a, ab], [ab, b], [b, bc], [bc, c], [c, ca], [ca, a], [ab, bc], [bc, ca], [ca, ab]]:
			var p: Vector3 = e[0] * r
			var q: Vector3 = e[1] * r
			var key := "%s|%s" % [p.snapped(Vector3.ONE * 0.01), q.snapped(Vector3.ONE * 0.01)]
			var rkey := "%s|%s" % [q.snapped(Vector3.ONE * 0.01), p.snapped(Vector3.ONE * 0.01)]
			if seen.has(key) or seen.has(rkey):
				continue
			seen[key] = true
			out.append([p, q])
	return out
