extends VBoxContainer

## The Files tab's "PC windows" place (docs/pc-windows.md; scripts/pc/pc_windows.gd): each connected PC with its
## windows and monitors as thumbnails (the PC's own pictures, at most 256 px); picking one opens it as a pane in front
## of the viewer (or brings its pane into focus). Under them, a line with the on-pane keyboard that types into the
## pane in focus (`text`), for when there is no keyboard paired.
## The titles and the pictures are the PC's (content, never translated, never logged). Built again whenever the
## feature says something changed.

const W := preload("res://ui/pane_widgets.gd")
const OnscreenKeyboard := preload("res://ui/onscreen_keyboard.gd")

const TILE := Vector2(250, 190)

var feature: Node
var _line: LineEdit
var _keyboard: OnscreenKeyboard
## Window tiles made (the tests press them): [{button, pc, id}].
var tiles: Array[Dictionary] = []


func _init() -> void:
	name = "PcPlace"
	add_theme_constant_override("separation", 6)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func bind(p_feature: Node) -> void:
	feature = p_feature
	if feature != null:
		feature.changed.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	tiles.clear()
	_line = null
	_keyboard = null
	if feature == null or feature.service == null:
		add_child(W.help("PC windows is off. Turn it on in System, PC windows, and add your PC there."))
		return
	if feature.sessions().is_empty():
		var l := W.label(feature.service.status_text(), &"MutedLabel")
		W.content(l)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(l)
		return
	for s: RefCounted in feature.sessions():
		var head := W.label(str(s.pc_name), &"AccentLabel")
		W.content(head)
		add_child(head)
		var flow := W.flow()
		add_child(flow)
		for w: Dictionary in s.windows:
			flow.add_child(_tile(s, w))
		if s.windows.is_empty():
			add_child(W.help("No windows yet."))
	_add_typing()


func _tile(s: RefCounted, w: Dictionary) -> Button:
	var b := Button.new()
	b.theme_type_variation = &"RowButton"
	b.custom_minimum_size = TILE
	b.toggle_mode = true
	b.set_pressed_no_signal(feature.pane_for(s.client_id, w["id"]) != null)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 8
	box.offset_right = -8
	box.offset_top = 6
	box.offset_bottom = -6
	b.add_child(box)
	var pic := TextureRect.new()
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pic.texture = w.get("thumb")
	box.add_child(pic)
	var title := str(w["title"]) if str(w["title"]) != "" else (tr("Monitor") if w["kind"] == "monitor" else str(w["app"]))
	var l := W.ellipsis(W.label(title))
	W.content(l)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(l)
	var client: String = s.client_id
	var id: String = w["id"]
	b.pressed.connect(func() -> void:
		feature.open_window(client, id)
		b.set_pressed_no_signal(true))
	tiles.append({"button": b, "pc": client, "id": id})
	return b


## Types into the pane in focus: a line, the on-pane keyboard, Send.
func _add_typing() -> void:
	add_child(W.section("Type into the window in focus"))
	_line = LineEdit.new()
	_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_line.placeholder_text = tr("Text to type")
	_line.text_submitted.connect(func(_t: String) -> void: _send())
	add_child(W.hbox([_line, W.button("Send", _send), W.button("Keyboard", func() -> void:
		if _keyboard == null:
			_keyboard = OnscreenKeyboard.new()
			_keyboard.target = _line
			_keyboard.done.connect(func() -> void: _send())
			add_child(_keyboard)
		else:
			_keyboard.visible = not _keyboard.visible)]))


func _send() -> void:
	if _line == null or _line.text == "":
		return
	if feature.send_text(_line.text):
		_line.text = ""
