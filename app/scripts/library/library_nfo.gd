extends RefCounted

## NFO files as Kodi writes and reads them (docs/library.md): XML with the root tvshow, episodedetails or movie. The
## fields are those of Kodi's own parser (xbmc/video/VideoInfoTag.cpp). Everything is optional and a broken file gives
## what was read before it broke, or {}. Nothing in a file is followed or run: thumb and fanart URLs are not read at
## all, and nested elements (actor, ratings, fileinfo, ...) are skipped.
##
## Works on any thread. A file with several episodedetails is one file with several episodes: "episodes" lists them.
## A line after the XML (a scraper's URL, in Kodi's "hybrid" files) is ignored.
##
##   LibraryNfo.read(path) -> {kind: tvshow | episodedetails | movie, title, plot, ..., genre: [...], named_seasons:
##       {number: name}, episodes: [...]}, or {}
##   LibraryNfo.number(d, "season") -> int, -1 without one;  LibraryNfo.year(d) -> int, 0 without one

## Bigger than this is not an NFO.
const MAX_BYTES := 1048576
const TEXT_MAX := 4000
const ROOTS := ["tvshow", "episodedetails", "movie"]
const FIELDS := ["title", "showtitle", "originaltitle", "sorttitle", "plot", "outline", "tagline", "premiered", "aired",
		"year", "runtime", "season", "episode", "displayseason", "displayepisode", "mpaa", "genre", "studio",
		"namedseason"]
## Repeated elements, kept as lists.
const LISTS := ["genre", "studio"]


static func read(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() > MAX_BYTES:
		return {}
	return parse(f.get_buffer(f.get_length()))


static func parse(bytes: PackedByteArray) -> Dictionary:
	var text := _as_utf8(bytes)
	var x := XMLParser.new()
	if text.is_empty() or x.open_buffer(text) != OK:
		return {}
	var found: Array[Dictionary] = []
	var entry := {}
	var depth := 0
	var field := ""
	var season := -1
	var value := ""
	while x.read() == OK:
		match x.get_node_type():
			XMLParser.NODE_ELEMENT:
				var tag := x.get_node_name().to_lower()
				if depth == 0 and tag in ROOTS:
					entry = {"kind": tag}
					found.append(entry)
				elif depth == 1 and tag in FIELDS and not found.is_empty():
					field = tag
					value = ""
					season = x.get_named_attribute_value_safe("number").to_int() if tag == "namedseason" else -1
				if not x.is_empty():
					depth += 1
			XMLParser.NODE_ELEMENT_END:
				depth = maxi(depth - 1, 0)
				if depth == 1 and field != "":
					_store(entry, field, season, value)
					field = ""
			XMLParser.NODE_TEXT:
				if depth == 2 and field != "" and value.length() < TEXT_MAX:
					value += x.get_node_data().xml_unescape()
			XMLParser.NODE_CDATA:
				# The engine gives a CDATA section's text as its name.
				if depth == 2 and field != "" and value.length() < TEXT_MAX:
					value += x.get_node_name()
	if field != "":
		_store(entry, field, season, value)  # The file stopped inside this element.
	if found.is_empty():
		return {}
	var out: Dictionary = found[0]
	if found.size() > 1:
		out["episodes"] = found
	return out


static func _store(entry: Dictionary, field: String, season: int, value: String) -> void:
	var v := value.strip_edges().left(TEXT_MAX)
	if v == "":
		return
	if field == "namedseason":
		if season >= 0:
			if not entry.has("named_seasons"):
				entry["named_seasons"] = {}
			entry["named_seasons"][season] = v
	elif field in LISTS:
		if not entry.has(field):
			entry[field] = []
		(entry[field] as Array).append(v)
	else:
		entry[field] = v


## UTF-8 with no byte order mark.
static func _as_utf8(b: PackedByteArray) -> PackedByteArray:
	if b.size() >= 3 and b[0] == 0xEF and b[1] == 0xBB and b[2] == 0xBF:
		return b.slice(3)
	if b.size() >= 2 and ((b[0] == 0xFF and b[1] == 0xFE) or (b[0] == 0xFE and b[1] == 0xFF)):
		return b.get_string_from_utf16().to_utf8_buffer()
	return b


## A whole number from a field, or -1.
static func number(d: Dictionary, field: String) -> int:
	var v := str(d.get(field, ""))
	return v.to_int() if v.is_valid_int() and v.to_int() >= 0 else -1


## premiered or aired (YYYY-MM-DD) as Kodi prefers, else year; 0 without one.
static func year(d: Dictionary) -> int:
	for field: String in ["premiered", "aired"]:
		var v := str(d.get(field, "")).left(4)
		if v.length() == 4 and v.is_valid_int():
			return v.to_int()
	return maxi(number(d, "year"), 0)


## The short text for a row: the outline when there is one, else the plot.
static func summary(d: Dictionary) -> String:
	return str(d.get("outline", d.get("plot", "")))
