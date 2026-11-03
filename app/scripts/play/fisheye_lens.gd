extends Node

## Fisheye lens profiles (ideas #73): how far from the image circle's centre a ray at angle theta from the lens axis
## lands, r(theta), instead of assuming every lens is equidistant. Wide lenses (190-220 degrees) are often closer to
## equisolid-angle or stereographic, and a wrong model bends straight lines and misplaces the edge of the view. The
## profile reshapes the fisheye mesh (ProjectionMeshes.fisheye's mapping): no cost per pixel.
##
## Profiles (generic models; no maker's data ships with the app):
##   equidistant     r = f * theta                  (the default, as before)
##   equisolid       r = 2f * sin(theta / 2)        (many wide fisheyes)
##   stereographic   r = 2f * tan(theta / 2)        (keeps shapes at the edge larger)
##   polynomial      r = f * theta * (1 + k1 t^2 + k2 t^4 + k3 t^6 + k4 t^8), t = theta: a calibrated lens's
##                   coefficients in the common fisheye calibration model ([lens] k1..k4)
## r is scaled so the edge of the field of view (fov / 2) is the image circle's edge.
##
##   profile               the profile for the open file (its own choice, else the default)
##   PROFILES, set_profile(id, for_file := true), default_profile, set_coefficients(k: PackedFloat32Array)
##   mapping(id, fov, k) -> Callable(theta) -> r in 0..1 of the circle's radius   (static)
##   signal changed(profile)
## Settings: [lens] default (equidistant), k1..k4; [lens_files] <file key> = profile.

const FileKey := preload("res://scripts/play/file_key.gd")

signal changed(profile: String)

const PROFILES := ["equidistant", "equisolid", "stereographic", "polynomial"]

var main: Node3D
var profile := "equidistant"
var default_profile := "equidistant"
var coefficients := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _key := ""


func _ready() -> void:
	default_profile = _valid(str(main.settings.get_value("lens", "default", "equidistant")))
	for i in 4:
		coefficients[i] = float(main.settings.get_value("lens", "k%d" % (i + 1), 0.0))
	main.file_opened.connect(_on_file_opened)
	_on_file_opened(main.current_path)


static func _valid(id: String) -> String:
	return id if id in PROFILES else "equidistant"


## theta (radians, 0 .. fov/2) -> distance from the centre as a fraction of the image circle's radius.
static func mapping(id: String, fov_deg: float, k: PackedFloat32Array = PackedFloat32Array()) -> Callable:
	var half := deg_to_rad(fov_deg * 0.5)
	var g: Callable
	match id:
		"equisolid":
			g = func(t: float) -> float: return 2.0 * sin(t * 0.5)
		"stereographic":
			g = func(t: float) -> float: return 2.0 * tan(minf(t, PI * 0.99) * 0.5)
		"polynomial":
			var c := k if k.size() >= 4 else PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
			g = func(t: float) -> float:
				var t2 := t * t
				return t * (1.0 + t2 * (c[0] + t2 * (c[1] + t2 * (c[2] + t2 * c[3]))))
		_:
			g = func(t: float) -> float: return t
	var edge: float = g.call(half)
	return func(t: float) -> float: return float(g.call(t)) / edge if edge > 0.0 else t / half


func set_profile(id: String, for_file := true) -> void:
	id = _valid(id)
	if for_file and _key != "":
		main.settings.set_value("lens_files", _key, null if id == default_profile else id)
	elif not for_file:
		default_profile = id
		main.settings.set_value("lens", "default", null if id == "equidistant" else id)
	profile = id
	_apply()


func set_coefficients(k: PackedFloat32Array) -> void:
	for i in 4:
		coefficients[i] = k[i] if i < k.size() else 0.0
		main.settings.set_value("lens", "k%d" % (i + 1), null if is_zero_approx(coefficients[i]) else coefficients[i])
	_apply()


func _on_file_opened(path: String) -> void:
	_key = FileKey.key(path) if path != "" else ""
	profile = default_profile
	if _key != "" and main.settings.has_value("lens_files", _key):
		profile = _valid(str(main.settings.get_value("lens_files", _key, default_profile)))
	_apply()


func _apply() -> void:
	var screen: Node3D = main.screen
	screen.set("lens_profile", {"id": profile, "k": coefficients.duplicate()})
	if screen.has_method("rebuild"):
		screen.call("rebuild")
	changed.emit(profile)
