extends SceneTree

## The atmosphere system (scripts/env/systems/atmosphere.gd; docs/environments.md, "Atmosphere and weather") in a small
## test room (a hall like the cinema's with a beam): the haze takes screen_frame's lens and the screen's corners, a
## beam-shaped volume of six surfaces, see-through; it follows film.brightness and film.colour through bindings; ground
## fog in layers; breath puffs now and then from under the eyes, forward and down, never at eye level; the room passes
## the checks (budget, sight line, comfort, names, no people). No main scene.
## godot --headless --xr-mode off --path app --script res://tests/test_env_atmosphere.gd

const EnvChecks := preload("res://scripts/env/env_checks.gd")
const EnvDoc := preload("res://scripts/env/env_doc.gd")
const EnvRoom := preload("res://scripts/env/env_room.gd")
const Registry := preload("res://scripts/env/systems/registry.gd")
const Atmosphere := preload("res://scripts/env/systems/atmosphere.gd")
const ScreenFrame := preload("res://scripts/env/systems/screen_frame.gd")

var _failures := 0
var _checks := 0


func _init() -> void:
	_run.call_deferred()


static func test_doc() -> Dictionary:
	return {"schema": 4, "name": "Haze test", "room": {"ambient": 0.05, "screen_glow": 1.0},
		"screen": {"center": [0.0, 1.6, -13.8], "size": [12.0, 5.0]},
		"systems": [{"system": "light"}, {"system": "auditorium", "id": "hall"}, {"system": "screen_frame"},
			{"system": "atmosphere", "params": {
				"beam_haze": {"bind": "film.brightness", "range": [0.3, 1.0], "smooth": 0.5},
				"beam_dust": 0.6, "beam_smoke": 0.3,
				"beam_colour": {"bind": "film.colour", "strength": 0.5, "smooth": 0.5},
				"fog": 0.4, "fog_center": [0.0, -3.0, -11.0], "fog_size": [18.0, 5.0], "fog_walls": true,
				"breath": 0.8, "breath_seconds": 4.0}}]}


func _build(doc: Dictionary) -> Node3D:
	var room: Node3D = EnvRoom.new()
	room.doc = doc
	root.add_child(room)
	room.host.auto = false
	room.host.on_screen_changed(room.get_screen_anchor(), Vector2(12.0, 5.0))
	return room


func _steps(host: Node, seconds: float, delta := 0.1) -> void:
	for i in int(round(seconds / delta)):
		host.step(delta)


func _run() -> void:
	var s := Registry.spec("atmosphere")
	_check("registered, kind atmosphere", Registry.has("atmosphere") and s["kind"] == "atmosphere")
	_check("the beam's levels are brightness parameters (the comfort check holds them)",
			s["params"]["beam_haze"].get("brightness", false) and s["params"]["beam_dust"].get("brightness", false))
	var doc := test_doc()
	var v := EnvDoc.validate(doc)
	_check("the test room validates (%s)" % [v["errors"]], v["ok"])
	var st := EnvChecks.static_checks(doc)
	for k: String in st:
		_check("static check %s %s" % [k, st[k]], (st[k] as Array).is_empty())
	var room := _build(doc)
	await process_frame
	var host: Node = room.host
	var atm: Node = host.system("atmosphere")
	_check("built", atm != null and atm.get_script() == Atmosphere)
	# The beam.
	var sf: Node = host.system("screen_frame")
	var lv: Array = sf.params["lens"]
	_check("the haze takes screen_frame's lens (%s)" % atm.lens(), atm.lens().is_equal_approx(
			Vector3(lv[0], lv[1], lv[2])))
	var beam: MeshInstance3D = atm.beam()
	_check("a beam-shaped volume: four sides and a cross, one draw (%s)" % [beam.mesh],
			beam.mesh != null and beam.mesh.get_surface_count() == 1 and beam.mesh.get_faces().size() == 18)
	_check("see-through for the sight line", beam.is_in_group(ScreenFrame.SEE_THROUGH))
	var far := Vector3.ZERO
	for p: Vector3 in beam.mesh.get_faces():
		far = far if far.length() > p.length() else p
	var corner := 0.0
	for k: Vector2 in [Vector2(-6.0, 2.5), Vector2(6.0, 2.5), Vector2(6.0, -2.5), Vector2(-6.0, -2.5)]:
		corner = maxf(corner, (room.get_screen_anchor() * Vector3(k.x, k.y, 0.0) - atm.lens()).length())
	_check("it reaches the screen's corners (%.2f, %.2f)" % [far.length(), corner], absf(far.length() - corner) < 0.05)
	host.signals.fake("film.brightness", 1.0)
	host.signals.fake("film.colour", Color(1.0, 0.0, 0.0))
	_steps(host, 4.0)
	_check("shown (no main: the beam's rules say yes)", beam.visible)
	var haze := float(atm.params["beam_haze"])
	_check("a bright picture: thick haze (%.2f)" % haze, haze > 0.95)
	_check("the shader has it", is_equal_approx(float(atm.beam_material().get_shader_parameter("haze")), haze))
	var col: Color = atm.params["beam_colour"]
	_check("the film's colour, half way (%s)" % col, col.r > 0.95 and col.g < 0.6 and col.g > 0.35)
	host.signals.fake("film.brightness", 0.0)
	_steps(host, 4.0)
	_check("a dark picture: thin haze (%.2f)" % float(atm.params["beam_haze"]),
			absf(float(atm.params["beam_haze"]) - 0.3) < 0.03)
	host.signals.clear_fakes()
	# Fog.
	var fog: Node3D = atm.fog_node()
	_check("ground fog: four layers, see-through", fog != null and fog.get_child_count() == 4 and fog.visible
			and fog.get_children().all(func(n: Node) -> bool: return n.is_in_group(ScreenFrame.SEE_THROUGH)))
	var total := 0.0
	for m: ShaderMaterial in atm.fog_materials():
		total += float(m.get_shader_parameter("opacity"))
	_check("together the fog's opacity (%.3f)" % total, absf(total - 0.7 * 0.4) < 0.001)
	_check("its floor (%s)" % fog.position, fog.position.is_equal_approx(Vector3(0, -3, -11)))
	# Breath.
	var head := Transform3D(Basis(), Vector3(0.0, 1.2, 0.0))
	atm.head_override = head
	var before: int = atm.puffs
	_steps(host, 12.0)
	_check("breath: a puff now and then (%d in 12 s)" % (atm.puffs - before), atm.puffs - before >= 2
			and atm.puffs - before <= 4)
	var b: GPUParticles3D = atm.breath_node()
	var o: Transform3D = b.global_transform
	_check("from under the eyes and a little ahead (%s)" % o.origin, o.origin.is_equal_approx(
			Vector3(0.0, 1.2 - Atmosphere.BREATH_DOWN, -Atmosphere.BREATH_AHEAD)))
	var dir: Vector3 = o.basis * Atmosphere.BREATH_DIRECTION.normalized()
	_check("forward and down (%s)" % dir, dir.y < -0.2 and dir.z < -0.8)
	_check("a few particles, short lived", b.amount == Atmosphere.BREATH_PARTICLES and b.one_shot
			and b.lifetime <= 3.0)
	# Its reach: at the fastest, with no damping, the puff stays well under the eye line and far from the screen.
	var pm := b.process_material as ParticleProcessMaterial
	var worst := -90.0
	for t in range(0, 25):
		var tt := float(t) * 0.1
		var spread := deg_to_rad(pm.spread)
		var up := Basis(Vector3.RIGHT, spread) * Atmosphere.BREATH_DIRECTION.normalized()
		var p := Vector3(0, -Atmosphere.BREATH_DOWN, -Atmosphere.BREATH_AHEAD) + up * pm.initial_velocity_max * tt \
				+ pm.gravity * tt * tt * 0.5
		var size := 0.11 * 0.5
		worst = maxf(worst, rad_to_deg(atan2(p.y + size, -p.z)))
	_check("never at eye level: its top stays %.0f degrees under the eye line" % -worst, worst < -20.0)
	atm.head_override = Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(1.0, 1.2, 0.0))
	_steps(host, 6.0)
	o = b.global_transform
	_check("it follows the head's turn (%s)" % o.origin, o.origin.is_equal_approx(
			Vector3(1.0 - Atmosphere.BREATH_AHEAD, 1.2 - Atmosphere.BREATH_DOWN, 0.0)))
	atm.set_param("breath", 0.0)
	before = atm.puffs
	_steps(host, 10.0)
	_check("breath 0: none", atm.puffs == before and not b.visible)
	atm.set_param("breath", 0.8)
	atm.head_override = head
	_steps(host, 0.2)
	# The budget and the sight line, with everything showing.
	var stats := EnvChecks.measure(room)
	print("  haze test room: %s" % [stats])
	var over := EnvChecks.budget(stats)
	_check("within the headset's budget %s" % [over], over.is_empty())
	var own := {"draws": 0, "triangles": 0, "particles": 0}
	for n: Node in atm.owned():
		var holder := Node3D.new()
		var c := n.duplicate()
		holder.add_child(c)
		var m := EnvChecks.measure(holder)
		for k: String in own:
			own[k] += int(m[k])
		holder.free()
	print("  atmosphere's own: %s (spec: %s)" % [own, s["cost"]])
	_check("its cost as its spec says (%s)" % [own], own["draws"] <= int(s["cost"]["draws"])
			and own["triangles"] <= int(s["cost"]["triangles"]) and own["particles"] <= int(s["cost"]["particles"]))
	var blocked: Array = await EnvChecks.sight_line(self, room)
	_check("a clear sight line from every seat %s" % [blocked.slice(0, 2)], blocked.is_empty())
	_check("no live light", stats["lights"] == 0)
	fog = atm.fog_node()
	atm.set_param("fog", 0.0)
	_check("fog 0: hidden", not fog.visible)
	room.queue_free()
	await process_frame
	# Comfort: a brightness bound without smoothing is refused.
	var raw := test_doc()
	raw["systems"][3]["params"]["beam_haze"] = {"bind": "film.brightness"}
	_check("an unsmoothed beam haze fails the comfort check", not EnvChecks.comfort(raw).is_empty())
	# Without screen_frame: its own lens; without beam parameters: no beam at all (its cost stays honest).
	var alone := {"schema": 4, "name": "Alone", "screen": {"center": [0.0, 1.6, -8.0], "size": [6.0, 3.0]},
		"systems": [{"system": "atmosphere", "params": {"beam_haze": 0.5, "lens": [1.0, 2.0, 3.0]}}]}
	_check("alone validates (%s)" % [EnvDoc.validate(alone)["errors"]], EnvDoc.validate(alone)["ok"])
	room = _build(alone)
	await process_frame
	atm = room.host.system("atmosphere")
	_check("its own lens", atm.lens().is_equal_approx(Vector3(1, 2, 3)) and atm.beam() != null)
	_check("no fog, no breath unless asked", atm.fog_node() == null and atm.breath_node() == null)
	room.queue_free()
	var plain := {"schema": 4, "name": "Plain", "systems": [{"system": "atmosphere", "params": {"fog": 0.3}}]}
	room = _build(plain)
	await process_frame
	atm = room.host.system("atmosphere")
	_check("fog only: no beam", atm.beam() == null and atm.fog_node() != null)
	room.queue_free()
	await process_frame
	print("test_env_atmosphere: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)
