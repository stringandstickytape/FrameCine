extends RefCounted

## The Picture, Sound and Subtitles tabs and the transport's extras as commands (docs/dev/assistant-coverage/playback.md):
## what the viewer does there with the controllers, the assistant does with these. Registered by command_host.gd, so
## the PC link, the phone and the assistant service (the "assistant" tag) share them.
##
## Each tab has one read (picture, sound, subtitle_settings; playback for the transport's extras) and a few section
## setters (set_picture, set_screen, set_sound...) whose params are all optional: give the ones to change. A setter
## goes through the same feature call the tab's widget makes, so the effect is identical; then the tab syncs, the toast
## says what changed, and undo puts back every value that changed. Values outside the tab's own range are refused, not
## clamped, so the assistant learns the range.

const DevCommands := preload("res://scripts/dev/dev_commands.gd")
const VideoMode := preload("res://scripts/video_mode.gd")
const PCAudio := preload("res://scripts/dev/pc_audio.gd")

const PROJECTIONS: Array[String] = ["flat", "180", "360", "fisheye", "dualfisheye"]
const LAYOUTS: Array[String] = ["mono", "sbs", "tb"]
## two_d.eye + 1: both eyes (3D), the left eye's picture, the right eye's.
const EYES: Array[String] = ["3d", "left", "right"]
const RESET_PARTS: Array[String] = ["screen", "zoom", "horizon", "picture", "hdr", "dual_lens"]
## Items with no folder for a folder rule (as the Picture tab's Use for this folder).
const NO_FOLDER_PREFIXES: Array[String] = ["stub://", "window://", "browser://", "lab://"]

## command -> its setter fields, for picture_reset's undo.
static var _fields := {}


static func register_commands(host: Node) -> void:
	_register_transport(host)
	_register_picture(host)
	_register_sound(host)
	_register_subtitles(host)


# --- Section setters ------------------------------------------------------------------------------------------------

## One setting of a section setter: its param, getter(main) and setter(main, value). extra: min, max (checked, and
## the description says them), enum, derived (true: computed from others, so undo restores those instead), needs
## (main -> "" or why it can't be set now).
static func _field(name: String, type: String, description: String, getter: Callable, setter: Callable,
		extra := {}) -> Dictionary:
	var param := {"name": name, "type": type, "description": description}
	if extra.has("enum"):
		param["enum"] = extra["enum"]
	var f := {"param": param, "get": getter, "set": setter}
	f.merge(extra)
	return f


## Registers a setter over `fields`: the given params are checked, then set in the fields' order. Returns read(main).
## options: check (args -> "" or why the combination is refused), assistant (its level; default settings).
static func _register_setter(host: Node, command: String, description: String, fields: Array, tab: String,
		label: String, read: Callable, options := {}) -> void:
	_fields[command] = fields
	var check: Callable = options.get("check", Callable())
	var params: Array = []
	for f: Dictionary in fields:
		params.append(f["param"])
	var names := ", ".join(params.map(func(p: Dictionary) -> String: return p["name"]))
	DevCommands.register(command, func(args: Dictionary, ctx: DevCommands.Call) -> Variant:
		var m: Node = host.main
		var given: Array = fields.filter(func(f: Dictionary) -> bool: return args.has(f["param"]["name"]))
		if given.is_empty():
			return ctx.fail("give at least one of: %s" % names)
		var refused := str(check.call(args)) if check.is_valid() else ""
		if refused != "":
			return ctx.fail(refused)
		for f: Dictionary in given:
			var why := _refusal(f, args[f["param"]["name"]], m)
			if why != "":
				return ctx.fail(why)
		var before := _snapshot(fields, m)
		var said: Array[String] = []
		for f: Dictionary in given:
			var v: Variant = args[f["param"]["name"]]
			(f["set"] as Callable).call(m, v)
			said.append("%s %s" % [str(f["param"]["name"]).replace("_", " "), _short(v)])
		_sync_tab(m, tab)
		ctx.summary = "%s: %s" % [label, ", ".join(said)]
		ctx.undo = func() -> void:
			_restore(fields, before, host.main)
			_sync_tab(host.main, tab)
		return read.call(m), {
		"description": description, "params": params, "level": "control",
		"assistant": options.get("assistant", "settings"),
		"returns": "the tab's state after the change, as its read gives it"})


static func _refusal(f: Dictionary, v: Variant, m: Node) -> String:
	var name: String = f["param"]["name"]
	if f.has("needs"):
		var why: String = (f["needs"] as Callable).call(m)
		if why != "":
			return "%s: %s" % [name, why]
	if (v is float or v is int) and f.has("min") and (v < f["min"] or v > f["max"]):
		return "%s must be between %s and %s" % [name, f["min"], f["max"]]
	return ""


static func _snapshot(fields: Array, m: Node) -> Dictionary:
	var out := {}
	for f: Dictionary in fields:
		if not f.get("derived", false):
			out[f["param"]["name"]] = (f["get"] as Callable).call(m)
	return out


## Sets back, in the fields' order, every value that differs from `before`.
static func _restore(fields: Array, before: Dictionary, m: Node) -> void:
	for f: Dictionary in fields:
		var name: String = f["param"]["name"]
		if before.has(name) and (f["get"] as Callable).call(m) != before[name]:
			(f["set"] as Callable).call(m, before[name])


## The tab shows the new values (most follow their feature's signal already; a few, such as the subtitle look, don't).
static func _sync_tab(m: Node, tab: String) -> void:
	var layer: Object = m.get("ui") if m != null else null
	var pane: Object = layer.get("ui") if layer != null else null
	var t: Object = pane.get(tab) if pane != null else null
	if t != null and t.has_method("sync"):
		t.sync()


static func _short(v: Variant) -> String:
	if v is float:
		return str(snappedf(v, 0.01))
	if v is bool:
		return "on" if v else "off"
	return str(v)


static func _r(v: float) -> float:
	return snappedf(v, 0.001)


# --- Transport ------------------------------------------------------------------------------------------------------

static func _register_transport(host: Node) -> void:
	var R := DevCommands
	R.register("playback", func(_args: Dictionary, _ctx: DevCommands.Call) -> Variant:
		return _playback_state(host.main), {
		"description": "The transport's extras: the playback speed and the speeds offered, trick play (scanning "
				+ "forward with pictures), the A-B loop, the info overlay, whether a 10 s replay runs, and one frame's "
				+ "length.", "level": "read", "assistant": "read",
		"returns": "{can_seek, speed, speeds, trick_speed, trick_available, loop: {active, a, b, text}, overlay, "
				+ "replaying, frame_seconds}"})
	R.register("trick_play", func(args: Dictionary, ctx: DevCommands.Call) -> Variant:
		var m: Node = host.main
		var trick: Node = m.features.trick
		var speed: float = args["speed"]
		if speed <= 0.0:
			trick.stop()
			ctx.summary = "scan off"
			return _playback_state(m)
		if not m.player.can_seek() or not bool(trick.available()):
			return ctx.fail("this file can't scan (trick play needs a seekable video file)")
		if not bool(trick.start(speed)):
			return ctx.fail("the player could not start scanning")
		ctx.summary = "scan %dx" % roundi(speed)
		ctx.undo = func() -> void: host.main.features.trick.stop()
		return _playback_state(m), {
		"description": "Scans forward with pictures and no sound at 4x or 8x, as holding the stick right or the pane's "
				+ "4x / 8x button does; it goes on until trick_play 0, a seek, or play / pause.",
		"params": [{"name": "speed", "type": "float", "required": true, "enum": [0.0, 4.0, 8.0],
				"description": "4 or 8 to scan at that speed; 0 to stop and play on from the frame on screen"}],
		"level": "control", "assistant": "control", "returns": "the playback read"})
	R.register("frame_step", func(args: Dictionary, ctx: DevCommands.Call) -> Variant:
		var m: Node = host.main
		var frames: int = args["frames"]
		if frames == 0 or absi(frames) > 100:
			return ctx.fail("frames: -100..100, not 0")
		if not m.player.can_seek():
			return ctx.fail("this source can't seek")
		var old: float = m.player.get_position()
		m.features.step_loop.step(frames)
		ctx.summary = "frame %s%d" % ["+" if frames > 0 else "", frames]
		ctx.undo = func() -> void: host.main.player.seek(old)
		return {"position": _r(m.player.get_position()), "playing": m.player.is_playing()}, {
		"description": "Pauses and steps whole frames forward or back, as the Picture tab's Frame back and Frame "
				+ "forward buttons do.",
		"params": [{"name": "frames", "type": "int", "default": 1,
				"description": "how many frames: 1 forward, -1 back (up to 100 either way)"}],
		"level": "control", "assistant": "control", "returns": "{position, playing}"})
	R.register("loop", func(args: Dictionary, ctx: DevCommands.Call) -> Variant:
		var m: Node = host.main
		var duration: float = m.player.get_duration()
		if not m.player.can_seek() or duration <= 0.0:
			return ctx.fail("a loop needs a seekable file")
		for k: String in ["a", "b"]:
			if float(args[k]) < 0.0 or float(args[k]) > duration:
				return ctx.fail("%s must be between 0 and %s (the duration)" % [k, snappedf(duration, 0.01)])
		var sl: Node = m.features.step_loop
		var old := [bool(sl.active), float(sl.a), float(sl.b)]
		sl.set_loop(args["a"], args["b"])
		ctx.summary = sl.text()
		ctx.undo = func() -> void: _put_loop(host.main, old)
		return _playback_state(m)["loop"], {
		"description": "Repeats the part between two times (the A-B loop; the Picture tab's Mark A / B marks them at "
				+ "the position now). At least 0.5 s long.",
		"params": [{"name": "a", "type": "float", "required": true, "description": "the loop's start, seconds"},
				{"name": "b", "type": "float", "required": true, "description": "the loop's end, seconds"}],
		"level": "control", "assistant": "control", "returns": "{active, a, b, text}"})
	R.register("loop_clear", func(_args: Dictionary, ctx: DevCommands.Call) -> Variant:
		var m: Node = host.main
		var sl: Node = m.features.step_loop
		var old := [bool(sl.active), float(sl.a), float(sl.b)]
		sl.clear()
		ctx.summary = "loop cleared"
		ctx.undo = func() -> void: _put_loop(host.main, old)
		return _playback_state(m)["loop"], {
		"description": "Ends the A-B loop (the Picture tab's Clear loop); playback goes on.",
		"level": "control", "assistant": "control", "returns": "{active, a, b, text}"})
	R.register("replay", func(_args: Dictionary, ctx: DevCommands.Call) -> Variant:
		var m: Node = host.main
		if not m.player.can_seek():
			return ctx.fail("this source can't seek")
		var old: float = m.player.get_position()
		m.features.catch_up.replay()
		ctx.summary = "replay 10 s"
		ctx.undo = func() -> void:
			host.main.features.catch_up.cancel()
			host.main.player.seek(old)
		return {"position": _r(m.player.get_position()), "until": _r(float(m.features.catch_up.end_position))}, {
		"description": "Goes back 10 s and plays them again with subtitles on, then puts the subtitles back as they "
				+ "were (\"what did they say?\"; the Subtitles tab's Replay 10 s and the controller's REPLAY).",
		"level": "control", "assistant": "control", "returns": "{position, until}"})
	R.register("speed", func(args: Dictionary, ctx: DevCommands.Call) -> Variant:
		var m: Node = host.main
		var sp: Node = m.features.speed
		var old: float = sp.speed
		sp.set_speed(args["speed"])
		ctx.summary = "speed %s" % sp.text()
		ctx.undo = func() -> void: host.main.features.speed.set_speed(old)
		return {"speed": sp.speed}, {
		"description": "The playback speed with the pitch kept (the Sound tab's Speed); 1 is normal.",
		"params": [{"name": "speed", "type": "float", "required": true,
				"enum": Array(preload("res://scripts/play/playback_speed.gd").STEPS),
				"description": "times normal speed: 0.5 to 2 in the tab's steps"}],
		"level": "control", "assistant": "control", "returns": "{speed}"})
	R.register("info_overlay", func(args: Dictionary, ctx: DevCommands.Call) -> Variant:
		var m: Node = host.main
		var old: bool = m.overlay_on
		m.set_overlay(args["on"])
		_sync_tab(m, "system")
		ctx.summary = "info overlay %s" % ("on" if args["on"] else "off")
		ctx.undo = func() -> void:
			host.main.set_overlay(old)
			_sync_tab(host.main, "system")
		return {"overlay": m.overlay_on}, {
		"description": "Shows or hides the info overlay under the screen: title, time, the mode and the battery (the "
				+ "controller's INFO button and the System tab's Info overlay). It hides while the panel is open.",
		"params": [{"name": "on", "type": "bool", "required": true, "description": "true shows it, false hides it"}],
		"level": "control", "assistant": "control", "returns": "{overlay}"})
	R.register("screenshot_frame", func(_args: Dictionary, ctx: DevCommands.Call) -> Variant:
		var m: Node = host.main
		var shot: Node = m.features.screenshot
		var path: String = await shot.capture()
		if path == "":
			return ctx.fail("no screenshot: %s" % shot.last_error)
		ctx.summary = "screenshot %s" % path.get_file()
		return {"path": ProjectSettings.globalize_path(path)}, {
		"description": "Saves the frame on screen as a picture on the headset, in the video's own layout (both eyes "
				+ "for 3D), as the Picture tab's Screenshot does. The picture stays on the headset.",
		"level": "control", "assistant": "control", "returns": "{path}"})
	R.register("av_calibrate", func(_args: Dictionary, ctx: DevCommands.Call) -> Variant:
		var m: Node = host.main
		var old: String = m.current_path
		m.open_path("lab://av_sync", false)
		ctx.summary = "A/V calibration card"
		if old != "":
			ctx.undo = func() -> void: host.main.open_path(old, false)
		return {"opened": "lab://av_sync"}, {
		"description": "Opens the A/V calibration card (the Sound tab's Calibrate): a flash and a click the viewer "
				+ "lines up with the A/V offset; open the film again after.",
		"level": "control", "assistant": "control", "returns": "{opened}"})


static func _put_loop(m: Node, old: Array) -> void:
	var sl: Node = m.features.step_loop
	if old[0]:
		sl.set_loop(old[1], old[2])
	else:
		sl.clear()


static func _playback_state(m: Node) -> Dictionary:
	var f: Node = m.features
	var sl: Node = f.step_loop
	return {
		"can_seek": m.player.can_seek(),
		"speed": f.speed.speed,
		"speeds": Array(f.speed.STEPS),
		"trick_speed": float(f.trick.speed),
		"trick_available": bool(f.trick.available()) and m.player.can_seek(),
		"loop": {"active": bool(sl.active), "a": _r(sl.a) if sl.a >= 0.0 else null,
				"b": _r(sl.b) if sl.b >= 0.0 else null, "text": sl.text()},
		"overlay": m.overlay_on,
		"replaying": bool(f.catch_up.active),
		"frame_seconds": snappedf(float(sl.frame_duration()), 0.0001),
	}


# --- Picture --------------------------------------------------------------------------------------------------------

static func _register_picture(host: Node) -> void:
	var R := DevCommands
	var read := func(m: Node) -> Dictionary: return _picture_state(m)
	R.register("picture", func(_args: Dictionary, _ctx: DevCommands.Call) -> Variant:
		return _picture_state(host.main), {
		"description": "Everything in the Picture tab: the mode (projection, layout, half, swap, how it was chosen, "
				+ "the folder rule), 3D, the screen (size, distance, height, size in degrees, curvature, zoom, head "
				+ "follow, lying down, auto crop), the horizon, the picture controls, HDR, the fisheye lenses, the "
				+ "slideshow and picture in picture (pip: null when none is open). applies: false where the section "
				+ "has no effect in this mode.",
		"level": "read", "assistant": "read",
		"returns": "{mode, stereo, screen, horizon, picture, hdr, lens, slideshow, pip}"})

	R.register("set_mode", func(args: Dictionary, ctx: DevCommands.Call) -> Variant:
		var m: Node = host.main
		if args.is_empty():
			return ctx.fail("give at least one of: projection, layout, half, swap, fisheye_fov")
		if args.has("fisheye_fov") and (float(args["fisheye_fov"]) < 120.0 or float(args["fisheye_fov"]) > 240.0):
			return ctx.fail("fisheye_fov must be between 120 and 240")
		var old: VideoMode = m.mode.copy()
		var old_source: String = m.mode_source
		var mode: VideoMode = m.mode.copy()
		if args.has("projection"):
			mode.projection = PROJECTIONS.find(args["projection"]) as VideoMode.Proj
		if args.has("layout"):
			mode.layout = LAYOUTS.find(args["layout"]) as VideoMode.Layout
		if args.has("half"):
			mode.half = args["half"]
		if args.has("swap"):
			mode.swap = args["swap"]
		if args.has("fisheye_fov"):
			mode.fisheye_fov = args["fisheye_fov"]
		m.set_video_mode(mode)
		ctx.summary = "mode %s" % m.mode.describe()
		ctx.undo = func() -> void:
			if old_source in ["auto", "metadata"]:
				host.main.auto_mode()
			else:
				host.main.set_video_mode(old)
		return _picture_state(m)["mode"], {
		"description": "Sets how the picture is shown, as the Picture tab's mode diagrams, Half and Swap eyes do, "
				+ "remembered for this file. Give only what changes; mode_auto goes back to the guess.",
		"params": [{"name": "projection", "type": "string", "enum": PROJECTIONS, "description": "flat screen, 180 or "
						+ "360 degree sphere, one fisheye lens, or a dual fisheye 360 camera's two lenses"},
				{"name": "layout", "type": "string", "enum": LAYOUTS, "description": "one picture (mono), or the two "
						+ "eyes side by side (sbs) or top and bottom (tb)"},
				{"name": "half", "type": "bool", "description": "the two eyes are squeezed to half width or height "
						+ "(half SBS / TB); flat 3D only"},
				{"name": "swap", "type": "bool", "description": "the right eye's picture comes first in the frame"},
				{"name": "fisheye_fov", "type": "float", "description": "the fisheye lens's field of view, 120 to 240 "
						+ "degrees"}],
		"level": "control", "assistant": "settings", "returns": "the picture read's mode"})
	R.register("mode_auto", func(_args: Dictionary, ctx: DevCommands.Call) -> Variant:
		var m: Node = host.main
		var old: VideoMode = m.mode.copy()
		var old_source: String = m.mode_source
		m.auto_mode()
		ctx.summary = "mode auto: %s" % m.mode.describe()
		if not old_source in ["auto", "metadata"]:
			ctx.undo = func() -> void: host.main.set_video_mode(old)
		return _picture_state(m)["mode"], {
		"description": "Forgets the mode chosen for this file and goes back to the one guessed from the file's name, "
				+ "size and metadata (the Picture tab's Auto).",
		"level": "control", "assistant": "settings", "returns": "the picture read's mode"})
	R.register("folder_rule", func(args: Dictionary, ctx: DevCommands.Call) -> Variant:
		var m: Node = host.main
		var fm: Node = m.features.folder_modes
		var path := str(m.current_path)
		var before: Dictionary = fm.rule_for(path)
		if args["on"]:
			if path == "" or NO_FOLDER_PREFIXES.any(func(x: String) -> bool: return path.begins_with(x)):
				return ctx.fail("the open item has no folder")
			fm.use_current_for_folder()
		elif before.is_empty():
			return ctx.fail("no folder rule applies to this file")
		else:
			fm.clear_rule(before["folder"])
		var after: Dictionary = fm.rule_for(path)
		ctx.summary = "folder rule %s" % ("set" if args["on"] else "cleared")
		ctx.undo = func() -> void:
			var f: Node = host.main.features.folder_modes
			if not before.is_empty():
				f.set_rule(before["folder"], before["mode"])
			elif not after.is_empty():
				f.clear_rule(after["folder"])
		return _picture_state(m)["mode"], {
		"description": "Makes the mode now the rule for the open file's folder, so its files without a mode of their "
				+ "own open in it, or clears the rule that applies (the Picture tab's Use for this folder and Clear "
				+ "folder rule).",
		"params": [{"name": "on", "type": "bool", "required": true,
				"description": "true: use the mode now for this folder; false: clear the folder's rule"}],
		"level": "control", "assistant": "settings", "returns": "the picture read's mode"})

	var depth_max: float = preload("res://scripts/play/stereo_depth.gd").MAX
	_register_setter(host, "set_3d", "The Picture tab's 3D section: which eye's picture shows, the depth, and soft "
			+ "edges. For 3D layouts (sbs, tb) only.", [
		_field("show", "string", "3d: both eyes; left or right: that eye's picture to both eyes (2D from 3D)",
				func(m: Node) -> String: return EYES[int(m.features.two_d.eye) + 1],
				func(m: Node, v: String) -> void: m.features.two_d.set_eye(EYES.find(v) - 1), {"enum": EYES}),
		_field("depth_this_file_only", "bool", "true: the depth is kept for this file only; false: the file uses the "
				+ "depth for all files", func(m: Node) -> bool: return bool(m.features.depth.has_file_value()),
				func(m: Node, v: bool) -> void:
					if v:
						m.features.depth.set_depth(m.features.depth.value, true)
					else:
						m.features.depth.clear_file()),
		_field("depth", "float", "moves the eye pictures apart (+, further away) or together (-), as a fraction of "
				+ "the picture's width, -%s to %s (the tab shows it as a percentage)" % [depth_max, depth_max],
				func(m: Node) -> float: return float(m.features.depth.value),
				func(m: Node, v: float) -> void: m.features.depth.set_depth(v, m.features.depth.has_file_value()),
				{"min": -depth_max, "max": depth_max}),
		_field("soft_edges", "bool", "fades the screen's edges, which eases 3D at the frame",
				func(m: Node) -> bool: return float(m.features.edge_fade.width) > 0.0,
				func(m: Node, v: bool) -> void:
					m.features.edge_fade.set_width(m.features.edge_fade.DEFAULT_ON if v else 0.0)),
	], "picture", "3D", read)

	var angle_script := preload("res://scripts/comfort/screen_angle.gd")
	var zoom_max: float = preload("res://scripts/play/zoom_pan.gd").MAX_ZOOM
	_register_setter(host, "set_screen", "The Picture tab's Screen section: the flat screen's size (in metres or in "
			+ "degrees), distance, height, curvature and zoom, a preset, head follow, lying down and auto crop. Give "
			+ "width or size_degrees, not both; a preset sets the size, the distance and lying down.", [
		_field("preset", "string", "a seat preset: large_format (70 degrees at 14 m), living_room (32 degrees at "
				+ "3.2 m) or in_bed (42 degrees at 2.4 m, lying down)",
				func(m: Node) -> String: return str(m.features.angle.matching_preset()),
				func(m: Node, v: String) -> void: m.features.angle.apply_preset(v),
				{"enum": angle_script.PRESETS.keys(), "derived": true}),
		_field("distance", "float", "how far the screen is, 0.5 to 30 m (the size in degrees changes with it)",
				func(m: Node) -> float: return float(m.screen_distance),
				func(m: Node, v: float) -> void: m.set_screen(m.screen_width, v, m.screen_height_offset),
				{"min": 0.5, "max": 30.0}),
		_field("height", "float", "the screen's centre above eye level, -3 to 6 m",
				func(m: Node) -> float: return float(m.screen_height_offset),
				func(m: Node, v: float) -> void: m.set_screen(m.screen_width, m.screen_distance, v),
				{"min": -3.0, "max": 6.0}),
		_field("width", "float", "the screen's width, 0.5 to 30 m",
				func(m: Node) -> float: return float(m.screen_width),
				func(m: Node, v: float) -> void: m.set_screen(v, m.screen_distance, m.screen_height_offset),
				{"min": 0.5, "max": 30.0}),
		_field("size_degrees", "float", "how wide the screen looks, %d to %d degrees, at the distance it is (sets "
				% [angle_script.MIN_ANGLE, angle_script.MAX_ANGLE] + "the width)",
				func(m: Node) -> float: return float(m.features.angle.angle()),
				func(m: Node, v: float) -> void: m.features.angle.set_angle(v),
				{"min": angle_script.MIN_ANGLE, "max": angle_script.MAX_ANGLE, "derived": true}),
		_field("curvature", "float", "0 flat to 100: the screen wraps evenly around the viewer",
				func(m: Node) -> float: return float(m.features.curve.amount) * 100.0,
				func(m: Node, v: float) -> void: m.features.curve.set_amount(v / 100.0), {"min": 0.0, "max": 100.0}),
		_field("zoom", "float", "magnifies the picture inside the screen, 1 (none) to %s, kept for this file"
				% zoom_max, func(m: Node) -> float: return float(m.features.zoom.zoom),
				func(m: Node, v: float) -> void: m.features.zoom.set_zoom(v), {"min": 1.0, "max": zoom_max}),
		_field("follow_head", "bool", "the screen follows the head slowly; false pins it where it is",
				func(m: Node) -> bool: return bool(m.features.pose.follow),
				func(m: Node, v: bool) -> void: m.features.pose.set_follow(v)),
		_field("lying_down", "bool", "the screen tilts up for watching lying down (this session only)",
				func(m: Node) -> bool: return bool(m.features.pose.lying),
				func(m: Node, v: bool) -> void: m.features.pose.set_lying(v)),
		_field("auto_crop", "bool", "crops black letterbox or pillarbox bars from the picture (turning it on reopens "
				+ "the file at its place)", func(m: Node) -> bool: return bool(m.features.auto_crop.enabled),
				func(m: Node, v: bool) -> void: m.features.auto_crop.set_enabled(v)),
		_field("grow_screen", "bool", "with auto crop: the screen grows to keep its height",
				func(m: Node) -> bool: return bool(m.features.auto_crop.grow),
				func(m: Node, v: bool) -> void: m.features.auto_crop.set_grow(v)),
	], "picture", "screen", read, {"check": func(args: Dictionary) -> String:
		if args.has("width") and args.has("size_degrees"):
			return "give width or size_degrees, not both"
		if args.has("preset") and (args.has("width") or args.has("size_degrees") or args.has("distance")
				or args.has("lying_down")):
			return "a preset sets the size, the distance and lying down itself"
		return ""})

	var horizon_max: float = preload("res://scripts/play/horizon.gd").MAX
	_register_setter(host, "set_horizon", "The Picture tab's Horizon section: levels a 180 or 360 picture shot "
			+ "tilted, kept for this file. picture_reset horizon levels it.", [
		_field("pitch", "float", "tilts the picture up (+) or down (-), -%d to %d degrees" % [horizon_max, horizon_max],
				func(m: Node) -> float: return float(m.features.horizon.pitch),
				func(m: Node, v: float) -> void: m.features.horizon.set_trim(v, m.features.horizon.roll),
				{"min": -horizon_max, "max": horizon_max}),
		_field("roll", "float", "turns the picture clockwise (+) or anticlockwise (-), -%d to %d degrees"
				% [horizon_max, horizon_max], func(m: Node) -> float: return float(m.features.horizon.roll),
				func(m: Node, v: float) -> void: m.features.horizon.set_trim(m.features.horizon.pitch, v),
				{"min": -horizon_max, "max": horizon_max}),
	], "picture", "horizon", read)

	var pc_ranges: Dictionary = preload("res://scripts/play/picture_controls.gd").RANGES
	var pc_words := {"brightness": "adds light to the whole picture", "contrast": "spreads the darks and lights apart",
			"saturation": "colour strength, 0 black and white", "gamma": "brightens (> 1) or darkens (< 1) the "
			+ "mid-tones", "lift": "raises the darkest parts in dark scenes", "sharpen": "a light sharpen, 0 off"}
	var picture_fields: Array = []
	for key: String in pc_ranges:
		var r: Array = pc_ranges[key]
		var k := key
		picture_fields.append(_field(k, "float", "%s, %s to %s (normal %s)" % [pc_words.get(k, k), r[0], r[1], r[2]],
				func(m: Node) -> float: return float(m.features.picture.values.get(k, r[2])),
				func(m: Node, v: float) -> void: m.features.picture.set_value(k, v), {"min": r[0], "max": r[1]}))
	picture_fields.append(_field("deinterlace", "string", "for interlaced video: off, bob, edge, or auto (on when "
			+ "the file is interlaced)", func(m: Node) -> String: return str(m.features.deinterlace.mode),
			func(m: Node, v: String) -> void: m.features.deinterlace.set_mode(v),
			{"enum": preload("res://scripts/play/deinterlace.gd").MODES}))
	picture_fields.append(_field("film_grain", "float", "a projector's film grain, 0 to 1",
			func(m: Node) -> float: return float(m.features.projector.grain),
			func(m: Node, v: float) -> void: m.features.projector.set_grain(v), {"min": 0.0, "max": 1.0}))
	picture_fields.append(_field("gate_weave", "float", "a projector's gentle picture wobble, 0 to 1",
			func(m: Node) -> float: return float(m.features.projector.weave),
			func(m: Node, v: float) -> void: m.features.projector.set_weave(v), {"min": 0.0, "max": 1.0}))
	_register_setter(host, "set_picture", "The Picture tab's Picture section: brightness, contrast, saturation, "
			+ "gamma, dark-scene lift and sharpen (kept per room), deinterlace, film grain and gate weave. "
			+ "picture_reset picture puts them back.", picture_fields, "picture", "picture", read)

	var hdr_ranges: Dictionary = preload("res://scripts/play/hdr_tone_map.gd").RANGES
	var hdr_field := func(name: String, key: String, words: String) -> Dictionary:
		var r: Array = hdr_ranges[key]
		return _field(name, "float", "%s, %s to %s (normal %s)" % [words, r[0], r[1], r[2]],
				func(m: Node) -> float: return float(m.features.hdr.values.get(key, r[2])),
				func(m: Node, v: float) -> void: m.features.hdr.set_value(key, v), {"min": r[0], "max": r[1]})
	_register_setter(host, "set_hdr", "The Picture tab's HDR section, for HDR files (the picture read's hdr.is_hdr): "
			+ "tone mapping on or off, exposure, knee and brightness.", [
		_field("tone_map", "bool", "maps the file's highlights into the display's range; false clips them, for "
				+ "comparison", func(m: Node) -> bool: return bool(m.features.hdr.enabled),
				func(m: Node, v: bool) -> void: m.features.hdr.set_enabled(v)),
		hdr_field.call("exposure", "exposure", "stops brighter (+) or darker (-)"),
		hdr_field.call("knee", "knee", "where the highlights start to roll off, as a fraction"),
		hdr_field.call("brightness_nits", "target_nits", "the brightness of white, nits"),
	], "picture", "HDR", read)

	var lens_script := preload("res://scripts/play/fisheye_lens.gd")
	var dual_script := preload("res://scripts/play/dual_fisheye.gd")
	_register_setter(host, "set_lens", "The Picture tab's lens settings: the fisheye lens model (fisheye mode, for "
			+ "this file) and the dual fisheye 360 camera, its lenses' field of view and the seam (dualfisheye mode, "
			+ "kept per camera).", [
		_field("fisheye_lens", "string", "the fisheye lens's model, for this file",
				func(m: Node) -> String: return str(m.features.lens.profile),
				func(m: Node, v: String) -> void: m.features.lens.set_profile(v, true),
				{"enum": Array(lens_script.PROFILES)}),
		_field("dual_camera", "string", "the dual fisheye 360 camera: camera360 (its videos), camera360_photo (its "
				+ "photos) or generic (another camera)", func(m: Node) -> String: return str(m.features.dual_fisheye.profile),
				func(m: Node, v: String) -> void: m.features.dual_fisheye.set_profile(v, true),
				{"enum": Array(dual_script.PROFILES)}),
		_field("dual_fov", "float", "both lenses' field of view, 170 to 220 degrees",
				func(m: Node) -> float: return float(m.features.dual_fisheye.fov()),
				func(m: Node, v: float) -> void: m.features.dual_fisheye.set_value("fov", v), {"min": 170.0, "max": 220.0}),
		_field("dual_seam", "float", "turns the back lens's picture sideways so the two pictures meet, -%s to %s "
				% [dual_script.SEAM_RANGE, dual_script.SEAM_RANGE] + "degrees",
				func(m: Node) -> float: return float(m.features.dual_fisheye.seam()),
				func(m: Node, v: float) -> void: m.features.dual_fisheye.set_value("seam", v),
				{"min": -dual_script.SEAM_RANGE, "max": dual_script.SEAM_RANGE}),
	], "picture", "lens", read)

	_register_setter(host, "slideshow", "The Picture tab's Slideshow: with it on, each picture shows this long and "
			+ "then the next in the folder opens.", [
		_field("on", "bool", "the slideshow on or off", func(m: Node) -> bool: return bool(m.features.slideshow.enabled),
				func(m: Node, v: bool) -> void: m.features.slideshow.set_enabled(v)),
		_field("seconds", "float", "how long each picture shows, 2 to 60 s",
				func(m: Node) -> float: return float(m.features.slideshow.seconds),
				func(m: Node, v: float) -> void: m.features.slideshow.set_seconds(v), {"min": 2.0, "max": 60.0}),
		_field("crossfade", "float", "how long one picture fades into the next, 0 (a cut) to 3 s",
				func(m: Node) -> float: return float(m.features.slideshow.crossfade),
				func(m: Node, v: float) -> void: m.features.slideshow.set_crossfade(v), {"min": 0.0, "max": 3.0}),
	], "picture", "slideshow", read)

	var pip_open := func(m: Node) -> String:
		return "" if str(m.features.pip.state) != "" else "no picture in picture is open (Files opens one in a corner)"
	var pip_script := preload("res://scripts/play/picture_in_picture.gd")
	_register_setter(host, "pip_set", "Picture in picture (a second film, silent, in a corner of the screen; the "
			+ "Picture tab's Corner film section): its size and corner.", [
		_field("size", "float", "its width as a fraction of the screen's, 0.15 to 0.5",
				func(m: Node) -> float: return float(m.features.pip.size),
				func(m: Node, v: float) -> void: m.features.pip.set_size(v), {"min": 0.15, "max": 0.5, "needs": pip_open}),
		_field("corner", "string", "which corner it sits in", func(m: Node) -> String: return str(m.features.pip.corner),
				func(m: Node, v: String) -> void: m.features.pip.set_corner(v),
				{"enum": Array(pip_script.CORNERS), "needs": pip_open}),
	], "picture", "picture in picture", read, {"assistant": "control"})
	R.register("pip_swap", func(_args: Dictionary, ctx: DevCommands.Call) -> Variant:
		var m: Node = host.main
		if pip_open.call(m) != "":
			return ctx.fail(pip_open.call(m))
		if not bool(m.features.pip.swap()):
			return ctx.fail("picture in picture can't swap now (still opening?)")
		ctx.summary = "picture in picture swapped"
		ctx.undo = func() -> void: host.main.features.pip.swap()
		return _picture_state(m)["pip"], {
		"description": "Swaps the film in the corner and the main film: the corner one plays large with its sound "
				+ "(the Corner film section's Swap).",
		"level": "control", "assistant": "control", "returns": "the picture read's pip"})
	R.register("pip_close", func(_args: Dictionary, ctx: DevCommands.Call) -> Variant:
		var m: Node = host.main
		if pip_open.call(m) != "":
			return ctx.fail(pip_open.call(m))
		m.features.pip.close()
		ctx.summary = "picture in picture closed"
		return {"closed": true}, {
		"description": "Closes the film in the corner (the Corner film section's Close corner); the main film plays "
				+ "on.",
		"level": "control", "assistant": "control", "returns": "{closed}"})

	R.register("picture_reset", func(args: Dictionary, ctx: DevCommands.Call) -> Variant:
		var m: Node = host.main
		var part: String = args["part"]
		var fields: Array = _reset_fields(part)
		var before := _snapshot(fields, m)
		var f: Node = m.features
		match part:
			"screen":
				m.reset_screen()
			"zoom":
				f.zoom.reset()
			"horizon":
				f.horizon.reset()
			"picture":
				f.picture.reset()
			"hdr":
				f.hdr.reset()
			"dual_lens":
				f.dual_fisheye.reset()
		_sync_tab(m, "picture")
		ctx.summary = "%s reset" % part.replace("_", " ")
		ctx.undo = func() -> void:
			_restore(fields, before, host.main)
			_sync_tab(host.main, "picture")
		return _picture_state(m), {
		"description": "Puts one part of the Picture tab back to its defaults: the screen's size, distance and "
				+ "height for this room, the zoom, the horizon (Level), the picture controls, HDR, or the dual fisheye "
				+ "lens.",
		"params": [{"name": "part", "type": "string", "required": true, "enum": RESET_PARTS,
				"description": "which part to reset"}],
		"level": "control", "assistant": "settings", "returns": "the picture read"})


## The setter fields a picture_reset part changes, for its undo: from the registered specs' own fields.
static func _reset_fields(part: String) -> Array:
	var keys: Dictionary = {"screen": ["set_screen", ["distance", "height", "width"]],
			"zoom": ["set_screen", ["zoom"]], "horizon": ["set_horizon", []], "picture": ["set_picture", []],
			"hdr": ["set_hdr", []], "dual_lens": ["set_lens", ["dual_fov", "dual_seam"]]}
	var k: Array = keys[part]
	var fields: Array = _fields.get(k[0], [])
	if (k[1] as Array).is_empty():
		return fields
	return fields.filter(func(f: Dictionary) -> bool: return str(f["param"]["name"]) in k[1])


static func _picture_state(m: Node) -> Dictionary:
	var f: Node = m.features
	var mode: VideoMode = m.mode
	var spherical := mode.is_spherical()
	var rule: Dictionary = f.folder_modes.rule_for(m.current_path)
	var pc := {}
	for key: String in f.picture.RANGES:
		pc[key] = _r(float(f.picture.values.get(key, f.picture.RANGES[key][2])))
	pc["deinterlace"] = str(f.deinterlace.mode)
	pc["film_grain"] = _r(float(f.projector.grain))
	pc["gate_weave"] = _r(float(f.projector.weave))
	var hdr: Node = f.hdr
	var pip: Node = f.pip
	return {
		"mode": {"id": mode.to_id(), "text": mode.describe(), "projection": PROJECTIONS[int(mode.projection)],
				"layout": LAYOUTS[int(mode.layout)], "half": mode.half, "swap": mode.swap,
				"fisheye_fov": mode.fisheye_fov, "chosen_by": m.mode_source,
				"folder_rule": {"folder": rule["folder"], "mode": rule["mode"]} if not rule.is_empty() else null},
		"stereo": {"applies": mode.layout != VideoMode.Layout.MONO, "show": EYES[int(f.two_d.eye) + 1],
				"depth": _r(float(f.depth.value)), "depth_this_file_only": bool(f.depth.has_file_value()),
				"soft_edges": float(f.edge_fade.width) > 0.0},
		"screen": {"applies": not spherical, "width": _r(m.screen_width), "distance": _r(m.screen_distance),
				"height": _r(m.screen_height_offset), "size_degrees": snappedf(float(f.angle.angle()), 0.1),
				"preset": str(f.angle.matching_preset()), "curvature": roundi(float(f.curve.amount) * 100.0),
				"zoom": _r(float(f.zoom.zoom)), "follow_head": bool(f.pose.follow), "lying_down": bool(f.pose.lying),
				"auto_crop": bool(f.auto_crop.enabled), "grow_screen": bool(f.auto_crop.grow),
				"crop": str(f.auto_crop.state().get("text", "")) if bool(f.auto_crop.enabled) else ""},
		"horizon": {"applies": spherical, "pitch": _r(float(f.horizon.pitch)), "roll": _r(float(f.horizon.roll))},
		"picture": pc,
		"hdr": {"is_hdr": bool(hdr.is_hdr()), "text": str(hdr.text()), "tone_map": bool(hdr.enabled),
				"exposure": _r(float(hdr.values.get("exposure", hdr.RANGES["exposure"][2]))),
				"knee": _r(float(hdr.values.get("knee", hdr.RANGES["knee"][2]))),
				"brightness_nits": _r(float(hdr.values.get("target_nits", hdr.RANGES["target_nits"][2])))},
		"lens": {"fisheye_applies": mode.projection == VideoMode.Proj.FISHEYE, "fisheye_lens": str(f.lens.profile),
				"dual_applies": mode.projection == VideoMode.Proj.DUAL_FISHEYE,
				"dual_camera": str(f.dual_fisheye.profile), "dual_fov": _r(float(f.dual_fisheye.fov())),
				"dual_seam": _r(float(f.dual_fisheye.seam()))},
		"slideshow": {"on": bool(f.slideshow.enabled), "seconds": float(f.slideshow.seconds),
				"crossfade": float(f.slideshow.crossfade), "is_picture": bool(f.slideshow.is_picture())},
		"pip": {"state": str(pip.state), "path": str(pip.path), "size": _r(float(pip.size)),
				"corner": str(pip.corner)} if str(pip.state) != "" else null,
	}


# --- Sound ----------------------------------------------------------------------------------------------------------

static func _register_sound(host: Node) -> void:
	DevCommands.register("sound", func(_args: Dictionary, _ctx: DevCommands.Call) -> Variant:
		return _sound_state(host.main), {
		"description": "Everything in the Sound tab but the audio tracks (tracks lists them) and the speed (playback "
				+ "has it): the volume, the A/V offset, the live delay, night mode and dialogue boost (available: "
				+ "whether this player has them), the speakers in the room, and the sound on a PC.",
		"level": "read", "assistant": "read",
		"returns": "{volume, av_offset_ms, live, live_delay, night: {available, on, strength, dialogue_boost, "
				+ "boost_applies}, speakers: {on, bass_channel, active, channels}, pc_audio}"})
	var night_ok := func(m: Node) -> String:
		return "" if bool(m.features.night.available()) else "this player has no night mode"
	_register_setter(host, "set_sound", "The Sound tab's settings: A/V offset, live delay, night mode and dialogue "
			+ "boost, and the speakers in the room. The volume is the volume command, the speed the speed command.", [
		_field("av_offset_ms", "float", "delays the picture (+) or the sound (-) to line them up, -300 to 300 ms",
				func(m: Node) -> float: return roundf(float(m.player.av_offset) * 1000.0),
				func(m: Node, v: float) -> void: m.set_av_offset(v / 1000.0), {"min": -300.0, "max": 300.0}),
		_field("environment_sound_db", "float", "the room's own sound (rain, birds, the projector) on its own bus, "
				+ "always ducked under the film: -60 (off) to 0 dB; -18 is the default",
				func(m: Node) -> float: return float(m.features.env_audio.environment_db),
				func(m: Node, v: float) -> void: m.features.env_audio.set_environment_db(v), {"min": -60.0, "max": 0.0}),
		_field("live_delay", "float", "for live streams: how far behind live to play, 0.1 to 2.5 s (a change "
				+ "reopens a live stream)", func(m: Node) -> float: return float(m.features.live.latency),
				func(m: Node, v: float) -> void: m.features.live.set_latency(v), {"min": 0.1, "max": 2.5}),
		_field("night_mode", "bool", "evens out loud and quiet parts", func(m: Node) -> bool:
				return bool(m.features.night.night), func(m: Node, v: bool) -> void: m.features.night.set_night(v),
				{"needs": night_ok}),
		_field("night_strength", "float", "how much night mode evens out, 0 to 1",
				func(m: Node) -> float: return float(m.features.night.strength),
				func(m: Node, v: float) -> void: m.features.night.set_strength(v),
				{"min": 0.0, "max": 1.0, "needs": night_ok}),
		_field("dialogue_boost", "float", "raises the centre (dialogue) channel, 0 to 12 dB; files with a centre "
				+ "channel only", func(m: Node) -> float: return float(m.features.night.boost_db),
				func(m: Node, v: float) -> void: m.features.night.set_dialogue_boost(v),
				{"min": 0.0, "max": 12.0, "needs": night_ok}),
		_field("speakers", "bool", "spatial sound: each audio channel (or a 360 video's sound field) plays from its "
				+ "place in the room, in front, behind and above, and stays put when the head turns (turning it on "
				+ "reopens the file at its place)",
				func(m: Node) -> bool: return bool(m.features.speakers.enabled),
				func(m: Node, v: bool) -> void: m.features.speakers.set_enabled(v)),
		_field("bass_channel", "bool", "with spatial sound on: the bass (LFE) channel plays too",
				func(m: Node) -> bool: return bool(m.features.speakers.lfe),
				func(m: Node, v: bool) -> void: m.features.speakers.set_lfe(v)),
		_field("output_profile", "string", "what the sound plays on: auto (the sound device decides), speakers (the "
				+ "headset's own) or headphones; each has its own HRTF set and tuning",
				func(m: Node) -> String: return str(m.features.speakers.output),
				func(m: Node, v: String) -> void: m.features.speakers.set_output(v),
				{"enum": ["auto", "speakers", "headphones"]}),
		_field("hrtf", "string", "the set of head measurements spatial sound uses for the output profile in use (sound "
				+ "lists them as speakers.hrtf_sets; sets not downloaded yet need download_hrtf first)",
				func(m: Node) -> String: return str(m.features.speakers.hrtf),
				func(m: Node, v: String) -> void: m.features.speakers.set_hrtf(v)),
		_field("room_reverb", "float", "how much of the room's reflections and reverb spatial sound adds, 0 (none) "
				+ "to 2 (twice the room's own); 1 is the room as designed",
				func(m: Node) -> float: return float(m.features.speakers.reverb),
				func(m: Node, v: float) -> void: m.features.speakers.set_reverb(v), {"min": 0.0, "max": 2.0}),
	], "sound", "sound", func(m: Node) -> Dictionary: return _sound_state(m), {"check": func(args: Dictionary) -> String:
		var sp: Node = host.main.features.speakers
		if args.has("hrtf") and sp.hrtf_file(str(args["hrtf"])) == "":
			return "no HRTF set %s here (sound lists them as speakers.hrtf_sets; download_hrtf fetches one)" % args["hrtf"]
		if args.has("output_profile") and not str(args["output_profile"]) in ["auto", "speakers", "headphones"]:
			return "output_profile is auto, speakers or headphones"
		return ""})
	DevCommands.register("download_hrtf", func(args: Dictionary, ctx: DevCommands.Call) -> Variant:
		var sp: Node = host.main.features.speakers
		var id := str(args["id"])
		var error: String = sp.download_hrtf(id)
		if error != "":
			return ctx.fail(error)
		ctx.summary = "fetching HRTF set %s" % id
		return {"fetching": id}, {
		"description": "Fetches an HRTF set that is not bundled (sound lists them as speakers.hrtf_sets with their "
				+ "licences: tell the user the licence first), converts it and keeps it; set_sound hrtf then uses it. "
				+ "Takes a few seconds; sound shows it as downloaded when done.",
		"level": "control", "assistant": "settings",
		"params": [{"name": "id", "type": "string", "required": true,
				"description": "the set's id, one of speakers.hrtf_sets whose bundled is false"}],
		"returns": "{fetching}"})
	DevCommands.register("spatial_tune", func(args: Dictionary, ctx: DevCommands.Call) -> Variant:
		var t: Node = host.main.features.spatial_tune
		var action := str(args["action"])
		match action:
			"start":
				if not bool(host.main.features.speakers.available()):
					return ctx.fail("this player has no spatial sound")
				t.start()
				ctx.summary = "tune spatial sound"
			"cancel":
				t.cancel()
				ctx.summary = "spatial sound tuning cancelled"
			"a", "b", "same", "again":
				var error: String = t.choose(action)
				if error != "":
					return ctx.fail(error)
				ctx.summary = "spatial sound tuning: %s" % action
		return t.status(), {
		"description": "Tune spatial sound in the headset: a sound circles the viewer and passes overhead, played "
				+ "twice, as A and then B, through two versions of the spatial sound; the viewer picks A or B (or "
				+ "can't tell) on a card with the laser, about 9 picks in about 2 minutes. The profile's current HRTF "
				+ "set starts as the champion, every other set challenges it, then head size and ear shape steps. "
				+ "The menu button cancels with nothing changed. The result is kept for the output in use (sound "
				+ "shows it as speakers.tuning). action: start, cancel, status, or a pick for the viewer (a, b, same, "
				+ "again: only when they ask).",
		"params": [{"name": "action", "type": "string", "default": "start",
				"enum": ["start", "cancel", "status", "a", "b", "same", "again"],
				"description": "start (the default), cancel (nothing changes), status, or a pick: a, b, same (can't "
						+ "tell), again (hear both again)"}],
		"level": "control", "assistant": "control",
		"returns": "{running, stage, pick, picks, playing, heard_both, ready, skips, lead_ms}"})


static func _sound_state(m: Node) -> Dictionary:
	var f: Node = m.features
	var night: Node = f.night
	var sp: Node = f.speakers
	var pc := PCAudio.instance()
	return {
		"volume": m.volume,
		"av_offset_ms": roundf(float(m.player.av_offset) * 1000.0),
		"environment_sound_db": float(f.env_audio.environment_db),
		"live": bool(f.live.live),
		"live_delay": float(f.live.latency),
		"night": {"available": bool(night.available()), "on": bool(night.night), "strength": float(night.strength),
				"dialogue_boost": float(night.boost_db), "boost_applies": bool(night.boost_applies())},
		"speakers": {"on": bool(sp.enabled), "bass_channel": bool(sp.lfe), "active": bool(sp.active),
				"available": bool(sp.available()), "channels": Array(sp.channels()), "hrtf": str(sp.hrtf),
				"room_reverb": float(sp.reverb), "output_profile": str(sp.output), "profile_in_use": str(sp.profile()),
				"hrtf_sets": sp.hrtf_sets(), "downloading": str(sp.downloading),
				"tuning": sp.profile_settings().tuning, "tuning_running": bool(f.spatial_tune.running)},
		"pc_audio": pc.status() if pc != null and not pc.is_queued_for_deletion() else {"on": false},
	}


# --- Subtitles ------------------------------------------------------------------------------------------------------

static func _register_subtitles(host: Node) -> void:
	DevCommands.register("subtitle_settings", func(_args: Dictionary, _ctx: DevCommands.Call) -> Variant:
		return _subtitle_state(host.main), {
		"description": "The Subtitles tab but its track list (tracks has it): on or off and the track, the second "
				+ "track and its choices, the look (size, position, offset, nearer, background), the delay, and the "
				+ "subtitle files found next to the video.",
		"level": "read", "assistant": "read",
		"returns": "{on, track, second: {index, options: [{index, title, language}]}, size, position, offset, "
				+ "nearer, background, delay, find_files, files, replaying}"})
	var display := func(m: Node) -> Node: return m.features.subtitles.display
	_register_setter(host, "set_subtitle_options", "The Subtitles tab's look and timing: size, below or inside the "
			+ "picture, offset, nearer, background and delay, and finding subtitle files next to the video.", [
		_field("size", "float", "the text's size, 0.5 to 3 times normal",
				func(m: Node) -> float: return float(display.call(m).scale_factor),
				func(m: Node, v: float) -> void: display.call(m).set_scale_factor(v), {"min": 0.5, "max": 3.0}),
		_field("position", "string", "below the picture, or inside it at the bottom",
				func(m: Node) -> String: return str(display.call(m).position_mode),
				func(m: Node, v: String) -> void: display.call(m).set_position_mode(v), {"enum": ["below", "inside"]}),
		_field("offset", "float", "moves the text up (+) or down (-), -0.5 to 0.5 of the picture's height",
				func(m: Node) -> float: return float(display.call(m).offset),
				func(m: Node, v: float) -> void: display.call(m).set_offset(v), {"min": -0.5, "max": 0.5}),
		_field("nearer", "float", "brings the text toward the eyes, 0 to 2 m (easier to read on 3D)",
				func(m: Node) -> float: return float(display.call(m).depth),
				func(m: Node, v: float) -> void: display.call(m).set_depth(v), {"min": 0.0, "max": 2.0}),
		_field("background", "float", "a dark box behind the text, 0 (none) to 1 (opaque)",
				func(m: Node) -> float: return float(display.call(m).background),
				func(m: Node, v: float) -> void: display.call(m).set_background(v), {"min": 0.0, "max": 1.0}),
		_field("delay", "float", "shows the subtitles later (+) or earlier (-), -5 to 5 s, kept for this file and "
				+ "track; 0 is the tab's Reset delay", func(m: Node) -> float: return float(m.features.sub_delay.delay),
				func(m: Node, v: float) -> void: m.features.sub_delay.set_delay(v), {"min": -5.0, "max": 5.0}),
		_field("find_files", "bool", "loads subtitle files next to the video as tracks",
				func(m: Node) -> bool: return bool(m.features.sub_files.enabled),
				func(m: Node, v: bool) -> void: m.features.sub_files.set_enabled(v)),
	], "subtitles", "subtitles", func(m: Node) -> Dictionary: return _subtitle_state(m))
	DevCommands.register("second_subtitles", func(args: Dictionary, ctx: DevCommands.Call) -> Variant:
		var m: Node = host.main
		var subs: Node = m.features.subtitles
		var index: int = args["index"]
		var options: Array = subs.secondary_tracks()
		if index >= 0 and not options.any(func(t: Dictionary) -> bool: return int(t.get("index", -1)) == index):
			return ctx.fail("no second track %d (subtitle_settings lists second.options)" % index if not options.is_empty()
					else "a second track needs a subtitle file next to the video")
		var old: int = subs.secondary
		subs.select_secondary(index)
		ctx.summary = "second subtitles %s" % ("off" if index < 0 else str(index))
		ctx.undo = func() -> void: host.main.features.subtitles.select_secondary(old)
		return _subtitle_state(m)["second"], {
		"description": "A second subtitle track above the first (the Subtitles tab's Second track), from a subtitle "
				+ "file next to the video; -1 turns it off.",
		"params": [{"name": "index", "type": "int", "required": true,
				"description": "a track index from subtitle_settings second.options, or -1 for none"}],
		"level": "control", "assistant": "control", "returns": "{index, options}"})


static func _subtitle_state(m: Node) -> Dictionary:
	var f: Node = m.features
	var subs: Node = f.subtitles
	var d: Node = subs.display
	var options: Array = []
	for t: Dictionary in subs.secondary_tracks():
		options.append({"index": int(t.get("index", 0)), "title": str(t.get("title", "")),
				"language": str(t.get("language", ""))})
	var files: Array = []
	for x: Dictionary in f.sub_files.loaded:
		files.append(str(x.get("path", "")).get_file())
	return {
		"on": bool(subs.enabled), "track": int(subs.track),
		"second": {"index": int(subs.secondary), "options": options},
		"size": _r(float(d.scale_factor)), "position": str(d.position_mode), "offset": _r(float(d.offset)),
		"nearer": _r(float(d.depth)), "background": _r(float(d.background)), "delay": _r(float(f.sub_delay.delay)),
		"find_files": bool(f.sub_files.enabled), "files": files, "replaying": bool(f.catch_up.active),
	}
