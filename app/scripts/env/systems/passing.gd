extends "res://scripts/env/systems/env_system.gd"

## Scenery that goes by outside a cabin's windows (docs/environments/passing.md): a journey as long as the film. The
## viewer never moves; the scenery does. The cabin's place along its way follows the film's position: a pause holds
## it, a seek goes dark, moves and comes back, and a film of known length arrives at the route's end as it ends. A
## film with no length never arrives.
##
## Everything that comes round (bands: rows and scatters of one shape on a loop), what stands once (landmarks) and the
## ground beside the way are three meshes, three draws. Nothing is moved on the CPU: each tick sets the shaders'
## uniforms (each band's phase along its loop, each landmark's place), and the shaders carry the scenery past.
## The comfort limits are env_checks.gd's FLOW_* constants; comfort_for() and flow_volumes() hold a room to them.
##
## The way's frame: a across the way (positive: to the right of the way the cabin goes), y up, t along (ahead
## positive). The cabin goes along the room's Z axis: towards -Z when `facing` is forward, +Z when backward.

const EnvChecks := preload("res://scripts/env/env_checks.gd")
const EnvSignals := preload("res://scripts/env/env_signals.gd")
const ShapeMesh := preload("res://scripts/env/systems/passing/shape_mesh.gd")
const Shapes := preload("res://scripts/env/systems/passing/shapes.gd")
const SkySystem := preload("res://scripts/env/systems/sky.gd")
const SHADER := preload("res://shaders/env_passing.gdshader")
const LIGHTS_SHADER := preload("res://shaders/env_passing_lights.gdshader")
const GROUND_SHADER := preload("res://shaders/env_passing_ground.gdshader")

## Under way it may go this much faster or slower than its speed to stay with the film.
const CATCH_UP := 0.15
## It slows for the route's end at half the limit: an arrival is gentle.
const BRAKE := EnvChecks.FLOW_ACCEL * 0.5
## Seconds: the scenery goes dark, moves, comes back.
const BLINK_OUT := 0.5
const BLINK_IN := 1.0
## Nothing is drawn further than this from the origin: the camera's far plane is 200.
const FAR := 188.0
## An item grows from nothing over the last (1 - EDGE) of its loop's half length.
const EDGE := 0.82
## Metres: the ground's pattern repeats over this.
const GROUND_PERIOD := 64.0
## The presence texture's width.
const PRESENCE_WIDTH := 64
## How far ahead and astern the ground strips reach (metres).
const GROUND_REACH := 175.0
## The shaders' uniform arrays: at most this many bands and landmarks (the spec's list maxima).
const MAX_BANDS := 10
const MAX_LANDMARKS := 12
## Where the scenery can be drawn, about the origin (its vertices are placed in the shader, not on the CPU).
const SCENERY_AABB := AABB(Vector3(-190.0, -30.0, -190.0), Vector3(380.0, 100.0, 380.0))
## The ground's kinds, in the order of their index (UV2.x), and their own colours.
const GROUND_KINDS: Array[String] = ["water", "grass", "path", "field", "snow", "sand", "stone"]
const KIND_COLOURS := {"water": "#0c1218", "grass": "#1a2414", "path": "#3b362c", "field": "#201c16",
		"snow": "#c8ccd6", "sand": "#4a4232", "stone": "#34322e"}


static func spec() -> Dictionary:
	var band := {
		"shape": {"type": "enum", "values": Shapes.BANDS, "required": true, "description": "what stands in the band"},
		"side": {"type": "enum", "values": ["left", "right", "both"], "default": "both",
				"description": "which side of the way"},
		"near": {"type": "float", "min": 3.0, "max": 170.0, "default": 6.0,
				"description": "the nearest its feet stand from the way's line, metres"},
		"far": {"type": "float", "min": 3.0, "max": 170.0, "default": 12.0,
				"description": "the furthest its feet stand from the way's line (made at least near)"},
		"count": {"type": "int", "min": 1, "max": 600, "default": 40,
				"description": "how many (shapes that stand end to end in a row: the loop's length decides)"},
		"length": {"type": "float", "min": 60.0, "max": 340.0, "default": 240.0,
				"description": "the loop's length, metres: after it the band comes round again"},
		"seems": {"type": "float", "min": 1.0, "max": 200.0, "default": 1.0,
				"description": "how many times further off it seems than it is drawn; it goes by that much slower"},
		"height": {"type": "float", "min": -20.0, "max": 40.0, "default": 0.0, "description": "its feet's height"},
		"size": {"type": "float", "min": 0.1, "max": 6.0, "default": 1.0, "description": "times its natural size"},
		"colour": {"type": "color", "description": "its main colour (none: the shape's own)"},
		"seed": {"type": "int", "min": 0, "max": 100000, "default": 0,
				"description": "another arrangement of the same"},
		"presence": {"type": "list", "max": 8, "of": {"type": "vec2", "min": 0.0, "max": 1.0},
				"default": [[0.0, 1.0]],
				"description": "[[route fraction, how much of it]]: where along the route it stands"},
	}
	var landmark := {
		"shape": {"type": "enum", "values": Shapes.LANDMARKS, "required": true, "description": "what it is"},
		"at": {"type": "float", "min": 0.0, "max": 1.0, "required": true,
				"description": "its place on the route, as a fraction"},
		"side": {"type": "enum", "values": ["left", "right"], "default": "left",
				"description": "which side of the way"},
		"distance": {"type": "float", "min": 3.0, "max": 170.0, "default": 8.0,
				"description": "metres from the way's line"},
		"height": {"type": "float", "min": -20.0, "max": 40.0, "default": 0.0, "description": "its foot's height"},
		"size": {"type": "float", "min": 0.1, "max": 6.0, "default": 1.0, "description": "times its natural size"},
		"colour": {"type": "color", "description": "its main colour (none: the shape's own)"},
		"seed": {"type": "int", "min": 0, "max": 100000, "default": 0,
				"description": "another arrangement of the same"},
	}
	var strip := {
		"side": {"type": "enum", "values": ["left", "right", "both"], "default": "both",
				"description": "which side of the way"},
		"from": {"type": "float", "min": 0.0, "max": 175.0, "required": true,
				"description": "its near edge, metres from the way's line"},
		"to": {"type": "float", "min": 0.0, "max": 175.0, "required": true,
				"description": "its far edge, metres from the way's line"},
		"height_from": {"type": "float", "min": -20.0, "max": 40.0, "default": 0.0,
				"description": "its height at its near edge"},
		"height_to": {"type": "float", "min": -20.0, "max": 40.0, "default": 0.0,
				"description": "its height at its far edge"},
		"kind": {"type": "enum", "values": GROUND_KINDS, "default": "grass", "description": "what it is"},
		"colour": {"type": "color", "description": "its colour (none: the kind's own)"},
	}
	return {
		"kind": "journey",
		"moves_viewer": false,
		"description": "Scenery that goes by outside a cabin's windows, on a journey as long as the film: rows of "
				+ "trees, hedges, far ridges and lights that come round, landmarks that stand once on the route, "
				+ "strips of ground and water. The viewer never moves. A pause holds it; a seek goes dark and moves.",
		"params": {
			"facing": {"type": "enum", "values": ["forward", "backward"], "default": "forward",
					"description": "which way the cabin goes: forward towards the screen's side (-Z), or backward"},
			"speed": {"type": "float", "min": 0.0, "max": 12.0, "default": 1.0, "live": true,
					"motion": {"max": 12.0}, "description": "metres a second under way"},
			"arrive": {"type": "bool", "default": true,
					"description": "with a film of known length, slow down and stop at the route's end as it ends"},
			"bands": {"type": "list", "max": MAX_BANDS, "of": {"type": "object", "fields": band}, "default": [],
					"description": "the scenery that comes round: [{shape, side, near, far, count, length, seems, "
					+ "height, size, colour, seed, presence}]"},
			"landmarks": {"type": "list", "max": MAX_LANDMARKS, "of": {"type": "object", "fields": landmark},
					"default": [], "description": "things that stand once on the route: [{shape, at, side, distance, "
					+ "height, size, colour, seed}]"},
			"ground": {"type": "list", "max": 12, "of": {"type": "object", "fields": strip}, "default": [],
					"description": "strips of ground or water: [{side, from, to, height_from, height_to, kind, "
					+ "colour}]"},
			"light": {"type": "float", "min": 0.0, "max": 2.0, "default": 1.0, "live": true, "brightness": true,
					"description": "the scenery's light: 1 as the sky lights it"},
			"sky_light": {"type": "bool", "default": true,
					"description": "lit by the room's sky system (its colours overhead and at the horizon)"},
			"night": {"type": "color", "default": "#1b2236", "live": true,
					"description": "the light on the scenery without a sky system"},
			"glow": {"type": "float", "min": 0.0, "max": 2.0, "default": 0.6, "live": true, "brightness": true,
					"description": "the cabin's own light on what passes close"},
			"glow_colour": {"type": "color", "default": "#ffc27a", "live": true,
					"description": "the cabin's light's colour"},
			"glow_reach": {"type": "float", "min": 1.0, "max": 20.0, "default": 6.0,
					"description": "metres from the way's line at which the cabin's glow is gone"},
			"glow_half_length": {"type": "float", "min": 0.5, "max": 30.0, "default": 3.0,
					"description": "how far ahead and astern of the origin the cabin's windows reach, metres"},
			"windows": {"type": "float", "min": 0.0, "max": 2.0, "default": 1.0, "live": true, "brightness": true,
					"description": "the lit windows of the scenery"},
			"lights": {"type": "float", "min": 0.0, "max": 2.0, "default": 1.0, "live": true, "brightness": true,
					"description": "the scenery's points of light"},
			"mist": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true, "brightness": true,
					"description": "mist that takes the far scenery"},
			"mist_colour": {"type": "color", "default": "#3a4250", "live": true, "description": "the mist's colour"},
			"spill": {"type": "float", "min": 0.0, "max": 4.0, "default": 1.0,
					"description": "how much the near scenery catches the screen's light"},
		},
		"cost": {"draws": 3, "triangles": 30000, "lights": 0, "particles": 0, "texture_mb": 0.3},
		"requires": [],
		"provides": ["flow"],
	}


# --- The journey's state ----------------------------------------------------------------------------------------------

## How far the cabin has come (metres, >= 0).
var travel := 0.0
## Its speed now (metres a second).
var speed_now := 0.0
## How dark the scenery is (0..1): a blink takes it to 1 while the cabin moves out of sight.
var dark := 0.0
## The document's speed, before the Motion setting.
var own_speed := 1.0
## The route's length as the scenery shows it (0: no end).
var route_shown := 0.0
## The way's directions in the room's frame (from `facing`).
var along_dir := Vector3(0.0, 0.0, -1.0)
var across_dir := Vector3(1.0, 0.0, 0.0)

var _placed := false
## The blink: 0 none, 1 going dark, 2 coming back.
var _blink := 0
## The cruise of the last tick (on_seek starts a blink only while the journey goes).
var _cruise := 0.0
var _sky: Node
var _scenery: MeshInstance3D
var _lights: MeshInstance3D
var _ground: MeshInstance3D
var _mat: ShaderMaterial
var _lights_mat: ShaderMaterial
var _ground_mat: ShaderMaterial
var _presence_img: Image
var _presence_tex: ImageTexture
## The bands, landmarks and strips as built (defaults filled); each band's loop and seems.
var _bands: Array[Dictionary] = []
var _loops: Array[float] = []
var _seems: Array[float] = []
var _landmarks: Array[Dictionary] = []
var _strips: Array[Dictionary] = []


# --- Building ---------------------------------------------------------------------------------------------------------

func setup() -> void:
	_sky = null
	if bool(params["sky_light"]) and host != null:
		for s: Node in host.systems_of_kind("sky"):
			if s.has_method("sky_light"):
				_sky = s
				break
	var backward := str(params["facing"]) == "backward"
	along_dir = Vector3(0.0, 0.0, 1.0) if backward else Vector3(0.0, 0.0, -1.0)
	across_dir = Vector3(-1.0, 0.0, 0.0) if backward else Vector3(1.0, 0.0, 0.0)
	_bands.clear()
	_loops.clear()
	_seems.clear()
	_landmarks.clear()
	_strips.clear()
	var m := ShapeMesh.new()
	var bands: Array = params["bands"] if params["bands"] is Array else []
	for b in mini(bands.size(), MAX_BANDS):
		if bands[b] is Dictionary:
			_build_band(m, b, band_with_defaults(bands[b]))
	var landmarks: Array = params["landmarks"] if params["landmarks"] is Array else []
	for k in mini(landmarks.size(), MAX_LANDMARKS):
		if landmarks[k] is Dictionary:
			_build_landmark(m, k, landmark_with_defaults(landmarks[k]))
	_presence()
	_mat = null
	_lights_mat = null
	_ground_mat = null
	var mesh := m.commit()
	if mesh != null:
		_mat = _material(SHADER)
		_scenery = _instance("Passing", mesh, _mat)
	var lights_mesh := m.commit_lights()
	if lights_mesh != null:
		_lights_mat = _material(LIGHTS_SHADER)
		_lights = _instance("PassingLights", lights_mesh, _lights_mat)
	var strips: Array = params["ground"] if params["ground"] is Array else []
	for s: Variant in strips:
		if s is Dictionary:
			_strips.append(strip_with_defaults(s))
	if not _strips.is_empty():
		_ground_mat = ShaderMaterial.new()
		_ground_mat.shader = GROUND_SHADER
		_ground_mat.set_shader_parameter("noise_tex", SkySystem.noise_texture())
		_ground_mat.set_shader_parameter("nearest", EnvChecks.FLOW_NEAREST)
		_ground = MeshInstance3D.new()
		_ground.name = "PassingGround"
		_ground.mesh = _ground_mesh()
		_ground.material_override = _ground_mat
		_ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Not in the lightmap bake: it is lit in its shader, and its pattern moves.
		_ground.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		own(_ground)
	_uniforms()


## A band with its defaults filled in; `far` made at least `near`.
static func band_with_defaults(raw: Dictionary) -> Dictionary:
	# The schema asks for a shape ("required"); a caller that skips the schema gets the plainest one.
	var out := {"shape": "post", "side": "both", "near": 6.0, "far": 12.0, "count": 40, "length": 240.0,
			"seems": 1.0, "height": 0.0, "size": 1.0, "colour": null, "seed": 0, "presence": [[0.0, 1.0]]}
	out.merge(raw, true)
	out["far"] = maxf(float(out["far"]), float(out["near"]))
	return out


static func landmark_with_defaults(raw: Dictionary) -> Dictionary:
	# The schema asks for a shape and a place ("required"); without it, a lamp at the journey's start.
	var out := {"shape": "lamp", "at": 0.0, "side": "left", "distance": 8.0, "height": 0.0, "size": 1.0,
			"colour": null, "seed": 0}
	out.merge(raw, true)
	return out


static func strip_with_defaults(raw: Dictionary) -> Dictionary:
	# The schema asks for both edges ("required"); without it the strip has no width and nothing is drawn.
	var out := {"side": "both", "from": 0.0, "to": 0.0, "height_from": 0.0, "height_to": 0.0, "kind": "grass",
			"colour": null}
	out.merge(raw, true)
	return out


## -1 for left, 1 for right; both: both.
static func _sides(side: String) -> Array[float]:
	if side == "left":
		return [-1.0]
	if side == "right":
		return [1.0]
	return [-1.0, 1.0]


## A document's colour, or the fallback, as it is written. Every colour in these meshes goes in as written (sRGB),
## the document's and the shapes' own (a willow's bark, a roof, a lit window) alike, and the shaders take them all
## to linear light in one place (env_passing_place.gdshaderinc passing_colour()). Converting some here and not the
## others would draw a shape's own colours far lighter than the colour its document gave it.
static func _written(c: Variant, fallback: String) -> Color:
	var col := RoomSchemaRef.to_color(c if c != null else fallback)
	return Color(col.r, col.g, col.b, 1.0)


static func _default_presence(presence: Variant) -> bool:
	if not (presence is Array) or (presence as Array).size() != 1 or not (presence[0] is Array):
		return false
	var k: Array = presence[0]
	return k.size() == 2 and float(k[0]) == 0.0 and float(k[1]) == 1.0


func _build_band(m: ShapeMesh, b: int, band: Dictionary) -> void:
	var shape := str(band["shape"])
	var colour := _written(band["colour"], str(Shapes.COLOURS.get(shape, "#808080")))
	var seems := float(band["seems"])
	var pace := 1.0 / seems
	var near := float(band["near"])
	var far := float(band["far"])
	var height := float(band["height"])
	var size := float(band["size"])
	var seed := int(band["seed"])
	var all_show := _default_presence(band["presence"])
	var rng := RandomNumberGenerator.new()
	var loop: float
	if Shapes.SEGMENT.has(shape):
		var seg := float(Shapes.SEGMENT[shape])
		var n := floori(float(band["length"]) / seg)
		loop = n * seg
		for i in n:
			var threshold := 0.0 if all_show else (i + 0.5) / n
			for side in _sides(str(band["side"])):
				# Seeded as a scattered item is; the same on both sides (a row's shapes take nothing from it today).
				rng.seed = hash([seed, b, i])
				m.begin_item(side * near, height, i * seg, threshold, loop, pace, b, false)
				Shapes.draw(shape, m, rng, size, colour, {"along": i * seg, "length": loop, "side": int(side),
						"distance": near})
	else:
		var count := int(band["count"])
		loop = float(band["length"])
		for i in count:
			rng.seed = hash([seed, b, i])
			var along := rng.randf() * loop
			var across := lerpf(near, far, rng.randf())
			var side := 1.0
			match str(band["side"]):
				"left":
					side = -1.0
				"both":
					side = -1.0 if rng.randf() < 0.5 else 1.0
			var item_size := size * rng.randf_range(Shapes.VARY.x, Shapes.VARY.y)
			var threshold := 0.0 if all_show else (i + 0.5) / count
			m.begin_item(side * across, height, along, threshold, loop, pace, b, false)
			Shapes.draw(shape, m, rng, item_size, colour, {"along": along, "length": loop, "side": int(side),
					"distance": across})
	_bands.append(band)
	_loops.append(loop)
	_seems.append(seems)


func _build_landmark(m: ShapeMesh, k: int, lm: Dictionary) -> void:
	var shape := str(lm["shape"])
	var side := -1.0 if str(lm["side"]) == "left" else 1.0
	var distance := float(lm["distance"])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(lm["seed"]), k])
	m.begin_item(side * distance, float(lm["height"]), 0.0, 0.0, 0.0, 1.0, k, true)
	Shapes.draw(shape, m, rng, float(lm["size"]), _written(lm["colour"], str(Shapes.COLOURS.get(shape, "#808080"))),
			{"along": 0.0, "length": 0.0, "side": int(side), "distance": distance})
	_landmarks.append(lm)


## Each band's presence along the route: texel (x, b) is band b's at route fraction (x + 0.5) / PRESENCE_WIDTH,
## straight lines between its keys, held flat before the first and after the last.
func _presence() -> void:
	_presence_img = Image.create_empty(PRESENCE_WIDTH, maxi(_bands.size(), 1), false, Image.FORMAT_RF)
	_presence_img.fill(Color(1.0, 0.0, 0.0))
	for b in _bands.size():
		var keys: Array = []
		for k: Variant in _bands[b]["presence"]:
			if k is Array and (k as Array).size() == 2:
				keys.append(Vector2(float(k[0]), float(k[1])))
		# Keys given out of order are put in order: a document's list is not a trap.
		keys.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.x < q.x)
		for x in PRESENCE_WIDTH:
			_presence_img.set_pixel(x, b, Color(presence_at(keys, (x + 0.5) / PRESENCE_WIDTH), 0.0, 0.0))
	_presence_tex = ImageTexture.create_from_image(_presence_img)


## The presence at route fraction u of keys (Vector2s, sorted by x); 1 with none.
static func presence_at(keys: Array, u: float) -> float:
	if keys.is_empty():
		return 1.0
	if u <= (keys[0] as Vector2).x:
		return (keys[0] as Vector2).y
	for i in range(1, keys.size()):
		var a: Vector2 = keys[i - 1]
		var c: Vector2 = keys[i]
		if u <= c.x:
			return lerpf(a.y, c.y, (u - a.x) / (c.x - a.x)) if c.x > a.x else c.y
	return (keys[-1] as Vector2).y


func _material(shader: Shader) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("presence_tex", _presence_tex)
	mat.set_shader_parameter("band_count", float(maxi(_bands.size(), 1)))
	mat.set_shader_parameter("far", FAR)
	mat.set_shader_parameter("edge", EDGE)
	# What does not change while the room stands: how far a row's piece runs on from its foot, and the ground each
	# landmark stands on, which no band's item may stand on too (Shapes.clearing()).
	var extent := PackedFloat32Array()
	extent.resize(MAX_BANDS)
	for b in _bands.size():
		extent[b] = float(Shapes.SEGMENT.get(str(_bands[b]["shape"]), 0.0))
	mat.set_shader_parameter("band_extent", extent)
	var clear := PackedVector3Array()
	clear.resize(MAX_LANDMARKS)
	for k in _landmarks.size():
		var lm: Dictionary = _landmarks[k]
		clear[k] = Shapes.clearing(str(lm["shape"]), float(lm["size"]), -1.0 if str(lm["side"]) == "left" else 1.0,
				float(lm["distance"]))
	mat.set_shader_parameter("landmark_clear", clear)
	return mat


func _instance(node_name: String, mesh: ArrayMesh, mat: ShaderMaterial) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.custom_aabb = SCENERY_AABB
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# Its vertices lie about each item's foot and the shader carries them to their places: the checks that cast
	# rays must not read them as they are (env_checks.gd PLACED_IN_SHADER).
	mi.add_to_group(EnvChecks.PLACED_IN_SHADER)
	own(mi)
	return mi


## The ground: a quad a strip (two for side both), from GROUND_REACH astern to GROUND_REACH ahead, in the room's
## frame. COLOR its colour, UV2.x its kind's index, UV (across, along) in metres in the way's frame; normal up.
func _ground_mesh() -> ArrayMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	for s: Dictionary in _strips:
		var kind := str(s["kind"])
		var col := _written(s["colour"], str(KIND_COLOURS.get(kind, KIND_COLOURS["grass"])))
		var k := float(maxi(GROUND_KINDS.find(kind), 0))
		for side in _sides(str(s["side"])):
			var edges := [[float(s["from"]), float(s["height_from"])], [float(s["to"]), float(s["height_to"])]]
			var first := v.size()
			for corner: Array in [[0, -1.0], [1, -1.0], [1, 1.0], [0, 1.0]]:
				var a := side * float(edges[corner[0]][0])
				var y := float(edges[corner[0]][1])
				var t := float(corner[1]) * GROUND_REACH
				v.append(across_dir * a + Vector3.UP * y + along_dir * t)
				n.append(Vector3.UP)
				c.append(col)
				uv.append(Vector2(a, t))
				uv2.append(Vector2(k, 0.0))
			idx.append_array([first, first + 1, first + 2, first, first + 2, first + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_COLOR] = c
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# --- The journey ------------------------------------------------------------------------------------------------------

func tick(delta: float) -> void:
	# 1. The film.
	var pos := 0.0
	var dur := 0.0
	var main := main_node()
	if main == null:
		var snap: Variant = host.get("snapshot_override") if host != null else null
		if snap is Dictionary:
			pos = float((snap as Dictionary).get("position", 0.0))
			dur = float((snap as Dictionary).get("duration", 0.0))
	elif main.get("player") != null:
		var p: Node = main.get("player")
		pos = float(p.get_position())
		dur = float(p.get_duration())
	var state := str(host.timeline.state) if host != null and host.get("timeline") != null else ""
	# 2. The Motion setting (the host has already scaled params.speed by it).
	var m := clampf(float(host.setting("motion")) if host != null and host.setting("motion") != null else 1.0, 0.0,
			1.0)
	var speed := float(params["speed"])
	if m >= 0.01:
		own_speed = speed / m
	var cruise := speed if m >= EnvChecks.FLOW_MOTION_FLOOR else 0.0
	_cruise = cruise
	# 3. The route: the film's length at this speed, less what the slowing for the end saves.
	var route := 0.0
	if cruise > 0.0 and dur > 0.0 and bool(params["arrive"]):
		route = maxf(cruise * dur - cruise * cruise / (2.0 * BRAKE), 0.0)
	if cruise > 0.0:
		route_shown = route
	var target := cruise * pos
	if route > 0.0:
		target = minf(target, route)
	var going := state in ["starting", "playing", "credits"]
	# 4. The first tick: the cabin is where the film is.
	if not _placed:
		travel = target
		speed_now = cruise if going else 0.0
		_placed = true
	# 5. Too far from the film: go dark and move.
	if cruise > 0.0 and _blink == 0 and absf(target - travel) > maxf(cruise * 60.0, 30.0):
		_blink = 1
	# 6. The speed it wants.
	going = going or (state == "ended" and route > 0.0)
	var want := cruise if going else 0.0
	if want > 0.0 and state != "ended":
		want *= clampf(1.0 + (target - travel) / maxf(cruise * 20.0, 5.0), 1.0 - CATCH_UP, 1.0 + CATCH_UP)
	if route > 0.0:
		want = minf(want, sqrt(maxf(2.0 * BRAKE * (route - travel), 0.0)))
	# 7. Never faster a change than the limit; never back.
	speed_now = move_toward(speed_now, want, EnvChecks.FLOW_ACCEL * delta)
	travel += maxf(speed_now, 0.0) * delta
	if route > 0.0:
		travel = minf(travel, route)
	# 8. The blink.
	if _blink == 1:
		dark = minf(dark + delta / BLINK_OUT, 1.0)
		if dark >= 1.0:
			travel = target
			# The speed after the jump: what it wants at the new place, without the catch-up (it is where the film
			# is), and slowed for the route's end from there, so a jump to the end leaves it stopped at the wharf.
			var plain := cruise if going else 0.0
			if route > 0.0:
				plain = minf(plain, sqrt(maxf(2.0 * BRAKE * (route - travel), 0.0)))
			speed_now = plain
			_blink = 2
	elif _blink == 2:
		dark = maxf(dark - delta / BLINK_IN, 0.0)
		if dark <= 0.0:
			_blink = 0
	# 9. The channels.
	if host != null:
		var values: Dictionary = host.signals.values
		values["journey.speed"] = clampf(speed_now / maxf(own_speed, 0.001), 0.0, 1.0)
		values["journey.progress"] = travel / route_shown if route_shown > 0.0 \
				else EnvSignals.progress(travel / maxf(own_speed, 0.001), 0.0)
	# 10. The shaders.
	_uniforms()


## The film's position jumped: go dark, move, come back (while the journey goes).
func on_seek(_from: float, _to: float) -> void:
	if _cruise > 0.0 and _blink != 1:
		_blink = 1


func route_length() -> float:
	return route_shown


func blinking() -> bool:
	return _blink != 0


# --- The shaders' uniforms --------------------------------------------------------------------------------------------

func _uniforms() -> void:
	var top: Color
	var low: Color
	if _sky != null and is_instance_valid(_sky):
		var l: Dictionary = _sky.call("sky_light")
		top = l["zenith"]
		low = l["horizon"]
	else:
		top = color_param("night")
		low = top
	var shown := 1.0 - dark
	var phase := PackedFloat32Array()
	phase.resize(MAX_BANDS)
	for b in _loops.size():
		phase[b] = fposmod(travel / _seems[b], _loops[b]) if _loops[b] > 0.0 else 0.0
	var landmark_along := PackedFloat32Array()
	landmark_along.resize(MAX_LANDMARKS)
	landmark_along.fill(1e6)
	for k in _landmarks.size():
		var at := float(_landmarks[k]["at"])
		if route_shown > 0.0:
			landmark_along[k] = at * route_shown - travel
		elif at == 0.0:
			landmark_along[k] = -travel
	for mat: ShaderMaterial in [_mat, _lights_mat, _ground_mat]:
		if mat == null:
			continue
		mat.set_shader_parameter("along_dir", along_dir)
		mat.set_shader_parameter("across_dir", across_dir)
		mat.set_shader_parameter("shown", shown)
		mat.set_shader_parameter("light", float(params["light"]))
		mat.set_shader_parameter("sky_top", top)
		mat.set_shader_parameter("sky_low", low)
		mat.set_shader_parameter("mist", float(params["mist"]))
		mat.set_shader_parameter("mist_colour", color_param("mist_colour"))
		mat.set_shader_parameter("glow", float(params["glow"]))
		mat.set_shader_parameter("glow_colour", color_param("glow_colour"))
		mat.set_shader_parameter("glow_reach", float(params["glow_reach"]))
		mat.set_shader_parameter("glow_half_length", float(params["glow_half_length"]))
		mat.set_shader_parameter("spill", float(params["spill"]))
	for mat: ShaderMaterial in [_mat, _lights_mat]:
		if mat == null:
			continue
		mat.set_shader_parameter("phase", phase)
		mat.set_shader_parameter("landmark_along", landmark_along)
		mat.set_shader_parameter("travel", travel)
		mat.set_shader_parameter("route", route_shown)
		mat.set_shader_parameter("endless_half", maxf(own_speed * EnvSignals.ENDLESS_HALF_MINUTES * 60.0, 1.0))
	if _mat != null:
		_mat.set_shader_parameter("windows", float(params["windows"]))
	if _lights_mat != null:
		_lights_mat.set_shader_parameter("lights", float(params["lights"]))
	if _ground_mat != null:
		_ground_mat.set_shader_parameter("ground_phase", fposmod(travel, GROUND_PERIOD))
		_ground_mat.set_shader_parameter("far", FAR)


## The materials (tests): "Passing", "PassingLights", "PassingGround"; null when not made.
func material_of(node_name: String) -> ShaderMaterial:
	match node_name:
		"Passing":
			return _mat
		"PassingLights":
			return _lights_mat
		"PassingGround":
			return _ground_mat
	return null


## The presence of each band along the route (row b: band b), as the shaders read it.
func presence_image() -> Image:
	return _presence_img


func presence_texture() -> ImageTexture:
	return _presence_tex


# --- Comfort ----------------------------------------------------------------------------------------------------------

## What is wrong with these parameters for comfort (env_checks.gd FLOW_*), judged from them alone: a band or a
## landmark any part of which comes nearer the line the eyes go along than FLOW_NEAREST, or crosses the eye faster
## than FLOW_MAX_DEG there, at the fastest the journey goes (its speed and the catch-up). "Any part": a shape's
## crown, shoots, eaves and arm are measured (Shapes.nearest()), at the largest the band draws it; where its foot
## stands is not how near it comes. Ground nearer than FLOW_NEAREST is fine: its shader holds its pattern still.
static func comfort_for(p: Dictionary) -> Array:
	var out: Array = []
	var top := float(p.get("speed", 1.0)) * (1.0 + CATCH_UP)
	var bands: Array = p.get("bands", []) if p.get("bands") is Array else []
	for i in bands.size():
		if bands[i] is Dictionary:
			var band := band_with_defaults(bands[i])
			var shape := str(band["shape"])
			var largest := float(band["size"]) * (1.0 if Shapes.SEGMENT.has(shape) else Shapes.VARY.y)
			_judge(out, "band %d (%s)" % [i, shape], Shapes.nearest(shape, largest, float(band["near"]),
					float(band["height"]), EnvChecks.EYE_HEIGHT), float(band["seems"]), top)
	var landmarks: Array = p.get("landmarks", []) if p.get("landmarks") is Array else []
	for k in landmarks.size():
		if landmarks[k] is Dictionary:
			var lm := landmark_with_defaults(landmarks[k])
			var shape := str(lm["shape"])
			_judge(out, "landmark %d (%s)" % [k, shape], Shapes.nearest(shape, float(lm["size"]),
					float(lm["distance"]), float(lm["height"]), EnvChecks.EYE_HEIGHT), 1.0, top)
	return out


static func _judge(out: Array, what: String, nearest: float, seems: float, top: float) -> void:
	if nearest < EnvChecks.FLOW_NEAREST:
		out.append("%s: comes within %.1f m of the line the eyes go along, nearer than %s" % [what, nearest,
				EnvChecks.FLOW_NEAREST])
	var rate := rad_to_deg(top / maxf(seems, 0.001) / maxf(nearest, 0.001))
	if rate > EnvChecks.FLOW_MAX_DEG:
		out.append("%s: crosses the eye at %.1f degrees a second at its nearest, over %s (slower, or further off)"
				% [what, rate, EnvChecks.FLOW_MAX_DEG])


## Where moving scenery can be, as boxes in the room's frame (env_checks.gd flow_clear()): each band's side from
## where its largest item reaches to (its near less Shapes.REACH) to its far across, half its loop (at most GROUND_REACH) each way along, from 2 m under its feet to 30 m over; each
## landmark 15 m either side of its distance (never under FLOW_NEAREST); each ground strip's part beyond FLOW_NEAREST.
func flow_volumes() -> Array:
	var out: Array = []
	for b in _bands.size():
		var band: Dictionary = _bands[b]
		var reach := minf(_loops[b] * 0.5, GROUND_REACH)
		var h := float(band["height"])
		for side in _sides(str(band["side"])):
			out.append(_volume(side, maxf(float(band["near"]) - _reach(band), 0.0), float(band["far"]), reach,
					h - 2.0, h + 30.0))
	for lm: Dictionary in _landmarks:
		var d := float(lm["distance"])
		var h := float(lm["height"])
		# A landmark comes by along the whole way that is drawn.
		out.append(_volume(-1.0 if str(lm["side"]) == "left" else 1.0, maxf(d - 15.0, EnvChecks.FLOW_NEAREST),
				d + 15.0, GROUND_REACH, h - 2.0, h + 30.0))
	for s: Dictionary in _strips:
		var from := maxf(minf(float(s["from"]), float(s["to"])), EnvChecks.FLOW_NEAREST)
		var to := maxf(float(s["from"]), float(s["to"]))
		if to <= from:
			continue
		var lo := minf(float(s["height_from"]), float(s["height_to"])) - 0.1
		var hi := maxf(float(s["height_from"]), float(s["height_to"])) + 0.1
		for side in _sides(str(s["side"])):
			out.append(_volume(side, from, to, GROUND_REACH, lo, hi))
	return out


## How far towards the way a band's largest item reaches from its foot (Shapes.REACH).
static func _reach(band: Dictionary) -> float:
	var shape := str(band["shape"])
	if not Shapes.REACH.has(shape):
		return 0.0
	var wide: Array = Shapes.REACH[shape]["wide"]
	return float(wide[0]) + float(wide[1]) * float(band["size"]) * (1.0 if Shapes.SEGMENT.has(shape)
			else Shapes.VARY.y)


func _volume(side: float, a0: float, a1: float, reach: float, y0: float, y1: float) -> AABB:
	var p0 := across_dir * (side * a0) + along_dir * -reach + Vector3.UP * y0
	var p1 := across_dir * (side * a1) + along_dir * reach + Vector3.UP * y1
	return AABB(p0, Vector3.ZERO).expand(p1)
