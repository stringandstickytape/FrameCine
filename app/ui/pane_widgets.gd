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
static func choices(names: Array, on_chosen: Callable) -> HFlowContainer:
	# A row that wraps where it is narrow (a card on the tablet).
	var row := flow()
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
static func slider_row(text: String, min_v: float, max_v: float, step: float, fmt: Callable, on_change: Callable) -> VBoxContainer:
	# The name and the value on one line, the slider under them the full width: fits a half-width card on the
	# tablet, and gives a finger the whole width.
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", PaneStyle.constant(&"gap"))
	var name_label := ellipsis(label(text))
	head.add_child(name_label)
	row.add_child(head)
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_FILL
	s.custom_minimum_size = Vector2(0, PaneStyle.constant(&"button_height") - 8)
	var value_label := label("", &"TimeLabel")
	value_label.custom_minimum_size = Vector2(84, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(value_label)
	row.add_child(s)
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


## A help line under a control (ui/help_texts.gd): muted, up to two lines (an ellipsis if it is longer still: a
## half-width card holds few words to a line), not clickable. Its meta "help" marks it.
static func help(text: String) -> Label:
	var l := ellipsis(label(text, &"MutedLabel"))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.max_lines_visible = 2
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
	# Grouped already: as they are.
	if not children.is_empty() and children.all(func(c: Node) -> bool: return c is VBoxContainer and c.has_meta("section")):
		for c in children:
			groups.append(c)
		return groups
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


## Lays a tab's box out as cards (the tablet, ui/pane_ui.gd): its sections (group_sections()) each in a CardPanel,
## packed two to a row where both fit half the width, else one to a row (refresh_cards()); off: the groups back in
## the box, one under another. The cards and their rows live in a box kept on the tab's box as meta "cards".
static func card_layout(box: VBoxContainer, on: bool) -> void:
	var holder: VBoxContainer = (box.get_meta("cards") if box.has_meta("cards") else null)
	if on and holder == null:
		var groups := group_sections(box)
		holder = VBoxContainer.new()
		holder.name = "Cards"
		holder.add_theme_constant_override("separation", PaneStyle.constant(&"gap"))
		holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var all: Array = []
		for g in groups:
			box.remove_child(g)
			var card := PanelContainer.new()
			card.theme_type_variation = &"CardPanel"
			card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			card.add_child(g)
			all.append(card)
		holder.set_meta("all", all)
		holder.set_meta("packed", "")
		box.add_child(holder)
		box.set_meta("cards", holder)
	elif not on and holder != null:
		for card: Control in holder.get_meta("all", []):
			var g: Node = card.get_child(0)
			card.remove_child(g)
			box.add_child(g)
			if card.get_parent() != null:
				card.get_parent().remove_child(card)
			card.free()
		box.remove_child(holder)
		holder.queue_free()
		box.remove_meta("cards")


## The cards of a box laid out by card_layout() (PanelContainers, in order), or none.
static func cards(box: VBoxContainer) -> Array:
	var holder: VBoxContainer = (box.get_meta("cards") if box.has_meta("cards") else null)
	return holder.get_meta("all", []) if holder != null else []


## A card (card_layout()) has something to show past its heading: a tab hides what doesn't apply, such as 3D for a
## flat film. A group whose heading sits inside its one child has no heading of its own at the front: every child
## counts then.
static func card_shows(card: Control) -> bool:
	var g: Node = card.get_child(0)
	var first := 1 if g.get_child_count() > 0 and g.get_child(0).has_meta("section") else 0
	for i in range(first, g.get_child_count()):
		var c: Node = g.get_child(i)
		if c is CanvasItem and (c as CanvasItem).visible:
			return true
	return false


## The card's section (its group's "section" meta).
static func card_section(card: Control) -> String:
	return str(card.get_child(0).get_meta("section", ""))


## The sections of a box laid out as cards that have something to show, in order (the tablet's sections column,
## ui/pane_ui.gd).
static func shown_sections(box: VBoxContainer) -> Array[String]:
	var out: Array[String] = []
	for card: Control in cards(box):
		if card_shows(card):
			out.append(card_section(card))
	return out


## Packs the cards for a width (pixels): a card whose section has nothing to show (card_shows()) is left out; a card
## too wide for half the width takes a row of its own; a run of cards that fit go into two columns, each to the
## shorter column, so a tall list and a short card don't stretch each other. `only`: that section's card alone, the
## full width (the tablet's sections column picks it). Packed again only when that changes.
static func refresh_cards(box: VBoxContainer, width: float, only := "") -> void:
	var holder: VBoxContainer = (box.get_meta("cards") if box.has_meta("cards") else null)
	if holder == null:
		return
	var gap := PaneStyle.constant(&"gap")
	var half := (width - gap) * 0.5
	var shown: Array = []
	var key := only + ":"
	for card: Control in holder.get_meta("all", []):
		if card_shows(card) and (only == "" or card_section(card) == only):
			shown.append(card)
			key += "W" if only != "" or card.get_combined_minimum_size().x > half else "1"
		else:
			key += "0"
	if key == str(holder.get_meta("packed", "")):
		return
	holder.set_meta("packed", key)
	for card: Control in holder.get_meta("all", []):
		if card.get_parent() != null:
			card.get_parent().remove_child(card)
	for row in holder.get_children():
		holder.remove_child(row)
		row.queue_free()
	var columns: Array = []
	var heights := [0.0, 0.0]
	for card: Control in shown:
		if only != "" or card.get_combined_minimum_size().x > half:
			columns = []
			holder.add_child(card)
			continue
		if columns.is_empty():
			var pair := HBoxContainer.new()
			pair.add_theme_constant_override("separation", gap)
			for k in 2:
				var col := VBoxContainer.new()
				col.add_theme_constant_override("separation", gap)
				col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
				pair.add_child(col)
				columns.append(col)
			heights = [0.0, 0.0]
			holder.add_child(pair)
		var k := 0 if heights[0] <= heights[1] else 1
		(columns[k] as Container).add_child(card)
		heights[k] += card.get_combined_minimum_size().y + gap


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


## A row that wraps onto more rows where it is narrow (a card on the tablet): the diagrams, a row of choices.
static func flow(children: Array = []) -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", PaneStyle.constant(&"gap"))
	row.add_theme_constant_override("v_separation", PaneStyle.constant(&"gap"))
	for c: Control in children:
		row.add_child(c)
	return row


## A grid of equal columns (the mode diagrams: three to a row, so they fit a card).
static func grid(columns: int, children: Array = []) -> GridContainer:
	var g := GridContainer.new()
	g.columns = columns
	g.add_theme_constant_override("h_separation", PaneStyle.constant(&"gap"))
	g.add_theme_constant_override("v_separation", PaneStyle.constant(&"gap"))
	for c: Control in children:
		g.add_child(c)
	return g


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
