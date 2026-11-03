extends SceneTree

## Tests for the picture group: fisheye lens profiles (#73), per-folder mode rules (#83), the light sharpen (#90) and
## the GPU deinterlace (#95). The lens maths, the mesh rebuild and the folder rules run anywhere; the sharpen and
## deinterlace checks draw known pictures through the real video shader into a small viewport, so they need a renderer
## (skipped with --headless). Settings are read-only.
## Run: godot --xr-mode off --path app --script res://tests/test_picture.gd

const FisheyeLens := preload("res://scripts/play/fisheye_lens.gd")
const FolderModes := preload("res://scripts/play/folder_modes.gd")
const Deinterlace := preload("res://scripts/play/deinterlace.gd")
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
	_lens_maths()
	await _lens_mesh()
	await _folder_rules()
	_deinterlace_script()
	if DisplayServer.get_name() == "headless":
		print("SKIP shader checks (headless)")
	else:
		await _shader_checks()
	print("test_picture: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _lens_maths() -> void:
	var half := deg_to_rad(100.0)
	var eq := FisheyeLens.mapping("equidistant", 200.0)
	_near("equidistant: half way in angle is half way out", eq.call(half * 0.5), 0.5, 1e-5)
	_near("equidistant: edge", eq.call(half), 1.0, 1e-5)
	for id: String in ["equisolid", "stereographic", "polynomial"]:
		_near("%s: edge of the view at the circle's edge" % id, FisheyeLens.mapping(id, 200.0).call(half), 1.0, 1e-5)
	var es := FisheyeLens.mapping("equisolid", 200.0)
	_near("equisolid: 2 sin(t/2), normalised", es.call(half * 0.5), sin(half * 0.25) / sin(half * 0.5), 1e-5)
	_check("equisolid puts the middle further out than equidistant", es.call(half * 0.5) > 0.5)
	var st := FisheyeLens.mapping("stereographic", 220.0)
	var h220 := deg_to_rad(110.0)
	_near("stereographic 220: 2 tan(t/2), normalised", st.call(h220 * 0.5), tan(h220 * 0.25) / tan(h220 * 0.5), 1e-5)
	_check("stereographic puts the middle nearer the centre", st.call(h220 * 0.5) < 0.5)
	_near("polynomial with zero coefficients is equidistant", FisheyeLens.mapping("polynomial", 200.0).call(0.7),
			0.7 / half, 1e-5)
	var k := PackedFloat32Array([-0.05, 0.004, 0.0, 0.0])
	var p := FisheyeLens.mapping("polynomial", 200.0, k)
	var g := func(t: float) -> float: return t * (1.0 + k[0] * t * t + k[1] * pow(t, 4))
	_near("polynomial k1, k2", p.call(0.9), g.call(0.9) / g.call(half), 1e-5)
	_check("mapping is monotonic (all profiles, 190-220 degrees)", _monotonic())
	_check("unknown profile: equidistant", is_equal_approx(FisheyeLens.mapping("nope", 180.0).call(PI / 4.0), 0.5))


func _monotonic() -> bool:
	for fov: float in [190.0, 200.0, 220.0]:
		for id: String in FisheyeLens.PROFILES:
			var m := FisheyeLens.mapping(id, fov, PackedFloat32Array([-0.03, 0.002, 0.0, 0.0]))
			var last := -1.0
			for i in 51:
				var r: float = m.call(deg_to_rad(fov * 0.5) * i / 50.0)
				if r <= last:
					return false
				last = r
	return true


## The radius (0..1 of the image circle) of the fisheye mesh's ring half way out, from the vertex at phi = 0.
func _mid_ring() -> Array:
	var mesh: Mesh = main.screen._sphere.mesh
	var arrays := mesh.surface_get_arrays(0)
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var rings := uvs.size() / 129 - 1
	var i := rings / 2
	var v := verts[i * 129]
	return [(uvs[i * 129].x - 0.5) * 2.0, acos(clampf(-v.normalized().z, -1.0, 1.0))]


func _lens_mesh() -> void:
	var f: Node = main.features
	main.set_environment("void")
	main.open_path("stub://fisheye_sbs_fov200")
	await _frames(5)
	_check("fisheye 200 open", main.mode.to_id() == "fisheye_sbs_fov200")
	_check("default profile: equidistant", f.lens.profile == "equidistant")
	var before: Mesh = main.screen._sphere.mesh
	var r0: Array = _mid_ring()
	_near("equidistant mesh: ring radius = theta / half", r0[0], r0[1] / deg_to_rad(100.0), 1e-3)
	f.lens.set_profile("equisolid")
	await _frames(1)
	var r1: Array = _mid_ring()
	_check("profile change rebuilds the mesh", main.screen._sphere.mesh != before)
	_near("equisolid mesh ring", r1[0], sin(r1[1] * 0.5) / sin(deg_to_rad(50.0)), 1e-3)
	_check("profile remembered for the file", main.settings.get_value("lens_files", f.lens._key, "") == "equisolid")
	f.lens.set_coefficients(PackedFloat32Array([-0.05, 0.004]))
	f.lens.set_profile("polynomial")
	var r2: Array = _mid_ring()
	var t: float = r2[1]
	var half := deg_to_rad(100.0)
	_near("polynomial mesh ring", r2[0], (t * (1 - 0.05 * t * t + 0.004 * pow(t, 4)))
			/ (half * (1 - 0.05 * half * half + 0.004 * pow(half, 4))), 1e-3)
	main.open_path("stub://flat_mono")
	await _frames(3)
	main.open_path("stub://fisheye_sbs_fov200")
	await _frames(3)
	_check("profile restored on reopening the file", f.lens.profile == "polynomial")
	f.lens.set_profile("equidistant")
	f.lens.set_coefficients(PackedFloat32Array())
	_check("back to the default: per-file value erased", not main.settings.has_value("lens_files", f.lens._key))


func _folder_rules() -> void:
	var f: Node = main.features
	_check("normalise", FolderModes.normalise("C:\\Films\\VR") == "C:/Films/VR/" and FolderModes.normalise("/a/") == "/a/")
	f.folder_modes.set_rule("/media/VR", "180_sbs")
	f.folder_modes.set_rule("/media/VR/360", "360_tb")
	_check("rule for a file in the folder", f.folder_modes.mode_for("/media/VR/clip.mp4") == "180_sbs")
	_check("deepest folder wins", f.folder_modes.mode_for("/media/VR/360/a/clip.mp4") == "360_tb")
	_check("no rule outside", f.folder_modes.mode_for("/media/Films/clip.mp4") == "")
	_check("a folder name prefix is not the folder", f.folder_modes.mode_for("/media/VRX/clip.mp4") == "")
	_check("no rule for test patterns", f.folder_modes.mode_for("stub://flat_mono") == "")
	f.folder_modes.clear_rule("/media/VR/360/")
	_check("cleared", f.folder_modes.mode_for("/media/VR/360/clip.mp4") == "180_sbs")
	f.folder_modes.clear_rule("/media/VR")
	_check("all cleared: setting erased", not main.settings.has_value("folder_modes", "rules"))
	# Through main: a file with no mode of its own opens in its folder's rule.
	var dir := OS.get_user_data_dir().path_join("test_picture/VR")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("clip.mp4")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("not a video")
	file.close()
	f.folder_modes.set_rule(dir, "180_sbs")
	main.open_path(path)
	await _until(func() -> bool: return main.current_path == path and main.mode_source == "folder", 5.0)
	_check("main opens the file in the folder's mode (%s, %s)" % [main.mode.to_id(), main.mode_source],
			main.mode.to_id() == "180_sbs" and main.mode_source == "folder")
	main.open_path("stub://flat_mono")
	await _frames(3)
	f.folder_modes.clear_rule(dir)
	DirAccess.remove_absolute(path)


func _deinterlace_script() -> void:
	var d: Node = main.features.deinterlace
	_check("deinterlace off by default", d.mode == "off" and d.active() == 0)
	_check("field at the start of a frame: the first", Deinterlace.field_at(0.0, 25.0, true) == 0)
	_check("field in the second half: the second", Deinterlace.field_at(0.03, 25.0, true) == 1)
	_check("bottom first", Deinterlace.field_at(0.01, 25.0, false) == 1 and Deinterlace.field_at(0.03, 25.0, false) == 0)
	_check("field order: tt and bt show the top field first, bb and tb the bottom one",
			Deinterlace.top_field_first("tt") and Deinterlace.top_field_first("bt") and not Deinterlace.top_field_first("bb")
			and not Deinterlace.top_field_first("TB") and Deinterlace.top_field_first(""))
	_check("field order: interlaced or not", Deinterlace.is_interlaced("tb") and not Deinterlace.is_interlaced("progressive")
			and not Deinterlace.is_interlaced(""))
	d.set_mode("bob")
	_check("bob sets the shader", d.active() == 1 and main.screen.material.get_shader_parameter("deinterlace") == 1)
	d.set_mode("auto")
	_check("auto on a progressive pattern: off", d.active() == 0)
	d.set_mode("edge")
	_check("edge", d.active() == 2)
	d.set_mode("off")
	_check("off clears the setting and the shader", not main.settings.has_value("picture", "deinterlace")
			and main.screen.material.get_shader_parameter("deinterlace") == 0)
	main.features.picture.set_value("sharpen", 0.5)
	_check("sharpen reaches the shader", is_equal_approx(main.screen.material.get_shader_parameter("pc_sharpen"), 0.5))
	main.features.picture.set_value("sharpen", 0.0)


## Draws an 8x8 luma picture (8-bit limited-range codes, one per pixel, rows top first) through the video shader;
## returns the displayed luma per pixel (0..1 of the limited range).
func _draw(codes: Callable, params: Dictionary) -> Array:
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
	mesh.size = Vector2(1, 1)
	quad.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = VIDEO_SHADER
	var yi := Image.create_empty(8, 8, false, Image.FORMAT_L8)
	for y in 8:
		for x in 8:
			var c: float = float(codes.call(x, y)) / 255.0
			yi.set_pixel(x, y, Color(c, c, c))
	var ci := Image.create_empty(4, 4, false, Image.FORMAT_LA8)
	ci.fill(Color(128 / 255.0, 128 / 255.0, 128 / 255.0, 128 / 255.0))
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
	var img := vp.get_texture().get_image()
	var out := []
	for y in 8:
		var row := []
		for x in 8:
			row.append(img.get_pixel(x, y).g)
		out.append(row)
	vp.queue_free()
	return out


func _shader_checks() -> void:
	var stripes := func(_x: int, y: int) -> int: return 235 if y % 2 == 0 else 16
	var off: Array = await _draw(stripes, {})
	_check("off: stripes as they are (%.2f, %.2f)" % [off[2][3], off[3][3]], off[2][3] > 0.97 and off[3][3] < 0.03)
	var bob0: Array = await _draw(stripes, {"deinterlace": 1, "field": 0})
	_check("bob, even field: the odd lines rebuilt white (%.2f)" % bob0[3][3], bob0[3][3] > 0.97 and bob0[4][3] > 0.97)
	var bob1: Array = await _draw(stripes, {"deinterlace": 1, "field": 1})
	_check("bob, odd field: the even lines rebuilt black (%.2f)" % bob1[4][3], bob1[4][3] < 0.03 and bob1[3][3] < 0.03)
	# A diagonal edge (white right of x = y): bob blurs it to grey on the rebuilt line; edge follows the diagonal.
	var diag := func(x: int, y: int) -> int: return 235 if x > y else 16
	var bob: Array = await _draw(diag, {"deinterlace": 1, "field": 0})
	var edge: Array = await _draw(diag, {"deinterlace": 2, "field": 0})
	_check("bob on a diagonal: grey on the rebuilt line (%.2f, %.2f)" % [bob[3][3], bob[3][4]],
			absf(bob[3][3] - 0.5) < 0.05 and absf(bob[3][4] - 0.5) < 0.05)
	_check("edge on a diagonal: the true values (%.2f, %.2f)" % [edge[3][3], edge[3][4]],
			edge[3][3] < 0.03 and edge[3][4] > 0.97)
	_check("edge keeps the shown field's lines", edge[2][3] > 0.97 and edge[2][2] < 0.03)
	# Sharpen: an 80 / 160 step in x. Off: unchanged; on: overshoot on both sides of the step, flat areas unchanged.
	var step := func(x: int, _y: int) -> int: return 160 if x >= 4 else 80
	var flat: Array = await _draw(step, {})
	var sharp: Array = await _draw(step, {"pc_sharpen": 1.0})
	var lo := (80.0 - 16.0) / 219.0
	var hi := (160.0 - 16.0) / 219.0
	var over := 0.25 * (hi - lo)
	_near("sharpen off: unchanged", flat[4][4], hi, 0.01)
	_near("sharpen on: bright side of the step", sharp[4][4], hi + over, 0.015)
	_near("sharpen on: dark side of the step", sharp[4][3], lo - over, 0.015)
	_near("sharpen on: flat area unchanged", sharp[4][6], hi, 0.01)


func _until(cond: Callable, seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await process_frame


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _near(what: String, got: float, want: float, tol: float) -> void:
	_check("%s: %.4f ~ %.4f" % [what, got, want], absf(got - want) <= tol)


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL ", what)
