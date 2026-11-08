extends "res://tests/env_builder_harness.gd"

## The mirror-lid set's true mirror (scripts/env/mirror_view.gd; docs/environments.md, "mirror_lid"): TV 1937's lid
## holds a mirror that reflects (two reflected cameras, one an eye), the film lies on the tube's face under the top
## board (TubePicture: the screen's mesh and material at the screen's mirror image) and the upright screen is hidden
## while the mirror shows. Checked on the shipped room with a stand-in for the screen's flat mesh: the mirror's layer
## (its cameras leave it out, and the private layer), TubePicture the reflection of the screen (facing up, on the
## tube's face in the top's hole, the mirrored culling's determinant), the cameras at the eyes' mirror image with the
## near plane on the mirror (the eye's distance to it), the screen hidden and given back (no screen, the room hidden,
## the room built again, the room gone), a change of the screen's layers while hidden kept; in the main scene: the
## screen's own Flat hidden in TV 1937 and back in another room, TubePicture drawing with the presentation's material.
## With a renderer (lavapipe): a test card on the screen seen from the seat is in the mirror, bright, upright, the
## right way round and its grey as grey (the viewport's colour decoded once); from in front of the set, looking down
## under the lid, the card on the tube's face (its top towards the viewer, as a real set's tube shows it). Pictures in
## user://mirror_view/ (or $ENV_SHOTS).
## godot --headless --xr-mode off --path app --script res://tests/test_mirror_view.gd
## VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a godot --xr-mode off --path app --script
## res://tests/test_mirror_view.gd   (adds the renders)

const MirrorView := preload("res://scripts/env/mirror_view.gd")
const Domestic := preload("res://scripts/env/systems/domestic.gd")
const VideoScreen := preload("res://scripts/video_screen.gd")
const RoomRender := preload("res://tests/room_render.gd")
const OUT := "user://mirror_view"
const RED := Color(0.9, 0.1, 0.1)
const BLUE := Color(0.1, 0.2, 0.9)
const WHITE := Color(1, 1, 1)
const GREY := Color(0.5, 0.5, 0.5)


func run_tests() -> void:
	test_name = "test_mirror_view"
	var r := EnvDoc.load_file("res://environments/tv_1937.env.json")
	var doc: Dictionary = r["doc"]
	check("tv_1937 reads", (r["errors"] as Array).is_empty() and not doc.is_empty())
	if doc.is_empty():
		return
	await _standalone(doc)
	await _in_main()
	if DisplayServer.get_name() != "headless":
		await _renders(doc)
	else:
		print("  (headless: the renders need a renderer)")


## The room, its mirror, the stand-in screen and a camera at the viewer's eyes: [room, mirror, stand-in, camera].
func _open(doc: Dictionary, card := false) -> Array:
	var room: Node3D = EnvRoom.new()
	room.doc = doc.duplicate(true)
	root.add_child(room)
	await process_frame
	var mirror := room.get_node_or_null("Mirror") as MirrorView
	var s: Dictionary = doc["screen"]
	var size := Vector2(float(s["size"][0]), float(s["size"][1]))
	var stand := MeshInstance3D.new()
	stand.name = "StandIn"
	var qm := QuadMesh.new()
	qm.size = size
	stand.mesh = qm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if card:
		mat.albedo_texture = ImageTexture.create_from_image(_card())
	stand.material_override = mat
	stand.position = Vector3(float(s["center"][0]), float(s["center"][1]), float(s["center"][2]))
	root.add_child(stand)
	var cam := Camera3D.new()
	cam.fov = 40.0
	root.add_child(cam)
	cam.look_at_from_position(Vector3(0.0, EnvChecks.EYE_HEIGHT, 0.0), stand.position)
	cam.current = true
	if mirror != null:
		mirror.flat = stand
	for i in 3:
		await process_frame
	return [room, mirror, stand, cam]


func _close(o: Array) -> void:
	for n: Variant in [o[3], o[2], o[0]]:
		if is_instance_valid(n):
			(n as Node).queue_free()
	await process_frame


## The test card: a white band along the top, red on the left and blue on the right under it, a mid grey along the
## bottom (sRGB).
func _card() -> Image:
	var img := Image.create_empty(64, 48, false, Image.FORMAT_RGB8)
	for y in 48:
		for x in 64:
			var c := RED if x < 32 else BLUE
			if y < 12:
				c = WHITE
			elif y >= 36:
				c = GREY
			img.set_pixel(x, y, c)
	return img


func _standalone(doc: Dictionary) -> void:
	var o := await _open(doc)
	var room: Node3D = o[0]
	var mirror: MirrorView = o[1]
	var stand: MeshInstance3D = o[2]
	var cam: Camera3D = o[3]
	check("tv_1937: the lid's mirror is a true mirror (mirror_view.gd)", mirror != null)
	if mirror == null:
		await _close(o)
		return
	var glass := mirror.glass()
	check("the mirror's glass on its own layer only, see-through for the sight line",
			glass.layers == 1 << (MirrorView.LAYER - 1) and glass.is_in_group("env_see_through"))
	var cams := mirror.cameras()
	var masks_ok := cams.size() == 2
	for rc: Camera3D in cams:
		masks_ok = masks_ok and not rc.get_cull_mask_value(MirrorView.LAYER) \
				and not rc.get_cull_mask_value(VideoScreen.PRIVATE_LAYER) and rc.get_cull_mask_value(1)
	check("two cameras, one an eye, leaving out the mirror and the private layer", masks_ok)
	var px := mirror.views()[0].size
	check("each eye's reflection %s pixels, the mirror's shape" % px, px.x == MirrorView.PIXELS_WIDE
			and absf(float(px.x) / px.y - mirror.half_right.length() / mirror.half_up.length()) < 0.01)
	# The screen hidden, the film on the tube.
	check("the upright screen hidden from every camera (layers %d)" % stand.layers, stand.layers == 0
			and int(stand.get_meta(MirrorView.META, -1)) == 1)
	var tube := mirror.tube_picture()
	var want := mirror.reflection() * stand.global_transform
	check("TubePicture the screen's reflection, its mesh and material", tube.visible
			and tube.global_transform.is_equal_approx(want) and tube.mesh == stand.mesh
			and tube.material_override == stand.material_override and tube.layers == 1)
	var b: Node = room.host.system("room")
	var t: Dictionary = Domestic._telly(Domestic.resolved(b.params))
	var tc: Vector3 = (t["tube"] as Array)[0]
	var face := float((t["body"] as Array)[1].y)
	var tb := tube.global_transform
	check("TubePicture faces up (%s), mirrored (det %.2f)" % [tb.basis.z.normalized(), tb.basis.determinant()],
			tb.basis.z.normalized().is_equal_approx(Vector3.UP) and tb.basis.determinant() < -0.99)
	check("TubePicture on the tube's face (%s, the face at %s), under the top board (%.3f under the top)" % [tb.origin,
			tc, face - tb.origin.y], tb.origin.distance_to(tc) < 0.002
			and face - tb.origin.y >= Domestic.TOP_BOARD + 0.002)
	check("its top towards the viewer, left and right kept: the reflection of upright",
			tb.basis.y.normalized().is_equal_approx(Vector3.BACK) and tb.basis.x.normalized().is_equal_approx(
					Vector3.RIGHT))
	# The cameras.
	var w := mirror.world_rect()
	var c: Vector3 = w[0]
	var n: Vector3 = w[3]
	var eye := cam.global_position
	var d := (eye - c).dot(n)
	var rc := cams[0]
	check("the left camera at the eye's mirror image (%s)" % rc.global_position,
			rc.global_position.is_equal_approx(eye - 2.0 * d * n))
	check("its near plane on the mirror: the eye's distance to it (%.4f, %.4f)" % [rc.near, d],
			absf(rc.near - d) < 0.0001 and rc.projection == Camera3D.PROJECTION_FRUSTUM)
	check("looking through the mirror (its forward the mirror's normal), upright",
			(-rc.global_transform.basis.z).is_equal_approx(n) and rc.global_transform.basis.y.dot(
					(w[2] as Vector3).normalized()) > 0.999)
	var off := Vector2((c - rc.global_position).dot(rc.global_transform.basis.x),
			(c - rc.global_position).dot(rc.global_transform.basis.y))
	check("its frustum the mirror's rectangle (size %.3f, offset %s)" % [rc.size, rc.frustum_offset],
			absf(rc.size - 2.0 * (w[2] as Vector3).length()) < 0.0001 and rc.frustum_offset.is_equal_approx(off))
	check("on a desktop one eye: the left renders, the right not", mirror.views()[0].render_target_update_mode
			== SubViewport.UPDATE_ALWAYS and mirror.views()[1].render_target_update_mode == SubViewport.UPDATE_DISABLED)
	# Looking away, or from behind: no render.
	cam.look_at(Vector3(0.0, EnvChecks.EYE_HEIGHT, 5.0))
	await process_frame
	check("looking away: no render", mirror.views()[0].render_target_update_mode == SubViewport.UPDATE_DISABLED)
	cam.look_at_from_position(c + Vector3(0.0, 0.3, -0.4), c)
	await process_frame
	check("behind the mirror: no render", mirror.views()[0].render_target_update_mode == SubViewport.UPDATE_DISABLED)
	cam.look_at_from_position(Vector3(1.05, EnvChecks.EYE_HEIGHT, 0.45), stand.position)
	await process_frame
	d = (cam.global_position - c).dot(n)
	check("from a side seat: rendering, the near plane its distance (%.3f)" % d, mirror.views()[0]
			.render_target_update_mode == SubViewport.UPDATE_ALWAYS and absf(rc.near - d) < 0.0001)
	# A change of the screen's layers while hidden (VideoScreen.set_private) is the screen's new layers.
	stand.layers = 1 << (VideoScreen.PRIVATE_LAYER - 1)
	await process_frame
	check("the screen made private while hidden: hidden still, TubePicture private", stand.layers == 0
			and tube.layers == 1 << (VideoScreen.PRIVATE_LAYER - 1))
	stand.layers = 1
	await process_frame
	# No screen: given back.
	mirror.flat = null
	await process_frame
	check("no screen: the screen's layers given back, no TubePicture", stand.layers == 1 and not tube.visible
			and not stand.has_meta(MirrorView.META))
	mirror.flat = stand
	await process_frame
	room.visible = false
	await process_frame
	var none := true
	for v: SubViewport in mirror.views():
		none = none and v.render_target_update_mode == SubViewport.UPDATE_DISABLED
	check("the room hidden (a 180 / 360 film): the screen back, no renders", stand.layers == 1 and none)
	room.visible = true
	await process_frame
	check("shown again: hidden again", stand.layers == 0)
	# The room built again: the old mirror gives the screen back, the new one takes it.
	room.host.rebuild()
	check("the room built again: the old mirror gave the screen back", stand.layers == 1)
	var again := room.get_node_or_null("Mirror") as MirrorView
	check("a new mirror", again != null and again != mirror)
	if again != null:
		again.flat = stand
		await process_frame
		await process_frame
		check("the new mirror hides the screen", stand.layers == 0 and again.tube_picture().visible)
	room.free()
	check("the room gone: the screen's layers back", stand.layers == 1 and not stand.has_meta(MirrorView.META))
	await _close(o)


## In the main scene: TV 1937 hides the screen's own Flat and draws the presentation's film on the tube; another room
## gives it back.
func _in_main() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	for i in 5:
		await process_frame
	main.open_path("stub://flat_mono")
	for i in 3:
		await process_frame
	var flat := main.screen.get_node("Flat") as MeshInstance3D
	var before := flat.layers
	main.set_environment("tv_1937")
	for i in 4:
		await process_frame
	var mirror := main.env.get_node_or_null("Mirror") as MirrorView
	check("main: TV 1937's mirror finds the screen's Flat", mirror != null and mirror.get("_hidden") == flat)
	if mirror != null:
		var p: Node = main.env.host.system_of_kind("screen")
		var tube := mirror.tube_picture()
		check("main: Flat hidden (%d, was %d)" % [flat.layers, before], flat.layers == 0 and before != 0)
		check("main: TubePicture draws with the presentation's material, Flat's mesh", tube.visible
				and p != null and tube.material_override == p.material() and flat.material_override == p.material()
				and tube.mesh == flat.mesh)
		check("main: TubePicture the reflection of Flat", tube.global_transform.is_equal_approx(
				mirror.reflection() * flat.global_transform))
		if DisplayServer.get_name() != "headless" and p != null:
			await _main_renders(main, mirror, flat, p)
	main.set_environment("void")
	for i in 3:
		await process_frame
	check("main: another room: Flat's layers back (%d)" % flat.layers, flat.layers == before
			and not flat.has_meta(MirrorView.META))
	main.queue_free()
	for i in 2:
		await process_frame


## In the main scene, the set switched on: the stub's pattern through the 1937 presentation, in the mirror from the
## seat and on the tube from in front of the set.
func _main_renders(main: Node3D, mirror: MirrorView, flat: MeshInstance3D, p: Node) -> void:
	root.size = Vector2i(800, 600)
	p.set("power", "on")
	p.call("_apply_power")
	var cam := Camera3D.new()
	cam.fov = 40.0
	main.add_child(cam)
	cam.current = true
	var at := flat.global_position
	var size := main.screen.get_flat_size() as Vector2
	cam.look_at_from_position(at + Vector3(0.0, 0.06, 1.15), at)
	var img := await _shot("main_seat")
	var lit := _mean(img, _rect_of(cam, flat.global_transform, size), Rect2(0.3, 0.3, 0.4, 0.4))
	check("main: the set on, its picture in the mirror from the seat (%s)" % lit, lit.get_luminance() > 0.12)
	var tube := mirror.tube_picture()
	cam.look_at_from_position(tube.global_position + Vector3(0.0, 0.3, 0.5), tube.global_position)
	cam.fov = 50.0
	img = await _shot("main_above")
	lit = _mean(img, _rect_of(cam, tube.global_transform, size), Rect2(0.3, 0.3, 0.4, 0.4))
	check("main: and on the tube's face from above (%s)" % lit, lit.get_luminance() > 0.12)
	cam.queue_free()


## The pictures: from the seat the card in the mirror; from in front of the set, down under the lid, on the tube.
func _renders(doc: Dictionary) -> void:
	root.size = Vector2i(800, 600)
	var s: Dictionary = doc["screen"]
	RoomRender.set_light(Vector3(float(s["center"][0]), float(s["center"][1]), float(s["center"][2])), 1.0)
	var o := await _open(doc, true)
	var mirror: MirrorView = o[1]
	var stand: MeshInstance3D = o[2]
	var cam: Camera3D = o[3]
	if mirror == null:
		await _close(o)
		return
	var size := (stand.mesh as QuadMesh).size
	var img := await _shot("seat")
	# The card's place from the seat: the reflection is where the screen stands.
	var rect := _rect_of(cam, stand.global_transform, size)
	var top := _mean(img, rect, Rect2(0.2, 0.04, 0.6, 0.12))
	var left := _mean(img, rect, Rect2(0.1, 0.35, 0.3, 0.3))
	var right := _mean(img, rect, Rect2(0.6, 0.35, 0.3, 0.3))
	var grey := _mean(img, rect, Rect2(0.2, 0.82, 0.6, 0.12))
	print("  from the seat: top %s, left %s, right %s, grey %s" % [top, left, right, grey])
	check("from the seat: the card in the mirror, upright (white along the top: %s)" % top, top.r > 0.75
			and top.g > 0.7 and top.b > 0.6)
	check("the right way round: red on the left (%s), blue on the right (%s)" % [left, right], left.r > 0.6
			and left.b < 0.3 and right.b > 0.6 and right.r < 0.3)
	# The grey through the silvering: sRGB(linear(0.5) * reflectance), once decoded; twice bright if not.
	var g_want := _srgb(_linear(0.5) * mirror.tint.g)
	check("the grey as grey through the silvering (%.3f, want %.3f)" % [grey.g, g_want], absf(grey.g - g_want) < 0.06)
	# From in front of the set, looking down under the lid at the tube.
	var b: Node = (o[0] as Node3D).host.system("room")
	var t: Dictionary = Domestic._telly(Domestic.resolved(b.params))
	var tc: Vector3 = (t["tube"] as Array)[0]
	var front := float((t["body"] as Array)[0].z) + float((t["body"] as Array)[1].z) * 0.5
	cam.look_at_from_position(Vector3(0.0, tc.y + 0.3, front + 0.2), tc)
	cam.fov = 50.0
	img = await _shot("above")
	var tube := mirror.tube_picture()
	rect = _rect_of(cam, tube.global_transform, size)
	# The tube's card: its top (white) towards the viewer, at the bottom of this view; red on the left.
	var near := _mean(img, rect, Rect2(0.25, 0.04, 0.5, 0.1))
	left = _mean(img, rect, Rect2(0.1, 0.4, 0.3, 0.2))
	right = _mean(img, rect, Rect2(0.6, 0.4, 0.3, 0.2))
	print("  from above: near %s, left %s, right %s" % [near, left, right])
	check("from above: the card on the tube's face, its top towards the viewer (%s)" % near, near.r > 0.75
			and near.b > 0.6)
	check("from above: red on the left (%s), blue on the right (%s), as the tube shows it" % [left, right],
			left.r > 0.6 and left.b < 0.3 and right.b > 0.6 and right.r < 0.3)
	# To look at: the set from the side seat and from standing beside it (no picture floating behind the lid).
	cam.fov = 40.0
	cam.look_at_from_position(Vector3(1.05, EnvChecks.EYE_HEIGHT, 0.45), stand.position)
	await _shot("side_seat")
	cam.fov = 50.0
	cam.look_at_from_position(Vector3(1.1, 1.6, -0.3), Vector3(0.0, 1.0, -0.95))
	await _shot("standing")
	await _close(o)


## A quad of `size` at `xf` as the camera sees it: [camera, transform, size], for _mean().
func _rect_of(cam: Camera3D, xf: Transform3D, size: Vector2) -> Array:
	return [cam, xf, size]


## The mean colour on screen of a part of the quad (`part` in the card's UV: 0, 0 its top left as the card is drawn),
## each sample the camera's projection of its point on the quad, so a part of the card is found whichever way the
## quad lies (upright, mirrored, lying in the tube).
func _mean(img: Image, q: Array, part: Rect2) -> Color:
	var cam: Camera3D = q[0]
	var xf: Transform3D = q[1]
	var size: Vector2 = q[2]
	var sum := Vector3.ZERO
	var k := 0
	for j in 8:
		for i in 8:
			var u := part.position.x + part.size.x * (i + 0.5) / 8.0
			var v := part.position.y + part.size.y * (j + 0.5) / 8.0
			var p := cam.unproject_position(xf * Vector3((u - 0.5) * size.x, (0.5 - v) * size.y, 0.0))
			var x := clampi(int(p.x), 0, img.get_width() - 1)
			var y := clampi(int(p.y), 0, img.get_height() - 1)
			var c := img.get_pixel(x, y)
			sum += Vector3(c.r, c.g, c.b)
			k += 1
	sum /= k
	return Color(sum.x, sum.y, sum.z)


func _shot(label: String) -> Image:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var out := OS.get_environment("ENV_SHOTS")
	if out == "":
		DirAccess.make_dir_recursive_absolute(OUT)
		out = OUT
	img.save_png("%s/%s.png" % [out, label])
	return img


static func _linear(c: float) -> float:
	return c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)


static func _srgb(c: float) -> float:
	return c * 12.92 if c <= 0.0031308 else 1.055 * pow(c, 1.0 / 2.4) - 0.055
