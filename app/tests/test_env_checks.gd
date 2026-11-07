extends SceneTree

## Each check (docs/environments.md, "The checks"; scripts/env/env_checks.gd) catching a bad document: a schema error,
## a room over the headset's budget, a wall between the seats and the screen, a brightness that flickers and a motion
## over its limit, an asset that isn't CC0 or isn't credited, a real mark in a name (pastiche passes), a crowd.
## godot --headless --xr-mode off --path app --script res://tests/test_env_checks.gd

const EnvChecks := preload("res://scripts/env/env_checks.gd")
const EnvRoom := preload("res://scripts/env/env_room.gd")

var _failures := 0
var _checks := 0


func _init() -> void:
	_run.call_deferred()


func _doc(systems: Array, extra := {}) -> Dictionary:
	var d := {"schema": 4, "name": "Check", "systems": systems,
			"screen": {"center": [0.0, 1.6, -13.8], "size": [12.0, 5.0]}}
	d.merge(extra, true)
	return d


func _build(doc: Dictionary) -> Node3D:
	var room: Node3D = EnvRoom.new()
	room.doc = doc
	root.add_child(room)
	return room


func _run() -> void:
	# Schema.
	var bad := _doc([{"system": "light"}, {"system": "auditorium", "params": {"rows_front": -1}}])
	_check("schema: a bad parameter (%s)" % [EnvChecks.schema(bad)], EnvChecks.schema(bad).size() == 1)
	# Budget: a hall of 61 x 61 seats.
	var huge := _build(_doc([{"system": "light"}, {"system": "auditorium", "params": {"rows_front": 30,
			"rows_back": 30, "seats_per_row": 61, "block_x": 20.0, "room_min": [-21, -11, -60],
			"room_max": [21, 25, 90]}}]))
	await process_frame
	var stats := EnvChecks.measure(huge)
	var over := EnvChecks.budget(stats)
	_check("budget: 3721 seats over it (%s)" % [over], over.any(func(s: String) -> bool: return s.begins_with("triangles")))
	huge.queue_free()
	_check("budget: a live light counts", not EnvChecks.budget({"lights": 3}).is_empty())
	# Sight line: a wall across the hall between the seats and the screen; the hall without it is clear.
	var walled := _build(_doc([{"system": "light"}, {"system": "auditorium", "params": {"partition_z": -6.0,
			"rows_front": 2, "rows_back": 1, "seats_per_row": 5}}]))
	await process_frame
	var blocked: Array = await EnvChecks.sight_line(self, walled)
	_check("sight line: the wall in the way (%d reports: %s)" % [blocked.size(), blocked.slice(0, 1)],
			blocked.size() >= 8)
	walled.queue_free()
	var open := _build(_doc([{"system": "light"}, {"system": "auditorium", "params": {"rows_front": 2,
			"rows_back": 1, "seats_per_row": 5}}]))
	await process_frame
	blocked = await EnvChecks.sight_line(self, open)
	_check("sight line: without it, clear (%s)" % [blocked], blocked.is_empty())
	open.queue_free()
	# A steep enough rake that the row in front's backs block the screen's bottom.
	var flat := _build(_doc([{"system": "light"}, {"system": "auditorium", "params": {"row_rise": 0.0,
			"rows_front": 7, "rows_back": 0, "seats_per_row": 3}}],
			{"screen": {"center": [0.0, 0.0, -13.8], "size": [12.0, 5.0]}}))
	await process_frame
	blocked = await EnvChecks.sight_line(self, flat)
	_check("sight line: flat rows with a low screen, seat backs in the way (%d)" % blocked.size(), not blocked.is_empty())
	flat.queue_free()
	# Comfort.
	var flicker := _doc([{"system": "light", "params": {"house_lamps": {"bind": "film.transient"}}}])
	_check("comfort: a brightness following a channel unsmoothed (%s)" % [EnvChecks.comfort(flicker)],
			EnvChecks.comfort(flicker).size() == 1)
	var smooth := _doc([{"system": "light", "params": {"house_lamps": {"bind": "film.transient", "smooth": 0.2}}}])
	_check("comfort: smoothed, fine", EnvChecks.comfort(smooth).is_empty())
	var snap := _doc([{"system": "light"}], {"cues": [{"name": "snap", "when": {"state": "playing"},
			"steps": [{"set": "light.house_lamps", "to": 0.0, "seconds": 0.0}]}]})
	_check("comfort: a cue's fade too quick (%s)" % [EnvChecks.comfort(snap)], EnvChecks.comfort(snap).size() == 1)
	var fake := func(n: String) -> Dictionary:
		return {"kind": "motion", "moves_viewer": n == "camera_crane", "params": {"tilt": {"type": "float",
				"min": 0.0, "max": 10.0, "default": 0.5, "motion": {"max": 1.5}}}}
	var tilted := _doc([{"system": "sway", "params": {"tilt": 4.0}}, {"system": "camera_crane"}])
	var c: Array = EnvChecks.comfort(tilted, fake)
	_check("comfort: a motion over its limit and a system moving the viewer (%s)" % [c], c.size() == 2)
	# Licences.
	var cinema_doc: Dictionary = preload("res://scripts/env/env_doc.gd").load_file("res://environments/cinema.env.json")["doc"]
	_check("licences: the cinema's library materials, CC0 and credited (%s)" % [EnvChecks.materials_of(cinema_doc)],
			EnvChecks.licences(cinema_doc).is_empty() and EnvChecks.materials_of(cinema_doc).size() >= 8)
	var uncredited := _doc([], {"credits": [{"asset": "textures/poster.png", "title": "Poster", "source": "made here",
			"licence": "CC0 1.0"}]})
	_check("licences: an asset not bundled and not credited (%s)" % [EnvChecks.licences(uncredited)],
			EnvChecks.licences(uncredited).size() == 2)
	var byline := _doc([], {"credits": [{"asset": "x.ogg", "title": "X", "source": "a site", "licence": "CC-BY 4.0"}]})
	_check("licences: CC-BY refused (%s)" % [EnvChecks.licences(byline)], EnvChecks.licences(byline).any(
			func(s: String) -> bool: return s.contains("not CC0")))
	# Names.
	_check("names: a real mark caught", EnvChecks.names(_doc([], {"name": "The Odeon"})).size() == 1)
	var marks := ["Nickelodeon", "Regal", "Omnimax", "Atmos", "Compton", "Tron", "Quality Street", "Kia-Ora",
			"Trinitron", "Baird Televisor", "HD Ready", "Sinclair", "Freeview"]
	var caught := marks.filter(func(m: String) -> bool: return not EnvChecks.names(
			{"settings": [{"label": "Our %s mode" % m.to_lower()}]}).is_empty())
	_check("names: every example caught, any case (%d of %d)" % [caught.size(), marks.size()], caught.size() == marks.size())
	var pastiche := {"name": "Sirclive", "settings": [{"label": "FreeDTV box", "description": "The atmosphere of a "
			+ "regalia-free electron gun on a Trinitronic set"}]}
	_check("names: pastiche passes, and so do words that hold a mark (%s)" % [EnvChecks.names(pastiche)],
			EnvChecks.names(pastiche).is_empty())
	# No people.
	var crowd := _doc([], {"parts": [{"name": "Crowd", "object": "box"}, {"name": "Usher_1", "object": "box"},
			{"name": "Popcorn", "object": "mannequin"}, {"name": "Stand", "object": "box"}]})
	var p: Array = EnvChecks.no_people(crowd)
	_check("no people: a crowd, an usher and a mannequin (%s)" % [p], p.size() == 3)
	_check("no people: the cinema and the Void have none",
			EnvChecks.no_people(cinema_doc).is_empty())
	print("test_env_checks: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)
