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
##
## The model: whisper/models/ next to the server first (a package made with a model, the benchmark kit), then
## user://whisper-models/. The release package has none (docs/framedrop.md "The speech model"): with the server there
## but no model, the backend waits (Transcriber.waiting) and downloads the default model (scripts/voice/
## model_download.gd, about 264 MB) when the first start's introduction opens (ui/intro.gd: model_status(),
## fetch_model(), quiet), else the first time voice is used, then starts the server. The viewer sees a notice
## when it starts, at each quarter, and when voice is ready; with no network, one notice says so, and the next use of
## voice tries again, not sooner than RETRY_SECONDS later. Nothing else waits for it. Only the default model is
## downloaded: another whisper_model that is missing stays off with the line as before.
## Flag: --model-url=URL takes the model from URL (tests, a mirror).

const Transcriber := preload("res://scripts/voice/transcriber.gd")
const WorkerTask := preload("res://scripts/dev/worker_task.gd")
const ModelDownload := preload("res://scripts/voice/model_download.gd")

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

## Where a downloaded model goes (outside the install folder: updates keep it).
const USER_MODELS := "user://whisper-models"
## The setting values that mean the model the player downloads (ModelDownload.MODEL_FILE).
const DOWNLOADABLE: Array[String] = ["small.en", "small.en-q8_0", "ggml-small.en-q8_0.bin"]
## After a failed download, voice tries again at its next use, but not sooner than this (no retry storm).
const RETRY_SECONDS := 60.0
## A notice for a press comes when voice has not been asked for this long: push-to-talk asks every second while the
## button is held (live partials) and once at the release, and the "Listening" line goes at the release.
const NOTICE_DELAY := 1.2
## The same notice is not shown again within this time.
const NOTICE_REPEAT := 6.0
## What the viewer sees (the notices, translated; why() in English for the assistant's card).
const TEXT_DOWNLOADING := "Voice needs a one-time download of about %d MB. Downloaded: %d %%. The rest of the player works as usual."  # i18n
const TEXT_PROGRESS := "Speech model download: %d %%"  # i18n
const TEXT_OFFLINE := "Voice needs the network once, for a download of about %d MB. The rest of the player works as usual."  # i18n
const TEXT_FAILED := "The speech model did not download. Voice tries again when you use it next."  # i18n
const TEXT_STARTING := "Voice is starting."  # i18n
const TEXT_READY := "Voice is ready."  # i18n

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
## The model download (tests change these): the folder, the address ("" is ModelDownload.url()), size, SHA-256 and
## the timeouts (connect, then no bytes).
var model_store := USER_MODELS
var model_url := ""
var model_size := ModelDownload.MODEL_SIZE
var model_sha256 := ModelDownload.MODEL_SHA256
var connect_timeout := 15.0
var stall_timeout := 30.0
## "" (the model is there, or can't be downloaded), "needed", "running", "failed" or "done" (then the server starts).
var download_state := ""
var download_error := ""
var download_offline := false
## Notices shown, newest last (for the tests).
var notices: PackedStringArray = []

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
var _need_download := false
var _download: RefCounted = null
var _download_t0 := 0
var _failed_at := -1
## No notices while the introduction shows the download itself (ui/intro.gd).
var quiet := false
var _quarter := 0
var _announce_ready := false
var _notice := ""
var _notice_left := 0.0
var _notice_pending := false
var _shown := ""
var _shown_at := -100000
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
	model_url = str(args.get("model-url", ""))
	if model == "":
		model = DEFAULT_MODEL


func _ready() -> void:
	set_process(false)
	if autostart:
		start()


func ready() -> bool:
	return _ready_flag


func describe() -> String:
	var s := "whisper.cpp %s, %s, %d threads" % [model_name(), backend_kind, threads]
	match download_state:
		"needed":
			s += " (no model yet: it downloads, %d MB, the first time voice is used)" % (model_size / 1000000)
		"running":
			s += " (downloading the model: %d %%)" % _percent()
		"failed":
			s += " (the model download failed: %s; the next use of voice tries again)" % download_error
	return s


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
	var found := _resolve()
	var cpu_problem := cpu_missing_features() if found or _need_download else ""
	if cpu_problem != "":
		_fail("this CPU lacks %s, which the bundled whisper-server needs" % cpu_problem)
		return false
	if not found and _need_download:
		_wait_for_model()
		return false
	if not found:
		_fail(last_error)
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
	if Transcriber.waiting == self:
		Transcriber.waiting = null
	download_state = ""
	_check_left = 1.0
	set_process(true)
	print("Voice: whisper-server ready: model %s, %s, %d threads, loaded in %d ms (%s:%d, pid %d)" % [
			model_name(), backend_kind, threads, load_ms, HOST, port, pid])
	if _announce_ready:
		_announce_ready = false
		_queue(tr(TEXT_READY), 0.0)
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


## Whole answers whisper makes up from silence or noise (the user heard "The game is over." a few times, 2026-11-06),
## compared without case, spaces or punctuation: such an answer counts as nothing said. Only whole answers: the same
## words inside a longer sentence are kept. "Thank you" is left out on purpose: people say it.
const MADE_UP := ["the game is over", "thanks for watching", "thank you for watching", "thank you so much for watching",
		"please subscribe", "subscribe to my channel", "you", "bye", "the end", "subtitles by the amaraorg community"]


## The text of the server's JSON answer, on one line, without whisper's markers such as [BLANK_AUDIO], and "" for an
## answer it makes up from silence (MADE_UP).
static func parse_text(body: String) -> String:
	var json := JSON.new()
	if json.parse(body) != OK or not json.data is Dictionary:
		return ""
	var text := str(json.data.get("text", "")).replace("\n", " ").replace("\t", " ")
	var re := RegEx.create_from_string("\\[[A-Z_ ]+\\]|\\((?:music|silence|inaudible|blank audio)\\)")
	text = re.sub(text, " ", true)
	text = " ".join(text.split(" ", false))
	return "" if is_made_up(text) else text


static func is_made_up(text: String) -> bool:
	var bare := RegEx.create_from_string("[^a-z ]").sub(text.to_lower(), "", true)
	return " ".join(bare.split(" ", false)) in MADE_UP


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
	_need_download = false
	if server_path == "":
		last_error = "no %s in %s" % [exe, ", ".join(dirs)]
		return false
	var server_dir := server_path.get_base_dir().trim_suffix("/vulkan")
	model_path = find_model(model, server_dir)
	if model_path == "":
		model_path = store_model()
	if model_path == "":
		_need_download = model in DOWNLOADABLE
		last_error = "no model %s in %s/models or %s (%s)" % [model, server_dir, model_store,
				"it downloads the first time voice is used" if _need_download
				else "build/whisper-models.sh downloads them"]
		return false
	return true


## The model in model_store ("" when it is not there). A downloaded model of the wrong size is deleted (the
## download writes it only after its check, so that is damage, and a new download replaces it).
func store_model() -> String:
	var dir := ProjectSettings.globalize_path(model_store)
	var p := find_model(model, dir)
	if p != "" and p.get_file() == ModelDownload.MODEL_FILE and model_size > 0 and FileAccess.get_size(p) != model_size:
		print("Voice: %s has %d bytes, not %d; deleted" % [p, FileAccess.get_size(p), model_size])
		DirAccess.remove_absolute(p)
		return ""
	return p


# --- The model download ------------------------------------------------------------------------------------------

## Voice was used and is not available (Transcriber.available() calls this while Transcriber.waiting is this node):
## the first time the download starts; while it runs, the progress; after a failure, the reason, or another try
## once RETRY_SECONDS have passed.
func wanted() -> void:
	match download_state:
		"needed":
			_begin_download()
		"failed":
			if Time.get_ticks_msec() - _failed_at >= int(RETRY_SECONDS * 1000.0):
				_begin_download()
	if why() != "":
		_queue("", NOTICE_DELAY)  # why(true) then, as it is at that moment


## The viewer's line for now: English (for the assistant's card), or translated for the menus. "" when voice works
## or the backend knows no help.
func why(localised := false) -> String:
	var mb := model_size / 1000000
	match download_state:
		"needed", "running":
			return _t(TEXT_DOWNLOADING, localised) % [mb, _percent()]
		"failed":
			return _t(TEXT_OFFLINE, localised) % mb if download_offline else _t(TEXT_FAILED, localised)
		"done":
			return _t(TEXT_STARTING, localised)
	return ""


## For the introduction at the first start (ui/intro.gd), which fetches the model at once rather than at the first
## use of voice: download_state ("" when the model is there or isn't one the player downloads; "needed", "running",
## "failed", "done"), the percent, and whether the failure was the network.
func model_status() -> Dictionary:
	return {"state": download_state, "percent": _percent(), "offline": download_offline}


## Starts the download now, without RETRY_SECONDS' wait (the introduction's Retry); nothing when it isn't needed.
func fetch_model() -> void:
	if download_state in ["needed", "failed"]:
		_begin_download()


func _t(text: String, localised: bool) -> String:
	return tr(text) if localised else text


func _wait_for_model() -> void:
	if download_state in ["running", "failed"]:
		return
	download_state = "needed"
	Transcriber.waiting = self
	print("Voice: no speech model yet (%s, %d MB); it downloads the first time voice is used" % [
			ModelDownload.MODEL_FILE, model_size / 1000000])


func _begin_download() -> void:
	if _download == null:
		_download = ModelDownload.new()
	_download.connect_timeout = connect_timeout
	_download.stall_timeout = stall_timeout
	var from := model_url if model_url != "" else ModelDownload.url()
	var dir := ProjectSettings.globalize_path(model_store)
	if not _download.start(from, dir, ModelDownload.MODEL_FILE, model_size, model_sha256):
		return
	download_state = "running"
	download_error = ""
	download_offline = false
	_quarter = 0
	_download_t0 = Time.get_ticks_msec()
	var kept := FileAccess.get_size(dir.path_join(ModelDownload.MODEL_FILE + ".part")) \
			if FileAccess.file_exists(dir.path_join(ModelDownload.MODEL_FILE + ".part")) else 0
	print("Voice: downloading the speech model (%d MB%s) from %s" % [model_size / 1000000,
			", %d MB already here" % (kept / 1000000) if kept > 0 else "", from])
	set_process(true)


func _percent() -> int:
	if _download == null or model_size <= 0:
		return 0
	var p: Dictionary = _download.progress()
	return clampi(int(p.get("bytes", 0)) * 100 / model_size, 0, 100)


func _poll_download() -> void:
	var p: Dictionary = _download.progress()
	if str(p["state"]) == "running":
		var q := int(p["bytes"]) * 4 / model_size if model_size > 0 else 0
		if q > _quarter and q < 4:
			_quarter = q
			_queue(tr(TEXT_PROGRESS) % (q * 25), 0.0)
		return
	_download.finish()
	_download = null
	var secs := (Time.get_ticks_msec() - _download_t0) / 1000.0
	if str(p["state"]) == "done":
		print("Voice: speech model downloaded and checked in %.0f s" % secs)
		download_state = "done"
		_announce_ready = true
		start()
		return
	download_state = "failed"
	download_error = str(p["error"])
	download_offline = bool(p["offline"])
	_failed_at = Time.get_ticks_msec()
	var line := "Voice: speech model download failed after %.0f s: %s" % [secs, download_error]
	var part := ProjectSettings.globalize_path(model_store).path_join(ModelDownload.MODEL_FILE + ".part")
	var kept := FileAccess.get_size(part) if FileAccess.file_exists(part) else 0
	print(line + " (%d of %d bytes kept; the next use of voice tries again)" % [kept, model_size])
	_queue(why(true), 0.0)


## Shows `text` (translated) as a notice after `delay` s; a newer one replaces it, and each call starts the delay
## again. "" shows why(true) as it is when the delay ends (nothing if voice works by then).
func _queue(text: String, delay: float) -> void:
	if quiet:
		return
	_notice = text
	_notice_left = delay
	_notice_pending = true
	set_process(true)


func _show(text: String) -> void:
	var now := Time.get_ticks_msec()
	if text == _shown and now - _shown_at < int(NOTICE_REPEAT * 1000.0):
		return
	_shown = text
	_shown_at = now
	notices.append(text)
	var main := get_tree().current_scene if is_inside_tree() else null
	var ui: Object = main.get("ui") if main != null else null
	if ui != null and ui.has_method("notify"):
		ui.notify(text)


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
	if _download != null:
		_poll_download()
	if _notice_pending:
		_notice_left -= delta
		if _notice_left <= 0.0:
			_notice_pending = false
			var line := _notice if _notice != "" else why(true)
			if line != "":
				_show(line)
	if not _ready_flag:
		if _download == null and not _notice_pending:
			set_process(false)
		return
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


func _fail(reason: String) -> void:
	last_error = reason
	_ready_flag = false
	if Transcriber.backend == self:
		Transcriber.backend = null
	if Transcriber.waiting == self:
		Transcriber.waiting = null
	download_state = ""
	print("Voice: on-device transcription unavailable: " + reason)


## Stops the server and a model download (also on exit; the download's part stays for the next try).
func stop() -> void:
	set_process(false)
	_ready_flag = false
	if Transcriber.backend == self:
		Transcriber.backend = null
	if Transcriber.waiting == self:
		Transcriber.waiting = null
	if _download != null:
		_download.stop()
		_download = null
		if download_state == "running":
			download_state = "needed"
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
		if _download != null:
			_download.stop()


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
		if arg.begins_with("--whisper-") or arg.begins_with("--model-url="):
			var kv := arg.trim_prefix("--").split("=", true, 1)
			if kv.size() == 2:
				out[kv[0]] = kv[1]
	return out


static func _expand(p: String) -> String:
	if p.begins_with("~/"):
		return OS.get_environment("HOME").path_join(p.trim_prefix("~/"))
	return p
