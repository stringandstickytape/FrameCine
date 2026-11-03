extends Node

## Motion for the assistant's parts (docs/assistant.md, "Rooms", motion): named, bounded movements the app runs; the
## assistant only names them and their numbers. One node per room, one _process loop over every moving part (a few
## multiplies each), nothing per part in the scene tree.
##
## Per part, "motion": a motion or a list of up to MAX_PER_PART:
##   {"type": "spin",  "axis": [0, 1, 0], "speed": 30}                      degrees a second, about the part's own axis
##   {"type": "bob",   "height": 0.05, "period": 4}                         up and down, metres, seconds a cycle
##   {"type": "sway",  "angle": 10, "period": 6, "axis": [0, 0, 1]}         to and fro about its own axis
##   {"type": "orbit", "center": [0, 2, -3], "radius": 1, "period": 20, "axis": [0, 1, 0], "face": true}
##   {"type": "flap",  "angle": 40, "period": 0.5, "axis": [0, 0, 1], "hinge": [0, 0, 0], "mirror": false}
##   {"type": "move_to", "position": [x, y, z], "rotation": [x, y, z], "duration": 20, "easing": "sine_in_out",
##    "at": 120 | "end-30" | "end"}                                        once; with at, on the film's clock
## Every cycle is eased (sine), never a linear back and forth. Each part gets a small phase and speed offset from its
## name, so copies never move in step; parts with the same "sync" name share one (a pair of wings).

const RoomSchema := preload("res://scripts/assistant/room_schema.gd")
const MAX_PER_PART := 3
## Bounds: the comfort of a viewer who sits still for two hours.
const SPEC := {
	"spin": {"speed": [-180.0, 180.0], "axis": "axis"},
	"bob": {"height": [0.0, 1.0], "period": [0.5, 120.0]},
	"sway": {"angle": [0.0, 60.0], "period": [0.5, 120.0], "axis": "axis"},
	"orbit": {"center": "vec3", "radius": [0.0, 20.0], "period": [2.0, 600.0], "axis": "axis", "face": "bool"},
	"flap": {"angle": [0.0, 80.0], "period": [0.2, 20.0], "axis": "axis", "hinge": "vec3", "mirror": "bool"},
	"move_to": {"position": "vec3", "rotation": "vec3", "duration": [0.1, 600.0], "easing": "easing", "at": "at"},
}
const REQUIRED := {"spin": ["speed"], "bob": ["height", "period"], "sway": ["angle", "period"],
		"orbit": ["center", "radius", "period"], "flap": ["angle", "period"], "move_to": ["duration"]}
const EASINGS: Array[String] = ["sine_in_out", "cubic_in_out", "ease_out", "ease_in", "linear"]
## How much each instance's speed may differ from the one asked (so copies drift apart): +- this fraction.
const SPEED_SPREAD := 0.04

## [{node, base: Transform3D, motions: [{...}], phase, speed}]
var _items: Array = []
var _start := 0.0
## Seconds since the room was built; tests set `clock` to step it by hand.
var clock := -1.0


## Checks a part's "motion": problems appended as {path, error}.
static func validate(v: Variant, path: String, errors: Array) -> void:
	var list: Array = v if v is Array else [v]
	if list.size() > MAX_PER_PART or list.is_empty():
		errors.append({"path": path, "error": "a motion or a list of 1..%d" % MAX_PER_PART})
		return
	for i in list.size():
		var p := path + ("[%d]" % i if v is Array else "")
		if not (list[i] is Dictionary):
			errors.append({"path": p, "error": "{type, ...}: one of %s" % ", ".join(SPEC.keys())})
			continue
		var m: Dictionary = list[i]
		var type := str(m.get("type", ""))
		if not SPEC.has(type):
			errors.append({"path": p + ".type", "error": "one of %s" % ", ".join(SPEC.keys())})
			continue
		var spec: Dictionary = SPEC[type]
		for k: String in REQUIRED[type]:
			if not m.has(k):
				errors.append({"path": "%s.%s" % [p, k], "error": "required for %s" % type})
		if type == "move_to" and not m.has("position") and not m.has("rotation"):
			errors.append({"path": p + ".position", "error": "move_to needs position or rotation (or both)"})
		for k: Variant in m:
			var key := str(k)
			if key == "type" or key == "sync":
				if key == "sync" and not RoomSchema._name_ok(m[k]):
					errors.append({"path": p + ".sync", "error": "a group name: letters, digits, space, - and _"})
				continue
			if not spec.has(key):
				errors.append({"path": "%s.%s" % [p, key], "error": "unknown for %s (known: %s, sync)" % [type,
						", ".join(spec.keys())]})
				continue
			var s: Variant = spec[key]
			var x: Variant = m[k]
			var bad := ""
			if s is Array:
				var f := RoomSchema._num(x)
				if not (f >= float(s[0]) and f <= float(s[1])):
					bad = "%s..%s" % [s[0], s[1]]
			elif s == "vec3":
				if not RoomSchema._vec(x, 3):
					bad = "[x, y, z]"
			elif s == "axis":
				if not RoomSchema._vec(x, 3) or Vector3(float(x[0]), float(x[1]), float(x[2])).length() < 1e-3:
					bad = "[x, y, z], not all 0"
			elif s == "bool":
				if not (x is bool):
					bad = "true or false"
			elif s == "easing":
				if not (x is String and x in EASINGS):
					bad = "one of %s" % ", ".join(EASINGS)
			elif s == "at":
				if not at_ok(x):
					bad = "seconds into the film (a number), \"end\", or \"end-30\" (30 s before the end)"
			if bad != "":
				errors.append({"path": "%s.%s" % [p, key], "error": bad})


static func at_ok(x: Variant) -> bool:
	if (x is float or x is int) and float(x) >= 0.0:
		return true
	if not (x is String):
		return false
	var s := (x as String).replace(" ", "")
	if s == "end":
		return true
	return s.begins_with("end-") and s.trim_prefix("end-").is_valid_float() and float(s.trim_prefix("end-")) >= 0.0


## A film moment as seconds, given the film's duration; NAN when it can't be known yet.
static func at_seconds(x: Variant, duration: float) -> float:
	if x is float or x is int:
		return float(x)
	if duration <= 0.0:
		return NAN
	var s := str(x).replace(" ", "")
	return duration if s == "end" else maxf(duration - float(s.trim_prefix("end-")), 0.0)


static func motions_of(p: Dictionary) -> Array:
	var v: Variant = p.get("motion")
	if v == null:
		return []
	return v if v is Array else [v]


## A part with motion joins the loop. Its document pose is the base every motion starts from.
func add(node: Node3D, p: Dictionary) -> void:
	var list := motions_of(p)
	if list.is_empty():
		return
	var key := str(p["name"])
	for m: Dictionary in list:
		if m.has("sync"):
			key = "sync:" + str(m["sync"])
	# A stable offset from the name (or the sync group): copies drift apart, a restart looks the same.
	var h := key.md5_text()
	var phase := float(h.substr(0, 4).hex_to_int()) / 65535.0
	var speed := 1.0 + SPEED_SPREAD * (float(h.substr(4, 4).hex_to_int()) / 65535.0 * 2.0 - 1.0)
	_items.append({"node": node, "base": node.transform, "motions": list, "phase": phase, "speed": speed})


func count() -> int:
	return _items.size()


func _ready() -> void:
	_start = Time.get_ticks_msec() / 1000.0
	set_process(not _items.is_empty())


func _process(_delta: float) -> void:
	var t := clock if clock >= 0.0 else Time.get_ticks_msec() / 1000.0 - _start
	var film := _film()
	step(t, film[0], film[1])


func _film() -> Array:
	var tree := get_tree()
	var m: Node = tree.current_scene if tree != null else null
	if m == null or not ("player" in m) or m.player == null:
		return [0.0, 0.0]
	return [float(m.player.get_position()), float(m.player.get_duration())]


## Every moving part at time t (seconds since the room was built), the film at film_pos of film_len.
func step(t: float, film_pos: float, film_len: float) -> void:
	for it: Dictionary in _items:
		var node: Node3D = it["node"]
		if not is_instance_valid(node):
			continue
		node.transform = pose(it, t, film_pos, film_len)


## A part's transform at time t: move_to first (the base it moves from and to), then the turning motions about the
## part's own axes, then the travelling ones (bob, orbit) in the room.
static func pose(it: Dictionary, t: float, film_pos: float, film_len: float) -> Transform3D:
	var base: Transform3D = it["base"]
	var phase: float = it["phase"]
	var k: float = it["speed"]
	var xf := base
	for m: Dictionary in it["motions"]:
		if str(m["type"]) == "move_to":
			xf = _move_to(base, m, t, film_pos, film_len)
	var local := Transform3D()
	var travel := Vector3.ZERO
	for m: Dictionary in it["motions"]:
		var axis := _axis(m.get("axis", [0, 1, 0] if m["type"] == "spin" or m["type"] == "orbit" else [0, 0, 1]))
		match str(m["type"]):
			"spin":
				var a := deg_to_rad(float(m["speed"])) * k * t + phase * TAU
				local = local * Transform3D(Basis(axis, a), Vector3.ZERO)
			"sway":
				var a := deg_to_rad(float(m["angle"])) * sin(TAU * (t * k / float(m["period"]) + phase))
				local = local * Transform3D(Basis(axis, a), Vector3.ZERO)
			"flap":
				# A wing beat: quick down, slower up (two sines), mirrored for the other wing.
				var c := TAU * (t * k / float(m["period"]) + phase)
				var s := sin(c) * 0.8 + sin(2.0 * c) * 0.2
				var a := deg_to_rad(float(m["angle"])) * s * (-1.0 if bool(m.get("mirror", false)) else 1.0)
				var hinge := _vec(m.get("hinge", [0, 0, 0]))
				local = local * Transform3D(Basis(), hinge) * Transform3D(Basis(axis, a), Vector3.ZERO) \
						* Transform3D(Basis(), -hinge)
			"bob":
				travel.y += float(m["height"]) * 0.5 * sin(TAU * (t * k / float(m["period"]) + phase))
			"orbit":
				var centre := _vec(m["center"])
				var a := TAU * (t * k / float(m["period"]) + phase)
				var rel := xf.origin - centre
				# The part's offset from the centre, flattened to the orbit's plane, set to the radius.
				var flat := rel - axis * rel.dot(axis)
				if flat.length() < 1e-4:
					flat = axis.cross(Vector3.FORWARD if absf(axis.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT)
				flat = flat.normalized() * float(m["radius"])
				var turned := Basis(axis, a) * flat
				xf.origin = centre + axis * rel.dot(axis) + turned
				if bool(m.get("face", false)):
					xf.basis = Basis(axis, a) * xf.basis
	xf.origin += travel
	return xf * local


static func _move_to(base: Transform3D, m: Dictionary, t: float, film_pos: float, film_len: float) -> Transform3D:
	var u := 0.0
	var d := float(m["duration"])
	if m.has("at"):
		var at := at_seconds(m["at"], film_len)
		if is_nan(at):
			return base
		u = clampf((film_pos - at) / d, 0.0, 1.0)
	else:
		u = clampf(t / d, 0.0, 1.0)
	u = ease_by(str(m.get("easing", "sine_in_out")), u)
	var to_pos := _vec(m["position"]) if m.has("position") else base.origin
	var to_basis := base.basis
	if m.has("rotation"):
		var r := _vec(m["rotation"])
		to_basis = Basis.from_euler(Vector3(deg_to_rad(r.x), deg_to_rad(r.y), deg_to_rad(r.z))) \
				.scaled(base.basis.get_scale())
	var q0 := base.basis.get_rotation_quaternion()
	var q1 := to_basis.get_rotation_quaternion()
	var b := Basis(q0.slerp(q1, u)).scaled(base.basis.get_scale())
	return Transform3D(b, base.origin.lerp(to_pos, u))


static func ease_by(name: String, u: float) -> float:
	match name:
		"linear":
			return u
		"ease_in":
			return 1.0 - cos(u * PI * 0.5)
		"ease_out":
			return sin(u * PI * 0.5)
		"cubic_in_out":
			return 4.0 * u * u * u if u < 0.5 else 1.0 - pow(-2.0 * u + 2.0, 3.0) / 2.0
	return 0.5 - 0.5 * cos(u * PI)


static func _vec(a: Variant) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


static func _axis(a: Variant) -> Vector3:
	var v := _vec(a)
	return v.normalized() if v.length() > 1e-6 else Vector3.UP
