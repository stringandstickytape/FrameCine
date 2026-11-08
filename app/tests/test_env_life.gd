extends SceneTree

## Ambient life (docs/environments.md, "Ambient life"): the life system and its nine creatures in a test room (the
## cinema's hall with every creature in it), built headless. The room passes the checks (schema, budget, sight line,
## comfort, licences, names, no people); no creature is ever in the sight line to the picture or in the viewer's face,
## and no walker stays in the sight line long; moths keep to the beam; the whale passes on its quiet-scene cue once
## (its cooldown holds the next), sings on the Environment bus under the level target; fireflies dim with a bright film
## and steady with Flickering lights off; the fish come closer to the screen in a bright scene; birds scatter and come
## back to their perches; the cat sits; the deer visits and leaves; a plane crosses high; Ambient life off fades them
## out. Every creature's MultiMesh layout is the engine's.
## godot --headless --xr-mode off --path app --script res://tests/test_env_life.gd

const EnvRoom := preload("res://scripts/env/env_room.gd")
const EnvDoc := preload("res://scripts/env/env_doc.gd")
const EnvChecks := preload("res://scripts/env/env_checks.gd")
const EnvAudio := preload("res://scripts/env/env_audio.gd")
const EnvSynth := preload("res://scripts/env/env_synth.gd")
const Registry := preload("res://scripts/env/systems/registry.gd")
const Life := preload("res://scripts/env/systems/life.gd")
const Creature := preload("res://scripts/env/systems/life/creature.gd")

const FLOCKS := ["moths", "birds", "fireflies", "fish", "school", "jellies", "planes"]
const WALKERS := ["cat", "deer", "whale", "rays"]

var _failures := 0
var _checks := 0


func _init() -> void:
	_run.call_deferred()


static func test_doc() -> Dictionary:
	return {"schema": 4, "name": "Life test",
		"room": {"ambient": 0.05, "screen_glow": 1.0},
		"screen": {"center": [0.0, 1.6, -13.8], "size": [12.0, 5.0]},
		"systems": [
			{"system": "light"},
			{"system": "auditorium", "id": "hall"},
			{"system": "screen_frame"},
			{"system": "life", "id": "moths", "params": {"creature": "moth", "attraction": 0.9}},
			{"system": "life", "id": "birds", "params": {"creature": "bird"}},
			{"system": "life", "id": "fireflies", "params": {"creature": "firefly",
				"glow": {"bind": "film.brightness", "range": [1.0, 0.2], "smooth": 1.0}}},
			{"system": "life", "id": "cat", "params": {"creature": "cat",
				"path": [[-8.5, 1.4, -10.0], [-8.5, 1.4, 2.0]]}},
			{"system": "life", "id": "deer", "params": {"creature": "deer", "every": 0}},
			{"system": "life", "id": "fish", "params": {"creature": "fish",
				"region": {"min": [-9.0, 3.5, -12.0], "max": [9.0, 8.5, 4.0]},
				"attraction": {"bind": "film.brightness", "range": [0.0, 1.0], "smooth": 2.0}}},
			{"system": "life", "id": "jellies", "params": {"creature": "jelly", "attraction": 0.8,
				"colour": {"bind": "film.colour", "strength": 0.5, "base": "#59bfff", "smooth": 1.0}}},
			{"system": "life", "id": "whale", "params": {"creature": "whale"}},
			{"system": "life", "id": "planes", "params": {"creature": "plane", "every": 0}},
			{"system": "life", "id": "rays", "params": {"creature": "ray", "every": 0}},
			{"system": "life", "id": "school", "params": {"creature": "fish", "schooling": 1.0, "count": 30,
				"region": {"min": [-9.0, 4.0, -12.0], "max": [9.0, 8.5, 2.0]}}},
		],
		"cues": [{"name": "whale", "when": {"signal": "film.quiet", "above": 0.9, "for": 4},
			"states": ["playing"], "chance": 1.0, "cooldown": 900, "steps": [{"do": "whale.pass"}]}]}


func _steps(h: Node, seconds: float, dt := 0.05, each := Callable()) -> void:
	var t := 0.0
	while t < seconds - 1e-6:
		h.step(dt)
		t += dt
		if each.is_valid():
			each.call()


func _run() -> void:
	_spec()
	_layout()
	var doc := test_doc()
	var v := EnvDoc.validate(doc)
	_check("the test room is valid (%s)" % [v["errors"]], v["ok"])
	var stat := EnvChecks.static_checks(doc)
	for k: String in stat:
		_check("the test room: %s %s" % [k, stat[k]], (stat[k] as Array).is_empty())
	var room: Node3D = EnvRoom.new()
	room.doc = doc
	root.add_child(room)
	var h: Node = room.host
	h.auto = false
	await process_frame
	var stats := EnvChecks.measure(room)
	print("  the test room: %s" % [stats])
	# Texture memory is the headset's, rendered or not (env_checks.gd measure()).
	var limits := EnvChecks.BUDGET.duplicate()
	_check("within the headset's budget %s" % [EnvChecks.budget(stats, limits)], EnvChecks.budget(stats, limits).is_empty())
	var blocked: Array = await EnvChecks.sight_line(self, room)
	_check("a clear sight line from every seat (%s)" % [blocked], blocked.is_empty())
	_costs(room)
	h.snapshot_override = {"open": true, "playing": true, "position": 600.0, "duration": 6000.0}
	_kept_out(h)
	_timing(h)
	_moths(h)
	_whale(h)
	_fireflies(h)
	await _whale_level()
	_fish(h)
	_schooling(h)
	_birds(h)
	_cat_deer_planes(h)
	_life_off(h)
	room.queue_free()
	await process_frame
	print("test_env_life: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _spec() -> void:
	_check("life is registered, of kind life", Registry.has("life") and Registry.spec("life")["kind"] == "life")
	var s: Dictionary = Registry.spec("life")
	_check("ten creatures", (s["params"]["creature"]["values"] as Array).size() == 10)
	_check("its actions: pass, scatter, settle, call", (s["actions"] as Dictionary).has_all(["pass", "scatter",
			"settle", "call"]))
	for p: String in ["glow", "colour"]:
		_check("%s is a live brightness" % p, bool(s["params"][p].get("live")) and bool(s["params"][p].get("brightness")))
	_check("blink flickers (steady with Flickering lights off)", bool(s["params"]["blink"].get("flicker")))
	var bad := {"schema": 4, "name": "Bad", "systems": [{"system": "life", "params": {"creature": "usher"}}]}
	_check("no such creature", not EnvDoc.validate(bad)["ok"])
	var unsmoothed := {"schema": 4, "name": "Fast", "systems": [{"system": "life", "params": {"creature": "firefly",
			"glow": {"bind": "film.transient"}}}]}
	_check("a glow following the film unsmoothed is refused by the comfort check",
			EnvChecks.comfort(unsmoothed).size() == 1)
	var not_live := {"schema": 4, "name": "Count", "systems": [{"system": "life", "params": {"count":
			{"bind": "film.bass"}}}]}
	_check("count is built once: no film binding", not EnvDoc.validate(not_live)["ok"])
	var bad_do := {"schema": 4, "name": "Do", "systems": [{"system": "life", "id": "whale",
			"params": {"creature": "whale"}}], "cues": [{"name": "x", "when": {"every": 60},
			"steps": [{"do": "whale.dance"}]}]}
	_check("a cue may call only its actions", not EnvDoc.validate(bad_do)["ok"])


## The MultiMesh buffer as creature.gd writes it is the engine's layout (rendered runs only: headless, the server keeps
## no buffer).
func _layout() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var c: RefCounted = Creature.new()
	var holder := Node3D.new()
	root.add_child(holder)
	var fake := Node.new()
	fake.set_script(load("res://scripts/env/systems/env_system.gd"))
	fake.set("room", holder)
	fake.set("params", {"glow": 1.0})
	c.life = fake
	var q := QuadMesh.new()
	c.multimesh(q, 2, c.glow_material(Color.WHITE, 0), Creature.WIDE, "T")
	var xf := Transform3D(Basis(Vector3(0.3, 0.7, 0.1).normalized(), 0.8).scaled(Vector3(1, 2, 3)), Vector3(4, 5, 6))
	c.put(1, xf, Color(0.1, 0.2, 0.3, 0.4), Color(0.5, 0.6, 0.7, 0.8))
	c.flush()
	var back: Transform3D = c.mm.get_instance_transform(1)
	_check("the buffer's transform is the engine's (%s / %s)" % [back, xf], back.is_equal_approx(xf))
	_check("its colour and custom data", c.mm.get_instance_color(1).is_equal_approx(Color(0.1, 0.2, 0.3, 0.4))
			and c.mm.get_instance_custom_data(1).is_equal_approx(Color(0.5, 0.6, 0.7, 0.8)))
	holder.free()
	fake.free()


func _costs(room: Node3D) -> void:
	var worst := 0
	for id: String in FLOCKS + WALKERS:
		var s: Node = room.host.system(id)
		var g: GeometryInstance3D = s.creature.instance
		var tris := 0
		if g is MultiMeshInstance3D:
			var mm := (g as MultiMeshInstance3D).multimesh
			tris = EnvChecks._triangles(mm.mesh) * mm.instance_count
		else:
			tris = EnvChecks._triangles((g as MeshInstance3D).mesh)
		worst = maxi(worst, tris)
		print("  %s: %d x, %d triangles, 1 draw" % [id, s.creature.count, tris])
		_check("%s: one draw, in the see-through group" % id, g.is_in_group(Creature.SEE_THROUGH)
				and (s.owned() as Array).size() == 1)
	_check("the spec's cost holds the largest (%d)" % worst, worst <= int(Registry.spec("life")["cost"]["triangles"]))


## Two minutes of everything: never in the sight line or the viewer's face; walkers through it briefly at most.
func _kept_out(h: Node) -> void:
	for id: String in WALKERS + ["planes"]:
		h.system(id).act("pass", {})
	var worst := []
	var faces := []
	var seen := {}
	var check := func() -> void:
		for id: String in FLOCKS + WALKERS:
			var s: Node = h.system(id)
			var eye: Vector3 = s.eye_now()
			for b: Array in s.bounds():
				var p: Vector3 = b[0]
				var r: float = minf(float(b[1]), 1.0)
				seen[id] = true
				if id in FLOCKS and s.in_view(p, r) and worst.size() < 5:
					worst.append([id, p])
				if p.distance_to(eye) < float(s.params["personal"]) - 0.01 and faces.size() < 5:
					faces.append([id, p])
	_steps(h, 120.0, 0.05, check)
	_check("every creature showed (%s)" % [seen.keys()], seen.size() == FLOCKS.size() + WALKERS.size())
	_check("no flier ever in the sight line to the picture %s" % [worst], worst.is_empty())
	_check("none in the viewer's face %s" % [faces], faces.is_empty())
	for id: String in WALKERS:
		var s: Node = h.system(id)
		_check("%s: never long in the sight line (%.1f s)" % [id, s.longest_in_view], s.longest_in_view < 4.0)


## The CPU a frame of every creature takes (all nine at their default counts), on this machine.
func _timing(h: Node) -> void:
	var frames := 200
	var each := 0.0
	var parts: Array[String] = []
	for id: String in FLOCKS + WALKERS:
		var t0 := Time.get_ticks_usec()
		for i in frames:
			h.system(id).tick(1.0 / 90.0)
		var ms := float(Time.get_ticks_usec() - t0) / float(frames) / 1000.0
		each += ms
		parts.append("%s %.3f" % [id, ms])
	print("  the nine creatures' ticks: %.2f ms a frame (desktop): %s" % [each, ", ".join(parts)])
	_check("their ticks under 3 ms a frame on the desktop (%.2f)" % each, each < 3.0)


func _moths(h: Node) -> void:
	var m: Node = h.system("moths")
	var lens: Vector3 = m.beam()["lens"]
	var lit := 0
	for p: Vector3 in m.positions():
		if m.beam_light(lens, p) > 0.05:
			lit += 1
	_check("moths: most in the beam, catching its light (%d of %d)" % [lit, m.positions().size()],
			lit > m.positions().size() / 2)
	var over := 0
	var eye: Vector3 = m.eye_now()
	for p: Vector3 in m.positions():
		if p.y > eye.y:
			over += 1
	_check("moths: over the viewer's head (%d)" % over, over > m.positions().size() / 2)


func _whale(h: Node) -> void:
	var w: Node = h.system("whale")
	_steps(h, 120.0)
	var passes: int = w.creature.passes
	_check("whale: not passing at first", not w.creature.passing)
	h.signals.fake("film.quiet", 1.0)
	_steps(h, 5.0)
	_check("whale: a quiet scene for 4 s calls it (%d -> %d)" % [passes, w.creature.passes],
			w.creature.passes == passes + 1 and w.creature.passing)
	var sounds_before: int = h.sounds.size()
	# [showed, in front of the screen's plane] (a lambda changes an array, not a local).
	var seen := [false, false]
	_steps(h, 90.0, 0.05, func() -> void:
		if not w.positions().is_empty():
			seen[0] = true
			var p: Vector3 = w.positions()[0]
			if (w.screen().affine_inverse() * p).z > 0.0:
				seen[1] = true)
	_check("whale: it showed and went, behind the screen's plane (%s)" % [seen], seen[0] and not seen[1]
			and not w.creature.passing)
	_check("whale: it sang on the Environment bus (%s)" % [h.sounds.slice(sounds_before)],
			h.sounds.slice(sounds_before).any(func(s: Array) -> bool: return s[0] == "whale"))
	_check("whale: its song an event", w.events.any(func(e: Array) -> bool: return e[0] == "whale_song"))
	h.signals.fake("film.quiet", 0.0)
	_steps(h, 2.0)
	h.signals.fake("film.quiet", 1.0)
	_steps(h, 10.0)
	_check("whale: the cooldown holds the next (%d)" % w.creature.passes, w.creature.passes == passes + 1)
	h.signals.fake("film.quiet", 0.0)


func _whale_level() -> void:
	var level: float = await EnvAudio.measure_level(self, [[EnvSynth.stream("whale"),
			float(Registry.spec("life")["params"]["voice_db"]["default"])]], 1.5)
	print("  the whale's song at the default %.1f dBFS RMS (target %.1f)" % [level, EnvAudio.LEVEL_TARGET_DB])
	_check("whale: its song under the level target with 2 dB to spare (%.1f)" % level,
			level < EnvAudio.LEVEL_TARGET_DB - 2.0)


func _fireflies(h: Node) -> void:
	var f: Node = h.system("fireflies")
	h.signals.fake("film.brightness", 0.0)
	_steps(h, 6.0)
	var dark := float(f.params["glow"])
	h.signals.fake("film.brightness", 0.9)
	_steps(h, 6.0)
	var bright := float(f.params["glow"])
	_check("fireflies: dim in a bright scene (%.2f -> %.2f)" % [dark, bright], dark > 0.9 and bright < 0.4)
	_check("fireflies: the shader has it", is_equal_approx(float(f.creature.material.get_shader_parameter("glow")),
			bright))
	h.signals.fake("film.brightness", 0.0)
	var flashes: int = f.creature.flashes
	_steps(h, 5.0)
	_check("fireflies: they flash (%d)" % (f.creature.flashes - flashes), f.creature.flashes - flashes > 20)
	h.set_setting("flicker", false)
	_steps(h, 0.2)
	var steady: Array = f.creature.lights()
	_check("fireflies: Flickering lights off, steady (%s)" % [steady.slice(0, 4)], not bool(f.params["blink"])
			and steady.all(func(x: float) -> bool: return is_equal_approx(x, 0.55)))
	h.set_setting("flicker", true)
	_check("fireflies: blinking again", bool(f.params["blink"]))
	f.set_param("activity", 0.0)
	_steps(h, 3.0)
	_check("fireflies: activity 0, none out", f.positions().is_empty())
	f.set_param("activity", 1.0)
	_steps(h, 0.1)


func _fish(h: Node) -> void:
	var f: Node = h.system("fish")
	h.signals.fake("film.brightness", 0.0)
	_steps(h, 40.0)
	var light: Vector3 = f.creature.light_point()
	var dark := _mean(f.positions()).distance_to(light)
	h.signals.fake("film.brightness", 1.0)
	_steps(h, 40.0)
	var bright := _mean(f.positions()).distance_to(light)
	_check("fish: drawn to the screen in a bright scene (%.1f m -> %.1f m)" % [dark, bright], bright < dark - 1.0)
	h.signals.fake("film.brightness", 0.0)


## A schooling school (schooling 1): longer along its way than across it, and its turns reach the back later than the
## front (the back follows where the school was a moment before).
func _schooling(h: Node) -> void:
	var s: Node = h.system("school")
	var fish: RefCounted = s.creature
	_steps(h, 20.0)
	var along_sum := 0.0
	var across_sum := 0.0
	for o: Vector3 in fish.slot:
		along_sum += absf(o.z)
		across_sum += absf(o.x)
	var plain: RefCounted = h.system("fish").creature
	_check("school: drawn in and longer along its way than across it (%.1f, %.1f; plain %.2f m apart, schooling "
			% [along_sum, across_sum, plain._spread] + "%.2f)" % fish._spread, along_sum > across_sum * 1.8
			and fish._spread < plain._spread)
	_check("school: its history reaches back over the lag (%d samples)" % fish._history.size(),
			fish._history.size() >= int(fish.LAG / fish.HISTORY_STEP))
	var then: Array = fish._recall(fish.LAG)
	_check("school: the back follows where the school was (%.2f m behind now)" % (then[0] as Vector3).distance_to(
			fish.centre), (then[0] as Vector3).distance_to(fish.centre) > 0.05)


func _mean(ps: Array) -> Vector3:
	var c := Vector3.ZERO
	for p: Vector3 in ps:
		c += p
	return c / maxf(float(ps.size()), 1.0)


func _birds(h: Node) -> void:
	var b: Node = h.system("birds")
	var bird: RefCounted = b.creature
	_check("birds: they flit between perches (%d flights)" % bird.flights, bird.flights > 0)
	b.act("scatter", {})
	_steps(h, 0.5)
	_check("birds: scattered, all in the air", Array(bird.mode).all(func(m: int) -> bool: return m != 0))
	_steps(h, 30.0)
	var perched := Array(bird.mode).filter(func(m: int) -> bool: return m == 0).size()
	_check("birds: back on their perches (%d of %d)" % [perched, bird.count], perched >= bird.count - 1)


func _cat_deer_planes(h: Node) -> void:
	var c: Node = h.system("cat")
	c.act("settle", {})
	_steps(h, 2.0)
	_check("cat: it sits (pose %.2f) and purrs (an event)" % c.creature.pose, c.creature.pose > 0.9
			and c.events.any(func(e: Array) -> bool: return e[0] == "purr"))
	var y: float = c.positions()[0].y
	_check("cat: on its wall (%.2f)" % y, absf(y - 1.55) < 0.01)
	var d: Node = h.system("deer")
	_steps(h, 90.0)
	_check("deer: away between visits (every 0: only on a cue)", d.positions().is_empty())
	var visits: int = d.creature.visits
	d.act("pass", {"side": "left"})
	_steps(h, 1.0)
	_check("deer: a visit (%d)" % d.creature.visits, d.creature.visits == visits + 1 and not d.positions().is_empty())
	_steps(h, 120.0)
	_check("deer: it left", d.positions().is_empty())
	var pl: Node = h.system("planes")
	pl.act("pass", {"side": "right"})
	_steps(h, 10.0)
	var eye: Vector3 = pl.seat_eye()
	var ps: Array = pl.positions()
	_check("planes: one crossing (%d)" % ps.size(), ps.size() == 1)
	if not ps.is_empty():
		var p: Vector3 = ps[0]
		var el := asin(clampf((p - eye).normalized().y, -1.0, 1.0))
		_check("planes: high and far (%.0f m, %.0f degrees up)" % [p.distance_to(eye), rad_to_deg(el)],
				absf(p.distance_to(eye) - 160.0) < 1.0 and el > 0.25)
	_steps(h, 200.0)
	_check("planes: gone over", pl.positions().is_empty())


func _life_off(h: Node) -> void:
	h.set_setting("life", false)
	_steps(h, 2.0)
	var shown := []
	for id: String in FLOCKS + WALKERS:
		var s: Node = h.system(id)
		for n: Node in s.owned():
			if (n as Node3D).visible:
				shown.append(id)
	_check("Ambient life off: all faded and hidden %s" % [shown], shown.is_empty())
	var cat: Node = h.system("cat")
	h.set_setting("life", true)
	_steps(h, 2.0)
	_check("Ambient life on: back", (cat.owned()[0] as Node3D).visible and cat.fade >= 1.0)


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)
