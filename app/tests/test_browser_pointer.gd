extends SceneTree

## The stick pointer on a captured window (scripts/window_pointer.gd, scripts/video/stick_cursor.gd), against the real
## main scene with a stand-in for the window capture and the gaze: pointer mode on and off with the hysteresis and
## the latch, the cursor shown and hidden (the screen's shader uniforms), its movement with the stick and the speed
## curve, the jump to the gaze and its setting, clicks at the right window pixel, squeeze held + stick scrolling,
## the normal job while looking away, the laser alternative, the legends for each mode, and browser_pointer.
##
## godot --headless --xr-mode off --path app --script res://tests/test_browser_pointer.gd

const WindowVideoSource := preload("res://scripts/video/window_video_source.gd")
const StickCursor := preload("res://scripts/video/stick_cursor.gd")
const DevCommands := preload("res://scripts/dev/dev_commands.gd")
const CommandHost := preload("res://scripts/dev/command_host.gd")

const DT := 1.0 / 72.0
const W := 1920.0
const H := 1080.0


## Stands in for X11WindowSource: keeps every input it is sent.
class FakeWin extends RefCounted:
	var calls: Array = []
	var size := Vector2i(1920, 1080)

	func get_size() -> Vector2i:
		return size

	func get_texture() -> Texture2D:
		return null

	func update() -> bool:
		return false

	func get_stats() -> Dictionary:
		return {}

	func send_pointer(x: float, y: float) -> void:
		calls.append(["pointer", Vector2(x, y)])

	func send_button(b: int, pressed: bool) -> void:
		calls.append(["button", b, pressed])

	func send_scroll(dx: float, dy: float) -> void:
		calls.append(["scroll", dx, dy])

	func send_godot_key(k: int, pressed: bool) -> void:
		calls.append(["key", k, pressed])

	func send_unicode(u: int, pressed: bool) -> void:
		calls.append(["unicode", u, pressed])

	func stop_capture() -> void:
		pass

	func close() -> void:
		pass

	func close_window(_id: int) -> void:
		calls.append(["close_window"])

	func of(kind: String) -> Array:
		return calls.filter(func(c: Array) -> bool: return c[0] == kind)


var _failures := 0
var _checks := 0
var main: Node3D
var wp: Node
var win: FakeWin
var src: WindowVideoSource


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _run() -> void:
	await _frames(5)
	CommandHost.ensure(self)
	_cursor_unit_checks()
	await _open_window()
	wp = main.window_pointer
	wp.set_process(false)
	wp.test_xr = true
	wp.use_gaze_override = true
	_check("a browser window on screen, menu hidden: the window has the input", wp.is_active() and wp.has_cursor())
	_mode_checks()
	_latch_checks()
	_movement_checks()
	_jump_checks()
	_click_checks()
	_grip_checks()
	_away_checks()
	_legend_checks()
	_head_checks()
	await _command_checks()
	_terminal_and_menu_checks()
	main.queue_free()
	await _frames(2)
	print("test_browser_pointer: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(1 if _failures > 0 else 0)


# --- Set-up --------------------------------------------------------------------------------------------------------

func _open_window() -> void:
	main.ui.hide_panel()
	await _frames(2)
	main.player.close()
	src = WindowVideoSource.new()
	win = FakeWin.new()
	src.path = WindowVideoSource.browser_path("https://example.org/")
	src.url = "https://example.org/"
	src.launched = true
	src.window_id = 0x2a00003
	src.win = win
	# No DevTools reads in this test.
	src._page_next_msec = 1 << 62
	main.current_path = src.path
	main.player.source = src
	main.mode = src.get_known_mode().copy()
	await _frames(2)


## A gaze ray from the camera to a point of the window (UV; outside 0..1 is off it).
func _look(uv: Variant) -> void:
	if uv == null:
		wp.gaze_override = []
		return
	var screen: Node3D = main.screen
	var quad: Vector2 = screen.get_flat_size()
	var p: Vector2 = uv
	var target: Vector3 = screen.global_transform * Vector3((p.x - 0.5) * quad.x, (0.5 - p.y) * quad.y, 0.0)
	var eye: Vector3 = main.camera.global_position
	wp.gaze_override = [eye, (target - eye).normalized()]


## n frames of the window's pointer with this stick (the stick goes through on_stick() as main.gd sends it).
func _step(n: int, stick := Vector2.ZERO) -> void:
	for i in n:
		wp.on_stick(main.right_hand, stick, DT)
		wp.step(DT)


func _seconds(s: float, stick := Vector2.ZERO) -> void:
	_step(ceili(s / DT), stick)


func _off() -> void:
	_look(Vector2(2.0, 0.5))
	_seconds(0.6)


# --- Checks --------------------------------------------------------------------------------------------------------

func _cursor_unit_checks() -> void:
	var c := StickCursor.new()
	_check("the speed curve: nothing in the dead zone", StickCursor.speed_of(0.15) == 0.0
			and StickCursor.speed_of(0.2) == 0.0)
	_check("the speed curve: slow for small tilts (%.3f)" % StickCursor.speed_of(0.4),
			absf(StickCursor.speed_of(0.4) - 0.0625) < 0.001 and StickCursor.speed_of(0.6) < 0.3)
	_check("the speed curve: full tilt is full speed", is_equal_approx(StickCursor.speed_of(1.0), 1.0))
	_check("the margin round the screen counts as on it", StickCursor.on_screen(Vector2(1.04, -0.04))
			and not StickCursor.on_screen(Vector2(1.06, 0.5)) and not StickCursor.on_screen(null))
	c.step(DT, null, Vector2.ZERO, false, false, Vector2(100, 200))
	_check("pinned (the laser): pointer mode at the pin at once", c.mode and c.pos == Vector2(100, 200) and c.moved)
	c.step(DT, null, Vector2.ZERO)
	c.reset()
	_check("reset hides it at once", not c.mode and c.alpha == 0.0)


func _mode_checks() -> void:
	var mat: ShaderMaterial = main.screen.material
	_look(null)
	_seconds(0.5)
	_check("no gaze: no pointer mode, no cursor", not wp.cursor.mode and float(mat.get_shader_parameter("cursor_alpha"))
			== 0.0)
	_look(Vector2(0.3, 0.4))
	_step(5)
	_check("pointer mode waits for 0.1 s of gaze", not wp.cursor.mode)
	_step(3)
	_check("pointer mode after 0.1 s on the screen", wp.cursor.mode)
	_check("the cursor appears where the viewer looks (%s)" % wp.cursor.pos,
			wp.cursor.pos.distance_to(Vector2(0.3 * W, 0.4 * H)) < 3.0 and wp.cursor.last_jump == "appear")
	_check("it fades in: not at once (%.2f)" % wp.cursor.alpha, wp.cursor.alpha > 0.0 and wp.cursor.alpha < 0.5)
	_seconds(0.1)
	_check("shown within 0.1 s, drawn by the screen's shader (%s, %s)" % [mat.get_shader_parameter("cursor_alpha"),
			mat.get_shader_parameter("cursor_px")], is_equal_approx(float(mat.get_shader_parameter("cursor_alpha")), 1.0)
			and (mat.get_shader_parameter("cursor_px") as Vector2) == wp.cursor.pos)
	var sent := win.of("pointer")
	_check("the window's pointer went to the cursor", not sent.is_empty()
			and (sent[-1][1] as Vector2).distance_to(wp.cursor.pos) < 0.01)
	_look(Vector2(2.0, 0.5))
	_seconds(0.3)
	_check("a glance away under 0.4 s keeps pointer mode", wp.cursor.mode)
	_look(Vector2(0.3, 0.4))
	_step(1)
	_look(Vector2(2.0, 0.5))
	_seconds(0.45)
	_check("0.4 s looking away ends it", not wp.cursor.mode)
	_seconds(0.1)
	_check("and the cursor fades out within 0.1 s", wp.cursor.alpha == 0.0
			and float(mat.get_shader_parameter("cursor_alpha")) == 0.0)
	_look(Vector2(1.04, 0.5))
	_seconds(0.3)
	_check("just past the edge (inside the 5 %% margin) is on the screen", wp.cursor.mode)
	_check("the cursor stays on the window there (%s)" % wp.cursor.pos, wp.cursor.pos.x <= W - 1.0)
	_off()


func _latch_checks() -> void:
	_look(Vector2(0.5, 0.5))
	_seconds(0.2)
	_look(Vector2(2.0, 0.5))
	_seconds(1.0, Vector2(0.5, 0.0))
	_check("the latch: pointer mode stays while the stick is pushed", wp.cursor.mode)
	_seconds(0.3)
	_check("let go: still on for under 0.4 s", wp.cursor.mode)
	_seconds(0.2)
	_check("and off after 0.4 s", not wp.cursor.mode)
	_look(Vector2(0.5, 0.5))
	_seconds(0.2)
	wp.on_trigger(main.right_hand, true)
	_look(Vector2(2.0, 0.5))
	_seconds(1.0)
	_check("the latch: a drag (trigger held) keeps it too", wp.cursor.mode)
	wp.on_trigger(main.right_hand, false)
	_seconds(0.5)
	_check("let go of the trigger: off", not wp.cursor.mode)


func _movement_checks() -> void:
	_look(Vector2(0.25, 0.5))
	_seconds(0.2)
	var start: Vector2 = wp.cursor.pos
	_seconds(0.5, Vector2(1.0, 0.0))
	var moved: Vector2 = wp.cursor.pos - start
	_check("full tilt crosses the page in about a second (%.0f px in 0.5 s)" % moved.x, absf(moved.x - W * 0.5) < 30.0
			and absf(moved.y) < 0.5)
	start = wp.cursor.pos
	_seconds(1.0, Vector2(0.0, 0.4))
	moved = wp.cursor.pos - start
	_check("a small tilt moves slowly, and stick up is up the page (%.0f px in 1 s)" % moved.y, moved.y < -100.0
			and moved.y > -140.0)
	start = wp.cursor.pos
	_seconds(0.5, Vector2(0.15, 0.1))
	_check("the dead zone: no drift", wp.cursor.pos == start)
	_seconds(3.0, Vector2(1.0, 1.0))
	_check("the cursor stays on the window (%s)" % wp.cursor.pos, wp.cursor.pos.x <= W - 1.0 and wp.cursor.pos.y >= 0.0)
	_check("the window's pointer follows the stick", (win.of("pointer")[-1][1] as Vector2).distance_to(wp.cursor.pos)
			< 0.01)
	_off()


func _jump_checks() -> void:
	_look(Vector2(0.2, 0.2))
	_seconds(0.2)
	_seconds(0.3, Vector2(0.5, 0.0))
	var aimed: Vector2 = wp.cursor.pos
	_look(Vector2(0.8, 0.7))
	_seconds(0.3)
	_check("no jump right after the stick moved (it fine-tunes)", wp.cursor.pos == aimed)
	_seconds(0.6)
	_check("the gaze rests far away with the stick still: the cursor jumps there (%s)" % wp.cursor.pos,
			wp.cursor.pos.distance_to(Vector2(0.8 * W, 0.7 * H)) < 3.0)
	var at: Vector2 = wp.cursor.pos
	_look(Vector2(0.85, 0.7))
	_seconds(1.0)
	_check("a look within 10 %% of the width: no jump", wp.cursor.pos == at)
	_look(Vector2(0.3, 0.7))
	_step(5)
	_check("the jump waits for the gaze to rest (0.15 s)", wp.cursor.pos == at)
	_seconds(0.2)
	_check("then jumps", wp.cursor.pos.distance_to(Vector2(0.3 * W, 0.7 * H)) < 3.0)
	_off()
	wp.set_follows_gaze(false)
	_check("the setting is kept ([browser] pointer_follows_gaze false)",
			main.settings.get_value("browser", "pointer_follows_gaze", true) == false)
	var kept: Vector2 = wp.cursor.pos
	_look(Vector2(0.7, 0.2))
	_seconds(0.3)
	_check("follows_gaze off: the cursor comes back where it was", wp.cursor.mode and wp.cursor.pos == kept)
	_look(Vector2(0.1, 0.9))
	_seconds(1.5)
	_check("follows_gaze off: no jump to the gaze", wp.cursor.pos == kept)
	wp.set_follows_gaze(true)
	_check("on again: the setting goes back to the default", not main.settings.has_value("browser",
			"pointer_follows_gaze") or main.settings.get_value("browser", "pointer_follows_gaze", true) == true)
	_off()


func _click_checks() -> void:
	_look(Vector2(0.5, 0.5))
	_seconds(0.2)
	_seconds(0.25, Vector2(0.6, -0.6))
	var at: Vector2 = wp.cursor.pos
	win.calls.clear()
	_check("the trigger is taken", wp.on_trigger(main.right_hand, true))
	_check("a press: the pointer at the cursor's pixel, then the left button (%s)" % [win.calls],
			win.calls.size() >= 2 and win.calls[-2] == ["pointer", at] and win.calls[-1] == ["button", 1, true])
	wp.on_trigger(main.right_hand, false)
	_check("the release at the same pixel", win.calls[-1] == ["button", 1, false] and win.calls[-2] == ["pointer", at])
	win.calls.clear()
	_check("a squeeze tap is the right button at the cursor", wp.on_grip_tap(main.right_hand)
			and win.calls == [["pointer", at], ["button", 3, true], ["button", 3, false]])
	_off()
	win.calls.clear()
	wp.on_trigger(main.right_hand, true)
	wp.on_trigger(main.right_hand, false)
	_check("looking away: the trigger clicks nothing", win.of("button").is_empty())
	_check("looking away: a squeeze tap is no right click", not wp.on_grip_tap(main.right_hand)
			and win.of("button").is_empty())


func _grip_checks() -> void:
	_look(Vector2(0.5, 0.5))
	_seconds(0.2)
	var at: Vector2 = wp.cursor.pos
	main.right_hand.grip_down = true
	win.calls.clear()
	_seconds(0.25, Vector2(0.0, -1.0))
	var notches := 0.0
	for c: Array in win.of("scroll"):
		notches += float(c[2])
	_check("squeeze held + stick down scrolls down (%.2f notches in 0.25 s)" % notches, absf(notches - 3.0) < 0.3)
	_check("and the cursor stays put", wp.cursor.pos == at and wp.cursor.mode)
	win.calls.clear()
	_seconds(0.1, Vector2(1.0, 0.0))
	_check("squeeze held + stick right: the Right arrow", win.of("key").has(["key", KEY_RIGHT, true]))
	_check("letting go of that squeeze is no right click", wp.on_grip_tap(main.right_hand)
			and win.of("button").is_empty())
	main.right_hand.grip_down = false
	_step(1)
	win.calls.clear()
	_check("a plain squeeze tap still right-clicks", wp.on_grip_tap(main.right_hand) and win.of("button").size() == 2)
	_off()


func _away_checks() -> void:
	win.calls.clear()
	_seconds(0.25, Vector2(0.0, 1.0))
	var notches := 0.0
	for c: Array in win.of("scroll"):
		notches += float(c[2])
	_check("looking away, no cursor: stick up scrolls up (%.2f)" % notches, notches < -2.5 and not wp.cursor.shown())
	win.calls.clear()
	_seconds(0.1, Vector2(-1.0, 0.0))
	_check("looking away: stick left is the Left arrow", win.of("key").has(["key", KEY_LEFT, true]))


func _legend_checks() -> void:
	var profile: String = main.PREVIEW_PROFILE
	_off()
	var away: Dictionary = main.controller_labels(profile, "right", false, true, false, false, false, wp.window_labels())
	_check("legends looking away: scroll and keys, no trigger, no squeeze (%s)" % [away],
			str(away.get("thumbstick", "")).begins_with("SCROLL / KEYS") and not away.has("trigger")
			and not away.has("squeeze") and away.get("a") == "SPACE")
	_look(Vector2(0.5, 0.5))
	_seconds(0.2)
	var on: Dictionary = main.controller_labels(profile, "right", false, true, false, false, false, wp.window_labels())
	_check("legends in pointer mode: pointer, click, hold to scroll (%s)" % [on],
			str(on.get("thumbstick", "")).begins_with("POINTER") and on.get("trigger") == "CLICK"
			and on.get("squeeze") == "HOLD: SCROLL")
	var printed: Dictionary = main.right_hand.visual.get("_texts") if main.right_hand.visual.get("_texts") is Dictionary \
			else {}
	if not printed.is_empty():
		_check("the printed legends follow the mode (%s)" % [printed], str(printed.get("thumbstick", "")).begins_with(
				"POINTER"))
	wp.set_laser(true)
	_off()
	var laser: Dictionary = main.controller_labels(profile, "right", false, true, false, false, false, wp.window_labels())
	_check("with the laser on, looking away: the laser's legends (%s)" % [laser], laser.get("trigger") == "CLICK"
			and laser.get("squeeze") == "R-CLICK")
	_check("the laser setting is kept", main.settings.get_value("browser", "laser", false) == true)
	wp.set_laser(false)
	_check("laser off by default: the UI layer keeps the hand's laser", not wp.owns_laser(main.right_hand))


func _head_checks() -> void:
	wp.use_gaze_override = false
	var r: Array = wp.gaze_ray()
	_check("no eye tracking here: the head's direction (%s)" % wp.gaze_source, wp.gaze_source == "head" and r.size() == 2)
	wp.use_gaze_override = true


func _command_checks() -> void:
	_look(Vector2(0.5, 0.5))
	_seconds(0.2)
	var r: Dictionary = await DevCommands.execute("browser_pointer", {}, true)
	var res: Dictionary = r.get("result", {})
	_check("browser_pointer: pointer mode and the cursor (%s)" % [res], r["ok"] and res.get("pointer_mode") == true
			and res.get("active") == true and res["cursor"]["x"] == roundi(wp.cursor.pos.x)
			and res["window"]["width"] == 1920 and res.get("follows_gaze") == true)
	_check("browser_pointer: for the assistant", DevCommands.get_spec("browser_pointer").get("assistant") == "read")
	_off()
	r = await DevCommands.execute("browser_pointer", {}, true)
	_check("browser_pointer: looking away", r["ok"] and r["result"]["pointer_mode"] == false)
	_check("the settings for the dev link", DevCommands.has_setting("browser_pointer_follows_gaze")
			and DevCommands.has_setting("browser_laser"))


func _terminal_and_menu_checks() -> void:
	_look(Vector2(0.5, 0.5))
	_seconds(0.2)
	main.set_menu_shown(true)
	_step(1)
	_check("the menu opens: the window lets go, the cursor hides at once", not wp.is_active() and not wp.cursor.mode
			and float((main.screen.material as ShaderMaterial).get_shader_parameter("cursor_alpha")) == 0.0)
	main.set_menu_shown(false)
	_step(1)
	src.terminal_id = "claude"
	_seconds(0.3)
	_check("an agent's terminal: no stick pointer", not wp.has_cursor() and not wp.cursor.mode)
	src.terminal_id = ""


# --- Helpers ------------------------------------------------------------------------------------------------------

func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL " + what)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
