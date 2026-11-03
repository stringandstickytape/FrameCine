extends SceneTree

## The headset pulling a file from the assistant's machine (scripts/assistant/assistant_fetch.gd) and the Browser
## source's current page (scripts/video/browser_devtools.gd), against a small HTTP server in this test on the loopback
## (the loopback is allowed here only: AssistantFetch.allow_loopback). Checks: a download with progress events, its
## name and extension, opened with the mode given; a redirect; the refusals (not http, not a private address, the
## headset itself, a bad mode, one at a time); the disk check; a body longer than announced; cancel deleting the
## partial file; /state's download and browser; the DevTools page read from a fake /json.
##
## godot --headless --xr-mode off --path app --script res://tests/test_assistant_fetch.gd

const AssistantCommands := preload("res://scripts/assistant/assistant_commands.gd")
const AssistantFetch := preload("res://scripts/assistant/assistant_fetch.gd")
const BrowserDevtools := preload("res://scripts/video/browser_devtools.gd")
const WindowVideoSource := preload("res://scripts/video/window_video_source.gd")
const BrowserHistory := preload("res://scripts/video/browser_history.gd")
const WorkerTask := preload("res://scripts/dev/worker_task.gd")


## One WebSocket client at a time, answering Page.navigate as Chromium's DevTools does.
class FakePageSocket extends Node:
	var server := TCPServer.new()
	var port := 0
	var peer: WebSocketPeer
	var got: Array[Dictionary] = []

	func start() -> void:
		server.listen(0, "127.0.0.1")
		port = server.get_local_port()

	func _process(_delta: float) -> void:
		if server.is_connection_available():
			peer = WebSocketPeer.new()
			peer.accept_stream(server.take_connection())
		if peer == null:
			return
		peer.poll()
		while peer.get_available_packet_count() > 0:
			var m: Variant = JSON.parse_string(peer.get_packet().get_string_from_utf8())
			if m is Dictionary:
				got.append(m)
				peer.send_text(JSON.stringify({"id": m["id"], "result": {"frameId": "F1"}}))

## A tiny HTTP/1.0 server: routes path -> {status, headers, body, rate (bytes a second, 0 = all at once)}.
class TestServer extends Node:
	var server := TCPServer.new()
	var port := 0
	var routes := {}
	var requests: Array[String] = []
	var _conns: Array[Dictionary] = []

	func start() -> void:
		server.listen(0, "127.0.0.1")
		port = server.get_local_port()

	func _process(delta: float) -> void:
		while server.is_connection_available():
			_conns.append({"peer": server.take_connection(), "in": "", "out": PackedByteArray(), "sent": 0,
					"rate": 0, "budget": 0.0})
		for c: Dictionary in _conns.duplicate():
			var peer: StreamPeerTCP = c["peer"]
			peer.poll()
			if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				_conns.erase(c)
				continue
			if (c["out"] as PackedByteArray).is_empty() and peer.get_available_bytes() > 0:
				c["in"] += peer.get_utf8_string(peer.get_available_bytes())
				if str(c["in"]).contains("\r\n\r\n"):
					_answer(c, str(c["in"]).get_slice(" ", 1))
			var out: PackedByteArray = c["out"]
			if out.is_empty():
				continue
			var n := out.size() - int(c["sent"])
			if int(c["rate"]) > 0:
				c["budget"] = float(c["budget"]) + delta * int(c["rate"])
				n = mini(n, int(c["budget"]))
				c["budget"] = float(c["budget"]) - n
			if n > 0:
				var r: Array = peer.put_partial_data(out.slice(int(c["sent"]), int(c["sent"]) + n))
				c["sent"] = int(c["sent"]) + int(r[1])
			if int(c["sent"]) >= out.size():
				peer.disconnect_from_host()
				_conns.erase(c)

	func _answer(c: Dictionary, path: String) -> void:
		requests.append(path)
		var r: Dictionary = routes.get(path, {"status": 404, "body": "no".to_utf8_buffer()})
		var body: PackedByteArray = r.get("body", PackedByteArray())
		var head := "HTTP/1.0 %d X\r\n" % int(r.get("status", 200))
		var headers: Dictionary = r.get("headers", {})
		if not headers.has("Content-Length") and not bool(r.get("no_length", false)):
			headers["Content-Length"] = str(body.size())
		for k: String in headers:
			head += "%s: %s\r\n" % [k, headers[k]]
		var out := (head + "\r\n").to_utf8_buffer()
		out.append_array(body)
		c["out"] = out
		c["rate"] = int(r.get("rate", 0))


var _failures := 0
var _checks := 0
var main: Node3D
var commands: AssistantCommands
var srv: TestServer
var events: Array[Dictionary] = []
var dir := ""


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _run() -> void:
	await _frames(5)
	dir = OS.get_user_data_dir().path_join("test_fetch")
	_clear()
	AssistantFetch.folder_override = dir
	srv = TestServer.new()
	srv.start()
	root.add_child(srv)
	commands = AssistantCommands.new()
	commands.allow_control = func() -> bool: return true
	commands.allow_files = func() -> bool: return true
	commands.allow_room = func() -> bool: return false
	var fetch: Node = AssistantFetch.ensure(self)
	await _frames(2)
	fetch.event.connect(func(d: Dictionary) -> void: events.append(d))
	var clip := PackedByteArray()
	clip.resize(3 * 1024 * 1024)
	for i in clip.size():
		clip[i] = i % 251
	srv.routes["/films/Rollercoaster_360.mkv"] = {"body": clip, "rate": 1200 * 1024}
	srv.routes["/old"] = {"status": 302, "headers": {"Location": "/films/small.mp4"}}
	srv.routes["/films/small.mp4"] = {"body": clip.slice(0, 1000)}
	srv.routes["/noext"] = {"body": clip.slice(0, 500), "headers": {"Content-Type": "video/x-matroska"}}
	srv.routes["/liar.mp4"] = {"body": clip.slice(0, 5000), "headers": {"Content-Length": "1000"}}
	srv.routes["/slow.mp4"] = {"body": clip, "rate": 200 * 1024}
	var base := "http://127.0.0.1:%d" % srv.port

	# --- Refusals. ---
	for bad: Array in [["ftp://192.168.1.2/x.mkv", "http"], ["http://8.8.8.8/x.mkv", "not on this network"],
			["http://user:pw@192.168.1.2/x.mkv", "passwords"], [base + "/films/small.mp4", "this headset itself"]]:
		var r: Dictionary = await commands.run("fetch", {"url": bad[0]})
		_check("refused: %s (%s)" % [bad[0], r.get("error", "")], r.get("ok") == false
				and str(r.get("error", "")).contains(bad[1]))
	AssistantFetch.allow_loopback = true
	var r: Dictionary = await commands.run("fetch", {"url": base + "/films/small.mp4", "mode": "dome"})
	_check("a mode that isn't one is said (%s)" % r.get("error", ""), r.get("ok") == false
			and str(r.get("error", "")).contains("360"))
	commands.allow_files = func() -> bool: return false
	r = await commands.run("fetch", {"url": base + "/films/small.mp4"})
	_check("needs the viewer's files permission", r.get("refused") == true
			and r.get("switch") == "Let the assistant manage files")
	commands.allow_files = func() -> bool: return true

	# --- A download with progress, opened with the mode given. ---
	events.clear()
	var t0 := Time.get_ticks_msec()
	r = await commands.run("fetch", {"url": base + "/films/Rollercoaster_360.mkv", "mode": "360"})
	_check("fetch starts (%s)" % str(r).left(160), r.get("ok") == true
			and r["result"]["name"] == "Rollercoaster_360.mkv")
	var again: Dictionary = await commands.run("fetch", {"url": base + "/films/small.mp4"})
	_check("one at a time (%s)" % again.get("error", ""), again.get("ok") == false
			and str(again.get("error", "")).contains("one at a time"))
	await _frames(20)
	var st: Dictionary = AssistantCommands.state(main, true)
	_check("/state shows the download (%s)" % [st.get("download")], st.get("download") is Dictionary
			and st["download"]["name"] == "Rollercoaster_360.mkv")
	var last := await _until_done()
	var progress := events.filter(func(e: Dictionary) -> bool: return e["state"] == "progress")
	var path := dir.path_join("Rollercoaster_360.mkv")
	_check("done, with the path (%s after %.1f s)" % [last, (Time.get_ticks_msec() - t0) / 1000.0],
			last.get("state") == "done" and last.get("path") == path)
	var steps := progress.map(func(e: Dictionary) -> String: return "%d/%d" % [e["bytes"], e["total"]])
	_check("progress events, at most once a second (%d: %s)" % [progress.size(), steps], progress.size() >= 1
			and progress.size() <= 4
			and progress.all(func(e: Dictionary) -> bool: return int(e["total"]) == clip.size() and e.has("rate")))
	_check("the file is whole, no .part left", FileAccess.get_file_as_bytes(path) == clip
			and not FileAccess.file_exists(path + ".part"))
	_check("opened with the mode given (%s, %s)" % [main.current_path, main.settings.get_file_mode(path)],
			main.current_path == path and main.settings.get_file_mode(path) == "360_mono")
	_check("/state: no download now", AssistantCommands.state(main, true).get("download") == null)
	_check("the folder is in the places", main.get_node("/root").has_node(AssistantFetch.NODE_NAME)
			and preload("res://ui/files_tab.gd").get_places().any(func(p: Dictionary) -> bool:
				return p["path"] == dir))

	# --- A redirect; a name without an extension takes the content type's; a taken name gets a number. ---
	events.clear()
	r = await commands.run("fetch", {"url": base + "/old", "open": false})
	last = await _until_done()
	_check("a redirect is followed (%s)" % [last], last.get("state") == "done"
			and str(last.get("path")).get_file() == "small.mp4" and srv.requests.has("/films/small.mp4"))
	events.clear()
	r = await commands.run("fetch", {"url": base + "/noext", "name": "../My film", "open": false})
	last = await _until_done()
	_check("a plain name, the extension from the content type (%s)" % [last.get("path")], last.get("state") == "done"
			and str(last.get("path")).get_file() == "_My film.mkv")
	events.clear()
	r = await commands.run("fetch", {"url": base + "/films/small.mp4", "open": false})
	last = await _until_done()
	_check("a name already there gets a number (%s)" % [last.get("path")],
			str(last.get("path")).get_file() == "small (2).mp4")

	# --- The disk and the size. ---
	AssistantFetch.free_space_override = AssistantFetch.KEEP_FREE + 1000
	events.clear()
	r = await commands.run("fetch", {"url": base + "/films/Rollercoaster_360.mkv", "open": false})
	last = await _until_done()
	_check("refused when it would leave under 2 GB free (%s)" % last.get("reason"), last.get("state") == "failed"
			and str(last.get("reason")).contains("keeps 2.0 GB free")
			and not FileAccess.file_exists(dir.path_join("Rollercoaster_360 (2).mkv.part")))
	AssistantFetch.free_space_override = -1
	events.clear()
	r = await commands.run("fetch", {"url": base + "/liar.mp4", "open": false})
	last = await _until_done()
	# HTTPClient reads exactly the announced length: nothing past it is ever written (the worker's own check is the
	# second line of defence).
	_check("a body longer than announced: no more than announced is kept (%s, %d bytes)" % [last.get("state"),
			FileAccess.get_file_as_bytes(dir.path_join("liar.mp4")).size()], (last.get("state") == "done"
			and FileAccess.get_file_as_bytes(dir.path_join("liar.mp4")).size() == 1000) or (last.get("state") == "failed"
			and str(last.get("reason")).contains("more than") and not FileAccess.file_exists(dir.path_join("liar.mp4")))
			and not FileAccess.file_exists(dir.path_join("liar.mp4.part")))
	# A connection that closes before the announced size: failed, the partial file goes.
	srv.routes["/short.mp4"] = {"body": clip.slice(0, 1000), "headers": {"Content-Length": "5000"}}
	events.clear()
	r = await commands.run("fetch", {"url": base + "/short.mp4", "open": false})
	last = await _until_done()
	_check("cut short: failed, the partial file goes (%s)" % last.get("reason"), last.get("state") == "failed"
			and not FileAccess.file_exists(dir.path_join("short.mp4.part"))
			and not FileAccess.file_exists(dir.path_join("short.mp4")))

	# --- Cancel (from the command; the card's Cancel button calls the same). ---
	events.clear()
	r = await commands.run("fetch", {"url": base + "/slow.mp4", "open": false})
	var wait_end := Time.get_ticks_msec() + 10000
	while events.filter(func(e: Dictionary) -> bool: return e["state"] in ["progress", "done", "failed"]).is_empty() \
			and Time.get_ticks_msec() < wait_end:
		await process_frame
	_check("a partial file while downloading", FileAccess.file_exists(dir.path_join("slow.mp4.part")))
	var c: Dictionary = await commands.run("fetch_cancel", {})
	last = await _until_done()
	_check("cancelled, and the partial file is gone (%s)" % [c], c.get("ok") == true
			and last.get("state") == "cancelled" and not FileAccess.file_exists(dir.path_join("slow.mp4.part"))
			and not FileAccess.file_exists(dir.path_join("slow.mp4")))
	c = await commands.run("fetch_cancel", {})
	_check("nothing to cancel then", c.get("ok") == false)
	var card: Node = main.ui.get("card") if main.get("ui") != null else null
	if card != null:
		_check("the card offers Cancel while downloading", card.has_method("set_card_text"))

	# --- The Browser source's page. ---
	var targets := [{"type": "background_page", "url": "chrome-extension://x/bg.html", "title": "ext"},
			{"type": "page", "url": "https://www.youtube.com/watch?v=abc", "title": "Rollercoaster 360 - YouTube",
				"id": "1"},
			{"type": "service_worker", "url": "https://www.youtube.com/sw.js", "title": ""}]
	srv.routes["/json"] = {"body": JSON.stringify(targets).to_utf8_buffer(),
			"headers": {"Content-Type": "application/json"}}
	var dv: Dictionary = await BrowserDevtools.read(self, srv.port)
	_check("DevTools /json read (%s)" % str(dv).left(120), dv.has("targets") and (dv["targets"] as Array).size() == 3)
	var page := BrowserDevtools.page_of(dv["targets"], "Rollercoaster 360 - YouTube - Chromium")
	_check("the page target (%s)" % [page], page.get("url") == "https://www.youtube.com/watch?v=abc")
	var free := BrowserDevtools.free_port()
	_check("a free loopback port per launch (%d)" % free, free > 0
			and BrowserDevtools.flags(free) == ["--remote-debugging-port=%d" % free])
	# Never this machine's own browser history.
	BrowserHistory.path_override = dir.path_join("no history here")
	var src := WindowVideoSource.new()
	src.url = "https://www.youtube.com"
	src._title = "Rollercoaster 360 - YouTube"
	var info: Dictionary = src.page_info()
	_check("without DevTools: the title only (%s)" % [info], info.get("url") == null
			and info.get("title") == "Rollercoaster 360 - YouTube" and info.get("via") == "window title")
	src.devtools_port = srv.port
	await src.refresh_page()
	info = src.page_info()
	_check("with DevTools: the current url (%s)" % [info], info.get("url") == "https://www.youtube.com/watch?v=abc"
			and info.get("via") == "devtools" and info.get("opened_url") == "https://www.youtube.com")
	src.devtools_port = BrowserDevtools.free_port()
	src._page = {}
	await src.refresh_page()
	info = src.page_info()
	_check("a closed port: the title, and why (%s)" % [info.get("note")], info.get("url") == null
			and str(info.get("note", "")).contains("did not answer"))
	# The history fallback: a Chromium-like database made with python3's sqlite3.
	var db := dir.path_join("History")
	DirAccess.make_dir_recursive_absolute(dir)
	var py := "import sqlite3, sys\n" \
			+ "c = sqlite3.connect(sys.argv[1])\n" \
			+ "c.execute('create table urls (id integer primary key, url text, title text)')\n" \
			+ "c.execute('create table visits (id integer primary key, url integer, visit_time integer)')\n" \
			+ "rows = [(1, 'https://www.youtube.com/watch?v=abc', 'Rollercoaster 360 - YouTube'), " \
			+ "(2, 'https://www.youtube.com/', 'YouTube'), (3, 'chrome://newtab/', 'New Tab')]\n" \
			+ "c.executemany('insert into urls values (?, ?, ?)', rows)\n" \
			+ "c.executemany('insert into visits (url, visit_time) values (?, ?)', [(1, 100), (2, 200), (3, 300)])\n" \
			+ "c.commit()\n"
	var made := OS.execute("python3", ["-c", py, ProjectSettings.globalize_path(db)])
	BrowserHistory.path_override = ProjectSettings.globalize_path(db)
	var h: Dictionary = (await WorkerTask.run(self, func() -> Variant:
		return BrowserHistory.read_now("Rollercoaster 360 - YouTube"), 10.0))["result"]
	_check("history: the visit titled as the window, not the newest (%s; made %d)" % [h, made], made == 0
			and h.get("url") == "https://www.youtube.com/watch?v=abc" and h.get("via") == "history"
			and h.get("reader") == "python3" and not h.has("note"))
	h = (await WorkerTask.run(self, func() -> Variant: return BrowserHistory.read_now("Something else"), 10.0))["result"]
	_check("history: no title match: the newest http(s) page, with a note (%s)" % [h],
			h.get("url") == "https://www.youtube.com/" and str(h.get("note", "")).contains("doesn't match"))
	_check("history: the copy is gone at once", Array(DirAccess.get_directories_at(OS.get_user_data_dir())).filter(
			func(d: String) -> bool: return d.begins_with("history_")).is_empty())
	_check("titles match with a suffix, not by accident", BrowserHistory.titles_match("Rollercoaster 360",
			"Rollercoaster 360 - YouTube") and not BrowserHistory.titles_match("Roller", "Rollercoaster")
			and not BrowserHistory.titles_match("", "x"))
	var hs := WindowVideoSource.new()
	hs._title = "Rollercoaster 360 - YouTube"
	hs.window_id = 1
	await hs.refresh_page()
	var hinfo: Dictionary = hs.page_info()
	_check("a browser without DevTools: the page from the history (%s)" % [hinfo],
			hinfo.get("via") == "history" and hinfo.get("url") == "https://www.youtube.com/watch?v=abc")
	BrowserHistory.path_override = ""
	DirAccess.remove_absolute(db)
	# Going to a page over DevTools (Page.navigate on the page's socket).
	var sock := FakePageSocket.new()
	sock.start()
	root.add_child(sock)
	var nav: String = await BrowserDevtools.navigate(self, "ws://127.0.0.1:%d/devtools/page/1" % sock.port,
			"https://www.bbc.co.uk/iplayer")
	_check("navigate over DevTools (%s, %s)" % [nav, sock.got], nav == "" and sock.got.size() == 1
			and sock.got[0]["method"] == "Page.navigate" and sock.got[0]["params"]["url"] == "https://www.bbc.co.uk/iplayer")
	nav = await BrowserDevtools.navigate(self, "ws://example.com/devtools/page/1", "https://x.org")
	_check("never a socket off the loopback", nav != "")
	sock.queue_free()
	# The player's own browser windows, remembered for the next launch.
	WindowVideoSource._save_launched_ids([0x2a00007, 0x2a0000b])
	_check("launched windows remembered", WindowVideoSource._launched_ids() == [0x2a00007, 0x2a0000b])
	WindowVideoSource._save_launched_ids([])
	r = await commands.run("browser_page", {})
	_check("browser_page with no browser shown: null", r.get("ok") == true and r.get("result") == null)
	_check("/state's browser: null with no browser", AssistantCommands.state(main, true).has("browser")
			and AssistantCommands.state(main, true)["browser"] == null)

	AssistantFetch.allow_loopback = false
	AssistantFetch.folder_override = ""
	_clear()
	print("test_assistant_fetch: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(1 if _failures > 0 else 0)


## The next final event (done, failed or cancelled).
func _until_done() -> Dictionary:
	var end := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < end:
		for e: Dictionary in events:
			if e["state"] in ["done", "failed", "cancelled"]:
				return e
		await process_frame
	return {"state": "timeout"}


func _clear() -> void:
	if DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(f))
		DirAccess.remove_absolute(dir)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL " + what)
