extends Node

## Scripted tours and kiosk mode (idea #91; docs/tours.md): a JSON file with a room (a recipe or a built-in
## environment), a playlist, and screen and camera moves, run unattended. Started with --tour=FILE (FILE: a path, or a
## name in user://tours/), or with the `tour` command. --kiosk (or "kiosk": true in the file) loops it for ever, keeps
## the pane out of the way and skips what fails.
##
##   {"name": "Lobby", "recipe": "lobby", "loop": true, "kiosk": true, "volume": 0.6,
##    "steps": [
##      {"screen": {"width": 4, "distance": 5, "yaw": 0}, "over": 0},
##      {"open": "films/a.mkv", "mode": "flat_sbs_half", "start": 30, "for": 60},
##      {"screen": {"yaw": 25, "distance": 4}, "over": 6, "async": true},
##      {"camera": {"yaw": 20, "pitch": -5}, "over": 4},
##      {"playlist": ["b.mp4", "c.mp4"], "each": 20},
##      {"environment": "cinema"}, {"light": 0.5}, {"wait": 3}, {"pause": true}, {"play": true}, {"seek": 10},
##      {"command": "set", "args": {"setting": "overlay", "value": true}}]}
##
## Paths in the file are relative to the file's folder; ~/ is the home folder. A step waits for what it does (the
## file's `for` seconds or its end, the move's `over` seconds) unless "async": true, which runs it alongside the next
## steps. Camera steps move the flat camera (no XR); in XR the head is the camera and they are skipped. While a tour
## runs the settings are not written (its screen moves and files are not remembered).

const DevCommands := preload("res://scripts/dev/dev_commands.gd")
const CommandHost := preload("res://scripts/dev/command_host.gd")
const VideoMode := preload("res://scripts/video_mode.gd")

const NODE_NAME := "Tour"
const DIR := "user://tours"
## Longest wait for a file to open (a share can take a while).
const OPEN_TIMEOUT := 30.0
## Longest a file plays without a `for` (an endless stream).
const MAX_PLAY := 4.0 * 3600.0
## Command steps may read, control and change; never run code.
const ALLOWED_LEVELS: Array[String] = ["read", "control", "change"]

## The tour file's contents.
var tour := {}
var file := ""
var kiosk := false
var loop := false
var rounds := 0
var step_index := -1
var _stop := false
var _errors: Array[String] = []

## The main scene (scripts/main.gd), looked up each time (it survives `reload app`).
var main: Node:
	get:
		var tree := Engine.get_main_loop() as SceneTree
		return tree.current_scene if tree != null else null


## main.gd calls this at the end of _ready(): starts the tour given by --tour, if any.
static func attach(m: Node, args: Dictionary) -> Node:
	if not args.has("tour"):
		return null
	var r := start(m, str(args["tour"]), args.has("kiosk"))
	if r.has("error"):
		push_error("--tour: %s" % r["error"])
		return null
	return r["node"]


## Loads a tour file and starts it (stopping one that runs). {node} or {error}.
static func start(m: Node, path: String, force_kiosk := false) -> Dictionary:
	var resolved := resolve(path)
	if resolved == "":
		return {"error": "no tour file %s (a path, or a name in %s)" % [path, ProjectSettings.globalize_path(DIR)]}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(resolved))
	if not parsed is Dictionary or not (parsed as Dictionary).get("steps") is Array:
		return {"error": "%s: not a tour (a JSON object with a \"steps\" list)" % resolved}
	stop()
	var t: Node = (load("res://scripts/dev/tour.gd") as GDScript).new()
	t.name = NODE_NAME
	t.tour = parsed
	t.file = resolved
	t.kiosk = force_kiosk or bool(parsed.get("kiosk", false))
	t.loop = bool(parsed.get("loop", t.kiosk))
	m.get_tree().root.add_child.call_deferred(t)
	return {"node": t}


## The tour running, or null.
static func running() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	var t: Node = tree.root.get_node_or_null(NODE_NAME) if tree != null else null
	return t if t != null and not t.is_queued_for_deletion() else null


static func stop() -> void:
	var t := running()
	if t != null:
		t._stop = true
		t.name = NODE_NAME + "_stopping"
		t.queue_free()


## A path, ~/path, or a name in user://tours (with or without .json). "" when there is no such file.
static func resolve(path: String) -> String:
	var p := path
	if p.begins_with("~/"):
		p = OS.get_environment("HOME").path_join(p.trim_prefix("~/"))
	if FileAccess.file_exists(p):
		return p
	for candidate in [DIR.path_join(p), DIR.path_join(p + ".json")]:
		if FileAccess.file_exists(candidate):
			return candidate
	return ""


## The shared commands (command_host.gd): `tour` starts or stops one; `tour_status` says where it is.
static func register_commands() -> void:
	DevCommands.register("tour", func(args: Dictionary, ctx: DevCommands.Call) -> Variant:
		if args["stop"]:
			var had := running() != null
			stop()
			return {"stopped": had}
		var r := start(Engine.get_main_loop().current_scene, args["file"], args["kiosk"])
		if r.has("error"):
			return ctx.fail(r["error"])
		ctx.summary = "tour %s" % args["file"]
		return {"started": r["node"].file, "kiosk": r["node"].kiosk, "loop": r["node"].loop}, {
		"description": "Runs a tour file (a room, a playlist and screen / camera moves; docs/tours.md), or stops it.",
		"params": [{"name": "file", "type": "string", "default": "", "description": "a path or a name in user://tours"},
				{"name": "kiosk", "type": "bool", "default": false},
				{"name": "stop", "type": "bool", "default": false}],
		"level": "control", "returns": "{started, kiosk, loop} or {stopped}"})
	DevCommands.register("tour_status", func(_args: Dictionary, _ctx: DevCommands.Call) -> Variant:
		var t := running()
		return t.status() if t != null else {"running": false}, {
		"description": "The tour running: file, step, round, errors.", "returns": "{running, file, step, ...}"})


func status() -> Dictionary:
	var steps: Array = tour.get("steps", [])
	return {"running": true, "file": file, "name": str(tour.get("name", file.get_file())), "kiosk": kiosk,
			"loop": loop, "round": rounds, "step": step_index, "steps": steps.size(),
			"current": steps[step_index] if step_index >= 0 and step_index < steps.size() else {},
			"errors": _errors.slice(-10)}


func _ready() -> void:
	_run.call_deferred()


func _exit_tree() -> void:
	_stop = true
	var m := main
	if m != null and is_instance_valid(m) and has_meta("settings_read_only"):
		m.settings.read_only = get_meta("settings_read_only")


func _run() -> void:
	var m := main
	if m == null:
		return
	# The tour's moves and files are not remembered.
	set_meta("settings_read_only", m.settings.read_only)
	m.settings.read_only = true
	print("Tour: %s (%d steps%s%s)" % [file, (tour["steps"] as Array).size(), ", kiosk" if kiosk else "",
			", loops" if loop else ""])
	if kiosk:
		m.set_overlay(false)
	await _apply_header()
	while not _stop:
		rounds += 1
		var round_start := Time.get_ticks_msec()
		var steps: Array = tour["steps"]
		for i in steps.size():
			if _stop:
				return
			step_index = i
			var step: Variant = steps[i]
			if not step is Dictionary:
				_error("step %d is not an object" % (i + 1))
				continue
			_hide_pane()
			if bool(step.get("async", false)):
				_do(step, i)
			else:
				await _do(step, i)
		if not loop or _stop:
			break
		# A round that took no time (every file missing): don't spin.
		if Time.get_ticks_msec() - round_start < 2000:
			_error("round %d took under 2 s; waiting 10 s" % rounds)
			await _sleep(10.0)
		if kiosk:
			main.set_overlay(false)
		await _apply_header()
	if not _stop:
		print("Tour: done (%d round%s, %d errors)" % [rounds, "" if rounds == 1 else "s", _errors.size()])
		if bool(tour.get("quit", false)):
			get_tree().quit()
		queue_free()


## The file's top-level room, light and volume, at the start of each round.
func _apply_header() -> void:
	for key in ["recipe", "environment", "light", "volume", "screen"]:
		if tour.has(key):
			await _do({key: tour[key]}, -1)


func _error(text: String) -> void:
	_errors.append(text)
	push_warning("Tour: %s" % text)


func _hide_pane() -> void:
	var m := main
	if m != null and m.ui != null and m.ui.has_method("hide_panel"):
		m.ui.hide_panel()


## Runs one step. Errors are logged and the tour goes on.
func _do(step: Dictionary, index: int) -> void:
	var m := main
	if m == null or _stop:
		return
	var label := "step %d" % (index + 1) if index >= 0 else "header"
	if step.has("open"):
		await _open(step, label)
	elif step.has("playlist"):
		var each := float(step.get("each", -1.0))
		for item: Variant in step["playlist"]:
			if _stop:
				return
			var entry: Dictionary = item if item is Dictionary else {"open": item}
			if each > 0.0 and not entry.has("for"):
				entry["for"] = each
			for k in ["mode", "start"]:
				if step.has(k) and not entry.has(k):
					entry[k] = step[k]
			_hide_pane()
			await _open(entry, label)
	elif step.has("recipe"):
		_set_environment("recipe:" + str(step["recipe"]), label)
	elif step.has("environment"):
		_set_environment(str(step["environment"]), label)
	elif step.has("light"):
		m.set_room_light(float(step["light"]))
	elif step.has("volume"):
		m.set_volume(float(step["volume"]))
	elif step.has("overlay"):
		m.set_overlay(bool(step["overlay"]))
	elif step.has("screen"):
		await _move_screen(step["screen"], float(step.get("over", 0.0)))
	elif step.has("camera"):
		await _move_camera(step["camera"], float(step.get("over", 0.0)), label)
	elif step.has("wait"):
		await _sleep(float(step["wait"]))
	elif step.has("play"):
		m.player.play()
	elif step.has("pause"):
		m.player.pause()
	elif step.has("seek"):
		m.player.seek(float(step["seek"]))
	elif step.has("mode"):
		m.set_video_mode(VideoMode.from_id(str(step["mode"])), false)
	elif step.has("command"):
		await _command(str(step["command"]), step.get("args", {}), label)
	elif step.has("print"):
		print("Tour: %s" % step["print"])
	else:
		_error("%s: nothing to do in %s" % [label, JSON.stringify(step)])


func _sleep(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not _stop and Time.get_ticks_msec() < end:
		await get_tree().process_frame


func _path(p: String) -> String:
	if p.begins_with("~/"):
		return OS.get_environment("HOME").path_join(p.trim_prefix("~/"))
	if p.contains("://") or p.is_absolute_path():
		return p
	return file.get_base_dir().path_join(p)


func _open(step: Dictionary, label: String) -> void:
	var m := main
	var path := _path(str(step["open"]))
	var opened := [false]
	var on_opened := func(_p: String) -> void: opened[0] = true
	m.file_opened.connect(on_opened)
	var only: Array[String] = [path]
	m.open_path(path, true, only)
	var deadline := Time.get_ticks_msec() + int(OPEN_TIMEOUT * 1000.0)
	while not opened[0] and not _stop and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if m.file_opened.is_connected(on_opened):
		m.file_opened.disconnect(on_opened)
	if _stop:
		return
	var src: Object = m.player.source
	if not opened[0] or src == null or (src.last_error != "" and src.get_kind() == "stub" and
			not path.begins_with("stub://")):
		_error("%s: can't open %s%s" % [label, path, (": " + str(src.last_error)) if src != null else ""])
		return
	if step.has("mode"):
		m.set_video_mode(VideoMode.from_id(str(step["mode"])), false)
	if float(step.get("start", 0.0)) > 0.0 and m.player.can_seek():
		m.player.seek(float(step["start"]))
	if not m.player.is_playing():
		m.player.play()
	_hide_pane()
	# Plays for `for` seconds, or to its end.
	var length := float(step.get("for", -1.0))
	var ended := [false]
	var on_ended := func() -> void: ended[0] = true
	m.player.ended.connect(on_ended)
	var end := Time.get_ticks_msec() + int((length if length > 0.0 else MAX_PLAY) * 1000.0)
	while not _stop and not ended[0] and Time.get_ticks_msec() < end and m.player.source == src:
		await get_tree().process_frame
	if m.player.ended.is_connected(on_ended):
		m.player.ended.disconnect(on_ended)


## An environment id or one of its --env names (room, cinema), or recipe:<name>.
func _set_environment(name: String, label: String) -> void:
	var m := main
	var want := name.to_lower()
	for e: Array in m.all_environments():
		if want == str(e[0]).to_lower() or want in e[3]:
			m.set_environment(e[0])
			return
	_error("%s: no environment %s" % [label, name])


## Eases the screen from where it is to the given width / distance / height (m) / yaw (degrees).
func _move_screen(to: Dictionary, over: float) -> void:
	var m := main
	var from := [m.screen_width, m.screen_distance, m.screen_height_offset, m.screen_yaw]
	var target := [float(to.get("width", from[0])), float(to.get("distance", from[1])),
			float(to.get("height", from[2])), deg_to_rad(float(to["yaw"])) if to.has("yaw") else from[3]]
	await _ease(over, func(t: float) -> void:
		var v := []
		for k in 4:
			v.append(lerpf(from[k], target[k], t))
		main.screen_yaw = v[3]
		main.set_screen(v[0], v[1], v[2]))


## Eases the flat camera to yaw / pitch (degrees, as --look), fov (degrees) and position [x, y, z]. Skipped in XR.
func _move_camera(to: Dictionary, over: float, label: String) -> void:
	var m := main
	if m.use_xr:
		print("Tour: %s: a camera move, skipped in XR (the head is the camera)" % label)
		return
	var cam: Camera3D = m.flat_camera
	var look_from: Vector2 = m.get("_look")
	var look_to := Vector2(float(to.get("yaw", look_from.x)), float(to.get("pitch", look_from.y)))
	var fov_from := cam.fov
	var fov_to := float(to.get("fov", fov_from))
	var pos_from := cam.position
	var pos_to := pos_from
	if to.get("position") is Array and (to["position"] as Array).size() == 3:
		var p: Array = to["position"]
		pos_to = Vector3(float(p[0]), float(p[1]), float(p[2]))
	await _ease(over, func(t: float) -> void:
		var c: Camera3D = main.flat_camera
		main.set("_look", look_from.lerp(look_to, t))
		main.call("_apply_look")
		c.fov = lerpf(fov_from, fov_to, t)
		c.position = pos_from.lerp(pos_to, t))


## Calls apply(t) each frame with t eased from 0 to 1 over `seconds` (once with 1 when 0).
func _ease(seconds: float, apply: Callable) -> void:
	if seconds <= 0.0:
		apply.call(1.0)
		return
	var start := Time.get_ticks_msec()
	while not _stop:
		var t := clampf((Time.get_ticks_msec() - start) / (seconds * 1000.0), 0.0, 1.0)
		apply.call(smoothstep(0.0, 1.0, t))
		if t >= 1.0:
			return
		await get_tree().process_frame


func _command(cmd: String, args: Variant, label: String) -> void:
	CommandHost.ensure(get_tree())
	var r: Dictionary = await DevCommands.execute(cmd, args if args is Dictionary else {}, false, self)
	if not r["ok"]:
		_error("%s: %s: %s" % [label, cmd, r["error"]])


## The gate for command steps: read, control and change; never code.
func check(ctx: DevCommands.Call, spec: Dictionary) -> String:
	var level := str(spec.get("level", "read"))
	if ctx.name == "set":
		var setting := str(ctx.args.get("setting", ""))
		level = str(DevCommands.setting_spec(setting).get("level", "change")) if DevCommands.has_setting(setting) \
				else "change"
	return "" if level in ALLOWED_LEVELS else "a tour can't run %s commands" % level
