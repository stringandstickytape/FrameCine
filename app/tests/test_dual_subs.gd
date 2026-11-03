extends SceneTree

## Tests for a second embedded subtitle track (scripts/play/subtitles.gd, ideas #65) on the engine's
## select_secondary_subtitle_track (PLAYER_REQUESTS) in the real main scene: animated_subs.mkv (make-test-files.sh) has a
## SubRip track (index 0, "Cue N at T s") and an ASS track (index 1, "ASS N"), both English, cues every 5 s; in this
## clip the cues are muxed 8.3 s late (Cue 0: 9.3-11.8 s, ASS 0: 9.3-11.3 s).
## The ASS track is offered as a second track, read by the engine alongside the SubRip one, routed by each event's
## "track", shown with the main one, and turned off again. Needs the fork (8-bit H.264 decodes in software on the
## desktop build since PLAYER_FINAL).
## Run: godot --xr-mode off --path app --script res://tests/test_dual_subs.gd

var CLIP := OS.get_environment("HOME").path_join("media-tests/animated_subs.mkv")

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
	if not ClassDB.class_has_method("MediaSource", "select_secondary_subtitle_track") or not FileAccess.file_exists(CLIP):
		print("SKIP (needs the fork's PLAYER_REQUESTS build and the clip)")
	else:
		await _dual()
	print("test_dual_subs: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _dual() -> void:
	var sub: Node = main.features.subtitles
	main.set_environment("void")
	main.open_path(CLIP)
	await _until(func() -> bool: return main.player.source != null and main.player.get_position() > 0.3, 10.0)
	var src: Object = main.player.source
	_check("the clip opens (%s)" % src.get_kind(), src.get_kind() == "hw" and src.has_secondary_subtitles())
	sub.select_track(0)
	var offered: Array = sub.secondary_tracks().map(func(t: Dictionary) -> int: return int(t["index"]))
	_check("the ASS track is offered as the second (%s)" % [offered], offered == [1])
	sub.select_secondary(1, false)
	_check("selected in the engine", sub.secondary == 1 and src.get_secondary_subtitle_track() == 1)
	# Choosing tracks doesn't seek (the demuxer has read ahead): go back so both tracks' lines come through.
	main.player.seek(4.0)
	await _until(func() -> bool: return main.player.get_position() > 10.0, 20.0)
	await _frames(3)
	var main_text: String = sub.text
	var second: Array = sub._second.active(main.player.get_position() - sub.delay)
	var second_text := "" if second.is_empty() else str(second[0][2])
	print("  at %.1f s: main '%s', second '%s'" % [main.player.get_position(), main_text, second_text.replace("\n", " / ")])
	_check("main track: the SubRip cue", main_text.begins_with("Cue 0"))
	_check("second track: the ASS cue, routed by its track", second_text.begins_with("ASS 0") and not main_text.contains("ASS"))
	_check("both on screen", sub._shown_ids.any(func(i: int) -> bool: return i < 0) and sub._shown_ids.any(func(i: int) -> bool: return i > 0))
	sub.select_secondary(-1, false)
	_check("off: the engine reads one track again", sub.secondary == -1 and src.get_secondary_subtitle_track() == -1
			and sub._second.events.is_empty())
	sub.select_secondary(1, false)
	sub.select_track(1)
	_check("the main track taking the second's index clears the second", sub.track == 1 and sub.secondary == -1
			and src.get_secondary_subtitle_track() == -1)
	main.open_path("stub://flat_mono")
	await _frames(3)


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
