## The keyboard's picture in its ordinary SubViewport. Drawing from the layout keeps every hit box aligned with its
## legend, and avoids taking focus from a field in the menu. All ink and boxes use the pane theme.
extends Control

const Layout := preload("res://keyboard/key_layout.gd")
const Style := preload("res://ui/pane_style.gd")
const UNIT := 100.0
var keyboard: Node3D
## Pressed and hovered keys are content: only this second, private picture contains them. The ordinary board has
## just its panel, legends and lock lights, so a room snapshot cannot transcribe a sequence of lit letters.
var lights_only := false
var _ground_from: StyleBox
var _ground_box: StyleBox


func _draw() -> void:
	if keyboard == null:
		return
	var theme := Style.active()
	var font := theme.default_font
	# Two symbol legends must fit in one key even when the tablet's text scale is larger.
	var font_size := mini(theme.default_font_size * 2, 30)
	if not lights_only:
		draw_style_box(_ground(theme), Rect2(Vector2.ZERO, Layout.SIZE * UNIT))
		draw_string(font, Vector2(25, 50 + font.get_ascent(font_size) / 2.0 - 4), keyboard.router.target_name(),
				HORIZONTAL_ALIGNMENT_LEFT, 1900, font_size, Style.color(&"muted"))
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
		if lights_only and not (on or hovered):
			continue
		var lamp := on and (code in Layout.MODIFIERS or code in [KEY_CAPSLOCK, KEY_NUMLOCK, KEY_SCROLLLOCK])
		var look := &"normal"
		if on and (lights_only or lamp):
			look = &"pressed"
		elif lights_only:
			look = &"hover"
		_box(k.rect, legend, look, font, font_size)
		if lamp:
			var r: Rect2 = k.rect
			draw_circle((r.position + Vector2(0.13, 0.13)) * UNIT, 5, Style.color(&"accent"))
			if int(keyboard.state.modifiers.get(i, 0)) == 2:
				draw_circle((r.position + Vector2(0.28, 0.13)) * UNIT, 5, Style.color(&"accent"))


## The pane's own surface and lit edge, made opaque: without a solid ground the legends float in the room, and a
## see-through one lets a bright room wash them out.
func _ground(theme: Theme) -> StyleBox:
	var from := theme.get_stylebox(&"panel", &"PaneRoot")
	if from != _ground_from:
		_ground_from = from
		_ground_box = from.duplicate()
		if _ground_box is StyleBoxFlat:
			(_ground_box as StyleBoxFlat).bg_color.a = 1.0
	return _ground_box


func _box(rect: Rect2, text: String, look: StringName, font: Font, font_size: int) -> void:
	var r := Rect2(rect.position * UNIT, rect.size * UNIT)
	draw_style_box(Style.active().get_stylebox(look, &"KeyButton"), r)
	var lines := text.split("\n")
	var height := font.get_height(font_size)
	for i in lines.size():
		var at := Vector2(r.position.x, r.get_center().y - height * lines.size() / 2.0 + font.get_ascent(font_size) + i * height)
		draw_string(font, at, lines[i], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, font_size, Style.color(&"text"))
