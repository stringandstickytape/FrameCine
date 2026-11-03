extends Node

## Playback speed with the pitch kept (ideas #69): 0.5x to 2x. The engine time-stretches the audio
## (MediaSource.playback_speed, a WSOLA stretch in the mixer) and, as the audio is the master clock, the video follows;
## without audio the frame clock runs faster or slower (HWVideoTexture.playback_speed). The test patterns follow too.
## The end time (#36) and the battery forecast (#2) count in real time at this speed.
##
##   speed                    in effect; kept from file to file for the session, back to 1 at the next start
##   STEPS                    the choices for the pane and the keys
##   set_speed(s), faster(), slower(), reset()
##   signal changed(speed)
## Desktop keys (menu hidden): 9 slower, 0 faster.
## Not for a captured window (the page plays on its own clock). The hardware decoder must decode faster at > 1x:
## 2x on an 8K file may be beyond it.

signal changed(speed: float)

const STEPS: Array[float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

var main: Node3D
var speed := 1.0


func _ready() -> void:
	main.file_opened.connect(func(_p: String) -> void: _apply())


func set_speed(s: float) -> void:
	speed = clampf(snappedf(s, 0.05), STEPS[0], STEPS[-1])
	_apply()


func faster() -> void:
	for s in STEPS:
		if s > speed + 0.01:
			set_speed(s)
			return


func slower() -> void:
	for i in range(STEPS.size() - 1, -1, -1):
		if STEPS[i] < speed - 0.01:
			set_speed(STEPS[i])
			return


func reset() -> void:
	set_speed(1.0)


## "1.5x" when not 1, else "".
func text() -> String:
	return "" if is_equal_approx(speed, 1.0) else ("%.2fx" % speed).replace("0x", "x").replace(".0x", "x")


func _apply() -> void:
	main.player.speed = speed
	if main.player.has_source() and main.player.source.get_kind() != "window":
		main.player.source.set_playback_speed(speed)
	changed.emit(speed)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or main.menu_shown or main.window_pointer.is_active():
		return
	match key.keycode:
		KEY_9:
			slower()
		KEY_0:
			faster()
		_:
			return
	print("Speed %.2fx" % speed)
