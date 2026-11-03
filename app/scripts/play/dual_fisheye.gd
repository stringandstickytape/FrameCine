extends Node

## Dual fisheye 360 lens profiles: how a 360 camera's raw frame (two image circles side by side, the left lens looking
## ahead and the right one looking back; VideoMode.Proj.DUAL_FISHEYE) maps onto the sphere. The values reshape the
## sphere's mesh (ProjectionMeshes.dual_fisheye): no cost per pixel.
##
## A profile holds, per lens (front, back): fov (degrees across the circle), cx, cy (the circle's centre, fractions of
## the frame's width and height), radius (fraction of the frame's height; 0.5 = it touches the top and bottom), yaw,
## pitch, roll (degrees: the lens turned from looking straight ahead / straight back, for alignment). And blend (half
## the seam's soft band, degrees: the lenses cross-fade from 90 - blend to 90 + blend off the front's axis) and the
## lens model (scripts/play/fisheye_lens.gd's generic ones; polynomial is not offered here).
##
## Profiles:
##   camera360        a dual-lens 360 camera's raw video, 4096 x 2048, fitted to the user's footage
##                  (docs/features.md, "Dual fisheye 360"): equidistant, each circle centred in its half.
##   camera360_photo  the same camera's raw stills, 5792 x 2896: the circles are a little smaller in the frame than in
##                  the video (the video is a different readout of the sensor), so they get their own fit.
##   generic        any dual fisheye 360 camera: centred circles filling their halves, 190 degrees, no turn.
## The values a user changes are kept per profile ([dual_fisheye_<id>] <lens>_<key>, blend), so a nudge for one camera
## stays for all its files; reset() goes back to the profile's own. The profile is chosen per file
## ([dual_fisheye_files]); without a choice, a 360 camera file name (360_NNNN) gets camera360 (a picture gets
## camera360_photo), others the default ([dual_fisheye] default, generic).
##
##   profile, PROFILES, PROFILE_NAMES, set_profile(id, for_file := true), default_profile
##   values() -> {front: {...}, back: {...}, blend, model}   the open file's profile with the user's changes
##   set_value(key, v)    key: "<front|back>_<fov|cx|cy|radius|yaw|pitch|roll>", "blend", "model", or the Picture
##                        tab's two: "fov" (both lenses) and "seam" (the back lens's yaw: slides the back picture
##                        sideways along the seam)
##   set_values(dict)     several at once, nested like values() (the dev link's dual_fisheye_lens)
##   reset()              the profile's own values again
##   static defaults(id) -> the profile's built-in values;  static uniforms(lens, frame_aspect) -> the zoom lens's
##   signal changed(profile)

const FileKey := preload("res://scripts/play/file_key.gd")
const VideoMode := preload("res://scripts/video_mode.gd")
const ProjectionMeshes := preload("res://scripts/projection_meshes.gd")

signal changed(profile: String)

const PROFILES := ["camera360", "camera360_photo", "generic"]
const PROFILE_NAMES := ["360 camera video", "360 camera photo", "Other camera"]
## Picture files (scripts/play/image_source.gd's EXTENSIONS).
const PICTURE_EXTENSIONS := ["jpg", "jpeg", "png", "webp"]
const LENS_KEYS := ["fov", "cx", "cy", "radius", "yaw", "pitch", "roll"]
const MODELS := ["equidistant", "equisolid", "stereographic"]
## [min, max] of each value.
const RANGES := {"fov": [150.0, 240.0], "cx": [0.0, 1.0], "cy": [0.0, 1.0], "radius": [0.05, 1.0],
		"yaw": [-20.0, 20.0], "pitch": [-20.0, 20.0], "roll": [-20.0, 20.0], "blend": [0.0, 15.0]}
## The Picture tab's seam slider: the back lens's yaw within +-SEAM_RANGE degrees.
const SEAM_RANGE := 5.0

const DEFAULTS := {
	# Fitted on feature pairs matched across the seam in the user's 360 camera footage (2026-11-01; docs/features.md,
	# "Dual fisheye 360"): 195 degrees across a circle a little larger than the frame's height (it is cut at the top
	# and bottom), the back lens turned by a fraction of a degree.
	"camera360": {
		"front": {"fov": 195.0, "cx": 0.249, "cy": 0.5072, "radius": 0.5183, "yaw": 0.0, "pitch": 0.0, "roll": 0.0},
		"back": {"fov": 195.0, "cx": 0.7521, "cy": 0.5051, "radius": 0.5183, "yaw": -0.68, "pitch": 0.68, "roll": -0.4},
		"blend": 3.0, "model": "equidistant"},
	"camera360_photo": {
		"front": {"fov": 195.0, "cx": 0.2489, "cy": 0.5012, "radius": 0.5104, "yaw": 0.0, "pitch": 0.0, "roll": 0.0},
		"back": {"fov": 195.0, "cx": 0.752, "cy": 0.4991, "radius": 0.5104, "yaw": -0.99, "pitch": -0.15, "roll": -0.39},
		"blend": 3.0, "model": "equidistant"},
	"generic": {
		"front": {"fov": 190.0, "cx": 0.25, "cy": 0.5, "radius": 0.5, "yaw": 0.0, "pitch": 0.0, "roll": 0.0},
		"back": {"fov": 190.0, "cx": 0.75, "cy": 0.5, "radius": 0.5, "yaw": 0.0, "pitch": 0.0, "roll": 0.0},
		"blend": 2.5, "model": "equidistant"},
}

var main: Node
var profile := "generic"
var default_profile := "generic"
var _key := ""
var _path := ""


func _ready() -> void:
	default_profile = _valid(str(main.settings.get_value("dual_fisheye", "default", "generic")))
	main.file_opened.connect(_on_file_opened)
	main.mode_changed.connect(_on_mode_changed)
	_on_file_opened(main.current_path)


static func _valid(id: String) -> String:
	return id if id in PROFILES else "generic"


## The profile's built-in values (a fresh copy).
static func defaults(id: String) -> Dictionary:
	return (DEFAULTS[_valid(id)] as Dictionary).duplicate(true)


## The profile (the open file's by default) with the user's changes.
func values(id := "") -> Dictionary:
	id = _valid(id if id != "" else profile)
	var v := defaults(id)
	var section := "dual_fisheye_" + id
	for lens in ["front", "back"]:
		for k: String in LENS_KEYS:
			if main.settings.has_value(section, lens + "_" + k):
				v[lens][k] = _clamp(k, float(main.settings.get_value(section, lens + "_" + k, 0.0)))
	if main.settings.has_value(section, "blend"):
		v["blend"] = _clamp("blend", float(main.settings.get_value(section, "blend", 3.0)))
	var model := str(main.settings.get_value(section, "model", v["model"]))
	v["model"] = model if model in MODELS else "equidistant"
	return v


static func _clamp(k: String, x: float) -> float:
	var r: Array = RANGES.get(k, [-INF, INF])
	return clampf(x, r[0], r[1])


## The Picture tab's field of view: the front lens's (set_value("fov") sets both).
func fov() -> float:
	return float(values()["front"]["fov"])


## The Picture tab's seam nudge: the back lens's yaw.
func seam() -> float:
	return float(values()["back"]["yaw"])


func set_value(key: String, v: Variant) -> void:
	_store(key, v)
	_apply()


func set_values(d: Dictionary) -> void:
	for lens in ["front", "back"]:
		if d.get(lens) is Dictionary:
			for k: String in (d[lens] as Dictionary):
				_store(lens + "_" + k, d[lens][k])
	for k in ["blend", "model", "fov", "seam"]:
		if d.has(k):
			_store(k, d[k])
	_apply()


func _store(key: String, v: Variant) -> void:
	var section := "dual_fisheye_" + profile
	var base := defaults(profile)
	match key:
		"fov":
			_store("front_fov", v)
			_store("back_fov", v)
			return
		"seam":
			_store("back_yaw", clampf(float(v), -SEAM_RANGE, SEAM_RANGE))
			return
		"model":
			var m := str(v)
			main.settings.set_value(section, "model", null if m == base["model"] or not m in MODELS else m)
			return
		"blend":
			var b := _clamp("blend", float(v))
			main.settings.set_value(section, "blend", null if is_equal_approx(b, base["blend"]) else b)
			return
	var parts := key.split("_", false, 1)
	if parts.size() != 2 or not parts[0] in ["front", "back"] or not parts[1] in LENS_KEYS:
		push_warning("Dual fisheye: no value %s" % key)
		return
	var x := _clamp(parts[1], float(v))
	main.settings.set_value(section, key, null if is_equal_approx(x, base[parts[0]][parts[1]]) else x)


## The profile's own values again (the user's changes to it erased).
func reset() -> void:
	var section := "dual_fisheye_" + profile
	for k: String in main.settings.get_keys(section):
		main.settings.set_value(section, k, null)
	_apply()


func set_profile(id: String, for_file := true) -> void:
	id = _valid(id)
	if for_file and _key != "":
		main.settings.set_value("dual_fisheye_files", _key, null if id == _auto_profile(_path) else id)
	elif not for_file:
		default_profile = id
		main.settings.set_value("dual_fisheye", "default", null if id == "generic" else id)
	profile = id
	_apply()


## The profile a file gets without a choice: camera360 or camera360_photo for a 360 camera name, else the default.
func _auto_profile(path: String) -> String:
	var size: Vector2 = main.call("_frame_size") if main.has_method("_frame_size") else Vector2.ZERO
	return auto_profile(path, default_profile, int(size.x))


## A 360 camera name's profile: by the frame's width once it is known (the stills are 5792 wide, the video 4096; a
## video frame saved as a picture is still video), else by the extension. Other names: fallback.
static func auto_profile(path: String, fallback := "generic", frame_width := 0) -> String:
	if path == "" or not VideoMode.is_camera360_raw_name(path.get_file()):
		return fallback
	if frame_width > 0:
		return "camera360_photo" if frame_width > 5000 else "camera360"
	return "camera360_photo" if path.get_extension().to_lower() in PICTURE_EXTENSIONS else "camera360"


func _on_file_opened(path: String) -> void:
	_path = path
	_key = FileKey.key(path) if path != "" else ""
	profile = _auto_profile(path)
	if _has_choice():
		profile = _valid(str(main.settings.get_value("dual_fisheye_files", _key, profile)))
	_apply()


func _has_choice() -> bool:
	return _key != "" and main.settings.has_value("dual_fisheye_files", _key)


## The frame's size is known (or changed): a 360 camera file without a choice may move between video and photo.
func _on_mode_changed(_mode: VideoMode, _auto_text: String) -> void:
	if _has_choice():
		return
	var id := _auto_profile(_path)
	if id != profile:
		profile = id
		_apply()


func _apply() -> void:
	var screen: Node3D = main.screen
	screen.set("dual_lens", values())
	if screen.has_method("rebuild"):
		screen.call("rebuild")
	changed.emit(profile)


## The zoom lens's uniforms (shaders/magnifier.gdshader) for these values: the inverse turn of each lens, its circle
## (cx, cy, radius across in fractions of the width, of the height) and half field of view in radians, and the blend.
static func uniforms(lens: Dictionary, frame_aspect: float) -> Dictionary:
	var out := {"dfe_blend": deg_to_rad(float(lens.get("blend", 3.0)))}
	for side in ["front", "back"]:
		var l: Dictionary = lens[side]
		var r := float(l["radius"])
		out["dfe_%s_inverse" % side] = ProjectionMeshes.lens_basis(l).transposed()
		out["dfe_%s_circle" % side] = Vector4(float(l["cx"]), float(l["cy"]), r / maxf(frame_aspect, 0.01), r)
		out["dfe_%s_half_fov" % side] = deg_to_rad(float(l["fov"]) * 0.5)
	return out
