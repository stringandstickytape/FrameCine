extends Node

## The room light in effect: the user's room light (main.room_light, remembered per environment) times factors that
## features set, each faded over its own time. So the sleep timer (#17) and "room light follows playback" (#20) can
## both dim the room without fighting over it, and the user's setting is never overwritten.
##
##   set_factor(name, value, fade_seconds)   0..1 dims (1 = no effect), up to 4 brightens (the film's flashes, #81);
##                                           fades from where it is now
##   get_factor(name)                        the factor's current (faded) value
##   effective()                             main.room_light x every factor
## Applied through the environment's apply_light() only when something changes. If the user changes the room light
## or the environment (main.set_room_light / set_environment apply it directly), the product is put back next frame.

var main: Node3D
## name -> [current, target, rate per second]
var _factors := {}
var _applied := -1.0
var _env: Node = null
var _user := -1.0


func set_factor(factor_name: String, value: float, fade_seconds := 0.0) -> void:
	value = clampf(value, 0.0, 4.0)
	var cur: float = _factors[factor_name][0] if _factors.has(factor_name) else 1.0
	var rate := absf(value - cur) / fade_seconds if fade_seconds > 0.0 else INF
	_factors[factor_name] = [cur, value, rate]
	_step(0.0)


func get_factor(factor_name: String) -> float:
	return float(_factors[factor_name][0]) if _factors.has(factor_name) else 1.0


## True while any factor is still fading.
func is_fading() -> bool:
	for f: Array in _factors.values():
		if not is_equal_approx(f[0], f[1]):
			return true
	return false


func effective() -> float:
	var v: float = main.room_light
	for f: Array in _factors.values():
		v *= float(f[0])
	return v


func _process(delta: float) -> void:
	_step(delta)


func _step(delta: float) -> void:
	for f: Array in _factors.values():
		if not is_equal_approx(f[0], f[1]):
			f[0] = move_toward(f[0], f[1], f[2] * delta) if f[2] != INF else f[1]
	var v := effective()
	if main.env == null:
		return
	if main.env != _env or not is_equal_approx(main.room_light, _user) or not is_equal_approx(v, _applied):
		_env = main.env
		_user = main.room_light
		_applied = v
		main.env.apply_light(v)
