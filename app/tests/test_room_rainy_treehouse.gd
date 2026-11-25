extends "res://tests/env_builder_harness.gd"

## Rainy treehouse (app/environments/rainy_treehouse.env.json; docs/environments/rooms/rainy_treehouse.md):
## a Cozy retreats room built by Gemini 4 Neon Extra High. A hand-built cedar-plank and pitched-corrugated-tin canopy
## hideaway nestled 14 m up inside an ancient mossy forest oak on a warm rainy twilight night.
## godot --headless --xr-mode off --path app --script res://tests/test_room_rainy_treehouse.gd

const RoomRender := preload("res://tests/room_render.gd")
const RoomSound := preload("res://tests/room_sound.gd")
const RainyTreehouse := preload("res://scripts/env/systems/kit/rainy_treehouse.gd")
const DOC := "res://environments/rainy_treehouse.env.json"

## Tight Rainy treehouse lightmap atlas ceiling (1024x1024 max).
const TREEHOUSE_MAX_ATLAS := 1024
## Tight second-build speed target (< 2.0 pace units).
const TREEHOUSE_BUILD_BUDGET := 2.0


func run_tests() -> void:
	test_name = "test_room_rainy_treehouse"
	var r := EnvDoc.load_file(DOC)
	check("the document reads without schema errors (%s)" % [r["errors"]], (r["errors"] as Array).is_empty())
	var doc: Dictionary = r["doc"]
	if doc.is_empty():
		return
	if OS.get_environment("TREEHOUSE_RENDER_ONLY") == "":
		var room := await check_room("rainy_treehouse", doc)
		room.host.auto = false
		_by_part(room)
		await _built_and_budgets(room, doc)
		_dead_centre_seats(room)
		_outside_only_rain_and_fog(room)
		_settings_fireflies_and_cues(room)
		_sound_and_acoustics(room)
		await done(room)
		await _build_speed(doc)
		await RoomSound.check_level(self, self, "rainy_treehouse", doc)
	await _render(doc)


func _built_and_budgets(room: Node3D, doc: Dictionary) -> void:
	var host: Node = room.host
	var stats := EnvChecks.measure(room)
	print("  measured: %s" % [stats])
	check("Rainy treehouse tight budgets: draws <= 34 (%d), tris <= 90k (%d), 0 live lights (%d), texture <= 12.0 MB (%.1f)"
			% [int(stats["draws"]), int(stats["triangles"]), int(stats["lights"]), float(stats["texture_mb"])],
			int(stats["draws"]) <= 34 and int(stats["triangles"]) <= 90000 and int(stats["lights"]) == 0
			and float(stats["texture_mb"]) <= 12.0)

	var meta: Dictionary = doc.get("room", {})
	var room_name := str(doc.get("name", ""))
	check("room name is 'Rainy treehouse' with no apostrophe", room_name == "Rainy treehouse" and not room_name.contains("'"))
	check("category is retreat (%s)" % str(meta.get("category", "")), str(meta.get("category", "")) == "retreat")
	check("author is Gemini 4 Neon Extra High", str(meta.get("author", "")) == "Gemini 4 Neon Extra High")
	check("description <= 200 chars (%d)" % str(meta.get("description", "")).length(),
			str(meta.get("description", "")).length() <= 200)

	var kit: Node = host.system("treehouse")
	check("kit builds cleanly with zero problems (%s)" % [kit.problems()], kit != null and kit.problems().is_empty())
	for n: String in ["PieceStatic", "PieceSoft", "PieceLamps", "PieceCove", "PieceGlass", "NordicRug", "Seats",
			"SkyDome", "SkyStars", "SkyMoon", "Fall0", "Fall1", "Fall2", "Fog", "Fireflies"]:
		check("room has %s" % n, room.find_child(n, true, false) != null)
	for n: String in ["Walls", "Floor", "Ceiling", "Trim"]:
		check("domestic %s left to the kit" % n, room.get_node_or_null(n) == null)

	# Hidden bake lights: 6 cabin/lantern omnis + 1 twilight moonlight spot, zero visible live lights.
	var omnis := room.find_children("KitLamp*", "OmniLight3D", true, false)
	var spots := room.find_children("KitSpot*", "SpotLight3D", true, false)
	var all_hidden := (omnis + spots).all(func(l: Node) -> bool: return not (l as Light3D).visible)
	check("bake lights present (6 omnis, 1 spot) and all hidden (%d, %d)" % [omnis.size(), spots.size()],
			omnis.size() == 6 and spots.size() == 1 and all_hidden)

	# Lightmap atlas hint strictly <= 1024x1024 on every static mesh.
	var largest := Vector2i.ZERO
	for mi: MeshInstance3D in room.static_meshes():
		largest = largest.max((mi.mesh as ArrayMesh).lightmap_size_hint)
	print("  atlas: %s (%d static meshes)" % [largest, room.static_meshes().size()])
	check("static atlas <= %dx%d (%s)" % [TREEHOUSE_MAX_ATLAS, TREEHOUSE_MAX_ATLAS, largest],
			not room.static_meshes().is_empty() and largest.x > 0
			and largest.x <= TREEHOUSE_MAX_ATLAS and largest.y <= TREEHOUSE_MAX_ATLAS)

	# Every kit physics box stays >= 0.5 m clear of viewer origin (0, 0, 0).
	var min_clear := INF
	for sh: Array in kit.collision_shapes():
		var bs := sh[0] as BoxShape3D
		var xf := sh[1] as Transform3D
		var local_o := xf.affine_inverse() * Vector3(0.0, 0.5, 0.0)
		var he := bs.size * 0.5
		var clamped := local_o.clamp(-he, he)
		min_clear = minf(min_clear, local_o.distance_to(clamped))
	check("every kit physics box >= 0.5 m clear of (0, 0, 0) (min %.2f m)" % min_clear, min_clear >= 0.5)

	# Blend overdraw strictly < 1.0.
	var bl := await EnvChecks.blend_layers(self, room)
	print("  blend: mean %.2f, peak %d, share %.2f (limit < 1.00)" % [
			float(bl["mean"]), int(bl["peak"]), float(bl["share"])])
	check("blended layers mean %.2f < 1.00" % float(bl["mean"]), float(bl["mean"]) < 1.0)


## Hard user requirement: dead-centre seat at (0, 0, 0) facing -Z head-on at the screen, and EVERY row has an odd
## seat count with a seat at x = 0.0 (zero centre aisle).
func _dead_centre_seats(room: Node3D) -> void:
	var seats: Array[Transform3D] = room.room_seat_transforms()
	check("6 cozy bean-bag seats across 2 rows (%d)" % seats.size(), seats.size() == 6)
	var seats_sys: Node = room.host.system("seats")
	check("seats model is bean_bag", seats_sys != null and str(seats_sys.params["model"]) == "bean_bag")

	var has_origin_head_on := false
	var by_row := {}
	for st: Transform3D in seats:
		var fwd := (-st.basis.z).normalized()
		if absf(st.origin.x) < 0.001 and absf(st.origin.z) < 0.001 and fwd.dot(Vector3.FORWARD) > 0.999:
			has_origin_head_on = true
		var rkey := roundi(st.origin.z * 100.0)
		var row_xs: Array = by_row.get(rkey, [])
		row_xs.append(st.origin.x)
		by_row[rkey] = row_xs
	check("dead-centre seat at x=0.0, z=0.0 facing -Z head-on", has_origin_head_on)

	var all_odd_and_centred := not by_row.is_empty()
	for rkey: int in by_row:
		var xs: Array = by_row[rkey]
		var has_zero := false
		for x: float in xs:
			if absf(x) < 0.001:
				has_zero = true
		if xs.size() % 2 != 1 or not has_zero:
			all_odd_and_centred = false
	check("every row (%d rows) has an odd seat count with a seat at x=0.0 (zero centre aisle)" % by_row.size(),
			all_odd_and_centred)


## Verify rain areas stay strictly outside the dry corrugated-tin roof overhang ([-5.12..5.12, -6.55..5.15]) with zero
## inward wind, and that `setting.rain` drives rain, mist, clouds, stars and Moon live.
func _outside_only_rain_and_fog(room: Node3D) -> void:
	var host: Node = room.host
	var w: Node = host.system("weather")
	var sky: Node = host.system("sky")
	var atm: Node = host.system("atmosphere")
	check("weather draws falling rain across 3 outside canopy curtains",
			w != null and str(w.params["falls"]) == "rain" and (w.areas() as Array).size() == 3)

	var wind: Array = w.params["wind"]
	var dry_eave := Rect2(-RainyTreehouse.EAVE_X, RainyTreehouse.EAVE_FZ,
			RainyTreehouse.EAVE_X * 2.0, RainyTreehouse.EAVE_BZ - RainyTreehouse.EAVE_FZ)
	var all_outside := float(wind[0]) == 0.0 and float(wind[1]) == 0.0
	for a: Array in w.areas():
		var box: AABB = a[2]
		var area_xz := Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
		# Require >= 0.45 m buffer outside the overhanging rain eaves so zero drops ever clip inside!
		if area_xz.intersects(dry_eave.grow(0.45)):
			all_outside = false
	check("all 3 rain boxes stay >= 0.45 m outside dry eaves footprint with zero inward wind", all_outside)

	# Live `rain` setting transitions: steady -> drizzle -> clear -> steady.
	host.set_setting("rain", "clear")
	_steps(host, 95.0, 0.5)
	var r_clear := float(w.rain_amount())
	var stars_clear := float(sky.params["stars"])
	var fog_clear := float(atm.params["fog"])

	host.set_setting("rain", "drizzle")
	_steps(host, 95.0, 0.5)
	var r_driz := float(w.rain_amount())

	host.set_setting("rain", "steady")
	_steps(host, 95.0, 0.5)
	var r_steady := float(w.rain_amount())
	var stars_steady := float(sky.params["stars"])
	var fog_steady := float(atm.params["fog"])

	check("rain setting drives weather.rain (steady=%.2f, drizzle=%.2f, clear=%.2f)" % [r_steady, r_driz, r_clear],
			r_steady > 0.85 and r_driz > 0.22 and r_driz < 0.38 and r_clear < 0.04)
	check("rain setting shifts sky stars & forest mist (stars %.2f->%.2f, fog %.2f->%.2f)"
			% [stars_steady, stars_clear, fog_steady, fog_clear],
			stars_clear > 0.90 and stars_steady < 0.45 and fog_steady > fog_clear + 0.20)


## Verify `lanterns` setting, `fireflies` setting + rain-easing brightening, sight-line clearance, and film dimming cues.
func _settings_fireflies_and_cues(room: Node3D) -> void:
	var host: Node = room.host
	var kit: Node = host.system("treehouse")
	var ff: Node = host.system("fireflies")

	# 1. Fairy lanterns setting: amber / forest_gold / dim.
	host.timeline.state = ""
	host.snapshot_override = {"open": false}
	host.set_setting("lanterns", "amber")
	_steps(host, 5.0)
	var cs_amb: Dictionary = kit.cove_state()
	host.set_setting("lanterns", "forest_gold")
	_steps(host, 5.0)
	var cs_gold: Dictionary = kit.cove_state()
	host.set_setting("lanterns", "dim")
	_steps(host, 5.0)
	var cs_dim: Dictionary = kit.cove_state()
	check("lanterns setting switches fairy lantern colour & glow (amber=%.2f, gold=%.2f, dim=%.2f)"
			% [float(cs_amb["glow"]), float(cs_gold["glow"]), float(cs_dim["glow"])],
			float(cs_amb["glow"]) > 1.15 and float(cs_gold["glow"]) > 1.10 and float(cs_dim["glow"]) < 0.45
			and (cs_gold["colour"] as Color).g > (cs_amb["colour"] as Color).g + 0.15)
	host.set_setting("lanterns", "amber")
	_steps(host, 5.0)

	# 2. Fireflies: 36 golden-chartreuse fireflies, clear of screen sight line, controlled by setting & brightening as rain clears!
	host.set_setting("fireflies", "many")
	host.set_setting("rain", "steady")
	_steps(host, 60.0, 0.5)
	var pts_many: Array = ff.positions()
	var in_sight := 0
	for p: Vector3 in pts_many:
		if ff.in_view(p, 0.0):
			in_sight += 1
	var glow_rain := float(ff.params["glow"])
	check("36 fireflies active at many and clear of sight line (%d total, %d in sight)" % [pts_many.size(), in_sight],
			pts_many.size() == 36 and in_sight == 0)

	host.set_setting("rain", "clear")
	_steps(host, 95.0, 0.5)
	var glow_clear := float(ff.params["glow"])
	check("fireflies brighten when canopy rain clears (%.2f -> %.2f)" % [glow_rain, glow_clear],
			glow_clear > glow_rain + 0.55)
	host.set_setting("rain", "steady")
	_steps(host, 60.0, 0.5)

	host.set_setting("fireflies", "few")
	_steps(host, 6.0)
	var pts_few: Array = ff.positions()
	host.set_setting("fireflies", "off")
	_steps(host, 6.0)
	var pts_off: Array = ff.positions()
	check("fireflies setting scales active count (many=%d, few=%d, off=%d)" % [pts_many.size(), pts_few.size(), pts_off.size()],
			pts_few.size() >= 10 and pts_few.size() <= 18 and pts_off.size() == 0)
	host.set_setting("fireflies", "many")
	_steps(host, 5.0)

	# 3. Film ritual dimming cues: house_lamps -> 0.18, PieceCove keeps cove_floor=0.38, restored to 1.0 on ended.
	host.snapshot_override = {"open": false}
	_steps(host, 8.0)
	var pre_lamps := float(host.param("light.house_lamps"))
	var pre_cove := float(kit.cove_state()["glow"])
	host.snapshot_override = {"open": true, "playing": true, "position": 0.5, "duration": 7200.0}
	_steps(host, 12.0)
	var film_lamps := float(host.param("light.house_lamps"))
	var film_cove := float(kit.cove_state()["glow"])
	check("film cue dims lamps (%.2f -> %.2f) while fairy lanterns keep cove_floor (%.2f -> %.2f)"
			% [pre_lamps, film_lamps, pre_cove, film_cove],
			pre_lamps > 0.95 and absf(film_lamps - 0.18) < 0.03
			and film_cove >= 0.36 * 1.25 and film_cove < pre_cove * 0.55)
	host.snapshot_override = {"open": true, "playing": false, "ended": true, "position": 7200.0, "duration": 7200.0}
	_steps(host, 8.0)
	check("ended restores cabin lamps (%.2f)" % float(host.param("light.house_lamps")),
			float(host.param("light.house_lamps")) > 0.95)


func _sound_and_acoustics(room: Node3D) -> void:
	RoomSound.check_beds(self, "rainy_treehouse", room,
			{"tin_roof": "rain_tin", "canopy_rain": "rain_leaves", "breeze": "wind", "owl": "tawny_owl"},
			"small_room")
	RoomSound.check_follows(self, "rainy_treehouse", room, "tin_roof", "weather.rain")
	RoomSound.check_follows(self, "rainy_treehouse", room, "canopy_rain", "weather.rain")

	var ac: Node = room.host.system("acoustics")
	check("acoustics tuned for timber treehouse (rt60=%.2f, wet=%.2f)"
			% [float(ac.params["rt60"]), float(ac.params["wet"])],
			absf(float(ac.params["rt60"]) - 0.42) < 0.02 and absf(float(ac.params["wet"]) - 0.16) < 0.02)

	var sr: Dictionary = room.get_sound_room()
	var box: AABB = sr["box"]
	var v := box.size.x * box.size.y * box.size.z
	var area := 2.0 * (box.size.x * box.size.y + box.size.y * box.size.z + box.size.z * box.size.x)
	var alpha := 0.161 * v / (area * float(sr["rt60"]))
	print("  acoustics: box %.1f x %.1f x %.1f, rt60 %.2f, wet %.2f, Sabine alpha %.3f"
			% [box.size.x, box.size.y, box.size.z, float(sr["rt60"]), float(sr["wet"]), alpha])
	check("Sabine mean absorption %.3f in 0.05..0.75" % alpha, alpha >= 0.05 and alpha <= 0.75)


func _build_speed(doc: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	var second: Node3D = EnvRoom.new()
	second.doc = doc
	root.add_child(second)
	await process_frame
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var units := EnvChecks.build_units(ms)
	print("  build: %.1f ms (%.1f pace units; limit < %.1f)" % [ms, units, TREEHOUSE_BUILD_BUDGET])
	check("fast second-build time %.1f < %.1f pace units" % [units, TREEHOUSE_BUILD_BUDGET],
			units < TREEHOUSE_BUILD_BUDGET)
	await done(second)


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
	var eye := Vector3(0.0, 1.20, 0.0)

	# --- 1. Pre-show: Steady canopy rain + Warm amber fairy lanterns + Many fireflies ---
	RoomRender.set_light(screen, 0.055)
	var vc := await RoomRender.open(self, doc, 92.0)
	var host: Node = (vc[2] as Node).host
	RenderingServer.global_shader_parameter_set("screen_glow", 0.20)
	host.snapshot_override = {"open": false}
	host.set_setting("rain", "steady")
	host.set_setting("lanterns", "amber")
	host.set_setting("fireflies", "many")
	host.signals.fake("film.brightness", 0.0)
	_steps(host, 10.0, 0.25)

	# Shot 1: Dead-centre seat front view toward hand-lashed screen, coffee table, fairy lanterns & forward shutters!
	await RoomRender.shot(self, vc, eye, screen + Vector3(0.0, -0.04, 0.0), "treehouse_centre_seat")
	# Shot 2: Looking starboard & slightly up at gnarled ancient mossy oak trunk, canopy limbs & propped shutters!
	await RoomRender.shot(self, vc, Vector3(-0.6, 1.30, -0.4), Vector3(4.2, 2.25, 0.8), "treehouse_oak_trunk_canopy")
	# Shot 3: Looking port across propped-open timber shutter awning, jam-jar candles, spyglass, misty woodland & rain!
	await RoomRender.shot(self, vc, Vector3(0.4, 1.28, -1.2), Vector3(-5.0, 1.40, -2.5), "treehouse_port_shutter_shelf")
	# Shot 4: Looking AFT across bean bags & Nordic rug toward open balcony door, curving rope bridge, trapdoor & shelf!
	await RoomRender.shot(self, vc, Vector3(-0.3, 1.48, -1.6), Vector3(0.1, 1.05, 6.2), "treehouse_aft_bridge_trapdoor")
	# Shot 5: Looking UP at pitched weathered corrugated-tin roof, exposed cedar rafters, king-posts & fairy lanterns!
	await RoomRender.shot(self, vc, Vector3(0.0, 1.15, 0.8), Vector3(0.0, 4.45, -2.8), "treehouse_ceiling_tin_lanterns")
	# Shot 6: Close-up of low cedar-stump coffee table (enamel teapot, mugs, brass oil lantern, field guides) & rug!
	(vc[1] as Camera3D).fov = 62.0
	await RoomRender.shot(self, vc, Vector3(-0.55, 1.05, -0.55), Vector3(0.05, 0.44, -1.92),
			"treehouse_coffee_table_closeup")
	# Shot 7: Outside on the aft wrap-around slatted cedar balcony looking down the curving rope suspension bridge!
	(vc[1] as Camera3D).fov = 84.0
	await RoomRender.shot(self, vc, Vector3(-0.85, 1.45, 4.75), Vector3(-2.8, 0.85, 16.5), "treehouse_bridge_outside")
	(vc[1] as Camera3D).fov = 92.0

	# --- 2. Variant: Clear after rain + Forest gold lanterns + Bright fireflies ---
	host.set_setting("rain", "clear")
	host.set_setting("lanterns", "forest_gold")
	host.set_setting("fireflies", "many")
	_steps(host, 90.0, 0.5)
	await RoomRender.shot(self, vc, eye, Vector3(-2.6, 2.05, -5.0), "treehouse_clear_fireflies_gold")

	# --- 3. Variant: Light drizzle + Dim embers lanterns ---
	host.set_setting("rain", "drizzle")
	host.set_setting("lanterns", "dim")
	_steps(host, 75.0, 0.5)
	await RoomRender.shot(self, vc, eye, screen + Vector3(0.0, 0.05, 0.0), "treehouse_dim_drizzle")

	# --- 4. Film-playing dimmed view (default steady rain + warm amber fairy lanterns at cove_floor) ---
	host.set_setting("rain", "steady")
	host.set_setting("lanterns", "amber")
	host.set_setting("fireflies", "many")
	RoomRender.set_light(screen, 0.018)
	RenderingServer.global_shader_parameter_set("screen_glow", 1.12)
	host.snapshot_override = {"open": true, "playing": true, "position": 1800.0, "duration": 7200.0}
	host.signals.fake("film.brightness", 0.72)
	host.signals.fake("film.colour", Color(0.92, 0.62, 0.34))
	host.signals.fake("playback.playing", 1.0)
	_steps(host, 65.0, 0.5)
	await RoomRender.shot(self, vc, eye, screen + Vector3(0.0, -0.02, 0.0), "treehouse_film_playing")

	await RoomRender.close(self, vc)
