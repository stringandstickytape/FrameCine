extends "res://environments/vr_environment.gd"

## A dark stadium-seated auditorium. The viewer sits in the middle of row 0 at the origin; rows in front step down
## (so seat backs never cover the screen), rows behind step up. Everything is unlit (env_unlit.gdshader, lit only by
## the fake screen spill) and built here in 6 draw calls: room shell, tiers (MultiMesh), seats (MultiMesh), stage,
## the curtains either side of the front wall (MultiMesh), and the black masking border that follows the screen.
## Library materials (docs/materials.md) in the room's colours: fabric-lined walls, carpeted tiers, velvet seats and
## pleated velvet curtains, a wooden stage.

const ENV_SHADER := preload("res://shaders/env_unlit.gdshader")
const MaterialLibrary := preload("res://scripts/env/material_library.gd")

const ROOM_MIN := Vector3(-9, -3, -14)
const ROOM_MAX := Vector3(9, 9, 6)
const ROW_DEPTH := 1.3
const ROW_RISE := 0.35
const ROWS_FRONT := 7
const ROWS_BACK := 3
const SEAT_PITCH := 0.62
const AISLE_X := 7.6
const CURTAIN_WIDTH := 2.2

var _border: MeshInstance3D


func _ready() -> void:
	var walls := _textured("felt", Color(0.2, 0.17, 0.2), 1.0, 0.2)
	var room := BoxMesh.new()
	room.size = ROOM_MAX - ROOM_MIN
	room.flip_faces = true
	room.material = walls
	_add_mesh("Room", room, Transform3D(Basis(), (ROOM_MIN + ROOM_MAX) * 0.5))

	# Tiers: one block per row, from the pit floor up to the row's floor.
	var tier_mesh := BoxMesh.new()
	tier_mesh.size = Vector3.ONE
	tier_mesh.material = _textured("plush_carpet", Color(0.12, 0.1, 0.11), 1.0, 0.0)
	var tiers: Array[Transform3D] = []
	for row in range(-ROWS_BACK, ROWS_FRONT + 1):
		var floor_y := -ROW_RISE * row
		var height := floor_y - ROOM_MIN.y
		var z := -ROW_DEPTH * row
		tiers.append(Transform3D(Basis.from_scale(Vector3(ROOM_MAX.x - ROOM_MIN.x, height, ROW_DEPTH)),
				Vector3(0, ROOM_MIN.y + height * 0.5, z)))
	_add_multimesh("Tiers", tier_mesh, tiers)

	# Seats: a block per seat (seat + back), towards the back of each row; none where the viewer sits.
	var seat_mesh := BoxMesh.new()
	seat_mesh.size = Vector3(0.52, 0.95, 0.55)
	seat_mesh.material = _textured("velvet", Color(0.42, 0.06, 0.08), 1.0, 0.0)
	var seats: Array[Transform3D] = []
	for row in range(-ROWS_BACK, ROWS_FRONT + 1):
		var floor_y := -ROW_RISE * row
		var x := -AISLE_X + SEAT_PITCH * 0.5
		while x < AISLE_X:
			if not (row == 0 and absf(x) < 0.4):
				seats.append(Transform3D(Basis(), Vector3(x, floor_y + 0.475, -ROW_DEPTH * row + 0.3)))
			x += SEAT_PITCH
	_add_multimesh("Seats", seat_mesh, seats)

	var stage := BoxMesh.new()
	stage.size = Vector3(ROOM_MAX.x - ROOM_MIN.x, 0.9, 1.6)
	stage.material = _textured("red_hardwood", Color(0.16, 0.13, 0.12), 1.0, 0.0)
	_add_mesh("Stage", stage, Transform3D(Basis(), Vector3(0, ROOM_MIN.y + 0.45, ROOM_MIN.z + 0.8)))

	# Curtains on the front wall either side, beyond the widest screen: pleated velvet (folds from the shader).
	var curtain := BoxMesh.new()
	curtain.size = Vector3(CURTAIN_WIDTH, ROOM_MAX.y - ROOM_MIN.y - 0.9, 0.12)
	curtain.material = _textured("velvet", Color(0.3, 0.04, 0.06), 1.0, 0.2, {"pleats": 3.0, "pleat_depth": 0.6})
	var curtains: Array[Transform3D] = []
	for side in [-1.0, 1.0]:
		curtains.append(Transform3D(Basis(), Vector3(side * (ROOM_MAX.x - CURTAIN_WIDTH * 0.5),
				ROOM_MIN.y + 0.9 + curtain.size.y * 0.5, ROOM_MIN.z + 0.08)))
	_add_multimesh("Curtains", curtain, curtains)

	var border := QuadMesh.new()
	border.material = _material(Color(0.0, 0.0, 0.0), 0.0, 0.0)
	_border = _add_mesh("ScreenBorder", border, get_screen_anchor())


## Seat choice (scripts/comfort/seat_choice.gd, ideas #19): the floor point under a seated viewer's eyes for every seat,
## the viewer's own spot included (row 0, middle).
func get_seats() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for row in range(-ROWS_BACK, ROWS_FRONT + 1):
		var x := -AISLE_X + SEAT_PITCH * 0.5
		while x < AISLE_X:
			out.append(Vector3(0.0 if row == 0 and absf(x) < 0.4 else x, -ROW_RISE * row, -ROW_DEPTH * row))
			x += SEAT_PITCH
	return out


func on_screen_changed(screen_transform: Transform3D, size: Vector2) -> void:
	if _border == null:
		return
	(_border.mesh as QuadMesh).size = size + Vector2(0.5, 0.5)
	_border.transform = screen_transform.translated_local(Vector3(0, 0, -0.03))


func _material(albedo: Color, spill: float, floor_darkening: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ENV_SHADER
	m.set_shader_parameter("albedo", albedo)
	m.set_shader_parameter("spill", spill)
	m.set_shader_parameter("floor_darkening", floor_darkening)
	return m


## A library material in the room's light (as primitive_room.gd's textured()); _material() if the library lacks it.
func _textured(id: String, colour: Color, spill: float, floor_darkening: float, options := {}) -> Material:
	var o := options.duplicate()
	o.merge({"colour": colour, "spill": spill, "floor_darkening": floor_darkening})
	var m := MaterialLibrary.get_material(id, o)
	return m if m != null else _material(colour, spill, floor_darkening)


func _add_mesh(node_name: String, mesh: Mesh, xform: Transform3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.transform = xform
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _add_multimesh(node_name: String, mesh: Mesh, xforms: Array[Transform3D]) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
