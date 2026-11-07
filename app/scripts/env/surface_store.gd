extends Node

## Surfaces from three sources in one search (docs/features.md "Surfaces", docs/materials.md "User materials",
## docs/decisions.md D29), imported into the user materials (surface_import.gd), by the viewer (Objects → Surfaces:
## ui/surface_panel.gd) or an assistant (material_search, material_import, material_status). The app makes every
## request; an assistant only asks it to.
##
##   megascans  Quixel Megascans' free surfaces on Fab, through fab_store.gd (its licence gate, its go-slow rules, its
##              cache; listing type "material", the texture set's 1K zip). Error "eula" until the viewer accepted.
##   polyhaven  api.polyhaven.com: no account or key, ever (their terms, 2.3); every request names this app in its
##              User-Agent (2.4); where the results show, "Powered by Poly Haven" says where they come from, with no
##              claim of endorsement (2.5). The whole texture list is one request (/assets?type=textures, about
##              850 KB), kept on disk and searched here, asked again at most once a day (INDEX_TTL); the files'
##              links come from /files/<id>.
##   ambientcg  ambientcg.com's API v2 (full_json): no account; a page of 24 with its 1K and 2K JPEG zips' links.
##              Its docs say it may not be "enterprise-level" stable: an answer that isn't as expected is an error
##              ("shape"), never a crash.
## The rules for all three (host_gate.gd): one request at a time, a source's pages 1 s apart, thumbnails and
## downloads a quarter of a second; a 429 or a 5xx backs that source off; answers are kept a day, thumbnails until
## the cache is full. No crawl: the next page only when asked for.
##
## The transport (fab_http.gd) is a child; a test sets `transport` to a fake with the same fetch(), progress() and
## cancel(), and `root` to its own folder.

const FabStore := preload("res://scripts/assistant/fab_store.gd")
const FabHttp := preload("res://scripts/assistant/fab_http.gd")
const HostGate := preload("res://scripts/assistant/host_gate.gd")
const SurfaceImport := preload("res://scripts/env/surface_import.gd")
const MaterialLibrary := preload("res://scripts/env/material_library.gd")
const WorkerTask := preload("res://scripts/dev/worker_task.gd")
const DevCommands := preload("res://scripts/dev/dev_commands.gd")

const NODE_NAME := "SurfaceStore"
const SOURCES: Array[String] = ["megascans", "polyhaven", "ambientcg"]
const PH_API := "https://api.polyhaven.com"
const PH_INDEX := PH_API + "/assets?type=textures"
const PH_FILES := PH_API + "/files/%s"
const ACG_SEARCH := "https://ambientcg.com/api/v2/full_json?type=Material&q=%s&limit=%d&offset=%d&include=" \
		+ "downloadData,displayData,tagData,dimensionsData,previewData"
const ACG_ASSET := "https://ambientcg.com/api/v2/full_json?id=%s&include=downloadData,displayData,tagData," \
		+ "dimensionsData,previewData"
const PAGE := 24
const INDEX_TTL := 86400
const SEARCH_TTL := 86400
const THUMB_CACHE_BYTES := 16 << 20
const QUERY_MAX := 100
## Where each result comes from, shown beside it (Poly Haven's terms ask for the first; the badges on the tiles).
const CREDITS := {"polyhaven": "Powered by Poly Haven", "ambientcg": "From ambientCG",
		"megascans": "Quixel Megascans, through Fab"}
const BADGES := {"polyhaven": "PH", "ambientcg": "aCG", "megascans": "MS"}
const JOB_STATES: Array[String] = ["files", "download", "import"]

signal changed

var transport: Object
var gate := HostGate.new()
var root := "user://surfaces"
var index_ttl := INDEX_TTL
var search_ttl := SEARCH_TTL
var thumb_cache_bytes := THUMB_CACHE_BYTES
## The Fab store (fab_store.gd) for Megascans; null: the app's.
var fab: Node
## Requests sent through this store's gate (the tests count them).
var requests: int:
	get:
		return gate.requests

var _job := {}
var _known := {}
var _index: Array = []
var _index_loaded := false


static func ensure(tree: SceneTree) -> Node:
	var s := tree.root.get_node_or_null(NODE_NAME)
	if s != null:
		return s
	if tree.root.has_meta(NODE_NAME) and is_instance_valid(tree.root.get_meta(NODE_NAME)):
		return tree.root.get_meta(NODE_NAME)
	s = (load("res://scripts/env/surface_store.gd") as GDScript).new()
	s.name = NODE_NAME
	tree.root.set_meta(NODE_NAME, s)
	tree.root.add_child.call_deferred(s)
	return s


func _init() -> void:
	var http := FabHttp.new()
	http.name = "Http"
	add_child(http)
	transport = http
	gate.names = {"polyhaven": "Poly Haven", "ambientcg": "ambientCG"}
	gate.changed.connect(func() -> void: changed.emit())


func _ready() -> void:
	FabStore._clear_dir(root.path_join("tmp"))


static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _fab() -> Node:
	if fab == null or not is_instance_valid(fab):
		fab = FabStore.ensure(_tree())
	return fab


static func _err(code: String, message: String, more := {}) -> Dictionary:
	var out := {"ok": false, "error": code, "message": message}
	out.merge(more)
	return out


## One GET in its turn (host_gate.gd), with the app's own User-Agent (Poly Haven's terms, 2.4).
func _get(url: String, kind: String, site: String, file := "", job := {}) -> Dictionary:
	if not is_inside_tree():
		await _tree().process_frame
	gate.transport = transport
	var h := PackedStringArray(["User-Agent: " + FabStore.user_agent()])
	if kind == "api":
		h.append("Accept: application/json")
	return await gate.request(url, h, kind, site, file, job)


func _json(url: String, site: String, job := {}) -> Dictionary:
	var r: Dictionary = await _get(url, "api", site, "", job)
	if r.has("ok"):
		return r
	return _answer(r, site, true)


static func _answer(r: Dictionary, site: String, json: bool) -> Dictionary:
	var who := str(SurfaceImport.SITES.get(site, {}).get("name", site))
	var e := str(r.get("error", ""))
	if e == "cancelled":
		return _err("cancelled", "cancelled")
	if e != "":
		return _err("network", "%s can't be reached (%s)" % [who, e.trim_prefix("network: ")])
	var code := int(r.get("code", 0))
	if code != 200:
		return _err("http", "%s answered HTTP %d" % [who, code], {"http": code})
	if not json:
		return {"ok": true}
	var j: Variant = JSON.parse_string((r.get("body", PackedByteArray()) as PackedByteArray).get_string_from_utf8())
	if j == null:
		return _err("shape", "%s's answer isn't JSON (its site may have changed)" % who)
	return {"ok": true, "data": j}


func backoff_left(site := "") -> float:
	if site == "megascans":
		return _fab().backoff_left()
	return gate.backoff_left(site)


# --- Search ----------------------------------------------------------------------------------------------------------

## One search over the sources (source "": all three; else one): {ok, query, results: [{source, id, title, tags,
## thumb, tiling, importable, in_library}], next (a cursor for the next page, "" on the last), credits [the sources'
## lines], errors {source: {error, message}}}, or an error when the one source asked for refused.
## cursor: a next this gave.
func search(query: String, source := "", cursor := "") -> Dictionary:
	var q := query.strip_edges().to_lower().left(QUERY_MAX)
	if q == "":
		return _err("query", "give a word or two to search for (in English: brick, oak, marble)")
	if source != "" and not (source in SOURCES):
		return _err("source", "source: one of %s, or empty for all" % ", ".join(SOURCES))
	var at: Dictionary = {}
	if cursor != "":
		var c: Variant = JSON.parse_string(cursor)
		if not (c is Dictionary):
			return _err("cursor", "that isn't a cursor material_search gave")
		at = c
	var sources: Array = [source] if source != "" else SOURCES.duplicate()
	if cursor != "":
		sources = sources.filter(func(s: String) -> bool: return at.has(s))
	var results: Array = []
	var next := {}
	var errors := {}
	for s: String in sources:
		var r: Dictionary
		match s:
			"megascans":
				r = await _search_megascans(q, str(at.get(s, "")))
			"polyhaven":
				r = await _search_polyhaven(q, int(at.get(s, 0)))
			"ambientcg":
				r = await _search_ambientcg(q, int(at.get(s, 0)))
		if not bool(r.get("ok", false)):
			if source != "":
				return r
			errors[s] = {"error": r.get("error", ""), "message": r.get("message", "")}
			continue
		for e: Dictionary in r["results"]:
			_known["%s:%s" % [s, e["id"]]] = e
			results.append(e)
		if str(r["next"]) != "":
			next[s] = r["next"]
	var credits: Array = []
	for s: String in sources:
		if not errors.has(s):
			credits.append(CREDITS[s])
	return {"ok": true, "query": q, "results": results, "next": JSON.stringify(next) if not next.is_empty() else "",
			"credits": credits, "errors": errors}


func _search_megascans(q: String, cursor: String) -> Dictionary:
	var r: Dictionary = await _fab().search(q, cursor, FabStore.MATERIAL_TYPE)
	if not bool(r.get("ok", false)):
		return r
	var out: Array = []
	for e: Dictionary in r["results"]:
		out.append({"source": "megascans", "id": e["uid"], "title": e["title"], "tags": e["tags"], "thumb": e["thumb"],
				"tiling": 0.0, "importable": e["importable"], "in_library": e["in_library"]})
	return {"ok": true, "results": out, "next": r["next"]}


# Poly Haven: the list once a day, searched here.

func _index_path() -> String:
	return root.path_join("polyhaven_textures.json")


## The texture list (cached a day): [{id, name, tags, tiling, thumb, authors, rank}], or an error.
func polyhaven_index() -> Dictionary:
	var path := _index_path()
	var age := INF
	if FileAccess.file_exists(path):
		age = Time.get_unix_time_from_system() - float(FileAccess.get_modified_time(path))
		if not _index_loaded:
			var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if j is Dictionary and (j as Dictionary).get("entries") is Array:
				_index = j["entries"]
				_index_loaded = true
	if _index_loaded and age <= index_ttl:
		return {"ok": true, "entries": _index, "cached": true}
	var r: Dictionary = await _json(PH_INDEX, "polyhaven")
	if not bool(r.get("ok", false)):
		# A stale list is better than none.
		if _index_loaded:
			return {"ok": true, "entries": _index, "cached": true, "stale": true}
		return r
	var entries := parse_polyhaven_index(r["data"])
	if entries.is_empty():
		return _err("shape", "Poly Haven's texture list wasn't as expected (its site may have changed)")
	_index = entries
	_index_loaded = true
	DirAccess.make_dir_recursive_absolute(root)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"entries": entries}))
		f.close()
	return {"ok": true, "entries": entries, "cached": false}


## /assets?type=textures read: what the search needs of each, the rest left out.
static func parse_polyhaven_index(data: Variant) -> Array:
	var out: Array = []
	if not (data is Dictionary):
		return out
	for id: Variant in data:
		var e: Variant = data[id]
		if not (e is Dictionary) or not RegEx.create_from_string("^[a-z0-9_-]{1,64}$").search(str(id)):
			continue
		var d := e as Dictionary
		var dims: Variant = d.get("dimensions")
		var tiling := float(dims[0]) / 1000.0 if dims is Array and (dims as Array).size() >= 1 \
				and float(dims[0]) > 0.0 else 0.0
		var words: Array = []
		for k: String in ["tags", "categories"]:
			if d.get(k) is Array:
				for t: Variant in d[k]:
					words.append(str(t).to_lower())
		var authors: Array = (d["authors"] as Dictionary).keys() if d.get("authors") is Dictionary else []
		out.append({"id": str(id), "name": str(d.get("name", id)), "tags": words, "tiling": snappedf(tiling, 0.01),
				"thumb": str(d.get("thumbnail_url", "")) if str(d.get("thumbnail_url", "")).begins_with("https://")
				else "", "authors": ", ".join(authors), "rank": int(d.get("download_count", 0))})
	return out


func _search_polyhaven(q: String, offset: int) -> Dictionary:
	var ix: Dictionary = await polyhaven_index()
	if not bool(ix.get("ok", false)):
		return ix
	var words := q.split(" ", false)
	var hits: Array = []
	for e: Dictionary in ix["entries"]:
		var hay := (str(e["id"]) + " " + str(e["name"]).to_lower() + " " + " ".join(e["tags"]))
		if Array(words).all(func(w: String) -> bool: return hay.contains(w)):
			hits.append(e)
	# The name's own words first, then the most downloaded.
	hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var na := str(a["name"]).to_lower().contains(q)
		var nb := str(b["name"]).to_lower().contains(q)
		if na != nb:
			return na
		return int(a["rank"]) > int(b["rank"]))
	var page := hits.slice(offset, offset + PAGE)
	var out: Array = []
	for e: Dictionary in page:
		var have := SurfaceImport.material_for_asset("polyhaven", str(e["id"]))
		out.append({"source": "polyhaven", "id": e["id"], "title": e["name"], "tags": (e["tags"] as Array).slice(0, 8),
				"thumb": e["thumb"], "tiling": e["tiling"], "importable": true, "author": e["authors"],
				"in_library": str(have.get("id", ""))})
	return {"ok": true, "results": out, "next": str(offset + PAGE) if offset + PAGE < hits.size() else ""}


# ambientCG: its own search, a page kept a day.

func _search_ambientcg(q: String, offset: int) -> Dictionary:
	var url := ACG_SEARCH % [q.uri_encode(), PAGE, offset]
	var page := _cached(url)
	if page.is_empty():
		var r: Dictionary = await _json(url, "ambientcg")
		if not bool(r.get("ok", false)):
			return r
		page = parse_ambientcg(r["data"], offset)
		if page.has("error"):
			return _err("shape", str(page["error"]))
		_cache(url, page)
	var out: Array = []
	for e: Dictionary in page["results"]:
		var shown := e.duplicate(true)
		shown["in_library"] = str(SurfaceImport.material_for_asset("ambientcg", str(e["id"])).get("id", ""))
		out.append(shown)
	return {"ok": true, "results": out, "next": str(page["next"])}


## full_json read: {results: [{source, id, title, tags, thumb, tiling, zip, zip_size, importable}], next} or {error}.
static func parse_ambientcg(data: Variant, offset: int) -> Dictionary:
	if not (data is Dictionary) or not ((data as Dictionary).get("foundAssets") is Array):
		return {"error": "ambientCG's answer has no foundAssets list (its API may have changed)"}
	var out: Array = []
	for a: Variant in data["foundAssets"]:
		var e := parse_ambientcg_asset(a)
		if not e.is_empty():
			out.append(e)
	var total := int((data as Dictionary).get("numberOfResults", 0))
	var n := (data["foundAssets"] as Array).size()
	return {"results": out, "next": str(offset + n) if n > 0 and offset + n < total else ""}


static func parse_ambientcg_asset(a: Variant) -> Dictionary:
	if not (a is Dictionary):
		return {}
	var d := a as Dictionary
	var id := str(d.get("assetId", ""))
	if not RegEx.create_from_string("^[A-Za-z0-9_-]{1,64}$").search(id):
		return {}
	var zip := ""
	var size := 0
	var folders: Variant = d.get("downloadFolders")
	if folders is Dictionary:
		for fk: Variant in folders:
			var cats: Variant = (folders[fk] as Dictionary).get("downloadFiletypeCategories") if folders[fk] is Dictionary \
					else null
			var zips: Variant = (cats as Dictionary).get("zip") if cats is Dictionary else null
			var downloads: Variant = (zips as Dictionary).get("downloads") if zips is Dictionary else null
			if not (downloads is Array):
				continue
			for want: String in ["1K-JPG", "2K-JPG"]:
				for x: Variant in downloads:
					if zip == "" and x is Dictionary and str(x.get("attribute", "")) == want \
							and str(x.get("downloadLink", "")).begins_with("https://"):
						zip = str(x["downloadLink"])
						size = int(x.get("size", 0))
	var thumb := ""
	if d.get("previewImage") is Dictionary:
		for k: String in ["256-PNG", "128-PNG", "512-PNG"]:
			if thumb == "" and str(d["previewImage"].get(k, "")).begins_with("https://"):
				thumb = str(d["previewImage"][k])
	var tags: Array = []
	if d.get("tags") is Array:
		for t: Variant in d["tags"]:
			if tags.size() < 8:
				tags.append(str(t).to_lower())
	# Its size: dimensionX in centimetres (0: not given).
	var cm := float(d.get("dimensionX", 0)) if (d.get("dimensionX") is float or d.get("dimensionX") is int) else 0.0
	var title := str(d.get("displayName", id)).strip_edges()
	return {"source": "ambientcg", "id": id, "title": title if title != "" else id, "tags": tags, "thumb": thumb,
			"tiling": snappedf(cm / 100.0, 0.01) if cm > 0.0 else 0.0, "zip": zip, "zip_size": size,
			"importable": zip != ""}


func _cached(url: String) -> Dictionary:
	var path := root.path_join("search").path_join(url.md5_text() + ".json")
	if not FileAccess.file_exists(path):
		return {}
	if Time.get_unix_time_from_system() - float(FileAccess.get_modified_time(path)) > search_ttl:
		return {}
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return j if j is Dictionary and (j as Dictionary).get("results") is Array else {}


func _cache(url: String, page: Dictionary) -> void:
	var dir := root.path_join("search")
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join(url.md5_text() + ".json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(page))
		f.close()


# --- Thumbnails ------------------------------------------------------------------------------------------------------

## A result's thumbnail (cached, else fetched in its turn and kept), or null. A Megascans one through the Fab store.
func thumbnail(result: Dictionary) -> Image:
	var url := str(result.get("thumb", ""))
	if not url.begins_with("https://"):
		return null
	if str(result.get("source", "")) == "megascans":
		return await _fab().thumbnail(url)
	var path := root.path_join("thumbs").path_join(url.md5_text() + ".img")
	if FileAccess.file_exists(path):
		return SurfaceImport.image_of(FileAccess.get_file_as_bytes(path))
	var r: Dictionary = await _get(url, "thumb", str(result.get("source", "")))
	if r.has("ok") or str(r.get("error", "")) != "" or int(r.get("code", 0)) != 200:
		return null
	var bytes: PackedByteArray = r.get("body", PackedByteArray())
	var img := SurfaceImport.image_of(bytes)
	if img == null:
		return null
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_buffer(bytes)
		f.close()
	_trim_thumbs()
	return img


func _trim_thumbs() -> void:
	var dir := root.path_join("thumbs")
	var files: Array = []
	var total := 0
	for f in DirAccess.get_files_at(dir):
		var p := dir.path_join(f)
		var n := FabStore._size(p)
		total += n
		files.append([FileAccess.get_modified_time(p), p, n])
	if total <= thumb_cache_bytes:
		return
	files.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
	for e: Array in files:
		if total <= thumb_cache_bytes * 4 / 5:
			break
		DirAccess.remove_absolute(str(e[1]))
		total -= int(e[2])


func clear_cache() -> void:
	for k: String in ["search", "thumbs"]:
		FabStore._clear_dir(root.path_join(k))
	DirAccess.remove_absolute(_index_path())
	_index = []
	_index_loaded = false
	changed.emit()


# --- Import ----------------------------------------------------------------------------------------------------------

func job_active() -> bool:
	return str(job_state().get("state", "")) in JOB_STATES


## Starts importing a search result (source and id as material_search gave them), in the background:
## {ok, state: started, source, id, title}, {ok, state: already, material: {id, name}} or an error.
func start_import(source: String, id: String) -> Dictionary:
	if not (source in SOURCES):
		return _err("source", "source: one of %s" % ", ".join(SOURCES))
	if source == "megascans":
		var r: Dictionary = _fab().start_import(id, str(_known.get("megascans:" + id, {}).get("title", "")),
				FabStore.MATERIAL_TYPE)
		if bool(r.get("ok", false)):
			r["source"] = source
			if r.has("object"):
				r["material"] = r["object"]
				r.erase("object")
			if r.get("state") == "started":
				_job = {"via_fab": true, "state": "files"}
				changed.emit()
		return r
	if not RegEx.create_from_string("^[A-Za-z0-9_-]{1,64}$").search(id):
		return _err("id", "not an id material_search gave")
	if job_active():
		return _err("busy", "%s is on its way already: material_status says how far" % job_state()["title"])
	var have := SurfaceImport.material_for_asset(source, id)
	if not have.is_empty():
		return {"ok": true, "state": "already", "source": source, "id": id,
				"material": {"id": have["id"], "name": have["name"]}}
	var known: Dictionary = _known.get("%s:%s" % [source, id], {})
	_job = {"source": source, "id": id, "title": str(known.get("title", id)), "state": "files", "bytes": 0,
			"total": -1, "error": "", "message": "", "material": {}, "cancel": false, "known": known}
	changed.emit()
	if source == "polyhaven":
		_run_polyhaven(_job)
	else:
		_run_ambientcg(_job)
	return {"ok": true, "state": "started", "source": source, "id": id, "title": _job["title"]}


func cancel() -> bool:
	if bool(_job.get("via_fab", false)):
		return _fab().cancel()
	if not (str(_job.get("state", "")) in JOB_STATES):
		return false
	_job["cancel"] = true
	if _job["state"] == "download" and gate.busy():
		transport.cancel()
	changed.emit()
	return true


## Poly Haven's files for the 1K (2K where ASTC is made here) JPEGs: base colour, OpenGL normal, roughness (or the
## packed AO-roughness-metal map), ambient occlusion. {slot: url} or {error}.
static func polyhaven_files(data: Variant, res: String) -> Dictionary:
	if not (data is Dictionary):
		return {"error": "Poly Haven's file list isn't as expected"}
	var keys := {}
	for k: Variant in data:
		keys[str(k).to_lower()] = k
	var url := func(name: String) -> String:
		var k: Variant = keys.get(name.to_lower())
		if k == null or not (data[k] is Dictionary):
			return ""
		for r: String in [res, "1k", "2k"]:
			var e: Variant = (data[k] as Dictionary).get(r)
			if e is Dictionary and (e as Dictionary).get("jpg") is Dictionary:
				var u := str(e["jpg"].get("url", ""))
				if u.begins_with("https://"):
					return u
		return ""
	var out := {"albedo": url.call("Diffuse"), "normal": url.call("nor_gl"), "roughness": url.call("Rough"),
			"ao": url.call("AO")}
	if out["roughness"] == "":
		out["arm"] = url.call("arm")
	if out["albedo"] == "" or out["normal"] == "":
		return {"error": "this texture has no base colour or OpenGL normal map in JPEG"}
	for k: String in out.keys():
		if out[k] == "":
			out.erase(k)
	return out


func _run_polyhaven(job: Dictionary) -> void:
	var r: Dictionary = await _json(PH_FILES % job["id"], "polyhaven", job)
	if _stopped(job, r):
		return
	var files := polyhaven_files(r["data"], "2k" if SurfaceImport.astc_available() else "1k")
	if files.has("error"):
		_end(job, "failed", "no_file", str(files["error"]))
		return
	_step(job, "download")
	var dir := root.path_join("tmp")
	DirAccess.make_dir_recursive_absolute(dir)
	var paths := {}
	for slot: String in files:
		var path := dir.path_join("%s_%s.jpg" % [job["id"], slot])
		var got: Dictionary = await _get(str(files[slot]), "file", "polyhaven", path, job)
		if not got.has("ok"):
			got = _answer(got, "polyhaven", false)
		if _stopped(job, got):
			_remove(paths.values() + [path])
			return
		paths[slot] = path
		job["bytes"] = int(job["bytes"]) + FabStore._size(path)
	_step(job, "import")
	var known: Dictionary = job["known"]
	if known.is_empty():
		for e: Dictionary in _index:
			if str(e["id"]) == str(job["id"]):
				known = {"title": e["name"], "tags": e["tags"], "tiling": e["tiling"], "author": e["authors"]}
	var info := {"name": str(known.get("title", job["id"])), "tags": known.get("tags", []),
			"tiling": float(known.get("tiling", 0.0)), "author": str(known.get("author", ""))}
	var id := str(job["id"])
	var w: Dictionary = await WorkerTask.run(_tree(), func() -> Variant:
		var maps := {}
		for slot: String in paths:
			var img := SurfaceImport.image_of(FileAccess.get_file_as_bytes(paths[slot]))
			if img == null:
				continue
			if slot == "arm":
				# AO in red, roughness in green: split.
				maps["roughness"] = _channel(img, 1)
				maps["ao"] = _channel(img, 0)
			else:
				maps[slot] = img
		return SurfaceImport.import_maps("polyhaven", id, info, maps), 120.0)
	_remove(paths.values())
	_finish(job, w)


## One channel of an RGB picture as a grey one.
static func _channel(img: Image, c: int) -> Image:
	var src := img.duplicate() as Image
	src.convert(Image.FORMAT_RGB8)
	var d := src.get_data()
	var out := PackedByteArray()
	out.resize(src.get_width() * src.get_height())
	for i in out.size():
		out[i] = d[i * 3 + c]
	return Image.create_from_data(src.get_width(), src.get_height(), false, Image.FORMAT_L8, out)


func _run_ambientcg(job: Dictionary) -> void:
	var known: Dictionary = job["known"]
	if str(known.get("zip", "")) == "":
		var r: Dictionary = await _json(ACG_ASSET % job["id"], "ambientcg", job)
		if _stopped(job, r):
			return
		var page := parse_ambientcg(r["data"], 0)
		if page.has("error") or (page["results"] as Array).is_empty():
			_end(job, "failed", "shape", "ambientCG has no material %s" % job["id"])
			return
		known = page["results"][0]
		job["title"] = known["title"]
	if str(known.get("zip", "")) == "":
		_end(job, "failed", "no_file", "this material has no 1K or 2K JPEG zip")
		return
	if int(known.get("zip_size", 0)) > SurfaceImport.MAX_ZIP_BYTES:
		_end(job, "failed", "too_big", "the zip is %d MB" % (int(known["zip_size"]) >> 20))
		return
	job["total"] = int(known.get("zip_size", -1))
	_step(job, "download")
	var dir := root.path_join("tmp")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(str(job["id"]) + ".zip")
	var got: Dictionary = await _get(str(known["zip"]), "file", "ambientcg", path, job)
	if not got.has("ok"):
		got = _answer(got, "ambientcg", false)
	if _stopped(job, got):
		_remove([path])
		return
	_step(job, "import")
	var id := str(job["id"])
	var info := {"name": str(known.get("title", id)), "tags": known.get("tags", []),
			"tiling": float(known.get("tiling", 0.0))}
	var w: Dictionary = await WorkerTask.run(_tree(), func() -> Variant:
		return SurfaceImport.import_ambientcg_zip(path, id, info), 120.0)
	_remove([path])
	_finish(job, w)


func _finish(job: Dictionary, w: Dictionary) -> void:
	var out: Dictionary = w.get("result", {}) if bool(w.get("done", false)) and w.get("result") is Dictionary \
			else {"ok": false, "error": "the import took too long"}
	if bool(job["cancel"]):
		if out.get("ok") == true:
			SurfaceImport.delete(str(out["entry"]["id"]))
		_end(job, "cancelled")
		return
	if out.get("ok") != true:
		_end(job, "failed", "import", str(out.get("error", "the import failed")))
		return
	SurfaceImport.loaded()
	var e: Dictionary = out["entry"]
	job["material"] = {"id": e["id"], "name": e["name"]}
	_end(job, "done")
	var mat_name := str(e["name"])
	_notify(TranslationServer.translate("%s is in your materials.") % mat_name) # i18n
	var oc := load("res://scripts/assistant/object_commands.gd") as GDScript
	oc.call("_sync_tab")


static func _remove(paths: Array) -> void:
	for p: Variant in paths:
		if FileAccess.file_exists(str(p)):
			DirAccess.remove_absolute(str(p))


func _stopped(job: Dictionary, r: Dictionary) -> bool:
	if bool(job["cancel"]) or str(r.get("error", "")) == "cancelled":
		_end(job, "cancelled")
		return true
	if not bool(r.get("ok", false)):
		_end(job, "failed", str(r.get("error", "")), str(r.get("message", "")))
		return true
	return false


func _step(job: Dictionary, state: String) -> void:
	job["state"] = state
	changed.emit()


func _end(job: Dictionary, state: String, error := "", message := "") -> void:
	job["state"] = state
	job["error"] = error
	job["message"] = message
	changed.emit()


func _notify(text: String) -> void:
	var m := _tree().current_scene
	var ui: Object = m.get("ui") if m != null else null
	if ui != null and ui.has_method("notify"):
		ui.notify(text)


## The import now or the last one (Poly Haven, ambientCG; a Megascans one is the Fab store's): {source, id, title,
## state, bytes, total, error, message, material}, or {}.
func job_state() -> Dictionary:
	if bool(_job.get("via_fab", false)):
		var fj: Dictionary = _fab().job_state()
		if str(fj.get("kind", "")) != FabStore.MATERIAL_TYPE:
			return {}
		return {"source": "megascans", "id": fj["uid"], "title": fj["title"], "state": {"files": "files",
				"link": "files"}.get(fj["state"], fj["state"]), "bytes": fj["bytes"], "total": fj["total"],
				"error": fj["error"], "message": fj["message"], "material": fj["object"]}
	if _job.is_empty():
		return {}
	if _job["state"] == "download" and gate.busy():
		var p: Array = transport.progress()
		if int(p[1]) > 0:
			_job["total"] = int(p[1])
	var out := _job.duplicate(true)
	out.erase("cancel")
	out.erase("known")
	return out


## material_status: the import, the back-offs, the user materials and what they take.
func status() -> Dictionary:
	var users := SurfaceImport.user_entries()
	var disk := 0
	var gpu := 0
	for e: Dictionary in users:
		gpu += int(e.get("gpu_bytes", 0))
		for m: String in e.get("maps", {}):
			disk += FabStore._size(SurfaceImport.dir().path_join(str(e["maps"][m])))
	var mem := MaterialLibrary.memory()
	return {"job": job_state(), "busy": gate.busy() or _fab().gate.busy(),
			"backoff_s": {"polyhaven": ceili(gate.backoff_left("polyhaven")),
					"ambientcg": ceili(gate.backoff_left("ambientcg")), "megascans": ceili(_fab().backoff_left())},
			"fab_eula_accepted": _fab().eula_accepted(), "user_materials": users.size(),
			"disk_bytes": disk, "gpu_bytes_if_all_loaded": gpu, "gpu_bytes_loaded": int(mem["user_bytes"]),
			"astc": SurfaceImport.astc_available(),
			"resolution": "2K ASTC 8x8" if SurfaceImport.astc_available() else "1K uncompressed, mipmaps"}


# --- The commands ----------------------------------------------------------------------------------------------------

## material_search and material_status (read), material_import (room).
static func register_commands(_host: Node = null) -> void:
	var R := DevCommands
	R.register("material_search", func(a: Dictionary, ctx: DevCommands.Call) -> Variant:
		var r: Dictionary = await ensure(_tree()).search(str(a["query"]), str(a["source"]), str(a["cursor"]))
		if not r["ok"]:
			return FabStore._fail(ctx, r)
		var out: Array = []
		for e: Dictionary in r["results"]:
			out.append({"source": e["source"], "id": e["id"], "title": e["title"], "tags": e["tags"],
					"tiling": e["tiling"], "importable": e["importable"], "in_library": e["in_library"]})
		return {"query": r["query"], "results": out, "count": out.size(), "next": r["next"], "credits": r["credits"],
				"errors": r["errors"]}, {
		"description": "Searches surfaces to import as materials (walls, floors, fabric, stone, wood...) from Quixel "
				+ "Megascans (through Fab; error eula until the user has accepted Fab's licence in Objects → Your "
				+ "objects → Fab), Poly Haven and ambientCG (both CC0), 24 a page from each. The app asks the "
				+ "sites, one request at a time, and keeps the answers a day. A title is the site's, in English; "
				+ "credits say where the results come from (tell the user: \"Powered by Poly Haven\").",
		"params": [{"name": "query", "type": "string", "required": true, "description": "Words in English (brick, "
				+ "oak floor, marble)."},
				{"name": "source", "type": "string", "default": "", "enum": ["", "megascans", "polyhaven",
				"ambientcg"], "description": "One source; empty: all three (a source that refuses is in errors)."},
				{"name": "cursor", "type": "string", "default": "", "description": "The next page: the `next` of the "
				+ "page before."}],
		"assistant": "read", "title": "Search surfaces to import",
		"returns": "{query, results: [{source, id, title, tags, tiling (metres, 0 unknown), importable, in_library "
				+ "(the material's id, or empty)}], count, next, credits, errors {source: {error, message}}}"})
	R.register("material_import", func(a: Dictionary, ctx: DevCommands.Call) -> Variant:
		var r: Dictionary = ensure(_tree()).start_import(str(a["source"]), str(a["id"]))
		if not r["ok"]:
			return FabStore._fail(ctx, r)
		r.erase("ok")
		if r["state"] == "started":
			ctx.summary = "importing %s" % r["title"]
		return r, {
		"description": "Imports a material_search result into the user's materials (1K maps: colour with its "
				+ "shading, normal, roughness), in the background: material_status says how far, and gives the "
				+ "material's id when done (then material_apply). Megascans ones are refused with error eula until "
				+ "the user has accepted Fab's licence in Objects → Your objects → Fab: ask them to.",
		"params": [{"name": "source", "type": "string", "required": true, "enum": SOURCES,
				"description": "megascans, polyhaven or ambientcg (material_search's source)."},
				{"name": "id", "type": "string", "required": true, "description": "The result's id."}],
		"level": "change", "assistant": "room", "title": "Import a material",
		"returns": "{state: started, source, id, title} or {state: already, material: {id, name}}; refused: {error: "
				+ "eula | busy | source | id, message}"})
	R.register("material_status", func(_a: Dictionary, _ctx: DevCommands.Call) -> Variant:
		return ensure(_tree()).status(), {
		"description": "Material imports: the one under way or the last (state files, download, import, done, "
				+ "already, failed, cancelled; the material's id when done), the sites' back-offs, whether Fab's "
				+ "licence is accepted, the user materials and the memory they take (on the GPU: each 1K "
				+ "uncompressed material about 12.6 MB once a room shows it).",
		"params": [], "assistant": "read", "title": "Material imports and memory",
		"returns": "{job, busy, backoff_s {polyhaven, ambientcg, megascans}, fab_eula_accepted, user_materials, "
				+ "disk_bytes, gpu_bytes_if_all_loaded, gpu_bytes_loaded, astc, resolution}"})
