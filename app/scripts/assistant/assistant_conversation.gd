extends RefCounted

## The conversation on the card beside the screen (docs/assistant.md, Voice), as tools/listener.py builds it for the
## dev link: one line per press of the talk button, the assistant's answers under what the viewer said, the newest
## lines kept. A line in progress (live) ends in " ...", which the card (ui/watch_card.gd) draws as dancing dots until
## the final text replaces it. Presses can overlap: each keeps its own line.
##
##   var conv := AssistantConversation.new()
##   conv.set_line(7, "You", "(listening)", true)       # uid 7: the seventh press
##   conv.set_line(7, "You", "who is that", false)
##   conv.set_line(-1, "Assistant", "The lighthouse keeper.")   # -1: a new line
##   card.show_card({"text": conv.text(), "title": "Conversation", "seconds": SECONDS, "id": ID})

const ID := "conversation"
const TITLE := "Conversation"
## An upper bound; the card itself drops the oldest lines that do not fit.
const CHARS := 1500
const SECONDS := 180.0
## An answer goes under the conversation while a line came in the last this many seconds.
const RECENT := 600.0
const KEEP := 12

## [{uid, who, text, live}]
var lines: Array[Dictionary] = []
var changed_at := -1.0e9


## Sets press `uid`'s line (text null removes it), or appends a new line when uid < 0.
func set_line(uid: int, who: String, text: Variant, live := false) -> void:
	var entry := {}
	if uid >= 0:
		for e in lines:
			if e["uid"] == uid:
				entry = e
	if text == null:
		if not entry.is_empty():
			lines.erase(entry)
	elif not entry.is_empty():
		entry["text"] = _clean(str(text))
		entry["live"] = live
	else:
		lines.append({"uid": uid, "who": who, "text": _clean(str(text)), "live": live})
	while lines.size() > KEEP:
		lines.remove_at(0)
	changed_at = Time.get_ticks_msec() / 1000.0


func has_line(uid: int) -> bool:
	return lines.any(func(e: Dictionary) -> bool: return e["uid"] == uid)


func recent() -> bool:
	return not lines.is_empty() and Time.get_ticks_msec() / 1000.0 - changed_at < RECENT


## The card's text: the newest lines that fit in CHARS, oldest first.
func text() -> String:
	var out: PackedStringArray = []
	var total := 0
	for i in range(lines.size() - 1, -1, -1):
		var e: Dictionary = lines[i]
		var t: String = e["text"] if str(e["text"]).length() <= 2000 else str(e["text"]).left(1997) + "..."
		var line := "%s: %s%s" % [e["who"], t, " ..." if e["live"] else ""]
		if not out.is_empty() and total + line.length() > CHARS:
			break
		out.insert(0, line)
		total += line.length() + 2
	return "\n\n".join(out)


static func _clean(s: String) -> String:
	return " ".join(s.replace("\n", " ").replace("\r", " ").replace("\t", " ").split(" ", false))
