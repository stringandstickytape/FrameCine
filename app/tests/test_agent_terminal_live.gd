extends SceneTree

## An agent's terminal for real: a real terminal on a real X display, a shell script standing in for the agent, the real
## X11WindowSource (two of them together, the pane's and the big screen's), real keys. Needs a renderer, a display and
## a terminal: AGENT_TERMINAL=<command> (a wrapper or a path to xterm); skipped without them. ROOM_SNAPSHOT_OUT=<folder>
## saves the pictures: the pane at headset density, the same terminal on the big screen.
## A restart of the player is two runs on one display: AGENT_TERMINAL_RESTART=leave ends with the terminal open, then
## AGENT_TERMINAL_RESTART=find, a new process that can't start a terminal, must find that one and carry on in it.
##
## AGENT_TERMINAL=/path/to/xterm godot --display-driver x11 --rendering-driver vulkan --xr-mode off --path app \
##     --script res://tests/test_agent_terminal_live.gd

const AgentTerminal := preload("res://scripts/agents/agent_terminal.gd")
const RoomSnapshot := preload("res://scripts/assistant/room_snapshot.gd")
const VideoScreen := preload("res://scripts/video_screen.gd")
const WindowVideoSource := preload("res://scripts/video/window_video_source.gd")

const STAND_IN := """#!/bin/sh
# Stands in for the agent: a prompt, and every line it reads goes to log.txt.
printf '\\033[38;5;208m * Claude Code\\033[0m  stand-in, 66 columns on the controller\\n\\n'
n=0
while [ $n -lt 40 ]; do n=$((n+1)); echo "  earlier output, line $n"; done
printf '\\n\\033[1m> \\033[0m'
while read -r line; do
	printf '%s\\n' "$line" >>log.txt
	printf '\\033[38;5;245m  You said:\\033[0m %s\\n\\n\\033[1m> \\033[0m' "$line"
done
"""

var _failures := 0
var _checks := 0
var main: Node3D
var agents: Node
var home := ""


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _run() -> void:
	await _frames(5)
	var terminal := OS.get_environment("AGENT_TERMINAL")
	if terminal == "" or not ClassDB.class_exists("X11WindowSource") or DisplayServer.get_name() == "headless":
		print("test_agent_terminal_live: skipped (needs AGENT_TERMINAL, a display and X11WindowSource)")
		quit(0)
		return
	home = OS.get_user_data_dir().path_join("test_agents_live")
	var restart := OS.get_environment("AGENT_TERMINAL_RESTART")
	if restart == "find":
		await _find_again(terminal)
		return
	_clear(home)
	DirAccess.make_dir_recursive_absolute(home.path_join(".local/bin"))
	AgentTerminal.home_override = home
	AgentTerminal.terminal_override.assign([terminal])
	var f := FileAccess.open(home.path_join(".local/bin/claude"), FileAccess.WRITE)
	f.store_string(STAND_IN)
	f.close()
	FileAccess.set_unix_permissions(home.path_join(".local/bin/claude"), 0x1ED)
	agents = main.local_agents
	agents.pair_on_start = false
	main.open_path("stub://flat_sbs")
	main.ui.hide_panel()
	await _seconds(0.5)

	agents.open_agent("claude", true)
	await _until(func() -> bool: return agents.is_running("claude"), 15.0)
	_check("the terminal came up, found by its class", agents.is_running("claude"))
	# As a real agent's first hook would: the stand-in reads lines, so an Escape ahead of the words would be in them,
	# and it has no question about the folder to answer, so the first run's prompt mark is cleared here.
	FileAccess.open(AgentTerminal.player_dir("claude").path_join("hook_seen"), FileAccess.WRITE).close()
	agents._answered()
	await _seconds(1.5)
	agents._poll = 0.0
	await _frames(2)
	var x: Object = agents.x
	var size: Vector2i = x.call("get_size")
	print("test_agent_terminal_live: the window is %d x %d" % [size.x, size.y])
	# The 1920 x 1080 the headset's window manager forces on every top-level window (AgentTerminal.COLUMNS, LINES, FONT_PX).
	_check("about the display's size (%d x %d)" % [size.x, size.y], absi(size.x - 1920) < 80 and absi(size.y - 1080) < 120)
	_check("the capture has a picture", agents.pane_shown() and x.call("get_texture") != null)
	var log_file := home.path_join("Claude/log.txt")
	agents.deliver("make the sky darker, please: 100% (ok?)")
	await _until(func() -> bool: return FileAccess.file_exists(log_file), 5.0)
	var said := FileAccess.get_file_as_string(log_file)
	_check("spoken words reach it, then Enter (%s)" % said.strip_edges(), said.strip_edges()
			== "make the sky darker, please: 100% (ok?)")
	await _seconds(0.5)
	await _pane_shot("agent-pane-headset-density.png", true)
	await _pane_shot("agent-pane-not-in-snapshots.png", false)
	# Shift + Page Up, the scrollback: picture to look at, and it must leave the session alone.
	var hand: Node = main.right_hand
	main.ui.pointer_hand = hand
	hand.set("grip_down", true)
	agents.on_stick(hand, Vector2(0, 1), 0.016)
	agents.on_stick(hand, Vector2.ZERO, 0.016)
	hand.set("grip_down", false)
	await _seconds(0.5)
	await _pane_shot("agent-pane-scrolled-back.png", true)
	agents.deliver("still here")
	await _seconds(0.8)
	_check("still the same session after scrolling (%s)" % FileAccess.get_file_as_string(log_file).strip_edges(),
			FileAccess.get_file_as_string(log_file).ends_with("still here\n"))
	# The same terminal on the big screen, a second capture alongside.
	agents.show_on_screen("claude")
	await _until(func() -> bool: return agents.on_big_screen(), 5.0)
	_check("on the big screen too", agents.on_big_screen())
	await _seconds(1.0)
	var snap: RoomSnapshot = RoomSnapshot.new()
	root.add_child(snap)
	(snap.get("_camera") as Camera3D).set_cull_mask_value(VideoScreen.PRIVATE_LAYER, true)
	await _frames(2)
	var s: Dictionary = await snap.capture("viewer", Vector2i(1280, 720), 60.0)
	_save(s, "agent-terminal-big-screen.png")
	snap.queue_free()
	agents.deliver("typed on the big screen")
	await _seconds(0.8)
	_check("keys go through the big screen's source", FileAccess.get_file_as_string(log_file).contains(
			"typed on the big screen"))
	# A film again: the source goes, the terminal stays.
	main.open_path("stub://flat_sbs")
	await _seconds(1.0)
	agents._refresh_running()
	_check("another source opened: the terminal stays", agents.is_running("claude"))
	# Both captures at once, on one window: the pane's and a window source's.
	agents.open_agent("claude")
	await _seconds(0.5)
	var second: Object = ClassDB.instantiate("X11WindowSource")
	var ok: bool = second.call("open") == OK and second.call("capture", AgentTerminal.find_window(agents.x, "claude")) == OK
	await _seconds(0.5)
	_check("two captures of one window together", ok and agents.pane_shown())
	second.call("stop_capture")
	second.call("close")
	await _seconds(0.3)
	agents.deliver("after the second capture went")
	await _seconds(0.8)
	_check("letting go of one leaves the other working", FileAccess.get_file_as_string(log_file).contains(
			"after the second capture went"))
	if restart == "leave":
		agents.hide_pane()
		_finish()
		return
	await _close_terminal()
	_clear(home)
	_finish()


## The second run of a restart: this process started no terminal and can't, so a session here is the one left running.
func _find_again(terminal: String) -> void:
	AgentTerminal.home_override = home
	AgentTerminal.terminal_override.assign([terminal + ".not-there"])
	agents = main.local_agents
	agents.pair_on_start = false
	main.ui.hide_panel()
	await _until(func() -> bool: return agents.is_running("claude"), 5.0)
	_check("after a restart: the terminal is found by its class", agents.is_running("claude"))
	agents.open_agent("claude", true)
	await _seconds(0.5)
	_check("after a restart: on the pane", agents.pane_shown())
	agents.deliver("after the restart")
	await _seconds(0.8)
	_check("after a restart: the same session reads the words", FileAccess.get_file_as_string(home.path_join(
			"Claude/log.txt")).contains("after the restart"))
	await _close_terminal()
	_clear(home)
	_finish()


## The test closes the terminal by hand: the player never does.
func _close_terminal() -> void:
	var x: Object = agents.x
	x.call("close_window", AgentTerminal.find_window(x, "claude"))
	await _seconds(1.0)
	agents.hide_pane()
	await _frames(3)


func _finish() -> void:
	AgentTerminal.home_override = ""
	AgentTerminal.terminal_override.clear()
	print("test_agent_terminal_live: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(1 if _failures > 0 else 0)


## The pane about 45 cm from the eye at the Frame's density (about 25 pixels a degree), a film on the big screen behind.
func _pane_shot(file: String, see_it: bool) -> void:
	var pane: Node3D = agents.get_node("AgentPane")
	var cam: Node3D = main.camera
	pane.global_transform = Transform3D(cam.global_basis.rotated(cam.global_basis.x, deg_to_rad(-12.0)),
			cam.global_position - cam.global_basis.z * 0.45 - cam.global_basis.y * 0.03)
	var snap: RoomSnapshot = RoomSnapshot.new()
	root.add_child(snap)
	await _frames(1)
	if see_it:
		(snap.get("_camera") as Camera3D).set_cull_mask_value(VideoScreen.PRIVATE_LAYER, true)
	var s: Dictionary = await snap.capture("viewer", Vector2i(1000, 1000), 40.0)
	_save(s, file)
	snap.queue_free()


func _save(s: Dictionary, file: String) -> void:
	var out_dir := OS.get_environment("ROOM_SNAPSHOT_OUT")
	if out_dir != "" and s.has("png"):
		var fa := FileAccess.open(out_dir.path_join(file), FileAccess.WRITE)
		fa.store_buffer(s["png"])
		fa.close()


func _clear(p: String) -> void:
	var d := DirAccess.open(p)
	if d == null:
		return
	d.include_hidden = true
	for sub in d.get_directories():
		_clear(p.path_join(sub))
	for f in d.get_files():
		DirAccess.remove_absolute(p.path_join(f))
	DirAccess.remove_absolute(p)


func _until(f: Callable, seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end and not bool(f.call()):
		await process_frame


func _seconds(s: float) -> void:
	var end := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL " + what)
