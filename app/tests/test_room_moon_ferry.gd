extends "res://tests/env_builder_harness.gd"

## Moon ferry (app/environments/moon_ferry.env.json; docs/environments/rooms/moon_ferry.md): a classic retro-futuristic
## cislunar passenger liner gliding silently from an orbital transfer dock to the Moon Crater base. Earth shrinks astern
## while the procedural cratered Moon grows ahead, culminating in a gentle touchdown on lunar regolith.
## Built by Gemini 4 Neon Extra High.
## godot --headless --xr-mode off --path app --script res://tests/test_room_moon_ferry.gd

const RoomJourney := preload("res://tests/room_journey.gd")
const RoomRender := preload("res://tests/room_render.gd")
const RoomSound := preload("res://tests/room_sound.gd")
const DOC := "res://environments/moon_ferry.env.json"


func run_tests() -> void:
	test_name = "test_room_moon_ferry"
	var doc := RoomJourney.load_doc(self, DOC)
	if doc.is_empty():
		return
	var room := await RoomJourney.check_journey(self, "moon_ferry", doc, "ferry", "cislunar", {
			"min_speed": 3.4, "max_speed": 4.2, "start_landmark": "orbital_station", "end_landmark": "lunar_base"})
	RoomJourney.check_fittings(self, room, "ferry", "fittings",
			"the forward console, viewport ledges, airlock collar and aft consoles", 6)
	check("the mission chronometer is built (PieceClock)", room.find_child("PieceClock", true, false) != null)
	check("the orbital coves and aisle guides are built (PieceCove)",
			room.find_child("PieceCove", true, false) != null)
	check("the cabin sconces are built (PieceLamps)", room.find_child("PieceLamps", true, false) != null)
	check("the telemetry monitors, airlock viewport and trajectory map are built (PieceWindows)",
			room.find_child("PieceWindows", true, false) != null)
	check("the glazed canopy and aerospace viewports are built (Glass)",
			room.find_child("Glass", true, false) != null)
	check("Earth and the procedural Moon are built (SkyEarth, SkyMoon)",
			room.find_child("SkyEarth", true, false) != null and room.find_child("SkyMoon", true, false) != null)
	check("the lunar regolith plain is built (PassingGround)",
			room.find_child("PassingGround", true, false) != null)
	check("the room is credited to Gemini 4 Neon Extra High",
			str((doc.get("room", {}) as Dictionary).get("author", "")) == "Gemini 4 Neon Extra High")
	var seats: Array[Transform3D] = room.room_seat_transforms()
	var own := seats.any(func(t: Transform3D) -> bool: return t.origin.length() < 0.001)
	check("three rows of four cislunar recliners (%d), one at the origin" % seats.size(), seats.size() == 12 and own)
	_cislunar_arc_and_settings(room)
	# Sound: vacuum acoustics, ultra-subtle cabin life support hum, speed-bound transit drive hum, retro-burn thruster
	# pulse and orbital boarding/touchdown cabin chime.
	RoomSound.check_beds(self, "moon_ferry", room, {"life_support": "hum", "drive": "climber_hum",
			"thruster": "rumble", "chime": "cabin_chime"}, "vacuum")
	RoomJourney.check_speed_bed(self, room, "drive", "the cislunar transit drive hum", 0.25)
	RoomJourney.check_figures(self, "moon_ferry", room, 38, 120000)
	await done(room)
	await RoomSound.check_level(self, self, "moon_ferry", doc)
	await _render(doc)


## Earth shrinks astern (28 -> 2.2 deg), the Moon grows ahead (2.4 -> 34 deg), regolith stays hidden in deep space and
## emerges cleanly on lunar descent (0.76..0.88), and Cabin light / Starlight settings work live.
func _cislunar_arc_and_settings(room: Node3D) -> void:
	var host: Node = room.host
	var sky: Node = host.system("sky")
	var way: Node = host.system("cislunar")
	var kit: Node = host.system("fittings")
	var ground := room.find_child("PassingGround", true, false) as MeshInstance3D

	check("sky is full all-sky space with 4000 faint stars and detailed Milky Way (%s, all_sky=%s, stars=%d)" % [
			str(sky.params["mode"]), str(sky.params["all_sky"]), int(sky.params["faint_stars"])],
			sky != null and str(sky.params["mode"]) == "space" and bool(sky.params["all_sky"])
			and int(sky.params["faint_stars"]) == 4000 and float(sky.params["milky_detail"]) >= 0.99
			and bool(sky.params["earth"]) and bool(sky.params["earth_detail"]))

	# Stage 0: Departure (huge 28 deg Earth, small 2.4 deg Moon, lunar regolith hidden so 360 deg stars shine below).
	RoomJourney.step_stage(host, 0.0)
	check("at departure Earth is large (%.1f deg), Moon is distant (%.1f deg), regolith hidden (vis %.2f, vis=%s)" % [
			float(sky.params["earth_size"]), float(sky.params["moon_size"]), float(way.params["ground_vis"]),
			str(ground.visible)],
			absf(float(sky.params["earth_size"]) - 28.0) < 0.5 and absf(float(sky.params["moon_size"]) - 2.4) < 0.3
			and float(way.params["ground_vis"]) < 0.01 and not ground.visible)

	# Stage 1: Mid-transit cislunar coast (0.45) — Earth shrinking, Moon growing, deep space all around.
	RoomJourney.step_stage(host, 0.45)
	check("mid-transit: Earth shrunk (%.1f deg), Moon grown (%.1f deg), regolith still hidden (%.2f)" % [
			float(sky.params["earth_size"]), float(sky.params["moon_size"]), float(way.params["ground_vis"])],
			float(sky.params["earth_size"]) < 12.0 and float(sky.params["earth_size"]) > 8.0
			and float(sky.params["moon_size"]) > 14.0 and float(way.params["ground_vis"]) < 0.01)

	# Stage 2: Final lunar orbital approach (0.76) — giant 34 deg cratered Moon fills the glass before descent!
	RoomJourney.step_stage(host, 0.76)
	check("lunar approach: Moon fills the glass (%.1f deg, alt %.1f deg, moon %.2f), Earth distant (%.1f deg)" % [
			float(sky.params["moon_size"]), float(sky.params["moon_altitude"]), float(sky.params["moon"]),
			float(sky.params["earth_size"])],
			float(sky.params["moon_size"]) >= 33.0 and absf(float(sky.params["moon_altitude"]) - 6.0) < 0.5
			and float(sky.params["moon"]) > 0.95 and float(sky.params["earth_size"]) < 5.0)

	# Stage 3: Lunar touchdown at Crater base (1.0) — Earth shrunk to 2.2 deg, sunlit regolith plain fully visible!
	RoomJourney.step_stage(host, 1.0)
	check("at lunar touchdown: Earth shrunk to %.1f deg (alt %.1f deg), regolith visible (vis %.2f, vis=%s)" % [
			float(sky.params["earth_size"]), float(sky.params["earth_altitude"]), float(way.params["ground_vis"]),
			str(ground.visible)],
			absf(float(sky.params["earth_size"]) - 2.2) < 0.2 and float(sky.params["earth_altitude"]) > 10.0
			and float(way.params["ground_vis"]) > 0.98 and ground.visible)

	# Cabin light setting: Warm amber / Ice blue / Off.
	host.set_setting("cabin_light", "blue")
	for i in 12:
		host.step(0.25)
	var st_b: Dictionary = kit.cove_state()
	var col_b: Color = st_b.get("colour", Color.BLACK)
	check("Cabin light=blue shifts orbital coves to ice blue (%s)" % col_b,
			not st_b.is_empty() and col_b.b > col_b.r * 1.8)
	host.set_setting("cabin_light", "off")
	for i in 12:
		host.step(0.25)
	check("Cabin light=off dims coves to zero (%.2f)" % float(kit.cove_state().get("glow", 1.0)),
			float(kit.cove_state().get("glow", 1.0)) < 0.01)
	host.set_setting("cabin_light", "amber")
	for i in 12:
		host.step(0.25)
	var st_a: Dictionary = kit.cove_state()
	var col_a: Color = st_a.get("colour", Color.BLACK)
	check("Cabin light=amber restores warm orbital amber (%s)" % col_a,
			not st_a.is_empty() and col_a.r > col_a.b * 1.8)

	# Starlight setting: Deep Milky Way / Quiet stars / Constellations.
	host.set_setting("starlight", "quiet")
	for i in 24:
		host.step(0.25)
	check("Starlight=quiet lowers Milky Way (%.2f)" % float(sky.params["milky_way"]),
			float(sky.params["milky_way"]) < 0.35)
	host.set_setting("starlight", "constellations")
	for i in 24:
		host.step(0.25)
	check("Starlight=constellations raises constellation lines (%.2f) and builds SkyLines" % float(sky.params["lines"]),
			float(sky.params["lines"]) > 0.45 and room.find_child("SkyLines", true, false) != null)
	host.set_setting("starlight", "milky_way")
	for i in 24:
		host.step(0.25)
	check("Starlight=milky_way restores full Milky Way (%.2f)" % float(sky.params["milky_way"]),
			float(sky.params["milky_way"]) > 0.72)


func _render(doc: Dictionary) -> void:
	if not RoomRender.has_renderer():
		print("SKIP render (headless)")
		return
	var sc: Array = doc["screen"]["center"]
	var screen := Vector3(float(sc[0]), float(sc[1]), float(sc[2]))
	RoomRender.set_light(screen, 0.05)
	var vc := await RoomRender.open(self, doc)
	var host: Node = (vc[2] as Node).host
	host.signals.fake("film.brightness", 0.6)
	host.signals.fake("playback.playing", 1.0)
	var eye := Vector3(0.0, 1.2, 0.0)

	# 1. Pre-show cabin overview at Earth-orbit departure dock (travel = 0.0): ivory composite, brushed titanium,
	#    crimson recliners, warm amber coves, telemetry, circular aft airlock hatch, trajectory map console,
	#    orbital_station transfer dock outside starboard & glowing 28 deg Earth outside port!
	host.snapshot_override = {"open": false}
	for i in 48:
		host.step(0.25)
	RenderingServer.global_shader_parameter_set("screen_glow", 0.0)
	await RoomRender.shot(self, vc, Vector3(-0.82, 1.70, 2.55), screen, "mf_preshow_front")
	await RoomRender.shot(self, vc, Vector3(-0.82, 1.56, -2.15), Vector3(-0.82, 1.32, 3.4), "mf_preshow_aft")
	await RoomRender.shot(self, vc, Vector3(-1.35, 1.50, 1.25), Vector3(-2.36, 0.96, 2.95), "mf_preshow_console")
	await RoomRender.shot(self, vc, eye, eye + Vector3(0.92, 0.10, -0.38), "mf_departure_station")

	# 2. Earth-orbit departure under way (0.0005): huge 28 deg Earth gleaming out port viewports & screen seat view!
	RoomRender.set_light(screen, 0.018)
	RoomJourney.step_stage(host, 0.0005)
	await RoomRender.shot(self, vc, eye, eye + Vector3(-0.96, 0.11, 0.28), "mf_departure_earth")
	await RoomRender.shot(self, vc, eye, screen, "mf_departure_seat")

	# 3. Mid-cislunar coast (0.45): Earth shrunk astern, growing cratered Moon ahead, 360 deg Milky Way & stars!
	RoomJourney.step_stage(host, 0.45)
	await RoomRender.shot(self, vc, eye, eye + Vector3(-0.96, 0.14, 0.28), "mf_midtransit_earth")
	await RoomRender.shot(self, vc, eye, eye + Vector3(0.85, 0.19, -0.53), "mf_midtransit_moon")
	await RoomRender.shot(self, vc, Vector3(-0.82, 1.18, 0.35), Vector3(-0.82, 2.95, -1.2), "mf_midtransit_canopy")

	# 4. Final lunar orbital approach (0.76): colossal 34 deg procedural cratered Moon filling the starboard glass!
	RoomJourney.step_stage(host, 0.76)
	await RoomRender.shot(self, vc, eye, eye + Vector3(0.85, 0.11, -0.53), "mf_approach_moon")
	await RoomRender.shot(self, vc, Vector3(-0.82, 1.32, 1.35), Vector3(0.65, 1.72, -1.65), "mf_approach_wide")
	# Verify live Ice blue cabin lighting + Constellations setting during lunar approach!
	host.set_setting("cabin_light", "blue")
	host.set_setting("starlight", "constellations")
	for i in 24:
		host.step(0.25)
	await RoomRender.shot(self, vc, Vector3(-0.82, 1.32, 1.85), Vector3(-0.45, 2.05, -3.2),
			"mf_approach_blue_constellations")
	host.set_setting("cabin_light", "amber")
	host.set_setting("starlight", "milky_way")
	for i in 24:
		host.step(0.25)

	# 5. Touchdown at Moon Crater base (1.0): sunlit cratered regolith plain, crater-rim ridge, illuminated geodesic
	#    domes & pad strobes of lunar_base, and tiny 2.2 deg Earth hanging in black space above the port crater rim!
	RoomJourney.step_stage(host, 1.0)
	RoomRender.set_light(screen, 0.05)
	RenderingServer.global_shader_parameter_set("screen_glow", 0.0)
	await RoomRender.shot(self, vc, eye, eye + Vector3(0.98, 0.03, -0.18), "mf_touchdown_base")
	await RoomRender.shot(self, vc, eye, eye + Vector3(-0.96, 0.16, 0.28), "mf_touchdown_earth")
	await RoomRender.close(self, vc)
