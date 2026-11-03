extends Node

## Bias light from the picture (ideas #29): the screen's light on the room takes the film's colour and brightness, so
## a sunset warms the walls and a night scene lets the room go dark. Each side of the room takes the colour of the
## picture's side nearest to it.
##
## All on the GPU, nothing read back: a tiny offscreen viewport (4 x 2 pixels) draws the picture through the screen's
## own uniforms (shaders/bias_sample.gdshader), each pixel the mean of its part, blended over the frames before it
## (the viewport keeps its contents), so changes fade in over about BLEND_SECONDS. The environment shaders read it
## as the global screen_thumb (shaders/env_spill.gdshaderinc), scaled so a typical film lights the room as designed.
## Flat screens only (180 / 360 hide the room); the void has no spill to colour.
##
##   enabled, set_enabled(on)        [bias_light] enabled (default off until its cost is measured on the headset)
##   strength, set_strength(v)       [bias_light] strength, 0..1 (default 1): how far the spill follows the picture
##   active()                        the tint is applied now
##   tint, axis                      the globals screen_tint and screen_axis as last set
##   thumbnail() -> Texture2D        the smoothed picture (4 x 2)
##   request_sampling(who, on)       keep the picture's copy fresh for an assistant room's reacting glow; sampling()
##   signal changed

signal changed

const SAMPLE_SHADER := preload("res://shaders/bias_sample.gdshader")
const CELLS := Vector2i(4, 2)
## Time constant of the smoothing, seconds.
const BLEND_SECONDS := 0.25

var main: Node3D
var enabled := false
var strength := 1.0
var _vp: SubViewport
var _material: ShaderMaterial
var _names: Array[String] = []
var _active := false
var _sampling := false
var _requests := {}
var tint := 0.0
var axis := Vector3.ZERO


func _ready() -> void:
	enabled = bool(main.settings.get_value("bias_light", "enabled", false))
	strength = clampf(float(main.settings.get_value("bias_light", "strength", 1.0)), 0.0, 1.0)
	_vp = SubViewport.new()
	_vp.name = "BiasLightSampler"
	_vp.size = CELLS
	_vp.own_world_3d = true
	_vp.transparent_bg = false
	_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.0
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.position = Vector3(0, 0, 1)
	var env := Environment.new()
	env.background_mode = Environment.BG_KEEP
	cam.environment = env
	_vp.add_child(cam)
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	# The camera sees 1 m high and 2 m wide (4 x 2 pixels): the quad fills it.
	mesh.size = Vector2(float(CELLS.x) / CELLS.y, 1.0)
	quad.mesh = mesh
	_material = ShaderMaterial.new()
	_material.shader = SAMPLE_SHADER
	_material.set_shader_parameter("cells", Vector2(CELLS))
	quad.material_override = _material
	_vp.add_child(quad)
	add_child(_vp)
	for u: Dictionary in SAMPLE_SHADER.get_shader_uniform_list():
		var n: String = u["name"]
		if not n in ["blend", "cells"]:
			_names.append(n)
	RenderingServer.global_shader_parameter_set("screen_thumb", _vp.get_texture())


func set_enabled(on: bool) -> void:
	enabled = on
	main.settings.set_value("bias_light", "enabled", true if on else null)
	changed.emit()


func set_strength(v: float) -> void:
	strength = clampf(v, 0.0, 1.0)
	main.settings.set_value("bias_light", "strength", null if is_equal_approx(strength, 1.0) else strength)
	changed.emit()


## Keep the picture's copy fresh for `who` (an assistant room's screen-reactive glow) even with the bias light off.
func request_sampling(who: Object, on: bool) -> void:
	if on:
		_requests[who.get_instance_id()] = true
	else:
		_requests.erase(who.get_instance_id())


func sampling() -> bool:
	return _sampling


func _requested() -> bool:
	for id: int in _requests.keys():
		if not is_instance_id_valid(id):
			_requests.erase(id)
	return not _requests.is_empty()


func active() -> bool:
	return _active


func thumbnail() -> Texture2D:
	return _vp.get_texture()


func _process(delta: float) -> void:
	var screen: Node3D = main.screen
	var source_ok: bool = main.player.has_source() and screen.is_shown() and not main.mode.is_spherical()
	var want: bool = enabled and strength > 0.0 and source_ok
	# The copy is also kept for a room's screen-reactive glow, with the tint off if the bias light is.
	var sample: bool = source_ok and (want or _requested())
	if sample != _sampling:
		_sampling = sample
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if sample else SubViewport.UPDATE_DISABLED
		if sample:
			# Start from the picture as it is, not from what the viewport held before.
			_material.set_shader_parameter("blend", 1.0)
	elif sample:
		_material.set_shader_parameter("blend", clampf(1.0 - exp(-delta / BLEND_SECONDS), 0.01, 1.0))
	if want != _active:
		_active = want
		tint = strength if want else 0.0
		RenderingServer.global_shader_parameter_set("screen_tint", tint)
		changed.emit()
	if not sample:
		return
	if want:
		tint = strength
		RenderingServer.global_shader_parameter_set("screen_tint", tint)
	var src: ShaderMaterial = screen.material
	for n in _names:
		_material.set_shader_parameter(n, src.get_shader_parameter(n))
	_material.set_shader_parameter("force_eye", 0)
	var width: float = screen.get_flat_size().x
	var right: Vector3 = screen.global_transform.basis.x.normalized()
	axis = right / maxf(width, 0.1)
	RenderingServer.global_shader_parameter_set("screen_axis", axis)
