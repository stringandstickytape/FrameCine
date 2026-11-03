extends Node

## Picture in picture (ideas #87): a second video plays, silent, on a small screen in a corner of the main one, on a
## second decoder session (fork 347778e84c: a second HWVideoTexture on its own MediaSource). Swap puts it on the big
## screen with its sound, and the film that was there goes to the corner, both playing on where they were.
##
## The small screen is a quad with the video shader, a child of the screen node, so it moves, sizes and curves away
## with the screen; in 180 and 360 it floats where the flat screen's corner would be. Its MediaSource has no audio
## track selected (select_audio_track(-1)), so nothing is decoded or heard and its texture runs on its own clock. It
## pauses and plays with the main film. A stereo file shows its left eye (mono_eye). It closes at its end.
## Swap: PlaybackController.adopt() with the old source kept (main.adopt_next(path, src, true)); the audio tracks are
## switched over; the open-file bookkeeping runs for the swapped-in file (mode, subtitles; resume keeps its place).
## Video files only (not pictures, music, the lab or windows), and engine builds with MediaSource.
##
##   open(path)                         plays `path` in the corner (opens on a worker thread)
##   close(), swap() -> bool
##   state                              "", "opening", "playing"
##   path, source                       the corner's file and its VideoSource
##   size, set_size(f)                  [pip] size: the corner screen's width as a fraction of the screen's (0.15-0.5,
##                                      default 0.3)
##   corner, set_corner(c)              [pip] corner: "top_right" (default), "top_left", "bottom_right", "bottom_left"
##   signal changed(state, path)

const HWVideoSource := preload("res://scripts/video/hw_video_source.gd")
const VideoSourceFactory := preload("res://scripts/video/video_source_factory.gd")
const VideoMode := preload("res://scripts/video_mode.gd")
const HdrToneMap := preload("res://scripts/play/hdr_tone_map.gd")
const VIDEO_SHADER := preload("res://shaders/video.gdshader")

signal changed(state: String, path: String)

const CORNERS: Array[String] = ["top_right", "top_left", "bottom_right", "bottom_left"]
const MARGIN := 0.04  # Of the screen's width, from its edges.
const LIFT := 0.02  # Metres in front of the screen.

var main: Node3D
var state := ""
var path := ""
var source: Object = null
var size := 0.3
var corner := "top_right"
var quad: MeshInstance3D
var material: ShaderMaterial
var _audio_track := -1
var _open_id := 0
var _tasks: Array[int] = []
var _aspect := 16.0 / 9.0
var _placed_for := Vector2.ZERO


func _ready() -> void:
	size = clampf(float(main.settings.get_value("pip", "size", 0.3)), 0.15, 0.5)
	corner = str(main.settings.get_value("pip", "corner", "top_right"))
	if corner not in CORNERS:
		corner = "top_right"
	material = ShaderMaterial.new()
	material.shader = VIDEO_SHADER
	quad = MeshInstance3D.new()
	quad.name = "PictureInPicture"
	quad.mesh = QuadMesh.new()
	quad.material_override = material
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quad.visible = false
	main.screen.add_child(quad)
	main.player.playing_changed.connect(_on_playing_changed)
	main.screen_changed.connect(func(_w: float, _d: float, _h: float) -> void: _place())


func available() -> bool:
	return HWVideoSource.is_available() and HWVideoSource.has_media_source()


static func can_show(p: String) -> bool:
	if p == "" or p.begins_with("stub://") or p.begins_with("lab://") or HWVideoSource.is_raw_stream(p):
		return false
	if VideoSourceFactory.is_image_file(p) or VideoSourceFactory.is_music_file(p):
		return false
	return VideoSourceFactory.is_video_file(p) or HWVideoSource.is_stream_url(p) or p.begins_with("smb://")


func open(p: String) -> bool:
	if not available() or not can_show(p):
		return false
	close()
	_open_id += 1
	var id := _open_id
	path = p
	_set_state("opening")
	_tasks.append(WorkerThreadPool.add_task(func() -> void:
		var result := HWVideoSource.open_media_blocking(p)
		_on_media.call_deferred(id, p, result), false, "pip " + p))
	return true


func close() -> void:
	_open_id += 1
	if source != null:
		source.close()
	source = null
	quad.visible = false
	material.set_shader_parameter("y_tex", null)
	material.set_shader_parameter("uv_tex", null)
	path = ""
	_set_state("")


## The corner's film goes to the big screen with its sound, and the big screen's film to the corner. Both play on.
func swap() -> bool:
	var big: Object = main.player.source
	if state != "playing" or big == null or big.get_kind() != "hw" or not big.has_method("select_audio_track"):
		return false
	var big_path: String = main.current_path
	var big_track: int = big.get_audio_track()
	var small: Object = source
	var small_path := path
	var small_at: float = small.get_position()
	if _audio_track >= 0:
		small.select_audio_track(_audio_track)
	var old: Object = main.adopt_next(small_path, small, true)
	if old == null:
		return false
	old.select_audio_track(-1)
	# The audio track comes back from the demuxer's place, up to a second ahead of the picture: go back to the frame
	# that was showing, so the film carries on exactly where it was.
	if main.player.can_seek():
		main.player.seek(small_at)
	source = old
	path = big_path
	_audio_track = big_track
	_bind()
	print("Picture in picture: swapped, %s on the big screen" % small_path.get_file())
	_set_state("playing")
	return true


func set_size(f: float) -> void:
	size = clampf(f, 0.15, 0.5)
	main.settings.set_value("pip", "size", null if is_equal_approx(size, 0.3) else size)
	_place()
	changed.emit(state, path)


func set_corner(c: String) -> void:
	if c not in CORNERS:
		return
	corner = c
	main.settings.set_value("pip", "corner", null if c == "top_right" else c)
	_place()
	changed.emit(state, path)


func _on_media(id: int, p: String, result: Dictionary) -> void:
	for i in range(_tasks.size() - 1, -1, -1):
		if WorkerThreadPool.is_task_completed(_tasks[i]):
			WorkerThreadPool.wait_for_task_completion(_tasks[i])
			_tasks.remove_at(i)
	var media: Object = result.get("media")
	if id != _open_id:
		if media != null and media.has_method("close"):
			media.call("close")
		return
	var src: Object = VideoSourceFactory.create_from_media(p, self, result)
	if src == null or src.get_kind() != "hw":
		print("Picture in picture: can't play %s: %s" % [p, src.last_error if src != null else "?"])
		if src != null:
			src.close()
		path = ""
		_set_state("")
		return
	# Silent: no audio decoded, the texture on its own clock. The track is remembered for a swap.
	_audio_track = src.get_audio_track()
	src.select_audio_track(-1)
	source = src
	_bind()
	if main.player.is_playing():
		source.play()
	_set_state("playing")


func _bind() -> void:
	var info: Dictionary = source.get_video_info()
	var w := int(info.get("width", 1920))
	var h := int(info.get("height", 1080))
	var m := VideoMode.guess(path.get_file(), w, h)
	_aspect = m.display_aspect(Vector2(w, h))
	material.set_shader_parameter("y_tex", source.get_plane_texture(0))
	material.set_shader_parameter("uv_tex", source.get_plane_texture(1))
	var r: Rect2 = source.get_visible_uv_rect()
	material.set_shader_parameter("visible_rect", Vector4(r.position.x, r.position.y, r.size.x, r.size.y))
	material.set_shader_parameter("stereo_layout", int(m.layout))
	material.set_shader_parameter("mono_eye", 0 if m.layout != VideoMode.Layout.MONO else -1)
	var d := HdrToneMap.describe(info)
	material.set_shader_parameter("yuv_matrix", int(d.get("matrix", 0)))
	material.set_shader_parameter("full_range", bool(d.get("full_range", false)))
	material.set_shader_parameter("transfer", int(d.get("transfer", 0)))
	material.set_shader_parameter("primaries_bt2020", bool(d.get("primaries_bt2020", false)))
	if not source.format_changed.is_connected(_on_format_changed):
		source.format_changed.connect(_on_format_changed)
	_place()
	quad.visible = true


func _on_format_changed() -> void:
	if source != null:
		var r: Rect2 = source.get_visible_uv_rect()
		material.set_shader_parameter("visible_rect", Vector4(r.position.x, r.position.y, r.size.x, r.size.y))
		material.set_shader_parameter("y_tex", source.get_plane_texture(0))
		material.set_shader_parameter("uv_tex", source.get_plane_texture(1))


func _place() -> void:
	var screen: Node3D = main.screen
	var s: Vector2 = screen.get_flat_size()
	_placed_for = s
	var w := s.x * size
	var h := w / maxf(_aspect, 0.1)
	(quad.mesh as QuadMesh).size = Vector2(w, h)
	var m := s.x * MARGIN
	var x := s.x * 0.5 - w * 0.5 - m
	var y := s.y * 0.5 - h * 0.5 - m
	if corner.ends_with("left"):
		x = -x
	if corner.begins_with("bottom"):
		y = -y
	quad.position = Vector3(x, y, LIFT)


func _on_playing_changed(playing: bool) -> void:
	if source == null:
		return
	if playing:
		source.play()
	else:
		source.pause()


func _process(delta: float) -> void:
	if source == null or state != "playing":
		return
	source.update(delta, -1.0)
	if main.screen.get_flat_size() != _placed_for:
		_place()  # The big screen changed size (a new file, a mode, the crop, the width).
	if source.is_ended():
		print("Picture in picture: %s ended" % path.get_file())
		close()


func _set_state(s: String) -> void:
	state = s
	changed.emit(state, path)


func _exit_tree() -> void:
	close()
	for t in _tasks:
		WorkerThreadPool.wait_for_task_completion(t)
	_tasks.clear()
