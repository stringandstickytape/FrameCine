extends "res://environments/vr_environment.gd"

## Passthrough (ideas #71; docs/research-cameras-and-splats.md): the real room around the screen. The headset's
## cameras show behind everything the app draws, through the OpenXR ALPHA_BLEND environment blend mode: the app clears
## to transparent and the runtime puts its camera view behind. The built-in cameras give a monochrome view; with the
## colour camera add-on plugged in, the same view is in colour, with no change here.
##
## The room light dims the camera view: a black shell around the viewer whose opacity is 1 - light, so lights-down
## during playback (#20) and the sleep timer dim the real room as they dim the other rooms. At light 1 or more, the
## room shows as the cameras see it.
##
## Leaving this room puts everything back (blend mode, the viewport's transparency, the background). Without XR, or
## when the runtime offers no ALPHA_BLEND, it is a black room and says so once in the log.

const SHELL_RADIUS := 60.0

var active := false
var _xr: XRInterface
var _shell_mat: StandardMaterial3D
var _saved_bg := -1
var _saved_transparent := false
var _saved_clear := Color.BLACK
var _world_env: Environment


## Spatial audio: the real room is unknown, so the standard layout 2 m round the seat (ITU angles, the screen pair on
## the screen) in an ordinary living room's acoustics: a box about 5 x 2.6 x 5.5 m, a short reverb.
func get_sound_room() -> Dictionary:
	return {"box": AABB(Vector3(-2.5, 0, -3.2), Vector3(5.0, 2.6, 5.5)), "ring": true, "distance": 2.0, "reflect": 0.45,
			"rt60": 0.4, "wet": 0.45}


func _ready() -> void:
	_build_shell()
	_xr = XRServer.find_interface("OpenXR")
	if _xr == null or not _xr.is_initialized():
		print("Passthrough room: no XR session; a black room on a desktop")
		return
	if not XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND in _xr.get_supported_environment_blend_modes():
		print("Passthrough room: the runtime offers no ALPHA_BLEND blend mode; a black room")
		return
	var vp := get_viewport()
	_saved_transparent = vp.transparent_bg
	_saved_clear = RenderingServer.get_default_clear_color()
	_world_env = _find_world_environment()
	if _world_env != null:
		_saved_bg = _world_env.background_mode
		_world_env.background_mode = Environment.BG_CLEAR_COLOR
	RenderingServer.set_default_clear_color(Color(0, 0, 0, 0))
	vp.transparent_bg = true
	_xr.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
	active = true
	print("Passthrough room: ALPHA_BLEND on; the cameras show behind the screen")


func _exit_tree() -> void:
	if not active:
		return
	active = false
	if _xr != null and _xr.is_initialized():
		_xr.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_OPAQUE
	var vp := get_viewport()
	if vp != null:
		vp.transparent_bg = _saved_transparent
	RenderingServer.set_default_clear_color(_saved_clear)
	if _world_env != null and _saved_bg >= 0:
		_world_env.background_mode = _saved_bg as Environment.BGMode
	print("Passthrough room: off, opaque again")


## The room light dims the camera view (see the top). A shell, not the clear colour's alpha: the shell's alpha reaches
## the swapchain the same way in every renderer.
func apply_light(user_scale: float) -> void:
	super.apply_light(user_scale)
	if _shell_mat != null:
		_shell_mat.albedo_color = Color(0, 0, 0, clampf(1.0 - user_scale, 0.0, 1.0))


func _build_shell() -> void:
	_shell_mat = StandardMaterial3D.new()
	_shell_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shell_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shell_mat.cull_mode = BaseMaterial3D.CULL_FRONT
	_shell_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_shell_mat.render_priority = BaseMaterial3D.RENDER_PRIORITY_MIN
	_shell_mat.albedo_color = Color(0, 0, 0, 0)
	var sphere := SphereMesh.new()
	sphere.radius = SHELL_RADIUS
	sphere.height = SHELL_RADIUS * 2.0
	sphere.radial_segments = 24
	sphere.rings = 12
	var shell := MeshInstance3D.new()
	shell.name = "DimShell"
	shell.mesh = sphere
	shell.material_override = _shell_mat
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shell.position = Vector3(0, NOMINAL_EYE_HEIGHT, 0)
	add_child(shell)


func _find_world_environment() -> Environment:
	var root := get_tree().current_scene if get_tree() != null else null
	if root == null:
		return null
	for we: Node in root.find_children("*", "WorldEnvironment", true, false):
		var env := (we as WorldEnvironment).environment
		if env != null:
			return env
	return null
