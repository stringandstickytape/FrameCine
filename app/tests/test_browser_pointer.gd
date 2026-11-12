extends SceneTree

## The film screen as a surface and the laser on a captured window (scripts/screen_surface.gd,
## scripts/window_pointer.gd; docs/dev/surfaces-design.md, step 5), against the real main scene with a stand-in for
## the window capture: the screen's frame with the chrome (X), its bar selecting and moving the screen without a
## jump, the side stack (Back for a window; Previous and Next for a film), a film's picture answering no ray, the
## laser as the window's pointer (the cursor at its pixel, the trigger the left button, a drag, the squeeze tap the
## right button, the stick scrolling), the gaze changing nothing, the legends staying as they are, and browser_pointer.
##
## godot --headless --xr-mode off --path app --script res://tests/test_browser_pointer.gd

const WindowVideoSource := preload("res://scripts/video/window_video_source.gd")
const VideoMode := preload("res://scripts/video_mode.gd")
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
var surface: Node
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
	await _open_window()
	wp = main.window_pointer
	surface = main.screen_surface
	wp.set_process(false)
	wp.test_xr = true
	surface.set_process(false)
	surface.test_xr = true
	main.set_process(false)
	_check("a browser window on the flat screen: the screen is a surface with a window", wp.is_active()
			and wp.has_cursor() and surface.shows() and surface.window() == src)
	_frame_checks()
	_pointer_checks()
	_click_checks()
	_stick_checks()
	_gaze_and_legend_checks()
	await _command_checks()
	_terminal_and_menu_checks()
	_film_checks()
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


## The right hand's laser on a window pixel, or (local) on a point of the screen's plane in metres from its middle;
## both null: off the screen. The left hand points away. Then `steps` frames of the surface and the pointer.
func _aim(px: Variant, local: Variant = null, steps := 1) -> void:
	for i in steps:
		var hand: Node3D = main.right_hand
		var screen: Node3D = main.screen
		var quad: Vector2 = screen.get_flat_size()
		hand.global_position = main.camera.global_position + Vector3(0.2, -0.3, 0.0)
		var at := Vector3(quad.x * 3.0, 0.0, 0.0)
		if px != null:
			at = Vector3(((px as Vector2).x / W - 0.5) * quad.x, (0.5 - (px as Vector2).y / H) * quad.y, 0.0)
		elif local != null:
			at = Vector3((local as Vector2).x, (local as Vector2).y, 0.0)
		hand.look_at(screen.global_transform * at, Vector3.UP)
		var left: Node3D = main.left_hand
		left.look_at(left.global_position + screen.global_basis.z, Vector3.UP)
		main.pointing.refresh()
		surface.step()
		wp.step(DT)


## A point of the bar, in metres from the screen's middle (x as a share of the width from the middle).
func _bar(x_share := 0.0) -> Vector2:
	var size: Vector2 = surface.frame.content_size
	return Vector2(size.x * x_share, size.y / 2.0 + surface.frame.bar_height() / 2.0)


## The middle of the side stack's button `index` (0: the top one, beside the bar).
func _stack(index: int) -> Vector2:
	var size: Vector2 = surface.frame.content_size
	var bh: float = surface.frame.bar_height()
	return Vector2(size.x / 2.0 + surface.frame.stack_width() / 2.0, size.y / 2.0 + bh / 2.0 - bh * index)


# --- Checks --------------------------------------------------------------------------------------------------------

func _frame_checks() -> void:
	var hand: Node3D = main.right_hand
	_aim(Vector2(960, 540))
	_check("the screen wears a frame with the chrome shown: a title, no Close", surface.frame.shown
			and surface.frame.title != "" and not surface.frame.has_close)
	_aim(null, _bar(-0.3))
	_check("the laser on its bar (%s)" % [surface.aims.get(hand)], surface.aims.get(hand, {}).get("part", "") == "bar"
			and wp.owns_laser(hand))
	_aim(null, _stack(0))
	_check("a window on it: Back in the side stack (%s)" % [surface.aims.get(hand)],
			surface.aims.get(hand, {}).get("part", "") == "button" and surface.aims[hand].get("id", "") == "back")
	win.calls.clear()
	_check("the trigger on Back is taken", surface.on_trigger(hand, true))
	surface.on_trigger(hand, false)
	_check("Back sent the key and no click (%s)" % [win.calls], win.of("key").any(func(c: Array) -> bool: return c[1] == KEY_BACK)
			and win.of("button").is_empty())
	# The bar selects the screen and takes it: the point taken stays under the laser, the screen does not jump.
	main.pointing.select(null)
	_aim(null, _bar(-0.3))
	var before: Vector3 = main.screen.global_position
	win.calls.clear()
	_check("the trigger on the bar selects the screen and sends the window nothing", surface.on_trigger(hand, true)
			and main.pointing.selected == main.screen and win.of("button").is_empty())
	main._update_grab(DT)
	_check("taken by a point of its bar off the middle, it does not jump (%.4f m)" % main.screen.global_position.distance_to(before),
			main.screen.global_position.distance_to(before) < 0.01)
	_check("held, the hand is the screen's whatever it points at", surface.point_holds(hand))
	hand.global_position += Vector3(0.0, 0.2, 0.0)
	main._update_grab(DT)
	_check("and then it follows the hand (%.3f m up)" % (main.screen.global_position.y - before.y),
			main.screen.global_position.y - before.y > 0.1)
	_check("the trigger up lets it go", surface.on_trigger(hand, false) and not surface.point_holds(hand))
	# X hides the chrome: no bar to take, and the window still clicks.
	main.set_ui_shown(false)
	_aim(null, _bar(-0.3))
	_check("the chrome hidden: the frame goes and cannot be hit", not surface.frame.shown and not surface.aims.has(hand))
	_aim(Vector2(960, 540))
	_check("and the window still takes the laser", surface.aims.get(hand, {}).has("pixel"))
	main.set_ui_shown(true)
	_aim(Vector2(960, 540))


func _pointer_checks() -> void:
	var hand: Node3D = main.right_hand
	var mat: ShaderMaterial = main.screen.material
	_aim(null)
	_check("no laser on the window: no pointer, no cursor", wp.pointer == wp.NO_HIT and not wp.cursor.mode
			and not wp.owns_laser(hand))
	win.calls.clear()
	_aim(Vector2(480, 270), null, 30)
	_check("the laser on the window is the pointer, at its pixel (%s)" % wp.pointer, wp.cursor.mode
			and wp.pointer.distance_to(Vector2(480, 270)) < 2.0 and wp.pointer_hand == hand and wp.owns_laser(hand))
	_check("the cursor is drawn there (%s)" % mat.get_shader_parameter("cursor_px"),
			(mat.get_shader_parameter("cursor_px") as Vector2).distance_to(Vector2(480, 270)) < 2.0
			and float(mat.get_shader_parameter("cursor_alpha")) > 0.9)
	_check("the window is told where the pointer is", not win.of("pointer").is_empty()
			and (win.of("pointer")[-1][1] as Vector2).distance_to(Vector2(480, 270)) < 2.0)
	_aim(null, null, 2)
	_check("the laser leaves: the cursor goes at once", not wp.cursor.mode
			and float(mat.get_shader_parameter("cursor_alpha")) == 0.0)


func _click_checks() -> void:
	var hand: Node3D = main.right_hand
	main.pointing.select(null)
	_aim(Vector2(1200, 600), null, 3)
	win.calls.clear()
	_check("the trigger on the window is taken", surface.on_trigger(hand, true))
	_check("it selects the screen", main.pointing.selected == main.screen)
	_check("the left button goes down at the laser's pixel (%s)" % [win.calls], win.of("button") == [["button", 1, true]]
			and (win.of("pointer")[-1][1] as Vector2).distance_to(Vector2(1200, 600)) < 2.0)
	_aim(Vector2(1400, 700), null, 3)
	_check("held and moved: a drag, the pointer follows", wp.pointer.distance_to(Vector2(1400, 700)) < 2.0
			and wp.holds(hand))
	_aim(null, null, 2)
	_check("the hand stays the screen's while the button is down", surface.point_holds(hand))
	_check("the trigger up is the button up", surface.on_trigger(hand, false) and win.of("button")[-1] == ["button", 1, false]
			and not wp.holds(hand))
	_check("a trigger with no laser on the screen is not taken", not surface.on_trigger(hand, true))
	surface.on_trigger(hand, false)
	# The squeeze tap: the right button at the laser.
	_aim(Vector2(300, 300), null, 2)
	win.calls.clear()
	_check("a squeeze tap with the laser on the window is the right button there", wp.on_grip_tap(hand)
			and win.of("button") == [["button", 3, true], ["button", 3, false]]
			and (win.of("pointer")[-1][1] as Vector2).distance_to(Vector2(300, 300)) < 2.0)
	_aim(null)
	win.calls.clear()
	_check("off the window a squeeze tap is no click", not wp.on_grip_tap(hand) and win.of("button").is_empty())


func _stick_checks() -> void:
	var hand: Node3D = main.right_hand
	_aim(Vector2(960, 540), null, 2)
	win.calls.clear()
	_check("the stick with the laser on the window is taken", wp.on_stick(hand, Vector2(0, -1), 0.1))
	_check("down scrolls down (%s)" % [win.of("scroll")], win.of("scroll").size() == 1 and float(win.of("scroll")[0][2]) > 0.0)
	win.calls.clear()
	wp.on_stick(hand, Vector2(1, 0), 0.1)
	_check("right is the right arrow", win.of("key").any(func(c: Array) -> bool: return c[1] == KEY_RIGHT))
	wp.on_stick(hand, Vector2.ZERO, 0.1)
	_check("the left hand's stick, its laser elsewhere, is the film's", not wp.on_stick(main.left_hand, Vector2(0, 1), 0.1))
	_aim(null)
	win.calls.clear()
	_check("with no laser on the window the stick is the film's", not wp.on_stick(hand, Vector2(0, -1), 0.1)
			and win.calls.is_empty())


func _gaze_and_legend_checks() -> void:
	# Where the viewer looks changes nothing: with the laser off the window there is no pointer, looked at or not.
	_aim(null)
	wp.use_gaze_override = true
	var eye: Vector3 = main.camera.global_position
	wp.gaze_override = [eye, (main.screen.global_position - eye).normalized()]
	for i in 80:
		wp.step(DT)
	_check("a long look at the window gives no pointer and no cursor", not wp.cursor.mode and wp.pointer == wp.NO_HIT)
	wp.use_gaze_override = false
	var with: Dictionary = main.controller_labels(main.PREVIEW_PROFILE, "right", false)
	_check("the legends on a window are the fixed ones (%s)" % [with], with.get("trigger") == "CLICK"
			and with.get("a") == "PLAY / PAUSE" and not with.values().has("SPACE") and not with.values().has("BACK")
			and wp.window_labels().is_empty())


func _command_checks() -> void:
	_aim(Vector2(960, 540), null, 3)
	var r: Dictionary = await DevCommands.execute("browser_pointer", {}, true)
	var res: Dictionary = r.get("result", {})
	_check("browser_pointer: the laser's pointer and the cursor (%s)" % [res], r["ok"] and res.get("pointer_mode") == true
			and res.get("active") == true and res["cursor"]["x"] == roundi(wp.cursor.pos.x)
			and res["window"]["width"] == 1920 and not res.has("gaze") and not res.has("laser"))
	_check("browser_pointer: for the assistant", DevCommands.get_spec("browser_pointer").get("assistant") == "read")
	_aim(null, null, 2)
	r = await DevCommands.execute("browser_pointer", {}, true)
	_check("browser_pointer: no laser on the window", r["ok"] and r["result"]["pointer_mode"] == false)
	_check("the laser setting is gone", not DevCommands.has_setting("browser_laser"))


func _terminal_and_menu_checks() -> void:
	var hand: Node3D = main.right_hand
	# The menu is one more pane: a laser still works the window with it open; the keyboard is the menu's.
	main.set_menu_shown(true)
	_aim(Vector2(960, 540), null, 2)
	_check("the menu open: the laser still points at the window, the keys are not the window's", wp.cursor.mode
			and not wp.is_active())
	main.set_menu_shown(false)
	src.terminal_id = "claude"
	_aim(Vector2(960, 540), null, 2)
	_check("an agent's terminal: no cursor, no Back in the stack", not wp.has_cursor() and not wp.cursor.mode
			and surface.frame.stack_width() == 0.0)
	win.calls.clear()
	wp.on_stick(hand, Vector2(0, 1), 0.1)
	var keys: Array = win.of("key").map(func(c: Array) -> int: return c[1])
	_check("the stick up on a terminal scrolls back (%s)" % [keys], keys.has(KEY_SHIFT) and keys.has(KEY_PAGEUP))
	wp.on_stick(hand, Vector2.ZERO, 0.1)
	win.calls.clear()
	surface.on_trigger(hand, true)
	surface.on_trigger(hand, false)
	_check("the trigger on a terminal is a click, never Enter", not win.of("key").any(func(c: Array) -> bool: return c[1] == KEY_ENTER))
	src.terminal_id = ""


## A film: its picture answers no ray; its bar selects it; Previous and Next are in its stack.
func _film_checks() -> void:
	var hand: Node3D = main.right_hand
	main.player.source = null
	main.screen.set_shown(true)
	main.pointing.select(null)
	_aim(null, Vector2.ZERO)
	_check("a film's picture answers no ray", surface.shows() and not surface.aims.has(hand)
			and surface.point_hit(hand, hand.get_ray_origin(), hand.get_ray_direction()).is_empty())
	_aim(null, _stack(0))
	var first: String = str(surface.aims.get(hand, {}).get("id", ""))
	_aim(null, _stack(1))
	_check("Previous and Next in its side stack (%s, %s)" % [first, surface.aims.get(hand, {}).get("id", "")],
			first == "previous" and surface.aims.get(hand, {}).get("id", "") == "next")
	_aim(null, _bar(0.2))
	_check("its bar selects it", surface.on_trigger(hand, true) and main.pointing.selected == main.screen)
	surface.on_trigger(hand, false)
	(main.mode as VideoMode).projection = VideoMode.Proj.EQUIRECT_360
	_aim(null, _bar(0.2))
	_check("a 180 or 360 picture is no surface: no frame", not surface.shows() and not surface.frame.shown
			and not surface.aims.has(hand))


# --- Helpers ------------------------------------------------------------------------------------------------------

func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL " + what)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
