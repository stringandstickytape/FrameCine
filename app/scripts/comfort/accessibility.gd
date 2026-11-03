extends Node

## Accessibility pack (ideas #74): a few settings in one place. Two are applied here; two are for the pane to read.
##
##   ui_scale          1.0 .. 2.0: the pane and its text larger. The pane applies it (it owns the layout); listen to
##                     changed("ui_scale", v).
##   left_handed       the left controller is the panel's pointer until a menu press picks one (ui-design.md,
##                     "Revision 2"). The panel applies it. Direct bindings stay as they are: both sticks already seek.
##   monocular         one eye's picture to both views for every 3D file: 2D from 3D (#59) with `monocular_eye`.
##                     Turning it off turns 2D from 3D off.
##   subtitles_always  every file opens with subtitles on (the remembered language's track, else the default one),
##                     whatever the last file's on/off was. Turning them off during a film lasts for that film.
##   set_value(key, value), get_value(key), signal changed(key, value)
## Settings: [accessibility] ui_scale, left_handed, monocular, monocular_eye, subtitles_always.

signal changed(key: String, value: Variant)

const DEFAULTS := {
	"ui_scale": 1.0,
	"left_handed": false,
	"monocular": false,
	"monocular_eye": 0,
	"subtitles_always": false,
}

var main: Node3D
var _values := {}


func _ready() -> void:
	for k: String in DEFAULTS:
		_values[k] = main.settings.get_value("accessibility", k, DEFAULTS[k])
	_values["ui_scale"] = clampf(float(_values["ui_scale"]), 1.0, 2.0)
	main.file_opened.connect(_on_file_opened)
	if bool(_values["monocular"]):
		main.features.two_d.set_eye(int(_values["monocular_eye"]))


func get_value(key: String) -> Variant:
	return _values.get(key, DEFAULTS.get(key))


func set_value(key: String, value: Variant) -> void:
	if not DEFAULTS.has(key):
		push_warning("Accessibility: no '%s'" % key)
		return
	match key:
		"ui_scale":
			value = clampf(float(value), 1.0, 2.0)
		"monocular_eye":
			value = clampi(int(value), 0, 1)
		_:
			value = bool(value)
	_values[key] = value
	main.settings.set_value("accessibility", key, null if value == DEFAULTS[key] else value)
	match key:
		"monocular":
			main.features.two_d.set_eye(int(_values["monocular_eye"]) if value else -1)
		"monocular_eye":
			if bool(_values["monocular"]):
				main.features.two_d.set_eye(int(value))
		"subtitles_always":
			if value:
				_subtitles_on()
	changed.emit(key, value)


func _on_file_opened(path: String) -> void:
	if path != "" and bool(_values["subtitles_always"]):
		_subtitles_on()


func _subtitles_on() -> void:
	var subs: Node = main.features.subtitles
	if subs.enabled and subs.track >= 0:
		return
	var t: int = subs.pick_track()
	if t >= 0:
		# Not the user's own toggle: language memory doesn't learn from it, and settings keep the user's on/off.
		subs.set_state({"enabled": true, "track": t})
