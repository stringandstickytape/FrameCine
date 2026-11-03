extends SceneTree

## Tests for scripts/env/projector.gd (ideas #92) in the real main scene: the beam from behind and above the seat to
## the screen's corners, the motes inside it, hidden in 360; grain and weave reaching the shader, the weave small and
## moving. With a renderer, grain is checked to change a flat grey picture and weave to move the picture.
## Run: godot --xr-mode off --path app --script res://tests/test_projector.gd

const VIDEO_SHADER := preload("res://shaders/video.gdshader")

var _failures := 0
var _checks := 0
var main: Node3D


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	await _frames(5)
	var pr: Node = main.features.projector
	main.set_environment("cinema")
	main.open_path("stub://flat_mono")
	await _frames(3)
	_check("off by default", not pr.beam and pr.grain == 0.0 and pr.weave == 0.0 and not pr.beam_mesh.visible)
	pr.set_beam(true)
	await _frames(2)
	var a: Vector3 = pr.apex()
	var seat: Vector3 = main.camera.global_position
	var to_screen: Vector3 = main.screen.global_position - seat
	_check("the lens behind and above the seat", (a - seat).dot(to_screen) < -5.0 and a.y > seat.y + 2.0)
	var mesh: Mesh = pr.beam_mesh.mesh
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var size: Vector2 = main.screen.get_flat_size()
	var corner: Vector3 = main.screen.global_transform * Vector3(-0.5 * size.x, 0.5 * size.y, 0.0)
	var found := false
	for v in verts:
		if (pr.beam_mesh.global_transform * v).distance_to(corner) < 0.001:
			found = true
	_check("four sides (%d vertices) reaching the screen's corners" % verts.size(), verts.size() == 12 and found)
	_check("motes emitting inside the beam", pr.motes.visible and pr.motes.emitting
			and pr.motes.process_material.emission_point_count == pr.MOTES)
	main.open_path("stub://360_mono")
	await _frames(3)
	_check("360: no beam", not pr.beam_mesh.visible and not pr.motes.emitting)
	main.open_path("stub://flat_mono")
	await _frames(3)
	_check("flat again: beam back", pr.beam_mesh.visible)
	pr.set_beam(false)

	var m: ShaderMaterial = main.screen.material
	pr.set_grain(0.6)
	await _frames(1)
	var s1: float = m.get_shader_parameter("grain_seed")
	await _frames(1)
	_check("grain on the picture, a new pattern each frame", is_equal_approx(m.get_shader_parameter("film_grain"), 0.6)
			and m.get_shader_parameter("grain_seed") != s1)
	pr.set_weave(1.0)
	var biggest := 0.0
	var moved := false
	var last := Vector2.ZERO
	for i in 60:
		await process_frame
		var w: Vector2 = m.get_shader_parameter("film_weave")
		biggest = maxf(biggest, maxf(absf(w.x), absf(w.y)))
		moved = moved or w != last
		last = w
	_check("weave moves, at most 0.33 %% of the picture (%.4f)" % biggest, moved and biggest > 0.0
			and biggest <= pr.WEAVE_MAX * 1.1)
	pr.set_weave(0.0)
	pr.set_grain(0.0)
	_check("off again: no grain, no weave", m.get_shader_parameter("film_grain") == 0.0
			and m.get_shader_parameter("film_weave") == Vector2.ZERO)
	_check("defaults erase the settings", not main.settings.has_value("projector", "grain")
			and not main.settings.has_value("projector", "weave") and not main.settings.has_value("projector", "beam"))

	if DisplayServer.get_name() != "headless":
		var grey := func(_x: int, _y: int) -> Color: return Color(0.5, 0.5, 0.5)
		var plain: Image = await _draw(grey, {})
		var grained: Image = await _draw(grey, {"film_grain": 1.0, "grain_seed": 3.0})
		_check("grain changes a flat grey (spread %.3f vs %.3f)" % [_spread(grained), _spread(plain)],
				_spread(plain) < 0.01 and _spread(grained) > 0.03)
		var bars := func(x: int, _y: int) -> Color: return Color(1, 1, 1) if x % 16 < 8 else Color(0, 0, 0)
		var still: Image = await _draw(bars, {})
		var shifted: Image = await _draw(bars, {"film_weave": Vector2(4.0 / 64.0, 0.0)})
		_check("weave moves the picture (4 px)", still.get_pixel(10, 8).r < 0.1 and shifted.get_pixel(6, 8).r < 0.1
				and still.get_pixel(6, 8).r > 0.9)
	else:
		print("SKIP render checks (headless)")
	print("test_projector: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _spread(img: Image) -> float:
	var lo := 1.0
	var hi := 0.0
	for y in img.get_height():
		for x in img.get_width():
			lo = minf(lo, img.get_pixel(x, y).r)
			hi = maxf(hi, img.get_pixel(x, y).r)
	return hi - lo


## A 64x16 RGB picture through the video shader into a 64x16 viewport, pixel for pixel.
func _draw(pixel: Callable, params: Dictionary) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 16)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.own_world_3d = true
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.0
	cam.position = Vector3(0, 0, 1)
	vp.add_child(cam)
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(4, 1)
	quad.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = VIDEO_SHADER
	var img := Image.create_empty(64, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 64:
			img.set_pixel(x, y, pixel.call(x, y))
	mat.set_shader_parameter("rgb_tex", ImageTexture.create_from_image(img))
	mat.set_shader_parameter("rgb_source", true)
	mat.set_shader_parameter("force_eye", 0)
	for k: String in params:
		mat.set_shader_parameter(k, params[k])
	quad.material_override = mat
	vp.add_child(quad)
	root.add_child(vp)
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var out := vp.get_texture().get_image()
	vp.queue_free()
	return out


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL ", what)
	else:
		print("PASS ", what)
