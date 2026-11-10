extends SceneTree

## The Room tab, System tab, eye gaze and director commands for the assistant
## (docs/dev/assistant-coverage/room-system.md), through DevCommands.execute against the real main scene: every
## command of the area is tagged with a consumer level and describes every parameter; each change shows its effect,
## reads back the same, syncs the tab and can be undone; no tagged command can reach the assistant's own permission
## switches.
## godot --headless --xr-mode off --path app --script res://tests/test_assistant_coverage_system.gd

const DevCommands := preload("res://scripts/dev/dev_commands.gd")
const AssistantCommands := preload("res://scripts/assistant/assistant_commands.gd")
const CommandHost := preload("res://scripts/dev/command_host.gd")

const CONSUMER_LEVELS := ["read", "card", "control", "room", "settings", "files", "apps"]
## The commands of this area and the consumer level each must have.
const AREA := {
	"room_settings": "read", "set_environment": "room", "use_picture_as_room": "room", "seat": "control",
	"floor_reflection": "room", "bias_light": "room", "react_to_film": "room", "projector_beam": "room",
	"time_of_day": "room", "room_light": "room", "dim_while_playing": "room", "curtains": "room", "up_next": "room",
	"intermission": "room", "crossfade": "room", "sleep_timer": "control", "room_setting": "room",
	"time_travel": "room",
	"system_settings": "read", "panel_layout": "settings", "reset_panel_layout": "settings",
	"accessibility": "settings", "foveation": "settings", "controller_looks": "read", "controller_look": "settings",
	"haptics": "settings", "jog_wheel": "settings", "seek_bar_pictures": "settings",
	"zoom_lens": "settings", "open_test_card": "control", "lab_cards": "read", "bandwidth_test": "control",
	"hwvideo_status": "read", "gaze_status": "read", "gaze_calibrate": "control", "gaze_pip": "control",
	"find_line": "read", "jump_to_line": "control", "script_lines": "read",
	"pc_status": "read", "pc_list": "read", "pc_open": "control", "pc_close": "control", "pc_screen": "control",
	"pc_pane_size": "control",
}
## Words that would mark a command reaching the assistant's own permissions or its pairing.
const FORBIDDEN_WORDS := ["allow", "pair", "forget", "permission", "token"]

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
	CommandHost.ensure(self)
	await _frames(2)
	var allow_before := _assistant_switches()

	_test_specs()
	await _test_room()
	await _test_seat()
	await _test_effects()
	await _test_showing()
	await _test_sleep()
	await _test_time_travel()
	await _test_system()
	await _test_rest()

	_check("the assistant's switches unchanged by every command (%s)" % [_assistant_switches()],
			_assistant_switches() == allow_before)
	main.queue_free()
	await _frames(2)
	print("test_assistant_coverage_system: %d checks, %s" % [_checks,
			"all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


# --- The registry -------------------------------------------------------------------------------------------------

func _test_specs() -> void:
	for c: String in AREA:
		if not DevCommands.has_command(c):
			_check("%s is registered" % c, false)
			continue
		var spec := DevCommands.get_spec(c)
		_check("%s: assistant %s (got %s)" % [c, AREA[c], spec.get("assistant")], spec.get("assistant") == AREA[c])
		_check("%s: described" % c, str(spec.get("description", "")).length() > 10)
		_check("%s: not a code-level command" % c, spec.get("level") != "code")
		for p: Dictionary in spec["params"]:
			_check("%s: %s described" % [c, p["name"]], str(p.get("description", "")).strip_edges() != "")
	# Nothing tagged may reach the assistant's own switches, its pairing, the raw settings or code.
	for c: String in DevCommands.command_names():
		var spec := DevCommands.get_spec(c)
		if not spec.has("assistant"):
			continue
		_check("%s: a consumer level (%s)" % [c, spec["assistant"]], spec["assistant"] in CONSUMER_LEVELS)
		_check("%s: not code" % c, spec.get("level") != "code")
		var words := c.to_lower()
		for p: Dictionary in spec["params"]:
			words += " " + str(p["name"]).to_lower()
		for w: String in FORBIDDEN_WORDS:
			_check("%s: nothing about %s" % [c, w], not w in words)
	for c: String in ["set", "get", "permissions", "call", "set_prop", "run", "reload", "benchmark", "tour"]:
		_check("%s is not reachable by the assistant" % c, not DevCommands.has_command(c)
				or not DevCommands.get_spec(c).has("assistant"))


# --- The room ------------------------------------------------------------------------------------------------------

func _test_room() -> void:
	main.set_environment("void")
	await _frames(2)
	var r := await _run_cmd("set_environment", {"id": "home_theatre"})
	_check("set_environment: the room changes", r["ok"] and main.env_id == "home_theatre"
			and r["result"]["environment"] == "home_theatre")
	_check("set_environment: room_settings says so", (await _read("room_settings"))["environment"] == "home_theatre")
	var room_tab: Node = _tab("room")
	if room_tab != null:
		var row := -1
		for i in room_tab._env_ids.size():
			if room_tab._env_ids[i] == "home_theatre":
				row = i
		_check("set_environment: the tab marks the room", row >= 0
				and (room_tab._env_rows[row] as Button).button_pressed)
	(r["call"] as DevCommands.Call).undo.call()
	await _frames(2)
	_check("set_environment: undo", main.env_id == "void")
	r = await _run_cmd("set_environment", {"id": "no_such_room"})
	_check("set_environment: an unknown room refused", not r["ok"] and "room_settings" in str(r["error"]))
	r = await _run_cmd("use_picture_as_room", {})
	_check("use_picture_as_room: refused without a picture", not r["ok"] and main.env_id == "void")

	r = await _run_cmd("room_light", {"level": 0.6})
	_check("room_light: applied", r["ok"] and is_equal_approx(main.room_light, 0.6)
			and is_equal_approx(float((await _read("room_settings"))["room_light"]), 0.6))
	(r["call"] as DevCommands.Call).undo.call()
	_check("room_light: undo", is_equal_approx(main.room_light, 1.0))
	r = await _run_cmd("room_light", {"level": 5.0})
	_check("room_light: kept to 2", is_equal_approx(main.room_light, 2.0))
	(r["call"] as DevCommands.Call).undo.call()

	r = await _run_cmd("time_of_day", {"mode": "dusk"})
	_check("time_of_day: refused in a room without a sky", not r["ok"])
	main.set_environment("drive_in")
	await _frames(2)
	var tod: Node = main.features.time_of_day
	var old_mode := str(tod.mode)
	r = await _run_cmd("time_of_day", {"mode": "clock", "latitude": 12.0})
	_check("time_of_day: now at 12 degrees", r["ok"] and tod.mode == "clock" and is_equal_approx(tod.latitude, 12.0))
	var st := await _read("room_settings")
	_check("time_of_day: read back", st["time_of_day"]["mode"] == "clock" and st["time_of_day"]["available"])
	r = await _run_cmd("time_of_day", {"mode": "noon"})
	_check("time_of_day: a mode outside the list refused", not r["ok"])
	r = await _run_cmd("time_of_day", {"mode": old_mode})
	main.set_environment("void")
	await _frames(2)


func _test_seat() -> void:
	# A room with seats.
	var with_seats := ""
	for e: Array in main.get_environment_list():
		if not (str(e[0]) in ["cinema", "home_theatre", "drive_in", "planetarium", "dome"]):
			continue
		main.set_environment(str(e[0]))
		await _frames(2)
		if main.features.seat.names().size() >= 2:
			with_seats = str(e[0])
			break
	if with_seats == "":
		_check("a built-in room with two seats", false)
		return
	var seat: Node = main.features.seat
	var names: Array = seat.names()
	var r := await _run_cmd("seat", {"to": names[1]})
	_check("seat: by name (%s)" % names[1], r["ok"] and int(seat.seat) == 1 and r["result"]["seat"] == names[1])
	_check("seat: room_settings says so", (await _read("room_settings"))["seat"]["index"] == 1)
	var undo: Callable = (r["call"] as DevCommands.Call).undo
	r = await _run_cmd("seat", {"to": "next"})
	_check("seat: next", r["ok"] and int(seat.seat) == 2 % names.size())
	r = await _run_cmd("seat", {"to": "own"})
	_check("seat: the room's own spot", r["ok"] and int(seat.seat) == -1)
	r = await _run_cmd("seat", {"to": "the roof"})
	_check("seat: an unknown seat refused with the names", not r["ok"] and names[0] in str(r["error"]))
	undo.call()
	main.set_environment("void")
	await _frames(2)
	r = await _run_cmd("seat", {"to": "next"})
	_check("seat: refused in a room without seats (%s)" % r.get("error"), not r["ok"]
			or main.features.seat.names().size() > 0)


func _test_effects() -> void:
	var f: Node = main.features
	# The Void's reflection is on by default (its mirror floor, docs/environments.md): undo puts back what was.
	var was_on: bool = f.reflection.enabled
	var was_strength: float = f.reflection.strength
	var r := await _run_cmd("floor_reflection", {"on": true, "strength": 0.4})
	_check("floor_reflection: on at 40 %", r["ok"] and f.reflection.enabled and is_equal_approx(f.reflection.strength, 0.4))
	_check("floor_reflection: read back", (await _read("room_settings"))["reflection"]["on"] == true)
	(r["call"] as DevCommands.Call).undo.call()
	_check("floor_reflection: undo", f.reflection.enabled == was_on and is_equal_approx(f.reflection.strength,
			was_strength))
	r = await _run_cmd("floor_reflection", {})
	_check("floor_reflection: nothing to change refused", not r["ok"])

	# The bias light is on by default: start from off, so the undo has something to put back.
	f.bias.set_enabled(false)
	r = await _run_cmd("bias_light", {"on": true, "strength": 0.5})
	_check("bias_light: on at 50 %", r["ok"] and f.bias.enabled and is_equal_approx(f.bias.strength, 0.5))
	var room_tab: Node = _tab("room")
	if room_tab != null:
		_check("bias_light: the tab's toggle follows", (room_tab._bias as Button).button_pressed)
	_check("bias_light: read back", (await _read("room_settings"))["bias_light"]["on"] == true)
	(r["call"] as DevCommands.Call).undo.call()
	_check("bias_light: undo", not f.bias.enabled)
	if room_tab != null:
		_check("bias_light: the tab follows the undo", not (room_tab._bias as Button).button_pressed)

	r = await _run_cmd("react_to_film", {"on": true, "strength": 0.8})
	_check("react_to_film: on at 80 %", r["ok"] and f.react.enabled and is_equal_approx(f.react.strength, 0.8))
	(r["call"] as DevCommands.Call).undo.call()
	_check("react_to_film: undo", not f.react.enabled)

	var beam := bool(f.projector.beam)
	r = await _run_cmd("projector_beam", {"on": not beam})
	_check("projector_beam: switched", r["ok"] and f.projector.beam == not beam
			and (await _read("room_settings"))["projector_beam"] == not beam)
	(r["call"] as DevCommands.Call).undo.call()
	_check("projector_beam: undo", f.projector.beam == beam)

	r = await _run_cmd("dim_while_playing", {"on": true, "level": 0.2})
	_check("dim_while_playing: on to 20 %", r["ok"] and f.light_follow.enabled
			and is_equal_approx(f.light_follow.play_level, 0.2))
	_check("dim_while_playing: read back", is_equal_approx(
			float((await _read("room_settings"))["dim_while_playing"]["level"]), 0.2))
	(r["call"] as DevCommands.Call).undo.call()


func _test_showing() -> void:
	var f: Node = main.features
	var curtains := bool(f.preshow.enabled)
	var r := await _run_cmd("curtains", {"on": not curtains})
	_check("curtains: switched", r["ok"] and f.preshow.enabled == not curtains
			and (await _read("room_settings"))["showing"]["curtains"] == not curtains)
	(r["call"] as DevCommands.Call).undo.call()
	_check("curtains: undo", f.preshow.enabled == curtains)

	r = await _run_cmd("up_next", {"on": true, "seconds": 20.0})
	_check("up_next: 20 s", r["ok"] and f.up_next.enabled and is_equal_approx(f.up_next.seconds, 20.0)
			and is_equal_approx(float((await _read("room_settings"))["showing"]["up_next_seconds"]), 20.0))
	(r["call"] as DevCommands.Call).undo.call()

	r = await _run_cmd("intermission", {"on": true, "minutes": 5.0})
	_check("intermission: 5 min", r["ok"] and f.intermission.enabled and is_equal_approx(f.intermission.minutes, 5.0))
	(r["call"] as DevCommands.Call).undo.call()
	_check("intermission: undo", not f.intermission.enabled)

	r = await _run_cmd("crossfade", {"music_seconds": 4.0, "video_seconds": 2.0})
	_check("crossfade: 4 s and 2 s", r["ok"] and is_equal_approx(f.crossfade.music_seconds, 4.0)
			and is_equal_approx(f.crossfade.video_seconds, 2.0))
	_check("crossfade: read back", is_equal_approx(
			float((await _read("room_settings"))["showing"]["crossfade_video_seconds"]), 2.0))
	(r["call"] as DevCommands.Call).undo.call()
	_check("crossfade: undo", is_zero_approx(f.crossfade.music_seconds) and is_zero_approx(f.crossfade.video_seconds))


func _test_sleep() -> void:
	var sleep: Node = main.features.sleep
	var r := await _run_cmd("sleep_timer", {"set": "30"})
	_check("sleep_timer: 30 min", r["ok"] and sleep.active and not sleep.end_of_file
			and absf(float(sleep.remaining()) - 1800.0) < 2.0)
	_check("sleep_timer: read back", (await _read("room_settings"))["sleep"]["active"] == true)
	var room_tab: Node = _tab("room")
	if room_tab != null:
		_check("sleep_timer: the tab shows 30 min", (room_tab._sleep_status as Label).text.contains("30"))
	r = await _run_cmd("sleep_timer", {"set": "end_of_file"})
	_check("sleep_timer: end of file", r["ok"] and sleep.active and sleep.end_of_file)
	(r["call"] as DevCommands.Call).undo.call()
	_check("sleep_timer: undo back to minutes", sleep.active and not sleep.end_of_file)
	r = await _run_cmd("sleep_timer", {"set": "off"})
	_check("sleep_timer: off", r["ok"] and not sleep.active)
	r = await _run_cmd("sleep_timer", {"then": "close"})
	_check("sleep_timer: then close", r["ok"] and sleep.then == "close" and (r["result"] as Dictionary)["then"] == "close")
	if room_tab != null:
		var picked := -1
		for i in (room_tab._sleep_then as Node).get_child_count():
			if ((room_tab._sleep_then as Node).get_child(i) as Button).button_pressed:
				picked = i
		_check("sleep_timer: the tab's Then follows (%d)" % picked, picked == 1)
	_check("sleep_timer: then back to pause", (await _run_cmd("sleep_timer", {"then": "pause"}))["ok"]
			and sleep.then == "pause")
	r = await _run_cmd("sleep_timer", {"set": "45"})
	_check("sleep_timer: a choice outside the list refused", not r["ok"])


# --- The System tab ---------------------------------------------------------------------------------------------------

func _test_system() -> void:
	var f: Node = main.features
	if main.ui != null and main.ui.has_method("layout_value"):
		var hold := float(main.ui.layout_value("recentre_hold"))
		var r := await _run_cmd("panel_layout", {"recentre_hold": 1.2})
		_check("panel_layout: applied", r["ok"] and is_equal_approx(float(main.ui.layout_value("recentre_hold")), 1.2)
				and is_equal_approx(main.ui.menu.hold, 1.2))
		var st := await _read("system_settings")
		_check("panel_layout: read back", is_equal_approx(float(st["panel"]["recentre_hold"]), 1.2)
				and not st["panel"].has("size") and not st["panel"].has("follow_head"))
		var gone := await _run_cmd("panel_layout", {"size": 1.5})
		_check("panel_layout: no size any more (the menu is the tablet's)", not gone["ok"])
		(r["call"] as DevCommands.Call).undo.call()
		_check("panel_layout: undo", is_equal_approx(float(main.ui.layout_value("recentre_hold")), hold))
		await _run_cmd("panel_layout", {"recentre_hold": 1.4})
		r = await _run_cmd("reset_panel_layout", {})
		_check("reset_panel_layout: back to the defaults", r["ok"]
				and is_equal_approx(float(main.ui.layout_value("recentre_hold")),
				float(main.ui.LAYOUT_DEFAULTS["recentre_hold"])))
		(r["call"] as DevCommands.Call).undo.call()
		_check("reset_panel_layout: undo", is_equal_approx(float(main.ui.layout_value("recentre_hold")), 1.4))
		main.ui.reset_layout()
	else:
		_check("the main scene has its menu layer", false)

	var access: Node = f.access
	var r := await _run_cmd("accessibility", {"larger_panel": 1.4, "eye": "right", "one_eye_3d": true,
			"subtitles_always": true})
	_check("accessibility: applied", r["ok"] and is_equal_approx(float(access.get_value("ui_scale")), 1.4)
			and int(access.get_value("monocular_eye")) == 1 and bool(access.get_value("monocular"))
			and bool(access.get_value("subtitles_always")))
	var st := await _read("system_settings")
	_check("accessibility: read back", st["accessibility"]["eye"] == "right" and st["accessibility"]["one_eye_3d"])
	(r["call"] as DevCommands.Call).undo.call()
	_check("accessibility: undo", is_equal_approx(float(access.get_value("ui_scale")), 1.0)
			and not bool(access.get_value("monocular")) and not bool(access.get_value("subtitles_always")))
	r = await _run_cmd("accessibility", {"eye": "middle"})
	_check("accessibility: an eye outside the list refused", not r["ok"])

	r = await _run_cmd("haptics", {"on": false, "strength": 0.3})
	_check("haptics: off, 30 %", r["ok"] and not f.haptics.enabled and is_equal_approx(f.haptics.strength, 0.3)
			and (await _read("system_settings"))["haptics"]["on"] == false)
	(r["call"] as DevCommands.Call).undo.call()
	_check("haptics: undo", f.haptics.enabled and is_equal_approx(f.haptics.strength, 1.0))

	r = await _run_cmd("jog_wheel", {"seconds_per_turn": 120.0})
	_check("jog_wheel: 2 min a turn", r["ok"] and is_equal_approx(f.jog.seconds_per_turn, 120.0))
	(r["call"] as DevCommands.Call).undo.call()

	r = await _run_cmd("seek_bar_pictures", {"on": true})
	_check("seek_bar_pictures: on", r["ok"] and f.thumbs.enabled and (await _read("system_settings"))["seek_bar_pictures"])
	(r["call"] as DevCommands.Call).undo.call()
	_check("seek_bar_pictures: undo", not f.thumbs.enabled)

	r = await _run_cmd("zoom_lens", {"magnification": 5.0})
	_check("zoom_lens: 5x", r["ok"] and is_equal_approx(f.zoom_lens.magnification, 5.0))
	(r["call"] as DevCommands.Call).undo.call()


func _test_rest() -> void:
	var cards: Array = (await _run_cmd("lab_cards", {}))["result"]
	_check("lab_cards: listed", not cards.is_empty())
	if not cards.is_empty():
		var card := str(cards[0]["path"]).get_slice("://", 1)
		var r := await _run_cmd("open_test_card", {"card": card})
		await _frames(5)
		_check("open_test_card: %s opens" % card, r["ok"] and main.current_path == "lab://" + card)
	var r := await _run_cmd("open_test_card", {"card": "no_such_card"})
	_check("open_test_card: an unknown card refused", not r["ok"])
	r = await _run_cmd("bandwidth_test", {"path": "https://example.com/film.mkv"})
	_check("bandwidth_test: a web address refused", not r["ok"])
	r = await _run_cmd("bandwidth_test", {"path": "smb://unsaved-host/share/a.mkv"})
	_check("bandwidth_test: a host not saved refused", not r["ok"] and "saved" in str(r["error"]))

	r = await _run_cmd("gaze_pip", {"on": true})
	_check("gaze_pip: on", r["ok"] and r["result"]["pip"] == true
			and (await _run_cmd("gaze_status", {}))["result"]["pip"] == true)
	(r["call"] as DevCommands.Call).undo.call()
	_check("gaze_pip: undo", (await _run_cmd("gaze_status", {}))["result"]["pip"] == false)
	r = await _run_cmd("gaze_calibrate", {})
	_check("gaze_calibrate: refused without eye gaze", not r["ok"])
	r = await _run_cmd("hwvideo_status", {})
	_check("hwvideo_status: answers with the 10-bit path (%s)" % [r.get("result")], r["ok"] and r["result"] is Dictionary
			and r["result"].get("path") in ["p010", "q10c", "software", "unknown"] and r["result"].has("hw_vp9"))
	var gate := AssistantCommands.new()
	r = await DevCommands.execute("hwvideo_status", {}, true, gate)
	_check("hwvideo_status: an assistant reads it, and nothing in it installs or asks for a password",
			r["ok"] and not JSON.stringify(r["result"]).contains("password")
			and not JSON.stringify(DevCommands.get_spec("hwvideo_status")).to_lower().contains("sudo"))
	_check("hwsetup_status is gone", not DevCommands.has_command("hwsetup_status"))


# --- Helpers ------------------------------------------------------------------------------------------------------

func _run_cmd(cmd: String, args: Dictionary) -> Dictionary:
	return await DevCommands.execute(cmd, args, true)


func _read(cmd: String) -> Dictionary:
	var r := await _run_cmd(cmd, {})
	return r["result"] if r["ok"] else {}


## A tab of the panel (pane_ui.gd's room or system), or null without the menu layer.
func _tab(which: String) -> Node:
	var layer: Node = main.ui
	var pane: Node = layer.get("ui") if layer != null else null
	return pane.get(which) if pane != null else null


func _assistant_switches() -> Array:
	# The whole [assistant] section: today's switches and any added later.
	var cfg: ConfigFile = main.settings._cfg
	var out: Array = []
	if cfg.has_section("assistant"):
		for key in cfg.get_section_keys("assistant"):
			out.append([key, cfg.get_value("assistant", key)])
	return out


## Time travel: on moves a room that isn't an era to the first; advance goes to the next; off stays; undo puts it back.
func _test_time_travel() -> void:
	var tt: Node = main.features.time_travel
	var before: String = main.env_id
	main.set_environment("void")
	await _frames(2)
	var eras: Array = tt.eras()
	_check("time travel: the eras in order (%s)" % [eras], eras.size() >= 7 and eras[0] == "tv_1930"
			and eras.find("tv_1953") < eras.find("tv_2005") and not ("pillow_fort_1993" in eras))
	var r: Dictionary = await _run_cmd("time_travel", {"on": true, "minutes": 5})
	_check("time travel on: the first era at once (%s)" % main.env_id, r["ok"] and tt.active and main.env_id == eras[0]
			and int(tt.minutes) == 5 and is_equal_approx(float(tt.remaining()), 300.0))
	_check("and the read says so", bool((await _read("room_settings"))["time_travel"]["active"]))
	r = await _run_cmd("time_travel", {"on": true, "advance": true})
	_check("advance: the next era (%s)" % main.env_id, r["ok"] and main.env_id == eras[1] and tt.active)
	main.set_environment("cinema")
	await _frames(2)
	_check("the viewer picks a room that isn't an era: time travel stops", not tt.active)
	r = await _run_cmd("time_travel", {"on": true, "minutes": 7})
	_check("a choice it doesn't have is refused", not r["ok"])
	r = await _run_cmd("time_travel", {"on": false})
	_check("off", r["ok"] and not tt.active)
	main.set_environment(before)
	await _frames(2)


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL " + what)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
