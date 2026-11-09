extends "res://tests/env_builder_harness.gd"

## The Narrowboat (app/environments/narrowboat.env.json; docs/environments/rooms/narrowboat.md): the first of the
## Journeys. A canal boat's saloon; the canal goes by outside at walking pace for as long as the film lasts. Built
## headless from its document and checked as every shipped room is and as a builder's room; then what makes it this
## room: the journey follows the film and ends at the wharf, nothing that goes by is near the picture or too near the
## eyes, the lamps go down with the film. Under lavapipe it draws the saloon and the canal at five places on the route.
## godot --headless --xr-mode off --path app --script res://tests/test_room_narrowboat.gd

const RoomRender := preload("res://tests/room_render.gd")
const Passing := preload("res://scripts/env/systems/passing.gd")
const DOC := "res://environments/narrowboat.env.json"
const FILM := 7200.0


func run_tests() -> void:
	test_name = "test_room_narrowboat"
	var r := EnvDoc.load_file(DOC)
	check("the document reads (%s)" % [r["errors"]], (r["errors"] as Array).is_empty())
	var doc: Dictionary = r["doc"]
	if doc.is_empty():
		return
	var room := await check_room("narrowboat", doc, "saloon")
	var host: Node = room.host
	host.auto = false
	var canal: Node = host.system("canal")
	check("it is a journey", str(doc["room"]["category"]) == "journey" and canal != null)
	var comfort: Array = EnvChecks.comfort(doc)
	check("comfort: nothing that goes by comes too near or too fast (%s)" % [comfort], comfort.is_empty())
	var clear: Array = await EnvChecks.flow_clear(self, room)
	check("nothing goes by within %s degrees of the picture (%s)" % [EnvChecks.FLOW_CLEAR_DEG, clear.slice(0, 2)],
			clear.is_empty())
	var layers: Dictionary = await EnvChecks.blend_layers(self, room)
	check("the windows' glass is well under a layer over the view (%s)" % [layers],
			float(layers["mean"]) <= EnvChecks.BLEND_BUDGET * 0.5)
	# The journey is as long as the film and ends at the wharf.
	host.snapshot_override = {"open": true, "playing": true, "position": 0.0, "duration": FILM}
	for i in 40:
		host.step(0.25)
	var speed := float(canal.own_speed)
	check("under way at a walking pace (%.2f m/s)" % speed, speed >= 0.8 and speed <= 1.4)
	check("the route is the film's length at that pace, less the slowing for the end (%.0f m)" % canal.route_length(),
			absf(canal.route_length() - (speed * FILM - speed * speed / (2.0 * Passing.BRAKE))) < 0.5)
	check("the lamps go down with the film (%.2f)" % float(host.param("light.house_lamps")),
			float(host.param("light.house_lamps")) < 0.2)
	var landmarks: Array = canal.params["landmarks"]
	check("it leaves from under a lamp and ends at a wharf (%s, %s)" % [landmarks[0]["shape"], landmarks[-1]["shape"]],
			str(landmarks[0]["shape"]) == "lamp" and float(landmarks[0]["at"]) == 0.0
			and str(landmarks[-1]["shape"]) == "wharf" and float(landmarks[-1]["at"]) == 1.0)
	host.snapshot_override = {"open": true, "playing": false, "ended": true, "position": FILM, "duration": FILM}
	for i in 60:
		host.step(0.25)
	check("the film over: stopped at the route's end, the lamps up (%.1f of %.1f m, %.2f m/s, lamps %.2f)" % [
			canal.travel, canal.route_length(), canal.speed_now, float(host.param("light.house_lamps"))],
			absf(canal.travel - canal.route_length()) < 0.5 and canal.speed_now == 0.0
			and float(host.param("light.house_lamps")) > 0.95)
	await done(room)
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
		var at := float(stage[1]) * FILM
		host.snapshot_override = {"open": true, "playing": at < FILM, "ended": at >= FILM, "position": at,
				"duration": FILM}
		# (No player here: the film's own channels are given by hand, as the snapshot is.)
		host.signals.fake("film.progress", float(stage[1]))
		host.signals.fake("film.minutes", at / 60.0)
		for i in 80:
			host.step(0.25)
		var n := str(stage[0])
		await RoomRender.shot(self, vc, eye, screen, "narrowboat_%s_seat" % n)
		await RoomRender.shot(self, vc, eye, eye + Vector3(-1.0, 0.05, -0.3), "narrowboat_%s_left" % n)
		await RoomRender.shot(self, vc, eye, eye + Vector3(1.0, 0.05, -0.3), "narrowboat_%s_right" % n)
		# From outside and above, to see the way's banks (not a view anyone has), and from the roof over the fields.
		await RoomRender.shot(self, vc, Vector3(-3.0, 9.0, 16.0), Vector3(0.0, 1.0, -14.0), "narrowboat_%s_over" % n)
		await RoomRender.shot(self, vc, Vector3(0.0, 2.6, 0.0), Vector3(-40.0, 3.0, -14.0), "narrowboat_%s_fields" % n)
	await RoomRender.close(self, vc)
