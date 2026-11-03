extends SceneTree

## Unit tests for scripts/play/end_time.gd (wall-clock end time, ideas #36).
## Run: godot --headless --xr-mode off --path app --script res://tests/test_end_time.gd

const EndTime := preload("res://scripts/play/end_time.gd")

var _failures := 0


func _init() -> void:
	# 2026-10-31 22:00:00 UTC, a Saturday.
	var now := float(Time.get_unix_time_from_datetime_string("2026-10-31T22:00:00"))
	_eq(EndTime.clock_at(now, 0), "22:00")
	_eq(EndTime.clock_at(now, 60), "23:00")
	_eq(EndTime.clock_at(now, -300), "17:00")
	_eq(EndTime.format_end(80 * 60, 1.0, now, 0), "ends 23:20")
	_eq(EndTime.format_end(80 * 60, 2.0, now, 0), "ends 22:40")
	_eq(EndTime.format_end(3 * 3600 + 10 * 60, 1.0, now, 0), "ends 01:10 tomorrow")
	_eq(EndTime.format_end(50 * 3600, 1.0, now, 0), "ends 00:00 Tue")
	_eq(EndTime.format_end(0.0, 1.0, now, 0), "")
	_eq(EndTime.format_end(-5.0, 1.0, now, 0), "")
	# A time zone ahead moves the day boundary: 22:00 UTC is 00:00 the next day at +120.
	_eq(EndTime.format_end(30 * 60, 1.0, now, 120), "ends 00:30")
	_eq(EndTime.format_end(30 * 60, 1.0, now, 60), "ends 23:30")
	_eq(EndTime.format_end(90 * 60, 1.0, now, 60), "ends 00:30 tomorrow")
	_eq(EndTime.format_remaining(84 * 60 + 5), "1:24 left")
	_eq(EndTime.format_remaining(8 * 60 + 59), "8 min left")
	_eq(EndTime.format_remaining(20), "<1 min left")
	_eq(EndTime.format_remaining(0), "")
	_check("end_unix", is_equal_approx(EndTime.end_unix(600, 1.0, now), now + 600))
	EndTime.use_24h = false
	_eq(EndTime.clock_at(now, 0), "10:00 pm")
	_eq(EndTime.clock_at(now + 2 * 3600, 0), "12:00 am")
	_eq(EndTime.clock_at(now - 10 * 3600, 0), "12:00 pm")
	EndTime.use_24h = true
	# The system's own time zone: just that it formats.
	_check("system clock '%s'" % EndTime.format_end(60), EndTime.format_end(60).begins_with("ends "))
	print("test_end_time: %s" % ("all passed" if _failures == 0 else "%d FAILED" % _failures))
	quit(_failures)


func _eq(got: String, want: String) -> void:
	_check("'%s' == '%s'" % [got, want], got == want)


func _check(what: String, ok: bool) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL " + what)
