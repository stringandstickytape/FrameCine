extends "res://scripts/env/systems/env_system.gd"

## The common ground of the parametric builders (docs/environments.md, "The builders"): shopfront, nave, dome_hall,
## terrace, domestic and vehicle extend it. The conventions are auditorium.gd's:
##   - the viewer's own seat is at the origin facing -Z, the floor under it at y 0
##   - static parts are ArrayMeshes in room coordinates (scripts/env/room_mesh.gd) with their own UV2, gi_mode static,
##     one surface a material; library materials on the house shader come from the light system (from_param), so the
##     light's fill, the film's spill, the stand-in lamps and a run-time lightmap (the light's bake hooks) all apply
##   - a light source's glow is the light system's lamp material, by group (house, steps, stage, signs, booth,
##     accent); its real light for a bake goes to the light system's hidden bake lights
##   - seats are slots (seat_slots(), build_util.gd): the builder draws its plain default seat in them unless the
##     room has a seats system, which then draws them; single seats are one MultiMesh named Seats (one instance a
##     slot, the viewer's own folded away), pews, benches and cushions are static meshes
##   - collision_shapes(): cheap boxes for object physics; the seats' boxes only when the builder draws the seats
##   - slots(): named places for the kit ({name: [{transform, size}]}: the piece's front faces its local +Z)
##   - glass and other see-through parts are in the group env_see_through (the sight-line check looks through them)
## Each builder declares static layout(p), seat_slots_for(p), collision_shapes_for(p, with_seats), screen_for(p) and
## slots_for(p), which work from parameters alone.

const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const PhysicsShapes := preload("res://scripts/play/physics_shapes.gd")
const Shapes := preload("res://scripts/env/systems/kit/shapes.gd")
const Procedural := preload("res://scripts/env/systems/kit/procedural.gd")
const SeatModels := preload("res://scripts/env/systems/kit/seat_models.gd")
const U := preload("res://scripts/env/systems/kit/build_util.gd")
## Nodes the sight-line check looks through (screen_frame.gd SEE_THROUGH).
const SEE_THROUGH := "env_see_through"
## The flicker's frequencies (Hz): every one under the photosensitivity ceiling (room_schema.gd MAX_HZ, 3).
const FLICKER_HZ: Array[float] = [0.37, 0.83, 1.31, 2.07]
## The surface key glass is drawn into (a RoomMesh's surface; the glass shader is the mesh's override).
static var GLASS := StandardMaterial3D.new()
const GLOW_SHADER := preload("res://scripts/env/systems/kit/env_flame.gdshader")


## What env_room.gd's room_seat_transforms() reads before the systems are built: layout(p).seat_transforms().
class SeatList:
	var slots: Array

	func _init(s: Array) -> void:
		slots = s

	func seat_transforms() -> Array[Transform3D]:
		return U.transforms(slots)


var _light: Node
var _seats_mm: MultiMeshInstance3D
var _seat_xforms: Array[Transform3D] = []
var _hidden_seat := -1
## Flickering lamps: [material, energy as designed, group, phase].
var _flickering: Array = []
var _flicker_t := 0.0


func setup() -> void:
	_light = host.system_of_kind("light")
	build()


## The builder's own building (setup() has found the light system).
func build() -> void:
	pass


# --- Hooks ---------------------------------------------------------------------------------------------------------

func seat_slots() -> Array:
	var out: Array = get_script().call("seat_slots_for", params)
	for s: Dictionary in out:
		s["builder"] = id
	return out


func seats() -> Array[Transform3D]:
	return U.transforms(seat_slots())


func collision_shapes() -> Array:
	return get_script().call("collision_shapes_for", params, not draws_seats_elsewhere())


func slots() -> Dictionary:
	return get_script().call("slots_for", params)


## The room's default screen for these parameters: {center, size} (a room document's "screen" should match).
func screen() -> Dictionary:
	return get_script().call("screen_for", params)


## A seats system in the room draws the seats (the seats system's interface): this builder draws none.
func draws_seats_elsewhere() -> bool:
	return host != null and host.system_of_kind("seats") != null


# --- Materials and lamps -----------------------------------------------------------------------------------------

func _mat(param: String, instanced := false) -> ShaderMaterial:
	return _light.from_param(params[param], instanced)


## A material parameter with a pattern of procedural.gd over it ("plain": the library's own maps).
func _patterned(param: String, pattern: String, instanced := false) -> ShaderMaterial:
	var m := _mat(param, instanced)
	if pattern != "plain" and pattern != "":
		Procedural.apply(m, pattern, RoomSchemaRef.to_color(params[param].get("color", "#b0b0b0")))
	return m


## A light source's glow (the light system's lamp material). flicker: it wavers with the builder's `flicker`
## parameter (slowly: every frequency under the photosensitivity ceiling).
func _lamp(colour: Color, energy: float, follows_house: float, group: String, flicker := false) -> ShaderMaterial:
	var m: ShaderMaterial = _light.lamp_material(colour, energy, follows_house, group)
	if flicker:
		_flickering.append([m, energy, group, float(_flickering.size()) * 1.7])
	return m


func _group_level(group: String) -> float:
	return float(_light.params.get(_light.GROUPS.get(group, "accent"), 1.0))


func tick(delta: float) -> void:
	if _flickering.is_empty():
		return
	_flicker_t += delta
	var amount := float(params.get("flicker", 0.0))
	for e: Array in _flickering:
		var w := 0.0
		if e.size() < 5 or bool(e[4]):
			for i in FLICKER_HZ.size():
				w += sin(TAU * FLICKER_HZ[i] * _flicker_t + float(e[3]) * (i + 1)) / (i + 1)
		(e[0] as ShaderMaterial).set_shader_parameter("energy", float(e[1]) * _group_level(str(e[2]))
				* (1.0 + 0.1 * amount * w))


## The flicker now, as a factor on the first flickering lamp's energy (tests).
func flicker_factor() -> float:
	if _flickering.is_empty():
		return 1.0
	var e: Array = _flickering[0]
	return float((e[0] as ShaderMaterial).get_shader_parameter("energy")) / maxf(float(e[1]) * _group_level(str(e[2])),
			0.0001)


func _bake_spot(node_name: String, at: Vector3, down: bool, angle: float, reach: float, energy: float,
		colour: Color) -> void:
	var l := SpotLight3D.new()
	l.name = node_name
	l.position = at
	l.rotation = Vector3(-PI * 0.5 if down else PI * 0.5, 0.0, 0.0)
	l.spot_angle = angle
	l.spot_range = reach
	l.light_energy = energy
	l.light_color = colour
	_light.add_bake_light(l)


func _bake_omni(node_name: String, at: Vector3, reach: float, energy: float, colour: Color) -> void:
	var l := OmniLight3D.new()
	l.name = node_name
	l.position = at
	l.omni_range = reach
	l.light_energy = energy
	l.light_color = colour
	_light.add_bake_light(l)


# --- Nodes ---------------------------------------------------------------------------------------------------------

func _add_static(node_name: String, b: RoomMesh) -> MeshInstance3D:
	if b.triangle_count() == 0:
		return null
	var mi := _add_mesh(node_name, b.commit(true))
	mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	return mi


## A mesh lit by the fill, the lamps and the spill but left out of a bake (leaves, rounded seats).
func _add_unbaked(node_name: String, b: RoomMesh) -> MeshInstance3D:
	if b.triangle_count() == 0:
		return null
	var mi := _add_mesh(node_name, b.commit(false))
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return mi


func _add_lamps(node_name: String, b: RoomMesh) -> MeshInstance3D:
	return _add_unbaked(node_name, b)


func _add_glass(node_name: String, b: RoomMesh, colour := Color(0.62, 0.74, 0.8), alpha := 0.06) -> MeshInstance3D:
	if b.triangle_count() == 0:
		return null
	var mesh := b.commit(false)
	var mi := _add_mesh(node_name, mesh)
	mi.material_override = Procedural.glass(colour, alpha, float(room.get("ambient_level")))
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.add_to_group(SEE_THROUGH)
	return mi


func _add_mesh(node_name: String, mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	own(mi)
	return mi


## Pictures on flat quads: [centre, half across, half up, facing] each; one mesh, one lamp material.
func _add_picture(node_name: String, quads: Array, picture: Texture2D, colour: Color, energy: float,
		group: String, flicker := false) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for q: Array in quads:
		var c: Vector3 = q[0]
		var u: Vector3 = q[1]
		var v: Vector3 = q[2]
		var n: Vector3 = q[3]
		var corners := [c - u - v, c + u - v, c + u + v, c - u + v]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		var order := [0, 1, 2, 0, 2, 3]
		if (corners[2] - corners[0]).cross(corners[1] - corners[0]).dot(n) < 0.0:
			order = [0, 2, 1, 0, 3, 2]
		for k: int in order:
			st.set_normal(n)
			st.set_uv(uvs[k])
			st.add_vertex(corners[k])
	var m := _lamp(colour, energy, 0.0, group, flicker)
	m.set_shader_parameter("picture", picture)
	m.set_shader_parameter("use_picture", true)
	var mesh := st.commit()
	mesh.surface_set_material(0, m)
	var mi := _add_mesh(node_name, mesh)
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return mi


## A soft-edged glow on flat quads (flames, a neon tube's halo): the picture added over what is behind
## (env_flame.gdshader), by group, flickering with the builder's `flicker` when asked. See-through for the sight line;
## never baked. quads as _add_picture's.
func _add_glow(node_name: String, quads: Array, picture: Texture2D, colour: Color, energy: float, group: String,
		flicker := false) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for q: Array in quads:
		var c: Vector3 = q[0]
		var u: Vector3 = q[1]
		var v: Vector3 = q[2]
		var n: Vector3 = q[3]
		var corners := [c - u - v, c + u - v, c + u + v, c - u + v]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for k: int in [0, 1, 2, 0, 2, 3]:
			st.set_normal(n)
			st.set_uv(uvs[k])
			st.add_vertex(corners[k])
	var m := ShaderMaterial.new()
	m.shader = GLOW_SHADER
	m.set_shader_parameter("colour", colour)
	m.set_shader_parameter("picture", picture)
	m.set_shader_parameter("energy", energy * _group_level(group))
	# The flicker (and the group's level) through tick(); steady ones too, so the group's level follows.
	_flickering.append([m, energy, group, float(_flickering.size()) * 1.7, flicker])
	var mesh := st.commit()
	mesh.surface_set_material(0, m)
	var mi := _add_mesh(node_name, mesh)
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.add_to_group(SEE_THROUGH)
	return mi


# --- Seats ---------------------------------------------------------------------------------------------------------

## The plain default seats in the slots (none when the room has a seats system): single seats as one MultiMesh.
func _build_seat_multimesh(model: String, cover: ShaderMaterial, frame: ShaderMaterial, slots: Array,
		seed_value := 1, variation := 0.6) -> void:
	if draws_seats_elsewhere() or slots.is_empty():
		return
	cover.set_shader_parameter("instance_tint", true)
	var mesh := SeatModels.mesh(model, cover, frame)
	_seat_xforms = U.transforms(slots)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = _seat_xforms.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in _seat_xforms.size():
		mm.set_instance_transform(i, _seat_xforms[i])
		var v := lerpf(1.0, rng.randf_range(0.86, 1.1), variation)
		var warm := rng.randf_range(-0.04, 0.04) * variation
		mm.set_instance_color(i, Color(v * (1.0 + warm), v, v * (1.0 - warm)))
	_seats_mm = MultiMeshInstance3D.new()
	_seats_mm.name = "Seats"
	_seats_mm.multimesh = mm
	_seats_mm.set_meta("instances", _seat_xforms.size())
	_seats_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_seats_mm.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	own(_seats_mm)


func on_room_moved() -> void:
	_hide_occupied_seat()


## The seat the viewer sits in (the room moved so it is at the origin) is folded away; the others are all there.
func _hide_occupied_seat() -> void:
	if _seats_mm == null or not room.is_inside_tree():
		return
	var here := room.global_transform.affine_inverse() * Vector3.ZERO
	var found := -1
	for i in _seat_xforms.size():
		var o := _seat_xforms[i].origin
		if Vector2(o.x - here.x, o.z - here.z).length() < 0.2 and absf(o.y - here.y) < 0.2:
			found = i
			break
	if found == _hidden_seat:
		return
	var mm := _seats_mm.multimesh
	if _hidden_seat >= 0:
		mm.set_instance_transform(_hidden_seat, _seat_xforms[_hidden_seat])
	if found >= 0:
		mm.set_instance_transform(found, _seat_xforms[found].scaled_local(Vector3.ZERO))
	_hidden_seat = found


func hidden_seat() -> int:
	return _hidden_seat
