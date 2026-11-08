extends "res://tests/env_builder_harness.gd"

## Pink Palace (app/environments/pink_palace.env.json; docs/environments.md, "Room: Pink Palace"): a dream palace in
## sugared almond colours, the hall the inside of a great scallop shell. Built headless from its document and checked
## as every shipped room is (schema, budget, sight lines from every seat including the balcony's, comfort, licences,
## names, no people); then what makes it this room: its figures and parts, light in the bake only (the sconces, the
## fans, the vault's glow down the walls, the downlights' pools, the chandelier), the shell vault (ribs pink on the
## crest and blue in the trough, graded from the cornice's lamps, gilt rays), the rings round the picture, the festoon
## (down to the stage, up clear of the picture, its gold fringe), the balcony's buttoned front under the front row's
## sight line, the troughs' slow colour (pink to blue and back before the film; the film's colour at a glow in it), the
## sunburst (the dome's lamps swell and fall before the film, never in it), the ritual and its return, Pre-show off,
## and the room's level (tests/room_sound.gd).
## Under lavapipe it draws the room from its own seat, a side seat, the balcony, up and back, in the pre-show and with
## a film playing (PINK_BAKE=1 bakes it first; PINK_RENDER_ONLY=1 skips the checks; PINK_ONLY=preshow or film draws
## one; PINK_QUICK=1 draws the seat and one wall only).
## godot --headless --xr-mode off --path app --script res://tests/test_room_pink_palace.gd

const RoomRender := preload("res://tests/room_render.gd")
const RoomSound := preload("res://tests/room_sound.gd")
const RoomBake := preload("res://scripts/env/room_bake.gd")
const PinkPalace := preload("res://scripts/env/systems/kit/pink_palace.gd")
const DOC := "res://environments/pink_palace.env.json"
const BAKE_ID := "pink_palace_render_test"
const PINK := Color(1.0, 0.6, 0.7)


func run_tests() -> void:
	test_name = "test_room_pink_palace"
	var r := EnvDoc.load_file(DOC)
	check("the document reads (%s)" % [r["errors"]], (r["errors"] as Array).is_empty())
	var doc: Dictionary = r["doc"]
	if doc.is_empty():
		return
	if OS.get_environment("PINK_RENDER_ONLY") == "":
		var room := await check_room("pink_palace", doc)
		_by_part(room)
		_built(room)
		_vault(room)
		_balcony(room)
		_festoon(room)
		_troughs(room)
		_sunburst(room)
		_ritual(room)
		_pre_show_off(room)
		await done(room)
		await RoomSound.check_level(self, self, "pink_palace", doc)
	await _render(doc)


## The figures (docs/environments.md, "Room: Pink Palace"), the parts, the bake's lights.
func _built(room: Node3D) -> void:
	var host: Node = room.host
	var stats := EnvChecks.measure(room)
	check("the figures as documented: 26 to 32 draws, under 290k triangles, no live light, no particles, under 16 MB "
			+ "(%s)" % [stats], int(stats["draws"]) >= 26 and int(stats["draws"]) <= 32
			and int(stats["triangles"]) < 290000 and int(stats["lights"]) == 0 and int(stats["particles"]) == 0
			and float(stats["texture_mb"]) < 16.0)
	for n: String in ["PieceStatic", "PieceSoft", "PieceCove", "PieceLamps", "Festoon", "Seats", "Balcony"]:
		check("the room has its %s" % n, room.find_child(n, true, false) != null)
	for sid: String in ["palace", "sunburst"]:
		check("the %s kit draws without a problem (%s)" % [sid, host.system(sid).problems()],
				(host.system(sid).problems() as Array).is_empty())
	var hall: Node = host.system("hall")
	check("the hall gives way to the kit: no walls, ceiling, drapes or sconces of its own (%s)" % [[
			hall.params["side_walls"], hall.params["ceiling_cover"], hall.params["proscenium"],
			hall.params["sconce_joints"]]], not bool(hall.params["side_walls"])
			and float(hall.params["ceiling_cover"]) == 0.0 and str(hall.params["proscenium"]) == "none"
			and (hall.params["sconce_joints"] as Array).is_empty() and room.find_child("Walls", true, false) == null
			and room.find_child("Ceiling", true, false) == null and room.find_child("Curtains", true, false) == null)
	check("the hall's ceiling raised for the dome (%.1f m), the seats where they were (%d)" % [
			float(hall.params["room_max"][1]), room.room_seat_transforms().size()],
			float(hall.params["room_max"][1]) >= PinkPalace.DOME_TOP + 0.1 and room.room_seat_transforms().size() == 356)
	# Light in the bake only: the sconces and fans, the vault's glow down the walls, the rear shell's lamp, the
	# downlights' pools, the chandelier; all hidden, none live.
	var glows := room.find_children("KitGlow*", "OmniLight3D", true, false)
	var spots := room.find_children("KitSpot*", "SpotLight3D", true, false)
	var lamps := room.find_children("KitLamp*", "OmniLight3D", true, false)
	var hidden := true
	for l: Node in glows + spots + lamps:
		hidden = hidden and not (l as Light3D).visible
	check("the sconces, fans and coves light the bake (%d), the downlights (%d), the chandelier (%d), hidden" % [
			glows.size(), spots.size(), lamps.size()], glows.size() >= 20 and spots.size() == 3 and lamps.size() == 1
			and hidden)


## The shell vault: graded light (bright by the cornice, much of it in shadow), crests pink and troughs blue, the gilt
## rays; the dome's lamps light its foot more than its apex.
func _vault(room: Node3D) -> void:
	var cove := room.find_child("PieceCove", true, false) as MeshInstance3D
	var cols: PackedColorArray = cove.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var lit := 0
	var dark := 0
	var pinkish := 0
	var blueish := 0
	for c: Color in cols:
		if c.a > 0.6:
			lit += 1
		elif c.a < 0.15:
			dark += 1
		if c.r > c.b * 1.2:
			pinkish += 1
		elif c.b > c.r:
			blueish += 1
	check("the vault and rings graded: some bright by the lamps (%d), much in shadow (%d) of %d" % [lit, dark,
			cols.size()], lit > cols.size() / 20 and dark > cols.size() / 10)
	check("pink crests and blue troughs (%d pink, %d blue)" % [pinkish, blueish], pinkish > cols.size() / 5
			and blueish > cols.size() / 5)
	var dome: Node = room.host.system("sunburst")
	var dm: MeshInstance3D = null
	for n: Node in dome.owned():
		if n is MeshInstance3D and str(n.name).begins_with("PieceCove"):
			dm = n as MeshInstance3D
	check("the dome has its own coves (its own colour)", dm != null and dm != cove)
	if dm != null:
		var verts: PackedVector3Array = dm.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var dcols: PackedColorArray = dm.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		var foot := 0.0
		var nf := 0
		var apex := 0.0
		var na := 0
		for i in verts.size():
			if verts[i].y < PinkPalace.CROWN + PinkPalace.DRUM + 0.05 and verts[i].y > PinkPalace.CROWN:
				foot += dcols[i].a
				nf += 1
			elif verts[i].y > PinkPalace.DOME_TOP - 0.1:
				apex += dcols[i].a
				na += 1
		check("the dome lit from its foot (%.2f) more than its apex (%.2f)" % [foot / maxf(nf, 1), apex / maxf(na, 1)],
				nf > 0 and na > 0 and foot / nf > 2.0 * apex / na)


## The balcony's front: the builder's parapet lowered under the buttoned roll, and the front row sees the picture's
## foot over it (the sight-line check covers every seat; this is the reason).
func _balcony(room: Node3D) -> void:
	var hall: Node = room.host.system("hall")
	check("the balcony's parapet at 0.8 m, under the buttoned front's roll", is_equal_approx(float(
			hall.params["balcony_parapet"]), 0.8))
	var front := 0
	for t: Transform3D in room.room_seat_transforms():
		if t.origin.y > 4.0 and t.origin.z < 4.2:
			front += 1
	check("the balcony's front row is there (%d seats)" % front, front >= 25)


## The festoon: in front of the picture until it rises; down, to the stage; up, its lowest swag over the picture's top;
## a gold fringe on its hem (a second surface).
func _festoon(room: Node3D) -> void:
	var host: Node = room.host
	var doc: Dictionary = room.get("doc")
	var sc: Array = doc["screen"]["center"]
	var sz: Array = doc["screen"]["size"]
	var top := float(sc[1]) + float(sz[1]) * 0.5
	var festoon: Node = host.system("festoon")
	var cloth := festoon.call("target") as MeshInstance3D
	check("the festoon is in front of the picture until it rises", cloth != null and cloth.is_in_group("env_in_front"))
	host.timeline.state = ""
	host.snapshot_override = {"open": false}
	_steps(host, 2.0)
	check("its gold fringe along the hem (%d surfaces)" % cloth.mesh.get_surface_count(),
			cloth.mesh.get_surface_count() == 2)
	var down := cloth.global_transform * cloth.get_aabb()
	var stage := float(host.system("hall").params["stage_top"])
	check("down, the festoon reaches the stage (%.2f, the stage %.2f)" % [down.position.y, stage],
			down.position.y < stage + 0.1)
	check("and fills the first ring's opening (%.2f wide, the ring %.2f)" % [down.size.x, PinkPalace.RING_HALF * 2.0],
			down.size.x > PinkPalace.RING_HALF * 2.0 - 0.3)
	festoon.act("snap", {"at": 1.0})
	_steps(host, 0.5)
	var up := _lowest(cloth)
	check("up, its lowest swag and fringe clear the picture's top (%.2f over %.2f)" % [up, top], up > top + 0.03)
	festoon.act("snap", {"at": 0.0})
	_steps(host, 0.5)


static func _lowest(mi: MeshInstance3D) -> float:
	var lo := INF
	var xf := mi.global_transform
	for s in mi.mesh.get_surface_count():
		for v: Vector3 in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			lo = minf(lo, (xf * v).y)
	return lo


## The troughs' light: pink by default, slowly to blue and back before the film; the film's colour at a glow in it.
func _troughs(room: Node3D) -> void:
	var host: Node = room.host
	var kit: Node = host.system("palace")
	check("the troughs pink by default (%s)" % kit.cove_colour_now(), kit.cove_colour_now().is_equal_approx(PINK))
	host.timeline.state = ""
	host.snapshot_override = {"open": false}
	var seen := {}
	var bluest := 0.0
	var fastest := 0.0
	var last: Color = kit.cove_colour_now()
	var t := 0.0
	while t < 60.0:
		_steps(host, 0.5)
		var c: Color = kit.cove_colour_now()
		if OS.get_environment("PINK_DEBUG") != "" and fmod(t, 5.0) < 0.01:
			print("  troughs t %.1f state %s colour %s param %s film %s %s" % [t, host.timeline.state, c,
					host.param("palace.cove_colour"), host.param("palace.cove_film"),
					host.param("palace.cove_film_colour")])
		seen["%.1f %.1f %.1f" % [c.r, c.g, c.b]] = true
		bluest = maxf(bluest, c.b - c.r)
		fastest = maxf(fastest, Vector3(c.r - last.r, c.g - last.g, c.b - last.b).length() / 0.5)
		last = c
		t += 0.5
	check("before the film they move pink to blue and back (%d colours, bluest %.2f)" % [seen.size(), bluest],
			seen.size() >= 4 and bluest > 0.2)
	check("slowly: under a tenth of the way a second (%.3f)" % fastest, fastest < 0.06)
	var pre: Dictionary = kit.cove_state()
	host.signals.fake("film.colour", Color(0.1, 0.3, 0.9))
	host.signals.fake("playback.playing", 1.0)
	host.snapshot_override = {"open": true, "playing": true, "position": 0.5, "duration": 7200.0}
	_steps(host, 25.0)
	var film: Dictionary = kit.cove_state()
	var fc: Color = film["colour"]
	check("in the film the troughs take the film's colour (%s)" % fc, fc.b > fc.r and fc.b > 0.5)
	check("and sink to a glow: under a tenth of the pre-show's (%.3f, %.3f)" % [float(film["glow"]),
			float(pre["glow"])], float(film["glow"]) < float(pre["glow"]) * 0.1)
	host.signals.clear_fakes()


## The sunburst: the dome's lamps swell and fall before the film (slowly), and rest steady in it.
func _sunburst(room: Node3D) -> void:
	var host: Node = room.host
	host.snapshot_override = {"open": false}
	host.timeline.state = ""
	_steps(host, 1.0)
	var lo := 1.0
	var hi := 0.0
	var t := 0.0
	while t < 34.0:
		_steps(host, 0.25)
		var v := float(host.param("sunburst.cove"))
		lo = minf(lo, v)
		hi = maxf(hi, v)
		t += 0.25
	check("before the film the sunburst swells and falls (%.2f .. %.2f)" % [lo, hi], lo < 0.7 and hi > 0.95)
	host.signals.fake("playback.playing", 1.0)
	host.snapshot_override = {"open": true, "playing": true, "position": 0.5, "duration": 7200.0}
	_steps(host, 12.0)
	var a := float(host.param("sunburst.cove"))
	_steps(host, 9.0)
	var b := float(host.param("sunburst.cove"))
	check("in the film it rests at its glow (%.2f, %.2f)" % [a, b], absf(a - b) < 0.01 and a < 0.6)
	host.signals.clear_fakes()


## The ritual: the bells, the festoon up, the lamps to 15 %; at the end the lamps up and the festoon down.
func _ritual(room: Node3D) -> void:
	var host: Node = room.host
	var festoon: Node = host.system("festoon")
	var bells: Node = host.system("bells")
	host.timeline.state = ""
	host.snapshot_override = {"open": false}
	_steps(host, 10.0)
	var rung: int = bells.plays
	host.snapshot_override = {"open": true, "playing": true, "position": 0.5, "duration": 7200.0}
	_steps(host, 28.0)
	check("in the film: the bells rang once (%d), the festoon up (%.2f), the lamps at 15 %% (%.2f)" % [
			bells.plays - rung, festoon.call("progress"), host.param("light.house_lamps")], bells.plays - rung == 1
			and float(festoon.call("progress")) > 0.99 and absf(float(host.param("light.house_lamps")) - 0.15) < 0.02)
	host.snapshot_override = {"open": true, "playing": false, "ended": true, "position": 7200.0, "duration": 7200.0}
	_steps(host, 25.0)
	check("at the end: the lamps up (%.2f), the festoon down (%.2f)" % [host.param("light.house_lamps"),
			festoon.call("progress")], float(host.param("light.house_lamps")) > 0.95
			and float(festoon.call("progress")) < 0.01)


## Pre-show off: no bells, but the film still dims the lamps and the festoon still rises.
func _pre_show_off(room: Node3D) -> void:
	var host: Node = room.host
	host.set_setting("ritual", false)
	var festoon: Node = host.system("festoon")
	var bells: Node = host.system("bells")
	host.timeline.state = ""
	host.snapshot_override = {"open": false}
	_steps(host, 6.0)
	var rung: int = bells.plays
	host.snapshot_override = {"open": true, "playing": true, "position": 0.5, "duration": 7200.0}
	_steps(host, 28.0)
	check("Pre-show off: no bells (%d), the lamps down (%.2f), the festoon up (%.2f)" % [bells.plays - rung,
			host.param("light.house_lamps"), festoon.call("progress")], bells.plays == rung
			and absf(float(host.param("light.house_lamps")) - 0.15) < 0.02 and float(festoon.call("progress")) > 0.99)
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
	var baked := OS.get_environment("PINK_BAKE") != "" and RoomBake.can_bake()
	var only := OS.get_environment("PINK_ONLY")
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
		var p := "pink_%s%s_" % ["baked_" if baked else "", phase]
		var img: Image = await RoomRender.shot(self, vc, eye, screen, p + "seat")
		# How lit the walls and the proscenium are beside the picture (printed for the docs).
		var walls := (RoomRender.mean(img, Rect2(0.04, 0.3, 0.12, 0.3)).get_luminance()
				+ RoomRender.mean(img, Rect2(0.84, 0.3, 0.12, 0.3)).get_luminance()) * 0.5
		var proscenium := RoomRender.mean(img, Rect2(0.25, 0.15, 0.06, 0.25)).get_luminance()
		var picture := RoomRender.mean(img, Rect2(0.4, 0.42, 0.2, 0.12)).get_luminance()
		print("  render: %s from the seat: the walls %.3f, the proscenium %.3f, the picture %.3f" % [phase, walls,
				proscenium, picture])
		if OS.get_environment("PINK_QUICK") != "":
			(vc[1] as Camera3D).fov = 45.0
			await RoomRender.shot(self, vc, eye, Vector3(-9.0, 4.0, -6.0), p + "left_near")
			await RoomRender.close(self, vc)
			continue
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
		# The balcony's front row, middle, and from there looking back and up.
		await RoomRender.shot(self, vc, Vector3(0.3, 5.65, 4.1), screen, p + "balcony")
		await RoomRender.shot(self, vc, Vector3(0.3, 5.65, 4.1), Vector3(0.3, 7.4, 6.2), p + "balcony_back")
		(vc[1] as Camera3D).fov = 45.0
		await RoomRender.shot(self, vc, eye, Vector3(0.0, 3.0, -14.0), p + "proscenium")
		await RoomRender.shot(self, vc, eye, Vector3(-9.0, 4.0, -6.0), p + "left_near")
		await RoomRender.shot(self, vc, eye, Vector3(0.0, 9.0, -4.0), p + "ceiling")
		await RoomRender.shot(self, vc, eye, Vector3(0.0, 4.5, 6.2), p + "circle")
		await RoomRender.shot(self, vc, Vector3(-3.0, -1.6, -8.0), Vector3(-1.5, -1.0, -12.6), p + "footlights")
		await RoomRender.shot(self, vc, eye, Vector3(-9.6, 1.5, -6.7), p + "mirror")
		(vc[1] as Camera3D).fov = 90.0
		if phase == "preshow":
			# The troughs at the blue end of their slow cycle.
			host.fade("palace.cove_colour", Color(0.62, 0.72, 1.0), 0.05)
			for i in 4:
				host.step(0.05)
			await RoomRender.shot(self, vc, eye, screen, p + "seat_blue")
			await RoomRender.shot(self, vc, eye, eye + Vector3(-1.0, 0.7, -0.6), p + "up_left_blue")
		await RoomRender.close(self, vc)
