extends SceneTree

## Tests for the delight features (ideas #34, #37, #39, #63, #66) in the real main scene with test patterns: the
## up-next countdown, pre-show curtains, the intermission, the jog wheel, stereo screenshots (the capture itself needs
## a renderer: skipped with --headless). Settings are read-only.
## Run: godot --xr-mode off --path app --script res://tests/test_delight.gd   (or --headless without the capture)

const VideoMode := preload("res://scripts/video_mode.gd")
const Shot := preload("res://scripts/play/stereo_screenshot.gd")

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
	var f: Node = main.features
	main.set_environment("cinema")

	# #37 pre-show: a film from its start sits behind closed curtains; they part on play and close at the end.
	main.open_path("stub://flat_mono")
	await _frames(2)
	_check("cinema has curtains; closed or just opening at the start (%.2f)" % f.preshow.openness,
			f.preshow.available() and f.preshow.openness < 0.2)
	await _sleep(4.5)
	_check("open after the film starts (%.2f)" % f.preshow.openness, f.preshow.openness > 0.99 and not f.preshow.visible)

	# #34 up next: with continuous play, the end counts down to the next file; a seek cancels.
	f.queue.set_continuous(true)
	f.up_next.set_seconds(3.0)
	var first: String = main.current_path
	var index: int = main.playlist_index
	_end_of_file()
	await _wait(func() -> bool: return f.up_next.active, 4.0)
	_check("at the end: the countdown to the next file (%s)" % f.up_next.next_path, f.up_next.active
			and f.up_next.next_path == main.playlist[index + 1] and f.up_next.card.is_showing())
	_check("the card names it", f.up_next.card.title.begins_with("Up next: "))
	await _sleep(1.0)
	_check("curtains close at the end (%.2f)" % f.preshow.openness, f.preshow.openness < 0.9)
	_check("still on the same file during the countdown", main.current_path == first)
	await _wait(func() -> bool: return main.current_path != first, 4.0)
	_check("after the countdown the next file opens", main.playlist_index == index + 1 and not f.up_next.active)
	var second: String = main.current_path
	_end_of_file()
	await _wait(func() -> bool: return f.up_next.active, 4.0)
	main.player.seek(100.0)
	await _frames(2)
	_check("a seek cancels it", not f.up_next.active and not f.up_next.card.is_showing() and main.current_path == second)
	main.auto_advance = true
	_end_of_file()
	await _wait(func() -> bool: return main.current_path != second, 4.0)
	_check("a --dir run goes on at once", not f.up_next.active and main.current_path != second)
	main.auto_advance = false
	f.queue.set_continuous(false)

	# #39 intermission: at the chapter start nearest the middle; pauses, closes the curtains, the card, resume.
	main.open_path("stub://flat_mono")
	await _frames(3)
	f.intermission.set_enabled(true)
	f.intermission.min_film_minutes = 5.0
	var p: float = f.intermission.point()
	var d: float = main.player.get_duration()
	_check("the stop point is a chapter start near the middle (%.0f of %.0f)" % [p, d], p >= d * 0.35 and p <= d * 0.65)
	await _sleep(4.5)
	main.player.seek(p - 1.0)
	main.player.play()
	await _wait(func() -> bool: return f.intermission.active, 4.0)
	_check("it stops there: paused, the card", f.intermission.active and not main.player.is_playing()
			and f.intermission.card.is_showing() and f.intermission.card.title == "Intermission")
	await _sleep(1.0)
	_check("the curtains close (%.2f)" % f.preshow.openness, f.preshow.openness < 0.8)
	_check("the card counts down", f.intermission.card.line.begins_with("The film continues in "))
	f.intermission.resume_now()
	await _frames(2)
	_check("resume: playing, card gone, curtains opening", main.player.is_playing() and not f.intermission.card.is_showing()
			and f.preshow._target == 1.0)
	main.player.seek(p - 1.0)
	await _sleep(2.0)
	_check("only once per showing", not f.intermission.active and f.intermission.done)
	f.intermission.set_enabled(false)
	_check("films shorter than the minimum never stop", (func() -> bool:
		f.intermission.min_film_minutes = 100.0
		return f.intermission.point() < 0.0).call())

	# #63 jog wheel: a circle at the rim scrubs (60 s a turn); a quick flick still seeks 10 s.
	main.set_environment("void")
	main.player.seek(200.0)
	await _frames(3)
	var hand := "test hand"
	var start: float = main.player.get_position()
	var consumed := true
	for i in 13:  # a quarter turn clockwise, from the top
		var a := deg_to_rad(i * 7.5)
		consumed = f.jog.on_stick(hand, Vector2(sin(a), cos(a)), 1.0 / 60.0) and consumed
	_check("a quarter circle: the jog has the stick", consumed and f.jog.jogging(hand))
	_check("target about 15 s on (%.1f)" % (f.jog.target - start), absf(f.jog.target - start - 15.0) < 2.0)
	_check("the card shows the time", f.jog.card.is_showing())
	f.jog.on_stick(hand, Vector2.ZERO, 1.0 / 60.0)
	await _frames(3)
	_check("let go: seeks there, card gone (%.1f)" % main.player.get_position(), absf(main.player.get_position() - f.jog.target) < 1.0
			and not f.jog.card.is_showing() and not f.jog.jogging(hand))
	var before: float = main.player.get_position()
	f.jog.on_stick(hand, Vector2(1, 0), 1.0 / 60.0)
	f.jog.on_stick(hand, Vector2(1, 0), 1.0 / 60.0)
	f.jog.on_stick(hand, Vector2.ZERO, 1.0 / 60.0)
	await _frames(3)
	_check("a quick flick right still seeks +10 s (%.1f)" % (main.player.get_position() - before),
			absf(main.player.get_position() - before - 10.0) < 1.0)
	before = main.player.get_position()
	var held := false
	for i in 20:  # held right past the decision time: main gets it
		held = f.jog.on_stick(hand, Vector2(1, 0), 1.0 / 60.0)
	_check("held still at the rim: handed back to main", not held and not f.jog.jogging(hand))
	f.jog.on_stick(hand, Vector2.ZERO, 1.0 / 60.0)

	# #66 stereo screenshots: names that reopen in the same mode; the capture with a renderer.
	var sbs := VideoMode.from_id("flat_sbs_half")
	_check("names: flat SBS", Shot.file_name("/v/My Film.mkv", 3725.0, sbs, true) == "My_Film_1h02m05s_sbs.jpg")
	_check("names: 360 TB", Shot.file_name("/v/a.mp4", 5.0, VideoMode.from_id("360_tb"), true).ends_with("_360_tb.jpg"))
	_check("names: reopen in the same mode", VideoMode.guess(Shot.file_name("/v/a.mp4", 5.0, VideoMode.from_id("180_sbs"), true)).to_id()
			== VideoMode.from_id("180_sbs").to_id())
	if DisplayServer.get_name() == "headless":
		print("SKIP the capture (headless)")
	else:
		main.open_path("stub://flat_sbs")
		await _frames(10)
		var path: String = await f.screenshot.capture()
		var img := Image.load_from_file(ProjectSettings.globalize_path(path)) if path != "" else null
		_check("capture saved (%s)" % path, img != null and path.ends_with("_sbs.jpg"))
		if img != null:
			# The pattern: the left eye's picture is red, the right one blue.
			var l := img.get_pixel(img.get_width() / 4, img.get_height() / 8)
			var r := img.get_pixel(img.get_width() * 3 / 4, img.get_height() / 8)
			_check("left half from the left eye, right from the right (%s / %s)" % [l, r], l.r > l.b and r.b > r.r)
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("test_delight: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


## The test patterns loop rather than end: the player's end of file, as a real file gives it (main._on_ended runs).
func _end_of_file() -> void:
	main.player.pause()
	main.player.ended.emit()


func _wait(cond: Callable, seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await process_frame


func _sleep(seconds: float) -> void:
	await create_timer(seconds).timeout


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL " + what)
	else:
		print("PASS " + what)
