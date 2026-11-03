extends Node3D

## Spike 02: imports a test-pattern NV12 dmabuf as one Vulkan image and samples its two planes on a quad.
## User arguments (after `--`):
##   --no-xr            flat Camera3D instead of OpenXR (also used when OpenXR isn't initialized).
##   --device=PATH      DRM node for the dumb buffer (default /dev/dri/card0; falls back to /dev/udmabuf).
##   --quit-after=N     quit after N frames (for runs over ssh).
##   --screenshot=PATH  save the main viewport as PNG at frame 30 (verify over ssh without the headset).
##   --cycle            release() and acquire() again every frame, as a video player does (tests the ownership transfers).
##   --device=host / host-split: no dmabuf; a linear image in host memory (host-split: two images, one per plane view).
##   --device=host-p010 / host-p010-split: the same as 10-bit P010 (G10X6_B10X6R10X6_2PLANE_420_UNORM_3PACK16).

@export var pattern_size := Vector2i(1920, 1080)

var screenshot_path := ""
var screenshot_frame := 30

@onready var quad: MeshInstance3D = $Quad
@onready var flat_camera: Camera3D = $FlatCamera
@onready var xr_camera: XRCamera3D = $XROrigin3D/XRCamera3D

var image: DmabufImage
var y_texture: Texture2DRD
var uv_texture: Texture2DRD
var quit_after := -1
var frames := 0
var cycle := false
var cycles := 0
var cycle_errors := 0


func _ready() -> void:
	var device := "/dev/dri/card0"
	var use_xr := true
	for arg in OS.get_cmdline_user_args():
		if arg == "--no-xr":
			use_xr = false
		elif arg.begins_with("--device="):
			device = arg.trim_prefix("--device=")
		elif arg.begins_with("--quit-after="):
			quit_after = arg.trim_prefix("--quit-after=").to_int()
		elif arg.begins_with("--screenshot="):
			screenshot_path = arg.trim_prefix("--screenshot=")
		elif arg.begins_with("--screenshot-frame="):
			screenshot_frame = arg.trim_prefix("--screenshot-frame=").to_int()
		elif arg == "--cycle":
			cycle = true
		elif arg == "--plain":
			# Bisect aid: draw the quad with an unshaded red material instead of the NV12 shader.
			var plain := StandardMaterial3D.new()
			plain.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			plain.albedo_color = Color(1, 0, 0)
			quad.material_override = plain
			print("Plain red material on the quad")

	_setup_view(use_xr)

	if "--no-import" in OS.get_cmdline_user_args():
		print("Skipping DmabufImage import (--no-import)")
		return

	var modifiers := PackedStringArray()
	for modifier in DmabufImage.get_supported_nv12_modifiers():
		modifiers.push_back("0x%x" % modifier)
	print("Sampleable NV12 modifiers: ", ", ".join(modifiers))

	image = DmabufImage.new()
	var err := image.import_test_pattern(pattern_size.x, pattern_size.y, device)
	if err != OK:
		push_error("import_test_pattern failed: %s" % error_string(err))
		return
	print("Imported %s NV12, modifier 0x%x, %d Vulkan image(s)" % [image.get_size(), image.get_drm_modifier(), image.get_image_count()])

	y_texture = Texture2DRD.new()
	y_texture.texture_rd_rid = image.get_plane_rid(0)
	uv_texture = Texture2DRD.new()
	uv_texture.texture_rd_rid = image.get_plane_rid(1)
	var material := quad.material_override as ShaderMaterial
	material.set_shader_parameter("y_tex", y_texture)
	material.set_shader_parameter("uv_tex", uv_texture)
	material.set_shader_parameter("p010", device.contains("p010"))


func _setup_view(use_xr: bool) -> void:
	var xr_interface := XRServer.find_interface("OpenXR")
	if use_xr and xr_interface and xr_interface.is_initialized():
		# The OpenXR runtime paces frames.
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		get_viewport().use_xr = true
		xr_camera.current = true
		print("View: OpenXR")
	else:
		flat_camera.current = true
		print("View: flat camera")


func _process(_delta: float) -> void:
	if image and image.is_imported():
		RenderingServer.call_on_render_thread(_acquire_on_render_thread)

	frames += 1
	if frames == 3 and get_viewport().use_xr:
		XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, true)
	if frames == screenshot_frame and screenshot_path != "":
		_save_screenshot()
	if quit_after > 0 and frames >= quit_after:
		if cycle:
			print("Release/acquire cycles: %d, errors %d" % [cycles, cycle_errors])
		print("Quitting after %d frames" % frames)
		get_tree().quit()


func _save_screenshot() -> void:
	# Under gamescope an unfocused X11 window may report window_can_draw() == false, in which case the
	# root viewport is never drawn. Render the screenshot through an offscreen SubViewport that shares
	# the main world instead; SubViewports are drawn regardless of window visibility.
	print("DisplayServer: can_draw=%s mode=%d size=%s" % [DisplayServer.window_can_draw(),
			DisplayServer.window_get_mode(), DisplayServer.window_get_size()])
	var cam3d := get_viewport().get_camera_3d()
	print("Main viewport camera: %s at %s; quad visible=%s pos=%s aabb=%s material=%s" % [
			cam3d, cam3d.global_position if cam3d else Vector3.INF, quad.is_visible_in_tree(),
			quad.global_position, quad.get_aabb(), quad.material_override])
	# 2D control: a red square top-left. If this shows and the quad doesn't, the 3D pass is the problem.
	var layer := CanvasLayer.new()
	add_child(layer)
	var rect := ColorRect.new()
	rect.color = Color(1, 0, 0)
	rect.position = Vector2(20, 20)
	rect.size = Vector2(200, 200)
	layer.add_child(rect)
	var sub := SubViewport.new()
	sub.size = Vector2i(1920, 1080)
	sub.world_3d = get_world_3d()
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.transparent_bg = false
	add_child(sub)
	var cam := Camera3D.new()
	sub.add_child(cam)
	cam.global_transform = flat_camera.global_transform
	cam.current = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := sub.get_texture().get_image()
	var err := img.save_png(screenshot_path)
	print("Screenshot (offscreen) %s (%dx%d): %s" % [screenshot_path, img.get_width(), img.get_height(), error_string(err)])
	var main_img := get_viewport().get_texture().get_image()
	main_img.save_png(screenshot_path.get_basename() + "_window.png")
	sub.queue_free()


func _acquire_on_render_thread() -> void:
	# Queue family ownership transfer FOREIGN -> ours, GENERAL -> SHADER_READ_ONLY, recorded before this frame's draws.
	# A decoder client would release() before re-queuing the buffer and acquire() after dequeuing the next frame in it.
	# The test pattern never changes, so after the first frame this does nothing (unless --cycle).
	if cycle and image.is_acquired():
		if image.release() != OK:
			cycle_errors += 1
		cycles += 1
	if image.acquire() != OK:
		cycle_errors += 1


func _exit_tree() -> void:
	# The Texture2DRDs must let go of the planes before the image frees them.
	var material := quad.material_override as ShaderMaterial
	material.set_shader_parameter("y_tex", null)
	material.set_shader_parameter("uv_tex", null)
	if y_texture:
		y_texture.texture_rd_rid = RID()
		uv_texture.texture_rd_rid = RID()
	if image:
		image.free_image()
