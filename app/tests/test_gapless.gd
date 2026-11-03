extends SceneTree

## Tests for the gapless playlist (scripts/play/gapless.gd, ideas #44) in the real main scene on the fork's
## HWVideoTexture.set_next: two 14 s clips (make-feature-media.sh: gapless/gap_a.avi dark, gap_b.avi light, 10 fps,
## with a beep track) in a continuous queue. The next one is prepared 10 s before the end with the up-next card
## counting down, takes over at the last frame with no dark frame on screen and without an end, and its audio plays.
## Seeking back drops it; cancelling the card stops at the end; off goes back to the countdown after the end.
## Needs the fork and a renderer.
## Run: godot --xr-mode off --path app --script res://tests/test_gapless.gd

const Gapless := preload("res://scripts/play/gapless.gd")
var DIR := OS.get_environment("HOME") + "/media-tests/app-features/gapless/"

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
	var g: Node = main.features.gapless
	_check("off by default (until the headset check), idle", not g.enabled and g.state == "idle")
	g.set_enabled(true)
	_check("chainable: video files and network files", Gapless.chainable("/a/b.mkv") and Gapless.chainable("smb://h/s/f.mp4")
			and Gapless.chainable("http://h:8200/MediaItems/7.mkv"))
	_check("not: pictures, music, raw streams, stand-ins, the lab, udp", not Gapless.chainable("/a/b.jpg")
			and not Gapless.chainable("/a/b.flac") and not Gapless.chainable("/a/b.h264") and not Gapless.chainable("stub://flat_mono")
			and not Gapless.chainable("lab://av_sync") and not Gapless.chainable("udp://@:1234"))
	if not ClassDB.class_has_method("HWVideoTexture", "set_next") or not FileAccess.file_exists(DIR + "gap_b.avi") \
			or DisplayServer.get_name() == "headless":
		print("SKIP playback checks (needs the fork, the clips and a renderer)")
	else:
		await _playback(g)
	print("test_gapless: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _playback(g: Node) -> void:
	var a := DIR + "gap_a.avi"
	var b := DIR + "gap_b.avi"
	var siblings: Array[String] = [a, b]
	main.set_environment("void")
	main.features.queue.set_continuous(true)
	var ended := [0]
	main.player.ended.connect(func() -> void: ended[0] += 1)
	var up_next: Node = main.features.up_next

	# Not in the window yet: idle.
	main.open_path(a, true, siblings)
	await _until(func() -> bool: return main.player.get_position() > 1.0, 10.0)
	_check("the next file is b", g.next_for() == b)
	await create_timer(1.0).timeout
	_check("over 10 s left: idle", g.state == "idle")
	var dark := _brightness()
	await _until(func() -> bool: return g.state == "ready", 10.0)
	var left: float = main.player.get_duration() - main.player.get_position()
	_check("ready 10 s before the end (%.1f s left)" % left, g.state == "ready" and g.next_path == b and left > 5.0 and left <= 10.5)
	_check("the up-next card counts down to the end (%.1f)" % up_next.remaining, up_next.active and up_next.following
			and up_next.card.is_showing() and absf(up_next.remaining - left) < 1.0)
	var old: Object = main.player.source
	var chained: Object = old.get_chained()
	await create_timer(1.0).timeout
	var preroll := float(old.get("_tex").get_stats().get("next_preroll_seconds", -1.0))
	print("  the next item's first frame was ready %.3f s after chaining" % preroll)
	_check("its first frame is ready and waiting (%.3f s)" % preroll, chained != null and preroll >= 0.0 and preroll < 2.0)

	# The change: every frame from 1 s before the end to 1 s after, the picture is never black.
	await _until(func() -> bool: return main.player.get_duration() - main.player.get_position() < 1.0, 12.0)
	var darkest := 1.0
	var changed_ms := -1
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 2500:
		await process_frame
		darkest = minf(darkest, _brightness())
		if changed_ms < 0 and main.current_path == b:
			changed_ms = Time.get_ticks_msec() - t0
	var light := _brightness()
	print("  brightness: a %.3f, b %.3f, darkest during the change %.3f; b took over %d ms into the last second" % [dark,
			light, darkest, changed_ms])
	_check("b took over by itself", main.current_path == b and main.playlist_index == 1 and main.player.source == chained)
	_check("no end, no countdown after it", ended[0] == 0 and not up_next.active)
	_check("the old source closed", old.get("_tex") == null)
	_check("the picture went from dark to light", light > dark + 0.2)
	_check("no dark frame during the change (darkest %.3f, a %.3f)" % [darkest, dark], darkest > dark * 0.8)
	var a_player: AudioStreamPlayer = main.player.audio
	await create_timer(1.0).timeout
	_check("b plays with its audio (%.2f s)" % main.player.get_position(), main.player.get_position() > 1.0
			and a_player.playing and a_player.stream == main.player.source.get_audio_stream())
	_check("idle again after the change", g.state == "idle")

	# Seeking back drops the prepared item.
	main.open_path(a, true, siblings)
	await _until(func() -> bool: return main.player.get_position() > 0.5, 10.0)
	main.player.seek(main.player.get_duration() - 8.0)
	await _until(func() -> bool: return g.state == "ready", 10.0)
	var src: Object = main.player.source
	_check("ready after a seek into the window", g.state == "ready" and src.get_chained() != null)
	main.player.seek(0.0)
	await create_timer(0.6).timeout
	_check("seeking back drops it", g.state == "idle" and src.get_chained() == null and not up_next.active)

	# Cancelling the card: the film stops at its end.
	main.player.seek(main.player.get_duration() - 6.0)
	await _until(func() -> bool: return g.state == "ready", 10.0)
	up_next.cancel()
	_check("cancel: dropped", g.state == "idle" and src.get_chained() == null)
	await _until(func() -> bool: return ended[0] > 0, 10.0)
	await create_timer(0.5).timeout
	_check("cancel: it ends and stays (%s)" % main.current_path.get_file(), ended[0] == 1 and main.current_path == a
			and not up_next.active)

	# Off: the countdown after the end, as before.
	g.set_enabled(false)
	main.open_path(a, true, siblings)
	await _until(func() -> bool: return main.player.get_position() > 0.5, 10.0)
	main.player.seek(main.player.get_duration() - 4.0)
	await _until(func() -> bool: return ended[0] > 1, 10.0)
	await _frames(3)
	_check("off: no preparing, the countdown after the end", g.state == "idle" and up_next.active and not up_next.following)
	up_next.cancel()
	g.set_enabled(true)
	main.features.queue.set_continuous(false)
	main.open_path("stub://flat_mono")
	await _frames(3)


## The mean brightness of the middle of the window (the screen).
func _brightness() -> float:
	var img := root.get_texture().get_image()
	var c := Vector2i(img.get_width() / 2, img.get_height() / 2)
	var sum := 0.0
	for dy in range(-4, 5, 4):
		for dx in range(-4, 5, 4):
			sum += img.get_pixelv(c + Vector2i(dx, dy)).get_luminance()
	return sum / 9.0


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
