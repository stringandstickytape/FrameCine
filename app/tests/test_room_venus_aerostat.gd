extends "res://tests/env_builder_harness.gd"

## Venus aerostat (app/environments/venus_aerostat.env.json; docs/environments/rooms/venus_aerostat.md): gilded
## hammered-copper, brass and cream-enamel Art Nouveau cloud gondola suspended 52 km above Venus inside sunlit
## golden-amber cloud canyons beneath a glowing ivory-and-gold buoyant gas envelope. Built by Gemini 4 Neon Extra High.
## godot --headless --xr-mode off --path app --script res://tests/test_room_venus_aerostat.gd

const RoomRender := preload("res://tests/room_render.gd")
const RoomSound := preload("res://tests/room_sound.gd")
const SoundFixture := preload("res://tests/env_sound_fixture.gd")
const VenusKit := preload("res://scripts/env/systems/kit/venus_aerostat.gd")
const DOC := "res://environments/venus_aerostat.env.json"


func run_tests() -> void:
	test_name = "test_room_venus_aerostat"
	var r := EnvDoc.load_file(DOC)
	check("the document reads cleanly (%s)" % [r["errors"]], (r["errors"] as Array).is_empty())
	var doc: Dictionary = r["doc"]
	if doc.is_empty():
		return
	if OS.get_environment("VENUS_RENDER_ONLY") == "":
		var room := await check_room("venus_aerostat", doc)
		room.host.auto = false
		_by_part(room)
		await _built_and_budgets(room, doc)
		_settings_cues_and_clouds(room)
		_sound(room)
		await done(room)
		await RoomSound.check_level(self, self, "venus_aerostat", doc)
	await _render(doc)


## Verifies architecture, custom pieces, budgets (draws <= 34, tris <= 90k, lights == 0, blend <= 1.0, fast build),
## physics clearance (>= 0.5 m from origin), Sabine acoustics alpha, and bake hooks.
func _built_and_budgets(room: Node3D, doc: Dictionary) -> void:
	var host: Node = room.host
	var rm: Dictionary = doc.get("room", {})
	check("credited to Gemini 4 Neon Extra High in world category",
			str(rm.get("author", "")) == "Gemini 4 Neon Extra High" and str(rm.get("category", "")) == "world")
	check("description under 200 chars (%d)" % str(rm.get("description", "")).length(),
			str(rm.get("description", "")).length() <= 200 and str(rm.get("description", "")).length() > 20)

	var stats := EnvChecks.measure(room)
	check("strict budgets: draws <= 34, tris <= 90k, lights == 0, particles == 0 (%s)" % [stats],
			int(stats["draws"]) <= 34 and int(stats["triangles"]) <= 90000 and int(stats["lights"]) == 0
			and int(stats["particles"]) == 0)

	var blend: Dictionary = await EnvChecks.blend_layers(self, room)
	print("  blend: %s (budget %.2f)" % [blend, EnvChecks.BLEND_BUDGET])
	check("blended layers within budget (mean %.2f <= %.2f)" % [float(blend["mean"]), EnvChecks.BLEND_BUDGET],
			float(blend["mean"]) <= EnvChecks.BLEND_BUDGET)

	# Second-build timing against BUILD_BUDGET (as test_environments.gd checks).
	var t0 := Time.get_ticks_usec()
	var second: Node3D = EnvRoom.new()
	second.doc = doc
	root.add_child(second)
	var build_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var units := EnvChecks.build_units(build_ms)
	print("  build: %.1f ms (%.1f pace units, budget %.1f)" % [build_ms, units, EnvChecks.BUILD_BUDGET])
	check("builds within BUILD_BUDGET (%.1f <= %.1f)" % [units, EnvChecks.BUILD_BUDGET],
			units <= EnvChecks.BUILD_BUDGET)
	second.queue_free()
	await process_frame

	# Domestic shell left to kit; every expected gondola & exterior mesh built cleanly.
	for n: String in ["Walls", "Floor", "Ceiling", "Trim"]:
		check("domestic %s left to the kit" % n, room.get_node_or_null(n) == null)
	for n: String in ["PieceStatic", "PieceSoft", "PieceCove", "PieceLamps", "PieceGlass", "PieceWindows",
			"PieceClock", "VenusCloudSphere", "VenusEnvelope", "VenusCompanions", "VenusCloudShafts"]:
		check("room has %s" % n, room.find_child(n, true, false) != null)

	var kit: Node = host.system("gondola")
	check("kit builds with zero problems (%s)" % [kit.problems()], kit != null and kit.problems().is_empty())

	# VenusCloudSphere uses dedicated opaque cloud canyon shader (zero alpha blend).
	var clouds := room.find_child("VenusCloudSphere", true, false) as MeshInstance3D
	var cm := clouds.mesh.surface_get_material(0) as ShaderMaterial if clouds != null else null
	check("VenusCloudSphere uses opaque env_venus_clouds.gdshader",
			cm != null and cm.shader == VenusKit.CLOUDS_SHADER and not EnvChecks.blends(cm))

	# VenusCloudShafts uses env_world_shaft.gdshader and is see-through.
	var shafts := room.find_child("VenusCloudShafts", true, false) as MeshInstance3D
	var sm := shafts.mesh.surface_get_material(0) as ShaderMaterial if shafts != null else null
	check("VenusCloudShafts uses env_world_shaft.gdshader in env_see_through",
			shafts != null and sm != null and sm.shader == VenusKit.SHAFT_SHADER
			and shafts.is_in_group("env_see_through"))

	# 4 distant companion aerostats in VenusCompanions MultiMesh.
	var comp := room.find_child("VenusCompanions", true, false) as MultiMeshInstance3D
	check("VenusCompanions has 4 distant floating aerostats",
			comp != null and int(comp.get_meta("instances", 0)) == 4)

	# 9 lounge seats (3x3), viewer's own seat at origin.
	var seats: Array[Transform3D] = room.room_seat_transforms()
	var own := seats.any(func(t: Transform3D) -> bool: return t.origin.length() < 0.001)
	check("nine lounge armchairs (%d), viewer seat at origin" % seats.size(),
			seats.size() == 9 and own and str(host.system("seats").params["model"]) == "lounge")

	# 8 hidden bake lamps matching bake_lamps: 8, and static meshes under MAX_ATLAS.
	var bake_omnis := room.find_children("KitLamp*", "OmniLight3D", true, false)
	var all_hidden := bake_omnis.all(func(l: Node) -> bool: return not (l as Light3D).visible)
	check("8 hidden tulip sconce bake lights (%d)" % bake_omnis.size(), bake_omnis.size() == 8 and all_hidden)
	var largest := Vector2i.ZERO
	for mi: MeshInstance3D in room.static_meshes():
		largest = largest.max((mi.mesh as ArrayMesh).lightmap_size_hint)
	print("  bake: %d static meshes, largest atlas %s" % [room.static_meshes().size(), largest])
	check("static meshes for bake, atlas under %d (%s)" % [MAX_ATLAS, largest],
			largest.x > 0 and largest.x <= MAX_ATLAS and largest.y <= MAX_ATLAS)
	check("collision shapes present (%d)" % room.collision_shapes().size(), room.collision_shapes().size() > 20)

	# All kit prop physics boxes stay >= 0.5 m clear of the viewer's origin (0, 0, 0).
	var kit_shapes: Array = kit.collision_shapes()
	var min_clear := INF
	for sh: Array in kit_shapes:
		var bs := sh[0] as BoxShape3D
		var xf: Transform3D = sh[1]
		var local_o := xf.affine_inverse() * Vector3.ZERO
		var half := bs.size * 0.5
		var clamped := local_o.clamp(-half, half)
		min_clear = minf(min_clear, local_o.distance_to(clamped))
	check("kit physics boxes (%d) stay >= 0.5 m clear of origin (nearest %.2f m)" % [kit_shapes.size(), min_clear],
			kit_shapes.size() >= 10 and min_clear >= 0.5)

	# Sabine mean absorption alpha for film acoustics strictly inside 0.05..0.75.
	var sr: Dictionary = room.get_sound_room()
	var box: AABB = sr["box"]
	var vol := box.size.x * box.size.y * box.size.z
	var area := 2.0 * (box.size.x * box.size.y + box.size.y * box.size.z + box.size.z * box.size.x)
	var alpha := 0.161 * vol / (area * float(sr["rt60"]))
	print("  acoustics: box %.1fx%.1fx%.1f m, rt60 %.2f s, Sabine alpha %.2f"
			% [box.size.x, box.size.y, box.size.z, float(sr["rt60"]), alpha])
	check("Sabine absorption alpha in 0.05..0.75 (%.2f)" % alpha, alpha >= 0.05 and alpha <= 0.75)


## Tests live settings (cloud_light, cabin_coves, lightning), Flickering lights safety, Motion freeze, working
## PieceClock, and starting/ended ritual cues + chime.
func _settings_cues_and_clouds(room: Node3D) -> void:
	var host: Node = room.host
	var kit: Node = host.system("gondola")
	var clouds := room.find_child("VenusCloudSphere", true, false) as MeshInstance3D
	var cm := clouds.mesh.surface_get_material(0) as ShaderMaterial

	# 1. Working astronomical gondola clock (PieceClock).
	var hands: Array = kit.clock_hands()
	check("working astronomical clock exposes valid hands (%s)" % [hands],
			hands.size() == 2 and is_finite(float(hands[0])) and is_finite(float(hands[1])))

	# 2. Cabin coves setting: Warm brass / Botanical emerald / Dim.
	host.set_setting("cabin_coves", "brass")
	_steps(host, 2.0)
	var st_b: Dictionary = kit.cove_state()
	var c_b: Color = st_b.get("colour", Color.BLACK)
	check("cabin_coves=brass glows warm brass gold (%s)" % c_b, c_b.r > c_b.b * 1.4 and float(st_b.get("glow", 0.0)) > 0.8)

	host.set_setting("cabin_coves", "emerald")
	_steps(host, 2.0)
	var st_e: Dictionary = kit.cove_state()
	var c_e: Color = st_e.get("colour", Color.BLACK)
	check("cabin_coves=emerald shifts coves to botanical emerald (%s)" % c_e, c_e.g > c_e.r * 1.8)

	host.set_setting("cabin_coves", "dim")
	_steps(host, 2.0)
	var st_d: Dictionary = kit.cove_state()
	check("cabin_coves=dim lowers cove glow (%.2f)" % float(st_d.get("glow", 1.0)),
			float(st_d.get("glow", 1.0)) < 0.45 and float(st_d.get("glow", 0.0)) > 0.1)
	host.set_setting("cabin_coves", "brass")
	_steps(host, 1.0)

	# 3. Cloud light mood: Amber noon / Copper sunset / Stormy gold.
	host.set_setting("cloud_light", "amber")
	_steps(host, 4.0)
	var hor_a: Color = cm.get_shader_parameter("horizon_col")
	host.set_setting("cloud_light", "copper")
	_steps(host, 6.0)
	var hor_c: Color = cm.get_shader_parameter("horizon_col")
	check("cloud_light=copper warms horizon deeper orange-copper (amber %s -> copper %s)" % [hor_a, hor_c],
			str(clouds.get_meta("cloud_mood", "")) == "copper" and hor_c.g < hor_a.g - 0.1)

	host.set_setting("cloud_light", "stormy")
	_steps(host, 6.0)
	var hor_s: Color = cm.get_shader_parameter("horizon_col")
	var storm_l := float(clouds.get_meta("lightning_level", 0.0))
	check("cloud_light=stormy deepens clouds and strengthens distant lightning (%.2f)" % storm_l,
			str(clouds.get_meta("cloud_mood", "")) == "stormy" and hor_s.r < hor_a.r - 0.1 and storm_l > 0.8)
	host.set_setting("cloud_light", "amber")
	_steps(host, 4.0)

	# 4. Distant sheet lightning respects both setting.lightning == "off" AND Flickering lights == false!
	host.set_setting("lightning", "off")
	_steps(host, 1.5)
	check("lightning=off turns sheet lightning strictly off (%.3f)" % float(cm.get_shader_parameter("lightning_level")),
			float(cm.get_shader_parameter("lightning_level")) == 0.0)
	host.set_setting("lightning", "glow")
	host.set_setting("flicker", false)
	_steps(host, 1.5)
	check("Flickering lights off forces sheet lightning strictly off (%.3f)"
			% float(cm.get_shader_parameter("lightning_level")),
			float(cm.get_shader_parameter("lightning_level")) == 0.0)
	host.set_setting("flicker", true)
	_steps(host, 3.0)
	check("sheet lightning returns softly when re-enabled (%.2f)" % float(cm.get_shader_parameter("lightning_level")),
			float(cm.get_shader_parameter("lightning_level")) > 0.4)

	# 5. Motion setting freezes cloud drift cleanly at 0.
	host.set_setting("motion", 1.0)
	_steps(host, 1.0)
	var clk0 := float(clouds.get_meta("cloud_clock", 0.0))
	_steps(host, 1.0)
	var clk1 := float(clouds.get_meta("cloud_clock", 0.0))
	host.set_setting("motion", 0.0)
	_steps(host, 1.5)
	var clk2 := float(clouds.get_meta("cloud_clock", 0.0))
	check("Motion scales cloud drift and freezes at 0 (%.2f -> %.2f -> %.2f)" % [clk0, clk1, clk2],
			clk1 > clk0 + 0.5 and absf(clk2 - clk1) < 0.01)
	host.set_setting("motion", 1.0)

	# 6. Pre-show ritual: starting dims house lamps & accent, rings departure chime, mellows exterior; ended restores!
	SoundFixture.finish_loading(room)
	var chime: Node = host.system("chime")
	var plays_before := int(chime.plays)
	host.timeline.state = ""
	host.snapshot_override = {"open": false}
	_steps(host, 10.0)
	check("pre-show: house lamps full (%.2f)" % float(host.param("light.house_lamps")),
			float(host.param("light.house_lamps")) > 0.95)

	host.snapshot_override = {"open": true, "playing": true, "position": 0.5, "duration": 7200.0}
	_steps(host, 14.0)
	var ext_play := float(clouds.get_meta("exterior_level", 1.0))
	check("film playing: house lamps dim to 0.15, accent 0.45, chime plays (%d->%d), exterior mellows (%.2f)"
			% [plays_before, int(chime.plays), ext_play],
			absf(float(host.param("light.house_lamps")) - 0.15) < 0.03
			and absf(float(host.param("light.accent")) - 0.45) < 0.03
			and int(chime.plays) > plays_before and ext_play < 0.72)

	host.snapshot_override = {"open": true, "playing": false, "ended": true, "position": 7200.0, "duration": 7200.0}
	_steps(host, 10.0)
	check("after film: house lamps & accent restore to 1.0 (%.2f, %.2f)"
			% [float(host.param("light.house_lamps")), float(host.param("light.accent"))],
			float(host.param("light.house_lamps")) > 0.95 and float(host.param("light.accent")) > 0.95)


func _sound(room: Node3D) -> void:
	RoomSound.check_beds(self, "venus_aerostat", room,
			{"aerostat_hum": "aerostat_hum", "thunder": "rumble", "chime": "chime"}, "hull")


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
	RoomRender.set_light(screen, 0.05)
	var vc := await RoomRender.open(self, doc, 88.0)
	var host: Node = (vc[2] as Node).host
	var cam := vc[1] as Camera3D
	SoundFixture.finish_loading(vc[2])

	# Pre-show state: full warm Art Nouveau house lamps, amber noon cloud canyons, warm brass coves.
	host.snapshot_override = {"open": false}
	host.timeline.state = "preshow"
	host.signals.fake("playback.playing", 0.0)
	host.signals.fake("film.brightness", 0.0)
	host.set_setting("cloud_light", "amber")
	host.set_setting("cabin_coves", "brass")
	host.set_setting("lightning", "glow")
	_steps(host, 6.0)
	RoomRender.set_light(screen, 0.05)
	RenderingServer.global_shader_parameter_set("screen_glow", 0.0)

	# 1. Front gondola hero overview from aft-centre gallery: lounge chairs, compass rose, screen proscenium & clouds!
	cam.fov = 88.0
	await RoomRender.shot(self, vc, Vector3(0.0, 2.15, 4.35), Vector3(0.0, 2.25, -6.90), "venus_01_front_gondola")

	# 2. Viewer's own seat view looking straight at screen proscenium & flanking golden cloud bays!
	cam.fov = 88.0
	await RoomRender.shot(self, vc, Vector3(0.0, 1.20, 0.0), screen, "venus_02_seat_view")

	# 3. Looking UP through the 7.1 m skylight oculus at the vast glowing ivory-and-gold buoyant gas envelope & rigging!
	cam.fov = 95.0
	await RoomRender.shot(self, vc, Vector3(0.0, 1.45, 0.65), Vector3(0.0, 20.5, -2.5), "venus_03_look_up_envelope")

	# 4. Looking out starboard panoramic bays at golden Venus cloud canyons, sunbeams & distant companion aerostats!
	cam.fov = 82.0
	await RoomRender.shot(self, vc, Vector3(-0.60, 1.85, 0.25), Vector3(24.0, 2.6, -9.5), "venus_04_starboard_canyons")

	# 5. Looking port-forward at the hanging geodesic glass botanical terrarium with emerald ferns against golden clouds!
	cam.fov = 76.0
	await RoomRender.shot(self, vc, Vector3(-0.85, 1.95, 1.15), Vector3(-5.05, 2.55, -1.25), "venus_05_port_terrarium")

	# 6. Aft airlock hatch with spoked brass wheel, working astronomical clock (PieceClock) & spectrometer console!
	cam.fov = 84.0
	await RoomRender.shot(self, vc, Vector3(-0.85, 1.95, -0.85), Vector3(1.15, 2.05, 6.20), "venus_06_aft_airlock_console")

	# 7. Copper sunset variant: deep molten copper-orange cloud canyons & warm glowing aerostats!
	host.set_setting("cloud_light", "copper")
	_steps(host, 10.0)
	cam.fov = 88.0
	await RoomRender.shot(self, vc, Vector3(-1.85, 2.15, 3.65), Vector3(2.85, 2.25, -5.80), "venus_07_copper_sunset")

	# 8. Botanical emerald coves + Stormy gold cloud mood + closeup of terrarium & proscenium arch!
	host.set_setting("cabin_coves", "emerald")
	host.set_setting("cloud_light", "stormy")
	_steps(host, 10.0)
	cam.fov = 86.0
	await RoomRender.shot(self, vc, Vector3(2.25, 2.05, 3.55), Vector3(-2.45, 2.45, -4.60),
			"venus_08_emerald_coves_stormy")

	# 9. Film-playing dimmed view from viewer's seat: warm brass coves at floor, glowing picture, mellow golden clouds!
	host.set_setting("cabin_coves", "brass")
	host.set_setting("cloud_light", "amber")
	host.snapshot_override = {"open": true, "playing": true, "position": 120.0, "duration": 7200.0}
	host.timeline.state = "playing"
	host.signals.fake("playback.playing", 1.0)
	host.signals.fake("film.brightness", 0.72)
	host.signals.fake("film.colour", Color(0.92, 0.64, 0.36))
	_steps(host, 12.0)
	RoomRender.set_light(screen, 0.016)
	RenderingServer.global_shader_parameter_set("screen_glow", 1.0)
	cam.fov = 88.0
	await RoomRender.shot(self, vc, Vector3(0.0, 1.20, 0.0), screen, "venus_09_film_playing")

	await RoomRender.close(self, vc)
