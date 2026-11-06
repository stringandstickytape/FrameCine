extends SceneTree

## Tests for the video shader's footprint filter (shaders/video_common.gdshaderinc, footprint_taps) in the real main
## scene, rendered: the 8K 360° zone plate (lab://zoneplate_360) on the sphere at a modest window size, so the frame is
## shrunk on screen as it is in the headset, seen four ways round, with the filter off (1 tap) and on (3). Where the
## rings are finer than the screen can show, the right picture is flat grey and a single sample shows false rings: the
## filter takes most of that away. Where the rings are coarse, it keeps them. And the 8K starfield (lab://starfield_360)
## turned in small steps: a single sample makes stars blink as they fall between pixels; filtered, a patch's light
## holds steady. Settings are read-only. Prints the measures.
## Run: VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a godot --xr-mode off --path app --script
## res://tests/test_footprint.gd (needs a renderer; headless, it only checks the shader's uniform is there)

var _failures := 0
var _checks := 0
var main: Node3D

const WINDOW := Vector2i(640, 640)
const PATCH := 160


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	await _frames(5)
	main.ui.hide_panel()
	main.open_path("lab://zoneplate_360")
	await _frames(10)
	var mat: ShaderMaterial = main.screen.material
	_check("the screen's shader has footprint_taps, 3 at first", mat != null
			and int(mat.get_shader_parameter("footprint_taps") if mat.get_shader_parameter("footprint_taps") != null
			else RenderingServer.shader_get_parameter_default(mat.shader.get_rid(), "footprint_taps")) == 3)
	if DisplayServer.get_name() == "headless":
		print("SKIP render checks (headless)")
		_done()
		return
	get_root().size = WINDOW
	main.ui.hide_panel()
	await _frames(10)
	var ratios: Array[float] = []
	var lines: Array[String] = []
	for yaw: float in [0.0, 90.0, 180.0, 270.0]:
		var spread: Array[float] = []
		for taps: int in [1, 3]:
			mat.set_shader_parameter("footprint_taps", taps)
			main._look = Vector2(yaw, 0.0)
			main._apply_look()
			var img := await _grab()
			spread.append(_std(img))
		ratios.append(spread[1] / maxf(spread[0], 1e-4))
		lines.append("yaw %3d: spread %.3f off, %.3f on (%.2f)" % [roundi(yaw), spread[0], spread[1], ratios[-1]])
	print("  zone plate: " + "; ".join(lines))
	_check("where the rings are finer than the screen: most of the false rings gone (least kept %.2f)"
			% ratios.min(), ratios.min() < 0.6)
	_check("where they are coarse: the rings kept (most kept %.2f)" % ratios.max(), ratios.max() > 0.85)

	main.open_path("lab://starfield_360")
	await _frames(10)
	mat = main.screen.material
	var steadiness: Array[float] = []
	for taps: int in [1, 3]:
		mat.set_shader_parameter("footprint_taps", taps)
		var sums: Array[float] = []
		for step in 8:
			main._look = Vector2(30.0 + step * 0.013, 5.0)
			main._apply_look()
			var img := await _grab()
			sums.append(_mean(img))
		steadiness.append(_std_of(sums) / maxf(_mean_of(sums), 1e-5))
	print("  starfield: a patch's light over 8 small turns varies %.3f off, %.3f on" % [steadiness[0], steadiness[1]])
	_check("stars twinkle less as the head turns (%.3f -> %.3f)" % steadiness, steadiness[1] < steadiness[0] * 0.7)
	mat.set_shader_parameter("footprint_taps", 3)
	_done()


func _done() -> void:
	print("Footprint test: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


## The middle PATCH x PATCH of the window, a couple of frames after a change.
func _grab() -> Image:
	for k in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var c := img.get_size() / 2
	return img.get_region(Rect2i(c - Vector2i(PATCH, PATCH) / 2, Vector2i(PATCH, PATCH)))


func _std(img: Image) -> float:
	var vals: Array[float] = []
	for y in img.get_height():
		for x in img.get_width():
			vals.append(img.get_pixel(x, y).v)
	return _std_of(vals)


func _mean(img: Image) -> float:
	var s := 0.0
	for y in img.get_height():
		for x in img.get_width():
			s += img.get_pixel(x, y).v
	return s / float(img.get_width() * img.get_height())


func _mean_of(v: Array[float]) -> float:
	var s := 0.0
	for x in v:
		s += x
	return s / float(maxi(v.size(), 1))


func _std_of(v: Array[float]) -> float:
	var m := _mean_of(v)
	var s := 0.0
	for x in v:
		s += (x - m) * (x - m)
	return sqrt(s / float(maxi(v.size(), 1)))


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print(("PASS " if ok else "FAIL ") + what)
