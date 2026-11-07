extends "res://scripts/env/systems/env_system.gd"

## The auditorium builder (docs/environments.md, "The auditorium builder"): a stadium-seated hall from parameters.
## Its defaults are the cinema (app/environments/cinema.env.json), moved here from environments/cinema.gd, which
## built the same room as code. The viewer sits in the middle of row 0 at the origin; rows in front step down (so seat
## backs never cover the screen: row_rise per row_depth keeps every seat back under the sight line from the seated
## eyes to the bottom of the default screen), rows behind step up. The rows curve toward the screen (arcs round a
## point row_radius ahead of the viewer; 0: straight rows).
##
## What it builds (node names; the static parts are ArrayMeshes in room coordinates, gi_mode static, with their own
## lightmap UV2 from scripts/env/room_mesh.gd, no xatlas):
##   Floor        the carpeted tiers, their risers, the side aisles' steps (two a row), the pit and the rear walkway
##   Walls        side and rear walls, FrontWall (behind the screen), Ceiling (with acoustic clouds; ceiling_cover
##                under 1 leaves the back of it open to the sky)
##   WallPanels   fabric panels on the side walls and the rear wall, with wooden rails (wall_treatment "panels")
##   Stage, Curtains (proscenium "drapes": pleated velvet either side and a valance), Doors (exits with frames and
##   push bars, the booth's window frames), Brass (the sconces' plates, the aisle handrails)
##   Seats        seats_per_row x rows modelled seats in one MultiMesh (instance colour: a slight tint per seat)
##   HouseLamps, StepLights, StageLight, ExitSigns, BoothWindow   the light sources' own glow (the light system's
##                lamp materials, by group)
##   Balcony, Boxes, Partition    when balcony_rows, boxes_per_side, partition_z ask for them
## The bake lights (sconces up and down, house lights, step lights, exit signs) go to the light system.

const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const PhysicsShapes := preload("res://scripts/play/physics_shapes.gd")

## Object physics (collision_shapes()): the walls' boxes this thick, the tiers in this many blocks along their arc,
## and a seat's two boxes in its own frame (the seat's floor point at the origin, facing -Z): the cushion with its
## standards and pedestal down to the floor, and the back, turned with it. The stadium seat model's.
const WALL_THICKNESS := 1.0
const TIER_SEGMENTS := 8
const SEAT_BOX_CENTRE := Vector3(0.0, 0.24, -0.05)
const SEAT_BOX_SIZE := Vector3(0.55, 0.48, 0.52)
const SEAT_BACK_PIVOT := Vector3(0.0, 0.42, 0.2)
const SEAT_BACK_TILT_DEG := 13.0
const SEAT_BACK_CENTRE := Vector3(0.0, 0.35, 0.03)
const SEAT_BACK_SIZE := Vector3(0.52, 0.72, 0.14)
## Straight rows: arcs this large.
const STRAIGHT_RADIUS := 100000.0
## The seat models a hall of rows takes (scripts/env/systems/seats.gd SINGLE_MODELS): the stadium seat is drawn here
## (seat_mesh()), the others by the seats system's models.
const SEAT_MODELS: Array[String] = ["stadium", "folding_chair", "plush", "multiplex", "club_chair", "director",
		"cushion", "bean_bag"]
const SEATS := "res://scripts/env/systems/seats.gd"


static func spec() -> Dictionary:
	return {
		"kind": "builder",
		"description": "A stadium-seated hall: rows on a rake (curved or straight), modelled seats, side aisles with "
				+ "steps, side and rear walls with fabric panels, a stage and a proscenium, the screen wall, a "
				+ "ceiling with acoustic clouds (or open to the sky), the house and step lights, exits and the "
				+ "projection booth; a balcony, boxes and a partition wall when asked for. Its defaults are the cinema.",
		"params": PARAMS,
		"requires": ["light"],
		"provides": ["seats", "collision", "sound_room", "bake"],
		"cost": {"draws": 20, "triangles": 130000, "lights": 0, "particles": 0, "texture_mb": 48},
	}


const PARAMS := {
	"room_min": {"type": "vec3", "min": -200.0, "max": 200.0, "default": [-9.6, -3.0, -14.5],
			"description": "the hall's corner: x left wall, y the pit's floor, z the screen wall"},
	"room_max": {"type": "vec3", "min": -200.0, "max": 200.0, "default": [9.6, 9.0, 6.2],
			"description": "the hall's other corner: x right wall, y the ceiling, z the rear wall"},
	"rows_front": {"type": "int", "min": 0, "max": 30, "default": 7, "description": "rows in front of the viewer's"},
	"rows_back": {"type": "int", "min": 0, "max": 30, "default": 3, "description": "rows behind the viewer's"},
	"row_depth": {"type": "float", "min": 0.7, "max": 3.0, "default": 1.3, "description": "metres a row, front to back"},
	"row_rise": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.35,
			"description": "the rake: how much higher each row is than the one in front"},
	"seats_per_row": {"type": "int", "min": 1, "max": 61, "default": 27,
			"description": "seats along a row (an odd count puts one in the middle: the viewer's)"},
	"seat_pitch": {"type": "float", "min": 0.45, "max": 1.2, "default": 0.58, "description": "seat centres, metres"},
	"row_radius": {"type": "float", "min": 0.0, "max": 500.0, "default": 45.0,
			"description": "rows curve round a point this far ahead; 0: straight rows"},
	"block_x": {"type": "float", "min": 0.5, "max": 100.0, "default": 8.1,
			"description": "the seats' block reaches this far either side; the side aisles go on to the walls"},
	"row_segments": {"type": "int", "min": 2, "max": 64, "default": 24, "description": "the tiers' arcs, in pieces"},
	"seat_model": {"type": "enum", "values": SEAT_MODELS, "default": "stadium",
			"description": "the seat: stadium, or a model of the seats system (plush, multiplex, folding_chair, ...)"},
	"seat_upholstery": {"type": "material", "default": {"library": "velvet", "color": [0.376, 0.092, 0.11],
			"tiling": 0.22}, "description": "the seats' cushion and back"},
	"seat_shell": {"type": "material", "default": {"library": "black_leather", "color": [0.08, 0.075, 0.078]},
			"description": "the seats' arms, standards and pedestal"},
	"seat_variation": {"type": "float", "min": 0.0, "max": 2.0, "default": 1.0,
			"description": "how much one seat's colour differs from the next (faded and replaced velvet)"},
	"seat_seed": {"type": "int", "min": 0, "max": 1000000, "default": 1907, "description": "the seats' tints' seed"},
	"wall_treatment": {"type": "enum", "values": ["panels", "plain"], "default": "panels",
			"description": "the side and rear walls: fabric panels with wooden rails, or plain"},
	"proscenium": {"type": "enum", "values": ["drapes", "none"], "default": "drapes",
			"description": "round the screen: velvet drapes either side and a valance, or nothing"},
	"stage_depth": {"type": "float", "min": 0.0, "max": 10.0, "default": 1.9, "description": "the stage, metres deep"},
	"stage_top": {"type": "float", "min": -20.0, "max": 5.0, "default": -2.1, "description": "the stage's top"},
	"curtain_width": {"type": "float", "min": 0.5, "max": 10.0, "default": 2.2, "description": "each drape's width"},
	"panels": {"type": "int", "min": 1, "max": 20, "default": 7, "description": "fabric panels along each side wall"},
	"panel_from": {"type": "float", "min": -200.0, "max": 200.0, "default": -9.6, "description": "the panels' front z"},
	"panel_to": {"type": "float", "min": -200.0, "max": 200.0, "default": 6.0, "description": "the panels' back z"},
	"panel_top": {"type": "float", "min": 0.0, "max": 50.0, "default": 7.6, "description": "the panels' top"},
	"panel_gap": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.16, "description": "between panels"},
	"sconce_joints": {"type": "list", "of": {"type": "int", "min": 0, "max": 20}, "max": 8, "default": [1, 3, 5],
			"description": "the panel joints a sconce hangs at, each side"},
	"sconce_height": {"type": "float", "min": 0.5, "max": 10.0, "default": 2.5,
			"description": "a sconce's height over the aisle"},
	"door_size": {"type": "vec2", "min": 0.5, "max": 5.0, "default": [1.8, 2.35], "description": "an exit's size"},
	"doors": {"type": "bool", "default": true, "description": "four exits with signs over them"},
	"booth": {"type": "bool", "default": true, "description": "the projection booth's windows in the rear wall"},
	"lens": {"type": "vec3", "min": -200.0, "max": 200.0, "default": [0.0, 3.45, 6.15],
			"description": "the projector's lens, in the booth's window"},
	"cloud_drop": {"type": "float", "min": 0.0, "max": 5.0, "default": 0.7,
			"description": "the acoustic clouds hang this far under the ceiling"},
	"clouds": {"type": "list", "of": {"type": "float", "min": -200.0, "max": 200.0}, "max": 8,
			"default": [-9.0, -3.5, 2.0], "description": "the acoustic clouds' z"},
	"ceiling_cover": {"type": "float", "min": 0.0, "max": 1.0, "default": 1.0,
			"description": "the ceiling's share from the front: under 1, the back is open to the sky"},
	"balcony_rows": {"type": "int", "min": 0, "max": 8, "default": 0, "description": "a balcony over the rear"},
	"balcony_height": {"type": "float", "min": 2.0, "max": 20.0, "default": 3.4,
			"description": "the balcony's floor over the rear walkway"},
	"boxes_per_side": {"type": "int", "min": 0, "max": 6, "default": 0, "description": "boxes on each side wall"},
	"box_height": {"type": "float", "min": 1.0, "max": 20.0, "default": 3.0, "description": "the boxes' floor"},
	"partition_z": {"type": "float", "min": -200.0, "max": 0.0, "default": 0.0,
			"description": "a plain wall across the hall at this z (a subdivided hall); 0: none"},
	"house_lamp_colour": {"type": "color", "default": [1.0, 0.72, 0.45], "description": "the house lamps' glow"},
	"step_colour": {"type": "color", "default": [1.0, 0.62, 0.3], "description": "the step lights' glow"},
	"floor": {"type": "material", "default": {"library": "woven_carpet", "color": [0.3, 0.12, 0.11], "tiling": 0.9},
			"description": "the tiers, aisles, pit and walkway"},
	"walls": {"type": "material", "default": {"library": "felt", "color": [0.17, 0.15, 0.16]},
			"description": "the side and rear walls"},
	"front_wall": {"type": "material", "default": {"library": "felt", "color": [0.04, 0.035, 0.04], "spill": 1.0},
			"description": "the wall behind the screen"},
	"ceiling": {"type": "material", "default": {"library": "acoustic_foam", "color": [0.2, 0.19, 0.2],
			"tiling": 1.2}, "description": "the ceiling and its clouds"},
	"panel_fabric": {"type": "material", "default": {"library": "felt", "color": [0.38, 0.15, 0.12], "tiling": 0.6},
			"description": "the wall panels"},
	"panel_wood": {"type": "material", "default": {"library": "walnut_veneer", "color": [0.3, 0.19, 0.12]},
			"description": "the panels' rails"},
	"stage": {"type": "material", "default": {"library": "red_hardwood", "color": [0.36, 0.22, 0.15]},
			"description": "the stage"},
	"curtains": {"type": "material", "default": {"library": "velvet", "color": [0.45, 0.05, 0.07], "pleats": 3.0,
			"pleat_depth": 0.6}, "description": "the drapes"},
	"door_leaf": {"type": "material", "default": {"library": "walnut_veneer", "color": [0.25, 0.15, 0.1]},
			"description": "the doors"},
	"door_metal": {"type": "material", "default": {"library": "brushed_steel", "color": [0.45, 0.45, 0.46]},
			"description": "the door frames, push bars and kick plates"},
	"brass": {"type": "material", "default": {"library": "brass", "color": [0.55, 0.42, 0.22]},
			"description": "the sconces' plates and the handrails"},
	"partition": {"type": "material", "default": {"library": "felt", "color": [0.6, 0.58, 0.55]},
			"description": "the partition wall"},
}


## The hall's layout from parameters: rows, arcs, the aisles' floor, the seats. Static parts of the builder that the
## cinema's script (and its tests) read without building.
class Layout:
	var lo: Vector3
	var hi: Vector3
	var rows_front: int
	var rows_back: int
	var depth: float
	var rise: float
	var per_row: int
	var pitch: float
	var radius: float
	var block_x: float

	func _init(p: Dictionary) -> void:
		lo = _v3(p["room_min"])
		hi = _v3(p["room_max"])
		rows_front = int(p["rows_front"])
		rows_back = int(p["rows_back"])
		depth = float(p["row_depth"])
		rise = float(p["row_rise"])
		per_row = int(p["seats_per_row"])
		pitch = float(p["seat_pitch"])
		radius = float(p["row_radius"]) if float(p["row_radius"]) > 0.0 else STRAIGHT_RADIUS
		block_x = float(p["block_x"])

	static func _v3(v: Variant) -> Vector3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))

	func row_floor(row: int) -> float:
		return -rise * row

	## The radius of a row's centre line (where the seated eyes are).
	func row_radius(row: int) -> float:
		return radius - depth * row

	## z of the arc of this radius at x (the arcs' centre is `radius` ahead).
	func arc_z(r: float, x: float) -> float:
		return -radius + sqrt(maxf(r * r - x * x, 0.0))

	## The floor's height along the side aisles at z: the pit, two steps a row, the rear walkway.
	func aisle_floor(z: float) -> float:
		for row in range(rows_front, -rows_back - 1, -1):
			var front := arc_z(row_radius(row) - depth * 0.5, block_x)
			var back := arc_z(row_radius(row) + depth * 0.5, block_x)
			if z < front:
				return lo.y if row == rows_front else row_floor(row + 1)
			if z < (front + back) * 0.5:
				return row_floor(row) - rise * 0.5
			if z < back:
				return row_floor(row)
		return row_floor(-rows_back)

	## Every seat of the rows: the floor point under the seated eyes and the seat's facing (toward the rows' centre),
	## by row from the back, left to right. Row 0's middle seat is the viewer's own, at the origin.
	func seat_transforms() -> Array[Transform3D]:
		var out: Array[Transform3D] = []
		var half := (per_row - 1) / 2
		for row in range(-rows_back, rows_front + 1):
			var r := row_radius(row)
			for k in range(-half, per_row - half):
				var a := k * pitch / r
				out.append(Transform3D(Basis(Vector3.UP, a), Vector3(r * sin(a), row_floor(row), -radius + r * cos(a))))
		return out


static func layout(p: Dictionary) -> Layout:
	return Layout.new(p)


var L: Layout
var _seats: MultiMeshInstance3D
var _seat_xforms: Array[Transform3D] = []
var _hidden_seat := -1
var _light: Node


func setup() -> void:
	L = Layout.new(params)
	_light = host.system_of_kind("light")
	_build_floor()
	_build_shell()
	if str(params["wall_treatment"]) == "panels":
		_build_wall_panels()
	_build_front()
	if bool(params["doors"]) or bool(params["booth"]):
		_build_doors_and_booth()
	_build_fixtures()
	if int(params["balcony_rows"]) > 0:
		_build_balcony()
	if int(params["boxes_per_side"]) > 0:
		_build_boxes()
	if float(params["partition_z"]) < 0.0:
		_build_partition()
	_build_seats()
	_build_bake_lights()


func _mat(param: String, instanced := false) -> ShaderMaterial:
	return _light.from_param(params[param], instanced)


func _v3(param: String) -> Vector3:
	return Layout._v3(params[param])


func lens() -> Vector3:
	return _v3("lens")


# --- Hooks ------------------------------------------------------------------------------------------------------------

func seats() -> Array[Transform3D]:
	return _all_seats()


func _all_seats() -> Array[Transform3D]:
	var out := L.seat_transforms()
	out.append_array(_balcony_seats())
	return out


## Spatial audio: the walls; the document's acoustics give the rest.
func sound_room() -> Dictionary:
	return {"box": AABB(L.lo, L.hi - L.lo), "surround_height": 4.0, "array": 3, "array_spacing": 3.0}


## Object physics (scripts/play/object_physics.gd, docs/physics.md): the room as cheap boxes, [[Shape3D, Transform3D]]
## in its own frame. A slab under the floor, the walls and the ceiling (outside the room), the stage, each row's tier as
## TIER_SEGMENTS solid blocks along its arc (down to the pit's floor), the side aisles' steps, the rear walkway, and two
## boxes a seat: the cushion with its standards, and the tilted back. The seats share two shapes.
static func collision_shapes_for(p: Dictionary) -> Array:
	var l := Layout.new(p)
	var out: Array = []
	var lo := l.lo
	var hi := l.hi
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
	var stage_depth := float(p["stage_depth"])
	var stage_h := float(p["stage_top"]) - lo.y
	if stage_depth > 0.0 and stage_h > 0.0:
		out.append(PhysicsShapes.box(Vector3(0.0, lo.y + stage_h * 0.5, lo.z + stage_depth * 0.5),
				Vector3(size.x, stage_h, stage_depth)))
	for row in range(-l.rows_back, l.rows_front + 1):
		var r := l.row_radius(row)
		var top := l.row_floor(row)
		var h := top - lo.y
		if h <= 0.01:
			continue
		var reach := asin(clampf(l.block_x / (r + l.depth * 0.5), -1.0, 1.0))
		for i in TIER_SEGMENTS:
			var a0 := lerpf(-reach, reach, float(i) / TIER_SEGMENTS)
			var a1 := lerpf(-reach, reach, float(i + 1) / TIER_SEGMENTS)
			var a := (a0 + a1) * 0.5
			# The back edge's chord is the widest: the blocks meet there and overlap a little in front.
			var chord := 2.0 * (r + l.depth * 0.5) * sin((a1 - a0) * 0.5) * 1.02
			out.append(PhysicsShapes.box(Vector3(r * sin(a), lo.y + h * 0.5, -l.radius + r * cos(a)),
					Vector3(chord, h, l.depth), Basis(Vector3.UP, a)))
		# The side aisles: two steps a row, straight across to the wall.
		var zf := l.arc_z(r - l.depth * 0.5, l.block_x)
		var zb := l.arc_z(r + l.depth * 0.5, l.block_x)
		var zm := (zf + zb) * 0.5
		var low := top - l.rise * 0.5
		var aisle_w := hi.x - l.block_x
		if aisle_w <= 0.01:
			continue
		for s: float in [-1.0, 1.0]:
			var x := s * (l.block_x + aisle_w * 0.5)
			out.append(PhysicsShapes.box(Vector3(x, lo.y + h * 0.5, (zm + zb) * 0.5), Vector3(aisle_w, h, zb - zm)))
			if low - lo.y > 0.01:
				out.append(PhysicsShapes.box(Vector3(x, (lo.y + low) * 0.5, (zf + zm) * 0.5),
						Vector3(aisle_w, low - lo.y, zm - zf)))
	# The rear walkway: level with the back row, from the back row's arc at the aisles to the rear wall.
	var walk := l.row_floor(-l.rows_back)
	var walk_from := l.arc_z(l.row_radius(-l.rows_back) + l.depth * 0.5, l.block_x)
	if walk - lo.y > 0.01 and hi.z - walk_from > 0.01:
		out.append(PhysicsShapes.box(Vector3(mid.x, (lo.y + walk) * 0.5, (walk_from + hi.z) * 0.5),
				Vector3(size.x, walk - lo.y, hi.z - walk_from)))
	var cushion := BoxShape3D.new()
	cushion.size = SEAT_BOX_SIZE
	var back := BoxShape3D.new()
	back.size = SEAT_BACK_SIZE
	var tilt := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(SEAT_BACK_TILT_DEG)), SEAT_BACK_PIVOT)
	var back_xf := Transform3D(tilt.basis, tilt * SEAT_BACK_CENTRE)
	var all := l.seat_transforms()
	all.append_array(_balcony_seats_for(p, l))
	# Another seat model's own boxes (seats.gd model_boxes(): a club chair or a bean bag is wider than the stadium seat).
	var model := str(p.get("seat_model", "stadium"))
	var seats_script: GDScript = load(SEATS) if model != "stadium" else null
	for st in all:
		if seats_script != null:
			out.append_array(seats_script.call("model_boxes", model, st))
			continue
		out.append([cushion, st * Transform3D(Basis(), SEAT_BOX_CENTRE)])
		out.append([back, st * back_xf])
	for b: Array in _balcony_boxes(p, l):
		out.append(PhysicsShapes.box(b[0], b[1]))
	return out


func collision_shapes() -> Array:
	return collision_shapes_for(params)


# --- Building ---------------------------------------------------------------------------------------------------------

func _build_floor() -> void:
	var b := RoomMesh.new()
	b.surface(_mat("floor"))
	var xs: Array[float] = []
	var segments := int(params["row_segments"])
	for i in segments + 1:
		xs.append(lerpf(-L.block_x, L.block_x, float(i) / segments))
	for row in range(-L.rows_back, L.rows_front + 1):
		var y := L.row_floor(row)
		var below := L.lo.y if row == L.rows_front else L.row_floor(row + 1)
		var r_front := L.row_radius(row) - L.depth * 0.5
		var r_back := L.row_radius(row) + L.depth * 0.5
		var front := PackedVector3Array()
		var back := PackedVector3Array()
		var low := PackedVector3Array()
		var ups := PackedVector3Array()
		var faces := PackedVector3Array()
		for x in xs:
			var zf := L.arc_z(r_front, x)
			front.append(Vector3(x, y, zf))
			back.append(Vector3(x, y, L.arc_z(r_back, x)))
			low.append(Vector3(x, below, zf))
			ups.append(Vector3.UP)
			faces.append(Vector3(-x, 0.0, -L.radius - zf).normalized())
		b.strip(front, back, ups)
		b.strip(low, front, faces)
		# The side aisles: two steps a row, straight across to the wall.
		var zf := L.arc_z(r_front, L.block_x)
		var zb := L.arc_z(r_back, L.block_x)
		var zm := (zf + zb) * 0.5
		var mid := y - L.rise * 0.5
		if L.hi.x - L.block_x <= 0.01:
			continue
		for s: float in [-1.0, 1.0]:
			var x0 := L.block_x * s
			var x1 := L.hi.x * s
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
	var edge_x: Array[float] = [L.lo.x]
	edge_x.append_array(xs)
	edge_x.append(L.hi.x)
	var pit_a := PackedVector3Array()
	var pit_b := PackedVector3Array()
	var walk_a := PackedVector3Array()
	var walk_b := PackedVector3Array()
	var ups := PackedVector3Array()
	var top := L.row_floor(-L.rows_back)
	for x in edge_x:
		var cx := clampf(x, -L.block_x, L.block_x)
		pit_a.append(Vector3(x, L.lo.y, L.lo.z + float(params["stage_depth"])))
		pit_b.append(Vector3(x, L.lo.y, L.arc_z(L.row_radius(L.rows_front) - L.depth * 0.5, cx)))
		walk_a.append(Vector3(x, top, L.arc_z(L.row_radius(-L.rows_back) + L.depth * 0.5, cx)))
		walk_b.append(Vector3(x, top, L.hi.z))
		ups.append(Vector3.UP)
	b.strip(pit_a, pit_b, ups)
	b.strip(walk_a, walk_b, ups)
	_add_static("Floor", b)


func _build_shell() -> void:
	var lo := L.lo
	var hi := L.hi
	var walls := RoomMesh.new()
	walls.surface(_mat("walls"))
	for s: float in [-1.0, 1.0]:
		var x := hi.x * s
		walls.face([Vector3(x, lo.y, lo.z), Vector3(x, lo.y, hi.z), Vector3(x, hi.y, hi.z), Vector3(x, hi.y, lo.z)],
				Vector3(-s, 0.0, 0.0))
	var walk := L.row_floor(-L.rows_back)
	walls.face([Vector3(lo.x, walk, hi.z), Vector3(hi.x, walk, hi.z), Vector3(hi.x, hi.y, hi.z),
			Vector3(lo.x, hi.y, hi.z)], Vector3.FORWARD)
	_add_static("Walls", walls)
	var front := RoomMesh.new()
	front.surface(_mat("front_wall"))
	front.face([Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z),
			Vector3(lo.x, hi.y, lo.z)], Vector3.BACK)
	_add_static("FrontWall", front)
	var cover := float(params["ceiling_cover"])
	if cover <= 0.0:
		return
	var ceiling := RoomMesh.new()
	ceiling.surface(_mat("ceiling"))
	var end_z := lerpf(lo.z, hi.z, cover)
	ceiling.face([Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, end_z),
			Vector3(lo.x, hi.y, end_z)], Vector3.DOWN)
	# Acoustic clouds hung below it over the seats: a sense of the ceiling's height.
	for z: float in _cloud_z():
		if z + 1.3 <= end_z:
			ceiling.box(Vector3(0.0, hi.y - float(params["cloud_drop"]), z), Vector3(12.0, 0.18, 2.6), Basis(),
					[RoomMesh.UP])
	_add_static("Ceiling", ceiling)


func _cloud_z() -> Array[float]:
	var out: Array[float] = []
	for z: Variant in params["clouds"]:
		out.append(float(z))
	return out


## The side walls' fabric panels, from above the aisle floor at their back edge to panel_top, with a wooden rail
## under and over each.
func _build_wall_panels() -> void:
	var b := RoomMesh.new()
	var fabric := _mat("panel_fabric")
	var wood := _mat("panel_wood")
	var panels := int(params["panels"])
	var from := float(params["panel_from"])
	var to := float(params["panel_to"])
	var top := float(params["panel_top"])
	var gap := float(params["panel_gap"])
	var pitch := (to - from) / panels
	for s: float in [-1.0, 1.0]:
		var x := L.hi.x * s
		for i in panels:
			var z0 := from + i * pitch + gap * 0.5
			var z1 := z0 + pitch - gap
			var bottom := L.aisle_floor(z1 - 0.01) + 1.05
			var centre := Vector3(x - s * 0.04, (bottom + top) * 0.5, (z0 + z1) * 0.5)
			b.surface(fabric)
			b.box(centre, Vector3(0.08, top - bottom, z1 - z0), Basis(), [Vector3(s, 0, 0)])
			b.surface(wood)
			for y: float in [bottom - 0.05, top + 0.05]:
				b.box(Vector3(x - s * 0.06, y, (z0 + z1) * 0.5), Vector3(0.12, 0.1, pitch), Basis(),
						[Vector3(s, 0, 0)])
	# The rear wall: two panels either side, between the booth's windows and the doors.
	var walk := L.row_floor(-L.rows_back)
	var bottom := walk + 1.05
	for s: float in [-1.0, 1.0]:
		for i in 2:
			var x0 := s * (2.3 + i * 2.25)
			var x1 := x0 + s * (2.25 - gap)
			var centre := Vector3((x0 + x1) * 0.5, (bottom + top) * 0.5, L.hi.z - 0.04)
			b.surface(fabric)
			b.box(centre, Vector3(absf(x1 - x0), top - bottom, 0.08), Basis(), [RoomMesh.BACK])
			b.surface(wood)
			for y: float in [bottom - 0.05, top + 0.05]:
				b.box(Vector3(centre.x, y, L.hi.z - 0.06), Vector3(2.25, 0.1, 0.12), Basis(), [RoomMesh.BACK])
	_add_static("WallPanels", b)


func _build_front() -> void:
	var stage_depth := float(params["stage_depth"])
	var stage_top := float(params["stage_top"])
	var h := stage_top - L.lo.y
	if stage_depth > 0.0 and h > 0.0:
		var stage := RoomMesh.new()
		stage.surface(_mat("stage"))
		stage.box(Vector3(0.0, L.lo.y + h * 0.5, L.lo.z + stage_depth * 0.5),
				Vector3(L.hi.x - L.lo.x, h, stage_depth), Basis(),
				[RoomMesh.LEFT, RoomMesh.RIGHT, RoomMesh.DOWN, RoomMesh.FRONT])
		_add_static("Stage", stage)
	if str(params["proscenium"]) != "drapes":
		return
	# Curtains on the front wall either side, beyond the widest screen, and a valance across the top: pleated velvet
	# (folds from the shader).
	var curtains := RoomMesh.new()
	curtains.surface(_mat("curtains"))
	var width := float(params["curtain_width"])
	var height := L.hi.y - stage_top
	for s: float in [-1.0, 1.0]:
		curtains.box(Vector3(s * (L.hi.x - width * 0.5), stage_top + height * 0.5, L.lo.z + 0.1),
				Vector3(width, height, 0.14), Basis(), [RoomMesh.FRONT, RoomMesh.UP, RoomMesh.DOWN])
	curtains.box(Vector3(0.0, L.hi.y - 0.6, L.lo.z + 0.25), Vector3(L.hi.x * 2.0 - 0.2, 1.2, 0.14),
			Basis(), [RoomMesh.FRONT, RoomMesh.UP])
	_add_static("Curtains", curtains)


## The exits (two at the front on the side walls, two at the back on the rear walkway) and the booth's windows.
func _build_doors_and_booth() -> void:
	var b := RoomMesh.new()
	var leaf := _mat("door_leaf")
	var metal := _mat("door_metal")
	var ds := _door_size()
	for d in _doors():
		var at: Vector3 = d[0]
		var basis: Basis = d[1]
		var w := ds.x
		var h := ds.y
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
	if not bool(params["doors"]):
		b.surface(metal)
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


func _door_size() -> Vector2:
	var v: Array = params["door_size"]
	return Vector2(float(v[0]), float(v[1]))


## [bottom centre, basis (x along the wall, z out into the room)] of each exit door.
func _doors() -> Array:
	if not bool(params["doors"]):
		return []
	var front_z := (L.lo.z + float(params["stage_depth"]) + L.arc_z(L.row_radius(L.rows_front) - L.depth * 0.5,
			L.block_x)) * 0.5
	var walk := L.row_floor(-L.rows_back)
	var out: Array = []
	for s: float in [-1.0, 1.0]:
		var into := Vector3(-s, 0.0, 0.0)
		out.append([Vector3(L.hi.x * s, L.lo.y, front_z), Basis(Vector3.UP.cross(into), Vector3.UP, into)])
		out.append([Vector3(s * (L.hi.x - 1.6), walk, L.hi.z), Basis(Vector3.LEFT, Vector3.UP, Vector3.FORWARD)])
	return out


## [centre, size] of the booth's windows: the projector's port round the lens, a viewing port either side.
func _booth_windows() -> Array:
	if not bool(params["booth"]):
		return []
	var lens_at := lens()
	return [[Vector3(lens_at.x, lens_at.y, L.hi.z), Vector2(1.3, 0.75)],
			[Vector3(-1.5, lens_at.y, L.hi.z), Vector2(0.55, 0.4)],
			[Vector3(1.5, lens_at.y, L.hi.z), Vector2(0.55, 0.4)]]


## [position, wall side] of each sconce (room coordinates).
func _sconces() -> Array:
	var out: Array = []
	var panels := int(params["panels"])
	var from := float(params["panel_from"])
	var pitch := (float(params["panel_to"]) - from) / panels
	for s: float in [-1.0, 1.0]:
		for j: Variant in params["sconce_joints"]:
			var z := from + int(j) * pitch
			out.append([Vector3(s * (L.hi.x - 0.13), L.aisle_floor(z) + float(params["sconce_height"]), z), s])
	return out


## Lamps and their fittings: sconces (a brass plate and a glowing shade), ceiling cans, the aisle handrails, the step
## lights, the exit signs and the booth's windows.
func _build_fixtures() -> void:
	var brass := RoomMesh.new()
	brass.surface(_mat("brass"))
	var house := RoomMesh.new()
	house.surface(_light.lamp_material(color_param("house_lamp_colour"), 1.6, 1.0, "house"))
	var lamp: Color = _light.lamp_colour() * float(_light.params["lamp_energy"])
	var cone := cos(deg_to_rad(float(_light.params["lamp_cone_deg"])))
	for sc: Array in _sconces():
		var p: Vector3 = sc[0]
		var s: float = sc[1]
		brass.box(Vector3(s * (L.hi.x - 0.015), p.y, p.z), Vector3(0.03, 0.5, 0.12), Basis(), [Vector3(s, 0, 0)])
		house.box(p, Vector3(0.18, 0.34, 0.14), Basis(), [Vector3(s, 0, 0)])
		_light.add_lamp(p, lamp, cone)
	# Handrails along the side walls, following the aisle's slope.
	var rail_from := Vector3(0.0, L.lo.y + 0.9, L.arc_z(L.row_radius(L.rows_front) - L.depth * 0.5, L.block_x))
	var rail_to := Vector3(0.0, L.row_floor(-L.rows_back) + 0.9, L.arc_z(L.row_radius(-L.rows_back) + L.depth * 0.5,
			L.block_x))
	for s: float in [-1.0, 1.0]:
		var a := rail_from + Vector3(s * (L.hi.x - 0.09), 0.0, 0.0)
		var c := rail_to + Vector3(s * (L.hi.x - 0.09), 0.0, 0.0)
		var dir := (c - a).normalized()
		var across := Vector3.UP.cross(dir).normalized()
		brass.box((a + c) * 0.5, Vector3(0.05, 0.05, a.distance_to(c)), Basis(across, dir.cross(across), dir))
	_add_static("Brass", brass)
	# Ceiling cans (the house lights): two rows under each acoustic cloud, a row on the ceiling at either end.
	var cans: Array[Vector3] = []
	var cover_end := lerpf(L.lo.z, L.hi.z, float(params["ceiling_cover"]))
	for z: float in _cloud_z():
		if z + 1.3 > cover_end:
			continue
		for dz: float in [-0.7, 0.7]:
			for ix in 5:
				cans.append(Vector3(lerpf(-5.0, 5.0, ix / 4.0), L.hi.y - float(params["cloud_drop"]) - 0.095, z + dz))
	for z: float in [L.lo.z + 2.5, L.hi.z - 1.4]:
		if z > cover_end:
			continue
		for ix in 5:
			cans.append(Vector3(lerpf(-5.0, 5.0, ix / 4.0), L.hi.y - 0.005, z))
	for c in cans:
		var corners: Array = []
		for k in 8:
			var a := TAU * k / 8.0
			corners.append(c + Vector3(cos(a), 0.0, sin(a)) * 0.12)
		house.face(corners, Vector3.DOWN)
	_add_lamps("HouseLamps", house)
	# Step lights: a strip on the nose of every aisle step.
	var steps := RoomMesh.new()
	steps.surface(_light.lamp_material(color_param("step_colour"), 1.1, 0.0, "steps"))
	for row in range(-L.rows_back, L.rows_front + 1):
		var zf := L.arc_z(L.row_radius(row) - L.depth * 0.5, L.block_x)
		var zm := (zf + L.arc_z(L.row_radius(row) + L.depth * 0.5, L.block_x)) * 0.5
		for nose: Vector2 in [Vector2(zm, L.row_floor(row)), Vector2(zf, L.row_floor(row) - L.rise * 0.5)]:
			for s: float in [-1.0, 1.0]:
				var x0 := s * (L.block_x + 0.15)
				var x1 := s * (L.hi.x - 0.15)
				var z := nose.x - 0.004
				steps.face([Vector3(x0, nose.y - 0.035, z), Vector3(x1, nose.y - 0.035, z), Vector3(x1, nose.y - 0.01, z),
						Vector3(x0, nose.y - 0.01, z)], Vector3.FORWARD)
	_add_lamps("StepLights", steps)
	# The stage's apron light: a broad, dim band, not a thin bright line. A 3 cm strip at 14 m strobed in the
	# periphery with foveation on (the user, 2026-11-04).
	var stage_top := float(params["stage_top"])
	if float(params["stage_depth"]) > 0.0:
		var sz := L.lo.z + float(params["stage_depth"]) + 0.004
		var apron := RoomMesh.new()
		apron.surface(_light.lamp_material(color_param("step_colour"), 0.4, 0.0, "stage"))
		apron.face([Vector3(L.lo.x, stage_top - 0.12, sz), Vector3(L.hi.x, stage_top - 0.12, sz),
				Vector3(L.hi.x, stage_top - 0.02, sz), Vector3(L.lo.x, stage_top - 0.02, sz)], Vector3.BACK)
		_add_lamps("StageLight", apron)
	# Exit signs over the doors, and the booth's windows: pictures.
	var signs: Array = []
	var ds := _door_size()
	for d in _doors():
		var at: Vector3 = d[0]
		var basis: Basis = d[1]
		signs.append([at + basis * Vector3(0.0, ds.y + 0.4, 0.081), basis.x * 0.25, Vector3.UP * 0.1, basis.z])
	if not signs.is_empty():
		_add_picture("ExitSigns", signs, exit_picture(), Color(1, 1, 1), 1.4, "signs")
	var windows: Array = []
	var booth := _booth_windows()
	for w: Array in booth:
		var c: Vector3 = w[0]
		var size: Vector2 = w[1]
		windows.append([c + Vector3(0, 0, -0.01), Vector3.LEFT * size.x * 0.5, Vector3.UP * size.y * 0.5,
				Vector3.FORWARD, w == booth[0]])
	if not windows.is_empty():
		_add_picture("BoothWindow", windows, booth_picture(), Color(1, 1, 1), 1.0, "booth")


func _build_seats() -> void:
	# A red velvet a third of the way to grey: the full red read as too saturated under the house lights (the user, in
	# the headset, 2026-11-04).
	var velvet := _mat("seat_upholstery", true)
	velvet.set_shader_parameter("instance_tint", true)
	var shell := _mat("seat_shell", true)
	var mesh := seat_mesh(velvet, shell, float(params["seat_pitch"]), str(params["seat_model"]))
	_seat_xforms = _all_seats()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = _seat_xforms.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(params["seat_seed"])
	var k := float(params["seat_variation"])
	for i in _seat_xforms.size():
		mm.set_instance_transform(i, _seat_xforms[i])
		# Velvet fades and is replaced seat by seat: a little lighter or darker, a little warmer or cooler.
		var v := lerpf(0.98, rng.randf_range(0.86, 1.1), k)
		var warm := rng.randf_range(-0.04, 0.04) * k
		mm.set_instance_color(i, Color(v * (1.0 + warm), v, v * (1.0 - warm)))
	_seats = MultiMeshInstance3D.new()
	_seats.name = "Seats"
	_seats.multimesh = mm
	# Read by the checks (a MultiMesh keeps no instances without a renderer).
	_seats.set_meta("instances", _seat_xforms.size())
	_seats.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Not baked (a bake covers MeshInstance3Ds only): lit by the fill, the lamps and the spill, never by the probes.
	_seats.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	own(_seats)


## One seat, its floor point under the seated eyes at the origin, facing -Z: a velvet cushion and back (the back
## curved in plan and tilted) with an outer cover behind it, half an arm rest and half a standard either side (the
## neighbour's halves complete them: a joined row), and a pedestal under the cushion. Another model: the seats
## system's (seats.gd model_mesh()), `pitch` wide.
static func seat_mesh(upholstery: Material, frame: Material, pitch := 0.58, model := "stadium") -> ArrayMesh:
	if model != "stadium":
		return (load(SEATS) as GDScript).call("model_mesh", model, upholstery, frame, pitch, "")
	var b := RoomMesh.new()
	var half := pitch * 0.5
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


## The room's real lights, for a lightmap bake only (the light system hides them).
func _build_bake_lights() -> void:
	var i := 0
	var cone := float(_light.params["lamp_cone_deg"])
	for sc: Array in _sconces():
		var p: Vector3 = sc[0]
		for up: bool in [true, false]:
			var l := SpotLight3D.new()
			l.name = "Sconce%d%s" % [i, "Up" if up else "Down"]
			l.position = p + Vector3(0.0, 0.18 if up else -0.18, 0.0)
			l.rotation = Vector3(PI * 0.5 if up else -PI * 0.5, 0.0, 0.0)
			l.spot_angle = cone
			l.spot_range = 5.0
			l.light_energy = 2.0
			l.light_color = _light.lamp_colour()
			_light.add_bake_light(l)
		i += 1
	i = 0
	for x: float in [-4.0, 4.0]:
		for z: float in [-7.0, 1.0]:
			var l := SpotLight3D.new()
			l.name = "House%d" % i
			l.position = Vector3(x, L.hi.y - 0.2, z)
			l.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
			l.spot_angle = 60.0
			l.spot_range = 16.0
			l.light_energy = 1.2
			l.light_color = Color(1.0, 0.86, 0.7)
			_light.add_bake_light(l)
			i += 1
	i = 0
	for row: int in [6, 2, -2]:
		if row > L.rows_front or row < -L.rows_back:
			continue
		var zf := L.arc_z(L.row_radius(row) - L.depth * 0.5, L.block_x)
		for s: float in [-1.0, 1.0]:
			var l := OmniLight3D.new()
			l.name = "Step%d" % i
			l.position = Vector3(s * (L.block_x + L.hi.x) * 0.5, L.row_floor(row) - 0.05, zf - 0.15)
			l.omni_range = 1.8
			l.light_energy = 0.5
			l.light_color = color_param("step_colour")
			_light.add_bake_light(l)
			i += 1
	i = 0
	var ds := _door_size()
	for d in _doors():
		var at: Vector3 = d[0]
		var basis: Basis = d[1]
		var l := OmniLight3D.new()
		l.name = "Exit%d" % i
		l.position = at + basis * Vector3(0.0, ds.y + 0.4, 0.25)
		l.omni_range = 2.5
		l.light_energy = 0.35
		l.light_color = Color(0.2, 1.0, 0.45)
		_light.add_bake_light(l)
		i += 1


# --- Balcony, boxes, partition -------------------------------------------------------------------------------------------

## The balcony's rows: straight, over the rear, rising to the back; [centre z, floor y] each, front to back.
static func _balcony_rows(p: Dictionary, l: Layout) -> Array:
	var out: Array = []
	var n := int(p["balcony_rows"])
	var base := l.row_floor(-l.rows_back) + float(p["balcony_height"])
	for j in n:
		var z := l.hi.z - (n - j - 0.5) * l.depth
		out.append([z, base + j * l.rise])
	return out


static func _balcony_seats_for(p: Dictionary, l: Layout) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var count := maxi(int(floorf(l.block_x * 2.0 / l.pitch)), 1)
	for row: Array in _balcony_rows(p, l):
		for k in count:
			var x := (k - (count - 1) * 0.5) * l.pitch
			out.append(Transform3D(Basis(), Vector3(x, float(row[1]), float(row[0]))))
	return out


func _balcony_seats() -> Array[Transform3D]:
	return _balcony_seats_for(params, L)


## [centre, size] of the balcony's solid parts: each tier down to the slab, the slab, the parapet.
static func _balcony_boxes(p: Dictionary, l: Layout) -> Array:
	var rows := _balcony_rows(p, l)
	if rows.is_empty():
		return []
	var out: Array = []
	var width := l.hi.x - l.lo.x
	var slab_y := float(rows[0][1])
	for row: Array in rows:
		var h := float(row[1]) - slab_y + 0.3
		out.append([Vector3(0.0, float(row[1]) - h * 0.5, float(row[0])), Vector3(width, h, l.depth)])
	var front_z := float(rows[0][0]) - l.depth * 0.5
	out.append([Vector3(0.0, slab_y + 0.5, front_z - 0.08), Vector3(width, 1.0, 0.16)])
	return out


func _build_balcony() -> void:
	var b := RoomMesh.new()
	b.surface(_mat("floor"))
	for part: Array in _balcony_boxes(params, L):
		b.box(part[0], part[1])
	_add_static("Balcony", b)


func _build_boxes() -> void:
	var b := RoomMesh.new()
	b.surface(_mat("panel_fabric"))
	var n := int(params["boxes_per_side"])
	var y := float(params["box_height"])
	for s: float in [-1.0, 1.0]:
		for i in n:
			var z := lerpf(float(params["panel_from"]) + 2.0, float(params["panel_to"]) - 2.0, (i + 0.5) / n)
			var x := s * (L.hi.x - 0.7)
			b.box(Vector3(x, y - 0.1, z), Vector3(1.4, 0.2, 2.0))
			b.box(Vector3(x - s * 0.65, y + 0.5, z), Vector3(0.1, 1.0, 2.0))
	_add_static("Boxes", b)


func _build_partition() -> void:
	var b := RoomMesh.new()
	b.surface(_mat("partition"))
	var z := float(params["partition_z"])
	b.face([Vector3(L.lo.x, L.lo.y, z), Vector3(L.hi.x, L.lo.y, z), Vector3(L.hi.x, L.hi.y, z),
			Vector3(L.lo.x, L.hi.y, z)], Vector3.BACK)
	_add_static("Partition", b)


# --- Nodes ---------------------------------------------------------------------------------------------------------------

func _add_static(node_name: String, b: RoomMesh) -> MeshInstance3D:
	var mi := _add_mesh(node_name, b.commit(true))
	mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	return mi


func _add_lamps(node_name: String, b: RoomMesh) -> MeshInstance3D:
	var mi := _add_mesh(node_name, b.commit(false))
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return mi


func _add_mesh(node_name: String, mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	own(mi)
	return mi


## Pictures on flat quads: [centre, half across, half up, facing, (optional) bright] each; one mesh, one material.
func _add_picture(node_name: String, quads: Array, picture: Texture2D, colour: Color, energy: float,
		group: String) -> void:
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
	var m: ShaderMaterial = _light.lamp_material(colour, energy, 0.0, group)
	m.set_shader_parameter("picture", picture)
	m.set_shader_parameter("use_picture", true)
	var mesh := st.commit()
	mesh.surface_set_material(0, m)
	var mi := _add_mesh(node_name, mesh)
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED


## "EXIT" in white on green, in a 5 x 7 pixel face, drawn here (no font, nothing borrowed).
static func exit_picture() -> Texture2D:
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
	return ImageTexture.create_from_image(img)


## The booth seen through its windows: left half the projector's port (the lens, bright, in a dim booth), right
## half a viewing port (the dim booth).
static func booth_picture() -> Texture2D:
	var img := Image.create_empty(128, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 128:
			var u := float(x % 64) / 63.0
			var v := float(y) / 63.0
			# A dim booth, warmer near its lamp above.
			var c := Color(0.035, 0.03, 0.035).lerp(Color(0.09, 0.07, 0.05), clampf(1.0 - v, 0.0, 1.0) * 0.6)
			if x < 64:
				var d := Vector2((u - 0.5) * 1.75, v - 0.5).length()
				var lens_glow := exp(-d * d / 0.004) * 1.0 + exp(-d * d / 0.03) * 0.25
				c = c.lerp(Color(1.0, 0.96, 0.88), clampf(lens_glow, 0.0, 1.0))
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


# --- The viewer's seat ----------------------------------------------------------------------------------------------------

func on_room_moved() -> void:
	_hide_occupied_seat()


## The seat the viewer sits in (the room moved so it is at the origin) is folded away; the others are all there.
func _hide_occupied_seat() -> void:
	if _seats == null or not room.is_inside_tree():
		return
	var here := room.global_transform.affine_inverse() * Vector3.ZERO
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
