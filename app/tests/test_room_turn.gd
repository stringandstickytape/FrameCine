extends SceneTree

## The right squeeze on no object holds the room and turns it about the viewer (scripts/main.gd, _update_turn()), in the
## real main scene: what the laser is on stays under it as the hand swings, the head stays where it is, the left
## squeeze turns nothing, letting go stops it, and recentre puts the room straight again.
##
## godot --headless --xr-mode off --path app --script res://tests/test_room_turn.gd

var _failures := 0
var _checks := 0
var main: Node3D


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _run() -> void:
	await _frames(5)
	main.ui.hide_panel()
	await _frames(2)
	main.set_process(false)
	var hand: Node3D = main.right_hand
	var origin: Node3D = main.xr_origin
	hand.position = Vector3(0.2, 1.1, -0.3)
	hand.rotation = Vector3.ZERO
	var head: Vector3 = main.camera.global_position
	var aimed: Vector3 = hand.get_ray_direction()
	main._on_grip(hand, true)
	hand.grip_down = true
	_check("the right squeeze on nothing holds the room", not main._turn.is_empty())
	main._update_turn()
	_check("held still: nothing turns", origin.global_transform.is_equal_approx(Transform3D.IDENTITY))
	# The hand swings 30 degrees to the left (in its own tracking space).
	hand.rotation.y = deg_to_rad(30.0)
	main._update_turn()
	var turned: float = origin.global_basis.get_euler().y
	_check("the room turns with the hand (%.1f degrees)" % rad_to_deg(turned), absf(absf(turned) - deg_to_rad(30.0)) < 0.001)
	_check("what the laser was on stays under it (%s)" % hand.get_ray_direction(),
			hand.get_ray_direction().distance_to(aimed) < 0.001)
	_check("the head stays where it is", main.camera.global_position.distance_to(head) < 0.001)
	hand.rotation.y = deg_to_rad(75.0)
	main._update_turn()
	_check("and goes on turning", hand.get_ray_direction().distance_to(aimed) < 0.001
			and main.camera.global_position.distance_to(head) < 0.001)
	# Pointing straight up there is no turn to read: nothing jumps, then or after.
	var before: Transform3D = origin.global_transform
	hand.rotation = Vector3(deg_to_rad(89.0), deg_to_rad(75.0), 0.0)
	main._update_turn()
	hand.rotation = Vector3(0.0, deg_to_rad(20.0), 0.0)
	main._update_turn()
	_check("a hand pointing straight up turns nothing, and coming back does not jump",
			origin.global_transform.is_equal_approx(before))
	hand.grip_down = false
	main._on_grip(hand, false)
	hand.rotation.y = deg_to_rad(-40.0)
	if not main._turn.is_empty():
		main._update_turn()
	_check("let go: the room stays", main._turn.is_empty() and origin.global_transform.is_equal_approx(before))
	var left: Node3D = main.left_hand
	main._on_grip(left, true)
	_check("the left squeeze holds nothing", main._turn.is_empty())
	main._on_grip(left, false)
	main.recenter()
	_check("recentre puts the room straight", origin.transform.is_equal_approx(Transform3D.IDENTITY))
	main.queue_free()
	await _frames(2)
	print("test_room_turn: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(1 if _failures > 0 else 0)


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL " + what)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
