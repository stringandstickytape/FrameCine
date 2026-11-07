extends SceneTree

## The environments engine's registry and the version 4 document (docs/environments.md): every system declares its
## parameters (type, range, description) and its cost; versions 1 to 3 still read; a version 4 document's sections
## are checked with paths: systems and their parameters, bindings, settings declarations, cues, film-time tracks,
## credits; the rooms that ship pass. No main scene.
## godot --headless --xr-mode off --path app --script res://tests/test_env_registry.gd

const Registry := preload("res://scripts/env/systems/registry.gd")
const EnvDoc := preload("res://scripts/env/env_doc.gd")
const RoomSchema := preload("res://scripts/assistant/room_schema.gd")

var _failures := 0
var _checks := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_registry()
	_versions()
	_systems()
	_bindings()
	_settings()
	_cues()
	_shipped()
	print("test_env_registry: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _registry() -> void:
	var names := Registry.names()
	_check("the systems registered (%s)" % [names], names.has("auditorium") and names.has("light")
			and names.has("mirror_floor") and names.has("screen_frame") and names.has("showing"))
	for n: String in names:
		var s := Registry.spec(n)
		_check("%s: a kind of the list (%s)" % [n, s.get("kind")], str(s.get("kind")) in Registry.KINDS)
		_check("%s: described" % n, str(s.get("description", "")).length() > 20)
		_check("%s: a cost (draws, triangles, lights, particles, texture_mb)" % n, (s.get("cost", {}) as Dictionary)
				.has_all(["draws", "triangles", "lights", "particles", "texture_mb"]))
		var ok := true
		var why := ""
		for p: String in s.get("params", {}):
			var ps: Dictionary = s["params"][p]
			if not (str(ps.get("type")) in EnvDoc.PARAM_TYPES) or str(ps.get("description", "")).length() < 4:
				ok = false
				why = p
			if ps.get("type") in ["float", "int"] and not (ps.has("min") and ps.has("max")):
				ok = false
				why = p + " (range)"
			# Every default passes its own check.
			var errs: Array = []
			if ps.has("default") and ps["default"] != null:
				EnvDoc.check_value(ps, ps["default"], p, errs, {"no_bind": true})
			if not errs.is_empty():
				ok = false
				why = "%s default: %s" % [p, errs]
		_check("%s: every parameter typed, ranged, described, its default valid %s" % [n, why], ok)
	var d := Registry.describe()
	_check("describe(): every spec, named, sorted", d.size() == names.size() and str(d[0]["name"]) < str(d[-1]["name"]))
	_check("unknown: no script", Registry.script_of("crowd") == null and not Registry.has("crowd"))


func _versions() -> void:
	var v1 := {"schema": 1, "name": "Old", "base": "void", "parts": [{"name": "Box", "type": "box",
			"size": [1, 1, 1], "position": [0, 0.5, -2]}]}
	_check("version 1 still reads", RoomSchema.validate(v1, "new")["ok"])
	var v3 := {"schema": 3, "name": "Three", "base": "void", "parts": [{"name": "B", "object": "box",
			"position": [0, 0.5, -2], "scale": 0.5}]}
	_check("version 3 still reads", RoomSchema.validate(v3, "new")["ok"])
	var v3sys := v3.duplicate(true)
	v3sys["systems"] = []
	var r := RoomSchema.validate(v3sys, "new")
	_check("systems need version 4 (%s)" % [r["errors"]], not r["ok"] and _has(r, "$.systems"))
	var v4 := {"schema": 4, "name": "Four", "systems": [{"system": "light"}, {"system": "auditorium"}]}
	r = RoomSchema.validate(v4, "new")
	_check("a version 4 document (%s)" % [r["errors"]], r["ok"])
	_check("EnvDoc.validate is the same", EnvDoc.validate(v4)["ok"])
	var v5 := {"schema": 5, "name": "Five"}
	_check("version 5 refused", not RoomSchema.validate(v5, "new")["ok"])


func _doc(systems: Array, extra := {}) -> Dictionary:
	var d := {"schema": 4, "name": "T", "systems": systems}
	d.merge(extra, true)
	return d


func _systems() -> void:
	var r := EnvDoc.validate(_doc([{"system": "nonsense"}]))
	_check("an unknown system, named with the known (%s)" % [r["errors"]], _has(r, "$.systems[0].system", "known"))
	r = EnvDoc.validate(_doc([{"system": "auditorium"}]))
	_check("the auditorium needs a light system before it", _has(r, "$.systems[0]", "needs a light"))
	r = EnvDoc.validate(_doc([{"system": "light"}, {"system": "auditorium", "params": {"rows_front": 99}}]))
	_check("a parameter out of range (%s)" % [r["errors"]], _has(r, "$.systems[1].params.rows_front", "at most 30"))
	r = EnvDoc.validate(_doc([{"system": "light"}, {"system": "auditorium", "params": {"rows_front": 2.5}}]))
	_check("an int that isn't whole", _has(r, "$.systems[1].params.rows_front", "whole"))
	r = EnvDoc.validate(_doc([{"system": "light"}, {"system": "auditorium", "params": {"seats": 3}}]))
	_check("an unknown parameter", _has(r, "$.systems[1].params.seats", "unknown"))
	r = EnvDoc.validate(_doc([{"system": "light"}, {"system": "auditorium", "params": {"proscenium": "castle"}}]))
	_check("an enum value it doesn't have", _has(r, "$.systems[1].params.proscenium", "one of"))
	r = EnvDoc.validate(_doc([{"system": "light"}, {"system": "auditorium", "params": {
			"floor": {"library": "no_such_material"}}}]))
	_check("a material the library doesn't have", _has(r, "$.systems[1].params.floor.library", "no such"))
	r = EnvDoc.validate(_doc([{"system": "light"}, {"system": "light"}]))
	_check("two of one system need their own ids", _has(r, "$.systems[1].id", "twice"))
	r = EnvDoc.validate(_doc([{"system": "light", "id": "a"}, {"system": "light", "id": "b"}]))
	_check("with their own ids: fine (%s)" % [r["errors"]], r["ok"])
	r = EnvDoc.validate(_doc([{"system": "light", "id": "Bad Id"}]))
	_check("an id: lower case", _has(r, "$.systems[0].id"))
	r = EnvDoc.validate(_doc([], {"room": {"ambient": 3.0}, "acoustics": {"rt60": 0.0}, "audio": {"level_db": 20}}))
	_check("room, acoustics and audio checked (%s)" % [r["errors"]], _has(r, "$.room.ambient") and
			_has(r, "$.acoustics.rt60") and _has(r, "$.audio.level_db"))
	r = EnvDoc.validate(_doc([], {"credits": [{"asset": "x.png", "title": "X", "source": "y", "licence": "CC-BY 4.0"}]}))
	_check("credits: CC0 only", _has(r, "$.credits[0].licence", "CC0"))


func _bindings() -> void:
	var light := {"system": "light", "params": {"house_lamps": {"bind": "film.brightness", "range": [0.2, 1.0],
			"smooth": 0.5}}}
	var r := EnvDoc.validate(_doc([light]))
	_check("a binding on a live parameter (%s)" % [r["errors"]], r["ok"])
	r = EnvDoc.validate(_doc([{"system": "light", "params": {"house_lamps": {"bind": "film.nothing"}}}]))
	_check("an unknown channel", _has(r, "$.systems[0].params.house_lamps.bind", "a channel"))
	r = EnvDoc.validate(_doc([{"system": "light"}, {"system": "auditorium", "params": {"rows_front":
			{"bind": "film.bass"}}}]))
	_check("a film signal can't drive a parameter built once", _has(r, "$.systems[1].params.rows_front.bind",
			"built once"))
	r = EnvDoc.validate(_doc([{"system": "light", "params": {"house_lamps": {"bind": "film.bass", "range": [0, 5]}}}]))
	_check("a binding's range inside the parameter's", _has(r, "$.systems[0].params.house_lamps.range[1]", "at most"))
	r = EnvDoc.validate(_doc([{"system": "light", "params": {"house_lamps": {"bind": "film.bass", "range": [0, 1],
			"map": {"a": 1}}}}]))
	_check("one of range, keys and map", _has(r, "$.systems[0].params.house_lamps", "one of"))
	r = EnvDoc.validate(_doc([{"system": "light", "params": {"house_lamps": {"bind": "playback.state"}}}]))
	_check("a state's name must be mapped", _has(r, "$.systems[0].params.house_lamps", "map it"))
	r = EnvDoc.validate(_doc([{"system": "light", "params": {"house_lamps": {"bind": "playback.state",
			"map": {"playing": 0.2, "lunch": 1.0}}}}]))
	_check("a map's states are states", _has(r, "$.systems[0].params.house_lamps.map.lunch", "a state"))
	r = EnvDoc.validate(_doc([{"system": "light", "params": {"house_lamps": {"bind": "film.colour"}}}]))
	_check("a colour drives colours only", _has(r, "$.systems[0].params.house_lamps.bind", "colour"))
	r = EnvDoc.validate(_doc([{"system": "light", "params": {"house_lamps": {"bind": "film.minutes",
			"keys": [[0, 0.0], [10, 1.0], [5, 0.5]]}}}]))
	_check("keys with x rising", _has(r, "$.systems[0].params.house_lamps.keys[2]", "rising"))
	r = EnvDoc.validate(_doc([{"system": "light", "params": {"house_lamps": {"bind": "setting.none"}}}]))
	_check("a setting the room doesn't declare", _has(r, "$.systems[0].params.house_lamps.bind"))
	r = EnvDoc.validate(_doc([{"system": "light", "params": {"house_lamps": {"bind": "setting.motion",
			"range": [0, 1]}}}]))
	_check("a common setting is a channel too (%s)" % [r["errors"]], r["ok"])
	r = EnvDoc.validate(_doc([{"system": "light", "params": {"house_lamps": {"bind": "film.bass", "expr": "1+1"}}}]))
	_check("no expressions: an unknown key in a binding", _has(r, "$.systems[0].params.house_lamps.expr", "unknown"))


func _settings() -> void:
	var good := [{"name": "weather", "type": "choice", "choices": ["rain", "mist", "clear", "changing"],
			"labels": ["Rain", "Mist", "Clear", "Changing"], "default": "changing", "label": "Weather",
			"description": "Rain on the roof, mist, a clear night, or each in turn."},
			{"name": "tinny", "type": "bool", "default": false, "label": "Window speaker",
			"description": "The film through the car's window speaker."},
			{"name": "earth_speed", "type": "range", "min": 0.5, "max": 4.0, "step": 0.5, "default": 1.0,
			"format": "times", "label": "Earth's speed", "description": "How fast Earth turns over the film."}]
	var r := EnvDoc.validate(_doc([], {"settings": good}))
	_check("three declarations: a choice, a bool, a range (%s)" % [r["errors"]], r["ok"])
	var bad: Array = [
		[{"name": "Bad", "type": "bool", "default": true, "label": "X", "description": "Y"}, "$.settings[0].name"],
		[{"name": "dim", "type": "bool", "default": true, "label": "X", "description": "Y"}, "$.settings[0].name"],
		[{"name": "a", "type": "slider", "default": 1, "label": "X", "description": "Y"}, "$.settings[0].type"],
		[{"name": "a", "type": "range", "min": 2, "max": 1, "default": 1, "label": "X", "description": "Y"},
				"$.settings[0]"],
		[{"name": "a", "type": "range", "min": 0, "max": 1, "default": 3, "label": "X", "description": "Y"},
				"$.settings[0].default"],
		[{"name": "a", "type": "choice", "choices": ["x", "y"], "labels": ["X"], "default": "x", "label": "X",
				"description": "Y"}, "$.settings[0].labels"],
		[{"name": "a", "type": "choice", "choices": ["x", "y"], "labels": ["X", "Y"], "default": "z", "label": "X",
				"description": "Y"}, "$.settings[0].default"],
		[{"name": "a", "type": "bool", "default": true, "label": "", "description": "Y"}, "$.settings[0].label"],
		[{"name": "a", "type": "bool", "default": true, "label": "X", "description": "Y", "code": "x"},
				"$.settings[0].code"],
	]
	for b: Array in bad:
		r = EnvDoc.validate(_doc([], {"settings": [b[0]]}))
		_check("a bad declaration caught at %s (%s)" % [b[1], r["errors"]], _has(r, b[1]))
	r = EnvDoc.validate(_doc([], {"settings": [good[1], good[1]]}))
	_check("a name declared twice", _has(r, "$.settings[1].name", "twice"))
	# Bound through the binding mechanism, map for a choice.
	r = EnvDoc.validate(_doc([{"system": "light", "params": {"house_lamps": {"bind": "setting.weather",
			"map": {"rain": 0.2, "clear": 1.0}}}}], {"settings": good}))
	_check("a setting bound to a parameter by map (%s)" % [r["errors"]], r["ok"])


func _cues() -> void:
	var sys := [{"system": "light"}, {"system": "showing"}]
	var good := {"name": "whale", "when": {"signal": "film.quiet", "above": 0.9, "for": 4}, "states": ["playing"],
			"chance": 0.5, "cooldown": 900, "steps": [{"set": "light.house_lamps", "to": 0.0, "seconds": 2},
			{"wait": 1}, {"do": "showing.open_curtains", "args": {"seconds": 3}}, {"sound": "whale", "gain_db": -6},
			{"release": "light.house_lamps", "seconds": 2}]}
	var r := EnvDoc.validate(_doc(sys, {"cues": [good]}))
	_check("a cue with every kind of step (%s)" % [r["errors"]], r["ok"])
	var bad: Array = [
		[{"name": "a", "when": {"state": "lunch"}, "steps": [{"wait": 1}]}, "$.cues[0].when.state"],
		[{"name": "a", "when": {"signal": "film.bass"}, "steps": [{"wait": 1}]}, "$.cues[0].when"],
		[{"name": "a", "when": {"every": 0}, "steps": [{"wait": 1}]}, "$.cues[0].when.every"],
		[{"name": "a", "when": {"state": "playing"}, "steps": []}, "$.cues[0].steps"],
		[{"name": "a", "when": {"state": "playing"}, "steps": [{"set": "hall.rows_front", "to": 2}]},
				"$.cues[0].steps[0].set"],
		[{"name": "a", "when": {"state": "playing"}, "steps": [{"set": "light.bake", "to": false}]},
				"$.cues[0].steps[0].set"],
		[{"name": "a", "when": {"state": "playing"}, "steps": [{"set": "light.house_lamps", "to": 4}]},
				"$.cues[0].steps[0].to"],
		[{"name": "a", "when": {"state": "playing"}, "steps": [{"do": "showing.dance"}]}, "$.cues[0].steps[0].do"],
		[{"name": "a", "when": {"state": "playing"}, "steps": [{"sound": "music.mp3"}]}, "$.cues[0].steps[0].sound"],
		[{"name": "a", "when": {"state": "playing"}, "steps": [{"wait": 1, "set": "light.house_lamps"}]},
				"$.cues[0].steps[0]"],
		[{"name": "a", "when": {"state": "playing"}, "chance": 2, "steps": [{"wait": 1}]}, "$.cues[0].chance"],
		[{"name": "a", "when": {"state": "playing"}, "requires": [{"setting": "nope"}], "steps": [{"wait": 1}]},
				"$.cues[0].requires[0].setting"],
		[{"name": "a", "when": {"state": "playing"}, "steps": [{"set": "light.house_lamps", "to": {"setting": "dim"}}]},
				"$.cues[0].steps[0].to"],
	]
	for b: Array in bad:
		r = EnvDoc.validate(_doc(sys, {"cues": [b[0]]}))
		_check("a bad cue caught at %s (%s)" % [b[1], r["errors"]], _has(r, b[1]))
	r = EnvDoc.validate(_doc(sys, {"timeline": {"tracks": [{"target": "light.house_lamps", "by": "film.minutes",
			"keys": [[0, 1.0], [10, 0.0]]}]}}))
	_check("a film-time track (%s)" % [r["errors"]], r["ok"])
	r = EnvDoc.validate(_doc(sys, {"timeline": {"tracks": [{"target": "light.house_lamps", "by": "film.bass",
			"keys": [[0, 1.0], [10, 0.0]]}]}}))
	_check("a track goes by film time", _has(r, "$.timeline.tracks[0].by"))


func _shipped() -> void:
	for f in DirAccess.get_files_at("res://environments"):
		if f.ends_with(".env.json"):
			var r := EnvDoc.load_file("res://environments/" + f)
			_check("%s passes (%s)" % [f, r["errors"]], (r["errors"] as Array).is_empty() and not (r["doc"] as Dictionary).is_empty())


func _has(r: Dictionary, path: String, words := "") -> bool:
	for e: Dictionary in r["errors"]:
		if str(e["path"]) == path and (words == "" or str(e["error"]).contains(words)):
			return true
	return false


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)
