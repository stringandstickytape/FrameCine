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
	sh.loft([[-0.5, 0.01, 0.01, 0.0], [-0.45, 0.06, 0.05, 0.0], [-0.3, 0.1, 0.085, 0.0], [-0.1, 0.11, 0.09, 0.0],
			[0.1, 0.085, 0.07, 0.0], [0.3, 0.04, 0.035, 0.0], [0.42, 0.015, 0.015, 0.0]], 8, wave)
	var fw := Vector4(0, 0, 1, 0)
	for sx: float in [-1.0, 1.0]:
		# Flukes, and a long fin each side.
		sh.tri(Vector3(0, 0, 0.4), Vector3(sx * 0.13, 0, 0.5), Vector3(sx * 0.04, 0, 0.47), fw, fw, fw)
		sh.tri(Vector3(0, 0, 0.4), Vector3(sx * 0.04, 0, 0.47), Vector3(0, 0, 0.45), fw, fw, fw)
		sh.tri(Vector3(sx * 0.09, -0.04, -0.26), Vector3(sx * 0.32, -0.09, -0.12), Vector3(sx * 0.09, -0.04, -0.18))
	var m := body_material(life.colour_or(COLOUR), {"sway": 0.035, "waves": 4.0, "sway_up": true, "spill": 0.6})
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
