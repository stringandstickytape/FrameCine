extends RefCounted

## Commands for remote controls (the phone remote, the PC link): the file browser's places and folder listings, typing
## into the pane's focused text field, and opening a web page on the Browser source. Registered with the built-ins by
## command_host.gd. Listings reuse the file browser's data (DirectoryLister, saved hosts, saved pages, test patterns)
## and run on a WorkerThreadPool task, so a slow share never blocks the frame.

const DevCommands := preload("res://scripts/dev/dev_commands.gd")
const DirectoryLister := preload("res://scripts/net/directory_lister.gd")
const NetworkHosts := preload("res://scripts/net/network_hosts.gd")
const WebPages := preload("res://scripts/net/web_pages.gd")
const VideoSourceFactory := preload("res://scripts/video/video_source_factory.gd")
const StubVideoSource := preload("res://scripts/video/stub_video_source.gd")
const FileBrowser := preload("res://ui/files_tab.gd")
const HostDiscovery := preload("res://scripts/net/host_discovery.gd")
const MediaServers := preload("res://scripts/net/media_servers.gd")
const AssistantFetch := preload("res://scripts/assistant/assistant_fetch.gd")

const LIST_TIMEOUT := 20.0
const WorkerTask := preload("res://scripts/dev/worker_task.gd")

## scripts/dev/command_host.gd
var host: Node


func register_all() -> void:
	DevCommands.register("places", _cmd_places, {
		"description": "The file browser's places: test patterns, Network, Browser, home, removable media.",
		"assistant": "read", "returns": "[{label, path}]"})
	DevCommands.register("list_dir", _cmd_list_dir, {
		"description": "A folder as the file browser lists it: folders first, then video files. Also stub://, "
				+ "network:// (saved hosts), browser:// (saved pages), smb://host and smb://host/share/..., upnp:// (media "
				+ "servers; a video's path is its http:// URL). all: every file of a folder, not just videos",
		"params": [{"name": "path", "type": "string", "required": true, "description": "a folder: a local path, "
				+ "network://, smb://host/share/..., upnp://..., stub:// or browser://"},
				{"name": "all", "type": "bool", "default": false, "description": "every file, not just videos"}],
		"assistant": "read", "returns": "{path, parent, entries: [{name, path, is_dir, size}], error, simulated}"})
	DevCommands.register("media_servers", _cmd_media_servers, {
		"description": "Looks for media servers (UPnP/DLNA) on the LAN for a few seconds; url adds one by its "
				+ "description URL instead (when multicast doesn't get through).",
		"params": [{"name": "seconds", "type": "float", "default": 3.0,
				"description": "how long to look, 0.5 to 15 seconds"},
				{"name": "url", "type": "string", "default": "",
				"description": "a server's description URL on this network, to add it without looking"}],
		"returns": "[{uuid, name, model, location, control}]", "assistant": "files"})
	DevCommands.register("discover_hosts", _cmd_discover_hosts, {
		"description": "Looks for file servers on the LAN (NetBIOS node status and mDNS _smb._tcp) for a few seconds, "
				+ "as the Network place's Find hosts does; host_add saves one.",
		"params": [{"name": "seconds", "type": "float", "default": 3.0,
				"description": "how long to look, 0.5 to 15 seconds"}],
		"returns": "[{name, address, source, file_server, port}]", "assistant": "read"})
	DevCommands.register("type_text", _cmd_type_text, {
		"description": "Types text into the pane's focused text field (host form, URL form, keyboard field).",
		"params": [{"name": "text", "type": "string", "required": true},
				{"name": "submit", "type": "bool", "default": false, "description": "then press Enter"},
				{"name": "replace", "type": "bool", "default": false, "description": "replace the field's text"}],
		"level": "control", "returns": "{field, text}"})
	DevCommands.register("open_url", _cmd_open_url, {
		"description": "Opens a web page on the screen through the Browser source (https:// is added when missing).",
		"params": [{"name": "url", "type": "string", "required": true}],
		"level": "control", "returns": "{opening: browser://url}"})


func _cmd_places(_args: Dictionary, _ctx: DevCommands.Call) -> Variant:
	return FileBrowser.get_places()


func _cmd_list_dir(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var path: String = args["path"]
	var entries: Array = []
	match path:
		"stub://", "stub:":
			for p in StubVideoSource.list_patterns():
				entries.append({"name": str(p.get("label", p["path"])), "path": p["path"], "is_dir": false, "size": 0})
			return {"path": "stub://", "parent": "", "entries": entries, "error": "", "simulated": false}
		"network://":
			for h in NetworkHosts.hosts:
				var root := NetworkHosts.root_path(h)
				entries.append({"name": root.trim_prefix("smb://"), "path": root, "is_dir": true, "size": 0})
			return {"path": path, "parent": "", "entries": entries, "error": "", "simulated": false}
		"browser://":
			for u in WebPages.pages:
				entries.append({"name": u, "path": "browser://" + u, "is_dir": false, "size": 0})
			return {"path": path, "parent": "", "entries": entries, "error": "", "simulated": false}
	if MediaServers.is_upnp(path) or path == "upnp:":
		var r: Variant = await _off_thread(func() -> Variant: return MediaServers.list(path), LIST_TIMEOUT)
		if r == null:
			return ctx.fail("listing %s took longer than %d s" % [path, LIST_TIMEOUT])
		return {"path": path, "parent": r["parent"], "entries": r["entries"], "error": r["error"], "simulated": false}
	if not NetworkHosts.is_smb(path) and not DirAccess.dir_exists_absolute(path):
		return ctx.fail("no such folder on the headset: %s" % path)
	# DirectoryLister blocks (a share can take seconds): run it on a worker and wait without blocking the frame.
	var listed: Dictionary = await WorkerTask.run(host.get_tree(),
			func() -> Variant: return DirectoryLister.list(path), LIST_TIMEOUT)
	if not listed["done"]:
		return ctx.fail("listing %s took longer than %d s" % [path, LIST_TIMEOUT])
	var result: Dictionary = listed["result"] if listed["result"] is Dictionary else {"entries": [], "error": "no result"}
	for e: Dictionary in result["entries"]:
		if not e["is_dir"] and not args["all"] and not VideoSourceFactory.is_video_file(e["name"]):
			continue
		var child := path.trim_suffix("/") + "/" + str(e["name"])
		entries.append({"name": e["name"], "path": child, "is_dir": e["is_dir"], "size": e["size"]})
	return {"path": path, "parent": _parent_of(path), "entries": entries, "error": result["error"],
			"simulated": result.get("simulated", false)}


func _cmd_media_servers(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var url: String = args["url"]
	var seconds: float = clampf(args["seconds"], 0.5, 15.0)
	# An assistant's URL: a server on this network only (the headset fetches it).
	if url != "" and ctx.client != "":
		var u := AssistantFetch.parse_url(url)
		if u.has("error"):
			return ctx.fail(str(u["error"]))
		var why: String = await AssistantFetch.host_refusal(host.get_tree(), str(u["host"]))
		if why != "":
			return ctx.fail(why)
	var r: Variant = await _off_thread(func() -> Variant:
		if url != "":
			var d := MediaServers.add_server(url)
			return d if d.has("error") else MediaServers.known()
		return MediaServers.discover(seconds), seconds + 30.0)
	if r == null:
		return ctx.fail("timed out")
	if r is Dictionary and r.has("error"):
		return ctx.fail(r["error"])
	return r


## Runs f on a worker thread and waits for it frame by frame; null after `timeout` seconds.
func _off_thread(f: Callable, timeout: float) -> Variant:
	var r: Dictionary = await WorkerTask.run(host.get_tree(), f, timeout)
	return r.get("result")


static func _parent_of(p: String) -> String:
	if NetworkHosts.is_smb(p):
		var rest := p.trim_prefix("smb://").trim_suffix("/")
		return "network://" if not rest.contains("/") else "smb://" + rest.get_base_dir()
	var trimmed := p.trim_suffix("/")
	var parent := trimmed.get_base_dir()
	return "" if parent == trimmed or parent == "" else parent


func _cmd_discover_hosts(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var d := HostDiscovery.new()
	d.name = "HostDiscovery"
	host.add_child(d)
	if not d.start(clampf(args["seconds"], 0.5, 15.0)):
		d.queue_free()
		return ctx.fail("can't open a UDP socket")
	var found: Array = await d.finished
	d.queue_free()
	return found


func _cmd_type_text(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var field := focused_text_field()
	if field == null:
		return ctx.fail("no text field has the focus on the pane (open a form first)")
	var text: String = args["text"]
	if field is LineEdit:
		var le := field as LineEdit
		if args["replace"]:
			le.text = text
			le.caret_column = text.length()
		else:
			le.insert_text_at_caret(text)
		le.text_changed.emit(le.text)
		if args["submit"]:
			le.text_submitted.emit(le.text)
		ctx.summary = "typed %d characters" % text.length()
		return {"field": str(le.name), "text": "" if le.secret else le.text}
	var te := field as TextEdit
	if args["replace"]:
		te.text = text
	else:
		te.insert_text_at_caret(text)
	ctx.summary = "typed %d characters" % text.length()
	return {"field": str(te.name), "text": te.text}


## The LineEdit or TextEdit that has the keyboard focus in the menu's viewports (or the window's), or null.
func focused_text_field() -> Control:
	var m: Node = host.main
	var viewports: Array[Viewport] = []
	if m != null and m.get("ui") != null:
		for vp in (m.ui as Node).find_children("*", "SubViewport", true, false):
			viewports.append(vp as Viewport)
	viewports.append(host.get_viewport())
	for vp in viewports:
		var c := vp.gui_get_focus_owner()
		if c is LineEdit or c is TextEdit:
			return c
	return null


func _cmd_open_url(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var url := WebPages.normalized(args["url"])
	if url == "":
		return ctx.fail("empty url")
	WebPages.set_last_url(url)
	host.main.open_path("browser://" + url)
	ctx.summary = "open %s" % url
	return {"opening": "browser://" + url}
