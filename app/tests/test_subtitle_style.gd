extends SceneTree

## Unit tests for scripts/play/subtitle_style.gd and subtitle_file.gd (styled subtitles and subtitle files, ideas #67
## and #65). Run: godot --headless --xr-mode off --path app --script res://tests/test_subtitle_style.gd

const Style := preload("res://scripts/play/subtitle_style.gd")
const SubFile := preload("res://scripts/play/subtitle_file.gd")

var _failures := 0


func _init() -> void:
	var ass := "0,0,Default,,0,0,0,,"
	_eq(Style.from_event({"ass": ass + "Plain line"})["bbcode"], "Plain line")
	_eq(Style.from_event({"ass": ass + "{\\i1}Whisper{\\i0} said"})["bbcode"], "[i]Whisper[/i] said")
	_eq(Style.from_event({"ass": ass + "{\\b1}Bold{\\b0}\\Nnext"})["bbcode"], "[b]Bold[/b]\nnext")
	_eq(Style.from_event({"ass": ass + "{\\c&H0000FF&}red{\\c} plain"})["bbcode"], "[color=#ff0000]red[/color] plain")
	_eq(Style.from_event({"ass": ass + "{\\1c&H00FF00&\\u1}green u"})["bbcode"], "[u][color=#00ff00]green u[/color][/u]")
	_eq(Style.from_event({"ass": ass + "{\\b700}heavy{\\r}reset"})["bbcode"], "[b]heavy[/b]reset")
	_eq(Style.from_event({"ass": ass + "{\\pos(10,20)\\fad(100,100)}moved"})["bbcode"], "moved")
	_eq(Style.from_event({"ass": ass + "{\\p1}m 0 0 l 10 10{\\p0}after"})["bbcode"], "after")
	_eq(Style.from_event({"ass": ass + "a [tag] here"})["bbcode"], "a [lb]tag] here")
	_eq(Style.from_event({"ass": ass + "with, commas, kept"})["plain"], "with, commas, kept")
	_eq(Style.from_event({"ass": ass + "one\n1,0,Default,,0,0,0,,two"})["plain"], "one\ntwo")
	_check("alignment \\an8 (top)", Style.from_event({"ass": ass + "{\\an8}top"})["alignment"] == 8)
	_check("legacy \\a6 is top centre (8)", Style.from_event({"ass": ass + "{\\a6}top"})["alignment"] == 8)
	_check("default bottom centre", Style.from_event({"text": "x"})["alignment"] == 2)
	_eq(Style.from_event({"text": "only [text]"})["bbcode"], "only [lb]text]")
	_eq(Style.from_event({"ass": ass + "x\\hy"})["plain"], "x y")
	# The engine's parsed lines win over "ass"; sizes are relative to the largest run; white and black are defaults.
	var styled := {"ass": ass + "ignored", "styled": [{"alignment": 7, "runs": [
			{"text": "Hi ", "bold": true, "size": 40.0, "color": Color.WHITE, "outline_color": Color.BLACK},
			{"text": "there", "italic": true, "size": 20.0, "color": Color(1, 1, 0), "outline_color": Color(0, 0, 1)}]}]}
	var e := Style.from_event(styled)
	_eq(e["bbcode"], "[b]Hi [/b][i][outline_color=#0000ff][color=#ffff00]there[/color][/outline_color][/i]")
	_eq(Style.to_bbcode(e["lines"], 60), "[b]Hi [/b][i][font_size=30][outline_color=#0000ff][color=#ffff00]there" +
			"[/color][/outline_color][/font_size][/i]")
	_check("styled alignment 7", e["alignment"] == 7)
	_check("relative size 0.5", is_equal_approx(float(e["lines"][0]["runs"][1]["size"]), 0.5))

	# Subtitle files the app reads itself (second subtitle track, #65).
	var srt := "﻿1\r\n00:00:01,000 --> 00:00:02,500\r\n<i>Hello</i> <font color=\"#ff0000\">red</font>\r\n" + \
			"second line\r\n\r\n2\r\n00:01:02.250 --> 00:01:04,000 X1:10\r\n<b>Two</b> & <u>u</u>\r\n"
	var ev := SubFile.parse(srt, "srt")
	_check("srt: two events (%d)" % ev.size(), ev.size() == 2)
	if ev.size() == 2:
		_check("srt: times", is_equal_approx(ev[0]["start"], 1.0) and is_equal_approx(ev[0]["end"], 2.5)
				and is_equal_approx(ev[1]["start"], 62.25) and is_equal_approx(ev[1]["end"], 64.0))
		_eq(Style.from_event(ev[0])["bbcode"], "[i]Hello[/i] [color=#ff0000]red[/color]\nsecond line")
		_eq(ev[0]["text"], "Hello red\nsecond line")
		_eq(Style.from_event(ev[1])["bbcode"], "[b]Two[/b] & [u]u[/u]")
	var vtt := "WEBVTT\n\nNOTE skip me\n\ncue-1\n00:05.000 --> 00:07.000 line:90%\n<v Ann>Hi <i>you</i></v>\n\n" + \
			"01:00:00.000 --> 01:00:01.000\n<c.yellow>Late</c> &amp; &lt;b&gt;\n"
	ev = SubFile.parse(vtt, "vtt")
	_check("vtt: two events (%d)" % ev.size(), ev.size() == 2)
	if ev.size() == 2:
		_check("vtt: times", is_equal_approx(ev[0]["start"], 5.0) and is_equal_approx(ev[1]["start"], 3600.0))
		_eq(Style.from_event(ev[0])["bbcode"], "Hi [i]you[/i]")
		_eq(ev[1]["text"], "Late & <b>")
	var ssa := "[Script Info]\nPlayResY: 288\n\n[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, " + \
			"MarginV, Effect, Text\nComment: 0,0:00:00.00,0:00:01.00,Default,,0,0,0,,skip\n" + \
			"Dialogue: 0,0:00:03.50,0:00:05.00,Default,,0,0,0,,{\\an8}Top, with comma\\Nnext\n"
	ev = SubFile.parse(ssa, "ass")
	_check("ass: one dialogue (%d)" % ev.size(), ev.size() == 1)
	if ev.size() == 1:
		_check("ass: times", is_equal_approx(ev[0]["start"], 3.5) and is_equal_approx(ev[0]["end"], 5.0))
		var s := Style.from_event(ev[0])
		_eq(s["plain"], "Top, with comma\nnext")
		_check("ass: alignment 8", s["alignment"] == 8)
	_check("unknown format: no events", SubFile.parse("whatever", "sub").is_empty())
	_eq(SubFile.decode(PackedByteArray([0x43, 0x61, 0x66, 0xE9])), "Café")
	_eq(SubFile.decode("Café".to_utf8_buffer()), "Café")
	_eq(SubFile.decode(PackedByteArray([0xFF, 0xFE, 0x48, 0x00, 0x69, 0x00])), "Hi")
	print("test_subtitle_style: %s" % ("all passed" if _failures == 0 else "%d FAILED" % _failures))
	quit(_failures)


func _eq(got: String, want: String) -> void:
	_check("'%s' == '%s'" % [got.c_escape(), want.c_escape()], got == want)


func _check(what: String, ok: bool) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL " + what)
