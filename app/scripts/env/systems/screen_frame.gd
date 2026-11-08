extends "res://scripts/env/systems/env_system.gd"

## The screen's frame in the room (docs/environments.md, "The systems"; the first part of screen presentation): the
## black masking round the picture, following the screen as it moves, and the projector's beam from a lens to the
## screen's corners (room_beam.gdshader, additive), shown while a flat film plays and the projector feature's own beam
## does not. Moved here from environments/cinema.gd.
##   ScreenBorder   the masking (a quad a little bigger than the screen, just behind it)
##   Beam/Cone      the beam: four sides from the lens to the screen's edges (UV.y along it, 0 at the lens)

const ENV_SHADER := preload("res://shaders/env_unlit.gdshader")
const BEAM_SHADER := preload("res://shaders/room_beam.gdshader")
const VOLUME_SHADER := preload("res://shaders/env_beam_volume.gdshader")
const SkySystem := preload("res://scripts/env/systems/sky.gd")
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
			# Since 2026-11-08 (the drive-in, where the beam passes over the viewer): "flat", as before, is the
			# default.
			"beam_style": {"type": "enum", "values": ["flat", "volume"], "default": "flat",
					"description": "flat: the beam's sides, soft-edged (a hall's beam seen from the side); volume: the "
					+ "light along each view ray's path through it, brightest by the lens, in the picture's colours, "
					+ "a slow haze drifting in it (a beam passing overhead, seen from under it)"},
			"beam_strength": {"type": "float", "min": 0.0, "max": 0.05, "default": 0.004, "brightness": true,
					"description": "volume: how much the air scatters the beam's light"},
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
var _haze_time := 0.0


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
		if str(params["beam_style"]) == "volume":
			m.shader = VOLUME_SHADER
			m.set_shader_parameter("strength", float(params["beam_strength"]))
			m.set_shader_parameter("haze", SkySystem.noise_texture())
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
	if str(params["beam_style"]) == "volume":
		_shape_volume(corners)
		return
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


## The volume beam: the closed pyramid (its sides and the screen's end, each facing out, so the far side is drawn
## once a pixel) and its planes for the shader.
func _shape_volume(corners: Array[Vector3]) -> void:
	var centre := (corners[0] + corners[1] + corners[2] + corners[3]) * 0.25
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris: Array = []
	var m := _beam.material_override as ShaderMaterial
	for i in 4:
		var p := corners[i]
		var q := corners[(i + 1) % 4]
		var n := p.cross(q).normalized()
		if n.dot(centre) > 0.0:
			n = -n
		m.set_shader_parameter("side_n%d" % i, n)
		tris.append([Vector3.ZERO, p, q, n])
	var axis := centre.normalized()
	tris.append([corners[0], corners[1], corners[2], axis])
	tris.append([corners[0], corners[2], corners[3], axis])
	for t: Array in tris:
		var a: Vector3 = t[0]
		var b: Vector3 = t[1]
		var c: Vector3 = t[2]
		var n: Vector3 = t[3]
		var order := [a, b, c] if (c - a).cross(b - a).dot(n) >= 0.0 else [a, c, b]
		for v: Vector3 in order:
			st.set_normal(n)
			st.set_uv(Vector2(0.0, v.length() / centre.length()))
			st.add_vertex(v)
	_beam.mesh = st.commit()
	var far_n := (corners[1] - corners[0]).cross(corners[3] - corners[0]).normalized()
	if far_n.dot(axis) < 0.0:
		far_n = -far_n
	m.set_shader_parameter("far_plane", Plane(far_n, far_n.dot(corners[0])))
	m.set_shader_parameter("axis", axis)
	m.set_shader_parameter("axis_len", centre.length())
	m.set_shader_parameter("right", (corners[1] - corners[0]).normalized())
	m.set_shader_parameter("half_w", corners[0].distance_to(corners[1]) * 0.5)


func tick(delta: float) -> void:
	if _beam_root == null:
		return
	if str(params["beam_style"]) == "volume":
		_haze_time += delta
		(_beam.material_override as ShaderMaterial).set_shader_parameter("haze_time", _haze_time)
	var on := true
	var main := main_node()
	if main != null:
		on = main.player.is_playing() and main.screen.is_shown() and not main.mode.is_spherical()
		var projector: Node = main.features.get("projector") if main.get("features") != null else null
		if projector != null and projector.beam_applies():
			on = false
	_beam_root.visible = on
