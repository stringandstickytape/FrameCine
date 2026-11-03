extends SceneTree

## Tests for the quad layer spike (scripts/xr_spikes/quad_layers.gd, ideas #70) in the real main scene, forced on
## without an XR session: the layers are built, placed and sized, the scene's own pane quad and screen quad stop being
## drawn, and everything comes back when the layers go. The runtime's composition itself needs the headset. With a
## renderer, the two eyes' viewports of a 3D pattern are checked to show different pictures.
## Run: godot --xr-mode off --path app --script res://tests/test_quad_layers.gd

const QuadLayers := preload("res://scripts/xr_spikes/quad_layers.gd")

var _failures := 0
var _checks := 0
var main: Node3D


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	await _frames(5)
	if not QuadLayers.available():
		print("SKIP (no OpenXRCompositionLayerQuad in this engine)")
		print("test_quad_layers: 0 checks, all passed")
		quit(0)
		return
	_check("no flags: nothing added", QuadLayers.attach(main, {}, true) == null)
	_check("no XR session: nothing added", QuadLayers.attach(main, {"pane-layer": true}) == null)
	var q: Node = QuadLayers.attach(main, {"pane-layer": true, "video-layer": true}, true)
	main.set_environment("void")
	main.open_path("stub://flat_sbs")
	await _frames(5)
	var pane: Node3D = main.ui.panel
	var layer: Node3D = q.pane_layer
	_check("pane layer under the XR origin", layer != null and layer.get_parent() == main.xr_origin)
	_check("pane layer shows the pane's viewport at the pane's size", layer.get("layer_viewport") == pane.viewport
			and layer.get("quad_size") == pane.size_m and layer.get("sort_order") == 1)
	_check("the pane's own quad is not drawn", not pane.get_node("Quad").visible)
	main.ui.call("show_pane") if main.ui.has_method("show_pane") else pane.fade_to(1.0)
	await create_timer(0.6).timeout
	_check("pane layer follows the pane (shown %s)" % pane.visible, layer.global_transform.origin.distance_to(
			pane.global_transform.origin) < 0.001 and layer.visible == (pane.visible and pane.opacity > 0.5))

	_check("video layers: two, one per eye", q.video_layers.size() == 2
			and q.video_layers[0].get("eye_visibility") == 1 and q.video_layers[1].get("eye_visibility") == 2)
	_check("behind the scene with a hole punched", q.video_layers[0].get("enable_hole_punch")
			and q.video_layers[0].get("sort_order") == -1)
	var px: Vector2i = q.eye_pixels()
	_check("each eye's viewport is one eye's picture (%s)" % px, px == Vector2i(1920, 1080)
			and q.video_viewports[0].size == px and q.video_viewports[1].size == px)
	_check("at the screen's pose and size", q.video_layers[1].global_transform.origin.distance_to(
			main.screen.global_position) < 0.001 and q.video_layers[1].get("quad_size") == main.screen.get_flat_size())
	_check("the screen's own quad is not drawn", main.screen.get_node("Flat").layers == 0)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var l: Image = q.video_viewports[0].get_texture().get_image()
		var r: Image = q.video_viewports[1].get_texture().get_image()
		var differ := 0
		for y in range(0, l.get_height(), 97):
			for x in range(0, l.get_width(), 97):
				if not l.get_pixel(x, y).is_equal_approx(r.get_pixel(x, y)):
					differ += 1
		_check("the eyes' pictures differ on a 3D pattern (%d samples)" % differ, differ > 5)
	main.open_path("stub://360_mono")
	await _frames(3)
	_check("360: no video layers, the screen drawn again", q.video_layers.is_empty()
			and main.screen.get_node("Flat").layers == 1)
	main.open_path("stub://flat_mono")
	await _frames(3)
	_check("flat again: layers back", q.video_layers.size() == 2)
	q.queue_free()
	await _frames(2)
	_check("spike removed: pane quad and screen drawn", pane.get_node("Quad").visible
			and main.screen.get_node("Flat").layers == 1)
	print("test_quad_layers: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL ", what)
	else:
		print("PASS ", what)
