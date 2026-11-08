extends "res://scripts/env/systems/env_system.gd"

## Ambient life (docs/environments.md, "Ambient life"): animals, never people. One life system is one kind of creature
## (`creature`): moths in the projector's beam, birds roosting and flitting through an open roof, fireflies, a cat
## along a wall, an occasional deer, a school of fish outside the glass, glowing deep-sea creatures drawn to the
## screen's light, a manta ray gliding over, a rare whale, plane lights crossing a night sky. A room with several kinds
## has several, each with its own id ("moths", "whale"); a cue calls one by that id ("whale.pass").
##
## Every creature keeps out of the viewer's face (`personal` metres from the eyes) and out of the sight line to the
## picture: the pyramid from the eyes to the screen's edges, `keep_out` metres wider (keep()). So nothing of it stands
## between the viewer and the film, and on the Frame, where the film is a composition layer drawn over whatever is in
## front of the screen (scripts/play/film_layer.gd), nothing of it is hidden by the film either. A walker whose path
## crosses the pyramid (the cat, the deer) never stops in it and goes through at a trot.
##
## The creatures live in scripts/env/systems/life/<creature>.gd and draw with shaders/env_life.gdshader (bodies) and
## env_life_glow.gdshader (lights and glowing bells). The common "Ambient life" setting turns them off (set_active).

const Creature := preload("res://scripts/env/systems/life/creature.gd")
const EnvDoc := preload("res://scripts/env/env_doc.gd")
const CREATURES := {
	"moth": preload("res://scripts/env/systems/life/moth.gd"),
	"bird": preload("res://scripts/env/systems/life/bird.gd"),
	"firefly": preload("res://scripts/env/systems/life/firefly.gd"),
	"cat": preload("res://scripts/env/systems/life/cat.gd"),
	"deer": preload("res://scripts/env/systems/life/deer.gd"),
	"fish": preload("res://scripts/env/systems/life/fish.gd"),
	"jelly": preload("res://scripts/env/systems/life/jelly.gd"),
	"whale": preload("res://scripts/env/systems/life/whale.gd"),
	"plane": preload("res://scripts/env/systems/life/plane.gd"),
	"ray": preload("res://scripts/env/systems/life/ray.gd"),
}
## Seconds the creatures take to fade out (Ambient life off) or in again.
const FADE_SECONDS := 1.5
## A walker in the sight line goes this many times faster, and never stops there.
const THROUGH_SPEED := 2.5
## Eyes over a seat's floor point (env_checks.gd EYE_HEIGHT).
const EYE_HEIGHT := 1.2

signal creature_event(what: String, at: Vector3)


static func spec() -> Dictionary:
	return {
		"kind": "life",
		"description": "Ambient life, one kind of creature each: moths in the projector's beam, birds that roost and "
				+ "flit through an open roof, fireflies, a cat on a wall, an occasional deer, fish outside the glass, "
				+ "glowing deep-sea creatures drawn to the screen, a manta gliding over, a rare whale, plane lights in "
				+ "a night sky. They keep out of the viewer's face and out of the sight line to the picture. Never "
				+ "people.",
		"params": {
			"creature": {"type": "enum", "values": ["moth", "bird", "firefly", "cat", "deer", "fish", "jelly", "ray",
					"whale", "plane"], "default": "moth",
					"description": "which creature: moth, bird, firefly, cat, deer, fish, jelly (glowing deep-sea "
					+ "creatures), ray (a manta gliding over), whale, plane (a plane's lights)"},
			"count": {"type": "int", "min": 0, "max": 200, "default": 0,
					"description": "how many; 0: the creature's own (moths 40, birds 6, fireflies 60, fish 48, "
					+ "jellies 18, one cat, deer, ray or whale, planes 2 at once); the cat, deer, ray and whale are "
					+ "one at most"},
			"schooling": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0,
					"description": "fish: how tightly they school; over 0 the school draws in, stretches along its "
					+ "way and its turns ripple back through it from the leaders (each fish follows where the school "
					+ "was a moment before, the later the further back it swims)"},
			"region": {"type": "object", "nullable": true, "default": null,
					"fields": {"min": {"type": "vec3", "min": -500.0, "max": 500.0},
						"max": {"type": "vec3", "min": -500.0, "max": 500.0}},
					"description": "the box they keep to, in the room's frame ({min, max}); null: the creature's own "
					+ "(moths: the projector's beam; jellies: round the screen; fish, fireflies, birds: round the "
					+ "viewer)"},
			"path": {"type": "list", "of": {"type": "vec3", "min": -500.0, "max": 500.0}, "max": 16, "default": [],
					"description": "points in the room's frame: the wall top the cat walks, the deer's and the "
					+ "whale's way across (first to last), the birds' perches; []: the creature's own"},
			"size": {"type": "float", "min": 0.25, "max": 4.0, "default": 1.0,
					"description": "times the creature's own size"},
			"speed": {"type": "float", "min": 0.2, "max": 3.0, "default": 1.0, "live": true,
					"description": "times the creature's own speed (all are slow)"},
			"colour": {"type": "color", "nullable": true, "default": null, "live": true, "brightness": true,
					"description": "the body's colour, or the glow's (fireflies, jellies); null: the creature's own. "
					+ "It can follow film.colour"},
			"glow": {"type": "float", "min": 0.0, "max": 2.0, "default": 1.0, "live": true, "brightness": true,
					"description": "how bright the lights are: fireflies, jellies, a plane's lights. Bound to "
					+ "film.brightness (inverted) the fireflies dim while the film is bright"},
			"attraction": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.5, "live": true,
					"description": "how strongly they are drawn to the light: moths to the beam, fish and jellies "
					+ "to the screen. Bound to film.brightness the fish come closer in a bright scene"},
			"activity": {"type": "float", "min": 0.0, "max": 1.0, "default": 1.0, "live": true,
					"description": "the share of them out and about (the rest fade away): fireflies at dusk, birds "
					+ "flitting by day, planes at night (time.of_day)"},
			"every": {"type": "float", "min": 0.0, "max": 7200.0, "nullable": true, "default": null,
					"description": "seconds between visits on average (the deer, a plane, a bird across the roof); "
					+ "0: only when a cue calls pass; null: the creature's own (deer 300, planes 75, a ray 90, the "
					+ "whale 0)"},
			"keep_out": {"type": "float", "min": 0.1, "max": 3.0, "default": 0.4,
					"description": "metres they keep from the sight line to the picture (the eyes to its edges)"},
			"personal": {"type": "float", "min": 0.8, "max": 6.0, "default": 1.5,
					"description": "metres they keep from the viewer's eyes"},
			"blink": {"type": "bool", "default": true, "live": true, "flicker": true, "steady": false,
					"description": "fireflies flash and a plane's strobes blink; off (or Flickering lights off): "
					+ "a steady glow"},
			"voice": {"type": "bool", "default": true,
					"description": "a call where the synthesiser has one (the whale's song as it passes); the "
					+ "others are silent and give events only"},
			"voice_db": {"type": "float", "min": -40.0, "max": 0.0, "default": -12.0,
					"description": "the call's gain on the Environment bus"},
		},
		"actions": {
			"pass": "one goes by now: the whale or the deer crosses, a manta glides over, a plane flies over, a bird "
					+ "flits across the roof, the cat walks its wall end to end, the school sweeps past (args: side "
					+ "left or right, seconds)",
			"scatter": "they start away and settle again: birds take off and circle, fish dart, moths and fireflies "
					+ "spread, the cat trots off (args: from [x, y, z])",
			"settle": "they rest now: birds to their perches, the cat sits, fish and moths slow",
			"call": "one call: a bird's, the cat's purr, the whale's song (a sound only where the synthesiser has "
					+ "one; otherwise an event)",
		},
		# Measured (test_env_life.gd), at the default counts: fish 48 x 34 = 1632 (the largest), jellies 18 x 60,
		# moths 40 x 6, birds 6 x 31, fireflies 60 x 2, planes 8 lights x 2, the cat 86, the deer 98, the whale 102.
		# One draw each. A count of 200 fish would be 6800.
		"cost": {"draws": 1, "triangles": 1700, "lights": 0, "particles": 0, "texture_mb": 0},
	}


## The creature (scripts/env/systems/life/<creature>.gd).
var creature: RefCounted
var rng := RandomNumberGenerator.new()
## The Ambient life setting, and the fade towards it (0..1).
var active := true
var fade := 1.0
## Events so far: [[what, at]] (a bird's call, the cat's purr, the whale's song); tests read them.
var events: Array = []
## Tests: where the eyes are (room frame), instead of the camera.
var eye_override: Variant = null
## Tests: seconds the walkers spent in the sight line, in a row, at most.
var longest_in_view := 0.0
var _in_view_for := 0.0
var _screen := Transform3D()
var _screen_inv := Transform3D()
var _half := Vector2(1.0, 0.5)
var _seat_eye := Vector3(0.0, EYE_HEIGHT, 0.0)
var _eye := Vector3(0.0, EYE_HEIGHT, 0.0)


func setup() -> void:
	rng.seed = hash("%s/%s" % [id, params["creature"]])
	_screen_from_room()
	var seats: Array = host.seats() if host != null else []
	if not seats.is_empty():
		var best: Transform3D = seats[0]
		for s: Transform3D in seats:
			if s.origin.length() < best.origin.length():
				best = s
		_seat_eye = best.origin + Vector3.UP * EYE_HEIGHT
	_eye = eye()
	var script: GDScript = CREATURES[str(params["creature"])]
	var d: Dictionary = script.call("defaults")
	creature = script.new()
	creature.life = self
	creature.rng = rng
	var n := int(params["count"])
	creature.count = mini(n if n > 0 else int(d["count"]), int(d.get("max", 200)))
	creature.build()
	active = bool(host.setting("life")) if host != null and host.setting("life") != null else true
	fade = 1.0 if active else 0.0
	_show(active)


## The default screen (the document's) until the room says where the screen is.
func _screen_from_room() -> void:
	if room.has_method("get_screen_anchor"):
		var a: Transform3D = room.call("get_screen_anchor")
		var w := float(room.get("default_screen_width")) if room.get("default_screen_width") != null else 3.0
		var doc: Dictionary = room.get("doc") if room.get("doc") is Dictionary else {}
		var h := w * 9.0 / 16.0
		if doc.get("screen") is Dictionary and (doc["screen"].get("size", []) as Array).size() > 1:
			h = float(doc["screen"]["size"][1])
		_set_screen(a, Vector2(w, h))


func _set_screen(local: Transform3D, size: Vector2) -> void:
	_screen = Transform3D(local.basis.orthonormalized(), local.origin)
	_screen_inv = _screen.affine_inverse()
	_half = size * 0.5


func on_screen_changed(local: Transform3D, size: Vector2) -> void:
	if size != Vector2.ZERO:
		_set_screen(local, size)


func _param_changed(param: String, _value: Variant) -> void:
	if creature != null:
		creature.param_changed(param)


func act(action: String, args: Dictionary) -> void:
	if creature != null and active:
		creature.act(action, args)


## The Ambient life setting (the host calls it): they fade away, or come back.
func set_active(on: bool) -> void:
	active = on
	if on:
		_show(true)


func _show(on: bool) -> void:
	for n: Node in owned():
		if n is Node3D:
			(n as Node3D).visible = on


func tick(delta: float) -> void:
	if creature == null:
		return
	var target := 1.0 if active else 0.0
	if fade != target:
		fade = move_toward(fade, target, delta / FADE_SECONDS)
		if fade <= 0.0:
			_show(false)
	if fade <= 0.0:
		return
	_eye = eye()
	creature.step(delta)
	_in_view_for = _in_view_for + delta if creature.walker_in_view() else 0.0
	longest_in_view = maxf(longest_in_view, _in_view_for)


# --- Where they may be ---------------------------------------------------------------------------------------------------

## The viewer's eyes in the room's frame now: the camera, or the room's own seat.
func eye() -> Vector3:
	if eye_override is Vector3:
		return eye_override
	var main := main_node()
	if main != null and main.get("camera") != null and (main.camera as Node3D).is_inside_tree() \
			and room.is_inside_tree():
		return room.global_transform.affine_inverse() * (main.camera as Node3D).global_position
	return _seat_eye


func eye_now() -> Vector3:
	return _eye


func screen() -> Transform3D:
	return _screen


func screen_half() -> Vector2:
	return _half


## Whether p is in the sight line to the picture: between the eyes and the screen's plane, inside the pyramid from
## the eyes to the picture's edges widened by margin metres (at p's depth).
func in_view(p: Vector3, margin := -1.0) -> bool:
	return not _view_hit(p, margin).is_empty()


## [screen-plane point, k] when p is in the sight line; [] when not.
func _view_hit(p: Vector3, margin: float) -> Array:
	var m := float(params["keep_out"]) if margin < 0.0 else margin
	var e := _screen_inv * _eye
	var s := _screen_inv * p
	if e.z <= 0.05 or s.z <= 0.0 or s.z >= e.z:
		return []
	var k := e.z / (e.z - s.z)
	var on := Vector2(e.x + (s.x - e.x) * k, e.y + (s.y - e.y) * k)
	if absf(on.x) < _half.x + m * k and absf(on.y) < _half.y + m * k:
		return [on, k, e, s]
	return []


## p moved the least way out of the sight line (sideways or up, never down through a floor below the picture's
## bottom unless that is nearest) and out of the viewer's face.
func keep(p: Vector3, margin := -1.0) -> Vector3:
	var m := float(params["keep_out"]) if margin < 0.0 else margin
	var q := p
	var r := float(params["personal"])
	var away := q - _eye
	if away.length() < r:
		q = _eye + (away.normalized() if away.length() > 1e-4 else Vector3.UP) * r
	var hit := _view_hit(q, m)
	if hit.is_empty():
		return q
	var on: Vector2 = hit[0]
	var k: float = hit[1]
	var e: Vector3 = hit[2]
	var s: Vector3 = hit[3]
	var edge := Vector2(_half.x + m * k + 0.01, _half.y + m * k + 0.01)
	var best := on
	var best_d := INF
	for c: Vector2 in [Vector2(edge.x, on.y), Vector2(-edge.x, on.y), Vector2(on.x, edge.y), Vector2(on.x, -edge.y)]:
		var d := (c - on).length() * (1.4 if c.y < on.y and c.x == on.x else 1.0)
		if d < best_d:
			best_d = d
			best = c
	# Back from the screen's plane to p's depth along the line from the eyes.
	var back := Vector3(e.x + (best.x - e.x) / k, e.y + (best.y - e.y) / k, s.z)
	q = _screen * back
	away = q - _eye
	if away.length() < r:
		q = _eye + away.normalized() * r
	return q


## Whether every point along a..b (n steps) is clear of the sight line and the viewer's face.
func clear_line(a: Vector3, b: Vector3, n := 12) -> bool:
	for i in n + 1:
		var p := a.lerp(b, float(i) / float(n))
		if in_view(p) or p.distance_to(_eye) < float(params["personal"]):
			return false
	return true


## The document's region as an AABB, or null.
func region() -> Variant:
	var r: Variant = params.get("region")
	if not (r is Dictionary) or not (r as Dictionary).has("min") or not (r as Dictionary).has("max"):
		return null
	var lo := RoomSchemaRef.vec3(r["min"])
	var hi := RoomSchemaRef.vec3(r["max"])
	return AABB(lo.min(hi), (hi - lo).abs())


## A box round the viewer: dx to either side, from dy_lo to dy_hi over the eyes, from dz_back behind to dz_front
## in front (towards the screen).
func around_viewer(dx: float, dy_lo: float, dy_hi: float, dz_front: float, dz_back: float) -> AABB:
	var f := forward()
	var side := f.cross(Vector3.UP).normalized()
	var corners: Array[Vector3] = []
	for sx: float in [-dx, dx]:
		for sy: float in [dy_lo, dy_hi]:
			for sz: float in [-dz_back, dz_front]:
				corners.append(_seat_eye + side * sx + Vector3.UP * sy + f * sz)
	var box := AABB(corners[0], Vector3.ZERO)
	for c in corners:
		box = box.expand(c)
	return box


## The eyes over the room's own seat (the one nearest the room's origin).
func seat_eye() -> Vector3:
	return _seat_eye


## Horizontal, from the viewer towards the screen.
func forward() -> Vector3:
	var f := _screen.origin - _seat_eye
	f.y = 0.0
	return f.normalized() if f.length() > 0.01 else Vector3.FORWARD


func path_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p: Variant in params.get("path", []):
		out.append(RoomSchemaRef.vec3(p))
	return out


## The creature's own number, or the document's (the null and 0 rules of count and every).
func every_or(own: float) -> float:
	return float(params["every"]) if params.get("every") != null else own


func colour_or(own: Color) -> Color:
	return color_param("colour") if params.get("colour") != null else own


## The projector's beam (a screen system with a lens and its beam on): {lens, on}; {} when there is none.
func beam() -> Dictionary:
	if host == null:
		return {}
	for s: Node in host.systems_of_kind("screen"):
		if s.params.has("lens") and bool(s.params.get("beam", false)):
			var b := room.get_node_or_null("Beam") as Node3D
			return {"lens": RoomSchemaRef.vec3(s.params["lens"]), "on": b == null or b.visible}
	return {}


## A point in the beam: t from the lens (0) to the screen (1), u and v across the picture (-0.5..0.5).
func beam_point(lens: Vector3, t: float, u: float, v: float) -> Vector3:
	var on := _screen * Vector3(u * _half.x * 2.0, v * _half.y * 2.0, 0.0)
	return lens.lerp(on, t)


## How much of the beam's light p is in (0 outside it, 1 in its middle), stronger near the lens.
func beam_light(lens: Vector3, p: Vector3) -> float:
	var l := _screen_inv * lens
	var s := _screen_inv * p
	if l.z <= 0.01 or s.z <= 0.0 or s.z >= l.z:
		return 0.0
	var t := (l.z - s.z) / l.z
	var q := Vector2(l.x + (s.x - l.x) / t, l.y + (s.y - l.y) / t)
	var inside := (1.0 - smoothstep(_half.x * 0.85, _half.x * 1.05, absf(q.x))) \
			* (1.0 - smoothstep(_half.y * 0.85, _half.y * 1.05, absf(q.y)))
	return inside * lerpf(2.5, 0.6, t)


# --- Calls ----------------------------------------------------------------------------------------------------------------

## A creature's moment (a call, a purr, a song): an event, and its sound where the synthesiser has one.
func call_out(what: String, sound: String, at: Vector3) -> void:
	events.append([what, at])
	creature_event.emit(what, at)
	if bool(params["voice"]) and sound != "" and sound in EnvDoc.SOUNDS and host != null:
		host.play_sound(sound, float(params["voice_db"]), [at.x, at.y, at.z])


# --- Tests ----------------------------------------------------------------------------------------------------------------

func positions() -> Array:
	return creature.positions() if creature != null and fade > 0.0 else []


func bounds() -> Array:
	return creature.bounds() if creature != null and fade > 0.0 else []
