extends Node

## Catch-up replay (ideas #11): one action replays the last SECONDS with subtitles forced on, then puts the subtitle
## state back as it was once playback is past the point where the replay started.
##
##   replay()     start (or, during a replay, go back another SECONDS, keeping the original end)
##   cancel()     stop forcing subtitles now, stay where playback is
##   active       a replay is running; end_position is where it ends
##   signals started(from, to), finished
## The replay ends, and the subtitle state is restored, when playback reaches end_position, when someone seeks
## elsewhere, or when another file opens. If the user changes the subtitles during the replay, their choice stays.
## Without subtitle tracks it still replays, just without text. Paused playback starts playing.
## Controls: Backspace on a keyboard (menu hidden); the left d-pad down with the opt-in action map
## (xr/openxr_action_map_dpad.tres).

signal started(from: float, to: float)
signal finished

const SECONDS := 10.0

var main: Node3D
var active := false
var end_position := 0.0
var _saved := {}
var _own_change := false
var _restore := true
## The position has been seen back before end_position since the replay's seek. Right after a seek the source can
## still report the old position for a few frames (the decoder settles from the keyframe), which would end the replay
## at once.
var _armed := false


func _ready() -> void:
	main.player.seeked.connect(_on_seeked)
	for hand: XRController3D in [main.left_hand, main.right_hand]:
		hand.button_pressed.connect(func(action: String) -> void:
			if action == "replay":
				replay())
	main.file_opened.connect(func(_p: String) -> void:
		if active:
			_finish(false))
	main.features.subtitles.track_changed.connect(func(_i: int, _on: bool) -> void:
		if active and not _own_change:
			# The user chose something during the replay: keep it.
			_restore = false)


func replay() -> void:
	var player: Node = main.player
	if not player.can_seek():
		return
	var pos: float = player.get_position()
	if active:
		_seek(maxf(pos - SECONDS, 0.0))
		return
	var subs: Node = main.features.subtitles
	_saved = subs.get_state()
	_restore = true
	if not subs.enabled or subs.track < 0:
		var t: int = subs.pick_track()
		if t >= 0:
			_own_change = true
			subs.set_state({"enabled": true, "track": t})
			_own_change = false
	active = true
	_armed = false
	end_position = pos
	var from := maxf(pos - SECONDS, 0.0)
	_seek(from)
	if not player.is_playing():
		player.play()
	started.emit(from, end_position)
	print("Catch-up: replaying %.0f s with subtitles" % (end_position - from))


func cancel() -> void:
	if active:
		_finish(true)


func _seek(t: float) -> void:
	_own_change = true
	main.player.seek(t)
	_own_change = false


func _on_seeked(_t: float) -> void:
	if active and not _own_change:
		_finish(true)


func _process(_delta: float) -> void:
	if not active or not main.player.has_source() or main.player.source.is_settling():
		return
	var t: float = main.player.get_position()
	if not _armed:
		_armed = t < end_position - 0.25
	elif t >= end_position:
		_finish(true)


func _finish(restore_subtitles: bool) -> void:
	active = false
	if restore_subtitles and _restore:
		_own_change = true
		main.features.subtitles.set_state(_saved)
		_own_change = false
	finished.emit()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or main.menu_shown or main.window_pointer.is_active():
		return
	if key.keycode == KEY_BACKSPACE:
		replay()
