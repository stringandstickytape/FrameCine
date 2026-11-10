extends SceneTree

## Tests for the bias light (scripts/env/bias_light.gd, ideas #29) in the real main scene: when it applies, the
## smoothed picture thumbnail, and the room shader's spill taking the colour of the picture's nearest side. The
## thumbnail and spill checks draw through the GPU, so they need a renderer (skipped with --headless).
## Run: godot --xr-mode off --path app --script res://tests/test_bias.gd

const ENV_SHADER := preload("res://shaders/env_unlit.gdshader")

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
	var b: Node = main.features.bias
	_check("on by default", b.enabled)
	b.set_enabled(true)
	main.set_environment("cinema")
	main.open_path("stub://flat_mono")
	await _frames(5)
	_check("turned on: active on a flat screen", b.enabled and b.active())
	_check("tint global set", is_equal_approx(_global("screen_tint"), 1.0))
	main.open_path("stub://360_mono")
	await _frames(3)
	_check("off in 360 (no room)", not b.active() and is_equal_approx(_global("screen_tint"), 0.0))
	main.open_path("stub://flat_mono")
	await _frames(3)
	b.set_enabled(false)
	await _frames(2)
	_check("turned off: the spill white again", not b.active() and is_equal_approx(_global("screen_tint"), 0.0))
	b.set_enabled(true)
	await _frames(2)
	_check("on again", b.active())
	var axis: Vector3 = _global("screen_axis")
	_check("screen axis: right over the width (%s)" % axis, absf(axis.length() * main.screen.get_flat_size().x - 1.0)
			< 0.01 and axis.normalized().dot(main.screen.global_transform.basis.x.normalized()) > 0.99)
	if DisplayServer.get_name() == "headless":
		print("SKIP render checks (headless)")
	else:
		await _render_checks()
	print("test_bias: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _global(n: String) -> Variant:
	return main.features.bias.tint if n == "screen_tint" else main.features.bias.axis


## A picture (left half `left`, right half `right`) on the screen as an RGB source, in place of the pattern.
func _show(left: Color, right: Color) -> void:
	var img := Image.create_empty(64, 32, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(0, 0, 32, 32), left)
	img.fill_rect(Rect2i(32, 0, 32, 32), right)
	var m: ShaderMaterial = main.screen.material
	m.set_shader_parameter("rgb_tex", ImageTexture.create_from_image(img))
	m.set_shader_parameter("rgb_source", true)


func _thumb() -> Image:
	await RenderingServer.frame_post_draw
	return main.features.bias.thumbnail().get_image()


func _render_checks() -> void:
	_show(Color(0.8, 0.1, 0.1), Color(0.1, 0.1, 0.8))
	await create_timer(1.5).timeout
	var t: Image = await _thumb()
	_check("thumbnail %dx%d" % [t.get_width(), t.get_height()], t.get_width() == 4 and t.get_height() == 2)
	var l := t.get_pixel(0, 0)
	var r := t.get_pixel(3, 1)
	print("  thumbnail left %s, right %s" % [l, r])
	_check("left cells red", l.r > 0.7 and l.b < 0.2)
	_check("right cells blue", r.b > 0.7 and r.r < 0.2)
	# Smoothing: a change to green fades in over about a quarter second.
	_show(Color(0.1, 0.8, 0.1), Color(0.1, 0.8, 0.1))
	await _frames(1)
	var mid: Image = await _thumb()
	var g1 := mid.get_pixel(0, 0)
	await create_timer(1.5).timeout
	var g2: Color = (await _thumb()).get_pixel(0, 0)
	print("  after one frame %s, after 1.5 s %s" % [g1, g2])
	_check("smoothed: part way after one frame", g1.g < 0.75 and g1.r > 0.15)
	_check("settled after 1.5 s", g2.g > 0.75 and g2.r < 0.2)
	# The room shader: a white wall left of the screen takes the left side's colour, one right of it the right side's.
	_show(Color(0.8, 0.1, 0.1), Color(0.1, 0.1, 0.8))
	await create_timer(1.5).timeout
	var right: Vector3 = main.screen.global_transform.basis.x.normalized()
	var w: float = main.screen.get_flat_size().x
	var centre: Vector3 = main.screen.global_position
	var lw: Color = await _wall(centre - right * w)
	var rw: Color = await _wall(centre + right * w)
	print("  wall left %s, right %s" % [lw, rw])
	_check("wall left of the screen reddish", lw.r > lw.b * 2.0)
	_check("wall right of the screen bluish", rw.b > rw.r * 2.0)
	main.features.bias.set_enabled(false)
	await _frames(2)
	var plain: Color = await _wall(centre - right * w)
	_check("bias light off: the wall's spill white", absf(plain.r - plain.b) < 0.02 and plain.r > 0.02)
	main.features.bias.set_enabled(true)
	main.features.bias.set_enabled(false)


## A white env_unlit quad at world position p, facing the camera, drawn in its own small viewport.
func _wall(p: Vector3) -> Color:
	var vp := SubViewport.new()
	vp.size = Vector2i(4, 4)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.own_world_3d = true
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 0.1
	cam.position = p + Vector3(0, 0, 1)
	vp.add_child(cam)
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.5, 0.5)
	quad.mesh = mesh
	quad.position = p
	var m := ShaderMaterial.new()
	m.shader = ENV_SHADER
	m.set_shader_parameter("albedo", Color(1, 1, 1))
	m.set_shader_parameter("floor_darkening", 0.0)
	quad.material_override = m
	vp.add_child(quad)
	root.add_child(vp)
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var c := vp.get_texture().get_image().get_pixel(2, 2)
	vp.queue_free()
	return c


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
