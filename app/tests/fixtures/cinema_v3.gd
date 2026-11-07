extends "res://environments/vr_environment.gd"

## The cinema: a stadium-seated auditorium, the flagship room. The viewer sits in the middle of row 0 at the origin;
## rows in front step down (so seat backs never cover the screen: ROW_RISE per ROW_DEPTH keeps every seat back under
## the sight line from the seated eyes to the bottom of the default screen), rows behind step up. The rows curve
## gently toward the screen (arcs round a point ROW_RADIUS ahead of the viewer).
##
## What is in it (node names; the static parts are ArrayMeshes in room coordinates, gi_mode static, with their own
## lightmap UV2 from scripts/env/room_mesh.gd, no xatlas):
##   Floor        the carpeted tiers, their risers, the side aisles' steps (two a row), the pit and the rear walkway
##   Walls        side and rear walls (dark felt), FrontWall (black felt behind the screen), Ceiling (acoustic foam)
##   WallPanels   fabric panels on the side walls (stepping with the aisle) and the rear wall, with wooden rails
##   Stage, Curtains (pleated velvet either side and a valance), Doors (four exits with frames and push bars, and
##   the booth's window frames), Brass (the sconces' plates, the aisle handrails)
##   Seats        SEATS_PER_ROW x rows modelled seats in one MultiMesh: velvet cushion and back (instance colour: a
##                slight tint per seat), arm rests, standards and a pedestal
##   (lamp glows) the light sources' own glow (room_lamp.gdshader: emission only, so a bake takes them as emitters):
##                HouseLamps (sconce shades, ceiling cans: dim with the house lights), StepLights (the aisle steps'
##                noses: always on), StageLight (a broad dim band along the stage edge), ExitSigns, BoothWindow (the lens and the booth behind it)
##   Beam         the projector's beam (Cone) from the booth window to the screen (room_beam.gdshader, additive),
##   BakeLights   the room's real lights for a lightmap bake: sconces (a spot up and one down each), house lights
##                over the seats, step lights, the exit signs. Hidden: they never light the room live (LightmapGI
##                bakes hidden lights; bake_mode static)
##   ScreenBorder the black masking round the screen, following it
##
## Light. Every surface is a library material on room_material_house.gdshader (MaterialLibrary option "house"): the
## engine's lighting on the maps' colour, normals and roughness, scaled by the house lights' level (the room light:
## env_light over this room's ambient_level, so it dims while the film plays as every room does), plus, as emission,
## a warm hemisphere fill, the screen's live spill (as the unlit rooms: screen_glow, the bias light's colour) and,
## until a lightmap is baked, lamps standing in for the sconces (LAMP_*: soft point lights without shadows, shining up
## and down). No live lights at all: the room costs its draw calls and the shader's ALU, never a light pass.
## The bake (scripts/env/room_bake.gd, another part of the app) hooks in with:
##   set_baking(true)     before LightmapGI.bake(): the surfaces show the lightmapper their colour only (no fill,
##                        spill or lamps, which would bake in as light); set_baking(false) after
##   set_baked(true)      a lightmap is on the room: the static surfaces drop the lamps and most of the fill (the
##                        lightmap has them); the seats (a MultiMesh, which a bake does not cover) keep theirs. A
##                        LightmapGI added as a child of the room is noticed by itself (its light_data set)
##   bake_lights()        the BakeLights node; static_meshes() the MeshInstance3Ds the bake covers
## The house level scales a lightmap too (it is in ALBEDO), so the house lights still go down when the film starts.

const MaterialLibrary := preload("res://scripts/env/material_library.gd")
const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const PhysicsShapes := preload("res://scripts/play/physics_shapes.gd")
## Object physics (collision_shapes()): the walls' boxes this thick, the tiers in this many blocks along their arc
## (the arc strays under a centimetre from a block's straight edge), and a seat's two boxes in its own frame (the
## seat's floor point at the origin, facing -Z, seat_mesh()): the cushion with its standards and pedestal down to
## the floor, and the back, turned with it.
const WALL_THICKNESS := 1.0
const TIER_SEGMENTS := 8
const SEAT_BOX_CENTRE := Vector3(0.0, 0.24, -0.05)
const SEAT_BOX_SIZE := Vector3(0.55, 0.48, 0.52)
const SEAT_BACK_PIVOT := Vector3(0.0, 0.42, 0.2)
const SEAT_BACK_TILT_DEG := 13.0
const SEAT_BACK_CENTRE := Vector3(0.0, 0.35, 0.03)
const SEAT_BACK_SIZE := Vector3(0.52, 0.72, 0.14)
const ENV_SHADER := preload("res://shaders/env_unlit.gdshader")
const LAMP_SHADER := preload("res://shaders/room_lamp.gdshader")
const BEAM_SHADER := preload("res://shaders/room_beam.gdshader")

const ROOM_MIN := Vector3(-9.6, -3.0, -14.5)
const ROOM_MAX := Vector3(9.6, 9.0, 6.2)
const ROW_DEPTH := 1.3
const ROW_RISE := 0.35
const ROWS_FRONT := 7
const ROWS_BACK := 3
## Seats along each row's arc, centre to centre; an odd count puts a seat in the middle (the viewer's).
const SEAT_PITCH := 0.58
const SEATS_PER_ROW := 27
## Row 0's radius: every row is an arc round the point this far ahead of the viewer, on the floor's axis.
const ROW_RADIUS := 45.0
## The tiers reach to here either side; the side aisles' steps run from there to the walls.
const BLOCK_X := 8.1
const ROW_SEGMENTS := 24
const STAGE_DEPTH := 1.9
const STAGE_TOP := -2.1
const CURTAIN_WIDTH := 2.2
## The projector's lens, in the booth window in the rear wall (projector.gd's lens, 6 m behind and 2.2 m above the
## seated eyes, falls about here too).
const LENS := Vector3(0.0, 3.45, 6.15)
const PANEL_TOP := 7.6
const PANELS := 7
const PANEL_FROM := -9.6
const PANEL_TO := 6.0
const PANEL_GAP := 0.16
## The sconces: on the side walls in the gaps between panels (these panel joints), this high over the aisle.
const SCONCE_JOINTS := [1, 3, 5]
const SCONCE_HEIGHT := 2.5
const DOOR_SIZE := Vector2(1.8, 2.35)
## The acoustic clouds hang this far under the ceiling.
const CLOUD_DROP := 0.7
## The fill (the house lights' bounce, before a bake), as picked; and how much of it stays once a lightmap is on.
const FILL_TOP := Color(1.1, 0.88, 0.7)
const FILL_BOTTOM := Color(0.32, 0.25, 0.21)
const BAKED_FILL := 0.15
## How much the surfaces catch the screen's light (the unlit rooms' spill is 1): it carries the room while the film
## plays, when the house lights give 12 %.
const SPILL := 3.0
## The lamps standing in for the sconces before a bake: colour times energy, range (m), the cones' half angle.
const LAMP_COLOUR := Color(1.0, 0.68, 0.42)
const LAMP_ENERGY := 2.6
const LAMP_RANGE := 6.0
const LAMP_CONE_DEG := 42.0
const SEAT_SEED := 1907

var _border: MeshInstance3D
var _seats: MultiMeshInstance3D
var _seat_xforms: Array[Transform3D] = []
var _hidden_seat := -1
## Library materials of the static surfaces, and the seats' (instanced: never baked).
var _static_materials: Array[ShaderMaterial] = []
var _seat_materials: Array[ShaderMaterial] = []
var _lamp_materials: Array[ShaderMaterial] = []
## The stand-in lamps, room coordinates: [position, colour (energy in), cone cosine].
var _lamps: Array = []
var _baked := false
var _baking := false
var _lightmap: Node
## A LightmapGI child with data was seen (set_baked follows it; the bake may also call set_baked itself).
var _lightmap_seen := false
var _main: Node
var _beam_root: Node3D
var _beam: MeshInstance3D
var _screen_world := Transform3D()
var _screen_size := Vector2.ZERO
var _beam_key := ""


func _ready() -> void:
	set_notify_transform(true)
	_build_floor()
	_build_shell()
	_build_wall_panels()
	_build_front()
	_build_doors_and_booth()
	_build_fixtures()
	_build_seats()
	_build_bake_lights()
	_build_beam()
	var border := QuadMesh.new()
	var bm := ShaderMaterial.new()
	bm.shader = ENV_SHADER
	bm.set_shader_parameter("albedo", Color.BLACK)
	bm.set_shader_parameter("spill", 0.0)
	border.material = bm
	_border = _add_mesh("ScreenBorder", border, get_screen_anchor())
	_border.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	child_entered_tree.connect(_on_child_entered)
	child_exiting_tree.connect(_on_child_exiting)
	_place_lamps()
	_hide_occupied_seat()


# --- Layout -------------------------------------------------------------------------------------------------------

static func row_floor(row: int) -> float:
	return -ROW_RISE * row


## The radius of a row's centre line (where the seated eyes are).
static func row_radius(row: int) -> float:
	return ROW_RADIUS - ROW_DEPTH * row


## z of the arc of this radius at x (the arcs' centre is ROW_RADIUS ahead).
static func arc_z(radius: float, x: float) -> float:
	return -ROW_RADIUS + sqrt(maxf(radius * radius - x * x, 0.0))


## The floor's height along the side aisles at z: the pit, two steps a row, the rear walkway.
static func aisle_floor(z: float) -> float:
	for row in range(ROWS_FRONT, -ROWS_BACK - 1, -1):
		var front := arc_z(row_radius(row) - ROW_DEPTH * 0.5, BLOCK_X)
		var back := arc_z(row_radius(row) + ROW_DEPTH * 0.5, BLOCK_X)
		if z < front:
			return ROOM_MIN.y if row == ROWS_FRONT else row_floor(row + 1)
		if z < (front + back) * 0.5:
			return row_floor(row) - ROW_RISE * 0.5
		if z < back:
			return row_floor(row)
	return row_floor(-ROWS_BACK)


## Every seat: the floor point under the seated eyes and the seat's facing (toward the rows' centre), by row from the
## back, left to right. Row 0's middle seat is the viewer's own, at the origin.
static func seat_transforms() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var half := (SEATS_PER_ROW - 1) / 2
	for row in range(-ROWS_BACK, ROWS_FRONT + 1):
		var r := row_radius(row)
		for k in range(-half, half + 1):
			var a := k * SEAT_PITCH / r
			out.append(Transform3D(Basis(Vector3.UP, a), Vector3(r * sin(a), row_floor(row), -ROW_RADIUS + r * cos(a))))
	return out


## Seat choice (scripts/comfort/seat_choice.gd, ideas #19): the floor point under a seated viewer's eyes for every
## seat, the viewer's own spot included (row 0, middle).
func get_seats() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for t in seat_transforms():
		out.append(t.origin)
	return out


## Spatial audio: screen speakers behind the screen, surround arrays of three along the side walls and on the back
## wall, 4 m above the seat's floor, the heights on the ceiling. Fabric-lined walls and a carpet: little reflection,
## a short, dead reverb for its size.
func get_sound_room() -> Dictionary:
	return {"box": AABB(ROOM_MIN, ROOM_MAX - ROOM_MIN), "reflect": [0.3, 0.3, 0.25, 0.35, 0.2, 0.3], "rt60": 0.7,
			"wet": 0.55, "surround_height": 4.0, "array": 3, "array_spacing": 3.0}


## Object physics (scripts/play/object_physics.gd, docs/physics.md): the room as cheap boxes, [[Shape3D, Transform3D]]
## in its own frame. A slab under the floor, the walls and the ceiling (WALL_THICKNESS thick, outside the room), the
## stage, each row's tier as TIER_SEGMENTS solid blocks along its arc (down to the pit's floor), the side aisles'
## steps, the rear walkway, and two boxes a seat from seat_transforms(): the cushion with its standards, and the
## tilted back. The seats share two shapes.
func collision_shapes() -> Array:
	var out: Array = []
	var lo := ROOM_MIN
	var hi := ROOM_MAX
	var size := hi - lo
	var mid := (lo + hi) * 0.5
	var t := WALL_THICKNESS
	out.append(PhysicsShapes.box(Vector3(mid.x, lo.y - t * 0.5, mid.z), Vector3(size.x + 2.0 * t, t, size.z + 2.0 * t)))
	out.append(PhysicsShapes.box(Vector3(mid.x, hi.y + t * 0.5, mid.z), Vector3(size.x + 2.0 * t, t, size.z + 2.0 * t)))
	for s: float in [-1.0, 1.0]:
		out.append(PhysicsShapes.box(Vector3(mid.x + s * (size.x + t) * 0.5, mid.y, mid.z),
				Vector3(t, size.y + 2.0 * t, size.z + 2.0 * t)))
		out.append(PhysicsShapes.box(Vector3(mid.x, mid.y, mid.z + s * (size.z + t) * 0.5),
				Vector3(size.x + 2.0 * t, size.y + 2.0 * t, t)))
	var stage_h := STAGE_TOP - lo.y
	out.append(PhysicsShapes.box(Vector3(0.0, lo.y + stage_h * 0.5, lo.z + STAGE_DEPTH * 0.5),
			Vector3(size.x, stage_h, STAGE_DEPTH)))
	for row in range(-ROWS_BACK, ROWS_FRONT + 1):
		var r := row_radius(row)
		var top := row_floor(row)
		var h := top - lo.y
		if h <= 0.01:
			continue
		var reach := asin(BLOCK_X / (r + ROW_DEPTH * 0.5))
		for i in TIER_SEGMENTS:
			var a0 := lerpf(-reach, reach, float(i) / TIER_SEGMENTS)
			var a1 := lerpf(-reach, reach, float(i + 1) / TIER_SEGMENTS)
			var a := (a0 + a1) * 0.5
			# The back edge's chord is the widest: the blocks meet there and overlap a little in front.
			var chord := 2.0 * (r + ROW_DEPTH * 0.5) * sin((a1 - a0) * 0.5) * 1.02
			out.append(PhysicsShapes.box(Vector3(r * sin(a), lo.y + h * 0.5, -ROW_RADIUS + r * cos(a)),
					Vector3(chord, h, ROW_DEPTH), Basis(Vector3.UP, a)))
		# The side aisles: two steps a row, straight across to the wall.
		var zf := arc_z(r - ROW_DEPTH * 0.5, BLOCK_X)
		var zb := arc_z(r + ROW_DEPTH * 0.5, BLOCK_X)
		var zm := (zf + zb) * 0.5
		var low := top - ROW_RISE * 0.5
		var aisle_w := hi.x - BLOCK_X
		for s: float in [-1.0, 1.0]:
			var x := s * (BLOCK_X + aisle_w * 0.5)
			out.append(PhysicsShapes.box(Vector3(x, lo.y + h * 0.5, (zm + zb) * 0.5), Vector3(aisle_w, h, zb - zm)))
			if low - lo.y > 0.01:
				out.append(PhysicsShapes.box(Vector3(x, (lo.y + low) * 0.5, (zf + zm) * 0.5),
						Vector3(aisle_w, low - lo.y, zm - zf)))
	# The rear walkway: level with the back row, from the back row's arc at the aisles to the rear wall.
	var walk := row_floor(-ROWS_BACK)
	var walk_from := arc_z(row_radius(-ROWS_BACK) + ROW_DEPTH * 0.5, BLOCK_X)
	out.append(PhysicsShapes.box(Vector3(mid.x, (lo.y + walk) * 0.5, (walk_from + hi.z) * 0.5),
			Vector3(size.x, walk - lo.y, hi.z - walk_from)))
	var cushion := BoxShape3D.new()
	cushion.size = SEAT_BOX_SIZE
	var back := BoxShape3D.new()
	back.size = SEAT_BACK_SIZE
	var tilt := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(SEAT_BACK_TILT_DEG)), SEAT_BACK_PIVOT)
	var back_xf := Transform3D(tilt.basis, tilt * SEAT_BACK_CENTRE)
	for st in seat_transforms():
		out.append([cushion, st * Transform3D(Basis(), SEAT_BOX_CENTRE)])
		out.append([back, st * back_xf])
	return out


# --- Building ------------------------------------------------------------------------------------------------------

func _build_floor() -> void:
	var b := RoomMesh.new()
	b.surface(_library("woven_carpet", Color(0.3, 0.12, 0.11), {"tiling": 0.9}))
	var xs: Array[float] = []
	for i in ROW_SEGMENTS + 1:
		xs.append(lerpf(-BLOCK_X, BLOCK_X, float(i) / ROW_SEGMENTS))
	for row in range(-ROWS_BACK, ROWS_FRONT + 1):
		var y := row_floor(row)
		var below := ROOM_MIN.y if row == ROWS_FRONT else row_floor(row + 1)
		var r_front := row_radius(row) - ROW_DEPTH * 0.5
		var r_back := row_radius(row) + ROW_DEPTH * 0.5
		var front := PackedVector3Array()
		var back := PackedVector3Array()
		var low := PackedVector3Array()
		var ups := PackedVector3Array()
		var faces := PackedVector3Array()
		for x in xs:
			var zf := arc_z(r_front, x)
			front.append(Vector3(x, y, zf))
			back.append(Vector3(x, y, arc_z(r_back, x)))
			low.append(Vector3(x, below, zf))
			ups.append(Vector3.UP)
			faces.append(Vector3(-x, 0.0, -ROW_RADIUS - zf).normalized())
		b.strip(front, back, ups)
		b.strip(low, front, faces)
		# The side aisles: two steps a row, straight across to the wall.
		var zf := arc_z(r_front, BLOCK_X)
		var zb := arc_z(r_back, BLOCK_X)
		var zm := (zf + zb) * 0.5
		var mid := y - ROW_RISE * 0.5
		for s: float in [-1.0, 1.0]:
			var x0 := BLOCK_X * s
			var x1 := ROOM_MAX.x * s
			b.face([Vector3(x0, y, zm), Vector3(x1, y, zm), Vector3(x1, y, zb), Vector3(x0, y, zb)], Vector3.UP)
			b.face([Vector3(x0, mid, zf), Vector3(x1, mid, zf), Vector3(x1, mid, zm), Vector3(x0, mid, zm)], Vector3.UP)
			b.face([Vector3(x0, mid, zm), Vector3(x1, mid, zm), Vector3(x1, y, zm), Vector3(x0, y, zm)],
					Vector3.FORWARD)
			b.face([Vector3(x0, below, zf), Vector3(x1, below, zf), Vector3(x1, mid, zf), Vector3(x0, mid, zf)],
					Vector3.FORWARD)
			# Where the tier's front half stands above the aisle's lower step.
			b.face([Vector3(x0, mid, zf), Vector3(x0, mid, zm), Vector3(x0, y, zm), Vector3(x0, y, zf)],
					Vector3(s, 0.0, 0.0))
	# The pit (from the stage to the front row) and the rear walkway (from the back row to the rear wall).
	var edge_x: Array[float] = [ROOM_MIN.x]
	edge_x.append_array(xs)
	edge_x.append(ROOM_MAX.x)
	var pit_a := PackedVector3Array()
	var pit_b := PackedVector3Array()
	var walk_a := PackedVector3Array()
	var walk_b := PackedVector3Array()
	var ups := PackedVector3Array()
	var top := row_floor(-ROWS_BACK)
	for x in edge_x:
		var cx := clampf(x, -BLOCK_X, BLOCK_X)
		pit_a.append(Vector3(x, ROOM_MIN.y, ROOM_MIN.z + STAGE_DEPTH))
		pit_b.append(Vector3(x, ROOM_MIN.y, arc_z(row_radius(ROWS_FRONT) - ROW_DEPTH * 0.5, cx)))
		walk_a.append(Vector3(x, top, arc_z(row_radius(-ROWS_BACK) + ROW_DEPTH * 0.5, cx)))
		walk_b.append(Vector3(x, top, ROOM_MAX.z))
		ups.append(Vector3.UP)
	b.strip(pit_a, pit_b, ups)
	b.strip(walk_a, walk_b, ups)
	_add_static("Floor", b)


func _build_shell() -> void:
	var lo := ROOM_MIN
	var hi := ROOM_MAX
	var walls := RoomMesh.new()
	walls.surface(_library("felt", Color(0.17, 0.15, 0.16)))
	for s: float in [-1.0, 1.0]:
		var x := hi.x * s
		walls.face([Vector3(x, lo.y, lo.z), Vector3(x, lo.y, hi.z), Vector3(x, hi.y, hi.z), Vector3(x, hi.y, lo.z)],
				Vector3(-s, 0.0, 0.0))
	var walk := row_floor(-ROWS_BACK)
	walls.face([Vector3(lo.x, walk, hi.z), Vector3(hi.x, walk, hi.z), Vector3(hi.x, hi.y, hi.z),
			Vector3(lo.x, hi.y, hi.z)], Vector3.FORWARD)
	_add_static("Walls", walls)
	var front := RoomMesh.new()
	front.surface(_library("felt", Color(0.04, 0.035, 0.04), {"spill": 1.0}))
	front.face([Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z),
			Vector3(lo.x, hi.y, lo.z)], Vector3.BACK)
	_add_static("FrontWall", front)
	var ceiling := RoomMesh.new()
	ceiling.surface(_library("acoustic_foam", Color(0.2, 0.19, 0.2), {"tiling": 1.2}))
	ceiling.face([Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z),
			Vector3(lo.x, hi.y, hi.z)], Vector3.DOWN)
	# Acoustic clouds hung below it over the seats: a sense of the ceiling's height.
	for z: float in _cloud_z():
		ceiling.box(Vector3(0.0, hi.y - CLOUD_DROP, z), Vector3(12.0, 0.18, 2.6), Basis(), [RoomMesh.UP])
	_add_static("Ceiling", ceiling)


func _cloud_z() -> Array[float]:
	return [-9.0, -3.5, 2.0]


## The side walls' fabric panels, from above the aisle floor at their back edge to PANEL_TOP, with a wooden rail
## under and over each.
func _build_wall_panels() -> void:
	var b := RoomMesh.new()
	var fabric := _library("felt", Color(0.38, 0.15, 0.12), {"tiling": 0.6})
	var wood := _library("walnut_veneer", Color(0.3, 0.19, 0.12))
	var pitch := (PANEL_TO - PANEL_FROM) / PANELS
	for s: float in [-1.0, 1.0]:
		var x := ROOM_MAX.x * s
		for i in PANELS:
			var z0 := PANEL_FROM + i * pitch + PANEL_GAP * 0.5
			var z1 := z0 + pitch - PANEL_GAP
			var bottom := aisle_floor(z1 - 0.01) + 1.05
			var centre := Vector3(x - s * 0.04, (bottom + PANEL_TOP) * 0.5, (z0 + z1) * 0.5)
			b.surface(fabric)
			b.box(centre, Vector3(0.08, PANEL_TOP - bottom, z1 - z0), Basis(), [Vector3(s, 0, 0)])
			b.surface(wood)
			for y: float in [bottom - 0.05, PANEL_TOP + 0.05]:
				b.box(Vector3(x - s * 0.06, y, (z0 + z1) * 0.5), Vector3(0.12, 0.1, pitch), Basis(),
						[Vector3(s, 0, 0)])
	# The rear wall: two panels either side, between the booth's windows and the doors.
	var walk := row_floor(-ROWS_BACK)
	var bottom := walk + 1.05
	for s: float in [-1.0, 1.0]:
		for i in 2:
			var x0 := s * (2.3 + i * 2.25)
			var x1 := x0 + s * (2.25 - PANEL_GAP)
			var centre := Vector3((x0 + x1) * 0.5, (bottom + PANEL_TOP) * 0.5, ROOM_MAX.z - 0.04)
			b.surface(fabric)
			b.box(centre, Vector3(absf(x1 - x0), PANEL_TOP - bottom, 0.08), Basis(), [RoomMesh.BACK])
			b.surface(wood)
			for y: float in [bottom - 0.05, PANEL_TOP + 0.05]:
				b.box(Vector3(centre.x, y, ROOM_MAX.z - 0.06), Vector3(2.25, 0.1, 0.12), Basis(), [RoomMesh.BACK])
	_add_static("WallPanels", b)


func _build_front() -> void:
	var stage := RoomMesh.new()
	stage.surface(_library("red_hardwood", Color(0.36, 0.22, 0.15)))
	var h := STAGE_TOP - ROOM_MIN.y
	stage.box(Vector3(0.0, ROOM_MIN.y + h * 0.5, ROOM_MIN.z + STAGE_DEPTH * 0.5),
			Vector3(ROOM_MAX.x - ROOM_MIN.x, h, STAGE_DEPTH), Basis(),
			[RoomMesh.LEFT, RoomMesh.RIGHT, RoomMesh.DOWN, RoomMesh.FRONT])
	_add_static("Stage", stage)
	# Curtains on the front wall either side, beyond the widest screen, and a valance across the top: pleated velvet
	# (folds from the shader).
	var curtains := RoomMesh.new()
	curtains.surface(_library("velvet", Color(0.45, 0.05, 0.07), {"pleats": 3.0, "pleat_depth": 0.6}))
	var height := ROOM_MAX.y - STAGE_TOP
	for s: float in [-1.0, 1.0]:
		curtains.box(Vector3(s * (ROOM_MAX.x - CURTAIN_WIDTH * 0.5), STAGE_TOP + height * 0.5, ROOM_MIN.z + 0.1),
				Vector3(CURTAIN_WIDTH, height, 0.14), Basis(), [RoomMesh.FRONT, RoomMesh.UP, RoomMesh.DOWN])
	curtains.box(Vector3(0.0, ROOM_MAX.y - 0.6, ROOM_MIN.z + 0.25), Vector3(ROOM_MAX.x * 2.0 - 0.2, 1.2, 0.14),
			Basis(), [RoomMesh.FRONT, RoomMesh.UP])
	_add_static("Curtains", curtains)


## The exits (two at the front on the side walls, two at the back on the rear walkway) and the booth's windows.
func _build_doors_and_booth() -> void:
	var b := RoomMesh.new()
	var leaf := _library("walnut_veneer", Color(0.25, 0.15, 0.1))
	var metal := _library("brushed_steel", Color(0.45, 0.45, 0.46))
	for d in _doors():
		var at: Vector3 = d[0]
		var basis: Basis = d[1]
		var w := DOOR_SIZE.x
		var h := DOOR_SIZE.y
		b.surface(leaf)
		for side: float in [-1.0, 1.0]:
			b.box(at + basis * Vector3(side * w * 0.25, h * 0.5, 0.025), Vector3(w * 0.5 - 0.012, h - 0.02, 0.05),
					basis, [RoomMesh.FRONT])
		b.surface(metal)
		for side: float in [-1.0, 1.0]:
			b.box(at + basis * Vector3(side * (w * 0.5 + 0.05), h * 0.5 + 0.05, 0.04), Vector3(0.1, h + 0.1, 0.08),
					basis, [RoomMesh.FRONT])
			# Push bar and kick plate on each leaf.
			b.box(at + basis * Vector3(side * w * 0.25, 1.0, 0.09), Vector3(w * 0.36, 0.06, 0.07), basis,
					[RoomMesh.FRONT])
			b.box(at + basis * Vector3(side * w * 0.25, 0.13, 0.053), Vector3(w * 0.44, 0.24, 0.006), basis,
					[RoomMesh.FRONT])
		b.box(at + basis * Vector3(0.0, h + 0.05, 0.04), Vector3(w + 0.2, 0.1, 0.08), basis, [RoomMesh.FRONT])
		# The sign's housing.
		b.box(at + basis * Vector3(0.0, h + 0.4, 0.04), Vector3(0.56, 0.24, 0.08), basis, [RoomMesh.FRONT])
	# The booth's windows in the rear wall: the projector's port and two viewing ports beside it.
	for w: Array in _booth_windows():
		var c: Vector3 = w[0]
		var size: Vector2 = w[1]
		for side: float in [-1.0, 1.0]:
			b.box(c + Vector3(side * (size.x * 0.5 + 0.05), 0.0, -0.06), Vector3(0.1, size.y + 0.2, 0.12), Basis(),
					[RoomMesh.BACK])
			b.box(c + Vector3(0.0, side * (size.y * 0.5 + 0.05), -0.06), Vector3(size.x, 0.1, 0.12), Basis(),
					[RoomMesh.BACK])
	_add_static("Doors", b)


## [bottom centre, basis (x along the wall, z out into the room)] of each exit door.
func _doors() -> Array:
	var front_z := (ROOM_MIN.z + STAGE_DEPTH + arc_z(row_radius(ROWS_FRONT) - ROW_DEPTH * 0.5, BLOCK_X)) * 0.5
	var walk := row_floor(-ROWS_BACK)
	var out: Array = []
	for s: float in [-1.0, 1.0]:
		var into := Vector3(-s, 0.0, 0.0)
		out.append([Vector3(ROOM_MAX.x * s, ROOM_MIN.y, front_z), Basis(Vector3.UP.cross(into), Vector3.UP, into)])
		out.append([Vector3(s * (ROOM_MAX.x - 1.6), walk, ROOM_MAX.z),
				Basis(Vector3.LEFT, Vector3.UP, Vector3.FORWARD)])
	return out


## [centre, size] of the booth's windows: the projector's port round the lens, a viewing port either side.
func _booth_windows() -> Array:
	return [[Vector3(LENS.x, LENS.y, ROOM_MAX.z), Vector2(1.3, 0.75)],
			[Vector3(-1.5, LENS.y, ROOM_MAX.z), Vector2(0.55, 0.4)],
			[Vector3(1.5, LENS.y, ROOM_MAX.z), Vector2(0.55, 0.4)]]


## [position, wall side] of each sconce (room coordinates).
func _sconces() -> Array:
	var out: Array = []
	var pitch := (PANEL_TO - PANEL_FROM) / PANELS
	for s: float in [-1.0, 1.0]:
		for j: int in SCONCE_JOINTS:
			var z := PANEL_FROM + j * pitch
			out.append([Vector3(s * (ROOM_MAX.x - 0.13), aisle_floor(z) + SCONCE_HEIGHT, z), s])
	return out


## Lamps and their fittings: sconces (a brass plate and a glowing shade), ceiling cans, the aisle handrails, the step
## lights, the exit signs and the booth's windows.
func _build_fixtures() -> void:
	var brass := RoomMesh.new()
	brass.surface(_library("brass", Color(0.55, 0.42, 0.22)))
	var house := RoomMesh.new()
	house.surface(_lamp_material(Color(1.0, 0.72, 0.45), 1.6, 1.0))
	for sc: Array in _sconces():
		var p: Vector3 = sc[0]
		var s: float = sc[1]
		brass.box(Vector3(s * (ROOM_MAX.x - 0.015), p.y, p.z), Vector3(0.03, 0.5, 0.12), Basis(), [Vector3(s, 0, 0)])
		house.box(p, Vector3(0.18, 0.34, 0.14), Basis(), [Vector3(s, 0, 0)])
		_lamps.append([p, LAMP_COLOUR * LAMP_ENERGY, cos(deg_to_rad(LAMP_CONE_DEG))])
	# Handrails along the side walls, following the aisle's slope.
	var rail_from := Vector3(0.0, ROOM_MIN.y + 0.9, arc_z(row_radius(ROWS_FRONT) - ROW_DEPTH * 0.5, BLOCK_X))
	var rail_to := Vector3(0.0, row_floor(-ROWS_BACK) + 0.9, arc_z(row_radius(-ROWS_BACK) + ROW_DEPTH * 0.5, BLOCK_X))
	for s: float in [-1.0, 1.0]:
		var a := rail_from + Vector3(s * (ROOM_MAX.x - 0.09), 0.0, 0.0)
		var c := rail_to + Vector3(s * (ROOM_MAX.x - 0.09), 0.0, 0.0)
		var dir := (c - a).normalized()
		var across := Vector3.UP.cross(dir).normalized()
		brass.box((a + c) * 0.5, Vector3(0.05, 0.05, a.distance_to(c)), Basis(across, dir.cross(across), dir))
	_add_static("Brass", brass)
	# Ceiling cans (the house lights): two rows under each acoustic cloud, a row on the ceiling at either end.
	var cans: Array[Vector3] = []
	for z: float in _cloud_z():
		for dz: float in [-0.7, 0.7]:
			for ix in 5:
				cans.append(Vector3(lerpf(-5.0, 5.0, ix / 4.0), ROOM_MAX.y - CLOUD_DROP - 0.095, z + dz))
	for z: float in [-12.0, 4.8]:
		for ix in 5:
			cans.append(Vector3(lerpf(-5.0, 5.0, ix / 4.0), ROOM_MAX.y - 0.005, z))
	for c in cans:
		var corners: Array = []
		for k in 8:
			var a := TAU * k / 8.0
			corners.append(c + Vector3(cos(a), 0.0, sin(a)) * 0.12)
		house.face(corners, Vector3.DOWN)
	_add_lamps("HouseLamps", house)
	# Step lights: a strip on the nose of every aisle step.
	var steps := RoomMesh.new()
	steps.surface(_lamp_material(Color(1.0, 0.62, 0.3), 1.1, 0.0))
	for row in range(-ROWS_BACK, ROWS_FRONT + 1):
		var zf := arc_z(row_radius(row) - ROW_DEPTH * 0.5, BLOCK_X)
		var zm := (zf + arc_z(row_radius(row) + ROW_DEPTH * 0.5, BLOCK_X)) * 0.5
		for nose: Vector2 in [Vector2(zm, row_floor(row)), Vector2(zf, row_floor(row) - ROW_RISE * 0.5)]:
			for s: float in [-1.0, 1.0]:
				var x0 := s * (BLOCK_X + 0.15)
				var x1 := s * (ROOM_MAX.x - 0.15)
				var z := nose.x - 0.004
				steps.face([Vector3(x0, nose.y - 0.035, z), Vector3(x1, nose.y - 0.035, z), Vector3(x1, nose.y - 0.01, z),
						Vector3(x0, nose.y - 0.01, z)], Vector3.FORWARD)
	_add_lamps("StepLights", steps)
	# The stage's apron light: a broad, dim band, not a thin bright line. A 3 cm strip at 14 m strobed in the
	# periphery with foveation on (the user, 2026-11-04).
	var sz := ROOM_MIN.z + STAGE_DEPTH + 0.004
	var apron := RoomMesh.new()
	apron.surface(_lamp_material(Color(1.0, 0.62, 0.3), 0.4, 0.0))
	apron.face([Vector3(ROOM_MIN.x, STAGE_TOP - 0.12, sz), Vector3(ROOM_MAX.x, STAGE_TOP - 0.12, sz),
			Vector3(ROOM_MAX.x, STAGE_TOP - 0.02, sz), Vector3(ROOM_MIN.x, STAGE_TOP - 0.02, sz)], Vector3.BACK)
	_add_lamps("StageLight", apron)
	# Exit signs over the doors, and the booth's windows: pictures.
	var signs: Array = []
	for d in _doors():
		var at: Vector3 = d[0]
		var basis: Basis = d[1]
		signs.append([at + basis * Vector3(0.0, DOOR_SIZE.y + 0.4, 0.081), basis.x * 0.25, Vector3.UP * 0.1, basis.z])
	_add_picture("ExitSigns", signs, _exit_picture(), Color(1, 1, 1), 1.4)
	var windows: Array = []
	for w: Array in _booth_windows():
		var c: Vector3 = w[0]
		var size: Vector2 = w[1]
		windows.append([c + Vector3(0, 0, -0.01), Vector3.LEFT * size.x * 0.5, Vector3.UP * size.y * 0.5,
				Vector3.FORWARD, w == _booth_windows()[0]])
	_add_picture("BoothWindow", windows, _booth_picture(), Color(1, 1, 1), 1.0)


func _build_seats() -> void:
	# A red velvet a third of the way to grey: the full red read as too saturated under the house lights (the user, in
	# the headset, 2026-11-04).
	var velvet := _library("velvet", Color(0.376, 0.092, 0.11), {"tiling": 0.22}, true)
	velvet.set_shader_parameter("instance_tint", true)
	var shell := _library("black_leather", Color(0.08, 0.075, 0.078), {}, true)
	var mesh := seat_mesh(velvet, shell)
	_seat_xforms = seat_transforms()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = _seat_xforms.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEAT_SEED
	for i in _seat_xforms.size():
		mm.set_instance_transform(i, _seat_xforms[i])
		# Velvet fades and is replaced seat by seat: a little lighter or darker, a little warmer or cooler.
		var v := rng.randf_range(0.86, 1.1)
		var warm := rng.randf_range(-0.04, 0.04)
		mm.set_instance_color(i, Color(v * (1.0 + warm), v, v * (1.0 - warm)))
	_seats = MultiMeshInstance3D.new()
	_seats.name = "Seats"
	_seats.multimesh = mm
	_seats.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Not baked (a bake covers MeshInstance3Ds only): lit by the fill, the lamps and the spill, never by the probes.
	_seats.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(_seats)


## One seat, its floor point under the seated eyes at the origin, facing -Z: a velvet cushion and back (the back
## curved in plan and tilted) with an outer cover behind it, half an arm rest and half a standard either side (the
## neighbour's halves complete them: a joined row), and a pedestal under the cushion.
static func seat_mesh(upholstery: Material, frame: Material) -> ArrayMesh:
	var b := RoomMesh.new()
	var half := SEAT_PITCH * 0.5
	var tilt := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(13.0)), Vector3(0.0, 0.42, 0.2))
	b.surface(upholstery)
	b.rounded_box(Vector3(0.0, 0.41, -0.07), Vector3(half * 2.0 - 0.08, 0.13, 0.5), 0.045, Transform3D(), 1,
			Vector3i(1, 0, 0), 0.0, [RoomMesh.DOWN])
	b.rounded_box(Vector3(0.0, 0.33, 0.0), Vector3(half * 2.0 - 0.08, 0.66, 0.09), 0.04, tilt, 1, Vector3i(3, 1, 0),
			-0.5, [RoomMesh.DOWN])
	# The back's outer cover, a little bigger, behind it (what the row behind sees).
	b.rounded_box(Vector3(0.0, 0.35, 0.068), Vector3(half * 2.0 - 0.06, 0.72, 0.045), 0.02, tilt, 1,
			Vector3i(3, 1, 0), -0.5, [RoomMesh.DOWN])
	b.surface(frame)
	for s: float in [-1.0, 1.0]:
		var x := s * (half - 0.0155)
		b.rounded_box(Vector3(x, 0.655, -0.03), Vector3(0.031, 0.05, 0.44), 0.012, Transform3D(), 1, Vector3i.ZERO,
				0.0, [Vector3(s, 0, 0), RoomMesh.DOWN])
		b.box(Vector3(x, 0.315, 0.09), Vector3(0.031, 0.63, 0.3), Basis(), [Vector3(s, 0, 0), RoomMesh.DOWN])
	b.box(Vector3(0.0, 0.175, -0.02), Vector3(0.1, 0.31, 0.1), Basis(), [RoomMesh.DOWN, RoomMesh.UP])
	b.box(Vector3(0.0, 0.01, -0.02), Vector3(0.32, 0.02, 0.26), Basis(), [RoomMesh.DOWN])
	return b.commit(false)


## The room's real lights, for a lightmap bake only (hidden; LightmapGI bakes hidden lights).
func _build_bake_lights() -> void:
	var root := Node3D.new()
	root.name = "BakeLights"
	add_child(root)
	var i := 0
	for sc: Array in _sconces():
		var p: Vector3 = sc[0]
		for up: bool in [true, false]:
			var l := SpotLight3D.new()
			l.name = "Sconce%d%s" % [i, "Up" if up else "Down"]
			l.position = p + Vector3(0.0, 0.18 if up else -0.18, 0.0)
			l.rotation = Vector3(PI * 0.5 if up else -PI * 0.5, 0.0, 0.0)
			l.spot_angle = LAMP_CONE_DEG
			l.spot_range = 5.0
			l.light_energy = 2.0
			l.light_color = LAMP_COLOUR
			_bake_light(root, l)
		i += 1
	i = 0
	for x: float in [-4.0, 4.0]:
		for z: float in [-7.0, 1.0]:
			var l := SpotLight3D.new()
			l.name = "House%d" % i
			l.position = Vector3(x, ROOM_MAX.y - 0.2, z)
			l.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
			l.spot_angle = 60.0
			l.spot_range = 16.0
			l.light_energy = 1.2
			l.light_color = Color(1.0, 0.86, 0.7)
			_bake_light(root, l)
			i += 1
	i = 0
	for row: int in [6, 2, -2]:
		var zf := arc_z(row_radius(row) - ROW_DEPTH * 0.5, BLOCK_X)
		for s: float in [-1.0, 1.0]:
			var l := OmniLight3D.new()
			l.name = "Step%d" % i
			l.position = Vector3(s * (BLOCK_X + ROOM_MAX.x) * 0.5, row_floor(row) - 0.05, zf - 0.15)
			l.omni_range = 1.8
			l.light_energy = 0.5
			l.light_color = Color(1.0, 0.62, 0.3)
			_bake_light(root, l)
			i += 1
	i = 0
	for d in _doors():
		var at: Vector3 = d[0]
		var basis: Basis = d[1]
		var l := OmniLight3D.new()
		l.name = "Exit%d" % i
		l.position = at + basis * Vector3(0.0, DOOR_SIZE.y + 0.4, 0.25)
		l.omni_range = 2.5
		l.light_energy = 0.35
		l.light_color = Color(0.2, 1.0, 0.45)
		_bake_light(root, l)
		i += 1


func _bake_light(root: Node3D, l: Light3D) -> void:
	l.light_bake_mode = Light3D.BAKE_STATIC
	l.shadow_enabled = true
	l.visible = false
	root.add_child(l)


func _build_beam() -> void:
	_beam_root = Node3D.new()
	_beam_root.name = "Beam"
	_beam_root.position = LENS
	add_child(_beam_root)
	_beam = MeshInstance3D.new()
	_beam.name = "Cone"
	var m := ShaderMaterial.new()
	m.shader = BEAM_SHADER
	m.set_shader_parameter("house_reference", ambient_level)
	_beam.material_override = m
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_beam_root.add_child(_beam)


# --- Materials and nodes ---------------------------------------------------------------------------------------------

## A library material on the house shader, this room's own copy (its lamps and bake state are set on it).
func _library(id: String, colour: Color, options := {}, instanced := false) -> ShaderMaterial:
	var o := options.duplicate()
	o.merge({"colour": colour, "spill": SPILL, "house": {"sky_top": FILL_TOP, "sky_bottom": FILL_BOTTOM}})
	var shared := MaterialLibrary.get_material(id, o)
	var m: ShaderMaterial
	if shared != null:
		m = shared.duplicate() as ShaderMaterial
	else:
		# Without the library (a broken install): a plain lit colour on the same shader's terms.
		m = ShaderMaterial.new()
		m.shader = MaterialLibrary.SHADER_HOUSE
		m.set_shader_parameter("tint", colour)
	# The fill again, as vectors: duplicate() loses a Color set on a vec3 uniform.
	_set_fill(m, 1.0)
	m.set_shader_parameter("house_reference", ambient_level)
	m.set_shader_parameter("contact_strength", 0.0)
	(_seat_materials if instanced else _static_materials).append(m)
	return m


static func _set_fill(m: ShaderMaterial, k: float) -> void:
	m.set_shader_parameter("sky_top", Vector3(FILL_TOP.r, FILL_TOP.g, FILL_TOP.b) * k)
	m.set_shader_parameter("sky_bottom", Vector3(FILL_BOTTOM.r, FILL_BOTTOM.g, FILL_BOTTOM.b) * k)


func _lamp_material(colour: Color, energy: float, follows_house: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = LAMP_SHADER
	m.set_shader_parameter("colour", colour)
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("follows_house", follows_house)
	m.set_shader_parameter("house_reference", ambient_level)
	_lamp_materials.append(m)
	return m


func _add_static(node_name: String, b: RoomMesh) -> MeshInstance3D:
	var mi := _add_mesh(node_name, b.commit(true), Transform3D())
	mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	return mi


func _add_lamps(node_name: String, b: RoomMesh) -> MeshInstance3D:
	var mi := _add_mesh(node_name, b.commit(false), Transform3D())
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return mi


## Pictures on flat quads: [centre, half across, half up, facing, (optional) bright] each; one mesh, one material.
func _add_picture(node_name: String, quads: Array, picture: Texture2D, colour: Color, energy: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for q: Array in quads:
		var c: Vector3 = q[0]
		var u: Vector3 = q[1]
		var v: Vector3 = q[2]
		var n: Vector3 = q[3]
		# The window's picture: the lens's half (u 0..0.5) for the projector's port, the other half for the others.
		var u0 := 0.0
		var u1 := 1.0
		if q.size() > 4:
			u0 = 0.0 if q[4] else 0.5
			u1 = u0 + 0.5
		var corners := [c - u - v, c + u - v, c + u + v, c - u + v]
		var uvs := [Vector2(u0, 1), Vector2(u1, 1), Vector2(u1, 0), Vector2(u0, 0)]
		var order := [0, 1, 2, 0, 2, 3]
		if (corners[2] - corners[0]).cross(corners[1] - corners[0]).dot(n) < 0.0:
			order = [0, 2, 1, 0, 3, 2]
		for k: int in order:
			st.set_normal(n)
			st.set_uv(uvs[k])
			st.add_vertex(corners[k])
	var m := _lamp_material(colour, energy, 0.0)
	m.set_shader_parameter("picture", picture)
	m.set_shader_parameter("use_picture", true)
	var mesh := st.commit()
	mesh.surface_set_material(0, m)
	var mi := _add_mesh(node_name, mesh, Transform3D())
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED


## "EXIT" in white on green, in a 5 x 7 pixel face, drawn here (no font, nothing borrowed).
static func _exit_picture() -> Texture2D:
	var glyphs := {
		"E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
		"X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
		"I": ["111", "010", "010", "010", "010", "010", "111"],
		"T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
	}
	var img := Image.create_empty(27, 11, false, Image.FORMAT_RGB8)
	img.fill(Color(0.03, 0.55, 0.22))
	var x := 3
	for ch in "EXIT":
		var rows: Array = glyphs[ch]
		for y in rows.size():
			var line: String = rows[y]
			for i in line.length():
				if line[i] == "1":
					img.set_pixel(x + i, 2 + y, Color(0.95, 1.0, 0.95))
		x += (rows[0] as String).length() + 1
	var tex := ImageTexture.create_from_image(img)
	return tex


## The booth seen through its windows: left half the projector's port (the lens, bright, in a dim booth), right
## half a viewing port (the dim booth).
static func _booth_picture() -> Texture2D:
	var img := Image.create_empty(128, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 128:
			var u := float(x % 64) / 63.0
			var v := float(y) / 63.0
			# A dim booth, warmer near its lamp above.
			var c := Color(0.035, 0.03, 0.035).lerp(Color(0.09, 0.07, 0.05), clampf(1.0 - v, 0.0, 1.0) * 0.6)
			if x < 64:
				var d := Vector2((u - 0.5) * 1.75, v - 0.5).length()
				var lens := exp(-d * d / 0.004) * 1.0 + exp(-d * d / 0.03) * 0.25
				c = c.lerp(Color(1.0, 0.96, 0.88), clampf(lens, 0.0, 1.0))
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


func _add_mesh(node_name: String, mesh: Mesh, xform: Transform3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.transform = xform
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


# --- Bake hooks ----------------------------------------------------------------------------------------------------

func bake_lights() -> Node3D:
	return get_node("BakeLights") as Node3D


## The meshes a lightmap bake covers (gi_mode static, with UV2).
func static_meshes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for n in get_children():
		if n is MeshInstance3D and (n as MeshInstance3D).gi_mode == GeometryInstance3D.GI_MODE_STATIC:
			out.append(n)
	return out


## While LightmapGI.bake() renders the surfaces: their colour at the designed level only, the lamps' glow as it is.
func set_baking(on: bool) -> void:
	_baking = on
	for m in _static_materials + _seat_materials + _lamp_materials:
		m.set_shader_parameter("bake_pass", on)


## A lightmap is on the room (or gone again): the static surfaces drop the stand-in lamps and most of the fill.
func set_baked(on: bool) -> void:
	_baked = on
	_place_lamps()
	for m in _static_materials:
		_set_fill(m, BAKED_FILL if on else 1.0)


func is_baked() -> bool:
	return _baked


func _on_child_entered(n: Node) -> void:
	if n is LightmapGI:
		_lightmap = n


func _on_child_exiting(n: Node) -> void:
	if n == _lightmap:
		_lightmap = null


## The stand-in lamps' places in the world (the room moves when a seat is chosen); none on baked surfaces.
func _place_lamps() -> void:
	if not is_inside_tree():
		return
	var pos := PackedVector4Array()
	var col := PackedVector4Array()
	for l: Array in _lamps:
		var p: Vector3 = global_transform * Vector3(l[0])
		var c: Color = l[1]
		pos.append(Vector4(p.x, p.y, p.z, LAMP_RANGE))
		col.append(Vector4(c.r, c.g, c.b, float(l[2])))
	while pos.size() < 8:
		pos.append(Vector4.ZERO)
		col.append(Vector4.ZERO)
	for m in _static_materials + _seat_materials:
		var live := not (_baked and m in _static_materials)
		m.set_shader_parameter("lamp_position", pos)
		m.set_shader_parameter("lamp_colour", col)
		m.set_shader_parameter("lamp_count", _lamps.size() if live else 0)


# --- Following the screen and the seat -------------------------------------------------------------------------------

func on_screen_changed(screen_transform: Transform3D, size: Vector2) -> void:
	var main := _find_main()
	_screen_world = (main.global_transform if main != null and main.is_inside_tree() else Transform3D()) \
			* screen_transform
	_screen_size = size
	_fit_to_screen()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_place_lamps()
		_fit_to_screen()
		_hide_occupied_seat()


func _fit_to_screen() -> void:
	if _border == null or _screen_size == Vector2.ZERO or not is_inside_tree():
		return
	var local := global_transform.affine_inverse() * _screen_world
	(_border.mesh as QuadMesh).size = _screen_size + Vector2(0.5, 0.5)
	_border.transform = local.translated_local(Vector3(0, 0, -0.03))
	_shape_beam(local)


## The beam: four sides from the lens to the screen's edges (UV.y along it, 0 at the lens; UV2.x across a side).
func _shape_beam(screen: Transform3D) -> void:
	var corners: Array[Vector3] = []
	for c: Vector2 in [Vector2(-0.5, 0.5), Vector2(0.5, 0.5), Vector2(0.5, -0.5), Vector2(-0.5, -0.5)]:
		corners.append(screen * Vector3(c.x * _screen_size.x, c.y * _screen_size.y, 0.0) - LENS)
	var key := str(corners)
	if key == _beam_key:
		return
	_beam_key = key
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 4:
		var p := corners[i]
		var q := corners[(i + 1) % 4]
		for v: Array in [[Vector3.ZERO, 0.0, 0.5], [p, 1.0, 0.0], [q, 1.0, 1.0]]:
			st.set_uv(Vector2(0.0, v[1]))
			st.set_uv2(Vector2(v[2], 0.0))
			st.add_vertex(v[0])
	_beam.mesh = st.commit()


## The seat the viewer sits in (the room moved so it is at the origin) is folded away; the others are all there.
func _hide_occupied_seat() -> void:
	if _seats == null or not is_inside_tree():
		return
	var here := global_transform.affine_inverse() * Vector3.ZERO
	var found := -1
	for i in _seat_xforms.size():
		var o := _seat_xforms[i].origin
		if Vector2(o.x - here.x, o.z - here.z).length() < 0.2 and absf(o.y - here.y) < 0.2:
			found = i
			break
	if found == _hidden_seat:
		return
	var mm := _seats.multimesh
	if _hidden_seat >= 0:
		mm.set_instance_transform(_hidden_seat, _seat_xforms[_hidden_seat])
	if found >= 0:
		mm.set_instance_transform(found, _seat_xforms[found].scaled_local(Vector3.ZERO))
	_hidden_seat = found


func _process(_delta: float) -> void:
	var has := _lightmap != null and (_lightmap as LightmapGI).light_data != null
	if has != _lightmap_seen:
		_lightmap_seen = has
		set_baked(has)
	var on := true
	var main := _find_main()
	if main != null:
		on = main.player.is_playing() and main.screen.is_shown() and not main.mode.is_spherical()
		var projector: Node = main.features.get("projector") if main.get("features") != null else null
		if projector != null and projector.beam_applies():
			on = false
	_beam_root.visible = on


## The app's main node (scenes/main.tscn), the room's ancestor; null when the room stands alone (tests, tools).
func _find_main() -> Node:
	if _main != null and is_instance_valid(_main):
		return _main
	var n := get_parent()
	while n != null:
		if n.get("player") != null and n.get("screen") != null and n.has_method("set_environment"):
			_main = n
			return n
		n = n.get_parent()
	return null
