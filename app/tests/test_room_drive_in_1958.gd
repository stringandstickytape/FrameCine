extends "res://tests/env_builder_harness.gd"

## Drive-in, 1958 (app/environments/drive_in_1958.env.json; docs/environments.md, "Room: Drive-in - 1958"): the
## viewer on the front bench of a convertible on a drive-in's lot in the desert. The room is its document alone (the
## older drive-in scene stays as it was) and passes the checks (schema, budget, sight lines from every seat, comfort,
## licences, names, no people) and the car's builder conventions. What makes it the drive-in: the lot with its screen
## tower and a neon snack bar behind, the car, dusk falling to a starry night over the film's first minutes and the
## stars turning through it, mesas round the horizon, moths in the projector's beam, a plane's lights now and then,
## the Window speaker setting (off by default: the film's own sound; on: the window speaker), and the car's lamps:
## off for the film, the dials dimmed, the headlamps on again after the end.
## godot --headless --xr-mode off --path app --script res://tests/test_room_drive_in_1958.gd

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
	await done(room)
