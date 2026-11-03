extends VBoxContainer

## The on-pane keyboard for text fields in VR (the engine's virtual keyboard is for phones and the web only, and the
## headset's desktop build has none). Types into `target` (a LineEdit) at its caret. Keys use the theme's KeyButton
## look (ui/themes/default.tres).
##
## Layers: letters (Shift for capitals, one key press; Shift held down with a second press locks it) and symbols
## (?123). Bottom row: Shift, ?123, Space, caret left and right, Del, Clear, Paste (the clipboard; the phone remote can
## also type into the focused field directly), Done. `quick`: an optional row of whole strings for the form
## ("https://", ".com" for web pages; "smb://", ".local" for hosts).

signal done

const ROWS_LOWER: Array[String] = ["1234567890-", "qwertyuiop_", "asdfghjkl.@", "zxcvbnm/\\:"]
const ROWS_UPPER: Array[String] = ["1234567890-", "QWERTYUIOP_", "ASDFGHJKL.@", "ZXCVBNM/\\:"]
const ROWS_SYMBOLS: Array[String] = ["!#$%&*()+=~", "`^'\"<>[]{}|", ";,?€£§°¬¦·", "        "]
const KEY_SIZE := Vector2(56, 40)

var target: LineEdit
## Whole strings on an extra row above the letters; empty for none. Set before the keyboard enters the tree.
var quick: Array[String] = []
var _shift := false
var _caps_lock := false
var _symbols := false
var _letter_keys: Array[Button] = []
var _shift_key: Button
var _symbols_key: Button


func _ready() -> void:
	add_theme_constant_override("separation", 3)
	if not quick.is_empty():
		var q := _row()
		for text in quick:
			var b := _key(text, Vector2(maxf(KEY_SIZE.x, 14.0 * text.length() + 20.0), KEY_SIZE.y))
			b.pressed.connect(_insert.bind(text))
			q.add_child(b)
	for r in ROWS_LOWER.size():
		var row := _row()
		for c in ROWS_LOWER[r].length():
			var b := _key(ROWS_LOWER[r][c], KEY_SIZE)
			b.pressed.connect(_type.bind(r, c))
			row.add_child(b)
			_letter_keys.append(b)
	var bottom := _row()
	_shift_key = _key("Shift", Vector2(78, KEY_SIZE.y))
	_shift_key.toggle_mode = true
	_shift_key.toggled.connect(func(on: bool) -> void:
		# A press while Shift is on locks capitals; the next press releases both.
		if not on and _shift and not _caps_lock:
			_caps_lock = true
			_shift_key.set_pressed_no_signal(true)
		else:
			_caps_lock = false
			_shift = on
		_relabel())
	bottom.add_child(_shift_key)
	_symbols_key = _key("?123", Vector2(70, KEY_SIZE.y))
	_symbols_key.pressed.connect(func() -> void:
		_symbols = not _symbols
		_symbols_key.text = "abc" if _symbols else "?123"
		_relabel())
	bottom.add_child(_symbols_key)
	var space := _key("Space", Vector2(150, KEY_SIZE.y))
	space.pressed.connect(func() -> void: _insert(" "))
	bottom.add_child(space)
	var left := _key("<", Vector2(44, KEY_SIZE.y))
	left.pressed.connect(func() -> void: _move(-1))
	bottom.add_child(left)
	var right := _key(">", Vector2(44, KEY_SIZE.y))
	right.pressed.connect(func() -> void: _move(1))
	bottom.add_child(right)
	var back := _key("Del", Vector2(62, KEY_SIZE.y))
	back.pressed.connect(_backspace)
	bottom.add_child(back)
	var clear := _key("Clear", Vector2(66, KEY_SIZE.y))
	clear.pressed.connect(func() -> void:
		if target != null:
			target.text = ""
			target.caret_column = 0)
	bottom.add_child(clear)
	var paste := _key("Paste", Vector2(66, KEY_SIZE.y))
	paste.pressed.connect(func() -> void: _insert(DisplayServer.clipboard_get().strip_edges()))
	bottom.add_child(paste)
	var enter := _key("Done", Vector2(78, KEY_SIZE.y))
	enter.pressed.connect(func() -> void: done.emit())
	bottom.add_child(enter)


func _row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(row)
	return row


func _key(text: String, size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.theme_type_variation = &"KeyButton"
	b.focus_mode = Control.FOCUS_NONE  # Keep the text field focused.
	return b


func _rows() -> Array[String]:
	return ROWS_SYMBOLS if _symbols else (ROWS_UPPER if _shift else ROWS_LOWER)


func _type(row: int, col: int) -> void:
	var rows := _rows()
	if col >= rows[row].length() or rows[row][col] == " ":
		return
	_insert(rows[row][col])
	# Shift is for one letter unless locked.
	if _shift and not _caps_lock and not _symbols:
		_shift = false
		_shift_key.set_pressed_no_signal(false)
		_relabel()


func _insert(text: String) -> void:
	if target == null or text == "":
		return
	var col := target.caret_column
	target.text = target.text.substr(0, col) + text + target.text.substr(col)
	target.caret_column = col + text.length()


func _backspace() -> void:
	if target != null and target.caret_column > 0:
		var col := target.caret_column
		target.text = target.text.substr(0, col - 1) + target.text.substr(col)
		target.caret_column = col - 1


func _move(step: int) -> void:
	if target != null:
		target.caret_column = clampi(target.caret_column + step, 0, target.text.length())


func _relabel() -> void:
	var rows := _rows()
	var i := 0
	for r in ROWS_LOWER.size():
		for c in ROWS_LOWER[r].length():
			var ch := rows[r][c] if c < rows[r].length() else " "
			_letter_keys[i].text = ch
			_letter_keys[i].disabled = ch == " "
			i += 1
