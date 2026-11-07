extends "res://scripts/env/systems/life/creature.gd"

## A cat on a wall (the Athens rooftop): dark, 42 cm long, walking the path (the wall's top, first point to last) to
## a spot, sitting a while (its head bowed a little, as if washing), getting up and walking on, turning round at the
## ends. It never sits in the sight line and goes through it at a trot. settle: it sits now; pass: it walks the wall
## end to end; scatter: it trots off to the far end; call: a purr (an event; a sound only where the synthesiser has one).
## Sitting down it purrs too.

const COLOUR := Color(0.24, 0.21, 0.19)
const WALK := 0.35
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
## Times it sat down (tests).
var sits := 0
var _pos := Vector3.ZERO


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
			if pose <= 0.0:
				var v: float = WALK * speed() * hurry * (life.THROUGH_SPEED if in_view else 1.0)
				var dir := signf(goal - s)
				s = move_toward(s, goal, v * delta)
				phase = fmod(phase + delta * v / 0.25, 1.0)
				if absf(goal - s) < 0.01:
					hurry = 1.0
					if not in_view and rng.randf() < 0.75:
						_sit()
					else:
						_new_goal()
				elif dir != 0.0:
					var d: Vector3 = along(path, s)[1] * dir
					face = face.lerp(d, clampf(delta * 3.0, 0.0, 1.0)).normalized()
		SITTING:
			pose = move_toward(pose, 1.0, delta / 1.2)
			timer -= delta
			if timer <= 0.0 or in_view:
				state = WALKING
				_new_goal()
	_place(delta)


func _place(_delta: float) -> void:
	_pos = along(path, s)[0]
	var moving := 1.0 if state == WALKING and pose <= 0.0 and absf(goal - s) > 0.01 else 0.0
	put_single(facing(_pos, face, size()), Color(1, 1, 1, life.fade), Color(phase, moving, 0.0, pose))


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
