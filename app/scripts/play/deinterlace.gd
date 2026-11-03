extends Node

## GPU deinterlace (ideas #95) for interlaced video (DVD rips, 1080i broadcast recordings): the two fields of each
## frame are shown one after the other at twice the frame rate, each with the other field's lines rebuilt in the
## shader (video_common.gdshaderinc's field_luma / field_chroma): "bob" interpolates straight down, "edge" along the
## best of three directions so diagonals stay smooth. Spatial only (no previous or next frame): lighter than a full
## temporal deinterlacer, and the decoder's frames are used as they are. Off by default.
##
##   mode                 "off", "bob", "edge", "auto" ([picture] deinterlace, default off); auto: edge when the file
##                        says it is interlaced (video info "field_order" tt / tb / bb / bt), else off
##   active() -> int      the shader's mode now (0 off, 1 bob, 2 edge)
##   top_first            the first field in time is the even lines (from field_order; default true)
##   static is_interlaced(order), top_field_first(order)   FFmpeg's field_order names (engine PLAYER_REQUESTS):
##                        "tt" and "bt" show the top field first, "bb" and "tb" the bottom one (the first letter is
##                        the field coded first, the second the one shown first)
##   set_mode(m)
##   signal changed(mode)

signal changed(mode: String)

const MODES := ["off", "bob", "edge", "auto"]

var main: Node3D
var mode := "off"
var top_first := true
var _active := 0
var _fps := 25.0


func _ready() -> void:
	mode = str(main.settings.get_value("picture", "deinterlace", "off"))
	if not mode in MODES:
		mode = "off"
	main.file_opened.connect(func(_p: String) -> void: _update())
	main.player.format_changed.connect(_update)
	_update()


func set_mode(m: String) -> void:
	mode = m if m in MODES else "off"
	main.settings.set_value("picture", "deinterlace", null if mode == "off" else mode)
	_update()


func active() -> int:
	return _active


static func is_interlaced(order: String) -> bool:
	return order.to_lower() in ["tt", "tb", "bb", "bt"]


## The field shown first is the top one (even lines). FFmpeg's AVFieldOrder: TT top coded and shown first, BB bottom
## both, TB top coded first but bottom shown first, BT bottom coded first but top shown first. Unknown: top.
static func top_field_first(order: String) -> bool:
	return not order.to_lower() in ["bb", "tb"]


func _update() -> void:
	var info: Dictionary = main.player.source.get_video_info() if main.player.source != null else {}
	var order := str(info.get("field_order", "")).to_lower()
	var interlaced := is_interlaced(order)
	top_first = top_field_first(order)
	_fps = float(info.get("fps", 0.0))
	if _fps <= 0.0:
		_fps = 25.0
	match mode:
		"bob":
			_active = 1
		"edge":
			_active = 2
		"auto":
			_active = 2 if interlaced else 0
		_:
			_active = 0
	var m: ShaderMaterial = main.screen.material
	if m != null:
		m.set_shader_parameter("deinterlace", _active)
	changed.emit(mode)


## The field for the moment on screen: the first field in the frame's first half, the second in its second half.
static func field_at(position: float, fps: float, p_top_first: bool) -> int:
	var first := 0 if p_top_first else 1
	return first if fmod(position * fps, 1.0) < 0.5 else 1 - first


func _process(_delta: float) -> void:
	if _active == 0 or not main.player.has_source():
		return
	main.screen.material.set_shader_parameter("field", field_at(main.player.get_position(), _fps, top_first))
