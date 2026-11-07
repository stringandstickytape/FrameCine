extends RefCounted

## One kind of creature of the life system (scripts/env/systems/life.gd, docs/environments.md "Ambient life"): the
## base of moth.gd, bird.gd, firefly.gd, cat.gd, deer.gd, fish.gd, jelly.gd, whale.gd and plane.gd. A creature builds
## its meshes into the room through the system (life.own), moves them every frame, and answers the system's actions.
## The system keeps every creature out of the viewer's face and out of the sight line to the picture (life.keep()).
##
##   static defaults() -> {count, size, speed, colour, every, max}   the creature's own numbers (the system's 0 or null)
##   build()                     its meshes (one draw: a MultiMesh, or one mesh for a single creature)
##   step(delta)                 a frame; delta already scaled by nothing (speed is the creature's to use)
##   act(action, args) -> bool   pass, scatter, settle, call; false when it has no such action
##   param_changed(name)         a live parameter changed (glow, colour, blink...)
##   positions() -> Array        tests: where each one that shows is (room frame)
##   bounds() -> Array           tests: [centre, radius] of each one that shows

const BODY_SHADER := preload("res://shaders/env_life.gdshader")
const GLOW_SHADER := preload("res://shaders/env_life_glow.gdshader")
## The sight-line check looks through these (screen_frame.gd SEE_THROUGH): life moves; it is not the room's.
const SEE_THROUGH := "env_see_through"
## Floats per MultiMesh instance: a 3 x 4 transform, a colour, custom data.
const STRIDE := 20

## The system (life.gd).
var life: Node
var rng: RandomNumberGenerator
var count := 0
var mm: MultiMesh
var instance: GeometryInstance3D
var material: ShaderMaterial
var _buf := PackedFloat32Array()


static func defaults() -> Dictionary:
	return {}


func build() -> void:
	pass


func step(_delta: float) -> void:
	pass


func act(_action: String, _args: Dictionary) -> bool:
	return false


func param_changed(_param: String) -> void:
	pass


func positions() -> Array:
	return []


## Whether a walker (the cat, the deer, the whale) is in the sight line now (life.gd counts how long, for tests).
func walker_in_view() -> bool:
	return false


func bounds() -> Array:
	var r := radius()
	return positions().map(func(p: Vector3) -> Array: return [p, r])


## About how far the creature reaches from its centre (metres).
func radius() -> float:
	return 0.1


# --- Helpers ----------------------------------------------------------------------------------------------------------

## Where a MultiMesh may draw (its custom AABB, in the room's frame): wide, so it is never culled by its bounds.
const WIDE := AABB(Vector3(-400, -100, -400), Vector3(800, 400, 800))


func random_in(box: AABB) -> Vector3:
	return box.position + Vector3(rng.randf(), rng.randf(), rng.randf()) * box.size


func jitter() -> Vector3:
	return Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))


## Instance i shows while it is among the first count x activity.
func shown(i: int) -> bool:
	return float(i) < float(count) * float(life.params["activity"]) - 0.001


func size() -> float:
	return float(life.params["size"])


func speed() -> float:
	return float(life.params["speed"])


## A fade towards on or off over seconds.
static func fade_to(f: float, on: bool, delta: float, seconds := 1.5) -> float:
	return move_toward(f, 1.0 if on else 0.0, delta / seconds)


## The point at distance d along a path (a polyline), and the path's direction there.
static func along(path: Array[Vector3], d: float) -> Array:
	var left := maxf(d, 0.0)
	for i in path.size() - 1:
		var seg := path[i].distance_to(path[i + 1])
		if left <= seg or i == path.size() - 2:
			var dir := (path[i + 1] - path[i]).normalized()
			return [path[i] + dir * minf(left, seg), dir]
		left -= seg
	return [path[0], Vector3.FORWARD]


## A cue's {"from": [x, y, z]}, or the given point.
static func from_arg(args: Dictionary, otherwise: Vector3) -> Vector3:
	var f: Variant = args.get("from")
	if f is Array and (f as Array).size() == 3:
		return Vector3(float(f[0]), float(f[1]), float(f[2]))
	return otherwise


## A cue's side: -1 from the left, 1 from the right, 0 either.
static func side_arg(args: Dictionary) -> int:
	match str(args.get("side", "")):
		"left":
			return -1
		"right":
			return 1
	return 0


static func path_length(path: Array[Vector3]) -> float:
	var n := 0.0
	for i in path.size() - 1:
		n += path[i].distance_to(path[i + 1])
	return n


# --- Meshes -----------------------------------------------------------------------------------------------------------

## A body material on env_life.gdshader.
func body_material(colour: Color, uniforms := {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = BODY_SHADER
	m.set_shader_parameter("colour", colour)
	for k: String in uniforms:
		m.set_shader_parameter(k, uniforms[k])
	return m


func glow_material(colour: Color, mode: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = GLOW_SHADER
	m.set_shader_parameter("colour", colour)
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("glow", float(life.params["glow"]))
	return m


## n instances of a mesh in one draw, in the room. aabb: where they may be (no culling surprises, no CPU bounds).
func multimesh(mesh: Mesh, n: int, mat: ShaderMaterial, aabb: AABB, node_name: String) -> MultiMeshInstance3D:
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = n
	mm.custom_aabb = aabb
	_buf.resize(n * STRIDE)
	_buf.fill(0.0)
	var mi := MultiMeshInstance3D.new()
	mi.name = node_name
	mi.multimesh = mm
	mi.material_override = mat
	material = mat
	_quiet(mi)
	instance = mi
	life.own(mi)
	return mi


## One creature's mesh in the room (the cat, the deer, the whale): its instance data are uniforms.
func single(mesh: Mesh, mat: ShaderMaterial, node_name: String) -> MeshInstance3D:
	mat.set_shader_parameter("single", true)
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	material = mat
	_quiet(mi)
	instance = mi
	life.own(mi)
	return mi


func _quiet(g: GeometryInstance3D) -> void:
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	g.add_to_group(SEE_THROUGH)


## Instance i: where it is, its tint (alpha: the fade), its custom data (phase, amount, lit, pose).
func put(i: int, xf: Transform3D, tint: Color, custom: Color) -> void:
	var o := i * STRIDE
	var b := xf.basis
	_buf[o] = b.x.x
	_buf[o + 1] = b.y.x
	_buf[o + 2] = b.z.x
	_buf[o + 3] = xf.origin.x
	_buf[o + 4] = b.x.y
	_buf[o + 5] = b.y.y
	_buf[o + 6] = b.z.y
	_buf[o + 7] = xf.origin.y
	_buf[o + 8] = b.x.z
	_buf[o + 9] = b.y.z
	_buf[o + 10] = b.z.z
	_buf[o + 11] = xf.origin.z
	_buf[o + 12] = tint.r
	_buf[o + 13] = tint.g
	_buf[o + 14] = tint.b
	_buf[o + 15] = tint.a
	_buf[o + 16] = custom.r
	_buf[o + 17] = custom.g
	_buf[o + 18] = custom.b
	_buf[o + 19] = custom.a


func flush() -> void:
	mm.buffer = _buf


## A single creature's instance data.
func put_single(xf: Transform3D, tint: Color, custom: Color) -> void:
	(instance as Node3D).transform = xf
	material.set_shader_parameter("single_tint", Vector4(tint.r, tint.g, tint.b, tint.a))
	material.set_shader_parameter("single_custom", Vector4(custom.r, custom.g, custom.b, custom.a))
	instance.visible = tint.a > 0.001


## Facing along dir (its -Z), upright; scaled.
static func facing(at: Vector3, dir: Vector3, scale: float, bank := 0.0) -> Transform3D:
	var d := dir.normalized() if dir.length() > 1e-5 else Vector3.FORWARD
	var up := Vector3.UP if absf(d.dot(Vector3.UP)) < 0.98 else Vector3.BACK
	var b := Basis.looking_at(d, up)
	if bank != 0.0:
		b = b * Basis(Vector3.FORWARD, bank)
	return Transform3D(b.scaled(Vector3.ONE * scale), at)


## A low-poly mesh from triangles with the shader's weights per vertex: Vector4(wing, leg, wave, head).
class Shape:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()

	func tri(a: Vector3, b: Vector3, c: Vector3, wa := Vector4.ZERO, wb := Vector4.ZERO, wc := Vector4.ZERO) -> void:
		var n := (b - a).cross(c - a).normalized()
		for p: Array in [[a, wa], [b, wb], [c, wc]]:
			verts.append(p[0])
			normals.append(n)
			var w: Vector4 = p[1]
			uv.append(Vector2(w.x, w.y))
			uv2.append(Vector2(w.z, w.w))

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, w := Callable()) -> void:
		var ws: Array = [a, b, c, d].map(func(p: Vector3) -> Vector4: return w.call(p) if w.is_valid() else Vector4.ZERO)
		tri(a, b, c, ws[0], ws[1], ws[2])
		tri(a, c, d, ws[0], ws[2], ws[3])

	## A box between lo and hi; w(point) -> its weights.
	func box(lo: Vector3, hi: Vector3, w := Callable()) -> void:
		var p := func(x: int, y: int, z: int) -> Vector3:
			return Vector3(hi.x if x else lo.x, hi.y if y else lo.y, hi.z if z else lo.z)
		quad(p.call(0, 0, 1), p.call(1, 0, 1), p.call(1, 1, 1), p.call(0, 1, 1), w)
		quad(p.call(1, 0, 0), p.call(0, 0, 0), p.call(0, 1, 0), p.call(1, 1, 0), w)
		quad(p.call(0, 0, 0), p.call(0, 0, 1), p.call(0, 1, 1), p.call(0, 1, 0), w)
		quad(p.call(1, 0, 1), p.call(1, 0, 0), p.call(1, 1, 0), p.call(1, 1, 1), w)
		quad(p.call(0, 1, 1), p.call(1, 1, 1), p.call(1, 1, 0), p.call(0, 1, 0), w)
		quad(p.call(0, 0, 0), p.call(1, 0, 0), p.call(1, 0, 1), p.call(0, 0, 1), w)

	## A body of revolution along Z: rings of `sides` points, radii per station [[z, rx, ry, y], ...].
	func loft(stations: Array, sides: int, w := Callable()) -> void:
		var rings: Array = []
		for s: Array in stations:
			var ring := PackedVector3Array()
			for i in sides:
				var a := TAU * float(i) / float(sides)
				ring.append(Vector3(cos(a) * float(s[1]), float(s[3]) + sin(a) * float(s[2]), float(s[0])))
			rings.append(ring)
		for r in range(rings.size() - 1):
			for i in sides:
				var j := (i + 1) % sides
				quad(rings[r][i], rings[r][j], rings[r + 1][j], rings[r + 1][i], w)

	func commit() -> ArrayMesh:
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = verts
		a[Mesh.ARRAY_NORMAL] = normals
		var white := PackedColorArray()
		white.resize(verts.size())
		white.fill(Color.WHITE)
		a[Mesh.ARRAY_COLOR] = white
		a[Mesh.ARRAY_TEX_UV] = uv
		a[Mesh.ARRAY_TEX_UV2] = uv2
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		return m


## A four-legged walker along Z (head at -Z), feet at y 0: body, head, ears, tail and legs as boxes, with the leg,
## wave (tail) and head weights. dims: {length, height, leg, width, neck, head, tail, ears}.
static func quadruped(dims: Dictionary) -> ArrayMesh:
	var s := Shape.new()
	var length := float(dims["length"])
	var leg := float(dims["leg"])
	var width := float(dims["width"])
	var body_h := float(dims["height"]) - leg
	var z0 := -length * 0.5
	var z1 := length * 0.5
	var neck := float(dims.get("neck", 0.0))
	var head := float(dims["head"])
	var tail := float(dims["tail"])
	# The head weight runs from the shoulders (0) to the nose (1).
	var head_w := func(p: Vector3) -> Vector4:
		return Vector4(0, 0, 0, clampf((z0 + length * 0.15 - p.z) / maxf(neck + head, 0.01), 0.0, 1.0))
	s.box(Vector3(-width * 0.5, leg, z0), Vector3(width * 0.5, leg + body_h, z1), head_w)
	# Neck: up and forward from the shoulders.
	var neck_top := leg + body_h + neck * 0.8
	if neck > 0.0:
		s.box(Vector3(-width * 0.22, leg + body_h * 0.4, z0 - neck * 0.5), Vector3(width * 0.22, neck_top,
				z0 + body_h * 0.3), head_w)
	var hy := neck_top if neck > 0.0 else leg + body_h * 0.9
	s.box(Vector3(-head * 0.45, hy - head * 0.35, z0 - neck * 0.5 - head), Vector3(head * 0.45, hy + head * 0.4,
			z0 - neck * 0.5), func(_p: Vector3) -> Vector4: return Vector4(0, 0, 0, 1))
	var ear := float(dims.get("ears", head * 0.35))
	for sx: float in [-1.0, 1.0]:
		var bx := sx * head * 0.3
		var by := hy + head * 0.4
		var bz := z0 - neck * 0.5 - head * 0.55
		var hw := Vector4(0, 0, 0, 1)
		s.tri(Vector3(bx - head * 0.12, by, bz), Vector3(bx + head * 0.12, by, bz), Vector3(bx, by + ear, bz + 0.01),
				hw, hw, hw)
	# Tail: thin, swaying (the wave weight grows along it).
	var tail_w := func(p: Vector3) -> Vector4: return Vector4(0, 0, clampf((p.z - z1) / maxf(tail, 0.01), 0.0, 1.0), 0)
	var ty := leg + body_h * 0.8
	s.box(Vector3(-width * 0.08, ty - width * 0.08, z1), Vector3(width * 0.08, ty + width * 0.06, z1 + tail), tail_w)
	# Legs: the leg weight from the hip (0) to the foot (1).
	var lw := width * 0.22
	for lx: float in [-width * 0.5 + lw * 0.6, width * 0.5 - lw * 0.6]:
		for lz: float in [z0 + lw * 1.2, z1 - lw * 1.2]:
			s.box(Vector3(lx - lw * 0.5, 0.0, lz - lw * 0.5), Vector3(lx + lw * 0.5, leg + body_h * 0.3, lz + lw * 0.5),
					func(p: Vector3) -> Vector4: return Vector4(0, clampf(1.0 - p.y / leg, 0.0, 1.0), 0, 0))
	return s.commit()
