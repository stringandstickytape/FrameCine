extends SceneTree

## Tests for "Tune spatial sound" (scripts/play/spatial_tune.gd, docs/features.md #21, "Tuning"): the knockout's
## order against simulated listeners who prefer one set, one head size and one ear shape; the path round the head and
## the listener pose that keeps it fixed in the room while the head turns; the pulsed pink noise; and, in the real
## main scene, the step run with picks on its card (a pick before both are heard refused, Again, the menu's cancel
## changing nothing), its sound streamed, its result saved for the output profile, and the spatial_tune command.
## Settings are read-only.
## Run: godot --headless --xr-mode off --path app --script res://tests/test_spatial_tune.gd

const SpatialTune := preload("res://scripts/play/spatial_tune.gd")
const Layouts := preload("res://scripts/play/speaker_layouts.gd")
const DevCommands := preload("res://scripts/dev/dev_commands.gd")
const CommandHost := preload("res://scripts/dev/command_host.gd")
const SETS := ["sadie2_d1", "sadie2_d2", "sadie2_h3", "sadie2_h4", "sadie2_h5", "sadie2_h6"]
const ALL := ["sadie2_d1", "sadie2_d2", "sadie2_h3", "sadie2_h4", "sadie2_h5", "sadie2_h6", "mit_dummy", "hutubs_pp1",
		"ari_nh2", "cipic_003"]

var _failures := 0
var _checks := 0
var main: Node3D


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _run() -> void:
	CommandHost.ensure(self)
	await _frames(5)
	_knockout_checks()
	_path_checks()
	_stimulus_checks()
	await _step_checks()
	print("test_spatial_tune: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


## How much a listener likes a candidate: their set best, then nearest their head size and ear shape.
func _liking(v: Dictionary, best: String, itd: float, warp: float) -> float:
	return (10.0 if v.set == best else 0.0) - 20.0 * absf(float(v.tuning.itd_scale) - itd) \
			- 20.0 * absf(float(v.tuning.pinna_warp) - warp)


## Runs a knockout to the end with a listener; returns the picks made.
func _run_knockout(k: SpatialTune.Knockout, listener: Callable) -> int:
	var n := 0
	while n < 50:
		var pair := k.current()
		if pair.is_empty():
			break
		k.pick(listener.call(pair))
		n += 1
	return n


func _prefers(best: String, itd: float, warp: float) -> Callable:
	return func(pair: Dictionary) -> String:
		var a := _liking(pair.a, best, itd, warp)
		var b := _liking(pair.b, best, itd, warp)
		return "same" if is_equal_approx(a, b) else ("a" if a > b else "b")


func _knockout_checks() -> void:
	var K = SpatialTune.Knockout
	var k = K.new(SETS, "sadie2_d1", {"itd_scale": 0.9}, 7)
	var first: Dictionary = k.current()
	_check("the profile's set and tuning are the first champion", k.champion.set == "sadie2_d1"
			and is_equal_approx(float(k.champion.tuning.itd_scale), 0.9)
			and (first.a.set == "sadie2_d1" or first.b.set == "sadie2_d1"))
	_check("6 sets: 5 challengers, head size and ear shape, 9 picks", k.total == 9)
	var challengers: Array = []
	var champion_a := 0
	var n := 0
	while not k.current().is_empty() and k.stage == "sets":
		challengers.append(k.challenger.set)
		champion_a += 1 if k.a_is_champion else 0
		k.pick("same")
		n += 1
	_check("every other set challenges once (%s)" % [challengers], challengers == SETS.slice(1))
	_check("the champion is A in some picks, B in others (%d of %d A)" % [champion_a, n], champion_a > 0
			and champion_a < n)
	_check("Can't tell: the champion stays", k.champion.set == "sadie2_d1")
	var all = K.new(ALL, "sadie2_d1", {}, 3)
	_check("10 sets: no ear shape picks (%d)" % all.total, all.total == 9 + 2)
	var one = K.new(["sadie2_d1"], "sadie2_d1", {}, 3)
	_check("one set: head size and ear shape only (%d)" % one.total, one.total == 4 and one.stage == "itd_scale")

	# Listeners who know what they like, over 20 seeded runs.
	var right := 0
	var exact := 0
	var all_picks := true
	for run in 20:
		var kk = K.new(SETS, "sadie2_d1", {}, 100 + run)
		var picks := _run_knockout(kk, _prefers("sadie2_h4", 1.1, 1.07))
		var r: Dictionary = kk.result()
		all_picks = all_picks and picks == kk.total and kk.stage == "done" and kk.done == picks
		right += 1 if r.set == "sadie2_h4" and r.changed else 0
		exact += 1 if is_equal_approx(float(r.tuning.itd_scale), 1.1) \
				and is_equal_approx(float(r.tuning.pinna_warp), 1.07) else 0
	_check("the picks made are the picks counted", all_picks)
	_check("their set wins (%d of 20)" % right, right == 20)
	_check("their head size and ear shape found, a step away (%d of 20)" % exact, exact == 20)
	var far := 0
	for run in 20:
		var kk = K.new(SETS, "sadie2_d1", {}, 200 + run)
		_run_knockout(kk, _prefers("sadie2_d1", 1.3, 1.0))
		var itd := float(kk.result().tuning.itd_scale)
		far += 1 if itd > 1.05 and itd < 1.25 else 0
	_check("two steps away: one step toward it (%d of 20)" % far, far == 20)
	var unsure = K.new(SETS, "sadie2_h3", {"itd_scale": 1.2, "pinna_warp": 0.93, "concha_db": 3.0}, 9)
	_run_knockout(unsure, func(_p: Dictionary) -> String: return "same")
	var ur: Dictionary = unsure.result()
	_check("Can't tell throughout: nothing changes", not ur.changed and ur.set == "sadie2_h3"
			and is_equal_approx(float(ur.tuning.itd_scale), 1.2) and is_equal_approx(float(ur.tuning.concha_db), 3.0))
	# At the limit: a bigger head can't go past 1.3; the count shrinks to the picks made.
	var limit_ok := true
	for run in 10:
		var kk = K.new(["sadie2_d1"], "sadie2_d1", {"itd_scale": 1.3}, 300 + run)
		var picks := _run_knockout(kk, func(p: Dictionary) -> String:
			for v: Dictionary in [p.a, p.b]:
				limit_ok = limit_ok and float(v.tuning.itd_scale) <= 1.3 + 1e-6
			return "a" if float(p.a.tuning.itd_scale) > float(p.b.tuning.itd_scale) else "b")
		limit_ok = limit_ok and picks == kk.total and is_equal_approx(float(kk.result().tuning.itd_scale), 1.3)
	_check("at the limit: never past it, and the count matches", limit_ok)
	# What the next pick may bring is known before this one is made (so it loads while this one plays).
	var foreseen := true
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for run in 10:
		var kk = K.new(SETS, "sadie2_d2", {"itd_scale": 1.1}, 400 + run)
		while not kk.current().is_empty():
			var ahead: Array = kk.upcoming()
			var before: int = kk.done
			kk.pick(["a", "b", "same"][rng.randi_range(0, 2)])
			foreseen = foreseen and kk.done == before + 1 and kk.history.size() == kk.done
			if not kk.challenger.is_empty():
				foreseen = foreseen and ahead.any(func(v: Dictionary) -> bool:
					return K.same(v, kk.challenger))
	_check("the next challenger is always one foreseen", foreseen)
	var h: Dictionary = k.history[0]
	_check("the history keeps each pick", k.history.size() == 5 and h.stage == "sets" and h.choice == "same"
			and not h.won)


func _path_checks() -> void:
	var T := SpatialTune.PLAY_SECONDS
	var c := T * SpatialTune.CIRCLE_SHARE
	var near := func(v: Vector3, az: float, el: float) -> bool:
		return v.distance_to(Layouts.vector(az, el)) < 0.01
	_check("the path starts in front", near.call(SpatialTune.path(0.0, T) * Vector3.FORWARD, 0, 0))
	_check("a quarter round: on the right", near.call(SpatialTune.path(c * 0.25, T) * Vector3.FORWARD, 90, 0))
	_check("half round: behind", near.call(SpatialTune.path(c * 0.5, T) * Vector3.FORWARD, 180, 0))
	_check("three quarters: on the left", near.call(SpatialTune.path(c * 0.75, T) * Vector3.FORWARD, -90, 0))
	_check("then up over the top", near.call(SpatialTune.path(c + (T - c) * 90.0 / 150.0, T) * Vector3.FORWARD, 0, 90))
	_check("and down behind, 30 degrees up", near.call(SpatialTune.path(T, T) * Vector3.FORWARD, 180, 30))
	var smooth := true
	var last := Vector3.FORWARD
	for i in 600:
		var d := SpatialTune.path(T * i / 599.0, T) * Vector3.FORWARD
		smooth = smooth and d.angle_to(last) < deg_to_rad(3.0)
		last = d
	_check("the path has no jumps", smooth)
	# Head tracking: the source stays in the room. The frame faces right; at a quarter round the source is behind the
	# room's front... seen from a head turned toward it, it is straight ahead.
	var frame := Basis(Vector3.UP, -PI / 2.0)
	var turn := SpatialTune.path(c * 0.25, T)
	var world := frame * turn * Vector3.FORWARD
	_check("the round's frame turns the path (a quarter round from facing right: behind)",
			world.distance_to(Layouts.vector(180, 0)) < 0.01)
	var heads := [Transform3D(Basis(), Vector3(0, 1.6, 0)), Transform3D(Basis(Vector3.UP, PI), Vector3(0.3, 1.5, 0.2)),
			Transform3D(Basis(Vector3.UP, 0.7) * Basis(Vector3.RIGHT, -0.4), Vector3.ZERO)]
	var held := true
	for head: Transform3D in heads:
		var pose := SpatialTune.listener_pose(head, frame, turn)
		var heard := pose.basis.inverse() * Vector3.FORWARD # The source as the renderer hears it, in the head.
		var want := head.basis.inverse() * world
		held = held and heard.distance_to(want) < 1e-4 and pose.origin == head.origin
	_check("whichever way the head turns, the source is heard where it is in the room", held)
	var facing := SpatialTune.listener_pose(Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO), frame, turn)
	_check("a head turned to it hears it straight ahead",
			(facing.basis.inverse() * Vector3.FORWARD).distance_to(Vector3.FORWARD) < 1e-4)


func _stimulus_checks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var rate := 48000.0
	var s := SpatialTune.stimulus(2.0, rate, rng)
	var peak := 0.0
	for v in s:
		peak = maxf(peak, absf(v))
	_check("the sound: %d frames, peak %.3f" % [s.size(), peak], s.size() == 96000 and peak > 0.05 and peak < 0.5
			and absf(s[0]) < 1e-4 and absf(s[s.size() - 1]) < 1e-4)
	# Pulses: loud in the middle of each, silent between them.
	var on := 0.0
	var off := 0.0
	for p in 7:
		var base := int(p * SpatialTune.PULSE * rate)
		for i in range(base + int(0.05 * rate), base + int(0.12 * rate)):
			on += s[i] * s[i]
		for i in range(base + int(0.19 * rate), base + int(0.24 * rate)):
			off += s[i] * s[i]
	_check("the sound pulses: four a second, silent between", on > 1.0e-3 and off < 1e-9)
	var e := 0.0
	var d := 0.0
	for i in range(1, s.size()):
		e += s[i] * s[i]
		d += (s[i] - s[i - 1]) * (s[i] - s[i - 1])
	_check("pink: falls with frequency (high band %.2f of white's 2.0)" % (d / e), d / e < 1.0)


## The step itself: picks go through the card's buttons (no controllers headless: card.click at a button).
func _step_checks() -> void:
	var t: Node = main.features.spatial_tune
	var sp: Node = main.features.speakers
	if not sp.available():
		print("SKIP the step (no BinauralRenderer in this engine)")
		return
	var card: Node = main.ui.card
	var hrtf_before := str(sp.hrtf)
	t.play_seconds = 0.6
	# Cancel: nothing changes.
	sp.set_profile_tuning({"itd_scale": 1.2})
	t.start()
	_check("started: running, a card with A and B", t.running and card.is_showing() and card.id == "spatial_tune"
			and card.action_point("a") != null and card.action_point("b") != null)
	var st: Dictionary = t.status()
	_check("status: the first pick of %d, head measurements" % st.picks, st.stage == "sets" and st.pick == 1
			and st.picks == t.search.total and st.picks >= 9)
	t._on_menu(null)
	await _frames(2)
	_check("the menu button cancels; nothing changed", not t.running and sp.hrtf == hrtf_before
			and is_equal_approx(float(sp.profile_settings().tuning.itd_scale), 1.2)
			and not (sp.profile_settings().tuning as Dictionary).has("tuned_at"))
	sp.set_profile_tuning({})

	t.start()
	await _until(func() -> bool: return t.status().playing == "a", 5.0)
	_check("A plays first", t.status().playing == "a")
	await _click("a")
	_check("a pick before both are heard is refused", t.status().pick == 1 and card.is_showing()
			and str(card._text.text).contains("both first"))
	await _until(func() -> bool: return t.status().playing == "b", 5.0)
	_check("then B", t.status().playing == "b")
	await _until(func() -> bool: return t.status().heard_both, 5.0)
	_check("both heard; the sound was rendered (peak %.3f)" % t._peak, t.status().heard_both and t._peak > 0.01)
	await _click("again")
	await _until(func() -> bool: return t.status().playing == "a", 5.0)
	_check("Again plays A again", t.status().playing == "a" and t.status().pick == 1)
	var r: Dictionary = await DevCommands.execute("spatial_tune", {"action": "status"}, false)
	_check("spatial_tune status: the same", r["ok"] and r["result"]["running"] and r["result"]["pick"] == 1)
	# The rest: always B, through the card; then one through the command.
	var picks := 0
	var end := Time.get_ticks_msec() + 120000
	while t.running and Time.get_ticks_msec() < end:
		await process_frame
		if t.status().heard_both:
			if picks == 1:
				r = await DevCommands.execute("spatial_tune", {"action": "same"}, false)
			else:
				await _click("b")
			picks += 1
	_check("the step ran every pick (%d)" % picks, not t.running and picks == t.search.total)
	var res: Dictionary = t.search.result()
	var saved: Dictionary = sp.profile_settings().tuning
	_check("the result saved for the profile: %s, %s" % [res.set, saved], sp.hrtf == res.set
			and saved.has_all(["itd_scale", "pinna_warp", "concha_db", "picks", "tuned_at"])
			and is_equal_approx(float(saved.itd_scale), float(res.tuning.itd_scale)))
	_check("the card says what was chosen", card.is_showing() and str(card._text.text).contains("head size"))
	_check("no sound left playing", t._player == null and t._renderers.is_empty())
	r = await DevCommands.execute("spatial_tune", {}, false)
	_check("spatial_tune starts it", r["ok"] and t.running)
	r = await DevCommands.execute("spatial_tune", {"action": "cancel"}, false)
	_check("spatial_tune cancel", r["ok"] and not t.running)
	var spec := DevCommands.get_spec("spatial_tune")
	_check("spatial_tune: described for the assistant", spec.get("assistant") == "control"
			and str(spec.get("description", "")).contains("A or B"))
	sp.set_profile_tuning({})
	sp.set_hrtf(hrtf_before)


## The trigger on one of the card's buttons, once the card has laid them out.
func _click(action: String) -> void:
	await _frames(3)
	var card: Node = main.ui.card
	card.click(card.action_point(action))


func _until(cond: Callable, seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await process_frame


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL ", what)
	else:
		print("PASS ", what)
