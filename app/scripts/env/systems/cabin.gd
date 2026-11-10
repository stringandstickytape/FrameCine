extends "res://scripts/env/systems/kit/builder.gd"

## The cabin builder (docs/environments/cabin.md): the inside of a vehicle for the Journeys rooms (a narrowboat's
## saloon, a railway carriage, a coach). One section along Z: two side walls that may lean in, a flat or arched roof,
## a bulkhead at each end. Windows along the walls in bays, with frames, reveals and glass; a dado, ribs between the
## bays, lamps under the roof or on the walls, a door in the rear bulkhead with a lit window, a ledge outside.
##   Floor, Lining (dado, walls, ceiling, bulkheads), Trim (frames, rails, ribs, the screen's frame, the door, the
##   lamps' fittings), Glass, DoorGlow, Lamps, Hull (the ledge), Seats
## Slots for the kit: side_walls, window_sills, windows, screen, proscenium, rear_wall, floor, ceiling, corners.

## The arched roof's steps of angle.
const ROOF_STEPS := 10
## Steps of a window's round corner (CORNER_STEPS + 1 points).
const CORNER_STEPS := 4
## The least height a window has (metres): where the walls leave less over the sill, the cabin has no windows.
const MIN_WINDOW := 0.1
## How far inside a bulkhead a bay's mark must be for a rib, a wall lamp or a side_walls slot to stand at it.
const MARK_MARGIN := 0.1
## The windows' glass: its tint, how much of it shows square on, and how much more where the view grazes it.
const GLASS_TINT := Color(0.62, 0.74, 0.8)
const GLASS_ALPHA := 0.02
const GLASS_RIM := 0.06


static func spec() -> Dictionary:
	return {
		"kind": "builder",
		"description": "The inside of a vehicle: a narrowboat's saloon, a railway carriage, a coach. Side walls that "
				+ "may lean in, a flat or arched roof, windows in bays with round corners, a dado, ribs, lamps under "
				+ "the roof or on the walls, a door in the rear bulkhead, seats in rows or one seat of the viewer's own.",
		"params": PARAMS,
		"actions": {},
		"requires": ["light"],
		"provides": ["seats", "collision", "sound_room", "bake", "slots"],
		"cost": {"draws": 12, "triangles": 6000, "lights": 0, "particles": 0, "texture_mb": 30},
	}


const PARAMS := {
	"width": {"type": "float", "min": 1.6, "max": 12.0, "default": 2.6, "description": "the inside width at the floor"},
	"wall_height": {"type": "float", "min": 1.2, "max": 3.5, "default": 1.9,
			"description": "the height at which the side walls end and the roof begins"},
	"lean": {"type": "float", "min": -15.0, "max": 15.0, "default": 0.0,
			"description": "degrees the side walls lean in towards their tops (negative: out)"},
	"roof": {"type": "enum", "values": ["flat", "arched"], "default": "arched", "description": "the roof's shape"},
	"roof_rise": {"type": "float", "min": 0.0, "max": 1.5, "default": 0.25,
			"description": "how far an arched roof rises over the walls' tops at its middle"},
	"front_z": {"type": "float", "min": -30.0, "max": -1.5, "default": -3.0,
			"description": "z of the front bulkhead (the screen's)"},
	"back_z": {"type": "float", "min": 0.6, "max": 30.0, "default": 2.4, "description": "z of the rear bulkhead"},
	"centre_x": {"type": "float", "min": -3.0, "max": 3.0, "default": 0.0,
			"description": "the cabin's centre line (used with seating none)"},
	"window_sides": {"type": "enum", "values": ["both", "left", "right", "none"], "default": "both",
			"description": "the walls that have windows"},
	"window_count": {"type": "int", "min": 0, "max": 24, "default": 3,
			"description": "windows along each windowed side"},
	"window_from_z": {"type": "float", "min": -30.0, "max": 30.0, "default": -1.2,
			"description": "z of the middle of the window nearest the screen"},
	"bay_pitch": {"type": "float", "min": 0.4, "max": 6.0, "default": 1.5,
			"description": "from one window's middle to the next"},
	"window_width": {"type": "float", "min": 0.25, "max": 4.0, "default": 0.9, "description": "a window's width"},
	"window_height": {"type": "float", "min": 0.25, "max": 2.5, "default": 0.6, "description": "a window's height"},
	"window_sill": {"type": "float", "min": 0.2, "max": 2.5, "default": 1.0,
			"description": "the window's bottom edge over the floor"},
	"window_round": {"type": "float", "min": 0.0, "max": 1.25, "default": 0.08,
			"description": "the windows' corners' radius"},
	"wall_thickness": {"type": "float", "min": 0.02, "max": 0.4, "default": 0.06,
			"description": "the side walls' thickness (the windows' reveals)"},
	"frame_width": {"type": "float", "min": 0.01, "max": 0.2, "default": 0.04,
			"description": "the window frames' width round the opening"},
	"frame_depth": {"type": "float", "min": 0.0, "max": 0.08, "default": 0.015,
			"description": "how far the window frames stand out from the wall"},
	"dado_height": {"type": "float", "min": 0.0, "max": 2.0, "default": 0.9,
			"description": "the dado's height (0: none)"},
	"ribs": {"type": "bool", "default": true, "description": "ribs between the bays, up the walls and under the roof"},
	"rib_width": {"type": "float", "min": 0.03, "max": 0.3, "default": 0.05, "description": "a rib's width along Z"},
	"rib_depth": {"type": "float", "min": 0.01, "max": 0.2, "default": 0.025,
			"description": "how far a rib stands out from the wall"},
	"lamps": {"type": "enum", "values": ["none", "ceiling", "wall"], "default": "ceiling",
			"description": "lamps under the roof's middle, on the walls between the windows, or none"},
	"lamp_height": {"type": "float", "min": 1.0, "max": 3.0, "default": 1.5, "description": "the wall lamps' height"},
	"lamp_colour": {"type": "color", "default": [1.0, 0.82, 0.58], "description": "the lamps' glow"},
	"rear_door": {"type": "enum", "values": ["none", "centre"], "default": "centre",
			"description": "a door in the rear bulkhead"},
	"door_glow": {"type": "float", "min": 0.0, "max": 2.0, "default": 0.3, "live": true, "brightness": true,
			"description": "the light in the door's window"},
	"door_colour": {"type": "color", "default": [1.0, 0.85, 0.6], "description": "the colour of the door's light"},
	"screen_size": {"type": "vec2", "min": 0.0, "max": 8.0, "default": [0.0, 0.0],
			"description": "the picture's width and height ([0, 0]: its own, from the cabin's size)"},
	"screen_bottom": {"type": "float", "min": 0.0, "max": 3.0, "default": 0.0,
			"description": "the picture's bottom edge over the floor (0: its own)"},
	"screen_frame": {"type": "bool", "default": true, "description": "a narrow frame round the picture"},
	"seating": {"type": "enum", "values": ["none", "rows"], "default": "none",
			"description": "none: the viewer's own seat alone; rows: seats in rows either side of an aisle"},
	"rows_front": {"type": "int", "min": 0, "max": 30, "default": 2, "description": "rows in front of the viewer's"},
	"rows_back": {"type": "int", "min": 0, "max": 30, "default": 1, "description": "rows behind the viewer's"},
	"row_pitch": {"type": "float", "min": 0.7, "max": 2.0, "default": 0.9, "description": "metres a row"},
	"seats_left": {"type": "int", "min": 0, "max": 4, "default": 2, "description": "seats in a row left of the aisle"},
	"seats_right": {"type": "int", "min": 0, "max": 4, "default": 2,
			"description": "seats in a row right of the aisle"},
	"seat_pitch": {"type": "float", "min": 0.42, "max": 1.0, "default": 0.5, "description": "seat centres, metres"},
	"aisle": {"type": "float", "min": 0.3, "max": 2.0, "default": 0.5, "description": "the aisle's width"},
	"own_side": {"type": "enum", "values": ["left", "right"], "default": "right",
			"description": "which block the viewer's own seat is in"},
	"own_index": {"type": "int", "min": 0, "max": 3, "default": 0,
			"description": "the viewer's own seat's place in that block, 0 by the aisle"},
	"seat_model": {"type": "enum", "values": ["none", "folding", "director", "club", "plush"], "default": "plush",
			"description": "the plain seat drawn when the room has no seats system (none: no seats drawn)"},
	"ledge": {"type": "float", "min": 0.0, "max": 1.5, "default": 0.0,
			"description": "a ledge outside each windowed wall, this wide (0: none)"},
	"ledge_y": {"type": "float", "min": -1.0, "max": 2.5, "default": 0.7, "description": "the ledge's height"},
	"walls": {"type": "material", "default": {"library": "rough_plaster", "color": [0.78, 0.74, 0.64]},
			"description": "the side walls above the dado"},
	"dado": {"type": "material", "default": {"library": "wood_panelling", "color": [0.28, 0.17, 0.1]},
			"description": "the dado"},
	"ceiling": {"type": "material", "default": {"library": "rough_plaster", "color": [0.8, 0.78, 0.72]},
			"description": "the roof's inside"},
	"floor": {"type": "material", "default": {"library": "rustic_planks", "color": [0.3, 0.2, 0.13]},
			"description": "the floor"},
	"trim": {"type": "material", "default": {"library": "walnut_veneer", "color": [0.22, 0.13, 0.08]},
			"description": "the window frames, rails, ribs, the screen's frame, the door, the lamps' fittings"},
	"bulkhead": {"type": "material", "default": {"library": "wood_panelling", "color": [0.3, 0.19, 0.11]},
			"description": "the front and rear bulkheads"},
	"hull": {"type": "material", "default": {"library": "dark_metal", "color": [0.06, 0.06, 0.07]},
			"description": "the ledge outside"},
	"seat_cover": {"type": "material", "default": {"library": "felt", "color": [0.35, 0.1, 0.1]},
			"description": "the seats' cover"},
	"seat_frame": {"type": "material", "default": {"library": "dark_metal", "color": [0.12, 0.12, 0.12]},
			"description": "the seats' frames"},
}


# --- From parameters alone ----------------------------------------------------------------------------------------

## A copy of p with the values every other static function works from: L (the lean in radians), hw, wall_len,
## top_half, rise, headroom, cx, dado (the dado's height as built), window_zs (the kept windows' middles),
## window_sides_s (the windowed sides, -1 and +1), r (the corners' radius), and window_height, screen_size and
## screen_bottom as built.
static func resolved(p: Dictionary) -> Dictionary:
	var out := p.duplicate()
	var lean := deg_to_rad(float(p["lean"]))
	var hw := float(p["width"]) * 0.5
	var wall_h := float(p["wall_height"])
	out["L"] = lean
	out["hw"] = hw
	out["wall_len"] = wall_h / cos(lean)
	var top_half := hw - wall_h * tan(lean)
	out["top_half"] = top_half
	var rise := float(p["roof_rise"]) if str(p["roof"]) == "arched" else 0.0
	out["rise"] = rise
	var headroom := wall_h + rise
	out["headroom"] = headroom
	# Rows with no seat in either block are no rows: the viewer's own seat alone, on centre_x.
	if str(p["seating"]) == "rows" and int(p["seats_left"]) + int(p["seats_right"]) <= 0:
		out["seating"] = "none"
	out["cx"] = -_own_offset(p) if str(out["seating"]) == "rows" else float(p["centre_x"])
	# The windows: those that stay clear of the bulkheads, no higher than the walls allow.
	var fz := float(p["front_z"])
	var bz := float(p["back_z"])
	var ww := float(p["window_width"])
	var sides: Array[float] = []
	match str(p["window_sides"]):
		"both":
			sides = [-1.0, 1.0]
		"left":
			sides = [-1.0]
		"right":
			sides = [1.0]
	var zs: Array[float] = []
	if not sides.is_empty():
		for k in int(p["window_count"]):
			var z := float(p["window_from_z"]) + k * float(p["bay_pitch"])
			if z - ww / 2.0 >= fz + 0.15 and z + ww / 2.0 <= bz - 0.15:
				zs.append(z)
	var sill := float(p["window_sill"])
	var wh := float(p["window_height"])
	if sill + wh > wall_h - 0.05:
		wh = maxf(wall_h - 0.05 - sill, 0.0)
	# A sill so high that the wall leaves a window under a hand's height: no windows, not slits and not openings
	# with nothing in them.
	if wh < MIN_WINDOW:
		zs.clear()
	if zs.is_empty():
		sides = []
	out["window_zs"] = zs
	out["window_sides_s"] = sides
	out["window_height"] = wh
	out["r"] = minf(float(p["window_round"]), minf(ww / 2.0, wh / 2.0))
	out["dado"] = minf(float(p["dado_height"]), sill) if not zs.is_empty() else float(p["dado_height"])
	# The screen.
	var ss := U.v2(p["screen_size"])
	var w := ss.x
	var h := ss.y
	# A 0 in screen_size is worked out. Both: the cabin's own picture. One: 16:9 from the other, so a room can ask
	# for a width and let the height follow.
	if w == 0.0 and h == 0.0:
		w = clampf(top_half * 2.0 - 0.5, 0.6, 3.2)
		h = w * 9.0 / 16.0
		if h > headroom - 0.95:
			h = headroom - 0.95
			w = h * 16.0 / 9.0
	elif h == 0.0:
		h = w * 9.0 / 16.0
	elif w == 0.0:
		w = h * 16.0 / 9.0
	out["screen_size"] = [w, h]
	var bottom := float(p["screen_bottom"])
	if bottom == 0.0:
		bottom = clampf(1.3 - h / 2.0, 0.75, headroom - 0.12 - h)
	out["screen_bottom"] = bottom
	return out


## The viewer's own seat's offset from the centre line (with seating rows): positive in the right block.
static func _own_offset(p: Dictionary) -> float:
	var right := str(p["own_side"]) == "right"
	var n := int(p["seats_right"]) if right else int(p["seats_left"])
	if n <= 0:
		right = not right
		n = int(p["seats_right"]) if right else int(p["seats_left"])
	# (Rows with no seat in either block are seating none: resolved() never asks then.)
	var idx := clampi(int(p["own_index"]), 0, maxi(n - 1, 0))
	var o := float(p["aisle"]) / 2.0 + float(p["seat_pitch"]) * (idx + 0.5)
	return o if right else -o


## A point of side s's wall by (u along Z, v up the slope from the floor).
static func _pt(q: Dictionary, s: float, u: float, v: float) -> Vector3:
	return Vector3(float(q["cx"]) + s * float(q["hw"]), 0.0, 0.0) + _up(q, s) * v + Vector3(0.0, 0.0, u)


## Up the slope of side s's wall.
static func _up(q: Dictionary, s: float) -> Vector3:
	var lean := float(q["L"])
	return Vector3(-s * sin(lean), cos(lean), 0.0)


## Side s's wall's inward normal.
static func _n(q: Dictionary, s: float) -> Vector3:
	var lean := float(q["L"])
	return Vector3(-s * cos(lean), -sin(lean), 0.0)


## Side s's wall's frame: x along the wall, y up its slope, z its inward normal (a piece's front faces +Z).
static func _wall_basis(q: Dictionary, s: float) -> Basis:
	return Basis(_up(q, s).cross(_n(q, s)), _up(q, s), _n(q, s))


## The roof's points across the section (x, y), left to right, and their normals (into the cabin).
static func _roof(q: Dictionary) -> Array:
	var cx := float(q["cx"])
	var th := float(q["top_half"])
	var wall_h := float(q["wall_height"])
	var rise := float(q["rise"])
	var pts := PackedVector2Array()
	var normals := PackedVector2Array()
	if rise < 0.001:
		pts.append_array([Vector2(cx - th, wall_h), Vector2(cx + th, wall_h)])
		normals.append_array([Vector2.DOWN, Vector2.DOWN])
		return [pts, normals]
	var r := (th * th + rise * rise) / (2.0 * rise)
	var y0 := wall_h + rise - r
	var a := asin(th / r)
	for i in ROOF_STEPS + 1:
		var t := -a + 2.0 * a * i / ROOF_STEPS
		pts.append(Vector2(cx + r * sin(t), y0 + r * cos(t)))
		normals.append(Vector2(-sin(t), -cos(t)))
	return [pts, normals]


## Where the bays meet: half a bay_pitch before the first window, between each pair, after the last. With no windows
## the cabin's middle alone.
static func _bay_marks(q: Dictionary) -> Array[float]:
	var zs: Array[float] = q["window_zs"]
	var out: Array[float] = []
	if zs.is_empty():
		out.append((float(q["front_z"]) + float(q["back_z"])) * 0.5)
		return out
	var bay := float(q["bay_pitch"])
	var marks: Array[float] = [zs[0] - bay * 0.5]
	for i in range(1, zs.size()):
		marks.append((zs[i - 1] + zs[i]) * 0.5)
	marks.append(zs[-1] + bay * 0.5)
	# A mark is kept only where it is inside the cabin with room for what stands at it (a rib, a wall lamp, a
	# side_walls slot): the first and the last can fall in a bulkhead or beyond it.
	for z in marks:
		if z >= float(q["front_z"]) + MARK_MARGIN and z <= float(q["back_z"]) - MARK_MARGIN:
			out.append(z)
	return out


## A window's outline in the wall's (u, v): its box with corners of radius r, as [points, outward directions, grow
## vectors (a point grown outwards by g moves by g times its vector)]. A point that repeats the one before it (a
## corner's radius half the box) is left out.
static func _outline(mid: Vector2, half: Vector2, r: float) -> Array:
	var pts := PackedVector2Array()
	var dirs := PackedVector2Array()
	var grows := PackedVector2Array()
	var corners: Array[Vector2] = [Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1)]
	for qi in 4:
		var c: Vector2 = corners[qi]
		if r > 0.0:
			var centre := mid + c * (half - Vector2(r, r))
			var a0 := -PI * 0.5 + qi * PI * 0.5
			for j in CORNER_STEPS + 1:
				var a := a0 + j * PI * 0.5 / CORNER_STEPS
				var d := Vector2(cos(a), sin(a))
				var p := centre + d * r
				if not pts.is_empty() and p.distance_to(pts[-1]) < 1e-6:
					continue
				pts.append(p)
				dirs.append(d)
				grows.append(d)
		else:
			# A square corner grows along both edges, so the frame keeps its width.
			pts.append(mid + c * half)
			dirs.append(c.normalized())
			grows.append(c)
	if pts.size() > 1 and pts[-1].distance_to(pts[0]) < 1e-6:
		pts.remove_at(pts.size() - 1)
		dirs.remove_at(dirs.size() - 1)
		grows.remove_at(grows.size() - 1)
	return [pts, dirs, grows]


static func _box(p: Dictionary) -> AABB:
	var q := resolved(p)
	var hw := float(q["hw"])
	var lo := Vector3(float(q["cx"]) - hw, 0.0, float(q["front_z"]))
	return AABB(lo, Vector3(hw * 2.0, float(q["headroom"]), float(q["back_z"]) - lo.z))


static func seat_slots_for(p: Dictionary) -> Array:
	var q := resolved(p)
	var out: Array = []
	if str(q["seating"]) != "rows":
		out.append(U.slot(Transform3D(), 0, "club", 0.7))
		return out
	var cx := float(q["cx"])
	var half_aisle := float(q["aisle"]) / 2.0
	var pitch := float(q["seat_pitch"])
	for row in range(-int(q["rows_back"]), int(q["rows_front"]) + 1):
		var z := -row * float(q["row_pitch"])
		if absf(z - float(q["front_z"])) < 0.5 or absf(z - float(q["back_z"])) < 0.5:
			continue
		for i in range(int(q["seats_left"]) - 1, -1, -1):
			out.append(U.slot(Transform3D(Basis(), Vector3(cx - half_aisle - pitch * (i + 0.5), 0.0, z)), row,
					"chair", pitch))
		for i in int(q["seats_right"]):
			out.append(U.slot(Transform3D(Basis(), Vector3(cx + half_aisle + pitch * (i + 0.5), 0.0, z)), row,
					"chair", pitch))
	return out


static func layout(p: Dictionary) -> SeatList:
	return SeatList.new(seat_slots_for(p))


## The picture hangs flat on the front bulkhead and says so (`facing`). A screen that does not say which way it
## faces is turned towards the room's own seat, and with rows that seat is beside the aisle, off the cabin's centre
## line: the picture would turn a few degrees and one edge of it go through the bulkhead (the Showboat's did, by
## 0.17 m, 2026-11-10). Someone in an aisle seat of a real hall sees the picture a little from the side too.
static func screen_for(p: Dictionary) -> Dictionary:
	var q := resolved(p)
	var s := U.v2(q["screen_size"])
	return {"center": [float(q["cx"]), float(q["screen_bottom"]) + s.y / 2.0, float(q["front_z"]) + 0.03],
			"size": [s.x, s.y], "facing": [0.0, 0.0, 1.0]}


static func collision_shapes_for(p: Dictionary, with_seats := true) -> Array:
	var box := _box(p)
	var out := U.shell_boxes(box.position, box.end)
	if with_seats and str(p["seat_model"]) != "none":
		out.append_array(U.seat_boxes(seat_slots_for(p), str(p["seat_model"])))
	return out


## Every window: {side, center (the middle of the opening on the wall's inner plane), size, normal}.
static func window_boxes_for(p: Dictionary) -> Array:
	var q := resolved(p)
	var lean := float(q["L"])
	var vs := float(q["window_sill"]) / cos(lean)
	var vt := (float(q["window_sill"]) + float(q["window_height"])) / cos(lean)
	var out: Array = []
	for s: float in q["window_sides_s"]:
		for z: float in q["window_zs"]:
			out.append({"side": s, "center": _pt(q, s, z, (vs + vt) * 0.5),
					"size": Vector2(float(q["window_width"]), float(q["window_height"])), "normal": _n(q, s)})
	return out


static func slots_for(p: Dictionary) -> Dictionary:
	var q := resolved(p)
	var box := _box(p)
	var cx := float(q["cx"])
	var lean := float(q["L"])
	var dado := float(q["dado"])
	var wall_h := float(q["wall_height"])
	var headroom := float(q["headroom"])
	var t := float(q["wall_thickness"])
	var ww := float(q["window_width"])
	var wh := float(q["window_height"])
	var walls: Array = []
	var bay_size := [float(q["bay_pitch"]) - ww, wall_h - dado, 0.3]
	if (q["window_zs"] as Array).is_empty() or (q["window_sides_s"] as Array).is_empty():
		bay_size = [1.0, wall_h - dado, 0.3]
	# On both walls, also with windows on one side only: the wall without them has the same bays to dress.
	for s: float in [-1.0, 1.0]:
		for z: float in _bay_marks(q):
			walls.append({"transform": Transform3D(_wall_basis(q, s), _pt(q, s, z, dado / cos(lean))),
					"size": bay_size.duplicate()})
	var sills: Array = []
	var windows: Array = []
	var vs := float(q["window_sill"]) / cos(lean)
	var vt := (float(q["window_sill"]) + wh) / cos(lean)
	for s: float in q["window_sides_s"]:
		for z: float in q["window_zs"]:
			sills.append({"transform": Transform3D(_wall_basis(q, s), _pt(q, s, z, vs)), "size": [ww, wh, t]})
			windows.append({"transform": Transform3D(_wall_basis(q, s), _pt(q, s, z, (vs + vt) * 0.5) - _n(q, s) * t),
					"size": [ww, wh, 0.0]})
	var sc: Dictionary = screen_for(p)
	var ss := U.v2(sc["size"])
	var mid := box.get_center()
	var corners: Array = []
	for x: float in [box.position.x, box.end.x]:
		for z: float in [box.position.z, box.end.z]:
			var into := Vector3(mid.x - x, 0.0, mid.z - z).normalized()
			corners.append({"transform": Transform3D(Basis(Vector3.UP.cross(into), Vector3.UP, into), Vector3(x, 0.0, z)),
					"size": [0.4, headroom, 0.4]})
	return {
		"side_walls": walls,
		"window_sills": sills,
		"windows": windows,
		"screen": [{"transform": Transform3D(Basis(), U.v3(sc["center"])), "size": [ss.x, ss.y, 0.1]}],
		"proscenium": [{"transform": Transform3D(Basis(), Vector3(cx, 0.0, box.position.z)),
				"size": [box.size.x, headroom, 0.5]}],
		"rear_wall": [{"transform": Transform3D(Basis(Vector3.UP, PI), Vector3(cx, 0.0, box.end.z)),
				"size": [box.size.x, headroom, 0.3]}],
		"ceiling": [{"transform": Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(cx, headroom, mid.z)),
				"size": [box.size.x, box.size.z, 0.2]}],
		"floor": [{"transform": Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(cx, 0.0, mid.z)),
				"size": [box.size.x, box.size.z, 0.0]}],
		"corners": corners,
	}


func sound_room() -> Dictionary:
	var q := resolved(params)
	return {"box": _box(params), "surround_height": minf(1.6, float(q["headroom"]) - 0.3), "array": 1,
			"array_spacing": 2.0}


# --- Building -----------------------------------------------------------------------------------------------------

var _door_glow: ShaderMaterial


func build() -> void:
	var q := resolved(params)
	var cx := float(q["cx"])
	var hw := float(q["hw"])
	var fz := float(q["front_z"])
	var bz := float(q["back_z"])
	# The floor.
	var fl := RoomMesh.new()
	fl.surface(_mat("floor"))
	fl.face([Vector3(cx - hw, 0.0, fz), Vector3(cx + hw, 0.0, fz), Vector3(cx + hw, 0.0, bz), Vector3(cx - hw, 0.0, bz)],
			Vector3.UP)
	_add_static("Floor", fl)
	var trim := RoomMesh.new()
	trim.surface(_mat("trim"))
	_build_lining(q)
	_build_windows(q, trim)
	_build_ribs(q, trim)
	_build_screen_frame(q, trim)
	_build_door(q, trim)
	_build_lamps(q, trim)
	_add_static("Trim", trim)
	_build_hull(q)
	if str(params["seat_model"]) != "none":
		_build_seat_multimesh(str(params["seat_model"]), _mat("seat_cover", true), _mat("seat_frame", true),
				seat_slots_for(params), 77)


## The dado, the walls above it with the windows' openings, the roof, the bulkheads.
func _build_lining(q: Dictionary) -> void:
	var lean := float(q["L"])
	var fz := float(q["front_z"])
	var bz := float(q["back_z"])
	var vd := float(q["dado"]) / cos(lean)
	var wall_len := float(q["wall_len"])
	var lin := RoomMesh.new()
	lin.surface(_mat("dado"))
	if vd > 0.0:
		for s: float in [-1.0, 1.0]:
			_wall_face(lin, q, s, fz, bz, 0.0, vd)
	lin.surface(_mat("walls"))
	var zs: Array[float] = q["window_zs"]
	var sides: Array[float] = q["window_sides_s"]
	var ww := float(q["window_width"])
	var vs := float(q["window_sill"]) / cos(lean)
	var vt := (float(q["window_sill"]) + float(q["window_height"])) / cos(lean)
	var r := float(q["r"])
	for s: float in [-1.0, 1.0]:
		if not (s in sides):
			_wall_face(lin, q, s, fz, bz, vd, wall_len)
			continue
		# Cells cut at the midpoints between neighbouring windows; each wraps its window's box.
		for i in zs.size():
			var u0 := fz if i == 0 else (zs[i - 1] + zs[i]) * 0.5
			var u1 := bz if i == zs.size() - 1 else (zs[i] + zs[i + 1]) * 0.5
			var ua := zs[i] - ww / 2.0
			var ub := zs[i] + ww / 2.0
			_wall_face(lin, q, s, u0, u1, vd, vs)
			_wall_face(lin, q, s, u0, u1, vt, wall_len)
			_wall_face(lin, q, s, u0, ua, vs, vt)
			_wall_face(lin, q, s, ub, u1, vs, vt)
			if r <= 0.0:
				continue
			# The round corners: the space between the box's square corner and the round one.
			var mid := Vector2(zs[i], (vs + vt) * 0.5)
			var half := Vector2(ww / 2.0, (vt - vs) / 2.0)
			var corners: Array[Vector2] = [Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1)]
			for qi in 4:
				var c: Vector2 = corners[qi]
				var centre := mid + c * (half - Vector2(r, r))
				var poly := PackedVector3Array([_pt(q, s, mid.x + c.x * half.x, mid.y + c.y * half.y)])
				for j in CORNER_STEPS + 1:
					var a := -PI * 0.5 + qi * PI * 0.5 + j * PI * 0.5 / CORNER_STEPS
					var p := centre + Vector2(cos(a), sin(a)) * r
					poly.append(_pt(q, s, p.x, p.y))
				lin.polygon(poly, _n(q, s))
	# The roof.
	lin.surface(_mat("ceiling"))
	var roof: Array = _roof(q)
	var pts: PackedVector2Array = roof[0]
	var normals: PackedVector2Array = roof[1]
	if float(q["rise"]) < 0.001:
		var y := float(q["wall_height"])
		lin.face([Vector3(pts[0].x, y, fz), Vector3(pts[1].x, y, fz), Vector3(pts[1].x, y, bz), Vector3(pts[0].x, y, bz)],
				Vector3.DOWN)
	else:
		var front := PackedVector3Array()
		var back := PackedVector3Array()
		var n3 := PackedVector3Array()
		for i in pts.size():
			front.append(Vector3(pts[i].x, pts[i].y, fz))
			back.append(Vector3(pts[i].x, pts[i].y, bz))
			n3.append(Vector3(normals[i].x, normals[i].y, 0.0))
		lin.strip(front, back, n3)
	# The bulkheads: the section's outline (the roof's points begin and end at the walls' tops).
	lin.surface(_mat("bulkhead"))
	var cx := float(q["cx"])
	var hw := float(q["hw"])
	for end: Array in [[fz, Vector3.BACK], [bz, Vector3.FORWARD]]:
		var z: float = end[0]
		var outline := PackedVector3Array([Vector3(cx - hw, 0.0, z)])
		for p: Vector2 in pts:
			outline.append(Vector3(p.x, p.y, z))
		outline.append(Vector3(cx + hw, 0.0, z))
		lin.polygon(outline, end[1])
	_add_static("Lining", lin)


## One face of side s's wall, u0..u1 along Z, v0..v1 up the slope; nothing when it has no area.
func _wall_face(b: RoomMesh, q: Dictionary, s: float, u0: float, u1: float, v0: float, v1: float) -> void:
	if u1 - u0 < 1e-6 or v1 - v0 < 1e-6:
		return
	b.face([_pt(q, s, u0, v0), _pt(q, s, u1, v0), _pt(q, s, u1, v1), _pt(q, s, u0, v1)], _n(q, s))


## Each window's frame and reveal (trim) and its glass.
func _build_windows(q: Dictionary, trim: RoomMesh) -> void:
	var lean := float(q["L"])
	var ww := float(q["window_width"])
	var vs := float(q["window_sill"]) / cos(lean)
	var vt := (float(q["window_sill"]) + float(q["window_height"])) / cos(lean)
	var fw := float(q["frame_width"])
	var fd := float(q["frame_depth"])
	var t := float(q["wall_thickness"])
	var glass := RoomMesh.new()
	glass.surface(GLASS)
	for s: float in q["window_sides_s"]:
		var n := _n(q, s)
		var up := _up(q, s)
		for z: float in q["window_zs"]:
			var o: Array = _outline(Vector2(z, (vs + vt) * 0.5), Vector2(ww / 2.0, (vt - vs) / 2.0), float(q["r"]))
			var pts: PackedVector2Array = o[0]
			var dirs: PackedVector2Array = o[1]
			var grows: PackedVector2Array = o[2]
			var inner := PackedVector3Array()
			var outer := PackedVector3Array()
			var face_n := PackedVector3Array()
			var wall_line := PackedVector3Array()
			var out_line := PackedVector3Array()
			var reveal_n := PackedVector3Array()
			var pane := PackedVector3Array()
			for k in pts.size() + 1:
				var i := k % pts.size()
				var p := _pt(q, s, pts[i].x, pts[i].y)
				var g := pts[i] + grows[i] * fw
				inner.append(p + n * fd)
				outer.append(_pt(q, s, g.x, g.y) + n * fd)
				face_n.append(n)
				wall_line.append(p)
				out_line.append(p - n * t)
				reveal_n.append(-(Vector3(0.0, 0.0, dirs[i].x) + up * dirs[i].y).normalized())
				if k < pts.size():
					pane.append(p - n * t)
			trim.strip(inner, outer, face_n)
			trim.strip(wall_line, out_line, reveal_n)
			glass.polygon(pane, n)
	# Fainter than a hall's glass (0.06, and 0.22 more where the view grazes it): a cabin's windows are an arm's
	# length from a bright picture and are looked through at night, and at a hall's strength the picture's light
	# on the panes was a grey veil over everything outside (2026-11-09, the Narrowboat's wharf at night).
	var panes := _add_glass("Glass", glass, GLASS_TINT, GLASS_ALPHA)
	if panes != null and panes.material_override is ShaderMaterial:
		(panes.material_override as ShaderMaterial).set_shader_parameter("rim", GLASS_RIM)


## The dado's rail, and the ribs at the bays' marks up both walls and under the roof.
func _build_ribs(q: Dictionary, trim: RoomMesh) -> void:
	var lean := float(q["L"])
	var fz := float(q["front_z"])
	var bz := float(q["back_z"])
	var vd := float(q["dado"]) / cos(lean)
	var wall_len := float(q["wall_len"])
	if vd > 0.0:
		for s: float in [-1.0, 1.0]:
			# The rail sits across the join: half on the dado, half on the wall above.
			trim.box(_pt(q, s, (fz + bz) * 0.5, vd) + _n(q, s) * 0.02, Vector3(bz - fz, 0.03, 0.04), _wall_basis(q, s),
					[RoomMesh.FRONT])
	if not bool(q["ribs"]) or (q["window_zs"] as Array).is_empty():
		return
	var rw := float(q["rib_width"])
	var rd := float(q["rib_depth"])
	var roof: Array = _roof(q)
	var pts: PackedVector2Array = roof[0]
	var normals: PackedVector2Array = roof[1]
	for z: float in _bay_marks(q):
		for s: float in [-1.0, 1.0]:
			trim.box(_pt(q, s, z, (vd + wall_len) * 0.5) + _n(q, s) * rd * 0.5, Vector3(rw, wall_len - vd, rd),
					_wall_basis(q, s), [RoomMesh.FRONT])
		if float(q["rise"]) < 0.001:
			trim.box(Vector3(float(q["cx"]), float(q["wall_height"]) - rd * 0.5, z),
					Vector3(float(q["top_half"]) * 2.0, rd, rw), Basis(), [RoomMesh.UP])
			continue
		var a := PackedVector3Array()
		var b := PackedVector3Array()
		var n3 := PackedVector3Array()
		for i in pts.size():
			var p := pts[i] + normals[i] * rd
			a.append(Vector3(p.x, p.y, z - rw * 0.5))
			b.append(Vector3(p.x, p.y, z + rw * 0.5))
			n3.append(Vector3(normals[i].x, normals[i].y, 0.0))
		trim.strip(a, b, n3)


## Four boxes round the picture, on the front bulkhead.
func _build_screen_frame(q: Dictionary, trim: RoomMesh) -> void:
	if not bool(q["screen_frame"]):
		return
	var sc := screen_for(params)
	var c := U.v3(sc["center"])
	var size := U.v2(sc["size"])
	var t := 0.04
	var z := float(q["front_z"]) + 0.015
	# At the picture's edge, with none of the 0.08 a hall's frame leaves round its picture: a cabin's picture
	# is as large as its bulkhead allows, and a frame stood off from it would cut into the roof's arch.
	var half := size * 0.5
	for s: float in [-1.0, 1.0]:
		trim.box(Vector3(c.x + s * (half.x + t * 0.5), c.y, z), Vector3(t, half.y * 2.0 + t * 2.0, 0.03), Basis(),
				[RoomMesh.FRONT])
		trim.box(Vector3(c.x, c.y + s * (half.y + t * 0.5), z), Vector3(half.x * 2.0, t, 0.03), Basis(),
				[RoomMesh.FRONT])


## The rear door, its handle, and the light in its window.
func _build_door(q: Dictionary, trim: RoomMesh) -> void:
	if str(q["rear_door"]) != "centre":
		return
	var cx := float(q["cx"])
	var bz := float(q["back_z"])
	var dh := minf(1.85, float(q["headroom"]) - 0.1)
	trim.box(Vector3(cx, dh * 0.5, bz - 0.01), Vector3(0.62, dh, 0.02), Basis(), [RoomMesh.BACK])
	# Seen from inside (facing +Z), the right is -X.
	trim.box(Vector3(cx - 0.24, 1.0, bz - 0.02 - 0.015), Vector3(0.02, 0.1, 0.03), Basis(), [RoomMesh.BACK])
	var glow := RoomMesh.new()
	_door_glow = _lamp(color_param("door_colour"), float(params["door_glow"]), 0.0, "accent")
	glow.surface(_door_glow)
	var z := bz - 0.02 - 0.012
	glow.face([Vector3(cx - 0.15, 1.3, z), Vector3(cx + 0.15, 1.3, z), Vector3(cx + 0.15, 1.7, z),
			Vector3(cx - 0.15, 1.7, z)], Vector3.FORWARD)
	_add_lamps("DoorGlow", glow)


## The lamps under the roof's middle at each window, or on the walls between the windows; their fittings in the trim
## and a bake light each.
func _build_lamps(q: Dictionary, trim: RoomMesh) -> void:
	var kind := str(q["lamps"])
	if kind == "none":
		return
	var colour := color_param("lamp_colour")
	var lamps := RoomMesh.new()
	lamps.surface(_lamp(colour, 1.0, 1.0, "house"))
	var i := 0
	if kind == "ceiling":
		var cx := float(q["cx"])
		var top := float(q["headroom"])
		var zs: Array[float] = []
		zs.assign(q["window_zs"])
		if zs.is_empty():
			zs.append((float(q["front_z"]) + float(q["back_z"])) * 0.5)
		for z in zs:
			lamps.box(Vector3(cx, top - 0.002 - 0.0175, z), Vector3(0.16, 0.035, 0.16), Basis(), [RoomMesh.UP])
			trim.box(Vector3(cx, top - 0.001 - 0.01, z), Vector3(0.2, 0.02, 0.2), Basis(), [RoomMesh.UP])
			# The bake's light hangs 0.12 under the lamp's glass, clear of the roof it would otherwise burn out.
			_bake_omni("CabinLamp%d" % i, Vector3(cx, top - 0.037 - 0.12, z), 3.5, 0.6, colour)
			i += 1
	else:
		var v := float(q["lamp_height"]) / cos(float(q["L"]))
		# At the bays' marks (with no windows: one a side at the cabin's middle, as the side_walls slots). A lamp
		# stands at the end of its arm, its back 0.06 out from the wall.
		for s: float in [-1.0, 1.0]:
			var n := _n(q, s)
			var basis := _wall_basis(q, s)
			for z: float in _bay_marks(q):
				var at := _pt(q, s, z, v)
				var lamp_at := at + n * (0.06 + 0.035)
				lamps.box(lamp_at, Vector3(0.07, 0.1, 0.07), basis, [])
				trim.box(at + n * 0.03, Vector3(0.02, 0.02, 0.06), basis, [RoomMesh.FRONT])
				_bake_omni("CabinLamp%d" % i, lamp_at, 2.5, 0.35, colour)
				i += 1
	_add_lamps("Lamps", lamps)


## The ledge outside each windowed wall, with an upstand at its outer edge.
func _build_hull(q: Dictionary) -> void:
	var ledge := float(q["ledge"])
	if ledge <= 0.0:
		return
	var lean := float(q["L"])
	var t := float(q["wall_thickness"])
	var y := float(q["ledge_y"])
	var fz := float(q["front_z"]) - 2.0
	var bz := float(q["back_z"]) + 2.0
	var hull := RoomMesh.new()
	hull.surface(_mat("hull"))
	for s: float in q["window_sides_s"]:
		# The wall's outer plane (its inner plane moved by -N * wall_thickness) at height y.
		var v := (y - sin(lean) * t) / cos(lean)
		var x0 := float(q["cx"]) + s * (float(q["hw"]) - sin(lean) * v + cos(lean) * t)
		var x1 := x0 + s * ledge
		hull.face([Vector3(x0, y, fz), Vector3(x1, y, fz), Vector3(x1, y, bz), Vector3(x0, y, bz)], Vector3.UP)
		hull.box(Vector3(x1 - s * 0.015, y + 0.025, (fz + bz) * 0.5), Vector3(0.03, 0.05, bz - fz), Basis(),
				[RoomMesh.DOWN])
	_add_unbaked("Hull", hull)


func _param_changed(param: String, value: Variant) -> void:
	if param == "door_glow" and _door_glow != null:
		_door_glow.set_shader_parameter("energy", float(value) * _group_level("accent"))
