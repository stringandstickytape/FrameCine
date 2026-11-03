extends SceneTree

## The Files tab's actions as commands (docs/dev/assistant-coverage/files.md), each through DevCommands.execute against
## the real main scene: the effect, the read-back, the tab following, undo; that no reply or summary holds a saved
## login; the rules for a paired assistant (a host on this network only, open_in_corner as open, no restart of itself);
## and that every command of the area carries a consumer level and describes each parameter. Stand-ins: the window
## capture (as test_local_agents.gd), a home folder for the agents and the Android apps, a Library (library_fixture.gd).
##
## godot --headless --xr-mode off --path app --script res://tests/test_assistant_coverage_files.gd

const DevCommands := preload("res://scripts/dev/dev_commands.gd")
const CommandHost := preload("res://scripts/dev/command_host.gd")
const NetworkHosts := preload("res://scripts/net/network_hosts.gd")
const WebPages := preload("res://scripts/net/web_pages.gd")
const LibraryIndex := preload("res://scripts/library/library_index.gd")
const LibraryFixture := preload("res://tests/library_fixture.gd")
const AgentTerminal := preload("res://scripts/agents/agent_terminal.gd")
const Lepton := preload("res://scripts/android/lepton.gd")
const StubVideoSource := preload("res://scripts/video/stub_video_source.gd")
const WindowVideoSource := preload("res://scripts/video/window_video_source.gd")

## Every command of the area, with the consumer level it must carry.
const AREA := {
	"places": "read", "list_dir": "read", "discover_hosts": "read", "media_servers": "files",
	"hosts": "read", "host_add": "files", "host_edit": "files", "host_remove": "files",
	"favourites": "read", "favourite_add": "files", "favourite_remove": "files",
	"queue": "read", "queue_jump": "control", "queue_remove": "control", "queue_clear_upcoming": "control",
	"queue_shuffle": "control", "queue_repeat": "control", "queue_play_on": "control", "gapless": "control",
	"search": "read", "library": "read", "files_show": "files", "open_in_corner": "control", "stop_showing": "control",
	"web_pages": "read", "web_page_save": "files", "web_page_remove": "files",
	"agents": "read", "agent_start": "apps", "agent_restart": "apps", "agent_show": "apps", "agent_hide": "apps",
	"agent_big_screen": "apps",
	"android_status": "read", "android_start": "apps", "android_stop": "apps", "android_back": "apps",
}
const CONSUMER_LEVELS: Array[String] = ["read", "card", "control", "room", "settings", "files", "apps"]
const SAVED_PASSWORD := "pw-Saved-7731"
const SAVED_USER := "user-Saved-7731"
const NEW_PASSWORD := "pw-New-4410"
const NEW_USER := "user-New-4410"
const EDITED_PASSWORD := "pw-Edited-9902"
const CLAUDE := "Claude Code on this headset"


## Stands in for the consumer API's dispatcher: the registry asks the gate first, which names the caller.
class AsClient extends RefCounted:
	var client := ""

	func check(ctx: RefCounted, _spec: Dictionary) -> String:
		ctx.client = client
		return ""


## The window capture, as in test_local_agents.gd.
class FakeX extends RefCounted:
	var windows: Array[Dictionary] = []

	func open() -> int:
		return OK

	func close() -> void:
		pass

	func list_windows(_all := false) -> Array[Dictionary]:
		return windows

	func capture(_id: int) -> int:
		return OK

	func stop_capture() -> void:
		pass

	func update() -> bool:
		return false

	func get_texture() -> Texture2D:
		return ImageTexture.create_from_image(Image.create_empty(64, 64, false, Image.FORMAT_RGBA8))

	func get_size() -> Vector2i:
		return Vector2i(64, 64)

	func send_unicode(_code: int, _pressed: bool) -> void:
		pass

	func send_godot_key(_key: int, _pressed: bool) -> void:
		pass


var _failures := 0
var _checks := 0
var main: Node3D
var files: Node
var home := ""
## Every reply and summary, for the check that no login leaks.
var _said: Array[String] = []


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _run() -> void:
	await _frames(5)
	CommandHost.ensure(self)
	await _frames(2)
	files = main.ui.ui.files
	home = OS.get_user_data_dir().path_join("test_coverage_files_home")
	_clear(home)
	DirAccess.make_dir_recursive_absolute(home)
	var hosts_before := NetworkHosts.hosts.duplicate(true)
	var pages_before := WebPages.pages.duplicate()
	_spec_checks()
	await _host_checks()
	await _web_page_checks()
	await _queue_checks()
	await _favourite_checks()
	await _search_checks()
	await _library_checks()
	await _tab_checks()
	await _window_checks()
	await _agent_checks()
	await _android_checks()
	_leak_checks()
	NetworkHosts.hosts.assign(hosts_before)
	WebPages.pages.assign(pages_before)
	_clear(home)
	print("test_assistant_coverage_files: %d checks, %s" % [_checks,
			"all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(1 if _failures > 0 else 0)


## Runs a command as the consumer API would, as `client` ("" for the dev link).
func _cmd(command: String, args := {}, client := "") -> Dictionary:
	var gate := AsClient.new()
	gate.client = client
	var r: Dictionary = await DevCommands.execute(command, args, true, gate)
	var call: DevCommands.Call = r["call"]
	_said.append("%s %s %s" % [JSON.stringify(r.get("result")), r.get("error", ""), call.summary])
	return r


func _spec_checks() -> void:
	for c: String in AREA:
		var spec := DevCommands.get_spec(c)
		_check("%s is registered" % c, not spec.is_empty())
		if spec.is_empty():
			continue
		_check("%s has a description" % c, str(spec.get("description", "")).length() > 10)
		# places and list_dir are tagged by the core's change, which also describes their parameters.
		if c in ["places", "list_dir"]:
			_check("%s is tagged %s if tagged" % [c, AREA[c]], spec.get("assistant", AREA[c]) == AREA[c])
			continue
		_check("%s is tagged %s (%s)" % [c, AREA[c], spec.get("assistant")], spec.get("assistant") == AREA[c])
		for p: Dictionary in spec["params"]:
			_check("%s %s is described" % [c, p["name"]], str(p.get("description", "")).length() > 5)
	for c: String in DevCommands.command_names():
		var spec := DevCommands.get_spec(c)
		if spec.has("assistant"):
			_check("%s: a consumer level (%s)" % [c, spec["assistant"]], spec["assistant"] in CONSUMER_LEVELS)
			_check("%s: not a code command" % c, spec["level"] != "code")


func _host_checks() -> void:
	NetworkHosts.hosts.clear()
	NetworkHosts.save_host(-1, {"host": "192.168.1.10", "share": "Films", "user": SAVED_USER,
			"password": SAVED_PASSWORD, "label": "Shelf"})
	var r := await _cmd("hosts")
	_check("hosts: path, label, a login saved (%s)" % [r.get("result")], r["ok"] and r["result"].size() == 1
			and r["result"][0]["path"] == "smb://192.168.1.10/Films" and r["result"][0]["label"] == "Shelf"
			and r["result"][0]["login"] == true and not r["result"][0].has("user")
			and not r["result"][0].has("password"))
	files.open_folder("network://")
	r = await _cmd("host_add", {"host": "8.8.8.8", "share": "Films"}, CLAUDE)
	_check("an assistant: not a host on another network (%s)" % r.get("error"), not r["ok"]
			and str(r.get("error")).contains("not on this network") and NetworkHosts.hosts.size() == 1)
	r = await _cmd("host_add", {"host": "smb://someone@192.168.1.20/Films"}, CLAUDE)
	_check("no login in the host's path", not r["ok"])
	r = await _cmd("host_add", {"host": "192.168.1.10", "share": "Films"}, CLAUDE)
	_check("a saved host again is refused (%s)" % r.get("error"), not r["ok"]
			and str(r.get("error")).contains("saved already"))
	r = await _cmd("host_add", {"host": "smb://192.168.1.20/Shows", "label": "Den", "user": NEW_USER,
			"password": NEW_PASSWORD}, CLAUDE)
	var added := NetworkHosts.find_host("192.168.1.20")
	_check("host_add saves it with its login (%s)" % [r.get("result")], r["ok"] and added.get("share") == "Shows"
			and added.get("label") == "Den" and added.get("user") == NEW_USER and added.get("password") == NEW_PASSWORD
			and r["result"]["login"] == true)
	_check("the Network place lists it at once (%s)" % [files.row_texts()], files.row_texts().any(
			func(t: String) -> bool: return t.contains("smb://192.168.1.20/Shows")))
	r = await _cmd("list_dir", {"path": "network://"})
	_check("list_dir network:// has it (%s)" % [r.get("result")], r["ok"] and (r["result"]["entries"] as Array).any(
			func(e: Dictionary) -> bool: return e["path"] == "smb://192.168.1.20/Shows"))
	r = await _cmd("host_edit", {"path": "smb://192.168.1.20/Shows", "label": "Den TV", "password": EDITED_PASSWORD},
			CLAUDE)
	added = NetworkHosts.find_host("192.168.1.20")
	_check("host_edit: only the fields given (%s)" % [r.get("result")], r["ok"] and added.get("label") == "Den TV"
			and added.get("password") == EDITED_PASSWORD and added.get("user") == NEW_USER)
	var call: DevCommands.Call = r["call"]
	call.undo.call()
	_check("host_edit's undo: the old label and login", NetworkHosts.find_host("192.168.1.20").get("label") == "Den"
			and NetworkHosts.find_host("192.168.1.20").get("password") == NEW_PASSWORD)
	r = await _cmd("host_edit", {"path": "smb://192.168.1.20/Shows", "user": "", "password": ""})
	_check("an empty user and password: no login", r["ok"] and r["result"]["login"] == false)
	r = await _cmd("host_edit", {"path": "smb://192.168.1.99"})
	_check("host_edit: an unknown host", not r["ok"] and str(r.get("error")).contains("no saved host"))
	r = await _cmd("host_remove", {"path": "smb://192.168.1.10/Films"}, CLAUDE)
	_check("host_remove: gone (%s)" % [r.get("result")], r["ok"] and NetworkHosts.find_host("192.168.1.10").is_empty())
	_check("the Network place follows", not files.row_texts().any(
			func(t: String) -> bool: return t.contains("192.168.1.10")))
	call = r["call"]
	call.undo.call()
	var back := NetworkHosts.find_host("192.168.1.10")
	_check("host_remove's undo: back with its login", back.get("password") == SAVED_PASSWORD
			and back.get("user") == SAVED_USER and back.get("label") == "Shelf")
	r = await _cmd("hosts")
	_check("hosts reads back both", r["ok"] and r["result"].size() == 2)


func _web_page_checks() -> void:
	WebPages.pages.clear()
	files.open_folder("browser://")
	var r := await _cmd("web_page_save", {"url": "192.168.1.30/guide"}, CLAUDE)
	_check("web_page_save: https:// added, saved (%s)" % [WebPages.pages], r["ok"]
			and WebPages.pages.has("https://192.168.1.30/guide"))
	_check("the Browser place lists it", files.row_texts().has("https://192.168.1.30/guide"))
	r = await _cmd("web_pages")
	_check("web_pages reads it back", r["ok"] and (r["result"]["pages"] as Array).has("https://192.168.1.30/guide"))
	r = await _cmd("web_page_save", {"url": "https://192.168.1.30/guide"})
	_check("saved twice is refused", not r["ok"])
	r = await _cmd("web_page_remove", {"url": "https://192.168.1.30/guide"}, CLAUDE)
	_check("web_page_remove", r["ok"] and WebPages.pages.is_empty() and not files.row_texts().has(
			"https://192.168.1.30/guide"))
	var call: DevCommands.Call = r["call"]
	call.undo.call()
	_check("its undo saves it again", WebPages.pages.has("https://192.168.1.30/guide"))
	WebPages.remove_page("https://192.168.1.30/guide")


func _queue_checks() -> void:
	var pats: Array[String] = []
	for p: Dictionary in StubVideoSource.list_patterns():
		pats.append(str(p["path"]))
	pats.resize(4)
	main.playlist.assign(pats)
	main.open_path(pats[0], false)
	await _frames(5)
	var q: Node = main.features.queue
	q.set_shuffle(false)
	files.open_folder("queue://")
	var r := await _cmd("queue")
	_check("queue: the files, the playing one marked (%s)" % [r.get("result")], r["ok"]
			and r["result"]["items"].size() == 4 and r["result"]["items"][0]["current"] == true
			and r["result"]["items"][2]["path"] == pats[2])
	r = await _cmd("queue_remove", {"index": 0}, CLAUDE)
	_check("queue_remove: never the playing one", not r["ok"] and main.playlist.size() == 4)
	r = await _cmd("queue_remove", {"index": 2}, CLAUDE)
	_check("queue_remove: out (%s)" % [main.playlist], r["ok"] and main.playlist.size() == 3
			and not main.playlist.has(pats[2]))
	_check("the Queue place follows (%s)" % [files.row_texts()], files.row_texts().size() == 3)
	var call: DevCommands.Call = r["call"]
	call.undo.call()
	_check("queue_remove's undo: back in its place (%s)" % [main.playlist], main.playlist == pats)
	r = await _cmd("queue_repeat", {"mode": "all"})
	_check("queue_repeat all", r["ok"] and q.repeat == "all")
	r = await _cmd("queue_repeat", {"mode": "twice"})
	_check("queue_repeat: off, one or all only", not r["ok"])
	call = (await _cmd("queue_repeat", {"mode": "one"}))["call"]
	call.undo.call()
	_check("queue_repeat's undo", q.repeat == "all")
	q.set_repeat("off")
	r = await _cmd("queue_play_on", {"on": true})
	_check("queue_play_on", r["ok"] and q.continuous == true)
	q.set_continuous(false)
	r = await _cmd("queue_shuffle", {"on": true})
	_check("queue_shuffle on: the playing one stays first", r["ok"] and q.shuffle and main.playlist[0] == pats[0]
			and main.playlist.size() == 4)
	r = await _cmd("queue_shuffle", {"on": false})
	_check("queue_shuffle off: the order comes back", r["ok"] and main.playlist == pats)
	var g: Node = main.features.get("gapless")
	if g != null:
		var was: bool = g.enabled
		r = await _cmd("gapless", {"on": not was})
		_check("gapless", r["ok"] and g.enabled == not was)
		(r["call"] as DevCommands.Call).undo.call()
		_check("gapless's undo", g.enabled == was)
	r = await _cmd("queue")
	_check("queue reads the switches back", r["ok"] and r["result"]["shuffle"] == false
			and r["result"]["repeat"] == "off" and r["result"]["play_on"] == false)
	r = await _cmd("queue_clear_upcoming")
	_check("queue_clear_upcoming", r["ok"] and r["result"]["removed"] == 3 and main.playlist.size() == 1)
	call = r["call"]
	call.undo.call()
	_check("its undo puts them back", main.playlist == pats)
	r = await _cmd("queue_jump", {"index": 1}, CLAUDE)
	await _frames(5)
	_check("queue_jump opens it (%s)" % main.current_path, r["ok"] and main.current_path == pats[1])
	r = await _cmd("queue_jump", {"index": 9})
	_check("queue_jump: no such file", not r["ok"])


func _favourite_checks() -> void:
	var lib: Node = main.features.library
	var folder := home.path_join("Clips")
	DirAccess.make_dir_recursive_absolute(folder)
	for f: Dictionary in lib.favourites():
		lib.remove_favourite(str(f["path"]))
	files.open_folder("favourites://")
	var r := await _cmd("favourite_add", {"path": folder}, CLAUDE)
	_check("favourite_add: a folder (%s)" % [r.get("result")], r["ok"] and r["result"]["is_dir"] == true
			and lib.is_favourite(folder))
	r = await _cmd("favourite_add", {})
	_check("favourite_add: the playing file", r["ok"] and lib.is_favourite(main.current_path))
	await _frames(1)
	_check("the Favourites place follows (%s)" % [files.row_texts()], files.row_texts().any(
			func(t: String) -> bool: return t.begins_with("Clips/")))
	r = await _cmd("favourite_add", {"path": folder})
	_check("a favourite twice is refused", not r["ok"])
	r = await _cmd("favourite_add", {"path": home.path_join("nothing.mkv")})
	_check("a file that isn't there is refused", not r["ok"])
	r = await _cmd("favourites")
	_check("favourites reads them back", r["ok"] and r["result"].size() == 2)
	r = await _cmd("favourite_remove", {"path": folder}, CLAUDE)
	_check("favourite_remove", r["ok"] and not lib.is_favourite(folder))
	(r["call"] as DevCommands.Call).undo.call()
	_check("its undo stars it again", lib.is_favourite(folder))
	for f: Dictionary in lib.favourites():
		lib.remove_favourite(str(f["path"]))


func _search_checks() -> void:
	var folder := home.path_join("Search/Deep")
	DirAccess.make_dir_recursive_absolute(folder)
	FileAccess.open(folder.path_join("Lantern Walk.mkv"), FileAccess.WRITE).close()
	var r := await _cmd("search", {"query": "lantern", "folder": home.path_join("Search")})
	_check("search walks the folder (%s)" % [r.get("result")], r["ok"] and (r["result"]["results"] as Array).any(
			func(e: Dictionary) -> bool: return str(e["path"]).ends_with("Lantern Walk.mkv")))
	r = await _cmd("search", {"query": "  "})
	_check("search needs a word", not r["ok"])


func _library_checks() -> void:
	var lib_root := home.path_join("Library")
	LibraryIndex.root_override = lib_root
	LibraryFixture.make(lib_root)
	var r := await _cmd("library")
	_check("library: the home view (%s)" % str(r.get("result")).left(120), r["ok"] and r["result"]["view"] == "home")
	r = await _cmd("library", {"path": lib_root.path_join("TV Shows/Harbour Lights (2011)")})
	_check("library: a show's seasons (%s)" % str(r.get("result")).left(120), r["ok"] and r["result"]["view"] == "show")
	r = await _cmd("library", {"path": home})
	_check("library: only inside the Library", not r["ok"])
	LibraryIndex.root_override = ""


func _tab_checks() -> void:
	main.ui.hide_panel()
	files.open_folder("stub://")
	var r := await _cmd("files_show", {"path": "network://"}, CLAUDE)
	_check("files_show: the menu at Files, at the place (%s)" % [r.get("result")], r["ok"] and main.ui.is_open()
			and files.current == "network://")
	(r["call"] as DevCommands.Call).undo.call()
	_check("its undo: the folder before, the menu hidden", files.current == "stub://" and not main.ui.is_open())
	r = await _cmd("files_show", {"query": "lantern"})
	_check("files_show with a query: the Search place", r["ok"] and files.current == "search://")
	r = await _cmd("files_show", {"path": "/no/such/folder"})
	_check("files_show: no such folder", not r["ok"])
	main.ui.hide_panel()
	r = await _cmd("open_in_corner", {"path": "stub://flat_mono"})
	_check("open_in_corner: video files only (%s)" % r.get("error"), not r["ok"])
	r = await _cmd("open_in_corner", {"path": "smb://192.168.1.77/Films/a.mkv"}, CLAUDE)
	_check("open_in_corner as open: only a saved host (%s)" % r.get("error"), not r["ok"]
			and str(r.get("error")).contains("not a host saved"))


func _window_checks() -> void:
	var r := await _cmd("stop_showing")
	_check("stop_showing: nothing to stop", not r["ok"])
	var path := WindowVideoSource.window_path(0x2a00003)
	main.player.close()
	main.current_path = path
	var s := WindowVideoSource.new()
	s.path = path
	s.window_id = 0x2a00003
	main.player.source = s
	r = await _cmd("stop_showing", {}, CLAUDE)
	_check("stop_showing closes the window (%s)" % main.current_path, r["ok"] and main.current_path == "")


func _agent_checks() -> void:
	AgentTerminal.home_override = home
	AgentTerminal.terminal_override.assign(["/bin/true"])
	var agents: Node = main.local_agents
	agents.pair_on_start = false
	var fake := FakeX.new()
	agents.x = fake
	DirAccess.make_dir_recursive_absolute(home.path_join(".local/bin"))
	for bin in ["claude", "codex"]:
		var f := FileAccess.open(home.path_join(".local/bin").path_join(bin), FileAccess.WRITE)
		f.store_string("#!/bin/sh\n")
		f.close()
	fake.windows = [{"id": 0x400001, "class": "frame-claude", "instance": "xterm", "title": "t"}]
	await _seconds(0.7)
	var r := await _cmd("agents", {}, CLAUDE)
	var list: Array = r["result"]["agents"] if r["ok"] else []
	_check("agents: who runs, and who is calling (%s)" % [r.get("result")], r["ok"] and r["result"]["you"] == "claude"
			and list.any(func(a: Dictionary) -> bool: return a["id"] == "claude" and a["running"] and a["installed"])
			and list.any(func(a: Dictionary) -> bool: return a["id"] == "codex" and not a["running"]))
	r = await _cmd("agent_show", {"id": "claude"}, CLAUDE)
	_check("agent_show: on the pane", r["ok"] and agents.active == "claude" and agents.pane_shown())
	r = await _cmd("agent_hide", {}, CLAUDE)
	_check("agent_hide: its own pane, it keeps running", r["ok"] and not agents.pane_shown()
			and agents.is_running("claude"))
	(r["call"] as DevCommands.Call).undo.call()
	_check("agent_hide's undo shows it again", agents.pane_shown())
	r = await _cmd("agent_show", {"id": "codex"})
	_check("agent_show: not running is refused", not r["ok"] and str(r.get("error")).contains("agent_start"))
	r = await _cmd("agent_start", {"id": "claude"})
	_check("agent_start: running already is refused", not r["ok"])
	r = await _cmd("agent_start", {"id": "codex", "plain": true}, CLAUDE)
	_check("agent_start codex, plain (%s)" % [r.get("result")], r["ok"] and agents.active == "codex"
			and not FileAccess.get_file_as_string(AgentTerminal.player_dir("codex").path_join("run.sh")).contains("P='"))
	fake.windows.append({"id": 0x500001, "class": "frame-codex", "instance": "xterm", "title": ""})
	await _seconds(0.7)
	r = await _cmd("agent_restart", {"id": "claude"}, CLAUDE)
	_check("agent_restart of the caller itself is refused (%s)" % r.get("error"), not r["ok"]
			and str(r.get("error")).contains("that is you"))
	r = await _cmd("agent_restart", {"id": "codex"}, CLAUDE)
	_check("agent_restart of another agent goes ahead", r["ok"] and r["result"]["restarting"] == "codex")
	fake.windows = [fake.windows[0]]
	await _seconds(0.5)
	r = await _cmd("agent_restart", {"id": "claude", "self": true}, CLAUDE)
	_check("agent_restart of itself with self: true", r["ok"])
	fake.windows.clear()
	await _seconds(1.2)
	r = await _cmd("agent_restart", {"id": "claude"})
	_check("agent_restart: not running is refused", not r["ok"])
	agents.set_active("")
	agents.hide_pane()
	agents.x = null
	AgentTerminal.terminal_override.clear()


func _android_checks() -> void:
	var r := await _cmd("android_status")
	_check("android_status (%s)" % str(r.get("result")).left(120), r["ok"] and r["result"]["state"] == "idle")
	r = await _cmd("android_start", {"name": "Nothing Here"}, CLAUDE)
	_check("android_start: no such app (%s)" % r.get("error"), not r["ok"]
			and str(r.get("error")).contains("no app called"))
	r = await _cmd("android_stop", {}, CLAUDE)
	_check("android_stop when idle", r["ok"] and r["result"]["state"] == "idle")
	AgentTerminal.home_override = ""


func _leak_checks() -> void:
	var all := "\n".join(_said)
	for secret: String in [SAVED_PASSWORD, SAVED_USER, NEW_PASSWORD, NEW_USER, EDITED_PASSWORD]:
		_check("no reply or summary holds %s" % secret.left(8), not all.contains(secret))
	_check("describe holds no login", not JSON.stringify(DevCommands.to_json(DevCommands.describe())).contains(
			SAVED_PASSWORD))


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL " + what)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _seconds(s: float) -> void:
	await create_timer(s).timeout


func _clear(p: String) -> void:
	var d := DirAccess.open(p)
	if d == null:
		return
	d.include_hidden = true
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		_clear(p.path_join(sub))
	DirAccess.remove_absolute(p)
