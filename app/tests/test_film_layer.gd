extends SceneTree

## Tests for the film layer (scripts/play/film_layer.gd, ideas #70) in the real main scene: the setting, the fallback
## to the screen's mesh without an XR session, and, forced on without one, the layers' kind, eyes, order, hole punch,
## size and place for flat 2D, flat 3D, 3D shown as 2D, the curved screen and 360, drawing only on new pictures or
## changed uniforms, switching at run time while playing, and hiding while the menu is open. The runtime's
## composition itself needs the headset.
## Run: godot --headless --xr-mode off --path app --script res://tests/test_film_layer.gd

const FilmLayer := preload("res://scripts/play/film_layer.gd")
const VideoMode := preload("res://scripts/video_mode.gd")

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
	if not FilmLayer.available():
		print("SKIP (no OpenXRCompositionLayerQuad in this engine)")
		print("test_film_layer: 0 checks, all passed")
		quit(0)
		return
	var film: Node = main.features.film_layer
	var flat: Node3D = main.screen.get_node("Flat")
	main.set_environment("void")
	main.open_path("stub://flat_mono")
	await _frames(3)
	_check("on by default; no XR session, so no layers and the screen's quad drawn", film.enabled
			and film.layers.is_empty() and flat.visible and film.kind == "")

	# The setting: only off is stored.
	film.set_enabled(false)
	_check("off: saved", main.settings.get_value("view", "film_layer", true) == false)
	var fresh: Node = FilmLayer.new()
	fresh.main = main
	main.add_child(fresh)
	_check("a new instance reads it", not fresh.enabled)
	fresh.free()
	film.set_enabled(true)
	_check("on: the key goes", not main.settings.has_value("view", "film_layer"))
	film.set_enabled(false, false)
	_check("for the run only: off, not saved", not film.enabled and not main.settings.has_value("view", "film_layer"))
	film.set_enabled(true, false)

	# No XR session: the mesh.
	await _frames(3)
	_check("no XR session: no layers, the quad drawn", film.layers.is_empty() and flat.visible)
	_check("no XR session: the status says so", "headset" in film.status())

	# Forced on: flat 2D. The panel is open at launch; closed, so the layer isn't held for the menu.
	main.ui.hide_panel()
	film.force = true
	await _frames(2)
	var size: Vector2 = main.screen.get_flat_size()
	_check("flat 2D: one quad layer both eyes see", film.kind == "quad" and film.layers.size() == 1
			and film.layers[0].get("eye_visibility") == 0)
	var layer: Node3D = film.layers[0]
	_check("behind the scene, opaque, with a hole punched", layer.get("sort_order") == -1
			and layer.get("enable_hole_punch") and not layer.get("alpha_blend"))
	_check("on the screen, at its size", layer.get_parent() == main.screen and layer.transform == Transform3D.IDENTITY
			and (layer.get("quad_size") as Vector2).is_equal_approx(size))
	_check("the viewport is the film's pixels (%s)" % film.viewports[0].size, film.viewports[0].size == Vector2i(1920, 1080)
			and layer.get("layer_viewport") == film.viewports[0])
	_check("the screen's quad is not drawn", not flat.visible and main.screen.is_shown())
	_check("the status says it is in use", film.status().begins_with("In use: one quad layer"))
	if DisplayServer.get_name() != "headless":
		# The layer's picture against the screen's shader drawn the same size (the stereo screenshot's way), paused.
		main.player.pause()
		main.screen.material.set_shader_parameter("brightness", 1.0)
		# The colour conversion compared, not the deband's dither (random per pixel and frame, on each side).
		main.screen.material.set_shader_parameter("pc_deband", 0.0)
		await _frames(2)
		await RenderingServer.frame_post_draw
		var mine: Image = film.viewports[0].get_texture().get_image()
		var ref: Image = await main.features.screenshot._render_eye(0, film.viewports[0].size)
		var worst := 0.0
		# The colour bars and the grey ramp (the pattern's sweep line moves even when paused).
		for y in range(880, 980, 11):
			for x in range(400, 1520, 23):
				var a := mine.get_pixel(x, y)
				var b := ref.get_pixel(x, y)
				worst = maxf(worst, maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))))
		_check("the layer's colours match the screen's shader (worst %.3f)" % worst, worst < 0.02)
		main.screen.material.set_shader_parameter("pc_deband", main.features.picture.values["deband"])
		main.player.play()

	# Resize: the layer follows, the viewport keeps the film's pixels.
	main.set_screen(4.5, main.screen_distance, main.screen_height_offset)
	await _frames(2)
	_check("resize: the quad follows (%s)" % layer.get("quad_size"), (layer.get("quad_size") as Vector2).is_equal_approx(
			main.screen.get_flat_size()) and film.viewports[0].size == Vector2i(1920, 1080))

	# Draws only on a new picture or a changed uniform.
	main.player.pause()
	await _frames(2)
	film._update()
	var before: int = film.updates
	film._update()
	_check("nothing new: not drawn again", film.updates == before
			and film.viewports[0].render_target_update_mode == SubViewport.UPDATE_DISABLED)
	main.screen.material.set_shader_parameter("pc_brightness", 0.1)
	film._update()
	_check("a changed uniform: drawn, with the value", film.updates == before + 1
			and film.viewports[0].render_target_update_mode == SubViewport.UPDATE_ALWAYS
			and is_equal_approx(float(film._materials[0].get_shader_parameter("pc_brightness")), 0.1))
	main.screen.material.set_shader_parameter("pc_brightness", 0.0)
	main.player.play()
	var frames0: int = Engine.get_process_frames()
	var updates0: int = film.updates
	await create_timer(0.5).timeout
	var drawn: int = film.updates - updates0
	var frames: int = Engine.get_process_frames() - frames0
	_check("playing: drawn on new pictures only (%d of %d frames)" % [drawn, frames], drawn >= 2 and drawn < frames)

	# Flat 3D: one layer per eye.
	main.open_path("stub://flat_sbs")
	await _frames(3)
	_check("flat 3D: two quad layers, left and right", film.layers.size() == 2
			and film.layers[0].get("eye_visibility") == 1 and film.layers[1].get("eye_visibility") == 2)
	_check("each eye's viewport is one eye's picture (%s)" % film.viewports[0].size,
			film.viewports[0].size == Vector2i(1920, 1080) and film.viewports[1].size == Vector2i(1920, 1080))
	_check("each draws its own eye, one hole for both", film._materials[0].get_shader_parameter("force_eye") == 0
			and film._materials[1].get_shader_parameter("force_eye") == 1
			and film.layers[0].get("enable_hole_punch") and not film.layers[1].get("enable_hole_punch"))
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var l: Image = film.viewports[0].get_texture().get_image()
		var r: Image = film.viewports[1].get_texture().get_image()
		var differ := 0
		for y in range(0, l.get_height(), 97):
			for x in range(0, l.get_width(), 97):
				if not l.get_pixel(x, y).is_equal_approx(r.get_pixel(x, y)):
					differ += 1
		_check("the eyes' pictures differ on a 3D pattern (%d samples)" % differ, differ > 5)
	main.features.two_d.set_eye(0)
	await _frames(2)
	_check("3D shown as 2D: one layer", film.layers.size() == 1 and film.layers[0].get("eye_visibility") == 0)
	main.features.two_d.set_eye(-1)
	await _frames(2)

	# Curved: a cylinder whose arc is the curved mesh.
	main.screen.set_curve_radius(5.0)
	await _frames(2)
	size = main.screen.get_flat_size()
	var cyl: Node3D = film.layers[0] if not film.layers.is_empty() else null
	var ok: bool = cyl != null and film.kind == "cylinder" and is_equal_approx(float(cyl.get("radius")), 5.0) \
			and is_equal_approx(float(cyl.get("central_angle")), size.x / 5.0) \
			and is_equal_approx(float(cyl.get("aspect_ratio")), size.x / size.y) \
			and cyl.position.is_equal_approx(Vector3(0, 0, 5.0))
	_check("curved: cylinder layers on the curve's axis", ok)
	if cyl != null:
		# The arc's right end, as the engine's cylinder puts it (at -Z from its pose), against the screen's corner.
		var half := float(cyl.get("central_angle")) * 0.5
		var end := cyl.global_transform * Vector3(5.0 * sin(half), size.y * 0.5, -5.0 * cos(half))
		_check("curved: the arc ends at the screen's corner", end.distance_to(main.screen.top_right_corner()) < 0.001)
	main.screen.set_curve_radius(0.0)
	await _frames(2)
	_check("flat again: quads", film.kind == "quad")

	# 180 / 360: the mesh.
	main.open_path("stub://360_mono")
	await _frames(3)
	_check("360: no layers", film.layers.is_empty() and film.kind == "" and "360" in film.status())

	# Switching at run time keeps playback going.
	main.open_path("stub://flat_mono")
	await _frames(3)
	var source: Object = main.player.source
	film.set_enabled(false, false)
	await _frames(1)
	_check("switched off while playing: the quad drawn, the same source playing", film.layers.is_empty()
			and flat.visible and main.player.source == source and main.player.is_playing())
	film.set_enabled(true, false)
	await _frames(1)
	_check("and on again", film.layers.size() == 1 and not flat.visible and main.player.source == source)

	# The menu: the layer hides and the mesh draws, then back; nothing remade, the setting untouched.
	var held_layer: Node3D = film.layers[0]
	main.set_menu_shown(true)
	await _frames(1)
	_check("menu open: the layer hidden, the quad drawn", film.held and not held_layer.visible and flat.visible
			and film.layers[0] == held_layer and film.enabled and "menu" in film.status())
	main.set_menu_shown(false)
	await _frames(1)
	_check("menu closed: the same layer back, the quad not drawn", not film.held and held_layer.visible
			and not flat.visible and film.layers[0] == held_layer)

	# The pure sizing helper.
	var m := VideoMode.new()
	_check("4K 2D: 3840 x 2160", FilmLayer.eye_pixels(Vector2(3840, 2160), Vector2(3.2, 1.8), m) == Vector2i(3840, 2160))
	_check("8K 2D: scaled to fit 3840", FilmLayer.eye_pixels(Vector2(7680, 4320), Vector2(3.2, 1.8), m)
			== Vector2i(3840, 2160))
	m.layout = VideoMode.Layout.TB
	_check("full top / bottom: one eye's half", FilmLayer.eye_pixels(Vector2(1920, 2160), Vector2(3.2, 1.8), m)
			== Vector2i(1920, 1080))
	m.layout = VideoMode.Layout.SBS
	m.half = true
	_check("half side by side: stretched to the full width", FilmLayer.eye_pixels(Vector2(1920, 1080), Vector2(3.2, 1.8),
			m) == Vector2i(1920, 1080))
	var odd := FilmLayer.eye_pixels(Vector2(1001, 563), Vector2(3.0, 1.687), VideoMode.new())
	_check("odd sizes snap to %d px (%s)" % [FilmLayer.SNAP, odd], odd.x % FilmLayer.SNAP == 0 and odd.y % FilmLayer.SNAP == 0)

	var hub: Node = film.get_parent()
	hub.remove_child(film)
	await _frames(1)
	_check("the feature taken out: the quad drawn", flat.visible and main.screen.get_children().filter(
			func(n: Node) -> bool: return n.name.begins_with("FilmLayer")).is_empty())
	hub.add_child(film)
	print("test_film_layer: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


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
