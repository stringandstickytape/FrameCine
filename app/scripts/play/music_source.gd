extends "res://scripts/video/video_source.gd"

## Music files (ideas #64): MP3, FLAC, Ogg, Opus, WAV, AAC / M4A, AC-3, DTS, ... played by the engine's MediaSource
## without video (fork 5997ea5369: the audio is the clock), with a card on the flat screen instead of a picture: the
## cover from the file (get_album_art()), title, artist and album from its tags, the time, and a visualiser of the
## sound (docs/visualisers.md: a shader from res://visualisers or user://visualisers, run by
## scripts/visualisers/visualiser_host.gd on the shared analysis, scripts/play/audio_analysis.gd, held while the file
## is open). 16:9, flat and mono, so lying down (#12) and the other screen comforts work as for films.
##
## Kind "music". The card is a SubViewport (CARD_SIZE): MusicCard draws the background, the visualiser's TextureRect
## sits in its area (the manifest's "area": a strip under the words, a taller area, or the whole card), and CardText
## draws the cover, words and time line over it. The card's texture is the screen's RGB source.
## Network files (smb://, http://) open on the player's worker thread like videos (open_with_media()).

const NetworkHosts := preload("res://scripts/net/network_hosts.gd")
const Registry := preload("res://scripts/visualisers/visualiser_registry.gd")
const VisualiserHost := preload("res://scripts/visualisers/visualiser_host.gd")
const AudioAnalysis := preload("res://scripts/play/audio_analysis.gd")
const EXTENSIONS: Array[String] = ["mp3", "flac", "ogg", "oga", "opus", "wav", "m4a", "aac", "alac", "ac3", "eac3",
		"dts", "thd", "mka", "wma", "aiff", "aif"]
const CARD_SIZE := Vector2i(1280, 720)
## levels(): this many bands, for the overlay and tests (the visualisers read the analysis's 128).
const BARS := 32
const OFF := "off"
const DEFAULT_STYLE := "bars"
const BACKGROUND := Color(0.06, 0.06, 0.08)

## The visualiser every music card draws now: an id from the registry, or "off" ([music] visualiser through
## main.features.set_visualiser()).
static var style := DEFAULT_STYLE

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
var _levels := PackedFloat32Array()
var _cover_tex: Texture2D
var _vis: VisualiserHost
var _vis_rect: TextureRect
var _text: Control
var _holding := false


## Every style: the visualisers' ids in order, then "off".
static func styles() -> Array[String]:
	var out := Registry.ids()
	out.append(OFF)
	return out


## The styles' names for people (the manifests' "name"; "Off").
static func style_names() -> Dictionary:
	var out := {OFF: "Off"}
	for id in Registry.ids():
		out[id] = Registry.entry(id)["name"]
	return out


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
	_hold(true)
	print("Music: %s%s%s, %.1f s%s" % [title, " - " + artist if artist != "" else "",
			" (" + album + ")" if album != "" else "", _duration, ", cover" if cover != null else ""])
	return OK


func _build_card() -> void:
	_vp = SubViewport.new()
	_vp.name = "MusicCard"
	_vp.size = CARD_SIZE
	_vp.disable_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if cover != null:
		_cover_tex = ImageTexture.create_from_image(cover)
	_card = MusicCard.new()
	_card.size = Vector2(CARD_SIZE)
	_vp.add_child(_card)
	_vis_rect = TextureRect.new()
	_vis_rect.name = "VisualiserArea"
	_vp.add_child(_vis_rect)
	_text = CardText.new()
	_text.source = self
	_text.cover_tex = _cover_tex
	_text.size = Vector2(CARD_SIZE)
	_vp.add_child(_text)
	_vis = VisualiserHost.new()
	_vis.name = "VisualiserHost"
	_vis.cover = _cover_tex
	_vp.add_child(_vis)
	_vis.setup(_vp, _vis_rect)
	if _host != null:
		_host.add_child(_vp)


## Holds the shared analysis (with the waveform) while the file is open.
func _hold(on: bool) -> void:
	var a := AudioAnalysis.shared
	if a != null and on != _holding:
		a.request(self, on, true)
	_holding = on and a != null


## The levels now, 0..1 each: BARS bands from the analysis's smoothed ones (the overlay, tests).
func levels() -> PackedFloat32Array:
	return _levels


## The visualiser style the card draws (the static `style`).
func style_now() -> String:
	return style


## The visualiser running on the card (null before the card is built).
func visualiser() -> VisualiserHost:
	return _vis


## The visualiser's area on the card for an area kind ("strip", "tall", "backdrop"), with or without a cover.
static func area_rect(kind: String, with_cover: bool) -> Rect2:
	var s := Vector2(CARD_SIZE)
	if kind == "backdrop":
		return Rect2(Vector2.ZERO, s)
	if not with_cover:
		return Rect2(s.x * 0.08, s.y * 0.28, s.x * 0.84, s.y * 0.42)
	var text_x := s.x * 0.06 + s.y * 0.62 + s.x * 0.05
	if kind == "tall":
		return Rect2(text_x, s.y * 0.4, s.x - text_x - s.x * 0.06, s.y * 0.42)
	return Rect2(text_x, s.y * 0.56, s.x - text_x - s.x * 0.06, s.y * 0.2)


func close() -> void:
	_hold(false)
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
	var a := AudioAnalysis.shared
	var per := AudioAnalysis.BINS / BARS
	for i in BARS:
		var sum := 0.0
		if a != null and a.active():
			for j in per:
				sum += a.smooth[i * per + j]
		_levels[i] = sum / per
	_show_visualiser()
	if _text != null:
		_text.queue_redraw()
	if not _drawn:
		_drawn = true
		format_changed.emit()


## Starts the chosen visualiser when it changed, and places its area.
func _show_visualiser() -> void:
	if _vis == null:
		return
	if style != OFF and style != _vis.id and not _vis.use(style):
		push_warning("Music: no visualiser %s" % style)
		style = OFF
	var on := style != OFF
	_vis_rect.visible = on
	_vis.set_active(on)
	_vis.playing = _playing
	if on:
		var r := area_rect(str(_vis.entry.get("area", "strip")), _cover_tex != null)
		_vis_rect.position = r.position
		_vis_rect.size = r.size
		_vis.set_area(r.size)
		_text.backdrop = r.size == Vector2(CARD_SIZE)
	else:
		_text.backdrop = false


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


## The card's background (the visualiser's TextureRect and CardText are drawn over it).
class MusicCard extends Control:
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)


## The words over the visualiser: cover on the left, title, artist and album on the right, the time line at the
## bottom. Without a cover the words start further left. Over a backdrop visualiser, dark panels keep them readable.
class CardText extends Control:
	const SCRIM := Color(0.0, 0.0, 0.0, 0.5)
	var source: Object
	var cover_tex: Texture2D
	var backdrop := false
	var _font: Font = ThemeDB.fallback_font

	func _draw() -> void:
		var s := size
		var text_x := s.x * 0.08
		if cover_tex != null:
			var side := s.y * 0.62
			var at := Vector2(s.x * 0.06, (s.y - side) * 0.5 - s.y * 0.04)
			draw_texture_rect(cover_tex, Rect2(at, Vector2(side, side)), false)
			text_x = at.x + side + s.x * 0.05
		var title_size := int(s.y * 0.075)
		var y := s.y * 0.2 if cover_tex != null else s.y * 0.14
		var line_y := s.y * 0.88
		if backdrop:
			var lines := 1 + (1 if str(source.artist) != "" else 0) + (1 if str(source.album) != "" else 0)
			draw_rect(Rect2(text_x - s.x * 0.02, y - title_size * 1.1, s.x - text_x - s.x * 0.04,
					title_size * (0.5 + 0.95 * lines)), SCRIM)
			draw_rect(Rect2(s.x * 0.06, line_y - s.y * 0.03, s.x * 0.88, s.y * 0.11), SCRIM)
		draw_string(_font, Vector2(text_x, y), str(source.title), HORIZONTAL_ALIGNMENT_LEFT, s.x - text_x - 40.0,
				title_size, Color(0.95, 0.95, 0.97))
		if str(source.artist) != "":
			draw_string(_font, Vector2(text_x, y + title_size * 1.2), str(source.artist), HORIZONTAL_ALIGNMENT_LEFT,
					s.x - text_x - 40.0, int(title_size * 0.7), Color(0.8, 0.82, 0.86))
		if str(source.album) != "":
			draw_string(_font, Vector2(text_x, y + title_size * 2.1), str(source.album), HORIZONTAL_ALIGNMENT_LEFT,
					s.x - text_x - 40.0, int(title_size * 0.55), Color(0.6, 0.62, 0.66))
		# Time line.
		var d: float = source.get_duration()
		var p: float = source.get_position()
		draw_rect(Rect2(s.x * 0.08, line_y, s.x * 0.84, 4.0), Color(0.25, 0.25, 0.28))
		if d > 0.0:
			draw_rect(Rect2(s.x * 0.08, line_y, s.x * 0.84 * clampf(p / d, 0.0, 1.0), 4.0), Color(0.9, 0.9, 0.95))
		draw_string(_font, Vector2(s.x * 0.08, line_y + s.y * 0.06), "%s / %s" % [_t(p), _t(d)],
				HORIZONTAL_ALIGNMENT_LEFT, -1, int(s.y * 0.035), Color(0.7, 0.72, 0.76))

	static func _t(sec: float) -> String:
		var t := int(sec)
		return "%d:%02d:%02d" % [t / 3600, (t / 60) % 60, t % 60] if t >= 3600 else "%d:%02d" % [t / 60, t % 60]
