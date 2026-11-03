extends Node

## Stereo screenshots (ideas #66): the video frame showing now, saved as a picture in the video's own layout: each
## eye at the picture's resolution (up to MAX_EYE), side by side or top / bottom for 3D, one picture for 2D, the
## equirectangular or fisheye frame itself for 180 / 360. Each eye is drawn through video.gdshader in an offscreen
## viewport with the screen's settings (colour, HDR tone map, picture controls), without the depth shift, zoom, edge
## fade or dimming. The file name carries the mode ("..._sbs", "_tb", "_180_sbs", "_360_tb", "_fisheye_sbs"), so the
## player's picture viewer (#22) opens it the same way again.
##
##   capture() -> String     (await) the saved file's path, or "" (with last_error)
##   folder                  user://screenshots
##   signal saved(path)

signal saved(path: String)

const VIDEO_SHADER := preload("res://shaders/video.gdshader")
const VideoMode := preload("res://scripts/video_mode.gd")
const FOLDER := "user://screenshots"
const MAX_EYE := 4096
## Uniforms that are about showing, not about the picture.
const NEUTRAL := {"stereo_shift": 0.0, "zoom": 1.0, "pan": Vector2.ZERO, "edge_fade": 0.0, "brightness": 1.0}

var main: Node3D
var last_error := ""
var _busy := false


func capture() -> String:
	last_error = ""
	if _busy:
		last_error = "a screenshot is being taken"
		return ""
	if not main.player.has_source() or not main.player.source.has_frame():
		last_error = "nothing on the screen"
		return ""
	_busy = true
	var mode: VideoMode = main.mode
	var info: Dictionary = main.player.source.get_video_info()
	var frame := Vector2(float(info.get("width", 1920)), float(info.get("height", 1080)))
	var eye := mode.eye_pixels(frame) if mode.layout != VideoMode.Layout.MONO else frame
	var scale := minf(1.0, float(MAX_EYE) / maxf(eye.x, eye.y))
	var size := Vector2i(maxi(roundi(eye.x * scale), 2), maxi(roundi(eye.y * scale), 2))
	var stereo := mode.layout != VideoMode.Layout.MONO and int(main.screen.material.get_shader_parameter("mono_eye")) < 0
	var left := await _render_eye(0, size)
	var out := left
	if stereo:
		var right := await _render_eye(1, size)
		if mode.layout == VideoMode.Layout.TB:
			out = Image.create_empty(size.x, size.y * 2, false, left.get_format())
			out.blit_rect(left, Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
			out.blit_rect(right, Rect2i(Vector2i.ZERO, size), Vector2i(0, size.y))
		else:
			out = Image.create_empty(size.x * 2, size.y, false, left.get_format())
			out.blit_rect(left, Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
			out.blit_rect(right, Rect2i(Vector2i.ZERO, size), Vector2i(size.x, 0))
	DirAccess.make_dir_recursive_absolute(FOLDER)
	var path := FOLDER.path_join(file_name(main.current_path, main.player.get_position(), mode, stereo))
	var err := out.save_jpg(path, 0.92)
	_busy = false
	if err != OK:
		last_error = "can't save %s (%s)" % [path, error_string(err)]
		return ""
	print("Stereo screenshot: %s (%dx%d)" % [ProjectSettings.globalize_path(path), out.get_width(), out.get_height()])
	saved.emit(path)
	return path


## "<video name>_<h>h<mm>m<ss>s<mode tags>.jpg"
static func file_name(video_path: String, t: float, mode: VideoMode, stereo: bool) -> String:
	var base := video_path.get_file().get_basename() if not video_path.begins_with("stub://") else video_path.trim_prefix("stub://")
	base = base.validate_filename().replace(" ", "_").left(60)
	var s := int(t)
	var tags := ""
	match mode.projection:
		VideoMode.Proj.EQUIRECT_180:
			tags += "_180"
		VideoMode.Proj.EQUIRECT_360:
			tags += "_360"
		VideoMode.Proj.FISHEYE:
			tags += "_fisheye%d" % roundi(mode.fisheye_fov)
		VideoMode.Proj.DUAL_FISHEYE:
			tags += "_dualfisheye"
	if stereo:
		tags += "_tb" if mode.layout == VideoMode.Layout.TB else "_sbs"
	return "%s_%dh%02dm%02ds%s.jpg" % [base, s / 3600, s / 60 % 60, s % 60, tags]


func _render_eye(eye: int, size: Vector2i) -> Image:
	var vp := SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = 1.0
	cam.position = Vector3(0, 0, 1)
	vp.add_child(cam)
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(float(size.x) / size.y, 1.0)
	quad.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = VIDEO_SHADER
	var src: ShaderMaterial = main.screen.material
	for u: Dictionary in VIDEO_SHADER.get_shader_uniform_list():
		var n := str(u["name"])
		mat.set_shader_parameter(n, NEUTRAL[n] if NEUTRAL.has(n) else src.get_shader_parameter(n))
	mat.set_shader_parameter("force_eye", eye)
	quad.material_override = mat
	vp.add_child(quad)
	add_child(vp)
	for i in 2:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	return img
