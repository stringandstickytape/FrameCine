extends RefCounted

## A source of video frames as the two NV12 planes video.gdshader samples (Y; interleaved CbCr at half size, read as
## .r / .ra), plus the clock, seeking and audio the player needs. Implementations:
##   hw_video_source.gd    HWVideoTexture (+ MediaSource when the engine has it): hardware decode, zero copy.
##   stub_video_source.gd  generated test patterns for desktop runs and for checking eye mapping in the headset.
##   window_video_source.gd a desktop window (the browser) through X11WindowSource: one RGB texture, no audio.
## The PlaybackController drives it: update() every frame with the audio clock (or -1 to run on the frame clock).
## Preload to use (no class_name, see video_mode.gd).

const VideoMode := preload("res://scripts/video_mode.gd")

## The frame size or visible rectangle changed (plane textures, visible_uv_rect and get_video_info() are current).
signal format_changed

var path := ""
var last_error := ""


## "hw", "stub", "window" or "none".
func get_kind() -> String:
	return "none"


## Called before open(); sources that need nodes in the tree (viewports) put them under host.
func attach(_host: Node) -> void:
	pass


func open(_path: String) -> Error:
	return ERR_UNAVAILABLE


func close() -> void:
	pass


func play() -> void:
	pass


func pause() -> void:
	pass


func is_playing() -> bool:
	return false


func can_seek() -> bool:
	return false


func seek(_seconds: float) -> void:
	pass


## Media time of the frame on screen, seconds.
func get_position() -> float:
	return 0.0


## Seconds; 0 if unknown.
func get_duration() -> float:
	return 0.0


## master_clock >= 0: show the frame for that media time (audio master); < 0: advance by delta while playing.
func update(_delta: float, _master_clock: float) -> void:
	pass


## True once a frame is ready to be shown (the player starts the clocks then).
func has_frame() -> bool:
	return false


func is_ended() -> bool:
	return false


func get_plane_texture(_plane: int) -> Texture2D:
	return null


## True when the planes are 10-bit P010 (R16 / R16G16) rather than 8-bit NV12 (R8 / R8G8): the shader reads them
## differently (shaders/video_common.gdshaderinc, `p010`).
func is_p010() -> bool:
	return false


## An RGB picture with sRGB values to show instead of the planes (a captured window), or null.
func get_rgb_texture() -> Texture2D:
	return null


## Visible rectangle in UV of the plane textures (the decoder pads the height to 32 lines).
func get_visible_uv_rect() -> Rect2:
	return Rect2(0, 0, 1, 1)


## {codec, width, height, fps, bit_depth}; width/height are the visible size.
func get_video_info() -> Dictionary:
	return {}


## The decoded audio as a stream for an AudioStreamPlayer, or null.
func get_audio_stream() -> AudioStream:
	return null


## [{index, codec, channels, language, title}]
func get_audio_tracks() -> Array[Dictionary]:
	return []


func select_audio_track(_index: int) -> void:
	pass


## The selected audio track's index, or -1.
func get_audio_track() -> int:
	return -1


func get_stats() -> Dictionary:
	return {}


## [{index, codec, language, title, text, bitmap, default, forced}] (MediaSource's get_subtitle_tracks()).
func get_subtitle_tracks() -> Array[Dictionary]:
	return []


## Selects a subtitle track (-1: none). Events of the new track come through read_subtitle_event().
func select_subtitle_track(_index: int) -> void:
	pass


func get_subtitle_track() -> int:
	return -1


## The next queued event of the selected track: {start, end (-1: until the next), text, ass, bitmap, serial}, or {}.
func read_subtitle_event() -> Dictionary:
	return {}


## Subtitle files next to the video (ideas #50): true when add_external_subtitle() can load them.
func supports_external_subtitles() -> bool:
	return false


## Loads a subtitle file (SubRip, ASS, WebVTT) as one more subtitle track; its index, or -1. Blocking (reads the file):
## any thread.
func add_external_subtitle(_file: String, _language := "", _title := "") -> int:
	return -1


## Read the video this many seconds further ahead while a file's own subtitle track is selected, so a negative
## subtitle delay still gets its lines in time (MediaSource.subtitle_read_ahead, 0..30).
func set_subtitle_read_ahead(_seconds: float) -> void:
	pass


## Playback speed (ideas #69), 0.5..2, pitch kept: the audio is time-stretched and the video follows it (or the frame
## clock runs this much faster without audio).
func set_playback_speed(_speed: float) -> void:
	pass


## Language memory through the engine (MediaSource.pick_audio_track / pick_subtitle_track): the best track for a
## preference list (codes or names, most preferred first), -1 for none, -2 when this source can't pick (the app's own
## matching is used then).
func pick_audio_track(_languages: PackedStringArray) -> int:
	return -2


func pick_subtitle_track(_languages: PackedStringArray, _forced_only := false) -> int:
	return -2


## [{index, start, end, title}] in media seconds, or [] (MediaSource's get_chapters() when the engine has it).
func get_chapters() -> Array[Dictionary]:
	return []


## A mode the source knows better than the file name (test patterns), or null.
func get_known_mode() -> VideoMode:
	return null


## True while the decoder works from a keyframe up to a seek target (the player holds the audio meanwhile).
func is_settling() -> bool:
	return false


## True while no more video comes until the audio plays, so the player must not hold the audio for a frame.
func is_audio_blocking_video() -> bool:
	return false
