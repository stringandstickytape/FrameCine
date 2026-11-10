## The floating keyboard's ANSI US layout (docs/dev/keyboard-design.md). Positions and sizes are in key units;
## drawing, pointing and the swipe dictionary all use these same centres. Legends are physical, never translated.
extends RefCounted

const SIZE := Vector2(23, 8.25)
const MODIFIERS := [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]


static func keys() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_add(out, KEY_ESCAPE, "Esc", 0, 2)
	for i in 12:
		_add(out, KEY_F1 + i, "F%d" % (i + 1), 2 + i + floori(i / 4.0) * 0.5, 2)
	for i in 3:
		_add(out, [KEY_PRINT, KEY_SCROLLLOCK, KEY_PAUSE][i], ["Print\nScreen", "Scroll\nLock", "Pause"][i], 15.5 + i, 2)
	_row(out, "`1234567890-=", "~!@#$%^&*()_+", 0, 3.25)
	_add(out, KEY_BACKSPACE, "Backspace", 13, 3.25, 2)
	_add(out, KEY_TAB, "Tab", 0, 4.25, 1.5)
	_row(out, "qwertyuiop[]", "QWERTYUIOP{}", 1.5, 4.25)
	_add(out, KEY_BACKSLASH, "\\", 13.5, 4.25, 1.5, 1, KEY_LOCATION_UNSPECIFIED, "|")
	_add(out, KEY_CAPSLOCK, "Caps Lock", 0, 5.25, 1.75)
	_row(out, "asdfghjkl;'", "ASDFGHJKL:\"", 1.75, 5.25)
	_add(out, KEY_ENTER, "Enter", 12.75, 5.25, 2.25)
	_add(out, KEY_SHIFT, "Shift", 0, 6.25, 2.25, 1, KEY_LOCATION_LEFT)
	_row(out, "zxcvbnm,./", "ZXCVBNM<>?", 2.25, 6.25)
	_add(out, KEY_SHIFT, "Shift", 12.25, 6.25, 2.75, 1, KEY_LOCATION_RIGHT)
	var x := 0.0
	for item: Array in [[KEY_CTRL, "Ctrl", 1.25, KEY_LOCATION_LEFT], [KEY_META, "Super", 1.25, KEY_LOCATION_LEFT],
			[KEY_ALT, "Alt", 1.25, KEY_LOCATION_LEFT], [KEY_SPACE, "Space", 6.25, KEY_LOCATION_UNSPECIFIED],
			[KEY_ALT, "Alt", 1.25, KEY_LOCATION_RIGHT], [KEY_META, "Super", 1.25, KEY_LOCATION_RIGHT],
			[KEY_MENU, "Menu", 1.25, KEY_LOCATION_UNSPECIFIED], [KEY_CTRL, "Ctrl", 1.25, KEY_LOCATION_RIGHT]]:
		_add(out, item[0], item[1], x, 7.25, item[2], 1, item[3])
		x += float(item[2])
	for i in 6:
		_add(out, [KEY_INSERT, KEY_HOME, KEY_PAGEUP, KEY_DELETE, KEY_END, KEY_PAGEDOWN][i],
				["Insert", "Home", "Page\nUp", "Delete", "End", "Page\nDown"][i], 15.5 + i % 3, 3.25 + floori(i / 3.0))
	_add(out, KEY_UP, "Up", 16.5, 6.25)
	for i in 3:
		_add(out, [KEY_LEFT, KEY_DOWN, KEY_RIGHT][i], ["Left", "Down", "Right"][i], 15.5 + i, 7.25)
	for i in 4:
		_add(out, [KEY_NUMLOCK, KEY_KP_DIVIDE, KEY_KP_MULTIPLY, KEY_KP_SUBTRACT][i],
				["Num\nLock", "/", "*", "-"][i], 19 + i, 3.25)
	for row in 3:
		for col in 3:
			var n := 7 - row * 3 + col
			_add(out, KEY_KP_0 + n, str(n), 19 + col, 4.25 + row)
	_add(out, KEY_KP_ADD, "+", 22, 4.25, 1, 2)
	_add(out, KEY_KP_ENTER, "Enter", 22, 6.25, 1, 2)
	_add(out, KEY_KP_0, "0", 19, 7.25, 2)
	_add(out, KEY_KP_PERIOD, ".", 21, 7.25)
	return out


static func _row(out: Array[Dictionary], lower: String, upper: String, x: float, y: float) -> void:
	for i in lower.length():
		_add(out, lower.to_upper().unicode_at(i), lower[i], x + i, y, 1, 1, KEY_LOCATION_UNSPECIFIED, upper[i])


static func _add(out: Array[Dictionary], code: int, legend: String, x: float, y: float, w := 1.0, h := 1.0,
		location := KEY_LOCATION_UNSPECIFIED, shifted := "") -> void:
	out.append({"code": code, "location": location, "legend": legend, "shifted": shifted,
			"rect": Rect2(x + 0.045, y + 0.045, w - 0.09, h - 0.09)})


static func letters() -> Dictionary:
	var out := {}
	for k in keys():
		if int(k.code) >= KEY_A and int(k.code) <= KEY_Z:
			out[str(k.legend)] = (k.rect as Rect2).get_center()
	return out


static func character(k: Dictionary, shift: bool, caps: bool, num: bool) -> int:
	var code := int(k.code)
	if code >= KEY_A and code <= KEY_Z:
		return code if shift != caps else code + 32
	if code >= KEY_KP_0 and code <= KEY_KP_9:
		return 48 + code - KEY_KP_0 if num else 0
	if code == KEY_SPACE:
		return 32
	if code == KEY_KP_PERIOD:
		return 46 if num else 0
	if code in [KEY_KP_DIVIDE, KEY_KP_MULTIPLY, KEY_KP_SUBTRACT, KEY_KP_ADD]:
		return str(k.legend).unicode_at(0)
	var text := str(k.shifted) if shift and str(k.shifted) != "" else str(k.legend)
	return text.unicode_at(0) if text.length() == 1 else 0
