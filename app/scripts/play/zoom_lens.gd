extends Node3D

## Zoom lens for 180 / 360 pictures (ideas #38): hold the grip and pull the trigger, and a round lens appears where
## the hand aims, showing that part of the picture magnified (default 3x). Let go of either to put it away. While it
## is up, the grip does not turn the sphere. Flat screens have the manual zoom (#35) instead.
##
## The lens is a disc LENS_DISTANCE in front of the eyes on the line along the aim, LENS_SIZE across, drawn on top of
## everything by shaders/magnifier.gdshader with the screen's uniforms: each fragment looks along its own direction
## from the eye, pulled towards the aim by the magnification, so the picture keeps its stereo depth.
##
##   enabled, set_enabled(on)          [zoom_lens] enabled (default on)
##   magnification, set_magnification(v)   [zoom_lens] magnification, 1.5..8 (default 3)
##   active, hand                      the lens is up, and the hand holding it
##   on_trigger(hand, pressed) -> bool main's trigger asks first; true when the lens took the press
##   begin(hand), end()                (also for the desktop and tests)
##   aim() -> Vector3                  the aim, a unit direction (world)
##   signal changed(active)

signal changed(active: bool)

const MAGNIFIER_SHADER := preload("res://shaders/magnifier.gdshader")
const VideoMode := preload("res://scripts/video_mode.gd")
const DualFisheye := preload("res://scripts/play/dual_fisheye.gd")
const LENS_DISTANCE := 0.8
const LENS_SIZE := 0.32
const RANGE := Vector2(1.5, 8.0)

var main: Node3D
var enabled := true
var magnification := 3.0
var active := false
var hand: XRController3D
var lens: MeshInstance3D
var _material: ShaderMaterial
var _names: Array[String] = []


func _ready() -> void:
	top_level = true
	enabled = bool(main.settings.get_value("zoom_lens", "enabled", true))
	magnification = clampf(float(main.settings.get_value("zoom_lens", "magnification", 3.0)), RANGE.x, RANGE.y)
	lens = MeshInstance3D.new()
	lens.name = "Lens"
	var quad := QuadMesh.new()
	quad.size = Vector2(LENS_SIZE, LENS_SIZE)
	lens.mesh = quad
	_material = ShaderMaterial.new()
	_material.shader = MAGNIFIER_SHADER
	_material.render_priority = 8
	lens.material_override = _material
	lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lens.visible = false
	add_child(lens)
	for u: Dictionary in MAGNIFIER_SHADER.get_shader_uniform_list():
		var n := str(u["name"])
		if not n in ["sphere_inverse", "projection", "fisheye_fov", "aim", "magnification", "lens_opacity"] \
				and not n.begins_with("dfe_"):
			_names.append(n)


func set_enabled(on: bool) -> void:
	enabled = on
	main.settings.set_value("zoom_lens", "enabled", null if on else false)
	if not on:
		end()


func set_magnification(v: float) -> void:
	magnification = clampf(v, RANGE.x, RANGE.y)
	main.settings.set_value("zoom_lens", "magnification", null if is_equal_approx(magnification, 3.0)
			else magnification)


func applies() -> bool:
	return enabled and main.player.has_source() and main.mode.is_spherical()


## Main's trigger handler asks first: with the grip held on that hand in 180 / 360, the trigger brings the lens.
func on_trigger(p_hand: XRController3D, pressed: bool) -> bool:
	if pressed and applies() and bool(p_hand.get("grip_down")):
		begin(p_hand)
		return true
	if not pressed and active and p_hand == hand:
		end()
		return true
	return false


func begin(p_hand: XRController3D) -> void:
	hand = p_hand
	active = true
	# The grip's sphere turn stops while the lens is up.
	if main.get("_grab") is Dictionary and (main._grab as Dictionary).get("hand") == p_hand:
		main._grab = {}
	lens.visible = true
	_update()
	changed.emit(true)


func end() -> void:
	if not active:
		return
	active = false
	hand = null
	lens.visible = false
	changed.emit(false)


func aim() -> Vector3:
	if hand != null and hand.has_method("get_ray_direction"):
		return (hand.call("get_ray_direction") as Vector3).normalized()
	var cam: Camera3D = main.camera
	return -cam.global_transform.basis.z if cam != null else Vector3.FORWARD


func _process(_delta: float) -> void:
	if not active:
		return
	# A tracked hand that let go of the grip puts it away (a hand-less begin(), on a desktop, stays until end()).
	var let_go := hand != null and hand.get_is_active() and not bool(hand.get("grip_down"))
	if not applies() or let_go:
		end()
		return
	_update()


func _update() -> void:
	var cam: Node3D = main.camera
	var eye: Vector3 = cam.global_position if cam != null else Vector3(0, main.eye_height, 0)
	var a := aim()
	var centre := eye + a * LENS_DISTANCE
	var up := Vector3.UP if absf(a.dot(Vector3.UP)) < 0.95 else Vector3.BACK
	# The quad's face (+Z) towards the eye.
	lens.global_transform = Transform3D(Basis.looking_at(a, up), centre)
	var src: ShaderMaterial = main.screen.material
	for n in _names:
		_material.set_shader_parameter(n, src.get_shader_parameter(n))
	var sphere: Node3D = main.screen.get("_sphere")
	var b: Basis = sphere.global_transform.basis.orthonormalized() if sphere != null else Basis.IDENTITY
	_material.set_shader_parameter("sphere_inverse", b.inverse())
	var proj: int = main.mode.projection
	_material.set_shader_parameter("projection", 0 if proj == VideoMode.Proj.EQUIRECT_180
			else (2 if proj == VideoMode.Proj.FISHEYE else (3 if proj == VideoMode.Proj.DUAL_FISHEYE else 1)))
	if proj == VideoMode.Proj.DUAL_FISHEYE:
		var u: Dictionary = DualFisheye.uniforms(main.screen.get_dual_lens(), main.screen.frame_aspect())
		for k: String in u:
			_material.set_shader_parameter(k, u[k])
	_material.set_shader_parameter("fisheye_fov", float(main.mode.fisheye_fov))
	_material.set_shader_parameter("aim", a)
	_material.set_shader_parameter("magnification", magnification)
