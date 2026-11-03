extends SceneTree

## Tests for "Tune spatial sound" (scripts/play/spatial_tune.gd, docs/features.md #21, "Tuning"): the scoring of an
## answer (angle, azimuth, elevation, front / back mix-ups) and the search, against simulated listeners whose errors
## depend on the HRTF set and the tuning; the burst's pink noise and its WAV; and, in the real main scene, the step
## run with simulated trigger pulls, its result saved for the output profile. Settings are read-only.
## Run: godot --headless --xr-mode off --path app --script res://tests/test_spatial_tune.gd

const SpatialTune := preload("res://scripts/play/spatial_tune.gd")
const Layouts := preload("res://scripts/play/speaker_layouts.gd")
const SETS := ["sadie2_d1", "sadie2_d2", "sadie2_h3", "sadie2_h4", "sadie2_h5", "sadie2_h6"]

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
	await _frames(5)
	_score_checks()
	_search_checks()
	_noise_checks()
	await _step_checks()
	print("test_spatial_tune: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _score_checks() -> void:
	var S = SpatialTune.Search
	var front := Layouts.vector(0, 0)
	var e: Dictionary = S.score(front, front)
	_check("a right answer: no error", e.error < 0.01 and not e.flip)
	e = S.score(front, Layouts.vector(30, 0))
	_check("30 degrees off to the side: 30 degrees, azimuth 30", absf(e.error - 30.0) < 0.01
			and absf(e.azimuth - 30.0) < 0.01 and e.elevation < 0.01 and not e.flip)
	e = S.score(Layouts.vector(30, 0), Layouts.vector(150, 0))
	_check("30 in front heard at 150 behind: a front / back mix-up", e.flip and absf(e.error - 120.0) < 0.01)
	e = S.score(Layouts.vector(90, 0), Layouts.vector(100, 0))
	_check("at the side: never a mix-up", not e.flip)
	e = S.score(Layouts.vector(0, 40), Layouts.vector(0, 10))
	_check("elevation error 30", absf(e.elevation - 30.0) < 0.01 and absf(e.error - 30.0) < 0.01)
	e = S.score(Layouts.vector(170, 0), Layouts.vector(-170, 0))
	_check("azimuth error wraps round the back (20)", absf(e.azimuth - 20.0) < 0.01)


## A listener for whom one set fits best (fewest mix-ups, least scatter) and whose ears like a given tuning.
func _listener(best: String, itd: float, warp: float, rng: RandomNumberGenerator) -> Callable:
	return func(trial: Dictionary) -> Vector3:
		var t: Dictionary = trial.tuning
		var scatter := 12.0 if trial.set == best else 25.0 + 4.0 * SETS.find(trial.set)
		scatter += 120.0 * absf(float(t.itd_scale) - itd) + 150.0 * absf(float(t.pinna_warp) - warp)
		var flip_p := 0.05 if trial.set == best else 0.3
		var az := float(trial.azimuth) + rng.randfn(0.0, scatter)
		var el := clampf(float(trial.elevation) + rng.randfn(0.0, scatter * 0.6), -89.0, 89.0)
		if rng.randf() < flip_p and absf(absf(az) - 90.0) > 25.0:
			az = 180.0 - az
		return Layouts.vector(az, el)


func _search_checks() -> void:
	var wins := 0
	var improved := 0
	var itd_right := 0
	var runs := 10
	for run in runs:
		var rng := RandomNumberGenerator.new()
		rng.seed = 1000 + run
		var best: String = SETS[3]
		var answer := _listener(best, 1.1, 1.07, rng)
		var s = SpatialTune.Search.new(SETS, "sadie2_d1", {}, 77 + run)
		var n := 0
		while true:
			var t: Dictionary = s.next()
			if t.is_empty():
				break
			s.record(t, answer.call(t))
			n += 1
		var r: Dictionary = s.summary()
		if run == 0:
			_check("the search runs %d bursts, as it said (%d)" % [n, s.total], n == s.total and s.stage == "done")
			print("  run 0: %s, tuning %s, %.0f -> %.0f degrees, mix-ups %.0f %% -> %.0f %%" % [r.set, r.tuning,
					r.before, r.after, r.flips_before * 100.0, r.flips_after * 100.0])
		wins += 1 if r.set == best else 0
		improved += 1 if r.after < r.before else 0
		itd_right += 1 if is_equal_approx(float(r.tuning.itd_scale), 1.1) else 0
	_check("the best-fitting set wins (%d of %d runs)" % [wins, runs], wins >= 8)
	_check("the error after is lower than before (%d of %d)" % [improved, runs], improved >= 9)
	_check("the ITD scale moves to the listener's (%d of %d)" % [itd_right, runs], itd_right >= 6)
	# A listener who hears everything right: nothing changes from where it starts.
	var still = SpatialTune.Search.new(SETS, "sadie2_d1", {}, 5)
	while true:
		var t: Dictionary = still.next()
		if t.is_empty():
			break
		still.record(t, Layouts.vector(t.azimuth, t.elevation))
	_check("a perfect listener: no tuning step taken (all errors 0)", still.summary().tuning ==
			{"itd_scale": 1.0, "pinna_warp": 1.0, "concha_db": 0.0} and is_zero_approx(still.summary().after))
	var one = SpatialTune.Search.new(["sadie2_d1"], "sadie2_d1", {"itd_scale": 0.9}, 3)
	var first: Dictionary = one.next()
	_check("one set: the current tuning is where it starts", is_equal_approx(float(first.tuning.itd_scale), 0.9))


func _noise_checks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var n := SpatialTune.pink_noise(9600, 0.5, rng)
	var peak := 0.0
	for v in n:
		peak = maxf(peak, absf(v))
	_check("pink noise: within level, faded in and out", peak < 0.5 and peak > 0.05 and absf(n[0]) < 1e-4
			and absf(n[n.size() - 1]) < 1e-4)
	# Pink: more energy low than high (first difference against the signal).
	var e := 0.0
	var d := 0.0
	for i in range(1, n.size()):
		e += n[i] * n[i]
		d += (n[i] - n[i - 1]) * (n[i] - n[i - 1])
	_check("pink noise: falls with frequency (high band %.2f of white's 2.0)" % (d / e), d / e < 1.0)
	var w := SpatialTune.to_wav(PackedFloat32Array([0.5, -0.5, 1.5, 0.0]), 48000)
	_check("the burst's WAV: 16-bit stereo, clipped", w.stereo and w.data.size() == 8 and w.data.decode_s16(4) == 32767)


## The step itself with simulated trigger pulls (no controllers headless: the answers go to its handler directly).
func _step_checks() -> void:
	var t: Node = main.features.spatial_tune
	var sp: Node = main.features.speakers
	if not sp.available():
		print("SKIP the step (no BinauralRenderer in this engine)")
		return
	var hand := XRController3D.new()
	root.add_child(hand)
	t.start()
	_check("started: the film paused, a label up", t.running)
	var answered := 0
	var end := Time.get_ticks_msec() + 120000
	while t.running and Time.get_ticks_msec() < end:
		await process_frame
		if t._answerable:
			# Point exactly where the burst came from (in the head's frame; the camera doesn't move here).
			var dir := Layouts.vector(float(t._trial.azimuth), float(t._trial.elevation))
			hand.global_transform = Transform3D(Basis.looking_at(t._head * dir, Vector3.UP), Vector3.ZERO)
			t._wait = 0.0
			t._on_trigger(hand, true)
			t._wait = 0.0
			answered += 1
	_check("the step ran every burst (%d)" % answered, not t.running and answered == t.search.total)
	var saved: Dictionary = sp.profile_settings().tuning
	_check("the result saved for the profile, with before and after", saved.has_all(["itd_scale", "pinna_warp",
			"concha_db", "before_deg", "after_deg", "flips_before", "tuned_at"]) and float(saved.after_deg) < 1.0)
	sp.set_profile_tuning({})
	hand.queue_free()


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
