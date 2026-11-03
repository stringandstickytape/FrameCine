extends SceneTree

## Director mode (scripts/director/): SubRip, WebVTT and ASS parsing with markup removed, search (words, quoted
## phrases, accents and punctuation), line_at() and paging.
## The engine's whole-track dump (MediaSource.get_subtitle_lines, faked here): one read for callers at once, a
## progress state while it reads, a stopped read not kept.
## godot --headless --xr-mode off --path app --script res://tests/test_director.gd

const SubtitleText := preload("res://scripts/director/subtitle_text.gd")
const Director := preload("res://scripts/director/director.gd")

const SRT := "1\r\n00:00:01,000 --> 00:00:03,500\r\n<i>Where is</i> the money?\r\n\r\n2\r\n00:00:06,000 --> 00:00:08,500\r\nIt's in the car.\r\nThe red one.\r\n\r\n3\r\n01:02:03,250 --> 01:02:05,000\r\nNo money, no car!\r\n"
const VTT := "WEBVTT\n\n00:01.000 --> 00:02.000 align:start\nHello there\n\nnote-id\n00:00:05.500 --> 00:00:06.000\n<v Bob>Good evening</v>\n"
const ASS := "[Script Info]\nTitle: x\n\n[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\nDialogue: 0,0:00:11.00,0:00:13.00,Default,,0,0,0,,{\\i1}Café, s'il vous plaît{\\i0}\\Nsecond, line\nComment: 0,0:00:12.00,0:00:13.00,Default,,0,0,0,,not this\nDialogue: 0,0:00:01.00,0:00:03.00,Default,,0,0,0,,{\\pos(1,2)}First\n"

var _fails := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_srt()
	_test_vtt()
	_test_ass()
	_test_search()
	await _test_engine_index()
	print("test_director: %s" % ("all passed" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + what)


func _test_srt() -> void:
	var l := SubtitleText.parse(SRT, "srt")
	_check(l.size() == 3, "srt: 3 lines (got %d)" % l.size())
	_check(is_equal_approx(l[0]["start"], 1.0) and is_equal_approx(l[0]["end"], 3.5), "srt: times")
	_check(l[0]["text"] == "Where is the money?", "srt: <i> removed (got %s)" % l[0]["text"])
	_check(l[1]["text"] == "It's in the car.\nThe red one.", "srt: two lines kept")
	_check(is_equal_approx(l[2]["start"], 3723.25), "srt: hours (got %s)" % l[2]["start"])


func _test_vtt() -> void:
	var l := SubtitleText.parse(VTT, "vtt")
	_check(l.size() == 2, "vtt: 2 cues (got %d)" % l.size())
	_check(is_equal_approx(l[0]["start"], 1.0) and is_equal_approx(l[0]["end"], 2.0), "vtt: mm:ss.mmm, settings after")
	_check(l[1]["text"] == "Good evening", "vtt: <v> removed (got %s)" % l[1]["text"])


func _test_ass() -> void:
	var l := SubtitleText.parse(ASS, "ass")
	_check(l.size() == 2, "ass: 2 dialogue lines, comment skipped (got %d)" % l.size())
	_check(l[0]["text"] == "First", "ass: sorted, {pos} removed (got %s)" % l[0]["text"])
	_check(l[1]["text"] == "Café, s'il vous plaît\nsecond, line", "ass: commas in text, N (got %s)" % l[1]["text"])


func _index(raw: Array) -> Dictionary:
	var lines: Array = []
	for r: Dictionary in raw:
		lines.append({"start": r["start"], "end": r["end"], "text": r["text"], "norm": Director.normalise(r["text"])})
	return {"lines": lines, "count": lines.size()}


func _test_search() -> void:
	var idx := _index(SubtitleText.parse(SRT, "srt"))
	_check(Director.search(idx, "money").size() == 2, "search: a word in two lines")
	_check(Director.search(idx, "MONEY car").size() == 1, "search: all words, any case")
	_check(Director.search(idx, "\"the car\"").size() == 1, "search: quoted phrase")
	_check(Director.search(idx, "\"car in\"").is_empty(), "search: phrase order matters")
	_check(Director.search(idx, "its").size() == 1, "search: apostrophes ignored (it's)")
	_check(Director.search(idx, "money?").size() == 2, "search: punctuation ignored")
	_check(Director.search(idx, "").is_empty(), "search: empty query")
	var h := Director.search(idx, "red")
	_check(h.size() == 1 and h[0]["i"] == 1 and h[0]["before"] == "Where is the money?", "search: index and context")
	_check(Director.search(idx, "money", 1).size() == 1, "search: limit")
	_check(Director.line_at(idx, 0.5) == -1 and Director.line_at(idx, 6.0) == 1 and Director.line_at(idx, 100.0) == 1,
			"line_at")
	_check(Director.lines(idx, 1, 10).size() == 2, "lines: paging")
	var a := _index(SubtitleText.parse(ASS, "ass"))
	_check(Director.search(a, "cafe").is_empty() and Director.search(a, "café").size() == 1,
			"search: accents kept as written")


class FakeMedia extends RefCounted:
	var calls := 0
	var lines: Array = []
	var error := ""
	var delay_ms := 0

	func get_subtitle_tracks() -> Array:
		return [{"index": 2, "language": "eng", "title": "", "text": true}]

	func get_subtitle_track() -> int:
		return 2

	func get_subtitle_lines(_track: int) -> Array:
		calls += 1
		OS.delay_msec(delay_ms)
		return lines.duplicate(true)

	func get_last_error() -> String:
		return error


class FakeSource extends RefCounted:
	var _media: Object


class FakePlayer extends RefCounted:
	var source: Object


class FakeMain extends Node:
	var current_path := "C:/no/such/folder/film.mkv"
	var player := FakePlayer.new()


func _test_engine_index() -> void:
	var media := FakeMedia.new()
	media.lines = [{"start": 5.0, "end": 6.0, "text": "Second line", "ass": ""},
			{"start": 1.0, "end": 2.0, "text": "<i>First</i> line", "ass": ""}]
	media.delay_ms = 300
	var main := FakeMain.new()
	main.player.source = FakeSource.new()
	main.player.source._media = media
	root.add_child(main)
	Director.clear_cache()

	var got: Array = []
	var ask := func() -> void: got.append(await Director.index(main))
	ask.call()
	ask.call()
	await process_frame
	var b := Director.building(main)
	_check(b.get("source", "") == "engine" and float(b.get("seconds", -1.0)) >= 0.0, "engine: building() while read (%s)" % b)
	var until := Time.get_ticks_msec() + 5000
	while got.size() < 2 and Time.get_ticks_msec() < until:
		await process_frame
	_check(got.size() == 2 and media.calls == 1, "engine: two callers, one read (%d calls)" % media.calls)
	_check(Director.building(main).is_empty(), "engine: building() empty after")
	var idx: Dictionary = got[0] if got.size() > 0 else {}
	_check(idx.get("source", "") == "engine" and idx.get("track", "") == "t2" and idx.get("count", 0) == 2,
			"engine: index of track t2 with 2 lines (%s)" % idx.get("count", 0))
	_check(idx.get("count", 0) == 2 and idx["lines"][0]["text"] == "First line", "engine: sorted, markup removed")
	await Director.index(main)
	_check(media.calls == 1, "engine: kept after a good read")

	media.delay_ms = 0
	media.lines = []
	media.error = "Stopped: the file was closed."
	Director.clear_cache()
	idx = await Director.index(main)
	_check(idx["count"] == 0 and str(idx["error"]).begins_with("Stopped"), "engine: a stopped read says why")
	await Director.index(main)
	_check(media.calls == 3, "engine: a stopped read is not kept (%d calls)" % media.calls)

	media.error = ""
	Director.clear_cache()
	await Director.index(main)
	await Director.index(main)
	_check(media.calls == 4, "engine: a track with no lines is kept, not read again (%d calls)" % media.calls)
	Director.clear_cache()
	main.queue_free()
