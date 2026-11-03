extends RefCounted

## The Files tab's own actions as commands (docs/dev/assistant-coverage/files.md): the saved network hosts and their
## logins, favourites, the play queue and its switches, search, the Library's view, saved web pages, the Files tab on
## the pane, "In corner" and the Browser place's "Stop showing". Registered with the built-ins by command_host.gd. Each
## runs the code the tab's buttons run (files_tab.gd, NetworkHosts, the queue and favourites features), and the tab
## follows when it shows the place a command changed.
##
## Logins go in and never out: hosts says whether a host has a login saved, never what it is, and no reply, summary or
## print line holds a user name or a password. host_remove is the host form's Delete host: no question, as in the form,
## and undo puts the host back with its login.
##
## A call from a paired assistant (ctx.client set) gets the assistant's rules: a host or a media server on this network
## only, and open_in_corner only what `open` would open (assistant_commands.gd, open_refusal).

const DevCommands := preload("res://scripts/dev/dev_commands.gd")
const NetworkHosts := preload("res://scripts/net/network_hosts.gd")
const WebPages := preload("res://scripts/net/web_pages.gd")
const MediaServers := preload("res://scripts/net/media_servers.gd")
const LibraryIndex := preload("res://scripts/library/library_index.gd")
const FavouritesSearch := preload("res://scripts/play/favourites_search.gd")
const VideoSourceFactory := preload("res://scripts/video/video_source_factory.gd")
const WindowVideoSource := preload("res://scripts/video/window_video_source.gd")
const AssistantFetch := preload("res://scripts/assistant/assistant_fetch.gd")
const WorkerTask := preload("res://scripts/dev/worker_task.gd")
const FileBrowser := preload("res://ui/files_tab.gd")

const READ_TIMEOUT := 20.0
const REPEATS: Array[String] = ["off", "one", "all"]
const HOST_PATH := "the host's path as hosts or list_dir network:// give it: smb://host or smb://host/share"

## scripts/dev/command_host.gd
var host: Node


func register_all() -> void:
	var R := DevCommands
	# --- Network hosts ---
	R.register("hosts", _cmd_hosts, {
		"description": "The saved network (SMB) hosts of the Network place: each one's path, host, share, label and "
				+ "whether a login is saved (never the login itself).",
		"returns": "[{path, host, share, label, login}]", "assistant": "read"})
	R.register("host_add", _cmd_host_add, {
		"description": "Saves a network (SMB) host in the Network place, as the Add host form does; with a login when "
				+ "it needs one. The login is kept in the player and never given back.",
		"params": [
			{"name": "host", "type": "string", "required": true,
				"description": "the host's name or address on this network, e.g. nas.local or 192.168.1.10"},
			{"name": "share", "type": "string", "default": "",
				"description": "a share to open at, e.g. Movies; empty for the host's list of shares"},
			{"name": "label", "type": "string", "default": "", "description": "a short name shown in the list, e.g. TV"},
			{"name": "user", "type": "string", "default": "", "description": "the login's user name; empty for none"},
			{"name": "password", "type": "string", "default": "",
				"description": "the login's password; kept in the player, never shown or given back"},
			{"name": "domain", "type": "string", "default": "", "description": "the login's domain, usually empty"}],
		"level": "change", "returns": "the host as hosts lists it", "assistant": "files"})
	R.register("host_edit", _cmd_host_edit, {
		"description": "Changes a saved host, as Edit hosts does: only the fields given change. An empty user and "
				+ "password remove its login.",
		"params": [
			{"name": "path", "type": "string", "required": true, "description": HOST_PATH},
			{"name": "host", "type": "string", "description": "a new name or address for the host"},
			{"name": "share", "type": "string", "description": "a new share to open at; empty for none"},
			{"name": "label", "type": "string", "description": "a new short name; empty for none"},
			{"name": "user", "type": "string", "description": "the login's user name"},
			{"name": "password", "type": "string",
				"description": "the login's password; kept in the player, never shown or given back"},
			{"name": "domain", "type": "string", "description": "the login's domain"}],
		"level": "change", "returns": "the host as hosts lists it", "assistant": "files"})
	R.register("host_remove", _cmd_host_remove, {
		"description": "Removes a saved host and its login, as the host form's Delete host does (no question; undo "
				+ "puts it back).",
		"params": [{"name": "path", "type": "string", "required": true, "description": HOST_PATH}],
		"level": "change", "returns": "{removed: path}", "assistant": "files"})
	# --- Favourites ---
	R.register("favourites", _cmd_favourites, {
		"description": "The Favourites place: the files and folders the viewer starred, newest first.",
		"returns": "[{path, title, is_dir, added}]", "assistant": "read"})
	R.register("favourite_add", _cmd_favourite_add, {
		"description": "Stars a file or a folder, as a folder's Favourite button or \"Add the playing file\" does.",
		"params": [
			{"name": "path", "type": "string", "default": "",
				"description": "a file or folder path as list_dir gives it; empty for the file playing now"},
			{"name": "title", "type": "string", "default": "", "description": "the name to list it by; empty for its own"}],
		"level": "change", "returns": "{path, title, is_dir}", "assistant": "files"})
	R.register("favourite_remove", _cmd_favourite_remove, {
		"description": "Takes a file or folder out of the favourites, as Edit favourites does.",
		"params": [{"name": "path", "type": "string", "required": true, "description": "its path as favourites lists it"}],
		"level": "change", "returns": "{removed: path}", "assistant": "files"})
	# --- The queue ---
	R.register("queue", _cmd_queue, {
		"description": "The Queue place: the files of the playlist in order with the playing one marked, and the "
				+ "switches shuffle, repeat, play_on and gapless.",
		"returns": "{items: [{index, path, title, current}], shuffle, repeat, play_on, gapless}", "assistant": "read"})
	R.register("queue_jump", _cmd_queue_jump, {
		"description": "Opens a file of the queue, as a row of the Queue place does.",
		"params": [{"name": "index", "type": "int", "required": true, "description": "its index as queue lists it"}],
		"level": "control", "returns": "{opening: path}", "assistant": "control"})
	R.register("queue_remove", _cmd_queue_remove, {
		"description": "Takes a file out of the queue, as Edit queue does; never the one playing.",
		"params": [{"name": "index", "type": "int", "required": true, "description": "its index as queue lists it"}],
		"level": "control", "returns": "{removed: path}", "assistant": "control"})
	R.register("queue_clear_upcoming", _cmd_queue_clear, {
		"description": "Drops every file after the one playing, as Clear upcoming does.",
		"level": "control", "returns": "{removed: count}", "assistant": "control"})
	R.register("queue_shuffle", _cmd_queue_shuffle, {
		"description": "Shuffle on or off: on, the files after the playing one play in a random order; off, the order "
				+ "comes back.",
		"params": [{"name": "on", "type": "bool", "required": true, "description": "true to shuffle, false for the order"}],
		"level": "control", "returns": "{shuffle}", "assistant": "control"})
	R.register("queue_repeat", _cmd_queue_repeat, {
		"description": "What happens at the end: off, one (the same file again) or all (back to the first after the "
				+ "last).",
		"params": [{"name": "mode", "type": "string", "required": true, "enum": REPEATS,
				"description": "off, one or all"}],
		"level": "control", "returns": "{repeat}", "assistant": "control"})
	R.register("queue_play_on", _cmd_queue_play_on, {
		"description": "Play on: at the end of a file the next one of the queue opens by itself.",
		"params": [{"name": "on", "type": "bool", "required": true, "description": "true to play on, false to stop"}],
		"level": "control", "returns": "{play_on}", "assistant": "control"})
	R.register("gapless", _cmd_gapless, {
		"description": "Gapless: the next file of the queue opens behind the playing one and takes over at its end, "
				+ "with no pause between.",
		"params": [{"name": "on", "type": "bool", "required": true, "description": "true for gapless, false for off"}],
		"level": "control", "returns": "{gapless}", "assistant": "control"})
	# --- Search, the Library, the tab ---
	R.register("search", _cmd_search, {
		"description": "The Search place's search: favourites, watch history and the queue, then a local folder and "
				+ "its subfolders. Every word must be in the name; case and accents don't matter.",
		"params": [
			{"name": "query", "type": "string", "required": true, "description": "the words to look for"},
			{"name": "folder", "type": "string", "default": "",
				"description": "a local folder to walk as well; empty for the last one the Files tab showed"}],
		"returns": "{query, folder, results: [{path, title, is_dir, source}]}", "assistant": "read"})
	R.register("library", _cmd_library, {
		"description": "A folder of the Library as its view draws it, from the NFO files: the shows and films, a show's "
				+ "seasons, a season's episodes, a film; view plain where nothing says what it is.",
		"params": [{"name": "path", "type": "string", "default": "",
				"description": "a folder inside the Library; empty for the Library itself"}],
		"returns": "{view: home | shelf | show | season | movie | plain, title, parent, ...}", "assistant": "read"})
	R.register("files_show", _cmd_files_show, {
		"description": "Shows the menu at the Files tab, at a folder or place, for the viewer to look at or pick from.",
		"params": [
			{"name": "path", "type": "string", "default": "",
				"description": "a folder or place as places or list_dir give it; empty for the one on show"},
			{"name": "query", "type": "string", "default": "",
				"description": "with path search://, a search to run and show"}],
		"level": "control", "returns": "{folder, shown}", "assistant": "files"})
	R.register("open_in_corner", _cmd_open_in_corner, {
		"description": "Plays a video small and silent in a corner of the screen, beside the film, as Files' In "
				+ "corner does (picture in picture).",
		"params": [{"name": "path", "type": "string", "required": true,
				"description": "a video file as list_dir gives it (not a picture, music or a test pattern)"}],
		"level": "control", "returns": "{state, path}", "assistant": "control"})
	R.register("stop_showing", _cmd_stop_showing, {
		"description": "Stops showing the window on the big screen (a web page or a desktop window), as the Browser "
				+ "place's Stop showing does.",
		"level": "control", "returns": "{stopped: path}", "assistant": "control"})
	# --- Saved web pages ---
	R.register("web_pages", _cmd_web_pages, {
		"description": "The web pages saved in the Browser place.",
		"returns": "{pages: [url]}", "assistant": "read"})
	R.register("web_page_save", _cmd_web_page_save, {
		"description": "Saves a web page in the Browser place, as the web page form's Save does; it doesn't open it.",
		"params": [{"name": "url", "type": "string", "required": true,
				"description": "the page's address; https:// is added when it has no scheme"}],
		"level": "change", "returns": "{saved: url}", "assistant": "files"})
	R.register("web_page_remove", _cmd_web_page_remove, {
		"description": "Removes a saved web page from the Browser place, as Edit pages does.",
		"params": [{"name": "url", "type": "string", "required": true, "description": "the page as web_pages lists it"}],
		"level": "change", "returns": "{removed: url}", "assistant": "files"})


func _main() -> Node:
	return host.main if host != null and is_instance_valid(host.main) else null


## The Files tab, or null (a build or a test without the pane).
func _files() -> Node:
	var m := _main()
	var layer: Node = m.get("ui") if m != null else null
	var pane: Object = layer.get("ui") if layer != null else null
	return pane.get("files") if pane != null else null


func _feature(feature_name: String) -> Node:
	var m := _main()
	return m.features.get(feature_name) if m != null and m.get("features") != null else null


func _refresh(place: String) -> void:
	var files := _files()
	if files != null:
		files.refresh_place(place)


# --- Network hosts ---------------------------------------------------------------------------------------------------

## A host as the commands give it out: never its user name or password.
static func host_entry(h: Dictionary) -> Dictionary:
	return {"path": NetworkHosts.root_path(h), "host": str(h["host"]), "share": str(h.get("share", "")),
			"label": str(h.get("label", "")), "login": str(h.get("user", "")) != "" or str(h.get("password", "")) != ""}


static func _host_index(path: String) -> int:
	var p := path.strip_edges().trim_suffix("/").to_lower()
	for i in NetworkHosts.hosts.size():
		if NetworkHosts.root_path(NetworkHosts.hosts[i]).to_lower() == p:
			return i
	return -1


## [host, share] from "nas.local", "smb://nas.local" or "smb://nas.local/Movies"; [] when it isn't a plain host.
static func _split_host(text: String) -> Array:
	var rest := text.strip_edges().trim_prefix("smb://").trim_suffix("/")
	var parts := rest.split("/", false)
	if parts.is_empty() or parts.size() > 2 or rest.contains("@") or rest.contains("://") or rest.contains(" "):
		return []
	return [parts[0], parts[1] if parts.size() > 1 else ""]


## Why an assistant may not save this host, or "": on this network only.
func _host_refusal(ctx: DevCommands.Call, host_name: String) -> String:
	if ctx.client == "":
		return ""
	return await AssistantFetch.host_refusal(host.get_tree(), host_name)


func _cmd_hosts(_args: Dictionary, _ctx: DevCommands.Call) -> Variant:
	var out: Array = []
	for h: Dictionary in NetworkHosts.hosts:
		out.append(host_entry(h))
	return out


func _cmd_host_add(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var split := _split_host(args["host"])
	if split.is_empty():
		return ctx.fail("host: a name or address, e.g. nas.local, or smb://host/share (no login in it)")
	var share: String = args["share"] if str(args["share"]) != "" else split[1]
	var entry := {"host": split[0], "share": share, "label": str(args["label"]).strip_edges(), "user": args["user"],
			"password": args["password"], "domain": args["domain"]}
	var path := NetworkHosts.root_path(entry)
	if _host_index(path) >= 0:
		return ctx.fail("%s is saved already (host_edit changes it)" % path)
	var why: String = await _host_refusal(ctx, split[0])
	if why != "":
		return ctx.fail(why)
	FileBrowser.save_host(-1, entry)
	_refresh("network://")
	ctx.summary = "host %s saved" % path
	ctx.undo = func() -> void:
		var i := _host_index(path)
		if i >= 0:
			FileBrowser.delete_host(i)
			_refresh("network://")
	return host_entry(NetworkHosts.hosts[_host_index(path)])


func _cmd_host_edit(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var i := _host_index(args["path"])
	if i < 0:
		return ctx.fail("no saved host %s (hosts lists them)" % args["path"])
	var old: Dictionary = NetworkHosts.hosts[i].duplicate()
	var entry := old.duplicate()
	if args.has("host"):
		var split := _split_host(args["host"])
		if split.is_empty() or str(split[1]) != "":
			return ctx.fail("host: a name or address, e.g. nas.local (the share is its own field)")
		entry["host"] = split[0]
		if str(split[0]).to_lower() != str(old["host"]).to_lower():
			var why: String = await _host_refusal(ctx, split[0])
			if why != "":
				return ctx.fail(why)
	for k in ["share", "label", "user", "password", "domain"]:
		if args.has(k):
			entry[k] = str(args[k]).strip_edges() if k in ["share", "label"] else args[k]
	var path := NetworkHosts.root_path(entry)
	var other := _host_index(path)
	if other >= 0 and other != i:
		return ctx.fail("%s is saved already" % path)
	FileBrowser.save_host(i, entry)
	_refresh("network://")
	ctx.summary = "host %s changed" % path
	ctx.undo = func() -> void:
		var j := _host_index(path)
		if j >= 0:
			FileBrowser.save_host(j, old)
			_refresh("network://")
	return host_entry(NetworkHosts.hosts[i])


func _cmd_host_remove(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var i := _host_index(args["path"])
	if i < 0:
		return ctx.fail("no saved host %s (hosts lists them)" % args["path"])
	var old: Dictionary = NetworkHosts.hosts[i].duplicate()
	var path := NetworkHosts.root_path(old)
	FileBrowser.delete_host(i)
	_refresh("network://")
	ctx.summary = "host %s removed" % path
	ctx.undo = func() -> void:
		if _host_index(path) < 0:
			FileBrowser.save_host(-1, old)
			_refresh("network://")
	return {"removed": path}


# --- Favourites ------------------------------------------------------------------------------------------------------

func _cmd_favourites(_args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var lib := _feature("library")
	if lib == null:
		return ctx.fail("no favourites in this build")
	return lib.favourites()


func _cmd_favourite_add(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var lib := _feature("library")
	if lib == null:
		return ctx.fail("no favourites in this build")
	var path: String = str(args["path"]).strip_edges()
	var title: String = str(args["title"]).strip_edges()
	if path == "":
		path = _main().current_path
		if title == "":
			title = _main().display_title() if path != "" else ""
	if path == "":
		return ctx.fail("nothing plays now: give a path")
	if WindowVideoSource.is_window_path(path) or path.begins_with("browser://"):
		return ctx.fail("a window or web page can't be a favourite (web_page_save keeps a page)")
	if lib.is_favourite(path):
		return ctx.fail("%s is a favourite already" % path)
	var is_dir := DirAccess.dir_exists_absolute(path) or ((NetworkHosts.is_smb(path) or MediaServers.is_upnp(path))
			and not VideoSourceFactory.is_media_file(path))
	if not is_dir and not path.contains("://") and not FileAccess.file_exists(path):
		return ctx.fail("no such file or folder on the headset: %s" % path)
	lib.add_favourite(path, title, is_dir)
	ctx.summary = "favourite: %s" % (title if title != "" else path.trim_suffix("/").get_file())
	ctx.undo = func() -> void: lib.remove_favourite(path)
	for f: Dictionary in lib.favourites():
		if str(f["path"]) == path:
			return {"path": path, "title": f["title"], "is_dir": f["is_dir"]}
	return {"path": path, "title": title, "is_dir": is_dir}


func _cmd_favourite_remove(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var lib := _feature("library")
	if lib == null:
		return ctx.fail("no favourites in this build")
	var path: String = args["path"]
	var old := {}
	for f: Dictionary in lib.favourites():
		if str(f["path"]) == path:
			old = f
	if old.is_empty():
		return ctx.fail("%s is not a favourite (favourites lists them)" % path)
	lib.remove_favourite(path)
	ctx.summary = "no longer a favourite: %s" % old.get("title", path)
	ctx.undo = func() -> void: lib.add_favourite(path, str(old.get("title", "")), bool(old.get("is_dir", false)))
	return {"removed": path}


# --- The queue -------------------------------------------------------------------------------------------------------

func _queue_state(q: Node) -> Dictionary:
	var items: Array = []
	var list: Array = q.items()
	for i in list.size():
		var it: Dictionary = list[i]
		items.append({"index": i, "path": it["path"], "title": it["title"], "current": it["current"]})
	var g := _feature("gapless")
	return {"items": items, "shuffle": q.shuffle, "repeat": q.repeat, "play_on": q.continuous,
			"gapless": bool(g.enabled) if g != null else false}


func _cmd_queue(_args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var q := _feature("queue")
	if q == null:
		return ctx.fail("no queue in this build")
	return _queue_state(q)


func _cmd_queue_jump(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var q := _feature("queue")
	var m := _main()
	if q == null:
		return ctx.fail("no queue in this build")
	var index: int = args["index"]
	if index < 0 or index >= m.playlist.size():
		return ctx.fail("no file %d in the queue (it has %d)" % [index, m.playlist.size()])
	var old: int = m.playlist_index
	var path: String = m.playlist[index]
	q.jump(index)
	ctx.summary = "queue: %s" % path.get_file()
	if old >= 0 and old != index:
		ctx.undo = func() -> void: q.jump(old)
	return {"opening": path}


func _cmd_queue_remove(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var q := _feature("queue")
	var m := _main()
	if q == null:
		return ctx.fail("no queue in this build")
	var index: int = args["index"]
	if index < 0 or index >= m.playlist.size():
		return ctx.fail("no file %d in the queue (it has %d)" % [index, m.playlist.size()])
	if index == m.playlist_index:
		return ctx.fail("that one is playing; only the others can go")
	var path: String = m.playlist[index]
	q.remove(index)
	ctx.summary = "out of the queue: %s" % path.get_file()
	ctx.undo = func() -> void:
		q.append(path)
		q.move(m.playlist.size() - 1, mini(index, m.playlist.size() - 1))
	return {"removed": path}


func _cmd_queue_clear(_args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var q := _feature("queue")
	var m := _main()
	if q == null:
		return ctx.fail("no queue in this build")
	var gone: Array = m.playlist.slice(m.playlist_index + 1)
	q.clear_upcoming()
	ctx.summary = "upcoming cleared"
	ctx.undo = func() -> void:
		for p: String in gone:
			q.append(p)
	return {"removed": gone.size()}


func _cmd_queue_shuffle(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var q := _feature("queue")
	if q == null:
		return ctx.fail("no queue in this build")
	var old: bool = q.shuffle
	q.set_shuffle(args["on"])
	ctx.summary = "shuffle %s" % ("on" if args["on"] else "off")
	ctx.undo = func() -> void: q.set_shuffle(old)
	return {"shuffle": q.shuffle}


func _cmd_queue_repeat(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var q := _feature("queue")
	if q == null:
		return ctx.fail("no queue in this build")
	var old: String = q.repeat
	q.set_repeat(args["mode"])
	ctx.summary = "repeat %s" % args["mode"]
	ctx.undo = func() -> void: q.set_repeat(old)
	return {"repeat": q.repeat}


func _cmd_queue_play_on(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var q := _feature("queue")
	if q == null:
		return ctx.fail("no queue in this build")
	var old: bool = q.continuous
	q.set_continuous(args["on"])
	ctx.summary = "play on %s" % ("on" if args["on"] else "off")
	ctx.undo = func() -> void: q.set_continuous(old)
	return {"play_on": q.continuous}


func _cmd_gapless(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var g := _feature("gapless")
	if g == null:
		return ctx.fail("no gapless playback in this build")
	var old: bool = g.enabled
	g.set_enabled(args["on"])
	_refresh("queue://")
	ctx.summary = "gapless %s" % ("on" if args["on"] else "off")
	ctx.undo = func() -> void:
		g.set_enabled(old)
		_refresh("queue://")
	return {"gapless": bool(g.enabled)}


# --- Search, the Library, the tab ------------------------------------------------------------------------------------

func _cmd_search(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var lib := _feature("library")
	if lib == null:
		return ctx.fail("no search in this build")
	var query: String = str(args["query"]).strip_edges()
	if query == "":
		return ctx.fail("query: give a word to look for")
	var folder: String = args["folder"]
	if folder == "" and _files() != null:
		folder = _files().last_local_folder()
	var results: Array = lib.search_known(query)
	if folder != "" and not folder.contains("://"):
		if not DirAccess.dir_exists_absolute(folder):
			return ctx.fail("no such folder on the headset: %s" % folder)
		# The walk the Search place runs (favourites_search.gd, search_folder), on a worker.
		var walked: Dictionary = await WorkerTask.run(host.get_tree(), func() -> Variant:
			return FavouritesSearch.walk(folder, query), READ_TIMEOUT)
		var seen := {}
		for r: Dictionary in results:
			seen[str(r["path"])] = true
		for r: Dictionary in (walked.get("result", []) if walked["done"] else []):
			if not seen.has(str(r["path"])):
				results.append(r)
	return {"query": query, "folder": folder, "results": results}


func _cmd_library(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var path: String = str(args["path"]).strip_edges().trim_suffix("/")
	if path == "":
		path = LibraryIndex.root()
	if path != LibraryIndex.root() and not LibraryIndex.is_inside(path):
		return ctx.fail("%s is not inside the Library (%s)" % [path, LibraryIndex.root()])
	if path == LibraryIndex.root():
		LibraryIndex.ensure_root()
	if not DirAccess.dir_exists_absolute(path):
		return ctx.fail("no such folder in the Library: %s" % path)
	var r: Dictionary = await WorkerTask.run(host.get_tree(), func() -> Variant: return LibraryIndex.read(path),
			READ_TIMEOUT)
	if not r["done"]:
		return ctx.fail("reading %s took longer than %d s" % [path, READ_TIMEOUT])
	var data: Dictionary = r["result"]
	data["path"] = path
	return data


func _cmd_files_show(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var m := _main()
	var files := _files()
	if files == null or m.ui == null:
		return ctx.fail("this build has no menu")
	var path: String = str(args["path"]).strip_edges()
	var query: String = str(args["query"]).strip_edges()
	if query != "" and path == "":
		path = "search://"
	if query != "" and path != "search://":
		return ctx.fail("query goes with path search://")
	if path != "" and not _showable(path):
		return ctx.fail("no such folder or place: %s (places and list_dir give them)" % path)
	var was_open: bool = m.ui.is_open()
	var old_folder: String = files.current
	m.ui.show_panel()
	m.ui.ui.show_tab((m.ui.ui.tabs as Array).find(files))
	if query != "":
		files.search_for(query)
	elif path != "":
		files.open_folder(path)
	ctx.summary = "Files: %s" % files.current
	ctx.undo = func() -> void:
		if old_folder != "" and is_instance_valid(files):
			files.open_folder(old_folder)
		if not was_open and _main() != null:
			_main().ui.hide_panel()
	return {"folder": files.current, "shown": m.ui.is_open()}


## A folder or place the Files tab can open (open_folder falls back to Home for anything else).
func _showable(path: String) -> bool:
	if path.ends_with("://") or path.begins_with("agent://"):
		for p: Dictionary in FileBrowser.get_places():
			if str(p["path"]) == path:
				return true
		return path == "search://"
	return NetworkHosts.is_smb(path) or MediaServers.is_upnp(path) or DirAccess.dir_exists_absolute(path) \
			or path == LibraryIndex.root()


func _cmd_open_in_corner(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var path: String = str(args["path"]).strip_edges()
	if ctx.client != "":
		# Loaded, not preloaded: assistant_commands.gd preloads command_host.gd, which preloads this file.
		var why: String = load("res://scripts/assistant/assistant_commands.gd").open_refusal(path)
		if why != "":
			return ctx.fail(why)
	var pip := _feature("pip")
	if pip == null:
		return ctx.fail("no picture in picture in this build")
	if not pip.can_show(path):
		return ctx.fail("the corner shows video files only (not pictures, music, test patterns or windows)")
	if not pip.open(path):
		return ctx.fail("picture in picture needs an engine build with MediaSource")
	ctx.summary = "in the corner: %s" % path.get_file()
	ctx.undo = func() -> void: pip.close()
	return {"state": pip.state, "path": path}


func _cmd_stop_showing(_args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var m := _main()
	var path: String = m.current_path
	if not WindowVideoSource.is_window_path(path):
		return ctx.fail("no window or web page is on the big screen")
	m.close_media()
	ctx.summary = "stopped showing %s" % WindowVideoSource.describe_path(path)
	return {"stopped": path}


# --- Saved web pages -------------------------------------------------------------------------------------------------

func _cmd_web_pages(_args: Dictionary, _ctx: DevCommands.Call) -> Variant:
	return {"pages": WebPages.pages.duplicate()}


func _cmd_web_page_save(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var url := WebPages.normalized(args["url"])
	if not (url.begins_with("http://") or url.begins_with("https://")) or url.contains(" "):
		return ctx.fail("url: a web page's address, http or https")
	if url in WebPages.pages:
		return ctx.fail("%s is saved already" % url)
	WebPages.add_page(url)
	_refresh("browser://")
	ctx.summary = "page saved: %s" % url
	ctx.undo = func() -> void:
		WebPages.remove_page(url)
		_refresh("browser://")
	return {"saved": url}


func _cmd_web_page_remove(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var url: String = args["url"]
	if not (url in WebPages.pages):
		return ctx.fail("%s is not a saved page (web_pages lists them)" % url)
	WebPages.remove_page(url)
	_refresh("browser://")
	ctx.summary = "page removed: %s" % url
	ctx.undo = func() -> void:
		WebPages.add_page(url)
		_refresh("browser://")
	return {"removed": url}
