extends RefCounted

## An SVG drawing made solid, in the app (no outside tools): the object library's SVG import (object_library.gd,
## docs/assistant.md "Objects"). What it reads:
##   - path data: M L H V C S Q T A Z, absolute and relative, implicit repeats, arc flags without separators; rect
##     (rounded too), circle, ellipse, polygon and polyline as paths
##   - transforms on paths and groups (matrix, translate, scale, rotate, skewX, skewY), the root's viewBox
##   - fill colours (#rgb, #rrggbb, rgb(), names, currentColor), from attributes, a <style> block's .class and #id rules
##     and style=""; fill-rule nonzero and evenodd; display none and visibility hidden
## What it doesn't: clip paths and masks are ignored; gradients and patterns become one flat colour (the gradient's
## first stop) and pictures and text are left out, each with a warning.
##
## Curves are flattened to within TOLERANCE at the model's size. Each filled shape's outlines are sorted by its fill
## rule into outer edges and holes (a sample either side of each outline's longest edge), its faces cut by the holes
## into pieces without holes (vertical cuts through each hole, the engine's polygon clipping) and triangulated
## (Geometry2D), and it is extruded to `depth` with a small chamfer on both edges. UVs: the front and back planar over
## the whole drawing (a picture lies on the front as on the drawing), the sides wrapped round each outline. Shapes later
## in the drawing stand a hair further forward, so overlapping colours never fight.
##
## Each top-level element of the drawing (a path, or a group with everything in it) is one part: a MeshInstance3D
## named by its id when it has one, else part_1, part_2, ...; options.part_names renames them in order, and parts
## given the same name are joined. The front faces +Z, the back is at z = 0, the drawing centred on x and y.
##
##   build(svg_text, {width, depth, bevel, part_names}) -> {node, parts, warnings, size, triangles} or {error}

const DEFAULT_WIDTH := 0.4
const DEFAULT_DEPTH := 0.02
## Curves are flattened to within this, in metres at the model's size.
const TOLERANCE := 0.0004
const MAX_POINTS := 200000
const KAPPA := 0.5522847498
## Elements whose content is never drawn (definitions, clip paths, masks, ...).
const SKIP: Array[String] = ["defs", "clipPath", "mask", "symbol", "pattern", "marker", "linearGradient",
		"radialGradient", "style", "title", "desc", "metadata", "filter", "foreignObject"]
## Two side faces meet smoothly when they turn by less than this (degrees); more is a hard edge.
const SMOOTH_DEG := 40.0


static func build(svg: String, options := {}) -> Dictionary:
	var width := float(options.get("width", DEFAULT_WIDTH))
	var depth := float(options.get("depth", DEFAULT_DEPTH))
	if not (width > 0.0 and width <= 20.0) or not (depth > 0.0 and depth <= 2.0):
		return {"error": "width 0..20 m and depth 0..2 m"}
	var r := Reader.new()
	var err := r.read(svg)
	if err != "":
		return {"error": err}
	if r.shapes.is_empty():
		return {"error": "nothing to extrude: no filled path or shape (%s)" % ("; ".join(r.warnings) if not
				r.warnings.is_empty() else "the drawing is empty")}
	# The drawing's extent (curves coarsely flattened), for the size and the tolerance.
	var lo := Vector2.INF
	var hi := -Vector2.INF
	for s: Dictionary in r.shapes:
		for sub: Dictionary in s["subpaths"]:
			for p: Vector2 in _flatten(sub, INF):
				lo = lo.min(p)
				hi = hi.max(p)
	if hi.x - lo.x <= 0.0 or hi.y - lo.y <= 0.0:
		return {"error": "the drawing has no area"}
	var k := width / (hi.x - lo.x)
	var mid := (lo + hi) * 0.5
	var tol := TOLERANCE / k
	var height := (hi.y - lo.y) * k
	var box := Rect2(Vector2(-width * 0.5, -height * 0.5), Vector2(width, height))
	var bevel := float(options.get("bevel", -1.0))
	if bevel < 0.0:
		bevel = minf(depth * 0.08, width * 0.002)
	bevel = clampf(bevel, 0.0, depth * 0.4)
	var step := minf(0.0005, depth * 0.25 / maxf(r.shapes.size(), 1))
	var warnings: Array = r.warnings.duplicate()
	# The parts: top-level elements in order, named by id or part_N, renamed by part_names, same names joined.
	var tops: Array = []
	for s: Dictionary in r.shapes:
		if not (s["top"] in tops):
			tops.append(s["top"])
	var names_given: Array = options.get("part_names", []) if options.get("part_names") is Array else []
	var part_of := {}
	var order: Array = []
	for i in tops.size():
		var name := str(r.top_ids.get(tops[i], ""))
		name = _plain(name) if _plain(name) != "" else "part_%d" % (i + 1)
		if i < names_given.size() and _plain(str(names_given[i])) != "":
			name = _plain(str(names_given[i]))
		part_of[tops[i]] = name
		if not (name in order):
			order.append(name)
	# {part name: {colour html: surface arrays}}
	var surfaces := {}
	var points := 0
	var dropped := 0
	for i in r.shapes.size():
		var s: Dictionary = r.shapes[i]
		var contours: Array = []
		for sub: Dictionary in s["subpaths"]:
			var flat := _flatten(sub, tol)
			var c := PackedVector2Array()
			for p: Vector2 in flat:
				var q := Vector2((p.x - mid.x) * k, (mid.y - p.y) * k)
				if c.is_empty() or q.distance_squared_to(c[c.size() - 1]) > 1e-14:
					c.append(q)
			if c.size() > 2 and c[0].distance_squared_to(c[c.size() - 1]) <= 1e-14:
				c.remove_at(c.size() - 1)
			if c.size() >= 3:
				contours.append(c)
				points += c.size()
		if points > MAX_POINTS:
			return {"error": "the drawing has over %d points once its curves are flattened; simplify it" % MAX_POINTS}
		var part: String = part_of[s["top"]]
		var key: String = (s["color"] as Color).to_html(false)
		var by_colour: Dictionary = surfaces.get_or_add(part, {})
		if not by_colour.has(key):
			# Plain arrays while they grow (a packed array taken out of a dictionary is a copy).
			by_colour[key] = {"color": s["color"], "v": [], "n": [], "uv": []}
		var front := depth + step * i
		for region: Dictionary in _regions(contours, bool(s["evenodd"])):
			if not _solid(by_colour[key], region, 0.0, front, bevel, box):
				dropped += 1
	if dropped > 0:
		warnings.append("%d outline%s crossing themselves could not be filled and were left out" % [dropped,
				"" if dropped == 1 else "s"])
	var root := Node3D.new()
	root.name = "SvgObject"
	var triangles := 0
	var parts: Array = []
	for name: String in order:
		if not surfaces.has(name):
			continue
		var mesh := ArrayMesh.new()
		mesh.resource_name = name
		for key: String in surfaces[name]:
			var a: Dictionary = surfaces[name][key]
			if (a["v"] as Array).is_empty():
				continue
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(a["v"])
			arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(a["n"])
			arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(a["uv"])
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var mat := StandardMaterial3D.new()
			mat.albedo_color = a["color"]
			mat.resource_name = "%s %s" % [name, key]
			mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
			triangles += (a["v"] as Array).size() / 3
		if mesh.get_surface_count() == 0:
			continue
		var mi := MeshInstance3D.new()
		mi.name = name
		mi.mesh = mesh
		root.add_child(mi)
		parts.append(name)
	if parts.is_empty():
		root.free()
		return {"error": "nothing to extrude: every shape was empty or crossed itself"}
	return {"node": root, "parts": parts, "warnings": warnings, "size": [width, height, depth + step *
			(r.shapes.size() - 1)], "triangles": triangles}


## A name made plain: letters, digits, space, - and _ (anything else _), at most 40.
static func _plain(text: String) -> String:
	var out := ""
	for c in text.strip_edges():
		out += c if c.is_valid_identifier() or c.is_valid_int() or c in " -_" else "_"
	return out.strip_edges().left(40)


# --- Curves --------------------------------------------------------------------------------------------------------

## A subpath ({start, segs: [[p] line or [c1, c2, p] cubic]}) as points; tol INF: a coarse pass (8 steps a curve).
static func _flatten(sub: Dictionary, tol: float) -> PackedVector2Array:
	var out := PackedVector2Array([sub["start"]])
	var cur: Vector2 = sub["start"]
	for seg: Array in sub["segs"]:
		if seg.size() == 1:
			out.append(seg[0])
		elif is_inf(tol):
			for i in range(1, 9):
				out.append(_cubic(cur, seg[0], seg[1], seg[2], i / 8.0))
		else:
			_subdivide(cur, seg[0], seg[1], seg[2], tol, 0, out)
		cur = seg[seg.size() - 1]
	return out


static func _cubic(p0: Vector2, c1: Vector2, c2: Vector2, p1: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return p0 * (u * u * u) + c1 * (3.0 * u * u * t) + c2 * (3.0 * u * t * t) + p1 * (t * t * t)


## Splits the cubic in half until its control points lie within tol of its chord; appends the end points.
static func _subdivide(p0: Vector2, c1: Vector2, c2: Vector2, p1: Vector2, tol: float, depth: int,
		out: PackedVector2Array) -> void:
	var chord := p1 - p0
	var len := chord.length()
	var d1: float
	var d2: float
	if len < 1e-12:
		d1 = p0.distance_to(c1)
		d2 = p0.distance_to(c2)
	else:
		d1 = absf(chord.cross(c1 - p0)) / len
		d2 = absf(chord.cross(c2 - p0)) / len
	if depth >= 12 or maxf(d1, d2) <= tol:
		out.append(p1)
		return
	var a := (p0 + c1) * 0.5
	var b := (c1 + c2) * 0.5
	var c := (c2 + p1) * 0.5
	var ab := (a + b) * 0.5
	var bc := (b + c) * 0.5
	var m := (ab + bc) * 0.5
	_subdivide(p0, a, ab, m, tol, depth + 1, out)
	_subdivide(m, bc, c, p1, tol, depth + 1, out)


# --- Fill rule: outer edges and holes --------------------------------------------------------------------------------

## The filled regions of one shape's outlines under its fill rule: [{outer (counter-clockwise), holes (clockwise)}].
## Each outline is tested just inside and just outside its longest edge: filled inside and empty outside, it is an outer
## edge; the other way round, a hole's; the same both sides (an edge inside a filled area), it bounds nothing.
static func _regions(contours: Array, evenodd: bool) -> Array:
	var outers: Array = []
	var holes: Array = []
	for c: PackedVector2Array in contours:
		var area := _area(c)
		if absf(area) < 1e-12:
			continue
		var best := 0
		var best_len := -1.0
		for i in c.size():
			var l := c[i].distance_squared_to(c[(i + 1) % c.size()])
			if l > best_len:
				best_len = l
				best = i
		var a := c[best]
		var b := c[(best + 1) % c.size()]
		var e := (b - a).normalized()
		var left := Vector2(-e.y, e.x)
		var eps := maxf(sqrt(best_len) * 1e-3, 1e-6)
		var mid := (a + b) * 0.5
		var on_left := _filled(mid + left * eps, contours, evenodd)
		var on_right := _filled(mid - left * eps, contours, evenodd)
		if on_left == on_right:
			continue
		# Counter-clockwise (positive area): its inside is on the left of each edge.
		var ccw := c if area > 0.0 else _reversed(c)
		var inside_filled := on_left if area > 0.0 else on_right
		var probe := mid + (left if area > 0.0 else -left) * eps
		if inside_filled:
			outers.append({"outer": ccw, "area": absf(area), "holes": []})
		else:
			holes.append({"poly": _reversed(ccw), "probe": probe})
	outers.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["area"]) < float(y["area"]))
	for h: Dictionary in holes:
		# The smallest outer edge round it.
		for o: Dictionary in outers:
			if Geometry2D.is_point_in_polygon(h["probe"], o["outer"]):
				(o["holes"] as Array).append(h["poly"])
				break
	return outers


static func _filled(p: Vector2, contours: Array, evenodd: bool) -> bool:
	var wn := 0
	for c: PackedVector2Array in contours:
		wn += _winding(p, c)
	return (absi(wn) % 2 == 1) if evenodd else wn != 0


## How many times the outline goes round p (counter-clockwise positive).
static func _winding(p: Vector2, c: PackedVector2Array) -> int:
	var wn := 0
	var n := c.size()
	for i in n:
		var a := c[i]
		var b := c[(i + 1) % n]
		var side := (b.x - a.x) * (p.y - a.y) - (p.x - a.x) * (b.y - a.y)
		if a.y <= p.y:
			if b.y > p.y and side > 0.0:
				wn += 1
		elif b.y <= p.y and side < 0.0:
			wn -= 1
	return wn


## Signed area: positive counter-clockwise (x right, y up).
static func _area(c: PackedVector2Array) -> float:
	var s := 0.0
	for i in c.size():
		var a := c[i]
		var b := c[(i + 1) % c.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5


static func _reversed(c: PackedVector2Array) -> PackedVector2Array:
	var out := c.duplicate()
	out.reverse()
	return out


## A region's face as triangles (3 points each, any winding). Holes: the outer cut into slabs by a vertical line
## through each hole's middle, each slab clipped by the holes: pieces without holes, which triangulate.
static func _face(outer: PackedVector2Array, holes: Array) -> PackedVector2Array:
	var pieces: Array = [outer]
	if not holes.is_empty():
		var lo := Vector2.INF
		var hi := -Vector2.INF
		for p: Vector2 in outer:
			lo = lo.min(p)
			hi = hi.max(p)
		var cuts: Array = [lo.x - 1.0, hi.x + 1.0]
		for h: PackedVector2Array in holes:
			var hx := Vector2(INF, -INF)
			for p: Vector2 in h:
				hx = Vector2(minf(hx.x, p.x), maxf(hx.y, p.y))
			# A hair off the middle, so the cut seldom runs through a vertex.
			cuts.append((hx.x + hx.y) * 0.5 + (hx.y - hx.x) * 0.0173)
		cuts.sort()
		pieces = []
		for i in cuts.size() - 1:
			if cuts[i + 1] - cuts[i] < 1e-9:
				continue
			var slab_box := PackedVector2Array([Vector2(cuts[i], lo.y - 1.0), Vector2(cuts[i + 1], lo.y - 1.0),
					Vector2(cuts[i + 1], hi.y + 1.0), Vector2(cuts[i], hi.y + 1.0)])
			var slab: Array = Geometry2D.intersect_polygons(outer, slab_box)
			for h: PackedVector2Array in holes:
				var next: Array = []
				for piece: PackedVector2Array in slab:
					next.append_array(Geometry2D.clip_polygons(piece, h))
				slab = next
			pieces.append_array(slab)
	var out := PackedVector2Array()
	for piece: PackedVector2Array in pieces:
		if _area(piece) <= 0.0:
			continue  # a hole left in a piece: not expected once every hole is cut
		var idx := Geometry2D.triangulate_polygon(piece)
		if idx.is_empty():
			for convex: PackedVector2Array in Geometry2D.decompose_polygon_in_convex(piece):
				for t in range(1, convex.size() - 1):
					out.append_array([convex[0], convex[t], convex[t + 1]])
			continue
		for i in idx:
			out.append(piece[i])
	return out


# --- The solid ------------------------------------------------------------------------------------------------------

## One region extruded from z0 (back) to z1 (front), chamfered by bevel, into a surface's arrays. False when its
## face could not be triangulated (an outline crossing itself).
static func _solid(s: Dictionary, region: Dictionary, z0: float, z1: float, bevel: float, box: Rect2) -> bool:
	var rings: Array = [region["outer"]]
	rings.append_array(region["holes"])
	# The chamfer, kept small next to each outline; none where insetting would turn an outline inside out.
	var b := bevel
	for c: PackedVector2Array in rings:
		var lo := Vector2.INF
		var hi := -Vector2.INF
		for p: Vector2 in c:
			lo = lo.min(p)
			hi = hi.max(p)
		b = minf(b, 0.15 * minf(hi.x - lo.x, hi.y - lo.y))
	var insets: Array = []
	for c: PackedVector2Array in rings:
		var inset := _inset(c, b)
		if b > 0.0 and (signf(_area(inset)) != signf(_area(c)) or absf(_area(inset)) < absf(_area(c)) * 0.3):
			b = 0.0
			break
		insets.append(inset)
	if b <= 0.0:
		insets = rings.duplicate()
	var front := _face(insets[0], insets.slice(1))
	if front.is_empty():
		return false
	for i in range(0, front.size(), 3):
		var tri := [front[i], front[i + 1], front[i + 2]]
		_tri(s, [_v3(tri[0], z1), _v3(tri[1], z1), _v3(tri[2], z1)], [Vector3.BACK, Vector3.BACK, Vector3.BACK],
				[_uv(tri[0], box, false), _uv(tri[1], box, false), _uv(tri[2], box, false)], Vector3.BACK)
		_tri(s, [_v3(tri[0], z0), _v3(tri[1], z0), _v3(tri[2], z0)], [Vector3.FORWARD, Vector3.FORWARD,
				Vector3.FORWARD], [_uv(tri[0], box, true), _uv(tri[1], box, true), _uv(tri[2], box, true)],
				Vector3.FORWARD)
	for j in rings.size():
		_walls(s, rings[j], insets[j], z0, z1, b)
	return true


static func _v3(p: Vector2, z: float) -> Vector3:
	return Vector3(p.x, p.y, z)


## Planar over the whole drawing: (0, 0) its top left; the back mirrored, so a picture reads right from behind.
static func _uv(p: Vector2, box: Rect2, back: bool) -> Vector2:
	var u := (p.x - box.position.x) / box.size.x
	return Vector2(1.0 - u if back else u, (box.end.y - p.y) / box.size.y)


## An outline moved into the filled side (the left of each edge) by d, at the corners along the mitre (limited at
## sharp ones).
static func _inset(c: PackedVector2Array, d: float) -> PackedVector2Array:
	if d <= 0.0:
		return c
	var n := c.size()
	var out := PackedVector2Array()
	out.resize(n)
	for i in n:
		var a := _out_normal(c[(i - 1 + n) % n], c[i])
		var b := _out_normal(c[i], c[(i + 1) % n])
		var m := -(a + b)
		m = m.normalized() if m.length() > 1e-6 else -b
		out[i] = c[i] + m * (d / maxf(m.dot(-b), 0.35))
	return out


## The outward normal of the edge a -> b (the filled side is on its left).
static func _out_normal(a: Vector2, b: Vector2) -> Vector2:
	var e := (b - a).normalized()
	return Vector2(e.y, -e.x)


## The sides of one outline: front chamfer (inset at z1 to the outline at z1 - b), side, back chamfer; normals smooth
## round gentle turns and split at corners; u along the outline, v down the depth.
static func _walls(s: Dictionary, c: PackedVector2Array, inset: PackedVector2Array, z0: float, z1: float,
		b: float) -> void:
	var n := c.size()
	var edge_n: Array[Vector2] = []
	var cum: Array[float] = [0.0]
	for i in n:
		edge_n.append(_out_normal(c[i], c[(i + 1) % n]))
		cum.append(cum[i] + c[i].distance_to(c[(i + 1) % n]))
	var perimeter: float = maxf(cum[n], 1e-9)
	var smooth_cos := cos(deg_to_rad(SMOOTH_DEG))
	# Each band: [outline at its front, z there, outline at its back, z there, how far the normal leans to +Z].
	var bands: Array = []
	if b > 0.0:
		bands.append([inset, z1, c, z1 - b, 1.0])
		bands.append([c, z1 - b, c, z0 + b, 0.0])
		bands.append([c, z0 + b, inset, z0, -1.0])
	else:
		bands.append([c, z1, c, z0, 0.0])
	var depth := maxf(z1 - z0, 1e-9)
	for i in n:
		var j := (i + 1) % n
		var en := edge_n[i]
		var prev := edge_n[(i - 1 + n) % n]
		var next := edge_n[j]
		var n_start := (prev + en).normalized() if prev.dot(en) > smooth_cos else en
		var n_end := (en + next).normalized() if en.dot(next) > smooth_cos else en
		var u0: float = cum[i] / perimeter
		var u1: float = cum[i + 1] / perimeter
		for band: Array in bands:
			var top: PackedVector2Array = band[0]
			var bottom: PackedVector2Array = band[2]
			var za: float = band[1]
			var zb: float = band[3]
			var lean: float = band[4]
			var ns := Vector3(n_start.x, n_start.y, lean).normalized()
			var ne := Vector3(n_end.x, n_end.y, lean).normalized()
			var flat := Vector3(en.x, en.y, lean).normalized()
			var p := [_v3(top[i], za), _v3(top[j], za), _v3(bottom[j], zb), _v3(bottom[i], zb)]
			var uv := [Vector2(u0, (z1 - za) / depth), Vector2(u1, (z1 - za) / depth), Vector2(u1, (z1 - zb) / depth),
					Vector2(u0, (z1 - zb) / depth)]
			_tri(s, [p[0], p[1], p[2]], [ns, ne, ne], [uv[0], uv[1], uv[2]], flat)
			_tri(s, [p[0], p[2], p[3]], [ns, ne, ns], [uv[0], uv[2], uv[3]], flat)


## One triangle, wound so it faces `facing` (Godot's front faces wind clockwise seen from the front: their cross
## product points away from the viewer).
static func _tri(s: Dictionary, p: Array, n: Array, uv: Array, facing: Vector3) -> void:
	var cross: Vector3 = (p[1] - p[0]).cross(p[2] - p[0])
	if cross.length_squared() < 1e-24:
		return
	var order := [0, 1, 2] if cross.dot(facing) < 0.0 else [0, 2, 1]
	for k: int in order:
		(s["v"] as Array).append(p[k])
		(s["n"] as Array).append(n[k])
		(s["uv"] as Array).append(uv[k])


# --- Reading the SVG ------------------------------------------------------------------------------------------------

## The drawing as filled shapes: [{top, color, evenodd, subpaths: [{start, segs}]}] in drawing order, in the root's
## user units (y down), every transform applied.
class Reader:
	var shapes: Array = []
	var warnings: Array = []
	## Top-level element index -> its id.
	var top_ids := {}
	## The same one level down: a drawing whose top level is one wrapping group (an editor's layer) has its parts
	## there.
	var inner_ids := {}
	var _stack: Array = []
	var _tops := 0
	var _inner := 0
	var _css := {}
	var _gradients := {}
	var _gradient_links := {}
	var _gradient := ""
	var _pending: Array = []
	var _warned := {}

	func read(svg: String) -> String:
		var x := XMLParser.new()
		if x.open_buffer(svg.to_utf8_buffer()) != OK:
			return "not an SVG file"
		# The style blocks first: a rule may come after the shapes it colours.
		var blocks := RegEx.create_from_string("<style[^>]*>([\\s\\S]*?)</style>")
		for m in blocks.search_all(svg):
			_parse_css(m.get_string(1).replace("<![CDATA[", "").replace("]]>", ""))
		var seen_root := false
		while x.read() == OK:
			match x.get_node_type():
				XMLParser.NODE_ELEMENT:
					var tag := x.get_node_name().get_slice(":", 1) if x.get_node_name().contains(":") \
							else x.get_node_name()
					var attrs := {}
					for i in x.get_attribute_count():
						attrs[x.get_attribute_name(i)] = x.get_attribute_value(i)
					if not seen_root:
						if tag != "svg":
							return "not an SVG file (it starts with <%s>)" % tag
						seen_root = true
					var empty := x.is_empty()
					_open(tag, attrs)
					if empty:
						_stack.pop_back()
				XMLParser.NODE_ELEMENT_END:
					if not _stack.is_empty():
						_stack.pop_back()
		if not seen_root:
			return "not an SVG file"
		_finish()
		# One wrapping group at the top level: its children are the parts.
		var tops := {}
		var inners := {}
		for s: Dictionary in shapes:
			tops[s["top"]] = true
			inners[s["inner"]] = true
		if tops.size() == 1 and inners.size() > 1 and not inners.has(-1):
			for s: Dictionary in shapes:
				s["top"] = s["inner"]
			top_ids = inner_ids
		return ""

	func _warn(text: String) -> void:
		if not _warned.has(text):
			_warned[text] = true
			warnings.append(text)

	func _open(tag: String, attrs: Dictionary) -> void:
		var parent: Dictionary = _stack[-1] if not _stack.is_empty() else {"xf": Transform2D.IDENTITY,
				"fill": "black", "rule": "nonzero", "top": -1, "inner": -1, "skip": false, "color": "black", "depth": 0,
				"stroke": false}
		var frame := {"tag": tag, "xf": parent["xf"], "fill": parent["fill"], "rule": parent["rule"],
				"top": parent["top"], "inner": parent["inner"], "skip": parent["skip"], "color": parent["color"],
				"depth": int(parent["depth"]) + 1, "stroke": parent["stroke"]}
		if tag in ["linearGradient", "radialGradient"] and attrs.has("id"):
			_gradient = str(attrs["id"])
			var link := str(attrs.get("href", attrs.get("xlink:href", "")))
			if link.begins_with("#"):
				_gradient_links[_gradient] = link.substr(1)
		if tag == "stop" and _gradient != "" and not _gradients.has(_gradient):
			var st := _style(attrs)
			_gradients[_gradient] = str(st.get("stop-color", "black"))
		if tag in SKIP or frame["skip"]:
			frame["skip"] = true
			_stack.append(frame)
			return
		var st := _style(attrs)
		if str(st.get("display", "")) == "none":
			frame["skip"] = true
			_stack.append(frame)
			return
		if st.has("fill"):
			frame["fill"] = str(st["fill"])
		if st.has("fill-rule"):
			frame["rule"] = str(st["fill-rule"])
		if st.has("color"):
			frame["color"] = str(st["color"])
		if st.has("stroke"):
			frame["stroke"] = not (str(st["stroke"]) in ["none", ""])
		if tag == "svg" and frame["depth"] == 1:
			frame["xf"] = _viewbox(attrs)
		if attrs.has("transform"):
			frame["xf"] = (frame["xf"] as Transform2D) * Reader.parse_transform(str(attrs["transform"]))
		if frame["depth"] in [2, 3] and tag in ["g", "path", "rect", "circle", "ellipse", "polygon", "polyline", "svg",
				"a", "switch"]:
			if frame["depth"] == 2:
				frame["top"] = _tops
				if attrs.has("id"):
					top_ids[_tops] = str(attrs["id"])
				_tops += 1
			else:
				frame["inner"] = _inner
				if attrs.has("id"):
					inner_ids[_inner] = str(attrs["id"])
				_inner += 1
		_stack.append(frame)
		if str(st.get("visibility", "")) == "hidden":
			return
		match tag:
			"image":
				_warn("pictures (<image>) can't be extruded: left out")
			"text":
				_warn("text can't be extruded: turn it into paths first; left out")
			"use":
				_warn("<use> copies are not followed: left out")
			"path", "rect", "circle", "ellipse", "polygon", "polyline":
				var subs := _subpaths(tag, attrs)
				if not subs.is_empty():
					_pending.append({"frame": frame, "subpaths": subs})

	## Once the whole file is read (gradients may come after their use): colours and transforms.
	func _finish() -> void:
		for p: Dictionary in _pending:
			var frame: Dictionary = p["frame"]
			var colour: Variant = _colour(str(frame["fill"]), str(frame["color"]))
			if colour == null:
				if bool(frame["stroke"]):
					_warn("lines (stroke) can't be extruded, only filled shapes: unfilled outlines left out")
				continue
			var xf: Transform2D = frame["xf"]
			var subs: Array = []
			for sub: Dictionary in p["subpaths"]:
				var segs: Array = []
				for seg: Array in sub["segs"]:
					segs.append(seg.map(func(v: Vector2) -> Vector2: return xf * v))
				subs.append({"start": xf * (sub["start"] as Vector2), "segs": segs})
			shapes.append({"top": maxi(int(frame["top"]), 0), "inner": int(frame["inner"]), "color": colour,
					"evenodd": str(frame["rule"]).strip_edges() == "evenodd", "subpaths": subs})

	## The root's user units: viewBox scaled to width and height when both are given (uniformly, centred).
	func _viewbox(attrs: Dictionary) -> Transform2D:
		var vb := Reader.numbers(str(attrs.get("viewBox", "")))
		if vb.size() != 4 or vb[2] <= 0.0 or vb[3] <= 0.0:
			return Transform2D.IDENTITY
		var w := str(attrs.get("width", "")).to_float()
		var h := str(attrs.get("height", "")).to_float()
		if w <= 0.0 or h <= 0.0 or str(attrs.get("width", "")).ends_with("%"):
			return Transform2D(0.0, Vector2(-vb[0], -vb[1]))
		var s := minf(w / vb[2], h / vb[3])
		return Transform2D(Vector2(s, 0), Vector2(0, s), Vector2(-vb[0] * s + (w - vb[2] * s) * 0.5,
				-vb[1] * s + (h - vb[3] * s) * 0.5))

	## Presentation attributes, then the style block's .class and #id rules, then style="" (the last wins).
	func _style(attrs: Dictionary) -> Dictionary:
		var out := {}
		for k in ["fill", "fill-rule", "display", "visibility", "color", "stop-color", "stroke"]:
			if attrs.has(k):
				out[k] = str(attrs[k]).strip_edges()
		for cls in str(attrs.get("class", "")).split(" ", false):
			out.merge(_css.get("." + cls, {}), true)
		if attrs.has("id"):
			out.merge(_css.get("#" + str(attrs["id"]), {}), true)
		out.merge(Reader.declarations(str(attrs.get("style", ""))), true)
		return out

	## A style block's rules for one class (.name) or one id (#name); other selectors are not followed.
	func _parse_css(text: String) -> void:
		var rx := RegEx.create_from_string("([^{}]+)\\{([^}]*)\\}")
		for m in rx.search_all(text):
			var decls := Reader.declarations(m.get_string(2))
			for sel in m.get_string(1).split(","):
				var key := sel.strip_edges()
				if key.begins_with(".") or key.begins_with("#"):
					var cur: Dictionary = _css.get_or_add(key, {})
					cur.merge(decls, true)

	static func declarations(style: String) -> Dictionary:
		var out := {}
		for d in style.split(";", false):
			var kv := d.split(":", true, 1)
			if kv.size() == 2:
				out[kv[0].strip_edges()] = kv[1].strip_edges()
		return out

	## A fill as a colour; null for none. Gradients and patterns: a flat colour, with a warning.
	func _colour(fill: String, current: String) -> Variant:
		var f := fill.strip_edges()
		if f == "none" or f == "transparent":
			return null
		if f == "currentColor":
			f = current if current != "currentColor" else "black"
		if f.begins_with("url("):
			var id := f.trim_prefix("url(").get_slice(")", 0).strip_edges().trim_prefix("#").trim_prefix("'") \
					.trim_suffix("'").trim_prefix("\"").trim_suffix("\"")
			var seen := 0
			while not _gradients.has(id) and _gradient_links.has(id) and seen < 8:
				id = _gradient_links[id]
				seen += 1
			_warn("gradients and patterns can't be extruded: each takes one flat colour (its first stop)")
			f = str(_gradients.get(id, "#808080"))
			var rest := fill.get_slice(")", 1).strip_edges()
			if not _gradients.has(id) and rest != "":
				f = rest
		var rgb := RegEx.create_from_string("^rgba?\\(([^)]*)\\)$").search(f)
		if rgb != null:
			var bits := rgb.get_string(1).split(",")
			if bits.size() >= 3:
				var c := [0.0, 0.0, 0.0]
				for i in 3:
					var b := bits[i].strip_edges()
					c[i] = clampf(b.to_float() / (100.0 if b.ends_with("%") else 255.0), 0.0, 1.0)
				return Color(c[0], c[1], c[2])
		if f.begins_with("#") and f.length() == 4:
			f = "#" + f[1] + f[1] + f[2] + f[2] + f[3] + f[3]
		if f.begins_with("#") and Color.html_is_valid(f):
			var col := Color.html(f)
			col.a = 1.0
			return col
		var named := Color.from_string(f, Color(0.5, 0.5, 0.5, 0.0))
		if named.a == 0.0:
			_warn("an unknown colour (%s) became grey" % f.left(30))
			return Color(0.5, 0.5, 0.5)
		return Color(named.r, named.g, named.b)

	# --- Shapes as subpaths: [{start, segs}] (segs: [p] a line, [c1, c2, p] a cubic) ---

	func _subpaths(tag: String, a: Dictionary) -> Array:
		match tag:
			"path":
				return Reader.parse_path(str(a.get("d", "")))
			"rect":
				var x := str(a.get("x", "0")).to_float()
				var y := str(a.get("y", "0")).to_float()
				var w := str(a.get("width", "0")).to_float()
				var h := str(a.get("height", "0")).to_float()
				if w <= 0.0 or h <= 0.0:
					return []
				var rx := str(a.get("rx", a.get("ry", "0"))).to_float()
				var ry := str(a.get("ry", a.get("rx", "0"))).to_float()
				rx = clampf(rx, 0.0, w * 0.5)
				ry = clampf(ry, 0.0, h * 0.5)
				if rx <= 0.0 or ry <= 0.0:
					return [{"start": Vector2(x, y), "segs": [[Vector2(x + w, y)], [Vector2(x + w, y + h)],
							[Vector2(x, y + h)], [Vector2(x, y)]]}]
				var d := "M%f,%f H%f A%f,%f 0 0 1 %f,%f V%f A%f,%f 0 0 1 %f,%f H%f A%f,%f 0 0 1 %f,%f V%f A%f,%f 0 0 1 %f,%f Z" \
						% [x + rx, y, x + w - rx, rx, ry, x + w, y + ry, y + h - ry, rx, ry, x + w - rx, y + h, x + rx,
						rx, ry, x, y + h - ry, y + ry, rx, ry, x + rx, y]
				return Reader.parse_path(d)
			"circle", "ellipse":
				var cx := str(a.get("cx", "0")).to_float()
				var cy := str(a.get("cy", "0")).to_float()
				var rx := str(a.get("r" if tag == "circle" else "rx", "0")).to_float()
				var ry := str(a.get("r" if tag == "circle" else "ry", "0")).to_float()
				if rx <= 0.0 or ry <= 0.0:
					return []
				var k := KAPPA
				var c := Vector2(cx, cy)
				return [{"start": c + Vector2(rx, 0), "segs": [
					[c + Vector2(rx, ry * k), c + Vector2(rx * k, ry), c + Vector2(0, ry)],
					[c + Vector2(-rx * k, ry), c + Vector2(-rx, ry * k), c + Vector2(-rx, 0)],
					[c + Vector2(-rx, -ry * k), c + Vector2(-rx * k, -ry), c + Vector2(0, -ry)],
					[c + Vector2(rx * k, -ry), c + Vector2(rx, -ry * k), c + Vector2(rx, 0)]]}]
			"polygon", "polyline":
				var n := Reader.numbers(str(a.get("points", "")))
				if n.size() < 6:
					return []
				var segs: Array = []
				for i in range(2, n.size() - 1, 2):
					segs.append([Vector2(n[i], n[i + 1])])
				return [{"start": Vector2(n[0], n[1]), "segs": segs}]
		return []

	static func numbers(text: String) -> PackedFloat64Array:
		var out := PackedFloat64Array()
		var rx := RegEx.create_from_string("[-+]?(?:\\d+\\.?\\d*|\\.\\d+)(?:[eE][-+]?\\d+)?")
		for m in rx.search_all(text):
			out.append(m.get_string().to_float())
		return out

	## transform="...": the list composed left to right (the last one applies first).
	static func parse_transform(text: String) -> Transform2D:
		var out := Transform2D.IDENTITY
		var rx := RegEx.create_from_string("(matrix|translate|scale|rotate|skewX|skewY)\\s*\\(([^)]*)\\)")
		for m in rx.search_all(text):
			var n := Reader.numbers(m.get_string(2))
			var t := Transform2D.IDENTITY
			match m.get_string(1):
				"matrix":
					if n.size() == 6:
						t = Transform2D(Vector2(n[0], n[1]), Vector2(n[2], n[3]), Vector2(n[4], n[5]))
				"translate":
					if n.size() >= 1:
						t = Transform2D(0.0, Vector2(n[0], n[1] if n.size() > 1 else 0.0))
				"scale":
					if n.size() >= 1:
						t = Transform2D(Vector2(n[0], 0), Vector2(0, n[1] if n.size() > 1 else n[0]), Vector2.ZERO)
				"rotate":
					if n.size() >= 1:
						t = Transform2D(deg_to_rad(n[0]), Vector2.ZERO)
						if n.size() >= 3:
							var c := Vector2(n[1], n[2])
							t = Transform2D(0.0, c) * t * Transform2D(0.0, -c)
				"skewX":
					if n.size() >= 1:
						t = Transform2D(Vector2(1, 0), Vector2(tan(deg_to_rad(n[0])), 1), Vector2.ZERO)
				"skewY":
					if n.size() >= 1:
						t = Transform2D(Vector2(1, tan(deg_to_rad(n[0]))), Vector2(0, 1), Vector2.ZERO)
			out = out * t
		return out

	## Path data as subpaths of lines and cubics (quadratics raised, arcs as cubics of at most 90 degrees).
	static func parse_path(d: String) -> Array:
		var rx := RegEx.create_from_string("[MmLlHhVvCcSsQqTtAaZz]|[-+]?(?:\\d+\\.?\\d*|\\.\\d+)(?:[eE][-+]?\\d+)?")
		var tokens: Array = []
		for m in rx.search_all(d):
			tokens.append(m.get_string())
		var t := {"i": 0, "tokens": tokens}
		var subs: Array = []
		var sub := {}
		var cur := Vector2.ZERO
		var start := Vector2.ZERO
		var cmd := ""
		var prev := ""
		var last_c := Vector2.ZERO
		var last_q := Vector2.ZERO
		var guard := 0
		while int(t["i"]) < tokens.size() and guard < 1000000:
			guard += 1
			var tok: String = tokens[t["i"]]
			if tok.length() == 1 and "MmLlHhVvCcSsQqTtAaZz".contains(tok):
				cmd = tok
				t["i"] = int(t["i"]) + 1
				if cmd == "Z" or cmd == "z":
					if not sub.is_empty():
						if cur != start:
							(sub["segs"] as Array).append([start])
						subs.append(sub)
						sub = {}
					cur = start
					prev = cmd
					continue
			elif cmd == "" or cmd == "Z" or cmd == "z":
				return subs  # numbers with no command: the rest is unreadable
			var rel := cmd == cmd.to_lower()
			var o := cur if rel else Vector2.ZERO
			if sub.is_empty() and not (cmd in ["M", "m"]):
				sub = {"start": cur, "segs": []}
				start = cur
			match cmd:
				"M", "m":
					if not _has(t, 2):
						break
					var p := o + _pt(t)
					if not sub.is_empty() and not (sub["segs"] as Array).is_empty():
						subs.append(sub)
					sub = {"start": p, "segs": []}
					cur = p
					start = p
					cmd = "l" if rel else "L"
				"L", "l":
					if not _has(t, 2):
						break
					cur = o + _pt(t)
					(sub["segs"] as Array).append([cur])
				"H", "h":
					if not _has(t, 1):
						break
					cur = Vector2((cur.x if rel else 0.0) + _num(t), cur.y)
					(sub["segs"] as Array).append([cur])
				"V", "v":
					if not _has(t, 1):
						break
					cur = Vector2(cur.x, (cur.y if rel else 0.0) + _num(t))
					(sub["segs"] as Array).append([cur])
				"C", "c":
					if not _has(t, 6):
						break
					var c1 := o + _pt(t)
					var c2 := o + _pt(t)
					var p := o + _pt(t)
					(sub["segs"] as Array).append([c1, c2, p])
					last_c = c2
					cur = p
				"S", "s":
					if not _has(t, 4):
						break
					var c1 := cur * 2.0 - last_c if prev in ["C", "c", "S", "s"] else cur
					var c2 := o + _pt(t)
					var p := o + _pt(t)
					(sub["segs"] as Array).append([c1, c2, p])
					last_c = c2
					cur = p
				"Q", "q":
					if not _has(t, 4):
						break
					var q := o + _pt(t)
					var p := o + _pt(t)
					(sub["segs"] as Array).append([cur + (q - cur) * (2.0 / 3.0), p + (q - p) * (2.0 / 3.0), p])
					last_q = q
					cur = p
				"T", "t":
					if not _has(t, 2):
						break
					var q := cur * 2.0 - last_q if prev in ["Q", "q", "T", "t"] else cur
					var p := o + _pt(t)
					(sub["segs"] as Array).append([cur + (q - cur) * (2.0 / 3.0), p + (q - p) * (2.0 / 3.0), p])
					last_q = q
					cur = p
				"A", "a":
					# The two flags may share one token ("01"): count the numbers before and after them.
					if not _has(t, 4):
						break
					var r := Vector2(absf(_num(t)), absf(_num(t)))
					var phi := _num(t)
					var large := _flag(t)
					if not _has(t, 1):
						break
					var sweep := _flag(t)
					if not _has(t, 2):
						break
					var p := o + _pt(t)
					(sub["segs"] as Array).append_array(Reader.arc(cur, r, phi, large, sweep, p))
					cur = p
			prev = cmd
		if not sub.is_empty() and not (sub["segs"] as Array).is_empty():
			subs.append(sub)
		return subs

	static func _has(t: Dictionary, n: int) -> bool:
		var tokens: Array = t["tokens"]
		var i: int = t["i"]
		if i + n > tokens.size():
			t["i"] = tokens.size()
			return false
		for k in n:
			var tok: String = tokens[i + k]
			if tok.length() == 1 and "MmLlHhVvCcSsQqTtAaZz".contains(tok):
				t["i"] = i + k
				return false
		return true

	static func _num(t: Dictionary) -> float:
		var i: int = t["i"]
		t["i"] = i + 1
		return (t["tokens"][i] as String).to_float()

	static func _pt(t: Dictionary) -> Vector2:
		var x := _num(t)
		return Vector2(x, _num(t))

	## An arc flag: one character, which may run into the next number ("a1 1 0 01 1 1": flags 0 and 1, then 1).
	static func _flag(t: Dictionary) -> bool:
		var i: int = t["i"]
		var tok: String = t["tokens"][i]
		var on := tok.begins_with("1")
		if tok.length() > 1:
			t["tokens"][i] = tok.substr(1)
		else:
			t["i"] = i + 1
		return on

	## An elliptical arc (SVG's endpoint form) as cubics: [[c1, c2, p], ...] (a line when a radius is 0).
	static func arc(p0: Vector2, r: Vector2, phi_deg: float, large: bool, sweep: bool, p1: Vector2) -> Array:
		if p0.is_equal_approx(p1):
			return []
		if r.x < 1e-12 or r.y < 1e-12:
			return [[p1]]
		var phi := deg_to_rad(phi_deg)
		var cp := cos(phi)
		var sp := sin(phi)
		var h := (p0 - p1) * 0.5
		var x1 := cp * h.x + sp * h.y
		var y1 := -sp * h.x + cp * h.y
		var rx := r.x
		var ry := r.y
		var lam := (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
		if lam > 1.0:
			rx *= sqrt(lam)
			ry *= sqrt(lam)
		var num := rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
		var den := rx * rx * y1 * y1 + ry * ry * x1 * x1
		var coef := sqrt(maxf(0.0, num / den)) if den > 0.0 else 0.0
		if large == sweep:
			coef = -coef
		var cxp := coef * rx * y1 / ry
		var cyp := -coef * ry * x1 / rx
		var c := Vector2(cp * cxp - sp * cyp, sp * cxp + cp * cyp) + (p0 + p1) * 0.5
		var u := Vector2((x1 - cxp) / rx, (y1 - cyp) / ry)
		var v := Vector2((-x1 - cxp) / rx, (-y1 - cyp) / ry)
		var theta := atan2(u.y, u.x)
		var delta := atan2(u.x * v.y - u.y * v.x, u.dot(v))
		if not sweep and delta > 0.0:
			delta -= TAU
		elif sweep and delta < 0.0:
			delta += TAU
		var n := maxi(1, ceili(absf(delta) / (PI / 2.0) - 1e-9))
		var d := delta / n
		var alpha := 4.0 / 3.0 * tan(d / 4.0)
		var out: Array = []
		var at := func(a: float) -> Vector2:
			return c + Vector2(rx * cos(a) * cp - ry * sin(a) * sp, rx * cos(a) * sp + ry * sin(a) * cp)
		var tangent := func(a: float) -> Vector2:
			return Vector2(-rx * sin(a) * cp - ry * cos(a) * sp, -rx * sin(a) * sp + ry * cos(a) * cp)
		for k in n:
			var a0 := theta + d * k
			var a1 := a0 + d
			var e0: Vector2 = at.call(a0)
			var e1: Vector2 = p1 if k == n - 1 else at.call(a1)
			out.append([e0 + (tangent.call(a0) as Vector2) * alpha, e1 - (tangent.call(a1) as Vector2) * alpha, e1])
		return out
