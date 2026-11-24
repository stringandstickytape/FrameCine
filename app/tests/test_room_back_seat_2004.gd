extends "res://tests/env_builder_harness.gd"

## Back seat, 2004 (app/environments/back_seat_2004.env.json; docs/environments/rooms/back_seat_2004.md): the twelfth
## of the Journeys (Road). Built by Gemini 4 Neon Extra High. The cozy, rain-streaked back seat of a 2004 family car
## cruising down a late-night wet motorway: brushed-silver roof-mounted flip-down portable LCD screen, empty slate-grey
## velour front bucket seats framing a glowing 2004 dashboard (ice-blue/emerald dials, amber needles, 3-spoke steering
## wheel, 23:14 stereo clock, illuminated HVAC knobs, leather-booted gearstick), draped tartan wool blanket, travel
## cushions, disc carry-case and headphones, sideways-drifting raindrops on all four car windows, distant sodium
## highway lamps, blue direction gantries, and lit motorway services at departure, mid-way and arrival.
## godot --headless --xr-mode off --path app --script res://tests/test_room_back_seat_2004.gd

const RoomJourney := preload("res://tests/room_journey.gd")
const RoomRender := preload("res://tests/room_render.gd")
const RoomSound := preload("res://tests/room_sound.gd")
const DOC := "res://environments/back_seat_2004.env.json"


func run_tests() -> void:
	test_name = "test_room_back_seat_2004"
	var doc := RoomJourney.load_doc(self, DOC)
	if doc.is_empty():
		return
	var room := await RoomJourney.check_journey(self, "back_seat_2004", doc, "car", "motorway", {
			"min_speed": 5.4, "max_speed": 6.6, "start_landmark": "services", "end_landmark": "services"})
	RoomJourney.check_fittings(self, room, "car", "fittings",
			"the 2004 family car dashboard, front seats, roof LCD pod and parcel shelf", 5)
	check("the stereo digital clock display is built (PieceDisplay)",
			room.find_child("PieceDisplay", true, false) != null)
	check("the backlit dashboard gauges and HVAC rings are built (PieceCove)",
			room.find_child("PieceCove", true, false) != null)
	check("the amber gauge needles and door window switches are built (PieceWindows)",
			room.find_child("PieceWindows", true, false) != null)
	check("the overhead courtesy dome map lights are built (PieceLamps)",
			room.find_child("PieceLamps", true, false) != null)
	var meta: Dictionary = doc.get("room", {})
	check("the room is credited to Gemini 4 Neon Extra High",
			str(meta.get("author", "")) == "Gemini 4 Neon Extra High")
	check("the room description is at most 200 characters (%d)" % str(meta.get("description", "")).length(),
			str(meta.get("description", "")).length() <= 200)
	_weather_and_drift(room)
	_settings(room)
	# Sound: petrol motorway cruise + wet tarmac following journey.speed, rain on car glass following weather.rain,
	# soft wind hush around the roof; vehicle acoustics.
	RoomSound.check_beds(self, "back_seat_2004", room, {
			"engine": "car_motorway", "rain": "rain_glass", "wind": "wind"}, "vehicle")
	RoomJourney.check_speed_bed(self, room, "engine", "the 2004 car engine and wet tarmac", 0.22)
	RoomSound.check_follows(self, "back_seat_2004", room, "rain", "weather.rain")
	RoomJourney.check_figures(self, "back_seat_2004", room, 38, 120000)
	await done(room)
	await RoomSound.check_level(self, self, "back_seat_2004", doc)
	await _render(doc)


## Merged 4-window rain glass drifts sideways aft under way and drips vertically when stopped; falling rain areas stay
## strictly outside the car body with zero inward wind so zero drops enter the cabin.
func _weather_and_drift(room: Node3D) -> void:
	var host: Node = room.host
	var weather: Node = host.system("weather")
	check("merged 4-pane car rain glass built in one draw", weather != null and weather.pane() != null)
	var areas: Array = weather.areas() if weather != null else []
	var wind: Array = weather.params.get("wind", [0.0, 0.0]) if weather != null else [0.0, 0.0]
	var clear_of_cabin := areas.size() == 2 and is_zero_approx(float(wind[0]))
	for a: Array in areas:
		var box: AABB = a[2]
		if box.position.x < 1.4 and box.end.x > -1.4:
			clear_of_cabin = false
	check("falling rain areas stay strictly outside |x| >= 1.4 m with zero crosswind", clear_of_cabin)
	host.timeline.state = ""
	var pos := 600.0
	for i in 48:
		pos += 0.25
		host.snapshot_override = {"open": true, "playing": true, "position": pos, "duration": RoomJourney.FILM}
		host.step(0.25)
	check("raindrops crawl sideways aft at motorway speed (%.2f)" % float(weather.params["pane_drift"]),
			float(weather.params["pane_drift"]) > 1.55)
	host.snapshot_override = {"open": true, "playing": false, "position": pos, "duration": RoomJourney.FILM}
	for i in 120:
		host.step(0.25)
	check("raindrops drip vertically when stopped at services (%.2f)" % float(weather.params["pane_drift"]),
			float(weather.params["pane_drift"]) < 0.1)


## Live settings: Rain (Steady rain / Drizzle / Passing showers / Dry night), Dash glow (Ice blue & amber / Warm
## emerald / Dim), and Car audio (Full cinema / Small screen speaker).
func _settings(room: Node3D) -> void:
	var host: Node = room.host
	var kit: Node = host.system("fittings")
	var pres: Node = host.system("presentation")
	var weather: Node = host.system("weather")
	# Dash glow: starts Ice blue & amber, switches live to Warm emerald and Dim.
	host.step(0.25)
	var st_blue: Dictionary = kit.cove_state()
	var col_blue: Color = st_blue.get("colour", Color.BLACK)
	check("Dash glow starts Ice blue & amber (%s)" % col_blue, not st_blue.is_empty() and col_blue.b > col_blue.r * 2.0)
	host.set_setting("dash_glow", "emerald")
	for i in 12:
		host.step(0.25)
	var st_em: Dictionary = kit.cove_state()
	var col_em: Color = st_em.get("colour", Color.BLACK)
	check("Dash glow=emerald shifts gauges to warm emerald (%s)" % col_em,
			not st_em.is_empty() and col_em.g > col_em.b * 1.4 and col_em.g > col_em.r * 2.0)
	host.set_setting("dash_glow", "dim")
	for i in 12:
		host.step(0.25)
	var st_dim: Dictionary = kit.cove_state()
	check("Dash glow=dim lowers instrument brightness (%.2f < %.2f)" % [float(st_dim.get("glow", 9.0)),
			float(st_blue.get("glow", 0.0))], float(st_dim.get("glow", 9.0)) < float(st_blue.get("glow", 0.0)) * 0.5)
	host.set_setting("dash_glow", "ice_blue")
	for i in 12:
		host.step(0.25)
	# Car audio: switches cleanly between Full cinema and Small screen speaker (telly).
	check("Car audio starts Full cinema (speaker=none)", pres != null and str(pres.value("speaker")) == "none")
	host.set_setting("car_audio", "speaker")
	host.step(0.25)
	check("Car audio=speaker engages small flip-down screen mono speaker (telly)",
			pres != null and str(pres.value("speaker")) == "telly")
	host.set_setting("car_audio", "cinema")
	host.step(0.25)
	# Rain setting: switches live between Steady rain, Drizzle and Dry night.
	host.set_setting("rain", "none")
	for i in 240:
		host.step(0.5)
	check("Rain=none clears the rain (%.2f)" % float(weather.rain_amount()), float(weather.rain_amount()) < 0.05)
	host.set_setting("rain", "drizzle")
	for i in 160:
		host.step(0.5)
	var driz := float(weather.rain_amount())
	check("Rain=drizzle settles at light rain (%.2f)" % driz, driz > 0.2 and driz < 0.45)
	host.set_setting("rain", "rain")
	for i in 160:
		host.step(0.5)
	check("Rain=rain restores steady rain (%.2f)" % float(weather.rain_amount()), float(weather.rain_amount()) > 0.9)


func _render(doc: Dictionary) -> void:
	if not RoomRender.has_renderer():
		print("SKIP render (headless)")
		return
	var sc: Array = doc["screen"]["center"]
	var screen := Vector3(float(sc[0]), float(sc[1]), float(sc[2]))
	RoomRender.set_light(screen, 0.05)
	var vc := await RoomRender.open(self, doc, 86.0)
	var host: Node = (vc[2] as Node).host
	host.signals.fake("film.brightness", 0.65)
	host.signals.fake("playback.playing", 1.0)
	var eye := Vector3(0.0, 1.20, 0.0)

	# 1. Pre-show: parked at departure motorway services, overhead dome lights on, flip-down screen off.
	host.snapshot_override = {"open": false}
	host.set_setting("rain", "rain")
	host.set_setting("dash_glow", "ice_blue")
	for i in 48:
		host.step(0.25)
	RoomRender.set_light(screen, 0.05)
	RenderingServer.global_shader_parameter_set("screen_glow", 0.0)
	await RoomRender.shot(self, vc, eye, Vector3(0.0, 1.05, -1.35), "car_preshow_seat")
	await RoomRender.shot(self, vc, Vector3(0.0, 0.94, -0.42), Vector3(0.16, 0.74, -1.72), "car_preshow_dash")
	await RoomRender.shot(self, vc, Vector3(0.28, 1.10, -0.40), Vector3(-0.52, 0.44, 0.06), "car_preshow_blanket")
	await RoomRender.shot(self, vc, Vector3(0.0, 1.15, -0.78), Vector3(0.0, 0.70, 0.78), "car_preshow_aft")
	await RoomRender.shot(self, vc, eye, eye + Vector3(-1.0, -0.05, -0.10), "car_preshow_left_services")

	# 2. Cruising down the rainy night motorway: flip-down screen ON, dome lights dimmed, dash glowing!
	host.system("presentation").act("switch_on", {})
	RoomRender.set_light(screen, 0.016)
	RoomJourney.step_stage(host, 0.24)
	await RoomRender.shot(self, vc, eye, Vector3(0.0, 1.08, -1.20), "car_cruise_seat")
	await RoomRender.shot(self, vc, eye, eye + Vector3(-1.0, -0.05, -0.18), "car_cruise_left")
	await RoomRender.shot(self, vc, eye, eye + Vector3(1.0, -0.05, -0.18), "car_cruise_right")
	await RoomRender.shot(self, vc, Vector3(0.26, 1.08, -0.38), Vector3(-0.52, 0.44, 0.06), "car_cruise_blanket")

	# 3. Live Dash glow switched to Warm emerald while cruising.
	host.set_setting("dash_glow", "emerald")
	for i in 24:
		host.step(0.25)
	await RoomRender.shot(self, vc, eye, Vector3(0.06, 0.98, -1.30), "car_emerald_seat")
	host.set_setting("dash_glow", "ice_blue")
	for i in 24:
		host.step(0.25)

	# 4. Mid-way motorway services glowing outside the right rain-streaked windows.
	RoomJourney.step_stage(host, 0.50)
	await RoomRender.shot(self, vc, eye, eye + Vector3(1.0, -0.03, -0.08), "car_midway_services")

	# 5. Arrival at destination motorway services: slowed to a stop, raindrops vertical, courtesy lamps up.
	RoomJourney.step_stage(host, 1.0)
	RoomRender.set_light(screen, 0.045)
	await RoomRender.shot(self, vc, eye, eye + Vector3(-1.0, -0.03, -0.08), "car_arrival_left")
	await RoomRender.close(self, vc)
