extends "res://tests/env_builder_harness.gd"

## Night ferry 1994 (app/environments/night_ferry_1994.env.json; docs/environments/rooms/night_ferry_1994.md): the
## fourth of the Journeys. Built by Gemini 4 Neon Extra High. A 1994 cross-Channel passenger ferry's video lounge:
## Pullman recliners with antimacassars and tray tables under a ceiling-bracketed 1994 CRT television and locked VCR
## cage, salt-streaked storm windows with wind-driven rain, a slow volumetric lighthouse beam sweeping across the dark
## sea, passing container freighters, and floodlit Ro-Ro ferry ports at departure and arrival.
## godot --headless --xr-mode off --path app --script res://tests/test_room_night_ferry_1994.gd

const RoomJourney := preload("res://tests/room_journey.gd")
const RoomRender := preload("res://tests/room_render.gd")
const RoomSound := preload("res://tests/room_sound.gd")
const DOC := "res://environments/night_ferry_1994.env.json"


func run_tests() -> void:
	test_name = "test_room_night_ferry_1994"
	var doc := RoomJourney.load_doc(self, DOC)
	if doc.is_empty():
		return
	var room := await RoomJourney.check_journey(self, "night_ferry_1994", doc, "lounge", "channel", {
			"min_speed": 3.5, "max_speed": 4.6, "start_landmark": "ferry_port", "end_landmark": "ferry_port"})
	RoomJourney.check_fittings(self, room, "lounge", "fittings", "the ferry lounge CRT rig, tables and fire cabinet", 4)
	check("the aft bulkhead clock is built (PieceClock)", room.find_child("PieceClock", true, false) != null)
	check("the VCR clock display is built (PieceDisplay)", room.find_child("PieceDisplay", true, false) != null)
	check("the volumetric lighthouse beam is built (PassingBeams)",
			room.find_child("PassingBeams", true, false) != null)
	check("the room is credited to Gemini 4 Neon Extra High",
			str((doc.get("room", {}) as Dictionary).get("author", "")) == "Gemini 4 Neon Extra High")
	var seats: Array[Transform3D] = room.room_seat_transforms()
	var own := seats.any(func(t: Transform3D) -> bool: return t.origin.length() < 0.001)
	check("three rows of four Pullman recliners (%d), one at the origin" % seats.size(), seats.size() == 12 and own)
	_weather_and_beam(room)
	_settings(room)
	# Sound: twin marine diesels following journey.speed, heavy hull wash, rain on storm panes, hull creaks, VCR,
	# CRT flyback whine, PA departure chime and ship's horn; hull acoustics.
	RoomSound.check_beds(self, "night_ferry_1994", room, {"engines": "ferry_diesel", "sea_wash": "water_lap",
			"rain": "rain_glass", "creak": "hull_creak", "vcr": "vcr", "whine": "tube_whine",
			"chime": "ferry_chime", "horn": "ship_horn"}, "hull")
	RoomJourney.check_speed_bed(self, room, "engines", "the ferry diesels", 0.35)
	RoomJourney.check_figures(self, "night_ferry_1994", room, 38, 120000)
	await done(room)
	await RoomSound.check_level(self, self, "night_ferry_1994", doc)
	await _render(doc)


## Multi-pane salt-streaked rain glass drifts aft under way and settles vertically in port; the lighthouse beam turns.
func _weather_and_beam(room: Node3D) -> void:
	var host: Node = room.host
	var weather: Node = host.system("weather")
	var channel: Node = host.system("channel")
	check("merged multi-pane rain glass built in one draw", weather != null and weather.pane() != null)
	var bmat: ShaderMaterial = channel.material_of("PassingBeams")
	check("lighthouse beam shader compiled and attached", bmat != null)
	host.timeline.state = ""
	var pos := 600.0
	var p0 := float(bmat.get_shader_parameter("beam_phase")) if bmat != null else 0.0
	for i in 40:
		pos += 0.25
		host.snapshot_override = {"open": true, "playing": true, "position": pos, "duration": RoomJourney.FILM}
		host.step(0.25)
	var p1 := float(bmat.get_shader_parameter("beam_phase")) if bmat != null else 0.0
	check("lighthouse beam rotates slowly over time (%.2f -> %.2f rad)" % [p0, p1],
			bmat != null and not is_equal_approx(p0, p1))
	check("rain streaks drift aft at sea (%.2f)" % float(weather.params["pane_drift"]),
			float(weather.params["pane_drift"]) > 1.1)
	host.snapshot_override = {"open": true, "playing": false, "position": pos, "duration": RoomJourney.FILM}
	for i in 120:
		host.step(0.25)
	check("rain drips vertically when berthed (%.2f)" % float(weather.params["pane_drift"]),
			float(weather.params["pane_drift"]) < 0.1)


## Live settings: Picture (VHS / CRT / Clean), Telly speaker, Night strips, and Weather at sea.
func _settings(room: Node3D) -> void:
	var host: Node = room.host
	var pres: Node = host.system("presentation")
	var kit: Node = host.system("fittings")
	check("presentation starts on 1994 CRT & tape (nightowl_1993, tape)", pres != null
			and str(pres.value("preset")) == "nightowl_1993" and str(pres.value("source")) == "tape")
	host.set_setting("picture", "crt")
	host.step(0.25)
	check("picture=crt keeps CRT display with clean source",
			str(pres.value("display")) == "crt" and str(pres.value("source")) == "none")
	host.set_setting("picture", "clean")
	host.step(0.25)
	check("picture=clean switches off CRT and tape stages",
			str(pres.value("display")) == "none" and str(pres.value("source")) == "none")
	host.set_setting("picture", "tape")
	host.set_setting("speaker", true)
	host.step(0.25)
	check("Telly speaker toggle engages mono telly speaker", str(pres.value("speaker")) == "telly")
	host.set_setting("speaker", false)
	host.set_setting("night_strips", "teal")
	for i in 12:
		host.step(0.25)
	var st: Dictionary = kit.cove_state()
	var col: Color = st.get("colour", Color.BLACK)
	check("Night strips=teal moves aisle and pelmet coves (%s)" % col, not st.is_empty() and col.g > col.r * 2.0)
	host.set_setting("night_strips", "amber")
	for i in 12:
		host.step(0.25)


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
	# Pre-show: bright fluorescent panels, berthed at departure Ro-Ro ferry port, CRT off before the show.
	host.snapshot_override = {"open": false}
	host.set_setting("weather", "rain")
	for i in 48:
		host.step(0.25)
	RoomRender.set_light(screen, 0.05)
	RenderingServer.global_shader_parameter_set("screen_glow", 0.0)
	await RoomRender.shot(self, vc, Vector3(-0.91, 1.68, 2.5), screen, "ferry_preshow_back")
	await RoomRender.shot(self, vc, Vector3(-0.91, 1.62, -2.4), Vector3(-0.91, 1.68, 2.85), "ferry_preshow_aft")
	await RoomRender.shot(self, vc, Vector3(-0.91, 1.75, -0.7), Vector3(-0.91, 1.98, -3.5), "ferry_preshow_crt")
	# Switch CRT on and step through five crossing stages: port departure, headland lighthouse & beam, mid-Channel
	# freighter & Moon in rain, starboard arrival lighthouse, and arrival Ro-Ro ferry terminal.
	host.system("presentation").act("switch_on", {})
	RoomRender.set_light(screen, 0.018)
	for stage: Array in [["port", 0.0005], ["lighthouse", 0.0033], ["channel", 0.3585], ["approach", 0.9965],
			["arrival", 1.0]]:
		RoomJourney.step_stage(host, float(stage[1]))
		var n := str(stage[0])
		await RoomRender.shot(self, vc, eye, screen, "ferry_%s_seat" % n)
		await RoomRender.shot(self, vc, eye, eye + Vector3(-1.0, 0.04, -0.22), "ferry_%s_left" % n)
		await RoomRender.shot(self, vc, eye, eye + Vector3(1.0, 0.04, -0.22), "ferry_%s_right" % n)
		await RoomRender.shot(self, vc, Vector3(-0.91, 3.8, 0.0), Vector3(-70.0, 1.8, -16.0), "ferry_%s_port" % n)
		await RoomRender.shot(self, vc, Vector3(-0.91, 3.8, 0.0), Vector3(70.0, 1.8, -16.0), "ferry_%s_starboard" % n)
	await RoomRender.close(self, vc)
