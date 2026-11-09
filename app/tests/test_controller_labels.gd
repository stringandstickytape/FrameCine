extends SceneTree

## Unit tests for the controller labels: label texts per bound profile (main.gd's CONTROL_LABELS through the action
## map) and render model node names -> inputs (controller_visual.gd). Run:
##   godot --headless --xr-mode off --path app --script res://tests/test_controller_labels.gd

const Main := preload("res://scripts/main.gd")
const ControllerVisual := preload("res://scripts/xr/controller_visual.gd")
const HEADSET_PROFILE := "/interaction_profiles/valve/frame_controller_valve"

var _failures := 0


func _init() -> void:
	var app: Node = Main.new()
	var right: Dictionary = app.controller_labels(HEADSET_PROFILE, "right", false)
	var left: Dictionary = app.controller_labels(HEADSET_PROFILE, "left", false)
	print("Headset profile right, menu hidden: %s" % right)
	print("Headset profile left, menu hidden: %s" % left)
	_check("right trigger", right.get("trigger") == "PLAY / PAUSE")
	_check("right A / B", right.get("a") == "NEXT" and right.get("b") == "PREV")
	_check("right menu", right.get("menu") == "MENU")
	_check("right stick: seek + press for menu", str(right.get("thumbstick", "")).begins_with("SEEK / DIST")
			and str(right.get("thumbstick", "")).ends_with("PUSH: MENU"))
	_check("right bumper", right.get("bumper") == "LABELS")
	# Squeeze does nothing of its own: only a captured window or a terminal gives it a legend.
	_check("right squeeze: no legend", not right.has("squeeze"))
	var on_window: Dictionary = app.controller_labels(HEADSET_PROFILE, "right", false, true)
	_check("window: squeeze is the right click", on_window.get("squeeze") == "R-CLICK")
	_check("window: the left hand keeps no squeeze", not app.controller_labels(HEADSET_PROFILE, "left", false, true).has("squeeze"))
	var terminal: Dictionary = app.controller_labels(HEADSET_PROFILE, "right", false, false, true)
	_check("terminal: squeeze scrolls back", terminal.get("squeeze") == "HOLD: SCROLL")
	_check("menu shown: squeeze stays blank", not app.controller_labels(HEADSET_PROFILE, "right", true, true).has("squeeze"))
	# The menu on either controller (docs/ui-design.md, "Revision 2"): the left view button; the overlay moves to the
	# left stick click.
	_check("left view is the menu", left.get("view") == "MENU")
	_check("left stick: seek + press for the overlay", str(left.get("thumbstick", "")).ends_with("PUSH: INFO"))
	_check("left has no A / menu button", not left.has("a") and not left.has("menu"))
	# Y has the sparkle on its cap (controller_visual.gd), not a legend. Both action maps bind it, on the right hand only.
	_check("Y: no text legend", not right.has("y") and not app.controller_labels(HEADSET_PROFILE, "right", true).has("y"))
	for path: String in ["res://xr/openxr_action_map.tres", "res://xr/openxr_action_map_dpad.tres"]:
		var profile: OpenXRInteractionProfile = (load(path) as OpenXRActionMap).find_interaction_profile(HEADSET_PROFILE)
		var y := []
		for i in profile.get_binding_count():
			var binding := profile.get_binding(i)
			if binding.action.resource_name == "agent":
				y.append(binding.binding_path)
		_check("%s: Y on the right is the agent" % path.get_file(), y == ["/user/hand/right/input/y/click"])
		var x := []
		for i in profile.get_binding_count():
			if profile.get_binding(i).action.resource_name == "enter":
				x.append(profile.get_binding(i).binding_path)
		_check("%s: X on the right is Enter" % path.get_file(), x == ["/user/hand/right/input/x/click"])
	# X: no legend until an agent's terminal shows, then ENTER, the menu open or not; the left has no X.
	_check("X: no legend normally", not right.has("x"))
	var enter: Dictionary = app.controller_labels(HEADSET_PROFILE, "right", false, false, false, false, false, {}, false, true)
	var enter_menu: Dictionary = app.controller_labels(HEADSET_PROFILE, "right", true, false, false, false, false, {}, false, true)
	_check("X: ENTER while the terminal shows, the menu open too", enter.get("x") == "ENTER" and enter_menu.get("x") == "ENTER")
	_check("X: the other legends stay", enter.get("trigger") == right.get("trigger") and enter.get("a") == right.get("a"))
	_check("left: no X", not app.controller_labels(HEADSET_PROFILE, "left", false, false, false, false, false, {}, false, true).has("x"))
	_check("X's legend has its place in the layout", ControllerVisual.layout_entry("right", "x").get("line_height", 0.0) > 0.003)
	var left_menu: Dictionary = app.controller_labels(HEADSET_PROFILE, "left", true)
	_check("menu shown: the left view button closes", left_menu.get("view") == "CLOSE")
	# Every profile with a menu action has one on each hand, so one controller is enough.
	for profile: String in [HEADSET_PROFILE, "/interaction_profiles/khr/generic_controller",
			"/interaction_profiles/valve/index_controller", "/interaction_profiles/oculus/touch_controller",
			"/interaction_profiles/khr/simple_controller"]:
		for side: String in ["left", "right"]:
			var texts: Dictionary = app.controller_labels(profile, side, false)
			var has_menu := false
			for t: Variant in texts.values():
				var lines := str(t).split("\n")
				has_menu = has_menu or lines.has("MENU") or lines.has("PUSH: MENU")
			_check("%s %s: a menu input" % [profile.get_file(), side], has_menu)
	var right_menu: Dictionary = app.controller_labels(HEADSET_PROFILE, "right", true)
	_check("menu shown: trigger clicks", right_menu.get("trigger") == "CLICK")
	_check("menu shown: menu closes", right_menu.get("menu") == "CLOSE")
	_check("menu shown: stick scrolls", str(right_menu.get("thumbstick", "")).begins_with("SCROLL"))
	var touch_left: Dictionary = app.controller_labels("/interaction_profiles/oculus/touch_controller", "left", false)
	_check("third-party profile left X / Y / menu", touch_left.get("x") == "NEXT" and touch_left.get("y") == "PREV"
			and touch_left.get("menu") == "MENU")
	var generic_left: Dictionary = app.controller_labels("/interaction_profiles/khr/generic_controller", "left", false)
	_check("generic left primary -> x = menu", generic_left.get("x") == "MENU")
	var simple: Dictionary = app.controller_labels("/interaction_profiles/khr/simple_controller", "right", false)
	_check("simple select -> trigger", simple.get("trigger") == "PLAY / PAUSE")
	_check("no profile: no labels", app.controller_labels("", "right", false).is_empty())
	app.free()

	for c: Array in [["trigger", "trigger"], ["Trigger_Pivot", "trigger"], ["thumbstick_x_axis", "thumbstick"],
			["JoystickTilt", "thumbstick"], ["joystick", "thumbstick"], ["grip_button", "squeeze"], ["button_a", "a"],
			["a_button", "a"], ["AButton", "a"], ["abutton", "a"], ["DPadUp", "dpad_up"], ["b", "b"], ["menu_button", "menu"],
			["view", "view"], ["system_button", "system"], ["bumper", "bumper"], ["dpad_up", "dpad_up"],
			["body", "body"], ["battery_indicator", ""], ["x", "x"], ["dpad", "dpad"], ["status", ""],
			# The headset's runtime models (worn run): left and right node names.
			["button_grip", "squeeze"], ["button_system", "system"], ["button_view", "view"], ["button_menu", "menu"],
			["button_y", "y"], ["{frame_controller}frame_controller_left", ""]]:
		var got := ControllerVisual.match_node_name(c[0])
		_check("node '%s' -> '%s' (got '%s')" % [c[0], c[1], got], got == c[1])

	print("test_controller_labels: %s" % ("all passed" if _failures == 0 else "%d FAILED" % _failures))
	quit(_failures)


func _check(what: String, ok: bool) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL " + what)
