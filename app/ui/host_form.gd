extends VBoxContainer

## Add / edit a network (SMB) host: host, share (optional), user, password, domain, with the on-panel keyboard typing
## into whichever field has focus. Plain controls; the pane's theme styles them.

const OnscreenKeyboard := preload("res://ui/onscreen_keyboard.gd")

signal saved(index: int, entry: Dictionary)
signal deleted(index: int)
signal cancelled

var _index := -1
var _fields := {}
var _keyboard: OnscreenKeyboard
var _delete: Button
var _title: Label


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	# The title on the buttons' row, the fields three to a row: the form and its keyboard fit the tablet's pane.
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	add_child(grid)
	for spec: Array in [["host", "Host"], ["share", "Share"], ["user", "User"], ["password", "Password"],
			["domain", "Domain"]]:
		var l := Label.new()
		l.text = spec[1]
		grid.add_child(l)
		var e := LineEdit.new()
		e.custom_minimum_size = Vector2(150, 0)
		e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		e.virtual_keyboard_enabled = false
		e.placeholder_text = {"host": "nas.local or 192.168.1.10", "share": "optional", "domain": "optional"}.get(spec[0], "")
		if spec[0] == "password":
			e.secret = true
		e.focus_entered.connect(func() -> void: _keyboard.target = e)
		grid.add_child(e)
		_fields[spec[0]] = e
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	buttons.add_child(_title)
	add_child(buttons)
	move_child(buttons, 0)
	var save := Button.new()
	save.text = "Save"
	save.pressed.connect(_save)
	buttons.add_child(save)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(func() -> void: cancelled.emit())
	buttons.add_child(cancel)
	_delete = Button.new()
	_delete.text = "Delete host"
	_delete.pressed.connect(func() -> void: deleted.emit(_index))
	buttons.add_child(_delete)
	var show := Button.new()
	show.text = "Show password"
	show.toggle_mode = true
	show.focus_mode = Control.FOCUS_NONE
	show.toggled.connect(func(on: bool) -> void: (_fields["password"] as LineEdit).secret = not on)
	buttons.add_child(show)
	_keyboard = OnscreenKeyboard.new()
	_keyboard.quick = ["smb://", ".local", ".lan", "192.168."]
	_keyboard.done.connect(_save)
	add_child(_keyboard)


## index -1: a new host.
func edit(index: int, entry: Dictionary) -> void:
	_index = index
	_title.text = "Add a network host (SMB)" if index < 0 else "Edit network host"
	for key: String in _fields:
		(_fields[key] as LineEdit).text = str(entry.get(key, ""))
	_delete.visible = index >= 0
	var host_field: LineEdit = _fields["host"]
	_keyboard.target = host_field
	host_field.grab_focus.call_deferred()
	host_field.caret_column = host_field.text.length()


func get_field(key: String) -> LineEdit:
	return _fields[key]


func _save() -> void:
	var entry := {}
	for key: String in _fields:
		entry[key] = (_fields[key] as LineEdit).text.strip_edges()
	if entry["host"] == "":
		(_fields["host"] as LineEdit).grab_focus()
		return
	saved.emit(_index, entry)
