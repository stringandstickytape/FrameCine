extends SceneTree

## Tests for scripts/env/time_of_day.gd and the drive-in's sky (ideas #84): the sun's elevation against the NOAA
## solar calculator's values, the default night as designed, the real sun in clock mode at a summer noon and a winter
## dusk, the fixed modes, and rooms without a sky left alone. Settings are read-only.
## Run: godot --headless --xr-mode off --path app --script res://tests/test_time_of_day.gd

const TimeOfDay := preload("res://scripts/env/time_of_day.gd")

var _failures := 0
var _checks := 0
var main: Node3D


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	await _frames(5)
	# [lat, lon, unix UTC, NOAA elevation]
	for c: Array in [[51.5, 0.0, 1718884800, 61.94], [51.5, 0.0, 1718928000, -15.06], [0.0, 0.0, 1710936000, 88.17],
			[51.5, 0.0, 1734798600, -5.53], [-33.9, 151.2, 1704852000, 78.14], [40.7, -74.0, 1725233400, -1.33]]:
		var e := TimeOfDay.sun_elevation(c[0], c[1], c[2])
		_check("sun at %.1f, %.1f, %d: %.2f ~ %.2f" % [c[0], c[1], c[2], e, c[3]], absf(e - float(c[3])) < 0.3)

	var t: Node = main.features.time_of_day
	main.set_environment("drive_in")
	await _frames(2)
	var env: Node = main.env
	_check("default: the night as designed", t.mode == "night" and is_equal_approx(env.ambient_level, 0.04)
			and env._stars.visible)
	t.latitude = 51.5
	t.longitude = 0.0
	t.now_override = 1718884800.0
	t.set_mode("clock")
	_check("clock, summer noon: day (%.1f deg, ambient %.2f)" % [env.sun_elevation, env.ambient_level],
			env.sun_elevation > 60.0 and env.ambient_level > 0.85 and not env._stars.visible)
	var sky: Color = _shown(env._sky_mat, env)
	_check("day sky blue (%s)" % sky, sky.b > 0.8 and sky.b > sky.r * 1.8)
	t.now_override = 1734798600.0
	t.apply()
	var band: Color = _shown(env._band_mat, env)
	_check("clock, winter 16:30: dusk, warm band, stars coming (%.1f deg, band %s)" % [env.sun_elevation, band],
			env.sun_elevation < -4.0 and band.r > band.b * 2.0 and env._stars.visible
			and env._star_mat.albedo_color.r < 0.85)
	t.set_mode("day")
	_check("day mode", is_equal_approx(env.sun_elevation, 40.0) and env.ambient_level > 0.85)
	t.set_mode("dusk")
	band = _shown(env._band_mat, env)
	_check("dusk mode: the band glows (%s)" % band, band.r > 0.6)
	main.set_environment("cinema")
	await _frames(2)
	_check("a room without a sky: untouched", not main.env.has_method("set_time_of_day"))
	main.set_environment("drive_in")
	await _frames(2)
	_check("a new drive-in gets the mode", is_equal_approx(main.env.sun_elevation, -2.0))
	t.set_mode("night")
	_check("night again: as designed", is_equal_approx(main.env.ambient_level, 0.04)
			and not main.settings.has_value("time_of_day", "mode"))
	_check("longitude from the time zone when unset", is_equal_approx(TimeOfDay.new().longitude_in_use(),
			float(Time.get_time_zone_from_system().get("bias", 0)) / 4.0))
	print("test_time_of_day: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


## The colour a material shows (sRGB) at the room's ambient level: albedo to linear, times the ambient, back to sRGB.
func _shown(m: ShaderMaterial, env: Node) -> Color:
	var a: Color = Color(m.get_shader_parameter("albedo")).srgb_to_linear()
	return Color(a.r * env.ambient_level, a.g * env.ambient_level, a.b * env.ambient_level).linear_to_srgb()


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
