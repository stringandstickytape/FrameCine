extends "res://tests/env_builder_harness.gd"

## Cloud temple (app/environments/cloud_temple.env.json; docs/environments/rooms/cloud_temple.md): a luminous open-air
## classical white-marble sky-sanctuary suspended above an endless 360-degree golden-dusk sea of clouds that deepens
## into starlight and the rising Milky Way over the film. Built headless and verified against every shipped room check
## (schema, budget, blend layers, build speed, sight line from every seat, comfort, licences, names, no people, Sabine
## acoustics, audio levels) plus its architecture, cloud sea, reflecting basin, bronze braziers, sunset god-ray shafts,
## settings (sky_mood, braziers, god_rays), and temple bell ritual cues. Under lavapipe, renders 10 PNGs into ENV_SHOTS.
## godot --headless --xr-mode off --path app --script res://tests/test_room_cloud_temple.gd

const RoomRender := preload("res://tests/room_render.gd")
const RoomSound := preload("res://tests/room_sound.gd")
const SoundFixture := preload("res://tests/env_sound_fixture.gd")
const CloudTemple := preload("res://scripts/env/systems/kit/cloud_temple.gd")
const DOC := "res://environments/cloud_temple.env.json"


func run_tests() -> void:
	test_name = "test_room_cloud_temple"
	var r := EnvDoc.load_file(DOC)
	check("the document reads without schema errors (%s)" % [r["errors"]], (r["errors"] as Array).is_empty())
	var doc: Dictionary = r["doc"]
	if doc.is_empty():
		return
	if OS.get_environment("CT_RENDER_ONLY") == "":
		var room := await check_room("cloud_temple", doc)
		room.host.auto = false
		_by_part(room)
		await _built_and_budgets(room, doc)
		_physics_and_acoustics(room)
		_settings_and_cues(room)
		_sound(room)
		await done(room)
		await RoomSound.check_level(self, self, "cloud_temple", doc)
	await _render(doc)


## Figures, budgets, blended layers, build speed, metadata and expected scene nodes.
func _built_and_budgets(room: Node3D, doc: Dictionary) -> void:
	var host: Node = room.host
	var stats := EnvChecks.measure(room)
	print("  cloud_temple figures: %s" % [stats])
	check("tight budget: <= 34 draws, <= 90k tris, 0 live lights, 0 particles, < 32 MB (%s)" % [stats],
			int(stats["draws"]) <= 34 and int(stats["triangles"]) <= 90000 and int(stats["lights"]) == 0
			and int(stats["particles"]) == 0 and float(stats["texture_mb"]) < 32.0)

	var blend: Dictionary = await EnvChecks.blend_layers(self, room)
	print("  cloud_temple blend_layers: %s" % [blend])
	check("blended layers within budget (mean %.2f, peak %d, limit %.2f)" % [blend["mean"], blend["peak"],
			EnvChecks.BLEND_BUDGET], float(blend["mean"]) <= EnvChecks.BLEND_BUDGET)

	# Measure second build speed against EnvChecks.BUILD_BUDGET.
	var second: Node3D = EnvRoom.new()
	second.doc = doc
	var t0 := Time.get_ticks_usec()
	root.add_child(second)
	var build_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var units := EnvChecks.build_units(build_ms)
	root.remove_child(second)
	second.free()
	print("  cloud_temple build speed: %.1f pace units (%d ms)" % [units, roundi(build_ms)])
	check("builds within BUILD_BUDGET (%.1f <= %.1f)" % [units, EnvChecks.BUILD_BUDGET],
			units <= EnvChecks.BUILD_BUDGET)

	var meta: Dictionary = doc.get("room", {})
	check("metadata: name Cloud temple, category world, author Gemini 4 Neon Extra High",
			str(doc.get("name", "")) == "Cloud temple" and str(meta.get("category", "")) == "world"
			and str(meta.get("author", "")) == "Gemini 4 Neon Extra High")

	var dom: Node = host.system("room")
	check("domestic shell delegated to kit (no Floor/Walls/Ceiling/Window/Door)",
			str(dom.params["shell"]) == "kit" and room.get_node_or_null("Walls") == null
			and room.get_node_or_null("Floor") == null and room.get_node_or_null("Ceiling") == null
			and room.get_node_or_null("Window") == null and room.get_node_or_null("Door") == null)
	var kit: Node = host.system("kit")
	check("kit reports zero problems (%s)" % [kit.problems()], (kit.problems() as Array).is_empty())

	for n: String in ["PieceStatic", "PieceSoft", "PieceCove", "PieceLamps", "CloudSea", "SkyIslands",
			"ReflectingBasin", "BrazierFlames", "SunsetShafts", "Seats", "SkyDome", "SkyStars"]:
		check("room builds %s" % n, room.find_child(n, true, false) != null)

	# Verify opaque vs see-through shader discipline.
	for opaque_name: String in ["CloudSea", "SkyIslands", "ReflectingBasin"]:
		var mi := room.find_child(opaque_name, true, false) as MeshInstance3D
		check("%s is opaque (zero blend cost)" % opaque_name,
				mi != null and not EnvChecks.blends(mi.get_active_material(0)))
	for see_name: String in ["BrazierFlames", "SunsetShafts"]:
		var mi := room.find_child(see_name, true, false) as MeshInstance3D
		check("%s is in env_see_through" % see_name, mi != null and mi.is_in_group("env_see_through"))

	# 16 columns, 4 braziers, 12 temple cushion seats with viewer seat at origin.
	check("16 perimeter marble columns (%d)" % CloudTemple.column_azimuths().size(),
			CloudTemple.column_azimuths().size() == 16)
	var seats: Array[Transform3D] = room.room_seat_transforms()
	var own := seats.any(func(t: Transform3D) -> bool: return t.origin.length() < 0.001)
	check("12 temple cushion seats across 4 rows, viewer at origin (%d seats)" % seats.size(),
			seats.size() == 12 and own and str(host.system("seats").params["model"]) == "cushion")


## Physics boxes stay >= 0.5 m clear of viewer origin (0, 0, 0); Sabine alpha fits open-air colonnade box (0.05..0.75).
func _physics_and_acoustics(room: Node3D) -> void:
	var kit: Node = room.host.system("kit")
	var min_clearance := INF
	for sh: Array in kit.collision_shapes():
		var shape := sh[0] as BoxShape3D
		var xf: Transform3D = sh[1]
		if shape == null:
			continue
		var local_origin := xf.affine_inverse() * Vector3.ZERO
		var half := shape.size * 0.5
		var clamped := local_origin.clamp(-half, half)
		var dist := local_origin.distance_to(clamped)
		min_clearance = minf(min_clearance, dist)
	check("every kit physics box is >= 0.5 m clear of viewer (0, 0, 0) (min %.2f m)" % min_clearance,
			min_clearance >= 0.5)

	var sr: Dictionary = room.get_sound_room()
	var box: AABB = sr["box"]
	var s := box.size.abs()
	var v := s.x * s.y * s.z
	var area := 2.0 * (s.x * s.y + s.y * s.z + s.z * s.x)
	var alpha := 0.161 * v / (area * float(sr["rt60"]))
	print("  cloud_temple acoustics: box %s rt60 %.2f wet %.2f late %.2f Sabine alpha %.3f" % [s, float(sr["rt60"]),
			float(sr["wet"]), float(sr["late"]), alpha])
	check("Sabine mean absorption alpha in 0.05..0.75 (%.3f)" % alpha, alpha > 0.05 and alpha < 0.75)


## Settings (sky_mood, braziers, god_rays), motion scaling, flicker ceiling, and ritual bell cues.
func _settings_and_cues(room: Node3D) -> void:
	var host: Node = room.host
	var kit: Node = host.system("kit")
	var sky: Node = host.system("sky")
	var bell: Node = host.system("bell")
	var cloud_mi := room.find_child("CloudSea", true, false) as MeshInstance3D
	var flames_mi := room.find_child("BrazierFlames", true, false) as MeshInstance3D
	var shafts_mi := room.find_child("SunsetShafts", true, false) as MeshInstance3D

	# 1. Arrival (preshow): finish loading worker streams (triggers initial arrive bell), verify golden sunset & lamps.
	SoundFixture.finish_loading(room)
	host.snapshot_override = {"open": false}
	host.signals.fake("film.minutes", 0.0)
	_steps(host, 6.0)
	check("preshow: golden dusk (%.2f), bell rings on arrival (%d), house lamps full (%.2f)" % [
			float(sky.params["dusk"]), int(bell.plays), float(host.param("light.house_lamps"))],
			absf(float(sky.params["dusk"]) - 0.18) < 0.02 and int(bell.plays) == 1
			and float(host.param("light.house_lamps")) > 0.95)
	check("preshow: sunset shafts visible (%.2f) and cloud sea synced to dusk (%.2f)" % [
			float(shafts_mi.get_meta("shaft_level", 0.0)), float(cloud_mi.get_meta("dusk", -1.0))],
			shafts_mi.visible and float(shafts_mi.get_meta("shaft_level", 0.0)) > 0.18
			and absf(float(cloud_mi.get_meta("dusk", -1.0)) - 0.18) < 0.02)

	# 2. Starting ritual: temple bell rings again, house lamps dim to 0.22 while PieceCove keeps cove_floor 0.35.
	var plays_before := int(bell.plays)
	host.snapshot_override = {"open": true, "playing": true, "position": 0.5, "duration": 7200.0}
	_steps(host, 10.0)
	var cove_st: Dictionary = kit.cove_state()
	check("starting ritual: bell plays (%d -> %d), house lamps dim (%.2f), cove stays >= floor (%.2f)" % [
			plays_before, int(bell.plays), float(host.param("light.house_lamps")), float(cove_st.get("glow", 0.0))],
			int(bell.plays) == plays_before + 1 and absf(float(host.param("light.house_lamps")) - 0.22) < 0.02
			and float(cove_st.get("glow", 0.0)) > 0.35)

	# 3. Film-time sunset-to-Milky-Way track: dusk advances from 0.18 to 0.92 and shafts fade into night.
	host.snapshot_override = {"open": true, "playing": true, "position": 1800.0, "duration": 7200.0}
	host.signals.fake("film.minutes", 30.0)
	_steps(host, 12.0)
	check("mid-film sunset_to_stars: sky deepens to starlight (dusk %.2f), shafts fade (%.2f)" % [
			float(sky.params["dusk"]), float(shafts_mi.get_meta("shaft_level", 1.0))],
			float(sky.params["dusk"]) > 0.88 and float(cloud_mi.get_meta("dusk", 0.0)) > 0.88
			and float(shafts_mi.get_meta("shaft_level", 1.0)) < 0.04)

	# 4. sky_mood overrides: Eternal golden dusk holds sunset mid-film; Starlight clouds holds night in pre-show.
	host.set_setting("sky_mood", "golden_dusk")
	_steps(host, 4.0)
	check("sky_mood=golden_dusk holds sunset mid-film (dusk %.2f, shafts %.2f)" % [
			float(sky.params["dusk"]), float(shafts_mi.get_meta("shaft_level", 0.0))],
			absf(float(sky.params["dusk"]) - 0.18) < 0.03 and shafts_mi.visible)

	host.snapshot_override = {"open": false}
	host.signals.fake("film.minutes", 0.0)
	host.set_setting("sky_mood", "starlight_clouds")
	_steps(host, 4.0)
	check("sky_mood=starlight_clouds holds starlight night in pre-show (dusk %.2f)" % float(sky.params["dusk"]),
			absf(float(sky.params["dusk"]) - 0.92) < 0.03 and float(cloud_mi.get_meta("dusk", 0.0)) > 0.88)

	host.set_setting("sky_mood", "sunset_to_stars")
	_steps(host, 5.0)
	check("sky_mood=sunset_to_stars releases hold back to track (dusk %.2f)" % float(sky.params["dusk"]),
			absf(float(sky.params["dusk"]) - 0.18) < 0.04)

	# 5. god_rays setting: Soft shafts <-> Off.
	host.set_setting("god_rays", "off")
	_steps(host, 3.0)
	check("god_rays=off hides sunset light shafts (level %.3f)" % float(shafts_mi.get_meta("shaft_level", 1.0)),
			not shafts_mi.visible and float(shafts_mi.get_meta("shaft_level", 1.0)) < 0.01)
	host.set_setting("god_rays", "soft")
	_steps(host, 3.0)
	check("god_rays=soft restores sunset light shafts (level %.2f)" % float(shafts_mi.get_meta("shaft_level", 0.0)),
			shafts_mi.visible and float(shafts_mi.get_meta("shaft_level", 0.0)) > 0.18)

	# 6. braziers setting (lit / embers / off) & gentle sub-3 Hz flicker.
	host.set_setting("braziers", "lit")
	_steps(host, 4.0)
	var lo := 9.0
	var hi := 0.0
	for i in 90:
		host.step(1.0 / 30.0)
		var fl := float(flames_mi.get_meta("fire_level", 0.0))
		lo = minf(lo, fl)
		hi = maxf(hi, fl)
	check("braziers=lit burns brightly with gentle sub-3 Hz waver (%.2f..%.2f)" % [lo, hi],
			flames_mi.visible and lo > 0.80 and hi - lo > 0.02 and hi - lo < 0.35
			and CloudTemple.FLICKER_HZ.all(func(f: float) -> bool: return f < 3.0))

	host.set_setting("braziers", "embers")
	_steps(host, 4.0)
	var emb := float(flames_mi.get_meta("fire_level", 0.0))
	check("braziers=embers dims flames to low embers (%.2f)" % emb, emb > 0.18 and emb < 0.38)

	host.set_setting("braziers", "off")
	_steps(host, 4.0)
	check("braziers=off extinguishes flames (%.3f)" % float(flames_mi.get_meta("fire_level", 1.0)),
			not flames_mi.visible and float(flames_mi.get_meta("fire_level", 1.0)) < 0.01)
	host.set_setting("braziers", "lit")
	_steps(host, 4.0)

	# 7. Motion setting scales cloud sea drift cleanly (0 holds clouds still).
	var c0 := float(cloud_mi.get_meta("clock", 0.0))
	_steps(host, 2.0)
	var c1 := float(cloud_mi.get_meta("clock", 0.0))
	host.set_setting("motion", 0.0)
	_steps(host, 2.0)
	var c2 := float(cloud_mi.get_meta("clock", 0.0))
	check("cloud sea drifts with Motion (delta %.2f) and holds still at Motion 0 (delta %.3f)" % [c1 - c0, c2 - c1],
			c1 - c0 > 1.0 and absf(c2 - c1) < 0.001)
	host.set_setting("motion", 1.0)

	# 8. Ended cue: bell chimes and sanctuary lamps return to 1.0.
	host.snapshot_override = {"open": true, "playing": true, "position": 100.0, "duration": 7200.0}
	_steps(host, 2.0)
	var before_end := int(bell.plays)
	host.snapshot_override = {"open": true, "playing": false, "ended": true, "position": 7200.0, "duration": 7200.0}
	_steps(host, 6.0)
	check("ended cue: temple bell chimes (%d -> %d) and lamps rise (%.2f)" % [
			before_end, int(bell.plays), float(host.param("light.house_lamps"))],
			int(bell.plays) == before_end + 1 and float(host.param("light.house_lamps")) > 0.95)
	host.snapshot_override = {"open": false}
	host.signals.clear_fakes()


## Sound beds: cloud_wind, fire (follows braziers setting), temple_bell on outdoors acoustics.
func _sound(room: Node3D) -> void:
	RoomSound.check_beds(self, "cloud_temple", room, {
		"wind": "cloud_wind", "fire": "fire", "bell": "temple_bell",
	}, "outdoors")
	RoomSound.check_setting(self, "cloud_temple", room, "fire", "braziers", "off", "lit")


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


## Renders 10 lavapipe PNGs into ENV_SHOTS covering golden sunset, colonnade & cloud sea, braziers & god-rays,
## reflecting water basin, aft brass astrolabe & sky-arches, open sky overhead, and deep starlight Milky Way night.
func _render(doc: Dictionary) -> void:
	if not RoomRender.has_renderer():
		print("SKIP render (headless)")
		return
	var sc: Array = doc["screen"]["center"]
	var screen := Vector3(float(sc[0]), float(sc[1]), float(sc[2]))
	var eye := Vector3(0.0, 1.2, 0.0)

	# --- Phase 1: Golden Sunset Pre-show (dusk 0.18, warm sunlight, god-rays, lit bronze braziers) ---
	RoomRender.set_light(screen, 0.06)
	var vc := await RoomRender.open(self, doc, 90.0)
	var room := vc[2] as Node3D
	var host: Node = room.host
	SoundFixture.finish_loading(room)
	RenderingServer.global_shader_parameter_set("screen_glow", 0.25)
	host.snapshot_override = {"open": false}
	host.set_setting("sky_mood", "golden_dusk")
	host.set_setting("braziers", "lit")
	host.set_setting("god_rays", "soft")
	_steps(host, 6.0, 0.2)

	# 1. Golden sunset front view from viewer's seat.
	await RoomRender.shot(self, vc, eye, screen, "cloud_sunset_seat")
	# 2. Looking right across the fluted marble colonnade, sunset god-rays, golden cloud sea & sunset arch island.
	await RoomRender.shot(self, vc, eye, Vector3(14.0, 1.6, -9.0), "cloud_sunset_colonnade_right")
	# 3. Looking left across the colonnade, mosaic floor, braziers & twin-colonnade sky-island.
	await RoomRender.shot(self, vc, eye, Vector3(-14.0, 1.5, -8.5), "cloud_sunset_colonnade_left")
	# 4. Cast-bronze tripod brazier with golden flames & slanting sunset god-ray shafts.
	(vc[1] as Camera3D).fov = 68.0
	await RoomRender.shot(self, vc, Vector3(1.2, 1.45, -1.8), Vector3(6.2, 1.65, -6.5), "cloud_sunset_braziers_shafts")
	# 5. Low view across the sky-reflecting marble water basin toward twin fluted screen pylons & screen.
	await RoomRender.shot(self, vc, Vector3(-1.4, 1.15, -3.4), Vector3(0.4, 2.25, -11.4), "cloud_sunset_basin_pylons")
	# 6. Aft view across saffron cushions & marble plinths toward gleaming brass astrolabe altar & distant sky-arch.
	(vc[1] as Camera3D).fov = 78.0
	await RoomRender.shot(self, vc, Vector3(-0.8, 1.45, -0.8), Vector3(0.4, 1.95, 8.0), "cloud_sunset_aft_astrolabe")
	# 7. Looking up through the broken classical entablature & fluted capitals at the open golden-twilight sky.
	(vc[1] as Camera3D).fov = 90.0
	await RoomRender.shot(self, vc, eye, Vector3(2.8, 10.0, -5.5), "cloud_sunset_up_open_sky")
	# 8. Elevated overview showing the circular floating marble sanctuary, mosaic medallion, basin & 360 cloud sea.
	await RoomRender.shot(self, vc, Vector3(-6.2, 5.6, 5.4), Vector3(1.2, 0.6, -5.8), "cloud_sunset_overview")

	# --- Phase 2: Deep Starlight & Milky Way Film View (dusk 0.92, dimmed house lamps, cove floor, starlit clouds) ---
	RoomRender.set_light(screen, 0.022)
	RenderingServer.global_shader_parameter_set("screen_glow", 1.0)
	host.snapshot_override = {"open": true, "playing": true, "position": 2400.0, "duration": 7200.0}
	host.signals.fake("film.brightness", 0.72)
	host.signals.fake("film.colour", Color(0.85, 0.62, 0.38))
	host.signals.fake("playback.playing", 1.0)
	host.set_setting("sky_mood", "starlight_clouds")
	host.set_setting("braziers", "lit")
	_steps(host, 12.0, 0.25)

	# 9. Deep starlight Milky Way front seat view during film playback (golden coves + reflecting basin + starlit clouds).
	await RoomRender.shot(self, vc, eye, screen, "cloud_starlight_seat")
	# 10. Deep starlight Milky Way view looking left-and-up across colonnade, silver-blue clouds & stars.
	await RoomRender.shot(self, vc, Vector3(0.6, 1.35, 0.5), Vector3(-12.0, 5.8, -7.0), "cloud_starlight_milky_way")

	await RoomRender.close(self, vc)
