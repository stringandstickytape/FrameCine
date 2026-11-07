extends "res://scripts/env/systems/life/creature.gd"

## An occasional deer (the reclaimed cinema): now and then (every, 300 s on average by default; 0: only when a cue
## calls pass) it comes out of the dark at one end of its path, walks along it, stops to graze once or twice, looks up
## and walks on, and fades into the dark at the far end. It never grazes in the sight line and goes through it at a
## trot. By default its way runs past the viewer's left, well clear of the picture. pass: a visit now (args: side, the
## end it comes from: left or right of the viewer; seconds is ignored).

const COLOUR := Color(0.45, 0.32, 0.2)
const WALK := 0.7
const FADE_METRES := 3.0
const DIMS := {"length": 1.1, "height": 1.15, "leg": 0.75, "width": 0.32, "neck": 0.4, "head": 0.28, "tail": 0.12,
		"ears": 0.12}
enum { AWAY, WALKING, GRAZING }

var path: Array[Vector3] = []
var length := 0.0
var state := AWAY
var s := 0.0
var way := 1.0
var phase := 0.0
var pose := 0.0
var timer := 0.0
var grazes: Array = []
var next_visit := 0.0
## Visits so far (tests).
var visits := 0
var _pos := Vector3.ZERO


static func defaults() -> Dictionary:
	return {"count": 1, "max": 1}


func build() -> void:
	path = life.path_points()
	if path.size() < 2:
		var f: Vector3 = life.forward()
		var side := f.cross(Vector3.UP).normalized()
		var ground: Vector3 = life.seat_eye() + Vector3.DOWN * life.EYE_HEIGHT
		path = [ground - side * 5.5 + f * 9.0, ground - side * 5.5 - f * 3.0]
	length = path_length(path)
	var leg := float(DIMS["leg"])
	var body_h := float(DIMS["height"]) - leg
	var z0 := -float(DIMS["length"]) * 0.5
	var m := body_material(life.colour_or(COLOUR), {"stride": 0.18, "sway": 0.03, "waves": 12.0, "graze": 1.0,
			"pivot_neck": Vector3(0, leg + body_h * 0.8, z0 + 0.1), "spill": 0.9})
	single(quadruped(DIMS), m, "Deer")
	next_visit = _gap()
	_place()


func _gap() -> float:
	var every: float = life.every_or(300.0)
	return every * rng.randf_range(0.5, 1.5) if every > 0.0 else INF


func param_changed(param: String) -> void:
	if param == "colour" and material != null:
		material.set_shader_parameter("colour", life.colour_or(COLOUR))


func walker_in_view() -> bool:
	return state != AWAY and life.in_view(_pos + Vector3.UP * 0.9, 0.0)


## A visit: from the start of the path (way 1) or its end (way -1).
func visit(from_end := false) -> void:
	if state != AWAY:
		return
	state = WALKING
	visits += 1
	way = -1.0 if from_end else 1.0
	s = length if from_end else 0.0
	grazes.clear()
	for k in rng.randi_range(1, 2):
		grazes.append(length * rng.randf_range(0.3, 0.7))
	grazes.sort()
	if from_end:
		grazes.reverse()


func step(delta: float) -> void:
	match state:
		AWAY:
			if float(life.params["activity"]) > 0.05:
				next_visit -= delta
			if next_visit <= 0.0:
				next_visit = _gap()
				visit(rng.randf() < 0.5)
		WALKING:
			pose = move_toward(pose, 0.0, delta / 1.5)
			if pose <= 0.0:
				var in_view := walker_in_view()
				var v: float = WALK * speed() * (life.THROUGH_SPEED if in_view else 1.0)
				s += way * v * delta
				phase = fmod(phase + delta * v / 0.9, 1.0)
				if not grazes.is_empty() and (s - float(grazes[0])) * way >= 0.0:
					grazes.pop_front()
					if not in_view:
						state = GRAZING
						timer = rng.randf_range(6.0, 15.0)
				if s < 0.0 or s > length:
					state = AWAY
		GRAZING:
			pose = move_toward(pose, 1.0, delta / 1.5)
			timer -= delta
			if timer <= 0.0:
				state = WALKING
	_place()


func _fade() -> float:
	if state == AWAY:
		return 0.0
	return clampf(minf(s, length - s) / FADE_METRES, 0.0, 1.0)


func _place() -> void:
	var a: Array = along(path, clampf(s, 0.0, length))
	_pos = a[0]
	var moving := 1.0 if state == WALKING and pose <= 0.0 else 0.0
	put_single(facing(_pos, (a[1] as Vector3) * way, size()), Color(1, 1, 1, _fade() * life.fade),
			Color(phase, moving, 0.0, pose))


func act(action: String, args: Dictionary) -> bool:
	if action != "pass":
		return false
	var side := side_arg(args)
	if side == 0:
		visit(rng.randf() < 0.5)
	else:
		# The end on that side of the viewer (along the screen's right).
		var right: Vector3 = life.screen().basis.x
		var start_right := path[0].dot(right) > path[-1].dot(right)
		visit(start_right != (side > 0))
	return true


func positions() -> Array:
	return [] if state == AWAY else [_pos + Vector3.UP * 0.9]


func radius() -> float:
	return 0.8 * size()
