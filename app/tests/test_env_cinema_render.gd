extends SceneTree

## The converted cinema looks the same (docs/environments.md, "The converted cinema"): the old cinema, the room as code
## before the conversion (tests/fixtures/cinema_v3.gd), and the new one, a version 4 document built by the systems
## (environments/cinema.tscn), drawn by the Mobile renderer side by side from the seat and from the aisle, compared
## pixel by pixel. The pictures are kept in user://env_render/ (old, new, and the difference x8).
## VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a godot --xr-mode off --path app --script
## res://tests/test_env_cinema_render.gd (headless: skipped, it needs a renderer)

const OldCinema := preload("res://tests/fixtures/cinema_v3.gd")
const Cinema := preload("res://environments/cinema.gd")
const Auditorium := preload("res://scripts/env/systems/auditorium.gd")
const VIEW := Vector2i(640, 360)
const OUT := "user://env_render"
## The mean difference a channel may have (0..1), and the share of pixels that may differ by more than PIXEL_LIMIT.
const MEAN_LIMIT := 0.004
const PIXEL_LIMIT := 0.04
const SHARE_LIMIT := 0.005

var _failures := 0
var _checks := 0


func _init() -> void:
	_run.call_deferred()


func _old() -> Node3D:
	var c: Node3D = OldCinema.new()
	c.name = "OldCinema"
	c.display_name = "Cinema"
	c.ambient_level = 0.05
	c.screen_glow = 1.0
	c.default_screen_width = 12.0
	var a := Marker3D.new()
	a.name = "ScreenAnchor"
	a.transform = Transform3D(Basis(), Vector3(0, 1.6, -13.8))
	c.add_child(a)
	c.screen_anchor = a
	return c


func _viewport(room: Node3D) -> Array:
	var vp := SubViewport.new()
	vp.size = VIEW
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	vp.add_child(room)
	var cam := Camera3D.new()
	cam.fov = 80.0
	cam.far = 200.0
	vp.add_child(cam)
	cam.current = true
	root.add_child(vp)
	return [vp, cam]


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP render checks (headless)")
		print("test_env_cinema_render: 0 checks, all passed")
		quit(0)
		return
	DirAccess.make_dir_recursive_absolute(OUT)
	var old := _old()
	var new: Node3D = (load("res://environments/cinema.tscn") as PackedScene).instantiate()
	var a := _viewport(old)
	var b := _viewport(new)
	_check("the new cinema is the document's, built by its systems", new.get_script() == Cinema
			and new.get_node_or_null("Systems") != null and new.get_node_or_null("Systems/hall") != null
			and old.get_node_or_null("Systems") == null)
	for room: Node3D in [old, new]:
		room.apply_light(1.0)
		room.on_screen_changed(room.get_screen_anchor(), Vector2(12.0, 5.02))
	var aisle_y := Auditorium.layout(Cinema.HALL).aisle_floor(-2.0)
	var views := {
		"seat": [Vector3(0, 1.2, 0), Vector3(0, 1.0, -13.8)],
		"aisle": [Vector3(8.8, aisle_y + 1.6, -2.0), Vector3(0.0, 0.0, -13.0)],
		"back": [Vector3(-3.0, Cinema.seat_transforms()[0].origin.y + 1.3, 5.0), Vector3(2.0, 1.5, -14.0)],
	}
	for view: String in views:
		var at: Vector3 = views[view][0]
		var look: Vector3 = views[view][1]
		for vc: Array in [a, b]:
			(vc[1] as Camera3D).look_at_from_position(at, look)
		for i in 6:
			await process_frame
		await RenderingServer.frame_post_draw
		var ia := (a[0] as SubViewport).get_texture().get_image()
		var ib := (b[0] as SubViewport).get_texture().get_image()
		ia.convert(Image.FORMAT_RGB8)
		ib.convert(Image.FORMAT_RGB8)
		var diff := Image.create_empty(VIEW.x, VIEW.y, false, Image.FORMAT_RGB8)
		var sum := 0.0
		var off := 0
		var bright := 0.0
		for y in VIEW.y:
			for x in VIEW.x:
				var ca := ia.get_pixel(x, y)
				var cb := ib.get_pixel(x, y)
				var d := maxf(maxf(absf(ca.r - cb.r), absf(ca.g - cb.g)), absf(ca.b - cb.b))
				sum += (absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) / 3.0
				bright += ca.get_luminance()
				if d > PIXEL_LIMIT:
					off += 1
				diff.set_pixel(x, y, Color(minf(d * 8.0, 1.0), minf(d * 8.0, 1.0), minf(d * 8.0, 1.0)))
		var n := float(VIEW.x * VIEW.y)
		var mean := sum / n
		var share := off / n
		ia.save_png(OUT.path_join("%s_old.png" % view))
		ib.save_png(OUT.path_join("%s_new.png" % view))
		diff.save_png(OUT.path_join("%s_diff.png" % view))
		print("  %s: mean difference %.5f, %.3f %% of pixels over %.2f, mean brightness %.3f (%s)" % [view, mean,
				share * 100.0, PIXEL_LIMIT, bright / n, ProjectSettings.globalize_path(OUT)])
		_check("%s: something drawn (%.3f)" % [view, bright / n], bright / n > 0.01)
		_check("%s: the same picture (mean %.5f, %.3f %% off)" % [view, mean, share * 100.0], mean < MEAN_LIMIT
				and share < SHARE_LIMIT)
	for vc: Array in [a, b]:
		(vc[0] as Node).queue_free()
	await process_frame
	print("test_env_cinema_render: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)
