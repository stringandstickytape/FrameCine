extends "res://tests/env_builder_harness.gd"

## Screen 3, 1983 (app/environments/screen_3_1983.env.json; docs/environments.md, "Room: Screen 3 - 1983"): the old
## circle of a picture palace walled off into a small multiplex screen. The room is its document alone and passes the
## checks (schema, budget, sight lines from every seat, comfort, licences, names, no people). What makes it Screen 3:
## the hall's plasterboard partition with the screen on it, the swirling carpet, multiplex seats with one broken in
## the row in front, the water stain on the new wall, smoke in the beam, the worn print (its Weave and tilt setting
## moves the weave and the tilt, the Motion setting scales them), the exit sign that flickers now and then (held by
## Flickering lights off), and the house lamps that go down for the film and come back up at the end. Its sound: the
## next screen's film rumbling through the wall with the film's bass, a small hall's acoustics, the level measured.
## godot --headless --xr-mode off --path app --script res://tests/test_room_screen_3_1983.gd

const RoomSound := preload("res://tests/room_sound_checks.gd")
const Procedural := preload("res://scripts/env/systems/kit/procedural.gd")
const PATH := "res://environments/screen_3_1983.env.json"
const BROKEN := 69


func run_tests() -> void:
	test_name = "test_room_screen_3_1983"
	var r := EnvDoc.load_file(PATH)
	check("the document reads %s" % [r["errors"]], (r["errors"] as Array).is_empty())
	var doc: Dictionary = r["doc"]
	check("a cinema in the Room tab", str(doc["room"].get("category", "")) == "cinema")
	var listed: Array = load("res://scripts/env/env_library.gd").document_rooms().map(
			func(e: Array) -> String: return str(e[0]))
	check("listed as a room by its document (%s)" % [listed], listed.has("screen_3_1983"))
	var room := await check_room("Screen 3", doc)
	var h: Node = room.host
	h.auto = false
	for sid: String in ["light", "hall", "kit", "seats", "screen_frame", "atmosphere", "presentation"]:
		check("system %s built" % sid, h.system(sid) != null)
	var hall: Node = h.system("hall")

	# The subdivided hall: a partition across it with the screen on its plasterboard face.
	var screen_z := float(doc["screen"]["center"][2])
	check("the partition across the hall", room.get_node_or_null("Partition") != null
			and float(hall.params["partition_z"]) < screen_z)
	check("the kit placed its pieces (%s)" % [h.system("kit").problems()], h.system("kit").problems().is_empty()
			and room.get_node_or_null("PieceStatic") != null)
	var floor_m := (room.get_node("Floor") as MeshInstance3D).mesh.surface_get_material(0) as ShaderMaterial
	check("the swirling carpet on the floor", floor_m != null
			and floor_m.get_shader_parameter("normal_map") == Procedural.maps("swirl_carpet")["normal"])
	check("multiplex seats", str(hall.params["seat_model"]) == "multiplex")

	# The viewer's own seat, and the broken one in the row in front.
	var seats: Array[Transform3D] = room.room_seat_transforms()
	check("the viewer's own seat at the origin (the default seat)", seats.any(
			func(t: Transform3D) -> bool: return t.origin.length() < 0.01))
	var drawn: Array = h.system("seats").drawn()
	check("one broken multiplex seat (%d)" % drawn.size(), drawn.size() == 1 and drawn[0]["model"] == "multiplex"
			and drawn[0]["form"] == "broken")
	var b: Vector3 = seats[BROKEN].origin
	check("the broken seat in the row in front, a little to the left (%s)" % b, b.z < -0.5 and b.z > -1.5
			and b.x < -0.5 and b.x > -2.0)

	# Smoke in the beam; the worn print.
	var air: Node = h.system("atmosphere")
	check("haze and smoke in the beam", float(air.params["beam_haze"]) > 0.3 and float(air.params["beam_smoke"]) > 0.3)
	var pres: Node = h.system("presentation")
	check("the worn print: a film source, dust, scratches, a flicker; the film drawn in the room",
			str(pres.value("source")) == "film" and float(pres.value("dust")) > 0.0
			and float(pres.value("scratches")) > 0.0 and float(pres.value("flicker")) > 0.0 and pres.picture_on())
	check("weave and tilt at the setting's default (%s, %s)" % [pres.params["weave"], pres.params["tilt"]],
			is_equal_approx(float(pres.params["weave"]), 0.7) and is_equal_approx(float(pres.params["tilt"]), 0.35))
	h.set_setting("weave", 0.0)
	check("Weave and tilt at 0: steady and straight", is_zero_approx(float(pres.params["weave"]))
			and is_zero_approx(float(pres.params["tilt"])))
	h.set_setting("weave", 1.0)
	check("Weave and tilt at full (%s, %s)" % [pres.params["weave"], pres.params["tilt"]],
			is_equal_approx(float(pres.params["weave"]), 1.0) and is_equal_approx(float(pres.params["tilt"]), 0.5))
	h.set_setting("motion", 0.5)
	check("the Motion setting halves them", is_equal_approx(float(pres.params["weave"]), 0.5)
			and is_equal_approx(float(pres.params["tilt"]), 0.25))
	h.set_setting("motion", 1.0)
	h.set_setting("weave", 0.7)
	check("the common settings that show here: Flickering lights and Motion", room.common_applies("flicker")
			and room.common_applies("motion") and not room.common_applies("life"))

	# The house lamps: down for the film, up at the end.
	h.snapshot_override = {"open": false}
	h.step(0.05)
	h.snapshot_override = {"open": true, "playing": true, "position": 0.1, "duration": 6000.0}
	h.step(0.05)
	check("starting: %s" % h.timeline.state, h.timeline.state == "starting")
	for i in 100:
		h.step(0.05)
	check("the house lamps down in the film (%.2f)" % float(h.param("light.house_lamps")),
			float(h.param("light.house_lamps")) < 0.1)
	h.snapshot_override = {"open": true, "playing": false, "position": 6000.0, "duration": 6000.0, "ended": true}
	for i in 100:
		h.step(0.05)
	check("the house lamps up after the end (%.2f)" % float(h.param("light.house_lamps")),
			float(h.param("light.house_lamps")) > 0.95)
	# With Dim during the film off, they stay up.
	h.set_setting("dim", false)
	h.snapshot_override = {"open": true, "playing": true, "position": 0.1, "duration": 6000.0}
	for i in 100:
		h.step(0.05)
	check("Dim during the film off: the lamps stay up (%.2f)" % float(h.param("light.house_lamps")),
			float(h.param("light.house_lamps")) > 0.95)
	h.set_setting("dim", true)

	# The exit sign: it stutters now and then; steady with Flickering lights off.
	var cue: Dictionary = {}
	for c: Dictionary in doc["cues"]:
		if c["name"] == "exit_sign":
			cue = c
	check("the exit sign's cue comes every so often, by chance", cue.get("when", {}).has("every")
			and float(cue.get("chance", 1.0)) < 1.0)
	h.set_setting("flicker", false)
	check("Flickering lights off: the exit sign's cue may not fire", not h.timeline.allowed(cue))
	h.set_setting("flicker", true)
	check("Flickering lights on: it may", h.timeline.allowed(cue))
	h.timeline.run_cue("exit_sign")
	var low := 1.0
	for i in 60:
		h.step(0.05)
		low = minf(low, float(h.param("light.signs")))
	check("the exit sign dips (to %.2f) and comes back (%.2f)" % [low, float(h.param("light.signs"))], low < 0.5
			and float(h.param("light.signs")) > 0.95)

	# The sound: the next screen's film rumbling through the left wall, following the film's bass; a small hall.
	var bus := RoomSound.on_room_bus(room, ["next_screen"])
	check("the rumble on the room's bus, under Environment (the slider, the duck, Ambience) %s" % [bus], bus.is_empty())
	var ac := RoomSound.acoustics(room, "small_room", 0.6)
	check("a small hall's acoustics (rt60 0.6) %s" % [ac], ac.is_empty())
	var wall: Node = h.system("next_screen")
	check("the wall's rumble keeps its level in the film (film_db 0)", str(wall.params["sound"]) == "wall_rumble"
			and is_zero_approx(float(wall.params["film_db"])))
	h.snapshot_override = {"open": true, "playing": true, "position": 600.0, "duration": 6000.0}
	h.signals.fake("film.bass", 0.0)
	for i in 40:
		h.step(0.05)
	check("no bass in the film: the wall is quiet (%.3f)" % float(wall.params["level"]), not wall.playing())
	h.signals.fake("film.bass", 0.8)
	for i in 40:
		h.step(0.05)
	var through: Array = wall.players()
	check("the film's bass: the wall rumbles (%.2f), from the left wall" % float(wall.params["level"]),
			wall.playing() and absf(float(wall.params["level"]) - 0.8) < 0.05 and through.size() == 1
			and (through[0] as Node3D).position.x < -5.0)
	h.signals.clear_fakes()
	var lv: Dictionary = await RoomSound.levels(self, room, "Screen 3", {"film.bass": 0.8})
	for v: Array in RoomSound.verdicts("Screen 3", lv):
		check(v[0], v[1])
	await done(room)
