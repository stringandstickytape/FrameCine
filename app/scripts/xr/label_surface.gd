extends RefCounted

## The surface of a controller model, for the print that lies on it. It keeps the model's triangles (read once per
## model, in the label root's space, with each part where it stood then) and lays a legend on them as a small mesh: one
## patch per glyph, every vertex just above the plastic, the text flat in its UVs, so it wraps the shape like print and
## neither stretches nor sinks. Built when a legend or the model changes, never per frame. It works on any meshes:
## the runtime's model, our own, the hand-built body.
##
## How a legend is laid: the surface under its rectangle is rasterised into a grid of heights in the legend's own frame
## (faster than a ray per point, and it finds the exact triangles). A legend can be square to the face and yet lie on
## plastic that slopes away, which would stretch the text as much as the slope, so the frame is first turned to the
## smooth surface fitted through those heights and the grid is read again. What breaks away from that surface is a step
## (the wells round the buttons, seams), not plastic to follow: the print bridges it, as a sticker would, and doesn't
## dive in. A step has plastic on both sides of it; a glyph with no plastic under it, past the edge of the model, is
## left out, or it would hang in the air. On a long legend the wall still curves, so the glyphs are spaced by length
## along the surface, not along the flat frame. A legend belongs to the part most of it lies on, so it moves with that
## part and no other.

## Height over the plastic. Enough to clear the small sag of the patches over the curved surface, too little to see.
const OFFSET := 0.00015
## Grid over the legend's rectangle.
const GRID := 0.0005
## Margin of the grid around the rectangle: a glyph's quad reaches past the text by the field's padding.
const MARGIN := 0.001
## Patch of one glyph, cells each way.
const PATCH := 3
## Below this slope the frame stays as it is.
const MIN_TILT := deg_to_rad(0.5)
## Further than this from the smooth surface is a step, and bridged.
const STEP := 0.0004
## Cells of the grid per sample of the fit, each way.
const FIT_STRIDE := 3

## [{"node": MeshInstance3D, "to_root": its pose, "faces": PackedVector3Array in the root's space, "box": AABB}]
var parts: Array[Dictionary] = []


## Reads a part's triangles. to_root: the node's pose in the space the legends are placed in.
func add_part(node: MeshInstance3D, to_root: Transform3D) -> void:
	if node.mesh == null:
		return
	var faces: PackedVector3Array = to_root * node.mesh.get_faces()
	if faces.is_empty():
		return
	var box := AABB(faces[0], Vector3.ZERO)
	for v in faces:
		box = box.expand(v)
	parts.append({"node": node, "to_root": to_root, "faces": faces, "box": box})


## Lays a legend on the surface. frame: X along the text, Y out of the surface, Z down the text, origin at the centre
## of the rectangle; size: text width, how far the surface is looked for along Y (half each way), text height; quads
## and scale from label_font.gd (metres per em). Returns {"node": the part it lies on, "vertices", "uvs", "indices"
## (in the root's space), "kept": the quads printed, "frame": the fitted frame, "cover": the share of the rectangle on the surface, "bridged":
## the share of it over a step, "reach": the largest height off the frame's plane}, or {} when no surface is there.
func lay(frame: Transform3D, size: Vector3, quads: Array, scale: float) -> Dictionary:
	var half := Vector2(size.x * 0.5 + MARGIN, size.z * 0.5 + MARGIN)
	var depth := size.y * 0.5
	var grid := _read(frame, half, depth)
	if grid.is_empty():
		return {}
	var empty := _empty_cells(grid)
	var fitted := _turned(frame, _bridged(grid, half), half)
	if fitted != frame:
		var again := _read(fitted, half, depth, grid["part"])
		if not again.is_empty():
			grid = again
			frame = fitted
			empty = _empty_cells(grid)
			_bridged(grid, half)
	var arc := _arc_lengths(grid)
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var kept := PackedInt32Array()
	var top_left := Vector2(-size.x * 0.5, -size.z * 0.5)
	for q in quads.size():
		var rect: Rect2 = quads[q][0]
		var uv: Rect2 = quads[q][1]
		if _off_the_edge(empty, grid, half, top_left + (rect.position + rect.size * 0.5) * scale):
			continue
		kept.append(q)
		var base := vertices.size()
		for j in PATCH + 1:
			for i in PATCH + 1:
				var along := Vector2(float(i), float(j)) / PATCH
				var p := top_left + (rect.position + rect.size * along) * scale
				p.x = _unrolled(arc, p.x, half.x)
				vertices.append(frame * Vector3(p.x, _height(grid, half, p) + OFFSET, p.y))
				uvs.append(uv.position + uv.size * along)
		for j in PATCH:
			for i in PATCH:
				var a := base + j * (PATCH + 1) + i
				var b := a + 1
				var c := a + PATCH + 1
				var d := c + 1
				indices.append_array(PackedInt32Array([a, b, c, b, d, c]))
	var reach := 0.0
	var heights: PackedFloat32Array = grid["heights"]
	for h in heights:
		reach = maxf(reach, absf(h))
	return {"node": parts[grid["part"]]["node"], "vertices": vertices, "uvs": uvs, "indices": indices, "kept": kept, "frame": frame,
			"cover": grid["cover"], "bridged": grid["bridged"], "reach": reach}


## The vertices' worst distance from the plastic along the laid frame, past the print's height: ray per vertex. Over a
## step the print bridges, on purpose: x is the worst over plastic it follows, y how far it stands over a step.
func worst_gap(laid: Dictionary) -> Vector2:
	var frame: Transform3D = laid["frame"]
	var worst := Vector2.ZERO
	var vertices: PackedVector3Array = laid["vertices"]
	var y := frame.basis.y.normalized()
	var faces := PackedVector3Array()
	for part: Dictionary in parts:
		if part["node"] == laid["node"]:
			faces = part["faces"]
	# In millimetres: the engine's ray test takes small triangles in metres as edge-on (see tools/label_layout.gd).
	var mm := scaled(faces, 1000.0)
	for i in range(0, vertices.size(), 7):
		var from := (vertices[i] + y * 0.005) * 1000.0
		var best := INF
		for t in range(0, mm.size(), 3):
			var hit: Variant = Geometry3D.ray_intersects_triangle(from, -y, mm[t], mm[t + 1], mm[t + 2])
			if hit != null:
				best = minf(best, from.distance_to(hit))
		var gap := absf((best - 5.0) / 1000.0 - OFFSET)
		if gap < STEP:
			worst.x = maxf(worst.x, gap)
		elif best != INF and gap < 0.006:
			worst.y = maxf(worst.y, gap)
	return worst


static func scaled(points: PackedVector3Array, by: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(points.size())
	for i in points.size():
		out[i] = points[i] * by
	return out


## The most any edge of a laid legend's patches is longer than in the flat text: 1.1 = stretched by 10 %.
static func stretch(laid: Dictionary, quads: Array, scale: float) -> float:
	var vertices: PackedVector3Array = laid["vertices"]
	var row := PATCH + 1
	var worst := 1.0
	var kept: PackedInt32Array = laid["kept"]
	for k in kept.size():
		var rect: Rect2 = quads[kept[k]][0]
		var base: int = k * row * row
		var along := rect.size.x * scale / PATCH
		var down := rect.size.y * scale / PATCH
		for j in row:
			for i in row:
				var at := base + j * row + i
				if i < row - 1:
					worst = maxf(worst, vertices[at].distance_to(vertices[at + 1]) / along)
				if j < row - 1:
					worst = maxf(worst, vertices[at].distance_to(vertices[at + row]) / down)
	return worst


## A mesh of laid legends that all lie on one part, in that part's own space, so it can hang under the part's node.
func mesh_for(node: MeshInstance3D, laid: Array) -> ArrayMesh:
	var to_part := Transform3D()
	for part: Dictionary in parts:
		if part["node"] == node:
			to_part = (part["to_root"] as Transform3D).affine_inverse()
			break
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for one: Dictionary in laid:
		var base := vertices.size()
		vertices.append_array(to_part * (one["vertices"] as PackedVector3Array))
		uvs.append_array(one["uvs"])
		for i: int in one["indices"]:
			indices.append(base + i)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## The height of the outermost plastic over a grid of the frame's plane, from one part (the one with most of the
## rectangle) or the part given. {} when none lies there. Faces turned away are skipped: the print is on the outside.
func _read(frame: Transform3D, half: Vector2, depth: float, only := -1) -> Dictionary:
	var nx := ceili(half.x * 2.0 / GRID) + 1
	var nz := ceili(half.y * 2.0 / GRID) + 1
	var to_frame := frame.affine_inverse()
	var region := frame * AABB(Vector3(-half.x, -depth, -half.y), Vector3(half.x, depth, half.y) * 2.0)
	var best := {}
	var best_cells := 0
	var tops := PackedFloat32Array()
	tops.resize(nx * nz)
	tops.fill(-INF)
	var owners := PackedInt32Array()
	owners.resize(nx * nz)
	owners.fill(-1)
	var read := []
	for p in parts.size():
		if (only >= 0 and p != only) or not (parts[p]["box"] as AABB).intersects(region):
			continue
		var heights := _rasterise(to_frame * (parts[p]["faces"] as PackedVector3Array), nx, nz, half, depth)
		read.append([p, heights])
		for i in heights.size():
			if heights[i] > tops[i]:
				tops[i] = heights[i]
				owners[i] = p
	var counts := {}
	for o in owners:
		if o >= 0:
			counts[o] = int(counts.get(o, 0)) + 1
	var winner := -1
	for p: int in counts:
		if int(counts[p]) > best_cells:
			best_cells = counts[p]
			winner = p
	if winner < 0:
		return {}
	for item: Array in read:
		if item[0] == winner:
			best = {"part": winner, "heights": item[1], "nx": nx, "nz": nz, "cover": float(best_cells) / (nx * nz)}
	return best


## Rasterises triangles given in the frame's space into the grid: the highest within `depth` of the plane at each
## point, -INF where there is none.
static func _rasterise(faces: PackedVector3Array, nx: int, nz: int, half: Vector2, depth: float) -> PackedFloat32Array:
	var heights := PackedFloat32Array()
	heights.resize(nx * nz)
	heights.fill(-INF)
	for t in range(0, faces.size(), 3):
		var a := faces[t]
		var b := faces[t + 1]
		var c := faces[t + 2]
		if minf(a.x, minf(b.x, c.x)) > half.x or maxf(a.x, maxf(b.x, c.x)) < -half.x:
			continue
		if minf(a.z, minf(b.z, c.z)) > half.y or maxf(a.z, maxf(b.z, c.z)) < -half.y:
			continue
		if minf(a.y, minf(b.y, c.y)) > depth or maxf(a.y, maxf(b.y, c.y)) < -depth:
			continue
		# Twice the area on the plane; positive when the face looks out along +Y (Godot's fronts wind clockwise).
		var area := (b.x - a.x) * (c.z - a.z) - (c.x - a.x) * (b.z - a.z)
		if area <= 1e-14:
			continue
		var i0 := maxi(ceili((minf(a.x, minf(b.x, c.x)) + half.x) / GRID), 0)
		var i1 := mini(floori((maxf(a.x, maxf(b.x, c.x)) + half.x) / GRID), nx - 1)
		var j0 := maxi(ceili((minf(a.z, minf(b.z, c.z)) + half.y) / GRID), 0)
		var j1 := mini(floori((maxf(a.z, maxf(b.z, c.z)) + half.y) / GRID), nz - 1)
		for j in range(j0, j1 + 1):
			var z := j * GRID - half.y
			for i in range(i0, i1 + 1):
				var x := i * GRID - half.x
				var wb := ((x - a.x) * (c.z - a.z) - (c.x - a.x) * (z - a.z)) / area
				var wc := ((b.x - a.x) * (z - a.z) - (x - a.x) * (b.z - a.z)) / area
				if wb < -1e-4 or wc < -1e-4 or wb + wc > 1.0001:
					continue
				var h := a.y + (b.y - a.y) * wb + (c.y - a.y) * wc
				if absf(h) <= depth and h > heights[j * nx + i]:
					heights[j * nx + i] = h
	return heights


## The frame turned and moved onto the smooth surface at the legend's centre, keeping the text's direction. The same
## frame when the slope is too small to matter.
static func _turned(frame: Transform3D, smooth: PackedFloat64Array, half: Vector2) -> Transform3D:
	var y := Vector3(-smooth[1] / half.x, 1.0, -smooth[2] / half.y).normalized()
	if y.angle_to(Vector3.UP) < MIN_TILT:
		return frame
	# The baseline may rise and fall with the surface, and nothing else: it stays in the plane of the frame's X and Y, so
	# seen along Y, and along Z on a wall, it is square to the axis the legend was placed on.
	var x := Vector3(1.0, -y.x / y.y, 0.0).normalized()
	return frame * Transform3D(Basis(x, y, x.cross(y)), Vector3(0.0, smooth[0], 0.0))


## Height over the frame = c0 + c1 u + c2 v + c3 u^2 + c4 uv + c5 v^2, with u, v from -1 to 1 over the grid: least
## squares over a sparse sample of the cells that hit, which is plenty for a surface this smooth.
static func _fit(grid: Dictionary, half: Vector2) -> PackedFloat64Array:
	var heights: PackedFloat32Array = grid["heights"]
	var nx: int = grid["nx"]
	var nz: int = grid["nz"]
	var size := 6
	var a := PackedFloat64Array()
	a.resize(size * (size + 1))
	var terms := PackedFloat64Array()
	terms.resize(size)
	for j in range(0, nz, FIT_STRIDE):
		for i in range(0, nx, FIT_STRIDE):
			var h := heights[j * nx + i]
			if h == -INF:
				continue
			var u := (i * GRID - half.x) / half.x
			var v := (j * GRID - half.y) / half.y
			terms[0] = 1.0
			terms[1] = u
			terms[2] = v
			terms[3] = u * u
			terms[4] = u * v
			terms[5] = v * v
			for r in size:
				for c in size:
					a[r * (size + 1) + c] += terms[r] * terms[c]
				a[r * (size + 1) + size] += terms[r] * h
	# Gaussian elimination with partial pivoting; a term the sample can't tell (a narrow band of hits) stays zero.
	var out := PackedFloat64Array()
	out.resize(size)
	var pivots := PackedInt32Array()
	var free := []
	for c in size:
		var best := -1
		var value := 1e-6
		for r in size:
			if r not in pivots and absf(a[r * (size + 1) + c]) > value:
				value = absf(a[r * (size + 1) + c])
				best = r
		if best < 0:
			free.append(c)
			pivots.append(-1)
			continue
		pivots.append(best)
		for r in size:
			if r != best:
				var f := a[r * (size + 1) + c] / a[best * (size + 1) + c]
				if f != 0.0:
					for k in size + 1:
						a[r * (size + 1) + k] -= f * a[best * (size + 1) + k]
	for c in size:
		if c not in free:
			out[c] = a[pivots[c] * (size + 1) + size] / a[pivots[c] * (size + 1) + c]
	return out


static func _smooth_height(smooth: PackedFloat64Array, u: float, v: float) -> float:
	return smooth[0] + smooth[1] * u + smooth[2] * v + smooth[3] * u * u + smooth[4] * u * v + smooth[5] * v * v


## The smooth surface through the grid. Cells that break away from it are steps (a well, a seam) and cells with no
## plastic under them (past an edge) take its height instead: the print bridges them. Returns it; grid["bridged"] is
## the share of the grid that was a step.
static func _bridged(grid: Dictionary, half: Vector2) -> PackedFloat64Array:
	var heights: PackedFloat32Array = grid["heights"]
	var nx: int = grid["nx"]
	var nz: int = grid["nz"]
	var smooth := _fit(grid, half)
	var steps := 0
	# A wide limit first: a deep well pulls the first fit towards it.
	for limit: float in [STEP * 3.0, STEP]:
		for j in nz:
			var v := (j * GRID - half.y) / half.y
			for i in nx:
				var h := heights[j * nx + i]
				if h != -INF and absf(h - _smooth_height(smooth, (i * GRID - half.x) / half.x, v)) > limit:
					heights[j * nx + i] = -INF
					steps += 1
		grid["heights"] = heights
		smooth = _fit(grid, half)
	for j in nz:
		var v := (j * GRID - half.y) / half.y
		for i in nx:
			if heights[j * nx + i] == -INF:
				heights[j * nx + i] = _smooth_height(smooth, (i * GRID - half.x) / half.x, v)
	grid["heights"] = heights
	# Added to: the grid can come through here twice, and the steps are gone the second time.
	grid["bridged"] = float(grid.get("bridged", 0.0)) + float(steps) / (nx * nz)
	return smooth


## Which cells have no plastic under them, as read (the bridging fills them in).
static func _empty_cells(grid: Dictionary) -> PackedByteArray:
	var heights: PackedFloat32Array = grid["heights"]
	var out := PackedByteArray()
	out.resize(heights.size())
	for i in heights.size():
		out[i] = 1 if heights[i] == -INF else 0
	return out


## Whether the glyph centred at a point of the plane has no plastic under its middle.
static func _off_the_edge(empty: PackedByteArray, grid: Dictionary, half: Vector2, p: Vector2) -> bool:
	var nx: int = grid["nx"]
	var nz: int = grid["nz"]
	var i := roundi((p.x + half.x) / GRID)
	var j := roundi((p.y + half.y) / GRID)
	return i < 0 or j < 0 or i >= nx or j >= nz or empty[j * nx + i] == 1


## Length along the surface from the left of the grid to each column, on the legend's centre line.
static func _arc_lengths(grid: Dictionary) -> PackedFloat32Array:
	var heights: PackedFloat32Array = grid["heights"]
	var nx: int = grid["nx"]
	var row: int = grid["nz"] / 2 * nx
	var out := PackedFloat32Array()
	out.resize(nx)
	var length := 0.0
	for i in range(1, nx):
		length += Vector2(GRID, heights[row + i] - heights[row + i - 1]).length()
		out[i] = length
	return out


## Where on the frame's X a point of the flat text lands, its distance from the legend's centre kept along the surface.
static func _unrolled(arc: PackedFloat32Array, x: float, half_x: float) -> float:
	var centre := arc[arc.size() / 2] + (arc[arc.size() / 2 + 1] - arc[arc.size() / 2]) * (half_x / GRID - arc.size() / 2)
	var want := centre + x
	var i := clampi(arc.bsearch(want), 1, arc.size() - 1)
	var part := (want - arc[i - 1]) / maxf(arc[i] - arc[i - 1], 1e-9)
	return (i - 1 + part) * GRID - half_x


## The grid's height at a point of the plane (bilinear).
static func _height(grid: Dictionary, half: Vector2, p: Vector2) -> float:
	var heights: PackedFloat32Array = grid["heights"]
	var nx: int = grid["nx"]
	var nz: int = grid["nz"]
	var fx := clampf((p.x + half.x) / GRID, 0.0, nx - 1.001)
	var fz := clampf((p.y + half.y) / GRID, 0.0, nz - 1.001)
	var i := int(fx)
	var j := int(fz)
	var top := lerpf(heights[j * nx + i], heights[j * nx + i + 1], fx - i)
	var bottom := lerpf(heights[(j + 1) * nx + i], heights[(j + 1) * nx + i + 1], fx - i)
	return lerpf(top, bottom, fz - j)
