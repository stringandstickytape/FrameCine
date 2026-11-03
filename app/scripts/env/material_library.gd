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
## colour), tint (Color, multiplies the maps' colour, after colour), tiling (metres per repeat), offset (Vector2,
## metres), uv (true: the mesh's UVs, repeated `repeat` (Vector2) times; default: the surface's own axes in metres),
## triplanar (true: three blended projections, for meshes with neither flat faces nor UVs; three times the fetches),
## roughness_scale, normal_strength, specular, sheen, pleats (folds per metre, curtains), pleat_depth, spill and
## floor_darkening (as env_unlit.gdshader). Materials with the same id and options are one shared ShaderMaterial:
## duplicate() it before changing it for one surface only.

const DIR := "res://materials"
const SHADER := preload("res://shaders/room_material.gdshader")
const SHADER_TRIPLANAR := preload("res://shaders/room_material_triplanar.gdshader")
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
static var _materials := {}
## Whether the GPU samples ASTC (-1: not asked yet).
static var _astc := -1
## Load counts, for the tests and the benchmark: files read, cache hits.
static var loads := 0
static var hits := 0


## Every material: [{id, name, tags, tiling, swatch, size}], sorted by name.
static func list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in _entries().values():
		out.append({"id": e["id"], "name": e.get("name", e["id"]), "tags": e.get("tags", []),
				"tiling": e.get("tiling", 1.0), "swatch": e.get("swatch", "#808080"), "size": e.get("size", 1024)})
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
	for m in MAPS:
		var path := DIR.path_join(str(e.get("maps", {}).get(m, "")))
		var tex := load_texture(path)
		if tex == null:
			return {}
		out[m] = tex
	return out


## A shared ShaderMaterial for this id and options; null when the id is unknown (or its files are bad).
static func get_material(id: String, options := {}) -> ShaderMaterial:
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
	return v if v is Color else Color.from_string(str(v), Color.WHITE)


## True when `node` is (inside) the base of an assistant's room with real lighting (scripts/assistant/assistant_room.gd,
## found by its lighting_of() and doc): that room relights the base's plain materials, which it can't do with library
## materials yet, so the built-in rooms keep their plain ones there.
static func in_lit_room(node: Node) -> bool:
	var p := node.get_parent() if node != null else null
	while p != null:
		if p.has_method("lighting_of") and p.get("doc") is Dictionary:
			return bool((p.call("lighting_of", p.get("doc")) as Dictionary).get("lit", false))
		p = p.get_parent()
	return false


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


## A .mtex file as a texture (cached by path): the ASTC blocks as they are, with their mip levels. null if bad.
static func load_texture(path: String) -> Texture2D:
	if _textures.has(path):
		hits += 1
		return _textures[path]
	var bytes := FileAccess.get_file_as_bytes(path)
	var image := decode_mtex(bytes)
	if image == null:
		push_warning("material library: %s is not a texture (%d bytes)" % [path, bytes.size()])
		return null
	loads += 1
	if not _gpu_has_astc():
		# A PC's GPU: the engine would decompress it anyway, with a warning per texture.
		image.decompress()
	var tex := ImageTexture.create_from_image(image)
	_textures[path] = tex
	return tex


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
	_materials.clear()
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
	return _catalogue


## The `materials` command (scripts/dev/command_host.gd registers it): the list, for the assistant and the dev link.
static func register_commands(_host: Node) -> void:
	var DevCommands := load("res://scripts/dev/dev_commands.gd")
	DevCommands.register("materials", func(a: Dictionary, _ctx: RefCounted) -> Variant:
			var tag := str(a["tag"]).strip_edges().to_lower()
			return list().filter(func(e: Dictionary) -> bool: return tag == "" or tag in e["tags"]), {
		"description": "The material library: textured surfaces a room can use (wood floors, carpet, velvet, "
				+ "leather, plaster, brick, stone, metal...), each with its id, name, tags, metres per repeat of its "
				+ "pattern, mean colour (swatch) and texture size.",
		"params": [{"name": "tag", "type": "string", "default": "",
				"description": "only materials with this tag (floor, wall, seat, curtain, fabric, wood, metal, ...)"}],
		"assistant": "read",
		"returns": "[{id, name, tags, tiling, swatch, size}]"})
