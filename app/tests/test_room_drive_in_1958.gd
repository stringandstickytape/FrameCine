extends "res://tests/env_builder_harness.gd"

## Drive-in, 1958 (app/environments/drive_in_1958.env.json; docs/environments.md, "Room: Drive-in - 1958"): the
## viewer on the front bench of a convertible on a drive-in's lot in the desert. The room is its document alone (the
## older drive-in scene stays as it was) and passes the checks (schema, budget, sight lines from every seat, comfort,
## licences, names, no people) and the car's builder conventions. What makes it the drive-in: the lot with its screen
## tower and a neon snack bar behind, the car, dusk falling to a starry night over the film's first minutes and the
## stars turning through it, mesas round the horizon, moths in the projector's beam, a plane's lights now and then,
## the Window speaker setting (off by default: the film's own sound; on: the window speaker), and the car's lamps:
## off for the film, the dials dimmed, the headlamps on again after the end. Its sound: crickets round the car, a far
## freight train now and then, the open air's acoustics, the level measured (with the train passing).
## godot --headless --xr-mode off --path app --script res://tests/test_room_drive_in_1958.gd

const RoomSound := preload("res://tests/room_sound_checks.gd")
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
	for sid: String in ["light", "lot", "car", "kit", "screen_frame", "sky", "vista", "moths", "planes",
			"presentation"]:
		check("system %s built" % sid, h.system(sid) != null)

	# The lot, the tower, the snack bar; the viewer on the car's front bench.
	var lot: Node = h.system("lot")
	check("the terrace as a drive-in's lot, the screen on the kit's tower", str(lot.params["style"]) == "lot"
			and str(lot.params["screen"]) == "none")
	check("the kit placed its pieces (%s)" % [h.system("kit").problems()], h.system("kit").problems().is_empty())
	check("a neon sign over the snack bar", room.get_node_or_null("Sign0") != null)
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
	var lv: Dictionary = await RoomSound.levels(self, room, "Drive-in")
	for v: Array in RoomSound.verdicts("Drive-in", lv):
		check(v[0], v[1])
	await done(room)
