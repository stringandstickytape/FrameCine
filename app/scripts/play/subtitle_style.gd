extends RefCounted

## Styled subtitle text (ideas #67): turns a subtitle event into lines of styled runs, and those into BBCode for a
## RichTextLabel. Static; preload to use.
##
## Sources, best first:
##   event["styled"]  the engine's parsed ASS lines (hwvideo subtitle_style.cpp): [{runs: [{text, size, color,
##                    outline_color, outline_width, bold, italic, underline, strikeout, font}], text, alignment,
##                    position, margin_l/r/v, play_res, style, layer, back_color}]
##   event["ass"]     FFmpeg's ASS event line(s), "ReadOrder,Layer,Style,Name,MarginL,MarginR,MarginV,Effect,Text",
##                    one per line; parsed here for engines without "styled". SubRip <i>, <b>, <u>, <font color>
##                    arrive as ASS tags too. Understood: \b \i \u \s (0/1, \b also a weight), \c and \1c
##                    (&HBBGGRR&), \an and \a (alignment), \r (reset), \p (drawing: its text is skipped); \N and \n
##                    break lines, \h is a hard space. Other tags (\pos, \move, \fad, \k, ...) are dropped.
##   event["text"]    plain text
##
## from_event(event) -> {lines: [{runs, alignment}], bbcode: String, plain: String, alignment: int}
##   run: {text, bold, italic, underline, strikeout, color (Color or null), outline_color (Color or null),
##         size (1.0 = the event's largest text)}
##   alignment: ASS numpad 1-9 of the first line (2 = bottom centre). Fonts and explicit positions are not used: the
##   app draws every line in its own font, in its own band (see subtitle_renderer.gd).
## to_bbcode(lines, font_px) -> String: [b] [i] [u] [s] [color] [outline_color], and [font_size] for runs whose size
##   differs from 1.0 when font_px > 0.

const DEFAULT_ALIGNMENT := 2
## Smallest relative run size kept (ASS signs in tiny type stay readable).
const MIN_SIZE := 0.5


static func from_event(event: Dictionary) -> Dictionary:
	var lines: Array = []
	if event.get("styled") is Array and not (event["styled"] as Array).is_empty():
		for l: Dictionary in event["styled"]:
			var runs: Array = []
			for r: Dictionary in l.get("runs", []):
				runs.append(_run(str(r.get("text", "")), bool(r.get("bold", false)), bool(r.get("italic", false)),
						bool(r.get("underline", false)), bool(r.get("strikeout", false)), r.get("color", null),
						r.get("outline_color", null), float(r.get("size", 0.0))))
			lines.append({"runs": runs, "alignment": int(l.get("alignment", DEFAULT_ALIGNMENT))})
	elif str(event.get("ass", "")) != "":
		for line in str(event["ass"]).split("\n", false):
			lines.append(parse_ass(line))
	else:
		lines.append({"runs": [_run(str(event.get("text", "")))], "alignment": DEFAULT_ALIGNMENT})
	_relative_sizes(lines)
	var plain: Array[String] = []
	for l: Dictionary in lines:
		var t := ""
		for r: Dictionary in l["runs"]:
			t += str(r["text"])
		if t.strip_edges() != "":
			plain.append(t.strip_edges())
	var alignment := int(event.get("alignment", lines[0]["alignment"] if not lines.is_empty() else DEFAULT_ALIGNMENT))
	return {"lines": lines, "bbcode": to_bbcode(lines), "plain": "\n".join(plain), "alignment": alignment}


## The Text field of an ASS event line (after the eighth comma), or the line itself when it has fewer fields.
static func ass_text(line: String) -> String:
	var parts := line.split(",", true, 8)
	return parts[8] if parts.size() > 8 else line


## One ASS event line -> {runs, alignment}.
static func parse_ass(line: String) -> Dictionary:
	var text := ass_text(line)
	var runs: Array = []
	var state := {"b": false, "i": false, "u": false, "s": false, "c": null, "p": false}
	var alignment := DEFAULT_ALIGNMENT
	var buf := ""
	var i := 0
	while i < text.length():
		var ch := text[i]
		if ch == "{":
			var close := text.find("}", i)
			if close < 0:
				break
			if buf != "":
				runs.append(_run_from(buf, state))
				buf = ""
			alignment = _apply_tags(text.substr(i + 1, close - i - 1), state, alignment)
			i = close + 1
			continue
		if ch == "\\" and i + 1 < text.length() and text[i + 1] in ["N", "n", "h"]:
			if not state["p"]:
				buf += "\n" if text[i + 1] != "h" else " "
			i += 2
			continue
		if not state["p"]:
			buf += ch
		i += 1
	if buf != "":
		runs.append(_run_from(buf, state))
	return {"runs": _merge(runs), "alignment": alignment}


## Applies one override block's tags to `state`; returns the alignment (changed by \an / \a).
static func _apply_tags(block: String, state: Dictionary, alignment: int) -> int:
	for raw in block.split("\\", false):
		var t := raw.strip_edges()
		if t.begins_with("an") and t.substr(2).is_valid_int():
			alignment = clampi(t.substr(2).to_int(), 1, 9)
		elif t.begins_with("a") and t.substr(1).is_valid_int():
			# Legacy \a: 1-3 bottom, 5-7 top, 9-11 middle -> numpad.
			var a := t.substr(1).to_int()
			var col := (a - 1) % 4 + 1
			alignment = col + (6 if a >= 5 and a <= 7 else (3 if a >= 9 else 0))
		elif t.begins_with("1c") or (t.begins_with("c") and t.length() > 1 and t[1] == "&"):
			state["c"] = _ass_color(t.substr(2 if t.begins_with("1c") else 1))
		elif t == "c" or t == "1c":
			state["c"] = null
		elif t.length() >= 2 and t[0] in ["b", "i", "u", "s"] and t.substr(1).is_valid_int():
			var v := t.substr(1).to_int()
			state[t[0]] = v == 1 or (t[0] == "b" and v >= 600)
		elif t.begins_with("p") and t.substr(1).is_valid_int():
			state["p"] = t.substr(1).to_int() > 0
		elif t == "r":
			for k: String in ["b", "i", "u", "s"]:
				state[k] = false
			state["c"] = null
	return alignment


## "&HBBGGRR&" (or with alpha, &HAABBGGRR&) -> Color.
static func _ass_color(v: String) -> Variant:
	var hex := v.replace("&", "").replace("H", "").replace("h", "")
	if not hex.is_valid_hex_number():
		return null
	hex = hex.lpad(6, "0").right(6)
	return Color(hex.substr(4, 2).hex_to_int() / 255.0, hex.substr(2, 2).hex_to_int() / 255.0,
			hex.substr(0, 2).hex_to_int() / 255.0)


static func _run(text: String, b := false, i := false, u := false, s := false, color: Variant = null,
		outline: Variant = null, size := 0.0) -> Dictionary:
	return {"text": text, "bold": b, "italic": i, "underline": u, "strikeout": s, "color": color,
			"outline_color": outline, "size": size}


static func _run_from(text: String, state: Dictionary) -> Dictionary:
	return _run(text, state["b"], state["i"], state["u"], state["s"], state["c"])


static func _same_style(a: Dictionary, b: Dictionary) -> bool:
	for k: String in ["bold", "italic", "underline", "strikeout", "color", "outline_color", "size"]:
		if a[k] != b[k]:
			return false
	return true


## Neighbouring runs with the same style become one.
static func _merge(runs: Array) -> Array:
	var out: Array = []
	for r: Dictionary in runs:
		if not out.is_empty() and _same_style(out[-1], r):
			out[-1]["text"] = str(out[-1]["text"]) + str(r["text"])
			continue
		out.append(r.duplicate())
	return out


## Absolute run sizes (script units) -> relative to the event's largest; runs without a size are 1.0.
static func _relative_sizes(lines: Array) -> void:
	var largest := 0.0
	for l: Dictionary in lines:
		for r: Dictionary in l["runs"]:
			largest = maxf(largest, float(r["size"]))
	for l: Dictionary in lines:
		for r: Dictionary in l["runs"]:
			r["size"] = clampf(float(r["size"]) / largest, MIN_SIZE, 1.0) if largest > 0.0 and float(r["size"]) > 0.0 else 1.0


static func to_bbcode(lines: Array, font_px := 0) -> String:
	var out: Array[String] = []
	for l: Dictionary in lines:
		var line := ""
		for r: Dictionary in l["runs"]:
			var t := str(r["text"]).replace("[", "[lb]")
			if t == "":
				continue
			if r["color"] is Color and r["color"] != Color.WHITE:
				var c: Color = r["color"]
				t = "[color=#%s]%s[/color]" % [c.to_html(c.a < 1.0), t]
			if r["outline_color"] is Color and r["outline_color"] != Color.BLACK:
				var oc: Color = r["outline_color"]
				t = "[outline_color=#%s]%s[/outline_color]" % [oc.to_html(oc.a < 1.0), t]
			if font_px > 0 and float(r["size"]) < 0.999:
				t = "[font_size=%d]%s[/font_size]" % [maxi(roundi(font_px * float(r["size"])), 1), t]
			if r["strikeout"]:
				t = "[s]" + t + "[/s]"
			if r["underline"]:
				t = "[u]" + t + "[/u]"
			if r["italic"]:
				t = "[i]" + t + "[/i]"
			if r["bold"]:
				t = "[b]" + t + "[/b]"
			line += t
		if line.strip_edges() != "":
			out.append(line.strip_edges())
	return "\n".join(out)
