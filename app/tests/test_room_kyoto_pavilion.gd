extends "res://tests/env_builder_harness.gd"

## Kyoto garden pavilion (app/environments/kyoto_pavilion.env.json; docs/environments/rooms/kyoto_pavilion.md):
## a tranquil hinoki-cypress engawa pavilion opening onto a lantern-lit Kyoto night garden with animated mirror-emerald
## koi pond, 18 swimming Nishikigoi, curved vermilion footbridge, carved granite yukimi-doro stone lanterns, bamboo
## shishi-odoshi water-clack basin, raked Zen gravel courtyard, backlit sliding shoji screens, recessed tokonoma alcove,
## and seasonal weeping cherry / Japanese maple trees.
## Built headless and verified against every shipped room check (schema, strict budgets, atlas <= 1024, blend layers,
## build speed < 2.0 units, sight line from every seat, dead-centre head-on odd-row seating, comfort, licences, names,
## no people, Sabine acoustics, koi pond containment, settings, ritual cues, and sound levels). Under Vulkan Forward
## Mobile / lavapipe, renders 10 views into ENV_SHOTS for full visual self-inspection.
## godot --headless --xr-mode off --path app --script res://tests/test_room_kyoto_pavilion.gd

const RoomRender := preload("res://tests/room_render.gd")
const RoomSound := preload("res://tests/room_sound.gd")
const SoundFixture := preload("res://tests/env_sound_fixture.gd")
const KyotoPavilion := preload("res://scripts/env/systems/kit/kyoto_pavilion.gd")
const DOC := "res://environments/kyoto_pavilion.env.json"


func run_tests() -> void:
	test_name = "test_room_kyoto_pavilion"
	var r := EnvDoc.load_file(DOC)
	check("the document reads without schema errors (%s)" % [r["errors"]], (r["errors"] as Array).is_empty())
	var doc: Dictionary = r["doc"]
	if doc.is_empty():
		return
	if OS.get_environment("KYOTO_RENDER_ONLY") == "":
		var room := await check_room("kyoto_pavilion", doc)
		room.host.auto = false
		_by_part(room)
		await _built_and_budgets(room, doc)
		_dead_centre_seating(room)
		_physics_and_acoustics(room)
		_koi_and_fireflies(room)
		_settings_and_cues(room)
		_sound(room)
		await done(room)
		await RoomSound.check_level(self, self, "kyoto_pavilion", doc)
	await _render(doc)


## Strict budgets (0 live lights, draws <= 34, triangles <= 90k, texture_mb <= 12.0, atlas <= 1024x1024,
## blend_layers < 1.0, build < 2.0 pace units), metadata, domestic delegation, and expected nodes.
func _built_and_budgets(room: Node3D, doc: Dictionary) -> void:
	var host: Node = room.host
	var stats := EnvChecks.measure(room)
	print("  kyoto_pavilion figures: %s" % [stats])
	check("strict budgets: draws <= 34, tris <= 90k, 0 lights, tex <= 12 MB (%s)" % [stats],
			int(stats["draws"]) <= 34 and int(stats["triangles"]) <= 90000 and int(stats["lights"]) == 0
			and float(stats["texture_mb"]) <= 12.0)

	var largest := Vector2i.ZERO
	for mi: MeshInstance3D in room.static_meshes():
		largest = largest.max((mi.mesh as ArrayMesh).lightmap_size_hint)
	print("  kyoto_pavilion bake: %d static meshes, largest atlas %s" % [room.static_meshes().size(), largest])
	check("static meshes for bake, atlas <= 1024x1024 (%s)" % [largest],
			largest.x > 0 and largest.x <= 1024 and largest.y <= 1024)

	var blend: Dictionary = await EnvChecks.blend_layers(self, room)
	print("  kyoto_pavilion blend_layers: %s (budget %.2f)" % [blend, EnvChecks.BLEND_BUDGET])
	check("blended layers strictly under 1.0 (mean %.2f, peak %d)" % [blend["mean"], blend["peak"]],
			float(blend["mean"]) < EnvChecks.BLEND_BUDGET)

	# Second-build speed (cached procedural maps already warm).
	var second: Node3D = EnvRoom.new()
	second.doc = doc
	var t0 := Time.get_ticks_usec()
	root.add_child(second)
	await process_frame
	var build_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var units := EnvChecks.build_units(build_ms)
	root.remove_child(second)
	second.free()
	print("  kyoto_pavilion build speed: %.2f pace units (%.1f ms, limit < 2.0)" % [units, build_ms])
	check("second build time < 2.0 pace units (%.2f)" % units, units < 2.0)

	var meta: Dictionary = doc.get("room", {})
	var room_name := str(doc.get("name", ""))
	check("metadata: name Kyoto garden pavilion (no apostrophe), category retreat, author Gemini 4 Neon Extra High",
			room_name == "Kyoto garden pavilion" and not room_name.contains("'")
			and str(meta.get("category", "")) == "retreat"
			and str(meta.get("author", "")) == "Gemini 4 Neon Extra High")

	var dom: Node = host.system("room")
	check("domestic shell delegated to kit (no Walls/Floor/Ceiling/Window/Door)",
			str(dom.params["shell"]) == "kit" and room.get_node_or_null("Walls") == null
			and room.get_node_or_null("Floor") == null and room.get_node_or_null("Ceiling") == null
			and room.get_node_or_null("Window") == null and room.get_node_or_null("Door") == null)
	var kit: Node = host.system("fittings")
	check("kit reports zero problems (%s)" % [kit.problems()], (kit.problems() as Array).is_empty())

	var bake_lamps := room.find_children("KitLamp*", "OmniLight3D", true, false)
	var all_hidden := bake_lamps.all(func(l: Node) -> bool: return not (l as Light3D).visible)
	check("8 hidden bake omni lamps (%d)" % bake_lamps.size(), bake_lamps.size() == 8 and all_hidden)

	for n: String in ["PieceStatic", "PieceSoft", "PieceCove", "PieceLamps", "KyotoPondWater", "KyotoCanopy",
			"KyotoHills", "BambooRocker", "Seats", "SkyDome", "SkyStars", "SkyMoon", "Fish", "Fireflies"]:
		check("room builds %s" % n, room.find_child(n, true, false) != null)

	for opaque_name: String in ["KyotoPondWater", "KyotoCanopy", "KyotoHills"]:
		var mi := room.find_child(opaque_name, true, false) as MeshInstance3D
		check("%s is opaque (zero blend cost)" % opaque_name,
				mi != null and not EnvChecks.blends(mi.get_active_material(0)))


## Explicit verification of HARD USER REQUIREMENT: dead-centre seat at (0, 0, 0) facing -Z head-on at the screen,
## odd seat count per row (zero centre aisle), and every row contains a dead-centre seat at x = 0.0!
func _dead_centre_seating(room: Node3D) -> void:
	var seats: Array[Transform3D] = room.room_seat_transforms()
	check("6 zabuton cushion seats across 2 rows (%d seats)" % seats.size(),
			seats.size() == 6 and str(room.host.system("seats").params["model"]) == "cushion")
	var has_origin_head_on := false
	var by_row := {}
	for st: Transform3D in seats:
		var z_key := roundi(st.origin.z * 100.0)
		if not by_row.has(z_key):
			by_row[z_key] = []
		(by_row[z_key] as Array).append(st.origin.x)
		if st.origin.distance_to(Vector3.ZERO) < 0.001:
			var forward := -st.basis.z.normalized()
			if forward.dot(Vector3.FORWARD) > 0.999:
				has_origin_head_on = true
	check("dead-centre seat at (0.0, 0.0, 0.0) facing -Z head-on at the screen", has_origin_head_on)
	var all_odd_with_centre := not by_row.is_empty()
	for z_key: int in by_row:
		var xs: Array = by_row[z_key]
		var has_x0 := xs.any(func(x: float) -> bool: return absf(x) < 0.001)
		if xs.size() % 2 != 1 or not has_x0:
			all_odd_with_centre = false
	check("every row has odd seat count with a seat at x = 0.0 (zero centre aisle: %s)" % [by_row],
			all_odd_with_centre)


## Kit physics boxes stay >= 0.5 m clear of viewer origin (0, 0, 0) and Sabine mean absorption fits the pavilion box.
func _physics_and_acoustics(room: Node3D) -> void:
	var kit: Node = room.host.system("fittings")
	var min_clearance := INF
	for sh: Array in kit.collision_shapes():
		var shape := sh[0] as BoxShape3D
		var xf: Transform3D = sh[1]
		if shape == null:
			continue
		var lp := xf.affine_inverse() * Vector3.ZERO
		var half := shape.size * 0.5
		var dist := lp.distance_to(lp.clamp(-half, half))
		min_clearance = minf(min_clearance, dist)
	check("every kit physics box is >= 0.5 m clear of viewer origin (nearest %.2f m)" % min_clearance,
			min_clearance >= 0.5)

	var sr: Dictionary = room.get_sound_room()
	var box: AABB = sr["box"]
	var s := box.size.abs()
	var v := s.x * s.y * s.z
	var area := 2.0 * (s.x * s.y + s.y * s.z + s.z * s.x)
	var alpha := 0.161 * v / (area * float(sr["rt60"]))
	print("  kyoto_pavilion acoustics: box %s rt60 %.2f wet %.2f late %.2f Sabine alpha %.3f" % [s, float(sr["rt60"]),
			float(sr["wet"]), float(sr["late"]), alpha])
	check("Sabine mean absorption alpha in 0.05..0.75 (%.3f)" % alpha, alpha > 0.05 and alpha < 0.75)


## Living wildlife: 18 koi stay strictly in the shallow koi pond water (never floating out of water, never inside
## the pavilion deck, never in the sight line); fireflies remain clear of personal space and sight line.
func _koi_and_fireflies(room: Node3D) -> void:
	var host: Node = room.host
	var koi: Node = host.system("koi")
	var fireflies: Node = host.system("fireflies")
	_steps(host, 8.0, 0.2)

	var kpos: Array = koi.positions()
	check("18 living swimming koi populated (%d)" % kpos.size(), kpos.size() == 18)
	var bad_y := 0
	var in_pavilion := 0
	var in_sight := 0
	var min_koi_sep := INF
	for i in kpos.size():
		var p: Vector3 = kpos[i]
		if p.y < KyotoPavilion.WATER_Y - 0.02 or p.y > KyotoPavilion.WATER_Y + 0.05:
			bad_y += 1
		if p.x < 3.85 and p.z > -3.10:
			in_pavilion += 1
		if koi.in_view(p):
			in_sight += 1
		for j in range(i + 1, kpos.size()):
			var q: Vector3 = kpos[j]
			min_koi_sep = minf(min_koi_sep, Vector2(p.x - q.x, p.z - q.z).length())
	check("all 18 koi stay flat inside open koi pond clear of verandah (bad_y %d, near_engawa %d, sight %d, min_sep %.2f m)" % [
			bad_y, in_pavilion, in_sight, min_koi_sep],
			bad_y == 0 and in_pavilion == 0 and in_sight == 0 and min_koi_sep >= 0.45)

	# Switch to summer so all 28 fireflies emerge and verify clearance.
	host.set_setting("season", "summer")
	_steps(host, 6.0, 0.25)
	var fpos: Array = fireflies.positions()
	var bad_f := 0
	for p: Vector3 in fpos:
		if fireflies.in_view(p) or p.distance_to(Vector3(0.0, 1.2, 0.0)) < 3.4:
			bad_f += 1
	check("summer fireflies active (%d) and clear of personal space & sight line (%d intrusions)" % [
			fpos.size(), bad_f], fpos.size() >= 24 and bad_f == 0)
	host.set_setting("season", "sakura")
	_steps(host, 6.0, 0.25)


## Settings (season, lanterns, bamboo_spout, motion) and bamboo_clack ritual cues.
func _settings_and_cues(room: Node3D) -> void:
	var host: Node = room.host
	var kit: Node = host.system("fittings")
	var light_s: Node = host.system_of_kind("light")
	var spout: Node = host.system("spout")
	var petals: Node = host.system("petals")
	var fireflies: Node = host.system("fireflies")
	var water_mi := room.find_child("KyotoPondWater", true, false) as MeshInstance3D
	var canopy_mi := room.find_child("KyotoCanopy", true, false) as MeshInstance3D

	SoundFixture.finish_loading(room)
	host.snapshot_override = {"open": false}
	_steps(host, 6.0)

	# 1. Default Spring sakura + Warm washi + Steady bamboo spout.
	var sak_col: Color = canopy_mi.get_meta("canopy_tint")
	check("spring sakura defaults: pink blossom canopy (%s), petals active (%.2f), arrival clack played (%d)" % [
			sak_col, float(petals.params["intensity"]), int(spout.plays)],
			sak_col.r > 0.90 and sak_col.b > 0.72 and float(petals.params["intensity"]) > 0.80 and int(spout.plays) >= 1)

	# 2. Switch to Autumn maple -> rich crimson-gold canopy; Summer emerald -> lush green + full fireflies!
	host.set_setting("season", "maple")
	_steps(host, 8.0)
	var map_col: Color = canopy_mi.get_meta("canopy_tint")
	check("autumn maple shifts canopy to crimson-gold (%s)" % [map_col],
			map_col.r > 0.80 and map_col.g < 0.45 and map_col.b < 0.28)

	host.set_setting("season", "summer")
	_steps(host, 8.0)
	var sum_col: Color = canopy_mi.get_meta("canopy_tint")
	check("summer shifts canopy to emerald (%s), stops petals (%.2f), raises fireflies (%.2f)" % [
			sum_col, float(petals.params["intensity"]), float(fireflies.params["activity"])],
			sum_col.g > sum_col.r and float(petals.params["intensity"]) < 0.05
			and float(fireflies.params["activity"]) > 0.95)
	host.set_setting("season", "sakura")
	_steps(host, 8.0)

	# 3. Lanterns setting: washi -> moonlight -> dim -> washi.
	var washi_cove: Dictionary = kit.cove_state()
	host.set_setting("lanterns", "moonlight")
	_steps(host, 5.0)
	var moon_cove: Dictionary = kit.cove_state()
	var moon_col: Color = moon_cove["colour"]
	check("moonlight lanterns shift cove & lamp tint to cool silver-blue (%s, mix %.2f)" % [
			moon_col, float(light_s.params["glow_mix"])],
			moon_col.b > moon_col.r and float(light_s.params["glow_mix"]) > 0.85)
	host.set_setting("lanterns", "dim")
	_steps(host, 5.0)
	var dim_cove: Dictionary = kit.cove_state()
	check("dim lanterns soften cove glow (%.2f -> %.2f)" % [float(washi_cove["glow"]), float(dim_cove["glow"])],
			float(dim_cove["glow"]) < float(washi_cove["glow"]) * 0.45)
	host.set_setting("lanterns", "washi")
	_steps(host, 5.0)

	# 4. Film start ritual & ended cues: bamboo_clack plays, house_lamps dim to 0.18 while cove keeps floor >= 0.36.
	var plays_before := int(spout.plays)
	host.snapshot_override = {"open": true, "playing": true, "position": 0.5, "duration": 7200.0}
	_steps(host, 10.0)
	var during_lamps := float(host.param("light.house_lamps"))
	var during_cove := float(kit.cove_state()["glow"])
	check("film start ritual plays bamboo_clack (%d -> %d) and dims lamps (%.2f)" % [
			plays_before, int(spout.plays), during_lamps],
			int(spout.plays) > plays_before and absf(during_lamps - 0.18) < 0.02)
	check("cove floor keeps gentle backlit shoji glow during film (%.2f)" % during_cove, during_cove >= 0.36)

	var before_end := int(spout.plays)
	host.snapshot_override = {"open": true, "playing": false, "ended": true, "position": 7200.0, "duration": 7200.0}
	_steps(host, 8.0)
	check("ended cue plays departure bamboo_clack (%d -> %d) and restores lamps (%.2f)" % [
			before_end, int(spout.plays), float(host.param("light.house_lamps"))],
			int(spout.plays) > before_end and float(host.param("light.house_lamps")) > 0.95)
	host.snapshot_override = {"open": false}
	_steps(host, 4.0)

	# 5. Motion setting scales pond clock and freezes at 0.
	var c0 := float(water_mi.get_meta("clock", 0.0))
	host.set_setting("motion", 1.0)
	_steps(host, 1.5)
	var c1 := float(water_mi.get_meta("clock", 0.0))
	host.set_setting("motion", 0.0)
	_steps(host, 1.5)
	var c2 := float(water_mi.get_meta("clock", 0.0))
	check("pond water clock advances with Motion=1 and freezes at Motion=0 (%.2f -> %.2f -> %.2f)" % [c0, c1, c2],
			c1 > c0 + 1.0 and absf(c2 - c1) < 0.001)
	host.set_setting("motion", 1.0)


## Sound beds (bamboo_clack, fountain, crickets, wind), bamboo_spout setting control, and small_room acoustics.
func _sound(room: Node3D) -> void:
	RoomSound.check_beds(self, "kyoto_pavilion", room, {
		"spout": "bamboo_clack",
		"pond": "fountain",
		"crickets": "crickets",
		"breeze": "wind",
	}, "small_room")
	var host: Node = room.host
	var spout: Node = host.system("spout")
	host.set_setting("bamboo_spout", "quiet")
	_steps(host, 6.0)
	var plays_quiet := int(spout.plays)
	host.do_action("spout.play", {})
	check("bamboo_spout=quiet silences spout level (%.2f) and suppresses clacks (%d == %d)" % [
			float(spout.params["level"]), int(spout.plays), plays_quiet],
			float(spout.params["level"]) < 0.02 and int(spout.plays) == plays_quiet)
	host.set_setting("bamboo_spout", "rare")
	_steps(host, 6.0)
	check("bamboo_spout=rare softens spout level (%.2f)" % float(spout.params["level"]),
			float(spout.params["level"]) > 0.35 and float(spout.params["level"]) < 0.55)
	host.set_setting("bamboo_spout", "steady")
	_steps(host, 6.0)
	var plays_steady := int(spout.plays)
	host.do_action("spout.play", {})
	check("bamboo_spout=steady restores full spout level (%.2f) and clacks (%d -> %d)" % [
			float(spout.params["level"]), plays_steady, int(spout.plays)],
			float(spout.params["level"]) > 0.95 and int(spout.plays) == plays_steady + 1)


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


## Renders 10 lavapipe PNGs to ENV_SHOTS covering every architectural detail, seasonal canopy, koi pond, bridge,
## Zen courtyard, backlit shoji & tokonoma alcove, ceiling rafters, and film playing.
func _render(doc: Dictionary) -> void:
	if not RoomRender.has_renderer():
		print("SKIP render (headless)")
		return
	var sc: Array = doc["screen"]["center"]
	var screen := Vector3(float(sc[0]), float(sc[1]), float(sc[2]))
	var eye := Vector3(0.0, 1.2, 0.0)

	# --- Pass 1: Spring Sakura + Warm Washi Lanterns (Pre-show) ---
	RoomRender.set_light(screen, float(doc["room"]["ambient"]))
	RenderingServer.global_shader_parameter_set("screen_glow", 0.22)
	var vc := await RoomRender.open(self, doc, 90.0)
	var room := vc[2] as Node3D
	var host: Node = room.host
	SoundFixture.finish_loading(room)
	host.snapshot_override = {"open": false}
	host.set_setting("season", "sakura")
	host.set_setting("lanterns", "washi")
	_steps(host, 6.0, 0.2)

	# 1. Dead-centre seat head-on view across chabudai & koi pond to torii screen, sakura trees & moon!
	await RoomRender.shot(self, vc, eye, screen, "kyoto_01_front_seat_sakura")
	# 2. Starboard view across engawa to curved vermilion footbridge, swimming koi & stone lanterns!
	await RoomRender.shot(self, vc, Vector3(0.6, 1.35, -0.5), Vector3(6.8, 0.35, -2.1), "kyoto_02_starboard_bridge_koi")
	# 3. Port view across engawa to raked Zen gravel courtyard, mossy rocks & bamboo shishi-odoshi basin!
	await RoomRender.shot(self, vc, Vector3(-0.6, 1.45, -0.4), Vector3(-6.4, -0.15, -0.6), "kyoto_03_port_zen_spout")
	# 4. Aft view across zabuton cushions & tatami toward backlit shoji screens & recessed tokonoma alcove!
	await RoomRender.shot(self, vc, Vector3(0.0, 1.35, -1.6), Vector3(0.0, 1.45, 3.2), "kyoto_04_aft_shoji_tokonoma")
	# 5. Looking up at exposed hinoki rafters (taruki), tie-beams, king posts & cantilevered kawara eaves!
	await RoomRender.shot(self, vc, Vector3(0.0, 1.15, 0.4), Vector3(0.4, 4.8, -2.6), "kyoto_05_ceiling_rafters_up")
	# 6. Angled close-up of woven tatami, zabuton cushions, glossy chabudai tea table, teapot, matcha cups & andon!
	(vc[1] as Camera3D).fov = 78.0
	await RoomRender.shot(self, vc, Vector3(-1.35, 1.15, 0.35), Vector3(0.15, 0.18, -1.55), "kyoto_06_chabudai_tatami")
	(vc[1] as Camera3D).fov = 90.0

	# --- Pass 2: Autumn Maple Season (crimson-gold trees over pond & red footbridge!) ---
	host.set_setting("season", "maple")
	_steps(host, 8.0, 0.25)
	await RoomRender.shot(self, vc, Vector3(-0.6, 1.35, 0.4), Vector3(2.8, 1.75, -5.8), "kyoto_07_autumn_maple")

	# --- Pass 3: Summer Emerald + Moonlit Silver Lanterns + Glowing Garden Fireflies! ---
	host.set_setting("season", "summer")
	host.set_setting("lanterns", "moonlight")
	_steps(host, 8.0, 0.25)
	await RoomRender.shot(self, vc, Vector3(0.2, 1.30, 0.5), Vector3(1.8, 1.55, -6.2), "kyoto_08_summer_moonlight")

	# --- Pass 4: Film Playing (Spring Sakura + Warm Washi dimmed, live screen spill rippling across koi pond!) ---
	host.set_setting("season", "sakura")
	host.set_setting("lanterns", "washi")
	RoomRender.set_light(screen, 0.018)
	RenderingServer.global_shader_parameter_set("screen_glow", 1.0)
	host.snapshot_override = {"open": true, "playing": true, "position": 900.0, "duration": 7200.0}
	host.signals.fake("film.brightness", 0.78)
	host.signals.fake("film.colour", Color(0.95, 0.62, 0.34))
	host.signals.fake("playback.playing", 1.0)
	_steps(host, 12.0, 0.25)
	await RoomRender.shot(self, vc, eye, screen, "kyoto_09_film_playing")

	# --- Pass 5: Elevated Garden Overview (Pre-show Spring Sakura, showing full pavilion, pond, bridge & Zen garden) ---
	RoomRender.set_light(screen, float(doc["room"]["ambient"]))
	RenderingServer.global_shader_parameter_set("screen_glow", 0.22)
	host.snapshot_override = {"open": false}
	_steps(host, 8.0, 0.25)
	await RoomRender.shot(self, vc, Vector3(-5.8, 5.4, 5.2), Vector3(1.4, 0.4, -4.6), "kyoto_10_garden_overview")

	await RoomRender.close(self, vc)
