extends "res://tests/env_builder_harness.gd"

## Coach trip, 1988 (app/environments/coach_trip_1988.env.json; docs/environments/rooms/coach_trip_1988.md): the
## eleventh of the Journeys (Road). Built by Gemini 4 Neon Extra High. An overnight 1988 express touring coach rolling
## down a sodium-lit British/European night motorway: swirly 1988 moquette, five rows of warm brown-terracotta
## recliners with linen antimacassars, moulded armrests and seatback trays, a ceiling-mounted 4:3 CRT television above
## a flashing 12:00 video deck and stacked rental tape cases, a drawn burgundy driver's curtain, continuous overhead
## parcel racks with passenger service pods, and glowing motorway services at departure, intermission and arrival.
## godot --headless --xr-mode off --path app --script res://tests/test_room_coach_trip_1988.gd

const RoomJourney := preload("res://tests/room_journey.gd")
const RoomRender := preload("res://tests/room_render.gd")
const RoomSound := preload("res://tests/room_sound.gd")
const DOC := "res://environments/coach_trip_1988.env.json"


func run_tests() -> void:
	test_name = "test_room_coach_trip_1988"
	var doc := RoomJourney.load_doc(self, DOC)
	if doc.is_empty():
		return
	var room := await RoomJourney.check_journey(self, "coach_trip_1988", doc, "coach", "motorway", {
			"min_speed": 5.8, "max_speed": 6.4, "start_landmark": "services", "end_landmark": "services"})
	RoomJourney.check_fittings(self, room, "coach", "fittings", "the 1988 coach CRT rig and stairwell modesty panels", 3)
	check("the aft bulkhead quartz clock is built (PieceClock)", room.find_child("PieceClock", true, false) != null)
	check("the video recorder clock display is built (PieceDisplay)",
			room.find_child("PieceDisplay", true, false) != null)
	check("the break-glass emergency hammer glass is built (PieceGlass)",
			room.find_child("PieceGlass", true, false) != null)
	check("the room is credited to Gemini 4 Neon Extra High",
			str((doc.get("room", {}) as Dictionary).get("author", "")) == "Gemini 4 Neon Extra High")
	var seats: Array[Transform3D] = room.room_seat_transforms()
	var own := seats.any(func(t: Transform3D) -> bool: return t.origin.length() < 0.001)
	check("five rows of four 1988 coach recliners (%d), one at the origin" % seats.size(), seats.size() == 20 and own)
	clock_flashes("coach_trip_1988", room)
	_intermission_and_weather(room)
	_settings(room)
	# Sound: rear underfloor coach diesel following journey.speed, video deck loader, subtle CRT flyback whine,
	# motorway drizzle on glass, and soft motorway slipstream; vehicle acoustics.
	RoomSound.check_beds(self, "coach_trip_1988", room, {"engines": "coach_diesel", "vcr": "vcr",
			"whine": "tube_whine", "rain": "rain_glass", "wind": "wind"}, "vehicle")
	RoomJourney.check_speed_bed(self, room, "engines", "the coach diesel", 0.32)
	RoomJourney.check_figures(self, "coach_trip_1988", room, 38, 120000)
	await done(room)
	await RoomSound.check_level(self, self, "coach_trip_1988", doc)
	await _render(doc)


## Intermission smoothly brakes the coach to a complete halt at the motorway services, brings up warm courtesy lamps
## and idles the diesel; resuming playback dims the lights back down and accelerates back to motorway cruise.
func _intermission_and_weather(room: Node3D) -> void:
	var host: Node = room.host
	var way: Node = host.system("motorway")
	var weather: Node = host.system("weather")
	var engines: Node = host.system("engines")
	check("merged 10-pane rain glass built in one draw", weather != null and weather.pane() != null)
	# Establish full motorway cruise mid-journey (~0.5).
	host.timeline.state = ""
	var pos := RoomJourney.FILM * 0.495
	for i in 120:
		pos += 0.25
		host.snapshot_override = {"open": true, "playing": true, "position": pos, "duration": RoomJourney.FILM}
		host.step(0.25)
	var cruise_speed := float(way.speed_now)
	var cruise_lamps := float(host.param("light.house_lamps"))
	var cruise_drift := float(weather.params["pane_drift"])
	check("cruising on the night motorway (%.2f m/s, lamps %.2f, drift %.2f)" % [cruise_speed, cruise_lamps,
			cruise_drift], cruise_speed > 5.5 and cruise_lamps < 0.2 and cruise_drift > 1.3)
	# Enter intermission: coach brakes smoothly to 0.0 m/s, courtesy lamps rise to ~0.55, diesel settles to idle,
	# rain streaks slow to vertical drips on the glass.
	for i in 120:
		host.snapshot_override = {"open": true, "playing": false, "intermission": true, "position": pos,
				"duration": RoomJourney.FILM}
		host.step(0.25)
	var stop_speed := float(way.speed_now)
	var stop_lamps := float(host.param("light.house_lamps"))
	var stop_eng := float(engines.params["level"])
	var stop_drift := float(weather.params["pane_drift"])
	check("intermission brakes smoothly to a halt (%.2f m/s), courtesy lamps up (%.2f), diesel idle (%.2f), rain vertical (%.2f)"
			% [stop_speed, stop_lamps, stop_eng, stop_drift],
			stop_speed == 0.0 and stop_lamps > 0.48 and stop_lamps < 0.65
			and absf(stop_eng - 0.32) <= 0.05 and stop_drift < 0.1)
	# Resume playback: coach accelerates cleanly back to cruise speed and lamps dim back down.
	for i in 120:
		pos += 0.25
		host.snapshot_override = {"open": true, "playing": true, "intermission": false, "position": pos,
				"duration": RoomJourney.FILM}
		host.step(0.25)
	var resume_speed := float(way.speed_now)
	var resume_lamps := float(host.param("light.house_lamps"))
	check("resuming from intermission accelerates back to cruise (%.2f m/s) and dims cabin (%.2f)" % [resume_speed,
			resume_lamps], resume_speed > 5.5 and resume_lamps < 0.18)


## Live settings: Tape wear (1988 rental tape / 1988 CRT / Clean), Coach speaker, Night strips, and Motorway weather.
func _settings(room: Node3D) -> void:
	var host: Node = room.host
	var pres: Node = host.system("presentation")
	var kit: Node = host.system("fittings")
	check("presentation starts on 1988 rental tape (rewinder_1987, tape)", pres != null
			and str(pres.value("preset")) == "rewinder_1987" and str(pres.value("source")) == "tape")
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
	check("Coach speaker toggle engages mono telly speaker", str(pres.value("speaker")) == "telly")
	host.set_setting("speaker", false)
	host.set_setting("night_strips", "teal")
	for i in 12:
		host.step(0.25)
	var st: Dictionary = kit.cove_state()
	var col: Color = st.get("colour", Color.BLACK)
	check("Night strips=teal shifts floor and luggage-rack coves (%s)" % col,
			not st.is_empty() and col.g > col.r * 2.0)
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
	# Pre-show: bright warm overhead fluorescent troughs, parked at departure services, CRT off.
	# Step 49 x 0.25 s (12.25 s) so the flashing 12:00 video-deck display is at peak brightness for the close-up.
	host.snapshot_override = {"open": false}
	host.set_setting("weather", "light")
	for i in 49:
		host.step(0.25)
	RoomRender.set_light(screen, 0.05)
	RenderingServer.global_shader_parameter_set("screen_glow", 0.0)
	await RoomRender.shot(self, vc, Vector3(-0.45, 1.55, 2.75), Vector3(-0.45, 1.45, -3.95), "coach_preshow_cabin")
	await RoomRender.shot(self, vc, Vector3(-0.45, 1.58, -1.55), Vector3(-0.45, 1.72, -4.05), "coach_preshow_crt")
	await RoomRender.shot(self, vc, Vector3(-0.45, 1.45, -1.8), Vector3(-0.45, 1.45, 3.4), "coach_preshow_aft")
	# Switch CRT on and step through key motorway stages: departure services, night motorway cruise with sodium
	# lamps & gantries, intermission stop halted right alongside the glowing twin motorway services, and arrival.
	host.system("presentation").act("switch_on", {})
	RoomRender.set_light(screen, 0.018)
	# 1. Departure: just pulling out past the glowing departure motorway services (travel ~ 0..6 m)
	host.snapshot_override = {"open": true, "playing": true, "position": 0.0, "duration": RoomJourney.FILM}
	host.signals.fake("film.progress", 0.0)
	host.signals.fake("film.minutes", 0.0)
	for i in 12:
		host.step(0.25)
	await RoomRender.shot(self, vc, eye, screen, "coach_depart_seat")
	await RoomRender.shot(self, vc, eye, eye + Vector3(1.0, 0.06, -0.15), "coach_depart_right")
	# 2. Night motorway cruise (sodium lamps, blue gantry, crescent Moon & clouds)
	RoomJourney.step_stage(host, 0.24)
	await RoomRender.shot(self, vc, eye, screen, "coach_cruise_seat")
	await RoomRender.shot(self, vc, eye, eye + Vector3(-1.0, 0.08, -0.22), "coach_cruise_left")
	await RoomRender.shot(self, vc, eye, eye + Vector3(1.0, 0.06, -0.18), "coach_cruise_right")
	# 3. Intermission stop at glowing twin mid-route motorway services (approach, brake smoothly to 0.0 m/s dead
	# abreast of at: 0.5 services, warm courtesy lamps risen to 0.55!)
	var way: Node = host.system("motorway")
	var mid_frac := 0.4945
	RoomJourney.step_stage(host, mid_frac)
	var mid_pos := mid_frac * RoomJourney.FILM
	for i in 100:
		host.snapshot_override = {"open": true, "playing": false, "intermission": true, "position": mid_pos,
				"duration": RoomJourney.FILM}
		host.step(0.25)
	# Align stopped coach squarely beside the twin mid-route motorway services forecourt (travel == 0.5 * route).
	way.travel = way.route_length() * 0.5
	host.step(0.05)
	RoomRender.set_light(screen, 0.032)
	await RoomRender.shot(self, vc, eye, screen, "coach_intermission_seat")
	await RoomRender.shot(self, vc, eye, eye + Vector3(1.0, 0.08, -0.12), "coach_intermission_services")
	await RoomRender.shot(self, vc, eye, eye + Vector3(-1.0, 0.08, -0.12), "coach_intermission_left")
	# 4. Arrival at destination motorway services
	RoomRender.set_light(screen, 0.018)
	RoomJourney.step_stage(host, 1.0)
	await RoomRender.shot(self, vc, eye, screen, "coach_arrival_seat")
	await RoomRender.shot(self, vc, eye, eye + Vector3(1.0, 0.08, -0.12), "coach_arrival_right")
	await RoomRender.close(self, vc)
