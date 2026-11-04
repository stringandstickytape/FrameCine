extends Node

## Film layer (ideas #70; on by default since 2026-11-04): the flat film shown by an OpenXR composition layer instead
## of the screen's mesh. In the scene the film is resampled twice: into the eye buffers (at lower
## resolution away from the centre while foveation is on), then again by the runtime's lens distortion. As a layer
## the runtime samples the film's own pixels once, at display resolution: sharper text and fine detail, no foveation
## on the film. On the Steam Frame, stars in a paused 4K frame stopped shimmering, and the app's GPU time with a 4K
## film fell from 2.5 to 1.4 ms (docs/features.md, "Film layer").
##
## Each layer has a SubViewport the size of one eye's picture (at most MAX_EDGE pixels a side), drawn by
## video_layer.gdshader with the screen's uniforms copied over: the same picture code as the screen (colour matrix,
## HDR and 10-bit tone mapping, picture controls, zoom, depth shift, edge fade, dimming). The viewport is drawn only
## on a frame with a new video frame (VideoSource.frame_key()) or a changed uniform: UPDATE_ALWAYS for that frame,
## else UPDATE_DISABLED, and the runtime keeps showing the last image. The layers are children of the screen node, so
## they follow every move, resize and recentre.
##   flat 2D, or 3D shown as 2D   one quad layer that both eyes see
##   flat 3D (SBS, TB)            two quad layers, one per eye (eye_visibility)
##   curved screen                cylinder layers when the runtime has XR_KHR_composition_layer_cylinder; the Frame's
##                                runtime has not (docs/research-device.md), so the mesh there
##   180, 360, fisheye            the mesh (no equirect layers on the Frame; fisheye would need a reprojection pass)
## Depth: a layer is not depth-tested. These sit behind the scene (sort_order -1) with a hole punched where the screen
## is: the engine's hole-punch mesh writes depth and alpha 0 into the eye buffers, and the runtime shows the layer
## through. The pane, the laser, the controllers, subtitles and room objects in front of the screen cover the film as
## before, half-transparent ones blend over it, and what is behind the screen stays hidden by the hole's depth.
## Off, without an XR session, without layers in the engine, or with no layer for the mode: the screen's mesh, as
## always. Switching at run time keeps playback going.
##
##   enabled, set_enabled(on, save := true)
##   force                  tests: build the layers without an XR session (they don't show then)
##   layers, viewports      while in use ([] otherwise)
##   kind                   "quad", "cylinder" or "" (the mesh)
##   updates                viewport draws so far (one per new picture or changed uniform)
##   status() -> String     one line for the pane
##   static available(), static eye_pixels(frame_px, flat_size, mode) -> Vector2i
##   signal changed         layers made or dropped
## Settings: [view] film_layer (default on; only false is stored).

signal changed

const VideoMode := preload("res://scripts/video_mode.gd")
const CurvedScreen := preload("res://scripts/play/curved_screen.gd")
const LAYER_SHADER := preload("res://shaders/video_layer.gdshader")
const MAX_EDGE := 3840
## Viewport sides snap to this many pixels, so a screen that grows a little (the auto crop) doesn't remake the
## swapchains on every step.
const SNAP := 8
## OpenXRCompositionLayer.EyeVisibility: both, left, right.
const EYES_BOTH := 0

var main: Node3D
var enabled := false
var force := false
var layers: Array[Node3D] = []
var viewports: Array[SubViewport] = []
var kind := ""
var updates := 0

var _materials: Array[ShaderMaterial] = []
var _names: Array[String] = []
## Uniform name -> the value last copied from the screen's material.
var _copied := {}
var _frame_key := NAN
var _dirty := false
var _cylinder := -1


func _ready() -> void:
	# After the player's update and the features that set the screen's uniforms each frame.
	process_priority = 100
	enabled = bool(main.settings.get_value("view", "film_layer", true))
	for u: Dictionary in LAYER_SHADER.get_shader_uniform_list():
		if str(u["name"]) != "force_eye":
			_names.append(str(u["name"]))


static func available() -> bool:
	return ClassDB.class_exists("OpenXRCompositionLayerQuad")


## save false: for this run only (the --video-layer flag).
func set_enabled(on: bool, save := true) -> void:
	enabled = on
	if save:
		main.settings.set_value("view", "film_layer", null if on else false)
	_update()


## One eye's picture in pixels for frames of frame_px (visible size, square pixels) on a flat screen of flat_size
## metres: the eye's own width (half the frame in full side by side; half-width frames are drawn stretched), the
## height from the screen's aspect, both scaled down to fit MAX_EDGE and snapped to SNAP.
static func eye_pixels(frame_px: Vector2, flat_size: Vector2, mode: VideoMode) -> Vector2i:
	var w := frame_px.x if frame_px.x > 0.0 else 1920.0
	if mode.layout == VideoMode.Layout.SBS and not mode.half:
		w *= 0.5
	var h := w * flat_size.y / maxf(flat_size.x, 0.01)
	var k := minf(1.0, MAX_EDGE / maxf(w, h))
	return Vector2i(maxi(SNAP, snappedi(roundi(w * k), SNAP)), maxi(SNAP, snappedi(roundi(h * k), SNAP)))


## The layer type for what is on screen now; "" for the mesh.
func wanted_kind() -> String:
	if not enabled or not available() or not _xr_running():
		return ""
	var screen: Node3D = main.screen
	if not main.player.has_source() or not screen.is_shown() or screen.mode.projection != VideoMode.Proj.FLAT:
		return ""
	if float(screen.curve_radius) > 0.0:
		return "cylinder" if force or _has_cylinder() else ""
	return "quad"


func status() -> String:
	if not enabled:
		return "Off: the film is drawn in the room."
	if not available():
		return "This engine has no OpenXR layers."
	if not _xr_running():
		return "Only in the headset: here the film is drawn in the room."
	if kind == "":
		if main.player.has_source() and main.screen.mode.projection != VideoMode.Proj.FLAT:
			return "180, 360 and fisheye films are drawn in the room."
		if main.player.has_source() and float(main.screen.curve_radius) > 0.0:
			return "This headset has no curved layers: a curved screen is drawn in the room."
		return "On; nothing to show."
	var px: Vector2i = viewports[0].size
	if layers.size() == 2:
		return "In use: two %s layers, one per eye, %d x %d px each." % [kind, px.x, px.y]
	return "In use: one %s layer, %d x %d px." % [kind, px.x, px.y]


func _xr_running() -> bool:
	if force:
		return true
	if not main.use_xr:
		return false
	var xr := XRServer.find_interface("OpenXR")
	return xr != null and xr.is_initialized()


## Whether the runtime takes cylinder layers (asked once).
func _has_cylinder() -> bool:
	if _cylinder < 0:
		var probe: Node = ClassDB.instantiate("OpenXRCompositionLayerCylinder") if ClassDB.class_exists(
				"OpenXRCompositionLayerCylinder") else null
		_cylinder = 1 if probe != null and bool(probe.call("is_natively_supported")) else 0
		if probe != null:
			probe.free()
	return _cylinder == 1


## Both eyes see one picture, unless a 3D film is shown in 3D.
func _eye_count() -> int:
	var mono_eye: Variant = main.screen.material.get_shader_parameter("mono_eye")
	return 2 if main.screen.mode.is_stereo() and (mono_eye == null or int(mono_eye) < 0) else 1


func _process(_delta: float) -> void:
	_update()


func _update() -> void:
	var want := wanted_kind()
	var eyes := _eye_count() if want != "" else 0
	if want != kind or eyes != layers.size():
		_drop()
		if want != "":
			_make(want, eyes)
		changed.emit()
	if kind == "":
		return
	_place()
	var px := eye_pixels(main.screen.frame_size, main.screen.get_flat_size(), main.screen.mode)
	for vp in viewports:
		if vp.size != px:
			vp.size = px
			_dirty = true
	if _copy_uniforms():
		_dirty = true
	var key: float = main.player.source.frame_key()
	if key != _frame_key:
		# NAN never equals itself: a source that can't tell draws every frame.
		_frame_key = key
		_dirty = true
	var mode := SubViewport.UPDATE_ALWAYS if _dirty else SubViewport.UPDATE_DISABLED
	for vp in viewports:
		vp.render_target_update_mode = mode
	if _dirty:
		updates += 1
	_dirty = false


func _make(p_kind: String, eyes: int) -> void:
	kind = p_kind
	var px := eye_pixels(main.screen.frame_size, main.screen.get_flat_size(), main.screen.mode)
	for eye in eyes:
		var vp := SubViewport.new()
		vp.name = "FilmLayerView%d" % eye
		vp.size = px
		vp.disable_3d = true
		vp.gui_disable_input = true
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		var rect := ColorRect.new()
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		var m := ShaderMaterial.new()
		m.shader = LAYER_SHADER
		m.set_shader_parameter("force_eye", eye)
		rect.material = m
		vp.add_child(rect)
		add_child(vp)
		var layer: Node3D = ClassDB.instantiate("OpenXRCompositionLayerQuad" if kind == "quad"
				else "OpenXRCompositionLayerCylinder")
		layer.name = "FilmLayer%d" % eye
		layer.set("layer_viewport", vp)
		layer.set("sort_order", -1)
		layer.set("alpha_blend", false)
		# One hole is enough for both eyes' layers.
		layer.set("enable_hole_punch", eye == 0)
		layer.set("eye_visibility", EYES_BOTH if eyes == 1 else 1 + eye)
		if kind == "cylinder":
			layer.set("fallback_segments", CurvedScreen.SEGMENTS)
		main.screen.add_child(layer)
		viewports.append(vp)
		layers.append(layer)
		_materials.append(m)
	_copied.clear()
	_dirty = true
	main.screen.set_flat_drawn(false)
	print("Film layer: %d %s layer(s), %d x %d px, natively supported: %s" % [eyes, kind, px.x, px.y,
			layers[0].call("is_natively_supported")])


func _drop() -> void:
	# The layers live under the screen, which may be gone first when the app quits.
	for n: Variant in layers + viewports:
		if is_instance_valid(n):
			(n as Node).free()
	layers.clear()
	viewports.clear()
	_materials.clear()
	kind = ""
	_frame_key = NAN
	if is_instance_valid(main) and is_instance_valid(main.screen):
		main.screen.set_flat_drawn(true)


## The layers on the screen's picture: a quad of its flat size at its centre, or a cylinder whose axis is `radius`
## in front of it (the curved mesh bends toward the viewer; the layer's arc lies at -Z from its pose).
func _place() -> void:
	var size: Vector2 = main.screen.get_flat_size()
	var r := float(main.screen.curve_radius)
	for layer in layers:
		if kind == "quad":
			if not (layer.get("quad_size") as Vector2).is_equal_approx(size):
				layer.set("quad_size", size)
			continue
		var angle := size.x / r
		var aspect := size.x / maxf(size.y, 0.01)
		if not is_equal_approx(float(layer.get("radius")), r) or not is_equal_approx(float(layer.get("central_angle")),
				angle) or not is_equal_approx(float(layer.get("aspect_ratio")), aspect):
			layer.set("radius", r)
			layer.set("central_angle", angle)
			layer.set("aspect_ratio", aspect)
			layer.position = Vector3(0.0, 0.0, r)


## Copies the screen's uniforms that changed; true if any did.
func _copy_uniforms() -> bool:
	var src: ShaderMaterial = main.screen.material
	var any := false
	for n in _names:
		var v: Variant = src.get_shader_parameter(n)
		if _copied.has(n) and typeof(_copied[n]) == typeof(v) and _copied[n] == v:
			continue
		_copied[n] = v
		for m in _materials:
			m.set_shader_parameter(n, v)
		any = true
	return any


func _exit_tree() -> void:
	if kind != "":
		_drop()
