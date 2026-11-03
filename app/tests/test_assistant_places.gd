extends SceneTree

## An assistant suggesting places (scripts/assistant/assistant_places.gd): the card asks with the assistant's name, Add
## saves where the file browser keeps it (a share in NetworkHosts with the host's saved login; a folder under home in
## SavedPlaces; a page in WebPages), No and the timeout save nothing, the place event says how it ended; refusals
## (not on this network, outside home, inside a share, a login in the path, a duplicate with its label); remove_place.
##
## godot --headless --xr-mode off --path app --script res://tests/test_assistant_places.gd

const AssistantCommands := preload("res://scripts/assistant/assistant_commands.gd")
const AssistantPlaces := preload("res://scripts/assistant/assistant_places.gd")
const NetworkHosts := preload("res://scripts/net/network_hosts.gd")
const WebPages := preload("res://scripts/net/web_pages.gd")
const SavedPlaces := preload("res://scripts/net/saved_places.gd")

var _failures := 0
var _checks := 0
var main: Node3D
var commands: AssistantCommands
var events: Array[Dictionary] = []
var card: Node


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _run() -> void:
	await _frames(5)
	var hosts_before := NetworkHosts.hosts.duplicate(true)
	var pages_before := WebPages.pages.duplicate()
	var saved_before := SavedPlaces.places.duplicate(true)
	var home := OS.get_user_data_dir().path_join("test_places_home")
	DirAccess.make_dir_recursive_absolute(home.path_join("Films/Kids"))
	AssistantPlaces.home_override = home
	NetworkHosts.hosts.clear()
	NetworkHosts.hosts.append({"host": "192.168.1.21", "share": "", "user": "viewer", "password": "secret",
			"domain": "", "label": ""})
	commands = AssistantCommands.new()
	commands.allow_control = func() -> bool: return true
	commands.allow_files = func() -> bool: return true
	commands.allow_room = func() -> bool: return false
	commands.client_name = "Test AI"
	var places: Node = AssistantPlaces.ensure(self)
	await _frames(2)
	places.event.connect(func(d: Dictionary) -> void: events.append(d))
	card = main.ui.get("card") if main.get("ui") != null else null
	_check("a card to ask on", card != null)

	# --- Refusals. ---
	for bad: Array in [["smb://8.8.8.8/TV", "not on this network"], ["smb://192.168.1.21/TV/Kids", "host or a share"],
			["smb://viewer@192.168.1.21/TV", "no user names"], ["/etc", "not under the home folder"],
			["ftp://192.168.1.21/x", "a place is"], ["http://8.8.8.8/", "not on this network"],
			[home.path_join("Nothing here"), "not a folder"], ["smb://127.0.0.1/TV", "this headset itself"]]:
		var r: Dictionary = await commands.run("add_place", {"label": "X", "path": bad[0]})
		_check("refused: %s (%s)" % [bad[0], r.get("error", "")], r.get("ok") == false
				and str(r.get("error", "")).contains(bad[1]))
	commands.allow_files = func() -> bool: return false
	var r: Dictionary = await commands.run("add_place", {"label": "TV", "path": "smb://192.168.1.21/TV"})
	_check("needs the viewer's files permission", r.get("refused") == true)
	commands.allow_files = func() -> bool: return true

	# --- A share on a host with a saved login: Add. ---
	r = await commands.run("add_place", {"label": " TV\n shows ", "path": "smb://192.168.1.21/TV"})
	_check("pending at once (%s)" % str(r).left(200), r.get("ok") == true and r["result"]["pending"] == true
			and r["result"]["label"] == "TV shows")
	_check("the card asks with the assistant's name (%s)" % _card_text(), _card_text().contains(
			"Test AI wants to add TV shows (smb://192.168.1.21/TV) to your places")
			and _card_text().contains("login saved for 192.168.1.21"))
	_check("nothing saved before the answer", NetworkHosts.hosts.size() == 1 and events.is_empty())
	card.dismiss("add")
	await _frames(2)
	var tv := NetworkHosts.hosts.filter(func(h: Dictionary) -> bool: return h["share"] == "TV")
	_check("added: the place event (%s)" % [events], events.size() == 1 and events[0]["state"] == "added"
			and events[0]["path"] == "smb://192.168.1.21/TV" and events[0]["label"] == "TV shows")
	_check("saved as a network host with the label and the host's saved login (%s)" % [tv], tv.size() == 1
			and tv[0]["label"] == "TV shows" and tv[0]["user"] == "viewer" and tv[0]["password"] == "secret")
	r = await commands.run("add_place", {"label": "Telly", "path": "smb://192.168.1.21/TV/"})
	_check("a duplicate is refused with the label there (%s)" % r.get("error", ""), r.get("ok") == false
			and str(r.get("error", "")).contains("TV shows"))

	# --- A host without a saved login: the viewer will be asked on first open; No saves nothing. ---
	events.clear()
	r = await commands.run("add_place", {"label": "Music", "path": "smb://192.168.1.40/Music"})
	_check("no saved login: the card says the viewer is asked on first open (%s)" % _card_text(),
			_card_text().contains("asked for it the first time you open it")
			and str(r["result"].get("note", "")).contains("asked"))
	card.dismiss("no")
	await _frames(2)
	_check("No: declined, nothing saved (%s)" % [events], events.size() == 1 and events[0]["state"] == "declined"
			and NetworkHosts.find_host("192.168.1.40").is_empty())

	# --- A folder under home: a timeout, then Add. ---
	events.clear()
	var films := home.path_join("Films")
	r = await commands.run("add_place", {"label": "Films", "path": films + "/Kids/.."})
	card.dismiss("timeout")
	await _frames(2)
	_check("a timeout: nothing saved (%s)" % [events], events.size() == 1 and events[0]["state"] == "timeout"
			and SavedPlaces.find(films).is_empty())
	events.clear()
	r = await commands.run("add_place", {"label": "Films", "path": films})
	card.dismiss("add")
	await _frames(2)
	_check("a folder under home is added and listed among the places", events.size() == 1
			and events[0]["state"] == "added" and not SavedPlaces.find(films).is_empty()
			and preload("res://ui/files_tab.gd").get_places().any(func(p: Dictionary) -> bool:
				return p["path"] == films and p["label"] == "Films"))

	# --- A page on this network goes under Browser. ---
	events.clear()
	r = await commands.run("add_place", {"label": "Media server", "path": "http://192.168.1.20:8096/"})
	card.dismiss("add")
	await _frames(2)
	_check("a page on this network goes under Browser", events.size() == 1 and events[0]["state"] == "added"
			and "http://192.168.1.20:8096/" in WebPages.pages)

	# --- Removing. ---
	r = await commands.run("remove_place", {"path": home})
	_check("a built-in place can't be removed (%s)" % r.get("error", ""), r.get("ok") == false)
	events.clear()
	r = await commands.run("remove_place", {"path": "smb://192.168.1.21/TV"})
	_check("remove asks (%s)" % _card_text(), r.get("ok") == true and r["result"]["pending"] == true
			and _card_text().contains("Test AI wants to remove TV shows"))
	card.dismiss("remove")
	await _frames(2)
	_check("removed (%s)" % [events], events.size() == 1 and events[0]["state"] == "removed"
			and NetworkHosts.hosts.filter(func(h: Dictionary) -> bool: return h["share"] == "TV").is_empty()
			and not NetworkHosts.find_host("192.168.1.21").is_empty())
	events.clear()
	r = await commands.run("remove_place", {"path": films})
	card.dismiss("no")
	await _frames(2)
	_check("kept when the viewer says no", events.size() == 1 and events[0]["state"] == "declined"
			and not SavedPlaces.find(films).is_empty())
	_check("the label is made one plain line", AssistantPlaces.clean_label("a\tb\n\nc" + "x".repeat(80)).length() == 40
			and not AssistantPlaces.clean_label("a\tb\nc").contains("\n"))

	# --- browse: asks first, opens on Open. ---
	for bad: Array in [["javascript:alert(1)", "not javascript"], ["file:///etc/passwd", "not file"],
			["data:text/html,hi", "not data"], ["chrome://settings", "not chrome"],
			["https://u:p@www.bbc.co.uk/", "passwords"], ["mailto:a@b.c", "only http and https"]]:
		r = await commands.run("browse", {"url": bad[0]})
		_check("browse refused: %s (%s)" % [bad[0], r.get("error", "")], r.get("ok") == false
				and str(r.get("error", "")).contains(bad[1]))
	var browse_events: Array[Dictionary] = []
	var browse: Node = preload("res://scripts/assistant/assistant_browse.gd").ensure(self)
	await _frames(2)
	browse.event.connect(func(d: Dictionary) -> void: browse_events.append(d))
	var before_path: String = main.current_path
	r = await commands.run("browse", {"url": "www.bbc.co.uk/iplayer"})
	_check("browse asks first (%s; %s)" % [str(r).left(160), _card_text()], r.get("ok") == true
			and r["result"]["pending"] == true and r["result"]["url"] == "https://www.bbc.co.uk/iplayer"
			and _card_text() == "Test AI wants to open www.bbc.co.uk/iplayer" and main.current_path == before_path)
	card.dismiss("no")
	await _frames(2)
	_check("No: declined, nothing opened (%s)" % [browse_events], browse_events.size() == 1
			and browse_events[0]["state"] == "declined" and main.current_path == before_path)
	browse_events.clear()
	r = await commands.run("browse", {"url": "https://www.bbc.co.uk/iplayer"})
	card.dismiss("timeout")
	await _frames(2)
	_check("timeout: nothing opened", browse_events.size() == 1 and browse_events[0]["state"] == "timeout"
			and main.current_path == before_path)
	browse_events.clear()
	r = await commands.run("browse", {"url": "https://www.bbc.co.uk/iplayer"})
	card.dismiss("open")
	await _frames(3)
	_check("Open: the Browser source at the page (%s, %s)" % [browse_events, main.current_path],
			browse_events.size() == 1 and browse_events[0]["state"] == "opened"
			and main.current_path == "browser://https://www.bbc.co.uk/iplayer")

	NetworkHosts.hosts.assign(hosts_before)
	WebPages.pages.assign(pages_before)
	SavedPlaces.places.assign(saved_before)
	AssistantPlaces.home_override = ""
	DirAccess.remove_absolute(home.path_join("Films/Kids"))
	DirAccess.remove_absolute(home.path_join("Films"))
	DirAccess.remove_absolute(home)
	print("test_assistant_places: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(1 if _failures > 0 else 0)


func _card_text() -> String:
	var t: Node = card.get("_text") if card != null else null
	return str(t.get("text")) if t != null else ""


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL " + what)
