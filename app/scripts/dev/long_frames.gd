extends Node

## Long frames in the log (a check for the picture breaking up at an event: a tab's first show, the browser's start).
## On with --long-frames or [dev] long_frames=true in user://settings.cfg (Steam starts the app with no flags). Off, the
## script is not loaded.
##
## One line for each frame that took more than LIMIT refresh periods, with what the panel shows, so a fault seen in
## the headset can be set beside the frame times:
##   Long frame: 48.3 ms at 231.42 s (72 Hz; panel: Objects)
## At most MAX_A_SECOND lines a second; the rest are counted in the next line ("+N more"). Each line also has the main
## viewport's measured render times (cpu, gpu) and the script time of the frame before.
##
## Every second also one summary line, so a run with the fault and one without can be compared:
##   Frames: 72 in 1.00 s, mean 13.9 max 14.6 ms; gpu mean 7.5 max 7.9; cpu 0.4; script 5.1; panel: Files
## (The main viewport can't be read back in XR: get_image() gives black, tried 2026-11-22.)

const LIMIT := 1.5
const MAX_A_SECOND := 20

var main: Node
var _last_usec := 0
var _second := -1
var _lines := 0
var _skipped := 0
var _sum_start := 0
var _n := 0
var _ms_sum := 0.0
var _ms_max := 0.0
var _gpu_sum := 0.0
var _gpu_max := 0.0
var _cpu_sum := 0.0


static func attach(m: Node, args: Dictionary) -> void:
	if not args.has("long-frames") and not bool(m.settings.get_value("dev", "long_frames", false)):
		return
	var n: Node = (load("res://scripts/dev/long_frames.gd") as GDScript).new()
	n.name = "LongFrames"
	n.main = m
	m.add_child(n)
	RenderingServer.viewport_set_measure_render_time(m.get_viewport().get_viewport_rid(), true)
	print("Long frames: logged (more than %.1f refresh periods)" % LIMIT)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var ms := (now - _last_usec) / 1000.0
	var first := _last_usec == 0
	_last_usec = now
	if first:
		return
	var vp := main.get_viewport().get_viewport_rid()
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(vp)
	var cpu := RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
	_n += 1
	_ms_sum += ms
	_ms_max = maxf(_ms_max, ms)
	_gpu_sum += gpu
	_gpu_max = maxf(_gpu_max, gpu)
	_cpu_sum += cpu
	if now - _sum_start >= 1000000:
		if _sum_start > 0:
			print("Frames: %d in %.2f s, mean %.1f max %.1f ms; gpu mean %.1f max %.1f; cpu %.1f; script %.1f; %s" % [
					_n, (now - _sum_start) / 1e6, _ms_sum / _n, _ms_max, _gpu_sum / _n, _gpu_max, _cpu_sum / _n,
					Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, _showing()])
		_sum_start = now
		_n = 0
		_ms_sum = 0.0
		_ms_max = 0.0
		_gpu_sum = 0.0
		_gpu_max = 0.0
		_cpu_sum = 0.0
	var hz := _refresh()
	if ms <= LIMIT * 1000.0 / hz:
		return
	var second := int(now / 1000000)
	if second != _second:
		_second = second
		_lines = 0
	if _lines >= MAX_A_SECOND:
		_skipped += 1
		return
	_lines += 1
	var more := " +%d more" % _skipped if _skipped > 0 else ""
	_skipped = 0
	print("Long frame: %.1f ms at %.2f s (%d Hz; %s; cpu %.1f gpu %.1f)%s" % [ms, now / 1e6, roundi(hz), _showing(), cpu,
			gpu, more])



func _refresh() -> float:
	var xr := XRServer.find_interface("OpenXR") as OpenXRInterface
	if main.use_xr and xr != null and xr.display_refresh_rate > 0.0:
		return xr.display_refresh_rate
	var hz := DisplayServer.screen_get_refresh_rate()
	return hz if hz > 0.0 else 60.0


func _showing() -> String:
	if not bool(main.menu_shown) or main.ui == null:
		return "panel: closed"
	var ui: Variant = main.ui.get("ui")
	if ui == null:
		return "panel: open"
	var names: Array = ui.TAB_NAMES
	return "panel: %s" % names[clampi(int(ui.current_tab), 0, names.size() - 1)]
