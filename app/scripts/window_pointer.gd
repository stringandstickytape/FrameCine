extends Node

## Input for a captured window (scripts/video/window_video_source.gd) while it is on the flat screen. The screen is a
## surface (scripts/screen_surface.gd; docs/dev/surfaces-design.md, step 5): a laser on it is the pointer, with either
## hand, and where the viewer looks changes nothing.
##   The trigger is the left button at the laser's pixel (held: drags work). A cursor is drawn into the picture there
##   (video_common.gdshaderinc, cursor_px / cursor_alpha: the film layer can't hide it).
##   The stick with the laser on the window: up / down scrolls, left / right sends the arrow keys (web players seek
##   with them). On an agent's terminal: up / down scrolls back (Shift + Page Up / Down, xterm's own scrollback).
##   A squeeze tap with the laser on the window is the right button there.
##   The right stick click keeps the picture under the laser (scripts/pictures/picture_keeper.gd).
##   Back is a button of the screen's side stack. A, B, X, Y and Menu are what they always are.
## With no laser on the window the controllers do what they do for a film.
## Desktop: the mouse over the screen is the window's mouse; the keyboard types into the window, except F1 (overlay),
## F3 (menu) and F12 (screenshot). A keyboard paired to the headset arrives the same way.
## Command: browser_pointer (read).

const XRHand := preload("res://scripts/xr/xr_hand.gd")
const WindowVideoSource := preload("res://scripts/video/window_video_source.gd")
const VideoMode := preload("res://scripts/video_mode.gd")
const StickCursor := preload("res://scripts/video/stick_cursor.gd")
const DevCommands := preload("res://scripts/dev/dev_commands.gd")

const NO_HIT := Vector2(-1, -1)
const SECTION := "browser"
## Scroll notches a second at full tilt.
const SCROLL_RATE := 12.0
const SCROLL_DEAD_ZONE := 0.2
const ARROW_THRESHOLD := 0.75
const ARROW_REPEAT := 0.4
## Desktop keys the player keeps while a window has the keyboard.
const RESERVED_KEYS: Array[Key] = [KEY_F1, KEY_F3, KEY_F12]
const MOUSE_TO_X := {MOUSE_BUTTON_LEFT: 1, MOUSE_BUTTON_MIDDLE: 2, MOUSE_BUTTON_RIGHT: 3, MOUSE_BUTTON_XBUTTON1: 8,
		MOUSE_BUTTON_XBUTTON2: 9}

## scripts/main.gd
var main: Node3D
## Window pixel a click goes to now (where a laser meets the window), or NO_HIT.
var pointer := NO_HIT
## The cursor drawn in the picture: on ("mode") while a laser is on the window, at its pixel ("pos").
var cursor := StickCursor.new()
## The hand whose laser is the pointer now, and the one that has the left button down.
var pointer_hand: Object = null
var _left_hand: Object = null
## Tests: run as in the headset without an XR session, and look where gaze_override says ([origin, dir], or [] for
## no gaze at all) instead of the eyes or the head.
var test_xr := false
var use_gaze_override := false
var gaze_override: Array = []
## Where the last gaze came from: "eyes", "head", "test" or "" (none).
var gaze_source := ""
var _last_sent := NO_HIT
var _left_down := false
var _mouse_down := {}
var _arrow_hold := -1.0
var _was_active := false
var _drawn_alpha := -1.0
var _drawn_px := Vector2(-2, -2)


func _ready() -> void:
	register_commands()


func get_source() -> WindowVideoSource:
	var src: Object = main.player.source
	return src as WindowVideoSource if src is WindowVideoSource else null


## A captured window is on the flat screen and the menu is hidden.
func is_active() -> bool:
	var src := get_source()
	return src != null and src.has_frame() and not main.menu_shown \
			and (main.mode as VideoMode).projection == VideoMode.Proj.FLAT


## A captured window is on the flat screen, the menu open or not: a laser can point at it (the menu is one more pane).
func on_screen() -> bool:
	var src := get_source()
	return src != null and src.has_frame() and (main.mode as VideoMode).projection == VideoMode.Proj.FLAT


## The window takes a pointer and shows a cursor: any window but an agent's terminal.
func has_cursor() -> bool:
	var src := get_source()
	return on_screen() and not src.is_terminal()


## The UI layer leaves this hand's laser alone: it is on the screen (scripts/screen_surface.gd draws it).
func owns_laser(hand: Object) -> bool:
	var surface: Node = main.get("screen_surface")
	return surface != null and bool(surface.has_hand(hand))


## The legends never change on a window now (docs/dev/surfaces-design.md).
func window_labels() -> Dictionary:
	return {}


## This hand has the window's left button down.
func holds(hand: Object) -> bool:
	return _left_down and _left_hand == hand


## What this hand's laser is on, on the screen ({} when it is not on it).
func _aim(hand: Object) -> Dictionary:
	var surface: Node = main.get("screen_surface")
	return surface.aims.get(hand, {}) if surface != null else {}


## The stick clicked with the laser on the window: the cursor back where it was before the click's nudge, and held
## there a moment (stick_cursor.gd freeze()). Returns that window pixel, or NO_HIT with no laser on the window.
func freeze_cursor(seconds: float) -> Vector2:
	if not cursor.mode or not has_cursor():
		return NO_HIT
	var at := cursor.freeze(seconds)
	pointer = at
	var src := get_source()
	if src != null:
		src.send_pointer(at)
		_last_sent = at
	_draw_cursor()
	return at


## Where a ray meets the flat screen's plane: {"uv" (0..1 inside the window, outside values off it), "distance"},
## or {} when it points away from it.
func ray_to_uv(origin: Vector3, direction: Vector3) -> Dictionary:
	var screen: Node3D = main.screen
	var to_local := screen.global_transform.affine_inverse()
	var o := to_local * origin
	var d := to_local.basis * direction
	if absf(d.z) < 1e-6:
		return {}
	var t := -o.z / d.z
	if t <= 0.0:
		return {}
	var hit := o + d * t
	var quad: Vector2 = screen.call("get_flat_size")
	return {"uv": Vector2(hit.x / quad.x + 0.5, 0.5 - hit.y / quad.y),
			"distance": origin.distance_to(screen.global_transform * hit)}


## Window pixel where a ray meets the flat screen ({"pixel", "distance"}), or {} when it misses.
func ray_to_window(origin: Vector3, direction: Vector3) -> Dictionary:
	var src := get_source()
	if src == null:
		return {}
	var h := ray_to_uv(origin, direction)
	if h.is_empty():
		return {}
	var uv: Vector2 = h["uv"]
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return {}
	var size := Vector2(src.get_size())
	return {"pixel": (uv * size).clamp(Vector2.ZERO, size - Vector2.ONE), "distance": h["distance"]}


## Where the viewer looks: the calibrated eye gaze when the headset gives one, else the head's direction.
func gaze_ray() -> Array:
	if use_gaze_override:
		gaze_source = "test" if not gaze_override.is_empty() else ""
		return gaze_override
	var features: Node = main.get("features")
	var g: Node = features.get("gaze") if features != null else null
	if g != null and g.available():
		var r: Array = g.ray()
		if not r.is_empty():
			gaze_source = "eyes"
			return r
	var cam: Camera3D = main.camera
	if cam == null:
		gaze_source = ""
		return []
	gaze_source = "head"
	return [cam.global_position, -cam.global_transform.basis.z.normalized()]


func _process(delta: float) -> void:
	step(delta)


## One frame of the window's pointer (tests call it with test_xr).
func step(delta: float) -> void:
	var active := on_screen()
	if active != _was_active:
		_was_active = active
		if not active:
			_release_all()
			cursor.reset()
	if not active or not (main.use_xr or test_xr) or not has_cursor():
		pointer = NO_HIT
		pointer_hand = null
		if cursor.mode or cursor.alpha > 0.0:
			cursor.reset()
		_draw_cursor()
		return
	var src := get_source()
	var size := Vector2(src.get_size())
	if size.x >= 1.0 and size.y >= 1.0:
		cursor.size = size
	# The hand with the button down keeps the pointer; else the right hand's laser on the window, else the left's.
	var at: Variant = null
	pointer_hand = null
	var order: Array = [_left_hand] if _left_down else []
	order.append(main.right_hand)
	order.append_array(main.hands)
	for hand: Object in order:
		var aim := _aim(hand)
		if aim.has("pixel"):
			at = aim["pixel"]
			pointer_hand = hand
			break
	if at == null:
		pointer = NO_HIT
		if cursor.mode or cursor.alpha > 0.0:
			cursor.reset()
		_draw_cursor()
		return
	cursor.step(delta, null, Vector2.ZERO, false, _left_down, at)
	pointer = cursor.pos
	if pointer.distance_to(_last_sent) >= 0.5:
		_last_sent = pointer
		src.send_pointer(pointer)
	_draw_cursor()


## The cursor's uniforms on the screen's material (the film layer copies them to its own).
func _draw_cursor() -> void:
	var mat: ShaderMaterial = main.screen.material if main.screen != null else null
	if mat == null:
		return
	if cursor.alpha != _drawn_alpha:
		_drawn_alpha = cursor.alpha
		mat.set_shader_parameter("cursor_alpha", cursor.alpha)
	if cursor.pos != _drawn_px:
		_drawn_px = cursor.pos
		mat.set_shader_parameter("cursor_px", cursor.pos)


## Lets go of buttons held on the window (the menu opened, the source closed).
func _release_all() -> void:
	var src := get_source()
	if _left_down and src != null:
		src.send_button(1, false)
	_left_down = false
	_left_hand = null
	if src != null:
		for b: int in _mouse_down:
			src.send_button(b, false)
	_mouse_down.clear()
	_arrow_hold = -1.0
	_last_sent = NO_HIT


# --- Controllers -------------------------------------------------------------------------------------------------

## The left button goes down at this pixel with this hand's trigger (scripts/screen_surface.gd, which knows what the
## laser is on).
func click(hand: Object, pixel: Vector2) -> void:
	var src := get_source()
	if src == null:
		return
	pointer = pixel
	_last_sent = pixel
	src.send_pointer(pixel)
	src.send_button(1, true)
	_left_down = true
	_left_hand = hand


## The trigger comes up: the left button with it, wherever the laser is by then. True when it was down with this hand.
func on_trigger(hand: Object, pressed: bool) -> bool:
	if pressed or not holds(hand):
		return false
	var src := get_source()
	if src != null:
		if pointer != NO_HIT:
			src.send_pointer(pointer)
		src.send_button(1, false)
	_left_down = false
	_left_hand = null
	return true


## A squeeze tap (main.gd measured it) with the laser on the window: the right button there. False otherwise.
func on_grip_tap(hand: XRHand) -> bool:
	var aim := _aim(hand)
	if not aim.has("pixel") or not has_cursor():
		return false
	var src := get_source()
	src.send_pointer(aim["pixel"])
	src.send_button(3, true)
	src.send_button(3, false)
	hand.pulse()
	return true


## The stick with this hand's laser on the window: it scrolls. False with no laser on it (the film's stick then).
func on_stick(hand: XRHand, stick: Vector2, delta: float) -> bool:
	if not on_screen() or not _aim(hand).has("pixel"):
		return false
	var src := get_source()
	if src.is_terminal():
		# Up is back through the terminal's history, as on its own pane.
		if absf(stick.y) < ARROW_THRESHOLD:
			_arrow_hold = -1.0
			return true
		if _arrow_hold < 0.0 or _arrow_hold >= ARROW_REPEAT:
			_arrow_hold = 0.0
			src.send_godot_key(KEY_SHIFT, true)
			src.tap_key(KEY_PAGEUP if stick.y > 0.0 else KEY_PAGEDOWN)
			src.send_godot_key(KEY_SHIFT, false)
		_arrow_hold += delta
		return true
	if absf(stick.y) > SCROLL_DEAD_ZONE:
		src.send_scroll(0.0, -stick.y * SCROLL_RATE * delta)
	if absf(stick.x) > ARROW_THRESHOLD:
		if _arrow_hold < 0.0 or _arrow_hold >= ARROW_REPEAT:
			src.tap_key(KEY_RIGHT if stick.x > 0.0 else KEY_LEFT)
			_arrow_hold = 0.0
		_arrow_hold += delta
	else:
		_arrow_hold = -1.0
	return true


# --- Desktop -----------------------------------------------------------------------------------------------------

## The flat camera's mouse; ray = [origin, direction]. True when the window used the event.
func on_mouse(event: InputEventMouse, ray: Array) -> bool:
	if not is_active() or main.use_xr:
		return false
	var src := get_source()
	var hit := ray_to_window(ray[0], ray[1])
	if event is InputEventMouseMotion:
		if hit.is_empty():
			return not _mouse_down.is_empty()
		src.send_pointer(hit["pixel"])
		return true
	var button := event as InputEventMouseButton
	var index := button.button_index
	if index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		if hit.is_empty():
			return false
		if button.pressed:
			src.send_pointer(hit["pixel"])
			match index:
				MOUSE_BUTTON_WHEEL_UP:
					src.send_scroll(0, -1)
				MOUSE_BUTTON_WHEEL_DOWN:
					src.send_scroll(0, 1)
				MOUSE_BUTTON_WHEEL_LEFT:
					src.send_scroll(-1, 0)
				MOUSE_BUTTON_WHEEL_RIGHT:
					src.send_scroll(1, 0)
		return true
	if not MOUSE_TO_X.has(index):
		return false
	var x_button: int = MOUSE_TO_X[index]
	if button.pressed:
		if hit.is_empty():
			return false
		src.send_pointer(hit["pixel"])
		src.send_button(x_button, true)
		_mouse_down[x_button] = true
		return true
	if _mouse_down.has(x_button):
		_mouse_down.erase(x_button)
		if not hit.is_empty():
			src.send_pointer(hit["pixel"])
		src.send_button(x_button, false)
		return true
	return false


## The keyboard (desktop, or a keyboard paired to the headset). True when the window took the key.
func on_key(event: InputEventKey) -> bool:
	if not is_active() or event.keycode in RESERVED_KEYS:
		return false
	var src := get_source()
	return keyboard_key(event, src)


## Shared with the floating keyboard. Its physical keys are held for X11's own repeat and include the function
## keys reserved for the player's paired keyboard. A captured source keeps the key up when the menu opens.
func keyboard_key(event: InputEventKey, src: Object, physical := false) -> bool:
	if not is_instance_valid(src):
		return false
	# Printable characters as text (the layout's shifted symbols stay right), the rest as keys.
	if not physical and event.unicode >= 32 and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
		if event.pressed:
			src.send_char(event.unicode)
		return true
	src.send_godot_key(event.keycode, event.pressed)
	return true


# --- Commands ------------------------------------------------------------------------------------------------------

## The pointer now, for the dev link and the assistant (browser_pointer).
func status() -> Dictionary:
	var src := get_source()
	var size := src.get_size() if src != null else Vector2i.ZERO
	return {"active": is_active(), "cursor_window": has_cursor(), "pointer_mode": cursor.mode,
			"cursor_shown": cursor.shown(), "cursor": {"x": roundi(cursor.pos.x), "y": roundi(cursor.pos.y)}
					if cursor.pos.x >= 0.0 else null,
			"window": {"width": size.x, "height": size.y}}


func register_commands() -> void:
	DevCommands.register("browser_pointer", func(_args: Dictionary, _ctx: DevCommands.Call) -> Variant:
		return status(), {"assistant": "read",
			"description": "The pointer on the window on the big screen (the browser): active (a window is on the flat "
					+ "screen, menu hidden), pointer_mode (a controller's laser is on the window: the trigger clicks "
					+ "there and the stick scrolls), cursor_shown, cursor {x, y} in window pixels (null before a laser "
					+ "was first on it), window {width, height}.",
			"returns": "{active, cursor_window, pointer_mode, cursor_shown, cursor, window}"})
