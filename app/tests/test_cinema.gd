extends SceneTree

## Tests for the cinema (environments/cinema.gd) in the real main scene: its parts and their budget (draw calls by
## surface, vertices), the modelled seats (count, curved rows, every seat back under the sight line to the screen,
## the tint per seat, the viewer's own seat folded away and another after a seat change), the static parts ready for
## a lightmap bake (gi_mode static, UV2 inside the atlas, a size hint), the bake lights (static, hidden), the lit
## library materials and their fill and lamps, the bake hooks (set_baking, set_baked, a LightmapGI noticed), the
## house lights following the room light, the curtains and the beam following playback, the beam reaching the
## screen's corners. Needs a renderer (a MultiMesh keeps no instances without one): lavapipe under xvfb on the PC.
## Run: godot --xr-mode off --path app --script res://tests/test_cinema.gd

const Cinema := preload("res://environments/cinema.gd")
const MaterialLibrary := preload("res://scripts/env/material_library.gd")

## Draw calls the room may make (one per mesh surface, the particles one).
const DRAW_BUDGET := 24
## Vertices one seat may have, and the whole room.
const SEAT_VERTS := 800
const ROOM_VERTS := 260000

var _failures := 0
var _checks := 0
var main: Node3D


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	# The room as built, before any lightmap: rooms light themselves on first showing (scripts/env/room_lightmaps.gd),
	# which would drop the stand-in lamps and most of the fill this test looks at.
	main.features.lightmaps.set_enabled(false)
	await _frames(5)
	main.set_environment("cinema")
	main.open_path("stub://flat_mono")
	await _frames(5)
	var env: Node3D = main.env
	_check("the cinema is on show", env != null and env.get_script() == Cinema)

	# Parts and budget.
	var names: Array = env.get_children().map(func(n: Node) -> String: return str(n.name))
	for n: String in ["Floor", "Walls", "FrontWall", "Ceiling", "WallPanels", "Stage", "Curtains", "Doors", "Brass",
			"HouseLamps", "StepLights", "ExitSigns", "BoothWindow", "Seats", "BakeLights", "Beam", "ScreenBorder"]:
		_check("has %s" % n, n in names)
	var draws := 0
	var verts := 0
	for g in env.find_children("*", "GeometryInstance3D", true, false):
		if g is MeshInstance3D:
			var m := (g as MeshInstance3D).mesh
			draws += m.get_surface_count()
			verts += _verts(m)
		elif g is MultiMeshInstance3D:
			var mm := (g as MultiMeshInstance3D).multimesh
			draws += mm.mesh.get_surface_count()
			verts += _verts(mm.mesh) * mm.instance_count
		elif g is GPUParticles3D:
			draws += 1
	_check("draw calls within budget (%d <= %d)" % [draws, DRAW_BUDGET], draws <= DRAW_BUDGET)
	_check("vertices within budget (%d <= %d)" % [verts, ROOM_VERTS], verts <= ROOM_VERTS)

	# Seats.
	var seats_node := env.get_node("Seats") as MultiMeshInstance3D
	var mm := seats_node.multimesh
	var rows := Cinema.ROWS_FRONT + Cinema.ROWS_BACK + 1
	_check("%d seats, one MultiMesh (%d)" % [Cinema.SEATS_PER_ROW * rows, mm.instance_count],
			mm.instance_count == Cinema.SEATS_PER_ROW * rows and mm.instance_count >= 280)
	_check("a modelled seat: two surfaces, %d vertices (<= %d)" % [_verts(mm.mesh), SEAT_VERTS],
			mm.mesh.get_surface_count() == 2 and _verts(mm.mesh) > 300 and _verts(mm.mesh) <= SEAT_VERTS)
	var seats: Array[Vector3] = env.get_seats()
	_check("get_seats lists every seat, the viewer's at the origin", seats.size() == mm.instance_count
			and seats.has(Vector3.ZERO))
	# The auditorium system builds the seats. A MultiMesh keeps no instance data without a renderer (these tests run
	# headless), so the checks read the system: its seat variation and the seat it folded.
	var hall: Node = env.host.systems_of_kind("builder").filter(func(n: Node) -> bool: return n.get("_hidden_seat") != null).front()
	_check("each seat's velvet a little different (variation %.2f, per-seat colours)" % float(hall.params["seat_variation"]),
			mm.use_colors and float(hall.params["seat_variation"]) > 0.0)
	var xforms := Cinema.seat_transforms()
	var end := xforms[Cinema.ROWS_BACK * Cinema.SEATS_PER_ROW + Cinema.SEATS_PER_ROW - 1]
	_check("rows curve toward the screen: row 0's end seat nearer it and turned in (%s)" % end.origin,
			end.origin.z < -0.4 and end.origin.x > 7.0 and (end.basis * Vector3.FORWARD).x < -0.1)
	# Sight line: from the seated eyes to the bottom edge of the default screen, every seat back in front under it.
	var anchor: Transform3D = env.get_screen_anchor()
	var bottom_y: float = anchor.origin.y - env.default_screen_width * 9.0 / 16.0 * 0.5
	var eye := Vector3(0, Cinema.NOMINAL_EYE_HEIGHT, 0)
	var top := mm.mesh.get_aabb().end.y
	var worst := INF
	for t in xforms:
		if t.origin.z >= -0.5 or absf(t.origin.x) > 4.0:
			continue
		var back := t * Vector3(0.0, top, 0.36)
		var line_y := lerpf(eye.y, bottom_y, (eye.z - back.z) / (eye.z - anchor.origin.z))
		worst = minf(worst, line_y - back.y)
	_check("every seat back in front is under the sight line to the screen's bottom (clearance %.2f m)" % worst,
			worst > 0.05)
	_check("the viewer's own seat is folded away (%d)" % int(hall.get("_hidden_seat")),
			int(hall.get("_hidden_seat")) == Cinema.ROWS_BACK * Cinema.SEATS_PER_ROW + Cinema.SEATS_PER_ROW / 2)

	# Static parts ready for a bake.
	var statics: Array[MeshInstance3D] = env.static_meshes()
	_check("static parts: %d" % statics.size(), statics.size() >= 9)
	var uv2_ok := true
	var hints_ok := true
	for mi in statics:
		var mesh := mi.mesh as ArrayMesh
		hints_ok = hints_ok and mesh.lightmap_size_hint.x > 0 and mesh.lightmap_size_hint.y > 0
		for s in mesh.get_surface_count():
			var fmt := mesh.surface_get_format(s)
			if not (fmt & Mesh.ARRAY_FORMAT_TEX_UV2) or not (fmt & Mesh.ARRAY_FORMAT_NORMAL):
				uv2_ok = false
				continue
			for uv: Vector2 in mesh.surface_get_arrays(s)[Mesh.ARRAY_TEX_UV2]:
				if uv.x < 0.0 or uv.y < 0.0 or uv.x > 1.0 or uv.y > 1.0:
					uv2_ok = false
	_check("every static part has normals and UV2 inside its atlas", uv2_ok)
	_check("and a lightmap size hint", hints_ok)
	var dynamic_ok := true
	for n: String in ["Seats", "HouseLamps", "StepLights", "ExitSigns", "BoothWindow", "ScreenBorder", "Beam/Cone"]:
		dynamic_ok = dynamic_ok and (env.get_node(n) as GeometryInstance3D).gi_mode \
				== GeometryInstance3D.GI_MODE_DISABLED
	_check("seats, lamps, signs, border and beam left out of a bake", dynamic_ok)
	var lights: Array = env.bake_lights().get_children()
	var lights_ok := lights.size() >= 20
	for l: Light3D in lights:
		lights_ok = lights_ok and l.light_bake_mode == Light3D.BAKE_STATIC and not l.visible
	_check("%d bake lights, static and hidden (no live light)" % lights.size(), lights_ok)
	var live := 0
	for l: Light3D in env.find_children("*", "Light3D", true, false):
		if l.is_visible_in_tree():
			live += 1
	_check("no live lights in the room", live == 0)

	# Materials.
	var house_ok := true
	var filled := true
	for mi in statics:
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s) as ShaderMaterial
			house_ok = house_ok and m != null and m.shader == MaterialLibrary.SHADER_HOUSE \
					and MaterialLibrary.id_of(m) != "" and is_equal_approx(float(m.get_shader_parameter(
					"house_reference")), env.ambient_level)
			if m != null:
				var top_fill: Variant = m.get_shader_parameter("sky_top")
				filled = filled and top_fill is Vector3 and (top_fill as Vector3).length() > 0.5
	_check("every static surface a library material on the house shader", house_ok)
	_check("with its fill set", filled)
	var wall := (env.get_node("Walls") as MeshInstance3D).get_active_material(0) as ShaderMaterial
	var seat_mat := mm.mesh.surface_get_material(0) as ShaderMaterial
	_check("lamps stand in for the sconces before a bake (%s)" % wall.get_shader_parameter("lamp_count"),
			int(wall.get_shader_parameter("lamp_count")) == 6 and int(seat_mat.get_shader_parameter("lamp_count")) == 6)
	_check("the seats' velvet takes the instance colour", seat_mat.get_shader_parameter("instance_tint") == true)

	# Bake hooks.
	env.set_baking(true)
	_check("set_baking: every surface in the bake pass", wall.get_shader_parameter("bake_pass") == true
			and seat_mat.get_shader_parameter("bake_pass") == true)
	env.set_baking(false)
	var lm := LightmapGI.new()
	lm.name = "Lightmap"
	env.add_child(lm)
	lm.light_data = LightmapGIData.new()
	await _frames(2)
	_check("a LightmapGI with data is noticed: baked", env.is_baked())
	_check("baked: the walls drop the lamps and most of the fill, the seats keep theirs",
			int(wall.get_shader_parameter("lamp_count")) == 0 and int(seat_mat.get_shader_parameter("lamp_count")) == 6
			and (wall.get_shader_parameter("sky_top") as Vector3).length() < 0.5)
	lm.queue_free()
	await _frames(2)
	_check("the lightmap gone: unbaked again", not env.is_baked()
			and int(wall.get_shader_parameter("lamp_count")) == 6)

	# Showing state: the room light, the curtains, the beam (the menu closed: it keeps the light up).
	main.ui.hide_panel()
	_check("the cinema has curtains for the pre-show", main.features.preshow.available())
	main.player.play()
	await create_timer(2.5).timeout
	_check("playing: the room light goes down (%.2f), which dims the house lights" % main.features.room_light.effective(),
			main.features.room_light.effective() < 0.6)
	var beam := env.get_node("Beam") as Node3D
	_check("playing: the beam shows", beam.visible)
	var cone: ArrayMesh = (env.get_node("Beam/Cone") as MeshInstance3D).mesh
	var size: Vector2 = main.screen.get_flat_size()
	var corner: Vector3 = main.screen.global_transform * Vector3(0.5 * size.x, -0.5 * size.y, 0.0)
	var reaches := false
	for v: Vector3 in cone.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		if (beam.global_transform * v).distance_to(corner) < 0.05:
			reaches = true
	_check("the beam reaches the screen's corner from the booth window", reaches
			and beam.global_position.z > 5.0 and beam.global_position.y > 3.0)
	_check("no dust in the beam (it spoilt the picture: the user, 2026-11-04)", env.get_node_or_null("Beam/Dust") == null)
	main.player.pause()
	await _frames(3)
	_check("paused: no beam", not beam.visible)

	# Seat choice: the room moves, the occupied seat follows, the lamps stay on the walls.
	var lamp_before: Vector4 = (wall.get_shader_parameter("lamp_position") as PackedVector4Array)[0]
	var back := -1
	for i in seats.size():
		if seats[i].z > 3.0 and absf(seats[i].x) < 0.1:
			back = i
	main.features.seat.choose_seat(back)
	await _frames(3)
	var hall_now: Node = main.env.host.systems_of_kind("builder").filter(func(n: Node) -> bool: return n.get("_hidden_seat") != null).front()
	_check("a back seat chosen: that one folded away, the viewer's own back (%d)" % int(hall_now.get("_hidden_seat")),
			int(hall_now.get("_hidden_seat")) == back)
	var lamp_after: Vector4 = (wall.get_shader_parameter("lamp_position") as PackedVector4Array)[0]
	_check("the lamps moved with the room (%s -> %s)" % [lamp_before, lamp_after],
			Vector3(lamp_after.x, lamp_after.y, lamp_after.z).is_equal_approx(
			Vector3(lamp_before.x, lamp_before.y, lamp_before.z) + env.position))
	main.features.seat.choose_seat(seats.find(Vector3.ZERO))
	await _frames(2)

	var room: Dictionary = env.get_sound_room()
	_check("the sound room is the hall's box", (room["box"] as AABB).has_point(Vector3(0, 1.2, 0))
			and (room["box"] as AABB).size.z > 18.0)
	print("test_cinema: %d checks, %s (draws %d, vertices %d)" % [_checks, "all passed" if _failures == 0
			else "%d FAILED" % _failures, draws, verts])
	quit(_failures)


func _verts(m: Mesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		n += (m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return n


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL ", what)
	else:
		print("PASS ", what)
