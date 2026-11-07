extends RefCounted

## The room tests' render (tests/test_room_bathysphere.gd, test_room_crater.gd; lavapipe, skipped headless): a shipped
## room drawn by the Mobile renderer from its own seat, with a stand-in picture on the default screen (a sunset's
## colours) and the screen's light on the room as the bias light gives it. The pictures are kept in user://room_render/
## (or $ENV_SHOTS). Not a test itself (no test_ prefix). Static; preload to use.

const EnvRoom := preload("res://scripts/env/env_room.gd")
const VIEW := Vector2i(960, 540)
const OUT := "user://room_render"


static func has_renderer() -> bool:
	return DisplayServer.get_name() != "headless"


## The screen's light as the bias light gives it: warm on the left, cool on the right; the room's light level.
static func set_light(screen_center: Vector3, env_light: float) -> void:
	RenderingServer.global_shader_parameter_set("env_light", env_light)
	RenderingServer.global_shader_parameter_set("screen_center", screen_center)
	RenderingServer.global_shader_parameter_set("screen_glow", 1.0)
	RenderingServer.global_shader_parameter_set("screen_axis", Vector3(0.333, 0.0, 0.0))
	var img := Image.create_empty(4, 2, false, Image.FORMAT_RGBA8)
	for x in 4:
		for y in 2:
			img.set_pixel(x, y, Color(0.85, 0.5, 0.3).lerp(Color(0.3, 0.5, 0.85), x / 3.0))
	RenderingServer.global_shader_parameter_set("screen_thumb", ImageTexture.create_from_image(img))
	RenderingServer.global_shader_parameter_set("screen_tint", 1.0)


## The room in a viewport of its own with a camera: [viewport, camera, room]. The host steps only when asked.
static func open(tree: SceneTree, doc: Dictionary, fov := 90.0) -> Array:
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
	var cam := Camera3D.new()
	cam.fov = fov
	cam.near = 0.05
	cam.far = 200.0
	vp.add_child(cam)
	cam.current = true
	tree.root.add_child(vp)
	var room: Node3D = EnvRoom.new()
	room.doc = doc
	vp.add_child(room)
	room.host.auto = false
	var s: Dictionary = doc["screen"]
	var size := Vector2(float(s["size"][0]), float(s["size"][1]))
	room.host.on_screen_changed(room.get_screen_anchor(), size)
	# The stand-in picture: a sunset's colours, unshaded, on the default screen.
	var pic := Image.create_empty(8, 4, false, Image.FORMAT_RGBA8)
	for x in 8:
		for y in 4:
			pic.set_pixel(x, y, Color(0.95, 0.62, 0.32).lerp(Color(0.25, 0.42, 0.8), y / 3.0).lerp(
					Color(0.9, 0.85, 0.7), 0.25 * float(x % 3 == 0)))
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = ImageTexture.create_from_image(pic)
	var quad := QuadMesh.new()
	quad.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = mat
	mi.position = Vector3(float(s["center"][0]), float(s["center"][1]), float(s["center"][2]))
	room.add_child(mi)
	return [vp, cam, room]


## A picture from `at` towards `look`, saved as <name>.png. Returns the image.
static func shot(tree: SceneTree, vc: Array, at: Vector3, look: Vector3, name: String) -> Image:
	(vc[1] as Camera3D).look_at_from_position(at, look)
	for i in 4:
		await tree.process_frame
	await RenderingServer.frame_post_draw
	var img := (vc[0] as SubViewport).get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var out := OS.get_environment("ENV_SHOTS")
	if out == "":
		DirAccess.make_dir_recursive_absolute(OUT)
		out = OUT
	img.save_png("%s/%s.png" % [out, name])
	return img


static func close(tree: SceneTree, vc: Array) -> void:
	(vc[0] as Node).queue_free()
	await tree.process_frame


## The mean colour of a rectangle of the picture (fractions of its size).
static func mean(img: Image, r: Rect2) -> Color:
	var sum := Vector3.ZERO
	var n := 0
	for y in range(int(r.position.y * img.get_height()), int(r.end.y * img.get_height())):
		for x in range(int(r.position.x * img.get_width()), int(r.end.x * img.get_width())):
			var c := img.get_pixel(x, y)
			sum += Vector3(c.r, c.g, c.b)
			n += 1
	sum /= maxf(n, 1)
	return Color(sum.x, sum.y, sum.z)
