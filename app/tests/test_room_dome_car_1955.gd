extends "res://tests/env_builder_harness.gd"

## Dome car 1955 (app/environments/dome_car_1955.env.json; docs/environments/rooms/dome_car_1955.md): a gleaming
## mid-century stainless-steel desert observation dome car crossing moonlit Southwest canyon country beneath the
## Milky Way and shooting stars. Built by Gemini 4 Neon Extra High.
## godot --headless --xr-mode off --path app --script res://tests/test_room_dome_car_1955.gd

const RoomJourney := preload("res://tests/room_journey.gd")
const RoomRender := preload("res://tests/room_render.gd")
const RoomSound := preload("res://tests/room_sound.gd")
const DOC := "res://environments/dome_car_1955.env.json"


func run_tests() -> void:
	test_name = "test_room_dome_car_1955"
	var doc := RoomJourney.load_doc(self, DOC)
	if doc.is_empty():
		return
	var room := await RoomJourney.check_journey(self, "dome_car_1955", doc, "dome", "desert", {
			"min_speed": 4.8, "max_speed": 6.2, "start_landmark": "station", "end_landmark": "station"})
	RoomJourney.check_fittings(self, room, "dome", "fittings", "the dome car console, ledges and aft balustrade", 7)
	check("the sunburst bulkhead clock is built (PieceClock)", room.find_child("PieceClock", true, false) != null)
	check("the dome coves and aisle guides are built (PieceCove)", room.find_child("PieceCove", true, false) != null)
	check("the atomic dome table lamps are built (PieceLamps)", room.find_child("PieceLamps", true, false) != null)
	check("the curved glazed roof and panoramic windows are built (Glass)",
			room.find_child("Glass", true, false) != null)
	check("the room is credited to Gemini 4 Neon Extra High",
			str((doc.get("room", {}) as Dictionary).get("author", "")) == "Gemini 4 Neon Extra High")
	var seats: Array[Transform3D] = room.room_seat_transforms()
	var own := seats.any(func(t: Transform3D) -> bool: return t.origin.length() < 0.001)
	check("three rows of four observation recliners (%d), one at the origin" % seats.size(), seats.size() == 12 and own)
	_sky_and_settings(room)
	# Sound: brisk streamliner rail joints following journey.speed, diesel horn one-shot on departure/arrival,
	# desert crickets loud at stations and quiet under way, soft desert night wind; small_room acoustics.
	RoomSound.check_beds(self, "dome_car_1955", room, {"rails": "rail_joints", "horn": "diesel_horn",
			"crickets": "crickets", "wind": "wind"}, "small_room")
	RoomJourney.check_speed_bed(self, room, "rails", "the rail joints", 0.0)
	_crickets_inverse(room)
	RoomJourney.check_figures(self, "dome_car_1955", room, 38, 120000)
	await done(room)
	await RoomSound.check_level(self, self, "dome_car_1955", doc)
	await _render(doc)


## Desert twilight deepens into full Milky Way night; Dome coves and Starlight settings work live.
func _sky_and_settings(room: Node3D) -> void:
	var host: Node = room.host
	var sky: Node = host.system("sky")
	var kit: Node = host.system("fittings")
	check("sky starts in desert twilight (dusk %.2f, milky_detail %.1f, faint_stars %d)" % [
			float(sky.params["dusk"]), float(sky.params["milky_detail"]), int(sky.params["faint_stars"])],
			sky != null and absf(float(sky.params["dusk"]) - 0.2) < 0.05
			and float(sky.params["milky_detail"]) >= 0.99 and int(sky.params["faint_stars"]) == 2800)
	RoomJourney.step_stage(host, 0.35)
	check("sky deepens to ink-black desert night by 35%% of the film (dusk %.2f)" % float(sky.params["dusk"]),
			float(sky.params["dusk"]) > 0.98)
	var before_m := int(sky.meteors_sent)
	sky.act("shooting_star", {})
	check("shooting star action fires across the dome sky (%d -> %d)" % [before_m, int(sky.meteors_sent)],
			int(sky.meteors_sent) == before_m + 1)

	# Dome coves setting: Turquoise / Desert coral / Warm chrome / Off.
	host.set_setting("cove", "coral")
	for i in 12:
		host.step(0.25)
	var st: Dictionary = kit.cove_state()
	var col: Color = st.get("colour", Color.BLACK)
	check("Dome coves=coral shifts valance and aisle strips warm coral (%s)" % col,
			not st.is_empty() and col.r > col.b * 2.0)
	host.set_setting("cove", "off")
	for i in 12:
		host.step(0.25)
	check("Dome coves=off dims cove strips to zero (%.2f)" % float(kit.cove_state().get("glow", 1.0)),
			float(kit.cove_state().get("glow", 1.0)) < 0.01)
	host.set_setting("cove", "turquoise")
	for i in 12:
		host.step(0.25)
	var st_t: Dictionary = kit.cove_state()
	var col_t: Color = st_t.get("colour", Color.BLACK)
	check("Dome coves=turquoise restores turquoise glow (%s)" % col_t,
			not st_t.is_empty() and col_t.g > col_t.r * 2.0 and col_t.b > col_t.r * 2.0)

	# Starlight setting: Milky Way & meteors / Quiet stars / Constellations.
	host.set_setting("starlight", "quiet")
	for i in 24:
		host.step(0.25)
	check("Starlight=quiet lowers Milky Way (%.2f) and turns off meteors (%.1f)" % [
			float(sky.params["milky_way"]), float(sky.params["meteors"])],
			float(sky.params["milky_way"]) < 0.45 and float(sky.params["meteors"]) < 0.1)
	host.set_setting("starlight", "constellations")
	for i in 24:
		host.step(0.25)
	check("Starlight=constellations raises constellation lines (%.2f) and builds SkyLines" % float(sky.params["lines"]),
			float(sky.params["lines"]) > 0.45 and room.find_child("SkyLines", true, false) != null)
	host.set_setting("starlight", "cosmos")
	for i in 24:
		host.step(0.25)
	check("Starlight=cosmos restores full Milky Way (%.2f) and meteors (%.1f)" % [
			float(sky.params["milky_way"]), float(sky.params["meteors"])],
			float(sky.params["milky_way"]) > 0.9 and float(sky.params["meteors"]) >= 11.5)


## Desert crickets chirp loudly at desert station stops and hush to a whisper under way.
func _crickets_inverse(room: Node3D) -> void:
	var host: Node = room.host
	var crickets: Node = host.system("crickets")
	host.timeline.state = ""
	var pos := 600.0
	for i in 120:
		pos += 0.25
		host.snapshot_override = {"open": true, "playing": true, "position": pos, "duration": RoomJourney.FILM}
		host.step(0.25)
	var rolling := float(crickets.params["level"])
	host.snapshot_override = {"open": true, "playing": false, "position": pos, "duration": RoomJourney.FILM}
	for i in 120:
		host.step(0.25)
	var stopped := float(crickets.params["level"])
	check("desert crickets quiet under way (%.2f) and loud at station stops (%.2f)" % [rolling, stopped],
			rolling < 0.14 and stopped > 0.8)


func _render(doc: Dictionary) -> void:
	if not RoomRender.has_renderer():
		print("SKIP render (headless)")
		return
	var sc: Array = doc["screen"]["center"]
	var screen := Vector3(float(sc[0]), float(sc[1]), float(sc[2]))
	RoomRender.set_light(screen, 0.015)
	var vc := await RoomRender.open(self, doc)
	var host: Node = (vc[2] as Node).host
	host.signals.fake("film.brightness", 0.6)
	host.signals.fake("playback.playing", 1.0)
	var eye := Vector3(0.0, 1.2, 0.0)

	# 1. Pre-show: bright atomic dome lamps & turquoise coves, paused at desert twilight station (screen_glow = 0).
	host.snapshot_override = {"open": false}
	for i in 48:
		host.step(0.25)
	RoomRender.set_light(screen, 0.05)
	RenderingServer.global_shader_parameter_set("screen_glow", 0.0)
	await RoomRender.shot(self, vc, Vector3(-0.785, 1.72, 2.55), screen, "dome_preshow_front")
	await RoomRender.shot(self, vc, Vector3(-0.785, 1.62, -2.5), Vector3(-0.785, 1.55, 3.4), "dome_preshow_aft")
	await RoomRender.shot(self, vc, Vector3(-0.785, 1.15, 0.4), Vector3(-0.785, 2.85, -1.6), "dome_preshow_sky_up")

	# 2. Desert twilight departure (lit station platform + terracotta sunset glow + Evening Star + Belt of Venus).
	await RoomRender.shot(self, vc, eye, eye + Vector3(1.0, 0.04, -0.08), "dome_twilight_right")
	RoomRender.set_light(screen, 0.018)
	RoomJourney.step_stage(host, 0.0005)
	await RoomRender.shot(self, vc, eye, screen, "dome_twilight_seat")
	await RoomRender.shot(self, vc, eye, eye + Vector3(-1.0, 0.10, -0.15), "dome_twilight_left")

	# 3. Deep-night Milky Way + shooting star + red-rock mesas + cacti + lit railway water tower!
	RoomJourney.step_stage(host, 0.3467)
	# Frame a crisp shooting star right across the upper dome glass beside the Milky Way!
	var room_node: Node = vc[2]
	var dome_mi := room_node.find_child("SkyDome", true, false) as MeshInstance3D
	if dome_mi != null and dome_mi.material_override is ShaderMaterial:
		var dm := dome_mi.material_override as ShaderMaterial
		dm.set_shader_parameter("meteor_from", Vector4(-0.42, 0.86, -0.28, 0.55))
		dm.set_shader_parameter("meteor_to", Vector3(-0.08, 0.94, -0.32).normalized())
	await RoomRender.shot(self, vc, eye, screen, "dome_night_seat")
	await RoomRender.shot(self, vc, Vector3(-0.785, 1.18, 0.35), Vector3(-1.15, 2.95, -0.95), "dome_night_milkyway_up")
	await RoomRender.shot(self, vc, eye, eye + Vector3(-1.0, 0.14, -0.12), "dome_night_left_tower")
	await RoomRender.shot(self, vc, eye, eye + Vector3(1.0, 0.36, -0.22), "dome_night_right_moon")
	# Also verify Desert coral cove + Constellations live look!
	host.set_setting("cove", "coral")
	host.set_setting("starlight", "constellations")
	for i in 24:
		host.step(0.25)
	await RoomRender.shot(self, vc, Vector3(-0.785, 1.22, 1.6), Vector3(-0.785, 2.35, -3.2), "dome_night_coral_constellations")
	host.set_setting("cove", "turquoise")
	host.set_setting("starlight", "cosmos")
	for i in 24:
		host.step(0.25)

	# 4. Arrival at the desert station under the deep starry cosmos (film.progress = 1.0).
	RoomJourney.step_stage(host, 1.0)
	RoomRender.set_light(screen, 0.05)
	RenderingServer.global_shader_parameter_set("screen_glow", 0.0)
	await RoomRender.shot(self, vc, eye, eye + Vector3(1.0, 0.03, -0.12), "dome_arrival_station")
	await RoomRender.close(self, vc)
