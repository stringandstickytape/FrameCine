extends SceneTree

## Tests for live streams (scripts/play/live_stream.gd; HWVideoSource's udp:// and live rules) in the real main scene,
## on the fork's MediaSource: the URL rule for the Open URL form, the latency setting, and a real udp:// stream fed by
## this test from trick10.ts (make-feature-media.sh: the trick play clip remuxed to MPEG-TS, video only) at its own
## rate: it opens, plays, is live, can't seek, has no trick play, and a new latency opens it again with it.
## Needs the fork and a renderer for the stream part.
## Run: godot --xr-mode off --path app --script res://tests/test_live.gd

const LiveStream := preload("res://scripts/play/live_stream.gd")
const HWVideoSource := preload("res://scripts/video/hw_video_source.gd")
var CLIP := OS.get_environment("HOME").path_join("media-tests/app-features/trick10.ts")
const PORT := 47912

var _failures := 0
var _checks := 0
var main: Node3D
var _ts := PackedByteArray()
var _sent := 0
var _start_msec := 0
var _rate := 0.0
var _udp: PacketPeerUDP


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	await _frames(5)
	_check("udp:// is media", LiveStream.is_media_url("udp://@:1234") and LiveStream.is_media_url(" udp://239.1.1.1:5000 "))
	_check("http(s) to a media file is media", LiveStream.is_media_url("http://192.168.1.5:8200/MediaItems/7.mkv")
			and LiveStream.is_media_url("https://cam.local/live/stream.ts?token=1"))
	_check("a web page is not", not LiveStream.is_media_url("https://example.com")
			and not LiveStream.is_media_url("https://example.com/watch?v=1") and not LiveStream.is_media_url("example.com/a.mkv")
			and not LiveStream.is_media_url("http://host.mkv"))
	var lv: Node = main.features.live
	_check("latency 0.5 by default, given to the source", is_equal_approx(lv.latency, 0.5)
			and is_equal_approx(HWVideoSource.live_latency, 0.5))
	lv.set_latency(9.0)
	_check("latency clamped to 2.5", is_equal_approx(lv.latency, 2.5) and is_equal_approx(HWVideoSource.live_latency, 2.5))
	lv.set_latency(0.5)
	_check("not live without a file", not lv.live and lv.state()["text"] == "")
	_check("udp:// opens on a worker thread", HWVideoSource.opens_async("udp://@:1234") == HWVideoSource.has_media_source())

	if not ClassDB.class_has_method("MediaSource", "is_live") or not FileAccess.file_exists(CLIP) \
			or DisplayServer.get_name() == "headless":
		print("SKIP stream checks (needs the fork, the clip and a renderer)")
	else:
		await _stream(lv)
	print("test_live: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _stream(lv: Node) -> void:
	_ts = FileAccess.get_file_as_bytes(CLIP)
	_rate = _ts.size() / 120.0
	_udp = PacketPeerUDP.new()
	_udp.set_dest_address("127.0.0.1", PORT)
	_start_msec = Time.get_ticks_msec()
	process_frame.connect(_feed)
	main.set_environment("void")
	var changes: Array[bool] = []
	lv.changed.connect(func(on: bool) -> void: changes.append(on))
	var url := "udp://@:%d" % PORT
	main.open_path(url)
	await _until(func() -> bool: return main.player.source != null and main.player.get_position() > 1.0, 15.0)
	var src: Object = main.player.source
	_check("the stream opens and plays (%s, %.2f s)" % [src.get_kind() if src else "none", main.player.get_position()],
			src != null and src.get_kind() == "hw" and main.player.get_position() > 1.0)
	if src == null:
		return
	_check("no audio track: no audio stream, the video's own clock", main.player.audio.stream == null)
	_check("live, with the marker", lv.live and changes == [true] and lv.state()["text"] == "LIVE"
			and main.features.status_line().contains("LIVE"))
	_check("can't seek", not main.player.can_seek() and not src.can_seek())
	_check("no trick play", not main.features.trick.available() and not main.features.trick.start(4.0))
	_check("the playlist is the stream", main.playlist == [url])
	var p0: float = main.player.get_position()
	var t0 := Time.get_ticks_msec()
	main.player.seek(p0 + 30.0)
	main.player.seek_relative(-10.0)
	await create_timer(2.0).timeout
	var rate: float = (main.player.get_position() - p0) / ((Time.get_ticks_msec() - t0) / 1000.0)
	_check("seeks do nothing, it plays on at 1x (%.2f)" % rate, rate > 0.8 and rate < 1.2)
	var st: Dictionary = lv.state()
	print("  state %s, network: skips %d, overruns %d bytes" % [st, int(src.get_media_stats().get("net_skips", -1)),
			int(src.get_media_stats().get("net_overruns", -1))])
	_check("state for the pane", st["live"] and is_equal_approx(st["latency"], 0.5) and st.has("buffered"))

	# A new latency opens it again.
	lv.set_latency(1.0)
	var reopened := func() -> bool: return main.player.source != null and main.player.source != src and main.player.get_position() > 0.5
	await _until(reopened, 15.0)
	var src2: Object = main.player.source
	var applied: float = src2._media.live_latency if src2 != null and src2._media != null else -1.0
	_check("a new latency reopens the stream with it (%.2f)" % applied, src2 != src and is_equal_approx(applied, 1.0) and lv.live)
	lv.set_latency(0.5)
	await _until(func() -> bool: return main.player.source != null and main.player.source != src2, 15.0)

	process_frame.disconnect(_feed)
	main.open_path("stub://flat_mono")
	await _frames(5)
	_check("a file after it: not live", not lv.live and changes.back() == false)


## Sends the TS at its own rate (7 TS packets a datagram), looping.
func _feed() -> void:
	var due := int((Time.get_ticks_msec() - _start_msec) / 1000.0 * _rate)
	var n := 0
	while _sent < due and n < 400:
		var off := _sent % _ts.size()
		var end := mini(off + 188 * 7, _ts.size())
		_udp.put_packet(_ts.slice(off, end))
		_sent += end - off
		n += 1


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
