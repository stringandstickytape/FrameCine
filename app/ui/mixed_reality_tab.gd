extends ScrollContainer

## The Mixed reality tab (above System; the user, 2026-11-06): windows to the real room (scripts/play/real_windows.gd;
## docs/USAGE.md "The Mixed reality tab"). Make an area by sweeping the controller over the place or by touching three
## of its corners; each area with On and a pick; the picked one shows brighter while the menu is open and has Move
## (with the controller: the trigger held moves it, the stick turns and sizes it), Mark again, its width, height and
## depth, and Delete (with Undo). All on, All off. Settings: the areas shown while the menu is open, and how far the
## cameras' view may dim with the room.

const W := preload("res://ui/pane_widgets.gd")
const PaneStyle := preload("res://ui/pane_style.gd")

const SIDE_CM := Vector2(5.0, 400.0)

var app: Node
var box: VBoxContainer
var _status: Label
var _rows: VBoxContainer
var _editor: VBoxContainer
var _editor_title: Label
var _sliders: Array = []
var _outlines: Button
var _light: Control
## What the list was built from (ids, names, On, the pick): rebuilt only when that changes, so a size slider being
## dragged is not remade under the laser.
var _shape := ""
var _size_labels := {}
var _picks := {}


func _init() -> void:
	name = "Mixed reality"
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	box = W.vbox()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(box)


func bind(p_app: Node) -> void:
	app = p_app
	add_theme_constant_override("separation", PaneStyle.constant(&"gap"))
	box.add_child(W.section("Windows to the real room"))
	_status = W.label("", &"MutedLabel")
	box.add_child(_status)
	box.add_child(W.hbox([W.button("Sweep an area", func() -> void: app.ui.start_window_mark()),
			W.button("Touch corners", func() -> void: app.ui.start_window_corners())]))
	box.add_child(W.help("A real place, the coffee table say, shows through the headset's cameras in every room. "
			+ "Sweep: hold the trigger and pass the controller over it. Corners: touch three corners of something flat."))
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 0)
	box.add_child(_rows)
	box.add_child(W.hbox([W.button("All on", func() -> void: _rw().set_all(true)),
			W.button("All off", func() -> void: _rw().set_all(false))]))

	_editor = W.vbox()
	_editor_title = W.label("", &"MutedLabel")
	_editor.add_child(_editor_title)
	_editor.add_child(W.hbox([W.button("Move with the controller", func() -> void:
				app.ui.start_window_adjust(_rw().selected)),
			W.button("Mark again", func() -> void: app.ui.start_window_mark_again(_rw().selected)),
			W.button("Delete", _delete)]))
	for i in 3:
		var axis := i
		var row := W.slider_row(["Width", "Height", "Depth"][i], SIDE_CM.x, SIDE_CM.y, 1.0,
				func(v: float) -> String: return "%d cm" % roundi(v),
				func(v: float) -> void: _set_side(axis, v))
		_sliders.append(row)
		_editor.add_child(row)
	box.add_child(_editor)

	box.add_child(W.section("Settings"))
	_outlines = W.toggle("Show the areas while the menu is open", func(on: bool) -> void: _rw().set_outlines(on))
	box.add_child(_outlines)
	_light = W.slider_row("Cameras' view when the room dims", 0.0, 100.0, 5.0,
			func(v: float) -> String: return "%d %%" % roundi(v),
			func(v: float) -> void: _rw().set_light_min(v / 100.0))
	box.add_child(_light)
	box.add_child(W.help("The room light dims the cameras' view too, never below this."))

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
	_status.text = rw.status()
	W.set_on(_outlines, rw.outlines)
	W.set_slider(_light, rw.light_min * 100.0)
	if not rw.selected.is_empty() and rw.window_by_id(rw.selected).is_empty():
		rw.selected = ""
	var shape: String = JSON.stringify(rw.windows.map(func(w: Dictionary) -> Array: return [w["id"], w["name"], w["on"]])) \
			+ rw.selected
	if shape != _shape:
		_shape = shape
		_build_rows(rw)
	for id: String in _size_labels:
		var w: Dictionary = rw.window_by_id(id)
		if not w.is_empty():
			(_size_labels[id] as Label).text = _size_text(w)
	var picked: Dictionary = rw.window_by_id(rw.selected)
	_editor.visible = not picked.is_empty()
	if not picked.is_empty():
		_editor_title.text = "%s: move it, mark it again, or set its size." % picked["name"]
		for i in 3:
			var slider: HSlider = W.slider_of(_sliders[i])
			if not slider.has_focus() and not slider.get_meta("dragging", false):
				W.set_slider(_sliders[i], float(picked["size"][i]) * 100.0)


func _build_rows(rw: Node) -> void:
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	_size_labels.clear()
	_picks.clear()
	var group := ButtonGroup.new()
	for w: Dictionary in rw.windows:
		var id := str(w["id"])
		var pick := W.button(str(w["name"]), Callable(), &"RowButton")
		pick.toggle_mode = true
		pick.button_group = group
		pick.set_pressed_no_signal(id == rw.selected)
		pick.pressed.connect(func() -> void:
			rw.selected = id
			sync())
		var size := W.ellipsis(W.label(_size_text(w), &"MutedLabel"))
		size.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var on := W.toggle("On", func(v: bool) -> void: rw.set_on(id, v))
		W.set_on(on, bool(w.get("on", true)))
		_rows.add_child(W.hbox([pick, size, on]))
		_size_labels[id] = size
		_picks[id] = pick


func _size_text(w: Dictionary) -> String:
	var s: Array = w["size"]
	return "%d x %d x %d cm" % [roundi(float(s[0]) * 100.0), roundi(float(s[1]) * 100.0), roundi(float(s[2]) * 100.0)]


func _set_side(axis: int, cm: float) -> void:
	var rw := _rw()
	var w: Dictionary = rw.window_by_id(rw.selected)
	if w.is_empty():
		return
	var size := Vector3(float(w["size"][0]), float(w["size"][1]), float(w["size"][2]))
	size[axis] = cm / 100.0
	rw.set_size(rw.selected, size)


func _delete() -> void:
	var rw := _rw()
	var gone: Dictionary = rw.remove(rw.selected)
	if gone.is_empty():
		return
	app.ui.ui.show_toast("%s deleted" % gone["name"], "Undo", func() -> void:
		rw.restore(gone)
		app.ui.ui.hide_toast(), 8.0)
