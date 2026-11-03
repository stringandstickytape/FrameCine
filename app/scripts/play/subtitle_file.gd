extends RefCounted

## Reads a subtitle file in the app (SubRip, WebVTT, ASS / SSA), for the second subtitle track (ideas #65): the engine
## reads one subtitle track at a time, so a second one shown with it comes from a file next to the video, read here.
## Static; preload to use.
##
##   load_file(path) -> Array of events, [] when unreadable. Blocking: call on a worker thread for files on a share.
##   parse(text, extension) -> [{start, end, text, ass}] sorted by start. `ass` is the line in FFmpeg's event form
##       ("ReadOrder,Layer,Style,Name,MarginL,MarginR,MarginV,Effect,Text"), so subtitle_style.gd styles it like a line
##       from the engine: SubRip and WebVTT <b> <i> <u> <s> <font color> become ASS override tags; WebVTT cue settings,
##       voices and classes are dropped.
##   decode(bytes) -> String: UTF-8 (with or without a BOM), UTF-16 with a BOM, else Windows-1252.

const MAX_BYTES := 8 * 1024 * 1024
const EXTENSIONS := ["srt", "vtt", "ass", "ssa"]
## Windows-1252 characters for 0x80-0x9F (0 where the code page has none).
const CP1252 := [0x20AC, 0, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0,
		0x017D, 0, 0, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0,
		0x017E, 0x0178]
const ASS_PREFIX := "0,0,Default,,0,0,0,,"


static func load_file(path: String) -> Array:
	var ext := path.get_extension().to_lower()
	if not ext in EXTENSIONS:
		return []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var bytes := f.get_buffer(mini(f.get_length(), MAX_BYTES))
	return parse(decode(bytes), ext)


static func parse(text: String, extension: String) -> Array:
	text = text.trim_prefix("\ufeff").replace("\r\n", "\n").replace("\r", "\n")
	var out: Array = []
	match extension.to_lower():
		"srt", "vtt":
			out = _parse_cues(text)
		"ass", "ssa":
			out = _parse_ass(text)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["start"]) < float(b["start"]))
	return out


static func decode(bytes: PackedByteArray) -> String:
	if bytes.size() >= 2 and bytes[0] == 0xFF and bytes[1] == 0xFE:
		return bytes.slice(2).get_string_from_utf16()
	if bytes.size() >= 2 and bytes[0] == 0xFE and bytes[1] == 0xFF:
		var swapped := bytes.slice(2)
		for i in range(0, swapped.size() - 1, 2):
			var b := swapped[i]
			swapped[i] = swapped[i + 1]
			swapped[i + 1] = b
		return swapped.get_string_from_utf16()
	if _is_utf8(bytes):
		return bytes.get_string_from_utf8()
	var s := ""
	for b in bytes:
		var c: int = CP1252[b - 0x80] if b >= 0x80 and b < 0xA0 else b
		if c != 0:
			s += String.chr(c)
	return s


static func _is_utf8(bytes: PackedByteArray) -> bool:
	var i := 0
	var n := bytes.size()
	while i < n:
		var b := bytes[i]
		var extra := 0
		if b < 0x80:
			i += 1
			continue
		elif b & 0xE0 == 0xC0 and b >= 0xC2:
			extra = 1
		elif b & 0xF0 == 0xE0:
			extra = 2
		elif b & 0xF8 == 0xF0 and b <= 0xF4:
			extra = 3
		else:
			return false
		if i + extra >= n:
			return false
		for k in range(1, extra + 1):
			if bytes[i + k] & 0xC0 != 0x80:
				return false
		i += extra + 1
	return true


## "01:02:03,456", "02:03.456", "0:02:03.45" -> seconds; -1 when unreadable.
static func parse_time(t: String) -> float:
	var parts := t.strip_edges().replace(",", ".").split(":")
	if parts.size() < 2 or parts.size() > 3:
		return -1.0
	var seconds := 0.0
	for p in parts:
		if not p.is_valid_float():
			return -1.0
		seconds = seconds * 60.0 + p.to_float()
	return seconds


## SubRip and WebVTT: blocks separated by blank lines; the line with "-->" holds the times, the lines after it the text.
static func _parse_cues(text: String) -> Array:
	var out: Array = []
	var lines := text.split("\n")
	var i := 0
	while i < lines.size():
		var line := lines[i]
		if not line.contains("-->"):
			i += 1
			continue
		var times := line.split("-->")
		var start := parse_time(times[0])
		var end_field := times[1].strip_edges().split(" ", false)
		var end := parse_time(end_field[0]) if not end_field.is_empty() else -1.0
		i += 1
		var body: Array[String] = []
		while i < lines.size() and lines[i].strip_edges() != "":
			body.append(lines[i].strip_edges())
			i += 1
		if start < 0.0 or body.is_empty():
			continue
		var cue := "\n".join(body)
		out.append({"start": start, "end": end, "text": _plain(cue), "ass": ASS_PREFIX + _tags_to_ass(cue)})
	return out


## HTML-like tags -> ASS overrides; unknown tags dropped; entities decoded; line breaks -> \N.
static func _tags_to_ass(cue: String) -> String:
	var re := RegEx.create_from_string("<\\s*(/?)\\s*([a-zA-Z]+)([^>]*)>")
	var out := ""
	var pos := 0
	for m in re.search_all(cue):
		out += _entities(cue.substr(pos, m.get_start() - pos))
		pos = m.get_end()
		var closing := m.get_string(1) == "/"
		var tag := m.get_string(2).to_lower()
		match tag:
			"b", "i", "u", "s":
				out += "{\\%s%d}" % [tag, 0 if closing else 1]
			"font":
				if closing:
					out += "{\\c}"
				else:
					var cm := RegEx.create_from_string("color\\s*=\\s*\"?([#a-zA-Z0-9]+)\"?").search(m.get_string(3))
					var c: Variant = _color(cm.get_string(1)) if cm != null else null
					if c is Color:
						out += "{\\c&H%02X%02X%02X&}" % [(c as Color).b8, (c as Color).g8, (c as Color).r8]
	out += _entities(cue.substr(pos))
	return out.replace("\n", "\\N")


static func _plain(cue: String) -> String:
	return _entities(RegEx.create_from_string("<[^>]*>").sub(cue, "", true))


static func _entities(s: String) -> String:
	return s.replace("&lt;", "<").replace("&gt;", ">").replace("&nbsp;", "\u00a0").replace("&lrm;", "") \
			.replace("&rlm;", "").replace("&amp;", "&")


static func _color(v: String) -> Variant:
	var sentinel := Color(-1, -1, -1, -1)
	var c := Color.from_string(v, sentinel)
	return null if c == sentinel else c


## ASS / SSA: the [Events] section's Dialogue lines, in the field order of its Format line.
static func _parse_ass(text: String) -> Array:
	var out: Array = []
	var in_events := false
	var fields := PackedStringArray(["layer", "start", "end", "style", "name", "marginl", "marginr", "marginv",
			"effect", "text"])
	var order := 0
	for raw in text.split("\n"):
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
		var values := line.substr(9).strip_edges().split(",", true, fields.size() - 1)
		if values.size() < fields.size():
			continue
		var v := {}
		for k in fields.size():
			v[fields[k]] = values[k].strip_edges() if fields[k] != "text" else values[k]
		var start := parse_time(str(v.get("start", "")))
		var end := parse_time(str(v.get("end", "")))
		if start < 0.0:
			continue
		var layer := str(v.get("layer", "0")).trim_prefix("Marked=")
		var ass := "%d,%s,%s,%s,%s,%s,%s,%s,%s" % [order, layer, v.get("style", "Default"), v.get("name", ""),
				v.get("marginl", "0"), v.get("marginr", "0"), v.get("marginv", "0"), v.get("effect", ""), v.get("text", "")]
		order += 1
		var plain := RegEx.create_from_string("\\{[^}]*\\}").sub(str(v.get("text", "")), "", true)
		plain = plain.replace("\\N", "\n").replace("\\n", "\n").replace("\\h", "\u00a0")
		out.append({"start": start, "end": end, "text": plain, "ass": ass})
	return out
