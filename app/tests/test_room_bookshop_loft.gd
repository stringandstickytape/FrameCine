extends "res://tests/env_builder_harness.gd"

## Bookshop loft (app/environments/bookshop_loft.env.json; docs/environments/rooms/bookshop_loft.md):
## a Cozy retreats room built by Gemini 4 Neon Extra High. A warm walnut-and-oak timber mezzanine loft perched
## overlooking a winding two-storey antique bookshop after closing on a rainy night.
## godot --headless --xr-mode off --path app --script res://tests/test_room_bookshop_loft.gd

const RoomRender := preload("res://tests/room_render.gd")
const RoomSound := preload("res://tests/room_sound.gd")
const BookshopLoft := preload("res://scripts/env/systems/kit/bookshop_loft.gd")
const DOC := "res://environments/bookshop_loft.env.json"


func run_tests() -> void:
	test_name = "test_room_bookshop_loft"
	var r := EnvDoc.load_file(DOC)
	check("the document reads (%s)" % [r["errors"]], (r["errors"] as Array).is_empty())
	var doc: Dictionary = r["doc"]
	if doc.is_empty():
		return
	if OS.get_environment("BOOKSHOP_RENDER_ONLY") == "":
		var room := await check_room("bookshop_loft", doc)
		room.host.auto = false
		_by_part(room)
		await _built_and_budgets(room, doc)
		_centre_seats_and_balustrade(room, doc)
		_clock_dial(room)
		_lamps_and_cues(room)
		_rain_and_dormers(room)
		_sound(room)
		await done(room)
		await _build_speed(doc)
		var lvl := await RoomSound.check_level(self, self, "bookshop_loft", doc)
		check("sound pre-show RMS comfortably below -38 dBFS (%.1f dBFS)" % float(lvl["pre"]),
				float(lvl["pre"]) < -44.0)
		check("sound under-film RMS in -62..-82 dBFS quiet band (%.1f dBFS)" % float(lvl["under"]),
				float(lvl["under"]) < -62.0 and float(lvl["under"]) > -84.0)
	await _render(doc)


## Tight budgets, metadata, meshes, hidden bake lights, <= 1024 lightmap atlas, physics clearance & blend overdraw.
func _built_and_budgets(room: Node3D, doc: Dictionary) -> void:
	var host: Node = room.host
	var stats := EnvChecks.measure(room)
	print("  measured: %s" % [stats])
	check("within Bookshop loft tight budget: <= 34 draws, <= 90k tris, 0 live lights, <= 12 MB tex (%s)" % [stats],
			int(stats["draws"]) <= 34 and int(stats["triangles"]) <= 90000 and int(stats["lights"]) == 0
			and int(stats["particles"]) <= 1200 and float(stats["texture_mb"]) <= 12.0)

	var meta: Dictionary = doc.get("room", {})
	check("name is Bookshop loft with no apostrophe (%s)" % str(doc.get("name", "")),
			str(doc.get("name", "")) == "Bookshop loft" and not str(doc.get("name", "")).contains("'"))
	check("category is retreat (%s)" % str(meta.get("category", "")), str(meta.get("category", "")) == "retreat")
	check("author is Gemini 4 Neon Extra High", str(meta.get("author", "")) == "Gemini 4 Neon Extra High")
	check("description <= 200 chars (%d)" % str(meta.get("description", "")).length(),
			str(meta.get("description", "")).length() <= 200)

	var kit: Node = host.system("bookshop")
	check("kit builds cleanly with zero problems (%s)" % [kit.problems()], kit != null and kit.problems().is_empty())
	for n: String in ["PieceStatic", "PieceSoft", "PieceLamps", "PieceCove", "PieceClock", "PieceGlass",
			"PieceWindows", "MezzanineRug", "RainPane", "Fall0", "Fall1", "Seats", "SkyDome", "SkyMoon"]:
		check("room has %s" % n, room.find_child(n, true, false) != null)
	for n: String in ["Walls", "Floor", "Ceiling", "Trim", "Doorway", "Screen"]:
		check("domestic %s left to the kit" % n, room.get_node_or_null(n) == null)

	# Hidden bake lights: 8 warm omni lamps + 2 dormer moonlight spots, all hidden (0 live lights).
	var omnis := room.find_children("KitLamp*", "OmniLight3D", true, false)
	var spots := room.find_children("KitSpot*", "SpotLight3D", true, false)
	var all_hidden := true
	for l: Node in omnis + spots:
		all_hidden = all_hidden and not (l as Light3D).visible
	check("bake lights present (8 omnis, 2 moonlight spots) and all hidden (%d, %d)" % [omnis.size(), spots.size()],
			omnis.size() == 8 and spots.size() == 2 and all_hidden)

	# Static meshes for the bake, each with atlas <= 1024 x 1024; sound room box; collision shapes.
	var largest := Vector2i.ZERO
	for mi: MeshInstance3D in room.static_meshes():
		largest = largest.max((mi.mesh as ArrayMesh).lightmap_size_hint)
	print("  bake: %d static meshes, largest atlas %s" % [room.static_meshes().size(), largest])
	check("static meshes for bake with atlas <= 1024 x 1024 (%s)" % [largest],
			not room.static_meshes().is_empty() and largest.x > 0 and largest.x <= 1024 and largest.y <= 1024)
	check("sound room box and physics shapes present (%d)" % room.collision_shapes().size(),
			room.get_sound_room().has("box") and room.collision_shapes().size() >= 15)

	# Every kit physics box >= 0.5 m clear of the dead-centre seat origin (0, 0, 0).
	var min_clear := INF
	for sh: Array in kit.collision_shapes():
		var bs := sh[0] as BoxShape3D
		var xf := sh[1] as Transform3D
		var local_o := xf.affine_inverse() * Vector3(0.0, 0.5, 0.0)
		var he := bs.size * 0.5
		var clamped := Vector3(clampf(local_o.x, -he.x, he.x), clampf(local_o.y, -he.y, he.y),
				clampf(local_o.z, -he.z, he.z))
		min_clear = minf(min_clear, local_o.distance_to(clamped))
	check("every kit physics box >= 0.5 m clear of (0, 0, 0) (min %.2f m)" % min_clear, min_clear >= 0.5)

	# Blended overdraw across forward view strictly < 1.0.
	var bl := await EnvChecks.blend_layers(self, room)
	print("  blend_layers: %s (budget < %.2f)" % [bl, EnvChecks.BLEND_BUDGET])
	check("blend_layers mean < %.2f (%s)" % [EnvChecks.BLEND_BUDGET, bl],
			float(bl["mean"]) < EnvChecks.BLEND_BUDGET)


## HARD USER REQUIREMENT: Dead-centre head-on seat at (0, 0, 0) facing -Z, every row odd-count with a seat at x = 0.0
## and zero centre aisle, plus verified balustrade vertical clearance below every seat's sight line to the screen bottom!
func _centre_seats_and_balustrade(room: Node3D, doc: Dictionary) -> void:
	var seats: Array[Transform3D] = room.room_seat_transforms()
	check("six club armchairs in two rows of three (%d seats)" % seats.size(), seats.size() == 6)

	var has_origin_head_on := false
	var by_row := {}
	for st: Transform3D in seats:
		var o := st.origin
		var facing_neg_z := st.basis.z.is_equal_approx(Vector3.BACK)
		if absf(o.x) < 0.001 and absf(o.y) < 0.001 and absf(o.z) < 0.001 and facing_neg_z:
			has_origin_head_on = true
		var rz := roundi(o.z * 100.0)
		if not by_row.has(rz):
			by_row[rz] = []
		(by_row[rz] as Array).append(st)
	check("dead-centre head-on seat exists at (0.0, 0.0, 0.0) facing -Z", has_origin_head_on)

	var every_row_odd_and_centred := not by_row.is_empty()
	for rz: int in by_row:
		var row_seats: Array = by_row[rz]
		if row_seats.size() % 2 != 1:
			every_row_odd_and_centred = false
		var has_x0 := false
		for st: Transform3D in row_seats:
			if absf(st.origin.x) < 0.001 and st.basis.z.is_equal_approx(Vector3.BACK):
				has_x0 = true
		if not has_x0:
			every_row_odd_and_centred = false
	check("every row has an odd seat count with a head-on seat at x = 0.0 (rows=%d)" % by_row.size(),
			every_row_odd_and_centred)

	# Verify exact vertical clearance of the mezzanine balustrade (y = RAIL_H = 0.86 m at z = WELL_Z1 + 0.06 = -1.99)
	# beneath the lowest visual ray from EVERY seat's eye (y = 1.20 m) to the true bottom edge of the screen!
	var sc_c: Array = doc["screen"]["center"]
	var sc_s: Array = doc["screen"]["size"]
	var scr_bot_y := float(sc_c[1]) - float(sc_s[1]) * 0.5
	var scr_z := float(sc_c[2])
	var rail_z := BookshopLoft.WELL_Z1 + 0.06
	var min_margin := INF
	for st: Transform3D in seats:
		var eye_y := st.origin.y + EnvChecks.EYE_HEIGHT
		var eye_z := st.origin.z
		var t := (eye_z - rail_z) / (eye_z - scr_z)
		var ray_y := lerpf(eye_y, scr_bot_y, t)
		min_margin = minf(min_margin, ray_y - BookshopLoft.RAIL_H)
	check("balustrade clears screen bottom from every seat by >= 0.20 m (min margin %.2f m)" % min_margin,
			min_margin >= 0.20)


## The tall aft carved oak grandfather clock (`PieceClock`) keeps real wall time.
func _clock_dial(room: Node3D) -> void:
	var kit: Node = room.host.system("bookshop")
	var hands: Array = kit.clock_hands()
	check("grandfather clock has live hour and minute hands (%s)" % [hands], hands.size() == 2)
	if hands.size() == 2:
		var t := Time.get_time_dict_from_system()
		var mins := float(t["minute"]) + float(t["second"]) / 60.0
		var hrs := fmod(float(t["hour"]), 12.0) + mins / 60.0
		var want_h := TAU * hrs / 12.0
		var want_m := TAU * mins / 60.0
		var err_h := absf(wrapf(float(hands[0]) - want_h, -PI, PI))
		var err_m := absf(wrapf(float(hands[1]) - want_m, -PI, PI))
		check("grandfather clock hands match real wall time (err h=%.3f m=%.3f rad)" % [err_h, err_m],
				err_h < 0.05 and err_m < 0.08)


## Live `lamps` setting shifts the banker's lamps & cornice uplight (`PieceCove`) cleanly across
## Warm amber / Emerald banker / Dim; film cues dim house & accent lights while holding cozy cove_floor.
func _lamps_and_cues(room: Node3D) -> void:
	var host: Node = room.host
	var kit: Node = host.system("bookshop")

	host.timeline.state = ""
	host.snapshot_override = {"open": false}
	host.set_setting("lamps", "warm_amber")
	_steps(host, 8.0)
	var st_warm: Dictionary = kit.cove_state()
	var c_warm: Color = st_warm.get("colour", Color.BLACK)
	check("lamps=warm_amber glows warm honey amber (%s, glow %.2f)" % [c_warm, float(st_warm.get("glow", 0.0))],
			c_warm.r > 0.9 and c_warm.g > 0.65 and c_warm.r > c_warm.b * 2.4 and float(st_warm.get("glow", 0.0)) > 1.1)

	host.set_setting("lamps", "emerald_banker")
	_steps(host, 5.0)
	var st_em: Dictionary = kit.cove_state()
	var c_em: Color = st_em.get("colour", Color.BLACK)
	check("lamps=emerald_banker shifts shades to jewel emerald green (%s)" % c_em,
			c_em.g > 0.70 and c_em.g > c_em.r * 5.0 and c_em.g > c_em.b * 2.0)

	host.set_setting("lamps", "dim")
	_steps(host, 5.0)
	var st_dim: Dictionary = kit.cove_state()
	check("lamps=dim lowers cove brightness (%.2f)" % float(st_dim.get("glow", 9.0)),
			float(st_dim.get("glow", 9.0)) < float(st_warm.get("glow", 0.0)) * 0.4)

	host.set_setting("lamps", "warm_amber")
	_steps(host, 5.0)

	# Film cues: house lamps & stove accent dim cleanly, cove_floor 0.42 keeps a warm reading ember, all back at end.
	host.snapshot_override = {"open": true, "playing": true, "position": 0.5, "duration": 7200.0}
	_steps(host, 14.0)
	var house_film := float(host.param("light.house_lamps"))
	var accent_film := float(host.param("light.accent"))
	var cove_film := float(kit.cove_state().get("glow", 0.0))
	check("during film: house lamps dim (%.2f), accent dims (%.2f), lamps hold cove_floor (%.2f)" % [
			house_film, accent_film, cove_film],
			absf(house_film - 0.18) < 0.03 and absf(accent_film - 0.45) < 0.03 and cove_film > 0.44 and cove_film < 0.64)

	host.snapshot_override = {"open": true, "playing": false, "ended": true, "position": 7200.0, "duration": 7200.0}
	_steps(host, 10.0)
	check("after film: house lamps (%.2f) and accent (%.2f) return to 1.0" % [
			float(host.param("light.house_lamps")), float(host.param("light.accent"))],
			float(host.param("light.house_lamps")) > 0.96 and float(host.param("light.accent")) > 0.96)


## Rain falls strictly outside the port & starboard dormer skylights (`|x| >= 6.0 m`, zero inward X wind),
## 4 merged rain-beaded dormer panes sit cleanly inside the roof dormers, and `rain` setting switches live.
func _rain_and_dormers(room: Node3D) -> void:
	var host: Node = room.host
	var w: Node = host.system("weather")
	check("weather draws falling rain and 4 merged dormer panes",
			w != null and str(w.params["falls"]) == "rain" and w.pane() != null and (w.params["panes"] as Array).size() == 4)
	var wind: Array = w.params["wind"]
	var outside_ok := (w.areas() as Array).size() == 2 and absf(float(wind[0])) < 0.001
	for a: Array in w.areas():
		var box: AABB = a[2]
		if box.end.x > -6.0 and box.position.x < 6.0:
			outside_ok = false
	check("all rain areas stay strictly outside |x| >= 6.0 m with zero inward wind", outside_ok)

	host.set_setting("rain", "clear")
	_steps(host, 120.0, 0.5)
	check("rain=clear stops the rain (%.2f)" % float(w.rain_amount()), float(w.rain_amount()) < 0.05)
	host.set_setting("rain", "drizzle")
	_steps(host, 90.0, 0.5)
	var driz := float(w.rain_amount())
	check("rain=drizzle settles at light drizzle (%.2f)" % driz, driz > 0.20 and driz < 0.40)
	host.set_setting("rain", "steady")
	_steps(host, 90.0, 0.5)
	check("rain=steady restores steady rain (%.2f)" % float(w.rain_amount()), float(w.rain_amount()) > 0.85)


## Sound beds (`grand_clock`, `rain_glass`, `fire`, `purr`), small_room acoustics, `clock` setting & `weather.rain`.
func _sound(room: Node3D) -> void:
	RoomSound.check_beds(self, "bookshop_loft", room, {
			"clock": "grand_clock", "rain": "rain_glass", "stove": "fire", "cat": "purr"}, "small_room")
	RoomSound.check_follows(self, "bookshop_loft", room, "rain", "weather.rain")
	RoomSound.check_setting(self, "bookshop_loft", room, "clock", "clock", "off", "soft")
	# Also verify the intermediate `quiet` level on `grand_clock`.
	var h: Node = room.host
	h.set_setting("clock", "quiet")
	_steps(h, 10.0, 0.25)
	var clk: Node = h.system("clock")
	var q_lvl := float(clk.params["level"])
	check("clock=quiet settles at gentle intermediate tick level (%.2f)" % q_lvl, q_lvl > 0.25 and q_lvl < 0.45)
	h.set_setting("clock", "soft")
	_steps(h, 10.0, 0.25)


## Second build time (after procedural cache warm-up) stays cleanly under 2.0 pace units.
func _build_speed(doc: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	var room2: Node3D = EnvRoom.new()
	room2.doc = doc
	root.add_child(room2)
	await process_frame
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var units := EnvChecks.build_units(ms)
	print("  build_time: %.1f ms (%.1f pace units, target < 2.0)" % [ms, units])
	check("build time < 2.0 pace units (%.1f)" % units, units < 2.0)
	await done(room2)


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
	RoomRender.set_light(screen, 0.055)
	var vc := await RoomRender.open(self, doc, 88.0)
	var host: Node = (vc[2] as Node).host
	var eye := Vector3(0.0, 1.20, 0.0)

	# 1. Pre-show, Warm amber reading lamps, steady rain outside.
	host.snapshot_override = {"open": false}
	host.set_setting("lamps", "warm_amber")
	host.set_setting("rain", "steady")
	_steps(host, 12.0)
	RoomRender.set_light(screen, 0.055)
	RenderingServer.global_shader_parameter_set("screen_glow", 0.22)

	# Shot 1: Dead-centre seat front view across oak-and-brass balustrade to grand arched mahogany screen bay!
	await RoomRender.shot(self, vc, eye, screen + Vector3(0.0, -0.10, 0.0), "loft_01_center_seat")
	# Shot 2: Back-row centre seat looking past front Chesterfield armchairs & balustrade to screen (zero clipping!).
	await RoomRender.shot(self, vc, Vector3(0.0, 1.20, 1.75), screen + Vector3(0.0, -0.15, 0.0), "loft_02_back_seat")
	# Shot 3: Leaning over the mezzanine balustrade to peer down into the glowing two-storey bookshop atrium well!
	await RoomRender.shot(self, vc, Vector3(0.0, 1.52, -2.02), Vector3(0.0, -2.45, -4.95), "loft_03_atrium_down")
	# Shot 4: Port bookshelves, thousands of jewel-toned spines, port rolling brass ladder & brass globe table!
	await RoomRender.shot(self, vc, Vector3(0.55, 1.35, -0.35), Vector3(-4.85, 1.55, -3.55), "loft_04_port_shelves_ladder")
	# Shot 5: Closer hero look at starboard mahogany reading table, banker's lamp, teacup, magnifier & ladder!
	(vc[1] as Camera3D).fov = 72.0
	await RoomRender.shot(self, vc, Vector3(0.65, 1.28, 0.45), Vector3(2.55, 0.85, -0.45), "loft_05_starboard_table")
	# Shot 6: Aft view across woven Nordic rug & Chesterfield chairs to grandfather clock, aft shelves & staircase!
	(vc[1] as Camera3D).fov = 88.0
	await RoomRender.shot(self, vc, Vector3(0.40, 1.42, -1.25), Vector3(-0.75, 1.40, 4.65), "loft_06_aft_clock_stairs")
	# Shot 7: Looking up at exposed walnut attic rafters, collar beams, rain-beaded dormers, Moon & chimney roofs!
	await RoomRender.shot(self, vc, Vector3(0.65, 1.25, 0.15), Vector3(-4.80, 4.30, -3.45), "loft_07_rafters_dormers")

	# 2. Live `lamps` switched to `emerald_banker`!
	host.set_setting("lamps", "emerald_banker")
	_steps(host, 6.0)
	# Shot 8: Wide front-starboard view under emerald banker's lamps & jade cornice uplight!
	await RoomRender.shot(self, vc, Vector3(-0.35, 1.25, 0.35), Vector3(1.45, 1.65, -4.20), "loft_08_emerald_banker")
	# Shot 9: Close-up on starboard banker's lamp, teacup & magnifying glass under emerald banker glow!
	(vc[1] as Camera3D).fov = 70.0
	await RoomRender.shot(self, vc, Vector3(0.75, 1.22, 0.38), Vector3(2.48, 0.88, -0.40), "loft_09_emerald_closeup")
	(vc[1] as Camera3D).fov = 88.0

	# 3. Film playing dimmed view from the dead-centre seat!
	host.set_setting("lamps", "warm_amber")
	host.snapshot_override = {"open": true, "playing": true, "position": 0.5, "duration": 7200.0}
	host.signals.fake("film.brightness", 0.72)
	host.signals.fake("film.colour", Color(0.88, 0.62, 0.38))
	host.signals.fake("playback.playing", 1.0)
	_steps(host, 14.0)
	RoomRender.set_light(screen, 0.018)
	RenderingServer.global_shader_parameter_set("screen_glow", 1.05)
	# Shot 10: Film playing from the dead-centre seat!
	await RoomRender.shot(self, vc, eye, screen, "loft_10_film_playing")

	await RoomRender.close(self, vc)
