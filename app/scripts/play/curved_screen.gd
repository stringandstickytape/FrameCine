extends Node

## Curved screen (ideas #31): the flat projections (mono, SBS, TB) on a section of a vertical cylinder instead of a
## plane, curving toward the viewer. The picture's width is the arc length, so the screen size setting means the same
## thing. The mesh carries the same per-vertex UV as the quad (0..1 across one eye's picture), so video.gdshader is
## unchanged; VideoScreen swaps the quad for this mesh when curve_radius > 0.
##
## The amount is what the user sets (the Picture tab's "Curvature", 0..100 %): 0 = flat, 1 = a radius equal to the
## screen distance (every column of the picture at the same distance from the viewer; the screen wraps evenly around
## them). radius = distance / amount, so the radius is never smaller than the viewing distance: a radius far below it
## rolled a wide screen into a tube (12 m of arc on a 2.5 m radius is 275°), which read as "curvature doesn't work".
## When the distance changes, the radius follows so the amount holds.
##
##   amount               0..1; set_amount(a) (below MIN_AMOUNT: flat), remembered per environment
##   radius               metres, 0 = flat (derived: distance / amount)
##   set_radius(r)        the older API: amount = distance / r (at most 1), 0 below MIN_RADIUS
##   match_distance()     amount 1
##   static radius_for(distance, amount), static amount_for(distance, radius)
##   static build(size, radius) -> ArrayMesh
## Not for a captured window: its pointer maps onto the plane, so the window stays flat.
## Settings: [screen_<environment id>] curve_radius (the radius, as before; read back as an amount at the
## environment's distance).

signal changed(radius: float)

const MIN_RADIUS := 1.0
## Below 1 %: flat.
const MIN_AMOUNT := 0.01
const SEGMENTS := 64

var main: Node3D
var radius := 0.0
var amount := 0.0


func _ready() -> void:
	main.environment_changed.connect(func(_id: String, _l: float) -> void: _load())
	main.file_opened.connect(func(_p: String) -> void: _apply())
	main.screen_changed.connect(func(_w: float, _d: float, _h: float) -> void: _follow_distance())
	_load()


static func radius_for(distance: float, p_amount: float) -> float:
	return 0.0 if p_amount < MIN_AMOUNT else distance / clampf(p_amount, MIN_AMOUNT, 1.0)


static func amount_for(distance: float, p_radius: float) -> float:
	return 0.0 if p_radius < MIN_RADIUS else clampf(distance / p_radius, 0.0, 1.0)


func _load() -> void:
	var stored := float(main.settings.get_value("screen_" + main.env_id, "curve_radius", 0.0))
	amount = amount_for(main.screen_distance, stored)
	radius = radius_for(main.screen_distance, amount)
	_apply()


## 0..1 of a full wrap (radius = the screen distance).
func set_amount(a: float) -> void:
	amount = 0.0 if a < MIN_AMOUNT else clampf(a, 0.0, 1.0)
	_store()


## The radius in metres; kept for older callers (the dev link, tests). Never below the screen distance.
func set_radius(r: float) -> void:
	set_amount(amount_for(main.screen_distance, r))


func match_distance() -> void:
	set_amount(1.0)


func _follow_distance() -> void:
	if amount <= 0.0:
		return
	var r := radius_for(main.screen_distance, amount)
	if not is_equal_approx(r, radius):
		_store()


func _store() -> void:
	radius = radius_for(main.screen_distance, amount)
	main.settings.set_value("screen_" + main.env_id, "curve_radius", snappedf(radius, 0.01) if radius > 0.0 else null)
	_apply()


func _apply() -> void:
	var on_window: bool = main.player.has_source() and main.player.source.get_kind() == "window"
	main.screen.set_curve_radius(0.0 if on_window else radius)
	changed.emit(radius)


## A cylinder section `size.x` wide (arc length) and `size.y` tall, centred on the origin, bulging away from +Z (its
## edges come toward a viewer on +Z), UV (0,0) top left as the quad's. Clockwise as seen from +Z, for cull_back.
static func build(size: Vector2, r: float, segments := SEGMENTS) -> ArrayMesh:
	var theta := size.x / r
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	for i in segments + 1:
		var u := float(i) / segments
		var phi := (u - 0.5) * theta
		var x := r * sin(phi)
		var z := r * (1.0 - cos(phi))
		var n := Vector3(-sin(phi), 0.0, cos(phi))
		for row in 2:
			verts.append(Vector3(x, size.y * (0.5 - row), z))
			uvs.append(Vector2(u, float(row)))
			normals.append(n)
	var idx := PackedInt32Array()
	for i in segments:
		var a := i * 2
		# a: top left, a+1: bottom left, a+2: top right, a+3: bottom right.
		idx.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
