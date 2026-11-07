extends SceneTree

## The motion system (docs/environments.md, "The motion system"): in a small room, an organ console rises from the
## pit within the speed and acceleration limits, an action's seconds is a wish the limits cap, the ritual's cue starts
## it; a painting in front of the screen does not count against the sight line and goes away by itself once the film
## has played a few seconds; a curtain sways within its angle and the room's Motion setting scales it, stopping eases
## it back; a globe turns within its rate and acceleration; a festoon curtain rises in swags; under reduced Motion a
## travel snaps, or fades out and back in, even when a cue's fade leads it; the room passes the checks, and a motion
## over its limit is refused.
## godot --headless --xr-mode off --path app --script res://tests/test_env_motion.gd

const EnvChecks := preload("res://scripts/env/env_checks.gd")
const EnvDoc := preload("res://scripts/env/env_doc.gd")
const EnvRoom := preload("res://scripts/env/env_room.gd")
const Motion := preload("res://scripts/env/systems/motion.gd")
const ScreenFrame := preload("res://scripts/env/systems/screen_frame.gd")
const Registry := preload("res://scripts/env/systems/registry.gd")

const DT := 1.0 / 90.0

var _failures := 0
var _checks := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_spec()
	await _checks_pass()
	await _organ()
	await _painting()
	await _reduced()
	await _sway()
	await _turn()
	await _festoon()
	print("test_env_motion: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _doc() -> Dictionary:
	return {"schema": 4, "name": "Motion test", "screen": {"center": [0.0, 1.8, -7.0], "size": [5.0, 2.8]},
		"room": {"curtains": false},
		"systems": [
			{"system": "light"},
			{"system": "motion", "id": "organ", "params": {"node": "Console", "path": [[0.0, 2.8, 0.0]],
				"speed": 0.3, "accel": 0.15}},
			{"system": "motion", "id": "painting", "params": {"node": "Painting", "path": [[0.0, 3.0, 0.0]],
				"in_front": true, "reduced": "fade"}},
			{"system": "motion", "id": "curtain", "params": {"node": "Drape", "mode": "sway", "sway_angle": 2.0,
				"sway_period": 6.0, "pivot": [0.0, 1.5, 0.0]}},
			{"system": "motion", "id": "earth", "params": {"node": "Globe", "mode": "turn", "turn_rate": 10.0}},
			{"system": "motion", "id": "festoon", "params": {"build": "festoon"}},
		],
		"cues": [{"name": "ritual", "when": {"state": "starting"}, "requires": [{"setting": "ritual"}],
			"steps": [{"do": "organ.rise", "args": {"seconds": 12}}, {"do": "festoon.rise", "args": {"seconds": 8}}]}]}


func _box(n: String, size: Vector3, at: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = at
	return mi


func _make(doc := _doc()) -> Node3D:
	var room: Node3D = EnvRoom.new()
	room.doc = doc
	room.add_child(_box("Console", Vector3(2.0, 1.5, 1.0), Vector3(0.0, -3.5, -5.0)))
	room.add_child(_box("Painting", Vector3(5.4, 3.2, 0.05), Vector3(0.0, 1.8, -6.9)))
	room.add_child(_box("Drape", Vector3(1.0, 3.0, 0.1), Vector3(-3.5, 1.5, -6.8)))
	var globe := MeshInstance3D.new()
	globe.name = "Globe"
	var sphere := SphereMesh.new()
	sphere.radial_segments = 16
	sphere.rings = 8
	globe.mesh = sphere
	globe.position = Vector3(4.0, 3.0, -6.0)
	room.add_child(globe)
	root.add_child(room)
	room.host.auto = false
	return room


func _steps(room: Node3D, seconds: float) -> void:
	for i in int(round(seconds / DT)):
		room.host.step(DT)


func _free(room: Node3D) -> void:
	room.queue_free()
	await process_frame


func _spec() -> void:
	var s := Registry.spec("motion")
	_check("registered, kind motion, never the viewer", str(s.get("kind")) == "motion"
			and s.get("moves_viewer") == false)
	for a: String in ["rise", "lower", "go", "snap", "start", "stop"]:
		_check("action %s" % a, (s["actions"] as Dictionary).has(a))
	for p: String in ["speed", "accel", "turn_speed", "sway_angle", "sway_shift", "turn_rate"]:
		_check("%s declares its comfort limit, and its range ends there" % p, s["params"][p].has("motion")
				and is_equal_approx(float(s["params"][p]["motion"]["max"]), float(s["params"][p]["max"])))
	var bad := _doc()
	bad["systems"][1]["params"]["speed"] = 0.8
	_check("a speed over the limit refused", not EnvDoc.validate(bad)["ok"])
	bad = _doc()
	bad["systems"][4]["params"]["turn_rate"] = {"bind": "film.progress", "range": [0.0, 40.0]}
	_check("a binding past the turn's limit refused", not EnvDoc.validate(bad)["ok"])
	bad = _doc()
	bad["cues"][0]["steps"].append({"do": "organ.fly"})
	_check("an action it doesn't have refused", not EnvDoc.validate(bad)["ok"])


func _checks_pass() -> void:
	var doc := _doc()
	var r := EnvDoc.validate(doc)
	_check("the test room's schema %s" % [r["errors"]], r["ok"])
	var s := EnvChecks.static_checks(doc)
	for k: String in s:
		_check("checks: %s %s" % [k, s[k]], (s[k] as Array).is_empty())
	var room := _make()
	await process_frame
	var stats := EnvChecks.measure(room)
	print("  motion room: %s" % [stats])
	_check("within the budget %s" % [EnvChecks.budget(stats)], EnvChecks.budget(stats).is_empty())
	var festoon := room.get_node_or_null("Festoon") as MeshInstance3D
	_check("the festoon built: %d triangles" % EnvChecks._triangles(festoon.mesh), festoon != null
			and EnvChecks._triangles(festoon.mesh) <= 1300)
	var painting := room.get_node("Painting")
	_check("the painting and the festoon are in front: see-through for the check, grouped for the film layer",
			painting.is_in_group(ScreenFrame.SEE_THROUGH) and painting.is_in_group(Motion.IN_FRONT)
			and festoon.is_in_group(Motion.IN_FRONT))
	var blocked: Array = await EnvChecks.sight_line(self, room)
	_check("a clear sight line %s" % [blocked], blocked.is_empty())
	_check("the Motion setting applies here", room.common_applies("motion"))
	await _free(room)


func _organ() -> void:
	var room := _make()
	await process_frame
	var organ: Node = room.host.system("organ")
	var console := room.get_node("Console") as Node3D
	var y0 := console.position.y
	organ.recording = true
	room.host.do_action("organ.rise", {})
	var t := 0.0
	while organ.progress() < 1.0 and t < 40.0:
		room.host.step(DT)
		t += DT
	var tr: Array = organ.trace
	var vmax := 0.0
	var amax := 0.0
	var last_v := 0.0
	for i in range(1, tr.size()):
		var v: float = ((tr[i][1] as Vector3) - (tr[i - 1][1] as Vector3)).length() / DT
		vmax = maxf(vmax, v)
		if i > 1:
			amax = maxf(amax, absf(v - last_v) / DT)
		last_v = v
	_check("the organ rises 2.8 m (%.3f)" % (console.position.y - y0), is_equal_approx(console.position.y - y0, 2.8))
	_check("in %.1f s: its length over its speed and the ramps (11.3 s)" % t, t > 10.5 and t < 12.5)
	_check("never faster than its speed (%.3f m/s, 0.3)" % vmax, vmax <= 0.3 + 1e-3)
	_check("never speeding up or slowing faster than its accel (%.3f m/s2, 0.15)" % amax, amax <= 0.15 * 1.05)
	_check("straight up: x and z unchanged", is_equal_approx(console.position.x, 0.0)
			and is_equal_approx(console.position.z, -5.0))
	room.host.do_action("organ.lower", {"seconds": 20.0})
	t = 0.0
	while organ.progress() > 0.0 and t < 40.0:
		room.host.step(DT)
		t += DT
	_check("lower over 20 s: a wish it can keep (%.1f s)" % t, absf(t - 20.0) < 1.0)
	room.host.do_action("organ.rise", {"seconds": 2.0})
	t = 0.0
	while organ.progress() < 1.0 and t < 40.0:
		room.host.step(DT)
		t += DT
	_check("rise in 2 s: the limits win (%.1f s)" % t, t > 10.5)
	# The ritual: when the film starts from its start, the cue raises it.
	room.host.do_action("organ.snap", {"at": 0.0})
	room.host.snapshot_override = {"open": true, "playing": false, "position": 0.0, "duration": 3600.0}
	room.host.step(DT)
	room.host.snapshot_override = {"open": true, "playing": true, "position": 0.1, "duration": 3600.0}
	_steps(room, 3.0)
	_check("the ritual's cue raises it (%.2f)" % organ.progress(), room.host.timeline.state == "starting"
			and organ.progress() > 0.05 and organ.progress() < 1.0)
	_steps(room, 12.0)
	_check("risen in the ritual's 12 s", is_equal_approx(organ.progress(), 1.0))
	await _free(room)


func _painting() -> void:
	var room := _make()
	await process_frame
	var p: Node = room.host.system("painting")
	var painting := room.get_node("Painting") as Node3D
	room.host.snapshot_override = {"open": true, "playing": false, "position": 0.0, "duration": 3600.0}
	room.host.step(DT)
	_steps(room, 5.0)
	_check("in the pre-show the painting stays", is_equal_approx(p.progress(), 0.0))
	room.host.snapshot_override = {"open": true, "playing": true, "position": 0.1, "duration": 3600.0}
	_steps(room, 3.5)
	_check("the film started, no cue: still there for a moment", is_equal_approx(p.progress(), 0.0))
	_steps(room, 1.0)
	_check("after %.0f s it goes away by itself (%.2f)" % [Motion.CUE_GRACE, p.progress()], p.progress() > 0.0)
	_steps(room, 20.0)
	_check("up out of the way (%.2f)" % painting.position.y, is_equal_approx(painting.position.y, 1.8 + 3.0))
	await _free(room)


func _reduced() -> void:
	var room := _make()
	await process_frame
	room.host.set_setting("motion", 0.0)
	var organ: Node = room.host.system("organ")
	room.host.do_action("organ.rise", {"seconds": 12.0})
	room.host.step(DT)
	_check("reduced Motion: the organ snaps up", is_equal_approx(organ.progress(), 1.0))
	room.host.fade("organ.at", 0.0, 6.0)
	room.host.step(DT)
	room.host.step(DT)
	_check("a cue's fade leads it: it snaps to the end it heads for (%.2f)" % organ.progress(),
			is_equal_approx(organ.progress(), 0.0))
	_steps(room, 7.0)
	_check("and stays there", is_equal_approx(organ.progress(), 0.0))
	var p: Node = room.host.system("painting")
	var painting := room.get_node("Painting") as MeshInstance3D
	room.host.do_action("painting.rise", {})
	_steps(room, 0.25)
	_check("the painting fades out where it is (%.2f)" % painting.transparency, painting.transparency > 0.3
			and is_equal_approx(painting.position.y, 1.8))
	_steps(room, 0.4)
	_check("then is up, fading back in", is_equal_approx(painting.position.y, 4.8) and painting.transparency > 0.0
			and painting.transparency < 1.0)
	_steps(room, 0.5)
	_check("and shows again", is_equal_approx(painting.transparency, 0.0) and is_equal_approx(p.progress(), 1.0))
	_check("the sway and the turn scaled to nothing", is_zero_approx(float(room.host.system("curtain")
			.params["sway_angle"])) and is_zero_approx(float(room.host.system("earth").params["turn_rate"])))
	room.host.set_setting("motion", 0.5)
	_check("half Motion: half the speed (%.3f)" % float(organ.params["speed"]), is_equal_approx(float(
			organ.params["speed"]), 0.15))
	await _free(room)


## The sway's angle about z from rest, degrees (atan2 of the turned x axis: a quaternion's angle is too coarse in
## single precision for one frame's turn).
func _angle(n: Node3D, rest: Transform3D) -> float:
	var v := rest.basis.inverse() * (n.transform.basis * Vector3.RIGHT)
	return absf(rad_to_deg(atan2(v.y, v.x)))


## The turn about y, degrees.
func _yaw(n: Node3D) -> float:
	var v := n.transform.basis * Vector3.RIGHT
	return rad_to_deg(atan2(-v.z, v.x))


func _sway() -> void:
	var room := _make()
	await process_frame
	var drape := room.get_node("Drape") as Node3D
	var rest := Transform3D(Basis(), Vector3(-3.5, 1.5, -6.8))
	var top := 0.0
	var speed := 0.0
	var last := 0.0
	for i in int(12.0 / DT):
		room.host.step(DT)
		var a := _angle(drape, rest)
		top = maxf(top, a)
		speed = maxf(speed, absf(a - last) / DT)
		last = a
	_check("the curtain sways up to its 2 degrees (%.2f)" % top, top > 1.8 and top <= 2.0 + 1e-3)
	_check("slowly: about 2 x 2 pi / 6 degrees a second at most (%.2f)" % speed, speed <= 2.0 * TAU / 6.0 * 1.1)
	_check("about its top: the top edge stays (%.4f)" % (drape.transform * Vector3(0.0, 1.5, 0.0)).distance_to(
			rest * Vector3(0.0, 1.5, 0.0)), (drape.transform * Vector3(0.0, 1.5, 0.0)).distance_to(
			rest * Vector3(0.0, 1.5, 0.0)) < 1e-4)
	room.host.set_setting("motion", 0.5)
	top = 0.0
	for i in int(12.0 / DT):
		room.host.step(DT)
		top = maxf(top, _angle(drape, rest))
	_check("half Motion: half the sway (%.2f)" % top, top <= 1.0 + 1e-3 and top > 0.8)
	room.host.do_action("curtain.stop", {})
	_steps(room, 6.0)
	_check("stopped: it eases back to rest (%.4f)" % _angle(drape, rest), _angle(drape, rest) < 0.01)
	await _free(room)


func _turn() -> void:
	var room := _make()
	await process_frame
	var globe := room.get_node("Globe") as Node3D
	var prev := _yaw(globe)
	var speed := 0.0
	var accel := 0.0
	var last := 0.0
	for i in int(6.0 / DT):
		room.host.step(DT)
		var w := absf(wrapf(_yaw(globe) - prev, -180.0, 180.0)) / DT
		speed = maxf(speed, w)
		accel = maxf(accel, absf(w - last) / DT)
		last = w
		prev = _yaw(globe)
	_check("the globe turns at its 10 degrees a second (%.2f)" % speed, absf(speed - 10.0) < 0.05)
	_check("easing in at most %.0f degrees a second squared (%.2f)" % [Motion.MAX_TURN_ACCEL, accel],
			accel <= Motion.MAX_TURN_ACCEL * 1.05)
	_check("in place", globe.position.is_equal_approx(Vector3(4.0, 3.0, -6.0)))
	room.host.do_action("earth.stop", {})
	_steps(room, 2.0)
	prev = _yaw(globe)
	room.host.step(DT)
	_check("stopped", absf(_yaw(globe) - prev) < 1e-4)
	await _free(room)


func _festoon() -> void:
	var room := _make()
	await process_frame
	var f: Node = room.host.system("festoon")
	var mi := room.get_node("Festoon") as MeshInstance3D
	var h0 := mi.mesh.get_aabb().size.y
	_check("the festoon hangs over the screen, wider and deeper (%.2f x %.2f)" % [mi.mesh.get_aabb().size.x, h0],
			mi.mesh.get_aabb().size.x > 5.0 and h0 > 2.8)
	f.recording = true
	room.host.do_action("festoon.rise", {"seconds": 8.0})
	var t := 0.0
	var hem_speed := 0.0
	var last_hem: float = f.festoon_hem()
	while f.progress() < 1.0 and t < 40.0:
		room.host.step(DT)
		t += DT
		hem_speed = maxf(hem_speed, absf(f.festoon_hem() - last_hem) / DT)
		last_hem = f.festoon_hem()
	var h1 := mi.mesh.get_aabb().size.y
	_check("it rises in swags: the cloth gathers up (%.2f m to %.2f m)" % [h0, h1], h1 < h0 * 0.45)
	_check("its hem no faster than its speed (%.3f m/s)" % hem_speed, hem_speed <= 0.25 + 1e-3)
	_check("in about its 8 s (%.1f)" % t, absf(t - 8.0) < 1.5 or t > 8.0)
	await _free(room)


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)
