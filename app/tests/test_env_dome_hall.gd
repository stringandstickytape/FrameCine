extends "res://tests/env_builder_harness.gd"

## The dome hall builder (scripts/env/systems/dome_hall.gd; docs/environments.md, "The builders"): a test room of a
## glass dome looking out to water (a bathysphere: the light, the hall) passes the checks and the builder's
## conventions; the panes are glass the sight line looks through, the seats are on arcs facing the screen, every seat
## inside the hall; the water's glow is live; a solid dome with a night outside, and a glass dome over no floor of its
## own and no seats (the crater's cover over a terrace), pass too.
## godot --headless --xr-mode off --path app --script res://tests/test_env_dome_hall.gd


func run_tests() -> void:
	test_name = "test_env_dome_hall"
	var doc := room_doc("Dome test", [{"system": "dome_hall", "id": "dome"}], screen_of("dome_hall"))
	var room := await check_room("dome_hall glass", doc, "dome")
	var dome: Node = room.host.system("dome")
	var panes := room.get_node_or_null("Panes")
	check("glass panes the sight line looks through", panes != null and panes.is_in_group("env_see_through"))
	var screen: Dictionary = dome.screen()
	var foot := Vector3(0, 0, float(screen["center"][2]))
	var facing := true
	var inside := true
	var c := Vector3(0, 0, float(dome.params["centre_z"]))
	for s: Dictionary in dome.seat_slots():
		var xf: Transform3D = s["transform"]
		var to := (foot - xf.origin)
		to.y = 0.0
		if (-xf.basis.z).dot(to.normalized()) < 0.999:
			facing = false
		if Vector2(xf.origin.x - c.x, xf.origin.z - c.z).length() > float(dome.params["radius"]):
			inside = false
	check("every seat faces the screen (%d seats)" % dome.seat_slots().size(), facing)
	check("every seat inside the hall", inside)
	var outside := room.get_node_or_null("Outside") as MeshInstance3D
	check("deep water outside", outside != null)
	dome.set_param("outside_glow", 1.5)
	check("the water's glow is live", is_equal_approx(float(outside.mesh.surface_get_material(0)
			.get_shader_parameter("energy")), 1.5))
	await done(room)
	var solid := {"dome": "solid", "outside": "night", "radius": 12.0, "centre_z": -4.0, "rows_back": 5,
			"arc_deg": 150.0, "seat_model": "club", "seat_pitch": 0.95}
	doc = room_doc("Dome solid", [{"system": "dome_hall", "id": "dome", "params": solid}], screen_of("dome_hall", solid))
	room = await check_room("dome_hall solid", doc, "dome")
	await done(room)
	var cover := {"has_floor": false, "seating": false, "outside": "none", "radius": 20.0, "drum_height": 0.0,
			"dome_height": 14.0, "centre_z": -6.0}
	doc = room_doc("Dome cover", [{"system": "dome_hall", "id": "dome", "params": cover}], screen_of("dome_hall", cover))
	room = await check_room("dome_hall cover", doc)
	check("the cover: no floor, no seats", room.get_node_or_null("Floor") == null
			and room.host.system("dome").seat_slots().is_empty())
	await done(room)
