extends SceneTree

## On-device speech to text (scripts/voice/whisper_backend.gd): the WAV and form it sends, model and folder lookup,
## the CPU check, a missing binary or model (available() stays false, one clear line), then the real x86_64
## whisper-server with tiny.en: listening on 127.0.0.1 only, a final of the JFK sample with the right words, a partial
## skipped while the final runs, a partial on its own, one restart after the server dies, off after the second death.
## Needs build/whisper-build.sh x86_64 and build/whisper-models.sh (WHISPER_TEST_DIR and WHISPER_TEST_MODEL override
## where they are). Without them the server part is skipped and reported, not failed.
## godot --headless --xr-mode off --path app --script res://tests/test_whisper.gd

const Backend := preload("res://scripts/voice/whisper_backend.gd")
const Transcriber := preload("res://scripts/voice/transcriber.gd")

var _fails := 0
var _done: Array = []


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame  # the root is in the tree from the first frame on
	Transcriber.events().done.connect(func(id: int, text: String, final: bool) -> void: _done.append([id, text, final]))
	_test_units()
	await _test_missing()
	await _test_server()
	await _test_ensure()
	print("test_whisper: %s" % ("all passed" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + what)


func _repo() -> String:
	return ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir()


func _test_units() -> void:
	var w := Backend.wav(PackedByteArray([1, 0, 2, 0, 3]))
	_check(w.slice(0, 4).get_string_from_ascii() == "RIFF" and w.slice(8, 16).get_string_from_ascii() == "WAVEfmt ",
			"wav header")
	_check(w.decode_u32(24) == 16000 and w.decode_u16(22) == 1 and w.decode_u16(34) == 16, "wav: 16 kHz mono 16-bit")
	_check(w.decode_u32(40) == Backend.MIN_SAMPLES * 2 and w.size() == 44 + Backend.MIN_SAMPLES * 2,
			"a short clip is padded to just over 1 s, odd byte dropped (data %d)" % w.decode_u32(40))
	_check(w[44] == 1 and w[46] == 2 and w[48] == 0, "samples kept, padding silent")
	var long := PackedByteArray()
	long.resize(64000)
	_check(Backend.wav(long).size() == 64044, "a 2 s clip is not padded")

	_check(Backend.parse_text('{"text":" [BLANK_AUDIO]\\n"}') == "", "blank audio marker dropped")
	_check(Backend.parse_text('{"text":" Dim the  lights\\n and skip.\\n"}') == "Dim the lights and skip.",
			"text on one line: %s" % Backend.parse_text('{"text":" Dim the  lights\\n and skip.\\n"}'))
	_check(Backend.parse_text("not json") == "", "bad answer gives empty text")

	var form: Array = Backend.request_body(PackedByteArray([0, 0]), true)
	var text: String = (form[1] as PackedByteArray).slice(0, 1200).get_string_from_ascii()
	_check(str(form[0]).begins_with("multipart/form-data; boundary="), "content type")
	_check(text.contains("name=\"beam_size\"\r\n\r\n5\r\n"), "final: beam 5")
	_check(text.contains("Steam Frame") and text.contains("47800"), "final: the vocabulary prompt")
	var partial: String = (Backend.request_body(PackedByteArray([0, 0]), false)[1] as PackedByteArray).slice(0, 1200) \
			.get_string_from_ascii()
	_check(partial.contains("name=\"beam_size\"\r\n\r\n1\r\n") and partial.contains("name=\"temperature_inc\"\r\n\r\n0.0"),
			"partial: greedy, no fallback")

	# Model lookup: a bare name takes q8_0, then q5_1, then f16; a stem or a path is taken as is.
	var dir := ProjectSettings.globalize_path("user://test_whisper_models")
	DirAccess.make_dir_recursive_absolute(dir.path_join("models"))
	for f in ["ggml-base.en-q5_1.bin", "ggml-base.en.bin", "ggml-small.en-q8_0.bin"]:
		FileAccess.open(dir.path_join("models").path_join(f), FileAccess.WRITE).store_8(0)
	_check(Backend.find_model("base.en", dir).ends_with("models/ggml-base.en-q5_1.bin"), "base.en: q5_1 when no q8_0")
	_check(Backend.find_model("small.en", dir).ends_with("ggml-small.en-q8_0.bin"), "small.en: q8_0 first")
	_check(Backend.find_model("base.en-q8_0", dir) == "", "an exact stem that is missing")
	_check(Backend.find_model("ggml-base.en.bin", dir).ends_with("models/ggml-base.en.bin"), "a file name")
	_check(Backend.find_model(dir.path_join("models/ggml-base.en.bin"), "/nowhere") != "", "an absolute path")
	_check(Backend.find_model("tiny.en", dir) == "", "missing model")
	_check(Backend.candidate_dirs("/a/b/../whisper") == PackedStringArray(["/a/whisper"]), "configured dir only")
	_check(Backend.candidate_dirs("").size() >= 2, "default dirs: next to the engine and up")

	var x4 := "processor\t: 0\nFeatures\t: fp asimd evtstrm aes pmull sha1 sha2 crc32 atomics fphp asimdhp cpuid " \
			+ "asimdrdm lrcpc dcpop sha3 sm3 sm4 asimddp sha512 sve asimdfhm dit uscat ilrcpc flagm i8mm bf16\n"
	_check(Backend.cpu_missing_features(x4) == "", "Snapdragon 8 Gen 3 features pass")
	_check(Backend.cpu_missing_features("Features\t: fp asimd evtstrm crc32 cpuid\n") == "asimddp, i8mm, asimdhp",
			"a Cortex-A53 lacks dotprod, i8mm and fp16")
	_check(Backend.cpu_missing_features("model name\t: x\n") == "", "no Features line: no guess")

	var b: Node = Backend.new()
	b.configure({"whisper_model": "small.en", "whisper_threads": 6, "whisper_dir": "/x"},
			{"whisper-threads": "8", "whisper-backend": "Vulkan"})
	_check(b.model == "small.en" and b.threads == 8 and b.whisper_dir == "/x" and b.backend_kind == "vulkan",
			"flags over settings: %s %d %s %s" % [b.model, b.threads, b.whisper_dir, b.backend_kind])
	b.configure({}, {})
	_check(b.model == "small.en" and b.threads == 4 and b.backend_kind == "cpu", "defaults")
	b.free()


func _make(dir: String, model: String) -> Node:
	var b: Node = Backend.new()
	b.autostart = false
	b.whisper_dir = dir
	b.model = model
	b.threads = 4
	root.add_child(b)
	return b


func _test_missing() -> void:
	var b := _make("/nonexistent/whisper", "tiny.en")
	var ok: bool = await b.start()
	_check(not ok and not Transcriber.available() and Transcriber.backend == null, "no binary: not available")
	_check(str(b.last_error) == "no whisper-server in /nonexistent/whisper", "no binary: says where (%s)" % b.last_error)
	_check(Transcriber.transcribe(PackedByteArray([0, 0]), true) == -1, "no backend: transcribe gives -1")
	b.queue_free()

	var bin_dir := _bin_dir()
	if bin_dir == "":
		return
	var m := _make(bin_dir, "nonexistent.en")
	ok = await m.start()
	_check(not ok and not Transcriber.available(), "no model: not available")
	_check(str(m.last_error).begins_with("no model nonexistent.en in " + bin_dir + "/models"),
			"no model: says which and where (%s)" % m.last_error)
	_check(m.pid == -1, "no model: nothing started")
	m.queue_free()


func _bin_dir() -> String:
	var d := OS.get_environment("WHISPER_TEST_DIR")
	if d == "":
		d = _repo().path_join("build/out/whisper/x86_64")
	return d if FileAccess.file_exists(d.path_join("whisper-server")) else ""


func _model() -> String:
	var m := OS.get_environment("WHISPER_TEST_MODEL")
	if m != "":
		return m
	for stem in ["tiny.en-q5_1", "tiny.en-q8_0", "tiny.en"]:
		var p := _repo().path_join("build/out/whisper-models/ggml-%s.bin" % stem)
		if FileAccess.file_exists(p):
			return p
	return ""


## The samples' PCM (the data chunk of a 16 kHz mono 16-bit WAV).
func _pcm(path: String) -> PackedByteArray:
	var b := FileAccess.get_file_as_bytes(path)
	var at := 12
	while at + 8 <= b.size():
		var size := b.decode_u32(at + 4)
		if b.slice(at, at + 4).get_string_from_ascii() == "data":
			return b.slice(at + 8, at + 8 + size)
		at += 8 + size + (size & 1)
	return PackedByteArray()


func _wait_done(id: int, seconds: float) -> Array:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		for d: Array in _done:
			if d[0] == id:
				return d
		await process_frame
	return []


func _test_server() -> void:
	var bin_dir := _bin_dir()
	var model := _model()
	if bin_dir == "" or model == "":
		print("test_whisper: SKIPPED the server part: no x86_64 whisper-server (build/whisper-build.sh x86_64) or "
				+ "no tiny.en model (build/whisper-models.sh)")
		return
	var b := _make(bin_dir, model)
	var ok: bool = await b.start()
	_check(ok and Transcriber.available(), "server starts: %s" % b.last_error)
	if not ok:
		return
	_check(Transcriber.describe() == "whisper.cpp %s, cpu, 4 threads" % model.get_file().trim_prefix("ggml-")
			.trim_suffix(".bin"), "describe: %s" % Transcriber.describe())
	_check(OS.is_process_running(b.pid), "server process runs")
	_check_loopback_only(b.port)
	_check(str(b.route).length() == 33, "a random route prefix")
	var probe: Dictionary = Backend.http_request(b.port, "GET", "/health", PackedByteArray(), "", 5.0)
	_check(int(probe["code"]) == 404, "the server answers nothing without the route (got %s)" % probe)
	probe = Backend.http_request(b.port, "GET", str(b.route) + "/health", PackedByteArray(), "", 5.0)
	_check(int(probe["code"]) == 200, "health under the route (got %s)" % probe)

	# A final of the JFK sample; a partial sent while it runs is skipped.
	var jfk := _pcm(_repo().path_join("build/whisper/samples/jfk-11s.wav"))
	_check(jfk.size() > 300000, "sample read (%d bytes)" % jfk.size())
	var t0 := Time.get_ticks_msec()
	var id := Transcriber.transcribe(jfk, true)
	_check(id > 0 and b.busy == 1, "final taken")
	_check(Transcriber.transcribe(jfk.slice(0, 64000), false) == -1, "partial skipped while the final runs")
	var frames := [0]
	var counter := func() -> void: frames[0] += 1
	process_frame.connect(counter)
	var d := await _wait_done(id, 120.0)
	process_frame.disconnect(counter)
	_check(not d.is_empty(), "final done")
	if not d.is_empty():
		var words := str(d[1]).to_lower()
		_check(d[2] == true, "final flag")
		_check(words.contains("fellow americans") and words.contains("ask not what your country can do for you"),
				"JFK text: %s" % d[1])
		print("test_whisper: final in %d ms over %d frames: %s" % [Time.get_ticks_msec() - t0, frames[0], d[1]])
		_check(frames[0] > 5, "frames went on while transcribing (%d)" % frames[0])
	_check(b.busy == 0, "not busy after the final")

	# A partial on its own (the first 3 s): greedy, done with final = false.
	var pid_ := Transcriber.transcribe(jfk.slice(0, 96000), false)
	_check(pid_ > 0, "partial taken when idle")
	d = await _wait_done(pid_, 60.0)
	_check(not d.is_empty() and d[2] == false and str(d[1]).to_lower().contains("fellow"),
			"partial text: %s" % [d])

	# The server dies: restarted once; dies again: off, with a line.
	var first_pid: int = b.pid
	_crash(first_pid)
	var deadline := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < deadline and not (b.restarts == 1 and b.call("ready")):
		await process_frame
	_check(b.restarts == 1 and b.call("ready") and b.pid != first_pid and Transcriber.available(),
			"restarted once after a crash (restarts %d, ready %s)" % [b.restarts, b.call("ready")])
	_crash(b.pid)
	deadline = Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline and Transcriber.available():
		await process_frame
	_check(not Transcriber.available() and str(b.last_error).contains("stopped again"),
			"off after the second crash: %s" % b.last_error)

	# Stop and exit kill the server.
	b.restarts = 0
	ok = await b.start()
	_check(ok, "starts again on request")
	var last_pid: int = b.pid
	b.queue_free()
	await process_frame
	await process_frame
	_check(not DirAccess.dir_exists_absolute("/proc/%d" % last_pid), "server killed when the node leaves the tree")
	_check(Transcriber.backend == null, "backend cleared")


## A crash as seen from the app: the process ends by itself (not through OS.kill, which also reaps it).
func _crash(p: int) -> void:
	OS.execute("kill", ["-9", str(p)])


## Listening on 127.0.0.1 only: /proc/net/tcp has the port bound to 0100007F, nothing on another address or IPv6;
## a connection to the machine's LAN address is refused.
func _check_loopback_only(p: int) -> void:
	var hex := "%04X" % p
	var listen_addrs := PackedStringArray()
	for f in ["/proc/net/tcp", "/proc/net/tcp6"]:
		for line in Backend.read_text(f).split("\n"):
			var cols := line.strip_edges().split(" ", false)
			if cols.size() > 3 and cols[1].ends_with(":" + hex) and cols[3] == "0A":
				listen_addrs.append(cols[1].get_slice(":", 0))
	_check(listen_addrs == PackedStringArray(["0100007F"]), "listens on 127.0.0.1 only: %s" % listen_addrs)
	for a in IP.get_local_addresses():
		if a.contains(".") and not a.begins_with("127."):
			var s := StreamPeerTCP.new()
			s.connect_to_host(a, p)
			var deadline := Time.get_ticks_msec() + 1000
			while Time.get_ticks_msec() < deadline and s.get_status() == StreamPeerTCP.STATUS_CONNECTING:
				s.poll()
				OS.delay_msec(10)
			_check(s.get_status() != StreamPeerTCP.STATUS_CONNECTED, "refused on %s:%d" % [a, p])
			s.disconnect_from_host()
			break


## ensure(): one node under the root, configured from the settings, started by itself; here (no whisper/ next to the
## engine or the app) it ends unavailable with its line.
func _test_ensure() -> void:
	var a: Node = Backend.ensure(self)
	_check(Backend.ensure(self) == a and a.name == "WhisperBackend", "ensure gives one node")
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline and str(a.last_error) == "":
		await process_frame
	_check(a.get_parent() == root, "ensure adds it under the root")
	_check(not Transcriber.available() and str(a.last_error).begins_with("no whisper-server in "),
			"ensure without a bundled server: %s" % a.last_error)
	a.queue_free()
	await process_frame
