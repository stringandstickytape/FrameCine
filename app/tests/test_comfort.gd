extends SceneTree

## Tests for the screen comfort features (ideas #12, #19, #33, #55) in the real main scene, on the desktop camera:
## lying down, head follow and pin, screen size in degrees and its presets, seat choice. Settings are read-only.
## Run: godot --headless --xr-mode off --path app --script res://tests/test_comfort.gd

var _failures := 0
var _checks := 0
var main: Node3D


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	_run.call_deferred()


func _look(yaw_deg: float, pitch_deg: float) -> void:
	main._look = Vector2(yaw_deg, pitch_deg)
	main._apply_look()


func _screen_dir() -> Vector3:
	return (main.screen.global_position - Vector3(0, main.eye_height, 0)).normalized()


func _run() -> void:
	await _frames(5)
	var f: Node = main.features
	main.set_environment("void")
	main.open_path("stub://flat_mono")
	await _frames(5)
	var start: Vector3 = main.screen.global_position

	# #12 lying down: up to where the head points, slowly following pitch, never roll; back on off.
	_look(0.0, 70.0)
	f.pose.set_lying(true)
	await _frames(2)
	var elev := rad_to_deg(asin(_screen_dir().y))
	_check("lying down: the screen goes up to the head's pitch (%.0f deg)" % elev, absf(elev - 70.0) < 2.0)
	_check("it faces the viewer", main.screen.global_transform.basis.z.dot(-_screen_dir()) > 0.99)
	_check("roll stays level", absf(main.screen.global_transform.basis.x.y) < 0.001)
	_look(0.0, 85.0)
	await _sleep(0.5)
	elev = rad_to_deg(asin(_screen_dir().y))
	_check("a small head move (15 deg) is followed slowly: still on the way after 0.5 s (%.1f)" % elev, elev > 70.5 and elev < 80.0)
	await _sleep(7.5)
	elev = rad_to_deg(asin(_screen_dir().y))
	_check("... and gets there (%.1f)" % elev, absf(elev - 85.0) < 2.5)
	_look(0.0, 80.0)
	await _sleep(1.0)
	elev = rad_to_deg(asin(_screen_dir().y))
	_check("inside the dead zone (5 deg): no move (%.1f)" % elev, elev > 82.0)
	var sub: Node = f.subtitles
	var t: float = main.player.get_position()
	sub.select_track(0)
	sub.add_event(t - 0.5, t + 60.0, "on the ceiling")
	await _frames(3)
	var q: Node3D = sub.display.get_node("Quad")
	_check("subtitles follow the screen up", q.global_position.y > main.eye_height + 1.0)
	sub.set_enabled(false)
	main.open_path("stub://360_mono")
	await _frames(3)
	_check("360 turns up too (sphere tilt %.0f deg)" % rad_to_deg(main.screen.sphere_tilt.x), rad_to_deg(main.screen.sphere_tilt.x) > 75.0)
	main.open_path("stub://flat_mono")
	await _frames(3)
	f.pose.set_lying(false)
	await _frames(2)
	_check("off: the screen is back", main.screen.global_position.is_equal_approx(start)
			and is_zero_approx(main.screen.sphere_tilt.x))
	_look(0.0, 0.0)

	# #33 head follow: follows a big turn lazily, not a small one; pinning keeps the place.
	f.pose.set_follow(true)
	_look(10.0, 0.0)
	await _sleep(0.6)
	_check("follow: a 10 deg glance doesn't move it", main.screen.global_position.is_equal_approx(start))
	_look(60.0, 0.0)
	await _sleep(2.0)
	var dir := _screen_dir()
	var yaw := rad_to_deg(atan2(dir.x, -dir.z))
	_check("follow: a 60 deg turn brings the screen round (%.0f deg)" % yaw, absf(yaw + 60.0) < 3.0 or absf(yaw - 60.0) < 3.0)
	var followed: Vector3 = main.screen.global_position
	f.pose.set_follow(false)
	_look(0.0, 0.0)
	await _sleep(0.6)
	_check("pinned: it stays where it followed to", main.screen.global_position.is_equal_approx(followed)
			and is_equal_approx(main.screen_yaw, f.pose.yaw))
	main.screen_yaw = 0.0
	main.set_screen(main.screen_width, main.screen_distance, main.screen_height_offset)

	# #55 size in degrees, presets.
	f.angle.set_angle(40.0)
	_check("set 40 deg: width matches (%.2f m at %.1f m)" % [main.screen_width, main.screen_distance],
			absf(f.angle.angle() - 40.0) < 0.05)
	f.angle.apply_preset("large_format")
	_check("large format: 70 deg at 14 m", absf(f.angle.angle() - 70.0) < 0.05 and is_equal_approx(main.screen_distance, 14.0)
			and f.angle.matching_preset() == "large_format")
	f.angle.apply_preset("in_bed")
	_check("in bed: 42 deg at 2.4 m, lying down on", f.angle.matching_preset() == "in_bed" and f.pose.lying)
	f.angle.apply_preset("living_room")
	_check("living room: lying down off", f.angle.matching_preset() == "living_room" and not f.pose.lying)

	# #19 seat choice in the cinema: the back row sees the screen further and lower; back to the own spot.
	main.set_environment("cinema")
	await _frames(2)
	var seats: Array = f.seat.seats()
	_check("cinema lists its seats (%d)" % seats.size(), seats.size() > 100)
	var d0: float = main.screen_distance
	var back := -1
	for i in seats.size():
		var s: Vector3 = seats[i]
		if s.z > 3.0 and absf(s.x) < 0.5:
			back = i
	f.seat.choose_seat(back)
	await _frames(2)
	var s_back: Vector3 = seats[back]
	_check("back row: room moved, screen further (%.1f -> %.1f m) and lower relative to the eyes" % [d0, main.screen_distance],
			main.env.position.is_equal_approx(-s_back) and main.screen_distance > d0 + 3.0)
	var anchor_world: Vector3 = main.env.global_transform * main.env.get_screen_anchor().origin
	_check("the screen is at the room's anchor (%s vs %s)" % [main.screen.global_position, anchor_world],
			Vector2(main.screen.global_position.x, main.screen.global_position.z).distance_to(
					Vector2(anchor_world.x, anchor_world.z)) < 0.05)
	var side := -1
	for i in seats.size():
		var s: Vector3 = seats[i]
		# Row 0 (its floor at 0; the rows curve, so its ends are nearer the screen), well to the right.
		if is_zero_approx(s.y) and s.x > 5.0:
			side = i
	f.seat.choose_seat(side)
	_check("a side seat turns the screen toward the middle (yaw %.0f deg)" % rad_to_deg(main.screen_yaw), main.screen_yaw < -0.2)
	# The screen stays square to the room, as a real one does: it does not turn to face the side seat.
	var room_facing: Vector3 = main.env.global_basis * main.env.get_screen_anchor().basis.z
	var facing: Vector3 = (main.screen as Node3D).global_basis.z
	_check("a side seat: the screen stays square to the room (%.1f deg off)" % rad_to_deg(facing.angle_to(room_facing)),
			facing.angle_to(room_facing) < 0.01)
	var pointed: Vector3 = main.env.global_transform * Vector3(seats[back])
	_check("pointing at a seat picks it", f.seat.choose_seat_at(pointed + Vector3(0.15, 0.5, 0.0)) and f.seat.seat == back)
	_check("pointing at nothing near a seat: no change", not f.seat.choose_seat_at(Vector3(0, 30, 0)))
	f.seat.choose_seat(-1)
	_check("own spot again", main.env.position == Vector3.ZERO and absf(main.screen_distance - d0) < 0.01
			and is_zero_approx(main.screen_yaw))
	main.set_environment("home_theatre")
	await _frames(2)
	_check("home theatre: three places on the sofa", f.seat.seats().size() == 3)
	main.set_environment("void")
	_check("void: no seats", f.seat.seats().is_empty())
	print("test_comfort: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _sleep(seconds: float) -> void:
	await create_timer(seconds).timeout


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL " + what)
	else:
		print("PASS " + what)
