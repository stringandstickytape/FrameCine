extends Node

## XR spikes (#71 passthrough, #72 hand tracking; docs/xr-spikes.md). Untested on the device.
##
## Always, when XR is up: one log line at session start with what the runtime offers that scripts can see
## ("OpenXR capabilities: ..."). From PLAYER_REQUESTS on the engine has OpenXRAPIExtension.get_supported_extensions(),
## and the line names the watched and vendor extensions; with other engines the list is only in the engine's --verbose
## log ("Found OpenXR extension").
##
## --passthrough   the ALPHA_BLEND environment blend mode, if the runtime offers it, with a transparent background:
##                 the runtime's camera view behind the screen. Off: opaque, as always.
## --hands         hand tracking: XRHandModifier3D skeletons with a dot per joint, pinch as the trigger, and the index
##                 finger as the laser when no controller is in that hand (hands.gd).
##
## Hand tracking is a start-up setting of the engine (xr/openxr/extensions/hand_tracking, off in project.godot, so the
## runtime does not track hands when nobody uses them). --hands switches it on through user://xr_override.cfg
## (project.godot's application/config/project_settings_override), read at the next start: the first run with --hands
## says "restart", and the launcher run.sh writes the file before it starts the engine. A start without --hands
## removes the file again.

const OVERRIDE := "user://xr_override.cfg"
const HAND_SETTINGS := ["xr/openxr/extensions/hand_tracking",
		"xr/openxr/extensions/hand_tracking_unobstructed_data_source",
		"xr/openxr/extensions/hand_tracking_controller_data_source"]
## Extensions the spikes care about; looked up in the full list when the engine gives one.
const WATCHED := ["XR_EXT_hand_tracking", "XR_EXT_hand_interaction", "XR_EXT_hand_tracking_data_source",
		"XR_FB_passthrough", "XR_HTC_passthrough", "XR_EXT_dpad_binding"]
const BLEND_NAMES := {XRInterface.XR_ENV_BLEND_MODE_OPAQUE: "opaque", XRInterface.XR_ENV_BLEND_MODE_ADDITIVE: "additive",
		XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND: "alpha_blend"}

var main: Node3D
var want_hands := false
var want_passthrough := false
var hands: Node
var _xr: XRInterface


static func attach(m: Node3D, args: Dictionary) -> void:
	var want := args.has("hands")
	var active := hand_tracking_enabled()
	var had_file := FileAccess.file_exists(OVERRIDE)
	_set_override(want)
	if want and not active:
		print("Hand tracking: switched on for the next start (%s); start again with --hands" % OVERRIDE)
	elif not want and active and had_file and not FileAccess.file_exists(OVERRIDE):
		print("Hand tracking: on in this run (left over from --hands); off from the next start")
	var xr := XRServer.find_interface("OpenXR")
	if xr == null or not xr.is_initialized() or not m.use_xr:
		if want or args.has("passthrough"):
			print("XR spikes: no XR session; --hands and --passthrough do nothing on a desktop")
		return
	var s: Node = (load("res://scripts/xr_spikes/xr_spikes.gd") as GDScript).new()
	s.name = "XRSpikes"
	s.main = m
	s._xr = xr
	s.want_hands = want and active
	s.want_passthrough = args.has("passthrough")
	m.add_child(s)


static func hand_tracking_enabled() -> bool:
	return bool(ProjectSettings.get_setting(HAND_SETTINGS[0], false))


## Writes or removes the override file (the next start reads it). Never touches a file with other settings in it.
static func _set_override(on: bool) -> void:
	var cfg := ConfigFile.new()
	var exists := cfg.load(OVERRIDE) == OK
	if exists:
		for section in cfg.get_sections():
			for key in cfg.get_section_keys(section):
				if not (section == "xr" and ("xr/" + key) in HAND_SETTINGS):
					return
	if on:
		for k: String in HAND_SETTINGS:
			cfg.set_value("xr", k.trim_prefix("xr/"), true)
		cfg.save(OVERRIDE)
	elif exists:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(OVERRIDE))


func _ready() -> void:
	if _xr.has_signal("session_begun"):
		_xr.connect("session_begun", _on_session_begun, CONNECT_ONE_SHOT)
	if want_hands:
		hands = load("res://scripts/xr_spikes/hands.gd").new()
		hands.name = "Hands"
		hands.origin = main.xr_camera.get_parent()
		add_child(hands)


func _on_session_begun() -> void:
	print(capabilities_line(_xr))
	if want_passthrough:
		_start_passthrough()


static func capabilities_line(xr: XRInterface) -> String:
	var parts: Array[String] = []
	var ox := xr as OpenXRInterface
	if ox != null:
		parts.append("hand tracking %s" % ("active" if ox.is_hand_tracking_supported() else
				("not offered" if hand_tracking_enabled() else "off (start with --hands)")))
		parts.append("hand interaction profile %s" % ("yes" if ox.is_hand_interaction_supported() else "no"))
		parts.append("eye gaze %s" % ("yes" if ox.is_eye_gaze_interaction_supported() else "no"))
		parts.append("refresh rates %s" % str(ox.get_available_display_refresh_rates()))
	var modes: Array[String] = []
	for m: int in xr.get_supported_environment_blend_modes():
		modes.append(BLEND_NAMES.get(m, str(m)))
	parts.append("blend modes %s" % ", ".join(modes))
	var all := supported_extensions()
	if all.is_empty():
		parts.append("extension list: not visible to scripts (engine --verbose: \"Found OpenXR extension\")")
	else:
		var seen: Array[String] = []
		for e: String in WATCHED:
			seen.append("%s %s" % [e, "yes" if e in all else "no"])
		var vendor: Array[String] = []
		for e: String in all:
			if e.begins_with("XR_VALVE") or e.begins_with("XR_MNDX"):
				vendor.append(e)
		parts.append(", ".join(seen))
		parts.append("vendor: %s" % (", ".join(vendor) if not vendor.is_empty() else "none"))
		parts.append("%d extensions in all" % all.size())
	return "OpenXR capabilities: " + "; ".join(parts)


## The runtime's extensions, when the engine exposes them to scripts and OpenXR runs; else [].
static func supported_extensions() -> PackedStringArray:
	if not ClassDB.class_has_method("OpenXRAPIExtension", "get_supported_extensions"):
		return PackedStringArray()
	var ox := XRServer.find_interface("OpenXR")
	if ox == null or not ox.is_initialized():
		return PackedStringArray()  # The engine would print a null-singleton error.
	var api: Object = ClassDB.instantiate("OpenXRAPIExtension")
	return PackedStringArray(api.call("get_supported_extensions")) if api != null else PackedStringArray()


## #71: the runtime's camera view behind the scene. The void room with a transparent clear colour; the screen stays.
func _start_passthrough() -> void:
	if not XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND in _xr.get_supported_environment_blend_modes():
		print("Passthrough: the runtime offers no ALPHA_BLEND blend mode; staying opaque")
		return
	_xr.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
	get_viewport().transparent_bg = true
	RenderingServer.set_default_clear_color(Color(0, 0, 0, 0))
	if main.has_method("set_environment") and main.env_id != "void":
		main.set_environment("void")
	var cleared := 0
	for we: Node in main.find_children("*", "WorldEnvironment", true, false):
		var env: Environment = (we as WorldEnvironment).environment
		if env != null:
			env.background_mode = Environment.BG_CLEAR_COLOR
			cleared += 1
	print("Passthrough: ALPHA_BLEND on, transparent background (%d environment(s) cleared)" % cleared)
