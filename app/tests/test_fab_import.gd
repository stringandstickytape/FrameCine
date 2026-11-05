extends SceneTree

## Fab downloads made user objects (scripts/assistant/fab_import.gd, docs/assistant.md "Objects from Fab"), from a
## zip made here as Fab lays one out (no one's asset is in the repository): telling a Fab zip from another, the .json
## read (name, tags, small asset on a table, the id), the maps found by their names, a big map made smaller, the
## ambient occlusion multiplied into the colour, gloss turned to roughness, the normal map kept in the .glb, the import
## kept once. FAB_ZIP=<a real download's zip> also imports that (its .fbx through the engine's FBX loader).
## godot --headless --xr-mode off --path app --script res://tests/test_fab_import.gd

const FabImport := preload("res://scripts/assistant/fab_import.gd")
const ObjectLibrary := preload("res://scripts/assistant/object_library.gd")

const DIR := "user://test_fab"
const ID := "testfab01"

var _failures := 0
var _checks := 0


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	_clear()
	var zip := _make_zip(DIR.path_join("fab.zip"), true)
	var plain := _make_zip(DIR.path_join("plain.zip"), false)

	_check("a Fab zip is told apart", FabImport.is_fab_zip(zip))
	_check("a zip without the asset's .json isn't one", not FabImport.is_fab_zip(plain))
	_check("nor a file that isn't a zip", not FabImport.is_fab_zip(DIR.path_join("nothing.txt")))

	var a := FabImport.read_zip(zip)
	_check("read: no error (%s)" % a.get("error", ""), not a.has("error"))
	_check("read: id and name", a.get("id") == ID and a.get("name") == "Test Fab Crate")
	_check("read: tags lower case, once each (%s)" % [a.get("tags")], a.get("tags") == ["crate", "wood"])
	_check("read: a small asset goes on a table", a.get("mount") == "table")
	var maps: Dictionary = a.get("maps", {})
	var slots := maps.keys()
	slots.sort()
	_check("read: maps by name (%s)" % [slots], slots == ["albedo", "ao", "gloss", "normal"])
	_check("read: a map over %d px made smaller (%d)" % [FabImport.MAX_TEXTURE, (maps["albedo"] as Image).get_width()],
			(maps["albedo"] as Image).get_width() == FabImport.MAX_TEXTURE)

	var m := FabImport.material(maps)
	var c := m.albedo_texture.get_image().get_pixel(10, 4)
	_check("material: occlusion multiplied in (%s)" % c, absf(c.r8 - 230 * 128 / 255) <= 2 and absf(c.g8 - 200 * 128 / 255) <= 2)
	_check("material: gloss turned to roughness (%.2f)" % m.roughness_texture.get_image().get_pixel(1, 1).r,
			m.roughness_texture.get_image().get_pixel(1, 1).r < 0.3)
	_check("material: the normal map", m.normal_enabled and m.normal_texture != null)

	_rules()

	var r := FabImport.import_zip(zip)
	_check("import: ok (%s)" % r.get("error", ""), r.get("ok") == true and not r.has("already"))
	var man: Dictionary = r.get("manifest", {})
	_check("import: keeps the asset's id", man.get("fab") == ID)
	_check("import: a user object, on a table", man.get("source") == "user" and man.get("mount") == "table")
	_check("import: its size in metres (%s)" % [man.get("size")], absf(float(man.get("size", [0])[0]) - 0.3) < 0.01)
	_check("import: the part named after the asset (%s)" % [man.get("parts")],
			(man.get("parts", []) as Array).size() == 1 and man["parts"][0]["name"] == "Test Fab Crate")
	var glb := ObjectLibrary.glb(str(man.get("id", "")))
	_check("import: the .glb keeps the normal and roughness maps", _has_maps(glb))
	_check("import: under user://objects", ObjectLibrary.USER_DIR.begins_with("user://") and not glb.is_empty())
	var again := FabImport.import_zip(zip)
	_check("import again: kept once", again.get("ok") == true and again.get("already") == true
			and again["manifest"]["id"] == man.get("id"))
	_check("downloads(): a list", FabImport.downloads() is Array)
	var redo := FabImport.import_zip(zip, true)
	_check("import again (again): the same id, made again (%s)" % redo.get("error", ""), redo.get("ok") == true
			and not redo.has("already") and redo["manifest"]["id"] == man.get("id") and redo["manifest"]["fab"] == ID)
	_check("import again (again): one object for the asset", ObjectLibrary.list("", "user").filter(
			func(o: Dictionary) -> bool: return o.get("fab") == ID).size() == 1)

	var real := OS.get_environment("FAB_ZIP")
	if real != "":
		var t0 := Time.get_ticks_msec()
		var rr := FabImport.import_zip(real)
		var rm: Dictionary = rr.get("manifest", {})
		print("FAB_ZIP: %s, %d ms, %s" % [rr.get("error", "ok"), Time.get_ticks_msec() - t0,
				{"name": rm.get("name"), "size": rm.get("size"), "triangles": rm.get("triangles"),
				"mount": rm.get("mount"), "glb_bytes": ObjectLibrary.glb(str(rm.get("id", ""))).size()}])
		_check("FAB_ZIP: imported", rr.get("ok") == true)
		if rr.get("ok") == true and not rr.has("already"):
			ObjectLibrary.delete(str(rm["id"]))
			ObjectLibrary.purge(str(rm["id"]))

	_clear()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


## The material's rules on made-up maps: a plant's AO, a dark scan, the name from semanticTags.
func _rules() -> void:
	var grey := func(v: float, size := 16) -> Image:
		var img := Image.create_empty(size, size, false, Image.FORMAT_RGB8)
		img.fill(Color(v, v, v))
		return img
	var plant := FabImport.material({"albedo": grey.call(0.6), "ao": grey.call(0.2), "opacity": grey.call(1.0)})
	_check("a plant's AO is left out (opacity map)", plant.albedo_texture.get_image().get_pixel(1, 1).r > 0.55)
	_check("a plant is cut out, two-sided", plant.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			and plant.cull_mode == BaseMaterial3D.CULL_DISABLED)
	var dim_ao := FabImport.material({"albedo": grey.call(0.6), "ao": grey.call(0.3)})
	_check("an AO map mostly dark is left out", dim_ao.albedo_texture.get_image().get_pixel(1, 1).r > 0.55)
	var dark := FabImport.material({"albedo": grey.call(0.1)})
	var v := dark.albedo_texture.get_image().get_pixel(1, 1).r
	_check("a dark scan lifted, at most %.0f times (%.3f)" % [FabImport.COLOUR_MAX_GAIN, v], v > 0.15 and v < 0.21)
	var mid := FabImport.material({"albedo": grey.call(0.5)})
	_check("a scan bright enough left as it is", absf(mid.albedo_texture.get_image().get_pixel(1, 1).r - 0.5) < 0.01)
	_check("the name from semanticTags when the .json has none", FabImport._name_of(
			{"id": "abc", "semanticTags": {"name": "Old Chair 07"}}) == "Old Chair 07")
	_check("else the id", FabImport._name_of({"id": "abc"}) == "abc")
	var cut := load("res://scripts/env/gltf_room.gd").convert_material(plant) as ShaderMaterial
	_check("in a room a cut-out is the room shader, cut out and two-sided (dimmed with the room)", cut != null
			and cut.shader.code.contains("#define ALPHA_CUT") and cut.shader.code.contains("cull_disabled"))


## A zip as Fab lays one out: the asset's .json at the top, a model, its maps named <name>_<id>_<res>_<Map>.
func _make_zip(path: String, with_json: bool) -> String:
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.3, 0.2, 0.25)
	box.mesh = mesh
	box.name = "crate_LOD0_000"
	var root := Node3D.new()
	root.add_child(box)
	var glb := ObjectLibrary.to_glb(root)
	root.free()
	var z := ZIPPacker.new()
	z.open(path)
	if with_json:
		_put(z, "%s.json" % ID, JSON.stringify({"id": ID, "name": "Test Fab Crate", "tags": ["Crate", "wood", "crate"],
				"meta": [{"key": "small3dasset", "name": "Small3dAsset", "value": "true"}]}).to_utf8_buffer())
	_put(z, "Test_Fab_Crate_%s_Low.glb" % ID, glb)
	_put(z, "Test_Fab_Crate_%s_Low_1K_BaseColor.png" % ID, _png(Color(230 / 255.0, 200 / 255.0, 180 / 255.0), Vector2i(2100, 16)))
	_put(z, "Test_Fab_Crate_%s_Low_1K_AO.png" % ID, _png(Color(128 / 255.0, 128 / 255.0, 128 / 255.0), Vector2i(64, 64)))
	_put(z, "Test_Fab_Crate_%s_Low_1K_Normal.png" % ID, _png(Color(0.5, 0.5, 1.0), Vector2i(64, 64)))
	_put(z, "Test_Fab_Crate_%s_Low_1K_Gloss.png" % ID, _png(Color(0.9, 0.9, 0.9), Vector2i(64, 64)))
	_put(z, "Test_Fab_Crate_%s_Low_1K_Cavity.png" % ID, _png(Color(0.5, 0.5, 0.5), Vector2i(8, 8)))
	z.close()
	return path


func _put(z: ZIPPacker, name: String, bytes: PackedByteArray) -> void:
	z.start_file(name)
	z.write_file(bytes)
	z.close_file()


func _png(c: Color, size: Vector2i) -> PackedByteArray:
	var img := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGB8)
	img.fill(c)
	return img.save_png_to_buffer()


func _has_maps(glb: PackedByteArray) -> bool:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if glb.is_empty() or doc.append_from_buffer(glb, "", state) != OK:
		return false
	for mat in state.get_materials():
		var b := mat as BaseMaterial3D
		if b != null and b.normal_texture != null and b.roughness_texture != null:
			return true
	return false


func _clear() -> void:
	for m: Dictionary in ObjectLibrary.list("", "user"):
		if str(m.get("fab", "")) == ID:
			ObjectLibrary.delete(str(m["id"]))
			ObjectLibrary.purge(str(m["id"]))


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)
