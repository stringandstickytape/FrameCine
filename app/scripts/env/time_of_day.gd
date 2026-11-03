extends Node

## Time of day for the outdoor rooms (ideas #84): the drive-in at dusk when it is dusk outside. The sun's elevation
## comes from the system clock and a latitude setting (no internet, no weather); an environment with
## set_time_of_day(elevation_deg) shows it (the drive-in: sky, horizon band, stars, the lot's light).
##
##   mode        "night" (the room as designed: the default), "clock" (the real sun), "dusk", "day"
##   latitude    degrees north (default 50); longitude: degrees east, or derived from the system's time zone (15 degrees
##               an hour; daylight saving can put the sun's times an hour off without the setting)
##   elevation() -> float            the sun's elevation (degrees) for the mode now
##   static sun_elevation(lat, lon, unix_utc) -> float     the sun's elevation, a low-precision solar position
##                                   formula (about 0.1 degree, plenty for a sky)
##   set_mode(m), set_latitude(v), set_longitude(v or null)
##   signal changed(elevation)
## Settings: [time_of_day] mode, latitude, longitude. In clock mode the sky is updated once a minute.

signal changed(elevation: float)

const MODES := ["night", "clock", "dusk", "day"]
## Fixed elevations for the fixed modes.
const FIXED := {"night": -90.0, "dusk": -2.0, "day": 40.0}
const UPDATE_SECONDS := 60.0

var main: Node3D
var mode := "night"
var latitude := 50.0
## null: from the time zone.
var longitude: Variant = null
## Unix time (UTC) to use instead of the clock (tests); < 0: the clock.
var now_override := -1.0
var _since := 0.0


func _ready() -> void:
	mode = str(main.settings.get_value("time_of_day", "mode", "night"))
	if not mode in MODES:
		mode = "night"
	latitude = clampf(float(main.settings.get_value("time_of_day", "latitude", 50.0)), -90.0, 90.0)
	longitude = float(main.settings.get_value("time_of_day", "longitude", 0.0)) 			if main.settings.has_value("time_of_day", "longitude") else null
	main.environment_changed.connect(func(_id: String, _l: float) -> void: apply())
	apply()


func set_mode(m: String) -> void:
	mode = m if m in MODES else "night"
	main.settings.set_value("time_of_day", "mode", null if mode == "night" else mode)
	apply()


func set_latitude(v: float) -> void:
	latitude = clampf(v, -90.0, 90.0)
	main.settings.set_value("time_of_day", "latitude", null if is_equal_approx(latitude, 50.0) else latitude)
	apply()


func set_longitude(v: Variant) -> void:
	longitude = clampf(float(v), -180.0, 180.0) if v != null else null
	main.settings.set_value("time_of_day", "longitude", longitude)
	apply()


func longitude_in_use() -> float:
	if longitude != null:
		return float(longitude)
	return float(Time.get_time_zone_from_system().get("bias", 0)) / 4.0


func elevation() -> float:
	if mode == "clock":
		var t := now_override if now_override >= 0.0 else Time.get_unix_time_from_system()
		return sun_elevation(latitude, longitude_in_use(), t)
	return float(FIXED.get(mode, -90.0))


## The sun's elevation in degrees at latitude / longitude (degrees, east positive) and a Unix time (UTC).
static func sun_elevation(lat: float, lon: float, unix_utc: float) -> float:
	var d := unix_utc / 86400.0 - 10957.5
	var g := deg_to_rad(fposmod(357.528 + 0.9856003 * d, 360.0))
	var l := fposmod(280.46 + 0.9856474 * d, 360.0)
	var lam := deg_to_rad(l + 1.915 * sin(g) + 0.020 * sin(2.0 * g))
	var eps := deg_to_rad(23.439 - 0.0000004 * d)
	var ra := atan2(cos(eps) * sin(lam), cos(lam))
	var dec := asin(sin(eps) * sin(lam))
	var gmst := fposmod(18.697374558 + 24.06570982441908 * d, 24.0)
	var h := deg_to_rad(fposmod((gmst * 15.0 + lon) - rad_to_deg(ra), 360.0))
	var phi := deg_to_rad(lat)
	return rad_to_deg(asin(sin(phi) * sin(dec) + cos(phi) * cos(dec) * cos(h)))


func apply() -> void:
	var e := elevation()
	var env: Node = main.env
	if env != null and env.has_method("set_time_of_day"):
		env.call("set_time_of_day", e)
		var rl: Node = main.features.get("room_light") if main.features != null else null
		env.call("apply_light", float(rl.effective()) if rl != null else float(main.room_light))
	changed.emit(e)


func _process(delta: float) -> void:
	if mode != "clock":
		return
	_since += delta
	if _since >= UPDATE_SECONDS:
		_since = 0.0
		apply()
