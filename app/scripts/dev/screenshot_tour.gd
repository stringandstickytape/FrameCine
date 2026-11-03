extends Node

## Screenshot tour (--shots=DIR): opens each test pattern in its mode, and a few environment / menu views, and saves
## both eyes side by side as small PNGs (desktop, flat camera, eyes forced through the shaders' force_eye). Then quits.
## --shots-only=PREFIX takes only the shots whose names start with it (env_: the rooms).

const VideoMode := preload("res://scripts/video_mode.gd")
const PaneUI := preload("res://ui/pane_ui.gd")

## name, path, env, look (yaw, pitch degrees), fov, extra ("ui_files", "ui_picture", "ui_room", "ui_system",
## "ui_sound", "ui_subtitles", "ui_keyboard", "watch_card", "controllers_input", "debug"). The panel shots open it
## straight ahead and frame it (38 cm wide at 0.6 m, about 35°); "ui_room@0.5" scrolls the tab half way down,
## "@1" to its end, so the long tabs' lower controls are in the tour too. controllers_input holds the trigger, grip, stick, A and view
## on our controller model.
const SHOTS: Array = [
	["flat_mono", "stub://flat_mono", "void", Vector2(0, 0), 60.0, ""],
	["flat_sbs_full", "stub://flat_sbs", "void", Vector2(0, 0), 60.0, ""],
	["flat_sbs_half", "stub://flat_sbs_half", "void", Vector2(0, 0), 60.0, ""],
	["flat_tb_full", "stub://flat_tb", "void", Vector2(0, 0), 60.0, ""],
	["flat_tb_half", "stub://flat_tb_half", "void", Vector2(0, 0), 60.0, ""],
	["180_mono", "stub://180_mono", "void", Vector2(0, 0), 100.0, ""],
	["180_sbs", "stub://180_sbs", "void", Vector2(0, 0), 100.0, ""],
	["180_sbs_look_right", "stub://180_sbs", "void", Vector2(70, 10), 100.0, ""],
	["360_mono", "stub://360_mono", "void", Vector2(0, 0), 100.0, ""],
	["360_mono_look_back", "stub://360_mono", "void", Vector2(180, 0), 100.0, ""],
	["360_tb", "stub://360_tb", "void", Vector2(0, 0), 100.0, ""],
	["360_tb_look_up", "stub://360_tb", "void", Vector2(0, 75), 100.0, ""],
	["fisheye_sbs", "stub://fisheye_sbs", "void", Vector2(0, 0), 110.0, ""],
	["fisheye_sbs_fov200", "stub://fisheye_sbs_fov200", "void", Vector2(0, 0), 110.0, ""],
	["wrong_mode_sbs_as_mono", "stub://flat_sbs", "void", Vector2(0, 0), 60.0, "as_mono"],
	["env_dim_room", "stub://flat_sbs", "dim_room", Vector2(0, -5), 75.0, ""],
	["env_cinema", "stub://flat_mono", "cinema", Vector2(0, 5), 75.0, ""],
	["env_cinema_side", "stub://flat_mono", "cinema", Vector2(-50, -10), 75.0, ""],
	["env_cinema_seats", "stub://flat_mono", "cinema", Vector2(-35, -20), 75.0, ""],
	["env_home_theatre", "stub://flat_mono", "home_theatre", Vector2(0, -15), 75.0, ""],
	["env_home_theatre_side", "stub://flat_mono", "home_theatre", Vector2(-70, -20), 75.0, ""],
	["env_planetarium", "stub://flat_mono", "planetarium", Vector2(-30, -25), 75.0, ""],
	["env_dome", "stub://flat_mono", "dome", Vector2(20, -25), 75.0, ""],
	["ui_files", "stub://flat_mono", "dim_room", Vector2(0, 0), 44.0, "ui_files"],
	["ui_picture", "stub://flat_sbs", "void", Vector2(0, 0), 44.0, "ui_picture"],
	["ui_room", "stub://flat_mono", "cinema", Vector2(0, 0), 44.0, "ui_room"],
	["ui_system", "stub://flat_mono", "void", Vector2(0, 0), 44.0, "ui_system"],
	["ui_sound", "stub://flat_mono", "void", Vector2(0, 0), 44.0, "ui_sound"],
	["ui_keyboard", "stub://flat_mono", "void", Vector2(0, 0), 44.0, "ui_keyboard"],
	["ui_subtitles", "stub://flat_mono", "void", Vector2(0, 0), 44.0, "ui_subtitles"],
	["ui_picture_middle", "stub://flat_sbs", "void", Vector2(0, 0), 44.0, "ui_picture@0.4"],
	["ui_picture_end", "stub://flat_sbs", "void", Vector2(0, 0), 44.0, "ui_picture@1"],
	["ui_sound_end", "stub://flat_mono", "void", Vector2(0, 0), 44.0, "ui_sound@1"],
	["ui_room_middle", "stub://flat_mono", "cinema", Vector2(0, 0), 44.0, "ui_room@0.45"],
	["ui_room_end", "stub://flat_mono", "cinema", Vector2(0, 0), 44.0, "ui_room@1"],
	["ui_system_middle", "stub://flat_mono", "void", Vector2(0, 0), 44.0, "ui_system@0.5"],
	["watch_card", "stub://flat_mono", "dim_room", Vector2(12, 0), 70.0, "watch_card"],
	["controllers_input", "stub://flat_mono", "void", Vector2(27, -33), 20.0, "controllers_input"],
	# Last: controllers posed by hand (no tracking on a desktop): without the menu, then with it
	# (right hand laser on the menu).
	["controllers_labels", "stub://flat_mono", "dim_room", Vector2(0, -32), 62.0, "controllers_labels"],
	["controllers_menu", "stub://flat_mono", "dim_room", Vector2(0, -12), 70.0, "controllers"],
	# A stand-in for the runtime render model (node origins at the model origin, meshes carry the positions, tilted
	# 15 degrees), to check the model path of the label placement.
	["controllers_close", "stub://flat_mono", "void", Vector2(27, -33), 20.0, "controllers_labels"],
	["controllers_model", "stub://flat_mono", "dim_room", Vector2(0, -32), 62.0, "controllers_model"],
	["controllers_model_close", "stub://flat_mono", "void", Vector2(27, -33), 20.0, "controllers_model"],
]

var main: Node
var out_dir := ""


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	await _frames(10)
	main.set_overlay(true)
	var saved := 0
	var skipped := 0
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots-only="):
			only = a.trim_prefix("--shots-only=")
	for shot: Array in SHOTS:
		var shot_name: String = shot[0]
		if not shot_name.begins_with(only):
			skipped += 1
			continue
		if not str(shot[1]).begins_with("stub://") and not FileAccess.file_exists(shot[1]):
			print("Shot %s skipped: %s not found" % [shot_name, shot[1]])
			skipped += 1
			continue
		main.ui.hide_panel()
		main.ui.card.dismiss("cleared")
		main.ui.ui.files._hide_form(false)
		for hand: Node3D in main.hands:
			hand.visual.pose_inputs({})
		main.set_environment(shot[2])
		main.open_path(shot[1])
		main.flat_camera.fov = shot[4]
		main._look = shot[3]
		main._apply_look()
		match shot[5]:
			"as_mono":
				var m := VideoMode.from_id("flat_mono")
				main.set_video_mode(m, false)
			"controllers_model":
				await _pose_controllers(false)
				await _attach_fake_models()
			"controllers", "controllers_labels":
				await _pose_controllers(shot[5] == "controllers")
			"watch_card":
				main.ui.card.show_card({"title": "Who is that", "text": "The actor from the opening scene, here 20 years "
						+ "later.", "seconds": 0.0})
			"controllers_input":
				await _pose_controllers(false)
				for hand: Node3D in main.hands:
					hand.visual.pose_inputs({"trigger": 1.0, "squeeze": 1.0, "thumbstick": Vector2(0.8, 0.6),
							"pressed": {"a": true, "view": true}})
			_ when str(shot[5]).begins_with("ui_"):
				var ui_shot := str(shot[5]).get_slice("@", 0)
				var scroll := float(str(shot[5]).get_slice("@", 1)) if str(shot[5]).contains("@") else 0.0
				main._look = Vector2.ZERO
				main._apply_look()
				main.ui.show_panel()
				main._look = shot[3]
				main._apply_look()
				var tab: int = {"ui_files": PaneUI.Tab.FILES, "ui_picture": PaneUI.Tab.PICTURE,
						"ui_room": PaneUI.Tab.ROOM, "ui_system": PaneUI.Tab.SYSTEM, "ui_sound": PaneUI.Tab.SOUND,
						"ui_subtitles": PaneUI.Tab.SUBTITLES, "ui_keyboard": PaneUI.Tab.FILES}.get(ui_shot,
						PaneUI.Tab.FILES)
				main.ui.ui.show_tab(tab)
				var tab_scroll := main.ui.ui.tabs[tab] as ScrollContainer
				if tab_scroll != null:
					await _frames(3)
					var bar := tab_scroll.get_v_scroll_bar()
					tab_scroll.scroll_vertical = roundi(scroll * maxf(bar.max_value - bar.page, 0.0))
				if ui_shot == "ui_files":
					main.ui.ui.files.open_folder("stub://")
				if ui_shot == "ui_keyboard":
					main.ui.ui.files.open_folder("network://")
					main.ui.ui.files._show_form(-1, {"host": "nas.local"})
		# Close-ups show the label anchors (--labels-debug spheres).
		for hand: Node3D in main.hands:
			hand.visual.set_debug_anchors(shot_name.ends_with("_close"))
		# Let the pattern play a little (timecode, markers) and the overlay refresh.
		await _frames(45)
		# With --snapshot-dir: the in-headset snapshot set for the stand-in model (checks scripts/dev/snapshots.gd).
		if main.snapshots != null and shot_name == "controllers_model":
			await main.snapshots.take()
		var img: Image = await main.capture_eyes(640)
		var path := out_dir.path_join(shot_name + ".png")
		var err := img.save_png(path)
		print("Shot %s: %s" % [path, error_string(err)])
		if err == OK:
			saved += 1
	print("Screenshot tour: %d of %d saved to %s" % [saved, SHOTS.size(), out_dir])
	main.get_tree().quit(0 if saved + skipped == SHOTS.size() else 1)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Shows both controllers where hands would hold them, as XR would draw them. With the
## menu: the right one points at it (laser), the labels say what the inputs do on the menu.
func _pose_controllers(with_menu: bool) -> void:
	if with_menu:
		main.ui.show_panel()
	await _frames(2)
	var target: Vector3 = main.ui.panel.global_position + Vector3(0.1, 0.05, 0) if with_menu else Vector3(0.3, 1.1, -3.0)
	for hand: Node3D in main.hands:
		var right: bool = hand == main.right_hand
		hand.show_when_tracked = false
		hand.visible = true
		var pos := Vector3(0.18 if right else -0.2, 0.95, -0.35)
		var aim := target if right else pos + Vector3(0.05, 0.1, -1.0)
		hand.global_transform = Transform3D(Basis(), pos).looking_at(aim, Vector3.UP)
		if right and with_menu:
			var hit: Dictionary = main.ui.panel.ray_hit(hand.global_position, -hand.global_basis.z)
			hand.set_laser(true, float(hit.get("distance", 3.0)), not hit.is_empty())
		else:
			hand.set_laser(false)


## Gives each hand a stand-in for the runtime's render model, built like the headset's: a root, "body" and one node per
## control named as on the device, every node at the model origin with its mesh carrying the position. The model is
## tilted 15 degrees and shifted, so the label placement must find the face plane and front direction from the nodes.
## It starts far from the hand for a few frames, as the runtime's model did on the device.
func _attach_fake_models() -> void:
	const Visual := preload("res://scripts/xr/controller_visual.gd")
	for hand: Node3D in main.hands:
		var visual: Node3D = hand.visual
		var old := hand.get_node_or_null("FakeModel")
		if old != null:
			visual.attach_render_model(old)
			continue
		var s := -1.0 if hand == main.left_hand else 1.0
		var root := Node3D.new()
		root.name = "FakeModel"
		# As on the device's first tracked frame: the model starts far from the hand (its parent not yet compensating
		# the aim pose) and moves to its place a few frames later. Labels must end up on it.
		root.transform = Transform3D(Basis(), Vector3(0.2, -0.65, 0.4))
		hand.add_child(root)
		var mat := StandardMaterial3D.new()
		# Dark plastic and a lit material, like the runtime's glTF (the visual makes it unlit).
		mat.albedo_color = Color(0.09, 0.09, 0.1)
		var parts := {"body": [Vector3(0, -0.013, 0), Vector3(0.065, 0.026, 0.06)]}
		var names := {"thumbstick": "thumbstick", "trigger": "trigger", "bumper": "bumper", "squeeze": "button_grip",
				"system": "button_system"}
		if hand == main.right_hand:
			names.merge({"a": "button_a", "b": "button_b", "x": "button_x", "y": "button_y", "menu": "button_menu"})
		else:
			names.merge({"dpad": "dpad", "view": "button_view"})
		for input: String in names:
			var size := Vector3(0.008, 0.004, 0.008)
			if input in ["thumbstick", "dpad"]:
				size = Vector3(0.018, 0.012, 0.018) if input == "thumbstick" else Vector3(0.022, 0.003, 0.022)
			elif input in ["trigger", "bumper", "squeeze"]:
				size = Vector3(0.02, 0.014, 0.012) if input != "squeeze" else Vector3(0.006, 0.02, 0.012)
			parts[names[input]] = [Visual.ANCHORS[input] * Vector3(s, 1, 1), size]
		for node_name: String in parts:
			var node := Node3D.new()
			node.name = node_name
			root.add_child(node)
			var mi := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = parts[node_name][1]
			mi.mesh = box
			mi.material_override = mat
			mi.position = parts[node_name][0]
			node.add_child(mi)
		# The authored layout fits the real model, not this stand-in: the computed placement is what is tested here.
		visual.use_layout = false
		visual.attach_render_model(root)
	await _frames(3)
	for hand: Node3D in main.hands:
		var root: Node3D = hand.get_node_or_null("FakeModel")
		if root != null:
			root.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(15.0)), Vector3(0.0, -0.01, 0.02))
	await _frames(3)
