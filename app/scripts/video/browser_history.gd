extends RefCounted

## The Browser source's current page when the browser has no DevTools port (one started by an earlier run of the
## player, or by anything else): from Chromium's history database. The database is locked while Chromium runs, so it
## is copied (History and History-journal) to a temporary folder, read there and the copy deleted at once. The reader
## is python3's sqlite3 module, else the sqlite3 command (SteamOS has both; reader() says which is used). Only the current page comes out: the most recent visit whose title matches the window's title, else the
## most recent visit (with a note). Never the browsing history.
##
##   read_now(window_title) -> {url, title, via: "history", reader, note?} or {error}   blocking: a worker thread

## Chromium's profile in the flatpak (the Frame's browser), else the usual places.
const PATHS: Array[String] = [".var/app/org.chromium.Chromium/config/chromium/Default/History",
		".config/chromium/Default/History"]
## Recent visits looked at for the window's title.
const RECENT := 40
const QUERY := "select u.url, u.title from visits v join urls u on u.id = v.url order by v.visit_time desc limit %d" \
		% RECENT
const PY := "import json, sqlite3, sys\n" \
		+ "c = sqlite3.connect('file:' + sys.argv[1] + '?mode=ro', uri=True)\n" \
		+ "print(json.dumps([{'url': r[0], 'title': r[1]} for r in c.execute(sys.argv[2])]))\n"

## Tests: another database, a reader forced ("sqlite3" or "python3").
static var path_override := ""
static var reader_override := ""


static func history_path() -> String:
	if path_override != "":
		return path_override
	var home := OS.get_environment("HOME")
	for p in PATHS:
		if FileAccess.file_exists(home.path_join(p)):
			return home.path_join(p)
	return home.path_join(PATHS[0])


static func _has(command: String) -> bool:
	var out: Array = []
	return OS.execute("sh", ["-c", "command -v %s" % command], out) == 0


## The reader this system has: "sqlite3", "python3" or "".
static func reader() -> String:
	if reader_override != "":
		return reader_override
	# python3 first: its sqlite3 module needs no particular command-line version (-json is sqlite 3.33+).
	if _has("python3"):
		return "python3"
	if _has("sqlite3"):
		return "sqlite3"
	return ""


static func read_now(window_title: String) -> Dictionary:
	var src := history_path()
	if not FileAccess.file_exists(src):
		return {"error": "no browser history at %s" % src}
	var how := reader()
	if how == "":
		return {"error": "neither sqlite3 nor python3 is here to read the browser's history"}
	var tmp := OS.get_user_data_dir().path_join("history_%d" % (Time.get_ticks_usec() % 1000000000))
	DirAccess.make_dir_recursive_absolute(tmp)
	var copy := tmp.path_join("History")
	var rows: Variant = null
	var err := DirAccess.copy_absolute(src, copy)
	if err == OK and FileAccess.file_exists(src + "-journal"):
		DirAccess.copy_absolute(src + "-journal", copy + "-journal")
	if err == OK:
		var out: Array = []
		var code: int
		if how == "sqlite3":
			code = OS.execute("sqlite3", ["-readonly", "-json", copy, QUERY], out)
		else:
			code = OS.execute("python3", ["-c", PY, copy, QUERY], out)
		if code == 0 and not out.is_empty():
			rows = JSON.parse_string(str(out[0]).strip_edges()) if str(out[0]).strip_edges() != "" else []
	# The copy goes at once, whatever happened.
	for f in DirAccess.get_files_at(tmp):
		DirAccess.remove_absolute(tmp.path_join(f))
	DirAccess.remove_absolute(tmp)
	if err != OK:
		return {"error": "could not copy the browser's history"}
	if not (rows is Array):
		return {"error": "could not read the browser's history with %s" % how}
	var r := pick(rows, window_title)
	if r.is_empty():
		return {"error": "no page in the browser's history"}
	r["via"] = "history"
	r["reader"] = how
	return r


## Two titles are the same page: equal, or one is the other with a suffix (" - YouTube", " - Chromium").
static func titles_match(a: String, b: String) -> bool:
	var x := a.strip_edges().to_lower()
	var y := b.strip_edges().to_lower()
	if x == "" or y == "":
		return false
	if x == y:
		return true
	var short := x if x.length() < y.length() else y
	var long := y if short == x else x
	return short.length() >= 4 and long.begins_with(short) and long.substr(short.length()).begins_with(" ")


## From the recent visits (newest first): {url, title, note?} of the window's page; only http(s) pages.
static func pick(rows: Array, window_title: String) -> Dictionary:
	var pages: Array = rows.filter(func(r: Variant) -> bool:
		return r is Dictionary and (str(r.get("url", "")).begins_with("https://")
				or str(r.get("url", "")).begins_with("http://")))
	if pages.is_empty():
		return {}
	for r: Dictionary in pages:
		if titles_match(str(r.get("title", "")), window_title):
			return {"url": str(r["url"]), "title": str(r.get("title", ""))}
	return {"url": str(pages[0]["url"]), "title": str(pages[0].get("title", "")),
			"note": "the most recent page in the browser's history; its title doesn't match the window's (%s)"
			% window_title}
