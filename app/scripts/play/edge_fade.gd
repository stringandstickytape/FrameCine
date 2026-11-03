extends Node

## Edge fade for 3D (ideas #79): soft screen edges, so things that pop out of the screen don't get cut by its hard
## frame (a window violation). The picture fades to black over `width` of the screen's width at the left and right
## edges, and half of that at the top and bottom (video.gdshader's edge_fade). Only for flat stereo pictures; mono and
## spherical ones keep hard edges, and so does a 3D file shown as 2D (#59).
##
##   width        0 (off) .. MAX, fraction of the screen's width
##   set_width(w)
##   signal changed(width)
## Settings: [stereo] edge_fade (global, default off).

signal changed(width: float)

const MAX := 0.1
## A suggested value for the pane's "on" toggle.
const DEFAULT_ON := 0.03

var main: Node3D
var width := 0.0


func _ready() -> void:
	width = clampf(float(main.settings.get_value("stereo", "edge_fade", 0.0)), 0.0, MAX)
	main.mode_changed.connect(func(_m: Variant, _a: String) -> void: _apply())
	main.features.two_d.changed.connect(func(_e: int) -> void: _apply())
	_apply()


func set_width(w: float) -> void:
	width = clampf(w, 0.0, MAX)
	main.settings.set_value("stereo", "edge_fade", snappedf(width, 0.001) if width > 0.0 else null)
	_apply()


## Whether the fade applies to what is on screen now.
func applies() -> bool:
	return width > 0.0 and main.mode.is_stereo() and not main.mode.is_spherical() and main.features.two_d.eye < 0


func _apply() -> void:
	main.screen.material.set_shader_parameter("edge_fade", width if applies() else 0.0)
	changed.emit(width)
