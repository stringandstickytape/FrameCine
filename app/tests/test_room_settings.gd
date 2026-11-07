extends SceneTree

## Every room's own settings (docs/environments.md, "Room settings"; scripts/env/room_settings.gd) in the real main
## scene: the declarations (common and the document's), the Room tab's "This room" built from them (a toggle, a
## slider, a row of choices, each with its description; Back to defaults), storage as [room:<id>] <name> with only
## changes kept, the bindings applied live (the cinema's house lights, the Void's ripple), the common ones reaching
## what they drive (dim during the film, the pre-show), and the assistant's room_settings / room_setting commands.
## godot --headless --xr-mode off --path app --script res://tests/test_room_settings.gd

const DevCommands := preload("res://scripts/dev/dev_commands.gd")
const CommandHost := preload("res://scripts/dev/command_host.gd")
const W := preload("res://ui/pane_widgets.gd")

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


func _names() -> Array:
	return main.features.room_settings.declarations().map(func(d: Dictionary) -> String: return d["name"])


func _run() -> void:
	await _frames(5)
	CommandHost.ensure(self)
	var rs: Node = main.features.room_settings
	main.set_environment("cinema")
	await _frames(3)
	_check("the cinema: dim, room sound, the pre-show and its house lights (%s)" % [_names()],
			_names() == ["dim", "ambience_db", "ritual", "house_level"])
	main.set_environment("void")
	await _frames(3)
	_check("the Void: dim, room sound, its ripple (%s)" % [_names()], _names() == ["dim", "ambience_db", "ripple"])
	main.set_environment("home_theatre")
	await _frames(3)
	_check("a room without a document: the common ones that apply (%s)" % [_names()],
			_names() == ["dim", "ambience_db", "ritual"])
	_check("each has a label and a description", rs.declarations().all(func(d: Dictionary) -> bool:
			return str(d["label"]) != "" and str(d["description"]) != ""))

	# The menu, built from the declarations.
	main.set_environment("cinema")
	await _frames(3)
	var tab: Node = main.ui.ui.room
	tab.sync()
	var box: VBoxContainer = tab._this_room
	var controls: Dictionary = tab._this_room_controls
	_check("This room: a control per setting (%s)" % [controls.keys()], controls.keys() == ["dim", "ambience_db",
			"ritual", "house_level"])
	_check("a toggle for a bool", controls["dim"] is Button and (controls["dim"] as Button).toggle_mode)
	_check("a slider for a range", (controls["house_level"] as Control).has_meta("slider"))
	_check("the descriptions under them", box.find_children("*", "Label", true, false).any(func(l: Label) -> bool:
			return l.text == "How bright the house lamps stay once the film has started."))
	_check("labels translate themselves (keys, not content)", (controls["dim"] as Button).auto_translate_mode
			!= Node.AUTO_TRANSLATE_MODE_DISABLED)
	# The user's change through the control.
	(controls["dim"] as Button).button_pressed = false
	await _frames(2)
	_check("the toggle sets it (%s)" % rs.value("dim"), rs.value("dim") == false)
	_check("stored as [room:cinema] dim", main.settings.get_value("room:cinema", "dim", null) == false)
	_check("dim during the film off: light follows playback holds the light", is_equal_approx(
			main.features.light_follow.wanted(), 1.0))
	W.slider_of(controls["house_level"]).value = 0.5
	await _frames(2)
	_check("the slider sets the house lights (%.2f)" % rs.value("house_level"), is_equal_approx(rs.value("house_level"), 0.5))
	_check("the room has it (%s)" % main.env.host.setting("house_level"),
			is_equal_approx(float(main.env.host.setting("house_level")), 0.5))
	rs.set_value("house_level", 0.2)
	_check("back to its default: the key erased", not main.settings.has_value("room:cinema", "house_level"))
	_check("refused: a value of the wrong kind (%s)" % rs.set_value("dim", 3), rs.set_value("dim", 3) != "")
	_check("refused: a setting the room doesn't have", rs.set_value("ripple", 0.5) != "")
	rs.set_value("house_level", 7.0)
	_check("a range clamped (%.2f)" % rs.value("house_level"), is_equal_approx(rs.value("house_level"), 1.0))
	# The pre-show off: no curtains in the cinema.
	rs.set_value("ritual", false)
	_check("Pre-show off: the cinema's curtains go", not main.features.preshow.available()
			and main.env.has_curtains == false)
	rs.set_value("ritual", true)
	_check("on again", main.features.preshow.available())
	# Kept per room: the cinema's change is not the Void's.
	rs.set_value("ambience_db", -6.0)
	main.set_environment("void")
	await _frames(3)
	_check("per room: the Void's room sound its own (%s)" % rs.value("ambience_db"), is_equal_approx(
			rs.value("ambience_db"), 0.0))
	rs.set_value("ripple", 0.2)
	_check("the Void's ripple bound live (%.2f)" % main.env.host.param("mirror_floor.ripple"),
			is_equal_approx(float(main.env.host.param("mirror_floor.ripple")), 0.2))
	main.set_environment("cinema")
	await _frames(3)
	_check("back in the cinema: its own kept (%s, %s)" % [rs.value("ambience_db"), rs.value("dim")],
			is_equal_approx(rs.value("ambience_db"), -6.0) and rs.value("dim") == false)
	tab.sync()
	_check("the menu shows them", not (tab._this_room_controls["dim"] as Button).button_pressed)
	# Back to defaults.
	var back: Button = null
	for b: Button in tab._this_room_box.find_children("*", "Button", true, false):
		if b.text == "Back to defaults":
			back = b
	_check("a Back to defaults button", back != null)
	back.pressed.emit()
	await _frames(2)
	_check("back to defaults: every value and every key", rs.value("dim") == true and is_equal_approx(
			rs.value("ambience_db"), 0.0) and main.settings.get_keys("room:cinema").is_empty())

	# The assistant: room_settings' this_room, room_setting.
	var r := await DevCommands.execute("room_settings", {}, true)
	var this_room: Array = r["result"]["this_room"] if r["ok"] else []
	_check("room_settings: this_room, each with a JSON Schema (%d)" % this_room.size(), this_room.size() == 4
			and this_room.all(func(d: Dictionary) -> bool: return (d["schema"] as Dictionary).has("type")))
	var hl: Dictionary = this_room.filter(func(d: Dictionary) -> bool: return d["name"] == "house_level")[0]
	_check("its schema from the declaration (%s)" % [hl["schema"]], hl["schema"]["type"] == "number"
			and float(hl["schema"]["maximum"]) == 1.0 and is_equal_approx(float(hl["value"]), 0.2))
	r = await DevCommands.execute("room_setting", {"name": "house_level", "value": 0.4}, true)
	_check("room_setting: set (%s)" % r.get("error", ""), r["ok"] and is_equal_approx(rs.value("house_level"), 0.4))
	(r["call"] as DevCommands.Call).undo.call()
	_check("room_setting: undo", is_equal_approx(rs.value("house_level"), 0.2))
	r = await DevCommands.execute("room_setting", {"name": "house_level", "value": "bright"}, true)
	_check("room_setting: a bad value refused (%s)" % r.get("error", ""), not r["ok"])
	r = await DevCommands.execute("room_setting", {"name": "dim", "value": false}, true)
	r = await DevCommands.execute("room_setting", {"reset": true}, true)
	_check("room_setting: reset", r["ok"] and rs.value("dim") == true)
	_check("room_setting: tagged for the assistant at the room level",
			DevCommands.get_spec("room_setting").get("assistant") == "room")
	main.queue_free()
	await _frames(2)
	print("test_room_settings: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)
