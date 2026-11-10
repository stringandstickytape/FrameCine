extends "res://tests/env_builder_harness.gd"

## The passing system (scripts/env/systems/passing.gd; docs/environments/passing.md): scenery that goes by outside a
## cabin's windows on a journey as long as the film. A test room (the shopfront hall with a passing system after it)
## passes the checks; the journey follows the film under the comfort limits: it starts and stops no faster than
## FLOW_ACCEL, keeps with the film, holds on a pause, goes dark and moves on a seek, arrives as a film of known length
## ends, never arrives with no length, and stops under the Motion setting's floor; the comfort hooks catch scenery that
## passes too near or too fast; the shaders' uniforms and the presence texture are as the journey says.
## godot --headless --xr-mode off --path app --script res://tests/test_env_passing.gd

const Passing := preload("res://scripts/env/systems/passing.gd")
const Shapes := preload("res://scripts/env/systems/passing/shapes.gd")
const DT := 1.0 / 30.0

## The film as the timeline sees it (the host's snapshot_override); _step() moves its position on while it plays.
var _snap := {"open": false}


func run_tests() -> void:
	test_name = "test_env_passing"
	var doc := _doc("Passing test", _params())
	# 1. The checks, and the system's nodes, triangles and draws (15).
	var room := await check_room("passing", doc, "hall")
	var sys: Node = room.host.system("passing")
	check("the passing system is built", sys != null)
	if sys == null:
		return
	var tris := {}
	for n: String in ["Passing", "PassingLights", "PassingGround"]:
		var mi := room.get_node_or_null(n) as MeshInstance3D
		check("%s exists" % n, mi != null and mi.mesh != null)
		tris[n] = mi.mesh.get_faces().size() / 3 if mi != null and mi.mesh != null else -1
	print("  triangles: %s" % [tris])
	var with_draws := int(EnvChecks.measure(room)["draws"])
	var plain := await _build(_doc("Passing test without", {}, false))
	var without_draws := int(EnvChecks.measure(plain)["draws"])
	await done(plain)
	print("  draws: %d with the system, %d without" % [with_draws, without_draws])
	check("three draws more with the system (%d, %d)" % [with_draws, without_draws], with_draws - without_draws == 3)
	_comfort()
	await _flow(room, sys)
	_presence(sys)
	_journey(room, sys)
	await done(room)
	await _fresh_motion()
	await _arrival()
	await _backward()
	await _moon_road()
	await _ahead()


## The test room's passing parameters: a row of posts near by, a far ridge that seems further off still, far lights
## that come in over the first half of the route; water beside the way and grass beyond it.
func _params(extra := {}) -> Dictionary:
	var p := {"speed": 1.0,
			"bands": [{"shape": "post", "near": 6, "far": 9, "count": 30},
					{"shape": "ridge", "near": 150, "seems": 20, "length": 170},
					{"shape": "lights", "near": 60, "far": 120, "count": 40, "seems": 4,
							"presence": [[0.0, 0.0], [0.5, 1.0]]}],
			"ground": [{"kind": "water", "from": 2.9, "to": 8}, {"kind": "grass", "from": 8, "to": 170}]}
	p.merge(extra, true)
	return p


func _doc(room_name: String, params: Dictionary, with_passing := true) -> Dictionary:
	var systems: Array = [{"system": "shopfront", "id": "hall"}]
	if with_passing:
		systems.append({"system": "passing", "params": params})
	return room_doc(room_name, systems, screen_of("shopfront"))


## A room built without the checks, stepped by hand.
func _build(doc: Dictionary) -> Node3D:
	var room: Node3D = EnvRoom.new()
	room.doc = doc
	root.add_child(room)
	await process_frame
	room.host.auto = false
	return room


## Steps the room for `seconds`, the film's position moving on while it plays (up to `until`, its end); `watch`
## is called after each step.
func _step(room: Node3D, seconds: float, watch := Callable(), until := INF) -> void:
	room.host.snapshot_override = _snap
	for i in roundi(seconds / DT):
		if bool(_snap.get("playing", false)):
			_snap["position"] = minf(float(_snap.get("position", 0.0)) + DT, until)
		room.host.step(DT)
		if watch.is_valid():
			watch.call()


# --- 10. Comfort ------------------------------------------------------------------------------------------------------

func _comfort() -> void:
	var spec: Dictionary = Registry.spec("passing")["params"]
	var ok: Array = Passing.comfort_for(EnvDoc.with_defaults(spec, _params()))
	check("comfort_for: the test room's parameters are fine %s" % [ok], ok.is_empty())
	# (This band seems twice as far as it is: at the test room's speed a post 2 m off would also cross the eye at
	# 33 degrees a second, a second problem; so only the first shows.)
	var near: Array = Passing.comfort_for(EnvDoc.with_defaults(spec, {"speed": 1.0,
			"bands": [{"shape": "post", "near": 2, "seems": 2}]}))
	check("comfort_for: a band 2 m off is one problem %s" % [near], near.size() == 1
			and str(near[0]).contains("nearer than"))
	var fast_params := {"speed": 5.0, "bands": [{"shape": "post", "near": 4}]}
	var fast: Array = Passing.comfort_for(EnvDoc.with_defaults(spec, fast_params))
	check("comfort_for: at 5 m/s a band 4 m off crosses the eye too fast %s" % [fast], fast.size() == 1
			and str(fast[0]).contains("crosses the eye"))
	# A shape is judged by how near any part of it comes, not by where its foot stands (Shapes.nearest()).
	var crown: Array = Passing.comfort_for(EnvDoc.with_defaults(spec, {"speed": 1.0,
			"bands": [{"shape": "tree", "near": 9, "far": 20}]}))
	check("comfort_for: a tree whose foot is 9 m off is judged by its crown %s" % [crown], crown.size() == 1
			and str(crown[0]).contains("crosses the eye"))
	var wood: Array = Passing.comfort_for(EnvDoc.with_defaults(spec, {"speed": 1.0,
			"bands": [{"shape": "tree", "near": 12, "far": 20}]}))
	check("comfort_for: at 12 m its crown is clear %s" % [wood], wood.is_empty())
	# The ground cannot be refused, so its pattern is held still where it would cross the eye too fast.
	check("still_within: at walking pace the ground is still inside %.2f m" % Passing.still_within(1.0),
			absf(Passing.still_within(1.0) - 1.15 / deg_to_rad(EnvChecks.FLOW_MAX_DEG)) < 0.001
			and Passing.still_within(1.0) > EnvChecks.FLOW_NEAREST)
	check("still_within: slower than that, never nearer than FLOW_NEAREST (%.2f)" % Passing.still_within(0.5),
			Passing.still_within(0.5) == EnvChecks.FLOW_NEAREST)
	check("still_within: at 12 m/s, 40 m (%.1f)" % Passing.still_within(12.0),
			absf(Passing.still_within(12.0) - 39.5) < 0.5)
	var moored: Array = Passing.comfort_for(EnvDoc.with_defaults(spec, {"speed": 1.0,
			"landmarks": [{"shape": "boat", "at": 0.5, "distance": 3.5}]}))
	check("comfort_for: a moored boat 3.5 m off is judged by its side, a metre nearer %s" % [moored],
			moored.size() >= 1 and str(moored[0]).contains("nearer than"))
	var arch: Array = Passing.comfort_for(EnvDoc.with_defaults(spec, {"speed": 1.0,
			"landmarks": [{"shape": "bridge", "at": 0.5, "distance": 4.5, "height": 0.5, "size": 1.3}]}))
	check("comfort_for: a bridge whose piers stand 4.5 m off goes over well clear %s" % [arch], arch.is_empty())
	check("nearest: a lamp's lantern hangs over the eyes' height, so its post is what comes near (%.2f)"
			% Shapes.nearest("lamp", 1.0, 5.0, 0.0, 1.2), absf(Shapes.nearest("lamp", 1.0, 5.0, 0.0, 1.2) - 4.69) < 0.01)
	# The ground a landmark stands on (Shapes.clearing()).
	var wharf := Shapes.clearing("wharf", 1.0, 1.0, 4.5)
	check("clearing: a wharf on the right, 4.5 m off: 11.5 m each way, from 2.5 to 15.5 across %s" % [wharf],
			wharf.is_equal_approx(Vector3(11.5, 2.5, 15.5)))
	var left := Shapes.clearing("wharf", 1.0, -1.0, 4.5)
	check("clearing: the same on the left is its mirror %s" % [left], left.is_equal_approx(Vector3(11.5, -15.5, -2.5)))
	var bridge := Shapes.clearing("bridge", 1.0, 1.0, 6.0)
	check("clearing: a bridge clears both sides of the way %s" % [bridge], bridge.y == -bridge.z and bridge.z == 15.0)
	check("clearing: a lamp stands on nothing", Shapes.clearing("lamp", 1.0, 1.0, 5.0) == Vector3.ZERO)
	# A document without a shape is a mistake in the document.
	var errors: Array = EnvDoc.validate(_doc("Passing with no shape", {"bands": [{"near": 6}]}))["errors"]
	check("a band without a shape does not pass the schema %s" % [errors.slice(0, 1)],
			errors.any(func(e: Variant) -> bool: return str(e).contains("shape") and str(e).contains("missing")))
	var all: Array = EnvChecks.comfort(_doc("Passing too fast", fast_params))
	check("the comfort check carries it, the system's id in front %s" % [all],
			all.any(func(s: Variant) -> bool: return str(s).begins_with("passing: band 0 (post): crosses the eye")))


# --- 11. Clear of the picture -----------------------------------------------------------------------------------------

func _flow(room: Node3D, sys: Node) -> void:
	var clear: Array = await EnvChecks.flow_clear(self, room)
	check("flow_clear: nothing goes by near the picture (the hall's walls are solid) %s" % [clear], clear.is_empty())
	var boxes: Array = sys.flow_volumes()
	var ok := boxes.size() >= 2
	if ok:
		var left: AABB = boxes[0]
		var right: AABB = boxes[1]
		# From where a post reaches to (its near less 0.07) to its far.
		ok = is_equal_approx(left.position.x, -9.0) and is_equal_approx(left.end.x, -5.93) \
				and is_equal_approx(right.position.x, 5.93) and is_equal_approx(right.end.x, 9.0)
	check("flow_volumes: the first band's left and right boxes %s" % [boxes.slice(0, 2)], ok)


# --- 14. Presence -----------------------------------------------------------------------------------------------------

func _presence(sys: Node) -> void:
	var img: Image = sys.presence_image()
	var x := int(0.25 * Passing.PRESENCE_WIDTH)
	var v := img.get_pixel(x, 2).r if img != null and img.get_height() >= 3 else -1.0
	check("presence: the third band at route fraction 0.25 is 0.5 (%.3f)" % v, absf(v - 0.5) <= 0.05)


# --- 2 to 9, 12, 13. The journey --------------------------------------------------------------------------------------

func _journey(room: Node3D, sys: Node) -> void:
	var host: Node = room.host
	host.auto = false
	var speed := 1.0
	# 2. Before a film.
	_snap = {"open": false}
	_step(room, 5.0)
	check("before a film: travel 0, speed 0 (%.3f, %.3f)" % [sys.travel, sys.speed_now], sys.travel == 0.0
			and sys.speed_now == 0.0)
	# 3. Playing from the start: it gathers speed at the limit.
	_snap = {"open": true, "playing": true, "position": 0.0, "duration": 0.0}
	var w := {"last": float(sys.speed_now), "jump": 0.0, "top": 0.0}
	var watch := func() -> void:
		w["jump"] = maxf(float(w["jump"]), absf(float(sys.speed_now) - float(w["last"])))
		w["top"] = maxf(float(w["top"]), float(sys.speed_now))
		w["last"] = float(sys.speed_now)
	_step(room, 2.0, watch)
	check("2 s playing: speed 0.6 (%.3f)" % sys.speed_now, absf(float(sys.speed_now) - 0.6) <= 0.05)
	# 4. A minute in: with the film.
	_step(room, 58.0, watch)
	check("no step changes the speed faster than the limit (%.6f)" % w["jump"],
			float(w["jump"]) <= EnvChecks.FLOW_ACCEL * DT + 1e-6)
	check("never faster than speed and its catch-up (%.4f)" % w["top"],
			float(w["top"]) <= speed * (1.0 + Passing.CATCH_UP) + 1e-6)
	var pos := float(_snap["position"])
	check("60 s playing: with the film (travel %.2f, position %.2f)" % [sys.travel, pos],
			absf(float(sys.travel) - speed * pos) < 2.0)
	# 12. The channel under way.
	check("journey.speed under way: 1 (%.3f)" % host.channel("journey.speed"),
			absf(float(host.channel("journey.speed")) - 1.0) <= 0.05)
	# 5. A pause: it stops, never going back.
	_snap["playing"] = false
	var stopped_at := -1.0
	var t := 0.0
	var back := false
	var last_travel := float(sys.travel)
	while t < 10.0:
		_step(room, DT)
		t += DT
		back = back or float(sys.travel) < last_travel
		last_travel = float(sys.travel)
		if float(sys.speed_now) == 0.0 and stopped_at < 0.0:
			stopped_at = t
	var limit := speed * (1.0 + Passing.CATCH_UP) / EnvChecks.FLOW_ACCEL + 0.5
	check("paused: stopped in %.2f s (at most %.2f)" % [stopped_at, limit], stopped_at >= 0.0 and stopped_at <= limit)
	check("paused: travel never went back", not back)
	check("journey.speed stopped: 0 (%.3f)" % host.channel("journey.speed"),
			float(host.channel("journey.speed")) == 0.0)
	# 6. A seek of +1000 s while playing: dark, then there.
	_snap["playing"] = true
	_step(room, 5.0)
	var before := float(sys.travel)
	_snap["position"] = float(_snap["position"]) + 1000.0
	var b := {"moved_lit": 0.0, "dark_step": 0.0, "last_dark": float(sys.dark), "dark_at": -1.0, "back_at": -1.0,
			"t": 0.0}
	var blink_watch := func() -> void:
		b["t"] = float(b["t"]) + DT
		b["dark_step"] = maxf(float(b["dark_step"]), absf(float(sys.dark) - float(b["last_dark"])))
		b["last_dark"] = float(sys.dark)
		if float(b["dark_at"]) < 0.0:
			if float(sys.dark) >= 1.0:
				b["dark_at"] = b["t"]
			else:
				b["moved_lit"] = maxf(float(b["moved_lit"]), absf(float(sys.travel) - before))
		elif float(b["back_at"]) < 0.0 and float(sys.dark) <= 0.0:
			b["back_at"] = b["t"]
	_step(room, Passing.BLINK_OUT + Passing.BLINK_IN + 0.3, blink_watch)
	check("seek: dark (at %.2f s) before travel moved more than 5 m (%.2f)" % [b["dark_at"], b["moved_lit"]],
			float(b["dark_at"]) > 0.0 and float(b["moved_lit"]) <= 5.0)
	pos = float(_snap["position"])
	check("seek: then with the film (travel %.2f, position %.2f)" % [sys.travel, pos],
			absf(float(sys.travel) - speed * pos) < 2.0)
	check("seek: lit again within %.1f s (%.2f)" % [Passing.BLINK_OUT + Passing.BLINK_IN + 0.3, b["back_at"]],
			float(b["back_at"]) > 0.0 and float(sys.dark) == 0.0)
	check("seek: no step changes dark faster than going dark over BLINK_OUT (%.4f)" % b["dark_step"],
			float(b["dark_step"]) <= DT / Passing.BLINK_OUT + 1e-6)
	# 13. Far along (a seek to 5000 s): the first band's phase, computed in 64 bits.
	_snap["position"] = 5000.0
	_step(room, 20.0)
	var phase: PackedFloat32Array = sys.material_of("Passing").get_shader_parameter("phase")
	var want := fposmod(float(sys.travel), 240.0)
	check("phase of band 0 after a long way (%.4f, %.4f; travel %.2f)" % [phase[0], want, sys.travel],
			absf(phase[0] - want) <= 0.001)
	# 8. A film with no length, an hour in: half way, and never there.
	_snap["position"] = 3600.0
	_step(room, 3.0)
	check("no length, an hour in: progress 0.5 (%.3f; travel %.1f)" % [host.channel("journey.progress"), sys.travel],
			absf(float(host.channel("journey.progress")) - 0.5) <= 0.02)
	# 9. The Motion setting: under its floor the journey stops (no faster than the limit), holds, nothing jumps.
	_snap["position"] = 100.0
	_step(room, 5.0)
	pos = float(_snap["position"])
	check("at 100 s: travel near 100 (%.2f)" % sys.travel, absf(float(sys.travel) - speed * pos) < 2.0)
	host.set_setting("motion", 0.2)
	var mw := {"last": float(sys.speed_now), "jump": 0.0, "dark": 0.0}
	var motion_watch := func() -> void:
		mw["jump"] = maxf(float(mw["jump"]), absf(float(sys.speed_now) - float(mw["last"])))
		mw["last"] = float(sys.speed_now)
		mw["dark"] = maxf(float(mw["dark"]), float(sys.dark))
	_step(room, 4.0, motion_watch)
	var held := float(sys.travel)
	_step(room, 2.0, motion_watch)
	check("Motion 0.2: stopped (%.3f), no faster than the limit (%.6f)" % [sys.speed_now, mw["jump"]],
			float(sys.speed_now) == 0.0 and float(mw["jump"]) <= EnvChecks.FLOW_ACCEL * DT + 1e-6)
	check("Motion 0.2: travel holds (%.3f, %.3f), nothing jumps (dark %.2f)" % [held, sys.travel, mw["dark"]],
			float(sys.travel) == held and float(mw["dark"]) == 0.0)
	check("Motion 0.2: its own speed still 1 (%.3f)" % sys.own_speed, is_equal_approx(float(sys.own_speed), 1.0))
	host.set_setting("motion", 1.0)
	_step(room, 60.0)
	pos = float(_snap["position"])
	check("Motion back to 1: with the film again (travel %.2f, position %.2f)" % [sys.travel, pos],
			absf(float(sys.travel) - speed * pos) < 2.0)


## 9. A room entered with the Motion setting under its floor, at 100 s: the journey has not left.
func _fresh_motion() -> void:
	var room := await _build(_doc("Passing test", _params()))
	var sys: Node = room.host.system("passing")
	room.host.set_setting("motion", 0.2)
	_snap = {"open": true, "playing": true, "position": 100.0, "duration": 0.0}
	_step(room, 1.0)
	check("entered at Motion 0.2: travel 0 (%.3f)" % sys.travel, float(sys.travel) == 0.0)
	await done(room)


## 7. A film of 600 s: the route is its length less the slowing; the cabin arrives as the film ends.
func _arrival() -> void:
	var room := await _build(_doc("Passing test", _params()))
	var sys: Node = room.host.system("passing")
	var speed := 1.0
	_snap = {"open": true, "playing": false, "position": 0.0, "duration": 600.0}
	_step(room, DT)
	var route := speed * 600.0 - speed * speed / (2.0 * Passing.BRAKE)
	check("route for 600 s: %.3f (%.3f)" % [sys.route_length(), route], absf(float(sys.route_length()) - route) <= 0.01)
	_snap["playing"] = true
	_step(room, 570.0, Callable(), 600.0)
	var a := {"last": float(sys.speed_now), "rose": 0.0}
	var watch := func() -> void:
		a["rose"] = maxf(float(a["rose"]), float(sys.speed_now) - float(a["last"]))
		a["last"] = float(sys.speed_now)
	_step(room, 30.0, watch, 600.0)
	check("the film ends: travel already within 0.5 of the route (%.3f, %.3f)" % [sys.travel, sys.route_length()],
			absf(float(sys.travel) - float(sys.route_length())) <= 0.5)
	_snap["ended"] = true
	_snap["playing"] = false
	_step(room, 3.0, watch, 600.0)
	check("arrived: travel at the route's end (%.3f, %.3f), stopped (%.4f)" % [sys.travel, sys.route_length(),
			sys.speed_now], absf(float(sys.travel) - float(sys.route_length())) <= 0.3 and float(sys.speed_now) == 0.0)
	check("over the last 30 s the speed never rose (%.9f)" % a["rose"], float(a["rose"]) <= 0.0)
	await done(room)


## 16. Facing backward: the way goes towards +Z, its right towards -X.
func _backward() -> void:
	var room := await _build(_doc("Passing test", _params({"facing": "backward"})))
	var sys: Node = room.host.system("passing")
	_snap = {"open": false}
	_step(room, DT)
	var m: ShaderMaterial = sys.material_of("Passing")
	var along: Vector3 = m.get_shader_parameter("along_dir")
	var across: Vector3 = m.get_shader_parameter("across_dir")
	check("backward: along (0, 0, 1) %s, across (-1, 0, 0) %s" % [along, across],
			along.is_equal_approx(Vector3(0, 0, 1)) and across.is_equal_approx(Vector3(-1, 0, 0)))
	await done(room)


## 17. The Moon's road on the water: the ground's shader has the sky's Moon, where it stands and how bright its road
## is (sky.gd moon_shine()): less while the sky is light, none at `moon_road` 0, none under a sky with no Moon.
func _moon_road() -> void:
	var moon := {"moon": 0.8, "moon_bearing": 100.0, "moon_altitude": 14.0, "moon_phase": 0.9, "dusk": 1.0}
	var room := await _build(_sky_doc(moon))
	var sys: Node = room.host.system("passing")
	var sky: Node = room.host.system("sky")
	_snap = {"open": false}
	_step(room, DT)
	var m: ShaderMaterial = sys.material_of("PassingGround")
	var want := 0.8 * lerpf(0.6, 1.0, smoothstep(0.05, 0.3, sin(deg_to_rad(14.0)))) * 0.9
	var got := float(m.get_shader_parameter("moon"))
	check("a Moon at night: its road on the water at %.3f (%.3f)" % [want, got], absf(got - want) < 0.001)
	var dir: Vector3 = m.get_shader_parameter("moon_dir")
	check("... towards the Moon %s, 14 degrees up" % dir, dir.is_equal_approx(sky.moon_direction())
			and absf(rad_to_deg(asin(dir.y)) - 14.0) < 0.01)
	sky.set_param("dusk", 0.0)
	_step(room, DT)
	var light := float(m.get_shader_parameter("moon"))
	check("under a sky still light the road is at %.2f of that (%.3f)" % [sky.MOON_ROAD_IN_TWILIGHT, light],
			absf(light - want * float(sky.MOON_ROAD_IN_TWILIGHT)) < 0.001)
	sky.set_param("dusk", 1.0)
	sys.set_param("moon_road", 0.0)
	_step(room, DT)
	check("moon_road 0: no road", float(m.get_shader_parameter("moon")) == 0.0)
	await done(room)
	var moonless := await _build(_sky_doc({"dusk": 1.0}))
	_step(moonless, DT)
	var none: ShaderMaterial = moonless.host.system("passing").material_of("PassingGround")
	check("a sky with no Moon: no road", float(none.get_shader_parameter("moon")) == 0.0)
	await done(moonless)


## The test room under a sky (before the passing system, which takes its light from it).
func _sky_doc(sky_params: Dictionary) -> Dictionary:
	return room_doc("Passing test", [{"system": "shopfront", "id": "hall"}, {"system": "sky", "params": sky_params},
			{"system": "passing", "params": _params()}], screen_of("shopfront"))


## 18. A landmark's `ahead`: metres along the way from its place on the route. At the journey's start a lamp 20 m
## ahead is 20 m ahead; when a film of 600 s ends, a lamp set 12 m before the route's end is 12 m astern, as it would
## be for a film of any length.
func _ahead() -> void:
	var room := await _build(_doc("Passing test", _params({"landmarks": [
			{"shape": "lamp", "at": 0.0, "ahead": 20.0, "distance": 8.0},
			{"shape": "lamp", "at": 1.0, "ahead": -12.0, "distance": 8.0}]})))
	var sys: Node = room.host.system("passing")
	_snap = {"open": true, "playing": false, "position": 0.0, "duration": 600.0}
	_step(room, DT)
	var m: ShaderMaterial = sys.material_of("Passing")
	var along: PackedFloat32Array = m.get_shader_parameter("landmark_along")
	check("ahead 20 at the start: 20 m ahead (%.3f)" % along[0], absf(along[0] - 20.0) < 0.001)
	check("ahead -12 at the end: the route's length less 12 away (%.3f)" % along[1],
			absf(along[1] - (float(sys.route_length()) - 12.0)) < 0.001)
	_snap = {"open": true, "playing": false, "ended": true, "position": 600.0, "duration": 600.0}
	sys.travel = float(sys.route_length())
	_step(room, DT)
	along = m.get_shader_parameter("landmark_along")
	check("arrived: that lamp is 12 m astern (%.3f)" % along[1], absf(along[1] + 12.0) < 0.05)
	await done(room)
