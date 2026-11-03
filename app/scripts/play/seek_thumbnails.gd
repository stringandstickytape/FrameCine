extends Node

## Seek-bar thumbnails (ideas #40): while the seek bar is scrubbed or hovered, a small picture of the film near that
## time. A second decoder session on the open file (fork 347778e84c: its own MediaSource, no audio track, its own
## HWVideoTexture) jumps to the keyframe at or before the time with MediaSource.trick_play(), shows it, and stops;
## the picture is drawn once into a small viewport with the video shader and copied into an ImageTexture. Requests are
## throttled (one grab at a time, the newest request wins) and the last CACHE_SIZE pictures are kept, by keyframe.
## The session opens on the first request for a file and closes after IDLE_CLOSE_SECONDS without one, on another
## file, or when turned off. Off by default until the headset's memory is checked: a second set of decoder buffers is
## about 150 MB at 2160p.
##
##   enabled, set_enabled(on)          [thumbnails] enabled (default off)
##   request(seconds)                  the pane calls this as the hovered / scrubbed time changes
##   thumbnail_for(seconds) -> Texture2D   the cached picture nearest to `seconds` within NEAR_SECONDS, or null
##   size                              the pictures' size in pixels (WIDTH wide, the film's aspect)
##   state                             "off", "idle" (no session), "opening", "warming", "ready", "grabbing"
##   signal thumbnail_ready(seconds, texture)   seconds: the keyframe's time

const HWVideoSource := preload("res://scripts/video/hw_video_source.gd")
const VideoMode := preload("res://scripts/video_mode.gd")
const HdrToneMap := preload("res://scripts/play/hdr_tone_map.gd")
const VIDEO_SHADER := preload("res://shaders/video.gdshader")

signal thumbnail_ready(seconds: float, texture: Texture2D)

const WIDTH := 256
const CACHE_SIZE := 24
const NEAR_SECONDS := 6.0
const IDLE_CLOSE_SECONDS := 20.0
## Give up on a grab after this long (a file whose keyframes are far apart, a slow share).
const GRAB_TIMEOUT := 4.0

var main: Node3D
var enabled := false
var state := "off"
var size := Vector2i(WIDTH, 144)
var _media: Object = null
var _tex: Object = null
var _path := ""
var _open_id := 0
var _tasks: Array[int] = []
var _pending := -1.0
var _grab_for := -1.0
var _grab_time := 0.0
var _shown_before := 0
var _idle := 0.0
## [{t: keyframe seconds, asked: seconds, tex: ImageTexture}], newest last.
var _cache: Array[Dictionary] = []
var _vp: SubViewport
var _quad: MeshInstance3D
var _material: ShaderMaterial
var _render_wait := 0


func _ready() -> void:
	enabled = bool(main.settings.get_value("thumbnails", "enabled", false))
	state = "idle" if enabled else "off"
	_vp = SubViewport.new()
	_vp.name = "ThumbnailViewport"
	_vp.size = size
	_vp.own_world_3d = true
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.0
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.position = Vector3(0, 0, 1)
	_vp.add_child(cam)
	_quad = MeshInstance3D.new()
	_quad.mesh = QuadMesh.new()
	_material = ShaderMaterial.new()
	_material.shader = VIDEO_SHADER
	_material.set_shader_parameter("force_eye", 0)
	_quad.material_override = _material
	_vp.add_child(_quad)
	add_child(_vp)
	main.file_opened.connect(func(_p: String) -> void: _close_session())


func set_enabled(on: bool) -> void:
	enabled = on
	main.settings.set_value("thumbnails", "enabled", true if on else null)
	if not on:
		_close_session()
	state = "idle" if on else "off"


func request(seconds: float) -> void:
	if not enabled:
		return
	_idle = 0.0
	_pending = maxf(seconds, 0.0)
	if state == "idle":
		_open_session()


func thumbnail_for(seconds: float) -> Texture2D:
	var best: Dictionary = {}
	for e: Dictionary in _cache:
		var d := absf(float(e["asked"]) - seconds)
		if d <= NEAR_SECONDS and (best.is_empty() or d < absf(float(best["asked"]) - seconds)):
			best = e
	return best.get("tex") if not best.is_empty() else null


func _open_session() -> void:
	var src: Object = main.player.source
	if src == null or src.get_kind() != "hw" or not main.player.can_seek() or not ClassDB.class_has_method("MediaSource", "trick_play"):
		return
	_open_id += 1
	var id := _open_id
	var p: String = main.current_path
	_path = p
	state = "opening"
	_tasks.append(WorkerThreadPool.add_task(func() -> void:
		var result := HWVideoSource.open_media_blocking(p)
		_on_media.call_deferred(id, p, result), false, "thumbnails " + p))


func _on_media(id: int, p: String, result: Dictionary) -> void:
	for i in range(_tasks.size() - 1, -1, -1):
		if WorkerThreadPool.is_task_completed(_tasks[i]):
			WorkerThreadPool.wait_for_task_completion(_tasks[i])
			_tasks.remove_at(i)
	var media: Object = result.get("media")
	if id != _open_id or int(result.get("err", FAILED)) != OK:
		if media != null and media.has_method("close"):
			media.call("close")
		if id == _open_id:
			state = "idle"
		return
	if media.has_method("select_audio_track"):
		media.select_audio_track(-1)
	var tex: Object = ClassDB.instantiate("HWVideoTexture")
	HWVideoSource.apply_hw_vp9(tex)  # A VP9 film's own hardware session keeps this one in software.
	if tex.call("open_source", media) != OK:
		print("Thumbnails: can't open %s: %s" % [p, tex.call("get_last_error")])
		tex.call("close")
		media.call("close")
		state = "idle"
		return
	_media = media
	_tex = tex
	_bind()
	# Let it show its first frame before the first jump (a jump right after the open lands late).
	_tex.play()
	_grab_time = 0.0
	state = "warming"


func _bind() -> void:
	var info: Dictionary = _media.get_video_info()
	var w := int(info.get("width", 1920))
	var h := int(info.get("height", 1080))
	var m := VideoMode.guess(_path.get_file(), w, h)
	if main.mode != null and main.current_path == _path:
		m = main.mode
	var aspect := m.display_aspect(Vector2(w, h))
	if m.is_spherical():
		aspect = 2.0 if m.projection == VideoMode.Proj.EQUIRECT_360 else 1.0
	size = Vector2i(WIDTH, clampi(int(WIDTH / maxf(aspect, 0.25)), 32, 512))
	_vp.size = size
	(_quad.mesh as QuadMesh).size = Vector2(float(size.x) / size.y, 1.0)
	_material.set_shader_parameter("y_tex", _tex.get_plane_texture(0))
	_material.set_shader_parameter("uv_tex", _tex.get_plane_texture(1))
	var r: Rect2 = _tex.get_visible_uv_rect()
	_material.set_shader_parameter("visible_rect", Vector4(r.position.x, r.position.y, r.size.x, r.size.y))
	_material.set_shader_parameter("stereo_layout", int(m.layout))
	var d := HdrToneMap.describe(info)
	_material.set_shader_parameter("yuv_matrix", int(d.get("matrix", 0)))
	_material.set_shader_parameter("full_range", bool(d.get("full_range", false)))
	_material.set_shader_parameter("transfer", int(d.get("transfer", 0)))
	_material.set_shader_parameter("primaries_bt2020", bool(d.get("primaries_bt2020", false)))


func _process(delta: float) -> void:
	if state == "off" or state == "idle":
		return
	_idle += delta
	if _idle > IDLE_CLOSE_SECONDS and state != "grabbing":
		_close_session()
		return
	if _tex == null:
		return
	if state == "warming":
		_grab_time += delta
		_tex.update(delta, -1.0)
		if int(_tex.get_stats().get("frames_shown", 0)) > 0 or _grab_time > GRAB_TIMEOUT:
			_tex.pause()
			state = "ready"
		return
	if state == "ready" and _pending >= 0.0:
		var cached := thumbnail_for(_pending)
		if cached != null and _near_cached(_pending):
			_pending = -1.0
			return
		_grab_for = _pending
		_pending = -1.0
		_grab_time = 0.0
		_shown_before = int(_tex.get_stats().get("frames_shown", 0))
		_tex.play()
		_media.trick_play(2.0, _grab_for)
		state = "grabbing"
		return
	if state == "grabbing":
		_grab_time += delta
		_tex.update(delta, -1.0)
		if _render_wait > 0:
			_render_wait -= 1
			if _render_wait == 0:
				_store()
			return
		var st: Dictionary = _tex.get_stats()
		var shown: int = int(st.get("frames_shown", 0))
		var ft := float(st.get("frame_time", -1.0))
		# The keyframe at or before the time; a frame after it is left over from before the jump: wait for the next.
		var right := ft >= 0.0 and ft <= _grab_for + 0.05
		if shown > _shown_before and not right:
			_shown_before = shown
		if shown > _shown_before and right and not bool(st.get("settling", false)):
			_tex.pause()
			_bind()  # The planes and visible rectangle are known now.
			_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
			_render_wait = 2  # Drawn in the next frame; read it back in the one after.
		elif _grab_time > GRAB_TIMEOUT:
			_tex.pause()
			state = "ready"


## True when the cache already has the keyframe that `seconds` would show (asked for within 0.5 s).
func _near_cached(seconds: float) -> bool:
	for e: Dictionary in _cache:
		if absf(float(e["asked"]) - seconds) < 0.5:
			return true
	return false


func _store() -> void:
	var img := _vp.get_texture().get_image()
	var t := float(_tex.get_stats().get("frame_time", _grab_for))
	var it := ImageTexture.create_from_image(img)
	_cache.append({"t": t, "asked": _grab_for, "tex": it})
	while _cache.size() > CACHE_SIZE:
		_cache.pop_front()
	state = "ready"
	thumbnail_ready.emit(t, it)


func _close_session() -> void:
	_open_id += 1
	if _tex != null:
		_tex.close()
	if _media != null and _media.has_method("close"):
		_media.close()
	_tex = null
	_media = null
	_cache.clear()
	_pending = -1.0
	_render_wait = 0
	_material.set_shader_parameter("y_tex", null)
	_material.set_shader_parameter("uv_tex", null)
	state = "idle" if enabled else "off"


func _exit_tree() -> void:
	_close_session()
	for t in _tasks:
		WorkerThreadPool.wait_for_task_completion(t)
	_tasks.clear()
