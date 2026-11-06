extends "res://scripts/video/video_source.gd"

## Test-pattern video for desktop runs (no hardware decoder) and for checking the per-eye mapping in the headset.
## A TestCard is drawn in a SubViewport, then encoded on the GPU into the same two NV12 planes the hardware decoder
## gives (BT.709 limited range, height padded to 32 lines, CbCr read as .r/.a), so the real video shader, crop and
## eye selection are exercised. The card redraws 10 times a second (timecode, moving markers).
## Paths: "stub://<mode id>" (see PATTERNS; any VideoMode id works), or a real file the hardware path couldn't open,
## shown as the pattern for the mode its name suggests, with the reason on the card.

const TestCard := preload("res://scripts/video/test_card.gd")
const ENCODE_SHADER := preload("res://shaders/nv12_encode.gdshader")
const SCHEME := "stub://"
const REDRAW_INTERVAL := 0.1
## Test subtitles (two text tracks): a line every SUB_EVERY seconds, SUB_LENGTH long, delivered up to SUB_AHEAD
## seconds ahead of the position like MediaSource's queue. After a seek, events starting before the target are not
## delivered (as with MediaSource).
const SUB_EVERY := 5.0
const SUB_LENGTH := 3.0
const SUB_AHEAD := 1.0
## Two silent test audio tracks (the stub plays no sound), so track choice and language memory can be tested.
const AUDIO_TRACKS: Array[Dictionary] = [
	{"index": 0, "stream_index": 1, "codec": "none", "channels": 2, "channel_layout": "stereo", "language": "eng",
			"title": "Test (silent)", "default": true},
	{"index": 1, "stream_index": 4, "codec": "none", "channels": 2, "channel_layout": "stereo", "language": "jpn",
			"title": "Test 2 (silent)", "default": false},
]
const SUB_TRACKS: Array[Dictionary] = [
	{"index": 0, "stream_index": 2, "codec": "subrip", "language": "eng", "title": "Test lines", "text": true,
			"bitmap": false, "default": false, "forced": false},
	{"index": 1, "stream_index": 3, "codec": "subrip", "language": "fre", "title": "Lignes de test", "text": true,
			"bitmap": false, "default": false, "forced": false},
]

## [mode id, label, width, height] -- typical frame sizes for each kind of content. The label is on a marked line, off
## the id's: it is a key (docs/i18n.md), and the Files tab's Test patterns place translates it.
const PATTERNS: Array = [
	["flat_mono",
			"Flat 2D", 1920, 1080], # i18n
	["flat_sbs",
			"Flat 3D, side by side (full)", 3840, 1080], # i18n
	["flat_sbs_half",
			"Flat 3D, side by side (half)", 1920, 1080], # i18n
	["flat_tb",
			"Flat 3D, top/bottom (full)", 1920, 2160], # i18n
	["flat_tb_half",
			"Flat 3D, top/bottom (half)", 1920, 1080], # i18n
	["180_mono",
			"180° mono", 2048, 2048], # i18n
	["180_sbs",
			"180° 3D, side by side", 4096, 2048], # i18n
	["360_mono",
			"360° mono", 3840, 1920], # i18n
	["360_tb",
			"360° 3D, top/bottom", 2880, 2880], # i18n
	["fisheye_mono",
			"Fisheye 180° mono", 2048, 2048], # i18n
	["fisheye_sbs",
			"Fisheye 180° 3D, side by side", 3840, 1920], # i18n
	["fisheye_sbs_fov200",
			"Fisheye 200° 3D, side by side", 3840, 1920], # i18n
	["dualfisheye_mono",
			"Dual fisheye 360° (front and back lens)", 3840, 1920], # i18n
]

var _host: Node
var _root: Node
var _card: TestCard
var _card_vp: SubViewport
var _y_vp: SubViewport
var _uv_vp: SubViewport
var _mode: VideoMode
var _known_mode: VideoMode
var _size := Vector2i(1920, 1080)
var _padded_height := 1088
var _position := 0.0
var _duration := 600.0
var _playing := false
var _since_redraw := 0.0
var _encode_frames := 0
var _frames := 0
var _redraws := 0
var _speed := 1.0
var _sub_track := -1
var _audio_track := 0
## Start time of the next subtitle event to deliver.
var _sub_cursor := 0.0
var _serial := 0


static func list_patterns() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p: Array in PATTERNS:
		out.append({"path": SCHEME + p[0], "label": p[1]})
	return out


static func is_stub_path(p: String) -> bool:
	return p.begins_with(SCHEME)


static func _default_size(mode: VideoMode) -> Vector2i:
	for p: Array in PATTERNS:
		if p[0] == mode.to_id():
			return Vector2i(p[2], p[3])
	for p: Array in PATTERNS:
		var m := VideoMode.from_id(p[0])
		if m.projection == mode.projection and m.layout == mode.layout and m.half == mode.half:
			return Vector2i(p[2], p[3])
	return Vector2i(1920, 1080)


func get_kind() -> String:
	return "stub"


func attach(host: Node) -> void:
	_host = host


func open(p_path: String) -> Error:
	path = p_path
	var id := p_path.trim_prefix(SCHEME)
	var label := id
	var size := Vector2i.ZERO
	for p: Array in PATTERNS:
		if p[0] == id:
			label = p[1]
			size = Vector2i(p[2], p[3])
	var mode := VideoMode.from_id(id)
	if size == Vector2i.ZERO:
		size = _default_size(mode)
	_known_mode = mode
	_duration = 600.0
	_build(mode, size, "Test pattern: " + label, "Generated NV12 %dx%d, no decoder" % [size.x, size.y])
	return OK


## Stands in for a real file the hardware path can't play here: the pattern for the mode its name suggests.
func open_placeholder(p_path: String, reason: String) -> Error:
	path = p_path
	last_error = reason
	var mode := VideoMode.guess(p_path.get_file())
	_known_mode = null
	_duration = 120.0
	_build(mode, _default_size(mode), p_path.get_file(), "Stand-in pattern: " + reason)
	return OK


func _build(mode: VideoMode, size: Vector2i, title: String, subtitle: String) -> void:
	close()
	_mode = mode
	_size = Vector2i(size.x / 2 * 2, size.y / 2 * 2)
	_padded_height = ceili(_size.y / 32.0) * 32
	_root = Node.new()
	_root.name = "StubVideo"
	_host.add_child(_root)

	_card_vp = SubViewport.new()
	_card_vp.size = _size
	_card_vp.disable_3d = true
	_card_vp.transparent_bg = false
	_card_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_card = _new_card()
	_card.mode = mode
	_card.title = title if title.length() <= 48 else title.left(45) + "..."
	_card.subtitle = subtitle
	_card.position = Vector2.ZERO
	_card.size = Vector2(_size)
	_card_vp.add_child(_card)
	_root.add_child(_card_vp)

	_y_vp = _make_encoder(Vector2i(_size.x, _padded_height), 0, false)
	_uv_vp = _make_encoder(Vector2i(_size.x / 2, _padded_height / 2), 1, true)
	_position = 0.0
	_frames = 0
	_since_redraw = REDRAW_INTERVAL
	format_changed.emit()


## The card drawn into the frame (lab_video_source.gd draws calibration cards instead).
func _new_card() -> TestCard:
	return TestCard.new()


func _make_encoder(vp_size: Vector2i, plane: int, keep_alpha: bool) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = vp_size
	vp.disable_3d = true
	# The CbCr plane keeps Cr in alpha.
	vp.transparent_bg = keep_alpha
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var mat := ShaderMaterial.new()
	mat.shader = ENCODE_SHADER
	mat.set_shader_parameter("card", _card_vp.get_texture())
	mat.set_shader_parameter("plane", plane)
	mat.set_shader_parameter("visible_v", float(_size.y) / float(_padded_height))
	var rect := ColorRect.new()
	rect.material = mat
	rect.position = Vector2.ZERO
	rect.size = Vector2(vp_size)
	vp.add_child(rect)
	_root.add_child(vp)
	return vp


func close() -> void:
	if _root != null:
		_root.queue_free()
	_root = null
	_card = null
	_card_vp = null
	_y_vp = null
	_uv_vp = null


func play() -> void:
	_playing = true


func pause() -> void:
	_playing = false


func is_playing() -> bool:
	return _playing


func can_seek() -> bool:
	return true


func seek(seconds: float) -> void:
	_position = clampf(seconds, 0.0, _duration)
	_since_redraw = REDRAW_INTERVAL
	_serial += 1
	_sub_cursor = ceilf(_position / SUB_EVERY) * SUB_EVERY


func get_position() -> float:
	return _position


func get_duration() -> float:
	return _duration


func update(delta: float, master_clock: float) -> void:
	if _card == null:
		return
	_frames += 1
	if _playing:
		_position = master_clock if master_clock >= 0.0 else _position + delta * _speed
		if _position >= _duration:
			_position = fmod(_position, _duration)
			_sub_cursor = 0.0
	_since_redraw += delta
	if _since_redraw >= REDRAW_INTERVAL:
		_since_redraw = 0.0
		_card.time = _position
		_card.queue_redraw()
		_card_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		# Viewports render in an unspecified order within a frame: encode on this frame and the next, so the
		# encoders always see the new card.
		_encode_frames = 2
		_redraws += 1
	if _encode_frames > 0:
		_encode_frames -= 1
		_y_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		_uv_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func has_frame() -> bool:
	return _card != null and _frames >= 3


func get_plane_texture(plane: int) -> Texture2D:
	if _y_vp == null:
		return null
	return _y_vp.get_texture() if plane == 0 else _uv_vp.get_texture()


func get_visible_uv_rect() -> Rect2:
	return Rect2(0, 0, 1, float(_size.y) / float(_padded_height))


func get_video_info() -> Dictionary:
	return {"codec": "test pattern (NV12)", "width": _size.x, "height": _size.y, "fps": 1.0 / REDRAW_INTERVAL,
			"bit_depth": 8}


func get_stats() -> Dictionary:
	return {"state_name": "stub", "frames_shown": _redraws, "frames_dropped": 0, "position": _position,
			"frame_time": _position}


## Moves on the redraw's frame and on the next (the planes are encoded on both).
func frame_key() -> float:
	return float(_redraws * 3 + _encode_frames)


func get_known_mode() -> VideoMode:
	return _known_mode


func get_audio_tracks() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _known_mode != null:
		out.assign(AUDIO_TRACKS.duplicate(true))
	return out


func select_audio_track(index: int) -> void:
	_audio_track = index


func get_audio_track() -> int:
	return _audio_track if _known_mode != null else -1


func set_playback_speed(speed: float) -> void:
	_speed = clampf(speed, 0.25, 4.0)


func get_subtitle_tracks() -> Array[Dictionary]:
	return SUB_TRACKS.duplicate(true)


## Five test chapters (none on the stand-in for a real file).
func get_chapters() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _known_mode == null:
		return out
	var titles := ["Opening", "Colour bars", "Motion", "Stereo check", "Closing"]
	var step := _duration / titles.size()
	for i in titles.size():
		out.append({"index": i, "start": i * step, "end": (i + 1) * step, "title": titles[i]})
	return out


func select_subtitle_track(index: int) -> void:
	_sub_track = index if index >= 0 and index < SUB_TRACKS.size() else -1
	# Like MediaSource: what was read before isn't delivered for the new track.
	_sub_cursor = ceilf((_position + SUB_AHEAD) / SUB_EVERY) * SUB_EVERY


func get_subtitle_track() -> int:
	return _sub_track


func read_subtitle_event() -> Dictionary:
	if _sub_track < 0 or _sub_cursor > _position + SUB_AHEAD or _sub_cursor >= _duration:
		return {}
	var start := _sub_cursor
	_sub_cursor += SUB_EVERY
	var n := int(start / SUB_EVERY) + 1
	var s := int(start)
	var clock := "%d:%02d" % [s / 60, s % 60]
	var text := ("Line %d at %s" if _sub_track == 0 else "Ligne %d à %s") % [n, clock]
	return {"start": start, "end": start + SUB_LENGTH, "text": text, "ass": "", "bitmap": false, "serial": _serial}
