extends "res://tests/env_builder_harness.gd"

## The Crater (app/environments/crater.env.json; docs/environments.md, "Room: Crater"): a lunar amphitheatre of stone
## tiers under a glass dome, Earth in the black sky. Built headless from its document and checked as every shipped room
## is (schema, budget, sight lines, comfort, licences, names, no people) and as a builder's room (seats, physics,
## bake); then what makes it this room: the dome covers the tiers and the screen and adds no floor or seats of its own,
## the sky is space with Earth over the screen, Earth turns at the Earth's speed setting (scaled by Motion), the Milky
## Way comes up as the film starts, the dome's lamps go down with the film, and the room is silent: no sound at all.
## Under lavapipe it draws the room from its own seat and Earth over it.
## godot --headless --xr-mode off --path app --script res://tests/test_room_crater.gd

const RoomRender := preload("res://tests/room_render.gd")
const DOC := "res://environments/crater.env.json"


func run_tests() -> void:
	test_name = "test_room_crater"
	var r := EnvDoc.load_file(DOC)
	check("the document reads (%s)" % [r["errors"]], (r["errors"] as Array).is_empty())
	var doc: Dictionary = r["doc"]
	if doc.is_empty():
		return
	var room := await check_room("crater", doc, "amphitheatre")
	var host: Node = room.host
	host.auto = false
	var amph: Node = host.system("amphitheatre")
	var dome: Node = host.system("dome")
	var sky: Node = host.system("sky")
	check("a lunar amphitheatre", str(amph.params["style"]) == "amphitheatre" and room.get_node_or_null("Tiers") != null)
	check("under a glass dome with no floor, seats or water of its own", str(dome.params["dome"]) == "glass"
			and not bool(dome.params["has_floor"]) and dome.seat_slots().is_empty()
			and str(dome.params["outside"]) == "none" and room.get_node_or_null("Outside") == null
			and room.get_node_or_null("Panes") != null)
	# Everything under the dome: every seat's eyes, the screen's corners.
	var dp: Dictionary = dome.params
	var seats: Array[Transform3D] = room.room_seat_transforms()
	var under := true
	for t in seats:
		if not _under_dome(dp, t.origin + Vector3.UP * 1.2, 1.0):
			under = false
	check("every seat (%d, on the tiers) is under the dome with a metre to spare" % seats.size(), seats.size() > 100
			and under and seats.all(func(t: Transform3D) -> bool: return t.origin.y > -1.0))
	var sc: Dictionary = doc["screen"]
	var c := Vector3(float(sc["center"][0]), float(sc["center"][1]), float(sc["center"][2]))
	var half := Vector2(float(sc["size"][0]), float(sc["size"][1])) * 0.5
	var corners_in := true
	for k: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		if not _under_dome(dp, c + Vector3(k.x * half.x, k.y * half.y, 0), 1.0):
			corners_in = false
	check("the screen under the dome", corners_in)
	check("the screen is the amphitheatre's", is_equal_approx(float(amph.screen()["center"][2]), c.z)
			and is_equal_approx(float(amph.screen()["center"][1]), c.y))
	# The sky: space, Earth over the screen from the room's own seat, the crater's rim round the horizon.
	check("the sky is space, Earth in it", str(sky.params["mode"]) == "space" and bool(sky.params["earth"]))
	var top := rad_to_deg(atan2(c.y + half.y - 1.2, -c.z))
	var earth_low := float(sky.params["earth_altitude"]) - float(sky.params["earth_size"]) * 0.5
	check("Earth hangs over the picture (%.1f degrees over its top at %.1f)" % [earth_low, top], earth_low > top + 5.0)
	var vista: Node = host.system("vista")
	check("the crater's rim round the horizon", vista != null and str(vista.params["items"][0]["shape"]) == "hills")
	# Earth's speed: 1 x is twelve times the real speed (once in two hours); the setting from 0.5 to 4 times.
	var turns := {}
	for v: float in [0.5, 1.0, 4.0]:
		host.set_setting("earth_speed", v)
		turns[v] = float(host.param("sky.earth_turn"))
	check("Earth's speed: 0.5, 1 and 4 times turn Earth 6, 12 and 48 times its real speed (%s)" % [turns],
			is_equal_approx(turns[0.5], 6.0) and is_equal_approx(turns[1.0], 12.0) and is_equal_approx(turns[4.0], 48.0))
	check("never past the comfort limit", float(turns[4.0]) <= 60.0)
	host.set_setting("motion", 0.5)
	var halved := float(host.param("sky.earth_turn"))
	check("Motion at half halves it (%.1f)" % halved, absf(halved - 24.0) < 0.01)
	host.set_setting("motion", 1.0)
	host.set_setting("earth_speed", 1.0)
	var spin0 := float(sky.get("_earth_spin"))
	for i in 240:
		host.step(0.25)
	var turned := rad_to_deg(float(sky.get("_earth_spin")) - spin0)
	check("Earth turns: a minute at 1 x is %.2f degrees (3 expected)" % turned, absf(turned - 3.0) < 0.05)
	# The Milky Way as the lights dim; the dome's lamps go down with the film and up at the end.
	host.timeline.state = ""
	host.snapshot_override = {"open": false}
	host.signals.fake("playback.playing", 0.0)
	for i in 60:
		host.step(0.25)
	var mw_before := float(host.param("sky.milky_way"))
	var lamps_before := float(host.param("light.house_lamps"))
	host.snapshot_override = {"open": true, "playing": true, "position": 0.5, "duration": 7200.0}
	host.signals.fake("playback.playing", 1.0)
	for i in 60:
		host.step(0.25)
	var mw_film := float(host.param("sky.milky_way"))
	var lamps_film := float(host.param("light.house_lamps"))
	check("the Milky Way comes up as the film starts (%.2f to %.2f)" % [mw_before, mw_film], mw_before < 0.45
			and mw_film > 0.9)
	check("the dome's lamps go down with the film (%.2f to %.2f)" % [lamps_before, lamps_film], lamps_before > 0.95
			and lamps_film < 0.05)
	host.snapshot_override = {"open": true, "playing": false, "ended": true, "position": 7200.0, "duration": 7200.0}
	for i in 30:
		host.step(0.25)
	check("and come up at the end", float(host.param("light.house_lamps")) > 0.95)
	# Silence: no sound of any kind.
	check("silent: no sound played", host.sounds.is_empty())
	check("silent: no life, no sound steps, no pause rise", host.systems_of_kind("life").is_empty()
			and not JSON.stringify(doc["cues"]).contains("\"sound\"")
			and float(doc["audio"]["pause_rise_db"]) == 0.0)
	await done(room)
	await _render(doc)


## Whether q is under the dome's glass (inside its drum and under its ellipsoid), `margin` metres in.
static func _under_dome(p: Dictionary, q: Vector3, margin: float) -> bool:
	var c := Vector3(0.0, float(p["floor_y"]), float(p["centre_z"]))
	var r := float(p["radius"]) - margin
	var d := Vector2(q.x - c.x, q.z - c.z).length()
	var y := q.y - c.y
	if d > r:
		return false
	var drum := float(p["drum_height"])
	if y <= drum:
		return true
	var h := float(p["dome_height"]) - margin
	return pow(d / r, 2.0) + pow((y - drum) / h, 2.0) < 1.0


func _render(doc: Dictionary) -> void:
	if not RoomRender.has_renderer():
		print("SKIP render (headless)")
		return
	var sc: Array = doc["screen"]["center"]
	var screen := Vector3(float(sc[0]), float(sc[1]), float(sc[2]))
	RoomRender.set_light(screen, 0.012)
	var vc := await RoomRender.open(self, doc)
	var host: Node = (vc[2] as Node).host
	host.snapshot_override = {"open": true, "playing": true, "position": 0.5, "duration": 7200.0}
	host.signals.fake("playback.playing", 1.0)
	for i in 60:
		host.step(0.25)
	var eye := Vector3(0, 1.2, 0)
	await RoomRender.shot(self, vc, eye, screen, "crater_seat")
	var sky: Node = host.system("sky")
	var az := deg_to_rad(float(sky.params["earth_bearing"]) - float(sky.params["facing"]))
	var el := deg_to_rad(float(sky.params["earth_altitude"]))
	var to := Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
	(vc[1] as Camera3D).fov = 30.0
	var img: Image = await RoomRender.shot(self, vc, eye, eye + to, "crater_earth")
	var earth := RoomRender.mean(img, Rect2(0.46, 0.46, 0.08, 0.08))
	var space := RoomRender.mean(img, Rect2(0.0, 0.0, 0.15, 0.15))
	print("  render: Earth %s, space by it %s" % [earth, space])
	check("Earth shows, bright and blue, against black space (%s, %s)" % [earth, space],
			earth.get_luminance() > space.get_luminance() + 0.05 and earth.b > earth.r)
	(vc[1] as Camera3D).fov = 90.0
	await RoomRender.shot(self, vc, eye, eye + Vector3(0.0, 1.0, -0.6), "crater_up")
	RoomRender.set_light(screen, 0.03)
	host.snapshot_override = {"open": false}
	host.signals.fake("playback.playing", 0.0)
	for i in 30:
		host.step(0.25)
	await RoomRender.shot(self, vc, Vector3(0, 3.5, 4.5), screen, "crater_back")
	await RoomRender.close(self, vc)
