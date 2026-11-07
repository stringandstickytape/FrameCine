extends SceneTree

## A room document's own screen through the app (scripts/env/env_room.gd): its curve (screen.curve, the Flagship) is
## the screen's until the viewer sets one, and a builder's screen that moves with a setting (the Pillow Fort's telly
## filling the fort's opening) moves the app's screen with it.
##
## godot --headless --xr-mode off --path app --script res://tests/test_env_screen_follow.gd

var _failures := 0
var _checks := 0
var main: Node3D


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.settings.read_only = true
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _run() -> void:
	await _frames(5)
	await _test_curve()
	await _test_telly()
	main.queue_free()
	await _frames(2)
	print("test_env_screen_follow: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _test_curve() -> void:
	main.settings.set_value("screen_flagship", "curve_radius", null)
	main.set_environment("flagship")
	await _frames(3)
	var curve: Node = main.features.curve
	_check("the Flagship's screen starts curved by its document (%.2f)" % curve.amount, is_equal_approx(curve.amount, 0.3)
			and main.screen.curve_radius > 0.0 and is_equal_approx(main.env.get_home_curve(), 0.3))
	curve.set_amount(0.0)
	_check("flattened, it keeps 0 (%s)" % [main.settings.get_value("screen_flagship", "curve_radius", "none")],
			main.settings.has_value("screen_flagship", "curve_radius")
			and is_zero_approx(float(main.settings.get_value("screen_flagship", "curve_radius", -1.0))))
	main.set_environment("void")
	await _frames(2)
	_check("the Void has no curve of its own", main.env.get_home_curve() < 0.0 or not main.env.has_method("get_home_curve")
			or main.env.get_home_curve() < 0.0)
	main.set_environment("flagship")
	await _frames(3)
	_check("and the Flagship stays flat when the viewer flattened it", curve.amount == 0.0)
	main.settings.set_value("screen_flagship", "curve_radius", null)
	main.set_environment("crater")
	await _frames(3)
	_check("a room with no curve opens flat (%.2f)" % curve.amount, curve.amount == 0.0)


func _test_telly() -> void:
	main.settings.set_value("room:pillow_fort_1993", "telly_fills", null)
	main.set_environment("pillow_fort_1993")
	await _frames(4)
	var rs: Node = main.features.room_settings
	var near_d: float = main.screen_distance
	var near_w: float = main.screen_width
	_check("the telly fills the fort's opening: the screen close (%.2f m, %.2f m wide)" % [near_d, near_w],
			bool(rs.value("telly_fills")) and near_d < 1.6)
	var err: String = rs.set_value("telly_fills", false)
	await _frames(4)
	var far_d: float = main.screen_distance
	_check("off: the room builds again and the screen goes with the telly across the room (%.2f m, %.2f m wide) %s"
			% [far_d, main.screen_width, err], err == "" and far_d > near_d + 0.5
			and not is_equal_approx(main.env.default_screen_width, near_w))
	var anchor: Transform3D = main.env.get_screen_anchor()
	var sc: Dictionary = (load("res://scripts/env/systems/domestic.gd") as GDScript).call("screen_for",
			main.env.host.system("room").params)
	_check("the screen's anchor is where the builder puts the telly now (%s, %s)" % [anchor.origin, sc["center"]],
			anchor.origin.distance_to(Vector3(sc["center"][0], sc["center"][1], sc["center"][2])) < 0.05)
	rs.set_value("telly_fills", true)
	await _frames(4)
	_check("on again: back in the opening (%.2f m)" % main.screen_distance, absf(main.screen_distance - near_d) < 0.05
			and absf(main.screen_width - near_w) < 0.05)
	main.settings.set_value("room:pillow_fort_1993", "telly_fills", null)


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
