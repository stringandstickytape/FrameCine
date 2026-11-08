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
	"glass_alpha": {"type": "float", "min": 0.0, "max": 0.3, "default": 0.05,
			"description": "how much of the glass's tint lies over what is outside (lower: clearer, less haze)"},
	"lamps": {"type": "int", "min": 0, "max": 24, "default": 12, "description": "lamps round the drum's top"},
	"lamp_colour": {"type": "color", "default": [1.0, 0.82, 0.6], "description": "the lamps' glow"},
	"rib_phase": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0,
			"description": "turns a glass dome's ribs by this share of the gap between two (0.5: no rib stands "
			+ "straight behind the screen's middle)"},
	# The water (outside "water"): docs/environments.md "dome_hall", "The water and the sea floor".
	"depth": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.5, "live": true, "brightness": true,
			"description": "how deep the water is: 0 the sunlit shallows (Snell's window overhead, shafts of light, "
			+ "caustics on the sea floor), 0.5 the water's own colours (water_top, water_deep), 1 the abyss (black: "
			+ "only the lamps and what glows show)"},
	"murk": {"type": "float", "min": 0.01, "max": 0.3, "default": 0.07,
			"description": "how quickly the water hides what lies in it, per metre (0.07: 20 m off is mostly water)"},
	"water_motion": {"type": "float", "min": 0.0, "max": 1.0, "default": 1.0, "live": true, "motion": {"max": 1.0},
			"description": "how fast the water's light moves: the shafts sway, caustics drift, fronds sway, marine "
			+ "snow sinks and bubbles rise (the Motion setting scales it)"},
	"seabed": {"type": "bool", "default": false,
			"description": "a sea floor round the hall: banks rising to the sides and behind, a trench falling away "
			+ "behind the screen, rocks and two ledges near the glass"},
	"rocks": {"type": "int", "min": 0, "max": 80, "default": 24, "description": "boulders on the sea floor"},
	"coral": {"type": "int", "min": 0, "max": 60, "default": 0,
			"description": "coral on the right ledge and round it: branching coral, coral heads, sea fans, anemones"},
	"fronds": {"type": "int", "min": 0, "max": 200, "default": 0,
			"description": "tall fronds swaying in beds on the left ledge and the banks (kelp; sea whips deeper)"},
	"wreck": {"type": "bool", "default": false,
			"description": "an old diving bell on its skid, half silted, a fallen derrick and an anchor (left, behind)"},
	"vent": {"type": "bool", "default": false,
			"description": "a vent's chimney (right, behind) whose bubbles rise past the glass to the surface"},
	"bubbles": {"type": "int", "min": 0, "max": 400, "default": 140, "description": "the vent's bubbles at once"},
	"snow": {"type": "int", "min": 0, "max": 3000, "default": 0,
			"description": "specks of marine snow sinking slowly through the water round the dome (never inside it)"},
	"floodlights": {"type": "int", "min": 0, "max": 4, "default": 0,
			"description": "lamps on the drum's top outside, aimed at the ledges, the wreck and the vent; their "
			+ "beams show in the murk"},
	"flood": {"type": "float", "min": 0.0, "max": 2.0, "default": 1.0, "live": true, "brightness": true,
			"description": "how bright the floodlights are (a cue dims them for the film)"},
	"flood_colour": {"type": "color", "default": [1.0, 0.88, 0.7], "description": "the floodlights' light"},
	# The fittings (kit/dome_fittings.gd): a diving bell's inside.
	"portholes": {"type": "int", "min": 0, "max": 24, "default": 0,
			"description": "round ports in the drum (brass rims, the water in their glass), none in front"},
	"rivets": {"type": "bool", "default": false,
			"description": "rivet heads along a glass dome's ribs and round the drum's ledge"},
	"gauges": {"type": "int", "min": 0, "max": 12, "default": 0,
			"description": "pressure gauges round the drum (and two on the console), backlit faces"},
	"gauge": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true,
			"description": "how far the gauges' needles swing from their rest (bind it to film.bass)"},
	"console": {"type": "bool", "default": false,
			"description": "an instrument desk against the drum behind the seats, a sonar scope in its middle"},
	"sonar": {"type": "float", "min": 0.0, "max": 1.5, "default": 1.0, "live": true, "brightness": true,
			"description": "the sonar scope's glow (its sweep turns once in 6 s)"},
	"hatch": {"type": "bool", "default": false,
			"description": "a round hatch with a wheel in the floor behind the last row"},
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
	if bool(p["console"]) and bool(p["has_floor"]):
		var cb := Fittings.console_box(p)
		out.append(PhysicsShapes.box(cb[0], cb[1], cb[2]))
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
		_add_glass("Panes", panes, color_param("glass_colour"), float(params["glass_alpha"]))
		var ribs := RoomMesh.new()
		ribs.surface(_mat("frame"))
		var n := int(params["ribs"])
		for k in n:
			var a := TAU * (k + float(params["rib_phase"])) / n
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
		if str(params["outside"]) == "water":
			_build_sea()
	_build_lamps(c, r, drum_h)
	_build_fittings()
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
	var rings := 24
	var sides := 48
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
	if str(params["outside"]) == "water":
		# The water's own shader (env_water_outside.gdshader): its colour by where the eye looks, the surface's light.
		_outside = ShaderMaterial.new()
		_outside.shader = WATER_SHADER
		_water_mats.append(_outside)
	else:
		_outside = _lamp(Color(1, 1, 1), float(params["outside_glow"]), 0.0, "accent")
		_outside.set_shader_parameter("picture", Procedural.gradient(top, deep))
		_outside.set_shader_parameter("use_picture", true)
	var mesh := st.commit()
	mesh.surface_set_material(0, _outside)
	var mi := _add_mesh("Outside", mesh)
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_apply_water()


func _param_changed(param: String, value: Variant) -> void:
	if param == "outside_glow" and _outside != null:
		_outside.set_shader_parameter("energy", float(value) * _group_level("accent"))
	elif param in ["depth", "water_motion", "flood"]:
		_apply_water()
	elif param == "gauge":
		_place_needles()
	elif param == "sonar" and _sonar != null:
		_sonar.set_shader_parameter("glow", float(value))


# --- The water and the sea floor ------------------------------------------------------------------------------------

const WATER_SHADER := preload("res://shaders/env_water_outside.gdshader")
const Seabed := preload("res://scripts/env/systems/kit/seabed.gd")
## The water's colours at the two ends of `depth` (sRGB); 0.5 is the document's water_top and water_deep.
const SHALLOW_TOP := Color(0.1, 0.4, 0.5)
const SHALLOW_DEEP := Color(0.02, 0.13, 0.19)
const ABYSS_TOP := Color(0.004, 0.012, 0.024)
const ABYSS_DEEP := Color(0.0, 0.0, 0.003)
## The floodlights' cones: half angle (degrees) and how far a beam shows.
const FLOOD_DEG := 17.0
const FLOOD_REACH := 15.0

## Every material that draws the water or something in it (they share its uniforms).
var _water_mats: Array[ShaderMaterial] = []
var _flood_lamps: Array = []
var _flood_lens: ShaderMaterial
var _accent_seen := -1.0


## The water's colours, its light from the surface and its glow in the abyss at a depth (0..1).
func water_at(depth: float) -> Dictionary:
	var top := color_param("water_top")
	var deep := color_param("water_deep")
	if depth < 0.5:
		top = SHALLOW_TOP.lerp(top, depth * 2.0)
		deep = SHALLOW_DEEP.lerp(deep, depth * 2.0)
	else:
		top = top.lerp(ABYSS_TOP, (depth - 0.5) * 2.0)
		deep = deep.lerp(ABYSS_DEEP, (depth - 0.5) * 2.0)
	return {"top": top, "deep": deep, "sun": pow(clampf((0.8 - depth) / 0.8, 0.0, 1.0), 1.8),
			"biolum": smoothstep(0.55, 1.0, depth)}


## The water's uniforms on every material that draws it (a live parameter changed, the room moved).
func _apply_water() -> void:
	if _water_mats.is_empty():
		return
	var w := water_at(float(params["depth"]))
	var xf := room.global_transform if room.is_inside_tree() else Transform3D()
	var pos := PackedVector4Array()
	var aim := PackedVector4Array()
	var cone := cos(deg_to_rad(FLOOD_DEG))
	for l: Array in _flood_lamps:
		var p: Vector3 = xf * (l[0] as Vector3)
		var d: Vector3 = (xf.basis * (l[1] as Vector3)).normalized()
		pos.append(Vector4(p.x, p.y, p.z, 1.0))
		aim.append(Vector4(d.x, d.y, d.z, cone))
	while pos.size() < Seabed.FLOOD_TARGETS.size():
		pos.append(Vector4.ZERO)
		aim.append(Vector4(0, -1, 0, 1))
	var flood := float(params["flood"]) * _group_level("accent")
	for m in _water_mats:
		m.set_shader_parameter("water_top", w["top"])
		m.set_shader_parameter("water_deep", w["deep"])
		m.set_shader_parameter("sun", w["sun"])
		m.set_shader_parameter("murk", float(params["murk"]))
		m.set_shader_parameter("water_motion", float(params["water_motion"]))
		m.set_shader_parameter("caustic_map", Seabed.caustic_map())
		m.set_shader_parameter("flood_count", _flood_lamps.size())
		m.set_shader_parameter("flood_pos", pos)
		m.set_shader_parameter("flood_aim", aim)
		m.set_shader_parameter("flood_colour", color_param("flood_colour"))
		m.set_shader_parameter("flood", flood)
		m.set_shader_parameter("screen_normal", xf.basis.z.normalized())
		m.set_shader_parameter("biolum", w["biolum"])
	if _outside != null and str(params["outside"]) == "water":
		_outside.set_shader_parameter("energy", float(params["outside_glow"]) * _group_level("accent"))
	if _flood_lens != null:
		_flood_lens.set_shader_parameter("energy", 0.9 * flood)


## The sea floor and what is in the water (kit/seabed.gd): each part only when the document asks for it.
func _build_sea() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1934
	if bool(params["seabed"]):
		var bed := ShaderMaterial.new()
		bed.shader = Seabed.SEABED_SHADER
		bed.set_shader_parameter("sway", 0.0)
		_water_mats.append(bed)
		var floor_mesh := Seabed.floor_mesh(params, rng)
		floor_mesh.surface_set_material(0, bed)
		_add_mesh("Seabed", floor_mesh).gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		if int(params["fronds"]) > 0:
			var fm := ShaderMaterial.new()
			fm.shader = Seabed.SEABED_SHADER
			fm.set_shader_parameter("sway", 0.35)
			_water_mats.append(fm)
			var fronds := Seabed.fronds_mesh(params, rng, int(params["fronds"]))
			fronds.surface_set_material(0, fm)
			_add_mesh("Fronds", fronds).gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	if bool(params["vent"]) and int(params["bubbles"]) > 0:
		var bm := ShaderMaterial.new()
		bm.shader = Seabed.MOTES_SHADER
		bm.set_shader_parameter("kind", 1)
		bm.set_shader_parameter("size", 0.07)
		bm.set_shader_parameter("opacity", 0.55)
		bm.set_shader_parameter("vent", Seabed.vent_top(params))
		bm.set_shader_parameter("rise_height", Seabed.water_radius(params) - Seabed.vent_top(params).y - 2.0)
		_water_mats.append(bm)
		var bubbles := Seabed.motes_mesh(params, rng, int(params["bubbles"]), false)
		bubbles.surface_set_material(0, bm)
		_add_water("Bubbles", bubbles)
	if int(params["snow"]) > 0:
		var sm := ShaderMaterial.new()
		sm.shader = Seabed.MOTES_SHADER
		sm.set_shader_parameter("kind", 0)
		sm.set_shader_parameter("dome_centre", _centre(params))
		sm.set_shader_parameter("dome_radius", float(params["radius"]))
		sm.set_shader_parameter("dome_drum", float(params["drum_height"]))
		sm.set_shader_parameter("dome_height", float(params["dome_height"]))
		_water_mats.append(sm)
		var snow := Seabed.motes_mesh(params, rng, int(params["snow"]), true)
		snow.surface_set_material(0, sm)
		_add_water("MarineSnow", snow)
	var n := int(params["floodlights"])
	if n > 0:
		_flood_lamps = Seabed.floods(params, n)
		var beams := ShaderMaterial.new()
		beams.shader = Seabed.BEAM_SHADER
		beams.set_shader_parameter("reach", FLOOD_REACH)
		beams.set_shader_parameter("spread", tan(deg_to_rad(FLOOD_DEG)))
		_water_mats.append(beams)
		var bmesh := Seabed.beams_mesh(_flood_lamps, FLOOD_REACH, FLOOD_DEG)
		bmesh.surface_set_material(0, beams)
		_add_water("FloodBeams", bmesh)
		# The lamps' lenses on the drum's top: small round glows.
		var lens := RoomMesh.new()
		_flood_lens = _lamp(color_param("flood_colour"), 0.9, 0.0, "accent")
		lens.surface(_flood_lens)
		for l: Array in _flood_lamps:
			var at_p: Vector3 = l[0]
			var d: Vector3 = l[1]
			Shapes.cylinder(lens, at_p - d * 0.05, 0.07, 0.06, 10, Basis(d.cross(Vector3.UP).normalized(), -acos(
					clampf(d.dot(Vector3.UP), -1.0, 1.0))))
		_add_lamps("FloodLamps", lens)
	_apply_water()


## A diving bell's fittings (kit/dome_fittings.gd), each only when the document asks for it.
func _build_fittings() -> void:
	var p := params
	if not bool(p["has_floor"]):
		return
	var brass := RoomMesh.new()
	brass.surface(_mat("frame"))
	var dark := RoomMesh.new()
	dark.surface(_mat("drum"))
	var small := RoomMesh.new()
	small.surface(_mat("frame"))
	if int(p["portholes"]) > 0 and str(p["outside"]) == "water":
		Fittings.porthole_rims(brass, p)
		var glass := ShaderMaterial.new()
		glass.shader = WATER_SHADER
		_water_mats.append(glass)
		var gm := Fittings.porthole_glass(p)
		gm.surface_set_material(0, glass)
		_add_mesh("PortGlass", gm).gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	if bool(p["rivets"]) and str(p["dome"]) == "glass":
		Fittings.rivets(small, p)
	var lamps: Array = []
	if bool(p["console"]):
		lamps = Fittings.console(dark, brass, small, p)
		var scope := ShaderMaterial.new()
		scope.shader = SONAR_SHADER
		scope.set_shader_parameter("glow", float(p["sonar"]))
		_sonar = scope
		var q: Array = Fittings.scope_quad(p)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var cc: Vector3 = q[0]
		var u: Vector3 = q[1]
		var v: Vector3 = q[2]
		for k: Array in [[-1, -1], [1, -1], [1, 1], [-1, -1], [1, 1], [-1, 1]]:
			st.set_normal(q[3])
			st.set_uv(Vector2((k[0] + 1) * 0.5, (1 - k[1]) * 0.5))
			st.add_vertex(cc + u * k[0] + v * k[1])
		var sm := st.commit()
		sm.surface_set_material(0, scope)
		_add_mesh("Sonar", sm).gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	if bool(p["hatch"]):
		Fittings.hatch(brass, dark, p)
	_gauges = Fittings.gauges(p)
	if not _gauges.is_empty():
		Fittings.gauge_bezels(brass, p)
		_add_picture("GaugeFaces", Fittings.gauge_faces(p), Fittings.gauge_face(), Color(1.0, 0.92, 0.78), 0.55,
				"accent")
		var nm: ShaderMaterial = _light.library("dark_metal", Color(0.05, 0.04, 0.03), {}, true)
		var mesh := Fittings.needle_mesh(float(_gauges[-1][4]), nm)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = _gauges.size()
		_needles = MultiMeshInstance3D.new()
		_needles.name = "Needles"
		_needles.multimesh = mm
		_needles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_needles.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		own(_needles)
		_place_needles()
	if not lamps.is_empty():
		# Small steady indicator lamps, green, amber and blue: three materials, one draw each.
		var greens := RoomMesh.new()
		var mats: Array = []
		for col: Color in [Color(0.3, 1.0, 0.45), Color(1.0, 0.65, 0.2), Color(0.35, 0.8, 1.0)]:
			mats.append(_lamp(col, 1.2, 0.0, "accent"))
		for l: Array in lamps:
			var q: Array = l[0]
			greens.surface(mats[int(l[1])])
			Shapes.cylinder(greens, (q[0] as Vector3), 0.016, 0.012, 8, _basis_facing(q[3]))
		_add_lamps("ConsoleLamps", greens)
	# Unbaked: their many small faces would each be a lightmap chart (bolts, toggles, a gauge's bezel).
	_add_unbaked("Fittings", brass)
	_add_unbaked("FittingsDark", dark)
	_add_unbaked("Rivets", small)


## A basis whose local +Y is `n` (a cylinder standing out of a panel).
static func _basis_facing(n: Vector3) -> Basis:
	var y := n.normalized()
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	return Basis(x, y, x.cross(y))


const Fittings := preload("res://scripts/env/systems/kit/dome_fittings.gd")
const SONAR_SHADER := preload("res://shaders/env_sonar.gdshader")
var _gauges: Array = []
var _needles: MultiMeshInstance3D
var _sonar: ShaderMaterial
var _needle_t := 0.0


## The needles at their readings: each its own rest, swinging with `gauge`, trembling a little (slowly).
func _place_needles() -> void:
	if _needles == null:
		return
	var readings := needle_readings()
	for i in _gauges.size():
		_needles.multimesh.set_instance_transform(i, Fittings.needle_xform(_gauges[i], readings[i]))


## Light in the water (specks, beams): see-through for the sight-line check, never baked.
func _add_water(node_name: String, mesh: Mesh) -> MeshInstance3D:
	var mi := _add_mesh(node_name, mesh)
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.add_to_group(SEE_THROUGH)
	return mi


## The gauges' readings now (0..1 of each needle's sweep; tests).
func needle_readings() -> Array[float]:
	var out: Array[float] = []
	var g := float(params["gauge"])
	for i in _gauges.size():
		var e: Array = _gauges[i]
		out.append(float(e[2]) + float(e[3]) * g + 0.012 * sin(_needle_t * 0.9 + i * 1.7))
	return out


func on_room_moved() -> void:
	super.on_room_moved()
	_apply_water()


func on_screen_changed(_local: Transform3D, _size: Vector2) -> void:
	_apply_water()


func tick(delta: float) -> void:
	super.tick(delta)
	if _needles != null:
		_needle_t += delta
		_place_needles()
	# The accent group's level (the light system's) scales the water's glow and the floodlights.
	var acc := _group_level("accent") if _light != null else 1.0
	if acc != _accent_seen:
		_accent_seen = acc
		_apply_water()


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
