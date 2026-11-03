extends Node

## The A/V offset per display refresh rate (ideas #24): the picture's delay through the display differs at 72, 90 and
## 120 Hz, so the offset found with the A/V sync card (lab://av_sync: a flash and a beep each second) is remembered
## for the rate it was set at, and put back whenever the display runs at that rate again. main.set_av_offset() (the
## Sound tab's slider) calls remember(); the plain [audio] av_offset stays the value for rates never set.
##
##   refresh_rate() -> int        the display's rate now (the XR runtime's, else the screen's), 0 if unknown
##   remember(seconds)            store for the rate now
##   offset_for(rate) -> Variant  the stored offset, or null
##   rate_override                tests: a rate to use instead of the display's (0: the display's)
##   signal applied(rate, seconds)
## Settings: [audio] av_offset_<rate> (seconds). The display's rate is checked every CHECK_SECONDS.

signal applied(rate: int, seconds: float)

const CHECK_SECONDS := 2.0

var main: Node3D
var rate_override := 0
var _rate := -1
var _since := 0.0


func _ready() -> void:
	_check()


func refresh_rate() -> int:
	if rate_override > 0:
		return rate_override
	var xr := XRServer.find_interface("OpenXR")
	if xr != null and xr.is_initialized() and "display_refresh_rate" in xr:
		var r := float(xr.get("display_refresh_rate"))
		if r > 0.0:
			return roundi(r)
	var s := DisplayServer.screen_get_refresh_rate()
	return roundi(s) if s > 0.0 else 0


func offset_for(rate: int) -> Variant:
	if rate <= 0 or not main.settings.has_value("audio", "av_offset_%d" % rate):
		return null
	return float(main.settings.get_value("audio", "av_offset_%d" % rate, 0.0))


func remember(seconds: float) -> void:
	var rate := refresh_rate()
	if rate > 0:
		main.settings.set_value("audio", "av_offset_%d" % rate, seconds)


func _process(delta: float) -> void:
	_since += delta
	if _since >= CHECK_SECONDS:
		_since = 0.0
		_check()


func _check() -> void:
	var rate := refresh_rate()
	if rate == _rate:
		return
	_rate = rate
	var v: Variant = offset_for(rate)
	if v != null:
		main.player.av_offset = float(v)
		applied.emit(rate, float(v))
