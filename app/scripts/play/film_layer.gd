extends Node

## Film layer (ideas #70; on by default since 2026-11-04): the flat film shown by an OpenXR composition layer instead
## of the screen's mesh. In the scene the film is resampled twice: into the eye buffers, then again by the runtime's
## lens distortion. As a layer the runtime samples the film's own pixels once, at display resolution: sharper text
## and fine detail. On the Steam Frame, stars in a paused 4K frame stopped shimmering, and the app's GPU time with a 4K
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
## While the menu is open (main.menu_shown) the layers hide and the mesh draws the film: the runtime drew the layer
## over the panels (the user, 2026-11-04). They come back when it closes; nothing is remade and the setting is not
## touched. The same while something is between the viewer and the screen: a room object (object_physics.gd
## solid_nodes(): placed, held, thrown, attached), a controller, the laser or its dot. The runtime draws a quad layer
## over everything in front of it, hole punch or not: the panels (2026-11-04), a ham lobbed at the screen and a
## controller held up in front of the film (the user, 2026-11-06). Not the laser that is a captured window's pointer:
## see _covered(). Its bounds seen from the eyes cover part of the
## picture -> held at once; clear for COVER_RELEASE seconds -> the layer again (no flicker at the picture's edge).
## In front of the film (2026-11-23): tried on the Frame, the runtime draws a quad layer over the scene's layer
## whatever the order asked for, with or without the hole, with or without a true alpha in the eye buffers. So the
## scene can never cover the film, and the mesh's picture is too coarse to read a page by with a laser on it (the
## user). For a quad layer, what is in front is therefore drawn again as layers over the film: for each eye a
## viewport with a camera at that eye, its frustum through the picture's rectangle and ending just short of it, on a
## clear ground, shown by a quad layer where the screen is (sort_order 1, blended, that eye only). The room's own
## drawing of the same things lies under the film; outside the picture it is what is seen. Only while something is in
## front (the menu, a laser, a controller, a room object); the film's layer stays. Over a cylinder layer too, on the
## plane through the curve's edges (_place_front()).
## A room that draws the film itself (its presentation: a telly's glass, a worn print; scripts/env/systems/
## presentation.gd) asks with request_scene(who, true): while any asks, no layer is made (wanted_kind() ""), so the
## screen's mesh draws the film with the room's material; the setting is not touched.
##
##   enabled, set_enabled(on, save := true)
##   force                  tests: build the layers without an XR session (they don't show then)
##   request_scene(who, on), scene_requests   the film drawn in the scene for a room (see above)
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
## Seconds clear of room objects before the layer comes back.
const COVER_RELEASE := 1.0
## The layers over the film: the picture's height in pixels (the width follows its shape), and the nearest drawn.
const FRONT_HEIGHT := 1440
const FRONT_MAX_WIDTH := 3072
const FRONT_NEAR := 0.03
## The render layer (18; 19 and 20 are the mirrors' and the private one) of what the layers over the film draw: the menu and the other panels, the controllers with
## their lasers, the room objects that can be picked up, and a room's things in front of the screen. Not the room
## itself: a projector's beam or a haze adds light with a full alpha, and the film behind went black (2026-11-23).
const FRONT_BIT := 1 << 17

var main: Node3D
var enabled := false
## The layers are hidden for the menu (see the header).
var held := false
## What is in front of the film, drawn over it (see "In front of the film" in the header): one quad layer an eye,
## above the film's, each with a camera at that eye looking through the picture's rectangle.
var front_layers: Array[Node3D] = []
var front_views: Array[SubViewport] = []
var _front_cams: Array[Camera3D] = []
## In use now: something is in front of the film and the layers over it draw it.
var front := false
## Off (tests; user://no_front_layer on the device, read once a second): the film is drawn in the scene instead while
## something is in front, as before.
var front_enabled := true
var _front_check := 0
var _front_mark := 0
## The room object that last covered the picture ("" none), and when the view was last covered (ticks, ms).
var covered_by := ""
var _covered_ms := -1000000
## Node -> its bounds in its own frame (from its meshes), worked out once.
var _local_aabbs := {}
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
## Curved screens as cylinder layers when the runtime has them ([view] cylinder_layers): on by default (the user,
## 2026-11-09; it was off by default before, for this reason:). SteamOS
## 0.5.7 (SteamVR 2.19.1) brought cylinder layers to the Frame, and the runtime drew them over everything in the
## room (an icicle in front of the screen, the user, 2026-11-04): the hole punch that keeps a quad layer behind the
## scene did not hold for them. The mesh draws a curved screen in the right place; this is for trying the layers.
var cylinder_layers := true
## Tests: no layers over the film.
var front_off := false
## Who asks for the film in the scene (request_scene): {who: true}.
var scene_requests := {}


func _ready() -> void:
	# After the player's update and the features that set the screen's uniforms each frame.
	process_priority = 100
	enabled = bool(main.settings.get_value("view", "film_layer", true))
	cylinder_layers = bool(main.settings.get_value("view", "cylinder_layers", true))
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


## The film drawn in the scene while `who` asks (a room's presentation); not kept.
func request_scene(who: String, on: bool) -> void:
	if on:
		scene_requests[who] = true
	else:
		scene_requests.erase(who)
	if main != null and is_inside_tree():
		_update()


## Curved screens as cylinder layers (see cylinder_layers), kept in the settings.
func set_cylinder_layers(on: bool) -> void:
	cylinder_layers = on
	main.settings.set_value("view", "cylinder_layers", null if on else false)
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
	if not enabled or not available() or not _xr_running() or not scene_requests.is_empty():
		return ""
	var screen: Node3D = main.screen
	if not main.player.has_source() or not screen.is_shown() or screen.mode.projection != VideoMode.Proj.FLAT:
		return ""
	if float(screen.curve_radius) > 0.0:
		return "cylinder" if force or (cylinder_layers and _has_cylinder()) else ""
	return "quad"


## The line under the System tab's switch, in the menus' language (docs/i18n.md).
func status() -> String:
	if not enabled:
		return tr("Off: the film is drawn in the room.")
	if not available():
		return tr("This engine has no OpenXR layers.")
	if not _xr_running():
		return tr("Only in the headset: here the film is drawn in the room.")
	if kind == "":
		if not scene_requests.is_empty():
			return tr("On; this room draws the film itself, for the look of its screen.")
		if main.player.has_source() and main.screen.mode.projection != VideoMode.Proj.FLAT:
			return tr("180, 360 and fisheye films are drawn in the room.")
		if main.player.has_source() and float(main.screen.curve_radius) > 0.0:
			if _has_cylinder() and not cylinder_layers:
				return tr("A curved screen is drawn in the room (curved layers are off).")
			return tr("This headset has no curved layers: a curved screen is drawn in the room.")
		return tr("On; nothing to show.")
	var px: Vector2i = viewports[0].size
	if held and not bool(main.get("menu_shown")) and covered_by != "":
		return tr("On; the room draws the film while something is in front of the screen, so it shows.")
	if held:
		return tr("On; the room draws the film while the menu is open, so the menu shows in front.")
	if layers.size() == 2:
		return (tr("In use: two cylinder layers, one per eye, %d x %d px each.") if kind == "cylinder"
				else tr("In use: two quad layers, one per eye, %d x %d px each.")) % [px.x, px.y]
	return (tr("In use: one cylinder layer, %d x %d px.") if kind == "cylinder"
			else tr("In use: one quad layer, %d x %d px.")) % [px.x, px.y]


## The name of a room object, a controller's part ("RightHand Visual") or the laser whose bounds, seen from the eyes,
## cover part of the flat picture and lie between the eyes and the screen; "" when none does.
func _covered() -> String:
	var physics: Node = main.features.get("physics") if main.get("features") != null else null
	var flat := main.screen.get_node_or_null("Flat") as Node3D if main.screen != null else null
	var cam := main.get_viewport().get_camera_3d() if main.is_inside_tree() else null
	if flat == null or cam == null:
		return ""
	var nodes: Array = physics.solid_nodes() if physics != null and physics.has_method("solid_nodes") else []
	# The controllers (their models and legends, which load late: not kept), the laser and its dot while they show.
	var fresh := {}
	var wp: Node = main.get("window_pointer")
	for hand: Node in main.get("hands") if main.get("hands") != null else []:
		if not (hand is Node3D) or not (hand as Node3D).is_visible_in_tree():
			continue
		# A laser that is the pointer on a captured window (scripts/window_pointer.gd) does not count: the window is
		# read and worked with the laser on it, and the mesh's picture is too coarse for a page's text (the user,
		# 2026-11-23). The layer stays; the beam ends at the picture's edge, and the cursor drawn into the picture
		# shows where it points.
		# Only where nothing can be drawn over the film (front_enabled off, a cylinder layer).
		var pointing: bool = not front_enabled and wp != null and bool(wp.has_cursor()) 				and bool(wp.owns_laser(hand))
		for part: String in ["Visual", "Laser", "Dot"]:
			if pointing and part != "Visual":
				continue
			var n := hand.get_node_or_null(part) as Node3D
			if n != null and n.is_visible_in_tree():
				nodes.append(n)
				if part == "Visual":
					fresh[n.get_instance_id()] = true
	# A room's things that stand in front of the screen on purpose (motion's in_front: a painting, a festoon; group
	# env_in_front, docs/environments.md), while they show.
	for n: Node in main.get_tree().get_nodes_in_group("env_in_front") if main.is_inside_tree() else []:
		if n is Node3D and (n as Node3D).is_visible_in_tree():
			nodes.append(n)
			fresh[n.get_instance_id()] = true
	if nodes.is_empty():
		return ""
	var screen := Transform3D(flat.global_transform.basis.orthonormalized(), flat.global_transform.origin)
	var half: Vector2 = main.screen.get_flat_size() * 0.5
	var eye := screen.affine_inverse() * cam.global_position
	if eye.z <= 0.01:
		return ""
	# A curved screen (cylinder layers drew over an icicle, 2026-11-04): every point of the curve lies on or in front
	# of the plane through its middle, so that plane never misses what is in front; its edges come forward by the
	# sagitta, so seen from the eyes they reach wider than the flat half-width: widened to match.
	var radius := float(main.screen.get("curve_radius")) if kind == "cylinder" else 0.0
	if radius > 0.0:
		var phi := half.x / radius
		var sag := radius * (1.0 - cos(phi))
		var reach := radius * sin(phi) * eye.z / maxf(eye.z - sag, 0.01)
		half.x = maxf(half.x, reach) * 1.02
	for n: Node3D in nodes:
		if fresh.has(n.get_instance_id()):
			_local_aabbs.erase(n.get_instance_id())
		if _covers(screen, eye, half, n):
			return str(n.name) if not (n.get_parent() is XRController3D) else "%s %s" % [n.get_parent().name, n.name]
	return ""


## Whether `n`'s bounds cover part of the picture (half its size, in the screen's frame) seen from `eye` (the same
## frame, +Z towards the viewer): each corner in front of the screen and behind the eyes, carried along its line from
## the eye onto the screen's plane; the box of those points meets the picture.
func _covers(screen: Transform3D, eye: Vector3, half: Vector2, n: Node3D) -> bool:
	var local: AABB = _local_aabb(n)
	if local.size == Vector3.ZERO:
		return false
	var to_screen := screen.affine_inverse() * n.global_transform
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var any := false
	for i in 8:
		var c := to_screen * local.get_endpoint(i)
		# Behind the screen's plane, or at or behind the eyes: not between them.
		if c.z <= 0.0 or c.z >= eye.z - 0.02:
			continue
		var k := eye.z / (eye.z - c.z)
		var on := Vector2(eye.x + (c.x - eye.x) * k, eye.y + (c.y - eye.y) * k)
		lo = lo.min(on)
		hi = hi.max(on)
		any = true
	return any and lo.x < half.x and hi.x > -half.x and lo.y < half.y and hi.y > -half.y


func _local_aabb(n: Node3D) -> AABB:
	var id := n.get_instance_id()
	if _local_aabbs.has(id):
		return _local_aabbs[id]
	var box := AABB()
	var first := true
	var inv := n.global_transform.affine_inverse()
	for v in [n] + n.find_children("*", "VisualInstance3D", true, false):
		if not (v is VisualInstance3D) or str(v.name).begins_with("Contact_"):
			continue
		var b: AABB = (inv * (v as VisualInstance3D).global_transform) * (v as VisualInstance3D).get_aabb()
		if b.size == Vector3.ZERO:
			continue
		box = b if first else box.merge(b)
		first = false
	# Not kept while it has no meshes yet (a model still loading).
	if box.size != Vector3.ZERO:
		if _local_aabbs.size() > 256:
			_local_aabbs.clear()
		_local_aabbs[id] = box
	return box


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
		held = false
		return
	# Marking a window to the real room: the whole view is the cameras, the screen too (real_windows.gd).
	var rw: Node = main.features.get("real_windows") if main.get("features") != null else null
	var hold := bool(main.get("menu_shown")) or (rw != null and bool(rw.get("marking")))
	if not hold and kind in ["quad", "cylinder"]:
		var by := _covered()
		if by != "":
			covered_by = by
			_covered_ms = Time.get_ticks_msec()
		hold = Time.get_ticks_msec() - _covered_ms < int(COVER_RELEASE * 1000.0)
	# A quad layer: what is in front is drawn over the film instead (the header, "In front of the film").
	_front_check -= 1
	if _front_check <= 0:
		_front_check = 60
		front_enabled = not FileAccess.file_exists("user://no_front_layer") and not front_off
	var marking := rw != null and bool(rw.get("marking"))
	var want_front := hold and kind in ["quad", "cylinder"] and front_enabled and not marking
	_set_front(want_front)
	if want_front:
		hold = false
		_front_mark -= 1
		if _front_mark <= 0:
			_front_mark = 30
			_mark_front()
		_place_front()
	if hold != held:
		held = hold
		for layer in layers:
			layer.visible = not held
		main.screen.set_flat_drawn(held)
		_dirty = true
	if held:
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
	held = false
	main.screen.set_flat_drawn(false)
	print("Film layer: %d %s layer(s), %d x %d px, natively supported: %s" % [eyes, kind, px.x, px.y,
			layers[0].call("is_natively_supported")])


func _drop() -> void:
	# The layers live under the screen, which may be gone first when the app quits.
	for n: Variant in layers + viewports + front_layers + front_views:
		if is_instance_valid(n):
			(n as Node).free()
	front_layers.clear()
	front_views.clear()
	_front_cams.clear()
	front = false
	layers.clear()
	viewports.clear()
	_materials.clear()
	kind = ""
	_frame_key = NAN
	if is_instance_valid(main) and is_instance_valid(main.screen):
		main.screen.set_flat_drawn(true)


## The layers on the screen's picture: a quad of its flat size at its centre, or a cylinder whose axis is `radius`
## in front of it (the curved mesh bends toward the viewer; the layer's arc lies at -Z from its pose).
## The layers over the film on or off; made the first time.
func _set_front(on: bool) -> void:
	if on == front:
		return
	front = on
	if on and front_layers.is_empty():
		for eye in 2:
			var vp := SubViewport.new()
			vp.name = "FilmFrontView%d" % eye
			vp.transparent_bg = true
			vp.gui_disable_input = true
			vp.msaa_3d = Viewport.MSAA_2X
			var cam := Camera3D.new()
			cam.name = "FilmFrontCamera%d" % eye
			cam.keep_aspect = Camera3D.KEEP_HEIGHT
			cam.cull_mask = FRONT_BIT
			vp.add_child(cam)
			add_child(vp)
			cam.current = true
			var layer: Node3D = ClassDB.instantiate("OpenXRCompositionLayerQuad")
			layer.name = "FilmFront%d" % eye
			layer.set("layer_viewport", vp)
			layer.set("sort_order", 1 + eye)
			layer.set("alpha_blend", true)
			layer.set("eye_visibility", 1 + eye)
			main.screen.add_child(layer)
			front_views.append(vp)
			_front_cams.append(cam)
			front_layers.append(layer)
		print("Film layer: what is in front is drawn over the film (two layers)")
	if on:
		_front_mark = 0
	for layer in front_layers:
		layer.visible = on
	for vp in front_views:
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED


## Puts what can be in front of the film on the layers' render layer (again every half second while in use: models
## and legends load late, objects are made).
func _mark_front() -> void:
	var roots: Array = []
	for hand: Node in main.get("hands") if main.get("hands") != null else []:
		roots.append(hand)
	if main.get("ui") != null:
		roots.append(main.ui)
	var physics: Node = main.features.get("physics") if main.get("features") != null else null
	if physics != null and physics.has_method("solid_nodes"):
		roots.append_array(physics.solid_nodes())
	if main.is_inside_tree():
		roots.append_array(main.get_tree().get_nodes_in_group("env_in_front"))
	while not roots.is_empty():
		var n: Node = roots.pop_back()
		if not is_instance_valid(n) or n in front_layers:
			continue
		if n is VisualInstance3D and (n as VisualInstance3D).layers & FRONT_BIT == 0:
			(n as VisualInstance3D).layers |= FRONT_BIT
		# Not into a panel's own viewport: hundreds of controls, none of them drawn in the room (walking them
		# every half second was a stutter, the user, 2026-11-23).
		if not (n is Viewport):
			roots.append_array(n.get_children())


## Each eye's camera at that eye, square to the screen, its frustum through the picture's rectangle and ending just
## short of the screen.
func _place_front() -> void:
	var flat := main.screen.get_node_or_null("Flat") as Node3D
	if flat == null:
		return
	var size: Vector2 = main.screen.get_flat_size()
	var w := mini(FRONT_MAX_WIDTH, roundi(FRONT_HEIGHT * size.x / maxf(size.y, 0.01)))
	var px := Vector2i(maxi(2, w - w % 2), FRONT_HEIGHT)
	var screen := Transform3D(flat.global_transform.basis.orthonormalized(), flat.global_transform.origin)
	# A curved screen: its edges come forward by the sagitta. The layers stand on the plane through those edges (the
	# chord, as wide as the curve is seen), and the cameras draw on to the curve's middle behind it.
	var sag := 0.0
	var radius := float(main.screen.get("curve_radius")) if kind == "cylinder" else 0.0
	if radius > 0.0:
		var phi := size.x * 0.5 / radius
		sag = radius * (1.0 - cos(phi))
		size.x = 2.0 * radius * sin(phi)
		w = mini(FRONT_MAX_WIDTH, roundi(FRONT_HEIGHT * size.x / maxf(size.y, 0.01)))
		px = Vector2i(maxi(2, w - w % 2), FRONT_HEIGHT)
		screen = screen * Transform3D(Basis(), Vector3(0.0, 0.0, sag))
	for eye in front_layers.size():
		if not (front_layers[eye].get("quad_size") as Vector2).is_equal_approx(size):
			front_layers[eye].set("quad_size", size)
		front_layers[eye].position = Vector3(0.0, 0.0, sag)
		if front_views[eye].size != px:
			front_views[eye].size = px
		var at := screen.affine_inverse() * eye_position(eye)
		var cam := _front_cams[eye]
		if at.z <= FRONT_NEAR * 2.0:
			# At or behind the screen: nothing is in front.
			front_layers[eye].visible = false
			continue
		front_layers[eye].visible = true
		cam.global_transform = Transform3D(screen.basis, screen * at)
		var k := FRONT_NEAR / at.z
		cam.set_frustum(size.y * k, Vector2(-at.x, -at.y) * k, FRONT_NEAR, at.z + sag - 0.004)


## Where an eye is in the world (0 left, 1 right): the headset's, or beside the camera without a session.
func eye_position(eye: int) -> Vector3:
	var xr := XRServer.primary_interface
	var origin := main.get_node_or_null("XROrigin3D") as Node3D
	if xr != null and xr.is_initialized() and origin != null and xr.get_view_count() > eye:
		return xr.get_transform_for_view(eye, origin.global_transform).origin
	var cam := main.get_viewport().get_camera_3d()
	if cam == null:
		return Vector3.ZERO
	return cam.global_transform * Vector3(-0.032 if eye == 0 else 0.032, 0.0, 0.0)


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
