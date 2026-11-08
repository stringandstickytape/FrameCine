extends Node3D

## A true plane mirror (docs/environments.md, "mirror_lid"): "the mirrored tv - can't we do that *properly*?" (the
## user, 2026-11-08). The mirror-lid set's picture was a fake: an upright picture standing over the hinge, dark panels
## behind it, all of it plain to see from above or the side. Now the mirror reflects:
##   - each eye's reflection is rendered every frame by a camera at the eye's mirror image (the eye reflected in the
##     mirror's plane), looking through the mirror: its near plane is the mirror's plane and its frustum the mirror's
##     rectangle (an off-axis frustum), so it sees exactly what the eye would see in the mirror, and nothing behind the
##     mirror (the lid, the wall). Two small SubViewports in the room's world, one an eye; env_mirror.gdshader shows
##     each eye its own.
##   - the film lies on the tube's face (TubePicture): the screen's flat mesh with the screen's own material (the
##     presentation's, so the tube's shape, the scan lines, switching on and off and Wrong way round all carry over)
##     at the screen's mirror image. The room's screen stands where the reflection of the tube's face is, so the
##     reflection of TubePicture is the screen's own place: what the viewer sees in the mirror is the picture where
##     the room put it, and looking down into the cabinet, the picture on the tube.
##   - the upright screen is hidden from every camera while the mirror shows (its render layers 0, given back on
##     exit), so it shows only as the reflection.
## The cost: two more renders of the room a frame (Mobile, no shadows, no MSAA), PIXELS_WIDE across each: the knob.
## They stop while the mirror is out of view or seen from behind, and while it is hidden (a 180 / 360 film: the room
## hides).

## The mirror's own render layer: its cameras leave it out (a mirror does not see itself).
const LAYER := 19
## What never leaves the headset (VideoScreen.PRIVATE_LAYER): the mirror leaves it out too, so a snapshot of the room
## (scripts/assistant/room_snapshot.gd, which leaves out only that layer) never sees it in the mirror.
const PRIVATE_LAYER := 20
## The cost knob: each eye's reflection is this many pixels across (its height from the mirror's shape). 720 is
## about the headset's own pixels over a 0.8 m mirror at 1.5 m; fewer blur the reflection, more cost fill rate.
const PIXELS_WIDE := 720
## Past this angle from the head's forward (to the mirror's nearest edge) the mirror is out of view: no render.
const OUT_OF_VIEW := deg_to_rad(80.0)
const FAR := 60.0
const SHADER := preload("res://shaders/env_mirror.gdshader")
## The screen's render layers while it is hidden (on the screen's flat mesh, so a rebuilt room's mirror finds them).
const META := "mirror_view_layers"
## The sight-line check looks through these (screen_frame.gd SEE_THROUGH).
const SEE_THROUGH := "env_see_through"

## The mirror in this node's space (the room's): its centre, half its width to the viewer's right, half its height
## up. The reflecting face is the side half_right x half_up points to.
var centre := Vector3.ZERO
var half_right := Vector3(0.5, 0.0, 0.0)
var half_up := Vector3(0.0, 0.5, 0.0)
## The silvering's reflectance, linear (env_mirror.gdshader tint): old silver, a little dim and warm.
var tint := Color(0.82, 0.78, 0.68)
## Returns the screen's flat mesh (main.screen's Flat), or null; or set `flat` (tests, a room on its own).
var find_flat: Callable
var flat: MeshInstance3D

var _views: Array[SubViewport] = []
var _cameras: Array[Camera3D] = []
var _glass: MeshInstance3D
var _tube: MeshInstance3D
## The flat mesh hidden now (null: none).
var _hidden: MeshInstance3D


func _ready() -> void:
	# After the screen's placing and the head's tracking.
	process_priority = 1000
	var aspect := half_right.length() / maxf(half_up.length(), 0.001)
	var px := Vector2i(PIXELS_WIDE, maxi(roundi(PIXELS_WIDE / aspect), 16))
	for side: String in ["Left", "Right"]:
		var vp := SubViewport.new()
		vp.name = side
		vp.size = px
		vp.msaa_3d = Viewport.MSAA_DISABLED
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		vp.positional_shadow_atlas_size = 0
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(vp)
		var cam := Camera3D.new()
		cam.name = "Camera"
		cam.projection = Camera3D.PROJECTION_FRUSTUM
		cam.keep_aspect = Camera3D.KEEP_HEIGHT
		cam.set_cull_mask_value(LAYER, false)
		cam.set_cull_mask_value(PRIVATE_LAYER, false)
		vp.add_child(cam)
		cam.current = true
		_views.append(vp)
		_cameras.append(cam)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("left_view", _views[0].get_texture())
	mat.set_shader_parameter("right_view", _views[1].get_texture())
	mat.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	mat.set_shader_parameter("half_size", Vector2(half_right.length(), half_up.length()))
	_glass = MeshInstance3D.new()
	_glass.name = "Glass"
	_glass.mesh = _quad_mesh()
	_glass.material_override = mat
	_glass.layers = 0
	_glass.set_layer_mask_value(LAYER, true)
	_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glass.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_glass.add_to_group(SEE_THROUGH)
	add_child(_glass)
	_tube = MeshInstance3D.new()
	_tube.name = "TubePicture"
	_tube.top_level = true
	_tube.visible = false
	_tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tube.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_tube.add_to_group(SEE_THROUGH)
	add_child(_tube)


## The mirror's quad: UV (0, 0) at the viewer's top left.
func _quad_mesh() -> ArrayMesh:
	var n := half_right.cross(half_up).normalized()
	var v := PackedVector3Array([centre - half_right + half_up, centre + half_right + half_up,
			centre + half_right - half_up, centre - half_right - half_up])
	var uv := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var normals := PackedVector3Array([n, n, n, n])
	# Clockwise seen from the front (Godot's front faces).
	var idx := PackedInt32Array([0, 1, 2, 0, 2, 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## The mirror in world space: [centre, half right, half up, normal (towards the viewer)].
func world_rect() -> Array:
	var g := global_transform
	var r := g.basis * half_right
	var u := g.basis * half_up
	return [g * centre, r, u, r.cross(u).normalized()]


## The reflection across the mirror's plane, in world space (its basis's determinant is -1).
func reflection() -> Transform3D:
	var w := world_rect()
	var c: Vector3 = w[0]
	var n: Vector3 = w[3]
	var b := Basis(Vector3.RIGHT - 2.0 * n.x * n, Vector3.UP - 2.0 * n.y * n, Vector3.BACK - 2.0 * n.z * n)
	return Transform3D(b, 2.0 * c.dot(n) * n)


func cameras() -> Array[Camera3D]:
	return _cameras


func views() -> Array[SubViewport]:
	return _views


func tube_picture() -> MeshInstance3D:
	return _tube


func glass() -> MeshInstance3D:
	return _glass


func _process(_delta: float) -> void:
	var f := _find()
	if not is_visible_in_tree():
		f = null
		for vp in _views:
			vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if f != _hidden:
		_show_flat()
	if f == null:
		_tube.visible = false
	else:
		_hide_flat(f)
		_follow(f)
	if is_visible_in_tree():
		_aim()


func _find() -> MeshInstance3D:
	if flat != null and is_instance_valid(flat):
		return flat
	if find_flat.is_valid():
		var f: Variant = find_flat.call()
		if f is MeshInstance3D and is_instance_valid(f):
			return f
	return null


## The screen's flat mesh off every camera: its layers kept on it (META), 0 while the mirror shows. Something that
## sets its layers meanwhile (VideoScreen.set_private) is taken as the new layers.
func _hide_flat(f: MeshInstance3D) -> void:
	if f.layers != 0 or not f.has_meta(META):
		f.set_meta(META, f.layers)
	f.layers = 0
	_hidden = f


func _show_flat() -> void:
	if _hidden != null and is_instance_valid(_hidden) and _hidden.has_meta(META):
		_hidden.layers = int(_hidden.get_meta(META))
		_hidden.remove_meta(META)
	_hidden = null


## The film on the tube's face: the screen's mesh and material at the screen's mirror image.
func _follow(f: MeshInstance3D) -> void:
	_tube.visible = f.is_visible_in_tree()
	if not _tube.visible:
		return
	if _tube.mesh != f.mesh:
		_tube.mesh = f.mesh
	if _tube.material_override != f.material_override:
		_tube.material_override = f.material_override
	_tube.extra_cull_margin = f.extra_cull_margin
	_tube.layers = int(f.get_meta(META, f.layers))
	_tube.global_transform = reflection() * f.global_transform


## Each eye's reflected camera, or no render where the eye cannot see the mirror.
func _aim() -> void:
	var eyes := _eyes()
	var w := world_rect()
	var c: Vector3 = w[0]
	var r: Vector3 = w[1]
	var u: Vector3 = w[2]
	var n: Vector3 = w[3]
	var seen := not eyes.is_empty() and _in_view(eyes[0], c, (r + u).length())
	for i in _views.size():
		var vp := _views[i]
		if not seen or i >= (eyes[1] as Array).size():
			vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
			continue
		var p: Vector3 = eyes[1][i]
		var d := (p - c).dot(n)
		if d < 0.02:
			# Behind the mirror, or in its plane: it shows the viewer nothing.
			vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
			continue
		var pr := p - 2.0 * d * n
		var y := u.normalized()
		var z := -n
		var x := y.cross(z)
		var cam := _cameras[i]
		cam.global_transform = Transform3D(Basis(x, y, z), pr)
		cam.set_frustum(2.0 * u.length(), Vector2((c - pr).dot(x), (c - pr).dot(y)), d, d + FAR)
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS


## [the head's transform, the eyes' positions]: in the headset each eye, from the head's pose this frame (XRCamera3D,
## tracked for the frame about to be shown) and the eyes' spacing (the views' own poses lag a frame: the engine
## locates them just before rendering); on a desktop (and in tests) the one camera. [] without a camera.
func _eyes() -> Array:
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp != null else null
	if cam == null:
		return []
	var head := cam.global_transform
	var xr := XRServer.primary_interface
	if cam is XRCamera3D and vp.use_xr and xr != null and xr.is_initialized() and xr.get_view_count() == 2 \
			and cam.get_parent() is Node3D:
		var origin := (cam.get_parent() as Node3D).global_transform
		var half := xr.get_transform_for_view(0, origin).origin.distance_to(
				xr.get_transform_for_view(1, origin).origin) * 0.5
		var side := head.basis.x.normalized() * half
		return [head, [head.origin - side, head.origin + side]]
	return [head, [head.origin]]


## Whether any of the mirror (a sphere of `radius` round `c`) is within OUT_OF_VIEW of the head's forward.
static func _in_view(head: Transform3D, c: Vector3, radius: float) -> bool:
	var to := c - head.origin
	var dist := to.length()
	if dist <= radius:
		return true
	var angle := (-head.basis.z).angle_to(to)
	return angle - asin(radius / dist) < OUT_OF_VIEW


func _exit_tree() -> void:
	_show_flat()
