extends SceneTree

## Tests for trick play (scripts/play/trick_play.gd, ideas #46) in the real main scene on the fork's
## MediaSource.trick_play: a tap does not start it, a hold scans at 4x then 8x with pictures shown, letting go plays on
## with the audio in step, a seek ends it, and the setting turns the hold off. Needs the fork and a renderer.
## The clip: trick10.avi from make-feature-media.sh (pcm10_h264_avi.py: High 10 I_PCM H.264, 160x96 at 10 fps, 120 s, every frame a
## keyframe, PCM audio with a beep each second); the desktop decodes 10-bit H.264 in software.
## Run: godot --xr-mode off --path app --script res://tests/test_trick_play.gd

var CLIP := OS.get_environment("HOME").path_join("media-tests/app-features/trick10.avi")
const HAND := "test hand"

var _failures := 0
var _checks := 0
var main: Node3D


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	await _frames(5)
	var tp: Node = main.features.trick
	_check("on by default, idle", tp.enabled and tp.speed == 0.0)
	_check("not for the stand-in source", not tp.available() and not tp.start(4.0))
	if not ClassDB.class_has_method("MediaSource", "trick_play") or not FileAccess.file_exists(CLIP) \
			or DisplayServer.get_name() == "headless":
		print("SKIP playback checks (needs the fork, the clip and a renderer)")
	else:
		await _playback(tp)
	print("test_trick_play: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _playback(tp: Node) -> void:
	main.set_environment("void")
	main.open_path(CLIP)
	await _until(func() -> bool: return main.player.source != null and main.player.get_position() > 2.0, 10.0)
	_check("the clip plays (%.2f s)" % main.player.get_position(), main.player.get_position() > 2.0)
	_check("available for the clip", tp.available())
	var changes: Array[float] = []
	tp.changed.connect(func(s: float) -> void: changes.append(s))

	# A tap: under HOLD_SECONDS, then let go.
	await _hold(Vector2(1, 0), 0.2)
	await _hold(Vector2.ZERO, 0.1)
	_check("a tap does not start it", tp.speed == 0.0 and changes.is_empty())

	# Hold: 4x after HOLD_SECONDS.
	var src: Object = main.player.source
	await _hold(Vector2(1, 0), 0.6)
	_check("held: 4x (%.0f, engine %.0f)" % [tp.speed, src.get_trick_play_speed()], tp.speed == 4.0
			and is_equal_approx(src.get_trick_play_speed(), 4.0))
	var shown0 := _shown()
	var p0: float = main.player.get_position()
	await _hold(Vector2(1, 0), 1.0)
	var rate4: float = main.player.get_position() - p0
	print("  4x: %.2f s of film in 1 s, %d pictures" % [rate4, _shown() - shown0])
	_check("4x moves about 4 s a second (%.2f)" % rate4, rate4 > 2.5 and rate4 < 6.0)
	_check("pictures shown meanwhile (%d)" % (_shown() - shown0), _shown() - shown0 >= 2)
	await _hold(Vector2(1, 0), 1.0)
	_check("held on: 8x (%.0f)" % tp.speed, tp.speed == 8.0)
	p0 = main.player.get_position()
	shown0 = _shown()
	await _hold(Vector2(1, 0), 1.0)
	var rate8: float = main.player.get_position() - p0
	print("  8x: %.2f s of film in 1 s, %d pictures" % [rate8, _shown() - shown0])
	_check("8x moves about 8 s a second (%.2f)" % rate8, rate8 > 5.0 and rate8 < 12.0)

	# Let go: normal playback with the audio in step.
	var t_release: int = Time.get_ticks_msec()
	await _hold(Vector2.ZERO, 0.05)
	_check("let go: normal (%s)" % [changes], tp.speed == 0.0 and src.get_trick_play_speed() == 0.0
			and changes == [4.0, 8.0, 0.0])
	var p1: float = main.player.get_position()
	var worst := 0.0
	var in_step_ms := -1
	var end := Time.get_ticks_msec() + 2500
	while Time.get_ticks_msec() < end:
		await process_frame
		var a: Object = main.player.audio
		if a.playing and not a.stream_paused:
			var off: float = main.player._audio_clock() - src.get_position()
			if absf(off) < 0.05 and in_step_ms < 0:
				in_step_ms = Time.get_ticks_msec() - t_release
			if Time.get_ticks_msec() > end - 1000:
				worst = maxf(worst, absf(off))
	var rate1: float = (main.player.get_position() - p1) / 2.5
	print("  back: audio in step after %d ms, worst offset in the last second %.0f ms, rate %.2f" % [in_step_ms, worst * 1000.0, rate1])
	_check("back to 1x (%.2f)" % rate1, rate1 > 0.8 and rate1 < 1.2)
	_check("audio in step within 0.5 s (%d ms)" % in_step_ms, in_step_ms >= 0 and in_step_ms < 500)
	# Desktop audio timing jitters (WSLg): 8 to 15 ms usually; one run in six showed 54 ms.
	_check("and stays in step (worst %.0f ms)" % (worst * 1000.0), worst < 0.1)

	# A seek ends it.
	_check("start(16) from the pane", tp.start(16.0) and tp.speed == 16.0)
	await _frames(10)
	main.player.seek(20.0)
	await _frames(30)
	_check("a seek ends it (%.0f, at %.1f s)" % [tp.speed, main.player.get_position()], tp.speed == 0.0
			and src.get_trick_play_speed() == 0.0 and absf(main.player.get_position() - 20.0) < 1.5)

	# Pausing first: the hold plays.
	main.player.pause()
	await _hold(Vector2(1, 0), 0.6)
	_check("from pause: plays and scans", tp.speed == 4.0 and main.player.is_playing())
	await _hold(Vector2.ZERO, 0.05)

	# Off: the hold does nothing (main's repeat seeks remain).
	tp.set_enabled(false)
	await _hold(Vector2(1, 0), 0.6)
	_check("off: no trick play", tp.speed == 0.0)
	await _hold(Vector2.ZERO, 0.05)
	tp.set_enabled(true)
	main.open_path("stub://flat_mono")
	await _frames(3)
	_check("a new file: idle", tp.speed == 0.0 and not tp.available())


## Feeds the stick to trick play for this long, as main._update_sticks would.
func _hold(stick: Vector2, seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	var last := Time.get_ticks_msec()
	while true:
		var now := Time.get_ticks_msec()
		main.features.trick.on_stick(HAND, stick, (now - last) / 1000.0)  # Real time (frames can be 4 ms here).
		last = now
		await process_frame
		if Time.get_ticks_msec() >= end:
			break


func _shown() -> int:
	var src: Object = main.player.source
	if src == null:
		return 0
	var st: Dictionary = src.get_stats()
	return int(st.get("frames_shown", st.get("frames_presented", st.get("frames", 0))))


func _until(cond: Callable, seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await process_frame


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL ", what)
	else:
		print("PASS ", what)
