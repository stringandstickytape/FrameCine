extends Label3D

## What to do now, on a card over the controller in use, for as long as a task with steps lasts (marking or editing a
## window to the real room, scripts/play/real_windows.gd hint()). A notice (world_toast.gd) is placed once where the
## head looked and fades in seconds: the steps' instructions kept going while the viewer looked down at the table
## (the user, 2026-11-06). The card follows the controller, a little above it, turned to the head, and stays until the
## task ends. Text, outline and font from the pane's tokens (ui/pane_style.gd). The text shows as given: the caller
## translates it (docs/i18n.md).
##
##   show_over(hand, head, text)   each frame while the task lasts; hide_hint() after

const PaneStyle := preload("res://ui/pane_style.gd")
const W := preload("res://ui/pane_widgets.gd")

## Metres above the controller, and the line width in pixels before it wraps.
const LIFT := 0.075
const WIDTH := 520.0


func _ready() -> void:
	name = "HandHint"
	W.content(self)
	top_level = true
	no_depth_test = true
	render_priority = 10
	shaded = false
	double_sided = false
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	font = PaneStyle.font(&"medium")
	font_size = 26
	outline_size = 8
	pixel_size = 0.00042
	modulate = PaneStyle.color(&"text")
	outline_modulate = PaneStyle.color(&"surface")
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	width = WIDTH
	visible = false


func show_over(hand: Node3D, head: Node3D, line: String) -> void:
	if hand == null or line == "":
		hide_hint()
		return
	if text != line:
		text = line
	var at := hand.global_position + Vector3.UP * LIFT
	# A little towards the head, so the controller's own model doesn't cover the card's lower edge.
	if head != null:
		at += (head.global_position - at).normalized() * 0.02
	global_position = at
	visible = true


func hide_hint() -> void:
	visible = false
