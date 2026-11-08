extends "res://scripts/env/systems/life/creature.gd"

## A manta ray gliding over (the Bathysphere, since 2026-11-08: "go nuts on the bathysphere", the user): 4 m across
## its wings, dark above and pale below (the body shader's belly), its wings beating slowly (a beat every 5 s) and
## the rest of the time gliding. Now and then (every, default 90 s; or a cue's pass) one comes out of the gloom on one
## side, glides high over the room on a long gentle curve, banking a little into it, and fades into the gloom on the
## other side. Its way: the path's points if the document gives them (first to last), else a chord across a circle
## round the room's middle at `region`'s height, its direction new each time. It never comes down into the sight
## line to the picture (life.keep()) or near the viewer. Slow: 1.4 m/s at most.

const COLOUR := Color(0.13, 0.15, 0.18)
const BELLY := Color(0.82, 0.84, 0.86)
const SPAN := 4.0
const SWIM := 1.4
const BEAT_SECONDS := 5.0
const FADE_SHARE := 0.14

var passing := false
var passes := 0
var next_pass := INF
var _path: Array[Vector3] = []
var _length := 0.0
var _s := 0.0
var _phase := 0.0
var _beat := 0.0
var _pos := Vector3.ZERO
var _dir := Vector3.FORWARD
var _bank := 0.0


static func defaults() -> Dictionary:
	return {"count": 1, "max": 1}


func build() -> void:
	var sh := Shape.new()
	# Weights: the wing's share of the half span (UV.x), so the tips beat and the body stays.
	var w := func(q: Vector3) -> Vector4: return Vector4(clampf(absf(q.x) / (SPAN * 0.5), 0.0, 1.0), 0, 0, 0)
	# The body's outline in plan, nose at -Z: a rounded diamond with swept wings (half span 2 m, chord 1.6 m).
	var half := SPAN * 0.5
	var outline := [Vector3(0, 0, -0.75), Vector3(0.35, 0, -0.7), Vector3(0.9, 0, -0.45), Vector3(1.5, 0, -0.1),
			Vector3(half, 0, 0.18), Vector3(1.45, 0, 0.3), Vector3(0.8, 0, 0.42), Vector3(0.35, 0, 0.6),
			Vector3(0.0, 0, 0.66)]
	# A low ridge down the back: the top surface rises to 0.16 m over the spine.
	var top := func(q: Vector3) -> Vector3: return q + Vector3(0, 0.16 * (1.0 - clampf(absf(q.x) / 0.9, 0.0, 1.0)), 0)
	var bottom := func(q: Vector3) -> Vector3: return q - Vector3(0, 0.05 * (1.0 - clampf(absf(q.x) / 0.9, 0.0, 1.0)), 0)
	var spine := [Vector3(0, 0, -0.75), Vector3(0, 0, -0.3), Vector3(0, 0, 0.2), Vector3(0, 0, 0.66)]
	for sx: float in [-1.0, 1.0]:
		var pts: Array[Vector3] = []
		for q: Vector3 in outline:
			pts.append(Vector3(q.x * sx, q.y, q.z))
		# A fan of triangles from the spine's points to the outline, top and bottom.
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var c: Vector3 = spine[clampi(int(float(i) / (pts.size() - 1) * spine.size()), 0, spine.size() - 1)]
			var ta: Vector3 = top.call(a)
			var tb: Vector3 = top.call(b)
			var tc: Vector3 = top.call(c)
			if sx > 0.0:
				sh.tri(tc, tb, ta, w.call(c), w.call(b), w.call(a))
				sh.tri(bottom.call(c), bottom.call(a), bottom.call(b), w.call(c), w.call(a), w.call(b))
			else:
				sh.tri(tc, ta, tb, w.call(c), w.call(a), w.call(b))
				sh.tri(bottom.call(c), bottom.call(b), bottom.call(a), w.call(c), w.call(b), w.call(a))
		# The two cephalic fins curling forward either side of the mouth.
		var f0 := Vector3(0.22 * sx, 0.02, -0.72)
		sh.tri(f0, Vector3(0.3 * sx, -0.02, -1.0), Vector3(0.12 * sx, 0.0, -0.95))
	# The thin tail.
	sh.tri(Vector3(-0.03, 0.03, 0.62), Vector3(0.03, 0.03, 0.62), Vector3(0.0, 0.02, 1.9))
	var m := body_material(life.colour_or(COLOUR), {"flap": 0.35, "belly": 1.0, "belly_colour": BELLY,
			"spill": 0.8})
	single(sh.commit(), m, "Ray")
	next_pass = _gap() * 0.5
	_place()


func _gap() -> float:
	var every: float = life.every_or(90.0)
	return every * rng.randf_range(0.5, 1.5) if every > 0.0 else INF


func param_changed(param: String) -> void:
	if param == "colour" and material != null:
		material.set_shader_parameter("colour", life.colour_or(COLOUR))


## Its way this time: the document's path, or a chord across the room high up, from one side of the gloom to the
## other, bending gently.
func _new_path(side: int) -> void:
	var given: Array[Vector3] = life.path_points()
	if given.size() >= 2:
		_path = given
		if side != 0 and (given[0].x > given[-1].x) != (side > 0):
			_path.reverse()
	else:
		var r: Variant = life.region()
		var c: Vector3 = life.seat_eye()
		var y := 12.0
		var reach := 22.0
		if r is AABB:
			c = (r as AABB).get_center()
			y = c.y
			reach = maxf((r as AABB).size.x, (r as AABB).size.z) * 0.5
		var a := rng.randf_range(0.0, TAU)
		if side != 0:
			a = PI * 0.5 * float(side) + rng.randf_range(-0.6, 0.6)
		var from := Vector3(c.x + sin(a) * reach, y, c.z + cos(a) * reach)
		var to := Vector3(c.x - sin(a) * reach, y + rng.randf_range(-1.5, 1.5), c.z - cos(a) * reach)
		var mid := (from + to) * 0.5 + (to - from).cross(Vector3.UP).normalized() * rng.randf_range(-5.0, 5.0)
		_path = []
		for i in 9:
			var f := float(i) / 8.0
			_path.append(from.lerp(mid, f).lerp(mid.lerp(to, f), f))
	_length = path_length(_path)


func start(side := 0) -> bool:
	if passing:
		return false
	_new_path(side)
	passing = true
	passes += 1
	_s = 0.0
	return true


func step(delta: float) -> void:
	if not passing:
		next_pass -= delta
		if next_pass <= 0.0:
			next_pass = _gap()
			start()
	else:
		_s += SWIM * speed() * delta
		if _s > _length:
			passing = false
		# A slow beat now and then, gliding between.
		_beat += delta / BEAT_SECONDS
		_phase = fmod(_phase + delta / BEAT_SECONDS, 1.0)
	_place()


func _place() -> void:
	var f := 0.0
	if passing and _length > 0.0:
		var a: Array = along(_path, clampf(_s, 0.0, _length))
		var ahead: Array = along(_path, clampf(_s + 1.5, 0.0, _length))
		var want: Vector3 = life.keep(a[0], float(life.params["keep_out"]) + 1.5)
		_pos = want
		var d: Vector3 = (ahead[0] as Vector3) - (a[0] as Vector3)
		if d.length() > 0.01:
			var turn := _dir.signed_angle_to(d.normalized(), Vector3.UP)
			_bank = lerpf(_bank, clampf(-turn * 6.0, -0.35, 0.35), 0.05)
			_dir = d.normalized()
		var done := clampf(_s / _length, 0.0, 1.0)
		f = clampf(minf(done, 1.0 - done) / FADE_SHARE, 0.0, 1.0)
	# Beating for the first half of each slow cycle, gliding for the rest.
	var amount := clampf(sin(_beat * TAU * 0.5) * 2.0, 0.0, 1.0)
	put_single(facing(_pos, _dir, size(), _bank), Color(1, 1, 1, f * life.fade), Color(_phase, amount, 0.0, 0.0))


func act(action: String, args: Dictionary) -> bool:
	match action:
		"pass":
			start(side_arg(args))
			return true
	return false


func positions() -> Array:
	return [_pos] if passing else []


func radius() -> float:
	return SPAN * 0.5 * size()
