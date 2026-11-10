## The floating keyboard without XR: physical layout, balanced events, modifier chords, repeat, routing, the real
## menu's fields, geometry and persistence, and two-hand pokes.
## godot --headless --xr-mode off --path app --script res://tests/test_keyboard.gd
extends SceneTree

const Layout := preload("res://keyboard/key_layout.gd")
const Router := preload("res://keyboard/keyboard_router.gd")
const State := preload("res://keyboard/key_state.gd")
const Keyboard := preload("res://keyboard/floating_keyboard.gd")
const Commands := preload("res://scripts/dev/dev_commands.gd")
const CommandHost := preload("res://scripts/dev/command_host.gd")

class Recorder extends Node:
	var events: Array[InputEventKey] = []
	func target(repeat := true) -> Dictionary:
		return {"object": self, "identity": self, "name": "test field", "repeat": repeat,
				"send": func(e: InputEventKey) -> void: events.append(e.duplicate())}

class Harness extends Node:
	var ui: Node

var _checks := 0
var _failures := 0
var main: Node3D
var recorder := Recorder.new()
var harness := Harness.new()
var router := Router.new()
var state := State.new()
var _remote := false


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	root.add_child(harness)
	root.add_child(recorder)
	router.app = harness
	router.providers.append(func() -> Dictionary: return recorder.target(not _remote))
	state.router = router
	_layout()
	_events()
	_modifiers()
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.settings.read_only = true
	root.add_child(main)
	current_scene = main
	await _frames(4)
	main.ui.set_process(false)
	await _fields_and_routing()
	await _pane()
	await _provider_order()
	await _window_paths()
	main.queue_free()
	harness.queue_free()
	recorder.queue_free()
	await _frames(3)
	print("Keyboard test: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(0 if _failures == 0 else 1)


func _layout() -> void:
	var keys := Layout.keys()
	_check("ANSI has exactly 104 physical keys", keys.size() == 104)
	var ids := {}
	var required: Array[int] = [KEY_ESCAPE, KEY_PRINT, KEY_SCROLLLOCK, KEY_PAUSE, KEY_BACKSPACE, KEY_TAB,
			KEY_BACKSLASH, KEY_CAPSLOCK, KEY_ENTER, KEY_SPACE, KEY_MENU, KEY_INSERT, KEY_HOME, KEY_PAGEUP,
			KEY_DELETE, KEY_END, KEY_PAGEDOWN, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_NUMLOCK,
			KEY_KP_DIVIDE, KEY_KP_MULTIPLY, KEY_KP_SUBTRACT, KEY_KP_ADD, KEY_KP_ENTER, KEY_KP_PERIOD]
	for code in range(KEY_A, KEY_Z + 1): required.append(code)
	for code in range(KEY_0, KEY_9 + 1): required.append(code)
	for code in range(KEY_F1, KEY_F12 + 1): required.append(code)
	for code in range(KEY_KP_0, KEY_KP_9 + 1): required.append(code)
	for code in [KEY_QUOTELEFT, KEY_MINUS, KEY_EQUAL, KEY_BRACKETLEFT, KEY_BRACKETRIGHT, KEY_SEMICOLON,
			KEY_APOSTROPHE, KEY_COMMA, KEY_PERIOD, KEY_SLASH]: required.append(code)
	for k in keys:
		var id := "%d:%d" % [k.code, k.location]
		_check("physical key %s is unique and in bounds" % id, not ids.has(id)
				and Rect2(Vector2.ZERO, Layout.SIZE).encloses(k.rect))
		ids[id] = true
	for code in required:
		_check("Godot code %s present" % OS.get_keycode_string(code), keys.any(func(k: Dictionary) -> bool: return int(k.code) == code))
	for code in Layout.MODIFIERS:
		for location in [KEY_LOCATION_LEFT, KEY_LOCATION_RIGHT]:
			_check("modifier %s location %d" % [OS.get_keycode_string(code), location], ids.has("%d:%d" % [code, location]))
	_check("wide keys have ANSI widths", is_equal_approx((keys[state.find_key(KEY_SPACE)].rect as Rect2).size.x, 6.16)
			and is_equal_approx((keys[state.find_key(KEY_TAB)].rect as Rect2).size.x, 1.41)
			and is_equal_approx((keys[state.find_key(KEY_CAPSLOCK)].rect as Rect2).size.x, 1.66))
	_check("number row has shifted legends", keys[state.find_key(KEY_1)].shifted == "!"
			and keys[state.find_key(KEY_BRACKETLEFT)].shifted == "{")
	_check("pad Enter has its own code", state.find_key(KEY_ENTER) != state.find_key(KEY_KP_ENTER))


func _events() -> void:
	recorder.events.clear()
	state.press("left", state.find_key(KEY_A))
	_check("laser down is a physical down", recorder.events.size() == 1 and recorder.events[0].pressed
			and recorder.events[0].keycode == KEY_A and recorder.events[0].physical_keycode == KEY_A
			and recorder.events[0].unicode == 97)
	state.step(0.49)
	_check("repeat waits 500 ms", recorder.events.size() == 1)
	state.step(0.011)
	_check("field repeat is an echo down", recorder.events.size() == 2 and recorder.events[1].echo)
	state.step(0.1)
	_check("field repeats at 30 Hz", recorder.events.size() == 5)
	state.release("left")
	_check("release is key up", not recorder.events[-1].pressed and not recorder.events[-1].echo)
	_remote = true
	recorder.events.clear()
	state.press("left", state.find_key(KEY_F5))
	state.step(2.0)
	state.release("left")
	_check("windows get just down and up for native repeat", recorder.events.size() == 2)
	_remote = false
	recorder.events.clear()
	state.press("left", state.find_key(KEY_A))
	state.press("right", state.find_key(KEY_A))
	state.release("left")
	_check("two hands cannot release each other's same key", recorder.events.size() == 1)
	state.release("right")
	_check("last hand releases the shared physical key", recorder.events.size() == 2 and not recorder.events[1].pressed)
	recorder.events.clear()
	state.press("absent", state.find_key(KEY_A), {})
	state.release("absent")
	_check("a captured missing target stays missing", recorder.events.is_empty())
	state.press("modifier", state.find_key(KEY_CTRL))
	state.press("key", state.find_key(KEY_C))
	state.cancel()
	_check("cancellation balances held chords", recorder.events.size() == 4
			and not recorder.events[-1].pressed and router._down.is_empty())
	state.press("modifier", state.find_key(KEY_SHIFT))
	state.press("key", state.find_key(KEY_A))
	state.step(0.51)
	state.release("modifier")
	state.step(0.034)
	_check("field repeat follows a released Shift", recorder.events[-1].echo and recorder.events[-1].unicode == 97
			and not recorder.events[-1].shift_pressed)
	state.release("key")


func _tap(code: int, source := "tap") -> void:
	state.press(source, state.find_key(code))
	state.release(source)


func _modifiers() -> void:
	for code in Layout.MODIFIERS:
		state.cancel()
		recorder.events.clear()
		_tap(code)
		_check("modifier tap latches without typing", state.modifier_on(code) and recorder.events.is_empty())
		_tap(KEY_C)
		_check("one-shot wraps real down/key/up events", recorder.events.size() == 4 and recorder.events[0].keycode == code
				and recorder.events[0].pressed and recorder.events[1].keycode == KEY_C and recorder.events[1].pressed
				and not recorder.events[2].pressed and recorder.events[3].keycode == code and not recorder.events[3].pressed)
		_check("one-shot consumed", not state.modifier_on(code))
		_tap(code)
		_tap(code)
		_check("second tap locks", int(state.modifiers.get(state.find_key(code), 0)) == 2)
		_tap(KEY_C)
		_tap(KEY_C)
		_check("lock survives two keys", state.modifier_on(code))
		_tap(code)
		_check("third tap unlocks", not state.modifier_on(code))
		recorder.events.clear()
		state.press("hold", state.find_key(code))
		state.press("key", state.find_key(KEY_R))
		state.release("key")
		_check("held modifier stays down after the letter comes up", recorder.events.size() == 3)
		state.release("hold")
		_check("releasing used modifier sends up without latching", recorder.events.size() == 4
				and recorder.events[-1].keycode == code and not recorder.events[-1].pressed and not state.modifier_on(code))
		recorder.events.clear()
		state.press("hold", state.find_key(code))
		state.press("key", state.find_key(KEY_R))
		state.release("hold")
		_check("modifier can release before its letter", recorder.events.size() == 3 and recorder.events[-1].keycode == code
				and not recorder.events[-1].pressed)
		state.release("key")
	state.cancel()
	_tap(KEY_CAPSLOCK)
	recorder.events.clear()
	_tap(KEY_A)
	_check("Caps lights and capital Unicode", state.caps and recorder.events[0].unicode == 65)
	_tap(KEY_SHIFT)
	recorder.events.clear()
	_tap(KEY_A)
	_check("Shift reverses Caps", recorder.events[1].unicode == 97)
	_tap(KEY_CAPSLOCK)
	_tap(KEY_NUMLOCK)
	_check("Num toggles and pad Unicode follows it", not state.num and state.event(state.find_key(KEY_KP_7), true).unicode == 0)
	_tap(KEY_NUMLOCK)
	_check("Num on gives a pad digit", state.num and state.event(state.find_key(KEY_KP_7), true).unicode == 55)
	state.press("left", state.find_key(KEY_NUMLOCK))
	state.press("right", state.find_key(KEY_NUMLOCK))
	_check("two hands toggle a shared lock only once", not state.num)
	state.release("left")
	state.release("right")
	_tap(KEY_NUMLOCK)
	_tap(KEY_SCROLLLOCK)
	_check("Scroll Lock light toggles", state.scroll)
	state.cancel()


func _fields_and_routing() -> void:
	main.ui.show_panel()
	var field := LineEdit.new()
	field.size = Vector2(200, 40)
	main.ui.panel.ui.add_child(field)
	field.grab_focus()
	await _frames(1)
	var kr: Router = main.ui.keyboard.router
	var received: Array[InputEventKey] = []
	field.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventKey: received.append(e.duplicate()))
	var ks := State.new()
	ks.router = kr
	var fallback := kr.providers.duplicate()
	kr.providers.clear()
	kr.providers.append(func() -> Dictionary: return recorder.target())
	ks.press("field", ks.find_key(KEY_B))
	ks.release("field")
	_check("menu field wins over a registered window", field.text == "b")
	_check("field receives real down and up with all key properties", received.size() == 2
			and received[0].physical_keycode == KEY_B and received[0].keycode == KEY_B
			and received[0].unicode == 98 and received[0].location == KEY_LOCATION_UNSPECIFIED and not received[1].pressed)
	ks.press("field", ks.find_key(KEY_C))
	ks.step(0.51)
	ks.release("field")
	_check("field repeat edits text and has echo", field.text == "bcc" and received[-2].echo)
	ks.press("field", ks.find_key(KEY_D))
	var next_field := LineEdit.new()
	main.ui.panel.ui.add_child(next_field)
	next_field.grab_focus()
	await _frames(1)
	ks.step(0.6)
	ks.release("field")
	_check("repeat stops when its field loses focus", next_field.text == "")
	next_field.release_focus()
	next_field.queue_free()
	field.release_focus()
	recorder.events.clear()
	ks.press("old", ks.find_key(KEY_F5))
	kr.providers.clear()
	ks.release("old")
	_check("release follows the captured target after focus changes", recorder.events.size() == 2 and not recorder.events[1].pressed)
	_check("no target has a plain status", kr.target_name() == "Nothing to type into")
	ks.press("none", ks.find_key(KEY_A))
	ks.release("none")
	_check("no target safely consumes a key", ks.held.is_empty())
	var second := Recorder.new()
	root.add_child(second)
	kr.providers.append(func() -> Dictionary: return recorder.target())
	kr.providers.append(func() -> Dictionary: return second.target())
	ks.press("first", ks.find_key(KEY_TAB))
	ks.release("first")
	_check("registered targets keep their priority", recorder.events.size() == 4 and second.events.is_empty())
	kr.providers.pop_front()
	ks.press("second", ks.find_key(KEY_TAB))
	ks.release("second")
	_check("next target takes over when the first disappears", second.events.size() == 2)
	kr.providers = fallback
	field.queue_free()
	second.queue_free()
	await _frames(1)
	var area := TextEdit.new()
	area.size = Vector2(200, 60)
	main.ui.panel.ui.add_child(area)
	area.grab_focus()
	await _frames(1)
	ks.press("area", ks.find_key(KEY_A))
	ks.release("area")
	_check("TextEdit is a menu target too", area.text == "a")
	area.queue_free()
	await _frames(1)


func _pane() -> void:
	var kb: Keyboard = main.ui.keyboard
	kb.set_shown(true)
	var pose := kb.global_transform
	var head: Vector3 = main.camera.global_position
	_check("first placement below and in front of the head", pose.origin.y < head.y and pose.origin.distance_to(head) < 1.0)
	_check("ordinary board with private key lights", kb._mesh.get_layer_mask_value(1)
			and not kb._light_mesh.get_layer_mask_value(1)
			and kb._light_mesh.get_layer_mask_value(kb.VideoScreen.PRIVATE_LAYER)
			and kb._light_surface.lights_only)
	_check("keyboard tilts its front towards the head", pose.basis.z.dot((head - pose.origin).normalized()) > 0.999)
	var ray := kb.hit(pose.origin + pose.basis.z, -pose.basis.z)
	_check("ray hits the face", not ray.is_empty() and is_equal_approx(float(ray.distance), 1.0))
	_check("back face rejects rays", kb.hit(pose.origin - pose.basis.z, pose.basis.z).is_empty())
	var hand: Node3D = main.right_hand
	var other: Node3D = main.left_hand
	kb.aims[hand] = ray
	_check("grip takes the keyboard", kb.on_grip(hand, true) and kb.owns_laser(hand))
	kb.on_stick(hand, Vector2.RIGHT, 100)
	_check("resize clamps at 1.6 m", is_equal_approx(kb.width, Keyboard.MAX_WIDTH))
	kb.on_stick(hand, Vector2.LEFT, 100)
	_check("resize clamps at 0.35 m", is_equal_approx(kb.width, Keyboard.MIN_WIDTH))
	kb.on_stick(hand, Vector2.UP, 100)
	_check("holding distance has a near limit", float(kb._holds[hand].distance) >= 0.2)
	kb.test_xr = true
	var before := kb.global_position
	kb.step(0.0)
	_check("held pane follows the ray at the captured distance", not kb.global_position.is_equal_approx(before)
			and kb.global_position.is_equal_approx(hand.get_ray_origin() + hand.get_ray_direction() * float(kb._holds[hand].distance)))
	kb.test_xr = false
	pose = kb.global_transform
	kb.on_grip(hand, false)
	_check("pose and size saved in settings", main.settings.has_value("keyboard", "transform")
			and is_equal_approx(float(main.settings.get_value("keyboard", "width", 0)), kb.width))
	kb.set_width(0.85)
	kb.router = router
	kb.state.router = router
	recorder.events.clear()
	var index := kb.state.find_key(KEY_F5)
	kb.aims[hand] = {"key": index, "point": (kb.state.keys[index].rect as Rect2).get_center(), "distance": 1.0}
	kb.on_trigger(hand, true)
	kb.aims.erase(hand)
	kb.on_trigger(hand, false)
	_check("laser key release works off the keyboard", recorder.events.size() == 2 and not recorder.events[1].pressed)
	recorder.events.clear()
	index = kb.state.find_key(KEY_A)
	var centre: Vector2 = (kb.state.keys[index].rect as Rect2).get_center()
	var local := Vector3((centre.x - Layout.SIZE.x / 2) * kb.width / Layout.SIZE.x,
			(Layout.SIZE.y / 2 - centre.y) * kb.width / Layout.SIZE.x, 0.02)
	kb._poke(hand, kb.to_global(local))
	kb._poke(hand, kb.to_global(local - Vector3(0, 0, 0.03)))
	_check("inward tip crossing presses", recorder.events.size() == 1 and recorder.events[0].pressed)
	kb._poke(other, kb.to_global(local))
	kb._poke(other, kb.to_global(local - Vector3(0, 0, 0.03)))
	_check("other poke cannot share the pressed key", recorder.events.size() == 1 and not kb._pokes.has(other))
	kb._poke(hand, kb.to_global(local - Vector3(0, 0, 0.019)))
	_check("poke hysteresis holds through the face", recorder.events.size() == 1)
	kb._poke(hand, kb.to_global(local))
	_check("withdrawal releases poke", recorder.events.size() == 2 and not recorder.events[-1].pressed)
	kb.aims[hand] = {"key": kb.state.find_key(KEY_CTRL), "point": Vector2.ZERO, "distance": 1.0}
	kb.on_trigger(hand, true)
	kb.set_shown(false)
	_check("close releases and clears every hand", kb.state.held.is_empty() and kb.state.modifiers.is_empty()
			and kb._pokes.is_empty() and not kb.owns_laser(hand))
	kb.set_shown(true)
	_check("reopening preserves the world pose", kb.global_transform.is_equal_approx(pose))
	# A letter goes down with the trigger: no wait for the release.
	recorder.events.clear()
	kb.state.press("shift", kb.state.find_key(KEY_SHIFT))
	index = kb.state.find_key(KEY_A)
	kb.aims[hand] = {"key": index, "point": (kb.state.keys[index].rect as Rect2).get_center(), "distance": 1.0}
	kb.on_trigger(hand, true)
	_check("laser letter is sent on trigger down", _typed(recorder.events) == "A")
	kb.state.release("shift")
	kb.on_trigger(hand, false)
	_check("laser tap keeps held Shift's case", _typed(recorder.events) == "A" and not kb.state.modifier_on(KEY_SHIFT)
			and not recorder.events[-1].pressed)
	kb.aims[hand] = {"key": -1, "point": kb.CLOSE.get_center(), "distance": 1.0}
	kb.on_trigger(hand, true)
	_check("Close box in the bar closes the keyboard", not kb.visible)
	kb.on_trigger(hand, false)
	kb.set_shown(true)
	_check("no key lies under the bar", kb.state.keys.all(func(k: Dictionary) -> bool: return (k.rect as Rect2).position.y >= 1.0))
	kb.aims[hand] = {"key": index, "point": (kb.state.keys[index].rect as Rect2).get_center(), "distance": 1.0}
	kb.state.press("shift", kb.state.find_key(KEY_SHIFT))
	kb.state.release("shift")
	recorder.events.clear()
	kb.on_trigger(hand, true)
	var other_index := kb.state.find_key(KEY_B)
	kb.aims[other] = {"key": other_index, "point": (kb.state.keys[other_index].rect as Rect2).get_center(), "distance": 1.0}
	kb.on_trigger(other, true)
	kb.on_trigger(hand, false)
	kb.on_trigger(other, false)
	_check("only the first of two taps consumes one-shot Shift", _typed(recorder.events) == "Ab")
	var moved := kb.global_position
	var world_pose := kb.global_transform
	main.ui.hide_panel()
	main.camera.position.x += 0.2
	main.ui.show_panel()
	kb.aims.clear()
	kb.state.cancel()
	kb._redraw()
	kb._viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	kb._redraw()
	_check("an unchanged keyboard is not drawn again", kb._viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	kb.aims[hand] = {"key": 3, "point": Vector2.ZERO, "distance": 1.0}
	kb._redraw()
	_check("a newly pointed-at key draws once", kb._viewport.render_target_update_mode == SubViewport.UPDATE_ONCE
			and kb._light_viewport.render_target_update_mode == SubViewport.UPDATE_ONCE)
	kb.aims.clear()
	_check("opening the menu leaves the keyboard world-locked", kb.global_transform.is_equal_approx(world_pose))
	main.ui.recentre()
	_check("menu recentre also replaces the open keyboard", not kb.global_position.is_equal_approx(moved)
			and kb.global_transform.is_equal_approx(main.settings.get_value("keyboard", "transform", Transform3D())))
	main.camera.position.x -= 0.2
	kb.router = Router.new()
	kb.router.setup(main)
	kb.state.router = kb.router
	CommandHost.ensure(self)
	var answer: Variant = await Commands.execute("keyboard", {"show": false}, true)
	_check("dev keyboard command closes without content", not kb.visible and answer is Dictionary)
	if "--keyboard-shot" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		kb.set_shown(true)
		kb._viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		kb._light_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		kb._surface.queue_redraw()
		kb.aims[hand] = {"key": kb.state.find_key(KEY_G), "point": Vector2.ZERO, "distance": 1.0}
		kb._light_surface.queue_redraw()
		for i in 8:
			kb._surface.queue_redraw()
			kb._light_surface.queue_redraw()
			await _frames(1)
		RenderingServer.force_draw()
		var board := kb._viewport.get_texture().get_image()
		var ink := 0
		for x in range(205, 295):
			for y in range(105, 195):
				if board.get_pixel(x, y).r > 0.4: ink += 1
		_check("rendered ordinary F1 legend has visible ink", ink > 30)
		_check("the board has a solid ground between keys", board.get_pixel(1150, 205).a > 0.8
				and board.get_pixel(1450, 150).a > 0.8)
		board.save_png("/tmp/framecine-keyboard.png")
		kb._light_viewport.get_texture().get_image().save_png("/tmp/framecine-keyboard-gestures.png")
		kb.set_shown(false)


class FakePc extends Node:
	var focused: Node
	var events: Array = []
	func keyboard_key(e: InputEventKey, pane: Node) -> void: events.append([pane, e.pressed])

class FakeAgents extends Node:
	var window: Object
	func keyboard_target() -> Object: return window
	func keyboard_key(e: InputEventKey, target: Object, _physical: bool) -> void: target.send_godot_key(e.keycode, e.pressed)

class FakePointer extends Node:
	var window: Object
	func get_source() -> Object: return window
	func keyboard_key(e: InputEventKey, target: Object, _physical: bool) -> void: target.send_godot_key(e.keycode, e.pressed)

class Features extends Node:
	var pc_windows: Node

class RoutingApp extends Node:
	var ui: Node
	var features := Features.new()
	var local_agents := FakeAgents.new()
	var window_pointer := FakePointer.new()


func _provider_order() -> void:
	var fixture := RoutingApp.new()
	root.add_child(fixture)
	fixture.add_child(fixture.features)
	fixture.add_child(fixture.local_agents)
	fixture.add_child(fixture.window_pointer)
	var pc := FakePc.new()
	fixture.features.add_child(pc)
	fixture.features.pc_windows = pc
	var pane := Node.new()
	fixture.add_child(pane)
	pc.focused = pane
	var terminal := FakeWindow.new()
	var browser := FakeWindow.new()
	fixture.local_agents.window = terminal
	fixture.window_pointer.window = browser
	var kr := Router.new()
	kr.setup(fixture)
	var t := kr.capture()
	_check("actual router chooses focused PC before terminal and browser", t.identity == pane)
	pc.focused = null
	t = kr.capture()
	_check("actual router chooses terminal before browser", t.identity == terminal)
	fixture.local_agents.window = null
	t = kr.capture()
	_check("actual router falls back to browser", t.identity == browser)
	var e := state.event(state.find_key(KEY_F5), true)
	kr.key(e, t)
	fixture.window_pointer.window = null
	e.pressed = false
	kr.key(e, t)
	_check("actual browser adapter keeps its captured source on up", browser.events == [[KEY_F5, true], [KEY_F5, false]])
	_check("actual router chooses nothing with all windows gone", kr.capture().is_empty())
	# The X11 API has one modifier code for both locations. Its adapter must count them together.
	terminal.events.clear()
	fixture.local_agents.window = terminal
	t = kr.capture()
	var shift := state.find_key(KEY_SHIFT)
	e = state.event(shift, true)
	kr.key(e, t)
	var right := e.duplicate() as InputEventKey
	right.location = KEY_LOCATION_RIGHT
	kr.key(right, t)
	e.pressed = false
	kr.key(e, t)
	_check("X11 merges modifier locations while either is held", terminal.events == [[KEY_SHIFT, true]])
	right.pressed = false
	kr.key(right, t)
	_check("X11 releases the shared modifier once", terminal.events == [[KEY_SHIFT, true], [KEY_SHIFT, false]])
	fixture.queue_free()
	await _frames(1)


func _typed(events: Array) -> String:
	var text := ""
	for e: InputEventKey in events:
		if e.pressed and e.unicode >= 32: text += String.chr(e.unicode)
	return text


class FakeWindow extends RefCounted:
	var events: Array = []
	func has_frame() -> bool: return true
	func is_ended() -> bool: return false
	func send_char(u: int) -> void: events.append(["char", u])
	func send_godot_key(code: int, down: bool) -> void: events.append([code, down])


func _window_paths() -> void:
	var window := FakeWindow.new()
	var e := state.event(state.find_key(KEY_A), true)
	main.window_pointer.keyboard_key(e, window, true)
	e.pressed = false
	main.window_pointer.keyboard_key(e, window, true)
	_check("browser shared path gets physical down and up", window.events == [[KEY_A, true], [KEY_A, false]])
	window.events.clear()
	e = state.event(state.find_key(KEY_F1), true)
	main.local_agents.keyboard_key(e, window, true)
	e.pressed = false
	main.local_agents.keyboard_key(e, window, true)
	_check("terminal shared path gets even reserved function keys", window.events == [[KEY_F1, true], [KEY_F1, false]])
	window.events.clear()
	e = state.event(state.find_key(KEY_A), true)
	main.window_pointer.keyboard_key(e, window)
	_check("paired keyboard retains its Unicode path", window.events == [["char", 97]])


func _frames(count: int) -> void:
	for i in count: await process_frame


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok: _failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", what])
