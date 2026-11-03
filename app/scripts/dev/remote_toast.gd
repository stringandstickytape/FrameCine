extends Label3D

## The toast for remote changes (permission_ring.gd): a short line of text placed in the world, 1.2 m in front of the
## head and below eye level, where the head looks when it appears. It is not head-locked: it stays where it appeared
## and fades after a few seconds. The last three lines stack. A fallback until the pane shows these itself with an
## Undo button (signal remote_change on the permission ring).

const SHOW_SECONDS := 4.0
const FADE_SECONDS := 0.5
const DISTANCE := 1.2
const DROP := 0.35
const MAX_LINES := 3
## Colours from the UI token set (docs/ui-design.md): text and muted.
const TEXT_COLOUR := Color("#E6EAEE")
const OUTLINE_COLOUR := Color("#0C0F13")

## scripts/main.gd (for the head pose)
var main: Node
var _lines: Array[String] = []
var _left := 0.0


func _ready() -> void:
	top_level = true
	no_depth_test = true
	render_priority = 10
	shaded = false
	double_sided = false
	billboard = BaseMaterial3D.BILLBOARD_DISABLED
	font_size = 36
	outline_size = 10
	pixel_size = 0.0007
	modulate = TEXT_COLOUR
	outline_modulate = OUTLINE_COLOUR
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	visible = false
	set_process(false)


## Shows a line (newest at the bottom). undoable adds how to undo it.
func show_text(text: String, undoable := false) -> void:
	var line := text
	if undoable:
		line += "   (undo: PC or Ctrl+Z)"
	_lines.append(line)
	while _lines.size() > MAX_LINES:
		_lines.pop_front()
	self.text = "\n".join(_lines)
	if not visible:
		_place()
	visible = true
	_left = SHOW_SECONDS
	modulate.a = 1.0
	set_process(true)


func _place() -> void:
	if main == null or not is_instance_valid(main) or main.camera == null:
		return
	var head: Transform3D = (main.camera as Camera3D).global_transform
	var fwd := -head.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 1e-3 else Vector3.FORWARD
	var pos := head.origin + fwd * DISTANCE + Vector3.DOWN * DROP
	# The text reads from its +Z side: +Z towards the head.
	global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), pos)


func _process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0:
		visible = false
		_lines.clear()
		set_process(false)
	elif _left < FADE_SECONDS:
		modulate.a = _left / FADE_SECONDS
