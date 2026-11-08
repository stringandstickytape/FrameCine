extends "res://tests/env_builder_harness.gd"

## Streamline 1937 (app/environments/streamline_1937.env.json; docs/environments.md, "Room: Streamline 1937"): a 1937
## moderne picture house. Built headless from its document and checked as every shipped room is (schema, budget, sight
## lines from every seat, comfort, licences, names, no people); then what makes it this room: its figures and parts,
## light only in the bake (the shell lights' pools, the circle's downlights, the coves' glow down the walls), the coves (their light
## graded from the slots, gold by default, a setting's colour, cycling before the film, the film's colour at a glow in
## it), the stepped proscenium round the picture, the festoon (down to the stage, up behind the first frame's head,
## clear of the picture), the organ console on its lift (it rises lit and the organ plays as the room opens and between
## films, closes with a cadence and sinks as the film starts; its top under the front row's sight line), the clock
## telling the real time, the ritual and its return, Pre-show off, and the room's level (tests/room_sound.gd).
## Under lavapipe it draws the room from its own seat, a side seat, up and back, in the pre-show (gold, jade, rose) and
## with a film playing (STREAM_BAKE=1 bakes it first; STREAM_RENDER_ONLY=1 skips the checks; STREAM_ONLY=preshow or
## film draws one).
## godot --headless --xr-mode off --path app --script res://tests/test_room_streamline_1937.gd

const RoomRender := preload("res://tests/room_render.gd")
const RoomSound := preload("res://tests/room_sound.gd")
const DOC := "res://environments/streamline_1937.env.json"
const RoomBake := preload("res://scripts/env/room_bake.gd")
const BAKE_ID := "streamline_1937_render_test"
const GOLD := Color(1.0, 0.72, 0.4)
const JADE := Color(0.42, 0.92, 0.7)


func run_tests() -> void:
	test_name = "test_room_streamline_1937"
	var r := EnvDoc.load_file(DOC)
	check("the document reads (%s)" % [r["errors"]], (r["errors"] as Array).is_empty())
	var doc: Dictionary = r["doc"]
	if doc.is_empty():
		return
	if OS.get_environment("STREAM_RENDER_ONLY") == "":
		var room := await check_room("streamline_1937", doc)
		_by_part(room)
		_built(room)
		_proscenium(room)
		_clock(room)
		_coves(room)
		await _console(room)
		_ritual(room)
		_pre_show_off(room)
		await done(room)
		await RoomSound.check_level(self, self, "streamline_1937", doc)
	await _render(doc)


## The figures (docs/environments.md, "Room: Streamline 1937"), the parts, the bake's lights.
func _built(room: Node3D) -> void:
	var host: Node = room.host
	var stats := EnvChecks.measure(room)
	check("the figures as documented: 22 to 30 draws, under 230k triangles, no live light, no particles, under 16 MB "
			+ "(%s)" % [stats], int(stats["draws"]) >= 22 and int(stats["draws"]) <= 30
			and int(stats["triangles"]) < 230000 and int(stats["lights"]) == 0 and int(stats["particles"]) == 0
			and float(stats["texture_mb"]) < 16.0)
	for n: String in ["PieceStatic", "PieceSoft", "PieceCove", "PieceLamps", "PieceClock", "Festoon", "Console"]:
		check("the room has its %s" % n, room.find_child(n, true, false) != null)
	var kit: Node = host.system("moderne")
	check("the hall's kit draws without a problem (%s)" % [kit.problems()], kit.problems().is_empty())
	check("the console's kit draws without a problem (%s)" % [host.system("console").problems()],
			host.system("console").problems().is_empty())
	var hall: Node = host.system("hall")
	check("the hall gives way to the kit: no ceiling of its own, no drapes, sconces, handrails (%s)" % [[
			hall.params["ceiling_cover"], hall.params["proscenium"], hall.params["sconce_joints"],
			hall.params["handrails"]]], float(hall.params["ceiling_cover"]) == 0.0
			and str(hall.params["proscenium"]) == "none" and (hall.params["sconce_joints"] as Array).is_empty()
			and room.find_child("Brass", true, false) == null and room.find_child("Ceiling", true, false) == null)
	# Light in the bake only: the shell lights' pools, the circle's downlights, the coves' slots; hidden, never live.
	var lamps := room.find_children("KitLamp*", "OmniLight3D", true, false)
	var spots := room.find_children("KitSpot*", "SpotLight3D", true, false)
	var glows := room.find_children("KitGlow*", "OmniLight3D", true, false)
	var hidden := true
	for l: Node in lamps + spots + glows:
		hidden = hidden and not (l as Light3D).visible
	check("the shells' pools (%d), the downlights (%d) and the coves' glow down the walls (%d) light the bake, hidden"
			% [lamps.size(), spots.size(), glows.size()], lamps.size() == 8 and spots.size() == 3 and glows.size() == 10
			and hidden)
	# The cove's light is graded: bright by the slots, gone a few metres off.
	var cove := room.find_child("PieceCove", true, false) as MeshInstance3D
	var lit := 0
	var dark := 0
	var cols: PackedColorArray = cove.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	for c: Color in cols:
		if c.a > 0.6:
			lit += 1
		elif c.a < 0.1:
			dark += 1
	check("the coves graded: some plaster bright by a slot (%d), much of it in shadow (%d) of %d" % [lit, dark,
			cols.size()], lit > cols.size() / 20 and dark > cols.size() / 5)


## The stepped proscenium: three frames round the picture, none of it in front of the picture; the festoon down to the
## stage, up behind the first frame's head and clear of the picture.
func _proscenium(room: Node3D) -> void:
	var host: Node = room.host
	var doc: Dictionary = room.get("doc")
	var sc: Array = doc["screen"]["center"]
	var sz: Array = doc["screen"]["size"]
	var top := float(sc[1]) + float(sz[1]) * 0.5
	var head := top + 0.35
	var festoon: Node = host.system("festoon")
	var cloth := festoon.call("target") as MeshInstance3D
	check("the festoon is in front of the picture until it rises", cloth != null and cloth.is_in_group("env_in_front"))
	host.timeline.state = ""
	host.snapshot_override = {"open": false}
	_steps(host, 2.0)
	var down := cloth.global_transform * cloth.get_aabb()
	var stage := float(host.system("hall").params["stage_top"])
	check("down, the festoon reaches the stage (%.2f, the stage %.2f)" % [down.position.y, stage],
			down.position.y < stage + 0.1)
	festoon.act("snap", {"at": 1.0})
	_steps(host, 0.5)
	var up := _lowest(cloth)
	check("up, its lowest swag is behind the first frame's head (%.2f over %.2f)" % [up, head], up > head + 0.1)
	festoon.act("snap", {"at": 0.0})
	_steps(host, 0.5)


static func _lowest(mi: MeshInstance3D) -> float:
	var lo := INF
	var xf := mi.global_transform
	for v: Vector3 in mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		lo = minf(lo, (xf * v).y)
	return lo


## The clock tells the real time.
func _clock(room: Node3D) -> void:
	var kit: Node = room.host.system("moderne")
	_steps(room.host, 1.2)
	var hands: Array = kit.clock_hands()
	var t := Time.get_time_dict_from_system()
	var minute := TAU * (float(t["minute"]) + float(t["second"]) / 60.0) / 60.0
	var off := absf(wrapf(float(hands[1]) - minute, -PI, PI)) if hands.size() == 2 else 9.0
	check("the clock's minute hand at the real time (%.3f rad off)" % off, off < 0.05)


## The coves: gold by default, a steady colour by the setting, the Changing cycle before the film, the film's colour
## (at a glow) in the film.
func _coves(room: Node3D) -> void:
	var host: Node = room.host
	var kit: Node = host.system("moderne")
	check("Cove colours: Changing by default", host.setting("cove") == "changing")
	check("the coves gold by default (%s)" % kit.cove_colour_now(), kit.cove_colour_now().is_equal_approx(GOLD))
	host.set_setting("cove", "jade")
	kit = host.system("moderne")
	host.timeline.state = ""
	host.snapshot_override = {"open": false}
	_steps(host, 25.0)
	check("Jade: the coves jade and they hold (%s)" % kit.cove_colour_now(), kit.cove_colour_now().is_equal_approx(JADE)
			and (host.system("console").cove_colour_now() as Color).is_equal_approx(JADE))
	host.set_setting("cove", "changing")
	kit = host.system("moderne")
	host.timeline.state = ""
	host.snapshot_override = {"open": false}
	var seen := {}
	var t := 0.0
	while t < 45.0:
		_steps(host, 1.0)
		var c: Color = kit.cove_colour_now()
		seen["%.1f %.1f %.1f" % [c.r, c.g, c.b]] = true
		t += 1.0
	check("Changing: the coves move through the colours before the film (%d seen)" % seen.size(), seen.size() >= 4)
	var pre: Dictionary = kit.cove_state()
	host.signals.fake("film.colour", Color(0.1, 0.3, 0.9))
	host.signals.fake("playback.playing", 1.0)
	host.snapshot_override = {"open": true, "playing": true, "position": 0.5, "duration": 7200.0}
	_steps(host, 25.0)
	var film: Dictionary = kit.cove_state()
	var fc: Color = film["colour"]
	check("in the film the coves take the film's colour (%s)" % fc, fc.b > fc.r and fc.b > 0.5)
	check("and sink to a glow: under a tenth of the pre-show's (%.3f, %.3f)" % [float(film["glow"]), float(pre["glow"])],
			float(film["glow"]) < float(pre["glow"]) * 0.1)
	host.signals.clear_fakes()


## The organ console: as the room opens it rises lit from the pit and the organ plays; up, its top stays under every
## seat's sight line to the picture.
func _console(room: Node3D) -> void:
	var host: Node = room.host
	var organ: Node = host.system("organ")
	var pipes: Node = host.system("pipes")
	var lift := organ.call("target") as Node3D
	check("the console is one node the lift moves (%s)" % [lift.name if lift != null else "none"], lift != null
			and lift.name == "Console" and host.system("console").owned().has(lift))
	host.timeline.state = ""
	host.snapshot_override = {"open": false}
	_steps(host, 1.0)
	check("as the room opens the console is down (%.2f)" % organ.call("progress"), float(organ.call("progress")) < 0.01)
	_steps(host, 16.0)
	check("then it rises from the pit (%.2f) and the organ plays" % organ.call("progress"),
			float(organ.call("progress")) > 0.99 and pipes.get("_forced_on") == true)
	check("a theatre organ at the console (%s)" % [pipes.params["at"]], str(pipes.params["instrument"]) == "organ"
			and str(pipes.params["stop"]) == "theatre" and absf(float(pipes.params["at"][2]) + 11.35) < 0.5)
	var blocked: Array = await EnvChecks.sight_line(self, room)
	check("up, the console is under every seat's sight line to the picture %s" % [blocked], blocked.is_empty())
	var glass: Dictionary = host.system("console").cove_state()
	check("its glass lit in the coves' colour (%s)" % [glass], float(glass.get("glow", 0.0)) > 0.9)


## The film's ritual: the organ's cadence, the console down, the festoon up, the lamps to a glow; all of it back at the
## end, with the console up again and the organ playing the house out.
func _ritual(room: Node3D) -> void:
	var host: Node = room.host
	var organ: Node = host.system("organ")
	var festoon: Node = host.system("festoon")
	var pipes: Node = host.system("pipes")
	host.snapshot_override = {"open": true, "playing": true, "position": 0.5, "duration": 7200.0}
	# The cadence comes once the bar playing now has ended (the organ writes its bars a little ahead).
	var cadence := false
	for i in 40:
		_steps(host, 0.25)
		cadence = cadence or pipes.bar_kind == "flourish"
	check("as the film starts, the organ's cadence", cadence)
	_steps(host, 20.0)
	check("in the film: the festoon up (%.2f), the console down (%.2f), the lamps at 15 %% (%.2f)" % [
			festoon.call("progress"), organ.call("progress"), host.param("light.house_lamps")],
			float(festoon.call("progress")) > 0.99 and float(organ.call("progress")) < 0.01
			and absf(float(host.param("light.house_lamps")) - 0.15) < 0.02)
	check("the organ rests for the film", pipes.resting() and not pipes.sounding())
	host.snapshot_override = {"open": true, "playing": false, "ended": true, "position": 7200.0, "duration": 7200.0}
	_steps(host, 25.0)
	check("at the end: the lamps up (%.2f), the festoon down (%.2f), the console up again (%.2f), the organ playing" % [
			host.param("light.house_lamps"), festoon.call("progress"), organ.call("progress")],
			float(host.param("light.house_lamps")) > 0.95 and float(festoon.call("progress")) < 0.01
			and float(organ.call("progress")) > 0.99 and pipes.get("_forced_on") == true)


## Pre-show off: the console stays in the pit and the organ silent.
func _pre_show_off(room: Node3D) -> void:
	var host: Node = room.host
	host.set_setting("ritual", false)
	var organ: Node = host.system("organ")
	var pipes: Node = host.system("pipes")
	host.snapshot_override = {"open": true, "playing": true, "position": 0.5, "duration": 7200.0}
	_steps(host, 20.0)
	check("Pre-show off: the film still dims the lamps (%.2f) and the console goes down (%.2f)" % [
			host.param("light.house_lamps"), organ.call("progress")],
			absf(float(host.param("light.house_lamps")) - 0.15) < 0.02 and float(organ.call("progress")) < 0.01)
	host.timeline.state = ""
	host.snapshot_override = {"open": false}
	var notes: int = pipes.notes_played
	_steps(host, 20.0)
	check("and before the next film the console stays down (%.2f), the organ silent (%d notes)" % [
			organ.call("progress"), pipes.notes_played - notes], float(organ.call("progress")) < 0.01
			and pipes.notes_played == notes)
	host.set_setting("ritual", true)


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
			var owner_name := str(g.get_parent().name) if g.get_parent() != room else ""
			rows.append([("%s/%s" % [owner_name, g.name]) if owner_name != "" else str(g.name), stats["draws"],
					stats["triangles"]])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return int(a[2]) > int(b[2]))
	for r: Array in rows:
		print("  part %-26s %2d draws %7d triangles" % r)


static func _steps(host: Node, seconds: float, dt := 0.25) -> void:
	var t := 0.0
	while t < seconds:
		host.step(dt)
		t += dt


func _render(doc: Dictionary) -> void:
	if not RoomRender.has_renderer():
		print("SKIP render (headless)")
		return
	var sc: Array = doc["screen"]["center"]
	var screen := Vector3(float(sc[0]), float(sc[1]), float(sc[2]))
	var baked := OS.get_environment("STREAM_BAKE") != "" and RoomBake.can_bake()
	var only := OS.get_environment("STREAM_ONLY")
	for phase: String in ["preshow", "film"]:
		if only != "" and only != phase:
			continue
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
			# Before the film the festoon is down over the screen: no picture lights the room.
			RenderingServer.global_shader_parameter_set("screen_glow", 0.0)
			for n: Node in (vc[2] as Node).get_children():
				if n is MeshInstance3D and (n as MeshInstance3D).mesh is QuadMesh:
					var m := (n as MeshInstance3D).material_override as StandardMaterial3D
					if m != null:
						m.albedo_texture = null
						m.albedo_color = Color(0.02, 0.02, 0.02)
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
		var p := "stream_%s%s_" % ["baked_" if baked else "", phase]
		var img: Image = await RoomRender.shot(self, vc, eye, screen, p + "seat")
		# How lit the walls and the proscenium are beside the picture (printed for the docs).
		var walls := (RoomRender.mean(img, Rect2(0.04, 0.3, 0.12, 0.3)).get_luminance()
				+ RoomRender.mean(img, Rect2(0.84, 0.3, 0.12, 0.3)).get_luminance()) * 0.5
		var proscenium := RoomRender.mean(img, Rect2(0.25, 0.15, 0.06, 0.25)).get_luminance()
		var picture := RoomRender.mean(img, Rect2(0.4, 0.42, 0.2, 0.12)).get_luminance()
		print("  render: %s from the seat: the walls %.3f, the proscenium %.3f, the picture %.3f" % [phase, walls,
				proscenium, picture])
		await RoomRender.shot(self, vc, eye, eye + Vector3(-1.0, 0.2, -0.3), p + "left")
		await RoomRender.shot(self, vc, eye, eye + Vector3(1.0, 0.2, -0.3), p + "right")
		await RoomRender.shot(self, vc, eye, eye + Vector3(0.0, 1.0, -0.2), p + "up")
		await RoomRender.shot(self, vc, eye, eye + Vector3(0.0, 0.1, 1.0), p + "back")
		await RoomRender.shot(self, vc, eye, eye + Vector3(0.0, 0.6, 1.0), p + "back_up")
		var side := Vector3(-6.0, 0, 3.0)
		var best := Vector3(999, 0, 0)
		for t: Transform3D in (vc[2] as Node).call("room_seat_transforms"):
			if t.origin.distance_to(side) < best.distance_to(side):
				best = t.origin
		await RoomRender.shot(self, vc, best + Vector3(0, 1.2, 0), screen, p + "side_seat")
		await RoomRender.shot(self, vc, best + Vector3(0, 1.2, 0), best + Vector3(-1.0, 1.5, -0.4), p + "side_wall")
		(vc[1] as Camera3D).fov = 45.0
		await RoomRender.shot(self, vc, eye, Vector3(0.0, 3.0, -14.0), p + "proscenium")
		await RoomRender.shot(self, vc, eye, Vector3(0.0, -1.0, -11.5), p + "console")
		await RoomRender.shot(self, vc, eye, Vector3(-9.0, 4.0, -6.0), p + "left_near")
		await RoomRender.shot(self, vc, eye, Vector3(0.0, 9.0, -6.0), p + "ceiling")
		await RoomRender.shot(self, vc, Vector3(-2.0, -0.6, -8.0), Vector3(0.0, -1.7, -11.35), p + "console_close")
		await RoomRender.shot(self, vc, eye, Vector3(0.0, 3.0, 6.2), p + "circle")
		(vc[1] as Camera3D).fov = 70.0
		await RoomRender.shot(self, vc, Vector3(8.8, 1.7, 0.6), Vector3(8.6, -2.2, -8.0), p + "aisle")
		await RoomRender.shot(self, vc, Vector3(-6.0, -1.2, -9.4), Vector3(-9.0, 1.0, -12.0), p + "grille")
		(vc[1] as Camera3D).fov = 90.0
		if phase == "preshow":
			# The coves in jade and in rose (the Changing cycle's other colours).
			for col: Array in [["jade", JADE], ["rose", Color(1.0, 0.5, 0.58)]]:
				for sid: String in ["moderne", "console"]:
					host.fade(sid + ".cove_colour", col[1], 0.05)
				for i in 4:
					host.step(0.05)
				await RoomRender.shot(self, vc, eye, screen, p + "seat_" + str(col[0]))
				await RoomRender.shot(self, vc, eye, eye + Vector3(-1.0, 0.7, -0.6), p + "up_left_" + str(col[0]))
		await RoomRender.close(self, vc)
