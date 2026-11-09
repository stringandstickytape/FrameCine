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

const RoomRender := preload("res://tests/room_render.gd")
const Passing := preload("res://scripts/env/systems/passing.gd")
const PassingShapes := preload("res://scripts/env/systems/passing/shapes.gd")
const Cabin := preload("res://scripts/env/systems/cabin.gd")
const RoomSound := preload("res://tests/room_sound.gd")
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
	_comfort_table(canal.params)
	_fittings(room)
	# Sound: the owl and the bell far off, the engine astern under the deck, the water on the hull; a small room.
	RoomSound.check_beds(self, "narrowboat", room, {"owl": "tawny_owl", "bell": "church_bell",
			"engine": "boat_engine", "water": "water_lap"}, "small_room")
	_engine(room)
	var stats := EnvChecks.measure(room)
	print("  narrowboat: %d draws, %d triangles, %d lights, %.1f MB of textures" % [int(stats["draws"]),
			int(stats["triangles"]), int(stats["lights"]), float(stats["texture_mb"])])
	check("the figures: at most 26 draws, 60 000 triangles, no live light (%s)" % [stats],
			int(stats["draws"]) <= 26 and int(stats["triangles"]) <= 60000 and int(stats["lights"]) == 0)
	await done(room)
	await RoomSound.check_level(self, self, "narrowboat", doc)
	await _render(doc)


## The engine follows the journey (its level bound to journey.speed, 0.4 to 1): full under way, down to 0.4 stopped.
func _engine(room: Node3D) -> void:
	var host: Node = room.host
	var engine: Node = host.system("engine")
	host.timeline.state = ""
	var pos := 600.0
	for i in 120:
		pos += 0.25
		host.snapshot_override = {"open": true, "playing": true, "position": pos, "duration": FILM}
		host.step(0.25)
	var going := float(engine.params["level"])
	host.snapshot_override = {"open": true, "playing": false, "position": pos, "duration": FILM}
	for i in 120:
		host.step(0.25)
	var stopped := float(engine.params["level"])
	check("the engine under way (%.2f) and stopped (%.2f)" % [going, stopped], going > 0.9
			and absf(stopped - 0.4) <= 0.05)


## The saloon's furniture: inside the cabin (but the stove's flue, which goes up through the roof), and nothing but
## the rug within 0.45 m of the seat.
func _fittings(room: Node3D) -> void:
	var host: Node = room.host
	var kit: Node = host.system("fittings")
	check("the saloon's furniture (the kit fittings)", kit != null)
	if kit == null:
		return
	var cabin_box: AABB = Cabin._box(host.system("saloon").params).grow(0.001)
	# The stove's flue in the room: the stove at (-0.66, 2.2), turned to face +X; its flue 0.08 behind its middle.
	var flue := Vector2(-0.74, 2.2)
	var inside := true
	var clear := true
	var boxes: Array = kit.collision_shapes()
	for s: Array in boxes:
		var shape := s[0] as BoxShape3D
		var box: AABB = (s[1] as Transform3D) * AABB(-shape.size * 0.5, shape.size)
		var mid := box.get_center()
		var is_flue := Vector2(mid.x, mid.z).distance_to(flue) < 0.06 and box.position.y > 0.5
		if not cabin_box.encloses(box) and not is_flue:
			inside = false
		var nearest := Vector2(clampf(0.0, box.position.x, box.end.x), clampf(0.0, box.position.z, box.end.z))
		if nearest.length() < 0.45:
			clear = false
	check("its pieces' boxes (%d) inside the cabin, but the flue's top" % boxes.size(), boxes.size() > 0 and inside)
	check("nothing but the rug within 0.45 m of the seat", clear)
	check("nothing the kit could not place (%s)" % [kit.problems()], kit.problems().is_empty())


## The comfort figures of every band and landmark (docs/environments/rooms/narrowboat.md, "Comfort"): the nearest
## any part of it comes (Shapes.nearest(), as passing.gd comfort_for() asks) and the degrees a second it crosses the
## eye there at the fastest the journey goes (its speed times 1 + CATCH_UP).
func _comfort_table(p: Dictionary) -> void:
	var top := float(p.get("speed", 1.0)) * (1.0 + Passing.CATCH_UP)
	print("  comfort at %.2f m/s:" % top)
	var bands: Array = p["bands"]
	for i in bands.size():
		var band := Passing.band_with_defaults(bands[i])
		var shape := str(band["shape"])
		var largest := float(band["size"]) * (1.0 if PassingShapes.SEGMENT.has(shape) else PassingShapes.VARY.y)
		var near := PassingShapes.nearest(shape, largest, float(band["near"]), float(band["height"]),
				EnvChecks.EYE_HEIGHT)
		print("    band %d %s %s: nearest %.2f m, %.1f deg/s" % [i, shape, band["side"], near,
				rad_to_deg(top / float(band["seems"]) / near)])
	var landmarks: Array = p["landmarks"]
	for k in landmarks.size():
		var lm := Passing.landmark_with_defaults(landmarks[k])
		var shape := str(lm["shape"])
		var near := PassingShapes.nearest(shape, float(lm["size"]), float(lm["distance"]), float(lm["height"]),
				EnvChecks.EYE_HEIGHT)
		print("    landmark %d %s %s at %.3f: nearest %.2f m, %.1f deg/s" % [k, shape, lm["side"], float(lm["at"]),
				near, rad_to_deg(top / near)])


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
	# The saloon's furniture in the pre-show, the lamps up: the stove by the rear door, the sideboard under the picture.
	host.timeline.state = ""
	host.snapshot_override = {"open": false}
	for i in 40:
		host.step(0.25)
	RoomRender.set_light(screen, 0.04)
	await RoomRender.shot(self, vc, Vector3(0.0, 1.5, -1.6), Vector3(-0.66, 0.5, 2.2), "narrowboat_stove")
	await RoomRender.shot(self, vc, Vector3(0.5, 1.6, 1.8), Vector3(0.0, 0.6, -1.9), "narrowboat_saloon")
	await RoomRender.close(self, vc)
