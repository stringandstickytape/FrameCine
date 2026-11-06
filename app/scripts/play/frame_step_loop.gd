extends Node

## Frame step and A-B loop (ideas #80).
##
## Frame step: pauses, then moves one frame back or forward. The engine has no step call, so it is a seek of one
## frame's duration (1 / fps from the video info, 24 when unknown). MediaSource seeks decode from the keyframe up to
## the target, so the step is exact but can take a moment on long GOPs.
##   step(frames)          -1 back, +1 forward (any count)
##
## A-B loop: the first mark sets A, the second sets B and starts looping (B before A swaps them), a third clears it.
## While it loops, reaching B goes back to A. Opening another file clears it; seeking outside A-B keeps it (playback
## comes back to the loop at B).
##   mark(), clear(), set_loop(a, b), active, a, b, text() ("loop 1:02:03-1:02:10" / "A 1:02:03" / "")
##   signals loop_changed(active, a, b)
## Desktop keys (menu hidden): comma / period step, slash marks.
## Settings: none.

signal loop_changed(active: bool, a: float, b: float)

## The shortest loop, seconds.
const MIN_LOOP := 0.5

var main: Node3D
var a := -1.0
var b := -1.0
var active := false
## A jump back to A was issued and the position hasn't been seen back inside the loop yet (the source reports the
## old position for a few frames while it settles).
var _jumping := false


func _ready() -> void:
	main.file_opened.connect(func(_p: String) -> void: clear())


func frame_duration() -> float:
	if not main.player.has_source():
		return 1.0 / 24.0
	var fps := float(main.player.source.get_video_info().get("fps", 0.0))
	return 1.0 / fps if fps > 1.0 else 1.0 / 24.0


func step(frames: int) -> void:
	var player: Node = main.player
	if not player.can_seek():
		return
	if player.is_playing():
		player.pause()
	player.seek(maxf(player.get_position() + frames * frame_duration(), 0.0))


func mark() -> void:
	var t: float = main.player.get_position()
	if active:
		clear()
	elif a < 0.0:
		a = t
		loop_changed.emit(false, a, -1.0)
	else:
		set_loop(a, t)


func set_loop(p_a: float, p_b: float) -> void:
	var lo := minf(p_a, p_b)
	var hi := maxf(p_a, p_b)
	if hi - lo < MIN_LOOP:
		hi = lo + MIN_LOOP
	a = lo
	b = hi
	active = true
	loop_changed.emit(true, a, b)


func clear() -> void:
	var was := active or a >= 0.0
	a = -1.0
	b = -1.0
	active = false
	if was:
		loop_changed.emit(false, -1.0, -1.0)


## "loop 0:01:02-0:01:10", "A 0:01:02" or "". English for the dev link and the header; localised: in the menus'
## language (the Picture tab, docs/i18n.md).
func text(localised := false) -> String:
	if active:
		return (TranslationServer.translate("loop %s-%s") if localised else "loop %s-%s") % [_clock(a), _clock(b)]
	if a >= 0.0:
		return "A %s" % _clock(a)
	return ""


func _process(_delta: float) -> void:
	if not active or not main.player.has_source() or main.player.source.is_settling():
		return
	var t: float = main.player.get_position()
	if _jumping:
		_jumping = t >= b
	elif main.player.is_playing() and t >= b:
		_jumping = true
		main.player.seek(a)


static func _clock(t: float) -> String:
	var s := int(t)
	return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or main.menu_shown or main.window_pointer.is_active():
		return
	match key.keycode:
		KEY_COMMA:
			step(-1)
		KEY_PERIOD:
			step(1)
		KEY_SLASH:
			if key.echo:
				return
			mark()
			print("A-B: %s" % (text() if text() != "" else "off"))
