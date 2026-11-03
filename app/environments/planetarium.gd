extends "res://scripts/env/primitive_room.gd"

## A planetarium (ideas #52): a round room under a dark dome full of projected stars, a skyline silhouette around the
## dome's foot, a soft cove light, reclined seats in rows, and the star projector on its pedestal behind you. Flat
## video goes high on the dome ahead; 180 and 360 video replace the room anyway. Velvet seats and a carpeted floor
## (library materials, docs/materials.md).

const RADIUS := 9.0
const WALL := 2.4


## Spatial audio: a ring of speakers behind the dome's foot, 8 m round, the heights and the top one behind the dome
## overhead. A hard dome over a carpeted floor: a long, smooth reverb.
func get_sound_room() -> Dictionary:
	return {"box": AABB(Vector3(-RADIUS, 0, -RADIUS), Vector3(RADIUS * 2.0, WALL + RADIUS, RADIUS * 2.0)), "ring": true,
			"distance": 8.0, "reflect": [0.5, 0.5, 0.25, 0.6, 0.5, 0.5], "rt60": 1.2, "wet": 0.5}


func _build() -> void:
	var wall := CylinderMesh.new()
	wall.top_radius = RADIUS
	wall.bottom_radius = RADIUS
	wall.height = WALL
	wall.flip_faces = true
	wall.cap_top = false
	add_mesh("Wall", wall, Transform3D(Basis(), Vector3(0, WALL * 0.5, 0)), material(Color(0.1, 0.1, 0.14), 1.0, 0.3))
	var dome := SphereMesh.new()
	dome.radius = RADIUS
	dome.height = RADIUS
	dome.is_hemisphere = true
	dome.flip_faces = true
	add_mesh("Dome", dome, Transform3D(Basis(), Vector3(0, WALL, 0)), material(Color(0.12, 0.13, 0.24), 0.8, 0.0))

	var star := SphereMesh.new()
	star.radius = 0.025
	star.height = 0.05
	star.radial_segments = 4
	star.rings = 2
	var stars: Array[Transform3D] = []
	for p in sky_points(900, 0.08):
		stars.append(Transform3D(Basis(), Vector3(0, WALL, 0) + p * (RADIUS - 0.05)))
	add_multimesh("Stars", star, stars, glow(Color(0.8, 0.82, 0.9)))

	# Skyline silhouette: blocks of fixed, varied heights around the dome's foot.
	var block := BoxMesh.new()
	block.size = Vector3.ONE
	var blocks: Array[Transform3D] = []
	var n := 72
	for i in n:
		var a := TAU * i / n
		var h := 0.4 + 0.9 * absf(sin(i * 1.7)) * absf(cos(i * 0.6))
		var w := TAU * (RADIUS - 0.3) / n
		blocks.append(Transform3D(Basis(Vector3.UP, -a).scaled(Vector3(w * 1.05, h, 0.3)),
				Vector3(sin(a) * (RADIUS - 0.3), WALL + h * 0.5 - 0.05, -cos(a) * (RADIUS - 0.3))))
	add_multimesh("Skyline", block, blocks, material(Color(0.02, 0.02, 0.03), 0.0, 0.0))
	var cove := CylinderMesh.new()
	cove.top_radius = RADIUS - 0.35
	cove.bottom_radius = RADIUS - 0.35
	cove.height = 0.05
	cove.flip_faces = true
	cove.cap_top = false
	cove.cap_bottom = false
	add_mesh("Cove", cove, Transform3D(Basis(), Vector3(0, WALL - 0.1, 0)), material(Color(1.2, 1.6, 3.0), 0.0, 0.0))

	# Reclined seats in rows facing forward; none where you sit.
	var seat := BoxMesh.new()
	seat.size = Vector3(0.55, 0.12, 0.6)
	var back := BoxMesh.new()
	back.size = Vector3(0.55, 0.65, 0.1)
	var seat_xforms: Array[Transform3D] = []
	var backs: Array[Transform3D] = []
	var recline := Basis(Vector3.RIGHT, deg_to_rad(-55.0))
	for row in range(-2, 4):
		var z := 0.2 - row * 1.4
		var half := sqrt(maxf(RADIUS * RADIUS * 0.7 - z * z, 0.0))
		var x := -half
		while x < half:
			if not (row == 0 and absf(x) < 0.4):
				seat_xforms.append(Transform3D(Basis(), Vector3(x, 0.32, z)))
				backs.append(Transform3D(recline, Vector3(x, 0.52, z + 0.48)))
			seats.append(Vector3(x, 0.0, z))
			x += 0.65
	var upholstery := textured("velvet", Color(0.16, 0.18, 0.3), 1.0, 0.0)
	add_multimesh("Seats", seat, seat_xforms, upholstery)
	add_multimesh("SeatBacks", back, backs, upholstery)
	add_box("Floor", Vector3(RADIUS * 2.0, 0.02, RADIUS * 2.0), Vector3(0, 0.0, 0),
			textured("plush_carpet", Color(0.08, 0.08, 0.09), 1.0, 0.0))

	# The star projector behind.
	var dark := material(Color(0.12, 0.12, 0.13), 1.0, 0.0)
	var pedestal := CylinderMesh.new()
	pedestal.top_radius = 0.25
	pedestal.bottom_radius = 0.4
	pedestal.height = 1.2
	add_mesh("Pedestal", pedestal, Transform3D(Basis(), Vector3(0, 0.6, 4.2)), dark)
	var head := SphereMesh.new()
	head.radius = 0.45
	head.height = 0.9
	add_mesh("Projector", head, Transform3D(Basis(), Vector3(0, 1.55, 4.2)), dark)
