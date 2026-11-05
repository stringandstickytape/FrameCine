extends Node3D

## The terminal of an agent on the headset (scripts/agents/local_agents.gd), held on the pointer controller where the
## card sits (watch_card.hand_transform): in the plane of the X, Y and B buttons, its sides parallel to the laser, its
## bottom edge just past the controller's front. It shows the window's picture as it is: sRGB values in a UNORM texture,
## decoded here. Its size is its window's shape at PANE_WIDTH_M; on a render layer the snapshots for assistants don't
## see (VideoScreen.PRIVATE_LAYER), so its contents stay in the headset.
##
## Three small signs in the shader: a red dot in the corner while recording, an amber edge while the agent waits on a
## prompt, a blue edge while the viewer's look gives the hand to it (the stick and the trigger go to it either way). With
## both, the blue runs inside the amber.
##
## It comes and goes with an ease of its opacity and a small growth out of its bottom edge, the controller's end. One
## amount runs both ways, so a press in the middle turns it back from where it is.
##
##   app, set_texture(tex, size), set_shown(on), set_recording(on), set_waiting(on), set_looked_at(on), is_shown()
##   looked_at(origin, dir, margin_deg) -> bool; faded: gone from sight
## Without XR (a desktop, a picture) it floats in front of the camera.

signal faded

const WatchCard := preload("res://ui/watch_card.gd")
const VideoScreen := preload("res://scripts/video_screen.gd")

## The pane's width, metres: at arm's length (about 45 cm) 66 columns are about the card's text size, and the 940 px
## window a little over the display's own pixel density, so nothing is lost to the texture
## (docs/shots/assistant/agent-pane-headset-density.png).
const PANE_WIDTH_M := 0.26
const FADE_SECONDS := 0.2
## Its size at the far end of the fade.
const FADE_SCALE := 0.92
## Where it floats without XR: this far ahead and this far down.
const DESK_DISTANCE := 0.55
const DESK_DROP := 0.04
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
var _height := PANE_WIDTH_M


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
		_height = PANE_WIDTH_M * float(size.y) / size.x
		(_mesh.mesh as QuadMesh).size = Vector2(PANE_WIDTH_M, _height)
		_apply_fade()


func set_shown(on: bool) -> void:
	_target = 1.0 if on else 0.0
	if on:
		visible = true
		place()


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


func _apply_fade() -> void:
	var eased := smoothstep(0.0, 1.0, _amount)
	var size := lerpf(FADE_SCALE, 1.0, eased)
	_mat.set_shader_parameter("opacity", eased)
	_mesh.scale = Vector3(size, size, 1.0)
	# The bottom edge stays where it is.
	_mesh.position.y = -0.5 * (1.0 - size) * _height


func place() -> void:
	if app == null:
		return
	if app.use_xr and app.ui != null and app.ui.pointer_hand != null:
		global_transform = WatchCard.hand_transform(app.ui.pointer_hand, _height)
		return
	var cam: Node3D = app.camera
	var at: Vector3 = cam.global_position - cam.global_basis.z * DESK_DISTANCE - cam.global_basis.y * DESK_DROP
	global_transform = Transform3D(cam.global_basis, at)


func _process(delta: float) -> void:
	if not visible:
		return
	place()
	if _amount != _target:
		_amount = move_toward(_amount, _target, delta / FADE_SECONDS)
		_apply_fade()
		if _amount <= 0.0:
			visible = false
			faded.emit()
