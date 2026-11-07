extends "res://tests/room_doc_harness.gd"

## The Screening room 1962 (app/environments/screening_room_1962.env.json; docs/environments.md, "Room: Screening
## room 1962"): the shipped document passes the checks, and is that room: the walnut room with two rows of club
## chairs, the pool glowing through the picture window from the viewer's seat, and the ritual: the painting comes down
## over the screen before the film, rises as the film starts (never faster than the motion system's limit) while the
## wall lamps go down to the room's setting, rises by itself on a film resumed later, and stays up with the Pre-show
## off. Rendered (with a renderer): user://room_render/screening_room_1962_*.png.
## godot --headless --xr-mode off --path app --script res://tests/test_room_screening_room_1962.gd

const PATH := "res://environments/screening_room_1962.env.json"
## The motion system's speed limit (docs/environments.md, "The motion system").
const MAX_SPEED := 0.5


func run_tests() -> void:
	test_name = "test_room_screening_room_1962"
	var room := await check_shipped("screening_room_1962", PATH, "room")
	var b: Node = room.host.system("room")
	check("walnut: the painting, the fireplace, the brass lamps, the window", room.get_node_or_null("Painting") != null
			and room.get_node_or_null("Fireplace") != null and room.get_node_or_null("Lamps") != null
			and room.get_node_or_null("Window") != null)
	check("no glow behind the window: the vista shows there", room.get_node_or_null("Outside") == null)
	var seats: Array[Transform3D] = room.room_seat_transforms()
	check("six club chairs (%d)" % seats.size(), seats.size() == 6
			and (room.host.system("seats").drawn() as Array).all(func(d: Dictionary) -> bool:
				return d["model"] == "club_chair"))
	await check_seat_pick("screening_room_1962", room, 5, true)
	check("a night sky and the vista", room.host.system("sky") != null and room.host.system("vista") != null)
	# The pool shows through the window from the viewer's seat.
	var pool: Array = room.host.system("vista").get("_pool")
	var win: Dictionary = (b.slots()["window"] as Array)[0]
	check("a pool in the vista", not pool.is_empty())
	if not pool.is_empty():
		var eye := Vector3(0, EnvChecks.EYE_HEIGHT, 0)
		var wt: Transform3D = win["transform"]
		var n := wt.basis.z
		var c: Vector3 = pool[0]
		var t := (wt.origin - eye).dot(n) / (c - eye).dot(n)
		var hit := wt.affine_inverse() * (eye + (c - eye) * t)
		var size: Array = win["size"]
		check("the pool through the window from the seat (%s in %s)" % [hit, size], t > 0.0 and t < 1.0
				and absf(hit.x) < float(size[0]) * 0.5 and absf(hit.y) < float(size[1]) * 0.5)
	await _ritual(room, b)
	if rendering():
		await _render(room)
	await done(room)


func _ritual(room: Node3D, b: Node) -> void:
	var host: Node = room.host
	host.auto = false
	var painting := room.get_node("Painting") as Node3D
	check("the painting is in front of the screen on purpose (env_in_front)", painting.is_in_group("env_in_front"))
	host.snapshot_override = {"open": false}
	steps(host, 9.0)
	check("pre-show: the painting is down over the screen (%.2f)" % b.params["painting_open"],
			float(b.params["painting_open"]) < 0.01 and painting.position.y < 0.01)
	check("pre-show: the wall lamps up (%.2f)" % host.param("light.house_lamps"),
			is_equal_approx(float(host.param("light.house_lamps")), 1.0))
	# The film starts from its start: the ritual.
	host.snapshot_override = {"open": true, "playing": true, "position": 0.5, "duration": 7200.0}
	var fastest := 0.0
	var y := painting.position.y
	for i in 30 * 12:
		host.step(1.0 / 30.0)
		fastest = maxf(fastest, absf(painting.position.y - y) * 30.0)
		y = painting.position.y
	check("starting: the ritual fired", host.timeline.fired.any(func(f: Array) -> bool: return f[0] == "ritual"))
	check("the painting has risen (%.2f, %.2f m up)" % [b.params["painting_open"], y],
			float(b.params["painting_open"]) > 0.99 and y > 1.5)
	check("never faster than the motion limit (%.2f m/s)" % fastest, fastest > 0.05 and fastest <= MAX_SPEED)
	check("the wall lamps at the room's setting (%.2f)" % host.param("light.house_lamps"),
			is_equal_approx(float(host.param("light.house_lamps")), 0.15))
	host.set_setting("house_level", 0.5)
	steps(host, 1.0)
	check("the lamps follow the setting in the film (%.2f)" % host.param("light.house_lamps"),
			absf(float(host.param("light.house_lamps")) - 0.5) < 0.01)
	host.set_setting("house_level", 0.15)
	steps(host, 1.0)
	# The end: the lamps come up, the painting comes down again.
	host.snapshot_override = {"open": true, "playing": false, "position": 7200.0, "duration": 7200.0, "ended": true}
	steps(host, 8.0)
	check("ended: the painting down, the lamps up (%.2f, %.2f)" % [b.params["painting_open"],
			host.param("light.house_lamps")], float(b.params["painting_open"]) < 0.01
			and is_equal_approx(float(host.param("light.house_lamps")), 1.0))
	# A film resumed later (not from its start): the painting rises by itself.
	host.snapshot_override = {"open": true, "playing": true, "position": 1800.0, "duration": 7200.0}
	steps(host, 5.0)
	check("resumed: %s, the painting up (%.2f)" % [host.timeline.state, b.params["painting_open"]],
			host.timeline.state == "playing" and float(b.params["painting_open"]) > 0.99)
	# Pre-show off: the painting stays up before the film.
	host.set_setting("ritual", false)
	host.snapshot_override = {"open": false}
	steps(host, 8.0)
	check("Pre-show off: the painting stays up (%.2f)" % b.params["painting_open"],
			float(b.params["painting_open"]) > 0.99)
	host.snapshot_override = {"open": true, "playing": true, "position": 0.5, "duration": 7200.0}
	steps(host, 4.0)
	check("Pre-show off: no ritual, the lamps down all the same (%.2f)" % host.param("light.house_lamps"),
			host.timeline.fired.any(func(f: Array) -> bool: return f[0] == "dim")
			and absf(float(host.param("light.house_lamps")) - 0.15) < 0.01)
	host.set_setting("ritual", true)


## From the viewer's seat: the painting down before the film, the screen showing, and the window with the pool.
func _render(room: Node3D) -> void:
	var host: Node = room.host
	var vp := render_view(room)
	var eye := Vector3(0, EnvChecks.EYE_HEIGHT, 0)
	host.snapshot_override = {"open": false}
	steps(host, 9.0)
	await shot(vp, eye, screen_point(room), "screening_room_1962_preshow")
	host.snapshot_override = {"open": true, "playing": true, "position": 600.0, "duration": 7200.0}
	steps(host, 6.0)
	await shot(vp, eye, screen_point(room), "screening_room_1962_seat")
	await shot(vp, eye, Vector3(-3.2, 1.0, -2.2), "screening_room_1962_window")
	await shot(vp, Vector3(1.0, 1.2, 1.7), Vector3(-1.0, 1.4, -5.0), "screening_room_1962_back_row")
	host.snapshot_override = null
	await end_render(vp, room)
