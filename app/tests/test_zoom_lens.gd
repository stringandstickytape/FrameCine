extends SceneTree

## Tests for the zoom lens (scripts/play/zoom_lens.gd, ideas #38) in the real main scene: grip + trigger brings it in
## 180 / 360 and not on a flat screen, the trigger then does not pause, it sits on the aim, and it goes on release.
## With a renderer: through the lens, the picture at the aim is the part of the equirectangular picture the aim points
## at, and a higher magnification shows fewer stripes. Settings are read-only.
## Run: godot --xr-mode off --path app --script res://tests/test_zoom_lens.gd

const BANDS := 32

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
	var z: Node = main.features.zoom_lens
	var hand: XRController3D = main.right_hand
	main.set_environment("void")
	main.open_path("stub://flat_mono")
	await _frames(3)
	hand.set("grip_down", true)
	_check("flat screen: no lens", not z.on_trigger(hand, true) and not z.active)
	main.open_path("stub://360_mono")
	await _frames(3)
	# A docked pane takes the trigger first (as "accept"): put it away.
	if main.ui != null and bool(main.ui.get("docked")):
		main.toggle_menu()
		await _frames(2)
	_check("pane not docked", main.ui == null or not bool(main.ui.get("docked")))
	var playing: bool = main.player.is_playing()
	main._on_trigger(hand, true)
	_check("360, grip held + trigger: the lens, playback untouched", z.active and z.lens.visible and z.hand == hand
			and main.player.is_playing() == playing)
	await _frames(1)
	var eye: Vector3 = main.camera.global_position
	_check("on the aim, 0.8 m out", z.lens.global_position.distance_to(eye + z.aim() * z.LENS_DISTANCE) < 0.01)
	main._on_trigger(hand, false)
	_check("trigger released: gone", not z.active and not z.lens.visible and main.player.is_playing() == playing)
	hand.set("grip_down", false)
	main._on_trigger(hand, true)
	await _frames(1)
	_check("trigger alone: play / pause as before", main.player.is_playing() != playing and not z.active)
	main._on_trigger(hand, false)
	main.player.toggle()
	z.set_magnification(20.0)
	_check("magnification clamped to 8", is_equal_approx(z.magnification, 8.0))
	z.set_magnification(3.0)
	_check("default erases the setting", not main.settings.has_value("zoom_lens", "magnification"))

	if DisplayServer.get_name() == "headless":
		print("SKIP render checks (headless)")
	else:
		await _render_checks(z)
	print("test_zoom_lens: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


## The colour of band i of the test picture (BANDS vertical bands across the equirectangular picture).
func _band_colour(i: int) -> Color:
	return [Color(1, 0, 0), Color(0, 1, 0), Color(0, 0, 1), Color(1, 1, 0)][i % 4]


func _render_checks(z: Node) -> void:
	var img := Image.create_empty(BANDS * 8, 64, false, Image.FORMAT_RGBA8)
	for i in BANDS:
		img.fill_rect(Rect2i(i * 8, 0, 8, 64), _band_colour(i))
	var m: ShaderMaterial = main.screen.material
	m.set_shader_parameter("rgb_tex", ImageTexture.create_from_image(img))
	m.set_shader_parameter("rgb_source", true)
	main._look = Vector2(37.0, 0.0)
	main._apply_look()
	z.begin(null)
	z.set_magnification(1.5)
	await _frames(3)
	await RenderingServer.frame_post_draw
	var shot := root.get_texture().get_image()
	var c := shot.get_pixel(shot.get_width() / 2, shot.get_height() / 2)
	var a: Vector3 = z.aim()
	var sphere: Node3D = main.screen.get("_sphere")
	var d: Vector3 = sphere.global_transform.basis.orthonormalized().inverse() * a
	var u := 0.5 + atan2(d.x, -d.z) / TAU
	var want := _band_colour(int(u * BANDS))
	_check("the lens's centre shows the aimed part (u %.3f, %s vs %s)" % [u, c, want], c.is_equal_approx(want)
			or (absf(c.r - want.r) < 0.15 and absf(c.g - want.g) < 0.15 and absf(c.b - want.b) < 0.15))
	var low := _changes(shot)
	z.set_magnification(6.0)
	await _frames(3)
	await RenderingServer.frame_post_draw
	var high := _changes(root.get_texture().get_image())
	_check("more magnification, fewer bands across the lens (%d -> %d)" % [low, high], high < low and low >= 3)
	z.end()
	main._look = Vector2.ZERO
	main._apply_look()


## Colour changes along the middle row, within the lens (a band of the image's middle third).
func _changes(img: Image) -> int:
	var y := img.get_height() / 2
	var n := 0
	var last := img.get_pixel(img.get_width() / 3, y)
	for x in range(img.get_width() / 3, img.get_width() * 2 / 3):
		var p := img.get_pixel(x, y)
		if absf(p.r - last.r) + absf(p.g - last.g) + absf(p.b - last.b) > 0.5:
			n += 1
		last = p
	return n


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
