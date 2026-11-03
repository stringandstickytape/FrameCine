extends SceneTree

## Playback features on real files through MediaSource (engine fork with modules/hwvideo). Uses test media made in
## WSL (the engine-demux agent's features/ set and tests/make-feature-media.sh), not in the repository:
##   $MEDIA_TESTS (default ~/media-tests): features/meta_*.{mkv,mp4}, app-features/vp9_sbs_chapters_subs.mkv
## Off the headset there is no V4L2 decoder, so only VP9 (the engine's software path, up to 1080p) opens through the
## app; the H.264 files are checked at the MediaSource level.
## Skips (exit 0) when the engine has no MediaSource or the files are missing.
## Run: godot --headless --xr-mode off --path app --script res://tests/test_media_features.gd

const ContainerMode := preload("res://scripts/play/container_mode.gd")

var _failures := 0
var _checks := 0
var main: Node3D
var media := ""


func _init() -> void:
	media = OS.get_environment("MEDIA_TESTS")
	if media == "":
		media = OS.get_environment("HOME").path_join("media-tests")
	if not ClassDB.class_exists("MediaSource") or not DirAccess.dir_exists_absolute(media.path_join("features")):
		print("test_media_features: skipped (no MediaSource, or no %s/features)" % media)
		quit(0)
		return
	_metadata_direct()
	_languages_direct()
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	_run.call_deferred()


## #25 and #15 straight from MediaSource: what each file's container says, and the mode the app takes from it.
func _metadata_direct() -> void:
	# file -> expected mode id from the metadata ("" = none), and whether it has chapters
	var cases := {
		"meta_none.mp4": ["", false],
		"meta_sbs_chapters.mkv": ["flat_sbs*", true],
		"meta_tb_inverted.mkv": ["flat_tb*swap", false],
		"meta_vr180.mkv": ["180_sbs", false],
		"meta_vr180.mp4": ["180_sbs", true],
		"meta_360_tb.mp4": ["360_tb", false],
	}
	for file: String in cases:
		var path := media.path_join("features").path_join(file)
		if not FileAccess.file_exists(path):
			_check("%s present" % file, false)
			continue
		var src: Object = ClassDB.instantiate("MediaSource")
		if src.call("open", path) != OK:
			_check("%s opens: %s" % [file, src.call("get_last_error")], false)
			continue
		var info: Dictionary = src.call("get_video_info")
		var r := ContainerMode.from_info(info, file, int(info.get("width", 0)), int(info.get("height", 0)))
		var got: String = r["mode"].to_id() if r["mode"] != null else ""
		var want: String = cases[file][0]
		var meta := "stereo '%s'%s, projection '%s' %s" % [info.get("stereo_mode", "?"),
				" inverted" if info.get("stereo_inverted", false) else "", info.get("projection", "?"),
				info.get("projection_fov", "")]
		_check("%s: %s -> '%s' (%s), want '%s'" % [file, meta, got, r["reason"], want],
				got == "" if want == "" else got.match(want))
		var chapters: Array = src.call("get_chapters") if src.has_method("get_chapters") else []
		_check("%s: %d chapters" % [file, chapters.size()], (chapters.size() > 0) == bool(cases[file][1]))
		src.call("close")


## #28 with the engine's helpers: normalisation, and the app's pick agreeing with the engine's on real track lists.
func _languages_direct() -> void:
	var LM := preload("res://scripts/play/language_memory.gd")
	if not ClassDB.class_has_method("MediaSource", "normalize_language"):
		print("  (no normalize_language: engine language checks skipped)")
		return
	_check("engine normalisation: German / ger / deu / de -> de",
			["German", "ger", "deu", "de"].all(func(c: String) -> bool: return LM.normalize(c) == "de"))
	_check("region kept: pt_BR -> pt-br (%s)" % LM.normalize("pt_BR"), LM.normalize("pt_BR") == "pt-br")
	_check("und -> none", LM.normalize("und") == "")
	var path := media.path_join("features/ext/Film.Name.2019.mkv")
	if not FileAccess.file_exists(path) or not ClassDB.class_exists("MediaBrowser"):
		return
	var src: Object = ClassDB.instantiate("MediaSource")
	if src.call("open", path) != OK:
		_check("ext film opens", false)
		return
	var browser: Object = ClassDB.instantiate("MediaBrowser")
	for s: Dictionary in browser.call("find_subtitles", path):
		src.call("add_external_subtitle", str(s["path"]))
	var tracks: Array = src.call("get_subtitle_tracks")
	for langs: Array in [["de"], ["fr"], ["en"], ["pt-BR"], ["it", "es"], ["xx"]]:
		var pl := PackedStringArray(langs)
		for forced: bool in [false, true]:
			var engine := int(src.call("pick_subtitle_track", pl, forced))
			var ours := LM._pick(tracks, pl, true, forced)
			_check("subtitle pick %s%s: engine %d, app %d" % [langs, " forced" if forced else "", engine, ours],
					engine == ours)
	src.call("close")


func _run() -> void:
	await _frames(5)
	var f: Node = main.features
	if main.ui != null:
		main.ui.hide_panel()

	# Opened through the app: the hardware source class with MediaSource (VP9: the software path on a desktop).
	var path := media.path_join("app-features/vp9_sbs_chapters_subs.mkv")
	if not FileAccess.file_exists(path):
		print("  (no %s: run tests/make-feature-media.sh; app-path checks skipped)" % path)
		print("test_media_features: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
		quit(_failures)
		return
	main.open_path(path)
	await _wait_until(func() -> bool: return main.player.has_source() and main.player.source.has_frame(), 10.0)
	var kind: String = main.player.source.get_kind() if main.player.has_source() else "none"
	_check("app opens it with the hardware source class (%s: %s)" % [kind, main.player.source.last_error if main.player.has_source() else ""],
			kind == "hw")
	if kind == "hw":
		_check("mode from the container (%s, %s)" % [main.mode.to_id(), main.mode_source], main.mode_source == "metadata"
				and main.mode.layout == preload("res://scripts/video_mode.gd").Layout.SBS)
		var ch: Node = f.chapters
		_check("chapters through the app: %d, now '%s'" % [ch.chapters.size(), ch.title_text()], ch.chapters.size() > 0)
		if ch.chapters.size() > 1:
			ch.next_chapter()
			await _wait_until(func() -> bool: return not main.player.source.is_settling(), 5.0)
			await _frames(10)
			_check("next chapter seeks there (%.2f, chapter 2 at %.2f)" % [main.player.get_position(),
					ch.chapters[1]["start"]], absf(main.player.get_position() - float(ch.chapters[1]["start"])) < 1.0)

	# Subtitles from the same file (SubRip, "Cue 0 at 1 s" at 1-3.5 s): tracks listed, events arrive, a line shows.
	if kind == "hw":
		var sub: Node = f.subtitles
		_check("subtitle tracks listed (%d: %s)" % [sub.tracks.size(), sub.tracks.map(func(t: Dictionary) -> String:
				return "%s/%s" % [t.get("language", ""), t.get("codec", "")])], sub.tracks.size() > 0)
		if sub.tracks.size() > 0:
			sub.select_track(sub.pick_track())
			# Headless, the audio driver is a dummy and the audio master clock doesn't run, so move by seeking.
			main.player.seek(0.0)
			await _wait_until(func() -> bool: return sub.event_count() > 0, 8.0)
			_check("events arrive (%d)" % sub.event_count(), sub.event_count() > 0)
			main.player.seek(1.5)
			await _wait_until(func() -> bool: return sub.text != "", 8.0)
			_check("the line shows at 1.5 s: '%s' (position %.2f)" % [sub.text.left(40), main.player.get_position()],
					sub.text == "Cue 0 at 1 s")
			_check("text at 1.5 s is the first cue ('%s')" % sub.text_at(1.5), sub.text_at(1.5) == "Cue 0 at 1 s")
			# Catch-up replay on a real source: back 10 s (to 0 here), subtitles forced on.
			sub.set_enabled(false)
			main.player.seek(7.0)
			await _wait_until(func() -> bool: return not main.player.source.is_settling(), 5.0)
			f.catch_up.replay()
			await _frames(3)
			await _wait_until(func() -> bool: return not main.player.source.is_settling(), 5.0)
			await _frames(5)
			_check("catch-up on a real source: subtitles on, back near 0 (%.1f)" % main.player.get_position(),
					f.catch_up.active and sub.enabled and main.player.get_position() < 2.0)
			f.catch_up.cancel()
			sub.set_enabled(false)

		# #50 subtitle files next to the video, and #28's forced parts: German audio, subtitles off -> the forced file.
		var sf: Node = f.sub_files
		if sf.available():
			f.languages.forget()
			f.languages.subtitle_languages = PackedStringArray(["fr"])
			main.open_path(path)
			await _wait_until(func() -> bool: return sf.loaded.size() >= 2, 10.0)
			await _frames(2)
			_check("subtitle files loaded as tracks (%d files, %d tracks)" % [sf.loaded.size(), sub.tracks.size()],
					sf.loaded.size() == 2 and sub.tracks.size() == 3)
			var cur: Dictionary = sub.current_track()
			_check("subtitles off + German audio: the forced German file shows (%s)" % cur,
					sub.enabled and bool(cur.get("forced", false)) and str(cur.get("language_code", cur.get("language", ""))).begins_with("de"))
			_check("the user's own setting is still off", not bool(main.settings.get_value("subtitles", "enabled", true)))
			sub.set_enabled(true)
			cur = sub.current_track()
			_check("turned on: the remembered language, full track (%s)" % cur,
					str(cur.get("language_code", cur.get("language", ""))).begins_with("fr") and not bool(cur.get("forced", false)))
			main.player.seek(1.5)
			await _wait_until(func() -> bool: return sub.text != "", 8.0)
			_check("a line from the file shows: '%s'" % sub.text, sub.text == "Cue 0 at 1 s")
			# #65 second track: the German file, read by the app, above the French one.
			var second := -1
			for t: Dictionary in sub.secondary_tracks():
				if str(t.get("language_code", t.get("language", ""))).begins_with("de"):
					second = int(t["index"])
			sub.select_secondary(second)
			var rd: Node = sub.display
			var labels := func() -> Array: return rd.find_children("*", "RichTextLabel", true, false)
			await _wait_until(func() -> bool: return labels.call().size() == 2, 5.0)
			var texts: Array = labels.call().map(func(l: RichTextLabel) -> String: return l.get_parsed_text())
			_check("second track: the German file's line drawn with the French one (%s)" % [texts],
					second >= 0 and texts.size() == 2 and texts[0] == "Cue 0 at 1 s" and texts[1] == "Cue 0 at 1 s")
			sub.select_secondary(-1)
			# #61: a negative delay reads the video further ahead.
			f.sub_delay.set_delay(-4.0)
			var media_obj: Object = main.player.source._media
			_check("negative delay sets the read-ahead (%.1f)" % float(media_obj.get("subtitle_read_ahead")),
					is_equal_approx(float(media_obj.get("subtitle_read_ahead")), 4.0))
			f.sub_delay.set_delay(0.5)
			_check("positive delay: no read-ahead", is_zero_approx(float(media_obj.get("subtitle_read_ahead"))))
			f.sub_delay.reset()
			# #69: the speed reaches the MediaSource (its audio is the clock) and the texture.
			f.speed.set_speed(1.5)
			_check("speed 1.5 on the MediaSource (%.2f)" % float(media_obj.get("playback_speed")),
					is_equal_approx(float(media_obj.get("playback_speed")), 1.5))
			f.speed.reset()
			sub.set_enabled(false)
			f.languages.forget()

	print("test_media_features: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _wait_until(cond: Callable, seconds: float) -> void:
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
		printerr("FAIL " + what)
	else:
		print("PASS " + what)
