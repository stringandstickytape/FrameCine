extends Node

## Up next (ideas #34): when a file ends and the queue goes on by itself (continuous play or repeat, #78), a card under
## the screen counts down ("Up next: <name>", "Playing in 8 s") and then the next file opens. Play now: the N key or
## the next button as usual, or play_now(). Cancel: cancel(), pressing play (the film starts over, as before), a seek,
## or opening something else. A --dir run (tours, kiosk) and the picture slideshow go on at once as before.
##
##   enabled, seconds               [up_next] enabled (default on), seconds (3..30, default 10)
##   active, remaining, next_path
##   begin(path, go) -> bool        PlayQueue.on_ended() asks; true when the countdown started (go opens the file)
##   play_now(), cancel()
##   following, follow(path, seconds_left, go, on_cancel), set_remaining(s)   gapless (#44): counts down to the end
##   signal changed(active, remaining, next_title)

const ScreenCard := preload("res://scripts/play/screen_card.gd")

signal changed(active: bool, remaining: float, next_title: String)

var main: Node3D
var enabled := true
var seconds := 10.0
var active := false
var remaining := 0.0
var next_path := ""
var card: ScreenCard
## Gapless (scripts/play/gapless.gd, #44): the card counts down to the end of the film, which then runs straight on
## into the next file; gapless sets `remaining`. Seeks and play do not cancel it; cancel() does (the film then stops at
## its end), and play_now() goes on at once.
var following := false
var _go: Callable
var _on_cancel: Callable
var _declined_path := ""


func _ready() -> void:
	enabled = bool(main.settings.get_value("up_next", "enabled", true))
	seconds = clampf(float(main.settings.get_value("up_next", "seconds", 10.0)), 3.0, 30.0)
	card = ScreenCard.new()
	card.name = "UpNextCard"
	card.main = main
	add_child(card)
	main.file_opened.connect(_on_file_opened)
	main.player.seeked.connect(func(_t: float) -> void:
		if not following:
			cancel())
	main.player.playing_changed.connect(func(playing: bool) -> void:
		if playing and not following:
			cancel())


func set_enabled(on: bool) -> void:
	enabled = on
	main.settings.set_value("up_next", "enabled", on)
	if not on:
		cancel()


func set_seconds(s: float) -> void:
	seconds = clampf(s, 3.0, 30.0)
	main.settings.set_value("up_next", "seconds", seconds)


## Starts the countdown to `path`; `go` opens it at the end. False when the queue should go on at once instead.
func begin(path: String, go: Callable) -> bool:
	if _declined_path != "" and _declined_path == main.current_path:
		return true  # The gapless countdown was cancelled: stay at the end.
	if not enabled or main.auto_advance or path == "":
		return false
	var src: Object = main.player.source
	# A slideshow moves on by itself; music goes straight to the next track (ideas #22, #64).
	if src != null and src.get_kind() in ["image", "music"]:
		return false
	active = true
	remaining = seconds
	next_path = path
	_go = go
	card.show_card("Up next: " + title_of(path), _line())
	changed.emit(true, remaining, title_of(path))
	return true


## Gapless (#44): shows the card for `path`, `seconds_left` before the film's end. `go`: play now; `on_cancel`: the
## user cancelled (the film then stops at its end). False when up next is off (gapless then goes on without a card).
func follow(path: String, seconds_left: float, go: Callable, on_cancel: Callable) -> bool:
	if not enabled or path == "":
		return false
	active = true
	following = true
	remaining = seconds_left
	next_path = path
	_go = go
	_on_cancel = on_cancel
	card.show_card("Up next: " + title_of(path), _line())
	changed.emit(true, remaining, title_of(path))
	return true


## Gapless (#44): the time left to the film's end.
func set_remaining(seconds_left: float) -> void:
	if not following:
		return
	remaining = maxf(seconds_left, 0.0)
	card.set_line(_line())
	changed.emit(true, remaining, title_of(next_path))


static func title_of(path: String) -> String:
	var name := path.get_file().get_basename() if not path.begins_with("stub://") else path.trim_prefix("stub://")
	name = name.replace(".", " ").replace("_", " ").strip_edges()
	return name.left(60)


func play_now() -> void:
	if not active:
		return
	var go := _go
	_finish()
	if go.is_valid():
		go.call()


func cancel() -> void:
	if not active:
		return
	var cb := _on_cancel if following else Callable()
	if following:
		_declined_path = main.current_path
	_finish()
	if cb.is_valid():
		cb.call()


func _on_file_opened(_p: String) -> void:
	_declined_path = ""
	if active:
		_finish()


func _finish() -> void:
	active = false
	following = false
	_go = Callable()
	_on_cancel = Callable()
	card.hide_card()
	changed.emit(false, 0.0, "")


func _line() -> String:
	return "Playing in %d s" % ceili(remaining)


func _process(delta: float) -> void:
	if not active or following:
		return
	remaining -= delta
	if remaining <= 0.0:
		play_now()
		return
	card.set_line(_line())
	changed.emit(true, remaining, title_of(next_path))


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if not active or key == null or not key.pressed or key.echo or main.menu_shown:
		return
	if key.keycode == KEY_ESCAPE:
		cancel()
		get_viewport().set_input_as_handled()
