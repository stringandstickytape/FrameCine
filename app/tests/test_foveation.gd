extends SceneTree

## Foveation (docs/decisions.md D22; main.gd's [view] foveation and foveation_sharp_panel) in the real main scene: the
## settings' round trip through the settings file, the System tab's Rendering row (and its state when the build starts
## without foveation), the `foveation` command through DevCommands.execute, and the level _update_foveation() sets for
## every level, toggle, panel and pane. Without XR a stand-in takes the OpenXR interface's place. Settings are
## read-only.
## godot --headless --xr-mode off --path app --script res://tests/test_foveation.gd

const DevCommands := preload("res://scripts/dev/dev_commands.gd")
const CommandHost := preload("res://scripts/dev/command_host.gd")
const AppSettings := preload("res://scripts/app_settings.gd")
const Main := preload("res://scripts/main.gd")
const SystemTab := preload("res://ui/system_tab.gd")

const PROJECT_LEVEL := "xr/openxr/foveation_level"
const TMP_PATH := "user://test_foveation.cfg"


## Stands in for OpenXRInterface: its run-time foveation level, and how often it was set.
class FakeXR:
	extends RefCounted
	var sets := 0
	var foveation_level := 0:
		set(v):
			foveation_level = v
			sets += 1


var _failures := 0
var _checks := 0
var main: Node3D
var fake := FakeXR.new()


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
	_check("defaults: low, sharp while the panel shows", main.foveation == "low" and main.foveation_sharp_panel)
	_check("the project starts with a foveated swapchain", main.foveation_available())
	_check("no XR: nothing to set foveation on", main.foveation_xr == null)
	main.foveation_xr = fake

	_test_choice()
	_test_update()
	_test_round_trip()
	await _test_row()
	await _test_command()

	main.queue_free()
	await _frames(2)
	print("test_foveation: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


## The rule alone: the level, but 0 while the panel or the pane shows and the toggle is on.
func _test_choice() -> void:
	for level in 4:
		for sharp: bool in [false, true]:
			for panel: bool in [false, true]:
				for pane: bool in [false, true]:
					var want := 0 if sharp and (panel or pane) else level
					var got := Main.foveation_choice(level, sharp, panel, pane)
					_check("choice: level %d, sharp %s, panel %s, pane %s -> %d (got %d)" % [level, sharp, panel, pane,
							want, got], got == want)
	_check("choice: a level past High is High", Main.foveation_choice(7, false, false, false) == 3)


## Through main: the saved level and toggle with the panel shown or not reach the interface; the pane is closed here
## (no agent runs in a test), so its half of the rule is _test_choice()'s.
func _test_update() -> void:
	var menu_was: bool = main.menu_shown
	_check("no agent pane in a test", not main.local_agents.pane_shown())
	for i in Main.FOVEATION_LEVELS.size():
		for sharp: bool in [false, true]:
			for panel: bool in [false, true]:
				main.set_foveation(Main.FOVEATION_LEVELS[i])
				main.set_foveation_sharp_panel(sharp)
				main.set_menu_shown(panel)
				main._update_foveation()
				var want := 0 if sharp and panel else i
				_check("update: %s, sharp %s, panel %s -> %d (got %d)" % [Main.FOVEATION_LEVELS[i], sharp, panel, want,
						fake.foveation_level], fake.foveation_level == want)
	# Opening and closing the panel alone changes it (the UI layer calls set_menu_shown).
	main.set_foveation("medium")
	main.set_foveation_sharp_panel(true)
	main.set_menu_shown(false)
	_check("update: panel closed, Medium", fake.foveation_level == 2)
	main.set_menu_shown(true)
	_check("update: panel open, off", fake.foveation_level == 0)
	var sets := fake.sets
	main._update_foveation()
	_check("update: set only when it changes", fake.sets == sets)
	main.set_menu_shown(false)
	# No foveated swapchain: the level is never set.
	ProjectSettings.set_setting(PROJECT_LEVEL, 0)
	sets = fake.sets
	main.set_foveation("high")
	_check("update: not available, nothing set", fake.sets == sets and fake.foveation_level == 2)
	ProjectSettings.set_setting(PROJECT_LEVEL, 1)
	main._update_foveation()
	_check("update: available again, High", fake.foveation_level == 3)
	main.set_foveation("low")
	main.set_menu_shown(menu_was)


## [view] foveation and foveation_sharp_panel, written and read back through a settings file.
func _test_round_trip() -> void:
	var fresh := AppSettings.new()
	var old: RefCounted = main.settings
	main.settings = fresh
	main.load_foveation()
	_check("round trip: no keys -> low, sharp", main.foveation == "low" and main.foveation_sharp_panel)
	main.set_foveation("medium")
	main.set_foveation_sharp_panel(false)
	_check("round trip: written", fresh.get_value("view", "foveation", "") == "medium"
			and fresh.get_value("view", "foveation_sharp_panel", true) == false)
	main.set_foveation("ultra")
	_check("round trip: an unknown level not taken", main.foveation == "medium"
			and fresh.get_value("view", "foveation", "") == "medium")
	_check("round trip: saved", fresh._cfg.save(TMP_PATH) == OK)
	var back := AppSettings.new()
	_check("round trip: loaded", back._cfg.load(TMP_PATH) == OK)
	main.settings = back
	main.foveation = "low"
	main.foveation_sharp_panel = true
	main.load_foveation()
	_check("round trip: read back medium, not sharp", main.foveation == "medium" and not main.foveation_sharp_panel)
	back.set_value("view", "foveation", "ultra")
	main.load_foveation()
	_check("round trip: an unknown word in the file reads as low", main.foveation == "low")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PATH))
	main.settings = old
	main.load_foveation()


## The System tab's Rendering row: Off / Low / Medium / High, the help line, the toggle; disabled without foveation.
func _test_row() -> void:
	var tab: Node = _system_tab()
	if tab == null:
		_check("the main scene has its System tab", false)
		return
	tab.sync()
	var row: HBoxContainer = tab._foveation
	var words: Array = []
	for b: Button in row.get_children():
		words.append(b.text)
	_check("row: Off / Low / Medium / High (%s)" % [words], words == ["Off", "Low", "Medium", "High"])
	_check("row: its name", (row.get_parent().get_child(0) as Label).text == "Foveation")
	_check("row: Low marked", _marked(row) == 1)
	_check("row: the help line", (tab._foveation_help as Label).text == SystemTab.FOVEATION_HELP
			and (tab._foveation_help as Label).has_meta("help"))
	var sharp: Button = tab._foveation_sharp
	_check("row: the toggle on", sharp.text == "Sharp while the panel shows" and sharp.button_pressed)

	(row.get_child(3) as Button).pressed.emit()
	_check("row: High chosen applies and saves", main.foveation == "high"
			and main.settings.get_value("view", "foveation", "") == "high")
	main.set_menu_shown(false)
	_check("row: High reaches the interface with the panel closed", fake.foveation_level == 3)
	main.set_menu_shown(true)
	_check("row: off while the panel shows", fake.foveation_level == 0)
	sharp.button_pressed = false
	_check("row: the toggle off applies and saves", not main.foveation_sharp_panel
			and main.settings.get_value("view", "foveation_sharp_panel", true) == false and fake.foveation_level == 3)
	sharp.button_pressed = true
	_check("row: the toggle on again", main.foveation_sharp_panel and fake.foveation_level == 0)
	main.set_foveation("medium")
	_check("row: follows a change made elsewhere", _marked(row) == 2)

	ProjectSettings.set_setting(PROJECT_LEVEL, 0)
	tab.sync()
	var all_off := sharp.disabled
	for b: Button in row.get_children():
		all_off = all_off and b.disabled
	_check("row: not available, disabled", all_off and _marked(row) == -1)
	_check("row: not available, says so", (tab._foveation_help as Label).text == SystemTab.FOVEATION_UNAVAILABLE)
	ProjectSettings.set_setting(PROJECT_LEVEL, 1)
	tab.sync()
	_check("row: available again", not sharp.disabled and not (row.get_child(0) as Button).disabled
			and _marked(row) == 2 and (tab._foveation_help as Label).text == SystemTab.FOVEATION_HELP)
	main.set_foveation("low")
	await _frames(1)


## `foveation` and system_settings' foveation, through the registry.
func _test_command() -> void:
	_check("foveation is registered", DevCommands.has_command("foveation"))
	if not DevCommands.has_command("foveation"):
		return
	var spec := DevCommands.get_spec("foveation")
	_check("foveation: assistant settings", spec.get("assistant") == "settings" and spec.get("level") == "change")
	for p: Dictionary in spec["params"]:
		_check("foveation: %s described" % p["name"], str(p.get("description", "")).strip_edges() != "")
	var st := await _read("system_settings")
	_check("system_settings: foveation (%s)" % [st.get("foveation")], st.get("foveation", {}) == {"level": "low",
			"sharp_panel": true, "available": true})

	main.set_menu_shown(false)
	var r := await _run_cmd("foveation", {"level": "high"})
	_check("foveation: High", r["ok"] and main.foveation == "high" and r["result"]["level"] == "high"
			and fake.foveation_level == 3)
	_check("foveation: summary", "high" in (r["call"] as DevCommands.Call).summary)
	_check("foveation: read back", (await _read("system_settings"))["foveation"]["level"] == "high")
	var tab: Node = _system_tab()
	if tab != null:
		_check("foveation: the tab follows", _marked(tab._foveation) == 3)
	(r["call"] as DevCommands.Call).undo.call()
	_check("foveation: undo", main.foveation == "low" and fake.foveation_level == 1)
	if tab != null:
		_check("foveation: the tab follows the undo", _marked(tab._foveation) == 1)

	r = await _run_cmd("foveation", {"sharp_panel": false})
	main.set_menu_shown(true)
	_check("foveation: not kept sharp under the panel", r["ok"] and not main.foveation_sharp_panel
			and fake.foveation_level == 1 and r["result"]["sharp_panel"] == false)
	if tab != null:
		_check("foveation: the tab's toggle follows", not (tab._foveation_sharp as Button).button_pressed)
	(r["call"] as DevCommands.Call).undo.call()
	_check("foveation: undo the toggle", main.foveation_sharp_panel and fake.foveation_level == 0)

	r = await _run_cmd("foveation", {})
	_check("foveation: nothing to change refused", not r["ok"])
	r = await _run_cmd("foveation", {"level": "ultra"})
	_check("foveation: a level outside the list refused", not r["ok"] and main.foveation == "low")
	ProjectSettings.set_setting(PROJECT_LEVEL, 0)
	r = await _run_cmd("foveation", {"level": "off"})
	_check("foveation: refused without a foveated swapchain (%s)" % r.get("error"), not r["ok"]
			and main.foveation == "low" and "available" in str(r["error"]))
	_check("system_settings: says it isn't available",
			(await _read("system_settings"))["foveation"]["available"] == false)
	ProjectSettings.set_setting(PROJECT_LEVEL, 1)


# --- Helpers ------------------------------------------------------------------------------------------------------

func _run_cmd(cmd: String, args: Dictionary) -> Dictionary:
	return await DevCommands.execute(cmd, args, true)


func _read(cmd: String) -> Dictionary:
	var r := await _run_cmd(cmd, {})
	return r["result"] if r["ok"] else {}


func _system_tab() -> Node:
	var layer: Node = main.ui
	var pane: Node = layer.get("ui") if layer != null else null
	return pane.get("system") if pane != null else null


## The index of the pressed choice, -1 for none.
static func _marked(row: Container) -> int:
	for i in row.get_child_count():
		if (row.get_child(i) as Button).button_pressed:
			return i
	return -1


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL " + what)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
