extends Node

## An assistant suggests a place for the file browser; the viewer says yes or no on the card (docs/assistant.md,
## "Places"). Nothing is saved until the viewer presses Add (or Remove). Kinds, each kept where the file browser's own
## UI keeps it:
##   smb://host or smb://host/share   NetworkHosts (the Network place), with the label; the saved login of the same host
##                                    is reused. No credentials ever pass through the API: without a saved login the
##                                    viewer is asked on first open, in the headset, as with any host.
##   a folder under the home folder   SavedPlaces (listed among the places)
##   http(s):// on the LAN            WebPages (the Browser place; pages keep no label)
## LAN only (every address of the host private, not the headset itself); a path already a place is refused with its
## label. The reply comes at once with pending: true; the outcome is the `place` event {state: added | removed |
## declined | timeout, label, path} (and card_dismissed).
##
##   AssistantPlaces.ensure(tree) -> node
##   await suggest_add(label, path, who) / suggest_remove(path, who) -> {ok, result: {pending, ...} | error, refused}
##   signal event(data)

signal event(data: Dictionary)

const AssistantFetch := preload("res://scripts/assistant/assistant_fetch.gd")
const NetworkHosts := preload("res://scripts/net/network_hosts.gd")
const WebPages := preload("res://scripts/net/web_pages.gd")
const SavedPlaces := preload("res://scripts/net/saved_places.gd")
const NODE_NAME := "AssistantPlaces"
const LABEL_MAX := 40
## How long the card asks (seconds); then the event says timeout.
const ASK_SECONDS := 60.0

## Tests: the home folder places must be under.
static var home_override := ""

var _next := 1


static func ensure(tree: SceneTree) -> Node:
	var n := tree.root.get_node_or_null(NODE_NAME)
	if n != null:
		return n
	if tree.root.has_meta(NODE_NAME) and is_instance_valid(tree.root.get_meta(NODE_NAME)):
		return tree.root.get_meta(NODE_NAME)
	n = (load("res://scripts/assistant/assistant_places.gd") as GDScript).new()
	n.name = NODE_NAME
	tree.root.set_meta(NODE_NAME, n)
	tree.root.add_child.call_deferred(n)
	return n


static func home() -> String:
	if home_override != "":
		return home_override
	var h := OS.get_environment("HOME")
	return h if h != "" else OS.get_environment("USERPROFILE").replace("\\", "/")


## A label for the list: printable, one line, at most LABEL_MAX characters.
static func clean_label(s: String) -> String:
	var out := ""
	for ch in s.strip_edges():
		var c := ch.unicode_at(0)
		out += " " if c < 32 or c == 127 else ch
	while out.contains("  "):
		out = out.replace("  ", " ")
	return out.strip_edges().left(LABEL_MAX).strip_edges()


## {kind: smb | local | web, path, host?, share?} or {error}. Doesn't look at the network (see check()).
static func classify(path: String) -> Dictionary:
	var p := path.strip_edges()
	if p.begins_with("smb://"):
		var rest := p.trim_prefix("smb://").trim_suffix("/")
		var parts := rest.split("/", false)
		if parts.is_empty():
			return {"error": "no host in %s" % p}
		if parts.size() > 2:
			return {"error": "a network place is a host or a share (smb://host or smb://host/share), not a folder "
					+ "inside one"}
		var host := parts[0]
		if host.contains("@"):
			return {"error": "no user names or passwords in the path: the viewer gives the login in the headset"}
		var share := parts[1] if parts.size() > 1 else ""
		return {"kind": "smb", "host": host, "share": share, "path": NetworkHosts.root_path({"host": host,
				"share": share})}
	if p.begins_with("http://") or p.begins_with("https://"):
		var u := AssistantFetch.parse_url(p)
		if u.has("error"):
			return {"error": u["error"]}
		return {"kind": "web", "host": u["host"], "path": p}
	if p.contains("://"):
		return {"error": "a place is smb://host/share, a folder under the home folder, or an http(s) page on this "
				+ "network"}
	var h := home()
	if p.begins_with("~/") or p == "~":
		p = h + p.substr(1)
	if not p.is_absolute_path():
		return {"error": "give an absolute path under the home folder (%s)" % h}
	p = p.simplify_path().trim_suffix("/")
	if p != h and not p.begins_with(h.trim_suffix("/") + "/"):
		return {"error": "%s is not under the home folder (%s)" % [p, h]}
	if not DirAccess.dir_exists_absolute(p):
		return {"error": "%s is not a folder on the headset" % p}
	return {"kind": "local", "path": p}


## The place already there for a path: its label, or "" when it isn't one.
static func existing_label(path: String) -> String:
	var files_tab: GDScript = load("res://ui/files_tab.gd")
	for p: Dictionary in files_tab.get_places():
		if str(p["path"]).trim_suffix("/") == path.trim_suffix("/"):
			return str(p["label"])
	for h: Dictionary in NetworkHosts.hosts:
		if NetworkHosts.root_path(h).to_lower() == path.to_lower():
			return str(h.get("label", "")) if str(h.get("label", "")) != "" else NetworkHosts.root_path(h)
	for w: String in WebPages.pages:
		if w == path:
			return w
	return ""


func suggest_add(label: String, path: String, who: String) -> Dictionary:
	var c := classify(path)
	if c.has("error"):
		return {"ok": false, "refused": true, "error": c["error"]}
	if c.has("host"):
		var why: String = await AssistantFetch.host_refusal(get_tree(), str(c["host"]))
		if why != "":
			return {"ok": false, "refused": true, "error": why}
	var there := existing_label(str(c["path"]))
	if there != "":
		return {"ok": false, "refused": true, "error": "%s is already a place: %s" % [c["path"], there]}
	var name := clean_label(label)
	if name == "":
		name = str(c["path"]).trim_suffix("/").get_file()
	if name == "":
		name = str(c.get("host", c["path"]))
	var note := ""
	match str(c["kind"]):
		"smb":
			if not NetworkHosts.find_host(str(c["host"])).is_empty():
				note = "It uses the login saved for %s." % c["host"]
			else:
				note = "If it needs a login, you'll be asked for it the first time you open it."
		"web":
			note = "It goes under Browser."
	var text := "%s wants to add %s (%s) to your places.%s" % [who, name, c["path"], "\n" + note if note != "" else ""]
	var card := _card_node()
	if card == null:
		return {"ok": false, "error": "no card to ask the viewer on"}
	var id := "place%d" % _next
	_next += 1
	card.show_card({"id": id, "title": "A new place", "text": text, "seconds": ASK_SECONDS,
			"actions": [{"id": "add", "label": "Add"}, {"id": "no", "label": "No"}]})
	var add := func() -> String:
		_save(c, name)
		return "added"
	_await_answer(card, id, add, c, name)
	return {"ok": true, "result": {"pending": true, "card": id, "label": name, "path": c["path"], "kind": c["kind"],
			"note": note, "events": "place {state: added | declined | timeout, label, path}"}}


func suggest_remove(path: String, who: String) -> Dictionary:
	var p := path.strip_edges()
	var kind := ""
	var label := ""
	if not SavedPlaces.find(p.trim_suffix("/")).is_empty():
		kind = "local"
		p = p.trim_suffix("/")
		label = str(SavedPlaces.find(p)["label"])
	elif p.begins_with("smb://"):
		for h: Dictionary in NetworkHosts.hosts:
			if NetworkHosts.root_path(h).to_lower() == p.trim_suffix("/").to_lower():
				kind = "smb"
				p = NetworkHosts.root_path(h)
				label = str(h.get("label", "")) if str(h.get("label", "")) != "" else p
	elif p in WebPages.pages:
		kind = "web"
		label = p
	if kind == "":
		return {"ok": false, "refused": true, "error": "%s is not a place the viewer added (the built-in places stay)"
				% p}
	var card := _card_node()
	if card == null:
		return {"ok": false, "error": "no card to ask the viewer on"}
	var id := "place%d" % _next
	_next += 1
	card.show_card({"id": id, "title": "Remove a place", "text": "%s wants to remove %s (%s) from your places."
			% [who, label, p], "seconds": ASK_SECONDS,
			"actions": [{"id": "remove", "label": "Remove"}, {"id": "no", "label": "Keep it"}]})
	var c := {"kind": kind, "path": p}
	var drop := func() -> String:
		_unsave(c)
		return "removed"
	_await_answer(card, id, drop, c, label)
	return {"ok": true, "result": {"pending": true, "card": id, "label": label, "path": p,
			"events": "place {state: removed | declined | timeout, label, path}"}}


## When the card goes: the viewer's yes runs `act`; the place event says how it ended.
func _await_answer(card: Node, id: String, act: Callable, c: Dictionary, label: String) -> void:
	var slot: Array[Callable] = []
	var on_dismissed := func(card_id: String, how: String) -> void:
		if card_id != id:
			return
		card.dismissed.disconnect(slot[0])
		var state := "declined"
		if how in ["add", "remove"]:
			state = act.call()
		elif how == "timeout":
			state = "timeout"
		event.emit({"state": state, "label": label, "path": c["path"], "kind": c["kind"]})
	slot.append(on_dismissed)
	card.dismissed.connect(on_dismissed)


func _save(c: Dictionary, label: String) -> void:
	match str(c["kind"]):
		"smb":
			var entry := {"host": c["host"], "share": c["share"], "label": label}
			var known := NetworkHosts.find_host(str(c["host"]))
			for k in ["user", "password", "domain"]:
				entry[k] = known.get(k, "")
			NetworkHosts.save_host(-1, entry)
		"web":
			WebPages.add_page(str(c["path"]))
		_:
			SavedPlaces.add(label, str(c["path"]))


func _unsave(c: Dictionary) -> void:
	match str(c["kind"]):
		"smb":
			for i in NetworkHosts.hosts.size():
				if NetworkHosts.root_path(NetworkHosts.hosts[i]) == str(c["path"]):
					NetworkHosts.remove_host(i)
					return
		"web":
			WebPages.remove_page(str(c["path"]))
		_:
			SavedPlaces.remove(str(c["path"]))


func _card_node() -> Node:
	var main := get_tree().current_scene if is_inside_tree() else null
	if main == null or main.get("ui") == null:
		return null
	var card: Node = main.ui.get("card")
	return card if card != null and card.has_method("show_card") and card.has_signal("dismissed") else null
