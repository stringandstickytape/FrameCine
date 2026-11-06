extends Node

## Android apps in a window on the big screen (docs/features.md, "Android apps"; the files, the commands and the log are
## in scripts/android/lepton.gd). One click in Files: the nested compositor, then the container, then the app, with the
## steps on the card, read from Lepton's log as it grows. Once up, the compositor's window goes on the big screen as a
## window:// source, exactly as a window would, and window_pointer.gd works it.
##
## The window on the big screen is the whole of the app's life, the user's decision: when it stops being the source for
## any reason (another file opened, the Files row, the menu's close, the app quitting) the app, the container and the
## compositor all stop, and nothing keeps playing behind. That is a look at the source on a timer, not a signal: a file on
## a share takes the source away seconds before file_opened comes. The player's own exit starts stop.sh and leaves it to
## finish; a crash leaves the marker, and the next run clears up. One app at a time: starting another stops the first.
##
## Nothing here blocks a frame: every command runs on a worker thread, and the logs are read on a timer, new bytes only.
## The status and the print lines hold steps and reasons, never anything from inside the app's data.
##
##   start_app(name) -> "" or why not, cancel(), stop_app(), back() -> {way, before, after}
##   state, step, last_error; status() -> Dictionary; is_app(name); on_big_screen()

signal changed

const Lepton := preload("res://scripts/android/lepton.gd")
const WindowVideoSource := preload("res://scripts/video/window_video_source.gd")
const WorkerTask := preload("res://scripts/dev/worker_task.gd")
const DevCommands := preload("res://scripts/dev/dev_commands.gd")

enum State { IDLE, STARTING, RUNNING, STOPPING }

const STATE_NAMES: Array[String] = ["idle", "starting", "running", "stopping"]
const TITLE := "Android apps"
const CARD_ID := "android"
## A worker's command, at most (the commands have their own limits, this is the backstop).
const JOB_TIMEOUT := 20.0
## B: a look, Back, a look, and maybe two more commands.
const BACK_TIMEOUT := 60.0
const READY_SECONDS := 4.0
const STOPPED_SECONDS := 3.0
const FAILED_SECONDS := 30.0
const NOT_STOPPED := "Android may still be running. It is cleared the next time an app starts."

## scripts/main.gd
var main: Node3D
## Stands in for the commands (the tests).
var runner: Object = Lepton.Runner.new()
## Puts a window path on the big screen. Tests: a stand-in, with no X display to capture.
var open_window: Callable
## How often the logs and the source are looked at, and the units asked (seconds).
var poll_seconds := 0.25
var unit_check_seconds := 3.0
## How long the compositor has to show its window, a whole start, and a whole stop. A first start installs the app, so
## allow far more than the 15 to 20 seconds of a later one.
var display_timeout := 20.0
var start_timeout := 180.0
var stop_timeout := 45.0
var state := State.IDLE
## What is happening now, in plain words.
var step := ""
## Why the last start failed, or "".
var last_error := ""
## The last B: {way, before, after}.
var last_back := {}
## {name, label, folder, apk} of the app starting, running or stopping; {} when idle.
var app := {}
## The app's Android package, once the log has named it.
var package := ""
## Bumped by anything that ends what is going on: a start's steps stop at their next look.
var _run := 0
## The compositor's X window, 0 until found.
var _window := 0
var _tail: Lepton.LogTail
## The steps done so far, for the card.
var _done: Array[String] = []
## The best reason in the log so far.
var _reason := ""
var _reason_is_error := false
## The app to start once the one on show has stopped.
var _queued := ""
## Starts of units on a worker thread: a stop waits for them, or it would miss a unit that comes up a moment later.
var _spawning := 0
var _poll := 0.0
var _unit_left := 0.0
var _unit_checking := false
var _back_busy := false
var _started_msec := 0
## The viewer put the card away, or another card took its place: steps go on in Files only.
var _card_gone := false
## Our own show_card() replacing our own card.
var _card_ours := false


func _ready() -> void:
	if not open_window.is_valid():
		open_window = func(path: String) -> void: main.open_path(path)
	main.file_opened.connect(_on_file_opened)
	if FileAccess.file_exists(Lepton.marker()):
		print("Android: an earlier run left the marker; clearing up")
		runner.launch(Lepton.stop_argv())


func _exit_tree() -> void:
	_run += 1
	# STOPPING has stop.sh running already.
	if state == State.STARTING or state == State.RUNNING:
		print("Android: the player is closing; stop.sh finishes without it")
		runner.launch(Lepton.stop_argv())


# --- What runs --------------------------------------------------------------------------------------------------------

func is_app(app_name: String) -> bool:
	return str(app.get("name", "")) == app_name


func label() -> String:
	return str(app.get("label", ""))


func _path() -> String:
	return WindowVideoSource.window_path(_window)


## Our window is the big screen's source.
func on_big_screen() -> bool:
	var src: Object = main.player.source if main.player != null else null
	return _window != 0 and src is WindowVideoSource and (src as WindowVideoSource).path == _path() \
			and (src as WindowVideoSource).window_id == _window


## What the Files place says about now, or "". `localised`: in the menus' language (docs/i18n.md), the steps marked
## i18n too; the app's name and the failure's own words stay as they are.
func status_line(localised := false) -> String:
	var t := func(s: String) -> String: return tr(s) if localised else s
	match state:
		State.STARTING, State.STOPPING:
			return "%s: %s ..." % [label(), t.call(step)]
		State.RUNNING:
			return t.call("%s is on the big screen") % label() # i18n
	return t.call("Last try: %s") % last_error.get_slice("\n", 0) if last_error != "" else "" # i18n


## For the dev link. Steps, names and reasons only.
func status() -> Dictionary:
	var names: Array[String] = []
	for a: Dictionary in Lepton.apps():
		names.append(str(a["name"]))
	return {"state": STATE_NAMES[state], "step": step, "app": str(app.get("name", "")), "package": package,
			"on_big_screen": on_big_screen(), "error": last_error, "missing": Lepton.missing(), "apps": names,
			"last_back": last_back}


# --- Starting ---------------------------------------------------------------------------------------------------------

## Starts the app in ~/Android/<name>/, if it isn't going already. Another app stops first. "" or why not, in plain words.
func start_app(app_name: String) -> String:
	var a := Lepton.find_app(app_name)
	if a.is_empty():
		return _refuse("There's no app called %s in ~/%s" % [app_name, Lepton.FOLDER])
	if bool(a["spaces"]):
		return _refuse("%s's APK has spaces in its file name, so it can't run yet" % app_name)
	var missing := Lepton.missing()
	if not missing.is_empty():
		return _refuse(" ".join(missing))
	if main.local_agents.x == null:
		return _refuse("No window capture here: Android apps need the desktop's display")
	if is_app(app_name) and (state == State.STARTING or state == State.RUNNING):
		return ""
	if state != State.IDLE:
		stop_app()
		_queued = app_name
		return ""
	_run += 1
	app = a
	package = ""
	last_error = ""
	state = State.STARTING
	_window = 0
	_done.clear()
	step = ""
	_reason = ""
	_reason_is_error = false
	_card_gone = false
	_started_msec = Time.get_ticks_msec()
	_start(_run)
	return ""


func _refuse(why: String) -> String:
	_note(why)
	return why


## The steps of a start, one after another. Each await can come back to a start that was cancelled.
func _start(run: int) -> void:
	_set_step("Getting ready") # i18n
	_show_card(true)
	var r := runner
	var left_over: Variant = await _job(func() -> Variant: return Lepton.units_alive(r))
	if not _live(run):
		return
	if left_over == true:
		_set_step("Clearing what was left from last time") # i18n
		var cleared: bool = await _stop_units(run)
		if not _live(run):
			return
		if not cleared:
			_fail("What was left from last time would not stop. Restart the headset if this keeps happening.")
			return
	var why := Lepton.prepare(app)
	if why != "":
		_fail(why)
		return
	_set_step("Starting the display") # i18n
	why = await _spawn(func() -> String: return Lepton.start_display(r))
	if not _live(run):
		return
	if why != "":
		_fail("The display did not start: %s" % why)
		return
	_window = await _wait_window(run)
	if not _live(run):
		return
	if _window == 0:
		_note_log(Lepton.LogTail.new(Lepton.display_log()))
		_fail("The display's window did not come within %d seconds.%s" % [display_timeout, _log_words()])
		return
	_set_step("Starting Android") # i18n
	_tail = Lepton.LogTail.new(Lepton.run_log())
	why = await _spawn(func() -> String: return Lepton.start_android(r))
	if not _live(run):
		return
	if why != "":
		_fail("Android did not start: %s" % why)
		return
	if not await _follow_log(run):
		return
	_set_step("Opening the app") # i18n
	if await _open_app(run, app["apk"], package):
		_show()


func _live(run: int) -> bool:
	return run == _run and is_inside_tree()


## Runs a command on a worker thread, the frame going on. High priority: the viewer is waiting, and a slow listing on a
## share mustn't hold it up. Its result, or null if it took too long.
func _job(f: Callable, timeout := JOB_TIMEOUT) -> Variant:
	var r: Dictionary = await WorkerTask.run(get_tree(), f, timeout, true)
	return r.get("result")


## Starts a unit on a worker thread. "" or the reason.
func _spawn(f: Callable) -> String:
	_spawning += 1
	var why: Variant = await _job(f)
	_spawning -= 1
	return str(why) if why != null else "it took too long"


## The compositor's window by its title (the agents' X connection and listing), or 0 after display_timeout.
func _wait_window(run: int) -> int:
	var deadline := Time.get_ticks_msec() + int(display_timeout * 1000.0)
	while _live(run):
		var id := Lepton.find_window(main.local_agents.x)
		if id != 0 or Time.get_ticks_msec() > deadline:
			return id
		await get_tree().create_timer(poll_seconds).timeout
	return 0


## Waits for Lepton's own launch, then brings the app forward if it stayed behind the Android launcher. With no process
## in time the window goes up as it is. False if the run ended: it failed, or was cancelled.
func _open_app(run: int, apk: String, pkg: String) -> bool:
	var r := runner
	var deadline := Time.get_ticks_msec() + int(Lepton.launch_seconds * 1000.0)
	var front_by := 0
	while _live(run):
		for line: String in _tail.new_lines():
			if Lepton.log_event(line).has("exited"):
				_fail("%s closed as soon as it started.%s" % [label(), _log_words()])
				return false
			_keep_reason(line)
		var top: Variant = await _job(func() -> Variant: return Lepton.top_activity(r, apk))
		var up: Variant = await _job(func() -> Variant: return Lepton.app_running(r, apk, pkg))
		if not _live(run):
			return false
		if str(top).contains(pkg + "/"):
			return true
		var now := Time.get_ticks_msec()
		if up == true and front_by == 0:
			front_by = now + int(Lepton.front_seconds * 1000.0)
		elif up == true and now > front_by:
			await _job(func() -> Variant: return Lepton.bring_forward(r, apk, pkg))
			return _live(run)
		elif up != true and now > deadline:
			return true
		await get_tree().create_timer(poll_seconds).timeout
	return false


## Follows Lepton's log to the line that names the package. False if the run ended: it failed, or was cancelled.
func _follow_log(run: int) -> bool:
	var deadline := _started_msec + int(start_timeout * 1000.0)
	var check_left := unit_check_seconds
	var r := runner
	while _live(run):
		for line: String in _tail.new_lines():
			var e := Lepton.log_event(line)
			if e.has("step"):
				_set_step(e["step"])
			elif e.has("package"):
				package = e["package"]
				return true
			elif e.has("exited"):
				_fail("%s closed as soon as it started.%s" % [label(), _log_words()])
				return false
			elif e.has("failed"):
				_keep_reason(line)
				_fail("Installing %s failed.%s" % [label(), _log_words()])
				return false
			else:
				_keep_reason(line)
		if Time.get_ticks_msec() > deadline:
			_fail("%s did not start within %d seconds.%s" % [label(), start_timeout, _log_words()])
			return false
		check_left -= poll_seconds
		if check_left <= 0.0:
			check_left = unit_check_seconds
			var alive: Variant = await _job(func() -> Variant: return Lepton.units_alive(r, [Lepton.APP_UNIT]))
			if not _live(run):
				return false
			if alive == false:
				_note_log(_tail)
				_fail("Android stopped before %s opened.%s" % [label(), _log_words()])
				return false
		await get_tree().create_timer(poll_seconds).timeout
	return false


## The rest of a log, for its reason.
func _note_log(tail: Lepton.LogTail) -> void:
	for line: String in tail.new_lines():
		_keep_reason(line)


## An error line beats any other, and a later line beats an earlier one of its kind.
func _keep_reason(line: String) -> void:
	var t := Lepton.reason_line(line)
	if t == "":
		return
	var is_error := Lepton.looks_like_error(t)
	if is_error or not _reason_is_error:
		_reason = t
		_reason_is_error = is_error


func _log_words() -> String:
	return " The log says: %s" % _reason if _reason != "" else ""


func _set_step(words: String) -> void:
	if words == step:
		return
	if step != "":
		_done.append(step)
	step = words
	print("Android: %s" % words)
	var card := _card()
	if card != null and not _card_gone and card.has_method("set_card_text"):
		card.set_card_text(CARD_ID, _card_text())
	changed.emit()


## The window goes on the big screen, the menu closes, and the app's life is the window's from here on.
func _show() -> void:
	state = State.RUNNING
	WindowVideoSource.named_windows[_window] = "Android: %s" % label()
	_poll = poll_seconds
	_unit_left = unit_check_seconds
	open_window.call(_path())
	if not on_big_screen():
		_fail("The window could not go on the big screen.")
		return
	if main.ui != null and main.ui.has_method("hide_panel"):
		main.ui.hide_panel()
	_set_step("Ready") # i18n
	_show_card(false, READY_SECONDS, _card_text(false))
	changed.emit()


func _process(delta: float) -> void:
	if state != State.RUNNING:
		return
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = poll_seconds
	if not on_big_screen():
		stop_app()
		return
	for line: String in _tail.new_lines():
		if Lepton.log_event(line).has("exited"):
			_app_ended()
			return
	_unit_left -= poll_seconds
	if _unit_left <= 0.0:
		_unit_left = unit_check_seconds
		_check_unit()


## The app can end without a word in the log, if the unit was killed.
func _check_unit() -> void:
	if _unit_checking:
		return
	_unit_checking = true
	var run := _run
	var r := runner
	var alive: Variant = await _job(func() -> Variant: return Lepton.units_alive(r, [Lepton.APP_UNIT]))
	_unit_checking = false
	if _live(run) and state == State.RUNNING and alive == false:
		_app_ended()


func _app_ended() -> void:
	stop_app("%s has closed." % label())


## A new file opened while an app starts: the viewer has moved on.
func _on_file_opened(path: String) -> void:
	if state == State.STARTING and path != "":
		stop_app("%s stopped: something else was opened." % label())


# --- Stopping ---------------------------------------------------------------------------------------------------------

## Cancel on the card or in Files.
func cancel() -> void:
	if state == State.STARTING:
		stop_app("Cancelled.")


## Stops the app, the container and the compositor. The picture leaves the screen if it is still there; a window that
## has lost the screen already just goes. closing: what the card says at the end.
func stop_app(closing := "") -> void:
	_queued = ""
	if state == State.IDLE or state == State.STOPPING:
		return
	_run += 1
	state = State.STOPPING
	if _window != 0 and main.current_path == _path():
		main.close_media()
	_done.clear()
	step = ""
	_stop(_run, closing if closing != "" else "%s has stopped." % label())


func _stop(run: int, closing: String) -> void:
	_set_step("Stopping %s" % label())
	# Out of the way of what is playing now: no buttons, and a card that is someone else's stays.
	var card := _card()
	_card_gone = card != null and card.is_showing() and card.id != CARD_ID
	_show_card(false)
	while _spawning > 0 and _live(run):
		await get_tree().process_frame
	if not _live(run):
		return
	var stopped: bool = await _stop_units(run)
	if not _live(run):
		return
	WindowVideoSource.named_windows.erase(_window)
	_window = 0
	if not stopped:
		last_error = (last_error + " " + NOT_STOPPED).strip_edges()
	if last_error != "":
		_show_failure()
	elif _card_gone:
		_note(closing)
	else:
		_show_card(false, STOPPED_SECONDS, closing)
	state = State.IDLE
	app = {}
	package = ""
	step = ""
	changed.emit()
	if _queued != "":
		var next := _queued
		_queued = ""
		start_app(next)


## stop.sh in its own unit, followed through its log. True when it says everything has gone.
func _stop_units(run: int) -> bool:
	var tail := Lepton.LogTail.new(Lepton.stop_log())
	var r := runner
	var a := app
	var why: Variant = await _job(func() -> Variant: return Lepton.start_stop(r, a))
	if not _live(run) or str(why) != "":
		return false
	var deadline := Time.get_ticks_msec() + int(stop_timeout * 1000.0)
	while _live(run):
		for line: String in tail.new_lines():
			var words := line.strip_edges()
			if words == Lepton.STOPPED:
				return true
			if words == Lepton.STILL_RUNNING:
				return false
			if words != "":
				_set_step(words)
		if Time.get_ticks_msec() > deadline:
			return false
		await get_tree().create_timer(poll_seconds).timeout
	return false


## A start that failed: what was started goes, then the reason stays on the card. The player can't tell more than the
## log does.
func _fail(why: String) -> void:
	print("Android: failed: %s" % why)
	last_error = why
	stop_app()


func _show_failure() -> void:
	if _card() == null:
		_note(last_error)
		return
	_card_gone = false
	_show_card(false, FAILED_SECONDS, last_error)


# --- B ----------------------------------------------------------------------------------------------------------------

## B on this window (Lepton.back_now(), unverified on the device): off the main thread, one at a time.
func back() -> Dictionary:
	if state != State.RUNNING or _back_busy:
		return {"way": "none", "before": "", "after": ""}
	_back_busy = true
	var r := runner
	var apk: String = app["apk"]
	var pkg := package
	var got: Variant = await _job(func() -> Variant: return Lepton.back_now(r, apk, pkg), BACK_TIMEOUT)
	_back_busy = false
	last_back = got if got is Dictionary else {"way": "none", "before": "", "after": ""}
	print("Android: B went by %s" % last_back["way"])
	return last_back


# --- The card ---------------------------------------------------------------------------------------------------------

func _card() -> Node:
	var card: Node = main.ui.get("card") if main.get("ui") != null else null
	return card if card != null and card.has_method("show_card") else null


## The steps done, then the one going on: a last line ending " ..." dances on the card.
func _card_text(live := true) -> String:
	var lines := _done.duplicate()
	lines.append(step + (" ..." if live else ""))
	return "\n".join(lines)


func _show_card(with_cancel: bool, seconds := 0.0, text := "") -> void:
	var card := _card()
	if card == null or _card_gone:
		return
	if card.has_signal("dismissed") and not card.dismissed.is_connected(_on_card_dismissed):
		card.dismissed.connect(_on_card_dismissed)
	var data := {"id": CARD_ID, "title": "%s: %s" % [TITLE, label()] if label() != "" else TITLE,
			"text": text if text != "" else _card_text(), "seconds": seconds}
	if with_cancel:
		data["actions"] = [{"id": "cancel", "label": "Cancel"}]
	_card_ours = true
	card.show_card(data)
	_card_ours = false


func _on_card_dismissed(id: String, how: String) -> void:
	if id != CARD_ID or _card_ours:
		return
	if how == "cancel":
		cancel()
	elif how in ["user", "replaced"]:
		_card_gone = true


func _note(text: String) -> void:
	if main.get("ui") != null and main.ui.has_method("notify"):
		main.ui.notify(text)
	else:
		print("Android: " + text)


# --- The dev link -----------------------------------------------------------------------------------------------------

## The Android apps place as commands, for the dev link and (level apps) an assistant: its rows run the same functions.
## An app's name is its folder's name, the user's own; nothing here names an app.
static func register_commands(cmd_host: Node) -> void:
	DevCommands.register("android_status", func(_args: Dictionary, _ctx: DevCommands.Call) -> Variant:
		return cmd_host.main.android_apps.status(), {
		"description": "The Android apps place: the apps in ~/Android (by folder name), what is missing to run them, "
				+ "the state (idle, starting, running, stopping), the step of a start, the app on show, the last "
				+ "failure and what the last Back did.",
		"returns": "{state, step, app, package, on_big_screen, error, missing, apps, last_back}", "assistant": "read"})
	DevCommands.register("android_start", func(args: Dictionary, ctx: DevCommands.Call) -> Variant:
		var why: String = cmd_host.main.android_apps.start_app(args["name"])
		if why != "":
			return ctx.fail(why)
		ctx.summary = "Android: %s" % args["name"]
		return cmd_host.main.android_apps.status(), {
		"description": "Starts an Android app and puts it on the big screen, as its row in the Android apps place "
				+ "does; one that runs already stops first. A start takes 15 seconds or more: android_status follows it.",
		"params": [{"name": "name", "type": "string", "required": true,
				"description": "the app's folder name, as android_status lists it in apps"}],
		"level": "control", "returns": "android_status: it goes on in the background", "assistant": "apps"})
	DevCommands.register("android_stop", func(_args: Dictionary, ctx: DevCommands.Call) -> Variant:
		cmd_host.main.android_apps.stop_app()
		ctx.summary = "Android stopped"
		return cmd_host.main.android_apps.status(), {
		"description": "Stops the Android app on the big screen and everything under it, or cancels a start, as the "
				+ "place's Stop and Cancel rows do.",
		"level": "control", "returns": "android_status: it goes on in the background", "assistant": "apps"})
	DevCommands.register("android_back", func(_args: Dictionary, ctx: DevCommands.Call) -> Variant:
		ctx.summary = "Android: Back"
		return await cmd_host.main.android_apps.back(), {
		"description": "What B does on an Android window: Android Back, then the app's start screen if Back left it "
				+ "where it was.",
		"level": "control", "returns": "{way: back | launcher | none, before, after}", "assistant": "apps"})
