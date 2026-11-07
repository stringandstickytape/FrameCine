extends "res://tests/room_doc_harness.gd"

## The Pillow Fort 1993 (app/environments/pillow_fort_1993.env.json; docs/environments.md, "Room: Pillow Fort 1993"):
## the shipped document passes the checks, and is that room: a child's bedroom with a pillow fort of cushions and a
## bedsheet round three floor cushions, fairy lights along the fort's hem that flicker slowly (steady with Flickering
## lights off), the telly filling the fort's opening, its picture a 1993 tube playing a tape (the presentation's
## Nightowl preset), the telly's speaker only when the setting asks; rain on the window pane (at the window, facing
## in) and outside it, by the Rain setting; the video recorder under the telly flashing 12:00; the sound (a small
## room, a ticking radiator, rain on the glass with the rain, the tape going in as the film starts). Rendered (with a renderer): user://room_render/pillow_fort_1993_*.png.
## godot --headless --xr-mode off --path app --script res://tests/test_room_pillow_fort_1993.gd

const PATH := "res://environments/pillow_fort_1993.env.json"
const Domestic := preload("res://scripts/env/systems/domestic.gd")


func run_tests() -> void:
	test_name = "test_room_pillow_fort_1993"
	var room := await check_shipped("pillow_fort_1993", PATH, "room")
	var host: Node = room.host
	var b: Node = host.system("room")
	check("the bedroom: the fort, its sheet, fairy lights, the telly, the bed", room.get_node_or_null("Fort") != null
			and room.get_node_or_null("FortSheet") != null and room.get_node_or_null("FairyLights") != null
			and room.get_node_or_null("Telly") != null and room.get_node_or_null("Bed") != null)
	check("the fort's hem in front of the picture on purpose (env_in_front)",
			room.get_node("FortSheet").is_in_group("env_in_front"))
	var sc: Dictionary = room.get("doc")["screen"]
	check("the telly fills the fort's opening: the picture just beyond it, 4:3, at least 1.2 m wide (%s)" % [sc],
			float(sc["center"][2]) < Domestic.FORT_FRONT and float(sc["center"][2]) > Domestic.FORT_FRONT - 0.6
			and absf(float(sc["size"][0]) / float(sc["size"][1]) - 4.0 / 3.0) < 0.01 and float(sc["size"][0]) > 1.2)
	var seats: Array[Transform3D] = room.room_seat_transforms()
	check("three floor cushions in the fort (%d)" % seats.size(), seats.size() == 3
			and (host.system("seats").drawn() as Array).all(func(d: Dictionary) -> bool: return d["model"] == "cushion")
			and seats.all(func(t: Transform3D) -> bool: return absf(t.origin.x) < Domestic.FORT_HALF))
	await check_seat_pick("pillow_fort_1993", room, 0, false)
	# The telly: a 1993 tube playing a tape; its own speaker only when asked.
	var p: Node = host.system("presentation")
	check("a CRT with an aperture grille playing a tape (%s, %s, %s)" % [p.value("display"), p.value("mask"),
			p.value("source")], p.value("display") == "crt" and p.value("mask") == "grille" and p.value("source") == "tape")
	check("the film's own sound by default (speaker %s)" % p.value("speaker"), p.value("speaker") == "none")
	host.set_setting("telly_sound", true)
	check("the telly's speaker with the setting on (%s)" % p.value("speaker"), p.value("speaker") == "telly")
	host.set_setting("telly_sound", false)
	check("and off again (%s)" % p.value("speaker"), p.value("speaker") == "none")
	# The rain: the pane on the window, facing in; rain outside it; the setting.
	var w: Node = host.system("weather")
	var win: Dictionary = (b.slots()["window"] as Array)[0]
	var wt: Transform3D = win["transform"]
	var pc := Vector3(w.params["pane_center"][0], w.params["pane_center"][1], w.params["pane_center"][2])
	var facing := Basis(Vector3.UP, deg_to_rad(float(w.params["pane_yaw"]))) * Vector3.BACK
	check("the pane on the window (%s at %s), facing into the room" % [pc, wt.origin], pc.distance_to(wt.origin) < 0.1
			and facing.dot(wt.basis.z) > 0.99)
	var area: Dictionary = (w.params["areas"] as Array)[0]
	check("the rain outside falls beyond the window", float(area["max"][0]) < wt.origin.x
			and float(area["min"][2]) < wt.origin.z and float(area["max"][2]) > wt.origin.z)
	host.auto = false
	steps(host, 60.0)
	check("rain by default (%.2f)" % w.rain_amount(), w.rain_amount() > 0.8)
	host.set_setting("rain", "none")
	steps(host, 90.0)
	check("Rain: none dries up (%.2f, %s)" % [w.rain_amount(), w.params["mode"]], w.rain_amount() < 0.05
			and w.params["mode"] == "clear")
	check("and the rain on the glass goes quiet (%.2f)" % float(host.system("rain").params["level"]),
			float(host.system("rain").params["level"]) < 0.1)
	host.set_setting("rain", "drizzle")
	check("Rain: drizzle (%s)" % w.params["mode"], w.params["mode"] == "light")
	host.set_setting("rain", "rain")
	steps(host, 60.0)
	check("rain on the glass again (%.2f)" % float(host.system("rain").params["level"]),
			float(host.system("rain").params["level"]) > 0.8)
	# The fairy lights flicker slowly; Flickering lights off holds them.
	var values: Array[float] = []
	for i in 90:
		host.step(1.0 / 30.0)
		values.append(b.flicker_factor())
	var fastest := 0.0
	for i in range(1, values.size()):
		fastest = maxf(fastest, absf(values[i] - values[i - 1]) * 30.0)
	check("the fairy lights flicker, slowly (%.3f..%.3f, %.2f a second)" % [values.min(), values.max(), fastest],
			float(values.max()) - float(values.min()) > 0.01 and fastest < 2.0)
	host.set_setting("flicker", false)
	host.step(0.5)
	check("Flickering lights off: steady (%.3f)" % b.flicker_factor(), is_equal_approx(b.flicker_factor(), 1.0))
	host.set_setting("flicker", true)
	# The video recorder on the floor under the telly, its clock flashing 12:00.
	var vcr: Dictionary = host.system("kit").params["pieces"][0]
	var shelf: Transform3D = b.slots()["telly_shelf"][0]["transform"]
	var t: Dictionary = Domestic._telly(Domestic.resolved(b.params))
	check("the video recorder under the telly, in front of its chest (%s)" % shelf.origin, vcr["piece"] == "video_recorder"
			and vcr["slot"] == "telly_shelf" and shelf.origin.y < float(t["foot"]) and shelf.origin.z
			> float(sc["center"][2]) and shelf.origin.z < Domestic.FORT_FRONT + 0.1
			and (host.system("kit").problems() as Array).is_empty())
	await clock_flashes("pillow_fort_1993", room)
	# The sound: a small room, the radiator ticking, rain on the glass, the tape going in as the film starts.
	await sounds("pillow_fort_1993", room, {"radiator": "radiator", "rain": "rain_glass", "vcr": "vcr"})
	var takes := int(host.system("vcr").get("plays"))
	host.snapshot_override = {"open": false}
	steps(host, 1.0)
	host.snapshot_override = {"open": true, "playing": true, "position": 0.0, "duration": 5400.0}
	steps(host, 1.0)
	check("the tape goes in as the film starts (%d plays)" % int(host.system("vcr").get("plays")),
			int(host.system("vcr").get("plays")) > takes)
	host.set_setting("telly_fills", false)
	await process_frame
	var across: Transform3D = host.system("room").slots()["telly_shelf"][0]["transform"]
	check("the telly back across the room: its video recorder with it (%s)" % across.origin, across.origin.z < -2.5
			and room.get_node_or_null("PieceDisplay") != null and (host.system("kit").problems() as Array).is_empty())
	host.set_setting("telly_fills", true)
	await process_frame
	if rendering():
		await _render(room)
	await done(room)


func _render(room: Node3D) -> void:
	var vp := render_view(room)
	var eye := Vector3(0, EnvChecks.EYE_HEIGHT, 0)
	await shot(vp, eye, screen_point(room), "pillow_fort_1993_seat")
	await shot(vp, eye, Vector3(-2.6, 1.4, -1.6), "pillow_fort_1993_window")
	await shot(vp, Vector3(1.6, 1.6, 1.9), Vector3(-0.3, 0.7, -1.2), "pillow_fort_1993_room")
	await end_render(vp, room)
