extends Node

## The sound of a captured window, for the analysis (docs/visualisers.md, "On the screen for anything"). A window's
## sound never passes through the app: the browser plays it straight to the headset's sound server. So that a
## visualiser can follow it, this records that program's stream from PipeWire (pw-record, raw mono float) and plays
## the samples on a muted bus of the app's own (BUS), and the shared analysis (scripts/play/audio_analysis.gd) listens
## there for as long as it runs. Nothing is heard twice: the bus is muted, and an effect on a muted bus still hears.
## Only while something asks (the screen's visualiser over a window): no recorder runs otherwise.
## Linux with PipeWire only (the Steam Frame); anywhere else, or with no stream to record, it stays quiet and the
## visualiser idles.
##
##   request(on)         start looking for the stream and recording it, or stop
##   live                samples are arriving
##   target              the stream being recorded: {serial, name} ({} none yet)
##   status() -> String  one line for the logs and the dev tools
## The stream: the first playing program stream (media.class Stream/Output/Audio) that is not the app's own nor a
## system one, a browser before anything else (find_stream()). Looked for again every FIND_EVERY seconds until
## found (a page makes its stream when it first plays a sound), and again when the recorder ends (the page stopped).

const AudioAnalysis := preload("res://scripts/play/audio_analysis.gd")
const BUS := "Window sound"
const RATE := 44100
const FIND_EVERY := 2.0
## At most this many samples wait to be played (a second): the analysis wants the newest.
const MAX_PENDING := RATE
const NODE_NAME := "FrameCineWindowSound"

var main: Node3D
var live := false
var target := {}
var _want := false
var _pid := -1
var _pipe: FileAccess
var _thread: Thread
var _stop := false
var _mutex := Mutex.new()
var _pending := PackedFloat32Array()
var _player: AudioStreamPlayer
var _find_task := -1
var _found: Variant
var _next_find := 0.0
var _quiet_s := 0.0
var _tools := -1


## pw-record and pw-dump are here (checked once).
func available() -> bool:
	if _tools < 0:
		_tools = 1 if OS.get_name() == "Linux" and _which("pw-record") and _which("pw-dump") else 0
	return _tools == 1


static func _which(tool: String) -> bool:
	for dir: String in OS.get_environment("PATH").split(":", false):
		if FileAccess.file_exists(dir.path_join(tool)):
			return true
	return false


func request(on: bool) -> void:
	if on == _want:
		return
	_want = on
	_next_find = 0.0
	if not on:
		_end()


func status() -> String:
	if not available():
		return "window sound: no PipeWire tools here"
	if not _want:
		return "window sound: not asked for"
	if _pid < 0:
		return "window sound: looking for a program's stream"
	return "window sound: recording %s (%s)" % [target.get("name", "?"), "live" if live else "silent so far"]


func _process(delta: float) -> void:
	if not _want or not available():
		return
	if _pid < 0:
		_look(delta)
		return
	if not OS.is_process_running(_pid):
		# The stream went (the page stopped, the browser closed): look again.
		_end()
		return
	var got := PackedFloat32Array()
	_mutex.lock()
	if not _pending.is_empty():
		got = _pending
		_pending = PackedFloat32Array()
	_mutex.unlock()
	if got.is_empty():
		_quiet_s += delta
		if live and _quiet_s > 1.0:
			_set_live(false)
		return
	_quiet_s = 0.0
	if not live:
		_set_live(true)
		print("Window sound: samples arriving; the analysis listens to them")
	var playback := _player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return
	var n := mini(got.size(), playback.get_frames_available())
	var frames := PackedVector2Array()
	frames.resize(n)
	# The newest n samples: what does not fit is old already.
	var from := got.size() - n
	for i in n:
		var v := got[from + i]
		frames[i] = Vector2(v, v)
	playback.push_buffer(frames)


## Looks for the stream on a worker thread (pw-dump takes a few tens of milliseconds), then starts the recorder.
func _look(delta: float) -> void:
	if _find_task >= 0:
		if not WorkerThreadPool.is_task_completed(_find_task):
			return
		WorkerThreadPool.wait_for_task_completion(_find_task)
		_find_task = -1
		if _found is Dictionary and not (_found as Dictionary).is_empty():
			_start(_found)
		return
	_next_find -= delta
	if _next_find > 0.0:
		return
	_next_find = FIND_EVERY
	_found = null
	_find_task = WorkerThreadPool.add_task(func() -> void:
		var out: Array = []
		if OS.execute("pw-dump", [], out) == 0 and not out.is_empty():
			_found = find_stream(JSON.parse_string(str(out[0]))))


## The stream to record from pw-dump's objects: {serial, name}, or {} when there is none. A browser first.
static func find_stream(objects: Variant) -> Dictionary:
	if not (objects is Array):
		return {}
	var best := {}
	for o: Variant in objects:
		if not (o is Dictionary) or not str((o as Dictionary).get("type", "")).ends_with("Node"):
			continue
		var info: Variant = (o as Dictionary).get("info")
		var props: Variant = (info as Dictionary).get("props") if info is Dictionary else null
		if not (props is Dictionary) or str((props as Dictionary).get("media.class", "")) != "Stream/Output/Audio":
			continue
		var p: Dictionary = props
		var app := str(p.get("application.name", ""))
		var binary := str(p.get("application.process.binary", ""))
		# The app's own stream, our recorder, and the sound server's inner streams (no program behind them).
		if app == "" or binary.contains("framecine") or app == "FrameCine" or str(p.get("node.name", "")) == NODE_NAME:
			continue
		# A whole number, as pw-record wants it (JSON gives a float: "1509.0" names nothing, and the recorder would
		# then take the default source, the microphone).
		var raw: Variant = p.get("object.serial")
		if not (raw is float or raw is int or (raw is String and (raw as String).is_valid_int())):
			continue
		var serial := str(int(raw))
		var one := {"serial": serial, "name": app}
		var browser := binary.to_lower().contains("chrom") or app.to_lower().contains("chrom") \
				or app.to_lower().contains("firefox")
		if browser:
			return one
		if best.is_empty():
			best = one
	return best


func _start(stream: Dictionary) -> void:
	_ensure_player()
	var io := OS.execute_with_pipe("pw-record", ["--target", str(stream["serial"]), "--raw", "--format", "f32",
			"--rate", str(RATE), "--channels", "1", "--latency", "20ms",
			"-P", "{ node.name=%s node.dont-reconnect=true }" % NODE_NAME, "-"], true)
	if io.is_empty() or int(io.get("pid", -1)) <= 0:
		push_warning("Window sound: pw-record did not start")
		return
	target = stream
	_pid = int(io["pid"])
	_pipe = io["stdio"]
	_stop = false
	_quiet_s = 0.0
	_thread = Thread.new()
	_thread.start(_read)
	print("Window sound: recording %s (stream %s) for the visualiser" % [stream["name"], stream["serial"]])


## The recorder's samples as they come (its own thread: reading the pipe waits).
func _read() -> void:
	while not _stop:
		# A waiting read (the pipe was opened so): about 23 ms of sound a time. Nothing: the recorder has ended.
		var bytes := _pipe.get_buffer(4096)
		if bytes.is_empty():
			return
		var samples := bytes.slice(0, bytes.size() - bytes.size() % 4).to_float32_array()
		_mutex.lock()
		_pending.append_array(samples)
		if _pending.size() > MAX_PENDING:
			_pending = _pending.slice(_pending.size() - MAX_PENDING)
		_mutex.unlock()


func _end() -> void:
	if _pid > 0:
		_stop = true
		OS.kill(_pid)
		if _thread != null:
			_thread.wait_to_finish()
		_thread = null
		_pipe = null
		_pid = -1
	target = {}
	_mutex.lock()
	_pending = PackedFloat32Array()
	_mutex.unlock()
	if live:
		_set_live(false)


## The analysis listens on our bus while samples arrive, and on its own again after.
func _set_live(on: bool) -> void:
	live = on
	var a := AudioAnalysis.shared
	if a != null:
		a.set_bus(BUS if on else "")


func _ensure_player() -> void:
	if _player != null:
		return
	if AudioServer.get_bus_index(BUS) < 0:
		AudioServer.add_bus()
		var b := AudioServer.bus_count - 1
		AudioServer.set_bus_name(b, BUS)
		AudioServer.set_bus_send(b, "Master")
		AudioServer.set_bus_mute(b, true)
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.1
	_player = AudioStreamPlayer.new()
	_player.name = "WindowSound"
	_player.stream = gen
	_player.bus = BUS
	add_child(_player)
	_player.play()


func _exit_tree() -> void:
	_want = false
	_end()
	if _find_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_find_task)
		_find_task = -1
