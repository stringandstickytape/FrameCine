extends RefCounted

## The one-time download of the speech model (docs/framedrop.md "The speech model"). The package has no model; the
## first time voice is used, scripts/voice/whisper_backend.gd starts this, and the model goes to
## user://whisper-models/ (outside the install folder, so updates never fetch it again).
##
##   var dl := ModelDownload.new()
##   dl.start(ModelDownload.url(), dir, ModelDownload.MODEL_FILE, ModelDownload.MODEL_SIZE, ModelDownload.MODEL_SHA256)
##   dl.progress()     # {state, bytes, total, error, offline} from the main thread, at any time
##   dl.finish()       # once state is not "running": joins the thread
##
## One worker thread does it all; the main thread never waits (the name lookup too runs off the main thread).
## - The bytes go to NAME.part. A part from an earlier try is continued with a range request
##   (`Range: bytes=N-`); a server that ignores the range sends it all again, and the part starts over.
## - Timeouts: connect_timeout for the name lookup, the TCP connection and TLS together; then the download stops when
##   no bytes come for stall_timeout seconds. No total limit. No retries here: the caller tries again the next time
##   voice is used, and not sooner than whisper_backend.gd's RETRY_SECONDS.
## - When the part is complete, its size and SHA-256 are checked; only then is it renamed to NAME. A wrong hash
##   deletes the part.
## - HTTPS with the usual certificate check (the engine's own CA list), as the updater does; the SHA-256 in this file
##   is checked as well.
##
## Flag (after `--`): --model-url=URL takes the model from URL instead (tests, a mirror).

## The project's releases. The rename touches this line only (and fab_store.gd's PROJECT_URL).
const RELEASES := "https://github.com/stringandstickytape/FrameCine/releases/download"
## A release only for the models; it never changes and is never marked latest (tools/upload-model.sh).
const MODEL_RELEASE := "models-1"
const MODEL_FILE := "ggml-small.en-q8_0.bin"
## build/whisper-models.sh pins the same file (Hugging Face ggerganov/whisper.cpp, small.en-q8_0).
const MODEL_SIZE := 264477561
const MODEL_SHA256 := "67a179f608ea6114bd3fdb9060e762b588a3fb3bd00c4387971be4d177958067"
const MAX_REDIRECTS := 5
## Room kept free on the disk beyond the model.
const KEEP_FREE := 200 * 1024 * 1024
const USER_AGENT := "FrameCine-model/1"

var connect_timeout := 15.0
var stall_timeout := 30.0

var _thread: Thread
var _mutex := Mutex.new()
var _job := {}


## The model's address: --model-url=URL, else the release asset.
static func url() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--model-url="):
			return arg.trim_prefix("--model-url=")
	return "%s/%s/%s" % [RELEASES, MODEL_RELEASE, MODEL_FILE]


## Starts the download of `from` into dir/name (false while one runs).
func start(from: String, dir: String, name: String, size: int, sha256: String) -> bool:
	if running():
		return false
	if _thread != null:
		_thread.wait_to_finish()
	_job = {"state": "running", "url": from, "dir": dir, "name": name, "size": size, "sha256": sha256.to_lower(),
			"bytes": 0, "total": size, "error": "", "offline": false, "cancel": false, "resumed_from": 0,
			"phase": "download"}
	_thread = Thread.new()
	_thread.start(_work)
	return true


func running() -> bool:
	return str(_job_get("state")) == "running"


## {state: "running", "done" or "failed", phase ("download", then "check" while the SHA-256 is computed), bytes,
## total, error, offline (true: no network, no answer, or the connection went), resumed_from (the bytes kept from an
## earlier try)}.
func progress() -> Dictionary:
	_mutex.lock()
	var out := _job.duplicate()
	_mutex.unlock()
	out.erase("cancel")
	return out


## Asks the thread to stop (the part is kept for the next try).
func cancel() -> void:
	_job_set({"cancel": true})


## Joins the thread once it has ended (true), or does nothing while it runs (false).
func finish() -> bool:
	if _thread == null:
		return true
	if running():
		return false
	_thread.wait_to_finish()
	_thread = null
	return true


## Cancels and waits (at exit).
func stop() -> void:
	cancel()
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null


## The SHA-256 of a file, hex ("" if it can't be read). Reads in 1 MB blocks.
static func file_sha256(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	while f.get_position() < f.get_length():
		h.update(f.get_buffer(1 << 20))
	return h.finish().hex_encode()


## "" when the file has the size and the SHA-256, else why not.
static func verify(path: String, size: int, sha256: String) -> String:
	if not FileAccess.file_exists(path):
		return "no file"
	var got_size := FileAccess.get_size(path)
	if size > 0 and got_size != size:
		return "%d bytes, expected %d" % [got_size, size]
	var got := file_sha256(path)
	if got != sha256.to_lower():
		return "SHA-256 %s, expected %s" % [got, sha256]
	return ""


## "http://host:port/a?b" -> {scheme, host, port, path} or {error}.
static func parse_url(u: String) -> Dictionary:
	var tls := u.begins_with("https://")
	if not tls and not u.begins_with("http://"):
		return {"error": "not an http(s) address: %s" % u}
	var rest := u.substr(8 if tls else 7)
	var slash := rest.find("/")
	var hostport := rest if slash < 0 else rest.substr(0, slash)
	var path := "/" if slash < 0 else rest.substr(slash)
	var port := 443 if tls else 80
	var host := hostport
	if hostport.begins_with("["):
		var close := hostport.find("]")
		host = hostport.substr(1, close - 1)
		if hostport.length() > close + 2:
			port = int(hostport.substr(close + 2))
	elif hostport.contains(":"):
		host = hostport.get_slice(":", 0)
		port = int(hostport.get_slice(":", 1))
	if host == "":
		return {"error": "no host in %s" % u}
	return {"scheme": "https" if tls else "http", "host": host, "port": port, "path": path}


static func resolve_location(base: Dictionary, loc: String) -> String:
	if loc.contains("://"):
		return loc
	var host := ("[%s]" % base["host"]) if str(base["host"]).contains(":") else str(base["host"])
	var origin := "%s://%s:%d" % [base["scheme"], host, base["port"]]
	if loc.begins_with("/"):
		return origin + loc
	return origin + str(base["path"]).get_slice("?", 0).get_base_dir().path_join(loc)


## The first byte of a `Content-Range: bytes N-M/T` header (-1 when it has none).
static func range_start(content_range: String) -> int:
	var v := content_range.strip_edges().to_lower()
	if not v.begins_with("bytes "):
		return -1
	var span := v.substr(6).get_slice("/", 0)
	if not span.contains("-") or not span.get_slice("-", 0).is_valid_int():
		return -1
	return span.get_slice("-", 0).to_int()


# --- The worker thread -------------------------------------------------------------------------------------------

func _job_get(key: String) -> Variant:
	_mutex.lock()
	var v: Variant = _job.get(key)
	_mutex.unlock()
	return v


func _job_set(values: Dictionary) -> void:
	_mutex.lock()
	_job.merge(values, true)
	_mutex.unlock()


func _fail(why: String, offline := false) -> void:
	if bool(_job_get("cancel")):
		why = "stopped"
	_job_set({"state": "failed", "error": why, "offline": offline})


func _work() -> void:
	var dir := str(_job_get("dir"))
	var final := dir.path_join(str(_job_get("name")))
	var part := final + ".part"
	var size := int(_job_get("size"))
	DirAccess.make_dir_recursive_absolute(dir)
	if not DirAccess.dir_exists_absolute(dir):
		_fail("can't make %s" % dir)
		return
	var have := FileAccess.get_size(part) if FileAccess.file_exists(part) else 0
	if size > 0 and have > size:
		DirAccess.remove_absolute(part)
		have = 0
	var da := DirAccess.open(dir)
	var left := da.get_space_left() if da != null else -1
	if size > 0 and left >= 0 and left < size - have + KEEP_FREE:
		_fail("%d MB free on the disk; the model needs %d MB and %d MB stay free" % [left >> 20,
				(size - have) >> 20, KEEP_FREE >> 20])
		return
	_job_set({"bytes": have, "resumed_from": have})
	if size <= 0 or have < size:
		if not _fetch(part, have):
			return
	_job_set({"phase": "check"})
	var why := verify(part, size, str(_job_get("sha256")))
	if why != "":
		DirAccess.remove_absolute(part)
		_fail("the download is not the model (%s); deleted" % why)
		return
	if FileAccess.file_exists(final):
		DirAccess.remove_absolute(final)
	if DirAccess.rename_absolute(part, final) != OK:
		_fail("can't rename %s" % part)
		return
	_job_set({"state": "done", "bytes": FileAccess.get_size(final)})


## Downloads into `part` from byte `have` on, following redirects. False (and _fail) on any problem.
func _fetch(part: String, have: int) -> bool:
	var to := str(_job_get("url"))
	var client := HTTPClient.new()
	client.read_chunk_size = 256 * 1024
	for hop in MAX_REDIRECTS + 1:
		var u := parse_url(to)
		if u.has("error"):
			_fail(str(u["error"]))
			return false
		var tls: TLSOptions = TLSOptions.client() if u["scheme"] == "https" else null
		var err := client.connect_to_host(str(u["host"]), int(u["port"]), tls)
		if err != OK:
			_fail("can't connect to %s: %s" % [u["host"], error_string(err)], true)
			return false
		var end := Time.get_ticks_msec() + int(connect_timeout * 1000.0)
		while client.get_status() in [HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING]:
			if bool(_job_get("cancel")):
				_fail("stopped")
				return false
			if Time.get_ticks_msec() > end:
				_fail("%s: no connection in %d s" % [u["host"], int(connect_timeout)], true)
				return false
			client.poll()
			OS.delay_msec(5)
		match client.get_status():
			HTTPClient.STATUS_CONNECTED:
				pass
			HTTPClient.STATUS_CANT_RESOLVE:
				_fail("can't resolve %s" % u["host"], true)
				return false
			HTTPClient.STATUS_TLS_HANDSHAKE_ERROR:
				_fail("TLS handshake with %s failed" % u["host"], true)
				return false
			_:
				_fail("can't connect to %s:%d" % [u["host"], u["port"]], true)
				return false
		var headers := PackedStringArray(["User-Agent: " + USER_AGENT, "Accept: */*"])
		if have > 0:
			headers.append("Range: bytes=%d-" % have)
		if client.request(HTTPClient.METHOD_GET, str(u["path"]), headers) != OK:
			_fail("the request to %s could not be sent" % u["host"], true)
			return false
		end = Time.get_ticks_msec() + int(stall_timeout * 1000.0)
		while client.get_status() == HTTPClient.STATUS_REQUESTING:
			if bool(_job_get("cancel")):
				_fail("stopped")
				return false
			if Time.get_ticks_msec() > end:
				_fail("%s did not answer in %d s" % [u["host"], int(stall_timeout)], true)
				return false
			client.poll()
			OS.delay_msec(5)
		if not client.has_response():
			_fail("%s closed the connection without an answer" % u["host"], true)
			return false
		var code := client.get_response_code()
		var h := {}
		for line: String in client.get_response_headers():
			if line.contains(":"):
				h[line.get_slice(":", 0).strip_edges().to_lower()] = line.substr(line.find(":") + 1).strip_edges()
		if code in [301, 302, 303, 307, 308] and h.has("location"):
			to = resolve_location(u, str(h["location"]))
			client.close()
			continue
		if code == 416 and have > 0:
			# The range starts at or past the end: a part as long as the file. The check after this decides.
			client.close()
			return true
		var append := false
		if code == 206 and have > 0:
			if range_start(str(h.get("content-range", ""))) != have:
				_fail("the server sent a range from %s, not from %d" % [h.get("content-range", "?"), have])
				client.close()
				return false
			append = true
		elif code != 200:
			_fail("%s answered HTTP %d" % [u["host"], code])
			client.close()
			return false
		return _body(client, part, have if append else 0)
	_fail("more than %d redirects" % MAX_REDIRECTS)
	return false


func _body(client: HTTPClient, part: String, from: int) -> bool:
	var f: FileAccess
	if from > 0:
		f = FileAccess.open(part, FileAccess.READ_WRITE)
		if f != null:
			f.seek(from)
	else:
		f = FileAccess.open(part, FileAccess.WRITE)
	if f == null:
		_fail("can't write %s" % part)
		client.close()
		return false
	var size := int(_job_get("size"))
	var bytes := from
	_job_set({"bytes": bytes, "resumed_from": from})
	var last_data := Time.get_ticks_msec()
	var why := ""
	var offline := false
	while client.get_status() == HTTPClient.STATUS_BODY:
		if bool(_job_get("cancel")):
			why = "stopped"
			break
		client.poll()
		var chunk := client.read_response_body_chunk()
		if chunk.is_empty():
			if Time.get_ticks_msec() - last_data > int(stall_timeout * 1000.0):
				why = "no data for %d s at %d of %d bytes" % [int(stall_timeout), bytes, size]
				offline = true
				break
			OS.delay_msec(2)
			continue
		last_data = Time.get_ticks_msec()
		if size > 0 and bytes + chunk.size() > size:
			why = "the server sent more than the %d bytes of the model" % size
			break
		f.store_buffer(chunk)
		bytes += chunk.size()
		_job_set({"bytes": bytes})
	f.close()
	client.close()
	if why == "" and size > 0 and bytes < size:
		why = "the connection closed at %d of %d bytes" % [bytes, size]
		offline = true
	if why != "":
		_fail(why, offline)  # the part stays: the next try continues it
		return false
	return true
