extends SceneTree

## The passing system's scenery shapes (scripts/env/systems/passing/shapes.gd): each band shape and landmark draws
## something, the same seed draws the same item, each keeps to its triangle budget and its size, a hedge's pieces
## meet, a cottage's lit windows and a lamp's lights face the way, a bridge leaves the way open, and every material is
## one of ShapeMesh's. No main scene.
## godot --headless --xr-mode off --path app --script res://tests/test_env_passing_shapes.gd

const Shapes := preload("res://scripts/env/systems/passing/shapes.gd")
const ShapeMesh := preload("res://scripts/env/systems/passing/shape_mesh.gd")

const BUDGET := {"reeds": 70, "willow": 400, "tree": 420, "poplar": 120, "hedge": 60, "fence": 50, "ridge": 2,
		"lights": 0, "cottage": 80, "post": 12, "lamp": 70, "bridge": 140, "boat": 130, "wharf": 220, "tower": 130}
## The highest point of each shape at size 1 (metres): at least, at most.
const HEIGHT := {"reeds": [1.2, 2.4], "willow": [3.0, 6.5], "tree": [9.0, 14.0], "poplar": [13.5, 20.5],
		"hedge": [1.4, 2.2], "fence": [1.0, 1.2], "cottage": [5.3, 5.5], "post": [1.1, 1.3], "lamp": [3.1, 3.3],
		"bridge": [5.1, 5.3], "boat": [1.9, 2.0], "wharf": [4.7, 4.9], "tower": [19.5, 19.7]}
const VARIED: Array[String] = ["reeds", "willow", "tree", "cottage", "boat"]

var _failures := 0
var _checks := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for shape: String in Shapes.BANDS + Shapes.LANDMARKS:
		_shape(shape)
	_tree()
	_hedge()
	_cottage()
	_bridge()
	_lamp()
	var m := _draw("nothing", 1234, _info())
	_check("an unknown shape draws nothing", m.triangle_count() == 0 and m.light_count() == 0)
	print("test_env_passing_shapes: %d checks, %s" % [_checks,
			"all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _info(along := 12.0, side := 1, distance := 8.0) -> Dictionary:
	return {"along": along, "length": 240.0, "side": side, "distance": distance}


func _draw(shape: String, seed_: int, info: Dictionary) -> ShapeMesh:
	var m := ShapeMesh.new()
	m.begin_item(8.0, 0.0, 12.0, 0.0, 240.0, 1.0, 0, false)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	Shapes.draw(shape, m, rng, 1.0, Color(Shapes.COLOURS.get(shape, "#ffffff")), info)
	return m


## The committed mesh's arrays (empty when nothing was drawn).
func _arrays(m: ShapeMesh) -> Array:
	var mesh := m.commit()
	if mesh == null:
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = PackedVector3Array()
		a[Mesh.ARRAY_COLOR] = PackedColorArray()
		a[Mesh.ARRAY_TEX_UV2] = PackedVector2Array()
		return a
	return mesh.surface_get_arrays(0)


func _light_points(m: ShapeMesh) -> PackedVector3Array:
	var mesh := m.commit_lights()
	if mesh == null:
		return PackedVector3Array()
	return mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]


func _shape(shape: String) -> void:
	var m := _draw(shape, 1234, _info())
	print("%s: %d triangles, %d lights" % [shape, m.triangle_count(), m.light_count()])
	if shape == "lights":
		_check("%s draws something" % shape, m.light_count() > 0)
	else:
		_check("%s draws something" % shape, m.triangle_count() > 0)
	var a := _arrays(m)
	var again := _draw(shape, 1234, _info())
	var b := _arrays(again)
	_check("%s: the same seed draws the same item" % shape, m.triangle_count() == again.triangle_count()
			and m.light_count() == again.light_count() and a[Mesh.ARRAY_VERTEX] == b[Mesh.ARRAY_VERTEX]
			and _light_points(m) == _light_points(again))
	if shape in VARIED:
		# "A different one" is any difference in the vertices, their colours or their materials: a cottage and a
		# boat differ only in which windows are lit.
		var c := _arrays(_draw(shape, 4321, _info()))
		_check("%s: a different seed draws a different one" % shape, a[Mesh.ARRAY_VERTEX] != c[Mesh.ARRAY_VERTEX]
				or a[Mesh.ARRAY_COLOR] != c[Mesh.ARRAY_COLOR] or a[Mesh.ARRAY_TEX_UV2] != c[Mesh.ARRAY_TEX_UV2])
	_check("%s: %d triangles within its budget of %d" % [shape, m.triangle_count(), BUDGET[shape]],
			m.triangle_count() <= int(BUDGET[shape]))
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var low := INF
	var high := -INF
	for v in verts:
		low = minf(low, v.y)
		high = maxf(high, v.y)
	_check("%s: nothing under y = -2.1 (%.3f)" % [shape, low], verts.is_empty() or low >= -2.1)
	if HEIGHT.has(shape):
		var r: Array = HEIGHT[shape]
		_check("%s: its highest point %.3f within %s" % [shape, high, r], high >= r[0] and high <= r[1])
	var mats_ok := true
	for uv2 in a[Mesh.ARRAY_TEX_UV2] as PackedVector2Array:
		if not (uv2.x in [0.0, 1.0, 2.0, 3.0, 4.0]):
			mats_ok = false
	_check("%s: every material one of M_*" % shape, mats_ok)


## The highest y of the vertices at local z.
func _top_at(m: ShapeMesh, z: float) -> float:
	var high := -INF
	for v in _arrays(m)[Mesh.ARRAY_VERTEX] as PackedVector3Array:
		if absf(v.z - z) < 1e-4:
			high = maxf(high, v.y)
	return high


## A tree is as tall as it says for every seed, not for one: its top ball's top is its height, and no other ball
## stands over it.
func _tree() -> void:
	var low := INF
	var high := -INF
	for s in range(1, 41):
		var top := -INF
		for v in _arrays(_draw("tree", s, _info()))[Mesh.ARRAY_VERTEX] as PackedVector3Array:
			top = maxf(top, v.y)
		low = minf(low, top)
		high = maxf(high, top)
	_check("tree: forty seeds stand from %.2f to %.2f m, within 9 to 14" % [low, high], low >= 9.0 and high <= 14.0)
	_check("tree: and they are not all one height (%.2f m between them)" % (high - low), high - low > 2.0)


func _hedge() -> void:
	var want := Shapes.hedge_height(18.0)
	var end := _top_at(_draw("hedge", 1234, _info(12.0)), 6.0)
	var start := _top_at(_draw("hedge", 1234, _info(18.0)), 0.0)
	_check("hedge: the piece at 12 ends at hedge_height(18) (%.4f, %.4f)" % [end, want], absf(end - want) < 0.001)
	_check("hedge: the piece at 18 starts at hedge_height(18) (%.4f, %.4f)" % [start, want],
			absf(start - want) < 0.001)


func _cottage() -> void:
	for side: int in [1, -1]:
		var found := false
		for s in range(1, 21):
			var a := _arrays(_draw("cottage", s, _info(12.0, side)))
			var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var uv2: PackedVector2Array = a[Mesh.ARRAY_TEX_UV2]
			var lit := 0
			var ok := true
			for i in verts.size():
				if uv2[i].x == float(ShapeMesh.M_WINDOW):
					lit += 1
					if signf(verts[i].x) != -side:
						ok = false
			if lit > 0:
				found = true
				_check("cottage (side %d, seed %d): its lit windows face the way" % [side, s], ok)
				break
		_check("cottage (side %d): a seed of 1 to 20 has a lit window" % side, found)


func _bridge() -> void:
	for side: int in [1, -1]:
		var verts: PackedVector3Array = _arrays(_draw("bridge", 1234, _info(12.0, side, 8.0)))[Mesh.ARRAY_VERTEX]
		var lo := INF
		var hi := -INF
		var open := true
		for v in verts:
			lo = minf(lo, v.x)
			hi = maxf(hi, v.x)
			if absf(v.x + side * 8.0) < 7.9 and v.y < 1.39:
				open = false
		var want_lo := -17.2 if side == 1 else -1.2
		var want_hi := 1.2 if side == 1 else 17.2
		_check("bridge (side %d): x runs from %.3f to %.3f" % [side, lo, hi], absf(lo - want_lo) < 0.01
				and absf(hi - want_hi) < 0.01)
		_check("bridge (side %d): the way under the arch is open" % side, open)


func _lamp() -> void:
	for side: int in [1, -1]:
		var m := _draw("lamp", 1234, _info(12.0, side))
		var ok := m.light_count() == 2
		for p in _light_points(m):
			if absf(p.x - (-side * 0.5)) > 1e-5:
				ok = false
		_check("lamp (side %d): two lights at x = %.1f" % [side, -side * 0.5], ok)


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)
