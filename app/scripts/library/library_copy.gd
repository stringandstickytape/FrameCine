extends Node

## Copies a file from a saved SMB host into the Library (docs/library.md): the headset has no SMB mount and no smbclient,
## and the login stays in the app, so an assistant names the file and the app reads it. One file at a time, on a worker
## thread, as a .part file renamed when whole; a failed or cancelled copy leaves nothing behind. Keeps
## AssistantFetch.KEEP_FREE of the disk free.
##
## The engine's MediaBrowser reads any size in pieces (open_read, fork branch frame/library-copy). An older engine has
## only read_file(), up to 64 MiB in memory: NFOs and pictures, not videos; a bigger file is refused with that reason.
##
##   LibraryCopy.ensure(tree) -> node
##   start(from, to) -> {ok, result | error, refused};  cancel();  status() -> {...} or null (in /state)
##   signal event(data)  {state: started | progress | done | failed | cancelled, name, ...}: the `library_copy` event
## The card shows the progress, with Cancel.

signal event(data: Dictionary)

const AssistantFetch := preload("res://scripts/assistant/assistant_fetch.gd")
const LibraryIndex := preload("res://scripts/library/library_index.gd")
const NetworkHosts := preload("res://scripts/net/network_hosts.gd")
const VideoSourceFactory := preload("res://scripts/video/video_source_factory.gd")

const NODE_NAME := "LibraryCopy"
const CARD_ID := "library_copy"
const PROGRESS_EVERY := 1.0
const CHUNK := 4194304
const SPACE_CHECK_EVERY := 268435456
## What else may sit beside the videos.
const OTHER_FILES := ["nfo", "jpg", "jpeg", "png", "webp", "srt", "ass", "ssa", "vtt", "sub", "idx"]
const MAX_DEPTH := 4

## Tests: () -> a reader with open_read, read_next, close_read, get_last_error.
static var reader_override: Callable

var _thread: Thread
var _mutex := Mutex.new()
## The copy now (shared with the thread under _mutex): from, to, name, path, part, state, bytes, total, reason, cancel.
var _job := {}
var _last_progress_msec := 0
var _last_bytes := 0


static func ensure(tree: SceneTree) -> Node:
	var n := tree.root.get_node_or_null(NODE_NAME)
	if n != null:
		return n
	if tree.root.has_meta(NODE_NAME) and is_instance_valid(tree.root.get_meta(NODE_NAME)):
		return tree.root.get_meta(NODE_NAME)
	n = (load("res://scripts/library/library_copy.gd") as GDScript).new()
	n.name = NODE_NAME
	tree.root.set_meta(NODE_NAME, n)
	tree.root.add_child.call_deferred(n)
	return n


## Why `to` may not be written, or "". It must name a file under TV Shows or Movies of the Library, by the layout's plain
## folder names: nothing can climb out of the Library, land on a hidden file, or be a program.
static func to_refusal(to: String) -> String:
	if to == "" or to.begins_with("/") or to.begins_with("~") or to.contains("\\") or to.contains("://"):
		return "to: a path inside the Library, e.g. TV Shows/Show (2001)/Season 01/Show - S01E01 - Title.mkv"
	var parts := to.split("/")
	if not parts[0] in [LibraryIndex.TV_SHOWS, LibraryIndex.MOVIES]:
		return "to: starts with %s/ or %s/" % [LibraryIndex.TV_SHOWS, LibraryIndex.MOVIES]
	if parts.size() < 2 or parts.size() > MAX_DEPTH:
		return "to: at most %d levels: TV Shows/<Show (Year)>/Season 01/<file>" % MAX_DEPTH
	for part in parts:
		if part != AssistantFetch.clean_name(part) or part == "":
			return "to: %s is not a plain name (no leading dots, no : * ? \" < > |)" % part
	var ext := to.get_extension().to_lower()
	if not (VideoSourceFactory.is_video_file(to) or ext in OTHER_FILES):
		return "to: a video, or one of %s" % ", ".join(OTHER_FILES)
	return ""


func busy() -> bool:
	return not _job.is_empty()


## `open_refusal` of the commands has checked `from` is on a saved host: this checks it is a file there.
func start(from: String, to: String) -> Dictionary:
	if busy():
		return {"ok": false, "refused": true, "error": "a copy is already running (%s): one at a time; " % _job["name"]
				+ "the library_copy event says when it ends, copy_cancel stops it"}
	if not NetworkHosts.is_smb(from) or from.contains("/../") or from.ends_with("/.."):
		return {"ok": false, "refused": true, "error": "from: an smb:// file on a host saved in the player"}
	var why := to_refusal(to)
	if why != "":
		return {"ok": false, "refused": true, "error": why}
	var path := LibraryIndex.root().path_join(to)
	if FileAccess.file_exists(path):
		return {"ok": false, "refused": true, "error": "%s is already in the Library" % to}
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
		return {"ok": false, "error": "could not make the folder %s" % path.get_base_dir()}
	var shown := path.get_file()
	_job = {"from": from, "to": to, "name": shown, "path": path, "part": path + ".part", "state": "reading", "bytes": 0,
			"total": -1, "reason": "", "cancel": false}
	_last_progress_msec = Time.get_ticks_msec()
	_last_bytes = 0
	_thread = Thread.new()
	_thread.start(_work)
	event.emit({"state": "started", "name": shown, "from": from, "to": to})
	_card("Copying %s ..." % shown, true)
	return {"ok": true, "result": {"state": "started", "name": shown, "path": path, "events": "library_copy: progress "
			+ "at most once a second, then done (path), failed (reason) or cancelled"}}


func cancel() -> Dictionary:
	if not busy():
		return {"ok": false, "error": "no copy is running"}
	_mutex.lock()
	_job["cancel"] = true
	var n := str(_job["name"])
	_mutex.unlock()
	return {"ok": true, "result": {"cancelling": n}}


## The copy in progress for /state, or null.
func status() -> Variant:
	if not busy():
		return null
	_mutex.lock()
	var s := {"name": _job["name"], "to": _job["to"], "state": _job["state"], "bytes": _job["bytes"],
			"total": _job["total"]}
	_mutex.unlock()
	return s


func _process(_delta: float) -> void:
	if not busy():
		return
	_mutex.lock()
	var state := str(_job["state"])
	var bytes := int(_job["bytes"])
	var total := int(_job["total"])
	var n := str(_job["name"])
	var part := str(_job["part"])
	_mutex.unlock()
	if state in ["done", "failed", "cancelled"]:
		_finish()
		return
	if _thread != null and not _thread.is_alive():
		_mutex.lock()
		_job["state"] = "failed"
		_job["reason"] = "the copy stopped unexpectedly"
		_mutex.unlock()
		DirAccess.remove_absolute(part)
		_finish()
		return
	var now := Time.get_ticks_msec()
	if now - _last_progress_msec >= PROGRESS_EVERY * 1000.0:
		var rate := (bytes - _last_bytes) * 1000.0 / maxf(now - _last_progress_msec, 1.0)
		_last_progress_msec = now
		_last_bytes = bytes
		event.emit({"state": "progress", "name": n, "bytes": bytes, "total": total, "rate": roundi(rate)})
		_card_text("Copying %s, %s%s" % [n, AssistantFetch.gb(bytes), " of " + AssistantFetch.gb(total)
				if total > 0 else ""])


func _finish() -> void:
	_thread.wait_to_finish()
	_thread = null
	var job := _job.duplicate()
	_job = {}
	var n := str(job["name"])
	match str(job["state"]):
		"done":
			event.emit({"state": "done", "name": n, "path": job["path"], "bytes": job["bytes"]})
			_card("%s is in the Library (%s)." % [n, AssistantFetch.gb(int(job["bytes"]))], false, 8.0)
			var main := get_tree().current_scene if is_inside_tree() else null
			if main != null and main.get("ui") != null and main.ui.get("ui") != null:
				main.ui.ui.files.refresh_library()
		"failed":
			event.emit({"state": "failed", "name": n, "reason": job["reason"]})
			_card("Copying %s failed: %s" % [n, job["reason"]], false, 12.0)
		_:
			event.emit({"state": "cancelled", "name": n})
			_card("Copy of %s cancelled." % n, false, 5.0)


func _card_node() -> Node:
	var main := get_tree().current_scene if is_inside_tree() else null
	if main == null or main.get("ui") == null:
		return null
	var card: Node = main.ui.get("card")
	return card if card != null and card.has_method("show_card") else null


func _card(text: String, with_cancel: bool, seconds := 0.0) -> void:
	var card := _card_node()
	if card == null:
		return
	var data := {"id": CARD_ID, "title": "Library", "text": text, "seconds": seconds}
	if with_cancel:
		data["actions"] = [{"id": "cancel", "label": "Cancel copy"}]
	card.show_card(data)
	if with_cancel and card.has_signal("dismissed") and not card.dismissed.is_connected(_on_card_dismissed):
		card.dismissed.connect(_on_card_dismissed)


func _card_text(text: String) -> void:
	var card := _card_node()
	if card != null and card.has_method("set_card_text"):
		card.set_card_text(CARD_ID, text)


func _on_card_dismissed(id: String, how: String) -> void:
	if id == CARD_ID and how == "cancel" and busy():
		cancel()


# --- The worker thread -----------------------------------------------------------------------------------------------

## What read_file() can do, for an engine without open_read: the whole file in memory.
class WholeFile:
	extends RefCounted
	var browser: Object
	var bytes := PackedByteArray()
	var at := 0

	func open_read(path: String) -> int:
		bytes = browser.call("read_file", path)
		at = 0
		return bytes.size() if str(browser.call("get_last_error")) == "" else -1

	func read_next(max_bytes: int) -> PackedByteArray:
		var piece := bytes.slice(at, at + max_bytes)
		at += piece.size()
		return piece

	func close_read() -> void:
		bytes = PackedByteArray()

	func get_last_error() -> String:
		return str(browser.call("get_last_error"))


func _job_get(key: String) -> Variant:
	_mutex.lock()
	var v: Variant = _job.get(key)
	_mutex.unlock()
	return v


func _set_job(values: Dictionary) -> void:
	_mutex.lock()
	_job.merge(values, true)
	_mutex.unlock()


func _fail(reason: String) -> void:
	DirAccess.remove_absolute(str(_job_get("part")))
	_set_job({"state": "cancelled" if bool(_job_get("cancel")) else "failed", "reason": reason})


static func _reader() -> Object:
	if reader_override.is_valid():
		return reader_override.call()
	if not ClassDB.class_exists("MediaBrowser"):
		return null
	var browser: Object = ClassDB.instantiate("MediaBrowser")
	if browser.has_method("open_read"):
		return browser
	var whole := WholeFile.new()
	whole.browser = browser
	return whole


func _work() -> void:
	var from := str(_job_get("from"))
	var reader: Object = _reader()
	if reader == null:
		_fail("this build can't read SMB shares")
		return
	var engine_reads_all: bool = reader is not WholeFile
	if reader.has_method("set_timeout"):
		reader.call("set_timeout", 30.0)
	if reader is WholeFile:
		NetworkHosts.apply_credentials((reader as WholeFile).browser, from)
	else:
		NetworkHosts.apply_credentials(reader, from)
	var total: int = reader.call("open_read", from)
	if total < 0:
		var why := str(reader.call("get_last_error"))
		_fail(why if engine_reads_all else why + " This engine copies files of up to 64 MiB; a newer one copies any size.")
		return
	var dir := str(_job_get("path")).get_base_dir()
	var left := AssistantFetch.space_left(dir)
	if left >= 0 and left - total < AssistantFetch.KEEP_FREE:
		reader.call("close_read")
		_fail("the file is %s; the headset has %s free and keeps %s free" % [AssistantFetch.gb(total),
				AssistantFetch.gb(left), AssistantFetch.gb(AssistantFetch.KEEP_FREE)])
		return
	var part := str(_job_get("part"))
	var f := FileAccess.open(part, FileAccess.WRITE)
	if f == null:
		reader.call("close_read")
		_fail("could not write %s" % part)
		return
	_set_job({"total": total, "state": "body"})
	var bytes := 0
	var why := ""
	var next_check := SPACE_CHECK_EVERY
	while bytes < total:
		if bool(_job_get("cancel")):
			why = "cancelled"
			break
		var piece: PackedByteArray = reader.call("read_next", CHUNK)
		if piece.is_empty():
			why = str(reader.call("get_last_error"))
			why = why if why != "" else "the file ended at %s of %s" % [AssistantFetch.gb(bytes), AssistantFetch.gb(total)]
			break
		f.store_buffer(piece)
		if f.get_error() != OK:
			why = "writing failed: %s" % error_string(f.get_error())
			break
		bytes += piece.size()
		_set_job({"bytes": bytes})
		if bytes >= next_check:
			next_check += SPACE_CHECK_EVERY
			left = AssistantFetch.space_left(dir)
			if left >= 0 and left < AssistantFetch.KEEP_FREE:
				why = "the disk is down to %s free (it keeps %s)" % [AssistantFetch.gb(left),
						AssistantFetch.gb(AssistantFetch.KEEP_FREE)]
				break
	f.close()
	reader.call("close_read")
	if why != "":
		_fail(why)
		return
	if DirAccess.rename_absolute(part, str(_job_get("path"))) != OK:
		_fail("could not rename the finished file")
		return
	_set_job({"bytes": bytes, "state": "done"})


func _exit_tree() -> void:
	if _thread != null:
		_mutex.lock()
		_job["cancel"] = true
		_mutex.unlock()
		_thread.wait_to_finish()
		_thread = null
