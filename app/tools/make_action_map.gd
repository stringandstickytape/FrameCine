extends SceneTree

## Writes res://xr/openxr_action_map.tres, the app's XR action map. Run from the repository root:
##   godot --headless --xr-mode off --path app --script res://tools/make_action_map.gd
## The engine's default action map has no binding for the headset's own controller profile, so the app ships its own.
## One action set, "player", with the actions the app reads through XRController3D:
##   aim_pose, grip_pose      poses (the menu laser comes from the aim pose). The engine renames pose actions on the
##                            tracker: aim_pose -> "aim", grip_pose -> "grip", so XRController3D.pose is "aim", and
##                            no other action may be called "aim", "grip" or "default" (the engine drops it silently).
##   trigger (float)          menu shown: click under the laser; menu hidden: play / pause
##   squeeze (float)          grip held: move the screen (flat) or turn the sphere; tap: screen to where you look
##   thumbstick (vector2)     on the menu: scroll; else left/right seek 10 s, up/down screen distance
##   menu (bool)              open / close the menu panel (held: recentre it); on every profile each hand has one, so
##                            a single controller is enough (docs/ui-design.md, "Revision 2")
##   stick_click (bool)       the headset profile's right stick click: the menu, except while the browser's stick
##                            pointer is on an image, where it keeps the picture (scripts/pictures/picture_keeper.gd)
##   overlay (bool)           show / hide the info overlay
##   next_file / prev_file    next / previous video in the folder (or test pattern)
##   labels (bool)            the bumper: the left half of the snapshot chord (headset profile: either bumper)
##   agent (bool)             the agent's pane on or off (headset profile: Y, on the right controller only)
##   haptic                   click feedback
## It also writes res://xr/openxr_action_map_dpad.tres, the same map plus the left d-pad on the headset's own profile
## (chapter_prev / chapter_next on left / right, replay on down; scripts/play/chapters.gd, catch_up.gd). That map is
## opt-in until a device run shows the runtime accepts the d-pad paths, because one rejected path voids the whole
## profile: put app/override.cfg next to project.godot with
##   [xr]
##   openxr/default_action_map="res://xr/openxr_action_map_dpad.tres"

const OUT := "res://xr/openxr_action_map.tres"
const OUT_DPAD := "res://xr/openxr_action_map_dpad.tres"
const LEFT := "/user/hand/left"
const RIGHT := "/user/hand/right"
## OpenXRAction.OPENXR_ACTION_HAPTIC: in the C++ enum but not bound to scripts in 4.7.
const ACTION_HAPTIC := 4


func _init() -> void:
	var err := ResourceSaver.save(_build(false), OUT)
	print("Saved %s: %s" % [OUT, error_string(err)])
	var err_dpad := ResourceSaver.save(_build(true), OUT_DPAD)
	print("Saved %s: %s" % [OUT_DPAD, error_string(err_dpad)])
	quit(0 if err == OK and err_dpad == OK else 1)


## dpad: also the left d-pad actions on the headset's own profile (the opt-in map).
func _build(dpad: bool) -> OpenXRActionMap:
	var action_map := OpenXRActionMap.new()
	var action_set := OpenXRActionSet.new()
	action_set.resource_name = "player"
	action_set.localized_name = "Video player"
	action_set.priority = 0
	var hands := PackedStringArray([LEFT, RIGHT])
	var actions := {}
	var specs: Array = [
			["aim_pose", "Aim pose", OpenXRAction.OPENXR_ACTION_POSE],
			["grip_pose", "Grip pose", OpenXRAction.OPENXR_ACTION_POSE],
			["trigger", "Click / play-pause (trigger)", OpenXRAction.OPENXR_ACTION_FLOAT],
			["squeeze", "Move screen (grip squeeze)", OpenXRAction.OPENXR_ACTION_FLOAT],
			["thumbstick", "Scroll / seek / distance", OpenXRAction.OPENXR_ACTION_VECTOR2],
			["menu", "Show / hide menu", OpenXRAction.OPENXR_ACTION_BOOL],
			["stick_click", "Menu / keep picture (stick click)", OpenXRAction.OPENXR_ACTION_BOOL],
			["overlay", "Show / hide info overlay", OpenXRAction.OPENXR_ACTION_BOOL],
			["next_file", "Next video", OpenXRAction.OPENXR_ACTION_BOOL],
			["prev_file", "Previous video", OpenXRAction.OPENXR_ACTION_BOOL],
			["labels", "Show controller labels (hold)", OpenXRAction.OPENXR_ACTION_BOOL],
			["agent", "Show / hide the agent's terminal", OpenXRAction.OPENXR_ACTION_BOOL],
			["haptic", "Haptic", ACTION_HAPTIC]]
	if dpad:
		specs.append_array([
				["chapter_prev", "Previous chapter", OpenXRAction.OPENXR_ACTION_BOOL],
				["chapter_next", "Next chapter", OpenXRAction.OPENXR_ACTION_BOOL],
				["replay", "Replay 10 s with subtitles", OpenXRAction.OPENXR_ACTION_BOOL]])
	for spec: Array in specs:
		var action := OpenXRAction.new()
		action.resource_name = spec[0]
		action.localized_name = spec[1]
		action.action_type = spec[2]
		action.toplevel_paths = hands
		action_set.add_action(action)
		actions[spec[0]] = action
	action_map.add_action_set(action_set)

	var both_hands := {
		"aim_pose": "input/aim/pose",
		"grip_pose": "input/grip/pose",
		"haptic": "output/haptic",
		"trigger": "input/trigger/value",
		"squeeze": "input/squeeze/value",
		"thumbstick": "input/thumbstick",
	}

	# The headset's own controller profile. Only paths the engine registers for the profile (its controller
	# extension in modules/openxr), and only the ones we need: one path the runtime rejects voids the whole profile's
	# suggestion. The engine lists A/B/X/Y on the right controller and the d-pad and "view" on the left; X and the d-pad
	# are left out until the device shows what it reports. Profile paths are protocol identifiers.
	# The menu is on both controllers' buttons at the front of the face (right: menu, left: view), so one controller is
	# enough for the panel; the overlay moves to the left stick click.
	var frame_single: Array = [
		["menu", RIGHT + "/input/menu/click"],
		["menu", LEFT + "/input/view/click"],
		# Fallback in case the runtime keeps menu for itself; on an image in the browser it keeps the picture.
		["stick_click", RIGHT + "/input/thumbstick/click"],
		["overlay", LEFT + "/input/thumbstick/click"],
		["next_file", RIGHT + "/input/a/click"],
		["prev_file", RIGHT + "/input/b/click"],
		["agent", RIGHT + "/input/y/click"],
	]
	if dpad:
		# The engine registers the d-pad on the left controller only (modules/openxr, the controller extension).
		frame_single.append_array([
			["chapter_prev", LEFT + "/input/dpad_left/click"],
			["chapter_next", LEFT + "/input/dpad_right/click"],
			["replay", LEFT + "/input/dpad_down/click"],
		])
	_add_profile(action_map, actions, "/interaction_profiles/valve/frame_controller_valve", _merge(both_hands, {
		"labels": "input/bumper/click",
	}), frame_single)

	# Generic controller profile (core in XR 1.1). The headset's runtime bound this one in an early run with the
	# engine's default action map. It has no menu button: per hand only primary, secondary and thumbstick clicks.
	# Right primary / secondary = next / previous (A / B on a gamepad-style layout); the menu is on the left primary
	# and the right thumbstick click, the overlay on the left secondary and the left thumbstick click, so whatever the
	# runtime maps to them, the menu can be reached.
	_add_profile(action_map, actions, "/interaction_profiles/khr/generic_controller", both_hands, [
		["next_file", RIGHT + "/input/primary/click"],
		["prev_file", RIGHT + "/input/secondary/click"],
		["menu", LEFT + "/input/primary/click"],
		["menu", RIGHT + "/input/thumbstick/click"],
		["overlay", LEFT + "/input/secondary/click"],
		["overlay", LEFT + "/input/thumbstick/click"],
	])

	# Third-party controller with A/B: system is reserved, so both thumbstick clicks are the menu (one controller is
	# enough); the overlay is in the System tab and on the keyboard.
	_add_profile(action_map, actions, "/interaction_profiles/valve/index_controller", _merge(both_hands, {
		"next_file": "input/a/click",
		"prev_file": "input/b/click",
		"menu": "input/thumbstick/click",
	}), [])

	# Third-party controller with A/B/X/Y (also what many runtimes emulate): A/X next, B/Y previous. The menu is the
	# left menu button and the right stick click (the right has no menu button), the overlay the left stick click.
	_add_profile(action_map, actions, "/interaction_profiles/oculus/touch_controller", both_hands, [
		["menu", LEFT + "/input/menu/click"],
		["menu", RIGHT + "/input/thumbstick/click"],
		["overlay", LEFT + "/input/thumbstick/click"],
		["next_file", RIGHT + "/input/a/click"],
		["next_file", LEFT + "/input/x/click"],
		["prev_file", RIGHT + "/input/b/click"],
		["prev_file", LEFT + "/input/y/click"],
	])

	# Simple controller profile: select and menu only.
	_add_profile(action_map, actions, "/interaction_profiles/khr/simple_controller", {
		"aim_pose": "input/aim/pose",
		"grip_pose": "input/grip/pose",
		"haptic": "output/haptic",
		"trigger": "input/select/click",
		"menu": "input/menu/click",
	}, [])

	return action_map


func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate()
	out.merge(b, true)
	return out


## per_hand: action -> path below /user/hand/{left,right}/ (bound on both hands).
## single: [action, full path] pairs for one-hand inputs.
func _add_profile(action_map: OpenXRActionMap, actions: Dictionary, profile_path: String, per_hand: Dictionary,
		single: Array) -> void:
	var profile := OpenXRInteractionProfile.new()
	profile.interaction_profile_path = profile_path
	var bindings: Array = []
	for action_name: String in per_hand:
		for hand: String in [LEFT, RIGHT]:
			bindings.append(_binding(actions[action_name], hand + "/" + per_hand[action_name]))
	for pair: Array in single:
		bindings.append(_binding(actions[pair[0]], pair[1]))
	profile.set_bindings(bindings)
	action_map.add_interaction_profile(profile)


func _binding(action: OpenXRAction, path: String) -> OpenXRIPBinding:
	var binding := OpenXRIPBinding.new()
	binding.action = action
	binding.binding_path = path
	return binding
