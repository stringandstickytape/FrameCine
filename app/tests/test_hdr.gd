extends SceneTree

## Tests for scripts/play/hdr_tone_map.gd and the colour part of shaders/video.gdshader (ideas #85).
## describe() runs anywhere; the shader checks draw known Y'CbCr values through the real shader into a small viewport,
## so they need a renderer (skipped with --headless).
## Run: godot --xr-mode off --path app --script res://tests/test_hdr.gd

const Hdr := preload("res://scripts/play/hdr_tone_map.gd")
const VIDEO_SHADER := preload("res://shaders/video.gdshader")

var _failures := 0
var _checks := 0


func _init() -> void:
	_describe_checks()
	await _node_checks()
	if DisplayServer.get_name() == "headless":
		print("SKIP shader checks (headless)")
	else:
		await _shader_checks()
		if Hdr.engine_curve_available():
			await _engine_curve_checks()
		else:
			print("SKIP engine curve checks (no MediaSource.get_tone_mapping)")
	print("test_hdr: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _describe_checks() -> void:
	var hdr10 := Hdr.describe({"color_primaries": "bt2020", "color_transfer": "smpte2084", "color_matrix": "bt2020nc",
			"color_range": "tv", "height": 816})
	_check("HDR10: PQ, BT.2020 matrix and primaries, limited, default peak", hdr10["transfer"] == Hdr.TRANSFER_PQ
			and hdr10["matrix"] == Hdr.MATRIX_2020 and hdr10["primaries_bt2020"] and not hdr10["full_range"]
			and hdr10["peak_nits"] == 1000.0 and hdr10["peak_from"] == "default")
	var hlg := Hdr.describe({"color_transfer": "arib-std-b67", "height": 2160})
	_check("HLG without primaries: BT.2020 assumed", hlg["transfer"] == Hdr.TRANSFER_HLG and hlg["primaries_bt2020"]
			and hlg["matrix"] == Hdr.MATRIX_2020)
	_check("hdr flag alone: PQ", Hdr.describe({"hdr": true})["transfer"] == Hdr.TRANSFER_PQ)
	var sd := Hdr.describe({"color_matrix": "", "height": 576})
	_check("SD without a matrix: BT.601", sd["matrix"] == Hdr.MATRIX_601 and sd["transfer"] == Hdr.TRANSFER_SDR
			and not sd["primaries_bt2020"])
	_check("HD without a matrix: BT.709", Hdr.describe({"height": 1080})["matrix"] == Hdr.MATRIX_709)
	_check("smpte170m: BT.601", Hdr.describe({"color_matrix": "smpte170m", "height": 1080})["matrix"] == Hdr.MATRIX_601)
	_check("full range from color_range pc", Hdr.describe({"color_range": "pc"})["full_range"])
	var cll := Hdr.describe({"color_transfer": "smpte2084", "max_cll": 1500.0, "mastering_max_luminance": 1000.0})
	_check("MaxCLL capped by the mastering peak", cll["peak_nits"] == 1000.0 and cll["peak_from"] == "content light level")
	var m := Hdr.describe({"color_transfer": "smpte2084", "mastering_max_luminance": 4000.0})
	_check("mastering peak used without MaxCLL", m["peak_nits"] == 4000.0 and m["peak_from"] == "mastering display")
	_check("peak at least reference white", Hdr.describe({"color_transfer": "smpte2084", "max_cll": 50.0})["peak_nits"] == 203.0)
	var engine_keys := Hdr.describe({"hdr_transfer": "pq", "max_cll": 0, "mastering_display_luminance": Vector2(0.005, 4000.0)})
	_check("engine keys: hdr_transfer pq, mastering peak from mastering_display_luminance", engine_keys["transfer"]
			== Hdr.TRANSFER_PQ and engine_keys["peak_nits"] == 4000.0 and engine_keys["primaries_bt2020"])
	_check("hdr_transfer hlg", Hdr.describe({"hdr_transfer": "hlg"})["transfer"] == Hdr.TRANSFER_HLG)
	_check("stub / window info: SDR BT.709", Hdr.describe({"codec": "stub", "width": 1920, "height": 1080, "bit_depth": 8})
			== {"matrix": 0, "transfer": 0, "primaries_bt2020": false, "full_range": false, "peak_nits": 1000.0,
			"peak_from": "default", "dovi": 0})
	var dv5 := Hdr.describe({"dolby_vision_profile": 5, "height": 2076, "color_range": "pc"})
	_check("Dolby Vision profile 5: IPT (dovi 1), PQ, BT.2020, limited", dv5["dovi"] == 1
			and dv5["transfer"] == Hdr.TRANSFER_PQ and dv5["primaries_bt2020"] and dv5["matrix"] == Hdr.MATRIX_2020
			and not dv5["full_range"])
	_check("profile 8 keeps its HDR10 base", Hdr.describe({"dolby_vision_profile": 8, "color_transfer": "smpte2084"})["dovi"] == 0)


## Draws one pixel of Y'CbCr (8-bit codes, limited range) through the video shader with `params`; returns the
## displayed colour (sRGB-encoded, as the viewport stores it).
func _draw(y: int, cb: int, cr: int, params: Dictionary) -> Color:
	var vp := SubViewport.new()
	vp.size = Vector2i(8, 8)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.own_world_3d = true
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.0
	cam.position = Vector3(0, 0, 1)
	vp.add_child(cam)
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2, 2)
	quad.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = VIDEO_SHADER
	var yi := Image.create_empty(4, 4, false, Image.FORMAT_L8)
	yi.fill(Color(y / 255.0, y / 255.0, y / 255.0))
	var ci := Image.create_empty(2, 2, false, Image.FORMAT_LA8)
	ci.fill(Color(cb / 255.0, cb / 255.0, cb / 255.0, cr / 255.0))
	mat.set_shader_parameter("y_tex", ImageTexture.create_from_image(yi))
	mat.set_shader_parameter("uv_tex", ImageTexture.create_from_image(ci))
	mat.set_shader_parameter("force_eye", 0)
	for k: String in params:
		mat.set_shader_parameter(k, params[k])
	quad.material_override = mat
	vp.add_child(quad)
	root.add_child(vp)
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var c := vp.get_texture().get_image().get_pixel(4, 4)
	vp.queue_free()
	return c


func _shader_checks() -> void:
	# SDR BT.709 grey: unchanged by this work (limited-range code 126 -> (126-16)/219 = 0.502).
	var c := await _draw(126, 128, 128, {})
	_near("SDR 709 grey", c.r, 110.0 / 219.0, 0.01)
	# BT.709 vs BT.2020 matrix on the same saturated code: the red channel differs as the coefficients say.
	var r709 := await _draw(81, 128, 180, {})
	var r2020 := await _draw(81, 128, 180, {"yuv_matrix": 2})
	var y := (81.0 - 16.0) / 219.0
	var crv := (180.0 - 128.0) / 224.0
	_near("709 red channel", r709.r, clampf(y + 1.5748 * crv, 0.0, 1.0), 0.01)
	_near("2020 red channel", r2020.r, clampf(y + 1.4746 * crv, 0.0, 1.0), 0.01)
	_near("601 red channel", (await _draw(81, 128, 180, {"yuv_matrix": 1})).r, clampf(y + 1.402 * crv, 0.0, 1.0), 0.01)
	# PQ grey at reference white (203 nits: PQ signal 0.5806 -> code 16 + 219 * 0.5806 = 143).
	var e := (143.0 - 16.0) / 219.0
	var lin := _pq_nits(e) / 203.0
	var on := await _draw(143, 128, 128, {"transfer": 1, "primaries_bt2020": true, "yuv_matrix": 2})
	_near("PQ reference white, tone mapped (%.3f)" % on.r, on.r, _srgb(_tone(lin, 1000.0 / 203.0, 1.0, 0.75)), 0.01)
	_check("PQ reference white sits below display white (%.3f)" % on.r, on.r > 0.85 and on.r < 0.98)
	var off := await _draw(143, 128, 128, {"transfer": 1, "primaries_bt2020": true, "yuv_matrix": 2, "tm_enabled": false})
	_check("tone mapping off: reference white clips to white (%.3f)" % off.r, off.r > 0.99)
	# A PQ highlight at 1000 nits (signal 0.7518 -> code 181) reaches display white; 100 nits stays linear-ish.
	var hi := await _draw(181, 128, 128, {"transfer": 1, "yuv_matrix": 2})
	_check("PQ 1000 nits -> about white (%.3f)" % hi.r, hi.r > 0.97)
	var mid := await _draw(127, 128, 128, {"transfer": 1, "yuv_matrix": 2})
	var lin_mid := _pq_nits((127.0 - 16.0) / 219.0) / 203.0
	_near("PQ about 100 nits, below the knee: unchanged (%.3f)" % mid.r, mid.r, _srgb(lin_mid), 0.01)
	var brighter := await _draw(127, 128, 128, {"transfer": 1, "yuv_matrix": 2, "tm_exposure": 2.0})
	_check("exposure +1 stop brightens (%.3f -> %.3f)" % [mid.r, brighter.r], brighter.r > mid.r + 0.1)
	# HLG reference white (signal 0.75 -> code 180): close to PQ's reference white.
	var hlg := await _draw(180, 128, 128, {"transfer": 2, "yuv_matrix": 2, "primaries_bt2020": true})
	_check("HLG reference white near PQ's (%.3f vs %.3f)" % [hlg.r, on.r], absf(hlg.r - on.r) < 0.05)
	# Grey stays grey through the BT.2020 -> BT.709 primaries.
	_check("grey stays neutral", absf(on.r - on.g) < 0.01 and absf(on.g - on.b) < 0.01)
	# Dolby Vision profile 5: reference white and a red as I'P'T' codes come out as the same light does through PQ
	# Y'CbCr (8-bit codes on both sides, so a little slack).
	var dv_params := {"dovi": 1, "transfer": 1, "primaries_bt2020": true, "yuv_matrix": 2}
	var w := _ipt_codes(Vector3(1.0, 1.0, 1.0))
	var dvw := await _draw(w[0], w[1], w[2], dv_params)
	_check("DV5 reference white matches PQ's (%.3f %.3f %.3f vs %.3f)" % [dvw.r, dvw.g, dvw.b, on.r],
			absf(dvw.r - on.r) < 0.03 and absf(dvw.g - on.r) < 0.03 and absf(dvw.b - on.r) < 0.03)
	var red := Vector3(0.5, 0.1, 0.1)
	var ri := _ipt_codes(red)
	var rp := _pq_codes(red)
	var dvr := await _draw(ri[0], ri[1], ri[2], dv_params)
	var pqr := await _draw(rp[0], rp[1], rp[2], {"transfer": 1, "primaries_bt2020": true, "yuv_matrix": 2})
	_check("DV5 red matches PQ's (%.3f %.3f %.3f vs %.3f %.3f %.3f)" % [dvr.r, dvr.g, dvr.b, pqr.r, pqr.g, pqr.b],
			absf(dvr.r - pqr.r) < 0.04 and absf(dvr.g - pqr.g) < 0.04 and absf(dvr.b - pqr.b) < 0.04 and dvr.r > dvr.g + 0.2)


## The node in the real main scene: the engine curve chosen for an HDR file when the engine has it, its parameters on
## the screen's material, and the target brightness and exposure moving display white.
func _node_checks() -> void:
	var main: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	for i in 5:
		await process_frame
	var hdr: Node = main.features.hdr
	var m: ShaderMaterial = main.screen.material
	hdr._info = {"color_transfer": "smpte2084", "color_primaries": "bt2020", "color_matrix": "bt2020nc", "max_cll": 482,
			"mastering_display_luminance": Vector2(0.0, 1000.0), "height": 1080}
	hdr.current = Hdr.describe(hdr._info)
	hdr._apply()
	if Hdr.engine_curve_available():
		_check("HDR file: the engine's BT.2390 curve (%s)" % hdr.text(), hdr.uses_engine_curve()
				and m.get_shader_parameter("tm_curve") == 1 and hdr.text().contains("BT.2390"))
		_check("peak from the engine: MaxCLL 482", is_equal_approx(hdr.current["peak_nits"], 482.0))
		_near("display white 203 nits", m.get_shader_parameter("tm_target_nits"), 203.0, 0.01)
		hdr.set_value("target_nits", 150.0)
		_near("target 150 nits", m.get_shader_parameter("tm_target_nits"), 150.0, 0.01)
		hdr.set_value("exposure", 1.0)
		_near("+1 stop halves display white", m.get_shader_parameter("tm_target_nits"), 75.0, 0.01)
	else:
		_check("no engine curve: the app's own", not hdr.uses_engine_curve() and m.get_shader_parameter("tm_curve") == 0)
		hdr.set_value("target_nits", 101.5)
		_near("target 101.5 nits doubles the exposure", m.get_shader_parameter("tm_exposure"), 2.0, 0.01)
	hdr.reset()
	hdr._info = {}
	hdr.current = Hdr.describe({})
	hdr._apply()
	_check("SDR: no engine curve", not hdr.uses_engine_curve() and m.get_shader_parameter("tm_curve") == 0)
	main.queue_free()
	await process_frame


## The shader's BT.2390 path against the engine's own CPU reference (MediaSource.tone_map_color) on PQ greys.
func _engine_curve_checks() -> void:
	var ms: Object = ClassDB.instantiate("MediaSource")
	var tm: Dictionary = ms.call("get_tone_mapping", {"color_transfer": "smpte2084", "color_primaries": "bt2020",
			"max_cll": 1000}, 203.0)
	var params := {"transfer": 1, "yuv_matrix": 2, "primaries_bt2020": true, "tm_curve": 1,
			"tm_src_min_pq": tm["source_min_pq"], "tm_src_max_pq": tm["source_max_pq"], "tm_max_lum": tm["max_luminance"],
			"tm_knee_start": tm["knee_start"], "tm_target_nits": tm["target_peak_nits"]}
	for code: int in [80, 127, 143, 165, 181, 200]:
		var e := (code - 16.0) / 219.0
		var want: Color = ms.call("tone_map_color", Color(e, e, e), tm)
		var got := await _draw(code, 128, 128, params)
		_near("BT.2390 grey, code %d: shader vs engine" % code, got.r, _srgb(want.r), 0.012)
	var top := await _draw(181, 128, 128, params)
	_check("the 1000 nit source peak reaches display white (%.3f)" % top.r, top.r > 0.98)


## PQ signal for a luminance in nits.
func _nits_to_pq(nits: float) -> float:
	var y := pow(maxf(nits, 0.0) / 10000.0, 0.1593017578125)
	return pow((0.8359375 + 18.8515625 * y) / (1.0 + 18.6875 * y), 78.84375)


## Linear BT.2020 RGB (1.0 = reference white) as the 8-bit limited-range Y'CbCr codes of a PQ BT.2020 file.
func _pq_codes(lin: Vector3) -> Array[int]:
	var e := Vector3(_nits_to_pq(lin.x * 203.0), _nits_to_pq(lin.y * 203.0), _nits_to_pq(lin.z * 203.0))
	var yy := 0.2627 * e.x + 0.6780 * e.y + 0.0593 * e.z
	return [roundi(16.0 + 219.0 * yy), roundi(128.0 + 224.0 * (e.z - yy) / 1.8814), roundi(128.0 + 224.0 * (e.x - yy) / 1.4746)]


## The same light as the 8-bit limited-range I'P'T' codes of a Dolby Vision profile 5 base layer: linear BT.2020 RGB to
## LMS, PQ, then the RPU's matrix the other way (the shader's constants inverted).
func _ipt_codes(lin: Vector3) -> Array[int]:
	var rgb := lin * 203.0
	var to_lms: Array[Vector3] = [Vector3(0.452503, 0.529895, 0.011438), Vector3(0.190754, 0.748533, 0.054708), Vector3(0.029845, 0.044782, 0.906641)]
	var lms := Vector3(to_lms[0].dot(rgb), to_lms[1].dot(rgb), to_lms[2].dot(rgb))
	var pq := Vector3(_nits_to_pq(lms.x), _nits_to_pq(lms.y), _nits_to_pq(lms.z))
	var to_ipt: Array[Vector3] = [Vector3(0.400128, 0.399890, 0.199981), Vector3(4.455344, -4.851464, 0.396120), Vector3(0.805668, 0.357180, -1.162847)]
	var ipt := Vector3(to_ipt[0].dot(pq), to_ipt[1].dot(pq), to_ipt[2].dot(pq))
	return [roundi(16.0 + 219.0 * ipt.x), roundi(128.0 + 224.0 * ipt.y), roundi(128.0 + 224.0 * ipt.z)]


func _pq_nits(e: float) -> float:
	var p := pow(e, 1.0 / 78.84375)
	return 10000.0 * pow(maxf(p - 0.8359375, 0.0) / (18.8515625 - 18.6875 * p), 1.0 / 0.1593017578125)


func _tone(m: float, peak: float, exposure: float, knee: float) -> float:
	m *= exposure
	peak *= exposure
	if m <= knee or peak <= 1.0:
		return m
	var d := 1.0 - knee
	var u := (m - knee) / d
	var uw := (peak - knee) / d
	return knee + d * u * (1.0 + u / (uw * uw)) / (1.0 + u)


func _srgb(c: float) -> float:
	c = clampf(c, 0.0, 1.0)
	return c * 12.92 if c < 0.0031308 else 1.055 * pow(c, 1.0 / 2.4) - 0.055


func _near(what: String, got: float, want: float, tol: float) -> void:
	_check("%s: %.4f ~ %.4f" % [what, got, want], absf(got - want) <= tol)


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL " + what)
	else:
		print("PASS " + what)
