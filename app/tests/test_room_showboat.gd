extends "res://tests/env_builder_harness.gd"

## Showboat 1927 (app/environments/showboat_1927.env.json; docs/environments/rooms/showboat_1927.md): the second of
## the Journeys. A floating theatre on a wide river for as long as the film lasts. Built headless from its document
## and checked as every shipped room is and as a builder's room; then the journey's arrival, comfort, lamps, stage
## and seats; the paddle wheel following the journey's speed, water, crickets and a far train on the room's bus,
## under the level check's target; the room's figures. Under lavapipe it draws the hall and river at five places on
## the route, and the hall in the pre-show.
## godot --headless --xr-mode off --path app --script res://tests/test_room_showboat.gd

const RoomJourney := preload("res://tests/room_journey.gd")
const RoomRender := preload("res://tests/room_render.gd")
const RoomSound := preload("res://tests/room_sound.gd")
const DOC := "res://environments/showboat_1927.env.json"


func run_tests() -> void:
	test_name = "test_room_showboat"
	var doc := RoomJourney.load_doc(self, DOC)
	if doc.is_empty():
		return
	var room := await RoomJourney.check_journey(self, "showboat", doc, "hall", "river", {
			"min_speed": 1.6, "max_speed": 2.4, "start_landmark": "wharf", "end_landmark": "wharf"})
	RoomJourney.check_fittings(self, room, "hall", "fittings", "the hall's stage and proscenium", 3)
	var seats: Array[Transform3D] = room.room_seat_transforms()
	var own := seats.any(func(t: Transform3D) -> bool: return t.origin.length() < 0.001)
	check("seven rows of eight seats (%d), one at the origin" % seats.size(), seats.size() == 56 and own)
	# Sound: the paddle wheel astern, water on the hull, crickets around and a far train; the hall's reverb.
	RoomSound.check_beds(self, "showboat", room, {"wheel": "paddle_wheel", "water": "water_lap",
			"crickets": "crickets", "train": "train"}, "shopfront")
	RoomJourney.check_speed_bed(self, room, "wheel", "the paddle wheel", 0.05)
	RoomJourney.check_figures(self, "showboat", room, 32, 90000)
	await done(room)
	await RoomSound.check_level(self, self, "showboat", doc)
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
	await RoomRender.shot(self, vc, Vector3(-0.7, 1.7, 4.0), screen, "showboat_preshow_back")
	await RoomRender.shot(self, vc, Vector3(-0.7, 1.6, -3.6), Vector3(-0.7, 1.4, 4.6), "showboat_preshow_hall")
	await RoomRender.shot(self, vc, Vector3(-0.7, 1.5, -2.0), Vector3(-0.7, 1.9, -5.5), "showboat_preshow_stage")
	RoomRender.set_light(screen, 0.015)
	for stage: Array in [["dusk", 0.03], ["steamer", 0.297], ["town", 0.52], ["night", 0.8], ["landing", 1.0]]:
		RoomJourney.step_stage(host, float(stage[1]))
		var n := str(stage[0])
		await RoomRender.shot(self, vc, eye, screen, "showboat_%s_seat" % n)
		await RoomRender.shot(self, vc, eye, eye + Vector3(-1.0, 0.1, -0.3), "showboat_%s_left" % n)
		await RoomRender.shot(self, vc, eye, eye + Vector3(1.0, 0.1, -0.3), "showboat_%s_right" % n)
		# From outside and above, to see the river and its bank, and from the roof to either side.
		await RoomRender.shot(self, vc, Vector3(-8.0, 14.0, 26.0), Vector3(0.0, 1.0, -20.0), "showboat_%s_over" % n)
		await RoomRender.shot(self, vc, Vector3(-0.7, 4.6, 0.0), Vector3(-60.0, 3.0, -14.0), "showboat_%s_river" % n)
		await RoomRender.shot(self, vc, Vector3(-0.7, 4.6, 0.0), Vector3(40.0, 3.0, -14.0), "showboat_%s_bank" % n)
	await RoomRender.close(self, vc)
