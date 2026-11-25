extends "res://tests/env_builder_harness.gd"

## Orbital ring (app/environments/orbital_ring.env.json; docs/environments/rooms/orbital_ring.md): a sleek
## cantilevered mid-century-futurist glass-and-travertine observation terrace inside a colossal rotating O'Neill
## cylinder space habitat. Checked headless as every shipped room is (schema, budget, blend layers, build time,
## clear sight lines from all 9 seats, comfort, licences, names, no people, physics, bake, seat picking) plus
## room-specific checks: custom O'Neill cylinder geometry inside the 184 m sky layers with 3 real open space-window
## gaps, opaque water & cylinder shaders, all 3 live settings (`habitat_time`, `terrace_glow`, `sky_windows`),
## working modernist wall clock, starting ritual chime & dimming cues, and sound beds & levels.
## Under Vulkan Forward Mobile / lavapipe it renders 9 PNGs to `$ENV_SHOTS`.
## godot --headless --xr-mode off --path app --script res://tests/test_room_orbital_ring.gd

const RoomRender := preload("res://tests/room_render.gd")
const RoomSound := preload("res://tests/room_sound.gd")
const OrbitalRing := preload("res://scripts/env/systems/kit/orbital_ring.gd")
const DOC := "res://environments/orbital_ring.env.json"


func run_tests() -> void:
	test_name = "test_room_orbital_ring"
	var r := EnvDoc.load_file(DOC)
	check("the document reads (%s)" % [r["errors"]], (r["errors"] as Array).is_empty())
	var doc: Dictionary = r["doc"]
	if doc.is_empty():
		return
	if OS.get_environment("ORBITAL_RENDER_ONLY") == "":
		var room := await check_room("orbital_ring", doc)
		room.host.auto = false
		_by_part(room)
		await _built(room, doc)
		_cylinder_and_water(room)
		_settings(room)
		_ritual(room)
		_sound(room)
		await done(room)
		await RoomSound.check_level(self, self, "orbital_ring", doc)
	await _render(doc)


## Figures, parts, blend layers, build time, shell left to kit, and seat-origin physics clearance.
func _built(room: Node3D, doc: Dictionary) -> void:
	var host: Node = room.host
	var stats := EnvChecks.measure(room)
	check("figures within Orbital ring limits: draws <= 34, tris <= 90k, 0 lights, 0 particles, < 32 MB (%s)"
			% [stats], int(stats["draws"]) <= 34 and int(stats["triangles"]) <= 90000 and int(stats["lights"]) == 0
			and int(stats["particles"]) == 0 and float(stats["texture_mb"]) < 32.0)

	var blend: Dictionary = await EnvChecks.blend_layers(self, room)
	print("  blend_layers: %s" % [blend])
	check("blended layers under budget (%s <= %s)" % [blend["mean"], EnvChecks.BLEND_BUDGET],
			float(blend["mean"]) <= EnvChecks.BLEND_BUDGET)

	# Measure second-build speed in pace() units (same method as test_environments.gd).
	var probe: Node3D = EnvRoom.new()
	probe.doc = doc
	var t0 := Time.get_ticks_usec()
	root.add_child(probe)
	var build_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var units := EnvChecks.build_units(build_ms)
	print("  build: %.1f pace units (%d ms)" % [units, roundi(build_ms)])
	check("fast build time (%.1f <= %.1f)" % [units, EnvChecks.BUILD_BUDGET], units <= EnvChecks.BUILD_BUDGET)
	root.remove_child(probe)
	probe.free()

	for n: String in ["PieceStatic", "PieceSoft", "PieceLamps", "PieceCove", "PieceGlass", "PieceClock",
			"PieceWindows", "RingCylinder", "RingWater", "Seats", "SkyDome", "SkyStars"]:
		check("room has %s" % n, room.find_child(n, true, false) != null)
	for n: String in ["Walls", "Floor", "Ceiling", "Trim", "Doorway", "Screen"]:
		check("domestic builder left %s to the kit" % n, room.get_node_or_null(n) == null)

	var kit: Node = host.system("kit")
	check("kit built cleanly (%s)" % [kit.problems()], kit.problems().is_empty())
	check("9 lounge seats in 3x3 arrangement (%d)" % room.room_seat_transforms().size(),
			room.room_seat_transforms().size() == 9 and str(host.system("seats").params["model"]) == "lounge")

	# Six hidden bake omni lamps from the six terrace globe bollards, plus bake atlas and sound-room checks.
	var largest := Vector2i.ZERO
	for mi: MeshInstance3D in room.static_meshes():
		largest = largest.max((mi.mesh as ArrayMesh).lightmap_size_hint)
	print("  bake: %d static meshes, largest atlas %s" % [room.static_meshes().size(), largest])
	check("static meshes for bake, each atlas under %d (%s)" % [MAX_ATLAS, largest],
			largest.x > 0 and largest.x <= MAX_ATLAS and largest.y <= MAX_ATLAS)
	check("sound room box and physics shapes present (%d)" % room.collision_shapes().size(),
			room.get_sound_room().has("box") and room.collision_shapes().size() > 20)
	var lamps := room.find_children("KitLamp*", "OmniLight3D", true, false)
	var all_hidden := true
	for l: Node in lamps:
		all_hidden = all_hidden and not (l as Light3D).visible
	check("6 hidden bake bollard lamps (%d, hidden %s)" % [lamps.size(), all_hidden],
			lamps.size() == 6 and all_hidden)

	# Every kit physics box stays >= 0.5 m clear of the viewer's seat origin (0, 0, 0).
	var too_close := 0
	for sh: Array in kit.collision_shapes():
		var bs := sh[0] as BoxShape3D
		var xf: Transform3D = sh[1]
		if bs == null:
			continue
		var local_o := xf.affine_inverse() * Vector3(0.0, 0.5, 0.0)
		var he := bs.size * 0.5
		var clamped := Vector3(clampf(local_o.x, -he.x, he.x), clampf(local_o.y, -he.y, he.y),
				clampf(local_o.z, -he.z, he.z))
		if local_o.distance_to(clamped) < 0.5:
			too_close += 1
	check("all kit physics boxes >= 0.5 m clear of viewer origin (%d too close)" % too_close, too_close == 0)

	# Working modernist wall clock hands follow system time.
	var hands: Array = kit.clock_hands()
	check("working clock hands present (%s)" % [hands], hands.size() == 2 and is_finite(float(hands[0]))
			and is_finite(float(hands[1])))


## O'Neill cylinder mesh bounds (inside 184 m sky layers), opaque shaders, and 3 real open space-window gaps.
func _cylinder_and_water(room: Node3D) -> void:
	var cyl := room.find_child("RingCylinder", true, false) as MeshInstance3D
	var water := room.find_child("RingWater", true, false) as MeshInstance3D
	var cm := cyl.mesh.surface_get_material(0) as ShaderMaterial
	var wm := water.mesh.surface_get_material(0) as ShaderMaterial
	check("RingCylinder uses opaque env_ring_world shader", cm != null and cm.shader == OrbitalRing.RING_SHADER
			and not EnvChecks.blends(cm))
	check("RingWater uses opaque env_world_water shader", wm != null and wm.shader == OrbitalRing.WATER_SHADER
			and not EnvChecks.blends(wm))

	# Verify every vertex of RingCylinder sits strictly inside 182 m from the viewer's eye (safe inside 184 m SkyLines).
	var eye := Vector3(0.0, 1.2, 0.0)
	var verts: PackedVector3Array = cyl.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var max_dist := 0.0
	for p: Vector3 in verts:
		max_dist = maxf(max_dist, eye.distance_to(p))
	print("  cylinder max vertex distance from eye: %.1f m (limit < 182.0 m)" % max_dist)
	check("cylinder stays inside sky sphere & far plane (%.1f m < 182 m)" % max_dist,
			max_dist > 70.0 and max_dist < 182.0)

	# Raycast verification: all 3 land continents (zenith 180 deg, starboard 60 deg, port 300 deg) are solid,
	# while the open space-window gaps (upper-right 120 deg, upper-left 240 deg) pass straight out to the Milky Way!
	var faces := cyl.mesh.get_faces()
	var dir_to := func(deg_a: float, z: float) -> Vector3:
		return (OrbitalRing._cyl_pt(deg_to_rad(deg_a), z) - eye).normalized()
	var hit_zenith := _hits_faces(faces, eye, dir_to.call(180.0, -10.0))
	var hit_starboard := _hits_faces(faces, eye, dir_to.call(60.0, -10.0))
	var hit_port := _hits_faces(faces, eye, dir_to.call(300.0, -10.0))
	var hit_win_right := _hits_faces(faces, eye, dir_to.call(120.0, -10.0))
	var hit_win_left := _hits_faces(faces, eye, dir_to.call(240.0, -10.0))
	check("3 land continents solid & upper space windows are real open gaps (up=%s, R_land=%s, L_land=%s, R_win=%s, L_win=%s)"
			% [hit_zenith, hit_starboard, hit_port, hit_win_right, hit_win_left],
			hit_zenith and hit_starboard and hit_port and not hit_win_right and not hit_win_left)


## Live settings: habitat_time (Night city lights / Golden hour / Twilight glow), terrace_glow, sky_windows.
func _settings(room: Node3D) -> void:
	var host: Node = room.host
	var kit: Node = host.system("kit")
	var sky: Node = host.system("sky")
	var cyl := room.find_child("RingCylinder", true, false) as MeshInstance3D
	var cm := cyl.mesh.surface_get_material(0) as ShaderMaterial

	# 1. habitat_time live transitions.
	_steps(host, 1.0)
	check("default habitat_time is night (time_mood=%.1f, mw=%s)" % [float(cm.get_shader_parameter("time_mood")),
			cm.get_shader_parameter("mood_weights")],
			is_equal_approx(float(cm.get_shader_parameter("time_mood")), 0.0)
			and (cm.get_shader_parameter("mood_weights") as Vector3).x > 0.95)
	host.set_setting("habitat_time", "golden")
	_steps(host, 6.0)
	check("habitat_time golden updates cylinder (time_mood=%.1f, mw=%s)" % [float(cm.get_shader_parameter("time_mood")),
			cm.get_shader_parameter("mood_weights")],
			is_equal_approx(float(cm.get_shader_parameter("time_mood")), 1.0)
			and (cm.get_shader_parameter("mood_weights") as Vector3).y > 0.95)
	host.set_setting("habitat_time", "twilight")
	_steps(host, 6.0)
	check("habitat_time twilight updates cylinder (time_mood=%.1f, mw=%s)" % [float(cm.get_shader_parameter("time_mood")),
			cm.get_shader_parameter("mood_weights")],
			is_equal_approx(float(cm.get_shader_parameter("time_mood")), 2.0)
			and (cm.get_shader_parameter("mood_weights") as Vector3).z > 0.95)
	host.set_setting("habitat_time", "night")
	_steps(host, 6.0)

	# 2. terrace_glow live cove colour & intensity.
	var gold: Dictionary = kit.cove_state()
	host.set_setting("terrace_glow", "orbital_cyan")
	_steps(host, 0.5)
	var cyan: Dictionary = kit.cove_state()
	host.set_setting("terrace_glow", "off")
	_steps(host, 0.5)
	var off: Dictionary = kit.cove_state()
	check("terrace_glow switches Warm gold -> Orbital cyan -> Off (%s, %s, %s)" % [gold, cyan, off],
			(gold["colour"] as Color).r > 0.9 and (cyan["colour"] as Color).b > 0.9
			and float(off["glow"]) < 0.01)
	host.set_setting("terrace_glow", "warm_gold")
	_steps(host, 0.5)

	# 3. sky_windows live Milky Way / Constellations / Quiet stars.
	check("default sky_windows is Milky Way (mw=%.2f, lines=%.2f)" % [float(sky.params["milky_way"]),
			float(sky.params["lines"])],
			float(sky.params["milky_way"]) > 0.95 and float(sky.params["lines"]) < 0.01)
	host.set_setting("sky_windows", "constellations")
	_steps(host, 0.5)
	var lines_node := room.find_child("SkyLines", true, false) as MeshInstance3D
	check("sky_windows constellations enables SkyLines (lines=%.2f, visible=%s)" % [float(sky.params["lines"]),
			lines_node != null and lines_node.visible],
			float(sky.params["lines"]) > 0.5 and lines_node != null and lines_node.visible)
	host.set_setting("sky_windows", "quiet")
	_steps(host, 0.5)
	check("sky_windows quiet dims Milky Way & hides lines (mw=%.2f, lines=%.2f)" % [float(sky.params["milky_way"]),
			float(sky.params["lines"])],
			float(sky.params["milky_way"]) < 0.25 and float(sky.params["lines"]) < 0.01)
	host.set_setting("sky_windows", "milky_way")
	_steps(host, 0.5)


## Ritual cues: starting chime plays, terrace lamps dim smoothly while cove_floor & cylinder remain gently visible.
func _ritual(room: Node3D) -> void:
	var host: Node = room.host
	var kit: Node = host.system("kit")
	var chime: Node = host.system("chime")
	chime.finish_loading()
	var cyl := room.find_child("RingCylinder", true, false) as MeshInstance3D
	var cm := cyl.mesh.surface_get_material(0) as ShaderMaterial

	host.timeline.state = ""
	host.snapshot_override = {"open": false}
	_steps(host, 10.0)
	var before_house := float(host.param("light.house_lamps"))
	var before_plays := int(chime.plays)
	check("pre-show terrace lamps full (%.2f)" % before_house, before_house > 0.95)

	host.snapshot_override = {"open": true, "playing": true, "position": 0.5, "duration": 7200.0}
	_steps(host, 12.0)
	var during_house := float(host.param("light.house_lamps"))
	var during_cove := float(kit.cove_state()["glow"])
	var during_dim := float(cm.get_shader_parameter("film_dim"))
	check("starting ritual plays cabin_chime (%d -> %d)" % [before_plays, int(chime.plays)],
			int(chime.plays) == before_plays + 1)
	check("film dims house lamps (%.2f), keeps soft cove floor (%.2f) & gentle cylinder glow (%.2f)"
			% [during_house, during_cove, during_dim],
			absf(during_house - 0.14) < 0.02 and during_cove > 0.45 and during_dim > 0.65 and during_dim < 0.85)

	host.snapshot_override = {"open": true, "playing": false, "ended": true, "position": 7200.0, "duration": 7200.0}
	_steps(host, 10.0)
	check("terrace lights return cleanly at end (%.2f)" % float(host.param("light.house_lamps")),
			float(host.param("light.house_lamps")) > 0.95)


## Sound beds and acoustics preset.
func _sound(room: Node3D) -> void:
	RoomSound.check_beds(self, "orbital_ring", room,
			{"wind": "wind", "city": "city", "fountain": "fountain", "chime": "cabin_chime"}, "cinema")


static func _hits_faces(faces: PackedVector3Array, from: Vector3, dir: Vector3) -> bool:
	for k in range(0, faces.size(), 3):
		if Geometry3D.ray_intersects_triangle(from, dir, faces[k], faces[k + 1], faces[k + 2]) != null:
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


## Lavapipe visual verification: 9 shots covering front terrace, upside-down cylinder & Milky Way, golden hour,
## twilight + orbital cyan + constellations, infinity pool & planters, lounge seating, aft promenade, and film mode.
func _render(doc: Dictionary) -> void:
	if not RoomRender.has_renderer():
		print("SKIP render (headless)")
		return
	var sc: Array = doc["screen"]["center"]
	var screen := Vector3(float(sc[0]), float(sc[1]), float(sc[2]))
	var ambient := float(doc["room"]["ambient"])

	# --- Phase 1: Pre-show (house lights bright, zero false screen spill) ---
	RoomRender.set_light(screen, ambient)
	RenderingServer.global_shader_parameter_set("screen_glow", 0.0)
	var vc := await RoomRender.open(self, doc, 92.0)
	var host: Node = (vc[2] as Node).host
	host.snapshot_override = {"open": false}
	_steps(host, 6.0)

	var eye := Vector3(0.0, 1.25, 0.0)
	await RoomRender.shot(self, vc, eye, screen, "orbital_preshow_seat")
	await RoomRender.shot(self, vc, Vector3(0.0, 1.25, 0.6), Vector3(0.0, 26.0, -18.0), "orbital_preshow_up")
	await RoomRender.shot(self, vc, Vector3(0.0, 1.25, 0.0), Vector3(0.0, 52.0, -5.0), "orbital_preshow_zenith")
	await RoomRender.shot(self, vc, Vector3(0.5, 1.35, -1.8), Vector3(-5.2, 1.0, -5.5), "orbital_left_pool_planter")
	await RoomRender.shot(self, vc, Vector3(-1.8, 1.45, 1.2), Vector3(4.8, 1.1, -1.6), "orbital_right_promenade")
	await RoomRender.shot(self, vc, Vector3(0.0, 1.45, -1.5), Vector3(0.0, 1.65, 6.0), "orbital_aft_promenade")

	# Golden hour habitat variant!
	host.set_setting("habitat_time", "golden")
	_steps(host, 8.0)
	await RoomRender.shot(self, vc, Vector3(0.0, 1.35, 0.4), Vector3(0.0, 10.0, -18.0), "orbital_golden_hour")

	# Twilight glow + Orbital cyan terrace coves + Constellations sky windows!
	host.set_setting("habitat_time", "twilight")
	host.set_setting("terrace_glow", "orbital_cyan")
	host.set_setting("sky_windows", "constellations")
	_steps(host, 8.0)
	await RoomRender.shot(self, vc, Vector3(0.0, 1.35, 0.4), Vector3(0.0, 14.0, -18.0), "orbital_twilight_cyan")
	await RoomRender.close(self, vc)

	# --- Phase 2: Film playing (dimmed house, active screen spill on infinity pool & ribs) ---
	RoomRender.set_light(screen, 0.015)
	RenderingServer.global_shader_parameter_set("screen_glow", 1.0)
	var vc2 := await RoomRender.open(self, doc, 92.0)
	var host2: Node = (vc2[2] as Node).host
	host2.snapshot_override = {"open": true, "playing": true, "position": 0.5, "duration": 7200.0}
	host2.signals.fake("film.brightness", 0.72)
	host2.signals.fake("film.colour", Color(0.88, 0.58, 0.36))
	host2.signals.fake("playback.playing", 1.0)
	_steps(host2, 14.0)
	await RoomRender.shot(self, vc2, eye, screen, "orbital_film_playing")
	await RoomRender.close(self, vc2)
