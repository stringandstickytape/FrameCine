extends "res://scripts/env/systems/kit/builder.gd"

## The vehicle builder (docs/environments.md, "The builders"): the inside of a generic 1950s convertible with its top
## down, parked facing the screen (a drive-in: on a terrace builder's lot, ground_y about -0.5). A front bench seat
## with three places (the viewer's in the middle, at the origin), a rear bench, a long bonnet ahead, a wraparound
## windscreen in a chrome frame (its glass is see-through; its top stays under the eyes, so the view of a screen up on
## a lot's frame or tower goes over it), a painted dashboard with softly lit dials, a steering wheel in front of the
## left place, doors, tail fins, chrome bumpers, whitewall tyres. No mirror, no badge, no maker's shape: generic.
##   Body (the body, the cabin, the windscreen's frame: baked), Fittings (benches, the dash's top, chrome, tyres, the
##   folded top: unbaked), Wheel (the steering wheel), Dials, Windscreen (glass),
##   Lamps (headlamps and tail lamps)
## Slots for the kit: dash (its top), bonnet (the bonnet's top, at the front), rear_shelf (behind the rear bench), floor.

static func spec() -> Dictionary:
	return {
		"kind": "builder",
		"description": "The inside of a generic 1950s convertible with its top down, facing the screen (on a "
				+ "drive-in's lot): a front bench for three (the viewer in the middle), a rear bench, a long bonnet, a "
				+ "wraparound windscreen in chrome under the eye line, a painted dashboard with softly lit dials, a "
				+ "steering wheel, tail fins, whitewall tyres.",
		"params": PARAMS,
		"requires": ["light"],
		"provides": ["seats", "collision", "bake", "slots"],
		"cost": {"draws": 16, "triangles": 6000, "lights": 0, "particles": 0, "texture_mb": 10},
	}


const PARAMS := {
	"ground_y": {"type": "float", "min": -2.0, "max": 0.0, "default": -0.5,
			"description": "the ground under the car (the cabin's floor is at 0)"},
	"rear_seat": {"type": "bool", "default": true, "description": "a rear bench with three more places"},
	"top": {"type": "enum", "values": ["folded", "none"], "default": "folded",
			"description": "the soft top folded behind the rear bench under its cover, or none"},
	"fins": {"type": "float", "min": 0.0, "max": 0.6, "default": 0.32, "description": "the tail fins' rise, metres"},
	"headlamps": {"type": "float", "min": 0.0, "max": 2.0, "default": 0.0, "live": true, "brightness": true,
			"description": "the headlamps' and tail lamps' glow (off while parked for the film)"},
	"dial_glow": {"type": "float", "min": 0.0, "max": 2.0, "default": 0.5, "live": true, "brightness": true,
			"description": "the dashboard dials' soft light"},
	"dial_colour": {"type": "color", "default": [0.55, 0.85, 0.75], "description": "the dials' light"},
	"body": {"type": "material", "default": {"library": "dark_metal", "color": [0.42, 0.66, 0.64]},
			"description": "the paint"},
	"chrome": {"type": "material", "default": {"library": "brushed_steel", "color": [0.82, 0.83, 0.85]},
			"description": "the bumpers, the windscreen's frame, the trim"},
	"upholstery": {"type": "material", "default": {"library": "oxblood_leather", "color": [0.6, 0.14, 0.11]},
			"description": "the benches and the door panels"},
	"piping": {"type": "material", "default": {"library": "brown_leather", "color": [0.86, 0.8, 0.7]},
			"description": "the benches' second colour (their sides and the door panels' tops)"},
	"carpet": {"type": "material", "default": {"library": "woven_carpet", "color": [0.2, 0.08, 0.07]},
			"description": "the floor"},
	"tyres": {"type": "material", "default": {"library": "black_leather", "color": [0.04, 0.04, 0.04]},
			"description": "the tyres"},
	"hood_cover": {"type": "material", "default": {"library": "linen", "color": [0.82, 0.78, 0.68]},
			"description": "the folded top's cover"},
}

## The car's plan (metres, the viewer's seat at the origin, the bonnet towards -Z).
const HALF := 0.98
const INNER := 0.8
const FRONT := -3.0
const DASH_Z := -0.9
const CABIN_BACK := 1.62
const REAR := 2.8
const BELT := 0.72
const BODY_BOTTOM := -0.28
const PLACE := 0.55
const REAR_BENCH_Z := 1.12
const WINDSCREEN_TOP := 1.12
const WHEEL_R := 0.36
const AXLES: Array[float] = [-2.05, 1.85]
## The wheel arches: half their length, their top.
const ARCH := 0.46
const ARCH_TOP := 0.3


# --- From parameters alone ----------------------------------------------------------------------------------------

static func seat_slots_for(p: Dictionary) -> Array:
	var out := U.row(0.0, 0.0, 3, PLACE, 0, "bench")
	if bool(p["rear_seat"]):
		out.append_array(U.row(REAR_BENCH_Z, 0.0, 3, PLACE, -1, "bench"))
	return out


static func layout(p: Dictionary) -> SeatList:
	return SeatList.new(seat_slots_for(p))


## The car brings no screen: this is a drive-in lot's (the terrace builder's lot preset), so a test room has one.
static func screen_for(p: Dictionary) -> Dictionary:
	return {"center": [0.0, float(p["ground_y"]) + 9.0, -49.4], "size": [24.0, 10.0]}


## A bench: [seat cushion centre, size, back centre, back size, back tilt degrees].
static func _bench(z: float) -> Array:
	return [Vector3(0, 0.33, z - 0.02), Vector3(INNER * 2.0 - 0.06, 0.2, 0.56), Vector3(0, 0.7, z + 0.33),
			Vector3(INNER * 2.0 - 0.06, 0.52, 0.16), 12.0]


static func collision_shapes_for(p: Dictionary, with_seats := true) -> Array:
	var out: Array = []
	var gy := float(p["ground_y"])
	# Under the cabin's floor, the sides, the bonnet, the boot, the dashboard.
	out.append(PhysicsShapes.box(Vector3(0, (BODY_BOTTOM + 0.0) * 0.5, (FRONT + REAR) * 0.5),
			Vector3(HALF * 2.0, -BODY_BOTTOM, REAR - FRONT)))
	for s: float in [-1.0, 1.0]:
		out.append(PhysicsShapes.box(Vector3(s * (INNER + HALF) * 0.5, BELT * 0.5, (DASH_Z + CABIN_BACK) * 0.5),
				Vector3(HALF - INNER, BELT, CABIN_BACK - DASH_Z)))
	out.append(PhysicsShapes.box(Vector3(0, 0.31, (FRONT + DASH_Z) * 0.5), Vector3(HALF * 2.0, 0.62, DASH_Z - FRONT)))
	out.append(PhysicsShapes.box(Vector3(0, 0.33, (CABIN_BACK + REAR) * 0.5), Vector3(HALF * 2.0, 0.66, REAR - CABIN_BACK)))
	out.append(PhysicsShapes.box(Vector3(0, 0.62, DASH_Z - 0.12), Vector3(INNER * 2.0, 0.32, 0.26)))
	if gy < BODY_BOTTOM - 0.05:
		for z: float in AXLES:
			for s: float in [-1.0, 1.0]:
				out.append(PhysicsShapes.box(Vector3(s * (HALF - 0.12), gy + WHEEL_R, z), Vector3(0.22, WHEEL_R * 2.0,
						WHEEL_R * 2.0)))
	if with_seats:
		var zs: Array[float] = [0.0]
		if bool(p["rear_seat"]):
			zs.append(REAR_BENCH_Z)
		for z in zs:
			var b := _bench(z)
			out.append(PhysicsShapes.box(Vector3(0, 0.2, (b[0] as Vector3).z), Vector3((b[1] as Vector3).x, 0.4,
					(b[1] as Vector3).z)))
			out.append(PhysicsShapes.box(b[2], b[3], Basis(Vector3.RIGHT, deg_to_rad(float(b[4])))))
	return out


static func slots_for(p: Dictionary) -> Dictionary:
	return {
		"dash": [{"transform": Transform3D(Basis(), Vector3(0.3, 0.8, DASH_Z - 0.12)), "size": [0.8, 0.3, 0.2]}],
		"bonnet": [{"transform": Transform3D(Basis(), Vector3(0, 0.62, FRONT + 0.35)), "size": [0.3, 0.2, 0.3]}],
		"rear_shelf": [{"transform": Transform3D(Basis(Vector3.UP, PI), Vector3(0, BELT, CABIN_BACK + 0.15)),
				"size": [INNER * 2.0, 0.3, 0.3]}],
		"floor": [{"transform": Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0.0, (DASH_Z + CABIN_BACK) * 0.5)),
				"size": [INNER * 2.0, CABIN_BACK - DASH_Z, 0.0]}],
	}


# --- Building -----------------------------------------------------------------------------------------------------

var _lamps_m: Array[ShaderMaterial] = []
var _lamp_energy: Array[float] = []
var _dials: ShaderMaterial
var _s: RoomMesh
var _u: RoomMesh
var _mats := {}
## Whether the wheels are drawn (the ground under the body).
var wheels_drawn := false


## A material parameter as a house material, made once for the car (one draw a material).
func _mm(param: String) -> ShaderMaterial:
	if not _mats.has(param):
		_mats[param] = _mat(param)
	return _mats[param]


func build() -> void:
	var gy := float(params["ground_y"])
	var body_m := _mm("body")
	var chrome_m := _mm("chrome")
	# The body's outside: the sides along the cabin, the bonnet, the boot, the fins; static (baked).
	_s = RoomMesh.new()
	_u = RoomMesh.new()
	var body := _s
	body.surface(body_m)
	for s: float in [-1.0, 1.0]:
		# A side along its whole length in pieces round the wheel arches, a dark well inside each arch.
		var zs: Array[float] = [FRONT]
		for a: float in AXLES:
			zs.append_array([a - ARCH, a + ARCH])
		zs.append(REAR)
		for k in zs.size() - 1:
			var y0 := BODY_BOTTOM if k % 2 == 0 else ARCH_TOP
			body.box(Vector3(s * (HALF - 0.09), (y0 + BELT) * 0.5, (zs[k] + zs[k + 1]) * 0.5),
					Vector3(0.18, BELT - y0, zs[k + 1] - zs[k]), Basis(), [Vector3(-s, 0, 0)])
		for a: float in AXLES:
			body.surface(_mm("tyres"))
			body.face([Vector3(s * 0.6, BODY_BOTTOM, a - ARCH), Vector3(s * 0.6, BODY_BOTTOM, a + ARCH),
					Vector3(s * 0.6, ARCH_TOP, a + ARCH), Vector3(s * 0.6, ARCH_TOP, a - ARCH)], Vector3(s, 0, 0))
			body.surface(body_m)
		# The door's top rail.
		body.box(Vector3(s * (INNER + HALF) * 0.5, BELT + 0.02, (DASH_Z + CABIN_BACK) * 0.5),
				Vector3(HALF - INNER + 0.02, 0.04, CABIN_BACK - DASH_Z), Basis(), [RoomMesh.DOWN])
	# The bonnet: a long deck sloping a little to the front, the boot's deck behind.
	body.face([Vector3(-HALF + 0.18, 0.62, DASH_Z - 0.25), Vector3(HALF - 0.18, 0.62, DASH_Z - 0.25),
			Vector3(HALF - 0.18, 0.5, FRONT + 0.1), Vector3(-HALF + 0.18, 0.5, FRONT + 0.1)], Vector3(0, 1, 0.05).normalized())
	body.face([Vector3(-HALF + 0.18, 0.5, FRONT + 0.1), Vector3(HALF - 0.18, 0.5, FRONT + 0.1),
			Vector3(HALF - 0.18, BODY_BOTTOM, FRONT), Vector3(-HALF + 0.18, BODY_BOTTOM, FRONT)],
			Vector3(0, 0.3, -1).normalized())
	body.face([Vector3(-HALF + 0.18, 0.62, CABIN_BACK + 0.4), Vector3(HALF - 0.18, 0.62, CABIN_BACK + 0.4),
			Vector3(HALF - 0.18, 0.58, REAR - 0.1), Vector3(-HALF + 0.18, 0.58, REAR - 0.1)], Vector3.UP)
	body.face([Vector3(-HALF + 0.18, 0.58, REAR - 0.1), Vector3(HALF - 0.18, 0.58, REAR - 0.1),
			Vector3(HALF - 0.18, BODY_BOTTOM, REAR), Vector3(-HALF + 0.18, BODY_BOTTOM, REAR)], Vector3(0, 0.2, 1).normalized())
	# The sides' tops ahead of and behind the cabin, at the belt line, and the fins rising to the back.
	var fin := float(params["fins"])
	for s: float in [-1.0, 1.0]:
		var x0 := s * HALF
		var x1 := s * (HALF - 0.18)
		_wedge(body, x0, x1, CABIN_BACK, REAR, BELT, BELT + fin, s)
	# The bonnet's sides between the deck and the wings, under the belt line.
	for s: float in [-1.0, 1.0]:
		body.face([Vector3(s * (HALF - 0.18), BELT, DASH_Z), Vector3(s * (HALF - 0.18), BELT, FRONT),
				Vector3(s * (HALF - 0.18), 0.5, FRONT + 0.1), Vector3(s * (HALF - 0.18), 0.62, DASH_Z - 0.25)],
				Vector3(-s, 0, 0))
		body.face([Vector3(s * (HALF - 0.18), BELT, CABIN_BACK), Vector3(s * (HALF - 0.18), BELT, REAR),
				Vector3(s * (HALF - 0.18), 0.58, REAR - 0.1), Vector3(s * (HALF - 0.18), 0.62, CABIN_BACK + 0.4)],
				Vector3(-s, 0, 0))
	_build_cabin(body_m)
	_build_windscreen(chrome_m)
	_build_chrome(chrome_m, gy)
	_build_benches()
	_build_wheels(gy, chrome_m)
	_build_lamps()
	_add_static("Body", _s)
	_add_unbaked("Fittings", _u)
	_bake_spot("Sky", Vector3(0, 6.0, 0), true, 70.0, 10.0, 0.3, Color(0.6, 0.65, 0.85))


## A fin: a wedge along the side from z0 to z1, its top rising from y0 to y1.
func _wedge(b: RoomMesh, x0: float, x1: float, z0: float, z1: float, y0: float, y1: float, s: float) -> void:
	if y1 - y0 < 0.01:
		return
	var up := Vector3(0, z1 - z0, -(y1 - y0)).normalized()
	for x: float in [x0, x1]:
		b.face([Vector3(x, y0, z0), Vector3(x, y0, z1), Vector3(x, y1, z1)], Vector3(s if x == x0 else -s, 0, 0))
	b.face([Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y1, z1), Vector3(x0, y1, z1)], up)
	b.face([Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1)], Vector3.BACK)


## The cabin: the carpeted floor, the door panels, the firewall, the panel behind the rear bench, the dashboard with
## its padded top, the dials (softly lit), the steering wheel in front of the left place.
func _build_cabin(body_m: ShaderMaterial) -> void:
	var cab := _s
	cab.surface(_mm("carpet"))
	cab.face([Vector3(-INNER, 0, DASH_Z), Vector3(INNER, 0, DASH_Z), Vector3(INNER, 0, CABIN_BACK),
			Vector3(-INNER, 0, CABIN_BACK)], Vector3.UP)
	cab.surface(_mm("upholstery"))
	for s: float in [-1.0, 1.0]:
		cab.face([Vector3(s * INNER, 0, DASH_Z), Vector3(s * INNER, 0, CABIN_BACK), Vector3(s * INNER, BELT - 0.16, CABIN_BACK),
				Vector3(s * INNER, BELT - 0.16, DASH_Z)], Vector3(-s, 0, 0))
	cab.face([Vector3(-INNER, 0, CABIN_BACK), Vector3(INNER, 0, CABIN_BACK), Vector3(INNER, BELT, CABIN_BACK),
			Vector3(-INNER, BELT, CABIN_BACK)], Vector3.FORWARD)
	cab.surface(_mm("piping"))
	for s: float in [-1.0, 1.0]:
		cab.face([Vector3(s * INNER, BELT - 0.16, DASH_Z), Vector3(s * INNER, BELT - 0.16, CABIN_BACK),
				Vector3(s * INNER, BELT, CABIN_BACK), Vector3(s * INNER, BELT, DASH_Z)], Vector3(-s, 0, 0))
		# The door's pull, a chrome-less strap.
		cab.box(Vector3(s * (INNER - 0.02), 0.45, -0.1), Vector3(0.03, 0.04, 0.3))
	cab.surface(body_m)
	cab.face([Vector3(-INNER, 0, DASH_Z - 0.25), Vector3(INNER, 0, DASH_Z - 0.25), Vector3(INNER, 0.46, DASH_Z - 0.25),
			Vector3(-INNER, 0.46, DASH_Z - 0.25)], Vector3.BACK)
	# The dashboard: its face, its top running to the windscreen's foot.
	cab.box(Vector3(0, 0.62, DASH_Z - 0.12), Vector3(INNER * 2.0, 0.32, 0.26), Basis(), [RoomMesh.FRONT])
	var dash := _u
	dash.surface(_mm("upholstery"))
	dash.rounded_box(Vector3(0, 0.8, DASH_Z - 0.1), Vector3(INNER * 2.0, 0.07, 0.22), 0.03, Transform3D(), 1)
	# The dials: two round ones in front of the driver, a clock and the radio's band in the middle.
	var dials := RoomMesh.new()
	_dials = _lamp(color_param("dial_colour"), float(params["dial_glow"]), 0.0, "accent")
	dials.surface(_dials)
	var face_z := DASH_Z + 0.012
	for at: Vector3 in [Vector3(-PLACE - 0.09, 0.64, face_z), Vector3(-PLACE + 0.09, 0.64, face_z),
			Vector3(0.0, 0.66, face_z)]:
		Shapes.cylinder(dials, at, 0.055, 0.01, 12, Basis(Vector3.RIGHT, PI * 0.5))
	dials.box(Vector3(0.25, 0.62, face_z), Vector3(0.24, 0.035, 0.01))
	_add_lamps("Dials", dials)
	# The steering wheel: a ring on a column, tilted towards the driver, its top under the eyes.
	var wheel := RoomMesh.new()
	wheel.surface(_mm("piping"))
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(-28.0))
	var hub := Vector3(-PLACE, 0.84, -0.52)
	Shapes.arch(wheel, hub, 0.19, 0.215, 0.025, 24, tilt, 0.0, TAU)
	for k in 3:
		var a := TAU * (k / 3.0) + PI * 0.5
		Shapes.beam(wheel, hub, hub + tilt * Vector3(cos(a) * 0.19, sin(a) * 0.19, 0), Vector2(0.02, 0.012),
				tilt * Vector3.BACK)
	Shapes.beam(wheel, hub, hub + tilt * Vector3(0, 0, -0.5), Vector2(0.045, 0.045))
	_add_unbaked("Wheel", wheel)


## The wraparound windscreen: glass from the dashboard's top to under the eye line, flat across the middle and curving
## back at the corners, in a chrome frame (a top rail and the corner posts). No mirror.
func _build_windscreen(chrome_m: ShaderMaterial) -> void:
	var lo := PackedVector3Array()
	var hi := PackedVector3Array()
	var ns := PackedVector3Array()
	var n := 12
	for k in n + 1:
		var t := lerpf(-1.0, 1.0, float(k) / n)
		var x := t * (INNER + 0.06)
		var back := 0.28 * pow(maxf(absf(t) - 0.55, 0.0) / 0.45, 2.0)
		var z := DASH_Z - 0.2 + back
		lo.append(Vector3(x, 0.83, z))
		hi.append(Vector3(x * 0.97, WINDSCREEN_TOP, z + 0.12 + back * 0.2))
		var along := Vector3(1.0, 0, 2.0 * 0.28 * maxf(absf(t) - 0.55, 0.0) / (0.45 * 0.45) * signf(t) / (INNER + 0.06))
		ns.append(Vector3(-along.z, 0.0, along.x).normalized())
	var glass := RoomMesh.new()
	glass.surface(GLASS)
	glass.strip(lo, hi, ns)
	_add_glass("Windscreen", glass, Color(0.6, 0.72, 0.74), 0.05)
	var frame := _s
	frame.surface(chrome_m)
	for k in n:
		Shapes.beam(frame, hi[k], hi[k + 1], Vector2(0.03, 0.025))
		Shapes.beam(frame, lo[k], lo[k + 1], Vector2(0.03, 0.02))
	for k: int in [0, n]:
		Shapes.beam(frame, lo[k] + Vector3(0, -0.02, 0), hi[k] + Vector3(0, 0.015, 0), Vector2(0.035, 0.035))


## Chrome: the bumpers, a grille between the headlamps, a strip along each side, the boot's lip.
func _build_chrome(chrome_m: ShaderMaterial, _gy: float) -> void:
	var c := _u
	c.surface(chrome_m)
	c.rounded_box(Vector3(0, 0.0, FRONT - 0.06), Vector3(HALF * 2.0 + 0.04, 0.16, 0.16), 0.06, Transform3D(), 1)
	c.rounded_box(Vector3(0, 0.02, REAR + 0.06), Vector3(HALF * 2.0 + 0.04, 0.15, 0.15), 0.06, Transform3D(), 1)
	for s: float in [-1.0, 1.0]:
		c.rounded_box(Vector3(s * (HALF + 0.005), 0.42, (FRONT + REAR) * 0.5), Vector3(0.02, 0.025, REAR - FRONT - 0.4),
				0.01, Transform3D(), 1)
	# The grille: bars across the front under the bonnet's lip.
	for k in 5:
		c.rounded_box(Vector3(0, 0.12 + k * 0.06, FRONT - 0.01), Vector3(1.1, 0.02, 0.03), 0.008, Transform3D(), 1)


## The benches when the room has no seats system: a seat cushion and a back each, piped at the sides, as one mesh.
func _build_benches() -> void:
	if draws_seats_elsewhere():
		return
	var b := _u
	var zs: Array[float] = [0.0]
	if bool(params["rear_seat"]):
		zs.append(REAR_BENCH_Z)
	for z in zs:
		var bench := _bench(z)
		var tilt := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(float(bench[4]))), bench[2])
		b.surface(_mm("upholstery"))
		b.rounded_box(bench[0], bench[1], 0.06, Transform3D(), 1, Vector3i(2, 0, 0))
		b.rounded_box(Vector3.ZERO, bench[3], 0.06, tilt, 1, Vector3i(2, 1, 0))
		# Pleats: three raised rolls across the back.
		for k in 3:
			b.rounded_box(Vector3((k - 1) * 0.5, 0.02, -0.07), Vector3(0.44, 0.4, 0.04), 0.02, tilt, 1)
		b.surface(_mm("piping"))
		b.box(Vector3(0, 0.12, (bench[0] as Vector3).z), Vector3(INNER * 2.0 - 0.1, 0.24, 0.5), Basis(),
				[RoomMesh.DOWN])


## Four wheels with whitewalls and hub caps under the arches (only when the ground is under the body).
func _build_wheels(gy: float, chrome_m: ShaderMaterial) -> void:
	if gy > BODY_BOTTOM - 0.05:
		return
	var w := _u
	wheels_drawn = true
	var side := Basis(Vector3.FORWARD, PI * 0.5)
	for z: float in AXLES:
		for s: float in [-1.0, 1.0]:
			var at := Vector3(s * (HALF - 0.12), gy + WHEEL_R, z)
			w.surface(_mm("tyres"))
			Shapes.lathe(w, [Vector2(WHEEL_R - 0.1, -0.11), Vector2(WHEEL_R, -0.1), Vector2(WHEEL_R, 0.1),
					Vector2(WHEEL_R - 0.1, 0.11)], at, 16, side)
			w.surface(_mm("piping"))
			var out := s * 0.112
			Shapes.lathe(w, [Vector2(WHEEL_R - 0.03, 0.0), Vector2(WHEEL_R - 0.11, 0.0)], at + Vector3(out, 0, 0), 16,
					side if s > 0.0 else side * Basis(Vector3.RIGHT, PI))
			w.surface(chrome_m)
			Shapes.lathe(w, [Vector2(WHEEL_R - 0.11, 0.0), Vector2(0.12, 0.02), Vector2(0.0, 0.04)],
					at + Vector3(out, 0, 0), 12, side if s > 0.0 else side * Basis(Vector3.RIGHT, PI))


## The headlamps (two each side, round) and the tail lamps at the fins' feet: off while parked (headlamps 0), a
## glow when lit; the stand-in lamps and bake lights are left to the lot.
func _build_lamps() -> void:
	var on := float(params["headlamps"])
	var head := RoomMesh.new()
	var hm := _lamp(Color(1.0, 0.95, 0.82), 1.6 * on, 0.0, "accent")
	head.surface(hm)
	for s: float in [-1.0, 1.0]:
		for k in 2:
			var at := Vector3(s * (HALF - 0.16 - k * 0.2), 0.42, FRONT + 0.02)
			Shapes.cylinder(head, at, 0.075, 0.02, 12, Basis(Vector3.RIGHT, -PI * 0.5))
	var tm := _lamp(Color(0.9, 0.08, 0.05), 1.2 * on, 0.0, "accent")
	head.surface(tm)
	for s: float in [-1.0, 1.0]:
		Shapes.cylinder(head, Vector3(s * (HALF - 0.09), BELT + 0.04, REAR - 0.02), 0.06, 0.03, 10,
				Basis(Vector3.RIGHT, PI * 0.5))
	_lamps_m = [hm, tm]
	_lamp_energy = [1.6, 1.2]
	_add_lamps("Lamps", head)
	if str(params["top"]) == "folded":
		var cover := _u
		cover.surface(_mm("hood_cover"))
		cover.rounded_box(Vector3(0, BELT + 0.07, CABIN_BACK + 0.2), Vector3(INNER * 2.0 + 0.1, 0.16, 0.38), 0.07,
				Transform3D(), 1)


func _param_changed(param: String, value: Variant) -> void:
	match param:
		"headlamps":
			for i in _lamps_m.size():
				_lamps_m[i].set_shader_parameter("energy", _lamp_energy[i] * float(value) * _group_level("accent"))
		"dial_glow":
			if _dials != null:
				_dials.set_shader_parameter("energy", float(value) * _group_level("accent"))
