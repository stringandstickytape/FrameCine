extends "res://scripts/env/systems/life/creature.gd"

## Fireflies (the reclaimed cinema): soft yellow-green points drifting low through the region, each flashing on its
## own about every two to six seconds (a slow swell and fall of 0.6 s: far under the photosensitivity ceiling), faint
## in between. With blink off, or the room's Flickering lights off, they glow steady. glow scales them: bound to
## film.brightness (inverted) they dim while the film is bright. activity: how many are out.

const FLASH := 0.6
const DRIFT := 0.25
const POINT := 0.09
const COLOUR := Color(0.75, 1.0, 0.35)

var pos: Array[Vector3] = []
var vel: Array[Vector3] = []
var home: Array[Vector3] = []
var next := PackedFloat32Array()
var flash := PackedFloat32Array()
var fades := PackedFloat32Array()
var _box := AABB()
## Flashes so far (tests).
var flashes := 0


static func defaults() -> Dictionary:
	return {"count": 60}


func build() -> void:
	var r: Variant = life.region()
	_box = r if r is AABB else life.around_viewer(8.0, -1.1, 1.4, 10.0, 4.0)
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	multimesh(q, count, glow_material(life.colour_or(COLOUR), 0), WIDE, "Fireflies")
	for i in count:
		var p: Vector3 = life.keep(random_in(_box))
		pos.append(p)
		vel.append(Vector3.ZERO)
		home.append(p)
		next.append(rng.randf_range(0.0, 5.0))
		flash.append(-1.0)
		fades.append(1.0 if shown(i) else 0.0)


func param_changed(param: String) -> void:
	if material == null:
		return
	if param == "glow":
		material.set_shader_parameter("glow", float(life.params["glow"]))
	elif param == "colour":
		material.set_shader_parameter("colour", life.colour_or(COLOUR))


func step(delta: float) -> void:
	var blink := bool(life.params["blink"])
	var top := DRIFT * speed()
	for i in count:
		if pos[i].distance_to(home[i]) < 0.2 or rng.randf() < delta * 0.1:
			home[i] = life.keep(random_in(_box))
		var acc := (home[i] - pos[i]).normalized() * 0.3 + jitter() * 0.5
		vel[i] = (vel[i] + acc * delta).limit_length(top)
		pos[i] = life.keep(pos[i] + vel[i] * delta)
		var b := 0.55
		if blink:
			b = 0.06
			if flash[i] >= 0.0:
				flash[i] += delta
				var f := sin(PI * clampf(flash[i] / FLASH, 0.0, 1.0))
				b = maxf(b, f * f)
				if flash[i] >= FLASH:
					flash[i] = -1.0
					next[i] = rng.randf_range(1.5, 6.0)
			else:
				next[i] -= delta
				if next[i] <= 0.0:
					flash[i] = 0.0
					flashes += 1
		fades[i] = fade_to(fades[i], shown(i), delta, 2.0)
		put(i, Transform3D(Basis.from_scale(Vector3.ONE * POINT * size()), pos[i]),
				Color(1, 1, 1, fades[i] * life.fade), Color(0.0, 0.0, b, 0.0))
	flush()


func act(action: String, args: Dictionary) -> bool:
	match action:
		"scatter":
			var from := from_arg(args, life.eye_now())
			for i in count:
				var away := (pos[i] - from)
				away.y = absf(away.y) + 1.0
				home[i] = life.keep(pos[i] + away.normalized() * 2.0)
			return true
		"settle":
			for i in count:
				var h := random_in(_box)
				h.y = _box.position.y + _box.size.y * 0.2 * rng.randf()
				home[i] = life.keep(h)
			return true
	return false


## The light of each one now (tests): its flash, 0..1.
func lights() -> Array:
	var out: Array = []
	for i in count:
		out.append(_buf[i * STRIDE + 18])
	return out


func positions() -> Array:
	var out: Array = []
	for i in count:
		if fades[i] > 0.0:
			out.append(pos[i])
	return out


func radius() -> float:
	return POINT * size()
