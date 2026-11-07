extends "res://scripts/env/systems/kit/builder.gd"

## The dome hall builder (docs/environments.md, "The builders"): a round hall under a dome, glass or solid. A round
## floor, a low drum wall, the dome over it (glass panes between metal ribs, or a solid shell), a ring of small lamps
## round the drum's top, a low stage under the screen, and seats on arcs round the screen (a ring of seating that
## faces it). Beyond a glass dome: nothing (a sky system's sky), deep water lit from above (a bathysphere), or a dark
## night. Without its floor and seats it covers another builder (the crater: a lunar amphitheatre under a glass dome).
##   Floor, Drum, Dome (solid) or Panes (glass) and Ribs, Stage, Lamps, Outside, Seats
## Slots for the kit: drum (round the wall, facing in), screen, proscenium, floor, ceiling.

static func spec() -> Dictionary:
	return {
		"kind": "builder",
		"description": "A round hall under a dome, glass or solid: a round floor, a low drum wall, the dome (glass "
				+ "panes between metal ribs, or a solid shell), lamps round the drum, a low stage under the screen, "
				+ "seats on arcs round the screen. Beyond glass: a sky, deep water or a dark night. Without its floor "
				+ "and seats it covers another builder (a lunar amphitheatre under a glass dome).",
		"params": PARAMS,
		"requires": ["light"],
		"provides": ["seats", "collision", "sound_room", "bake", "slots"],
		"cost": {"draws": 9, "triangles": 30000, "lights": 0, "particles": 0, "texture_mb": 20},
	}


const PARAMS := {
	"radius": {"type": "float", "min": 3.0, "max": 60.0, "default": 9.0, "description": "the hall's radius, metres"},
	"centre_z": {"type": "float", "min": -60.0, "max": 10.0, "default": -2.5,
			"description": "z of the hall's centre (the viewer's seat is at the origin)"},
	"floor_y": {"type": "float", "min": -10.0, "max": 0.0, "default": 0.0,
			"description": "the hall's floor (under the viewer's seat: 0)"},
	"drum_height": {"type": "float", "min": 0.0, "max": 10.0, "default": 2.4,
			"description": "the straight wall round the floor, under the dome"},
	"dome_height": {"type": "float", "min": 1.0, "max": 60.0, "default": 7.5,
			"description": "the dome's rise over the drum"},
	"dome": {"type": "enum", "values": ["glass", "solid"], "default": "glass", "description": "the dome's shell"},
	"ribs": {"type": "int", "min": 0, "max": 48, "default": 16, "description": "a glass dome's ribs"},
	"rings": {"type": "int", "min": 0, "max": 12, "default": 3, "description": "a glass dome's rings between them"},
	"outside": {"type": "enum", "values": ["none", "water", "night"], "default": "water",
			"description": "beyond a glass dome: nothing (a sky system's), deep water, or a dark night"},
	"water_top": {"type": "color", "default": [0.05, 0.22, 0.32], "description": "the water's colour above"},
	"water_deep": {"type": "color", "default": [0.0, 0.02, 0.05], "description": "the water's colour below"},
	"outside_glow": {"type": "float", "min": 0.0, "max": 2.0, "default": 0.5, "live": true, "brightness": true,
			"description": "how bright the water or the night shows"},
	"has_floor": {"type": "bool", "default": true,
			"description": "the hall's own floor, drum and stage (off: it covers another builder's floor)"},
	"seating": {"type": "bool", "default": true, "description": "seats on arcs round the screen"},
	"rows_front": {"type": "int", "min": 0, "max": 12, "default": 2, "description": "rows in front of the viewer's"},
	"rows_back": {"type": "int", "min": 0, "max": 12, "default": 3, "description": "rows behind the viewer's"},
	"row_depth": {"type": "float", "min": 0.8, "max": 3.0, "default": 1.15, "description": "metres a row"},
	"seat_pitch": {"type": "float", "min": 0.5, "max": 1.5, "default": 0.68, "description": "seat centres, metres"},
	"arc_deg": {"type": "float", "min": 20.0, "max": 200.0, "default": 110.0,
			"description": "the arcs' spread, degrees, centred on the screen"},
	"seat_model": {"type": "enum", "values": ["plush", "club", "folding"], "default": "plush",
			"description": "the plain seat drawn when the room has no seats system"},
	"screen_size": {"type": "vec2", "min": 1.0, "max": 30.0, "default": [6.4, 3.6],
			"description": "the screen, width and height"},
	"screen_z": {"type": "float", "min": -60.0, "max": -2.0, "default": -8.8,
			"description": "z of the screen (the arcs are centred on it)"},
	"screen_bottom": {"type": "float", "min": 0.6, "max": 20.0, "default": 1.25,
			"description": "the picture's bottom edge over the floor"},
	"stage": {"type": "bool", "default": true, "description": "a low stage under the screen"},
	"floor": {"type": "material", "default": {"library": "terrazzo", "color": [0.3, 0.32, 0.33]},
			"description": "the floor and the stage"},
	"drum": {"type": "material", "default": {"library": "dark_metal", "color": [0.2, 0.22, 0.23]},
			"description": "the drum wall"},
	"frame": {"type": "material", "default": {"library": "brushed_steel", "color": [0.35, 0.36, 0.36]},
			"description": "a glass dome's ribs and rings"},
	"shell": {"type": "material", "default": {"library": "smooth_concrete", "color": [0.35, 0.34, 0.33]},
			"description": "a solid dome"},
	"seat_cover": {"type": "material", "default": {"library": "velvet", "color": [0.12, 0.2, 0.32], "tiling": 0.22},
			"description": "the seats' cover"},
	"seat_frame": {"type": "material", "default": {"library": "dark_metal", "color": [0.1, 0.1, 0.11]},
			"description": "the seats' frame"},
	"glass_colour": {"type": "color", "default": [0.55, 0.75, 0.82], "description": "the glass's tint"},
	"lamps": {"type": "int", "min": 0, "max": 24, "default": 12, "description": "lamps round the drum's top"},
	"lamp_colour": {"type": "color", "default": [1.0, 0.82, 0.6], "description": "the lamps' glow"},
}


# --- From parameters alone ----------------------------------------------------------------------------------------

static func _centre(p: Dictionary) -> Vector3:
	return Vector3(0.0, float(p["floor_y"]), float(p["centre_z"]))


static func _box(p: Dictionary) -> AABB:
	var r := float(p["radius"])
	var c := _centre(p)
	return AABB(c - Vector3(r, 0.0, r), Vector3(r * 2.0, float(p["drum_height"]) + float(p["dome_height"]), r * 2.0))


static func seat_slots_for(p: Dictionary) -> Array:
	if not bool(p["seating"]):
		return []
	var out: Array = []
	var foot := Vector3(0.0, 0.0, float(p["screen_z"]))
	var d0 := -foot.z
	var half := deg_to_rad(float(p["arc_deg"])) * 0.5
	var c := _centre(p)
	var r_hall := float(p["radius"]) - 0.6
	for row in range(-int(p["rows_back"]), int(p["rows_front"]) + 1):
		var r := d0 - row * float(p["row_depth"])
		if r < 1.5:
			continue
		for s: Dictionary in U.arc(foot, r, float(p["floor_y"]), float(p["seat_pitch"]), half, row, "ring"):
			var o := (s["transform"] as Transform3D).origin
			if Vector2(o.x - c.x, o.z - c.z).length() <= r_hall:
				out.append(s)
	return out


static func layout(p: Dictionary) -> SeatList:
	return SeatList.new(seat_slots_for(p))


static func screen_for(p: Dictionary) -> Dictionary:
	var s := U.v2(p["screen_size"])
	return {"center": [0.0, float(p["floor_y"]) + float(p["screen_bottom"]) + s.y * 0.5, float(p["screen_z"])],
			"size": [s.x, s.y]}


static func _stage(p: Dictionary) -> Array:
	var s := U.v2(p["screen_size"])
	return [Vector3(0.0, float(p["floor_y"]) + 0.15, float(p["screen_z"]) - 0.4), Vector3(s.x + 1.2, 0.3, 1.6)]


static func collision_shapes_for(p: Dictionary, with_seats := true) -> Array:
	var out: Array = []
	var c := _centre(p)
	var r := float(p["radius"])
	var top := float(p["drum_height"]) + float(p["dome_height"])
	if bool(p["has_floor"]):
		out.append(PhysicsShapes.box(c + Vector3(0, -0.5, 0), Vector3(r * 2.0 + 2.0, 1.0, r * 2.0 + 2.0)))
		if bool(p["stage"]):
			var st := _stage(p)
			out.append(PhysicsShapes.box(st[0], st[1]))
	# The drum and the dome's lower part as boxes round the circle, a cap over the top.
	var n := 16
	var chord := 2.0 * (r + 0.5) * tan(PI / n) * 1.05
	var wall_h := float(p["drum_height"]) + float(p["dome_height"]) * 0.5
	for k in n:
		var a := TAU * k / n
		var dir := Vector3(sin(a), 0, cos(a))
		out.append(PhysicsShapes.box(c + dir * (r + 0.5) + Vector3(0, wall_h * 0.5, 0), Vector3(chord, wall_h, 1.0),
				Basis(Vector3.UP, a)))
	out.append(PhysicsShapes.box(c + Vector3(0, top * 0.85 + 0.5, 0), Vector3(r * 1.8, 1.0, r * 1.8)))
	if with_seats:
		out.append_array(U.seat_boxes(seat_slots_for(p), str(p["seat_model"])))
	return out


static func slots_for(p: Dictionary) -> Dictionary:
	var c := _centre(p)
	var r := float(p["radius"])
	var drum: Array = []
	for k in 12:
		var a := TAU * k / 12.0
		var at := c + Vector3(sin(a), 0, cos(a)) * r
		var into := (c - at).normalized()
		drum.append({"transform": Transform3D(Basis(Vector3.UP.cross(into), Vector3.UP, into), at),
				"size": [2.0, float(p["drum_height"]), 0.5]})
	var sc := screen_for(p)
	var ss := U.v2(sc["size"])
	return {
		"drum": drum,
		"screen": [{"transform": Transform3D(Basis(), U.v3(sc["center"])), "size": [ss.x, ss.y, 0.1]}],
		"proscenium": [{"transform": Transform3D(Basis(), Vector3(0, c.y, float(p["screen_z"]) - 0.3)),
				"size": [ss.x + 2.0, ss.y + float(p["screen_bottom"]) + 1.0, 0.5]}],
		"floor": [{"transform": Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), c), "size": [r * 2.0, r * 2.0, 0.0]}],
		"ceiling": [{"transform": Transform3D(Basis(Vector3.RIGHT, PI * 0.5), c + Vector3(0, float(p["drum_height"])
				+ float(p["dome_height"]), 0)), "size": [r, r, 0.0]}],
	}


func sound_room() -> Dictionary:
	return {"box": _box(params), "surround_height": 2.0, "array": 2, "array_spacing": 3.0}


# --- Building -----------------------------------------------------------------------------------------------------

const SIDES := 32

var _outside: ShaderMaterial


func build() -> void:
	var c := _centre(params)
	var r := float(params["radius"])
	var drum_h := float(params["drum_height"])
	var dome_h := float(params["dome_height"])
	if bool(params["has_floor"]):
		var fl := RoomMesh.new()
		fl.surface(_mat("floor"))
		var disc: Array = []
		for k in SIDES:
			var a := -TAU * k / SIDES
			disc.append(c + Vector3(sin(a) * r, 0, cos(a) * r))
		fl.face(disc, Vector3.UP)
		if bool(params["stage"]):
			var st := _stage(params)
			fl.box(st[0], st[1], Basis(), [RoomMesh.DOWN])
		_add_static("Floor", fl)
	if drum_h > 0.0:
		var drum := RoomMesh.new()
		drum.surface(_mat("drum"))
		Shapes.lathe(drum, [Vector2(r, drum_h), Vector2(r, 0.0)], c, SIDES)
		# A ledge round the drum's top, under the dome.
		Shapes.lathe(drum, [Vector2(r, drum_h), Vector2(r - 0.25, drum_h), Vector2(r - 0.25, drum_h + 0.12),
				Vector2(r, drum_h + 0.12)], c, SIDES)
		_add_static("Drum", drum)
	var base := c + Vector3(0, drum_h, 0)
	if str(params["dome"]) == "solid":
		var shell := RoomMesh.new()
		shell.surface(_mat("shell"))
		_dome_lathe(shell, base, r, dome_h, true)
		_add_static("Dome", shell)
	else:
		var panes := RoomMesh.new()
		panes.surface(GLASS)
		_dome_lathe(panes, base, r, dome_h, true)
		_add_glass("Panes", panes, color_param("glass_colour"), 0.05)
		var ribs := RoomMesh.new()
		ribs.surface(_mat("frame"))
		var n := int(params["ribs"])
		for k in n:
			var a := TAU * k / n
			var prev := Vector3.INF
			for i in 13:
				var lat := PI * 0.5 * i / 12.0
				var p := base + Vector3(sin(a) * cos(lat) * (r - 0.05), sin(lat) * dome_h, cos(a) * cos(lat) * (r - 0.05))
				if prev != Vector3.INF:
					Shapes.beam(ribs, prev, p, Vector2(0.08, 0.1), (p - base).normalized())
				prev = p
		for i in int(params["rings"]):
			var lat := PI * 0.5 * (i + 1) / (int(params["rings"]) + 1)
			var rr := cos(lat) * (r - 0.06)
			var y := sin(lat) * dome_h
			Shapes.lathe(ribs, [Vector2(rr, y - 0.05), Vector2(rr, y + 0.05)], base, SIDES)
		_add_static("Ribs", ribs)
		if str(params["outside"]) != "none":
			_build_outside(c, r, drum_h + dome_h)
	_build_lamps(c, r, drum_h)
	if bool(params["seating"]):
		_build_seat_multimesh(str(params["seat_model"]), _mat("seat_cover", true), _mat("seat_frame", true),
				seat_slots_for(params), 1960)
	_bake_spot("DomeTop", base + Vector3(0, dome_h - 0.5, 0), true, 70.0, drum_h + dome_h + 3.0, 1.0,
			color_param("lamp_colour"))


## A dome's shell as a lathe of an ellipse's quarter (radius across, height up), seen from inside.
func _dome_lathe(b: RoomMesh, base: Vector3, r: float, h: float, inside: bool) -> void:
	var profile: Array = []
	for i in 13:
		var lat := PI * 0.5 * i / 12.0
		profile.append(Vector2(cos(lat) * r, sin(lat) * h))
	if inside:
		profile.reverse()
	Shapes.lathe(b, profile, base, SIDES)


## What a glass dome looks out on: a big sphere round the hall, seen from inside, its colour from the top down (water
## lit from above, fading to the deep; or a dark night). A lamp material: it lights the room a little in a bake.
func _build_outside(c: Vector3, r: float, h: float) -> void:
	var top := color_param("water_top")
	var deep := color_param("water_deep")
	if str(params["outside"]) == "night":
		top = Color(0.02, 0.025, 0.05)
		deep = Color(0.005, 0.005, 0.01)
	var big := maxf(r * 3.0, h * 2.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 12
	var sides := 24
	for i in rings:
		for k in sides:
			var quad: Array = []
			for d: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var lat := PI * 0.5 - PI * float(i + d.y) / rings
				var a := TAU * float(k + d.x) / sides
				quad.append([c + Vector3(sin(a) * cos(lat), sin(lat), cos(a) * cos(lat)) * big,
						Vector2(float(k + d.x) / sides, float(i + d.y) / rings)])
			for t: Array in [[0, 2, 1], [0, 3, 2]]:
				for j: int in t:
					var p: Vector3 = quad[j][0]
					st.set_normal((c - p).normalized())
					st.set_uv(quad[j][1])
					st.add_vertex(p)
	_outside = _lamp(Color(1, 1, 1), float(params["outside_glow"]), 0.0, "accent")
	_outside.set_shader_parameter("picture", Procedural.gradient(top, deep))
	_outside.set_shader_parameter("use_picture", true)
	var mesh := st.commit()
	mesh.surface_set_material(0, _outside)
	var mi := _add_mesh("Outside", mesh)
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED


func _param_changed(param: String, value: Variant) -> void:
	if param == "outside_glow" and _outside != null:
		_outside.set_shader_parameter("energy", float(value) * _group_level("accent"))


## Small lamps round the drum's top (house group): a glowing cap each; stand-in lamps for eight of them.
func _build_lamps(c: Vector3, r: float, drum_h: float) -> void:
	var n := int(params["lamps"])
	if n <= 0 or drum_h <= 0.3:
		return
	var glow := RoomMesh.new()
	glow.surface(_lamp(color_param("lamp_colour"), 1.4, 1.0, "house"))
	var colour: Color = color_param("lamp_colour") * float(_light.params["lamp_energy"]) * 0.6
	var cone := cos(deg_to_rad(float(_light.params["lamp_cone_deg"])))
	for k in n:
		var a := TAU * (k + 0.5) / n
		var dir := Vector3(sin(a), 0, cos(a))
		var at := c + dir * (r - 0.18) + Vector3(0, drum_h - 0.25, 0)
		Shapes.lathe(glow, [Vector2(0.0, -0.08), Vector2(0.09, -0.06), Vector2(0.11, 0.0), Vector2(0.0, 0.02)], at, 8)
		if k % maxi(n / 8, 1) == 0:
			_light.add_lamp(at, colour, cone)
		if k % maxi(n / 4, 1) == 0:
			_bake_omni("Ring%d" % k, at - dir * 0.2, 5.0, 0.5, color_param("lamp_colour"))
	_add_lamps("Lamps", glow)
