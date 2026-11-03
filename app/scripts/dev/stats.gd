extends Node

## Stats for nerds (idea #57): one dictionary with the render, video, decoder, GPU, power and thermal numbers, for the
## dev link (`stats` command and event) and for the pane. Add it as a child while someone looks (the dev tools keep
## one; the pane's System tab can make its own), call collect() a few times a second at most, and free it when done.
## While in the tree it records each frame's time for the histogram (one array append a frame); out of the tree it
## costs nothing.
##
##   var stats := preload("res://scripts/dev/stats.gd").new()
##   stats.main = main
##   add_child(stats)
##   ... stats.collect() -> Dictionary;  Stats.summary_lines(d) -> Array[String] for a text view
##
## Rates (decode fps, bitrate, CPU) are measured between two collect() calls of the same instance.

const Sysfs := preload("res://scripts/dev/sysfs.gd")
const Benchmark := preload("res://scripts/dev/benchmark.gd")

## Histogram bucket upper edges in ms: 180, 120, 90, 72, 60 Hz frames, then slow frames. The last bucket is open.
const EDGES_MS: Array[float] = [5.6, 8.3, 11.1, 13.9, 16.7, 20.0, 25.0, 33.3, 50.0, 100.0]
const MAX_SAMPLES := 20000

## scripts/main.gd
var main: Node
var _frame_ms := PackedFloat32Array()
var _last_usec := 0
var _prev := {}


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_usec > 0 and _frame_ms.size() < MAX_SAMPLES:
		_frame_ms.append((now - _last_usec) / 1000.0)
	_last_usec = now


## Everything, measured since the previous collect().
func collect() -> Dictionary:
	var now_usec := Time.get_ticks_usec()
	var seconds := (now_usec - int(_prev.get("usec", now_usec))) / 1e6
	var out := {"t": Time.get_unix_time_from_system(), "interval_s": snappedf(seconds, 0.001)}
	out["render"] = _render()
	out["frames"] = _frames()
	out["video"] = _video(seconds)
	out["gpu"] = Sysfs.gpu()
	out["battery"] = Sysfs.battery()
	out["thermal"] = Sysfs.thermal()
	var cpu: Variant = Sysfs.process_cpu_seconds()
	if cpu != null and _prev.has("cpu") and seconds > 0.0:
		out["cpu"] = {"process_percent_of_core": snappedf((cpu - float(_prev["cpu"])) / seconds * 100.0, 0.1)}
	# The self-benchmark (benchmark.gd): what the device decoded on its own run, and a run in progress.
	if main != null and is_instance_valid(main):
		var bench := Benchmark.report(main.settings)
		if not bench.is_empty():
			out["benchmark"] = bench
	_prev["usec"] = now_usec
	_prev["cpu"] = cpu
	return out


func _render() -> Dictionary:
	return {
		"fps": Engine.get_frames_per_second(),
		"process_ms": snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.01),
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"video_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"static_mem_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
	}


## Frame times since the last collect(): count, average, percentiles, max and the histogram.
func _frames() -> Dictionary:
	var samples := _frame_ms
	_frame_ms = PackedFloat32Array()
	if samples.is_empty():
		return {"count": 0}
	var sorted := samples.duplicate()
	sorted.sort()
	var counts: Array[int] = []
	counts.resize(EDGES_MS.size() + 1)
	counts.fill(0)
	var total := 0.0
	for ms in samples:
		total += ms
		var i := EDGES_MS.size()
		for k in EDGES_MS.size():
			if ms <= EDGES_MS[k]:
				i = k
				break
		counts[i] += 1
	var n := sorted.size()
	return {
		"count": n,
		"avg_ms": snappedf(total / n, 0.01),
		"p50_ms": snappedf(sorted[n / 2], 0.01),
		"p95_ms": snappedf(sorted[mini(n - 1, n * 95 / 100)], 0.01),
		"p99_ms": snappedf(sorted[mini(n - 1, n * 99 / 100)], 0.01),
		"max_ms": snappedf(sorted[n - 1], 0.01),
		"histogram": {"edges_ms": EDGES_MS, "counts": counts},
	}


func _video(seconds: float) -> Dictionary:
	if main == null or not is_instance_valid(main) or main.player.source == null:
		return {}
	var src: Object = main.player.source
	var info: Dictionary = src.get_video_info()
	var s: Dictionary = src.get_stats()
	var out := {"kind": src.get_kind(), "path": main.current_path, "width": info.get("width", 0),
			"height": info.get("height", 0), "codec": info.get("codec", ""),
			"decode_path": s.get("decode_path", ""), "playing": main.player.is_playing()}
	var decoded := int(s.get("frames_decoded", 0))
	var dropped := int(s.get("frames_dropped", 0))
	out["frames_dropped"] = dropped
	if seconds > 0.0 and _prev.has("decoded"):
		out["decode_fps"] = snappedf(maxi(0, decoded - int(_prev["decoded"])) / seconds, 0.1)
		out["dropped_since_last"] = maxi(0, dropped - int(_prev.get("dropped", dropped)))
	_prev["decoded"] = decoded
	_prev["dropped"] = dropped
	# Decoder queue depth: access units in the driver (OUTPUT), frames in the driver (CAPTURE), frames decoded and
	# waiting to be shown; and the demuxer's video packet queue.
	var queue := {}
	for key: String in ["output_in_driver", "capture_in_driver", "capture_buffers", "frames_ready", "aus_queued",
			"queued_rate", "latency_avg_ms", "latency_max_ms"]:
		if s.has(key):
			queue[key] = s[key]
	var media: Variant = src.get("_media")
	var m: Dictionary = media.get_stats() if media != null and media.has_method("get_stats") else {}
	for key: String in ["video_queue", "video_queue_bytes", "decoder_queue_depth", "video_packets_queued"]:
		if m.has(key):
			queue[key] = m[key]
	out["queue"] = queue
	# Bitrate: the video bytes the demuxer read between two calls (MediaSource), else the engine's own figure.
	if m.has("bitrate_bps"):
		out["bitrate_mbps"] = snappedf(float(m["bitrate_bps"]) / 1e6, 0.01)
	elif m.has("video_bytes") and seconds > 0.0 and _prev.has("video_bytes"):
		out["bitrate_mbps"] = snappedf(maxi(0, int(m["video_bytes"]) - int(_prev["video_bytes"])) * 8.0 / seconds / 1e6,
				0.01)
	if m.has("video_bytes"):
		_prev["video_bytes"] = int(m["video_bytes"])
	if bool(s.get("network", false)):
		out["network"] = {"mbps": s.get("net_average_mbps", 0.0), "buffered_mb": snappedf(
				float(s.get("net_buffered_bytes", 0)) / 1e6, 0.1), "stalls": s.get("net_stalls", 0),
				"reconnects": s.get("net_reconnects", 0)}
	return out


## A few lines of text for a pane or overlay view of collect()'s result.
static func summary_lines(d: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var f: Dictionary = d.get("frames", {})
	var r: Dictionary = d.get("render", {})
	if int(f.get("count", 0)) > 0:
		lines.append("frame %.1f ms avg, p95 %.1f, max %.1f | %d fps | %d draws" % [f["avg_ms"], f["p95_ms"],
				f["max_ms"], r.get("fps", 0), r.get("draw_calls", 0)])
	var v: Dictionary = d.get("video", {})
	if not v.is_empty():
		var q: Dictionary = v.get("queue", {})
		lines.append("%s %dx%d %s | decode %s fps | dropped %d | %s Mbit/s" % [v.get("kind", ""), v.get("width", 0),
				v.get("height", 0), v.get("decode_path", ""), v.get("decode_fps", "-"), v.get("frames_dropped", 0),
				v.get("bitrate_mbps", "-")])
		if not q.is_empty():
			lines.append("queue: driver in %s out %s, ready %s, demux %s" % [q.get("output_in_driver", "-"),
					q.get("capture_in_driver", "-"), q.get("frames_ready", "-"), q.get("video_queue", "-")])
	var g: Dictionary = d.get("gpu", {})
	var b: Dictionary = d.get("battery", {})
	var t: Dictionary = d.get("thermal", {})
	var parts: Array[String] = []
	if not g.is_empty():
		parts.append("GPU %s MHz%s" % [g.get("clock_mhz", "-"),
				(", %s%%" % g["load_percent"]) if g.get("load_percent") != null else ""])
	if b.has("power_w"):
		parts.append("%.1f W" % b["power_w"])
	if not t.is_empty():
		parts.append("hottest %s %.0f C" % [t["hottest"]["name"], t["hottest"]["c"]])
	if d.has("cpu"):
		parts.append("CPU %.0f%% of a core" % d["cpu"]["process_percent_of_core"])
	if not parts.is_empty():
		lines.append(" | ".join(parts))
	var bench: Dictionary = d.get("benchmark", {})
	if bench.has("running"):
		lines.append("benchmark: %s" % bench["running"]["text"])
	elif bench.has("summary"):
		lines.append("benchmark: %s" % bench["summary"])
	return lines
