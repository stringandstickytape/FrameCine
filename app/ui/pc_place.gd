extends VBoxContainer

## The Files tab's "PC windows" place (docs/pc-windows.md; scripts/pc/pc_windows.gd): each connected PC with its
## windows and monitors as thumbnails (the PC's own pictures, at most 256 px); picking one opens it as a pane in front
## of the viewer (or brings its pane into focus). Under them, a line with the on-pane keyboard that types into the
## pane in focus (`text`), for when there is no keyboard paired.
## The titles and the pictures are the PC's (content, never translated, never logged). Built again when the feature
## says something changed, once a frame at most and only while it shows (else when it next shows): a title changing
## every second rebuilt it every second, hidden or not, and the headset lurched (the user, 2026-11-08). While it shows,
## the same windows in the same order are not built again: their titles, pictures and pressed state are set in place
## (the user, 2026-11-11: a terminal whose title moves every second, with this place open, lurched once a second).

const W := preload("res://ui/pane_widgets.gd")
const OnscreenKeyboard := preload("res://ui/onscreen_keyboard.gd")

const TILE := Vector2(250, 190)

var feature: Node
var _line: LineEdit
var _keyboard: OnscreenKeyboard
## Window tiles made (the tests press them): [{button, pc, id}].
var tiles: Array[Dictionary] = []
var _dirty := false
## What the tiles were built from (_shape()): the PCs and their windows' ids, in order.
var _built := []
var _queued := false


func _init() -> void:
	name = "PcPlace"
	add_theme_constant_override("separation", 6)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	visibility_changed.connect(func() -> void:
		if _dirty and is_visible_in_tree():
			_changed())


func bind(p_feature: Node) -> void:
	feature = p_feature
	if feature != null:
		feature.changed.connect(_changed)
	_rebuild()


func _changed() -> void:
	if not is_inside_tree() or not is_visible_in_tree():
		_dirty = true
		return
	if not _queued:
		_queued = true
		_rebuild_now.call_deferred()


func _rebuild_now() -> void:
	_queued = false
	if _shape() == _built and not _built.is_empty():
		_refresh()
	else:
		_rebuild()


## The PCs and their windows, as far as the layout goes: a change here builds the place again.
func _shape() -> Array:
	var out := []
	if feature == null or feature.service == null:
		return out
	for s: RefCounted in feature.sessions():
		var ids := []
		for w: Dictionary in s.windows:
			ids.append([str(w["id"]), str(w["kind"])])
		out.append([str(s.client_id), str(s.pc_name), ids])
	return out


## The same windows as built: only what a tile says.
func _refresh() -> void:
	_dirty = false
	var at := {}
	for s: RefCounted in feature.sessions():
		for w: Dictionary in s.windows:
			at["%s|%s" % [s.client_id, w["id"]]] = w
	for t: Dictionary in tiles:
		var w: Dictionary = at.get("%s|%s" % [t["pc"], t["id"]], {})
		if w.is_empty() or not is_instance_valid(t["button"]):
			continue
		var text := _title(w)
		if (t["label"] as Label).text != text:
			(t["label"] as Label).text = text
		if (t["picture"] as TextureRect).texture != w.get("thumb"):
			(t["picture"] as TextureRect).texture = w.get("thumb")
		(t["button"] as Button).set_pressed_no_signal(feature.pane_for(t["pc"], t["id"]) != null)


func _title(w: Dictionary) -> String:
	return str(w["title"]) if str(w["title"]) != "" else (tr("Monitor") if w["kind"] == "monitor" else str(w["app"]))


func _rebuild() -> void:
	_dirty = false
	for c in get_children():
		remove_child(c)
		c.queue_free()
	tiles.clear()
	_line = null
	_keyboard = null
	_built = _shape()
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
	var l := W.ellipsis(W.label(_title(w)))
	W.content(l)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(l)
	var client: String = s.client_id
	var id: String = w["id"]
	b.pressed.connect(func() -> void:
		feature.open_window(client, id)
		b.set_pressed_no_signal(true))
	tiles.append({"button": b, "pc": client, "id": id, "label": l, "picture": pic})
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
