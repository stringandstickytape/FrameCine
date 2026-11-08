extends "res://tests/env_builder_harness.gd"

## Drive-in, 1958 (app/environments/drive_in_1958.env.json; docs/environments.md, "Room: Drive-in - 1958"): the
## viewer on the front bench of a convertible on a drive-in's lot in the desert. The room is its document alone (the
## older drive-in scene stays as it was) and passes the checks (schema, budget, sight lines from every seat, comfort,
## licences, names, no people) and the car's builder conventions. What makes it the drive-in: the lot with its screen
## tower and a neon snack bar behind, the car, dusk falling to a starry night over the film's first minutes and the
## stars turning through it, mesas round the horizon, moths in the projector's beam, a plane's lights now and then,
## the Window speaker setting (off by default: the film's own sound; on: the window speaker), and the car's lamps:
## off for the film, the dials dimmed, the headlamps on again after the end. Its sound: crickets round the car, a far
## freight train now and then, a soft wind, a far car on the highway behind as its lights go by, the open air's
## acoustics, the level measured (with the train passing).
## godot --headless --xr-mode off --path app --script res://tests/test_room_drive_in_1958.gd

const EnvSynth := preload("res://scripts/env/env_synth.gd")
const RoomSound := preload("res://tests/room_sound_checks.gd")
const RoomRender := preload("res://tests/room_render.gd")
const PATH := "res://environments/drive_in_1958.env.json"


func run_tests() -> void:
	test_name = "test_room_drive_in_1958"
	var r := EnvDoc.load_file(PATH)
	check("the document reads %s" % [r["errors"]], (r["errors"] as Array).is_empty())
	var doc: Dictionary = r["doc"]
	check("a cinema in the Room tab", str(doc["room"].get("category", "")) == "cinema")
	var Library: GDScript = load("res://scripts/env/env_library.gd")
	var names := {}
	for e: Array in Library.environments():
		names[str(e[0])] = str(e[1])
	check("listed by its document, named apart from the older drive-in (%s, %s)" % [names.get("drive_in_1958"),
			names.get("drive_in")], names.has("drive_in_1958") and names.has("drive_in")
			and names["drive_in_1958"] != names["drive_in"])
	var room := await check_room("Drive-in", doc, "car")
	var h: Node = room.host
	h.auto = false
	for sid: String in ["light", "lot", "car", "screen_frame", "sky", "vista", "moths", "planes",
			"presentation"]:
		check("system %s built" % sid, h.system(sid) != null)

	# The lot, the tower, the snack bar; the viewer on the car's front bench.
	var lot: Node = h.system("lot")
	check("the terrace as a whole drive-in, the screen on its tower", str(lot.params["style"]) == "lot"
			and str(lot.params["screen"]) == "none" and bool(lot.params["drive_in"]))
	await _drive_in(room, doc)
	var seats: Array[Transform3D] = room.room_seat_transforms()
	check("six places on the car's two benches, the viewer's at the origin (the default seat)", seats.size() == 6
			and seats.any(func(t: Transform3D) -> bool: return t.origin.length() < 0.01))
	var sc: Dictionary = doc["screen"]
	check("the screen big and far, over the windscreen", float(sc["size"][0]) >= 20.0
			and float(sc["center"][2]) < -40.0 and float(sc["center"][1]) - float(sc["size"][1]) * 0.5 > 1.2)

	# Dusk to stars over the film; the stars turn; the Milky Way as the film plays.
	var sky: Node = h.system("sky")
	h.signals.fake("film.minutes", 0.0)
	h.signals.fake("playback.playing", 0.0)
	for i in 60:
		h.step(0.1)
	var dusk0 := float(sky.params["dusk"])
	var hour0 := float(sky.params["hour"])
	var milky0 := float(sky.params["milky_way"])
	check("before the film: the last light of the evening (dusk %.2f)" % dusk0, dusk0 < 0.05)
	h.signals.fake("film.minutes", 40.0)
	h.signals.fake("playback.playing", 1.0)
	for i in 300:
		h.step(0.1)
	check("forty minutes in: full night (dusk %.2f)" % float(sky.params["dusk"]), float(sky.params["dusk"]) > 0.95)
	check("the stars turned with the film (hour %.2f to %.2f)" % [hour0, float(sky.params["hour"])],
			float(sky.params["hour"]) > hour0 + 0.4)
	check("the Milky Way brighter as the film plays (%.2f to %.2f)" % [milky0, float(sky.params["milky_way"])],
			float(sky.params["milky_way"]) > milky0 + 0.4)
	check("mesas round the horizon", (h.system("vista").params["items"] as Array).filter(
			func(it: Dictionary) -> bool: return it["shape"] == "mesas").size() >= 2)
	h.signals.clear_fakes()

	# Moths in the beam, a plane now and then; Ambient life shows here.
	check("moths in the projector's beam", str(h.system("moths").params["creature"]) == "moth"
			and bool(h.system("screen_frame").params["beam"]))
	check("a plane's lights", str(h.system("planes").params["creature"]) == "plane")
	check("Ambient life shows here", room.common_applies("life"))

	# The window speaker: off by default (the film's own sound and the film layer kept), on: the window speaker.
	var pres: Node = h.system("presentation")
	check("Window speaker off by default: no speaker, no picture stage", str(pres.value("speaker")) == "none"
			and not pres.picture_on())
	h.set_setting("tinny", true)
	check("Window speaker on: the window speaker (%s), still no picture stage" % pres.value("speaker"),
			str(pres.value("speaker")) == "window" and not pres.picture_on())
	h.set_setting("tinny", false)
	check("and off again", str(pres.value("speaker")) == "none")

	# The car's lamps: off for the film, the dials dimmed; the headlamps on after the end.
	var car: Node = h.system("car")
	h.snapshot_override = {"open": false}
	for i in 40:
		h.step(0.05)
	check("the pre-show: headlamps off, the dials lit", is_zero_approx(float(car.params["headlamps"]))
			and float(car.params["dial_glow"]) > 0.45)
	h.snapshot_override = {"open": true, "playing": true, "position": 0.1, "duration": 6000.0}
	for i in 100:
		h.step(0.05)
	check("in the film: the dials dimmed (%.2f)" % float(car.params["dial_glow"]), float(car.params["dial_glow"]) < 0.2)
	h.snapshot_override = {"open": true, "playing": false, "position": 6000.0, "duration": 6000.0, "ended": true}
	for i in 100:
		h.step(0.05)
	check("after the end: the headlamps on, time to go (%.2f)" % float(car.params["headlamps"]),
			float(car.params["headlamps"]) > 1.0)

	# The sound: crickets round the car, a far freight train now and then (its horn in it), the open air.
	var bus := RoomSound.on_room_bus(room, ["crickets", "train"])
	check("the crickets and the train on the room's bus, under Environment (the slider, the duck, Ambience) %s"
			% [bus], bus.is_empty())
	var ac := RoomSound.acoustics(room, "outdoors", 0.2)
	check("the open air's acoustics (rt60 0.2) %s" % [ac], ac.is_empty())
	var crickets: Node = h.system("crickets")
	var round_ok: bool = crickets.players().size() == 4
	for q: Node3D in crickets.players():
		round_ok = round_ok and absf(Vector2(q.position.x, q.position.z).length() - 8.0) < 0.01
	check("crickets round the car: four voices 8 m out", crickets.is_loop() and crickets.playing() and round_ok)
	var train: Node = h.system("train")
	check("the train every 15 minutes or so, a one-shot of its own bed (no cue sound)", not train.is_loop()
			and is_equal_approx(float(train.params["every"]), 900.0) and float(train.params["reach"]) >= 300.0
			and (doc["cues"] as Array).all(func(c: Dictionary) -> bool: return (c["steps"] as Array).all(
				func(s: Dictionary) -> bool: return not s.has("sound"))))
	check("the train waits for its time", train.players().is_empty())
	h.snapshot_override = {"open": true, "playing": true, "position": 600.0, "duration": 6000.0}
	for i in 80:
		h.step(0.05)
	h.do_action("train.play", {})
	h.step(0.05)
	var engine: Array = train.players()
	check("it comes by far off (%s)" % [engine.map(func(p: Node) -> float: return (p as Node3D).position.length())],
			train.playing() and train.plays == 1 and engine.size() == 1
			and (engine[0] as Node3D).position.length() > 300.0)
	check("in the film the train sits 8 dB under its level (%.1f dB)" % train.designed_db(),
			absf(train.designed_db() - (-60.0)) < 0.2)
	check("the window speaker still off by default", str(pres.value("speaker")) == "none")
	# The quality pass: a soft wind over the lot, and the far highway's car heard as its lights go by behind.
	var more := RoomSound.on_room_bus(room, ["wind", "far_car"])
	check("the wind and the far car on the room's bus %s" % [more], more.is_empty())
	var wind: Node = h.system("wind")
	check("a soft wind bed (%.1f dB in the film)" % wind.designed_db(), wind.is_loop() and wind.playing()
			and wind.designed_db() < -65.0)
	var far: Node = h.system("far_car")
	var road_cue: Dictionary = (doc["cues"] as Array).filter(
			func(c: Dictionary) -> bool: return c["name"] == "road")[0]
	check("the road cue drives the lights one way and plays the far car with them",
			(road_cue["steps"] as Array).any(func(s: Dictionary) -> bool: return str(s.get("do", "")) == "far_car.play")
			and (road_cue["steps"] as Array).any(func(s: Dictionary) -> bool:
				return str(s.get("do", "")) == "lot.car_passes" and float((s.get("args", {}) as Dictionary).get("way",
						0.0)) == 1.0))
	h.do_action("lot.car_passes", {"way": 1})
	h.do_action("far_car.play", {})
	for i in 200:
		h.step(0.05)
	var lit: Variant = h.system("lot").passing_car()
	var heard: Array = far.players().map(func(p: Node) -> Vector3: return (p as Node3D).position)
	check("the far car's sound rides with its lights behind the lot (%s / %s)" % [lit, heard],
			lit is Vector3 and heard.any(func(q: Vector3) -> bool: return q.distance_to(lit) < 40.0 and q.z > 60.0))
	check("the far car a one-shot only the cue plays, as long as the lights' run (%.1f s)"
			% EnvSynth.stream("far_car").get_length(), not far.is_loop() and float(far.params["every"]) == 0.0
			and absf(EnvSynth.stream("far_car").get_length() - 34.0) < 0.1)
	var lv: Dictionary = await RoomSound.levels(self, room, "Drive-in")
	for v: Array in RoomSound.verdicts("Drive-in", lv):
		check(v[0], v[1])
	await done(room)
	await _render(doc)


## The quality pass (2026-11-08: "aim for incredible quality", the user): the whole drive-in round the car, the car
## itself, the light, the sky.
func _drive_in(room: Node3D, _doc: Dictionary) -> void:
	var h: Node = room.host
	var lot: Node = h.system("lot")
	var car: Node = h.system("car")
	var DI: GDScript = lot.DriveInLot
	for n: String in ["Ground", "Posts", "Structures", "TowerFrame", "RampLights", "Neon", "NeonGlow", "SnackWindows",
			"MarqueeBoard", "Bulbs", "ParkedCars", "Road", "Car", "Wheel", "Dials", "Windscreen", "Lamps"]:
		check("the drive-in's %s" % n, room.get_node_or_null(n) != null)
	# The cars parked round the viewer's: on the rows' arcs, facing the screen's side, none in the viewer's bay, the
	# bays beside it or straight ahead; dark paint; the sight-line check takes them where they stand.
	var mmi := room.get_node("ParkedCars") as MultiMeshInstance3D
	var mm := mmi.multimesh
	var placed: Array = mmi.get_meta("env_placed", [])
	var colours: Array = mmi.get_meta("colours", [])
	check("cars parked (%d)" % mm.instance_count, mm.instance_count >= 20
			and mm.instance_count == int(lot.params["cars"]) and placed.size() == mm.instance_count)
	var clear := true
	var facing := true
	var dark := true
	for i in placed.size():
		var t: Transform3D = placed[i]
		if Vector2(t.origin.x, t.origin.z).length() < 4.5 or (absf(t.origin.x) < 1.5 and t.origin.z > -9.0
				and t.origin.z < 0.0):
			clear = false
		var to_centre := Vector3(0.0, 0.0, DI.CENTRE_Z) - Vector3(t.origin.x, 0.0, t.origin.z)
		if (-t.basis.z).normalized().dot(to_centre.normalized()) < 0.99:
			facing = false
		if (colours[i] as Color).get_luminance() > 0.35:
			dark = false
		if absf(t.origin.y - 0.0) > 0.01:
			clear = false
	check("none beside the viewer or straight ahead, all on the ground", clear)
	check("every car faces the rows' centre (the screen)", facing)
	check("their paint dark: shapes with chrome glints at night", dark)
	# A post beside the viewer's front seats, its speaker in the car on the left door, its cable to the post.
	var ours := false
	for e: Array in DI.posts(-0.5):
		if (e[0] as Vector3).distance_to(Vector3(-1.75, -0.5, -0.3)) < 0.1:
			ours = true
	check("the viewer's post beside the left door", ours)
	check("the speaker hung on the left door", bool(car.params["speaker"]))
	# The car: lacquer and chrome on the reflecting shader, their sky from the sky system as dusk falls.
	var mats: Array = car.reflective_materials()
	var Reflect: GDScript = load("res://scripts/env/systems/kit/reflect.gd")
	check("the paint and the chrome reflect", mats.size() == 2 and mats.all(func(m: ShaderMaterial) -> bool:
			return m.shader == Reflect.SHADER and float(m.get_shader_parameter("reflect_amount")) > 0.5))
	check("the chrome is chrome, the paint a clear coat", float(mats[1].get_shader_parameter("reflect_metal")) > 0.9
			and float(mats[0].get_shader_parameter("reflect_metal")) < 0.1)
	h.signals.fake("film.minutes", 0.0)
	for i in 40:
		h.step(0.1)
	var z0: Color = mats[0].get_shader_parameter("refl_horizon")
	h.signals.fake("film.minutes", 40.0)
	for i in 300:
		h.step(0.1)
	var z1: Color = mats[0].get_shader_parameter("refl_horizon")
	check("the sky in the paint darkens with the dusk (%s to %s)" % [z0, z1], z1.get_luminance() < z0.get_luminance())
	var dials := (room.get_node("Dials") as MeshInstance3D).mesh.surface_get_material(0) as ShaderMaterial
	check("the clock on the dash keeps the sky's time (%.2f, %.2f)" % [float(dials.get_shader_parameter("hour")),
			float(h.system("sky").hour_shown())], absf(float(dials.get_shader_parameter("hour"))
			- float(h.system("sky").hour_shown())) < 0.01)
	h.signals.clear_fakes()
	check("the dials light the cabin: a stand-in lamp under the dash", int(h.system("light").lamp_count()) >= 3)
	# The beam: light in hazy air, a closed pyramid from the booth's port.
	h.on_screen_changed(room.get_screen_anchor(), Vector2(24.0, 10.0))
	var beam := room.get_node_or_null("Beam/Cone") as MeshInstance3D
	var faces := beam.mesh.get_faces().size() if beam != null and beam.mesh != null else 0
	check("the beam: the volume's shader on a closed pyramid (%d vertices)" % faces,
			str(h.system("screen_frame").params["beam_style"]) == "volume" and faces == 18)
	# The sky's finer dusk and night; desert plants outside the lot.
	var sky: Node = h.system("sky")
	check("the twilight's bands, the galaxy's dust, an evening star", float(sky.params["afterglow"]) > 0.5
			and float(sky.params["milky_detail"]) > 0.5 and float(sky.params["evening_star"]) > 0.0)
	var outside := true
	var plants := 0
	for it: Dictionary in h.system("vista").built:
		if str(it["shape"]) != "cacti":
			continue
		plants += int(it["count"])
		for fa: float in [-0.5, 0.5]:
			for fd: float in [-0.5, 0.5]:
				var az := deg_to_rad(float(it["azimuth"]) + fa * float(it["spread"]))
				var dist := float(it["distance"]) + fd * float(it["depth"])
				var p := Vector2(sin(az) * dist, -cos(az) * dist - DI.CENTRE_Z)
				var a := rad_to_deg(atan2(absf(p.x), p.y))
				if p.length() < DI.R_BACK + 2.0 and p.y > 0.0 and a < DI.FAN_DEG + 3.0:
					outside = false
	check("desert plants round the lot (%d), none inside its fence" % plants, plants >= 40 and outside)
	# The lit things and their cues: the marquee's bulbs chase before the film and hold still in it, the neon and the
	# ramp lights come down for the film and up after it.
	h.snapshot_override = {"open": false}
	for i in 60:
		h.step(0.1)
	check("the pre-show: the bulbs chase, the neon full", float(lot.params["chase"]) > 0.9
			and float(lot.params["neon"]) > 0.9)
	h.snapshot_override = {"open": true, "playing": true, "position": 30.0, "duration": 6000.0}
	for i in 120:
		h.step(0.1)
	check("in the film: the bulbs steady, the neon and the ramp lights down (%.2f, %.2f, %.2f)" % [
			float(lot.params["chase"]), float(lot.params["neon"]), float(lot.params["ramp_lights"])],
			float(lot.params["chase"]) < 0.05 and float(lot.params["neon"]) < 0.7
			and float(lot.params["ramp_lights"]) < 0.4)
	var neon := (room.get_node("Neon") as MeshInstance3D).mesh.surface_get_material(0) as ShaderMaterial
	check("the neon's glow follows (%.2f)" % float(neon.get_shader_parameter("energy")),
			float(neon.get_shader_parameter("energy")) < 2.2)
	# A car's lights on the road far behind, now and then; never in front of the viewer.
	h.do_action("lot.car_passes", {})
	var seen: Array = []
	for i in 400:
		h.step(0.1)
		var p: Variant = lot.passing_car()
		if p != null:
			seen.append(p)
	var behind := seen.all(func(p: Vector3) -> bool: return p.z > 60.0)
	check("a car went by on the road behind (%d frames), far behind the lot" % seen.size(), seen.size() > 100
			and behind and lot.passing_car() == null)


## Pictures under lavapipe (skipped headless): from the viewer's eyes as main.gd places them (SEAT_RISE 0.1 up,
## SEAT_NEARER: 0.25 m nearer the screen), in the pre-show and with a film playing, looking ahead, round, up and back.
func _render(doc: Dictionary) -> void:
	if not RoomRender.has_renderer():
		print("SKIP render (headless)")
		return
	var sc: Array = doc["screen"]["center"]
	var screen := Vector3(float(sc[0]), float(sc[1]), float(sc[2]))
	var eye := Vector3(0, 1.3, -0.25)
	# The pre-show: the last light of the evening, the room light up.
	RoomRender.set_light(screen, 0.03)
	var vc := await RoomRender.open(self, doc)
	var host: Node = (vc[2] as Node).host
	host.snapshot_override = {"open": false}
	host.signals.fake("film.minutes", 0.0)
	host.signals.fake("playback.playing", 0.0)
	for i in 80:
		host.step(0.25)
	await RoomRender.shot(self, vc, eye, screen, "drive_in_preshow")
	await RoomRender.shot(self, vc, eye, eye + Vector3(-0.9, -0.05, -0.5), "drive_in_preshow_left")
	await RoomRender.shot(self, vc, eye, eye + Vector3(0.0, -0.2, 1.0), "drive_in_preshow_back")
	await RoomRender.shot(self, vc, eye, eye + Vector3(0.0, -0.55, -0.6), "drive_in_preshow_dash")
	# The film playing, a few minutes in (dusk half fallen) and later (full night): the room light down.
	RoomRender.set_light(screen, 0.012)
	host.signals.fake("film.brightness", 0.6)
	host.signals.fake("playback.playing", 1.0)
	host.snapshot_override = {"open": true, "playing": true, "position": 360.0, "duration": 7200.0}
	host.signals.fake("film.minutes", 6.0)
	for i in 120:
		host.step(0.25)
	await RoomRender.shot(self, vc, eye, screen, "drive_in_dusk")
	host.signals.fake("film.minutes", 50.0)
	for i in 200:
		host.step(0.25)
	await RoomRender.shot(self, vc, eye, screen, "drive_in_night")
	await RoomRender.shot(self, vc, eye, eye + Vector3(-0.9, 0.0, -0.45), "drive_in_night_left")
	await RoomRender.shot(self, vc, eye, eye + Vector3(0.95, 0.05, -0.3), "drive_in_night_right")
	await RoomRender.shot(self, vc, eye, eye + Vector3(0.2, 1.0, -0.3), "drive_in_night_up")
	await RoomRender.shot(self, vc, eye, eye + Vector3(0.0, 0.05, 1.0), "drive_in_night_back")
	await RoomRender.shot(self, vc, eye, eye + Vector3(0.0, -0.55, -0.6), "drive_in_night_dash")
	var side := Vector3(0.55, 0, 1.12)
	await RoomRender.shot(self, vc, side + Vector3(0, 1.3, -0.25), screen, "drive_in_night_rear_seat")
	await RoomRender.close(self, vc)
