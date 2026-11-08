extends RefCounted

## A PC window's picture (docs/pc-windows.md): the decoder side of one video stream, on the main thread. The stream's
## reader (pc_stream.gd) fills a MediaSource in stream mode; here an HWVideoTexture of the engine fork decodes it, as
## a film's is decoded (V4L2 in hardware on the Frame, FFmpeg in software on a desktop), and shows each frame at its
## time on the PC's clock plus the delay (pc_clock.gd). The pane's material samples get_plane_texture() 0 and 1 (NV12,
## or P010 for Main 10: is_p010()).
## A new MediaSource (a config change: a new size or codec) gets a texture of its own, which decodes alongside; once it
## has a frame it takes over the plane textures (HWVideoTexture.swap_planes_with()), so the material never changes
## and the picture never goes black.

signal format_changed

var _tex: Object
var _next: Object
var _source: Object
var _next_source: Object
var _size := Vector2i.ZERO
var _error := ""
var _opened := 0


static func available() -> bool:
	return ClassDB.class_exists("HWVideoTexture") and ClassDB.class_exists("MediaSource") \
			and ClassDB.class_has_method("MediaSource", "open_stream")


## A source from the stream's reader (its first key frame pushed): decode it.
func use_source(source: Object) -> void:
	var tex: Object = ClassDB.instantiate("HWVideoTexture")
	if tex.call("open_source", source) != OK:
		_error = str(tex.call("get_last_error"))
		push_warning("PC windows: the stream's decoder did not open: %s" % _error)
		return
	tex.call("play")
	_opened += 1
	if _tex == null:
		_tex = tex
		_source = source
		_tex.connect("format_changed", _on_format)
	else:
		if _next != null:
			_next.call("close")
		_next = tex
		_next_source = source


## One frame: `clock` is the PC time to show (pc_clock.gd now()).
func update(delta: float, clock: float) -> void:
	if _tex == null:
		return
	_tex.call("update", delta, clock)
	if _next != null:
		_next.call("update", delta, clock)
		if bool(_next.call("has_frame")):
			# The new size is decoding: it takes the plane textures the material samples.
			_tex.call("swap_planes_with", _next)
			_tex.disconnect("format_changed", _on_format)
			_tex.call("close")
			_tex = _next
			_source = _next_source
			_next = null
			_next_source = null
			_tex.connect("format_changed", _on_format)
			_on_format()


func _on_format() -> void:
	var r: Rect2i = _tex.call("get_visible_rect")
	_size = r.size
	format_changed.emit()


func has_frame() -> bool:
	return _tex != null and bool(_tex.call("has_frame"))


## The picture's pixels (the visible rectangle), or 0 x 0 before the first frame.
func size() -> Vector2i:
	return _size


func get_plane_texture(plane: int) -> Texture2D:
	return _tex.call("get_plane_texture", plane) if _tex != null else null


func is_p010() -> bool:
	return _tex != null and int(_tex.call("get_packing")) == 3  # HWVideoTexture.PACKING_P010


func get_visible_uv_rect() -> Rect2:
	return _tex.call("get_visible_uv_rect") if _tex != null else Rect2(0, 0, 1, 1)


## The time of the frame on show (PC seconds), or -1.
func frame_time() -> float:
	return float(_tex.call("get_frame_time")) if _tex != null else -1.0


## The decoder lost its place (access units dropped, a decoder error): the stream should start again from a key frame.
func wants_key_frame() -> bool:
	if _source != null and bool(_source.call("is_keyframe_wanted")):
		return true
	if _tex != null:
		var st: Dictionary = _tex.call("get_stats")
		return str(st.get("state_name", "")) == "error"
	return false


## "hardware" or "software" (HWVideoTexture.get_decode_path()), or "".
func decode_path() -> String:
	return str(_tex.call("get_decode_path")) if _tex != null else ""


func stats() -> Dictionary:
	var out := {"opened": _opened, "error": _error, "size": [_size.x, _size.y], "path": decode_path()}
	if _tex != null:
		var st: Dictionary = _tex.call("get_stats")
		for k: String in ["frames_shown", "frames_dropped", "frames_stale", "frames_decoded", "state_name"]:
			if st.has(k):
				out[k] = st[k]
		out["frame_time"] = frame_time()
	return out


## A new stream for the same window: what decodes now goes; the next source starts afresh (new plane textures, so
## format_changed tells the pane and the big screen to take them).
func reset() -> void:
	if _tex != null and _tex.is_connected("format_changed", _on_format):
		_tex.disconnect("format_changed", _on_format)
	close()


func close() -> void:
	for t: Object in [_next, _tex]:
		if t != null:
			t.call("close")
	for s: Object in [_next_source, _source]:
		if s != null:
			s.call("close")
	_tex = null
	_next = null
	_source = null
	_next_source = null
