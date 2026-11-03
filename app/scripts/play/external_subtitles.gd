extends Node

## Subtitle files next to the video (ideas #50): when a file opens, the engine's MediaBrowser.find_subtitles() lists
## the subtitle files that go with it (named after the video, all of them in a folder with one video, a Subs folder
## next to it; local or on a share), and each is loaded into the MediaSource as one more subtitle track
## (add_external_subtitle). Both block (a folder listing, reading each file), so they run on a worker thread; the
## subtitle list is refreshed when they are done, and if subtitles are on without a user's choice for this file, the
## pick is made again (a file in the remembered language can win, #28).
##
##   enabled             [subtitles] find_files (default on)
##   loaded              [{path, index, language, forced, hearing_impaired}] for the open file
##   signal loaded_changed(loaded)
## Only for sources that can take subtitle files (MediaSource on an engine with add_external_subtitle). Opening
## another file meanwhile drops the late answer. At most MAX_FILES files.

const NetworkHosts := preload("res://scripts/net/network_hosts.gd")

signal loaded_changed(loaded: Array)

const MAX_FILES := 16

var main: Node3D
var enabled := true
var loaded: Array = []
var _id := 0
var _tasks: Array[int] = []


func _ready() -> void:
	enabled = bool(main.settings.get_value("subtitles", "find_files", true))
	main.file_opened.connect(_on_file_opened)


func set_enabled(on: bool) -> void:
	enabled = on
	main.settings.set_value("subtitles", "find_files", on)


static func available() -> bool:
	return ClassDB.class_has_method("MediaBrowser", "find_subtitles")


func _on_file_opened(path: String) -> void:
	_id += 1
	loaded = []
	var src: Object = main.player.source
	if not enabled or path == "" or src == null or not src.supports_external_subtitles() or not available():
		return
	var id := _id
	_tasks.append(WorkerThreadPool.add_task(func() -> void:
		var result := find_and_load(src, path)
		_on_done.call_deferred(id, result), false, "subtitle files for " + path.get_file()))


## Blocking (worker thread): finds the files and loads them into `src`. [{path, index, language, forced,
## hearing_impaired}] for the ones that loaded.
static func find_and_load(src: Object, path: String) -> Array:
	var browser: Object = ClassDB.instantiate("MediaBrowser")
	NetworkHosts.apply_credentials(browser, path)
	var out: Array = []
	var found: Array = browser.call("find_subtitles", path)
	for s: Dictionary in found.slice(0, MAX_FILES):
		var index: int = src.add_external_subtitle(str(s["path"]), str(s.get("language", "")), "")
		if index >= 0:
			out.append({"path": s["path"], "index": index, "language": s.get("language", ""),
					"forced": s.get("forced", false), "hearing_impaired": s.get("hearing_impaired", false)})
	return out


func _on_done(id: int, result: Array) -> void:
	for i in range(_tasks.size() - 1, -1, -1):
		if WorkerThreadPool.is_task_completed(_tasks[i]):
			WorkerThreadPool.wait_for_task_completion(_tasks[i])
			_tasks.remove_at(i)
	if id != _id:
		return
	loaded = result
	if not result.is_empty():
		print("Subtitle files: %d loaded (%s)" % [result.size(), ", ".join(result.map(func(e: Dictionary) -> String:
				return str(e["path"]).get_file()))])
		main.features.subtitles.refresh_tracks()
		main.features.languages.tracks_added()
	loaded_changed.emit(loaded)


func _exit_tree() -> void:
	for t in _tasks:
		WorkerThreadPool.wait_for_task_completion(t)
	_tasks.clear()
