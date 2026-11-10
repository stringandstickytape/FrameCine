extends "res://scripts/video/video_source.gd"

## A desktop window as the video: X11WindowSource (engine module x11window, fork branch frame/window) captures any X11
## window of the device's desktop as one texture, zero copy where it can, and sends that window input. See
## docs/window-source.md. Paths:
##   browser://<url>   launches the browser on <url> (BROWSER_ARGS, the command in docs/window-source.md), waits for
##                     its new window and captures it. close() closes that window (WM_DELETE_WINDOW).
##   window://0x<id>   captures a window that is already open. close() leaves it open.
##   terminal://<id>   an agent's terminal (scripts/agents/agent_terminal.gd). close() leaves it open.
## The picture is RGB with sRGB values (get_rgb_texture(); video.gdshader decodes it). No audio: the browser's sound
## goes through the desktop's audio server. Flat 2D, no seeking. play() / pause() only track the state; the controls
## for the page (Space, clicks) go through send_*() from scripts/window_input.gd.
## The engine class is looked up by name, so this script parses on engines without the module (is_available()).

const BrowserDevtools := preload("res://scripts/video/browser_devtools.gd")
const BrowserHistory := preload("res://scripts/video/browser_history.gd")
const WorkerTask := preload("res://scripts/dev/worker_task.gd")
## The browser windows the player launched, by X window id: an earlier run's are closed before the next launch, so the
## new browser starts with its DevTools port (a running Chromium takes a launch over and ignores the flag).
const LAUNCHED_FILE := "user://browser_windows.json"
## Before launching: how long to wait for an earlier run's windows to go, and then for their browser to exit (ms).
const LEFTOVER_TIMEOUT_MSEC := 8000
const LEFTOVER_SETTLE_MSEC := 1500
const AgentTerminal := preload("res://scripts/agents/agent_terminal.gd")
const ENGINE_CLASS := "X11WindowSource"
## How often the current page is read from the browser's DevTools endpoint while it is shown (ms).
const PAGE_EVERY_MSEC := 3000
const BROWSER_PREFIX := "browser://"
const WINDOW_PREFIX := "window://"
## An agent's terminal on the big screen (scripts/agents/): terminal://claude. It is found by its window class, started
## if it isn't running, and never closed by the player.
const TERMINAL_PREFIX := "terminal://"
## The browser command (docs/window-source.md, "In short"); "--app=<url>" follows.
const BROWSER_COMMAND := "flatpak"
const BROWSER_ARGS: Array[String] = ["run", "org.chromium.Chromium", "--ozone-platform=x11", "--window-size=1920,1080",
		"--window-position=0,0", "--no-first-run", "--disable-backgrounding-occluded-windows",
		"--disable-renderer-backgrounding", "--disable-background-timer-throttling",
		"--autoplay-policy=no-user-gesture-required"]
## The browser's window: a new window whose class or instance contains this (lower case). Not matched by pid: an
## already running browser opens the window in its own process.
const BROWSER_MATCH := "chrom"
const LAUNCH_TIMEOUT_MSEC := 20000
const POLL_MSEC := 250

## Overrides for desktop tests (--browser-command, --browser-match): the command and its arguments, and the class text.
static var browser_command: Array[String] = []
static var browser_match := BROWSER_MATCH
## Windows the app put on the screen under a name of its own, by X window id (scripts/android/android_apps.gd). The
## window's title is no use to the viewer, it isn't a web page, and what it shows stays out of the room snapshots.
static var named_windows := {}

## The X11WindowSource (null when closed).
var win: Object
## The captured window, 0 while waiting for the browser's window.
var window_id := 0
## True when this source started the window (close() closes it).
var launched := false
var url := ""
## The agent whose terminal this is (terminal://), or "".
var terminal_id := ""
## The launched process (the browser command), or -1.
var launched_pid := -1
var _known_ids := {}
var _waiting := false
var _wait_start_msec := 0
var _last_poll_msec := 0
var _playing := true
var _ended := false
var _title := ""
## The launched browser's DevTools port on 127.0.0.1 (browser_devtools.gd), 0 when it has none.
var devtools_port := 0
## The current page as last read: {url, title}, or {} (not read yet, or no DevTools).
var _page := {}
var _page_error := ""
var _page_reading := false
var _page_next_msec := 0
## The window title the history was last read for (the history is read again when the title changes).
var _history_title := "\u0000"
## Waiting for an earlier run's browser windows to close before launching: their ids, and since when.
var _leftovers: Array[int] = []
var _leftover_start_msec := 0
var _leftover_gone_msec := 0


static func is_available() -> bool:
	return ClassDB.class_exists(ENGINE_CLASS)


static func is_window_path(p: String) -> bool:
	return p.begins_with(BROWSER_PREFIX) or p.begins_with(WINDOW_PREFIX) or p.begins_with(TERMINAL_PREFIX)


static func terminal_path(id: String) -> String:
	return TERMINAL_PREFIX + id


static func browser_path(page_url: String) -> String:
	return BROWSER_PREFIX + page_url


static func window_path(id: int) -> String:
	return WINDOW_PREFIX + "0x%x" % id


static func window_id_of(p: String) -> int:
	var text := p.trim_prefix(WINDOW_PREFIX)
	return text.hex_to_int() if text.begins_with("0x") else text.to_int()


## A short name for a path (menu title, overlay) before the window's own title is known.
static func describe_path(p: String) -> String:
	if p.begins_with(BROWSER_PREFIX):
		return p.trim_prefix(BROWSER_PREFIX)
	if p.begins_with(TERMINAL_PREFIX):
		var id := p.trim_prefix(TERMINAL_PREFIX)
		return str(AgentTerminal.AGENTS[id]["name"]) if AgentTerminal.AGENTS.has(id) else id
	return "Window " + p.trim_prefix(WINDOW_PREFIX)


## The windows of the desktop that can be shown: {"windows": [{id, title, class, instance, width, height, browser}],
## "error": ""}. Mapped windows only, without the player's own window; browser windows first.
static func list_desktop_windows() -> Dictionary:
	if not is_available():
		return {"windows": [], "error": "this engine build has no window capture"}
	var w: Object = ClassDB.instantiate(ENGINE_CLASS)
	var err: Error = w.call("open")
	if err != OK:
		return {"windows": [], "error": "no X display: %s" % w.call("get_last_error")}
	var own := int(w.call("get_own_window"))
	var own_top := int(w.call("get_toplevel", own)) if own != 0 else 0
	var out: Array[Dictionary] = []
	for e: Dictionary in w.call("list_windows"):
		var id := int(e.get("id", 0))
		if id == 0 or id == own or id == own_top or int(e.get("frame", 0)) == own_top and own_top != 0:
			continue
		var cls := (str(e.get("class", "")) + " " + str(e.get("instance", ""))).to_lower()
		out.append({"id": id, "title": str(e.get("title", "")), "class": str(e.get("class", "")),
				"instance": str(e.get("instance", "")), "width": int(e.get("width", 0)),
				"height": int(e.get("height", 0)), "browser": BROWSER_MATCH in cls})
	w.call("close")
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["browser"] != b["browser"]:
			return a["browser"]
		return str(a["title"]).naturalnocasecmp_to(str(b["title"])) < 0)
	return {"windows": out, "error": ""}


func get_kind() -> String:
	return "window"


func open(p: String) -> Error:
	path = p
	if not is_available():
		last_error = "this engine build has no window capture (X11WindowSource)"
		return ERR_UNAVAILABLE
	win = ClassDB.instantiate(ENGINE_CLASS)
	# An agent's terminal may be on a display of its own, not the desktop's (agent_terminal.gd).
	var display := ""
	if p.begins_with(TERMINAL_PREFIX) and AgentTerminal.wait_display():
		display = AgentTerminal.display()
	var err: Error = win.call("open", display)
	if err != OK:
		last_error = "no X display: %s" % win.call("get_last_error")
		win = null
		return err
	win.connect("window_closed", _on_window_closed)
	win.connect("size_changed", func(_size: Vector2i) -> void: format_changed.emit())
	win.connect("title_changed", func() -> void: _title = _read_title())
	if p.begins_with(WINDOW_PREFIX):
		err = _capture(window_id_of(p), false)
		if err != OK:
			_close_connection()
		return err
	if p.begins_with(TERMINAL_PREFIX):
		terminal_id = p.trim_prefix(TERMINAL_PREFIX)
		if not AgentTerminal.AGENTS.has(terminal_id):
			last_error = "no agent %s" % terminal_id
			_close_connection()
			return ERR_INVALID_PARAMETER
		var id := AgentTerminal.find_window(win, terminal_id)
		if id != 0:
			err = _capture(id, false)
			if err != OK:
				_close_connection()
			return err
		var why := AgentTerminal.start(terminal_id)
		if why != "":
			last_error = why
			_close_connection()
			return ERR_CANT_CREATE
		_waiting = true
		_wait_start_msec = Time.get_ticks_msec()
		_last_poll_msec = 0
		return OK
	url = p.trim_prefix(BROWSER_PREFIX)
	return _launch()


## Starts the browser on `url`; update() looks for its window. An earlier run's browser windows (the player was
## stopped without closing them) are closed first, so this launch starts a browser with its DevTools port.
func _launch() -> Error:
	if browser_command.is_empty():
		var open_now := {}
		for e: Dictionary in win.call("list_windows", true):
			open_now[int(e.get("id", 0))] = true
		_leftovers.clear()
		for id: int in _launched_ids():
			if open_now.has(id):
				_leftovers.append(id)
		if not _leftovers.is_empty():
			print("Browser: closing %d window(s) an earlier run left open, then launching" % _leftovers.size())
			for id in _leftovers:
				win.call("close_window", id)
			_leftover_start_msec = Time.get_ticks_msec()
			_leftover_gone_msec = 0
			_waiting = true
			_wait_start_msec = Time.get_ticks_msec()
			return OK
		_save_launched_ids([])
	return _start_process()


func _start_process() -> Error:
	_known_ids.clear()
	for e: Dictionary in win.call("list_windows", true):
		_known_ids[int(e.get("id", 0))] = true
	var command := BROWSER_COMMAND
	var args: Array[String] = BROWSER_ARGS.duplicate()
	if not browser_command.is_empty():
		command = browser_command[0]
		args = browser_command.slice(1)
	if browser_command.is_empty():
		# The current page for the assistant (page_info()): DevTools on a random loopback port, this launch only.
		devtools_port = BrowserDevtools.free_port()
		args.append_array(BrowserDevtools.flags(devtools_port))
	args.append("--app=" + url)
	var pid := OS.create_process(command, PackedStringArray(args))
	launched_pid = pid
	if pid < 0:
		last_error = "could not start the browser (%s)" % command
		_close_connection()
		return ERR_CANT_CREATE
	print("Browser: started %s %s (pid %d); waiting for its window" % [command, " ".join(args), pid])
	_waiting = true
	_wait_start_msec = Time.get_ticks_msec()
	_last_poll_msec = 0
	return OK


## A window that is new since the launch and looks like the browser's, or 0.
func _find_new_window() -> int:
	if terminal_id != "":
		return AgentTerminal.find_window(win, terminal_id)
	for e: Dictionary in win.call("list_windows"):
		var id := int(e.get("id", 0))
		if id == 0 or _known_ids.has(id):
			continue
		var cls := (str(e.get("class", "")) + " " + str(e.get("instance", ""))).to_lower()
		if browser_match in cls:
			return id
	return 0


func _capture(id: int, ours: bool) -> Error:
	var err: Error = win.call("capture", id)
	if err != OK:
		last_error = "could not capture window 0x%x: %s" % [id, win.call("get_last_error")]
		return err
	window_id = id
	launched = ours
	_waiting = false
	_title = _read_title()
	# Launching mapped the browser's window, which took the desktop's focus: map ours again so the player has it.
	var own := int(win.call("get_own_window"))
	if ours and own != 0:
		win.call("remap_window", own)
	if ours and browser_command.is_empty():
		var ids := _launched_ids()
		if not id in ids:
			ids.append(id)
		_save_launched_ids(ids)
	var size: Vector2i = win.call("get_size")
	print("Window: captured 0x%x \"%s\" %dx%d (%s)" % [id, _title, size.x, size.y,
			"launched by the player" if ours else "already open"])
	format_changed.emit()
	return OK


func _read_title() -> String:
	if terminal_id != "":
		# Always the agent's name: what a terminal's title says stays in the headset.
		return describe_path(path)
	if is_named():
		return str(named_windows[window_id])
	if win == null or window_id == 0:
		return ""
	var info: Dictionary = win.call("get_window_info", window_id)
	return str(info.get("title", ""))


func _on_window_closed() -> void:
	print("Window: 0x%x was closed" % window_id)
	window_id = 0
	launched = false
	_ended = true
	last_error = "The window was closed."


## Closes the window if this source launched it (never one it only captured), then lets go of the capture.
func close() -> void:
	if win == null:
		return
	if window_id != 0 and launched:
		print("Window: closing 0x%x (launched by the player)" % window_id)
		win.call("close_window", window_id)
		var ids := _launched_ids()
		ids.erase(window_id)
		_save_launched_ids(ids)
	if _waiting:
		print("Window: closed while the browser was starting; its window stays open if it comes")
	_close_connection()


func _close_connection() -> void:
	# The DevTools port closes with the browser.
	devtools_port = 0
	_page = {}
	if win == null:
		return
	win.call("stop_capture")
	win.call("close")
	win = null
	window_id = 0
	_waiting = false


static func _launched_ids() -> Array[int]:
	var out: Array[int] = []
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAUNCHED_FILE)) \
			if FileAccess.file_exists(LAUNCHED_FILE) else null
	if data is Array:
		for v: Variant in data:
			out.append(int(v))
	return out


static func _save_launched_ids(ids: Array[int]) -> void:
	var f := FileAccess.open(LAUNCHED_FILE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(ids))


## A web browser, not a terminal or another window (the assistant link's `browser`).
func is_browser() -> bool:
	return terminal_id == "" and not is_named() and (launched or url != "" or window_id != 0)


func is_terminal() -> bool:
	return terminal_id != ""


func is_named() -> bool:
	return named_windows.has(window_id)


## Reads the current page now (await it for a fresh page_info()): from the DevTools endpoint, else (no port, or it
## doesn't answer) from the browser's history when the window's title changed since the last read.
func refresh_page(force_history := false) -> void:
	if _page_reading:
		return
	_page_reading = true
	var tree := Engine.get_main_loop() as SceneTree
	if devtools_port > 0:
		var r: Dictionary = await BrowserDevtools.read(tree, devtools_port)
		if r.has("targets"):
			_page = BrowserDevtools.page_of(r["targets"], _title)
			_page_error = "" if not _page.is_empty() else "no page among the browser's targets"
		else:
			_page = {}
			_page_error = str(r["error"])
	if (devtools_port <= 0 or _page.is_empty()) and (force_history or _history_title != _title):
		_history_title = _title
		var title := _title
		var h: Dictionary = await WorkerTask.run(tree, func() -> Variant: return BrowserHistory.read_now(title), 10.0)
		var got: Variant = h.get("result")
		if bool(h["done"]) and got is Dictionary and not (got as Dictionary).has("error"):
			_history = got
		else:
			_history = {}
			_history_error = str(got.get("error", "")) if got is Dictionary else "reading the history took too long"
	_page_reading = false
	_page_next_msec = Time.get_ticks_msec() + PAGE_EVERY_MSEC


var _history := {}
var _history_error := ""


## The page over DevTools (Page.navigate): "" when it went, else the reason (the caller then opens it anew).
func navigate(to_url: String) -> String:
	if devtools_port <= 0 or window_id == 0:
		return "no DevTools port"
	await refresh_page()
	if _page.is_empty():
		return "the DevTools port did not answer"
	var err: String = await BrowserDevtools.navigate(Engine.get_main_loop() as SceneTree, str(_page.get("ws", "")),
			to_url)
	if err == "":
		url = to_url
		_page_next_msec = 0
	return err


## The page's DevTools WebSocket (127.0.0.1 only), "" until the page was read or without DevTools. It stays inside
## the player (scripts/video/browser_dictation.gd), like the target id.
func page_ws() -> String:
	return str(_page.get("ws", "")) if devtools_port > 0 else ""


## The page shown: {url, title, via: devtools | window title, opened_url, note?}. Without DevTools only the window's
## title is known (url null).
func page_info() -> Dictionary:
	if not _page.is_empty():
		return {"url": _page["url"], "title": _page["title"] if str(_page["title"]) != "" else _title,
				"via": "devtools", "opened_url": url}
	if not _history.is_empty():
		var h := {"url": _history["url"], "title": _history["title"] if str(_history["title"]) != "" else _title,
				"via": "history", "opened_url": url}
		if _history.has("note"):
			h["note"] = _history["note"]
		return h
	var out := {"url": null, "title": _title, "via": "window title", "opened_url": url}
	if devtools_port <= 0:
		out["note"] = "this browser has no DevTools port (not launched by the player)"
	elif _page_error != "":
		out["note"] = "the browser's DevTools port did not answer (%s)" % _page_error
	if _history_error != "":
		out["note"] = str(out.get("note", "")) + "; " + _history_error if out.has("note") else _history_error
	return out


func play() -> void:
	_playing = true


func pause() -> void:
	_playing = false


func is_playing() -> bool:
	return _playing


func update(_delta: float, _master_clock: float) -> void:
	if win == null:
		return
	if is_browser() and window_id != 0 and not _page_reading and Time.get_ticks_msec() >= _page_next_msec \
			and (devtools_port > 0 or _history_title != _title):
		refresh_page()
	if not _leftovers.is_empty():
		# An earlier run's browser windows closing: once gone (or after the timeout), give their browser a moment
		# to exit, then launch.
		var now := Time.get_ticks_msec()
		var open_now := {}
		for e: Dictionary in win.call("list_windows", true):
			open_now[int(e.get("id", 0))] = true
		var still := _leftovers.filter(func(id: int) -> bool: return open_now.has(id))
		if still.is_empty() and _leftover_gone_msec == 0:
			_leftover_gone_msec = now
		var settled := _leftover_gone_msec > 0 and now - _leftover_gone_msec >= LEFTOVER_SETTLE_MSEC
		if settled or now - _leftover_start_msec > LEFTOVER_TIMEOUT_MSEC:
			_leftovers.clear()
			_save_launched_ids([])
			if _start_process() != OK:
				_waiting = false
				_ended = true
		return
	if _waiting:
		var now := Time.get_ticks_msec()
		if now - _last_poll_msec >= POLL_MSEC:
			_last_poll_msec = now
			var id := _find_new_window()
			if id != 0:
				if _capture(id, terminal_id == "") != OK:
					_waiting = false
					_ended = true
			elif now - _wait_start_msec > LAUNCH_TIMEOUT_MSEC:
				_waiting = false
				_ended = true
				last_error = "No browser window appeared within %d s." % (LAUNCH_TIMEOUT_MSEC / 1000)
				push_warning("Browser: " + last_error)
	if window_id != 0:
		win.call("update")


func is_waiting() -> bool:
	return _waiting


func has_frame() -> bool:
	return window_id != 0


func is_ended() -> bool:
	return _ended


func get_rgb_texture() -> Texture2D:
	return win.call("get_texture") if win != null and window_id != 0 else null


func get_size() -> Vector2i:
	return win.call("get_size") if win != null and window_id != 0 else Vector2i.ZERO


func get_title() -> String:
	return _title


func get_video_info() -> Dictionary:
	var size := get_size()
	return {"codec": "window", "width": size.x, "height": size.y, "fps": 0.0, "bit_depth": 8, "title": _title}


func get_stats() -> Dictionary:
	if win == null:
		return {}
	var s: Dictionary = win.call("get_stats")
	s["waiting"] = _waiting
	return s


func get_known_mode() -> VideoMode:
	return VideoMode.new()


# --- Input (window pixels; see docs/window-source.md) --------------------------------------------------------------

func send_pointer(p: Vector2) -> void:
	if win != null and window_id != 0:
		win.call("send_pointer", p.x, p.y)


## 1 left, 2 middle, 3 right, 8 back, 9 forward.
func send_button(button: int, pressed: bool) -> void:
	if win != null and window_id != 0:
		win.call("send_button", button, pressed)


## Notches; +y is down. Fractions accumulate in the engine.
func send_scroll(dx: float, dy: float) -> void:
	if win != null and window_id != 0:
		win.call("send_scroll", dx, dy)


func send_godot_key(key: Key, pressed: bool) -> void:
	if win != null and window_id != 0:
		win.call("send_godot_key", key, pressed)


## Press and release.
func tap_key(key: Key) -> void:
	send_godot_key(key, true)
	send_godot_key(key, false)


## Text typed into whatever has the window's focus, as the on-screen keyboard does (the engine's send_text: each
## character as a key press, Unicode included). No check of what has focus: the fallback without DevTools.
func send_text(text: String) -> void:
	if win == null or window_id == 0:
		return
	if win.has_method("send_text"):
		win.call("send_text", text)
		return
	for i in text.length():
		send_char(text.unicode_at(i))


## A typed character (keeps the keyboard layout's shifted symbols right).
func send_char(unicode: int) -> void:
	if win != null and window_id != 0:
		win.call("send_unicode", unicode, true)
		win.call("send_unicode", unicode, false)
