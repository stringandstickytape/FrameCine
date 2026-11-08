extends VBoxContainer

## The System tab's "PC windows" section (docs/pc-windows.md; scripts/pc/pc_windows.gd): on / off; "Add a PC" (a
## six-digit code for 10 minutes, with the minutes left and Cancel); the paired PCs with Forget. The code shows only
## here. Nothing is typed here: the code is typed on the PC.
## Languages (docs/i18n.md): the fixed words translate themselves; the built lines are made again when the language
## changes. A PC's name is the PC's own (content).

const W := preload("res://ui/pane_widgets.gd")

var app: Node
var _toggle: Button
var _body: VBoxContainer
var _status: Label
var _add_button: Button
var _pair_box: VBoxContainer
var _code: Label
var _left: Label
var _paired_box: VBoxContainer
var _paired_ids: Array = []
var _feature: Node


func _init() -> void:
	name = "PcWindowsRow"
	add_theme_constant_override("separation", 4)


func bind(p_app: Node) -> void:
	app = p_app
	_feature = app.features.get("pc_windows") if app.get("features") != null else null
	_toggle = W.toggle("PC windows", func(on: bool) -> void:
		if _feature != null:
			_feature.set_enabled(on)
		refresh.call_deferred())
	add_child(W.hbox([_toggle]))
	add_child(W.help("Your PC's windows as panes here, used with a mouse and keyboard paired with the headset. Run "
			+ "the PC windows app on the PC."))
	_body = W.vbox()
	add_child(_body)
	_status = W.label("")
	W.content(_status)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(_status)
	_add_button = W.button("Add a PC", func() -> void:
		if _feature != null and _feature.service != null:
			_feature.service.start_pairing()
		refresh.call_deferred())
	_body.add_child(W.hbox([_add_button]))
	_pair_box = W.vbox()
	_code = W.label("", &"TitleLabel")  # the largest text style
	W.content(_code)
	_left = W.label("", &"MutedLabel")
	W.content(_left)
	_pair_box.add_child(W.hbox([_code, _left, W.button("Cancel", func() -> void:
		if _feature != null and _feature.service != null:
			_feature.service.cancel_pairing())]))
	_pair_box.add_child(W.help("Type this code on the PC when it asks. Five wrong codes stop it."))
	_pair_box.visible = false
	_body.add_child(_pair_box)
	_paired_box = W.vbox()
	_body.add_child(_paired_box)
	if _feature != null:
		_feature.changed.connect(refresh)
	refresh()


## Called by the System tab a few times a second while it shows (the minutes left).
func tick() -> void:
	if _feature != null and _feature.service != null and _pair_box.visible:
		_refresh_pairing()


func refresh() -> void:
	var on: bool = _feature != null and _feature.service != null
	W.set_on(_toggle, on)
	_body.visible = on
	if not on:
		_paired_ids = []
		return
	var s: Node = _feature.service
	_status.text = s.status_text()
	_refresh_pairing()
	var paired: Array = s.paired()
	var ids: Array = paired.map(func(c: Dictionary) -> String: return "%s:%s" % [c["id"], c["connected"]])
	if ids == _paired_ids:
		return
	_paired_ids = ids
	for child in _paired_box.get_children():
		child.queue_free()
	for c: Dictionary in paired:
		var id: String = c["id"]
		var line := tr("%s, paired %s") % [c["name"], str(c["paired_at"]).get_slice(" ", 0)]
		if bool(c["connected"]):
			line += "  ·  " + tr("connected")
		var label := W.ellipsis(W.label(line, &"MutedLabel"))
		W.content(label)
		_paired_box.add_child(W.hbox([label, W.button("Forget", func() -> void:
			if _feature != null and _feature.service != null:
				_feature.service.forget(id))]))


func _refresh_pairing() -> void:
	var s: Node = _feature.service
	var code: String = s.pairing_code()
	_pair_box.visible = code != ""
	_add_button.visible = code == ""
	if code != "":
		_code.text = "%s %s" % [code.left(3), code.right(3)]
		_left.text = tr("%d min left") % ceili(float(s.pairing_left()) / 60.0)
	_status.text = s.status_text()


## The language changed: the paired list is made again in it.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and app != null and _paired_box != null:
		_paired_ids = []
		refresh()
