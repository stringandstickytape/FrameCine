extends RefCounted

## Lists a folder for the file browser and the playlist: local paths with DirAccess, smb://host with
## MediaBrowser.list_shares(), smb://host/share/... with MediaBrowser.list_dir(). Blocking: call it on a
## WorkerThreadPool task (the file browser does). Without the engine's MediaBrowser, a simulated one answers
## (fake_media_browser.gd) and the result says so.
##
## Result: {"entries": [{"name", "is_dir", "size"}], "error": "", "simulated": bool}, entries in natural order,
## folders first.

const NetworkHosts := preload("res://scripts/net/network_hosts.gd")
const FakeMediaBrowser := preload("res://scripts/net/fake_media_browser.gd")


static func has_media_browser() -> bool:
	return ClassDB.class_exists("MediaBrowser")


static func list(path: String) -> Dictionary:
	if NetworkHosts.is_smb(path):
		return _list_smb(path)
	return _list_local(path)


static func _list_local(path: String) -> Dictionary:
	var dir := DirAccess.open(path)
	if dir == null:
		return {"entries": [], "error": "Can't open %s: %s" % [path, error_string(DirAccess.get_open_error())],
				"simulated": false}
	dir.include_hidden = false
	var entries: Array = []
	for d in dir.get_directories():
		entries.append({"name": d, "is_dir": true, "size": 0})
	for f in dir.get_files():
		var size := 0
		var fa := FileAccess.open(path.path_join(f), FileAccess.READ)
		if fa != null:
			size = fa.get_length()
		entries.append({"name": f, "is_dir": false, "size": size})
	return {"entries": _sorted(entries), "error": "", "simulated": false}


## One browser per host, kept: a MediaBrowser keeps its connection open, so later listings take milliseconds instead
## of a new login. Listings run on worker threads; each host's Mutex keeps two of them off the same browser.
## host (lower case) -> [browser, Mutex]
static var _browsers := {}
static var _browsers_lock := Mutex.new()


static func _browser_for(host: String) -> Array:
	_browsers_lock.lock()
	var key := host.to_lower()
	if not _browsers.has(key):
		var browser: Object = FakeMediaBrowser.new() if not has_media_browser() else ClassDB.instantiate("MediaBrowser")
		_browsers[key] = [browser, Mutex.new()]
	var entry: Array = _browsers[key]
	_browsers_lock.unlock()
	return entry


## After a host's credentials change (or the host is deleted): drop its browser, so the next listing logs in afresh
## (an open connection keeps its old login), and with `clear`, remove its credentials from the engine's registry.
static func forget_host(host: String, clear := false) -> void:
	if host == "":
		return
	_browsers_lock.lock()
	var entry: Array = _browsers.get(host.to_lower(), [])
	_browsers.erase(host.to_lower())
	_browsers_lock.unlock()
	if not entry.is_empty():
		var browser: Object = entry[0]
		var lock: Mutex = entry[1]
		# A listing still running keeps its reference; it finishes on the old connection and the browser goes with it.
		if lock.try_lock():
			# Closes this browser's own kept connection (no arguments).
			if browser.has_method("disconnect_host"):
				browser.call("disconnect_host")
			lock.unlock()
	if clear and has_media_browser():
		# The registry is shared and keyed by host; an empty user and password remove the entry.
		var tmp: Object = ClassDB.instantiate("MediaBrowser")
		tmp.call("set_smb_credentials", host, "", "", "")


static func _list_smb(path: String) -> Dictionary:
	var simulated := not has_media_browser()
	var rest := path.trim_prefix("smb://").trim_suffix("/")
	var entry := _browser_for(NetworkHosts.host_of(path))
	var browser: Object = entry[0]
	var lock: Mutex = entry[1]
	lock.lock()
	NetworkHosts.apply_credentials(browser, path)
	var raw: Variant
	if not rest.contains("/"):
		raw = browser.call("list_shares", rest)
	else:
		raw = browser.call("list_dir", path)
	var last_error := str(browser.call("get_last_error")) if browser.has_method("get_last_error") else ""
	lock.unlock()
	var entries: Array = []
	if raw is Array:
		for e: Variant in raw:
			if e is Dictionary:
				entries.append({"name": str(e.get("name", "")), "is_dir": bool(e.get("is_dir", false)),
						"size": int(e.get("size", 0))})
			elif e is String:
				entries.append({"name": e, "is_dir": true, "size": 0})
	# Empty on success, else a user-ready sentence (never the password).
	return {"entries": _sorted(entries), "error": last_error, "simulated": simulated}


static func _sorted(entries: Array) -> Array:
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["is_dir"] != b["is_dir"]:
			return a["is_dir"]
		return str(a["name"]).naturalnocasecmp_to(b["name"]) < 0)
	return entries
