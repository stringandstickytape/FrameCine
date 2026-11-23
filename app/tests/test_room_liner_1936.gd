extends "res://tests/env_builder_harness.gd"

## Liner 1936 (app/environments/liner_1936.env.json; docs/environments/rooms/liner_1936.md): the third of the Journeys.
## An ocean liner's moderne lounge crossing at night: the ship never rolls while the tall velvet drapes sway gently with
## the sea swell, the Moon lays a road across open water to the horizon, a sister liner passes in mid-Atlantic, and
## harbour lights and a lit pier welcome the ship at the credits. Under lavapipe it renders the lounge, proscenium,
## drapes, Moon's road and harbour at five stages of the voyage.
## godot --headless --xr-mode off --path app --script res://tests/test_room_liner_1936.gd

const RoomJourney := preload("res://tests/room_journey.gd")
const RoomRender := preload("res://tests/room_render.gd")
const RoomSound := preload("res://tests/room_sound.gd")
const DOC := "res://environments/liner_1936.env.json"


func run_tests() -> void:
	test_name = "test_room_liner_1936"
	var doc := RoomJourney.load_doc(self, DOC)
	if doc.is_empty():
		return
	var room := await RoomJourney.check_journey(self, "liner_1936", doc, "lounge", "sea", {
			"min_speed": 3.0, "max_speed": 4.2, "start_landmark": "pier", "end_landmark": "pier"})
	RoomJourney.check_fittings(self, room, "lounge", "fittings", "the lounge's proscenium, pelmets and clock", 3)
	check("the rear bulkhead clock is built (PieceClock)", room.find_child("PieceClock", true, false) != null)
	check("the room is credited to Gemini 4 Neon Extra High",
			str((doc.get("room", {}) as Dictionary).get("author", "")) == "Gemini 4 Neon Extra High")
	var seats: Array[Transform3D] = room.room_seat_transforms()
	var own := seats.any(func(t: Transform3D) -> bool: return t.origin.length() < 0.001)
	check("five rows of four club armchairs (%d), one at the origin" % seats.size(), seats.size() == 20 and own)
	_drapes(room)
	_cove(room)
	# Sound: turbines following journey.speed, ocean wash, occasional hull creak, ship's horn; cinema lounge reverb.
	RoomSound.check_beds(self, "liner_1936", room, {"turbines": "deep_hum", "sea_wash": "water_lap",
			"creak": "hull_creak", "horn": "ship_horn"}, "cinema")
	RoomJourney.check_speed_bed(self, room, "turbines", "the turbines", 0.35)
	RoomJourney.check_figures(self, "liner_1936", room, 36, 120000)
	await done(room)
	await RoomSound.check_level(self, self, "liner_1936", doc)
	await _render(doc)


## The drapes sway in unison with the voyage while the lounge stays still: gentle at sea, settled in harbour.
func _drapes(room: Node3D) -> void:
	var host: Node = room.host
	var left: Node = host.system("sway_left")
	var right: Node = host.system("sway_right")
	var dl: Node = host.system("drapes_left")
	var dr: Node = host.system("drapes_right")
	check("both drape groups built with no problems", dl != null and dr != null and dl.problems().is_empty()
			and dr.problems().is_empty())
	check("both drape movers target their groups", left != null and right != null
			and left.target() != null and right.target() != null)
	if left == null or right == null:
		return
	host.timeline.state = ""
	var pos := 1200.0
	var peak_sea := 0.0
	for i in 120:
		pos += 0.25
		host.snapshot_override = {"open": true, "playing": true, "position": pos, "duration": RoomJourney.FILM}
		host.step(0.25)
		peak_sea = maxf(peak_sea, absf(float(left.call("_angle_now"))))
	var ang_l := float(left.call("_angle_now"))
	var ang_r := float(right.call("_angle_now"))
	check("at sea: drapes sway together (peak %.2f deg, L %.2f R %.2f)" % [peak_sea, ang_l, ang_r],
			peak_sea > 1.2 and peak_sea <= 2.2 and absf(ang_l - ang_r) < 0.05)
	host.snapshot_override = {"open": true, "playing": false, "position": pos, "duration": RoomJourney.FILM}
	for i in 120:
		host.step(0.25)
	var peak_port := 0.0
	for i in 40:
		host.step(0.25)
		peak_port = maxf(peak_port, absf(float(left.call("_angle_now"))))
	check("in harbour: drapes settle gently (peak %.2f deg)" % peak_port, peak_port <= 0.35)


## The proscenium coves follow the room's Cove lights setting before the film.
func _cove(room: Node3D) -> void:
	var host: Node = room.host
	var kit: Node = host.system("fittings")
	host.timeline.state = ""
	host.snapshot_override = {"open": false}
	host.set_setting("cove", "jade")
	for i in 20:
		host.step(0.25)
	var state: Dictionary = kit.cove_state()
	var col: Color = state.get("colour", Color.BLACK)
	check("cove setting jade moves the proscenium coves (%s)" % col, not state.is_empty() and col.g > col.r * 1.4)
	host.set_setting("cove", "gold")
	for i in 20:
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
	# Pre-show: lamps up, berthed beside the departure pier.
	host.snapshot_override = {"open": false}
	for i in 40:
		host.step(0.25)
	RoomRender.set_light(screen, 0.04)
	await RoomRender.shot(self, vc, Vector3(-1.09, 1.75, 4.1), screen, "liner_preshow_back")
	await RoomRender.shot(self, vc, Vector3(-1.09, 1.65, -3.5), Vector3(-1.09, 1.85, 4.6), "liner_preshow_hall")
	await RoomRender.shot(self, vc, Vector3(-1.09, 1.6, -1.8), Vector3(-1.09, 2.1, -5.8), "liner_preshow_proscenium")
	RoomRender.set_light(screen, 0.015)
	# Five stages along the voyage: dusk departure pier, breakwater lighthouse, open Atlantic with Moon & ship,
	# harbour approach, and arrival pier.
	for stage: Array in [["dusk", 0.002], ["lighthouse", 0.0045], ["ocean", 0.48], ["approach", 0.995], ["harbour", 1.0]]:
		RoomJourney.step_stage(host, float(stage[1]))
		var n := str(stage[0])
		await RoomRender.shot(self, vc, eye, screen, "liner_%s_seat" % n)
		await RoomRender.shot(self, vc, eye, eye + Vector3(-1.0, 0.05, -0.26), "liner_%s_left" % n)
		await RoomRender.shot(self, vc, eye, eye + Vector3(1.0, 0.02, -0.25), "liner_%s_right" % n)
		await RoomRender.shot(self, vc, Vector3(-1.09, 4.6, 0.0), Vector3(-70.0, 1.5, -18.0), "liner_%s_port" % n)
		await RoomRender.shot(self, vc, Vector3(-1.09, 4.6, 0.0), Vector3(70.0, 1.5, -18.0), "liner_%s_starboard" % n)
	await RoomRender.close(self, vc)
