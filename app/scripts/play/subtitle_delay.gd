extends Node

## Subtitle delay per track (ideas #61): shifts the selected subtitle track's timing, remembered with the file and the
## track, so a badly timed track stays fixed next time. Positive: the lines come later.
##
##   delay                 seconds in effect for the selected track (also Subtitles.delay)
##   set_delay(s), nudge(step), reset()
##   signal changed(delay)
## A negative delay needs lines before the demuxer would read them (about 1 s ahead): the source is told to read the
## video that much further ahead (MediaSource.subtitle_read_ahead, up to about 20 s at 24 fps).
## Desktop keys (menu hidden): ; and ' move it by STEP.
## Settings: [subtitle_delay_files] <file key>_<track index> = seconds.

const FileKey := preload("res://scripts/play/file_key.gd")

signal changed(delay: float)

const MAX := 30.0
const STEP := 0.1

var main: Node3D
var delay := 0.0
var _file := ""


func _ready() -> void:
	main.file_opened.connect(func(path: String) -> void:
		_file = FileKey.key(path) if path != "" else ""
		_load())
	main.features.subtitles.track_changed.connect(func(_i: int, _on: bool) -> void: _load())


func _key() -> String:
	var track: int = main.features.subtitles.track
	return "%s_%d" % [_file, track] if _file != "" and track >= 0 else ""


func _load() -> void:
	var k := _key()
	delay = clampf(float(main.settings.get_value("subtitle_delay_files", k, 0.0)), -MAX, MAX) if k != "" else 0.0
	_apply()


func set_delay(s: float) -> void:
	delay = clampf(snappedf(s, 0.01), -MAX, MAX)
	var k := _key()
	if k != "":
		main.settings.set_value("subtitle_delay_files", k, delay if not is_zero_approx(delay) else null)
	_apply()


func nudge(step: float) -> void:
	set_delay(delay + step)


func reset() -> void:
	set_delay(0.0)


func _apply() -> void:
	main.features.subtitles.delay = delay
	if main.player.has_source():
		main.player.source.set_subtitle_read_ahead(maxf(-delay, 0.0))
	changed.emit(delay)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or main.menu_shown or main.window_pointer.is_active():
		return
	match key.keycode:
		KEY_SEMICOLON:
			nudge(-STEP)
		KEY_APOSTROPHE:
			nudge(STEP)
		_:
			return
	print("Subtitle delay %+.1f s" % delay)
