extends RefCounted

## A library object's thumbnail (object_library.gd), drawn in the app without the GPU: the model's triangles seen from
## the front, a little from above and the right, in its parts' own colours with simple shading, on a clear background.
## It runs anywhere (headless too, and on a worker thread: the nodes are not in a tree) and gives the same picture
## every time, so a thumbnail never waits for a frame or stalls the headset's GPU.
##
##   render(node, size) -> Image (RGBA8, size x size)

## Drawn at this many times the size, then scaled down: smooth edges.
const SUPERSAMPLE := 2
const YAW := deg_to_rad(-28.0)
const PITCH := deg_to_rad(18.0)
const LIGHT := Vector3(-0.45, 0.75, 0.5)
const AMBIENT := 0.5
## The model fills this much of the picture.
const FILL := 0.86
## Past this many triangles every n-th is skipped first: big models still finish in a moment (their triangles are
## smaller than a pixel here anyway).
const TRIANGLES_MAX := 60000


static func render(node: Node3D, size := 128) -> Image:
	var tris := PackedVector3Array()
	var colours := PackedColorArray()
	_collect(node, node, tris, colours)
	var n := size * SUPERSAMPLE
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	if tris.is_empty():
		img.resize(size, size)
		return img
	var view := Basis(Vector3.RIGHT, PITCH) * Basis(Vector3.UP, YAW)
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for i in tris.size():
		tris[i] = view * tris[i]
		lo = lo.min(tris[i])
		hi = hi.max(tris[i])
	var extent := maxf(hi.x - lo.x, hi.y - lo.y)
	var scale := n * FILL / maxf(extent, 1e-6)
	var mid := (lo + hi) * 0.5
	var depth := PackedFloat32Array()
	depth.resize(n * n)
	depth.fill(-INF)
	var light := LIGHT.normalized()
	var step := maxi(1, ceili(float(tris.size() / 3) / TRIANGLES_MAX))
	for t in range(0, tris.size() / 3, step):
		var a := tris[t * 3]
		var b := tris[t * 3 + 1]
		var c := tris[t * 3 + 2]
		var normal := (b - a).cross(c - a)
		if normal.length_squared() < 1e-20:
			continue
		normal = normal.normalized()
		# Godot's front faces wind clockwise as seen: their cross product points away from the eye (+Z towards it).
		if normal.z > 0.0:
			continue
		var shade := AMBIENT + (1.0 - AMBIENT) * maxf(0.0, -normal.dot(light))
		var col: Color = colours[t]
		col = Color(col.r * shade, col.g * shade, col.b * shade, 1.0)
		var pa := _px(a, mid, scale, n)
		var pb := _px(b, mid, scale, n)
		var pc := _px(c, mid, scale, n)
		_fill(img, depth, n, pa, pb, pc, col)
	img.resize(size, size, Image.INTERPOLATE_BILINEAR)
	return img


static func _px(p: Vector3, mid: Vector3, scale: float, n: int) -> Vector3:
	return Vector3((p.x - mid.x) * scale + n * 0.5, (mid.y - p.y) * scale + n * 0.5, p.z)


## One triangle into the picture, nearer than what is there (z towards the eye is larger).
static func _fill(img: Image, depth: PackedFloat32Array, n: int, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	var x0 := maxi(0, floori(minf(a.x, minf(b.x, c.x))))
	var x1 := mini(n - 1, ceili(maxf(a.x, maxf(b.x, c.x))))
	var y0 := maxi(0, floori(minf(a.y, minf(b.y, c.y))))
	var y1 := mini(n - 1, ceili(maxf(a.y, maxf(b.y, c.y))))
	var area := (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
	if absf(area) < 1e-9:
		return
	for y in range(y0, y1 + 1):
		var py := y + 0.5
		for x in range(x0, x1 + 1):
			var px := x + 0.5
			var w0 := ((b.x - px) * (c.y - py) - (b.y - py) * (c.x - px)) / area
			var w1 := ((c.x - px) * (a.y - py) - (c.y - py) * (a.x - px)) / area
			var w2 := 1.0 - w0 - w1
			if w0 < 0.0 or w1 < 0.0 or w2 < 0.0:
				continue
			var z := a.z * w0 + b.z * w1 + c.z * w2
			var i := y * n + x
			if z <= depth[i]:
				continue
			depth[i] = z
			img.set_pixel(x, y, col)


## Every triangle under `root`, in its frame, with its surface's colour.
static func _collect(root: Node3D, n: Node, tris: PackedVector3Array, colours: PackedColorArray) -> void:
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var xf := Transform3D()
		var cur: Node = mi
		while cur != null and cur != root:
			if cur is Node3D:
				xf = (cur as Node3D).transform * xf
			cur = cur.get_parent()
		for s in mi.mesh.get_surface_count():
			if mi.mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arrays := mi.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var col := colour_of(mi.material_override if mi.material_override != null else mi.get_active_material(s))
			var count := idx.size() if not idx.is_empty() else v.size()
			for k in range(0, count - 2, 3):
				for j in 3:
					tris.append(xf * v[idx[k + j] if not idx.is_empty() else k + j])
				colours.append(col)


## A material's base colour: a StandardMaterial3D's albedo, a room shader's "albedo", else grey.
static func colour_of(m: Material) -> Color:
	if m is BaseMaterial3D:
		return (m as BaseMaterial3D).albedo_color
	if m is ShaderMaterial and (m as ShaderMaterial).get_shader_parameter("albedo") is Color:
		return (m as ShaderMaterial).get_shader_parameter("albedo")
	return Color(0.7, 0.7, 0.7)
