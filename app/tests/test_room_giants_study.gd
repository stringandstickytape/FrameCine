extends "res://tests/env_builder_harness.gd"

## Giant's study (app/environments/giants_study.env.json; docs/environments/rooms/giants_study.md): an Other Worlds
## room built by Gemini 4 Neon Extra High. A cozy rainy late-night Victorian study at 10:1 miniature scale where you
## sit ten centimetres tall on stitched felt cushions atop a giant woven cork-and-felt coaster on a mahogany desk.
## godot --headless --xr-mode off --path app --script res://tests/test_room_giants_study.gd

const RoomRender := preload("res://tests/room_render.gd")
const RoomSound := preload("res://tests/room_sound.gd")
const GiantsStudy := preload("res://scripts/env/systems/kit/giants_study.gd")
const DOC := "res://environments/giants_study.env.json"


func run_tests() -> void:
	test_name = "test_room_giants_study"
	var r := EnvDoc.load_file(DOC)
	check("the document reads (%s)" % [r["errors"]], (r["errors"] as Array).is_empty())
	var doc: Dictionary = r["doc"]
	if doc.is_empty():
		return
	if OS.get_environment("STUDY_RENDER_ONLY") == "":
		var room := await check_room("giants_study", doc)
		room.host.auto = false
		_by_part(room)
		await _built_and_budgets(room, doc)
		_clock_and_props(room)
		_lamp_and_cues(room)
		_rain_and_steam(room)
		_sound(room)
		await done(room)
		await _build_speed(doc)
		await RoomSound.check_level(self, self, "giants_study", doc)
	await _render(doc)


## Figures, metadata, meshes, bake lights, clear coaster origin and blended-layer budget.
func _built_and_budgets(room: Node3D, doc: Dictionary) -> void:
	var host: Node = room.host
	var stats := EnvChecks.measure(room)
	print("  measured: %s" % [stats])
	check("within Giant's study tight budget: <= 34 draws, <= 90k tris, 0 live lights, <= 1200 particles (%s)" % [stats],
			int(stats["draws"]) <= 34 and int(stats["triangles"]) <= 90000 and int(stats["lights"]) == 0
			and int(stats["particles"]) <= 1200 and float(stats["texture_mb"]) <= 48.0)

	var meta: Dictionary = doc.get("room", {})
	check("category is world (%s)" % str(meta.get("category", "")), str(meta.get("category", "")) == "world")
	check("author is Gemini 4 Neon Extra High", str(meta.get("author", "")) == "Gemini 4 Neon Extra High")
	check("description <= 200 chars (%d)" % str(meta.get("description", "")).length(),
			str(meta.get("description", "")).length() <= 200)

	var kit: Node = host.system("study")
	check("kit builds cleanly with zero problems (%s)" % [kit.problems()], kit != null and kit.problems().is_empty())
	for n: String in ["PieceStatic", "PieceSoft", "PieceLamps", "PieceCove", "PieceClock", "PieceGlass",
			"PieceWindows", "LeatherBlotter", "LampCone", "RainPane", "Fall0", "Fog"]:
		check("room has %s" % n, room.find_child(n, true, false) != null)
	for n: String in ["Walls", "Floor", "Ceiling", "Trim", "Doorway", "Screen"]:
		check("domestic %s left to the kit" % n, room.get_node_or_null(n) == null)

	var cone := room.find_child("LampCone", true, false) as MeshInstance3D
	check("LampCone is in group env_see_through", cone != null and cone.is_in_group("env_see_through"))

	# Hidden bake lights: 8 desk/study omni lamps + 1 moonlight spot through the colossal left window, all hidden.
	var omnis := room.find_children("KitLamp*", "OmniLight3D", true, false)
	var spots := room.find_children("KitSpot*", "SpotLight3D", true, false)
	var all_hidden := true
	for l: Node in omnis + spots:
		all_hidden = all_hidden and not (l as Light3D).visible
	check("bake lights present (8 omnis, 1 moonlight spot) and all hidden (%d, %d)" % [omnis.size(), spots.size()],
			omnis.size() == 8 and spots.size() == 1 and all_hidden)

	# Static meshes for the bake, each with an atlas under MAX_ATLAS; sound room box; collision shapes.
	var largest := Vector2i.ZERO
	for mi: MeshInstance3D in room.static_meshes():
		largest = largest.max((mi.mesh as ArrayMesh).lightmap_size_hint)
	print("  bake: %d static meshes, largest atlas %s" % [room.static_meshes().size(), largest])
	check("static meshes for bake with atlas <= %d (%s)" % [MAX_ATLAS, largest],
			not room.static_meshes().is_empty() and largest.x > 0 and largest.x <= MAX_ATLAS and largest.y <= MAX_ATLAS)
	check("sound room box and physics shapes present (%d)" % room.collision_shapes().size(),
			room.get_sound_room().has("box") and room.collision_shapes().size() >= 15)

	# Keep all kit physics boxes >= 0.5 m clear of the viewer's coaster origin (0, 0, 0).
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

	# Blended layers over the forward view within BLEND_BUDGET.
	var bl := await EnvChecks.blend_layers(self, room)
	print("  blend_layers: %s (budget %.2f)" % [bl, EnvChecks.BLEND_BUDGET])
	check("blend_layers mean <= %.2f (%s)" % [EnvChecks.BLEND_BUDGET, bl],
			float(bl["mean"]) <= EnvChecks.BLEND_BUDGET)


## The 2.3 m gleaming brass pocket watch dial (`PieceClock`) keeps real wall time.
func _clock_and_props(room: Node3D) -> void:
	var kit: Node = room.host.system("study")
	var hands: Array = kit.clock_hands()
	check("pocket watch has live hour and minute hands (%s)" % [hands], hands.size() == 2)
	if hands.size() == 2:
		var t := Time.get_time_dict_from_system()
		var mins := float(t["minute"]) + float(t["second"]) / 60.0
		var hrs := fmod(float(t["hour"]), 12.0) + mins / 60.0
		var want_h := TAU * hrs / 12.0
		var want_m := TAU * mins / 60.0
		var err_h := absf(wrapf(float(hands[0]) - want_h, -PI, PI))
		var err_m := absf(wrapf(float(hands[1]) - want_m, -PI, PI))
		check("pocket watch hands match real wall time (err h=%.3f m=%.3f rad)" % [err_h, err_m],
				err_h < 0.05 and err_m < 0.08)


## Live `desk_lamp` setting shifts the banker's shade (`PieceCove`) and downward volumetric cone (`LampCone`) cleanly
## across Warm brass / Green banker's glow / Dim; film cues dim house & hearth lights while keeping cove_floor warm.
func _lamp_and_cues(room: Node3D) -> void:
	var host: Node = room.host
	var kit: Node = host.system("study")
	var cone := room.find_child("LampCone", true, false) as MeshInstance3D
	var cone_m := cone.mesh.surface_get_material(0) as ShaderMaterial

	host.timeline.state = ""
	host.snapshot_override = {"open": false}
	host.set_setting("desk_lamp", "warm")
	_steps(host, 8.0)
	var st_warm: Dictionary = kit.cove_state()
	var c_warm: Color = st_warm.get("colour", Color.BLACK)
	check("desk_lamp=warm glows warm golden brass (%s, glow %.2f)" % [c_warm, float(st_warm.get("glow", 0.0))],
			c_warm.r > 0.9 and c_warm.g > 0.62 and c_warm.r > c_warm.b * 2.5 and float(st_warm.get("glow", 0.0)) > 1.1)

	host.set_setting("desk_lamp", "green")
	_steps(host, 5.0)
	var st_green: Dictionary = kit.cove_state()
	var c_green: Color = st_green.get("colour", Color.BLACK)
	var cone_green: Color = cone_m.get_shader_parameter("shaft_colour")
	check("desk_lamp=green shifts shade to emerald banker's glow (%s)" % c_green,
			c_green.g > 0.68 and c_green.g > c_green.r * 5.0 and c_green.g > c_green.b * 2.0)
	check("LampCone tints with green banker's glow (%s)" % cone_green, cone_green.g > cone_green.r * 1.4)

	host.set_setting("desk_lamp", "dim")
	_steps(host, 5.0)
	var st_dim: Dictionary = kit.cove_state()
	var lvl_dim := float(cone_m.get_shader_parameter("shaft_level"))
	check("desk_lamp=dim lowers shade and cone brightness (cove %.2f, cone %.3f)" % [
			float(st_dim.get("glow", 9.0)), lvl_dim],
			float(st_dim.get("glow", 9.0)) < float(st_warm.get("glow", 0.0)) * 0.4 and lvl_dim < 0.08)

	host.set_setting("desk_lamp", "warm")
	_steps(host, 5.0)

	# Film cues: house lamps & accent dim cleanly, cove_floor 0.45 keeps a cozy desk lamp ember, all back at end.
	host.snapshot_override = {"open": true, "playing": true, "position": 0.5, "duration": 7200.0}
	_steps(host, 14.0)
	var house_film := float(host.param("light.house_lamps"))
	var accent_film := float(host.param("light.accent"))
	var cove_film := float(kit.cove_state().get("glow", 0.0))
	check("during film: house lamps dim (%.2f), hearth accent dims (%.2f), shade holds cove_floor (%.2f)" % [
			house_film, accent_film, cove_film],
			absf(house_film - 0.18) < 0.03 and absf(accent_film - 0.45) < 0.03 and cove_film > 0.48 and cove_film < 0.66)

	host.snapshot_override = {"open": true, "playing": false, "ended": true, "position": 7200.0, "duration": 7200.0}
	_steps(host, 10.0)
	check("after film: house lamps (%.2f) and hearth accent (%.2f) return to 1.0" % [
			float(host.param("light.house_lamps")), float(host.param("light.accent"))],
			float(host.param("light.house_lamps")) > 0.96 and float(host.param("light.accent")) > 0.96)


## Rain falls strictly outside the giant leaded study window (`x <= -16.5 m`, zero inward wind), 2 rain-beaded window
## panes sit cleanly at `x = -15.30 m`, `rain` setting switches live, and teacup steam fog stays localized over the cup.
func _rain_and_steam(room: Node3D) -> void:
	var host: Node = room.host
	var w: Node = host.system("weather")
	check("weather draws falling rain and merged rain-beaded window panes",
			w != null and str(w.params["falls"]) == "rain" and w.pane() != null and (w.params["panes"] as Array).size() == 2)
	var wind: Array = w.params["wind"]
	var outside_ok := not (w.areas() as Array).is_empty() and float(wind[0]) <= 0.0
	for a: Array in w.areas():
		var box: AABB = a[2]
		if box.end.x > -16.5:
			outside_ok = false
	check("all rain areas stay strictly outside x <= -16.5 m with zero inward wind", outside_ok)

	host.set_setting("rain", "dry")
	_steps(host, 120.0, 0.5)
	check("rain=dry clears the rain (%.2f)" % float(w.rain_amount()), float(w.rain_amount()) < 0.05)
	host.set_setting("rain", "drizzle")
	_steps(host, 90.0, 0.5)
	var driz := float(w.rain_amount())
	check("rain=drizzle settles at light drizzle (%.2f)" % driz, driz > 0.20 and driz < 0.40)
	host.set_setting("rain", "steady")
	_steps(host, 90.0, 0.5)
	check("rain=steady restores steady rain (%.2f)" % float(w.rain_amount()), float(w.rain_amount()) > 0.85)

	# Delicate warm steam fog localized tightly over the giant porcelain teacup.
	var atm: Node = host.system("atmosphere")
	var fog_n: Node3D = atm.fog_node() if atm != null else null
	check("warm steam fog localized over the giant teacup (2 layers, 2.2 x 2.2 m)",
			fog_n != null and fog_n.visible and fog_n.get_child_count() == 2
			and fog_n.position.distance_to(Vector3(-5.60, 2.80, 0.95)) < 0.05)


## Sound beds, cinema acoustics, watch_tick setting & weather.rain binding.
func _sound(room: Node3D) -> void:
	RoomSound.check_beds(self, "giants_study", room, {
			"watch": "giant_clock", "rain": "rain_glass", "hearth": "fire", "cat": "purr"}, "cinema")
	RoomSound.check_follows(self, "giants_study", room, "rain", "weather.rain")
	RoomSound.check_setting(self, "giants_study", room, "watch", "watch_tick", "quiet", "soft")


## Second build time (after procedural cache warm-up) stays well inside EnvChecks.BUILD_BUDGET.
func _build_speed(doc: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	var room2: Node3D = EnvRoom.new()
	room2.doc = doc
	root.add_child(room2)
	await process_frame
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var units := EnvChecks.build_units(ms)
	print("  build_time: %.1f ms (%.1f pace units, budget %.1f)" % [ms, units, EnvChecks.BUILD_BUDGET])
	check("build time <= %.1f pace units (%.1f)" % [EnvChecks.BUILD_BUDGET, units], units <= EnvChecks.BUILD_BUDGET)
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

	# 1. Pre-show, Warm brass desk lamp, steady rain outside.
	host.snapshot_override = {"open": false}
	host.set_setting("desk_lamp", "warm")
	host.set_setting("rain", "steady")
	_steps(host, 12.0)
	RoomRender.set_light(screen, 0.055)
	RenderingServer.global_shader_parameter_set("screen_glow", 0.22)

	# Shot 1: Front coaster seat looking at propped pocket display, brass ruler, notebook & green blotter.
	await RoomRender.shot(self, vc, eye, screen + Vector3(0.0, -0.05, 0.0), "study_preshow_seat")
	# Shot 2: Looking left at towering 5.8 m book stack, giant steaming porcelain teacup, 2.3 m pocket watch & pen.
	await RoomRender.shot(self, vc, eye, Vector3(-5.2, 1.75, -1.55), "study_preshow_left")
	# Shot 3: Looking right at soaring 7.8 m banker's lamp, inkwell, pencil pot, spectacles, magnifier & paperclip.
	await RoomRender.shot(self, vc, eye, Vector3(4.8, 2.35, -1.65), "study_preshow_right")
	# Shot 4: Looking left-up through colossal mullioned leaded-glass window onto rainy moonlit night sky.
	await RoomRender.shot(self, vc, Vector3(-0.2, 1.55, -2.0), Vector3(-15.5, 4.2, -3.5), "study_preshow_window")
	# Shot 5: Closer hero look at the 2.3 m working pocket watch dial, fountain pen gold nib & steaming teacup.
	(vc[1] as Camera3D).fov = 68.0
	await RoomRender.shot(self, vc, Vector3(-0.2, 1.40, 0.45), Vector3(-4.6, 1.40, -1.85), "study_closeup_watch_tea")
	# Shot 6: Aft & back-right view across coaster cushions, mahogany desk edge, giant chair back & hearth.
	(vc[1] as Camera3D).fov = 88.0
	await RoomRender.shot(self, vc, Vector3(-1.4, 1.55, -1.6), Vector3(7.2, 1.4, 5.8), "study_preshow_aft")
	# Shot 7: Clear view of the glowing cozy Victorian fireplace hearth, charred logs, flames & bookshelves!
	(vc[1] as Camera3D).fov = 70.0
	await RoomRender.shot(self, vc, Vector3(3.4, 1.65, 2.2), Vector3(15.2, 1.75, 5.6), "study_preshow_hearth")
	(vc[1] as Camera3D).fov = 88.0

	# 2. Live `desk_lamp` switched to `Green banker's glow`!
	host.set_setting("desk_lamp", "green")
	_steps(host, 6.0)
	# Shot 8: Front-right composition with iconic glowing emerald banker's lamp & green-warm volumetric cone.
	await RoomRender.shot(self, vc, eye, Vector3(1.8, 2.1, -3.8), "study_green_lamp")
	# Shot 9: Looking right at emerald banker's shade, pull chain, crystal inkwell, coloured pencils & spectacles.
	await RoomRender.shot(self, vc, eye, Vector3(5.0, 2.55, -1.55), "study_green_right")

	# 3. Film playing dimmed view (screen spill on green leather blotter & brass bezel, desk lamp at cove_floor).
	host.snapshot_override = {"open": true, "playing": true, "position": 0.5, "duration": 7200.0}
	host.signals.fake("film.brightness", 0.72)
	host.signals.fake("film.colour", Color(0.88, 0.62, 0.38))
	host.signals.fake("playback.playing", 1.0)
	_steps(host, 14.0)
	RoomRender.set_light(screen, 0.018)
	RenderingServer.global_shader_parameter_set("screen_glow", 1.10)
	# Shot 10: Film playing from the front coaster seat!
	await RoomRender.shot(self, vc, eye, screen, "study_film_seat")

	await RoomRender.close(self, vc)
