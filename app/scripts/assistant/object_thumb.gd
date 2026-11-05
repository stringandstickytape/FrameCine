extends RefCounted

## A library object's thumbnail (object_library.gd), drawn in the app without the GPU: the model's triangles seen from
## the front, a little from above and the right, in its parts' own colours (a textured part's colour texture, read from
## a small copy) with simple shading, on a clear background.
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
## A colour texture is read from a copy at most this big (the thumbnail is 128 px).
const TEXTURE_SIDE := 128


static func render(node: Node3D, size := 128) -> Image:
	var tris := PackedVector3Array()
	var colours := PackedColorArray()
	var uvs := PackedVector2Array()
	var tex_of := PackedInt32Array()
	var textures: Array[Image] = []
	_collect(node, node, tris, colours, uvs, tex_of, textures)
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
		var tex: Image = textures[tex_of[t]] if tex_of[t] >= 0 else null
		if tex == null:
			_fill(img, depth, n, pa, pb, pc, col)
		else:
			_fill(img, depth, n, pa, pb, pc, col, tex, uvs[t * 3], uvs[t * 3 + 1], uvs[t * 3 + 2])
	img.resize(size, size, Image.INTERPOLATE_BILINEAR)
	return img


static func _px(p: Vector3, mid: Vector3, scale: float, n: int) -> Vector3:
	return Vector3((p.x - mid.x) * scale + n * 0.5, (mid.y - p.y) * scale + n * 0.5, p.z)


## One triangle into the picture, nearer than what is there (z towards the eye is larger).
## With a texture, each pixel takes the texture at its UV (the view has no perspective: plain barycentric), times col.
static func _fill(img: Image, depth: PackedFloat32Array, n: int, a: Vector3, b: Vector3, c: Vector3, col: Color,
		tex: Image = null, ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO) -> void:
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
			if tex == null:
				img.set_pixel(x, y, col)
			else:
				var uv := ua * w0 + ub * w1 + uc * w2
				var tx := posmod(floori(uv.x * tex.get_width()), tex.get_width())
				var ty := posmod(floori(uv.y * tex.get_height()), tex.get_height())
				var tc := tex.get_pixel(tx, ty)
				img.set_pixel(x, y, Color(tc.r * col.r, tc.g * col.g, tc.b * col.b, 1.0))


## Every triangle under `root`, in its frame, with its surface's colour, its UVs and its texture (an index into
## textures, -1 none).
static func _collect(root: Node3D, n: Node, tris: PackedVector3Array, colours: PackedColorArray,
		uvs: PackedVector2Array, tex_of: PackedInt32Array, textures: Array[Image]) -> void:
	var seen := {}
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
			var mat := mi.material_override if mi.material_override != null else mi.get_active_material(s)
			var col := colour_of(mat)
			var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null 					else PackedVector2Array()
			var ti := -1
			var tex := texture_of(mat)
			if tex != null and uv.size() == v.size():
				var key := tex.get_rid()
				if not seen.has(key):
					var small := _small(tex)
					seen[key] = textures.size() if small != null else -1
					if small != null:
						textures.append(small)
				ti = seen[key]
			var count := idx.size() if not idx.is_empty() else v.size()
			for k in range(0, count - 2, 3):
				for j in 3:
					var vi: int = idx[k + j] if not idx.is_empty() else k + j
					tris.append(xf * v[vi])
					uvs.append(uv[vi] if ti >= 0 else Vector2.ZERO)
				colours.append(col)
				tex_of.append(ti)


## A material's colour texture: a StandardMaterial3D's albedo texture, a room shader's "albedo_texture" when it uses
## it, else null.
static func texture_of(m: Material) -> Texture2D:
	if m is BaseMaterial3D:
		return (m as BaseMaterial3D).albedo_texture
	if m is ShaderMaterial:
		var sm := m as ShaderMaterial
		var t: Variant = sm.get_shader_parameter("albedo_texture")
		if t is Texture2D and sm.get_shader_parameter("use_texture") != false:
			return t
	return null


## A texture's picture made small and plain (RGBA8), or null.
static func _small(tex: Texture2D) -> Image:
	var src := tex.get_image()
	if src == null or src.is_empty():
		return null
	var img := src.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBA8)
	var side := maxi(img.get_width(), img.get_height())
	if side > TEXTURE_SIDE:
		var k := float(TEXTURE_SIDE) / side
		img.resize(maxi(1, roundi(img.get_width() * k)), maxi(1, roundi(img.get_height() * k)),
				Image.INTERPOLATE_BILINEAR)
	return img


## A material's base colour: a StandardMaterial3D's albedo, a room shader's "albedo", else grey.
static func colour_of(m: Material) -> Color:
	if m is BaseMaterial3D:
		return (m as BaseMaterial3D).albedo_color
	if m is ShaderMaterial and (m as ShaderMaterial).get_shader_parameter("albedo") is Color:
		return (m as ShaderMaterial).get_shader_parameter("albedo")
	return Color(0.7, 0.7, 0.7)
