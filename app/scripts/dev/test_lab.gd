extends RefCounted

## The test lab (idea #48; docs/test-lab.md): the calibration cards (scripts/video/lab_video_source.gd, "lab://"
## paths) and a bandwidth meter for files on a share. Registered with the shared commands (command_host.gd), so the
## pane, the PC link and the phone remote all reach it:
##   lab_cards                 the cards: [{path, label, description}]; open one with `open lab://alignment`
##   bandwidth_test {path}     reads a file (smb:// or local) as fast as the demuxer takes it for a few seconds,
##                             seeking around so the read-ahead keeps refilling; reports the throughput
## For the pane's System tab (app-shell):
##   TestLab.cards()                               the list, then main.open_path(card.path)
##   var r: Dictionary = await TestLab.measure_async(tree, "smb://pc/Movies/a.mkv", 8.0)

const DevCommands := preload("res://scripts/dev/dev_commands.gd")
const LabVideoSource := preload("res://scripts/video/lab_video_source.gd")
const NetworkHosts := preload("res://scripts/net/network_hosts.gd")

const SEEK_EVERY_MS := 1500
const SAMPLE_MS := 500
const WorkerTask := preload("res://scripts/dev/worker_task.gd")

## scripts/dev/command_host.gd
var host: Node


func register_all() -> void:
	DevCommands.register("lab_cards", _cmd_cards, {
		"description": "The test lab's calibration cards (open one: open_test_card, or open lab://<card>).",
		"returns": "[{path, label, description}]", "assistant": "read"})
	DevCommands.register("bandwidth_test", _cmd_bandwidth, {
		"description": "Reads a file (smb:// on a saved host, or on the headset) as fast as possible for a few "
				+ "seconds, seeking around, and reports the throughput (the System tab's Measure bandwidth). Needs the "
				+ "player engine (MediaSource).",
		"params": [{"name": "path", "type": "string", "required": true,
				"description": "The file: smb://<a host saved in the player>/share/... or a path on the headset."},
				{"name": "seconds", "type": "float", "default": 8.0, "description": "How long to read, 2 to 60 seconds."}],
		"level": "control", "returns": "{mbps_avg, mbps_peak, mbps_samples, open_ms, megabytes, network: {...}}",
		"assistant": "control"})


func _cmd_cards(_args: Dictionary, _ctx: DevCommands.Call) -> Variant:
	return cards()


static func cards() -> Array[Dictionary]:
	return LabVideoSource.list_cards()


## Why a path may not be measured, or "": a file on the headset, or on a share of a host saved in the player (never a
## web address: the meter stays on this network).
static func path_refusal(path: String) -> String:
	if NetworkHosts.is_smb(path):
		return "" if not NetworkHosts.find_host(NetworkHosts.host_of(path)).is_empty() \
				else "%s is not a host saved in the player" % NetworkHosts.host_of(path)
	if path.contains("://"):
		return "only smb:// on a saved host, or a file on the headset"
	return "" if path.is_absolute_path() else "give an absolute path on the headset"


func _cmd_bandwidth(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var why := path_refusal(str(args["path"]))
	if why != "":
		return ctx.fail(why)
	var r: Dictionary = await measure_async(host.get_tree(), args["path"], clampf(args["seconds"], 2.0, 60.0))
	if r.has("error"):
		return ctx.fail(r["error"])
	return r


## measure() on a worker thread, awaited frame by frame (never blocks the frame).
static func measure_async(tree: SceneTree, path: String, seconds: float) -> Dictionary:
	var r: Dictionary = await WorkerTask.run(tree, func() -> Variant: return measure(path, seconds))
	return r["result"] if r["result"] is Dictionary else {"error": "no result"}


## Blocking: opens `path` with its own MediaSource, drains the video packets so the demuxer keeps reading, seeks to a
## new place every 1.5 s so the read-ahead refills, and samples the bytes read every 0.5 s.
static func measure(path: String, seconds: float) -> Dictionary:
	if not ClassDB.class_exists("MediaSource"):
		return {"error": "the bandwidth meter needs the player engine (MediaSource)"}
	var src: Object = ClassDB.instantiate("MediaSource")
	NetworkHosts.apply_credentials(src, path)
	var t_open := Time.get_ticks_msec()
	var err: int = src.call("open", path)
	var open_ms := Time.get_ticks_msec() - t_open
	if err != OK:
		return {"error": "can't open %s: %s" % [path, src.call("get_last_error")]}
	var duration: float = src.call("get_duration")
	var network: bool = NetworkHosts.is_smb(path)
	var key := "net_bytes_read" if network else "bytes_read"
	var start_bytes := int((src.call("get_stats") as Dictionary).get(key, 0))
	var last_bytes := start_bytes
	var t0 := Time.get_ticks_msec()
	var last_t := t0
	var next_seek := t0 + SEEK_EVERY_MS
	var samples: Array[float] = []
	var rng := RandomNumberGenerator.new()
	while Time.get_ticks_msec() - t0 < int(seconds * 1000.0):
		while not (src.call("read_video_packet") as Dictionary).is_empty():
			pass
		OS.delay_msec(20)
		var now := Time.get_ticks_msec()
		if duration > 10.0 and now >= next_seek:
			src.call("seek", rng.randf_range(0.0, duration * 0.95))
			next_seek = now + SEEK_EVERY_MS
		if now - last_t >= SAMPLE_MS:
			var b := int((src.call("get_stats") as Dictionary).get(key, 0))
			samples.append(snappedf((b - last_bytes) * 8.0 / ((now - last_t) / 1000.0) / 1e6, 0.1))
			last_bytes = b
			last_t = now
	var stats: Dictionary = src.call("get_stats")
	var total := int(stats.get(key, 0)) - start_bytes
	var elapsed := maxf((Time.get_ticks_msec() - t0) / 1000.0, 0.001)
	src.call("close")
	var peak := 0.0
	for s in samples:
		peak = maxf(peak, s)
	var out := {"path": path, "mbps_avg": snappedf(total * 8.0 / elapsed / 1e6, 0.1), "mbps_peak": peak,
			"mbps_samples": samples, "open_ms": open_ms, "megabytes": snappedf(total / 1e6, 0.1),
			"seconds": snappedf(elapsed, 0.1)}
	if network:
		out["network"] = {"refill_mbps": stats.get("net_refill_mbps", 0.0), "stalls": stats.get("net_stalls", 0),
				"reconnects": stats.get("net_reconnects", 0), "requests": stats.get("net_requests", 0)}
	return out
