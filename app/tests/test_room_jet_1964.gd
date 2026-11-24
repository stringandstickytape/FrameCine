extends "res://tests/env_builder_harness.gd"

## Jet 1964 (app/environments/jet_1964.env.json; docs/environments/rooms/jet_1964.md): a glamorous 1964 mid-century
## Jet Age transpolar first-class cabin. Built by Gemini 4 Neon Extra High. Twelve burnt-orange first-class recliners
## with woven ivory antimacassars, flip-up tray tables and dual-hole air-tube headset armrests sit beneath open overhead
## hat-racks, six small high oval fuselage windows per side, a ceiling-mounted 16 mm twin-reel projector aimed at a
## pull-down bulkhead screen, an endless moonlit cloud sea below, 1960s jetport terminals at departure and arrival, and
## shimmering polar aurora blooming outside the oval windows in quiet scenes.
## godot --headless --xr-mode off --path app --script res://tests/test_room_jet_1964.gd

const RoomJourney := preload("res://tests/room_journey.gd")
const RoomRender := preload("res://tests/room_render.gd")
const RoomSound := preload("res://tests/room_sound.gd")
const DOC := "res://environments/jet_1964.env.json"


func run_tests() -> void:
	test_name = "test_room_jet_1964"
	var doc := RoomJourney.load_doc(self, DOC)
	if doc.is_empty():
		return
	var room := await RoomJourney.check_journey(self, "jet_1964", doc, "fuselage", "airway", {
			"min_speed": 4.8, "max_speed": 6.0, "start_landmark": "airport", "end_landmark": "airport"})
	RoomJourney.check_fittings(self, room, "fuselage", "fittings",
			"the 1964 jet screen cassette, ceiling projector, hat-racks and aft bulkhead", 6)
	check("the aft bulkhead cabin clock is built (PieceClock)", room.find_child("PieceClock", true, false) != null)
	check("the glowing 16 mm projector lens aperture is built (PiecePort)",
			room.find_child("PiecePort", true, false) != null)
	check("the backlit amber seatbelt/no-smoking placard is built (PieceWindows)",
			room.find_child("PieceWindows", true, false) != null)
	check("the hat-rack and aisle mood coves are built (PieceCove)",
			room.find_child("PieceCove", true, false) != null)
	check("the 16 mm projection beam haze is built (BeamHaze)",
			room.find_child("BeamHaze", true, false) != null)
	check("the cloud deck ground is built (PassingGround)",
			room.find_child("PassingGround", true, false) != null)
	check("the room is credited to Gemini 4 Neon Extra High",
			str((doc.get("room", {}) as Dictionary).get("author", "")) == "Gemini 4 Neon Extra High")
	var seats: Array[Transform3D] = room.room_seat_transforms()
	var own := seats.any(func(t: Transform3D) -> bool: return t.origin.length() < 0.001)
	check("three rows of four first-class recliners (%d), one at the origin" % seats.size(), seats.size() == 12 and own)
	_aurora_and_settings(room)
	# Sound: jet cabin engines following journey.speed, overhead 16 mm projector following Film print, cabin seatbelt
	# chime on departure and arrival; vehicle acoustics.
	RoomSound.check_beds(self, "jet_1964", room, {"engines": "jet_cabin", "projector": "projector",
			"chime": "cabin_chime"}, "vehicle")
	RoomJourney.check_speed_bed(self, room, "engines", "the jet cabin engines", 0.35)
	RoomSound.check_setting(self, "jet_1964", room, "projector", "picture", "clean", "print")
	RoomJourney.check_figures(self, "jet_1964", room, 38, 120000)
	await done(room)
	await RoomSound.check_level(self, self, "jet_1964", doc)
	await _render(doc)


## Polar aurora blooms in quiet scenes (default), glows steadily on Always, and switches off on Off; live settings for
## Film print, Air-tube headset (window speaker), and Cabin mood coves.
func _aurora_and_settings(room: Node3D) -> void:
	var host: Node = room.host
	var sky: Node = host.system("sky")
	var pres: Node = host.system("presentation")
	var kit: Node = host.system("fittings")
	check("sky system present with high-Arctic aurora", sky != null and float(sky.params["latitude"]) >= 70.0)
	# Default Aurora=quiet: subtle under lively dialogue, swells to 1.0 when film.quiet stays high, then settles back.
	host.timeline.state = ""
	var pos := 600.0
	host.signals.fake("film.quiet", 0.0)
	for i in 24:
		pos += 0.25
		host.snapshot_override = {"open": true, "playing": true, "position": pos, "duration": RoomJourney.FILM}
		host.step(0.25)
	var base_aurora := float(sky.params["aurora"])
	host.signals.fake("film.quiet", 1.0)
	for i in 64:
		pos += 0.25
		host.snapshot_override = {"open": true, "playing": true, "position": pos, "duration": RoomJourney.FILM}
		host.step(0.25)
	var bloom_aurora := float(sky.params["aurora"])
	host.signals.fake("film.quiet", 0.0)
	for i in 64:
		pos += 0.25
		host.snapshot_override = {"open": true, "playing": true, "position": pos, "duration": RoomJourney.FILM}
		host.step(0.25)
	var settled_aurora := float(sky.params["aurora"])
	host.signals.clear_fakes()
	check("Aurora=quiet blooms in quiet scenes and settles (%.2f -> %.2f -> %.2f)" % [
			base_aurora, bloom_aurora, settled_aurora],
			base_aurora < 0.35 and bloom_aurora > 0.92 and settled_aurora < 0.35)
	# Aurora=always and Aurora=off.
	host.set_setting("aurora", "always")
	host.step(0.25)
	check("Aurora=always glows steadily (%.2f)" % float(sky.params["aurora"]), float(sky.params["aurora"]) > 0.85)
	host.set_setting("aurora", "off")
	host.step(0.25)
	check("Aurora=off hides the aurora (%.2f)" % float(sky.params["aurora"]), float(sky.params["aurora"]) < 0.01)
	host.set_setting("aurora", "quiet")
	host.step(0.25)

	# Film print (16 mm worn_print vs clean) and Air-tube headset (window speaker).
	check("presentation starts on 16 mm print (worn_print, film)", pres != null
			and str(pres.value("preset")) == "worn_print" and str(pres.value("source")) == "film")
	host.set_setting("picture", "clean")
	host.step(0.25)
	check("Film print=clean switches off film stage", str(pres.value("source")) == "none")
	host.set_setting("picture", "print")
	host.set_setting("headset", true)
	host.step(0.25)
	check("Air-tube headset toggle engages tinny window speaker", str(pres.value("speaker")) == "window")
	host.set_setting("headset", false)
	host.step(0.25)
	check("Air-tube headset off restores clean audio", str(pres.value("speaker")) == "none")

	# Cabin mood coves (Warm ivory / Polar blue / Off).
	host.set_setting("mood", "polar")
	for i in 8:
		host.step(0.25)
	var st_polar: Dictionary = kit.cove_state()
	var c_polar: Color = st_polar.get("colour", Color.BLACK)
	check("Cabin mood=polar shifts hat-rack & aisle coves blue (%s)" % c_polar,
			not st_polar.is_empty() and c_polar.b > c_polar.r * 2.0)
	host.set_setting("mood", "off")
	for i in 8:
		host.step(0.25)
	var st_off: Dictionary = kit.cove_state()
	check("Cabin mood=off switches coves off (%.2f)" % float(st_off.get("glow", 1.0)),
			float(st_off.get("glow", 1.0)) < 0.01)
	host.set_setting("mood", "warm")
	for i in 8:
		host.step(0.25)


func _render(doc: Dictionary) -> void:
	if not RoomRender.has_renderer():
		print("SKIP render (headless)")
		return
	var sc: Array = doc["screen"]["center"]
	var screen := Vector3(float(sc[0]), float(sc[1]), float(sc[2]))
	var vc := await RoomRender.open(self, doc)
	var host: Node = (vc[2] as Node).host
	var eye := Vector3(0.0, 1.2, 0.0)

	# 1. Pre-show at the departure jetport gate (`travel == 0.0`): warm cabin lights up, screen off, zero screen glow.
	host.snapshot_override = {"open": false}
	host.signals.fake("playback.playing", 0.0)
	for i in 48:
		host.step(0.25)
	RoomRender.set_light(screen, 0.05)
	RenderingServer.global_shader_parameter_set("screen_glow", 0.0)
	await RoomRender.shot(self, vc, Vector3(-0.7, 1.56, 2.75), Vector3(-0.7, 1.66, -4.02), "jet_preshow_cabin")
	await RoomRender.shot(self, vc, Vector3(0.08, 1.86, -0.05), Vector3(-0.62, 2.22, -0.98), "jet_preshow_projector")
	await RoomRender.shot(self, vc, Vector3(-0.04, 1.18, 0.32), Vector3(0.18, 0.56, -0.42), "jet_preshow_armrest")
	await RoomRender.shot(self, vc, Vector3(-0.7, 1.52, -2.5), Vector3(-0.7, 1.48, 3.2), "jet_preshow_aft")
	# Parked right at the departure 1960s mid-century jetport gate (concourse, jetway, blue taxiway lights, ATC tower).
	await RoomRender.shot(self, vc, Vector3(0.56, 1.24, 0.0), Vector3(24.0, 2.2, -5.0), "jet_gate_window_right")
	await RoomRender.shot(self, vc, Vector3(2.8, 4.8, 1.5), Vector3(28.0, 5.5, -5.0), "jet_gate_airport_ext")

	# 2. Departure roll & lights dimming, 16 mm beam switching on.
	host.system("presentation").act("switch_on", {})
	host.signals.fake("film.brightness", 0.65)
	host.signals.fake("playback.playing", 1.0)
	RoomRender.set_light(screen, 0.018)
	host.snapshot_override = {"open": true, "playing": true, "position": 4.0, "duration": RoomJourney.FILM}
	for i in 24:
		host.step(0.25)
	await RoomRender.shot(self, vc, eye, screen, "jet_gate_seat")

	# 3. High-altitude transpolar polar-night cruise: quiet scene blooms shimmering emerald & violet Aurora Borealis
	# outside the starboard oval windows over the moonlit cloud sea below!
	host.signals.fake("film.quiet", 1.0)
	RoomJourney.step_stage(host, 0.48)
	for i in 64:
		host.step(0.25)
	await RoomRender.shot(self, vc, eye, screen, "jet_cruise_seat")
	await RoomRender.shot(self, vc, Vector3(0.56, 1.25, 0.0), Vector3(18.0, 3.8, -1.6), "jet_cruise_aurora_window")
	await RoomRender.shot(self, vc, eye, Vector3(12.0, 2.6, -1.2), "jet_cruise_aurora_aisle")
	await RoomRender.shot(self, vc, Vector3(-1.96, 1.25, 0.0), Vector3(-18.0, 2.2, -1.0), "jet_cruise_moon_port")
	await RoomRender.shot(self, vc, Vector3(3.0, 4.5, 0.0), Vector3(45.0, 5.5, -4.0), "jet_cruise_aurora_ext")
	# Polar blue cabin mood variant mid-flight.
	host.set_setting("mood", "polar")
	for i in 12:
		host.step(0.25)
	await RoomRender.shot(self, vc, Vector3(-0.7, 1.56, 2.75), Vector3(-0.7, 1.66, -4.02), "jet_cruise_polar_mood")
	host.set_setting("mood", "warm")

	# 4. Arrival at destination 1960s jetport terminal with lights coming up.
	host.signals.fake("film.quiet", 0.0)
	RoomJourney.step_stage(host, 1.0)
	RoomRender.set_light(screen, 0.04)
	await RoomRender.shot(self, vc, Vector3(0.56, 1.24, 0.0), Vector3(24.0, 2.2, -5.0), "jet_arrival_window")
	await RoomRender.close(self, vc)
