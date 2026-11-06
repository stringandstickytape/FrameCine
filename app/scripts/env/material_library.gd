extends RefCounted

## The material library (docs/materials.md): CC0 texture sets for room surfaces, one catalogue entry per material in
## res://materials/<id>.json (id, name, tags, maps, tiling in metres per repeat, tint, roughness_scale,
## normal_strength, specular, sheen, swatch, source), the maps as .mtex files (ASTC 8 x 8 with every mip level, packed
## by tools/materials/build_materials.py). Drawn by shaders/room_material.gdshader: the rooms' fake light (ambient
## plus the screen's spill) with the maps' detail, no lights or shadows.
##
## Each map is read once and kept: every material made from it shares the one texture. The file's bytes go straight
## to the GPU (Image.create_from_data); a GPU without ASTC (a PC) gets them decompressed by the engine.
## Static; preload to use:
##   const MaterialLibrary := preload("res://scripts/env/material_library.gd")
##   MaterialLibrary.list()                          [{id, name, tags, tiling, swatch, size}], by name
##   MaterialLibrary.entry("velvet")                 the catalogue entry, {} if unknown
##   MaterialLibrary.get_material("velvet", {"tint": Color(0.5, 0.1, 0.1)})   -> ShaderMaterial, null if unknown
##   MaterialLibrary.apply(mesh_instance, "oak_planks", {"tiling": 1.5}, surface)   -> ShaderMaterial
## Options (all optional): colour (Color: the material shows this colour on average, its pattern kept; a room's own
## colour), tint (Color, multiplies the maps' colour, after colour), tiling (metres per repeat), turn (degrees: the
## pattern turned on the surface), offset (Vector2,
## metres), uv (true: the mesh's UVs, repeated `repeat` (Vector2) times; default: the surface's own axes in metres),
## triplanar (true: three blended projections, for meshes with neither flat faces nor UVs; three times the fetches),
## roughness_scale, normal_strength, specular, sheen, pleats (folds per metre, curtains), pleat_depth, spill and
## floor_darkening (as env_unlit.gdshader), emission (Color, added on top), lit ({sky_top, sky_bottom, screen}: an
## assistant's room with real lighting, room_material_lit.gdshader; assistant_room.gd lighting_of()), house
## ({sky_top, sky_bottom}: a built-in room lit for real and ready for a lightmap, room_material_house.gdshader; the
## cinema sets its other uniforms). Materials with
## the same id and options are one shared ShaderMaterial: duplicate() it before changing it for one surface only.
##   MaterialLibrary.lit_variant(material, lighting)  a library material as its lit form (shared too)
##   MaterialLibrary.id_of(material), shown_colour(material)   which library material a surface shows, and its colour
##
## User materials (docs/materials.md, "User materials"): imported from Poly Haven, ambientCG or Megascans through Fab
## (scripts/env/surface_store.gd, surface_import.gd) into user://materials/<id>.json with their maps beside it in
## user://materials/textures (PNG or JPEG, mipmaps made on load; or .mtex where the engine can compress to ASTC).
## They are in list(), entry() and get_material() like the bundled ones, with "user": true and their source.
##   MaterialLibrary.user_ids(), forget_user()      the user materials; the catalogue read again (an import, a delete)
##   MaterialLibrary.memory()                       {bytes, user_bytes, textures}: what the loaded maps take

const DIR := "res://materials"
const USER_DIR := "user://materials"
## Where the user materials are (tests point it elsewhere).
static var user_dir := USER_DIR
const SHADER := preload("res://shaders/room_material.gdshader")
const SHADER_TRIPLANAR := preload("res://shaders/room_material_triplanar.gdshader")
const SHADER_LIT := preload("res://shaders/room_material_lit.gdshader")
const SHADER_LIT_TRIPLANAR := preload("res://shaders/room_material_lit_triplanar.gdshader")
const SHADER_HOUSE := preload("res://shaders/room_material_house.gdshader")
const MAPS: Array[String] = ["albedo", "normal", "orm"]
## .mtex: "MTEX", version, block size (x | y << 16), width, height, mip levels, flags, data size; then the data.
const MTEX_MAGIC := "MTEX"
const MTEX_HEADER := 32
const FLAG_SRGB := 1
const FLAG_NORMAL := 2
## Options passed to the shader as they are (the catalogue's tunables are the defaults).
const TUNABLES: Array[String] = ["roughness_scale", "normal_strength", "specular", "sheen", "pleats", "pleat_depth",
		"spill", "floor_darkening", "relief", "ao_strength"]

static var _catalogue := {}
static var _textures := {}
## path -> bytes of GPU memory a loaded map takes (its file's blocks, or its pixels with mipmaps).
static var _texture_bytes := {}
static var _materials := {}
## Whether the GPU samples ASTC (-1: not asked yet).
static var _astc := -1
## Load counts, for the tests and the benchmark: files read, cache hits.
static var loads := 0
static var hits := 0


## Every material: [{id, name, tags, tiling, swatch, size, source, user}], sorted by name. source: "bundled", or
## where a user material came from ("polyhaven", "ambientcg", "megascans").
static func list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in _entries().values():
		var user := bool(e.get("user", false))
		out.append({"id": e["id"], "name": e.get("name", e["id"]), "tags": e.get("tags", []),
				"tiling": e.get("tiling", 1.0), "swatch": e.get("swatch", "#808080"), "size": e.get("size", 1024),
				"source": str(e.get("source", {}).get("site", "")) if user else "bundled", "user": user})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["name"]) < str(b["name"]))
	return out


static func ids() -> Array[String]:
	var out: Array[String] = []
	out.assign(_entries().keys())
	out.sort()
	return out


static func has(id: String) -> bool:
	return _entries().has(id)


## The catalogue entry (a copy), {} when there is no such material.
static func entry(id: String) -> Dictionary:
	return _entries().get(id, {}).duplicate(true)


## A material's three textures {albedo, normal, orm}, each read once and shared; {} when unknown or a file is bad.
static func textures(id: String) -> Dictionary:
	var e: Dictionary = _entries().get(id, {})
	if e.is_empty():
		return {}
	var out := {}
	var dir := user_dir if bool(e.get("user", false)) else DIR
	for m in MAPS:
		var path := dir.path_join(str(e.get("maps", {}).get(m, "")))
		var tex := load_texture(path)
		if tex == null:
			return {}
		out[m] = tex
	return out


## A shared ShaderMaterial for this id and options; null when the id is unknown (or its files are bad).
static func get_material(id: String, options := {}) -> ShaderMaterial:
	if options.get("lit") is Dictionary:
		# The lighting's colours as opaque Colors in the key, whether given as Color (any alpha: the shader has no
		# use for it), Vector3 (a uniform read back) or text.
		var lit: Dictionary = (options["lit"] as Dictionary).duplicate()
		for k in ["sky_top", "sky_bottom"]:
			if lit.has(k):
				var c := _colour(lit[k])
				c.a = 1.0
				lit[k] = c
		options = options.duplicate()
		options["lit"] = lit
	var key := "%s %s" % [id, var_to_str(options)]
	if _materials.has(key) and is_instance_valid(_materials[key]):
		return _materials[key]
	var e: Dictionary = _entries().get(id, {})
	var tex := textures(id)
	if e.is_empty() or tex.is_empty():
		return null
	var m := ShaderMaterial.new()
	m.resource_name = id
	m.shader = SHADER_TRIPLANAR if options.get("triplanar", false) else SHADER
	if options.get("lit") is Dictionary:
		m.shader = SHADER_LIT_TRIPLANAR if options.get("triplanar", false) else SHADER_LIT
		_light(m, options["lit"])
	if options.get("house") is Dictionary:
		m.shader = SHADER_HOUSE
		_light(m, options["house"])
	if options.has("emission"):
		m.set_shader_parameter("emission", _colour(options["emission"]))
	m.set_shader_parameter("albedo_map", tex["albedo"])
	m.set_shader_parameter("normal_map", tex["normal"])
	m.set_shader_parameter("orm_map", tex["orm"])
	var tint := Color.from_string(str(e.get("tint", "#ffffff")), Color.WHITE)
	if options.has("colour"):
		tint = tint_for(id, _colour(options["colour"]))
	if options.has("tint"):
		tint *= _colour(options["tint"])
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("tiling", maxf(float(options.get("tiling", e.get("tiling", 1.0))), 0.01))
	m.set_shader_parameter("uv_offset", options.get("offset", Vector2.ZERO) / maxf(float(options.get("tiling",
			e.get("tiling", 1.0))), 0.01))
	m.set_shader_parameter("uv_turn", deg_to_rad(float(options.get("turn", 0.0))))
	m.set_shader_parameter("use_mesh_uv", bool(options.get("uv", false)))
	m.set_shader_parameter("uv_repeat", options.get("repeat", Vector2.ONE))
	for k in TUNABLES:
		if options.has(k):
			m.set_shader_parameter(k, float(options[k]))
		elif e.has(k):
			m.set_shader_parameter(k, float(e[k]))
	_materials[key] = m
	return m


## The tint that makes this material show `colour` on average (its swatch, the maps' mean colour, becomes colour),
## so a room keeps its colours with the maps' detail on top. Worked in linear light, returned as sRGB.
static func tint_for(id: String, colour: Color) -> Color:
	var swatch := Color.from_string(str(_entries().get(id, {}).get("swatch", "#ffffff")), Color.WHITE).srgb_to_linear()
	var c := colour.srgb_to_linear()
	return Color(c.r / maxf(swatch.r, 0.01), c.g / maxf(swatch.g, 0.01), c.b / maxf(swatch.b, 0.01)).linear_to_srgb()


static func _colour(v: Variant) -> Color:
	if v is Color:
		return v
	if v is Vector3:
		return Color(v.x, v.y, v.z)
	return Color.from_string(str(v), Color.WHITE)


## A colour as the Vector3 a vec3 uniform wants: a Color in a vec3 uniform renders dimmer than its values and is
## reset to zero when the material's properties are listed (duplicate(), saving).
static func _vec3(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)


static func _light(m: ShaderMaterial, lighting: Dictionary) -> void:
	m.set_shader_parameter("sky_top", _vec3(_colour(lighting.get("sky_top", Color.BLACK))))
	m.set_shader_parameter("sky_bottom", _vec3(_colour(lighting.get("sky_bottom", Color.BLACK))))
	m.set_shader_parameter("screen_light", float(lighting.get("screen", 0.0)))


## True when `m` is a library material (either shader, lit or not).
static func is_library(m: Material) -> bool:
	return m is ShaderMaterial and (m as ShaderMaterial).shader in [SHADER, SHADER_TRIPLANAR, SHADER_LIT,
			SHADER_LIT_TRIPLANAR, SHADER_HOUSE]


## The library material's id a surface's material shows, "" when it is not one.
static func id_of(m: Material) -> String:
	return str(m.resource_name) if is_library(m) else ""


## The colour a library material shows on average: its swatch (the base colour map's mean) times its tint, as sRGB.
static func shown_colour(m: Material) -> Color:
	if not is_library(m):
		return Color.WHITE
	var swatch := Color.from_string(str(_entries().get(id_of(m), {}).get("swatch", "#ffffff")), Color.WHITE)
	var tint: Variant = (m as ShaderMaterial).get_shader_parameter("tint")
	var t := (tint as Color) if tint is Color else Color.WHITE
	var c := swatch.srgb_to_linear() * t.srgb_to_linear()
	return Color(minf(c.r, 1.0), minf(c.g, 1.0), minf(c.b, 1.0)).linear_to_srgb()


static var _lit_variants := {}


## A library material (unlit) as its lit form for an assistant's room with real lighting (lighting: {sky_top,
## sky_bottom, screen}, assistant_room.gd lighting_of()): the same maps and settings on room_material_lit.gdshader. A
## built-in room's surfaces are made this way when that room is lit. One lit form per material and lighting, shared;
## null when `src` is not an unlit library material.
static func lit_variant(src: Material, lighting: Dictionary) -> ShaderMaterial:
	if not (src is ShaderMaterial) or not ((src as ShaderMaterial).shader in [SHADER, SHADER_TRIPLANAR]):
		return null
	var s := src as ShaderMaterial
	var key := "%d %s" % [s.get_instance_id(), var_to_str(lighting)]
	if _lit_variants.has(key) and is_instance_valid(_lit_variants[key][1]):
		return _lit_variants[key][1]
	var m := ShaderMaterial.new()
	m.resource_name = s.resource_name
	m.shader = SHADER_LIT_TRIPLANAR if s.shader == SHADER_TRIPLANAR else SHADER_LIT
	for u: Dictionary in s.shader.get_shader_uniform_list():
		var v: Variant = s.get_shader_parameter(u["name"])
		if v != null:
			m.set_shader_parameter(u["name"], v)
	_light(m, lighting)
	# The source kept with it, so its instance id isn't given to another material while this entry lives.
	_lit_variants[key] = [s, m]
	return m


## Puts a library material on a mesh: on one surface (its surface override) or, with surface -1, on all of it
## (material_override; MultiMeshInstance3D too). Returns the material, null when the id is unknown.
static func apply(target: GeometryInstance3D, id: String, options := {}, surface := -1) -> ShaderMaterial:
	var m := get_material(id, options)
	if m == null or target == null:
		return null
	if surface >= 0 and target is MeshInstance3D:
		(target as MeshInstance3D).set_surface_override_material(surface, m)
	else:
		target.material_override = m
	return m


## A .mtex file as a texture (cached by path): the ASTC blocks as they are, with their mip levels. A user material's
## PNG or JPEG (no .mtex): read, its mipmaps made, uncompressed. null if bad.
static func load_texture(path: String) -> Texture2D:
	if _textures.has(path):
		hits += 1
		return _textures[path]
	if path.get_extension() != "mtex":
		var img := Image.load_from_file(path) if FileAccess.file_exists(path) else null
		if img == null or img.is_empty():
			push_warning("material library: %s is not a picture" % path.get_file())
			return null
		if img.is_compressed():
			img.decompress()
		if not img.has_mipmaps():
			img.generate_mipmaps()
		loads += 1
		var t := ImageTexture.create_from_image(img)
		_textures[path] = t
		# RGB is held as RGBA on the GPU.
		_texture_bytes[path] = img.get_data_size() * (4 if img.get_format() == Image.FORMAT_RGB8 else 3) / 3
		return t
	var bytes := FileAccess.get_file_as_bytes(path)
	var image := decode_mtex(bytes)
	if image == null:
		push_warning("material library: %s is not a texture (%d bytes)" % [path, bytes.size()])
		return null
	loads += 1
	_texture_bytes[path] = bytes.size() - MTEX_HEADER
	if not _gpu_has_astc():
		# A PC's GPU: the engine would decompress it anyway, with a warning per texture.
		image.decompress()
	var tex := ImageTexture.create_from_image(image)
	_textures[path] = tex
	return tex


## GPU memory of the maps loaded so far: {bytes (all), user_bytes (the user materials'), textures (how many)}.
static func memory() -> Dictionary:
	var all := 0
	var user := 0
	for p: String in _texture_bytes:
		all += int(_texture_bytes[p])
		if p.begins_with(user_dir):
			user += int(_texture_bytes[p])
	return {"bytes": all, "user_bytes": user, "textures": _texture_bytes.size()}


## The user materials' ids.
static func user_ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in _entries():
		if bool(_entries()[id].get("user", false)):
			out.append(id)
	out.sort()
	return out


## The catalogue is read again (a user material was imported or deleted); a deleted one's maps are let go.
static func forget_user() -> void:
	_catalogue.clear()
	for p: String in _textures.keys():
		if p.begins_with(user_dir) and not FileAccess.file_exists(p):
			_textures.erase(p)
			_texture_bytes.erase(p)
	for k: String in _materials.keys():
		if not has(k.get_slice(" ", 0)):
			_materials.erase(k)


static func _gpu_has_astc() -> bool:
	if _astc == -1:
		var rd := RenderingServer.get_rendering_device()
		var usage := RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
		_astc = 1 if rd == null or rd.texture_is_format_supported_for_usage(
				RenderingDevice.DATA_FORMAT_ASTC_8x8_UNORM_BLOCK, usage) else 0
	return _astc == 1


## The image in a .mtex file's bytes, null when the header or the size is wrong.
static func decode_mtex(bytes: PackedByteArray) -> Image:
	if bytes.size() < MTEX_HEADER or bytes.slice(0, 4).get_string_from_ascii() != MTEX_MAGIC:
		return null
	var version := bytes.decode_u32(4)
	var block := bytes.decode_u32(8)
	var w := bytes.decode_u32(12)
	var h := bytes.decode_u32(16)
	var size := bytes.decode_u32(28)
	if version != 1 or block != (8 | (8 << 16)) or w == 0 or h == 0 or w > 8192 or h > 8192:
		return null
	if bytes.size() != MTEX_HEADER + size or size != astc8_size(w, h):
		return null
	return Image.create_from_data(w, h, true, Image.FORMAT_ASTC_8x8, bytes.slice(MTEX_HEADER))


## Bytes of an ASTC 8 x 8 picture with every mip level down to 1 x 1 (16 bytes a block), as the engine lays it out.
static func astc8_size(w: int, h: int) -> int:
	var total := 0
	while true:
		total += ceili(w / 8.0) * ceili(h / 8.0) * 16
		if w == 1 and h == 1:
			break
		w = maxi(1, w >> 1)
		h = maxi(1, h >> 1)
	return total


## The header's fields: {width, height, mips, flags, data_size}, {} when it is not a .mtex.
static func mtex_info(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < MTEX_HEADER or bytes.slice(0, 4).get_string_from_ascii() != MTEX_MAGIC:
		return {}
	return {"width": bytes.decode_u32(12), "height": bytes.decode_u32(16), "mips": bytes.decode_u32(20),
			"flags": bytes.decode_u32(24), "data_size": bytes.decode_u32(28)}


## Forgets the loaded textures and materials (tests; a material in use keeps its own).
static func clear_cache() -> void:
	_textures.clear()
	_texture_bytes.clear()
	_materials.clear()
	_lit_variants.clear()
	_catalogue.clear()
	loads = 0
	hits = 0


static func _entries() -> Dictionary:
	if not _catalogue.is_empty():
		return _catalogue
	for f in DirAccess.get_files_at(DIR):
		if f.get_extension() != "json":
			continue
		var e: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR.path_join(f)))
		if e is Dictionary and str(e.get("id", "")) == f.get_basename():
			_catalogue[e["id"]] = e
		else:
			push_warning("material library: %s is not a catalogue entry" % f)
	# The user's own, beside them (an id the bundled set has stays the bundled one).
	if DirAccess.dir_exists_absolute(user_dir):
		for f in DirAccess.get_files_at(user_dir):
			if f.get_extension() != "json" or _catalogue.has(f.get_basename()):
				continue
			var e: Variant = JSON.parse_string(FileAccess.get_file_as_string(user_dir.path_join(f)))
			if e is Dictionary and str(e.get("id", "")) == f.get_basename() and e.get("maps") is Dictionary:
				e["user"] = true
				_catalogue[e["id"]] = e
	return _catalogue


## The `materials` command (scripts/dev/command_host.gd registers it): the list, for the assistant and the dev link.
static func register_commands(_host: Node) -> void:
	var DevCommands := load("res://scripts/dev/dev_commands.gd")
	DevCommands.register("materials", func(a: Dictionary, _ctx: RefCounted) -> Variant:
			var tag := str(a["tag"]).strip_edges().to_lower()
			return list().filter(func(e: Dictionary) -> bool: return tag == "" or tag in e["tags"]), {
		"description": "The material library: textured surfaces a room can use (wood floors, carpet, velvet, "
				+ "leather, plaster, brick, stone, metal...), each with its id, name, tags, metres per repeat of its "
				+ "pattern, mean colour (swatch) and texture size; source: bundled (with the app), or polyhaven, "
				+ "ambientcg or megascans for the user's own imports (material_search, material_import).",
		"params": [{"name": "tag", "type": "string", "default": "",
				"description": "only materials with this tag (floor, wall, seat, curtain, fabric, wood, metal, ...)"}],
		"assistant": "read",
		"returns": "[{id, name, tags, tiling, swatch, size, source, user}]"})
