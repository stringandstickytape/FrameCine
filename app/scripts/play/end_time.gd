extends RefCounted

## Wall-clock end time (ideas #36): "ends 23:20" wherever a remaining duration is shown. Static helpers only;
## preload to use (no class_name, see video_mode.gd).
##   EndTime.format_end(remaining_seconds)      -> "ends 23:20" ("ends 01:10 tomorrow" past midnight)
##   EndTime.clock_at(unix_seconds)             -> "23:20" (local time)
##   EndTime.format_remaining(remaining_seconds) -> "1:24 left" / "8 min left"
## The clock is local time from the system's time zone. 24-hour by default; use_24h = false gives "11:20 pm".

## Settings: [display] clock_24h.
static var use_24h := true


## Local "HH:MM" of a Unix time. bias_minutes: the time zone's offset from UTC (default: the system's).
static func clock_at(unix: float, bias_minutes: Variant = null) -> String:
	var t := Time.get_time_dict_from_unix_time(int(floor(unix)) + _bias(bias_minutes) * 60)
	if use_24h:
		return "%02d:%02d" % [t["hour"], t["minute"]]
	var h := int(t["hour"]) % 12
	return "%d:%02d %s" % [12 if h == 0 else h, t["minute"], "am" if int(t["hour"]) < 12 else "pm"]


## "ends 23:20" for something that ends `remaining` seconds from now (at `speed` times real time). An end on a later
## local day says so: "ends 01:10 tomorrow", or the weekday further out. "" when remaining is not positive.
## localised: in the menus' language (the menu's header, docs/i18n.md); else English, as an assistant reads it.
static func format_end(remaining: float, speed := 1.0, now_unix: float = -1.0, bias_minutes: Variant = null,
		localised := false) -> String:
	if remaining <= 0.0 or speed <= 0.0:
		return ""
	var now := now_unix if now_unix >= 0.0 else Time.get_unix_time_from_system()
	var end := now + remaining / speed
	if localised:
		var day := _day_suffix(now, end, bias_minutes).strip_edges()
		var at := clock_at(end, bias_minutes)
		if day == "":
			return TranslationServer.translate("ends %s") % at
		if day == "tomorrow":
			return TranslationServer.translate("ends %s tomorrow") % at
		return TranslationServer.translate("ends %s %s") % [at, TranslationServer.translate(day)]
	return "ends " + clock_at(end, bias_minutes) + _day_suffix(now, end, bias_minutes)


## The end time as a Unix time (for comparisons, such as battery versus film).
static func end_unix(remaining: float, speed := 1.0, now_unix: float = -1.0) -> float:
	var now := now_unix if now_unix >= 0.0 else Time.get_unix_time_from_system()
	return now + maxf(remaining, 0.0) / maxf(speed, 0.001)


## "1:24 left" (hours:minutes) for an hour or more, "8 min left" below, "<1 min left" at the very end. localised: in
## the menus' language.
static func format_remaining(remaining: float, localised := false) -> String:
	if remaining <= 0.0:
		return ""
	var m := int(remaining / 60.0)
	if m >= 60:
		return (TranslationServer.translate("%d:%02d left") if localised else "%d:%02d left") % [m / 60, m % 60]
	if m >= 1:
		return (TranslationServer.translate("%d min left") if localised else "%d min left") % m
	return TranslationServer.translate("<1 min left") if localised else "<1 min left"


## " tomorrow" or " Sat" when `end` falls on a later local day than `now`, else "".
static func _day_suffix(now: float, end: float, bias_minutes: Variant) -> String:
	var b := _bias(bias_minutes) * 60
	var day_now := floori((now + b) / 86400.0)
	var day_end := floori((end + b) / 86400.0)
	if day_end <= day_now:
		return ""
	if day_end == day_now + 1:
		return " tomorrow"
	var names := ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"] # i18n
	var wd: int = Time.get_datetime_dict_from_unix_time(int(end) + b)["weekday"]
	return " " + names[wd]


static func _bias(bias_minutes: Variant) -> int:
	if bias_minutes != null:
		return int(bias_minutes)
	return int(Time.get_time_zone_from_system().get("bias", 0))
