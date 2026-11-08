extends "res://tests/room_doc_harness.gd"

## The Athens rooftop summer cinema (app/environments/rooftop_athens.env.json; docs/environments.md, "Room: Athens
## rooftop"): the shipped document passes the checks (the budget, a clear sight line from every seat, comfort), and is
## that room: a tiled roof with its whitewashed parapet, director's chairs in rows, the screen painted on the next
## building's blind wall, the roof's things (the hut, the kiosk, the plants, the bulb strings) in their few shared
## meshes, the city all round in one draw, the floodlit temple on its hill beside the screen wall and over the parapet;
## a summer night's sky at latitude 38 that darkens over the first minutes; the city's windows going out through the
## film; the bulbs dimmed for the film and up again after, the church bell before it; plane lights; a cat that walks
## the wall top and never enters the sight line; the Floodlights setting. Its sound: cicadas and the city's murmur
## that fade as the film starts, a moped passing below now and then, the bell far off, the open air, the level measured.
## Under lavapipe it draws the room from its own seat, a side seat, up and back, in the pre-show and with a film playing
## (ROOF_BAKE=1 bakes it first; ROOF_RENDER_ONLY=1 skips the checks; ROOF_SHOTS=seat,back picks the views).
## godot --headless --xr-mode off --path app --script res://tests/test_room_rooftop_athens.gd

const RoomRender := preload("res://tests/room_render.gd")
const RoomBake := preload("res://scripts/env/room_bake.gd")
const RoomSound := preload("res://tests/room_sound_checks.gd")
const PATH := "res://environments/rooftop_athens.env.json"
const BAKE_ID := "rooftop_athens_render_test"
## The roof's meshes: each part's pieces share one material (a draw each).
const PARTS := ["Floor", "Parapet", "ScreenWall", "Painted", "Ironwork", "Woodwork", "PaintedWood", "Plaster", "Pots",
		"Plants", "Canvas", "Bulbs", "BoothGlow", "KioskGlow", "Posters", "BulbHalos", "City"]


func run_tests() -> void:
	test_name = "test_room_rooftop_athens"
	var r := EnvDoc.load_file(PATH)
	check("the document reads (%s)" % [r["errors"]], (r["errors"] as Array).is_empty())
	var doc: Dictionary = r["doc"]
	if OS.get_environment("ROOF_RENDER_ONLY") == "":
		await _checks()
	await _render(doc)


func _checks() -> void:
	var room := await check_shipped("rooftop_athens", PATH, "terrace")
	var host: Node = room.host
	var t: Node = host.system("terrace")
	# The budget, tighter than the checks' own: the room is drawn twice (once an eye) on the headset.
	var stats := EnvChecks.measure(room)
	print("  rooftop_athens: %s" % [stats])
	check("about 30 draws (%d)" % stats["draws"], int(stats["draws"]) <= 32)
	check("under 250k triangles (%d)" % stats["triangles"], int(stats["triangles"]) < 250000)
	check("no more than one live light (%d), under 1500 particles (%d)" % [stats["lights"], stats["particles"]],
			int(stats["lights"]) <= 1 and int(stats["particles"]) < 1500)
	check("a rooftop with the city round it", str(t.params["style"]) == "rooftop" and bool(t.params["city"]))
	var missing: Array = PARTS.filter(func(n: String) -> bool: return room.find_child(n, true, false) == null)
	check("the roof's parts and the city, each one mesh (missing %s)" % [missing], missing.is_empty())
	var halos := room.find_child("BulbHalos", true, false)
	check("the bulbs' halos left out of the sight line (they face the eye)", halos != null
			and halos.is_in_group(EnvChecks.ScreenFrame.SEE_THROUGH))
	var seats: Array[Transform3D] = room.room_seat_transforms()
	check("director's chairs, seven rows of nine (%d)" % seats.size(), seats.size() == 63
			and (host.system("seats").drawn() as Array).all(func(d: Dictionary) -> bool: return d["model"] == "director"))
	await check_seat_pick("rooftop_athens", room, 0, true)
	var sky: Node = host.system("sky")
	check("a summer night's sky at latitude 38", is_equal_approx(float(sky.params["latitude"]), 38.0)
			and int(sky.params["day_of_year"]) > 150 and int(sky.params["day_of_year"]) < 240)
	_hill(t)
	var city: ShaderMaterial = t.city_material()
	host.set_setting("floodlights", 0.0)
	check("Floodlights off: the hill dark (%.2f)" % city.get_shader_parameter("floodlight"),
			float(city.get_shader_parameter("floodlight")) < 0.01)
	host.set_setting("floodlights", 1.0)
	check("Floodlights on (%.2f)" % city.get_shader_parameter("floodlight"),
			float(city.get_shader_parameter("floodlight")) > 0.99)
	check("plane lights", str(host.system("planes").params["creature"]) == "plane")
	await _evening(room)
	await _cat(room)
	await _sound(room)
	host.snapshot_override = null
	await done(room)


## The temple's hill: beside the screen building (its far edge as seen from the seat) and over the parapet.
func _hill(t: Node) -> void:
	var edge := rad_to_deg(atan2(8.5, 12.05))
	check("the temple clear of the screen building (%.0f from %.1f degrees)" % [AthensCity.CITADEL_AZ, edge],
			AthensCity.CITADEL_AZ - 8.0 > edge + 2.0)
	var hill := rad_to_deg(atan2(AthensCity.CITADEL_TOP - EnvChecks.EYE_HEIGHT, AthensCity.CITADEL_D))
	var parapet := rad_to_deg(atan2(float(t.params["parapet_height"]) + 0.06 - EnvChecks.EYE_HEIGHT,
			float(t.params["half_width"])))
	check("the hill's top over the parapet from the seat (%.1f over %.1f degrees)" % [hill, parapet],
			hill > parapet + 2.0)


## The evening: dusk deepens over the film's first minutes; the city's windows go out through it; the bulbs dim as it
## starts and come up after, with the bell from the church in the pre-show.
func _evening(room: Node3D) -> void:
	var host: Node = room.host
	var sky: Node = host.system("sky")
	var t: Node = host.system("terrace")
	var light: Node = host.system("light")
	var halos: ShaderMaterial = (room.find_child("BulbHalos", true, false) as MeshInstance3D).mesh.surface_get_material(0)
	host.auto = false
	host.snapshot_override = {"open": false}
	steps(host, 6.0)
	var pre_house := float(light.params["house_lamps"])
	var pre_halo := float(halos.get_shader_parameter("energy"))
	host.snapshot_override = {"open": true, "playing": true, "position": 10.0, "duration": 7200.0}
	host.signals.fake("film.minutes", 0.2)
	steps(host, 10.0)
	var early := float(sky.params["dusk"])
	var film_house := float(light.params["house_lamps"])
	var film_halo := float(halos.get_shader_parameter("energy"))
	check("the bulbs dim for the film (%.2f to %.2f), their halos with them (%.2f to %.2f)" % [pre_house, film_house,
			pre_halo, film_halo], pre_house > 0.99 and film_house < 0.15 and film_halo < pre_halo * 0.2)
	check("the kiosk's light down too (accent %.2f)" % light.params["accent"], float(light.params["accent"]) < 0.35)
	var windows_early := float(t.params["windows"])
	host.signals.fake("film.minutes", 25.0)
	steps(host, 15.0)
	check("dusk deepens over the film (%.2f, then %.2f)" % [early, sky.params["dusk"]], early < 0.8
			and float(sky.params["dusk"]) > 0.97)
	host.signals.fake("film.minutes", 130.0)
	steps(host, 15.0)
	var windows_late := float(t.params["windows"])
	var city: ShaderMaterial = t.city_material()
	check("the city's windows go out through the film (%.2f, then %.2f; the shader's %.2f)" % [windows_early,
			windows_late, city.get_shader_parameter("windows")], windows_early > 0.95 and windows_late < 0.6
			and is_equal_approx(float(city.get_shader_parameter("windows")), windows_late))
	host.signals.clear_fakes()
	# After it: the bulbs up again, the bell a little later.
	var bell: Node = host.system("bell")
	bell.finish_loading()
	var rang := int(bell.plays)
	host.snapshot_override = {"open": false}
	steps(host, 8.0)
	check("the bulbs up again after the film (%.2f)" % light.params["house_lamps"],
			float(light.params["house_lamps"]) > 0.99)
	var early_bell := int(bell.plays) - rang
	steps(host, 20.0)
	check("the church bell in the pre-show, not at once (%d, then %d)" % [early_bell, int(bell.plays) - rang],
			early_bell == 0 and int(bell.plays) - rang == 1)


## The cat walks the wall top, out of the sight line from the viewer's seat.
func _cat(room: Node3D) -> void:
	var host: Node = room.host
	var t: Node = host.system("terrace")
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


## The sound: cicadas round the roof and the city's murmur below that fade as the film starts, a moped passing in the
## street now and then, the church bell far off (a one-shot, nearly gone under a film), the cat's purr kept low, the
## open air; the level measured.
func _sound(room: Node3D) -> void:
	var host: Node = room.host
	var bus := RoomSound.on_room_bus(room, ["cicadas", "moped", "city", "bell"])
	check("the cicadas, the moped, the city and the bell on the room's bus, under Environment %s" % [bus],
			bus.is_empty())
	var ac := RoomSound.acoustics(room, "outdoors", 0.25)
	check("open air (rt60 0.25) %s" % [ac], ac.is_empty() and is_equal_approx(float(host.system("acoustics").values()
			["wet"]), 0.15))
	var cicadas: Node = host.system("cicadas")
	var round_ok: bool = cicadas.players().size() == 4
	for q: Node3D in cicadas.players():
		round_ok = round_ok and absf(Vector2(q.position.x, q.position.z + 4.0).length() - 9.0) < 0.01
	check("cicadas round the roof: four voices 9 m out", cicadas.is_loop() and round_ok)
	var city: Node = host.system("city")
	var below: bool = city.players().size() == 4
	for q: Node3D in city.players():
		below = below and q.position.y < -5.0
	check("the city's murmur all round, from the streets below", city.is_loop() and below)
	var bell: Node = host.system("bell")
	check("the bell a one-shot from the church (%s)" % [bell.params["at"]], not bell.is_loop()
			and Vector3(bell.params["at"][0], 0, bell.params["at"][2]).distance_to(AthensCity.CHURCH) < 1.0)
	host.snapshot_override = {"open": false}
	steps(host, 8.0)
	var before := [float(cicadas.designed_db()), float(city.designed_db()), float(bell.designed_db())]
	host.snapshot_override = {"open": true, "playing": true, "position": 0.5, "duration": 7200.0}
	steps(host, 8.0)
	var after := [float(cicadas.designed_db()), float(city.designed_db()), float(bell.designed_db())]
	check("the cicadas fade as the film starts (%.1f to %.1f dB)" % [before[0], after[0]],
			is_equal_approx(before[0], -54.0) and absf(after[0] - (-68.0)) < 0.2)
	check("the city's murmur under them, and down for the film (%.1f to %.1f dB)" % [before[1], after[1]],
			before[1] < before[0] and absf(after[1] - (before[1] - 10.0)) < 0.2)
	check("the bell far off, nearly gone under a film (%.1f to %.1f dB)" % [before[2], after[2]],
			before[2] < -55.0 and after[2] < -85.0)
	var moped: Node = host.system("moped")
	check("a moped every few minutes, a one-shot that travels", not moped.is_loop()
			and float(moped.params["every"]) >= 120.0 and moped.params.get("to") != null)
	host.do_action("moped.play", {})
	steps(host, 0.1)
	var m3: Node3D = moped.players()[-1]
	var x0 := m3.position.x
	steps(host, 2.0)
	check("it passes in the street below (%.1f -> %.1f, %.1f m down)" % [x0, m3.position.x, m3.position.y],
			m3.position.x > x0 + 15.0 and m3.position.y < -5.0)
	check("the cat's purr kept low, under the seat's ear (voice_db %.0f)" % host.system("cat").params["voice_db"],
			float(host.system("cat").params["voice_db"]) <= -15.0)
	var r: Dictionary = await RoomSound.levels(self, room, "rooftop_athens")
	for v: Array in RoomSound.verdicts("rooftop_athens", r):
		check(v[0], v[1])


func _render(doc: Dictionary) -> void:
	if not RoomRender.has_renderer():
		print("SKIP render (headless)")
		return
	var sc: Array = doc["screen"]["center"]
	var screen := Vector3(float(sc[0]), float(sc[1]), float(sc[2]))
	var baked := OS.get_environment("ROOF_BAKE") != "" and RoomBake.can_bake()
	var only := OS.get_environment("ROOF_SHOTS")
	for phase: String in ["preshow", "film"]:
		if OS.get_environment("ROOF_PHASE") != "" and OS.get_environment("ROOF_PHASE") != phase:
			continue
		RoomRender.set_light(screen, 0.06 if phase == "preshow" else 0.015)
		var vc := await RoomRender.open(self, doc)
		var host: Node = (vc[2] as Node).host
		if baked:
			var room := vc[2] as Node3D
			RoomBake.clear(BAKE_ID)
			RoomBake.prepare(room, BAKE_ID)
			room.call("set_baking", true)
			var br: Dictionary = RoomBake.bake(room, BAKE_ID)
			room.call("set_baking", false)
			print("  render: baked %s" % [br])
			for i in 4:
				await process_frame
		if phase == "preshow":
			# Before the film the painted screen is blank: no picture lights the roof.
			RenderingServer.global_shader_parameter_set("screen_glow", 0.0)
			for n: Node in (vc[2] as Node).get_children():
				if n is MeshInstance3D and (n as MeshInstance3D).mesh is QuadMesh:
					(n as MeshInstance3D).visible = false
			host.snapshot_override = {"open": false}
			host.signals.fake("film.brightness", 0.0)
		else:
			host.snapshot_override = {"open": true, "playing": true, "position": 600.0, "duration": 7200.0}
			host.signals.fake("film.brightness", 0.7)
			host.signals.fake("film.colour", Color(0.85, 0.55, 0.35))
			host.signals.fake("playback.playing", 1.0)
			host.signals.fake("film.minutes", 10.0)
		for i in 160:
			host.step(0.25)
		var eye := Vector3(0, 1.2, 0)
		var p := "roof_%s%s_" % ["baked_" if baked else "", phase]
		var shots := [
			["seat", eye, screen, 90.0],
			["left", eye, eye + Vector3(-1.0, 0.15, -0.3), 90.0],
			["right", eye, eye + Vector3(1.0, 0.15, -0.3), 90.0],
			["up", eye, eye + Vector3(0.0, 1.0, -0.2), 90.0],
			["back", eye, eye + Vector3(0.0, 0.05, 1.0), 90.0],
			["back_left", eye, eye + Vector3(-0.8, 0.12, 0.6), 90.0],
			["citadel", eye, AthensCity.citadel_centre() + Vector3(0, 18.0, 0), 40.0],
			["church", eye, AthensCity.CHURCH + Vector3(0, 2.0, 0), 45.0],
			["wall", eye, Vector3(-5.6, 4.6, -12.0), 50.0],
			["kiosk", Vector3(0.5, 1.6, 2.6), Vector3(5.0, 1.4, 5.5), 70.0],
			["hut", Vector3(-1.5, 1.6, 1.8), Vector3(-0.6, 1.6, 5.4), 70.0],
			["over", Vector3(-5.6, 1.7, -2.0), Vector3(-14.0, -6.0, 2.0), 80.0],
			["street", Vector3(0.0, 1.8, 7.4), Vector3(0.0, -12.0, 13.0), 80.0],
			["right_wall", Vector3(4.0, 1.5, -3.0), Vector3(6.6, 1.0, -6.0), 70.0],
			["front_left", eye, Vector3(-14.0, 3.0, -12.0), 45.0],
			["window_close", Vector3(-12.0, 3.5, -7.0), Vector3(-13.0, 3.5, -12.0), 50.0],
			["far_left", eye, Vector3(-60.0, 4.0, 10.0), 45.0],
			["far_back", eye, Vector3(20.0, 4.0, 60.0), 45.0],
		]
		var side := Vector3(-2.8, 0, -4.6)
		shots.append(["side_seat", side + Vector3(0, 1.2, 0), screen, 90.0])
		for s: Array in shots:
			if only != "" and not (str(s[0]) in only.split(",")):
				continue
			(vc[1] as Camera3D).fov = float(s[3])
			var img: Image = await RoomRender.shot(self, vc, s[1], s[2], p + str(s[0]))
			if str(s[0]) == "seat":
				var wall := (RoomRender.mean(img, Rect2(0.05, 0.25, 0.15, 0.25)).get_luminance()
						+ RoomRender.mean(img, Rect2(0.8, 0.25, 0.15, 0.25)).get_luminance()) * 0.5
				var floor_l := RoomRender.mean(img, Rect2(0.3, 0.85, 0.4, 0.15)).get_luminance()
				print("  render: %s from the seat: the wall %.3f, the floor and chairs %.3f" % [phase, wall, floor_l])
		await RoomRender.close(self, vc)


const AthensCity := preload("res://scripts/env/systems/kit/athens_city.gd")
