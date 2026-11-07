extends RefCounted

## A surface from Poly Haven, ambientCG or Megascans (through Fab) made a user material (docs/materials.md, "User
## materials"): user://materials/<id>.json beside the bundled catalogue's entries, with its maps in
## user://materials/textures, so MaterialLibrary.list() and get_material() have it like any other. The viewer's own
## data: nothing of it goes into the repository or a release (a CC0 one may be promoted into the bundled set: the
## entry keeps its site and asset, which tools/materials/build_materials.py takes).
##
## What is kept: the base colour with the ambient occlusion multiplied in (the rooms are drawn with simple lighting,
## as fab_import.gd does for objects), the normal map (OpenGL, green up) and roughness (or gloss turned round),
## metalness where there is one. Height and displacement are dropped. The tiling is the surface's real size where its
## metadata gives one (Poly Haven's dimensions, ambientCG's, a Megascans scan's area).
##
## The size: this engine build has no ASTC compressor (its templates are built with ASTCENC_DECOMPRESS_ONLY and the
## compressor's hook is TOOLS_ENABLED only; docs/materials.md), so the maps are 1K, uncompressed, with mipmaps (the
## packed map at half that): about 12.6 MB of GPU memory a material. Where Image.compress() can make ASTC (a build
## with the encoder), 2K as .mtex blocks instead: about 3.2 MB.
##
##   import_maps(site, asset, info, maps) -> {ok, entry} or {ok: false, error}        (safe on a worker thread)
##   import_megascans_zip(path, listing), import_ambientcg_zip(path, asset, info) -> the same
##   material_for_listing(uid), material_for_asset(site, asset) -> the user material's entry or {}
##   delete(id), loaded() (the catalogue read again: main thread), astc_available(), user_entries()

const MaterialLibrary := preload("res://scripts/env/material_library.gd")
const FabImport := preload("res://scripts/assistant/fab_import.gd")

## Each source: its name, the id's prefix, the licence, an asset's page.
const SITES := {
	"polyhaven": {"name": "Poly Haven", "prefix": "ph", "licence": "CC0 1.0", "page": "https://polyhaven.com/a/%s"},
	"ambientcg": {"name": "ambientCG", "prefix": "acg", "licence": "CC0 1.0",
			"page": "https://ambientcg.com/view?id=%s"},
	"megascans": {"name": "Megascans", "prefix": "ms", "licence": "Fab Standard License (the viewer's own)",
			"page": "https://www.fab.com/listings/%s"},
}
const SIZE := 1024
const ASTC_SIZE := 2048
const MAX_ZIP_BYTES := 200 << 20
## Map names in Megascans' and ambientCG's files (the last part of the name), by the slot they fill.
const MAP_NAMES := {
	"albedo": ["basecolor", "albedo", "diffuse", "color", "col"],
	"normal": ["normal", "normalgl", "nor_gl"],
	"roughness": ["roughness", "rough"],
	"gloss": ["gloss"],
	"ao": ["ao", "ambientocclusion", "occlusion"],
	"metallic": ["metalness", "metallic", "metal"],
}

static var _astc := -1


static func dir() -> String:
	return MaterialLibrary.user_dir


## "ph_brick_wall_001", "acg_bricks076", "ms_tgzpcj3bw": the source's prefix and its asset id, lower case.
static func id_for(site: String, asset: String) -> String:
	var clean := ""
	for c in asset.to_lower():
		clean += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "-" else "_"
	return ("%s_%s" % [SITES.get(site, {"prefix": "u"})["prefix"], clean]).left(64)


static func cc0(site: String) -> bool:
	return site in ["polyhaven", "ambientcg"]


## Whether this engine can compress to ASTC at run time (an 8 x 8 test picture, once).
static func astc_available() -> bool:
	if _astc < 0:
		var img := Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
		var was := Engine.print_error_messages
		Engine.print_error_messages = false
		_astc = 1 if img.compress(Image.COMPRESS_ASTC, Image.COMPRESS_SOURCE_GENERIC, Image.ASTC_FORMAT_8x8) == OK else 0
		Engine.print_error_messages = was
	return _astc == 1


## The user materials' entries, read from their folder (not the library's cache: this runs on worker threads too).
static func user_entries() -> Array:
	var out: Array = []
	if not DirAccess.dir_exists_absolute(dir()):
		return out
	for f in DirAccess.get_files_at(dir()):
		if f.get_extension() != "json":
			continue
		var e: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir().path_join(f)))
		if e is Dictionary and str(e.get("id", "")) == f.get_basename():
			out.append(e)
	return out


static func material_for_listing(uid: String) -> Dictionary:
	for e: Dictionary in user_entries():
		if uid != "" and str(e.get("source", {}).get("listing", "")) == uid:
			return e
	return {}


static func material_for_asset(site: String, asset: String) -> Dictionary:
	if asset == "":
		return {}
	var id := id_for(site, asset)
	for e: Dictionary in user_entries():
		if str(e["id"]) == id:
			return e
	return {}


## The library reads its catalogue again (after an import or a delete). Main thread.
static func loaded() -> void:
	MaterialLibrary.forget_user()


## A user material gone: its entry and maps.
static func delete(id: String) -> bool:
	var path := dir().path_join(id + ".json")
	if not FileAccess.file_exists(path) or not RegEx.create_from_string("^[a-z0-9_-]{1,64}$").search(id):
		return false
	var e: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if e is Dictionary and e.get("maps") is Dictionary:
		for m: String in e["maps"]:
			DirAccess.remove_absolute(dir().path_join(str(e["maps"][m])))
	DirAccess.remove_absolute(path)
	return true


# --- Reading ---------------------------------------------------------------------------------------------------------

## JPEG, PNG or WebP bytes as an image (by their first bytes), or null.
static func image_of(bytes: PackedByteArray) -> Image:
	if bytes.size() < 12:
		return null
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if bytes[0] == 0xFF and bytes[1] == 0xD8:
		err = img.load_jpg_from_buffer(bytes)
	elif bytes[0] == 0x89 and bytes[1] == 0x50:
		err = img.load_png_from_buffer(bytes)
	elif bytes.slice(0, 4).get_string_from_ascii() == "RIFF":
		err = img.load_webp_from_buffer(bytes)
	if err != OK or img.is_empty():
		return null
	if img.is_compressed():
		img.decompress()
	return img


static func _slot_of(file: String) -> String:
	var base := file.get_file().get_basename().to_lower()
	var last := base.rsplit("_", true, 1)[-1]
	for slot: String in MAP_NAMES:
		if last in MAP_NAMES[slot]:
			return slot
	return ""


## A zip's maps (slot -> Image; the first of each) and its first .json with an id ({} if none).
static func _read_zip(path: String) -> Dictionary:
	if FileAccess.file_exists(path) and FileAccess.get_size(path) > MAX_ZIP_BYTES:
		return {"error": "the zip is over %d MB" % (MAX_ZIP_BYTES >> 20)}
	var z := ZIPReader.new()
	if z.open(path) != OK:
		return {"error": "can't open %s" % path.get_file()}
	var info := {}
	var maps := {}
	for f in z.get_files():
		var ext := f.get_extension().to_lower()
		if ext == "json" and info.is_empty():
			var j: Variant = JSON.parse_string(z.read_file(f).get_string_from_utf8())
			if j is Dictionary and (j as Dictionary).has("id"):
				info = j
		elif ext in ["jpg", "jpeg", "png"]:
			var slot := _slot_of(f)
			if slot != "" and not maps.has(slot):
				var img := image_of(z.read_file(f))
				if img != null:
					maps[slot] = img
	z.close()
	return {"info": info, "maps": maps}


## A Megascans surface's texture set (Fab's zip: <Name>_<id>_<res>_<Map>.jpg and <id>.json) as a user material.
## listing: the Fab listing it came from (kept, so a search shows it is in the library).
static func import_megascans_zip(path: String, listing := "") -> Dictionary:
	var z := _read_zip(path)
	if z.has("error"):
		return {"ok": false, "error": z["error"]}
	var j: Dictionary = z["info"]
	if j.is_empty():
		return {"ok": false, "error": "%s isn't a Megascans surface (no asset .json)" % path.get_file()}
	var name := str(j.get("name", "")).strip_edges()
	if name == "" and j.get("semanticTags") is Dictionary:
		name = str(j["semanticTags"].get("name", ""))
	var tags: Array = []
	for t: Variant in j.get("tags", []):
		if str(t).strip_edges() != "":
			tags.append(str(t).strip_edges().to_lower())
	var info := {"name": name if name != "" else str(j["id"]), "tags": tags.slice(0, 8),
			"tiling": megascans_size(j), "listing": listing}
	return import_maps("megascans", str(j["id"]), info, z["maps"])


## A Megascans asset's real size in metres from its .json: its scan area ("2x2 m"), else its semantic size; 0 if none.
static func megascans_size(j: Dictionary) -> float:
	for e: Variant in j.get("meta", []):
		if e is Dictionary and str(e.get("key", "")) == "scanArea":
			var text := str(e.get("value", "")).to_lower()
			var m := RegEx.create_from_string("([0-9]+(?:\\.[0-9]+)?)\\s*x\\s*([0-9]+(?:\\.[0-9]+)?)\\s*(cm|m)").search(text)
			if m != null:
				return float(m.get_string(1)) * (0.01 if m.get_string(3) == "cm" else 1.0)
	var sem: Variant = j.get("semanticTags")
	if sem is Dictionary and float((sem as Dictionary).get("maxSize", 0)) > 0.0:
		return float(sem["maxSize"])
	return 0.0


## An ambientCG material's zip (<Asset>_1K-JPG.zip: <Asset>_1K-JPG_Color.jpg, _NormalGL, _Roughness, ...) as a user
## material. info: {name, tags, tiling} from its search result.
static func import_ambientcg_zip(path: String, asset: String, info: Dictionary) -> Dictionary:
	var z := _read_zip(path)
	if z.has("error"):
		return {"ok": false, "error": z["error"]}
	var maps: Dictionary = z["maps"]
	# ambientCG ships both normal conventions: only the OpenGL one is read (NormalDX is no slot).
	return import_maps("ambientcg", asset, info, maps)


# --- Making the material ---------------------------------------------------------------------------------------------

## The maps (slot -> Image: albedo and normal needed; roughness or gloss, ao, metallic if there) written as a user
## material. info: name, tags, tiling (metres, 0: 1 m), author, listing. Safe on a worker thread.
static func import_maps(site: String, asset: String, info: Dictionary, maps: Dictionary) -> Dictionary:
	if not SITES.has(site):
		return {"ok": false, "error": "no source %s" % site}
	if maps.get("albedo") == null or maps.get("normal") == null:
		return {"ok": false, "error": "the download has no base colour or normal map"}
	var id := id_for(site, asset)
	var astc := astc_available()
	var size := ASTC_SIZE if astc else SIZE
	var src_size := maxi((maps["albedo"] as Image).get_width(), (maps["albedo"] as Image).get_height())
	while size > 256 and size / 2 >= src_size:
		size /= 2
	var orm_size := size if astc else size / 2
	var albedo := _square(maps["albedo"], size, Image.FORMAT_RGB8)
	if maps.get("ao") != null:
		FabImport._multiply(albedo, _square(maps["ao"], size, Image.FORMAT_RGB8))
	var normal := _normal_xy(_square(maps["normal"], size, Image.FORMAT_RGB8))
	var rough: Image = null
	if maps.get("roughness") != null:
		rough = _square(maps["roughness"], orm_size, Image.FORMAT_L8)
	elif maps.get("gloss") != null:
		rough = _square(maps["gloss"], orm_size, Image.FORMAT_L8)
		FabImport._invert(rough)
		rough.convert(Image.FORMAT_L8)
	var metal: Image = _square(maps["metallic"], orm_size, Image.FORMAT_L8) if maps.get("metallic") != null else null
	var orm := _orm(orm_size, rough, metal)
	DirAccess.make_dir_recursive_absolute(dir().path_join("textures"))
	var out := {}
	var gpu := 0
	for slot: String in ["albedo", "normal", "orm"]:
		var img: Image = {"albedo": albedo, "normal": normal, "orm": orm}[slot]
		var rel := ""
		if astc:
			rel = "textures/%s_%s.mtex" % [id, slot]
			var bytes := _mtex(img, slot)
			if bytes.is_empty():
				return {"ok": false, "error": "the %s map could not be compressed" % slot}
			var f := FileAccess.open(dir().path_join(rel), FileAccess.WRITE)
			if f == null:
				return {"ok": false, "error": "can't write the maps"}
			f.store_buffer(bytes)
			f.close()
			gpu += bytes.size() - MaterialLibrary.MTEX_HEADER
		else:
			rel = "textures/%s_%s.%s" % [id, slot, "jpg" if slot == "albedo" else "png"]
			var err := img.save_jpg(dir().path_join(rel), 0.92) if slot == "albedo" else img.save_png(dir().path_join(rel))
			if err != OK:
				return {"ok": false, "error": "can't write the maps (%s)" % error_string(err)}
			# On the GPU as RGBA with mipmaps.
			gpu += img.get_width() * img.get_height() * 4 * 4 / 3
		out[slot] = rel
	var s: Dictionary = SITES[site]
	var tiling := float(info.get("tiling", 0.0))
	var entry := {
		"id": id, "name": str(info.get("name", asset)).strip_edges().left(60), "tags": _tags(info.get("tags", [])),
		"size": size, "tiling": snappedf(tiling, 0.01) if tiling > 0.0 else 1.0, "tiling_from": "size" if tiling > 0.0
		else "default", "swatch": _swatch(albedo), "maps": out, "format": "mtex" if astc else "png",
		"gpu_bytes": gpu,
		"source": {"site": site, "name": s["name"], "asset": asset, "title": str(info.get("name", asset)),
				"page": s["page"] % (str(info["listing"]) if site == "megascans" and str(info.get("listing", ""))
				!= "" else asset), "author": str(info.get("author", "")), "licence": s["licence"],
				"listing": str(info.get("listing", "")), "imported": Time.get_date_string_from_system()},
	}
	var f := FileAccess.open(dir().path_join(id + ".json"), FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "can't write %s" % dir()}
	f.store_string(JSON.stringify(entry, " "))
	f.close()
	return {"ok": true, "entry": entry}


static func _tags(tags: Variant) -> Array:
	var out: Array = []
	if tags is Array:
		for t: Variant in tags:
			var x := str(t).strip_edges().to_lower().left(24)
			if x != "" and not (x in out) and out.size() < 8:
				out.append(x)
	return out


## A map at size x size (the tiling is square), in this format.
static func _square(src: Image, size: int, format: Image.Format) -> Image:
	var img := src.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	if img.get_format() != format:
		img.convert(format)
	if img.get_width() != size or img.get_height() != size:
		img.resize(size, size, Image.INTERPOLATE_LANCZOS if img.get_width() > size else Image.INTERPOLATE_BILINEAR)
	return img


## A normal map (X in red, Y in green) as the shader reads it: X in RGB and Y in alpha, as the bundled maps' encoder
## lays it out (room_material.gdshaderinc samples .ga).
static func _normal_xy(img: Image) -> Image:
	var src := img.get_data()
	var n := img.get_width() * img.get_height()
	var d := PackedByteArray()
	d.resize(n * 4)
	for i in n:
		var x := src[i * 3]
		d[i * 4] = x
		d[i * 4 + 1] = x
		d[i * 4 + 2] = x
		d[i * 4 + 3] = src[i * 3 + 1]
	return Image.create_from_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, d)


## The packed map: R ambient occlusion (1: it is in the colour), G roughness (0.8 without one), B metalness (0).
static func _orm(size: int, rough: Image, metal: Image) -> Image:
	var r := rough.get_data() if rough != null else PackedByteArray()
	var m := metal.get_data() if metal != null else PackedByteArray()
	var d := PackedByteArray()
	d.resize(size * size * 3)
	for i in size * size:
		d[i * 3] = 255
		d[i * 3 + 1] = r[i] if not r.is_empty() else 204
		d[i * 3 + 2] = m[i] if not m.is_empty() else 0
	return Image.create_from_data(size, size, false, Image.FORMAT_RGB8, d)


## The base colour's mean, in linear light, as "#rrggbb" (the library's swatch).
static func _swatch(albedo: Image) -> String:
	var s := albedo.duplicate() as Image
	s.resize(32, 32, Image.INTERPOLATE_BILINEAR)
	var d := s.get_data()
	var sum := Vector3.ZERO
	for i in range(0, d.size(), 3):
		sum += Vector3(pow(d[i] / 255.0, 2.2), pow(d[i + 1] / 255.0, 2.2), pow(d[i + 2] / 255.0, 2.2))
	sum /= float(d.size() / 3)
	return "#%02x%02x%02x" % [roundi(pow(sum.x, 1.0 / 2.2) * 255.0), roundi(pow(sum.y, 1.0 / 2.2) * 255.0),
			roundi(pow(sum.z, 1.0 / 2.2) * 255.0)]


## A map as a .mtex file (MaterialLibrary's header and the ASTC 8 x 8 blocks with every mip level), or empty when the
## engine can't compress.
static func _mtex(img: Image, slot: String) -> PackedByteArray:
	var c := img.duplicate() as Image
	if c.get_format() != Image.FORMAT_RGBA8:
		c.convert(Image.FORMAT_RGBA8)
	c.generate_mipmaps()
	var source := Image.COMPRESS_SOURCE_SRGB if slot == "albedo" else Image.COMPRESS_SOURCE_GENERIC
	if c.compress(Image.COMPRESS_ASTC, source, Image.ASTC_FORMAT_8x8) != OK or c.get_format() != Image.FORMAT_ASTC_8x8:
		return PackedByteArray()
	var data := c.get_data()
	var out := PackedByteArray()
	out.append_array(MaterialLibrary.MTEX_MAGIC.to_ascii_buffer())
	out.resize(MaterialLibrary.MTEX_HEADER)
	out.encode_u32(4, 1)
	out.encode_u32(8, 8 | (8 << 16))
	out.encode_u32(12, c.get_width())
	out.encode_u32(16, c.get_height())
	out.encode_u32(20, c.get_mipmap_count() + 1)
	out.encode_u32(24, {"albedo": MaterialLibrary.FLAG_SRGB, "normal": MaterialLibrary.FLAG_NORMAL}.get(slot, 0))
	out.encode_u32(28, data.size())
	out.append_array(data)
	return out
