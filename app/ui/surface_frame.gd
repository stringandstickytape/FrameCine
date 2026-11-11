extends Node3D
## What every surface wears while the UI is shown (docs/dev/surfaces-design.md): a title bar over its picture, a side
## stack of its buttons joined to its right edge, and a glow outside all three. A child of the surface's node, which
## faces +Z with its picture centred on the origin. This node draws them and says what a point on the surface's plane
## is on; the surface's owner (scripts/pc/pc_windows.gd, scripts/agents/local_agents.gd) acts on it.
##
## Sizes are shares of the picture's own height (the user, 2026-11-11: sizing by angle looks wrong; minimums may come
## later). The bar is the picture's width: its name is the place to click to select the surface and to drag it; Close
## is at its right end. The stack's buttons are a column beside the picture, from the bar's top down, with a ground of
## their own that touches the picture (never words floating in the room).
##
## The glow is outside the surface, never over its picture: nothing inside the outline of the picture, the bar and the
## stack, then a soft light that falls away. It says which surface is selected, and only that (the user, in the
## headset, 2026-11-11: where the laser is needs no highlight, it is plain; and blue, not the theme's accent, which is
## yellow in the tablet's look).
##
##   set_content_size(metres), set_title(text), set_buttons([{id, text}]), has_close
##   set_shown(on)                 the UI is shown: off hides all three and hit() finds nothing
##   set_state(pointed, selected)  the glow: on for the selected surface
##   hover                         the part a pointer is on ("", "bar", "close" or a button's id): drawn lighter
##   hit(point) -> {} or {"part": "bar" | "close" | "button", "id": the button's}; point: metres, in the plane
##   bar_height(), stack_width(), outline() -> the rectangles of the picture with its bar, and of the stack

const PaneStyle := preload("res://ui/pane_style.gd")
const VideoScreen := preload("res://scripts/video_screen.gd")
const Pane := preload("res://ui/pane.gd")
const GLOW := preload("res://shaders/surface_glow.gdshader")

## The bar's height as a share of the picture's height.
const BAR_SHARE := 0.12
## Close's width, and the stack's, in bar heights.
const CLOSE_WIDTHS := 3.0
const STACK_WIDTHS := 5.5
## The type's height as a share of the bar's.
const TEXT_SHARE := 0.5
## How far the glow reaches, as a share of the picture's height.
const GLOW_SHARE := 0.34
const GLOW_POINTED := 0.0
const GLOW_SELECTED := 0.4
const GLOW_COLOUR := Color(0.2, 0.5, 1.0)
const FONT_SIZE := 64

var content_size := Vector2(1.0, 0.5625)
var title := ""
var has_close := true
var hover := "":
	set(v):
		if v != hover:
			hover = v
			_paint()
var shown := true
var _buttons: Array[Dictionary] = []
var _bar: MeshInstance3D
var _title: Label3D
var _close: MeshInstance3D
var _close_text: Label3D
var _stack: Node3D
var _stack_parts := {}
var _glow: MeshInstance3D
var _glow_mat: ShaderMaterial
var _level := 0.0
var _want := 0.0


func _ready() -> void:
	_glow_mat = ShaderMaterial.new()
	_glow_mat.shader = GLOW
	_glow_mat.render_priority = Pane.PRIORITY - 2
	_glow = _mesh("Glow", _glow_mat)
	_glow.position.z = -0.002
	_bar = _mesh("Bar", _flat())
	_title = _label(_bar, HORIZONTAL_ALIGNMENT_LEFT)
	_close = _mesh("Close", _flat())
	_close_text = _label(_close, HORIZONTAL_ALIGNMENT_CENTER)
	_stack = Node3D.new()
	_stack.name = "Stack"
	add_child(_stack)
	_layout()


func _mesh(p_name: String, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.name = p_name
	m.mesh = QuadMesh.new()
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# With the surface's picture: on the layer the snapshots for assistants do not see (a window's title is content).
	m.set_layer_mask_value(1, false)
	m.set_layer_mask_value(VideoScreen.PRIVATE_LAYER, true)
	add_child(m)
	return m


func _flat() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.render_priority = Pane.PRIORITY
	return mat


func _label(on: Node3D, align: HorizontalAlignment) -> Label3D:
	var l := Label3D.new()
	l.font = PaneStyle.active().default_font
	l.font_size = FONT_SIZE
	l.outline_size = 0
	l.horizontal_alignment = align
	l.position.z = 0.001
	l.render_priority = Pane.PRIORITY + 1
	l.set_layer_mask_value(1, false)
	l.set_layer_mask_value(VideoScreen.PRIVATE_LAYER, true)
	on.add_child(l)
	return l


func set_content_size(size: Vector2) -> void:
	if size != content_size and size.x > 0.0 and size.y > 0.0:
		content_size = size
		_layout()


func set_title(text: String) -> void:
	if text != title:
		title = text
		_layout()


## The side stack's buttons, top first: [{"id": String, "text": String}].
func set_buttons(buttons: Array) -> void:
	_buttons.assign(buttons)
	for c in _stack.get_children():
		c.queue_free()
	_stack_parts.clear()
	for b: Dictionary in _buttons:
		var m := MeshInstance3D.new()
		m.mesh = QuadMesh.new()
		m.material_override = _flat()
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.set_layer_mask_value(1, false)
		m.set_layer_mask_value(VideoScreen.PRIVATE_LAYER, true)
		_stack.add_child(m)
		var l := _label(m, HORIZONTAL_ALIGNMENT_CENTER)
		l.text = str(b.get("text", ""))
		_stack_parts[str(b["id"])] = [m, l]
	_layout()


func set_shown(on: bool) -> void:
	shown = on
	visible = on


## pointed: a laser or the mouse is on the surface. selected: typing and voice go to it.
func set_state(pointed: bool, selected: bool) -> void:
	_want = GLOW_SELECTED if selected else (GLOW_POINTED if pointed else 0.0)


func bar_height() -> float:
	return content_size.y * BAR_SHARE


func stack_width() -> float:
	return bar_height() * STACK_WIDTHS if not _buttons.is_empty() else 0.0


## The two rectangles that make the surface's outline, in the plane (metres, the picture centred on the origin): the
## picture with its bar, and the stack (no area without buttons).
func outline() -> Array[Rect2]:
	var w := content_size.x
	var h := content_size.y
	var bh := bar_height()
	var sw := stack_width()
	return [Rect2(-w / 2.0, -h / 2.0, w, h + bh), Rect2(w / 2.0, h / 2.0 + bh - bh * _buttons.size(), sw, bh * _buttons.size())]


## What a point of the surface's plane is on: {} (the picture, or nothing of the frame), {"part": "bar"},
## {"part": "close"}, or {"part": "button", "id"}.
func hit(point: Vector2) -> Dictionary:
	if not shown:
		return {}
	var w := content_size.x
	var h := content_size.y
	var bh := bar_height()
	if point.y >= h / 2.0 and point.y <= h / 2.0 + bh and absf(point.x) <= w / 2.0:
		if has_close and point.x >= w / 2.0 - bh * CLOSE_WIDTHS:
			return {"part": "close"}
		return {"part": "bar"}
	var sw := stack_width()
	if sw > 0.0 and point.x > w / 2.0 and point.x <= w / 2.0 + sw:
		var i := int(floor((h / 2.0 + bh - point.y) / bh))
		if i >= 0 and i < _buttons.size() and point.y <= h / 2.0 + bh:
			return {"part": "button", "id": str(_buttons[i]["id"])}
	return {}


func _layout() -> void:
	if _bar == null:
		return
	var w := content_size.x
	var h := content_size.y
	var bh := bar_height()
	var close_w := bh * CLOSE_WIDTHS if has_close else 0.0
	var pixel := bh * TEXT_SHARE / float(FONT_SIZE)
	(_bar.mesh as QuadMesh).size = Vector2(w, bh)
	_bar.position = Vector3(0.0, h / 2.0 + bh / 2.0, 0.0)
	_title.pixel_size = pixel
	_title.position.x = -w / 2.0 + bh * 0.45
	_title.text = _fit(title, (w - close_w - bh * 0.9) / pixel)
	_close.visible = has_close
	(_close.mesh as QuadMesh).size = Vector2(close_w, bh)
	_close.position = Vector3(w / 2.0 - close_w / 2.0, h / 2.0 + bh / 2.0, 0.0005)
	_close_text.pixel_size = pixel
	_close_text.text = tr("Close")
	var sw := stack_width()
	var i := 0
	for b: Dictionary in _buttons:
		var part: Array = _stack_parts[str(b["id"])]
		var m: MeshInstance3D = part[0]
		(m.mesh as QuadMesh).size = Vector2(sw, bh)
		m.position = Vector3(w / 2.0 + sw / 2.0, h / 2.0 + bh / 2.0 - bh * i, 0.0)
		var l: Label3D = part[1]
		l.pixel_size = pixel
		l.text = _fit(str(b.get("text", "")), (sw - bh * 0.5) / pixel)
		i += 1
	# The glow: one quad round both rectangles, with room for the light to fall away.
	var rects := outline()
	var all := rects[0].merge(rects[1]) if rects[1].has_area() else rects[0]
	var reach := h * GLOW_SHARE
	all = all.grow(reach)
	(_glow.mesh as QuadMesh).size = all.size
	_glow.position = Vector3(all.get_center().x, all.get_center().y, -0.002)
	_glow_mat.set_shader_parameter("quad_size", all.size)
	_glow_mat.set_shader_parameter("reach", reach)
	_glow_mat.set_shader_parameter("box_a", _box(rects[0], all.get_center()))
	_glow_mat.set_shader_parameter("box_b", _box(rects[1], all.get_center()) if rects[1].has_area() else Vector4(0, 0, -1, -1))
	_paint()


## centre x, centre y, half width, half height, against the glow quad's own centre.
static func _box(r: Rect2, centre: Vector2) -> Vector4:
	return Vector4(r.get_center().x - centre.x, r.get_center().y - centre.y, r.size.x / 2.0, r.size.y / 2.0)


## The text cut to a width in font pixels, with "..." when it is cut.
func _fit(text: String, room: float) -> String:
	var font := PaneStyle.active().default_font
	if font == null or font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x <= room:
		return text
	var out := text
	while out.length() > 1 and font.get_string_size(out + "...", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x > room:
		out = out.left(out.length() - 1)
	return out.strip_edges() + "..."


func _paint() -> void:
	if _bar == null:
		return
	var ground := PaneStyle.color(&"surface")
	ground.a = 1.0
	var lit := ground.lerp(GLOW_COLOUR, 0.3)
	var ink := PaneStyle.color(&"text")
	(_bar.material_override as StandardMaterial3D).albedo_color = lit if hover == "bar" else ground
	(_close.material_override as StandardMaterial3D).albedo_color = lit if hover == "close" else ground.lerp(ink, 0.06)
	_title.modulate = ink
	_close_text.modulate = ink
	for id: String in _stack_parts:
		var part: Array = _stack_parts[id]
		((part[0] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = lit if hover == id else ground
		(part[1] as Label3D).modulate = ink
	_glow_mat.set_shader_parameter("colour", GLOW_COLOUR)


func _process(delta: float) -> void:
	if _level != _want:
		_level = move_toward(_level, _want, delta * 4.0)
		_glow_mat.set_shader_parameter("level", _level)
	_glow.visible = _level > 0.001
