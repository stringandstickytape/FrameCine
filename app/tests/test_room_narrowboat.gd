extends "res://tests/env_builder_harness.gd"

## The Narrowboat (app/environments/narrowboat.env.json; docs/environments/rooms/narrowboat.md): the first of the
## Journeys. A canal boat's saloon; the canal goes by outside at walking pace for as long as the film lasts. Built
## headless from its document and checked as every shipped room is and as a builder's room; then what makes it this
## room: the journey follows the film and ends at the wharf, nothing that goes by is near the picture or too near the
## eyes, the lamps go down with the film; the saloon's furniture stays inside the cabin and clear of the seat; the
## owl, the bell, the engine (following the journey's speed) and the water on the room's bus, under the level check's
## target; the room's figures. Under lavapipe it draws the saloon and the canal at five places on the route, then the
## stove and the saloon in the pre-show.
## godot --headless --xr-mode off --path app --script res://tests/test_room_narrowboat.gd

const RoomJourney := preload("res://tests/room_journey.gd")
const RoomRender := preload("res://tests/room_render.gd")
const RoomSound := preload("res://tests/room_sound.gd")
const DOC := "res://environments/narrowboat.env.json"


func run_tests() -> void:
	test_name = "test_room_narrowboat"
	var doc := RoomJourney.load_doc(self, DOC)
	if doc.is_empty():
		return
	var room := await RoomJourney.check_journey(self, "narrowboat", doc, "saloon", "canal", {
			"min_speed": 0.8, "max_speed": 1.4, "start_landmark": "lamp", "end_landmark": "wharf"})
	# The stove's flue in the room: the stove at (-0.6, 2.2), turned to face +X; its flue 0.08 behind its middle.
	var flue := Vector2(-0.68, 2.2)
	var is_flue := func(box: AABB) -> bool:
		var mid := box.get_center()
		return Vector2(mid.x, mid.z).distance_to(flue) < 0.12 and box.position.y > 0.5
	RoomJourney.check_fittings(self, room, "saloon", "fittings", "the saloon's furniture", 1, is_flue)
	# Sound: the owl and the bell far off, the engine astern under the deck, the water on the hull; a small room.
	RoomSound.check_beds(self, "narrowboat", room, {"owl": "tawny_owl", "bell": "church_bell",
			"engine": "boat_engine", "water": "water_lap"}, "small_room")
	RoomJourney.check_speed_bed(self, room, "engine", "the engine", 0.4)
	RoomJourney.check_figures(self, "narrowboat", room, 26, 60000)
	await done(room)
	await RoomSound.check_level(self, self, "narrowboat", doc)
	await _render(doc)


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
	var eye := Vector3(0, 1.2, 0)
	# Before the film: the lamps up, at the mooring.
	host.snapshot_override = {"open": false}
	for i in 40:
		host.step(0.25)
	RoomRender.set_light(screen, 0.04)
	await RoomRender.shot(self, vc, Vector3(0.0, 1.45, 2.2), screen, "narrowboat_preshow_back")
	await RoomRender.shot(self, vc, eye, eye + Vector3(0.0, -0.1, 1.0), "narrowboat_preshow_astern")
	RoomRender.set_light(screen, 0.015)
	for stage: Array in [["dusk", 0.03], ["bridge", 0.1385], ["wood", 0.5], ["village", 0.75], ["wharf", 1.0]]:
		RoomJourney.step_stage(host, float(stage[1]))
		var n := str(stage[0])
		await RoomRender.shot(self, vc, eye, screen, "narrowboat_%s_seat" % n)
		await RoomRender.shot(self, vc, eye, eye + Vector3(-1.0, 0.05, -0.3), "narrowboat_%s_left" % n)
		await RoomRender.shot(self, vc, eye, eye + Vector3(1.0, 0.05, -0.3), "narrowboat_%s_right" % n)
		# From outside and above, to see the way's banks (not a view anyone has), and from the roof over the fields.
		await RoomRender.shot(self, vc, Vector3(-3.0, 9.0, 16.0), Vector3(0.0, 1.0, -14.0), "narrowboat_%s_over" % n)
		await RoomRender.shot(self, vc, Vector3(0.0, 2.6, 0.0), Vector3(-40.0, 3.0, -14.0), "narrowboat_%s_fields" % n)
	# The saloon's furniture in the pre-show, the lamps up: the stove by the rear door, the sideboard under the picture.
	host.timeline.state = ""
	host.snapshot_override = {"open": false}
	for i in 40:
		host.step(0.25)
	RoomRender.set_light(screen, 0.04)
	await RoomRender.shot(self, vc, Vector3(0.0, 1.5, -1.6), Vector3(-0.66, 0.5, 2.2), "narrowboat_stove")
	await RoomRender.shot(self, vc, Vector3(0.5, 1.6, 1.8), Vector3(0.0, 0.6, -1.9), "narrowboat_saloon")
	await RoomRender.close(self, vc)
