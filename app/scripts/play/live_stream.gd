extends Node

## Live streams: udp:// (MPEG-TS in datagrams: udp://@:1234 listens on every interface, udp://239.1.1.1:1234 joins a
## multicast group) and HTTP without a length (a media server's live TV, an IP camera's MPEG-TS) play as they arrive
## and can't seek. The engine (MediaSource.is_live(), live_latency) buffers `latency` seconds of audio before playing
## and after an underrun, and skips ahead when it falls more than twice that behind. HWVideoSource.can_seek() is false
## for them, so the seek features stand aside (they ask can_seek()); trick play is off. The pane hides its seek
## controls and shows a LIVE marker (app-shell's), from `live`.
##
##   live                              the open file is a live stream
##   latency, set_latency(seconds)     [network] live_latency (0.1 to 2.5, default 0.5): smaller is closer to live,
##                                     larger rides out more network jitter; a live stream open now opens again with it
##   buffered() -> float               seconds of audio decoded ahead now (about `latency` when steady), or -1
##   state() -> {live, latency, buffered, skips, text}   for the pane; text "LIVE" or ""
##   static is_media_url(url) -> bool  udp://, or http(s):// to a media file or a .ts stream: play it, not browse it
##   signal changed(live)

const HWVideoSource := preload("res://scripts/video/hw_video_source.gd")
const VideoSourceFactory := preload("res://scripts/video/video_source_factory.gd")

signal changed(live: bool)

const DEFAULT_LATENCY := 0.5

var main: Node3D
var live := false
var latency := DEFAULT_LATENCY


func _ready() -> void:
	latency = clampf(float(main.settings.get_value("network", "live_latency", DEFAULT_LATENCY)), 0.1, 2.5)
	HWVideoSource.live_latency = latency
	main.file_opened.connect(func(_p: String) -> void: _update())


func set_latency(seconds: float) -> void:
	latency = clampf(seconds, 0.1, 2.5)
	main.settings.set_value("network", "live_latency", null if is_equal_approx(latency, DEFAULT_LATENCY) else latency)
	HWVideoSource.live_latency = latency
	if live and main.current_path != "":
		# The engine takes it at open; a live stream has no place to lose.
		main.open_path(main.current_path, false)


func buffered() -> float:
	var src: Object = main.player.source
	if not live or src == null or not src.has_method("get_media_stats"):
		return -1.0
	return float(src.get_media_stats().get("audio_buffered", -1.0))


func state() -> Dictionary:
	var skips := 0
	var src: Object = main.player.source
	if live and src != null and src.has_method("get_media_stats"):
		skips = int(src.get_media_stats().get("net_skips", 0))
	return {"live": live, "latency": latency, "buffered": buffered(), "skips": skips, "text": "LIVE" if live else ""}


## udp://, or an http(s):// URL whose path ends in a video or music extension (.ts included): the URL form plays it
## instead of opening it as a web page.
static func is_media_url(url: String) -> bool:
	var u := url.strip_edges()
	if u.begins_with("udp://"):
		return true
	if not HWVideoSource.is_http(u):
		return false
	var p := u.split("?", true, 1)[0].split("#", true, 1)[0]
	var rest := p.substr(p.find("://") + 3)
	if not rest.contains("/"):
		return false
	return VideoSourceFactory.is_video_file(p) or VideoSourceFactory.is_music_file(p)


func _update() -> void:
	var src: Object = main.player.source
	var now: bool = src != null and src.has_method("is_live") and src.is_live()
	if now != live:
		live = now
		changed.emit(live)
