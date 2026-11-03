extends Node

## Screen size in degrees (ideas #55): how wide the screen looks, which is what matters in a headset, rather than its
## width in metres. Setting an angle keeps the distance and changes the width; presets set both (distance matters for
## the eyes' focus and convergence, and for how big the room around the screen feels).
##
##   angle() -> degrees           the flat screen's horizontal angle now
##   set_angle(deg)               10..120, at the current distance
##   PRESETS                      id -> {name, angle, distance, lying}: large format (wraps your view, far), living
##                                room (a big TV across the room), in bed (close, and lying down on, #12)
##   apply_preset(id), preset_ids(), matching_preset() -> id or ""
##   width_for(angle, distance) (static)
##   signal changed(angle)
## Settings: none of its own; the screen's width and distance are main's ([screen_<environment>]).

signal changed(angle: float)

const MIN_ANGLE := 10.0
const MAX_ANGLE := 120.0
const PRESETS := {
	"large_format": {"name": "Large format", "angle": 70.0, "distance": 14.0, "lying": false},
	"living_room": {"name": "Living room", "angle": 32.0, "distance": 3.2, "lying": false},
	"in_bed": {"name": "In bed", "angle": 42.0, "distance": 2.4, "lying": true},
}

var main: Node3D


func _ready() -> void:
	main.screen_changed.connect(func(_w: float, _d: float, _h: float) -> void: changed.emit(angle()))


static func width_for(deg: float, distance: float) -> float:
	return 2.0 * distance * tan(deg_to_rad(clampf(deg, MIN_ANGLE, MAX_ANGLE)) * 0.5)


static func angle_of(width: float, distance: float) -> float:
	return rad_to_deg(2.0 * atan(width * 0.5 / maxf(distance, 0.01)))


func angle() -> float:
	return angle_of(main.screen_width, main.screen_distance)


func set_angle(deg: float) -> void:
	main.set_screen(width_for(deg, main.screen_distance), main.screen_distance, main.screen_height_offset)


func preset_ids() -> Array:
	return PRESETS.keys()


func apply_preset(id: String) -> void:
	if not PRESETS.has(id):
		push_warning("Screen angle: no preset '%s'" % id)
		return
	var p: Dictionary = PRESETS[id]
	main.set_screen(width_for(p["angle"], p["distance"]), p["distance"], main.screen_height_offset)
	var pose: Node = main.features.get("pose")
	if pose != null:
		pose.set_lying(bool(p["lying"]))


## The preset the screen is at now (within a degree and 5 cm), or "".
func matching_preset() -> String:
	for id: String in PRESETS:
		var p: Dictionary = PRESETS[id]
		if absf(angle() - float(p["angle"])) < 1.0 and absf(main.screen_distance - float(p["distance"])) < 0.05:
			return id
	return ""
