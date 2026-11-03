extends "res://scripts/env/primitive_room.gd"

## A small home theatre (ideas #52): you sit on a sofa in a dark room, the screen on the front wall above a low cabinet,
## tower speakers either side, acoustic panels on the side walls, a rug and a coffee table, dim downlights in the
## ceiling (they dim with the room's level). The wooden floor can show the screen's reflection (#62). The surfaces are
## library materials (docs/materials.md) in the room's colours: plaster walls, a parquet floor, a woven rug, walnut,
## felt panels and speaker cloth, a herringbone sofa.

const MIN_CORNER := Vector3(-3.0, 0.0, -4.3)
const MAX_CORNER := Vector3(3.0, 2.8, 2.2)


func _build() -> void:
	reflection_floor_y = 0.0
	add_shell("Room", MIN_CORNER, MAX_CORNER, textured("smooth_plaster", Color(0.16, 0.17, 0.22), 1.0, 0.3))
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(MAX_CORNER.x - MIN_CORNER.x, MAX_CORNER.z - MIN_CORNER.z)
	add_mesh("Floor", floor_mesh, Transform3D(Basis(), Vector3(0, 0.001, (MIN_CORNER.z + MAX_CORNER.z) * 0.5)),
			textured("herringbone_parquet", Color(0.2, 0.13, 0.08), 1.0, 0.0, {"tiling": 2.4}))
	add_box("Rug", Vector3(2.6, 0.01, 1.8), Vector3(0, 0.006, -1.3),
			textured("woven_carpet", Color(0.3, 0.1, 0.09), 1.0, 0.0))

	# Front wall: cabinet, centre speaker, towers (speaker cloth on their fronts and sides).
	var a := get_screen_anchor().origin
	var black := material(Color(0.04, 0.04, 0.045), 0.8, 0.0)
	var cloth := textured("felt", Color(0.04, 0.04, 0.045), 0.8, 0.0, {"tiling": 0.3})
	add_box("Cabinet", Vector3(2.4, 0.5, 0.45), Vector3(0, 0.25, MIN_CORNER.z + 0.25),
			textured("walnut_veneer", Color(0.12, 0.08, 0.06), 1.0, 0.0))
	add_box("CentreSpeaker", Vector3(0.6, 0.18, 0.25), Vector3(0, 0.6, MIN_CORNER.z + 0.3), cloth)
	for side in [-1.0, 1.0]:
		add_box("Tower", Vector3(0.28, 1.1, 0.35), Vector3(side * 1.75, 0.55, MIN_CORNER.z + 0.45), cloth)
	# A thin frame behind the screen.
	add_box("ScreenFrame", Vector3(2.8, 1.65, 0.04), Vector3(a.x, a.y, MIN_CORNER.z + 0.03), black)

	# Side walls: acoustic panels.
	var panel := BoxMesh.new()
	panel.size = Vector3(0.05, 1.1, 0.8)
	var panels: Array[Transform3D] = []
	for side in [-1.0, 1.0]:
		for z in [-3.0, -1.6, -0.2, 1.2]:
			panels.append(Transform3D(Basis(), Vector3(side * (MAX_CORNER.x - 0.03), 1.45, z)))
	add_multimesh("Panels", panel, panels, textured("felt", Color(0.24, 0.2, 0.17), 1.0, 0.0))

	# The sofa you sit on, and a coffee table.
	var sofa := textured("herringbone_upholstery", Color(0.26, 0.24, 0.22), 1.0, 0.0)
	add_box("SofaSeat", Vector3(2.2, 0.42, 0.85), Vector3(0, 0.21, 0.1), sofa)
	add_box("SofaBack", Vector3(2.2, 0.55, 0.22), Vector3(0, 0.7, 0.62), sofa)
	for side in [-1.0, 1.0]:
		add_box("SofaArm", Vector3(0.2, 0.62, 0.95), Vector3(side * 1.2, 0.31, 0.15), sofa)
	seats = [Vector3(-0.7, 0, 0), Vector3(0, 0, 0), Vector3(0.7, 0, 0)]
	add_box("Table", Vector3(1.1, 0.06, 0.55), Vector3(0, 0.4, -1.25),
			textured("walnut_veneer", Color(0.14, 0.09, 0.06), 1.0, 0.0))

	# Downlights: bright discs that follow the room's level (env_unlit: albedo times the level).
	var light := CylinderMesh.new()
	light.top_radius = 0.07
	light.bottom_radius = 0.07
	light.height = 0.01
	var lights: Array[Transform3D] = []
	for x in [-1.8, 1.8]:
		for z in [-2.8, -0.4, 1.6]:
			lights.append(Transform3D(Basis(), Vector3(x, MAX_CORNER.y - 0.006, z)))
	add_multimesh("Downlights", light, lights, material(Color(6.0, 5.2, 4.2), 0.0, 0.0))
