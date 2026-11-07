extends RefCounted

## The control API's built-in commands and settings (docs/dev/control-protocol.md, "Commands"): describe, playback,
## open, get / set, the node tree and reload. command_host.gd makes one and keeps it; every handler reads the current
## main through `host`, so they keep working after `reload app`.

const DevCommands := preload("res://scripts/dev/dev_commands.gd")
const VideoMode := preload("res://scripts/video_mode.gd")
const HotReload := preload("res://scripts/dev/hot_reload.gd")

## Settings sections that `get` and `set` never touch (saved SMB passwords).
const PRIVATE_SECTIONS: Array[String] = ["network"]
## Sections `set` may not write: the permission ring's own settings, so the PC can't raise its own permissions.
const READ_ONLY_SECTIONS: Array[String] = ["dev"]
## Words that mark a secret in a setting key or a property path: the phone remote's pairing code ([remote] key), a
## PIN, saved passwords. The dev link logs every reply, so these never go out (is_private()).
const SECRET_WORDS: Array[String] = ["key", "pin", "password", "passwd", "secret", "token", "credential", "credentials"]
const OPEN_WAIT := 10.0
const TREE_MAX_NODES := 3000

## scripts/dev/dev_host.gd
var host: Node


func _main() -> Node:
	return host.main if host != null and is_instance_valid(host.main) else null


func register_all() -> void:
	var R := DevCommands
	R.register("describe", _cmd_describe, {
		"description": "The schema of every command, setting and event, generated from the running app.",
		"returns": "{proto, app, commands: {name: spec}, settings: {name: spec}, events: {name: spec}}"})
	R.register("get", _cmd_get, {
		"description": "A setting's value; with no setting, the app state and every registered setting.",
		"params": [{"name": "setting", "type": "string", "default": "",
				"description": "a registered setting, or SECTION/KEY of settings.cfg"}],
		"returns": "the value, or {state, settings}"})
	R.register("set", _cmd_set, {
		"description": "Changes a setting (registered: applied now; SECTION/KEY: written to settings.cfg, read at start).",
		"params": [{"name": "setting", "type": "string", "required": true},
				{"name": "value", "type": "any", "required": true}],
		"level": "change", "returns": "the new value"})
	R.register("play", _cmd_play, {"description": "Plays the open file from where it is.", "level": "control",
			"assistant": "control", "returns": "the state"})
	R.register("pause", _cmd_pause, {"description": "Pauses; play goes on from the same place.", "level": "control",
			"assistant": "control", "returns": "the state"})
	R.register("seek", _cmd_seek, {
		"description": "Seeks to a time in seconds, or by an amount with relative.",
		"params": [{"name": "seconds", "type": "float", "required": true,
				"description": "the time to go to, or with relative the amount to go forward (+) or back (-)"},
				{"name": "relative", "type": "bool", "default": false,
				"description": "true: seconds is an amount from the position now (the pane's -10 s / +10 s are -10 "
						+ "and 10)"}],
		"level": "control", "assistant": "control", "returns": "{position, duration}"})
	R.register("open", _cmd_open, {
		"description": "Opens a file on the headset (or stub://<mode id>, smb://host/share/path, browser://url) and "
				+ "waits up to %d s for it to open. Its folder becomes the playlist (a file already in the playlist "
				% OPEN_WAIT + "keeps it). It resumes at a saved position (resumed_from in the reply) unless from_start.",
		"params": [{"name": "path", "type": "string", "required": true},
				{"name": "from_start", "type": "bool", "default": false}],
		"level": "control", "assistant": "control",
		"returns": "the state once open, or {opening: path} if still connecting"})
	R.register("stop", _cmd_stop, {"description": "Stops: the file closes (resume keeps its place), the playlist "
			+ "is cleared and the room goes to its pre-show (a telly switches off).", "level": "control",
			"assistant": "control", "returns": "the state"})
	R.register("next", _cmd_next, {"description": "The next file of the playlist.", "level": "control",
			"assistant": "control", "returns": "the state"})
	R.register("previous", _cmd_previous, {"description": "The previous file, or the start of this one after 3 s.",
			"level": "control", "assistant": "control", "returns": "the state"})
	R.register("menu", _cmd_menu, {
		"description": "Shows the menu panel in front of the head (also when shown: a recentre) or hides it.",
		"params": [{"name": "shown", "type": "bool", "required": true},
				{"name": "hand", "type": "string", "default": "",
				"description": "left or right: that controller points at the panel (default: the current one)"}],
		"level": "control"})
	R.register("list_tree", _cmd_list_tree, {
		"description": "The scene tree under a node: name, class, script, visibility and position, to a depth.",
		"params": [{"name": "path", "type": "string", "default": "/root",
				"description": "absolute (/root/Main/...) or relative to the main scene"},
				{"name": "depth", "type": "int", "default": 3},
				{"name": "properties", "type": "bool", "default": false,
				"description": "also each node's editor-visible properties"}],
		"returns": "{name, class, path, children: [...]}"})
	R.register("reload", _cmd_reload, {
		"description": "Hot-reload now: \"\" every file changed since the last check, a res:// path that file, "
				+ "\"app\" the whole main scene instanced again.",
		"params": [{"name": "target", "type": "string", "default": ""}],
		"level": "change", "returns": "[{path, kind, ok, ms, note}] or {reloaded: app}"})
	_register_settings()


func _register_settings() -> void:
	var R := DevCommands
	R.register_setting("volume", func() -> float: return _main().volume,
			func(v: float) -> void: _main().set_volume(v),
			{"type": "float", "min": 0.0, "max": 1.0, "level": "control", "description": "master volume 0..1"})
	R.register_setting("av_offset", func() -> float: return _main().player.av_offset,
			func(v: float) -> void: _main().set_av_offset(v),
			{"type": "float", "min": -2.0, "max": 2.0, "level": "control",
			"description": "A/V offset in seconds (> 0: video later)"})
	R.register_setting("overlay", func() -> bool: return _main().overlay_on,
			func(v: bool) -> void: _main().set_overlay(v),
			{"type": "bool", "level": "control", "description": "the info overlay"})
	var env_ids: Array = []
	for e: Array in _main().get_environment_list():
		env_ids.append(e[0])
	R.register_setting("environment", func() -> String: return _main().env_id,
			func(v: String) -> void: _main().set_environment(v),
			{"type": "string", "enum": env_ids, "level": "control", "description": "the room"})
	R.register_setting("room_light", func() -> float: return _main().room_light,
			func(v: float) -> void: _main().set_room_light(v),
			{"type": "float", "min": 0.0, "max": 2.0, "level": "control",
			"description": "room light, 1 = as designed (remembered per environment)"})
	R.register_setting("screen_width", func() -> float: return _main().screen_width,
			_set_screen_width,
			{"type": "float", "min": 0.2, "max": 40.0, "level": "control", "description": "flat screen width, m"})
	R.register_setting("screen_distance", func() -> float: return _main().screen_distance,
			_set_screen_distance,
			{"type": "float", "min": 0.5, "max": 40.0, "level": "control", "description": "flat screen distance, m"})
	R.register_setting("screen_height", func() -> float: return _main().screen_height_offset,
			_set_screen_height,
			{"type": "float", "min": -5.0, "max": 10.0, "level": "control",
			"description": "screen centre above eye level, m"})
	R.register_setting("mode", func() -> String: return _main().mode.to_id(), _set_mode,
			{"type": "string", "level": "control",
			"description": "projection and layout: a mode id (flat_sbs_half, 360_tb, ...), a --mode= form, or auto"})
	# Dual fisheye 360 lenses (scripts/play/dual_fisheye.gd): the open file's profile and its values, kept per profile.
	var dual := func() -> Node: return _main().features.dual_fisheye
	R.register_setting("dual_fisheye_profile", func() -> String: return dual.call().profile,
			func(v: String) -> void: dual.call().set_profile(v, true),
			{"type": "string", "enum": preload("res://scripts/play/dual_fisheye.gd").PROFILES, "level": "control",
			"description": "dual fisheye 360 camera profile for the open file (camera360, camera360_photo, generic)"})
	R.register_setting("dual_fisheye_fov", func() -> float: return dual.call().fov(),
			func(v: float) -> void: dual.call().set_value("fov", v),
			{"type": "float", "min": 150.0, "max": 240.0, "level": "control",
			"description": "dual fisheye 360: both lenses' field of view, degrees (kept for the profile)"})
	R.register_setting("dual_fisheye_seam", func() -> float: return dual.call().seam(),
			func(v: float) -> void: dual.call().set_value("seam", v),
			{"type": "float", "min": -5.0, "max": 5.0, "level": "control",
			"description": "dual fisheye 360: the back lens's yaw, degrees (slides the back picture along the seam)"})
	R.register_setting("dual_fisheye_lens", func() -> Dictionary: return dual.call().values(),
			func(v: Dictionary) -> void: dual.call().set_values(v),
			{"type": "object", "level": "control",
			"description": "dual fisheye 360 values of the open file's profile: {front: {fov, cx, cy, radius, yaw, "
					+ "pitch, roll}, back: {...}, blend, model}; set any part of it ({\"back\": {\"roll\": -0.5}})"})


func _set_screen_width(v: float) -> void:
	var m := _main()
	m.set_screen(v, m.screen_distance, m.screen_height_offset)


func _set_screen_distance(v: float) -> void:
	var m := _main()
	m.set_screen(m.screen_width, v, m.screen_height_offset)


func _set_screen_height(v: float) -> void:
	var m := _main()
	m.set_screen(m.screen_width, m.screen_distance, v)


func _set_mode(v: String) -> void:
	var m := _main()
	if v.to_lower() == "auto":
		m.auto_mode()
		return
	var size: Vector2 = m._frame_size()
	m.set_video_mode(VideoMode.from_arg(v, int(size.x), int(size.y)))


# --- Handlers ------------------------------------------------------------------------------------------------------

func _cmd_describe(_args: Dictionary, _ctx: DevCommands.Call) -> Variant:
	var out := DevCommands.describe()
	out["proto"] = preload("res://scripts/dev/dev_link.gd").PROTOCOL
	out["app"] = str(ProjectSettings.get_setting("application/config/name"))
	out["levels"] = {
		"read": "changes nothing",
		"control": "playback and view: play, seek, open, volume, screen",
		"change": "settings files, the scene, reloads",
		"code": "runs code sent from the PC"}
	return out


func _cmd_get(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var setting: String = args["setting"]
	if setting == "":
		var values := {}
		for s: String in DevCommands.setting_names():
			values[s] = DevCommands.get_setting(s)
		return {"state": host.app_state(), "settings": values}
	if DevCommands.has_setting(setting):
		return DevCommands.get_setting(setting)
	var raw := _raw_key(setting)
	if raw.is_empty():
		return ctx.fail("no setting %s (registered: %s; or SECTION/KEY)" % [setting,
				", ".join(DevCommands.setting_names())])
	if is_private(setting):
		return ctx.fail("%s is private" % setting)
	return _main().settings.get_value(raw[0], raw[1], null)


func _cmd_set(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var setting: String = args["setting"]
	var value: Variant = args["value"]
	if DevCommands.has_setting(setting):
		var old: Variant = DevCommands.get_setting(setting)
		var err := DevCommands.set_setting(setting, value)
		if err != "":
			return ctx.fail(err)
		var now: Variant = DevCommands.get_setting(setting)
		ctx.summary = "%s %s" % [setting, _short(now)]
		ctx.undo = func() -> void: DevCommands.set_setting(setting, old)
		return now
	var raw := _raw_key(setting)
	if raw.is_empty():
		return ctx.fail("no setting %s (registered: %s; or SECTION/KEY)" % [setting,
				", ".join(DevCommands.setting_names())])
	if is_private(setting):
		return ctx.fail("%s is private" % setting)
	if raw[0] in READ_ONLY_SECTIONS:
		return ctx.fail("[%s] can only be changed on the headset" % raw[0])
	var settings: RefCounted = _main().settings
	var before: Variant = settings.get_value(raw[0], raw[1], null)
	settings.set_value(raw[0], raw[1], value)
	settings.save_if_dirty()
	ctx.summary = "settings %s %s" % [setting, _short(value)]
	ctx.undo = func() -> void:
		settings.set_value(raw[0], raw[1], before)
		settings.save_if_dirty()
	return {"written": setting, "value": value, "note": "read at the next start"}


## True for a setting ("section/key") or a property path ("a:b/c") that the dev link must not read or write: a
## private section, a GDScript private member (leading "_"), or a name with a secret word in it (remote_key, pin).
static func is_private(path: String) -> bool:
	var parts := path.replace(":", "/").split("/", false)
	if parts.size() >= 2 and parts[0] in PRIVATE_SECTIONS:
		return true
	for part in parts:
		if part.begins_with("_"):
			return true
		for word in part.to_lower().split("_", false):
			if word in SECRET_WORDS:
				return true
	return false


## True for what a masked text field holds (a password being typed, as in the SMB host form):
## its text property, or a method that returns or restores the text. get_prop, set_prop, call and list_tree refuse it.
static func is_secret_field(obj: Object, property_or_method: String) -> bool:
	if not (obj is LineEdit and (obj as LineEdit).secret):
		return false
	return property_or_method.get_slice(":", 0) in ["text", "get_text", "get_selected_text", "undo", "redo"]


## "section/key" -> [section, key], else [].
static func _raw_key(setting: String) -> Array:
	var parts := setting.split("/", false, 1)
	return [parts[0], parts[1]] if parts.size() == 2 else []


static func _short(v: Variant) -> String:
	if v is float:
		return str(snappedf(v, 0.01))
	var s := str(v)
	return s if s.length() <= 40 else s.substr(0, 37) + "..."


func _cmd_play(_args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var was: bool = _main().player.is_playing()
	_main().player.play()
	ctx.summary = "play"
	if not was:
		ctx.undo = func() -> void: _main().player.pause()
	return host.app_state()


func _cmd_pause(_args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var was: bool = _main().player.is_playing()
	_main().player.pause()
	ctx.summary = "pause"
	if was:
		ctx.undo = func() -> void: _main().player.play()
	return host.app_state()


func _cmd_stop(_args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var m := _main()
	var old: String = m.current_path
	if old == "":
		return ctx.fail("nothing is open")
	m.close_media()
	ctx.summary = "stopped %s" % old.get_file()
	# Undo opens it again; resume brings back its place.
	ctx.undo = func() -> void: _main().open_path(old, false)
	return host.app_state()


func _cmd_next(_args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var m := _main()
	var old: String = m.current_path
	m.next_file()
	ctx.summary = "next file"
	if old != "" and m.current_path != old:
		ctx.undo = func() -> void: _main().open_path(old, false)
	return host.app_state()


func _cmd_previous(_args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var m := _main()
	var old: String = m.current_path
	var old_pos: float = m.player.get_position()
	m.previous_file()
	ctx.summary = "previous"
	if m.current_path != old:
		ctx.undo = func() -> void: _main().open_path(old, false)
	else:
		ctx.undo = func() -> void: _main().player.seek(old_pos)
	return host.app_state()


func _cmd_seek(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var p: Node = _main().player
	if not p.has_source():
		return ctx.fail("nothing is open")
	if not p.can_seek():
		return ctx.fail("this source can't seek")
	var old: float = p.get_position()
	var target: float = old + args["seconds"] if args["relative"] else args["seconds"]
	target = clampf(target, 0.0, maxf(p.get_duration(), 0.0))
	p.seek(target)
	ctx.summary = "seek to %s" % _clock(target)
	ctx.undo = func() -> void: _main().player.seek(old)
	return {"position": snappedf(target, 0.01), "duration": snappedf(p.get_duration(), 0.01)}


static func _clock(t: float) -> String:
	var s := maxi(0, int(t))
	return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]


func _cmd_open(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var path: String = args["path"]
	if path.begins_with("~/"):
		path = OS.get_environment("HOME").path_join(path.trim_prefix("~/"))
	var scheme := path.get_slice("://", 0) if path.contains("://") else ""
	if scheme == "" and not FileAccess.file_exists(path):
		return ctx.fail("no such file on the headset: %s" % path)
	var m := _main()
	var old: String = m.current_path
	var opened := {"done": false}
	var on_open := func(p: String) -> void:
		if p == path:
			opened["done"] = true
	m.file_opened.connect(on_open)
	# The resume feature seeks just after the open: catch it, so the reply can say so (an assistant was surprised by a
	# silent resume).
	var resumed := {"at": -1.0}
	var rs: Object = m.features.get("resume") if m.get("features") != null else null
	var on_resumed := func(pos: float) -> void: resumed["at"] = pos
	if rs != null and rs.has_signal("resumed"):
		rs.resumed.connect(on_resumed)
	# A file already in the playlist keeps it (opening one of 90 made the playlist 1 of 1).
	m.open_path(path, m.playlist.find(path) < 0)
	var deadline := Time.get_ticks_msec() + int(OPEN_WAIT * 1000.0)
	while not opened["done"] and Time.get_ticks_msec() < deadline:
		await host.get_tree().process_frame
	if is_instance_valid(m) and m.file_opened.is_connected(on_open):
		m.file_opened.disconnect(on_open)
	ctx.summary = "open %s" % path.get_file()
	if old != "":
		ctx.undo = func() -> void: _main().open_path(old)
	if opened["done"]:
		for i in 3:
			await host.get_tree().process_frame
	if rs != null and is_instance_valid(rs) and rs.resumed.is_connected(on_resumed):
		rs.resumed.disconnect(on_resumed)
	if opened["done"] and bool(args.get("from_start", false)) and rs != null and rs.has_method("start_over"):
		rs.start_over()
		resumed["at"] = -1.0
	if not opened["done"]:
		return {"opening": path}
	var state: Dictionary = host.app_state()
	state["resumed_from"] = snappedf(resumed["at"], 0.1) if resumed["at"] > 0.0 else null
	state["playlist"] = {"index": m.playlist_index, "size": m.playlist.size()}
	var src: Object = m.player.source
	if src != null and str(src.last_error) != "":
		state["note"] = src.last_error
	return state


func _cmd_menu(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var m := _main()
	if m.ui == null:
		return ctx.fail("this build has no menu layer")
	var was_shown: bool = m.ui.is_open() if m.ui.has_method("is_open") else not args["shown"]
	var side := str(args.get("hand", ""))
	if not side in ["", "left", "right"]:
		return ctx.fail("hand: left or right")
	if args["shown"]:
		m.ui.show_panel(m.left_hand if side == "left" else (m.right_hand if side == "right" else null))
	else:
		m.ui.hide_panel()
	ctx.summary = "menu %s" % ("shown" if args["shown"] else "hidden")
	ctx.undo = func() -> void:
		var mm := _main()
		if mm.ui != null:
			if was_shown:
				mm.ui.show_panel()
			else:
				mm.ui.hide_panel()
	return {"shown": args["shown"]}


func _resolve(path: String) -> Node:
	var m := _main()
	if path == "" or path == ".":
		return m
	if path.begins_with("/"):
		return host.get_tree().root.get_node_or_null(NodePath(path))
	return m.get_node_or_null(NodePath(path)) if m != null else null


func _cmd_list_tree(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var node := _resolve(args["path"])
	if node == null:
		return ctx.fail("no node %s" % args["path"])
	var budget := [TREE_MAX_NODES]
	var out := _tree(node, args["depth"], args["properties"], budget)
	if budget[0] <= 0:
		out["truncated"] = "more than %d nodes; list a subtree or lower the depth" % TREE_MAX_NODES
	return out


func _tree(node: Node, depth: int, props: bool, budget: Array) -> Dictionary:
	budget[0] -= 1
	var d := {"name": str(node.name), "class": node.get_class(), "path": str(node.get_path())}
	var script: Script = node.get_script()
	if script != null and script.resource_path != "":
		d["script"] = script.resource_path
	if node is Node3D:
		d["visible"] = (node as Node3D).visible
		d["position"] = DevCommands.to_json((node as Node3D).position)
	elif node is CanvasItem:
		d["visible"] = (node as CanvasItem).visible
	if props:
		d["properties"] = node_properties(node)
	var n := node.get_child_count()
	if n == 0:
		return d
	if depth <= 0 or budget[0] <= 0:
		d["child_count"] = n
		return d
	var children: Array = []
	for c in node.get_children():
		if budget[0] <= 0:
			break
		children.append(_tree(c, depth - 1, props, budget))
	d["children"] = children
	return d


## The editor-visible properties of an object as JSON values.
static func node_properties(obj: Object) -> Dictionary:
	var out := {}
	for p: Dictionary in obj.get_property_list():
		if not (int(p["usage"]) & PROPERTY_USAGE_EDITOR) or int(p["usage"]) & PROPERTY_USAGE_GROUP \
				or int(p["usage"]) & PROPERTY_USAGE_CATEGORY or int(p["usage"]) & PROPERTY_USAGE_SUBGROUP \
				or is_private(str(p["name"])) or is_secret_field(obj, str(p["name"])):
			continue
		out[p["name"]] = DevCommands.to_json(obj.get(p["name"]))
	return out


func _cmd_reload(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var target: String = args["target"]
	if target == "app":
		var tree: SceneTree = host.get_tree()
		ctx.summary = "reload app"
		# After the reply goes out: the main scene is freed and instanced again; attach() re-points the tools.
		tree.reload_current_scene.call_deferred()
		return {"reloaded": "app"}
	var hr: HotReload = host.ensure_hot_reload()
	if hr == null:
		return ctx.fail("hot-reload needs dev mode (--dev or --listener)")
	if target == "":
		ctx.summary = "reload changed files"
		return hr.reload_changed()
	if not target.begins_with("res://"):
		return ctx.fail("target is \"\", \"app\" or a res:// path")
	ctx.summary = "reload %s" % target.get_file()
	var info := hr.reload_path(target)
	hr.finish_batch()
	return [info]
