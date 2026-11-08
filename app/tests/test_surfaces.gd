extends SceneTree

## Surfaces (scripts/env/surface_store.gd, surface_import.gd, material_library.gd's user materials) and apply to a
## part (scripts/assistant/part_apply.gd, ui/object_placer.gd's apply mode) in the real main scene, against a fake
## transport that serves answers written here in the three sources' shapes, with made-up names and ids; every
## picture and zip is made here. Nothing reaches the network.
##
## The three sources' search and paging; Poly Haven's list fetched once and kept (a day), its User-Agent and credit,
## no key in any request; ambientCG's pages kept a day; Megascans through the Fab store, refused with eula until the
## licence is accepted; a second between a source's pages; the back-off per source; each import into a user material
## that MaterialLibrary lists and makes (AO in the colour, normal X/Y in RGB/alpha, height dropped), its tiling from
## the real size; material_status; apply to a room part and to an object's part, kept in the room, Put back;
## pointed_part; the apply mode's preview, stick and trigger.
## godot --headless --xr-mode off --path app --script res://tests/test_surfaces.gd

const SurfaceStore := preload("res://scripts/env/surface_store.gd")
const SurfaceImport := preload("res://scripts/env/surface_import.gd")
const FabStore := preload("res://scripts/assistant/fab_store.gd")
const MaterialLibrary := preload("res://scripts/env/material_library.gd")
const PartApply := preload("res://scripts/assistant/part_apply.gd")
const ObjectCommands := preload("res://scripts/assistant/object_commands.gd")
const AssistantRoom := preload("res://scripts/assistant/assistant_room.gd")
const ObjectLibrary := preload("res://scripts/assistant/object_library.gd")
const RoomModel := preload("res://scripts/assistant/room_model.gd")
const RoomEditor := preload("res://scripts/assistant/room_editor.gd")
const DevCommands := preload("res://scripts/dev/dev_commands.gd")
const CommandHost := preload("res://scripts/dev/command_host.gd")
const AssistantCommands := preload("res://scripts/assistant/assistant_commands.gd")

const ROOT := "user://test_surfaces"
const CDN := "https://cdn.test.invalid/"
const THUMBS := "https://thumbs.test.invalid/"
const MS_UID := "00000000-0000-4000-8000-00000000d001"
const MS_FILE := "00000000-0000-4000-8000-0000000fd001"
const MS_ASSET := "tstms001"

var _failures := 0
var _checks := 0
var main: Node
var store: Node
var fab: Node
var fake: Fake
var commands: AssistantCommands


## Stands in for fab_http.gd (as tests/test_fab_store.gd's): answers by URL a frame later, files written as asked;
## the log keeps each request's URL, headers and start time.
class Fake extends RefCounted:
	var tree: SceneTree
	var routes := {}
	var log: Array = []

	func fetch(url: String, headers: PackedStringArray, file := "") -> Dictionary:
		var e := {"url": url, "headers": headers, "file": file, "start": Time.get_ticks_msec()}
		log.append(e)
		await tree.process_frame
		var r: Variant = routes.get(url, {"code": 404, "body": "{}"})
		var body: Variant = r.get("body", "")
		var bytes: PackedByteArray = body if body is PackedByteArray else str(body).to_utf8_buffer()
		var out := {"code": int(r.get("code", 200)), "headers": r.get("headers", {}), "body": PackedByteArray(),
				"error": ""}
		if file == "":
			out["body"] = bytes
		else:
			var f := FileAccess.open(file, FileAccess.WRITE)
			f.store_buffer(bytes)
			f.close()
		return out

	func progress() -> Array:
		return [0, -1]

	func cancel() -> void:
		pass

	func count(prefix: String) -> int:
		return log.filter(func(e: Dictionary) -> bool: return str(e["url"]).begins_with(prefix)).size()


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.settings.read_only = true
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _run() -> void:
	await _frames(5)
	CommandHost.ensure(self)
	await _frames(2)
	_wipe(ROOT)
	MaterialLibrary.user_dir = ROOT + "/materials"
	MaterialLibrary.forget_user()
	fake = Fake.new()
	fake.tree = self
	fab = FabStore.ensure(self)
	store = SurfaceStore.ensure(self)
	await _frames(2)
	fab.transport = fake
	fab.root = ROOT + "/fab"
	fab.withdraw_eula()
	store.transport = fake
	store.root = ROOT + "/store"
	store.fab = fab
	_routes()
	commands = AssistantCommands.new()
	commands.allow_room = func() -> bool: return true

	_test_parsing()
	await _test_search()
	await _test_spacing_and_backoff()
	await _test_imports()
	await _test_megascans()
	await _test_status()
	await _test_apply()
	await _test_apply_mode()
	await _test_paint_by_material()

	fab.withdraw_eula()
	_forget_rooms(["acg_testbricks000", "Test Box", "ms_" + MS_ASSET, "Test Sofa"])
	MaterialLibrary.user_dir = MaterialLibrary.USER_DIR
	MaterialLibrary.forget_user()
	_wipe(ROOT)
	main.queue_free()
	await _frames(2)
	print("test_surfaces: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


# --- Fixtures, in the sources' shapes (made-up names) ----------------------------------------------------------------

## A JPEG of one colour with a little noise (seeded), or a PNG.
static func _picture(size: int, colour: Color, png := false, seed_value := 1) -> PackedByteArray:
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for y in size:
		for x in size:
			var n := rng.randf_range(-0.03, 0.03)
			img.set_pixel(x, y, Color(clampf(colour.r + n, 0, 1), clampf(colour.g + n, 0, 1), clampf(colour.b + n, 0, 1)))
	return img.save_png_to_buffer() if png else img.save_jpg_to_buffer(0.95)


static func _zip(files: Dictionary) -> PackedByteArray:
	var path := ROOT + "/tmp_zip.zip"
	DirAccess.make_dir_recursive_absolute(ROOT)
	var z := ZIPPacker.new()
	z.open(path)
	for name: String in files:
		z.start_file(name)
		var v: Variant = files[name]
		z.write_file(v if v is PackedByteArray else str(v).to_utf8_buffer())
		z.close_file()
	z.close()
	var out := FileAccess.get_file_as_bytes(path)
	DirAccess.remove_absolute(path)
	return out


func _ph_index() -> Dictionary:
	var d := {}
	for i in 30:
		d["test_brick_wall_%02d" % i] = {"type": 1, "name": "Test Brick Wall %02d" % i, "tags": ["brick", "wall"],
				"categories": ["brick", "outdoor"], "dimensions": [2500, 2500], "authors": {"Test Author": "All"},
				"download_count": 100 - i, "thumbnail_url": THUMBS + "ph_%02d.png" % i}
	d["test_oak_floor"] = {"type": 1, "name": "Test Oak Floor", "tags": ["wood", "floor"], "categories": ["wood"],
			"dimensions": [3000, 3000], "authors": {"Test Author": "All"}, "download_count": 5,
			"thumbnail_url": THUMBS + "ph_oak.png"}
	return d


func _acg_asset(i: int) -> Dictionary:
	var id := "TestBricks%03d" % i
	return {"assetId": id, "displayName": "Test Bricks %03d" % i, "dataType": "Material", "tags": ["brick", "red"],
			"dimensionX": 200, "dimensionY": 200, "previewImage": {"256-PNG": THUMBS + id + ".png"},
			"downloadFolders": {"default": {"title": "Default", "downloadFiletypeCategories": {"zip": {"downloads": [
				{"attribute": "2K-JPG", "downloadLink": CDN + id + "_2K.zip", "size": 9000, "filetype": "zip"},
				{"attribute": "1K-JPG", "downloadLink": CDN + id + "_1K.zip", "size": 4000, "filetype": "zip"}]}}}}}


func _routes() -> void:
	var r := fake.routes
	r[SurfaceStore.PH_INDEX] = {"body": JSON.stringify(_ph_index())}
	var files := {}
	for m: String in ["Diffuse", "nor_gl", "Rough", "AO", "Displacement", "nor_dx"]:
		files[m] = {"1k": {"jpg": {"url": CDN + "ph_" + m + "_1k.jpg", "size": 1000}},
				"2k": {"jpg": {"url": CDN + "ph_" + m + "_2k.jpg", "size": 4000}}}
	r[SurfaceStore.PH_FILES % "test_brick_wall_00"] = {"body": JSON.stringify(files)}
	r[CDN + "ph_Diffuse_1k.jpg"] = {"body": _picture(64, Color(1, 1, 1))}
	r[CDN + "ph_nor_gl_1k.jpg"] = {"body": _picture(64, Color(0.5, 0.75, 1.0))}
	r[CDN + "ph_Rough_1k.jpg"] = {"body": _picture(64, Color(0.6, 0.6, 0.6))}
	# Half: the colour comes out half as bright (the AO multiplied in).
	r[CDN + "ph_AO_1k.jpg"] = {"body": _picture(64, Color(0.5, 0.5, 0.5))}
	var page1 := []
	for i in 24:
		page1.append(_acg_asset(i))
	r[SurfaceStore.ACG_SEARCH % ["brick", 24, 0]] = {"body": JSON.stringify({"foundAssets": page1,
			"numberOfResults": 26})}
	r[SurfaceStore.ACG_SEARCH % ["brick", 24, 24]] = {"body": JSON.stringify({"foundAssets": [_acg_asset(24),
			_acg_asset(25)], "numberOfResults": 26})}
	r[SurfaceStore.ACG_SEARCH % ["odd", 24, 0]] = {"body": "{\"assets\": []}"}
	r[SurfaceStore.ACG_SEARCH % ["busy", 24, 0]] = {"code": 429, "headers": {"retry-after": "2"}, "body": "{}"}
	var p := "TestBricks000_1K-JPG"
	r[CDN + "TestBricks000_1K.zip"] = {"body": _zip({p + "_Color.jpg": _picture(64, Color(0.7, 0.3, 0.2)),
			p + "_NormalGL.jpg": _picture(64, Color(0.5, 0.5, 1.0)), p + "_NormalDX.jpg": _picture(64, Color(0.5, 0.5, 1)),
			p + "_Roughness.jpg": _picture(64, Color(0.8, 0.8, 0.8)), p + "_Displacement.jpg": _picture(64, Color.GRAY),
			p + ".mtlx": "<materialx/>"})}
	# Megascans, through Fab.
	r[FabStore.search_url("brick", "", FabStore.MATERIAL_TYPE)] = {"body": JSON.stringify({"cursors": {"next": null},
			"results": [{"uid": MS_UID, "title": "Test Brick Surface", "listingType": "material",
				"category": {"name": "Brick"}, "tags": [{"name": "brick"}],
				"assetFormats": [{"assetFormatType": {"code": "texture-set"}}, {"assetFormatType": {"code": "gltf"}}],
				"thumbnails": []}]})}
	r[FabStore.FILES % MS_UID] = {"body": JSON.stringify([{"assetFormatType": {"code": "texture-set"}, "files": [
			{"uid": "00000000-0000-4000-8000-0000000fd008", "name": "test_brick_surface_%s_8k.zip" % MS_ASSET,
					"fileSize": 9000000},
			{"uid": MS_FILE, "name": "test_brick_surface_%s_1k.zip" % MS_ASSET, "fileSize": 5000}]},
			{"assetFormatType": {"code": "gltf"}, "files": [{"uid": "00000000-0000-4000-8000-0000000fd009",
					"name": "test_brick_surface_%s_1k_ue_low.zip" % MS_ASSET, "fileSize": 2000}]}])}
	r[FabStore.LINK % [MS_UID, "texture-set", MS_FILE]] = {"body": JSON.stringify({"downloadInfo": [
			{"downloadUrl": CDN + "ms.zip"}]})}
	var q := "Test_Brick_Surface_%s_1K_" % MS_ASSET
	r[CDN + "ms.zip"] = {"body": _zip({q + "BaseColor.jpg": _picture(64, Color(0.6, 0.4, 0.3)),
			q + "Normal.jpg": _picture(64, Color(0.5, 0.5, 1.0)), q + "Gloss.jpg": _picture(64, Color(0.2, 0.2, 0.2)),
			q + "Displacement.jpg": _picture(64, Color.GRAY), q + "Cavity.jpg": _picture(64, Color.WHITE),
			MS_ASSET + ".json": JSON.stringify({"id": MS_ASSET, "name": "Test Brick Surface",
					"tags": ["surface", "brick"], "meta": [{"key": "scanArea", "name": "Scan Area", "value": "2x2 m"}],
					"semanticTags": {"maxSize": 2, "name": "Test Brick Surface"}})})}
	for i in 30:
		r[THUMBS + "ph_%02d.png" % i] = {"body": _picture(16, Color(0.6, 0.2, 0.2), true)}


# --- The rules -----------------------------------------------------------------------------------------------------

func _test_parsing() -> void:
	var ix := SurfaceStore.parse_polyhaven_index(_ph_index())
	_check("Poly Haven's list: each texture with its real size in metres (%d)" % ix.size(), ix.size() == 31
			and ix.any(func(e: Dictionary) -> bool: return e["id"] == "test_oak_floor" and is_equal_approx(float(
			e["tiling"]), 3.0)))
	_check("an odd entry is left out", SurfaceStore.parse_polyhaven_index({"Bad Id!": {}, "ok_one": {"name": "x"}})
			.size() == 1)
	var a := SurfaceStore.parse_ambientcg_asset(_acg_asset(3))
	_check("ambientCG: the 1K JPEG zip, its size, the thumbnail, 2 m from 200 cm (%s)" % [a], a["zip"] == CDN
			+ "TestBricks003_1K.zip" and a["thumb"] == THUMBS + "TestBricks003.png" and is_equal_approx(float(
			a["tiling"]), 2.0) and a["importable"])
	_check("ambientCG: an answer without foundAssets is an error, not a crash",
			SurfaceStore.parse_ambientcg({"x": 1}, 0).has("error"))
	_check("Megascans' size from the scan area", is_equal_approx(SurfaceImport.megascans_size({"meta": [{"key":
			"scanArea", "value": "2x2 m"}]}), 2.0) and is_equal_approx(SurfaceImport.megascans_size({"meta": [{"key":
			"scanArea", "value": "50x50 cm"}]}), 0.5) and SurfaceImport.megascans_size({}) == 0.0)
	var pick := FabStore.choose_file(JSON.parse_string(str(fake.routes[FabStore.FILES % MS_UID]["body"])),
			FabStore.MATERIAL_TYPE)
	_check("Fab: the texture set's 1K zip, not the 8K nor the glTF (%s)" % [pick], pick.get("uid") == MS_FILE
			and pick.get("format") == "texture-set")
	_check("Fab's material search: listing type material, Megascans, free", FabStore.search_url("a", "",
			FabStore.MATERIAL_TYPE).contains("listing_types=material") and FabStore.search_url("a", "",
			FabStore.MATERIAL_TYPE).contains("is_free=1") and FabStore.search_url("a").contains("listing_types=3d-model"))
	_check("ids: the source's prefix and the asset, lower case", SurfaceImport.id_for("ambientcg", "Bricks076")
			== "acg_bricks076" and SurfaceImport.id_for("polyhaven", "brick_wall_001") == "ph_brick_wall_001")
	_check("this engine build can't compress to ASTC at run time (so 1K uncompressed)",
			not SurfaceImport.astc_available())


func _test_search() -> void:
	var r: Dictionary = await store.search("brick")
	_check("one search over three sources (%s)" % [r.get("errors")], r.get("ok") == true
			and (r["results"] as Array).any(func(e: Dictionary) -> bool: return e["source"] == "polyhaven")
			and (r["results"] as Array).any(func(e: Dictionary) -> bool: return e["source"] == "ambientcg"))
	_check("Megascans: refused with eula until the licence is accepted (the others still answer)",
			str(r["errors"].get("megascans", {}).get("error", "")) == "eula" and fake.count("https://www.fab.com") == 0)
	_check("the credit beside the results: Powered by Poly Haven (%s)" % [r["credits"]],
			"Powered by Poly Haven" in r["credits"])
	var ph: Array = r["results"].filter(func(e: Dictionary) -> bool: return e["source"] == "polyhaven")
	_check("Poly Haven: a page of 24, searched here, the name's words first, then the most downloaded (%d)" % ph.size(),
			ph.size() == 24 and ph[0]["id"] == "test_brick_wall_00" and is_equal_approx(float(ph[0]["tiling"]), 2.5))
	_check("Poly Haven's whole list was one request", fake.count(SurfaceStore.PH_INDEX) == 1
			and fake.count(SurfaceStore.PH_API) == 1)
	var ua_ok := true
	for e: Dictionary in fake.log:
		var h := "\n".join(e["headers"])
		ua_ok = ua_ok and h.contains("User-Agent: FrameVRVideo/") and h.contains("github.com")
	_check("every request names the app in its User-Agent", ua_ok and not fake.log.is_empty())
	_check("no key, account or token in any request", fake.log.all(func(e: Dictionary) -> bool:
		var u := str(e["url"]).to_lower()
		return not u.contains("key=") and not u.contains("token") and not "\n".join(e["headers"]).to_lower().contains(
				"authorization")))
	_check("the list is kept on disk", FileAccess.file_exists(ROOT + "/store/polyhaven_textures.json"))
	var next: Dictionary = JSON.parse_string(str(r["next"]))
	_check("the next page's cursor for each source with more (%s)" % [next], str(next.get("polyhaven", "")) == "24"
			and str(next.get("ambientcg", "")) == "24" and not next.has("megascans"))
	var r2: Dictionary = await store.search("brick", "", str(r["next"]))
	var ph2: Array = r2["results"].filter(func(e: Dictionary) -> bool: return e["source"] == "polyhaven")
	var acg2: Array = r2["results"].filter(func(e: Dictionary) -> bool: return e["source"] == "ambientcg")
	_check("the next page: the rest of Poly Haven's 30 and ambientCG's last 2 (%d, %d)" % [ph2.size(), acg2.size()],
			ph2.size() == 6 and acg2.size() == 2 and str(r2["next"]) == "")
	_check("Poly Haven's list not asked again within the day", fake.count(SurfaceStore.PH_INDEX) == 1)
	var before := fake.count("https://ambientcg.com")
	await store.search("brick", "ambientcg")
	_check("ambientCG's page kept a day: not asked again", fake.count("https://ambientcg.com") == before)
	store.index_ttl = -1
	store._index_loaded = false
	await store.search("oak", "polyhaven")
	_check("a day on: the list is asked again", fake.count(SurfaceStore.PH_INDEX) == 2)
	store.index_ttl = SurfaceStore.INDEX_TTL
	var odd: Dictionary = await store.search("odd", "ambientcg")
	_check("ambientCG's answer not as expected: an error (shape), no crash", odd.get("ok") == false
			and odd.get("error") == "shape")
	var img: Image = await store.thumbnail({"source": "polyhaven", "thumb": THUMBS + "ph_00.png"})
	_check("a thumbnail, fetched and kept", img != null and DirAccess.get_files_at(ROOT + "/store/thumbs").size() == 1)
	var n := fake.log.size()
	await store.thumbnail({"source": "polyhaven", "thumb": THUMBS + "ph_00.png"})
	_check("a kept thumbnail is not fetched again", fake.log.size() == n)
	var c: Dictionary = await commands.run("material_search", {"query": "oak", "source": "polyhaven"})
	_check("material_search (assistant): results with source and id, credits (%s)" % [c.get("error", "")],
			c.get("ok") == true and c["result"]["results"][0]["id"] == "test_oak_floor"
			and "Powered by Poly Haven" in c["result"]["credits"])


func _test_spacing_and_backoff() -> void:
	store.clear_cache()
	var start := fake.log.size()
	await store.search("brick", "ambientcg")
	await store.search("brick", "ambientcg", JSON.stringify({"ambientcg": "24"}))
	var times: Array = fake.log.slice(start).map(func(e: Dictionary) -> int: return int(e["start"]))
	_check("a second between one source's pages (%s)" % [times], times.size() == 2
			and int(times[1]) - int(times[0]) >= 950)
	var r: Dictionary = await store.search("busy", "ambientcg")
	_check("429: backoff (%s)" % [r.get("error")], r.get("error") == "backoff" and int(r.get("wait", 0)) >= 1)
	var n := fake.log.size()
	r = await store.search("brick", "ambientcg", JSON.stringify({"ambientcg": "48"}))
	_check("while it lasts nothing is asked of that source", r.get("error") == "backoff" and fake.log.size() == n)
	r = await store.search("oak", "polyhaven")
	_check("the other sources still answer", r.get("ok") == true)
	var s: Dictionary = store.status()
	_check("material_status says so (%s)" % [s["backoff_s"]], int(s["backoff_s"]["ambientcg"]) >= 1
			and int(s["backoff_s"]["polyhaven"]) == 0)
	await _until(func() -> bool: return store.backoff_left("ambientcg") <= 0.0, 4.0)
	fake.routes[SurfaceStore.ACG_SEARCH % ["broken", 24, 0]] = {"code": 503, "body": "{}"}
	r = await store.search("broken", "ambientcg")
	_check("5xx: backoff too, doubled for the second in a row (%s s)" % [r.get("wait")], r.get("error") == "backoff"
			and int(r.get("wait", 0)) == 4)
	await _until(func() -> bool: return store.backoff_left("ambientcg") <= 0.0, 6.0)


func _wait_job(seconds := 20.0) -> Dictionary:
	await _until(func() -> bool: return not store.job_active(), seconds)
	return store.job_state()


func _test_imports() -> void:
	await store.search("brick", "polyhaven")
	var r: Dictionary = store.start_import("polyhaven", "test_brick_wall_00")
	_check("Poly Haven import started (%s)" % [r], r.get("state") == "started")
	var job := await _wait_job()
	_check("done (%s)" % [job], job.get("state") == "done" and job["material"].get("id") == "ph_test_brick_wall_00")
	var urls: Array = fake.log.map(func(e: Dictionary) -> String: return str(e["url"]))
	_check("its file list from /files/<id>, then the 1K JPEGs; no height or DirectX normal",
			urls.has(SurfaceStore.PH_FILES % "test_brick_wall_00") and urls.has(CDN + "ph_Diffuse_1k.jpg")
			and not urls.has(CDN + "ph_Displacement_1k.jpg") and not urls.has(CDN + "ph_nor_dx_1k.jpg")
			and not urls.has(CDN + "ph_Diffuse_2k.jpg"))
	var id := "ph_test_brick_wall_00"
	_check("MaterialLibrary has it, beside the bundled ones", MaterialLibrary.has(id) and MaterialLibrary.has("velvet"))
	var e := MaterialLibrary.entry(id)
	_check("a user material: its source, no bigger than its maps (64 px here: 256), tiling 2.5 m from the real size "
			+ "(%s)" % [e.get("tiling")],
			bool(e.get("user", false)) and e["source"]["site"] == "polyhaven" and int(e["size"]) == 256
			and is_equal_approx(float(e["tiling"]), 2.5) and e["source"]["licence"] == "CC0 1.0")
	var listed: Array = MaterialLibrary.list().filter(func(m: Dictionary) -> bool: return m["id"] == id)
	_check("list(): with its source", listed.size() == 1 and listed[0]["source"] == "polyhaven" and listed[0]["user"])
	_check("the bundled ones say bundled", MaterialLibrary.list().any(func(m: Dictionary) -> bool:
		return m["id"] == "velvet" and m["source"] == "bundled"))
	var mat := MaterialLibrary.get_material(id, {"tiling": 1.5})
	_check("get_material() makes it", mat != null and MaterialLibrary.id_of(mat) == id)
	var tex := MaterialLibrary.textures(id)
	_check("its three maps load as textures", tex.size() == 3 and tex["albedo"] is ImageTexture)
	var albedo := _map(id, "albedo")
	_check("the colour has the AO multiplied in (white times half: %s)" % [albedo.get_pixel(8, 8) if albedo else null],
			albedo != null and absf(albedo.get_pixel(8, 8).r - 0.5) < 0.08)
	var normal := _map(id, "normal")
	var np := normal.get_pixel(8, 8) if normal != null else Color.BLACK
	_check("the normal map as the shader reads it: X in RGB, Y in alpha (%s)" % np, absf(np.g - 0.5) < 0.06
			and absf(np.a - 0.75) < 0.06)
	var orm := _map(id, "orm")
	_check("the packed map: AO 1 (in the colour), roughness kept, at half size", orm != null
			and absf(orm.get_pixel(4, 4).r - 1.0) < 0.02 and absf(orm.get_pixel(4, 4).g - 0.6) < 0.06
			and orm.get_width() == 128)
	var files := DirAccess.get_files_at(ROOT + "/materials/textures")
	_check("three maps beside it, no height (%s)" % [files], files.size() == 3 and FileAccess.file_exists(ROOT
			+ "/materials/" + id + ".json"))
	_check("its memory counted (%s)" % [MaterialLibrary.memory()], int(MaterialLibrary.memory()["user_bytes"]) > 0)
	r = store.start_import("polyhaven", "test_brick_wall_00")
	_check("in the library already: not downloaded again", r.get("state") == "already"
			and r["material"]["id"] == id)

	await store.search("brick", "ambientcg")
	r = store.start_import("ambientcg", "TestBricks000")
	job = await _wait_job()
	var aid := "acg_testbricks000"
	_check("ambientCG import: the 1K zip, a user material (%s)" % [job], job.get("state") == "done"
			and MaterialLibrary.has(aid) and fake.count(CDN + "TestBricks000_1K.zip") == 1
			and fake.count(CDN + "TestBricks000_2K.zip") == 0)
	e = MaterialLibrary.entry(aid)
	_check("its tiling from its size: 2 m", is_equal_approx(float(e["tiling"]), 2.0) and e["name"] == "Test Bricks 000")
	var rs: Dictionary = await store.search("brick", "ambientcg")
	_check("the search shows it in the library", rs["results"][0]["in_library"] == aid)
	var c: Dictionary = await commands.run("materials", {})
	_check("materials (assistant) includes the user ones, with their source", c.get("ok") == true
			and (c["result"] as Array).any(func(m: Dictionary) -> bool: return m["id"] == aid and m["source"] == "ambientcg"))


func _test_megascans() -> void:
	var a: Dictionary = await commands.run("material_import", {"source": "megascans", "id": MS_UID})
	_check("material_import (Megascans) before the licence: error eula (%s)" % [a], a.get("ok") == false
			and a.get("error") == "eula" and str(a.get("message", "")).contains("Your objects"))
	var r: Dictionary = await store.search("brick", "megascans")
	_check("material_search megascans alone: error eula", r.get("error") == "eula")
	fab.accept_eula()
	r = await store.search("brick", "megascans")
	_check("accepted: Megascans' surfaces through Fab (%s)" % [r.get("error", "")], r.get("ok") == true
			and r["results"][0]["source"] == "megascans" and r["results"][0]["id"] == MS_UID
			and r["results"][0]["importable"] and "Quixel Megascans, through Fab" in r["credits"])
	_check("Fab asked with the material listing type", fake.log.any(func(e: Dictionary) -> bool:
		return str(e["url"]).contains("listing_types=material")))
	a = await commands.run("material_import", {"source": "megascans", "id": MS_UID})
	_check("material_import started (%s)" % [a], a.get("ok") == true and a["result"]["state"] == "started")
	var job := await _wait_job(30.0)
	var mid := "ms_" + MS_ASSET
	_check("done: a user material from the texture set (%s)" % [job], job.get("state") == "done"
			and MaterialLibrary.has(mid) and job["source"] == "megascans")
	var e := MaterialLibrary.entry(mid)
	_check("tiling 2 m from the scan area; its listing kept; source megascans", is_equal_approx(float(e["tiling"]), 2.0)
			and e["source"]["listing"] == MS_UID and e["source"]["site"] == "megascans")
	var orm := _map(mid, "orm")
	_check("gloss turned round as roughness (0.2 -> 0.8: %.2f)" % (orm.get_pixel(4, 4).g if orm else -1.0),
			orm != null and absf(orm.get_pixel(4, 4).g - 0.8) < 0.06)
	r = await store.search("brick", "megascans")
	_check("the search shows it in the library", r["results"][0]["in_library"] == mid)
	_check("the zip went from the temporary folder", DirAccess.get_files_at(ROOT + "/fab/tmp").is_empty())


func _test_status() -> void:
	var s: Dictionary = await commands.run("material_status", {})
	var st: Dictionary = s.get("result", {})
	_check("material_status: the user materials, their memory, 1K uncompressed (%s)" % [st], s.get("ok") == true
			and int(st["user_materials"]) == 3 and int(st["gpu_bytes_if_all_loaded"]) > 0 and st["astc"] == false
			and str(st["resolution"]).begins_with("1K") and int(st["disk_bytes"]) > 0)


# --- Apply to a part -------------------------------------------------------------------------------------------------

## Points the pointer hand along a ray (world frame).
func _aim(from: Vector3, to: Vector3) -> void:
	var hand: Node3D = main.ui.pointer_hand
	hand.global_transform = Transform3D(Basis.looking_at((to - from).normalized(), Vector3.UP), from)


func _test_apply() -> void:
	main.set_environment("dim_room")
	await _frames(10)
	var eye: Vector3 = main.camera.global_position
	var env: Node3D = main.env
	var ahead := eye + (-env.global_basis.z) * 20.0
	_aim(eye, ahead)
	var p: Dictionary = PartApply.pointed(main)
	_check("pointed_part: the wall ahead, a room surface (%s)" % [p.get("part", "")], p.get("kind") == "room"
			and str(p.get("part", "")) != "")
	var wall := str(p.get("part", ""))
	var c: Dictionary = await commands.run("pointed_part", {})
	_check("pointed_part (assistant) says the same (%s)" % [c.get("result")], c.get("ok") == true
			and c["result"]["part"] == wall and c["result"]["kind"] == "room")
	var id := "acg_testbricks000"
	c = await commands.run("material_apply", {"part": wall, "material": id, "tiling": 1.5, "turn": 30.0})
	await _frames(5)
	_check("material_apply on the wall (%s)" % [c.get("error", "")], c.get("ok") == true)
	env = main.env
	var doc: Dictionary = env.get("doc") if env.get("doc") is Dictionary else {}
	var entry := _entry(doc, wall)
	_check("kept as the room's recolour with library_material, its tiling and turn (%s)" % [entry],
			env.get_script() == AssistantRoom and entry.get("material", {}).get("library_material") == id
			and is_equal_approx(float(entry["material"].get("tiling", 0)), 1.5)
			and is_equal_approx(float(entry["material"].get("turn", 0)), 30.0))
	var base: Node3D = RoomEditor._base(env)
	var g := base.find_children(wall, "GeometryInstance3D", true, false)[0] as GeometryInstance3D
	var m := AssistantRoom._shown_material(g) as ShaderMaterial
	_check("the wall shows it, the pattern turned", AssistantRoom.material_id_of(g) == id and m != null
			and absf(float(m.get_shader_parameter("uv_turn")) - deg_to_rad(30.0)) < 0.001)
	var kept := _kept_room_text(str(doc.get("name", "")))
	_check("in the kept room on disk", kept.contains(id) and kept.contains("\"%s\"" % wall))
	var undo: Variant = c.get("undo")
	_check("with an undo", undo is Callable)
	# An object's part.
	var r: Dictionary = await ObjectCommands.place(self, null, "box", {"name": "Test Box", "position": [0, 1, -1.5]})
	await _frames(5)
	_check("a box placed (%s)" % r.get("error", ""), r.get("ok") == true)
	c = await commands.run("material_apply", {"part": "Test Box/Box", "material": "ph_test_brick_wall_00"})
	await _frames(5)
	env = main.env
	doc = env.get("doc")
	_check("material_apply on an object's part: its part-level entry (%s)" % [c.get("error", "")], c.get("ok") == true
			and _entry(doc, "Test Box/Box").get("material", {}).get("library_material") == "ph_test_brick_wall_00")
	var parts: Dictionary = AssistantRoom.parts_of_placed(env.get_node("AssistantLayer/Test Box"))
	_check("the part shows it", AssistantRoom.material_id_of(parts["Box"]) == "ph_test_brick_wall_00")
	_aim(eye, (env.get_node("AssistantLayer/Test Box") as Node3D).global_position)
	p = PartApply.pointed(main)
	_check("pointed_part: the box's part (%s)" % [p.get("part")], p.get("part") == "Test Box/Box"
			and p.get("kind") == "object" and p.get("material") == "ph_test_brick_wall_00")
	# Put back.
	c = await commands.run("part_reset", {"part": wall})
	await _frames(5)
	env = main.env
	doc = env.get("doc")
	base = RoomEditor._base(env)
	g = base.find_children(wall, "GeometryInstance3D", true, false)[0] as GeometryInstance3D
	_check("part_reset: the wall as the room built it (%s)" % [c.get("error", "")], c.get("ok") == true
			and _entry(doc, wall).is_empty() and AssistantRoom.material_id_of(g) != id)
	c = await commands.run("part_reset", {"part": wall})
	_check("again: nothing to put back", c.get("ok") == false)
	c = await commands.run("part_reset", {"part": "Test Box/Box"})
	await _frames(5)
	_check("part_reset on the object's part", c.get("ok") == true and _entry(main.env.get("doc"), "Test Box/Box")
			.is_empty())
	c = await commands.run("material_apply", {"part": wall, "material": "no_such_material"})
	_check("an unknown material: refused", c.get("ok") == false)
	c = await commands.run("material_apply", {"part": "No Such Part", "material": id})
	_check("an unknown part: refused, naming pointed_part", c.get("ok") == false and str(c.get("error", ""))
			.contains("pointed_part"))


func _test_apply_mode() -> void:
	var layer: Node = main.ui
	var eye: Vector3 = main.camera.global_position
	var env: Node3D = main.env
	_aim(eye, eye + (-env.global_basis.z) * 20.0)
	var id := "ms_" + MS_ASSET
	_check("Apply starts the apply mode", layer.start_part_apply({"material": id}) and layer.is_applying()
			and layer.is_placing_object())
	var placer: Node = layer._placer
	var hand: Node3D = layer.pointer_hand
	placer.update(hand)
	var aimed: Dictionary = placer.aimed
	_check("the laser's part shows the material while it points (%s)" % [aimed.get("part", "")], not aimed.is_empty()
			and MaterialLibrary.id_of((aimed["node"] as GeometryInstance3D).material_override) == id)
	var t0: float = placer.apply_tiling
	placer.on_stick(Vector2(0, 1), 0.5)
	placer.on_stick(Vector2(1, 0), 0.5)
	_check("the stick sizes and turns the pattern (%.2f -> %.2f m, %.0f°)" % [t0, placer.apply_tiling,
			placer.apply_turn], placer.apply_tiling > t0 * 1.3 and absf(placer.apply_turn + 45.0) < 0.5)
	var sh := (aimed["node"] as GeometryInstance3D).material_override as ShaderMaterial
	_check("and the preview follows it", sh != null and absf(float(sh.get_shader_parameter("uv_turn"))
			- deg_to_rad(-45.0)) < 0.01)
	var labels: Dictionary = main.controller_labels("/interaction_profiles/valve/frame_controller_valve", "right",
			false, false, false, false, false, {}, true)
	_check("the legends: APPLY on the trigger (%s)" % [labels], labels.values().any(func(t: String) -> bool:
		return t.contains("APPLY")))
	var r: Dictionary = await placer.commit()
	await _frames(5)
	var part := str(aimed["part"])
	var entry := _entry(main.env.get("doc"), part)
	_check("the trigger applies it, kept with its tiling and turn (%s)" % [entry], r.get("ok") == true
			and entry.get("material", {}).get("library_material") == id and float(entry["material"].get("tiling", 0))
			> 2.5 and is_equal_approx(float(entry["material"].get("turn", 0)), -45.0))
	_check("and the mode ends", not layer.is_applying())
	layer.start_part_apply({"material": id})
	placer.update(hand)
	var node := placer.aimed.get("node") as GeometryInstance3D
	var showing: Material = node.material_override if node != null else null
	_check("B cancels: nothing changed, the part shows its own again", layer.cancel_object_place()
			and not layer.is_applying() and node != null and node.material_override != showing)
	await PartApply.reset(self, null, part)
	await _frames(3)


## Paint by material: a model whose Body mesh has two materials (Fabric, Wood) and whose Leg shares Wood.
func _test_paint_by_material() -> void:
	# The box from before would stand in the way.
	await ObjectCommands.remove_placed(self, null, "Test Box")
	await _frames(5)
	var glb := _sofa_glb()
	var read := RoomModel.load_glb(glb)
	var body_read := (read["node"] as Node).find_child("Body", true, false) as MeshInstance3D
	var leg_wood := false
	for q: Dictionary in read["parts"]:
		leg_wood = leg_wood or (q["name"] == "Leg" and q["materials"] == ["Wood"])
	_check("the model's surfaces name their file materials (%s)" % [read.get("parts")], body_read != null
			and RoomModel.surface_material(body_read, 0) == "Fabric" and RoomModel.surface_material(body_read, 1)
			== "Wood" and leg_wood)
	(read["node"] as Node).free()
	var imp := ObjectLibrary.import_glb(glb, "Test Sofa", ["sofa"], "floor")
	_check("the sofa imports (%s)" % imp.get("error", ""), imp.get("ok") == true)
	if imp.get("ok") != true:
		return
	var oid: String = imp["manifest"]["id"]
	var r: Dictionary = await ObjectCommands.place(self, null, oid, {"name": "Test Sofa", "position": [0, 1.2, -2.5]})
	await _frames(5)
	_check("the sofa placed (%s)" % r.get("error", ""), r.get("ok") == true)
	var env: Node3D = main.env
	var parts: Dictionary = AssistantRoom.parts_of_placed(env.get_node("AssistantLayer/Test Sofa"))
	var body := parts.get("Body") as MeshInstance3D
	var leg := parts.get("Leg") as MeshInstance3D
	_check("its parts: Body and Leg", body != null and leg != null)
	if body == null or leg == null:
		return
	var eye: Vector3 = main.camera.global_position
	_aim(eye, _surface_centre(body, 0))
	var p: Dictionary = PartApply.pointed(main)
	_check("pointed_part on the fabric: its material and the same-material match (%s)" % [p], p.get("part")
			== "Test Sofa/Body" and p.get("surface_material") == "Fabric" and p.get("same") == "Test Sofa/@Fabric")
	_aim(eye, _surface_centre(body, 1))
	p = PartApply.pointed(main)
	_check("on the Body's wood: Wood (%s)" % [p.get("same")], p.get("surface_material") == "Wood"
			and p.get("same") == "Test Sofa/@Wood")
	var c: Dictionary = await commands.run("pointed_part", {})
	_check("pointed_part (assistant) gives same too", c.get("ok") == true and c["result"]["same"] == "Test Sofa/@Wood")
	var info: Dictionary = await commands.run("object_info", {"placed": "Test Sofa"})
	_check("object_info lists the placed model's materials (%s)" % [info.get("result")],
			JSON.stringify(info.get("result", {})).contains("\"Fabric\"")
			and JSON.stringify(info.get("result", {})).contains("\"Wood\""))
	# The fabric only.
	var fabric := "acg_testbricks000"
	c = await commands.run("material_apply", {"part": "Test Sofa/@Fabric", "material": fabric})
	await _frames(5)
	_check("material_apply on Test Sofa/@Fabric (%s)" % [c.get("error", "")], c.get("ok") == true
			and _entry(main.env.get("doc"), "Test Sofa/@Fabric").get("material", {}).get("library_material") == fabric)
	parts = AssistantRoom.parts_of_placed(main.env.get_node("AssistantLayer/Test Sofa"))
	body = parts["Body"]
	leg = parts["Leg"]
	_check("the fabric shows it; the Body's wood and the Leg don't", AssistantRoom.material_id_of(body, 0) == fabric
			and AssistantRoom.material_id_of(body, 1) != fabric and AssistantRoom.material_id_of(leg) != fabric
			and body.material_override == null)
	# The wood, on the Body and the Leg alike.
	var wood := "ph_test_brick_wall_00"
	c = await commands.run("material_apply", {"part": "Test Sofa/@Wood", "material": wood})
	await _frames(5)
	parts = AssistantRoom.parts_of_placed(main.env.get_node("AssistantLayer/Test Sofa"))
	body = parts["Body"]
	leg = parts["Leg"]
	_check("@Wood: the Body's wood and the Leg, the fabric kept (%s)" % [c.get("error", "")], c.get("ok") == true
			and AssistantRoom.material_id_of(body, 1) == wood and AssistantRoom.material_id_of(leg) == wood
			and AssistantRoom.material_id_of(body, 0) == fabric)
	# The apply mode paints by material.
	var layer: Node = main.ui
	var placer: Node = layer._placer
	var hand: Node3D = layer.pointer_hand
	var id := "ms_" + MS_ASSET
	_aim(eye, _surface_centre(leg, 0))
	layer.start_part_apply({"material": id})
	placer.update(hand)
	_check("the apply mode on the Leg aims at the wood (%s)" % [placer.aimed.get("same")],
			PartApply.target_of(placer.aimed) == "Test Sofa/@Wood")
	_check("and the preview shows on the Leg and the Body's wood, not the fabric",
			MaterialLibrary.id_of(AssistantRoom.shown_material_at(leg, 0)) == id
			and MaterialLibrary.id_of(AssistantRoom.shown_material_at(body, 1)) == id
			and AssistantRoom.material_id_of(body, 0) == fabric)
	layer.cancel_object_place()
	_check("B: the preview goes, each surface as it was", AssistantRoom.material_id_of(body, 1) == wood
			and AssistantRoom.material_id_of(leg) == wood and AssistantRoom.material_id_of(body, 0) == fabric
			and body.material_override == null)
	_aim(eye, _surface_centre(body, 0))
	layer.start_part_apply({"material": id})
	placer.update(hand)
	r = await placer.commit()
	await _frames(5)
	parts = AssistantRoom.parts_of_placed(main.env.get_node("AssistantLayer/Test Sofa"))
	body = parts["Body"]
	leg = parts["Leg"]
	_check("the trigger on the fabric: Test Sofa/@Fabric changes, the wood stays (%s)" % [r.get("error", "")],
			r.get("ok") == true and AssistantRoom.material_id_of(body, 0) == id
			and AssistantRoom.material_id_of(body, 1) == wood and AssistantRoom.material_id_of(leg) == wood)
	# A whole-part entry after: it wins on both of the Body's surfaces.
	c = await commands.run("material_apply", {"part": "Test Sofa/Body", "material": fabric})
	await _frames(5)
	parts = AssistantRoom.parts_of_placed(main.env.get_node("AssistantLayer/Test Sofa"))
	body = parts["Body"]
	leg = parts["Leg"]
	_check("a later whole-part entry covers the Body, the Leg keeps the wood", c.get("ok") == true
			and AssistantRoom.material_id_of(body, 0) == fabric and AssistantRoom.material_id_of(body, 1) == fabric
			and AssistantRoom.material_id_of(leg) == wood)
	c = await commands.run("part_reset", {"part": "Test Sofa/@Wood"})
	await _frames(5)
	_check("part_reset on a material", c.get("ok") == true and _entry(main.env.get("doc"), "Test Sofa/@Wood")
			.is_empty())
	c = await commands.run("material_apply", {"part": "Test Sofa/@Velvet", "material": fabric})
	_check("a material the model doesn't have: refused", c.get("ok") == false)
	await ObjectCommands.remove_placed(self, null, "Test Sofa")
	ObjectLibrary.delete(oid)


## A surface's middle, in the world.
static func _surface_centre(mi: MeshInstance3D, s: int) -> Vector3:
	var verts: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
	var box := AABB(verts[0], Vector3.ZERO)
	for v in verts:
		box = box.expand(v)
	return mi.global_transform * box.get_center()


## The test sofa: Body (a fabric box and a wooden box, one mesh, two surfaces) and Leg (wood, the same material).
static func _sofa_glb() -> PackedByteArray:
	var fabric := StandardMaterial3D.new()
	fabric.resource_name = "Fabric"
	fabric.albedo_color = Color(0.7, 0.1, 0.1)
	var wood := StandardMaterial3D.new()
	wood.resource_name = "Wood"
	wood.albedo_color = Color(0.5, 0.3, 0.1)
	var root := Node3D.new()
	root.name = "Sofa"
	var mesh := ArrayMesh.new()
	for k in 2:
		var b := BoxMesh.new()
		b.size = Vector3(0.6, 0.6, 0.6)
		var arrays := b.get_mesh_arrays()
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in verts.size():
			verts[i] += Vector3(-0.5 if k == 0 else 0.5, 0, 0)
		arrays[Mesh.ARRAY_VERTEX] = verts
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(k, fabric if k == 0 else wood)
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = mesh
	root.add_child(body)
	var leg_mesh := BoxMesh.new()
	leg_mesh.size = Vector3(0.3, 0.3, 0.3)
	leg_mesh.material = wood
	var leg := MeshInstance3D.new()
	leg.name = "Leg"
	leg.mesh = leg_mesh
	leg.position = Vector3(1.3, 0, 0)
	root.add_child(leg)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	doc.append_from_scene(root, state)
	var out := doc.generate_buffer(state)
	root.free()
	return out


# --- Helpers ---------------------------------------------------------------------------------------------------------

## A user material's map, read from its file.
static func _map(id: String, slot: String) -> Image:
	var e := MaterialLibrary.entry(id)
	var rel := str(e.get("maps", {}).get(slot, ""))
	return Image.load_from_file(MaterialLibrary.user_dir.path_join(rel)) if rel != "" else null


static func _entry(doc: Dictionary, match: String) -> Dictionary:
	for r: Dictionary in doc.get("recolour", []):
		if str(r["match"]) == match:
			return r
	return {}


func _kept_room_text(name: String) -> String:
	var dir := "user://recipes"
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".room.json"):
			var t := FileAccess.get_file_as_string(dir.path_join(f))
			if t.contains("\"%s\"" % name):
				return t
	return ""


## The kept rooms this test made, gone (they name its materials and its box).
static func _forget_rooms(words: Array) -> void:
	var dir := "user://recipes"
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		var p := dir.path_join(f)
		var t := FileAccess.get_file_as_string(p) if f.ends_with(".json") else ""
		if words.any(func(w: String) -> bool: return t.contains(w)):
			DirAccess.remove_absolute(p)


static func _wipe(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for d in DirAccess.get_directories_at(dir):
		_wipe(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _until(cond: Callable, seconds := 5.0) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await process_frame


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)
