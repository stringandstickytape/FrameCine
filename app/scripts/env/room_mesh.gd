extends RefCounted

## An ArrayMesh built in code for a built-in room (environments/cinema.gd): faces, strips and boxes in the room's
## coordinates, one surface per material, and, for the static parts, its own second UV set (UV2) for a baked lightmap
## (LightmapGI, scripts/env/room_bake.gd). Every face, or every strip of faces, is a chart; the charts are laid out on
## shelves at TEXEL metres a texel with PAD texels round each, and the mesh's lightmap_size_hint is the atlas's size.
## Not ArrayMesh.lightmap_unwrap() (xatlas): this costs nothing at a room change and lays out the same atlas every
## time, so a lightmap baked once still fits the room built again at the next start.
## UV (the first set) is each chart's own coordinates in metres, for a material that wants the mesh's UVs; the
## library materials use the surface's own axes by default (room_material.gdshaderinc) and ignore it.
##
##   var b := RoomMesh.new()
##   b.surface(material)                         the following faces go to this material's surface
##   b.face([a, b, c, d], normal)                one flat face (a chart), corners in order round it, either way
##   b.box(centre, size, basis, skip, inside)    a box's faces (each a chart); skip: faces left out, by outward normal
##   b.strip(line_a, line_b, normals)            a strip of quads between two polylines (one chart, unrolled)
##   b.rounded_box(centre, size, radius, ...)    a box with rounded edges and smooth normals (no chart: seats)
##   b.commit(with_uv2) -> ArrayMesh

const TEXEL := 0.1
const PAD := 2

## Faces of a box, by their outward normal (box()'s skip).
const LEFT := Vector3.LEFT
const RIGHT := Vector3.RIGHT
const DOWN := Vector3.DOWN
const UP := Vector3.UP
const FRONT := Vector3.FORWARD
const BACK := Vector3.BACK


## One surface's arrays (an object, so they are changed in place).
class Surf:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var colours := PackedColorArray()
	var indices := PackedInt32Array()


## material -> Surf, and the order the surfaces were first used.
var _surfaces := {}
var _order: Array[Material] = []
var _current: Surf
## [{surface: Surf, first, count, size}]: each chart's vertices; their chart coordinates (metres) are in uvs.
var _charts: Array[Dictionary] = []
var _chart_open := false
var _chart_first := 0
var _chart_min := Vector2(INF, INF)
var _chart_max := Vector2(-INF, -INF)
## Vertex colour for what follows (white: an instance colour multiplies through unchanged).
var colour := Color.WHITE


func surface(material: Material) -> void:
	if not _surfaces.has(material):
		_surfaces[material] = Surf.new()
		_order.append(material)
	_current = _surfaces[material]


func vertex_count() -> int:
	var n := 0
	for s: Surf in _surfaces.values():
		n += s.verts.size()
	return n


func triangle_count() -> int:
	var n := 0
	for s: Surf in _surfaces.values():
		n += s.indices.size() / 3
	return n


## One flat face: its corners in order round it (either way), the side it faces.
func face(corners: Array, normal: Vector3) -> void:
	var a: Vector3 = corners[0]
	var u_axis: Vector3 = (Vector3(corners[1]) - a).normalized()
	var v_axis := normal.cross(u_axis).normalized()
	_begin_chart()
	var base := _current.verts.size()
	for p: Vector3 in corners:
		_vertex(p, normal, Vector2((p - a).dot(u_axis), (p - a).dot(v_axis)))
	for i in range(1, corners.size() - 1):
		_triangle(base, base + i, base + i + 1, corners[0], corners[i], corners[i + 1], normal)
	_end_chart()


## A box: its six faces (outward normals; inward with inside true, for a room's shell), each a chart.
func box(centre: Vector3, size: Vector3, basis := Basis(), skip: Array = [], inside := false) -> void:
	var h := size * 0.5
	for n: Vector3 in [LEFT, RIGHT, DOWN, UP, FRONT, BACK]:
		if n in skip:
			continue
		# Two axes across the face.
		var a1 := Vector3(n.y, n.z, n.x).abs()
		var a2 := n.cross(a1).abs()
		var corners: Array = []
		for k: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			corners.append(centre + basis * (n * h + a1 * h * k.x + a2 * h * k.y))
		face(corners, (basis * n).normalized() * (-1.0 if inside else 1.0))


## A strip of quads between two polylines of the same length (a curved tread or riser): one chart, unrolled along
## line_a. normals: one per point (shared by both lines), so a curve shades smoothly.
func strip(line_a: PackedVector3Array, line_b: PackedVector3Array, normals: PackedVector3Array) -> void:
	_begin_chart()
	var base := _current.verts.size()
	var along := 0.0
	for i in line_a.size():
		if i > 0:
			along += line_a[i].distance_to(line_a[i - 1])
		_vertex(line_a[i], normals[i], Vector2(along, 0.0))
		_vertex(line_b[i], normals[i], Vector2(along, line_a[i].distance_to(line_b[i])))
	for i in line_a.size() - 1:
		var n := (normals[i] + normals[i + 1]).normalized()
		var a := base + i * 2
		_triangle(a, a + 2, a + 3, line_a[i], line_a[i + 1], line_b[i + 1], n)
		_triangle(a, a + 3, a + 1, line_a[i], line_b[i + 1], line_b[i], n)
	_end_chart()


## A box with rounded edges and smooth normals, no chart (for instanced parts, which are never baked). steps: rows of
## the rounding (each edge's quarter round in 2 * steps slices); inner: extra rows across the flat middle, per axis
## (for bend). bend: the box curves in plan, z += bend * x * x (a seat back), normals turned with it. skip: faces left
## out (unseen undersides). xform places it.
func rounded_box(centre: Vector3, size: Vector3, radius: float, xform := Transform3D(), steps := 1,
		inner := Vector3i.ZERO, bend := 0.0, skip: Array = []) -> void:
	var r := minf(radius, minf(size.x, minf(size.y, size.z)) * 0.5 - 0.001)
	var hi := size * 0.5 - Vector3.ONE * r
	var axes_values: Array = []
	for axis in 3:
		var vals: Array[float] = []
		for k in range(steps, 0, -1):
			vals.append(-hi[axis] - r * float(k) / steps)
		vals.append(-hi[axis])
		for k in range(1, inner[axis] + 1):
			vals.append(lerpf(-hi[axis], hi[axis], float(k) / (inner[axis] + 1)))
		vals.append(hi[axis])
		for k in range(1, steps + 1):
			vals.append(hi[axis] + r * float(k) / steps)
		axes_values.append(vals)
	for n: Vector3 in [LEFT, RIGHT, DOWN, UP, FRONT, BACK]:
		if n in skip:
			continue
		var axis := 0 if n.x != 0.0 else (1 if n.y != 0.0 else 2)
		var u_axis := (axis + 1) % 3
		var v_axis := (axis + 2) % 3
		var us: Array = axes_values[u_axis]
		var vs: Array = axes_values[v_axis]
		var base := _current.verts.size()
		var grid: Array[Vector3] = []
		var grid_n: Array[Vector3] = []
		for vi in vs.size():
			for ui in us.size():
				var p := Vector3.ZERO
				p[axis] = (hi[axis] + r) * n[axis]
				p[u_axis] = us[ui]
				p[v_axis] = vs[vi]
				# Pushed out from the inner box: the corners and edges come out round.
				var core := p.clamp(-hi, hi)
				var dir := (p - core).normalized()
				var q := core + dir * r
				var nn := dir
				if bend != 0.0:
					nn = Basis(Vector3.UP, -atan(2.0 * bend * q.x)) * nn
					q.z += bend * q.x * q.x
				q = xform * (centre + q)
				nn = (xform.basis * nn).normalized()
				grid.append(q)
				grid_n.append(nn)
				_vertex(q, nn, Vector2(q.x, q.y))
		var w := us.size()
		for vi in vs.size() - 1:
			for ui in w - 1:
				var i0 := vi * w + ui
				var i1 := i0 + 1
				var i2 := i0 + w + 1
				var i3 := i0 + w
				var fn := (grid_n[i0] + grid_n[i2]).normalized()
				_triangle(base + i0, base + i1, base + i2, grid[i0], grid[i1], grid[i2], fn)
				_triangle(base + i0, base + i2, base + i3, grid[i0], grid[i2], grid[i3], fn)


## The mesh: one surface per material, in the order they were first used. with_uv2: the charts laid out as a
## lightmap atlas (UV2) and lightmap_size_hint set; without, no UV2 (instanced or never baked).
func commit(with_uv2 := true) -> ArrayMesh:
	var atlas := _pack() if with_uv2 else Vector2i.ZERO
	var mesh := ArrayMesh.new()
	for m: Material in _order:
		var s: Surf = _surfaces[m]
		if s.indices.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = s.verts
		arrays[Mesh.ARRAY_NORMAL] = s.normals
		arrays[Mesh.ARRAY_TEX_UV] = s.uvs
		arrays[Mesh.ARRAY_COLOR] = s.colours
		if with_uv2:
			arrays[Mesh.ARRAY_TEX_UV2] = s.uv2
		arrays[Mesh.ARRAY_INDEX] = s.indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, m)
	if with_uv2:
		mesh.lightmap_size_hint = atlas
	return mesh


func _vertex(p: Vector3, n: Vector3, uv: Vector2) -> void:
	_current.verts.append(p)
	_current.normals.append(n)
	_current.uvs.append(uv)
	_current.colours.append(colour)
	if _chart_open:
		_chart_min = _chart_min.min(uv)
		_chart_max = _chart_max.max(uv)


## A triangle facing `n`: Godot draws the side where the corners run clockwise.
func _triangle(i0: int, i1: int, i2: int, p0: Vector3, p1: Vector3, p2: Vector3, n: Vector3) -> void:
	if (p2 - p0).cross(p1 - p0).dot(n) >= 0.0:
		_current.indices.append_array([i0, i1, i2])
	else:
		_current.indices.append_array([i0, i2, i1])


func _begin_chart() -> void:
	_chart_open = true
	_chart_first = _current.verts.size()
	_chart_min = Vector2(INF, INF)
	_chart_max = Vector2(-INF, -INF)


func _end_chart() -> void:
	_chart_open = false
	var count := _current.verts.size() - _chart_first
	# The chart's own coordinates from 0 (they are also its UVs in metres).
	for i in range(_chart_first, _chart_first + count):
		_current.uvs[i] -= _chart_min
	_charts.append({"surface": _current, "first": _chart_first, "count": count, "size": _chart_max - _chart_min})


## Shelf packing, tallest first: each chart's place in the atlas, written to its surface's UV2. Returns the atlas's
## size in texels.
func _pack() -> Vector2i:
	for s: Surf in _surfaces.values():
		s.uv2.resize(s.verts.size())
	var cells: Array[Vector2i] = []
	var area := 0
	for c: Dictionary in _charts:
		var size: Vector2 = c["size"]
		var cell := Vector2i(ceili(size.x / TEXEL) + 1 + PAD * 2, ceili(size.y / TEXEL) + 1 + PAD * 2)
		cells.append(cell)
		area += cell.x * cell.y
	var order: Array = range(_charts.size())
	order.sort_custom(func(a: int, b: int) -> bool: return cells[a].y > cells[b].y)
	var width := ceili(sqrt(float(area)) * 1.2)
	for cell in cells:
		width = maxi(width, cell.x)
	width = ceili(width / 4.0) * 4
	var at := Vector2i.ZERO
	var shelf := 0
	var origin: Array[Vector2i] = []
	origin.resize(_charts.size())
	for i: int in order:
		if at.x + cells[i].x > width:
			at = Vector2i(0, at.y + shelf)
			shelf = 0
		origin[i] = at
		at.x += cells[i].x
		shelf = maxi(shelf, cells[i].y)
	var atlas := Vector2i(width, maxi(ceili((at.y + shelf) / 4.0) * 4, 4))
	for i in _charts.size():
		var c: Dictionary = _charts[i]
		var s: Surf = c["surface"]
		var first: int = c["first"]
		for k in range(first, first + int(c["count"])):
			s.uv2[k] = (Vector2(origin[i] + Vector2i(PAD, PAD)) + s.uvs[k] / TEXEL + Vector2(0.5, 0.5)) / Vector2(atlas)
	return atlas
