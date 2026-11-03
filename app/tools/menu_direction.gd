extends RefCounted

## The direction of a hand's menu or view button, in its model's space, measured from the button itself: the face legends
## run along it. Used by tools/label_layout.gd and, on its own measurement, by tools/label_proof.gd.
##
## Two figures, from the button's cap: "lines", the atlas's U axis carried onto the cap by its UV mapping, along which the
## printed icon runs, and "edge", the long side of the smallest rectangle round the cap's outline. They agree to about 0.1
## degrees on the dumped models. The right hand's three lines run along U in the atlas to under 0.1 degrees. On the left the
## icon is not three lines, but the mapping and the mesh are the right one's, mirrored.

## The cap: triangles facing the face normal at least this well (cosine).
const CAP_FACING := 0.85


## mi: the button's mesh. to_model: from its space to the model's. n: the face normal. right: the way the text runs, roughly.
## {"lines", "edge": unit vectors, in the model, on the plane square to n; "angle": degrees from right to "lines", towards
## n x right; "edge_angle": the same for "edge"; "rise": degrees "lines" leaves that plane by, on the cap}.
static func measure(mi: MeshInstance3D, to_model: Transform3D, n: Vector3, right: Vector3) -> Dictionary:
	var cap := _cap(mi, to_model, n)
	var points: PackedVector3Array = cap["points"]
	var front := n.cross(right).normalized()
	var lines: Vector3 = _uv_map(cap["ids"], points, cap["uvs"])[0].normalized()
	lines *= signf(lines.dot(right))
	var flat := (lines - n * lines.dot(n)).normalized()
	var outline := PackedVector2Array()
	for i: int in cap["ids"]:
		outline.append(Vector2(points[i].dot(right), points[i].dot(front)))
	var edge := _long_side(outline)
	return {"lines": flat, "edge": right * edge.x + front * edge.y, "angle": rad_to_deg(atan2(flat.dot(front), flat.dot(right))),
			"edge_angle": rad_to_deg(atan2(edge.y, edge.x)), "rise": rad_to_deg(asin(clampf(lines.dot(n), -1.0, 1.0)))}


## From atlas to model on a cap: [A, B, C], where p = (u - mean u) A + (v - mean v) B + C, and the mean UV.
static func cap_map(mi: MeshInstance3D, to_model: Transform3D, n: Vector3) -> Array:
	var cap := _cap(mi, to_model, n)
	return _uv_map(cap["ids"], cap["points"], cap["uvs"])


## The cap: {"points" in the model, "uvs", "ids" of the vertices on it}.
static func _cap(mi: MeshInstance3D, to_model: Transform3D, n: Vector3) -> Dictionary:
	var arrays := mi.mesh.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for i in points.size():
		points[i] = to_model * points[i]
	var cap := {}
	var facing := 0.0
	for t in range(0, indices.size(), 3):
		facing += (points[indices[t + 1]] - points[indices[t]]).cross(points[indices[t + 2]] - points[indices[t]]).dot(n)
	for t in range(0, indices.size(), 3):
		var a := points[indices[t]]
		var normal := (points[indices[t + 1]] - a).cross(points[indices[t + 2]] - a).normalized() * signf(facing)
		if normal.dot(n) > CAP_FACING:
			for k in 3:
				cap[indices[t + k]] = true
	return {"points": points, "uvs": arrays[Mesh.ARRAY_TEX_UV], "ids": cap.keys()}


## Least squares p = (u - mean u) A + (v - mean v) B + C over the points: [A, B, C, mean UV]. Round the means and in
## doubles: a cap is a small patch of the atlas, far from its origin, and in a Basis' single precision the answer moves by
## a quarter of a degree.
static func _uv_map(ids: Array, points: PackedVector3Array, uvs: PackedVector2Array) -> Array:
	var mean_u := 0.0
	var mean_v := 0.0
	var mean_p: Array[float] = [0.0, 0.0, 0.0]
	for i: int in ids:
		mean_u += uvs[i].x / ids.size()
		mean_v += uvs[i].y / ids.size()
		for c in 3:
			mean_p[c] += points[i][c] / ids.size()
	var uu := 0.0
	var uv := 0.0
	var vv := 0.0
	var up: Array[float] = [0.0, 0.0, 0.0]
	var vp: Array[float] = [0.0, 0.0, 0.0]
	for i: int in ids:
		var u := uvs[i].x - mean_u
		var v := uvs[i].y - mean_v
		uu += u * u
		uv += u * v
		vv += v * v
		for c in 3:
			up[c] += u * (points[i][c] - mean_p[c])
			vp[c] += v * (points[i][c] - mean_p[c])
	var along_u := Vector3.ZERO
	var along_v := Vector3.ZERO
	var det := uu * vv - uv * uv
	for c in 3:
		along_u[c] = (vv * up[c] - uv * vp[c]) / det
		along_v[c] = (uu * vp[c] - uv * up[c]) / det
	return [along_u, along_v, Vector3(mean_p[0], mean_p[1], mean_p[2]), Vector2(mean_u, mean_v)]


## The long side of the smallest rectangle round the points, x positive.
static func _long_side(points: PackedVector2Array) -> Vector2:
	var hull := Geometry2D.convex_hull(points)
	var least := INF
	var best := Vector2.RIGHT
	for i in hull.size() - 1:
		var along := hull[i + 1] - hull[i]
		if along.length() < 1e-6:
			continue
		along = along.normalized()
		var box := Rect2(Vector2(hull[0].dot(along), hull[0].dot(along.orthogonal())), Vector2.ZERO)
		for p in hull:
			box = box.expand(Vector2(p.dot(along), p.dot(along.orthogonal())))
		if box.get_area() < least:
			least = box.get_area()
			best = along if box.size.x >= box.size.y else along.orthogonal()
	return best * signf(best.x)
