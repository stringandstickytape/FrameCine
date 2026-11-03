extends SceneTree

## Tests for seek-bar thumbnails (scripts/play/seek_thumbnails.gd, ideas #40) in the real main scene on the fork: off
## by default; on, a request opens a second session on the open file and gives a picture of the keyframe at or before
## the time (trick10.avi from make-feature-media.sh: a bright column moves one step a second, so the picture says
## which second it is); requests are throttled with the newest winning; pictures are cached; the film plays on
## undisturbed; another file closes the session. Needs the fork and a renderer.
## Run: godot --xr-mode off --path app --script res://tests/test_thumbnails.gd

var CLIP := OS.get_environment("HOME").path_join("media-tests/app-features/trick10.avi")

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
	var th: Node = main.features.thumbs
	_check("off by default", not th.enabled and th.state == "off")
	th.request(3.0)
	_check("off: a request does nothing", th.state == "off" and th.thumbnail_for(3.0) == null)
	if not ClassDB.class_has_method("MediaSource", "trick_play") or not FileAccess.file_exists(CLIP) \
			or DisplayServer.get_name() == "headless":
		print("SKIP playback checks (needs the fork, the clip and a renderer)")
	else:
		await _playback(th)
	print("test_thumbnails: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _playback(th: Node) -> void:
	main.set_environment("void")
	main.open_path(CLIP)
	await _until(func() -> bool: return main.player.get_position() > 1.0, 10.0)
	th.set_enabled(true)
	_check("on: idle until asked", th.enabled and th.state == "idle")
	var got: Array[float] = []
	th.thumbnail_ready.connect(func(t: float, _tex: Texture2D) -> void: got.append(t))
	var p0: float = main.player.get_position()
	var t0 := Time.get_ticks_msec()
	th.request(3.0)
	await _until(func() -> bool: return got.size() >= 1, 8.0)
	var ms := Time.get_ticks_msec() - t0
	_check("a picture for 3 s (keyframe %s, %d ms with the session's open)" % [got, ms], got.size() == 1
			and absf(got[0] - 3.0) < 0.15)
	var tex: Texture2D = th.thumbnail_for(3.0)
	_check("cached, 256 wide at the film's aspect (%s)" % (tex.get_size() if tex else Vector2.ZERO), tex != null
			and tex.get_width() == 256 and absi(tex.get_height() - 154) <= 1)
	var col := _bright_column(tex)
	_check("it shows second 3: the bright column at 0.30-0.40 (%.2f)" % col, col > 0.28 and col < 0.42)

	t0 = Time.get_ticks_msec()
	th.request(7.5)
	await _until(func() -> bool: return got.size() >= 2, 8.0)
	ms = Time.get_ticks_msec() - t0
	col = _bright_column(th.thumbnail_for(7.5))
	_check("7.5 s: second 7, column at 0.70-0.80 (%.2f, %d ms)" % [col, ms], got.size() == 2 and col > 0.68 and col < 0.82)
	_check("near times share a picture; far ones have none", th.thumbnail_for(8.5) == th.thumbnail_for(7.5)
			and th.thumbnail_for(60.0) == null)

	# Scrubbing: three requests at once; the newest wins.
	var before := got.size()
	th.request(20.0)
	th.request(40.0)
	th.request(55.0)
	await _until(func() -> bool: return got.size() > before and absf(got.back() - 55.0) < 0.15, 8.0)
	print("  scrub: grabbed %s" % [got.slice(before)])
	_check("the newest request wins", got.size() > before and absf(got.back() - 55.0) < 0.15 and got.size() - before <= 2)
	col = _bright_column(th.thumbnail_for(55.0))
	_check("55 s: column at 0.50-0.60 (%.2f)" % col, col > 0.48 and col < 0.62)

	await create_timer(1.0).timeout
	var a: AudioStreamPlayer = main.player.audio
	var off: float = main.player._audio_clock() - main.player.source.get_position()
	_check("the film played on meanwhile with its sound (%.2f -> %.2f, A/V %.0f ms)" % [p0, main.player.get_position(),
			off * 1000.0], main.player.get_position() > p0 + 1.0 and a.playing and absf(off) < 0.1
			and main.player.source.get_audio_track() >= 0)

	main.open_path("stub://flat_mono")
	await _frames(3)
	_check("another file: session closed, cache cleared", th.state == "idle" and th._tex == null and th.thumbnail_for(3.0) == null)
	th.set_enabled(false)
	_check("off again", th.state == "off")


## The x of the brightest column of the picture's middle row, as a fraction of its width.
func _bright_column(tex: Texture2D) -> float:
	if tex == null:
		return -1.0
	var img := tex.get_image()
	var y := img.get_height() / 2
	var best := -1.0
	var best_x := 0
	for x in img.get_width():
		var l := img.get_pixel(x, y).get_luminance()
		if l > best:
			best = l
			best_x = x
	# The middle of the bright run that starts there.
	var end := best_x
	while end + 1 < img.get_width() and img.get_pixel(end + 1, y).get_luminance() > best - 0.1:
		end += 1
	return (best_x + end) * 0.5 / img.get_width()


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
