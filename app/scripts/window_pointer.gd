extends Node

## Input for a captured window (scripts/video/window_video_source.gd) while it is on the flat screen and the menu is
## hidden. main.gd asks it first (after the menu) and skips its own binding when it returns true.
## Right controller (docs/window-source.md, "Controller mapping"):
##   laser on the screen: the window's pointer (window pixels: the quad's UV times the window size, no scaling)
##   trigger: left button, held with the trigger (drags work)
##   squeeze tap: right button
##   thumbstick up / down: scroll wheel; left / right: arrow keys (web players seek with them)
##   A: Space (play / pause in web players); B: browser Back (an Android app's Back, below)
##   menu, view, bumper: unchanged
## An agent's terminal on the big screen (terminal://): trigger Enter, stick up / down arrows, B Escape, and with the
## squeeze held stick up / down scroll back (Shift + Page Up / Down, xterm's own scrollback).
## An Android app on the big screen (scripts/android/android_apps.gd): as any window, but B is its own Back.
## Left controller: trigger and X / Y do nothing on a window; the stick works as for video.
## Desktop: the mouse over the screen is the window's mouse; the keyboard types into the window, except F1 (overlay),
## F3 (menu) and F12 (screenshot). A keyboard paired to the headset arrives the same way.

const XRHand := preload("res://scripts/xr/xr_hand.gd")
const WindowVideoSource := preload("res://scripts/video/window_video_source.gd")
const VideoMode := preload("res://scripts/video_mode.gd")

const NO_HIT := Vector2(-1, -1)
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
## Window pixel under the right controller's laser, or NO_HIT.
var pointer := NO_HIT
var _last_sent := NO_HIT
var _left_down := false
var _mouse_down := {}
var _arrow_hold := -1.0
var _was_active := false


func get_source() -> WindowVideoSource:
	var src: Object = main.player.source
	return src as WindowVideoSource if src is WindowVideoSource else null


## A captured window is on the flat screen and the menu is hidden.
func is_active() -> bool:
	var src := get_source()
	return src != null and src.has_frame() and not main.menu_shown \
			and (main.mode as VideoMode).projection == VideoMode.Proj.FLAT


## The UI layer leaves this hand's laser alone: it is the window's pointer.
func owns_laser(hand: XRHand) -> bool:
	return main.use_xr and hand == main.right_hand and is_active()


## Window pixel where a ray meets the flat screen ({"pixel", "distance"}), or {} when it misses.
func ray_to_window(origin: Vector3, direction: Vector3) -> Dictionary:
	var src := get_source()
	if src == null:
		return {}
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
	var uv := Vector2(hit.x / quad.x + 0.5, 0.5 - hit.y / quad.y)
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return {}
	var size := Vector2(src.get_size())
	return {"pixel": (uv * size).clamp(Vector2.ZERO, size - Vector2.ONE),
			"distance": origin.distance_to(screen.global_transform * hit)}


func _process(_delta: float) -> void:
	var active := is_active()
	if active != _was_active:
		_was_active = active
		main.update_controller_labels()
		if not active:
			_release_all()
	if not active or not main.use_xr:
		pointer = NO_HIT
		return
	var hand: XRHand = main.right_hand
	if not hand.get_is_active():
		pointer = NO_HIT
		return
	var hit := ray_to_window(hand.get_ray_origin(), hand.get_ray_direction())
	pointer = hit.get("pixel", NO_HIT)
	hand.set_laser(true, float(hit.get("distance", 3.0)), not hit.is_empty())
	if pointer != NO_HIT and pointer.distance_to(_last_sent) >= 0.5:
		_last_sent = pointer
		get_source().send_pointer(pointer)


## Lets go of buttons held on the window (the menu opened, the source closed).
func _release_all() -> void:
	var src := get_source()
	if _left_down and src != null:
		src.send_button(1, false)
	_left_down = false
	if src != null:
		for b: int in _mouse_down:
			src.send_button(b, false)
	_mouse_down.clear()
	_arrow_hold = -1.0


# --- Controllers -------------------------------------------------------------------------------------------------

func on_trigger(hand: XRHand, pressed: bool) -> bool:
	if not is_active():
		return false
	if hand != main.right_hand:
		return true
	var src := get_source()
	if src.is_terminal():
		if pressed:
			src.tap_key(KEY_ENTER)
			hand.pulse()
		return true
	if pressed:
		if pointer != NO_HIT:
			src.send_pointer(pointer)
			src.send_button(1, true)
			_left_down = true
			hand.pulse()
	elif _left_down:
		src.send_button(1, false)
		_left_down = false
	return true


## A squeeze tap (main.gd measured it): right click where the laser points. False when off the window.
func on_grip_tap(hand: XRHand) -> bool:
	if not is_active() or hand != main.right_hand or pointer == NO_HIT:
		return false
	var src := get_source()
	src.send_pointer(pointer)
	src.send_button(3, true)
	src.send_button(3, false)
	hand.pulse()
	return true


func on_stick(hand: XRHand, stick: Vector2, delta: float) -> bool:
	if not is_active() or hand != main.right_hand:
		return false
	var src := get_source()
	if src.is_terminal():
		_terminal_stick(hand, stick, delta)
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


func _terminal_stick(hand: XRHand, stick: Vector2, delta: float) -> void:
	var src := get_source()
	if absf(stick.y) < ARROW_THRESHOLD:
		_arrow_hold = -1.0
		return
	if _arrow_hold < 0.0 or _arrow_hold >= ARROW_REPEAT:
		_arrow_hold = 0.0
		if hand.grip_down:
			src.send_godot_key(KEY_SHIFT, true)
			src.tap_key(KEY_PAGEUP if stick.y > 0.0 else KEY_PAGEDOWN)
			src.send_godot_key(KEY_SHIFT, false)
		else:
			src.tap_key(KEY_UP if stick.y > 0.0 else KEY_DOWN)
	_arrow_hold += delta


## next_file (A / X) and prev_file (B / Y). Right hand: Space and Back. Left hand: nothing.
func on_button(hand: XRHand, action: String) -> bool:
	if not is_active():
		return false
	if hand == main.right_hand:
		match action:
			"next_file":
				get_source().tap_key(KEY_SPACE)
			"prev_file":
				if main.android_apps.on_big_screen():
					main.android_apps.back()
					hand.pulse()
				else:
					get_source().tap_key(KEY_ESCAPE if get_source().is_terminal() else KEY_BACK)
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
	# Printable characters as text (the layout's shifted symbols stay right), the rest as keys.
	if event.unicode >= 32 and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
		if event.pressed:
			src.send_char(event.unicode)
		return true
	src.send_godot_key(event.keycode, event.pressed)
	return true
