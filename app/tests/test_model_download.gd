extends SceneTree

## The one-time speech model download (scripts/voice/model_download.gd, scripts/voice/whisper_backend.gd,
## docs/framedrop.md "The speech model"): the constants, the lookup order (the package's whisper/models/ first, then
## user://whisper-models/), the size and SHA-256 check, a download through a redirect, a download cut at half and
## continued with a range request, a server that ignores the range, a wrong hash, and the offline cases (no listener,
## a name that does not resolve, an address with no route, a server that accepts and sends nothing, one that stops
## in the body). Frames go on in each. Then the backend: it waits without a model, starts the download at the first
## use of voice, says so, says once that there is no network, does not try again before RETRY_SECONDS, and starts
## the server when the model is there. With WHISPER_TEST_DIR (the x86_64 whisper-server) and WHISPER_TEST_MODEL (a
## tiny model) it also checks that voice gets ready with a downloaded model.
## Needs python3 (app/tests/model_server.py).
## godot --headless --xr-mode off --path app --script res://tests/test_model_download.gd

const ModelDownload := preload("res://scripts/voice/model_download.gd")
const Backend := preload("res://scripts/voice/whisper_backend.gd")
const Transcriber := preload("res://scripts/voice/transcriber.gd")

const ROOT := "user://test_model_download"
const SIZE := 3 * 1024 * 1024 + 123

var _fails := 0
var _checks := 0
var _server_pid := -1
var _port := 0
var _root := ""
var _srv := ""
var _log := ""
var _sha := ""
## The longest frame seen while a download ran (ms).
var _worst_frame := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	_root = ProjectSettings.globalize_path(ROOT)
	_clear(_root)
	_srv = _root.path_join("srv")
	DirAccess.make_dir_recursive_absolute(_srv)
	_log = _root.path_join("requests.log")
	_make_model()
	_test_units()
	_test_lookup()
	if await _start_server():
		await _test_downloads()
		await _test_offline()
		await _test_backend()
		await _test_backend_real()
	else:
		_check(false, "python3 app/tests/model_server.py did not start")
	if _server_pid > 0:
		OS.kill(_server_pid)
	_clear(_root)
	print("test_model_download: %d checks, %s" % [_checks, "all passed" if _fails == 0 else "%d FAILED" % _fails])
	quit(1 if _fails > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("FAIL " + what)


func _clear(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_clear(dir.path_join(d))
	DirAccess.remove_absolute(dir)


## A file of SIZE pseudo-random bytes standing in for the model.
func _make_model() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 47800
	var b := PackedByteArray()
	b.resize(SIZE)
	for i in SIZE:
		b[i] = rng.randi() & 0xff
	var f := FileAccess.open(_srv.path_join("model.bin"), FileAccess.WRITE)
	f.store_buffer(b)
	f.close()
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(b)
	_sha = h.finish().hex_encode()


func _test_units() -> void:
	_check(ModelDownload.url() == "https://github.com/stringandstickytape/FrameCine/releases/download/"
			+ "models-1/ggml-small.en-q8_0.bin", "the default address: %s" % ModelDownload.url())
	_check(ModelDownload.MODEL_SIZE == 264477561 and ModelDownload.MODEL_SHA256.length() == 64,
			"the model's size and SHA-256 are constants")
	var u := ModelDownload.parse_url("https://example.org/a/b.bin?x=1")
	_check(u["host"] == "example.org" and u["port"] == 443 and u["path"] == "/a/b.bin?x=1", "parse https: %s" % u)
	u = ModelDownload.parse_url("http://127.0.0.1:8080")
	_check(u["port"] == 8080 and u["path"] == "/", "parse http with a port: %s" % u)
	_check(ModelDownload.parse_url("ftp://x/y").has("error"), "not http: an error")
	_check(ModelDownload.resolve_location(ModelDownload.parse_url("http://h:1/a/b"), "/c") == "http://h:1/c",
			"redirect to a path")
	_check(ModelDownload.resolve_location(ModelDownload.parse_url("http://h:1/a/b"), "https://o/x") == "https://o/x",
			"redirect to another host")
	_check(ModelDownload.range_start("bytes 1000-1999/2000") == 1000, "Content-Range start")
	_check(ModelDownload.range_start("") == -1 and ModelDownload.range_start("bytes */5") == -1, "no Content-Range")

	var p := _srv.path_join("model.bin")
	_check(ModelDownload.file_sha256(p) == _sha, "file_sha256 reads it all")
	_check(ModelDownload.verify(p, SIZE, _sha) == "", "verify: the right size and hash")
	_check(ModelDownload.verify(p, SIZE + 1, _sha).contains("expected"), "verify: a wrong size")
	_check(ModelDownload.verify(p, SIZE, "00" + _sha.substr(2)).begins_with("SHA-256"), "verify: a wrong hash")
	_check(ModelDownload.verify(p + ".nope", SIZE, _sha) == "no file", "verify: no file")


## A whisper/ folder with a stand-in whisper-server (a script that ends at once).
func _fake_server_dir(name: String) -> String:
	var d := _root.path_join(name)
	DirAccess.make_dir_recursive_absolute(d.path_join("models"))
	var f := FileAccess.open(d.path_join("whisper-server"), FileAccess.WRITE)
	f.store_string("#!/bin/sh\nexit 1\n")
	f.close()
	OS.execute("chmod", ["+x", d.path_join("whisper-server")])
	return d


func _touch(path: String, size := 1) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	var b := PackedByteArray()
	b.resize(size)
	f.store_buffer(b)
	f.close()


func _backend(dir: String, store: String, model := "small.en") -> Node:
	var b: Node = Backend.new()
	b.autostart = false
	b.whisper_dir = dir
	b.model = model
	b.model_store = ROOT.path_join(store)
	return b


func _test_lookup() -> void:
	var dir := _fake_server_dir("pkg")
	var store := _root.path_join("store1")
	var b := _backend(dir, "store1")
	# Neither: the default model is downloadable, another is not.
	_check(not b._resolve() and b._need_download, "no model anywhere: the default downloads")
	_check(str(b.last_error).contains("it downloads the first time voice is used"), "says so: %s" % b.last_error)
	var t := _backend(dir, "store1", "tiny.en")
	_check(not t._resolve() and not t._need_download, "no model anywhere: tiny.en does not download")
	_check(str(t.last_error).begins_with("no model tiny.en in " + dir + "/models"), "and says where: %s" % t.last_error)
	t.free()
	# Only in the store.
	b.model_size = 1
	_touch(store.path_join(ModelDownload.MODEL_FILE))
	_check(b._resolve() and b.model_path == store.path_join(ModelDownload.MODEL_FILE),
			"in user://whisper-models only: found there (%s)" % b.model_path)
	# In both: the package's copy first.
	_touch(dir.path_join("models").path_join(ModelDownload.MODEL_FILE))
	_check(b._resolve() and b.model_path == dir.path_join("models").path_join(ModelDownload.MODEL_FILE),
			"in both: the package's first (%s)" % b.model_path)
	DirAccess.remove_absolute(dir.path_join("models").path_join(ModelDownload.MODEL_FILE))
	# A downloaded file of the wrong size is damage: deleted, and it downloads again.
	b.model_size = 2
	_check(not b._resolve() and b._need_download and not FileAccess.file_exists(store.path_join(ModelDownload.MODEL_FILE)),
			"a stored model of the wrong size is deleted")
	var plain: Node = Backend.new()
	_check(Backend.USER_MODELS == "user://whisper-models" and plain.model_store == Backend.USER_MODELS,
			"the store is user://whisper-models")
	plain.free()
	b.free()


func _start_server() -> bool:
	_port = Backend.free_port()
	var script := ProjectSettings.globalize_path("res://tests/model_server.py")
	_server_pid = OS.create_process("python3", [script, "--dir", _srv, "--port", str(_port), "--log", _log])
	if _server_pid <= 0:
		return false
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		var c := StreamPeerTCP.new()
		if c.connect_to_host("127.0.0.1", _port) == OK:
			var t := Time.get_ticks_msec() + 300
			while c.get_status() == StreamPeerTCP.STATUS_CONNECTING and Time.get_ticks_msec() < t:
				c.poll()
				OS.delay_msec(5)
			if c.get_status() == StreamPeerTCP.STATUS_CONNECTED:
				c.disconnect_from_host()
				return true
		await create_timer(0.1).timeout
	return false


func _url(route: String) -> String:
	return "http://127.0.0.1:%d/%s" % [_port, route]


## Runs one download to its end, frame by frame; returns its last progress and notes the longest frame.
func _download(url: String, dir: String, sha := "", conn_s := 3.0, stall_s := 2.0, limit := 30.0) -> Dictionary:
	var dl := ModelDownload.new()
	dl.connect_timeout = conn_s
	dl.stall_timeout = stall_s
	_check(dl.start(url, dir, ModelDownload.MODEL_FILE, SIZE, sha if sha != "" else _sha), "start %s" % url)
	_check(not dl.start(url, dir, ModelDownload.MODEL_FILE, SIZE, _sha), "a second start while one runs is refused")
	var deadline := Time.get_ticks_msec() + int(limit * 1000.0)
	var last := Time.get_ticks_msec()
	while dl.running() and Time.get_ticks_msec() < deadline:
		await process_frame
		var now := Time.get_ticks_msec()
		_worst_frame = maxi(_worst_frame, now - last)
		last = now
	var p := dl.progress()
	if dl.running():
		dl.stop()
		p["state"] = "still running"
	dl.finish()
	return p


func _requests() -> PackedStringArray:
	var out := PackedStringArray()
	var f := FileAccess.open(_log, FileAccess.READ)
	if f == null:
		return out
	for line in f.get_as_text().split("\n", false):
		out.append(line)
	return out


func _test_downloads() -> void:
	var dir := _root.path_join("dl1")
	var final := dir.path_join(ModelDownload.MODEL_FILE)
	_worst_frame = 0
	# Through a redirect, as GitHub does.
	var p := await _download(_url("redirect/full/model.bin"), dir)
	_check(p["state"] == "done" and p["error"] == "", "a download through a redirect: %s" % p)
	_check(ModelDownload.verify(final, SIZE, _sha) == "" and not FileAccess.file_exists(final + ".part"),
			"in place, checked, no part left")
	_check(_worst_frame < 250, "frames go on during the download (longest %d ms)" % _worst_frame)

	# Cut at half: the part stays; the next try asks for the rest with a range request.
	dir = _root.path_join("dl2")
	final = dir.path_join(ModelDownload.MODEL_FILE)
	var half := SIZE / 2
	p = await _download(_url("cut/model.bin?at=%d" % half), dir)
	_check(p["state"] == "failed" and bool(p["offline"]), "cut at half: failed, as no network: %s" % p)
	_check(FileAccess.get_size(final + ".part") == half and not FileAccess.file_exists(final),
			"cut at half: the part has %d bytes, no model" % FileAccess.get_size(final + ".part"))
	var before := _requests().size()
	p = await _download(_url("full/model.bin"), dir)
	var reqs := _requests()
	_check(p["state"] == "done" and int(p["resumed_from"]) == half, "the next try continues: %s" % p)
	_check(reqs.size() == before + 1 and reqs[reqs.size() - 1] == "/full/model.bin bytes=%d-" % half,
			"with Range: bytes=%d- (%s)" % [half, reqs[reqs.size() - 1] if reqs.size() > 0 else "none"])
	_check(ModelDownload.verify(final, SIZE, _sha) == "", "continued: the right bytes")

	# A part as long as the file: 416 from the server, then the check decides.
	dir = _root.path_join("dl3")
	final = dir.path_join(ModelDownload.MODEL_FILE)
	_touch(final + ".part", 0)
	DirAccess.copy_absolute(_srv.path_join("model.bin"), final + ".part")
	p = await _download(_url("full/model.bin"), dir)
	_check(p["state"] == "done" and ModelDownload.verify(final, SIZE, _sha) == "",
			"a complete part: checked and used without a download: %s" % p)

	# A server that ignores the range: the part starts over.
	dir = _root.path_join("dl4")
	final = dir.path_join(ModelDownload.MODEL_FILE)
	_touch(final + ".part", 1000)
	p = await _download(_url("plain/model.bin"), dir)
	_check(p["state"] == "done" and int(p["resumed_from"]) == 0 and ModelDownload.verify(final, SIZE, _sha) == "",
			"the range ignored (200): started over, right bytes: %s" % p)

	# A wrong hash: nothing is put in place, the part goes.
	dir = _root.path_join("dl5")
	final = dir.path_join(ModelDownload.MODEL_FILE)
	p = await _download(_url("full/model.bin"), dir, "ab".repeat(32))
	_check(p["state"] == "failed" and not bool(p["offline"]) and str(p["error"]).contains("not the model"),
			"a wrong hash: failed: %s" % p)
	_check(not FileAccess.file_exists(final) and not FileAccess.file_exists(final + ".part"),
			"a wrong hash: no model, no part")

	# Not found.
	p = await _download(_url("full/nothing.bin"), _root.path_join("dl6"))
	_check(p["state"] == "failed" and str(p["error"]).contains("HTTP 404") and not bool(p["offline"]),
			"HTTP 404: failed: %s" % p)


func _test_offline() -> void:
	_worst_frame = 0
	var dir := _root.path_join("off")
	# Nothing listens (as with the network off: the connection is refused or never made).
	var t0 := Time.get_ticks_msec()
	var p := await _download("http://127.0.0.1:%d/x" % Backend.free_port(), dir)
	_check(p["state"] == "failed" and bool(p["offline"]), "nothing listens: failed, offline: %s" % p)
	_check(Time.get_ticks_msec() - t0 < 4000, "nothing listens: within the connect timeout")
	# A name that does not resolve.
	p = await _download("https://model-download-test.invalid/x", dir, "", 5.0)
	_check(p["state"] == "failed" and bool(p["offline"]), "a name that does not resolve: offline: %s" % p)
	# An address with no route (TEST-NET-1): the connect timeout ends it.
	t0 = Time.get_ticks_msec()
	p = await _download("http://192.0.2.1:9/x", dir, "", 1.5)
	_check(p["state"] == "failed" and bool(p["offline"]) and Time.get_ticks_msec() - t0 < 5000,
			"an address with no route: offline, in time: %s" % p)
	# A server that accepts the connection and sends nothing: the stall timeout ends it.
	t0 = Time.get_ticks_msec()
	p = await _download(_url("silent"), dir, "", 3.0, 1.5)
	var took := Time.get_ticks_msec() - t0
	_check(p["state"] == "failed" and bool(p["offline"]) and str(p["error"]).contains("did not answer"),
			"accepts and sends nothing: offline: %s" % p)
	_check(took >= 1400 and took < 5000, "accepts and sends nothing: ends after the stall timeout (%d ms)" % took)
	# One that stops in the body: the part keeps what came.
	p = await _download(_url("stall/model.bin?at=100000"), dir, "", 3.0, 1.5)
	_check(p["state"] == "failed" and bool(p["offline"]) and str(p["error"]).contains("no data"),
			"stops in the body: offline: %s" % p)
	_check(FileAccess.get_size(dir.path_join(ModelDownload.MODEL_FILE + ".part")) == 100000,
			"stops in the body: the part keeps 100000 bytes")
	_check(_worst_frame < 250, "frames go on in the offline cases (longest %d ms)" % _worst_frame)


func _wait(cond: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if cond.call():
			return true
		await process_frame
	return bool(cond.call())


func _test_backend() -> void:
	var dir := _fake_server_dir("pkg2")
	# Offline first: one notice, no new try within RETRY_SECONDS.
	var b := _backend(dir, "store2")
	b.model_size = SIZE
	b.model_sha256 = _sha
	b.connect_timeout = 2.0
	b.stall_timeout = 1.5
	b.model_url = "http://127.0.0.1:%d/x" % Backend.free_port()
	root.add_child(b)
	var ok: bool = await b.start()
	_check(not ok and b.download_state == "needed" and Transcriber.waiting == b,
			"no model: waits for voice (%s, %s)" % [b.download_state, b.last_error])
	_check(b.pid == -1 and b.notices.is_empty(), "no model: nothing started, nothing said at start")
	_check(b.describe().contains("no model yet"), "describe says so: %s" % b.describe())
	_check(not Transcriber.available(), "voice used: not available yet")
	_check(b.download_state in ["running", "failed"], "voice used: the download starts (%s)" % b.download_state)
	await _wait(func() -> bool: return b.download_state == "failed" and not b.notices.is_empty(), 5.0)
	_check(b.download_state == "failed" and b.download_offline, "offline: failed (%s)" % b.download_error)
	_check(b.notices.size() == 1 and b.notices[0] == TranslationServer.translate(Backend.TEXT_OFFLINE) % (SIZE / 1000000),
			"offline: one notice that it needs the network: %s" % [b.notices])
	_check(Transcriber.why_unavailable() == Backend.TEXT_OFFLINE % (SIZE / 1000000),
			"the assistant's card gets the same line: %s" % Transcriber.why_unavailable())
	for i in 3:
		Transcriber.available()
	await create_timer(Backend.NOTICE_DELAY + 0.3).timeout
	_check(b.download_state == "failed" and b.notices.size() == 1,
			"used again at once: no new try, no second notice (%s, %d)" % [b.download_state, b.notices.size()])
	# Once RETRY_SECONDS have passed, the next use tries again (now with a server there).
	b.model_url = _url("redirect/full/model.bin")
	b._failed_at -= int(Backend.RETRY_SECONDS * 1000.0) + 1000
	Transcriber.available()
	_check(b.download_state == "running", "after RETRY_SECONDS: the next use tries again")
	await _wait(func() -> bool: return b.download_state != "running", 20.0)
	var store := ProjectSettings.globalize_path(b.model_store)
	_check(ModelDownload.verify(store.path_join(ModelDownload.MODEL_FILE), SIZE, _sha) == "",
			"the model is in user://whisper-models after the download")
	# The stand-in server ends at once: the backend then is off, with its line, and no longer waits.
	await _wait(func() -> bool: return not b._starting, 10.0)
	_check(b.model_path == store.path_join(ModelDownload.MODEL_FILE), "the server was started with the downloaded model")
	_check(Transcriber.waiting == null and not Transcriber.available() and str(b.last_error).contains("exited"),
			"a server that does not start: off, with its line (%s)" % b.last_error)
	_check(b.notices.size() == 1, "a download that ended before the notice's delay: no stale notice (%s)" % [b.notices])
	b.queue_free()
	await process_frame

	# Leaving the tree mid-download stops it and keeps the part.
	var c := _backend(dir, "store3")
	c.model_size = SIZE
	c.model_sha256 = _sha
	c.stall_timeout = 30.0
	c.model_url = _url("stall/model.bin?at=200000")
	root.add_child(c)
	await c.start()
	Transcriber.available()
	await _wait(func() -> bool: return c._percent() > 0, 5.0)
	# The notice comes NOTICE_DELAY after the last use (the release of the button), with the size and how far.
	await create_timer(Backend.NOTICE_DELAY + 0.3).timeout
	var want := TranslationServer.translate(Backend.TEXT_DOWNLOADING) % [SIZE / 1000000, 200000 * 100 / SIZE]
	_check(c.notices.size() == 1 and c.notices[0] == want, "the notice: what downloads, how big, how far: %s" % [c.notices])
	_check(Transcriber.why_unavailable() == Backend.TEXT_DOWNLOADING % [SIZE / 1000000, 200000 * 100 / SIZE],
			"the card's line while it downloads: %s" % Transcriber.why_unavailable())
	_check(c.describe().contains("downloading the model: 6 %"), "describe: %s" % c.describe())
	var t0 := Time.get_ticks_msec()
	c.queue_free()
	await process_frame
	await process_frame
	_check(Time.get_ticks_msec() - t0 < 1000, "the node goes at once mid-download (%d ms)" % (Time.get_ticks_msec() - t0))
	_check(FileAccess.get_size(ProjectSettings.globalize_path(ROOT.path_join("store3")).path_join(
			ModelDownload.MODEL_FILE + ".part")) == 200000, "and the part stays for the next try")
	_check(Transcriber.waiting == null, "and nothing waits any more")


## The real whisper-server with a downloaded tiny model, when the environment points at them.
func _test_backend_real() -> void:
	var bin_dir := OS.get_environment("WHISPER_TEST_DIR")
	var model := OS.get_environment("WHISPER_TEST_MODEL")
	if bin_dir == "" or model == "" or not FileAccess.file_exists(bin_dir.path_join("whisper-server")) \
			or not FileAccess.file_exists(model):
		print("test_model_download: SKIPPED the real server part (set WHISPER_TEST_DIR and WHISPER_TEST_MODEL)")
		return
	var srv_model := _srv.path_join("tiny.bin")
	DirAccess.copy_absolute(model, srv_model)
	var b := _backend(bin_dir, "store4")
	b.model_size = FileAccess.get_size(srv_model)
	b.model_sha256 = ModelDownload.file_sha256(srv_model)
	b.model_url = _url("redirect/full/tiny.bin")
	root.add_child(b)
	await b.start()
	_check(b.download_state == "needed", "real: waits for voice")
	Transcriber.available()
	var ok: bool = await _wait(func() -> bool: return Transcriber.available_now(), 90.0)
	_check(ok, "real: voice gets ready with the downloaded model (%s)" % b.last_error)
	await create_timer(0.2).timeout
	_check(b.notices.size() > 0 and b.notices[b.notices.size() - 1] == TranslationServer.translate(Backend.TEXT_READY),
			"real: says voice is ready: %s" % [b.notices])
	_check(Transcriber.waiting == null and b.download_state == "", "real: nothing waits any more")
	b.queue_free()
	await process_frame
