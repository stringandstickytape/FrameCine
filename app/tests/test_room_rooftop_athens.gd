extends "res://tests/room_doc_harness.gd"

## The Athens rooftop summer cinema (app/environments/rooftop_athens.env.json; docs/environments.md, "Room: Athens
## rooftop"): the shipped document passes the checks, and is that room: a roof terrace with a low wall,
## director's chairs in rows, bougainvillea over the wall, the screen painted on the next building's wall; the
## floodlit acropolis on its hill beside the screen wall and over the low wall from the seat; a summer night's sky at
## latitude 38 that darkens over the first minutes of the film; plane lights; a cat that walks the wall top and never
## enters the sight line to the picture; the Floodlights setting.
## Rendered (with a renderer): user://room_render/rooftop_athens_*.png.
## godot --headless --xr-mode off --path app --script res://tests/test_room_rooftop_athens.gd

const PATH := "res://environments/rooftop_athens.env.json"
const Vista := preload("res://scripts/env/systems/vista.gd")


func run_tests() -> void:
	test_name = "test_room_rooftop_athens"
	var room := await check_shipped("rooftop_athens", PATH, "terrace")
	var host: Node = room.host
	var t: Node = host.system("terrace")
	check("a rooftop with its low wall and the painted screen wall", str(t.params["style"]) == "rooftop"
			and room.get_node_or_null("Parapet") != null and room.get_node_or_null("ScreenWall") != null
			and room.get_node_or_null("Painted") != null)
	var seats: Array[Transform3D] = room.room_seat_transforms()
	check("director's chairs, seven rows of nine (%d)" % seats.size(), seats.size() == 63
			and (host.system("seats").drawn() as Array).all(func(d: Dictionary) -> bool: return d["model"] == "director"))
	await check_seat_pick("rooftop_athens", room, 0, true)
	var kit: Node = host.system("kit")
	check("bougainvillea along the wall, every piece placed %s" % [kit.problems()], kit.problems().is_empty()
			and (kit.params["pieces"] as Array).all(func(p: Dictionary) -> bool: return p["piece"] == "bougainvillea"))
	var sky: Node = host.system("sky")
	check("a summer night's sky at latitude 38", is_equal_approx(float(sky.params["latitude"]), 38.0)
			and int(sky.params["day_of_year"]) > 150 and int(sky.params["day_of_year"]) < 240)
	# The acropolis: beside the screen wall (its edge as seen from the seat) and over the low wall.
	var vista: Node = host.system("vista")
	var acro: Dictionary = {}
	for it: Dictionary in vista.built:
		if it["shape"] == "acropolis":
			acro = it
	check("a floodlit acropolis in the vista", not acro.is_empty())
	if not acro.is_empty():
		var hw := float(t.params["half_width"]) + 2.0
		var wall_edge := rad_to_deg(atan2(hw, -float(t.params["front_z"])))
		var near_side := absf(float(acro["azimuth"])) - float(acro["spread"]) * 0.5
		check("the acropolis clear of the screen wall (%.1f from %.1f degrees)" % [near_side, wall_edge],
				near_side > wall_edge + 2.0)
		var d := float(acro["distance"])
		var top := float(acro["floor_y"]) + d * tan(deg_to_rad(3.0 * float(acro["size"])))
		var hill := rad_to_deg(atan2(top - EnvChecks.EYE_HEIGHT, d))
		var parapet := rad_to_deg(atan2(float(t.params["parapet_height"]) + 0.06 - EnvChecks.EYE_HEIGHT,
				float(t.params["half_width"])))
		check("the hill's top over the low wall from the seat (%.1f over %.1f degrees)" % [hill, parapet],
				hill > parapet + 2.0)
	host.set_setting("floodlights", 0.0)
	check("Floodlights off: the hill dark (%.2f)" % vista.params["floodlight"], float(vista.params["floodlight"]) < 0.01)
	host.set_setting("floodlights", 1.0)
	check("Floodlights on (%.2f)" % vista.params["floodlight"], float(vista.params["floodlight"]) > 0.99)
	check("plane lights", str(host.system("planes").params["creature"]) == "plane")
	# Dusk over the film's first minutes.
	host.auto = false
	host.snapshot_override = {"open": true, "playing": true, "position": 10.0, "duration": 7200.0}
	host.signals.fake("film.minutes", 0.2)
	steps(host, 10.0)
	var early := float(sky.params["dusk"])
	host.signals.fake("film.minutes", 25.0)
	steps(host, 15.0)
	host.signals.clear_fakes()
	check("dusk deepens over the film (%.2f, then %.2f)" % [early, sky.params["dusk"]], early < 0.8
			and float(sky.params["dusk"]) > 0.97)
	# The cat walks the wall top, out of the sight line from the viewer's seat.
	var cat: Node = host.system("cat")
	var path: Array[Vector3] = cat.path_points()
	check("the cat's way along the wall top (%d points)" % path.size(), path.size() >= 2
			and path.all(func(p: Vector3) -> bool: return absf(absf(p.x) - (float(t.params["half_width"]) + 0.15)) < 0.1))
	var seen := 0
	var spots := {}
	for i in 30 * 240:
		host.step(1.0 / 30.0)
		var at: Vector3 = (cat.creature.get("_pos") as Vector3)
		spots[snappedf(at.z, 1.0)] = true
		if cat.in_view(at + Vector3.UP * 0.15, 0.2):
			seen += 1
	check("the cat walked the wall (%d metres of it)" % spots.size(), spots.size() >= 5)
	check("never in the sight line in 4 minutes (%d frames)" % seen, seen == 0)
	host.snapshot_override = null
	if rendering():
		await _render(room)
	await done(room)


func _render(room: Node3D) -> void:
	var vp := render_view(room)
	var eye := Vector3(0, EnvChecks.EYE_HEIGHT, 0)
	var acro := Vector3(sin(deg_to_rad(52.0)), 0.0, -cos(deg_to_rad(52.0))) * 150.0 + Vector3(0, 6.0, 0)
	await shot(vp, eye, screen_point(room), "rooftop_athens_seat")
	await shot(vp, eye, acro, "rooftop_athens_acropolis")
	await shot(vp, eye, Vector3(-6.6, 1.2, -4.0), "rooftop_athens_wall")
	await shot(vp, eye, eye + Vector3(0, 1.0, -0.6), "rooftop_athens_sky")
	await end_render(vp, room)
