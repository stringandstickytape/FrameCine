extends Node3D

## The terminal of an agent on the headset (scripts/agents/local_agents.gd) in a window of its own that stays where it
## is put in the room, like a PC window's pane (scripts/pc/pc_pane.gd; the user, 2026-11-10: off the controller, a
## window that floats, to place and size). The first time it shows in a run it comes up in front of the head, a little
## below the eyes, facing it; after that it opens where it was left. local_agents moves it (squeeze and hold with the
## laser on it) and sizes it (the stick while holding). It shows the window's picture as it is: sRGB values in a UNORM
## texture, decoded here. Its shape is its window's; on a render layer the snapshots for assistants don't see
## (VideoScreen.PRIVATE_LAYER), so its contents stay in the headset.
##
## Three small signs in the shader: a red dot in the corner while recording, an amber edge while the agent waits on a
## prompt, a blue edge while the viewer's look (or a laser) gives the hand to it (the stick and the trigger go to it
## either way). With both, the blue runs inside the amber.
##
## It comes and goes with an ease of its opacity and a small growth out of its bottom edge. One amount runs both ways,
## so a press in the middle turns it back from where it is.
##
##   app, set_texture(tex, size), set_shown(on), set_recording(on), set_waiting(on), set_looked_at(on), is_shown()
##   set_width(m), width, place_in_front(), face(head_pos), face_along(front)
##   looked_at(origin, dir, margin_deg) -> bool; hit(origin, dir) -> {distance} or {}; faded: gone from sight

signal faded

const VideoScreen := preload("res://scripts/video_screen.gd")

## The window's width when it first shows, metres, and how far ahead. The terminal is 1920 x 1080 (agent_terminal.gd,
## COLUMNS, FONT_PX): 60 cm at 90 cm is about 37 x 21 degrees, the size it had on the controller (30 cm at about
## 45 cm), so its 28 px type is about 0.56 degrees an em, a capital 0.41.
const WIDTH_M := 0.60
const DISTANCE_M := 0.90
## How far below the eyes its middle comes up, metres.
const DROP_M := 0.12
## The stick's limits for its width.
const MIN_WIDTH_M := 0.2
const MAX_WIDTH_M := 4.0
const FADE_SECONDS := 0.2
## Its size at the far end of the fade.
const FADE_SCALE := 0.92
const Pane := preload("res://ui/pane.gd")

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_opaque, cull_back, shadows_disabled;
uniform sampler2D tex : filter_linear;
uniform float opacity = 1.0;
uniform float recording = 0.0;
uniform float waiting = 0.0;
uniform float looked_at = 0.0;
uniform vec2 pixels = vec2(960.0);
vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}
void fragment() {
	vec3 c = to_linear(texture(tex, UV).rgb);
	vec2 px = UV * pixels;
	float edge = min(min(px.x, pixels.x - px.x), min(px.y, pixels.y - px.y));
	c = mix(c, vec3(0.16, 0.52, 1.0), looked_at * step(edge, 16.0 + 16.0 * waiting));
	c = mix(c, vec3(0.95, 0.55, 0.05), waiting * step(edge, 16.0));
	float dot = 1.0 - smoothstep(13.0, 15.0, distance(px, vec2(pixels.x - 30.0, 30.0)));
	c = mix(c, vec3(0.9, 0.08, 0.05), recording * dot);
	ALBEDO = c;
	ALPHA = opacity;
}
"""

## scripts/main.gd
var app: Node
var _mat: ShaderMaterial
var _mesh: MeshInstance3D
var _target := 0.0
## 0 gone to 1 shown, even in time; _apply_fade() eases it.
var _amount := 0.0
## Metres across; the height follows the window's shape.
var width := WIDTH_M
var _aspect := 9.0 / 16.0
var _height := WIDTH_M * 9.0 / 16.0
## It has been put somewhere in this run (the first show places it in front).
var placed := false


func _ready() -> void:
	_mat = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = SHADER
	_mat.shader = shader
	_mat.render_priority = Pane.PRIORITY
	_mesh = MeshInstance3D.new()
	_mesh.name = "AgentQuad"
	_mesh.mesh = QuadMesh.new()
	_mesh.material_override = _mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.set_layer_mask_value(VideoScreen.PRIVATE_LAYER, true)
	_mesh.set_layer_mask_value(1, false)
	add_child(_mesh)
	_apply_fade()
	visible = false


func set_texture(tex: Texture2D, size: Vector2i) -> void:
	_mat.set_shader_parameter("tex", tex)
	if size.x > 0 and size.y > 0:
		_mat.set_shader_parameter("pixels", Vector2(size))
		_aspect = float(size.y) / size.x
		_layout()


func set_width(w: float) -> void:
	width = clampf(w, MIN_WIDTH_M, MAX_WIDTH_M)
	_layout()


func _layout() -> void:
	_height = width * _aspect
	(_mesh.mesh as QuadMesh).size = Vector2(width, _height)
	_apply_fade()


func set_shown(on: bool) -> void:
	_target = 1.0 if on else 0.0
	if on:
		visible = true
		if not placed:
			place_in_front()


func is_shown() -> bool:
	return _target > 0.0


func set_recording(on: bool) -> void:
	_mat.set_shader_parameter("recording", 1.0 if on else 0.0)


func set_waiting(on: bool) -> void:
	_mat.set_shader_parameter("waiting", 1.0 if on else 0.0)


func set_looked_at(on: bool) -> void:
	_mat.set_shader_parameter("looked_at", 1.0 if on else 0.0)


## A ray from in front of the pane meets it, or passes within margin_deg of its edge as seen from the ray's origin.
func looked_at(origin: Vector3, dir: Vector3, margin_deg: float) -> bool:
	var to_pane := global_transform.affine_inverse()
	var o := to_pane * origin
	var d := to_pane.basis * dir
	if o.z <= 0.0 or d.z >= 0.0:
		return false
	var hit := o - d * (o.z / d.z)
	var margin := o.distance_to(hit) * tan(deg_to_rad(margin_deg))
	var half := (_mesh.mesh as QuadMesh).size * 0.5 * _mesh.scale.x
	return absf(hit.x) <= half.x + margin and absf(hit.y - _mesh.position.y) <= half.y + margin


## Where a ray (a laser) meets the window: {distance} along the ray, or {} when it misses or comes from behind.
func hit(origin: Vector3, dir: Vector3) -> Dictionary:
	if not visible or _target <= 0.0 or not looked_at(origin, dir, 0.0):
		return {}
	var n := global_basis.z.normalized()
	var denom := n.dot(dir)
	if absf(denom) < 1e-5:
		return {}
	var t := n.dot(global_position - origin) / denom
	return {"distance": t} if t > 0.0 else {}


func _apply_fade() -> void:
	var eased := smoothstep(0.0, 1.0, _amount)
	var size := lerpf(FADE_SCALE, 1.0, eased)
	_mat.set_shader_parameter("opacity", eased)
	_mesh.scale = Vector3(size, size, 1.0)
	# The bottom edge stays where it is.
	_mesh.position.y = -0.5 * (1.0 - size) * _height


## In front of the head (level, whatever the head's tilt), a little below the eyes, facing it.
func place_in_front() -> void:
	if app == null or app.camera == null:
		return
	var cam: Node3D = app.camera
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	global_position = cam.global_position + fwd * DISTANCE_M + Vector3.DOWN * DROP_M
	face(cam.global_position)
	placed = true


## Turns the picture's front (+Z) toward the head, level (no tilt, no roll).
func face(head_pos: Vector3) -> void:
	var to := head_pos - global_position
	to.y = 0.0
	if to.length() < 0.01:
		return
	global_basis = Basis.looking_at(-to.normalized(), Vector3.UP)


## Turns the picture's front (+Z) to `front`, kept level (no roll); a front almost straight up or down is left alone.
func face_along(front: Vector3) -> void:
	if front.length() < 0.01 or absf(front.normalized().y) > 0.97:
		return
	global_basis = Basis.looking_at(-front.normalized(), Vector3.UP)


func _process(delta: float) -> void:
	if not visible:
		return
	if _amount != _target:
		_amount = move_toward(_amount, _target, delta / FADE_SECONDS)
		_apply_fade()
		if _amount <= 0.0:
			visible = false
			faded.emit()
