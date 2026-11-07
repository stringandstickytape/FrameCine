extends SceneTree

## The timeline and cues (docs/environments.md, "Timeline and cues") with fake playback: the states from the player's
## position, duration, end and the intermission; cues on a state, on a signal held for long enough (with a cooldown),
## every so often, by chance, gated by settings; steps that fade, wait, release, act and play a sound; a fade to a
## setting's value; and the converted cinema's ritual: lights up in the pre-show, the chime, the curtains, the house
## lamps down to the room's setting, up again at the end.
## godot --headless --xr-mode off --path app --script res://tests/test_env_timeline.gd

const EnvRoom := preload("res://scripts/env/env_room.gd")
const EnvDoc := preload("res://scripts/env/env_doc.gd")

var _failures := 0
var _checks := 0


func _init() -> void:
	_run.call_deferred()


func _room(doc: Dictionary) -> Node3D:
	var v := EnvDoc.validate(doc)
	_check("%s is valid (%s)" % [doc["name"], v["errors"]], v["ok"])
	var r: Node3D = EnvRoom.new()
	r.doc = doc
	root.add_child(r)
	r.host.auto = false
	return r


func _steps(h: Node, seconds: float, dt := 0.05) -> void:
	var t := 0.0
	while t < seconds - 1e-6:
		h.step(dt)
		t += dt


func _names(h: Node) -> Array:
	return h.timeline.fired.map(func(f: Array) -> String: return str(f[0]))


func _run() -> void:
	_states()
	_cues()
	_ritual()
	print("test_env_timeline: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _states() -> void:
	var room := _room({"schema": 4, "name": "States", "systems": [{"system": "light"}],
			"timeline": {"starting_seconds": 2.0, "credits_minutes": 5.0}})
	var h: Node = room.host
	var seen: Array = []
	h.timeline.state_changed.connect(func(s: String, _p: String) -> void: seen.append(s))
	h.snapshot_override = {"open": false}
	h.step(0.05)
	_check("nothing open: the pre-show", h.timeline.state == "preshow")
	h.snapshot_override = {"open": true, "playing": false, "position": 0.0, "duration": 3600.0}
	h.step(0.05)
	_check("open at its start, not started: still the pre-show", h.timeline.state == "preshow")
	h.snapshot_override = {"open": true, "playing": true, "position": 0.1, "duration": 3600.0}
	h.step(0.05)
	_check("started from its start: starting", h.timeline.state == "starting")
	_steps(h, 2.1)
	_check("after starting_seconds: playing (%s)" % h.timeline.state, h.timeline.state == "playing")
	h.snapshot_override = {"open": true, "playing": false, "position": 600.0, "duration": 3600.0}
	h.step(0.05)
	_check("paused", h.timeline.state == "paused")
	h.snapshot_override = {"open": true, "playing": false, "position": 600.0, "duration": 3600.0,
			"intermission": true}
	h.step(0.05)
	_check("the intermission", h.timeline.state == "intermission")
	h.snapshot_override = {"open": true, "playing": true, "position": 3400.0, "duration": 3600.0}
	h.step(0.05)
	_check("the last five minutes: credits (%s)" % h.timeline.state, h.timeline.state == "credits")
	h.snapshot_override = {"open": true, "playing": false, "position": 3600.0, "duration": 3600.0, "ended": true}
	h.step(0.05)
	_check("ended", h.timeline.state == "ended")
	h.snapshot_override = {"open": true, "playing": true, "position": 0.0, "duration": 3600.0}
	h.step(0.05)
	_check("played again from its start: starting again", h.timeline.state == "starting")
	h.snapshot_override = {"open": true, "playing": true, "position": 1500.0, "duration": 1500.0 * 0.0 + 600.0}
	_check("every state seen in order (%s)" % [seen], seen == ["preshow", "starting", "playing", "paused",
			"intermission", "credits", "ended", "starting"])
	var short := _room({"schema": 4, "name": "Short", "systems": [{"system": "light"}]})
	short.host.snapshot_override = {"open": true, "playing": true, "position": 290.0, "duration": 300.0}
	short.host.step(0.05)
	_check("a short film has no credits state (%s)" % short.host.timeline.state, short.host.timeline.state == "playing")
	var resumed := _room({"schema": 4, "name": "Resumed", "systems": [{"system": "light"}]})
	resumed.host.snapshot_override = {"open": true, "playing": true, "position": 1200.0, "duration": 6000.0}
	resumed.host.step(0.05)
	_check("resumed in the middle: playing, no starting", resumed.host.timeline.state == "playing")
	for r: Node in [room, short, resumed]:
		r.queue_free()


func _cues() -> void:
	var doc := {"schema": 4, "name": "Cues",
		"systems": [{"system": "light"}, {"system": "showing"}],
		"settings": [{"name": "whale", "type": "bool", "default": true, "label": "Whale",
				"description": "A whale in quiet scenes."},
				{"name": "level", "type": "range", "min": 0.0, "max": 1.0, "default": 0.3, "label": "Level",
				"description": "A level."}],
		"cues": [
			{"name": "on_start", "when": {"state": "starting"}, "requires": [{"setting": "ritual"}],
				"steps": [{"set": "light.house_lamps", "to": 0.0, "seconds": 2.0, "ease": "linear"}, {"wait": 2.5},
				{"do": "showing.open_curtains", "args": {"seconds": 3}}, {"sound": "chime", "gain_db": -6}]},
			{"name": "no_ritual", "when": {"state": "starting"}, "requires": [{"setting": "ritual", "is": false}],
				"steps": [{"wait": 0.1}]},
			{"name": "whale", "when": {"signal": "film.quiet", "above": 0.9, "for": 2.0}, "states": ["playing"],
				"requires": [{"setting": "whale"}], "cooldown": 30.0, "steps": [{"sound": "whale"}]},
			{"name": "never", "when": {"every": 1.0}, "chance": 0.0, "steps": [{"wait": 0.1}]},
			{"name": "always", "when": {"every": 1.0}, "chance": 1.0, "cooldown": 0.0, "steps": [{"wait": 0.01}]},
			{"name": "to_setting", "when": {"state": "paused"},
				"steps": [{"set": "light.signs", "to": {"setting": "level"}, "seconds": 0.5}, {"wait": 1.0},
				{"release": "light.signs", "seconds": 0.5}]},
		]}
	var room := _room(doc)
	var h: Node = room.host
	h.snapshot_override = {"open": true, "playing": false, "position": 0.0, "duration": 6000.0}
	h.step(0.05)
	h.snapshot_override = {"open": true, "playing": true, "position": 0.0, "duration": 6000.0}
	h.step(0.05)
	_check("a state's cue fires on entering it (%s)" % [_names(h)], "on_start" in _names(h))
	_check("a cue that requires the ritual off does not", not ("no_ritual" in _names(h)))
	h.step(0.95)
	var mid := float(h.param("light.house_lamps"))
	_check("a linear fade half way after 1 of 2 s (%.2f)" % mid, absf(mid - 0.5) < 0.06)
	_steps(h, 1.1)
	_check("at its end (%.2f)" % h.param("light.house_lamps"), is_equal_approx(float(h.param("light.house_lamps")), 0.0))
	var showing: Node = h.system("showing")
	_check("waited before acting: no action yet", showing.log.is_empty())
	_steps(h, 0.6)
	_check("then the action (%s) and the sound (%s)" % [showing.log, h.sounds], showing.log.size() == 1
			and showing.log[0][0] == "open_curtains" and int(showing.log[0][1]["seconds"]) == 3
			and h.sounds.size() == 1 and h.sounds[0][0] == "chime")
	_check("chance 0: never; chance 1: every second (%d)" % _names(h).count("always"),
			not ("never" in _names(h)) and _names(h).count("always") >= 2)
	# The whale: film.quiet held 2 s, at most once in 30 s.
	_steps(h, 6.0)
	var whales := func() -> int: return _names(h).count("whale")
	h.signals.fake("film.quiet", 1.0)
	_steps(h, 1.5)
	_check("quiet for 1.5 s: no whale yet", whales.call() == 0)
	_steps(h, 1.0)
	_check("quiet for 2 s: the whale", whales.call() == 1)
	_steps(h, 5.0)
	_check("still quiet: once only", whales.call() == 1)
	h.signals.fake("film.quiet", 0.0)
	h.step(0.05)
	h.signals.fake("film.quiet", 1.0)
	_steps(h, 3.0)
	_check("quiet again within the cooldown: none", whales.call() == 1)
	h.signals.fake("film.quiet", 0.0)
	_steps(h, 25.0)
	h.signals.fake("film.quiet", 1.0)
	_steps(h, 3.0)
	_check("after the cooldown: the whale again", whales.call() == 2)
	h.set_setting("whale", false)
	h.signals.fake("film.quiet", 0.0)
	_steps(h, 35.0)
	h.signals.fake("film.quiet", 1.0)
	_steps(h, 3.0)
	_check("the room's setting off: no whale", whales.call() == 2)
	# A fade to a setting's value, then released to the document's value.
	h.signals.clear_fakes()
	h.snapshot_override = {"open": true, "playing": false, "position": 900.0, "duration": 6000.0}
	_steps(h, 0.6)
	_check("to a setting's value (%.2f)" % h.param("light.signs"), is_equal_approx(float(h.param("light.signs")), 0.3))
	_steps(h, 1.2)
	_check("released: back to its own value (%.2f)" % h.param("light.signs"),
			is_equal_approx(float(h.param("light.signs")), 1.0))
	room.queue_free()


## The converted cinema's ritual, its own document.
func _ritual() -> void:
	var cinema: Node3D = (load("res://environments/cinema.tscn") as PackedScene).instantiate()
	root.add_child(cinema)
	var h: Node = cinema.host
	h.auto = false
	var light: Node = h.system("light")
	h.snapshot_override = {"open": true, "playing": false, "position": 0.0, "duration": 6000.0}
	_steps(h, 4.5)
	_check("the pre-show: the house lamps up (%.2f)" % h.param("light.house_lamps"),
			is_equal_approx(float(h.param("light.house_lamps")), 1.0) and "lights_up" in _names(h))
	_check("the house lamps' glow as designed (%.2f)" % light.group_energy("house"),
			is_equal_approx(light.group_energy("house"), 1.6))
	h.snapshot_override = {"open": true, "playing": true, "position": 0.0, "duration": 6000.0}
	h.step(0.05)
	_check("the film starts: the ritual (%s)" % [_names(h)], "ritual" in _names(h) and not ("dim" in _names(h)))
	_check("a chime on the Environment bus", h.sounds.size() >= 1 and h.sounds[-1][0] == "chime")
	_check("the curtains part (%s)" % [h.system("showing").log], h.system("showing").log.size() == 1)
	_steps(h, 1.5)
	_check("the house lamps half down (%.2f)" % h.param("light.house_lamps"),
			absf(float(h.param("light.house_lamps")) - 0.5) < 0.05)
	_steps(h, 6.0)
	_check("then down to the room's house-lights setting, 20 %% (%.2f)" % h.param("light.house_lamps"),
			is_equal_approx(float(h.param("light.house_lamps")), 0.2))
	_check("their glow follows (%.2f)" % light.group_energy("house"), is_equal_approx(light.group_energy("house"), 0.32))
	h.snapshot_override = {"open": true, "playing": false, "position": 6000.0, "duration": 6000.0, "ended": true}
	_steps(h, 4.5)
	_check("the end: the lamps back up (%.2f)" % h.param("light.house_lamps"),
			is_equal_approx(float(h.param("light.house_lamps")), 1.0))
	# The ritual off (the common Pre-show setting): no curtains, the lamps simply go down.
	h.set_setting("ritual", false)
	cinema.apply_room_settings({"ritual": false})
	_check("Pre-show off: no curtains here", not cinema.has_curtains)
	h.snapshot_override = {"open": true, "playing": true, "position": 0.0, "duration": 6000.0}
	_steps(h, 3.5)
	_check("Pre-show off: the plain dim, not the ritual (%s)" % [_names(h)], _names(h).count("ritual") == 1
			and "dim" in _names(h))
	cinema.queue_free()


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)
