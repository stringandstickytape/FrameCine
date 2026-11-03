extends Node

## Gapless playlist (ideas #44): when the queue goes on by itself (continuous play or a --dir run, #78), the next file
## opens LEAD_SECONDS before the current one ends, on a second decoder session behind it, and takes over at the last
## frame with no black and no wait. The up-next card (#34) counts down to the end meanwhile ("Up next: <name>",
## "Playing in 8 s"); cancelling it lets the film stop at its end, and "play now" goes on at once as before.
##
## The engine does the change (fork 347778e84c): the next MediaSource opens on a worker thread, then
## HWVideoSource.chain_next() opens its HWVideoTexture without playing and HWVideoTexture.set_next() chains it; it
## decodes and holds its first frame. At the end, the textures swap plane textures, the next one plays, and
## main.adopt_next() makes it the open file (PlaybackController.adopt(): the audio follows from its first frame).
## Seeking back before the window drops the prepared item (its decoder buffers too). Not for pictures, music, the lab,
## live streams, raw streams, repeat "one", a sleep timer at the end of the file, or engine builds without set_next;
## those end and go on as before.
##
##   enabled, set_enabled(on)          [queue] gapless (default off until the headset check: it opens a second hardware
##                                     decoder session at the end of every file; team lead, runbook E7)
##   state                             "idle", "opening", "ready" (the next item holds its first frame)
##   next_path                         the item being prepared, or ""
##   next_for() -> String              the item that would follow the open file now, or ""
##   cancel()                          drop it for this file: the film stops at its end
##   signal changed(state, next_path)

const HWVideoSource := preload("res://scripts/video/hw_video_source.gd")
const VideoSourceFactory := preload("res://scripts/video/video_source_factory.gd")

signal changed(state: String, next_path: String)

## Seconds before the end to open the next item (the engine needs well under 1 s; this covers slow shares).
const LEAD_SECONDS := 10.0
## Seeking back this much further than the lead drops the prepared item.
const DROP_MARGIN := 3.0
const POLL_SECONDS := 0.25

var main: Node3D
var enabled := true
var state := "idle"
var next_path := ""
var _since := 0.0
var _tasks: Array[int] = []
var _open_id := 0
var _declined := ""
var _source: Object = null


func _ready() -> void:
	enabled = bool(main.settings.get_value("queue", "gapless", false))
	main.file_opened.connect(_on_file_opened)


func set_enabled(on: bool) -> void:
	enabled = on
	main.settings.set_value("queue", "gapless", true if on else null)
	if not on:
		_drop()


## The item that follows the open file when the queue goes on by itself, if gapless can take it, else "".
func next_for() -> String:
	var queue: Node = main.features.queue
	if main.features.sleep.holds_auto_advance() or queue.repeat == "one":
		return ""
	if not (queue.continuous or main.auto_advance):
		return ""
	var crossfade: Node = main.features.get("crossfade")
	if crossfade != null and crossfade.video_seconds > 0.0:
		return ""  # Videos crossfade instead (scripts/play/crossfade.gd, #94).
	if main.playlist_index < 0 or main.playlist_index + 1 >= main.playlist.size():
		return ""
	var p: String = main.playlist[main.playlist_index + 1]
	return p if chainable(p) else ""


## A file gapless can open behind another: a container video file, local or on a share / server.
static func chainable(p: String) -> bool:
	if p == "" or p.begins_with("stub://") or p.begins_with("lab://") or p.begins_with("udp://"):
		return false
	if HWVideoSource.is_raw_stream(p) or VideoSourceFactory.is_image_file(p) or VideoSourceFactory.is_music_file(p):
		return false
	return VideoSourceFactory.is_video_file(p) or HWVideoSource.opens_async(p)


## Drops the prepared item for this file; the film stops at its end (through the up-next card when it shows, so a
## countdown does not start again at the end).
func cancel() -> void:
	var up_next: Node = main.features.up_next
	if up_next.following:
		up_next.cancel()  # Calls _cancelled() back.
	else:
		_cancelled()


func _cancelled() -> void:
	_declined = main.current_path
	_drop(false)


func _on_file_opened(_path: String) -> void:
	# A new file (the adopted one included) starts afresh; a prepared item for the old one is gone with it.
	_declined = ""
	_open_id += 1
	_source = null
	_set_state("idle", "")


func _process(delta: float) -> void:
	_since += delta
	if _since < POLL_SECONDS:
		return
	_since = 0.0
	var src: Object = main.player.source
	if src == null:
		return
	var left: float = main.player.get_duration() - main.player.get_position()
	if state != "idle":
		if src != _source or left > LEAD_SECONDS + DROP_MARGIN or not enabled:
			_drop()
			return
		var up_next: Node = main.features.up_next
		if up_next.following:
			up_next.set_remaining(left)
		return
	if not enabled or _declined == main.current_path or main.player.get_duration() <= 0.0:
		return
	if left > LEAD_SECONDS or left < 0.5 or not src.has_method("can_chain") or not src.can_chain():
		return
	var p := next_for()
	if p == "":
		return
	_start(src, p, left)


func _start(src: Object, p: String, left: float) -> void:
	_open_id += 1
	var id := _open_id
	_source = src
	_set_state("opening", p)
	main.features.up_next.follow(p, left, _play_now, _cancelled)
	_tasks.append(WorkerThreadPool.add_task(func() -> void:
		var result := HWVideoSource.open_media_blocking(p)
		_on_media.call_deferred(id, p, result), false, "gapless " + p))


func _on_media(id: int, p: String, result: Dictionary) -> void:
	for i in range(_tasks.size() - 1, -1, -1):
		if WorkerThreadPool.is_task_completed(_tasks[i]):
			WorkerThreadPool.wait_for_task_completion(_tasks[i])
			_tasks.remove_at(i)
	var src: Object = main.player.source
	if id != _open_id or src != _source or src == null:
		var m: Object = result.get("media")
		if m != null and m.has_method("close"):
			m.call("close")
		return
	if src.chain_next(p, result, main.player) != OK:
		print("Gapless: can't prepare %s: %s" % [p, src.last_error])
		_drop(false)
		return
	if not src.next_started.is_connected(_on_next_started):
		src.next_started.connect(_on_next_started)
	_set_state("ready", p)
	print("Gapless: %s ready behind %s" % [p.get_file(), main.current_path.get_file()])


func _on_next_started(nxt: Object) -> void:
	var p := next_path
	# Emitted inside the old texture's update(): adopt after it returns.
	main.adopt_next.call_deferred(p, nxt)


## Up next's "play now": drop the prepared item and open the next file at once, as before.
func _play_now() -> void:
	_drop(false)
	main.next_file()


## Drops a prepared item (and the card, unless the card is what cancelled).
func _drop(hide_card := true) -> void:
	_open_id += 1
	if _source != null and _source == main.player.source and _source.has_method("cancel_next"):
		_source.cancel_next()
	_source = null
	if hide_card:
		var up_next: Node = main.features.up_next
		if up_next.following:
			up_next._finish()
	_set_state("idle", "")


func _set_state(s: String, p: String) -> void:
	if s == state and p == next_path:
		return
	state = s
	next_path = p
	changed.emit(state, next_path)
