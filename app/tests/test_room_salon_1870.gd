extends "res://tests/env_builder_harness.gd"

## The Salon, 1870 (app/environments/salon_1870.env.json; docs/environments/rooms/salon_1870.md): Victorian 1870
## submarine velvet salon in the Journeys arc (Water). Built by Gemini 4 Neon Extra High. Riveted wrought-iron and
## brass arched hull ribs, crimson velvet and mahogany bookcases, 21-pipe aft salon pipe organ, brass marine
## chronometer and pressure gauges, animated 10-blade mechanical brass iris shutters on both circular observation
## viewports, underwater caustics, swaying giant kelp, coral outcrops, marine life, sunken wreck and volcanic vents.
## godot --headless --xr-mode off --path app --script res://tests/test_room_salon_1870.gd

const RoomJourney := preload("res://tests/room_journey.gd")
const RoomRender := preload("res://tests/room_render.gd")
const RoomSound := preload("res://tests/room_sound.gd")
const SoundFixture := preload("res://tests/env_sound_fixture.gd")
const DOC := "res://environments/salon_1870.env.json"


func run_tests() -> void:
	test_name = "test_room_salon_1870"
	var doc := RoomJourney.load_doc(self, DOC)
	if doc.is_empty():
		return
	var room := await RoomJourney.check_journey(self, "salon_1870", doc, "salon", "voyage", {
			"min_speed": 2.0, "max_speed": 3.0, "start_landmark": "sunken_wreck", "end_landmark": "hydro_vent"})
	RoomJourney.check_fittings(self, room, "salon", "fittings",
			"the submarine proscenium, bookcases, vitrines, aft pipe organ, binnacle and ballast manifold", 8)
	check("the aft marine chronometer is built (PieceClock)", room.find_child("PieceClock", true, false) != null)
	check("the indirect cove wash is built (PieceCove)", room.find_child("PieceCove", true, false) != null)
	var iris := room.find_child("SalonIrisShutters", true, false) as MultiMeshInstance3D
	check("the 20-blade mechanical brass iris MultiMesh is built (SalonIrisShutters)",
			iris != null and int(iris.get_meta("instances", 0)) == 20)
	check("the room is credited to Gemini 4 Neon Extra High",
			str((doc.get("room", {}) as Dictionary).get("author", "")) == "Gemini 4 Neon Extra High")
	var seats: Array[Transform3D] = room.room_seat_transforms()
	var own := seats.any(func(t: Transform3D) -> bool: return t.origin.length() < 0.001)
	check("three rows of two tufted club chairs (%d), one at the origin" % seats.size(), seats.size() == 6 and own)
	_check_life_outside_hull(doc)
	_iris_organ_and_settings(room, iris)
	# Sound: deep hull propulsion hum following journey.speed, low-pitch water lap, rising bubbles, periodic hull
	# creaks, brass engine-room telegraph bell, and aft Victorian flute pipe organ on hull acoustics.
	RoomSound.check_beds(self, "salon_1870", room, {
			"hull_hum": "deep_hum", "water": "water_lap", "vent_bubbles": "bubbles",
			"creak": "hull_creak", "telegraph": "telegraph_bell"}, "hull")
	RoomJourney.check_speed_bed(self, room, "hull_hum", "the submarine propulsion hum", 0.25)
	RoomJourney.check_figures(self, "salon_1870", room, 38, 120000)
	await done(room)
	await RoomSound.check_level(self, self, "salon_1870", doc)
	await _render(doc)


## Every marine life region and path stays strictly outside the submarine pressure hull (|x| >= 3.2 m).
func _check_life_outside_hull(doc: Dictionary) -> void:
	var clear := true
	var count := 0
	for entry: Dictionary in doc.get("systems", []):
		if str(entry.get("system", "")) != "life":
			continue
		count += 1
		var p: Dictionary = entry.get("params", {})
		if p.get("region") is Dictionary:
			var r: Dictionary = p["region"]
			var x0 := float(r["min"][0])
			var x1 := float(r["max"][0])
			if not (x1 <= -3.2 or x0 >= 3.2):
				clear = false
		if p.get("path") is Array:
			for pt: Array in p["path"]:
				if absf(float(pt[0])) < 3.2:
					clear = false
	check("all %d marine life regions and paths stay strictly outside the hull (|x| >= 3.2 m)" % count,
			count >= 4 and clear)


## Animated mechanical brass iris shutters spiral smoothly between pre-show oculus and open voyage (and snap when
## Motion < 0.25); aft pipe organ plays in pre-show and toggles cleanly; cove setting switches Amber/Turquoise/Off.
func _iris_organ_and_settings(room: Node3D, iris: MultiMeshInstance3D) -> void:
	var host: Node = room.host
	var kit: Node = host.system("fittings")
	var organ: Node = host.system("organ")

	# 1. Mechanical brass iris shutters: closed to glowing turquoise oculus in pre-show -> wide open during playback.
	host.set_setting("motion", 1.0)
	host.set_setting("shutters", "film")
	host.snapshot_override = {"open": false}
	host.timeline.state = "preshow"
	for i in 30:
		host.step(0.25)
	var pre_open := float(iris.get_meta("iris_open", -1.0)) if iris != null else -1.0
	var pre_deg := float(iris.get_meta("iris_angle_deg", -1.0)) if iris != null else -1.0
	check("pre-show brass iris sits mostly closed (open %.2f, angle %.1f deg)" % [pre_open, pre_deg],
			pre_open < 0.05 and pre_deg > 30.0)

	host.snapshot_override = {"open": true, "playing": true, "position": 0.0, "duration": RoomJourney.FILM}
	host.timeline.state = "playing"
	for i in 28:
		host.step(0.25)
	var play_open := float(iris.get_meta("iris_open", -1.0)) if iris != null else -1.0
	var play_deg := float(iris.get_meta("iris_angle_deg", 99.0)) if iris != null else 99.0
	check("playing brass iris spirals wide open (open %.2f, angle %.1f deg)" % [play_open, play_deg],
			play_open > 0.95 and play_deg < 1.0)

	# Half-open and Always-open room setting modes.
	host.set_setting("shutters", "half")
	for i in 24:
		host.step(0.25)
	var half_open := float(iris.get_meta("iris_open", -1.0)) if iris != null else -1.0
	var half_deg := float(iris.get_meta("iris_angle_deg", -1.0)) if iris != null else -1.0
	check("Viewport iris=half holds mid-aperture (open %.2f, angle %.1f deg)" % [half_open, half_deg],
			absf(half_open - 0.52) < 0.04 and half_deg > 10.0 and half_deg < 24.0)

	host.snapshot_override = {"open": false}
	host.timeline.state = "preshow"
	host.set_setting("shutters", "open")
	for i in 24:
		host.step(0.25)
	var always_open := float(iris.get_meta("iris_open", -1.0)) if iris != null else -1.0
	check("Viewport iris=open keeps shutters wide open in pre-show (open %.2f)" % always_open, always_open > 0.95)

	# Motion < 0.25 snaps cleanly without slow sliding!
	host.set_setting("motion", 0.0)
	host.set_setting("shutters", "film")
	host.step(0.1)
	var snap_open := float(iris.get_meta("iris_open", -1.0)) if iris != null else -1.0
	check("Motion < 0.25 snaps iris cleanly to closed in one step (open %.2f)" % snap_open, snap_open < 0.05)
	host.set_setting("motion", 1.0)

	# 2. Aft Victorian pipe organ plays in pre-show and stops cleanly when toggled off.
	check("organ music system exists", organ != null)
	if organ != null:
		SoundFixture.finish_loading(room)
		host.snapshot_override = {"open": false}
		host.timeline.state = "preshow"
		for i in 48:
			host.step(0.1)
		check("aft pipe organ plays flute chorales in pre-show (%d notes)" % organ.notes_played,
				organ.notes_played > 0)
		host.set_setting("organ", false)
		for i in 30:
			host.step(0.1)
		check("Salon organ=false silences the pipe organ", not organ.sounding())
		host.set_setting("organ", true)

	# 3. Cove glow setting: Warm amber -> Sea turquoise -> Off.
	host.set_setting("cove", "amber")
	for i in 12:
		host.step(0.25)
	var st_am: Dictionary = kit.cove_state()
	var c_am: Color = st_am.get("colour", Color.BLACK)
	check("Cove glow=amber washes coves warm brass gold (%s)" % c_am, not st_am.is_empty() and c_am.r > c_am.b * 1.4)
	host.set_setting("cove", "turquoise")
	for i in 12:
		host.step(0.25)
	var st_tq: Dictionary = kit.cove_state()
	var c_tq: Color = st_tq.get("colour", Color.BLACK)
	check("Cove glow=turquoise shifts coves to ocean turquoise (%s)" % c_tq,
			not st_tq.is_empty() and c_tq.b > c_tq.r * 1.4)
	host.set_setting("cove", "off")
	for i in 12:
		host.step(0.25)
	var st_off: Dictionary = kit.cove_state()
	check("Cove glow=off switches indirect coves off (%.2f)" % float(st_off.get("glow", 1.0)),
			float(st_off.get("glow", 1.0)) < 0.01)
	host.set_setting("cove", "amber")
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
	host.signals.fake("film.brightness", 0.65)
	host.signals.fake("playback.playing", 0.0)
	var eye := Vector3(0.0, 1.2, 0.0)

	# 1. Pre-show shots: warm amber Victorian lamplight, zero screen glow, brass iris closed to glowing turquoise
	#    oculus slit, grand aft 21-pipe organ, marine chronometer, navigation binnacle & pressure gauges!
	host.snapshot_override = {"open": false}
	host.timeline.state = "preshow"
	SoundFixture.finish_loading(vc[2])
	for i in 48:
		host.step(0.15)
	RoomRender.set_light(screen, 0.05)
	RenderingServer.global_shader_parameter_set("screen_glow", 0.0)
	await RoomRender.shot(self, vc, Vector3(-0.82, 1.72, 2.38), Vector3(-0.82, 1.48, -4.1), "salon_preshow_overview")
	await RoomRender.shot(self, vc, Vector3(-0.65, 1.46, -0.50), Vector3(1.58, 1.54, -0.50),
			"salon_preshow_iris_closed")
	await RoomRender.shot(self, vc, Vector3(-0.82, 1.55, -0.35), Vector3(-0.82, 1.52, 3.55), "salon_preshow_aft_organ")
	await RoomRender.shot(self, vc, Vector3(-0.35, 1.48, -1.55), Vector3(1.55, 1.38, -2.85),
			"salon_preshow_bookcase")

	# 2. Under way during the film: house lamps dimmed, screen glow on, brass iris blades spiral WIDE OPEN!
	host.signals.fake("playback.playing", 1.0)
	RoomRender.set_light(screen, 0.020)

	# Departure (0.0004): sunken 18th-century wooden wreck glowing right outside the open starboard brass viewport!
	RoomJourney.step_stage(host, 0.0004)
	await RoomRender.shot(self, vc, Vector3(-0.65, 1.46, -0.50), Vector3(18.0, 0.2, -1.8),
			"salon_departure_wreck_open")

	# Mid-voyage cruise (0.45): seat view + towering kelp forest, coral rocks, glowing jellies & port wreck!
	RoomJourney.step_stage(host, 0.45)
	await RoomRender.shot(self, vc, eye, screen, "salon_cruise_seat")
	await RoomRender.shot(self, vc, Vector3(-0.55, 1.42, -0.45), Vector3(16.0, 0.4, -1.2),
			"salon_cruise_starboard_kelp")
	await RoomRender.shot(self, vc, Vector3(-0.95, 1.42, -0.45), Vector3(-18.0, 0.4, -1.2),
			"salon_cruise_port_kelp")

	# Arrival (1.0): monumental glowing deep-sea hydrothermal volcanic chimney outside the open starboard viewport!
	# Keep iris open at arrival moment (0.996 = credits/arriving) so we see the volcanic vents framing arrival!
	RoomJourney.step_stage(host, 0.996)
	await RoomRender.shot(self, vc, Vector3(-0.65, 1.46, -0.50), Vector3(17.5, 1.2, -0.5),
			"salon_arrival_hydro_vent")

	# Also render half-open iris + sea-turquoise cove mood!
	host.set_setting("shutters", "half")
	host.set_setting("cove", "turquoise")
	for i in 28:
		host.step(0.25)
	await RoomRender.shot(self, vc, Vector3(-0.82, 1.72, 2.38), Vector3(-0.82, 1.48, -4.1),
			"salon_half_iris_turquoise")
	await RoomRender.close(self, vc)
