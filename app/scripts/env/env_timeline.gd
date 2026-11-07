extends RefCounted

## The timeline and the cues (docs/environments.md, "Timeline and cues"). States from playback (the player's position,
## duration and end, the intermission, the pre-show), and the cues a room document declares: triggers on a state, on a
## signal crossing a level for long enough, or every so often; the settings they require; a chance and a cooldown;
## steps that fade parameters, wait, release them, run a system's action or play a sound. Data only: a cue names what
## the host (env_host.gd) already has.
##
##   observe(snap, delta)   one step: snap {open, playing, position, duration, intermission, ended}
##   state, previous        the state now and the one before
##   run_cue(name)          starts a cue now (tests, the assistant's room preview)
##   fired                  [[cue, clock], ...] every cue started (tests)
##   signal state_changed(state, previous)

signal state_changed(state: String, previous: String)

const STARTING_WINDOW := 10.0
## Credits only in films at least this long.
const CREDITS_MIN_FILM := 20.0 * 60.0

var host: Node
## "" until the first step, which enters the first state (its cues fire then).
var state := ""
var previous := ""
var starting_seconds := 8.0
var credits_minutes := 6.0
var clock := 0.0
var fired: Array = []
var _cues: Array = []
## name -> {step, wait, since_fired}
var _running := {}
var _last_fired := {}
var _signal_for := {}
var _signal_armed := {}
var _every := {}
var _starting_left := 0.0
var _started := false


func setup(p_host: Node, doc: Dictionary) -> void:
	host = p_host
	var t: Dictionary = doc.get("timeline", {}) if doc.get("timeline") is Dictionary else {}
	starting_seconds = float(t.get("starting_seconds", 8.0))
	credits_minutes = float(t.get("credits_minutes", 6.0))
	_cues = doc.get("cues", []) if doc.get("cues") is Array else []
	for c: Dictionary in _cues:
		_signal_armed[c["name"]] = true


## The channels the cues' triggers read (the host keeps them fresh).
func channels() -> Array[String]:
	var out: Array[String] = []
	for c: Dictionary in _cues:
		var w: Dictionary = c.get("when", {})
		if w.has("signal"):
			out.append(str(w["signal"]))
	return out


func observe(snap: Dictionary, delta: float) -> void:
	clock += delta
	var s := _state_for(snap, delta)
	if s != state:
		previous = state
		state = s
		state_changed.emit(state, previous)
		_on_state(state)
	_triggers(delta)
	_run(delta)


func _state_for(snap: Dictionary, delta: float) -> String:
	var open := bool(snap.get("open", false))
	var playing := bool(snap.get("playing", false))
	var pos := float(snap.get("position", 0.0))
	var dur := float(snap.get("duration", 0.0))
	if not open:
		_started = false
		return "preshow"
	if bool(snap.get("intermission", false)):
		return "intermission"
	if bool(snap.get("ended", false)) and not playing:
		_started = false
		return "ended"
	if not playing:
		if not _started and pos < 2.0:
			return "preshow"
		return "paused"
	if not _started:
		_started = true
		# From its start (the pre-show or the end before): the starting ritual's state; resumed later: playing.
		if pos < STARTING_WINDOW and state in ["", "preshow", "ended"]:
			_starting_left = starting_seconds
	if _starting_left > 0.0:
		_starting_left -= delta
		if _starting_left > 0.0:
			return "starting"
	var credits := minf(credits_minutes * 60.0, dur * 0.1)
	if dur >= CREDITS_MIN_FILM and credits > 0.0 and dur - pos <= credits:
		return "credits"
	return "playing"


# --- Cues -------------------------------------------------------------------------------------------------------------

func _on_state(s: String) -> void:
	for c: Dictionary in _cues:
		var w: Dictionary = c.get("when", {})
		if not w.has("state"):
			continue
		var states: Array = w["state"] if w["state"] is Array else [w["state"]]
		if s in states:
			_try(c)


func _triggers(delta: float) -> void:
	for c: Dictionary in _cues:
		var w: Dictionary = c.get("when", {})
		var n := str(c["name"])
		if w.has("signal"):
			var v := float(host.channel(str(w["signal"])))
			var over: bool = v > float(w["above"]) if w.has("above") else v < float(w["below"])
			_signal_for[n] = float(_signal_for.get(n, 0.0)) + delta if over else 0.0
			if not over:
				_signal_armed[n] = true
			elif bool(_signal_armed.get(n, true)) and float(_signal_for[n]) >= float(w.get("for", 0.0)):
				_signal_armed[n] = false
				_try(c)
		elif w.has("every"):
			_every[n] = float(_every.get(n, 0.0)) + delta
			if float(_every[n]) >= float(w["every"]):
				_every[n] = 0.0
				_try(c)


## Whether a cue may fire now: its states, the settings it requires, its cooldown, its chance.
func allowed(c: Dictionary) -> bool:
	var n := str(c["name"])
	if _running.has(n):
		return false
	if c.has("states") and not (state in c["states"]):
		return false
	for r: Dictionary in c.get("requires", []):
		var v: Variant = host.setting(str(r["setting"]))
		if r.has("is"):
			if v != r["is"] and not (v is float and r["is"] is float and is_equal_approx(v, r["is"])):
				return false
		elif not bool(v):
			return false
	if _last_fired.has(n) and clock - float(_last_fired[n]) < float(c.get("cooldown", 0.0)):
		return false
	return true


func _try(c: Dictionary) -> void:
	if not allowed(c):
		return
	if c.has("chance") and host.rng.randf() >= float(c["chance"]):
		return
	_start(c)


func run_cue(cue_name: String) -> bool:
	for c: Dictionary in _cues:
		if c["name"] == cue_name:
			_start(c)
			return true
	return false


func _start(c: Dictionary) -> void:
	var n := str(c["name"])
	_last_fired[n] = clock
	fired.append([n, clock])
	_running[n] = {"cue": c, "step": 0, "wait": 0.0}


func running() -> Array:
	return _running.keys()


func _run(delta: float) -> void:
	for n: String in _running.keys():
		var r: Dictionary = _running[n]
		r["wait"] = float(r["wait"]) - delta
		var steps: Array = r["cue"]["steps"]
		while float(r["wait"]) <= 0.0 and int(r["step"]) < steps.size():
			var s: Dictionary = steps[int(r["step"])]
			r["step"] = int(r["step"]) + 1
			if s.has("wait"):
				r["wait"] = float(r["wait"]) + float(s["wait"])
			elif s.has("set"):
				host.fade(str(s["set"]), s["to"], float(s.get("seconds", 0.0)), str(s.get("ease", "in_out")))
			elif s.has("release"):
				host.release(str(s["release"]), float(s.get("seconds", 0.0)), str(s.get("ease", "in_out")))
			elif s.has("do"):
				host.do_action(str(s["do"]), s.get("args", {}))
			elif s.has("sound"):
				host.play_sound(str(s["sound"]), float(s.get("gain_db", 0.0)), s.get("at"))
		if int(r["step"]) >= steps.size() and float(r["wait"]) <= 0.0:
			_running.erase(n)
