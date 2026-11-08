extends "res://tests/env_builder_harness.gd"

## Reclaimed (app/environments/reclaimed.env.json; docs/environments.md, "Room: Reclaimed"): a picture house in ruins,
## half its roof gone, by moonlight. Built headless from its document and checked as every shipped room is (schema,
## budget, sight lines from every seat past the fallen chandelier, the birch and the meadow, comfort, licences, names,
## no people) and as a builder's room (seats, physics, bake, seat picking); then what makes it this room: its figures
## and parts (kit/reclaimed.gd: brick, plaster, timber, cloth, brass, crystal, leaves), the auditorium's shell left
## to the kit, the bake's atlases kept small with no live light and no bake light (the Moon's light rides in the
## vertices: some lit, more in shadow; never on the picture), seats tipped up and broken, never the viewer's; the owl
## far off and quiet in the film, the crickets only when it is dry (tests/test_room_set5.gd checks the weather, the
## creatures and the room's level). Under lavapipe it draws the room from its own seat, left, right, up, back, a side
## seat and up behind, in the pre-show and with a film playing (RECL_BAKE=1 bakes it first; RECL_RENDER_ONLY=1 skips
## the checks; RECL_SHOTS=preshow or film draws one of them; RECL_CLOSE=1 adds close views in the pre-show; RECL_TOP=1
## a view from over the roof; RECL_TAG names the files).
## godot --headless --xr-mode off --path app --script res://tests/test_room_reclaimed.gd

const RoomRender := preload("res://tests/room_render.gd")
const RoomBake := preload("res://scripts/env/room_bake.gd")
const Ruin := preload("res://scripts/env/systems/kit/reclaimed.gd")
const DOC := "res://environments/reclaimed.env.json"
const BAKE_ID := "reclaimed_render_test"
## The room's figures (docs/environments.md, "Room: Reclaimed").
const FIGURES := {"draws": 32, "triangles": 260000, "lights": 0, "particles": 1500, "texture_mb": 16.0}
## The bake: each atlas at most this a side, and all of them together at most this many texels (the headset bakes the
## room when it is chosen; the atlases set how long that takes).
const ATLAS_SIDE := 1024
const ATLAS_TEXELS := 1500000


func run_tests() -> void:
	test_name = "test_room_reclaimed"
	var r := EnvDoc.load_file(DOC)
	check("the document reads (%s)" % [r["errors"]], (r["errors"] as Array).is_empty())
	var doc: Dictionary = r["doc"]
	if doc.is_empty():
		return
	if OS.get_environment("RECL_RENDER_ONLY") == "":
		var t0 := Time.get_ticks_msec()
		var room := await check_room("reclaimed", doc)
		print("  built and checked in %d ms" % (Time.get_ticks_msec() - t0))
		room.host.auto = false
		_by_part(room)
		_built(room)
		_bake(room)
		_moon(room)
		_seats(room)
		_sound(room)
		await done(room)
	await _render(doc)


## The figures and the parts; the kit draws the hall, the auditorium only its tiers and seats.
func _built(room: Node3D) -> void:
	var host: Node = room.host
	var stats := EnvChecks.measure(room)
	check("the figures as documented: at most %s (%s)" % [FIGURES, stats], EnvChecks.budget(stats, FIGURES).is_empty())
	for n: String in ["RuinBrick", "RuinPlaster", "RuinWood", "RuinCloth", "RuinBrass", "RuinCrystal", "RuinLeaves",
			"RuinPort", "Floor", "Seats"]:
		check("the ruin has its %s" % n, room.find_child(n, true, false) != null)
	var kit: Node = host.system("kit")
	check("every piece built (%s)" % [kit.problems()], (kit.problems() as Array).is_empty())
	check("the auditorium leaves the shell to the kit", str(host.system("hall").params["shell"]) == "kit")
	var kinds: Array = (kit.params["pieces"] as Array).map(func(e: Dictionary) -> String: return str(e["piece"]))
	check("the ruin's four pieces (%s)" % [kinds], ["ruin_shell", "ruin_roof", "ruin_stalls", "ruin_growth"].all(
			func(k: String) -> bool: return k in kinds))
	# The fallen chandelier off to the right, on the floor, away from the viewer.
	var ch := (room.find_child("RuinCrystal", true, false) as MeshInstance3D).get_aabb()
	check("the chandelier lies on the floor to the side (%s)" % ch, ch.position.y < 0.0 and ch.end.y < 1.6
			and ch.get_center().x > 2.0)


## The bake: static meshes with small atlases; no light at all, live or for the bake.
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
	check("no light at all: the Moon rides in the vertices (%d)" % room.find_children("*", "Light3D", true,
			false).size(), room.find_children("*", "Light3D", true, false).is_empty())
	check("the light system bakes", bool(room.host.system("light").params["bake"]))


## The Moon's light in the baked meshes' vertices: on, by the shader's vertex_light; some of the ruin lit, more of it
## in shadow; the pool on the seats, the shaft through the roof's hole onto the stage, never on the picture.
func _moon(room: Node3D) -> void:
	for n: String in ["RuinBrick", "RuinPlaster", "RuinWood", "RuinCloth", "Floor"]:
		var mi := room.find_child(n, true, false) as MeshInstance3D
		var mat := mi.mesh.surface_get_material(0) as ShaderMaterial
		var vl: Vector3 = mat.get_shader_parameter("vertex_light") if mat != null else Vector3.ZERO
		var lit := 0
		var dark := 0
		var all := 0
		for si in mi.mesh.get_surface_count():
			var cols: PackedColorArray = mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_COLOR]
			for c: Color in cols:
				all += 1
				lit += 1 if c.a > 0.4 else 0
				dark += 1 if c.a < 0.05 else 0
		print("  moon %-12s %6d vertices, %4.1f%% lit, %4.1f%% dark" % [n, all, 100.0 * lit / maxi(all, 1),
				100.0 * dark / maxi(all, 1)])
		check("%s: the Moon in its vertices (%s; %d lit, %d dark of %d)" % [n, vl, lit, dark, all], vl.length() > 0.1
				and lit > 0 and dark > all / 4)
	check("the Moon on the seat (%.2f)" % Ruin.moon_light(Vector3(0, 1.0, 0)), Ruin.moon_light(Vector3(0, 1.0, 0)) > 0.9)
	check("no Moon under the front roof but for the hole (%.2f)" % Ruin.moon_light(Vector3(3.0, 1.0, -7.0)),
			Ruin.moon_light(Vector3(3.0, 1.0, -7.0)) < 0.01)
	var hole := Vector3(Ruin.HOLE.x, Ruin.CEIL, Ruin.HOLE.y)
	var pool := hole - Ruin.MOON_DIR / Ruin.MOON_DIR.y * (Ruin.CEIL - 1.0)
	check("the shaft through the hole lands on the stage (%s: %.2f)" % [pool, Ruin.moon_light(pool)],
			Ruin.moon_light(pool) > 0.9 and pool.z < -7.6 and pool.z > -9.2)
	var sc := _v3(room.doc["screen"]["center"])
	var ss: Array = room.doc["screen"]["size"]
	var worst := 0.0
	for i in 9:
		for j in 5:
			var p := sc + Vector3((i / 8.0 - 0.5) * float(ss[0]), (j / 4.0 - 0.5) * float(ss[1]), 0.05)
			worst = maxf(worst, Ruin.moon_light(p))
	check("no moonlight on the picture (%.2f)" % worst, worst < 0.01)


## Seats tipped up and broken, apart, never the viewer's own.
func _seats(room: Node3D) -> void:
	var seats: Array[Transform3D] = room.room_seat_transforms()
	var sys: Node = room.host.system("seats")
	var up: Array = sys.params["up"]
	var broken: Array = sys.params["broken"]
	var own := func(i: int) -> bool: return i < seats.size() and seats[i].origin.length() > 0.05
	check("seats tipped up (%d) and broken (%d), none the viewer's" % [up.size(), broken.size()], up.size() >= 6
			and broken.size() >= 4 and up.all(own) and broken.all(own))
	check("no seat both tipped up and broken", up.all(func(i: int) -> bool: return not (i in broken)))


## The owl far off and a whisper in the film; the crickets out by the side door, only when it is dry; the wind high
## over the open roof.
func _sound(room: Node3D) -> void:
	var host: Node = room.host
	var owl: Node = host.system("owl")
	var at := _v3(owl.params["at"])
	check("the owl outside, far off (%.0f m), much quieter in the film (%.0f dB)" % [at.length(),
			float(owl.params["film_db"])], at.length() > 20.0 and float(owl.params["film_db"]) <= -12.0)
	var crickets: Node = host.system("crickets")
	check("the crickets quiet (%.0f dB) and by the side door (%s)" % [float(crickets.params["gain_db"]),
			crickets.params["at"]], float(crickets.params["gain_db"]) <= -10.0
			and absf(float(crickets.params["at"][0])) > 8.0)
	host.signals.fake("weather.rain", 1.0)
	for i in 100:
		host.step(0.25)
	var wet := float(crickets.params["level"])
	host.signals.fake("weather.rain", 0.0)
	for i in 100:
		host.step(0.25)
	var dry := float(crickets.params["level"])
	host.signals.clear_fakes()
	check("the crickets stop in the rain (%.2f) and sing when it is dry (%.2f)" % [wet, dry], wet < 0.05 and dry > 0.9)
	var wind: Node = host.system("wind")
	check("the wind high over the open roof (%s)" % [wind.params.get("at", [])], float(wind.params["at"][1]) > 6.0)


func _v3(v: Variant) -> Vector3:
	return Vector3(float(v[0]), float(v[1]), float(v[2]))


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
		elif g is GPUParticles3D or g is CPUParticles3D:
			stats = {"draws": 1, "triangles": 0}
		if not stats.is_empty():
			rows.append([str(g.get_parent().name) + "/" + str(g.name), stats["draws"], stats["triangles"]])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return int(a[2]) > int(b[2]))
	for r: Array in rows:
		print("  part %-32s %2d draws %7d triangles" % r)


func _render(doc: Dictionary) -> void:
	if not RoomRender.has_renderer():
		print("SKIP render (headless)")
		return
	var sc: Array = doc["screen"]["center"]
	var screen := Vector3(float(sc[0]), float(sc[1]), float(sc[2]))
	var baked := OS.get_environment("RECL_BAKE") != "" and RoomBake.can_bake()
	var only := OS.get_environment("RECL_SHOTS")
	var tag := OS.get_environment("RECL_TAG")
	for phase: String in ["preshow", "film"]:
		if only != "" and not (phase in only):
			continue
		RoomRender.set_light(screen, 0.05 if phase == "preshow" else 0.015)
		var vc := await RoomRender.open(self, doc)
		var host: Node = (vc[2] as Node).host
		for mi: Node in (vc[2] as Node).get_children():
			if mi is MeshInstance3D and (mi as MeshInstance3D).mesh is QuadMesh:
				(mi as MeshInstance3D).gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		host.set_setting("weather", "clear")
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
		for l: Node in (vc[2] as Node).find_children("*", "Light3D", true, false):
			print("  light %s mode %d shadow %s at %s energy %.2f" % [l.name, (l as Light3D).light_bake_mode,
					(l as Light3D).shadow_enabled, (l as Node3D).global_position, (l as Light3D).light_energy])
		var eye := Vector3(0, 1.2, 0)
		var p := "recl_%s%s%s_" % [tag, "baked_" if baked else "", phase]
		await RoomRender.shot(self, vc, eye, screen, p + "seat")
		await RoomRender.shot(self, vc, eye, eye + Vector3(-1.0, 0.15, -0.4), p + "left")
		await RoomRender.shot(self, vc, eye, eye + Vector3(1.0, 0.15, -0.4), p + "right")
		await RoomRender.shot(self, vc, eye, eye + Vector3(0.0, 1.0, -0.35), p + "up")
		await RoomRender.shot(self, vc, eye, eye + Vector3(0.0, 0.25, 1.0), p + "back")
		var side := Vector3(-3.0, 0, 2.4)
		var best := Vector3(999, 0, 0)
		for t: Transform3D in (vc[2] as Node).call("room_seat_transforms"):
			if t.origin.distance_to(side) < best.distance_to(side):
				best = t.origin
		await RoomRender.shot(self, vc, best + Vector3(0, 1.2, 0), screen, p + "side_seat")
		await RoomRender.shot(self, vc, eye, eye + Vector3(-0.5, 0.9, 0.6), p + "up_back")
		if OS.get_environment("RECL_TOP") != "":
			# The floor from over the open roof (the Moon's pool and the trusses' shadows).
			(vc[1] as Camera3D).fov = 70.0
			await RoomRender.shot(self, vc, Vector3(0, 7.2, -1.0), Vector3(0, -0.4, -1.05), p + "top")
			(vc[1] as Camera3D).fov = 90.0
		if phase == "preshow" and OS.get_environment("RECL_CLOSE") != "":
			(vc[1] as Camera3D).fov = 55.0
			await RoomRender.shot(self, vc, Vector3(1.6, 1.4, -1.2), Vector3(3.7, -0.2, -3.6), p + "chandelier")
			await RoomRender.shot(self, vc, Vector3(0, 1.6, -4.0), Vector3(0, 3.6, -9.2), p + "proscenium")
			await RoomRender.shot(self, vc, Vector3(-1.0, 1.4, -1.0), Vector3(-5.5, 5.5, -2.5), p + "edge")
			await RoomRender.shot(self, vc, Vector3(2.0, 1.5, 0.5), Vector3(7.2, 4.0, 3.2), p + "birch")
			await RoomRender.shot(self, vc, Vector3(-3.0, 1.4, -2.0), Vector3(-5.8, 1.6, -8.6), p + "curtain")
			await RoomRender.shot(self, vc, Vector3(0.5, 1.3, -1.5), Vector3(1.5, -0.4, -4.6), p + "meadow")
			await RoomRender.shot(self, vc, Vector3(-1.5, 1.4, -2.0), Vector3(-0.4, 0.15, -8.8), p + "shaft")
			await RoomRender.shot(self, vc, Vector3(-3.0, 1.2, -2.0), Vector3(-7.0, 7.5, -5.9), p + "hole")
			(vc[1] as Camera3D).fov = 90.0
		await RoomRender.close(self, vc)
