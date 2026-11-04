extends HBoxContainer

## The Files tab (docs/ui-design.md): the places column, a breadcrumb, and the folder's rows with name, duration,
## resume marker and mode chip. One click opens (no double clicks with a laser). The add-host and web-page forms with
## the on-pane keyboard take the list's place (and the pane hides its seek bar and transport meanwhile, signal
## form_shown).
##
## Places: test patterns, Network (saved SMB hosts), Browser (web pages and desktop windows), home, the device user's
## home, removable media under /run/media, /mnt/*, drive letters on a desktop. Listing runs on a WorkerThreadPool task
## (network shares and slow mounts never block the frame); late answers for a folder the user already left are
## dropped. Virtual folders: "stub://" (test patterns), "network://" (saved hosts, and hosts found on the LAN, #49),
## "browser://" (the URL form, saved pages, the desktop's windows; scripts/video/window_video_source.gd), "queue://"
## (the play queue, #78), "favourites://" (#76), "search://" (#76: favourites, history, queue and the last local
## folder) and "android://" (the apps in ~/Android; scripts/android/). The Library (~/Videos/Library, made on first use) is a real folder, drawn by ui/library_view.gd as posters,
## seasons and episodes where its NFOs say what things are, and listed like any other where they don't.

const StubVideoSource := preload("res://scripts/video/stub_video_source.gd")
const VideoSourceFactory := preload("res://scripts/video/video_source_factory.gd")
const MediaServers := preload("res://scripts/net/media_servers.gd")
const LiveStream := preload("res://scripts/play/live_stream.gd")
const DirectoryLister := preload("res://scripts/net/directory_lister.gd")
const NetworkHosts := preload("res://scripts/net/network_hosts.gd")
const HostForm := preload("res://ui/host_form.gd")
const UrlForm := preload("res://ui/url_form.gd")
const WindowVideoSource := preload("res://scripts/video/window_video_source.gd")
const WebPages := preload("res://scripts/net/web_pages.gd")
const AssistantFetch := preload("res://scripts/assistant/assistant_fetch.gd")
const LibraryIndex := preload("res://scripts/library/library_index.gd")
const LibraryImages := preload("res://scripts/library/library_images.gd")
const LibraryView := preload("res://ui/library_view.gd")
const SavedPlaces := preload("res://scripts/net/saved_places.gd")
const AgentTerminal := preload("res://scripts/agents/agent_terminal.gd")
const Lepton := preload("res://scripts/android/lepton.gd")
const SearchForm := preload("res://ui/search_form.gd")
const HostDiscovery := preload("res://scripts/net/host_discovery.gd")
const VideoMode := preload("res://scripts/video_mode.gd")
const W := preload("res://ui/pane_widgets.gd")
const PaneStyle := preload("res://ui/pane_style.gd")

signal file_selected(path: String)
signal folder_changed(path: String)
## "Stop showing" on the Browser place: the app closes the window source.
signal close_requested
## A form (host, web page) took the list's place, or left it.
signal form_shown(on: bool)
## The list changed (for the footer's item count).
signal listing_changed

const PATTERNS_FOLDER := "stub://"
const NETWORK_FOLDER := "network://"
const BROWSER_FOLDER := "browser://"
## An agent on the headset: agent://claude, agent://codex (scripts/agents/).
const AGENT_PREFIX := "agent://"
## The Android apps in ~/Android (scripts/android/): one click runs one on the big screen.
const ANDROID_FOLDER := "android://"
const QUEUE_FOLDER := "queue://"
const FAVOURITES_FOLDER := "favourites://"
const SEARCH_FOLDER := "search://"
## Media servers on the LAN (UPnP/DLNA, scripts/net/media_servers.gd): upnp:// lists the servers, then their folders.
const MEDIA_SERVERS_FOLDER := "upnp://"
const DISCOVERY_SECONDS := 3.0

## scripts/main.gd, for the resume markers (main.features.resume); may be null.
var app: Node
var current := ""
## The path on screen (set by the UI layer): the Browser place offers to stop showing a window, the row is marked.
var active_path := ""
var active_title := ""
var _places_scroll: ScrollContainer
var _places_box: VBoxContainer
var _places_rule: VSeparator
## The places column is wanted (set_places_column(): the tablet lists the places beside the tabs instead).
var _places_shown := true
var _path_label: Label
var _add_button: Button
var _edit_button: Button
var _list_scroll: ScrollContainer
var _list: VBoxContainer
## The view (VIEWS): "details" (rows with their extras; the Library with pictures and plots), "list" (dense rows) or
## "grid" (tiles; the Library's posters and thumbnails). ui/pane_ui.gd keeps it in the settings.
var view := "details"
const VIEWS: Array[String] = ["details", "list", "grid"]
## The grid view's tile, pane pixels (the names wrap to two lines).
const TILE := Vector2(180, 96)
## The flow of tiles being filled (the grid view), or null: a row that is not a tile ends it.
var _tiles: HFlowContainer
var _form: HostForm
var _url_form: UrlForm
## Per list row: {"kind": "dir"|"file"|"up"|"host"|"add"|"url"|"page"|"window"|"stop"|"none", "path": String,
## "index": int, "button": Button or null}
var _rows: Array[Dictionary] = []
## _system_dir()'s answers.
static var _system_dirs := {}
var _request := 0
var _tasks: Array[int] = []
var _busy := false
var _edit_hosts := false
var _edit_pages := false
var _edit_queue := false
var _edit_favourites := false
var _search_form: SearchForm
var _query := ""
var _library_view: LibraryView
var _library_images: Node
## The list shows the library's view (else a plain folder).
var _library_shown := false
var _search_results: Array = []
var _search_folder_results: Array = []
## The last real (local) folder shown: the Search place walks it.
var _last_local := ""
var _discovery: Node
var _found: Array[Dictionary] = []
var _queue_bar: HBoxContainer
var _shuffle: Button
var _repeat: Button
var _continuous: Button
var _gapless: Button
## Picture in picture (#87): armed, the next video picked plays in the screen's corner instead.
var _in_corner: Button
var _favourite_folder: Button


func _ready() -> void:
	add_theme_constant_override("separation", PaneStyle.constant(&"gap"))
	_places_scroll = ScrollContainer.new()
	_places_scroll.custom_minimum_size = Vector2(PaneStyle.constant(&"places_width"), 0)
	_places_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_places_scroll)
	_places_box = VBoxContainer.new()
	_places_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_places_box.add_theme_constant_override("separation", 0)
	_places_scroll.add_child(_places_box)
	_places_rule = VSeparator.new()
	add_child(_places_rule)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(right)
	var bar := W.hbox()
	right.add_child(bar)
	_path_label = W.ellipsis(W.label("", &"MutedLabel"))
	bar.add_child(_path_label)
	_add_button = W.button("Add host", func() -> void: _show_form(-1, {}))
	bar.add_child(_add_button)
	_edit_button = W.button("Edit hosts", Callable())
	_edit_button.toggle_mode = true
	_edit_button.toggled.connect(func(on: bool) -> void:
		match current:
			BROWSER_FOLDER:
				_edit_pages = on
			QUEUE_FOLDER:
				_edit_queue = on
			FAVOURITES_FOLDER:
				_edit_favourites = on
			_:
				_edit_hosts = on
		_refresh())
	bar.add_child(_edit_button)
	_favourite_folder = W.button("Favourite", Callable())
	_favourite_folder.toggle_mode = true
	_favourite_folder.toggled.connect(func(_on: bool) -> void:
		if _library() != null:
			_library().toggle_favourite(current, true))
	bar.add_child(_favourite_folder)
	_in_corner = W.toggle("In corner", func(_on: bool) -> void: pass)
	bar.add_child(_in_corner)
	_queue_bar = W.hbox()
	_shuffle = W.toggle("Shuffle", func(on: bool) -> void: _queue().set_shuffle(on))
	_repeat = W.button("Repeat: off", func() -> void:
		_queue().cycle_repeat()
		_refresh())
	_continuous = W.toggle("Play on", func(on: bool) -> void: _queue().set_continuous(on))
	_gapless = W.toggle("Gapless", func(on: bool) -> void:
		var g: Node = _feature("gapless")
		if g != null:
			g.set_enabled(on))
	_queue_bar.add_child(_shuffle)
	_queue_bar.add_child(_repeat)
	_queue_bar.add_child(_continuous)
	_queue_bar.add_child(_gapless)
	_queue_bar.add_child(W.button("Clear upcoming", func() -> void:
		_queue().clear_upcoming()
		_refresh()))
	right.add_child(_queue_bar)
	_list_scroll = ScrollContainer.new()
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_list_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 0)
	_list_scroll.add_child(_list)

	_form = HostForm.new()
	_form.visible = false
	_form.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_form.saved.connect(func(index: int, entry: Dictionary) -> void:
		save_host(index, entry)
		_hide_form())
	_form.deleted.connect(func(index: int) -> void:
		delete_host(index)
		_hide_form())
	_form.cancelled.connect(_hide_form)
	add_child(_form)
	_url_form = UrlForm.new()
	_url_form.visible = false
	_url_form.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_url_form.open_requested.connect(func(text: String) -> void:
		# A media URL (udp://, http(s) ending in a video or music name) plays in the player as it is; anything else is
		# a web page (WebPages.normalized() adds https:// when needed).
		if LiveStream.is_media_url(text):
			_hide_form()
			file_selected.emit(text.strip_edges())
			return
		var u := WebPages.normalized(text)
		WebPages.set_last_url(u)
		_hide_form()
		file_selected.emit(WindowVideoSource.browser_path(u)))
	_url_form.play_requested.connect(func(text: String) -> void:
		_hide_form()
		file_selected.emit(text.strip_edges()))
	_url_form.save_requested.connect(func(text: String) -> void:
		WebPages.add_page(text)
		_hide_form())
	_url_form.remove_requested.connect(func(u: String) -> void:
		WebPages.remove_page(u)
		_hide_form())
	_url_form.cancelled.connect(_hide_form)
	add_child(_url_form)
	_search_form = SearchForm.new()
	_search_form.visible = false
	_search_form.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_search_form.search_requested.connect(func(q: String) -> void:
		_hide_form(false)
		_run_search(q))
	_search_form.cancelled.connect(_hide_form)
	add_child(_search_form)
	_build_places()
	var refresh_if := func(place: String) -> void:
		if current == place and not is_form_open():
			_refresh()
	if _queue() != null:
		_queue().changed.connect(refresh_if.bind(QUEUE_FOLDER))
	if _library() != null:
		_library().favourites_changed.connect(refresh_if.bind(FAVOURITES_FOLDER))
	if _android() != null:
		_android().changed.connect(refresh_if.bind(ANDROID_FOLDER))


func _build_places() -> void:
	for c in _places_box.get_children():
		c.queue_free()
	for place in places_in_order():
		var p: String = place["path"]
		var b := W.button(place["label"], func() -> void:
			open_folder(p)
			# An agent's entry: a running one comes up on the controller; else the list offers how to start it.
			if p.begins_with(AGENT_PREFIX) and get_tree().current_scene.local_agents.is_running(
					p.trim_prefix(AGENT_PREFIX)):
				get_tree().current_scene.local_agents.open_agent(p.trim_prefix(AGENT_PREFIX))
				_refresh(), &"PlaceButton")
		b.custom_minimum_size.y = PaneStyle.constant(&"row_height")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.toggle_mode = true
		b.set_meta("path", p)
		_places_box.add_child(b)
	_mark_place()


func _mark_place() -> void:
	for b in _places_box.get_children():
		if b is Button and b.has_meta("path"):
			(b as Button).set_pressed_no_signal(is_current_place(b.get_meta("path")))


## The place's list is on show, or a folder inside it (inside the Library only its own place, not the Videos folder
## it sits in).
func is_current_place(p: String) -> bool:
	return p == current or (p != "" and not p.ends_with("://") and current.begins_with(p.trim_suffix("/") + "/")
			and (p == LibraryIndex.root() or not LibraryIndex.is_inside(current)))


## The places column on the left, or not (a layout that lists the places elsewhere).
func set_places_column(on: bool) -> void:
	_places_shown = on
	_places_scroll.visible = on and not is_form_open()
	_places_rule.visible = _places_scroll.visible


## The view (VIEWS): the listing is drawn again in it.
func set_view(v: String) -> void:
	if v == view or not v in VIEWS:
		return
	view = v
	if not is_form_open():
		_refresh()


## The places column's width (pixels): scaled with the text on the tablet (ui/pane_ui.gd).
func set_places_width(px: float) -> void:
	_places_scroll.custom_minimum_size.x = px


## Adds a control at the right end of the title row (the tablet's view selector, ui/pane_ui.gd).
func add_to_bar(control: Control) -> void:
	_in_corner.get_parent().add_child(control)


## The places in order: the library and the lists first, then the network, the folders on the headset, the agents,
## and the test patterns last.
static func places_in_order() -> Array[Dictionary]:
	var first: Array[String] = [LibraryIndex.root(), FAVOURITES_FOLDER, QUEUE_FOLDER, SEARCH_FOLDER, NETWORK_FOLDER,
			MEDIA_SERVERS_FOLDER, ANDROID_FOLDER, BROWSER_FOLDER]
	var top: Array[Dictionary] = []
	var folders: Array[Dictionary] = []
	var agents: Array[Dictionary] = []
	var last: Array[Dictionary] = []
	for p: Dictionary in get_places():
		var path := str(p["path"])
		if path in first:
			top.append(p)
		elif path.begins_with(AGENT_PREFIX):
			agents.append(p)
		elif path == PATTERNS_FOLDER:
			last.append(p)
		else:
			folders.append(p)
	top.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return first.find(str(a["path"])) < first.find(str(b["path"])))
	return top + folders + agents + last


## [{label, path}] in display order; only places that exist.
static func get_places() -> Array[Dictionary]:
	# Offered before it exists: opening it makes it.
	var out: Array[Dictionary] = [{"label": LibraryIndex.FOLDER_NAME, "path": LibraryIndex.root()},
			{"label": "Test patterns", "path": PATTERNS_FOLDER},
			{"label": "Network", "path": NETWORK_FOLDER}, {"label": "Media servers", "path": MEDIA_SERVERS_FOLDER},
			{"label": "Browser", "path": BROWSER_FOLDER},
			{"label": "Queue", "path": QUEUE_FOLDER}, {"label": "Favourites", "path": FAVOURITES_FOLDER},
			{"label": "Search", "path": SEARCH_FOLDER}]
	for id: String in AgentTerminal.AGENTS:
		out.append({"label": str(AgentTerminal.AGENTS[id]["name"]), "path": AGENT_PREFIX + id})
	out.append({"label": "Android apps", "path": ANDROID_FOLDER})
	var seen := {}
	var add := func(label: String, p: String) -> void:
		if p != "" and not seen.has(p) and DirAccess.dir_exists_absolute(p):
			seen[p] = true
			out.append({"label": label, "path": p})
	var home := OS.get_environment("HOME")
	if home == "":
		home = OS.get_environment("USERPROFILE").replace("\\", "/")
	add.call("Home", home)
	add.call("Device home", "/home/steamos")
	add.call("Videos", _system_dir(OS.SYSTEM_DIR_MOVIES))
	add.call("Downloads", _system_dir(OS.SYSTEM_DIR_DOWNLOADS))
	# What an assistant fetched (scripts/assistant/assistant_fetch.gd), once there is anything.
	add.call(AssistantFetch.FOLDER_NAME, AssistantFetch.folder())
	# Folders the viewer added (an assistant's add_place, confirmed): scripts/net/saved_places.gd.
	for p: Dictionary in SavedPlaces.places:
		add.call(str(p["label"]), str(p["path"]))
	# Removable media: /run/media/<label> and /run/media/<user>/<label>.
	for d in _subdirs("/run/media"):
		var sub := _subdirs(d)
		if sub.is_empty() or d.get_file() in ["mmcblk0p1", "sdcard"]:
			add.call(d.get_file(), d)
		else:
			for s in sub:
				add.call(s.get_file(), s)
	for d in _subdirs("/mnt"):
		add.call("mnt/" + d.get_file(), d)
	if OS.get_name() == "Windows":
		for i in DirAccess.get_drive_count():
			var drive := DirAccess.get_drive_name(i)
			add.call(drive, drive + "/")
	return out


## OS.get_system_dir(), asked once: on Linux each call runs xdg-user-dir (about 45 ms on the headset), and the
## places are listed on every change of place.
static func _system_dir(which: OS.SystemDir) -> String:
	if not _system_dirs.has(which):
		_system_dirs[which] = OS.get_system_dir(which)
	return _system_dirs[which]


static func _subdirs(p: String) -> Array[String]:
	var out: Array[String] = []
	if not DirAccess.dir_exists_absolute(p):
		return out
	for d in DirAccess.get_directories_at(p):
		out.append(p.path_join(d))
	return out


static func is_video_file(p: String) -> bool:
	return VideoSourceFactory.is_video_file(p)


## What a folder lists: videos and pictures (#22: JPEG, PNG, WebP, JPS, MPO open like videos).
static func is_media_file(p: String) -> bool:
	return VideoSourceFactory.is_media_file(p)


static func _is_virtual(p: String) -> bool:
	return p in [PATTERNS_FOLDER, NETWORK_FOLDER, BROWSER_FOLDER, QUEUE_FOLDER, FAVOURITES_FOLDER, SEARCH_FOLDER,
			ANDROID_FOLDER] or p.begins_with(AGENT_PREFIX)


func open_folder(p: String) -> void:
	if p == LibraryIndex.root():
		LibraryIndex.ensure_root()
	if p == "" or (not _is_virtual(p) and not NetworkHosts.is_smb(p) and not MediaServers.is_upnp(p)
			and not DirAccess.dir_exists_absolute(p)):
		# The first real folder (Home), else the test patterns.
		p = PATTERNS_FOLDER
		for place in get_places():
			if not _is_virtual(place["path"]) and place["path"] != LibraryIndex.root():
				p = place["path"]
				break
	current = p
	if not _is_virtual(p) and not NetworkHosts.is_smb(p) and not MediaServers.is_upnp(p):
		_last_local = p
	_edit_button.set_pressed_no_signal(false)
	_edit_hosts = false
	_edit_pages = false
	_edit_queue = false
	_edit_favourites = false
	_hide_form(false)
	_mark_place()
	_refresh()
	folder_changed.emit(current)


## The video files of the folder on show, in list order (the playlist when one of them is opened).
func get_video_paths() -> Array[String]:
	var out: Array[String] = []
	for row in _rows:
		if row["kind"] == "file":
			out.append(row["path"])
	return out


func is_busy() -> bool:
	return _busy


func is_form_open() -> bool:
	return _form.visible or _url_form.visible or _search_form.visible


## "24 items", "3 folders, 12 videos"; "" while loading.
func count_text() -> String:
	if _busy:
		return ""
	var dirs := 0
	var files := 0
	for row in _rows:
		match row["kind"]:
			"dir", "host":
				dirs += 1
			"file", "page", "window", "queued", "favourite", "result", "android_app":
				files += 1
	if dirs > 0 and files > 0:
		return "%d folders, %d items" % [dirs, files]
	if dirs > 0:
		return "%d folder%s" % [dirs, "" if dirs == 1 else "s"]
	return "%d item%s" % [files, "" if files == 1 else "s"]


func _refresh() -> void:
	_add_button.visible = current == NETWORK_FOLDER
	_edit_button.visible = (current == NETWORK_FOLDER and not NetworkHosts.hosts.is_empty()) \
			or (current == BROWSER_FOLDER and not WebPages.pages.is_empty()) \
			or (current == QUEUE_FOLDER and _queue() != null) \
			or (current == FAVOURITES_FOLDER and _library() != null and not _library().favourites().is_empty())
	_edit_button.text = {BROWSER_FOLDER: "Edit pages", QUEUE_FOLDER: "Edit queue",
			FAVOURITES_FOLDER: "Edit favourites"}.get(current, "Edit hosts")
	_queue_bar.visible = current == QUEUE_FOLDER and _queue() != null
	_favourite_folder.visible = not _is_virtual(current) and _library() != null
	_in_corner.visible = _feature("pip") != null and current not in [NETWORK_FOLDER, BROWSER_FOLDER, PATTERNS_FOLDER,
			ANDROID_FOLDER]
	if not _in_corner.visible:
		_in_corner.set_pressed_no_signal(false)
	if _favourite_folder.visible:
		_favourite_folder.set_pressed_no_signal(_library().is_favourite(current))
	if current.begins_with(AGENT_PREFIX):
		_list_agent(current.trim_prefix(AGENT_PREFIX))
		return
	if current == ANDROID_FOLDER:
		_list_android()
		return
	if current == BROWSER_FOLDER:
		_list_browser()
		return
	if current == QUEUE_FOLDER:
		_list_queue()
		return
	if current == FAVOURITES_FOLDER:
		_list_favourites()
		return
	if current == SEARCH_FOLDER:
		_list_search()
		return
	if current == PATTERNS_FOLDER:
		_clear("Test patterns (generated, no decoder)")
		for pattern in StubVideoSource.list_patterns():
			_add_row(str(pattern["label"]), {"kind": "file", "path": pattern["path"]})
		listing_changed.emit()
		return
	if current == NETWORK_FOLDER:
		_clear("Network: pick a host to edit" if _edit_hosts else "Network (SMB)")
		for i in NetworkHosts.hosts.size():
			var h := NetworkHosts.hosts[i]
			var user := str(h["user"])
			var shown := NetworkHosts.root_path(h)
			if str(h.get("label", "")) != "":
				shown = "%s  %s" % [h["label"], shown]
			_add_row("%s%s%s" % ["Edit: " if _edit_hosts else "", shown,
					"   (%s)" % user if user != "" else ""], {"kind": "host", "path": NetworkHosts.root_path(h), "index": i})
		_add_row("+ Add host...", {"kind": "add", "path": ""})
		if _discovery != null:
			_add_row("Looking for hosts on this network...", {"kind": "none", "path": ""})
		else:
			_add_row("Find hosts on this network", {"kind": "discover", "path": ""})
		for h in _found:
			var target := str(h.get("name", "")) if str(h.get("name", "")) != "" else str(h.get("address", ""))
			_add_row("Found: %s   (%s)" % [target, h.get("address", "")], {"kind": "found", "path": "smb://" + target,
					"host": h})
		if not DirectoryLister.has_media_browser():
			_add_row("(simulated: this engine build has no MediaBrowser yet)", {"kind": "none", "path": ""})
		listing_changed.emit()
		return
	if LibraryIndex.is_inside(current):
		_start_library(current)
		return
	_start_listing(current)


## The Browser place: open a page, the saved pages, the desktop's windows (listed on the spot: a local X server
## answers in well under a millisecond), and stopping the window on show.
func _list_browser() -> void:
	_clear("Browser: pick a page to edit" if _edit_pages else "Browser (web pages and desktop windows)")
	if WindowVideoSource.is_window_path(active_path):
		_add_row("Stop showing: %s" % (active_title if active_title != "" else WindowVideoSource.describe_path(active_path)),
				{"kind": "stop", "path": active_path})
	_add_row("+ Open a web page or a stream...", {"kind": "url", "path": ""})
	for u in WebPages.pages:
		_add_row(("Edit: " if _edit_pages else "") + u, {"kind": "page", "path": WindowVideoSource.browser_path(u), "url": u})
	_add_row("Desktop windows", {"kind": "none", "path": ""})
	var listing := WindowVideoSource.list_desktop_windows()
	if listing["error"] != "":
		_add_row("(%s)" % listing["error"], {"kind": "none", "path": ""})
	elif (listing["windows"] as Array).is_empty():
		_add_row("(no windows)", {"kind": "none", "path": ""})
	for w: Dictionary in listing["windows"]:
		var title: String = w["title"] if w["title"] != "" else "(untitled)"
		_add_row("%s   (%s, %dx%d)" % [title, w["class"] if w["class"] != "" else w["instance"], w["width"], w["height"]],
				{"kind": "window", "path": WindowVideoSource.window_path(w["id"])})
	listing_changed.emit()


func _clear(title: String) -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_rows.clear()
	_tiles = null
	_library_shown = false
	_path_label.text = title
	_busy = false
	_list_scroll.scroll_vertical = 0


## Lists a folder on a worker thread. Media servers too (rediscover: look for servers again first).
func _start_listing(p: String, rediscover := false) -> void:
	_request += 1
	var id := _request
	_clear(p)
	_busy = true
	_path_label.text = p + "   (loading...)"
	var upnp := MediaServers.is_upnp(p)
	_add_row("Looking for media servers on this network..." if upnp and (p == MEDIA_SERVERS_FOLDER or rediscover)
			else "Loading...", {"kind": "none", "path": ""})
	listing_changed.emit()
	# The worker holds the tab only weakly; the tab waits for its workers before it goes (_wait_tasks).
	var me: WeakRef = weakref(self)
	_tasks.append(WorkerThreadPool.add_task(func() -> void:
		if rediscover:
			MediaServers.discover(DISCOVERY_SECONDS)
		var result := MediaServers.list(p) if upnp else DirectoryLister.list(p)
		var tab: Object = me.get_ref()
		if tab != null:
			tab.call_deferred("_on_listed", id, p, result), false, "list " + p))


## A folder of the Library, read on a worker thread as any listing: its NFOs on the way, none of it on the frame.
func _start_library(p: String) -> void:
	_request += 1
	var id := _request
	_clear(LibraryIndex.FOLDER_NAME + "   (loading...)")
	_busy = true
	listing_changed.emit()
	var me: WeakRef = weakref(self)
	_tasks.append(WorkerThreadPool.add_task(func() -> void:
		var data := LibraryIndex.read(p)
		var tab: Object = me.get_ref()
		if tab != null:
			tab.call_deferred("_on_library_read", id, p, data), false, "library " + p))


func _on_library_read(id: int, p: String, data: Dictionary) -> void:
	_reap_tasks()
	if id != _request or p != current:
		return
	if data["view"] == "plain":
		_start_listing(p)
		return
	_clear(str(data["title"]))
	_library_shown = true
	if _library_images == null:
		_library_images = LibraryImages.new()
		_library_images.name = "LibraryImages"
		add_child(_library_images)
		_library_view = LibraryView.new(self, _library_images)
	_library_view.draw(data)
	listing_changed.emit()


## The view may have changed under it (a copy finished).
func refresh_library() -> void:
	if LibraryIndex.is_inside(current) and not is_form_open():
		_refresh()


func add_library_control(c: Control) -> void:
	_list.add_child(c)


func add_library_up(parent: String) -> void:
	_add_row("..", {"kind": "up", "path": parent})


func add_library_folder(folder_name: String, path: String) -> void:
	_add_row(folder_name + "/", {"kind": "dir", "path": path})


func set_library_title(text: String) -> void:
	_path_label.text = text


## A row of the Library's own making: a poster or an episode. `parent` is the grid it sits in.
func add_library_row(b: Button, row: Dictionary, parent: Control = null) -> void:
	_tiles = null
	row["library"] = true
	b.set_meta("text", row["text"])
	b.set_pressed_no_signal(row["kind"] == "file" and row["path"] == active_path)
	var index := _rows.size()
	b.pressed.connect(func() -> void: _on_row_pressed(index))
	(parent if parent != null else _list).add_child(b)
	row["button"] = b
	_rows.append(row)


func resume_data() -> Object:
	return app.features.resume if app != null and app.get("features") != null else null


func _on_listed(id: int, p: String, result: Dictionary) -> void:
	_reap_tasks()
	if id != _request or p != current:
		return  # The user has moved on.
	# A media server's entries carry their own paths (folders upnp://..., videos the server's http:// URLs) and parent.
	var upnp := MediaServers.is_upnp(p)
	_clear(("Media servers" if p == MEDIA_SERVERS_FOLDER else p) + ("   (simulated)" if result.get("simulated", false) else ""))
	var parent := str(result.get("parent", "")) if upnp else _parent_of(p)
	if parent != "":
		_add_row("..", {"kind": "up", "path": parent})
	var error: String = result.get("error", "")
	if error != "":
		_add_row("(%s)" % error, {"kind": "none", "path": ""})
	if p == MEDIA_SERVERS_FOLDER:
		_add_row("Look again for media servers", {"kind": "rediscover", "path": ""})
	var shown := 0
	for e: Dictionary in result["entries"]:
		var full := str(e["path"]) if upnp and e.has("path") else _join(p, e["name"])
		if e["is_dir"]:
			_add_row(str(e["name"]) + "/", {"kind": "dir", "path": full})
			shown += 1
		elif upnp or is_media_file(e["name"]):
			_add_row(e["name"], {"kind": "file", "path": full, "size": int(e.get("size", 0)),
					"duration": float(e.get("duration", 0.0))})
			shown += 1
	if shown == 0 and error == "":
		_add_row("(no folders, videos or pictures here)", {"kind": "none", "path": ""})
	listing_changed.emit()


## A listing still running when the tab goes (the app quits early) would call back into a freed tab and crash the
## app: wait for them first. A media server's discovery can take a few seconds.
func _exit_tree() -> void:
	_wait_tasks()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_wait_tasks()


func _wait_tasks() -> void:
	for t in _tasks:
		WorkerThreadPool.wait_for_task_completion(t)
	_tasks.clear()


## Waits on (frees) the listing tasks that have finished.
func _reap_tasks() -> void:
	for i in range(_tasks.size() - 1, -1, -1):
		if WorkerThreadPool.is_task_completed(_tasks[i]):
			WorkerThreadPool.wait_for_task_completion(_tasks[i])
			_tasks.remove_at(i)


static func _join(folder: String, entry_name: String) -> String:
	return folder.trim_suffix("/") + "/" + entry_name if NetworkHosts.is_smb(folder) else folder.path_join(entry_name)


## Up: smb://host/share/dir -> smb://host/share -> smb://host -> network://; local as usual.
static func _parent_of(p: String) -> String:
	if NetworkHosts.is_smb(p):
		var rest := p.trim_prefix("smb://").trim_suffix("/")
		return NETWORK_FOLDER if not rest.contains("/") else "smb://" + rest.get_base_dir()
	var parent := p.get_base_dir()
	return parent if parent != p and parent != "" else ""


## A row: a RowButton whose content is name, resume marker, duration (or size) and mode chip. Rows that do nothing
## ("none") are a plain muted line.
## An agent's entry: a running one is on the controller already (the place's button); here, what it's doing, how to
## start it (briefed on the player, or plain: it just starts and waits), and the big screen.
func _list_agent(id: String) -> void:
	var a: Dictionary = AgentTerminal.AGENTS.get(id, {})
	var agents: Node = get_tree().current_scene.get("local_agents") if get_tree().current_scene != null else null
	if a.is_empty() or agents == null:
		_clear("No such agent")
		return
	_clear(str(a["name"]))
	var running: bool = agents.is_running(id)
	var state := "Running in its terminal" if running else "Not running"
	if not AgentTerminal.installed(id):
		state = "Not installed"
	_add_row(state, {"kind": "none", "path": ""})
	if running:
		_add_row("Show on the controller", {"kind": "agent_pane", "path": id})
		_add_row("Restart, briefed on the player", {"kind": "agent_restart", "path": id})
		_add_row("Restart plain, no briefing", {"kind": "agent_restart_plain", "path": id})
	else:
		_add_row("Start, briefed on the player", {"kind": "agent_pane", "path": id})
		_add_row("Start plain, no briefing", {"kind": "agent_plain", "path": id})
	if agents.active == id and agents.pane_shown():
		_add_row("Hide from the controller (it keeps working)", {"kind": "agent_hide", "path": id})
	_add_row("Put it on the big screen", {"kind": "agent_screen", "path": id})
	listing_changed.emit()


## The Android apps: a row each, what is missing in plain words, and while one starts or runs, its step and the way out.
## Rebuilt on each step (the `changed` signal), so the rows are the card's steps as well.
func _list_android() -> void:
	var apps := _android()
	_clear("Android apps")
	if apps == null:
		return
	Lepton.ensure_folder()
	var missing := Lepton.missing()
	for line in missing:
		_add_row(line, {"kind": "none", "path": ""})
	var state_line: String = apps.status_line()
	if state_line != "":
		_add_row(state_line, {"kind": "none", "path": ""})
	if apps.state == apps.State.STARTING:
		_add_row("Cancel", {"kind": "android_cancel", "path": ""})
	elif apps.state == apps.State.RUNNING:
		_add_row("Stop %s" % apps.label(), {"kind": "android_stop", "path": ""})
	var list := Lepton.apps()
	if list.is_empty():
		for line in Lepton.how_to_add():
			_add_row(line, {"kind": "none", "path": ""})
	for a: Dictionary in list:
		if bool(a["spaces"]):
			_add_row("%s: its APK's file name has spaces, so it can't run yet" % a["label"], {"kind": "none", "path": ""})
		elif not apps.is_app(a["name"]) and missing.is_empty():
			_add_row(str(a["label"]), {"kind": "android_app", "path": a["name"]})
	listing_changed.emit()


func _add_row(text: String, row: Dictionary) -> void:
	row["text"] = text
	var h := PaneStyle.constant(&"row_height")
	if row["kind"] == "none":
		_tiles = null
		var l := W.ellipsis(W.label(text, &"MutedLabel"))
		l.custom_minimum_size = Vector2(0, h)
		_list.add_child(l)
		row["button"] = null
		_rows.append(row)
		return
	var b := Button.new()
	b.theme_type_variation = &"RowButton"
	b.toggle_mode = true
	b.set_pressed_no_signal(row["kind"] == "file" and row["path"] == active_path)
	b.set_meta("text", text)
	var extras: Array[Control] = []
	if row["kind"] == "file":
		extras = _row_extras(row)
	if view == "grid" and row["kind"] in ["file", "dir"]:
		# A tile: the name over two lines, the extras along the bottom.
		b.custom_minimum_size = TILE
		var content := VBoxContainer.new()
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		content.offset_left = 10
		content.offset_right = -10
		content.offset_top = 6
		content.offset_bottom = -6
		b.add_child(content)
		var name_label := W.ellipsis(W.label(text, &"AccentLabel" if b.button_pressed else &""))
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.max_lines_visible = 2
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		name_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(name_label)
		var foot := W.hbox()
		foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for extra in extras:
			extra.mouse_filter = Control.MOUSE_FILTER_IGNORE
			foot.add_child(extra)
		content.add_child(foot)
		if _tiles == null:
			_tiles = W.flow()
			_list.add_child(_tiles)
		_tiles.add_child(b)
	else:
		_tiles = null
		b.custom_minimum_size = Vector2(0, h * 0.75 if view == "list" else h)
		var content := W.hbox()
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		content.offset_left = 12
		content.offset_right = -12
		b.add_child(content)
		var name_label := W.ellipsis(W.label(text, &"AccentLabel" if b.button_pressed else &""))
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(name_label)
		for extra in extras:
			extra.mouse_filter = Control.MOUSE_FILTER_IGNORE
			content.add_child(extra)
		_list.add_child(b)
	var index := _rows.size()
	b.pressed.connect(func() -> void: _on_row_pressed(index))
	row["button"] = b
	_rows.append(row)


## Resume marker ("0:42 ▶", accent; the font has no ▸), duration or size (muted), mode chip.
func _row_extras(row: Dictionary) -> Array[Control]:
	var out: Array[Control] = []
	var path: String = row["path"]
	var duration := 0.0
	if app != null and app.get("features") != null and app.features.resume != null:
		var entry: Dictionary = app.features.resume.entry_for(path)
		duration = float(entry.get("duration", 0.0))
		var pos: float = app.features.resume.position_for(path)
		if pos > 0.0:
			out.append(W.label("%s ▶" % W.short_clock(pos), &"AccentLabel"))
	if duration <= 0.0:
		duration = float(row.get("duration", 0.0))
	if duration > 0.0:
		out.append(W.label(W.short_clock(duration), &"MutedLabel"))
	elif int(row.get("size", 0)) > 0:
		out.append(W.label(_size_text(int(row["size"])), &"MutedLabel"))
	var chip := chip_text(VideoMode.guess(path.get_file()))
	if path.begins_with("stub://"):
		chip = ""
	if VideoSourceFactory.is_image_file(path):
		chip = ("PICTURE " + chip).strip_edges()
	elif VideoSourceFactory.is_music_file(path):
		chip = "MUSIC"
	if chip != "":
		out.append(W.label(chip, &"ChipLabel"))
	return out


## The mode chip: what isn't plain flat 2D ("SBS", "180 SBS", "360 TB", "FISHEYE", "DUAL 360"), or "".
static func chip_text(m: VideoMode) -> String:
	var parts: Array[String] = []
	match m.projection:
		VideoMode.Proj.EQUIRECT_180:
			parts.append("180")
		VideoMode.Proj.EQUIRECT_360:
			parts.append("360")
		VideoMode.Proj.FISHEYE:
			parts.append("FISHEYE")
		VideoMode.Proj.DUAL_FISHEYE:
			parts.append("DUAL 360")
	match m.layout:
		VideoMode.Layout.SBS:
			parts.append("SBS")
		VideoMode.Layout.TB:
			parts.append("TB")
	return " ".join(parts)


static func _size_text(n: int) -> String:
	if n <= 0:
		return ""
	if n >= 1e9:
		return "%.1f GB" % (n / 1e9)
	return "%.0f MB" % (n / 1e6)


func _on_row_pressed(index: int) -> void:
	if index < 0 or index >= _rows.size() or _busy:
		return
	var row := _rows[index]
	var b: Button = row.get("button")
	if b != null:
		b.set_pressed_no_signal(row["kind"] == "file" and row["path"] == active_path)
	match row["kind"]:
		"dir", "up":
			open_folder(row["path"])
		"host":
			if _edit_hosts:
				_show_form(row["index"], NetworkHosts.hosts[row["index"]])
			else:
				open_folder(row["path"])
		"add":
			_show_form(-1, {})
		"file", "window":
			if _open_in_corner(row["path"]):
				return
			file_selected.emit(row["path"])
		"url":
			_show_url_form(WebPages.last_url, false)
		"page":
			if _edit_pages:
				_show_url_form(row["url"], true)
			else:
				WebPages.set_last_url(row["url"])
				file_selected.emit(row["path"])
		"stop":
			close_requested.emit()
		"discover":
			start_discovery()
		"rediscover":
			_start_listing(MEDIA_SERVERS_FOLDER, true)
		"found":
			# Open it; "Add host" with the name filled in saves it (credentials, share).
			var h: Dictionary = row["host"]
			var target := str(h.get("name", "")) if str(h.get("name", "")) != "" else str(h.get("address", ""))
			_show_form(-1, {"host": target})
		"queued":
			if _edit_queue:
				_queue().remove(int(row["index"]))
				_refresh()
			else:
				_queue().jump(int(row["index"]))
		"favourite":
			if _edit_favourites:
				_library().remove_favourite(row["path"])
				_refresh()
			elif bool(row.get("is_dir", false)):
				open_folder(row["path"])
			else:
				file_selected.emit(row["path"])
		"agent_pane":
			get_tree().current_scene.local_agents.open_agent(row["path"])
			_refresh()
		"agent_plain":
			get_tree().current_scene.local_agents.open_agent(row["path"], true)
			_refresh()
		"agent_restart":
			get_tree().current_scene.local_agents.restart_agent(row["path"])
		"agent_restart_plain":
			get_tree().current_scene.local_agents.restart_agent(row["path"], true)
		"agent_hide":
			get_tree().current_scene.local_agents.hide_pane()
			_refresh()
		"agent_screen":
			get_tree().current_scene.local_agents.show_on_screen(row["path"])
		"android_app":
			_android().start_app(row["path"])
		"android_cancel":
			_android().cancel()
		"android_stop":
			_android().stop_app()
		"add_favourite":
			_library().add_favourite(active_path, active_title, false)
			_refresh()
		"result":
			if bool(row.get("is_dir", false)):
				open_folder(row["path"])
			else:
				file_selected.emit(row["path"])
		"query":
			_show_search_form()


func _show_form(index: int, entry: Dictionary) -> void:
	_set_list_visible(false)
	_form.visible = true
	_form.edit(index, entry)
	form_shown.emit(true)


func _show_url_form(url: String, saved_page: bool) -> void:
	_set_list_visible(false)
	_url_form.visible = true
	_url_form.edit(url, saved_page)
	form_shown.emit(true)


func _set_list_visible(on: bool) -> void:
	for c in get_children():
		if c is Control and c != _form and c != _url_form and c != _search_form:
			(c as Control).visible = on and (_places_shown or not (c == _places_scroll or c == _places_rule))


func _hide_form(refresh := true) -> void:
	var was := is_form_open()
	_form.visible = false
	_url_form.visible = false
	_search_form.visible = false
	_set_list_visible(true)
	if was:
		form_shown.emit(false)
	if refresh and current in [NETWORK_FOLDER, BROWSER_FOLDER, SEARCH_FOLDER]:
		_edit_hosts = false
		_edit_pages = false
		_edit_button.set_pressed_no_signal(false)
		_refresh()


## The host form's Save (and the files commands' host_add, host_edit): adds (index -1) or replaces a saved host. New
## credentials: the next listing logs in afresh. A renamed host loses its old credentials.
static func save_host(index: int, entry: Dictionary) -> void:
	var old_host := str(NetworkHosts.hosts[index]["host"]) if index >= 0 and index < NetworkHosts.hosts.size() else ""
	NetworkHosts.save_host(index, entry)
	var new_host := str(entry.get("host", "")).strip_edges().trim_prefix("smb://").trim_suffix("/")
	DirectoryLister.forget_host(old_host, old_host.to_lower() != new_host.to_lower())
	DirectoryLister.forget_host(new_host)


## The host form's Delete host (and host_remove): the host and its credentials go.
static func delete_host(index: int) -> void:
	if index >= 0 and index < NetworkHosts.hosts.size():
		DirectoryLister.forget_host(str(NetworkHosts.hosts[index]["host"]), true)
	NetworkHosts.remove_host(index)


## A command changed what a place lists (hosts, pages): the list follows if that place is on show.
func refresh_place(place: String) -> void:
	if current == place and not is_form_open():
		_refresh()


## The last local folder shown: the Search place walks it.
func last_local_folder() -> String:
	return _last_local


func get_url_form() -> UrlForm:
	return _url_form


func get_form() -> HostForm:
	return _form


## The row button whose text begins with `starts`, or null (tests, focus).
func row_button(starts: String) -> Button:
	for row in _rows:
		var b: Button = row.get("button")
		if b != null and str(b.get_meta("text")).strip_edges().begins_with(starts.strip_edges()):
			return b
	return null


## The rows' texts in order (tests).
func row_texts() -> Array[String]:
	var out: Array[String] = []
	for row in _rows:
		out.append(str(row["text"]))
	return out


func list_scroll() -> ScrollContainer:
	return _list_scroll


## The UI layer tells the browser what is on screen; the Browser place lists "Stop showing" for a window, and the
## playing file's row is marked.
func set_active(p: String, title: String) -> void:
	active_path = p
	active_title = title
	if is_form_open():
		return
	if current == BROWSER_FOLDER:
		_refresh()
		return
	for row in _rows:
		var b: Button = row.get("button")
		if b != null and row["kind"] == "file":
			b.set_pressed_no_signal(row["path"] == p)
			if row.get("library", false):
				if row.has("title_label"):
					(row["title_label"] as Label).theme_type_variation = &"AccentLabel" if row["path"] == p else &""
				continue
			var name_label := b.get_child(0).get_child(0) as Label
			name_label.theme_type_variation = &"AccentLabel" if row["path"] == p else &""


## The resume markers changed (a file was played): rebuild the rows of a local or share folder in place.
func refresh_markers() -> void:
	if _library_shown:
		_library_view.update_marks()
		return
	if current != BROWSER_FOLDER and current != NETWORK_FOLDER and not is_form_open() and not _busy:
		var scroll := _list_scroll.scroll_vertical
		if current == PATTERNS_FOLDER:
			_refresh()
		else:
			_rebuild_rows()
		_list_scroll.set_deferred("scroll_vertical", scroll)


func _rebuild_rows() -> void:
	var old := _rows.duplicate()
	var title := _path_label.text
	_clear(title)
	for row: Dictionary in old:
		var r := row.duplicate()
		r.erase("button")
		_add_row(str(r["text"]), r)
	listing_changed.emit()


## "In corner" armed and a video picked: it plays in the screen's corner (#87); the switch goes off. False otherwise
## (or for a file the corner can't show: it opens as usual).
func _open_in_corner(path: String) -> bool:
	if not _in_corner.button_pressed:
		return false
	_in_corner.set_pressed_no_signal(false)
	var pip: Node = _feature("pip")
	if pip == null or not pip.can_show(path):
		return false
	return bool(pip.open(path))


func _feature(feature_name: String) -> Node:
	return app.features.get(feature_name) if app != null and app.get("features") != null else null


func _android() -> Node:
	return app.get("android_apps") if app != null else null


func _queue() -> Node:
	return app.features.queue if app != null and app.get("features") != null else null


func _library() -> Node:
	return app.features.library if app != null and app.get("features") != null else null


## The Network place's "Find hosts": NetBIOS and mDNS for DISCOVERY_SECONDS (scripts/net/host_discovery.gd, #49).
func start_discovery() -> void:
	if _discovery != null:
		return
	_found.clear()
	_discovery = HostDiscovery.new()
	_discovery.name = "HostDiscovery"
	add_child(_discovery)
	_discovery.host_found.connect(func(h: Dictionary) -> void:
		for known in _found:
			if known.get("address") == h.get("address"):
				return
		_found.append(h)
		if current == NETWORK_FOLDER and not is_form_open():
			_refresh())
	_discovery.finished.connect(func(_hosts: Array) -> void:
		_discovery.queue_free()
		_discovery = null
		if current == NETWORK_FOLDER and not is_form_open():
			_refresh())
	if not _discovery.start(DISCOVERY_SECONDS):
		_discovery.queue_free()
		_discovery = null
	_refresh()


## The play queue (#78): the files in order, the playing one marked. A row jumps there; "Edit queue" removes.
func _list_queue() -> void:
	var q := _queue()
	_clear("Queue: pick a file to remove" if _edit_queue else "Queue")
	if q == null:
		return
	_shuffle.set_pressed_no_signal(bool(q.shuffle))
	_continuous.set_pressed_no_signal(bool(q.continuous))
	var g: Node = _feature("gapless")
	_gapless.visible = g != null
	if g != null:
		_gapless.set_pressed_no_signal(bool(g.enabled))
	_repeat.text = "Repeat: %s" % str(q.repeat)
	var items: Array = q.items()
	if items.is_empty():
		_add_row("(nothing queued: open a file from a folder)", {"kind": "none", "path": ""})
	for i in items.size():
		var it: Dictionary = items[i]
		var current_item := bool(it.get("current", false))
		_add_row("%s%s%s" % ["Remove: " if _edit_queue and not current_item else "", "Playing: " if current_item else "",
				it.get("title", "")], {"kind": "queued", "path": it.get("path", ""), "index": i})
	listing_changed.emit()


## Favourites (#76): folders and files the user starred. "Favourite" on a folder's bar adds it; the playing file is
## added here.
func _list_favourites() -> void:
	var lib := _library()
	_clear("Favourites: pick one to remove" if _edit_favourites else "Favourites")
	if lib == null:
		return
	if active_path != "" and not lib.is_favourite(active_path) and not WindowVideoSource.is_window_path(active_path):
		_add_row("+ Add the playing file", {"kind": "add_favourite", "path": active_path})
	var favs: Array = lib.favourites()
	if favs.is_empty():
		_add_row("(no favourites yet: open a folder and press Favourite)", {"kind": "none", "path": ""})
	for f: Dictionary in favs:
		var is_dir := bool(f.get("is_dir", false))
		var title := str(f.get("title", "")) if str(f.get("title", "")) != "" else str(f.get("path", "")).get_file()
		_add_row("%s%s%s" % ["Remove: " if _edit_favourites else "", title, "/" if is_dir else ""],
				{"kind": "favourite", "path": f.get("path", ""), "is_dir": is_dir})
	listing_changed.emit()


## Search (#76): the query row opens the form; results from search_known at once, then the last local folder's walk.
func _list_search() -> void:
	_clear("Search" + (": " + _query if _query != "" else ""))
	_add_row("Search: %s" % (_query if _query != "" else "type a name..."), {"kind": "query", "path": ""})
	var seen := {}
	for r: Dictionary in _search_results + _search_folder_results:
		var path := str(r.get("path", ""))
		if seen.has(path):
			continue
		seen[path] = true
		var is_dir := bool(r.get("is_dir", false))
		_add_row("%s%s" % [str(r.get("title", path.get_file())), "/" if is_dir else ""],
				{"kind": "result", "path": path, "is_dir": is_dir})
	if _query != "" and seen.is_empty():
		_add_row("(nothing found yet)", {"kind": "none", "path": ""})
	listing_changed.emit()


func _show_search_form() -> void:
	_set_list_visible(false)
	_search_form.visible = true
	_search_form.edit(_query)
	form_shown.emit(true)


func _run_search(q: String) -> void:
	_query = q
	var lib := _library()
	_search_results = lib.search_known(q) if lib != null else []
	_search_folder_results = []
	if lib != null and _last_local != "":
		if not lib.folder_results.is_connected(_on_folder_results):
			lib.folder_results.connect(_on_folder_results)
		lib.search_folder(_last_local, q)
	if current == SEARCH_FOLDER:
		_refresh()


func _on_folder_results(q: String, results: Array) -> void:
	if q != _query:
		return
	_search_folder_results = results
	if current == SEARCH_FOLDER and not is_form_open():
		_refresh()


## Opens the Search place with a query already run (the watch party's "Find it").
func search_for(q: String) -> void:
	_run_search(q)
	open_folder(SEARCH_FOLDER)


func get_search_form() -> SearchForm:
	return _search_form
