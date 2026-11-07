extends "res://scripts/env/systems/life/creature.gd"

## Glowing deep-sea creatures (the bathysphere): small bells, 35 cm, glowing at their rims, pulsing slowly (a beat
## every two or three seconds) and swimming on each beat. attraction draws them to the screen's light: each has its
## own place on a ring round the picture, just clear of the sight line, in front of the screen or behind it (outside
## the glass); bound to film.brightness, they gather in a bright scene. Their colour can follow film.colour.

const BELL := 0.17
const SWIM := 0.15
const COLOUR := Color(0.35, 0.75, 1.0)

var pos: Array[Vector3] = []
var vel: Array[Vector3] = []
var home: Array[Vector3] = []
var ring := PackedVector3Array()
var phase := PackedFloat32Array()
var rate := PackedFloat32Array()
var fades := PackedFloat32Array()
var _box := AABB()
var _dart := 0.0


static func defaults() -> Dictionary:
	return {"count": 18}


func build() -> void:
	var r: Variant = life.region()
	_box = r if r is AABB else _around_screen(4.0, 3.0, 3.0)
	var s := Shape.new()
	var sides := 8
	var rings: Array = []
	for deg: float in [0.0, 30.0, 60.0, 90.0, 105.0]:
		var phi := deg_to_rad(deg)
		rings.append([sin(phi) * BELL, cos(phi) * BELL * 0.8, deg / 105.0])
	for k in range(rings.size() - 1):
		for i in sides:
			var a0 := TAU * float(i) / float(sides)
			var a1 := TAU * float(i + 1) / float(sides)
			var p := func(rr: Array, a: float) -> Vector3:
				return Vector3(cos(a) * float(rr[0]), float(rr[1]), sin(a) * float(rr[0]))
			var w0 := Vector4(0, rings[k][2], 0, 0)
			var w1 := Vector4(0, rings[k + 1][2], 0, 0)
			if k == 0:
				s.tri(p.call(rings[k], a0), p.call(rings[k + 1], a1), p.call(rings[k + 1], a0), w0, w1, w1)
			else:
				s.tri(p.call(rings[k], a0), p.call(rings[k], a1), p.call(rings[k + 1], a1), w0, w0, w1)
				s.tri(p.call(rings[k], a0), p.call(rings[k + 1], a1), p.call(rings[k + 1], a0), w0, w1, w1)
	# Four trailing threads under the bell.
	for i in 4:
		var a := TAU * float(i) / 4.0 + 0.4
		var top := Vector3(cos(a) * BELL * 0.5, -0.02, sin(a) * BELL * 0.5)
		var w := Vector4(0, 1, 0, 0)
		s.tri(top - Vector3(0.01, 0, 0), top + Vector3(0.01, 0, 0), top + Vector3(0.0, -BELL * 2.2, 0.0), w, w, w)
	var m := glow_material(life.colour_or(COLOUR), 1)
	multimesh(s.commit(), count, m, WIDE, "Jellies")
	for i in count:
		var a := TAU * (float(i) + rng.randf() * 0.6) / float(maxi(count, 1))
		var half: Vector2 = life.screen_half()
		var reach := float(life.params["keep_out"]) + rng.randf_range(0.4, 2.0)
		ring.append(Vector3(cos(a) * (half.x + reach), sin(a) * (half.y + reach), rng.randf_range(-1.5, 2.5)))
		var p := _clamp(life.keep(random_in(_box)))
		pos.append(p)
		home.append(p)
		vel.append(Vector3.ZERO)
		phase.append(rng.randf())
		rate.append(rng.randf_range(0.35, 0.5))
		fades.append(1.0 if shown(i) else 0.0)


## A box round the screen, wider by dx, dy and dz either side (the screen's frame), as an AABB in the room's.
func _around_screen(dx: float, dy: float, dz: float) -> AABB:
	var sc: Transform3D = life.screen()
	var half: Vector2 = life.screen_half()
	var box := AABB(sc.origin, Vector3.ZERO)
	for x: float in [-half.x - dx, half.x + dx]:
		for y: float in [-half.y - dy, half.y + dy]:
			for z: float in [-dz, dz]:
				box = box.expand(sc * Vector3(x, y, z))
	return box


func _clamp(p: Vector3) -> Vector3:
	return Vector3(clampf(p.x, _box.position.x, _box.end.x), clampf(p.y, _box.position.y, _box.end.y),
			clampf(p.z, _box.position.z, _box.end.z))


func param_changed(param: String) -> void:
	if material == null:
		return
	if param == "glow":
		material.set_shader_parameter("glow", float(life.params["glow"]))
	elif param == "colour":
		material.set_shader_parameter("colour", life.colour_or(COLOUR))


## Where one wants to be: its own spot in the region drawn towards its place on the ring round the picture.
func target(i: int) -> Vector3:
	var on_ring: Vector3 = life.screen() * ring[i]
	return life.keep(_clamp(home[i].lerp(on_ring, float(life.params["attraction"]))))


func step(delta: float) -> void:
	_dart = maxf(_dart - delta, 0.0)
	var top := SWIM * speed()
	for i in count:
		if pos[i].distance_to(home[i]) < 0.3 or rng.randf() < delta * 0.03:
			home[i] = _clamp(life.keep(random_in(_box)))
		phase[i] = fmod(phase[i] + delta * rate[i], 1.0)
		var beat := maxf(0.0, sin(phase[i] * TAU))
		var to := target(i) - pos[i]
		var want := to.normalized() * top * (0.3 + 0.9 * beat) if to.length() > 0.1 else Vector3.ZERO
		if _dart > 0.0:
			want = (pos[i] - life.screen().origin).normalized() * top * 4.0
		vel[i] = vel[i].lerp(want, clampf(delta * 1.5, 0.0, 1.0))
		pos[i] = life.keep(pos[i] + vel[i] * delta)
		fades[i] = fade_to(fades[i], shown(i), delta, 2.0)
		var tilt := Basis()
		var side := Vector3.UP.cross(vel[i])
		if side.length() > 1e-4:
			tilt = Basis(side.normalized(), clampf(vel[i].length() / maxf(top, 0.01), 0.0, 1.0) * 0.35)
		put(i, Transform3D(tilt.scaled(Vector3.ONE * size()), pos[i]), Color(1, 1, 1, fades[i] * life.fade),
				Color(phase[i], 1.0, 0.75 + 0.25 * beat, 0.0))
	flush()


func act(action: String, _args: Dictionary) -> bool:
	match action:
		"scatter":
			_dart = 2.0
			return true
		"settle":
			for i in count:
				vel[i] = Vector3.ZERO
			return true
	return false


func positions() -> Array:
	var out: Array = []
	for i in count:
		if fades[i] > 0.0:
			out.append(pos[i])
	return out


func radius() -> float:
	return BELL * size()
