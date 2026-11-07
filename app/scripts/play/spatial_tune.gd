extends Node

## "Tune spatial sound" (docs/features.md, #21, "Tuning"): fits the spatial audio to the viewer's ears by ear, one
## "which sounds better?" pick at a time. A sound (pink-noise pulses, four a second) circles the head on the horizon
## (front, right, behind, left, front), then rises over the top to behind. It stays put in the room (head tracking on),
## so the viewer may turn toward it. Each pick plays it through two candidates, A then B; the viewer picks A, B or
## "Can't tell" on a card with the laser and the trigger, or hears them again. There is no right answer: whichever
## sounds more real, more outside the head, more in the room.
##
## The order (Knockout, pure, tested by tests/test_spatial_tune.gd): the output profile's HRTF set and tuning start
## as the champion, so tuning never leaves something the viewer likes less; every other set (bundled and fetched)
## challenges it once and the winner stays; then the champion's head size (ITD scale) and, when it fits in about two
## minutes, its ear shape (pinna warp), two picks each. The result is saved for the output profile in use
## (spatial_audio.gd: its HRTF set, [spatial] tuning_<profile>) and shown on a card. The menu button cancels; nothing
## changes then.
##
## The sound streams: an AudioStreamGenerator kept LEAD_SECONDS ahead, fed each frame in blocks of BLOCK frames, each
## rendered by the candidate's own BinauralRenderer (one per HRTF set and ear shape, loaded on a worker thread while
## the pick before plays) with the listener set to the head's pose just before. The path turns the listener, not the
## source, so it moves as smoothly as a head turn (listener_pose()).
##
##   start(), cancel(), choose("a" | "b" | "same" | "again"), running,
##   status() -> {running, stage, pick, picks, playing, heard_both, ready, skips, lead_ms}

const SpatialAudio := preload("res://scripts/play/spatial_audio.gd")

## One play: the horizon circle takes CIRCLE_SHARE of it, the pass overhead the rest (front, up, over, to 30 degrees
## up behind).
const PLAY_SECONDS := 6.0
const CIRCLE_SHARE := 0.73
const OVERHEAD_DEG := 150.0
## The pulses: one every PULSE seconds, PULSE_ON long with RAMP fades, each a little louder or softer.
const PULSE := 0.25
const PULSE_ON := 0.17
const RAMP := 0.012
const LEVEL_DB := -16.0
const JITTER_DB := 2.0
## Between A and B (A's room tail rings out in it), and after B.
const GAP := 0.6
const TAIL := 0.4
const BLOCK := 512
## How far ahead of the ear the stream is kept: the head tracking's delay on top of the sound device's own.
const LEAD_SECONDS := 0.05
const BUFFER_SECONDS := 0.25
## A pick takes about this long (A, B, deciding): for the time the card gives.
const ROUND_SECONDS := 15.0
const CARD_ID := "spatial_tune"
const STAGE_NAMES := {"sets": "Head measurements", "itd_scale": "Head size", "pinna_warp": "Ear shape"}

var main: Node3D
var running := false
var search: Knockout
## Seconds per play (tests shorten it).
var play_seconds := PLAY_SECONDS
var _rate := 48000.0
var _renderers := {} # set id -> {renderer, task (-1 once loaded), ok}
var _stimulus := PackedFloat32Array()
var _stimulus_task := -1
var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _capacity := 0
## What is to be heard, in order: [{kind: "sound" | "fade" | "tail", voice, renderer, tuning, frames, offset}].
var _seq: Array = []
var _pos := 0 # Frames of _seq[0] done.
var _frame := Basis() # The round's front: the head's heading when it started.
var _playing := ""
var _heard_both := false
var _waiting := false # The round's sets are still loading.
var _note := ""
var _own_show := false
var _peak := 0.0 # The loudest sample rendered (tests).
var _taken: Array = []
var _was_playing := false


## The order of the picks (pure). The champion is the profile's set and tuning at the start; every other set
## challenges it once (with no tuning) and the winner stays. Then each tuning step (ITD scale, then pinna warp if the
## picks fit in MAX_PICKS): a step one way (chosen at random) against the champion; if it won, a step further that way,
## if it lost, a step the other way; STEP_PICKS picks a step, fewer at the limits. "same" keeps the champion. Which of
## the two is A is random each pick, so the champion isn't always first.
class Knockout:
	extends RefCounted
	const STEPS := {"itd_scale": 0.1, "pinna_warp": 0.07}
	const LIMITS := {"itd_scale": [0.7, 1.3], "pinna_warp": [0.85, 1.18]}
	const STEP_PICKS := 2
	const MAX_PICKS := 9

	var start := {} # {set, tuning}
	var champion := {}
	var challenger := {}
	var a_is_champion := true
	var stage := "sets" # "sets", "itd_scale", "pinna_warp", "done"
	var done := 0
	var total := 0
	var history: Array = [] # [{stage, champion, challenger, choice, won}]
	var _sets: Array[String] = []
	var _params: Array[String] = []
	var _left := 0
	var _dir := 1
	var _turned := false
	var _moved := false
	var _rng := RandomNumberGenerator.new()

	func _init(p_sets: Array, p_current: String, p_tuning: Dictionary, p_seed := 0) -> void:
		_rng.seed = p_seed if p_seed != 0 else int(Time.get_ticks_usec())
		start = {"set": p_current, "tuning": full(p_tuning)}
		champion = start.duplicate(true)
		for s in p_sets:
			if str(s) != p_current and not str(s) in _sets:
				_sets.append(str(s))
		_params.assign(["itd_scale"])
		if _sets.size() + 2 * STEP_PICKS <= MAX_PICKS:
			_params.append("pinna_warp")
		total = _sets.size() + _params.size() * STEP_PICKS
		_next()

	static func full(t: Dictionary) -> Dictionary:
		return {"itd_scale": float(t.get("itd_scale", 1.0)), "pinna_warp": float(t.get("pinna_warp", 1.0)),
				"concha_db": float(t.get("concha_db", 0.0))}

	## The two to hear now: {stage, a: {set, tuning}, b: {set, tuning}}, or {} when it is over.
	func current() -> Dictionary:
		if stage == "done":
			return {}
		return {"stage": stage, "a": (champion if a_is_champion else challenger).duplicate(true),
				"b": (challenger if a_is_champion else champion).duplicate(true)}

	## The challengers the next pick may bring, whichever way this one goes: [{set, tuning}], to load them early.
	func upcoming() -> Array:
		var out: Array = []
		if stage == "done":
			return out
		for choice: String in ["a", "b"]:
			var k := _copy()
			k.pick(choice)
			if not k.challenger.is_empty():
				out.append(k.challenger)
		return out

	func _copy() -> Knockout:
		var k: Knockout = (get_script() as GDScript).new([], str(start.set), {}, 1)
		for p: String in ["start", "champion", "challenger", "a_is_champion", "stage", "done", "total", "_left", "_dir",
				"_turned", "_moved"]:
			var v: Variant = get(p)
			k.set(p, v.duplicate(true) if v is Dictionary else v)
		k._sets = _sets.duplicate()
		k._params = _params.duplicate()
		k._rng.state = _rng.state
		return k

	## The viewer's pick: "a", "b" or "same". Returns whether the challenger won.
	func pick(choice: String) -> bool:
		if stage == "done":
			return false
		var won := choice in ["a", "b"] and (choice == "a") != a_is_champion
		history.append({"stage": stage, "champion": champion.duplicate(true), "challenger": challenger.duplicate(true),
				"choice": choice, "won": won})
		done += 1
		if won:
			champion = challenger.duplicate(true)
		if stage != "sets":
			_left -= 1
			_moved = _moved or won
			if not won:
				# Lost after a win (the best is found) or both ways heard: this step is done.
				if _turned or _moved:
					total -= _left
					_left = 0
				else:
					_dir = -_dir
					_turned = true
		_next()
		return won

	## {set, tuning, changed}: the champion at the end.
	func result() -> Dictionary:
		return {"set": champion.set, "tuning": champion.tuning.duplicate(), "changed": not same(champion, start)}

	static func same(x: Dictionary, y: Dictionary) -> bool:
		if x.set != y.set:
			return false
		for k: String in ["itd_scale", "pinna_warp", "concha_db"]:
			if not is_equal_approx(float(x.tuning[k]), float(y.tuning[k])):
				return false
		return true

	func _next() -> void:
		challenger = {}
		while challenger.is_empty() and stage != "done":
			if stage == "sets":
				if not _sets.is_empty():
					challenger = {"set": _sets.pop_front(), "tuning": full({})}
				else:
					_next_param()
			elif _left <= 0:
				_next_param()
			else:
				var v := _step()
				if not is_equal_approx(v, float(champion.tuning[stage])):
					challenger = champion.duplicate(true)
					challenger.tuning[stage] = v
				elif _turned or _moved:
					# At the limit, and the other way already heard or beaten: this step is done.
					total -= _left
					_left = 0
				else:
					_dir = -_dir
					_turned = true
		a_is_champion = _rng.randf() < 0.5

	func _next_param() -> void:
		if _params.is_empty():
			stage = "done"
			return
		stage = _params.pop_front()
		_left = STEP_PICKS
		_dir = 1 if _rng.randf() < 0.5 else -1
		_turned = false
		_moved = false

	func _step() -> float:
		var lim: Array = LIMITS[stage]
		return snappedf(clampf(float(champion.tuning[stage]) + _dir * float(STEPS[stage]), lim[0], lim[1]), 0.001)


func status() -> Dictionary:
	return {"running": running, "stage": search.stage if search != null else "",
			"pick": mini(search.done + 1, search.total) if search != null else 0,
			"picks": search.total if search != null else 0, "playing": _playing, "heard_both": _heard_both,
			"ready": running and not _waiting, "skips": _playback.get_skips() if _playback != null else 0,
			"lead_ms": roundi(LEAD_SECONDS * 1000.0)}


func start() -> void:
	var sp: Node = main.features.speakers
	if running:
		return
	var ui: Node = main.get("ui")
	if sp.renderer == null or not sp.available() or ui == null or ui.get("card") == null:
		_say("Spatial sound isn't available in this player.", 6.0)
		return
	var sets: Array = []
	for s: Dictionary in sp.hrtf_sets():
		if s.downloaded:
			sets.append(s.id)
	search = Knockout.new(sets, str(sp.hrtf), sp.profile_settings().tuning)
	_rate = AudioServer.get_mix_rate()
	_seq = []
	_pos = 0
	_playing = ""
	_note = ""
	_peak = 0.0
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var seconds := play_seconds
	var rate := _rate
	_stimulus = PackedFloat32Array()
	_stimulus_task = WorkerThreadPool.add_task(func() -> void: _stimulus = stimulus(seconds, rate, rng))
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = _rate
	gen.buffer_length = BUFFER_SECONDS
	_player = AudioStreamPlayer.new()
	_player.name = "TuneSound"
	# A tool's sound (scripts/env/env_audio.gd): never ducked, never driving the film's analysis.
	_player.bus = &"Interface" if AudioServer.get_bus_index("Interface") >= 0 else &"Master"
	_player.stream = gen
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback()
	_capacity = _playback.get_frames_available()
	_was_playing = main.player.is_playing()
	if _was_playing:
		main.player.pause()
	if ui.has_method("hide_panel"):
		ui.hide_panel()
	ui.card.dismissed.connect(_on_card_dismissed)
	_take_triggers()
	running = true
	_begin_round()


func cancel() -> void:
	if not running:
		return
	_end()
	_say("Spatial sound tuning cancelled; nothing changed.", 6.0)


## A choice from the card (or the spatial_tune command): "a", "b", "same" (can't tell: the champion stays), "again".
## Returns "" or why it was not taken.
func choose(what: String) -> String:
	if not running:
		return "not running"
	var error := ""
	match what:
		"again":
			if _waiting:
				error = "still getting the sounds ready"
			else:
				_stop_sound()
				_seq.append_array(_round_seq())
		"a", "b", "same":
			if not _heard_both:
				error = "hear both first"
			else:
				var pair := search.current()
				_stop_sound()
				var won := search.pick(what)
				print("Spatial tune: %s, A %s, B %s: %s (%s)" % [pair.stage, _describe(pair.a), _describe(pair.b),
						what, "the challenger wins" if won else "the champion stays"])
				_begin_round()
				return ""
		_:
			error = "choose a, b, same or again"
	_note = "Listen to both first." if error == "hear both first" else ""
	_show_card()
	return error


func _process(_delta: float) -> void:
	if not running:
		return
	if _waiting and _round_ready():
		_waiting = false
		var cam: Node3D = main.camera
		var fwd: Vector3 = -cam.global_transform.basis.z if cam != null else Vector3.FORWARD
		_frame = Basis(Vector3.UP, -atan2(fwd.x, -fwd.z)) if Vector2(fwd.x, fwd.z).length() > 0.01 else Basis()
		_seq.append_array(_round_seq())
		_update_text()
	_feed()


## The next pick: its candidates loading (and those the pick after it may need), its card up; or the end.
func _begin_round() -> void:
	var pair := search.current()
	if pair.is_empty():
		_finish()
		return
	_heard_both = false
	_note = ""
	var wanted: Array = [pair.a, pair.b]
	wanted.append_array(search.upcoming())
	var keep: Array = wanted.map(func(v: Dictionary) -> String: return _key(v))
	for key: String in _renderers.keys():
		if not key in keep and int(_renderers[key].task) < 0:
			_renderers.erase(key)
	for v: Dictionary in wanted:
		_load(v)
	_waiting = true
	_show_card()


## A renderer per set and ear shape: a new pinna warp rebuilds the set's grid (as long as loading it), so that is
## done on the worker thread too; the head size and concha gain are cheap to change between plays.
static func _key(v: Dictionary) -> String:
	return "%s|%.3f" % [v.set, float(v.tuning.pinna_warp)]


## Starts loading a candidate's set into a renderer of its own, on a worker thread (about 0.27 s on the headset).
func _load(v: Dictionary) -> void:
	var key := _key(v)
	if _renderers.has(key):
		return
	var r: Object = ClassDB.instantiate("BinauralRenderer")
	r.set_sample_rate(_rate)
	var file: String = main.features.speakers.hrtf_file(str(v.set))
	var t: Dictionary = v.tuning
	_renderers[key] = {"renderer": r, "ok": false, "task": WorkerThreadPool.add_task(func() -> void:
		if r.load_hrtf(file) == OK:
			r.set_tuning(float(t.itd_scale), float(t.pinna_warp), float(t.concha_db)))}


## Both of the pick's candidates loaded (and the sound made). One that fails to load loses its pick.
func _round_ready() -> bool:
	if _stimulus_task >= 0:
		if not WorkerThreadPool.is_task_completed(_stimulus_task):
			return false
		WorkerThreadPool.wait_for_task_completion(_stimulus_task)
		_stimulus_task = -1
	var pair := search.current()
	for v: Dictionary in [pair.a, pair.b]:
		var e: Dictionary = _renderers.get(_key(v), {})
		if e.is_empty():
			_load(v)
			return false
		if int(e.task) >= 0:
			if not WorkerThreadPool.is_task_completed(int(e.task)):
				return false
			WorkerThreadPool.wait_for_task_completion(int(e.task))
			e.task = -1
			e.ok = e.renderer.is_ready()
			if e.ok:
				_configure(e.renderer)
	var failed: Array = []
	for voice: String in ["a", "b"]:
		if not _renderers[_key(pair[voice])].ok:
			push_warning("Spatial tune: can't load %s" % pair[voice].set)
			failed.append(voice)
	if failed.is_empty():
		return true
	# The one that loaded wins (both failed: the champion stays).
	search.pick("same" if failed.size() == 2 else ("b" if failed[0] == "a" else "a"))
	_begin_round()
	return false


## The renderer as the speakers' is, but with one source straight ahead (the path turns the listener) and only the
## light room of 180 / 360 (the reverb, no walls).
func _configure(r: Object) -> void:
	var sp: Node = main.features.speakers
	r.set_eq(sp.profile_settings().eq)
	r.set_gain(SpatialAudio.GAIN)
	var wet := float(SpatialAudio.SPHERE_ROOM.wet) * float(sp.reverb)
	r.set_room({"min": Vector3(-3, 0, -3), "max": Vector3(3, 2.8, 3), "reflect": 0.0,
			"rt60": SpatialAudio.SPHERE_ROOM.rt60, "wet": wet, "enabled": wet > 0.0})
	r.set_sources([{"input": 0, "kind": "point", "position": Vector3.FORWARD, "gain": 1.0, "at_infinity": true,
			"reflections": false}])


## A, a gap, B, a tail: the round's plays, each with its renderer and tuning.
func _round_seq() -> Array:
	var pair := search.current()
	var out: Array = []
	for voice: String in ["a", "b"]:
		var v: Dictionary = pair[voice]
		var r: Object = _renderers[_key(v)].renderer
		out.append({"kind": "sound", "voice": voice, "renderer": r, "tuning": v.tuning, "offset": 0,
				"frames": _stimulus.size()})
		out.append({"kind": "tail", "voice": voice, "renderer": r, "tuning": v.tuning, "offset": 0,
				"frames": int((GAP if voice == "a" else TAIL) * _rate)})
	return out


## Ends what plays with a short fade and lets the room's tail ring out.
func _stop_sound() -> void:
	if _seq.is_empty():
		return
	var step: Dictionary = _seq[0]
	if step.kind == "sound" and _pos > 0:
		var fade := step.duplicate()
		fade.kind = "fade"
		fade.offset = int(step.offset) + _pos
		fade.frames = BLOCK
		var tail := step.duplicate()
		tail.kind = "tail"
		tail.frames = int(TAIL * _rate)
		_seq = [fade, tail]
	elif step.kind == "sound":
		_seq = []
	else:
		_seq = [step]
		return
	_pos = 0
	if _playing != "":
		_playing = ""
		_update_text()


## Keeps the stream LEAD_SECONDS ahead.
func _feed() -> void:
	if _playback == null:
		return
	var queued := _capacity - _playback.get_frames_available()
	var want := int(LEAD_SECONDS * _rate)
	var n := 0
	while queued < want and n < 16:
		_playback.push_buffer(_block())
		queued += BLOCK
		n += 1


## The next BLOCK frames: the step playing, rendered with the listener at the head's pose now (turned by the path).
func _block() -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(BLOCK)
	if _seq.is_empty():
		return out
	var step: Dictionary = _seq[0]
	var r: Object = step.renderer
	if _pos == 0 and step.kind == "sound":
		var t: Dictionary = step.tuning
		r.set_tuning(float(t.itd_scale), float(t.pinna_warp), float(t.concha_db))
		r.reset()
		_playing = step.voice
		_update_text()
	var input := PackedFloat32Array()
	input.resize(BLOCK)
	var from := int(step.offset) + _pos
	if step.kind != "tail":
		for i in BLOCK:
			var k := from + i
			if k >= _stimulus.size():
				break
			input[i] = _stimulus[k] * ((1.0 - float(_pos + i) / BLOCK) if step.kind == "fade" else 1.0)
	var cam: Node3D = main.camera
	var head: Transform3D = cam.global_transform if cam != null else Transform3D()
	# The tail stays where the sound ended.
	var at := _stimulus.size() if step.kind == "tail" else mini(from + BLOCK / 2, _stimulus.size())
	var t_play := at / _rate
	r.set_listener(listener_pose(head, _frame, path(t_play, play_seconds)))
	var st: PackedFloat32Array = r.render(input, 1)
	for i in mini(BLOCK, st.size() / 2):
		out[i] = Vector2(st[2 * i], st[2 * i + 1])
		_peak = maxf(_peak, absf(st[2 * i]))
	_pos += BLOCK
	if _pos >= int(step.frames):
		_seq.pop_front()
		_pos = 0
		if step.kind == "sound":
			_playing = ""
			if step.voice == "b":
				_heard_both = true
			_update_text()
	return out


## The path's turn at t seconds into a play of `seconds`: the source's direction is this times straight ahead, in the
## round's frame. Round the horizon to the right, then up over the top.
static func path(t: float, seconds: float) -> Basis:
	var circle := seconds * CIRCLE_SHARE
	if t <= circle:
		return Basis(Vector3.UP, -TAU * clampf(t / maxf(circle, 1e-3), 0.0, 1.0))
	var u := clampf((t - circle) / maxf(seconds - circle, 1e-3), 0.0, 1.0)
	return Basis(Vector3.RIGHT, deg_to_rad(OVERHEAD_DEG) * u)


## The renderer's listener for a source fixed straight ahead (-Z) that should be heard at frame * turn * ahead in
## the room: the head turned back by the path, so the source sits where the path has it relative to the real head.
static func listener_pose(head: Transform3D, frame: Basis, turn: Basis) -> Transform3D:
	return Transform3D((frame * turn).inverse() * head.basis.orthonormalized(), head.origin)


## The sound: pink noise (Paul Kellet's filter on white noise) in pulses PULSE apart, each within JITTER_DB of
## LEVEL_DB, with RAMP fades.
static func stimulus(seconds: float, rate: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(seconds * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var b := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var ramp := maxf(RAMP * rate, 1.0)
	var period := int(PULSE * rate)
	var on := int(PULSE_ON * rate)
	var level := 1.0
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
		var k := i % period
		if k == 0:
			level = db_to_linear(LEVEL_DB + rng.randf_range(-JITTER_DB, JITTER_DB))
		var g := 0.0
		if k < on:
			g = 1.0
			if k < ramp:
				g = 0.5 - 0.5 * cos(PI * k / ramp)
			elif k >= on - ramp:
				g = 0.5 - 0.5 * cos(PI * (on - 1 - k) / ramp)
		if i - k + on > n:
			g = 0.0 # A pulse the end would cut short is left out.
		out[i] = p * 0.11 * level * g
	return out


func _finish() -> void:
	var r := search.result()
	var sp: Node = main.features.speakers
	var before := _describe(search.start)
	var t: Dictionary = r.tuning
	# Saved while the film is still paused (a new set loads in the speakers' renderer).
	sp.set_hrtf(str(r.set))
	sp.set_profile_tuning({"itd_scale": t.itd_scale, "pinna_warp": t.pinna_warp, "concha_db": t.concha_db,
			"picks": search.done, "changed": r.changed, "tuned_at": Time.get_datetime_string_from_system()})
	_end()
	var where := "headphones" if sp.profile() == "headphones" else "headset's speakers"
	if r.changed:
		_say("Spatial sound for the %s is now %s. Before: %s." % [where, _describe(r), before], 15.0)
	else:
		_say("Spatial sound for the %s: you kept what you had, %s." % [where, before], 15.0)


func _end() -> void:
	running = false
	_waiting = false
	_playing = ""
	_seq = []
	var ui: Node = main.get("ui")
	if ui != null and ui.get("card") != null and ui.card.dismissed.is_connected(_on_card_dismissed):
		ui.card.dismissed.disconnect(_on_card_dismissed)
		if ui.card.is_showing() and ui.card.id == CARD_ID:
			ui.card.dismiss("cleared")
	if is_instance_valid(_player):
		_player.queue_free()
	_player = null
	_playback = null
	if _stimulus_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_stimulus_task)
		_stimulus_task = -1
	for e: Dictionary in _renderers.values():
		if int(e.task) >= 0:
			WorkerThreadPool.wait_for_task_completion(int(e.task))
	_renderers.clear()
	_give_back_triggers()
	if _was_playing:
		main.player.play()


## "Listener H3, head size 110 %" (and the ear shape when it isn't 100 %).
func _describe(v: Dictionary) -> String:
	var name := str(v.set)
	for s: Dictionary in main.features.speakers.hrtf_sets():
		if s.id == v.set:
			name = s.name
	var text := "%s, head size %d %%" % [name, roundi(float(v.tuning.itd_scale) * 100.0)]
	if not is_equal_approx(float(v.tuning.pinna_warp), 1.0):
		text += ", ear shape %d %%" % roundi(float(v.tuning.pinna_warp) * 100.0)
	return text


# --- The card ------------------------------------------------------------------------------------------------------

func _show_card() -> void:
	var ui: Node = main.get("ui")
	if not running or ui == null:
		return
	_own_show = true
	ui.card.show_card({"id": CARD_ID, "seconds": 0.0, "text": _text(),
			"title": "%s: pick %d of %d" % [STAGE_NAMES.get(search.stage, ""), mini(search.done + 1, search.total),
					search.total],
			"actions": [{"id": "a", "label": "A"}, {"id": "b", "label": "B"}, {"id": "same", "label": "Can't tell"},
					{"id": "again", "label": "Again"}]})
	_own_show = false


func _update_text() -> void:
	var ui: Node = main.get("ui")
	if running and ui != null:
		ui.card.set_card_text(CARD_ID, _text())


func _text() -> String:
	var lines: Array[String] = []
	if search.done == 0:
		lines.append(("A sound circles you, then passes overhead: first as A, then as B. Turn your head if you like. "
				+ "There is no right answer: pick whichever sounds more real, more outside your head, more in the room. "
				+ "%d picks, about %d minutes. The menu button stops; nothing changes then.") % [search.total,
				maxi(1, roundi(search.total * ROUND_SECONDS / 60.0))])
	else:
		lines.append("No right answer: pick whichever sounds more real, more outside your head.")
	if _waiting:
		lines.append("Getting the sounds ready...")
	elif _playing != "":
		lines.append("Now playing: %s" % _playing.to_upper())
	elif _heard_both:
		lines.append("Which sounded better, A or B? Can't tell keeps it as it is.")
	elif not _seq.is_empty():
		lines.append("Next: B")
	if _note != "":
		lines.append(_note)
	return "\n\n".join(lines)


func _on_card_dismissed(id: String, how: String) -> void:
	if not running or _own_show or id != CARD_ID:
		return
	match how:
		"a", "b", "same", "again":
			choose(how)
		"replaced", "cleared":
			# Another card took its place: stop, nothing changed.
			print("Spatial tune: stopped (%s by another card)" % how)
			_end()
		_:
			_show_card() # The trigger beside the buttons: the card stays.


# --- The controllers -----------------------------------------------------------------------------------------------

## The trigger is the tuning's while it runs: main's handler off (no play / pause), the card's choices through the UI
## layer; the other controller's trigger makes it the pointer. The menu button cancels.
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


func _on_trigger(hand: XRController3D, pressed: bool) -> void:
	var ui: Node = main.get("ui")
	if not running or ui == null:
		return
	if ui.on_trigger(hand, pressed):
		return
	if pressed and hand != ui.get("pointer_hand") and hand.has_method("get_ray_origin"):
		ui.set_pointer_hand(hand)


func _on_menu(_hand: XRController3D) -> void:
	cancel.call_deferred()


func _say(text: String, seconds: float) -> void:
	var ui: Node = main.get("ui")
	if ui != null and ui.get("card") != null:
		ui.card.show_card({"text": text, "title": "Spatial sound", "seconds": seconds, "id": CARD_ID})
