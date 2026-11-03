extends Node

## Crossfade between items (ideas #94) when the queue goes on by itself (continuous play or a --dir run, #78): the
## next item starts `seconds` before the current one ends, on a second session, and the two overlap. Its sound comes up
## as the current one's goes down (equal power), and its picture (a film, or a music file's card) fades in over the
## screen on a quad just in front of it. At the end the next item becomes the open file (main.adopt_next(), as the
## gapless change does) and the overlay goes.
##   Music:  [crossfade] music seconds (0 to 12, default 0: off; music then goes straight on, as before).
##   Videos: [crossfade] videos seconds (0 to 10, default 0: off; the gapless change, #44, then applies).
## Pictures in a slideshow already crossfade by themselves ([images] crossfade, scripts/play/image_source.gd).
##
## The next item opens on a worker thread OPEN_LEAD seconds before the fade, plays muted into a second
## AudioStreamPlayer on the same bus, and is updated by this node with that player's clock until it is adopted.
## Video to video and music to music only; flat screens only for the picture (in 180 and 360 only the sound fades).
## Not with repeat "one" or a sleep timer at the end of the file.
##
##   music_seconds, set_music_seconds(s), video_seconds, set_video_seconds(s)
##   active                       a fade is running (or the next item is opening)
##   progress                     0..1 through the fade
##   next_path
##   signal changed(active, next_path)

const HWVideoSource := preload("res://scripts/video/hw_video_source.gd")
const VideoSourceFactory := preload("res://scripts/video/video_source_factory.gd")
const MusicSource := preload("res://scripts/play/music_source.gd")
const VideoMode := preload("res://scripts/video_mode.gd")
const HdrToneMap := preload("res://scripts/play/hdr_tone_map.gd")
const Gapless := preload("res://scripts/play/gapless.gd")
const FADE_SHADER := preload("res://shaders/video_fade.gdshader")

signal changed(active: bool, next_path: String)

const OPEN_LEAD := 2.0
## Hand over this long before the end (over a frame at 10 fps): the outgoing item is silent and hidden by then. The
## outgoing source holds its end meanwhile (hold_end), so a last frame shown early can't end it first.
const HANDOVER := 0.2

var main: Node3D
var music_seconds := 0.0
var video_seconds := 0.0
var active := false
var progress := 0.0
var next_path := ""
var overlay: MeshInstance3D
var material: ShaderMaterial
var _next: Object = null
var _player2: AudioStreamPlayer
var _main_db := 0.0
var _open_id := 0
var _tasks: Array[int] = []
var _from: Object = null
var _seconds := 0.0
var _started := false


func _ready() -> void:
	music_seconds = clampf(float(main.settings.get_value("crossfade", "music", 0.0)), 0.0, 12.0)
	video_seconds = clampf(float(main.settings.get_value("crossfade", "videos", 0.0)), 0.0, 10.0)
	material = ShaderMaterial.new()
	material.shader = FADE_SHADER
	overlay = MeshInstance3D.new()
	overlay.name = "CrossfadeOverlay"
	overlay.mesh = QuadMesh.new()
	overlay.material_override = material
	overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	overlay.position = Vector3(0, 0, 0.01)
	overlay.visible = false
	main.screen.add_child(overlay)
	_player2 = AudioStreamPlayer.new()
	_player2.name = "CrossfadeAudio"
	add_child(_player2)
	main.file_opened.connect(func(_p: String) -> void: _drop())


func set_music_seconds(s: float) -> void:
	music_seconds = clampf(s, 0.0, 12.0)
	main.settings.set_value("crossfade", "music", music_seconds if music_seconds > 0.0 else null)


func set_video_seconds(s: float) -> void:
	video_seconds = clampf(s, 0.0, 10.0)
	main.settings.set_value("crossfade", "videos", video_seconds if video_seconds > 0.0 else null)


## The next item and the fade length for the open file, or ["", 0].
func plan() -> Array:
	var src: Object = main.player.source
	var queue: Node = main.features.queue
	if src == null or main.features.sleep.holds_auto_advance() or queue.repeat == "one":
		return ["", 0.0]
	if not (queue.continuous or main.auto_advance):
		return ["", 0.0]
	if main.playlist_index < 0 or main.playlist_index + 1 >= main.playlist.size():
		return ["", 0.0]
	var p: String = main.playlist[main.playlist_index + 1]
	var kind: String = src.get_kind()
	if kind == "music" and music_seconds > 0.0 and MusicSource.is_music_path(p) and MusicSource.available():
		return [p, music_seconds]
	if kind == "hw" and video_seconds > 0.0 and Gapless.chainable(p) and not src.is_live():
		return [p, video_seconds]
	return ["", 0.0]


func _process(delta: float) -> void:
	var src: Object = main.player.source
	if src == null:
		return
	var left: float = main.player.get_duration() - main.player.get_position()
	if not active:
		if main.player.get_duration() <= 0.0 or not main.player.is_playing():
			return
		var pl := plan()
		if pl[0] != "" and left <= float(pl[1]) + OPEN_LEAD and left > float(pl[1]) * 0.5:
			_start(src, pl[0], pl[1])
		return
	if src != _from or left > _seconds + OPEN_LEAD + 1.0:
		_drop()  # Another file, or a seek back out of the window.
		return
	if _next == null:
		if left <= HANDOVER:
			_drop()  # Not open in time: the film ends and the queue goes on as before.
		return  # Still opening.
	var up_next: Node = main.features.up_next
	if up_next.following:
		up_next.set_remaining(left)
	progress = clampf(1.0 - (left - HANDOVER) / maxf(_seconds - HANDOVER, 0.01), 0.0, 1.0) if left <= _seconds else 0.0
	if progress > 0.0 and not _started:
		_started = true
		_next.play()
		if _player2.stream != null:
			_player2.play(0.0)
	var playing: bool = main.player.is_playing()
	if _started and playing != _next.is_playing():
		# Pause and play follow the film.
		if playing:
			_next.play()
		else:
			_next.pause()
		_player2.stream_paused = not playing
	var main_audio: AudioStreamPlayer = main.player.audio
	# Equal power: cos and sin of the progress, in amplitude.
	main_audio.volume_db = _main_db + linear_to_db(maxf(cos(progress * PI * 0.5), 0.0001))
	_player2.volume_db = _main_db + linear_to_db(maxf(sin(progress * PI * 0.5), 0.0001)) if progress > 0.0 else -80.0
	if _started:
		_next.update(delta, _player2.get_playback_position() if _player2.playing and not _player2.stream_paused else -1.0)
	material.set_shader_parameter("fade", progress)
	overlay.visible = progress > 0.0 and _next.has_frame() and main.mode.projection == VideoMode.Proj.FLAT
	if overlay.visible:
		_place()
	if left <= HANDOVER or main.player.source.is_ended():
		_hand_over()


func _start(src: Object, p: String, seconds: float) -> void:
	active = true
	progress = 0.0
	next_path = p
	_from = src
	_seconds = seconds
	_started = false
	if "hold_end" in src:
		src.set("hold_end", true)
	_main_db = main.player.audio.volume_db
	_open_id += 1
	var id := _open_id
	if src.get_kind() == "hw":
		var left: float = main.player.get_duration() - main.player.get_position()
		main.features.up_next.follow(p, left, _play_now, _cancelled)
	_tasks.append(WorkerThreadPool.add_task(func() -> void:
		var result := HWVideoSource.open_media_blocking(p)
		_on_media.call_deferred(id, p, result), false, "crossfade " + p))
	changed.emit(true, p)


func _on_media(id: int, p: String, result: Dictionary) -> void:
	for i in range(_tasks.size() - 1, -1, -1):
		if WorkerThreadPool.is_task_completed(_tasks[i]):
			WorkerThreadPool.wait_for_task_completion(_tasks[i])
			_tasks.remove_at(i)
	if id != _open_id or not active:
		var m: Object = result.get("media")
		if m != null and m.has_method("close"):
			m.call("close")
		return
	var nxt: Object = VideoSourceFactory.create_from_media(p, main.player, result)
	if nxt == null or not nxt.get_kind() in ["hw", "music"]:
		print("Crossfade: can't open %s" % p)
		if nxt != null:
			nxt.close()
		_drop()
		return
	_next = nxt
	_next.pause()
	_player2.stream = nxt.get_audio_stream()
	_player2.bus = main.player.audio.bus
	_player2.volume_db = -80.0
	_bind()


func _bind() -> void:
	for u: Dictionary in FADE_SHADER.get_shader_uniform_list():
		var n: String = u["name"]
		if n != "fade":
			material.set_shader_parameter(n, main.screen.material.get_shader_parameter(n))
	var rgb: Texture2D = _next.get_rgb_texture()
	if rgb != null:
		material.set_shader_parameter("rgb_source", true)
		material.set_shader_parameter("rgb_tex", rgb)
		material.set_shader_parameter("y_tex", null)
		material.set_shader_parameter("uv_tex", null)
	else:
		material.set_shader_parameter("rgb_source", false)
		material.set_shader_parameter("rgb_tex", null)
		material.set_shader_parameter("y_tex", _next.get_plane_texture(0))
		material.set_shader_parameter("uv_tex", _next.get_plane_texture(1))
		material.set_shader_parameter("p010", _next.is_p010())
	var r: Rect2 = _next.get_visible_uv_rect()
	material.set_shader_parameter("visible_rect", Vector4(r.position.x, r.position.y, r.size.x, r.size.y))
	var info: Dictionary = _next.get_video_info()
	var m: VideoMode = _next.get_known_mode() if _next.get_known_mode() != null \
			else VideoMode.guess(next_path.get_file(), int(info.get("width", 0)), int(info.get("height", 0)))
	material.set_shader_parameter("stereo_layout", int(m.layout))
	material.set_shader_parameter("swap_eyes", m.swap)
	if rgb == null:
		var d := HdrToneMap.describe(info)
		material.set_shader_parameter("yuv_matrix", int(d.get("matrix", 0)))
		material.set_shader_parameter("full_range", bool(d.get("full_range", false)))
		material.set_shader_parameter("transfer", int(d.get("transfer", 0)))
		material.set_shader_parameter("primaries_bt2020", bool(d.get("primaries_bt2020", false)))
	material.set_shader_parameter("zoom", 1.0)
	material.set_shader_parameter("pan", Vector2.ZERO)
	material.set_shader_parameter("fade", 0.0)
	if not _next.format_changed.is_connected(_on_next_format):
		_next.format_changed.connect(_on_next_format)
	_place()


func _on_next_format() -> void:
	if _next != null:
		_bind()


## The overlay at the next item's own shape, as wide as the screen (its height follows its aspect).
func _place() -> void:
	var s: Vector2 = main.screen.get_flat_size()
	var info: Dictionary = _next.get_video_info()
	var w := maxf(float(info.get("width", 16)), 1.0)
	var h := maxf(float(info.get("height", 9)), 1.0)
	var m: VideoMode = _next.get_known_mode() if _next.get_known_mode() != null else VideoMode.guess(next_path.get_file(), int(w), int(h))
	var aspect := m.display_aspect(Vector2(w, h))
	(overlay.mesh as QuadMesh).size = Vector2(s.x, s.x / maxf(aspect, 0.1))


func _hand_over() -> void:
	var nxt := _next
	var p := next_path
	var at: float = _player2.get_playback_position() if _player2.playing else nxt.get_position()
	_player2.stop()
	_player2.stream = null
	main.player.audio.volume_db = _main_db
	_next = null
	active = false
	overlay.visible = false
	nxt.update(0.0, at)
	nxt.play()
	print("Crossfade: %s takes over at %.2f s" % [p.get_file(), at])
	main.adopt_next(p, nxt)  # file_opened -> _drop() clears the rest.


func _play_now() -> void:
	_drop()
	main.next_file()


func _cancelled() -> void:
	_drop()


func _drop() -> void:
	_open_id += 1
	if _next != null:
		_next.close()
	_next = null
	if _player2.playing:
		_player2.stop()
	_player2.stream = null
	_player2.stream_paused = false
	_started = false
	if active:
		main.player.audio.volume_db = _main_db
		var up_next: Node = main.features.up_next
		if up_next.following:
			up_next._finish()
	overlay.visible = false
	material.set_shader_parameter("y_tex", null)
	material.set_shader_parameter("uv_tex", null)
	material.set_shader_parameter("rgb_tex", null)
	var was := active
	active = false
	progress = 0.0
	if _from != null and is_instance_valid(_from) and "hold_end" in _from:
		_from.set("hold_end", false)
	_from = null
	if was:
		next_path = ""
		changed.emit(false, "")


func _exit_tree() -> void:
	_drop()
	for t in _tasks:
		WorkerThreadPool.wait_for_task_completion(t)
	_tasks.clear()
