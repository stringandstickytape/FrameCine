extends "res://tests/env_builder_harness.gd"

## The nave builder (scripts/env/systems/nave.gd; docs/environments.md, "The builders"): a test room of a nave (the
## light, the nave) passes the checks and the builder's conventions; the pews are drawn one a run of places, the places
## a pew's width apart, the aisles' gaps between pews; the rose window glows in the end wall over the screen and its
## glow is live; the candles flicker; a flat-ceilinged nave without aisles passes too.
## godot --headless --xr-mode off --path app --script res://tests/test_env_nave.gd


func run_tests() -> void:
	test_name = "test_env_nave"
	var doc := room_doc("Nave test", [{"system": "nave"}], screen_of("nave"))
	var room := await check_room("nave", doc, "nave")
	var nave: Node = room.host.system("nave")
	var slots: Array = nave.seat_slots()
	check("pews: one slot a place, 9 a pew, 11 pews (%d)" % slots.size(), slots.size() == 99
			and slots.all(func(s: Dictionary) -> bool: return s["style"] == "pew"))
	check("the pews are static meshes, baked", room.get_node_or_null("Pews") != null
			and (room.get_node("Pews") as MeshInstance3D).gi_mode == GeometryInstance3D.GI_MODE_STATIC)
	var rose := room.get_node_or_null("Rose") as MeshInstance3D
	var screen: Dictionary = nave.screen()
	check("the rose window over the screen", rose != null and rose.get_aabb().position.y
			> float(screen["center"][1]) + float(screen["size"][1]) * 0.5)
	room.host.auto = false
	nave.set_param("rose_glow", 1.2)
	var m: ShaderMaterial = rose.mesh.surface_get_material(0)
	check("the rose window's glow is live", is_equal_approx(float(m.get_shader_parameter("energy")), 1.2))
	var values: Array[float] = []
	for i in 60:
		room.host.step(1.0 / 30.0)
		values.append(nave.flicker_factor())
	check("the candles flicker (%.3f..%.3f)" % [values.min(), values.max()], values.max() - values.min() > 0.02)
	await done(room)
	var plain := {"aisle_width": 0.0, "vault": "flat", "rows_front": 8, "rows_back": 2, "places_per_pew": 7,
			"candles": 0, "rose_window": false, "wall_height": 8.0}
	doc = room_doc("Nave plain", [{"system": "nave", "params": plain}], screen_of("nave", plain))
	room = await check_room("nave plain", doc, "nave")
	await done(room)
