extends RefCounted

## Where things are in an assistant's room (docs/assistant.md, "Rooms"), for room_state and the warnings a change
## comes back with. Cheap tests only: boxes (AABBs in the room frame) and a few rays.
##
##   geometry(base, to_room) -> [{name, aabb, boxes, faces}]     the base room's own parts in the room frame
##   interior(geometry, base_key, base) -> {min, max, open} or {known: false, why}   measured once per base, cached
##   warnings(parts, geometry, interior, eye, screen) -> [{part, kind, warning}]
##
## The interior is measured with six rays from the seated eyes over the room's origin, each to the farthest surface it
## crosses: the shell, past any furniture (the seat under the viewer too), and past a stepped floor to the lowest
## (the cinema's pit). A side with nothing is open (a sky, the void). It is a box: a room that is not one is only
## roughly described.

const EXTENT := 200.0
const PROBE := Vector3(0, 1.2, 0)
## Triangles per mesh tested ray by ray; a bigger mesh is tested as its box.
const FACES_MAX := 20000
## Instances of a MultiMesh kept as boxes; more are one box.
const INSTANCES_MAX := 2000
## Below this angle (degrees, from the eyes) a part is too small or far to make out.
const MIN_ANGLE := 0.5
const TOLERANCE := 0.02
const DIRS := {"floor": Vector3.DOWN, "ceiling": Vector3.UP, "left": Vector3.LEFT, "right": Vector3.RIGHT,
		"front": Vector3.FORWARD, "back": Vector3.BACK}

## base key -> interior, measured when that base was on show.
static var _interiors := {}


static func geometry(base: Node3D, to_room: Transform3D) -> Array:
	var out: Array = []
	if base == null or not base.is_inside_tree():
		return out
	for n in base.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if not g.visible:
			continue
		var xf := to_room * g.global_transform
		var e := {"name": str(g.name), "aabb": xf * g.get_aabb(), "boxes": [], "faces": PackedVector3Array()}
		if g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh != null:
			var mm := (g as MultiMeshInstance3D).multimesh
			var box := mm.mesh.get_aabb() if mm.mesh != null else AABB()
			if mm.get_aabb().size == Vector3.ZERO:
				# The instances' places are not known here (a renderer that keeps no data: headless): listed, but
				# left out of the tests.
				e["unplaced"] = true
			elif mm.instance_count <= INSTANCES_MAX:
				for i in mm.instance_count:
					e["boxes"].append(xf * mm.get_instance_transform(i) * box)
		elif g is MeshInstance3D and (g as MeshInstance3D).mesh != null:
			var faces := (g as MeshInstance3D).mesh.get_faces()
			if faces.size() <= FACES_MAX * 3:
				for i in faces.size():
					faces[i] = xf * faces[i]
				e["faces"] = faces
		if (e["boxes"] as Array).is_empty() and (e["faces"] as PackedVector3Array).is_empty() \
				and not e.has("unplaced"):
			e["boxes"].append(e["aabb"])
		out.append(e)
	return out


## The base's stock parts for room_state: [{name, aabb: {min, max}}] (the caller adds colours).
static func describe(geom: Array) -> Array:
	return geom.map(func(e: Dictionary) -> Dictionary: return {"name": e["name"], "aabb": box_json(e["aabb"])})


static func box_json(b: AABB) -> Dictionary:
	return {"min": _v(b.position), "max": _v(b.end)}


static func _v(p: Vector3) -> Array:
	return [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)]


static func cached(base_key: String) -> Variant:
	return _interiors.get(base_key)


static func interior(geom: Array, base_key: String, base: Node) -> Dictionary:
	if _interiors.has(base_key):
		return _interiors[base_key]
	var out: Dictionary
	var script: Script = base.get_script() if base != null else null
	if script != null and script.resource_path.ends_with("passthrough.gd"):
		out = {"known": false, "why": "the real room shows through the cameras; its walls are not known here"}
	else:
		var lo := Vector3(-EXTENT, 0, -EXTENT)
		var hi := Vector3(EXTENT, EXTENT, EXTENT)
		var open: Array = []
		for side: String in DIRS:
			var hits := _hits(geom, PROBE, DIRS[side])
			if hits.is_empty():
				open.append(side)
				if side == "floor":
					lo.y = -EXTENT
				continue
			var t: float = hits.max()
			var p: Vector3 = PROBE + DIRS[side] * t
			match side:
				"floor": lo.y = p.y
				"ceiling": hi.y = p.y
				"left": lo.x = p.x
				"right": hi.x = p.x
				"front": lo.z = p.z
				"back": hi.z = p.z
		out = {"min": _v(lo), "max": _v(hi), "open": open}
	_interiors[base_key] = out
	return out


## Distances along a ray to every surface it crosses (box faces both ways, triangles), up to EXTENT.
static func _hits(geom: Array, from: Vector3, dir: Vector3) -> Array:
	var out: Array = []
	for e: Dictionary in geom:
		var span := _slab(e["aabb"], from, dir)
		if span.is_empty():
			continue
		var faces: PackedVector3Array = e["faces"]
		if not faces.is_empty():
			for i in range(0, faces.size(), 3):
				var hit: Variant = Geometry3D.ray_intersects_triangle(from, dir, faces[i], faces[i + 1], faces[i + 2])
				if hit != null:
					out.append(((hit as Vector3) - from).length())
		for b: AABB in e["boxes"]:
			for t: float in _slab(b, from, dir):
				out.append(t)
	return out.filter(func(t: float) -> bool: return t > 0.001 and t <= EXTENT)


## Where a ray enters and leaves a box ([t_in, t_out], only those ahead), or [] when it misses.
static func _slab(b: AABB, from: Vector3, dir: Vector3) -> Array:
	var t0 := -INF
	var t1 := INF
	for a in 3:
		if absf(dir[a]) < 1e-9:
			if from[a] < b.position[a] - 1e-6 or from[a] > b.end[a] + 1e-6:
				return []
			continue
		var ta := (b.position[a] - from[a]) / dir[a]
		var tb := (b.end[a] - from[a]) / dir[a]
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
	if t1 < t0 or t1 < 0.0:
		return []
	return [t0, t1].filter(func(t: float) -> bool: return t > 0.0)


## inner lies within outer, give or take tol (negative: well within).
static func _contains(outer: AABB, inner: AABB, tol: float) -> bool:
	for a in 3:
		if inner.position[a] < outer.position[a] - tol or inner.end[a] > outer.end[a] + tol:
			return false
	return true


## Plain-words warnings about the assistant's parts. parts: [{name, aabb}] in the room frame; eye: the seated eyes;
## screen: room_state's screen ({center, size, facing, spherical}).
static func warnings(parts: Array, geom: Array, inside: Dictionary, eye: Vector3, screen: Dictionary) -> Array:
	var out: Array = []
	var centre := Vector3(screen["center"][0], screen["center"][1], screen["center"][2])
	var normal := Vector3(screen["facing"][0], screen["facing"][1], screen["facing"][2])
	var ahead := Vector3(centre.x - eye.x, 0, centre.z - eye.z)
	ahead = ahead.normalized() if ahead.length() > 0.05 else Vector3.FORWARD
	# Stock boxes that do not hold the eyes (a shell around the room holds everything, so it hides nothing).
	var blockers: Array = []
	for e: Dictionary in geom:
		for b: AABB in e["boxes"]:
			if not b.grow(0.001).has_point(eye):
				blockers.append([e["name"], b])
		if (e["boxes"] as Array).is_empty() and not e.has("unplaced") and not (e["aabb"] as AABB).has_point(eye):
			blockers.append([e["name"], e["aabb"]])
	for p: Dictionary in parts:
		var name: String = p["name"]
		var box: AABB = p["aabb"]
		var c := box.get_center()
		if inside.get("min") is Array:
			var lo := Vector3(inside["min"][0], inside["min"][1], inside["min"][2])
			var hi := Vector3(inside["max"][0], inside["max"][1], inside["max"][2])
			var room := AABB(lo, hi - lo)
			if not room.grow(TOLERANCE).intersects(box):
				out.append(_w(name, "outside_room", "outside the room's walls (the room is x %s..%s, y %s..%s, z %s..%s): "
						% [lo.x, hi.x, lo.y, hi.y, lo.z, hi.z] + "hidden behind them"))
			elif not _contains(room, box, TOLERANCE):
				out.append(_w(name, "outside_room", "partly outside the room's walls, floor or ceiling (the room is "
						+ "x %s..%s, y %s..%s, z %s..%s); that part is hidden" % [lo.x, hi.x, lo.y, hi.y, lo.z, hi.z]))
		var inside_of := ""
		for bl: Array in blockers:
			if _contains(bl[1], box, -0.005):
				inside_of = bl[0]
				break
		if inside_of != "":
			out.append(_w(name, "inside_stock_part", "inside the room's %s: hidden in it" % inside_of))
		else:
			for bl: Array in blockers:
				var b: AABB = bl[1]
				if b.has_point(c) or b.intersects(box):
					continue
				if b.intersects_segment(eye, c):
					out.append(_w(name, "behind_stock_part", "behind the room's %s as seen from the seat: hidden, or "
							% bl[0] + "mostly"))
					break
		var all_behind := true
		for i in 8:
			if (box.get_endpoint(i) - eye).dot(ahead) >= 0.0:
				all_behind = false
				break
		if all_behind:
			out.append(_w(name, "behind_viewer", "behind the viewer: seen only by turning round"))
		elif not bool(screen.get("spherical", false)):
			var den := (c - eye).dot(normal)
			if absf(den) > 1e-6:
				var t := (centre - eye).dot(normal) / den
				if t > 0.0 and t < 1.0:
					var hit := eye + (c - eye) * t
					var local := hit - centre
					var right := Vector3.UP.cross(normal).normalized()
					if absf(local.dot(right)) <= float(screen["size"][0]) * 0.5 \
							and absf(local.y) <= float(screen["size"][1]) * 0.5:
						out.append(_w(name, "behind_screen", "behind the screen as seen from the seat: the picture "
								+ "hides it"))
		var d := (c - eye).length()
		var biggest := maxf(box.size.x, maxf(box.size.y, box.size.z))
		var angle := rad_to_deg(2.0 * atan(biggest * 0.5 / maxf(d, 0.01)))
		if angle < MIN_ANGLE:
			out.append(_w(name, "too_small", "too small or far to make out: about %.2f degrees across from the seat "
					% angle + "(%.2f m wide at %.1f m); at least %.1f degrees is needed" % [biggest, d, MIN_ANGLE]))
	return out


static func _w(part: String, kind: String, text: String) -> Dictionary:
	return {"part": part, "kind": kind, "warning": "%s: %s" % [part, text]}
