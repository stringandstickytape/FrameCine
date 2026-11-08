extends "res://scripts/video/video_source.gd"

## A PC window on the big screen (docs/pc-windows.md, "Show on the big screen"): the pane's own decoder (pc_video.gd),
## shown where the film goes, so the room's presentation applies as to a film. The pane keeps decoding and updating
## it (pc_windows.gd); this source only hands the screen its planes. No audio here: the PC's sound has its own player
## (pc_sound.gd), which moves to the big screen meanwhile. Flat 2D, no seeking, never ends by itself.
##   pcwindow://<client id>/<window id>
## Closing it (another file opened, Stop) gives the window back to its pane.

const PREFIX := "pcwindow://"

## pc_windows.gd: path -> the pane's PcVideo, or null; and the call when the screen lets go of a window.
static var find_video := Callable()
static var released := Callable()

var _video: RefCounted
var _closed := false


static func is_pc_path(p: String) -> bool:
	return p.begins_with(PREFIX)


static func path_for(client_id: String, window_id: String) -> String:
	return PREFIX + client_id + "/" + window_id


func get_kind() -> String:
	return "pc"


func open(p_path: String) -> Error:
	path = p_path
	_video = find_video.call(p_path) if find_video.is_valid() else null
	if _video == null:
		last_error = "That PC window isn't open in the headset."
		return ERR_UNAVAILABLE
	_video.format_changed.connect(_on_format)
	return OK


func _on_format() -> void:
	format_changed.emit()


func close() -> void:
	if _closed:
		return
	_closed = true
	if _video != null and _video.format_changed.is_connected(_on_format):
		_video.format_changed.disconnect(_on_format)
	_video = null
	if released.is_valid():
		released.call(path)


func play() -> void:
	pass


func is_playing() -> bool:
	return _video != null


func has_frame() -> bool:
	return _video != null and _video.has_frame()


func get_plane_texture(plane: int) -> Texture2D:
	return _video.get_plane_texture(plane) if _video != null else null


func is_p010() -> bool:
	return _video != null and _video.is_p010()


func get_visible_uv_rect() -> Rect2:
	return _video.get_visible_uv_rect() if _video != null else Rect2(0, 0, 1, 1)


func get_video_info() -> Dictionary:
	var s: Vector2i = _video.size() if _video != null else Vector2i.ZERO
	return {"codec": "pc", "width": s.x, "height": s.y, "fps": 0.0, "bit_depth": 10 if is_p010() else 8}


func frame_key() -> float:
	return _video.frame_time() if _video != null else NAN


func get_known_mode() -> VideoMode:
	return VideoMode.new()


## The window pixels of the picture on the screen.
func get_size() -> Vector2i:
	return _video.size() if _video != null else Vector2i.ZERO
