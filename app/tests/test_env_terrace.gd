extends "res://tests/env_builder_harness.gd"

## The terrace builder (scripts/env/systems/terrace.gd; docs/environments.md, "The builders"): three test rooms, one a
## style. A rooftop terrace (the light, the terrace: a low parapet, the screen painted on the next building's wall,
## strings of bulbs, chairs in rows); a drive-in's lot (STYLES.lot: humps and speaker posts, the screen on a frame, no
## seats of its own); a lunar amphitheatre (STYLES.amphitheatre: stone tiers on arcs round the screen rising behind the
## viewer, rocks on the plain). Each passes the checks and the builder's conventions.
## godot --headless --xr-mode off --path app --script res://tests/test_env_terrace.gd

const Terrace := preload("res://scripts/env/systems/terrace.gd")


func run_tests() -> void:
	test_name = "test_env_terrace"
	var doc := room_doc("Rooftop test", [{"system": "terrace", "id": "roof"}], screen_of("terrace"))
	var room := await check_room("terrace rooftop", doc, "roof")
	var roof: Node = room.host.system("roof")
	check("a parapet, a painted wall, bulbs", room.get_node_or_null("Parapet") != null
			and room.get_node_or_null("ScreenWall") != null and room.get_node_or_null("Bulbs") != null)
	check("eight rows of nine chairs", roof.seat_slots().size() == 72)
	check("the painted panel behind the picture", room.get_node_or_null("Painted") != null)
	await done(room)

	var lot: Dictionary = Terrace.STYLES["lot"]
	doc = room_doc("Lot test", [{"system": "terrace", "id": "lot", "params": lot}], screen_of("terrace", lot))
	room = await check_room("terrace lot", doc, "lot")
	var l: Node = room.host.system("lot")
	check("the lot: no seats of its own (a vehicle's bench is the seat)", l.seat_slots().is_empty())
	check("the lot: humps, posts, a screen on a frame", room.get_node_or_null("Humps") != null
			and room.get_node_or_null("Posts") != null and room.get_node_or_null("ScreenFrame") != null)
	var sc: Dictionary = l.screen()
	check("the lot's screen is big and high (%s)" % [sc], float(sc["size"][0]) >= 20.0
			and float(sc["center"][1]) > 4.0)
	await done(room)

	var amph: Dictionary = Terrace.STYLES["amphitheatre"]
	doc = room_doc("Amphitheatre test", [{"system": "terrace", "id": "amph", "params": amph}],
			screen_of("terrace", amph))
	room = await check_room("terrace amphitheatre", doc, "amph")
	var a: Node = room.host.system("amph")
	var slots: Array = a.seat_slots()
	var rising := true
	var facing := true
	var foot := Vector3(0, 0, float(a.screen()["center"][2]))
	for s: Dictionary in slots:
		var xf: Transform3D = s["transform"]
		var row := int(s["row"])
		if not is_equal_approx(xf.origin.y, -float(a.params["tier_rise"]) * row):
			rising = false
		var to := foot - xf.origin
		to.y = 0.0
		if (-xf.basis.z).dot(to.normalized()) < 0.999:
			facing = false
		if str(s["style"]) != "tier":
			facing = false
	check("the tiers rise behind the viewer (%d seats)" % slots.size(), rising and slots.size() > 50)
	check("every tier seat faces the screen", facing)
	check("tiers and rocks", room.get_node_or_null("Tiers") != null)
	# The tiers face up: every upward-facing tread's normal is up (none turned under).
	var tiers := room.get_node("Tiers") as MeshInstance3D
	var arrays := tiers.mesh.surface_get_arrays(0)
	var ns: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var down := 0
	for n in ns:
		if n.y < -0.9:
			down += 1
	check("no tread faces down (%d)" % down, down == 0)
	await done(room)
