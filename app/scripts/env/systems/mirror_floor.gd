extends "res://scripts/env/systems/env_system.gd"

## A mirror-black floor (docs/environments.md, "The Void"): a wide unlit plane at the floor that the floor reflection
## (scripts/env/floor_reflection.gd) shows the film in, and a ripple where the viewer moves: when the head goes faster
## than MOVE_SPEED over the floor, a faint ring spreads from under it (at most one every RIPPLE_GAP seconds, four at a
## time). Its strength is the live parameter ripple (the Void's setting). shaders/env_ripple_floor.gdshader draws it.

const SHADER := preload("res://shaders/env_ripple_floor.gdshader")
## Metres a second of head movement over the floor that starts a ripple.
const MOVE_SPEED := 0.15
const RIPPLE_GAP := 0.8
const RIPPLES := 4


static func spec() -> Dictionary:
	return {
		"kind": "builder",
		"description": "A mirror-black floor that takes the film's reflection, with a faint ripple spreading from "
				+ "under the viewer when the head moves.",
		"params": {
			"colour": {"type": "color", "default": [0.01, 0.01, 0.012], "description": "the floor's black"},
			"size": {"type": "float", "min": 2.0, "max": 200.0, "default": 60.0, "description": "metres across"},
			"floor_y": {"type": "float", "min": -10.0, "max": 10.0, "default": 0.0, "description": "the floor's height"},
			"reflect": {"type": "bool", "default": true, "description": "the film's reflection on the floor, by default"},
			"ripple": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.5, "live": true, "brightness": true,
					"description": "how strong a ripple is; 0: none"},
			"ripple_speed": {"type": "float", "min": 0.1, "max": 3.0, "default": 0.6,
					"description": "metres a second the ring spreads"},
			"ripple_seconds": {"type": "float", "min": 0.5, "max": 8.0, "default": 2.5,
					"description": "how long a ring lasts"},
			"ring_colour": {"type": "color", "default": [0.55, 0.6, 0.7], "live": true,
					"description": "the ring's tint (it can follow film.colour)"},
		},
		"cost": {"draws": 1, "triangles": 2, "lights": 0, "particles": 0, "texture_mb": 0},
	}


var _floor: MeshInstance3D
var _material: ShaderMaterial
## [centre (world), age, strength] per ring.
var _rings: Array = []
var _last_head := Vector3.INF
var _since := 10.0
## Tests: where the head is (world), instead of the camera.
var head_override: Variant = null
var started := 0


func setup() -> void:
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("albedo", color_param("colour"))
	_material.set_shader_parameter("ring_colour", color_param("ring_colour"))
	_material.set_shader_parameter("speed", float(params["ripple_speed"]))
	_material.set_shader_parameter("life", float(params["ripple_seconds"]))
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * float(params["size"])
	_floor = MeshInstance3D.new()
	_floor.name = "MirrorFloor"
	_floor.mesh = plane
	_floor.material_override = _material
	_floor.position = Vector3(0.0, float(params["floor_y"]), 0.0)
	_floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_floor.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# Under an assistant's room (the Void as its base) the room's own floor is the floor: no second one under it.
	_floor.visible = not bool(room.call("is_base")) if room.has_method("is_base") else true
	own(_floor)
	room.set("reflection_floor_y", float(params["floor_y"]))
	room.set("reflection_default", bool(params["reflect"]))
	_upload()


func _param_changed(param: String, _value: Variant) -> void:
	if param == "ring_colour" and _material != null:
		_material.set_shader_parameter("ring_colour", color_param("ring_colour"))


func _head() -> Variant:
	if head_override != null:
		return head_override
	var main := main_node()
	if main != null and main.get("camera") != null:
		return (main.camera as Node3D).global_position
	return null


func tick(delta: float) -> void:
	_since += delta
	for r: Array in _rings:
		r[1] = float(r[1]) + delta
	_rings = _rings.filter(func(r: Array) -> bool: return float(r[1]) < float(params["ripple_seconds"]))
	var head: Variant = _head()
	if head is Vector3 and delta > 0.0:
		var h: Vector3 = head
		if _last_head != Vector3.INF:
			var moved := Vector2(h.x - _last_head.x, h.z - _last_head.z).length() / delta
			if moved > MOVE_SPEED and _since >= RIPPLE_GAP and float(params["ripple"]) > 0.0:
				_since = 0.0
				started += 1
				_rings.append([Vector3(h.x, 0.0, h.z), 0.0, 1.0])
				while _rings.size() > RIPPLES:
					_rings.pop_front()
		_last_head = h
	_upload()


func _upload() -> void:
	var rs: Array[Vector4] = []
	var ages := PackedFloat32Array()
	var k := float(params["ripple"])
	for i in RIPPLES:
		if i < _rings.size():
			var c: Vector3 = _rings[i][0]
			rs.append(Vector4(c.x, 0.0, c.z, float(_rings[i][2]) * k))
			ages.append(float(_rings[i][1]))
		else:
			rs.append(Vector4.ZERO)
			ages.append(0.0)
	_material.set_shader_parameter("ripples", rs)
	_material.set_shader_parameter("ripple_age", ages)


## The rings now: [[centre, age, strength x ripple]] (tests).
func rings() -> Array:
	return _rings.map(func(r: Array) -> Array: return [r[0], r[1], float(r[2]) * float(params["ripple"])])


func material() -> ShaderMaterial:
	return _material
