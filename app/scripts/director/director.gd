extends RefCounted

## Director mode (idea #8; docs/director.md): the open file's subtitle text as an index. Search it, and jump to where
## a line is said. The lines come from the engine's whole-track dump when it has one (MediaSource.get_subtitle_lines,
## requested from engine-demux), else from subtitle files next to the video (.srt, .vtt, .ass, .ssa; local only),
## parsed here (subtitle_text.gd). Building an index reads a whole track or file, so it runs on a worker thread, once
## per file and track; the result is kept for the last few. For a track inside the film the engine reads the WHOLE file
## (about 8 s for 800 MB, 12 to 23 s for 2 GB, PLAYER_REQUESTS), so building() tells a view how long it has read.
## Callers asking for the same index while it is built share that one read. An engine read that gives no lines (the
## file was closed, a share error: the engine says why) is not kept, so the next call tries again.
##
## For the pane (a Files-tab-style list):
##   const Director := preload("res://scripts/director/director.gd")
##   var idx: Dictionary = await Director.index(main)          # {path, source, track, tracks, count, error}
##   Director.search(idx, "where is the", 50)                  # [{i, start, end, text, before, after}]
##   Director.lines(idx, offset, count)                        # the whole script, page by page
##   Director.line_at(idx, main.player.get_position())         # the line being said now (-1: none)
##   Director.jump(main, hit)                                  # to just before the line, playing
##   Director.building(main)                                   # {seconds, source} while an index is read, else {}
## Commands (shared registry): find_line, jump_to_line, script_lines.

const SubtitleText := preload("res://scripts/director/subtitle_text.gd")
const DevCommands := preload("res://scripts/dev/dev_commands.gd")
const NetworkHosts := preload("res://scripts/net/network_hosts.gd")
const WorkerTask := preload("res://scripts/dev/worker_task.gd")

## Seconds before the line that a jump lands, so the line is heard from its start.
const DEFAULT_LEAD := 0.5
const CACHE_SIZE := 4

## "path|track" -> index
static var _cache := {}
static var _cache_order: Array[String] = []
## "path|track" -> {started (ticks msec), source} while that index is read. The pane's --ui-test puts a fake entry here
## (scripts/dev/ui_input_test.gd): tell app-shell before renaming it.
static var _building := {}


## The index for the open file (and a track: "" picks the subtitle track shown, else the first text track, else the
## first subtitle file). Never blocks the frame.
## The open file's subtitle text is indexed already, so index() returns at once. False while it is being built, and
## before: building may read the whole film (a network file too), which a quick caller must not start.
static func is_indexed(main: Node, track := "") -> bool:
	return _cache.has(str(main.current_path) + "|" + track)


static func index(main: Node, track := "") -> Dictionary:
	var path: String = main.current_path
	if path == "":
		return _empty("", "no file is open")
	var key := path + "|" + track
	if _cache.has(key):
		return _cache[key]
	var tree := main.get_tree()
	if _building.has(key):
		while _building.has(key):
			await tree.process_frame
		return _cache.get(key, _empty(path, "the subtitle text could not be read"))
	# What the worker needs, read here on the main thread.
	var media: Object = null
	var src: Object = main.player.source
	if src != null and "_media" in src:
		media = src.get("_media")
	var engine_tracks: Array = []
	var current := -1
	if media != null and media.has_method("get_subtitle_tracks"):
		for t: Dictionary in media.call("get_subtitle_tracks"):
			if bool(t.get("text", not bool(t.get("bitmap", false)))):
				engine_tracks.append(t)
		current = int(media.call("get_subtitle_track")) if media.has_method("get_subtitle_track") else -1
	var dump := media != null and media.has_method("get_subtitle_lines") and not engine_tracks.is_empty()
	_building[key] = {"started": Time.get_ticks_msec(), "source": "engine" if dump else "file"}
	var r: Dictionary = await WorkerTask.run(tree, func() -> Variant:
		return build(path, track, media, engine_tracks, current))
	_building.erase(key)
	var idx: Dictionary = r["result"] if r.get("result") is Dictionary else _empty(path, "no result")
	if not (idx["source"] == "engine" and idx["count"] == 0 and str(idx["error"]) != ""):
		_cache[key] = idx
		_cache_order.append(key)
		while _cache_order.size() > CACHE_SIZE:
			_cache.erase(_cache_order.pop_front())
	return idx


## While an index of the open file is read: {seconds: how long so far, source: engine (the whole film is read) or
## file}. Else {}.
static func building(main: Node) -> Dictionary:
	var path: String = main.current_path
	for key: String in _building:
		if key.begins_with(path + "|"):
			var b: Dictionary = _building[key]
			return {"seconds": (Time.get_ticks_msec() - int(b["started"])) / 1000.0, "source": b["source"]}
	return {}


## Forgets the indexes (a subtitle file was added, the engine loaded new tracks).
static func clear_cache() -> void:
	_cache.clear()
	_cache_order.clear()


static func _empty(path: String, error: String) -> Dictionary:
	return {"path": path, "source": "none", "track": "", "tracks": [], "lines": [], "count": 0, "error": error}


## Blocking (a worker thread). `media`: the playing MediaSource or null; `engine_tracks`: its text tracks.
static func build(path: String, track: String, media: Object, engine_tracks: Array, current: int) -> Dictionary:
	var tracks: Array = []
	var can_dump := media != null and media.has_method("get_subtitle_lines")
	if can_dump:
		for t: Dictionary in engine_tracks:
			var label := str(t.get("title", ""))
			if label == "":
				label = str(t.get("language", ""))
			tracks.append({"id": "t%d" % int(t["index"]), "label": label if label != "" else "track %d" % int(t["index"]),
					"source": "engine"})
	for f in sidecar_files(path):
		tracks.append({"id": f, "label": f.get_file(), "source": "file"})
	if tracks.is_empty():
		return _empty(path, "no text subtitles: no subtitle track the engine can dump, and no subtitle file next to "
				+ "the video")
	var chosen: Dictionary = {}
	for t: Dictionary in tracks:
		if track != "" and t["id"] == track:
			chosen = t
	if chosen.is_empty() and track != "":
		return _empty(path, "no subtitle track %s" % track)
	if chosen.is_empty() and current >= 0:
		for t: Dictionary in tracks:
			if t["id"] == "t%d" % current:
				chosen = t
	if chosen.is_empty():
		chosen = tracks[0]
	var raw: Array = []
	var error := ""
	if chosen["source"] == "engine":
		raw = media.call("get_subtitle_lines", int(str(chosen["id"]).substr(1)))
		if raw.is_empty() and media.has_method("get_last_error"):
			error = str(media.call("get_last_error"))
	else:
		raw = SubtitleText.parse_file(chosen["id"])
	var lines: Array = []
	for l: Dictionary in raw:
		var text := SubtitleText.strip_markup(str(l.get("plain", l.get("text", ""))))
		if text == "":
			continue
		lines.append({"start": float(l["start"]), "end": float(l.get("end", l["start"])), "text": text,
				"norm": normalise(text)})
	lines.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["start"] < b["start"])
	return {"path": path, "source": chosen["source"], "track": chosen["id"], "track_label": chosen["label"],
			"tracks": tracks, "lines": lines, "count": lines.size(), "error": error}


## Subtitle files that go with a local video: named after it (film.srt, film.en.srt), in its folder or a Subs /
## Subtitles folder next to it. Shares: none here (the engine loads those as tracks; external_subtitles.gd).
static func sidecar_files(video: String) -> Array[String]:
	var out: Array[String] = []
	if video.contains("://") or video == "":
		return out
	var dir := video.get_base_dir()
	var stem := video.get_file().get_basename().to_lower()
	for folder in [dir, dir.path_join("Subs"), dir.path_join("Subtitles"), dir.path_join("subs")]:
		if not DirAccess.dir_exists_absolute(folder):
			continue
		var files := Array(DirAccess.get_files_at(folder))
		files.sort()
		for f: String in files:
			if f.get_extension().to_lower() in SubtitleText.EXTENSIONS and f.to_lower().begins_with(stem) \
					and folder.path_join(f) not in out:
				out.append(folder.path_join(f))
	return out


## Lower case, letters and digits only, single spaces: what search compares.
static func normalise(s: String) -> String:
	var re := RegEx.create_from_string("[^\\p{L}\\p{N}']+")
	return re.sub(s.to_lower(), " ", true).replace("'", "").strip_edges()


## Lines that hold every word of the query (and each "quoted phrase" as it is), in time order:
## [{i, start, end, text, before, after}] with the lines either side for context.
static func search(idx: Dictionary, query: String, limit := 50) -> Array[Dictionary]:
	var lines: Array = idx.get("lines", [])
	var phrases: Array[String] = []
	var re := RegEx.create_from_string("\"([^\"]+)\"")
	for m in re.search_all(query):
		phrases.append(normalise(m.get_string(1)))
	var rest := normalise(re.sub(query, " ", true))
	var words := rest.split(" ", false)
	var out: Array[Dictionary] = []
	if phrases.is_empty() and words.is_empty():
		return out
	for i in lines.size():
		var n: String = " " + str(lines[i]["norm"]) + " "
		var ok := true
		for p in phrases:
			if not n.contains(" " + p + " "):
				ok = false
				break
		if ok:
			for w in words:
				if not n.contains(w):
					ok = false
					break
		if ok:
			out.append(_entry(lines, i))
			if out.size() >= limit:
				break
	return out


## Lines offset .. offset + count of the whole script, as search() entries.
static func lines(idx: Dictionary, offset := 0, count := 100) -> Array[Dictionary]:
	var all: Array = idx.get("lines", [])
	var out: Array[Dictionary] = []
	for i in range(maxi(offset, 0), mini(offset + count, all.size())):
		out.append(_entry(all, i))
	return out


## The index of the line being said at `t`, else the last one before it; -1 before the first.
static func line_at(idx: Dictionary, t: float) -> int:
	var all: Array = idx.get("lines", [])
	var lo := 0
	var hi := all.size() - 1
	var best := -1
	while lo <= hi:
		var mid := (lo + hi) / 2
		if float(all[mid]["start"]) <= t:
			best = mid
			lo = mid + 1
		else:
			hi = mid - 1
	return best


static func _entry(all: Array, i: int) -> Dictionary:
	var l: Dictionary = all[i]
	return {"i": i, "start": snappedf(l["start"], 0.001), "end": snappedf(l["end"], 0.001), "text": l["text"],
			"before": all[i - 1]["text"] if i > 0 else "", "after": all[i + 1]["text"] if i + 1 < all.size() else ""}


## Seeks to just before a line and plays.
static func jump(main: Node, entry: Dictionary, lead := DEFAULT_LEAD) -> float:
	var t := maxf(float(entry["start"]) - lead, 0.0)
	main.player.seek(t)
	if not main.player.is_playing():
		main.player.play()
	return t


## The shared commands (command_host.gd).
static func register_commands(host: Node) -> void:
	var track_param := {"name": "track", "type": "string", "default": "",
			"description": "a track id from the reply's tracks (t<n>: a track inside the film; a path: a subtitle "
					+ "file); empty: the track shown, else the first"}
	DevCommands.register("find_line", func(args: Dictionary, ctx: DevCommands.Call) -> Variant:
		var idx: Dictionary = await index(host.main, args["track"])
		if idx["count"] == 0:
			return ctx.fail(idx["error"])
		return {"path": idx["path"], "source": idx["source"], "track": idx["track"], "tracks": idx["tracks"],
				"lines": idx["count"], "hits": search(idx, args["query"], args["limit"])}, {
		"description": "Director mode: searches the open file's subtitle text (the Subtitles tab's Find a line). Every "
				+ "word must appear; \"quoted phrases\" as written. The first search of a film whose subtitles are "
				+ "inside it reads the whole file, which can take minutes.",
		"params": [{"name": "query", "type": "string", "required": true,
				"description": "the words to find, e.g. \"the door\" key"},
				{"name": "limit", "type": "int", "default": 20, "description": "at most this many lines back"},
				track_param],
		"assistant": "read", "returns": "{path, source: engine|file, track, tracks, lines, hits: [{i, start, end, text, before, after}]}"})
	DevCommands.register("jump_to_line", func(args: Dictionary, ctx: DevCommands.Call) -> Variant:
		var idx: Dictionary = await index(host.main, args["track"])
		if idx["count"] == 0:
			return ctx.fail(idx["error"])
		var entry := {}
		if int(args["i"]) >= 0:
			if int(args["i"]) >= idx["count"]:
				return ctx.fail("there are %d lines" % idx["count"])
			entry = _entry(idx["lines"], int(args["i"]))
		else:
			var hits := search(idx, args["query"], int(args["n"]))
			if hits.size() < int(args["n"]):
				return ctx.fail("%s: %d match%s" % [args["query"], hits.size(), "" if hits.size() == 1 else "es"])
			entry = hits[int(args["n"]) - 1]
		var old: float = host.main.player.get_position()
		var t := jump(host.main, entry, args["lead"])
		ctx.summary = "to %s: %s" % [_clock(t), str(entry["text"]).replace("\n", " ")]
		ctx.undo = func() -> void: host.main.player.seek(old)
		return {"time": t, "line": entry}, {
		"description": "Director mode: jumps to just before a subtitle line (the n-th match of a query, or line i) "
				+ "and plays, as a row of the Subtitles tab's Script does.",
		"params": [{"name": "query", "type": "string", "default": "",
				"description": "words of the line, as find_line takes them; used when i is -1"},
				{"name": "n", "type": "int", "default": 1, "description": "which match of the query, 1 = the first"},
				{"name": "i", "type": "int", "default": -1,
				"description": "a line's number (i from find_line or script_lines); -1 to use query"},
				{"name": "lead", "type": "float", "default": DEFAULT_LEAD,
				"description": "seconds before the line to start"},
				track_param],
		"level": "control", "assistant": "control", "returns": "{time, line}"})
	DevCommands.register("script_lines", func(args: Dictionary, ctx: DevCommands.Call) -> Variant:
		var idx: Dictionary = await index(host.main, args["track"])
		if idx["count"] == 0:
			return ctx.fail(idx["error"])
		var now := line_at(idx, host.main.player.get_position())
		var offset: int = args["offset"]
		if offset < 0:
			offset = maxi(now - int(args["count"]) / 2, 0)
		return {"total": idx["count"], "current": now, "offset": offset, "track": idx["track"],
				"lines": lines(idx, offset, args["count"])}, {
		"description": "Director mode: the open file's subtitle lines, a page at a time (offset -1: around the line "
				+ "being said now; the Subtitles tab's Lines around now).",
		"params": [{"name": "offset", "type": "int", "default": -1,
				"description": "the first line's number, or -1 for the lines around now"},
				{"name": "count", "type": "int", "default": 40, "description": "how many lines"},
				track_param],
		"assistant": "read", "returns": "{total, current, offset, track, lines: [...]}"})


static func _clock(t: float) -> String:
	var s := int(t)
	return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60] if s >= 3600 else "%d:%02d" % [s / 60, s % 60]
