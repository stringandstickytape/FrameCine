extends "res://tests/env_builder_harness.gd"

## Airship 1931 (app/environments/airship_1931.env.json; docs/environments/rooms/airship_1931.md): golden-age rigid
## airship promenade lounge in the Journeys arc. Built by Gemini 4 Neon Extra High. Outward-leaning panoramic
## observation windows framed by exposed brushed-duralumin triangular lattice girders, a self-playing featherweight
## grand piano with 61 animated moving keys, an endless moonlit sea of clouds far below, sleeping coast lights, and
## illuminated 1930s mooring masts at departure and arrival.
## godot --headless --xr-mode off --path app --script res://tests/test_room_airship_1931.gd

const RoomJourney := preload("res://tests/room_journey.gd")
const RoomRender := preload("res://tests/room_render.gd")
const RoomSound := preload("res://tests/room_sound.gd")
const SoundFixture := preload("res://tests/env_sound_fixture.gd")
const DOC := "res://environments/airship_1931.env.json"


func run_tests() -> void:
	test_name = "test_room_airship_1931"
	var doc := RoomJourney.load_doc(self, DOC)
	if doc.is_empty():
		return
	var room := await RoomJourney.check_journey(self, "airship_1931", doc, "promenade", "skyway", {
			"min_speed": 4.2, "max_speed": 5.6, "start_landmark": "airship_mast", "end_landmark": "airship_mast"})
	RoomJourney.check_fittings(self, room, "promenade", "fittings",
			"the airship proscenium, torchières, chart table, credenza and featherweight grand piano", 6)
	check("the aft bulkhead clock is built (PieceClock)", room.find_child("PieceClock", true, false) != null)
	check("the indirect cove wash is built (PieceCove)", room.find_child("PieceCove", true, false) != null)
	check("the animated piano keys MultiMesh is built (AirshipPianoKeys)",
			room.find_child("AirshipPianoKeys", true, false) != null)
	check("the room is credited to Gemini 4 Neon Extra High",
			str((doc.get("room", {}) as Dictionary).get("author", "")) == "Gemini 4 Neon Extra High")
	var seats: Array[Transform3D] = room.room_seat_transforms()
	var own := seats.any(func(t: Transform3D) -> bool: return t.origin.length() < 0.001)
	check("three rows of four lounge chairs (%d), one at the origin" % seats.size(), seats.size() == 12 and own)
	_piano_and_settings(room)
	# Sound: distant airship engines following journey.speed, soft high-altitude wind, salon chime, and self-playing
	# grand piano on small_room acoustics.
	RoomSound.check_beds(self, "airship_1931", room, {"engines": "airship_engines", "breeze": "wind",
			"chime": "chime"}, "small_room")
	RoomJourney.check_speed_bed(self, room, "engines", "the airship engines", 0.25)
	RoomJourney.check_figures(self, "airship_1931", room, 38, 120000)
	await done(room)
	await RoomSound.check_level(self, self, "airship_1931", doc)
	await _render(doc)


## Self-playing grand piano depresses its MultiMesh keys in pre-show and releases them when toggled off; Cove glow
## setting switches cleanly between Champagne, Moonlight silver, and Off.
func _piano_and_settings(room: Node3D) -> void:
	var host: Node = room.host
	var piano: Node = host.system("piano")
	var kit: Node = host.system("fittings")
	var keys_node := room.find_child("AirshipPianoKeys", true, false) as MultiMeshInstance3D
	check("piano music system exists", piano != null)
	if piano != null:
		SoundFixture.finish_loading(room)
		host.snapshot_override = {"open": false}
		host.timeline.state = "preshow"
		var saw_keys_down := 0
		for i in 48:
			host.step(0.1)
			if keys_node != null:
				saw_keys_down = maxi(saw_keys_down, int(keys_node.get_meta("keys_down", 0)))
		check("piano plays in pre-show (%d notes) and animates keys down (peak %d)" % [piano.notes_played,
				saw_keys_down], piano.notes_played > 0 and saw_keys_down > 0)
		host.set_setting("piano", false)
		for i in 30:
			host.step(0.1)
		var down_off := int(keys_node.get_meta("keys_down", 0)) if keys_node != null else -1
		check("Lounge piano=false stops piano and releases keys (down %d)" % down_off,
				not piano.sounding() and down_off == 0)
		host.set_setting("piano", true)
	# Cove glow setting: Champagne (warm) -> Moonlight silver (cool) -> Off (0.0).
	host.set_setting("cove", "champagne")
	for i in 12:
		host.step(0.25)
	var st_ch: Dictionary = kit.cove_state()
	var c_ch: Color = st_ch.get("colour", Color.BLACK)
	check("Cove glow=champagne washes coves warm gold (%s)" % c_ch, not st_ch.is_empty() and c_ch.r > c_ch.b * 1.4)
	host.set_setting("cove", "silver")
	for i in 12:
		host.step(0.25)
	var st_sv: Dictionary = kit.cove_state()
	var c_sv: Color = st_sv.get("colour", Color.BLACK)
	check("Cove glow=silver shifts coves to cool moonlight silver (%s)" % c_sv,
			not st_sv.is_empty() and c_sv.b > c_sv.r * 1.2)
	host.set_setting("cove", "off")
	for i in 12:
		host.step(0.25)
	var st_off: Dictionary = kit.cove_state()
	check("Cove glow=off switches indirect coves off (%.2f)" % float(st_off.get("glow", 1.0)),
			float(st_off.get("glow", 1.0)) < 0.01)
	host.set_setting("cove", "champagne")
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
	host.signals.fake("playback.playing", 0.0)
	var eye := Vector3(0.0, 1.2, 0.0)

	# Pre-show shots: full champagne ambient light, zero screen glow, piano playing & moving keys, moored at departure
	# mooring mast!
	host.snapshot_override = {"open": false}
	SoundFixture.finish_loading(vc[2])
	for i in 48:
		host.step(0.15)
	RoomRender.set_light(screen, 0.05)
	RenderingServer.global_shader_parameter_set("screen_glow", 0.0)
	await RoomRender.shot(self, vc, Vector3(-1.15, 1.82, 3.35), Vector3(-1.15, 1.55, -5.0), "airship_preshow_overview")
	await RoomRender.shot(self, vc, Vector3(-2.32, 1.32, -1.85), Vector3(-3.55, 0.92, -3.55), "airship_preshow_piano")
	await RoomRender.shot(self, vc, Vector3(-1.15, 1.65, -2.2), Vector3(-1.15, 1.45, 4.2), "airship_preshow_aft")
	await RoomRender.shot(self, vc, Vector3(-0.3, 1.48, 2.3), Vector3(0.75, 0.85, 3.85), "airship_preshow_chart")
	# Moored at departure airship mast outside the starboard leaning windows!
	await RoomRender.shot(self, vc, eye, eye + Vector3(1.0, 0.02, -0.05), "airship_departure_mast")

	# Under way during film: dim house lamps, screen glow on, gazing out & down through the leaning observation windows
	# at the moonlit cloud ocean, 3D cloud puffs, sleeping coast lights, and arrival mooring mast!
	host.signals.fake("playback.playing", 1.0)
	RoomRender.set_light(screen, 0.018)
	for stage: Array in [["departure", 0.0004], ["cruise", 0.48], ["arrival", 1.0]]:
		RoomJourney.step_stage(host, float(stage[1]))
		var n := str(stage[0])
		await RoomRender.shot(self, vc, eye, screen, "airship_%s_seat" % n)
		await RoomRender.shot(self, vc, eye, eye + Vector3(1.0, -0.18, -0.14), "airship_%s_starboard" % n)
		await RoomRender.shot(self, vc, Vector3(-3.4, 1.38, -0.3), Vector3(-12.0, -1.8, -1.2), "airship_%s_port" % n)
		if n == "cruise":
			await RoomRender.shot(self, vc, Vector3(1.45, 1.48, -0.3), Vector3(16.0, -2.6, -1.5),
					"airship_cruise_clouds_down")
			# Also verify Moonlight silver cove mood during mid-flight cruise!
			host.set_setting("cove", "silver")
			for i in 16:
				host.step(0.25)
			await RoomRender.shot(self, vc, Vector3(-1.15, 1.82, 3.35), Vector3(-1.15, 1.55, -5.0),
					"airship_cruise_silver")
			host.set_setting("cove", "champagne")
			for i in 16:
				host.step(0.25)
	await RoomRender.close(self, vc)
