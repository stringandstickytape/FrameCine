extends "res://tests/env_builder_harness.gd"

## The domestic builder (scripts/env/systems/domestic.gd; docs/environments.md, "The builders"): a test room for each
## style passes the checks and the builder's conventions. The plain sitting room (a pull-down screen, a radiator under
## the window); the 1962 screening room (walnut, club chairs, the painting that rises into the ceiling: live, and over
## the screen when down; the fire flickers slowly and holds steady with Flickering lights off); the 1993 bedroom (the
## pillow fort round the viewer's cushion, fairy lights, the telly on a chest; with opening_screen the telly fills the
## fort's opening); the ice room (the ice-block pattern on the walls, a vault, hides, candles, an open doorway).
## godot --headless --xr-mode off --path app --script res://tests/test_env_domestic.gd

const Procedural := preload("res://scripts/env/systems/kit/procedural.gd")
const Domestic := preload("res://scripts/env/systems/domestic.gd")


func run_tests() -> void:
	test_name = "test_env_domestic"
	var doc := room_doc("Sitting room test", [{"system": "domestic", "id": "room"}], screen_of("domestic"))
	var room := await check_room("domestic plain", doc, "room")
	check("plain: a window of glass, a radiator, a pull-down screen", room.get_node_or_null("Window") != null
			and room.get_node("Window").is_in_group("env_see_through") and room.get_node_or_null("Radiator") != null
			and room.get_node_or_null("Screen") != null)
	var slots: Dictionary = room.host.system("room").slots()
	check("plain: window and vista slots", slots.has("window") and slots.has("vista"))
	await done(room)

	var walnut := {"style": "walnut_1962"}
	doc = room_doc("Screening room test", [{"system": "domestic", "id": "room", "params": walnut}],
			screen_of("domestic", walnut))
	room = await check_room("domestic walnut_1962", doc, "room")
	var r: Node = room.host.system("room")
	var painting := room.get_node_or_null("Painting") as MeshInstance3D
	check("walnut: the painting, risen", painting != null and painting.position.y > 1.5)
	r.set_param("painting_open", 0.0)
	var sc: Dictionary = r.screen()
	var aabb := painting.global_transform * painting.get_aabb() if painting != null else AABB()
	check("walnut: the painting down covers the screen (%s)" % aabb, aabb.has_point(Vector3(0.0,
			float(sc["center"][1]), aabb.get_center().z)) and aabb.get_center().z > float(sc["center"][2]))
	r.set_param("painting_open", 1.0)
	check("walnut: a fireplace, its fire, brass lamps", room.get_node_or_null("Fireplace") != null
			and room.get_node_or_null("Fire") != null and room.get_node_or_null("Lamps") != null)
	check("walnut: club chairs, two rows of three", r.seat_slots().size() == 6
			and str(r.seat_slots()[0]["style"]) == "club")
	check("walnut: a mantel slot", (r.slots() as Dictionary).has("mantel"))
	room.host.auto = false
	var values: Array[float] = []
	for i in 90:
		room.host.step(1.0 / 30.0)
		values.append(r.flicker_factor())
	var lo: float = values.min()
	var hi: float = values.max()
	check("walnut: the fire flickers (%.3f..%.3f)" % [lo, hi], hi - lo > 0.02 and hi - lo < 0.4)
	var fastest := 0.0
	for i in range(1, values.size()):
		fastest = maxf(fastest, absf(values[i] - values[i - 1]) * 30.0)
	check("walnut: slowly (%.2f a second)" % fastest, fastest < 2.0)
	room.host.set_setting("flicker", false)
	room.host.step(0.5)
	check("walnut: Flickering lights off, steady (%.3f)" % r.flicker_factor(), is_equal_approx(r.flicker_factor(), 1.0))
	await done(room)

	var bedroom := {"style": "bedroom_1993"}
	doc = room_doc("Bedroom test", [{"system": "domestic", "id": "room", "params": bedroom}],
			screen_of("domestic", bedroom))
	room = await check_room("domestic bedroom_1993", doc, "room")
	r = room.host.system("room")
	check("bedroom: the fort, its sheet, fairy lights, the telly, the bed", room.get_node_or_null("Fort") != null
			and room.get_node_or_null("FortSheet") != null and room.get_node_or_null("FairyLights") != null
			and room.get_node_or_null("Telly") != null and room.get_node_or_null("Bed") != null)
	check("bedroom: three cushions in the fort", r.seat_slots().size() == 3
			and str(r.seat_slots()[0]["style"]) == "cushion")
	var small: Dictionary = r.screen()
	await done(room)
	var filled := {"style": "bedroom_1993", "opening_screen": true}
	doc = room_doc("Bedroom filled", [{"system": "domestic", "id": "room", "params": filled}],
			screen_of("domestic", filled))
	room = await check_room("domestic bedroom opening_screen", doc, "room")
	var big: Dictionary = room.host.system("room").screen()
	check("the telly fills the opening: bigger and nearer (%s, %s)" % [small["size"], big["size"]],
			float(big["size"][0]) > float(small["size"][0]) * 1.8 and float(big["center"][2]) > float(small["center"][2])
			and float(big["center"][2]) < Domestic.FORT_FRONT)
	await done(room)

	var ice := {"style": "ice"}
	doc = room_doc("Ice test", [{"system": "domestic", "id": "room", "params": ice}], screen_of("domestic", ice))
	room = await check_room("domestic ice", doc, "room")
	var walls := room.get_node_or_null("Walls") as MeshInstance3D
	var m: ShaderMaterial = walls.mesh.surface_get_material(0) if walls != null else null
	check("ice: the ice-block pattern on the walls", m != null
			and m.get_shader_parameter("normal_map") == Procedural.maps("ice_blocks")["normal"])
	check("ice: candles, an open doorway, hides", room.get_node_or_null("Candles") != null
			and room.get_node_or_null("Doorway") != null and room.get_node_or_null("Cushions") != null)
	check("ice: no window", room.get_node_or_null("Window") == null)
	await done(room)

	# Auto: a parameter the document gives wins over the style's.
	var p := Domestic.resolved({"style": "ice", "half_width": 4.0, "rows_front": 0, "walls": {}, "screen": "auto"})
	check("auto: given values kept, the rest the style's", is_equal_approx(float(p["half_width"]), 4.0)
			and int(p["rows_front"]) == 0 and str(p["screen"]) == "wall" and str(p["walls"]["library"]) == "white_marble")
