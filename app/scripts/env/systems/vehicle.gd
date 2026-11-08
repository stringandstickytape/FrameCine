extends "res://scripts/env/systems/kit/builder.gd"

## The vehicle builder (docs/environments.md, "The builders"): a generic 1950s convertible with its top down, parked
## facing the screen (a drive-in: on a terrace builder's lot, ground_y about -0.5). No badge, no name, no maker's shape.
## Since 2026-11-08 (the drive-in's quality pass: "the car is where you sit: the closest, most-looked-at thing. Make it
## superb", the brief) the body is lofted from cross-sections (kit/car_shape.gd): long wings ending in hooded headlamps,
## a crowned bonnet with a chrome spear and a jet on its nose, a side spear in a second colour, a skirted rear wheel,
## fins rising to rocket-like tail lamps. Its paint is lacquer and its chrome is chrome (kit/reflect.gd: the sky, the
## skyline, the screen's picture and the snack bar's neon in them, no probe). Inside: a front bench and a rear bench in
## tuck-and-roll vinyl of two colours, three places each (the viewer's in the middle, at the origin); a painted dash
## with a chrome band, a hooded speedometer and two small gauges in front of the left place, a radio with a glowing dial
## and push buttons in the middle, a clock that keeps the sky's time; a big thin steering wheel with a horn ring; door
## panels with arm rests, window cranks and handles; a carpeted floor with its hump; the wraparound windscreen with
## wing windows (its top under the eye line, so the screen up on its tower shows over it); the speaker of the lot's
## post hung on the left door, its cable to the post. Occlusion is in the vertex colours (the car is left out of the
## bake: its materials keep their fill and the dash's own stand-in lamp).
##   Car (paint, chrome, vinyl, carpet), Wheel (the steering wheel: vinyl, chrome), Dials (the lit faces),
##   Windscreen (glass), Lamps (head and tail lamps, one draw in their vertex colours)
## Slots for the kit: dash (its top), bonnet (the bonnet's top, at the front), rear_shelf (behind the rear bench), floor.

const CarShape := preload("res://scripts/env/systems/kit/car_shape.gd")
const Reflect := preload("res://scripts/env/systems/kit/reflect.gd")
const Strokes := preload("res://scripts/env/systems/kit/strokes.gd")
const DASH_SHADER := preload("res://shaders/env_dash.gdshader")

static func spec() -> Dictionary:
	return {
		"kind": "builder",
		"description": "A generic 1950s convertible with its top down, facing the screen (on a drive-in's lot): "
				+ "lacquered paint and chrome that show the sky and the picture, a front bench for three (the viewer "
				+ "in the middle) and a rear bench in tuck-and-roll vinyl, a lit dashboard (speedometer, radio, a "
				+ "clock keeping the sky's time), a big thin steering wheel, a wraparound windscreen under the eye "
				+ "line, tail fins, whitewall tyres, the lot's speaker hung on the door.",
		"params": PARAMS,
		"requires": ["light"],
		"provides": ["seats", "collision", "slots"],
		"cost": {"draws": 9, "triangles": 40000, "lights": 0, "particles": 0, "texture_mb": 8},
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
	"dash_light": {"type": "float", "min": 0.0, "max": 2.0, "default": 0.6,
			"description": "how much the dials' glow lights the cabin round them (a stand-in lamp under the dash)"},
	"body": {"type": "material", "default": {"library": "dark_metal", "color": [0.42, 0.66, 0.64]},
			"description": "the paint (lacquer: its colour; the maps are smooth)"},
	"trim": {"type": "color", "default": [0.93, 0.89, 0.79],
			"description": "the paint's second colour: the side spear"},
	"chrome": {"type": "material", "default": {"library": "brushed_steel", "color": [0.82, 0.83, 0.85]},
			"description": "the bumpers, the windscreen's frame, the trim (chrome: it shows its surroundings)"},
	"upholstery": {"type": "material", "default": {"library": "oxblood_leather", "color": [0.6, 0.14, 0.11]},
			"description": "the benches' rolls, the door panels' lower part (its library's grain; the colour)"},
	"piping": {"type": "material", "default": {"library": "brown_leather", "color": [0.86, 0.8, 0.7]},
			"description": "the vinyl's second colour (the bolsters, the door panels' tops, the steering wheel)"},
	"carpet": {"type": "material", "default": {"library": "woven_carpet", "color": [0.2, 0.08, 0.07]},
			"description": "the floor"},
	"tyres": {"type": "material", "default": {"library": "black_leather", "color": [0.04, 0.04, 0.04]},
			"description": "the tyres and the black rubber (their colour)"},
	"hood_cover": {"type": "material", "default": {"library": "linen", "color": [0.82, 0.78, 0.68]},
			"description": "the folded top's cover (its colour)"},
	"reflect_screen": {"type": "float", "min": 0.0, "max": 1.0, "default": 1.0, "live": true, "brightness": true,
			"description": "the screen's picture in the paint and the chrome (bind it to the playback: the screen "
			+ "dark before the film)"},
	"glint_at": {"type": "vec3", "min": -200.0, "max": 200.0, "default": [0.0, 3.5, 16.0],
			"description": "a bright sign round the car that its chrome shows (the snack bar's neon), the room's frame"},
	"glint_colour": {"type": "color", "default": [0.0, 0.0, 0.0],
			"description": "that sign's colour (black: none)"},
	"glint_energy": {"type": "float", "min": 0.0, "max": 4.0, "default": 1.0, "live": true, "brightness": true,
			"description": "that sign's brightness in the chrome"},
	"speaker": {"type": "bool", "default": true,
			"description": "the lot's speaker hung on the left door, its cable to the post beside the car"},
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
## The dash's top behind the windscreen, and the windscreen's foot.
const DASH_TOP := 0.79
const SCREEN_FOOT_Z := -1.1
## The steering wheel: its hub, its tilt towards the driver (degrees), its rim's radius.
const HUB := Vector3(-0.55, 0.84, -0.52)
const WHEEL_TILT := -28.0
const RIM := 0.215
## The dials' picture: its size (pixels); the clock's face in it.
const DIAL_W := 512
const DIAL_H := 256
const CLOCK_PX := Vector2(320.0, 64.0)
const CLOCK_R_PX := 60.0


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
		"dash": [{"transform": Transform3D(Basis(), Vector3(0.3, DASH_TOP + 0.01, DASH_Z - 0.12)), "size": [0.8, 0.3, 0.2]}],
		"bonnet": [{"transform": Transform3D(Basis(), Vector3(0, 0.62, FRONT + 0.35)), "size": [0.3, 0.2, 0.3]}],
		"rear_shelf": [{"transform": Transform3D(Basis(Vector3.UP, PI), Vector3(0, BELT, CABIN_BACK + 0.15)),
				"size": [INNER * 2.0, 0.3, 0.3]}],
		"floor": [{"transform": Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0.0, (DASH_Z + CABIN_BACK) * 0.5)),
				"size": [INNER * 2.0, CABIN_BACK - DASH_Z, 0.0]}],
	}


## A colour (sRGB, as a document gives it) as the linear value a vertex colour holds.
static func _lin(c: Color) -> Color:
	var l := c.srgb_to_linear()
	return Color(l.r, l.g, l.b, 1.0)


# --- Building -----------------------------------------------------------------------------------------------------

var _lamps_m: ShaderMaterial
var _dials: ShaderMaterial
var _paint: ShaderMaterial
var _chrome: ShaderMaterial
var _vinyl: ShaderMaterial
var _carpet: ShaderMaterial
## The parts being built, one a material: paint, chrome, vinyl, carpet.
var _pb: RoomMesh
var _cb: RoomMesh
var _vb: RoomMesh
var _kb: RoomMesh
var _d := {}
## Vertex colours (linear): the paint, its second colour, the vinyl's two, black rubber, the cabin's dark.
var _c_paint := Color.WHITE
var _c_trim := Color.WHITE
var _c_red := Color.WHITE
var _c_ivory := Color.WHITE
var _c_black := Color.BLACK
var _c_dark := Color.BLACK
var _screen_local := Transform3D(Basis(), Vector3(0.0, 8.5, -49.4))
var _screen_size := Vector2(24.0, 10.0)
var _dash_lamp := -1
var _sky: Node
var _glass: ShaderMaterial
## Whether the wheels are drawn (the ground under the body).
var wheels_drawn := false


func build() -> void:
	var gy := float(params["ground_y"])
	wheels_drawn = gy < BODY_BOTTOM - 0.05
	_d = CarShape.dims({"half": HALF, "inner": INNER, "front": FRONT, "rear": REAR, "belt": BELT,
			"bottom": BODY_BOTTOM, "dash_z": DASH_Z, "cabin_back": CABIN_BACK, "fins": float(params["fins"]),
			"axle_front": AXLES[0], "axle_rear": AXLES[1], "wheel_r": WHEEL_R, "arch": ARCH if wheels_drawn else 0.0,
			"ground_y": gy})
	_sky = host.system_of_kind("sky") if host != null else null
	_materials()
	_pb = RoomMesh.new()
	_pb.surface(_paint)
	_cb = RoomMesh.new()
	_cb.surface(_chrome)
	_vb = RoomMesh.new()
	_vb.surface(_vinyl)
	_kb = RoomMesh.new()
	_kb.surface(_carpet)
	CarShape.body(_pb, _d, _c_paint, _c_trim, _c_dark, _cb, true)
	if wheels_drawn:
		CarShape.wheels(_vb, _cb, _d, _c_black, _lin(Color(0.9, 0.88, 0.82)))
	_build_nose()
	_build_cabin()
	_build_dash()
	_build_windscreen()
	_build_benches()
	_build_tail()
	if bool(params["speaker"]):
		_build_speaker()
	var ao := Callable(self, "_occlusion")
	for b: RoomMesh in [_pb, _cb, _vb, _kb]:
		b.shade(ao)
	var mesh := ArrayMesh.new()
	for b: RoomMesh in [_pb, _cb, _vb, _kb]:
		if b.triangle_count() == 0:
			continue
		var part := b.commit(false)
		for s in part.get_surface_count():
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, part.surface_get_arrays(s))
			mesh.surface_set_material(mesh.get_surface_count() - 1, part.surface_get_material(s))
	var mi := _add_mesh("Car", mesh)
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_build_wheel()
	_build_lamps()
	# The dials' light on the cabin round them: a stand-in lamp under the dash's top (it stays after a bake: the car's
	# materials are left out of it).
	_dash_lamp = _light.add_lamp(Vector3(0.0, 0.62, DASH_Z + 0.2), _dash_light_colour(), 0.0)


func _materials() -> void:
	_c_paint = _lin(RoomSchemaRef.to_color(params["body"].get("color", "#6aa8a4")))
	_c_trim = _lin(color_param("trim"))
	_c_red = _lin(RoomSchemaRef.to_color(params["upholstery"].get("color", "#99241c")))
	_c_ivory = _lin(RoomSchemaRef.to_color(params["piping"].get("color", "#dbccb3")))
	_c_black = _lin(RoomSchemaRef.to_color(params["tyres"].get("color", "#0a0a0a")))
	_c_dark = _lin(Color(0.05, 0.045, 0.045))
	_paint = _mat("body", true)
	Reflect.make(_paint, 0.0, 1.0, 0.08)
	_paint.set_shader_parameter("tint", Color.WHITE)
	_paint.set_shader_parameter("instance_tint", true)
	_chrome = _mat("chrome", true)
	Reflect.make(_chrome, 1.0, 1.0, 0.05)
	_chrome.set_shader_parameter("tint", RoomSchemaRef.to_color(params["chrome"].get("color", "#d1d3d9")))
	_chrome.set_shader_parameter("instance_tint", true)
	# The vinyl: the upholstery's grain in white, its colours in the vertex colours (two tones, black rubber: one draw).
	var up: Dictionary = params["upholstery"]
	_vinyl = _light.library(str(up.get("library", "oxblood_leather")), Color(0.92, 0.92, 0.92), {"tiling": 0.35},
			true)
	_vinyl.set_shader_parameter("instance_tint", true)
	_carpet = _mat("carpet", true)
	_carpet.set_shader_parameter("instance_tint", true)


func _dash_light_colour() -> Color:
	var c := color_param("dial_colour")
	var k := float(params["dial_glow"]) * float(params["dash_light"]) * _group_level("accent") * 1.6
	return Color(c.r * k, c.g * k, c.b * k)


## Occlusion baked into the vertex colours: the cabin darker down towards its floor and under the dash, the body's
## sides darker towards the ground, anything facing down darker still.
func _occlusion(p: Vector3, n: Vector3) -> float:
	var k := 1.0
	var inside := absf(p.x) < INNER + 0.01 and p.z > SCREEN_FOOT_Z and p.z < CABIN_BACK + 0.02 and p.y < BELT
	if inside:
		k *= lerpf(0.55, 1.0, smoothstep(0.0, BELT, p.y))
		if p.z < DASH_Z + 0.3:
			k *= lerpf(0.5, 1.0, smoothstep(0.3, 0.6, p.y))
		k *= lerpf(0.75, 1.0, smoothstep(0.0, 0.12, INNER - absf(p.x)))
	else:
		k *= lerpf(0.5, 1.0, smoothstep(BODY_BOTTOM - 0.1, BELT * 0.85, p.y))
	if n.y < -0.3:
		k *= lerpf(1.0, 0.55, smoothstep(-0.3, -0.9, n.y))
	return k


## The nose: the jet on the bonnet's nose, the chrome spear back along its crown, a bullet on each wing's front, the
## headlamps' chrome hoods' rims.
func _build_nose() -> void:
	var c := _cb
	var nose_z := FRONT + 0.2
	var y0 := CarShape.crown(_d, nose_z)
	# The jet: a slim body pointing forward and a little up, swept wings, a fin; on a short plinth.
	var jet := Basis(Vector3.RIGHT, deg_to_rad(-80.0))
	var at := Vector3(0, y0 + 0.045, nose_z + 0.05)
	Shapes.lathe(c, [Vector2(0.0, -0.17), Vector2(0.012, -0.15), Vector2(0.02, -0.09), Vector2(0.022, 0.02),
			Vector2(0.016, 0.1), Vector2(0.006, 0.13)], at, 10, jet)
	for s: float in [-1.0, 1.0]:
		var root := at + Vector3(s * 0.015, -0.005, 0.02)
		var tip := at + Vector3(s * 0.11, -0.012, 0.1)
		c.face([root + Vector3(0, 0, -0.06), tip + Vector3(0, 0, -0.01), tip + Vector3(0, 0, 0.025),
				root + Vector3(0, 0, 0.07)], Vector3.UP)
		c.face([root + Vector3(0, 0, -0.06), root + Vector3(0, 0, 0.07), tip + Vector3(0, 0, 0.025),
				tip + Vector3(0, 0, -0.01)], Vector3.DOWN)
	c.face([at + Vector3(0, 0.015, 0.05), at + Vector3(0, 0.015, 0.12), at + Vector3(0, 0.075, 0.13)], Vector3.RIGHT)
	c.face([at + Vector3(0, 0.015, 0.05), at + Vector3(0, 0.075, 0.13), at + Vector3(0, 0.015, 0.12)], Vector3.LEFT)
	c.rounded_box(Vector3(0, y0 + 0.012, nose_z + 0.06), Vector3(0.04, 0.03, 0.12), 0.012, Transform3D(), 1)
	# The spear along the crown.
	var prev := Vector3(0, CarShape.crown(_d, nose_z + 0.14) + 0.004, nose_z + 0.14)
	var z := nose_z + 0.14
	while z < FRONT + 1.15:
		z += 0.1
		var next := Vector3(0, CarShape.crown(_d, z) + 0.004 - 0.004 * smoothstep(FRONT + 1.0, FRONT + 1.15, z), z)
		Shapes.beam(c, prev, next, Vector2(lerpf(0.03, 0.012, (z - nose_z) / 1.0), 0.012))
		prev = next
	# A bullet on each wing's front, the headlamp's rim under the hood.
	for s: float in [-1.0, 1.0]:
		var wz := FRONT + 0.34
		var wing := Vector3(s * (CarShape.half_width(_d, wz) - 0.11), CarShape.belt(_d, wz) + 0.012, wz)
		Shapes.lathe(c, [Vector2(0.0, -0.09), Vector2(0.014, -0.06), Vector2(0.018, 0.0), Vector2(0.014, 0.04),
				Vector2(0.0, 0.05)], wing, 8, Basis(Vector3.RIGHT, -PI * 0.5))
		var lamp := _headlamp_at(s)
		Shapes.lathe(c, [Vector2(0.1, -0.03), Vector2(0.092, -0.012), Vector2(0.075, 0.0)], lamp, 16,
				Basis(Vector3.RIGHT, -PI * 0.5))


## A headlamp's centre: in the wing's end, under its hood.
func _headlamp_at(s: float) -> Vector3:
	return Vector3(s * (CarShape.half_width(_d, FRONT) - 0.17), CarShape.belt(_d, FRONT + 0.1) - 0.13, FRONT - 0.005)


## The cabin: the carpeted floor with its hump and toe board, the firewall, the door panels in two tones with arm
## rests, cranks and handles, the panel behind the rear bench.
func _build_cabin() -> void:
	# The floor: the hump down the middle, the toe board rising to the firewall under the dash.
	var xs := PackedFloat32Array([-INNER, -0.45, -0.22, -0.13, -0.06, 0.0, 0.06, 0.13, 0.22, 0.45, INNER])
	var path := [Vector2(CABIN_BACK, 0.0), Vector2(0.6, 0.0), Vector2(-0.6, 0.0), Vector2(-0.78, 0.0),
			Vector2(-0.92, 0.12), Vector2(-1.02, 0.3)]
	var rows: Array = []
	var norms: Array = []
	for q: Vector2 in path:
		var row := PackedVector3Array()
		for x in xs:
			var hump := 0.11 * exp(-pow(x / 0.11, 2.0)) * smoothstep(1.2, 0.4, q.x)
			row.append(Vector3(x, q.y + hump, q.x))
		rows.append(row)
	norms = _grid_normals(rows, Vector3(0, 1.0, 0))
	_kb.grid(rows, norms)
	# The firewall behind the dash, dark.
	_vb.colour = _c_dark
	_vb.face([Vector3(-INNER, 0.3, -1.02), Vector3(INNER, 0.3, -1.02), Vector3(INNER, 0.45, -1.02),
			Vector3(-INNER, 0.45, -1.02)], Vector3.BACK)
	# Pedals in the driver's footwell.
	_vb.colour = _c_black
	_vb.rounded_box(Vector3(-0.42, 0.2, -0.86), Vector3(0.16, 0.06, 0.02), 0.008,
			Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-35.0)), Vector3.ZERO), 1)
	_vb.rounded_box(Vector3(-0.64, 0.15, -0.84), Vector3(0.06, 0.13, 0.015), 0.006,
			Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-40.0)), Vector3.ZERO), 1)
	_cb.surface(_chrome)
	Shapes.beam(_cb, Vector3(-0.42, 0.24, -0.89), Vector3(-0.42, 0.38, -1.0), Vector2(0.02, 0.012))
	# The door panels: ivory above a chrome strip, red below, a dark kick panel at the front.
	for s: float in [-1.0, 1.0]:
		var x := s * INNER
		var n := Vector3(-s, 0, 0)
		var top := BELT - 0.075
		_vb.colour = _c_ivory
		_vb.face([Vector3(x, 0.5, DASH_Z - 0.02), Vector3(x, 0.5, CABIN_BACK), Vector3(x, top, CABIN_BACK),
				Vector3(x, top, DASH_Z - 0.02)], n)
		_vb.colour = _c_red
		_vb.face([Vector3(x, 0.24, -0.55), Vector3(x, 0.24, CABIN_BACK), Vector3(x, 0.5, CABIN_BACK),
				Vector3(x, 0.5, -0.55)], n)
		_vb.face([Vector3(x, 0.24, DASH_Z - 0.02), Vector3(x, 0.24, -0.55), Vector3(x, 0.5, -0.55),
				Vector3(x, 0.5, DASH_Z - 0.02)], n)
		_vb.colour = _c_dark
		_vb.face([Vector3(x, 0.0, DASH_Z - 0.02), Vector3(x, 0.0, CABIN_BACK), Vector3(x, 0.24, CABIN_BACK),
				Vector3(x, 0.24, DASH_Z - 0.02)], n)
		# Rolls on the red: five raised bands along the door.
		_vb.colour = _c_red
		for k in 5:
			var y := 0.27 + k * 0.046
			_vb.rounded_box(Vector3(x - s * 0.006, y + 0.02, 0.22), Vector3(0.016, 0.036, 1.5), 0.008, Transform3D(),
					1, Vector3i.ZERO, 0.0, [Vector3(s, 0, 0)])
		# The door's back edge: a dark seam.
		_vb.colour = _c_dark
		_vb.box(Vector3(x - s * 0.004, 0.36, 0.62), Vector3(0.01, 0.72, 0.008))
		# Arm rests, ivory, front and rear.
		_vb.colour = _c_ivory
		_vb.rounded_box(Vector3(x - s * 0.045, 0.36, 0.08), Vector3(0.09, 0.06, 0.42), 0.025, Transform3D(), 2)
		_vb.rounded_box(Vector3(x - s * 0.04, 0.38, 1.2), Vector3(0.08, 0.06, 0.32), 0.025, Transform3D(), 2)
		# The chrome strip along the panel, the crank and the handle.
		Shapes.beam(_cb, Vector3(x - s * 0.006, 0.5, DASH_Z - 0.02), Vector3(x - s * 0.006, 0.5, CABIN_BACK),
				Vector2(0.006, 0.012), Vector3(s, 0, 0))
		var crank := Vector3(x - s * 0.012, 0.56, 0.34)
		Shapes.cylinder(_cb, crank, 0.022, 0.012, 10, Basis(Vector3.FORWARD, -s * PI * 0.5))
		Shapes.beam(_cb, crank + Vector3(-s * 0.014, 0, 0), crank + Vector3(-s * 0.014, -0.07, -0.03), Vector2(0.012, 0.006),
				Vector3(s, 0, 0))
		_vb.colour = _c_ivory
		Shapes.cylinder(_vb, crank + Vector3(-s * 0.016, -0.07, -0.03), 0.009, 0.035, 8,
				Basis(Vector3.FORWARD, -s * PI * 0.5))
		var handle := Vector3(x - s * 0.01, 0.53, -0.18)
		Shapes.beam(_cb, handle, handle + Vector3(-s * 0.02, 0.0, 0.11), Vector2(0.018, 0.008), Vector3(s, 0, 0))
		Shapes.beam(_cb, handle + Vector3(0, -0.008, -0.02), handle + Vector3(0, 0.008, 0.02), Vector2(0.02, 0.02))
		# The door's top: a chrome moulding along its inner lip.
		Shapes.beam(_cb, Vector3(s * (INNER + 0.012), BELT - 0.02, DASH_Z - 0.2),
				Vector3(s * (INNER + 0.012), BELT - 0.02, CABIN_BACK), Vector2(0.014, 0.012))
	# The panel behind the rear bench, up to the deck.
	_vb.colour = _c_red
	_vb.face([Vector3(-INNER, 0.0, CABIN_BACK), Vector3(INNER, 0.0, CABIN_BACK), Vector3(INNER, 0.68, CABIN_BACK),
			Vector3(-INNER, 0.68, CABIN_BACK)], Vector3.FORWARD)
	_vb.colour = Color.WHITE


## Normals for a grid, turned towards `up` (a floor) or away from a centre: the grid's own cross products.
static func _grid_normals(rows: Array, toward: Vector3, centre := Vector3.INF) -> Array:
	var out: Array = []
	var h := rows.size()
	for i in h:
		var row: PackedVector3Array = rows[i]
		var w := row.size()
		var nrow := PackedVector3Array()
		nrow.resize(w)
		for j in w:
			var along: Vector3 = (rows[mini(i + 1, h - 1)] as PackedVector3Array)[j] \
					- (rows[maxi(i - 1, 0)] as PackedVector3Array)[j]
			var across: Vector3 = row[mini(j + 1, w - 1)] - row[maxi(j - 1, 0)]
			var n := across.cross(along).normalized()
			var ref := toward if centre == Vector3.INF else (row[j] - centre)
			if n.dot(ref) < 0.0:
				n = -n
			nrow[j] = n
		out.append(nrow)
	return out


## The dashboard: its painted face bowed a little, a chrome band across, the padded top to the windscreen's foot, the
## speedometer under a hood in front of the left place with two small gauges, the radio in the middle (a lit dial, two
## knobs, five buttons, a grille on the top), the clock over the glove box on the right, the ignition key.
func _build_dash() -> void:
	var face_z := func(x: float) -> float: return DASH_Z - 0.025 * pow(x / INNER, 2.0)
	# The face: from its lower lip up to the band, tilted back a little.
	var rows: Array = []
	for y: float in [0.44, 0.5, 0.58, 0.66, 0.705]:
		var row := PackedVector3Array()
		for k in 17:
			var x := lerpf(-INNER, INNER, float(k) / 16.0)
			row.append(Vector3(x, y, face_z.call(x) - (y - 0.44) * 0.08))
		rows.append(row)
	_pb.colour = _c_paint
	_pb.grid(rows, _grid_normals(rows, Vector3.BACK))
	# Under the lip, back to the firewall.
	var under: Array = [rows[0]]
	var back := PackedVector3Array()
	for p: Vector3 in (rows[0] as PackedVector3Array):
		back.append(Vector3(p.x, 0.43, -1.02))
	under.append(back)
	_vb.colour = _c_dark
	_vb.grid(under, _grid_normals(under, Vector3.DOWN))
	# The chrome band, with fine ribs.
	var band: Array = []
	for y: float in [0.705, 0.712, 0.718, 0.724, 0.73, 0.736, 0.742]:
		var row := PackedVector3Array()
		for k in 17:
			var x := lerpf(-INNER, INNER, float(k) / 16.0)
			var rib := 0.0015 if int(round((y - 0.705) / 0.006)) % 2 == 1 else 0.0
			row.append(Vector3(x, y, face_z.call(x) - (y - 0.44) * 0.08 + 0.002 - rib))
		band.append(row)
	_cb.grid(band, _grid_normals(band, Vector3.BACK))
	# The pad: from the band's top rolling over to the windscreen's foot.
	var pad: Array = []
	var prof := [Vector2(0.0, 0.742), Vector2(0.012, 0.765), Vector2(0.035, 0.782), Vector2(0.07, DASH_TOP),
			Vector2(0.2, DASH_TOP + 0.002)]
	for q: Vector2 in prof:
		var row := PackedVector3Array()
		for k in 17:
			var x := lerpf(-INNER - 0.04, INNER + 0.04, float(k) / 16.0)
			var xc := clampf(x, -INNER, INNER)
			row.append(Vector3(x, q.y, face_z.call(xc) - (0.742 - 0.44) * 0.08 - q.x))
		pad.append(row)
	_vb.colour = _c_red * 0.45
	_vb.grid(pad, _grid_normals(pad, Vector3(0, 1, 0.4)))
	# The speaker's grille on the pad, in the middle; the defroster's slots by the glass.
	for k in 7:
		var z := DASH_Z - 0.12 - k * 0.013
		_cb.rounded_box(Vector3(0, DASH_TOP + 0.004, z), Vector3(0.3, 0.006, 0.006), 0.002, Transform3D(), 1)
	_vb.colour = _c_black
	for s: float in [-1.0, 1.0]:
		_vb.box(Vector3(s * 0.4, DASH_TOP + 0.003, -1.06), Vector3(0.36, 0.003, 0.012))
	# The speedometer's hood (paint) and the instruments' bezels (chrome).
	var sp := Vector3(-PLACE, 0.6, face_z.call(-PLACE) - 0.016 * 0.0 - (0.6 - 0.44) * 0.08)
	_pb.colour = _c_paint
	Shapes.arch(_pb, sp + Vector3(0, 0.0, -0.035), 0.125, 0.14, 0.11, 14, Basis(), 0.0, PI)
	Shapes.lathe(_cb, [Vector2(0.094, 0.0), Vector2(0.1, 0.006), Vector2(0.108, 0.014), Vector2(0.104, 0.02)],
			sp + Vector3(0, 0, 0.0), 24, Basis(Vector3.RIGHT, PI * 0.5))
	for s: float in [-1.0, 1.0]:
		var g := sp + Vector3(s * 0.175, -0.025, 0.002)
		Shapes.lathe(_cb, [Vector2(0.04, 0.0), Vector2(0.046, 0.006), Vector2(0.05, 0.014)], g, 16,
				Basis(Vector3.RIGHT, PI * 0.5))
	# The radio: a chrome bezel round the dial, knobs either side, five buttons under it.
	var radio := Vector3(0, 0.615, face_z.call(0.0) - (0.615 - 0.44) * 0.08)
	_cb.rounded_box(radio + Vector3(0, 0, 0.008), Vector3(0.34, 0.082, 0.02), 0.008, Transform3D(), 1,
			Vector3i(4, 0, 0))
	for s: float in [-1.0, 1.0]:
		Shapes.lathe(_cb, [Vector2(0.026, 0.0), Vector2(0.026, 0.012), Vector2(0.02, 0.03), Vector2(0.0, 0.032)],
				radio + Vector3(s * 0.215, 0.0, 0.0), 12, Basis(Vector3.RIGHT, PI * 0.5))
	for k in 5:
		_cb.rounded_box(radio + Vector3((k - 2) * 0.052, -0.068, 0.012), Vector3(0.036, 0.022, 0.024), 0.005,
				Transform3D(), 1)
	# The clock over the glove box, its latch.
	var clock := Vector3(0.42, 0.625, face_z.call(0.42) - (0.625 - 0.44) * 0.08)
	Shapes.lathe(_cb, [Vector2(0.064, 0.0), Vector2(0.07, 0.006), Vector2(0.077, 0.014)], clock, 20,
			Basis(Vector3.RIGHT, PI * 0.5))
	_cb.rounded_box(Vector3(0.42, 0.5, face_z.call(0.42) - 0.005 + 0.012), Vector3(0.05, 0.018, 0.016), 0.006,
			Transform3D(), 1)
	# The glove box's door: a fine shadow line round it.
	_vb.colour = _c_dark
	for e: Array in [[Vector3(0.27, 0.465, 0), Vector3(0.57, 0.465, 0)], [Vector3(0.27, 0.535, 0), Vector3(0.57, 0.535, 0)]]:
		var a: Vector3 = e[0]
		var b2: Vector3 = e[1]
		a.z = face_z.call(a.x) - (a.y - 0.44) * 0.08 + 0.0015
		b2.z = face_z.call(b2.x) - (b2.y - 0.44) * 0.08 + 0.0015
		Shapes.beam(_vb, a, b2, Vector2(0.004, 0.003), Vector3.BACK)
	# The ignition: a chrome boss, the key and its fob.
	var ign := Vector3(-0.24, 0.5, face_z.call(-0.24) - 0.005)
	Shapes.cylinder(_cb, ign, 0.018, 0.012, 12, Basis(Vector3.RIGHT, PI * 0.5))
	Shapes.beam(_cb, ign + Vector3(0, 0, 0.012), ign + Vector3(0, -0.005, 0.045), Vector2(0.016, 0.003))
	Shapes.beam(_cb, ign + Vector3(0, -0.005, 0.045), ign + Vector3(0, -0.06, 0.05), Vector2(0.004, 0.004))
	_vb.colour = _c_red
	_vb.rounded_box(ign + Vector3(0, -0.075, 0.05), Vector3(0.022, 0.032, 0.006), 0.003, Transform3D(), 1)
	_vb.colour = Color.WHITE
	_build_dials(sp, radio, clock, face_z)


## The lit faces (the Dials mesh, one draw): the speedometer, the two small gauges, the radio's dial, the clock (its
## hands the shader's), each a quad in the dials' picture.
func _build_dials(sp: Vector3, radio: Vector3, clock: Vector3, _face_z: Callable) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := Vector3(0, 0.08, 1).normalized()
	var up := Vector3(0, 1, -0.08).normalized()
	_dial_quad(st, sp + Vector3(0, 0, 0.003), 0.097, 0.097, n, up, Rect2(0, 0, 256, 256))
	_dial_quad(st, sp + Vector3(-0.175, -0.025, 0.004), 0.042, 0.042, n, up, Rect2(384, 0, 64, 64))
	_dial_quad(st, sp + Vector3(0.175, -0.025, 0.004), 0.042, 0.042, n, up, Rect2(448, 0, 64, 64))
	_dial_quad(st, radio + Vector3(0, 0.006, 0.02), 0.135, 0.022, n, up, Rect2(256, 160, 256, 64))
	_dial_quad(st, clock + Vector3(0, 0, 0.003), 0.066, 0.066, n, up, Rect2(CLOCK_PX - Vector2.ONE * 64.0,
			Vector2.ONE * 128.0))
	var mesh := st.commit()
	var m := _lamp(Color.WHITE, float(params["dial_glow"]), 0.0, "accent")
	m.shader = DASH_SHADER
	m.set_shader_parameter("picture", _dial_picture(color_param("dial_colour")))
	m.set_shader_parameter("use_picture", true)
	m.set_shader_parameter("clock_centre", Vector2(CLOCK_PX.x / DIAL_W, CLOCK_PX.y / DIAL_H))
	m.set_shader_parameter("clock_radius", CLOCK_R_PX / DIAL_H)
	m.set_shader_parameter("hand_colour", color_param("dial_colour").lerp(Color.WHITE, 0.5))
	m.set_shader_parameter("hour", _sky_hour())
	mesh.surface_set_material(0, m)
	_dials = m
	var mi := _add_mesh("Dials", mesh)
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED


func _dial_quad(st: SurfaceTool, c: Vector3, hu: float, hv: float, n: Vector3, up: Vector3, px: Rect2) -> void:
	var u := Vector3.RIGHT * hu
	var v := up * hv
	var corners := [c - u - v, c + u - v, c + u + v, c - u + v]
	var uv0 := px.position / Vector2(DIAL_W, DIAL_H)
	var uv1 := px.end / Vector2(DIAL_W, DIAL_H)
	var uvs := [Vector2(uv0.x, uv1.y), Vector2(uv1.x, uv1.y), Vector2(uv1.x, uv0.y), Vector2(uv0.x, uv0.y)]
	# Clockwise as the viewer sees it (the side Godot draws).
	for k: int in [0, 2, 1, 0, 3, 2]:
		st.set_normal(n)
		st.set_uv(uvs[k])
		st.add_vertex(corners[k])


## The sky's hour (the clock's time), or a quarter to nine without a sky.
func _sky_hour() -> float:
	if _sky != null and is_instance_valid(_sky) and _sky.has_method("hour_shown"):
		return float(_sky.call("hour_shown"))
	return 20.75


static var _pictures := {}


## The dials' faces drawn once (DIAL_W x DIAL_H): the speedometer (0 to 120, its needle at rest), the fuel and the
## temperature gauges (needles at three quarters and the middle), the radio's band with its pointer, the clock's
## face (its hands are the shader's). Luminous markings in the dials' colour on a faint ground; the radio amber.
static func _dial_picture(glow: Color) -> ImageTexture:
	var key := str(glow)
	if _pictures.has(key):
		return _pictures[key]
	var img := Image.create_empty(DIAL_W, DIAL_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 1))
	var ground := glow * 0.07
	ground.a = 1.0
	var mark := glow
	mark.a = 1.0
	var needle := Color(1.0, 0.45, 0.2, 1.0)
	# The speedometer.
	var c := Vector2(128, 128)
	_disc(img, c, 122.0, ground)
	_ring(img, c, 118.0, 2.0, mark * 0.7)
	for k in 25:
		var a := deg_to_rad(-135.0 + 270.0 * k / 24.0)
		var dir := Vector2(sin(a), -cos(a))
		var major := k % 4 == 0
		Strokes.line(img, c + dir * (92.0 if major else 101.0), c + dir * 112.0, mark, 4.0 if major else 2.0)
		if major:
			Strokes.draw(img, str(k * 5), c + dir * 72.0 + Vector2(0, 8), 16.0, mark, 2.4, true)
	Strokes.line(img, c, c + Vector2(sin(deg_to_rad(-133.0)), -cos(deg_to_rad(-133.0))) * 104.0, needle, 4.0)
	_disc(img, c, 11.0, Color(0.05, 0.05, 0.05, 1.0))
	Strokes.draw(img, "MPH", c + Vector2(0, 46), 12.0, mark * 0.8, 1.8, true)
	# The fuel and temperature gauges.
	for g: Array in [[Vector2(416, 32), "E", "F", 0.72], [Vector2(480, 32), "C", "H", 0.45]]:
		var gc: Vector2 = g[0]
		_disc(img, gc, 30.0, ground)
		for k in 5:
			var a := deg_to_rad(-60.0 + 120.0 * k / 4.0)
			var dir := Vector2(sin(a), -cos(a))
			Strokes.line(img, gc + dir * 20.0, gc + dir * 27.0, mark, 2.0)
		Strokes.draw(img, str(g[1]), gc + Vector2(-17, 18), 9.0, mark, 1.6, true)
		Strokes.draw(img, str(g[2]), gc + Vector2(17, 18), 9.0, mark, 1.6, true)
		var na := deg_to_rad(-60.0 + 120.0 * float(g[3]))
		Strokes.line(img, gc + Vector2(0, 8), gc + Vector2(sin(na), -cos(na)) * 25.0, needle, 2.5)
	# The radio's band.
	var amber := Color(1.0, 0.62, 0.28, 1.0)
	var band := Rect2(256, 160, 256, 64)
	for y in range(int(band.position.y), int(band.end.y)):
		for x in range(int(band.position.x), int(band.end.x)):
			var fy := (y - band.position.y) / band.size.y
			var fx := (x - band.position.x) / band.size.x
			var glow_k := 0.16 * sin(fy * PI) * (0.6 + 0.4 * sin(fx * PI))
			img.set_pixel(x, y, Color(amber.r * glow_k, amber.g * glow_k, amber.b * glow_k, 1.0))
	var labels := ["55", "60", "70", "80", "100", "120", "140", "160"]
	for k in labels.size():
		var x := band.position.x + 18.0 + k * (band.size.x - 36.0) / (labels.size() - 1)
		Strokes.line(img, Vector2(x, band.position.y + 8), Vector2(x, band.position.y + 20), amber, 2.0)
		Strokes.draw(img, labels[k], Vector2(x, band.position.y + 44), 15.0, amber, 2.0, true)
	for k in 29:
		var x := band.position.x + 18.0 + k * (band.size.x - 36.0) / 28.0
		Strokes.line(img, Vector2(x, band.position.y + 8), Vector2(x, band.position.y + 13), amber * 0.7, 1.2)
	Strokes.line(img, Vector2(band.position.x + 92, band.position.y + 4), Vector2(band.position.x + 92,
			band.end.y - 6), Color(1.0, 0.25, 0.15, 1.0), 3.0)
	# The clock's face: twelve marks, the quarters longer.
	_disc(img, CLOCK_PX, CLOCK_R_PX, ground)
	for k in 12:
		var a := TAU * k / 12.0
		var dir := Vector2(sin(a), -cos(a))
		Strokes.line(img, CLOCK_PX + dir * (CLOCK_R_PX * (0.7 if k % 3 == 0 else 0.8)), CLOCK_PX + dir * CLOCK_R_PX * 0.92,
				mark, 4.0 if k % 3 == 0 else 2.5)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_pictures[key] = t
	return t


static func _disc(img: Image, c: Vector2, r: float, col: Color) -> void:
	for y in range(maxi(int(c.y - r - 1), 0), mini(int(c.y + r + 2), img.get_height())):
		for x in range(maxi(int(c.x - r - 1), 0), mini(int(c.x + r + 2), img.get_width())):
			var k := clampf(r + 0.5 - Vector2(x + 0.5, y + 0.5).distance_to(c), 0.0, 1.0)
			if k > 0.0:
				img.set_pixel(x, y, img.get_pixel(x, y).lerp(col, k))


static func _ring(img: Image, c: Vector2, r: float, w: float, col: Color) -> void:
	for y in range(maxi(int(c.y - r - w - 1), 0), mini(int(c.y + r + w + 2), img.get_height())):
		for x in range(maxi(int(c.x - r - w - 1), 0), mini(int(c.x + r + w + 2), img.get_width())):
			var d := absf(Vector2(x + 0.5, y + 0.5).distance_to(c) - r)
			var k := clampf(w * 0.5 + 0.5 - d, 0.0, 1.0)
			if k > 0.0:
				img.set_pixel(x, y, img.get_pixel(x, y).lerp(Color(col.r, col.g, col.b, 1.0), k))


## The wraparound windscreen: glass from the dash's top to under the eye line, flat across the middle and curving back
## at the corners, in a chrome frame; a wing window behind each corner post, framed, its glass turned out a little.
func _build_windscreen() -> void:
	var lo := PackedVector3Array()
	var hi := PackedVector3Array()
	var ns := PackedVector3Array()
	var n := 14
	for k in n + 1:
		var t := lerpf(-1.0, 1.0, float(k) / n)
		var x := t * (INNER + 0.06)
		var back := 0.3 * pow(maxf(absf(t) - 0.55, 0.0) / 0.45, 2.0)
		var z := SCREEN_FOOT_Z + 0.02 + back
		lo.append(Vector3(x, DASH_TOP + 0.005 - 0.07 * pow(maxf(absf(t) - 0.75, 0.0) / 0.25, 1.5), z))
		hi.append(Vector3(x * 0.97, WINDSCREEN_TOP, z + 0.13 + back * 0.2))
		var along := Vector3(1.0, 0, 2.0 * 0.3 * maxf(absf(t) - 0.55, 0.0) / (0.45 * 0.45) * signf(t) / (INNER + 0.06))
		ns.append(Vector3(-along.z, 0.0, along.x).normalized())
	var glass := RoomMesh.new()
	glass.surface(GLASS)
	glass.strip(lo, hi, ns)
	# The frame: a top rail, a foot rail, the corner posts down to the doors' tops.
	for k in n:
		Shapes.beam(_cb, hi[k] + Vector3(0, 0.008, 0), hi[k + 1] + Vector3(0, 0.008, 0), Vector2(0.034, 0.022))
		Shapes.beam(_cb, lo[k] + Vector3(0, -0.004, 0), lo[k + 1] + Vector3(0, -0.004, 0), Vector2(0.026, 0.016))
	for k: int in [0, n]:
		var s := -1.0 if k == 0 else 1.0
		var foot := Vector3(s * (INNER + 0.07), BELT - 0.01, lo[k].z + 0.04)
		Shapes.beam(_cb, foot, hi[k] + Vector3(0, 0.02, 0), Vector2(0.034, 0.03))
		# The wing window: a post at its back, a frame round its top, the glass.
		var top_front := hi[k] + Vector3(s * 0.005, -0.03, 0.03)
		var post_foot := Vector3(s * (INNER + 0.08), BELT - 0.01, foot.z + 0.3)
		var post_top := Vector3(s * (INNER + 0.07), 0.98, foot.z + 0.27)
		Shapes.beam(_cb, post_foot, post_top, Vector2(0.018, 0.018))
		Shapes.beam(_cb, top_front, post_top, Vector2(0.016, 0.016))
		glass.face([foot + Vector3(0, 0.01, 0.02), post_foot + Vector3(0, 0.01, -0.01), post_top + Vector3(0, -0.01, -0.01),
				top_front + Vector3(0, -0.015, 0.0)], Vector3(s, 0, 0))
	_glass = _add_glass("Windscreen", glass, Color(0.6, 0.72, 0.74), 0.05).material_override as ShaderMaterial
	_glass.set_shader_parameter("sky_mix", 0.3)


## The benches when the room has no seats system: tuck-and-roll vinyl, rolls in the first colour between bolsters and
## a front band in the second, the back's top rolled over in the second colour.
func _build_benches() -> void:
	if draws_seats_elsewhere():
		return
	var zs: Array[float] = [0.0]
	if bool(params["rear_seat"]):
		zs.append(REAR_BENCH_Z)
	for z in zs:
		_bench_surface(z, true)
		_bench_surface(z, false)
		# The bench's base, dark, and its ends.
		_vb.colour = _c_dark
		_vb.box(Vector3(0, 0.11, z - 0.02), Vector3(INNER * 2.0 - 0.1, 0.22, 0.5), Basis(), [RoomMesh.DOWN])
	_vb.colour = Color.WHITE


## One part of a bench (the cushion or the back) as a grid: across, rolls of 7.5 cm between ivory bolsters; along, the
## part's profile (cushion: from the back over the top and down the front; back: up the front, over the top, down the
## rear), the rolls raised along it where it is upholstered in them.
func _bench_surface(z: float, cushion: bool) -> void:
	var w := INNER - 0.03
	var prof: Array
	var rolled: Array
	var centre: Vector2
	if cushion:
		prof = [Vector2(z + 0.27, 0.425), Vector2(z + 0.1, 0.438), Vector2(z - 0.1, 0.44), Vector2(z - 0.22, 0.428),
				Vector2(z - 0.275, 0.405), Vector2(z - 0.298, 0.36), Vector2(z - 0.3, 0.3), Vector2(z - 0.29, 0.21)]
		rolled = [true, true, true, true, false, false, false, false]
		centre = Vector2(z, 0.25)
	else:
		prof = [Vector2(z + 0.25, 0.43), Vector2(z + 0.27, 0.52), Vector2(z + 0.3, 0.66), Vector2(z + 0.33, 0.8),
				Vector2(z + 0.355, 0.9), Vector2(z + 0.38, 0.955), Vector2(z + 0.42, 0.975), Vector2(z + 0.47, 0.96),
				Vector2(z + 0.49, 0.9), Vector2(z + 0.48, 0.45)]
		rolled = [false, true, true, true, true, false, false, false, false, false]
		centre = Vector2(z + 0.38, 0.68)
	var pitch := 0.075
	var rolls_w := floorf((w * 2.0 - 0.16) / pitch) * pitch
	var xs := PackedFloat32Array()
	xs.append(-w)
	xs.append(-w + 0.02)
	xs.append(-rolls_w * 0.5 - 0.03)
	var steps := int(round(rolls_w / pitch)) * 4
	for k in steps + 1:
		xs.append(-rolls_w * 0.5 + rolls_w * float(k) / steps)
	xs.append(rolls_w * 0.5 + 0.03)
	xs.append(w - 0.02)
	xs.append(w)
	var rows: Array = []
	var norms: Array = []
	var cols: Array = []
	for i in prof.size():
		var q: Vector2 = prof[i]
		# The profile's normal in (z, y), away from the part's middle.
		var a: Vector2 = prof[maxi(i - 1, 0)]
		var b2: Vector2 = prof[mini(i + 1, prof.size() - 1)]
		var t := (b2 - a).normalized()
		var pn := Vector2(-t.y, t.x)
		if pn.dot(q - centre) < 0.0:
			pn = -pn
		var row := PackedVector3Array()
		var nrow := PackedVector3Array()
		var crow := PackedColorArray()
		for j in xs.size():
			var x := xs[j]
			var in_rolls := absf(x) <= rolls_w * 0.5 + 0.0001
			var lift := 0.0
			var slope := 0.0
			var seam := 1.0
			if bool(rolled[i]) and in_rolls:
				var u := fposmod((x + rolls_w * 0.5) / pitch + 0.0001, 1.0) * 2.0 - 1.0
				lift = 0.016 * sqrt(maxf(1.0 - u * u, 0.0))
				slope = -0.016 * u / maxf(sqrt(maxf(1.0 - u * u, 0.0)), 0.25) * 2.0 / pitch
				# The stitched seam between two rolls, darker.
				seam = lerpf(0.55, 1.0, smoothstep(0.92, 0.6, absf(u)))
			# The ends round down into the sides.
			var edge := smoothstep(w, w - 0.03, absf(x))
			var drop := (1.0 - edge) * 0.03
			var p3 := Vector3(x, q.y + pn.y * (lift - drop), q.x + pn.x * (lift - drop))
			var n3 := (Vector3(0, pn.y, pn.x) - Vector3(1, 0, 0) * clampf(slope * 0.6, -1.5, 1.5)).normalized()
			if absf(x) > w - 0.03:
				n3 = (n3 + Vector3(signf(x), 0, 0) * (1.0 - edge) * 2.0).normalized()
			row.append(p3)
			nrow.append(n3)
			crow.append((_c_red if bool(rolled[i]) and in_rolls else _c_ivory) * seam)
		rows.append(row)
		norms.append(nrow)
		cols.append(crow)
	_vb.grid(rows, norms, cols)
	# The ends: the profile closed down to the base, ivory.
	_vb.colour = _c_ivory
	for s: float in [-1.0, 1.0]:
		var poly: Array = []
		for q: Vector2 in prof:
			poly.append(Vector3(s * w, q.y - 0.03, q.x))
		if cushion:
			poly.append(Vector3(s * w, 0.21, z + 0.27))
		_vb.face(poly, Vector3(s, 0, 0))
	_vb.colour = Color.WHITE


## The tail: the folded top under its cover behind the rear bench, the deck lid's chrome handle, chrome along the
## fins' tops, the tail lamps' rocket nacelles.
func _build_tail() -> void:
	if str(params["top"]) == "folded":
		var cover := _lin(RoomSchemaRef.to_color(params["hood_cover"].get("color", "#d1c7ad")))
		_vb.colour = cover
		_vb.rounded_box(Vector3(0, BELT + 0.02, CABIN_BACK + 0.2), Vector3(INNER * 2.0 + 0.04, 0.17, 0.42), 0.08,
				Transform3D(), 2, Vector3i(4, 0, 1))
		# Its snaps along the edge.
		for k in 9:
			var x := lerpf(-INNER, INNER, float(k) / 8.0)
			_cb.rounded_box(Vector3(x, BELT + 0.07, CABIN_BACK - 0.005), Vector3(0.016, 0.016, 0.008), 0.005,
					Transform3D(), 1)
		_vb.colour = Color.WHITE
	var deck_z := REAR - 0.3
	Shapes.beam(_cb, Vector3(-0.12, CarShape.crown(_d, deck_z) + 0.01, deck_z),
			Vector3(0.12, CarShape.crown(_d, deck_z) + 0.01, deck_z), Vector2(0.03, 0.018))
	for s: float in [-1.0, 1.0]:
		var prev := Vector3.ZERO
		var z := CABIN_BACK + 0.3
		while z <= REAR - 0.1:
			var w := CarShape.half_width(_d, z)
			var p := Vector3(s * (w - 0.06), CarShape.belt(_d, z) + 0.006, z)
			if prev != Vector3.ZERO:
				Shapes.beam(_cb, prev, p, Vector2(0.012, 0.01))
			prev = p
			z += 0.1
		# The nacelle at the fin's end: a chrome shell pointing back; its red lens is in Lamps.
		var tail := _tail_lamp_at(s)
		Shapes.lathe(_cb, [Vector2(0.0, -0.32), Vector2(0.02, -0.28), Vector2(0.05, -0.16), Vector2(0.058, -0.02),
				Vector2(0.056, 0.0)], tail, 14, Basis(Vector3.RIGHT, PI * 0.5))


func _tail_lamp_at(s: float) -> Vector3:
	var z := REAR - 0.05
	return Vector3(s * (CarShape.half_width(_d, z) - 0.085), CarShape.belt(_d, z) - 0.07, REAR + 0.02)


## The lot's speaker hung on the left door: an aluminium case, a grille facing in, a volume knob, the hook over the
## door's top, the cable over the side and down to the post beside the car (terrace.gd's lot: its posts beside the
## front seats at x 1.75).
func _build_speaker() -> void:
	var at := Vector3(-(INNER - 0.045), 0.6, -0.2)
	var alu := Color(0.45, 0.46, 0.45)
	_cb.colour = alu
	_cb.rounded_box(at, Vector3(0.07, 0.15, 0.21), 0.025, Transform3D(), 2)
	_cb.colour = Color.WHITE
	_vb.colour = _c_dark
	_vb.rounded_box(at + Vector3(0.036, -0.012, 0.0), Vector3(0.006, 0.1, 0.16), 0.004, Transform3D(), 1)
	_vb.colour = Color.WHITE
	for k in 6:
		_cb.box(at + Vector3(0.041, -0.052 + k * 0.016, 0.0), Vector3(0.004, 0.005, 0.15))
	Shapes.cylinder(_cb, at + Vector3(0.035, 0.05, 0.065), 0.012, 0.012, 10, Basis(Vector3.FORWARD, -PI * 0.5))
	# The hook: a flat bar over the door's top.
	var hook := [at + Vector3(-0.02, 0.07, -0.02), Vector3(-(INNER + 0.0), BELT + 0.012, -0.22),
			Vector3(-(HALF - 0.02), BELT + 0.012, -0.22), Vector3(-(HALF + 0.005), BELT - 0.05, -0.22)]
	for k in hook.size() - 1:
		Shapes.beam(_cb, hook[k], hook[k + 1], Vector2(0.03, 0.006), Vector3(0, 1, 0))
	# The cable: from the hook outside the door, sagging, to the post's head.
	var from: Vector3 = hook[3] + Vector3(0, -0.02, 0)
	var gy := float(params["ground_y"])
	var to := Vector3(-1.75 + 0.06, gy + 1.12, -0.3)
	var prev := from
	_vb.colour = _c_black
	for k in range(1, 13):
		var t := float(k) / 12.0
		var p := from.lerp(to, t) + Vector3(0, -0.32 * sin(t * PI), 0)
		Shapes.beam(_vb, prev, p, Vector2(0.012, 0.012))
		prev = p
	_vb.colour = Color.WHITE


## The steering wheel in front of the left place: a big thin rim in the second colour, three chrome spokes, a chrome
## horn ring over the top half, the hub's dome; its column with the gear selector.
func _build_wheel() -> void:
	var b := RoomMesh.new()
	b.surface(_vinyl)
	var c := RoomMesh.new()
	c.surface(_chrome)
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(WHEEL_TILT))
	# The rim's plane faces the driver: local y along the column.
	var face := tilt * Basis(Vector3.RIGHT, PI * 0.5)
	var ring: Array = []
	for k in 9:
		var a := TAU * k / 8.0
		ring.append(Vector2(RIM + cos(a) * 0.013, sin(a) * 0.013))
	b.colour = _lin(RoomSchemaRef.to_color(params["piping"].get("color", "#dbccb3")))
	Shapes.lathe(b, ring, HUB, 40, face)
	for k in 3:
		var a := TAU * (k / 3.0) + PI * 0.5
		var dir := Vector3(cos(a), sin(a), 0.0)
		Shapes.beam(c, HUB + tilt * (dir * 0.04), HUB + tilt * (dir * (RIM - 0.01)), Vector2(0.016, 0.006),
				tilt * Vector3.BACK)
	var horn: Array = []
	for k in 7:
		var a := TAU * k / 6.0
		horn.append(Vector2(0.15 + cos(a) * 0.006, sin(a) * 0.006 + 0.012))
	Shapes.lathe(c, horn, HUB, 20, face, PI * 0.8, PI * 0.6)
	Shapes.lathe(c, [Vector2(0.045, 0.0), Vector2(0.04, 0.018), Vector2(0.022, 0.03), Vector2(0.0, 0.034)], HUB, 14,
			face)
	b.colour = _c_paint
	Shapes.beam(b, HUB + tilt * Vector3(0, 0, -0.02), HUB + tilt * Vector3(0, 0, -0.5), Vector2(0.05, 0.05))
	# The gear selector on the column: a chrome stalk, an ivory knob.
	var stalk := HUB + tilt * Vector3(0, 0, -0.12)
	Shapes.beam(c, stalk, stalk + tilt * Vector3(0.2, 0.03, 0.02), Vector2(0.01, 0.01))
	b.colour = _lin(RoomSchemaRef.to_color(params["piping"].get("color", "#dbccb3")))
	b.rounded_box(stalk + tilt * Vector3(0.21, 0.03, 0.02), Vector3(0.028, 0.028, 0.028), 0.012, Transform3D(), 1)
	b.colour = Color.WHITE
	var ao := Callable(self, "_occlusion")
	b.shade(ao)
	c.shade(ao)
	var mesh := b.commit(false)
	var cm := c.commit(false)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, cm.surface_get_arrays(0))
	mesh.surface_set_material(1, _chrome)
	var mi := _add_mesh("Wheel", mesh)
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED


## The headlamps (round, in the wings' hoods) and the tail lamps (red lenses at the nacelles' ends): off while parked
## (headlamps 0), a glow when lit; one draw in their vertex colours.
func _build_lamps() -> void:
	var on := float(params["headlamps"])
	var b := RoomMesh.new()
	_lamps_m = _lamp(Color.WHITE, 1.6 * on, 0.0, "accent")
	_lamps_m.set_shader_parameter("use_vertex_colour", true)
	b.surface(_lamps_m)
	b.colour = Color(1.0, 0.95, 0.82)
	for s: float in [-1.0, 1.0]:
		Shapes.lathe(b, [Vector2(0.078, 0.0), Vector2(0.06, 0.012), Vector2(0.0, 0.02)], _headlamp_at(s), 16,
				Basis(Vector3.RIGHT, -PI * 0.5))
	b.colour = Color(0.95, 0.06, 0.03) * 0.8
	for s: float in [-1.0, 1.0]:
		Shapes.lathe(b, [Vector2(0.054, 0.0), Vector2(0.042, 0.016), Vector2(0.0, 0.024)], _tail_lamp_at(s), 14,
				Basis(Vector3.RIGHT, PI * 0.5))
	_add_lamps("Lamps", b)


func on_screen_changed(local: Transform3D, size: Vector2) -> void:
	_screen_local = local
	_screen_size = size


func tick(delta: float) -> void:
	super.tick(delta)
	var glint := color_param("glint_colour") * float(params["glint_energy"])
	var at: Array = params["glint_at"]
	Reflect.update([_paint, _chrome], _sky, room, _screen_local, _screen_size,
			Vector3(float(at[0]), float(at[1]), float(at[2])), glint, Vector2(2.6, 0.5),
			float(params["reflect_screen"]))
	if _dials != null:
		_dials.set_shader_parameter("hour", _sky_hour())
	if _glass != null and _sky != null and is_instance_valid(_sky):
		var l: Dictionary = _sky.call("sky_light")
		_glass.set_shader_parameter("sky_colour", (l["horizon"] as Color).lerp(l["zenith"], 0.4))


func _param_changed(param: String, value: Variant) -> void:
	match param:
		"headlamps":
			if _lamps_m != null:
				_lamps_m.set_shader_parameter("energy", 1.6 * float(value) * _group_level("accent"))
		"dial_glow":
			if _dials != null:
				_dials.set_shader_parameter("energy", float(value) * _group_level("accent"))
			_light.set_lamp(_dash_lamp, _dash_light_colour())


## The materials that reflect (tests).
func reflective_materials() -> Array[ShaderMaterial]:
	return [_paint, _chrome]
