extends SceneTree

## Run-time lightmaps (scripts/env/room_bake.gd). Headless: prepare() gives every baked mesh a second UV set (the
## primitives their own, other meshes xatlas's, kept and reused), the stamp is steady and changes with a light, a
## material or a mesh, and an engine without the fork's LightmapGI.bake() says so.
## With a renderer and --bake (WSL: lavapipe; the bake itself 0.6 s at the default texel, 4.6 s at 0.05 m): a test
## room with library materials (lit, with a fill), a white StandardMaterial3D box, two lights and a glowing panel
## for the screen is drawn with no light, with real-time light, baked and drawn again; the fill is back after the
## bake; the bake is kept, a fresh copy of the room loads it without baking and looks the same, its surfaces stay lit
## with the lights hidden (both kinds of material show the lightmap), and a changed light makes it stale. The
## pictures go to --out=DIR (default user://bake_proof); --texel=M and --near-texel=M set prepare()'s resolution.
##   godot --headless --xr-mode off --path app --script res://tests/test_bake.gd
##   VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a -s "-screen 0 1920x1080x24" godot
##       --xr-mode off --path app --script res://tests/test_bake.gd -- --bake --out=/tmp/bake_proof

const RoomBake := preload("res://scripts/env/room_bake.gd")
const MaterialLibrary := preload("res://scripts/env/material_library.gd")

const ID := "bake_test"
const SHOT := Vector2i(960, 540)
## A dim hemisphere fill on the lit library materials: drawn as emission, which the bake must not take as light.
const FILL := {"sky_top": Color(0.3, 0.3, 0.32), "sky_bottom": Color(0.15, 0.12, 0.1), "screen": 0.0}

var _failures := 0
var _checks := 0
var _out := "user://bake_proof"
var _do_bake := false
## prepare()'s options for the bake run (--texel=, --near-texel=): the proof's resolution.
var _prepare_options := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--bake":
			_do_bake = true
		elif a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
		elif a.begins_with("--texel="):
			_prepare_options["texel"] = a.trim_prefix("--texel=").to_float()
		elif a.begins_with("--near-texel="):
			_prepare_options["near_texel"] = a.trim_prefix("--near-texel=").to_float()
	_run.call_deferred()


func _run() -> void:
	RoomBake.clear(ID)
	_prepare_checks()
	_stamp_checks()
	if _do_bake:
		await _bake_checks()
	RoomBake.clear(ID)
	print("Bake test: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


## The test room: viewer at the origin facing -Z, a 6 x 3 x 8 m shell, carpet, two seat rows, a white box, a glowing
## 16:9 panel on the front wall, a ceiling light and a wall light. `mesh_without_uv2` adds an ArrayMesh with no UV2
## (a sphere's arrays) for xatlas.
func build_room(mesh_without_uv2 := true) -> Node3D:
	var room := Node3D.new()
	room.name = "BakeRoom"
	var wall := _lib("painted_wall", Color(0.75, 0.72, 0.68))
	var shell := BoxMesh.new()
	shell.size = Vector3(6.0, 3.0, 8.0)
	shell.flip_faces = true
	_add(room, "Shell", shell, Vector3(0.0, 1.5, -1.0), wall)
	var carpet := PlaneMesh.new()
	carpet.size = Vector2(5.8, 7.8)
	_add(room, "Carpet", carpet, Vector3(0.0, 0.01, -1.0), _lib("woven_carpet", Color(0.35, 0.12, 0.12)))
	var seat := BoxMesh.new()
	seat.size = Vector3(4.0, 0.5, 0.6)
	var velvet := _lib("velvet", Color(0.5, 0.08, 0.1))
	_add(room, "SeatsFront", seat, Vector3(0.0, 0.25, -1.2), velvet)
	_add(room, "SeatsBack", seat, Vector3(0.0, 0.25, 0.6), velvet)
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.85, 0.85, 0.85)
	var cube := BoxMesh.new()
	cube.size = Vector3(0.8, 0.8, 0.8)
	_add(room, "WhiteBox", cube, Vector3(2.0, 0.4, -2.8), white)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color.BLACK
	glow.emission_enabled = true
	glow.emission = Color(0.8, 0.85, 1.0)
	glow.emission_energy_multiplier = 3.0
	var panel := QuadMesh.new()
	panel.size = Vector2(3.2, 1.8)
	_add(room, "Screen", panel, Vector3(0.0, 1.5, -4.95), glow)
	if mesh_without_uv2:
		var sphere := SphereMesh.new()
		sphere.radius = 0.35
		sphere.height = 0.7
		var arrays := sphere.get_mesh_arrays()
		arrays[Mesh.ARRAY_TEX_UV2] = null
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_add(room, "Sphere", am, Vector3(-2.0, 0.35, -2.8), white)
	var ceiling := OmniLight3D.new()
	ceiling.name = "CeilingLight"
	ceiling.position = Vector3(0.0, 2.7, -0.5)
	ceiling.omni_range = 7.0
	ceiling.light_energy = 1.2
	ceiling.light_color = Color(1.0, 0.85, 0.65)
	ceiling.shadow_enabled = true
	ceiling.light_bake_mode = Light3D.BAKE_STATIC
	room.add_child(ceiling)
	var sconce := OmniLight3D.new()
	sconce.name = "WallLight"
	sconce.position = Vector3(-2.8, 2.0, -3.0)
	sconce.omni_range = 3.5
	sconce.light_energy = 1.5
	sconce.light_color = Color(1.0, 0.6, 0.3)
	sconce.shadow_enabled = true
	sconce.light_bake_mode = Light3D.BAKE_STATIC
	room.add_child(sconce)
	return room


func _lib(id: String, colour: Color) -> Material:
	var m := MaterialLibrary.get_material(id, {"colour": colour, "lit": FILL})
	if m == null:
		var s := StandardMaterial3D.new()
		s.albedo_color = colour
		return s
	return m


func _add(room: Node3D, node_name: String, mesh: Mesh, at: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.position = at
	mi.material_override = mat
	room.add_child(mi)
	return mi


func _all_have_uv2(room: Node3D) -> Array[String]:
	var missing: Array[String] = []
	for mi in RoomBake.baked_meshes(room):
		for s in mi.mesh.get_surface_count():
			if mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_TEX_UV2] == null:
				missing.append(str(mi.name))
	return missing


func _prepare_checks() -> void:
	var has_xatlas := _xatlas_available()
	var room := build_room(has_xatlas)
	root.add_child(room)
	var r := RoomBake.prepare(room, ID)
	print("prepare: %s" % r)
	_check("prepare() covers every static mesh (%d)" % r["meshes"], r["meshes"] == (7 if has_xatlas else 6))
	_check("every baked mesh has UV2 (missing: %s)" % [_all_have_uv2(room)], _all_have_uv2(room).is_empty())
	_check("primitives use their own UV2, scaled per instance (%d)" % r["primitives"], r["primitives"] == 6)
	var shell := room.get_node("Shell") as MeshInstance3D
	var seats := room.get_node("SeatsBack") as MeshInstance3D
	_check("the shell at the room texel, the seats beside the viewer finer (%.2f, %.2f)" % [shell.gi_lightmap_texel_scale,
			seats.gi_lightmap_texel_scale], is_equal_approx(shell.gi_lightmap_texel_scale, 1.0)
			and is_equal_approx(seats.gi_lightmap_texel_scale, 2.0))
	if has_xatlas:
		_check("the mesh without UV2 is unwrapped by xatlas and kept", r["unwrapped"] == 1
				and DirAccess.get_files_at("user://lightmaps/%s/meshes" % ID).size() == 1)
		var again := build_room(true)
		root.add_child(again)
		var t0 := Time.get_ticks_usec()
		var r2 := RoomBake.prepare(again, ID)
		_check("a fresh copy of the room reuses the kept unwrap (%s)" % r2, r2["cached"] == 1 and r2["unwrapped"] == 0
				and _all_have_uv2(again).is_empty())
		var sphere := again.get_node("Sphere") as MeshInstance3D
		_check("the kept unwrap keeps the room's material", sphere.mesh.surface_get_material(0) == null
				and sphere.get_active_material(0) is StandardMaterial3D)
		print("prepare again (cached): %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
		again.free()
		# Unwrap timings for the record: every primitive of the room through xatlas, and a denser mesh.
		var forced := build_room(false)
		root.add_child(forced)
		RoomBake.clear(ID)
		var rf := RoomBake.prepare(forced, ID, {"xatlas": true})
		print("xatlas for all %d meshes: %.1f ms" % [rf["unwrapped"], rf["seconds"] * 1000.0])
		_check("xatlas can unwrap the primitives too (%d)" % rf["unwrapped"], rf["unwrapped"] == 6
				and _all_have_uv2(forced).is_empty())
		forced.free()
		RoomBake.clear(ID)
	else:
		print("(this engine has no xatlas: lightmap_unwrap() is not configured; the xatlas checks are skipped)")
	room.free()


func _xatlas_available() -> bool:
	var probe := ArrayMesh.new()
	var box := BoxMesh.new()
	probe.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, box.get_mesh_arrays())
	return probe.lightmap_unwrap(Transform3D(), 0.2) == OK


func _stamp_checks() -> void:
	var a := build_room(false)
	var b := build_room(false)
	root.add_child(a)
	root.add_child(b)
	RoomBake.prepare(a, ID)
	RoomBake.prepare(b, ID)
	var sa := RoomBake.stamp_of(a)
	_check("the stamp is steady (twice, and for an identical room)", sa == RoomBake.stamp_of(a)
			and sa == RoomBake.stamp_of(b))
	_check("the stamp takes the options", sa != RoomBake.stamp_of(a, {"bounces": 1}))
	(b.get_node("CeilingLight") as OmniLight3D).light_energy = 2.0
	var sb := RoomBake.stamp_of(b)
	_check("a light's change changes the stamp", sb != sa)
	(b.get_node("CeilingLight") as OmniLight3D).light_energy = 1.2
	_check("and back again", RoomBake.stamp_of(b) == sa)
	(b.get_node("WhiteBox") as MeshInstance3D).material_override.set("albedo_color", Color.RED)
	_check("a material's change changes the stamp", RoomBake.stamp_of(b) != sa)
	var lit := (a.get_node("Shell") as MeshInstance3D).get_active_material(0) as ShaderMaterial
	if lit != null:
		var was: Variant = lit.get_shader_parameter("screen_light")
		lit.set_shader_parameter("screen_light", 0.7)
		_check("the film light and fill (live stand-ins) don't change the stamp", RoomBake.stamp_of(a) == sa)
		lit.set_shader_parameter("screen_light", was)
	var c := build_room(false)
	root.add_child(c)
	((c.get_node("SeatsBack") as MeshInstance3D).mesh as BoxMesh).size = Vector3(4.0, 0.6, 0.6)
	RoomBake.prepare(c, ID)
	_check("a mesh's change changes the stamp", RoomBake.stamp_of(c) != sa)
	(c.get_node("WhiteBox") as MeshInstance3D).position.x += 0.5
	_check("can_bake() matches the engine (%s)" % RoomBake.can_bake(), RoomBake.can_bake()
			== (ClassDB.class_has_method("LightmapGI", "bake") and RenderingServer.get_rendering_device() != null
			and ClassDB.class_exists("LightmapperRD")))
	if not RoomBake.can_bake():
		var r := RoomBake.bake(a, ID)
		_check("bake() refuses with the reason where it can't (%s)" % r["error"], not r["ok"] and r["error"] != "")
	a.free()
	b.free()
	c.free()


func _bake_checks() -> void:
	if not RoomBake.can_bake():
		_check("--bake needs the fork's LightmapGI.bake() and a GPU renderer", false)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	var vp := SubViewport.new()
	vp.size = SHOT
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true
	root.add_child(vp)
	var room := build_room(true)
	vp.add_child(room)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 1.3, 2.6)
	cam.fov = 75.0
	vp.add_child(cam)
	cam.look_at(Vector3(0.0, 1.0, -4.0))
	cam.current = true
	var prep := RoomBake.prepare(room, ID, _prepare_options)
	# The reference: no lights, no lightmap (only the fill and the glowing panel).
	for l in RoomBake.baked_lights(room):
		l.visible = false
	var unlit := await _shot(vp, "unlit")
	for l in room.find_children("*", "Light3D", true, false):
		(l as Light3D).visible = true
	await _shot(vp, "before")

	var steps: Array[float] = []
	var t0 := Time.get_ticks_usec()
	var r := RoomBake.bake(room, ID, {"progress": func(f: float, text: String) -> void:
		steps.append(f)
		if steps.size() % 10 == 1:
			print("  %3d %%  %s" % [int(f * 100.0), text])})
	var wall_seconds := (Time.get_ticks_usec() - t0) / 1e6
	print("bake: %s (prepare %.1f ms, bake call %.2f s)" % [r, prep["seconds"] * 1000.0, wall_seconds])
	_check("the bake succeeds (%s)" % r["error"], r["ok"])
	if not r["ok"]:
		return
	var rising := true
	for i in range(1, steps.size()):
		rising = rising and steps[i] >= steps[i - 1]
	_check("progress rises from 0 to 1 (%d steps)" % steps.size(), steps.size() > 3 and rising and steps[-1] == 1.0)
	var wall := (room.get_node("Shell") as MeshInstance3D).get_active_material(0) as ShaderMaterial
	_check("the fill is back on the library materials after the bake",
			wall == null or _as_colour(wall.get_shader_parameter("sky_top")).is_equal_approx(FILL["sky_top"]))
	_check("the bake is kept with its stamp", FileAccess.file_exists(r["path"])
			and RoomBake.stored(ID).get("stamp", "") == RoomBake.stamp_of(room))
	var after := await _shot(vp, "after")

	# A fresh copy of the room, as at the next start: loads the kept bake instead of baking.
	room.free()
	await process_frame
	var fresh := build_room(true)
	vp.add_child(fresh)
	RoomBake.prepare(fresh, ID, _prepare_options)
	var t1 := Time.get_ticks_usec()
	var loaded := RoomBake.load(fresh, ID)
	print("load: %.1f ms" % ((Time.get_ticks_usec() - t1) / 1000.0))
	_check("the next start loads the kept bake", loaded)
	var again := await _shot(vp, "loaded")
	var same := _lum(again, Vector2i(192, 162))
	_check("and it looks the same (%.3f vs %.3f)" % [same, _lum(after, Vector2i(192, 162))],
			absf(same - _lum(after, Vector2i(192, 162))) < 0.02)
	# The lights hidden: the baked surfaces look the same (their light is all in the lightmap now).
	for l in RoomBake.baked_lights(fresh):
		l.visible = false
	var dark := await _shot(vp, "lights_hidden")
	for l in fresh.find_children("*", "Light3D", true, false):
		(l as Light3D).visible = true
	_check("with the lights hidden the baked walls stay lit (%.3f)" % _lum(dark, Vector2i(192, 162)),
			absf(_lum(dark, Vector2i(192, 162)) - same) < 0.02)
	# Which materials show the lightmap: lights hidden, each surface brighter than with no lights and no lightmap.
	var probes := {"wall (lit library shader)": Vector2(0.2, 0.3),
			"seat front, bounce only (lit library shader)": Vector2(0.5, 0.88),
			"white box (StandardMaterial3D)": Vector2(0.6375, 0.56)}
	for what: String in probes:
		var at := Vector2i(Vector2(SHOT) * (probes[what] as Vector2))
		var l0 := _lum(unlit, at)
		var l1 := _lum(dark, at)
		_check("the %s shows the lightmap (%.3f with no light, %.3f from the lightmap alone)" % [what, l0, l1],
				l1 > l0 + 0.01)
	(fresh.get_node("CeilingLight") as OmniLight3D).light_energy = 2.0
	_check("a changed light makes it stale", not RoomBake.load(fresh, ID))
	print("pictures: %s" % ProjectSettings.globalize_path(_out))
	vp.queue_free()


func _shot(vp: SubViewport, label: String) -> Image:
	for i in 4:
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.save_png(_out.path_join("bake_%s.png" % label))
	return img


## A vec3 uniform reads back as a Vector3.
func _as_colour(v: Variant) -> Color:
	return Color(v.x, v.y, v.z) if v is Vector3 else (v as Color if v is Color else Color.TRANSPARENT)


func _lum(img: Image, at: Vector2i) -> float:
	var sum := 0.0
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			sum += img.get_pixelv((at + Vector2i(dx, dy)).clamp(Vector2i.ZERO, img.get_size() - Vector2i.ONE)).get_luminance()
	return sum / 49.0


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if ok:
		print("ok   ", what)
	else:
		_failures += 1
		print("FAIL ", what)
