extends "res://tests/env_builder_harness.gd"

## Atmospheric 1928 (app/environments/atmospheric_1928.env.json; docs/environments.md, "Room: Atmospheric 1928"): a
## picture palace built as a Mediterranean courtyard at dusk. Built headless from its document and checked as every
## shipped room is (schema, budget, sight lines from every seat, comfort, licences, names, no people); then what makes
## it this room: its figures and parts, light only in the bake (the gate's floodlights, the lanterns' pools), the lit
## windows of every kind going out one by one with the film while the organ's chambers stay lit, the crescent Moon
## seen over the roofs from the main seat, the ritual (lamps to a glow, the courtyard to bed, night, the Moon paler)
## and its return, the organ's prelude, cadence and setting, the fountain at its basin, the crickets and the owl,
## the Motion setting stilling the water, and the room's level (tests/room_sound.gd).
## Under lavapipe it draws the room from its own seat, a side seat, up and back, in the pre-show and with a film
## playing (ATMO_BAKE=1 bakes it first; ATMO_RENDER_ONLY=1 skips the checks).
## godot --headless --xr-mode off --path app --script res://tests/test_room_atmospheric_1928.gd

const RoomRender := preload("res://tests/room_render.gd")
const RoomSound := preload("res://tests/room_sound.gd")
const DOC := "res://environments/atmospheric_1928.env.json"
const RoomBake := preload("res://scripts/env/room_bake.gd")
const BAKE_ID := "atmospheric_1928_render_test"


func run_tests() -> void:
	test_name = "test_room_atmospheric_1928"
	var r := EnvDoc.load_file(DOC)
	check("the document reads (%s)" % [r["errors"]], (r["errors"] as Array).is_empty())
	var doc: Dictionary = r["doc"]
	if doc.is_empty():
		return
	if OS.get_environment("ATMO_RENDER_ONLY") == "":
		var room := await check_room("atmospheric_1928", doc)
		_by_part(room)
		_built(room)
		_windows(room)
		_moon(room)
		_ritual(room)
		_organ(room)
		_sound(room)
		_motion(room)
		await done(room)
		await RoomSound.check_level(self, self, "atmospheric_1928", doc)
	await _render(doc)


## The figures (docs/environments.md, "Room: Atmospheric 1928"), the parts, the bake's lights.
func _built(room: Node3D) -> void:
	var host: Node = room.host
	var stats := EnvChecks.measure(room)
	check("the figures as documented: 26 to 36 draws, under 280k triangles, no live light, no particles, under 20 MB "
			+ "(%s)" % [stats], int(stats["draws"]) >= 26 and int(stats["draws"]) <= 36
			and int(stats["triangles"]) < 280000 and int(stats["lights"]) == 0 and int(stats["particles"]) == 0
			and float(stats["texture_mb"]) < 20.0)
	for n: String in ["PieceStatic", "PieceSoft", "PieceRoomWindows", "PieceWater", "PiecePort", "PieceLamps"]:
		check("the room has its %s" % n, room.find_child(n, true, false) != null)
	var kit: Node = host.system("kit")
	check("the kit draws without a problem (%s)" % [kit.problems()], kit.problems().is_empty())
	var kinds := {}
	for p: Dictionary in kit.params["pieces"]:
		kinds[str(p["piece"])] = int(kinds.get(str(p["piece"]), 0)) + 1
	check("a palace gate, thirteen houses, two lions, cypresses, palms and a pine (%s)" % [kinds],
			kinds.get("palace_gate", 0) == 1 and kinds.get("house", 0) == 13 and kinds.get("pedestal", 0) == 2
			and kinds.get("cypress", 0) >= 4 and kinds.get("palm", 0) >= 2 and kinds.get("pine", 0) >= 1)
	# Light in the bake only: the floodlights on the gate and the lanterns' pools, hidden, never live.
	var spots := room.find_children("KitSpot*", "SpotLight3D", true, false)
	var lamps := room.find_children("KitLamp*", "OmniLight3D", true, false)
	var hidden := true
	for l: Node in spots + lamps:
		hidden = hidden and not (l as Light3D).visible
	print("  bake lights: %d floods, %d lamps of the pieces' %d" % [spots.size(), lamps.size(),
			(kit.get("_ctx").lamps as Array).size()])
	check("the gate's floodlights (%d) and the lanterns' pools (%d) light the bake, hidden" % [spots.size(),
			lamps.size()], spots.size() == 4 and lamps.size() >= 10 and lamps.size() <= int(kit.params["bake_lamps"])
			and hidden)
	check("no handrail runs through the house fronts along the walls", room.find_child("Brass", true, false) == null)
	check("the hall's own house spots left out (the gate's floods light the stage)",
			room.find_children("House*", "SpotLight3D", true, false).is_empty()
			and bool(host.system("hall").params["house_spots"]) == false)


## The lit windows: rooms behind of every kind, a few dark, each its own moment of going out; the organ's chambers
## stay lit.
func _windows(room: Node3D) -> void:
	var mi := room.find_child("PieceRoomWindows", true, false) as MeshInstance3D
	if mi == null:
		return
	var seen := {}
	for s in mi.mesh.get_surface_count():
		var cols: Variant = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_COLOR]
		if cols == null:
			continue
		for c: Color in cols:
			seen[c] = true
	var kinds := {}
	var lit := 0
	var out_at_night := 0
	var dark := 0
	var organ := 0
	var lo := 1.0
	var hi := 0.0
	for c: Color in seen:
		if c.b > 0.95:
			dark += 1
			continue
		var kind := int(floor(c.b * 8.0))
		kinds[kind] = true
		if kind == 5:
			organ += 1
			check("an organ chamber never goes out (%.3f)" % c.a, c.a > 0.95)
			continue
		lit += 1
		lo = minf(lo, c.a)
		hi = maxf(hi, c.a)
		if c.a < 0.7:
			out_at_night += 1
	print("  windows: %d lit (kinds %s), %d dark, %d organ chambers, %d of the lit out at night 0.7" % [lit,
			kinds.keys(), dark, organ, out_at_night])
	check("lit windows (%d) of every kind (%s), a few dark (%d), two organ chambers (%d)" % [lit, kinds.keys(), dark,
			organ], lit >= 40 and kinds.size() == 6 and dark >= 3 and dark < lit / 3 and organ == 2)
	check("each window its own moment of going out (%.2f to %.2f)" % [lo, hi], lo < 0.15 and hi > 0.85)
	var share := float(out_at_night) / maxf(lit, 1.0)
	check("with the film most have gone out, some still lit (%.0f%% out)" % (share * 100.0), share > 0.5
			and share < 0.85)


## The crescent Moon: high in the south-west, seen from the main seat over the roofs.
func _moon(room: Node3D) -> void:
	var sky: Node = room.host.system("sky")
	var dir: Vector3 = sky.moon_direction()
	var alt := rad_to_deg(asin(clampf(dir.y, -1.0, 1.0)))
	check("a Moon in the sky, %.0f degrees up" % alt, dir != Vector3.ZERO and alt > 35.0 and alt < 60.0)
	var eye := Vector3(0.0, 1.2, 0.0)
	var blocked := ""
	for n: String in ["PieceStatic", "PieceSoft", "PieceRoomWindows"]:
		var mi := room.find_child(n, true, false) as MeshInstance3D
		if mi == null:
			continue
		var f := mi.mesh.get_faces()
		var xf := mi.global_transform
		for k in range(0, f.size(), 3):
			if Geometry3D.ray_intersects_triangle(eye, dir, xf * f[k], xf * f[k + 1], xf * f[k + 2]) != null:
				blocked = n
				break
		if blocked != "":
			break
	check("the Moon seen from the main seat over the roofs (%s)" % ("clear" if blocked == "" else blocked),
			blocked == "")


## The film's ritual: the house lamps and the lanterns sink to a glow, the courtyard goes to bed, the sky to night,
## the clouds lose the town's glow and the Moon pales; all of it back at the end.
func _ritual(room: Node3D) -> void:
	var host: Node = room.host
	host.timeline.state = ""
	host.snapshot_override = {"open": false}
	_steps(host, 20.0)
	var kit: Node = host.system("kit")
	var before := [float(host.param("light.house_lamps")), float(host.param("kit.night")), float(host.param("sky.dusk")),
			float(host.param("sky.cloud_glow_level")), float(host.param("sky.moon")), float(kit.window_state()["energy"])]
	check("before the film: lamps up, every window lit, dusk, the clouds lit from below, the Moon bright (%s)"
			% [before], before[0] > 0.95 and before[1] < 0.01 and absf(before[2] - 0.45) < 0.02 and before[3] > 0.95
			and before[4] > 0.95)
	host.snapshot_override = {"open": true, "playing": true, "position": 0.5, "duration": 7200.0}
	_steps(host, 30.0)
	var during := [float(host.param("light.house_lamps")), float(host.param("kit.night")), float(host.param("sky.dusk")),
			float(host.param("sky.cloud_glow_level")), float(host.param("sky.moon")), float(kit.window_state()["energy"])]
	check("with the film: lamps to a glow, the courtyard to bed, night, the glow off the clouds, the Moon paler (%s)"
			% [during], absf(during[0] - 0.12) < 0.02 and absf(during[1] - 0.7) < 0.02 and absf(during[2] - 0.85)
			< 0.02 and absf(during[3] - 0.25) < 0.02 and absf(during[4] - 0.6) < 0.02)
	check("the windows follow the house lamps down (%.2f to %.2f)" % [before[5], during[5]],
			during[5] < before[5] * 0.2)
	check("the windows' material knows the night (%.2f)" % float(kit.window_state()["night"]),
			absf(float(kit.window_state()["night"]) - 0.7) < 0.02)
	host.snapshot_override = {"open": true, "playing": false, "ended": true, "position": 7200.0, "duration": 7200.0}
	_steps(host, 20.0)
	check("all of it back at the end (%.2f, %.2f, %.2f, %.2f)" % [float(host.param("light.house_lamps")),
			float(host.param("kit.night")), float(host.param("sky.dusk")), float(host.param("sky.moon"))],
			float(host.param("light.house_lamps")) > 0.95 and float(host.param("kit.night")) < 0.01
			and absf(float(host.param("sky.dusk")) - 0.45) < 0.02 and float(host.param("sky.moon")) > 0.95)


## The organ behind the grilles: it plays a while as the room opens and between films, ends with a cadence as the
## film starts, and the Organ setting silences it.
func _organ(room: Node3D) -> void:
	var host: Node = room.host
	check("Organ before the film: on by default", host.setting("organ") == true)
	var organ: Node = host.system("organ")
	check("a theatre organ in the left tower (%s)" % [organ.params["at"]], str(organ.params["instrument"]) == "organ"
			and str(organ.params["stop"]) == "theatre" and float(organ.params["at"][0]) < -7.0
			and float(organ.params["at"][2]) < -13.0)
	host.timeline.state = ""
	host.snapshot_override = {"open": false}
	var fired: int = _fired(host, "prelude")
	_steps(host, 8.0)
	check("the prelude plays as the room opens", _fired(host, "prelude") > fired and organ.get("_forced_on") == true)
	_steps(host, 90.0)
	check("for a minute or so, then rests", organ.get("_forced_on") == false)
	var post: int = _fired(host, "postlude")
	host.snapshot_override = {"open": true, "playing": true, "position": 0.5, "duration": 7200.0}
	_steps(host, 2.0)
	check("a cadence as the film starts", _fired(host, "postlude") > post)
	_steps(host, 40.0)
	host.set_setting("organ", false)
	organ = host.system("organ")
	_steps(host, 1.0)
	check("the Organ setting off: the organ off", organ.params["on"] == false)
	fired = _fired(host, "prelude")
	host.snapshot_override = {"open": true, "playing": false, "ended": true, "position": 7200.0, "duration": 7200.0}
	_steps(host, 10.0)
	check("and no prelude between films", _fired(host, "prelude") == fired)
	host.set_setting("organ", true)
	_steps(host, 1.0)


## The fountain at its basin, the crickets round the courtyard, a scops owl now and then from the pine.
func _sound(room: Node3D) -> void:
	var host: Node = room.host
	RoomSound.check_beds(self, "atmospheric_1928", room, {"fountain": "fountain", "crickets": "crickets",
			"owl": "scops_owl"}, "cinema")
	var water := room.find_child("PieceWater", true, false) as MeshInstance3D
	if water != null:
		var aabb := water.global_transform * water.get_aabb()
		var at: Array = host.system("fountain").params["at"]
		var d := Vector3(float(at[0]), float(at[1]), float(at[2])).distance_to(aabb.get_center())
		check("the fountain sounds from its basin (%.1f m off)" % d, d < 1.5)
	var crickets: Node = host.system("crickets")
	var owl: Node = host.system("owl")
	check("the crickets and the owl draw back under the film (%.0f dB, %.0f dB)" % [float(crickets.params["film_db"]),
			float(owl.params["film_db"])], float(crickets.params["film_db"]) <= -15.0
			and float(owl.params["film_db"]) <= -35.0)
	host.timeline.state = ""
	host.snapshot_override = {"open": false}
	var o0: int = owl.plays
	_steps(host, 330.0, 0.5)
	check("in five and a half minutes the owl calls now and then (%d)" % (owl.plays - o0), owl.plays - o0 >= 3
			and owl.plays - o0 <= 10)


## Comfort: the Motion setting stills the fountain's water.
func _motion(room: Node3D) -> void:
	var host: Node = room.host
	var kit: Node = host.system("kit")
	host.set_setting("motion", 0.0)
	_steps(host, 1.0)
	var m: ShaderMaterial = kit.water_material()
	var t0 := float(m.get_shader_parameter("clock"))
	_steps(host, 5.0)
	check("Motion off stills the water (%.2f, clock %.2f to %.2f)" % [float(kit.params["water_motion"]), t0,
			float(m.get_shader_parameter("clock"))], float(kit.params["water_motion"]) == 0.0
			and is_equal_approx(t0, float(m.get_shader_parameter("clock"))))
	host.set_setting("motion", 1.0)
	_steps(host, 2.0)
	check("and Motion on moves it again", float(m.get_shader_parameter("clock")) > t0 + 0.5)


static func _steps(host: Node, seconds: float, dt := 0.25) -> void:
	var t := 0.0
	while t < seconds:
		host.step(dt)
		t += dt


func _fired(host: Node, cue: String) -> int:
	return host.timeline.fired.filter(func(f: Array) -> bool: return str(f[0]) == cue).size()


## The figures by part (printed for the docs): draws and triangles of each mesh.
func _by_part(room: Node3D) -> void:
	var rows: Array = []
	for g: Node in room.find_children("*", "GeometryInstance3D", true, false):
		if not (g as GeometryInstance3D).visible:
			continue
		var stats := {}
		if g is MeshInstance3D and (g as MeshInstance3D).mesh != null:
			var mi := g as MeshInstance3D
			stats = {"draws": mi.mesh.get_surface_count(), "triangles": EnvChecks._triangles(mi.mesh)}
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh != null:
			var mm := (g as MultiMeshInstance3D).multimesh
			stats = {"draws": mm.mesh.get_surface_count(), "triangles": EnvChecks._triangles(mm.mesh)
					* int(g.get_meta("instances", mm.instance_count))}
		if not stats.is_empty():
			rows.append([str(g.name), stats["draws"], stats["triangles"]])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return int(a[2]) > int(b[2]))
	for r: Array in rows:
		print("  part %-22s %2d draws %7d triangles" % r)


func _render(doc: Dictionary) -> void:
	if not RoomRender.has_renderer():
		print("SKIP render (headless)")
		return
	var sc: Array = doc["screen"]["center"]
	var screen := Vector3(float(sc[0]), float(sc[1]), float(sc[2]))
	var baked := OS.get_environment("ATMO_BAKE") != "" and RoomBake.can_bake()
	for phase: String in ["preshow", "film"]:
		RoomRender.set_light(screen, 0.05 if phase == "preshow" else 0.015)
		var vc := await RoomRender.open(self, doc)
		var host: Node = (vc[2] as Node).host
		if baked:
			var room := vc[2] as Node3D
			RoomBake.clear(BAKE_ID)
			RoomBake.prepare(room, BAKE_ID)
			room.call("set_baking", true)
			var br: Dictionary = RoomBake.bake(room, BAKE_ID)
			room.call("set_baking", false)
			print("  render: baked %s" % [br])
			for i in 4:
				await process_frame
		if phase == "preshow":
			# Before the film the pre-show's curtains are closed over the screen: no picture lights the room.
			RenderingServer.global_shader_parameter_set("screen_glow", 0.0)
			for n: Node in (vc[2] as Node).get_children():
				if n is MeshInstance3D and (n as MeshInstance3D).mesh is QuadMesh:
					var m := (n as MeshInstance3D).material_override as StandardMaterial3D
					if m != null:
						m.albedo_texture = null
						m.albedo_color = Color(0.2, 0.035, 0.04)
			host.snapshot_override = {"open": false}
			host.signals.fake("film.brightness", 0.0)
		else:
			host.snapshot_override = {"open": true, "playing": true, "position": 0.5, "duration": 7200.0}
			host.signals.fake("film.brightness", 0.7)
			host.signals.fake("film.colour", Color(0.85, 0.55, 0.35))
			host.signals.fake("playback.playing", 1.0)
		for i in 160:
			host.step(0.25)
		var eye := Vector3(0, 1.2, 0)
		var p := "atmo_%s%s_" % ["baked_" if baked else "", phase]
		var img: Image = await RoomRender.shot(self, vc, eye, screen, p + "seat")
		# The façades beside the screen against the picture (printed for the docs: how lit the courtyard is).
		var houses := (RoomRender.mean(img, Rect2(0.08, 0.3, 0.12, 0.2)).get_luminance()
				+ RoomRender.mean(img, Rect2(0.8, 0.3, 0.12, 0.2)).get_luminance()) * 0.5
		var gate := RoomRender.mean(img, Rect2(0.3, 0.3, 0.04, 0.15)).get_luminance()
		var picture := RoomRender.mean(img, Rect2(0.4, 0.42, 0.2, 0.12)).get_luminance()
		print("  render: %s from the seat: the houses %.3f, the gate %.3f, the picture %.3f" % [phase, houses, gate,
				picture])
		await RoomRender.shot(self, vc, eye, eye + Vector3(-1.0, 0.2, -0.3), p + "left")
		await RoomRender.shot(self, vc, eye, eye + Vector3(1.0, 0.2, -0.3), p + "right")
		await RoomRender.shot(self, vc, eye, eye + Vector3(0.0, 1.0, -0.2), p + "up")
		await RoomRender.shot(self, vc, eye, eye + Vector3(0.0, 0.1, 1.0), p + "back")
		var side := Vector3(-6.0, 0, 3.0)
		var best := Vector3(999, 0, 0)
		for t: Transform3D in (vc[2] as Node).call("room_seat_transforms"):
			if t.origin.distance_to(side) < best.distance_to(side):
				best = t.origin
		await RoomRender.shot(self, vc, best + Vector3(0, 1.2, 0), screen, p + "side_seat")
		await RoomRender.shot(self, vc, best + Vector3(0, 1.2, 0), best + Vector3(-1.0, 1.5, -0.4), p + "side_wall")
		(vc[1] as Camera3D).fov = 45.0
		await RoomRender.shot(self, vc, eye, Vector3(0.0, 5.0, -14.0), p + "gate")
		await RoomRender.shot(self, vc, eye, Vector3(-9.0, 4.0, -7.0), p + "left_near")
		await RoomRender.shot(self, vc, eye, Vector3(5.0, 15.0, -14.0), p + "moon")
		await RoomRender.shot(self, vc, eye, Vector3(0.0, 4.0, 6.2), p + "rear")
		await RoomRender.shot(self, vc, eye, Vector3(8.0, -1.5, -11.9), p + "lion")
		await RoomRender.shot(self, vc, eye, Vector3(9.0, 4.5, -2.0), p + "right_near")
		await RoomRender.shot(self, vc, Vector3(5.0, 0.2, -7.0), Vector3(8.0, -1.6, -11.9), p + "lion_close")
		await RoomRender.shot(self, vc, Vector3(-7.4, 2.9, 0.6), Vector3(-9.2, 2.1, 4.3), p + "fountain")
		(vc[1] as Camera3D).fov = 90.0
		await RoomRender.close(self, vc)
