extends VBoxContainer

## The Search place's query: a field with the on-pane keyboard, Search and Cancel. Plain controls like url_form.gd; the
## pane's theme styles them. The phone remote can type into the field too.

const OnscreenKeyboard := preload("res://ui/onscreen_keyboard.gd")

signal search_requested(query: String)
signal cancelled

var _field: LineEdit
## The line above the field (set before the form enters the tree).
var title_text := "Search your favourites, history, queue and the last local folder"
## The action button's text, the field's hint, and whether an empty field is an answer (a PIN cleared).
var button_text := "Search"
var placeholder := "words from the name"
var allow_empty := false
var _keyboard: OnscreenKeyboard
var _title: Label
var _button: Button


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	_title = Label.new()
	_title.text = title_text
	add_child(_title)
	_field = LineEdit.new()
	_field.custom_minimum_size = Vector2(560, 0)
	_field.virtual_keyboard_enabled = false
	_field.placeholder_text = placeholder
	_field.text_submitted.connect(func(_t: String) -> void: _search())
	add_child(_field)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	add_child(buttons)
	_button = Button.new()
	_button.text = button_text
	_button.pressed.connect(_search)
	buttons.add_child(_button)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(func() -> void: cancelled.emit())
	buttons.add_child(cancel)
	_keyboard = OnscreenKeyboard.new()
	_keyboard.target = _field
	_keyboard.done.connect(_search)
	add_child(_keyboard)


func edit(query: String) -> void:
	_field.text = query
	_field.grab_focus.call_deferred()
	_field.caret_column = query.length()


## One form for several questions (the watch party's name and PIN): new texts for the next edit().
func set_texts(title: String, button: String, hint: String, empty_ok: bool) -> void:
	title_text = title
	button_text = button
	placeholder = hint
	allow_empty = empty_ok
	if _title != null:
		_title.text = title
		_button.text = button
		_field.placeholder_text = hint


func get_field() -> LineEdit:
	return _field


func _search() -> void:
	var q := _field.text.strip_edges()
	if q == "" and not allow_empty:
		_field.grab_focus()
		return
	search_requested.emit(q)
