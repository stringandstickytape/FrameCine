extends Node3D

## One PC window in the headset (docs/pc-windows.md, "Panes"): the window's picture on a quad facing +Z, on the
## private render layer only (VideoScreen.PRIVATE_LAYER: the room snapshots for assistants never see it), with a bar
## under it holding Close and Show on the big screen. pc_windows.gd makes, moves and feeds it; this node draws it and
## answers where a ray meets it.
## Size: about one PC pixel to one headset pixel (PIXELS_PER_DEGREE) at the distance it was put, until resized.
## While it has the focus (the one looked at) a thin outline in the accent colour runs round it.

const PcVideo := preload("res://scripts/pc/pc_video.gd")
const VideoScreen := preload("res://scripts/video_screen.gd")
const PaneStyle := preload("res://ui/pane_style.gd")
const SHADER := preload("res://shaders/pc_pane.gdshader")

## The Frame's panels: 2160 pixels across about 108 degrees.
const PIXELS_PER_DEGREE := 20.0
const BAR_HEIGHT := 0.07
const BAR_GAP := 0.012
const BUTTON_WIDTH := 0.36
const MIN_WIDTH := 0.2
const MAX_WIDTH := 8.0

## The PC (its client id) and the window's id on it.
var client_id := ""
var window_id := ""
## The stream number asked for it.
var stream := -1
var title := ""
var video: PcVideo
## Metres across; the height follows the picture's aspect.
var width := 1.0
## Pixels of the picture (the stream's, else the window's from the list).
var pixels := Vector2i(1280, 720)
## The window is the big screen's source now: the pane hides.
var on_screen := false
var focused := false
## "close" or "screen" while a ray is over that button, else "".
var hover_button := ""
var material: ShaderMaterial
var _quad: MeshInstance3D
var _bar: Node3D
var _buttons := {}
var _labels := {}
var _focus_level := 0.0


func _ready() -> void:
	material = ShaderMaterial.new()
	material.shader = SHADER
	var accent := Color(0.36, 0.62, 1.0)
	if PaneStyle.theme() != null and PaneStyle.theme().has_color(&"accent", &"Tokens"):
		accent = PaneStyle.color(&"accent")
	material.set_shader_parameter("outline_colour", accent)
	_quad = _private(MeshInstance3D.new())
	_quad.name = "Picture"
	_quad.mesh = QuadMesh.new()
	_quad.material_override = material
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_quad)
	_bar = Node3D.new()
	_bar.name = "Bar"
	add_child(_bar)
	for b: Array in [["close", "Close"], ["screen", "Show on the big screen"]]:
		var m := MeshInstance3D.new()
		m.name = str(b[0]).capitalize()
		m.mesh = QuadMesh.new()
		(m.mesh as QuadMesh).size = Vector2(BUTTON_WIDTH, BAR_HEIGHT)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.12, 0.13, 0.15)
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_bar.add_child(m)
		var l := Label3D.new()
		l.text = b[1]
		l.pixel_size = 0.0006
		l.font_size = 44
		l.position.z = 0.001
		l.modulate = Color(0.92, 0.93, 0.95)
		l.outline_size = 0
		m.add_child(l)
		_buttons[b[0]] = m
		_labels[b[0]] = l
	_layout()


## The private layer only: never in a snapshot.
func _private(n: VisualInstance3D) -> VisualInstance3D:
	n.set_layer_mask_value(1, false)
	n.set_layer_mask_value(VideoScreen.PRIVATE_LAYER, true)
	return n


## Starts on the video's planes (the material keeps the same plane textures from then on: pc_video.gd).
func attach(p_video: PcVideo) -> void:
	video = p_video
	video.format_changed.connect(_on_format)


func _on_format() -> void:
	if video == null:
		return
	material.set_shader_parameter("y_tex", video.get_plane_texture(0))
	material.set_shader_parameter("uv_tex", video.get_plane_texture(1))
	material.set_shader_parameter("p010", video.is_p010())
	var r := video.get_visible_uv_rect()
	material.set_shader_parameter("visible_rect", Vector4(r.position.x, r.position.y, r.size.x, r.size.y))
	material.set_shader_parameter("has_picture", true)
	var s := video.size()
	if s.x > 0 and s.y > 0 and s != pixels:
		pixels = s
		_layout()


## Metres across for one PC pixel per headset pixel at `distance`.
static func natural_width(px: int, distance: float) -> float:
	var degrees := float(px) / PIXELS_PER_DEGREE
	return clampf(2.0 * distance * tan(deg_to_rad(minf(degrees, 150.0)) / 2.0), MIN_WIDTH, MAX_WIDTH)


func height() -> float:
	return width * float(pixels.y) / float(maxi(pixels.x, 1))


func set_width(w: float) -> void:
	width = clampf(w, MIN_WIDTH, MAX_WIDTH)
	_layout()


func _layout() -> void:
	if _quad == null:
		return
	var h := height()
	(_quad.mesh as QuadMesh).size = Vector2(width, h)
	material.set_shader_parameter("size_m", Vector2(width, h))
	material.set_shader_parameter("outline_m", clampf(width * 0.003, 0.002, 0.01))
	_bar.position = Vector3(0, -h / 2.0 - BAR_GAP - BAR_HEIGHT / 2.0, 0)
	(_buttons["close"] as Node3D).position.x = -BUTTON_WIDTH / 2.0 - 0.01
	(_buttons["screen"] as Node3D).position.x = BUTTON_WIDTH / 2.0 + 0.01
	_quad.visible = not on_screen


## On the big screen the picture is there instead: only the bar stays (Close, Back to a pane).
func set_on_screen(on: bool) -> void:
	on_screen = on
	if _quad != null:
		_quad.visible = not on


func set_focused(on: bool) -> void:
	focused = on


func _process(delta: float) -> void:
	_focus_level = move_toward(_focus_level, 1.0 if focused else 0.0, delta * 8.0)
	material.set_shader_parameter("outline", _focus_level)
	for b: String in _buttons:
		var mat: StandardMaterial3D = (_buttons[b] as MeshInstance3D).material_override
		mat.albedo_color = Color(0.22, 0.32, 0.5) if hover_button == b else Color(0.12, 0.13, 0.15)


func set_labels(close_text: String, screen_text: String) -> void:
	if _labels.is_empty():
		return
	(_labels["close"] as Label3D).text = close_text
	(_labels["screen"] as Label3D).text = screen_text


## Where a ray meets the pane: {"pixel": Vector2 (picture pixels, 0..w, 0..h), "distance"}, {"button": "close" |
## "screen", "distance"}, or {} when it misses (or the pane is hidden).
func hit(origin: Vector3, direction: Vector3) -> Dictionary:
	if not visible or not is_inside_tree():
		return {}
	var to_local := global_transform.affine_inverse()
	var o := to_local * origin
	var d := to_local.basis * direction
	if absf(d.z) < 1e-6:
		return {}
	var t := -o.z / d.z
	if t <= 0.0:
		return {}
	var p := o + d * t
	var dist := origin.distance_to(global_transform * p)
	var h := height()
	if not on_screen and absf(p.x) <= width / 2.0 and absf(p.y) <= h / 2.0:
		var uv := Vector2(p.x / width + 0.5, 0.5 - p.y / h)
		return {"pixel": uv * Vector2(pixels), "distance": dist}
	var by := p.y - _bar.position.y
	if absf(by) <= BAR_HEIGHT / 2.0:
		for b: String in _buttons:
			if absf(p.x - (_buttons[b] as Node3D).position.x) <= BUTTON_WIDTH / 2.0:
				return {"button": b, "distance": dist}
	return {}


## The point on the pane (world) at a picture pixel: where the cursor sprite goes.
func pixel_to_world(px: Vector2) -> Vector3:
	var uv := px / Vector2(maxf(pixels.x, 1), maxf(pixels.y, 1))
	return global_transform * Vector3((uv.x - 0.5) * width, (0.5 - uv.y) * height(), 0.002)


## Faces the head from where it is, upright.
func face(head_pos: Vector3) -> void:
	var to := head_pos - global_position
	to.y = 0.0
	if to.length() < 0.01:
		return
	global_basis = Basis.looking_at(-to.normalized(), Vector3.UP)


func status() -> Dictionary:
	return {"window": window_id, "stream": stream, "width_m": snappedf(width, 0.01), "pixels": [pixels.x, pixels.y],
			"on_screen": on_screen, "focused": focused,
			"position": [snappedf(global_position.x, 0.01), snappedf(global_position.y, 0.01),
					snappedf(global_position.z, 0.01)]}


func close() -> void:
	if video != null:
		if video.format_changed.is_connected(_on_format):
			video.format_changed.disconnect(_on_format)
		video = null
	queue_free()
