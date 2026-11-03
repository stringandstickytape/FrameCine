extends Node

## #70 Quad layers, a spike behind flags (docs/xr-spikes.md, "Quad layers"). Untested on the device.
##
## Normally the pane and the screen are drawn into the eye buffers, which the runtime then resamples again for the
## lenses: two filterings, and text loses sharpness. An OpenXR quad layer hands the runtime the picture itself, which
## it samples once, straight into the lens-corrected view. The engine's OpenXRCompositionLayerQuad does it with a
## SubViewport as the layer's image.
##
## --pane-layer    the pane's SubViewport (it already has one) as a quad layer over the scene, at the pane's pose and
##                 size. The pane's own quad is hidden; its halo stays in the scene. Composited over everything, so the
##                 laser and the controller show behind the pane where they cross it, and the pane cannot fade (its
##                 fades show as a cut): it is on above 50 % opacity.
## --video-layer   the flat video screen as two quad layers, one per eye (eye_visibility), each from a SubViewport the
##                 size of one eye's picture (at most MAX_EDGE pixels a side) drawn by the video shader with the
##                 screen's uniforms (force_eye 0 / 1). They sit behind the scene with a hole punched where the screen
##                 is, so the pane, the laser and subtitles in front still cover it. Flat screens only (no curve): 180
##                 / 360 and the curved screen keep the normal path. Cost: two extra passes of the video shader at the
##                 picture's resolution per frame (one per eye), and the runtime's composition of two more layers.
## Without an XR session (a desktop) the flags only print that they do nothing. The normal path stays the default.

const MAX_EDGE := 3840
const VIDEO_SHADER := preload("res://shaders/video.gdshader")
const VideoMode := preload("res://scripts/video_mode.gd")

var main: Node3D
var want_pane := false
var want_video := false
var pane_layer: Node3D
## [left, right] layers and their viewports while the video layer is up.
var video_layers: Array[Node3D] = []
var video_viewports: Array[SubViewport] = []
var _video_materials: Array[ShaderMaterial] = []
var _names: Array[String] = []
var _video_on := false


static func available() -> bool:
	return ClassDB.class_exists("OpenXRCompositionLayerQuad")


## Adds the spike when its flags are given. force: without an XR session too (tests; the layers do not show then).
static func attach(m: Node3D, args: Dictionary, force := false) -> Node:
	var pane := args.has("pane-layer")
	var video := args.has("video-layer")
	if not pane and not video:
		return null
	if not available():
		print("Quad layers: this engine has no OpenXRCompositionLayerQuad")
		return null
	var xr := XRServer.find_interface("OpenXR")
	if not force and (xr == null or not xr.is_initialized() or not m.use_xr):
		print("Quad layers: no XR session; --pane-layer and --video-layer do nothing on a desktop")
		return null
	var s: Node = (load("res://scripts/xr_spikes/quad_layers.gd") as GDScript).new()
	s.name = "QuadLayers"
	s.main = m
	s.want_pane = pane
	s.want_video = video
	m.add_child(s)
	return s


func _ready() -> void:
	for u: Dictionary in VIDEO_SHADER.get_shader_uniform_list():
		_names.append(str(u["name"]))
	if want_pane:
		_make_pane_layer.call_deferred()


func _origin() -> Node3D:
	return main.xr_origin


func _new_layer(viewport: SubViewport, size: Vector2) -> Node3D:
	var layer: Node3D = ClassDB.instantiate("OpenXRCompositionLayerQuad")
	layer.set("layer_viewport", viewport)
	layer.set("quad_size", size)
	layer.set("alpha_blend", true)
	_origin().add_child(layer)
	return layer


func _pane() -> Node3D:
	var ui: Node = main.get("ui")
	return ui.get("panel") if ui != null else null


func _make_pane_layer() -> void:
	var pane := _pane()
	if pane == null:
		print("Quad layers: no pane to put in a layer")
		return
	pane_layer = _new_layer(pane.viewport, pane.size_m)
	pane_layer.name = "PaneLayer"
	pane_layer.set("sort_order", 1)
	var quad: Node3D = pane.get_node_or_null("Quad")
	if quad != null:
		quad.visible = false
	print("Quad layers: the pane as a quad layer (%dx%d px, %.3f x %.3f m), natively supported: %s" % [
			pane.resolution.x, pane.resolution.y, pane.size_m.x, pane.size_m.y, pane_layer.call("is_natively_supported")])


func _process(_delta: float) -> void:
	if pane_layer != null:
		var pane := _pane()
		pane_layer.global_transform = pane.global_transform
		pane_layer.set("quad_size", pane.size_m)
		pane_layer.visible = pane.visible and float(pane.opacity) > 0.5
	if want_video:
		_update_video()


func video_applies() -> bool:
	var screen: Node3D = main.screen
	return main.player.has_source() and screen.is_shown() and not main.mode.is_spherical() \
			and is_zero_approx(float(screen.curve_radius))


## One eye's picture in pixels for the open file (the full frame's size, split and stretched as the mode says).
func eye_pixels() -> Vector2i:
	var size: Vector2 = main.screen.get_flat_size()
	var frame: Vector2 = main._frame_size()
	var w := frame.x
	if main.mode.layout == VideoMode.Layout.SBS and not main.mode.half:
		w = frame.x * 0.5
	w = clampf(w if w > 0.0 else 1920.0, 64.0, MAX_EDGE)
	var h := clampf(w * size.y / maxf(size.x, 0.01), 64.0, MAX_EDGE)
	return Vector2i(roundi(w), roundi(h))


func _update_video() -> void:
	var on := video_applies()
	if on != _video_on:
		_video_on = on
		if on:
			_make_video_layers()
		else:
			_free_video_layers()
	if not on:
		return
	var screen: Node3D = main.screen
	var px := eye_pixels()
	var src: ShaderMaterial = screen.material
	for eye in 2:
		if video_viewports[eye].size != px:
			video_viewports[eye].size = px
		var m := _video_materials[eye]
		for n in _names:
			m.set_shader_parameter(n, src.get_shader_parameter(n))
		m.set_shader_parameter("force_eye", eye)
		m.set_shader_parameter("edge_fade", 0.0)
		video_layers[eye].global_transform = screen.global_transform
		video_layers[eye].set("quad_size", screen.get_flat_size())


func _make_video_layers() -> void:
	var px := eye_pixels()
	for eye in 2:
		var vp := SubViewport.new()
		vp.name = "VideoLayerEye%d" % eye
		vp.size = px
		vp.own_world_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 1.0
		cam.keep_aspect = Camera3D.KEEP_HEIGHT
		cam.position = Vector3(0, 0, 1)
		vp.add_child(cam)
		var quad := MeshInstance3D.new()
		var mesh := QuadMesh.new()
		mesh.size = Vector2(float(px.x) / px.y, 1.0)
		quad.mesh = mesh
		var m := ShaderMaterial.new()
		m.shader = VIDEO_SHADER
		quad.material_override = m
		vp.add_child(quad)
		add_child(vp)
		var layer := _new_layer(vp, main.screen.get_flat_size())
		layer.name = "VideoLayerEye%d" % eye
		layer.set("alpha_blend", false)
		layer.set("sort_order", -1)
		layer.set("enable_hole_punch", true)
		# 1 left, 2 right (OpenXRCompositionLayer.EyeVisibility; 0 both).
		layer.set("eye_visibility", 1 + eye)
		video_viewports.append(vp)
		video_layers.append(layer)
		_video_materials.append(m)
	_set_screen_drawn(false)
	print("Quad layers: the video as two quad layers (%dx%d px per eye), natively supported: %s" % [px.x, px.y,
			video_layers[0].call("is_natively_supported")])


func _free_video_layers() -> void:
	for n: Node in video_layers + video_viewports:
		n.queue_free()
	video_layers.clear()
	video_viewports.clear()
	_video_materials.clear()
	_set_screen_drawn(true)


## The screen's flat quad drawn or not (render layers 0: no camera draws it). Its node, children and state stay.
func _set_screen_drawn(on: bool) -> void:
	var flat: VisualInstance3D = main.screen.get_node_or_null("Flat")
	if flat != null:
		flat.layers = 1 if on else 0


func _exit_tree() -> void:
	if _video_on:
		_free_video_layers()
	var pane := _pane()
	if pane != null and pane.get_node_or_null("Quad") != null:
		pane.get_node("Quad").visible = true
	if pane_layer != null:
		pane_layer.queue_free()
