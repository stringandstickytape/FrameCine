extends RefCounted

## The System tab's viewer settings as commands (ui/system_tab.gd; docs/dev/assistant-coverage/room-system.md): the
## panel's layout, accessibility, foveation, the controllers (haptic ticks, jog wheel, seek bar pictures, zoom lens) and the
## calibration cards. Each handler calls what the tab's control calls, then syncs the tab. Registered by
## command_host.gd; "assistant" in a spec is the consumer level that reaches it.
##
## Never here: the assistant's own switches and its pairing (ui/assistant_row.gd), the phone remote and file sharing
## (they open a server with its own pairing), and the dev tools. The hardware video row is read-only: its status is
## hw_video.gd's hwvideo_status. A change command takes only what it changes: a parameter left out stays as it is.

const DevCommands := preload("res://scripts/dev/dev_commands.gd")
const TestLab := preload("res://scripts/dev/test_lab.gd")

## [pane] layout keys the tab's Panel section sets; world_locked is "Follow my head" turned round.
const LAYOUT_KEYS := ["scale", "distance", "recentre_hold", "world_locked"]
const EYES := ["left", "right"]
## main.gd's FOVEATION_LEVELS.
const FOVEATION := ["off", "low", "medium", "high"]

## scripts/dev/command_host.gd
var host: Node


func _main() -> Node:
	return host.main if host != null and is_instance_valid(host.main) else null


func register_all() -> void:
	var R := DevCommands
	R.register("system_settings", _cmd_system_settings, {
		"description": "The System tab's viewer settings: the panel's layout, accessibility, foveation, the controllers "
				+ "and the app's version.",
		"returns": "{panel, accessibility, foveation, haptics, jog_wheel, seek_bar_pictures, zoom_lens, version}",
		"assistant": "read"})
	R.register("panel_layout", _cmd_panel_layout, {
		"description": "The menu panel's size and distance, how long the menu button is held to recentre it, and "
				+ "whether it follows the head.",
		"params": [{"name": "size", "type": "float",
				"description": "The panel's size, 0.5 to 3 (1 is 24 cm wide)."},
				{"name": "distance", "type": "float", "description": "How far away it opens, 0.4 to 2 metres."},
				{"name": "recentre_hold", "type": "float",
				"description": "How long the menu button is held to recentre the panel, 0.3 to 1.5 seconds."},
				{"name": "follow_head", "type": "bool",
				"description": "The panel follows the head (true) or stays where it was put (false)."}],
		"level": "change", "returns": "the panel's layout", "assistant": "settings"})
	R.register("reset_panel_layout", _cmd_reset_layout, {
		"description": "Puts the panel's layout back as it came: size, distance, hold, fixed in place, right-handed, "
				+ "normal size; the panel opens in front.",
		"level": "change", "returns": "the panel's layout", "assistant": "settings"})
	R.register("accessibility", _cmd_accessibility, {
		"description": "Accessibility: a larger panel, the left hand as the pointer, one eye's picture for 3D, and "
				+ "subtitles on for every file.",
		"params": [{"name": "larger_panel", "type": "float",
				"description": "The panel and its text larger, 1 to 2 times."},
				{"name": "left_handed", "type": "bool",
				"description": "The left controller points at the panel (true) or the right one (false)."},
				{"name": "one_eye_3d", "type": "bool",
				"description": "Shows one eye's picture to both eyes for every 3D file (true) or 3D as made (false)."},
				{"name": "eye", "type": "string", "enum": EYES, "description": "The eye one_eye_3d uses: left or right."},
				{"name": "subtitles_always", "type": "bool",
				"description": "Every file opens with subtitles on (true) or as the last file had them (false)."}],
		"level": "change", "returns": "the accessibility settings", "assistant": "settings"})
	R.register("foveation", _cmd_foveation, {
		"description": "Foveation: the headset draws the edges of the view in less detail, where the eyes don't look, "
				+ "to save GPU time. Applies at once.",
		"params": [{"name": "level", "type": "string", "enum": FOVEATION,
				"description": "off, low (can't be seen; the default), medium, or high (saves a little more; can look "
				+ "blocky at the edges)."},
				{"name": "sharp_panel", "type": "bool",
				"description": "Foveation off while the menu panel or the agent pane shows, so their text stays sharp "
				+ "(true, the default) or not (false)."}],
		"level": "change", "returns": "{level, sharp_panel, available}", "assistant": "settings"})
	R.register("haptics", _cmd_haptics, {
		"description": "The controllers' haptic ticks (on the panel's controls and while seeking).",
		"params": [{"name": "on", "type": "bool", "description": "Turns the ticks on (true) or off (false)."},
				{"name": "strength", "type": "float", "description": "How strong a tick is, 0 to 1."}],
		"level": "change", "returns": "{on, strength}", "assistant": "settings"})
	R.register("jog_wheel", _cmd_jog, {
		"description": "The jog wheel: circling a thumbstick round its rim scrubs through the film.",
		"params": [{"name": "on", "type": "bool", "description": "Turns the jog wheel on (true) or off (false)."},
				{"name": "seconds_per_turn", "type": "float",
				"description": "How far one turn goes, 10 to 600 seconds of the film."}],
		"level": "change", "returns": "{on, seconds_per_turn}", "assistant": "settings"})
	R.register("seek_bar_pictures", _cmd_thumbs, {
		"description": "Pictures of the film over the seek bar while pointing at it (a second decoder: about 150 MB "
				+ "of memory at 2160p).",
		"params": [{"name": "on", "type": "bool", "required": true,
				"description": "Shows the pictures (true) or not (false)."}],
		"level": "change", "returns": "{on}", "assistant": "settings"})
	R.register("zoom_lens", _cmd_zoom_lens, {
		"description": "The zoom lens in 180 and 360 films: hold the grip and pull the trigger for a magnifier.",
		"params": [{"name": "on", "type": "bool", "description": "Turns the zoom lens on (true) or off (false)."},
				{"name": "magnification", "type": "float", "description": "How much it magnifies, 1.5 to 8 times."}],
		"level": "change", "returns": "{on, magnification}", "assistant": "settings"})
	var cards: Array = []
	for c: Dictionary in TestLab.cards():
		cards.append(str(c["path"]).get_slice("://", 1))
	R.register("open_test_card", _cmd_test_card, {
		"description": "Opens one of the test lab's calibration cards on the screen (the System tab's Calibration "
				+ "cards; lab_cards describes each).",
		"params": [{"name": "card", "type": "string", "required": true, "enum": cards,
				"description": "The card's name, as lab_cards lists it without lab://."}],
		"level": "control", "returns": "{opened}", "assistant": "control"})


# --- Reads -------------------------------------------------------------------------------------------------------

func _cmd_system_settings(_args: Dictionary, _ctx: DevCommands.Call) -> Variant:
	return system_settings(_main())


static func system_settings(m: Node) -> Dictionary:
	var f: Node = m.features
	return {
		"panel": _layout(m),
		"accessibility": _access(m),
		"foveation": _foveation(m),
		"haptics": {"on": bool(f.haptics.enabled), "strength": snappedf(float(f.haptics.strength), 0.01)},
		"jog_wheel": {"on": bool(f.jog.enabled), "seconds_per_turn": float(f.jog.seconds_per_turn)},
		"seek_bar_pictures": bool(f.thumbs.enabled),
		"zoom_lens": {"on": bool(f.zoom_lens.enabled), "magnification": float(f.zoom_lens.magnification)},
		"version": str(ProjectSettings.get_setting("application/config/version", "")),
	}


## The [pane] layout as the tab's Panel section shows it.
static func _layout(m: Node) -> Dictionary:
	var layer: Node = m.get("ui")
	if layer == null or not layer.has_method("layout_value"):
		return {}
	return {"size": snappedf(float(layer.layout_value("scale")), 0.01),
			"distance": snappedf(float(layer.layout_value("distance")), 0.01),
			"recentre_hold": snappedf(float(layer.layout_value("recentre_hold")), 0.01),
			"follow_head": not bool(layer.layout_value("world_locked"))}


static func _access(m: Node) -> Dictionary:
	var a: Node = m.features.access
	return {"larger_panel": snappedf(float(a.get_value("ui_scale")), 0.01), "left_handed": bool(a.get_value("left_handed")),
			"one_eye_3d": bool(a.get_value("monocular")), "eye": EYES[clampi(int(a.get_value("monocular_eye")), 0, 1)],
			"subtitles_always": bool(a.get_value("subtitles_always"))}


## available false: the app started without a foveated swapchain; the level can't be changed then.
static func _foveation(m: Node) -> Dictionary:
	return {"level": str(m.foveation), "sharp_panel": bool(m.foveation_sharp_panel),
			"available": bool(m.foveation_available())}


## The System tab shows the change.
func _sync_tab() -> void:
	var m := _main()
	var layer: Node = m.get("ui") if m != null else null
	var pane: Node = layer.get("ui") if layer != null else null
	var tab: Node = pane.get("system") if pane != null else null
	if tab != null and tab.has_method("sync"):
		tab.sync()


## A change command with nothing to change.
static func _none(args: Dictionary, ctx: DevCommands.Call, keys: Array) -> bool:
	for k: String in keys:
		if args.has(k):
			return false
	ctx.fail("give %s" % " or ".join(keys))
	return true


## A saved value as it is in the file, null when it isn't there (setting null back takes it out again).
static func _raw(settings: RefCounted, section: String, key: String) -> Variant:
	return settings.get_value(section, key, null) if settings.has_value(section, key) else null


# --- The panel -------------------------------------------------------------------------------------------------------

func _cmd_panel_layout(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	if _none(args, ctx, ["size", "distance", "recentre_hold", "follow_head"]):
		return null
	var m := _main()
	var layer: Node = m.get("ui")
	if layer == null or not layer.has_method("apply_layout"):
		return ctx.fail("this build has no menu panel")
	var settings: RefCounted = m.settings
	var was := {}
	for key: String in LAYOUT_KEYS:
		was[key] = _raw(settings, "pane", key)
	# What the tab's Panel sliders and "Follow my head" do: write [pane], then the layer applies it.
	if args.has("size"):
		settings.set_value("pane", "scale", clampf(float(args["size"]), 0.5, 3.0))
	if args.has("distance"):
		settings.set_value("pane", "distance", clampf(float(args["distance"]), 0.4, 2.0))
	if args.has("recentre_hold"):
		settings.set_value("pane", "recentre_hold", clampf(float(args["recentre_hold"]), 0.3, 1.5))
	if args.has("follow_head"):
		settings.set_value("pane", "world_locked", not bool(args["follow_head"]))
	layer.apply_layout()
	_sync_tab()
	ctx.summary = "panel layout"
	ctx.undo = func() -> void:
		for key: String in was:
			settings.set_value("pane", key, was[key])
		var l: Node = _main().get("ui")
		if l != null:
			l.apply_layout()
		_sync_tab()
	return _layout(m)


func _cmd_reset_layout(_args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var m := _main()
	var layer: Node = m.get("ui")
	if layer == null or not layer.has_method("reset_layout"):
		return ctx.fail("this build has no menu panel")
	var settings: RefCounted = m.settings
	var access: Node = m.features.access
	var was := {}
	for key: String in LAYOUT_KEYS:
		was[key] = _raw(settings, "pane", key)
	var was_access := [access.get_value("left_handed"), access.get_value("ui_scale")]
	# The tab's Reset layout.
	layer.reset_layout()
	_sync_tab()
	ctx.summary = "panel layout reset"
	ctx.undo = func() -> void:
		for key: String in was:
			settings.set_value("pane", key, was[key])
		access.set_value("left_handed", was_access[0])
		access.set_value("ui_scale", was_access[1])
		var l: Node = _main().get("ui")
		if l != null:
			l.apply_layout()
		_sync_tab()
	return _layout(m)


func _cmd_accessibility(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var keys := {"larger_panel": "ui_scale", "left_handed": "left_handed", "one_eye_3d": "monocular",
			"eye": "monocular_eye", "subtitles_always": "subtitles_always"}
	if _none(args, ctx, keys.keys()):
		return null
	var m := _main()
	var access: Node = m.features.access
	var was := {}
	for k: String in keys.values():
		was[k] = access.get_value(k)
	# The eye before one_eye_3d, so turning it on shows the eye asked for at once.
	for k: String in ["eye", "larger_panel", "left_handed", "subtitles_always", "one_eye_3d"]:
		if args.has(k):
			var v: Variant = EYES.find(args[k]) if k == "eye" else args[k]
			access.set_value(keys[k], v)
	_sync_tab()
	ctx.summary = "accessibility"
	ctx.undo = func() -> void:
		for k: String in ["monocular_eye", "ui_scale", "left_handed", "subtitles_always", "monocular"]:
			access.set_value(k, was[k])
		_sync_tab()
	return _access(m)


# --- Rendering -----------------------------------------------------------------------------------------------------

func _cmd_foveation(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	if _none(args, ctx, ["level", "sharp_panel"]):
		return null
	var m := _main()
	if not bool(m.foveation_available()):
		return ctx.fail("foveation isn't available: this build starts without it")
	var was := [str(m.foveation), bool(m.foveation_sharp_panel)]
	# What the tab's Foveation choice and "Sharp while the panel shows" do.
	if args.has("level"):
		m.set_foveation(str(args["level"]))
	if args.has("sharp_panel"):
		m.set_foveation_sharp_panel(bool(args["sharp_panel"]))
	_sync_tab()
	ctx.summary = "foveation %s%s" % [m.foveation, "" if m.foveation_sharp_panel else " (panel not kept sharp)"]
	ctx.undo = func() -> void:
		var mm := _main()
		mm.set_foveation(was[0])
		mm.set_foveation_sharp_panel(was[1])
		_sync_tab()
	return _foveation(m)


# --- The controllers -----------------------------------------------------------------------------------------------

func _cmd_haptics(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	if _none(args, ctx, ["on", "strength"]):
		return null
	var h: Node = _main().features.haptics
	var was := [bool(h.enabled), float(h.strength)]
	if args.has("strength"):
		h.set_strength(clampf(float(args["strength"]), 0.0, 1.0))
	if args.has("on"):
		h.set_enabled(bool(args["on"]))
	_sync_tab()
	ctx.summary = "haptic ticks %s" % ("%d %%" % roundi(h.strength * 100.0) if h.enabled else "off")
	ctx.undo = func() -> void:
		h.set_strength(was[1])
		h.set_enabled(was[0])
		_sync_tab()
	return {"on": bool(h.enabled), "strength": snappedf(float(h.strength), 0.01)}


func _cmd_jog(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	if _none(args, ctx, ["on", "seconds_per_turn"]):
		return null
	var j: Node = _main().features.jog
	var was := [bool(j.enabled), float(j.seconds_per_turn)]
	if args.has("seconds_per_turn"):
		j.set_seconds_per_turn(clampf(float(args["seconds_per_turn"]), 10.0, 600.0))
	if args.has("on"):
		j.set_enabled(bool(args["on"]))
	_sync_tab()
	ctx.summary = "jog wheel %s" % ("on" if j.enabled else "off")
	ctx.undo = func() -> void:
		j.set_seconds_per_turn(was[1])
		j.set_enabled(was[0])
		_sync_tab()
	return {"on": bool(j.enabled), "seconds_per_turn": float(j.seconds_per_turn)}


func _cmd_thumbs(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var t: Node = _main().features.thumbs
	var was := bool(t.enabled)
	t.set_enabled(bool(args["on"]))
	_sync_tab()
	ctx.summary = "seek bar pictures %s" % ("on" if t.enabled else "off")
	ctx.undo = func() -> void:
		t.set_enabled(was)
		_sync_tab()
	return {"on": bool(t.enabled)}


func _cmd_zoom_lens(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	if _none(args, ctx, ["on", "magnification"]):
		return null
	var z: Node = _main().features.zoom_lens
	var was := [bool(z.enabled), float(z.magnification)]
	if args.has("magnification"):
		z.set_magnification(clampf(float(args["magnification"]), 1.5, 8.0))
	if args.has("on"):
		z.set_enabled(bool(args["on"]))
	_sync_tab()
	ctx.summary = "zoom lens %s" % ("%.1fx" % z.magnification if z.enabled else "off")
	ctx.undo = func() -> void:
		z.set_magnification(was[1])
		z.set_enabled(was[0])
		_sync_tab()
	return {"on": bool(z.enabled), "magnification": float(z.magnification)}


# --- Test and setup ------------------------------------------------------------------------------------------------

func _cmd_test_card(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var m := _main()
	var path := "lab://" + str(args["card"])
	var old: String = m.current_path
	# What a Calibration cards button does.
	m.open_path(path, false)
	ctx.summary = "open %s" % path
	if old != "":
		ctx.undo = func() -> void: _main().open_path(old)
	return {"opened": path}
