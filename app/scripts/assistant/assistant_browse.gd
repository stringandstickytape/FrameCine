extends Node

## An assistant asks to open a web page in the Browser source (docs/assistant.md, "Browsing"): a card asks the
## viewer ("<assistant> wants to open www.bbc.co.uk/iplayer", Open / No); nothing opens without Open. Public pages are
## allowed (unlike fetch); http and https only, no logins in the URL. On Open: the browser on show goes to the page
## over its DevTools port (Page.navigate), else the screen switches to the Browser source at the URL (a launch). The
## API never reads the browser's cookies, logins, form fields or page content: only the page's url and title.
##
##   AssistantBrowse.ensure(tree) -> node
##   await suggest(url, who) -> {ok, result: {pending, url, card} | error, refused}
##   signal event(data)   {state: opened | declined | timeout, url, how?: devtools | launch, error?}

signal event(data: Dictionary)

const WindowVideoSource := preload("res://scripts/video/window_video_source.gd")
const WebPages := preload("res://scripts/net/web_pages.gd")
const AssistantFetch := preload("res://scripts/assistant/assistant_fetch.gd")
const NODE_NAME := "AssistantBrowse"
const ASK_SECONDS := 60.0
const URL_MAX := 2048

var _next := 1


static func ensure(tree: SceneTree) -> Node:
	var n := tree.root.get_node_or_null(NODE_NAME)
	if n != null:
		return n
	if tree.root.has_meta(NODE_NAME) and is_instance_valid(tree.root.get_meta(NODE_NAME)):
		return tree.root.get_meta(NODE_NAME)
	n = (load("res://scripts/assistant/assistant_browse.gd") as GDScript).new()
	n.name = NODE_NAME
	tree.root.set_meta(NODE_NAME, n)
	tree.root.add_child.call_deferred(n)
	return n


## {url} (https:// added when there is no scheme) or {error}.
static func check(url: String) -> Dictionary:
	var u := url.strip_edges()
	if u == "":
		return {"error": "give a url"}
	if u.length() > URL_MAX:
		return {"error": "the url is longer than %d characters" % URL_MAX}
	for ch in u:
		if ch.unicode_at(0) <= 32 or ch.unicode_at(0) == 127:
			return {"error": "no spaces or control characters in the url"}
	var lower := u.to_lower()
	for bad in ["javascript:", "file:", "data:", "chrome:", "chrome-extension:", "about:", "blob:", "view-source:",
			"devtools:", "filesystem:", "ftp:"]:
		if lower.begins_with(bad):
			return {"error": "only http and https pages (not %s URLs)" % bad.trim_suffix(":")}
	if lower.contains(":") and not lower.begins_with("http://") and not lower.begins_with("https://") \
			and lower.get_slice(":", 0).is_valid_identifier() and not lower.get_slice(":", 1).is_valid_int():
		return {"error": "only http and https pages (not %s: URLs)" % lower.get_slice(":", 0)}
	u = WebPages.normalized(u)
	var p := AssistantFetch.parse_url(u)
	if p.has("error"):
		return {"error": "no user names or passwords in the url" if str(p["error"]).contains("passwords")
				else str(p["error"])}
	return {"url": u}


static func shown(url: String) -> String:
	var s := url.trim_prefix("https://").trim_prefix("http://").trim_suffix("/")
	return s if s.length() <= 80 else s.left(77) + "..."


func suggest(url: String, who: String) -> Dictionary:
	var c := check(url)
	if c.has("error"):
		return {"ok": false, "refused": true, "error": c["error"]}
	var to := str(c["url"])
	var card := _card_node()
	if card == null:
		return {"ok": false, "error": "no card to ask the viewer on"}
	var id := "browse%d" % _next
	_next += 1
	card.show_card({"id": id, "title": "Open a page", "text": "%s wants to open %s" % [who, shown(to)],
			"seconds": ASK_SECONDS, "actions": [{"id": "open", "label": "Open"}, {"id": "no", "label": "No"}]})
	var slot: Array[Callable] = []
	var on_dismissed := func(card_id: String, how: String) -> void:
		if card_id != id:
			return
		card.dismissed.disconnect(slot[0])
		if how == "open":
			_open(to)
		else:
			event.emit({"state": "timeout" if how == "timeout" else "declined", "url": to})
	slot.append(on_dismissed)
	card.dismissed.connect(on_dismissed)
	return {"ok": true, "result": {"pending": true, "card": id, "url": to,
			"events": "browse {state: opened | declined | timeout, url}"}}


## The browser on show goes to the page (DevTools), else the Browser source opens at it.
func _open(to: String) -> void:
	var main := get_tree().current_scene if is_inside_tree() else null
	if main == null or not main.has_method("open_path"):
		event.emit({"state": "declined", "url": to, "error": "the player is not ready"})
		return
	var src: Object = main.player.source
	if src != null and src.has_method("navigate") and int(src.get("devtools_port")) > 0:
		var err: String = await src.navigate(to)
		if err == "":
			event.emit({"state": "opened", "url": to, "how": "devtools"})
			return
	main.open_path(WindowVideoSource.browser_path(to))
	event.emit({"state": "opened", "url": to, "how": "launch"})


func _card_node() -> Node:
	var main := get_tree().current_scene if is_inside_tree() else null
	if main == null or main.get("ui") == null:
		return null
	var card: Node = main.ui.get("card")
	return card if card != null and card.has_method("show_card") and card.has_signal("dismissed") else null
