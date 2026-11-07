extends "res://scripts/env/systems/env_system.gd"

## The light system (docs/environments.md, "The systems"): how a built room is lit, without a live light. The screen is
## the main light: every surface takes the film's spill. Builders ask it for their materials and lamps:
##
##   library(id, colour, options, instanced) -> ShaderMaterial   a library material on the house shader
##                (MaterialLibrary option "house": the maps' colour, normals and roughness, scaled by the house
##                lights' level, plus as emission a warm hemisphere fill, the film's spill and, until a lightmap is
##                baked, stand-in lamps). instanced: a MultiMesh's (never baked: it keeps its fill and lamps)
##   lamp_material(colour, energy, follows_house, group) -> ShaderMaterial   a light source's own glow
##                (room_lamp.gdshader: emission only, so a bake takes it as an emitter); group: house, steps, stage,
##                signs, booth, accent; the live parameters scale each group
##   add_lamp(position, colour_energy, cone_cos)   a stand-in lamp (a soft point light in the shader, no shadows)
##   add_bake_light(light)        a real light for the lightmap bake only (hidden: LightmapGI bakes hidden lights)
## The bake (scripts/env/room_bake.gd) reaches it through the room: bake_lights(), set_baking(on), set_baked(on);
## a LightmapGI added to the room is noticed by itself. The house level scales a lightmap too (it is in ALBEDO), so the
## house lights still go down when the film starts. Moved here from environments/cinema.gd (the room as code).

const MaterialLibrary := preload("res://scripts/env/material_library.gd")
const LAMP_SHADER := preload("res://shaders/room_lamp.gdshader")
## The shader takes at most this many stand-in lamps.
const MAX_LAMPS := 8

static func spec() -> Dictionary:
	return {
		"kind": "light",
		"description": "How a built room is lit without a live light: library materials on the house shader (a warm "
				+ "fill, the film's spill, stand-in lamps until a lightmap is baked on the headset), the lamps' own "
				+ "glow by group, and the hidden lights the bake uses.",
		"params": {
			"fill_top": {"type": "vec3", "min": 0.0, "max": 4.0, "default": [1.1, 0.88, 0.7],
					"description": "the hemisphere fill from above (the house lights' bounce before a bake), linear RGB"},
			"fill_bottom": {"type": "vec3", "min": 0.0, "max": 4.0, "default": [0.32, 0.25, 0.21],
					"description": "the fill from below"},
			"baked_fill": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.15,
					"description": "how much of the fill stays once a lightmap is on"},
			"spill": {"type": "float", "min": 0.0, "max": 6.0, "default": 3.0,
					"description": "how much the surfaces catch the screen's light (the unlit rooms' is 1)"},
			"lamp_colour": {"type": "color", "default": [1.0, 0.68, 0.42],
					"description": "the stand-in lamps' colour"},
			"lamp_energy": {"type": "float", "min": 0.0, "max": 8.0, "default": 2.6,
					"description": "the stand-in lamps' energy"},
			"lamp_range": {"type": "float", "min": 0.5, "max": 20.0, "default": 6.0,
					"description": "metres a stand-in lamp reaches"},
			"lamp_cone_deg": {"type": "float", "min": 5.0, "max": 90.0, "default": 42.0,
					"description": "the stand-in lamps' cones' half angle (up and down)"},
			"house_lamps": {"type": "float", "min": 0.0, "max": 1.0, "default": 1.0, "live": true, "brightness": true,
					"description": "the house lamps' glow (sconces, ceiling cans): the ritual takes it down"},
			"step_lights": {"type": "float", "min": 0.0, "max": 1.0, "default": 1.0, "live": true, "brightness": true,
					"description": "the aisle steps' and the stage's glow"},
			"signs": {"type": "float", "min": 0.0, "max": 1.0, "default": 1.0, "live": true, "brightness": true,
					"description": "the exit signs' and the booth's glow"},
			"accent": {"type": "float", "min": 0.0, "max": 2.0, "default": 1.0, "live": true, "brightness": true,
					"description": "accent lamps' glow (group accent)"},
			"dimmed_level": {"type": "float", "min": -1.0, "max": 1.0, "default": -1.0, "live": true,
					"brightness": true, "description": "the room light's level while the film plays (light follows "
					+ "playback); -1: the app's own (the Room tab's Dimmed to)"},
			"bake": {"type": "bool", "default": true,
					"description": "the room is lit by a lightmap baked on the headset (its hidden bake lights)"},
		},
		"provides": ["bake"],
		"cost": {"draws": 0, "triangles": 0, "lights": 0, "particles": 0, "texture_mb": 0},
	}


## Each group's live parameter.
const GROUPS := {"house": "house_lamps", "steps": "step_lights", "stage": "step_lights", "signs": "signs",
		"booth": "signs", "accent": "accent"}

var _static_materials: Array[ShaderMaterial] = []
var _seat_materials: Array[ShaderMaterial] = []
## [material, energy as designed, group]
var _lamp_materials: Array = []
## [position (room frame), colour x energy, cone cosine]
var _lamps: Array = []
var _bake_root: Node3D
var _baked := false
var _baking := false
var _lightmap: Node
var _lightmap_seen := false


func setup() -> void:
	_bake_root = Node3D.new()
	_bake_root.name = "BakeLights"
	own(_bake_root)
	room.child_entered_tree.connect(_on_child_entered)
	room.child_exiting_tree.connect(_on_child_exiting)


func _fill_top() -> Color:
	var v: Array = params["fill_top"]
	return Color(v[0], v[1], v[2])


func _fill_bottom() -> Color:
	var v: Array = params["fill_bottom"]
	return Color(v[0], v[1], v[2])


## A library material on the house shader, this room's own copy (its lamps and bake state are set on it).
func library(material_id: String, colour: Color, options := {}, instanced := false) -> ShaderMaterial:
	var o := options.duplicate()
	o.merge({"colour": colour, "spill": float(params["spill"]), "house": {"sky_top": _fill_top(),
			"sky_bottom": _fill_bottom()}})
	var shared := MaterialLibrary.get_material(material_id, o)
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
	m.set_shader_parameter("house_reference", float(room.get("ambient_level")))
	m.set_shader_parameter("contact_strength", 0.0)
	(_seat_materials if instanced else _static_materials).append(m)
	return m


## A material parameter ({library, color, tiling, ...}) as a house material.
func from_param(m: Dictionary, instanced := false) -> ShaderMaterial:
	var o := {}
	for k: String in ["tiling", "pleats", "pleat_depth", "spill"]:
		if m.has(k):
			o[k] = float(m[k])
	if m.has("tint"):
		o["tint"] = RoomSchemaRef.to_color(m["tint"])
	return library(str(m.get("library", "felt")), RoomSchemaRef.to_color(m.get("color", "#808080")), o, instanced)


func _set_fill(m: ShaderMaterial, k: float) -> void:
	var t := _fill_top()
	var b := _fill_bottom()
	m.set_shader_parameter("sky_top", Vector3(t.r, t.g, t.b) * k)
	m.set_shader_parameter("sky_bottom", Vector3(b.r, b.g, b.b) * k)


func lamp_material(colour: Color, energy: float, follows_house: float, group := "accent") -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = LAMP_SHADER
	m.set_shader_parameter("colour", colour)
	m.set_shader_parameter("follows_house", follows_house)
	m.set_shader_parameter("house_reference", float(room.get("ambient_level")))
	_lamp_materials.append([m, energy, group])
	m.set_shader_parameter("energy", energy * _group_level(group))
	return m


func _group_level(group: String) -> float:
	return float(params.get(GROUPS.get(group, "accent"), 1.0))


## A stand-in lamp until a lightmap is baked (the shader's soft point lights; MAX_LAMPS at most).
func add_lamp(at: Vector3, colour_energy: Color, cone_cos: float) -> void:
	if _lamps.size() < MAX_LAMPS:
		_lamps.append([at, colour_energy, cone_cos])


func lamp_colour() -> Color:
	return color_param("lamp_colour")


## A real light for the bake only: static, with shadows, hidden.
func add_bake_light(l: Light3D) -> void:
	l.light_bake_mode = Light3D.BAKE_STATIC if bool(params["bake"]) else Light3D.BAKE_DISABLED
	l.shadow_enabled = true
	l.visible = false
	_bake_root.add_child(l)


func _param_changed(param: String, _value: Variant) -> void:
	if param in GROUPS.values():
		for e: Array in _lamp_materials:
			(e[0] as ShaderMaterial).set_shader_parameter("energy", float(e[1]) * _group_level(str(e[2])))


## The lamps' glow by group, as shown now (tests).
func group_energy(group: String) -> float:
	for e: Array in _lamp_materials:
		if e[2] == group:
			return float((e[0] as ShaderMaterial).get_shader_parameter("energy"))
	return 0.0


# --- Bake hooks --------------------------------------------------------------------------------------------------------

func bake_lights() -> Node3D:
	return _bake_root


## While LightmapGI.bake() renders the surfaces: their colour at the designed level only, the lamps' glow as it is.
func set_baking(on: bool) -> void:
	_baking = on
	for m in _static_materials + _seat_materials:
		m.set_shader_parameter("bake_pass", on)
	for e: Array in _lamp_materials:
		(e[0] as ShaderMaterial).set_shader_parameter("bake_pass", on)


## A lightmap is on the room (or gone again): the static surfaces drop the stand-in lamps and most of the fill.
func set_baked(on: bool) -> void:
	_baked = on
	place_lamps()
	for m in _static_materials:
		_set_fill(m, float(params["baked_fill"]) if on else 1.0)


func is_baked() -> bool:
	return _baked


func _on_child_entered(n: Node) -> void:
	if n is LightmapGI:
		_lightmap = n


func _on_child_exiting(n: Node) -> void:
	if n == _lightmap:
		_lightmap = null


## The stand-in lamps' places in the world (the room moves when a seat is chosen); none on baked surfaces.
func place_lamps() -> void:
	if not room.is_inside_tree():
		return
	var pos := PackedVector4Array()
	var col := PackedVector4Array()
	var reach := float(params["lamp_range"])
	for l: Array in _lamps:
		var p: Vector3 = room.global_transform * Vector3(l[0])
		var c: Color = l[1]
		pos.append(Vector4(p.x, p.y, p.z, reach))
		col.append(Vector4(c.r, c.g, c.b, float(l[2])))
	while pos.size() < MAX_LAMPS:
		pos.append(Vector4.ZERO)
		col.append(Vector4.ZERO)
	for m in _static_materials + _seat_materials:
		var live := not (_baked and m in _static_materials)
		m.set_shader_parameter("lamp_position", pos)
		m.set_shader_parameter("lamp_colour", col)
		m.set_shader_parameter("lamp_count", _lamps.size() if live else 0)


func on_room_moved() -> void:
	place_lamps()


func tick(_delta: float) -> void:
	var has := _lightmap != null and (_lightmap as LightmapGI).light_data != null
	if has != _lightmap_seen:
		_lightmap_seen = has
		set_baked(has)


func static_materials() -> Array[ShaderMaterial]:
	return _static_materials


func seat_materials() -> Array[ShaderMaterial]:
	return _seat_materials


func lamp_count() -> int:
	return _lamps.size()
