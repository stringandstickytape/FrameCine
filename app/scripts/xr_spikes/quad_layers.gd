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
## --video-layer   the film layer (scripts/play/film_layer.gd, [view] film_layer) on for this run, without saving it:
##                 the flat screen as quad layers behind the scene, with a hole punched where the screen is.
## Without an XR session (a desktop) the flags only print that they do nothing. The normal path stays the default.

var main: Node3D
var pane_layer: Node3D


static func available() -> bool:
	return ClassDB.class_exists("OpenXRCompositionLayerQuad")


## Adds the spike when --pane-layer is given; --video-layer turns the film layer on for the run. force: without an XR
## session too (tests; the layers do not show then).
static func attach(m: Node3D, args: Dictionary, force := false) -> Node:
	var pane := args.has("pane-layer")
	var video := args.has("video-layer")
	if not pane and not video:
		return null
	if not available():
		print("Quad layers: this engine has no OpenXRCompositionLayerQuad")
		return null
	if video and m.get("features") != null:
		m.features.film_layer.set_enabled(true, false)
		print("Quad layers: --video-layer turns the film layer on for this run")
	var xr := XRServer.find_interface("OpenXR")
	if not force and (xr == null or not xr.is_initialized() or not m.use_xr):
		print("Quad layers: no XR session; --pane-layer and --video-layer do nothing on a desktop")
		return null
	if not pane:
		return null
	var s: Node = (load("res://scripts/xr_spikes/quad_layers.gd") as GDScript).new()
	s.name = "QuadLayers"
	s.main = m
	m.add_child(s)
	return s


func _ready() -> void:
	_make_pane_layer.call_deferred()


func _new_layer(viewport: SubViewport, size: Vector2) -> Node3D:
	var layer: Node3D = ClassDB.instantiate("OpenXRCompositionLayerQuad")
	layer.set("layer_viewport", viewport)
	layer.set("quad_size", size)
	layer.set("alpha_blend", true)
	main.xr_origin.add_child(layer)
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


func _exit_tree() -> void:
	var pane := _pane()
	if pane != null and pane.get_node_or_null("Quad") != null:
		pane.get_node("Quad").visible = true
	if pane_layer != null:
		pane_layer.queue_free()
