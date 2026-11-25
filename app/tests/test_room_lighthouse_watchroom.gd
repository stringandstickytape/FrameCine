extends "res://tests/env_builder_harness.gd"

## Lighthouse watchroom (app/environments/lighthouse_watchroom.env.json; docs/environments/rooms/lighthouse_watchroom.md):
## a circular whitewashed-stone & painted cast-iron coastal lighthouse lantern/watchroom perched 26 m above a stormy
## Atlantic headland, crowned by a live rotating first-order brass-and-crystal Fresnel dioptric drum sweeping twin
## golden-ivory volumetric beams over the dark sea.
## Verifies every shipped room check (schema, tight budgets, atlas <= 1024, blend overdraw < 1.0, build < 2.0 units,
## clear sight lines from every seat, dead-centre head-on seat at x=0 z=0 & odd count per row, comfort, licences,
## names, no people, Sabine acoustics, audio levels) plus Fresnel beam modes, Motion scaling, storm weather & panes,
## foghorn ritual cues, and working ship's chronometer clock. Under lavapipe, renders 10 PNGs into ENV_SHOTS.
## godot --headless --xr-mode off --path app --script res://tests/test_room_lighthouse_watchroom.gd

const RoomRender := preload("res://tests/room_render.gd")
const RoomSound := preload("res://tests/room_sound.gd")
const SoundFixture := preload("res://tests/env_sound_fixture.gd")
const Lighthouse := preload("res://scripts/env/systems/kit/lighthouse_watchroom.gd")
const DOC := "res://environments/lighthouse_watchroom.env.json"


func run_tests() -> void:
	test_name = "test_room_lighthouse_watchroom"
	var r := EnvDoc.load_file(DOC)
	check("the document reads without schema errors (%s)" % [r["errors"]], (r["errors"] as Array).is_empty())
	var doc: Dictionary = r["doc"]
	if doc.is_empty():
		return
	if OS.get_environment("LW_RENDER_ONLY") == "":
		var room := await check_room("lighthouse_watchroom", doc)
		room.host.auto = false
		_by_part(room)
		await _built_and_budgets(room, doc)
		_dead_centre_seating(room)
		_physics_and_acoustics(room)
		_settings_and_cues(room)
		_sound(room)
		await done(room)
		await RoomSound.check_level(self, self, "lighthouse_watchroom", doc)
	await _render(doc)


## Tight budgets, lightmap atlas, blended overdraw, build speed, metadata and expected scene nodes.
func _built_and_budgets(room: Node3D, doc: Dictionary) -> void:
	var host: Node = room.host
	var stats := EnvChecks.measure(room)
	print("  lighthouse_watchroom figures: %s" % [stats])
	check("tight budget: <= 34 draws, <= 90k tris, 0 live lights, <= 12 MB textures (%s)" % [stats],
			int(stats["draws"]) <= 34 and int(stats["triangles"]) <= 90000 and int(stats["lights"]) == 0
			and float(stats["texture_mb"]) <= 12.0)

	var largest := Vector2i.ZERO
	for mi: MeshInstance3D in room.static_meshes():
		largest = largest.max((mi.mesh as ArrayMesh).lightmap_size_hint)
	print("  lighthouse_watchroom atlas: %s" % [largest])
	check("lightmap atlas <= 1024x1024 (%s)" % [largest],
			largest.x > 0 and largest.x <= 1024 and largest.y <= 1024)

	var blend: Dictionary = await EnvChecks.blend_layers(self, room)
	print("  lighthouse_watchroom blend_layers: %s" % [blend])
	check("blended layers within budget (mean %.2f, peak %d, limit %.2f)" % [blend["mean"], blend["peak"],
			EnvChecks.BLEND_BUDGET], float(blend["mean"]) < EnvChecks.BLEND_BUDGET)

	# Measure second build speed against the tight 2.0 pace unit target.
	var second: Node3D = EnvRoom.new()
	second.doc = doc
	var t0 := Time.get_ticks_usec()
	root.add_child(second)
	var build_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var units := EnvChecks.build_units(build_ms)
	root.remove_child(second)
	second.free()
	print("  lighthouse_watchroom build speed: %.1f pace units (%d ms)" % [units, roundi(build_ms)])
	check("builds fast (< 2.0 pace units, got %.1f)" % units, units < 2.0)

	var meta: Dictionary = doc.get("room", {})
	check("metadata: name Lighthouse watchroom, category retreat, author Gemini 4 Neon Extra High",
			str(doc.get("name", "")) == "Lighthouse watchroom" and str(meta.get("category", "")) == "retreat"
			and str(meta.get("author", "")) == "Gemini 4 Neon Extra High")

	var dom: Node = host.system("room")
	check("domestic shell delegated to kit (no Floor/Walls/Ceiling/Window/Door)",
			str(dom.params["shell"]) == "kit" and room.get_node_or_null("Walls") == null
			and room.get_node_or_null("Floor") == null and room.get_node_or_null("Ceiling") == null
			and room.get_node_or_null("Window") == null and room.get_node_or_null("Door") == null)
	var kit: Node = host.system("watchroom")
	check("kit reports zero problems (%s)" % [kit.problems()], (kit.problems() as Array).is_empty())

	for n: String in ["PieceStatic", "PieceSoft", "PieceCove", "PieceLamps", "PieceGlass", "PieceClock",
			"PieceWindows", "LighthouseLensRig", "LighthouseLensBrass", "LighthouseLensCrystal", "LighthouseBeams",
			"AtlanticOcean", "HeadlandOutside", "ChannelBuoy", "RainPane", "Seats", "SkyDome", "SkyStars", "SkyMoon"]:
		check("room builds %s" % n, room.find_child(n, true, false) != null)

	# Verify opaque vs see-through shader discipline.
	for opaque_name: String in ["AtlanticOcean", "HeadlandOutside", "ChannelBuoy", "LighthouseLensBrass",
			"LighthouseLensCrystal"]:
		var mi := room.find_child(opaque_name, true, false) as MeshInstance3D
		check("%s is opaque (zero blend cost)" % opaque_name,
				mi != null and not EnvChecks.blends(mi.get_active_material(0)))
	for see_name: String in ["PieceGlass", "RainPane", "LighthouseBeams"]:
		var mi := room.find_child(see_name, true, false) as MeshInstance3D
		check("%s is in env_see_through" % see_name, mi != null and mi.is_in_group("env_see_through"))

	# Working ship's chronometer clock has live hands.
	var hands: Array = kit.clock_hands()
	check("aft ship chronometer clock reports live hour and minute hands (%s)" % [hands], hands.size() == 2)


## Hard user requirement: dead-centre head-on seat at x = 0.0, z = 0.0 facing -Z, and EVERY row has an odd seat count
## with a seat at x = 0.0 (zero centre aisle!).
func _dead_centre_seating(room: Node3D) -> void:
	var seats: Array[Transform3D] = room.room_seat_transforms()
	var seats_sys: Node = room.host.system_of_kind("seats")
	check("6 club_chair captain armchairs across 2 rows (%d seats, model %s)" % [seats.size(),
			str(seats_sys.params["model"])], seats.size() == 6 and str(seats_sys.params["model"]) == "club_chair")

	var has_origin_head_on := false
	var rows := {}
	for xf: Transform3D in seats:
		var fwd := (-xf.basis.z).normalized()
		if absf(xf.origin.x) < 0.001 and absf(xf.origin.z) < 0.001 and fwd.dot(Vector3.FORWARD) > 0.999:
			has_origin_head_on = true
		var rz := roundi(xf.origin.z * 100.0)
		var arr: Array = rows.get(rz, [])
		arr.append(xf.origin.x)
		rows[rz] = arr
	check("dead-centre head-on seat at x=0.0, z=0.0 facing -Z", has_origin_head_on)

	var all_odd_with_centre := not rows.is_empty()
	for rz: int in rows:
		var xs: Array = rows[rz]
		var has_zero := xs.any(func(x: float) -> bool: return absf(x) < 0.001)
		if xs.size() % 2 != 1 or not has_zero:
			all_odd_with_centre = false
	check("every row has an odd seat count with a seat at x=0.0 (rows: %s)" % [rows], all_odd_with_centre)


## Kit physics boxes stay >= 0.5 m clear of viewer origin (0, 0, 0); weather rain areas stay strictly outside the
## circular glazing cage; Sabine alpha fits the circular stone-and-glass tower box (0.05..0.75).
func _physics_and_acoustics(room: Node3D) -> void:
	var kit: Node = room.host.system("watchroom")
	var min_clearance := INF
	for sh: Array in kit.collision_shapes():
		var shape := sh[0] as BoxShape3D
		var xf: Transform3D = sh[1]
		if shape == null:
			continue
		var local_origin := xf.affine_inverse() * Vector3.ZERO
		var half := shape.size * 0.5
		var clamped := local_origin.clamp(-half, half)
		min_clearance = minf(min_clearance, local_origin.distance_to(clamped))
	check("every kit physics box is >= 0.5 m clear of viewer (0, 0, 0) (min %.2f m)" % min_clearance,
			min_clearance >= 0.5)

	# Verify every weather rain area box keeps outside the circular lantern glass (r = 5.55 m).
	var weather: Node = room.host.system_of_kind("atmosphere")
	var rain_outside := weather != null and not (weather.areas() as Array).is_empty()
	if rain_outside:
		for a: Array in weather.areas():
			var box: AABB = a[2]
			var cx := clampf(Lighthouse.CX, box.position.x, box.end.x)
			var cz := clampf(Lighthouse.CZ, box.position.z, box.end.z)
			var dist := Vector2(cx - Lighthouse.CX, cz - Lighthouse.CZ).length()
			if dist < Lighthouse.R_INNER + 0.25:
				rain_outside = false
	check("every outside storm rain area stays strictly outside the circular lantern glass", rain_outside)

	var sr: Dictionary = room.get_sound_room()
	var box: AABB = sr["box"]
	var s := box.size.abs()
	var v := s.x * s.y * s.z
	var area := 2.0 * (s.x * s.y + s.y * s.z + s.z * s.x)
	var alpha := 0.161 * v / (area * float(sr["rt60"]))
	print("  lighthouse_watchroom acoustics: box %s rt60 %.2f wet %.2f late %.2f Sabine alpha %.3f" % [s,
			float(sr["rt60"]), float(sr["wet"]), float(sr["late"]), alpha])
	check("Sabine mean absorption alpha in 0.05..0.75 (%.3f)" % alpha, alpha > 0.05 and alpha < 0.75)


## Settings (beam, storm, foghorn), ultra-comfort Fresnel rotation & Motion scaling, weather panes, and foghorn cues.
func _settings_and_cues(room: Node3D) -> void:
	var host: Node = room.host
	var kit: Node = host.system("watchroom")
	var sky: Node = host.system("sky")
	var weather: Node = host.system_of_kind("atmosphere")
	var foghorn: Node = host.system("foghorn")
	var rig := room.find_child("LighthouseLensRig", true, false) as Node3D
	var beams := room.find_child("LighthouseBeams", true, false) as MeshInstance3D
	var ocean := room.find_child("AtlanticOcean", true, false) as MeshInstance3D
	var buoy := room.find_child("ChannelBuoy", true, false) as MeshInstance3D

	# 1. Pre-show arrival: foghorn sounds on arrival, house lamps rise to 1.0, sweeping beam active & rotates gently.
	SoundFixture.finish_loading(room)
	host.snapshot_override = {"open": false}
	_steps(host, 4.0)
	check("preshow arrival: foghorn plays (%d), house lamps full (%.2f)" % [int(foghorn.plays),
			float(host.param("light.house_lamps"))],
			int(foghorn.plays) >= 1 and float(host.param("light.house_lamps")) > 0.95)

	var yaw0 := rig.rotation.y
	var oc0 := float(ocean.get_meta("clock", 0.0))
	_steps(host, 4.0, 0.2)
	var yaw1 := rig.rotation.y
	var oc1 := float(ocean.get_meta("clock", 0.0))
	var dyaw := wrapf(yaw1 - yaw0, -PI, PI)
	check("beam=sweeping rotates serenely at ~0.09 rad/s (delta %.3f rad in 4 s) with visible twin beams" % dyaw,
			beams.visible and absf(dyaw - Lighthouse.LENS_ROT_SPEED * 4.0) < 0.05
			and float(beams.get_meta("shaft_level", 0.0)) > 0.35)
	check("Atlantic ocean swells animate smoothly (delta %.2f) and buoy pulse < 3 Hz" % (oc1 - oc0),
			oc1 - oc0 > 2.5 and Lighthouse.BUOY_PULSE_HZ < 3.0 and buoy != null)

	# 2. Motion=0 freezes Fresnel lens rotation and ocean clock cleanly.
	host.set_setting("motion", 0.0)
	var yaw_m0 := rig.rotation.y
	var oc_m0 := float(ocean.get_meta("clock", 0.0))
	_steps(host, 2.0, 0.2)
	check("Motion=0 freezes Fresnel rotation (%.4f) and ocean swells (%.4f)" % [
			absf(rig.rotation.y - yaw_m0), absf(float(ocean.get_meta("clock", 0.0)) - oc_m0)],
			absf(rig.rotation.y - yaw_m0) < 0.0005 and absf(float(ocean.get_meta("clock", 0.0)) - oc_m0) < 0.0005)
	host.set_setting("motion", 1.0)

	# 3. beam=steady holds beam at fixed seaward off-axis bearing (~44 deg); beam=lantern hides cones & lifts dome cove.
	host.set_setting("beam", "steady")
	_steps(host, 6.0, 0.2)
	var steady_yaw := rig.rotation.y
	_steps(host, 2.0, 0.2)
	var steady_drift := absf(wrapf(rig.rotation.y - steady_yaw, -PI, PI))
	check("beam=steady holds seaward bearing %.1f deg (drift %.4f)" % [rad_to_deg(rig.rotation.y), steady_drift],
			beams.visible and absf(rad_to_deg(wrapf(rig.rotation.y - deg_to_rad(Lighthouse.BEAM_STEADY_YAW_DEG), -PI, PI))) < 2.0
			and steady_drift < 0.02)

	host.set_setting("beam", "lantern")
	_steps(host, 5.0, 0.2)
	var cove_lantern := float(kit.cove_state().get("glow", 0.0))
	check("beam=lantern hides volumetric cones (level %.3f) and warms dome cove (%.2f)" % [
			float(beams.get_meta("shaft_level", 1.0)), cove_lantern],
			not beams.visible and float(beams.get_meta("shaft_level", 1.0)) < 0.01 and cove_lantern > 1.35)
	host.set_setting("beam", "sweeping")
	_steps(host, 4.0, 0.2)

	# 4. storm setting: gale -> rain -> clear controls weather rain, pane_drift & sky clouds.
	host.set_setting("storm", "clear")
	_steps(host, 18.0, 0.5)
	check("storm=clear clears rain (%.2f), lowers clouds (%.2f) and zeroes pane_drift (%.2f)" % [
			weather.rain_amount(), float(sky.params["clouds"]), float(weather.params["pane_drift"])],
			weather.rain_amount() < 0.06 and float(sky.params["clouds"]) < 0.20
			and absf(float(weather.params["pane_drift"])) < 0.05)

	host.set_setting("storm", "rain")
	_steps(host, 18.0, 0.5)
	check("storm=rain sets steady light rain (%.2f) and moderate clouds (%.2f)" % [
			weather.rain_amount(), float(sky.params["clouds"])],
			weather.rain_amount() > 0.22 and weather.rain_amount() < 0.45 and float(sky.params["clouds"]) > 0.40)

	host.set_setting("storm", "gale")
	_steps(host, 18.0, 0.5)
	check("storm=gale drives heavy rain (%.2f), gale pane_drift (%.2f) and storm clouds (%.2f)" % [
			weather.rain_amount(), float(weather.params["pane_drift"]), float(sky.params["clouds"])],
			weather.rain_amount() > 0.85 and float(weather.params["pane_drift"]) > 1.2
			and float(sky.params["clouds"]) > 0.68)

	# 5. foghorn setting (regular / rare / off): scales level smoothly and mutes cue triggers when off.
	host.set_setting("foghorn", "off")
	_steps(host, 6.0, 0.25)
	var plays_off := int(foghorn.plays)
	host.do_action("foghorn.play", {})
	check("foghorn=off drops level to 0 (%.3f) and blocks cue play (%d == %d)" % [
			float(foghorn.params["level"]), int(foghorn.plays), plays_off],
			float(foghorn.params["level"]) < 0.01 and int(foghorn.plays) == plays_off)

	host.set_setting("foghorn", "rare")
	_steps(host, 6.0, 0.25)
	check("foghorn=rare lowers horn level to distant 0.42 (%.2f)" % float(foghorn.params["level"]),
			absf(float(foghorn.params["level"]) - 0.42) < 0.03)

	host.set_setting("foghorn", "regular")
	_steps(host, 6.0, 0.25)
	var plays_reg := int(foghorn.plays)
	host.do_action("foghorn.play", {})
	check("foghorn=regular restores full level (%.2f) and plays on cue (%d -> %d)" % [
			float(foghorn.params["level"]), plays_reg, int(foghorn.plays)],
			float(foghorn.params["level"]) > 0.96 and int(foghorn.plays) == plays_reg + 1)

	# 6. Starting ritual & ended cues: foghorn sounds on film start & end, lamps dim to 0.20 while cove_floor holds!
	var before_start := int(foghorn.plays)
	host.snapshot_override = {"open": true, "playing": true, "position": 0.5, "duration": 7200.0}
	_steps(host, 10.0)
	var cove_film := float(kit.cove_state().get("glow", 0.0))
	check("starting ritual: foghorn sounds (%d -> %d), house lamps dim (%.2f), cove_floor holds (%.2f)" % [
			before_start, int(foghorn.plays), float(host.param("light.house_lamps")), cove_film],
			int(foghorn.plays) >= before_start + 1 and absf(float(host.param("light.house_lamps")) - 0.20) < 0.02
			and cove_film > 0.35)

	var before_end := int(foghorn.plays)
	host.snapshot_override = {"open": true, "playing": false, "ended": true, "position": 7200.0, "duration": 7200.0}
	_steps(host, 6.0)
	check("ended cue: foghorn sounds (%d -> %d) and lamps rise back to 1.0 (%.2f)" % [
			before_end, int(foghorn.plays), float(host.param("light.house_lamps"))],
			int(foghorn.plays) >= before_end + 1 and float(host.param("light.house_lamps")) > 0.95)
	host.snapshot_override = {"open": false}


## Sound beds: ocean_surf, rain_glass (follows weather.rain), wind (follows storm), foghorn (follows foghorn).
func _sound(room: Node3D) -> void:
	RoomSound.check_beds(self, "lighthouse_watchroom", room, {
		"ocean": "ocean_surf", "rain": "rain_glass", "wind": "wind", "foghorn": "foghorn",
	}, "hull")
	RoomSound.check_follows(self, "lighthouse_watchroom", room, "rain", "weather.rain")


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
		print("  part %-24s %2d draws %7d triangles" % r)


## Renders 10 lavapipe PNGs into ENV_SHOTS covering: centre seat front view (gale), looking up at the brass Fresnel
## lens & sweeping beam, port chart desk & storm sea, port-forward brass telescope & harbour buoy, starboard barometer
## & rain panes, aft spiral stair hatch & chronometer clock, exterior catwalk & Atlantic headland, clear moonlit sea,
## warm dome lantern mode, and film playing.
func _render(doc: Dictionary) -> void:
	if not RoomRender.has_renderer():
		print("SKIP render (headless)")
		return
	var sc: Array = doc["screen"]["center"]
	var screen := Vector3(float(sc[0]), float(sc[1]), float(sc[2]))
	var eye := Vector3(0.0, 1.2, 0.0)

	# --- Phase 1: Atlantic Gale Pre-show (sweeping Fresnel beam, storm rain panes, warm oil lanterns) ---
	RoomRender.set_light(screen, float(doc["room"]["ambient"]))
	var vc := await RoomRender.open(self, doc, 90.0)
	var room := vc[2] as Node3D
	var host: Node = room.host
	SoundFixture.finish_loading(room)
	RenderingServer.global_shader_parameter_set("screen_glow", 0.0)
	host.snapshot_override = {"open": false}
	host.set_setting("storm", "gale")
	host.set_setting("beam", "sweeping")
	_steps(host, 6.0, 0.2)

	# 1. Dead-centre front seat view toward twin-stanchion screen, diamond storm glass & sweeping golden Fresnel beam.
	await RoomRender.shot(self, vc, eye, screen, "lw_01_seat_front_gale")
	# 2. Looking up from centre seat at the rotating brass-and-crystal Fresnel drum, copper ribs & sweeping twin beams.
	await RoomRender.shot(self, vc, Vector3(0.0, 1.2, 0.65), Vector3(0.9, 5.2, -1.6), "lw_02_up_fresnel_beam")
	# 3. Port watchkeeper chart desk (sea chart, sextant, storm lantern, speaking tube) & dark Atlantic swells.
	(vc[1] as Camera3D).fov = 82.0
	await RoomRender.shot(self, vc, Vector3(-1.4, 1.42, 0.25), Vector3(-5.0, 1.05, -0.35), "lw_03_port_chart_desk")
	# 4. Port-forward brass telescope on mahogany tripod aimed out through storm glass at distant sea stacks & buoy.
	await RoomRender.shot(self, vc, Vector3(-1.5, 1.58, -0.7), Vector3(-5.0, 0.65, -4.4), "lw_04_telescope_sea")
	# 5. Starboard barometer station, signal locker, coiled hemp rope, rain-streaked panes & moonlit Atlantic coast.
	await RoomRender.shot(self, vc, Vector3(1.1, 1.42, 0.2), Vector3(5.2, 1.42, -0.7), "lw_05_starboard_barometer")
	# 6. Aft circular spiral-stair floor hatch, gleaming brass handrail loop, club chairs & ship's chronometer clock.
	(vc[1] as Camera3D).fov = 86.0
	await RoomRender.shot(self, vc, Vector3(-0.7, 1.55, 0.6), Vector3(0.15, 1.05, 5.2), "lw_06_aft_stair_clock")
	# 7. Looking down & seaward across the watchroom sill, exterior iron catwalk, basalt cliffs, sea stacks & Atlantic swells.
	(vc[1] as Camera3D).fov = 88.0
	await RoomRender.shot(self, vc, Vector3(2.9, 1.95, -2.5), Vector3(9.2, -9.2, -14.0), "lw_07_ocean_catwalk")

	# --- Phase 2: Clear Moonlit Sea (storm=clear, bright silver Moon, starry sky, dry crisp glass, steady beam) ---
	host.set_setting("storm", "clear")
	host.set_setting("beam", "steady")
	_steps(host, 20.0, 0.5)
	(vc[1] as Camera3D).fov = 90.0
	await RoomRender.shot(self, vc, eye, Vector3(1.4, 2.55, -4.55), "lw_08_clear_moonlit")

	# --- Phase 3: Warm Dome Lantern Glow (beam=lantern, no outward beam cones, rich warm ribbed copper dome) ---
	host.set_setting("beam", "lantern")
	_steps(host, 6.0, 0.25)
	await RoomRender.shot(self, vc, Vector3(0.0, 1.25, 1.4), Vector3(0.0, 3.85, -3.5), "lw_09_lantern_dome_glow")

	# --- Phase 4: Film Playing in Atlantic Gale (house lamps dimmed to 0.20, warm sill cove, screen spill, beam clear) ---
	RoomRender.set_light(screen, 0.020)
	RenderingServer.global_shader_parameter_set("screen_glow", 1.0)
	host.snapshot_override = {"open": true, "playing": true, "position": 1800.0, "duration": 7200.0}
	host.signals.fake("film.brightness", 0.72)
	host.signals.fake("film.colour", Color(0.82, 0.60, 0.36))
	host.signals.fake("playback.playing", 1.0)
	host.set_setting("storm", "gale")
	host.set_setting("beam", "sweeping")
	_steps(host, 18.0, 0.5)
	await RoomRender.shot(self, vc, eye, screen, "lw_10_film_playing")

	await RoomRender.close(self, vc)
