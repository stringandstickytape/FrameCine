extends "res://scripts/video/video_source.gd"

## Music files (ideas #64): MP3, FLAC, Ogg, Opus, WAV, AAC / M4A, AC-3, DTS, ... played by the engine's MediaSource
## without video (fork 5997ea5369: the audio is the clock), with a card on the flat screen instead of a picture: the
## cover from the file (get_album_art()), title, artist and album from its tags, the time, and a simple visualiser of
## the sound (bars from an AudioEffectSpectrumAnalyzer on the Master bus while it plays). Without a cover, the
## visualiser fills the card. 16:9, flat and mono, so lying down (#12) and the other screen comforts work as for films.
##
## Kind "music". The card is a SubViewport (CARD_SIZE) drawn by MusicCard below; its texture is the screen's RGB source.
## Network files (smb://, http://) open on the player's worker thread like videos (open_with_media()).

const NetworkHosts := preload("res://scripts/net/network_hosts.gd")
const EXTENSIONS: Array[String] = ["mp3", "flac", "ogg", "oga", "opus", "wav", "m4a", "aac", "alac", "ac3", "eac3",
		"dts", "thd", "mka", "wma", "aiff", "aif"]
const CARD_SIZE := Vector2i(1280, 720)
const BARS := 32
const BAND := Vector2(40.0, 12000.0)
## The visualiser's styles ([music] visualiser through main.features.set_visualiser()), with names for the pane.
const STYLES: Array[String] = ["bars", "mirror", "line", "radial", "off"]
const STYLE_NAMES := {"bars": "Bars", "mirror": "Mirror", "line": "Line", "radial": "Radial", "off": "Off"}

## The style every music card draws now.
static var style := "bars"

var title := ""
var artist := ""
var album := ""
var cover: Image
var _media: Object
var _host: Node
var _vp: SubViewport
var _card: Control
var _pos := 0.0
var _playing := true
var _duration := 0.0
var _drawn := false
var _analyzer: AudioEffectSpectrumAnalyzerInstance
var _effect_index := -1
var _levels := PackedFloat32Array()


static func is_music_path(p: String) -> bool:
	return p.get_extension().to_lower() in EXTENSIONS


static func available() -> bool:
	return ClassDB.class_exists("MediaSource") and ClassDB.class_has_method("MediaSource", "get_album_art")


func get_kind() -> String:
	return "music"


func attach(host: Node) -> void:
	_host = host


func open(p: String) -> Error:
	path = p
	if not available():
		last_error = "This engine build has no music playback (MediaSource.get_album_art)"
		return ERR_UNAVAILABLE
	var media: Object = ClassDB.instantiate("MediaSource")
	NetworkHosts.apply_credentials(media, p)
	var err: Error = media.call("open", p)
	if err != OK:
		last_error = str(media.call("get_last_error"))
		return err
	return _use(media)


## With a MediaSource already opened on a worker thread (HWVideoSource.open_media_blocking()'s result).
func open_with_media(p: String, result: Dictionary) -> Error:
	path = p
	if int(result.get("err", FAILED)) != OK:
		last_error = str(result.get("error", ""))
		return int(result.get("err", FAILED))
	return _use(result["media"])


func _use(media: Object) -> Error:
	_media = media
	_duration = float(media.call("get_duration"))
	var tags: Dictionary = media.call("get_tags")
	title = str(tags.get("title", "")).strip_edges()
	if title == "":
		title = path.get_file().get_basename().replace("_", " ")
	artist = str(tags.get("artist", tags.get("album_artist", ""))).strip_edges()
	album = str(tags.get("album", "")).strip_edges()
	var art: Variant = media.call("get_album_art")
	cover = art if art is Image and not (art as Image).is_empty() else null
	_build_card()
	_attach_analyzer(true)
	print("Music: %s%s%s, %.1f s%s" % [title, " - " + artist if artist != "" else "",
			" (" + album + ")" if album != "" else "", _duration, ", cover" if cover != null else ""])
	return OK


func _build_card() -> void:
	_vp = SubViewport.new()
	_vp.name = "MusicCard"
	_vp.size = CARD_SIZE
	_vp.disable_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_card = MusicCard.new()
	_card.source = self
	_card.size = Vector2(CARD_SIZE)
	if cover != null:
		_card.cover_tex = ImageTexture.create_from_image(cover)
	_vp.add_child(_card)
	if _host != null:
		_host.add_child(_vp)


func _attach_analyzer(on: bool) -> void:
	# The film's bus (scripts/env/env_audio.gd; Master without it): the room's own sounds never move the bars.
	var bus := AudioServer.get_bus_index("Film")
	if bus < 0:
		bus = AudioServer.get_bus_index("Master")
	if on and _effect_index < 0:
		var fx := AudioEffectSpectrumAnalyzer.new()
		fx.buffer_length = 0.1
		AudioServer.add_bus_effect(bus, fx)
		_effect_index = AudioServer.get_bus_effect_count(bus) - 1
		_analyzer = AudioServer.get_bus_effect_instance(bus, _effect_index) as AudioEffectSpectrumAnalyzerInstance
	elif not on and _effect_index >= 0:
		# Our effect is the last one we added; remove it by identity in case others came after.
		for i in AudioServer.get_bus_effect_count(bus):
			if AudioServer.get_bus_effect_instance(bus, i) == _analyzer:
				AudioServer.remove_bus_effect(bus, i)
				break
		_effect_index = -1
		_analyzer = null


## The bars' levels now, 0..1 each (log-spaced bands from BAND.x to BAND.y).
func levels() -> PackedFloat32Array:
	return _levels


## The visualiser style the card draws (the static `style`, for the card class).
func style_now() -> String:
	return style


func close() -> void:
	_attach_analyzer(false)
	if _vp != null:
		_vp.queue_free()
		_vp = null
	if _media != null and _media.has_method("close"):
		_media.call("close")
	_media = null


func play() -> void:
	_playing = true


func pause() -> void:
	_playing = false


func is_playing() -> bool:
	return _playing


func can_seek() -> bool:
	return _media != null and bool(_media.call("is_seekable"))


func seek(seconds: float) -> void:
	if _media != null:
		_media.call("seek", seconds)
		_pos = seconds


func get_position() -> float:
	return _pos


func get_duration() -> float:
	return _duration


func update(delta: float, master_clock: float) -> void:
	if _playing:
		_pos = master_clock if master_clock >= 0.0 else _pos + delta
	_levels.resize(BARS)
	for i in BARS:
		var lo := BAND.x * pow(BAND.y / BAND.x, float(i) / BARS)
		var hi := BAND.x * pow(BAND.y / BAND.x, float(i + 1) / BARS)
		var m := Vector2.ZERO
		if _analyzer != null and _playing:
			m = _analyzer.get_magnitude_for_frequency_range(lo, hi)
		var db := linear_to_db(maxf(maxf(m.x, m.y), 1e-6))
		var target := clampf((db + 60.0) / 54.0, 0.0, 1.0)
		# Up at once, down slowly.
		_levels[i] = target if target > _levels[i] else lerpf(_levels[i], target, clampf(delta * 6.0, 0.0, 1.0))
	if _card != null:
		_card.queue_redraw()
	if not _drawn:
		_drawn = true
		format_changed.emit()


func has_frame() -> bool:
	return _drawn


## Crossfade (scripts/play/crossfade.gd, #94): the next track takes over at the end; report no end meanwhile.
var hold_end := false


func is_ended() -> bool:
	if _media == null or hold_end:
		return false
	var st: Dictionary = _media.call("get_stats")
	return bool(st.get("audio_finished", false)) or (_duration > 0.0 and _pos >= _duration - 0.05
			and bool(_media.call("is_eof")))


func get_rgb_texture() -> Texture2D:
	return _vp.get_texture() if _vp != null else null


func get_video_info() -> Dictionary:
	return {"codec": "music", "width": CARD_SIZE.x, "height": CARD_SIZE.y, "fps": 30.0, "bit_depth": 8,
			"title": title, "artist": artist, "album": album, "has_cover": cover != null}


func get_known_mode() -> VideoMode:
	return VideoMode.from_id("flat")


func get_audio_stream() -> AudioStream:
	return _media.call("get_audio_stream") if _media != null else null


func get_audio_tracks() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _media != null:
		for t: Dictionary in _media.call("get_audio_tracks"):
			out.append(t)
	return out


func select_audio_track(index: int) -> void:
	if _media != null:
		_media.call("select_audio_track", index)


func get_audio_track() -> int:
	return int(_media.call("get_audio_track")) if _media != null else -1


func get_chapters() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _media != null and _media.has_method("get_chapters"):
		for c: Dictionary in _media.call("get_chapters"):
			out.append(c)
	return out


func set_playback_speed(speed: float) -> void:
	if _media != null and "playback_speed" in _media:
		_media.set("playback_speed", clampf(speed, 0.5, 2.0))


## Night mode and dialogue boost (scripts/play/night_mode.gd), as HWVideoSource has them.
func set_audio_dynamics(night: bool, strength: float, boost_db: float) -> void:
	if _media == null:
		return
	if "night_mode" in _media:
		_media.set("night_mode", night)
	if "night_mode_strength" in _media:
		_media.set("night_mode_strength", clampf(strength, 0.0, 1.0))
	if "dialogue_boost" in _media:
		_media.set("dialogue_boost", clampf(boost_db, 0.0, 12.0))


func get_media_stats() -> Dictionary:
	return _media.call("get_stats") if _media != null else {}


func get_stats() -> Dictionary:
	return {"state": 2 if _playing else 3, "music": true}


## The card: cover on the left, title, artist and album on the right, a time line and the visualiser's bars below.
## Without a cover, the bars take the card's middle.
class MusicCard extends Control:
	var source: Object
	var cover_tex: Texture2D
	var _font: Font = ThemeDB.fallback_font

	func _draw() -> void:
		var s := size
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.06, 0.06, 0.08))
		var lv: PackedFloat32Array = source.levels()
		var kind: String = source.style_now()
		var text_x := s.x * 0.08
		var bars_rect := Rect2(s.x * 0.08, s.y * 0.28, s.x * 0.84, s.y * 0.42)
		if cover_tex != null:
			var side := s.y * 0.62
			var at := Vector2(s.x * 0.06, (s.y - side) * 0.5 - s.y * 0.04)
			draw_texture_rect(cover_tex, Rect2(at, Vector2(side, side)), false)
			text_x = at.x + side + s.x * 0.05
			bars_rect = Rect2(text_x, s.y * 0.56, s.x - text_x - s.x * 0.06, s.y * 0.2)
		var title_size := int(s.y * 0.075)
		var y := s.y * 0.2 if cover_tex != null else s.y * 0.14
		draw_string(_font, Vector2(text_x, y), str(source.title), HORIZONTAL_ALIGNMENT_LEFT, s.x - text_x - 40.0,
				title_size, Color(0.95, 0.95, 0.97))
		if str(source.artist) != "":
			draw_string(_font, Vector2(text_x, y + title_size * 1.2), str(source.artist), HORIZONTAL_ALIGNMENT_LEFT,
					s.x - text_x - 40.0, int(title_size * 0.7), Color(0.8, 0.82, 0.86))
		if str(source.album) != "":
			draw_string(_font, Vector2(text_x, y + title_size * 2.1), str(source.album), HORIZONTAL_ALIGNMENT_LEFT,
					s.x - text_x - 40.0, int(title_size * 0.55), Color(0.6, 0.62, 0.66))
		# The visualiser. Radial wants height: below the album line, down to the time line.
		if kind == "radial" and cover_tex != null:
			bars_rect = Rect2(text_x, s.y * 0.4, s.x - text_x - s.x * 0.06, s.y * 0.42)
		_visualiser(kind, lv, bars_rect)
		# Time line.
		var d: float = source.get_duration()
		var p: float = source.get_position()
		var line_y := s.y * 0.88
		draw_rect(Rect2(s.x * 0.08, line_y, s.x * 0.84, 4.0), Color(0.25, 0.25, 0.28))
		if d > 0.0:
			draw_rect(Rect2(s.x * 0.08, line_y, s.x * 0.84 * clampf(p / d, 0.0, 1.0), 4.0), Color(0.9, 0.9, 0.95))
		draw_string(_font, Vector2(s.x * 0.08, line_y + s.y * 0.06), "%s / %s" % [_t(p), _t(d)],
				HORIZONTAL_ALIGNMENT_LEFT, -1, int(s.y * 0.035), Color(0.7, 0.72, 0.76))

	func _visualiser(kind: String, lv: PackedFloat32Array, r: Rect2) -> void:
		var n := lv.size()
		if n == 0 or kind == "off":
			return
		var w := r.size.x / n
		match kind:
			"mirror":
				# Bars both ways from the middle line.
				var mid := r.get_center().y
				for i in n:
					var h := maxf(r.size.y * 0.5 * lv[i], 1.0)
					draw_rect(Rect2(r.position.x + i * w + w * 0.15, mid - h, w * 0.7, h * 2.0), _colour(i, n))
			"line":
				# One line through the levels, with a faint fill under it.
				var pts := PackedVector2Array()
				for i in n:
					pts.append(Vector2(r.position.x + (i + 0.5) * w, r.end.y - r.size.y * lv[i]))
				for i in n - 1:
					var c := _colour(i, n)
					draw_line(pts[i], pts[i + 1], c, 4.0, true)
					draw_colored_polygon(PackedVector2Array([pts[i], pts[i + 1], Vector2(pts[i + 1].x, r.end.y),
							Vector2(pts[i].x, r.end.y)]), Color(c, 0.18))
			"radial":
				# Spokes round a circle in the middle of the area, low bands at the top, clockwise.
				var centre := r.get_center()
				var radius := minf(r.size.x, r.size.y) * 0.24
				var reach := minf(r.size.x, r.size.y) * 0.26
				for i in n:
					var a := TAU * float(i) / n - PI * 0.5
					var dir := Vector2(cos(a), sin(a))
					draw_line(centre + dir * radius, centre + dir * (radius + maxf(reach * lv[i], 2.0)), _colour(i, n),
							maxf(radius * TAU / n * 0.55, 2.0), true)
				draw_arc(centre, radius - 3.0, 0.0, TAU, 64, Color(0.3, 0.32, 0.38), 2.0, true)
			_:
				for i in n:
					var h := maxf(r.size.y * lv[i], 2.0)
					draw_rect(Rect2(r.position.x + i * w + w * 0.15, r.end.y - h, w * 0.7, h), _colour(i, n))

	static func _colour(i: int, n: int) -> Color:
		return Color(0.45, 0.7, 1.0).lerp(Color(1.0, 0.75, 0.4), float(i) / n)

	static func _t(sec: float) -> String:
		var t := int(sec)
		return "%d:%02d:%02d" % [t / 3600, (t / 60) % 60, t % 60] if t >= 3600 else "%d:%02d" % [t / 60, t % 60]
