extends RefCounted

## Subtitle files as plain lines for director mode (docs/director.md): SubRip (.srt), WebVTT (.vtt) and ASS / SSA
## (.ass, .ssa). parse(text, ext) -> [{start, end, text}], sorted by start; markup removed (ASS override tags, \N,
## HTML-style tags), lines joined with "\n". No engine needed: the fallback when the engine has no whole-track dump.

const EXTENSIONS: Array[String] = ["srt", "vtt", "ass", "ssa"]


static func parse(text: String, ext: String) -> Array[Dictionary]:
	var t := text.replace("\r\n", "\n").replace("\r", "\n").trim_prefix("﻿")
	var out: Array[Dictionary] = []
	match ext.to_lower():
		"ass", "ssa":
			out = _parse_ass(t)
		_:
			out = _parse_cues(t)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["start"]) < float(b["start"]))
	return out


static func parse_file(path: String) -> Array[Dictionary]:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var bytes := f.get_buffer(f.get_length())
	var text := bytes.get_string_from_utf8()
	if text == "" and not bytes.is_empty():
		text = bytes.get_string_from_ascii()
	return parse(text, path.get_extension())


## SubRip and WebVTT: blocks of "start --> end" then text lines, separated by blank lines.
static func _parse_cues(t: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for block in t.split("\n\n", false):
		var lines := block.strip_edges().split("\n")
		var i := 0
		while i < lines.size() and not lines[i].contains("-->"):
			i += 1
		if i >= lines.size():
			continue
		var times := lines[i].split("-->")
		var start := _time(times[0])
		var end := _time(times[1].strip_edges().split(" ")[0])
		if start < 0.0 or end < 0.0:
			continue
		var body := "\n".join(lines.slice(i + 1))
		var plain := strip_markup(body)
		if plain != "":
			out.append({"start": start, "end": end, "text": plain})
	return out


## ASS / SSA: the [Events] section's Dialogue lines, in the order its Format line gives.
static func _parse_ass(t: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var fields: PackedStringArray = ["layer", "start", "end", "style", "name", "marginl", "marginr", "marginv",
			"effect", "text"]
	var in_events := false
	for raw in t.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("["):
			in_events = line.to_lower() == "[events]"
			continue
		if not in_events:
			continue
		if line.to_lower().begins_with("format:"):
			fields = PackedStringArray()
			for f in line.substr(7).split(","):
				fields.append(f.strip_edges().to_lower())
			continue
		if not line.to_lower().begins_with("dialogue:"):
			continue
		var parts := line.substr(9).strip_edges().split(",", true, fields.size() - 1)
		if parts.size() < fields.size():
			continue
		var start := _time(parts[fields.find("start")])
		var end := _time(parts[fields.find("end")])
		var plain := strip_markup(parts[fields.find("text")])
		if start >= 0.0 and plain != "":
			out.append({"start": start, "end": end, "text": plain})
	return out


## "01:02:03,456", "01:02:03.45", "02:03.456" -> seconds; -1 if not a time.
static func _time(s: String) -> float:
	var parts := s.strip_edges().replace(",", ".").split(":")
	if parts.size() < 2 or parts.size() > 3:
		return -1.0
	var total := 0.0
	for p in parts:
		if not p.is_valid_float():
			return -1.0
		total = total * 60.0 + p.to_float()
	return total


## Removes ASS override tags ({\i1}), \N / \n / \h, and <i>-style tags; trims each line, drops empty ones.
static func strip_markup(s: String) -> String:
	var t := s.replace("\\N", "\n").replace("\\n", "\n").replace("\\h", " ")
	var re := RegEx.create_from_string("\\{[^}]*\\}|<[^>]+>")
	t = re.sub(t, "", true)
	var kept: PackedStringArray = []
	for l in t.split("\n"):
		var c := l.strip_edges()
		if c != "":
			kept.append(c)
	return "\n".join(kept)
