extends Node3D

## The buttons beside the screen (docs/visualisers.md, "On the screen for anything"): while the menu shows and
## something flat plays, a small themed panel hangs just right of the picture's bottom-right corner with
##   Visualiser        on: the visualiser takes the picture's place (a film, a captured window), or shows on the
##                     music card; off: the picture, or a card without one
##   previous, next    step through the visualisers (they turn it on), with the name of the one chosen between them
## (scripts/play/screen_visualiser.gd does the work). The laser and the trigger press them (ui/ui_layer.gd routes its
## hit here as it does the watch card's); on a desktop, the mouse.
## Built as the watch card is (ui/watch_card.gd): a viewport with the pane's theme on a quad that faces the viewer,
## about ANGLE wide at its distance, no further than NEAR_DISTANCE from the head.
##
##   shown() -> bool
##   ray_hit(origin, direction) -> {distance, point} or {}
##   click(point) -> String     the button pressed there ("toggle", "previous", "next", "" for none)
##   button_point(id) -> Variant   where a button is, as a world point (tests)

const PaneStyle := preload("res://ui/pane_style.gd")
const W := preload("res://ui/pane_widgets.gd")
const Pane := preload("res://ui/pane.gd")
const Icons := preload("res://ui/icons.gd")

const WIDTH_PX := 460
const ANGLE := deg_to_rad(22.0)
const GAP := 0.025
const FRONT := 0.02
const NEAR_DISTANCE := 2.0

## scripts/main.gd
var app: Node3D
var viewport: SubViewport
var size_m := Vector2(0.4, 0.1)
var _root: PanelContainer
var _toggle: Button
var _previous: Button
var _next: Button
var _name: Label
var _mesh: MeshInstance3D
var _mat: ShaderMaterial
var _opacity := 0.0
var _target := 0.0
var _buttons := {}


func _ready() -> void:
	viewport = SubViewport.new()
	viewport.name = "ScreenButtonsViewport"
	viewport.size = Vector2i(WIDTH_PX, 120)
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	_root = PanelContainer.new()
	_root.theme = PaneStyle.theme()
	_root.theme_type_variation = &"PaneRoot"
	_root.custom_minimum_size = Vector2(WIDTH_PX, 0)
	viewport.add_child(_root)
	var box := W.vbox()
	_root.add_child(box)
	# The laser presses these (click()); the viewport takes no input of its own.
	_toggle = W.toggle("Visualiser", func(_on: bool) -> void: pass)
	_toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(_toggle)
	var px := roundi(PaneStyle.constant(&"button_height") * 0.5)
	_previous = W.button("", func() -> void: pass)
	_previous.icon = Icons.texture("previous", px, PaneStyle.color(&"text"))
	_next = W.button("", func() -> void: pass)
	_next.icon = Icons.texture("next", px, PaneStyle.color(&"text"))
	# A visualiser's name is its manifest's (content).
	_name = W.ellipsis(W.label(""))
	W.content(_name)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(W.hbox([_previous, _name, _next]))
	_buttons = {"toggle": _toggle, "previous": _previous, "next": _next}

	_mat = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = Pane.PANE_SHADER
	_mat.shader = shader
	_mat.set_shader_parameter("tex", viewport.get_texture())
	_mat.set_shader_parameter("opacity", 0.0)
	# As the watch card: above the windows to the real room.
	_mat.render_priority = 4
	_mesh = MeshInstance3D.new()
	_mesh.name = "ScreenButtonsQuad"
	_mesh.mesh = QuadMesh.new()
	_mesh.material_override = _mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	visible = false


func _vis() -> Node:
	return app.features.get("screen_vis") if app != null and app.get("features") != null else null


## Wanted now: the menu shows and something flat plays.
func wanted() -> bool:
	var vis := _vis()
	return vis != null and bool(app.get("menu_shown")) and bool(vis.usable())


func shown() -> bool:
	return visible and _target > 0.0


func _process(delta: float) -> void:
	var want := wanted()
	_target = 1.0 if want else 0.0
	if want and not visible:
		visible = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if not visible:
		return
	var step := delta / maxf(PaneStyle.constant(&"fade_ms") / 1000.0, 0.001)
	_opacity = move_toward(_opacity, _target, step)
	_mat.set_shader_parameter("opacity", _opacity)
	if _opacity <= 0.0 and _target <= 0.0:
		visible = false
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	_sync()
	_fit()
	place()


func _sync() -> void:
	var vis := _vis()
	if vis == null:
		return
	W.set_on(_toggle, bool(vis.is_on()))
	var n := str(vis.style_name())
	if _name.text != n:
		_name.text = n


func _fit() -> void:
	var h := clampi(int(_root.get_combined_minimum_size().y), 40, 400)
	if viewport.size != Vector2i(WIDTH_PX, h):
		viewport.size = Vector2i(WIDTH_PX, h)
	_root.size = Vector2(WIDTH_PX, h)


## Hung by its bottom-left corner just right of the picture's bottom-right corner, square to the viewer.
func place() -> void:
	if app == null:
		return
	var head: Vector3 = app.camera.global_position
	var aspect := float(viewport.size.y) / WIDTH_PX
	var screen: Node3D = app.screen
	var corner: Vector3 = screen.top_right_corner() - screen.global_basis.y.normalized() * float(screen.get_flat_size().y)
	var dir: Vector3 = (corner - head).normalized() if corner.distance_to(head) > 0.01 else -app.camera.global_basis.z
	var dist := minf(corner.distance_to(head), NEAR_DISTANCE)
	var w := 2.0 * dist * tan(ANGLE * 0.5)
	size_m = Vector2(w, w * aspect)
	# A little nearer than the corner, so the screen's edge never covers the panel's.
	var bottom_left: Vector3 = head + dir * (dist - FRONT * dist)
	var to_head: Vector3 = head - bottom_left
	to_head.y = 0.0
	var basis := Basis.looking_at(to_head, Vector3.UP, true) if to_head.length() > 0.01 else Basis()
	var pos: Vector3 = bottom_left + basis.x * (GAP * dist + size_m.x * 0.5) + basis.y * size_m.y * 0.5
	global_transform = Transform3D(basis, pos)
	(_mesh.mesh as QuadMesh).size = size_m


## The trigger at `point` (a ray_hit point): presses the button there. Returns its id, or "".
func click(point: Vector3) -> String:
	var vis := _vis()
	if not shown() or vis == null:
		return ""
	var p := global_transform.affine_inverse() * point
	var px := Vector2((p.x / size_m.x + 0.5) * viewport.size.x, (0.5 - p.y / size_m.y) * viewport.size.y)
	for id: String in _buttons:
		if (_buttons[id] as Control).get_global_rect().grow(4.0).has_point(px):
			match id:
				"toggle":
					vis.toggle()
				"previous":
					vis.step(-1)
				"next":
					vis.step(1)
			_sync()
			return id
	return ""


func button_point(id: String) -> Variant:
	if not _buttons.has(id):
		return null
	var c := (_buttons[id] as Control).get_global_rect().get_center()
	return global_transform * Vector3((c.x / viewport.size.x - 0.5) * size_m.x,
			(0.5 - c.y / viewport.size.y) * size_m.y, 0.0)


## {"distance": float, "point": Vector3} where the ray meets the panel, or {}.
func ray_hit(origin: Vector3, direction: Vector3) -> Dictionary:
	if not shown():
		return {}
	var inv := global_transform.affine_inverse()
	var o := inv * origin
	var dv := inv.basis * direction
	if o.z <= 0.0 or dv.z >= -1e-6:
		return {}
	var t := -o.z / dv.z
	var p := o + dv * t
	if absf(p.x) > size_m.x * 0.5 or absf(p.y) > size_m.y * 0.5:
		return {}
	var world := global_transform * p
	return {"distance": world.distance_to(origin), "point": world}
