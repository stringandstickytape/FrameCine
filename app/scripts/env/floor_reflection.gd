extends Node3D

## The screen's reflection on the floor (ideas #62): one quad lying on the floor between you and the screen, drawn
## with video_reflection.gdshader, which shows on each floor point the part of the picture a mirror there would show,
## fading out with the distance from the screen's bottom edge. The quad is depth-tested, so seats and furniture in
## front hide it; it is blended over the floor. Flat screens only (not 180 / 360), and only in rooms with a floor for
## it: an environment's reflection_floor_y (scripts/env/primitive_room.gd, glTF rooms' JSON), and the void (y = 0).
## The screen's material uniforms are copied to the reflection's each frame while it shows.
##
##   enabled                on for this environment ([env_<id>] reflection; default on where the room has a floor
##                          for it; a room built from a document says, its reflection_default: on in the Void)
##   available() -> bool    this room has a floor for it
##   strength               [reflection] strength, 0..0.6 (default 0.25)
##   set_enabled(on), set_strength(v), is_showing()
##   signal changed

signal changed

const REFLECTION_SHADER := preload("res://shaders/video_reflection.gdshader")
const DEFAULT_FLOORS := {"void": 0.0}

var main: Node3D
var enabled := false
var strength := 0.25
var floor_y := NAN
var _quad: MeshInstance3D
var _material: ShaderMaterial
var _names: Array[String] = []
var _wanted := false
var _placed_for := Transform3D()


func _ready() -> void:
	strength = clampf(float(main.settings.get_value("reflection", "strength", 0.25)), 0.0, 0.6)
	_material = ShaderMaterial.new()
	_material.shader = REFLECTION_SHADER
	_material.render_priority = 1
	_quad = MeshInstance3D.new()
	_quad.name = "ReflectionQuad"
	_quad.mesh = PlaneMesh.new()
	_quad.material_override = _material
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_quad.visible = false
	add_child(_quad)
	for u: Dictionary in REFLECTION_SHADER.get_shader_uniform_list():
		var n := str(u["name"])
		# The deband stays off: the reflection is blurred, and four more samples a pixel there buy nothing.
		if not n in ["screen_inverse", "screen_size", "floor_y", "strength", "fade", "pc_deband"]:
			_names.append(n)
	_material.set_shader_parameter("pc_deband", 0.0)
	main.environment_changed.connect(func(_id: String, _l: float) -> void: _on_environment())
	main.screen_changed.connect(func(_w: float, _d: float, _h: float) -> void: _place())
	main.mode_changed.connect(func(_m: Variant, _a: String) -> void: _place())
	_on_environment()


func available() -> bool:
	return not is_nan(floor_y)


func is_showing() -> bool:
	return _quad.visible


func set_enabled(on: bool) -> void:
	enabled = on
	main.settings.set_value("env_" + main.env_id, "reflection", on)
	_place()
	changed.emit()


func set_strength(v: float) -> void:
	strength = clampf(v, 0.0, 0.6)
	main.settings.set_value("reflection", "strength", strength)
	_material.set_shader_parameter("strength", strength)
	changed.emit()


func _on_environment() -> void:
	floor_y = NAN
	var env: Node = main.env
	if env != null and "reflection_floor_y" in env and not is_nan(float(env.get("reflection_floor_y"))):
		floor_y = float(env.get("reflection_floor_y"))
	elif DEFAULT_FLOORS.has(main.env_id):
		floor_y = DEFAULT_FLOORS[main.env_id]
	var default_on := available() and not DEFAULT_FLOORS.has(main.env_id)
	# A room built from a document says (scripts/env/env_room.gd: its room section's reflection; the Void's mirror
	# floor is made for it).
	if env != null and env.get("reflection_default") != null and available():
		default_on = bool(env.get("reflection_default"))
	enabled = bool(main.settings.get_value("env_" + main.env_id, "reflection", default_on))
	_place()
	changed.emit()


## The quad spans the floor from the screen's foot to just behind the viewer, a little wider than the screen.
func _place() -> void:
	# Not while the screen is tipped up (lying down): there is no sensible floor image of a ceiling screen.
	var upright: bool = absf(main.screen.global_transform.basis.z.normalized().y) < 0.1
	_wanted = enabled and available() and not main.mode.is_spherical() and upright
	_quad.visible = _wanted and main.screen.is_shown()
	if not _wanted:
		return
	var screen: Node3D = main.screen
	var size: Vector2 = screen.get_flat_size()
	var t: Transform3D = screen.global_transform
	_placed_for = t
	# The room may be moved (seat choice, #19): its floor moves with it.
	var y: float = floor_y + (main.env.position.y if main.env != null else 0.0) + 0.002
	var foot := Vector3(t.origin.x, y, t.origin.z)
	var viewer := Vector3(0.0, y, 0.0)
	var length := foot.distance_to(viewer) + 0.5
	var plane := _quad.mesh as PlaneMesh
	plane.size = Vector2(size.x * 1.4, length)
	var forward := (viewer - foot).normalized()
	var basis := Basis(forward.cross(Vector3.UP).normalized() * -1.0, Vector3.UP, forward)
	_quad.global_transform = Transform3D(basis, foot + forward * length * 0.5)
	_material.set_shader_parameter("screen_inverse", Projection(t.affine_inverse()))
	_material.set_shader_parameter("screen_size", size)
	_material.set_shader_parameter("floor_y", y - 0.002)
	_material.set_shader_parameter("strength", strength)


func _process(_delta: float) -> void:
	if main.screen.global_transform != _placed_for:
		_place()
	_quad.visible = _wanted and main.screen.is_shown()
	if not _quad.visible:
		return
	var src: ShaderMaterial = main.screen.material
	for n in _names:
		_material.set_shader_parameter(n, src.get_shader_parameter(n))
