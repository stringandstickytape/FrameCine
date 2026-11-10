extends Node

## Input for a captured window (scripts/video/window_video_source.gd) while it is on the flat screen and the menu is
## hidden. main.gd asks it first (after the menu) and skips its own binding when it returns true.
## Right controller (docs/window-source.md, "Controller mapping"), in two modes:
##   Pointer mode, while the viewer looks at the screen (eye gaze, else the head's direction; stick_cursor.gd has the
##   hysteresis and the latch; the gaze only chooses the mode, the cursor never follows it): a cursor drawn into the picture (video_common.gdshaderinc,
##   cursor_px / cursor_alpha: the film layer can't hide it), moved by the stick; the trigger is the left button at
##   the cursor (held with the trigger: drags work); a squeeze tap is the right button there; squeeze held + stick:
##   the stick's normal job below.
##   Normal job, while they look away (the cursor is not drawn: that is the cue): stick up / down scrolls, left / right
##   sends the arrow keys (web players seek with them); the trigger and the squeeze do nothing.
##   Both: A is Space (play / pause in web players); B browser Back (an Android app's Back, below); menu, view, bumper
##   unchanged (the bumper: voice into the selected field, browser_dictation.gd, or the assistant). The right stick
##   click (the headset's own controllers) in pointer mode keeps the picture under the cursor
##   (scripts/pictures/picture_keeper.gd); looking away it is the menu.
## The laser: off on a window by default. It was drawn in front of the screen, so the film layer had to hide while it
## pointed there (film_layer.gd), and it competed with the cursor for the trigger. [browser] laser brings it back as an
## alternative: where it meets the window the cursor follows it, and the trigger clicks there.
## An agent's terminal on the big screen (terminal://): no cursor; trigger Enter, stick up / down arrows, B Escape,
## and with the squeeze held stick up / down scroll back (Shift + Page Up / Down, xterm's own scrollback).
## An Android app on the big screen (scripts/android/android_apps.gd): as any window, but B is its own Back.
## Left controller: trigger and X / Y do nothing on a window; the stick works as for video.
## Desktop: the mouse over the screen is the window's mouse; the keyboard types into the window, except F1 (overlay),
## F3 (menu) and F12 (screenshot). A keyboard paired to the headset arrives the same way.
## Settings: [browser] laser (default false).
## Command: browser_pointer (read); setting browser_laser (the dev link's set).

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
## Window pixel a click goes to now (the cursor in pointer mode, the laser's hit with [browser] laser), or NO_HIT.
var pointer := NO_HIT
## The stick pointer's state.
var cursor := StickCursor.new()
## [browser] laser: the laser on the window as an alternative pointer.
var laser := false
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
var _stick := Vector2.ZERO
var _stick_frame := -1
## The stick was used with the squeeze held, so letting go of the squeeze is no right click.
var _grip_scrolled := false
var _drawn_alpha := -1.0
var _drawn_px := Vector2(-2, -2)


func _ready() -> void:
	if main != null and main.get("settings") != null:
		laser = bool(main.settings.get_value(SECTION, "laser", false))
	register_commands()


func get_source() -> WindowVideoSource:
	var src: Object = main.player.source
	return src as WindowVideoSource if src is WindowVideoSource else null


## A captured window is on the flat screen and the menu is hidden.
func is_active() -> bool:
	var src := get_source()
	return src != null and src.has_frame() and not main.menu_shown \
			and (main.mode as VideoMode).projection == VideoMode.Proj.FLAT


## The window takes the stick pointer: any window but an agent's terminal.
func has_cursor() -> bool:
	var src := get_source()
	return is_active() and not src.is_terminal()


## The UI layer leaves this hand's laser alone: it is the window's pointer ([browser] laser only).
func owns_laser(hand: XRHand) -> bool:
	return laser and main.use_xr and hand == main.right_hand and has_cursor()


## [browser] laser.
func set_laser(on: bool) -> void:
	laser = on
	main.settings.set_value(SECTION, "laser", true if on else null)
	if not on and main.use_xr:
		main.right_hand.set_laser(false)
	main.update_controller_labels()


## The right controller's legends on the window for the mode now (main.gd's controller_labels()): {} for a terminal.
func window_labels() -> Dictionary:
	var src := get_source()
	if src == null or src.is_terminal():
		return {}
	if cursor.mode:
		# The stick click keeps the picture under the cursor: said only while there is one (picture_keeper.gd).
		var keeper: Node = main.get("picture_keeper")
		if keeper != null and bool(keeper.get("over_image")):
			var t: Dictionary = main.WINDOW_POINTER_LABELS.duplicate()
			t["stick_click"] = main.KEEP_PICTURE_LABEL
			return t
		return main.WINDOW_POINTER_LABELS
	return main.WINDOW_LABELS if laser else main.WINDOW_AWAY_LABELS


## The stick clicked in pointer mode: the cursor back where it was before the click's nudge, and held there a moment
## (stick_cursor.gd freeze()). Returns that window pixel, or NO_HIT outside pointer mode.
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
	var active := is_active()
	if active != _was_active:
		_was_active = active
		if not active:
			_release_all()
			cursor.reset()
		main.update_controller_labels()
	if not active or not (main.use_xr or test_xr) or not has_cursor():
		pointer = NO_HIT
		if cursor.mode or cursor.alpha > 0.0:
			cursor.reset()
			main.update_controller_labels()
		_draw_cursor()
		return
	var src := get_source()
	var size := Vector2(src.get_size())
	if size.x >= 1.0 and size.y >= 1.0:
		cursor.size = size
	var hand: XRHand = main.right_hand
	var laser_px: Variant = null
	if laser and main.use_xr and hand.get_is_active() and not (main.ui != null and main.ui.laser_in_use(hand)):
		var hit := ray_to_window(hand.get_ray_origin(), hand.get_ray_direction())
		hand.set_laser(true, float(hit.get("distance", 3.0)), not hit.is_empty())
		if not hit.is_empty():
			laser_px = hit["pixel"]
	var uv: Variant = null
	var g := gaze_ray()
	if not g.is_empty():
		var h := ray_to_uv(g[0], g[1])
		if not h.is_empty():
			uv = h["uv"]
	var stick := _stick if _stick_frame == Engine.get_process_frames() else Vector2.ZERO
	cursor.step(delta, uv, stick, hand.grip_down, _left_down, laser_px)
	pointer = cursor.pos if cursor.mode else NO_HIT
	if cursor.mode and pointer.distance_to(_last_sent) >= 0.5:
		_last_sent = pointer
		src.send_pointer(pointer)
	if cursor.mode_changed:
		main.update_controller_labels()
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
	if src != null:
		for b: int in _mouse_down:
			src.send_button(b, false)
	_mouse_down.clear()
	_arrow_hold = -1.0
	_last_sent = NO_HIT


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
		if pointer != NO_HIT:
			src.send_pointer(pointer)
		src.send_button(1, false)
		_left_down = false
	return true


## A squeeze tap (main.gd measured it): right click at the cursor. False when there is none (looking away). A squeeze
## that scrolled with the stick is no tap.
func on_grip_tap(hand: XRHand) -> bool:
	if not is_active() or hand != main.right_hand:
		return false
	if _grip_scrolled:
		_grip_scrolled = false
		return true
	if pointer == NO_HIT:
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
	_stick = stick
	_stick_frame = Engine.get_process_frames()
	if not hand.grip_down:
		_grip_scrolled = false
	if cursor.mode and not hand.grip_down:
		# Pointer mode: step() moves the cursor with this frame's stick.
		_arrow_hold = -1.0
		return true
	if hand.grip_down and stick.length() > SCROLL_DEAD_ZONE:
		_grip_scrolled = true
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
			"window": {"width": size.x, "height": size.y}, "gaze": gaze_source if has_cursor() else "",
			"laser": laser}


func register_commands() -> void:
	DevCommands.register("browser_pointer", func(_args: Dictionary, _ctx: DevCommands.Call) -> Variant:
		return status(), {"assistant": "read",
		"description": "The stick pointer on the window on the big screen (the browser): active (a window has the "
				+ "controllers, menu hidden), pointer_mode (the viewer looks at the screen, so the right stick moves "
				+ "the cursor and the trigger clicks; else the stick scrolls), cursor_shown, cursor {x, y} in window "
				+ "pixels (null before it first showed; it never follows the gaze, only the stick moves it), window "
				+ "{width, height}, gaze (eyes, head or none: what chooses the mode), laser.",
		"returns": "{active, cursor_window, pointer_mode, cursor_shown, cursor, window, gaze, laser}"})
	DevCommands.register_setting("browser_laser", func() -> bool: return laser,
			func(v: Variant) -> void: set_laser(bool(v)), {"type": "bool",
			"description": "The laser on a window as well as the stick pointer ([browser] laser)."})
