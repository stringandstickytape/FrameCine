extends SceneTree

## Tests for the material library (scripts/env/material_library.gd, docs/materials.md): the catalogue loads, every
## entry's map files exist with the right header, size and format, the shaders parse, a material applies to a mesh
## and to one surface, the cache shares textures and materials, rooms keep plain materials inside an assistant's lit
## room, the credits list every material, the repository's size budget holds, and the `materials` command lists them.
## Headless (the shaders are parsed, not drawn; the renders in docs/shots/materials are the drawn check).
##   godot --headless --xr-mode off --path app --script res://tests/test_materials.gd

const MaterialLibrary := preload("res://scripts/env/material_library.gd")
const DevCommands := preload("res://scripts/dev/dev_commands.gd")

## The repository's budget for the library's files (docs/materials.md).
const BUDGET_BYTES := 60 * 1024 * 1024
const KINDS := ["albedo", "normal", "orm"]

var _failures := 0
var _checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	MaterialLibrary.clear_cache()
	_catalogue()
	_files()
	_shaders()
	_apply()
	_cache()
	_lit_rooms()
	_credits()
	await _command()
	print("Materials test: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _catalogue() -> void:
	var ids := MaterialLibrary.ids()
	_check("the catalogue has 30 to 50 materials (%d)" % ids.size(), ids.size() >= 30 and ids.size() <= 50)
	var listed := MaterialLibrary.list()
	_check("list() gives every one, by name", listed.size() == ids.size()
			and listed.all(func(e: Dictionary) -> bool: return MaterialLibrary.has(e["id"])))
	var bad: Array[String] = []
	var re := RegEx.create_from_string("^[a-z][a-z0-9_]*$")
	for id in ids:
		var e := MaterialLibrary.entry(id)
		var maps: Dictionary = e.get("maps", {})
		var src: Dictionary = e.get("source", {})
		var why := ""
		if re.search(id) == null:
			why = "id not snake_case"
		elif str(e.get("name", "")).strip_edges() == "":
			why = "no name"
		elif not (e.get("tags") is Array) or (e["tags"] as Array).is_empty():
			why = "no tags"
		elif not (float(e.get("tiling", 0.0)) > 0.0):
			why = "no tiling"
		elif not KINDS.all(func(k: String) -> bool: return maps.has(k)):
			why = "maps %s" % [maps.keys()]
		elif str(src.get("licence", "")) != "CC0 1.0" or not str(src.get("url", "")).begins_with("https://"):
			why = "source %s" % [src]
		elif not Color.html_is_valid(str(e.get("tint", ""))) or not Color.html_is_valid(str(e.get("swatch", ""))):
			why = "tint or swatch"
		else:
			for k in ["roughness_scale", "normal_strength", "specular", "sheen"]:
				if not (e.get(k) is float or e.get(k) is int):
					why = "tunable %s" % k
		if why != "":
			bad.append("%s: %s" % [id, why])
	_check("every entry: snake_case id, name, tags, tiling, three maps, a CC0 source, tunables (%s)" % [bad],
			bad.is_empty())
	_check("an unknown id: no entry, no material", MaterialLibrary.entry("no_such_material").is_empty()
			and MaterialLibrary.get_material("no_such_material") == null)


func _files() -> void:
	var bad: Array[String] = []
	var total := 0
	var floors_2k := 0
	for id in MaterialLibrary.ids():
		var e := MaterialLibrary.entry(id)
		var size := int(e.get("size", 0))
		if size == 2048:
			floors_2k += 1
		for k: String in KINDS:
			var path := MaterialLibrary.DIR.path_join(str(e["maps"][k]))
			if not FileAccess.file_exists(path):
				bad.append("%s %s: missing" % [id, k])
				continue
			var bytes := FileAccess.get_file_as_bytes(path)
			total += bytes.size()
			var info := MaterialLibrary.mtex_info(bytes)
			var want_size := 1024 if k == "orm" else size
			var want_flags: int = {"albedo": MaterialLibrary.FLAG_SRGB, "normal": MaterialLibrary.FLAG_NORMAL, "orm": 0}[k]
			if info.is_empty():
				bad.append("%s %s: not a .mtex" % [id, k])
			elif info["width"] != want_size or info["height"] != want_size:
				bad.append("%s %s: %dx%d, not %d" % [id, k, info["width"], info["height"], want_size])
			elif info["flags"] != want_flags:
				bad.append("%s %s: flags %d" % [id, k, info["flags"]])
			elif info["mips"] != int(log(want_size) / log(2.0)) + 1:
				bad.append("%s %s: %d mip levels" % [id, k, info["mips"]])
			elif bytes.size() != MaterialLibrary.MTEX_HEADER + MaterialLibrary.astc8_size(want_size, want_size):
				bad.append("%s %s: %d bytes" % [id, k, bytes.size()])
			else:
				var img := MaterialLibrary.decode_mtex(bytes)
				if img == null or img.get_format() != Image.FORMAT_ASTC_8x8 or not img.has_mipmaps():
					bad.append("%s %s: does not decode as ASTC 8x8 with mipmaps" % [id, k])
	_check("every map exists: ASTC 8x8, all mip levels, its size (1K or 2K; the packed map 1K) and kind (%s)" % [bad],
			bad.is_empty())
	_check("2K only where a viewer gets close: 1 to 8 materials (%d)" % floors_2k, floors_2k >= 1 and floors_2k <= 8)
	_check("the textures fit the budget (%.1f MB of %.0f)" % [total / 1048576.0, BUDGET_BYTES / 1048576.0],
			total > 0 and total <= BUDGET_BYTES)
	var files := DirAccess.get_files_at(MaterialLibrary.DIR.path_join("textures"))
	_check("no stray files among the textures (%d files, %d maps)" % [files.size(), MaterialLibrary.ids().size() * 3],
			files.size() == MaterialLibrary.ids().size() * 3)
	# Broken files are refused, not crashed on.
	var good := FileAccess.get_file_as_bytes(MaterialLibrary.DIR.path_join(str(
			MaterialLibrary.entry(MaterialLibrary.ids()[0])["maps"]["orm"])))
	var cut := good.slice(0, good.size() - 16)
	var wrong := good.duplicate()
	wrong[0] = 0x4E
	_check("a short or foreign file is refused", MaterialLibrary.decode_mtex(cut) == null
			and MaterialLibrary.decode_mtex(wrong) == null and MaterialLibrary.decode_mtex(PackedByteArray()) == null)
	var decoded := MaterialLibrary.decode_mtex(good)
	decoded.decompress()
	_check("a map decompresses to its size (%s)" % decoded.get_size(), decoded.get_size() == Vector2i(1024, 1024)
			and not decoded.is_compressed())


func _shaders() -> void:
	for s: Shader in [MaterialLibrary.SHADER, MaterialLibrary.SHADER_TRIPLANAR]:
		var names: Array = s.get_shader_uniform_list().map(func(u: Dictionary) -> String: return u["name"])
		var want := ["albedo_map", "normal_map", "orm_map", "tint", "tiling", "use_mesh_uv", "roughness_scale",
				"normal_strength", "specular", "sheen", "pleats", "spill", "floor_darkening"]
		_check("%s parses with its uniforms (%d)" % [s.resource_path.get_file(), names.size()],
				want.all(func(n: String) -> bool: return n in names))


func _apply() -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	root.add_child(mi)
	var m := MaterialLibrary.apply(mi, "velvet", {"tint": Color(0.5, 0.2, 0.2), "tiling": 0.5})
	_check("apply: the whole mesh gets the library material", m != null and mi.material_override == m
			and m.shader == MaterialLibrary.SHADER)
	var tex := MaterialLibrary.textures("velvet")
	_check("its maps are the library's textures", m.get_shader_parameter("albedo_map") == tex["albedo"]
			and m.get_shader_parameter("normal_map") == tex["normal"] and m.get_shader_parameter("orm_map") == tex["orm"])
	var tint: Color = m.get_shader_parameter("tint")
	_check("options: tint times the entry's, tiling", tint.is_equal_approx(Color(0.5, 0.2, 0.2))
			and is_equal_approx(m.get_shader_parameter("tiling"), 0.5))
	_check("the entry's tunables are the defaults (sheen %s)" % m.get_shader_parameter("sheen"),
			is_equal_approx(m.get_shader_parameter("sheen"), float(MaterialLibrary.entry("velvet")["sheen"])))
	var t2 := tex["albedo"] as Texture2D
	_check("textures have their size and mip levels (%dx%d)" % [t2.get_width(), t2.get_height()],
			t2.get_width() == 1024 and t2.get_height() == 1024)
	var plane := MeshInstance3D.new()
	plane.mesh = PlaneMesh.new()
	root.add_child(plane)
	var m2 := MaterialLibrary.apply(plane, "oak_planks", {"uv": true, "repeat": Vector2(4, 4)}, 0)
	_check("apply to one surface: its override, with the mesh's UVs", m2 != null
			and plane.get_surface_override_material(0) == m2 and plane.material_override == null
			and m2.get_shader_parameter("use_mesh_uv") == true)
	var tri := MaterialLibrary.get_material("brushed_steel", {"triplanar": true})
	_check("triplanar: the three-projection shader", tri != null and tri.shader == MaterialLibrary.SHADER_TRIPLANAR)
	var mm := MultiMeshInstance3D.new()
	_check("a MultiMeshInstance3D takes it as its override", MaterialLibrary.apply(mm, "velvet") == mm.material_override)
	mm.free()
	_check("an unknown id applies nothing", MaterialLibrary.apply(mi, "no_such_material") == null
			and mi.material_override == m)
	mi.queue_free()
	plane.queue_free()


func _cache() -> void:
	MaterialLibrary.clear_cache()
	var a := MaterialLibrary.textures("red_brick")
	var loads := MaterialLibrary.loads
	var b := MaterialLibrary.textures("red_brick")
	_check("a second load reads no file (%d loads, %d hits)" % [MaterialLibrary.loads, MaterialLibrary.hits],
			loads == 3 and MaterialLibrary.loads == 3 and MaterialLibrary.hits == 3)
	_check("and returns the same textures", a["albedo"] == b["albedo"] and a["normal"] == b["normal"]
			and a["orm"] == b["orm"])
	var m1 := MaterialLibrary.get_material("red_brick", {"tiling": 2.0})
	var m2 := MaterialLibrary.get_material("red_brick", {"tiling": 2.0})
	var m3 := MaterialLibrary.get_material("red_brick", {"tint": Color.GRAY})
	_check("same options: one shared material; other options: another, on the same textures", m1 == m2 and m1 != m3
			and m3.get_shader_parameter("albedo_map") == m1.get_shader_parameter("albedo_map")
			and MaterialLibrary.loads == 3)


## Inside an assistant's lit room the built-in rooms keep their plain materials (that room relights only those).
func _lit_rooms() -> void:
	var s := GDScript.new()
	s.source_code = "extends Node3D\nvar doc := {}\nstatic func lighting_of(d: Dictionary) -> Dictionary:\n" \
			+ "\treturn {\"lit\": d.has(\"light\")}\n"
	s.reload()
	var holder: Node3D = s.new()
	var base := Node3D.new()
	var part := Node3D.new()
	holder.add_child(base)
	base.add_child(part)
	_check("an unlit assistant room: textures", not MaterialLibrary.in_lit_room(part))
	holder.set("doc", {"light": {"key": {}}})
	_check("a lit one: plain materials", MaterialLibrary.in_lit_room(part))
	var alone := Node3D.new()
	_check("no assistant room: textures", not MaterialLibrary.in_lit_room(alone))
	alone.free()
	holder.free()


func _credits() -> void:
	var text := FileAccess.get_file_as_string(MaterialLibrary.DIR.path_join("CREDITS.md"))
	var missing: Array[String] = []
	for id in MaterialLibrary.ids():
		var src: Dictionary = MaterialLibrary.entry(id)["source"]
		if not ("| `%s` " % id) in text or not str(src["url"]) in text:
			missing.append(id)
	_check("CREDITS.md lists every material with its page (missing: %s)" % [missing], missing.is_empty())
	_check("CREDITS.md states the licence", "CC0 1.0 Universal" in text)


func _command() -> void:
	MaterialLibrary.register_commands(null)
	_check("the materials command: read, for the assistant", DevCommands.assistant_level("materials") == "read"
			and DevCommands.get_spec("materials")["level"] == "read")
	var params: Array = DevCommands.get_spec("materials")["params"]
	_check("its params are described", params.all(func(p: Dictionary) -> bool:
			return str(p.get("description", "")) != ""))
	var r: Dictionary = await DevCommands.execute("materials", {})
	_check("it lists every material with name and tags", r["ok"] and (r["result"] as Array).size()
			== MaterialLibrary.ids().size() and (r["result"] as Array).all(func(e: Dictionary) -> bool:
				return e.has("name") and e.has("tags") and e.has("id")))
	r = await DevCommands.execute("materials", {"tag": "floor"})
	_check("tag: only those (%d floors)" % (r["result"] as Array).size(), r["ok"]
			and (r["result"] as Array).size() > 3 and (r["result"] as Array).all(func(e: Dictionary) -> bool:
				return "floor" in e["tags"]))


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if ok:
		print("ok   ", what)
	else:
		_failures += 1
		print("FAIL ", what)
