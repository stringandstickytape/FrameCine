extends RefCounted

## The object library's built-in objects (object_library.gd, docs/assistant.md "Objects"): a few simple ones made here
## from the engine's primitive meshes, so nothing anyone else made (the showrooms ship .glb copies written from these,
## by tools/showrooms.gd). Each is
## built as nodes (one MeshInstance3D per part, named), written as a .glb by the library and read back like any
## imported object. The front faces +Z; a wall object's back is at z = 0, a floor object's bottom at y = 0.
##
## Rooms are made of objects (docs/decisions.md): the primitives every shape of a room is a placement of (a 1 m box,
## sphere, cylinder and plane, centred; a placement's scale is their size, room_schema.gd build_form()) and the
## generators, whose node is made per placement from its options (a text's words, a particles area: no .glb).
##
##   ENTRIES: [{id, name, tags, mount, primitive?, generator?, widget?, widget_options?}]
##   build(id) -> Node3D (not in a tree) or null (a generator)

const ENTRIES := [
	# The shapes a room document sends (type box, sphere, cylinder, plane) are placements of these: one part each, named
	# after the shape, grey as an uncoloured part shows.
	{"id": "box", "name": "Box", "tags": ["shape"], "mount": "free", "primitive": true},
	{"id": "sphere", "name": "Sphere", "tags": ["shape"], "mount": "free", "primitive": true},
	{"id": "cylinder", "name": "Cylinder", "tags": ["shape"], "mount": "free", "primitive": true},
	{"id": "plane", "name": "Plane", "tags": ["shape"], "mount": "free", "primitive": true},
	# Made per placement: a text's words (text, text_options; a line 0.1 m high at scale 1), a particles area
	# (particles; 1 m a side at scale 1).
	{"id": "text", "name": "Text", "tags": ["text"], "mount": "free", "generator": "text"},
	{"id": "particles", "name": "Particles", "tags": ["effect"], "mount": "free", "generator": "particles"},
	{"id": "picture_frame", "name": "Picture frame", "tags": ["wall", "picture"], "mount": "wall"},
	{"id": "wall_shelf", "name": "Wall shelf", "tags": ["wall", "furniture"], "mount": "wall"},
	{"id": "pot_plant", "name": "Pot plant", "tags": ["floor", "plant"], "mount": "floor"},
	# The room's clock widget (room_widget.gd) draws the hands on the face: no background of its own.
	{"id": "wall_clock", "name": "Wall clock", "tags": ["wall", "clock"], "mount": "wall", "widget": "clock",
			"widget_options": {"style": "analog", "color": "#202020", "background": "#00000000"}},
]


static func build(id: String) -> Node3D:
	match id:
		"box", "sphere", "cylinder", "plane":
			return _primitive(id)
		"picture_frame":
			return _picture_frame()
		"wall_shelf":
			return _shelf()
		"pot_plant":
			return _pot_plant()
		"wall_clock":
			return _clock()
	return null


## Whether an id is one of the primitives or the generators.
static func is_primitive(id: String) -> bool:
	return ENTRIES.any(func(e: Dictionary) -> bool: return e["id"] == id and e.get("primitive", false))


static func generator_of(id: String) -> String:
	for e: Dictionary in ENTRIES:
		if e["id"] == id:
			return str(e.get("generator", ""))
	return ""


## A primitive's one part: "Box", "Sphere", "Cylinder", "Plane" (as "<placed>/Box" in a recolour).
static func part_name(kind: String) -> String:
	return kind.capitalize()


## A primitive at 1 m, centred, its one part grey.
static func _primitive(id: String) -> Node3D:
	var root := _root(part_name(id))
	_part(root, part_name(id), "#b0b0b0", [[shape_mesh(id, Vector3.ONE), Transform3D()]])
	return root


## A shape's mesh as a room builds it (assistant_room.gd _part): box size [w, h, d]; sphere size.x across; cylinder
## size.x across and size.y tall, round faces up and down; plane size.x by size.z, facing up.
static func shape_mesh(kind: String, size: Vector3) -> PrimitiveMesh:
	match kind:
		"box":
			var b := BoxMesh.new()
			b.size = size
			return b
		"sphere":
			var sp := SphereMesh.new()
			sp.radius = size.x * 0.5
			sp.height = size.x
			return sp
		"cylinder":
			var cy := CylinderMesh.new()
			cy.top_radius = size.x * 0.5
			cy.bottom_radius = cy.top_radius
			cy.height = size.y
			return cy
		"plane":
			var pl := PlaneMesh.new()
			pl.size = Vector2(size.x, size.z)
			return pl
	return null


## A dark wooden frame (0.5 x 0.4 m), a pale mount, and the picture: a quad that takes a texture whole.
static func _picture_frame() -> Node3D:
	var root := _root("PictureFrame")
	var w := 0.5
	var h := 0.4
	var bar := 0.045
	var d := 0.03
	_part(root, "Frame", "#3b2a1e", [
		[_box(Vector3(w, bar, d)), Transform3D(Basis(), Vector3(0, (h - bar) / 2.0, d / 2.0))],
		[_box(Vector3(w, bar, d)), Transform3D(Basis(), Vector3(0, -(h - bar) / 2.0, d / 2.0))],
		[_box(Vector3(bar, h - 2.0 * bar, d)), Transform3D(Basis(), Vector3(-(w - bar) / 2.0, 0, d / 2.0))],
		[_box(Vector3(bar, h - 2.0 * bar, d)), Transform3D(Basis(), Vector3((w - bar) / 2.0, 0, d / 2.0))]])
	_part(root, "Mount", "#ece6da", [[_box(Vector3(w - 2.0 * bar, h - 2.0 * bar, 0.01)),
			Transform3D(Basis(), Vector3(0, 0, 0.012))]])
	var quad := QuadMesh.new()
	quad.size = Vector2(w - 2.0 * bar - 0.07, h - 2.0 * bar - 0.07)
	_part(root, "Picture", "#8fa3b5", [[quad, Transform3D(Basis(), Vector3(0, 0, 0.0175))]])
	return root


## A light oak board on two dark brackets, 0.8 m wide.
static func _shelf() -> Node3D:
	var root := _root("WallShelf")
	_part(root, "Board", "#c8a27a", [[_box(Vector3(0.8, 0.025, 0.22)), Transform3D(Basis(), Vector3(0, 0, 0.11))]])
	var pieces: Array = []
	for x: float in [-0.28, 0.28]:
		pieces.append([_box(Vector3(0.02, 0.16, 0.01)), Transform3D(Basis(), Vector3(x, -0.0925, 0.005))])
		pieces.append([_box(Vector3(0.02, 0.012, 0.17)), Transform3D(Basis(), Vector3(x, -0.0185, 0.095))])
	_part(root, "Brackets", "#2b2b2b", pieces)
	return root


## A terracotta pot with soil and a fan of long leaves, about 0.75 m tall.
static func _pot_plant() -> Node3D:
	var root := _root("PotPlant")
	var pot := CylinderMesh.new()
	pot.top_radius = 0.14
	pot.bottom_radius = 0.105
	pot.height = 0.3
	pot.radial_segments = 32
	pot.rings = 1
	_part(root, "Pot", "#b5653d", [[pot, Transform3D(Basis(), Vector3(0, 0.15, 0))]])
	var soil := CylinderMesh.new()
	soil.top_radius = 0.13
	soil.bottom_radius = 0.13
	soil.height = 0.01
	soil.radial_segments = 32
	soil.rings = 1
	_part(root, "Soil", "#3a2a1c", [[soil, Transform3D(Basis(), Vector3(0, 0.29, 0))]])
	var leaf := SphereMesh.new()
	leaf.radius = 0.5
	leaf.height = 1.0
	leaf.radial_segments = 12
	leaf.rings = 6
	var leaves: Array = []
	# An outer ring leaning out and a few taller ones in the middle: each a long, thin ellipsoid from the soil.
	for i in 7:
		leaves.append([leaf, _leaf(TAU * i / 7.0, deg_to_rad(38.0), 0.36, Vector3(0, 0.29, 0))])
	for i in 3:
		leaves.append([leaf, _leaf(TAU * i / 3.0 + 0.5, deg_to_rad(14.0), 0.46, Vector3(0, 0.29, 0))])
	_part(root, "Leaves", "#4f8a3c", leaves)
	return root


static func _leaf(yaw: float, lean: float, length: float, base: Vector3) -> Transform3D:
	var turn := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -lean)
	var basis := turn * Basis.from_scale(Vector3(0.075, length, 0.02))
	return Transform3D(basis, base + turn * Vector3(0, length * 0.5, 0))


## A round clock, 0.34 m across: a dark rim and a pale face; the clock widget draws the hands on it.
static func _clock() -> Node3D:
	var root := _root("WallClock")
	var to_front := Basis(Vector3.RIGHT, PI / 2.0)
	var rim := CylinderMesh.new()
	rim.top_radius = 0.17
	rim.bottom_radius = 0.17
	rim.height = 0.04
	rim.radial_segments = 48
	rim.rings = 1
	_part(root, "Rim", "#222222", [[rim, Transform3D(to_front, Vector3(0, 0, 0.02))]])
	var face := CylinderMesh.new()
	face.top_radius = 0.155
	face.bottom_radius = 0.155
	face.height = 0.004
	face.radial_segments = 48
	face.rings = 1
	_part(root, "Face", "#f4f1ea", [[face, Transform3D(to_front, Vector3(0, 0, 0.041))]])
	return root


static func _root(name: String) -> Node3D:
	var root := Node3D.new()
	root.name = name
	return root


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


## One part: the pieces ([PrimitiveMesh, Transform3D]) joined into one mesh with one colour, as a MeshInstance3D
## named `name` (the glTF node name, which is the part's name when the .glb is read back).
static func _part(root: Node3D, name: String, colour: String, pieces: Array) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for piece: Array in pieces:
		st.append_from(piece[0] as Mesh, 0, piece[1] as Transform3D)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.html(colour)
	mat.resource_name = name
	st.set_material(mat)
	var mesh := st.commit()
	mesh.resource_name = name
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	root.add_child(mi)
