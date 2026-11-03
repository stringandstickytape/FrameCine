extends SceneTree

## The playback area's commands for the assistant (docs/dev/assistant-coverage/playback.md): every command of the
## transport and the Picture, Sound and Subtitles tabs is tagged for the assistant with a description on every param;
## each new one runs through DevCommands.execute against the real main scene, and its effect, its read-back, the tab's
## widget and its undo are checked. Settings are read-only; a test pattern plays.
## godot --headless --xr-mode off --path app --script res://tests/test_assistant_coverage_playback.gd

const DevCommands := preload("res://scripts/dev/dev_commands.gd")
const CommandHost := preload("res://scripts/dev/command_host.gd")
const VideoMode := preload("res://scripts/video_mode.gd")
const W := preload("res://ui/pane_widgets.gd")

const LEVELS := ["read", "card", "control", "room", "settings", "files", "apps"]
## Every command of this area: new ones, and the registry's own that this area tags.
const COMMANDS := ["playback", "trick_play", "frame_step", "loop", "loop_clear", "replay", "speed", "info_overlay",
		"screenshot_frame", "av_calibrate", "picture", "set_mode", "mode_auto", "folder_rule", "set_3d", "set_screen",
		"set_horizon", "set_picture", "set_hdr", "set_lens", "slideshow", "pip_set", "pip_swap", "pip_close",
		"picture_reset", "sound", "set_sound", "subtitle_settings", "set_subtitle_options", "second_subtitles",
		"play", "pause", "seek", "next", "previous", "chapter", "chapters", "subtitles", "find_line", "script_lines",
		"jump_to_line", "pc_audio", "pc_audio_status"]
const STUB := "stub://flat_mono"

var _failures := 0
var _checks := 0
var main: Node3D


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	current_scene = main  # the shared command handlers find the app as the current scene
	_run.call_deferred()


func _run() -> void:
	CommandHost.ensure(self)
	await _frames(5)
	main.open_path(STUB)
	await _frames(10)
	_tags()
	await _transport()
	await _picture()
	await _sound()
	await _subtitles()
	await _tagged()
	print("test_assistant_coverage_playback: %d checks, %s" % [_checks, "all passed" if _failures == 0
			else "%d FAILED" % _failures])
	quit(_failures)


## Every command is there, tagged with a consumer level, described, and every param described.
func _tags() -> void:
	for c: String in COMMANDS:
		if not DevCommands.has_command(c):
			_check("%s is registered" % c, false)
			continue
		var spec := DevCommands.get_spec(c)
		_check("%s: tagged with a consumer level (%s)" % [c, spec.get("assistant")], spec.get("assistant") in LEVELS)
		_check("%s: never code level" % c, spec.get("level") != "code")
		_check("%s: a description" % c, str(spec.get("description", "")).length() > 10)
		var bare: Array = (spec["params"] as Array).filter(func(p: Dictionary) -> bool:
			return str(p.get("description", "")).strip_edges() == "")
		_check("%s: every param described %s" % [c, bare.map(func(p: Dictionary) -> String: return p["name"])],
				bare.is_empty())
		if spec.get("assistant") == "read":
			_check("%s: a read changes nothing (level read)" % c, spec.get("level") == "read")


func _transport() -> void:
	var r := await _run_cmd("playback", {})
	_check("playback: reads the speed and the loop", r["ok"] and r["result"].has("speeds")
			and r["result"]["loop"]["active"] == false)

	r = await _run_cmd("speed", {"speed": 1.5})
	_check("speed 1.5: the player runs at 1.5x", r["ok"] and is_equal_approx(main.features.speed.speed, 1.5))
	_check("speed: the toast says it", str(r["call"].summary).contains("1.5"))
	_check("speed: read back", is_equal_approx(float((await _run_cmd("playback", {}))["result"]["speed"]), 1.5))
	_check("speed: the Sound tab shows it", _pane() == null
			or _choice(_pane().sound._speed) ==(main.features.speed.STEPS as Array).find(1.5))
	r["call"].undo.call()
	_check("speed: undo back to 1x", is_equal_approx(main.features.speed.speed, 1.0))
	_check("speed 3 refused (not a step)", not (await _run_cmd("speed", {"speed": 3.0}))["ok"])

	r = await _run_cmd("trick_play", {"speed": 4.0})
	var trick_ok: bool = main.features.trick.available()
	_check("trick_play 4: scans when the source can, else says why", r["ok"] == trick_ok
			and (trick_ok or str(r["error"]).contains("can't scan")))
	_check("trick_play 0: stops", (await _run_cmd("trick_play", {"speed": 0.0}))["ok"]
			and main.features.trick.speed == 0.0)
	_check("trick_play 5 refused", not (await _run_cmd("trick_play", {"speed": 5.0}))["ok"])

	main.player.seek(100.0)
	main.player.play()
	await _frames(2)
	var before: float = main.player.get_position()
	r = await _run_cmd("frame_step", {"frames": 1})
	_check("frame_step 1: paused, one frame on", r["ok"] and not main.player.is_playing()
			and main.player.get_position() > before)
	r["call"].undo.call()
	_check("frame_step: undo goes back", absf(main.player.get_position() - before) < 0.05)
	_check("frame_step 0 refused", not (await _run_cmd("frame_step", {"frames": 0}))["ok"])

	r = await _run_cmd("loop", {"a": 10.0, "b": 20.0})
	_check("loop 10-20: active", r["ok"] and main.features.step_loop.active
			and is_equal_approx(main.features.step_loop.a, 10.0) and is_equal_approx(main.features.step_loop.b, 20.0))
	_check("loop: read back", (await _run_cmd("playback", {}))["result"]["loop"]["active"] == true)
	r = await _run_cmd("loop_clear", {})
	_check("loop_clear: no loop", r["ok"] and not main.features.step_loop.active)
	r["call"].undo.call()
	_check("loop_clear: undo puts the loop back", main.features.step_loop.active)
	main.features.step_loop.clear()
	_check("loop past the end refused", not (await _run_cmd("loop", {"a": 10.0, "b": 9000.0}))["ok"])

	main.player.seek(100.0)
	await _frames(2)
	r = await _run_cmd("replay", {})
	_check("replay: 10 s back with subtitles forced", r["ok"] and main.features.catch_up.active
			and main.player.get_position() < 95.0)
	_check("replay: read back", (await _run_cmd("playback", {}))["result"]["replaying"] == true)
	main.features.catch_up.cancel()

	var overlay: bool = main.overlay_on
	r = await _run_cmd("info_overlay", {"on": not overlay})
	_check("info_overlay: toggled", r["ok"] and main.overlay_on == not overlay)
	_check("info_overlay: read back", (await _run_cmd("playback", {}))["result"]["overlay"] == not overlay)
	r["call"].undo.call()
	_check("info_overlay: undo", main.overlay_on == overlay)

	# The screenshot renders each eye through a viewport, which never draws without a renderer.
	if DisplayServer.get_name() == "headless":
		print("SKIP screenshot_frame (headless)")
	else:
		r = await _run_cmd("screenshot_frame", {})
		_check("screenshot_frame: a path, or why not", (r["ok"] and str(r["result"]["path"]) != "")
				or str(r.get("error", "")).begins_with("no screenshot"))
		if r["ok"]:
			DirAccess.remove_absolute(str(r["result"]["path"]))

	r = await _run_cmd("av_calibrate", {})
	await _frames(5)
	_check("av_calibrate: the calibration card opens", r["ok"] and main.current_path == "lab://av_sync")
	r["call"].undo.call()
	await _frames(10)
	_check("av_calibrate: undo opens the film again", main.current_path == STUB)


func _picture() -> void:
	var f: Node = main.features
	var r := await _run_cmd("picture", {})
	_check("picture: reads every section", r["ok"] and (r["result"] as Dictionary).has_all(["mode", "stereo",
			"screen", "horizon", "picture", "hdr", "lens", "slideshow", "pip"]))

	r = await _run_cmd("set_mode", {"layout": "sbs", "half": true})
	_check("set_mode sbs half: the mode", r["ok"] and main.mode.layout == VideoMode.Layout.SBS and main.mode.half)
	_check("set_mode: read back", (await _run_cmd("picture", {}))["result"]["mode"]["layout"] == "sbs")
	_check("set_mode: the toast", str(r["call"].summary).begins_with("mode"))
	_check("set_mode: the Picture tab's diagram", _pane() == null
			or _pane().picture._layout_buttons[int(VideoMode.Layout.SBS)].button_pressed)
	r["call"].undo.call()
	_check("set_mode: undo", main.mode.layout == VideoMode.Layout.MONO)
	_check("set_mode with nothing refused", not (await _run_cmd("set_mode", {}))["ok"])
	_check("set_mode fisheye_fov 300 refused", not (await _run_cmd("set_mode", {"fisheye_fov": 300.0}))["ok"])
	_check("set_mode projection cube refused", not (await _run_cmd("set_mode", {"projection": "cube"}))["ok"])
	await _run_cmd("set_mode", {"projection": "360"})
	r = await _run_cmd("mode_auto", {})
	_check("mode_auto: back to the guess", r["ok"] and main.mode_source in ["auto", "metadata"]
			and main.mode.projection == VideoMode.Proj.FLAT)
	r = await _run_cmd("folder_rule", {"on": true})
	_check("folder_rule on a test pattern refused (no folder)", not r["ok"])

	r = await _run_cmd("set_3d", {"show": "left", "depth": 0.01, "soft_edges": true})
	_check("set_3d: left eye, depth, soft edges", r["ok"] and f.two_d.eye == 0
			and is_equal_approx(f.depth.value, 0.01) and f.edge_fade.width > 0.0)
	var st: Dictionary = r["result"]["stereo"]
	_check("set_3d: read back", st["show"] == "left" and is_equal_approx(st["depth"], 0.01) and st["soft_edges"])
	_check("set_3d: the Picture tab's depth slider", _pane() == null
			or is_equal_approx(W.slider_of(_pane().picture._depth_row).value, 0.01))
	r["call"].undo.call()
	_check("set_3d: undo", f.two_d.eye == -1 and is_equal_approx(f.depth.value, 0.0) and f.edge_fade.width == 0.0)
	_check("set_3d depth 0.5 refused", not (await _run_cmd("set_3d", {"depth": 0.5}))["ok"])

	var width: float = main.screen_width
	var distance: float = main.screen_distance
	r = await _run_cmd("set_screen", {"width": 5.0, "distance": 4.0, "curvature": 50.0})
	_check("set_screen: width, distance, curvature", r["ok"] and is_equal_approx(main.screen_width, 5.0)
			and is_equal_approx(main.screen_distance, 4.0) and is_equal_approx(f.curve.amount, 0.5))
	_check("set_screen: read back", is_equal_approx(r["result"]["screen"]["width"], 5.0)
			and r["result"]["screen"]["curvature"] == 50)
	_check("set_screen: the Picture tab's size slider", _pane() == null
			or is_equal_approx(W.slider_of(_pane().picture._rows["width"]).value, 5.0))
	r["call"].undo.call()
	_check("set_screen: undo", is_equal_approx(main.screen_width, width)
			and is_equal_approx(main.screen_distance, distance) and f.curve.amount == 0.0)
	r = await _run_cmd("set_screen", {"size_degrees": 40.0})
	_check("set_screen size_degrees 40: the width follows", r["ok"] and absf(f.angle.angle() - 40.0) < 0.5)
	r["call"].undo.call()
	r = await _run_cmd("set_screen", {"preset": "living_room"})
	_check("set_screen preset living_room", r["ok"] and is_equal_approx(main.screen_distance, 3.2)
			and r["result"]["screen"]["preset"] == "living_room")
	r["call"].undo.call()
	_check("set_screen preset: undo", is_equal_approx(main.screen_distance, distance))
	_check("set_screen width and size_degrees refused",
			not (await _run_cmd("set_screen", {"width": 3.0, "size_degrees": 30.0}))["ok"])
	_check("set_screen distance 100 refused", not (await _run_cmd("set_screen", {"distance": 100.0}))["ok"])
	r = await _run_cmd("set_screen", {"zoom": 2.0, "follow_head": true})
	_check("set_screen zoom and follow head", r["ok"] and is_equal_approx(f.zoom.zoom, 2.0) and f.pose.follow)
	r["call"].undo.call()
	_check("set_screen zoom and follow: undo", is_equal_approx(f.zoom.zoom, 1.0) and not f.pose.follow)

	r = await _run_cmd("set_horizon", {"pitch": 5.0, "roll": -2.0})
	_check("set_horizon", r["ok"] and is_equal_approx(f.horizon.pitch, 5.0) and is_equal_approx(f.horizon.roll, -2.0))
	_check("set_horizon: read back", is_equal_approx(r["result"]["horizon"]["pitch"], 5.0))
	r["call"].undo.call()
	_check("set_horizon: undo", f.horizon.pitch == 0.0 and f.horizon.roll == 0.0)

	r = await _run_cmd("set_picture", {"brightness": 0.1, "saturation": 1.5, "deinterlace": "bob", "film_grain": 0.4})
	_check("set_picture", r["ok"] and is_equal_approx(float(f.picture.values["brightness"]), 0.1)
			and f.deinterlace.mode == "bob" and is_equal_approx(f.projector.grain, 0.4))
	_check("set_picture: read back", is_equal_approx(r["result"]["picture"]["saturation"], 1.5))
	_check("set_picture: the Picture tab's slider", _pane() == null
			or is_equal_approx(W.slider_of(_pane().picture._rows["pc_brightness"]).value, 0.1))
	var reset := await _run_cmd("picture_reset", {"part": "picture"})
	_check("picture_reset picture", reset["ok"] and f.picture.is_default())
	reset["call"].undo.call()
	_check("picture_reset: undo puts the values back", is_equal_approx(float(f.picture.values["brightness"]), 0.1))
	r["call"].undo.call()
	_check("set_picture: undo", f.picture.is_default() and f.deinterlace.mode == "off" and f.projector.grain == 0.0)
	_check("set_picture contrast 9 refused", not (await _run_cmd("set_picture", {"contrast": 9.0}))["ok"])

	r = await _run_cmd("set_hdr", {"exposure": 1.0, "tone_map": false})
	_check("set_hdr", r["ok"] and is_equal_approx(float(f.hdr.values["exposure"]), 1.0) and not f.hdr.enabled)
	_check("set_hdr: read back", is_equal_approx(r["result"]["hdr"]["exposure"], 1.0))
	r["call"].undo.call()
	_check("set_hdr: undo", f.hdr.enabled)

	r = await _run_cmd("set_lens", {"fisheye_lens": "equisolid", "dual_fov": 200.0})
	_check("set_lens", r["ok"] and f.lens.profile == "equisolid" and is_equal_approx(f.dual_fisheye.fov(), 200.0))
	_check("set_lens: read back", r["result"]["lens"]["fisheye_lens"] == "equisolid")
	r["call"].undo.call()
	_check("set_lens: undo", f.lens.profile != "equisolid")

	r = await _run_cmd("slideshow", {"seconds": 12.0, "crossfade": 0.5})
	_check("slideshow", r["ok"] and is_equal_approx(f.slideshow.seconds, 12.0)
			and is_equal_approx(r["result"]["slideshow"]["crossfade"], 0.5))
	r["call"].undo.call()

	for c: String in ["pip_set", "pip_swap", "pip_close"]:
		var args := {"size": 0.3} if c == "pip_set" else {}
		r = await _run_cmd(c, args)
		_check("%s with no picture in picture refused" % c, not r["ok"] and str(r["error"]).contains("picture in picture"))
	_check("picture_reset part refused when unknown", not (await _run_cmd("picture_reset", {"part": "all"}))["ok"])
	r = await _run_cmd("set_screen", {"width": 6.0})
	reset = await _run_cmd("picture_reset", {"part": "screen"})
	_check("picture_reset screen: the room's size", reset["ok"] and not is_equal_approx(main.screen_width, 6.0))
	reset["call"].undo.call()
	_check("picture_reset screen: undo", is_equal_approx(main.screen_width, 6.0))
	r["call"].undo.call()


func _sound() -> void:
	var f: Node = main.features
	var r := await _run_cmd("sound", {})
	_check("sound: reads the tab", r["ok"] and (r["result"] as Dictionary).has_all(["volume", "av_offset_ms",
			"live_delay", "night", "speakers", "pc_audio"]))
	r = await _run_cmd("set_sound", {"av_offset_ms": 100.0, "live_delay": 1.0, "bass_channel": true})
	_check("set_sound: offset, live delay, bass", r["ok"] and is_equal_approx(main.player.av_offset, 0.1)
			and is_equal_approx(f.live.latency, 1.0) and f.speakers.lfe)
	_check("set_sound: read back", is_equal_approx(r["result"]["av_offset_ms"], 100.0))
	_check("set_sound: the Sound tab's offset slider", _pane() == null
			or is_equal_approx(W.slider_of(_pane().sound._offset).value, 100.0))
	r["call"].undo.call()
	_check("set_sound: undo", is_equal_approx(main.player.av_offset, 0.0) and not f.speakers.lfe
			and is_equal_approx(f.live.latency, f.live.DEFAULT_LATENCY))
	_check("set_sound av_offset_ms 900 refused", not (await _run_cmd("set_sound", {"av_offset_ms": 900.0}))["ok"])
	r = await _run_cmd("set_sound", {"night_mode": true})
	if f.night.available():
		_check("set_sound night_mode", r["ok"] and f.night.night)
		r["call"].undo.call()
	else:
		_check("set_sound night_mode refused where the player has none", not r["ok"]
				and str(r["error"]).contains("night"))


func _subtitles() -> void:
	var f: Node = main.features
	var d: Node = f.subtitles.display
	var r := await _run_cmd("subtitle_settings", {})
	_check("subtitle_settings: reads the tab", r["ok"] and (r["result"] as Dictionary).has_all(["on", "second",
			"size", "position", "offset", "nearer", "background", "delay", "find_files"]))
	var size: float = d.scale_factor
	r = await _run_cmd("set_subtitle_options", {"size": 2.0, "position": "inside", "nearer": 0.5, "delay": 1.5})
	_check("set_subtitle_options", r["ok"] and is_equal_approx(d.scale_factor, 2.0) and d.position_mode == "inside"
			and is_equal_approx(d.depth, 0.5) and is_equal_approx(f.sub_delay.delay, 1.5))
	_check("set_subtitle_options: read back", is_equal_approx(r["result"]["size"], 2.0)
			and r["result"]["position"] == "inside")
	_check("set_subtitle_options: the Subtitles tab's size slider", _pane() == null
			or is_equal_approx(W.slider_of(_pane().subtitles._size).value, 2.0))
	r["call"].undo.call()
	_check("set_subtitle_options: undo", is_equal_approx(d.scale_factor, size) and d.position_mode == "below"
			and is_equal_approx(f.sub_delay.delay, 0.0))
	_check("set_subtitle_options position top refused",
			not (await _run_cmd("set_subtitle_options", {"position": "top"}))["ok"])
	r = await _run_cmd("second_subtitles", {"index": 3})
	_check("second_subtitles 3 refused without a subtitle file", not r["ok"])
	r = await _run_cmd("second_subtitles", {"index": -1})
	_check("second_subtitles -1: off", r["ok"] and f.subtitles.secondary == -1)


## The registry's own commands that this area tags still work as before.
func _tagged() -> void:
	var r := await _run_cmd("seek", {"seconds": 30.0})
	_check("seek 30", r["ok"] and absf(main.player.get_position() - 30.0) < 0.5)
	r = await _run_cmd("seek", {"seconds": -10.0, "relative": true})
	_check("seek -10 relative (the pane's -10 s)", r["ok"] and absf(main.player.get_position() - 20.0) < 0.5)
	_check("pause", (await _run_cmd("pause", {}))["ok"] and not main.player.is_playing())
	_check("play", (await _run_cmd("play", {}))["ok"] and main.player.is_playing())
	r = await _run_cmd("chapters", {})
	_check("chapters: the list and the current one", r["ok"] and (r["result"] as Dictionary).has_all(["count",
			"current", "list"]))


func _run_cmd(command: String, args: Dictionary) -> Dictionary:
	var r: Dictionary = await DevCommands.execute(command, args, false)
	await _frames(2)
	return r


## The pane (ui/pane_ui.gd), or null when this run has no menu layer.
func _pane() -> Object:
	var layer: Object = main.get("ui")
	return layer.get("ui") if layer != null else null


## The pressed button's index in a row of choices (pane_widgets.gd), or -1.
static func _choice(row: Container) -> int:
	var buttons := row.get_children().filter(func(c: Node) -> bool: return c is Button)
	for i in buttons.size():
		if (buttons[i] as Button).button_pressed:
			return i
	return -1


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL ", what)
	else:
		print("PASS ", what)
