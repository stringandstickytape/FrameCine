extends RefCounted

## The mesh the passing system's scenery is written into (docs/environments/passing.md). Every vertex says which item
## it is part of and where that item stands along the way, so one shader (shaders/env_passing.gdshader) carries all of
## a room's scenery past the cabin in one draw, and nothing is moved on the CPU.
##
## The way's frame: x across the way (positive: to the right of the way the cabin goes), y up, z along the way
## (positive: ahead). A shape writes its points in that frame, in metres about its item's foot.
##
##   var m := ShapeMesh.new()
##   m.begin_item(across, height, along, threshold, loop, pace, index, landmark)
##   m.material(M_LEAF, extra)                  what the next faces are made of
##   m.tri(), quad(), box(), tube(), ball(), ribbon()     the item's parts
##   m.light(at, colour, brightness, radius)    a point of light of the item
##   m.commit() -> ArrayMesh                    the scenery (null when empty); commit_lights() the points of light
##
## What a vertex carries (the shaders read exactly this; change both together):
##   VERTEX    the point, about the item's foot (the way's frame)
##   NORMAL    in the way's frame
##   COLOR     its colour; alpha is not used
##   UV        the shape's own (a stem's UV.y runs 0 at the foot to 1 at the tip)
##   UV2       x: the material (M_*); y: `extra`, a number of the item's own, 0..1
##   CUSTOM0   x: the foot's place across the way; y: its height; z: its place along the loop or the route (metres);
##             w: its threshold: the item shows while its band's presence is at or over this (0: always)
##   CUSTOM1   x: the loop's length (0: a landmark, which comes by once); y: its pace (a band that seems further off
##             than it is drawn goes by slower: 1 / seems); z: its band's or its landmark's index; w: 1 for a landmark
## A light is four vertices at one point: UV is the corner (-1..1 each way), UV2.x its radius in metres, COLOR.a its
## brightness; the lights' shader turns the corners to the eye.

const M_PLAIN := 0   ## its colour, lit by the sky: stone, a wall, a hull, a post
const M_LEAF := 1    ## foliage: mottled, a little more light on what faces up
const M_STEM := 2    ## reeds and grass: paler towards the tip (UV.y)
const M_BARK := 3
const M_WINDOW := 4  ## a lit window: it glows at the system's `windows` level and takes no light

var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _c := PackedColorArray()
var _uv := PackedVector2Array()
var _uv2 := PackedVector2Array()
var _c0 := PackedFloat32Array()
var _c1 := PackedFloat32Array()
var _lv := PackedVector3Array()
var _lc := PackedColorArray()
var _luv := PackedVector2Array()
var _luv2 := PackedVector2Array()
var _lc0 := PackedFloat32Array()
var _lc1 := PackedFloat32Array()
var _li := PackedInt32Array()
var _item0 := [0.0, 0.0, 0.0, 0.0]
var _item1 := [0.0, 1.0, 0.0, 0.0]
var _mat := M_PLAIN
var _extra := 0.0


## The item the next parts belong to: where its foot stands (across the way, its height, along the loop or route),
## its threshold, its loop's length (0 for a landmark), its pace, its band's or landmark's index.
func begin_item(across: float, height: float, along: float, threshold: float, loop: float, pace: float,
		index: int, landmark := false) -> void:
	_item0 = [across, height, along, threshold]
	_item1 = [loop, pace, float(index), 1.0 if landmark else 0.0]
	_mat = M_PLAIN
	_extra = 0.0


func material(id: int, extra := 0.0) -> void:
	_mat = id
	_extra = extra


func triangle_count() -> int:
	return _v.size() / 3


func light_count() -> int:
	return _lv.size() / 4


func _vert(p: Vector3, n: Vector3, col: Color, uv: Vector2) -> void:
	_v.append(p)
	_n.append(n)
	_c.append(col)
	_uv.append(uv)
	_uv2.append(Vector2(float(_mat), _extra))
	_c0.append_array(_item0)
	_c1.append_array(_item1)


## One flat triangle. It is seen from both sides (the shader culls nothing). Its normal is (b - a) x (c - a) unless
## `normal` gives one (a ball's faces all look outward).
func tri(a: Vector3, b: Vector3, c: Vector3, colour: Color, uva := Vector2.ZERO, uvb := Vector2.ZERO,
		uvc := Vector2.ZERO, normal := Vector3.ZERO) -> void:
	var n := normal if normal != Vector3.ZERO else (b - a).cross(c - a)
	n = n.normalized() if n.length() > 1e-9 else Vector3.UP
	_vert(a, n, colour, uva)
	_vert(b, n, colour, uvb)
	_vert(c, n, colour, uvc)


## A flat face of four corners in order round it; `colour_top` (when given) is the colour of c and d (a gradient
## from the a-b edge to the c-d edge). UV.y runs 0 on a-b to 1 on c-d.
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, colour: Color, colour_top: Variant = null) -> void:
	var top: Color = colour_top if colour_top is Color else colour
	var n := (b - a).cross(d - a)
	n = n.normalized() if n.length() > 1e-9 else Vector3.UP
	_vert(a, n, colour, Vector2(0, 0))
	_vert(b, n, colour, Vector2(1, 0))
	_vert(c, n, top, Vector2(1, 1))
	_vert(a, n, colour, Vector2(0, 0))
	_vert(c, n, top, Vector2(1, 1))
	_vert(d, n, top, Vector2(0, 1))


## A box by its centre and size, turned `yaw` radians about the vertical. bottom false leaves its underside out.
func box(centre: Vector3, size: Vector3, colour: Color, yaw := 0.0, bottom := false) -> void:
	var b := Basis(Vector3.UP, yaw)
	var h := size * 0.5
	var p := func(x: float, y: float, z: float) -> Vector3: return centre + b * Vector3(x * h.x, y * h.y, z * h.z)
	quad(p.call(-1, -1, 1), p.call(1, -1, 1), p.call(1, 1, 1), p.call(-1, 1, 1), colour)
	quad(p.call(1, -1, -1), p.call(-1, -1, -1), p.call(-1, 1, -1), p.call(1, 1, -1), colour)
	quad(p.call(1, -1, 1), p.call(1, -1, -1), p.call(1, 1, -1), p.call(1, 1, 1), colour)
	quad(p.call(-1, -1, -1), p.call(-1, -1, 1), p.call(-1, 1, 1), p.call(-1, 1, -1), colour)
	quad(p.call(-1, 1, 1), p.call(1, 1, 1), p.call(1, 1, -1), p.call(-1, 1, -1), colour)
	if bottom:
		quad(p.call(-1, -1, -1), p.call(1, -1, -1), p.call(1, -1, 1), p.call(-1, -1, 1), colour)


## A tube with no ends from `from` to `to`, its radius r0 there and r1 here, of `sides` flat-shaded sides, its
## colour running from colour0 to colour1. UV.y runs 0 at `from` to 1 at `to`.
func tube(from: Vector3, to: Vector3, r0: float, r1: float, sides: int, colour0: Color, colour1: Color) -> void:
	var axis := (to - from).normalized()
	var side := axis.cross(Vector3.RIGHT if absf(axis.x) < 0.9 else Vector3.FORWARD).normalized()
	var other := axis.cross(side)
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var d0 := side * cos(a0) + other * sin(a0)
		var d1 := side * cos(a1) + other * sin(a1)
		quad(from + d0 * r0, from + d1 * r0, to + d1 * r1, to + d0 * r1, colour0, colour1)


## A ball of `rings` by `sides` flat faces: `squash` times as high as it is wide; each point pushed in or out by up
## to `jitter` of the radius (rng) so no two are alike. Its colour is `colour`, darker underneath (to 0.7) and
## lighter on top (to 1.15): the sky's light, cheaply.
func ball(centre: Vector3, radius: float, rings: int, sides: int, colour: Color, squash := 1.0, jitter := 0.0,
		rng: RandomNumberGenerator = null) -> void:
	var rows: Array = []
	for r in rings + 1:
		var lat := PI * r / rings
		var row := PackedVector3Array()
		for s in sides:
			var lon := TAU * s / sides
			var k := 1.0 + (rng.randf_range(-jitter, jitter) if rng != null and r > 0 and r < rings else 0.0)
			row.append(centre + Vector3(sin(lat) * cos(lon), cos(lat) * squash, sin(lat) * sin(lon)) * radius * k)
		rows.append(row)
	for r in rings:
		var a: PackedVector3Array = rows[r]
		var b: PackedVector3Array = rows[r + 1]
		var shade0 := lerpf(1.15, 0.7, float(r) / rings)
		var shade1 := lerpf(1.15, 0.7, float(r + 1) / rings)
		var c0 := Color(colour.r * shade0, colour.g * shade0, colour.b * shade0)
		var c1 := Color(colour.r * shade1, colour.g * shade1, colour.b * shade1)
		for s in sides:
			var t := (s + 1) % sides
			var out := ((a[s] + a[t] + b[s] + b[t]) * 0.25 - centre).normalized()
			# The top row is one point and the bottom row is one point: each has one triangle a side, not two.
			if r > 0:
				tri(a[s], b[t], a[t], c0, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, out)
			if r < rings - 1:
				tri(a[s], b[s], b[t], c1, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, out)


## A flat strip along a line of points, `widths[i]` wide at each, lying across `side` (the direction of its width).
## Its colour runs from colour0 at the first point to colour1 at the last; UV.y runs 0 to 1.
func ribbon(points: PackedVector3Array, widths: PackedFloat32Array, side: Vector3, colour0: Color,
		colour1: Color) -> void:
	var n := points.size()
	for i in n - 1:
		var f0 := float(i) / (n - 1)
		var f1 := float(i + 1) / (n - 1)
		var h0 := side * widths[i] * 0.5
		var h1 := side * widths[i + 1] * 0.5
		var a := points[i] - h0
		var b := points[i] + h0
		var c := points[i + 1] + h1
		var d := points[i + 1] - h1
		var nn := (b - a).cross(d - a)
		nn = nn.normalized() if nn.length() > 1e-9 else Vector3.UP
		var ca := colour0.lerp(colour1, f0)
		var cb := colour0.lerp(colour1, f1)
		_vert(a, nn, ca, Vector2(0, f0))
		_vert(b, nn, ca, Vector2(1, f0))
		_vert(c, nn, cb, Vector2(1, f1))
		_vert(a, nn, ca, Vector2(0, f0))
		_vert(c, nn, cb, Vector2(1, f1))
		_vert(d, nn, cb, Vector2(0, f1))


## A point of light of the item, at `at` about its foot: its colour, its brightness (1: a lamp near by) and its
## radius in metres (the shader never draws it smaller than a tenth of a degree, so a far light does not shimmer).
func light(at: Vector3, colour: Color, brightness: float, radius: float) -> void:
	var first := _lv.size()
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		_lv.append(at)
		_lc.append(Color(colour.r, colour.g, colour.b, brightness))
		_luv.append(corner)
		_luv2.append(Vector2(radius, _extra))
		_lc0.append_array(_item0)
		_lc1.append_array(_item1)
	_li.append_array([first, first + 1, first + 2, first, first + 2, first + 3])


const _FORMAT := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
		| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)


## The scenery as one surface (null when nothing was drawn).
func commit() -> ArrayMesh:
	if _v.is_empty():
		return null
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = _v
	a[Mesh.ARRAY_NORMAL] = _n
	a[Mesh.ARRAY_COLOR] = _c
	a[Mesh.ARRAY_TEX_UV] = _uv
	a[Mesh.ARRAY_TEX_UV2] = _uv2
	a[Mesh.ARRAY_CUSTOM0] = _c0
	a[Mesh.ARRAY_CUSTOM1] = _c1
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a, [], {}, _FORMAT)
	return mesh


## The points of light as one surface (null when there are none).
func commit_lights() -> ArrayMesh:
	if _lv.is_empty():
		return null
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = _lv
	a[Mesh.ARRAY_COLOR] = _lc
	a[Mesh.ARRAY_TEX_UV] = _luv
	a[Mesh.ARRAY_TEX_UV2] = _luv2
	a[Mesh.ARRAY_CUSTOM0] = _lc0
	a[Mesh.ARRAY_CUSTOM1] = _lc1
	a[Mesh.ARRAY_INDEX] = _li
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a, [], {}, _FORMAT)
	return mesh
