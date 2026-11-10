## The keyboard's picture in its ordinary SubViewport. Drawing from the layout keeps every hit box and word path
## aligned with its legend, and avoids taking focus from a field in the menu. All ink and boxes use the pane theme.
extends Control

const Layout := preload("res://keyboard/key_layout.gd")
const Style := preload("res://ui/pane_style.gd")
const UNIT := 100.0
var keyboard: Node3D
## Candidates and gestures are content: only this second, private picture contains them. The ordinary board has
## just its legends and lock lights, so a room snapshot cannot transcribe a path or a sequence of lit letters.
var candidates_only := false


func _draw() -> void:
	if keyboard == null:
		return
	var theme := Style.active()
	var font := theme.default_font
	# Two symbol legends must fit in one key even when the tablet's text scale is larger.
	var font_size := mini(theme.default_font_size * 2, 30)
	if candidates_only:
		for i in 3:
			var text := str(keyboard.alternatives[i + 1]) if keyboard.alternatives.size() > i + 1 else ""
			if text != "":
				_box(Rect2(0.15 + i * 7.6, 1.0, 7.4, 0.7), text, false, font, font_size)
	else:
		draw_style_box(theme.get_stylebox(&"panel", &"PanelContainer"), Rect2(Vector2.ZERO, Layout.SIZE * UNIT))
		draw_string(font, Vector2(25, 55), keyboard.router.target_name(), HORIZONTAL_ALIGNMENT_LEFT, 1900,
				font_size, Style.color(&"text"))
		_box(Rect2(20.5, 0.12, 2.3, 0.65), tr("Close"), false, font, font_size)
		for i in 3:
			_box(Rect2(0.15 + i * 7.6, 1.0, 7.4, 0.7), "", false, font, font_size)
	for i in keyboard.state.keys.size():
		var k: Dictionary = keyboard.state.keys[i]
		var code := int(k.code)
		var legend := str(k.legend)
		if code >= KEY_A and code <= KEY_Z:
			legend = legend.to_upper() if keyboard.state.modifier_on(KEY_SHIFT) != keyboard.state.caps else legend
		elif str(k.shifted) != "":
			legend = str(k.shifted) + "\n" + legend
		var on: bool = keyboard.state.lit(i)
		var hovered: bool = keyboard.aims.values().any(func(a: Dictionary) -> bool: return int(a.get("key", -1)) == i)
		if candidates_only and not (on or hovered):
			continue
		var lamp := on and (code in Layout.MODIFIERS or code in [KEY_CAPSLOCK, KEY_NUMLOCK, KEY_SCROLLLOCK])
		_box(k.rect, legend, on or hovered if candidates_only else lamp, font, font_size)
		if lamp:
			var r: Rect2 = k.rect
			draw_circle((r.position + Vector2(0.13, 0.13)) * UNIT, 5, Style.color(&"accent"))
			if int(keyboard.state.modifiers.get(i, 0)) == 2:
				draw_circle((r.position + Vector2(0.28, 0.13)) * UNIT, 5, Style.color(&"accent"))
	if not candidates_only:
		return
	var now := Time.get_ticks_msec() / 1000.0
	for trail: Array in keyboard.trails.values():
		for i in range(1, trail.size()):
			var ink := Style.color(&"accent")
			ink.a *= clampf(1.0 - (now - float(trail[i].time)) / 0.7, 0.0, 1.0)
			draw_line(trail[i - 1].point * UNIT, trail[i].point * UNIT, ink, 5.0, true)


func _box(rect: Rect2, text: String, on: bool, font: Font, font_size: int) -> void:
	var r := Rect2(rect.position * UNIT, rect.size * UNIT)
	var theme := Style.active()
	draw_style_box(theme.get_stylebox(&"pressed" if on else &"normal", &"KeyButton"), r)
	var lines := text.split("\n")
	var height := font.get_height(font_size)
	for i in lines.size():
		var at := Vector2(r.position.x, r.get_center().y - height * lines.size() / 2.0 + font.get_ascent(font_size) + i * height)
		draw_string(font, at, lines[i], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, font_size, Style.color(&"text"))
