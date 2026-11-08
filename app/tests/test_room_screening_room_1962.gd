extends "res://tests/room_doc_harness.gd"

## The Screening room 1962 (app/environments/screening_room_1962.env.json; docs/environments.md, "Room: Screening
## room 1962"): the shipped document passes the checks, and is that room: a collector's walnut room (kit/
## screening_1962.gd) with two rows of club chairs, the pool glowing right outside the floor-to-ceiling window from the
## viewer's seat, a slow fire on a floating hearth, a sunburst clock keeping the real time, and the ritual: the
## painting comes down over the screen before the film, rises as the film starts (never faster than the motion
## system's limit) while the wall lamps go down to the room's setting and the fire and the pool settle low, rises by
## itself on a film resumed later, and stays up with the Pre-show off. Its sound: the fire at the hearth, the pool's
## pump through the glass, crickets in the garden, a far owl now and then, the house bells as the ritual starts, a
## small dry room, the level measured. The figures (draws, triangles, lights, particles, textures) as documented.
## Rendered (with a renderer, lavapipe): the room from its seat, a side seat, left, right, up and back, and close, in
## the pre-show and with a film playing (SR62_BAKE=1 bakes it first; SR62_RENDER_ONLY=1 skips the checks; SR62_ONLY=
## preshow or film draws one; SR62_QUICK=1 draws the seat only). Pictures: user://room_render/sr62_*.png (or
## $ENV_SHOTS).
## godot --headless --xr-mode off --path app --script res://tests/test_room_screening_room_1962.gd

const RoomSound := preload("res://tests/room_sound_checks.gd")
const RoomRender := preload("res://tests/room_render.gd")
const RoomBake := preload("res://scripts/env/room_bake.gd")
const Hall := preload("res://scripts/env/systems/kit/screening_1962.gd")
const PATH := "res://environments/screening_room_1962.env.json"
const BAKE_ID := "screening_room_1962_render_test"
## The motion system's speed limit (docs/environments.md, "The motion system").
const MAX_SPEED := 0.5


func run_tests() -> void:
	test_name = "test_room_screening_room_1962"
	if OS.get_environment("SR62_RENDER_ONLY") == "":
		var room := await check_shipped("screening_room_1962", PATH, "room")
		var b: Node = room.host.system("room")
		_built(room)
		_parts(room)
		_garden(room)
		_fire_and_clock(room)
		var seats: Array[Transform3D] = room.room_seat_transforms()
		check("six 1962 club chairs (%d)" % seats.size(), seats.size() == 6
				and (room.host.system("seats").drawn() as Array).all(func(d: Dictionary) -> bool:
					return d["model"] == "lounge"))
		await check_seat_pick("screening_room_1962", room, 5, true)
		await _ritual(room, b)
		await _sound(room)
		await done(room)
	await _render()


## The figures (docs/environments.md, "Room: Screening room 1962"), the shell given to the kit.
func _built(room: Node3D) -> void:
	var stats := EnvChecks.measure(room)
	print("  screening_room_1962 figures: %s" % [stats])
	check(("the figures as documented: at most 32 draws, under 120k triangles, no live light, no particles, under "
			+ "40 MB (%s)") % [stats], int(stats["draws"]) <= 32 and int(stats["triangles"]) < 120000
			and int(stats["lights"]) == 0 and int(stats["particles"]) == 0 and float(stats["texture_mb"]) < 40.0)
	var b: Node = room.host.system("room")
	check("the domestic builder gives its shell to the kit (no walls, floor or window of its own)",
			str(b.params["shell"]) == "kit" and room.find_child("Walls", true, false) == null
			and room.find_child("Window", true, false) == null and room.find_child("Fireplace", true, false) == null)
	check("the kit draws without a problem (%s)" % [room.host.system("kit").problems()],
			(room.host.system("kit").problems() as Array).is_empty())
	_by_part(room)


## What makes it this room: the painting over the screen (the builder's, in front on purpose), the kit's walnut and
## glass, the garden, the glows, the fire's place, the clock's hands; light in the bake only.
func _parts(room: Node3D) -> void:
	for n: String in ["Painting", "PaintingSlot", "PieceStatic", "PieceSoft", "PieceLamps", "PieceGlass", "Garden",
			"Glows", "Fire", "ClockHour", "ClockMinute", "Seats"]:
		check("the room has its %s" % n, room.find_child(n, true, false) != null)
	var spots := room.find_children("KitSpot*", "SpotLight3D", true, false)
	var glows := room.find_children("KitGlow*", "OmniLight3D", true, false)
	var hidden := true
	for l: Node in spots + glows:
		hidden = hidden and not (l as Light3D).visible
	check(("the downlights, wall-washers, sconces, the pool and the night light the bake (%d spots), the fire and the "
			+ "tripod lamp (%d), all hidden") % [spots.size(), glows.size()], spots.size() >= 14 and glows.size() >= 3
			and hidden)
	var light: Node = room.host.system("light")
	check("stand-in lamps for the chairs and the soft parts (%d, at most 8)" % light.lamp_count(),
			light.lamp_count() >= 5 and light.lamp_count() <= 8)


## The garden: the pool right outside the glass, seen from the viewer's seat through it; its glow ripples (the
## water's clock follows the Motion setting's water_motion).
func _garden(room: Node3D) -> void:
	var eye := Vector3(0, EnvChecks.EYE_HEIGHT, 0)
	var pool := Vector3((Hall.POOL_X0 + Hall.POOL_X1) * 0.5, Hall.WATER_Y, (Hall.POOL_Z0 + Hall.POOL_Z1) * 0.5)
	var t := (-Hall.HW - eye.x) / (pool.x - eye.x)
	var hit := eye + (pool - eye) * t
	check("the pool through the window from the seat (%s)" % hit, t > 0.0 and t < 1.0 and hit.z > Hall.WIN_Z0
			and hit.z < Hall.WIN_Z1 and hit.y > 0.0 and hit.y < Hall.H - Hall.BEAM_D)
	var kit: Node = room.host.system("kit")
	var h: Object = (kit.get("_ctx").halls as Array)[0]
	var m: ShaderMaterial = h.get("outside_m")
	var t0 := float(m.get_shader_parameter("water_clock"))
	kit.tick(1.0)
	var t1 := float(m.get_shader_parameter("water_clock"))
	check("the pool's light ripples at the water_motion's pace (%.2f s in 1 s)" % (t1 - t0),
			is_equal_approx(t1 - t0, float(kit.params["water_motion"])))


## The fire wavers slowly (every frequency under 3 Hz) and goes low with the accent lamps; the clock's hands keep
## the real time.
func _fire_and_clock(room: Node3D) -> void:
	var kit: Node = room.host.system("kit")
	var h: Object = (kit.get("_ctx").halls as Array)[0]
	var lo := 9.0
	var hi := 0.0
	for i in 120:
		kit.tick(1.0 / 30.0)
		lo = minf(lo, float(h.get("fire_level")))
		hi = maxf(hi, float(h.get("fire_level")))
	check("the fire wavers a little (%.2f .. %.2f)" % [lo, hi], hi - lo > 0.02 and hi - lo < 0.4)
	check("every waver under the photosensitivity ceiling", Hall.FLICKER_HZ.all(func(f: float) -> bool: return f < 3.0))
	var hands: Array = h.call("hand_angles")
	var t := Time.get_time_dict_from_system()
	var minutes := float(t["minute"]) + float(t["second"]) / 60.0
	var want := TAU * minutes / 60.0
	check("the clock's minute hand shows the real time (%.2f rad, want %.2f)" % [hands[1] if hands.size() > 1 else -1.0,
			want], hands.size() == 2 and absf(angle_difference(float(hands[1]), want)) < 0.05)


## The parts by draws and triangles (printed for the docs).
func _by_part(room: Node3D) -> void:
	var rows: Array = []
	for g: Node in room.find_children("*", "GeometryInstance3D", true, false):
		var stats := {}
		if g is MeshInstance3D and (g as MeshInstance3D).mesh != null:
			var mesh := (g as MeshInstance3D).mesh
			stats = {"draws": mesh.get_surface_count(), "triangles": EnvChecks._triangles(mesh)}
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh != null:
			var mm := (g as MultiMeshInstance3D).multimesh
			stats = {"draws": mm.mesh.get_surface_count(), "triangles": EnvChecks._triangles(mm.mesh)
					* int(g.get_meta("instances", mm.instance_count))}
		if not stats.is_empty():
			rows.append([str(g.name), stats["draws"], stats["triangles"]])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return int(a[2]) > int(b[2]))
	for r: Array in rows:
		print("  part %-22s %2d draws %7d triangles" % r)


## The sound: the fire's crackle at the hearth, the pool's filter pump humming beyond the glass, crickets in the
## garden, a small dry room, and the level measured (the ritual's bells in it).
func _sound(room: Node3D) -> void:
	var host: Node = room.host
	var fire: Node = host.system("fire")
	var pump: Node = host.system("pump")
	var hearth := (room.find_child("Fire", true, false) as Node3D).position
	var flames: Array = fire.players()
	check("the fire crackles at the hearth %s (%s)" % [hearth, flames.map(func(p: Node) -> Variant:
			return (p as Node3D).position)], fire.is_loop() and fire.playing() and flames.size() == 1
			and (flames[0] as Node3D).position.distance_to(hearth) < 0.2)
	var hum: Array = pump.players()
	check("the pool's pump hums beyond the glass, faint", pump.is_loop() and pump.playing()
			and str(pump.params["sound"]) == "hum" and hum.size() == 1 and (hum[0] as Node3D).position.x < -Hall.HW)
	var crickets: Node = host.system("crickets")
	check("crickets in the garden", crickets.is_loop() and crickets.playing()
			and (crickets.players()[0] as Node3D).position.x < -Hall.HW)
	var r: Dictionary = await RoomSound.levels(self, room, "screening_room_1962")
	for v: Array in RoomSound.verdicts("screening_room_1962", r):
		check(v[0], v[1])


func _ritual(room: Node3D, b: Node) -> void:
	var host: Node = room.host
	host.auto = false
	var bus := RoomSound.on_room_bus(room, ["fire", "pump", "crickets", "owl", "bells"])
	check(("the fire, the pump, the crickets, the owl and the bells on the room's bus, under Environment (the slider, "
			+ "the duck, Ambience) %s") % [bus], bus.is_empty())
	var ac := RoomSound.acoustics(room, "small_room", 0.45)
	check("a small, dry room (rt60 0.45) %s" % [ac], ac.is_empty())
	var bells: Node = host.system("bells")
	var painting := room.get_node("Painting") as Node3D
	check("the painting is in front of the screen on purpose (env_in_front)", painting.is_in_group("env_in_front"))
	host.snapshot_override = {"open": false}
	steps(host, 9.0)
	check("pre-show: the painting is down over the screen (%.2f)" % b.params["painting_open"],
			float(b.params["painting_open"]) < 0.01 and painting.position.y < 0.01)
	check("pre-show: the wall lamps up, the fire and the pool full (%.2f, %.2f, %.2f)" % [
			host.param("light.house_lamps"), host.param("light.accent"), host.param("kit.glow")],
			is_equal_approx(float(host.param("light.house_lamps")), 1.0)
			and is_equal_approx(float(host.param("light.accent")), 1.0)
			and is_equal_approx(float(host.param("kit.glow")), 1.0))
	# The film starts from its start: the ritual.
	host.snapshot_override = {"open": true, "playing": true, "position": 0.5, "duration": 7200.0}
	var fastest := 0.0
	var y := painting.position.y
	for i in 30 * 12:
		host.step(1.0 / 30.0)
		fastest = maxf(fastest, absf(painting.position.y - y) * 30.0)
		y = painting.position.y
	check("starting: the ritual fired", host.timeline.fired.any(func(f: Array) -> bool: return f[0] == "ritual"))
	check("the ritual rings the house bells once, through their bed (%d)" % bells.plays, bells.plays == 1
			and host.sounds.is_empty())
	check("the painting has risen (%.2f, %.2f m up)" % [b.params["painting_open"], y],
			float(b.params["painting_open"]) > 0.99 and y > 1.5)
	check("never faster than the motion limit (%.2f m/s)" % fastest, fastest > 0.05 and fastest <= MAX_SPEED)
	check("the wall lamps at the room's setting (%.2f)" % host.param("light.house_lamps"),
			is_equal_approx(float(host.param("light.house_lamps")), 0.15))
	steps(host, 10.0)
	check("in the film the fire an ember glow, the pool low (%.2f, %.2f)" % [host.param("light.accent"),
			host.param("kit.glow")], absf(float(host.param("light.accent")) - 0.25) < 0.01
			and absf(float(host.param("kit.glow")) - 0.12) < 0.01)
	host.set_setting("house_level", 0.5)
	steps(host, 1.0)
	check("the lamps follow the setting in the film (%.2f)" % host.param("light.house_lamps"),
			absf(float(host.param("light.house_lamps")) - 0.5) < 0.01)
	host.set_setting("house_level", 0.15)
	steps(host, 1.0)
	# The end: the lamps come up, the painting comes down again, the fire and the pool back up.
	host.snapshot_override = {"open": true, "playing": false, "position": 7200.0, "duration": 7200.0, "ended": true}
	steps(host, 12.0)
	check("ended: the painting down, the lamps up, the fire up (%.2f, %.2f, %.2f)" % [b.params["painting_open"],
			host.param("light.house_lamps"), host.param("light.accent")], float(b.params["painting_open"]) < 0.01
			and is_equal_approx(float(host.param("light.house_lamps")), 1.0)
			and is_equal_approx(float(host.param("light.accent")), 1.0))
	# A film resumed later (not from its start): the painting rises by itself.
	host.snapshot_override = {"open": true, "playing": true, "position": 1800.0, "duration": 7200.0}
	steps(host, 5.0)
	check("resumed: %s, the painting up (%.2f)" % [host.timeline.state, b.params["painting_open"]],
			host.timeline.state == "playing" and float(b.params["painting_open"]) > 0.99)
	# Pre-show off: the painting stays up before the film.
	host.set_setting("ritual", false)
	host.snapshot_override = {"open": false}
	steps(host, 8.0)
	check("Pre-show off: the painting stays up (%.2f)" % b.params["painting_open"],
			float(b.params["painting_open"]) > 0.99)
	host.snapshot_override = {"open": true, "playing": true, "position": 0.5, "duration": 7200.0}
	steps(host, 4.0)
	check("Pre-show off: no ritual, the lamps down all the same (%.2f)" % host.param("light.house_lamps"),
			host.timeline.fired.any(func(f: Array) -> bool: return f[0] == "dim")
			and absf(float(host.param("light.house_lamps")) - 0.15) < 0.01)
	host.set_setting("ritual", true)
	host.snapshot_override = null


## The renders (lavapipe): from the seat, a side seat, left, right, up and back, and close, before the film and in
## it; baked first with SR62_BAKE.
func _render() -> void:
	if not RoomRender.has_renderer():
		print("SKIP render (headless)")
		return
	var doc: Dictionary = EnvDoc.load_file(PATH)["doc"]
	var sc: Array = doc["screen"]["center"]
	var screen := Vector3(float(sc[0]), float(sc[1]), float(sc[2]))
	var baked := OS.get_environment("SR62_BAKE") != "" and RoomBake.can_bake()
	var only := OS.get_environment("SR62_ONLY")
	for phase: String in ["preshow", "film"]:
		if only != "" and only != phase:
			continue
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
			# Before the film the painting is down over the screen: no picture lights the room.
			RenderingServer.global_shader_parameter_set("screen_glow", 0.0)
			host.snapshot_override = {"open": false}
			host.signals.fake("film.brightness", 0.0)
		else:
			host.snapshot_override = {"open": true, "playing": true, "position": 0.5, "duration": 7200.0}
			host.signals.fake("film.brightness", 0.7)
			host.signals.fake("film.colour", Color(0.85, 0.55, 0.35))
			host.signals.fake("playback.playing", 1.0)
		for i in 160:
			host.step(0.25)
		var eye := Vector3(0, EnvChecks.EYE_HEIGHT, 0)
		var p := "sr62_%s%s_" % ["baked_" if baked else "", phase]
		var img: Image = await RoomRender.shot(self, vc, eye, screen, p + "seat")
		var walls := (RoomRender.mean(img, Rect2(0.04, 0.3, 0.12, 0.3)).get_luminance()
				+ RoomRender.mean(img, Rect2(0.84, 0.3, 0.12, 0.3)).get_luminance()) * 0.5
		var picture := RoomRender.mean(img, Rect2(0.4, 0.42, 0.2, 0.12)).get_luminance()
		print("  render: %s from the seat: the walls %.3f, the picture %.3f" % [phase, walls, picture])
		if OS.get_environment("SR62_QUICK") != "":
			await RoomRender.close(self, vc)
			continue
		await RoomRender.shot(self, vc, eye, eye + Vector3(-1.0, -0.1, -0.55), p + "left")
		await RoomRender.shot(self, vc, eye, eye + Vector3(1.0, -0.05, -0.45), p + "right")
		await RoomRender.shot(self, vc, eye, eye + Vector3(0.0, 1.0, -0.35), p + "up")
		await RoomRender.shot(self, vc, eye, eye + Vector3(0.0, 0.05, 1.0), p + "back")
		await RoomRender.shot(self, vc, Vector3(-1.0, EnvChecks.EYE_HEIGHT, 1.7), screen, p + "side_seat")
		await RoomRender.shot(self, vc, Vector3(1.0, EnvChecks.EYE_HEIGHT, 1.7), Vector3(-2.0, 1.0, -3.0),
				p + "back_row_window")
		(vc[1] as Camera3D).fov = 50.0
		await RoomRender.shot(self, vc, eye, Vector3(2.9, 0.9, -1.9), p + "hearth")
		await RoomRender.shot(self, vc, eye, Vector3(2.9, 0.6, 0.6), p + "bar_cart")
		await RoomRender.shot(self, vc, eye, Vector3(-5.5, 0.2, -3.6), p + "pool")
		await RoomRender.shot(self, vc, eye, Vector3(0.6, 1.3, 2.9), p + "shelves")
		await RoomRender.shot(self, vc, eye, Vector3(0.0, 0.7, -5.0), p + "credenza")
		await RoomRender.shot(self, vc, eye, Vector3(-40.0, -2.0, -60.0), p + "valley")
		await RoomRender.shot(self, vc, Vector3(0.0, 1.6, 1.2), Vector3(0.0, 2.2, 3.0), p + "port")
		await RoomRender.shot(self, vc, eye, Vector3(-3.2, 2.7, -2.6), p + "ceiling_window")
		(vc[1] as Camera3D).fov = 90.0
		await RoomRender.close(self, vc)
