extends ScrollContainer

## The Mixed reality tab (above System; the user, 2026-11-06): areas of the real room seen through the headset's
## cameras (scripts/play/real_windows.gd; docs/USAGE.md "The Mixed reality tab"). Sweep an area: hold the trigger and
## pass the controller over the place. Each area on a row with its size, On, Edit (a face at a time: the face shows
## bright, the stick moves it, the trigger goes to the next face and then Turn) and Delete (with Undo). All on, All
## off. Settings, a section of its own (the user, 2026-11-06): Passthrough dimming, the least the room light dims the
## cameras' view to.

const W := preload("res://ui/pane_widgets.gd")
const PaneStyle := preload("res://ui/pane_style.gd")

var app: Node
var box: VBoxContainer
var _empty: Label
var _rows: VBoxContainer
var _light: Control
## What the list was built from (ids, names, On): rebuilt only when that changes; the sizes are updated in place.
var _shape := ""
var _size_labels := {}


func _init() -> void:
	name = "Mixed reality"
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	box = W.vbox()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(box)


func bind(p_app: Node) -> void:
	app = p_app
	box.add_child(W.section("Areas"))
	box.add_child(W.label("Mark areas to see through to the cameras.", &"MutedLabel"))
	box.add_child(W.hbox([W.button("Sweep an area", func() -> void: app.ui.start_window_mark())]))
	box.add_child(W.help("Hold the trigger and pass the controller over the place; let go to keep it."))
	_empty = W.label("None yet.", &"MutedLabel")
	box.add_child(_empty)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 0)
	box.add_child(_rows)
	box.add_child(W.hbox([W.button("All on", func() -> void: _rw().set_all(true)),
			W.button("All off", func() -> void: _rw().set_all(false))]))
	box.add_child(W.section("Settings"))
	_light = W.slider_row("Passthrough dimming", 0.0, 100.0, 5.0,
			func(v: float) -> String: return "%d %%" % roundi(v),
			func(v: float) -> void: _rw().set_light_min(v / 100.0))
	box.add_child(_light)

	var rw := _rw()
	if rw != null:
		rw.changed.connect(sync)
	visibility_changed.connect(func() -> void:
		if is_visible_in_tree():
			sync())
	sync()


func _rw() -> Node:
	return app.features.get("real_windows") if app != null and app.get("features") != null else null


func sync() -> void:
	var rw := _rw()
	if rw == null:
		return
	W.set_slider(_light, rw.light_min * 100.0)
	_empty.visible = rw.windows.is_empty()
	if not rw.available():
		_empty.text = "The headset's cameras can't show here."
		_empty.visible = true
	var shape: String = JSON.stringify(rw.windows.map(func(w: Dictionary) -> Array: return [w["id"], w["name"], w["on"]]))
	if shape != _shape:
		_shape = shape
		_build_rows(rw)
	for id: String in _size_labels:
		var w: Dictionary = rw.window_by_id(id)
		if not w.is_empty():
			(_size_labels[id] as Label).text = _row_text(w)


## A row an area: its name and size, On, Edit, Delete.
func _build_rows(rw: Node) -> void:
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	_size_labels.clear()
	for w: Dictionary in rw.windows:
		var id := str(w["id"])
		var text := W.ellipsis(W.label(_row_text(w)))
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var on := W.toggle("On", func(v: bool) -> void: rw.set_on(id, v))
		W.set_on(on, bool(w.get("on", true)))
		_rows.add_child(W.hbox([text, on, W.button("Edit", func() -> void: app.ui.start_window_edit(id)),
				W.button("Delete", func() -> void: _delete(id))]))
		_size_labels[id] = text


func _row_text(w: Dictionary) -> String:
	var s: Array = w["size"]
	return "%s  ·  %d x %d x %d cm" % [w["name"], roundi(float(s[0]) * 100.0), roundi(float(s[1]) * 100.0),
			roundi(float(s[2]) * 100.0)]


func _delete(id: String) -> void:
	var rw := _rw()
	var gone: Dictionary = rw.remove(id)
	if gone.is_empty():
		return
	app.ui.ui.show_toast("%s deleted" % gone["name"], "Undo", func() -> void:
		rw.restore(gone)
		app.ui.ui.hide_toast(), 8.0)
