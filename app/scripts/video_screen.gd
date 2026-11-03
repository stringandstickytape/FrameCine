extends Node3D

## The video surface. Flat: a quad at this node's transform (centre of the screen, facing +Z towards the viewer),
## `width` metres wide, height from the eye's aspect. 180 / 360 / fisheye / dual fisheye 360: a sphere / cap of
## SPHERE_RADIUS centred on the head every frame (translation only, so the picture stays at infinity), turned by
## sphere_yaw.
## One ShaderMaterial (video.gdshader) for every mode; the plane textures never change for a source, only uniforms.

const VideoMode := preload("res://scripts/video_mode.gd")
const ProjectionMeshes := preload("res://scripts/projection_meshes.gd")
const VIDEO_SHADER := preload("res://shaders/video.gdshader")
const CurvedScreen := preload("res://scripts/play/curved_screen.gd")
const FisheyeLens := preload("res://scripts/play/fisheye_lens.gd")
const DualFisheye := preload("res://scripts/play/dual_fisheye.gd")
## Far enough that eye separation gives no visible disparity, near enough for depth precision.
const SPHERE_RADIUS := 20.0

var mode: VideoMode = VideoMode.new()
## Visible size of the decoded frame, pixels.
var frame_size := Vector2(1920, 1080)
## Flat screen width, metres.
var width := 3.0
## Turns spherical content around the vertical axis (radians).
var sphere_yaw := 0.0
## Horizon correction for spherical content (ideas #77, scripts/play/horizon.gd): x = pitch, y = roll, radians,
## applied in the picture's own frame before the yaw.
var sphere_tilt := Vector2.ZERO
## Spherical meshes follow this node's position (the XR or flat camera).
var head: Node3D
## Flat projections on a cylinder section of this radius (metres) instead of the quad; 0 = flat (ideas #31,
## scripts/play/curved_screen.gd).
var curve_radius := 0.0
## Fisheye lens profile {id, k} (ideas #73, scripts/play/fisheye_lens.gd); {} = equidistant. rebuild() after a change.
var lens_profile := {}
## Dual fisheye 360 lens values (scripts/play/dual_fisheye.gd, values()); {} = the generic profile. rebuild() after a
## change.
var dual_lens := {}
## The flat screen's size times this (the auto crop's growth, scripts/play/auto_crop.gd, ideas #42); 1 = as set.
var size_scale := 1.0
var material: ShaderMaterial

## The render layer of what never leaves the headset: the snapshot cameras leave it out.
const PRIVATE_LAYER := 20

var _flat: MeshInstance3D
var _sphere: MeshInstance3D
var _sphere_key := ""
var _curve_key := ""
var _shown := false


func _ready() -> void:
	material = ShaderMaterial.new()
	material.shader = VIDEO_SHADER
	_flat = MeshInstance3D.new()
	_flat.name = "Flat"
	_flat.mesh = QuadMesh.new()
	_flat.material_override = material
	_flat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flat.visible = false
	add_child(_flat)
	_sphere = MeshInstance3D.new()
	_sphere.name = "Sphere"
	_sphere.top_level = true
	_sphere.material_override = material
	_sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sphere.visible = false
	add_child(_sphere)


## Picture that stays in the headset (a terminal): on a render layer the room snapshots for assistants don't see.
func set_private(on: bool) -> void:
	_flat.set_layer_mask_value(PRIVATE_LAYER, on)
	_flat.set_layer_mask_value(1, not on)


func set_textures(y_tex: Texture2D, uv_tex: Texture2D, p010 := false) -> void:
	material.set_shader_parameter("rgb_source", false)
	material.set_shader_parameter("rgb_tex", null)
	material.set_shader_parameter("y_tex", y_tex)
	material.set_shader_parameter("uv_tex", uv_tex)
	# 10-bit P010 planes read as .r / .rg with a scale; 8-bit NV12 as .r / .ra (shaders/video_common.gdshaderinc).
	material.set_shader_parameter("p010", p010)


## One sRGB-encoded RGB texture instead of the NV12 planes (a captured window).
func set_rgb_texture(tex: Texture2D) -> void:
	material.set_shader_parameter("y_tex", null)
	material.set_shader_parameter("uv_tex", null)
	material.set_shader_parameter("rgb_tex", tex)
	material.set_shader_parameter("rgb_source", true)


func set_visible_rect(r: Rect2) -> void:
	material.set_shader_parameter("visible_rect", Vector4(r.position.x, r.position.y, r.size.x, r.size.y))


func set_mode(m: VideoMode, p_frame_size: Vector2) -> void:
	mode = m.copy()
	if p_frame_size.x > 0.0 and p_frame_size.y > 0.0:
		frame_size = p_frame_size
	_apply()


func set_width(w: float) -> void:
	width = w
	_apply()


func set_shown(shown: bool) -> void:
	_shown = shown
	_apply()


func is_shown() -> bool:
	return _shown


## -1: per view (VIEW_INDEX); 0 / 1: force an eye (desktop screenshots).
func set_force_eye(eye: int) -> void:
	material.set_shader_parameter("force_eye", eye)


## Builds the meshes again from the current settings (a lens profile changed).
func rebuild() -> void:
	_apply()


func set_curve_radius(r: float) -> void:
	curve_radius = maxf(r, 0.0)
	_apply()


func get_flat_size() -> Vector2:
	return Vector2(width, width / mode.display_aspect(frame_size)) * size_scale


## The picture's top-right corner in world space (flat projections), on the curve when the screen is curved.
func top_right_corner() -> Vector3:
	var size := get_flat_size()
	var local := Vector3(size.x * 0.5, size.y * 0.5, 0.0)
	if curve_radius > 0.0:
		var phi := size.x * 0.5 / curve_radius
		local = Vector3(curve_radius * sin(phi), size.y * 0.5, curve_radius * (1.0 - cos(phi)))
	return _flat.global_transform * local


func _apply() -> void:
	if material == null:
		return
	var dual := mode.projection == VideoMode.Proj.DUAL_FISHEYE
	material.set_shader_parameter("stereo_layout", 0 if dual else int(mode.layout))
	material.set_shader_parameter("swap_eyes", mode.swap and not dual)
	material.set_shader_parameter("circle_mask", mode.projection == VideoMode.Proj.FISHEYE)
	material.set_shader_parameter("dual_fisheye", dual)
	material.set_shader_parameter("wrap_x", mode.projection == VideoMode.Proj.EQUIRECT_360)
	var flat := mode.projection == VideoMode.Proj.FLAT
	_flat.visible = _shown and flat
	_sphere.visible = _shown and not flat
	if flat:
		var size := get_flat_size()
		if curve_radius > 0.0:
			var key := "%.4f_%.4f_%.3f" % [size.x, size.y, curve_radius]
			if key != _curve_key:
				_curve_key = key
				_flat.mesh = CurvedScreen.build(size, curve_radius)
		else:
			_curve_key = ""
			if not _flat.mesh is QuadMesh:
				_flat.mesh = QuadMesh.new()
			(_flat.mesh as QuadMesh).size = size
		return
	var key := "%d_%d_%s" % [mode.projection, roundi(mode.fisheye_fov), str(lens_profile)]
	if dual:
		key = "%d_%s_%.4f" % [mode.projection, str(get_dual_lens()), frame_aspect()]
	if key != _sphere_key:
		_sphere_key = key
		match mode.projection:
			VideoMode.Proj.EQUIRECT_180:
				_sphere.mesh = ProjectionMeshes.equirect(180.0, SPHERE_RADIUS)
			VideoMode.Proj.EQUIRECT_360:
				_sphere.mesh = ProjectionMeshes.equirect(360.0, SPHERE_RADIUS)
			VideoMode.Proj.FISHEYE:
				var lens := Callable()
				if not lens_profile.is_empty():
					lens = FisheyeLens.mapping(str(lens_profile["id"]), mode.fisheye_fov, lens_profile.get("k", PackedFloat32Array()))
				_sphere.mesh = ProjectionMeshes.fisheye(mode.fisheye_fov, SPHERE_RADIUS, lens)
			VideoMode.Proj.DUAL_FISHEYE:
				_sphere.mesh = ProjectionMeshes.dual_fisheye(get_dual_lens(), SPHERE_RADIUS, frame_aspect(),
						func(model: String, fov: float) -> Callable: return FisheyeLens.mapping(model, fov))
	_follow_head()


## The dual fisheye 360 lens values in use.
func get_dual_lens() -> Dictionary:
	return dual_lens if not dual_lens.is_empty() else DualFisheye.defaults("generic")


## Width / height of the whole frame.
func frame_aspect() -> float:
	return frame_size.x / frame_size.y if frame_size.y > 0.0 else 2.0


func _process(_delta: float) -> void:
	if _sphere.visible:
		_follow_head()


func _follow_head() -> void:
	var centre := head.global_position if head != null else global_position
	var basis := Basis(Vector3.UP, sphere_yaw)
	if sphere_tilt != Vector2.ZERO:
		basis = basis * Basis(Vector3.RIGHT, sphere_tilt.x) * Basis(Vector3.FORWARD, sphere_tilt.y)
	_sphere.global_transform = Transform3D(basis, centre)
