extends SceneTree

## Unit tests for scripts/comfort/battery_forecast.gd (battery versus film end, ideas #2), on a fake
## /sys/class/power_supply tree in user://. Run:
##   godot --headless --xr-mode off --path app --script res://tests/test_battery_forecast.gd

const BatteryForecast := preload("res://scripts/comfort/battery_forecast.gd")

var _failures := 0
var _root := ""


func _init() -> void:
	_root = OS.get_user_data_dir().path_join("test_power_supply")
	_clear()
	# A peripheral's battery (scope Device) sorts first and must be skipped; a charger is not a battery.
	_write("aa-controller", {"type": "Battery", "scope": "Device", "capacity": "50", "status": "Discharging"})
	_write("pm8550b-charger", {"type": "Unknown", "status": "Charging"})
	# The headset's gauge as the probe saw it: charge in uAh, signed current in uA, 2-cell voltage.
	_write("max1720x_bat_7-36", {"type": "Battery", "status": "Discharging", "capacity": "96",
			"voltage_now": "8810936", "current_now": "-1020000", "charge_now": "2784000", "charge_full": "2884000"})

	var f := BatteryForecast.new()
	f.root = _root
	f.remaining_override = 90 * 60.0
	_check("picks the system battery, not the controller: %s" % f.battery_dir.get_file(),
			f.find_battery().get_file() == "max1720x_bat_7-36")
	var r := f.read_battery()
	_check("level from charge_now / charge_full", is_equal_approx(r["level"], 2784000.0 / 2884000.0))
	_check("percent from capacity", r["percent"] == 96)
	_check("capacity in Wh from charge x voltage (%.1f)" % r["capacity_wh"], absf(r["capacity_wh"] - 25.41) < 0.05)
	_check("watts from |current| x voltage (%.2f)" % r["watts_now"], absf(r["watts_now"] - 8.99) < 0.02)

	# First sample: no window yet, the instantaneous power stands in.
	var info := f.sample(0.0)
	_check("first sample uses power_now (%s)" % info["drain_source"], info["drain_source"] == "power_now")
	_check("film end text set", info["film_end_text"] != "")
	# 9 W on 25.4 Wh: 0.354 per hour; 96.5 % left: 2.7 h > 1.5 h film -> ok.
	_check("verdict ok with 1.5 h of film (%s, %.0f min margin)" % [info["verdict"], info["margin_minutes"]],
			info["verdict"] == "ok")
	_check("text '%s'" % info["text"], str(info["text"]).begins_with("battery 96 %, ends ") and "film ends" in info["text"])

	# Ten minutes of samples draining 12 % per hour of charge: the window's slope takes over.
	var charge := 2784000.0
	for i in range(1, 31):
		charge -= 2884000.0 * 0.12 / 3600.0 * 20.0
		_write("max1720x_bat_7-36", {"charge_now": str(int(charge))})
		info = f.sample(i * 20.0)
	_check("window drain (%s, %.3f/h)" % [info["drain_source"], info["drain_per_hour"]],
			info["drain_source"] == "window" and absf(info["drain_per_hour"] - 0.12) < 0.002)

	# A long film with a fast drain: the battery ends first.
	f.remaining_override = 10 * 3600.0
	info = f.sample(620.0)
	_check("short verdict (%s)" % info["verdict"], info["verdict"] == "short" and "(battery first)" in info["text"])

	# Plugged in: charging, window restarts.
	_write("max1720x_bat_7-36", {"status": "Charging"})
	info = f.sample(640.0)
	_check("charging verdict", info["verdict"] == "charging" and info["charging"] and info["battery_end_unix"] == 0.0)
	_write("max1720x_bat_7-36", {"status": "Discharging"})
	info = f.sample(660.0)
	_check("after unplugging the window restarts (%s)" % info["drain_source"], info["drain_source"] == "power_now")

	# Static verdicts.
	_check("verdict tight", BatteryForecast.verdict(1000.0 + 600.0, 1000.0) == "tight")
	_check("verdict ok", BatteryForecast.verdict(1000.0 + 3600.0, 1000.0) == "ok")
	_check("verdict unknown", BatteryForecast.verdict(0.0, 1000.0) == "unknown")

	# No power supplies at all (a desktop): unknown, no errors, film end still given.
	var none := BatteryForecast.new()
	none.root = _root.path_join("missing")
	none.remaining_override = 600.0
	none.find_battery()
	info = none.sample(0.0)
	_check("no battery: unavailable, unknown", not info["available"] and info["verdict"] == "unknown"
			and info["percent"] == -1 and str(info["text"]).begins_with("film ends "))
	none.free()
	f.free()
	_clear()
	print("test_battery_forecast: %s" % ("all passed" if _failures == 0 else "%d FAILED" % _failures))
	quit(_failures)


func _write(name: String, files: Dictionary) -> void:
	var d := _root.path_join(name)
	DirAccess.make_dir_recursive_absolute(d)
	for k: String in files:
		FileAccess.open(d.path_join(k), FileAccess.WRITE).store_string(str(files[k]) + "\n")


func _clear() -> void:
	if not DirAccess.dir_exists_absolute(_root):
		return
	for d in DirAccess.get_directories_at(_root):
		for f in DirAccess.get_files_at(_root.path_join(d)):
			DirAccess.remove_absolute(_root.path_join(d).path_join(f))
		DirAccess.remove_absolute(_root.path_join(d))
	DirAccess.remove_absolute(_root)


func _check(what: String, ok: bool) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL " + what)
