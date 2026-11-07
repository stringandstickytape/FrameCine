extends RefCounted

## The builders' plain default seats (docs/environments.md, "The builders"): what a builder draws in its seat slots
## when the room has no seats system. Each is one mesh, its floor point under the seated eyes at the origin, facing
## -Z, two materials (the seat's cover and its frame). Never baked (instanced), so rounded boxes are fine. Static.
##
##   MODELS                       folding, director, club, plush, cushion
##   mesh(model, cover, frame) -> ArrayMesh
##   boxes(model) -> [[centre, size, tilt_deg]]   its physics boxes, in its own frame

const RoomMesh := preload("res://scripts/env/room_mesh.gd")

const MODELS: Array[String] = ["folding", "director", "club", "plush", "cushion"]


static func mesh(model: String, cover: Material, frame: Material) -> ArrayMesh:
	var b := RoomMesh.new()
	match model:
		"folding":
			# A slatted wooden seat and back on a folding steel frame.
			b.surface(cover)
			for i in 4:
				b.box(Vector3(0.0, 0.45, -0.24 + i * 0.1), Vector3(0.42, 0.025, 0.085), Basis(), [RoomMesh.DOWN])
			var back := Basis(Vector3.RIGHT, deg_to_rad(-8.0))
			for i in 2:
				b.box(Vector3(0.0, 0.66 + i * 0.13, 0.12 + i * 0.02), Vector3(0.42, 0.09, 0.022), back)
			b.surface(frame)
			for s: float in [-1.0, 1.0]:
				var x := s * 0.22
				_rod(b, Vector3(x, 0.0, -0.28), Vector3(x, 0.45, 0.1))
				_rod(b, Vector3(x, 0.0, 0.14), Vector3(x, 0.9, 0.16))
				_rod(b, Vector3(x, 0.45, -0.28), Vector3(x, 0.45, 0.12))
			_rod(b, Vector3(-0.22, 0.08, 0.14), Vector3(0.22, 0.08, 0.14))
		"director":
			# Canvas seat and back slung on a wooden frame with arms, crossed legs at the sides.
			b.surface(cover)
			b.box(Vector3(0.0, 0.46, -0.08), Vector3(0.46, 0.02, 0.4))
			b.box(Vector3(0.0, 0.8, 0.13), Vector3(0.5, 0.2, 0.015))
			b.surface(frame)
			for s: float in [-1.0, 1.0]:
				var x := s * 0.26
				_rod(b, Vector3(x, 0.0, -0.28), Vector3(x, 0.46, 0.12), 0.035)
				_rod(b, Vector3(x, 0.0, 0.12), Vector3(x, 0.46, -0.28), 0.035)
				_rod(b, Vector3(x, 0.66, -0.28), Vector3(x, 0.66, 0.12), 0.04)
				_rod(b, Vector3(x, 0.46, 0.12), Vector3(x, 0.92, 0.14), 0.035)
				_rod(b, Vector3(x, 0.46, -0.28), Vector3(x, 0.66, -0.28), 0.03)
		"club":
			# A deep upholstered armchair on short wooden feet.
			b.surface(cover)
			b.rounded_box(Vector3(0.0, 0.33, -0.05), Vector3(0.62, 0.16, 0.6), 0.05, Transform3D(), 1)
			b.rounded_box(Vector3(0.0, 0.25, -0.02), Vector3(0.84, 0.26, 0.74), 0.05, Transform3D(), 1, Vector3i.ZERO,
					0.0, [RoomMesh.DOWN])
			b.rounded_box(Vector3(0.0, 0.62, 0.28), Vector3(0.84, 0.6, 0.18), 0.07,
					Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-10.0)), Vector3.ZERO), 1)
			for s: float in [-1.0, 1.0]:
				b.rounded_box(Vector3(s * 0.36, 0.5, -0.04), Vector3(0.14, 0.24, 0.72), 0.06, Transform3D(), 1)
			b.surface(frame)
			for s: float in [-1.0, 1.0]:
				for z: float in [-0.34, 0.3]:
					b.box(Vector3(s * 0.36, 0.06, z), Vector3(0.06, 0.12, 0.06), Basis(), [RoomMesh.DOWN])
		"plush":
			# A single plush seat with arms, its back curved round the sitter.
			b.surface(cover)
			b.rounded_box(Vector3(0.0, 0.42, -0.07), Vector3(0.52, 0.13, 0.5), 0.045, Transform3D(), 1)
			b.rounded_box(Vector3(0.0, 0.36, 0.0), Vector3(0.54, 0.72, 0.1), 0.04,
					Transform3D(Basis(Vector3.RIGHT, deg_to_rad(13.0)), Vector3(0.0, 0.42, 0.2)), 1,
					Vector3i(3, 1, 0), -0.5)
			b.surface(frame)
			for s: float in [-1.0, 1.0]:
				b.rounded_box(Vector3(s * 0.3, 0.6, -0.04), Vector3(0.07, 0.05, 0.46), 0.015, Transform3D(), 1)
				b.box(Vector3(s * 0.3, 0.29, 0.06), Vector3(0.05, 0.58, 0.32), Basis(), [RoomMesh.DOWN])
			b.box(Vector3(0.0, 0.16, -0.02), Vector3(0.12, 0.3, 0.12), Basis(), [RoomMesh.DOWN, RoomMesh.UP])
		"cushion":
			# A floor cushion, and a second leaning behind it as a back rest.
			b.surface(cover)
			b.rounded_box(Vector3(0.0, 0.1, -0.05), Vector3(0.66, 0.2, 0.66), 0.08, Transform3D(), 2)
			b.rounded_box(Vector3(0.0, 0.0, 0.0), Vector3(0.6, 0.55, 0.18), 0.08,
					Transform3D(Basis(Vector3.RIGHT, deg_to_rad(18.0)), Vector3(0.0, 0.42, 0.32)), 2)
			b.surface(frame)
	return b.commit(false)


## Its physics boxes: [centre, size, tilt about X in degrees] in its own frame.
static func boxes(model: String) -> Array:
	match model:
		"folding", "director":
			return [[Vector3(0.0, 0.23, -0.08), Vector3(0.48, 0.46, 0.42), 0.0],
					[Vector3(0.0, 0.7, 0.14), Vector3(0.48, 0.42, 0.06), -8.0]]
		"club":
			return [[Vector3(0.0, 0.2, -0.04), Vector3(0.84, 0.4, 0.74), 0.0],
					[Vector3(0.0, 0.62, 0.28), Vector3(0.84, 0.6, 0.18), -10.0]]
		"plush":
			return [[Vector3(0.0, 0.24, -0.05), Vector3(0.55, 0.48, 0.52), 0.0],
					[Vector3(0.0, 0.77, 0.27), Vector3(0.52, 0.7, 0.14), 13.0]]
		"cushion":
			return [[Vector3(0.0, 0.1, -0.05), Vector3(0.66, 0.2, 0.66), 0.0]]
	return []


static func _rod(b: RoomMesh, a: Vector3, c: Vector3, t := 0.022) -> void:
	var dir := (c - a).normalized()
	var u := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var across := u.cross(dir).normalized()
	b.box((a + c) * 0.5, Vector3(t, t, a.distance_to(c)), Basis(across, dir.cross(across).normalized(), dir))
