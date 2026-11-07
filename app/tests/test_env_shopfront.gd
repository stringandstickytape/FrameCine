extends "res://tests/env_builder_harness.gd"

## The shopfront builder (scripts/env/systems/shopfront.gd; docs/environments.md, "The builders"): a test room of a
## 1906 shopfront picture house (the light, the hall, a tin booth from the kit) passes the checks and the builder's
## conventions; the pressed tin is the procedural pattern's maps on the library metal; the gas lamps flicker slowly and
## hold steady with the room's Flickering lights off; a wider hall with more rows and the plain tin pass too.
## godot --headless --xr-mode off --path app --script res://tests/test_env_shopfront.gd

const Procedural := preload("res://scripts/env/systems/kit/procedural.gd")


func run_tests() -> void:
	test_name = "test_env_shopfront"
	var doc := room_doc("Shopfront test", [{"system": "shopfront", "id": "hall"}], screen_of("shopfront"))
	var room := await check_room("shopfront", doc, "hall")
	var hall: Node = room.host.system("hall")
	var tin := room.get_node_or_null("Tin") as MeshInstance3D
	var m: ShaderMaterial = tin.mesh.surface_get_material(tin.mesh.get_surface_count() - 1) if tin != null else null
	check("pressed tin: the pattern's normal map on the ceiling", m != null
			and m.get_shader_parameter("normal_map") == Procedural.maps("pressed_tin")["normal"])
	check("the shop window is glass the sight line looks through", room.get_node_or_null("Window") != null
			and room.get_node("Window").is_in_group("env_see_through"))
	check("seven chairs a row, eleven rows", hall.seat_slots().size() == 77)
	# The gas lamps waver, slowly, and hold steady with Flickering lights off.
	room.host.auto = false
	var values: Array[float] = []
	for i in 90:
		room.host.step(1.0 / 30.0)
		values.append(hall.flicker_factor())
	var lo: float = values.min()
	var hi: float = values.max()
	check("the gas lamps flicker (%.3f..%.3f)" % [lo, hi], hi - lo > 0.02 and hi - lo < 0.4)
	var fastest := 0.0
	for i in range(1, values.size()):
		fastest = maxf(fastest, absf(values[i] - values[i - 1]) * 30.0)
	check("slowly: under 2 a second (%.2f)" % fastest, fastest < 2.0)
	room.host.set_setting("flicker", false)
	room.host.step(1.0 / 30.0)
	var a: float = hall.flicker_factor()
	room.host.step(0.5)
	check("Flickering lights off: steady (%.3f, %.3f)" % [a, hall.flicker_factor()],
			is_equal_approx(a, 1.0) and is_equal_approx(hall.flicker_factor(), 1.0))
	await done(room)
	var wide := {"width": 8.0, "rows_front": 9, "rows_back": 4, "chairs_per_row": 11, "tin_pattern": "plain",
			"seat_model": "director", "screen_size": [4.8, 2.7], "front_z": 8.0}
	doc = room_doc("Shopfront wide", [{"system": "shopfront", "id": "hall", "params": wide}],
			screen_of("shopfront", wide))
	room = await check_room("shopfront wide", doc, "hall")
	await done(room)
