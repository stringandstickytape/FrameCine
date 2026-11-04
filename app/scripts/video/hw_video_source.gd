extends "res://scripts/video/video_source.gd"

## Hardware video: HWVideoTexture from our engine fork (modules/hwvideo; V4L2 decode, decoder dmabufs sampled in
## place). Two ways in:
##   - MediaSource (demux + audio decode, in the module): .mkv / .mp4 files with H.264 / HEVC 8-bit video.
##     open_source(MediaSource) feeds the texture; MediaSource gives the audio stream, tracks, duration and seek.
##   - Raw Annex-B .h264/.hevc elementary streams (what spike 03 plays): HWVideoTexture.open(path, codec, fps), with
##     an optional Ogg Vorbis sidecar as audio. Seeking is restart-only there.
## The engine classes are looked up at run time (ClassDB) so this script also parses on a stock engine build.

const RAW_H264: Array[String] = ["h264", "264", "avc", "jsv"]
const RAW_HEVC: Array[String] = ["h265", "265", "hevc"]
const DEFAULT_FPS := 23.976
const NetworkHosts := preload("res://scripts/net/network_hosts.gd")

## HWVideoTexture (untyped: the class only exists in our engine build).
var _tex: Variant = null
## MediaSource, or null for raw streams.
var _media: Variant = null
var _audio: AudioStream = null
var _info := {}
var _duration := 0.0
var _state_ended := 4
var _state_error := 5
## The next item chained with HWVideoTexture.set_next() (scripts/play/gapless.gd, ideas #44), until it takes over.
var _next: Object = null
## True once the next item has taken over the plane textures: this source is done and must not report an end.
var _handed_over := false
## Crossfade (scripts/play/crossfade.gd, #94): the next item takes over at the end; report no end meanwhile.
var hold_end := false

## The chained next item took over at this item's end (HWVideoTexture.next_started): adopt `next` as the source,
## from the next frame on, then close this one.
signal next_started(next: Object)
## Keep the audio's channels apart (MediaSource.discrete_channels, set before a file opens) for the spatial audio
## (scripts/play/spatial_audio.gd, ideas #21 / #47). Engine builds without it ignore it.
static var discrete_channels := false
## Look for letterbox or pillarbox bars (MediaSource.letterbox_detection, set before a file opens) for the auto crop
## (scripts/play/auto_crop.gd, ideas #42). A nice-10 thread decodes a keyframe now and then; engine builds without it
## ignore it.
static var letterbox_detection := false
## Seconds of a live stream to buffer before playing (MediaSource.live_latency, 0.1 to 2.5, set before a file opens;
## scripts/play/live_stream.gd). Below 0: the engine's default. Engine builds without it ignore it.
static var live_latency := -1.0
## VP9 in hardware ([hwvideo] hw_vp9, default on; scripts/play/hw_video.gd sets it): HWVideoTexture.hw_vp9, set before
## a file opens. The engine keeps hardware VP9 to one session at a time (two crash the decoder firmware), so a second
## VP9 texture (next item, picture in picture, thumbnails) decodes in software. Engine builds without it ignore it.
static var hw_vp9 := true


static func is_available() -> bool:
	return ClassDB.class_exists("HWVideoTexture")


static func has_media_source() -> bool:
	return ClassDB.class_exists("MediaSource")


static func is_http(p_path: String) -> bool:
	return p_path.begins_with("http://") or p_path.begins_with("https://")


## http(s):// files and streams, and udp:// (MPEG-TS in datagrams, live): MediaSource opens them by URL.
static func is_stream_url(p_path: String) -> bool:
	return is_http(p_path) or p_path.begins_with("udp://")


static func is_raw_stream(file_path: String) -> bool:
	var ext := file_path.get_extension().to_lower()
	return ext in RAW_H264 or ext in RAW_HEVC


func get_kind() -> String:
	return "hw"


func open(p_path: String) -> Error:
	path = p_path
	if not is_available():
		last_error = "This engine build has no HWVideoTexture (hardware video)."
		return ERR_UNAVAILABLE
	# smb://, http(s):// (media servers, docs/media-servers.md) and udp:// are network files: MediaSource opens them.
	var smb := NetworkHosts.is_smb(path) or is_stream_url(path)
	if smb and is_raw_stream(path):
		last_error = "Raw .h264/.hevc streams must be local files (the decoder maps them); network files go through MediaSource."
		return ERR_UNAVAILABLE
	if not smb and not FileAccess.file_exists(path):
		last_error = "File not found: %s" % path
		return ERR_FILE_NOT_FOUND
	_read_state_constants()
	var err: Error
	if is_raw_stream(path):
		err = _open_raw()
	elif has_media_source():
		err = _open_media()
	else:
		last_error = "Container files need MediaSource, which this engine build does not have yet. Raw .h264/.hevc streams play."
		err = ERR_UNAVAILABLE
	if err != OK:
		close()
	return err


func _read_state_constants() -> void:
	if ClassDB.class_has_integer_constant("V4L2Decoder", "STATE_ENDED"):
		_state_ended = ClassDB.class_get_integer_constant("V4L2Decoder", "STATE_ENDED")
		_state_error = ClassDB.class_get_integer_constant("V4L2Decoder", "STATE_ERROR")


## smb://, http(s):// and udp:// container files open on a worker thread (see open_media_blocking()); a live stream's
## open waits for its next keyframe.
static func opens_async(p_path: String) -> bool:
	return (NetworkHosts.is_smb(p_path) or is_stream_url(p_path)) and is_available() and has_media_source() \
			and not is_raw_stream(p_path) \
			and not p_path.get_extension().to_lower() in ["jpg", "jpeg", "png", "webp", "jps", "mpo"]


func _open_raw() -> Error:
	var ext := path.get_extension().to_lower()
	var codec := "h264" if ext in RAW_H264 else "hevc"
	var fps := _fps_from_name(path.get_file())
	_tex = ClassDB.instantiate("HWVideoTexture")
	_tex.connect("format_changed", _on_format_changed)
	var err: Error = _tex.open(path, codec, fps)
	if err != OK:
		last_error = "%s (%s)" % [_tex.get_last_error(), error_string(err)]
		return err
	_info = {"codec": codec, "width": 0, "height": 0, "fps": fps, "bit_depth": 8}
	var audio_path := find_sidecar_audio(path)
	if audio_path != "":
		var ogg := AudioStreamOggVorbis.load_from_file(audio_path)
		if ogg:
			_audio = ogg
			_duration = ogg.get_length()
			print("HWVideoSource: audio %s (%.1f s)" % [audio_path, _duration])
	print("HWVideoSource: %s, raw %s at %.3f fps" % [path, codec, fps])
	return OK


func _open_media() -> Error:
	return _finish_media(open_media_blocking(path))


## The blocking part of opening a container file: a new MediaSource, the host's saved credentials (smb://), open().
## On a network share this connects, logs in and probes (milliseconds on a LAN, up to the source's timeout, 8 s per
## step, when the host doesn't answer), so PlaybackController runs it on a worker thread for smb:// paths.
## Returns {"media": MediaSource, "err": Error, "error": user-ready text or ""}.
static func open_media_blocking(p_path: String) -> Dictionary:
	var media: Object = ClassDB.instantiate("MediaSource")
	NetworkHosts.apply_credentials(media, p_path)
	if discrete_channels and "discrete_channels" in media:
		media.set("discrete_channels", true)
	if letterbox_detection and "letterbox_detection" in media:
		media.set("letterbox_detection", true)
	if live_latency > 0.0 and "live_latency" in media:
		media.set("live_latency", clampf(live_latency, 0.1, 2.5))
	var err: Error = media.call("open", p_path)
	var error := ""
	if err != OK:
		error = str(media.call("get_last_error")) if media.has_method("get_last_error") else ""
		if error == "":
			error = "MediaSource can't open %s (%s)" % [p_path, error_string(err)]
	return {"media": media, "err": err, "error": error}


## Finishes opening with a MediaSource opened by open_media_blocking() (here or on a worker thread).
func open_with_media(p_path: String, result: Dictionary) -> Error:
	path = p_path
	_read_state_constants()
	var err := _finish_media(result)
	if err != OK:
		close()
	return err


func _finish_media(result: Dictionary) -> Error:
	_media = result["media"]
	var err: Error = result["err"]
	if err != OK:
		last_error = result["error"]
		return err
	_info = _media.get_video_info()
	_duration = _media.get_duration()
	_tex = ClassDB.instantiate("HWVideoTexture")
	_tex.connect("format_changed", _on_format_changed)
	apply_hw_vp9(_tex)
	err = _tex.open_source(_media)
	if err != OK:
		last_error = "%s (%s)" % [_tex.get_last_error(), error_string(err)]
		return err
	_audio = _media.get_audio_stream()
	if _media.has_method("get_audio_track") and int(_media.get_audio_track()) < 0:
		# No audio track: the stream would play silence with a clock that stands (on a live stream it never ends), so
		# the video runs on its own clock instead.
		_audio = null
	print("HWVideoSource: %s via MediaSource: %s, %.1f s" % [path, _info, _duration])
	return OK


## Sets hw_vp9 on an HWVideoTexture before its open_source() (any texture the app makes: playback, thumbnails, ...).
static func apply_hw_vp9(tex: Object) -> void:
	if tex != null and "hw_vp9" in tex:
		tex.set("hw_vp9", hw_vp9)


## An Ogg Vorbis file next to a raw stream: same base name, else the longest .ogg whose base name is a leading word
## of the video's (documentary.ogg for documentary_sbs.h264, as in spike 03's streams folder).
static func find_sidecar_audio(video_path: String) -> String:
	var base := video_path.get_basename()
	if FileAccess.file_exists(base + ".ogg"):
		return base + ".ogg"
	var dir := video_path.get_base_dir()
	var stem := video_path.get_file().get_basename().to_lower()
	var best := ""
	for f in DirAccess.get_files_at(dir):
		if f.get_extension().to_lower() != "ogg":
			continue
		var s := f.get_basename().to_lower()
		if s.length() < 3 or not stem.begins_with(s) or s.length() <= best.get_basename().length():
			continue
		# Whole words only: "documentary" for "documentary_sbs", not "doc" for "documentary_sbs".
		if stem.length() == s.length() or stem[s.length()] in ["_", "-", ".", " "]:
			best = f
	return dir.path_join(best) if best != "" else ""


## Raw streams carry no timing: "..._60.h265", "..._29.97fps.h264"; else 23.976.
static func _fps_from_name(file_name: String) -> float:
	var re := RegEx.create_from_string("(?:^|[^0-9.])(23\\.976|24|25|29\\.97|30|48|50|59\\.94|60|90|100|120)(?:fps|p)?(?:[^0-9]|$)")
	var found := re.search(file_name.get_basename().to_lower())
	return found.get_string(1).to_float() if found else DEFAULT_FPS


func _on_format_changed() -> void:
	if _next != null and _tex.has_method("is_finished") and _tex.is_finished():
		return  # The swap at the end of the item: these planes now belong to the next one, which the player adopts.
	var r: Rect2i = _tex.get_visible_rect()
	_info["width"] = r.size.x
	_info["height"] = r.size.y
	format_changed.emit()


func close() -> void:
	cancel_next()
	if _tex != null:
		_tex.close()
	if _media != null and _media.has_method("close"):
		_media.close()
	_tex = null
	_media = null
	_audio = null


func play() -> void:
	if _tex != null:
		_tex.play()


func pause() -> void:
	if _tex != null:
		_tex.pause()


func is_playing() -> bool:
	return _tex != null and _tex.is_playing()


## Not a live stream (udp://, HTTP without a length), nor HTTP from a server without Range requests.
func can_seek() -> bool:
	if _media == null or is_live():
		return false
	return not _media.has_method("is_seekable") or _media.is_seekable()


## A live stream: it plays as it arrives and can't seek (MediaSource.is_live()).
func is_live() -> bool:
	return _media != null and _media.has_method("is_live") and _media.is_live()


## HWVideoTexture.seek(): with a MediaSource it seeks the source once (audio and video; the texture picks up the new
## serial); with a raw file only 0 works. The player's AudioStreamPlayer.play(t) right after does not seek again
## (AudioStreamPlaybackMedia ignores a start position within 50 ms of the source's audio position).
func seek(seconds: float) -> void:
	if _tex == null or is_live():
		return  # A live stream plays as it arrives (the controller still asks for 0 on a "restart").
	if _media != null:
		_tex.seek(seconds)
	elif seconds < 0.5:
		_tex.seek_to_start()


func get_position() -> float:
	return _tex.get_position() if _tex != null else 0.0


func get_duration() -> float:
	return _duration


func update(delta: float, master_clock: float) -> void:
	if _tex != null:
		_tex.update(delta, master_clock)


func has_frame() -> bool:
	return _tex != null and _tex.has_frame()


## The media time of the frame on show: it moves with every new frame, and with a seek while paused.
func frame_key() -> float:
	return _tex.get_frame_time() if _tex != null else NAN


func is_ended() -> bool:
	# A chained next item takes over at the end (one frame after the input ends): no end to report.
	if _tex == null or _handed_over or _next != null or hold_end:
		return false
	return int(_tex.get_stats().get("state", -1)) == _state_ended


func get_plane_texture(plane: int) -> Texture2D:
	return _tex.get_plane_texture(plane) if _tex != null else null


func is_p010() -> bool:
	return _tex != null and _tex.get_packing() == HWVideoTexture.PACKING_P010


func get_visible_uv_rect() -> Rect2:
	return _tex.get_visible_uv_rect() if _tex != null else Rect2(0, 0, 1, 1)


func get_video_info() -> Dictionary:
	return _info


func get_audio_stream() -> AudioStream:
	return _audio


## True when the open file's audio is kept as separate channels (discrete_channels was on when it opened).
func has_discrete_channels() -> bool:
	return _media != null and "discrete_channels" in _media and bool(_media.get("discrete_channels")) 			and _media.has_method("get_audio_channel_stream")


## The engine's channels: [{index, name, label, present}, ...]. With spatial audio engines (frame/binaural) the
## audio's own channels in their order (FL, FR, FC, LFE, ..., TFL, ..., ACN0, ...); older ones the eight 7.1 slots.
func get_audio_channels() -> Array:
	return _media.get_audio_channels() if _media != null and _media.has_method("get_audio_channels") else []


## {channels, ambisonic_order, ambisonic_channels, remapped, names} (MediaSource.get_audio_layout()), or {} on an
## engine without spatial audio.
func get_audio_layout() -> Dictionary:
	return _media.get_audio_layout() if _media != null and _media.has_method("get_audio_layout") else {}


## Spatial audio: the stereo stream plays `renderer`'s binaural mix of the channels (null: the downmix). False on an
## engine without it.
func set_spatial_renderer(renderer: Object) -> bool:
	if _media == null or not _media.has_method("set_spatial_renderer"):
		return false
	_media.set_spatial_renderer(renderer)
	return true


func get_spatial_renderer() -> Object:
	return _media.get_spatial_renderer() if _media != null and _media.has_method("get_spatial_renderer") else null


## Channel n (the order above) as a mono stream, or null.
func get_audio_channel_stream(n: int) -> AudioStream:
	if _media != null and _media.has_method("get_audio_channel_stream"):
		return _media.get_audio_channel_stream(n)
	return null


func get_audio_tracks() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _media != null:
		for t: Dictionary in _media.get_audio_tracks():
			out.append(t)
	elif _audio != null:
		out.append({"index": 0, "codec": "vorbis", "channels": 2, "language": "", "title": "Sidecar audio"})
	return out


## MediaSource re-seeks to the current position itself and keeps feeding the same audio stream, so the stream object
## (and the player's playback) stays; get_audio_stream() would make a new one.
func select_audio_track(index: int) -> void:
	if _media != null:
		_media.select_audio_track(index)


func get_audio_track() -> int:
	if _media != null:
		return int(_media.get_audio_track())
	return 0 if _audio != null else -1


func get_subtitle_tracks() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _media != null and _media.has_method("get_subtitle_tracks"):
		for t: Dictionary in _media.get_subtitle_tracks():
			out.append(t)
	return out


## Dual subtitles (ideas #65; engine PLAYER_REQUESTS): a second text track of the file's own, read alongside the main
## one; its events come through read_subtitle_event() with "track". Engine builds without it: false / ERR_UNAVAILABLE.
func has_secondary_subtitles() -> bool:
	return _media != null and _media.has_method("select_secondary_subtitle_track")


func select_secondary_subtitle_track(index: int) -> Error:
	if not has_secondary_subtitles():
		return ERR_UNAVAILABLE
	return _media.select_secondary_subtitle_track(index) as Error


func get_secondary_subtitle_track() -> int:
	if _media != null and _media.has_method("get_secondary_subtitle_track"):
		return int(_media.get_secondary_subtitle_track())
	return -1


func select_subtitle_track(index: int) -> void:
	if _media != null and _media.has_method("select_subtitle_track"):
		_media.select_subtitle_track(index)


func get_subtitle_track() -> int:
	return int(_media.get_subtitle_track()) if _media != null and _media.has_method("get_subtitle_track") else -1


func read_subtitle_event() -> Dictionary:
	return _media.read_subtitle_event() if _media != null and _media.has_method("read_subtitle_event") else {}


func supports_external_subtitles() -> bool:
	return _media != null and _media.has_method("add_external_subtitle")


func add_external_subtitle(file: String, language := "", title := "") -> int:
	if not supports_external_subtitles():
		return -1
	return int(_media.add_external_subtitle(file, language, title))


## MediaSource.playback_speed time-stretches the audio (the master clock, so the video follows);
## HWVideoTexture.playback_speed runs the frame clock when there is no audio. Both are set.
func set_playback_speed(speed: float) -> void:
	if _media != null and "playback_speed" in _media:
		_media.playback_speed = clampf(speed, 0.5, 2.0)
	if _tex != null and "playback_speed" in _tex:
		_tex.playback_speed = clampf(speed, 0.25, 4.0)


## Night mode and dialogue boost (scripts/play/night_mode.gd, ideas #26): MediaSource.night_mode, night_mode_strength
## and dialogue_boost, live while playing (heard after the audio queue, about 1 s). Engine builds without them ignore it.
func set_audio_dynamics(night: bool, strength: float, boost_db: float) -> void:
	if _media == null:
		return
	if "night_mode" in _media:
		_media.night_mode = night
	if "night_mode_strength" in _media:
		_media.night_mode_strength = clampf(strength, 0.0, 1.0)
	if "dialogue_boost" in _media:
		_media.dialogue_boost = clampf(boost_db, 0.0, 12.0)


## Gapless change to the next item (HWVideoTexture.set_next(), fork 347778e84c): this file can hand over to one
## opened behind it. Not for raw streams, live streams or engine builds without it.
func can_chain() -> bool:
	return _tex != null and _media != null and _tex.has_method("set_next") and not is_live() and not _handed_over


## Chains the next item, opened by open_media_blocking() (on a worker thread): its texture opens on the MediaSource
## without playing, decodes and holds its first frame, and takes over the plane textures when this item has shown its
## last frame. Then next_started(next) is emitted. Returns the next source's open error.
func chain_next(p_path: String, result: Dictionary, host: Node) -> Error:
	cancel_next()
	if not can_chain():
		var m: Object = result.get("media")
		if m != null and m.has_method("close"):
			m.call("close")
		return ERR_UNAVAILABLE
	var nxt := (get_script() as GDScript).new() as Object
	nxt.call("attach", host)
	var err: Error = nxt.call("open_with_media", p_path, result)
	if err != OK:
		last_error = str(nxt.get("last_error"))
		nxt.call("close")
		return err
	_next = nxt
	if not _tex.is_connected("next_started", _on_next_started):
		_tex.connect("next_started", _on_next_started)
	_tex.set_next(nxt.get("_tex"))
	return OK


## The chained next item, or null.
func get_chained() -> Object:
	return _next


## Drops a chained next item that has not taken over yet.
func cancel_next() -> void:
	if _next == null:
		return
	if _tex != null and _tex.has_method("set_next") and not _handed_over:
		_tex.set_next(null)
	_next.call("close")
	_next = null


func _on_next_started(_next_tex: Object) -> void:
	var nxt := _next
	_handed_over = true
	_next = null
	next_started.emit(nxt)


## The letterbox detector's state (MediaSource.get_letterbox(): rect, uv_rect, bars, picture_aspect, known, done,
## ...), or {} without it.
func get_letterbox() -> Dictionary:
	if _media != null and _media.has_method("get_letterbox"):
		return _media.get_letterbox()
	return {}


## Trick play (scripts/play/trick_play.gd, ideas #46): MediaSource.trick_play(speed, from) with a speed of 2 to 64
## shows keyframes only, without audio (the audio stream plays silence and reports itself finished), and
## HWVideoTexture runs its clock at that speed; a speed of 0 goes back to normal playback with audio from `from`. Either
## way it is a seek: returns the new serial, or -1 (engine builds without it, nothing open, a live stream).
func has_trick_play() -> bool:
	return _media != null and _tex != null and _media.has_method("trick_play") 			and not (_media.has_method("is_live") and _media.is_live())


func trick_play(speed: float, from: float) -> int:
	if not has_trick_play():
		return -1
	return int(_media.trick_play(speed, from))


## The trick play speed now, 0 for normal playback.
func get_trick_play_speed() -> float:
	if _media != null and _media.has_method("get_trick_play_speed"):
		return float(_media.get_trick_play_speed())
	return 0.0


## MediaSource's own statistics (audio keys such as dialogue_boost_applies, audio_gain_db), or {}.
func get_media_stats() -> Dictionary:
	return _media.get_stats() if _media != null and _media.has_method("get_stats") else {}


func set_subtitle_read_ahead(seconds: float) -> void:
	if _media != null and "subtitle_read_ahead" in _media:
		_media.subtitle_read_ahead = clampf(seconds, 0.0, 30.0)


func pick_audio_track(languages: PackedStringArray) -> int:
	if _media != null and _media.has_method("pick_audio_track"):
		return int(_media.pick_audio_track(languages))
	return -2


func pick_subtitle_track(languages: PackedStringArray, forced_only := false) -> int:
	if _media != null and _media.has_method("pick_subtitle_track"):
		return int(_media.pick_subtitle_track(languages, forced_only))
	return -2


## MediaSource.get_chapters() once the engine has it (requested from the engine fork), else [].
func get_chapters() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _media != null and _media.has_method("get_chapters"):
		for c: Dictionary in _media.get_chapters():
			out.append(c)
	return out


## HWVideoTexture: after a seek, the frame at the target isn't shown yet ("settling" in its statistics).
func is_settling() -> bool:
	return _tex != null and _media != null and bool(_tex.get_stats().get("settling", false))


## MediaSource: its audio queues are full (or the file's end is reached behind them) and no video is queued.
func is_audio_blocking_video() -> bool:
	return _media != null and _media.has_method("is_audio_blocking_video") and _media.is_audio_blocking_video()


func get_stats() -> Dictionary:
	if _tex == null:
		return {}
	var stats: Dictionary = _tex.get_stats()
	if int(stats.get("state", -1)) == _state_error and last_error == "":
		last_error = str(stats.get("last_error", "decoder error"))
	# Network files: MediaSource's network: true and net_* keys (buffered bytes, stalls, reconnects, average Mbps).
	# After 5 failed reconnects it gives up with the reason in get_last_error().
	if _media != null and _media.has_method("get_stats"):
		var media_stats: Dictionary = _media.get_stats()
		if bool(media_stats.get("network", false)):
			stats["network"] = true
			for key: String in media_stats:
				if key.begins_with("net_"):
					stats[key] = media_stats[key]
		if last_error == "" and _media.has_method("get_last_error"):
			last_error = str(_media.get_last_error())
	return stats
