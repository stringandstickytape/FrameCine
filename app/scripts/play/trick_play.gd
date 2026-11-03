extends Node

## Trick play (ideas #46): hold the thumbstick right to scan forward at 4x, and after STEP_SECONDS more at 8x, with
## pictures shown all the way; let go and playback goes on with sound from the frame on screen. A tap still skips
## 10 s as before (main._stick_seek): the hold takes over from main's repeat seeks after HOLD_SECONDS.
##
## The engine does the work (fork c318810fdd): MediaSource.trick_play(speed, from) with a speed of 2 to 64 reads and
## shows keyframes only (at most one per 0.25 s of wall time), without audio, and HWVideoTexture runs its clock at that
## speed; trick_play(0, position) goes back to normal playback with audio. Sources without it (engine builds before
## the fork commit, the lab, still pictures, music) keep the repeat seeks. Forward only: the engine has no reverse.
##
##   enabled, set_enabled(on)          [trick_play] enabled (default on): the stick hold
##   speed                             the trick speed now, 0 for normal playback
##   available() -> bool               the open file can do it
##   start(speed) -> bool              2 to 64; for the pane's transport buttons (hold to scan)
##   stop()                            back to normal playback from the frame on screen
##   on_stick(hand, stick, delta) -> bool   main calls this per hand per frame; true: trick play has the stick
##   signal changed(speed)

signal changed(speed: float)

const PUSH := 0.75
const HOLD_SECONDS := 0.35
const STEP_SECONDS := 2.0
const FIRST_SPEED := 4.0
const SECOND_SPEED := 8.0

var main: Node3D
var enabled := true
var speed := 0.0
var _hand: Variant = null
var _held := 0.0


func _ready() -> void:
	enabled = bool(main.settings.get_value("trick_play", "enabled", true))
	main.file_opened.connect(func(_p: String) -> void: _reset())
	main.player.seeked.connect(_on_seeked)


func set_enabled(on: bool) -> void:
	enabled = on
	main.settings.set_value("trick_play", "enabled", null if on else false)
	if not on and speed > 0.0:
		stop()


func available() -> bool:
	var src: Object = main.player.source
	return src != null and src.has_method("has_trick_play") and src.has_trick_play()


func start(p_speed: float) -> bool:
	if not available():
		return false
	var s := clampf(p_speed, 2.0, 64.0)
	if is_equal_approx(s, speed):
		return true
	var player: Node = main.player
	if not player.is_playing():
		player.play()
	if int(player.source.trick_play(s, player.get_position())) < 0:
		return false
	speed = s
	changed.emit(speed)
	return true


func stop() -> void:
	_hand = null
	_held = 0.0
	if speed <= 0.0:
		return
	speed = 0.0
	var src: Object = main.player.source
	if src != null and src.has_method("trick_play"):
		_normal_from(src.get_position())
	changed.emit(speed)


func on_stick(hand: Variant, stick: Vector2, delta: float) -> bool:
	if _hand != null and _hand != hand:
		return false
	if stick.x < PUSH:
		if _hand == hand:
			var was := speed > 0.0
			stop()
			return was
		return false
	if not enabled or not available():
		return false
	_hand = hand
	_held += minf(delta, 0.1)  # A long frame (a hitch) must not turn a tap into a hold.
	if _held < HOLD_SECONDS:
		return false  # main's first 10 s skip happens meanwhile.
	start(SECOND_SPEED if _held >= HOLD_SECONDS + STEP_SECONDS else FIRST_SPEED)
	return speed > 0.0


func _on_seeked(_t: float) -> void:
	# A seek from elsewhere (the pane's bar, a chapter) ends trick play: normal playback from the seek's target. (The
	# engine alone would scan on from there.)
	if speed > 0.0:
		speed = 0.0
		_hand = null
		_held = 0.0
		var src: Object = main.player.source
		if src != null and src.has_method("trick_play"):
			_normal_from(main.player.get_position())
		changed.emit(speed)


## Normal playback with audio from t. The engine's audio stream reported itself finished during trick play, so the
## AudioStreamPlayer has stopped: start it again at t (the stream does not seek again within 50 ms of its own place).
func _normal_from(t: float) -> void:
	var player: Node = main.player
	player.source.trick_play(0.0, t)
	var a: AudioStreamPlayer = player.audio
	if a.stream != null:
		if not a.playing:
			a.play(t)
		a.stream_paused = not player.is_playing()


func _reset() -> void:
	if speed > 0.0:
		speed = 0.0
		changed.emit(speed)
	_hand = null
	_held = 0.0
