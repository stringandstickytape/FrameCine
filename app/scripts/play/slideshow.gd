extends Node

## Slideshow of pictures (ideas #22). Pictures open like videos (scripts/play/image_source.gd) and the playlist is the
## folder's videos and pictures, so next / previous, shuffle and repeat (#78) work as for video. With the slideshow on,
## each picture shows for `seconds` and then the next one opens, crossfading from the last when it has the same
## shape; pause holds the picture. With it off, a picture stays until the user moves on.
##
##   enabled, seconds (2..60), crossfade (seconds, 0..3: 0 cuts)
##   set_enabled(on), set_seconds(s), set_crossfade(s)
##   is_picture() -> bool        a picture is showing
##   signal changed
## Settings: [images] slideshow, seconds, crossfade.

const ImageSource := preload("res://scripts/play/image_source.gd")

signal changed

var main: Node3D
var enabled := false
var seconds := 8.0
var crossfade := 1.0


func _ready() -> void:
	enabled = bool(main.settings.get_value("images", "slideshow", false))
	seconds = clampf(float(main.settings.get_value("images", "seconds", 8.0)), 2.0, 60.0)
	crossfade = clampf(float(main.settings.get_value("images", "crossfade", 1.0)), 0.0, 3.0)
	main.file_opened.connect(_on_file_opened)
	_push()


func is_picture() -> bool:
	return main.player.source != null and main.player.source.get_kind() == "image"


func set_enabled(on: bool) -> void:
	enabled = on
	main.settings.set_value("images", "slideshow", on)
	_push()
	if on and is_picture() and not main.player.is_playing():
		main.player.play()


func set_seconds(s: float) -> void:
	seconds = clampf(s, 2.0, 60.0)
	main.settings.set_value("images", "seconds", seconds)
	_push()


func set_crossfade(s: float) -> void:
	crossfade = clampf(s, 0.0, 3.0)
	main.settings.set_value("images", "crossfade", crossfade)
	_push()


func _push() -> void:
	ImageSource.slide_seconds = seconds if enabled else 0.0
	ImageSource.crossfade_seconds = crossfade
	if is_picture():
		main.player.source.set_duration(ImageSource.slide_seconds)
	changed.emit()


func _on_file_opened(_path: String) -> void:
	if not is_picture():
		ImageSource.forget_last()
