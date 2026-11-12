extends SceneTree

## Android apps on the big screen (scripts/android/) with stand-ins for the commands and the window capture: discovery, the
## scripts (stop.sh run for real against stand-in programs), the steps from a growing log, failures and time limits,
## Cancel, the full stop whenever the window leaves the big screen, one app at a time, what a crash leaves, B, the dev
## commands, and the Files rows.
##
## godot --headless --xr-mode off --path app --script res://tests/test_android_apps.gd

const AgentTerminal := preload("res://scripts/agents/agent_terminal.gd")
const Lepton := preload("res://scripts/android/lepton.gd")
const AndroidApps := preload("res://scripts/android/android_apps.gd")
const WindowVideoSource := preload("res://scripts/video/window_video_source.gd")
const DevCommands := preload("res://scripts/dev/dev_commands.gd")
const CommandHost := preload("res://scripts/dev/command_host.gd")
const AssistantCommands := preload("res://scripts/assistant/assistant_commands.gd")
const WINDOW := 0x2a00003
const TITLE := "KDE Wayland Compositor - Press right control key to grab input"
const PACKAGE := "com.example.app"
const ACTIVITY := "com.example.app/.MainActivity"


## Stands in for the commands: units come and go in `alive`, and every command is kept in `calls`. Commands come from
## worker threads, so everything goes through the mutex.
class FakeRunner extends RefCounted:
	var mutex := Mutex.new()
	var calls: Array[String] = []
	var launched: Array[String] = []
	var alive := {}
	## A unit systemd-run refuses.
	var refuse := ""
	## Starting this unit takes a while.
	var slow := ""
	## The stop unit comes up and never finishes.
	var stop_hangs := false
	## What each dumpsys says, in turn.
	var tops: Array[String] = []
	var resolves := ACTIVITY
	## What pidof says for the app.
	var pid := "1234"

	func run(argv: Array[String]) -> Dictionary:
		var line := " ".join(argv)
		mutex.lock()
		calls.append(line)
		mutex.unlock()
		if "systemd-run" in line:
			return _systemd_run(line)
		if "is-active" in line:
			return _is_active(line)
		if "dumpsys" in line:
			mutex.lock()
			var top: String = tops.pop_front() if not tops.is_empty() else ""
			mutex.unlock()
			return {"code": 0, "out": "  noise\n    mResumedActivity: %s\n  ResumedActivity: x\n" % top if top != ""
					else "lepton-example.apk\n"}
		if "resolve-activity" in line:
			return {"code": 0, "out": "priority=0 preferredOrder=0\n%s\n" % resolves}
		if "pidof" in line:
			return {"code": 0, "out": pid + "\n"}
		return {"code": 0, "out": ""}

	func launch(argv: Array[String]) -> int:
		mutex.lock()
		launched.append(" ".join(argv))
		mutex.unlock()
		return 1

	func _systemd_run(line: String) -> Dictionary:
		var unit := line.get_slice("--unit=", 1).get_slice(" ", 0)
		if unit == refuse:
			return {"code": 1, "out": "Failed to start transient service unit: nope\n"}
		if unit == slow:
			OS.delay_msec(300)
		mutex.lock()
		alive[unit] = true
		calls.append("up " + unit)
		mutex.unlock()
		if unit == Lepton.STOP_UNIT:
			if not stop_hangs:
				_finish_stop()
		return {"code": 0, "out": ""}

	func _finish_stop() -> void:
		var f := FileAccess.open(Lepton.stop_log(), FileAccess.READ_WRITE)
		f.seek_end()
		f.store_string("Stopping the app\nStopping Android\nStopping the display\nStopped\n")
		f.close()
		DirAccess.remove_absolute(Lepton.marker())
		mutex.lock()
		alive.clear()
		mutex.unlock()

	func _is_active(line: String) -> Dictionary:
		var out := ""
		var any := 1
		mutex.lock()
		for part in line.get_slice("is-active ", 1).split(" "):
			out += ("active\n" if alive.has(part) else "inactive\n")
			if alive.has(part):
				any = 0
		mutex.unlock()
		return {"code": any, "out": out}

	func is_alive(unit: String) -> bool:
		mutex.lock()
		var on := alive.has(unit)
		mutex.unlock()
		return on

	func ran(text: String) -> bool:
		mutex.lock()
		var found := false
		for c in calls:
			if text in c:
				found = true
		mutex.unlock()
		return found

	func index_of(text: String) -> int:
		mutex.lock()
		var at := -1
		for i in calls.size():
			if text in calls[i]:
				at = i
				break
		mutex.unlock()
		return at


## Stands in for the window capture: the compositor's window exists while its unit is alive.
class FakeX extends RefCounted:
	var runner: FakeRunner
	var no_window := false

	func list_windows(_all := false) -> Array[Dictionary]:
		var out: Array[Dictionary] = [{"id": 7, "title": "Some other window", "class": "other", "instance": "other"}]
		if runner.is_alive(Lepton.DISPLAY_UNIT) and not no_window:
			out.append({"id": WINDOW, "title": TITLE, "class": "", "instance": ""})
		return out

	func stop_capture() -> void:
		pass

	func close() -> void:
		pass


var _failures := 0
var _checks := 0
var main: Node3D
var apps: AndroidApps
var fake: FakeRunner
var fake_x: FakeX
var card: Node
var home := ""
## What apps.step was, each time it changed.
var steps: Array[String] = []


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _run() -> void:
	await _frames(5)
	home = OS.get_user_data_dir().path_join("test_android_home")
	_clear(home)
	DirAccess.make_dir_recursive_absolute(home)
	AgentTerminal.home_override = home
	Lepton.compositor = home.path_join("kwin_wayland")
	apps = main.android_apps
	card = main.ui.card
	fake = FakeRunner.new()
	fake_x = FakeX.new()
	fake_x.runner = fake
	main.local_agents.x = fake_x
	apps.runner = fake
	apps.open_window = _fake_open
	apps.poll_seconds = 0.02
	apps.unit_check_seconds = 0.1
	Lepton.launch_seconds = 0.4
	Lepton.front_seconds = 0.05
	apps.changed.connect(func() -> void:
		if steps.is_empty() or steps[-1] != apps.step:
			steps.append(apps.step))
	_discovery_checks()
	_script_checks()
	_stop_script_checks()
	_log_checks()
	await _start_checks()
	await _open_checks()
	await _leaving_checks()
	await _cancel_checks()
	await _failure_checks()
	await _one_at_a_time_checks()
	await _left_over_checks()
	await _back_checks()
	await _dev_checks()
	await _files_checks()
	main.local_agents.x = null
	AgentTerminal.home_override = ""
	Lepton.compositor = Lepton.COMPOSITOR
	_clear(home)
	print("test_android_apps: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(1 if _failures > 0 else 0)


## As main.open_path() with a captured window, with no X display to capture from.
func _fake_open(path: String) -> void:
	main.player.close()
	main.current_path = path
	var s := WindowVideoSource.new()
	s.path = path
	s.window_id = WindowVideoSource.window_id_of(path)
	main.player.source = s
	main.mode = s.get_known_mode().copy()


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _append(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ_WRITE)
	f.seek_end()
	f.store_string(text)
	f.close()


func _discovery_checks() -> void:
	var env := " ".join(Lepton._env())
	_check("a Steam launch's own variables don't reach Lepton (%s)" % env, env.contains("-u SteamAppId")
			and env.contains("-u SteamGameId") and env.contains("-u LD_PRELOAD"))
	_check("no folder: no apps", Lepton.apps().is_empty())
	_check("Lepton missing is said in plain words", Lepton.missing()[0].contains("Lepton isn't on this headset")
			and Lepton.missing()[1].contains("Steam"))
	_write(Lepton.lepton(), "#!/bin/sh\n")
	_check("the compositor missing too", Lepton.missing()[0].contains("compositor"))
	_write(Lepton.compositor, "#!/bin/sh\n")
	_check("nothing missing now", Lepton.missing().is_empty())
	_check("how to add an app names the folder", " ".join(Lepton.how_to_add()).contains("~/Android/<name>/"))
	_write(Lepton.folder().path_join("Example/example.apk"), "")
	_write(Lepton.folder().path_join("Example/notes.txt"), "")
	_write(Lepton.folder().path_join("Two Words/two.APK"), "")
	_write(Lepton.folder().path_join("Alpha/alpha.apk"), "")
	_write(Lepton.folder().path_join("Empty/readme.txt"), "")
	_write(Lepton.folder().path_join("Spaces/my app.apk"), "")
	_write(Lepton.folder().path_join(".player/stray.apk"), "")
	var list := Lepton.apps()
	var names: Array = list.map(func(a: Dictionary) -> String: return a["name"])
	_check("each folder with an APK is an app, in order (%s)" % [names],
			names == ["Alpha", "Example", "Spaces", "Two Words"])
	_check("labelled from the folder", list[3]["label"] == "Two Words" and list[1]["apk"] == Lepton.folder().path_join(
			"Example/example.apk"))
	_check("a name with spaces is noted", bool(list[2]["spaces"]) and not bool(list[1]["spaces"]))
	_check("found by name", Lepton.find_app("Example")["folder"] == Lepton.folder().path_join("Example")
			and Lepton.find_app("Nope").is_empty())


func _script_checks() -> void:
	var a := Lepton.find_app("Example")
	var display := Lepton.display_text()
	_check("display: the nested compositor as proved", display.contains(
			"--x11-display ':0' --socket wl-android --width 1920 --height 1080") or display.contains(
			"--socket wl-android --width 1920 --height 1080"))
	_check("display: no Wayland display of its own", display.contains("unset WAYLAND_DISPLAY")
			and display.contains("export DISPLAY=") and display.contains("export XDG_RUNTIME_DIR="))
	var run := Lepton.run_text(a)
	_check("run: the environment as proved", run.contains("export GAMESCOPE_WAYLAND_DISPLAY=wl-android")
			and run.contains("export STEAM_COMPAT_INSTALL_PATH='%s'\n" % a["folder"]) and run.contains("export IS_PARENT=true")
			and run.contains("export TERM=dumb") and run.contains("export XDG_RUNTIME_DIR="))
	_check("run: lepton start, output to the log", run.contains("'%s' start '%s' >>'%s' 2>&1" % [Lepton.lepton(), a["apk"],
			Lepton.run_log()]))
	_check("a quote in a folder's name can't break out", Lepton.quoted("it's") == "'it'\\''s'")
	var stop := Lepton.stop_text(a)
	_check("stop: force-stop first, no app output kept", stop.contains("cmd activity force-stop \"$pkg\" >/dev/null 2>&1"))
	_check("the app must not run as root or with sudo", not (display + run + stop).contains("sudo"))
	_check("prepare says nothing is wrong", Lepton.prepare(a) == "")
	_check("the show file is made for the user", FileAccess.file_exists(str(a["folder"]).path_join(Lepton.SHOW_FILE)))
	_check("the scripts are written, runnable", FileAccess.get_file_as_string(Lepton.player_dir().path_join("run.sh")) == run
			and FileAccess.get_unix_permissions(Lepton.player_dir().path_join("stop.sh")) & FileAccess.UNIX_EXECUTE_OWNER != 0)
	_check("the marker is there", FileAccess.file_exists(Lepton.marker()))
	_check("the user's files stay", FileAccess.file_exists(str(a["folder"]).path_join("example.apk"))
			and FileAccess.file_exists(str(a["folder"]).path_join("notes.txt")))
	var argv := Lepton.unit_argv(Lepton.APP_UNIT, "/x/run.sh")
	_check("a unit by systemd-run --user, collected", " ".join(argv).contains(
			"systemd-run --user --unit=frame-android-app --collect /x/run.sh"))
	var keep := FakeRunner.new()
	Lepton.exec(keep, "/a.apk", ["cmd", "x"])
	_check("exec: the environment it needs, and a time limit", keep.calls[0].contains("XDG_RUNTIME_DIR=")
			and keep.calls[0].contains("TERM=dumb") and keep.calls[0].contains("timeout %d" % Lepton.EXEC_SECONDS)
			and keep.calls[0].ends_with("exec /a.apk cmd x"))
	DirAccess.remove_absolute(Lepton.marker())


## stop.sh run for real, with systemctl and lepton stood in for by small scripts.
func _stop_script_checks() -> void:
	if OS.get_name() == "Windows":
		return
	var bin := home.path_join("fake bin")
	var state := bin.path_join("state")
	DirAccess.make_dir_recursive_absolute(state)
	_write(bin.path_join("systemctl"), ("#!/bin/sh\nd='%s'\necho \"systemctl $*\" >>\"$d/calls\"\ncase \"$2\" in\n" % state)
			+ "is-active) if [ -e \"$d/$3\" ]; then echo active; else echo inactive; exit 3; fi ;;\n"
			+ "stop) rm -f \"$d/$3\" ;;\nkill) rm -f \"$d/$4\" ;;\nesac\nexit 0\n")
	_write(Lepton.lepton(), ("#!/bin/sh\nd='%s'\necho \"lepton $*\" >>\"$d/calls\"\n" % state)
			+ "[ -e \"$d/ignores\" ] || rm -f \"$d/%s\"\n" % Lepton.APP_UNIT)
	OS.execute("chmod", ["+x", bin.path_join("systemctl"), Lepton.lepton()])
	var a := Lepton.find_app("Example")
	var odd := Lepton.folder().path_join("It's here")
	_write(odd.path_join("odd.apk"), "")
	var quoted_app := Lepton.find_app("It's here")
	Lepton.prepare(quoted_app)
	_write(Lepton.run_log(), "Launching lepton-1.apk\nWaiting for app %s to exit...\n" % PACKAGE)
	var calls := _run_stop(bin, state, [Lepton.APP_UNIT, Lepton.DISPLAY_UNIT])
	_check("stop.sh: force-stop by the package from the log, with the folder's quote intact (%s)" % calls,
			calls.contains("exec %s cmd activity force-stop %s" % [quoted_app["apk"], PACKAGE]))
	_check("stop.sh: the app ended by itself, so no forced stop of it", not calls.contains("stop %s" % Lepton.APP_UNIT))
	_check("stop.sh: then the compositor", calls.contains("--user stop %s" % Lepton.DISPLAY_UNIT))
	_check("stop.sh: says each step, and last that it has stopped", FileAccess.get_file_as_string(Lepton.stop_log()) ==
			"Stopping the app\nStopping the display\nStopped\n")
	_check("stop.sh: the marker goes", not FileAccess.file_exists(Lepton.marker()))
	_clear(odd)
	Lepton.prepare(a)
	_write(Lepton.run_log(), "Launching lepton-1.apk\nWaiting for boot...\n")
	calls = _run_stop(bin, state, [Lepton.APP_UNIT, Lepton.DISPLAY_UNIT])
	_check("stop.sh: still booting, so no package: straight to stopping the unit", not calls.contains("force-stop")
			and calls.contains("--user stop %s" % Lepton.APP_UNIT))
	Lepton.prepare(a)
	_write(Lepton.run_log(), "Waiting for app %s to exit...\n" % PACKAGE)
	_write(state.path_join("ignores"), "")
	calls = _run_stop(bin, state, [Lepton.APP_UNIT, Lepton.DISPLAY_UNIT])
	_check("stop.sh: force-stop ignored, so it falls back to stopping the unit", calls.contains("force-stop")
			and calls.contains("--user stop %s" % Lepton.APP_UNIT))
	DirAccess.remove_absolute(state.path_join("ignores"))
	calls = _run_stop(bin, state, [])
	_check("stop.sh: nothing running, nothing forced, and it ends", not calls.contains("lepton")
			and FileAccess.get_file_as_string(Lepton.stop_log()).ends_with("Stopped\n"))
	_write(Lepton.lepton(), "#!/bin/sh\n")


func _run_stop(bin: String, state: String, alive: Array[String]) -> String:
	DirAccess.remove_absolute(state.path_join("calls"))
	_write(Lepton.stop_log(), "")
	for u in alive:
		_write(state.path_join(u), "")
	var out: Array = []
	OS.execute("env", ["PATH=%s:%s" % [bin, OS.get_environment("PATH")], "sh", Lepton.player_dir().path_join("stop.sh")],
			out, true)
	return FileAccess.get_file_as_string(state.path_join("calls"))


func _log_checks() -> void:
	var path := Lepton.player_dir().path_join("tail.log")
	_write(path, "one\ntwo\nthr")
	var tail := Lepton.LogTail.new(path)
	_check("the whole lines so far; a line still being written waits", tail.new_lines() == ["one", "two"])
	var read_to := tail.offset
	_check("nothing new, nothing read", tail.new_lines().is_empty() and tail.offset == read_to)
	_append(path, "ee\nfour\n")
	_check("only the new bytes, and the line that was waiting whole", tail.new_lines() == ["three", "four"]
			and tail.offset > read_to)
	_write(path, "new\n")
	_check("a log started over is read from its start", tail.new_lines() == ["new"])
	_check("a missing log is no error", Lepton.LogTail.new(path + ".none").new_lines().is_empty())
	_check("each line of the log means its step", Lepton.log_event("Launching lepton-3.apk")["step"] == "Starting Android"
			and Lepton.log_event("Waiting for boot...")["step"] == "Starting Android"
			and Lepton.log_event("Boot complete!")["step"] == "Android is up"
			and Lepton.log_event("Installing foo.apk")["step"] == "Preparing the app"
			and Lepton.log_event("Performing Streamed Install")["step"] == "Preparing the app")
	_check("the package is read from its line", Lepton.log_event("Waiting for app com.a.b to exit...")["package"] == "com.a.b")
	_check("the end of the run", Lepton.log_event("Exited!").has("exited"))
	_check("an install failure", Lepton.log_event("Failure [INSTALL_FAILED_OLDER_SDK]").has("failed"))
	_check("other lines mean nothing", Lepton.log_event("Success").is_empty() and Lepton.log_event("").is_empty())
	_check("a line that could hold a login is never shown", Lepton.reason_line("user password=abc") == ""
			and Lepton.reason_line("Set-Cookie: abc") == "" and Lepton.reason_line("auth token abc") == "")
	_check("a reason is one short line", Lepton.reason_line("  x\tno\u0007 %s" % "y".repeat(300)).length()
			== Lepton.REASON_MAX)


## Runs the steps as a real start does, up to the app on the big screen.
func _begin(app_name := "Example") -> void:
	steps.clear()
	apps.start_app(app_name)
	await _until(func() -> bool: return apps.state == apps.State.IDLE or (apps.step == "Starting Android"
			and fake.is_alive(Lepton.APP_UNIT)))


func _say(line: String) -> void:
	_append(Lepton.run_log(), line + "\n")


func _start_ok(app_name := "Example") -> void:
	await _begin(app_name)
	_say("Launching lepton-1.apk")
	_say("Waiting for boot...")
	_say("Boot complete!")
	_say("Waiting for app %s to exit..." % PACKAGE)
	await _until(func() -> bool: return apps.state == apps.State.RUNNING)


func _start_checks() -> void:
	main.open_path("stub://flat_sbs")
	await _frames(2)
	main.ui.show_panel()
	await _begin()
	_check("started in the right order", fake.index_of("--unit=frame-android-display") >= 0
			and fake.index_of("--unit=frame-android-display") < fake.index_of("--unit=frame-android-app"))
	_check("the show file for this app", FileAccess.file_exists(Lepton.folder().path_join("Example").path_join(
			Lepton.SHOW_FILE)))
	_check("the card says what is going on", card.is_showing() and card.id == "android"
			and card._text.text.contains("Starting the display\nStarting Android"))
	_check("the card offers Cancel", card.action_point("cancel") != null)
	_check("a film stays on until the app is ready", main.current_path == "stub://flat_sbs")
	_check("the status says so", apps.status()["state"] == "starting" and apps.status()["step"] == "Starting Android")
	_say("Launching lepton-1.apk")
	_say("Waiting for boot...")
	await _until(func() -> bool: return apps.step == "Starting Android")
	_say("Boot complete!")
	await _until(func() -> bool: return apps.step == "Android is up")
	_check("the steps follow the log", apps.step == "Android is up")
	_append(Lepton.run_log(), "Installing lepton-1.apk")
	await _seconds(0.1)
	_check("half a line waits", apps.step == "Android is up")
	_append(Lepton.run_log(), "\nPerforming Streamed Install\n")
	await _until(func() -> bool: return apps.step == "Preparing the app")
	_check("the card keeps up", card._text.text.contains("Android is up\nPreparing the app"))
	_say("Success")
	_say("Waiting for app %s to exit..." % PACKAGE)
	await _until(func() -> bool: return apps.state == apps.State.RUNNING)
	_check("every step was shown (%s)" % [steps], steps.slice(0, 7) == ["Getting ready", "Starting the display",
			"Starting Android", "Android is up", "Preparing the app", "Opening the app", "Ready"])
	_check("the package came from the log", apps.package == PACKAGE)
	_check("brought forward: resolved, then started", fake.ran("cmd package resolve-activity --brief -c "
			+ "android.intent.category.LAUNCHER -a android.intent.action.MAIN %s" % PACKAGE)
			and fake.ran("cmd activity start-activity -n %s" % ACTIVITY))
	_check("found by its title, not a fixed id", apps.on_big_screen() and main.current_path == "window://0x2a00003")
	_check("the menu closed", not main.menu_shown)
	_check("the card says ready, with no button", card._text.text.ends_with("Ready") and card.action_point("cancel") == null)
	var src: WindowVideoSource = main.player.source
	_check("named for the viewer, not a browser", src.is_named() and src.get_title() == "" and not src.is_browser())
	src._title = src._read_title()
	_check("the title is the app's", src.get_title() == "Android: Example")
	_check("Files says it runs", apps.status_line() == "Example is on the big screen")
	await _stopped_by(func() -> void: apps.stop_app())


## Runs `leave`, then waits for the stop. Checks it was a full one.
func _stopped_by(leave: Callable) -> void:
	var stops := _count("--unit=frame-android-stop")
	leave.call()
	await _until(func() -> bool: return apps.state == apps.State.IDLE)
	_check("the stop ran", _count("--unit=frame-android-stop") == stops + 1)
	_check("nothing is left running", fake.alive.is_empty() and apps.app.is_empty())
	_check("the window's name goes", WindowVideoSource.named_windows.is_empty())


func _count(text: String) -> int:
	var n := 0
	for c in fake.calls:
		if text in c:
			n += 1
	return n


## Lepton's launch force-stops the app, and the app's process dying ends the container: nothing may start it before.
func _open_checks() -> void:
	const START := "cmd activity start-activity"
	var started := _count(START)
	await _opening()
	await _stopped_by(func() -> void: apps.cancel())
	_check("no process yet: Lepton's launch is to come, so nothing starts the app", _count(START) == started)

	await _opening()
	fake.pid = "1234 1235"
	await _seconds(Lepton.front_seconds * 3.0)
	await _until(func() -> bool: return apps.state == apps.State.RUNNING)
	_check("a process behind the launcher is brought forward", _count(START) == started + 1)
	await _stopped_by(func() -> void: main.open_path("stub://flat_sbs"))

	await _opening()
	fake.tops.assign(["ActivityRecord{1 u0 %s t3}" % ACTIVITY])
	fake.pid = "1234"
	await _until(func() -> bool: return apps.state == apps.State.RUNNING)
	_check("at the front by itself: nothing more to start", _count(START) == started + 1)
	await _stopped_by(func() -> void: main.open_path("stub://flat_sbs"))

	await _opening()
	_say("Exited!")
	await _until(func() -> bool: return apps.state == apps.State.IDLE)
	_check("the app ended while opening", apps.last_error.contains("closed as soon as it started"))

	await _opening()
	await _until(func() -> bool: return apps.state == apps.State.RUNNING)
	_check("no process in time: the window goes up, and still nothing starts the app",
			apps.on_big_screen() and _count(START) == started + 1)
	await _stopped_by(func() -> void: main.open_path("stub://flat_sbs"))
	fake.pid = "1234"


## A start up to the wait for Lepton's launch, with no process yet.
func _opening() -> void:
	fake.pid = ""
	await _begin()
	_say("Boot complete!")
	_say("Waiting for app %s to exit..." % PACKAGE)
	await _until(func() -> bool: return apps.step == "Opening the app")


func _leaving_checks() -> void:
	await _start_ok()
	await _stopped_by(func() -> void: main.open_path("stub://flat_sbs"))
	_check("another file opened: it stops, and the new file stays", main.current_path == "stub://flat_sbs")
	_check("the stop's steps show and it says it has stopped", card.is_showing() and card._text.text == "Example has stopped."
			and card.action_point("cancel") == null)
	await _start_ok()
	await _stopped_by(func() -> void: main.close_media())
	_check("the menu's close: it stops", main.current_path == "")
	await _start_ok()
	await _stopped_by(func() -> void: main.ui.ui.files.close_requested.emit())
	_check("Stop showing in Files: it stops", main.current_path == "")
	await _start_ok()
	await _stopped_by(func() -> void: (main.player.source as WindowVideoSource).window_id = 0)
	_check("the window went by itself: it stops", apps.state == apps.State.IDLE)
	main.close_media()
	await _start_ok()
	await _stopped_by(func() -> void: _say("Exited!"))
	_check("the app quit: the screen is cleared too", main.current_path == "" and card._text.text == "Example has closed.")
	await _start_ok()
	await _stopped_by(func() -> void:
		fake.mutex.lock()
		fake.alive.erase(Lepton.APP_UNIT)
		fake.mutex.unlock())
	_check("the unit died with no word in the log: it stops", main.current_path == "")
	await _start_ok()
	main.open_path("stub://flat_sbs")
	await _until(func() -> bool: return apps.state == apps.State.STOPPING)
	_check("stopping doesn't get in the way of the new file", main.current_path == "stub://flat_sbs"
			and card.action_point("cancel") == null)
	await _until(func() -> bool: return apps.state == apps.State.IDLE)
	await _start_ok()
	card.show_card({"id": "someone", "title": "Someone", "text": "Their card", "seconds": 0.0})
	await _stopped_by(func() -> void: main.open_path("stub://flat_sbs"))
	_check("a card that is someone else's stays", card.id == "someone" and card._text.text == "Their card")
	card.dismiss("cleared")


func _cancel_checks() -> void:
	await _begin()
	await _stopped_by(func() -> void: card.dismiss("cancel"))
	_check("Cancel on the card stops it", card.is_showing() and card._text.text == "Cancelled.")
	_check("and nothing comes to the big screen", not apps.on_big_screen() and main.current_path == "stub://flat_sbs")
	await _begin()
	var before: String = main.current_path
	await _stopped_by(func() -> void: apps.cancel())
	_check("cancel() does too, and the film goes on", main.current_path == before)
	fake.slow = Lepton.APP_UNIT
	fake.calls.clear()
	apps.start_app("Example")
	await _until(func() -> bool: return fake.ran("--unit=frame-android-app"))
	apps.cancel()
	await _until(func() -> bool: return apps.state == apps.State.IDLE)
	await _seconds(0.4)
	fake.slow = ""
	_check("a unit coming up as Cancel is pressed is stopped too, not missed", fake.index_of("up frame-android-app") >= 0
			and fake.index_of("up frame-android-app") < fake.index_of("--unit=frame-android-stop"))
	_check("nothing left", fake.alive.is_empty())
	await _begin()
	await _stopped_by(func() -> void: main.open_path("stub://360_tb"))
	_check("something else opened while starting: the viewer moved on", main.current_path == "stub://360_tb"
			and not apps.on_big_screen())
	await _begin()
	card.dismiss("user")
	await _until(func() -> bool: return not card.is_showing())
	await _frames(20)
	_say("Boot complete!")
	await _until(func() -> bool: return apps.step == "Android is up")
	_check("a card put away stays away, and the steps go on", not card.is_showing() and apps.state == apps.State.STARTING)
	_check("Files still has the way out", apps.status_line().contains("Android is up"))
	await _stopped_by(func() -> void: apps.cancel())


func _failure_checks() -> void:
	fake.refuse = Lepton.DISPLAY_UNIT
	await _failed_by(func() -> void: apps.start_app("Example"))
	_check("the display refused: the reason in plain words", apps.last_error.begins_with("The display did not start")
			and apps.last_error.contains("nope"))
	_check("the reason stays on the card", card.is_showing() and card._text.text == apps.last_error)
	fake.refuse = Lepton.APP_UNIT
	await _failed_by(func() -> void: apps.start_app("Example"))
	_check("Android refused", apps.last_error.begins_with("Android did not start"))
	fake.refuse = ""
	fake_x.no_window = true
	apps.display_timeout = 0.2
	apps.start_app("Example")
	await _until(func() -> bool: return apps.state == apps.State.IDLE)
	_check("no window: a time limit, not a silent hang", apps.last_error.contains("window did not come"))
	fake_x.no_window = false
	apps.display_timeout = 20.0
	await _begin()
	_say("Failure [INSTALL_FAILED_NO_MATCHING_ABIS: Failed to extract native libraries, res=-113]")
	await _until(func() -> bool: return apps.state == apps.State.IDLE)
	_check("an install failure says why", apps.last_error.begins_with("Installing Example failed.")
			and apps.last_error.contains("INSTALL_FAILED_NO_MATCHING_ABIS"))
	_check("what was started has gone", fake.alive.is_empty())
	await _begin()
	_say("Launching lepton-1.apk")
	_say("Exited!")
	await _until(func() -> bool: return apps.state == apps.State.IDLE)
	_check("the app closed at once", apps.last_error.contains("closed as soon as it started"))
	apps.start_timeout = 0.4
	await _begin()
	_say("Boot complete!")
	_say("some last line")
	await _until(func() -> bool: return apps.state == apps.State.IDLE)
	_check("the time limit, with the last useful line (%s)" % apps.last_error,
			apps.last_error.contains("did not start within") and apps.last_error.contains("some last line"))
	await _begin()
	_say("a real error: no such device")
	_say("something after it")
	await _until(func() -> bool: return apps.state == apps.State.IDLE)
	_check("an error line beats the lines after it", apps.last_error.contains("no such device"))
	apps.start_timeout = 180.0
	await _begin()
	_say("user password=hunter2")
	_say("auth token abcdef")
	fake.mutex.lock()
	fake.alive.erase(Lepton.APP_UNIT)
	fake.mutex.unlock()
	await _until(func() -> bool: return apps.state == apps.State.IDLE)
	_check("the unit died while starting", apps.last_error.begins_with("Android stopped before Example opened"))
	_check("no login reaches the card or the status", not apps.last_error.contains("hunter2")
			and not apps.last_error.contains("abcdef") and not str(apps.status()).contains("hunter2"))
	await _begin()
	fake.stop_hangs = true
	apps.stop_timeout = 0.3
	apps.cancel()
	await _until(func() -> bool: return apps.state == apps.State.IDLE)
	_check("a stop that hangs has a time limit and says so", apps.last_error.contains("may still be running")
			and card.is_showing() and card._text.text.contains("may still be running"))
	fake.stop_hangs = false
	apps.stop_timeout = 45.0
	fake.alive.clear()
	apps.last_error = ""


func _failed_by(start: Callable) -> void:
	start.call()
	await _until(func() -> bool: return apps.state == apps.State.IDLE)
	_check("it ended with a reason", apps.last_error != "" and apps.state == apps.State.IDLE)


func _one_at_a_time_checks() -> void:
	await _start_ok()
	var first_stops := _count("--unit=frame-android-stop")
	apps.start_app("Alpha")
	_check("the first stops at once", apps.state == apps.State.STOPPING)
	await _until(func() -> bool: return apps.step == "Starting Android" and apps.is_app("Alpha"))
	_check("starting another stops the first, then starts it", _count("--unit=frame-android-stop") == first_stops + 1
			and apps.is_app("Alpha") and apps.state == apps.State.STARTING)
	_check("the first's screen is cleared", main.current_path == "")
	await _stopped_by(func() -> void: apps.cancel())
	_check("two starts of one app are one start", _double_start())
	await _until(func() -> bool: return apps.step == "Starting Android")
	await _stopped_by(func() -> void: apps.cancel())
	await _start_ok()
	var refused := apps.start_app("Example")
	_check("the running one again changes nothing", refused == "" and apps.state == apps.State.RUNNING)
	await _stopped_by(func() -> void: apps.stop_app())
	_check("no such app is said", apps.start_app("Nope").contains("no app called Nope"))
	_check("a name with spaces is said, and nothing starts", apps.start_app("Spaces").contains("spaces")
			and apps.state == apps.State.IDLE)
	_check("its file isn't renamed", FileAccess.file_exists(Lepton.folder().path_join("Spaces/my app.apk")))
	main.local_agents.x = null
	_check("no X display is said", apps.start_app("Example").contains("display") and apps.state == apps.State.IDLE)
	main.local_agents.x = fake_x
	var kept := Lepton.compositor
	Lepton.compositor = home.path_join("none")
	_check("nothing to run on is said", apps.start_app("Example").contains("compositor"))
	Lepton.compositor = kept


func _double_start() -> bool:
	var count := _count("--unit=frame-android-display")
	apps.start_app("Example")
	apps.start_app("Example")
	return apps.state == apps.State.STARTING and count == _count("--unit=frame-android-display")


func _left_over_checks() -> void:
	fake.alive[Lepton.APP_UNIT] = true
	fake.alive[Lepton.DISPLAY_UNIT] = true
	await _begin()
	_check("what a crash left is stopped first", fake.index_of("--unit=frame-android-stop") >= 0 and steps.has(
			"Clearing what was left from last time"))
	_check("and then the app starts", apps.state == apps.State.STARTING and fake.is_alive(Lepton.APP_UNIT))
	await _stopped_by(func() -> void: apps.cancel())
	fake.stop_hangs = true
	apps.stop_timeout = 0.2
	fake.alive[Lepton.APP_UNIT] = true
	apps.start_app("Example")
	await _until(func() -> bool: return apps.state == apps.State.IDLE)
	_check("left-overs that won't stop: said, and nothing more starts", apps.last_error.contains("would not stop"))
	fake.stop_hangs = false
	apps.stop_timeout = 45.0
	fake.alive.clear()
	apps.last_error = ""
	_write(Lepton.marker(), "")
	var runner_for_new := FakeRunner.new()
	var boot := AndroidApps.new()
	boot.main = main
	boot.runner = runner_for_new
	root.add_child(boot)
	await _frames(1)
	_check("a marker at the player's start clears up, without waiting", runner_for_new.launched.size() == 1
			and runner_for_new.launched[0].contains("--unit=frame-android-stop") and runner_for_new.calls.is_empty())
	boot.state = boot.State.RUNNING
	root.remove_child(boot)
	_check("the player's own exit starts the stop, and doesn't wait", runner_for_new.launched.size() == 2)
	boot.state = boot.State.IDLE
	boot.free()
	DirAccess.remove_absolute(Lepton.marker())
	await _start_ok()
	await _stopped_by(func() -> void: apps.stop_app())
	_check("a clean stop leaves no marker in the real script",
			FileAccess.get_file_as_string(Lepton.player_dir().path_join("stop.sh")).contains(
			"rm -f '%s'" % Lepton.marker()))


func _back_checks() -> void:
	_check("Back worked when the top changed", Lepton.back_worked("ActivityRecord{1 a}", "ActivityRecord{2 b}"))
	_check("not when it stayed", not Lepton.back_worked("ActivityRecord{1 a}", "ActivityRecord{1 a}"))
	_check("not when a look failed", not Lepton.back_worked("", "ActivityRecord{1 a}")
			and not Lepton.back_worked("ActivityRecord{1 a}", "") and not Lepton.back_worked("", ""))
	_check("the top activity, and nothing else of the dump", Lepton.top_of(
			"x\n  mResumedActivity: ActivityRecord{2b u0 com.a/.B t3}\n  y") == "ActivityRecord{2b u0 com.a/.B t3}")
	_check("no such line: unknown", Lepton.top_of("lepton-example.apk\n") == "")
	await _start_ok()
	var a := "ActivityRecord{1 u0 %s t3}" % ACTIVITY
	var b := "ActivityRecord{2 u0 com.example.app/.Player t3}"
	var started := _count("--activity-clear-top")
	fake.tops.assign([b, a])
	var r: Dictionary = await apps.back()
	_check("Back landed: nothing more", r["way"] == "back" and _count("--activity-clear-top") == started)
	_check("Back goes by sh, as input needs", fake.ran("sh /system/bin/input keyevent 4"))
	fake.tops.assign([b, b])
	r = await apps.back()
	_check("Back had no effect: the launcher activity, clearing the top", r["way"] == "launcher"
			and fake.ran("cmd activity start-activity --activity-clear-top -n %s" % ACTIVITY))
	fake.tops.clear()
	r = await apps.back()
	_check("the top can't be read: the same way out", r["way"] == "launcher")
	fake.tops.assign([b, b])
	fake.resolves = "No activity found"
	r = await apps.back()
	_check("no launcher activity: says so, and starts nothing", r["way"] == "none")
	fake.resolves = "lepton-example.apk"
	fake.tops.assign([b, b])
	r = await apps.back()
	_check("a context name isn't an activity", r["way"] == "none")
	fake.resolves = ACTIVITY
	var frames := [0]
	var count := func() -> void: frames[0] += 1
	process_frame.connect(count)
	fake.tops.assign([b, a])
	apps.last_back = {}
	var press := func() -> void: await apps.back()
	press.call()
	_check("one at a time", (await apps.back())["way"] == "none")
	await _until(func() -> bool: return apps.last_back.get("way", "") == "back")
	process_frame.disconnect(count)
	_check("B never holds up a frame (%d frames meanwhile)" % frames[0], frames[0] > 5)
	var right: Node = main.right_hand
	fake.tops.assign([b, a])
	var keys := _count("keyevent 4")
	_check("B is not the window's any more", not main.window_pointer.has_method("on_button"))
	main.screen_surface._press("back")
	await _until(func() -> bool: return _count("keyevent 4") == keys + 1)
	_check("Back on the screen's side stack is Android Back", _count("keyevent 4") == keys + 1)
	await _until(func() -> bool: return not apps._back_busy)
	await _stopped_by(func() -> void: apps.stop_app())
	var after := await apps.back()
	_check("nothing running: B does nothing", after["way"] == "none")
	fake.alive.clear()
	_check("with no container it doesn't try", Lepton.back_now(fake, "/a.apk", PACKAGE)["way"] == "none")


func _dev_checks() -> void:
	CommandHost.ensure(self)
	await _frames(2)
	for c: String in ["android_status", "android_start", "android_stop", "android_back"]:
		_check("%s is registered" % c, DevCommands.has_command(c))
	_check("status reads, the rest are control", DevCommands.get_spec("android_status")["level"] == "read"
			and DevCommands.get_spec("android_start")["level"] == "control"
			and DevCommands.get_spec("android_stop")["level"] == "control")
	var s: Dictionary = await DevCommands.execute("android_status", {})
	_check("status lists the apps", s["ok"] and s["result"]["apps"] == ["Alpha", "Example", "Spaces", "Two Words"]
			and s["result"]["state"] == "idle")
	var bad: Dictionary = await DevCommands.execute("android_start", {"name": "Nope"})
	_check("a bad start fails with the reason", not bad["ok"] and str(bad["error"]).contains("no app called"))
	var ok: Dictionary = await DevCommands.execute("android_start", {"name": "Example"})
	_check("start starts", ok["ok"] and apps.state == apps.State.STARTING)
	await _until(func() -> bool: return apps.step == "Starting Android")
	var stop: Dictionary = await DevCommands.execute("android_stop", {})
	_check("stop stops", stop["ok"])
	await _until(func() -> bool: return apps.state == apps.State.IDLE)
	for c: String in DevCommands.assistant_names():
		if c.begins_with("android"):
			_check("the assistant reaches %s only behind its apps switch (or reading)" % c,
					DevCommands.assistant_level(c) in ["apps", "read"])
	_check("the assistant can't open the window either", AssistantCommands.open_refusal("window://0x2a00003") != "")


func _files_checks() -> void:
	var files: Node = main.ui.ui.files
	_check("Android apps is a place", files.get_places().any(func(p: Dictionary) -> bool:
			return p["label"] == "Android apps" and p["path"] == "android://"))
	files.open_folder("android://")
	await _frames(1)
	_check("a row for each app that can run", files.row_button("Alpha") != null and files.row_button("Example") != null
			and files.row_button("Two Words") != null)
	_check("spaces are said, with no row to press", files.row_button("Spaces") == null and files.row_texts().any(
			func(t: String) -> bool: return t.begins_with("Spaces: its APK's file name has spaces")))
	files.row_button("Example").pressed.emit()
	await _until(func() -> bool: return apps.step == "Starting Android")
	await _frames(1)
	_check("while starting the rows say so, with Cancel (%s)" % [files.row_texts()], files.row_button("Cancel") != null
			and files.row_texts().has("Example: Starting Android ...") and files.row_button("Example") == null)
	_say("Boot complete!")
	await _until(func() -> bool: return apps.step == "Android is up")
	await _frames(1)
	_check("the rows move with the log", files.row_texts().has("Example: Android is up ..."))
	files.row_button("Cancel").pressed.emit()
	await _until(func() -> bool: return apps.state == apps.State.IDLE)
	await _frames(1)
	_check("Cancel in Files stops it", files.row_button("Example") != null and fake.alive.is_empty())
	await _start_ok()
	await _frames(1)
	_check("running: its state and a Stop row", files.row_texts().has("Example is on the big screen")
			and files.row_button("Stop Example") != null)
	await _stopped_by(func() -> void: files.row_button("Stop Example").pressed.emit())
	_check("Stop in Files clears the screen", main.current_path == "")
	fake.refuse = Lepton.DISPLAY_UNIT
	apps.start_app("Example")
	await _until(func() -> bool: return apps.state == apps.State.IDLE)
	fake.refuse = ""
	await _frames(1)
	_check("the last failure is shown", files.row_texts().any(func(t: String) -> bool:
			return t.begins_with("Last try: The display did not start")))
	for a: Dictionary in Lepton.apps():
		_clear(a["folder"])
	files.open_folder("android://")
	await _frames(1)
	_check("no apps: how to add one", files.row_texts().has("No Android apps yet.") and files.row_texts().any(
			func(t: String) -> bool: return t.contains("~/Android/<name>/app.apk")))
	DirAccess.remove_absolute(Lepton.lepton())
	files.open_folder("android://")
	await _frames(1)
	_check("no Lepton: says so", files.row_texts().has("Lepton isn't on this headset."))
	_clear(Lepton.folder())
	files.open_folder("android://")
	await _frames(1)
	_check("the folder is made, so the words are true", DirAccess.dir_exists_absolute(Lepton.folder()))
	files.open_folder("stub://")


func _until(cond: Callable, seconds := 5.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if cond.call():
			return true
		await process_frame
	print("(a wait ran out; state %d, step %s, error %s)" % [apps.state, apps.step, apps.last_error])
	return false


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _seconds(s: float) -> void:
	await create_timer(s).timeout


func _clear(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_clear(dir.path_join(d))
	DirAccess.remove_absolute(dir)


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL " + what)
