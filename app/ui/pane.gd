extends Node3D

## The panel as an object in the world (docs/ui-design.md, "Revision 2"): pane_ui.gd rendered in a SubViewport onto a
## borderless quad facing +Z, with a soft halo quad behind it in the edge colour. No bezel, no thickness. Pointers (the
## pointer controller's laser, a poke with its tip, the mouse ray on a desktop) become mouse events pushed into the
## viewport, so ordinary Controls work; the stick focus becomes ui_* actions. The viewport renders only while
## the panel can be seen. Opacity fades in place over the token fade_ms.
##
## Lists are dragged (the user, 2026-11-04: push through, drag, pull back out): a press that moves more than DRAG_SLOP
## metres up or down, inside a ScrollContainer that has more than it shows (and not on a slider), lets go of the
## press away from everything (so the button under it doesn't fire) and moves the list with the pointer; let go while
## moving and it carries on, slowing (DRAG_FRICTION per second). A press that hardly moves is an ordinary click.
## configure() gives the pane another size and resolution (the tablet's, ui/tablet.gd), and halo_shown its halo.
## render_scale draws it at more pixels than it is laid out in (the viewport's size_2d_override, stretched): the
## tablet makes everything bigger with fewer layout pixels per metre and keeps it sharp this way. Pointer pixels are
## layout pixels.

const PaneStyle := preload("res://ui/pane_style.gd")
const PaneUI := preload("res://ui/pane_ui.gd")

## The pane quad. The design's alphas (the surface at 94 %) are meant as sRGB compositing; blended in linear light, as
## the renderer does, 6 % of a bright film shows through as about a quarter of its brightness. 1 - (1 - a)^2.2 gives
## about the sRGB result over a bright background. `opacity` (the fades) is part of `a`, so it
## reads as designed too.
const PANE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_opaque, cull_back, shadows_disabled;
uniform sampler2D tex : source_color, filter_linear;
uniform float opacity = 1.0;
void fragment() {
	vec4 c = texture(tex, UV);
	ALBEDO = c.rgb;
	ALPHA = 1.0 - pow(1.0 - c.a * opacity, 2.2);
}
"""
const HALO_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;
uniform vec4 colour : source_color;
uniform vec2 inner;
uniform float radius;
uniform float spread;
uniform float opacity;
varying vec3 p;
void vertex() { p = VERTEX; }
void fragment() {
	vec2 q = abs(p.xy) - inner + vec2(radius);
	float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
	float a = d > 0.0 ? exp(-4.0 * d / spread) * (1.0 - smoothstep(0.7 * spread, spread, d)) : 0.0;
	ALBEDO = colour.rgb;
	ALPHA = colour.a * a * opacity;
}
"""

## Metres a press may move and still be a click; how fast a let-go list slows (per second); the speed it stops at
## (pixels per second).
## Render priority of a pane's quad: over the things drawn at the screen without a depth test (the info overlay, the
## screen card, subtitles, toasts: up to 11), under the seat choice's veil. The halo is one below.
const PRIORITY := 12
const DRAG_SLOP := 0.006
const DRAG_FRICTION := 5.0
const DRAG_STOP := 20.0
## Seconds the speed takes as the least time between two moves, and the fastest a list carries on (pixels per
## second).
const DRAG_MIN_STEP := 1.0 / 120.0
const DRAG_MAX_SPEED := 3000.0

## Physical size (metres) and viewport size (pixels), from the theme tokens and [pane] scale.
var size_m := Vector2(0.24, 0.195)
var resolution := Vector2i(740, 600)
var viewport: SubViewport
var ui: PaneUI
var opacity := 0.0
var _target_opacity := 0.0
var _mesh: MeshInstance3D
var _mat: ShaderMaterial
var _halo: MeshInstance3D
var _halo_mat: ShaderMaterial
var _last_pixel := Vector2(-1, -1)
var _pressed := false
var halo_shown := true
## Drawn pixels per layout pixel (configure()).
var render_scale := 1.0
## A list being dragged: the ScrollContainer under the press (null: none), where the press was and the list's scroll
## then, and its speed (scroll pixels per second) for carrying on after.
var dragging := false
var _drag_scroll: ScrollContainer
var _press_pixel := Vector2.ZERO
var _press_scroll := 0.0
var _drag_speed := 0.0
var _drag_last_y := 0.0
var _drag_last_t := 0.0
var _coast: ScrollContainer
var _coast_scroll := 0.0


func _init(scale := 1.0) -> void:
	resolution = PaneStyle.pane_pixels()
	size_m = PaneStyle.pane_metres(scale)


## Changes the physical size (1 = the theme's 24 cm wide; the default [pane] scale is 1.6); the pixels stay the same.
func set_size_scale(scale: float) -> void:
	size_m = PaneStyle.pane_metres(maxf(scale, 0.1))
	if _mesh != null:
		(_mesh.mesh as QuadMesh).size = size_m
		apply_style()


## Another size (metres), resolution (layout pixels) and render scale: the tablet's (ui/tablet.gd), or the theme's
## again.
func configure(p_size_m: Vector2, p_resolution: Vector2i, p_render_scale := 1.0) -> void:
	size_m = p_size_m
	resolution = p_resolution
	render_scale = maxf(p_render_scale, 0.25)
	if _mesh == null:
		return
	var stretched := not is_equal_approx(render_scale, 1.0)
	viewport.size = Vector2i((Vector2(resolution) * render_scale).round())
	viewport.size_2d_override = resolution if stretched else Vector2i.ZERO
	viewport.size_2d_override_stretch = stretched
	ui.size = Vector2(resolution)
	(_mesh.mesh as QuadMesh).size = size_m
	apply_style()


func _ready() -> void:
	viewport = SubViewport.new()
	viewport.name = "Viewport"
	viewport.size = resolution
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.gui_embed_subwindows = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	ui = PaneUI.new()
	ui.position = Vector2.ZERO
	ui.size = Vector2(resolution)
	viewport.add_child(ui)

	_mat = ShaderMaterial.new()
	var pane_shader := Shader.new()
	pane_shader.code = PANE_SHADER
	_mat.shader = pane_shader
	_mat.set_shader_parameter("tex", viewport.get_texture())
	# Above the things drawn at the screen without a depth test (the info overlay, the screen card, subtitles, toasts:
	# priorities up to 11), which showed through the pane (the user, 2026-11-05). The pane is held close; it wins.
	_mat.render_priority = PRIORITY
	var quad := QuadMesh.new()
	quad.size = size_m
	_mesh = MeshInstance3D.new()
	_mesh.name = "Quad"
	_mesh.mesh = quad
	_mesh.material_override = _mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)

	_halo_mat = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = HALO_SHADER
	_halo_mat.shader = shader
	_halo_mat.render_priority = PRIORITY - 1
	_halo = MeshInstance3D.new()
	_halo.name = "Halo"
	_halo.material_override = _halo_mat
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_halo.position = Vector3(0, 0, -0.0005)
	add_child(_halo)
	apply_style()
	PaneStyle.holder().changed.connect(apply_style)
	_set_opacity(0.0)


## Re-reads the tokens the 3D parts use (halo colour and spread, corner radius).
func apply_style() -> void:
	var px_to_m := size_m.x / float(resolution.x)
	var spread := PaneStyle.constant(&"halo_px") * px_to_m
	var halo_quad := QuadMesh.new()
	halo_quad.size = size_m + Vector2.ONE * spread * 2.0
	_halo.mesh = halo_quad
	_halo_mat.set_shader_parameter("colour", PaneStyle.color(&"halo"))
	_halo_mat.set_shader_parameter("inner", size_m * 0.5)
	_halo_mat.set_shader_parameter("radius", PaneStyle.constant(&"radius_pane") * px_to_m)
	_halo_mat.set_shader_parameter("spread", spread)
	_halo.visible = halo_shown
	if ui != null:
		ui.apply_style()


## Fades toward `a` (0 hidden, 1 full) over the token fade_ms, in place.
func fade_to(a: float) -> void:
	_target_opacity = a


func _process(delta: float) -> void:
	_coast_step(delta)
	if is_equal_approx(opacity, _target_opacity):
		return
	var step := delta / maxf(PaneStyle.constant(&"fade_ms") / 1000.0, 0.001)
	_set_opacity(move_toward(opacity, _target_opacity, step))


func _set_opacity(a: float) -> void:
	opacity = a
	_mat.set_shader_parameter("opacity", a)
	_halo_mat.set_shader_parameter("opacity", a)
	var shown := a > 0.001
	if shown != visible:
		visible = shown
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if shown else SubViewport.UPDATE_DISABLED
		if not shown:
			pointer_exit()


func is_shown() -> bool:
	return visible


## {"pixel": Vector2, "distance": float, "point": Vector3} where the ray meets the pane's front, or {} if it misses
## (or the pane is hidden).
func ray_hit(origin: Vector3, direction: Vector3) -> Dictionary:
	if not visible:
		return {}
	var inv := global_transform.affine_inverse()
	var o := inv * origin
	var d := inv.basis * direction
	if o.z <= 0.0 or d.z >= -1e-6:
		return {}
	var t := -o.z / d.z
	var p := o + d * t
	if absf(p.x) > size_m.x * 0.5 or absf(p.y) > size_m.y * 0.5:
		return {}
	var world := global_transform * p
	return {"pixel": local_to_pixel(p), "distance": world.distance_to(origin), "point": world}


## For the poke: the point's distance in front of the pane (negative behind it), and its pixel if it is over the pane.
func poke_probe(point: Vector3) -> Dictionary:
	var p := global_transform.affine_inverse() * point
	var inside := absf(p.x) <= size_m.x * 0.5 and absf(p.y) <= size_m.y * 0.5
	return {"depth": p.z, "inside": inside, "pixel": local_to_pixel(p)}


func local_to_pixel(p: Vector3) -> Vector2:
	return Vector2((p.x / size_m.x + 0.5) * resolution.x, (0.5 - p.y / size_m.y) * resolution.y)


func pixel_to_world(pixel: Vector2) -> Vector3:
	var local := Vector3((pixel.x / resolution.x - 0.5) * size_m.x, (0.5 - pixel.y / resolution.y) * size_m.y, 0.0)
	return global_transform * local


func pointer_move(pixel: Vector2) -> void:
	if _pressed and _drag_scroll != null and not dragging:
		var moved := pixel - _press_pixel
		if absf(moved.y) > DRAG_SLOP / size_m.x * resolution.x and absf(moved.y) > absf(moved.x):
			_begin_drag(pixel)
	if dragging:
		_drag_to(pixel)
		_last_pixel = pixel
		return
	var ev := InputEventMouseMotion.new()
	ev.position = pixel
	ev.global_position = pixel
	ev.relative = pixel - _last_pixel if _last_pixel.x >= 0.0 else Vector2.ZERO
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if _pressed else 0
	_last_pixel = pixel
	viewport.push_input(ev, true)


func pointer_button(pixel: Vector2, pressed: bool) -> void:
	if pixel != _last_pixel:
		pointer_move(pixel)
	if not pressed and dragging:
		# The press was let go when the drag began: the list carries on from here.
		_end_drag()
		return
	if pressed:
		_coast = null
		_press_pixel = pixel
		_drag_scroll = scroll_under(hovered_control())
		if _drag_scroll != null:
			_press_scroll = _drag_scroll.scroll_vertical
	else:
		_drag_scroll = null
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pixel
	ev.global_position = pixel
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	_pressed = pressed
	viewport.push_input(ev, true)


## The stick's smooth scroll (scroll_by()): the list it moves and where, to a fraction of a pixel.
var _smooth: ScrollContainer
var _smooth_pos := 0.0


## Smooth scrolling (the stick; the user, 2026-11-06: wheel steps jumped): the list under the pointer moves by
## `pixels` (> 0 up), the fraction of a pixel kept for the next frame. False when nothing there scrolls (a slider,
## a list that fits): the caller steps the wheel instead.
func scroll_by(pixels: float) -> bool:
	var sc := scroll_under(hovered_control())
	if sc == null:
		return false
	if sc != _smooth or sc.scroll_vertical != roundi(_smooth_pos):
		_smooth = sc
		_smooth_pos = sc.scroll_vertical
	_coast = null
	var bar := sc.get_v_scroll_bar()
	_smooth_pos = clampf(_smooth_pos - pixels, 0.0, maxf(bar.max_value - bar.page, 0.0))
	sc.scroll_vertical = roundi(_smooth_pos)
	return true


## steps > 0 scrolls up.
func pointer_scroll(pixel: Vector2, steps: int) -> void:
	for i in absi(steps):
		for pressed in [true, false]:
			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_WHEEL_UP if steps > 0 else MOUSE_BUTTON_WHEEL_DOWN
			ev.pressed = pressed
			ev.factor = 1.0
			ev.position = pixel
			ev.global_position = pixel
			viewport.push_input(ev, true)


func is_pressed() -> bool:
	return _pressed


## The pointer left the pane: release a held button there and clear hover (a drag ends where it is).
func pointer_exit() -> void:
	if dragging:
		_end_drag()
	if _pressed and _last_pixel.x >= 0.0:
		pointer_button(_last_pixel, false)
	if _last_pixel.x >= 0.0:
		pointer_move(Vector2(-1000, -1000))
	_last_pixel = Vector2(-1, -1)


## Stick focus: ui_up / ui_down / ui_left / ui_right / ui_accept, pressed then released.
func push_action(action: StringName) -> void:
	for pressed in [true, false]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = pressed
		viewport.push_input(ev, true)


# --- Dragging a list -----------------------------------------------------------------------------------------------

## The ScrollContainer a press on `c` would drag: the nearest one round it with more than it shows; null for none, or
## for a slider (it is dragged sideways itself).
static func scroll_under(c: Control) -> ScrollContainer:
	var n: Node = c
	while n != null and n is Control:
		if n is Slider:
			return null
		if n is ScrollContainer and (n as ScrollContainer).vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
			var bar := (n as ScrollContainer).get_v_scroll_bar()
			if bar.max_value - bar.page > 0.5:
				return n
		n = n.get_parent()
	return null


func _begin_drag(pixel: Vector2) -> void:
	dragging = true
	_drag_speed = 0.0
	_drag_last_y = pixel.y
	_drag_last_t = Time.get_ticks_usec() / 1000000.0
	# Let go of the press away from everything: the button under it doesn't fire.
	var away := Vector2(-1000, -1000)
	var move := InputEventMouseMotion.new()
	move.position = away
	move.global_position = away
	move.button_mask = MOUSE_BUTTON_MASK_LEFT
	viewport.push_input(move, true)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = away
	up.global_position = away
	viewport.push_input(up, true)


func _drag_to(pixel: Vector2) -> void:
	if not is_instance_valid(_drag_scroll):
		return
	_drag_scroll.scroll_vertical = roundi(_press_scroll - (pixel.y - _press_pixel.y))
	var now := Time.get_ticks_usec() / 1000000.0
	# Moves can come close together (two in a frame): not less than DRAG_MIN_STEP apart, and no faster than
	# DRAG_MAX_SPEED, or a let-go list would fly to its end.
	var dt := maxf(now - _drag_last_t, DRAG_MIN_STEP)
	var speed := clampf(-(pixel.y - _drag_last_y) / dt, -DRAG_MAX_SPEED, DRAG_MAX_SPEED)
	_drag_speed = lerpf(_drag_speed, speed, 0.5)
	_drag_last_y = pixel.y
	_drag_last_t = now


func _end_drag() -> void:
	dragging = false
	_pressed = false
	_coast = _drag_scroll if is_instance_valid(_drag_scroll) else null
	_drag_scroll = null
	if _coast != null:
		_coast_scroll = _coast.scroll_vertical


## A let-go list carries on, slowing, until it stops, reaches an end, or something else scrolls it.
func _coast_step(delta: float) -> void:
	if _coast == null:
		return
	if not is_instance_valid(_coast) or absf(_drag_speed) < DRAG_STOP 			or _coast.scroll_vertical != roundi(_coast_scroll):
		_coast = null
		return
	_coast_scroll += _drag_speed * delta
	_drag_speed *= exp(-DRAG_FRICTION * delta)
	var before := _coast.scroll_vertical
	_coast.scroll_vertical = roundi(_coast_scroll)
	if _coast.scroll_vertical == before and absf(_drag_speed * delta) >= 1.0:
		_coast = null


## The control under the pointer, or null.
func hovered_control() -> Control:
	return viewport.gui_get_hovered_control()


func focus_owner() -> Control:
	return viewport.gui_get_focus_owner()
