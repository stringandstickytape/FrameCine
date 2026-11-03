extends SceneTree
## Desktop tests of the MediaSource features for the app (docs/ideas.md #15, #25, #28, #50, #61): chapters, stereo and
## spherical metadata, subtitle files next to the video, language picks, and the subtitle read-ahead. Headless, on the
## x86_64 build; files from make-feature-files.sh.
##   godot --headless --path spikes/03-player/demux-test --script features_test.gd [-- --films]
## --films also lists the chapters and metadata of the local films (no checks). The checks on real films read them from
## the local test library: a folder of links, with the neutral names used here, to films of your own ($VRVP_LIBRARY,
## default ~/media-tests/library); a missing one is skipped.

var F := OS.get_environment("HOME").path_join("media-tests/features")
var M := (OS.get_environment("VRVP_LIBRARY") if OS.has_environment("VRVP_LIBRARY")
		else OS.get_environment("HOME").path_join("media-tests/library"))

var failures := 0
var checks := 0


func _init() -> void:
	_languages()
	_subtitle_names()
	_metadata()
	_external_subtitles()
	_styled_subtitles()
	_bitmap_subtitles()
	_audio_picks()
	_read_ahead()
	_bitrate()
	_overlay_stats()
	_playback_speed()
	_night_mode()
	_discrete_channels()
	_hdr()
	_music()
	_network()
	_letterbox()
	_trick_play()
	_next_item()
	_requests()
	_audio_pull()
	if "--films" in OS.get_cmdline_user_args():
		_films()
	print("RESULT: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _check(condition: bool, what: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("  FAIL ", what)


func _eq(got: Variant, want: Variant, what: String) -> void:
	_check(got == want, "%s: got %s, want %s" % [what, var_to_str(got), var_to_str(want)])


func _near(got: float, want: float, what: String, tolerance := 0.01) -> void:
	_check(absf(got - want) <= tolerance, "%s: got %.4f, want %.4f" % [what, got, want])


func _languages() -> void:
	print("Languages")
	var cases := {"ger": "de", "deu": "de", "German": "de", "DE": "de", "eng": "en", "fre": "fr", "fra": "fr",
			"pt-BR": "pt-br", "pt_br": "pt-br", "es-419": "es-419", "chi": "zh", "zho": "zh", "cmn": "zh", "und": "",
			"": "", "nob": "nb", "xyz": "xyz", "Spanish": "es", "iw": "he"}
	for code: String in cases:
		_eq(MediaSource.normalize_language(code), cases[code], "normalize_language(%s)" % code)
	_eq(MediaSource.language_name("ger"), "German", "language_name(ger)")
	_eq(MediaSource.language_name("pt-BR"), "Portuguese (BR)", "language_name(pt-BR)")
	_eq(MediaSource.language_name("xyz"), "xyz", "language_name(xyz)")


func _subtitle_names() -> void:
	print("Subtitle file names")
	# [video, subtitle, subtitle?, matches_video, language, forced, hearing_impaired]
	var cases := [
		["Film.mkv", "Film.en.srt", true, true, "en", false, false],
		["Film.mkv", "Film.en.hi.srt", true, true, "en", false, true],
		["Film.mkv", "Film.hi.srt", true, true, "hi", false, false],
		["Film.mkv", "Film.de.forced.srt", true, true, "de", true, false],
		["Film.mkv", "film.PT-br.SRT", true, true, "pt-br", false, false],
		["Film.mkv", "Film.English.SDH.ass", true, true, "en", false, true],
		["Film.mkv", "Film.srt", true, true, "", false, false],
		["Film.mkv", "2_English.srt", true, false, "en", false, false],
		["Film.mkv", "3_Spanish-Forced.vtt", true, false, "es", true, false],
		["Film.mkv", "Film.txt", false, true, "", false, false],
		["Night.Ferry.mkv", "Night.Ferry.srt", true, true, "", false, false],
		["Night.Ferry.mkv", "Night.Ferry.eng.srt", true, true, "en", false, false],
	]
	for c: Array in cases:
		var d: Dictionary = MediaBrowser.parse_subtitle_name(c[0], c[1])
		var got := [d["subtitle"], d["matches_video"], d["language"], d["forced"], d["hearing_impaired"]]
		_eq(got, c.slice(2), "parse_subtitle_name(%s, %s)" % [c[0], c[1]])


func _open(path: String) -> MediaSource:
	var source := MediaSource.new()
	var err := source.open(path)
	_check(err == OK, "open %s: %s" % [path, source.get_last_error()])
	return source if err == OK else null


func _metadata() -> void:
	print("Stereo, spherical and chapters")
	# file: [stereo_mode, inverted, projection, fov, bounds, yaw, chapters]
	var cases := {
		"meta_sbs_chapters.mkv": ["sbs", false, "", Vector2.ZERO, Vector4.ZERO, 0.0, 6],
		"meta_tb_inverted.mkv": ["tb", true, "", Vector2.ZERO, Vector4.ZERO, 0.0, 0],
		"meta_vr180.mkv": ["sbs", false, "equirectangular", Vector2(180, 180), Vector4(0.25, 0, 0.25, 0), 90.0, 0],
		# FFmpeg's MP4 muxer writes Apple's vexu box next to st3d/sv3d, and its reader lets vexu win: "two views" without
		# the packing, and a full-sphere projection without the yaw. A VR180 crop has no vexu form, so sv3d stays.
		"meta_360_tb.mp4": ["unspecified", false, "equirectangular", Vector2(360, 180), Vector4.ZERO, 0.0, 0],
		"meta_vr180.mp4": ["unspecified", false, "equirectangular", Vector2(180, 180), Vector4(0.25, 0, 0.25, 0), 90.0, 3],
		"meta_none.mp4": ["", false, "", Vector2.ZERO, Vector4.ZERO, 0.0, 0],
	}
	for file: String in cases:
		var want: Array = cases[file]
		var source := _open(F.path_join(file))
		if source == null:
			continue
		var v := source.get_video_info()
		print("  %s: stereo \"%s\"%s, projection \"%s\" %s, bounds %s, yaw/pitch/roll %s, %d chapters" % [file, v["stereo_mode"],
				" inverted" if v["stereo_inverted"] else "", v["projection"], v["projection_fov"], v["projection_bounds"],
				v["projection_yaw_pitch_roll"], source.get_chapters().size()])
		_eq(v["stereo_mode"], want[0], file + " stereo_mode")
		_eq(v["stereo_inverted"], want[1], file + " stereo_inverted")
		# Matroska keeps its StereoMode as a tag too; MP4 has none.
		var tag_want: String = {"sbs": "left_right", "tb": "top_bottom"}.get(want[0], "") if file.ends_with(".mkv") else ""
		if file == "meta_tb_inverted.mkv":
			tag_want = "bottom_top"
		_eq(v["stereo_mode_tag"], tag_want, file + " stereo_mode_tag")
		_eq(v["projection"], want[2], file + " projection")
		_check((v["projection_fov"] as Vector2).is_equal_approx(want[3]), "%s projection_fov %s" % [file, v["projection_fov"]])
		_check((v["projection_bounds"] as Vector4).is_equal_approx(want[4]), "%s projection_bounds %s" % [file, v["projection_bounds"]])
		_near((v["projection_yaw_pitch_roll"] as Vector3).x, want[5], file + " yaw")
		var chapters := source.get_chapters()
		_eq(chapters.size(), want[6], file + " chapters")
		_eq(source.get_info()["chapters"].size(), want[6], file + " get_info chapters")
		if chapters.size() > 0:
			var step := 30.0 / chapters.size()
			for i in chapters.size():
				_near(chapters[i]["start"], i * step, "%s chapter %d start" % [file, i], 0.05)
				_near(chapters[i]["end"], (i + 1) * step, "%s chapter %d end" % [file, i], 0.05)
				_eq(chapters[i]["title"], "Chapter %d" % (i + 1), "%s chapter %d title" % [file, i])
			_eq(source.get_chapter_at(-1.0), -1, file + " chapter_at(-1)")
			_eq(source.get_chapter_at(0.0), 0, file + " chapter_at(0)")
			_eq(source.get_chapter_at(step * 2.5), 2, file + " chapter_at(2.5 chapters)")
			_eq(source.get_chapter_at(29.0), chapters.size() - 1, file + " chapter_at(29)")
		source.close()


func _read_all_events(source: MediaSource, limit := 100) -> Array:
	var events := []
	for i in limit:
		var e := source.read_subtitle_event()
		if e.is_empty():
			break
		events.append(e)
	return events


func _track_by_name(tracks: Array, file: String) -> Dictionary:
	for t: Dictionary in tracks:
		if str(t.get("path", "")).get_file() == file:
			return t
	return {}


func _external_subtitles() -> void:
	print("Subtitle files next to the video")
	var browser := MediaBrowser.new()
	var video := F.path_join("ext/Film.Name.2019.mkv")
	var found := browser.find_subtitles(video)
	var names: Array[String] = []
	for d: Dictionary in found:
		names.append(str(d["path"]).trim_prefix(F.path_join("ext") + "/"))
		print("  found %s: language \"%s\" (%s)%s%s" % [d["name"], d["language"], d["language_name"], ", forced" if d["forced"] else "", ", SDH" if d["hearing_impaired"] else ""])
	var want_names := ["Film.Name.2019.ass", "Film.Name.2019.de.forced.srt", "Film.Name.2019.en.hi.srt", "Film.Name.2019.en.srt",
			"Film.Name.2019.fr.sdh.vtt", "Film.Name.2019.pt-BR.srt", "Subs/Film.Name.2019/3_Italian.srt"]
	var sorted_names := names.duplicate()
	sorted_names.sort()
	_eq(sorted_names, want_names, "find_subtitles(ext/Film.Name.2019.mkv)")
	var single := browser.find_subtitles(F.path_join("single/My Movie (2019).mp4"))
	var single_names := []
	for d: Dictionary in single:
		single_names.append([d["name"], d["language"], d["hearing_impaired"]])
	single_names.sort()
	_eq(single_names, [["2_English_SDH.srt", "en", true], ["english.srt", "en", false]], "find_subtitles(single/My Movie (2019).mp4)")

	var source := _open(video)
	if source == null:
		return
	var own := source.get_subtitle_tracks().size()
	for d: Dictionary in found:
		var index := source.add_external_subtitle(d["path"])
		_check(index >= own, "add_external_subtitle(%s) = %d: %s" % [d["name"], index, source.get_last_error()])
	_eq(source.get_external_subtitle_count(), found.size(), "external subtitle count")
	var bad := source.add_external_subtitle(F.path_join("single/notes.txt"))
	_eq(bad, -1, "add_external_subtitle(notes.txt)")
	_check(source.get_last_error() != "", "notes.txt sets last_error")
	_eq(source.get_state(), MediaSource.STATE_READING, "a bad subtitle file leaves the source playable")

	var tracks := source.get_subtitle_tracks()
	_eq(tracks.size(), own + found.size(), "get_subtitle_tracks() with the files")
	# file: [language, forced, hearing_impaired, codec, first text, first start, first end]
	var cases := {
		"Film.Name.2019.en.srt": ["en", false, false, "subrip", "Hello there", 1.0, 3.0],
		"Film.Name.2019.de.forced.srt": ["de", true, false, "subrip", "Grüße aus Köln", 1.0, 3.0],
		"Film.Name.2019.pt-BR.srt": ["pt-br", false, false, "subrip", "Olá, ação", 1.0, 3.0],
		"Film.Name.2019.fr.sdh.vtt": ["fr", false, true, "webvtt", "[musique] Bonjour", 1.0, 3.0],
		"Film.Name.2019.en.hi.srt": ["en", false, true, "subrip", "[door creaks] Hello", 1.0, 3.0],
		"Film.Name.2019.ass": ["", false, false, "ass", "Styled one", 1.0, 3.0],
		"3_Italian.srt": ["it", false, false, "subrip", "Ciao", 1.0, 3.0],
	}
	for file: String in cases:
		var want: Array = cases[file]
		var t := _track_by_name(tracks, file)
		if t.is_empty():
			_check(false, "track for " + file)
			continue
		_eq([t["language"], t["forced"], t["hearing_impaired"], t["codec"], t["external"], t["text"]], [want[0], want[1], want[2], want[3], true, true], file + " track")
		source.select_subtitle_track(t["index"])
		var events := _read_all_events(source)
		_eq(events.size(), 3, file + " events")
		if events.size() > 0:
			_eq(events[0]["text"], want[4], file + " first text")
			_near(events[0]["start"], want[5], file + " first start")
			_near(events[0]["end"], want[6], file + " first end")
			_eq(events[0]["serial"], source.get_serial(), file + " serial")
		if want[3] == "ass":
			_check(source.get_subtitle_header().contains("[V4+ Styles]"), file + " ASS header")
			_check(str(events[0]["ass"]).contains("{\\i1}"), file + " ASS line kept")

	# After a seek: again, from the events still showing at the target.
	var en := _track_by_name(tracks, "Film.Name.2019.en.srt")
	source.select_subtitle_track(en["index"])
	_eq(_read_all_events(source).size(), 3, "en.srt: all events at once")
	_eq(_read_all_events(source).size(), 0, "en.srt: nothing more")
	source.seek(30.0)
	var after := _read_all_events(source)
	_eq(after.size(), 1, "en.srt after seek(30): events")
	if after.size() == 1:
		_near(after[0]["start"], 60.0, "en.srt after seek(30): start")
		_eq(after[0]["serial"], source.get_serial(), "en.srt after seek(30): serial")
	source.seek(2.0)
	_eq(_read_all_events(source).size(), 3, "en.srt after seek(2): the event showing at 2 s and the rest")

	# Language picks over the file's own tracks (two English text tracks) and the files.
	var index_of := func(file: String) -> int: return int(_track_by_name(tracks, file).get("index", -2))
	var own_tracks := source.get_subtitle_tracks().slice(0, own)
	print("  own tracks: %s" % [own_tracks.map(func(t: Dictionary) -> String: return "%d %s %s%s" % [t["index"], t["language_code"], t["title"], " default" if t["default"] else ""])])
	var english_own := -1
	for t: Dictionary in own_tracks:
		if t["language_code"] == "en" and english_own < 0:
			english_own = t["index"]
	for t: Dictionary in own_tracks:
		if t["language_code"] == "en" and t["default"]:
			english_own = t["index"]
	_eq(source.pick_subtitle_track(PackedStringArray(["en"])), english_own, "pick_subtitle_track([en])")
	_eq(source.pick_subtitle_track(PackedStringArray(["eng"]), true), -1, "pick_subtitle_track([eng], forced only)")
	_eq(source.pick_subtitle_track(PackedStringArray(["de"])), index_of.call("Film.Name.2019.de.forced.srt"), "pick_subtitle_track([de])")
	_eq(source.pick_subtitle_track(PackedStringArray(["German"]), true), index_of.call("Film.Name.2019.de.forced.srt"), "pick_subtitle_track([German], forced only)")
	_eq(source.pick_subtitle_track(PackedStringArray(["xx", "pt"])), index_of.call("Film.Name.2019.pt-BR.srt"), "pick_subtitle_track([xx, pt])")
	_eq(source.pick_subtitle_track(PackedStringArray(["pt-PT"])), -1, "pick_subtitle_track([pt-PT])")
	_eq(source.pick_subtitle_track(PackedStringArray(["fra"])), index_of.call("Film.Name.2019.fr.sdh.vtt"), "pick_subtitle_track([fra])")
	_eq(source.pick_subtitle_track(PackedStringArray(["it", "en"])), index_of.call("3_Italian.srt"), "pick_subtitle_track([it, en])")
	_eq(source.pick_subtitle_track(PackedStringArray([])), -1, "pick_subtitle_track([])")
	source.close()
	_eq(source.get_external_subtitle_count(), 0, "close() drops the files")


func _run_texts(styled: Dictionary) -> Array:
	var texts := []
	for r: Dictionary in styled["runs"]:
		texts.append(r["text"])
	return texts


func _styled_subtitles() -> void:
	print("Styled text subtitles")
	# parse_ass_event() without a file: an SSA (v4) script, no header at all, commas and \h in the text.
	var ssa := "[Script Info]\nPlayResY: 480\n\n[V4 Styles]\nFormat: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, TertiaryColour, BackColour, Bold, Italic, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, AlphaLevel, Encoding\nStyle: Default,Tahoma,24,16777215,65535,0,0,-1,0,1,2,0,6,10,10,10,0,0\n"
	var d := MediaSource.parse_ass_event("0,0,Default,,0000,0000,0000,,Hi{\\1a&HFF&}gone", ssa)
	_eq(d["play_res"], Vector2i(640, 480), "SSA play_res from PlayResY only")
	_eq(d["alignment"], 8, "SSA alignment 6 (top centre) as numpad")
	_eq(_run_texts(d), ["Hi", "gone"], "SSA runs")
	if d["runs"].size() == 2:
		_eq([d["runs"][0]["font"], d["runs"][0]["size"], d["runs"][0]["bold"], d["runs"][0]["color"]], ["Tahoma", 24.0, true, Color(1, 1, 1, 1)], "SSA style")
		_near(d["runs"][1]["color"].a, 0.0, "\\1a&HFF& is transparent")
	d = MediaSource.parse_ass_event("0,0,Default,,0,0,0,,{\\a9}Left middle", ssa)
	_eq(d["alignment"], 4, "SSA \\a9 (middle left) as numpad")
	d = MediaSource.parse_ass_event("1,0,Missing,,0,0,0,,{\\i1}x{\\i0}y{\\u1\\s1}z, w{\\fnCourier\\bord4}c{\\fn\\bord}d", "")
	_eq(d["play_res"], Vector2i(384, 288), "no header: ASS default resolution")
	_eq(d["style"], "Default", "no header: style")
	_eq(_run_texts(d), ["x", "y", "z, w", "c", "d"], "runs split at changes")
	if d["runs"].size() == 5:
		_eq([d["runs"][0]["italic"], d["runs"][1]["italic"], d["runs"][2]["underline"], d["runs"][2]["strikeout"]], [true, false, true, true], "\\i, \\u, \\s")
		_eq([d["runs"][3]["font"], d["runs"][3]["outline_width"], d["runs"][4]["font"], d["runs"][4]["outline_width"]], ["Courier", 4.0, "Arial", 2.0], "\\fn, \\bord and their resets")
	d = MediaSource.parse_ass_event("2,0,Default,,0,0,0,,One, two,\\hthree\\Nfour", "")
	_eq(d["text"], "One, two, three\nfour", "commas, \\h and \\N in the text")
	_eq(d["position"], Vector2(-1, -1), "no \\pos")

	# Files: what FFmpeg makes of SubRip tags, and an ASS script, through read_subtitle_event().
	var source := _open(F.path_join("meta_none.mp4"))
	if source == null:
		return
	var srt := source.add_external_subtitle(F.path_join("styled/tags.srt"))
	var ass := source.add_external_subtitle(F.path_join("styled/tags.ass"))
	_check(srt >= 0 and ass >= 0, "add the styled files: %s" % source.get_last_error())
	source.select_subtitle_track(srt)
	var events := _read_all_events(source)
	_eq(events.size(), 3, "tags.srt events")
	if events.size() == 3:
		var s: Array = events[0]["styled"]
		_eq(s.size(), 1, "tags.srt one styled line per event")
		_eq(_run_texts(s[0]), ["Bold", " and ", "italic"], "tags.srt <b>, <i> runs")
		if s[0]["runs"].size() == 3:
			_eq([s[0]["runs"][0]["bold"], s[0]["runs"][1]["bold"], s[0]["runs"][2]["italic"]], [true, false, true], "tags.srt bold, italic")
		_eq(s[0]["alignment"], 2, "tags.srt alignment")
		var red: Dictionary = events[1]["styled"][0]
		_eq(_run_texts(red), ["Red", " plain"], "tags.srt <font color> runs")
		if red["runs"].size() == 2:
			_eq([red["runs"][0]["color"], red["runs"][1]["color"]], [Color(1, 0, 0, 1), Color(1, 1, 1, 1)], "tags.srt colour and {\\c} reset")
		_eq([events[2]["styled"][0]["alignment"], events[2]["styled"][0]["text"]], [8, "Top line"], "tags.srt {\\an8}")
	source.select_subtitle_track(ass)
	events = _read_all_events(source)
	_eq(events.size(), 3, "tags.ass events")
	if events.size() == 3:
		var sign: Dictionary = events[0]["styled"][0]
		_eq([sign["style"], sign["layer"], sign["position"], sign["alignment"], sign["play_res"], sign["margin_v"]], ["Sign", 1, Vector2(640, 100), 8, Vector2i(1280, 720), 10], "tags.ass sign line")
		if sign["runs"].size() == 1:
			var r: Dictionary = sign["runs"][0]
			_eq([r["text"], r["font"], r["size"], r["color"], r["bold"], r["outline_width"]], ["Sign text", "Verdana", 30.0, Color(1, 1, 0, 1), true, 3.0], "tags.ass Sign style run")
		var normal: Dictionary = events[1]["styled"][0]
		_eq(_run_texts(normal), ["Normal ", "bold", " back\nsecond line"], "tags.ass \\b runs and \\N")
		_eq([normal["margin_v"], normal["margin_l"]], [50, 30], "tags.ass margins")
		_check(normal["back_color"].is_equal_approx(Color(0, 0, 0, 1.0 - 128.0 / 255.0)), "tags.ass back colour: %s" % normal["back_color"])
		var big: Dictionary = events[2]["styled"][0]
		_eq(_run_texts(big), ["Red big", " reset"], "tags.ass \\r runs")
		if big["runs"].size() == 2:
			_eq([big["runs"][0]["color"], big["runs"][0]["size"], big["runs"][1]["color"], big["runs"][1]["size"]], [Color(1, 0, 0, 1), 60.0, Color(1, 1, 1, 1), 40.0], "tags.ass colour, size, \\r")
	source.close()


func _bitmap_subtitles() -> void:
	print("Bitmap subtitles (PGS, VobSub) as images")
	var cases := [
		["Animated.Feature.2.3D.2019.MULTi.1080p.Half-SBS.mkv", 1, "hdmv_pgs_subtitle", "Feature 2 PGS"],
		["Documentary.3D.Full-SBS.mkv", 0, "dvd_subtitle", "Documentary VobSub"],
		["Animated.Feature.3.3D.Half-SBS.mkv", 0, "hdmv_pgs_subtitle", "Feature 3 PGS"],
	]
	for c: Array in cases:
		var path := M.path_join(c[0])
		if not FileAccess.file_exists(path):
			print("  (skipped: no %s)" % path)
			continue
		var name: String = c[3]
		var source := _open(path)
		if source == null:
			continue
		var track: Dictionary = source.get_subtitle_tracks()[c[1]]
		_eq([track["codec"], track["bitmap"], track["bitmap_decoded"], track["text"]], [c[2], true, true, false], name + " track")
		source.select_audio_track(-1)
		source.select_subtitle_track(c[1])
		source.seek(600.0)
		var events := []
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 20000:
			var p := source.read_video_packet()
			if p.is_empty():
				OS.delay_msec(1)
			elif float(p["pts"]) > 690.0:
				break
			events.append_array(_read_all_events(source))
		var pictures := 0
		var clearing := 0
		var bad := []
		var last_start := -1.0
		for e: Dictionary in events:
			var images: Array = e.get("images", [])
			if images.is_empty():
				clearing += 1
			else:
				pictures += 1
			if e["start"] < last_start - 0.001:
				bad.append("start %.2f before %.2f" % [e["start"], last_start])
			last_start = e["start"]
			if e["canvas_size"] != Vector2i(1920, 1080):
				bad.append("canvas %s" % e["canvas_size"])
			for i: Dictionary in images:
				var rect: Rect2i = i["rect"]
				var image: Image = i["image"]
				if not Rect2i(Vector2i.ZERO, e["canvas_size"]).encloses(rect):
					bad.append("rect %s outside the canvas" % rect)
				if image == null or image.get_size() != rect.size or image.get_format() != Image.FORMAT_RGBA8:
					bad.append("image does not match rect %s" % rect)
				elif image.get_used_rect().size == Vector2i.ZERO:
					bad.append("image at %.2f has no visible pixels" % e["start"])
		print("  %s: %d events from 600 s to 690 s, %d with pictures, %d clearing" % [name, events.size(), pictures, clearing])
		_check(pictures >= 5, name + ": events with pictures (%d)" % pictures)
		_eq(bad, [], name + " events")
		_eq(source.get_stats()["subtitle_decode_errors"], 0, name + " decode errors")
		if c[2] == "hdmv_pgs_subtitle":
			# PGS: each picture is followed by an empty one that clears it.
			_check(clearing >= pictures - 1, name + ": clearing events (%d)" % clearing)
		else:
			_check(events.all(func(e: Dictionary) -> bool: return e["end"] > e["start"]), name + ": VobSub events have an end")
		source.close()


func _audio_picks() -> void:
	print("Audio language picks")
	var feature := M.path_join("Animated.Feature.2.3D.2019.MULTi.1080p.Half-SBS.mkv")
	if not FileAccess.file_exists(feature):
		print("  (skipped: no %s)" % feature)
		return
	var source := _open(feature)
	if source == null:
		return
	for t: Dictionary in source.get_audio_tracks():
		print("  audio %d: %s (%s) %s%s" % [t["index"], t["language"], t["language_code"], t["title"], " default" if t["default"] else ""])
	_eq(source.pick_audio_track(PackedStringArray(["en"])), 1, "Feature 2 pick_audio_track([en])")
	_eq(source.pick_audio_track(PackedStringArray(["French"])), 0, "Feature 2 pick_audio_track([French])")
	_eq(source.pick_audio_track(PackedStringArray(["de", "fre"])), 0, "Feature 2 pick_audio_track([de, fre])")
	_eq(source.pick_audio_track(PackedStringArray(["de"])), -1, "Feature 2 pick_audio_track([de])")
	for t: Dictionary in source.get_subtitle_tracks():
		print("  subtitle %d: %s %s forced %s, bitmap %s" % [t["index"], t["language_code"], t["title"], t["forced"], t["bitmap"]])
	_eq(source.pick_subtitle_track(PackedStringArray(["fr"]), true), 0, "Feature 2 pick_subtitle_track([fr], forced only)")
	_eq(source.pick_subtitle_track(PackedStringArray(["fr"])), 1, "Feature 2 pick_subtitle_track([fr])")
	source.close()


func _wait_queue(source: MediaSource) -> int:
	# The demuxer fills the queues to their targets and then waits (nothing consumes here).
	var last := -1
	for i in 100:
		OS.delay_msec(50)
		var n := int(source.get_stats()["video_queue"])
		if n == last and n > 0:
			return n
		last = n
	return last


func _read_ahead() -> void:
	print("Subtitle read-ahead")
	var source := _open(OS.get_environment("HOME") + "/media-tests/animated_subs.mkv")
	if source == null:
		return
	source.select_audio_track(-1)
	source.select_subtitle_track(0)
	source.seek(0.0)
	var normal := _wait_queue(source)
	var events := _read_all_events(source)
	var latest := -1.0
	for e: Dictionary in events:
		latest = maxf(latest, e["start"])
	print("  read-ahead 0: video queue %d packets, %d events, latest at %.1f s" % [normal, events.size(), latest])
	source.subtitle_read_ahead = 12.0
	var deep := _wait_queue(source)
	events = _read_all_events(source)
	for e: Dictionary in events:
		latest = maxf(latest, e["start"])
	print("  read-ahead 12: video queue %d packets, %d more events, latest at %.1f s" % [deep, events.size(), latest])
	var fps: float = source.get_video_info()["fps"]
	_check(normal <= int(fps * 1.5), "read-ahead 0: about 1 s queued (%d packets)" % normal)
	# The file's cues are 5 s apart from about 4 s on: with 1 s read ahead none has come, with 12 s at least two.
	_check(deep >= int(fps * 12.0), "read-ahead 12: at least 12 s queued (%d packets)" % deep)
	_check(latest >= 9.0, "read-ahead 12: events at least 9 s ahead (latest %.1f)" % latest)
	source.select_subtitle_track(-1)
	source.close()


func _bitrate() -> void:
	print("Video bitrate history")
	var source := _open(OS.get_environment("HOME") + "/media-tests/animated_subs.mkv")
	if source == null:
		return
	source.select_audio_track(-1)
	source.seek(0.0)
	# Pull the video as a decoder would, and add up the packet sizes per second of PTS.
	var bytes := {}
	var serial := source.get_serial()
	var last_pts := 0.0
	for i in 5000:
		var p := source.read_video_packet()
		if p.is_empty():
			OS.delay_msec(2)
			continue
		if int(p["serial"]) != serial:
			continue
		var second := int(floor(float(p["pts"])))
		bytes[second] = int(bytes.get(second, 0)) + (p["data"] as PackedByteArray).size()
		last_pts = p["pts"]
		if last_pts > 13.0:
			break
	var history := source.get_video_bitrate_history(10, 11.0)
	_eq(history.size(), 10, "history size")
	var worst := 0.0
	for i in history.size():
		var second := 1 + i
		var want := int(bytes.get(second, 0)) * 8 / 1000.0
		worst = maxf(worst, absf(history[i] - want))
	print("  seconds 1-10: %s kbit/s (largest difference from the packets pulled: %.3f)" % [Array(history).map(func(v: float) -> int: return int(v)), worst])
	_check(worst < 0.01, "history matches the packet sizes per second")
	# get_stats()["bitrate_bps"]: the last 3 known seconds before the playback position (the last video packet taken).
	var stats_bps: int = source.get_stats().get("bitrate_bps", -1)
	var position := source.get_position()
	# The history is checked against the packets above; the last second the test pulled is incomplete (B-frames come
	# later in decode order), so compare with the history of the same 3 seconds.
	var recent := source.get_video_bitrate_history(3, position)
	var want_bps := (recent[0] + recent[1] + recent[2]) * 1000.0 / 3.0
	print("  get_stats() bitrate_bps %d at %.2f s (history says %d)" % [stats_bps, position, want_bps])
	_check(absf(stats_bps - want_bps) < 1000.0, "get_stats() bitrate_bps")
	_eq(source.get_video_bitrate_history(70, 11.0).size(), 64, "history is capped at 64 s")
	# After a seek: what came before the keyframe is unknown.
	source.seek(60.0)
	OS.delay_msec(300)
	var after := source.get_video_bitrate_history(10, 61.0)
	print("  after seek(60), seconds 51-60: %s" % [Array(after).map(func(v: float) -> int: return int(v))])
	# The queue holds about 1 s from the keyframe before 60 s on (nothing consumes here).
	_eq(after[0], -1.0, "after a seek, a second before the keyframe is unknown")
	_check(Array(after.slice(5)).any(func(v: float) -> bool: return v > 0.0), "after a seek, the seconds from the keyframe on are known")
	source.close()


func _overlay_stats() -> void:
	print("Overlay stats")
	# A fake sysfs tree (WSL has no GPU devfreq, thermal zones or battery). The paths are looked up once per process, so
	# this is the first call.
	var root := "/tmp/features-sysfs"
	var files := {
		"sys/class/devfreq/3d00000.gpu/cur_freq": "587000000",
		"sys/class/devfreq/3d00000.gpu/max_freq": "1100000000",
		"sys/class/devfreq/soc:qcom,cpu-llcc/cur_freq": "1",
		"sys/class/thermal/thermal_zone0/type": "cpu-0-0",
		"sys/class/thermal/thermal_zone0/temp": "48500",
		"sys/class/thermal/thermal_zone1/type": "gpuss-0",
		"sys/class/thermal/thermal_zone1/temp": "51200",
		"sys/class/thermal/thermal_zone2/type": "skin-msm-therm",
		"sys/class/thermal/thermal_zone2/temp": "36000",
		"sys/class/power_supply/usb/type": "USB",
		"sys/class/power_supply/battery/type": "Battery",
		"sys/class/power_supply/battery/current_now": "-1500000",
		"sys/class/power_supply/battery/voltage_now": "4000000",
		"sys/class/power_supply/battery/capacity": "83",
		"sys/class/power_supply/battery/status": "Discharging",
	}
	for f: String in files:
		DirAccess.make_dir_recursive_absolute(root.path_join(f).get_base_dir())
		var out := FileAccess.open(root.path_join(f), FileAccess.WRITE)
		out.store_string(files[f] + "\n")
		out.close()
	OS.set_environment("HWVIDEO_SYSFS_ROOT", root)
	var system := HWVideoTexture.get_system_stats()
	print("  system (fake tree): %s" % system)
	_near(system.get("gpu_mhz", 0.0), 587.0, "gpu_mhz")
	_near(system.get("gpu_max_mhz", 0.0), 1100.0, "gpu_max_mhz")
	_near(system.get("cpu_temperature_c", 0.0), 48.5, "cpu_temperature_c")
	_near(system.get("gpu_temperature_c", 0.0), 51.2, "gpu_temperature_c")
	_near(system.get("temperature_max_c", 0.0), 51.2, "temperature_max_c")
	_eq(system.get("temperature_max_zone", ""), "gpuss-0", "temperature_max_zone")
	_near(system.get("battery_power_w", 0.0), 6.0, "battery_power_w (current times voltage)")
	_eq(system.get("battery_percent", -1), 83, "battery_percent")
	_eq(system.get("battery_status", ""), "Discharging", "battery_status")
	# The software path (10-bit HEVC at 720p): no frames are shown here (no update()), but every number is there.
	var file := M.path_join("Feature.720p.10bit.mkv")
	if not FileAccess.file_exists(file):
		print("  (skipped: no %s)" % file)
		return
	var source := _open(file)
	if source == null:
		return
	var texture := HWVideoTexture.new()
	_eq(texture.open_source(source), OK, "open_source (software)")
	OS.delay_msec(500)
	var first := texture.get_overlay_stats()
	OS.delay_msec(500)
	var d := texture.get_overlay_stats()
	var shown := d.duplicate()
	shown.erase("video_kbps_history")
	print("  %s" % shown)
	for key in ["decode_path", "position", "codec", "video_size", "fps", "video_kbps", "file_kbps", "demux_video_queue",
			"demux_video_queue_seconds", "demux_video_queue_mb", "audio_buffered_seconds", "frames_ready", "frames_shown",
			"frames_dropped", "decoder_input_queue", "process_cpu_percent", "decode_fps", "shown_fps", "interval_seconds"]:
		_check(d.has(key), "overlay stats has " + key)
	_check(not first.has("process_cpu_percent"), "the first call has no rates yet")
	_eq(d["decode_path"], "software", "overlay decode_path")
	_eq((d["video_kbps_history"] as PackedFloat32Array).size(), 60, "overlay history size")
	_near(d["interval_seconds"], 0.5, "overlay interval", 0.1)
	_check(float(d["process_cpu_percent"]) > 0.0, "overlay CPU %% while software decoding (%.0f)" % d["process_cpu_percent"])
	texture.close()
	source.close()


# Power of one frequency in frames [from, from + count) (Goertzel).
func _goertzel(frames: PackedVector2Array, from: int, count: int, frequency: float, rate: float) -> float:
	var k := 2.0 * cos(TAU * frequency / rate)
	var s1 := 0.0
	var s2 := 0.0
	for i in range(from, from + count):
		var s0 := frames[i].x + k * s1 - s2
		s2 = s1
		s1 = s0
	return s1 * s1 + s2 * s2 - k * s1 * s2


# The step of tone_steps.avi (0-19) whose tone is loudest in frames [from, from + count).
func _tone_step(frames: PackedVector2Array, from: int, count: int, rate: float) -> int:
	var best := -1
	var best_power := 0.0
	for step in 20:
		var power := _goertzel(frames, from, count, 300.0 + 25.0 * step, rate)
		if power > best_power:
			best_power = power
			best = step
	return best


# Mixes p_seconds of output into frames; returns the microseconds spent in mix_audio() (the mixer's own cost).
func _mix_seconds(source: MediaSource, playback: AudioStreamPlayback, seconds: float, frames: PackedVector2Array) -> int:
	var rate := source.get_output_rate()
	var total := int(seconds * rate)
	var mixed := 0
	var usec := 0
	while mixed < total:
		for wait in 1000:
			var stats := source.get_stats()
			if float(stats["audio_buffered"]) > 0.3 or bool(stats["audio_finished"]):
				break
			OS.delay_msec(1)
		var before := Time.get_ticks_usec()
		var chunk := playback.mix_audio(1.0, mini(512, total - mixed))
		usec += Time.get_ticks_usec() - before
		frames.append_array(chunk)
		mixed += chunk.size()
	return usec


func _playback_speed() -> void:
	print("Playback speed with the pitch kept")
	var source := _open(F.path_join("tone_steps.avi"))
	if source == null:
		return
	var playback := source.get_audio_stream().instantiate_playback()
	playback.start(0.0)
	var rate := float(source.get_output_rate())
	for speed: float in [1.0, 1.5, 0.75, 2.0]:
		source.seek(1.0)
		source.playback_speed = speed
		var frames := PackedVector2Array()
		var underruns_before := int(source.get_stats()["audio_underruns"])
		var mix_usec := _mix_seconds(source, playback, 6.0, frames)
		var position := source.get_audio_position()
		var steps := []
		var wrong := 0
		for t in range(1, 12):
			var out_time := t * 0.5 + 0.12
			var input_time := 1.0 + speed * out_time
			if fposmod(input_time, 1.0) < 0.15 or fposmod(input_time, 1.0) > 0.85:
				continue # Near a tone change.
			var got := _tone_step(frames, int(out_time * rate) - 2205, 4410, rate)
			steps.append(got)
			if got != int(floor(input_time)):
				wrong += 1
		print("  speed %.2f: after 6 s of output the audio clock is at %.3f s (want %.3f); tone steps heard %s; mixing took %.2f ms per second of output" % [speed, position, 1.0 + 6.0 * speed, steps, mix_usec / 6000.0])
		_near(position, 1.0 + 6.0 * speed, "speed %.2f: audio clock" % speed, 0.03)
		_eq(wrong, 0, "speed %.2f: the tone heard is the one at the input position, at its own pitch" % speed)
		_eq(int(source.get_stats()["audio_underruns"]) - underruns_before, 0, "speed %.2f: no underruns" % speed)
	# Changing the speed while playing: the clock goes on from where it was.
	source.seek(2.0)
	source.playback_speed = 1.5
	var frames := PackedVector2Array()
	_mix_seconds(source, playback, 2.0, frames)
	source.playback_speed = 1.0
	_mix_seconds(source, playback, 2.0, frames)
	print("  1.5 for 2 s, then 1.0 for 2 s from 2 s: clock %.3f (want 7.0)" % source.get_audio_position())
	_near(source.get_audio_position(), 7.0, "speed change mid-play: audio clock", 0.03)
	_eq(_tone_step(frames, int(3.5 * rate) - 2205, 4410, rate), 6, "speed change mid-play: tone at 3.5 s of output")
	playback.stop()
	source.close()


# RMS level in dBFS of the left channel of frames [from, from + count).
func _rms_db(frames: PackedVector2Array, from: int, count: int) -> float:
	var sum := 0.0
	for i in range(from, from + count):
		sum += frames[i].x * frames[i].x
	return 10.0 * log(sum / count + 1e-12) / log(10.0)


func _peak(frames: PackedVector2Array, from: int, count: int) -> float:
	var peak := 0.0
	for i in range(from, from + count):
		peak = maxf(peak, maxf(absf(frames[i].x), absf(frames[i].y)))
	return peak


func _night_mode() -> void:
	print("Night mode and dialogue boost")
	var source := _open(F.path_join("dyn_steps.avi"))
	if source == null:
		return
	var playback := source.get_audio_stream().instantiate_playback()
	playback.start(0.0)
	var rate := source.get_output_rate()
	var half := rate / 2
	# 2 s at -6 dBFS and 2 s at -36 dBFS in turn: compare the middle half second of loud and quiet sections.
	var spread := func(frames: PackedVector2Array, loud_at: float, quiet_at: float) -> Array:
		var loud := _rms_db(frames, int(loud_at * rate) - half / 2, half)
		var quiet := _rms_db(frames, int(quiet_at * rate) - half / 2, half)
		return [loud, quiet]
	source.night_mode = false
	source.seek(0.0)
	var off := PackedVector2Array()
	_mix_seconds(source, playback, 20.0, off)
	var levels_off: Array = spread.call(off, 17.0, 19.0)
	source.night_mode = true
	source.seek(0.0)
	var on := PackedVector2Array()
	var usec := _mix_seconds(source, playback, 20.0, on)
	var levels_on: Array = spread.call(on, 17.0, 19.0)
	var stats := source.get_stats()
	print("  off: loud %.1f, quiet %.1f dBFS; night mode: loud %.1f, quiet %.1f dBFS, peak %.2f; gain %.1f dB, typical level %.1f dB; mixing %.2f ms per second" % [levels_off[0], levels_off[1], levels_on[0], levels_on[1],
			_peak(on, 12 * rate, 8 * rate), stats["audio_gain_db"], stats["audio_typical_level_db"], usec / 20000.0])
	_near(levels_off[0] - levels_off[1], 30.0, "night mode off: loud and quiet 30 dB apart", 0.5)
	_check(levels_on[0] - levels_on[1] < 20.0, "night mode: loud and quiet closer (%.1f dB apart)" % (levels_on[0] - levels_on[1]))
	_check(levels_on[0] < levels_off[0] - 6.0, "night mode: loud part at least 6 dB down")
	_check(_peak(on, 12 * rate, 8 * rate) <= db_to_linear(-1.0) + 0.002, "night mode: no peak above -1 dBFS")
	_eq([stats["night_mode"], stats["night_mode_decoder_drc"], stats["dialogue_boost_applies"]], [true, false, false], "stats on dyn_steps.avi")
	# Switched on while playing: in effect for the loud section from 8 s.
	source.night_mode = false
	source.seek(0.0)
	var live := PackedVector2Array()
	_mix_seconds(source, playback, 4.5, live)
	source.night_mode = true
	_mix_seconds(source, playback, 4.5, live)
	var first := _rms_db(live, int(0.75 * rate), half)
	var later := _rms_db(live, int(8.25 * rate), half)
	print("  switched on at 4.5 s: loud section at 1 s %.1f dBFS, at 8.5 s %.1f dBFS" % [first, later])
	_check(later < first - 6.0, "night mode switched on while playing")
	source.night_mode = false
	playback.stop()
	source.close()

	# Dialogue boost: the centre's 1 kHz against the fronts' 500 Hz in the left output channel.
	source = _open(F.path_join("centre_51.avi"))
	if source == null:
		return
	playback = source.get_audio_stream().instantiate_playback()
	playback.start(0.0)
	var ratios := []
	for boost: float in [0.0, 6.0, 12.0]:
		source.dialogue_boost = boost
		source.seek(0.0)
		var frames := PackedVector2Array()
		_mix_seconds(source, playback, 3.0, frames)
		var centre := _goertzel(frames, rate, rate, 1000.0, rate)
		var fronts := _goertzel(frames, rate, rate, 500.0, rate)
		ratios.append(10.0 * log(centre / fronts) / log(10.0))
	print("  centre against fronts at boost 0, 6, 12 dB: %.2f, %.2f, %.2f dB" % ratios)
	_near(ratios[0], -3.0, "dialogue boost 0: centre at -3 dB in the downmix", 0.2)
	_near(ratios[1] - ratios[0], 6.0, "dialogue boost 6 dB", 0.2)
	_near(ratios[2] - ratios[0], 12.0, "dialogue boost 12 dB", 0.2)
	_eq(source.get_stats()["dialogue_boost_applies"], true, "dialogue_boost_applies on 5.1")
	_eq(source.dialogue_boost, 12.0, "dialogue_boost property")
	source.dialogue_boost = 20.0
	_eq(source.dialogue_boost, 12.0, "dialogue_boost clamped to 12 dB")
	playback.stop()
	source.close()

	# FFmpeg's AC-3 decoder forgets its options when flushed (every seek): MediaSource sets them again.
	var ac3 := M.path_join("Feature.AC3.mp4")
	if not FileAccess.file_exists(ac3):
		print("  (skipped: no %s)" % ac3)
		return
	var level := []
	for options: Dictionary in [{}, {"target_level": "-10"}]:
		source = MediaSource.new()
		source.audio_decoder_options = options
		if source.open(ac3) != OK:
			_check(false, "open " + ac3)
			return
		playback = source.get_audio_stream().instantiate_playback()
		playback.start(0.0)
		source.seek(600.0)
		var frames := PackedVector2Array()
		_mix_seconds(source, playback, 5.0, frames)
		level.append(_rms_db(frames, 0, frames.size()))
		_eq(source.get_stats()["night_mode_decoder_drc"], true, "AC-3: night_mode_decoder_drc")
		playback.stop()
		source.close()
	print("  AC-3 after a seek: %.1f dBFS, with target_level -10: %.1f dBFS" % level)
	_check(level[1] > level[0] + 10.0, "AC-3 decoder options kept after a seek")


# Mix steps as the audio server does them: each playback in turn mixes 512 frames, once per step.
func _mix_steps(source: MediaSource, playbacks: Array, steps: int, outputs: Array) -> void:
	for step in steps:
		for wait in 1000:
			var stats := source.get_stats()
			if float(stats["audio_buffered"]) > 0.3 or bool(stats["audio_finished"]):
				break
			OS.delay_msec(1)
		for i in playbacks.size():
			outputs[i].append_array(playbacks[i].mix_audio(1.0, 512))


# How pure a tone is: its Goertzel power against that of a full-scale-normalised sine of the same RMS (1: pure).
func _purity(frames: PackedVector2Array, from: int, count: int, frequency: float, rate: float) -> float:
	var sum := 0.0
	for i in range(from, from + count):
		sum += frames[i].x * frames[i].x
	var amplitude := sqrt(2.0 * sum / count)
	var expected := pow(amplitude * count / 2.0, 2.0)
	return _goertzel(frames, from, count, frequency, rate) / expected if expected > 0.0 else 0.0


func _discrete_channels() -> void:
	print("Discrete channels")
	var path := F.path_join("channels_51.avi")
	var source := MediaSource.new()
	source.discrete_channels = true
	if source.open(path) != OK:
		_check(false, "open channels_51.avi: " + source.get_last_error())
		return
	var rate := float(source.get_output_rate())
	# A WAVE header without a channel mask is FFmpeg's "5.1": FL FR FC LFE BL BR.
	var tones := [300.0, 400.0, 500.0, 60.0, 700.0, 800.0, 0.0, 0.0] # FL FR FC LFE BL BR SL SR; 0: absent.
	var playbacks := [source.get_audio_stream().instantiate_playback()]
	for i in 8:
		playbacks.append(source.get_audio_channel_stream(i).instantiate_playback())
	for p: AudioStreamPlayback in playbacks:
		p.start(0.0)
	source.seek(0.0)
	var outs := []
	for i in 9:
		outs.append(PackedVector2Array())
	var steps := int(2.0 * rate / 512)
	_mix_steps(source, playbacks, steps, outs)
	var present := []
	for c: Dictionary in source.get_audio_channels():
		present.append(c["present"])
	_eq(present, [true, true, true, true, true, true, false, false], "get_audio_channels() present on 5.1")
	_near(source.get_audio_position(), steps * 512 / rate, "clock with the stereo and 8 channel streams", 512 / rate + 0.001)
	var from := int(0.5 * rate)
	var count := int(rate)
	var levels := []
	for i in 8:
		var frames: PackedVector2Array = outs[1 + i]
		var level := _rms_db(frames, from, count)
		levels.append(snappedf(level, 0.1))
		var same := true
		for j in range(from, from + count, 97):
			if frames[j].x != frames[j].y:
				same = false
		_check(same, "channel %d: mono (left = right)" % i)
		if tones[i] > 0.0:
			_near(level, -23.0, "channel %d: its tone at -20 dBFS peak" % i, 0.3)
			_check(_purity(frames, from, count, tones[i], rate) > 0.95, "channel %d: only its own tone (%.3f)" % [i, _purity(frames, from, count, tones[i], rate)])
		else:
			_check(level < -100.0, "channel %d: silent (%.1f dBFS)" % [i, level])
	print("  channel levels (dBFS RMS): %s" % [levels])
	# The stereo mix is the downmix of the same frames: L = FL + 0.707 FC + 0.707 BL.
	var worst := 0.0
	var stereo: PackedVector2Array = outs[0]
	for j in range(from, from + count):
		var l: float = outs[1][j].x + 0.70710678 * (outs[3][j].x + outs[5][j].x)
		var r: float = outs[2][j].x + 0.70710678 * (outs[3][j].x + outs[6][j].x)
		worst = maxf(worst, maxf(absf(stereo[j].x - l), absf(stereo[j].y - r)))
	_check(worst < 1e-5, "stereo = downmix of the channel streams, frame for frame (worst %s)" % worst)

	# Channel streams alone: they share the steps and move the clock.
	var alone := []
	for i in 8:
		alone.append(PackedVector2Array())
	var before := source.get_audio_position()
	_mix_steps(source, playbacks.slice(1), int(rate / 512), alone)
	_near(source.get_audio_position() - before, int(rate / 512) * 512 / rate, "clock with channel streams only", 0.001)
	_check(_purity(alone[2], 0, alone[2].size(), 500.0, rate) > 0.95, "FC alone: continuous (%.3f)" % _purity(alone[2], 0, alone[2].size(), 500.0, rate))

	# Dialogue boost raises the centre channel itself.
	source.dialogue_boost = 6.0
	source.seek(0.0)
	outs = []
	for i in 9:
		outs.append(PackedVector2Array())
	_mix_steps(source, playbacks, steps, outs)
	_near(_rms_db(outs[3], from, count), -17.0, "dialogue boost 6 dB on the FC stream", 0.3)
	_near(_rms_db(outs[1], from, count), -23.0, "dialogue boost leaves FL", 0.3)
	source.dialogue_boost = 0.0

	# Night mode: the channels get the gain the stereo mix got (the mix is still their downmix, frame for frame).
	source.night_mode = true
	source.seek(0.0)
	outs = []
	for i in 9:
		outs.append(PackedVector2Array())
	_mix_steps(source, playbacks, steps, outs)
	worst = 0.0
	for j in range(from, from + count):
		var l: float = outs[1][j].x + 0.70710678 * (outs[3][j].x + outs[5][j].x)
		var r: float = outs[2][j].x + 0.70710678 * (outs[3][j].x + outs[6][j].x)
		worst = maxf(worst, maxf(absf(outs[0][j].x - l), absf(outs[0][j].y - r)))
	print("  night mode: FL %.1f dBFS (gain %.1f dB); stereo against the channels' downmix: worst %s" % [_rms_db(outs[1], from, count), source.get_stats()["audio_gain_db"], worst])
	_check(_rms_db(outs[1], from, count) < -23.5 or _rms_db(outs[1], from, count) > -22.5, "night mode changes the channel streams' level")
	_check(worst < 1e-5, "night mode: stereo = downmix of the channel streams (worst %s)" % worst)
	source.night_mode = false

	# At another speed only the stereo mix plays; back at 1 the channels go on.
	source.playback_speed = 1.5
	source.seek(0.0)
	outs = []
	for i in 9:
		outs.append(PackedVector2Array())
	_mix_steps(source, playbacks, 40, outs)
	_check(_rms_db(outs[0], 0, outs[0].size()) > -30.0 and _rms_db(outs[3], 0, outs[3].size()) < -100.0, "speed 1.5: stereo plays, channel streams silent")
	source.playback_speed = 1.0
	outs = []
	for i in 9:
		outs.append(PackedVector2Array())
	_mix_steps(source, playbacks, 40, outs)
	_near(_rms_db(outs[3], 2048, outs[3].size() - 2048), -23.0, "back at speed 1: FC plays", 0.5)
	source.close()

	# The same file without discrete channels: the same stereo mix.
	var plain := MediaSource.new()
	plain.open(path)
	var plain_playback := plain.get_audio_stream().instantiate_playback()
	plain_playback.start(0.0)
	plain.seek(0.0)
	var plain_out := [PackedVector2Array()]
	_mix_steps(plain, [plain_playback], steps, plain_out)
	worst = 0.0
	for j in range(from, from + count):
		worst = maxf(worst, (plain_out[0][j] - stereo[j]).abs().x + (plain_out[0][j] - stereo[j]).abs().y)
	_check(worst < 1e-3, "stereo with and without discrete channels match (worst %s)" % worst)
	var lone := plain.get_audio_channel_stream(2).instantiate_playback()
	lone.start(0.0)
	_check(_rms_db(lone.mix_audio(1.0, 512), 0, 512) < -100.0, "a channel stream without discrete_channels is silent")
	plain.close()


# SMPTE ST 2084, written out again here so the engine's PQ is checked against an independent copy.
func _pq_nits(e: float) -> float:
	var m1 := 2610.0 / 16384.0
	var m2 := 2523.0 / 4096.0 * 128.0
	var c1 := 3424.0 / 4096.0
	var c2 := 2413.0 / 4096.0 * 32.0
	var c3 := 2392.0 / 4096.0 * 32.0
	var p := pow(e, 1.0 / m2)
	return 10000.0 * pow(maxf(p - c1, 0.0) / (c2 - c3 * p), 1.0 / m1)


func _pq_code(nits: float) -> float:
	var m1 := 2610.0 / 16384.0
	var m2 := 2523.0 / 4096.0 * 128.0
	var y := pow(nits / 10000.0, m1)
	return pow((3424.0 / 4096.0 + 2413.0 / 4096.0 * 32.0 * y) / (1.0 + 2392.0 / 4096.0 * 32.0 * y), m2)


func _hdr() -> void:
	print("HDR metadata and tone mapping")
	var hdr10 := {"color_transfer": "smpte2084", "color_primaries": "bt2020", "max_cll": 1000, "mastering_display_luminance": Vector2(0.005, 1000.0)}
	var tm := MediaSource.get_tone_mapping(hdr10, 203.0)
	# BT.2020 to BT.709 (ITU-R BT.2087), column by column.
	var m: Basis = tm["gamut_matrix"]
	var want := [Vector3(1.6605, -0.1246, -0.0182), Vector3(-0.5876, 1.1329, -0.1006), Vector3(-0.0728, -0.0083, 1.1187)]
	var units: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	for i in 3:
		var column: Vector3 = m * units[i]
		_check((column - want[i]).length() < 0.001, "BT.2020 to BT.709 column %d: %s" % [i, column])
	var p3: Basis = MediaSource.get_tone_mapping({"color_transfer": "smpte2084", "color_primaries": "smpte432"})["gamut_matrix"]
	_check((p3 * Vector3.RIGHT - Vector3(1.2249, -0.0420, -0.0197)).length() < 0.001, "P3 to BT.709 first column: %s" % (p3 * Vector3.RIGHT))
	_eq([tm["transfer"], tm["tone_mapping"], tm["source_peak_nits"], tm["target_peak_nits"]], ["pq", true, 1000.0, 203.0], "tone mapping basics")
	_near(tm["source_max_pq"], 0.7518, "PQ of 1000 nits", 0.0005)
	_near(_pq_code(203.0), 0.5806, "PQ of 203 nits (test's own PQ)", 0.0005)
	# Neutral greys: below the knee unchanged (nits / target), the source peak to 1.0, and rising all the way.
	var low := _pq_code(10.0)
	_near(MediaSource.tone_map_color(Color(low, low, low), tm).r, 10.0 / 203.0, "10 nits grey unchanged", 0.0005)
	var top := _pq_code(1000.0)
	_near(MediaSource.tone_map_color(Color(top, top, top), tm).g, 1.0, "the source peak to the target peak", 0.002)
	var last := -1.0
	var rising := true
	for i in 101:
		var v := MediaSource.tone_map_color(Color(i / 100.0, i / 100.0, i / 100.0), tm).b
		rising = rising and v >= last - 1e-5 # Flat at 1.0 above the source peak, give or take float noise.
		last = v
	_check(rising, "tone mapping rises with the input")
	# A colour keeps its hue: the channels keep their linear ratios through the EETF (BT.709 primaries: no matrix).
	var bright := Color(_pq_code(900.0), _pq_code(450.0), _pq_code(90.0))
	var mapped := MediaSource.tone_map_color(bright, MediaSource.get_tone_mapping({"color_transfer": "smpte2084", "color_primaries": "bt709", "max_cll": 1000}, 203.0))
	_near(mapped.g / mapped.r, 0.5, "hue kept: green / red", 0.002)
	_near(mapped.b / mapped.r, 0.1, "hue kept: blue / red", 0.002)
	_check(mapped.r < 1.0 and mapped.r > 0.7, "900 nits red compressed below the target peak (%.3f)" % mapped.r)
	# Fits the target: nothing to compress.
	var fits := MediaSource.get_tone_mapping({"color_transfer": "smpte2084", "color_primaries": "bt709", "max_cll": 150}, 203.0)
	_eq(fits["tone_mapping"], false, "MaxCLL 150 on a 203 nit target: no compression")
	_near(MediaSource.tone_map_color(Color(_pq_code(150.0), 0, 0), fits).r, 150.0 / 203.0, "150 nits to 150 / 203", 0.002)
	# HLG: signal 0.5 is scene light 1/12, shown at 1000 * (1/12)^1.2 nits on a 1000 nit display; below the knee.
	var hlg := MediaSource.get_tone_mapping({"color_transfer": "arib-std-b67", "color_primaries": "bt709"}, 203.0)
	_near(MediaSource.tone_map_color(Color(0.5, 0.5, 0.5), hlg).r, 1000.0 * pow(1.0 / 12.0, 1.2) / 203.0, "HLG 0.5 grey", 0.002)
	# SDR passes: BT.1886, white to 1.0.
	var sdr := MediaSource.get_tone_mapping({"color_transfer": "bt709", "color_primaries": "bt709"}, 203.0)
	_eq([sdr["transfer"], sdr["tone_mapping"], sdr["primaries_bt709"]], ["sdr", false, true], "SDR tone mapping")
	_near(MediaSource.tone_map_color(Color(1, 1, 1), sdr).r, 1.0, "SDR white", 0.0001)
	_near(_pq_nits(0.5806), 203.0, "test's own PQ round trip", 0.5)

	# Films: what FFmpeg's HEVC decoder reports on the first frame (scratch tool hdrprobe.c), from the container or SEI.
	var p3_display := PackedVector2Array([Vector2(0.68, 0.32), Vector2(0.265, 0.69), Vector2(0.15, 0.06), Vector2(0.3127, 0.329)])
	var films := [
		["HDR.A.1080p.mkv", "sei", Vector2(0.005, 1000), 0, 0, -1, p3_display],
		["HDR.B.1080p.mkv", "sei", Vector2(0, 1000), 482, 224, -1, p3_display],
		["HDR.C.2160p.mkv", "sei", Vector2(0.005, 1000), 989, 135, -1, p3_display],
		["HDR.DV.1080p.mkv", "container", Vector2(0.005, 4000), 3471, 99, 8, p3_display],
		["HDR.D.2160p.mkv", "sei", Vector2(0.0001, 1000), 0, 0, -1,
				PackedVector2Array([Vector2(0.708, 0.292), Vector2(0.17, 0.797), Vector2(0.131, 0.046), Vector2(0.3127, 0.329)])],
	]
	for f: Array in films:
		var path := M.path_join(f[0])
		if not FileAccess.file_exists(path):
			print("  (skipped: no %s)" % path)
			continue
		var t0 := Time.get_ticks_msec()
		var source := _open(path)
		if source == null:
			continue
		var open_ms := Time.get_ticks_msec() - t0
		var v := source.get_video_info()
		var name: String = f[0].get_slice(".", 0) + "." + f[0].get_slice(".", 1)
		var primaries: PackedVector2Array = v["mastering_display_primaries"]
		var close_enough := primaries.size() == 4
		for i in mini(primaries.size(), 4):
			close_enough = close_enough and (primaries[i] - f[6][i]).length() < 0.0001
		var luminance: Vector2 = v["mastering_display_luminance"]
		var t := MediaSource.get_tone_mapping(v)
		print("  %s: %s, %s, mastering %s nits, MaxCLL %d, MaxFALL %d, Dolby Vision %d, source %s; tone mapping from %.0f nits; open %d ms" % [name, v["hdr_transfer"], v["color_primaries"],
				luminance, v["max_cll"], v["max_fall"], v["dolby_vision_profile"], v["hdr_metadata_source"], t["source_peak_nits"], open_ms])
		_eq([v["hdr_transfer"], v["hdr_metadata_source"], v["max_cll"], v["max_fall"], v["dolby_vision_profile"]], ["pq", f[1], f[3], f[4], f[5]], name + " HDR metadata")
		_check(close_enough, name + " mastering primaries: %s" % primaries)
		_check((luminance - f[2]).length() < 0.001, name + " mastering luminance: %s" % luminance)
		source.close()


func _music() -> void:
	print("Audio-only files: tags, cover art, playback")
	var cases := [
		# [file, tags wanted, pictures, a tone step to check after seek(5) (-1: not the tone file)]
		["aac_cover.m4a", {"title": "Test Song", "artist": "Test Artist", "album": "Test Album", "track": "3"}, 1, -1],
		["tone_steps.flac", {"title": "Tone Steps", "artist": "Make Feature Files"}, 1, 5],
		["tone_steps.wav", {}, 0, 5],
		["clip.ac3", {}, 0, -1],
	]
	for c: Array in cases:
		var path := F.path_join("music").path_join(c[0])
		if not FileAccess.file_exists(path):
			print("  (skipped: no %s)" % path)
			continue
		var source := _open(path)
		if source == null:
			continue
		var tags := source.get_tags()
		var wanted: Dictionary = c[1]
		var got := {}
		for key in wanted:
			got[key] = tags.get(key, "")
		_eq(got, wanted, c[0] + " tags")
		_eq(source.get_video_info(), {}, c[0] + ": no video")
		var pictures := source.get_attached_pictures()
		_eq(pictures.size(), c[2], c[0] + " attached pictures")
		_eq(int(source.get_info()["attached_pictures"]), c[2], c[0] + " get_info() attached_pictures")
		if c[2] > 0:
			var art := source.get_album_art()
			_check(art != null and art.get_size() == Vector2i(64, 64), c[0] + " album art 64x64")
			if art != null:
				# The cover's pixel (x, y) is (4x, 4y, 160).
				var px := art.get_pixel(10, 20)
				_check(absf(px.r8 - 40) <= 1 and absf(px.g8 - 80) <= 1 and absf(px.b8 - 160) <= 1, c[0] + " album art pixel: %s" % px)
			_eq(pictures[0]["codec"], "png", c[0] + " picture codec")
		var playback := source.get_audio_stream().instantiate_playback()
		playback.start(0.0)
		var frames := PackedVector2Array()
		_mix_seconds(source, playback, 2.0, frames)
		var level := _rms_db(frames, 0, frames.size())
		_check(level > -45.0, c[0] + " plays (%.1f dBFS)" % level)
		_near(source.get_audio_position(), 2.0, c[0] + " clock after 2 s", 0.05)
		source.seek(5.0)
		frames = PackedVector2Array()
		_mix_seconds(source, playback, 1.0, frames)
		_near(source.get_audio_position(), 6.0, c[0] + " clock after seek(5) and 1 s", 0.05)
		if c[3] >= 0:
			var rate := float(source.get_output_rate())
			_eq(_tone_step(frames, int(0.5 * rate) - 2205, 4410, rate), c[3], c[0] + " tone after seek(5)")
		print("  %s: %s, %d picture(s), %.1f dBFS, tags %s" % [c[0], source.get_info()["format"], pictures.size(), level, tags])
		playback.stop()
		source.close()
	# A film has no pictures (and its video is not mistaken for one).
	var film := _open(F.path_join("meta_none.mp4"))
	if film:
		_eq([film.get_attached_pictures().size(), film.get_video_info().get("codec", "")], [0, "h264"], "meta_none.mp4: no pictures, h264 video")
		_eq(film.get_album_art(), null, "meta_none.mp4: no album art")
		film.close()


# Video packets from the source for up to wall_seconds of real time, or until the media time has moved media_seconds
# from the first one. Mixes the audio along (live sources don't wait). Returns [count, first pts, last pts, keyframe first].
func _read_for(source: MediaSource, media_seconds: float, wall_seconds: float, playback: AudioStreamPlayback = null) -> Array:
	var count := 0
	var first := -1.0
	var last := -1.0
	var keyframe_first := false
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < wall_seconds * 1000.0:
		var p := source.read_video_packet()
		if p.is_empty():
			if playback:
				playback.mix_audio(1.0, 256)
			OS.delay_msec(2)
			continue
		if int(p["serial"]) != source.get_serial():
			continue # Read before the last seek.
		if first < 0.0:
			first = p["pts"]
			keyframe_first = p["keyframe"]
		last = p["pts"]
		count += 1
		if last - first >= media_seconds:
			break
	return [count, first, last, keyframe_first]


func _network() -> void:
	print("Network input: HTTP, HTTPS, live HTTP, UDP")
	var root := OS.get_environment("HOME").path_join("media-tests")
	var script := ProjectSettings.globalize_path("res://tools/stream_server.py")
	var cert := F.path_join("test-cert.pem")
	var pids := [OS.create_process("python3", [script, "serve", root, "8701"])]
	var https := FileAccess.file_exists(cert)
	if https:
		pids.append(OS.create_process("python3", [script, "serve", root, "8702", cert, F.path_join("test-key.pem")]))
	OS.delay_msec(1000)
	var web := "http://127.0.0.1:8701/"

	# A file over HTTP: seekable through Range requests, the same packets as the local file.
	var local := _open(F.path_join("meta_none.mp4"))
	var local_read := _read_for(local, 5.0, 10.0) if local else [0, 0.0, 0.0, false]
	# The same seek on the file: this one has keyframes at 10.4 s and 20.8 s.
	var local_seek := [0, 0.0, 0.0, false]
	if local:
		local.seek(20.0)
		local_seek = _read_for(local, 0.5, 10.0)
		local.close()
	var http := MediaSource.new()
	var err := http.open(web + "features/meta_none.mp4")
	_eq(err, OK, "HTTP open: %s" % http.get_last_error())
	if err == OK:
		_eq([http.is_live(), http.is_seekable(), http.get_info()["live"]], [false, true, false], "HTTP mp4: seekable, not live")
		var got := _read_for(http, 5.0, 10.0)
		_eq(got.slice(0, 3), local_read.slice(0, 3), "HTTP mp4: the first 5 s of packets as from the file")
		var serial := http.seek(20.0)
		_check(serial > 0, "HTTP mp4: seek")
		var after := _read_for(http, 0.5, 10.0)
		_check(after[0] > 0 and after[3] and after[1] <= 20.01, "HTTP mp4 after seek(20): from a keyframe before 20 s (%s)" % [after])
		_eq(after.slice(0, 3), local_seek.slice(0, 3), "HTTP mp4 after seek(20): the same packets as the file")
		var playback := http.get_audio_stream().instantiate_playback()
		playback.start(0.0)
		var frames := PackedVector2Array()
		_mix_seconds(http, playback, 1.0, frames)
		_check(_rms_db(frames, 0, frames.size()) > -45.0, "HTTP mp4: audio plays")
		var stats := http.get_stats()
		print("  HTTP: %s; %d requests, %d resets, %.1f MB read" % [http.get_info()["network_description"], stats["net_requests"], stats["net_resets"], stats["net_bytes_read"] / 1e6])
		_check(int(stats["net_requests"]) >= 2, "HTTP mp4: more than one request (seeks)")
		var t := Time.get_ticks_msec()
		http.close()
		_check(Time.get_ticks_msec() - t < 500, "HTTP close() is quick (%d ms)" % (Time.get_ticks_msec() - t))

	# Redirect, missing file.
	var moved := MediaSource.new()
	_eq(moved.open(web + "redirect/features/meta_none.mp4"), OK, "HTTP redirect: %s" % moved.get_last_error())
	moved.close()
	var missing := MediaSource.new()
	_check(missing.open(web + "features/nope.mp4") != OK and missing.get_last_error().contains("404"), "HTTP 404: %s" % missing.get_last_error())

	# HTTPS with a self-signed certificate: refused unless network_tls_verify is off.
	if https:
		var strict := MediaSource.new()
		var refused := strict.open("https://127.0.0.1:8702/features/meta_none.mp4")
		_check(refused != OK and strict.get_last_error().to_lower().contains("tls"), "HTTPS, self-signed, verify on: refused (%s)" % strict.get_last_error())
		var lax := MediaSource.new()
		lax.network_tls_verify = false
		_eq(lax.open("https://127.0.0.1:8702/features/meta_none.mp4"), OK, "HTTPS, verify off: %s" % lax.get_last_error())
		if lax.is_open():
			_eq(_read_for(lax, 5.0, 10.0).slice(0, 3), local_read.slice(0, 3), "HTTPS mp4: the first 5 s of packets as from the file")
			_eq(lax.seek(20.0) > 0 and _read_for(lax, 0.5, 10.0)[0] > 0, true, "HTTPS mp4: seek and read")
			lax.close()

	# A server without Range: plays from the start, can't seek.
	var plain := MediaSource.new()
	_eq(plain.open(web + "norange/animated_90s.ts"), OK, "HTTP without Range: %s" % plain.get_last_error())
	if plain.is_open():
		_eq([plain.is_seekable(), plain.is_live()], [false, false], "HTTP without Range: not seekable, not live")
		var serial := plain.get_serial()
		_eq(plain.seek(30.0), serial, "HTTP without Range: seek() does nothing")
		_check(_read_for(plain, 3.0, 10.0)[0] > 30, "HTTP without Range: reads")
		plain.close()

	# Live HTTP (chunked MPEG-TS, paced at its bit rate): media time follows the wall clock.
	var live := MediaSource.new()
	var t_open := Time.get_ticks_msec()
	_eq(live.open(web + "live/animated_90s.ts?rate=298800"), OK, "live HTTP open: %s" % live.get_last_error())
	if live.is_open():
		var open_ms := Time.get_ticks_msec() - t_open
		_eq([live.is_live(), live.is_seekable()], [true, false], "live HTTP: live, not seekable")
		var playback := live.get_audio_stream().instantiate_playback()
		playback.start(0.0)
		var span := _read_for(live, 100.0, 4.0, playback)
		print("  live HTTP: open %d ms; in 4 s of wall time %d packets, %.2f s of media (%.2f-%.2f), keyframe first %s" % [open_ms, span[0], span[2] - span[1], span[1], span[2], span[3]])
		_check(span[2] - span[1] > 2.5 and span[2] - span[1] < 5.5, "live HTTP: about 4 s of media in 4 s (%.2f)" % (span[2] - span[1]))
		_check(span[3], "live HTTP: starts at a keyframe")
		# Not read for 4 s: the reader falls behind and skips ahead (bounded delay).
		OS.delay_msec(4000)
		var resumed := _read_for(live, 0.2, 4.0, playback)
		var stats := live.get_stats()
		print("  live HTTP after 4 s unread: skips %d, overruns %.1f MB, next packet at %.2f s" % [stats["net_skips"], stats["net_overruns"] / 1e6, resumed[1]])
		_check(int(stats["net_skips"]) >= 1, "live HTTP: skips ahead after falling behind")
		var t := Time.get_ticks_msec()
		live.close()
		_check(Time.get_ticks_msec() - t < 500, "live HTTP close() is quick (%d ms)" % (Time.get_ticks_msec() - t))

	# Live pre-roll: the audio, and so the clock, holds until live_latency of it is buffered.
	var held := MediaSource.new()
	held.live_latency = 2.0
	t_open = Time.get_ticks_msec()
	if held.open(web + "live/animated_90s.ts?rate=298800") == OK:
		var playback := held.get_audio_stream().instantiate_playback()
		playback.start(0.0)
		var position := held.get_audio_position()
		playback.mix_audio(1.0, 4096)
		_check(is_equal_approx(held.get_audio_position(), position), "live pre-roll: the clock holds right after open")
		while float(held.get_stats()["audio_buffered"]) < 2.0 and Time.get_ticks_msec() - t_open < 8000:
			OS.delay_msec(20)
		var ready_ms := Time.get_ticks_msec() - t_open
		playback.mix_audio(1.0, 4096)
		var moved_by := held.get_audio_position() - position
		print("  live pre-roll of 2 s: buffered %.2f s after %d ms; then the clock moved %.3f s" % [held.get_stats()["audio_buffered"], ready_ms, moved_by])
		_check(moved_by > 0.05, "live pre-roll: once 2 s are buffered it plays (the clock moved %.3f s for 4096 frames)" % moved_by)
		held.close()

	# UDP MPEG-TS.
	var sender := OS.create_process("python3", [script, "udp", root.path_join("animated_90s.ts"), "127.0.0.1", "8703", "298800"])
	var udp := MediaSource.new()
	udp.live_latency = 0.5
	t_open = Time.get_ticks_msec()
	_eq(udp.open("udp://@:8703"), OK, "UDP open: %s" % udp.get_last_error())
	if udp.is_open():
		var open_ms := Time.get_ticks_msec() - t_open
		_eq([udp.is_live(), udp.is_seekable()], [true, false], "UDP: live, not seekable")
		var v := udp.get_video_info()
		_eq([v.get("codec", ""), v.get("width", 0)], ["h264", 1920], "UDP: video found")
		var playback := udp.get_audio_stream().instantiate_playback()
		playback.start(0.0)
		var span := _read_for(udp, 100.0, 4.0, playback)
		var stats := udp.get_stats()
		print("  UDP: open %d ms; in 4 s %d packets, %.2f s of media; %d datagrams" % [open_ms, span[0], span[2] - span[1], stats["net_packets"]])
		_check(span[2] - span[1] > 2.5 and span[2] - span[1] < 5.5, "UDP: about 4 s of media in 4 s (%.2f)" % (span[2] - span[1]))
		_check(int(stats["net_packets"]) > 1000, "UDP: datagrams received")
		_check(int(stats["net_wakeups"]) < int(stats["net_packets"]), "UDP: datagrams taken in batches (%d wake-ups for %d)" % [stats["net_wakeups"], stats["net_packets"]])
		_check(String(udp.get_info()["network_description"]).contains("socket buffer"), "UDP: the description says the socket buffer (%s)" % udp.get_info()["network_description"])
		udp.close()
	OS.kill(sender)
	for pid in pids:
		OS.kill(pid)


# Opens with letterbox detection, reads the video (no audio) as fast as it comes until the result is final or the file
# ends, and returns get_letterbox().
func _detect_letterbox(path: String) -> Dictionary:
	var source := MediaSource.new()
	source.letterbox_detection = true
	if source.open(path) != OK:
		_check(false, "open %s: %s" % [path, source.get_last_error()])
		return {}
	source.select_audio_track(-1)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000:
		var packet := source.read_video_packet()
		if source.get_letterbox()["done"] or (source.is_eof() and packet.is_empty()):
			break
		if packet.is_empty():
			OS.delay_msec(1)
	OS.delay_msec(200) # The last keyframe offered may still be decoding.
	var result := source.get_letterbox()
	var t := Time.get_ticks_msec()
	source.close()
	_check(Time.get_ticks_msec() - t < 500, "letterbox: close() is quick")
	print("  %s: %s of %s, bars %s; %d frames with a picture at %s, %d of %d scanned dark; %.1f ms CPU" % [path.get_file(), result["rect"], result["frame_size"], result["bars"], result["frames"], result["frame_times"], result["dark"], result["scanned"], result["cpu_seconds"] * 1000.0])
	return result


func _letterbox() -> void:
	print("Letterbox detection")
	var off := _open(F.path_join("meta_none.mp4"))
	if off:
		var lb := off.get_letterbox()
		_eq([lb["enabled"], lb["known"], lb["scanned"]], [false, false, 0], "letterbox: off by default, nothing scanned")
		off.close()

	# 640x352, bars of 40 rows; black frames first, a dark scene, and a flash over the bars at 12-15 s.
	var lb := _detect_letterbox(F.path_join("letterbox/letterbox.avi"))
	if not lb.is_empty():
		_eq([lb["known"], lb["bars"], lb["rect"], lb["frame_size"]], [true, true, Rect2i(0, 40, 640, 272), Vector2i(640, 352)], "letterbox: bars of 40 rows top and bottom")
		_check(lb["uv_rect"].is_equal_approx(Rect2(0, 40.0 / 352.0, 1, 272.0 / 352.0)), "letterbox: uv_rect (%s)" % lb["uv_rect"])
		_check(absf(lb["picture_aspect"] - 640.0 / 272.0) < 0.001, "letterbox: picture aspect 2.35 (%.3f)" % lb["picture_aspect"])
		_check(int(lb["dark"]) >= 1, "letterbox: black and dark frames don't count (%d)" % lb["dark"])
		var flash := false
		for t in lb["frame_times"]:
			flash = flash or (t >= 12.0 and t < 16.0)
		if flash:
			_check(int(lb["frames"]) >= 4, "letterbox: the flash over the bars is left out (4 frames or more)")
		_check(float(lb["cpu_seconds"]) < 0.5, "letterbox: cheap (%.3f s CPU)" % lb["cpu_seconds"])

	var pb := _detect_letterbox(F.path_join("letterbox/pillarbox.avi"))
	if not pb.is_empty():
		_eq([pb["known"], pb["bars"], pb["rect"]], [true, true, Rect2i(80, 0, 480, 352)], "pillarbox: bars of 80 columns left and right")

	# A film cropped to its picture: no bars.
	var none := _detect_letterbox(OS.get_environment("HOME") + "/media-tests/animated_90s.ts")
	if not none.is_empty():
		_eq([none["known"], none["bars"], none["rect"]], [true, false, Rect2i(Vector2i(), none["frame_size"])], "letterbox: none in a cropped film")


# Up to p_count video packets of the current serial: [pts, keyframe] each.
func _video_packets(source: MediaSource, count: int, wall_ms: int) -> Array:
	var out := []
	var t0 := Time.get_ticks_msec()
	while out.size() < count and Time.get_ticks_msec() - t0 < wall_ms:
		var p := source.read_video_packet()
		if p.is_empty():
			if source.is_eof():
				break
			OS.delay_msec(1)
			continue
		if int(p["serial"]) == source.get_serial():
			out.append([float(p["pts"]), bool(p["keyframe"])])
	return out


# Keyframes only, each at least speed x 0.25 s after the one before.
func _check_trick_packets(name: String, packets: Array, speed: float) -> void:
	var keyframes := true
	var spaced := true
	for i in packets.size():
		keyframes = keyframes and packets[i][1]
		if i > 0:
			spaced = spaced and packets[i][0] - packets[i - 1][0] >= speed * 0.25 - 0.01
	_check(packets.size() >= 3 and keyframes and spaced, "%s: keyframes only, at least %.1f s apart (%s)" % [name, speed * 0.25, packets.map(func(p: Array) -> float: return snappedf(p[0], 0.01))])


func _trick_play() -> void:
	print("Trick play")
	# An AVI with an index and a keyframe every second: 8x jumps 2 s through the index, reading nothing in between.
	var avi := _open(F.path_join("letterbox/letterbox.avi"))
	if avi:
		var before := avi.get_stats()
		var serial := avi.trick_play(8.0, 2.0)
		_check(serial == avi.get_serial() and avi.get_trick_play_speed() == 8.0, "trick play: a seek, speed 8")
		var packets := _video_packets(avi, 12, 5000)
		_check_trick_packets("AVI 8x", packets, 8.0)
		_eq(packets.slice(0, 3).map(func(p: Array) -> float: return p[0]), [2.0, 4.0, 6.0], "AVI 8x: from the keyframe at the start, then every 2 s")
		var stats := avi.get_stats()
		_check(int(stats["trick_steps"]) >= 10 and int(stats["packets_read"]) - int(before["packets_read"]) <= packets.size() + 2, "AVI 8x: jumps through the index, reads only what it shows (%d steps, %d packets read)" % [stats["trick_steps"], int(stats["packets_read"]) - int(before["packets_read"])])
		avi.close()

	# MPEG-TS has no index: read on, drop all but the keyframes due. Audio stops, and comes back after.
	var ts := _open(OS.get_environment("HOME") + "/media-tests/animated_90s.ts")
	if ts:
		ts.trick_play(8.0, 10.0)
		var packets := _video_packets(ts, 8, 8000)
		_check_trick_packets("MPEG-TS 8x", packets, 8.0)
		var stats := ts.get_stats()
		_check(int(stats["trick_steps"]) == 0 and int(stats["video_skipped"]) > 100, "MPEG-TS 8x: reads on (%d skipped)" % stats["video_skipped"])
		_check(stats["audio_finished"] and float(stats["audio_buffered"]) == 0.0, "trick play: no audio")
		var playback := ts.get_audio_stream().instantiate_playback()
		playback.start(0.0)
		ts.trick_play(0.0, 30.0)
		_eq(ts.get_trick_play_speed(), 0.0, "trick play off")
		var normal := _video_packets(ts, 30, 5000)
		var non_key := normal.filter(func(p: Array) -> bool: return not p[1]).size()
		_check(normal.size() == 30 and non_key > 20 and normal[0][0] <= 30.0, "back to normal: every frame again from the keyframe before 30 s (%d of %d not keyframes, first %.2f)" % [non_key, normal.size(), normal[0][0] if normal.size() > 0 else -1.0])
		var frames := PackedVector2Array()
		_mix_seconds(ts, playback, 0.5, frames)
		_check(absf(ts.get_audio_position() - 30.5) < 0.1, "back to normal: the audio plays from 30 s (%.2f)" % ts.get_audio_position())
		ts.close()

	# MP4 (full index), 10 s between keyframes: every keyframe at 4x.
	var mp4 := _open(F.path_join("meta_none.mp4"))
	if mp4:
		mp4.trick_play(4.0, 1.0)
		var packets := _video_packets(mp4, 5, 4000)
		_check_trick_packets("MP4 4x", packets, 4.0)
		_check(int(mp4.get_stats()["trick_steps"]) >= 1, "MP4 4x: jumps through the index")
		mp4.close()


# The next-item API without a renderer (the handover itself runs in the spike: --next, see the README).
func _next_item() -> void:
	print("Next item (API)")
	var a := HWVideoTexture.new()
	var b := HWVideoTexture.new()
	var a_y := a.get_plane_texture(0)
	var a_uv := a.get_plane_texture(1)
	var b_y := b.get_plane_texture(0)
	_check(not a.is_finished(), "next item: a closed texture isn't finished")
	a.set_next(b)
	_check(a.get_next() == b and a.get_stats().get("next_preroll_seconds", 0.0) == -1.0, "next item: set_next(), no first frame yet")
	var changes := [0]
	a.format_changed.connect(func() -> void: changes[0] += 1)
	b.format_changed.connect(func() -> void: changes[0] += 1)
	a.swap_planes_with(b)
	_check(b.get_plane_texture(0) == a_y and b.get_plane_texture(1) == a_uv and a.get_plane_texture(0) == b_y, "next item: swap_planes_with() exchanges the plane textures")
	_eq(changes[0], 2, "next item: format_changed on both")
	a.swap_planes_with(b)
	_check(a.get_plane_texture(0) == a_y, "next item: and back")
	a.close()
	_check(a.get_next() == null, "next item: close() lets go of the next")


# The app's requests: field order, whole subtitle tracks, dual subtitles, small files through MediaBrowser.
func _requests() -> void:
	print("Field order, subtitle lines, dual subtitles, read_file")
	var path := F.get_base_dir().path_join("animated_subs.mkv")
	var source := _open(path)
	if source == null:
		return
	_eq(source.get_video_info().get("field_order", "?"), "progressive", "field_order")
	var srt := source.get_subtitle_lines(0)
	var ass := source.get_subtitle_lines(1)
	_eq([srt.size(), ass.size()], [17, 17], "get_subtitle_lines(): lines per track")
	if srt.size() > 1 and ass.size() > 1:
		_check(srt[0]["start"] < srt[1]["start"] and srt[0]["end"] > srt[0]["start"], "get_subtitle_lines(): sorted, with an end")
		_check("{" in str(ass[0]["ass"]) and not "{" in str(ass[0]["text"]) and "\n" in str(ass[0]["text"]), "get_subtitle_lines(): the ASS event as is, the text without tags")
	_eq(source.get_subtitle_lines(9).size(), 0, "get_subtitle_lines(): a track that isn't there")
	_check(source.get_last_error() != "" and source.get_state() != MediaSource.STATE_ERROR, "get_subtitle_lines(): last_error, not the error state")
	_check(source.select_secondary_subtitle_track(5) != OK, "select_secondary_subtitle_track(): a track that isn't there")
	source.select_audio_track(-1)
	source.select_subtitle_track(0)
	_eq(source.select_secondary_subtitle_track(1), OK, "select_secondary_subtitle_track(1)")
	_eq(source.get_secondary_subtitle_track(), 1, "get_secondary_subtitle_track()")
	source.seek(0.0)
	var per_track := {}
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 8000:
		var packet := source.read_video_packet()
		var e := source.read_subtitle_event()
		while not e.is_empty():
			per_track[e["track"]] = per_track.get(e["track"], 0) + 1
			e = source.read_subtitle_event()
		if packet.is_empty():
			if source.is_eof():
				break
			OS.delay_msec(1)
	_eq(per_track, {0: 17, 1: 17}, "dual subtitles: events per track")
	source.close()
	var browser := MediaBrowser.new()
	var bytes := browser.read_file(F.path_join("music/cover.png"))
	_check(bytes.size() > 1000 and bytes.slice(1, 4).get_string_from_ascii() == "PNG", "MediaBrowser.read_file(): a PNG")
	_check(browser.read_file(F.path_join("nothing.png")).is_empty() and browser.get_last_error() != "", "MediaBrowser.read_file(): a missing file")


# read_audio_frames() with and without set_external_clock(). The clock is given again before every read (at the
# current ticks), so the test runs faster than real time: it is a simulated output device clock plus an offset.
func _audio_pull() -> void:
	print("Audio without a player, and an external clock")
	var source := _open(F.path_join("tone_steps.avi"))
	if source == null:
		return
	var rate := float(source.get_output_rate())
	source.seek(2.0)
	var frames := PackedVector2Array()
	while frames.size() < int(3.0 * rate):
		_wait_audio(source)
		frames.append_array(source.read_audio_frames(333))
	_near(source.get_audio_position(), 2.0 + frames.size() / rate, "pull without a clock: audio clock", 0.002)
	_eq(_tone_step(frames, int(1.5 * rate) - 2205, 4410, rate), 3, "pull without a clock: tone at 1.5 s of output")
	_check(_purity(frames, int(0.3 * rate), 4096, 300.0 + 25.0 * 2, rate) > 0.9, "pull without a clock: a clean tone across reads")
	var stats := source.get_stats()
	_check(not stats["external_clock"] and stats["external_clock_ratio"] == 1.0, "pull without a clock: stats")
	_eq(source.read_audio_frames(0).size(), 0, "read_audio_frames(0)")
	# The clock 0.1 s ahead of the audio: the audio speeds up by 0.5 %, the gap closes towards 0 (20 s time constant).
	# Then 0.1 s behind it: the audio slows down.
	for offset: float in [0.1, -0.1]:
		source.seek(2.0)
		var out := 0
		var errors := []
		var pulled := PackedVector2Array()
		while out < int(10.0 * rate):
			_wait_audio(source)
			source.set_external_clock(2.0 + offset + out / rate, Time.get_ticks_usec())
			var chunk := source.read_audio_frames(512)
			if out < int(2.0 * rate):
				pulled.append_array(chunk)
			out += chunk.size()
			if out % int(rate) < 512:
				errors.append(snappedf(float(source.get_stats()["external_clock_error_ms"]), 0.1))
		var error := source.get_audio_position() - (2.0 + offset + out / rate)
		stats = source.get_stats()
		print("  clock %+.1f s: error each second %s ms; after 10 s %.1f ms, ratio %.4f" % [offset, errors, error * 1000.0, stats["external_clock_ratio"]])
		_near(error, -offset * exp(-0.5), "external clock %+.1f: the gap after 10 s" % offset, 0.005)
		_check(stats["external_clock"] and signf(stats["external_clock_ratio"] - 1.0) == signf(offset), "external clock %+.1f: stats" % offset)
		var shifted := (300.0 + 25.0 * 3) * (1.0 + 0.005 * signf(offset))
		_check(_purity(pulled, int(1.2 * rate), 8192, shifted, rate) > 0.9, "external clock %+.1f: the tone resampled cleanly" % offset)
	source.set_external_clock(-1.0, 0)
	_check(not source.get_stats()["external_clock"], "set_external_clock(-1): none")
	source.close()


func _wait_audio(source: MediaSource) -> void:
	for wait in 1000:
		var stats := source.get_stats()
		if float(stats["audio_buffered"]) > 0.3 or bool(stats["audio_finished"]):
			return
		OS.delay_msec(1)


func _films() -> void:
	print("Films (chapters and container metadata)")
	for f in DirAccess.get_files_at(M):
		if f.get_extension().to_lower() not in ["mkv", "mp4", "avi", "ts"]:
			continue
		var source := MediaSource.new()
		if source.open(M.path_join(f)) != OK:
			continue
		var v := source.get_video_info()
		var chapters := source.get_chapters()
		print("  %s: %d chapters%s, stereo \"%s\", projection \"%s\"" % [f, chapters.size(),
				(" (first \"%s\" at %.1f, last \"%s\" at %.1f)" % [chapters[0]["title"], chapters[0]["start"], chapters[-1]["title"], chapters[-1]["start"]]) if chapters.size() > 0 else "",
				v.get("stereo_mode", ""), v.get("projection", "")])
		source.close()
