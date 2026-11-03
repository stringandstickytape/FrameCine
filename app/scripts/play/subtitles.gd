extends Node

## Subtitle state: the file's tracks, the selected one, on/off, and the lines to show now. Events come from the source
## (MediaSource's read_subtitle_event(); the test patterns have two text tracks of their own) and are kept for the
## whole file, de-duplicated, so a jump back (catch-up replay, a seek) shows earlier lines even when the demuxer does
## not deliver them again. The renderer (scripts/play/subtitle_renderer.gd, `display`) draws them as a quad below the
## picture with their style (text) or pictures (PGS, VobSub, DVB); anything else can listen to text_changed.
##
##   tracks                     [{index, codec, language, title, text, bitmap, default, forced}] of the open file
##   track                      selected index, -1 for none
##   enabled                    the user's on/off ([subtitles] enabled); off selects no track, which saves demux work
##   text                       the plain line(s) showing now ("" for none; picture lines have no text)
##   set_enabled(on), select_track(index) (also turns them on; -1 turns them off), cycle_track()
##   get_state() / set_state(state)   {enabled, track}: for features that change them for a while (catch-up replay)
##   pick_track() -> index       the track chosen when subtitles turn on: the pick_override callable first (language
##                               memory), then the default-flagged text track, then the first text track
##   delay                      seconds added to every event's time (positive: later); see subtitle delay (#61)
##   add_event(start, end, text, event := {})   event: the source's dictionary (style, bitmap images)
##   text_at(t) -> String, events_at(t) -> Array[Dictionary], event_count()
##   signals tracks_changed(tracks), track_changed(index, enabled), text_changed(text)
##   by_user                    whether the last track_changed came from the user (select_track, set_enabled,
##                              cycle_track) rather than the automatic pick on open or a feature's set_state()
## Second track (ideas #65), shown above the main one, smaller and tinted, while subtitles are on:
##   secondary                  its index, -1 for none
##   secondary_tracks() -> Array[Dictionary]   tracks that can be the second one, other than the main track:
##                              subtitle files next to the video (#50), read here (subtitle_file.gd), and the file's
##                              own text tracks, read by the engine alongside the main one
##                              (select_secondary_subtitle_track, engine PLAYER_REQUESTS; events carry "track").
##                              Like a track change, choosing one doesn't seek: its lines start from where the
##                              demuxer is reading.
##   select_secondary(index)    -1 for none; remembers the language, and later files open with a second track in it
##   cycle_secondary(), signal secondary_changed(index)
## Desktop keys (menu hidden): S cycles off / each track; Shift+S cycles the second track.
## Settings: [subtitles] enabled, secondary_language; the renderer's size, position, offset, depth, background.

const SubtitleRenderer := preload("res://scripts/play/subtitle_renderer.gd")
const SubtitleFile := preload("res://scripts/play/subtitle_file.gd")

signal tracks_changed(tracks: Array)
signal track_changed(index: int, enabled: bool)
signal text_changed(text: String)
signal secondary_changed(index: int)

## Events kept per file.
const MAX_EVENTS := 20000
## An event without an end shows until the next one, but no longer than this (text) ...
const OPEN_END_SECONDS := 8.0
## ... or this (pictures: a picture track ends a line with an empty event, so this is only a guard).
const BITMAP_OPEN_END_SECONDS := 30.0


## Events of one track, sorted by start: [[start, end, text, event, id], ...].
class EventList:
	var events: Array = []
	var seen := {}

	func clear() -> void:
		events.clear()
		seen.clear()

	## False for a duplicate (same start and text, or same start and picture count).
	func add(entry: Array) -> bool:
		var e: Dictionary = entry[3]
		var what: String = ("bitmap%d" % (e.get("images", []) as Array).size()) if bool(e.get("bitmap", false)) \
				else str(entry[2])
		var key := "%.3f|%s" % [entry[0], what]
		if seen.has(key):
			return false
		seen[key] = true
		var start: float = entry[0]
		if events.is_empty() or float(events[-1][0]) <= start:
			events.append(entry)
		else:
			events.insert(events.bsearch_custom(start, func(a: Variant, b: Variant) -> bool:
				return (float(a[0]) if a is Array else float(a)) < (float(b[0]) if b is Array else float(b))), entry)
		if events.size() > MAX_EVENTS:
			events.pop_front()
		return true

	## Entries showing at t, oldest first. An event without an end lasts until the next one.
	func active(t: float) -> Array:
		var out: Array = []
		if events.is_empty():
			return out
		var hi := events.bsearch_custom(t, func(a: Variant, b: Variant) -> bool:
			return (float(a[0]) if a is Array else float(a)) <= (float(b[0]) if b is Array else float(b)))
		var i := hi - 1
		while i >= 0 and t - float(events[i][0]) < 60.0:
			var e: Array = events[i]
			var end: float = e[1]
			if end < 0.0:
				# Until the next event of the same kind (text or picture), within the cap.
				var bitmap := bool(e[3].get("bitmap", false))
				var cap: float = BITMAP_OPEN_END_SECONDS if bitmap else OPEN_END_SECONDS
				end = float(e[0]) + cap
				for j in range(i + 1, mini(i + 9, events.size())):
					if bool(events[j][3].get("bitmap", false)) == bitmap:
						end = minf(end, float(events[j][0]))
						break
			if t < end and _draws(e):
				out.push_front(e)
			i -= 1
		return out

	static func _draws(e: Array) -> bool:
		if bool(e[3].get("bitmap", false)):
			return not (e[3].get("images", []) as Array).is_empty()
		return str(e[2]) != ""


var main: Node3D
var tracks: Array[Dictionary] = []
var track := -1
var enabled := false
var text := ""
var delay := 0.0
## Callable(tracks: Array[Dictionary]) -> int (-1: no opinion). Set by language memory.
var pick_override: Callable
var by_user := false
var display: SubtitleRenderer
var secondary := -1
var _list := EventList.new()
var _second := EventList.new()
var _next_id := 0
var _secondary_serial := 0
## Worker tasks reading a second track's file: waited for when they finish and at exit (an unwaited task's lambda is
## freed after the script runtime at exit, which corrupted the heap; found by dev-plumbing).
var _tasks: Array[int] = []
## The second track is one of the file's own, read by the engine alongside the main one (select_secondary_subtitle_track,
## engine PLAYER_REQUESTS); else it is a subtitle file read here.
var _secondary_embedded := false
var _shown_ids: Array = []


func _ready() -> void:
	enabled = bool(main.settings.get_value("subtitles", "enabled", false))
	display = SubtitleRenderer.new()
	display.name = "SubtitleRenderer"
	display.main = main
	add_child(display)
	main.file_opened.connect(_on_file_opened)


func _on_file_opened(_path: String) -> void:
	_list.clear()
	_set_text("")
	_show([], [])
	track = -1
	_clear_secondary()
	# The user's own on/off, not a feature's state from the last file (catch-up, forced parts, always-on).
	enabled = bool(main.settings.get_value("subtitles", "enabled", false))
	tracks = []
	var src: Object = main.player.source
	if src != null:
		tracks = src.get_subtitle_tracks()
	tracks_changed.emit(tracks)
	if enabled:
		_select(pick_track())
	by_user = false
	track_changed.emit(track, enabled)
	secondary_changed.emit(secondary)


## Re-reads the track list (subtitle files were added to the source). If the user has subtitles on and hasn't chosen
## a track for this file, the pick is made again, so a file in the remembered language can win. A feature's track
## (forced parts, catch-up) is left alone. A second track in the remembered second language is picked if a file has it.
func refresh_tracks() -> void:
	var src: Object = main.player.source
	if src == null:
		return
	tracks = src.get_subtitle_tracks()
	tracks_changed.emit(tracks)
	if enabled and not by_user and bool(main.settings.get_value("subtitles", "enabled", false)):
		var t := pick_track()
		if t != track:
			_select(t)
			track_changed.emit(track, enabled)
	_auto_secondary()


## The track subtitles turn on with (see the header), or -1 when the file has none.
func pick_track() -> int:
	if tracks.is_empty():
		return -1
	if pick_override.is_valid():
		var i: int = pick_override.call(tracks)
		if i >= 0 and i < tracks.size():
			return i
	for t: Dictionary in tracks:
		if bool(t.get("default", false)) and bool(t.get("text", true)):
			return int(t["index"])
	for t: Dictionary in tracks:
		if bool(t.get("text", true)):
			return int(t["index"])
	return int(tracks[0]["index"])


func set_enabled(on: bool) -> void:
	enabled = on
	main.settings.set_value("subtitles", "enabled", on)
	# On: the pick, unless the user chose this file's track (a feature's track, such as forced parts, gives way).
	_select(pick_track() if on and (track < 0 or not by_user) else (track if on else -1))
	by_user = true
	track_changed.emit(track, enabled)


## index -1: off. Any other index turns subtitles on with that track.
func select_track(index: int) -> void:
	if index < 0:
		set_enabled(false)
		return
	enabled = true
	main.settings.set_value("subtitles", "enabled", true)
	_select(index)
	by_user = true
	track_changed.emit(track, enabled)


## Off, then each track in turn.
func cycle_track() -> void:
	if tracks.is_empty():
		return
	var pos := -1
	for i in tracks.size():
		if int(tracks[i]["index"]) == track:
			pos = i
	if not enabled or track < 0:
		select_track(int(tracks[0]["index"]))
	elif pos + 1 < tracks.size():
		select_track(int(tracks[pos + 1]["index"]))
	else:
		set_enabled(false)


func get_state() -> Dictionary:
	return {"enabled": enabled, "track": track}


## Puts back a state from get_state() (not saved as the user's setting unless `remember`).
func set_state(state: Dictionary, remember := false) -> void:
	enabled = bool(state.get("enabled", false))
	if remember:
		main.settings.set_value("subtitles", "enabled", enabled)
	_select(int(state.get("track", -1)) if enabled else -1)
	by_user = false
	track_changed.emit(track, enabled)


## The selected track's dictionary, or {}.
func current_track() -> Dictionary:
	for t: Dictionary in tracks:
		if int(t["index"]) == track:
			return t
	return {}


func _select(index: int) -> void:
	if index == track:
		return
	track = index
	_list.clear()
	_set_text("")
	_show([], [])
	if index >= 0 and index == secondary:
		_clear_secondary()
		secondary_changed.emit(secondary)
	var src: Object = main.player.source
	if src != null:
		src.select_subtitle_track(index)


func _process(_delta: float) -> void:
	if track < 0 or not main.player.has_source():
		if not _shown_ids.is_empty():
			_show([], [])
		return
	var src: Object = main.player.source
	for i in 64:
		var e: Dictionary = src.read_subtitle_event()
		if e.is_empty():
			break
		if _secondary_embedded and int(e.get("track", -2)) == secondary:
			_next_id += 1
			_second.add([float(e.get("start", 0.0)), float(e.get("end", -1.0)), str(e.get("text", "")), e, _next_id])
			continue
		add_event(float(e.get("start", 0.0)), float(e.get("end", -1.0)), str(e.get("text", "")), e)
	var t: float = main.player.get_position() - delay
	var primary := _list.active(t)
	var second := _second.active(t) if secondary >= 0 else []
	if _ids(primary, second) != _shown_ids:
		_show(primary, second)
	_set_text(_join(primary))


## Adds an event (de-duplicated by start and text), kept sorted by start. `event`: the source's dictionary (style,
## bitmap images); {} for plain text.
func add_event(start: float, end: float, line: String, event: Dictionary = {}) -> void:
	if event.is_empty():
		event = {"text": line}
	_next_id += 1
	_list.add([start, end, line, event, _next_id])


## The line(s) showing at media time t ("" for none). Overlapping lines stack (oldest on top).
func text_at(t: float) -> String:
	return _join(_list.active(t))


## The source's event dictionaries showing at media time t, oldest first (text and pictures).
func events_at(t: float) -> Array:
	return _list.active(t).map(func(e: Array) -> Dictionary: return e[3])


func event_count() -> int:
	return _list.events.size()


## The last `count` text lines that started at or before media time t, oldest first: [{start, text}]. From the lines
## the player has read so far (a track is selected; shown or not), so it costs nothing and never reads the file. Used
## for an assistant's context (scripts/assistant/assistant_commands.gd).
func lines_before(t: float, count: int) -> Array:
	var out: Array = []
	var i := _list.events.size() - 1
	while i >= 0 and out.size() < count:
		var e: Array = _list.events[i]
		i -= 1
		if float(e[0]) > t - delay or str(e[2]).strip_edges() == "":
			continue
		out.push_front({"start": snappedf(float(e[0]), 0.01), "text": str(e[2])})
	return out


func _join(entries: Array) -> String:
	var lines: Array[String] = []
	for e: Array in entries:
		if str(e[2]) != "":
			lines.append(str(e[2]))
	return "\n".join(lines)


func _ids(primary: Array, second: Array) -> Array:
	var ids: Array = []
	for e: Array in primary:
		ids.append(e[4])
	for e: Array in second:
		ids.append(-int(e[4]))
	return ids


func _show(primary: Array, second: Array) -> void:
	_shown_ids = _ids(primary, second)
	if display != null:
		display.show_events(primary.map(func(e: Array) -> Dictionary: return e[3]),
				second.map(func(e: Array) -> Dictionary: return e[3]))


## Tracks that can be the second one, other than the main track: subtitle files the app can read, and the file's own
## text tracks when the engine reads two at once.
func secondary_tracks() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var src: Object = main.player.source
	var embedded: bool = src != null and src.has_method("has_secondary_subtitles") and src.has_secondary_subtitles()
	for t: Dictionary in tracks:
		var i := int(t["index"])
		if i == track:
			continue
		if _file_for(i) != "" or (embedded and _is_own_text(t)):
			out.append(t)
	return out


## A text track inside the file (not a subtitle file next to it, not pictures).
func _is_own_text(t: Dictionary) -> bool:
	if bool(t.get("bitmap", false)) or bool(t.get("external", false)):
		return false
	return bool(t.get("text", true)) and _file_for(int(t["index"])) == ""


## -1: none. `remember`: keep its language for later files ([subtitles] secondary_language).
func select_secondary(index: int, remember := true) -> void:
	if index == secondary or (index >= 0 and (index == track or not _can_be_second(index))):
		return
	_clear_secondary()
	secondary = index
	if remember:
		var lang := ""
		for t: Dictionary in tracks:
			if int(t["index"]) == index:
				lang = _language(t)
		main.settings.set_value("subtitles", "secondary_language", lang if lang != "" else null)
	if index >= 0:
		var path := _file_for(index)
		if path == "":
			var src: Object = main.player.source
			src.select_secondary_subtitle_track(index)
			_secondary_embedded = true
		else:
			var serial := _secondary_serial
			_tasks.append(WorkerThreadPool.add_task(func() -> void:
				_secondary_loaded.call_deferred(serial, SubtitleFile.load_file(path))))
	secondary_changed.emit(secondary)


func _can_be_second(index: int) -> bool:
	for t: Dictionary in secondary_tracks():
		if int(t["index"]) == index:
			return true
	return false


## Off, then each possible second track in turn.
func cycle_secondary() -> void:
	var options := secondary_tracks()
	var pos := -1
	for i in options.size():
		if int(options[i]["index"]) == secondary:
			pos = i
	select_secondary(int(options[pos + 1]["index"]) if pos + 1 < options.size() else -1)


func _secondary_loaded(serial: int, events: Array) -> void:
	for i in range(_tasks.size() - 1, -1, -1):
		if WorkerThreadPool.is_task_completed(_tasks[i]):
			WorkerThreadPool.wait_for_task_completion(_tasks[i])
			_tasks.remove_at(i)
	if serial != _secondary_serial or secondary < 0:
		return
	for e: Dictionary in events:
		_next_id += 1
		_second.add([float(e["start"]), float(e["end"]), str(e["text"]), e, _next_id])
	print("Second subtitle track: %d lines" % events.size())


func _clear_secondary() -> void:
	if _secondary_embedded:
		var src: Object = main.player.source
		if src != null and src.has_method("select_secondary_subtitle_track"):
			src.select_secondary_subtitle_track(-1)
	_secondary_embedded = false
	secondary = -1
	_secondary_serial += 1
	_second.clear()


func _exit_tree() -> void:
	for t in _tasks:
		WorkerThreadPool.wait_for_task_completion(t)
	_tasks.clear()


## On open and when subtitle files arrive: the remembered second language, if a file other than the main track has it.
func _auto_secondary() -> void:
	var lang := str(main.settings.get_value("subtitles", "secondary_language", ""))
	if lang == "" or secondary >= 0:
		return
	for t: Dictionary in secondary_tracks():
		if _language(t) == lang:
			select_secondary(int(t["index"]), false)
			return


func _file_for(index: int) -> String:
	var features: Object = main.get("features")
	var files: Object = features.get("sub_files") if features != null else null
	if files == null:
		return ""
	for f: Dictionary in files.loaded:
		if int(f.get("index", -1)) == index:
			return str(f.get("path", ""))
	return ""


static func _language(t: Dictionary) -> String:
	return str(t.get("language_code", t.get("language", ""))).to_lower()


func _set_text(t: String) -> void:
	if t == text:
		return
	text = t
	text_changed.emit(t)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or main.menu_shown or main.window_pointer.is_active():
		return
	if key.keycode == KEY_S and key.shift_pressed:
		cycle_secondary()
		print("Second subtitle track: %d" % secondary)
	elif key.keycode == KEY_S:
		cycle_track()
		var t := current_track()
		print("Subtitles: %s" % ("off" if not enabled or t.is_empty() else "%s %s" % [t.get("language", ""), t.get("title", "")]))
