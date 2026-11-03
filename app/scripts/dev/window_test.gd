extends Node

## --window-test: the Browser place and the window source end to end on an X11 desktop (WSLg, or the device) with an
## engine that has X11WindowSource. Instead of the browser it launches a stand-in given with --browser-command (the
## spike's test window, spikes/05-window/testwin, which logs the input it gets) and --browser-match. Checks: the
## Browser place lists the desktop's windows; a page opens, the menu waits for the window, the RGB picture is on the
## screen in flat mono; the overlay shows updates/s and damage; mouse, keys and the controller's mapping reach the
## window; the labels change; closing closes only a window the player launched; a window that goes away ends the
## source. Prints PASS / FAIL lines and quits with the number of failures as the exit code.
## Example: godot --xr-mode off --path app -- --window-test --browser-command="<abs>/testwin --fps=30"
##          --browser-match=x11window-test

const VideoMode := preload("res://scripts/video_mode.gd")
const PaneUI := preload("res://ui/pane_ui.gd")
const WindowVideoSource := preload("res://scripts/video/window_video_source.gd")

const TEST_URL := "about:blank"

var main: Node
var _failures := 0
var _checks := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await _frames(5)
	if not WindowVideoSource.is_available():
		print("Window test: skipped, this engine build has no X11WindowSource")
		main.get_tree().quit(0)
		return
	if WindowVideoSource.browser_command.is_empty():
		print("Window test: needs --browser-command (a stand-in for the browser, e.g. the spike's testwin)")
		main.get_tree().quit(1)
		return
	var ui: PaneUI = main.ui.ui
	main.ui.show_panel()
	await _frames(2)

	# The Browser place.
	ui.files.open_folder("browser://")
	await _frames(2)
	_check("Browser place lists 'Open a web page'", _row(ui.files, "+ Open a web page") != null)
	_check("Browser place lists the desktop windows", _row(ui.files, "Desktop windows") != null)

	# A page: the menu stays ("Starting the browser...") until the window is captured, then hides.
	ui.files.file_selected.emit(WindowVideoSource.browser_path(TEST_URL))
	var src: WindowVideoSource = main.player.source as WindowVideoSource
	_check("browser:// opens the window source", src != null)
	if src == null:
		_finish()
		return
	_check("menu stays while the browser starts", main.ui.docked and not src.has_frame())
	_check("screen hidden while the browser starts", not main.screen.is_shown())
	var t0 := Time.get_ticks_msec()
	while not src.has_frame() and not src.is_ended() and Time.get_ticks_msec() - t0 < 25000:
		await _frames(1)
	_check("the launched window is captured (%d ms)" % (Time.get_ticks_msec() - t0), src.has_frame() and src.launched)
	if not src.has_frame():
		print("  error: %s" % src.last_error)
		_finish()
		return
	await _frames(3)
	_check("menu hides once the window shows", not main.ui.docked)
	var mat: ShaderMaterial = main.screen.material
	_check("screen shows the window's RGB texture", main.screen.is_shown()
			and bool(mat.get_shader_parameter("rgb_source")) and mat.get_shader_parameter("rgb_tex") == src.get_rgb_texture()
			and src.get_rgb_texture() != null)
	_check("flat mono, from the window", main.mode_source == "window" and main.mode.to_id() == VideoMode.new().to_id())
	var size := src.get_size()
	var flat: Vector2 = main.screen.get_flat_size()
	_check("screen aspect = window aspect (%dx%d)" % [size.x, size.y],
			absf(flat.x / flat.y - float(size.x) / size.y) < 0.01)
	main._overlay_text()
	await _seconds(1.0)
	var text: String = main._overlay_text()
	print(text)
	_check("overlay shows updates/s and damage", "updates/s" in text and "damage" in text)
	var stats := src.get_stats()
	_check("frames are updating (%d)" % int(stats.get("frames_updated", 0)), int(stats.get("frames_updated", 0)) > 5)

	# The laser / mouse mapping: the screen centre is the window centre.
	var cam: Camera3D = main.camera
	var centre: Vector3 = main.screen.global_position
	var hit: Dictionary = main.window_pointer.ray_to_window(cam.global_position, (centre - cam.global_position).normalized())
	_check("screen centre maps to the window centre (%s)" % hit.get("pixel"),
			not hit.is_empty() and (hit["pixel"] as Vector2).distance_to(Vector2(size) / 2.0) < 2.0)
	var corner: Vector3 = main.screen.global_transform * Vector3(-flat.x * 0.25, flat.y * 0.25, 0.0)
	hit = main.window_pointer.ray_to_window(cam.global_position, (corner - cam.global_position).normalized())
	_check("upper-left quarter point maps to (w/4, h/4) (%s)" % hit.get("pixel"),
			not hit.is_empty() and (hit["pixel"] as Vector2).distance_to(Vector2(size) / 4.0) < 2.0)

	# Desktop mouse and keyboard.
	var inputs := int(src.get_stats().get("input_events", 0))
	var at := cam.unproject_position(centre)
	await _mouse_button(at, MOUSE_BUTTON_LEFT)
	var after := int(src.get_stats().get("input_events", 0))
	_check("mouse click on the screen goes to the window (%d events)" % (after - inputs), after - inputs >= 3)
	_check("the click didn't start looking around", not main._mouse_look)
	inputs = after
	await _key(KEY_M, "m".unicode_at(0))
	await _key(KEY_ESCAPE, 0)
	after = int(src.get_stats().get("input_events", 0))
	_check("keys go to the window, M and Esc included (%d events)" % (after - inputs), after - inputs >= 4)
	_check("M typed into the window didn't open the menu", not main.ui.docked)

	# The controllers' mapping (no XR here: called as main.gd does).
	var right: Node = main.right_hand
	var left: Node = main.left_hand
	main.window_pointer.pointer = Vector2(size) / 2.0
	inputs = int(src.get_stats().get("input_events", 0))
	_check("right trigger is taken by the window", main.window_pointer.on_trigger(right, true))
	main.window_pointer.on_trigger(right, false)
	_check("squeeze tap is a right click", main.window_pointer.on_grip_tap(right))
	_check("right stick scrolls", main.window_pointer.on_stick(right, Vector2(0.0, -1.0), 0.1))
	_check("A is Space", main.window_pointer.on_button(right, "next_file"))
	_check("B is Back", main.window_pointer.on_button(right, "prev_file"))
	after = int(src.get_stats().get("input_events", 0))
	_check("controller input reached the window (%d events)" % (after - inputs), after - inputs >= 8)
	_check("left trigger does nothing on a window", main.window_pointer.on_trigger(left, true)
			and main.player.is_playing())
	_check("left stick still moves the screen", not main.window_pointer.on_stick(left, Vector2(0.0, 1.0), 0.1))
	var labels: Dictionary = main.controller_labels(main.PREVIEW_PROFILE, "right", false, true)
	_check("right labels for the window (%s)" % labels.get("trigger"), labels.get("trigger") == "CLICK"
			and labels.get("a") == "SPACE" and labels.get("b") == "BACK")
	labels = main.controller_labels(main.PREVIEW_PROFILE, "left", false, true)
	_check("left labels drop the trigger (%s)" % labels, not labels.has("trigger") and labels.get("squeeze") == "MOVE SCREEN")

	# The menu takes the input back while shown.
	main.ui.show_panel()
	await _frames(2)
	_check("menu shown: the window gives up the input", not main.window_pointer.is_active())
	ui.files.open_folder("browser://")
	await _frames(2)
	_check("Browser place offers 'Stop showing'", _row(ui.files, "Stop showing") != null)
	var launched_pid := src.launched_pid

	# A window that is already open: captured, and left open on close.
	var command: Array[String] = WindowVideoSource.browser_command
	var pid := OS.create_process(command[0], ["--title=already-open", "--fps=10"])
	var existing := 0
	t0 = Time.get_ticks_msec()
	while existing == 0 and Time.get_ticks_msec() - t0 < 10000:
		await _seconds(0.25)
		for w: Dictionary in WindowVideoSource.list_desktop_windows()["windows"]:
			if w["title"] == "already-open":
				existing = w["id"]
	_check("a window opened outside the player is listed", existing != 0)
	ui.files.open_folder("browser://")
	await _frames(2)
	var row: Variant = _row(ui.files, "already-open")
	_check("its row is in the Browser place", row != null)
	if row != null:
		row.pressed.emit()
	await _frames(5)
	src = main.player.source as WindowVideoSource
	_check("picking it captures it (not launched)", src != null and src.has_frame() and not src.launched
			and src.window_id == existing)
	main.close_media()
	await _seconds(0.5)
	_check("closing leaves a captured window open", _listed(existing))
	_check("closing drops the source and hides the screen", main.player.source == null and not main.screen.is_shown())

	# The window goes away: the source ends, the menu comes back.
	main.ui.hide_panel()
	main.open_path(WindowVideoSource.window_path(existing))
	await _frames(5)
	src = main.player.source as WindowVideoSource
	OS.kill(pid)
	t0 = Time.get_ticks_msec()
	while src != null and not src.is_ended() and Time.get_ticks_msec() - t0 < 5000:
		await _frames(1)
	await _frames(3)
	_check("a closed window ends the source (%s)" % (src.last_error if src != null else "-"), src != null and src.is_ended())
	_check("the menu shows again and the screen hides", main.ui.docked and not main.screen.is_shown())
	if launched_pid > 0:
		OS.kill(launched_pid)  # The stand-in ignores WM_DELETE_WINDOW (a browser closes on it).
	main.close_media()
	_finish()


func _finish() -> void:
	print("Window test: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	main.get_tree().quit(_failures)


func _listed(id: int) -> bool:
	for w: Dictionary in WindowVideoSource.list_desktop_windows()["windows"]:
		if w["id"] == id:
			return true
	return false


## The Files tab's row button whose text begins with prefix, or null. "Desktop windows" is a heading (no button).
func _row(files: Node, prefix: String) -> Variant:
	var b: Button = files.row_button(prefix)
	if b != null:
		return b
	for t: String in files.row_texts():
		if t.begins_with(prefix):
			return t
	return null


func _mouse_button(at: Vector2, button: MouseButton) -> void:
	var move := InputEventMouseMotion.new()
	move.position = at
	main._unhandled_input(move)
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.position = at
		e.button_index = button
		e.pressed = pressed
		main._unhandled_input(e)
		await _frames(1)


func _key(keycode: Key, unicode: int) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = keycode
		e.unicode = unicode
		e.pressed = pressed
		main._unhandled_input(e)
		await _frames(1)


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", what])


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
