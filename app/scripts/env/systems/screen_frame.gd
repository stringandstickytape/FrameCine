extends "res://scripts/env/systems/env_system.gd"

## The screen's frame in the room (docs/environments.md, "The systems"; the first part of screen presentation): the
## black masking round the picture, following the screen as it moves, and the projector's beam from a lens to the
## screen's corners (room_beam.gdshader, additive), shown while a flat film plays and the projector feature's own beam
## does not. Moved here from environments/cinema.gd.
##   ScreenBorder   the masking (a quad a little bigger than the screen, just behind it)
##   Beam/Cone      the beam: four sides from the lens to the screen's edges (UV.y along it, 0 at the lens)

const ENV_SHADER := preload("res://shaders/env_unlit.gdshader")
const BEAM_SHADER := preload("res://shaders/room_beam.gdshader")
## Nodes the sight-line check looks through (env_checks.gd).
const SEE_THROUGH := "env_see_through"


static func spec() -> Dictionary:
	return {
		"kind": "screen",
		"description": "The black masking round the screen (it follows the screen) and the projector's beam from a "
				+ "lens to the screen's corners while a flat film plays.",
		"params": {
			"masking": {"type": "bool", "default": true, "description": "the black masking round the picture"},
			"margin": {"type": "float", "min": 0.0, "max": 3.0, "default": 0.5,
					"description": "metres the masking reaches past the picture (both sides together)"},
			"beam": {"type": "bool", "default": true, "description": "the projector's beam through the room"},
			"lens": {"type": "vec3", "min": -200.0, "max": 200.0, "default": [0.0, 3.45, 6.15],
					"description": "the beam's lens, in the room's frame"},
		},
		"cost": {"draws": 2, "triangles": 16, "lights": 0, "particles": 0, "texture_mb": 0},
	}


var _border: MeshInstance3D
var _beam_root: Node3D
var _beam: MeshInstance3D
var _screen_local := Transform3D()
var _screen_size := Vector2.ZERO
var _beam_key := ""
var _lens := Vector3.ZERO


func setup() -> void:
	var lv: Array = params["lens"]
	_lens = Vector3(float(lv[0]), float(lv[1]), float(lv[2]))
	if bool(params["beam"]):
		_beam_root = Node3D.new()
		_beam_root.name = "Beam"
		_beam_root.position = _lens
		own(_beam_root)
		_beam = MeshInstance3D.new()
		_beam.name = "Cone"
		var m := ShaderMaterial.new()
		m.shader = BEAM_SHADER
		m.set_shader_parameter("house_reference", float(room.get("ambient_level")))
		_beam.material_override = m
		_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_beam.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		_beam.add_to_group(SEE_THROUGH)
		_beam_root.add_child(_beam)
	if bool(params["masking"]):
		var border := QuadMesh.new()
		var bm := ShaderMaterial.new()
		bm.shader = ENV_SHADER
		bm.set_shader_parameter("albedo", Color.BLACK)
		bm.set_shader_parameter("spill", 0.0)
		border.material = bm
		_border = MeshInstance3D.new()
		_border.name = "ScreenBorder"
		_border.mesh = border
		_border.transform = room.call("get_screen_anchor")
		_border.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_border.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		_border.add_to_group(SEE_THROUGH)
		own(_border)


func on_screen_changed(local: Transform3D, size: Vector2) -> void:
	_screen_local = local
	_screen_size = size
	if size == Vector2.ZERO:
		return
	if _border != null:
		(_border.mesh as QuadMesh).size = size + Vector2.ONE * float(params["margin"])
		_border.transform = local.translated_local(Vector3(0, 0, -0.03))
	if _beam != null:
		_shape_beam(local)


## The beam: four sides from the lens to the screen's edges (UV.y along it, 0 at the lens; UV2.x across a side).
func _shape_beam(screen: Transform3D) -> void:
	var corners: Array[Vector3] = []
	for c: Vector2 in [Vector2(-0.5, 0.5), Vector2(0.5, 0.5), Vector2(0.5, -0.5), Vector2(-0.5, -0.5)]:
		corners.append(screen * Vector3(c.x * _screen_size.x, c.y * _screen_size.y, 0.0) - _lens)
	var key := str(corners)
	if key == _beam_key:
		return
	_beam_key = key
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 4:
		var p := corners[i]
		var q := corners[(i + 1) % 4]
		for v: Array in [[Vector3.ZERO, 0.0, 0.5], [p, 1.0, 0.0], [q, 1.0, 1.0]]:
			st.set_uv(Vector2(0.0, v[1]))
			st.set_uv2(Vector2(v[2], 0.0))
			st.add_vertex(v[0])
	_beam.mesh = st.commit()


func tick(_delta: float) -> void:
	if _beam_root == null:
		return
	var on := true
	var main := main_node()
	if main != null:
		on = main.player.is_playing() and main.screen.is_shown() and not main.mode.is_spherical()
		var projector: Node = main.features.get("projector") if main.get("features") != null else null
		if projector != null and projector.beam_applies():
			on = false
	_beam_root.visible = on
