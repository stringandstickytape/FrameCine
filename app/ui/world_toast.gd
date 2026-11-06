extends Label3D

## A quiet line of text in the world for when the pane is not open (a controller battery running low, #75): placed
## once, 1.2 m ahead where the head looks and a little below, never head-locked; it fades after a few seconds. Text,
## outline and font come from the pane's tokens (ui/pane_style.gd). The text shows as given: the caller translates it
## (docs/i18n.md), and a name in it stays as it is.

const PaneStyle := preload("res://ui/pane_style.gd")
const W := preload("res://ui/pane_widgets.gd")

const SHOW_SECONDS := 5.0
const FADE_SECONDS := 0.6
const DISTANCE := 1.2
const DROP := 0.3

## The camera to place it by.
var head: Node3D
var _left := 0.0


func _ready() -> void:
	W.content(self)
	top_level = true
	no_depth_test = true
	render_priority = 10
	shaded = false
	double_sided = false
	font = PaneStyle.font(&"medium")
	font_size = 32
	outline_size = 8
	pixel_size = 0.0007
	modulate = PaneStyle.color(&"text")
	outline_modulate = PaneStyle.color(&"surface")
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	visible = false
	set_process(false)


## Shows a line for `seconds` (INF: until hide_now()).
func show_text(line: String, seconds := SHOW_SECONDS) -> void:
	text = line
	if head != null and is_instance_valid(head):
		var h := head.global_transform
		var fwd := -h.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized() if fwd.length() > 1e-3 else Vector3.FORWARD
		# The text reads from its +Z side: +Z toward the head.
		global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), h.origin + fwd * DISTANCE + Vector3.DOWN * DROP)
	visible = true
	modulate.a = 1.0
	_left = seconds
	set_process(true)


func hide_now() -> void:
	_left = minf(_left, FADE_SECONDS)


func _process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0:
		visible = false
		set_process(false)
	elif _left < FADE_SECONDS:
		modulate.a = _left / FADE_SECONDS
