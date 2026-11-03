extends SceneTree

## Tests for the environment library (ideas #52, #18, #53): the new built-in rooms build and follow the screen-anchor
## convention, a photo room shows a picture from user://skyboxes, a glTF room exported here loads with its anchor,
## width, sidecar JSON and unlit materials, and main.set_environment() switches to each. Settings are read-only.
## Run: godot --headless --xr-mode off --path app --script res://tests/test_rooms.gd

const EnvLibrary := preload("res://scripts/env/env_library.gd")
const GltfRoom := preload("res://scripts/env/gltf_room.gd")
const SkyboxRoom := preload("res://scripts/env/skybox_room.gd")
const Dome := preload("res://environments/dome.gd")

var _failures := 0
var _checks := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var sky_dir := ProjectSettings.globalize_path(EnvLibrary.SKY_DIR)
	var room_dir := ProjectSettings.globalize_path(EnvLibrary.ROOM_DIR)
	DirAccess.make_dir_recursive_absolute(sky_dir)
	DirAccess.make_dir_recursive_absolute(room_dir)
	# A panorama: red ahead (the middle), blue at the sides, a white horizon line.
	var pano := Image.create_empty(512, 256, false, Image.FORMAT_RGB8)
	pano.fill(Color(0.1, 0.1, 0.6))
	pano.fill_rect(Rect2i(192, 64, 128, 128), Color.RED)
	pano.fill_rect(Rect2i(0, 126, 512, 4), Color.WHITE)
	pano.save_png(sky_dir.path_join("test_pano.png"))
	_export_room(room_dir.path_join("test_room.glb"))
	var side := FileAccess.open(room_dir.path_join("test_room.json"), FileAccess.WRITE)
	side.store_string('{"name": "Test room", "ambient_level": 0.3, "reflection_floor_y": 0.0}')
	side.close()

	var list := EnvLibrary.environments()
	var ids: Array = list.map(func(e: Array) -> String: return e[0])
	_check("library lists the new rooms, the photo and the glTF room (%s)" % [ids], ids.has("drive_in")
			and ids.has("home_theatre") and ids.has("planetarium") and ids.has("dome") and ids.has("sky:test_pano.png")
			and ids.has("room:test_room.glb"))
	_check("geodesic frame: 120 edges", Dome.geodesic_edges(1.0).size() == 120)

	# The glTF room on its own.
	var room := GltfRoom.load_room(room_dir.path_join("test_room.glb"))
	_check("glTF room loads (%s)" % GltfRoom.last_error, room != null)
	if room != null:
		root.add_child(room)
		var anchor: Transform3D = room.get_screen_anchor()
		_check("its ScreenAnchor: place and width from the X scale (%s, %.2f)" % [anchor.origin, room.default_screen_width],
				anchor.origin.is_equal_approx(Vector3(0.5, 1.6, -4.5)) and is_equal_approx(room.default_screen_width, 3.5))
		_check("sidecar JSON: name, level, reflection floor", room.display_name == "Test room"
				and is_equal_approx(room.ambient_level, 0.3) and room.reflection_floor_y == 0.0)
		var unlit := 0
		var meshes := room.find_children("*", "MeshInstance3D", true, false)
		for mi: MeshInstance3D in meshes:
			var m := mi.get_surface_override_material(0)
			if m is ShaderMaterial and (m as ShaderMaterial).shader == GltfRoom.UNLIT_TEX:
				unlit += 1
		_check("materials made unlit (%d of %d meshes)" % [unlit, meshes.size()], unlit >= 2 and unlit == meshes.size() - 0)
		var lamp_ok := false
		for mi: MeshInstance3D in meshes:
			var m := mi.get_surface_override_material(0) as ShaderMaterial
			var e: Variant = m.get_shader_parameter("emission") if m != null else null
			if e is Color and (e as Color).r > 0.5:
				lamp_ok = true
		_check("emission kept (the lamp)", lamp_ok)
		_check("the anchor's own mesh hidden", not room.find_child("ScreenAnchor*", true, false).visible
				if room.find_child("ScreenAnchor*", true, false) != null else true)
		room.queue_free()
	_check("a missing file: null and a reason", GltfRoom.load_room(room_dir.path_join("nope.glb")) == null
			and GltfRoom.last_error != "")

	# The photo, prepared for the sphere: a 1:1 picture is centred on a 2:1 one.
	var square := Image.create_empty(100, 100, false, Image.FORMAT_RGB8)
	square.fill(Color.GREEN)
	var prepared := SkyboxRoom.prepare(square.save_png_to_buffer(), "png")
	_check("1:1 photo centred on 2:1", prepared.get_size() == Vector2i(200, 100) and prepared.get_pixel(100, 50).g > 0.9
			and prepared.get_pixel(10, 50).g < 0.1)

	# Through main: each room switches in, places the screen from its anchor, and the photo appears.
	var main: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.settings.read_only = true
	root.add_child(main)
	await _frames(5)
	for id: String in ["drive_in", "home_theatre", "planetarium", "dome", "room:test_room.glb", "sky:test_pano.png"]:
		main.set_environment(id)
		await _frames(2)
		var d: Dictionary = main.env.get_default_screen()
		_check("%s: switched, screen %.1f m wide at %.1f m" % [id, main.screen_width, main.screen_distance],
				main.env_id == id and is_equal_approx(main.screen_width, float(d["width"]))
				and is_equal_approx(main.screen_distance, float(d["distance"])))
	await _wait(func() -> bool: return main.env.is_ready(), 5.0)
	_check("the photo room shows its photo", main.env.is_ready())
	_check("--env aliases: drivein, planetarium", main._env_from_arg("drivein") == "drive_in"
			and main._env_from_arg("Planetarium") == "planetarium")
	var outside := ProjectSettings.globalize_path("user://test_pano_copy.png")
	pano.save_png(outside)
	_check("add_skybox copies a picture in", EnvLibrary.add_skybox(outside) == "sky:test_pano_copy.png"
			and FileAccess.file_exists(sky_dir.path_join("test_pano_copy.png")))
	_check("a picture already there: its id", EnvLibrary.add_skybox(sky_dir.path_join("test_pano.png")) == "sky:test_pano.png")
	DirAccess.remove_absolute(outside)
	# #62 floor reflection: on in the home theatre (it has a floor for it), off by default in the void, never in 360.
	var refl: Node = main.features.reflection
	main.open_path("stub://flat_sbs")
	main.set_environment("home_theatre")
	await _frames(3)
	_check("home theatre: reflection available and on", refl.available() and refl.enabled and refl.is_showing())
	var rm: ShaderMaterial = (refl.get_node("ReflectionQuad") as MeshInstance3D).material_override
	_check("the screen's uniforms reach the reflection", rm.get_shader_parameter("stereo_layout")
			== main.screen.material.get_shader_parameter("stereo_layout") and rm.get_shader_parameter("y_tex") != null)
	var quad: Node3D = refl.get_node("ReflectionQuad")
	_check("the quad lies on the floor between viewer and screen (%s)" % quad.global_position,
			absf(quad.global_position.y - 0.002) < 0.001 and quad.global_position.z < 0.0
			and quad.global_position.z > main.screen.global_position.z)
	main.set_environment("drive_in")
	await _frames(2)
	_check("drive-in: no floor for it", not refl.available() and not refl.is_showing())
	main.set_environment("void")
	await _frames(2)
	_check("void: available, off by default", refl.available() and not refl.enabled and not refl.is_showing())
	refl.set_enabled(true)
	await _frames(2)
	_check("void: turned on", refl.is_showing())
	main.open_path("stub://360_mono")
	await _frames(3)
	_check("360: hidden", not refl.is_showing())
	refl.set_enabled(false)
	main.set_environment("void")
	main.queue_free()
	for d: String in [sky_dir, room_dir]:
		for f in DirAccess.get_files_at(d):
			if f.begins_with("test_"):
				DirAccess.remove_absolute(d.path_join(f))
	print("test_rooms: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


## A small room exported to glTF: a floor, a lit-material wall, an emissive lamp and a ScreenAnchor (X scale 3.5).
func _export_room(path: String) -> void:
	var scene := Node3D.new()
	scene.name = "TestRoom"
	var floor_mi := MeshInstance3D.new()
	floor_mi.name = "Floor"
	var plane := PlaneMesh.new()
	plane.size = Vector2(6, 6)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.3, 0.25, 0.2)
	plane.material = fm
	floor_mi.mesh = plane
	scene.add_child(floor_mi)
	var lamp := MeshInstance3D.new()
	lamp.name = "Lamp"
	var sphere := SphereMesh.new()
	var lm := StandardMaterial3D.new()
	lm.emission_enabled = true
	lm.emission = Color(1, 0.9, 0.6)
	sphere.material = lm
	lamp.mesh = sphere
	lamp.position = Vector3(2, 2.5, -2)
	scene.add_child(lamp)
	var anchor := Node3D.new()
	anchor.name = "ScreenAnchor"
	anchor.position = Vector3(0.5, 1.6, -4.5)
	anchor.scale = Vector3(3.5, 1, 1)
	scene.add_child(anchor)
	for n in scene.get_children():
		n.owner = scene
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	doc.append_from_scene(scene, state)
	doc.write_to_filesystem(state, path)
	scene.free()


func _wait(cond: Callable, seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await process_frame


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL " + what)
	else:
		print("PASS " + what)
