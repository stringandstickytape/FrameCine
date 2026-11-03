extends RefCounted

## Device readings from /sys and /proc for the stats (stats.gd): GPU clock and load, battery power, thermal zones,
## and this process's CPU time. Every reading is optional: a file that is missing or unreadable gives null, so the
## same code runs on a desktop (where most are missing) and on the headset. The paths follow spikes/04-power/powerlog.sh,
## which logged them on the device. Paths are looked up once and cached.

const POWER_SUPPLY := "/sys/class/power_supply"
const THERMAL := "/sys/class/thermal"
## Thermal zones worth showing (the powerlog's choice); others count only for the hottest.
const ZONES_OF_INTEREST: Array[String] = ["video-thermal", "ddr-thermal", "gpuss-0-thermal", "cpuss0-thermal",
		"cpu7-top-thermal", "cpu2-top-thermal", "pm8550-thermal"]

static var _gpu_dir := ""
static var _battery_dir := ""
static var _zones := {}
static var _looked_up := false


static func _lookup() -> void:
	if _looked_up:
		return
	_looked_up = true
	for root in ["/sys/class/devfreq", "/sys/class/kgsl"]:
		if not DirAccess.dir_exists_absolute(root):
			continue
		for d in _entries(root):
			if d.contains("gpu") or d == "kgsl-3d0":
				_gpu_dir = root.path_join(d)
				break
		if _gpu_dir != "":
			break
	if DirAccess.dir_exists_absolute(POWER_SUPPLY):
		for d in _entries(POWER_SUPPLY):
			if str(read_text(POWER_SUPPLY.path_join(d).path_join("type"))) == "Battery":
				_battery_dir = POWER_SUPPLY.path_join(d)
				break
	if DirAccess.dir_exists_absolute(THERMAL):
		for d in _entries(THERMAL):
			if d.begins_with("thermal_zone"):
				var type: Variant = read_text(THERMAL.path_join(d).path_join("type"))
				if type != null:
					_zones[str(type)] = THERMAL.path_join(d).path_join("temp")


## Directory entries, symlinks included (sysfs entries are symlinks that may list as files).
static func _entries(dir: String) -> Array:
	return Array(DirAccess.get_directories_at(dir)) + Array(DirAccess.get_files_at(dir))


## The first line of a file, stripped, or null.
static func read_text(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var line := f.get_line().strip_edges()
	return line if line != "" else null


static func read_int(path: String) -> Variant:
	var t: Variant = read_text(path)
	if t == null:
		return null
	var s := str(t).get_slice(" ", 0)
	return s.to_int() if s.is_valid_int() else null


## {clock_mhz, load_percent} (either may be null), or {} with no GPU node.
static func gpu() -> Dictionary:
	_lookup()
	if _gpu_dir == "":
		return {}
	var hz: Variant = read_int(_gpu_dir.path_join("cur_freq"))
	if hz == null or hz == 0:
		hz = read_int(_gpu_dir.path_join("gpuclk"))
	var load: Variant = read_int(_gpu_dir.path_join("gpu_busy_percentage"))
	if load == null:
		load = read_int(_gpu_dir.path_join("load"))  # devfreq "load@freq" on some drivers
	return {"clock_mhz": roundi(hz / 1e6) if hz != null else null, "load_percent": load, "node": _gpu_dir}


## {percent, status, power_w (positive while discharging), voltage_v, current_a, temp_c}, or {} with no battery.
static func battery() -> Dictionary:
	_lookup()
	if _battery_dir == "":
		return {}
	var uv: Variant = read_int(_battery_dir.path_join("voltage_now"))
	var ua: Variant = read_int(_battery_dir.path_join("current_now"))
	var temp: Variant = read_int(_battery_dir.path_join("temp"))
	var out := {"percent": read_int(_battery_dir.path_join("capacity")),
			"status": read_text(_battery_dir.path_join("status"))}
	if uv != null and ua != null:
		out["voltage_v"] = snappedf(uv / 1e6, 0.001)
		out["current_a"] = snappedf(ua / 1e6, 0.001)
		# This battery reports a negative current while discharging (powerlog.sh).
		out["power_w"] = snappedf(absf(uv * ua) / 1e12, 0.01)
	if temp != null:
		out["temp_c"] = snappedf(temp / 10.0, 0.1)
	return out


## {zones: {name: C} (the zones of interest), hottest: {name, c}}, or {} without thermal zones.
static func thermal() -> Dictionary:
	_lookup()
	if _zones.is_empty():
		return {}
	var zones := {}
	var hottest_name := ""
	var hottest := -1000.0
	for name: String in _zones:
		var milli: Variant = read_int(_zones[name])
		if milli == null:
			continue
		var c := snappedf(milli / 1000.0, 0.1)
		if name in ZONES_OF_INTEREST:
			zones[name.trim_suffix("-thermal")] = c
		if c > hottest:
			hottest = c
			hottest_name = name
	return {"zones": zones, "hottest": {"name": hottest_name.trim_suffix("-thermal"), "c": hottest}}


## This process's CPU time in seconds (user + system), from /proc/self/stat; null elsewhere.
static func process_cpu_seconds() -> Variant:
	var t: Variant = read_text("/proc/self/stat")
	if t == null:
		return null
	# Fields after the command name (which may contain spaces) start after the last ')'.
	var rest := str(t).substr(str(t).rfind(")") + 2).split(" ")
	if rest.size() < 13:
		return null
	# utime and stime are fields 14 and 15 of the line: 12 and 13 after the name.
	return (rest[11].to_int() + rest[12].to_int()) / 100.0
