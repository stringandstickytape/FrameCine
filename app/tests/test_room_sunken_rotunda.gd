extends "res://tests/env_builder_harness.gd"

## Sunken rotunda (app/environments/sunken_rotunda.env.json; docs/environments/rooms/sunken_rotunda.md): a flooded
## classical marble Atlantis rotunda resting on the sunlit ocean floor beneath shimmering underwater caustics,
## surrounded by schooling fish, bioluminescent jellies, a gliding manta ray, and a rare whale.
## Built headless from its document and checked as every shipped room is (schema, budget, sight lines from every seat,
## blend layers, build time, comfort, licences, names, no people) and as a builder's room (seats, physics, bake, seat
## picking); then its own parts, settings (water_light, lanterns, whale, motion), cues (dim, lights_up, opening_bell),
## marine life clearances, and sound levels (tests/room_sound.gd).
## Under Vulkan Forward Mobile / lavapipe, renders 9 views to ENV_SHOTS covering the mosaic sanctuary, ruined oculus
## & manta, port/starboard colonnade arches, aft ruins, Deep sapphire / Sea cyan & Bioluminescent night variants, and
## film-playing dimmed view.
## godot --headless --xr-mode off --path app --script res://tests/test_room_sunken_rotunda.gd

const RoomRender := preload("res://tests/room_render.gd")
const RoomSound := preload("res://tests/room_sound.gd")
const DOC := "res://environments/sunken_rotunda.env.json"


func run_tests() -> void:
	test_name = "test_room_sunken_rotunda"
	var r := EnvDoc.load_file(DOC)
	check("the document reads (%s)" % [r["errors"]], (r["errors"] as Array).is_empty())
	var doc: Dictionary = r["doc"]
	if doc.is_empty():
		return
	if OS.get_environment("ROTUNDA_RENDER_ONLY") == "":
		var room := await check_room("sunken_rotunda", doc)
		room.host.auto = false
		_by_part(room)
		await _built(room, doc)
		_settings_and_water(room)
		_ritual(room)
		_marine_life(room)
		_sound(room)
		await done(room)
		await _build_speed(doc)
		await RoomSound.check_level(self, self, "sunken_rotunda", doc)
	await _render(doc)


## Figures, parts, domestic shell left to kit, physics clearance around (0, 0, 0), and blended layer budget.
func _built(room: Node3D, doc: Dictionary) -> void:
	var host: Node = room.host
	var stats := EnvChecks.measure(room)
	check("strict budget: draws <= 34, triangles <= 90k, 0 live lights, 0 particles, <= 64 MB (%s)" % [stats],
			int(stats["draws"]) <= 34 and int(stats["triangles"]) <= 90000 and int(stats["lights"]) == 0
			and int(stats["particles"]) == 0 and float(stats["texture_mb"]) <= 64.0)
	check("room metadata category world and author",
			str(doc["room"]["category"]) == "world" and str(doc["room"]["author"]) == "Gemini 4 Neon Extra High")
	for n: String in ["PieceStatic", "PieceSoft", "PieceLamps", "PieceCove", "RotundaWater", "RotundaShafts",
			"RotundaAqueducts", "Seats", "SkyDome"]:
		check("the room has its %s" % n, room.find_child(n, true, false) != null)
	for n: String in ["Walls", "Floor", "Ceiling", "Trim", "Screen"]:
		check("domestic shell %s left to the kit" % n, room.get_node_or_null(n) == null)
	var shafts := room.find_child("RotundaShafts", true, false) as MeshInstance3D
	check("light shafts are in env_see_through", shafts != null and shafts.is_in_group("env_see_through"))
	var kit: Node = host.system("fittings")
	check("the kit builds with zero problems (%s)" % [kit.problems()], kit.problems().is_empty())
	var bake_lamps := room.find_children("KitLamp*", "OmniLight3D", true, false)
	var all_hidden := bake_lamps.all(func(l: Node) -> bool: return not (l as Light3D).visible)
	check("8 hidden bake omni lamps for the sanctuary lanterns (%d)" % bake_lamps.size(),
			bake_lamps.size() == 8 and all_hidden)
	# Bake atlas check, sound room & physics boxes under every seat.
	var largest := Vector2i.ZERO
	for mi: MeshInstance3D in room.static_meshes():
		largest = largest.max((mi.mesh as ArrayMesh).lightmap_size_hint)
	print("  bake: %d static meshes, largest atlas %s" % [room.static_meshes().size(), largest])
	check("static meshes for bake, atlas under %d (%s)" % [MAX_ATLAS, largest],
			largest.x > 0 and largest.x <= MAX_ATLAS and largest.y <= MAX_ATLAS)
	check("sound room with box and collision shapes (%d)" % room.collision_shapes().size(),
			room.get_sound_room().has("box") and room.collision_shapes().size() > 24)
	# Kit physics boxes must stay >= 0.5 m clear of viewer origin (0, 0, 0).
	var nearest := INF
	for sh: Array in kit.collision_shapes():
		var shape: BoxShape3D = sh[0] as BoxShape3D
		var xf: Transform3D = sh[1]
		var lp := xf.affine_inverse() * Vector3.ZERO
		var hs := shape.size * 0.5
		var clamped := lp.clamp(-hs, hs)
		nearest = minf(nearest, lp.distance_to(clamped))
	check("kit physics boxes stay >= 0.5 m clear of viewer origin (nearest %.2f m)" % nearest, nearest >= 0.5)
	var bl := await EnvChecks.blend_layers(self, room)
	print("  blend_layers: %s (budget %.2f)" % [bl, EnvChecks.BLEND_BUDGET])
	check("blended layers within budget (%s <= %.2f)" % [bl, EnvChecks.BLEND_BUDGET],
			float(bl["mean"]) <= EnvChecks.BLEND_BUDGET)


## Measure second-build speed against EnvChecks.BUILD_BUDGET (cached procedural textures already warm).
func _build_speed(doc: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	var room2: Node3D = EnvRoom.new()
	room2.doc = doc
	root.add_child(room2)
	await process_frame
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var units := EnvChecks.build_units(ms)
	print("  build_time: %.1f ms (%.2f pace units, budget %.1f)" % [ms, units, EnvChecks.BUILD_BUDGET])
	check("second build time within BUILD_BUDGET (%.2f <= %.1f)" % [units, EnvChecks.BUILD_BUDGET],
			units <= EnvChecks.BUILD_BUDGET)
	await done(room2)


## Live settings (water_light, lanterns, motion) drive caustics, pelagic sky, water shader, shafts, lamps & coves.
func _settings_and_water(room: Node3D) -> void:
	var host: Node = room.host
	var light_s: Node = host.system_of_kind("light")
	var sky_s: Node = host.system_of_kind("sky")
	var kit_s: Node = host.system("fittings")
	var jellies_s: Node = host.system("jellies")
	var water_mi := room.find_child("RotundaWater", true, false) as MeshInstance3D

	# Default: Sunlit turquoise + Warm gold lanterns.
	_steps(host, 4.0)
	var sun_c := float(light_s.params["caustics"])
	var sun_dusk := float(sky_s.params["dusk"])
	var sun_shaft := float(water_mi.get_meta("shaft_level"))
	var sun_jelly := float(jellies_s.params["glow"])
	check("sunlit turquoise defaults (caustics %.2f, dusk %.2f, shaft %.2f)" % [sun_c, sun_dusk, sun_shaft],
			sun_c > 0.8 and sun_dusk < 0.25 and sun_shaft > 0.35)

	# Switch to Deep sapphire.
	host.set_setting("water_light", "sapphire")
	_steps(host, 6.0)
	var sap_c := float(light_s.params["caustics"])
	var sap_dusk := float(sky_s.params["dusk"])
	var sap_shaft := float(water_mi.get_meta("shaft_level"))
	check("deep sapphire lowers caustics/shafts and deepens pelagic sky (%.2f, %.2f, %.2f)" % [sap_c, sap_dusk, sap_shaft],
			sap_c < sun_c - 0.25 and sap_dusk > 0.85 and sap_shaft < sun_shaft)

	# Switch to Bioluminescent night.
	host.set_setting("water_light", "bioluminescent")
	_steps(host, 6.0)
	var bio_c := float(light_s.params["caustics"])
	var bio_blk := float(sky_s.params["blackout"])
	var bio_jelly := float(jellies_s.params["glow"])
	check("bioluminescent night darkens sky and boosts jelly glow (caustics %.2f, blackout %.2f, jelly %.2f)" % [
			bio_c, bio_blk, bio_jelly], bio_c < sap_c and bio_blk > 0.5 and bio_jelly > sun_jelly + 0.5)

	# Restore sunlit.
	host.set_setting("water_light", "sunlit")
	_steps(host, 6.0)

	# Lanterns setting: Warm gold -> Sea cyan -> Dim -> Warm gold.
	var gold_cove: Dictionary = kit_s.cove_state()
	host.set_setting("lanterns", "cyan")
	_steps(host, 4.0)
	var cyan_cove: Dictionary = kit_s.cove_state()
	var cyan_col: Color = cyan_cove["colour"]
	check("sea cyan lanterns shift cove & lamp tint toward cyan (%s)" % cyan_col,
			cyan_col.b > cyan_col.r and float(light_s.params["glow_mix"]) > 0.9)
	host.set_setting("lanterns", "dim")
	_steps(host, 4.0)
	var dim_cove: Dictionary = kit_s.cove_state()
	check("dim lanterns lower cove glow (%.2f -> %.2f)" % [float(gold_cove["glow"]), float(dim_cove["glow"])],
			float(dim_cove["glow"]) < float(gold_cove["glow"]) * 0.45)
	host.set_setting("lanterns", "gold")
	_steps(host, 4.0)

	# Motion setting scales water animation clock cleanly (0 pauses it).
	var t0 := float(water_mi.get_meta("clock"))
	host.set_setting("motion", 1.0)
	_steps(host, 1.0)
	var t1 := float(water_mi.get_meta("clock"))
	host.set_setting("motion", 0.0)
	_steps(host, 1.0)
	var t2 := float(water_mi.get_meta("clock"))
	check("water clock advances with Motion=1 and freezes at Motion=0 (%.2f -> %.2f -> %.2f)" % [t0, t1, t2],
			t1 > t0 + 0.8 and absf(t2 - t1) < 0.001)
	host.set_setting("motion", 1.0)


## Ritual cues: temple_bell rings on starting, house_lamps dim to 0.18 while coves keep 0.38 floor, restored on ended.
func _ritual(room: Node3D) -> void:
	var host: Node = room.host
	var bell: Node = host.system("bell")
	var kit_s: Node = host.system("fittings")
	bell.finish_loading()
	host.timeline.state = ""
	host.snapshot_override = {"open": false}
	_steps(host, 8.0)
	var before_lamps := float(host.param("light.house_lamps"))
	var before_bell := int(bell.plays)
	check("pre-show house lamps full (%.2f)" % before_lamps, before_lamps > 0.95)

	host.snapshot_override = {"open": true, "playing": true, "position": 0.5, "duration": 7200.0}
	_steps(host, 12.0)
	var during_lamps := float(host.param("light.house_lamps"))
	var during_cove := float(kit_s.cove_state()["glow"])
	check("film start dims house lamps to 0.18 and rings opening temple bell (%.2f, plays %d -> %d)" % [
			during_lamps, before_bell, int(bell.plays)],
			absf(during_lamps - 0.18) < 0.02 and int(bell.plays) > before_bell)
	check("cove floor keeps gentle glow during film (%.2f)" % during_cove, during_cove >= 0.38)

	host.snapshot_override = {"open": true, "playing": false, "ended": true, "position": 7200.0, "duration": 7200.0}
	_steps(host, 10.0)
	check("ended restores house lamps to 1.0 (%.2f)" % float(host.param("light.house_lamps")),
			float(host.param("light.house_lamps")) > 0.95)


## Marine life: port/starboard schooling fish, jellies, overhead manta ray, and far whale — all clear of dais & sight line.
func _marine_life(room: Node3D) -> void:
	var host: Node = room.host
	var port_f: Node = host.system("port_fish")
	var stbd_f: Node = host.system("starboard_fish")
	var jel: Node = host.system("jellies")
	var manta: Node = host.system("manta")
	var whale: Node = host.system("whale")
	host.do_action("manta.pass", {})
	host.do_action("whale.pass", {})
	_steps(host, 8.0)

	var pf_pos: Array = port_f.positions()
	var sf_pos: Array = stbd_f.positions()
	var j_pos: Array = jel.positions()
	var m_pos: Array = manta.positions()
	var w_pos: Array = whale.positions()
	check("marine life populated: port fish %d, starboard fish %d, jellies %d, manta %d, whale %d" % [
			pf_pos.size(), sf_pos.size(), j_pos.size(), m_pos.size(), w_pos.size()],
			pf_pos.size() == 34 and sf_pos.size() == 28 and j_pos.size() == 14 and m_pos.size() == 1 and w_pos.size() == 1)

	var intruding := 0
	for p: Vector3 in pf_pos:
		if p.x > -7.0 or port_f.in_view(p):
			intruding += 1
	for p: Vector3 in sf_pos:
		if p.x < 7.0 or stbd_f.in_view(p):
			intruding += 1
	for p: Vector3 in j_pos:
		if p.y < 5.0 or jel.in_view(p):
			intruding += 1
	for p: Vector3 in m_pos:
		if p.y < 10.5 or manta.in_view(p):
			intruding += 1
	for p: Vector3 in w_pos:
		if p.z > -16.0 or whale.in_view(p):
			intruding += 1
	check("all marine life strictly outside dry dais and sight line (%d intrusions)" % intruding, intruding == 0)


## Sound beds and stone_nave acoustics verification.
func _sound(room: Node3D) -> void:
	RoomSound.check_beds(self, "sunken_rotunda", room, {
		"deep": "deep_hum",
		"canal_lap": "water_lap",
		"reef_bubbles": "bubbles",
		"bell": "temple_bell",
		"far_song": "whale",
	}, "stone_nave")


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


## Renders 9 lavapipe PNGs to ENV_SHOTS covering every angle, lighting mood, marine life showcase, and film state.
func _render(doc: Dictionary) -> void:
	if not RoomRender.has_renderer():
		print("SKIP render (headless)")
		return
	var sc: Array = doc["screen"]["center"]
	var screen := Vector3(float(sc[0]), float(sc[1]), float(sc[2]))
	var eye := Vector3(0.0, 1.2, 0.0)

	# --- Pass 1: Pre-show Sunlit turquoise + Warm gold lanterns (6 architectural & marine views) ---
	RoomRender.set_light(screen, float(doc["room"]["ambient"]))
	RenderingServer.global_shader_parameter_set("screen_glow", 0.0)
	var vc := await RoomRender.open(self, doc, 90.0)
	var host: Node = (vc[2] as Node).host
	host.snapshot_override = {"open": false}
	host.signals.fake("film.brightness", 0.35)
	host.signals.fake("film.colour", Color(0.32, 0.85, 0.92))
	# Trigger manta ray so it glides gracefully into the sunlit oculus at a flattering 3/4 angle!
	host.do_action("manta.pass", {"side": "left"})
	_steps(host, 10.5, 0.25)

	await RoomRender.shot(self, vc, eye, screen, "rotunda_01_front_sanctuary")
	await RoomRender.shot(self, vc, Vector3(-2.3, 2.35, 3.65), Vector3(0.0, 0.55, -5.8), "rotunda_02_mosaic_canal_wide")
	await RoomRender.shot(self, vc, Vector3(0.6, 1.25, 1.8), Vector3(-0.6, 11.4, -2.8), "rotunda_03_oculus_up")
	await RoomRender.shot(self, vc, Vector3(0.4, 1.35, -0.4), Vector3(-9.2, 2.5, -2.6), "rotunda_04_port_colonnade")
	await RoomRender.shot(self, vc, Vector3(-0.4, 1.35, -0.4), Vector3(9.2, 2.6, 0.8), "rotunda_05_starboard_breach")
	await RoomRender.shot(self, vc, Vector3(0.0, 1.45, -2.4), Vector3(0.0, 2.3, 8.2), "rotunda_06_aft_arches")

	# --- Pass 2: Deep sapphire + Sea cyan lanterns + Whale gliding past the far port colonnade arches ---
	host.set_setting("water_light", "sapphire")
	host.set_setting("lanterns", "cyan")
	host.do_action("whale.pass", {"side": "left", "seconds": 28.0})
	_steps(host, 7.5, 0.25)
	await RoomRender.shot(self, vc, Vector3(1.2, 1.45, 1.6), Vector3(-3.8, 3.4, -10.2), "rotunda_07_sapphire_cyan")

	# --- Pass 3: Bioluminescent night + Warm gold lanterns ---
	host.set_setting("water_light", "bioluminescent")
	host.set_setting("lanterns", "gold")
	_steps(host, 10.0, 0.25)
	await RoomRender.shot(self, vc, Vector3(-1.2, 1.55, 2.2), Vector3(0.4, 2.8, -8.5), "rotunda_08_bioluminescent_night")

	# --- Pass 4: Film playing (Sunlit turquoise, dimmed lanterns, live screen spill on canal & marble) ---
	host.set_setting("water_light", "sunlit")
	host.set_setting("lanterns", "gold")
	RoomRender.set_light(screen, 0.016)
	RenderingServer.global_shader_parameter_set("screen_glow", 1.0)
	host.snapshot_override = {"open": true, "playing": true, "position": 0.5, "duration": 7200.0}
	host.signals.fake("film.brightness", 0.78)
	host.signals.fake("film.colour", Color(0.92, 0.58, 0.34))
	host.signals.fake("playback.playing", 1.0)
	_steps(host, 14.0, 0.25)
	await RoomRender.shot(self, vc, eye, screen, "rotunda_09_film_playing")

	await RoomRender.close(self, vc)
