extends "res://tests/env_builder_harness.gd"

## Snowed-in cabin (app/environments/snowed_in_cabin.env.json; docs/environments/rooms/snowed_in_cabin.md):
## a steep alpine timber A-frame chalet snowed in on a moonlit winter night in the Cozy retreats category.
## Verified headless against every shipped room check (schema, tight budgets, lightmap atlas <= 1024x1024,
## blend overdraw < 1.0, build speed < 2.0 pace units, sight line from every seat, dead-centre head-on seat in
## every row with odd seat count, outside-only snowfall envelopes, Sabine acoustics, audio levels, settings,
## cues & comfort), and under lavapipe renders 10 PNGs into ENV_SHOTS.
## godot --headless --xr-mode off --path app --script res://tests/test_room_snowed_in_cabin.gd

const RoomRender := preload("res://tests/room_render.gd")
const RoomSound := preload("res://tests/room_sound.gd")
const SoundFixture := preload("res://tests/env_sound_fixture.gd")
const SnowedInCabin := preload("res://scripts/env/systems/kit/snowed_in_cabin.gd")
const DOC := "res://environments/snowed_in_cabin.env.json"


func run_tests() -> void:
	test_name = "test_room_snowed_in_cabin"
	var r := EnvDoc.load_file(DOC)
	check("the document reads without schema errors (%s)" % [r["errors"]], (r["errors"] as Array).is_empty())
	var doc: Dictionary = r["doc"]
	if doc.is_empty():
		return
	if OS.get_environment("SC_RENDER_ONLY") == "":
		var room := await check_room("snowed_in_cabin", doc)
		room.host.auto = false
		_by_part(room)
		await _built_and_budgets(room, doc)
		_dead_centre_seats(room)
		_physics_weather_and_acoustics(room)
		_settings_and_cues(room)
		_sound(room)
		await done(room)
		await RoomSound.check_level(self, self, "snowed_in_cabin", doc)
	await _render(doc)


## Tight budgets, lightmap atlas <= 1024x1024, blend overdraw < 1.0, build speed < 2.0 units, metadata & scene nodes.
func _built_and_budgets(room: Node3D, doc: Dictionary) -> void:
	var host: Node = room.host
	var stats := EnvChecks.measure(room)
	print("  snowed_in_cabin figures: %s" % [stats])
	check("tight budget: <= 34 draws, <= 90k tris, 0 live lights, <= 12.0 MB textures (%s)" % [stats],
			int(stats["draws"]) <= 34 and int(stats["triangles"]) <= 90000 and int(stats["lights"]) == 0
			and float(stats["texture_mb"]) <= 12.0)

	var static_mi := room.find_child("PieceStatic", true, false) as MeshInstance3D
	var atlas := static_mi.mesh.lightmap_size_hint if (static_mi != null and static_mi.mesh != null) else Vector2i(9999, 9999)
	print("  snowed_in_cabin lightmap atlas: %dx%d" % [atlas.x, atlas.y])
	check("static lightmap atlas <= 1024x1024 (%dx%d)" % [atlas.x, atlas.y], atlas.x <= 1024 and atlas.y <= 1024)

	var blend: Dictionary = await EnvChecks.blend_layers(self, room)
	print("  snowed_in_cabin blend_layers: %s" % [blend])
	check("blended layers strictly < 1.0 (mean %.2f, peak %d)" % [blend["mean"], blend["peak"]],
			float(blend["mean"]) < 1.0)

	# Measure second build speed against the tight 2.0 pace-unit budget.
	var second: Node3D = EnvRoom.new()
	second.doc = doc
	var t0 := Time.get_ticks_usec()
	root.add_child(second)
	var build_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var units := EnvChecks.build_units(build_ms)
	root.remove_child(second)
	second.free()
	print("  snowed_in_cabin build speed: %.1f pace units (%d ms)" % [units, roundi(build_ms)])
	check("builds within 2.0 pace units (%.1f < 2.0)" % units, units < 2.0)

	var meta: Dictionary = doc.get("room", {})
	var room_name := str(doc.get("name", ""))
	check("metadata: name Snowed-in cabin (no apostrophe), category retreat, author Gemini 4 Neon Extra High",
			room_name == "Snowed-in cabin" and not room_name.contains("'")
			and str(meta.get("category", "")) == "retreat"
			and str(meta.get("author", "")) == "Gemini 4 Neon Extra High")

	var dom: Node = host.system("room")
	check("domestic shell delegated to kit (no Floor/Walls/Ceiling/Window/Door)",
			str(dom.params["shell"]) == "kit" and room.get_node_or_null("Walls") == null
			and room.get_node_or_null("Floor") == null and room.get_node_or_null("Ceiling") == null
			and room.get_node_or_null("Window") == null and room.get_node_or_null("Door") == null)
	var kit: Node = host.system("chalet")
	check("kit reports zero problems (%s)" % [kit.problems()], (kit.problems() as Array).is_empty())

	for n: String in ["PieceStatic", "PieceSoft", "PieceCove", "PieceLamps", "PieceGlass",
			"AlpineOutside", "HearthGlow", "HearthShaft", "Seats", "SeatEnds",
			"SkyDome", "SkyStars", "SkyMoon", "Fall0", "Fall1"]:
		check("room builds %s" % n, room.find_child(n, true, false) != null)

	var out_mi := room.find_child("AlpineOutside", true, false) as MeshInstance3D
	check("AlpineOutside is opaque (zero blend cost)",
			out_mi != null and not EnvChecks.blends(out_mi.get_active_material(0)))
	for see_name: String in ["HearthGlow", "HearthShaft"]:
		var mi := room.find_child(see_name, true, false) as MeshInstance3D
		check("%s is in env_see_through" % see_name, mi != null and mi.is_in_group("env_see_through"))
	check("low cedar coffee table top <= 0.44 m (%.2f m)" % SnowedInCabin.TABLE_TOP_Y,
			SnowedInCabin.TABLE_TOP_Y <= 0.44)


## Hard user requirement: dead-centre head-on seat at (0, 0, 0) facing -Z, and EVERY row has an odd seat count with
## a dead-centre seat at x = 0.0 (zero centre aisle!).
func _dead_centre_seats(room: Node3D) -> void:
	var seats: Array[Transform3D] = room.room_seat_transforms()
	check("6 plush settee seats across 2 rows (%d seats)" % seats.size(), seats.size() == 6)

	var origin_seat := false
	var origin_head_on := false
	var rows := {}
	for xf: Transform3D in seats:
		var rz := snappedf(xf.origin.z, 0.01)
		if not rows.has(rz):
			rows[rz] = []
		(rows[rz] as Array).append(xf)
		if xf.origin.length() < 0.001:
			origin_seat = true
			var fwd := (-xf.basis.z).normalized()
			origin_head_on = fwd.dot(Vector3.FORWARD) > 0.999
	check("dead-centre viewer seat at (0.0, 0.0, 0.0) facing -Z head-on at screen",
			origin_seat and origin_head_on)

	var all_odd := true
	var all_have_centre := true
	for rz: float in rows:
		var row: Array = rows[rz]
		if row.size() % 2 != 1:
			all_odd = false
		var has_mid := row.any(func(xf: Transform3D) -> bool: return absf(xf.origin.x) < 0.001)
		if not has_mid:
			all_have_centre = false
	check("every row (%d rows) has an odd seat count and a dead-centre seat at x = 0.0" % rows.size(),
			rows.size() == 2 and all_odd and all_have_centre)


## Kit physics clearance, outside-only snowfall drift envelopes, and snug timber cabin Sabine acoustics.
func _physics_weather_and_acoustics(room: Node3D) -> void:
	var kit: Node = room.host.system("chalet")
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

	# Verify BOTH weather snow boxes and their full wind-drift sweeps stay strictly outside the chalet interior!
	var weather: Node = room.host.system_of_kind("atmosphere")
	var wv: Array = weather.params["wind"]
	var wind := Vector3(float(wv[0]), 0.0, float(wv[1]))
	var interior := AABB(Vector3(-SnowedInCabin.HW, -1.0, SnowedInCabin.FZ),
			Vector3(SnowedInCabin.HW * 2.0, 9.0, SnowedInCabin.BZ - SnowedInCabin.FZ))
	var outside_only := true
	for entry: Array in weather.areas():
		var box: AABB = entry[2]
		var life := box.size.y / 0.75
		var half_drift := (wind * life * 0.5).abs()
		var swept := AABB(box.position - half_drift, box.size + half_drift * 2.0)
		if swept.intersects(interior):
			outside_only = false
	check("every snowfall particle box and full wind-drift envelope stays strictly outside the cabin",
			weather.areas().size() == 2 and outside_only)

	var sr: Dictionary = room.get_sound_room()
	var sbox: AABB = sr["box"]
	var sz := sbox.size.abs()
	var vol := sz.x * sz.y * sz.z
	var area := 2.0 * (sz.x * sz.y + sz.y * sz.z + sz.z * sz.x)
	var alpha := 0.161 * vol / (area * float(sr["rt60"]))
	print("  snowed_in_cabin acoustics: box %s rt60 %.2f wet %.2f late %.2f Sabine alpha %.3f" % [
			sz, float(sr["rt60"]), float(sr["wet"]), float(sr["late"]), alpha])
	check("Sabine mean absorption alpha in 0.05..0.75 (%.3f)" % alpha, alpha > 0.05 and alpha < 0.75)


## Live settings (snowfall, hearth, cabin_glow), sub-3 Hz fire flicker, Motion scaling, and film playback cues.
func _settings_and_cues(room: Node3D) -> void:
	var host: Node = room.host
	var kit: Node = host.system("chalet")
	var sky: Node = host.system("sky")
	var weather: Node = host.system_of_kind("atmosphere")
	var glow_mi := room.find_child("HearthGlow", true, false) as MeshInstance3D
	var shaft_mi := room.find_child("HearthShaft", true, false) as MeshInstance3D

	SoundFixture.finish_loading(room)
	host.snapshot_override = {"open": false}
	_steps(host, 5.0)
	check("preshow: house lamps full (%.2f), hearth roaring (%.2f)" % [
			float(host.param("light.house_lamps")), float(glow_mi.get_meta("fire_level", 0.0))],
			float(host.param("light.house_lamps")) > 0.95 and float(glow_mi.get_meta("fire_level", 0.0)) > 0.80)

	# 1. Hearth setting: roaring > low > embers, with gentle sub-3 Hz flicker & Flickering lights off holds steady.
	host.set_setting("hearth", "roaring")
	_steps(host, 4.0)
	var lo := 9.0
	var hi := 0.0
	for i in 90:
		host.step(1.0 / 30.0)
		var fl := float(glow_mi.get_meta("fire_level", 0.0))
		lo = minf(lo, fl)
		hi = maxf(hi, fl)
	check("hearth=roaring burns with gentle sub-3 Hz flicker (%.2f..%.2f)" % [lo, hi],
			glow_mi.visible and lo > 0.78 and hi - lo > 0.02 and hi - lo < 0.35
			and SnowedInCabin.FLICKER_HZ.all(func(f: float) -> bool: return f < 3.0))

	host.set_setting("flicker", false)
	_steps(host, 0.25, 0.1)
	var fl_a := float(glow_mi.get_meta("fire_level", 0.0))
	_steps(host, 1.5, 0.1)
	var fl_b := float(glow_mi.get_meta("fire_level", 0.0))
	check("Flickering lights off holds hearth flames steady (delta %.4f)" % absf(fl_b - fl_a),
			absf(fl_b - fl_a) < 0.005)
	host.set_setting("flicker", true)

	host.set_setting("hearth", "low")
	_steps(host, 4.0)
	var low_fl := float(glow_mi.get_meta("fire_level", 0.0))
	host.set_setting("hearth", "embers")
	_steps(host, 4.0)
	var emb_fl := float(glow_mi.get_meta("fire_level", 0.0))
	check("hearth=low (%.2f) and embers (%.2f) step down cleanly" % [low_fl, emb_fl],
			low_fl > 0.42 and low_fl < 0.68 and emb_fl > 0.14 and emb_fl < 0.30 and emb_fl < low_fl)
	host.set_setting("hearth", "roaring")
	_steps(host, 4.0)

	# 2. Snowfall setting: blizzard / gentle / clear drives weather.snow, sky clouds, and muffled alpine wind.
	host.set_setting("snowfall", "blizzard")
	_steps(host, 24.0)
	var bliz_s: float = weather.snow_amount()
	var bliz_c := float(sky.params["clouds"])
	host.set_setting("snowfall", "clear")
	_steps(host, 24.0)
	var clr_s: float = weather.snow_amount()
	var clr_c := float(sky.params["clouds"])
	host.set_setting("snowfall", "gentle")
	_steps(host, 24.0)
	var gen_s: float = weather.snow_amount()
	check("snowfall setting moves snow & clouds (blizzard %.2f/%.2f, gentle %.2f, clear %.2f/%.2f)" % [
			bliz_s, bliz_c, gen_s, clr_s, clr_c],
			bliz_s > 0.85 and gen_s > 0.20 and gen_s < 0.40 and clr_s < 0.04 and bliz_c > clr_c + 0.45)

	# 3. Cabin glow setting: amber / frost_blue / dim shifts PieceCove colour & level cleanly.
	host.set_setting("cabin_glow", "frost_blue")
	_steps(host, 4.0)
	var blue_cove: Color = kit.cove_state()["colour"]
	host.set_setting("cabin_glow", "dim")
	_steps(host, 4.0)
	var dim_glow := float(kit.cove_state()["glow"])
	host.set_setting("cabin_glow", "amber")
	_steps(host, 4.0)
	var amb_cove: Dictionary = kit.cove_state()
	check("cabin_glow shifts PieceCove (frost_blue b>r, dim %.2f < amber %.2f)" % [dim_glow, float(amb_cove["glow"])],
			blue_cove.b > blue_cove.r + 0.35 and dim_glow < 0.45 and float(amb_cove["glow"]) > 0.95)

	# 4. Motion setting scales steam/hearth-shaft drift clock cleanly (0 holds still).
	var c0 := float(shaft_mi.get_meta("clock", 0.0))
	_steps(host, 2.0)
	var c1 := float(shaft_mi.get_meta("clock", 0.0))
	host.set_setting("motion", 0.0)
	_steps(host, 2.0)
	var c2 := float(shaft_mi.get_meta("clock", 0.0))
	check("Motion scales steam/glow drift (delta %.2f) and freezes at 0 (delta %.4f)" % [c1 - c0, c2 - c1],
			c1 - c0 > 1.0 and absf(c2 - c1) < 0.001)
	host.set_setting("motion", 1.0)

	# 5. Film playback cues: playing dims house_lamps to 0.18 while cove_floor holds warm timber accents; paused lifts
	#    to 0.55; ended returns to 1.0.
	host.snapshot_override = {"open": true, "playing": true, "position": 120.0, "duration": 5400.0}
	_steps(host, 8.0)
	var play_lamps := float(host.param("light.house_lamps"))
	var play_cove := float(kit.cove_state()["glow"])
	host.snapshot_override = {"open": true, "playing": false, "paused": true, "position": 120.0, "duration": 5400.0}
	_steps(host, 5.0)
	var pause_lamps := float(host.param("light.house_lamps"))
	host.snapshot_override = {"open": true, "playing": false, "ended": true, "position": 5400.0, "duration": 5400.0}
	_steps(host, 6.0)
	var end_lamps := float(host.param("light.house_lamps"))
	check("cues dim on play (%.2f, cove floor %.2f), rise on pause (%.2f) & end (%.2f)" % [
			play_lamps, play_cove, pause_lamps, end_lamps],
			absf(play_lamps - 0.18) < 0.02 and play_cove > 0.34 and absf(pause_lamps - 0.55) < 0.04 and end_lamps > 0.95)
	host.snapshot_override = {"open": false}


## Sound beds: crackling hearth fire, muffled alpine wind, distant tawny owl on small_room acoustics.
func _sound(room: Node3D) -> void:
	RoomSound.check_beds(self, "snowed_in_cabin", room, {
		"hearth": "fire", "wind": "wind", "owl": "tawny_owl",
	}, "small_room")
	# Verify hearth fire bed & wind bed respond smoothly to setting.hearth and setting.snowfall.
	var h: Node = room.host
	h.set_setting("hearth", "embers")
	_steps(h, 6.0)
	var emb_lvl := float(h.system("hearth").params["level"])
	h.set_setting("hearth", "roaring")
	_steps(h, 6.0)
	var roar_lvl := float(h.system("hearth").params["level"])
	check("hearth fire sound bed scales with setting.hearth (embers %.2f < roaring %.2f)" % [emb_lvl, roar_lvl],
			emb_lvl > 0.18 and emb_lvl < 0.32 and roar_lvl > 0.95)

	h.set_setting("snowfall", "clear")
	_steps(h, 8.0)
	var clr_w := float(h.system("wind").params["level"])
	h.set_setting("snowfall", "blizzard")
	_steps(h, 8.0)
	var blz_w := float(h.system("wind").params["level"])
	h.set_setting("snowfall", "gentle")
	_steps(h, 6.0)
	check("alpine wind sound bed scales with setting.snowfall (clear %.2f < blizzard %.2f)" % [clr_w, blz_w],
			clr_w < 0.22 and blz_w > 0.95)


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


## Renders 10 lavapipe PNGs into ENV_SHOTS covering every angle, hero craft piece, alternate mood & film playback.
func _render(doc: Dictionary) -> void:
	if not RoomRender.has_renderer():
		print("SKIP render (headless)")
		return
	var sc: Array = doc["screen"]["center"]
	var screen := Vector3(float(sc[0]), float(sc[1]), float(sc[2]))
	var eye := Vector3(0.0, 1.2, 0.0)

	# --- Phase 1: Cozy Pre-Show (Warm amber glow, roaring fire, gentle flurries) ---
	RoomRender.set_light(screen, 0.055)
	var vc := await RoomRender.open(self, doc, 90.0)
	var room := vc[2] as Node3D
	var host: Node = room.host
	SoundFixture.finish_loading(room)
	RenderingServer.global_shader_parameter_set("screen_glow", 0.25)
	host.snapshot_override = {"open": false}
	host.set_setting("cabin_glow", "amber")
	host.set_setting("hearth", "roaring")
	host.set_setting("snowfall", "gentle")
	_steps(host, 6.0, 0.2)

	# 1. Dead-centre seat front view: screen, monumental gable windows, pines, coffee table & hearth edge.
	await RoomRender.shot(self, vc, eye, screen, "cabin_seat_front")
	# 2. Looking left-forward across gable window, port dormer window, snow-laden spruces, Moon & bookcase.
	await RoomRender.shot(self, vc, eye, Vector3(-6.2, 2.2, -5.8), "cabin_gable_left_pines")
	# 3. Hero starboard river-stone hearth closeup: stone arch, roaring flames, kettle, tools, firewood & garland.
	(vc[1] as Camera3D).fov = 72.0
	await RoomRender.shot(self, vc, Vector3(0.45, 1.25, -1.95), Vector3(4.1, 1.18, -2.75), "cabin_hearth_closeup")
	# 4. Looking up at soaring 45-deg Douglas-fir scissor trusses, iron gussets, wagon-wheel chandelier & gable apex.
	(vc[1] as Camera3D).fov = 92.0
	await RoomRender.shot(self, vc, Vector3(0.0, 1.25, 0.5), Vector3(0.0, 5.4, -4.6), "cabin_lookup_trusses_apex")
	# 5. Looking aft across sofas toward sleeping-loft mezzanine, balustrade, loft bed, ladder, chalet door & skis.
	(vc[1] as Camera3D).fov = 88.0
	await RoomRender.shot(self, vc, Vector3(-0.35, 1.45, -1.1), Vector3(0.25, 1.95, 5.5), "cabin_aft_loft_door_skis")
	# 6. Close-up of low live-edge cedar coffee table: steaming cocoa mugs, brass lantern, pinecones, tartan & nordic_rug.
	(vc[1] as Camera3D).fov = 66.0
	await RoomRender.shot(self, vc, Vector3(-0.25, 1.05, -0.35), Vector3(0.08, 0.42, -1.55), "cabin_coffee_table_detail")
	# 7. Elevated wide chalet overview from loft balustrade looking forward across seating, rug, hearth & gable.
	(vc[1] as Camera3D).fov = 90.0
	await RoomRender.shot(self, vc, Vector3(-2.6, 3.25, 3.15), Vector3(0.85, 1.35, -5.2), "cabin_wide_interior")

	# --- Phase 2: Frost Moonlight & Alpine Blizzard Mood ---
	host.set_setting("cabin_glow", "frost_blue")
	host.set_setting("snowfall", "blizzard")
	host.set_setting("hearth", "roaring")
	_steps(host, 20.0, 0.25)
	(vc[1] as Camera3D).fov = 90.0
	await RoomRender.shot(self, vc, eye, Vector3(1.1, 2.35, -7.2), "cabin_mood_frost_blizzard")

	# --- Phase 3: Hushed Dim Hearthlight & Clear Moonlit Peaks with Glowing Embers ---
	host.set_setting("cabin_glow", "dim")
	host.set_setting("snowfall", "clear")
	host.set_setting("hearth", "embers")
	_steps(host, 20.0, 0.25)
	await RoomRender.shot(self, vc, Vector3(-0.2, 1.25, -0.2), Vector3(3.4, 1.35, -3.5), "cabin_mood_dim_embers")

	# --- Phase 4: Film Playing (warm amber cove floor, roaring firelight, dimmed house lamps, screen spill!) ---
	RoomRender.set_light(screen, 0.022)
	RenderingServer.global_shader_parameter_set("screen_glow", 1.05)
	host.snapshot_override = {"open": true, "playing": true, "position": 900.0, "duration": 5400.0}
	host.signals.fake("film.brightness", 0.72)
	host.signals.fake("film.colour", Color(0.88, 0.64, 0.36))
	host.signals.fake("playback.playing", 1.0)
	host.set_setting("cabin_glow", "amber")
	host.set_setting("snowfall", "gentle")
	host.set_setting("hearth", "roaring")
	_steps(host, 10.0, 0.25)
	await RoomRender.shot(self, vc, eye, screen, "cabin_film_playing")

	await RoomRender.close(self, vc)
