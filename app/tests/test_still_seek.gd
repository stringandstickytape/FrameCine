extends SceneTree

## Sparse video in the real main scene: a resume or a seek in a 1 fps file, a slideshow, a video track that ends long
## before the audio, audio packets that outnumber the video by far, an MP3 with a cover, and a 24 fps file for comparison.
## After each, the picture (where there is one) and the sound must start and the position must move on. Needs a renderer
## and the clips of make-still-media.sh.
## The desktop decodes in software, which isn't paced. The headset's feed is tested through the fake decoder: fake_v4l2.c
## (LD_PRELOAD, FAKE_V4L2_DELAY pictures of reorder delay), on an engine with fake-import.patch (x86_64 test build only),
## with HWVIDEO_TEST_FAKE_IMPORT=1 (see make-still-media.sh).
## Run: godot --xr-mode off --path app --script res://tests/test_still_seek.gd

const FileKey := preload("res://scripts/play/file_key.gd")

## The most a resume or a seek may take to bring the sound back, in seconds.
const START_LIMIT := 1.0
const MEDIA := "/media-tests/still/"

var _failures := 0
var _checks := 0
var main: Node3D


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	for i in 5:
		await process_frame
	if DisplayServer.get_name() == "headless" or not FileAccess.file_exists(_clip("still_1fps.mkv")):
		print("SKIP (needs a renderer and the clips of make-still-media.sh)")
	else:
		main.set_environment("void")
		await _resume("still_1fps.mkv", 274.0, 1.0)
		await _resume("slideshow_0p1fps.mkv", 300.0, 10.0)
		await _resume("still_truehd.mkv", 60.0, 1.0)
		await _resume("video_ends_early.mkv", 200.0)
		await _resume("chunky_0p1fps.mkv", 300.0)
		await _resume("cover.mp3", 60.0)
		await _resume("normal_24fps.mkv", 40.0, 1.0 / 24.0)
		await _open_audio_first()
		await _seek("still_1fps.mkv", 300.0, 1.0)
		await _seek("video_ends_early.mkv", 200.0)
		await _seek("normal_24fps.mkv", 30.0, 1.0 / 24.0)
	print("test_still_seek: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	main.close_media()
	quit(_failures)


func _clip(file: String) -> String:
	return OS.get_environment("HOME") + MEDIA + file


## Opens the file with a saved position, as the app does after a restart.
func _resume(file: String, position: float, interval := 0.0) -> void:
	var clip := _clip(file)
	var resume: Node = main.features.resume
	var key := FileKey.key(clip)
	resume._cfg.set_value(key, "path", clip)
	resume._cfg.set_value(key, "position", position)
	resume._cfg.set_value(key, "duration", 600.0)
	main.open_path(clip)
	await _plays("resume %s at %.0f" % [file, position], position - 3.0, interval, position - 1.0)
	resume._cfg.erase_section(key)


## A seek while the file plays.
func _seek(file: String, to: float, interval := 0.0) -> void:
	var clip := _clip(file)
	main.open_path(clip)
	await _until(func() -> bool: return main.player.get_position() > 1.0, 5.0)
	main.player.seek(to)
	await _plays("seek in %s to %.0f" % [file, to], to, interval, to + 2.0)


## Audio before all the video in the file, more than the audio queues hold: the sound starts, nothing waits for a frame.
func _open_audio_first() -> void:
	var file := "audio_first.mkv"
	main.open_path(_clip(file))
	await _plays("open %s" % file, 0.0, 0.0, 2.0)


## interval: seconds from one picture to the next, 0 where no picture is expected.
func _plays(what: String, start: float, interval: float, reach: float) -> void:
	var p: Node = main.player
	var t0 := Time.get_ticks_msec()
	await _until(func() -> bool: return p.source != null and not p.is_settling() and p.audio.playing \
			and not p.audio.stream_paused, START_LIMIT)
	var waited := (Time.get_ticks_msec() - t0) / 1000.0
	_check("%s: the sound is on (%.2f s)" % [what, waited], p.audio.playing and not p.audio.stream_paused)
	await _until(func() -> bool: return p.get_position() >= reach, 4.0)
	_check("%s: plays on from %.1f (at %.1f)" % [what, start, p.get_position()], p.get_position() >= reach)
	if interval > 0.0:
		var stats := func() -> Dictionary: return p.source.get_stats()
		_check("%s: a picture" % what, p.source.has_frame())
		var shown: int = stats.call().get("frames_shown", 0)
		await _until(func() -> bool: return int(stats.call().get("frames_shown", 0)) > shown, interval * 2.0 + 0.5)
		_check("%s: the picture moves on" % what, int(stats.call().get("frames_shown", 0)) > shown)
		var late: float = p.get_position() - float(stats.call().get("frame_time", -1.0))
		_check("%s: the picture keeps up (%.2f s behind)" % [what, late], late < interval * 1.6 + 0.1)


func _until(condition: Callable, seconds: float) -> void:
	var t0 := Time.get_ticks_msec()
	while not condition.call() and Time.get_ticks_msec() - t0 < seconds * 1000.0:
		await process_frame


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if ok:
		print("PASS ", what)
	else:
		_failures += 1
		print("FAIL ", what)
