extends "res://scripts/env/systems/kit/builder.gd"

## The terrace builder (docs/environments.md, "The builders"): somewhere to watch in the open air, under a sky system's
## sky. Three styles:
##   rooftop        a tiled roof terrace with a low parapet, the screen painted on the blind wall of the building
##                  next door, strings of bulbs along the sides, chairs in rows
##   lot            a drive-in's lot: a wide ground, low humps the cars park against, speaker posts in rows, the
##                  screen on a frame (or the kit's screen tower); the seats are a vehicle's (seating off)
##   amphitheatre   stone tiers on arcs round the screen, rising behind the viewer, on a plain of dust and rocks (a
##                  lunar amphitheatre); the tiers are the seats (style "tier")
## STYLES has each style's recommended parameters (the docs' table); a document sets them.
##   Ground, Floor, Parapet, ScreenWall (and its painted panel) or ScreenFrame, Tiers, Rocks, Posts, Bulbs, Seats
## Slots for the kit: parapet (along the top of the side and back parapets), screen, proscenium, floor, corners.

static func spec() -> Dictionary:
	return {
		"kind": "builder",
		"description": "Open air: a rooftop terrace with a low parapet and the screen painted on the next "
				+ "building's wall, strings of bulbs and chairs in rows; or a drive-in's lot with humps and speaker "
				+ "posts (the seats are a vehicle's); or stone tiers on arcs round the screen on a dusty plain (a "
				+ "lunar amphitheatre).",
		"params": PARAMS,
		"actions": {"car_passes": "drive_in: a car's lights go by on the road behind the lot (args: way, 1 or -1)"},
		"requires": ["light"],
		"provides": ["seats", "collision", "sound_room", "bake", "slots"],
		"cost": {"draws": 8, "triangles": 13000, "lights": 0, "particles": 0, "texture_mb": 8},
	}


const PARAMS := {
	"style": {"type": "enum", "values": ["rooftop", "lot", "amphitheatre"], "default": "rooftop",
			"description": "rooftop terrace, drive-in lot, or amphitheatre of stone tiers"},
	"half_width": {"type": "float", "min": 2.0, "max": 100.0, "default": 6.5,
			"description": "the terrace's (or the lot's rows') half width"},
	"front_z": {"type": "float", "min": -150.0, "max": -3.0, "default": -12.0,
			"description": "z of the terrace's far edge, where the screen stands"},
	"back_z": {"type": "float", "min": 1.0, "max": 100.0, "default": 4.5, "description": "z of its near edge, behind"},
	"ground_y": {"type": "float", "min": -3.0, "max": 0.0, "default": 0.0,
			"description": "the ground's height under the viewer (a car's seat over the lot: about -0.5)"},
	"ground_extent": {"type": "float", "min": 0.0, "max": 400.0, "default": 0.0,
			"description": "metres the ground reaches past the terrace (an open lot, a plain); 0: none"},
	"parapet": {"type": "bool", "default": true, "description": "a low wall round the terrace's sides and back"},
	"parapet_height": {"type": "float", "min": 0.3, "max": 1.5, "default": 1.0, "description": "the parapet's height"},
	"screen": {"type": "enum", "values": ["painted_wall", "frame", "none"], "default": "painted_wall",
			"description": "the screen painted on a wall, on a frame on posts, or none of its own (the kit's tower)"},
	"screen_size": {"type": "vec2", "min": 1.0, "max": 60.0, "default": [6.4, 3.6],
			"description": "the picture, width and height"},
	"screen_bottom": {"type": "float", "min": 0.5, "max": 30.0, "default": 1.7,
			"description": "the picture's bottom edge over the ground"},
	"wall_height": {"type": "float", "min": 3.0, "max": 60.0, "default": 9.0, "description": "the painted wall's height"},
	"seating": {"type": "bool", "default": true,
			"description": "seats of its own (off for a lot, where a vehicle's bench is the seat)"},
	"rows_front": {"type": "int", "min": 0, "max": 20, "default": 5, "description": "rows in front of the viewer's"},
	"rows_back": {"type": "int", "min": 0, "max": 20, "default": 2, "description": "rows behind the viewer's"},
	"row_pitch": {"type": "float", "min": 0.8, "max": 3.0, "default": 1.1, "description": "metres a row"},
	"seats_per_row": {"type": "int", "min": 1, "max": 41, "default": 9,
			"description": "seats along a row (odd: one in the middle, the viewer's)"},
	"seat_pitch": {"type": "float", "min": 0.45, "max": 1.5, "default": 0.68, "description": "seat centres, metres"},
	"seat_model": {"type": "enum", "values": ["director", "folding", "plush"], "default": "director",
			"description": "the plain chair drawn when the room has no seats system (rooftop)"},
	"tier_rise": {"type": "float", "min": 0.15, "max": 0.8, "default": 0.42, "description": "an amphitheatre tier's rise"},
	"arc_deg": {"type": "float", "min": 30.0, "max": 220.0, "default": 140.0,
			"description": "an amphitheatre's spread, degrees"},
	"rocks": {"type": "int", "min": 0, "max": 40, "default": 14, "description": "rocks on an amphitheatre's plain"},
	"bays": {"type": "int", "min": 0, "max": 12, "default": 4, "description": "a lot's rows of parking bays in front"},
	"bay_pitch": {"type": "float", "min": 4.0, "max": 12.0, "default": 7.0, "description": "a lot's bay rows, apart"},
	"string_lights": {"type": "bool", "default": true, "description": "strings of bulbs along a rooftop's sides"},
	"bulb_colour": {"type": "color", "default": [1.0, 0.8, 0.52], "description": "the bulbs' glow"},
	"floor": {"type": "material", "default": {"library": "terrazzo", "color": [0.55, 0.5, 0.45]},
			"description": "a rooftop's tiles"},
	"parapet_material": {"type": "material", "default": {"library": "rough_plaster", "color": [0.78, 0.74, 0.68]},
			"description": "the parapet"},
	"wall": {"type": "material", "default": {"library": "painted_brick", "color": [0.62, 0.56, 0.5]},
			"description": "the wall the screen is painted on"},
	"paint": {"type": "material", "default": {"library": "painted_wall", "color": [0.85, 0.85, 0.83]},
			"description": "the painted panel round the picture"},
	"ground": {"type": "material", "default": {"library": "smooth_concrete", "color": [0.2, 0.2, 0.2], "tiling": 3.0},
			"description": "the lot's ground or the plain"},
	"stone": {"type": "material", "default": {"library": "smooth_concrete", "color": [0.42, 0.42, 0.42]},
			"description": "an amphitheatre's tiers and rocks"},
	"frame": {"type": "material", "default": {"library": "rustic_planks", "color": [0.3, 0.25, 0.2]},
			"description": "the screen's frame and posts, the speaker posts"},
	"seat_cover": {"type": "material", "default": {"library": "linen", "color": [0.55, 0.2, 0.12]},
			"description": "the chairs' canvas or cover"},
	"seat_frame": {"type": "material", "default": {"library": "oak_veneer", "color": [0.4, 0.28, 0.16]},
			"description": "the chairs' frames"},
	# The whole drive-in (kit/drive_in_lot.gd): since 2026-11-08, the drive-in's quality pass. Off: the lot as before.
	"drive_in": {"type": "bool", "default": false,
			"description": "a lot as a whole drive-in: rows on arcs in a fan facing the screen, gravel bays and "
			+ "lanes, posts with their speakers, other cars parked, the snack bar and projection booth in neon, the "
			+ "screen's tower, the marquee by the entrance, a fence, the desert round it, a road far behind"},
	"cars": {"type": "int", "min": 0, "max": 80, "default": 30,
			"description": "drive_in: cars parked in the bays round the viewer's (no people in them)"},
	"name": {"type": "string", "max": 20, "default": "",
			"description": "drive_in: the drive-in's name in neon on its marquee (our letters A to Z, 0 to 9)"},
	"snack_sign": {"type": "string", "max": 16, "default": "SNACK BAR",
			"description": "drive_in: the neon over the snack bar"},
	"board": {"type": "list", "max": 2, "of": {"type": "string", "max": 20}, "default": [],
			"description": "drive_in: the marquee's letter board, a line each"},
	"neon": {"type": "float", "min": 0.0, "max": 2.0, "default": 1.0, "live": true, "brightness": true,
			"description": "drive_in: the neon's and the lit windows' glow"},
	"chase": {"type": "float", "min": 0.0, "max": 1.0, "default": 1.0, "live": true, "brightness": true,
			"description": "drive_in: the marquee's bulbs chasing round its board (slowly; 0 holds them steady)"},
	"ramp_lights": {"type": "float", "min": 0.0, "max": 1.0, "default": 1.0, "live": true, "brightness": true,
			"description": "drive_in: the posts' small amber ramp lights"},
}

const DriveInLot := preload("res://scripts/env/systems/kit/drive_in_lot.gd")
const Reflect := preload("res://scripts/env/systems/kit/reflect.gd")

## Each style's recommended parameters (a room document sets these; the docs list them).
const STYLES := {
	"rooftop": {},
	"lot": {"style": "lot", "half_width": 20.0, "front_z": -50.0, "back_z": 12.0, "ground_y": -0.5,
			"ground_extent": 120.0, "parapet": false, "screen": "frame", "screen_size": [24.0, 10.0],
			"screen_bottom": 4.0, "seating": false, "string_lights": false},
	"amphitheatre": {"style": "amphitheatre", "half_width": 14.0, "front_z": -14.0, "back_z": 10.0,
			"ground_extent": 150.0, "parapet": false, "screen": "frame", "screen_size": [8.0, 4.5],
			"screen_bottom": 1.6, "rows_front": 3, "rows_back": 6, "row_pitch": 0.95, "seat_pitch": 0.6,
			"string_lights": false},
}


# --- From parameters alone ----------------------------------------------------------------------------------------

static func _amph(p: Dictionary) -> bool:
	return str(p["style"]) == "amphitheatre"


## The amphitheatre's pit (the floor round the screen) under the viewer's tier.
static func _pit_y(p: Dictionary) -> float:
	return -float(p["tier_rise"]) * (int(p["rows_front"]) + 1) if _amph(p) else float(p["ground_y"])


static func _screen_z(p: Dictionary) -> float:
	return float(p["front_z"]) + (0.08 if str(p["screen"]) == "painted_wall" else 0.6)


static func seat_slots_for(p: Dictionary) -> Array:
	if not bool(p["seating"]) or str(p["style"]) == "lot":
		return []
	var out: Array = []
	if _amph(p):
		var foot := Vector3(0, 0, _screen_z(p))
		var half := deg_to_rad(float(p["arc_deg"])) * 0.5
		for r in range(-int(p["rows_back"]), int(p["rows_front"]) + 1):
			var radius := -foot.z - r * float(p["row_pitch"])
			if radius > 2.0:
				out.append_array(U.arc(foot, radius, -float(p["tier_rise"]) * r, float(p["seat_pitch"]), half, r, "tier"))
		return out
	for r in range(-int(p["rows_back"]), int(p["rows_front"]) + 1):
		out.append_array(U.row(-r * float(p["row_pitch"]), float(p["ground_y"]), int(p["seats_per_row"]),
				float(p["seat_pitch"]), r, "chair"))
	return out


static func layout(p: Dictionary) -> SeatList:
	return SeatList.new(seat_slots_for(p))


static func screen_for(p: Dictionary) -> Dictionary:
	var s := U.v2(p["screen_size"])
	return {"center": [0.0, _pit_y(p) + float(p["screen_bottom"]) + s.y * 0.5, _screen_z(p)], "size": [s.x, s.y]}


## The amphitheatre's tiers: [radius, top y, depth] from the back row to the front.
static func _tiers(p: Dictionary) -> Array:
	var out: Array = []
	var d0 := -_screen_z(p)
	for r in range(-int(p["rows_back"]), int(p["rows_front"]) + 1):
		var radius := d0 - r * float(p["row_pitch"])
		if radius > 2.0:
			out.append([radius, -float(p["tier_rise"]) * r, float(p["row_pitch"])])
	return out


## The lot's speaker posts: their feet.
static func _posts(p: Dictionary) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if str(p["style"]) != "lot":
		return out
	if bool(p.get("drive_in", false)):
		for e: Array in DriveInLot.posts(float(p["ground_y"])):
			out.append(e[0])
		return out
	var hw := float(p["half_width"])
	for k in range(-1, int(p["bays"])):
		# Beside the front seats of a car whose front wheels are on the hump (the window speaker within reach).
		var z := -k * float(p["bay_pitch"]) - 0.3
		var x := 1.75
		while x < hw:
			out.append(Vector3(x, float(p["ground_y"]), z))
			out.append(Vector3(-x, float(p["ground_y"]), z))
			x += 3.5
	return out


static func collision_shapes_for(p: Dictionary, with_seats := true) -> Array:
	var out: Array = []
	var hw := float(p["half_width"])
	var fz := float(p["front_z"])
	var bz := float(p["back_z"])
	var gy := _pit_y(p)
	var ext := float(p["ground_extent"])
	var roof := str(p["style"]) == "rooftop"
	out.append(PhysicsShapes.box(Vector3(0, gy - 0.5, (fz + bz) * 0.5), Vector3((hw + (0.0 if roof else ext)) * 2.0,
			1.0, bz - fz + (0.0 if roof else ext * 2.0))))
	if roof and ext > 0.0:
		out.append(PhysicsShapes.box(Vector3(0, gy - 12.5, (fz + bz) * 0.5), Vector3((hw + ext) * 2.0, 1.0,
				bz - fz + ext * 2.0)))
	if bool(p["parapet"]):
		var h := float(p["parapet_height"])
		for s: float in [-1.0, 1.0]:
			out.append(PhysicsShapes.box(Vector3(s * (hw + 0.15), gy + h * 0.5, (fz + bz) * 0.5), Vector3(0.3, h, bz - fz)))
		out.append(PhysicsShapes.box(Vector3(0, gy + h * 0.5, bz + 0.15), Vector3(hw * 2.0, h, 0.3)))
	if str(p["screen"]) == "painted_wall":
		out.append(PhysicsShapes.box(Vector3(0, gy + float(p["wall_height"]) * 0.5, fz - 0.25),
				Vector3(hw * 2.0 + 4.0, float(p["wall_height"]), 0.5)))
	if _amph(p):
		var half := deg_to_rad(float(p["arc_deg"])) * 0.5
		var foot_z := _screen_z(p)
		for t: Array in _tiers(p):
			var r: float = t[0]
			var h: float = float(t[1]) - gy
			var segs := 10
			for i in segs:
				var a := lerpf(-half, half, (i + 0.5) / segs)
				var chord := 2.0 * (r + float(t[2]) * 0.5) * sin(half / segs) * 1.04
				out.append(PhysicsShapes.box(Vector3(r * sin(a), gy + h * 0.5, foot_z + r * cos(a)),
						Vector3(chord, h, float(t[2])), Basis(Vector3.UP, a)))
	for post in _posts(p):
		out.append(PhysicsShapes.box(post + Vector3(0, 0.7, 0), Vector3(0.12, 1.4, 0.12)))
	if str(p["style"]) == "lot" and bool(p.get("drive_in", false)):
		out.append(PhysicsShapes.box(Vector3(0, gy + DriveInLot.SNACK_H * 0.5, DriveInLot.SNACK_Z
				+ DriveInLot.SNACK_D * 0.5), Vector3(DriveInLot.SNACK_W, DriveInLot.SNACK_H, DriveInLot.SNACK_D)))
	if with_seats and str(p["style"]) == "rooftop":
		out.append_array(U.seat_boxes(seat_slots_for(p), str(p["seat_model"])))
	return out


static func slots_for(p: Dictionary) -> Dictionary:
	var hw := float(p["half_width"])
	var fz := float(p["front_z"])
	var bz := float(p["back_z"])
	var gy := _pit_y(p)
	var h := float(p["parapet_height"]) if bool(p["parapet"]) else 0.0
	var parapet: Array = []
	var z := fz + 1.5
	while z < bz - 0.5:
		for s: float in [-1.0, 1.0]:
			var into := Vector3(-s, 0, 0)
			parapet.append({"transform": Transform3D(Basis(Vector3.UP.cross(into), Vector3.UP, into),
					Vector3(s * (hw + 0.15), gy + h, z)), "size": [2.5, 1.5, 0.3]})
		z += 2.5
	var sc := screen_for(p)
	var ss := U.v2(sc["size"])
	var corners: Array = []
	for c: Vector2 in [Vector2(-hw, fz), Vector2(hw, fz), Vector2(-hw, bz), Vector2(hw, bz)]:
		corners.append({"transform": Transform3D(Basis(), Vector3(c.x, gy, c.y)), "size": [1.0, 1.0, 1.0]})
	return {
		"parapet": parapet,
		"corners": corners,
		"screen": [{"transform": Transform3D(Basis(), U.v3(sc["center"])), "size": [ss.x, ss.y, 0.1]}],
		"proscenium": [{"transform": Transform3D(Basis(), Vector3(0, gy, fz)),
				"size": [ss.x + 2.0, ss.y + float(p["screen_bottom"]) + 1.0, 1.0]}],
		"floor": [{"transform": Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, gy, (fz + bz) * 0.5)),
				"size": [hw * 2.0, bz - fz, 0.0]}],
	}


func sound_room() -> Dictionary:
	var hw := float(params["half_width"])
	var gy := _pit_y(params)
	var fz := float(params["front_z"])
	var bz := float(params["back_z"])
	return {"box": AABB(Vector3(-hw, gy, fz), Vector3(hw * 2.0, 12.0, bz - fz)),
			"reflect": [0.05, 0.05, 0.3, 0.0, 0.4 if str(params["screen"]) == "painted_wall" else 0.1, 0.05],
			"surround_height": 2.0}


# --- Building -----------------------------------------------------------------------------------------------------

func build() -> void:
	var hw := float(params["half_width"])
	var fz := float(params["front_z"])
	var bz := float(params["back_z"])
	var gy := _pit_y(params)
	var ext := float(params["ground_extent"])
	var style := str(params["style"])
	if style == "lot" and bool(params["drive_in"]):
		_build_drive_in(gy)
		match str(params["screen"]):
			"frame":
				_build_frame(gy)
		_bake_spot("Sky", Vector3(0, gy + 14.0, (fz + bz) * 0.5), true, 80.0, 30.0, 0.4, Color(0.6, 0.65, 0.85))
		return
	# The terrace's own floor is baked; the ground beyond it (an open lot, a plain: up to hundreds of metres) is a
	# ring round it left out of the bake, so the lightmap's atlas stays small.
	var fl := RoomMesh.new()
	fl.surface(_mat("floor") if style == "rooftop" else _mat("ground"))
	fl.face([Vector3(-hw, gy, fz), Vector3(hw, gy, fz), Vector3(hw, gy, bz), Vector3(-hw, gy, bz)], Vector3.UP)
	_add_static("Floor", fl)
	if ext > 0.0:
		var g := RoomMesh.new()
		g.surface(_mat("ground"))
		# A rooftop's street is far below the parapet; a lot's or a plain's ground goes on at the floor's height.
		var y := gy - 12.0 if style == "rooftop" else gy
		var x0 := -hw - ext
		var x1 := hw + ext
		var z0 := fz - ext
		var z1 := bz + ext
		var inner := [Vector3(-hw, y, fz), Vector3(hw, y, fz), Vector3(hw, y, bz), Vector3(-hw, y, bz)]
		var outer := [Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1)]
		for k in 4:
			g.face([inner[k], outer[k], outer[(k + 1) % 4], inner[(k + 1) % 4]], Vector3.UP)
		_add_unbaked("Ground", g)
	if bool(params["parapet"]):
		_build_parapet(hw, fz, bz, gy)
	match str(params["screen"]):
		"painted_wall":
			_build_wall(hw, fz, gy)
		"frame":
			_build_frame(gy)
	if style == "amphitheatre":
		_build_tiers(gy)
	if style == "lot":
		_build_lot(hw, gy)
	if style == "rooftop" and bool(params["string_lights"]):
		_build_bulbs(hw, fz, bz, gy)
	if style == "rooftop" and bool(params["seating"]):
		_build_seat_multimesh(str(params["seat_model"]), _mat("seat_cover", true), _mat("seat_frame", true),
				seat_slots_for(params), 1955)
	# A bake light: the open sky's soft light from above.
	_bake_spot("Sky", Vector3(0, gy + 14.0, (fz + bz) * 0.5), true, 80.0, 30.0, 0.4, Color(0.6, 0.65, 0.85))


func _build_parapet(hw: float, fz: float, bz: float, gy: float) -> void:
	var h := float(params["parapet_height"])
	var b := RoomMesh.new()
	b.surface(_mat("parapet_material"))
	var from := fz if str(params["screen"]) != "painted_wall" else fz - 0.5
	for s: float in [-1.0, 1.0]:
		b.box(Vector3(s * (hw + 0.15), gy + h * 0.5, (from + bz) * 0.5), Vector3(0.3, h, bz - from), Basis(),
				[RoomMesh.DOWN])
		b.box(Vector3(s * (hw + 0.15), gy + h + 0.03, (from + bz) * 0.5), Vector3(0.4, 0.06, bz - from + 0.1))
	b.box(Vector3(0, gy + h * 0.5, bz + 0.15), Vector3(hw * 2.0 + 0.6, h, 0.3), Basis(), [RoomMesh.DOWN])
	b.box(Vector3(0, gy + h + 0.03, bz + 0.15), Vector3(hw * 2.0 + 0.7, 0.06, 0.4))
	_add_static("Parapet", b)


## The next building's blind wall, the screen painted on it: a white panel a little bigger than the picture.
func _build_wall(hw: float, fz: float, gy: float) -> void:
	var b := RoomMesh.new()
	b.surface(_mat("wall"))
	var top := gy + float(params["wall_height"])
	var w := hw + 2.0
	b.box(Vector3(0, (gy - 3.0 + top) * 0.5, fz - 0.25), Vector3(w * 2.0, top - gy + 3.0, 0.5), Basis(),
			[RoomMesh.DOWN, RoomMesh.FRONT])
	_add_static("ScreenWall", b)
	var sc := screen_for(params)
	var c := U.v3(sc["center"])
	var size := U.v2(sc["size"])
	var paint := RoomMesh.new()
	paint.surface(_mat("paint"))
	Shapes.quad(paint, Vector3(c.x, c.y, fz + 0.01), Vector3(size.x * 0.5 + 0.3, 0, 0), Vector3(0, size.y * 0.5 + 0.3, 0),
			Vector3.BACK)
	_add_static("Painted", paint)


## A screen on a frame: a dark backing panel a little bigger than the picture on posts, braces behind.
func _build_frame(gy: float) -> void:
	var sc := screen_for(params)
	var c := U.v3(sc["center"])
	var size := U.v2(sc["size"])
	var b := RoomMesh.new()
	b.surface(_mat("frame"))
	var back_z := c.z - 0.15
	b.box(Vector3(c.x, c.y, back_z), Vector3(size.x + 0.6, size.y + 0.6, 0.12))
	var post := maxf(0.15, size.x * 0.012)
	for k in 4:
		var x := lerpf(-size.x * 0.5, size.x * 0.5, k / 3.0)
		var top := c.y + size.y * 0.5 + 0.3
		b.box(Vector3(x, (gy + top) * 0.5, back_z - 0.2), Vector3(post, top - gy, post))
		Shapes.beam(b, Vector3(x, top - size.y * 0.3, back_z - 0.25), Vector3(x, gy, back_z - size.y * 0.5),
				Vector2(post * 0.8, post * 0.8))
	_add_static("ScreenFrame", b)


## Stone tiers on arcs round the screen, rising behind the viewer, each down to the pit; the plain's rocks.
func _build_tiers(gy: float) -> void:
	var half := deg_to_rad(float(params["arc_deg"])) * 0.5
	var foot_z := _screen_z(params)
	var b := RoomMesh.new()
	b.surface(_mat("stone"))
	var segs := 28
	var tiers := _tiers(params)
	for i in tiers.size():
		var r: float = tiers[i][0]
		var y: float = tiers[i][1]
		var d: float = tiers[i][2]
		var below: float = float(tiers[i + 1][1]) if i + 1 < tiers.size() else gy
		var front := PackedVector3Array()
		var back := PackedVector3Array()
		var low := PackedVector3Array()
		var ground := PackedVector3Array()
		var ups := PackedVector3Array()
		var faces := PackedVector3Array()
		var outs := PackedVector3Array()
		for k in segs + 1:
			var a := lerpf(-half, half, float(k) / segs)
			var dir := Vector3(sin(a), 0, cos(a))
			var foot := Vector3(0, 0, foot_z)
			front.append(foot + dir * (r - d * 0.5) + Vector3(0, y, 0))
			back.append(foot + dir * (r + d * 0.5) + Vector3(0, y, 0))
			low.append(foot + dir * (r - d * 0.5) + Vector3(0, below, 0))
			ground.append(foot + dir * (r + d * 0.5) + Vector3(0, gy, 0))
			ups.append(Vector3.UP)
			faces.append(-dir)
			outs.append(dir)
		b.strip(front, back, ups)
		b.strip(low, front, faces)
		if i == 0:
			b.strip(back, ground, outs)
		# The tier's ends, down to the pit.
		for s: float in [-1.0, 1.0]:
			var dir := Vector3(sin(s * half), 0, cos(s * half))
			var side := Vector3(cos(s * half), 0, -sin(s * half)) * s
			var foot := Vector3(0, 0, foot_z)
			b.face([foot + dir * (r - d * 0.5) + Vector3(0, gy, 0), foot + dir * (r + d * 0.5) + Vector3(0, gy, 0),
					foot + dir * (r + d * 0.5) + Vector3(0, y, 0), foot + dir * (r - d * 0.5) + Vector3(0, y, 0)], side)
	# Rocks on the plain, out of the way: beyond the tiers' ends and behind.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1969
	var outer: float = float(tiers[0][0]) + float(tiers[0][2]) if not tiers.is_empty() else 10.0
	for k in int(params["rocks"]):
		var a := rng.randf_range(half + 0.15, TAU - half - 0.15)
		var dist := rng.randf_range(outer + 2.0, outer + 30.0) if k % 2 == 0 else rng.randf_range(4.0, outer)
		var at := Vector3(sin(a) * dist, gy, foot_z + cos(a) * dist)
		var size := rng.randf_range(0.3, 1.6)
		var prof: Array = [Vector2(size * 0.9, -0.1), Vector2(size, size * 0.25), Vector2(size * 0.7, size * 0.6),
				Vector2(size * 0.2, size * 0.75)]
		# Turned any way round the vertical, tipped a little (never on its side or upside down), squashed a little.
		var basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.2, 0.2)) \
				* Basis.from_scale(Vector3(1.0, rng.randf_range(0.6, 1.0), rng.randf_range(0.7, 1.3)))
		Shapes.lathe(b, prof, at, 6, basis)
	_add_static("Tiers", b)


## The lot: a low hump across each bay row (the cars' front wheels on it), speaker posts between the bays.
func _build_lot(hw: float, gy: float) -> void:
	var b := RoomMesh.new()
	b.surface(_mat("ground"))
	for k in range(-1, int(params["bays"])):
		var z := -k * float(params["bay_pitch"]) - 2.2
		var a := PackedVector3Array()
		var c := PackedVector3Array()
		var ns := PackedVector3Array()
		for j in 7:
			var t := float(j) / 6.0
			var y := gy + sin(t * PI) * 0.18
			a.append(Vector3(-hw, y, z - 0.8 + t * 1.6))
			c.append(Vector3(hw, y, z - 0.8 + t * 1.6))
			ns.append(Vector3(0, 1, -cos(t * PI) * 0.3).normalized())
		b.strip(c, a, ns)
	_add_static("Humps", b)
	var posts := RoomMesh.new()
	posts.surface(_mat("frame"))
	for foot in _posts(params):
		posts.box(foot + Vector3(0, 0.6, 0), Vector3(0.09, 1.2, 0.09))
		posts.box(foot + Vector3(0, 1.22, 0), Vector3(0.5, 0.05, 0.12))
		for s: float in [-1.0, 1.0]:
			posts.box(foot + Vector3(s * 0.17, 1.12, 0), Vector3(0.16, 0.2, 0.08))
	_add_static("Posts", posts)


## Strings of bulbs along both sides on posts at the parapet, sagging between them (house group).
func _build_bulbs(hw: float, fz: float, bz: float, gy: float) -> void:
	var wire := RoomMesh.new()
	wire.surface(_mat("frame"))
	var bulbs := RoomMesh.new()
	var colour := color_param("bulb_colour")
	bulbs.surface(_lamp(colour, 1.6, 1.0, "house"))
	var top := gy + 2.9
	var n := maxi(int((bz - fz) / 4.0), 1)
	var lamp_c: Color = colour * float(_light.params["lamp_energy"]) * 0.5
	var lamps := 0
	for s: float in [-1.0, 1.0]:
		var x := s * (hw - 0.05)
		for k in n + 1:
			var z := lerpf(fz + 0.5, bz - 0.3, float(k) / n)
			Shapes.beam(wire, Vector3(x, gy, z), Vector3(x, top + 0.1, z), Vector2(0.06, 0.06))
			if k == n:
				continue
			var z1 := lerpf(fz + 0.5, bz - 0.3, float(k + 1) / n)
			var prev := Vector3(x, top, z)
			for j in range(1, 9):
				var t := j / 8.0
				var p := Vector3(x, top - sin(t * PI) * 0.35, lerpf(z, z1, t))
				Shapes.beam(wire, prev, p, Vector2(0.012, 0.012))
				if j < 8 and j % 2 == 0:
					Shapes.lathe(bulbs, [Vector2(0.0, -0.09), Vector2(0.035, -0.07), Vector2(0.04, -0.03),
							Vector2(0.015, 0.0)], p, 6)
				prev = p
			if lamps < 8 and k % 2 == 0:
				_light.add_lamp(Vector3(x, top - 0.3, (z + z1) * 0.5), lamp_c, -1.0)
				_bake_omni("Bulbs%d" % lamps, Vector3(x - s * 0.3, top - 0.3, (z + z1) * 0.5), 4.0, 0.4, colour)
				lamps += 1
	_add_static("Wires", wire)
	_add_lamps("Bulbs", bulbs)


# --- The drive-in (drive_in on) --------------------------------------------------------------------------------------

## The parked cars' paint and chrome (they reflect: kit/reflect.gd), the lit materials whose level is live.
var _di_reflect: Array[ShaderMaterial] = []
var _di_neon: Array = []
var _di_bulbs: ShaderMaterial
var _di_ramp: ShaderMaterial
var _di_phase := 0.0
var _di_road: MeshInstance3D
## A car on the road: its age in seconds, -1 none; its way (+1 to the right, -1 to the left).
var _di_road_t := -1.0
var _di_road_way := 1.0
var _di_screen := Transform3D(Basis(), Vector3(0, 8.5, -49.4))
var _di_screen_size := Vector2(24.0, 10.0)
var _di_sky: Node
var _di_glint := Vector3(0, 3.0, 14.4)
## Seconds a passing car takes along the road.
const ROAD_SECONDS := 34.0
const ROAD_HALF := 420.0


## The whole drive-in (kit/drive_in_lot.gd): the ground and the plain, the posts, the parked cars, the snack bar and
## booth, the tower, the marquee, the fence, the road.
func _build_drive_in(gy: float) -> void:
	var sc: Dictionary = room.get("doc").get("screen", {}) if room.get("doc") is Dictionary else {}
	if sc.has("center"):
		_di_screen = Transform3D(Basis(), U.v3(sc["center"]))
		_di_screen_size = U.v2(sc["size"])
	_di_sky = host.system_of_kind("sky") if host != null else null
	var cars := DriveInLot.parked(int(params["cars"]), 1958)
	# The ground: the lot's fan and the plain, one draw, vertex colours (left out of the bake: its light is the fill's,
	# the film's spill and the stand-in lamps', which it keeps).
	var gm := _mat("ground", true)
	gm.set_shader_parameter("instance_tint", true)
	var g := RoomMesh.new()
	g.surface(gm)
	DriveInLot.ground(g, gy, cars)
	_add_unbaked("Ground", g)
	# The posts, their speakers and cables; the marquee's steel. One draw in vertex colours, baked.
	var steel: ShaderMaterial = _light.library("brushed_steel", Color(0.85, 0.85, 0.85), {"tiling": 0.5})
	steel.set_shader_parameter("instance_tint", true)
	var pb := RoomMesh.new()
	pb.surface(steel)
	var lamp_b := RoomMesh.new()
	_di_ramp = _lamp(Color(1.0, 0.62, 0.25), 0.9 * float(params["ramp_lights"]), 0.0, "steps")
	lamp_b.surface(_di_ramp)
	var taken := {}
	for e: Array in cars:
		taken["%d %.4f" % [e[0], e[1]]] = e
	var step0 := 0.0
	for e: Array in DriveInLot.posts(gy):
		var k := int(e[1])
		var a := float(e[2])
		step0 = DriveInLot.BAY / DriveInLot.row_radius(k)
		var right_bay := a + step0 * 0.5
		var into: Variant = null
		var key := "%d %.4f" % [k, right_bay]
		if taken.has(key):
			var f := DriveInLot.bay_frame(k, right_bay, gy)
			into = f * Vector3(-1.0, 0.68, -0.22)
		elif k == 0 and absf(right_bay) < 0.001:
			# The viewer's own car: its speaker on the left door (vehicle.gd draws the cable from there).
			into = null
			DriveInLot.post(pb, lamp_b, e[0], a, Vector3.INF)
			continue
		DriveInLot.post(pb, lamp_b, e[0], a, into)
	# The structures: the snack bar and booth, the tower, the fence (plaster and wood, vertex colours, baked).
	var plaster: ShaderMaterial = _light.library("rough_plaster", Color(0.9, 0.9, 0.9), {"tiling": 1.5})
	plaster.set_shader_parameter("instance_tint", true)
	var wood := _mat("frame")
	var sb := RoomMesh.new()
	sb.surface(plaster)
	var snack := DriveInLot.snack_bar(sb, gy, str(params["snack_sign"]))
	sb.surface(wood)
	sb.colour = Color.WHITE
	var tower_wood := RoomMesh.new()
	tower_wood.surface(wood)
	sb.surface(plaster)
	var beacon := DriveInLot.tower(sb, tower_wood, gy, _di_screen.origin, _di_screen_size)
	sb.surface(wood)
	DriveInLot.fence(sb, gy)
	var marquee := DriveInLot.marquee(pb, gy, str(params["name"]), params["board"])
	_add_static("Posts", pb)
	_add_static("Structures", sb)
	_add_static("TowerFrame", tower_wood)
	_add_lamps("RampLights", lamp_b)
	# The neon: tubes (one draw in their vertex colours) and their halo (one more); the booth's ports and the tower's
	# red lamp in the tubes' draw.
	var neon_lines: Array = []
	neon_lines.append_array(snack["neon"])
	neon_lines.append_array(marquee["neon"])
	var nm := _lamp(Color.WHITE, 3.0 * float(params["neon"]), 0.0, "signs")
	nm.set_shader_parameter("use_vertex_colour", true)
	_di_neon = [[nm, 3.0]]
	var nb := RoomMesh.new()
	nb.surface(nm)
	DriveInLot.tubes(nb, neon_lines, 0.026)
	nb.colour = Color(0.75, 0.82, 1.0) * 0.6
	for q: Array in snack["ports"]:
		Shapes.quad(nb, q[0], q[1], q[2], q[3])
	nb.colour = Color(1.0, 0.08, 0.04)
	Shapes.lathe(nb, [Vector2(0.0, 0.0), Vector2(0.12, 0.1), Vector2(0.0, 0.22)], beacon, 8)
	nb.colour = Color.WHITE
	_add_lamps("Neon", nb)
	var halos: Array = DriveInLot.halo_quads(snack["neon"], Vector3.FORWARD, 0.5)
	var mface: Basis = Basis(Vector3.UP, atan2(DriveInLot.MARQUEE_AT.x, DriveInLot.MARQUEE_AT.z))
	halos.append_array(DriveInLot.halo_quads(marquee["neon"], mface * Vector3.FORWARD, 0.7))
	_di_neon.append([_halo_mesh("NeonGlow", halos), 0.8])
	# The snack bar's windows (warm, booth group) and the marquee's letter board.
	_add_picture("SnackWindows", snack["windows"], DriveInLot.window_picture(), Color(1, 1, 1),
			1.4 * float(params["neon"]), "booth")
	if not (params["board"] as Array).is_empty():
		var board := _add_picture("MarqueeBoard", marquee["board"], DriveInLot.board_picture(params["board"]),
				Color(1.0, 0.95, 0.85), 1.2 * float(params["neon"]), "signs")
		_di_neon.append([board.mesh.surface_get_material(0), 1.2])
	_build_bulbs_mesh(marquee["bulbs"])
	# Their light on the lot: stand-in lamps before a bake, hidden lights for it.
	for l: Array in snack["lamps"]:
		var c: Color = l[1]
		_light.add_lamp(l[0], c * 1.6, -1.0)
		_bake_omni("SnackLight", l[0], 18.0, 1.2, c)
	_light.add_lamp(marquee["lamp"][0], (marquee["lamp"][1] as Color) * 1.2, -1.0)
	_bake_omni("MarqueeLight", marquee["lamp"][0], 12.0, 0.8, marquee["lamp"][1])
	_di_glint = Vector3(0, gy + DriveInLot.SNACK_H + 0.25, DriveInLot.SNACK_Z - 0.66)
	# The parked cars: one MultiMesh, their paint and chrome reflecting.
	if not cars.is_empty():
		var paint: ShaderMaterial = _light.library("dark_metal", Color.WHITE, {}, true)
		Reflect.make(paint, 0.0, 0.75, 0.1)
		paint.set_shader_parameter("tint", Color.WHITE)
		paint.set_shader_parameter("instance_tint", true)
		var chrome: ShaderMaterial = _light.library("brushed_steel", Color(0.8, 0.8, 0.82), {}, true)
		Reflect.make(chrome, 1.0, 1.0, 0.08)
		chrome.set_shader_parameter("tint", Color(0.8, 0.8, 0.82))
		_di_reflect = [paint, chrome]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = DriveInLot.parked_mesh(paint, chrome, -0.5)
		mm.instance_count = cars.size()
		var rng := RandomNumberGenerator.new()
		rng.seed = 58
		var placed: Array[Transform3D] = []
		var colours: Array[Color] = []
		for i in cars.size():
			var e: Array = cars[i]
			var f := DriveInLot.bay_frame(int(e[0]), float(e[1]), gy)
			f.basis = f.basis * Basis(Vector3.UP, rng.randf_range(-0.04, 0.04))
			mm.set_instance_transform(i, f)
			var c: Color = DriveInLot.CAR_COLOURS[rng.randi() % DriveInLot.CAR_COLOURS.size()]
			mm.set_instance_color(i, c)
			placed.append(f)
			colours.append(c)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "ParkedCars"
		mmi.multimesh = mm
		mmi.set_meta("instances", cars.size())
		# The sight-line check takes them where they stand (not as seats); a headless MultiMesh keeps no transforms.
		mmi.set_meta("env_placed", placed)
		mmi.set_meta("colours", colours)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		own(mmi)
	_build_road()


## Halos: soft bands, added over what is behind, in their colours (one draw).
func _halo_mesh(node_name: String, quads: Array) -> ShaderMaterial:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for q: Array in quads:
		var c: Vector3 = q[0]
		var u: Vector3 = q[1]
		var v: Vector3 = q[2]
		var corners := [c - u - v, c + u - v, c + u + v, c - u + v]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for k: int in [0, 1, 2, 0, 2, 3]:
			st.set_color(q[4])
			st.set_normal(q[3])
			st.set_uv(uvs[k])
			st.add_vertex(corners[k])
	var m := ShaderMaterial.new()
	m.shader = GLOW_SHADER
	m.set_shader_parameter("colour", Color.WHITE)
	m.set_shader_parameter("picture", DriveInLot.halo_picture())
	m.set_shader_parameter("use_vertex_colour", true)
	m.set_shader_parameter("energy", 0.8 * float(params["neon"]) * _group_level("signs"))
	var mesh := st.commit()
	mesh.surface_set_material(0, m)
	var mi := _add_mesh(node_name, mesh)
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.add_to_group(SEE_THROUGH)
	return m


## The marquee's bulbs: a quad each facing out from its board, its place in the run in UV2.
func _build_bulbs_mesh(bulbs: Array) -> void:
	if bulbs.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for e: Array in bulbs:
		var p: Vector3 = e[0]
		var n: Vector3 = e[2]
		var u := Vector3.UP.cross(n).normalized() * 0.09
		var v := Vector3.UP * 0.09
		var corners := [p - u - v, p + u - v, p + u + v, p - u + v]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for k: int in [0, 1, 2, 0, 2, 3]:
			st.set_normal(n)
			st.set_uv(uvs[k])
			st.set_uv2(Vector2(float(e[1]), 0.0))
			st.add_vertex(corners[k] + n * 0.02)
	_di_bulbs = ShaderMaterial.new()
	_di_bulbs.shader = DriveInLot.BULB_SHADER
	_di_bulbs.set_shader_parameter("picture", DriveInLot.bulb_picture())
	_di_bulbs.set_shader_parameter("energy", 1.5 * float(params["neon"]) * _group_level("signs"))
	_di_bulbs.set_shader_parameter("chase", float(params["chase"]))
	var mesh := st.commit()
	mesh.surface_set_material(0, _di_bulbs)
	var mi := _add_mesh("Bulbs", mesh)
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.add_to_group(SEE_THROUGH)


## The road far behind the lot: a car's lights (two white ahead, two red behind) that go by now and then.
func _build_road() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for e: Array in [[Vector3(2.3, 0, 0.7), Color(1.0, 0.93, 0.78)], [Vector3(2.3, 0, -0.7), Color(1.0, 0.93, 0.78)],
			[Vector3(-2.3, 0, 0.7), Color(0.9, 0.08, 0.04)], [Vector3(-2.3, 0, -0.7), Color(0.9, 0.08, 0.04)]]:
		var p: Vector3 = e[0] + Vector3(0, 0.7, 0)
		var u := Vector3(0.0, 0.0, 0.0)
		var corners := [p + Vector3(-0.5, -0.5, 0), p + Vector3(0.5, -0.5, 0), p + Vector3(0.5, 0.5, 0),
				p + Vector3(-0.5, 0.5, 0)]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for k: int in [0, 1, 2, 0, 2, 3]:
			st.set_color(e[1])
			st.set_normal(Vector3.FORWARD)
			st.set_uv(uvs[k])
			st.add_vertex(corners[k] + u)
	var m := ShaderMaterial.new()
	m.shader = GLOW_SHADER
	m.set_shader_parameter("colour", Color.WHITE)
	m.set_shader_parameter("picture", DriveInLot.bulb_picture())
	m.set_shader_parameter("use_vertex_colour", true)
	m.set_shader_parameter("energy", 1.6)
	var mesh := st.commit()
	mesh.surface_set_material(0, m)
	_di_road = _add_mesh("Road", mesh)
	_di_road.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_di_road.add_to_group(SEE_THROUGH)
	_di_road.visible = false


## way 1 drives it from -X to +X (as the room's far_car sound travels), -1 back; none: either.
func act(action: String, args: Dictionary) -> void:
	if action == "car_passes" and _di_road != null and _di_road_t < 0.0:
		_di_road_t = 0.0
		var way := float(args.get("way", 0.0))
		_di_road_way = signf(way) if way != 0.0 else (1.0 if randf() < 0.5 else -1.0)
		_di_road.visible = true


func on_screen_changed(local: Transform3D, size: Vector2) -> void:
	_di_screen = local
	_di_screen_size = size


func tick(delta: float) -> void:
	super.tick(delta)
	if _di_reflect.is_empty() and _di_bulbs == null and _di_road == null:
		return
	if not _di_reflect.is_empty():
		var neon := NEON_GLINT * float(params["neon"]) * _group_level("signs")
		Reflect.update(_di_reflect, _di_sky, room, _di_screen, _di_screen_size, _di_glint, neon, Vector2(2.6, 0.5),
				_screen_level())
	if _di_bulbs != null:
		# A wave every three bulbs, one bulb on in 0.55 s: each bulb's light goes round about once in 1.7 s.
		_di_phase = fposmod(_di_phase + delta * 0.6 * float(params["chase"]), 1000.0)
		_di_bulbs.set_shader_parameter("phase", _di_phase)
	if _di_road_t >= 0.0:
		_di_road_t += delta
		var t := _di_road_t / ROAD_SECONDS
		if t >= 1.0:
			_di_road_t = -1.0
			_di_road.visible = false
		else:
			var x := lerpf(-ROAD_HALF, ROAD_HALF, t) * _di_road_way
			_di_road.transform = Transform3D(Basis(Vector3.UP, 0.0 if _di_road_way > 0.0 else PI),
					Vector3(x, float(params["ground_y"]), DriveInLot.ROAD_Z))


## The neon's colour as the cars' chrome shows it.
const NEON_GLINT := Color(1.0, 0.3, 0.5) * 0.9


## The picture's level in the cars' paint: the film's while it plays (the playback state), dim before.
func _screen_level() -> float:
	if host == null:
		return 1.0
	var v: Variant = host.channel("playback.playing")
	return lerpf(0.25, 1.0, clampf(float(v) if v != null else 0.0, 0.0, 1.0))


func _param_changed(param: String, value: Variant) -> void:
	match param:
		"neon":
			for e: Array in _di_neon:
				(e[0] as ShaderMaterial).set_shader_parameter("energy", float(e[1]) * float(value)
						* _group_level("signs"))
			if _di_bulbs != null:
				_di_bulbs.set_shader_parameter("energy", 1.5 * float(value) * _group_level("signs"))
		"chase":
			if _di_bulbs != null:
				_di_bulbs.set_shader_parameter("chase", float(value))
		"ramp_lights":
			if _di_ramp != null:
				_di_ramp.set_shader_parameter("energy", 0.9 * float(value) * _group_level("steps"))


## The road's car now: its place, or null (tests).
func passing_car() -> Variant:
	return _di_road.position if _di_road != null and _di_road.visible else null
