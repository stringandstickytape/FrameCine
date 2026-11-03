extends SceneTree

## Tests for RoomModel.turn_inside_out_shapes() (scripts/assistant/room_model.gd): closed shapes built inside out are
## turned the right way, right ones and open ones are left alone. Headless.
## Run: godot --headless --xr-mode off --path app --script res://tests/test_room_model_winding.gd

const RoomModel := preload("res://scripts/assistant/room_model.gd")

var _failures := 0
var _checks := 0


func _init() -> void:
	var right := _sphere()
	var inside_out := _flipped(_sphere())
	_check("a right sphere has a negative signed volume (Godot's winding)", _volume(right, 0) < 0.0)
	_check("the inside-out copy's is positive", _volume(inside_out, 0) > 0.0)

	var r := RoomModel.turn_inside_out_shapes(right)
	_check("a right sphere is left alone", r[0] == null and int(r[1]) == 0)

	r = RoomModel.turn_inside_out_shapes(inside_out)
	var fixed: ArrayMesh = r[0]
	_check("an inside-out sphere is turned (%d)" % int(r[1]), fixed != null and int(r[1]) == 1)
	_check("its volume is negative again", fixed != null and _volume(fixed, 0) < 0.0)
	_check("its normals point out again", fixed != null and _normals_out(fixed, 0))

	# Two pieces in one surface (as the generated room had): one right, one inside out; and an open plane.
	var both := _merged([_sphere(Vector3(-2, 0, 0)), _flipped(_sphere(Vector3(2, 0, 0))), _plane(Vector3(0, 0, 3))])
	r = RoomModel.turn_inside_out_shapes(both)
	_check("of two spheres and a plane in one surface, only the inside-out sphere is turned (%d)" % int(r[1]),
			r[0] != null and int(r[1]) == 1)
	var plane_before := _plane(Vector3(0, 0, 3))
	r = RoomModel.turn_inside_out_shapes(_flipped(plane_before))
	_check("an open plane is never turned, either way up", r[0] == null)
	print("test_room_model_winding: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL ", what)


func _sphere(at := Vector3.ZERO) -> ArrayMesh:
	var a := SphereMesh.new().get_mesh_arrays()
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	for i in v.size():
		v[i] += at
	a[Mesh.ARRAY_VERTEX] = v
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	return m


func _plane(at: Vector3) -> ArrayMesh:
	var a := PlaneMesh.new().get_mesh_arrays()
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	for i in v.size():
		v[i] += at
	a[Mesh.ARRAY_VERTEX] = v
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	return m


## The same mesh inside out: triangles reversed, normals negated (what the generator wrote).
func _flipped(m: ArrayMesh) -> ArrayMesh:
	var a := m.surface_get_arrays(0)
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	for t in range(0, idx.size(), 3):
		var k := idx[t + 1]
		idx[t + 1] = idx[t + 2]
		idx[t + 2] = k
	a[Mesh.ARRAY_INDEX] = idx
	var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	for i in n.size():
		n[i] = -n[i]
	a[Mesh.ARRAY_NORMAL] = n
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	return out


## Several one-surface meshes as one surface (indices offset).
func _merged(meshes: Array) -> ArrayMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var idx := PackedInt32Array()
	for m: ArrayMesh in meshes:
		var a := m.surface_get_arrays(0)
		var base := v.size()
		v.append_array(a[Mesh.ARRAY_VERTEX])
		n.append_array(a[Mesh.ARRAY_NORMAL])
		for i: int in a[Mesh.ARRAY_INDEX]:
			idx.append(base + i)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_INDEX] = idx
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


func _volume(m: ArrayMesh, s: int) -> float:
	var a := m.surface_get_arrays(s)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var vol := 0.0
	for t in range(0, idx.size(), 3):
		vol += v[idx[t]].dot(v[idx[t + 1]].cross(v[idx[t + 2]]))
	return vol


func _normals_out(m: ArrayMesh, s: int) -> bool:
	var a := m.surface_get_arrays(s)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var out := 0
	for i in v.size():
		if v[i].length() > 0.01 and n[i].dot(v[i]) > 0.0:
			out += 1
	return out > v.size() * 0.9
