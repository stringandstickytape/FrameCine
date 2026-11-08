extends Node

## Self-benchmark (idea #82; docs/benchmark.md): decodes the biggest video file in a folder for 10 s as fast as the
## decoder goes, and reports what the device can do: decoded frames per second, how many times real time that is,
## the pixel rate, and an estimate for common sizes. The result goes into the settings ([benchmark] result) and into
## the stats dictionary (stats.gd, key "benchmark"), so the pane, the PC link and the phone see it.
##
## It runs:
##   - once on the first run, by itself, when the app has been idle (nothing playing) for 8 s. It picks the biggest
##     container file in the last file's folder or the local places (Videos, Downloads, home, removable media; one
##     level of subfolders). It gives up when the user opens a file, and tries again next start (3 tries at most).
##     [benchmark] auto = false turns that off; --no-save runs (tests) never start it.
##   - with --benchmark (or --benchmark=FOLDER_OR_FILE) at start, after 2 s, whatever was saved before.
##   - with the `benchmark` command (path, seconds), and from the pane:
##       var b := Benchmark.start(main, folder_or_file)      # "" picks a file; Benchmark.running() while it runs
##       b.progress.connect(func(fraction, text): ...);  var r: Dictionary = await b.finished
##       Benchmark.saved(main.settings)                       # the last result, {} if none
##
## How: its own MediaSource (audio off) and HWVideoTexture, not the player's. The texture's clock is kept LEAD seconds
## ahead of the newest frame shown, so the decoder is fed without pacing and each rendered frame shows the newest
## decoded frame (the rest count as dropped, as late frames do in playback). That is decode plus import, the work
## playback does, without the display's cadence. It needs the player engine (HWVideoTexture and MediaSource).

signal progress(fraction: float, text: String)
signal finished(result: Dictionary)

const HWVideoSource := preload("res://scripts/video/hw_video_source.gd")
const VideoSourceFactory := preload("res://scripts/video/video_source_factory.gd")
const DirectoryLister := preload("res://scripts/net/directory_lister.gd")
const NetworkHosts := preload("res://scripts/net/network_hosts.gd")
const Sysfs := preload("res://scripts/dev/sysfs.gd")
const DevCommands := preload("res://scripts/dev/dev_commands.gd")

const NODE_NAME := "SelfBenchmark"
const SECTION := "benchmark"
const VERSION := 1
const DEFAULT_SECONDS := 10.0
## The texture's clock leads the newest frame shown by this much.
const LEAD := 2.0
const IDLE_BEFORE_AUTO := 8.0
const AUTO_TRIES := 3
const FIRST_FRAME_TIMEOUT := 15.0
const SAMPLE_S := 0.5
## Files tried when the biggest one does not open (an unsupported codec).
const MAX_CANDIDATES := 3
const WorkerTask := preload("res://scripts/dev/worker_task.gd")
const SystemDirs := preload("res://scripts/system_dirs.gd")

## Sizes the estimate is given for: [label, width, height, fps]. Same codec and decode path as the file measured.
const TARGETS: Array = [
	["1080p 60", 1920, 1080, 60.0],
	["4K 30", 3840, 2160, 30.0],
	["4K 60", 3840, 2160, 60.0],
	["5.7K 180/360 30", 5760, 2880, 30.0],
	["8K 180/360 30", 7680, 3840, 30.0],
	["8K 180/360 60", 7680, 3840, 60.0],
]

## scripts/main.gd
var main: Node
## A file or a folder; "" picks a file.
var path := ""
var seconds := DEFAULT_SECONDS
## Write the result to the settings.
var save := true
## The first-run benchmark: waits for idle, stops when the user opens a file.
var auto := false
var delay := 0.0
var result := {}
var _abort := ""
## The measurement began (an auto run cancelled before that does not count as a try).
var _started := false
var _fraction := 0.0
var _text := "waiting"


## main.gd calls this at the end of _ready(). Returns the node, or null when nothing is to run.
static func attach(m: Node, args: Dictionary) -> Node:
	if args.has("benchmark"):
		var target: Variant = args["benchmark"]
		var b := start(m, "" if target is bool else str(target), false)
		if b != null:
			b.delay = 2.0
			b.finished.connect(func(r: Dictionary) -> void: print("Benchmark: %s" % JSON.stringify(r)))
		return b
	var s: Object = m.settings
	if s.read_only or not bool(s.get_value(SECTION, "auto", true)) or not saved(s).is_empty():
		return null
	if int(s.get_value(SECTION, "tries", 0)) >= AUTO_TRIES or not is_supported():
		return null
	return start(m, "", true)


## True when this engine build can run it (HWVideoTexture and MediaSource).
static func is_supported() -> bool:
	return HWVideoSource.is_available() and HWVideoSource.has_media_source()


## Starts a run under the scene root (or returns the one running). path: a file or folder, "" picks one.
static func start(m: Node, p_path := "", p_auto := false, p_seconds := DEFAULT_SECONDS) -> Node:
	var running_now := running()
	if running_now != null:
		return running_now
	var b: Node = (load("res://scripts/dev/benchmark.gd") as GDScript).new()
	b.name = NODE_NAME
	b.main = m
	b.path = p_path
	b.auto = p_auto
	b.seconds = clampf(p_seconds, 2.0, 60.0)
	if p_auto:
		b.delay = IDLE_BEFORE_AUTO
	m.get_tree().root.add_child.call_deferred(b)
	return b


## The run in progress, or null.
static func running() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NODE_NAME) if tree != null else null


## The last saved result, {} if none.
static func saved(settings: Object) -> Dictionary:
	var r: Variant = settings.get_value(SECTION, "result", {})
	return r if r is Dictionary else {}


## For the stats dictionary: the saved result, and the run in progress.
static func report(settings: Object) -> Dictionary:
	var out := saved(settings).duplicate()
	var b := running()
	if b != null:
		out["running"] = {"fraction": snappedf(b._fraction, 0.01), "text": b._text, "path": b.path}
	return out


## The shared commands (command_host.gd: the pane, the PC link, the phone): `benchmark` runs one and returns the
## result (the stats dictionary carries it after that, key "benchmark").
static func register_commands(host: Node) -> void:
	DevCommands.register("benchmark", func(args: Dictionary, ctx: DevCommands.Call) -> Variant:
		var b := start(host.main, args["path"], false, args["seconds"])
		if b.auto and not b._started:
			# The first-run benchmark is waiting for idle: run now, for this caller.
			b.auto = false
			b.delay = 0.0
			b.path = args["path"]
		var r: Dictionary = await b.finished
		if r.has("error"):
			return ctx.fail(r["error"])
		ctx.summary = r.get("summary", "benchmark")
		return r, {
		"description": "Decodes the biggest video file in a folder (or a given file) as fast as the decoder goes for a "
				+ "few seconds, and reports what the device can do. Saved; `stats` carries it as \"benchmark\".",
		"params": [{"name": "path", "type": "string", "default": "",
				"description": "a file or folder (smb:// too); empty: the last folder or the places"},
				{"name": "seconds", "type": "float", "default": DEFAULT_SECONDS}],
		"level": "control",
		"returns": "{decode_fps, realtime_x, mpix_per_s, can_play: [{label, fps_estimate, ok}], summary, ...}"})


## Asks the run to stop; finished() comes with {error: reason}.
func cancel(reason := "cancelled") -> void:
	_abort = reason


func _ready() -> void:
	if auto:
		main.file_opened.connect(func(_p: String) -> void: cancel("the user opened a file"))
	_run.call_deferred()


func _report(fraction: float, text: String) -> void:
	_fraction = fraction
	_text = text
	progress.emit(fraction, text)


func _run() -> void:
	var r := await _measure_all()
	r.erase("measured")
	result = r
	if save and main != null and is_instance_valid(main):
		var s: Object = main.settings
		if r.has("error"):
			if auto and _started:
				s.set_value(SECTION, "tries", int(s.get_value(SECTION, "tries", 0)) + 1)
			s.set_value(SECTION, "last_error", r["error"])
		else:
			s.set_value(SECTION, "result", r)
			s.set_value(SECTION, "last_error", null)
		s.save_if_dirty()
	if r.has("error"):
		print("Benchmark: not done: %s" % r["error"])
	else:
		print("Benchmark: %s" % r["summary"])
	_report(1.0, r.get("summary", r.get("error", "")))
	finished.emit(r)
	queue_free()


func _measure_all() -> Dictionary:
	var t_wait := 0.0
	while t_wait < delay or (auto and _busy()):
		if _abort != "":
			return {"error": _abort}
		t_wait = 0.0 if auto and _busy() else t_wait + get_process_delta_time()
		await get_tree().process_frame
	if not is_supported():
		return {"error": "the benchmark needs the player engine (HWVideoTexture and MediaSource)"}
	_started = true
	_report(0.0, "looking for a file")
	var candidates: Array = await _off_thread(func() -> Variant: return pick_files(path, _folders()))
	if candidates.is_empty():
		return {"error": "no video file found in %s" % (path if path != "" else "the last folder or the places")}
	var skipped: Array = []
	for c: Dictionary in candidates.slice(0, MAX_CANDIDATES):
		if _abort != "":
			return {"error": _abort}
		var r := await _measure(c["path"], int(c["size"]))
		if not r.has("error") or r.get("measured", false):
			if not skipped.is_empty():
				r["skipped"] = skipped
			return r
		skipped.append({"path": c["path"], "error": r["error"]})
		print("Benchmark: %s: %s" % [c["path"], r["error"]])
	return {"error": "no file opened: %s" % skipped[0]["error"], "skipped": skipped}


## The app is busy: a file is open (playing or paused).
func _busy() -> bool:
	if main == null or not is_instance_valid(main):
		return false
	var p: Node = main.player
	return main.current_path != "" or (p.source != null and p.is_playing())


## Runs `f` on a worker thread and waits for it frame by frame.
func _off_thread(f: Callable) -> Variant:
	var r: Dictionary = await WorkerTask.run(get_tree(), f)
	return r.get("result")


## Where the first-run benchmark looks: the last file's folder, then the local places.
func _folders() -> Array[String]:
	var out: Array[String] = []
	var last := str(main.settings.get_value("player", "last_file", "")) if main != null else ""
	if last != "" and not last.contains("://"):
		out.append(last.get_base_dir())
	var home := OS.get_environment("HOME")
	for p: String in [SystemDirs.get_dir(OS.SYSTEM_DIR_MOVIES), SystemDirs.get_dir(OS.SYSTEM_DIR_DOWNLOADS),
			"/home/steamos/Videos", "/home/steamos", home.path_join("Videos"), home]:
		if p != "" and p not in out:
			out.append(p)
	for media in ["/run/media", "/mnt"]:
		for d in _subdirs(media):
			out.append(d)
			for s in _subdirs(d):
				out.append(s)
	return out


static func _subdirs(p: String) -> Array[String]:
	var out: Array[String] = []
	if DirAccess.dir_exists_absolute(p):
		for d in DirAccess.get_directories_at(p):
			out.append(p.path_join(d))
	return out


## Blocking (a worker thread): the container files to try, biggest first: [{path, size}]. `target` is a file, a
## folder (local or smb://), or "" for `folders` (local; each with one level of subfolders).
static func pick_files(target: String, folders: Array[String]) -> Array:
	var found: Array = []
	if target != "" and _is_candidate(target) and (NetworkHosts.is_smb(target) or FileAccess.file_exists(target)):
		var fa := FileAccess.open(target, FileAccess.READ) if not NetworkHosts.is_smb(target) else null
		return [{"path": target, "size": fa.get_length() if fa != null else 0}]
	var roots: Array[String] = folders
	if target != "":
		roots = [target]
	for root in roots:
		var listing := DirectoryLister.list(root)
		for e: Dictionary in listing["entries"]:
			var child := root.trim_suffix("/") + "/" + str(e["name"])
			if not e["is_dir"] and _is_candidate(e["name"]):
				found.append({"path": child, "size": int(e["size"])})
			elif e["is_dir"] and not NetworkHosts.is_smb(root) and not str(e["name"]).begins_with("."):
				# One level down (films in their own folders); local only, a share listing costs a round trip each.
				for f in DirectoryLister.list(child)["entries"]:
					if not f["is_dir"] and _is_candidate(f["name"]):
						found.append({"path": child + "/" + str(f["name"]), "size": int(f["size"])})
		if target == "" and not found.is_empty():
			break
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["size"]) > int(b["size"]))
	return found


## Container files only (raw .h264/.hevc streams have no timing to measure against).
static func _is_candidate(p: String) -> bool:
	return VideoSourceFactory.is_video_file(p) and not HWVideoSource.is_raw_stream(p)


func _measure(file: String, size: int) -> Dictionary:
	_report(0.0, "opening %s" % file.get_file())
	var t_open := Time.get_ticks_msec()
	var opened: Dictionary = await _off_thread(func() -> Variant: return HWVideoSource.open_media_blocking(file))
	var open_ms := Time.get_ticks_msec() - t_open
	var media: Object = opened["media"]
	if opened["err"] != OK:
		return {"error": opened["error"]}
	var info: Dictionary = media.call("get_video_info")
	var duration: float = media.call("get_duration")
	if not (media.call("get_audio_tracks") as Array).is_empty():
		media.call("select_audio_track", -1)
	# Start a fifth of the way in: past titles and black openings, which decode faster than the film.
	var start_at := duration * 0.2 if duration > seconds * 4.0 else 0.0
	if start_at > 0.0:
		media.call("seek", start_at)
	var tex: Object = ClassDB.instantiate("HWVideoTexture")
	HWVideoSource.apply_hw_vp9(tex)
	var err: Error = tex.call("open_source", media)
	if err != OK:
		var why := "%s (%s)" % [tex.call("get_last_error"), error_string(err)]
		media.call("close")
		return {"error": why}
	tex.call("play")
	var content_fps := float(info.get("fps", 0.0))
	var t0 := Time.get_ticks_msec()
	var t_first := -1
	var decoded0 := 0
	var shown0 := 0
	var dropped0 := 0
	var cpu0 := 0.0
	var last_sample := 0
	var last_decoded := 0
	var samples: Array[float] = []
	var gpu_mhz: Array[int] = []
	var stats: Dictionary = {}
	var loops := 0
	# After a loop's seek, until a frame from the new place shows, the clock follows the seek target, not the last
	# frame shown (the end of the file).
	var shown_at_seek := -1
	var error := ""
	while true:
		await get_tree().process_frame
		var shown_now := int(stats.get("frames_shown", 0))
		var base: float = start_at if shown_now == shown_at_seek else maxf(float(tex.call("get_frame_time")), start_at)
		tex.call("update", get_process_delta_time(), base + LEAD)
		stats = tex.call("get_stats")
		var now := Time.get_ticks_msec()
		var decoded := int(stats.get("frames_decoded", 0))
		var state := str(stats.get("state_name", ""))
		if state == "error":
			error = str(stats.get("last_error", "decoder error"))
			break
		if _abort != "":
			error = _abort
			break
		if t_first < 0:
			# The window starts at the first frame shown, so opening and the decoder's start are not in it.
			if int(stats.get("frames_shown", 0)) > 0:
				t_first = now
				decoded0 = decoded
				shown0 = int(stats.get("frames_shown", 0))
				dropped0 = int(stats.get("frames_dropped", 0))
				cpu0 = float(stats.get("process_cpu_seconds", 0.0))
				last_sample = now
				last_decoded = decoded
			elif now - t0 > int(FIRST_FRAME_TIMEOUT * 1000.0):
				error = "no frame after %d s (%s)" % [int(FIRST_FRAME_TIMEOUT), state]
				break
			continue
		if now - last_sample >= int(SAMPLE_S * 1000.0):
			samples.append(snappedf((decoded - last_decoded) / ((now - last_sample) / 1000.0), 0.1))
			var g := Sysfs.gpu()
			if g.has("clock_mhz"):
				gpu_mhz.append(int(g["clock_mhz"]))
			last_sample = now
			last_decoded = decoded
			_report(clampf((now - t_first) / (seconds * 1000.0), 0.0, 1.0),
					"decoding %s: %.0f fps" % [file.get_file(), samples[-1]])
		if state == "ended" and not bool(stats.get("settling", false)):
			# A short file: back to the start, and on measuring (the seek's restart is in the measurement).
			loops += 1
			start_at = 0.0
			shown_at_seek = int(stats.get("frames_shown", 0))
			tex.call("seek", 0.0)
			continue
		if now - t_first >= int(seconds * 1000.0):
			break
	var elapsed := (Time.get_ticks_msec() - t_first) / 1000.0 if t_first >= 0 else 0.0
	var media_stats: Dictionary = media.call("get_stats") if media.has_method("get_stats") else {}
	var size_info := {"width": int(info.get("width", 0)), "height": int(info.get("height", 0))}
	tex.call("close")
	media.call("close")
	if elapsed < 1.0:
		return {"error": error if error != "" else "too short to measure (%.1f s)" % elapsed}
	var frames := int(stats.get("frames_decoded", 0)) - decoded0
	var fps := frames / elapsed
	var w: int = size_info["width"]
	var h: int = size_info["height"]
	var mpix := fps * w * h / 1e6
	var r := {
		"version": VERSION,
		"time": Time.get_datetime_string_from_system(false, true),
		"path": file,
		"file_mb": snappedf(size / 1e6, 0.1),
		"codec": str(info.get("codec", "")),
		"width": w,
		"height": h,
		"bit_depth": int(info.get("bit_depth", 8)),
		"content_fps": snappedf(content_fps, 0.001),
		"decode_path": str(stats.get("decode_path", "")),
		"seconds": snappedf(elapsed, 0.01),
		"frames": frames,
		"decode_fps": snappedf(fps, 0.1),
		"realtime_x": snappedf(fps / content_fps, 0.01) if content_fps > 0.0 else 0.0,
		"mpix_per_s": snappedf(mpix, 1.0),
		"fps_min": samples.min() if not samples.is_empty() else 0.0,
		"fps_samples": samples,
		"frames_shown": int(stats.get("frames_shown", 0)) - shown0,
		"frames_dropped": int(stats.get("frames_dropped", 0)) - dropped0,
		"decoder_latency_ms": snappedf(float(stats.get("latency_avg_ms", 0.0)), 0.1),
		"open_ms": open_ms,
		"first_frame_ms": t_first - t0,
		"cpu_percent_of_core": snappedf((float(stats.get("process_cpu_seconds", 0.0)) - cpu0) / elapsed * 100.0, 0.1),
		"loops": loops,
		"measured": true,
	}
	if error != "":
		r["error"] = error
	if not gpu_mhz.is_empty():
		r["gpu_mhz_max"] = gpu_mhz.max()
	var t := Sysfs.thermal()
	if not t.is_empty():
		r["hottest_c"] = t["hottest"]["c"]
	var b := Sysfs.battery()
	if b.has("power_w"):
		r["power_w"] = b["power_w"]
	if bool(media_stats.get("network", false)):
		r["network"] = {"mbps": media_stats.get("net_average_mbps", 0.0), "stalls": media_stats.get("net_stalls", 0)}
	r["can_play"] = estimate(mpix, r["codec"], r["decode_path"])
	r["summary"] = summary(r)
	return r


## What the measured pixel rate means for common sizes, on the same codec and decode path:
## [{label, fps_estimate, ok}]. ok when the estimate is at least 10 % over the size's frame rate.
static func estimate(mpix_per_s: float, _codec: String, _decode_path: String) -> Array:
	var out: Array = []
	for t: Array in TARGETS:
		var est := mpix_per_s * 1e6 / (float(t[1]) * float(t[2]))
		out.append({"label": t[0], "fps_estimate": snappedf(est, 0.1), "ok": est >= float(t[3]) * 1.1})
	return out


## One line for the log, the pane and the phone.
static func summary(r: Dictionary) -> String:
	var line := "%s %dx%d %s: %.0f fps decoded" % [str(r["codec"]).to_upper(), r["width"], r["height"],
			r["decode_path"], r["decode_fps"]]
	if float(r["realtime_x"]) > 0.0:
		line += ", %.1fx real time for its %s fps" % [r["realtime_x"], str(snappedf(float(r["content_fps"]), 0.001))]
	line += " (%d Mpixel/s)" % int(r["mpix_per_s"])
	var ok: Array[String] = []
	for e: Dictionary in r.get("can_play", []):
		if e["ok"]:
			ok.append(e["label"])
	line += ". Same codec: " + (", ".join(ok) if not ok.is_empty() else "none of the common sizes") + "."
	if int(r.get("loops", 0)) > 0:
		line += " A short file: it played %d times." % (int(r["loops"]) + 1)
	if r.has("network"):
		line += " Read over the network: the share may be the limit."
	return line
