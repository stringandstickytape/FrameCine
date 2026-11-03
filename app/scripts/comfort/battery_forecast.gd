extends Node

## Battery versus film end (ideas #2): measures the headset battery's drain over a rolling window and predicts when it
## runs out, against when the film ends. "Film ends 22:47, battery ends 23:20."
##
## The battery is found at run time under /sys/class/power_supply: the first entry of type "Battery" whose scope is not
## "Device" (a peripheral's battery) and that is present. On the headset that is the fuel gauge (max1720x_bat_*, with
## charge_now / charge_full in uAh and a signed current_now). Level, best first: energy_now / energy_full,
## charge_now / charge_full, capacity / 100. On a desktop without one, everything reports "unknown" and nothing fails.
##
## Drain: a least-squares slope of the level over the last WINDOW_SECONDS of samples (one every SAMPLE_SECONDS). Until
## the window spans MIN_WINDOW_SECONDS, the instantaneous power_now (or current_now x voltage_now) stands in, and before
## any reading the spike 04 average (PRIOR_WATTS) does. The window restarts when charging starts or stops.
##
## forecast_changed(info) after every sample; get_forecast() returns the same Dictionary:
##   available        a battery was found
##   percent          0-100 (int), -1 when unknown
##   charging         plugged in and charging (or full)
##   drain_per_hour   fraction of a full battery per hour (0.4 = 40 %/h), 0 when unknown or charging
##   drain_source     "window", "power_now", "prior" or ""
##   watts            the drain in watts when the battery's capacity in Wh is known, else 0
##   battery_end_unix Unix time the battery is predicted to be empty, 0 when unknown or charging
##   battery_end_text "23:20" (local), "" when unknown
##   film_end_unix, film_end_text   when what is playing ends (0 / "" when nothing with a duration plays)
##   margin_minutes   battery end minus film end, minutes (0 when either is unknown)
##   verdict          "ok" (MARGIN_OK_MINUTES or more to spare), "tight" (less), "short" (the battery ends first),
##                    "charging", or "unknown"
##   text             one line for the glance state and the overlay, e.g. "battery 72 %, ends 23:20 | film ends 22:47"
## Settings: [battery] margin_ok_minutes (default 15).

const EndTime := preload("res://scripts/play/end_time.gd")

signal forecast_changed(info: Dictionary)

const ROOT := "/sys/class/power_supply"
const SAMPLE_SECONDS := 20.0
const WINDOW_SECONDS := 600.0
const MIN_WINDOW_SECONDS := 120.0
## Spike 04: 9.05 W average worn with 8K-class video (spikes/04-power/results/SUMMARY.md).
const PRIOR_WATTS := 9.0
const MARGIN_OK_MINUTES := 15.0

## The app core; only used for the film's remaining time (main.features.remaining()). Null in tests.
var main: Node3D
## Where to look for power supplies (tests point it at a fake tree).
var root := ROOT
## Seconds to the film's end when there is no main (tests).
var remaining_override := -1.0
var margin_ok_minutes := MARGIN_OK_MINUTES

## The chosen battery's folder, or "".
var battery_dir := ""
## [[time_s, level], ...] inside the window.
var _samples: Array = []
var _charging := false
var _timer := 0.0
var _forecast := {}
var _last_percent := -1


func _ready() -> void:
	if main != null:
		margin_ok_minutes = float(main.settings.get_value("battery", "margin_ok_minutes", MARGIN_OK_MINUTES))
	find_battery()
	sample()


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= SAMPLE_SECONDS:
		_timer = 0.0
		sample()


## Picks the system battery (see the header). Returns its folder or "".
func find_battery() -> String:
	battery_dir = ""
	if not DirAccess.dir_exists_absolute(root):
		return ""
	# The entries are symlinks: list both kinds in case they are not reported as directories.
	var names := Array(DirAccess.get_directories_at(root)) + Array(DirAccess.get_files_at(root))
	names.sort()
	for n: String in names:
		var d := root.path_join(n)
		if _read(d, "type") != "Battery":
			continue
		if _read(d, "scope") == "Device":
			continue
		if _read(d, "present") == "0":
			continue
		battery_dir = d
		break
	return battery_dir


## Reads the battery now, updates the window and the forecast, emits forecast_changed. now_s: seconds on any
## monotonic clock (tests pass their own).
func sample(now_s := -1.0) -> Dictionary:
	var now := now_s if now_s >= 0.0 else Time.get_ticks_msec() / 1000.0
	var r := read_battery()
	if not r.is_empty():
		var charging: bool = r["charging"]
		if charging != _charging:
			_samples.clear()
			_charging = charging
		_samples.append([now, float(r["level"])])
		while _samples.size() > 2 and now - float(_samples[0][0]) > WINDOW_SECONDS:
			_samples.pop_front()
	_forecast = _compute(r, now)
	forecast_changed.emit(_forecast)
	return _forecast


func get_forecast() -> Dictionary:
	return _forecast


## {level 0..1, percent, charging, watts_now (0 if unknown), capacity_wh (0 if unknown)}, or {} without a battery.
func read_battery() -> Dictionary:
	if battery_dir == "":
		return {}
	var d := battery_dir
	var status := _read(d, "status")
	var charging := status in ["Charging", "Full", "Not charging"]
	var level := -1.0
	var capacity_wh := 0.0
	var energy_now := _num(d, "energy_now")
	var energy_full := _num(d, "energy_full")
	var charge_now := _num(d, "charge_now")
	var charge_full := _num(d, "charge_full")
	var volts := _num(d, "voltage_now") / 1e6
	if energy_now >= 0.0 and energy_full > 0.0:
		level = energy_now / energy_full
		capacity_wh = energy_full / 1e6
	elif charge_now >= 0.0 and charge_full > 0.0:
		level = charge_now / charge_full
		if volts > 0.0:
			capacity_wh = charge_full / 1e6 * volts
	var cap := _num(d, "capacity")
	if level < 0.0 and cap >= 0.0:
		level = cap / 100.0
	if level < 0.0:
		return {}
	var watts := 0.0
	var power_now := _num(d, "power_now")
	var current_now := _num(d, "current_now")
	if power_now > 0.0:
		watts = power_now / 1e6
	elif current_now != -1.0 and current_now != 0.0 and volts > 0.0:
		# The sign convention differs between gauges; while discharging the magnitude is the drain.
		watts = absf(current_now) / 1e6 * volts
	var percent := int(round(cap)) if cap >= 0.0 else int(round(level * 100.0))
	return {"level": clampf(level, 0.0, 1.0), "percent": clampi(percent, 0, 100), "charging": charging,
			"watts_now": watts, "capacity_wh": capacity_wh}


func _compute(r: Dictionary, now: float) -> Dictionary:
	var unix := Time.get_unix_time_from_system()
	var out := {"available": not r.is_empty(), "percent": -1, "charging": false, "drain_per_hour": 0.0,
			"drain_source": "", "watts": 0.0, "battery_end_unix": 0.0, "battery_end_text": "", "film_end_unix": 0.0,
			"film_end_text": "", "margin_minutes": 0.0, "verdict": "unknown", "text": ""}
	var remaining := _remaining()
	if remaining > 0.0:
		out["film_end_unix"] = EndTime.end_unix(remaining, 1.0, unix)
		out["film_end_text"] = EndTime.clock_at(out["film_end_unix"])
	if r.is_empty():
		out["text"] = ("film ends " + out["film_end_text"]) if remaining > 0.0 else ""
		return out
	out["percent"] = r["percent"]
	out["charging"] = r["charging"]
	var capacity_wh: float = r["capacity_wh"]
	if r["charging"]:
		out["verdict"] = "charging"
		out["text"] = "battery %d %%, charging" % r["percent"]
		if remaining > 0.0:
			out["text"] += " | film ends " + out["film_end_text"]
		return out
	var drain := 0.0
	var source := ""
	var span := float(_samples[-1][0]) - float(_samples[0][0]) if _samples.size() >= 2 else 0.0
	if span >= MIN_WINDOW_SECONDS:
		drain = -_slope_per_second(_samples) * 3600.0
		source = "window"
	if drain <= 0.0 and float(r["watts_now"]) > 0.0 and capacity_wh > 0.0:
		drain = float(r["watts_now"]) / capacity_wh
		source = "power_now"
	if drain <= 0.0 and capacity_wh > 0.0:
		drain = PRIOR_WATTS / capacity_wh
		source = "prior"
	out["drain_per_hour"] = drain
	out["drain_source"] = source
	out["watts"] = drain * capacity_wh if capacity_wh > 0.0 else 0.0
	if drain > 0.0:
		var hours: float = float(r["level"]) / drain
		out["battery_end_unix"] = unix + hours * 3600.0
		out["battery_end_text"] = EndTime.clock_at(out["battery_end_unix"])
	out["verdict"] = verdict(float(out["battery_end_unix"]), float(out["film_end_unix"]), margin_ok_minutes)
	if out["battery_end_unix"] > 0.0 and out["film_end_unix"] > 0.0:
		out["margin_minutes"] = (float(out["battery_end_unix"]) - float(out["film_end_unix"])) / 60.0
	var text := "battery %d %%" % r["percent"]
	if out["battery_end_text"] != "":
		text += ", ends " + out["battery_end_text"]
	if remaining > 0.0:
		text += " | film ends " + out["film_end_text"]
		if out["verdict"] == "short":
			text += " (battery first)"
	out["text"] = text
	return out


## "ok", "tight", "short" or "unknown" for a battery end and a film end (Unix times, 0 = unknown).
static func verdict(battery_end: float, film_end: float, ok_minutes := MARGIN_OK_MINUTES) -> String:
	if battery_end <= 0.0 or film_end <= 0.0:
		return "unknown"
	var margin := (battery_end - film_end) / 60.0
	if margin < 0.0:
		return "short"
	return "ok" if margin >= ok_minutes else "tight"


## Least-squares slope of level against time, per second.
static func _slope_per_second(samples: Array) -> float:
	var n := float(samples.size())
	var t0 := float(samples[0][0])
	var sx := 0.0
	var sy := 0.0
	var sxx := 0.0
	var sxy := 0.0
	for s: Array in samples:
		var x := float(s[0]) - t0
		var y := float(s[1])
		sx += x
		sy += y
		sxx += x * x
		sxy += x * y
	var den := n * sxx - sx * sx
	return (n * sxy - sx * sy) / den if absf(den) > 1e-9 else 0.0


func _remaining() -> float:
	if main != null:
		return main.features.remaining_real()
	return remaining_override


static func _read(dir: String, file: String) -> String:
	var f := FileAccess.open(dir.path_join(file), FileAccess.READ)
	return f.get_line().strip_edges() if f != null else ""


## A numeric attribute, or -1 when absent.
static func _num(dir: String, file: String) -> float:
	var s := _read(dir, file)
	return s.to_float() if s.is_valid_float() or s.is_valid_int() else -1.0
