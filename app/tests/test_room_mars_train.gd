extends "res://tests/env_builder_harness.gd"

## Mars train (app/environments/mars_train.env.json; docs/environments/rooms/mars_train.md): a rugged, warm-lit
## pressurised Martian rover-train crossing a rust-ochre plain under the real haunting blue Martian sunset, past
## whirling dust devils and basalt mesas, arriving at a glowing domed Martian night colony.
## Built by Gemini 4 Neon Extra High.
## godot --headless --xr-mode off --path app --script res://tests/test_room_mars_train.gd

const RoomJourney := preload("res://tests/room_journey.gd")
const RoomRender := preload("res://tests/room_render.gd")
const RoomSound := preload("res://tests/room_sound.gd")
const DOC := "res://environments/mars_train.env.json"


func run_tests() -> void:
	test_name = "test_room_mars_train"
	var doc := RoomJourney.load_doc(self, DOC)
	if doc.is_empty():
		return
	var room := await RoomJourney.check_journey(self, "mars_train", doc, "rover", "plain", {
			"min_speed": 4.8, "max_speed": 5.4, "start_landmark": "mars_base", "end_landmark": "mars_base"})
	RoomJourney.check_fittings(self, room, "rover", "fittings",
			"the Mars train console, ledges, aft lockers and pressure airlock", 6)
	check("the Martian Sol chronometer is built (PieceClock)", room.find_child("PieceClock", true, false) != null)
	check("the cabin cove strips and aisle deck guides are built (PieceCove)",
			room.find_child("PieceCove", true, false) != null)
	check("the expedition LED troughs and telemetry amber indicators are built (PieceLamps)",
			room.find_child("PieceLamps", true, false) != null)
	check("the airlock pressure-green & forward telemetry displays are built (PieceWindows)",
			room.find_child("PieceWindows", true, false) != null)
	check("the sample canister containment sleeves are built (PieceGlass)",
			room.find_child("PieceGlass", true, false) != null)
	check("the triple-glazed pressure windows are built (Glass)", room.find_child("Glass", true, false) != null)
	var meta: Dictionary = doc.get("room", {})
	check("the room is credited to Gemini 4 Neon Extra High", str(meta.get("author", "")) == "Gemini 4 Neon Extra High")
	check("the room description is at most 200 characters (%d)" % str(meta.get("description", "")).length(),
			str(meta.get("description", "")).length() <= 200)
	var seats: Array[Transform3D] = room.room_seat_transforms()
	var own := seats.any(func(t: Transform3D) -> bool: return t.origin.length() < 0.001)
	check("three rows of four technical recliners (%d), one at the origin" % seats.size(), seats.size() == 12 and own)
	_sky_and_settings(room)
	# Sound: electric-bogie traction hum + regolith roll bound to journey.speed, thin-air Martian wind around the hull,
	# airlock cabin chime on departure & arrival; hull acoustics.
	RoomSound.check_beds(self, "mars_train", room, {"drive": "rover_drive", "wind": "wind", "chime": "cabin_chime"},
			"hull")
	RoomJourney.check_speed_bed(self, room, "drive", "the rover drive", 0.0)
	var stats := RoomJourney.check_figures(self, "mars_train", room, 38, 120000)
	check("texture memory within 80 MB (%.1f MB)" % float(stats["texture_mb"]), float(stats["texture_mb"]) <= 80.0)
	await done(room)
	await RoomSound.check_level(self, self, "mars_train", doc)
	await _render(doc)


## Authentic blue Martian sunset sets into clear Martian starlight; Cabin lighting & Martian sky settings work live.
func _sky_and_settings(room: Node3D) -> void:
	var host: Node = room.host
	var sky: Node = host.system("sky")
	var kit: Node = host.system("fittings")
	# Reset to pre-show sunset baseline (check_journey stepped to film end).
	RoomJourney.step_stage(host, 0.0)
	check("sky starts at blue Martian sunset (dusk %.2f, sun_alt %.1f, sun_disc %.2f, faint_stars %d)" % [
			float(sky.params["dusk"]), float(sky.params["sun_altitude"]), float(sky.params["sun_disc"]),
			int(sky.params["faint_stars"])],
			sky != null and float(sky.params["dusk"]) < 0.05
			and absf(float(sky.params["sun_altitude"]) - 7.5) < 0.2
			and float(sky.params["sun_disc"]) > 0.95
			and int(sky.params["faint_stars"]) == 3000
			and float(sky.params["milky_detail"]) >= 0.99)
	RoomJourney.step_stage(host, 0.16)
	check("setting Sun sinks mid-sunset while disc stays visible (sun_alt %.1f, sun_disc %.2f)" % [
			float(sky.params["sun_altitude"]), float(sky.params["sun_disc"])],
			float(sky.params["sun_altitude"]) > 1.0 and float(sky.params["sun_altitude"]) < 5.0
			and float(sky.params["sun_disc"]) > 0.85)
	RoomJourney.step_stage(host, 0.36)
	check("Sun has set and Martian night starlight rules by 36%% (sun_alt %.1f, sun_disc %.2f, dusk %.2f)" % [
			float(sky.params["sun_altitude"]), float(sky.params["sun_disc"]), float(sky.params["dusk"])],
			float(sky.params["sun_altitude"]) < -2.5 and float(sky.params["sun_disc"]) < 0.05
			and float(sky.params["dusk"]) > 0.98)

	# Cabin lighting setting: Habitat amber / Telemetry teal / Off.
	host.set_setting("lighting", "teal")
	for i in 12:
		host.step(0.25)
	var st_teal: Dictionary = kit.cove_state()
	var col_teal: Color = st_teal.get("colour", Color.BLACK)
	check("Cabin lighting=teal shifts raceway & aisle coves to telemetry teal (%s)" % col_teal,
			not st_teal.is_empty() and col_teal.g > col_teal.r * 2.0 and col_teal.b > col_teal.r * 2.0)
	host.set_setting("lighting", "off")
	for i in 12:
		host.step(0.25)
	check("Cabin lighting=off dims cove strips to zero (%.2f)" % float(kit.cove_state().get("glow", 1.0)),
			float(kit.cove_state().get("glow", 1.0)) < 0.01)
	host.set_setting("lighting", "amber")
	for i in 12:
		host.step(0.25)
	var st_amb: Dictionary = kit.cove_state()
	var col_amb: Color = st_amb.get("colour", Color.BLACK)
	check("Cabin lighting=amber restores habitat amber glow (%s)" % col_amb,
			not st_amb.is_empty() and col_amb.r > col_amb.b * 2.0)

	# Martian sky setting: Blue sunset to stars / Clear starlight / Constellations.
	host.set_setting("sky_mode", "starlight")
	for i in 24:
		host.step(0.25)
	check("Martian sky=starlight raises Milky Way (%.2f) with lines off (%.2f)" % [
			float(sky.params["milky_way"]), float(sky.params["lines"])],
			float(sky.params["milky_way"]) > 0.9 and float(sky.params["lines"]) < 0.05)
	host.set_setting("sky_mode", "constellations")
	for i in 24:
		host.step(0.25)
	check("Martian sky=constellations raises constellation lines (%.2f) and builds SkyLines" % float(sky.params["lines"]),
			float(sky.params["lines"]) > 0.5 and room.find_child("SkyLines", true, false) != null)
	host.set_setting("sky_mode", "sunset")
	for i in 24:
		host.step(0.25)
	check("Martian sky=sunset restores default Milky Way (%.2f) and clears lines (%.2f)" % [
			float(sky.params["milky_way"]), float(sky.params["lines"])],
			absf(float(sky.params["milky_way"]) - 0.85) < 0.08 and float(sky.params["lines"]) < 0.05)


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

	# 1. Pre-show: full habitat amber coves & expedition LED ceiling troughs, docked at departure Martian outpost
	#    under the real blue Martian sunset (screen_glow = 0).
	host.snapshot_override = {"open": false}
	for i in 48:
		host.step(0.25)
	RoomRender.set_light(screen, 0.05)
	RenderingServer.global_shader_parameter_set("screen_glow", 0.0)
	await RoomRender.shot(self, vc, Vector3(-0.72, 1.62, 2.48), screen, "mars_preshow_front")
	await RoomRender.shot(self, vc, Vector3(-0.72, 1.48, -1.85), Vector3(-0.72, 1.32, 3.4), "mars_preshow_aft")
	await RoomRender.shot(self, vc, Vector3(-0.62, 1.38, 2.10), Vector3(1.15, 1.16, 2.96), "mars_preshow_samples")
	await RoomRender.shot(self, vc, Vector3(-0.82, 1.38, 2.10), Vector3(-2.55, 1.24, 2.96), "mars_preshow_geology")

	# 2. Authentic Blue Martian Sunset: small crisp Sun disc & pale ice-blue halo out the thick triple-glazed starboard
	#    pressure window over the rust-ochre plain, basalt ventifacts, mesas & whirling ochre dust devils!
	await RoomRender.shot(self, vc, eye, eye + Vector3(0.985, 0.08, -0.174), "mars_sunset_right")
	await RoomRender.shot(self, vc, eye, eye + Vector3(-1.0, 0.05, -0.05), "mars_departure_left")
	RoomRender.set_light(screen, 0.018)
	RoomJourney.step_stage(host, 0.02)
	await RoomRender.shot(self, vc, eye, screen, "mars_sunset_seat")

	# 3. Low setting Martian Sun kissing the distant mesas & dust devils (film.progress = 0.16).
	RoomJourney.step_stage(host, 0.16)
	await RoomRender.shot(self, vc, eye, eye + Vector3(0.985, 0.06, -0.174), "mars_sunset_low_right")

	# 4. Deep Martian night starlight plain: crystal-clear Milky Way, 3000 stars, rust plain & basalt rocks (0.55).
	RoomJourney.step_stage(host, 0.55)
	await RoomRender.shot(self, vc, eye, eye + Vector3(0.98, 0.14, -0.18), "mars_night_right")
	await RoomRender.shot(self, vc, eye, screen, "mars_night_seat")
	# Also verify live Telemetry teal cabin lighting + Constellations sky mode!
	host.set_setting("lighting", "teal")
	host.set_setting("sky_mode", "constellations")
	for i in 24:
		host.step(0.25)
	await RoomRender.shot(self, vc, Vector3(-0.72, 1.54, 2.35), Vector3(-0.25, 1.75, -3.5), "mars_teal_constellations")
	host.set_setting("lighting", "amber")
	host.set_setting("sky_mode", "sunset")
	for i in 24:
		host.step(0.25)

	# 5. Arrival at the glowing domed Martian night colony with the credits (film.progress = 1.0)!
	RoomJourney.step_stage(host, 1.0)
	RoomRender.set_light(screen, 0.05)
	RenderingServer.global_shader_parameter_set("screen_glow", 0.0)
	await RoomRender.shot(self, vc, eye, eye + Vector3(1.0, 0.07, -0.06), "mars_arrival_colony")
	await RoomRender.close(self, vc)
