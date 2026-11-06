extends RefCounted

## Android apps through Lepton, Valve's Steam tool: an APK in a podman Android 11 container (docs/features.md, "Android
## apps"). This file knows what is on disk, the scripts the app writes, the commands and what Lepton's log means;
## scripts/android/android_apps.gd is the running side (the steps, the card, the big screen).
##
## Each folder ~/Android/<name>/ holding an .apk is an app, labelled from the folder's name. The app adds
## lepton-show-flatscreen there (Lepton hides its flat window without it), and keeps ~/Android/.player/ for itself:
##   display.sh   the nested compositor. Android draws to a Wayland socket and the capture is X11: this gives it a window
##   run.sh       lepton start, with the environment it needs
##   stop.sh      stops the app, the container and the compositor, in that order; safe to run at any time
##   run.log      Lepton's output, which the steps are read from; display.log and stop.log likewise
##   running      exists from the start until stop.sh has finished: a crash leaves it, and the next run clears up
##
## All of it runs in `systemd-run --user` units, as the normal user: Lepton fails from a plain background process, and a
## unit finishes its work if the player has gone. Nothing here reads anything from inside the app's data: `lepton exec`
## output is used for one line and dropped, and stop.sh sends it to /dev/null.

const AgentTerminal := preload("res://scripts/agents/agent_terminal.gd")

const FOLDER := "Android"
const PLAYER_DIR := ".player"
const LEPTON := ".local/share/Steam/steamapps/common/Lepton/lepton"
const COMPOSITOR := "/usr/bin/kwin_wayland"
const SHOW_FILE := "lepton-show-flatscreen"
const SOCKET := "wl-android"
const WIDTH := 1920
const HEIGHT := 1080
## The nested compositor's window has no class: "KDE Wayland Compositor - Press right control key to grab input".
const WINDOW_TITLE := "KDE Wayland Compositor"
const DISPLAY_UNIT := "frame-android-display"
const APP_UNIT := "frame-android-app"
const STOP_UNIT := "frame-android-stop"
## What the desktop session has on the Frame, when the app was started without it.
const RUNTIME_DIR := "/run/user/1000"
const X_DISPLAY := ":0"
## stop.sh's last line.
const STOPPED := "Stopped"
const STILL_RUNNING := "Still running"
## A `lepton exec` that hangs is killed after this long.
const EXEC_SECONDS := 10
## Wait for Android Back to land before looking at the top activity again.
const BACK_SETTLE_MSEC := 800
## Lepton's log lines and the step each one means, in the order they come. "Waiting for app <package> to exit..." ends the
## list: the app is running. "Exited!" ends the run.
const LOG_STEPS: Array = [["Launching ", "Starting Android"], ["Waiting for boot", "Starting Android"],
		["Boot complete", "Android is up"], ["Installing", "Preparing the app"],
		["Performing Streamed Install", "Preparing the app"]]
const LOG_WAITING := "Waiting for app "
const LOG_EXITED := "Exited!"
## A line with one of these is the reason a start failed.
const ERROR_WORDS: Array[String] = ["error", "fail", "cannot", "can't", "denied", "not found", "no such"]
## A line with one of these never reaches the card or the dev link: it isn't the app's to pass on.
const PRIVATE_WORDS: Array[String] = ["password", "token", "cookie", "login", "secret", "auth", "session"]
const REASON_MAX := 120
const READ_MAX := 65536

## Tests: another compositor program.
static var compositor := COMPOSITOR
## Lepton's launch comes up to about ten seconds after its "Waiting for app" line, when Android's storage is mounted: how
## long to wait for the app's process, and then how long the app has to come to the front (seconds). Tests: shorter.
static var launch_seconds := 20.0
static var front_seconds := 3.0


## Runs the commands: tests stand in for it. run() waits, so only on a worker thread.
class Runner extends RefCounted:
	## {code, out}: stdout and stderr together.
	func run(argv: Array[String]) -> Dictionary:
		var out: Array = []
		var code := OS.execute(argv[0], PackedStringArray(argv.slice(1)), out, true)
		return {"code": code, "out": str(out[0]) if not out.is_empty() else ""}

	## Doesn't wait: for the player's own exit.
	func launch(argv: Array[String]) -> int:
		return OS.create_process(argv[0], PackedStringArray(argv.slice(1)))


## A growing log, read on a timer from where the last read stopped. A line still being written waits for its end.
class LogTail extends RefCounted:
	var path := ""
	var offset := 0
	var _partial := ""

	func _init(log_path: String) -> void:
		path = log_path

	## The whole lines added since the last call.
	func new_lines() -> Array[String]:
		var out: Array[String] = []
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			return out
		var size := f.get_length()
		if size < offset:
			offset = 0
			_partial = ""
		if size == offset:
			return out
		f.seek(offset)
		var bytes := f.get_buffer(mini(size - offset, READ_MAX))
		offset += bytes.size()
		var parts := (_partial + bytes.get_string_from_utf8()).split("\n")
		_partial = parts[parts.size() - 1]
		for i in parts.size() - 1:
			out.append(parts[i])
		return out


static func folder() -> String:
	return AgentTerminal.home().path_join(FOLDER)


static func player_dir() -> String:
	return folder().path_join(PLAYER_DIR)


static func lepton() -> String:
	return AgentTerminal.home().path_join(LEPTON)


static func run_log() -> String:
	return player_dir().path_join("run.log")


static func stop_log() -> String:
	return player_dir().path_join("stop.log")


static func display_log() -> String:
	return player_dir().path_join("display.log")


static func marker() -> String:
	return player_dir().path_join("running")


static func runtime_dir() -> String:
	var d := OS.get_environment("XDG_RUNTIME_DIR")
	return d if d != "" else RUNTIME_DIR


static func x_display() -> String:
	var d := OS.get_environment("DISPLAY")
	return d if d != "" else X_DISPLAY


## What is missing to run any app here, in plain words (one line a row), or []. English (android_status, an
## assistant), or with `localised` in the menus' language (the Files place; docs/i18n.md).
static func missing(localised := false) -> Array[String]:
	if not FileAccess.file_exists(lepton()):
		return [_t("Lepton isn't on this headset.", localised), # i18n
				_t("Install the Lepton tool from Steam, then come back here.", localised)] # i18n
	if not FileAccess.file_exists(compositor):
		return [_t("The compositor isn't on this headset (%s).", localised) % compositor] # i18n
	return []


## How to add an app, in plain words (one line a row). `localised` as for missing().
static func how_to_add(localised := false) -> Array[String]:
	return [_t("No Android apps yet.", localised), # i18n
			_t("Put an APK in a folder of its own: ~/%s/<name>/app.apk", localised) % FOLDER, # i18n
			_t("The folder's name is the name shown here.", localised)] # i18n


static func _t(text: String, localised: bool) -> String:
	return TranslationServer.translate(text) if localised else text


## The apps, by folder name: [{name, label, folder, apk}], in order. spaces: the APK's file name has spaces, so it can't
## run yet (its files stay as they are).
static func apps() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(folder()):
		return out
	var names := Array(DirAccess.get_directories_at(folder()))
	names.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	for n: String in names:
		if n.begins_with("."):
			continue
		var dir := folder().path_join(n)
		var apks: Array[String] = []
		for f in DirAccess.get_files_at(dir):
			if f.get_extension().to_lower() == "apk":
				apks.append(f)
		if apks.is_empty():
			continue
		apks.sort()
		out.append({"name": n, "label": n, "folder": dir, "apk": dir.path_join(apks[0]), "spaces": " " in apks[0]})
	return out


static func find_app(app_name: String) -> Dictionary:
	for a: Dictionary in apps():
		if a["name"] == app_name:
			return a
	return {}


## The folder exists from the start, so the words on screen are true.
static func ensure_folder() -> void:
	DirAccess.make_dir_recursive_absolute(folder())


# --- The scripts ------------------------------------------------------------------------------------------------------

## One argument for a shell. Folder names are the user's, so anything may be in them.
static func quoted(text: String) -> String:
	return "'" + text.replace("'", "'\\''") + "'"


static func display_text() -> String:
	return "#!/bin/sh\n# Written by the VR video player. The nested compositor: Android draws to its Wayland socket, " \
			+ "and it gives\n# the player's capture an X window.\n" \
			+ "export DISPLAY=%s\nexport XDG_RUNTIME_DIR=%s\nunset WAYLAND_DISPLAY\n" % [quoted(x_display()),
			quoted(runtime_dir())] \
			+ "exec %s --x11-display %s --socket %s --width %d --height %d >>%s 2>&1\n" % [quoted(compositor),
			quoted(x_display()), SOCKET, WIDTH, HEIGHT, quoted(display_log())]


## IS_PARENT skips `setpgid --foreground`, which needs a terminal.
static func run_text(app: Dictionary) -> String:
	return "#!/bin/sh\n# Written by the VR video player. Runs in a systemd unit: Lepton fails from a plain background " \
			+ "process.\n" \
			+ "export XDG_RUNTIME_DIR=%s\nexport GAMESCOPE_WAYLAND_DISPLAY=%s\n" % [quoted(runtime_dir()), SOCKET] \
			+ "export STEAM_COMPAT_INSTALL_PATH=%s\nexport IS_PARENT=true\nexport TERM=dumb\n" % quoted(app["folder"]) \
			+ "exec %s start %s >>%s 2>&1\n" % [quoted(lepton()), quoted(app["apk"]), quoted(run_log())]


## Force-stop first: the app's login survives that. The package comes from the run's own log, so a stop after a crash
## needs nothing from the player. Before the app has a package (still booting) there is nothing to force-stop.
static func stop_text(app: Dictionary) -> String:
	var unit := APP_UNIT
	var s := "#!/bin/sh\n# Written by the VR video player. Stops the Android app, its container and the compositor, and " \
			+ "is safe\n# to run at any time. A unit of its own, so it finishes if the player has gone.\n"
	s += "export XDG_RUNTIME_DIR=%s\nexport TERM=dumb\n" % quoted(runtime_dir())
	s += "say() { printf '%%s\\n' \"$1\" >>%s; }\n" % quoted(stop_log())
	s += "alive() { case \"$(systemctl --user is-active \"$1\")\" in inactive|failed|unknown|'') return 1 ;; esac; " \
			+ "return 0; }\n"
	s += "if alive %s; then\n" % unit
	s += "  pkg=$(sed -n 's/.*%s\\([^ ]*\\) to exit.*/\\1/p' %s | tail -n 1)\n" % [LOG_WAITING, quoted(run_log())]
	s += "  if [ -n \"$pkg\" ]; then\n    say 'Stopping the app'\n"
	s += "    timeout %d %s exec %s cmd activity force-stop \"$pkg\" >/dev/null 2>&1\n" % [EXEC_SECONDS,
			quoted(lepton()), quoted(app["apk"])]
	s += "    n=0\n    while alive %s && [ \"$n\" -lt 20 ]; do sleep 0.5; n=$((n + 1)); done\n  fi\n" % unit
	s += "  if alive %s; then\n    say 'Stopping Android'\n" % unit
	s += "    timeout 15 systemctl --user stop %s || systemctl --user kill --signal=SIGKILL %s\n  fi\nfi\n" % [unit, unit]
	s += "say 'Stopping the display'\n"
	s += "timeout 10 systemctl --user stop %s || systemctl --user kill --signal=SIGKILL %s\n" % [DISPLAY_UNIT,
			DISPLAY_UNIT]
	s += "if alive %s || alive %s; then\n  say '%s'\n  exit 1\nfi\n" % [unit, DISPLAY_UNIT, STILL_RUNNING]
	s += "systemctl --user reset-failed %s %s 2>/dev/null\nrm -f %s\nsay '%s'\n" % [unit, DISPLAY_UNIT,
			quoted(marker()), STOPPED]
	return s


## Everything a start needs: the show file in the app's folder, the scripts, empty logs, the marker. "" or the reason.
static func prepare(app: Dictionary) -> String:
	var dir := player_dir()
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		return "could not make %s" % dir
	FileAccess.set_unix_permissions(dir, FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER
			| FileAccess.UNIX_EXECUTE_OWNER)
	var show_file := str(app["folder"]).path_join(SHOW_FILE)
	if not FileAccess.file_exists(show_file) and not _write(show_file, ""):
		return "could not write %s" % show_file
	if not (_write(dir.path_join("display.sh"), display_text(), true) and _write(dir.path_join("run.sh"), run_text(app),
			true) and _write(dir.path_join("stop.sh"), stop_text(app), true)):
		return "could not write the scripts in %s" % dir
	_write(run_log(), "")
	_write(display_log(), "")
	_write(marker(), "")
	return ""


static func _write(path: String, text: String, executable := false) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	if executable:
		FileAccess.set_unix_permissions(path, FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER
				| FileAccess.UNIX_EXECUTE_OWNER)
	return true


# --- The commands: these wait, so only on a worker thread -------------------------------------------------------------

## Started from Steam the player has SteamAppId, which Lepton takes as the context of the call, and Steam's overlay in
## LD_PRELOAD: a `lepton exec` then finds no container.
static func _env() -> Array[String]:
	return ["env", "-u", "SteamAppId", "-u", "SteamGameId", "-u", "LD_PRELOAD", "XDG_RUNTIME_DIR=" + runtime_dir(),
			"TERM=dumb"]


static func unit_argv(unit: String, script: String) -> Array[String]:
	var argv := _env()
	argv.append_array(["systemd-run", "--user", "--unit=" + unit, "--collect", script])
	return argv


## Starts a script in a unit. "" or the reason.
static func start_unit(runner: Object, unit: String, script: String) -> String:
	var r: Dictionary = runner.run(unit_argv(unit, script))
	if int(r["code"]) == 0:
		return ""
	var why := reason_line(last_line(str(r["out"])))
	return why if why != "" else "systemd-run said no (%d)" % int(r["code"])


static func start_display(runner: Object) -> String:
	return start_unit(runner, DISPLAY_UNIT, player_dir().path_join("display.sh"))


static func start_android(runner: Object) -> String:
	return start_unit(runner, APP_UNIT, player_dir().path_join("run.sh"))


## Starts stop.sh. Written for `app` if no run ever wrote one. "" or the reason; one already running counts.
static func start_stop(runner: Object, app: Dictionary) -> String:
	var script := player_dir().path_join("stop.sh")
	if not FileAccess.file_exists(script):
		DirAccess.make_dir_recursive_absolute(player_dir())
		_write(script, stop_text(app), true)
	_write(stop_log(), "")
	var why := start_unit(runner, STOP_UNIT, script)
	return "" if why == "" or units_alive(runner, [STOP_UNIT]) else why


## Any of the units alive, by systemctl's word for each. Nothing answering counts as none.
static func units_alive(runner: Object, units: Array[String] = [APP_UNIT, DISPLAY_UNIT]) -> bool:
	var argv := _env()
	argv.append_array(["systemctl", "--user", "is-active"])
	argv.append_array(units)
	var r: Dictionary = runner.run(argv)
	for line in str(r["out"]).split("\n"):
		if line.strip_edges() in ["active", "activating", "deactivating", "reloading"]:
			return true
	return false


## `lepton exec`: root inside the container. It fails if no container runs, printing a context name, so callers go by
## what the output says, not the exit code.
static func exec(runner: Object, apk: String, args: Array[String]) -> Dictionary:
	var argv := _env()
	argv.append_array(["timeout", str(EXEC_SECONDS), lepton(), "exec", apk])
	argv.append_array(args)
	return runner.run(argv)


## The app's launcher activity as package/.Class, or "".
static func launcher_activity(runner: Object, apk: String, package: String) -> String:
	var line := last_line(str(exec(runner, apk, ["cmd", "package", "resolve-activity", "--brief", "-c",
			"android.intent.category.LAUNCHER", "-a", "android.intent.action.MAIN", package])["out"]))
	return line if line.begins_with(package + "/") else ""


## True if the app has a process. Before it has, Lepton's launch is still to come.
static func app_running(runner: Object, apk: String, package: String) -> bool:
	return last_line(str(exec(runner, apk, ["pidof", package])["out"])).get_slice(" ", 0).is_valid_int()


## The app sometimes stays behind the Android launcher: brings it forward. True if there was something to start. Only
## once app_running(): Lepton's launch force-stops the app first, and the app's process dying ends the container.
static func bring_forward(runner: Object, apk: String, package: String) -> bool:
	var activity := launcher_activity(runner, apk, package)
	if activity == "":
		return false
	exec(runner, apk, ["cmd", "activity", "start-activity", "-n", activity])
	return true


## The top activity, or "" (no container, or no such line).
static func top_activity(runner: Object, apk: String) -> String:
	return top_of(str(exec(runner, apk, ["dumpsys", "activity", "activities"])["out"]))


## The record on the first ResumedActivity line: ActivityRecord{hash user package/.Class task}. Only that: the rest of
## the dump is the app's own.
static func top_of(dump: String) -> String:
	for line in dump.split("\n"):
		var i := line.find("ResumedActivity")
		if i < 0:
			continue
		var from := line.find("ActivityRecord{", i)
		var to := line.find("}", from)
		if from >= 0 and to > from:
			return line.substr(from, to - from + 1)
	return ""


## Back worked: the top activity is known both ways and it changed. Anything else, and B falls back.
static func back_worked(before: String, after: String) -> bool:
	return before != "" and after != "" and before != after


## B on an Android window (req: a dependable way out of a full-screen player). UNVERIFIED ON THE DEVICE: input injection
## is unknown here. `input` has to go through sh; a full-screen player showed no effect from keyevent 4 by hand, which
## may be the injection or the app. So: Android Back, then a look at the top activity; if it didn't change, the app's
## launcher activity with --activity-clear-top, which did leave a player by hand. Adjust the commands here after a real
## test. {way: back | launcher | none, before, after}.
static func back_now(runner: Object, apk: String, package: String) -> Dictionary:
	if not units_alive(runner, [APP_UNIT]):
		return {"way": "none", "before": "", "after": ""}
	var before := top_activity(runner, apk)
	exec(runner, apk, ["sh", "/system/bin/input", "keyevent", "4"])
	OS.delay_msec(BACK_SETTLE_MSEC)
	var after := top_activity(runner, apk)
	if back_worked(before, after):
		return {"way": "back", "before": before, "after": after}
	var activity := launcher_activity(runner, apk, package)
	if activity == "":
		return {"way": "none", "before": before, "after": after}
	exec(runner, apk, ["cmd", "activity", "start-activity", "--activity-clear-top", "-n", activity])
	return {"way": "launcher", "before": before, "after": after}


## What the player's exit runs: doesn't wait, and stop.sh goes on without the player.
static func stop_argv() -> Array[String]:
	return unit_argv(STOP_UNIT, player_dir().path_join("stop.sh"))


# --- The log ----------------------------------------------------------------------------------------------------------

static func last_line(text: String) -> String:
	var lines := text.strip_edges().split("\n")
	return lines[lines.size() - 1].strip_edges()


## What a line of Lepton's log means: {step: words}, {package: name}, {exited: true}, {failed: true}, or {}.
static func log_event(line: String) -> Dictionary:
	if LOG_WAITING in line:
		return {"package": line.get_slice(LOG_WAITING, 1).get_slice(" ", 0)}
	if LOG_EXITED in line:
		return {"exited": true}
	if line.strip_edges().begins_with("Failure") or "INSTALL_FAILED" in line:
		return {"failed": true}
	for s: Array in LOG_STEPS:
		if str(s[0]) in line:
			return {"step": s[1]}
	return {}


## A log line made fit to show: one short line, or "" if there is nothing in it to show.
static func reason_line(line: String) -> String:
	var t := line.strip_escapes().strip_edges()
	for w in PRIVATE_WORDS:
		if w in t.to_lower():
			return ""
	return t.left(REASON_MAX)


static func looks_like_error(line: String) -> bool:
	var t := line.to_lower()
	for w in ERROR_WORDS:
		if w in t:
			return true
	return false


# --- The window -------------------------------------------------------------------------------------------------------

## The nested compositor's window among an X11WindowSource's windows, by its title, or 0.
static func find_window(win: Object) -> int:
	for e: Dictionary in win.call("list_windows"):
		if WINDOW_TITLE in str(e.get("title", "")):
			return int(e.get("id", 0))
	return 0
