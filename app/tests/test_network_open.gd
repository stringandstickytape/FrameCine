extends SceneTree

## Network paths without a server: listing an unreachable host and opening an smb:// file on it. With the engine's
## MediaBrowser / MediaSource (our player build) the open runs on a worker thread: `connecting` first, the frame loop
## keeps running, then `opened` with the test-pattern stand-in and the engine's reason. On other builds the simulated
## browser answers and the open falls back at once. Run:
##   godot --headless --xr-mode off --path app --script res://tests/test_network_open.gd

const PlaybackController := preload("res://scripts/playback_controller.gd")
const DirectoryLister := preload("res://scripts/net/directory_lister.gd")
const HWVideoSource := preload("res://scripts/video/hw_video_source.gd")
const HOST := "offline.invalid"
const FILE := "smb://offline.invalid/Movies/film.mkv"
## A non-routable address: the engine waits for its connect timeout (seconds); the frame loop must keep running.
const SLOW_FILE := "smb://10.255.255.1/Movies/film.mkv"
const TIMEOUT_MSEC := 60000

var _failures := 0
var _pc: Node
var _start := 0
var _frames_while_connecting := 0
var _done := false
var _files: Array[String] = []
var _index := 0


func _initialize() -> void:
	print("MediaBrowser: %s, async open: %s" % [DirectoryLister.has_media_browser(), HWVideoSource.opens_async(FILE)])
	var t := Time.get_ticks_msec()
	var listed := DirectoryLister.list("smb://" + HOST)
	print("list smb://%s in %d ms: error '%s', %d entries" % [HOST, Time.get_ticks_msec() - t, listed["error"],
			listed["entries"].size()])
	_check("listing an unreachable host gives an error", listed["error"] != "" and listed["entries"].is_empty())
	DirectoryLister.forget_host(HOST, true)
	_files = [FILE]
	if HWVideoSource.opens_async(FILE):
		_files.append(SLOW_FILE)
	_pc = PlaybackController.new()
	root.add_child.call_deferred(_pc)
	_open_next.call_deferred()


func _open_next() -> void:
	if not _pc.opened.is_connected(_on_opened):
		_pc.opened.connect(_on_opened)
	_frames_while_connecting = 0
	_start = Time.get_ticks_msec()
	var file: String = _files[_index]
	_pc.open(file)  # Without the engine's MediaSource this opens (and emits `opened`) at once.
	if HWVideoSource.opens_async(file):
		_check("connecting while the worker opens", _pc.connecting_path == file and _pc.source == null)


func _process(_delta: float) -> bool:
	if _start == 0:
		return false
	if _done:
		return true
	if _pc.connecting_path != "":
		_frames_while_connecting += 1
	if Time.get_ticks_msec() - _start > TIMEOUT_MSEC:
		_check("opened within %d s" % (TIMEOUT_MSEC / 1000), false)
		_finish()
	return _done


func _on_opened() -> void:
	var src: Object = _pc.source
	var file: String = _files[_index]
	print("%s opened after %d ms (%d frames ran while connecting): %s source, reason: %s" % [file,
			Time.get_ticks_msec() - _start, _frames_while_connecting, src.get_kind(), src.last_error])
	_check("%s falls back to the stand-in" % file, src.get_kind() != "hw")
	_check("%s with a reason" % file, str(src.last_error) != "")
	_check("%s: not connecting any more" % file, _pc.connecting_path == "")
	if HWVideoSource.opens_async(file):
		_check("%s: the frame loop ran while connecting" % file, _frames_while_connecting > 0)
	_index += 1
	if _index < _files.size():
		_open_next.call_deferred()
	else:
		_finish()


func _finish() -> void:
	_done = true
	_pc.close()
	print("test_network_open: %s" % ("all passed" if _failures == 0 else "%d FAILED" % _failures))
	quit(_failures)


func _check(what: String, ok: bool) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL " + what)
