extends SceneTree

## Tests for rooms lighting themselves (scripts/env/room_lightmaps.gd): which rooms are built for it, the setting,
## and, with a GPU renderer (lavapipe under xvfb; headless has no lightmapper), the cinema baked on its first
## showing and loaded from the kept bake on its second.
##   godot --headless --xr-mode off --path app --script res://tests/test_room_lightmaps.gd

const RoomBake := preload("res://scripts/env/room_bake.gd")

var main: Node3D
var passed := 0
var failed := 0


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	await _frames(5)
	var lm: Node = main.features.lightmaps
	_check("the feature is there, on by default", lm != null and lm.enabled)
	main.set_environment("void")
	await _frames(2)
	_check("the void is not built for a lightmap", not lm.room_bakeable())
	lm.set_enabled(false)
	_check("off: kept in the settings", not lm.enabled and main.settings.get_value("env", "lightmaps", true) == false)
	lm.set_enabled(true)
	_check("on again: the setting cleared", lm.enabled and main.settings.get_value("env", "lightmaps", true) == true)
	RoomBake.clear("cinema")
	main.set_environment("cinema")
	await _frames(2)
	_check("the cinema is built for a lightmap", lm.room_bakeable())
	# A saved screen placement outlives its room only while the room's own screen stays where it was.
	var own: Dictionary = main.env.get_default_screen()
	main.settings.set_value("screen_cinema", "distance", float(own["distance"]) - 4.0)
	main.settings.set_value("screen_cinema", "room_default", "another layout")
	main.set_environment("void")
	await _frames(1)
	main.set_environment("cinema")
	await _frames(1)
	_check("a placement saved for another layout of the room is dropped (%.1f)" % main.screen_distance,
			is_equal_approx(main.screen_distance, float(own["distance"]))
			and main.settings.get_value("screen_cinema", "room_default", null) == null)
	main.screen_distance = float(own["distance"]) - 2.0
	main._save_screen_settings()
	main.set_environment("void")
	await _frames(1)
	main.set_environment("cinema")
	await _frames(1)
	_check("one saved for this layout stays (%.1f)" % main.screen_distance,
			is_equal_approx(main.screen_distance, float(own["distance"]) - 2.0))
	main.settings.set_value("screen_cinema", "distance", null)
	main.settings.set_value("screen_cinema", "room_default", null)
	if not RoomBake.can_bake():
		_check("no lightmapper here: nothing baked, the room keeps its shader light", lm.last.is_empty()
				and main.env.get_node_or_null("RoomLightmap") == null)
		_done()
		return
	var end := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < end and not (bool(lm.last.get("baked", false)) or bool(lm.last.get("loaded", false))):
		await process_frame
	var r: Dictionary = lm.last.get("result", {})
	_check("the first showing bakes the cinema (%s, %.1f s)" % [r.get("error", "?"), float(r.get("seconds", 0.0))],
			bool(lm.last.get("baked", false)) and not bool(lm.last.get("loaded", false)))
	await _frames(3)
	var node: Node = main.env.get_node_or_null("RoomLightmap")
	_check("the room shows it: a LightmapGI with data, the cinema's baked look", node != null
			and node.get("light_data") != null and bool(main.env.get("_baked")))
	main.set_environment("void")
	await _frames(2)
	main.set_environment("cinema")
	var end2 := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < end2 and not (bool(lm.last.get("baked", false)) or bool(lm.last.get("loaded", false))):
		await process_frame
	_check("the second showing loads the kept bake", bool(lm.last.get("loaded", false)) and not bool(lm.last.get("baked", false))
			and main.env.get_node_or_null("RoomLightmap") != null)
	var again: Dictionary = await lm.bake_now()
	_check("bake_now() bakes it afresh (%s)" % again.get("error", "?"), bool(again.get("ok", false))
			and bool(lm.last.get("baked", false)))
	RoomBake.clear("cinema")
	_done()


func _check(what: String, ok: bool) -> void:
	if ok:
		passed += 1
		print("PASS ", what)
	else:
		failed += 1
		print("FAIL ", what)


func _done() -> void:
	print("test_room_lightmaps: %d checks, %s" % [passed + failed, "all passed" if failed == 0 else "%d FAILED" % failed])
	quit(1 if failed > 0 else 0)
