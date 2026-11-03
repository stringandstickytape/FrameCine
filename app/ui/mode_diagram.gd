extends Button

## A mode choice drawn as a small layout diagram above its word (docs/ui-design.md, Picture tab): mono, side by side,
## top / bottom, flat, 180°, 360°, fisheye, dual fisheye 360. Toggle button; the diagram is in the accent while chosen. Colours are
## tokens.

const PaneStyle := preload("res://ui/pane_style.gd")

const DIAGRAM_HEIGHT := 26.0

var kind := "mono"
## The word under the diagram (Button.text stays empty: Godot centres it vertically).
var word: Label


func _init(p_kind := "mono", p_word := "") -> void:
	kind = p_kind
	toggle_mode = true
	set_meta("word", p_word)
	word = Label.new()
	word.text = p_word
	word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	word.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(word)


func _ready() -> void:
	custom_minimum_size = Vector2(76, PaneStyle.constant(&"button_height") + DIAGRAM_HEIGHT)
	word.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	word.offset_top = -30.0
	word.offset_bottom = -6.0
	toggled.connect(func(_on: bool) -> void: _restyle())
	_restyle()


func _restyle() -> void:
	word.theme_type_variation = &"AccentLabel" if button_pressed else &""
	queue_redraw()


func set_chosen(on: bool) -> void:
	set_pressed_no_signal(on)
	_restyle()


func _get_minimum_size() -> Vector2:
	return custom_minimum_size


func _draw() -> void:
	var colour := PaneStyle.color(&"diagram_on" if button_pressed else &"diagram")
	var w := 34.0
	var h := 20.0
	var r := Rect2(Vector2((size.x - w) * 0.5, 8.0), Vector2(w, h))
	var c := r.get_center()
	match kind:
		"mono", "flat":
			draw_rect(r, colour, false, 1.5)
		"sbs":
			draw_rect(Rect2(r.position, Vector2(w * 0.5 - 1.5, h)), colour, false, 1.5)
			draw_rect(Rect2(r.position + Vector2(w * 0.5 + 1.5, 0), Vector2(w * 0.5 - 1.5, h)), colour, false, 1.5)
		"tb":
			draw_rect(Rect2(r.position, Vector2(w, h * 0.5 - 1.5)), colour, false, 1.5)
			draw_rect(Rect2(r.position + Vector2(0, h * 0.5 + 1.5), Vector2(w, h * 0.5 - 1.5)), colour, false, 1.5)
		"180":
			draw_arc(c + Vector2(0, h * 0.5), h, PI, TAU, 24, colour, 1.5, true)
			draw_line(c + Vector2(-h, h * 0.5), c + Vector2(h, h * 0.5), colour, 1.5, true)
		"360":
			draw_arc(c, h * 0.5, 0.0, TAU, 32, colour, 1.5, true)
			draw_line(c + Vector2(-h * 0.5, 0), c + Vector2(h * 0.5, 0), colour, 1.0, true)
		"fisheye":
			draw_arc(c, h * 0.5, 0.0, TAU, 32, colour, 1.5, true)
			draw_arc(c, h * 0.22, 0.0, TAU, 24, colour, 1.0, true)
		"dualfisheye":
			# Two circles side by side, one lens looking each way.
			draw_arc(c - Vector2(w * 0.25, 0), h * 0.42, 0.0, TAU, 28, colour, 1.5, true)
			draw_arc(c + Vector2(w * 0.25, 0), h * 0.42, 0.0, TAU, 28, colour, 1.5, true)
