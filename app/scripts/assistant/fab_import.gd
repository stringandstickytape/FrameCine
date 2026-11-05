extends RefCounted

## A scanned asset as downloaded from the Fab store (a .zip: an .fbx or .glb, its texture maps as .jpg/.png, and the
## asset's .json) made a user object (object_library.gd import_glb). The viewer downloads it themselves, on the
## headset, under their own Fab licence: nothing of it is in the repository or the release (docs/assistant.md,
## "Objects from Fab"). Their licence lets them use it, not hand it on, so it stays in user://objects like any import.
##
## From the .json: the name, the tags, Small3dAsset (it goes on a table) and the asset's id (kept as the manifest's
## `fab`, so the same download isn't added twice). The material is made here, not read from the .fbx (which names
## the 4K maps of the full asset, not the ones in the zip): the colour map with the ambient occlusion multiplied in
## (rooms draw objects unlit, gltf_room.gd, so the crevices keep their shade), the normal map, and roughness (or
## gloss turned round); an opacity map becomes the colour's alpha, cut out. Maps over MAX_TEXTURE are made smaller.
##
##   is_fab_zip(path) -> bool             read_zip(path) -> {id, name, tags, mount, model, model_name, maps} or {error}
##   import_zip(path) -> import_glb's result (+ "already" when that asset is in the library)
##   downloads() -> [{path, id, name}]   the Fab zips in the Downloads folder not yet in the library

const ObjectLibrary := preload("res://scripts/assistant/object_library.gd")

## The largest side kept for a map (the Frame's memory; Fab's Medium is 2K, High 4K).
const MAX_TEXTURE := 2048
## A zip bigger than this isn't read (a Raw download is hundreds of MB, far over the object limits anyway).
const MAX_ZIP_BYTES := 200 * 1024 * 1024
## Map names in the files, by the slot they fill (Fab writes <name>_<id>_<res>_<Map>.jpg).
const MAP_NAMES := {
	"albedo": ["basecolor", "albedo", "diffuse"],
	"normal": ["normal"],
	"roughness": ["roughness"],
	"gloss": ["gloss"],
	"ao": ["ao", "occlusion"],
	"opacity": ["opacity"],
}


static func is_fab_zip(path: String) -> bool:
	if path.get_extension().to_lower() != "zip":
		return false
	var z := ZIPReader.new()
	if z.open(path) != OK:
		return false
	var has_json := false
	var has_model := false
	for f in z.get_files():
		var ext := f.get_extension().to_lower()
		has_json = has_json or (ext == "json" and not f.contains("/"))
		has_model = has_model or ext in ["fbx", "glb"]
	z.close()
	return has_json and has_model


## The asset in a Fab zip: its .json read, its model's bytes, its maps' images (slot -> Image).
static func read_zip(path: String) -> Dictionary:
	if FileAccess.file_exists(path) and FileAccess.get_size(path) > MAX_ZIP_BYTES:
		return {"error": "the zip is over %d MB: download the Low or Medium quality" % (MAX_ZIP_BYTES >> 20)}
	var z := ZIPReader.new()
	if z.open(path) != OK:
		return {"error": "can't open %s" % path.get_file()}
	var info := {}
	var models: Array[String] = []
	var maps := {}
	for f in z.get_files():
		var ext := f.get_extension().to_lower()
		if ext == "json" and info.is_empty():
			var j: Variant = JSON.parse_string(z.read_file(f).get_string_from_utf8())
			if j is Dictionary and (j as Dictionary).has("id"):
				info = j
		elif ext in ["fbx", "glb"]:
			models.append(f)
		elif ext in ["jpg", "jpeg", "png"]:
			var slot := _slot_of(f)
			if slot != "" and not maps.has(slot):
				maps[slot] = f
	if info.is_empty() or models.is_empty():
		z.close()
		return {"error": "%s isn't a Fab download (no asset .json and model)" % path.get_file()}
	# One model: a .glb before an .fbx, then the first by name (a Low or Medium zip has one).
	models.sort_custom(func(a: String, b: String) -> bool:
		var ga := a.get_extension().to_lower() == "glb"
		var gb := b.get_extension().to_lower() == "glb"
		return ga and not gb if ga != gb else a < b)
	var out := {"id": str(info["id"]), "name": str(info.get("name", info["id"])), "tags": _tags(info),
			"mount": "table" if _meta(info, "small3dasset") == "true" else "floor",
			"model_name": models[0].get_file(), "model": z.read_file(models[0]), "maps": {}}
	for slot: String in maps:
		var img := _image(z.read_file(maps[slot]), maps[slot])
		if img != null:
			out["maps"][slot] = img
	z.close()
	return out


## Adds the asset in a Fab zip to the library. Safe on a worker thread.
static func import_zip(path: String) -> Dictionary:
	var a := read_zip(path)
	if a.has("error"):
		return {"ok": false, "error": a["error"]}
	for m: Dictionary in ObjectLibrary.list("", "user"):
		if str(m.get("fab", "")) == a["id"]:
			return {"ok": true, "already": true, "manifest": m, "warnings": []}
	var node := _load_model(a["model"], a["model_name"])
	if node == null:
		return {"ok": false, "error": "%s doesn't read" % a["model_name"]}
	_dress(node, a["maps"], ObjectLibrary.clean_name(a["name"]))
	var bytes := _to_glb(node)
	node.free()
	if bytes.is_empty():
		return {"ok": false, "error": "the model could not be written as a .glb"}
	return ObjectLibrary.import_glb(bytes, a["name"], a["tags"], a["mount"], {"fab": a["id"]})


## The Fab zips in the Downloads folder whose asset isn't in the library yet.
static func downloads() -> Array:
	var dir := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	var out: Array = []
	if dir == "" or not DirAccess.dir_exists_absolute(dir):
		return out
	var have := {}
	for m: Dictionary in ObjectLibrary.list("", "user"):
		if m.has("fab"):
			have[str(m["fab"])] = true
	for f in DirAccess.get_files_at(dir):
		var path := dir.path_join(f)
		if not is_fab_zip(path):
			continue
		var id := _zip_id(path)
		if id != "" and not have.has(id):
			out.append({"path": path, "id": id, "name": _zip_name(path)})
	return out


# --- Reading --------------------------------------------------------------------------------------------------------

static func _slot_of(file: String) -> String:
	var base := file.get_file().get_basename().to_lower()
	var last := base.rsplit("_", true, 1)[-1]
	for slot: String in MAP_NAMES:
		if last in MAP_NAMES[slot]:
			return slot
	return ""


static func _meta(info: Dictionary, key: String) -> String:
	for e: Variant in info.get("meta", []):
		if e is Dictionary and str(e.get("key", "")) == key:
			return str(e.get("value", "")).to_lower()
	return ""


static func _tags(info: Dictionary) -> Array:
	var out: Array = []
	for t: Variant in info.get("tags", []):
		var s := str(t).strip_edges().to_lower()
		if s != "" and not (s in out):
			out.append(s)
	return out.slice(0, ObjectLibrary.TAGS_MAX)


static func _zip_json(path: String) -> Dictionary:
	var z := ZIPReader.new()
	if z.open(path) != OK:
		return {}
	var out := {}
	for f in z.get_files():
		if f.get_extension().to_lower() == "json":
			var j: Variant = JSON.parse_string(z.read_file(f).get_string_from_utf8())
			if j is Dictionary and (j as Dictionary).has("id"):
				out = j
				break
	z.close()
	return out


static func _zip_id(path: String) -> String:
	return str(_zip_json(path).get("id", ""))


static func _zip_name(path: String) -> String:
	return str(_zip_json(path).get("name", path.get_file().get_basename()))


static func _image(bytes: PackedByteArray, file: String) -> Image:
	var img := Image.new()
	var ext := file.get_extension().to_lower()
	var err := img.load_png_from_buffer(bytes) if ext == "png" else img.load_jpg_from_buffer(bytes)
	if err != OK or img.is_empty():
		return null
	if img.is_compressed():
		img.decompress()
	var side := maxi(img.get_width(), img.get_height())
	if side > MAX_TEXTURE:
		var k := float(MAX_TEXTURE) / side
		img.resize(maxi(1, roundi(img.get_width() * k)), maxi(1, roundi(img.get_height() * k)),
				Image.INTERPOLATE_LANCZOS)
	return img


## The model as nodes. The .fbx names texture files that aren't in the zip: its loader's complaints are kept out of
## the log (the material is made here instead).
static func _load_model(bytes: PackedByteArray, file: String) -> Node3D:
	var fbx := file.get_extension().to_lower() == "fbx"
	if fbx and not ClassDB.class_exists("FBXDocument"):
		return null
	var doc: GLTFDocument = ClassDB.instantiate("FBXDocument") if fbx else GLTFDocument.new()
	var state: GLTFState = ClassDB.instantiate("FBXState") if fbx else GLTFState.new()
	var was := Engine.print_error_messages
	Engine.print_error_messages = false
	var err := doc.append_from_buffer(bytes, "", state)
	Engine.print_error_messages = was
	if err != OK:
		return null
	return doc.generate_scene(state) as Node3D


## The nodes as a .glb with the maps as JPEG (as PNG a 2K download's three maps near the 20 MB object limit).
static func _to_glb(node: Node3D) -> PackedByteArray:
	var doc := GLTFDocument.new()
	doc.image_format = "JPEG"
	doc.lossy_quality = 0.9
	var state := GLTFState.new()
	if doc.append_from_scene(node, state) != OK:
		return PackedByteArray()
	return doc.generate_buffer(state)


# --- The material ---------------------------------------------------------------------------------------------------

## Each mesh given the material made from the maps (one for all), and named after the asset ("Half Ham", "Half Ham
## 2"): its part name in a room.
static func _dress(root: Node3D, maps: Dictionary, name: String) -> void:
	var mat := material(maps)
	# Not the asset's name: glTF node names are made unique, and the mesh is to have it.
	root.name = "Model"
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	for i in meshes.size():
		var mi := meshes[i] as MeshInstance3D
		mi.name = name if i == 0 else "%s %d" % [name, i + 1]
		if mi.mesh == null or not (mi.mesh is ArrayMesh):
			continue
		for s in mi.mesh.get_surface_count():
			(mi.mesh as ArrayMesh).surface_set_material(s, mat)
		for s in mi.get_surface_override_material_count():
			mi.set_surface_override_material(s, null)


static func material(maps: Dictionary) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.metallic = 0.0
	m.roughness = 1.0
	var albedo: Image = maps.get("albedo")
	if albedo != null:
		albedo = albedo.duplicate()
		if maps.get("ao") != null:
			_multiply(albedo, maps["ao"])
		if maps.get("opacity") != null:
			_alpha(albedo, maps["opacity"])
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			m.alpha_scissor_threshold = 0.5
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.albedo_texture = ImageTexture.create_from_image(albedo)
	if maps.get("normal") != null:
		m.normal_enabled = true
		m.normal_texture = ImageTexture.create_from_image(maps["normal"])
	var rough: Image = maps.get("roughness")
	if rough == null and maps.get("gloss") != null:
		rough = (maps["gloss"] as Image).duplicate()
		_invert(rough)
	if rough != null:
		m.roughness_texture = ImageTexture.create_from_image(rough)
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	return m


## img *= ao (its red), per pixel, the ao map scaled to img first. On the bytes: a 2K map is 4 million pixels.
static func _multiply(img: Image, ao: Image) -> void:
	var a := _channel(_sized(ao, img))
	var rgba := img.detect_alpha() != Image.ALPHA_NONE
	img.convert(Image.FORMAT_RGBA8 if rgba else Image.FORMAT_RGB8)
	var d := img.get_data()
	var step := 4 if rgba else 3
	for i in a.size():
		var k := a[i]
		var o := i * step
		d[o] = d[o] * k / 255
		d[o + 1] = d[o + 1] * k / 255
		d[o + 2] = d[o + 2] * k / 255
	img.set_data(img.get_width(), img.get_height(), false, img.get_format(), d)


static func _alpha(img: Image, opacity: Image) -> void:
	var a := _channel(_sized(opacity, img))
	img.convert(Image.FORMAT_RGBA8)
	var d := img.get_data()
	for i in a.size():
		d[i * 4 + 3] = a[i]
	img.set_data(img.get_width(), img.get_height(), false, img.get_format(), d)


static func _invert(img: Image) -> void:
	img.convert(Image.FORMAT_RGB8)
	var d := img.get_data()
	for i in d.size():
		d[i] = 255 - d[i]
	img.set_data(img.get_width(), img.get_height(), false, img.get_format(), d)


## A map's first channel, one byte a pixel.
static func _channel(img: Image) -> PackedByteArray:
	var g := img.duplicate() as Image
	g.convert(Image.FORMAT_L8)
	return g.get_data()


static func _sized(src: Image, like: Image) -> Image:
	if src.get_size() == like.get_size():
		return src
	var out := src.duplicate() as Image
	out.resize(like.get_width(), like.get_height(), Image.INTERPOLATE_BILINEAR)
	return out
