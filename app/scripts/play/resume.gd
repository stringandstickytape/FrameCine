extends Node

## Resume per file (ideas #7): remembers where each file was left, resumes there (or offers to), and keeps the data
## for a "continue watching" row in the browser.
##
## Positions live in their own file, user://resume.cfg (not settings.cfg: it changes every few seconds while
## playing), one section per file key (scripts/play/file_key.gd: hash of path and size, path only on a share):
##   path, title, position, duration, updated (Unix time), finished (bool)
## A position is saved every SAVE_SECONDS while playing, on pause, when another file opens, and on exit. Positions
## under MIN_POSITION are not saved and don't replace a saved one, so opening a file by mistake keeps its place.
## Within the last FINISHED_FRACTION of the duration, or FINISHED_SECONDS, whichever is longer, or at the end, the
## file counts as finished: its position is cleared and `finished` set, so a row can show it as watched. At most
## MAX_ENTRIES are kept (the oldest go first).
##
## Behaviour on open, setting [resume] mode:
##   "auto" (default)  seek to the saved position, then emit resumed(position). The pane can show "Resumed at 0:42:17,
##                     start over?"; start_over() goes back to 0 (so does the B button / previous, as before).
##   "ask"             don't seek; emit resume_offered(position). The pane calls resume() or start_over().
##   "off"             neither saves nor resumes.
## API: position_for(path), entry_for(path), continue_watching(limit), forget(path), resume(), start_over(),
##      pending_position (the offered position in "ask" mode, or -1).
## Test patterns (stub://) are included (they are how this is tested on a desktop); windows are not.

const FileKey := preload("res://scripts/play/file_key.gd")

signal resumed(position: float)
signal resume_offered(position: float)
## The saved data changed (a row's marker or the continue-watching list may need a refresh).
signal entries_changed

const PATH := "user://resume.cfg"
const SAVE_SECONDS := 5.0
const MIN_POSITION := 30.0
const FINISHED_FRACTION := 0.05
const FINISHED_SECONDS := 60.0
const MAX_ENTRIES := 500
## Resume this far before the saved position, so the scene is picked up again.
const REWIND := 3.0

var main: Node3D
var mode := "auto"
## Offered position in "ask" mode, or -1.
var pending_position := -1.0
var read_only := false
var _cfg := ConfigFile.new()
var _dirty := false
var _path := ""
var _key := ""
var _last_pos := 0.0
var _last_duration := 0.0
var _timer := 0.0
var _save_timer := 0.0


func _ready() -> void:
	mode = str(main.settings.get_value("resume", "mode", "auto"))
	read_only = main.settings.read_only
	if not read_only:
		var err := _cfg.load(PATH)
		if err != OK and err != ERR_FILE_NOT_FOUND:
			push_warning("Can't read %s (%s)" % [PATH, error_string(err)])
	main.file_opened.connect(_on_file_opened)
	main.player.playing_changed.connect(func(playing: bool) -> void:
		if not playing:
			_record())
	main.player.ended.connect(_on_ended)


func _process(delta: float) -> void:
	if _key != "" and main.player.has_source():
		_last_pos = main.player.get_position()
		var d: float = main.player.get_duration()
		if d > 0.0:
			_last_duration = d
		_timer += delta
		if _timer >= SAVE_SECONDS and main.player.is_playing():
			_timer = 0.0
			_record()
	_save_timer += delta
	if _save_timer >= 10.0:
		_save_timer = 0.0
		save_if_dirty()


func _on_file_opened(path: String) -> void:
	# The file before: its last known position.
	_record()
	_path = path
	_key = ""
	_last_pos = 0.0
	_last_duration = 0.0
	_timer = 0.0
	pending_position = -1.0
	if path == "" or mode == "off" or not _tracked(path):
		return
	_key = FileKey.key(path)
	var pos := position_for(path)
	if pos <= 0.0:
		return
	if mode == "ask":
		pending_position = pos
		resume_offered.emit(pos)
	else:
		# Next frame: the source has just been opened in this call chain.
		_seek_and_announce.call_deferred(pos)


func _seek_and_announce(pos: float) -> void:
	if not main.player.can_seek():
		return
	if main.player.get_position() > 0.5:
		return  # Already playing on from elsewhere (picture in picture swapped in, #87): keep its place.
	main.player.seek(maxf(pos - REWIND, 0.0))
	resumed.emit(pos)
	print("Resumed %s at %s" % [_path.get_file(), _clock(pos)])


## "ask" mode: go to the offered position.
func resume() -> void:
	if pending_position > 0.0:
		var pos := pending_position
		pending_position = -1.0
		_seek_and_announce(pos)


func start_over() -> void:
	pending_position = -1.0
	if main.player.has_source():
		main.player.seek(0.0)
		_last_pos = 0.0
	if _key != "" and _cfg.has_section(_key):
		_cfg.set_value(_key, "position", 0.0)
		_dirty = true
		entries_changed.emit()


func _on_ended() -> void:
	if _key == "":
		return
	_last_pos = _last_duration
	_record()


## Saves the current file's position (or marks it finished).
func _record() -> void:
	if _key == "" or mode == "off" or not main.player.has_source():
		return
	var pos := _last_pos
	var duration := _last_duration
	if duration <= 0.0:
		return
	var finished := pos >= duration - maxf(duration * FINISHED_FRACTION, FINISHED_SECONDS)
	if not finished and pos < MIN_POSITION:
		# A short visit doesn't wipe a saved place (start_over() does).
		return
	# Listeners (the Files tab's markers rebuild every row) hear only of a new entry or a change of finished, not of
	# every position update: seen on the headset, a rebuild every SAVE_SECONDS dropped a video frame each time.
	var notable := not _cfg.has_section(_key) or bool(_cfg.get_value(_key, "finished", false)) != finished
	_cfg.set_value(_key, "path", _path)
	_cfg.set_value(_key, "title", main.display_title() if main.current_path == _path else _path.get_file())
	_cfg.set_value(_key, "position", 0.0 if finished else snappedf(pos, 0.1))
	_cfg.set_value(_key, "duration", snappedf(duration, 0.1))
	_cfg.set_value(_key, "updated", int(Time.get_unix_time_from_system()))
	_cfg.set_value(_key, "finished", finished)
	_dirty = true
	_prune()
	if notable:
		entries_changed.emit()


## Saved position for a file (0 when none, or finished).
func position_for(path: String) -> float:
	var k := FileKey.key(path)
	return float(_cfg.get_value(k, "position", 0.0)) if _cfg.has_section(k) else 0.0


## {path, title, position, duration, updated, finished, progress 0..1}, or {} when the file has no entry.
func entry_for(path: String) -> Dictionary:
	return _entry(FileKey.key(path))


## The same by the file's key (FileKey), for what a worker thread worked out: no file is opened.
func entry_by_key(key: String) -> Dictionary:
	return _entry(key)


## Files started and not finished, most recent first: [{path, title, position, duration, updated, progress}].
func continue_watching(limit := 10) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for k in _cfg.get_sections():
		var e := _entry(k)
		if not e["finished"] and float(e["position"]) > 0.0:
			out.append(e)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["updated"]) > int(b["updated"]))
	return out.slice(0, limit)


func forget(path: String) -> void:
	var k := FileKey.key(path)
	if _cfg.has_section(k):
		_cfg.erase_section(k)
		_dirty = true
		entries_changed.emit()


func _entry(k: String) -> Dictionary:
	if not _cfg.has_section(k):
		return {}
	var d := float(_cfg.get_value(k, "duration", 0.0))
	var p := float(_cfg.get_value(k, "position", 0.0))
	return {"path": str(_cfg.get_value(k, "path", "")), "title": str(_cfg.get_value(k, "title", "")), "position": p,
			"duration": d, "updated": int(_cfg.get_value(k, "updated", 0)),
			"finished": bool(_cfg.get_value(k, "finished", false)), "progress": p / d if d > 0.0 else 0.0}


func _prune() -> void:
	var sections := _cfg.get_sections()
	if sections.size() <= MAX_ENTRIES:
		return
	var by_age := Array(sections)
	by_age.sort_custom(func(a: String, b: String) -> bool:
		return int(_cfg.get_value(a, "updated", 0)) < int(_cfg.get_value(b, "updated", 0)))
	for i in sections.size() - MAX_ENTRIES:
		_cfg.erase_section(by_age[i])


static func _tracked(path: String) -> bool:
	return not (path.begins_with("browser://") or path.begins_with("window://") or path.begins_with("pcwindow://"))


static func _clock(t: float) -> String:
	var s := int(t)
	return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]


## Records the current position and writes the file now (the sleep timer, before the headset goes quiet).
func save_now() -> void:
	_record()
	save_if_dirty()


func save_if_dirty() -> void:
	if not _dirty or read_only:
		return
	var err := _cfg.save(PATH)
	if err != OK:
		push_warning("Can't write %s: %s" % [PATH, error_string(err)])
	_dirty = false


func _exit_tree() -> void:
	_record()
	save_if_dirty()
