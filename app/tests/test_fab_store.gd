extends SceneTree

## Fab in the app (scripts/assistant/fab_store.gd, ui/fab_panel.gd; docs/features.md "Fab in the app") in the real
## main scene, against a fake transport that serves answers written here: made-up titles and ids in Fab's shapes.
## No Fab answer, thumbnail or zip is in the repository, and nothing here reaches the network; the zip is made here
## from a built-in box, as tests/test_fab_import.gd makes its own.
##
## The licence first (every command refuses with error eula, the tab shows Accept, no command accepts it, Withdraw
## works); the search and its pages by cursor; the day's cache and the thumbnails' (and its cap); one request at a
## time, a second between Fab's pages; the back-off on 429 and 5xx; the FBX zip and its size; the download, the
## import and the object in Your objects; an object in the library not downloaded again; Cancel; the commands and
## their errors.
## godot --headless --xr-mode off --path app --script res://tests/test_fab_store.gd

const FabStore := preload("res://scripts/assistant/fab_store.gd")
const ObjectLibrary := preload("res://scripts/assistant/object_library.gd")
const DevCommands := preload("res://scripts/dev/dev_commands.gd")
const CommandHost := preload("res://scripts/dev/command_host.gd")
const AssistantCommands := preload("res://scripts/assistant/assistant_commands.gd")
const W := preload("res://ui/pane_widgets.gd")
const I18n := preload("res://scripts/i18n.gd")

const ROOT := "user://test_fab_store"
const ASSET := "tstcrate1"
const ASSET_NAME := "Test Fab Crate"
## Made-up listing uids, in Fab's form.
const CRATE := "00000000-0000-4000-8000-00000000c001"
const BARREL := "00000000-0000-4000-8000-00000000c002"
const CRATE_AGAIN := "00000000-0000-4000-8000-00000000c003"
const SLOW := "00000000-0000-4000-8000-00000000c004"
const STOOL := "00000000-0000-4000-8000-00000000c005"
const MID_UID := "00000000-0000-4000-8000-0000000f1003"
const CDN := "https://cdn.test.invalid/"
const THUMBS := "https://thumbs.test.invalid/"
const NEXT := "cGFnZTI="

var _failures := 0
var _checks := 0
var main: Node
var store: Node
var fake: Fake
var commands: AssistantCommands
var allow_room := true
var _zip := PackedByteArray()


## Stands in for fab_http.gd: answers by URL, a frame later; a download is written to the file asked for, slowly
## when the URL says so (for Cancel). The log keeps each request's URL, headers and times.
class Fake extends RefCounted:
	var tree: SceneTree
	var routes := {}
	var log: Array = []
	var _cancel := false
	var _bytes := 0
	var _total := -1

	func fetch(url: String, headers: PackedStringArray, file := "") -> Dictionary:
		var e := {"url": url, "headers": headers, "file": file, "start": Time.get_ticks_msec()}
		log.append(e)
		_cancel = false
		_bytes = 0
		_total = -1
		await tree.process_frame
		var r: Variant = routes.get(url, {"code": 404, "body": "{}"})
		var out := {"code": int(r.get("code", 200)), "headers": r.get("headers", {}), "body": PackedByteArray(),
				"error": ""}
		var body: Variant = r.get("body", "")
		var bytes: PackedByteArray = body if body is PackedByteArray else str(body).to_utf8_buffer()
		if file == "":
			out["body"] = bytes
		else:
			_total = bytes.size()
			var f := FileAccess.open(file, FileAccess.WRITE)
			var steps := 120 if bool(r.get("slow", false)) else 1
			for i in steps:
				if _cancel:
					f.close()
					e["end"] = Time.get_ticks_msec()
					return {"code": 0, "headers": {}, "body": PackedByteArray(), "error": "cancelled"}
				var a := bytes.size() * i / steps
				var b := bytes.size() * (i + 1) / steps
				f.store_buffer(bytes.slice(a, b))
				_bytes = b
				if steps > 1:
					await tree.process_frame
			f.close()
		e["end"] = Time.get_ticks_msec()
		return out

	func progress() -> Array:
		return [_bytes, _total]

	func cancel() -> void:
		_cancel = true

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
	_cleanup()
	store = FabStore.ensure(self)
	await _frames(2)
	fake = Fake.new()
	fake.tree = self
	store.transport = fake
	store.root = ROOT
	store.clear_cache()
	_zip = _make_zip()
	_routes()
	commands = AssistantCommands.new()
	commands.allow_room = func() -> bool: return allow_room

	_test_rules()
	await _test_licence()
	await _test_search()
	await _test_backoff()
	await _test_import()
	await _test_cancel()
	await _test_commands()
	await _test_panel()
	await _test_withdraw()

	_cleanup()
	store.clear_cache()
	main.queue_free()
	await _frames(2)
	print("test_fab_store: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


# --- Fixtures, in Fab's shapes ---------------------------------------------------------------------------------------

func _result(uid: String, title: String, thumb: String, formats := ["fbx", "converted-files", "gltf"]) -> Dictionary:
	return {"uid": uid, "title": title, "listingType": "3d-model", "isFree": false,
			"category": {"name": "Test Props", "path": "test/props"},
			"tags": [{"name": "Test", "slug": "test"}, {"name": "Wood", "slug": "wood"}],
			"thumbnails": [{"images": [{"url": THUMBS + thumb + "-320.png", "width": 320, "height": 180, "size": 9000},
					{"url": THUMBS + thumb + ".png", "width": 144, "height": 81, "size": 2000}]}],
			"assetFormats": formats.map(func(c: String) -> Dictionary: return {"assetFormatType": {"code": c},
					"fileSizesRange": {"lower": 1000, "upper": 9000}}),
			"licenses": [{"name": "Personal"}], "startingPrice": {"price": 0.0}}


func _page(results: Array, next: Variant) -> String:
	return JSON.stringify({"aggregations": null, "cursors": {"next": next, "previous": null},
			"next": null if next == null else "https://www.fab.com/i/listings/search?cursor=x", "previous": null,
			"results": results})


func _formats(stem: String, sizes: Array, extra := []) -> Array:
	var files: Array = []
	var i := 0
	for s: String in sizes:
		i += 1
		files.append({"uid": "00000000-0000-4000-8000-0000000f100%d" % i if s != "mid" else MID_UID,
				"name": "%s_%s.zip" % [stem, s], "fileSize": _zip.size() if s != "raw" else 300 << 20})
	var out: Array = [{"assetFormatType": {"code": "fbx", "extensions": ["fbx"]}, "files": files}]
	out.append_array(extra)
	return out


func _routes() -> void:
	var r := fake.routes
	r[FabStore.search_url("crate")] = {"body": _page([_result(CRATE, "Test Crate", "crate"),
			_result(BARREL, "Test Barrel", "barrel"), {"title": "No uid here"}, {"uid": "bad uid!", "title": "X"}],
			NEXT)}
	r[FabStore.search_url("crate", NEXT)] = {"body": _page([_result(CRATE_AGAIN, "Test Crate Again", "again"),
			_result(STOOL, "Test Stool", "stool", ["gltf"])], null)}
	r[FabStore.search_url("slow")] = {"body": _page([_result(SLOW, "Test Slow", "slow")], null)}
	r[FabStore.search_url("busy")] = {"code": 429, "headers": {"retry-after": "1"}, "body": "{}"}
	r[FabStore.search_url("broken")] = {"code": 503, "body": "{}"}
	r[FabStore.search_url("odd")] = {"body": "{\"items\": []}"}
	for t: String in ["crate", "barrel", "again", "slow", "stool"]:
		r[THUMBS + t + ".png"] = {"body": _png(Color(0.4, 0.3, 0.2), Vector2i(144, 81))}
	var gltf := {"assetFormatType": {"code": "gltf", "extensions": ["gltf"]},
			"files": [{"uid": "00000000-0000-4000-8000-0000000f2001", "name": "test_crate_%s_ue_mid.zip" % ASSET,
			"fileSize": 1000}]}
	r[FabStore.FILES % CRATE] = {"body": JSON.stringify(_formats("test_crate_" + ASSET, ["raw", "high", "mid", "low"],
			[gltf]))}
	r[FabStore.LINK % [CRATE, "fbx", MID_UID]] = {"body": JSON.stringify({"downloadInfo": [{"downloadUrl": CDN
			+ "crate_mid.zip?sig=test", "expires": "2026-11-06T21:00:00.000Z", "type": "binary",
			"assetFormat": "asset-format/3d-exchange/fbx"}]})}
	r[CDN + "crate_mid.zip?sig=test"] = {"body": _zip}
	# Another listing of the same asset (its files name the same id): found in the library before a download.
	r[FabStore.FILES % CRATE_AGAIN] = {"body": JSON.stringify(_formats("test_crate_" + ASSET, ["mid"]))}
	r[FabStore.FILES % SLOW] = {"body": JSON.stringify(_formats("test_slow_tstslow01", ["low"]))}
	r[FabStore.LINK % [SLOW, "fbx", "00000000-0000-4000-8000-0000000f1001"]] = {"body": JSON.stringify(
			{"downloadInfo": [{"downloadUrl": CDN + "slow.zip", "type": "binary"}]})}
	r[CDN + "slow.zip"] = {"body": _zip, "slow": true}
	r[FabStore.FILES % STOOL] = {"body": JSON.stringify([{"assetFormatType": {"code": "gltf"}, "files": [{"uid":
			"00000000-0000-4000-8000-0000000f3001", "name": "test_stool_tststool1_ue_mid.zip", "fileSize": 1000}]}])}


# --- The rules: the file, the size, the asset's id, the back-off's length --------------------------------------------

func _test_rules() -> void:
	var all := _formats("test_crate_" + ASSET, ["raw", "high", "mid", "low"])
	var pick := FabStore.choose_file(all)
	_check("the FBX zip, mid (%s)" % [pick], pick.get("format") == "fbx" and pick.get("quality") == "mid"
			and pick.get("uid") == MID_UID)
	pick = FabStore.choose_file(_formats("x_abc123_", ["raw", "high", "low"]))
	_check("no mid: low (%s)" % pick.get("quality"), pick.get("quality") == "low")
	pick = FabStore.choose_file(_formats("x_abc123", ["raw", "high"]))
	_check("only high and raw: high, never raw (%s)" % pick.get("quality"), pick.get("quality") == "high")
	pick = FabStore.choose_file(_formats("x_abc123", ["raw"]))
	_check("only raw: none (%s)" % pick.get("code"), pick.get("code") == "no_file")
	pick = FabStore.choose_file([{"assetFormatType": {"code": "gltf"}, "files": [{"uid": "a-1", "name": "x_ue_mid.zip"}]}])
	_check("gltf only: none (the importer reads Fab's FBX zips)", pick.get("code") == "no_file")
	_check("not a list: Fab's site changed", FabStore.choose_file({"x": 1}).get("code") == "shape")
	_check("the asset's id from a file name", FabStore.asset_id_of("old_wooden_chair_tbdpec3r_mid.zip") == "tbdpec3r"
			and FabStore.asset_id_of("odd.zip") == "")
	_check("back-off: Retry-After, else 2 s doubled, at most 300", FabStore.backoff_seconds(0, "7") == 7.0
			and FabStore.backoff_seconds(0, "") == 2.0 and FabStore.backoff_seconds(2, "") == 8.0
			and FabStore.backoff_seconds(12, "") == 300.0 and FabStore.backoff_seconds(1, "Wed, 21 Oct") == 4.0)
	_check("the link: https only", FabStore.download_url({"downloadInfo": [{"downloadUrl": "http://x/y.zip"}]}) == ""
			and FabStore.download_url({"downloadInfo": [{"downloadUrl": "https://x/y.zip"}]}) == "https://x/y.zip")
	var ua := FabStore.user_agent()
	_check("the User-Agent is the app's own name and version (%s)" % ua, ua.begins_with("FrameVRVideo/")
			and ua.contains("github.com") and not ua.contains("Mozilla"))
	_check("the search: Megascans, free, 3D models", FabStore.search_url("a b").contains("seller=Quixel%20Megascans")
			and FabStore.search_url("a b").contains("is_free=1") and FabStore.search_url("a b").contains("q=a%20b"))


# --- The licence first -----------------------------------------------------------------------------------------------

func _test_licence() -> void:
	_check("not accepted at first", not store.eula_accepted())
	var r: Dictionary = await store.search("crate")
	_check("search refused: eula (%s)" % r.get("error"), r.get("ok") == false and r.get("error") == "eula")
	_check("start_import refused: eula", store.start_import(CRATE).get("error") == "eula")
	_check("no thumbnail either", (await store.thumbnail(THUMBS + "crate.png")) == null)
	_check("nothing asked of Fab", fake.log.is_empty())
	for c: String in ["fab_search", "fab_import", "fab_cancel"]:
		var args := {"query": "crate"} if c == "fab_search" else ({"uid": CRATE} if c == "fab_import" else {})
		var d: Dictionary = await DevCommands.execute(c, args, false)
		_check("%s (dev link) refused: %s" % [c, d.get("error")], not d["ok"] and str(d.get("error")).begins_with("eula:"))
		var a: Dictionary = await commands.run(c, args)
		_check("%s (assistant): error eula, and where to send the user (%s)" % [c, a], a.get("ok") == false
				and a.get("error") == "eula" and str(a.get("message", "")).contains("Objects → Your objects → Fab"))
		_check("%s's description says so" % c, str(DevCommands.get_spec(c).get("description", "")).contains("eula")
				or str(DevCommands.get_spec(c).get("description", "")).contains("licence"))
	var s: Dictionary = await commands.run("fab_status", {})
	_check("fab_status: not accepted, and the message (%s)" % [s.get("result")], s.get("ok") == true
			and s["result"]["eula_accepted"] == false and str(s["result"].get("message", "")).contains("Your objects"))
	_check("no request yet", fake.log.is_empty())
	# No command can accept it: none is about the licence but these, none takes such a thing, no setting reaches it.
	for c: String in DevCommands.command_names():
		var spec := DevCommands.get_spec(c)
		var words := c.to_lower()
		for p: Dictionary in spec.get("params", []):
			words += " " + str(p["name"]).to_lower()
		_check("%s: nothing that accepts a licence" % c, not words.contains("eula") and not words.contains("accept")
				and not words.contains("licence"))
	_check("no setting for it", not DevCommands.setting_names().any(func(n: String) -> bool:
			return n.contains("fab") or n.contains("eula")))
	_check("still not accepted after every command", not store.eula_accepted())

	# The tab: the summary, Read Fab's licence and Accept; no search until then.
	var panel := await _panel()
	_check("the tab shows the licence and Accept", panel._licence.is_visible_in_tree() and not panel._accepted.visible
			and _button(panel, "Accept") != null and _button(panel, "Read Fab's licence") != null)
	_button(panel, "Accept").emit_signal("pressed")
	await _frames(1)
	_check("Accept: kept with the date (%s)" % main.settings.get_value("fab", "eula_accepted", ""),
			store.eula_accepted() and str(main.settings.get_value("fab", "eula_accepted", "")) ==
			Time.get_date_string_from_system())
	_check("then the search shows, and the day it was accepted", panel._accepted.visible and not panel._licence.visible
			and panel._accepted_label.text.contains(store.eula_date()))


# --- Search, pages, caches, spacing ---------------------------------------------------------------------------------

func _test_search() -> void:
	var r: Dictionary = await store.search("Crate")
	var res: Array = r.get("results", [])
	_check("search: two results, the odd ones left out (%s)" % [res.map(func(e: Dictionary) -> String: return e["title"])],
			r.get("ok") == true and res.size() == 2 and res[0]["uid"] == CRATE and res[0]["title"] == "Test Crate")
	_check("search: category, tags, the smallest thumbnail, importable", res.size() == 2 and res[0]["category"] ==
			"Test Props" and res[0]["tags"] == ["Test", "Wood"] and res[0]["thumb"] == THUMBS + "crate.png"
			and res[0]["importable"] == true)
	_check("search: the next page's cursor", r.get("next") == NEXT and r.get("cached") == false)
	var sent: Dictionary = fake.log[-1]
	_check("the request: the app's User-Agent, JSON", Array(sent["headers"]).has("User-Agent: " + FabStore.user_agent())
			and Array(sent["headers"]).has("Accept: application/json"))
	var p2: Dictionary = await store.search("crate", NEXT)
	_check("the next page by its cursor (%s)" % p2.get("error", ""), p2.get("ok") == true
			and (p2["results"] as Array).size() == 2 and p2["next"] == "")
	_check("a gltf-only listing isn't importable", (p2["results"] as Array).any(func(e: Dictionary) -> bool:
			return e["uid"] == STOOL and e["importable"] == false))
	# Spacing: one request at a time, a second between Fab's pages.
	var gaps := _gaps()
	_check("a second between Fab's pages (%s ms)" % [gaps], not gaps.is_empty() and gaps.all(func(g: int) -> bool:
			return g >= 990))
	var before: int = store.requests
	var again: Dictionary = await store.search("crate")
	_check("the same search again: kept, nothing asked", again.get("cached") == true and store.requests == before
			and (again["results"] as Array).size() == 2)
	# A day later it is asked again.
	var path := ROOT.path_join("search").path_join(FabStore.search_url("crate").md5_text() + ".json")
	var kept: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	kept["saved"] = Time.get_unix_time_from_system() - 2 * 86400
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(kept))
	f.close()
	again = await store.search("crate")
	_check("a day-old search is asked again", again.get("cached") == false and store.requests == before + 1)
	# Two at once: one after the other.
	var n := fake.log.size()
	store.clear_cache()
	var first: Array = []
	var a := func() -> void: first.append(await store.search("crate"))
	a.call()
	var b: Dictionary = await store.search("crate", NEXT)
	await _until(func() -> bool: return not first.is_empty())
	var l: Array = fake.log.slice(n)
	_check("two searches at once: one at a time (%d)" % l.size(), l.size() == 2 and int(l[1]["start"]) >= int(l[0]["end"])
			and b.get("ok") == true)
	_check("a form Fab's site no longer gives: an error, no crash", (await store.search("odd")).get("error") == "shape")
	_check("no words: refused", (await store.search("  ")).get("error") == "query")

	# Thumbnails: fetched once, then from the cache; within its cap, the oldest go.
	before = store.requests
	var img: Image = await store.thumbnail(THUMBS + "crate.png")
	_check("a thumbnail (%s)" % (img.get_size() if img != null else "none"), img != null and img.get_width() == 144
			and store.requests == before + 1)
	img = await store.thumbnail(THUMBS + "crate.png")
	_check("again: from the cache", img != null and store.requests == before + 1)
	var one: int = store._size(store._thumb_path(THUMBS + "crate.png"))
	store.thumb_cache_bytes = one * 3 / 2
	await store.thumbnail(THUMBS + "barrel.png")
	_check("over the cap: the oldest go, to within it (%s)" % [store.cache_info()], int(store.cache_info()["thumbs"]) == 1)
	store.thumb_cache_bytes = FabStore.THUMB_CACHE_BYTES
	store.clear_cache()
	_check("Clear Fab's cache: nothing kept (%d before)" % one, store.cache_info()["searches"] == 0
			and store.cache_info()["thumbs"] == 0)


## The gaps between each of Fab's pages and the request before it, in ms.
func _gaps() -> Array:
	var out: Array = []
	for i in range(1, fake.log.size()):
		if str(fake.log[i]["url"]).begins_with(FabStore.SITE) and fake.log[i - 1].has("end"):
			out.append(int(fake.log[i]["start"]) - int(fake.log[i - 1]["end"]))
	return out


# --- Back-off ---------------------------------------------------------------------------------------------------------

func _test_backoff() -> void:
	var r: Dictionary = await store.search("busy")
	_check("429: back off for Retry-After (%s)" % [r], r.get("error") == "backoff" and int(r.get("wait", 0)) == 1
			and int(r.get("http", 0)) == 429 and store.backoff_left() > 0.0)
	var before: int = store.requests
	r = await store.search("crate")
	_check("while backing off nothing is asked", r.get("error") == "backoff" and store.requests == before)
	var panel := await _panel()
	panel.sync()
	_check("the tab says so (%s)" % panel._status.text, panel._status.visible and panel._status.text.contains("busy"))
	await _until(func() -> bool: return store.backoff_left() <= 0.0, 3.0)
	r = await store.search("crate")
	_check("after it, asked again (%s)" % r.get("error", ""), r.get("ok") == true and store.requests == before + 1)
	r = await store.search("broken")
	_check("503 without Retry-After: 2 s, the count started again after the success (%s)" % [r],
			r.get("error") == "backoff" and int(r.get("wait", 0)) == 2)
	await _until(func() -> bool: return store.backoff_left() <= 0.0, 4.0)


# --- Import -----------------------------------------------------------------------------------------------------------

func _test_import() -> void:
	await store.search("crate")
	var n := fake.log.size()
	var r: Dictionary = store.start_import(CRATE)
	_check("import: started, with its title (%s)" % [r], r.get("state") == "started" and r.get("title") == "Test Crate")
	var busy: Dictionary = store.start_import(BARREL)
	_check("one import at a time (%s)" % busy.get("error"), busy.get("error") == "busy")
	await _until(func() -> bool: return not store.job_active(), 20.0)
	var job: Dictionary = store.job_state()
	_check("import: done (%s %s)" % [job.get("state"), job.get("message")], job.get("state") == "done"
			and job.get("quality") == "mid" and job.get("file") == "test_crate_%s_mid.zip" % ASSET)
	var urls: Array = fake.log.slice(n).map(func(e: Dictionary) -> String: return e["url"])
	_check("its files, its link, the zip, in turn (%s)" % [urls], urls == [FabStore.FILES % CRATE,
			FabStore.LINK % [CRATE, "fbx", MID_UID], CDN + "crate_mid.zip?sig=test"])
	_check("the download with the app's User-Agent too", Array(fake.log[-1]["headers"]).has("User-Agent: "
			+ FabStore.user_agent()))
	var m := ObjectLibrary.get_object(str(job["object"].get("id", "")))
	_check("in the library: a user object, the asset's id and the listing's (%s, %s)" % [m.get("fab"), m.get("fab_listing")],
			m.get("source") == "user" and m.get("fab") == ASSET and m.get("fab_listing") == CRATE
			and m.get("name") == ASSET_NAME)
	_check("ready to place and to throw: its model and its collision", not ObjectLibrary.glb(str(m.get("id", ""))).is_empty()
			and not ObjectLibrary.collision(str(m.get("id", ""))).is_empty())
	_check("the zip is gone", DirAccess.get_files_at(ROOT.path_join("tmp")).is_empty())
	var section: Node = main.ui.ui.objects.section
	await _until(func() -> bool: return section._tiles.has(str(m.get("id", ""))), 10.0)
	_check("it shows in Your objects", section._tiles.has(str(m.get("id", ""))))
	# Already in the library: by the listing, at once; by the asset's id, before a download.
	n = fake.log.size()
	r = store.start_import(CRATE)
	_check("the same listing again: already, nothing asked (%s)" % [r], r.get("state") == "already"
			and r["object"]["id"] == m.get("id") and fake.log.size() == n)
	r = store.start_import(CRATE_AGAIN)
	await _until(func() -> bool: return not store.job_active(), 10.0)
	urls = fake.log.slice(n).map(func(e: Dictionary) -> String: return e["url"])
	_check("another listing of the same asset: already, no download (%s)" % [urls], store.job_state()["state"] ==
			"already" and urls == [FabStore.FILES % CRATE_AGAIN] and store.job_state()["object"]["id"] == m.get("id"))
	var p: Dictionary = await store.search("crate")
	_check("a search marks it in the library", (p["results"] as Array)[0]["in_library"] == m.get("id"))
	r = store.start_import(STOOL)
	await _until(func() -> bool: return not store.job_active(), 10.0)
	_check("a listing with no FBX zip: said, nothing downloaded (%s)" % store.job_state()["error"],
			store.job_state()["state"] == "failed" and store.job_state()["error"] == "no_file")


func _test_cancel() -> void:
	await store.search("slow")
	var r: Dictionary = store.start_import(SLOW)
	_check("a slow one started", r.get("state") == "started")
	await _until(_downloading, 10.0)
	var j: Dictionary = store.job_state()
	_check("its progress (%d of %d)" % [j["bytes"], j["total"]], int(j["bytes"]) > 0 and int(j["total"]) == _zip.size())
	_check("Cancel", store.cancel())
	await _until(func() -> bool: return not store.job_active(), 5.0)
	_check("cancelled: no object, no file (%s)" % store.job_state()["state"], store.job_state()["state"] == "cancelled"
			and FabStore.object_for_listing(SLOW).is_empty()
			and DirAccess.get_files_at(ROOT.path_join("tmp")).is_empty())
	_check("nothing to cancel now", not store.cancel())


# --- The commands -----------------------------------------------------------------------------------------------------

func _test_commands() -> void:
	for c: String in ["fab_status", "fab_search", "fab_import", "fab_cancel"]:
		var spec := DevCommands.get_spec(c)
		_check("%s registered for the assistant (%s)" % [c, spec.get("assistant")], spec.get("assistant") ==
				("read" if c in ["fab_status", "fab_search"] else "room"))
		for p: Dictionary in spec.get("params", []):
			_check("%s: %s described" % [c, p["name"]], str(p.get("description", "")) != "")
	var a: Dictionary = await commands.run("fab_search", {"query": "crate"})
	var res: Array = a.get("result", {}).get("results", [])
	_check("fab_search: results with uid, title, in_library, no URLs (%s)" % [a.get("error", "")], a.get("ok") == true
			and res.size() == 2 and res[0].has("uid") and res[0].has("in_library") and not res[0].has("thumb")
			and a["result"]["next"] == NEXT)
	a = await commands.run("fab_search", {"query": "crate", "cursor": NEXT})
	_check("fab_search: the next page by cursor", a.get("ok") == true and a["result"]["next"] == "")
	a = await commands.run("fab_import", {"uid": "not a uid"})
	_check("fab_import: a bad uid (%s)" % a.get("error"), a.get("ok") == false and a.get("error") == "uid")
	a = await commands.run("fab_import", {"uid": CRATE})
	_check("fab_import: in the library already (%s)" % [a.get("result")], a.get("ok") == true
			and a["result"]["state"] == "already")
	allow_room = false
	a = await commands.run("fab_import", {"uid": SLOW})
	_check("fab_import behind the room switch", a.get("ok") == false and a.get("refused") == true)
	allow_room = true
	a = await commands.run("fab_import", {"uid": SLOW})
	_check("fab_import: started (%s)" % [a.get("result")], a.get("ok") == true and a["result"]["state"] == "started")
	var b: Dictionary = await commands.run("fab_import", {"uid": BARREL})
	_check("fab_import while one is under way: busy (%s)" % b.get("message"), b.get("error") == "busy")
	await _until(func() -> bool: return store.job_state().get("state") == "download", 10.0)
	var s: Dictionary = await commands.run("fab_status", {})
	_check("fab_status: the job (%s)" % [s.get("result", {}).get("job")], s.get("ok") == true
			and s["result"]["eula_accepted"] == true and s["result"]["job"]["uid"] == SLOW
			and s["result"]["job"]["state"] == "download")
	var c: Dictionary = await commands.run("fab_cancel", {})
	_check("fab_cancel", c.get("ok") == true and c["result"]["cancelled"] == true)
	await _until(func() -> bool: return not store.job_active(), 5.0)
	_check("fab_status: cancelled", (await commands.run("fab_status", {}))["result"]["job"]["state"] == "cancelled")


# --- The tab ----------------------------------------------------------------------------------------------------------

func _test_panel() -> void:
	var panel := await _panel()
	store.clear_cache()
	await panel._search("crate")
	_check("the tab: a tile for each result (%d)" % panel._grid.get_child_count(), panel._grid.get_child_count() == 2
			and panel._more.is_visible_in_tree())
	await _until(func() -> bool: return _all_art(panel), 10.0)
	_check("their thumbnails", _all_art(panel))
	var tile: Button = panel._grid.get_child(0)
	_check("a tile's title is content", tile.has_meta("content") and (tile.get_node("Title") as Label).text == "Test Crate")
	await _frames(2)
	_check("the tiles fill the card, square (%.0f x %.0f)" % [tile.size.x, tile.size.y],
			absf(tile.size.y - tile.size.x - panel.CARD_TEXT) < 1.0 and tile.size.x >= panel.TILE_MIN)
	_check("More", panel._more.is_visible_in_tree())
	await panel._fetch(panel._next)
	_check("More: the next page added (%d)" % panel._grid.get_child_count(), panel._grid.get_child_count() == 4
			and not panel._more.is_visible_in_tree())
	tile.emit_signal("pressed")
	_check("a pick in the library already: said, Import off (%s)" % panel._progress.text, panel._picked_label.text
			.begins_with("Test Crate") and panel._import.disabled and panel._progress.visible)
	var barrel: Button = panel._grid.get_child(1)
	barrel.emit_signal("pressed")
	_check("a pick: Import", not panel._import.disabled and panel._picked_label.text.begins_with("Test Barrel"))
	# The Your objects card fits its tab with the results in it, in English, Chinese and the pseudo-locale.
	var pui: Node = main.ui.ui
	var wide: Array = []
	for code: String in ["en", "zh_CN", I18n.PSEUDO]:
		I18n.set_language(code)
		await _frames(3)
		var width: float = pui.tabs[pui.Tab.OBJECTS].size.x
		for card: Control in pui.cards(pui.Tab.OBJECTS):
			if card.is_visible_in_tree() and card.get_combined_minimum_size().x > width + 0.5:
				wide.append("%s %s %.0f of %.0f" % [code, W.card_section(card), card.get_combined_minimum_size().x,
						width])
	I18n.set_language("en")
	await _frames(2)
	_check("every card fits its tab with results, in each language (%s)" % " | ".join(wide), wide.is_empty()
			and not pui.cards(pui.Tab.OBJECTS).is_empty())
	# Import from the tab, then Cancel from the tab.
	store.clear_cache()
	await panel._search("slow")
	(panel._grid.get_child(0) as Button).emit_signal("pressed")
	panel._import.emit_signal("pressed")
	await _until(_downloading, 10.0)
	panel.sync()
	_check("the tab: its progress and Cancel (%s)" % panel._progress.text, panel._progress.text.contains("Test Slow")
			and panel._cancel.visible and not panel._import.visible)
	panel._cancel.emit_signal("pressed")
	await _until(func() -> bool: return not store.job_active(), 5.0)
	panel.sync()
	_check("the tab: cancelled (%s)" % panel._progress.text, panel._progress.text == "Cancelled."
			and panel._import.visible)
	# The search form: the keyboard's, in the tab's place.
	panel._ask_search()
	_check("Search Fab: the keyboard's form", panel._form.is_visible_in_tree())
	panel._hide_form()
	_check("and back", not panel._form.visible and panel._accepted.is_visible_in_tree())


func _test_withdraw() -> void:
	var panel := await _panel()
	_button(panel, "Withdraw").emit_signal("pressed")
	await _frames(1)
	_check("Withdraw: not accepted, the setting gone", not store.eula_accepted()
			and not main.settings.has_value("fab", "eula_accepted"))
	_check("the tab: the licence and Accept again, the results gone", panel._licence.visible and not panel._accepted.visible
			and panel._grid.get_child_count() == 0)
	var a: Dictionary = await commands.run("fab_search", {"query": "crate"})
	_check("the commands refuse again", a.get("error") == "eula")


# --- Helpers ------------------------------------------------------------------------------------------------------------

func _panel() -> Node:
	var layer: Node = main.ui
	layer.show_panel()
	layer.ui.show_tab(layer.ui.Tab.OBJECTS)
	if layer.ui.has_method("show_section"):
		layer.ui.show_section("Your objects")
	await _frames(3)
	return layer.ui.objects.section.fab


func _all_art(panel: Node) -> bool:
	for t in panel._grid.get_children():
		if not t.has_node("Art"):
			return false
	return true


func _downloading() -> bool:
	return store.job_state().get("state") == "download" and int(store.job_state()["bytes"]) > 0


func _button(n: Node, text: String) -> Button:
	for b in n.find_children("*", "Button", true, false):
		if (b as Button).text == text and (b as Button).is_visible_in_tree():
			return b
	return null


## A zip as Fab lays one out (as tests/test_fab_import.gd): the asset's .json, a model, its colour map.
func _make_zip() -> PackedByteArray:
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.3, 0.2, 0.25)
	box.mesh = mesh
	var r := Node3D.new()
	r.add_child(box)
	var glb := ObjectLibrary.to_glb(r)
	r.free()
	DirAccess.make_dir_recursive_absolute(ROOT)
	var path := ROOT.path_join("made.zip")
	var z := ZIPPacker.new()
	z.open(path)
	_put(z, "%s.json" % ASSET, JSON.stringify({"id": ASSET, "name": ASSET_NAME, "tags": ["crate", "test"],
			"meta": [{"key": "small3dasset", "value": "true"}]}).to_utf8_buffer())
	_put(z, "Test_Fab_Crate_%s_Mid.glb" % ASSET, glb)
	_put(z, "Test_Fab_Crate_%s_2K_BaseColor.png" % ASSET, _png(Color(0.7, 0.6, 0.5), Vector2i(32, 32)))
	z.close()
	var bytes := FileAccess.get_file_as_bytes(path)
	DirAccess.remove_absolute(path)
	return bytes


func _put(z: ZIPPacker, name: String, bytes: PackedByteArray) -> void:
	z.start_file(name)
	z.write_file(bytes)
	z.close_file()


func _png(c: Color, size: Vector2i) -> PackedByteArray:
	var img := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGB8)
	img.fill(c)
	return img.save_png_to_buffer()


func _cleanup() -> void:
	for m: Dictionary in ObjectLibrary.list("", "user"):
		if str(m.get("fab", "")) in [ASSET, "tstslow01"]:
			ObjectLibrary.delete(str(m["id"]))
			ObjectLibrary.purge(str(m["id"]))


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
