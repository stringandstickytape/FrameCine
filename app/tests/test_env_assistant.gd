extends SceneTree

## An assistant builds a room from systems (docs/assistant.md, "Rooms from systems"): room_systems lists the registry
## and the vocabulary; new_room with a version 4 document builds its systems into the room (a small auditorium on the
## Void), kept as version 4 with its settings; a change keeps the sections; a bad system is refused with its path; the
## room's own setting shows in This room and reaches its system.
## godot --headless --xr-mode off --path app --script res://tests/test_env_assistant.gd

const AssistantCommands := preload("res://scripts/assistant/assistant_commands.gd")
const RoomEditor := preload("res://scripts/assistant/room_editor.gd")
const AssistantRoom := preload("res://scripts/assistant/assistant_room.gd")
const NAME := "Test env systems room"

var _failures := 0
var _checks := 0
var main: Node3D


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _cleanup() -> void:
	for p: String in [AssistantRoom.json_path(NAME)]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	var d := AssistantRoom.files_dir(NAME)
	if DirAccess.dir_exists_absolute(d):
		for f in DirAccess.get_files_at(d):
			DirAccess.remove_absolute(d.path_join(f))
		DirAccess.remove_absolute(d)


func _run() -> void:
	await _frames(5)
	_cleanup()
	var editor: Node = RoomEditor.new()
	root.add_child(editor)
	var commands := AssistantCommands.new()
	commands.allow_room = func() -> bool: return true
	commands.room = editor
	editor.perf_after_change = false
	main.set_environment("void")
	await _frames(3)
	var r: Dictionary = await commands.run("room_systems", {})
	var names: Array = (r.get("result", {}).get("systems", []) as Array).map(func(s: Dictionary) -> String:
			return s["name"])
	_check("room_systems: the registry (%s)" % [names], r.get("ok") == true and names.has("auditorium")
			and int(r["result"]["schema"]) == 4 and (r["result"]["channels"] as Dictionary).has("film.bass"))
	var d: Dictionary = AssistantCommands.describe()
	_check("describe: the systems' schema", int(d.get("room_systems_schema", 0)) == 4 and (d["commands"] as Array).any(
			func(c: Dictionary) -> bool: return c["name"] == "room_systems"))
	var doc := {"schema": 4, "name": NAME, "base": "void",
		"systems": [{"system": "light"}, {"system": "auditorium", "id": "hall", "params": {"rows_front": 2,
				"rows_back": 1, "seats_per_row": 7, "proscenium": "none", "room_min": [-6, -1, -10],
				"room_max": [6, 6, 4], "block_x": 4.5, "panel_from": -6.0, "panel_to": 3.0, "clouds": [-6.0]}}],
		"settings": [{"name": "lamps", "type": "range", "min": 0.0, "max": 1.0, "default": 1.0, "label": "Lamps",
				"description": "How bright the lamps are."}]}
	doc["systems"][0]["params"] = {"house_lamps": {"bind": "setting.lamps", "range": [0.0, 1.0]}}
	r = await commands.run("new_room", {"room": doc})
	await _frames(5)
	_check("new_room with a version 4 document (%s)" % [r.get("errors", r.get("error", ""))], r.get("ok") == true)
	var env: Node = main.env
	var host: Node = env.get_node_or_null("Systems")
	_check("its systems built into the room", host != null and host.system("hall") != null
			and env.get_node_or_null("Floor") != null and env.get_node_or_null("Seats") != null)
	var kept := FileAccess.get_file_as_string(AssistantRoom.json_path(NAME))
	var j: Variant = JSON.parse_string(kept)
	_check("kept as version 4, its sections with it", j is Dictionary and int(j.get("schema", 0)) == 4
			and (j as Dictionary).has("systems") and (j as Dictionary).has("settings"))
	r = await commands.run("room_apply", {"room": {"schema": 4, "parts": [{"name": "Lamp", "object": "box",
			"position": [0, 0.5, -3], "scale": 0.3}]}})
	await _frames(5)
	var j2: Variant = JSON.parse_string(FileAccess.get_file_as_string(AssistantRoom.json_path(
			str(main.env.doc.get("name", NAME)))))
	_check("a change keeps the systems (%s)" % [r.get("errors", r.get("error", ""))], r.get("ok") == true
			and main.env.get_node_or_null("Systems") != null and j2 is Dictionary and (j2 as Dictionary).has("systems"))
	var rs: Node = main.features.room_settings
	_check("its own setting in This room (%s)" % [rs.declarations().map(func(x: Dictionary) -> String: return x["name"])],
			rs.declarations().any(func(x: Dictionary) -> bool: return x["name"] == "lamps"))
	rs.set_value("lamps", 0.25)
	var h: Node = main.env.get_node("Systems")
	_check("it reaches its system (%.2f)" % float(h.param("light.house_lamps")),
			is_equal_approx(float(h.param("light.house_lamps")), 0.25))
	r = await commands.run("room_apply", {"room": {"schema": 4, "systems": [{"system": "crowd"}]}})
	_check("an unknown system refused with its path", r.get("ok") == false and (r.get("errors", []) as Array).any(
			func(e: Dictionary) -> bool: return e["path"] == "$.systems[0].system"))
	main.set_environment("void")
	await _frames(3)
	_cleanup()
	main.queue_free()
	await _frames(2)
	print("test_env_assistant: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)
