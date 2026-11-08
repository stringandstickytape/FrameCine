extends "res://tests/env_builder_harness.gd"

## The Nave (app/environments/nave.env.json; docs/environments.md, "Room: Nave"): a Gothic church at night with the
## screen in its chancel. Built headless from its document and checked as every shipped room is (schema, budget,
## sight lines from every seat, comfort, licences, names, no people) and as a builder's room (seats, physics, bake,
## seat picking); then what makes it this room: its figures and parts (kit/nave_gothic.gd: the stone, the carving,
## the dark shafts, the vaults, the floor with its ledger stones, the carved pews, the reredos, the glass), the
## bake's atlases kept small, the candles (stands beside the picture never before it, the coronae high over the
## nave, the votive lights) by the Candles setting, each lighting the bake only, the Moon's light through the south
## windows only, the ritual (the candles low for the film, the rose and the windows dimmer; all back at the end), the
## flicker under 3 Hz and held by Flickering lights; the stone's reverb, the wind high up, the owl far off and quiet in
## the film, the bell before the film and after it, never during it, and the room's level (tests/room_sound.gd).
## Under lavapipe it draws the room from its own seat, left, right, up, back and a side seat, in the pre-show and with
## a film playing (NAVE_BAKE=1 bakes it first; NAVE_RENDER_ONLY=1 skips the checks; NAVE_SHOTS=preshow or film draws
## one of them; NAVE_CANDLES=none, few or many sets the setting first).
## godot --headless --xr-mode off --path app --script res://tests/test_room_nave.gd

const RoomRender := preload("res://tests/room_render.gd")
const RoomSound := preload("res://tests/room_sound.gd")
const RoomBake := preload("res://scripts/env/room_bake.gd")
const Builder := preload("res://scripts/env/systems/kit/builder.gd")
const DOC := "res://environments/nave.env.json"
const BAKE_ID := "nave_render_test"
## The room's figures (docs/environments.md, "Room: Nave").
const FIGURES := {"draws": 26, "triangles": 200000, "lights": 0, "particles": 0, "texture_mb": 16.0}
## The bake: each atlas at most this a side, and all of them together at most this many texels (the headset bakes the
## room when it is chosen; the atlases set how long that takes).
const ATLAS_SIDE := 1024
const ATLAS_TEXELS := 1500000


func run_tests() -> void:
	test_name = "test_room_nave"
	var r := EnvDoc.load_file(DOC)
	check("the document reads (%s)" % [r["errors"]], (r["errors"] as Array).is_empty())
	var doc: Dictionary = r["doc"]
	if doc.is_empty():
		return
	if OS.get_environment("NAVE_RENDER_ONLY") == "":
		var t0 := Time.get_ticks_msec()
		var room := await check_room("nave", doc)
		print("  built and checked in %d ms" % (Time.get_ticks_msec() - t0))
		room.host.auto = false
		_by_part(room)
		_built(room)
		_bake(room)
		_candles(room)
		await _setting(room)
		_moon(room)
		_ritual(room)
		_sound(room)
		await done(room)
		await RoomSound.check_level(self, self, "nave", doc)
	await _render(doc)


## The figures and the parts; the church draws its own pews.
func _built(room: Node3D) -> void:
	var host: Node = room.host
	var stats := EnvChecks.measure(room)
	check("the figures as documented: at most %s (%s)" % [FIGURES, stats], EnvChecks.budget(stats, FIGURES).is_empty())
	for n: String in ["Stone", "Carving", "Shafts", "Vault", "Floor", "Pews", "Cloth", "Iron", "Gilt", "Glass", "Rose",
			"Candles", "Flames", "Candles_accent", "Flames_accent", "Votives", "Flames_stage"]:
		check("the church has its %s" % n, room.find_child(n, true, false) != null)
	var nave: Node = host.system("nave")
	check("the nave is gothic, rib-vaulted", str(nave.params["style"]) == "gothic" and str(nave.params["vault"]) == "rib")
	check("no seats system: the church draws its pews (baked), and their physics", host.system("seats") == null
			and not nave.draws_seats_elsewhere() and room.collision_shapes().size() > 30)
	var church: Object = nave.get("church")
	check("ledger stones in the floor (%d)" % church.ledgers.size(), church.ledgers.size() >= 4)
	# The poppy heads stay low enough for the sight line (checked from every seat by check_room) and the pews' backs
	# under a metre.
	var pews := room.find_child("Pews", true, false) as MeshInstance3D
	var top := -INF
	for v: Vector3 in pews.mesh.get_faces():
		# The oak mesh holds the reredos and the doors too: the pews' part only.
		if absf(v.x) < 3.0 and v.z > -4.6 and v.z < 5.6:
			top = maxf(top, v.y)
	check("the pews' poppy heads at most 1.21 m (%.2f)" % top, top < 1.21)
	# The rose over the reredos, clear of the picture.
	var rose := (room.find_child("Rose", true, false) as MeshInstance3D).get_aabb()
	var sc: Array = room.doc["screen"]["center"]
	var ss: Array = room.doc["screen"]["size"]
	var screen_top := float(sc[1]) + float(ss[1]) * 0.5
	check("the rose window over the screen, clear of it (its foot %.2f, the picture's top %.2f)" % [rose.position.y,
			screen_top], rose.position.y > screen_top + 1.0)


## The bake: static meshes with small atlases, the candles' and the Moon's lights for the bake only.
func _bake(room: Node3D) -> void:
	var total := 0
	var largest := Vector2i.ZERO
	for mi: MeshInstance3D in room.static_meshes():
		var hint := (mi.mesh as ArrayMesh).lightmap_size_hint
		largest = largest.max(hint)
		total += hint.x * hint.y
	print("  bake: %d static meshes, %d texels, the largest atlas %s" % [room.static_meshes().size(), total, largest])
	check("each atlas at most %d a side (%s)" % [ATLAS_SIDE, largest], largest.x <= ATLAS_SIDE
			and largest.y <= ATLAS_SIDE)
	check("all the atlases at most %d texels (%d)" % [ATLAS_TEXELS, total], total <= ATLAS_TEXELS)
	var lights := room.find_children("*", "Light3D", true, false)
	var hidden := lights.all(func(l: Node) -> bool: return not (l as Light3D).visible)
	check("every light is for the bake only, hidden (%d)" % lights.size(), not lights.is_empty() and hidden)
	check("no live light", EnvChecks.measure(room)["lights"] == 0)


## The candles: beside the picture or high over the nave, never in front of it; their flames flicker under 3 Hz.
func _candles(room: Node3D) -> void:
	var nave: Node = room.host.system("nave")
	var church: Object = nave.get("church")
	var sc: Array = room.doc["screen"]["center"]
	var ss: Array = room.doc["screen"]["size"]
	var half := float(ss[0]) * 0.5
	var near := 0
	var groups := {}
	for cd: Array in church.candles:
		var at: Vector3 = cd[0]
		groups[cd[1]] = int(groups.get(cd[1], 0)) + 1
		# Seen from the viewer's seat: within the picture's frame is too near.
		var dir := (at - Vector3(0, 1.2, 0)).normalized()
		var to_edge := (Vector3(half + 0.3, float(sc[1]), float(sc[2])) - Vector3(0, 1.2, 0)).normalized()
		var to_top := (Vector3(0, float(sc[1]) + float(ss[1]) * 0.5 + 0.3, float(sc[2])) - Vector3(0, 1.2, 0)).normalized()
		var across := absf(dir.x / -dir.z) < absf(to_edge.x / -to_edge.z)
		var under_top := dir.y / -dir.z < to_top.y / -to_top.z
		if dir.z < 0.0 and across and under_top:
			near += 1
	print("  candles by group: %s" % [groups])
	check("candles by the chancel (house: %d), on the coronae (accent: %d), votives (stage: %d)" % [groups.get("house",
			0), groups.get("accent", 0), groups.get("stage", 0)], int(groups.get("house", 0)) == 4
			and int(groups.get("accent", 0)) == 36 and int(groups.get("stage", 0)) > 10)
	check("no candle within the picture's frame from the seat (%d)" % near, near == 0)
	for f: float in Builder.FLICKER_HZ:
		check("a flicker under 3 Hz (%.2f)" % f, f < 3.0)
	var values: Array[float] = []
	for i in 90:
		room.host.step(1.0 / 30.0)
		values.append(nave.flicker_factor())
	check("the flames waver (%.3f..%.3f), gently" % [values.min(), values.max()], values.max() - values.min() > 0.02
			and values.max() - values.min() < 0.3)
	var stands := room.find_children("Stand*", "OmniLight3D", true, false)
	var coronae := room.find_children("Corona*", "OmniLight3D", true, false)
	check("each stand and corona lights the bake (%d, %d)" % [stands.size(), coronae.size()], stands.size() == 4
			and coronae.size() == 3)


## Candles none: the church by moonlight (no flames, no candle light in the bake); many: four stands a side.
func _setting(room: Node3D) -> void:
	var host: Node = room.host
	host.set_setting("candles", "none")
	await process_frame
	var lit := room.find_children("Flames*", "MeshInstance3D", true, false).filter(func(n: Node) -> bool:
			return not n.is_queued_for_deletion())
	var bake := room.find_children("Corona*", "OmniLight3D", true, false) + room.find_children("Stand*", "OmniLight3D",
			true, false)
	bake = bake.filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
	check("Candles none: no flames (%d), no candle light in the bake (%d)" % [lit.size(), bake.size()], lit.is_empty()
			and bake.is_empty())
	check("Candles none: the coronae still hang, unlit", room.find_child("Iron", true, false) != null)
	host.set_setting("candles", "many")
	await process_frame
	var church: Object = host.system("nave").get("church")
	var house: Array = church.candles.filter(func(cd: Array) -> bool: return cd[1] == "house")
	check("Candles many: four stands a side (%d)" % house.size(), house.size() == 8)
	var many := EnvChecks.measure(room)
	check("Candles many: inside the figures (%s)" % [many], EnvChecks.budget(many, FIGURES).is_empty())
	var blocked: Array = await EnvChecks.sight_line(self, room)
	check("Candles many: a clear sight line from every seat %s" % [blocked], blocked.is_empty())
	host.set_setting("candles", "few")
	await process_frame
	host.set_setting("flicker", false)
	check("Flickering lights off holds the flames", float(host.system("nave").params["flicker"]) == 0.0)
	host.set_setting("flicker", true)


## The Moon through the south windows only, from high up, down and across to the north.
func _moon(room: Node3D) -> void:
	var spots := room.find_children("Moon*", "SpotLight3D", true, false)
	var south := spots.all(func(l: Node) -> bool: return (l as Node3D).position.x > 3.0)
	var down := spots.all(func(l: Node) -> bool:
			var d := -(l as Node3D).transform.basis.z
			return d.y < -0.5 and d.x < -0.3)
	check("the Moon through the south windows (%d), down and across" % spots.size(), spots.size() >= 8 and south
			and down)


## The ritual: the candles sink low for the film (the chancel's lowest), the rose and the windows dimmer; all back at
## the end.
func _ritual(room: Node3D) -> void:
	var host: Node = room.host
	var nave: Node = host.system("nave")
	host.timeline.state = ""
	host.snapshot_override = {"open": false}
	_steps(host, 15.0)
	var before := [float(host.param("light.house_lamps")), float(host.param("light.accent")),
			float(nave.params["rose_glow"]), float(nave.params["window_glow"])]
	check("before the film: the candles bright, the rose and the windows as designed (%s)" % [before],
			before[0] > 0.95 and before[1] > 0.95 and is_equal_approx(before[2], 0.25) and is_equal_approx(before[3], 0.3))
	host.snapshot_override = {"open": true, "playing": true, "position": 0.5, "duration": 7200.0}
	_steps(host, 20.0)
	var during := [float(host.param("light.house_lamps")), float(host.param("light.accent")),
			float(host.param("light.step_lights")), float(nave.params["rose_glow"]), float(nave.params["window_glow"])]
	check("with the film: the chancel's candles low, the coronae a little higher, the rose and the windows dim (%s)"
			% [during], absf(during[0] - 0.2) < 0.02 and absf(during[1] - 0.3) < 0.02 and absf(during[2] - 0.35) < 0.02
			and absf(during[3] - 0.12) < 0.02 and absf(during[4] - 0.2) < 0.02)
	host.snapshot_override = {"open": true, "playing": false, "ended": true, "position": 7200.0, "duration": 7200.0}
	_steps(host, 15.0)
	check("all back at the end (%.2f, %.2f, %.2f)" % [float(host.param("light.house_lamps")),
			float(host.param("light.accent")), float(nave.params["rose_glow"])],
			float(host.param("light.house_lamps")) > 0.95 and float(host.param("light.accent")) > 0.95
			and is_equal_approx(float(nave.params["rose_glow"]), 0.25))


## The stone's long reverb; the wind high in the vault; a candle now and then; the owl far off, a whisper in the
## film; the bell only before the film and after it.
func _sound(room: Node3D) -> void:
	var host: Node = room.host
	RoomSound.check_beds(self, "nave", room, {"wind": "wind", "candle": "candle", "owl": "tawny_owl",
			"bell": "church_bell"}, "stone_nave")
	var owl: Node = host.system("owl")
	var at: Array = owl.params["at"]
	check("the owl outside, far off (%.0f m), much quieter in the film (%.0f dB)" % [Vector3(at[0], at[1],
			at[2]).length(), float(owl.params["film_db"])], Vector3(at[0], at[1], at[2]).length() > 20.0
			and float(owl.params["film_db"]) <= -12.0)
	var bell: Node = host.system("bell")
	check("the bell plays only when a cue asks", float(bell.params["every"]) == 0.0)
	for cue: Dictionary in room.doc["cues"]:
		if str(cue["name"]).begins_with("bell"):
			var states: Array = cue.get("states", [cue["when"].get("state", "")])
			check("the cue %s only before or after the film (%s)" % [cue["name"], states], not ("playing" in states)
					and not ("starting" in states) and not ("credits" in states))
	check("no music (no organ)", host.systems_of_kind("music").is_empty())


static func _steps(host: Node, seconds: float, dt := 0.25) -> void:
	var t := 0.0
	while t < seconds:
		host.step(dt)
		t += dt


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
			if mi.mesh is ArrayMesh and (mi.mesh as ArrayMesh).lightmap_size_hint.x > 0:
				print("  atlas %-21s %s" % [mi.name, (mi.mesh as ArrayMesh).lightmap_size_hint])
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
	var baked := OS.get_environment("NAVE_BAKE") != "" and RoomBake.can_bake()
	var only := OS.get_environment("NAVE_SHOTS")
	for phase: String in ["preshow", "film"]:
		if only != "" and not (phase in only):
			continue
		RoomRender.set_light(screen, 0.05 if phase == "preshow" else 0.015)
		var vc := await RoomRender.open(self, doc)
		var host: Node = (vc[2] as Node).host
		# The stand-in picture is a plain quad under the room: out of the bake (else its colours light the whole
		# church; the headset's screen is not under the room, so its bake never takes it).
		for mi: Node in (vc[2] as Node).get_children():
			if mi is MeshInstance3D and (mi as MeshInstance3D).mesh is QuadMesh:
				(mi as MeshInstance3D).gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		if OS.get_environment("NAVE_CANDLES") != "":
			host.set_setting("candles", OS.get_environment("NAVE_CANDLES"))
			for i in 2:
				await process_frame
		if baked:
			var room := vc[2] as Node3D
			RoomBake.clear(BAKE_ID)
			RoomBake.prepare(room, BAKE_ID)
			room.call("set_baking", true)
			var t0 := Time.get_ticks_msec()
			var br: Dictionary = RoomBake.bake(room, BAKE_ID)
			room.call("set_baking", false)
			print("  render: baked in %d ms %s" % [Time.get_ticks_msec() - t0, br])
			for i in 4:
				await process_frame
		if phase == "preshow":
			RenderingServer.global_shader_parameter_set("screen_glow", 0.15)
			host.snapshot_override = {"open": false}
			host.signals.fake("film.brightness", 0.0)
		else:
			host.snapshot_override = {"open": true, "playing": true, "position": 0.5, "duration": 7200.0}
			host.signals.fake("film.brightness", 0.7)
			host.signals.fake("film.colour", Color(0.85, 0.55, 0.35))
			host.signals.fake("playback.playing", 1.0)
		for i in 120:
			host.step(0.25)
		print("  render: %s, the light system baked: %s" % [phase, host.system("light").is_baked()])
		var eye := Vector3(0, 1.2, 0)
		var p := "nave_%s%s_" % ["baked_" if baked else "", phase]
		await RoomRender.shot(self, vc, eye, screen, p + "seat")
		await RoomRender.shot(self, vc, eye, eye + Vector3(-1.0, 0.15, -0.4), p + "left")
		await RoomRender.shot(self, vc, eye, eye + Vector3(1.0, 0.15, -0.4), p + "right")
		await RoomRender.shot(self, vc, eye, eye + Vector3(0.0, 1.0, -0.35), p + "up")
		await RoomRender.shot(self, vc, eye, eye + Vector3(0.0, 0.25, 1.0), p + "back")
		var side := Vector3(-2.0, 0, 2.0)
		var best := Vector3(999, 0, 0)
		for t: Transform3D in (vc[2] as Node).call("room_seat_transforms"):
			if t.origin.distance_to(side) < best.distance_to(side):
				best = t.origin
		await RoomRender.shot(self, vc, best + Vector3(0, 1.2, 0), screen, p + "side_seat")
		if phase == "preshow":
			# Close: the chancel, the rose, a corona, the hymn board, a pew's end, a ledger stone, the Moon's pool.
			(vc[1] as Camera3D).fov = 50.0
			await RoomRender.shot(self, vc, Vector3(0, 1.6, -3.2), Vector3(0, 3.6, -10.3), p + "chancel")
			await RoomRender.shot(self, vc, Vector3(0, 1.4, -2.0), Vector3(0, 8.9, -10.6), p + "rose")
			await RoomRender.shot(self, vc, eye, Vector3(0, 7.1, -4.75), p + "corona")
			await RoomRender.shot(self, vc, Vector3(1.0, 1.6, 0.5), Vector3(3.3, 2.3, -2.5), p + "hymn")
			await RoomRender.shot(self, vc, Vector3(3.4, 1.3, 1.7), Vector3(2.75, 0.85, 0.0), p + "pew_end")
			await RoomRender.shot(self, vc, Vector3(-3.0, 1.5, -1.2), Vector3(-5.3, 0.0, -2.35), p + "ledger")
			await RoomRender.shot(self, vc, Vector3(1.4, 1.7, 1.5), Vector3(4.4, 0.0, -1.25), p + "pool")
			await RoomRender.shot(self, vc, Vector3(-4.2, 1.5, -3.0), Vector3(-5.3, 1.0, -6.0), p + "votive")
			(vc[1] as Camera3D).fov = 90.0
		await RoomRender.close(self, vc)
