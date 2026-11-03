extends Control

## The seek bar (docs/ui-design.md, "Inside the pane"): a 2 px track, the played part in the accent, chapter ticks,
## a 12 px knob. Click to seek, drag to scrub (the seek happens on release). Colours and sizes are tokens.

const PaneStyle := preload("res://ui/pane_style.gd")

signal seek_requested(seconds: float)
signal scrub_changed(seconds: float)
## The time under the pointer while it hovers (not scrubbing), or -1 when it leaves.
signal hover_changed(seconds: float)

var position_s := 0.0
var duration := 0.0
var can_seek := false
## Chapter starts as fractions of the duration.
var ticks: PackedFloat32Array = []
var scrubbing := false
## False: a thin progress line only (the glance view).
var show_knob := true
var _scrub_to := 0.0
var _hover := false


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _ready() -> void:
	custom_minimum_size = Vector2(0, PaneStyle.constant(&"seek_height"))
	mouse_entered.connect(func() -> void:
		_hover = true
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hover = false
		hover_changed.emit(-1.0)
		queue_redraw())
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func set_state(p_position: float, p_duration: float, p_can_seek: bool) -> void:
	if is_equal_approx(p_position, position_s) and is_equal_approx(p_duration, duration) and p_can_seek == can_seek:
		return
	position_s = p_position
	duration = p_duration
	can_seek = p_can_seek
	queue_redraw()


func set_ticks(p_ticks: PackedFloat32Array) -> void:
	ticks = p_ticks
	queue_redraw()


func shown_position() -> float:
	return _scrub_to if scrubbing else position_s


func _fraction() -> float:
	return clampf(shown_position() / duration, 0.0, 1.0) if duration > 0.0 else 0.0


func _draw() -> void:
	var knob := float(PaneStyle.constant(&"seek_knob"))
	var track := float(PaneStyle.constant(&"seek_track"))
	var x0 := knob * 0.5
	var w := size.x - knob
	var y := size.y * 0.5
	draw_rect(Rect2(x0, y - track * 0.5, w, track), PaneStyle.color(&"seek_track"))
	var f := _fraction()
	draw_rect(Rect2(x0, y - track * 0.5, w * f, track), PaneStyle.color(&"seek_played"))
	var tick_colour := PaneStyle.color(&"seek_tick")
	for t in ticks:
		if t > 0.0 and t < 1.0:
			draw_rect(Rect2(x0 + w * t - 0.5, y - track * 2.0, 1.0, track * 4.0), tick_colour)
	if duration > 0.0 and show_knob:
		var r := knob * 0.5 * (1.25 if (_hover or scrubbing) and can_seek else 1.0)
		draw_circle(Vector2(x0 + w * f, y), r, PaneStyle.color(&"seek_knob"), true, -1.0, true)
	if has_focus():
		var box := get_theme_stylebox(&"focus", &"Button")
		draw_style_box(box, Rect2(Vector2.ZERO, size))


## Where a time is along the bar (local x), for the thumbnail above it.
func x_of(t: float) -> float:
	var knob := float(PaneStyle.constant(&"seek_knob"))
	return knob * 0.5 + (clampf(t / duration, 0.0, 1.0) if duration > 0.0 else 0.0) * maxf(size.x - knob, 1.0)


func _time_at(x: float) -> float:
	var knob := float(PaneStyle.constant(&"seek_knob"))
	return clampf((x - knob * 0.5) / maxf(size.x - knob, 1.0), 0.0, 1.0) * duration


func _gui_input(event: InputEvent) -> void:
	if not can_seek or duration <= 0.0:
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			scrubbing = true
			_scrub_to = _time_at(mb.position.x)
			scrub_changed.emit(_scrub_to)
		elif scrubbing:
			scrubbing = false
			_scrub_to = _time_at(mb.position.x)
			seek_requested.emit(_scrub_to)
		queue_redraw()
		accept_event()
		return
	var mm := event as InputEventMouseMotion
	if mm != null and scrubbing:
		_scrub_to = _time_at(mm.position.x)
		scrub_changed.emit(_scrub_to)
		queue_redraw()
		accept_event()
		return
	if mm != null:
		hover_changed.emit(_time_at(mm.position.x))
	# Docked focus: left / right step 10 s.
	if event.is_action_pressed(&"ui_left") or event.is_action_pressed(&"ui_right"):
		var step := -10.0 if event.is_action_pressed(&"ui_left") else 10.0
		seek_requested.emit(clampf(position_s + step, 0.0, duration))
		accept_event()
