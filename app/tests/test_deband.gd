extends SceneTree

## Tests for the deband (picture controls' "Smooth banding", pc_deband; shaders/video_common.gdshaderinc) in the real
## main scene: the setting (a picture control, on at 0.5, kept per environment, outside the pc_enabled block, off in
## the floor reflection), and rendered: the dark gradient card (lab://gradient, ramps that band in 8 bits) drawn
## through the film layer's shader (video_layer.gdshader, the screen's uniforms copied as the film layer copies them)
## into an 8-bit viewport, with the deband off and on. Off, the ramp is a staircase: flat runs and a jump of a code
## value between them. On, the jumps are spread and dithered: the largest step left between neighbouring columns
## (each the mean of many rows) is a fraction of a code value, and the picture's level is unchanged. Settings are
## read-only. Prints the measures.
## Run: VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a godot --xr-mode off --path app --script
## res://tests/test_deband.gd (the render needs a renderer; headless, only the setting is checked)

const LAYER_SHADER := preload("res://shaders/video_layer.gdshader")
const PictureControls := preload("res://scripts/play/picture_controls.gd")

var _failures := 0
var _checks := 0
var main: Node3D

const VIEW := Vector2i(1280, 720)


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	await _frames(5)
	var pc: Node = main.features.picture
	var mat: ShaderMaterial = main.screen.material
	_check("Smooth banding: a picture control, 0.5 at first", PictureControls.RANGES.has("deband")
			and is_equal_approx(float(PictureControls.RANGES["deband"][2]), 0.5)
			and is_equal_approx(float(mat.get_shader_parameter("pc_deband")), 0.5))
	_check("on by default, and still the defaults (the other controls' block stays skipped)", pc.is_default()
			and not bool(mat.get_shader_parameter("pc_enabled")))
	pc.set_value("deband", 0.8)
	_check("set: on the screen's material, and the defaults otherwise", is_equal_approx(
			float(mat.get_shader_parameter("pc_deband")), 0.8) and not bool(mat.get_shader_parameter("pc_enabled")))
	pc.reset()
	_check("reset: 0.5 again", is_equal_approx(float(mat.get_shader_parameter("pc_deband")), 0.5))
	var refl: Node = main.features.get("reflection")
	var refl_mat: ShaderMaterial = refl.get("_material") if refl != null else null
	_check("the floor reflection keeps it off", refl_mat == null
			or is_equal_approx(float(refl_mat.get_shader_parameter("pc_deband")), 0.0))
	# The toggles on the tablet's band (ui/pane_ui.gd): Steady detail (the footprint filter) and Smooth banding.
	var pui: Node = main.ui.ui
	_check("Steady detail on at first: the footprint filter's 3 taps, the toggle pressed", pc.steady
			and int(mat.get_shader_parameter("footprint_taps")) == 3 and pui._steady_toggle.button_pressed)
	pui._steady_toggle.toggled.emit(false)
	_check("Steady detail off: one tap, saved", not pc.steady and int(mat.get_shader_parameter("footprint_taps")) == 1
			and main.settings.get_value("picture", "steady_detail", true) == false)
	pui._steady_toggle.toggled.emit(true)
	_check("and on again", pc.steady and int(mat.get_shader_parameter("footprint_taps")) == 3
			and not main.settings.has_value("picture", "steady_detail"))
	pc.set_value("deband", 0.7)
	pui._banding_toggle.toggled.emit(false)
	_check("Smooth banding off: 0, the toggle up", is_equal_approx(float(mat.get_shader_parameter("pc_deband")), 0.0)
			and not pui._banding_toggle.button_pressed)
	pui._banding_toggle.toggled.emit(true)
	_check("on again: back to what it was (0.7)", is_equal_approx(float(mat.get_shader_parameter("pc_deband")), 0.7)
			and pui._banding_toggle.button_pressed)
	pc.reset()
	_check("the dark gradient card is listed", preload("res://scripts/video/lab_video_source.gd").list_cards().any(
			func(c: Dictionary) -> bool: return c["path"] == "lab://gradient"))

	if DisplayServer.get_name() == "headless":
		print("SKIP render checks (headless)")
		_done()
		return
	main.ui.hide_panel()
	main.open_path("lab://gradient")
	await _frames(12)
	var out: Array[Dictionary] = []
	for strength: float in [0.0, 0.5]:
		out.append(await _measure(strength))
	print("  grey ramp: largest step %.4f off, %.4f on (a code value is %.4f); mean %.4f off, %.4f on"
			% [out[0]["step"], out[1]["step"], 1.0 / 255.0, out[0]["mean"], out[1]["mean"]])
	_check("off: the ramp bands (steps of about a code value, %.4f)" % out[0]["step"], out[0]["step"] > 0.6 / 255.0)
	_check("on: the steps spread to a fraction of one (%.4f, %.0f %% of off)" % [out[1]["step"],
			100.0 * out[1]["step"] / maxf(out[0]["step"], 1e-6)], out[1]["step"] < out[0]["step"] * 0.5)
	_check("on: the picture's level is the same (%.4f, %.4f)" % [out[0]["mean"], out[1]["mean"]],
			absf(out[0]["mean"] - out[1]["mean"]) < 0.5 / 255.0)
	_done()


## The film layer's shader drawing the open card into an 8-bit viewport at `strength`; the top half's (the grey ramp's)
## column means: the largest step between neighbours (over the middle, away from the card's edges) and the mean.
func _measure(strength: float) -> Dictionary:
	var vp := SubViewport.new()
	vp.size = VIEW
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var m := ShaderMaterial.new()
	m.shader = LAYER_SHADER
	var src: ShaderMaterial = main.screen.material
	for u: Dictionary in LAYER_SHADER.get_shader_uniform_list():
		var n := str(u["name"])
		var v: Variant = src.get_shader_parameter(n)
		if v != null:
			m.set_shader_parameter(n, v)
	m.set_shader_parameter("force_eye", 0)
	m.set_shader_parameter("pc_deband", strength)
	var rect := ColorRect.new()
	rect.material = m
	rect.size = Vector2(VIEW)
	vp.add_child(rect)
	root.add_child(vp)
	for k in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	var rows := range(VIEW.y / 8, VIEW.y * 3 / 8)
	var cols: Array[float] = []
	for x in VIEW.x:
		var s := 0.0
		for y: int in rows:
			s += img.get_pixel(x, y).r
		cols.append(s / float(rows.size()))
	var step := 0.0
	var total := 0.0
	for x in range(VIEW.x / 10, VIEW.x * 9 / 10):
		step = maxf(step, absf(cols[x + 1] - cols[x]))
		total += cols[x]
	return {"step": step, "mean": total / float(VIEW.x * 8 / 10)}


func _done() -> void:
	print("Deband test: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print(("PASS " if ok else "FAIL ") + what)
