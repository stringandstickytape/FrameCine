extends "res://tests/env_builder_harness.gd"

## Cenote cavern (app/environments/cenote_cavern.env.json; docs/environments/rooms/cenote_cavern.md): an underground
## Yucatan limestone karst sinkhole and bioluminescent crystal grotto cinema (Other worlds).
## Built headless and verified against every shipped-room invariant: schema, budget (draws <= 34, tris <= 90k, 0 live
## lights), blend layers (<= BLEND_BUDGET), build time (<= BUILD_BUDGET), clear sight lines from all 12 seats, comfort,
## CC0 licences, zero people, zero trademarks, lightmap atlas hint <= 2048, Sabine acoustics, sound beds & levels
## (RoomSound.check_level), animated water pool & volumetric oculus shafts scaled by Motion, live settings (time,
## crystals, mist), fireflies keeping out of sight lines, and pre-show/film ritual cues.
## Under lavapipe (when ENV_SHOTS is set), renders 10 diagnostic and hero views for visual inspection.
## godot --headless --xr-mode off --path app --script res://tests/test_room_cenote_cavern.gd

const RoomRender := preload("res://tests/room_render.gd")
const RoomSound := preload("res://tests/room_sound.gd")
const CenoteCavern := preload("res://scripts/env/systems/kit/cenote_cavern.gd")
const DOC := "res://environments/cenote_cavern.env.json"


func run_tests() -> void:
	test_name = "test_room_cenote_cavern"
	var r := EnvDoc.load_file(DOC)
	check("the document reads without schema errors (%s)" % [r["errors"]], (r["errors"] as Array).is_empty())
	var doc: Dictionary = r["doc"]
	if doc.is_empty():
		return
	if OS.get_environment("CENOTE_RENDER_ONLY") == "":
		var room := await check_room("cenote_cavern", doc)
		room.host.auto = false
		_by_part(room)
		await _budget_and_blend(room, doc)
		_built(room)
		_water_and_shafts(room)
		_settings_and_cues(room)
		_life_and_sky(room)
		_sound_and_acoustics(room)
		await done(room)
		await RoomSound.check_level(self, self, "cenote_cavern", doc)
	await _render(doc)


func _budget_and_blend(room: Node3D, doc: Dictionary) -> void:
	var stats := EnvChecks.measure(room)
	check("Cenote cavern stays tight on budget: draws <= 34 (%d), tris <= 90k (%d), 0 live lights (%d), texture <= 20 MB (%.1f)"
			% [int(stats["draws"]), int(stats["triangles"]), int(stats["lights"]), float(stats["texture_mb"])],
			int(stats["draws"]) <= 34 and int(stats["triangles"]) <= 90000 and int(stats["lights"]) == 0
			and float(stats["texture_mb"]) <= 20.0)
	var blend: Dictionary = await EnvChecks.blend_layers(self, room)
	print("  blend: mean %.2f, peak %d, share %.2f (limit %.2f)" % [float(blend["mean"]), int(blend["peak"]),
			float(blend["share"]), EnvChecks.BLEND_BUDGET])
	check("blended layers mean %.2f <= %.2f" % [float(blend["mean"]), EnvChecks.BLEND_BUDGET],
			float(blend["mean"]) <= EnvChecks.BLEND_BUDGET)
	# Second-build time (with procedural maps cached) must fit within BUILD_BUDGET.
	var second: Node3D = EnvRoom.new()
	second.doc = doc
	var t0 := Time.get_ticks_usec()
	root.add_child(second)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var units := EnvChecks.build_units(ms)
	print("  build: %.1f ms (%.1f pace units; limit %.1f)" % [ms, units, EnvChecks.BUILD_BUDGET])
	check("fast build time %.1f <= %.1f pace units" % [units, EnvChecks.BUILD_BUDGET], units <= EnvChecks.BUILD_BUDGET)
	root.remove_child(second)
	second.free()


func _built(room: Node3D) -> void:
	var host: Node = room.host
	for n: String in ["PieceStatic", "PieceSoft", "PieceLamps", "PieceCove", "CenotePool", "CenoteShaft",
			"Seats", "SkyDome", "SkyStars", "SkyMoon", "Fog"]:
		check("room has %s" % n, room.find_child(n, true, false) != null)
	for n: String in ["Walls", "Floor", "Ceiling", "Trim"]:
		check("domestic %s left to kit" % n, room.get_node_or_null(n) == null)
	var kit: Node = host.system("kit")
	check("kit has zero problems (%s)" % [kit.problems()], kit.problems().is_empty())
	var seats: Array[Transform3D] = room.room_seat_transforms()
	check("12 cushion seats across 4 rows (%d)" % seats.size(), seats.size() == 12)
	check("seats model is cushion", str(host.system("seats").params["model"]) == "cushion")
	# Verify all kit physics boxes stay >= 0.5 m clear of viewer origin (0, 0, 0).
	var near_origin := 0
	for sh: Array in kit.collision_shapes():
		var shape: BoxShape3D = sh[0]
		var xf: Transform3D = sh[1]
		var half := shape.size * 0.5
		var local_o := xf.affine_inverse() * Vector3.ZERO
		var clamped := local_o.clamp(-half, half)
		if local_o.distance_to(clamped) < 0.5:
			near_origin += 1
	check("all kit physics boxes >= 0.5 m clear of origin (%d too close)" % near_origin, near_origin == 0)
	# Hidden bake lights (8 lantern omnis + 1 moonlight oculus spot), zero visible live lights.
	var omnis := room.find_children("KitLamp*", "OmniLight3D", true, false)
	var spots := room.find_children("KitSpot*", "SpotLight3D", true, false)
	var all_hidden := (omnis + spots).all(func(l: Node) -> bool: return not (l as Light3D).visible)
	check("bake lights ready and hidden (%d omnis, %d spots)" % [omnis.size(), spots.size()],
			omnis.size() == 8 and spots.size() == 1 and all_hidden)
	# Verify lightmap atlas size hint.
	var largest := Vector2i.ZERO
	for mi: MeshInstance3D in room.static_meshes():
		largest = largest.max((mi.mesh as ArrayMesh).lightmap_size_hint)
	print("  atlas: %s (%d static meshes)" % [largest, room.static_meshes().size()])
	check("static atlas under %d (%s)" % [MAX_ATLAS, largest],
			largest.x > 0 and largest.x <= MAX_ATLAS and largest.y <= MAX_ATLAS)
	# Verify clear upward view through the overhead jungle oculus to the sky & Moon from origin!
	var moon_dir: Vector3 = host.system("sky").call("moon_shine")["direction"]
	var eye := Vector3(0.0, 1.2, 0.0)
	var blocked_up := _hits_solid(room, eye, Vector3.UP, ["PieceStatic"])
	var blocked_moon := _hits_solid(room, eye, moon_dir, ["PieceStatic"])
	check("open jungle oculus directly overhead and toward Moon (up=%s, moon=%s)" % [blocked_up, blocked_moon],
			not blocked_up and not blocked_moon)


func _water_and_shafts(room: Node3D) -> void:
	var host: Node = room.host
	var pool := room.find_child("CenotePool", true, false) as MeshInstance3D
	var shaft := room.find_child("CenoteShaft", true, false) as MeshInstance3D
	var pm := pool.mesh.surface_get_material(0) as ShaderMaterial
	var sm := shaft.mesh.surface_get_material(0) as ShaderMaterial
	check("CenotePool uses opaque env_world_water shader", pm != null and pm.shader == CenoteCavern.WATER_SHADER
			and not EnvChecks.blends(pm))
	check("CenoteShaft uses env_world_shaft shader and is in env_see_through",
			sm != null and sm.shader == CenoteCavern.SHAFT_SHADER and shaft.is_in_group("env_see_through"))
	# Motion scaling: clock advances at motion=1.0, freezes at motion=0.0.
	host.set_setting("motion", 1.0)
	var c0 := float(pm.get_shader_parameter("clock"))
	_steps(host, 2.0, 0.25)
	var c1 := float(pm.get_shader_parameter("clock"))
	check("water & shaft clock advances with Motion=1.0 (%.2f -> %.2f)" % [c0, c1], c1 > c0 + 1.5)
	host.set_setting("motion", 0.0)
	_steps(host, 1.5, 0.25)
	var c2 := float(pm.get_shader_parameter("clock"))
	check("water & shaft clock freezes with Motion=0.0 (%.2f -> %.2f)" % [c1, c2], absf(c2 - c1) < 1e-4)
	host.set_setting("motion", 1.0)


func _settings_and_cues(room: Node3D) -> void:
	var host: Node = room.host
	var kit: Node = host.system("kit")
	var sky: Node = host.system("sky")
	var atm: Node = host.system("atmosphere")
	var shaft := room.find_child("CenoteShaft", true, false) as MeshInstance3D
	var sm := shaft.mesh.surface_get_material(0) as ShaderMaterial

	# 1. Crystals setting: cyan -> amethyst -> lanterns only.
	host.set_setting("crystals", "cyan")
	_steps(host, 0.5)
	var cs_cyan: Dictionary = kit.cove_state()
	host.set_setting("crystals", "amethyst")
	_steps(host, 0.5)
	var cs_am: Dictionary = kit.cove_state()
	host.set_setting("crystals", "lanterns")
	_steps(host, 0.5)
	var cs_off: Dictionary = kit.cove_state()
	check("crystals setting switches PieceCove live (cyan=%.2f, amethyst=%.2f, off=%.2f)"
			% [float(cs_cyan["glow"]), float(cs_am["glow"]), float(cs_off["glow"])],
			float(cs_cyan["glow"]) > 1.0 and float(cs_am["glow"]) > 1.0 and float(cs_off["glow"]) < 0.01
			and (cs_cyan["colour"] as Color).g > (cs_cyan["colour"] as Color).r
			and (cs_am["colour"] as Color).b > (cs_am["colour"] as Color).g)
	host.set_setting("crystals", "cyan")

	# 2. Time setting: moonlight -> dusk -> starlight.
	host.set_setting("time", "dusk")
	_steps(host, 4.0)
	var dusk_sky := float(sky.params["dusk"])
	var dusk_shaft := float(sm.get_shader_parameter("shaft_level"))
	host.set_setting("time", "starlight")
	_steps(host, 4.0)
	var star_sky := float(sky.params["dusk"])
	var star_shaft := float(sm.get_shader_parameter("shaft_level"))
	host.set_setting("time", "moonlight")
	_steps(host, 4.0)
	var moon_shaft := float(sm.get_shader_parameter("shaft_level"))
	check("time setting drives sky.dusk and volumetric shaft (dusk=%.2f/%.2f, star=%.2f/%.2f, moon=%.2f)"
			% [dusk_sky, dusk_shaft, star_sky, star_shaft, moon_shaft],
			dusk_sky < 0.35 and star_sky > 0.95 and dusk_shaft > 0.22 and star_shaft < 0.12 and moon_shaft > 0.18)

	# 3. Mist setting: soft -> clear.
	host.set_setting("mist", "soft")
	_steps(host, 0.5)
	var fog_soft := float(atm.params["fog"])
	host.set_setting("mist", "clear")
	_steps(host, 0.5)
	var fog_clear := float(atm.params["fog"])
	check("mist setting toggles water surface fog (soft=%.2f, clear=%.2f)" % [fog_soft, fog_clear],
			fog_soft > 0.25 and fog_clear < 0.01)
	host.set_setting("mist", "soft")

	# 4. Pre-show -> film playback ritual cues (house_lamps dim, crystals keep cove_floor=0.45, shaft dims gently).
	host.timeline.state = ""
	host.snapshot_override = {"open": false}
	_steps(host, 8.0)
	var pre_lamps := float(host.param("light.house_lamps"))
	var pre_cove := float(kit.cove_state()["glow"])
	var pre_shaft := float(sm.get_shader_parameter("shaft_level"))
	host.snapshot_override = {"open": true, "playing": true, "position": 0.5, "duration": 7200.0}
	_steps(host, 12.0)
	var film_lamps := float(host.param("light.house_lamps"))
	var film_cove := float(kit.cove_state()["glow"])
	var film_shaft := float(sm.get_shader_parameter("shaft_level"))
	check("film ritual dims lanterns (%.2f -> %.2f), keeps crystal cove floor (%.2f -> %.2f), softens shaft (%.2f -> %.2f)"
			% [pre_lamps, film_lamps, pre_cove, film_cove, pre_shaft, film_shaft],
			pre_lamps > 0.95 and absf(film_lamps - 0.16) < 0.03
			and film_cove >= 0.45 * 1.2 and film_cove < pre_cove
			and film_shaft < pre_shaft * 0.65 and film_shaft > 0.06)
	# End of film restores house lamps cleanly.
	host.snapshot_override = {"open": true, "playing": false, "ended": true, "position": 7200.0, "duration": 7200.0}
	_steps(host, 8.0)
	check("ended restores lanterns (%.2f)" % float(host.param("light.house_lamps")),
			float(host.param("light.house_lamps")) > 0.95)


func _life_and_sky(room: Node3D) -> void:
	var host: Node = room.host
	var ff: Node = host.system("fireflies")
	_steps(host, 2.0, 0.2)
	var pts: Array = ff.positions()
	var in_sight := 0
	for p: Vector3 in pts:
		if ff.in_view(p, 0.0):
			in_sight += 1
	check("42 fireflies drifting clear of screen sight line (%d total, %d in sight)" % [pts.size(), in_sight],
			pts.size() == 42 and in_sight == 0)
	var sky: Node = host.system("sky")
	check("tropical latitude 20.5 and Moon active", absf(float(sky.params["latitude"]) - 20.5) < 0.1
			and float(sky.params["moon"]) > 0.5)


func _sound_and_acoustics(room: Node3D) -> void:
	RoomSound.check_beds(self, "cenote_cavern", room,
			{"cavern": "cavern_hum", "drips": "drips", "water": "water_lap", "crickets": "crickets"}, "stone_nave")
	var sr: Dictionary = room.get_sound_room()
	var box: AABB = sr["box"]
	var v := box.size.x * box.size.y * box.size.z
	var area := 2.0 * (box.size.x * box.size.y + box.size.y * box.size.z + box.size.z * box.size.x)
	var alpha := 0.161 * v / (area * float(sr["rt60"]))
	print("  acoustics: box %.1f x %.1f x %.1f, rt60 %.2f, wet %.2f, late %.2f, Sabine alpha %.3f"
			% [box.size.x, box.size.y, box.size.z, float(sr["rt60"]), float(sr["wet"]), float(sr["late"]), alpha])
	check("Sabine mean absorption %.3f in 0.05..0.75" % alpha, alpha >= 0.05 and alpha <= 0.75)


func _hits_solid(room: Node3D, from: Vector3, dir: Vector3, names: Array) -> bool:
	var d := dir.normalized()
	for n: String in names:
		var mi := room.find_child(n, true, false) as MeshInstance3D
		if mi == null:
			continue
		var f := mi.mesh.get_faces()
		var xf := mi.global_transform
		for k in range(0, f.size(), 3):
			var hit: Variant = Geometry3D.ray_intersects_triangle(from, d, xf * f[k], xf * f[k + 1], xf * f[k + 2])
			if hit != null:
				return true
	return false


static func _steps(host: Node, seconds: float, dt := 0.25) -> void:
	var t := 0.0
	while t < seconds:
		host.step(dt)
		t += dt


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
	var eye := Vector3(0.0, 1.2, 0.0)

	# --- 1. Pre-show: Moonlight shaft + Bioluminescent cyan crystals (default) ---
	RoomRender.set_light(screen, 0.05)
	var vc := await RoomRender.open(self, doc, 92.0)
	var host: Node = (vc[2] as Node).host
	RenderingServer.global_shader_parameter_set("screen_glow", 0.18)
	host.snapshot_override = {"open": false}
	host.signals.fake("film.brightness", 0.0)
	_steps(host, 6.0, 0.25)
	# Hero front seat view toward basalt screen pylons, turquoise cenote pool, moonlight shaft & cyan crystals!
	await RoomRender.shot(self, vc, eye, screen + Vector3(0.0, 0.15, 0.0), "cenote_seat")
	# Looking UP through the jagged jungle oculus, gnarled roots, overhanging ferns, stars, Moon & moonlight shafts!
	await RoomRender.shot(self, vc, eye, Vector3(-0.6, 14.0, -3.2), "cenote_up_oculus")
	# Looking DOWN-LEFT at the turquoise cenote pool, stone steps, moonlight pool bloom & crystal outcrop!
	await RoomRender.shot(self, vc, eye + Vector3(0.0, 0.25, -0.3), Vector3(-3.8, -0.5, -5.2), "cenote_pool_down")
	# Looking LEFT across the cavern gallery, mossy islet, glowing crystals & hanging cave lantern!
	await RoomRender.shot(self, vc, eye, Vector3(-8.5, 1.4, -3.8), "cenote_left_gallery")
	# Looking AFT across the cushions, weathered timber boardwalk bridge, lanterns & aft moonlight shaft!
	await RoomRender.shot(self, vc, Vector3(0.0, 1.35, -0.9), Vector3(0.2, 1.0, 9.5), "cenote_aft_boardwalk")
	# Close-up of an intimate glowing bioluminescent cyan mineral crystal cluster beside the viewing island!
	(vc[1] as Camera3D).fov = 58.0
	await RoomRender.shot(self, vc, Vector3(-1.3, 0.85, 1.8), Vector3(-3.38, 0.22, 0.35), "cenote_crystal_closeup")
	# Front-row side seat view verifying crystal-clear screen framing and basalt pylon detail!
	(vc[1] as Camera3D).fov = 88.0
	await RoomRender.shot(self, vc, Vector3(1.05, 1.2, -1.45), screen, "cenote_front_side_seat")

	# --- 2. Variant: Amethyst crystal + Dusk emerald ---
	host.set_setting("crystals", "amethyst")
	host.set_setting("time", "dusk")
	_steps(host, 6.0, 0.25)
	await RoomRender.shot(self, vc, eye, screen + Vector3(0.0, 0.2, 0.0), "cenote_amethyst_dusk")

	# --- 3. Variant: Starlight grotto + Lanterns only ---
	host.set_setting("crystals", "lanterns")
	host.set_setting("time", "starlight")
	_steps(host, 6.0, 0.25)
	await RoomRender.shot(self, vc, eye, screen + Vector3(0.0, 0.15, 0.0), "cenote_starlight_lanterns")

	# --- 4. Film-playing dimmed view (default Moonlight shaft + Bioluminescent cyan) ---
	host.set_setting("crystals", "cyan")
	host.set_setting("time", "moonlight")
	RoomRender.set_light(screen, 0.015)
	RenderingServer.global_shader_parameter_set("screen_glow", 1.15)
	host.snapshot_override = {"open": true, "playing": true, "position": 1800.0, "duration": 7200.0}
	host.signals.fake("film.brightness", 0.72)
	host.signals.fake("film.colour", Color(0.88, 0.56, 0.34))
	host.signals.fake("playback.playing", 1.0)
	_steps(host, 12.0, 0.25)
	await RoomRender.shot(self, vc, eye, screen + Vector3(0.0, 0.1, 0.0), "cenote_film_playing")

	await RoomRender.close(self, vc)
