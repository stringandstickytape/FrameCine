extends SceneTree

## Tests for the engine's BinauralRenderer (fork branch frame/binaural; docs/features.md #21) with the bundled HRTF
## packs: the HRTF lookup and its interpolation, interaural time and level differences of a rendered noise from the
## front, back, left, right and above, a head turn keeping a source where it is in the world, no clicks while the head
## turns, ambisonic decoding and rotation, LFE and head-locked channels, the room, the tuning, no added latency, and
## the CPU time for 2, 6, 8 and 12 channels, first- and third-order ambisonics (printed; the budget checked).
## Without BinauralRenderer in the engine it says SKIP and passes.
## Run: godot --headless --xr-mode off --path app --script res://tests/test_binaural.gd

const PACK := "res://audio/hrtf/sadie2_d1.fhrtf"
const RATE := 48000.0

var _failures := 0
var _checks := 0
var _noise := PackedFloat32Array()


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ClassDB.class_exists("BinauralRenderer"):
		print("SKIP (no BinauralRenderer in this engine)")
		print("test_binaural: 0 checks, all passed")
		quit(0)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	_noise.resize(int(RATE * 0.5))
	for i in _noise.size():
		_noise[i] = rng.randf_range(-0.5, 0.5)
	_lookup_checks()
	_direction_checks()
	_rotation_checks()
	_ambisonic_checks()
	_other_checks()
	_cpu_checks()
	print("test_binaural: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _renderer() -> Object:
	var r: Object = ClassDB.instantiate("BinauralRenderer")
	r.load_hrtf(PACK)
	return r


func _lookup_checks() -> void:
	var r: Object = ClassDB.instantiate("BinauralRenderer")
	_check("not ready before an HRTF", not r.is_ready())
	_check("a missing pack is an error", r.load_hrtf("res://audio/hrtf/none.fhrtf") != OK and r.get_last_error() != "")
	_check("the bundled pack loads", r.load_hrtf(PACK) == OK and r.is_ready())
	var info: Dictionary = r.get_hrtf_info()
	_check("its name and credit (%s)" % info.get("name"), str(info.get("name")).contains("Dummy head A")
			and str(info.get("credit")).contains("Apache"))
	for path: String in ["sadie2_d2", "sadie2_h3", "sadie2_h4", "sadie2_h5", "sadie2_h6"]:
		var other: Object = ClassDB.instantiate("BinauralRenderer")
		_check("pack %s loads" % path, other.load_hrtf("res://audio/hrtf/%s.fhrtf" % path) == OK)
	var right: Dictionary = r.lookup_hrir(90.0, 0.0)
	var left: Dictionary = r.lookup_hrir(-90.0, 0.0)
	var front: Dictionary = r.lookup_hrir(0.0, 0.0)
	_check("right: the right ear first (delays %.1f / %.1f)" % [right.delay_left, right.delay_right],
			right.delay_left - right.delay_right > 20.0)
	_check("right: louder on the right (%.1f dB)" % _db(right.right, right.left), _db(right.right, right.left) > 8.0)
	_check("left: the mirror", left.delay_right - left.delay_left > 20.0 and _db(left.left, left.right) > 8.0)
	_check("front: no time difference (%.2f)" % (front.delay_left - front.delay_right),
			absf(front.delay_left - front.delay_right) < 2.0)
	# Between grid points (7.5 degrees apart) the lookup is the blend of its neighbours.
	var a: Dictionary = r.lookup_hrir(30.0, 0.0)
	var b: Dictionary = r.lookup_hrir(37.5, 0.0)
	var mid: Dictionary = r.lookup_hrir(33.75, 0.0)
	var worst := 0.0
	for i in 128:
		worst = maxf(worst, absf(mid.left[i] - 0.5 * (a.left[i] + b.left[i])))
	_check("interpolation: halfway is the average (error %.7f)" % worst, worst < 1e-5
			and absf(mid.delay_left - 0.5 * (a.delay_left + b.delay_left)) < 1e-3)
	var near: Dictionary = r.lookup_hrir(30.5, 0.0)
	_check("interpolation: continuous (half a degree moves little)", _distance(near.left, a.left) < 0.2)
	_check("azimuth wraps: 360 is 0", _distance(r.lookup_hrir(360.0, 0.0).left, front.left) < 1e-5)


func _direction_checks() -> void:
	var cues := {}
	for name: String in ["front", "back", "left", "right", "up"]:
		var pos: Vector3 = {"front": Vector3(0, 0, -2), "back": Vector3(0, 0, 2), "left": Vector3(-2, 0, 0),
				"right": Vector3(2, 0, 0), "up": Vector3(0, 2, 0)}[name]
		cues[name] = _cues(_render_point(pos, Transform3D()))
		print("  %-5s ITD %+5.1f samples, ILD %+5.1f dB, brightness %.2f dB" % [name, cues[name].itd, cues[name].ild,
				cues[name].bright])
	_check("left: the left ear leads by 0.4-1 ms", cues.left.itd > 18.0 and cues.left.itd < 50.0)
	_check("left: louder in the left ear", cues.left.ild > 6.0)
	_check("right: the mirror of left", cues.right.itd < -18.0 and cues.right.ild < -6.0)
	_check("front: centred", absf(cues.front.itd) <= 2.0 and absf(cues.front.ild) < 3.0)
	_check("back: centred", absf(cues.back.itd) <= 2.0 and absf(cues.back.ild) < 3.0)
	_check("up: centred", absf(cues.up.itd) <= 2.0 and absf(cues.up.ild) < 3.0)
	_check("front and back differ in timbre (%.1f dB)" % absf(cues.front.bright - cues.back.bright),
			absf(cues.front.bright - cues.back.bright) > 1.0)
	_check("front and up differ in timbre (%.1f dB)" % absf(cues.front.bright - cues.up.bright),
			absf(cues.front.bright - cues.up.bright) > 1.0)


func _rotation_checks() -> void:
	# The head turned 90 degrees to the left: a source in front is now on the right, as a source on the right is
	# with the head straight.
	var turned := Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), Vector3.ZERO)
	var a := _cues(_render_point(Vector3(0, 0, -2), turned))
	var b := _cues(_render_point(Vector3(2, 0, 0), Transform3D()))
	_check("head turned left: the front source sounds from the right (ITD %.1f / %.1f, ILD %.1f / %.1f)" % [a.itd,
			b.itd, a.ild, b.ild], absf(a.itd - b.itd) <= 1.0 and absf(a.ild - b.ild) < 1.0)
	# Moving the head (not turning it) to the source's side changes nothing for a source at a distance... but moves
	# a near one: a source 2 m ahead with the head 2 m to the left of it is at 45 degrees to the right.
	var moved := _cues(_render_point(Vector3(0, 0, -2), Transform3D(Basis(), Vector3(-2, 0, 0))))
	_check("the head moved: the source is where it is in the room", moved.itd < -8.0)
	# A tone while the head turns 180 degrees in 2 s: no clicks (no step much bigger than the tone's own).
	var r := _renderer()
	r.set_sources([{"input": 0, "position": Vector3(0, 0, -2)}])
	var tone := PackedFloat32Array()
	tone.resize(512)
	var out := PackedFloat32Array()
	var steps := 190
	for s in steps:
		for i in 512:
			tone[i] = 0.3 * sin(TAU * 500.0 * float(s * 512 + i) / RATE)
		r.set_listener(Transform3D(Basis(Vector3.UP, PI * float(s) / steps), Vector3.ZERO))
		out.append_array(r.render(tone, 1))
	# The second difference of each ear's signal: a click is a jump in it.
	var worst := 0.0
	var at := 0
	var typical := 0.0
	var skip := 2048 # The filter filling up at the start.
	for e in 2:
		for i in range(skip, out.size() / 2 - 1):
			var d2 := absf(out[(i + 1) * 2 + e] - 2.0 * out[i * 2 + e] + out[(i - 1) * 2 + e])
			if d2 > worst:
				worst = d2
				at = i
			typical += d2
	typical /= 2.0 * (out.size() / 2 - 1 - skip)
	_check("head turning: no clicks (largest step %.1f x the typical, at %d)" % [worst / typical, at],
			worst < typical * 4.0)


func _ambisonic_checks() -> void:
	_check("virtual speakers: 8, 12, 26 for orders 1-3", ClassDB.class_call_static("BinauralRenderer",
			"virtual_speakers", 1).size() == 8 and ClassDB.class_call_static("BinauralRenderer", "virtual_speakers",
			2).size() == 12 and ClassDB.class_call_static("BinauralRenderer", "virtual_speakers", 3).size() == 26)
	var enc: PackedFloat32Array = ClassDB.class_call_static("BinauralRenderer", "ambisonic_encode", Vector3.LEFT, 1)
	_check("AmbiX encoding: W 1, Y 1 for the left", enc.size() == 4 and is_equal_approx(enc[0], 1.0)
			and is_equal_approx(enc[1], 1.0) and absf(enc[2]) < 1e-6 and absf(enc[3]) < 1e-6)
	for order in [1, 3]:
		var left := _cues(_render_ambisonic(Vector3.LEFT, order, Basis(), Transform3D()))
		var front := _cues(_render_ambisonic(Vector3.FORWARD, order, Basis(), Transform3D()))
		_check("order %d: a sound field from the left is on the left (ITD %.1f, ILD %.1f)" % [order, left.itd,
				left.ild], left.itd > 10.0 and left.ild > 3.0)
		_check("order %d: from the front, centred (ITD %.1f)" % [order, front.itd], absf(front.itd) <= 2.0
				and absf(front.ild) < 2.0)
		# The head turned to face the left: the field stays put, so the left sound is now in front.
		var faced := _cues(_render_ambisonic(Vector3.LEFT, order, Basis(), Transform3D(Basis(Vector3.UP,
				deg_to_rad(90.0)), Vector3.ZERO)))
		_check("order %d: head turned to the sound: in front (ITD %.1f)" % [order, faced.itd], absf(faced.itd) <= 2.0)
		# The picture's front turned 90 degrees to the right: the field turns with it.
		var spun := _cues(_render_ambisonic(Vector3.FORWARD, order, Basis(Vector3.UP, deg_to_rad(-90.0)),
				Transform3D()))
		_check("order %d: the frame turned right: the front sound on the right (ITD %.1f)" % [order, spun.itd],
				spun.itd < -10.0)


func _other_checks() -> void:
	var r := _renderer()
	r.set_sources([{"input": 0, "kind": "lfe", "gain": 0.5}])
	var out: PackedFloat32Array = r.render(_noise.slice(0, 4800), 1)
	var same := true
	for i in 4800:
		same = same and is_equal_approx(out[i * 2], out[i * 2 + 1]) and is_equal_approx(out[i * 2], 0.5 * _noise[i])
	_check("LFE: the same to both ears, no direction", same)
	r = _renderer()
	r.set_sources([{"input": 0, "kind": "head_left"}, {"input": 1, "kind": "head_right"}])
	var stereo := PackedFloat32Array()
	for i in 1000:
		stereo.append_array([_noise[i], 0.0])
	out = r.render(stereo, 2)
	_check("head-locked left: straight to the left ear", is_equal_approx(out[200], _noise[100])
			and is_zero_approx(out[201]))
	# No latency: an impulse comes out within PRE + 2 samples and the shortest delay.
	r = _renderer()
	r.set_sources([{"input": 0, "position": Vector3(0, 0, -2)}])
	var impulse := PackedFloat32Array()
	impulse.resize(512)
	impulse[0] = 1.0
	out = r.render(impulse, 1)
	var first := -1
	var peak := 0.0
	for i in 512:
		peak = maxf(peak, absf(out[i * 2]))
	for i in 512:
		if absf(out[i * 2]) > 0.1 * peak:
			first = i
			break
	_check("no latency: the front impulse arrives after %d samples (< 32)" % first, first >= 0 and first < 32)
	var stats: Dictionary = r.get_stats()
	_check("latency reported as 0 frames", int(stats.latency_frames) == 0)
	# The room: a tail after the direct sound.
	var dry := _tail(0.0)
	var wet := _tail(1.0)
	_check("room: reflections and reverb after 20 ms (%.1f dB more)" % (wet - dry), wet - dry > 20.0)
	# Tuning: the ITD scale.
	var base := _cues(_render_point(Vector3(-2, 0, 0), Transform3D()))
	r = _renderer()
	r.set_tuning(1.3, 1.0, 0.0)
	r.set_sources([{"input": 0, "position": Vector3(-2, 0, 0)}])
	var scaled := _cues_of(r.render(_noise, 1))
	_check("tuning: ITD x 1.3 (%.1f -> %.1f)" % [base.itd, scaled.itd], scaled.itd / base.itd > 1.2
			and scaled.itd / base.itd < 1.4)
	r.set_tuning(1.0, 1.15, 0.0)
	var warped: Dictionary = r.lookup_hrir(-90.0, 0.0)
	var plain: Dictionary = _renderer().lookup_hrir(-90.0, 0.0)
	_check("tuning: the pinna warp changes the responses, not their energy", _distance(warped.left, plain.left) > 0.05
			and absf(_db(warped.left, plain.left)) < 0.5)
	_check("tuning: read back", is_equal_approx(r.get_tuning().pinna_warp, 1.15))


func _tail(wet: float) -> float:
	var r := _renderer()
	r.set_sources([{"input": 0, "position": Vector3(0, 0, -2.5)}])
	r.set_room({"min": Vector3(-4, -1.2, -5), "max": Vector3(4, 2, 3), "reflect": 0.6, "rt60": 0.6, "wet": wet})
	var impulse := PackedFloat32Array()
	impulse.resize(int(RATE * 0.3))
	impulse[0] = 1.0
	var out: PackedFloat32Array = r.render(impulse, 1)
	var e := 1e-12
	for i in range(int(RATE * 0.02), out.size() / 2):
		e += out[i * 2] * out[i * 2] + out[i * 2 + 1] * out[i * 2 + 1]
	return 10.0 * log(e) / log(10.0)


func _cpu_checks() -> void:
	# Noise in every channel, the head turning all the time (the costlier path: two filters crossfaded).
	var layouts := {2: 2, 6: 6, 8: 8, 12: 12}
	for n: int in layouts:
		var r := _renderer()
		var sources := []
		for c in n:
			var a := TAU * c / n
			sources.append({"input": c, "position": Vector3(sin(a) * 2.5, 0.3 * (c % 3), -cos(a) * 2.5)})
		r.set_sources(sources)
		r.set_room({"min": Vector3(-4, -1.2, -5), "max": Vector3(4, 2, 3), "reflect": 0.5, "rt60": 0.5, "wet": 1.0})
		_report_cpu(r, "%d channels" % n, n, 0)
	for order in [1, 3]:
		var r := _renderer()
		r.set_ambisonics(order, 0, Basis(), 1.0)
		_report_cpu(r, "ambisonics order %d" % order, (order + 1) * (order + 1), order)


func _report_cpu(r: Object, what: String, channels: int, _order: int) -> void:
	var seconds := 4.0
	var block := 512
	var input := PackedFloat32Array()
	input.resize(block * channels)
	for i in input.size():
		input[i] = _noise[i % _noise.size()]
	var blocks := int(seconds * RATE / block)
	r.reset_stats()
	for b in blocks:
		r.set_listener(Transform3D(Basis(Vector3.UP, 0.02 * b), Vector3.ZERO))
		r.render(input, channels)
	var s: Dictionary = r.get_stats()
	var per_block := float(s.usec) / float(s.calls)
	print("  CPU %-20s %6.1f us per 512-frame block, %.2f %% of one core (worst block %d us)" % [what, per_block,
			100.0 * float(s.load), s.max_usec])
	_check("CPU %s under 15 %% of a desktop core" % what, float(s.load) < 0.15)


func _render_point(pos: Vector3, listener: Transform3D) -> PackedFloat32Array:
	var r := _renderer()
	r.set_sources([{"input": 0, "position": pos}])
	r.set_listener(listener)
	return r.render(_noise, 1)


func _render_ambisonic(dir: Vector3, order: int, frame: Basis, listener: Transform3D) -> PackedFloat32Array:
	var r := _renderer()
	r.set_ambisonics(order, 0, frame, 1.0)
	r.set_listener(listener)
	var enc: PackedFloat32Array = ClassDB.class_call_static("BinauralRenderer", "ambisonic_encode", dir, order)
	var input := PackedFloat32Array()
	input.resize(_noise.size() * enc.size())
	for i in _noise.size():
		for k in enc.size():
			input[i * enc.size() + k] = _noise[i] * enc[k]
	return r.render(input, enc.size())


## {itd: samples, positive when the left ear leads; ild: dB, positive when the left is louder; bright: dB of the
## high band (first difference) against the whole, both ears}.
func _cues(out: PackedFloat32Array) -> Dictionary:
	return _cues_of(out)


func _cues_of(out: PackedFloat32Array) -> Dictionary:
	var n := out.size() / 2
	var skip := 1024
	var l := PackedFloat32Array()
	var r := PackedFloat32Array()
	l.resize(n - skip)
	r.resize(n - skip)
	for i in range(skip, n):
		l[i - skip] = out[i * 2]
		r[i - skip] = out[i * 2 + 1]
	# Cross-correlation over +-60 samples on 8192 samples.
	var best := -INF
	var lag := 0
	var m := mini(8192, l.size() - 120)
	for k in range(-60, 61):
		var s := 0.0
		for i in range(60, 60 + m):
			s += l[i] * r[i + k]
		if s > best:
			best = s
			lag = k
	var el := 1e-12
	var er := 1e-12
	var hi := 1e-12
	for i in range(1, l.size()):
		el += l[i] * l[i]
		er += r[i] * r[i]
		var dl := l[i] - l[i - 1]
		var dr := r[i] - r[i - 1]
		hi += dl * dl + dr * dr
	return {"itd": float(lag), "ild": 10.0 * log(el / er) / log(10.0), "bright": 10.0 * log(hi / (el + er)) / log(10.0)}


func _db(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var ea := 1e-12
	var eb := 1e-12
	for i in a.size():
		ea += a[i] * a[i]
		eb += b[i] * b[i]
	return 10.0 * log(ea / eb) / log(10.0)


func _distance(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var d := 0.0
	var e := 1e-12
	for i in a.size():
		d += (a[i] - b[i]) * (a[i] - b[i])
		e += b[i] * b[i]
	return sqrt(d / e)


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL ", what)
	else:
		print("PASS ", what)
