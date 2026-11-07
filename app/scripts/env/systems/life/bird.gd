extends "res://scripts/env/systems/life/creature.gd"

## Birds (the reclaimed cinema's broken roof): small, dark, 32 cm across the wings. They roost on perches (the path's
## points: the roof's broken edge; by default the top edges of the region) with their wings folded, turn now and then,
## and one at a time flit to another perch on an arc through the open air, never through the sight line or the
## viewer's face. activity: how often they flit (0: they roost; bind it to time.of_day for a night roost). scatter:
## all take off, circle over the region and come back; pass: one flies the length of the roof; settle: all to their
## perches. A perched bird calls now and then (an event; a sound only where the synthesiser has one).

const SPAN := 0.32
const FLY := 3.0
const COLOUR := Color(0.2, 0.18, 0.16)
enum { PERCHED, FLYING, CIRCLING }

var perches: Array[Vector3] = []
var mode := PackedInt32Array()
var at := PackedInt32Array()
var pos: Array[Vector3] = []
var dir: Array[Vector3] = []
var arc: Array = []
var t := PackedFloat32Array()
var rest := PackedFloat32Array()
var phase := PackedFloat32Array()
var fold := PackedFloat32Array()
var call_in := PackedFloat32Array()
var _circle := Vector3.ZERO
var _circle_for := 0.0
## Flights so far (tests).
var flights := 0
var _box := AABB()


static func defaults() -> Dictionary:
	return {"count": 6, "max": 40}


func build() -> void:
	var r: Variant = life.region()
	_box = r if r is AABB else life.around_viewer(9.0, 2.5, 5.0, 10.0, 6.0)
	for p in life.path_points():
		perches.append(life.keep(p))
	if perches.size() < 2:
		perches.clear()
		var top := _box.position.y + _box.size.y
		var n := count + 3
		for i in n:
			# Round the top face's rim.
			var u := float(i) / float(n) * 4.0
			var e := int(u)
			var f := u - float(e)
			var x0 := _box.position.x
			var x1 := _box.end.x
			var z0 := _box.position.z
			var z1 := _box.end.z
			var p: Vector3 = [Vector3(lerpf(x0, x1, f), top, z0), Vector3(x1, top, lerpf(z0, z1, f)),
					Vector3(lerpf(x1, x0, f), top, z1), Vector3(x0, top, lerpf(z1, z0, f))][e % 4]
			perches.append(life.keep(p))
	var s := Shape.new()
	var body := func(_p: Vector3) -> Vector4: return Vector4.ZERO
	s.loft([[-0.09, 0.005, 0.005, 0.0], [-0.06, 0.022, 0.025, 0.0], [0.02, 0.025, 0.022, 0.0],
			[0.08, 0.01, 0.008, 0.0]], 4, body)
	s.tri(Vector3(0, 0, 0.07), Vector3(0.03, 0, 0.13), Vector3(-0.03, 0, 0.13))
	var h := SPAN * 0.5
	for sx: float in [-1.0, 1.0]:
		var rf := Vector3(0, 0.01, -0.03)
		var rb := Vector3(0, 0.01, 0.03)
		var mf := Vector3(sx * h * 0.55, 0.01, -0.025)
		var mb := Vector3(sx * h * 0.55, 0.01, 0.035)
		var tip := Vector3(sx * h, 0.01, 0.025)
		var w0 := Vector4.ZERO
		var wm := Vector4(0.6, 0, 0, 0)
		var wt := Vector4(1, 0, 0, 0)
		s.tri(rf, mf, mb, w0, wm, wm)
		s.tri(rf, mb, rb, w0, wm, w0)
		s.tri(mf, tip, mb, wm, wt, wm)
	multimesh(s.commit(), count, body_material(life.colour_or(COLOUR), {"flap": 0.9, "fold": 0.85, "spill": 0.8}),
			WIDE, "Birds")
	var order := range(perches.size())
	for i in count:
		var k: int = order[i % order.size()]
		mode.append(PERCHED)
		at.append(k)
		pos.append(perches[k])
		dir.append(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized())
		arc.append([])
		t.append(0.0)
		rest.append(rng.randf_range(3.0, 30.0))
		phase.append(rng.randf())
		fold.append(1.0)
		call_in.append(rng.randf_range(15.0, 60.0))


func param_changed(param: String) -> void:
	if param == "colour" and material != null:
		material.set_shader_parameter("colour", life.colour_or(COLOUR))


## A flight from where bird i is to point b: an arc over the gap, raised until it is clear; false if none is.
func fly_to(i: int, b: Vector3, k := -1) -> bool:
	var a := pos[i]
	var lift := 0.3 * a.distance_to(b) + 1.0
	for attempt in 4:
		var c := (a + b) * 0.5 + Vector3.UP * lift
		var clear := true
		for n in 13:
			var p := _bezier(a, c, b, float(n) / 12.0)
			if life.in_view(p) or p.distance_to(life.eye_now()) < float(life.params["personal"]):
				clear = false
				break
		if clear:
			arc[i] = [a, c, b, k]
			mode[i] = FLYING
			t[i] = 0.0
			flights += 1
			return true
		lift += 2.0
	return false


static func _bezier(a: Vector3, c: Vector3, b: Vector3, f: float) -> Vector3:
	return a.lerp(c, f).lerp(c.lerp(b, f), f)


func _arc_seconds(i: int) -> float:
	var a: Array = arc[i]
	var n := 0.0
	var last: Vector3 = a[0]
	for s in range(1, 9):
		var p := _bezier(a[0], a[1], a[2], float(s) / 8.0)
		n += last.distance_to(p)
		last = p
	return n / (FLY * speed())


func _free_perch(i: int, far := false) -> int:
	var best := -1
	var best_d := -1.0 if far else INF
	for k in perches.size():
		if k == at[i]:
			continue
		var taken := false
		for j in count:
			if j != i and at[j] == k and mode[j] == PERCHED:
				taken = true
		if taken:
			continue
		var d := perches[k].distance_to(pos[i]) + rng.randf() * 0.5
		if (far and d > best_d) or (not far and d < best_d):
			best = k
			best_d = d
	return best


func step(delta: float) -> void:
	var activity := float(life.params["activity"])
	_circle_for = maxf(_circle_for - delta, 0.0)
	for i in count:
		match mode[i]:
			PERCHED:
				fold[i] = move_toward(fold[i], 1.0, delta * 3.0)
				rest[i] -= delta * activity
				if rng.randf() < delta * 0.08:
					dir[i] = dir[i].rotated(Vector3.UP, rng.randf_range(-1.2, 1.2))
				if rest[i] <= 0.0:
					rest[i] = rng.randf_range(8.0, 40.0)
					var k := _free_perch(i)
					if k >= 0:
						fly_to(i, perches[k], k)
				call_in[i] -= delta
				if call_in[i] <= 0.0:
					call_in[i] = rng.randf_range(20.0, 60.0)
					life.call_out("bird_call", "bird", pos[i])
			FLYING:
				fold[i] = move_toward(fold[i], 0.0, delta * 4.0)
				var a: Array = arc[i]
				t[i] += delta / maxf(_arc_seconds(i), 0.2)
				var f := minf(t[i], 1.0)
				var p := _bezier(a[0], a[1], a[2], f)
				var ahead := _bezier(a[0], a[1], a[2], minf(f + 0.02, 1.0)) - p
				if ahead.length() > 1e-4:
					dir[i] = ahead.normalized()
				pos[i] = life.keep(p)
				phase[i] = fmod(phase[i] + delta * (7.0 if f < 0.75 else 3.0), 1.0)
				if t[i] >= 1.0:
					mode[i] = PERCHED
					if int(a[3]) >= 0:
						at[i] = int(a[3])
					dir[i].y = 0.0
					dir[i] = dir[i].normalized() if dir[i].length() > 1e-3 else Vector3.FORWARD
			CIRCLING:
				fold[i] = move_toward(fold[i], 0.0, delta * 4.0)
				var radius := 3.0 + float(i % 3)
				var ang := t[i]
				t[i] += delta * FLY * speed() / radius
				var p := _circle + Vector3(cos(ang) * radius, 0.4 * sin(ang * 2.0 + float(i)), sin(ang) * radius)
				var nxt := Vector3(-sin(ang), 0.0, cos(ang))
				dir[i] = nxt
				pos[i] = pos[i].lerp(life.keep(p), clampf(delta * 2.0, 0.0, 1.0))
				phase[i] = fmod(phase[i] + delta * 6.0, 1.0)
				if _circle_for <= 0.0:
					var k := _free_perch(i)
					if k < 0 or not fly_to(i, perches[k], k):
						mode[i] = PERCHED
						pos[i] = perches[at[i]]
		var flapping := 0.0 if mode[i] == PERCHED else (1.0 if mode[i] == CIRCLING or t[i] < 0.75 else 0.35)
		put(i, facing(pos[i], dir[i], size()), Color(1, 1, 1, life.fade),
				Color(phase[i], flapping, 0.0, fold[i]))
	flush()


func act(action: String, args: Dictionary) -> bool:
	match action:
		"scatter":
			_circle = Vector3(_box.get_center().x, _box.end.y + 2.0, _box.get_center().z)
			_circle_for = rng.randf_range(6.0, 12.0)
			for i in count:
				mode[i] = CIRCLING
				t[i] = rng.randf() * TAU
			return true
		"settle":
			for i in count:
				if mode[i] != PERCHED:
					var k := _free_perch(i)
					if k < 0 or not fly_to(i, perches[k], k):
						mode[i] = PERCHED
						pos[i] = perches[at[i]]
			return true
		"pass":
			# The perched bird furthest to the given side flies to the perch furthest from it.
			var right: Vector3 = life.screen().basis.x
			var sgn := float(side_arg(args))
			var best := -1
			for i in count:
				if mode[i] == PERCHED and (best < 0 or sgn * pos[i].dot(right) > sgn * pos[best].dot(right)):
					best = i
			if best >= 0:
				var k := _free_perch(best, true)
				if k >= 0:
					fly_to(best, perches[k], k)
			return true
		"call":
			life.call_out("bird_call", "bird", pos[rng.randi() % count])
			return true
	return false


func positions() -> Array:
	return pos.duplicate()


func radius() -> float:
	return SPAN * 0.5 * size()
