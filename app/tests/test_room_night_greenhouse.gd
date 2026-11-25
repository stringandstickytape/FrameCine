extends "res://tests/env_builder_harness.gd"

## Greenhouse at night (app/environments/night_greenhouse.env.json; docs/environments/rooms/night_greenhouse.md):
## a lush Victorian wrought-iron & ribbed-glass barrel-vault conservatory in the midnight rain, brimming with warm-lit
## palms, sword ferns, elephant-ear foliage, climbing ivy, dwarf lemon & tangerine trees, cedar potting benches,
## terracotta pots, glass bell cloches, brass watering can, hanging fern baskets, and a trickling circular stone
## fountain. Verifies schema, tight budgets, atlas <= 1024, blend overdraw < 1.0, build speed < 2.0 units, dead-centre
## head-on seating invariant, zero rain inside, physics clearance, Sabine acoustics, all live settings (rain, lamps,
## mist), motion scaling, cues, and audio levels. Under lavapipe, renders 10 PNGs into ENV_SHOTS.
## godot --headless --xr-mode off --path app --script res://tests/test_room_night_greenhouse.gd

const RoomRender := preload("res://tests/room_render.gd")
const RoomSound := preload("res://tests/room_sound.gd")
const SoundFixture := preload("res://tests/env_sound_fixture.gd")
const NightGreenhouse := preload("res://scripts/env/systems/kit/night_greenhouse.gd")
const DOC := "res://environments/night_greenhouse.env.json"


func run_tests() -> void:
	test_name = "test_room_night_greenhouse"
	var r := EnvDoc.load_file(DOC)
	check("the document reads without schema errors (%s)" % [r["errors"]], (r["errors"] as Array).is_empty())
	var doc: Dictionary = r["doc"]
	if doc.is_empty():
		return
	if OS.get_environment("NG_RENDER_ONLY") == "":
		var room := await check_room("night_greenhouse", doc)
		room.host.auto = false
		_by_part(room)
		await _built_and_budgets(room, doc)
		_dead_centre_seating(room)
		_zero_rain_inside(room)
		_physics_and_acoustics(room)
		await _settings_and_cues(room)
		_sound(room)
		await done(room)
		await RoomSound.check_level(self, self, "night_greenhouse", doc)
	await _render(doc)


## Tight budgets, atlas size, blend overdraw, build speed, metadata and expected scene nodes.
func _built_and_budgets(room: Node3D, doc: Dictionary) -> void:
	var host: Node = room.host
	var stats := EnvChecks.measure(room)
	print("  night_greenhouse figures: %s" % [stats])
	check("tight budget: <= 34 draws, <= 90k tris, 0 live lights, <= 12 MB tex, <= 4k particles (%s)" % [stats],
			int(stats["draws"]) <= 34 and int(stats["triangles"]) <= 90000 and int(stats["lights"]) == 0
			and float(stats["texture_mb"]) <= 12.0 and int(stats["particles"]) <= 4000)

	# Lightmap atlas size hint <= 1024x1024 on every static mesh.
	var statics: Array[MeshInstance3D] = room.static_meshes()
	var max_atlas := Vector2i.ZERO
	for mi in statics:
		if mi.mesh is ArrayMesh:
			max_atlas = max_atlas.max((mi.mesh as ArrayMesh).lightmap_size_hint)
	print("  night_greenhouse static atlas: %s (%d static meshes)" % [max_atlas, statics.size()])
	check("lightmap atlas <= 1024x1024 (%s)" % max_atlas,
			not statics.is_empty() and max_atlas.x > 0 and max_atlas.x <= 1024 and max_atlas.y <= 1024)

	# Blend layers strictly < 1.0 in default steady rain.
	var blend: Dictionary = await EnvChecks.blend_layers(self, room)
	print("  night_greenhouse blend_layers (steady rain): %s" % [blend])
	check("blended layers < 1.0 in steady rain (mean %.2f, peak %d)" % [blend["mean"], blend["peak"]],
			float(blend["mean"]) < EnvChecks.BLEND_BUDGET)

	# Second build speed < 2.0 pace units.
	var second: Node3D = EnvRoom.new()
	second.doc = doc
	var t0 := Time.get_ticks_usec()
	root.add_child(second)
	var build_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var units := EnvChecks.build_units(build_ms)
	root.remove_child(second)
	second.free()
	print("  night_greenhouse build speed: %.1f pace units (%d ms)" % [units, roundi(build_ms)])
	check("builds within 2.0 pace units (%.1f < 2.0)" % units, units < 2.0)

	var meta: Dictionary = doc.get("room", {})
	var room_name := str(doc.get("name", ""))
	check("metadata: Greenhouse at night, retreat, Gemini 4 Neon Extra High, no apostrophes",
			room_name == "Greenhouse at night" and not room_name.contains("'")
			and str(meta.get("category", "")) == "retreat"
			and str(meta.get("author", "")) == "Gemini 4 Neon Extra High"
			and str(meta.get("description", "")).length() <= 200)

	var dom: Node = host.system("room")
	check("domestic shell delegated to kit (no Floor/Walls/Ceiling/Window/Door)",
			str(dom.params["shell"]) == "kit" and room.get_node_or_null("Walls") == null
			and room.get_node_or_null("Floor") == null and room.get_node_or_null("Ceiling") == null
			and room.get_node_or_null("Window") == null and room.get_node_or_null("Door") == null)
	var kit: Node = host.system("kit")
	check("kit reports zero problems (%s)" % [kit.problems()], (kit.problems() as Array).is_empty())

	for n: String in ["PieceStatic", "PieceSoft", "PieceCove", "PieceLamps", "PieceGlass", "PieceWater",
			"GreenhouseGarden", "GreenhouseRoofGlass", "GreenhouseMoonShafts", "Seats", "SkyDome", "SkyStars",
			"SkyMoon", "RainPane", "Fog"]:
		check("room builds %s" % n, room.find_child(n, true, false) != null)

	# Verify opaque vs see-through shader discipline.
	for opaque_name: String in ["GreenhouseGarden", "PieceWater"]:
		var mi := room.find_child(opaque_name, true, false) as MeshInstance3D
		check("%s is opaque (zero blend cost)" % opaque_name,
				mi != null and not EnvChecks.blends(mi.get_active_material(0)))
	for see_name: String in ["PieceGlass", "GreenhouseRoofGlass", "GreenhouseMoonShafts", "RainPane"]:
		var mi := room.find_child(see_name, true, false) as MeshInstance3D
		check("%s is in env_see_through" % see_name, mi != null and mi.is_in_group("env_see_through"))


## HARD REQUIREMENT: dead-centre seat at x = 0.0, z = 0.0 facing -Z head-on, and EVERY row has an odd seat count with
## a seat at x = 0.0 (zero centre aisle!).
func _dead_centre_seating(room: Node3D) -> void:
	var host: Node = room.host
	var seats: Array[Transform3D] = room.room_seat_transforms()
	check("6 vintage sage-linen director chairs across 2 rows (%d seats)" % seats.size(),
			seats.size() == 6 and str(host.system("seats").params["model"]) == "director")

	var found_origin := false
	var rows := {}
	for xf: Transform3D in seats:
		var z_key := roundi(xf.origin.z * 100.0)
		if not rows.has(z_key):
			rows[z_key] = []
		(rows[z_key] as Array).append(xf)
		if absf(xf.origin.x) < 0.001 and absf(xf.origin.z) < 0.001:
			var forward := -xf.basis.z
			if forward.dot(Vector3.FORWARD) > 0.999:
				found_origin = true
	check("dead-centre head-on seat at (0.0, 0.0, 0.0) facing -Z", found_origin)

	var all_rows_odd_and_centred := not rows.is_empty()
	for z_key: int in rows:
		var row: Array = rows[z_key]
		var has_centre := row.any(func(t: Transform3D) -> bool: return absf(t.origin.x) < 0.001)
		if row.size() % 2 != 1 or not has_centre:
			all_rows_odd_and_centred = false
	check("every row has odd seat count and a dead-centre x = 0.0 seat (rows: %d)" % rows.size(),
			all_rows_odd_and_centred)


## Verify EVERY weather rain area (including its full wind-drift envelope!) stays strictly OUTSIDE the conservatory!
func _zero_rain_inside(room: Node3D) -> void:
	var wsys: Node = room.host.system("weather")
	check("weather system present with exterior rain areas", wsys != null and not (wsys.areas() as Array).is_empty())
	if wsys == null:
		return
	var wv: Array = wsys.params["wind"]
	var wind := Vector3(float(wv[0]), 0.0, float(wv[1]))
	var interior := AABB(
		Vector3(-NightGreenhouse.HW, -0.5, NightGreenhouse.FRONT_APSE_Z),
		Vector3(NightGreenhouse.HW * 2.0, 10.0, NightGreenhouse.BACK_Z - NightGreenhouse.FRONT_APSE_Z)
	)
	var leaks := 0
	for a: Array in wsys.areas():
		var box: AABB = a[2]
		var life := box.size.y / 7.5
		var half_drift := Vector3(absf(wind.x) * life * 0.5, 0.0, absf(wind.z) * life * 0.5)
		var swept := AABB(box.position - half_drift, box.size + half_drift * 2.0)
		if swept.intersects(interior):
			leaks += 1
	check("zero rain inside conservatory (all %d exterior boxes clear of interior after wind drift)" %
			(wsys.areas() as Array).size(), leaks == 0)


## Kit physics boxes stay >= 0.5 m clear of viewer origin (0, 0, 0); Sabine alpha fits warm glass conservatory.
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
		min_clearance = minf(min_clearance, local_origin.distance_to(clamped))
	check("every kit physics box >= 0.5 m clear of viewer (0, 0, 0) (min %.2f m)" % min_clearance,
			min_clearance >= 0.5)

	var sr: Dictionary = room.get_sound_room()
	var box: AABB = sr["box"]
	var s := box.size.abs()
	var v := s.x * s.y * s.z
	var area := 2.0 * (s.x * s.y + s.y * s.z + s.z * s.x)
	var alpha := 0.161 * v / (area * float(sr["rt60"]))
	print("  night_greenhouse acoustics: box %s rt60 %.2f wet %.2f Sabine alpha %.3f" % [s, float(sr["rt60"]),
			float(sr["wet"]), alpha])
	check("Sabine mean absorption alpha in 0.05..0.75 (%.3f)" % alpha, alpha > 0.05 and alpha < 0.75)


## Live settings (rain, lamps, mist), moonbeam shafts & blend check in clear mode, motion scaling, and film cues.
func _settings_and_cues(room: Node3D) -> void:
	var host: Node = room.host
	var kit: Node = host.system("kit")
	var sky: Node = host.system("sky")
	var wsys: Node = host.system("weather")
	var atmos: Node = host.system("atmosphere")
	var roof_mi := room.find_child("GreenhouseRoofGlass", true, false) as MeshInstance3D
	var shaft_mi := room.find_child("GreenhouseMoonShafts", true, false) as MeshInstance3D

	# 1. Steady midnight rain pre-show defaults.
	SoundFixture.finish_loading(room)
	host.snapshot_override = {"open": false}
	_steps(host, 4.0)
	check("steady rain default: heavy mode, roof rain glass visible, moon shafts hidden",
			str(wsys.params["mode"]) == "heavy" and roof_mi.visible and not shaft_mi.visible
			and float(sky.params["clouds"]) > 0.75)

	# 2. Switch rain -> clear: sky clears, moon brightens, subtle moonbeam shafts bloom (and blend stays < 1.0!).
	host.set_setting("rain", "clear")
	_steps(host, 20.0, 0.5)
	check("rain=clear: weather mode clear, sky clears (clouds %.2f, moon %.2f), moonbeam shafts bloom (%.2f)" % [
			float(sky.params["clouds"]), float(sky.params["moon"]), float(shaft_mi.get_meta("moon_shaft_level", 0.0))],
			str(wsys.params["mode"]) == "clear" and float(sky.params["clouds"]) < 0.20
			and float(sky.params["moon"]) > 0.90 and shaft_mi.visible
			and float(shaft_mi.get_meta("moon_shaft_level", 0.0)) > 0.16)
	var blend_clear: Dictionary = await EnvChecks.blend_layers(self, room)
	print("  night_greenhouse blend_layers (clear moonlit): %s" % [blend_clear])
	check("blended layers < 1.0 in clear moonlit mode (mean %.2f, peak %d)" % [blend_clear["mean"], blend_clear["peak"]],
			float(blend_clear["mean"]) < EnvChecks.BLEND_BUDGET)

	# Motion setting scales moonbeam shaft drift cleanly (0 freezes it).
	var c0 := float(shaft_mi.get_meta("clock", 0.0))
	_steps(host, 2.0)
	var c1 := float(shaft_mi.get_meta("clock", 0.0))
	host.set_setting("motion", 0.0)
	_steps(host, 2.0)
	var c2 := float(shaft_mi.get_meta("clock", 0.0))
	check("moonbeam wisps drift with Motion (%.2f) and hold at Motion 0 (%.3f)" % [c1 - c0, c2 - c1],
			c1 - c0 > 1.0 and absf(c2 - c1) < 0.001)
	host.set_setting("motion", 1.0)

	# Drizzle intermediate state & back to steady.
	host.set_setting("rain", "drizzle")
	_steps(host, 4.0)
	check("rain=drizzle sets weather mode light", str(wsys.params["mode"]) == "light")
	host.set_setting("rain", "steady")
	_steps(host, 6.0)

	# 3. Lamps setting: warm_brass -> botanical emerald -> dim.
	host.set_setting("lamps", "botanical")
	_steps(host, 5.0)
	var bot_st: Dictionary = kit.cove_state()
	var bot_col: Color = bot_st.get("colour", Color.BLACK)
	check("lamps=botanical shifts cove uplight to lush emerald-jade (%s, glow %.2f)" % [bot_col, float(bot_st.get("glow", 0.0))],
			bot_col.g > bot_col.r * 1.8 and float(bot_st.get("glow", 0.0)) > 1.0)

	host.set_setting("lamps", "dim")
	_steps(host, 5.0)
	var dim_st: Dictionary = kit.cove_state()
	check("lamps=dim lowers cove glow to hushed level (%.2f)" % float(dim_st.get("glow", 9.0)),
			float(dim_st.get("glow", 9.0)) < 0.55)

	host.set_setting("lamps", "warm_brass")
	_steps(host, 5.0)
	var warm_st: Dictionary = kit.cove_state()
	var warm_col: Color = warm_st.get("colour", Color.BLACK)
	check("lamps=warm_brass restores warm amber glow (%s)" % warm_col, warm_col.r > warm_col.b * 1.8)

	# 4. Mist setting: lush -> light -> clear.
	host.set_setting("mist", "clear")
	_steps(host, 5.0)
	check("mist=clear hides conservatory fog (%.3f)" % float(atmos.params["fog"]),
			float(atmos.params["fog"]) < 0.01 and not atmos.fog_node().visible)
	host.set_setting("mist", "lush")
	_steps(host, 5.0)
	check("mist=lush restores warm conservatory fog (%.2f)" % float(atmos.params["fog"]),
			float(atmos.params["fog"]) > 0.35 and atmos.fog_node().visible)

	# 5. Film cues: playing dims house lamps to 0.24 while cove_floor keeps subtle glow; ended returns lamps to 1.0.
	host.snapshot_override = {"open": true, "playing": true, "position": 60.0, "duration": 7200.0}
	_steps(host, 8.0)
	var film_cove: Dictionary = kit.cove_state()
	check("playing cue dims house lamps to 0.24 (%.2f) while cove floor holds (%.2f)" % [
			float(host.param("light.house_lamps")), float(film_cove.get("glow", 0.0))],
			absf(float(host.param("light.house_lamps")) - 0.24) < 0.03 and float(film_cove.get("glow", 0.0)) > 0.22)

	host.snapshot_override = {"open": true, "playing": false, "ended": true, "position": 7200.0, "duration": 7200.0}
	_steps(host, 8.0)
	check("ended cue returns conservatory lamps to 1.0 (%.2f)" % float(host.param("light.house_lamps")),
			float(host.param("light.house_lamps")) > 0.95)
	host.snapshot_override = {"open": false}
	host.signals.clear_fakes()


## Sound beds: rain_glass (follows weather.rain), drips, fountain, crickets (when clear), wind on small_room acoustics.
func _sound(room: Node3D) -> void:
	RoomSound.check_beds(self, "night_greenhouse", room, {
		"rain": "rain_glass", "drips": "drips", "fountain": "fountain",
		"crickets": "crickets", "wind": "wind",
	}, "small_room")
	RoomSound.check_follows(self, "night_greenhouse", room, "rain", "weather.rain")

	# Crickets sound faintly when clear (weather.rain == 0) and hush during steady rain (weather.rain == 1).
	var h: Node = room.host
	var cr: Node = h.system("crickets")
	h.signals.fake("weather.rain", 1.0)
	_steps(h, 15.0)
	var lvl_rain := float(cr.params["level"])
	h.signals.fake("weather.rain", 0.0)
	_steps(h, 15.0)
	var lvl_clear := float(cr.params["level"])
	h.signals.clear_fakes()
	check("crickets hush in steady rain (%.2f) and sing when clear (%.2f)" % [lvl_rain, lvl_clear],
			lvl_rain < 0.02 and lvl_clear > 0.75)


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
		elif g is GPUParticles3D:
			stats = {"draws": 1, "triangles": (g as GPUParticles3D).amount * 2}
		if not stats.is_empty():
			rows.append([str(g.name), stats["draws"], stats["triangles"]])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return int(a[2]) > int(b[2]))
	for r: Array in rows:
		print("  part %-22s %2d draws %7d triangles" % r)


## Renders 10 lavapipe PNGs into ENV_SHOTS covering every view, mood & detail required for visual self-inspection!
func _render(doc: Dictionary) -> void:
	if not RoomRender.has_renderer():
		print("SKIP render (headless)")
		return
	var sc: Array = doc["screen"]["center"]
	var screen := Vector3(float(sc[0]), float(sc[1]), float(sc[2]))
	var eye := Vector3(0.0, 1.2, 0.0)

	# --- Phase 1: Steady Midnight Rain + Warm Brass Lamps Pre-show ---
	RoomRender.set_light(screen, 0.055)
	var vc := await RoomRender.open(self, doc, 88.0)
	var room := vc[2] as Node3D
	var host: Node = room.host
	SoundFixture.finish_loading(room)
	RenderingServer.global_shader_parameter_set("screen_glow", 0.25)
	host.snapshot_override = {"open": false}
	host.set_setting("rain", "steady")
	host.set_setting("lamps", "warm_brass")
	host.set_setting("mist", "lush")
	_steps(host, 6.0, 0.25)

	# 1. Centre seat front view toward Victorian botanical trellis screen, palms, fountain & quarry tiles.
	await RoomRender.shot(self, vc, eye, screen, "greenhouse_seat_steady")
	# 2. Looking straight up through kentia palms & hanging brass fern baskets at the rain-streaked glass vault!
	(vc[1] as Camera3D).fov = 92.0
	await RoomRender.shot(self, vc, Vector3(0.0, 1.25, -0.4), Vector3(0.4, 6.4, -3.2), "greenhouse_up_vault")
	# 3. Port slatted cedar potting bench, terracotta pots, glass bell cloches, coiled brass watering can & lemon tree.
	(vc[1] as Camera3D).fov = 72.0
	await RoomRender.shot(self, vc, Vector3(-1.35, 1.55, 0.85), Vector3(-4.85, 1.05, -0.75), "greenhouse_port_bench")
	# 4. Starboard foliage, circular stone drip fountain basin, fan palm, tangerine tree & rain-beaded panes.
	await RoomRender.shot(self, vc, Vector3(-0.35, 1.50, -1.65), Vector3(4.10, 1.15, -4.55),
			"greenhouse_starboard_fountain")
	# 5. Aft Victorian double glass-and-iron conservatory doors, brass handles, rose-fan gable & cast-iron potting table.
	(vc[1] as Camera3D).fov = 82.0
	await RoomRender.shot(self, vc, Vector3(-0.25, 1.45, -0.60), Vector3(0.45, 1.85, 6.20), "greenhouse_aft_doors")
	# 6. Closer forward look at the arched sage-green wrought-iron botanical trellis, climbing ivy & curved apse.
	(vc[1] as Camera3D).fov = 76.0
	await RoomRender.shot(self, vc, Vector3(0.0, 1.55, -2.65), Vector3(0.0, 2.75, -8.20), "greenhouse_close_trellis")
	# 7. Elevated interior corner overview showing checkerboard quarry tiles, heating grate, 6 director chairs & vault.
	(vc[1] as Camera3D).fov = 86.0
	await RoomRender.shot(self, vc, Vector3(-1.95, 3.35, 5.45), Vector3(0.35, 1.30, -4.60), "greenhouse_overview")

	# --- Phase 2: Clear Moonlit Midnight (rain=clear, starry sky, Moon & subtle moonbeam shafts!) ---
	(vc[1] as Camera3D).fov = 88.0
	host.set_setting("rain", "clear")
	host.set_setting("mist", "light")
	host.signals.fake("weather.rain", 0.0)
	host.signals.fake("weather.wet", 0.0)
	_steps(host, 24.0, 0.5)
	host.signals.clear_fakes()
	# 8. Clear moonlit conservatory looking forward-up toward the Moon, stars & slanting silver moonbeams!
	await RoomRender.shot(self, vc, Vector3(-0.6, 1.25, 0.4), Vector3(1.1, 3.25, -7.8), "greenhouse_clear_moonlight")

	# --- Phase 3: Botanical Emerald Uplight Mood (lamps=botanical, steady rain) ---
	host.set_setting("rain", "steady")
	host.set_setting("lamps", "botanical")
	host.set_setting("mist", "lush")
	_steps(host, 8.0, 0.25)
	# 9. Botanical emerald uplight mood bathing the tropical palms, ferns, citrus trees & coves!
	await RoomRender.shot(self, vc, eye, screen, "greenhouse_botanical_emerald")

	# --- Phase 4: Film Playing (warm brass, dimmed house lamps, cove floor, warm cinema spill) ---
	RoomRender.set_light(screen, 0.020)
	RenderingServer.global_shader_parameter_set("screen_glow", 1.0)
	host.set_setting("lamps", "warm_brass")
	host.snapshot_override = {"open": true, "playing": true, "position": 900.0, "duration": 7200.0}
	host.signals.fake("film.brightness", 0.72)
	host.signals.fake("film.colour", Color(0.92, 0.62, 0.34))
	host.signals.fake("playback.playing", 1.0)
	_steps(host, 10.0, 0.25)
	# 10. Film playing view from the dead-centre director's chair!
	await RoomRender.shot(self, vc, eye, screen, "greenhouse_film_playing")

	await RoomRender.close(self, vc)
