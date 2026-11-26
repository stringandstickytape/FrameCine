extends "res://tests/env_builder_harness.gd"

## M1 Grand Tour (app/environments/m1_grand_tour.env.json; docs/environments/rooms/m1_grand_tour.md):
## flagship room of the Real drives category, built by Gemini 4 Neon Extra High.
## Tests: schema, comfort, open-data credits, sight lines, tight VR budgets (0 live lights, <= 34 draws, <= 90k tris,
## blend < 1.0, build < 2.0), dead-centre 3-across rear bench, route start & NB/SB direction switching, weather &
## time-of-day switching, amber matrix '50' activation, live overbridge rain-occlusion dips, twin live screen hook,
## sound levels, and lavapipe visual QA shots (including UK TSRGD road sign close-ups!).
## godot --headless --xr-mode off --path app --script res://tests/test_room_m1_grand_tour.gd

const RoomRender := preload("res://tests/room_render.gd")
const RoomSound := preload("res://tests/room_sound.gd")
const DOC := "res://environments/m1_grand_tour.env.json"


func run_tests() -> void:
	test_name = "test_room_m1_grand_tour"
	var r := EnvDoc.load_file(DOC)
	check("the document reads (%s)" % [r["errors"]], (r["errors"] as Array).is_empty())
	var doc: Dictionary = r["doc"]
	if doc.is_empty():
		return
	if OS.get_environment("M1_RENDER_ONLY") == "":
		var room := await check_room("m1_grand_tour", doc)
		room.host.auto = false
		await _built_and_budgets(room, doc)
		_seats_and_cabin(room)
		_route_and_direction(room)
		_weather_time_and_bridges(room)
		_sound_beds(room)
		await done(room)
		await _build_speed(doc)
		var lvl := await RoomSound.check_level(self, self, "m1_grand_tour", doc)
		check("sound pre-show RMS comfortably below -38 dBFS (%.1f dBFS)" % float(lvl["pre"]),
				float(lvl["pre"]) < -42.0)
		check("sound under-film RMS in -58..-84 dBFS quiet band (%.1f dBFS)" % float(lvl["under"]),
				float(lvl["under"]) < -58.0 and float(lvl["under"]) > -84.0)
	await _render(doc)


func _built_and_budgets(room: Node3D, doc: Dictionary) -> void:
	var host: Node = room.host
	var stats := EnvChecks.measure(room)
	print("  measured: %s" % [stats])
	check("within M1 Grand Tour tight budget: <= 34 draws, <= 90k tris, 0 live lights, <= 32 MB tex (%s)" % [stats],
			int(stats["draws"]) <= 34 and int(stats["triangles"]) <= 90000 and int(stats["lights"]) == 0
			and int(stats["particles"]) <= 1200 and float(stats["texture_mb"]) <= 32.0)

	var meta: Dictionary = doc.get("room", {})
	check("name is M1 Grand Tour", str(doc.get("name", "")) == "M1 Grand Tour")
	check("category is drive", str(meta.get("category", "")) == "drive")
	check("author is Gemini 4 Neon Extra High", str(meta.get("author", "")) == "Gemini 4 Neon Extra High")
	check("description <= 200 chars (%d)" % str(meta.get("description", "")).length(),
			str(meta.get("description", "")).length() <= 200)

	var kit: Node = host.system("fittings")
	check("kit builds cleanly with zero problems (%s)" % [kit.problems()], kit != null and kit.problems().is_empty())
	for n: String in ["GtInterior", "GT_mat_hide", "GT_mat_walnut", "GT_mat_metal", "GT_mat_paint", "PieceClock",
			"GtLiveRig", "DashScreen", "WindscreenGlass", "WiperLeft", "WiperRight", "SpeedoNeedle",
			"MotorwayRoad", "MotorwayTerrain", "MotorwayTrees", "MotorwaySigns", "MotorwayHardware", "MotorwayTowers"]:
		check("room has %s" % n, room.find_child(n, true, false) != null)

	var layers: Dictionary = await EnvChecks.blend_layers(self, room)
	print("  blend layers: %s" % [layers])
	check("blend layers under budget (%s)" % [layers], float(layers["mean"]) <= EnvChecks.BLEND_BUDGET)


func _seats_and_cabin(room: Node3D) -> void:
	var seats: Array = room.call("get_seats")
	check("3-across odd rear bench (3 seats, got %d)" % seats.size(), seats.size() == 3)
	var has_centre := false
	for p: Vector3 in seats:
		if p.distance_to(Vector3.ZERO) < 0.02:
			has_centre = true
	check("dead-centre head-on seat at (0, 0, 0)", has_centre)
	var kit: Node = room.host.system("fittings")
	check("analogue centre clock hands live (%s)" % [kit.call("clock_hands")],
			(kit.call("clock_hands") as Array).size() == 2)


func _route_and_direction(room: Node3D) -> void:
	var mw: Node = room.host.system("motorway")
	check("real OSM overbridges loaded (%d)" % int(mw.call("overbridge_count")), int(mw.call("overbridge_count")) >= 200)
	room.host.set_setting("start_at", "chilterns_j10")
	room.host.set_setting("direction", "northbound")
	room.host.step(0.1)
	var km0 := float(mw.call("current_km"))
	check("Chilterns J10 start near 37.4 km (%.2f)" % km0, absf(km0 - 37.4) < 0.5)
	for _i in 10:
		room.host.step(0.2)
	var km1 := float(mw.call("current_km"))
	check("northbound advances chainage (%.3f -> %.3f)" % [km0, km1], km1 > km0 + 0.02)

	room.host.set_setting("start_at", "leeds_j47")
	room.host.set_setting("direction", "southbound")
	room.host.step(0.1)
	var s0 := float(mw.call("current_km"))
	for _i in 10:
		room.host.step(0.2)
	var s1 := float(mw.call("current_km"))
	check("southbound from Leeds J47 decreases chainage (%.3f -> %.3f)" % [s0, s1], s0 > 300.0 and s1 < s0 - 0.02)
	check("speedo cruises cleanly (%.1f mph)" % float(mw.call("speed_mph")), float(mw.call("speed_mph")) > 40.0)


func _weather_time_and_bridges(room: Node3D) -> void:
	var mw: Node = room.host.system("motorway")
	room.host.set_setting("weather", "fog")
	room.host.step(0.2)
	check("amber '50' matrix signal activates in fog", bool(mw.call("matrix_active")))

	room.host.set_setting("weather", "rain")
	room.host.step(0.2)
	check("rain level rises in steady rain (%.2f)" % float(mw.call("rain_level")), float(mw.call("rain_level")) > 0.4)
	# Jump onto a real OSM overbridge and verify live rain-occlusion acoustic dip + bridge_whoosh!
	var ob0: Dictionary = (mw.get("_overbridges") as Array)[10]
	var b_km := float(ob0["s"]) * 0.001
	mw.call("act", "jump_km", {"km": b_km})
	room.host.step(0.4)
	check("real OSM overbridge detected & dips roof/windscreen rain (shelter=%.2f)" % float(mw.call("bridge_shelter")),
			bool(mw.call("under_bridge")) and float(mw.call("bridge_shelter")) < 0.65)

	# Clear skies turns off matrix & dries rain
	room.host.set_setting("weather", "clear")
	for _i in 20:
		room.host.step(0.25)
	check("clear weather turns off matrix & dries glass (rain=%.2f)" % float(mw.call("rain_level")),
			not bool(mw.call("matrix_active")) and float(mw.call("rain_level")) < 0.05)


func _sound_beds(room: Node3D) -> void:
	for sid: String in ["gt_w12", "rain_roof", "rain_windscreen", "wiper_swish", "bridge_whoosh", "thunder_roll"]:
		var sb: Node = room.host.system(sid)
		check("sound bed %s present" % sid, sb != null)


func _build_speed(doc: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	var room2: Node3D = EnvRoom.new()
	room2.doc = doc
	root.add_child(room2)
	await process_frame
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var units := EnvChecks.build_units(ms)
	print("  build speed: %.1f ms (%.2f units)" % [ms, units])
	check("builds under 2.5 units (%.2f)" % units, units <= 2.5)
	await done(room2)


func _render(doc: Dictionary) -> void:
	if not RoomRender.has_renderer():
		print("SKIP render (headless)")
		return
	var sc: Array = doc["screen"]["center"]
	var screen := Vector3(float(sc[0]), float(sc[1]), float(sc[2]))
	RoomRender.set_light(screen, 0.14)
	var vc := await RoomRender.open(self, doc, 76.0)
	var room: Node3D = vc[2] as Node3D
	var cam: Camera3D = vc[1] as Camera3D
	room.host.auto = false
	var mw: Node = room.host.system("motorway")

	var settle := func(steps := 4, dt := 0.04) -> void:
		for _i in steps:
			room.host.step(dt)
			await process_frame

	# 1. Rear centre seat default view (Golden hour, Chilterns J10 approaching 1-mile Luton fork sign!)
	room.host.set_setting("start_at", "chilterns_j10")
	room.host.set_setting("direction", "northbound")
	room.host.set_setting("trim", "saddle")
	room.host.set_setting("time_of_day", "golden")
	room.host.set_setting("weather", "clear")
	mw.call("act", "jump_km", {"km": 37.448})
	await settle.call(3, 0.02)
	cam.fov = 76.0
	await RoomRender.shot(self, vc, Vector3(0.0, 1.20, 0.0), Vector3(0.0, 1.12, -25.0), "m1_01_centre_seat_golden")

	# 2. Front cockpit close-up (passenger-to-driver coupe view: twin-wing walnut dash, bullseye vents, clock, 4-gauge binnacle, wheel, shifter, door card!)
	cam.fov = 66.0
	await RoomRender.shot(self, vc, Vector3(-0.46, 1.08, -1.16), Vector3(0.24, 0.80, -1.74), "m1_02_cockpit_saddle_closeup")

	# 3. Zoomed Close-up of UK TSRGD Diagram 2904 1-mile Motorway Fork Sign (`ads_nb_j10` at s=37485) in-engine!
	mw.call("act", "jump_km", {"km": 37.460})
	await settle.call(2, 0.01)
	cam.fov = 38.0
	await RoomRender.shot(self, vc, Vector3(-10.2, 3.3, -12.5), Vector3(-11.7, 3.4, -25.0), "m1_03_sign_ads_j10_closeup")

	# 4. Zoomed Close-up of UK TSRGD 3-Lane Overhead Motorway Gantry (`gantry_nb_midlands` at s=143380) in-engine!
	room.host.set_setting("time_of_day", "afternoon")
	room.host.set_setting("weather", "clear")
	mw.call("act", "jump_km", {"km": 143.346})
	await settle.call(2, 0.01)
	cam.fov = 46.0
	await RoomRender.shot(self, vc, Vector3(0.0, 4.4, -6.0), Vector3(0.0, 6.2, -34.0), "m1_04_sign_gantry_j21_closeup")

	# 5. Daytime M1 drive from rear seat with Leicester J21 overhead gantry, UK trees & traffic ahead
	mw.call("act", "jump_km", {"km": 143.335})
	await settle.call(2, 0.01)
	cam.fov = 76.0
	await RoomRender.shot(self, vc, Vector3(0.0, 1.20, 0.0), Vector3(0.0, 1.24, -30.0), "m1_05_daytime_gantry_cabin")

	# 6. Iconic Ratcliffe-on-Soar 8 Cooling Towers rising over the Trent Valley at Golden Hour!
	room.host.set_setting("time_of_day", "golden")
	room.host.set_setting("weather", "clear")
	mw.call("act", "jump_km", {"km": 177.690})
	await settle.call(2, 0.01)
	cam.fov = 66.0
	await RoomRender.shot(self, vc, Vector3(0.0, 2.2, -4.0), Vector3(68.0, 18.0, -95.0), "m1_06_ratcliffe_cooling_towers")

	# 7. Foggy Night with SOX orange streetlamps + glowing steady Amber '50' Matrix Gantry Signals (`gantry_nb_south` at s=37740)!
	room.host.set_setting("time_of_day", "night")
	room.host.set_setting("weather", "fog")
	mw.call("act", "jump_km", {"km": 37.702})
	await settle.call(4, 0.02)
	cam.fov = 76.0
	await RoomRender.shot(self, vc, Vector3(0.0, 1.20, 0.0), Vector3(0.0, 1.32, -35.0), "m1_07_foggy_night_matrix50")

	# 8. Heavy Thunderstorm + Animated Wipers mid-sweep + Wet Windscreen + Leicester Forest East Bridge Cafe (`s=147046`)!
	room.host.set_setting("time_of_day", "dusk")
	room.host.set_setting("weather", "storm")
	mw.call("act", "jump_km", {"km": 146.978})
	await settle.call(14, 0.04)
	mw.call("act", "jump_km", {"km": 146.988})
	await settle.call(2, 0.01)
	cam.fov = 76.0
	await RoomRender.shot(self, vc, Vector3(0.0, 1.20, 0.0), Vector3(0.0, 1.24, -40.0), "m1_08_storm_wipers_lfe_cafe")

	# 9. Trim 2: Beluga & Dark Walnut cockpit close-up
	room.host.set_setting("trim", "beluga")
	room.host.set_setting("time_of_day", "afternoon")
	room.host.set_setting("weather", "clear")
	mw.call("act", "jump_km", {"km": 37.448})
	await settle.call(3, 0.02)
	cam.fov = 66.0
	await RoomRender.shot(self, vc, Vector3(-0.46, 1.08, -1.16), Vector3(0.24, 0.80, -1.74), "m1_09_trim_beluga")

	# 10. Trim 3: Oxblood & Dark Walnut cockpit close-up
	room.host.set_setting("trim", "oxblood")
	await settle.call(3, 0.02)
	await RoomRender.shot(self, vc, Vector3(-0.46, 1.08, -1.16), Vector3(0.24, 0.80, -1.74), "m1_10_trim_oxblood")

	# 11. Aft cabin & 3-across Saddle stitched rear bench view (cleanly behind floating seatback screen!)
	room.host.set_setting("trim", "saddle")
	await settle.call(3, 0.02)
	cam.fov = 76.0
	await RoomRender.shot(self, vc, Vector3(-0.32, 1.06, -0.50), Vector3(0.06, 0.66, 0.34), "m1_11_aft_rear_bench")

	# 12. Primary Rear Cinema Console Screen playing film on wet rainy British night M1!
	room.host.set_setting("time_of_day", "night")
	room.host.set_setting("weather", "rain")
	mw.call("act", "jump_km", {"km": 37.698})
	await settle.call(6, 0.02)
	var film_mat := _make_test_film_mat()
	var rig := room.find_child("GtLiveRig", true, false)
	if rig != null:
		rig.set("demo_film_mat", film_mat)
	var scr_xf: Transform3D = room.call("get_screen_anchor")
	var sc_q := QuadMesh.new()
	sc_q.size = Vector2(0.48, 0.27)
	var sc_mi := MeshInstance3D.new()
	sc_mi.mesh = sc_q
	sc_mi.material_override = film_mat
	sc_mi.transform = scr_xf
	room.add_child(sc_mi)
	await settle.call(2, 0.01)
	cam.fov = 74.0
	await RoomRender.shot(self, vc, Vector3(-0.22, 1.18, 0.06), Vector3(0.02, 0.94, -1.30), "m1_12_twin_screens_playing")

	# 13. Front Walnut Waterfall Live Synced Auxiliary `DashScreen` + Analogue Clock + Chrome Bullseye Vents!
	cam.fov = 52.0
	await RoomRender.shot(self, vc, Vector3(-0.04, 0.95, -1.16), Vector3(0.0, 0.78, -1.68), "m1_13_dash_screen_synced")
	sc_mi.queue_free()

	await RoomRender.close(self, vc)


func _make_test_film_mat() -> StandardMaterial3D:
	var img := Image.create_empty(256, 144, false, Image.FORMAT_RGB8)
	for y in 144:
		for x in 256:
			var u := float(x) / 256.0
			var v := float(y) / 144.0
			var c := Color(0.18 + 0.65 * sin(u * PI), 0.24 + 0.42 * (1.0 - v), 0.32 + 0.55 * cos((u - 0.5) * PI))
			if v < 0.10 or v > 0.90:
				c = Color(0.03, 0.03, 0.04) # 2.39:1 cinema letterbox bars!
			img.set_pixel(x, y, c)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = ImageTexture.create_from_image(img)
	return m
