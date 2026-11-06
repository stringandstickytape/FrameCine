extends Node

## Fab in the app (docs/features.md "Fab in the app", docs/assistant.md "Objects from Fab", docs/decisions.md D27):
## Quixel Megascans' free objects searched and imported from Fab with no browser and no sign-in, by the viewer
## (Objects, Your objects, Fab: ui/fab_panel.gd) or by an assistant (fab_search, fab_import, fab_status, fab_cancel).
## The app makes every request; an assistant only asks it to.
##
## Fab's own site endpoints (no published API: every answer is read with care, and a change shows as an error, not
## a crash): the search (always seller Quixel Megascans, free, 3D models), a listing's files, and a file's link (a
## signed URL on Epic's CDN, good for a few hours). The zip goes to user://fab/tmp, then to the importer
## (fab_import.gd import_zip()), then away.
##
## The rules (the user's, 2026-11-06):
##   - nothing before the viewer has accepted Fab's licence (its EULA), in the headset's menu: [fab] eula_accepted
##     holds the date. accept_eula() is the Objects tab's alone; no command calls it. Every command refuses with
##     error "eula" until then.
##   - one request at a time; API_GAP (1 s) before each of Fab's pages after the last request ended, THUMB_GAP before
##     a thumbnail or the download. A 429 or a 5xx: no request at all for Retry-After seconds, else BACKOFF_BASE
##     doubled with each one in a row (at most BACKOFF_MAX); a success starts the count again.
##   - a search page is kept a day (SEARCH_TTL), a thumbnail until the cache is cleared (at most THUMB_CACHE_BYTES:
##     the oldest go first). No crawl: the next page only when asked for.
##   - an object already in the library (its listing's id, `fab_listing`, or the asset's id in the file's name,
##     `fab`) is not downloaded again.
##   - the FBX zip, mid, else low, else high (FORMAT, SIZES): what fab_import.gd reads, at the Frame's size.
##
## The transport (fab_http.gd) is a child; a test sets `transport` to a fake with the same fetch(), progress() and
## cancel(), and `settings` and `root` to its own.

const FabImport := preload("res://scripts/assistant/fab_import.gd")
const FabHttp := preload("res://scripts/assistant/fab_http.gd")
const HostGate := preload("res://scripts/assistant/host_gate.gd")
const ObjectLibrary := preload("res://scripts/assistant/object_library.gd")
const ObjectCommands := preload("res://scripts/assistant/object_commands.gd")
const SurfaceImport := preload("res://scripts/env/surface_import.gd")
const WorkerTask := preload("res://scripts/dev/worker_task.gd")
const DevCommands := preload("res://scripts/dev/dev_commands.gd")

const NODE_NAME := "FabStore"
const SITE := "https://www.fab.com"
## The search: Quixel Megascans' free 3D models only; q and cursor are added.
const SEARCH := SITE + "/i/listings/search?seller=Quixel%20Megascans&is_free=1&listing_types=3d-model&q="
const FILES := SITE + "/i/listings/%s/asset-formats"
const LINK := SITE + "/i/listings/%s/asset-formats/%s/files/%s/download-info"
## Fab's licence, in full (the headset's browser shows it).
const EULA_URL := "https://www.fab.com/eula"
const WHERE := "Objects → Your objects → Fab"
const EULA_MESSAGE := "Ask the user to accept Fab's licence in Objects → Your objects → Fab first. Only the user " \
		+ "can, in the headset's menu; no command can."
const PROJECT_URL := "https://github.com/stringandstickytape/steam-frame-vr-video-player"

const API_GAP := 1.0
const THUMB_GAP := 0.25
const BACKOFF_BASE := 2.0
const BACKOFF_MAX := 300.0
const SEARCH_TTL := 86400
const THUMB_CACHE_BYTES := 16 << 20
## The download Fab's zips come in that the importer reads (fab_import.gd: an .fbx, its maps and the asset's .json),
## and the sizes in the order taken: mid (2K maps) suits the Frame's memory; raw never.
const FORMAT := "fbx"
const SIZES: Array[String] = ["mid", "low", "high"]
## Fab's listing types: 3D models (the object library) and Megascans' surfaces (the material search,
## scripts/env/surface_store.gd). A surface comes as a texture set: a zip of JPEG maps and the asset's .json, 1K first.
const MODEL_TYPE := "3d-model"
const MATERIAL_TYPE := "material"
const MATERIAL_FORMAT := "texture-set"
const MATERIAL_SIZES: Array[String] = ["1k", "2k"]
const SEARCH_BASE := SITE + "/i/listings/search?seller=Quixel%20Megascans&is_free=1&listing_types="
const QUERY_MAX := 100
const CURSOR_MAX := 200
const TAGS_MAX := 8
## The smallest thumbnail at least this wide (Fab's smallest is 144 x 81, about 2 KB).
const THUMB_MIN_WIDTH := 144
const JOB_STATES: Array[String] = ["files", "link", "download", "import"]

## A request began or ended, the job moved on, a back-off began, the licence was accepted or withdrawn.
signal changed

## fetch(url, headers, file) -> {code, headers, body, error} (await), progress() -> [bytes, total], cancel().
var transport: Object
## get_value() and set_value() (app_settings.gd); null: the main scene's.
var settings: Object
var root := "user://fab"
## The go-slow rules (host_gate.gd): one request at a time, the gaps, the back-off. Its site is "fab".
var gate := HostGate.new()
var api_gap := API_GAP:
	set(v):
		api_gap = v
		gate.api_gap = v
var thumb_gap := THUMB_GAP:
	set(v):
		thumb_gap = v
		gate.thumb_gap = v
var search_ttl := SEARCH_TTL
var thumb_cache_bytes := THUMB_CACHE_BYTES
## Requests sent (the tests count them).
var requests: int:
	get:
		return gate.requests

var _job := {}
var _known := {}
var _thumb_bytes := -1


static func ensure(tree: SceneTree) -> Node:
	var s := tree.root.get_node_or_null(NODE_NAME)
	if s != null:
		return s
	if tree.root.has_meta(NODE_NAME) and is_instance_valid(tree.root.get_meta(NODE_NAME)):
		return tree.root.get_meta(NODE_NAME)
	s = (load("res://scripts/assistant/fab_store.gd") as GDScript).new()
	s.name = NODE_NAME
	# The root may be busy adding the main scene (the Objects tab is made in main's _ready()).
	tree.root.set_meta(NODE_NAME, s)
	tree.root.add_child.call_deferred(s)
	return s


func _init() -> void:
	var http := FabHttp.new()
	http.name = "Http"
	add_child(http)
	transport = http
	gate.names["fab"] = "Fab"
	gate.changed.connect(func() -> void: changed.emit())


func _ready() -> void:
	# A download cut short (the app closed): its temporary file.
	_clear_dir(root.path_join("tmp"))


static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# --- The licence ---------------------------------------------------------------------------------------------------

func _settings() -> Object:
	if settings != null:
		return settings
	var m := _tree().current_scene if _tree() != null else null
	return m.get("settings") if m != null else null


## The day the viewer accepted Fab's licence ("2026-11-06"), or "".
func eula_date() -> String:
	var s := _settings()
	return str(s.get_value("fab", "eula_accepted", "")) if s != null else ""


func eula_accepted() -> bool:
	return eula_date() != ""


## The viewer pressed Accept in the Objects tab. Nothing else calls this: no command may accept for them.
func accept_eula() -> void:
	var s := _settings()
	if s != null:
		s.set_value("fab", "eula_accepted", Time.get_date_string_from_system())
	changed.emit()


## Withdrawn: a download under way stops, and nothing more is asked of Fab until it is accepted again.
func withdraw_eula() -> void:
	cancel()
	var s := _settings()
	if s != null:
		s.set_value("fab", "eula_accepted", null)
	changed.emit()


func _gate() -> Dictionary:
	if eula_accepted():
		return {}
	return _err("eula", EULA_MESSAGE)


static func _err(code: String, message: String, more := {}) -> Dictionary:
	var out := {"ok": false, "error": code, "message": message}
	out.merge(more)
	return out


# --- Requests ------------------------------------------------------------------------------------------------------

## The app's own name and version, and where it comes from: not a browser's.
static func user_agent() -> String:
	return "VRVideoPlayer/%s (+%s)" % [app_version(), PROJECT_URL]


## The release's version (tools/package.sh writes VERSION beside the app), else "dev".
static func app_version() -> String:
	var v := str(ProjectSettings.get_setting("application/config/version", ""))
	if v != "":
		return v
	var f := ProjectSettings.globalize_path("res://").path_join("../VERSION")
	if FileAccess.file_exists(f):
		var line := FileAccess.get_file_as_string(f).get_slice("\n", 0).strip_edges()
		if line.begins_with("version "):
			return line.trim_prefix("version ").strip_edges().replace(" ", "-")
	return "dev"


## Seconds left of a back-off (0: none).
func backoff_left() -> float:
	return gate.backoff_left("fab")


## How long a back-off lasts: Retry-After when it says (seconds), else BACKOFF_BASE doubled for each in a row.
static func backoff_seconds(level: int, retry_after: String) -> float:
	return HostGate.backoff_seconds(level, retry_after)


## One GET in its turn (host_gate.gd): one request at a time; Fab's pages ("api") api_gap after the last one ended,
## thumbnails and the download thumb_gap; a thumbnail waits while a page or the download is waiting. None during a
## back-off. Returns the transport's {code, headers, body, error}, or an error ({ok: false, ...}). job: its cancel
## stops it before it is sent. kind "file": a download to `file`.
func _get(url: String, kind: String, file := "", job := {}) -> Dictionary:
	if not is_inside_tree():
		await _tree().process_frame
	gate.transport = transport
	return await gate.request(url, _headers(kind), kind, "fab", file, job)


func _headers(kind: String) -> PackedStringArray:
	var h := PackedStringArray(["User-Agent: " + user_agent()])
	if kind == "api":
		h.append("Accept: application/json")
	return h


## One of Fab's pages as JSON: {ok: true, data} or an error.
func _json(url: String, job := {}) -> Dictionary:
	var r: Dictionary = await _get(url, "api", "", job)
	if r.has("ok"):
		return r
	return _answer(r, true)


## A transport answer as {ok: true, data} (JSON) or {ok: true} (the file), or an error.
static func _answer(r: Dictionary, json: bool) -> Dictionary:
	var e := str(r.get("error", ""))
	if e == "cancelled":
		return _err("cancelled", "cancelled")
	if e != "":
		return _err("network", "Fab can't be reached (%s)" % e.trim_prefix("network: "))
	var code := int(r.get("code", 0))
	if code != 200:
		return _err("http", "Fab answered HTTP %d" % code, {"http": code})
	if not json:
		return {"ok": true}
	var j: Variant = JSON.parse_string((r.get("body", PackedByteArray()) as PackedByteArray).get_string_from_utf8())
	if j == null:
		return _err("shape", "Fab's answer isn't JSON (its site may have changed)")
	return {"ok": true, "data": j}


# --- Search --------------------------------------------------------------------------------------------------------

## A page of Megascans' free 3D models (kind MODEL_TYPE) or surfaces (MATERIAL_TYPE) for `query`: {ok, query,
## cursor, results: [{uid, title, category, tags, formats, importable, thumb, kind, in_library (the object's or the
## user material's id)}], next (the next page's cursor, or ""), cached} or an error.
func search(query: String, cursor := "", kind := MODEL_TYPE) -> Dictionary:
	var gate := _gate()
	if not gate.is_empty():
		return gate
	var q := query.strip_edges().to_lower().left(QUERY_MAX)
	if q == "":
		return _err("query", "give a word or two to search for (in English: rock, chair, cabbage)")
	if cursor.length() > CURSOR_MAX:
		return _err("cursor", "that isn't a cursor fab_search gave")
	var url := search_url(q, cursor, kind)
	var page := _cached_search(url)
	var cached := not page.is_empty()
	if not cached:
		var r: Dictionary = await _json(url)
		if not r["ok"]:
			return r
		page = parse_search(r["data"], kind)
		if page.has("error"):
			return _err("shape", str(page["error"]))
		_cache_search(url, page)
	var results: Array = []
	for e: Dictionary in page["results"]:
		_known[str(e["uid"])] = e
		var shown := e.duplicate(true)
		var have := object_for_listing(str(e["uid"])) if kind == MODEL_TYPE \
				else SurfaceImport.material_for_listing(str(e["uid"]))
		shown["in_library"] = str(have["id"]) if not have.is_empty() else ""
		results.append(shown)
	return {"ok": true, "query": q, "cursor": cursor, "results": results, "next": str(page["next"]),
			"cached": cached}


static func search_url(q: String, cursor := "", kind := MODEL_TYPE) -> String:
	var base := SEARCH if kind == MODEL_TYPE else SEARCH_BASE + kind + "&q="
	return base + q.uri_encode() + ("&cursor=" + cursor.uri_encode() if cursor != "" else "")


## Fab's search answer read: {results: [...], next} or {error}. What doesn't look right is left out.
static func parse_search(data: Variant, kind := MODEL_TYPE) -> Dictionary:
	if not (data is Dictionary) or not ((data as Dictionary).get("results") is Array):
		return {"error": "Fab's search answer has no results list (its site may have changed)"}
	var out: Array = []
	for r: Variant in data["results"]:
		var e := parse_result(r, kind)
		if not e.is_empty():
			out.append(e)
	var next := ""
	var c: Variant = (data as Dictionary).get("cursors")
	if c is Dictionary and (c as Dictionary).get("next") is String:
		next = str(c["next"])
	return {"results": out, "next": next}


static func parse_result(r: Variant, kind := MODEL_TYPE) -> Dictionary:
	if not (r is Dictionary):
		return {}
	var d := r as Dictionary
	var uid := str(d.get("uid", ""))
	var title: Variant = d.get("title")
	if not uid_ok(uid) or not (title is String) or (title as String).strip_edges() == "":
		return {}
	var category := ""
	if d.get("category") is Dictionary and (d["category"] as Dictionary).get("name") is String:
		category = str(d["category"]["name"])
	var tags: Array = []
	if d.get("tags") is Array:
		for t: Variant in d["tags"]:
			if t is Dictionary and (t as Dictionary).get("name") is String and tags.size() < TAGS_MAX:
				tags.append(str(t["name"]))
	var formats: Array = []
	if d.get("assetFormats") is Array:
		for f: Variant in d["assetFormats"]:
			if f is Dictionary and (f as Dictionary).get("assetFormatType") is Dictionary:
				formats.append(str(f["assetFormatType"].get("code", "")))
	return {"uid": uid, "title": (title as String).strip_edges(), "category": category, "tags": tags,
			"formats": formats, "importable": formats.is_empty()
			or (MATERIAL_FORMAT if kind == MATERIAL_TYPE else FORMAT) in formats, "thumb": thumb_of(d), "kind": kind}


## The first thumbnail's smallest picture at least THUMB_MIN_WIDTH wide (else its largest), or "".
static func thumb_of(d: Dictionary) -> String:
	if not (d.get("thumbnails") is Array) or (d["thumbnails"] as Array).is_empty():
		return ""
	var th: Variant = d["thumbnails"][0]
	if not (th is Dictionary) or not ((th as Dictionary).get("images") is Array):
		return ""
	var images: Array = (th["images"] as Array).filter(func(i: Variant) -> bool:
		return i is Dictionary and str((i as Dictionary).get("url", "")).begins_with("https://"))
	if images.is_empty():
		return ""
	images.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("width", 0)) < int(b.get("width", 0)))
	for i: Dictionary in images:
		if int(i.get("width", 0)) >= THUMB_MIN_WIDTH:
			return str(i["url"])
	return str(images[-1]["url"])


static func uid_ok(uid: String) -> bool:
	return RegEx.create_from_string("^[A-Za-z0-9-]{1,64}$").search(uid) != null


func _cached_search(url: String) -> Dictionary:
	var path := root.path_join("search").path_join(url.md5_text() + ".json")
	if not FileAccess.file_exists(path):
		return {}
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (j is Dictionary) or not ((j as Dictionary).get("page") is Dictionary):
		return {}
	if Time.get_unix_time_from_system() - float(j.get("saved", 0)) > search_ttl:
		return {}
	var page: Dictionary = j["page"]
	return page if page.get("results") is Array and page.has("next") else {}


func _cache_search(url: String, page: Dictionary) -> void:
	var dir := root.path_join("search")
	DirAccess.make_dir_recursive_absolute(dir)
	var now := Time.get_unix_time_from_system()
	# The day-old ones go as a new one is kept.
	for f in DirAccess.get_files_at(dir):
		var p := dir.path_join(f)
		if now - float(FileAccess.get_modified_time(p)) > search_ttl:
			DirAccess.remove_absolute(p)
	var file := FileAccess.open(dir.path_join(url.md5_text() + ".json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"saved": now, "url": url, "page": page}))
		file.close()


# --- Thumbnails ----------------------------------------------------------------------------------------------------

## A result's thumbnail (from the cache, else fetched in its turn and kept), or null.
func thumbnail(url: String) -> Image:
	if not eula_accepted() or not url.begins_with("https://"):
		return null
	var path := _thumb_path(url)
	if FileAccess.file_exists(path):
		return _image(FileAccess.get_file_as_bytes(path))
	var r: Dictionary = await _get(url, "thumb")
	if r.has("ok") or str(r.get("error", "")) != "" or int(r.get("code", 0)) != 200:
		return null
	var bytes: PackedByteArray = r.get("body", PackedByteArray())
	var img := _image(bytes)
	if img == null:
		return null
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_buffer(bytes)
		f.close()
		_trim_thumbs(bytes.size())
	return img


func _thumb_path(url: String) -> String:
	return root.path_join("thumbs").path_join(url.md5_text() + ".img")


## JPEG, PNG or WebP, by its first bytes.
static func _image(bytes: PackedByteArray) -> Image:
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
	return img if err == OK and not img.is_empty() else null


## The thumbnails kept within thumb_cache_bytes: past it, the oldest go until it is down to four fifths.
func _trim_thumbs(added: int) -> void:
	var dir := root.path_join("thumbs")
	if _thumb_bytes < 0:
		_thumb_bytes = 0
		for f in DirAccess.get_files_at(dir):
			_thumb_bytes += _size(dir.path_join(f))
	else:
		_thumb_bytes += added
	if _thumb_bytes <= thumb_cache_bytes:
		return
	var files: Array = []
	for f in DirAccess.get_files_at(dir):
		var p := dir.path_join(f)
		files.append([FileAccess.get_modified_time(p), p, _size(p)])
	files.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
	for e: Array in files:
		if _thumb_bytes <= thumb_cache_bytes * 4 / 5:
			break
		DirAccess.remove_absolute(str(e[1]))
		_thumb_bytes -= int(e[2])


static func _size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_length() if f != null else 0


## Searches and thumbnails kept: {searches, thumbs, bytes}.
func cache_info() -> Dictionary:
	var out := {"searches": 0, "thumbs": 0, "bytes": 0}
	for k: String in ["search", "thumbs"]:
		var dir := root.path_join(k)
		for f in DirAccess.get_files_at(dir):
			out["searches" if k == "search" else "thumbs"] += 1
			out["bytes"] += _size(dir.path_join(f))
	return out


func clear_cache() -> void:
	_clear_dir(root.path_join("search"))
	_clear_dir(root.path_join("thumbs"))
	_thumb_bytes = 0
	changed.emit()


static func _clear_dir(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))


# --- Import --------------------------------------------------------------------------------------------------------

## The user object imported from this listing, or {}.
static func object_for_listing(uid: String) -> Dictionary:
	for m: Dictionary in ObjectLibrary.list("", "user"):
		if str(m.get("fab_listing", "")) == uid:
			return m
	return {}


## The user object of this Fab asset (its id in the zip's .json, kept as `fab`), or {}.
static func object_for_asset(asset: String) -> Dictionary:
	if asset == "":
		return {}
	for m: Dictionary in ObjectLibrary.list("", "user"):
		if str(m.get("fab", "")) == asset:
			return m
	return {}


## The file to take from a listing's formats: the FBX zip, mid, else low, else high; for a surface (MATERIAL_TYPE)
## the texture set, 1K, else 2K. {format, uid, name, size, quality} or {code, error}.
static func choose_file(formats: Variant, kind := MODEL_TYPE) -> Dictionary:
	if not (formats is Array):
		return {"code": "shape", "error": "Fab's list of files isn't a list (its site may have changed)"}
	var format := MATERIAL_FORMAT if kind == MATERIAL_TYPE else FORMAT
	var files: Array = []
	for f: Variant in formats:
		if f is Dictionary and (f as Dictionary).get("assetFormatType") is Dictionary \
				and str(f["assetFormatType"].get("code", "")) == format and (f as Dictionary).get("files") is Array:
			files = f["files"]
	if kind == MATERIAL_TYPE:
		for quality: String in MATERIAL_SIZES:
			for x: Variant in files:
				var n := str((x as Dictionary).get("name", "")) if x is Dictionary else ""
				if n.to_lower().ends_with("_%s.zip" % quality) and uid_ok(str(x.get("uid", ""))):
					return {"format": format, "uid": str(x["uid"]), "name": n, "size": int(x.get("fileSize", 0)),
							"quality": quality}
		return {"code": "no_file", "error": "this surface has no texture set in 1K or 2K"}
	for quality: String in SIZES:
		for x: Variant in files:
			if not (x is Dictionary):
				continue
			var name := str((x as Dictionary).get("name", ""))
			if name.to_lower().ends_with("_%s.zip" % quality) and uid_ok(str(x.get("uid", ""))):
				return {"format": FORMAT, "uid": str(x["uid"]), "name": name, "size": int(x.get("fileSize", 0)),
						"quality": quality}
	return {"code": "no_file", "error": "this listing has no FBX zip in mid, low or high (the importer reads Fab's "
			+ "FBX zips)"}


## The asset's id in a file's name ("cabbage_tgrmacdpa_mid.zip" -> "tgrmacdpa"), or "".
static func asset_id_of(file_name: String) -> String:
	var parts := file_name.get_file().get_basename().split("_")
	if parts.size() < 3:
		return ""
	var id := parts[parts.size() - 2].to_lower()
	return id if RegEx.create_from_string("^[a-z0-9]{3,32}$").search(id) != null else ""


## The signed link in a file's download-info, or "".
static func download_url(data: Variant) -> String:
	if not (data is Dictionary) or not ((data as Dictionary).get("downloadInfo") is Array):
		return ""
	for d: Variant in data["downloadInfo"]:
		if d is Dictionary and str((d as Dictionary).get("downloadUrl", "")).begins_with("https://"):
			return str(d["downloadUrl"])
	return ""


func job_active() -> bool:
	return str(_job.get("state", "")) in JOB_STATES


## Starts importing a listing (a search result's uid): its files, the link, the zip, the import, in the
## background. {ok, state: started, uid, title}, {ok, state: already, object: {id, name}}, or an error. kind: the
## listing's (a surface: MATERIAL_TYPE, into the user materials; "": as the search gave it, else a 3D model).
func start_import(uid: String, title := "", kind := "") -> Dictionary:
	var gate := _gate()
	if not gate.is_empty():
		return gate
	if not uid_ok(uid):
		return _err("uid", "not a Fab listing's uid (fab_search gives them)")
	if job_active():
		return _err("busy", "%s is on its way already: fab_status says how far, fab_cancel stops it" % _job["title"])
	if kind == "":
		kind = str(_known.get(uid, {}).get("kind", MODEL_TYPE))
	var have := object_for_listing(uid) if kind == MODEL_TYPE else SurfaceImport.material_for_listing(uid)
	if not have.is_empty():
		return {"ok": true, "state": "already", "uid": uid, "object": {"id": have["id"], "name": have["name"]},
				"kind": kind}
	if title == "":
		title = str(_known.get(uid, {}).get("title", uid))
	_job = {"uid": uid, "title": title, "state": "files", "file": "", "quality": "", "bytes": 0, "total": -1,
			"error": "", "message": "", "object": {}, "cancel": false, "kind": kind}
	changed.emit()
	_run_job(_job)
	return {"ok": true, "state": "started", "uid": uid, "title": title}


## Stops the import under way (before the import itself, which takes a second). true if there was one.
func cancel() -> bool:
	if not job_active():
		return false
	_job["cancel"] = true
	if _job["state"] == "download" and gate.busy():
		transport.cancel()
	changed.emit()
	return true


func _run_job(job: Dictionary) -> void:
	var r: Dictionary = await _json(FILES % job["uid"], job)
	if _stopped(job, r):
		return
	var material := str(job.get("kind", MODEL_TYPE)) == MATERIAL_TYPE
	var pick := choose_file(r["data"], str(job.get("kind", MODEL_TYPE)))
	if pick.has("error"):
		_end(job, "failed", str(pick["code"]), str(pick["error"]))
		return
	job["file"] = pick["name"]
	job["quality"] = pick["quality"]
	job["total"] = pick["size"]
	var have := SurfaceImport.material_for_asset("megascans", asset_id_of(str(pick["name"]))) if material \
			else object_for_asset(asset_id_of(str(pick["name"])))
	if not have.is_empty():
		job["object"] = {"id": have["id"], "name": have["name"]}
		_end(job, "already")
		return
	if int(pick["size"]) > FabImport.MAX_ZIP_BYTES:
		_end(job, "failed", "too_big", "the zip is %d MB, over the importer's %d MB" % [int(pick["size"]) >> 20,
				FabImport.MAX_ZIP_BYTES >> 20])
		return
	_step(job, "link")
	r = await _json(LINK % [job["uid"], pick["format"], pick["uid"]], job)
	if _stopped(job, r):
		return
	var url := download_url(r["data"])
	if url == "":
		_end(job, "failed", "shape", "Fab's download-info has no https link (its site may have changed)")
		return
	_step(job, "download")
	var dir := root.path_join("tmp")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(str(job["uid"]) + ".zip")
	var got: Dictionary = await _get(url, "file", path, job)
	if not got.has("ok"):
		got = _answer(got, false)
	if _stopped(job, got):
		DirAccess.remove_absolute(path)
		return
	_step(job, "import")
	if material:
		await _import_material(job, path)
		return
	# On the main thread, behind a notice, as the Objects tab's Add (object_section.gd _add_fab()).
	var title := str(job["title"])
	_notify(TranslationServer.translate("Adding %s: a moment.") % title) # i18n
	await _tree().process_frame
	await _tree().process_frame
	if bool(job["cancel"]):
		DirAccess.remove_absolute(path)
		_end(job, "cancelled")
		return
	var out := FabImport.import_zip(path, false, str(job["uid"]))
	DirAccess.remove_absolute(path)
	if out.get("ok") != true:
		_end(job, "failed", "import", str(out.get("error", "the import failed")))
		return
	var m: Dictionary = out["manifest"]
	job["object"] = {"id": m["id"], "name": m["name"]}
	_end(job, "already" if out.get("already") == true else "done")
	var obj_name := str(m["name"])
	if job["state"] == "done":
		_notify(TranslationServer.translate("%s is in your objects.") % obj_name) # i18n
	ObjectCommands._sync_tab()


## A surface's texture set made a user material (surface_import.gd), on a worker thread: the maps are resized and
## combined pixel by pixel, a second or two, while the frames go on.
func _import_material(job: Dictionary, path: String) -> void:
	var uid := str(job["uid"])
	var w: Dictionary = await WorkerTask.run(_tree(), func() -> Variant:
		return SurfaceImport.import_megascans_zip(path, uid), 120.0)
	DirAccess.remove_absolute(path)
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
	job["object"] = {"id": e["id"], "name": e["name"]}
	_end(job, "already" if out.get("already") == true else "done")
	var mat_name := str(e["name"])
	if job["state"] == "done":
		_notify(TranslationServer.translate("%s is in your materials.") % mat_name) # i18n
	ObjectCommands._sync_tab()


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


## The import now or the last one: {uid, title, state, file, quality, bytes, total, error, message, object}, or {}.
## state: files, link, download, import (under way), then done, already, failed or cancelled.
func job_state() -> Dictionary:
	if _job.is_empty():
		return {}
	if _job["state"] == "download" and gate.busy():
		var p: Array = transport.progress()
		_job["bytes"] = int(p[0])
		if int(p[1]) > 0:
			_job["total"] = int(p[1])
	var out := _job.duplicate(true)
	out.erase("cancel")
	return out


## For fab_status and the panel: the licence, a back-off, the import.
func status() -> Dictionary:
	var out := {"eula_accepted": eula_accepted(), "eula_date": eula_date(), "where": WHERE,
			"backoff_s": ceili(backoff_left()), "busy": gate.busy(), "job": job_state()}
	if not eula_accepted():
		out["message"] = EULA_MESSAGE
	return out


# --- The commands --------------------------------------------------------------------------------------------------

## fab_status (read), fab_search (read), fab_import and fab_cancel (room). None accepts the licence.
static func register_commands(_host: Node = null) -> void:
	var R := DevCommands
	R.register("fab_status", func(_a: Dictionary, _ctx: DevCommands.Call) -> Variant:
		return ensure(_tree()).status(), {
		"description": "Fab (Quixel Megascans' free 3D models, imported into the object library): whether the user "
				+ "has accepted Fab's licence (nothing else works until they have, in Objects → Your objects → Fab "
				+ "in the headset's menu), a back-off Fab asked for, and the import under way or the last one.",
		"params": [], "assistant": "read", "title": "Fab: the licence and the import",
		"returns": "{eula_accepted, eula_date, where, message (until accepted), backoff_s, busy, job: {uid, title, "
				+ "state: files | link | download | import | done | already | failed | cancelled, file, quality, "
				+ "bytes, total, error, message, object: {id, name}}}"})
	R.register("fab_search", func(a: Dictionary, ctx: DevCommands.Call) -> Variant:
		var r: Dictionary = await ensure(_tree()).search(str(a["query"]), str(a["cursor"]))
		if not r["ok"]:
			return _fail(ctx, r)
		var out: Array = []
		for e: Dictionary in r["results"]:
			out.append({"uid": e["uid"], "title": e["title"], "category": e["category"], "tags": e["tags"],
					"importable": e["importable"], "in_library": e["in_library"]})
		return {"query": r["query"], "results": out, "count": out.size(), "next": r["next"], "cached": r["cached"]}, {
		"description": "Searches Fab for Quixel Megascans' free 3D models (24 a page; the app asks Fab, one request "
				+ "at a time, and keeps a page a day). Refused with error eula until the user has accepted Fab's "
				+ "licence in Objects → Your objects → Fab: ask them to. A title is the asset's name, in English.",
		"params": [{"name": "query", "type": "string", "required": true, "description": "Words in English (rock, "
				+ "chair, cabbage)."},
				{"name": "cursor", "type": "string", "default": "", "description": "The next page: the `next` of the "
				+ "page before. Empty: the first page."}],
		"assistant": "read", "title": "Search Fab's free Megascans",
		"returns": "{query, results: [{uid, title, category, tags, importable, in_library (the object's id, or "
				+ "empty)}], count, next (empty on the last page), cached}; refused: {error: eula | backoff | "
				+ "network | http | shape, message}"})
	R.register("fab_import", func(a: Dictionary, ctx: DevCommands.Call) -> Variant:
		var r: Dictionary = ensure(_tree()).start_import(str(a["uid"]))
		if not r["ok"]:
			return _fail(ctx, r)
		r.erase("ok")
		if r["state"] == "started":
			ctx.summary = "importing %s from Fab" % r["title"]
		return r, {
		"description": "Downloads a Fab listing (a fab_search result's uid: its FBX zip, mid size, else low, else "
				+ "high) and adds it to the object library, in the background: fab_status says how far it is and "
				+ "gives the object's id when done (then object_place). Not downloaded again when it is in the "
				+ "library. Refused with error eula until the user has accepted Fab's licence in Objects → Your "
				+ "objects → Fab: ask them to.",
		"params": [{"name": "uid", "type": "string", "required": true, "description": "The listing's uid "
				+ "(fab_search)."}],
		"level": "change", "assistant": "room", "title": "Import from Fab",
		"returns": "{state: started, uid, title} or {state: already, uid, object: {id, name}}; refused: {error: eula "
				+ "| busy | uid, message}"})
	R.register("fab_cancel", func(_a: Dictionary, ctx: DevCommands.Call) -> Variant:
		var store := ensure(_tree())
		var g: Dictionary = store._gate()
		if not g.is_empty():
			return _fail(ctx, g)
		var was: bool = store.cancel()
		if was:
			ctx.summary = "stopped the Fab download"
		return {"cancelled": was}, {
		"description": "Stops the Fab import under way (fab_import), and its temporary file goes. Refused with error "
				+ "eula until the user has accepted Fab's licence.",
		"params": [], "level": "change", "assistant": "room", "title": "Stop the Fab import",
		"returns": "{cancelled: true, or false when nothing was under way}"})


## An error for the assistant: {error: <code>, message} beside ok false (the dev link: "<code>: <message>").
static func _fail(ctx: DevCommands.Call, r: Dictionary) -> Variant:
	for k: String in r:
		if k != "ok":
			ctx.reply[k] = r[k]
	return ctx.fail("%s: %s" % [r["error"], r["message"]])
