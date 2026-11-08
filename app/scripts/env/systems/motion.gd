extends "res://scripts/env/systems/env_system.gd"

## The motion system (docs/environments.md, "The motion system"): slow moves of the room's things, never the viewer and
## never their horizon. One system a mover: it moves one node a document names (`node`, among the nodes of the system
## `system`, or anywhere in the room), or a festoon curtain it builds itself (`build` "festoon"), in one of three ways:
##   travel   along `path` (offsets from where it stands, metres, in its parent's frame) and to `turn_to` (degrees,
##            about `pivot` in its own frame): `at` 0 is where it stands, 1 the path's end. The organ console rising
##            from the pit, the painting sliding up to show the screen, the festoon rising in swags.
##   sway     to and fro about `sway_axis` by `sway_angle` degrees and along `shift_dir` by `sway_shift` metres, every
##            `sway_period` seconds: a curtain stirring.
##   turn     about `turn_axis` at `turn_rate` degrees a second: Earth over the crater.
## Every move keeps to the comfort limits (MAX_SPEED, MAX_ACCEL, MAX_TURN, MAX_TURN_ACCEL, the sway's limits): `at`
## may be set by a cue's fade, a binding or an action, and the thing follows it no faster than those, speeding up and
## slowing down smoothly. The room's Motion setting scales every motion parameter (the host does), and under REDUCED
## a travel does not move at all: it snaps to its end, or fades out and back in there (`reduced`).
## A thing in front of the screen (`in_front`: the painting, the festoon) does not count against the sight-line check,
## is in the group IN_FRONT (the film layer's question; see the docs), and never stays in the way through the film:
## once the film has played for CUE_GRACE seconds it goes to its end (at 1) if no cue has taken it there.

const ScreenFrame := preload("res://scripts/env/systems/screen_frame.gd")
## Comfort limits (docs/environments.md, "The motion system"): metres a second, metres a second squared, degrees a
## second, degrees a second squared.
const MAX_SPEED := 0.5
const MAX_ACCEL := 0.3
const MAX_TURN := 20.0
const MAX_TURN_ACCEL := 8.0
const MAX_SWAY_DEG := 5.0
const MAX_SWAY_SHIFT := 0.1
const MIN_SWAY_PERIOD := 3.0
const MAX_TURN_RATE := 15.0
## The Motion setting under this: travels snap or fade instead of moving.
const REDUCED := 0.25
## A fade's half (out, then in), seconds.
const FADE_SECONDS := 0.5
## Seconds of the film before a thing in front of the screen goes out of the way by itself.
const CUE_GRACE := 4.0
## Things that may come between the viewer and the screen.
const IN_FRONT := "env_in_front"
## The festoon: its height left when fully up (a share of its drop), the grid's rows, columns a swag.
const FESTOON_GATHER := 0.14
const FESTOON_ROWS := 14
const FESTOON_COLS := 6


static func spec() -> Dictionary:
	return {
		"kind": "motion",
		"description": "Slow moves of the room's things, never the viewer: a node the document names (or a festoon "
				+ "curtain it builds) travels along a path and turns (an organ rising, a painting sliding up, the "
				+ "festoon rising in swags), sways (a curtain) or turns (Earth). Speeds and accelerations held to the "
				+ "comfort limits; under reduced Motion a travel snaps or fades instead.",
		"params": PARAMS,
		"actions": {
			"rise": "go to the path's end (at 1); args: seconds (a wish: never faster than the limits)",
			"lower": "go back to where it stood (at 0); args: seconds",
			"go": "go to a point of the path; args: at (0..1), seconds",
			"snap": "be at a point of the path at once; args: at (0..1)",
			"start": "the sway or turn starts, easing in",
			"stop": "the sway or turn stops, easing out",
		},
		"moves_viewer": false,
		"provides": [],
		"requires": [],
		"cost": {"draws": 1, "triangles": 1300, "lights": 0, "particles": 0, "texture_mb": 4},
	}


const PARAMS := {
	"system": {"type": "string", "max": 32, "default": "",
			"description": "the id of the system whose node it moves; empty: any node of the room"},
	"node": {"type": "string", "max": 64, "default": "", "description": "the name of the node it moves"},
	"build": {"type": "enum", "values": ["none", "festoon"], "default": "none",
			"description": "festoon: it builds a festoon curtain over the screen and moves that"},
	"mode": {"type": "enum", "values": ["travel", "sway", "turn"], "default": "travel",
			"description": "travel along the path, sway to and fro, or turn round"},
	"path": {"type": "list", "of": {"type": "vec3", "min": -50.0, "max": 50.0}, "max": 16,
			"default": [[0.0, 2.0, 0.0]],
			"description": "travel: offsets from where it stands, metres, passed through in order"},
	"turn_to": {"type": "vec3", "min": -360.0, "max": 360.0, "default": [0.0, 0.0, 0.0],
			"description": "travel: its turn at the path's end, degrees (x, y, z)"},
	"pivot": {"type": "vec3", "min": -50.0, "max": 50.0, "default": [0.0, 0.0, 0.0],
			"description": "the point it turns and sways about, in its own frame"},
	"at": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true,
			"description": "travel: where it is to be along the path (0 where it stands, 1 the end)"},
	"speed": {"type": "float", "min": 0.01, "max": MAX_SPEED, "default": 0.25, "motion": {"max": MAX_SPEED},
			"description": "travel: its top speed, metres a second"},
	"accel": {"type": "float", "min": 0.02, "max": MAX_ACCEL, "default": 0.15, "motion": {"max": MAX_ACCEL},
			"description": "travel: how fast it speeds up and slows down, metres a second squared"},
	"turn_speed": {"type": "float", "min": 1.0, "max": MAX_TURN, "default": 10.0, "motion": {"max": MAX_TURN},
			"description": "travel: its top turning speed, degrees a second"},
	"sway_angle": {"type": "float", "min": 0.0, "max": MAX_SWAY_DEG, "default": 1.5, "live": true,
			"motion": {"max": MAX_SWAY_DEG}, "description": "sway: degrees either way"},
	"sway_shift": {"type": "float", "min": 0.0, "max": MAX_SWAY_SHIFT, "default": 0.0, "live": true,
			"motion": {"max": MAX_SWAY_SHIFT}, "description": "sway: metres either way along shift_dir"},
	"sway_axis": {"type": "vec3", "min": -1.0, "max": 1.0, "default": [0.0, 0.0, 1.0],
			"description": "sway: the axis it turns about"},
	"shift_dir": {"type": "vec3", "min": -1.0, "max": 1.0, "default": [1.0, 0.0, 0.0],
			"description": "sway: the way it shifts"},
	"sway_period": {"type": "float", "min": MIN_SWAY_PERIOD, "max": 60.0, "default": 7.0,
			"description": "sway: seconds a full swing"},
	"turn_rate": {"type": "float", "min": -MAX_TURN_RATE, "max": MAX_TURN_RATE, "default": 2.0, "live": true,
			"motion": {"max": MAX_TURN_RATE}, "description": "turn: degrees a second (negative: the other way)"},
	"turn_axis": {"type": "vec3", "min": -1.0, "max": 1.0, "default": [0.0, 1.0, 0.0],
			"description": "turn: the axis, in its own frame"},
	"running": {"type": "bool", "default": true, "live": true,
			"description": "sway and turn: moving (they ease in and out)"},
	"reduced": {"type": "enum", "values": ["snap", "fade"], "default": "snap",
			"description": "under reduced Motion a travel snaps to its end, or fades out and back in there"},
	"in_front": {"type": "bool", "default": false,
			"description": "it stands between the viewer and the screen until it moves away (a painting, a curtain)"},
	"festoon_size": {"type": "vec2", "min": 0.0, "max": 60.0, "default": [0.0, 0.0],
			"description": "festoon: width and drop, metres; 0: the screen's, with a margin"},
	"festoon_swags": {"type": "int", "min": 2, "max": 12, "default": 5, "description": "festoon: swags across"},
	"festoon_depth": {"type": "float", "min": 0.0, "max": 2.0, "default": 0.25,
			"description": "festoon: how far in front of the screen it hangs, metres"},
	# Since 2026-11-08 (the Streamline 1937): fully up, a festoon's swags hang about a quarter of its drop under its
	# top; hung higher, behind a proscenium's head, it clears the picture. 0.5, as before, is the default.
	"festoon_top": {"type": "float", "min": 0.0, "max": 6.0, "default": 0.5,
			"description": "festoon: how far its top hangs over the screen's top, metres"},
	"curtain": {"type": "material", "default": {"library": "velvet", "color": [0.62, 0.42, 0.16], "tiling": 0.3},
			"description": "festoon: its cloth"},
}


var _node: Node3D
var _rest := Transform3D()
var _resolve_wait := 0.0
## Travel: progress along the path (0..1) and its rate (a second).
var _u := 0.0
var _v := 0.0
var _target := 0.0
## The parameter at as last set (a fade's direction under reduced Motion).
var _last_at := 0.0
## An action's wish for the top rate (progress a second); INF: the limits'.
var _wish := INF
## Travel's path as points (rest at 0), their cumulative lengths, the end's rotation.
var _points: Array[Vector3] = []
var _lengths: Array[float] = []
var _length := 0.0
var _turn_end := Quaternion()
var _turn_deg := 0.0
## Sway and turn: the clock, the ease (0 still .. 1 moving), the turn's angle and rate.
var _t := 0.0
var _ease := 1.0
var _angle := 0.0
var _rate := 0.0
## Reduced Motion, fade: -1 none, else seconds into it.
var _fade_t := -1.0
var _fade_to := 0.0
## The film has played this long (in_front's grace).
var _playing := -1.0
var _grace_done := false
var _festoon: MeshInstance3D
var _festoon_mesh: ArrayMesh
var _festoon_size := Vector2.ZERO
var _festoon_lift := -1.0
var _screen_local := Transform3D()
var _screen_size := Vector2.ZERO
## Tests: positions and turns of every frame [[time, origin, angle]], when recording.
var recording := false
var trace: Array = []
var _clock := 0.0


func setup() -> void:
	_points = [Vector3.ZERO]
	for p: Variant in params["path"]:
		_points.append(_v3(p))
	_lengths = [0.0]
	for i in range(1, _points.size()):
		_lengths.append(_lengths[i - 1] + _points[i].distance_to(_points[i - 1]))
	_length = _lengths[-1]
	var tt := _v3(params["turn_to"])
	_turn_end = Quaternion.from_euler(Vector3(deg_to_rad(tt.x), deg_to_rad(tt.y), deg_to_rad(tt.z)))
	_turn_deg = rad_to_deg(_turn_end.get_angle())
	_u = float(params["at"])
	_target = _u
	_last_at = _u
	# A sway or a turn eases in from still, never starts at full speed.
	_ease = 0.0
	_rate = 0.0
	if str(params["build"]) == "festoon":
		_build_festoon()
	_resolve()


static func _v3(v: Variant) -> Vector3:
	return Vector3(float(v[0]), float(v[1]), float(v[2]))


func _resolve() -> void:
	if _node != null and is_instance_valid(_node):
		return
	_node = null
	if _festoon != null:
		_node = _festoon
	elif str(params["node"]) != "":
		var want := str(params["node"])
		var roots: Array = []
		if str(params["system"]) != "":
			var s: Node = host.system(str(params["system"])) if host != null else null
			if s != null:
				roots = s.call("owned")
		else:
			roots = [room]
		for r: Node in roots:
			if not is_instance_valid(r):
				continue
			# A system's node by its name, or by the plain name it had before a second system of its kind
			# (env_system.gd own()).
			var n: Node = r if r.name == want or str(r.get_meta("env_name", "")) == want \
					else r.find_child(want, true, false)
			if n is Node3D:
				_node = n
				break
	if _node == null:
		return
	_rest = _node.transform
	if bool(params["in_front"]):
		for g: Node in _drawn():
			g.add_to_group(IN_FRONT)
			if g is MeshInstance3D:
				g.add_to_group(ScreenFrame.SEE_THROUGH)
	_apply()


## The thing it moves (null until found).
func target() -> Node3D:
	return _node


# --- Live parameters and actions ---------------------------------------------------------------------------------------

func _param_changed(param: String, value: Variant) -> void:
	match param:
		"at":
			var prev := _last_at
			_last_at = float(value)
			if _reduced():
				# No travel at all: a cue's fade or a binding leads it step by step, so it goes straight to the end
				# it is heading for.
				if _last_at > prev:
					_go(1.0, 0.0)
				elif _last_at < prev:
					_go(0.0, 0.0)
				return
			_go(_last_at, INF)


func act(action: String, args: Dictionary) -> void:
	var seconds := float(args.get("seconds", 0.0))
	match action:
		"rise":
			_go(1.0, seconds)
		"lower":
			_go(0.0, seconds)
		"go":
			_go(clampf(float(args.get("at", 1.0)), 0.0, 1.0), seconds)
		"snap":
			_snap(clampf(float(args.get("at", 1.0)), 0.0, 1.0))
		"start":
			params["running"] = true
		"stop":
			params["running"] = false
	if action in ["rise", "lower", "go", "snap"]:
		# The parameter says where it is going (a cue's fade or a release starts from there).
		params["at"] = _target
		_last_at = _target


func _reduced() -> bool:
	return host != null and float(host.setting("motion") if host.setting("motion") != null else 1.0) < REDUCED


## Travel towards `to`; seconds: a wish for how long it takes (0 or INF: as fast as the limits let it).
func _go(to: float, seconds: float) -> void:
	_target = clampf(to, 0.0, 1.0)
	_wish = INF
	if seconds > 0.0 and seconds < INF:
		var d := absf(_target - _u)
		var a := _limit_accel()
		# A trapezoid of top rate v and slopes a covers d in d / v + v / a: the v that takes `seconds`.
		var disc := a * a * seconds * seconds - 4.0 * a * d
		_wish = (a * seconds - sqrt(disc)) * 0.5 if disc >= 0.0 else INF
	if _reduced() and not is_equal_approx(_target, _u):
		if str(params["reduced"]) == "fade":
			if _fade_t < 0.0:
				_fade_t = 0.0
			_fade_to = _target
		else:
			_snap(_target)


func _snap(to: float) -> void:
	_target = to
	_u = to
	_v = 0.0
	_apply()


## The top rate along the path (progress a second) the limits allow: speed over the length, the turn's speed over
## its angle.
func _limit_rate() -> float:
	var r := INF
	if _length > 0.0:
		r = minf(r, minf(float(params["speed"]), MAX_SPEED) / _length)
	if _turn_deg > 0.01:
		r = minf(r, minf(float(params["turn_speed"]), MAX_TURN) / _turn_deg)
	if _festoon != null:
		r = minf(r, minf(float(params["speed"]), MAX_SPEED) / maxf(_lift_metres(), 0.01))
	return r


func _limit_accel() -> float:
	var a := INF
	if _length > 0.0:
		a = minf(a, minf(float(params["accel"]), MAX_ACCEL) / _length)
	if _turn_deg > 0.01:
		a = minf(a, MAX_TURN_ACCEL / _turn_deg)
	if _festoon != null:
		a = minf(a, minf(float(params["accel"]), MAX_ACCEL) / maxf(_lift_metres(), 0.01))
	return a


# --- Each frame --------------------------------------------------------------------------------------------------------

func tick(delta: float) -> void:
	_clock += delta
	if _node == null or not is_instance_valid(_node):
		_node = null
		_resolve_wait -= delta
		if _resolve_wait > 0.0:
			return
		_resolve_wait = 1.0
		_resolve()
		if _node == null:
			return
	_grace(delta)
	match str(params["mode"]):
		"travel":
			_step_travel(delta)
		"sway":
			_step_ease(delta, 0.5 * float(params["sway_period"]))
			_t += delta * _ease
		"turn":
			var want := float(params["turn_rate"]) if bool(params["running"]) else 0.0
			_rate = move_toward(_rate, want, MAX_TURN_ACCEL * delta)
			_angle = fmod(_angle + _rate * delta, 360.0)
	_apply()
	if recording:
		trace.append([_clock, _node.global_position, _angle_now(), _u])


func _step_ease(delta: float, seconds: float) -> void:
	var want := 1.0 if bool(params["running"]) else 0.0
	_ease = move_toward(_ease, want, delta / maxf(seconds, 0.1))


func _step_travel(delta: float) -> void:
	if _fade_t >= 0.0:
		_fade_t += delta
		if _fade_t >= FADE_SECONDS and not is_equal_approx(_u, _fade_to):
			_u = _fade_to
			_v = 0.0
		var f := _fade_t / FADE_SECONDS
		_set_fade(clampf(f if f <= 1.0 else 2.0 - f, 0.0, 1.0))
		if _fade_t >= FADE_SECONDS * 2.0:
			_fade_t = -1.0
			_set_fade(0.0)
		return
	if _reduced() and not is_equal_approx(_u, _target):
		_go(_target, 0.0)
		return
	var vmax := minf(_limit_rate(), _wish)
	var a := _limit_accel()
	if vmax == INF or a == INF:
		_u = _target
		_v = 0.0
		return
	var d := _target - _u
	if absf(d) < 1e-6:
		_u = _target
		_v = 0.0
		return
	var dir := signf(d)
	var stop := _v * _v / (2.0 * a)
	if _v != 0.0 and signf(_v) != dir:
		_v = move_toward(_v, 0.0, a * delta)
	elif stop >= absf(d):
		_v = dir * maxf(absf(_v) - a * delta, a * delta)
	else:
		_v = dir * minf(absf(_v) + a * delta, vmax)
	_u += _v * delta
	if signf(_target - _u) != dir:
		_u = _target
		_v = 0.0


## Things in front of the screen never stay there through the film: counted from the film's start (starting, then
## playing), once; any other state stops the count.
func on_state(state: String, _previous: String) -> void:
	if state in ["starting", "playing"]:
		if _playing < 0.0 and not _grace_done:
			_playing = 0.0
	else:
		_playing = -1.0
		_grace_done = false


func _grace(delta: float) -> void:
	if _playing < 0.0 or not bool(params["in_front"]):
		return
	_playing += delta
	if _playing >= CUE_GRACE:
		_playing = -1.0
		_grace_done = true
		if _target < 1.0:
			_go(1.0, 0.0)


func _set_fade(f: float) -> void:
	for g: Node in _drawn():
		if g is GeometryInstance3D:
			(g as GeometryInstance3D).transparency = f


## The node it moves and everything drawn under it.
func _drawn() -> Array:
	var out: Array = [_node]
	out.append_array(_node.find_children("*", "GeometryInstance3D", true, false))
	return out


func _angle_now() -> float:
	match str(params["mode"]):
		"sway":
			return float(params["sway_angle"]) * _ease * sin(TAU * _t / float(params["sway_period"]))
		"turn":
			return _angle
	return _turn_deg * _u


## The node where it is now.
func _apply() -> void:
	if _node == null:
		return
	if _festoon != null and _node == _festoon:
		_lift_festoon(_u)
		return
	var pivot := _v3(params["pivot"])
	var spin := Basis()
	var offset := Vector3.ZERO
	match str(params["mode"]):
		"travel":
			offset = _along(_u)
			spin = Basis(Quaternion().slerp(_turn_end, _u))
		"sway":
			var ph := sin(TAU * _t / float(params["sway_period"])) * _ease
			var axis := _v3(params["sway_axis"])
			if axis.length() > 0.001:
				spin = Basis(axis.normalized(), deg_to_rad(float(params["sway_angle"]) * ph))
			var dir := _v3(params["shift_dir"])
			if dir.length() > 0.001:
				offset = dir.normalized() * float(params["sway_shift"]) * ph
		"turn":
			var axis := _v3(params["turn_axis"])
			if axis.length() > 0.001:
				spin = Basis(axis.normalized(), deg_to_rad(_angle))
	var xf := _rest * Transform3D(Basis(), pivot) * Transform3D(spin, Vector3.ZERO) * Transform3D(Basis(), -pivot)
	xf.origin += offset
	_node.transform = xf


## The path's offset at progress u (by length; a path of one point at its end).
func _along(u: float) -> Vector3:
	if _length <= 0.0:
		return _points[-1] * u if _points.size() > 1 else Vector3.ZERO
	var s := u * _length
	for i in range(1, _points.size()):
		if s <= _lengths[i] or i == _points.size() - 1:
			var seg := _lengths[i] - _lengths[i - 1]
			var f := (s - _lengths[i - 1]) / seg if seg > 0.0 else 1.0
			return _points[i - 1].lerp(_points[i], clampf(f, 0.0, 1.0))
	return _points[-1]


## Where it is along its path now (0..1), and its rate (tests).
func progress() -> float:
	return _u


# --- The festoon -------------------------------------------------------------------------------------------------------

func on_screen_changed(local: Transform3D, size: Vector2) -> void:
	_screen_local = local
	_screen_size = size
	if _festoon != null:
		_place_festoon()


func _build_festoon() -> void:
	_festoon_mesh = ArrayMesh.new()
	_festoon = MeshInstance3D.new()
	_festoon.name = "Festoon"
	_festoon.mesh = _festoon_mesh
	_festoon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_festoon.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var light: Node = host.system_of_kind("light") if host != null else null
	var m: Dictionary = params["curtain"]
	if light != null:
		_festoon.material_override = light.call("from_param", m, true)
	else:
		var shared := MaterialLibrary.get_material(str(m.get("library", "velvet")),
				{"colour": RoomSchemaRef.to_color(m.get("color", "#a06a28"))})
		if shared != null:
			_festoon.material_override = shared
	own(_festoon)
	# A festoon is always in front of the screen.
	params["in_front"] = true
	_place_festoon()


func _place_festoon() -> void:
	var local := _screen_local
	var size := _screen_size
	if size == Vector2.ZERO:
		var anchor: Variant = room.call("get_screen_anchor") if room.has_method("get_screen_anchor") else null
		if anchor is Transform3D:
			local = anchor
		elif anchor is Node3D:
			local = (anchor as Node3D).transform
		var d: Variant = room.get("doc")
		if d is Dictionary and (d as Dictionary).get("screen") is Dictionary:
			var s: Array = d["screen"]["size"]
			size = Vector2(float(s[0]), float(s[1]))
		elif room.get("default_screen_width") != null:
			var w := float(room.get("default_screen_width"))
			size = Vector2(w, w * 9.0 / 16.0)
	var given := Vector2(float(params["festoon_size"][0]), float(params["festoon_size"][1]))
	_festoon_size = Vector2(given.x if given.x > 0.0 else size.x + 0.8, given.y if given.y > 0.0 else size.y + 0.7)
	# Its top over the screen's, the margin above; a little in front.
	_festoon.transform = local * Transform3D(Basis(), Vector3(0.0, size.y * 0.5 + float(params["festoon_top"]),
			float(params["festoon_depth"])))
	_rest = _festoon.transform
	_festoon_lift = -1.0
	_lift_festoon(_u)


func _lift_metres() -> float:
	return _festoon_size.y * (1.0 - FESTOON_GATHER)


## The cloth at lift a (0 down .. 1 up): the hem rises, the cloth above it gathers into tiers of folds, and between
## the lift cords it falls in swags that deepen as it rises.
func _lift_festoon(a: float) -> void:
	if _festoon_mesh == null or is_equal_approx(a, _festoon_lift):
		return
	_festoon_lift = a
	var swags := int(params["festoon_swags"])
	var cols := swags * FESTOON_COLS
	var w := _festoon_size.x
	var h := _festoon_size.y
	var hem := -h + a * _lift_metres()
	var spacing := w / swags
	var sag := 0.06 + minf(0.35 * spacing, 0.6) * a
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	for r in FESTOON_ROWS + 1:
		var v := float(r) / FESTOON_ROWS
		for c in cols + 1:
			var x := -w * 0.5 + w * float(c) / cols
			var s := fmod(float(c) / FESTOON_COLS, 1.0)
			var swag := sin(PI * s)
			var y := hem * (1.0 - v) - sag * swag * pow(1.0 - v, 0.7)
			var fold := (0.02 + 0.07 * a) * absf(sin(PI * v * 7.0))
			var z := fold + 0.05 * swag * (0.3 + a) * (1.0 - v)
			verts.append(Vector3(x, y, z))
			uvs.append(Vector2(x, v * h))
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	var w1 := cols + 1
	for r in FESTOON_ROWS + 1:
		for c in cols + 1:
			var i := r * w1 + c
			var dx := verts[r * w1 + mini(c + 1, cols)] - verts[r * w1 + maxi(c - 1, 0)]
			var dy := verts[mini(r + 1, FESTOON_ROWS) * w1 + c] - verts[maxi(r - 1, 0) * w1 + c]
			var n := dx.cross(dy).normalized()
			normals[i] = n if n.z >= 0.0 else -n
	var idx := PackedInt32Array()
	for r in FESTOON_ROWS:
		for c in cols:
			var i0 := r * w1 + c
			# Facing +z (the viewer): clockwise seen from the front.
			idx.append_array([i0, i0 + w1, i0 + 1, i0 + 1, i0 + w1, i0 + w1 + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mat := _festoon_mesh.surface_get_material(0) if _festoon_mesh.get_surface_count() > 0 else null
	_festoon_mesh.clear_surfaces()
	_festoon_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if mat != null:
		_festoon_mesh.surface_set_material(0, mat)


## The festoon's hem height under its top now (tests): metres, negative.
func festoon_hem() -> float:
	return -_festoon_size.y + _u * _lift_metres()


const MaterialLibrary := preload("res://scripts/env/material_library.gd")
