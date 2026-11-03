extends Node3D

## Projector mode (ideas #92): the feel of a film projector, all off by default.
##   beam    a faint light cone from a projector behind and above the seat to the flat screen's corners, with dust
##           motes drifting in it (GPU particles emitted at random points inside the cone)
##   grain   film grain on the picture (0..1), a new pattern every frame (video_common.gdshaderinc's film_grain)
##   weave   gate weave (0..1): the picture drifts by a fraction of a percent, unsteady, as film in a projector gate
## Grain and weave suit old releases; they apply in every projection. The beam is for flat screens only and follows
## the screen. Cheap: one transparent mesh, MOTES particles, and a few ALU operations per pixel for the grain.
##
##   beam, grain, weave; set_beam(on), set_grain(v), set_weave(v)
##   apex() -> Vector3              the projector's lens, world space
##   beam_mesh, motes               the nodes (tests)
##   signal changed
## Settings: [projector] beam (default off), grain (default 0), weave (default 0).

signal changed

const MOTES := 240
## The projector: this far behind the seat and above the eyes (metres).
const BACK := 6.0
const UP := 2.2
## Gate weave at weave 1, as a fraction of the picture's height (real projectors: about 0.1-0.3 %).
const WEAVE_MAX := 0.003

const BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled;
uniform vec3 colour : source_color = vec3(1.0, 0.95, 0.85);
uniform float strength = 0.005;
varying float along;
varying vec2 side;
void vertex() {
	along = UV.y;
	side = UV2;
}
void fragment() {
	// Brighter near the lens, fading out before the screen; soft towards the cone's edges. A side seen face-on is
	// looked through the beam's thick middle, one seen edge-on through its thin edge (a cheap stand-in for the
	// length of the path through the light).
	float edge = smoothstep(0.0, 0.25, min(side.x, 1.0 - side.x));
	float thick = abs(dot(NORMAL, VIEW));
	float a = strength * (1.0 - smoothstep(0.5, 0.95, along)) * (0.35 + 0.65 * (1.0 - along)) * edge * thick * thick;
	ALBEDO = colour * a;
}
"""

var main: Node3D
var beam := false
var grain := 0.0
var weave := 0.0
var beam_mesh: MeshInstance3D
var motes: GPUParticles3D
var _placed_for := Transform3D()
var _placed_size := Vector2.ZERO
var _weave := Vector2.ZERO
var _weave_target := Vector2.ZERO
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	top_level = true
	beam = bool(main.settings.get_value("projector", "beam", false))
	grain = clampf(float(main.settings.get_value("projector", "grain", 0.0)), 0.0, 1.0)
	weave = clampf(float(main.settings.get_value("projector", "weave", 0.0)), 0.0, 1.0)
	beam_mesh = MeshInstance3D.new()
	beam_mesh.name = "Beam"
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = BEAM_SHADER
	m.shader = sh
	beam_mesh.material_override = m
	beam_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam_mesh)
	motes = GPUParticles3D.new()
	motes.name = "Motes"
	motes.amount = MOTES
	motes.lifetime = 9.0
	motes.preprocess = 9.0
	motes.local_coords = true
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	pm.gravity = Vector3.ZERO
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 0.005
	pm.initial_velocity_max = 0.03
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	# Fade in and out over each mote's life.
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(0.2, 1.0))
	curve.add_point(Vector2(0.8, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.alpha_curve = ct
	motes.process_material = pm
	var dot := QuadMesh.new()
	dot.size = Vector2(0.008, 0.008)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.vertex_color_use_as_albedo = true
	dm.albedo_color = Color(1.0, 0.95, 0.85, 0.35)
	dot.material = dm
	motes.draw_pass_1 = dot
	add_child(motes)
	main.file_opened.connect(func(_p: String) -> void: _apply_picture())
	_apply_picture()
	_update_beam()


func set_beam(on: bool) -> void:
	beam = on
	main.settings.set_value("projector", "beam", true if on else null)
	_placed_size = Vector2.ZERO
	_update_beam()
	changed.emit()


func set_grain(v: float) -> void:
	grain = clampf(v, 0.0, 1.0)
	main.settings.set_value("projector", "grain", null if is_zero_approx(grain) else grain)
	_apply_picture()
	changed.emit()


func set_weave(v: float) -> void:
	weave = clampf(v, 0.0, 1.0)
	main.settings.set_value("projector", "weave", null if is_zero_approx(weave) else weave)
	_apply_picture()
	changed.emit()


func beam_applies() -> bool:
	return beam and main.player.has_source() and main.screen.is_shown() and not main.mode.is_spherical()


func apex() -> Vector3:
	var seat: Vector3 = main.camera.global_position if main.camera != null else Vector3(0, main.eye_height, 0)
	var front: Vector3 = main.screen.global_position - seat
	front.y = 0.0
	front = front.normalized() if front.length() > 0.01 else Vector3.FORWARD
	return seat - front * BACK + Vector3.UP * UP


func _apply_picture() -> void:
	var m: ShaderMaterial = main.screen.material
	if m == null:
		return
	m.set_shader_parameter("film_grain", grain)
	if is_zero_approx(weave):
		_weave = Vector2.ZERO
		m.set_shader_parameter("film_weave", Vector2.ZERO)


func _process(delta: float) -> void:
	_update_beam()
	var m: ShaderMaterial = main.screen.material
	if grain > 0.0:
		m.set_shader_parameter("grain_seed", _rng.randf() * 1000.0)
	if weave > 0.0:
		# A slow random walk towards a new target a few times a second, plus a little jitter each frame.
		if _weave.distance_to(_weave_target) < WEAVE_MAX * 0.05 or _rng.randf() < delta * 3.0:
			_weave_target = Vector2(_rng.randf_range(-0.4, 0.4), _rng.randf_range(-1.0, 1.0)) * WEAVE_MAX * weave
		_weave = _weave.lerp(_weave_target, clampf(delta * 8.0, 0.0, 1.0))
		var jitter := Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * WEAVE_MAX * 0.1 * weave
		m.set_shader_parameter("film_weave", _weave + jitter)


func _update_beam() -> void:
	var on := beam_applies()
	beam_mesh.visible = on
	motes.visible = on
	motes.emitting = on
	if not on:
		return
	var screen: Node3D = main.screen
	var size: Vector2 = screen.get_flat_size()
	if screen.global_transform == _placed_for and size == _placed_size:
		return
	_placed_for = screen.global_transform
	_placed_size = size
	var a := apex()
	var corners: Array[Vector3] = []
	for c: Vector2 in [Vector2(-0.5, 0.5), Vector2(0.5, 0.5), Vector2(0.5, -0.5), Vector2(-0.5, -0.5)]:
		corners.append(screen.global_transform * Vector3(c.x * size.x, c.y * size.y, 0.0))
	global_transform = Transform3D(Basis.IDENTITY, a)
	# Four sides from the lens to the screen's edges: UV.y along the beam (0 at the lens), UV2.x across each side.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 4:
		var p := corners[i] - a
		var q := corners[(i + 1) % 4] - a
		for v: Array in [[Vector3.ZERO, 0.0, 0.5], [p, 1.0, 0.0], [q, 1.0, 1.0]]:
			st.set_uv(Vector2(0.0, v[1]))
			st.set_uv2(Vector2(v[2], 0.0))
			st.add_vertex(v[0])
	beam_mesh.mesh = st.commit()
	# Motes: random points inside the cone (lens-local), away from the lens and the screen.
	var img := Image.create_empty(MOTES, 1, false, Image.FORMAT_RGBF)
	for i in MOTES:
		var t := _rng.randf_range(0.15, 0.9)
		var u := _rng.randf()
		var v := _rng.randf()
		var edge_point := (corners[0] - a).lerp(corners[1] - a, u).lerp((corners[3] - a).lerp(corners[2] - a, u), v)
		var pt := edge_point * t
		img.set_pixel(i, 0, Color(pt.x, pt.y, pt.z))
	var pm := motes.process_material as ParticleProcessMaterial
	pm.emission_point_texture = ImageTexture.create_from_image(img)
	pm.emission_point_count = MOTES
	motes.visibility_aabb = AABB(Vector3.ZERO, Vector3.ZERO).expand(corners[0] - a).expand(corners[1] - a) \
			.expand(corners[2] - a).expand(corners[3] - a).grow(0.5)
	motes.restart()
