extends VBoxContainer

## "Open a web page or a stream": a URL field with the on-panel keyboard, Open, Play as video, Save page (to the Browser
## place's list), Remove page (when editing a saved page) and Cancel. Open plays a media URL (udp://, or http(s) ending
## in a video or music name: live_stream.gd's is_media_url) and shows anything else as a web page; Play as video plays
## the URL whatever it looks like (an http stream with no extension). Plain controls, like host_form.gd; the pane's
## theme styles them.

const OnscreenKeyboard := preload("res://ui/onscreen_keyboard.gd")

signal open_requested(url: String)
## Play the URL in the player, not as a web page.
signal play_requested(url: String)
signal save_requested(url: String)
signal remove_requested(url: String)
signal cancelled

var _field: LineEdit
var _title: Label
var _remove: Button
var _keyboard: OnscreenKeyboard
var _editing := ""


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	_title = Label.new()
	add_child(_title)
	_field = LineEdit.new()
	_field.custom_minimum_size = Vector2(560, 0)
	_field.virtual_keyboard_enabled = false
	_field.placeholder_text = "example.com, https://.../film.mkv or udp://@:1234"
	_field.text_submitted.connect(func(_t: String) -> void: _open())
	add_child(_field)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	add_child(buttons)
	var open := Button.new()
	open.text = "Open"
	open.pressed.connect(_open)
	buttons.add_child(open)
	var play := Button.new()
	play.text = "Play as video"
	play.pressed.connect(func() -> void:
		if _field.text.strip_edges() != "":
			play_requested.emit(_field.text.strip_edges()))
	buttons.add_child(play)
	var save := Button.new()
	save.text = "Save page"
	save.pressed.connect(func() -> void:
		if _field.text.strip_edges() != "":
			save_requested.emit(_field.text.strip_edges()))
	buttons.add_child(save)
	_remove = Button.new()
	_remove.text = "Remove page"
	_remove.pressed.connect(func() -> void: remove_requested.emit(_editing))
	buttons.add_child(_remove)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(func() -> void: cancelled.emit())
	buttons.add_child(cancel)
	_keyboard = OnscreenKeyboard.new()
	_keyboard.quick = ["https://", "www.", ".com", ".co.uk", "/", "udp://@:"]
	_keyboard.target = _field
	_keyboard.done.connect(_open)
	add_child(_keyboard)


## Shows the form with `url` in the field; saved_page: the URL is a saved page (Remove page shows).
func edit(url: String, saved_page := false) -> void:
	_editing = url if saved_page else ""
	_title.text = "Saved page" if saved_page else "Open a web page or a stream"
	_remove.visible = saved_page
	_field.text = url
	_field.grab_focus.call_deferred()
	_field.caret_column = url.length()


func get_field() -> LineEdit:
	return _field


func _open() -> void:
	var text := _field.text.strip_edges()
	if text == "":
		_field.grab_focus()
		return
	open_requested.emit(text)
