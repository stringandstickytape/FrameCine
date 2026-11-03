extends Node

## "Tune spatial sound" (docs/features.md, #21, "Tuning"): fits the spatial audio's HRTF to the viewer's ears.
## Short pink-noise bursts (150-250 ms, a little level jitter) come from directions all round, above, below and
## behind; each burst is rendered in the head's frame, so it doesn't move if the head turns while it plays (head
## tracking frozen). The viewer points the controller's laser where they heard it and pulls the trigger. The error
## of each answer is logged: the angle off, azimuth and elevation off, and front / back mix-ups.
##
## The search (Search, pure, tested by tests/test_spatial_tune.gd):
##   1. sets       every HRTF set (bundled and fetched) gets SET_TRIALS bursts, interleaved; the best two go on
##   2. final      FINAL_TRIALS more each; the lower mean angular error over all its bursts wins
##   3. itd, pinna, concha   the winner's ITD scale (head size), pinna warp (notch frequencies) and concha gain, one
##                 at a time: a step down and up, PARAM_TRIALS bursts each; a step is kept if it is MIN_GAIN degrees
##                 better than what stands
## The result is saved for the output profile in use (spatial_audio.gd: its HRTF set, [spatial] tuning_<profile>
## with the errors before and after) and shown on a card. The menu button cancels; nothing changes then.
##
##   start(), cancel(), running, status() -> {running, stage, trial, trials, last}

const SpatialAudio := preload("res://scripts/play/spatial_audio.gd")
const Layouts := preload("res://scripts/play/speaker_layouts.gd")

const BURST_MIN := 0.15
const BURST_MAX := 0.25
const LEVEL_JITTER_DB := 3.0
const BURST_DB := -16.0
## Seconds after an answer before the next burst.
const GAP := 0.8

var main: Node3D
var running := false
var search: Search
var _trial := {}
var _head := Basis() # The head's orientation when the burst played: answers are taken in that frame.
var _answerable := false
var _player: AudioStreamPlayer
var _renderer: Object
var _label: Label3D
var _taken: Array = []
var _was_playing := false
var _rng := RandomNumberGenerator.new()
var _wait := 0.0


## The directions bursts come from (azimuth, elevation in degrees): the horizontal ring, the diagonals behind, above
## and below, and straight up. Each candidate hears the same ones, in another order.
const DIRECTIONS := [[0, 0], [180, 0], [45, 0], [-45, 0], [135, 0], [-135, 0], [90, 0], [-90, 0], [0, 40],
		[180, 40], [60, 40], [-120, 40], [30, -25], [-150, -25], [-60, -25], [120, -25], [0, 80], [165, 15]]


class Search:
	extends RefCounted
	const SET_TRIALS := 5
	const FINAL_TRIALS := 6
	const PARAM_TRIALS := 5
	const MIN_GAIN := 2.0
	const STEPS := {"itd_scale": 0.1, "pinna_warp": 0.07, "concha_db": 3.0}
	const LIMITS := {"itd_scale": [0.7, 1.3], "pinna_warp": [0.85, 1.18], "concha_db": [-9.0, 9.0]}

	var sets: Array[String] = []
	var current_set := ""
	var current_tuning := {}
	var stage := "sets"
	var best_set := ""
	var tuning := {} # The winner's tuning so far.
	var results := {} # key -> [{error, azimuth, elevation, flip}]
	var _queue: Array = []
	var _rng := RandomNumberGenerator.new()
	var _finalists: Array[String] = []
	var _params: Array[String] = ["itd_scale", "pinna_warp", "concha_db"]
	var _param := ""
	var _base_key := ""
	var total := 0
	var done := 0

	func _init(p_sets: Array, p_current: String, p_tuning: Dictionary, p_seed := 0) -> void:
		for s in p_sets:
			sets.append(str(s))
		current_set = p_current if p_current in sets else sets[0]
		current_tuning = _full(p_tuning)
		_rng.seed = p_seed if p_seed != 0 else int(Time.get_ticks_usec())
		total = sets.size() * SET_TRIALS + 2 * FINAL_TRIALS + _params.size() * 2 * PARAM_TRIALS
		for s in sets:
			_add(s, current_tuning if s == current_set else _full({}), SET_TRIALS)
		_queue.shuffle()

	static func _full(t: Dictionary) -> Dictionary:
		return {"itd_scale": float(t.get("itd_scale", 1.0)), "pinna_warp": float(t.get("pinna_warp", 1.0)),
				"concha_db": float(t.get("concha_db", 0.0))}

	static func key(set_id: String, t: Dictionary) -> String:
		return "%s|%.3f|%.3f|%.2f" % [set_id, float(t.itd_scale), float(t.pinna_warp), float(t.concha_db)]

	func _add(set_id: String, t: Dictionary, n: int) -> void:
		var dirs := DIRECTIONS.duplicate()
		# A shuffle of its own per stage, so a candidate's bursts are spread round.
		for i in range(dirs.size() - 1, 0, -1):
			var j := _rng.randi_range(0, i)
			var tmp: Variant = dirs[i]
			dirs[i] = dirs[j]
			dirs[j] = tmp
		for i in n:
			var d: Array = dirs[i % dirs.size()]
			_queue.append({"set": set_id, "tuning": t.duplicate(), "key": key(set_id, t),
					"azimuth": float(d[0]), "elevation": float(d[1])})

	## The next burst: {set, tuning, key, azimuth, elevation}, or {} when the search is over.
	func next() -> Dictionary:
		while _queue.is_empty() and stage != "done":
			_advance()
		return _queue[0] if not _queue.is_empty() else {}

	## The answer to the burst next() gave: a direction in the head's frame (Godot axes).
	func record(trial: Dictionary, answer: Vector3) -> Dictionary:
		var e := score(Layouts.vector(float(trial.azimuth), float(trial.elevation)), answer)
		if not results.has(trial.key):
			results[trial.key] = []
		results[trial.key].append(e)
		if not _queue.is_empty() and _queue[0] == trial:
			_queue.pop_front()
		done += 1
		return e

	func mean(k: String) -> float:
		var r: Array = results.get(k, [])
		if r.is_empty():
			return INF
		var s := 0.0
		for e: Dictionary in r:
			s += float(e.error)
		return s / r.size()

	func flips(k: String) -> float:
		var r: Array = results.get(k, [])
		if r.is_empty():
			return 0.0
		var n := 0
		for e: Dictionary in r:
			n += 1 if e.flip else 0
		return float(n) / r.size()

	func _advance() -> void:
		match stage:
			"sets":
				var ranked := sets.duplicate()
				ranked.sort_custom(func(a: String, b: String) -> bool: return _set_mean(a) < _set_mean(b))
				_finalists.assign(ranked.slice(0, 2))
				stage = "final"
				for s in _finalists:
					_add(s, current_tuning if s == current_set else _full({}), FINAL_TRIALS)
				_queue.shuffle()
			"final":
				var ranked := _finalists.duplicate()
				ranked.sort_custom(func(a: String, b: String) -> bool: return _set_mean(a) < _set_mean(b))
				best_set = ranked[0]
				tuning = current_tuning.duplicate() if best_set == current_set else _full({})
				_base_key = key(best_set, tuning)
				_next_param()
			"itd_scale", "pinna_warp", "concha_db":
				# Keep the better step if it beats what stands by MIN_GAIN.
				var best_key := _base_key
				var best_mean := mean(_base_key)
				for k: String in [_step_key(-1), _step_key(1)]:
					if mean(k) < best_mean - MIN_GAIN:
						best_key = k
						best_mean = mean(k)
				if best_key != _base_key:
					tuning[_param] = _step_value(1 if best_key == _step_key(1) else -1)
					_base_key = best_key
				_next_param()

	func _next_param() -> void:
		if _params.is_empty():
			stage = "done"
			return
		_param = _params.pop_front()
		stage = _param
		for dir in [-1, 1]:
			var t := tuning.duplicate()
			t[_param] = _step_value(dir)
			_add(best_set, t, PARAM_TRIALS)
		_queue.shuffle()

	func _step_value(dir: int) -> float:
		var lim: Array = LIMITS[_param]
		return clampf(float(tuning[_param]) + dir * float(STEPS[_param]), lim[0], lim[1])

	func _step_key(dir: int) -> String:
		var t := tuning.duplicate()
		t[_param] = _step_value(dir)
		return key(best_set, t)

	## Mean error over every burst a set had with its stage-1 tuning.
	func _set_mean(s: String) -> float:
		return mean(key(s, current_tuning if s == current_set else _full({})))

	## {before, after, flips_before, flips_after, set, tuning}: the current set's error at the start, the result's.
	func summary() -> Dictionary:
		var before_key := key(current_set, current_tuning)
		return {"before": mean(before_key), "after": mean(_base_key), "flips_before": flips(before_key),
				"flips_after": flips(_base_key), "set": best_set, "tuning": tuning.duplicate()}

	## One answer against the truth (both unit directions, Godot axes): the angle between them, the azimuth and
	## elevation errors (degrees), and whether it is a front / back mix-up (both off the side by more than 20
	## degrees, on opposite halves, and the answer nearer the truth's mirror image than the truth).
	static func score(truth: Vector3, answer: Vector3) -> Dictionary:
		var t := truth.normalized()
		var a := answer.normalized()
		var err := rad_to_deg(acos(clampf(t.dot(a), -1.0, 1.0)))
		var at := rad_to_deg(atan2(t.x, -t.z))
		var aa := rad_to_deg(atan2(a.x, -a.z))
		var mirror := Vector3(t.x, t.y, -t.z)
		var off_side := absf(t.z) > sin(deg_to_rad(20.0)) and absf(a.z) > sin(deg_to_rad(20.0))
		var flip := off_side and signf(t.z) != signf(a.z) and a.dot(mirror) > a.dot(t)
		return {"error": err, "azimuth": absf(wrapf(aa - at, -180.0, 180.0)),
				"elevation": absf(rad_to_deg(asin(clampf(a.y, -1.0, 1.0))) - rad_to_deg(asin(clampf(t.y, -1.0, 1.0)))),
				"flip": flip}


func _ready() -> void:
	process_priority = 100 # After the UI layer, which sets the lasers each frame.


func status() -> Dictionary:
	return {"running": running, "stage": search.stage if search != null else "",
			"trial": search.done if search != null else 0, "trials": search.total if search != null else 0}


func start() -> void:
	var sp: Node = main.features.speakers
	if running:
		return
	if sp.renderer == null or not sp.available():
		_say("Spatial sound isn't available in this player.", 6.0)
		return
	var sets: Array = []
	for s: Dictionary in sp.hrtf_sets():
		if s.downloaded:
			sets.append(s.id)
	search = Search.new(sets, str(sp.hrtf), sp.profile_settings().tuning)
	_renderer = ClassDB.instantiate("BinauralRenderer")
	_renderer.set_sample_rate(AudioServer.get_mix_rate())
	_renderer.set_eq(sp.profile_settings().eq)
	_renderer.set_gain(SpatialAudio.GAIN)
	_player = AudioStreamPlayer.new()
	_player.name = "TuneBurst"
	add_child(_player)
	_was_playing = main.player.is_playing()
	if _was_playing:
		main.player.pause()
	var ui: Node = main.get("ui")
	if ui != null and ui.has_method("hide_panel"):
		ui.hide_panel()
	_make_label()
	_take_triggers()
	running = true
	_wait = 1.0
	_instruct("Tune spatial sound: a short hiss plays from somewhere around you. Point the laser where you heard it and "
			+ "pull the trigger. %d sounds, about %d minutes. Menu cancels." % [search.total, ceili(search.total * 3.0 / 60.0)])


func cancel() -> void:
	if not running:
		return
	_end()
	_say("Spatial sound tuning cancelled; nothing changed.", 6.0)


func _process(delta: float) -> void:
	if not running:
		return
	for hand in [main.get("left_hand"), main.get("right_hand")]:
		if hand != null and hand.has_method("set_laser"):
			hand.set_laser(true, 4.0)
	if _answerable or _player.playing:
		return
	_wait -= delta
	if _wait > 0.0:
		return
	_trial = search.next()
	if _trial.is_empty():
		_finish()
		return
	_play(_trial)


## Renders the burst in the head's frame (the listener at the origin, looking down -Z) and plays it.
func _play(trial: Dictionary) -> void:
	var file: String = main.features.speakers.hrtf_file(str(trial.set))
	if _renderer.get_hrtf_info().get("source", "") != file:
		_renderer.load_hrtf(file)
	var t: Dictionary = trial.tuning
	_renderer.set_tuning(float(t.itd_scale), float(t.pinna_warp), float(t.concha_db))
	_renderer.set_sources([{"input": 0, "position": Layouts.vector(float(trial.azimuth), float(trial.elevation)),
			"at_infinity": true}])
	_renderer.set_listener(Transform3D())
	_renderer.reset()
	var rate := AudioServer.get_mix_rate()
	var n := int(rate * _rng.randf_range(BURST_MIN, BURST_MAX))
	var noise := pink_noise(n, db_to_linear(BURST_DB + _rng.randf_range(-LEVEL_JITTER_DB, LEVEL_JITTER_DB)), _rng)
	noise.resize(n + int(rate * 0.01)) # Silence after it for the filters' tails.
	var out: PackedFloat32Array = _renderer.render(noise, 1)
	_player.stream = to_wav(out, int(rate))
	var cam: Node3D = main.camera
	_head = cam.global_transform.basis.orthonormalized() if cam != null else Basis()
	_player.play()
	_answerable = true
	_instruct("Where did you hear it? Point and pull the trigger (%d of %d)." % [search.done + 1, search.total])


func _on_trigger(hand: XRController3D, pressed: bool) -> void:
	if not pressed or not running or not _answerable:
		return
	var aim := -hand.global_transform.basis.z
	var answer := _head.inverse() * aim # In the head's frame at the burst.
	var e := search.record(_trial, answer)
	_answerable = false
	_wait = GAP
	if hand.has_method("pulse"):
		hand.call("pulse")
	print("Spatial tune: %s at %+.0f / %+.0f: %.0f degrees off%s" % [_trial.set, _trial.azimuth, _trial.elevation,
			e.error, " (front / back)" if e.flip else ""])


func _finish() -> void:
	var r := search.summary()
	var sp: Node = main.features.speakers
	sp.set_hrtf(str(r.set))
	var t: Dictionary = r.tuning
	sp.set_profile_tuning({"itd_scale": t.itd_scale, "pinna_warp": t.pinna_warp, "concha_db": t.concha_db,
			"before_deg": snappedf(r.before, 0.1), "after_deg": snappedf(r.after, 0.1),
			"flips_before": snappedf(r.flips_before, 0.01), "flips_after": snappedf(r.flips_after, 0.01),
			"trials": search.done, "tuned_at": Time.get_datetime_string_from_system()})
	var name := str(r.set)
	for s: Dictionary in sp.hrtf_sets():
		if s.id == r.set:
			name = s.name
	_end()
	_say(("Spatial sound tuned for the %s: %s. Average error %.0f degrees before, %.0f after; front / back mix-ups "
			+ "%d %% before, %d %% after.") % ["headphones" if sp.profile() == "headphones" else "headset's speakers",
			name, r.before, r.after, roundi(r.flips_before * 100.0), roundi(r.flips_after * 100.0)], 15.0)


func _end() -> void:
	running = false
	_answerable = false
	if is_instance_valid(_player):
		_player.queue_free()
	if is_instance_valid(_label):
		_label.queue_free()
	_give_back_triggers()
	for hand in [main.get("left_hand"), main.get("right_hand")]:
		if hand != null and hand.has_method("set_laser"):
			hand.set_laser(false)
	if _was_playing:
		main.player.play()


## Pink noise (Paul Kellet's filter on white noise), peak about `level`.
static func pink_noise(n: int, level: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	var b := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var ramp := maxi(1, mini(n / 4, 480)) # 10 ms raised-cosine ends.
	for i in n:
		var w := rng.randf_range(-1.0, 1.0)
		b[0] = 0.99886 * b[0] + w * 0.0555179
		b[1] = 0.99332 * b[1] + w * 0.0750759
		b[2] = 0.96900 * b[2] + w * 0.1538520
		b[3] = 0.86650 * b[3] + w * 0.3104856
		b[4] = 0.55000 * b[4] + w * 0.5329522
		b[5] = -0.7616 * b[5] - w * 0.0168980
		var p: float = b[0] + b[1] + b[2] + b[3] + b[4] + b[5] + b[6] + w * 0.5362
		b[6] = w * 0.115926
		var g := 1.0
		if i < ramp:
			g = 0.5 - 0.5 * cos(PI * i / ramp)
		elif i >= n - ramp:
			g = 0.5 - 0.5 * cos(PI * (n - 1 - i) / ramp)
		out[i] = p * 0.11 * level * g
	return out


## Interleaved stereo floats to a 16-bit AudioStreamWAV.
static func to_wav(stereo: PackedFloat32Array, rate: int) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(stereo.size() * 2)
	for i in stereo.size():
		data.encode_s16(i * 2, clampi(roundi(stereo[i] * 32767.0), -32767, 32767))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.stereo = true
	w.mix_rate = rate
	w.data = data
	return w


func _make_label() -> void:
	_label = Label3D.new()
	_label.font_size = 40
	_label.pixel_size = 0.0016
	_label.width = 1200.0
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.no_depth_test = true
	_label.render_priority = 10
	_label.outline_size = 8
	add_child(_label)
	var cam: Node3D = main.camera
	var head: Transform3D = cam.global_transform if cam != null else Transform3D(Basis(), Vector3(0, 1.2, 0))
	var fwd := -head.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	_label.global_transform = Transform3D(Basis.looking_at(-fwd, Vector3.UP), head.origin + fwd * 1.5
			+ Vector3(0, -0.35, 0))


func _instruct(text: String) -> void:
	if is_instance_valid(_label):
		_label.text = text


func _say(text: String, seconds: float) -> void:
	var ui: Node = main.get("ui")
	if ui != null and ui.get("card") != null:
		ui.card.show_card({"text": text, "title": "Spatial sound", "seconds": seconds, "id": "spatial_tune"})


## The trigger is the tuning's while it runs: main's handler off, ours on; the menu button cancels.
func _take_triggers() -> void:
	for hand in [main.get("left_hand"), main.get("right_hand")]:
		if hand == null:
			continue
		var h := hand as XRController3D
		if h.has_signal("trigger_changed"):
			if main.has_method("_on_trigger") and h.trigger_changed.is_connected(main._on_trigger):
				h.trigger_changed.disconnect(main._on_trigger)
				_taken.append(h)
			if not h.trigger_changed.is_connected(_on_trigger):
				h.trigger_changed.connect(_on_trigger)
		if h.has_signal("menu_pressed") and not h.menu_pressed.is_connected(_on_menu):
			h.menu_pressed.connect(_on_menu)


func _give_back_triggers() -> void:
	for hand in [main.get("left_hand"), main.get("right_hand")] if main != null else []:
		if hand == null:
			continue
		var h := hand as XRController3D
		if h.has_signal("trigger_changed") and h.trigger_changed.is_connected(_on_trigger):
			h.trigger_changed.disconnect(_on_trigger)
		if h.has_signal("menu_pressed") and h.menu_pressed.is_connected(_on_menu):
			h.menu_pressed.disconnect(_on_menu)
	for h: XRController3D in _taken:
		if is_instance_valid(h) and not h.trigger_changed.is_connected(main._on_trigger):
			h.trigger_changed.connect(main._on_trigger)
	_taken.clear()


func _on_menu(_hand: XRController3D) -> void:
	cancel.call_deferred()
