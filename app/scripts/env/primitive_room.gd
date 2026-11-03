extends "res://environments/vr_environment.gd"

## Base for environments built from primitives in code (ideas #52), like the cinema: unlit surfaces
## (env_unlit.gdshader: the room's ambient level plus the screen's spill), boxes, spheres and cylinders, MultiMesh for
## repeats, no lights. A subclass builds itself in _build(); the scene (.tscn) only holds the script, the exported
## light levels and the ScreenAnchor marker (vr_environment.gd's convention: the viewer at the origin facing -Z, the
## floor at y = 0, the anchor at the screen's centre facing +Z).
##
##   reflection_floor_y   the floor height where a screen reflection may show (scripts/env/floor_reflection.gd, #62);
##                        NAN: this room has no floor for it
##   get_seats()          where a viewer can sit (seat choice, scripts/comfort/seat_choice.gd, #19): the floor point
##                        under the seated eyes, room coordinates; a subclass fills `seats` in _build()

const ENV_SHADER := preload("res://shaders/env_unlit.gdshader")
const MaterialLibrary := preload("res://scripts/env/material_library.gd")

var reflection_floor_y := NAN
var seats: Array[Vector3] = []


func _ready() -> void:
	_build()


func get_seats() -> Array[Vector3]:
	return seats


## Subclasses add their geometry here.
func _build() -> void:
	pass


func material(albedo: Color, spill := 1.0, floor_darkening := 0.2) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ENV_SHADER
	m.set_shader_parameter("albedo", albedo)
	m.set_shader_parameter("spill", spill)
	m.set_shader_parameter("floor_darkening", floor_darkening)
	return m


## A library material (scripts/env/material_library.gd, docs/materials.md) in this room's light: its pattern at
## `colour` on average, spill and floor_darkening as material(); material(colour, ...) if the library lacks it. In an
## assistant's lit room the room relights it (MaterialLibrary.lit_variant()).
func textured(id: String, colour: Color, spill := 1.0, floor_darkening := 0.2, options := {}) -> Material:
	var o := options.duplicate()
	o.merge({"colour": colour, "spill": spill, "floor_darkening": floor_darkening})
	var m := MaterialLibrary.get_material(id, o)
	return m if m != null else material(colour, spill, floor_darkening)


## A light that doesn't follow the room's level: lamps, stars, signs (unshaded colour).
func glow(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = colour
	m.disable_receive_shadows = true
	return m


func add_mesh(node_name: String, mesh: Mesh, xform: Transform3D, mat: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.transform = xform
	if mat != null:
		mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func add_box(node_name: String, size: Vector3, centre: Vector3, mat: Material, basis := Basis()) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return add_mesh(node_name, b, Transform3D(basis, centre), mat)


## An inside-out box: walls, floor and ceiling of a room seen from within.
func add_shell(node_name: String, min_corner: Vector3, max_corner: Vector3, mat: Material) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = max_corner - min_corner
	b.flip_faces = true
	return add_mesh(node_name, b, Transform3D(Basis(), (min_corner + max_corner) * 0.5), mat)


func add_multimesh(node_name: String, mesh: Mesh, xforms: Array[Transform3D], mat: Material = null) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	if mat != null:
		mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi


## Points spread evenly over a sphere's upper part (golden-angle spiral), for stars: `count` unit directions with
## y >= min_y, in a fixed order (no randomness: the same sky every time).
static func sky_points(count: int, min_y := 0.05) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var golden := PI * (3.0 - sqrt(5.0))
	var total := int(count / maxf(0.5 * (1.0 - min_y), 0.01))
	for i in total:
		var y := 1.0 - (float(i) + 0.5) / total * 2.0
		if y < min_y:
			break
		var r := sqrt(1.0 - y * y)
		var a := golden * i
		out.append(Vector3(cos(a) * r, y, sin(a) * r))
	return out
