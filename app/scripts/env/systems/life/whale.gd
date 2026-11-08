extends "res://scripts/env/systems/life/creature.gd"

## A whale passing (the bathysphere, in a quiet scene): 14 m long, dark, with long fins, coming out of the gloom at one
## end of its way, swimming slowly along it with its flukes beating and fading into the gloom at the other. It comes
## only when called: a cue on film.quiet with a long cooldown (so it is rare) calls whale.pass; every (default 0) can
## send it on its own too. By default its way runs high behind the screen, over the picture as the viewer sees it:
## never between the viewer and the film. A third of the way along it sings (the synthesiser's whale, from where it is,
## with voice on). pass: args side (left or right: where it comes from) and seconds (how long the pass takes).

const COLOUR := Color(0.18, 0.22, 0.28)
const LENGTH := 14.0
const SWIM := 1.6
const BEAT_HZ := 0.12
const FADE_SHARE := 0.12
const SONG_AT := 0.35

var path: Array[Vector3] = []
var length := 0.0
var passing := false
var s := 0.0
var way := 1.0
var rate := SWIM
var phase := 0.0
var sang := false
var next_pass := INF
## Passes so far (tests).
var passes := 0
var _pos := Vector3.ZERO


static func defaults() -> Dictionary:
	return {"count": 1, "max": 1}


func build() -> void:
	path = life.path_points()
	if path.size() < 2:
		var sc: Transform3D = life.screen()
		var half: Vector2 = life.screen_half()
		path = [sc * Vector3(-50.0, half.y + 9.0, -28.0), sc * Vector3(50.0, half.y + 6.0, -28.0)]
	length = path_length(path)
	var sh := Shape.new()
	var wave := func(p: Vector3) -> Vector4: return Vector4(0, 0, pow(clampf((p.z + 0.1) / 0.6, 0.0, 1.0), 1.5), 0)
	# A long, deep body with a broad flat head, the throat lower than the back, narrowing to a slim tail stock
	# (2026-11-08: twelve rings of ten sides, where it was seven of eight).
	sh.loft([[-0.5, 0.012, 0.01, -0.01], [-0.47, 0.05, 0.035, -0.012], [-0.42, 0.08, 0.06, -0.015],
			[-0.34, 0.105, 0.085, -0.015], [-0.24, 0.12, 0.1, -0.012], [-0.12, 0.122, 0.102, -0.005],
			[0.0, 0.112, 0.095, 0.0], [0.1, 0.09, 0.078, 0.005], [0.2, 0.062, 0.056, 0.008],
			[0.3, 0.035, 0.034, 0.008], [0.38, 0.018, 0.02, 0.006], [0.44, 0.01, 0.012, 0.004]], 10, wave)
	var fw := Vector4(0, 0, 1, 0)
	for sx: float in [-1.0, 1.0]:
		# Broad flukes, swept back, notched in the middle.
		sh.tri(Vector3(0, 0, 0.42), Vector3(sx * 0.16, 0.0, 0.5), Vector3(sx * 0.11, 0.0, 0.53), fw, fw, fw)
		sh.tri(Vector3(0, 0, 0.42), Vector3(sx * 0.11, 0.0, 0.53), Vector3(sx * 0.02, 0.0, 0.5), fw, fw, fw)
		sh.tri(Vector3(0, 0, 0.42), Vector3(sx * 0.02, 0.0, 0.5), Vector3(0, 0, 0.48), fw, fw, fw)
		# A long pectoral fin each side, a third of the body, swept back and down, with a scalloped leading edge.
		var root_a := Vector3(sx * 0.1, -0.05, -0.27)
		var root_b := Vector3(sx * 0.1, -0.05, -0.19)
		var pts := [root_a, Vector3(sx * 0.18, -0.09, -0.25), Vector3(sx * 0.26, -0.13, -0.2),
				Vector3(sx * 0.33, -0.16, -0.13), Vector3(sx * 0.38, -0.18, -0.07), Vector3(sx * 0.3, -0.15, -0.1),
				Vector3(sx * 0.2, -0.1, -0.15), root_b]
		for i in range(1, pts.size() - 2):
			sh.tri(root_a, pts[i], pts[i + 1])
		sh.tri(root_a, pts[-2], root_b)
		# A small dorsal fin two thirds back.
		sh.tri(Vector3(0, 0.08, 0.14), Vector3(0, 0.12, 0.2), Vector3(0, 0.065, 0.22))
	var m := body_material(life.colour_or(COLOUR), {"sway": 0.035, "waves": 4.0, "sway_up": true, "spill": 0.6,
			"belly": 0.7, "belly_colour": Color(0.62, 0.66, 0.68)})
	single(sh.commit(), m, "Whale")
	next_pass = _gap()
	_place()


func _gap() -> float:
	var every: float = life.every_or(0.0)
	return every * rng.randf_range(0.5, 1.5) if every > 0.0 else INF


func param_changed(param: String) -> void:
	if param == "colour" and material != null:
		material.set_shader_parameter("colour", life.colour_or(COLOUR))


func walker_in_view() -> bool:
	return passing and life.in_view(_pos, 0.0)


## A pass: from the path's first point (way 1) or its last, over seconds (0: at its own pace).
func start(from_end := false, seconds := 0.0) -> bool:
	if passing:
		return false
	passing = true
	passes += 1
	sang = false
	way = -1.0 if from_end else 1.0
	s = length if from_end else 0.0
	rate = length / seconds if seconds > 0.0 else SWIM * speed()
	return true


func step(delta: float) -> void:
	if not passing:
		next_pass -= delta
		if next_pass <= 0.0:
			next_pass = _gap()
			start(rng.randf() < 0.5)
	else:
		var v: float = rate * (life.THROUGH_SPEED if walker_in_view() else 1.0)
		s += way * v * delta
		phase = fmod(phase + delta * BEAT_HZ * maxf(rate / SWIM, 0.3), 1.0)
		var done := (s if way > 0.0 else length - s) / maxf(length, 0.01)
		if not sang and done >= SONG_AT:
			sang = true
			life.call_out("whale_song", "whale", _pos)
		if s < 0.0 or s > length:
			passing = false
	_place()


func _place() -> void:
	var a: Array = along(path, clampf(s, 0.0, length))
	_pos = a[0]
	var f := 0.0
	if passing:
		var done := clampf(s / maxf(length, 0.01), 0.0, 1.0)
		f = clampf(minf(done, 1.0 - done) / FADE_SHARE, 0.0, 1.0)
	put_single(facing(_pos, (a[1] as Vector3) * way, LENGTH * size()), Color(1, 1, 1, f * life.fade),
			Color(phase, 1.0, 0.0, 0.0))


func act(action: String, args: Dictionary) -> bool:
	match action:
		"pass":
			var side := side_arg(args)
			var from_end := rng.randf() < 0.5
			if side != 0:
				var right: Vector3 = life.screen().basis.x
				var start_right := path[0].dot(right) > path[-1].dot(right)
				from_end = start_right != (side > 0)
			start(from_end, float(args.get("seconds", 0.0)))
			return true
		"call":
			life.call_out("whale_song", "whale", _pos)
			return true
	return false


func positions() -> Array:
	return [_pos] if passing else []


func radius() -> float:
	return LENGTH * 0.5 * size()
