extends SceneTree

## Tests for dual fisheye 360 (a 360 camera's raw frame: front lens in the left circle, back lens in the right one;
## scripts/play/dual_fisheye.gd, ProjectionMeshes.dual_fisheye, video.gdshader's blend):
##   - the mesh: each lens's place for known directions (ahead, behind, the seams, up), the back lens mirrored, the
##     seam weights, a lens's turn moving its picture the right way, and every vertex's two places inverted back to
##     its direction;
##   - the app: the stub pattern and a picture named like a 360 camera's open as dual fisheye with the right profile, the shader
##     switch, the profile's values (fov, seam, reset, kept per profile), the per-file profile choice, the Picture
##     tab's controls, the dev link's settings and the zoom lens's uniforms;
##   - with a renderer: looking at a seam of the pattern shows the front lens's colour on one side, the back lens's on
##     the other and their mix in between; ahead shows only the front, behind only the back.
## Settings are read-only. Run: godot --xr-mode off --path app --script res://tests/test_dual_fisheye.gd
## (--headless skips the render checks).

const ProjectionMeshes := preload("res://scripts/projection_meshes.gd")
const DualFisheye := preload("res://scripts/play/dual_fisheye.gd")
const FisheyeLens := preload("res://scripts/play/fisheye_lens.gd")
const VideoMode := preload("res://scripts/video_mode.gd")
const TestCard := preload("res://scripts/video/test_card.gd")
const DevCommands := preload("res://scripts/dev/dev_commands.gd")

var _failures := 0
var _checks := 0
var main: Node3D
## The dev link's built-in commands, kept alive while their settings are used.
var _builtins: RefCounted


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	await _frames(5)
	_mesh_checks()
	await _app_checks()
	if DisplayServer.get_name() == "headless":
		print("SKIP render checks (headless)")
	else:
		await _render_checks()
	print("test_dual_fisheye: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


static func _mapping(model: String, fov: float) -> Callable:
	return FisheyeLens.mapping(model, fov)


## A simple lens: both circles centred in their halves of a 2:1 frame, radius = half the height, 180 degrees + 2 * 10.
static func _lens(back_turn := Vector3.ZERO) -> Dictionary:
	var l := {
		"front": {"fov": 200.0, "cx": 0.25, "cy": 0.5, "radius": 0.5, "yaw": 0.0, "pitch": 0.0, "roll": 0.0},
		"back": {"fov": 200.0, "cx": 0.75, "cy": 0.5, "radius": 0.5, "yaw": back_turn.x, "pitch": back_turn.y,
				"roll": back_turn.z},
		"blend": 4.0, "model": "equidistant"}
	return l


## The vertex nearest a direction: [uv, uv2, weight].
static func _at(mesh: ArrayMesh, dir: Vector3) -> Array:
	var a := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var best := 0
	var best_dot := -2.0
	for i in verts.size():
		var d := verts[i].normalized().dot(dir.normalized())
		if d > best_dot:
			best_dot = d
			best = i
	return [(a[Mesh.ARRAY_TEX_UV] as PackedVector2Array)[best], (a[Mesh.ARRAY_TEX_UV2] as PackedVector2Array)[best],
			(a[Mesh.ARRAY_COLOR] as PackedColorArray)[best].r]


func _mesh_checks() -> void:
	var t0 := Time.get_ticks_usec()
	var mesh := ProjectionMeshes.dual_fisheye(_lens(), 20.0, 2.0, _mapping)
	var a := mesh.surface_get_arrays(0)
	print("mesh: %d vertices, built in %.1f ms" % [(a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),
			(Time.get_ticks_usec() - t0) / 1000.0])
	_check("mesh has two UV sets and a weight", a[Mesh.ARRAY_TEX_UV2] != null and a[Mesh.ARRAY_COLOR] != null)
	# Straight ahead: the front circle's centre, all front.
	var ahead := _at(mesh, Vector3.FORWARD)
	_near_v("ahead: front circle's centre", ahead[0], Vector2(0.25, 0.5))
	_near("ahead: front weight 1", ahead[2], 1.0, 1e-3)
	# Straight behind: the back circle's centre, all back.
	var behind := _at(mesh, Vector3.BACK)
	_near_v("behind: back circle's centre", behind[1], Vector2(0.75, 0.5))
	_near("behind: front weight 0", behind[2], 0.0, 1e-3)
	# The right seam (+X, 90 degrees off both axes): on the front circle's right, on the back circle's LEFT (the back
	# lens looks the other way), weight one half.
	var r := 0.25 * 90.0 / 100.0
	var right := _at(mesh, Vector3.RIGHT)
	_near_v("right seam: front circle's right edge", right[0], Vector2(0.25 + r, 0.5))
	_near_v("right seam: back circle's left edge (mirrored)", right[1], Vector2(0.75 - r, 0.5))
	_near("right seam: half and half", right[2], 0.5, 0.02)
	var left := _at(mesh, Vector3.LEFT)
	_near_v("left seam: front circle's left edge", left[0], Vector2(0.25 - r, 0.5))
	_near_v("left seam: back circle's right edge", left[1], Vector2(0.75 + r, 0.5))
	# Up: the top of both circles (the circles are upright).
	var up := _at(mesh, Vector3.UP)
	_near_v("up: front circle's top", up[0], Vector2(0.25, 0.5 - 0.5 * 90.0 / 100.0))
	_near_v("up: back circle's top", up[1], Vector2(0.75, 0.5 - 0.5 * 90.0 / 100.0))
	# The band: 4 degrees either side of 90.
	var t := deg_to_rad(85.0)
	_near("5 degrees before the seam: all front", _at(mesh, Vector3(sin(t), 0, -cos(t)))[2], 1.0, 1e-3)
	t = deg_to_rad(95.0)
	_near("5 degrees past the seam: all back", _at(mesh, Vector3(sin(t), 0, -cos(t)))[2], 0.0, 1e-3)
	t = deg_to_rad(88.0)
	_near("2 degrees before the seam: smoothstep", _at(mesh, Vector3(sin(t), 0, -cos(t)))[2],
			1.0 - smoothstep(86.0, 94.0, 88.0), 0.01)
	# A turn of the back lens: yaw +2 degrees turns the lens's axis (+Z) towards +X, so what it sees straight along its
	# axis is now 2 degrees round to the right of straight behind.
	var turned := ProjectionMeshes.dual_fisheye(_lens(Vector3(2.0, 0.0, 0.0)), 20.0, 2.0, _mapping)
	var yaw := deg_to_rad(2.0)
	_near_v("back yaw 2: its centre is 2 degrees to the right of behind", _at(turned, Vector3(sin(yaw), 0, cos(yaw)))[1],
			Vector2(0.75, 0.5))
	# Every vertex's places, inverted with the equidistant model, give back its direction (both lenses, a turned lens).
	var lens := _lens(Vector3(1.5, -0.7, 2.0))
	var m2 := ProjectionMeshes.dual_fisheye(lens, 20.0, 2.0, _mapping)
	var a2 := m2.surface_get_arrays(0)
	var worst := 0.0
	var verts: PackedVector3Array = a2[Mesh.ARRAY_VERTEX]
	for i in range(0, verts.size(), 7):
		var d := verts[i].normalized()
		var w: float = (a2[Mesh.ARRAY_COLOR] as PackedColorArray)[i].r
		if w > 0.0:
			worst = maxf(worst, rad_to_deg(d.angle_to(_unproject((a2[Mesh.ARRAY_TEX_UV] as PackedVector2Array)[i],
					lens["front"], false))))
		if w < 1.0:
			worst = maxf(worst, rad_to_deg(d.angle_to(_unproject((a2[Mesh.ARRAY_TEX_UV2] as PackedVector2Array)[i],
					lens["back"], true))))
	_check("every used place maps back to its direction (worst %.4f degrees)" % worst, worst < 0.01)
	# The ring density through the band (finer rings there).
	var ring_count := verts.size() / 129
	_check("rings: the 2.8 degree grid plus the band's (%d)" % ring_count, ring_count >= 64 + 1 + 14)


## A place in the frame (2:1) -> the world direction it shows, for one lens (equidistant).
static func _unproject(uv: Vector2, l: Dictionary, back: bool) -> Vector3:
	var dx := (uv.x - float(l["cx"])) * 2.0 / float(l["radius"])
	var dy := -(uv.y - float(l["cy"])) / float(l["radius"])
	var theta := Vector2(dx, dy).length() * deg_to_rad(float(l["fov"]) * 0.5)
	var phi := atan2(dy, dx)
	var local := Vector3(sin(theta) * cos(phi), sin(theta) * sin(phi), cos(theta))
	var lens_dir := Vector3(-local.x, local.y, local.z) if back else Vector3(local.x, local.y, -local.z)
	return ProjectionMeshes.lens_basis(l) * lens_dir


func _app_checks() -> void:
	var f: Node = main.features
	var dual: Node = f.dual_fisheye
	main.set_environment("void")
	main.open_path("stub://dualfisheye_mono")
	await _frames(5)
	_check("pattern opens as dual fisheye", main.mode.to_id() == "dualfisheye_mono")
	var mat: ShaderMaterial = main.screen.material
	_check("shader: dual fisheye on, mono, no circle mask", bool(mat.get_shader_parameter("dual_fisheye"))
			and int(mat.get_shader_parameter("stereo_layout")) == 0 and not bool(mat.get_shader_parameter("circle_mask")))
	_check("not a 360 camera name: the generic profile", dual.profile == "generic")
	var before: Mesh = main.screen._sphere.mesh
	_check("the sphere carries the dual mesh", before != null and before.surface_get_format(0) & Mesh.ARRAY_FORMAT_TEX_UV2)
	dual.set_value("fov", 200.0)
	await _frames(1)
	_check("fov sets both lenses, rebuilds the mesh", main.screen._sphere.mesh != before
			and is_equal_approx(dual.values()["back"]["fov"], 200.0) and is_equal_approx(dual.fov(), 200.0))
	_check("kept for the profile", is_equal_approx(float(main.settings.get_value("dual_fisheye_generic", "front_fov", 0.0)), 200.0))
	dual.set_value("seam", 9.0)
	_check("seam: the back lens's yaw, clamped to 5", is_equal_approx(dual.seam(), 5.0)
			and is_equal_approx(dual.values()["back"]["yaw"], 5.0))
	dual.set_values({"back": {"roll": -0.5}, "blend": 2.0})
	_check("set_values: nested parts", is_equal_approx(dual.values()["back"]["roll"], -0.5)
			and is_equal_approx(dual.values()["blend"], 2.0))
	dual.reset()
	_check("reset: the profile's own values", dual.values() == DualFisheye.defaults("generic")
			and main.settings.get_keys("dual_fisheye_generic").is_empty())
	# The stub test card draws the generic profile's circles.
	_check("the card uses the generic profile", is_equal_approx(DualFisheye.DEFAULTS["generic"]["front"]["fov"],
			main.screen.get_dual_lens()["front"]["fov"]))
	# Per-file profile choice.
	dual.set_profile("camera360")
	_check("profile chosen for the file", str(main.settings.get_value("dual_fisheye_files", dual._key, "")) == "camera360"
			and is_equal_approx(main.screen.get_dual_lens()["back"]["roll"], DualFisheye.DEFAULTS["camera360"]["back"]["roll"]))
	main.open_path("stub://flat_mono")
	await _frames(3)
	main.open_path("stub://dualfisheye_mono")
	await _frames(3)
	_check("profile restored on reopening", dual.profile == "camera360")
	dual.set_profile("generic")
	_check("back to the automatic choice: the per-file value erased", not main.settings.has_value("dual_fisheye_files", dual._key))

	# The Picture tab: the mode's diagram, the lens controls shown, the layouts other than mono disabled.
	var tab: Node = _find_named(main, "Picture")
	if tab != null:
		tab.call("set_mode", main.mode, "")
		var box: Control = tab.get("_dual_box")
		_check("Picture tab: dual lens controls shown", box != null and box.visible)
		var buttons: Array = tab.get("_layout_buttons")
		_check("Picture tab: only mono layout", buttons.size() == 3 and not buttons[0].disabled and buttons[1].disabled
				and buttons[2].disabled)
		var projections: Array = tab.get("_projection_buttons")
		_check("Picture tab: the dual fisheye diagram chosen", projections.size() == 5 and projections[4].button_pressed)
		var rows: Dictionary = tab.get("_rows")
		var slider: HSlider = null
		for c in (rows["dual_seam"] as Node).get_children():
			if c is HSlider:
				slider = c
		if slider != null:
			slider.value = 1.5
			_check("Picture tab: the seam slider nudges the back lens", is_equal_approx(dual.seam(), 1.5))
		dual.reset()
		main.open_path("stub://360_mono")
		await _frames(3)
		_check("Picture tab: lens controls hidden for 360", not box.visible)
		main.open_path("stub://dualfisheye_mono")
		await _frames(3)
	else:
		_check("Picture tab found", false)

	# The dev link's settings (registered here as the dev link's command host does, against this main).
	if not DevCommands.has_setting("dual_fisheye_fov"):
		var host_script := GDScript.new()
		host_script.source_code = "extends Node\nvar main: Node\n"
		host_script.reload()
		var host: Node = host_script.new()
		host.set("main", main)
		root.add_child(host)
		_builtins = (load("res://scripts/dev/builtin_commands.gd") as GDScript).new()
		_builtins.set("host", host)
		_builtins.call("register_all")
	if DevCommands.has_setting("dual_fisheye_fov"):
		_check("dev link: set fov", DevCommands.set_setting("dual_fisheye_fov", 192.5) == ""
				and is_equal_approx(float(DevCommands.get_setting("dual_fisheye_fov")), 192.5))
		_check("dev link: lens values", DevCommands.set_setting("dual_fisheye_lens", {"back": {"pitch": 0.4}}) == ""
				and is_equal_approx((DevCommands.get_setting("dual_fisheye_lens") as Dictionary)["back"]["pitch"], 0.4))
		_check("dev link: profile enum", DevCommands.set_setting("dual_fisheye_profile", "nope") != "")
		dual.reset()
	else:
		print("SKIP dev link checks (no dev link in this run)")

	# The zoom lens's uniforms follow the lens values.
	var u: Dictionary = DualFisheye.uniforms(DualFisheye.defaults("camera360"), 2.0)
	var gb: Dictionary = DualFisheye.DEFAULTS["camera360"]["back"]
	var gr: float = gb["radius"]
	_check("zoom lens uniforms", (u["dfe_back_circle"] as Vector4).is_equal_approx(Vector4(gb["cx"], gb["cy"], gr * 0.5, gr))
			and is_equal_approx(u["dfe_front_half_fov"], deg_to_rad(97.5)))

	# 360 camera names: dual fisheye; the photo or the video profile by the frame's width once known (the stills are
	# 5792 wide, the video 4096), by the extension before.
	_check("360 camera names: the profile by width, else extension", DualFisheye.auto_profile("/x/360_0042.MP4") == "camera360"
			and DualFisheye.auto_profile("/x/360_0010.JPG") == "camera360_photo"
			and DualFisheye.auto_profile("/x/360_0010.JPG", "generic", 5792) == "camera360_photo"
			and DualFisheye.auto_profile("/x/360_0042.png", "generic", 4096) == "camera360"
			and DualFisheye.auto_profile("/x/walk_dfe.mp4") == "generic")
	var dir := OS.get_user_data_dir().path_join("dfe_test")
	DirAccess.make_dir_recursive_absolute(dir)
	for c: Array in [["360_0001.png", 5792, "camera360_photo"], ["360_0002.png", 1024, "camera360"]]:
		var path := dir.path_join(c[0])
		var img := Image.create_empty(c[1], c[1] / 2, false, Image.FORMAT_RGB8)
		img.fill(Color(0.2, 0.3, 0.4))
		img.save_png(path)
		main.open_path(path)
		await _until(func() -> bool: return main.player.source != null and main.player.source.has_frame(), 20.0)
		await _frames(3)
		_check("360 camera picture %d wide: dual fisheye (%s), %s (%s)" % [c[1], main.mode.to_id(), c[2], dual.profile],
				main.mode.to_id() == "dualfisheye_mono" and dual.profile == c[2])
		main.open_path("stub://flat_mono")
		await _frames(2)
		DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(dir)


func _render_checks() -> void:
	main.set_environment("void")
	main.open_path("stub://dualfisheye_mono")
	await _frames(8)
	if main.ui != null and main.ui.has_method("hide_panel"):
		main.ui.hide_panel()
	var front_tint := TestCard.TINT_LEFT
	var back_tint := TestCard.TINT_RIGHT
	# Ahead: the front lens's tint; behind: the back lens's; at the right seam, both and a mix between. Each colour is
	# a small patch's median, so the pattern's thin rings and spokes don't decide it.
	for look: Array in [[Vector2(15, 45), "ahead", 1.0], [Vector2(195, 45), "behind", 0.0]]:
		main._look = look[0]
		main._apply_look()
		await _frames(3)
		await RenderingServer.frame_post_draw
		var shot := root.get_texture().get_image()
		var c := _patch(shot, shot.get_width() / 2, shot.get_height() / 2)
		var want: Color = front_tint if look[2] > 0.5 else back_tint
		_check("%s shows the %s lens (%s)" % [look[1], "front" if look[2] > 0.5 else "back", c], _close(c, want, 0.08))
	# The right seam, looking 30 degrees up (away from the pattern's horizon band and labels).
	main._look = Vector2(90, 30)
	main._apply_look()
	await _frames(3)
	await RenderingServer.frame_post_draw
	var shot := root.get_texture().get_image()
	var y := shot.get_height() / 2
	var w := shot.get_width()
	var lft := _patch(shot, w / 8, y)
	var rgt := _patch(shot, w * 7 / 8, y)
	_check("seam: front lens on the left (%s)" % lft, _close(lft, front_tint, 0.08))
	_check("seam: back lens on the right (%s)" % rgt, _close(rgt, back_tint, 0.08))
	# Inside the band, either side of the pattern's bold 90 degree rings (which meet on the seam): the two tints mixed
	# by the smoothstep weight. The pixel for an angle off straight ahead comes from the camera's rays.
	var blend: float = main.screen.get_dual_lens()["blend"]
	var cam: Camera3D = main.camera
	for off in [-1.2, 1.2]:
		var want_theta: float = 90.0 + off
		var best_x := 0
		var best := 999.0
		for x in w:
			var d := cam.project_ray_normal(Vector2(x, y))
			var e := absf(rad_to_deg(acos(clampf(-d.z, -1.0, 1.0))) - want_theta)
			if e < best:
				best = e
				best_x = x
		var weight := 1.0 - smoothstep(90.0 - blend, 90.0 + blend, want_theta)
		var got := _patch(shot, best_x, y, 2)
		var mix := back_tint.lerp(front_tint, weight)
		_check("seam band at %.1f degrees: %.2f front (%s ~ %s)" % [want_theta, weight, got, mix], _close(got, mix, 0.05)
				and not _close(got, front_tint, 0.03) and not _close(got, back_tint, 0.03))
	# The zoom lens maps the same way: aimed ahead it shows the front lens, aimed behind the back one.
	var z: Node = main.features.zoom_lens
	for look: Array in [[Vector2(15, 45), front_tint, "front"], [Vector2(195, 45), back_tint, "back"]]:
		main._look = look[0]
		main._apply_look()
		z.begin(null)
		z.set_magnification(1.5)
		await _frames(3)
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var c := _patch(img, img.get_width() / 2, img.get_height() / 2)
		_check("zoom lens aimed at the %s lens shows it (%s)" % [look[2], c], _close(c, look[1], 0.08)
				and int((z.get("_material") as ShaderMaterial).get_shader_parameter("projection")) == 3)
		z.end()
	z.set_magnification(3.0)
	main._look = Vector2.ZERO
	main._apply_look()


## The median colour of the pixels within `half` of (x, y) (an 11 x 11 patch by default), per channel.
static func _patch(img: Image, x: int, y: int, half := 5) -> Color:
	var ch: Array = [[], [], []]
	for dy in range(-half, half + 1):
		for dx in range(-half, half + 1):
			var p := img.get_pixel(clampi(x + dx, 0, img.get_width() - 1), clampi(y + dy, 0, img.get_height() - 1))
			ch[0].append(p.r)
			ch[1].append(p.g)
			ch[2].append(p.b)
	var mid: int = ch[0].size() / 2
	for a: Array in ch:
		a.sort()
	return Color(ch[0][mid], ch[1][mid], ch[2][mid])


## Colours compared in the picture's gamma-encoded values (the screen shows the tint through sRGB).
static func _close(a: Color, b: Color, tol: float) -> bool:
	return absf(a.r - b.r) < tol and absf(a.g - b.g) < tol and absf(a.b - b.b) < tol


func _find_named(n: Node, node_name: String) -> Node:
	if n.name == node_name and n.has_method("set_mode"):
		return n
	for c in n.get_children():
		var found := _find_named(c, node_name)
		if found != null:
			return found
	return null


func _until(cond: Callable, seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await process_frame


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _near(what: String, got: float, want: float, tol: float) -> void:
	_check("%s: %.4f ~ %.4f" % [what, got, want], absf(got - want) <= tol)


func _near_v(what: String, got: Vector2, want: Vector2) -> void:
	_check("%s: %s ~ %s" % [what, got, want], got.distance_to(want) <= 0.004)


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL ", what)
	else:
		print("PASS ", what)
