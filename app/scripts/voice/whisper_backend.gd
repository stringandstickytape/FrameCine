extends Node

## On-device speech to text (docs/decisions.md D17, build/whisper/README.md): whisper.cpp's `whisper-server`, bundled
## in the package's whisper/ folder, runs as a child process on 127.0.0.1 with the model loaded once. Clips go to it as
## WAV over HTTP from a worker thread, so a frame never waits. Finals use beam search and the vocabulary prompt
## (as tools/voice.py did on the PC); live partials are greedy and skipped while a request is running.
##
## Started when the assistant needs it, not at every launch:
##   var whisper := preload("res://scripts/voice/whisper_backend.gd").ensure(get_tree())
## It sets Transcriber.backend = self once the server answers (scripts/voice/transcriber.gd); Transcriber.available()
## is false until then, and stays false with one log line when the binary or the model is missing.
##
## Settings ([voice] in user://settings.cfg) and flags (after `--`; a flag wins for that run):
##   whisper_dir      --whisper-dir=DIR       the folder with whisper-server and models/ (default: whisper/ next to the
##                                            engine, one folder up from it (a release's bin/), or next to the app)
##   whisper_model    --whisper-model=NAME    "small.en" (default): models/ggml-small.en-q8_0.bin, else -q5_1, else the
##                                            f16 file; or a full stem such as "small.en-q5_1"; or a .bin path
##   whisper_threads  --whisper-threads=N     4 (default; the server runs at nice 10)
##   whisper_backend  --whisper-backend=B     "cpu" (default) or "vulkan" (the GPU build in whisper/vulkan/)
## The server's own output goes to user://whisper-server.log.

const Transcriber := preload("res://scripts/voice/transcriber.gd")
const WorkerTask := preload("res://scripts/dev/worker_task.gd")

const SELF_PATH := "res://scripts/voice/whisper_backend.gd"
const NODE_NAME := "WhisperBackend"
const SECTION := "voice"
const DEFAULT_MODEL := "small.en"
const DEFAULT_THREADS := 4
const HOST := "127.0.0.1"
## Model variants tried for a bare name such as "base.en", best first.
const QUANT_ORDER: Array[String] = ["-q8_0", "-q5_1", ""]
const LOAD_TIMEOUT := 120.0
## Seconds a request may take: a final gets this plus 2 s per second of audio (a slow model on a long clip).
const FINAL_TIMEOUT := 60.0
const PARTIAL_TIMEOUT := 30.0
const FINAL_BEAM := 5
## whisper.cpp skips input shorter than 1 s; shorter clips are padded with silence.
const MIN_SAMPLES := 16800

## Words the speaker uses that a small model mishears without a hint (copied from tools/voice.py).
const VOCABULARY := ("Talking to Claude about the VR video player on the Steam Frame headset: the listener on port "
		+ "47800, the pane, the dev link, SMB, HEVC, HDR, pairing.")

## Configuration: set before the node enters the tree (ensure() fills them from the settings and flags).
var whisper_dir := ""
var model := DEFAULT_MODEL
var threads := DEFAULT_THREADS
var backend_kind := "cpu"
## Start the server when the node enters the tree (tests set false and call start() themselves).
var autostart := true

## State, for describe(), the tests and the dev link.
var server_path := ""
var model_path := ""
var port := 0
## A random path prefix for every route, new at each start: the port alone is no secret on 127.0.0.1, and the server
## answers any origin (a web page in a browser on the headset could post to it, or swap its model through /load).
var route := ""
var pid := -1
var load_ms := 0
var last_error := ""
var restarts := 0
var busy := 0
var _ready_flag := false
var _starting := false
var _watch_pid := -1
var _check_left := 1.0
static var _instance: Node = null


## The backend node under the scene root: the existing one, or a new one configured from the settings and flags
## (added deferred; it starts the server once it is in the tree).
static func ensure(tree: SceneTree) -> Node:
	if is_instance_valid(_instance) and not _instance.is_queued_for_deletion():
		return _instance
	var existing := tree.root.get_node_or_null(NODE_NAME)
	if existing != null:
		_instance = existing
		return existing
	var n: Node = load(SELF_PATH).new()
	n.name = NODE_NAME
	n.configure(_read_settings(tree), _read_args())
	tree.root.add_child.call_deferred(n)
	_instance = n
	return n


## Settings first, then the flags over them.
func configure(settings: Dictionary, args: Dictionary) -> void:
	whisper_dir = _expand(str(args.get("whisper-dir", settings.get("whisper_dir", ""))))
	model = str(args.get("whisper-model", settings.get("whisper_model", DEFAULT_MODEL)))
	threads = maxi(1, int(str(args.get("whisper-threads", settings.get("whisper_threads", DEFAULT_THREADS)))))
	backend_kind = str(args.get("whisper-backend", settings.get("whisper_backend", "cpu"))).to_lower()
	if model == "":
		model = DEFAULT_MODEL


func _ready() -> void:
	set_process(false)
	if autostart:
		start()


func ready() -> bool:
	return _ready_flag


func describe() -> String:
	return "whisper.cpp %s, %s, %d threads" % [model_name(), backend_kind, threads]


## The model's file stem, such as base.en-q8_0 (the setting as given while no file is found).
func model_name() -> String:
	if model_path == "":
		return model
	return model_path.get_file().trim_prefix("ggml-").trim_suffix(".bin")


## Finds the binary and the model, starts the server, waits for it to answer, then registers with the Transcriber.
## Returns true when it is ready. Never blocks a frame.
func start() -> bool:
	if _ready_flag or _starting:
		return _ready_flag
	_starting = true
	var ok := await _start()
	_starting = false
	return ok


func _start() -> bool:
	last_error = ""
	if not _resolve():
		_fail(last_error)
		return false
	var cpu_problem := cpu_missing_features()
	if cpu_problem != "":
		_fail("this CPU lacks %s, which the bundled whisper-server needs" % cpu_problem)
		return false
	port = free_port()
	if port <= 0:
		_fail("no free TCP port on %s" % HOST)
		return false
	route = "/" + Crypto.new().generate_random_bytes(16).hex_encode()
	var log_path := ProjectSettings.globalize_path("user://whisper-server.log")
	if restarts == 0:
		FileAccess.open(log_path, FileAccess.WRITE)  # a new log per app run; a restart appends to it
	# nice 10: the film's decoding and rendering always win the CPU (seen on the headset: lumpy playback while
	# transcribing at normal priority).
	var args := PackedStringArray(["-c", 'l=$1; shift; exec nice -n 10 "$@" >>"$l" 2>&1', "whisper-server", log_path,
			server_path,
			"-m", model_path, "-t", str(threads), "-l", "en", "--host", HOST, "--port", str(port),
			"--request-path", route])
	var t0 := Time.get_ticks_msec()
	pid = OS.create_process("/bin/sh", args)
	if pid <= 0:
		_fail("can't start %s" % server_path)
		return false
	_start_watchdog()
	var tree := get_tree()
	var my_port := port
	var my_pid := pid
	var my_route := route
	var r: Dictionary = await WorkerTask.run(tree, func() -> Variant: return _wait_healthy(my_port, my_route, my_pid),
			LOAD_TIMEOUT + 5.0)
	if not is_inside_tree():
		return false
	var state: String = r["result"] if bool(r["done"]) else "timeout"
	if state != "ok":
		_kill_server()
		_fail("whisper-server %s (model %s; its output: %s)" % [
				"exited while loading" if state == "dead" else "did not answer in %d s" % int(LOAD_TIMEOUT),
				model_path, log_path])
		return false
	load_ms = Time.get_ticks_msec() - t0
	_ready_flag = true
	Transcriber.backend = self
	_check_left = 1.0
	set_process(true)
	print("Voice: whisper-server ready: model %s, %s, %d threads, loaded in %d ms (%s:%d, pid %d)" % [
			model_name(), backend_kind, threads, load_ms, HOST, port, pid])
	return true


## Takes the clip: a final always (queued behind a running request), a partial only when nothing is running.
## Calls Transcriber.emit_done(id, text, final) once, on the main thread; text "" on failure (logged).
func transcribe(id: int, pcm: PackedByteArray, final: bool) -> bool:
	if not _ready_flag:
		return false
	if not final and busy > 0:
		return false
	busy += 1
	_run(id, pcm, final)
	return true


func _run(id: int, pcm: PackedByteArray, final: bool) -> void:
	var body_parts := request_body(pcm, final)
	var my_port := port
	var my_route := route
	var t0 := Time.get_ticks_msec()
	var timeout := FINAL_TIMEOUT + pcm.size() / 16000.0 if final else PARTIAL_TIMEOUT
	var r: Dictionary = await WorkerTask.run(get_tree(), func() -> Variant:
		return http_request(my_port, "POST", my_route + "/inference", body_parts[1], body_parts[0], timeout), timeout + 5.0,
			true)
	busy -= 1
	var text := ""
	if not bool(r["done"]):
		print("Voice: whisper %s %d timed out" % ["final" if final else "partial", id])
	else:
		var res: Dictionary = r["result"]
		if str(res["error"]) != "" or int(res["code"]) != 200:
			print("Voice: whisper %s %d failed: %s %s" % ["final" if final else "partial", id,
					res["error"] if str(res["error"]) != "" else "HTTP %d" % int(res["code"]),
					str(res["body"]).substr(0, 200)])
		else:
			text = parse_text(str(res["body"]))
			if final:
				print("Voice: whisper final %d: %.1f s of audio in %d ms" % [id, pcm.size() / 32000.0,
						Time.get_ticks_msec() - t0])
	Transcriber.emit_done(id, text, final)


## [content type, body] of the multipart form for one clip.
static func request_body(pcm: PackedByteArray, final: bool) -> Array:
	var boundary := "----vrvp%d%d" % [Time.get_ticks_usec(), randi()]
	var fields := {"response_format": "json", "language": "en", "no_timestamps": "true", "temperature": "0.0",
			"prompt": VOCABULARY}
	if final:
		fields["beam_size"] = str(FINAL_BEAM)
	else:
		fields["beam_size"] = "1"
		fields["temperature_inc"] = "0.0"  # no temperature fallback: a partial must come back quickly
	var body := PackedByteArray()
	for k: String in fields:
		body.append_array(("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n" % [boundary, k,
				fields[k]]).to_utf8_buffer())
	var head := "--%s\r\nContent-Disposition: form-data; name=\"file\"; filename=\"clip.wav\"\r\n" % boundary
	body.append_array((head + "Content-Type: audio/wav\r\n\r\n").to_utf8_buffer())
	body.append_array(wav(pcm))
	body.append_array(("\r\n--%s--\r\n" % boundary).to_utf8_buffer())
	return ["multipart/form-data; boundary=" + boundary, body]


## A 16 kHz mono 16-bit WAV of `pcm`, padded with silence to just over 1 s.
static func wav(pcm: PackedByteArray) -> PackedByteArray:
	var data := pcm.slice(0, pcm.size() - pcm.size() % 2)
	if data.size() < MIN_SAMPLES * 2:
		var pad := PackedByteArray()
		pad.resize(MIN_SAMPLES * 2 - data.size())
		pad.fill(0)
		data.append_array(pad)
	var h := PackedByteArray()
	h.resize(44)
	h.encode_u32(0, 0x46464952)  # RIFF
	h.encode_u32(4, 36 + data.size())
	h.encode_u32(8, 0x45564157)  # WAVE
	h.encode_u32(12, 0x20746d66)  # "fmt "
	h.encode_u32(16, 16)
	h.encode_u16(20, 1)  # PCM
	h.encode_u16(22, 1)  # mono
	h.encode_u32(24, 16000)
	h.encode_u32(28, 32000)
	h.encode_u16(32, 2)
	h.encode_u16(34, 16)
	h.encode_u32(36, 0x61746164)  # data
	h.encode_u32(40, data.size())
	h.append_array(data)
	return h


## The text of the server's JSON answer, on one line, without whisper's markers such as [BLANK_AUDIO].
static func parse_text(body: String) -> String:
	var json := JSON.new()
	if json.parse(body) != OK or not json.data is Dictionary:
		return ""
	var text := str(json.data.get("text", "")).replace("\n", " ").replace("\t", " ")
	var re := RegEx.create_from_string("\\[[A-Z_ ]+\\]|\\((?:music|silence|inaudible|blank audio)\\)")
	text = re.sub(text, " ", true)
	return " ".join(text.split(" ", false))


## One HTTP request to the server, blocking (worker threads only). {code, body, error}.
static func http_request(to_port: int, method: String, path: String, body := PackedByteArray(), content_type := "",
		timeout := 10.0) -> Dictionary:
	var c := HTTPClient.new()
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	if c.connect_to_host(HOST, to_port) != OK:
		return {"code": 0, "body": "", "error": "connect"}
	while c.get_status() in [HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING]:
		c.poll()
		if Time.get_ticks_msec() > deadline:
			return {"code": 0, "body": "", "error": "connect timeout"}
		OS.delay_msec(2)
	if c.get_status() != HTTPClient.STATUS_CONNECTED:
		return {"code": 0, "body": "", "error": "can't connect"}
	var headers := PackedStringArray(["Connection: close"])
	if content_type != "":
		headers.append("Content-Type: " + content_type)
	var m := HTTPClient.METHOD_POST if method == "POST" else HTTPClient.METHOD_GET
	if c.request_raw(m, path, headers, body) != OK:
		return {"code": 0, "body": "", "error": "request"}
	while c.get_status() == HTTPClient.STATUS_REQUESTING:
		c.poll()
		if Time.get_ticks_msec() > deadline:
			return {"code": 0, "body": "", "error": "timeout"}
		OS.delay_msec(2)
	if not c.has_response():
		return {"code": 0, "body": "", "error": "no response (status %d)" % c.get_status()}
	var code := c.get_response_code()
	var out := PackedByteArray()
	while c.get_status() == HTTPClient.STATUS_BODY:
		c.poll()
		var chunk := c.read_response_body_chunk()
		if chunk.is_empty():
			if Time.get_ticks_msec() > deadline:
				return {"code": code, "body": "", "error": "timeout reading"}
			OS.delay_msec(2)
		else:
			out.append_array(chunk)
	c.close()
	return {"code": code, "body": out.get_string_from_utf8(), "error": ""}


## Polls /health until the model is loaded: "ok", "dead" (the process ended) or "timeout". Worker threads only.
static func _wait_healthy(to_port: int, to_route: String, server_pid: int) -> String:
	var deadline := Time.get_ticks_msec() + int(LOAD_TIMEOUT * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if not OS.is_process_running(server_pid):
			return "dead"
		var r := http_request(to_port, "GET", to_route + "/health", PackedByteArray(), "", 2.0)
		if r["error"] == "" and int(r["code"]) == 200:
			return "ok"
		OS.delay_msec(50)
	return "timeout"


## The server binary and the model: true when both exist; else last_error says what is missing and where it looked.
func _resolve() -> bool:
	var dirs := candidate_dirs(whisper_dir)
	var exe := "vulkan/whisper-server" if backend_kind == "vulkan" else "whisper-server"
	server_path = ""
	for d: String in dirs:
		if FileAccess.file_exists(d.path_join(exe)):
			server_path = d.path_join(exe)
			break
	if server_path == "":
		last_error = "no %s in %s" % [exe, ", ".join(dirs)]
		return false
	model_path = find_model(model, server_path.get_base_dir().trim_suffix("/vulkan"))
	if model_path == "":
		last_error = "no model %s in %s/models (build/whisper-models.sh downloads them)" % [model,
				server_path.get_base_dir().trim_suffix("/vulkan")]
		return false
	return true


## Where whisper/ is looked for: the setting or flag, then next to the engine, one folder up from it (a release's
## bin/), and next to the app folder (a checkout).
static func candidate_dirs(configured: String) -> PackedStringArray:
	if configured != "":
		return PackedStringArray([configured.simplify_path()])
	var exe_dir := OS.get_executable_path().get_base_dir()
	var app_dir := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var out := PackedStringArray()
	for d: String in [exe_dir.path_join("whisper"), exe_dir.get_base_dir().path_join("whisper"),
			app_dir.get_base_dir().path_join("whisper")]:
		if not d.simplify_path() in out:
			out.append(d.simplify_path())
	return out


## The model file for a setting: a path to a .bin file, a stem such as small.en-q5_1, or a bare name such as base.en
## (q8_0, then q5_1, then f16). "" when none exists.
static func find_model(name: String, dir: String) -> String:
	if name.ends_with(".bin"):
		var p := name if name.is_absolute_path() else dir.path_join("models").path_join(name)
		return p if FileAccess.file_exists(p) else ""
	var suffixes: Array[String] = QUANT_ORDER
	if name.contains("-q"):
		suffixes = [""]
	for s: String in suffixes:
		for sub: String in ["models", ""]:
			var p := dir.path_join(sub).path_join("ggml-%s%s.bin" % [name, s]).simplify_path()
			if FileAccess.file_exists(p):
				return p
	return ""


## What the bundled aarch64 build needs that /proc/cpuinfo does not list ("" when all is there, or not on arm64).
static func cpu_missing_features(cpuinfo := "") -> String:
	if cpuinfo == "":
		if Engine.get_architecture_name() != "arm64" or not FileAccess.file_exists("/proc/cpuinfo"):
			return ""
		cpuinfo = read_text("/proc/cpuinfo")
	var have := PackedStringArray()
	for line in cpuinfo.split("\n"):
		if line.begins_with("Features"):
			have = line.get_slice(":", 1).strip_edges().split(" ", false)
			break
	if have.is_empty():
		return ""  # no Features line: don't guess
	var missing := PackedStringArray()
	for f: String in ["asimddp", "i8mm", "asimdhp"]:
		if not f in have:
			missing.append(f)
	return ", ".join(missing)


## A text file read line by line (files in /proc report a length of 0, so get_file_as_string() reads nothing).
static func read_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var lines := PackedStringArray()
	while not f.eof_reached():
		lines.append(f.get_line())
	return "\n".join(lines)


## A TCP port on 127.0.0.1 that nothing listens on now.
static func free_port() -> int:
	var s := TCPServer.new()
	if s.listen(0, HOST) != OK:
		return 0
	var p := s.get_local_port()
	s.stop()
	return p


## Kills the server if the engine ends without stopping it (a crash): a shell that waits for either to go.
func _start_watchdog() -> void:
	if _watch_pid > 0 and OS.is_process_running(_watch_pid):
		OS.kill(_watch_pid)
	_watch_pid = OS.create_process("/bin/sh", PackedStringArray(["-c",
			'while kill -0 "$1" 2>/dev/null && kill -0 "$2" 2>/dev/null; do sleep 2; done; kill "$2" 2>/dev/null',
			"whisper-watchdog", str(OS.get_process_id()), str(pid)]))


func _process(delta: float) -> void:
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = 1.0
	if pid > 0 and not OS.is_process_running(pid):
		_on_server_died()


func _on_server_died() -> void:
	set_process(false)
	_ready_flag = false
	if Transcriber.backend == self:
		Transcriber.backend = null
	pid = -1
	if restarts >= 1:
		_fail("whisper-server stopped again (output: user://whisper-server.log); on-device transcription is off")
		return
	restarts += 1
	print("Voice: whisper-server stopped; starting it again")
	start()


func _fail(why: String) -> void:
	last_error = why
	_ready_flag = false
	if Transcriber.backend == self:
		Transcriber.backend = null
	print("Voice: on-device transcription unavailable: " + why)


## Stops the server (also on exit).
func stop() -> void:
	set_process(false)
	_ready_flag = false
	if Transcriber.backend == self:
		Transcriber.backend = null
	_kill_server()


func _kill_server() -> void:
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
	pid = -1
	if _watch_pid > 0 and OS.is_process_running(_watch_pid):
		OS.kill(_watch_pid)
	_watch_pid = -1


func _exit_tree() -> void:
	stop()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_kill_server()


static func _read_settings(tree: SceneTree) -> Dictionary:
	var out := {}
	var main := tree.root.get_node_or_null("Main")
	var settings: Variant = main.get("settings") if main != null else null
	var cfg := ConfigFile.new()
	var use_cfg := settings == null and cfg.load("user://settings.cfg") == OK
	for key: String in ["whisper_dir", "whisper_model", "whisper_threads", "whisper_backend"]:
		if settings != null and settings.has_value(SECTION, key):
			out[key] = settings.get_value(SECTION, key, null)
		elif use_cfg and cfg.has_section_key(SECTION, key):
			out[key] = cfg.get_value(SECTION, key)
	return out


static func _read_args() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--whisper-"):
			var kv := arg.trim_prefix("--").split("=", true, 1)
			if kv.size() == 2:
				out[kv[0]] = kv[1]
	return out


static func _expand(p: String) -> String:
	if p.begins_with("~/"):
		return OS.get_environment("HOME").path_join(p.trim_prefix("~/"))
	return p
