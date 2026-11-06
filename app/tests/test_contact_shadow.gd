extends SceneTree

## The contact shadow (shaders/room_contact.gdshader) drawn by the Mobile renderer over a grey floor: near the quad's
## edge and outside it the floor is left as it is, under the part's middle it is darker by about the strength. The
## multiply blend it had halved the floor under the whole quad (the renderer divides what a shader writes by its
## luminance multiplier): a dark square under every object (the user, 2026-11-06).
## Run: VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a godot --xr-mode off --path app --script
## res://tests/test_contact_shadow.gd (headless: skipped, it needs a renderer)

const CONTACT := preload("res://shaders/room_contact.gdshader")
const VIEW := Vector2i(256, 256)

var _checks := 0
var _failures := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP render checks (headless)")
		print("Contact shadow test: 0 checks, all passed")
		quit(0)
		return
	var vp := SubViewport.new()
	vp.size = VIEW
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true
	root.add_child(vp)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	floor_mat.albedo_color = Color(0.5, 0.5, 0.5)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(8, 8)
	var floor_mi := MeshInstance3D.new()
	floor_mi.mesh = floor_mesh
	floor_mi.material_override = floor_mat
	vp.add_child(floor_mi)
	# As assistant_room.gd _add_contact_shadows(): a 2 x 2 quad scaled to the footprint plus its reach.
	var half := Vector2(0.4, 0.4)
	var reach := 0.2
	var m := ShaderMaterial.new()
	m.shader = CONTACT
	m.set_shader_parameter("half_size", half)
	m.set_shader_parameter("reach", reach)
	m.set_shader_parameter("strength", 0.45)
	var quad := PlaneMesh.new()
	quad.size = Vector2(2, 2)
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = m
	mi.position = Vector3(0, 0.004, 0)
	mi.scale = Vector3(half.x + reach, 1, half.y + reach)
	vp.add_child(mi)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.0
	cam.position = Vector3(0, 3, 0)
	cam.rotation_degrees = Vector3(-90, 0, 0)
	vp.add_child(cam)
	cam.current = true
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	# 2 m across 256 px: the quad reaches 0.6 m from the middle.
	var px_per_m := VIEW.x / 2.0
	var c := VIEW / 2
	var middle := img.get_pixelv(c).r
	var edge := img.get_pixel(c.x + int(0.58 * px_per_m), c.y).r
	var outside := img.get_pixel(c.x + int(0.9 * px_per_m), c.y).r
	var corner := img.get_pixel(c.x + int(0.58 * px_per_m), c.y + int(0.58 * px_per_m)).r
	print("  floor %.3f outside, %.3f at the edge, %.3f in the corner, %.3f in the middle" % [outside, edge, corner,
			middle])
	_check("the floor outside the quad (%.3f)" % outside, outside > 0.3)
	_check("the quad's edge leaves the floor as it is (%.3f against %.3f)" % [edge, outside],
			absf(edge - outside) < 0.02)
	_check("so does its corner (%.3f)" % corner, absf(corner - outside) < 0.02)
	# The strength (0.45) darkens in linear light: 0.55 of a mid-grey floor, about 0.76 of it in the image's sRGB values.
	var expected := Color(outside, outside, outside).srgb_to_linear().r * (1.0 - 0.45 * 0.97)
	var expected_srgb := Color(expected, expected, expected).linear_to_srgb().r
	_check("the middle is darker by the strength (%.3f, %.3f expected)" % [middle, expected_srgb],
			absf(middle - expected_srgb) < 0.03)
	print("Contact shadow test: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print(("PASS " if ok else "FAIL ") + what)
