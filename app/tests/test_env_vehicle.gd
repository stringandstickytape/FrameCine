extends "res://tests/env_builder_harness.gd"

## The vehicle builder (scripts/env/systems/vehicle.gd; docs/environments.md, "The builders"): a test room of a
## drive-in (the light, the terrace builder's lot, the convertible on it) passes the checks and the builder's
## conventions. The bench's places are three a row, the viewer's in the middle at the origin, the rear bench's behind;
## the windscreen is see-through glass with its top under the eyes; the steering wheel is in front of the left place
## with its top under 1.05 m; the dials' glow and the headlamps are live. A car without its rear bench and with the
## ground right under it (no wheels) passes too.
## godot --headless --xr-mode off --path app --script res://tests/test_env_vehicle.gd

const Terrace := preload("res://scripts/env/systems/terrace.gd")
const Vehicle := preload("res://scripts/env/systems/vehicle.gd")
const EYE := 1.2


func run_tests() -> void:
	test_name = "test_env_vehicle"
	var lot: Dictionary = Terrace.STYLES["lot"]
	var systems := [{"system": "terrace", "id": "lot", "params": lot}, {"system": "vehicle", "id": "car"}]
	var doc := room_doc("Drive-in test", systems, screen_of("terrace", lot))
	var room := await check_room("vehicle on the lot", doc, "car")
	var car: Node = room.host.system("car")
	var slots: Array = car.seat_slots()
	check("six places on two benches (%d)" % slots.size(), slots.size() == 6)
	check("the front bench: left, middle (the origin), right", (slots[0]["transform"] as Transform3D).origin.x < -0.3
			and (slots[1]["transform"] as Transform3D).origin.length() < 0.01
			and (slots[2]["transform"] as Transform3D).origin.x > 0.3 and str(slots[1]["style"]) == "bench")
	var glass := room.get_node_or_null("Windscreen") as MeshInstance3D
	check("the windscreen: see-through glass", glass != null and glass.is_in_group("env_see_through"))
	var top := -INF
	if glass != null:
		top = glass.get_aabb().end.y
	check("its top under the eyes (%.2f)" % top, top < EYE - 0.03)
	var wheel := room.get_node_or_null("Wheel") as MeshInstance3D
	var wb := wheel.get_aabb() if wheel != null else AABB()
	check("the steering wheel in front of the left place, its top under 1.05 m (%s)" % wb, wheel != null
			and wb.end.y < 1.05 and wb.get_center().x < -0.3 and wb.end.z < 0.0)
	check("wheels on the ground (the lot at -0.5)", car.wheels_drawn)
	car.set_param("dial_glow", 1.2)
	var dials := room.get_node("Dials") as MeshInstance3D
	check("the dials' glow is live", is_equal_approx(float(dials.mesh.surface_get_material(0)
			.get_shader_parameter("energy")), 1.2))
	car.set_param("headlamps", 1.0)
	var lamps := room.get_node("Lamps") as MeshInstance3D
	check("the headlamps light", float(lamps.mesh.surface_get_material(0).get_shader_parameter("energy")) > 1.0)
	await done(room)

	var plain := {"rear_seat": false, "ground_y": -0.28, "top": "none", "fins": 0.0}
	systems = [{"system": "terrace", "id": "lot", "params": lot}, {"system": "vehicle", "id": "car", "params": plain}]
	doc = room_doc("Car plain", systems, screen_of("terrace", lot))
	room = await check_room("vehicle plain", doc, "car")
	check("no rear bench: three places", room.host.system("car").seat_slots().size() == 3)
	check("no wheels without the ground under the body", not room.host.system("car").wheels_drawn)
	await done(room)
