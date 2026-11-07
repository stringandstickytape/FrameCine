extends "res://tests/env_builder_harness.gd"

## The Bathysphere (app/environments/bathysphere.env.json; docs/environments.md, "Room: Bathysphere"): a glass dome
## hall in deep water. Built headless from its document and checked as every shipped room is (schema, budget, sight
## lines, comfort, licences, names, no people) and as a builder's room (seats, physics, bake, seat picking); then what
## makes it this room: the glass looks out on dark water, the screen stands inside the glass, the fish and the glowing
## creatures stay outside the glass and come nearer in a bright scene, the whale passes in a quiet scene as often as
## the Whale setting says (never; rarely; sometimes) and never more than its cooldown allows, the house lamps go down
## with the film, no cue sounds but the whale's song; the hull's acoustics, its creaks to either side now and then and
## the deep's hum on the room's bus, under the level check's target and far under a film (tests/room_sound.gd).
## Under lavapipe it draws the room from its own seat.
## godot --headless --xr-mode off --path app --script res://tests/test_room_bathysphere.gd

const RoomRender := preload("res://tests/room_render.gd")
const RoomSound := preload("res://tests/room_sound.gd")
const DOC := "res://environments/bathysphere.env.json"


func run_tests() -> void:
	test_name = "test_room_bathysphere"
	var r := EnvDoc.load_file(DOC)
	check("the document reads (%s)" % [r["errors"]], (r["errors"] as Array).is_empty())
	var doc: Dictionary = r["doc"]
	if doc.is_empty():
		return
	var room := await check_room("bathysphere", doc, "hall")
	var host: Node = room.host
	host.auto = false
	var hall: Node = host.system("hall")
	var p: Dictionary = hall.params
	check("a glass dome looking out on water", str(p["dome"]) == "glass" and str(p["outside"]) == "water"
			and room.get_node_or_null("Outside") != null)
	var panes := room.get_node_or_null("Panes")
	check("the panes are glass the sight line looks through", panes != null and panes.is_in_group("env_see_through"))
	var deep: Color = hall.color_param("water_deep")
	var top: Color = hall.color_param("water_top")
	check("the water is dark blue-black (%s, %s)" % [top, deep], top.get_luminance() < 0.15 and top.b > top.r * 3.0
			and deep.get_luminance() < 0.02)
	# The screen stands inside the glass: its corners under the dome.
	var sc: Dictionary = doc["screen"]
	var c := Vector3(float(sc["center"][0]), float(sc["center"][1]), float(sc["center"][2]))
	var half := Vector2(float(sc["size"][0]), float(sc["size"][1])) * 0.5
	var corners_in := true
	for k: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		if not _inside_dome(p, c + Vector3(k.x * half.x, k.y * half.y, 0), 0.1):
			corners_in = false
	check("the screen stands inside the glass", corners_in)
	check("the screen is the builder's", is_equal_approx(float(hall.screen()["center"][2]), c.z))
	var seats: Array[Transform3D] = room.room_seat_transforms()
	check("seats on arcs round the screen (%d), the room's own at the origin" % seats.size(), seats.size() > 30
			and seats.any(func(t: Transform3D) -> bool: return t.origin.length() < 0.05))
	# Life outside the glass, drawn nearer the screen in a bright scene.
	var kinds := {}
	for id: String in ["fish", "shoal", "glow", "whale"]:
		var s: Node = host.system(id)
		kinds[id] = str(s.params["creature"]) if s != null else ""
	check("fish, a second shoal, glowing creatures and a whale (%s)" % [kinds], kinds["fish"] == "fish"
			and kinds["shoal"] == "fish" and kinds["glow"] == "jelly" and kinds["whale"] == "whale")
	host.snapshot_override = {"open": true, "playing": true, "position": 900.0, "duration": 7200.0}
	host.signals.fake("film.quiet", 0.0)
	var outside_ok := true
	var near_dark := 0.0
	var near_bright := 0.0
	for phase: float in [0.0, 1.0]:
		host.signals.fake("film.brightness", phase)
		for i in 240:
			host.step(0.25)
			if i % 8 == 0:
				for id: String in ["fish", "shoal", "glow"]:
					for q: Vector3 in host.system(id).positions():
						if _inside_dome(p, q, 0.3) or q.distance_to(_centre(p)) > _water_radius(p):
							outside_ok = false
		var d := 0.0
		for id: String in ["fish", "shoal", "glow"]:
			d += _mean_distance(host.system(id).positions(), c)
		if phase == 0.0:
			near_dark = d
		else:
			near_bright = d
	check("fish and glowing creatures keep outside the glass, inside the water's sphere", outside_ok)
	check("they come nearer the screen in a bright scene (%.1f m to %.1f m)" % [near_dark, near_bright],
			near_bright < near_dark - 0.5)
	check("the fish's attraction follows the film's brightness", float(host.system("fish").params["attraction"]) > 0.8)
	# The whale: only in a quiet scene, as often as the setting says, at most once in its cooldown.
	var whale: Node = host.system("whale")
	var path_ok := true
	for q: Variant in whale.params["path"]:
		var v := Vector3(float(q[0]), float(q[1]), float(q[2]))
		if _inside_dome(p, v, 2.0) or v.distance_to(_centre(p)) > _water_radius(p) - 1.0:
			path_ok = false
	check("the whale's way runs outside the glass, inside the water", path_ok)
	check("the Whale setting: never, rarely, sometimes; rarely by default",
			str(host.setting("whale")) == "rare")
	host.rng.seed = 7
	var counts := {}
	for choice: String in ["never", "rare", "sometimes"]:
		host.set_setting("whale", choice)
		counts[choice] = await _quiet_scenes(host, 24, false)
	check("never: no whale in 24 quiet scenes", counts["never"] == 0)
	check("rarely and sometimes: a whale, at most once in the cooldown (%s)" % [counts],
			counts["rare"] == 1 and counts["sometimes"] == 1)
	var loud := await _quiet_scenes(host, 6, true)
	check("no whale in a loud scene", loud == 0)
	var cues := {}
	for cue: Dictionary in doc["cues"]:
		cues[cue["name"]] = cue
	check("rarely: a smaller chance and a longer cooldown than sometimes",
			float(cues["whale_rare"]["chance"]) < float(cues["whale_sometimes"]["chance"])
			and float(cues["whale_rare"]["cooldown"]) > float(cues["whale_sometimes"]["cooldown"])
			and float(cues["whale_sometimes"]["cooldown"]) >= 900.0)
	# The whale outside the glass while it passes, and it sings.
	host.set_setting("whale", "sometimes")
	var sung: int = whale.events.size()
	host.do_action("whale.pass", {})
	var whale_out := true
	var seen := 0
	for i in 400:
		host.step(0.25)
		for q: Vector3 in whale.positions():
			seen += 1
			if _inside_dome(p, q, 2.0):
				whale_out = false
	check("the whale passes outside the glass (%d samples)" % seen, seen > 0 and whale_out)
	check("it sings as it passes", whale.events.size() > sung)
	# The house lamps go down with the film, and up again.
	host.timeline.state = ""
	host.snapshot_override = {"open": false}
	for i in 30:
		host.step(0.25)
	var up := float(host.param("light.house_lamps"))
	host.snapshot_override = {"open": true, "playing": true, "position": 0.5, "duration": 7200.0}
	for i in 30:
		host.step(0.25)
	var down := float(host.param("light.house_lamps"))
	check("the house lamps dim with the film (%.2f to %.2f)" % [up, down], up > 0.95 and down < 0.2)
	host.snapshot_override = {"open": true, "playing": false, "ended": true, "position": 7200.0, "duration": 7200.0}
	for i in 30:
		host.step(0.25)
	check("and come up at the end", float(host.param("light.house_lamps")) > 0.95)
	# Sound: no cue sounds but the whale's song (life's); the hull's ring, its creaks to the sides now and then, the
	# deep's low hum.
	var other: Array = host.sounds.filter(func(s: Variant) -> bool: return not str(s).contains("whale"))
	check("no cue sound but the whale's (%s)" % [other], other.is_empty())
	check("the whale sings at voice_db -4", is_equal_approx(float(host.system("whale").params["voice_db"]), -4.0))
	RoomSound.check_beds(self, "bathysphere", room, {"creak_left": "hull_creak", "creak_right": "hull_creak",
			"deep": "deep_hum"}, "hull")
	var reverb: Dictionary = host.system_of_kind("sound").values()
	check("a small hard room of metal and glass (rt60 %.1f)" % float(reverb["rt60"]),
			absf(float(reverb["rt60"]) - 0.9) < 0.01)
	var left: Node = host.system("creak_left")
	var right: Node = host.system("creak_right")
	check("the creaks to either side (x %.1f, %.1f)" % [float(left.params["at"][0]), float(right.params["at"][0])],
			float(left.params["at"][0]) < -5.0 and float(right.params["at"][0]) > 5.0)
	var l0: int = left.plays
	var r0: int = right.plays
	for i in 900:
		host.step(0.5)
	check("in 7.5 minutes the hull creaks now and then (%d left, %d right)" % [left.plays - l0, right.plays - r0],
			left.plays - l0 >= 2 and right.plays - r0 >= 2 and left.plays - l0 + right.plays - r0 <= 8)
	check("the deep's hum low (gain %.0f dB)" % float(host.system("deep").params["gain_db"]),
			float(host.system("deep").params["gain_db"]) < 0.0 and host.system("deep").playing())
	await done(room)
	await RoomSound.check_level(self, self, "bathysphere", doc)
	await _render(doc)


## Quiet scenes one after another (or loud ones): the film's quiet signal held for 6 s, then 30 s of sound. Returns how
## many times the whale cue fired.
func _quiet_scenes(host: Node, n: int, loud: bool) -> int:
	var before := _whale_fired(host)
	for k in n:
		host.signals.fake("film.quiet", 0.0 if loud else 1.0)
		for i in 24:
			host.step(0.25)
		host.signals.fake("film.quiet", 0.0)
		for i in 120:
			host.step(0.25)
	await process_frame
	return _whale_fired(host) - before


func _whale_fired(host: Node) -> int:
	return host.timeline.fired.filter(func(f: Array) -> bool: return str(f[0]).begins_with("whale")).size()


static func _centre(p: Dictionary) -> Vector3:
	return Vector3(0.0, float(p["floor_y"]), float(p["centre_z"]))


## The outside sphere's radius (dome_hall.gd _build_outside).
static func _water_radius(p: Dictionary) -> float:
	return maxf(float(p["radius"]) * 3.0, (float(p["drum_height"]) + float(p["dome_height"])) * 2.0)


## Whether q is under the dome (inside the drum's cylinder, or under the dome's ellipsoid), `margin` metres in.
static func _inside_dome(p: Dictionary, q: Vector3, margin: float) -> bool:
	var c := _centre(p)
	var r := float(p["radius"]) + margin
	var d := Vector2(q.x - c.x, q.z - c.z).length()
	var y := q.y - c.y
	if y < 0.0 or d > r:
		return false
	var drum := float(p["drum_height"])
	if y <= drum:
		return true
	var h := float(p["dome_height"]) + margin
	return pow(d / r, 2.0) + pow((y - drum) / h, 2.0) < 1.0


static func _mean_distance(points: Array, to: Vector3) -> float:
	if points.is_empty():
		return 0.0
	var s := 0.0
	for q: Vector3 in points:
		s += q.distance_to(to)
	return s / points.size()


func _render(doc: Dictionary) -> void:
	if not RoomRender.has_renderer():
		print("SKIP render (headless)")
		return
	var sc: Array = doc["screen"]["center"]
	var screen := Vector3(float(sc[0]), float(sc[1]), float(sc[2]))
	# The film playing: the room dimmed (the app's light follows playback), the house lamps down.
	RoomRender.set_light(screen, 0.015)
	var vc := await RoomRender.open(self, doc)
	var host: Node = (vc[2] as Node).host
	host.snapshot_override = {"open": true, "playing": true, "position": 0.5, "duration": 7200.0}
	host.signals.fake("film.brightness", 0.7)
	host.signals.fake("playback.playing", 1.0)
	for i in 120:
		host.step(0.25)
	var eye := Vector3(0, 1.2, 0)
	var img: Image = await RoomRender.shot(self, vc, eye, screen, "bathysphere_seat")
	var water := RoomRender.mean(img, Rect2(0.0, 0.0, 1.0, 0.12))
	print("  render: the water over the screen %s" % [water])
	check("from the seat: the water beyond the glass is dark blue (%s)" % [water], water.b > water.r
			and water.get_luminance() < 0.15)
	await RoomRender.shot(self, vc, eye, eye + Vector3(-0.8, 0.15, -0.6), "bathysphere_left")
	host.do_action("whale.pass", {"side": "left"})
	for i in 44:
		host.step(0.25)
	var at: Array = host.system("whale").positions()
	print("  render: the whale at %s" % [at])
	await RoomRender.shot(self, vc, eye, eye + Vector3(0.0, 0.55, -1.0), "bathysphere_whale")
	if not at.is_empty():
		(vc[1] as Camera3D).fov = 40.0
		img = await RoomRender.shot(self, vc, eye, at[0], "bathysphere_whale_close")
		var body := RoomRender.mean(img, Rect2(0.4, 0.4, 0.2, 0.2))
		var water_by := RoomRender.mean(img, Rect2(0.0, 0.0, 1.0, 0.1))
		print("  render: the whale %s against the water %s" % [body, water_by])
		check("the whale shows against the water (%.3f, %.3f)" % [body.get_luminance(), water_by.get_luminance()],
				absf(body.get_luminance() - water_by.get_luminance()) > 0.02)
		(vc[1] as Camera3D).fov = 90.0
	# Before the film: the house lamps up.
	RoomRender.set_light(screen, 0.04)
	host.snapshot_override = {"open": false}
	for i in 30:
		host.step(0.25)
	await RoomRender.shot(self, vc, Vector3(0, 2.4, 4.0), screen, "bathysphere_back")
	await RoomRender.close(self, vc)
