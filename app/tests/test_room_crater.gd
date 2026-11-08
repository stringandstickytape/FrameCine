extends "res://tests/env_builder_harness.gd"

## The Crater (app/environments/crater.env.json; docs/environments.md, "Room: Crater"): a Moon base's cinema under a
## geodesic glass dome, Earth in the black sky. Built headless from its document and checked as every shipped room is
## (schema, budget, sight lines from every seat, comfort, licences, names, no people) and as a builder's room (seats,
## physics, bake); then what makes it this room: its figures (under the brief's aim: about 30 draws, under 250k
## triangles, no live light, no particles), the dome covers the tiers and the screen and adds no floor or seats of its
## own, its lattice and its one layer of glass, the airlocks; the base inside (pavers, tiers of blocks, a pad at every
## seat, the strips of light, stairs, the stage and pylons, all baked but the pads and the steel) and the Moon outside
## (nothing of it inside the glass, none past the far plane, unbaked); Earth as itself over the screen (its map: Africa,
## the Atlantic, the Sahara, Antarctica), turning at the Earth's speed setting (scaled by Motion); the Milky Way coming
## up as the film starts; the dome's lamps and the base's strips going down with the film and up at the end, the plain
## outside dimming a little with them (never out); and the room is silent: no sound at all (a silence bed, dry
## acoustics, nothing measured on Environment; the Void's sound checked the same way).
## Under lavapipe it draws the room from its own seat, a side seat, up, back and towards the base, in the pre-show and
## with a film playing, and Earth close (CRATER_BAKE=1 bakes it first).
## godot --headless --xr-mode off --path app --script res://tests/test_room_crater.gd

const RoomRender := preload("res://tests/room_render.gd")
const RoomSound := preload("res://tests/room_sound.gd")
const DOC := "res://environments/crater.env.json"
const EarthMap := preload("res://scripts/env/systems/kit/earth_map.gd")
const RoomBake := preload("res://scripts/env/room_bake.gd")
const BAKE_ID := "crater_render_test"


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
	await _moon_base(room, doc, amph, dome, sky)
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
	var steps_before := float(host.param("light.step_lights"))
	var moon: ShaderMaterial = amph.moon_material()
	var plain_before := float(moon.get_shader_parameter("level"))
	host.snapshot_override = {"open": true, "playing": true, "position": 0.5, "duration": 7200.0}
	host.signals.fake("playback.playing", 1.0)
	for i in 60:
		host.step(0.25)
	var mw_film := float(host.param("sky.milky_way"))
	var lamps_film := float(host.param("light.house_lamps"))
	var steps_film := float(host.param("light.step_lights"))
	var plain_film := float(moon.get_shader_parameter("level"))
	check("the Milky Way comes up as the film starts (%.2f to %.2f)" % [mw_before, mw_film], mw_before < 0.3
			and mw_film > 0.55)
	check("the dome's lamps go down with the film (%.2f to %.2f)" % [lamps_before, lamps_film], lamps_before > 0.95
			and lamps_film < 0.05)
	check("the strips under the noses and the stairs' lamps go low, not out (%.2f to %.2f)" % [steps_before,
			steps_film], steps_before > 0.95 and absf(steps_film - 0.4) < 0.05)
	check("the plain outside dims a little with them, never out (%.2f to %.2f)" % [plain_before, plain_film],
			plain_before > 0.95 and plain_film > 0.5 and plain_film < 0.7
			and float(moon.get_shader_parameter("lamps")) < 0.05)
	host.snapshot_override = {"open": true, "playing": false, "ended": true, "position": 7200.0, "duration": 7200.0}
	for i in 30:
		host.step(0.25)
	check("and come up at the end", float(host.param("light.house_lamps")) > 0.95
			and float(host.param("light.step_lights")) > 0.95 and float(moon.get_shader_parameter("level")) > 0.95)
	# Silence: no sound of any kind.
	check("silent: no sound played", host.sounds.is_empty())
	check("silent: no life, no sound steps, no pause rise", host.systems_of_kind("life").is_empty()
			and not JSON.stringify(doc["cues"]).contains("\"sound\"")
			and float(doc["audio"]["pause_rise_db"]) == 0.0)
	RoomSound.check_beds(self, "crater", room, {"silence": "silence"}, "vacuum")
	check("silent: no music", host.systems_of_kind("music").is_empty())
	await done(room)
	await RoomSound.check_level(self, self, "crater", doc, true)
	# The Void is silent too, and says so the same way.
	var void_doc: Dictionary = EnvDoc.load_file("res://environments/void.env.json")["doc"]
	var kinds: Array = void_doc["systems"].map(func(e: Dictionary) -> String: return "%s %s" % [e["system"],
			e.get("params", {}).get("sound", e.get("params", {}).get("preset", ""))])
	check("void: a silence bed and dry acoustics only (%s)" % [kinds], kinds.has("sound_bed silence")
			and kinds.has("acoustics vacuum") and not JSON.stringify(void_doc).contains("\"music\""))
	await RoomSound.check_level(self, self, "void", void_doc, true)
	await _render(doc)


## The figures, the dome's lattice and airlocks, the base inside, the Moon outside, Earth's map.
func _moon_base(room: Node3D, doc: Dictionary, amph: Node, dome: Node, sky: Node) -> void:
	var stats := EnvChecks.measure(room)
	print("  crater: %s" % [stats])
	check("within the brief's aim: about 30 draws, under 250k triangles, no live light, no particles (%s)" % [stats],
			int(stats["draws"]) <= 30 and int(stats["triangles"]) < 250000 and int(stats["lights"]) == 0
			and int(stats["particles"]) == 0)
	check("a Moon base: the amphitheatre lunar", bool(amph.params["lunar"]))
	# The dome: a geodesic lattice, one layer of glass (see-through), the airlocks with their lamps; unbaked.
	var panes := room.get_node_or_null("Panes") as MeshInstance3D
	var ribs := room.get_node_or_null("Ribs") as MeshInstance3D
	check("the dome a geodesic lattice of struts and hubs (%d triangles), unbaked" % [_tris(ribs)],
			str(dome.params["lattice"]) == "geodesic" and ribs != null and _tris(ribs) > 5000
			and ribs.gi_mode == GeometryInstance3D.GI_MODE_DISABLED)
	var glass_layers := room.find_children("Panes*", "MeshInstance3D", true, false).size()
	check("its glass flat in every triangle, one layer only, see-through (%d triangles)" % [_tris(panes)],
			panes != null and glass_layers == 1 and panes.is_in_group("env_see_through") and _tris(panes) > 300)
	check("two airlocks with their doors, status lamps, panels and lit windows",
			int(dome.params["airlocks"]) == 2 and room.get_node_or_null("AirlockFrames") != null
			and room.get_node_or_null("AirlockLamps") != null and room.get_node_or_null("AirlockWindows") != null)
	check("a cable tray round the drum, cables in it", bool(dome.params["trays"])
			and room.get_node_or_null("Cables") != null)
	# The base inside.
	var baked := ["Floor", "Tiers", "ScreenFrame"].all(func(n: String) -> bool:
		var mi := room.get_node_or_null(n) as MeshInstance3D
		return mi != null and mi.gi_mode == GeometryInstance3D.GI_MODE_STATIC)
	check("the pavers, the tiers' blocks, the stage, the pylons and the frame are baked", baked)
	var lamps := ["StepLights", "Footlights", "PylonLights", "Pads", "Steel"].all(func(n: String) -> bool:
		return room.get_node_or_null(n) != null)
	check("the strips under the noses, the stairs', the footlights, the pylons' slots, the pads, the rails", lamps)
	var seats: Array = amph.seat_slots()
	var pads := _tris(room.get_node_or_null("Pads") as MeshInstance3D)
	check("a pad at every seat, a back pad below the top tier (%d triangles for %d seats)" % [pads, seats.size()],
			pads > seats.size() * 40)
	# The Moon outside: nothing of it under the glass (but the ground's edge under the drum), nothing past the far
	# plane, never baked.
	var moon_mi := room.get_node_or_null("Moon") as MeshInstance3D
	check("the Moon outside, unbaked (%d triangles)" % [_tris(moon_mi)], moon_mi != null
			and moon_mi.gi_mode == GeometryInstance3D.GI_MODE_DISABLED and _tris(moon_mi) > 20000)
	var dp: Dictionary = dome.params
	var c := Vector3(0.0, float(dp["floor_y"]), float(dp["centre_z"]))
	var r := float(dp["radius"])
	var inside := 0
	var farthest := 0.0
	var verts: PackedVector3Array = moon_mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for v: Vector3 in verts:
		var d := Vector2(v.x - c.x, v.z - c.z).length()
		farthest = maxf(farthest, d)
		if d < r - 0.2 and v.y > c.y + 0.05:
			inside += 1
	check("nothing of the Moon inside the glass (%d points)" % inside, inside == 0)
	var seat_far := 0.0
	for t: Transform3D in room.room_seat_transforms():
		seat_far = maxf(seat_far, Vector2(t.origin.x - c.x, t.origin.z - c.z).length())
	check("the crater's wall within the far plane and short of the stars' layer from every seat (%.0f + %.0f m)"
			% [farthest, seat_far], farthest + seat_far < 185.0 and farthest > 140.0)
	check("the base's lights face the eye, see-through, unbaked", room.get_node_or_null("MoonLights") != null
			and (room.get_node("MoonLights") as Node).is_in_group("env_see_through"))
	# Earth as itself: its map's land and sea where they are.
	check("Earth as itself (earth_detail), 5 degrees across", bool(sky.params["earth_detail"])
			and is_equal_approx(float(sky.params["earth_size"]), 5.0))
	var img: Image = EarthMap.texture().get_image()
	var at := func(lon: float, lat: float) -> Color:
		return img.get_pixel(int((lon + 180.0) / 360.0 * img.get_width()) % img.get_width(),
				clampi(int((90.0 - lat) / 180.0 * img.get_height()), 0, img.get_height() - 1))
	check("its map: Africa and Australia land, the Atlantic and the Pacific sea", (at.call(20.0, 5.0) as Color).r > 0.6
			and (at.call(134.0, -25.0) as Color).r > 0.6 and (at.call(-30.0, 0.0) as Color).r < 0.3
			and (at.call(-150.0, 10.0) as Color).r < 0.3)
	check("the Sahara dry, the Congo green, Antarctica ice, Europe lit at night",
			(at.call(10.0, 23.0) as Color).g > 0.7 and (at.call(22.0, -1.0) as Color).g < 0.3
			and (at.call(0.0, -80.0) as Color).b > 0.8 and (at.call(5.0, 49.0) as Color).a > 0.4)
	await process_frame


static func _tris(mi: MeshInstance3D) -> int:
	if mi == null or mi.mesh == null:
		return 0
	return mi.mesh.get_faces().size() / 3


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
	var baked := OS.get_environment("CRATER_BAKE") != "" and RoomBake.can_bake()
	for phase: String in ["preshow", "film"]:
		RoomRender.set_light(screen, 0.05 if phase == "preshow" else 0.015)
		var vc := await RoomRender.open(self, doc)
		var room := vc[2] as Node3D
		var host: Node = room.host
		if baked:
			RoomBake.clear(BAKE_ID)
			RoomBake.prepare(room, BAKE_ID)
			room.call("set_baking", true)
			var br: Dictionary = RoomBake.bake(room, BAKE_ID)
			room.call("set_baking", false)
			print("  render: baked %s" % [br])
			for i in 4:
				await process_frame
		if phase == "preshow":
			# Before the film no picture lights the room.
			RenderingServer.global_shader_parameter_set("screen_glow", 0.0)
			host.snapshot_override = {"open": false}
			host.signals.fake("playback.playing", 0.0)
		else:
			host.snapshot_override = {"open": true, "playing": true, "position": 0.5, "duration": 7200.0}
			host.signals.fake("film.brightness", 0.7)
			host.signals.fake("film.colour", Color(0.85, 0.55, 0.35))
			host.signals.fake("playback.playing", 1.0)
		for i in 120:
			host.step(0.25)
		var eye := Vector3(0, 1.2, 0)
		var p := "crater_%s%s_" % ["baked_" if baked else "", phase]
		await RoomRender.shot(self, vc, eye, screen, p + "seat")
		await RoomRender.shot(self, vc, eye, eye + Vector3(-1.0, 0.1, -0.5), p + "left")
		await RoomRender.shot(self, vc, eye, eye + Vector3(1.0, 0.1, -0.5), p + "right")
		await RoomRender.shot(self, vc, eye, eye + Vector3(0.0, 1.0, -0.4), p + "up")
		await RoomRender.shot(self, vc, eye, eye + Vector3(0.0, 0.2, 1.0), p + "back")
		await RoomRender.shot(self, vc, Vector3(-11.0, 2.0, -3.0), screen, p + "side_seat")
		(vc[1] as Camera3D).fov = 22.0
		await RoomRender.shot(self, vc, eye, Vector3(-60.0, 1.0, -62.0), p + "base")
		if phase == "film":
			var sky: Node = host.system("sky")
			var az := deg_to_rad(float(sky.params["earth_bearing"]) - float(sky.params["facing"]))
			var el := deg_to_rad(float(sky.params["earth_altitude"]))
			var to := Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
			(vc[1] as Camera3D).fov = 8.0
			var img: Image = await RoomRender.shot(self, vc, eye, eye + to, p + "earth")
			var earth := RoomRender.mean(img, Rect2(0.42, 0.42, 0.16, 0.16))
			var space := RoomRender.mean(img, Rect2(0.0, 0.0, 0.06, 0.06))
			print("  render: Earth %s, space by it %s" % [earth, space])
			check("Earth shows, bright and blue, against black space (%s, %s)" % [earth, space],
					earth.get_luminance() > space.get_luminance() + 0.05 and earth.b > earth.r)
		(vc[1] as Camera3D).fov = 90.0
		await RoomRender.close(self, vc)
