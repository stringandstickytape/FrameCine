extends RefCounted

## Builders for the pane's ordinary controls. Looks come from the theme (ui/themes/default.tres) by type variation;
## sizes from the tokens. Nothing here writes a colour or a font.

const PaneStyle := preload("res://ui/pane_style.gd")


static func label(text: String, variation := &"") -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


## An 11 px uppercase, letter-spaced label (sections, "Now playing").
static func caps(text: String) -> Label:
	var l := label(text, &"CapsLabel")
	l.uppercase = true
	return l


static func ellipsis(l: Label) -> Label:
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func button(text: String, on_pressed: Callable, variation := &"") -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.custom_minimum_size = Vector2(0, PaneStyle.constant(&"button_height"))
	if on_pressed.is_valid():
		b.pressed.connect(on_pressed)
	return b


## A button that stays pressed while its setting is on. on_toggled(on: bool) runs only for the user's changes.
static func toggle(text: String, on_toggled: Callable) -> Button:
	var b := button(text, Callable())
	b.toggle_mode = true
	b.toggled.connect(func(on: bool) -> void:
		if not b.has_meta("quiet"):
			on_toggled.call(on))
	return b


## Sets a toggle without running its callback.
static func set_on(b: Button, on: bool) -> void:
	b.set_pressed_no_signal(on)


## A row of mutually exclusive buttons. on_chosen(index) runs for the user's picks. Returns the HBoxContainer; its
## buttons are its children in order.
static func choices(names: Array, on_chosen: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", PaneStyle.constant(&"gap"))
	var group := ButtonGroup.new()
	for i in names.size():
		var b := button(str(names[i]), Callable())
		b.toggle_mode = true
		b.button_group = group
		var index := i
		b.pressed.connect(func() -> void: on_chosen.call(index))
		row.add_child(b)
	return row


static func set_choice(row: Container, index: int) -> void:
	var i := 0
	for c in row.get_children():
		if c is Button:
			(c as Button).set_pressed_no_signal(i == index)
			i += 1


## A slider row: name, slider, value. fmt(value) -> String gives the value text; on_change(value) runs for the user's
## changes only. The slider is the row's meta "slider".
static func slider_row(text: String, min_v: float, max_v: float, step: float, fmt: Callable, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", PaneStyle.constant(&"gap") * 2)
	row.custom_minimum_size = Vector2(0, PaneStyle.constant(&"button_height"))
	var name_label := label(text)
	name_label.custom_minimum_size = Vector2(170, 0)
	row.add_child(name_label)
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_FILL
	s.custom_minimum_size = Vector2(0, PaneStyle.constant(&"button_height"))
	row.add_child(s)
	var value_label := label("", &"TimeLabel")
	value_label.custom_minimum_size = Vector2(84, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	s.value_changed.connect(func(v: float) -> void:
		value_label.text = fmt.call(v)
		if not s.has_meta("quiet"):
			on_change.call(v))
	row.set_meta("slider", s)
	row.set_meta("value_label", value_label)
	row.set_meta("fmt", fmt)
	return row


## Sets a slider row's value without running its callback.
static func set_slider(row: Control, v: float) -> void:
	var s: HSlider = row.get_meta("slider")
	s.set_value_no_signal(v)
	(row.get_meta("value_label") as Label).text = (row.get_meta("fmt") as Callable).call(s.value)


static func slider_of(row: Control) -> HSlider:
	return row.get_meta("slider")


## A help line under a control (ui/help_texts.gd): one muted line (an ellipsis if it is too long; no wrapping, so the
## layout settles in one pass), not clickable. Its meta "help" marks it.
static func help(text: String) -> Label:
	var l := ellipsis(label(text, &"MutedLabel"))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.set_meta("help", true)
	return l


static func section(text: String) -> Label:
	var l := caps(text)
	l.custom_minimum_size = Vector2(0, 26)
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	l.set_meta("section", text)
	return l


## Groups a tab's box by its sections (section()): each heading and what follows it, up to the next, go into a box
## of their own (meta "section": the name), so one section can show at a time (the tablet, ui/pane_ui.gd). A box
## that starts with a heading is a section of its own; its own visibility stays the tab's. Looks the same with every
## group shown.
static func group_sections(box: VBoxContainer) -> Array[VBoxContainer]:
	var groups: Array[VBoxContainer] = []
	var group: VBoxContainer = null
	var children := box.get_children()
	for c in children:
		box.remove_child(c)
	for c in children:
		var title := section_title(c)
		if title != "" or group == null:
			group = vbox()
			group.add_theme_constant_override("separation", box.get_theme_constant("separation"))
			group.set_meta("section", title if title != "" else "General")
			groups.append(group)
			box.add_child(group)
		group.add_child(c)
	return groups


## The section a node starts (its heading, or a box's first child's, a few levels down), or "".
static func section_title(n: Node) -> String:
	for depth in 4:
		if n == null:
			return ""
		if n.has_meta("section"):
			return str(n.get_meta("section"))
		if not (n is Container) or n.get_child_count() == 0:
			return ""
		n = n.get_child(0)
	return ""


static func hbox(children: Array = []) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", PaneStyle.constant(&"gap"))
	for c: Control in children:
		row.add_child(c)
	return row


static func vbox() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", PaneStyle.constant(&"gap"))
	return box


## A tab body: a vertical box in a scroll container (no horizontal scrolling). Returns [scroll, box].
static func scrolled() -> Array:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := vbox()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	return [scroll, box]


static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


## h:mm:ss
static func clock(t: float) -> String:
	var s := maxi(0, int(t))
	return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]


## h:mm for the resume marker.
static func short_clock(t: float) -> String:
	var m := maxi(0, int(t)) / 60
	return "%d:%02d" % [m / 60, m % 60]
