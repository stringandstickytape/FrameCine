extends SceneTree

## Tests for crossfades between items (scripts/play/crossfade.gd, ideas #94) in the real main scene on the fork, in a
## continuous queue: music (tone_steps.wav into tone_steps.flac, make-feature-files.sh) overlaps for 4 s with the
## sound going over at equal power, and the next track carries on from where its fade got to; videos (gapless/gap_a.avi
## dark into gap_b.avi light, make-feature-media.sh) overlap for 3 s with the next picture fading in over the screen
## (read back from the window) while the gapless change stands aside. Off by default. Needs the fork and a renderer.
## Run: godot --xr-mode off --path app --script res://tests/test_crossfade.gd

var MUSIC := OS.get_environment("HOME") + "/media-tests/features/music/"
var VIDEO := OS.get_environment("HOME") + "/media-tests/app-features/gapless/"

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
	var cf: Node = main.features.crossfade
	_check("off by default", cf.music_seconds == 0.0 and cf.video_seconds == 0.0 and not cf.active)
	cf.set_music_seconds(20.0)
	cf.set_video_seconds(-1.0)
	_check("clamped", cf.music_seconds == 12.0 and cf.video_seconds == 0.0)
	if not ClassDB.class_has_method("HWVideoTexture", "set_next") or not FileAccess.file_exists(MUSIC + "tone_steps.flac") \
			or not FileAccess.file_exists(VIDEO + "gap_b.avi") or DisplayServer.get_name() == "headless":
		print("SKIP playback checks (needs the fork, the clips and a renderer)")
	else:
		main.set_environment("void")
		main.features.queue.set_continuous(true)
		await _music(cf)
		await _video(cf)
		main.features.queue.set_continuous(false)
	print("test_crossfade: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _music(cf: Node) -> void:
	cf.set_music_seconds(4.0)
	var a := MUSIC + "tone_steps.wav"
	var b := MUSIC + "tone_steps.flac"
	var siblings: Array[String] = [a, b]
	var ended := [0]
	var on_end := func() -> void: ended[0] += 1
	main.player.ended.connect(on_end)
	main.open_path(a, true, siblings)
	await _until(func() -> bool: return main.player.get_position() > 0.5, 10.0)
	var dur: float = main.player.get_duration()
	print("  music: %.1f s" % dur)
	main.player.seek(dur - 8.0)
	await _until(func() -> bool: return cf.active, 5.0)
	_check("music: the next track opens before the fade (%.1f s left)" % (dur - main.player.get_position()), cf.active
			and cf.next_path == b and cf.progress == 0.0)
	await _until(func() -> bool: return cf.progress >= 0.45, 8.0)
	var v1: float = main.player.audio.volume_db
	var v2: float = cf._player2.volume_db
	print("  mid-fade %.2f: outgoing %.1f dB, incoming %.1f dB" % [cf.progress, v1, v2])
	_check("music: halfway, both near -3 dB, both playing", absf(v1 + 3.0) < 1.5 and absf(v2 + 3.0) < 1.5
			and cf._player2.playing and main.player.audio.playing)
	await _until(func() -> bool: return main.current_path == b, 6.0)
	await _frames(3)
	var pos: float = main.player.get_position()
	print("  the flac took over at %.2f s" % pos)
	_check("music: the next track took over without an end", main.current_path == b and ended[0] == 0
			and main.player.source.get_kind() == "music")
	_check("music: from where its fade got to (%.2f)" % pos, pos > 3.0 and pos < 5.0)
	await create_timer(0.5).timeout
	_check("music: full volume, one player", is_equal_approx(main.player.audio.volume_db, 0.0) and main.player.audio.playing
			and not cf._player2.playing and not cf.active)
	main.player.ended.disconnect(on_end)
	cf.set_music_seconds(0.0)


func _video(cf: Node) -> void:
	cf.set_video_seconds(3.0)
	var a := VIDEO + "gap_a.avi"
	var b := VIDEO + "gap_b.avi"
	var siblings: Array[String] = [a, b]
	var ended := [0]
	var on_end := func() -> void: ended[0] += 1
	main.player.ended.connect(on_end)
	main.open_path(a, true, siblings)
	await _until(func() -> bool: return main.player.get_position() > 0.5, 10.0)
	var dark := _brightness()
	main.player.seek(main.player.get_duration() - 6.0)
	await _until(func() -> bool: return cf.active, 5.0)
	_check("videos: crossfade, not the gapless change", cf.active and main.features.gapless.state == "idle")
	_check("videos: the up-next card counts down", main.features.up_next.following)
	await _until(func() -> bool: return cf.progress >= 0.5, 6.0)
	await _frames(2)
	var mid := _brightness()
	await _until(func() -> bool: return main.current_path == b, 4.0)
	await create_timer(0.5).timeout
	var light := _brightness()
	print("  brightness: dark %.3f, halfway %.3f, light %.3f; b at %.2f s" % [dark, mid, light, main.player.get_position()])
	_check("videos: halfway, between the two pictures", mid > dark + 0.1 and mid < light - 0.1)
	_check("videos: b took over without an end, from its fade (%.2f)" % main.player.get_position(), main.current_path == b
			and ended[0] == 0 and main.player.get_position() > 2.5 and main.player.get_position() < 4.5)
	_check("videos: overlay gone, full volume", not cf.overlay.visible and is_equal_approx(main.player.audio.volume_db, 0.0)
			and main.player.audio.playing)
	var off: float = main.player._audio_clock() - main.player.source.get_position()
	_check("videos: A/V in step after (%.0f ms)" % (off * 1000.0), absf(off) < 0.1)
	main.player.ended.disconnect(on_end)

	# A seek back drops it.
	main.open_path(a, true, siblings)
	await _until(func() -> bool: return main.player.get_position() > 0.5, 10.0)
	main.player.seek(main.player.get_duration() - 4.0)
	await _until(func() -> bool: return cf.progress > 0.2, 5.0)
	main.player.seek(1.0)
	await create_timer(0.3).timeout
	_check("videos: a seek back drops it", not cf.active and not cf.overlay.visible
			and is_equal_approx(main.player.audio.volume_db, 0.0) and main.current_path == a)
	cf.set_video_seconds(0.0)
	main.open_path("stub://flat_mono")
	await _frames(3)


func _brightness() -> float:
	var img := root.get_texture().get_image()
	var c := Vector2i(img.get_width() / 2, img.get_height() / 2)
	var sum := 0.0
	for dy in [-4, 0, 4]:
		for dx in [-4, 0, 4]:
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
