extends "res://scripts/env/systems/life/creature.gd"

## A cat on a wall (the Athens rooftop): dark, 42 cm long, walking the path (the wall's top, first point to last) to
## a spot, sitting a while (its head bowed a little, as if washing), getting up and walking on, turning round at the
## ends. It never sits in the sight line and goes through it at a trot. settle: it sits now; pass: it walks the wall
## end to end; scatter: it trots off to the far end; call: a purr (an event; a sound only where the synthesiser has one).
## Sitting down it purrs too.
## It faces the way it walks. At an end, or wherever its way bends by more than TURN_AT, it stops and turns on the spot
## (TURN_SECONDS, eased, its legs stepping round); a gentler bend it steers through as it walks.

const COLOUR := Color(0.24, 0.21, 0.19)
const WALK := 0.35
## A turn on the spot: from this bend (radians) up; it takes TURN_SECONDS[0] (a small turn) to [1] (turning round).
const TURN_AT := 1.0
const TURN_SECONDS: Array[float] = [0.35, 0.55]
## A quick turn (it hurries, or turns in the sight line).
const TURN_QUICK := 0.3
## Steering through a gentle bend as it walks (radians per second).
const STEER := 3.0
## Its legs while it turns on the spot: shorter steps than walking.
const TURN_STRIDE := 0.6
const DIMS := {"length": 0.42, "height": 0.26, "leg": 0.13, "width": 0.12, "neck": 0.0, "head": 0.1, "tail": 0.28,
		"ears": 0.045}
enum { WALKING, SITTING }

var path: Array[Vector3] = []
var length := 0.0
var s := 0.0
var goal := 0.0
var state := WALKING
var timer := 0.0
var pose := 0.0
var phase := 0.0
var face := Vector3.FORWARD
var hurry := 1.0
## Where it faces: the angle about up from -Z (Vector3.FORWARD), and its pitch along a sloping way.
var yaw := 0.0
var slope := 0.0
## Turning on the spot: from, to (radians), how far through (0..1), how long (s).
var turning := false
var _turn_from := 0.0
var _turn_to := 0.0
var _turn_t := 0.0
var _turn_len := 0.5
var _gait := 0.0
## Times it sat down, times it turned on the spot (tests).
var sits := 0
var turns := 0
var _pos := Vector3.ZERO
var _tan := Vector3.FORWARD


static func defaults() -> Dictionary:
	return {"count": 1, "max": 1}


func build() -> void:
	path = life.path_points()
	if path.size() < 2:
		var f: Vector3 = life.forward()
		var side := f.cross(Vector3.UP).normalized()
		var e: Vector3 = life.seat_eye() + Vector3.DOWN * 0.4
		path = [e - side * 3.0 + f * 1.0, e - side * 3.0 + f * 6.0]
	length = path_length(path)
	var leg := float(DIMS["leg"])
	var body_h := float(DIMS["height"]) - leg
	var z1 := float(DIMS["length"]) * 0.5
	var lw := float(DIMS["width"]) * 0.22
	var m := body_material(life.colour_or(COLOUR), {"stride": 0.05, "sway": 0.05, "waves": 10.0, "sit": 0.75,
			"pivot_rear": Vector3(0, leg + body_h * 0.3, z1 - lw * 1.2), "graze": 0.25,
			"pivot_neck": Vector3(0, leg + body_h, -z1 + 0.04), "spill": 0.9})
	single(quadruped(DIMS), m, "Cat")
	s = rng.randf() * length
	goal = rng.randf() * length
	_at(s)
	var d := _tan * (signf(goal - s) if goal != s else 1.0)
	yaw = yaw_of(d)
	slope = d.y
	_place(0.0)


func param_changed(param: String) -> void:
	if param == "colour" and material != null:
		material.set_shader_parameter("colour", life.colour_or(COLOUR))


func walker_in_view() -> bool:
	return life.in_view(_pos + Vector3.UP * 0.15, radius())


func step(delta: float) -> void:
	var in_view := walker_in_view()
	match state:
		WALKING:
			pose = move_toward(pose, 0.0, delta / 1.0)
			_gait = 0.0
			if pose <= 0.0:
				var v: float = WALK * speed() * hurry * (life.THROUGH_SPEED if in_view else 1.0)
				var dir := signf(goal - s)
				var want := _tan * dir
				if not turning and dir != 0.0:
					var bend := angle_difference(yaw, yaw_of(want))
					if absf(bend) > TURN_AT:
						_start_turn(bend, in_view)
				if turning:
					# On the spot: eased round, the legs stepping at the walk's cadence.
					_turn_t = minf(_turn_t + delta / _turn_len, 1.0)
					yaw = lerpf(_turn_from, _turn_to, smoothstep(0.0, 1.0, _turn_t))
					slope = move_toward(slope, want.y, delta / _turn_len)
					phase = fmod(phase + delta * WALK * speed() / 0.25, 1.0)
					_gait = TURN_STRIDE
					if _turn_t >= 1.0:
						turning = false
						yaw = wrapf(_turn_to, -PI, PI)
				else:
					if dir != 0.0:
						yaw = rotate_toward(yaw, yaw_of(want), STEER * delta)
						slope = move_toward(slope, want.y, STEER * delta)
					s = move_toward(s, goal, v * delta)
					phase = fmod(phase + delta * v / 0.25, 1.0)
					_gait = 1.0
					if absf(goal - s) < 0.01:
						_gait = 0.0
						hurry = 1.0
						if not in_view and rng.randf() < 0.75:
							_sit()
						else:
							_new_goal()
		SITTING:
			pose = move_toward(pose, 1.0, delta / 1.2)
			timer -= delta
			if timer <= 0.0 or in_view:
				state = WALKING
				_new_goal()
	_place(delta)


func _place(_delta: float) -> void:
	_at(s)
	var h := sqrt(maxf(0.0, 1.0 - slope * slope))
	face = Vector3(-sin(yaw) * h, slope, -cos(yaw) * h)
	var moving := _gait if state == WALKING else 0.0
	put_single(facing(_pos, face, size()), Color(1, 1, 1, life.fade), Color(phase, moving, 0.0, pose))


## The angle about up from -Z of a direction (facing()'s: -Z along it).
static func yaw_of(d: Vector3) -> float:
	return atan2(-d.x, -d.z)


## A turn on the spot by bend radians: turning round (a bend of about half a turn) goes either way.
func _start_turn(bend: float, in_view: bool) -> void:
	var b := bend
	if absf(absf(b) - PI) < 0.05:
		b = PI * (1.0 if rng.randf() < 0.5 else -1.0)
	turning = true
	turns += 1
	_turn_from = yaw
	_turn_to = yaw + b
	_turn_t = 0.0
	var f := clampf((absf(b) - TURN_AT) / (PI - TURN_AT), 0.0, 1.0)
	_turn_len = lerpf(TURN_SECONDS[0], TURN_SECONDS[1], f)
	if hurry > 1.0 or in_view:
		_turn_len = TURN_QUICK


## Where along the way s is, and the way's direction there (_pos, _tan), without an array (creature.along()'s).
func _at(d: float) -> void:
	var left := maxf(d, 0.0)
	var last := path.size() - 2
	for i in path.size() - 1:
		var a: Vector3 = path[i]
		var b: Vector3 = path[i + 1]
		var seg := a.distance_to(b)
		if left <= seg or i == last:
			_tan = (b - a).normalized()
			_pos = a + _tan * minf(left, seg)
			return
		left -= seg


func _sit() -> void:
	state = SITTING
	timer = rng.randf_range(15.0, 60.0)
	sits += 1
	life.call_out("purr", "purr", _pos + Vector3.UP * 0.2)


func _new_goal() -> void:
	var g := rng.randf() * length
	if absf(g - s) < 1.0:
		g = fmod(s + length * 0.5, length)
	goal = g


func act(action: String, args: Dictionary) -> bool:
	match action:
		"settle":
			if not walker_in_view():
				_sit()
			return true
		"pass", "scatter":
			state = WALKING
			goal = length if s < length * 0.5 else 0.0
			hurry = 2.0 if action == "scatter" else 1.0
			return true
		"call":
			life.call_out("purr", "purr", _pos + Vector3.UP * 0.2)
			return true
	return false


func positions() -> Array:
	return [_pos + Vector3.UP * 0.15]


func radius() -> float:
	return 0.3 * size()
