extends Node

## Controller battery warning (idea #75): a quiet warning before a controller dies mid-film.
##
## Source: the engine has no OpenXR call for controller batteries, and OpenXR has no standard one. Linux lists
## peripheral batteries under /sys/class/power_supply with scope "Device" (the headset's own gauge has scope "System"
## or none and is the battery forecast's, #2). Whether the headset's controllers appear there is not known yet: the
## first poll logs every Device battery it sees, or that there are none, for the morning check. The side comes from
## the entry's name or model ("left", "right", "_l", "_r"); otherwise it is just "controller".
## Desktop stub: --fake-controller-battery=left:12,right:80 (percentages) instead of the files.
##
## Signals low(side, percent) once per threshold and controller (15 % and 5 %), and changed(levels) after each poll.

signal low(side: String, percent: int)
signal changed(levels: Dictionary)

const ROOT := "/sys/class/power_supply"
const POLL_SECONDS := 60.0
const THRESHOLDS: Array[int] = [15, 5]

## side -> percent, from the last poll.
var levels := {}
var _warned := {}
var _left := 0.0
var _fake := {}
var _logged := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fake-controller-battery="):
			for part in arg.trim_prefix("--fake-controller-battery=").split(",", false):
				_fake[part.get_slice(":", 0)] = part.get_slice(":", 1).to_int()
	poll.call_deferred()


func _process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0:
		poll()


## Reads the batteries now (also every POLL_SECONDS) and warns once per threshold.
func poll() -> void:
	_left = POLL_SECONDS
	levels = _fake.duplicate() if not _fake.is_empty() else read_levels(ROOT, not _logged)
	_logged = true
	for side: String in levels:
		var pct := int(levels[side])
		for t in THRESHOLDS:
			var key := "%s@%d" % [side, t]
			if pct <= t and not _warned.has(key):
				_warned[key] = true
				low.emit(side, pct)
				break
		if pct > THRESHOLDS[0] + 5:
			# Charged again: warn again next time.
			for t in THRESHOLDS:
				_warned.erase("%s@%d" % [side, t])
	changed.emit(levels)


## side -> percent for the Device batteries under root. log: print what was found.
static func read_levels(root: String, log := false) -> Dictionary:
	var out := {}
	var seen: Array[String] = []
	if DirAccess.dir_exists_absolute(root):
		for d in DirAccess.get_directories_at(root):
			var dir := root.path_join(d)
			if _read(dir, "type") != "Battery" or _read(dir, "scope") != "Device":
				continue
			var cap := _read(dir, "capacity")
			if cap == "":
				continue
			var label := (d + " " + _read(dir, "model_name")).to_lower()
			var side := "controller"
			if label.contains("left") or label.contains("_l") or label.ends_with(" l"):
				side = "left"
			elif label.contains("right") or label.contains("_r") or label.ends_with(" r"):
				side = "right"
			if out.has(side):
				side = "%s %s" % [side, d]
			out[side] = cap.to_int()
			seen.append("%s (%s, %s %%)" % [d, _read(dir, "model_name"), cap])
	if log:
		print("Controller batteries: %s" % (", ".join(seen) if not seen.is_empty()
				else "none under %s with scope Device" % root))
	return out


static func _read(dir: String, file: String) -> String:
	# sysfs files report a 4096-byte size but hold one short line: get_as_text() fails with
	# "r != len" (seen on the headset, 2026-10-31); get_line() reads what is there.
	var f := FileAccess.open(dir.path_join(file), FileAccess.READ)
	return f.get_line().strip_edges() if f != null else ""


## "Left controller 12 %, right 80 %", or "" when nothing is known.
func text() -> String:
	var parts: Array[String] = []
	for side: String in levels:
		parts.append("%s %d %%" % [side, int(levels[side])])
	return ("Controller battery: " + ", ".join(parts)) if not parts.is_empty() else ""
