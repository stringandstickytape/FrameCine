extends "res://scripts/env/systems/life/creature.gd"

## Moths drawn to the projector's beam (the drive-in): pale, 7 cm across, fluttering about homes in the beam between
## a tenth and three fifths of the way from the lens, where the beam's light catches them (bright near the lens,
## fainter on). attraction is the share that keep to the beam; the rest wander the region. Never in the sight line:
## the part of the beam they keep to is the part over the viewer's head. Without a beam they wander the region.

const SPAN := 0.07
const FLAPS_HZ := 9.0
const FLY := 0.6

var pos: Array[Vector3] = []
var vel: Array[Vector3] = []
var home: Array[Vector3] = []
var timer := PackedFloat32Array()
var phase := PackedFloat32Array()
var fades := PackedFloat32Array()
var _beam := {}
var _box := AABB()
var _away := {}


static func defaults() -> Dictionary:
	return {"count": 40}


func build() -> void:
	_beam = life.beam()
	var r: Variant = life.region()
	_box = r if r is AABB else life.around_viewer(6.0, 0.8, 4.0, 8.0, 3.0)
	var s := Shape.new()
	var w := Vector4(1, 0, 0, 0)
	var o := Vector4.ZERO
	var h := SPAN * 0.5
	# Body, then a fore and a hind wing each side (the wing weight at their outer points).
	s.tri(Vector3(0, 0, -0.02), Vector3(0.004, 0.003, 0.0), Vector3(0, 0, 0.022))
	s.tri(Vector3(0, 0, -0.02), Vector3(0, 0, 0.022), Vector3(-0.004, 0.003, 0.0))
	for sx: float in [-1.0, 1.0]:
		s.tri(Vector3(0, 0, -0.012), Vector3(sx * h, 0, -0.014), Vector3(sx * h * 0.85, 0, 0.008), o, w, w)
		s.tri(Vector3(0, 0, 0.0), Vector3(sx * h * 0.8, 0, 0.012), Vector3(sx * h * 0.3, 0, 0.024), o, w, w)
	var colour: Color = life.colour_or(Color(0.8, 0.76, 0.66))
	multimesh(s.commit(), count, body_material(colour, {"flap": 1.1, "spill": 0.5}), WIDE, "Moths")
	for i in count:
		var p := _new_home()
		pos.append(p)
		vel.append(Vector3.ZERO)
		home.append(p)
		timer.append(rng.randf_range(0.5, 4.0))
		phase.append(rng.randf())
		fades.append(1.0 if shown(i) else 0.0)


func _new_home() -> Vector3:
	if not _beam.is_empty() and rng.randf() < float(life.params["attraction"]):
		var lens: Vector3 = _beam["lens"]
		for k in 12:
			var p: Vector3 = life.beam_point(lens, rng.randf_range(0.1, 0.6), rng.randf_range(-0.42, 0.42),
					rng.randf_range(-0.42, 0.42))
			if not life.in_view(p) and p.distance_to(life.eye_now()) > float(life.params["personal"]):
				return p
	return life.keep(random_in(_box))


func param_changed(param: String) -> void:
	if param == "colour" and material != null:
		material.set_shader_parameter("colour", life.colour_or(Color(0.8, 0.76, 0.66)))


func step(delta: float) -> void:
	var top := FLY * speed()
	var lens: Vector3 = _beam.get("lens", Vector3.ZERO)
	var lit_on := not _beam.is_empty() and bool(life.beam().get("on", true))
	for i in count:
		timer[i] -= delta
		if timer[i] <= 0.0 or pos[i].distance_to(home[i]) < 0.12:
			home[i] = _new_home()
			timer[i] = rng.randf_range(1.0, 5.0)
		var acc := (home[i] - pos[i]).normalized() * 1.6 + jitter() * 3.0
		if _away.has(i):
			acc += _away[i] * 6.0
			_away[i] = (_away[i] as Vector3) * maxf(0.0, 1.0 - delta)
		var v := vel[i] + acc * delta
		vel[i] = v.limit_length(top * (2.5 if _away.has(i) else 1.0))
		pos[i] = life.keep(pos[i] + vel[i] * delta)
		phase[i] = fmod(phase[i] + delta * FLAPS_HZ, 1.0)
		fades[i] = fade_to(fades[i], shown(i), delta)
		var lit: float = life.beam_light(lens, pos[i]) if lit_on else 0.0
		put(i, facing(pos[i], vel[i], size()), Color(1, 1, 1, fades[i] * life.fade), Color(phase[i], 1.0, lit, 0.0))
	flush()
	for i: int in _away.keys():
		if (_away[i] as Vector3).length() < 0.05:
			_away.erase(i)


func act(action: String, args: Dictionary) -> bool:
	match action:
		"scatter":
			var from: Vector3 = from_arg(args, _centre())
			for i in count:
				_away[i] = (pos[i] - from).normalized()
				home[i] = life.keep(random_in(_box))
			return true
		"settle":
			for i in count:
				vel[i] = Vector3.ZERO
			return true
	return false


func _centre() -> Vector3:
	var c := Vector3.ZERO
	for p in pos:
		c += p
	return c / maxf(float(pos.size()), 1.0)


func positions() -> Array:
	var out: Array = []
	for i in count:
		if fades[i] > 0.0:
			out.append(pos[i])
	return out


func radius() -> float:
	return SPAN * 0.5 * size()
