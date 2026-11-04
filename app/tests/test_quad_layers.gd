extends SceneTree

## Tests for the quad layer spike (scripts/xr_spikes/quad_layers.gd, ideas #70) in the real main scene, forced on
## without an XR session: the pane's layer is built, placed and sized, the pane's own quad stops being drawn and comes
## back when the spike goes. --video-layer turns the film layer on for the run (its own tests:
## tests/test_film_layer.gd). The runtime's composition itself needs the headset.
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
	_check("--video-layer alone: no spike node", QuadLayers.attach(main, {"video-layer": true}, true) == null)
	_check("--video-layer: the film layer on for the run, not saved", main.features.film_layer.enabled
			and not main.settings.has_value("view", "film_layer"))
	var q: Node = QuadLayers.attach(main, {"pane-layer": true}, true)
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
	_check("no XR session: the screen keeps its quad", main.screen.get_node("Flat").visible)
	q.queue_free()
	await _frames(2)
	_check("spike removed: pane quad drawn", pane.get_node("Quad").visible)
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
