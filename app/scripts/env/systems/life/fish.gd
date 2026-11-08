extends "res://scripts/env/systems/life/creature.gd"

## A school of fish (the bathysphere, outside the glass): silver, 28 cm, each keeping its place in a loose school
## whose centre wanders the region. attraction draws the school towards the screen (the region's nearest point to the
## picture's middle): bound to film.brightness, they come closer in a bright scene and drift off in a dark one. They
## take the screen's light on their flanks (the room's spill). scatter: they dart away and gather again; pass: the
## school sweeps along the region to one end; settle: they slow. With `schooling` (since 2026-11-08) the school draws
## in and stretches along its way, and each fish keeps its place relative to where the school was a moment before,
## the later the further back it swims: a turn starts at the leaders and ripples back through the school. Cheap: one
## lookup in a short history a fish, no neighbour search.

const LENGTH := 0.28
const SWIM := 0.8
const COLOUR := Color(0.55, 0.62, 0.7)

var pos: Array[Vector3] = []
var vel: Array[Vector3] = []
var slot: Array[Vector3] = []
var phase := PackedFloat32Array()
var fades := PackedFloat32Array()
var centre := Vector3.ZERO
var centre_vel := Vector3.ZERO
var heading := Vector3.FORWARD
var _box := AABB()
var _wander := Vector3.ZERO
var _wander_for := 0.0
var _dart := 0.0
var _slow := 0.0
var _t := 0.0
var _spread := 1.0
## Schooling: the school's recent centres and turns, newest first.
var _history: Array = []
var _hist_t := 0.0
const HISTORY_STEP := 0.1
## Seconds the last fish of a schooling school (schooling 1) follows behind its leaders' turn.
const LAG := 2.4


static func defaults() -> Dictionary:
	return {"count": 48}


func build() -> void:
	var r: Variant = life.region()
	_box = r if r is AABB else life.around_viewer(10.0, -0.5, 4.0, 12.0, 2.0)
	var s := Shape.new()
	var wave := func(p: Vector3) -> Vector4: return Vector4(0, 0, clampf((p.z + 0.05) / 0.22, 0.0, 1.0), 0)
	s.loft([[-0.14, 0.003, 0.004, 0.0], [-0.1, 0.02, 0.035, 0.0], [0.0, 0.025, 0.045, 0.0], [0.08, 0.012, 0.02, 0.0],
			[0.12, 0.004, 0.008, 0.0]], 4, wave)
	var tw := Vector4(0, 0, 1, 0)
	s.tri(Vector3(0, 0, 0.11), Vector3(0, 0.045, 0.17), Vector3(0, 0, 0.15), tw, tw, tw)
	s.tri(Vector3(0, 0, 0.11), Vector3(0, 0, 0.15), Vector3(0, -0.045, 0.17), tw, tw, tw)
	multimesh(s.commit(), count, body_material(life.colour_or(COLOUR), {"sway": 0.03, "waves": 20.0,
			"spill": 1.3}), WIDE, "Fish")
	var schooling := float(life.params.get("schooling", 0.0))
	var spread := 0.45 * pow(float(count), 1.0 / 3.0) * size() * lerpf(1.0, 0.6, schooling)
	_spread = spread
	centre = life.keep(_box.get_center())
	_wander = centre
	for i in count:
		var o := Vector3(rng.randfn(0.0, 1.0), rng.randfn(0.0, 0.5), rng.randfn(0.0, 1.0)).limit_length(2.0) * spread
		# A schooling school is longer than it is wide (along its way: local Z).
		o.z *= lerpf(1.0, 1.9, schooling)
		o.x *= lerpf(1.0, 0.75, schooling)
		slot.append(o)
		pos.append(life.keep(centre + o))
		vel.append(Vector3.ZERO)
		phase.append(rng.randf())
		fades.append(1.0 if shown(i) else 0.0)


func param_changed(param: String) -> void:
	if param == "colour" and material != null:
		material.set_shader_parameter("colour", life.colour_or(COLOUR))


## The region's point nearest the picture's middle, clear of the sight line.
func light_point() -> Vector3:
	var c: Vector3 = life.screen().origin
	return life.keep(Vector3(clampf(c.x, _box.position.x, _box.end.x), clampf(c.y, _box.position.y, _box.end.y),
			clampf(c.z, _box.position.z, _box.end.z)), float(life.params["keep_out"]) + 1.0)


func step(delta: float) -> void:
	_t += delta
	_wander_for -= delta
	_dart = maxf(_dart - delta, 0.0)
	_slow = maxf(_slow - delta, 0.0)
	if _wander_for <= 0.0 or centre.distance_to(_wander) < 0.5:
		_wander = random_in(_box)
		_wander_for = rng.randf_range(6.0, 14.0)
	var top := SWIM * speed() * (0.4 if _slow > 0.0 else 1.0)
	var target := _wander.lerp(light_point(), float(life.params["attraction"]))
	centre_vel = (centre_vel + (target - centre).limit_length(1.0) * delta * 0.6).limit_length(top)
	centre = life.keep(centre + centre_vel * delta, float(life.params["keep_out"]) + 0.8)
	if centre_vel.length() > 0.05:
		heading = heading.lerp(centre_vel.normalized(), clampf(delta * 0.8, 0.0, 1.0)).normalized()
	var turn := Basis.looking_at(heading, Vector3.UP) if absf(heading.y) < 0.98 else Basis()
	var schooling := float(life.params.get("schooling", 0.0))
	if schooling > 0.0:
		_remember(delta, turn)
	for i in count:
		var c_i := centre
		var t_i := turn
		if schooling > 0.0:
			# Where the school was a moment ago: the further back in it this fish swims (its slot's +Z), the later.
			var back := clampf((slot[i].z / maxf(_spread * 1.9, 0.01) + 1.0) * 0.5, 0.0, 1.0)
			var then: Array = _recall(back * LAG * schooling)
			c_i = then[0]
			t_i = then[1]
		var desired := c_i + t_i * (slot[i] * (1.0 + 0.12 * sin(_t * 0.3 + float(i))))
		var steer := (desired - pos[i]) * 1.2 + centre_vel
		if _dart > 0.0:
			steer = (pos[i] - centre).normalized() * top * 3.0
		vel[i] = vel[i].lerp(steer, clampf(delta * 2.0, 0.0, 1.0)).limit_length(top * (3.0 if _dart > 0.0 else 1.6))
		var p := pos[i] + vel[i] * delta
		# Back into the region, gently, and never into the sight line or the viewer's face.
		p = p.lerp(Vector3(clampf(p.x, _box.position.x, _box.end.x), clampf(p.y, _box.position.y, _box.end.y),
				clampf(p.z, _box.position.z, _box.end.z)), clampf(delta * 2.0, 0.0, 1.0))
		pos[i] = life.keep(p)
		phase[i] = fmod(phase[i] + delta * (1.5 + 2.5 * vel[i].length() / maxf(SWIM, 0.01)), 1.0)
		fades[i] = fade_to(fades[i], shown(i), delta)
		var dir := vel[i] if vel[i].length() > 0.02 else heading
		put(i, facing(pos[i], dir, size()), Color(1, 1, 1, fades[i] * life.fade), Color(phase[i], 1.0, 0.0, 0.0))
	flush()


## The school's centre and turn, sampled every HISTORY_STEP seconds, for the ripple of a schooling school.
func _remember(delta: float, turn: Basis) -> void:
	_hist_t += delta
	if _history.is_empty() or _hist_t >= HISTORY_STEP:
		_hist_t = 0.0
		_history.push_front([centre, turn])
		if _history.size() > int(LAG / HISTORY_STEP) + 2:
			_history.pop_back()


## [centre, turn] as they were `ago` seconds since (the oldest kept at most).
func _recall(ago: float) -> Array:
	if _history.is_empty():
		return [centre, Basis()]
	var f := ago / HISTORY_STEP
	var i := clampi(int(f), 0, _history.size() - 1)
	var j := mini(i + 1, _history.size() - 1)
	var w := clampf(f - float(i), 0.0, 1.0)
	var a: Array = _history[i]
	var b: Array = _history[j]
	return [(a[0] as Vector3).lerp(b[0], w), (a[1] as Basis).slerp(b[1], w)]


func act(action: String, args: Dictionary) -> bool:
	match action:
		"scatter":
			_dart = 1.2
			return true
		"settle":
			_slow = 20.0
			return true
		"pass":
			var side := side_arg(args)
			var right: Vector3 = life.screen().basis.x
			var sgn := float(side if side != 0 else (1 if rng.randf() < 0.5 else -1))
			# From the given side to the other: the far end of the region along the screen's right.
			_wander = _box.get_center() - right * sgn * (absf(right.x) * _box.size.x + absf(right.z) * _box.size.z) * 0.45
			_wander_for = float(args.get("seconds", 15.0))
			return true
	return false


func positions() -> Array:
	var out: Array = []
	for i in count:
		if fades[i] > 0.0:
			out.append(pos[i])
	return out


func radius() -> float:
	return LENGTH * 0.5 * size()
