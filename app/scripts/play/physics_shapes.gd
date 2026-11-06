extends RefCounted

## The shapes object physics collides with (scripts/play/object_physics.gd, docs/physics.md). Cheap and simple: Jolt
## (project.godot) steps them on the CPU the headset also decodes video on.
##   the room      room_shapes(base): the room's own collision_shapes() when it has them (environments/cinema.gd:
##                 boxes for the floor, walls, stage, tiers and steps, two a seat; passthrough.gd: the floor), else
##                 shapes from its static meshes (a primitive's exact shape, a mesh's triangles, a MultiMesh's
##                 instances as boxes)
##   the screen    screen_shapes(screen): the film's screen as it shows: flat (a thin box behind the picture), curved
##                 (boxes along the arc), 180, 360 and the fisheyes (a low sphere or cap of triangles round the head)
##   an object     placement_shapes(): a built-in primitive as its exact shape (box, sphere, cylinder; a plane as a
##                 thin box); a model as one convex hull per part (ObjectLibrary.collision(): worked out once, kept)
## A shape is [Shape3D, Transform3D] in the frame of the body it goes on.
##
##   split(basis) -> [rotation, rest]     a node's basis as the rotation the body takes and the rest (its scale)
##   hulls_of(model) -> [PackedVector3Array]   one hull a part, in the model's frame (few points: HULL_POINTS)

## The collision layers: the room and the screen, placed objects (static), moving objects (picked up, thrown).
const LAYER_ROOM := 1
const LAYER_PLACED := 2
const LAYER_MOVING := 4
## Points a part's hull keeps at most (support points in evenly spread directions): Jolt's cost grows with them.
const HULL_POINTS := 48
## A hull thinner than this on an axis (a picture, a card) is given this thickness: a flat hull has no volume.
const FLAT := 0.01
## The fallback leaves out meshes bigger than this (skies, the passthrough shell): nothing is thrown that far.
const FALLBACK_MAX_EXTENT := 120.0
## The flat screen's box: this deep, behind the picture.
const SCREEN_DEPTH := 0.12
## The curved screen: boxes along its arc.
const CURVE_SEGMENTS := 12
## The 180 / 360 sphere's triangles (a low sphere: the picture is 20 m away).
const SPHERE_SEGMENTS := 24
const SPHERE_RINGS := 12


# --- The room ---------------------------------------------------------------------------------------------------

## The base room's shapes in its own frame: its collision_shapes() when it has them, else from its static meshes.
static func room_shapes(base: Node3D) -> Array:
	if base == null:
		return []
	if base.has_method("collision_shapes"):
		return base.collision_shapes()
	return mesh_shapes(base)


## Shapes from every visible mesh under `root` (in root's frame): a BoxMesh, SphereMesh or CylinderMesh as its exact
## shape when the transform keeps it one, a MultiMesh's instances as boxes round the mesh, any other mesh as its
## triangles (both sides collide). Meshes bigger than FALLBACK_MAX_EXTENT are left out. skip: nodes left out with
## everything under them.
static func mesh_shapes(root: Node3D, skip: Array = []) -> Array:
	var out: Array = []
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if not g.is_visible_in_tree() or _under_any(g, skip):
			continue
		var xf := relative(root, g)
		if g is MultiMeshInstance3D:
			var mm := (g as MultiMeshInstance3D).multimesh
			if mm == null or mm.mesh == null:
				continue
			var box_of := mm.mesh.get_aabb()
			if box_of.size.length() > FALLBACK_MAX_EXTENT:
				continue
			var count := mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
			for i in count:
				var ixf := xf * mm.get_instance_transform(i)
				if absf(ixf.basis.determinant()) < 1e-6:
					continue  # folded away (the cinema's occupied seat)
				out.append(_scaled_box(box_of, ixf))
			continue
		if not (g is MeshInstance3D) or (g as MeshInstance3D).mesh == null:
			continue
		var mesh := (g as MeshInstance3D).mesh
		var aabb := xf * mesh.get_aabb()
		if aabb.size.length() > FALLBACK_MAX_EXTENT:
			continue
		var exact := primitive_mesh_shape(mesh, xf)
		if not exact.is_empty():
			out.append(exact)
			continue
		var faces := mesh.get_faces()
		if faces.is_empty():
			continue
		for i in faces.size():
			faces[i] = xf * faces[i]
		var tri := ConcavePolygonShape3D.new()
		tri.backface_collision = true
		tri.set_faces(faces)
		out.append([tri, Transform3D()])
	return out


static func _under_any(n: Node, skip: Array) -> bool:
	for s: Variant in skip:
		if s is Node and is_instance_valid(s) and (n == s or (s as Node).is_ancestor_of(n)):
			return true
	return false


## A BoxMesh, SphereMesh or CylinderMesh under transform `xf` as its exact shape, or [] (another mesh, or a transform
## that would bend it: sheared, or a sphere scaled unevenly).
static func primitive_mesh_shape(mesh: Mesh, xf: Transform3D) -> Array:
	var s := split(xf.basis)
	var rest: Basis = s[1]
	if not is_diagonal(rest):
		return []
	var k := Vector3(rest.x.x, rest.y.y, rest.z.z).abs()
	var rigid := Transform3D(s[0], xf.origin)
	if mesh is BoxMesh:
		var b := BoxShape3D.new()
		b.size = ((mesh as BoxMesh).size * k).max(Vector3.ONE * FLAT)
		return [b, rigid]
	if mesh is SphereMesh and is_equal_approx(k.x, k.y) and is_equal_approx(k.x, k.z) \
			and is_equal_approx((mesh as SphereMesh).height, (mesh as SphereMesh).radius * 2.0):
		var sp := SphereShape3D.new()
		sp.radius = (mesh as SphereMesh).radius * k.x
		return [sp, rigid]
	if mesh is CylinderMesh and is_equal_approx(k.x, k.z) \
			and is_equal_approx((mesh as CylinderMesh).top_radius, (mesh as CylinderMesh).bottom_radius):
		var cy := CylinderShape3D.new()
		cy.radius = (mesh as CylinderMesh).top_radius * k.x
		cy.height = (mesh as CylinderMesh).height * k.y
		return [cy, rigid]
	return []


## A box round `aabb` (a mesh's extent) under xf: its centre and turn, the scale in its size.
static func _scaled_box(aabb: AABB, xf: Transform3D) -> Array:
	var s := split(xf.basis)
	var rest: Basis = s[1]
	var shape := BoxShape3D.new()
	shape.size = (aabb.size * Vector3(rest.x.length(), rest.y.length(), rest.z.length())).max(Vector3.ONE * FLAT)
	return [shape, Transform3D(s[0], xf * aabb.get_center())]


## One box: its centre and size, turned by basis (the rooms' collision_shapes() use it).
static func box(centre: Vector3, size: Vector3, basis := Basis()) -> Array:
	var b := BoxShape3D.new()
	b.size = size.abs().max(Vector3.ONE * FLAT)
	return [b, Transform3D(basis, centre)]


## n's transform in root's frame (n under root).
static func relative(root: Node, n: Node) -> Transform3D:
	var xf := Transform3D()
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


# --- The screen -------------------------------------------------------------------------------------------------

## The film's screen as it shows (world frame): {key, shapes} ({} when it doesn't show). key changes when the shapes
## would: the caller builds them again only then.
static func screen_shapes(screen: Node3D) -> Dictionary:
	if screen == null or not screen.has_method("is_shown") or not screen.is_shown():
		return {}
	var flat_node := screen.get_node_or_null("Flat") as MeshInstance3D
	var sphere_node := screen.get_node_or_null("Sphere") as MeshInstance3D
	var mode: Object = screen.get("mode")
	var flat: bool = mode != null and int(mode.get("projection")) == 0
	if flat and flat_node != null:
		var xf := flat_node.global_transform
		var size: Vector2 = screen.get_flat_size()
		var radius := float(screen.get("curve_radius"))
		var key := "flat %s %s %.3f" % [str(xf), str(size), radius]
		var shapes: Array = []
		var turn := xf.basis.orthonormalized()
		if radius <= 0.0:
			shapes.append(box(xf * Vector3(0, 0, -SCREEN_DEPTH * 0.5), Vector3(size.x, size.y, SCREEN_DEPTH), turn))
		else:
			# The cylinder section (curved_screen.gd build()): its axis upright, the picture's middle at the quad's
			# origin, its edges coming forward (+Z) round a centre `radius` in front.
			var phi := size.x * 0.5 / radius
			for i in CURVE_SEGMENTS:
				var a0 := lerpf(-phi, phi, float(i) / CURVE_SEGMENTS)
				var a1 := lerpf(-phi, phi, float(i + 1) / CURVE_SEGMENTS)
				var am := (a0 + a1) * 0.5
				var w := 2.0 * radius * sin((a1 - a0) * 0.5) * 1.02
				var local_basis := Basis(Vector3.UP, -am)
				var on := Vector3(radius * sin(am), 0.0, radius * (1.0 - cos(am)))
				var centre := on + local_basis * Vector3(0, 0, -SCREEN_DEPTH * 0.5)
				shapes.append(box(xf * centre, Vector3(w, size.y, SCREEN_DEPTH), turn * local_basis))
		return {"key": key, "shapes": shapes}
	if sphere_node == null or sphere_node.mesh == null or not sphere_node.visible:
		return {}
	var sxf := sphere_node.global_transform
	var sphere_key := "sphere %d %.1f %s" % [int(mode.get("projection")) if mode != null else -1,
			float(mode.get("fisheye_fov")) if mode != null else 0.0, str(sxf.origin.snapped(Vector3.ONE * 0.05))]
	return {"key": sphere_key, "shapes": [sphere_shell(sphere_node.mesh, sxf)]}


## The picture's sphere or cap as a low shell of triangles (world frame): the mesh's own extent says how much of the
## sphere it covers (a 180 the front half, a 360 all of it), from a low sphere of the same radius.
static func sphere_shell(mesh: Mesh, xf: Transform3D) -> Array:
	var aabb := mesh.get_aabb()
	var radius := maxf(maxf(aabb.end.x, -aabb.position.x), maxf(maxf(aabb.end.y, -aabb.position.y),
			maxf(aabb.end.z, -aabb.position.z)))
	var low := SphereMesh.new()
	low.radius = radius
	low.height = radius * 2.0
	low.radial_segments = SPHERE_SEGMENTS
	low.rings = SPHERE_RINGS
	var faces := low.get_faces()
	var keep := PackedVector3Array()
	var grown := aabb.grow(radius * 0.1)
	for i in range(0, faces.size(), 3):
		var mid := (faces[i] + faces[i + 1] + faces[i + 2]) / 3.0
		if grown.has_point(mid):
			keep.append_array([xf * faces[i], xf * faces[i + 1], xf * faces[i + 2]])
	var tri := ConcavePolygonShape3D.new()
	tri.backface_collision = true
	tri.set_faces(keep)
	return [tri, Transform3D()]


# --- Objects ----------------------------------------------------------------------------------------------------

## A placed object's shapes in its body's frame (the node's rotation and place; `rest`: the rest of its basis, its
## scale, from split()). kind: what the placement is built as (RoomSchema.kind_of); form: its build form (the size);
## hulls: a model's part hulls in the model's frame, model_xf the model under the node. [] for what has no shape.
static func placement_shapes(kind: String, form: Dictionary, rest: Basis, hulls: Array = [],
		model_xf := Transform3D()) -> Array:
	var size: Array = form.get("size", []) if form.get("size") is Array else []
	var diag := is_diagonal(rest)
	var k := Vector3(rest.x.x, rest.y.y, rest.z.z).abs()
	match kind:
		"box":
			var bs := Vector3(float(size[0]), float(size[1]), float(size[2])) if size.size() == 3 else Vector3.ONE
			if diag:
				return [box(Vector3.ZERO, bs * k)]
			return [_hull_shape(_scaled_points(_box_corners(bs), rest))]
		"plane":
			var ps := Vector3(float(size[0]) if size.size() > 0 else 1.0, FLAT,
					float(size[1]) if size.size() > 1 else 1.0)
			if diag:
				return [box(Vector3.ZERO, ps * k)]
			return [_hull_shape(_scaled_points(_box_corners(ps), rest))]
		"sphere":
			var d := float(size[0]) if size.size() > 0 else 1.0
			if diag and is_equal_approx(k.x, k.y) and is_equal_approx(k.x, k.z):
				var sp := SphereShape3D.new()
				sp.radius = d * 0.5 * k.x
				return [[sp, Transform3D()]]
			var m := SphereMesh.new()
			m.radius = d * 0.5
			m.height = d
			m.radial_segments = 12
			m.rings = 6
			return [_hull_shape(_scaled_points(m.get_faces(), rest))]
		"cylinder":
			var cd := float(size[0]) if size.size() > 0 else 1.0
			var ch := float(size[1]) if size.size() > 1 else 1.0
			if diag and is_equal_approx(k.x, k.z):
				var cy := CylinderShape3D.new()
				cy.radius = cd * 0.5 * k.x
				cy.height = ch * k.y
				return [[cy, Transform3D()]]
			var cm := CylinderMesh.new()
			cm.top_radius = cd * 0.5
			cm.bottom_radius = cd * 0.5
			cm.height = ch
			cm.radial_segments = 16
			cm.rings = 1
			return [_hull_shape(_scaled_points(cm.get_faces(), rest))]
		"model":
			var out: Array = []
			for h: Variant in hulls:
				var pts := PackedVector3Array()
				for p: Vector3 in (h as PackedVector3Array):
					pts.append(rest * (model_xf * p))
				if pts.size() >= 3:
					out.append(_hull_shape(pts))
			return out
	return []


static func _box_corners(s: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	for x: float in [-0.5, 0.5]:
		for y: float in [-0.5, 0.5]:
			for z: float in [-0.5, 0.5]:
				out.append(Vector3(x, y, z) * s)
	return out


static func _scaled_points(points: PackedVector3Array, rest: Basis) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in points:
		out.append(rest * p)
	return reduce_hull(out)


static func _hull_shape(points: PackedVector3Array) -> Array:
	var c := ConvexPolygonShape3D.new()
	c.points = thicken(points)
	return [c, Transform3D()]


## One hull a part (each MeshInstance3D under model), in model's frame: the engine's hull of its vertices, kept to
## HULL_POINTS support points and given FLAT thickness where it is flat.
static func hulls_of(model: Node3D) -> Array:
	var out: Array = []
	if model == null:
		return out
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var shape := mi.mesh.create_convex_shape(true, false)
		if shape == null or shape.points.size() < 3:
			continue
		var xf := relative(model, mi)
		var pts := PackedVector3Array()
		for p in shape.points:
			pts.append(xf * p)
		out.append(thicken(reduce_hull(pts)))
	return out


## At most n points of the hull of `points`: the farthest point in each of n directions spread evenly over the sphere
## (a hull's corners stay; a round one keeps its shape). Fewer points than n come back as they are.
static func reduce_hull(points: PackedVector3Array, n := HULL_POINTS) -> PackedVector3Array:
	if points.size() <= n:
		return points
	var c := Vector3.ZERO
	for p in points:
		c += p
	c /= points.size()
	var out := PackedVector3Array()
	var golden := PI * (3.0 - sqrt(5.0))
	for i in n:
		var y := 1.0 - 2.0 * (float(i) + 0.5) / n
		var r := sqrt(maxf(1.0 - y * y, 0.0))
		var d := Vector3(cos(golden * i) * r, y, sin(golden * i) * r)
		var best := 0
		var best_dot := -INF
		for j in points.size():
			var k := (points[j] - c).dot(d)
			if k > best_dot:
				best_dot = k
				best = j
		if not out.has(points[best]):
			out.append(points[best])
	return out


## A flat point set (a picture, a card) made FLAT thick on its thin axes, so its hull has a volume.
static func thicken(points: PackedVector3Array) -> PackedVector3Array:
	if points.is_empty():
		return points
	var extent := AABB(points[0], Vector3.ZERO)
	for p in points:
		extent = extent.expand(p)
	var out := points
	for axis in 3:
		if extent.size[axis] < FLAT:
			var off := Vector3.ZERO
			off[axis] = FLAT * 0.5
			var both := PackedVector3Array()
			for p in out:
				both.append(p - off)
				both.append(p + off)
			out = both
	return out


# --- Bases ------------------------------------------------------------------------------------------------------

## A basis as [its rotation (orthonormal, no mirror), the rest]: basis = rotation * rest. A body takes the rotation;
## the rest (a scale) goes into its shapes.
static func split(basis: Basis) -> Array:
	var q := basis.orthonormalized()
	if q.determinant() < 0.0:
		q = q * Basis.from_scale(Vector3(-1, 1, 1))
	return [q, q.transposed() * basis]


static func is_diagonal(b: Basis, eps := 1e-4) -> bool:
	return absf(b.x.y) < eps and absf(b.x.z) < eps and absf(b.y.x) < eps and absf(b.y.z) < eps \
			and absf(b.z.x) < eps and absf(b.z.y) < eps
