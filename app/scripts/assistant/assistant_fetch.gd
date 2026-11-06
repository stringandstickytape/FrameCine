extends Node

## The headset pulls a file from the assistant's machine (docs/assistant.md, "Fetching a file"): the assistant serves
## it over HTTP on the LAN and calls fetch; nothing is ever pushed into the headset. LAN only: every address the host
## resolves to (and every redirect's) must be private; http or https (a LAN server's own certificate is accepted: the
## address check is the trust here). One download at a time, on a worker thread, into FOLDER_NAME under the videos
## folder (made on first use, listed in the file browser's places). Checked against the disk: the announced size
## (Content-Length) must leave KEEP_FREE free, and a body longer than announced stops it; without a size, it stops
## when the disk gets down to KEEP_FREE. A failed or cancelled download leaves nothing behind (the .part file goes).
## Opens the file when done if asked, with a mode overriding the guess.
##
##   AssistantFetch.ensure(tree) -> node
##   await start(url, name, open, mode, to) -> {ok, result | error, refused}   to: a path inside the Library instead
##   cancel() -> {ok, ...};  status() -> {...} or null (in /state)
##   signal event(data)   {state: started | progress | done | failed | cancelled, name, ...}: the `download` event
## The card on the headset shows the progress, with Cancel.

signal event(data: Dictionary)

const RemoteServer := preload("res://scripts/remote/remote_server.gd")
const VideoMode := preload("res://scripts/video_mode.gd")
const LibraryIndex := preload("res://scripts/library/library_index.gd")
const LibraryCopy := preload("res://scripts/library/library_copy.gd")
const NODE_NAME := "AssistantFetch"
const FOLDER_NAME := "From assistant" # i18n
## Bytes kept free on the disk.
const KEEP_FREE := 2 * 1024 * 1024 * 1024
const MAX_REDIRECTS := 5
## Progress events and the card: at most this often (seconds).
const PROGRESS_EVERY := 1.0
const CONNECT_TIMEOUT_MSEC := 10000
## No bytes for this long: failed.
const STALL_TIMEOUT_MSEC := 30000
const RESOLVE_TIMEOUT_MSEC := 5000
const CARD_ID := "download"
const NAME_MAX := 120
const TYPES := {"video/mp4": "mp4", "video/x-matroska": "mkv", "video/webm": "webm", "video/quicktime": "mov",
		"video/mp2t": "ts", "video/x-msvideo": "avi", "image/jpeg": "jpg", "image/png": "png", "audio/mpeg": "mp3",
		"audio/flac": "flac", "application/x-matroska": "mkv"}

## Tests: another folder, the loopback allowed (a server in the test), a pretend amount of free space.
static var folder_override := ""
static var _folder := ""
static var allow_loopback := false
static var free_space_override := -1

var _thread: Thread
var _mutex := Mutex.new()
## The download now (shared with the thread under _mutex): url, name, path, part, open, mode, state, bytes, total,
## reason, cancel, started_msec.
var _job := {}
var _last_progress_msec := 0
var _last_bytes := 0


static func ensure(tree: SceneTree) -> Node:
	var n := tree.root.get_node_or_null(NODE_NAME)
	if n != null:
		return n
	if tree.root.has_meta(NODE_NAME) and is_instance_valid(tree.root.get_meta(NODE_NAME)):
		return tree.root.get_meta(NODE_NAME)
	n = (load("res://scripts/assistant/assistant_fetch.gd") as GDScript).new()
	n.name = NODE_NAME
	tree.root.set_meta(NODE_NAME, n)
	tree.root.add_child.call_deferred(n)
	return n


## The download folder: ~/Videos/From assistant (the system's videos folder).
static func folder() -> String:
	if folder_override != "":
		return folder_override
	# Asked once: on Linux OS.get_system_dir() runs xdg-user-dir (about 45 ms on the headset).
	if _folder == "":
		var videos := OS.get_system_dir(OS.SYSTEM_DIR_MOVIES)
		if videos == "":
			videos = OS.get_environment("HOME").path_join("Videos")
		_folder = videos.path_join(FOLDER_NAME)
	return _folder


# --- Checks ----------------------------------------------------------------------------------------------------------

## {scheme, host, port, path} or {error}.
static func parse_url(u: String) -> Dictionary:
	var scheme := u.get_slice("://", 0).to_lower() if u.contains("://") else ""
	if not (scheme in ["http", "https"]):
		return {"error": "only http:// or https:// URLs (a server on this network)"}
	var rest := u.get_slice("://", 1)
	var authority := rest.get_slice("/", 0).get_slice("?", 0).get_slice("#", 0)
	var path := rest.substr(authority.length())
	if path == "" or path.begins_with("?"):
		path = "/" + path
	path = path.get_slice("#", 0)
	if authority.contains("@"):
		return {"error": "no user names or passwords in the URL"}
	var host := authority
	var port := 443 if scheme == "https" else 80
	if authority.begins_with("["):
		host = authority.trim_prefix("[").get_slice("]", 0)
		var after := authority.get_slice("]", 1)
		if after.begins_with(":"):
			port = after.trim_prefix(":").to_int()
	elif authority.contains(":"):
		host = authority.get_slice(":", 0)
		port = authority.get_slice(":", 1).to_int()
	if host == "" or port <= 0 or port > 65535:
		return {"error": "no host in the URL"}
	return {"scheme": scheme, "host": host, "port": port, "path": path}


## Why an address may not be fetched from, or "".
static func address_refusal(address: String) -> String:
	var loopback := address.begins_with("127.") or address == "::1"
	if loopback and not allow_loopback:
		return "%s is this headset itself, not a machine on the network" % address
	if not RemoteServer.is_private(address):
		return "%s is not on this network (a private address); the headset fetches from the LAN only" % address
	return ""


## The host's addresses, all of which must be private: "" or the reason. Blocking (the worker thread's redirects).
static func host_refusal_now(host: String) -> String:
	var addresses: Array = [host] if host.is_valid_ip_address() else Array(IP.resolve_hostname_addresses(host))
	return _addresses_refusal(host, addresses)


static func _addresses_refusal(host: String, addresses: Array) -> String:
	if addresses.is_empty():
		return "%s does not resolve to an address" % host
	for a: Variant in addresses:
		var why := address_refusal(str(a))
		if why != "":
			return why if str(a) == host else "%s resolves to %s" % [host, why]
	return ""


## The same on the main thread without blocking it: the name resolved in the background.
func _host_refusal(host: String) -> String:
	return await host_refusal(get_tree(), host)


static func host_refusal(tree: SceneTree, host: String) -> String:
	if host.is_valid_ip_address():
		return _addresses_refusal(host, [host])
	var id := IP.resolve_hostname_queue_item(host, IP.TYPE_ANY)
	if id == IP.RESOLVER_INVALID_ID:
		return "could not look up %s" % host
	var end := Time.get_ticks_msec() + RESOLVE_TIMEOUT_MSEC
	while IP.get_resolve_item_status(id) == IP.RESOLVER_STATUS_WAITING and Time.get_ticks_msec() < end:
		await tree.process_frame
	var addresses: Array = Array(IP.get_resolve_item_addresses(id)) \
			if IP.get_resolve_item_status(id) == IP.RESOLVER_STATUS_DONE else []
	IP.erase_resolve_item(id)
	return _addresses_refusal(host, addresses)


## A mode id for VideoMode.from_id (e.g. 360, 180_sbs, sbs, flat_tb_half), or the reason it isn't one.
static func mode_refusal(mode: String) -> String:
	for part in mode.to_lower().split("_", false):
		if not (part in VideoMode.PROJECTION_IDS or part in VideoMode.LAYOUT_IDS or part in ["half", "swap"]
				or (part.begins_with("fov") and part.trim_prefix("fov").is_valid_float())):
			return "mode: %s is not a part of a mode (%s, %s, half, swap, fov<degrees>; e.g. 360, 180_sbs, sbs)" % [
				part, ", ".join(VideoMode.PROJECTION_IDS), ", ".join(VideoMode.LAYOUT_IDS)]
	return ""


## A plain file name: no folders, no control or reserved characters, not hidden, at most NAME_MAX characters.
static func clean_name(n: String) -> String:
	var out := ""
	for ch in n.strip_edges():
		var c := ch.unicode_at(0)
		if c < 32 or c == 127 or ch in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]:
			out += "_"
		else:
			out += ch
	out = out.strip_edges().lstrip(".").strip_edges()
	if out.length() > NAME_MAX:
		var ext := out.get_extension()
		out = out.left(NAME_MAX - ext.length() - 1) + "." + ext if ext != "" and ext.length() < 8 \
				else out.left(NAME_MAX)
	return out


## The name the file gets: the given one (or the URL's), with the URL's or the content type's extension when it has
## none; "download" at worst.
static func file_name(given: String, url_path: String, content_type: String) -> String:
	var from_url := clean_name(url_path.get_slice("?", 0).get_file().uri_decode())
	var n := clean_name(given) if clean_name(given) != "" else from_url
	if n == "":
		n = "download"
	if n.get_extension() == "" or n.get_extension().length() > 5:
		var ext := from_url.get_extension().to_lower()
		var t := content_type.get_slice(";", 0).strip_edges().to_lower()
		if TYPES.has(t):
			ext = TYPES[t]
		if ext != "":
			n += "." + ext
	return n


## A path in dir for name that isn't taken: "name.mkv", "name (2).mkv", ...
static func free_path(dir: String, n: String) -> String:
	var p := dir.path_join(n)
	var i := 2
	while FileAccess.file_exists(p) or FileAccess.file_exists(p + ".part"):
		p = dir.path_join("%s (%d)%s" % [n.get_basename(), i, "." + n.get_extension() if n.get_extension() != ""
				else ""])
		i += 1
	return p


static func space_left(dir: String) -> int:
	if free_space_override >= 0:
		return free_space_override
	var d := DirAccess.open(dir)
	return int(d.get_space_left()) if d != null else -1


static func gb(bytes: int) -> String:
	return "%.1f GB" % (bytes / 1073741824.0) if bytes >= 107374182 else "%.0f MB" % (bytes / 1048576.0)


# --- The download --------------------------------------------------------------------------------------------------

func busy() -> bool:
	return not _job.is_empty()


func start(url: String, name := "", open := true, mode := "", to := "") -> Dictionary:
	if busy():
		return {"ok": false, "refused": true, "error": "a download is already running (%s): one at a time; "
				% _job.get("name", "") + "fetch_cancel stops it"}
	var u := parse_url(url.strip_edges())
	if u.has("error"):
		return {"ok": false, "refused": true, "error": u["error"]}
	if mode != "" and mode_refusal(mode) != "":
		return {"ok": false, "error": mode_refusal(mode)}
	if to != "":
		if LibraryCopy.to_refusal(to) != "":
			return {"ok": false, "refused": true, "error": LibraryCopy.to_refusal(to)}
		if FileAccess.file_exists(LibraryIndex.root().path_join(to)):
			return {"ok": false, "refused": true, "error": "%s is already in the Library" % to}
	var why: String = await _host_refusal(str(u["host"]))
	if why != "":
		return {"ok": false, "refused": true, "error": why}
	if busy():
		return {"ok": false, "refused": true, "error": "a download is already running"}
	var dir := folder() if to == "" else LibraryIndex.root().path_join(to).get_base_dir()
	if to != "":
		name = to.get_file()
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		return {"ok": false, "error": "could not make the folder %s" % dir}
	var shown := file_name(name, str(u["path"]), "")
	_job = {"url": url.strip_edges(), "given": name, "name": shown, "path": "", "part": "", "open": open,
			"mode": mode, "state": "connecting", "bytes": 0, "total": -1, "reason": "", "cancel": false,
			"started_msec": Time.get_ticks_msec(), "dir": dir}
	_last_progress_msec = Time.get_ticks_msec()
	_last_bytes = 0
	_thread = Thread.new()
	_thread.start(_work)
	_event({"state": "started", "name": shown, "url": _job["url"]})
	_card("Downloading %s ..." % shown, true)
	return {"ok": true, "result": {"state": "started", "name": shown, "folder": dir,
			"events": "download: progress at most once a second, then done (path), failed (reason) or cancelled"}}


func cancel() -> Dictionary:
	if not busy():
		return {"ok": false, "error": "no download is running"}
	_mutex.lock()
	_job["cancel"] = true
	var n := str(_job["name"])
	_mutex.unlock()
	return {"ok": true, "result": {"cancelling": n}}


## The download in progress for /state, or null.
func status() -> Variant:
	if not busy():
		return null
	_mutex.lock()
	var s := {"name": _job["name"], "url": _job["url"], "state": _job["state"], "bytes": _job["bytes"],
			"total": _job["total"]}
	_mutex.unlock()
	return s


func _process(_delta: float) -> void:
	if not busy():
		return
	_mutex.lock()
	var state := str(_job["state"])
	var bytes := int(_job["bytes"])
	var total := int(_job["total"])
	var n := str(_job["name"])
	_mutex.unlock()
	if state in ["done", "failed", "cancelled"]:
		_finish()
		return
	if _thread != null and not _thread.is_alive():
		# The worker ended without saying how (a script error): failed, and nothing left behind.
		_mutex.lock()
		_job["state"] = "failed"
		_job["reason"] = "the download stopped unexpectedly"
		var part := str(_job.get("part", ""))
		_mutex.unlock()
		if part != "":
			DirAccess.remove_absolute(part)
		_finish()
		return
	var now := Time.get_ticks_msec()
	if state == "body" and now - _last_progress_msec >= PROGRESS_EVERY * 1000.0:
		var rate := (bytes - _last_bytes) * 1000.0 / maxf(now - _last_progress_msec, 1.0)
		_last_progress_msec = now
		_last_bytes = bytes
		_event({"state": "progress", "name": n, "bytes": bytes, "total": total, "rate": roundi(rate)})
		_card_text("Downloading %s, %s%s" % [n, gb(bytes), " of " + gb(total) if total > 0 else ""])


func _finish() -> void:
	_thread.wait_to_finish()
	_thread = null
	var job := _job.duplicate()
	_job = {}
	var n := str(job["name"])
	match str(job["state"]):
		"done":
			var path := str(job["path"])
			_event({"state": "done", "name": n, "path": path, "bytes": job["bytes"]})
			var main := get_tree().current_scene if is_inside_tree() else null
			if bool(job["open"]) and main != null and main.has_method("open_path"):
				if str(job["mode"]) != "":
					main.settings.set_file_mode(path, VideoMode.from_id(str(job["mode"])).to_id())
				main.open_path(path)
				_card("%s is here (%s); opening it." % [n, gb(int(job["bytes"]))], false, 8.0)
			else:
				_card("%s is here (%s), in %s." % [n, gb(int(job["bytes"])), FOLDER_NAME], false, 10.0)
		"failed":
			_event({"state": "failed", "name": n, "reason": job["reason"]})
			_card("Downloading %s failed: %s" % [n, job["reason"]], false, 12.0)
		_:
			_event({"state": "cancelled", "name": n})
			_card("Download of %s cancelled." % n, false, 5.0)


func _event(d: Dictionary) -> void:
	event.emit(d)


func _card_node() -> Node:
	var main := get_tree().current_scene if is_inside_tree() else null
	if main == null or main.get("ui") == null:
		return null
	var card: Node = main.ui.get("card")
	return card if card != null and card.has_method("show_card") else null


func _card(text: String, with_cancel: bool, seconds := 0.0) -> void:
	var card := _card_node()
	if card == null:
		return
	var data := {"id": CARD_ID, "title": "From the assistant", "text": text, "seconds": seconds}
	if with_cancel:
		data["actions"] = [{"id": "cancel", "label": "Cancel download"}]
	card.show_card(data)
	if with_cancel and card.has_signal("dismissed") and not card.dismissed.is_connected(_on_card_dismissed):
		card.dismissed.connect(_on_card_dismissed)


func _card_text(text: String) -> void:
	var card := _card_node()
	if card != null and card.has_method("set_card_text"):
		card.set_card_text(CARD_ID, text)


func _on_card_dismissed(id: String, how: String) -> void:
	if id == CARD_ID and how == "cancel" and busy():
		cancel()


# --- The worker thread -----------------------------------------------------------------------------------------------

func _job_get(key: String) -> Variant:
	_mutex.lock()
	var v: Variant = _job.get(key)
	_mutex.unlock()
	return v


func _set_job(values: Dictionary) -> void:
	_mutex.lock()
	_job.merge(values, true)
	_mutex.unlock()


## Ends the download as failed (or cancelled, when asked to): always false.
func _fail(reason: String) -> bool:
	_set_job({"state": "cancelled" if bool(_job_get("cancel")) else "failed", "reason": reason})
	return false


func _work() -> void:
	_download()


func _download() -> bool:
	var url := str(_job_get("url"))
	var client := HTTPClient.new()
	for hop in MAX_REDIRECTS + 1:
		var u := parse_url(url)
		if u.has("error"):
			return _fail(str(u["error"]))
		if hop > 0:
			var why := host_refusal_now(str(u["host"]))
			if why != "":
				return _fail("redirected to %s: %s" % [url, why])
		var tls: TLSOptions = TLSOptions.client_unsafe() if u["scheme"] == "https" else null
		if client.connect_to_host(str(u["host"]), int(u["port"]), tls) != OK:
			return _fail("could not connect to %s" % u["host"])
		var end := Time.get_ticks_msec() + CONNECT_TIMEOUT_MSEC
		while client.get_status() in [HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING]:
			if bool(_job_get("cancel")):
				return _fail("cancelled")
			if Time.get_ticks_msec() > end:
				return _fail("%s did not answer" % u["host"])
			client.poll()
			OS.delay_msec(5)
		if client.get_status() != HTTPClient.STATUS_CONNECTED:
			return _fail("could not connect to %s:%d" % [u["host"], u["port"]])
		if client.request(HTTPClient.METHOD_GET, str(u["path"]), ["User-Agent: FrameVRPlayer", "Accept: */*"]) != OK:
			return _fail("the request could not be sent")
		end = Time.get_ticks_msec() + STALL_TIMEOUT_MSEC
		while client.get_status() == HTTPClient.STATUS_REQUESTING:
			if bool(_job_get("cancel")):
				return _fail("cancelled")
			if Time.get_ticks_msec() > end:
				return _fail("the server did not answer")
			client.poll()
			OS.delay_msec(5)
		if not (client.get_status() in [HTTPClient.STATUS_BODY, HTTPClient.STATUS_CONNECTED]):
			return _fail("the connection failed")
		var code := client.get_response_code()
		var headers := {}
		for line: String in client.get_response_headers():
			if line.contains(":"):
				headers[line.get_slice(":", 0).strip_edges().to_lower()] = line.substr(line.find(":") + 1).strip_edges()
		if code in [301, 302, 303, 307, 308] and headers.has("location"):
			url = _resolve_location(url, u, str(headers["location"]))
			client.close()
			continue
		if code != 200:
			return _fail("the server answered %d" % code)
		return _body(client, u, headers)
	return _fail("more than %d redirects" % MAX_REDIRECTS)


static func _resolve_location(base: String, u: Dictionary, loc: String) -> String:
	if loc.contains("://"):
		return loc
	var origin := "%s://%s:%d" % [u["scheme"], ("[%s]" % u["host"]) if str(u["host"]).contains(":") else u["host"],
			u["port"]]
	if loc.begins_with("/"):
		return origin + loc
	return origin + str(u["path"]).get_slice("?", 0).get_base_dir().path_join(loc)


func _body(client: HTTPClient, u: Dictionary, headers: Dictionary) -> bool:
	var total := client.get_response_body_length() if client.has_response() else -1
	if headers.has("content-length"):
		total = str(headers["content-length"]).to_int()
	var dir := str(_job_get("dir"))
	var left := space_left(dir)
	if total > 0 and left >= 0 and left - total < KEEP_FREE:
		return _fail("the file is %s; the headset has %s free and keeps %s free" % [gb(total), gb(left),
				gb(KEEP_FREE)])
	var n := file_name(str(_job_get("given")), str(u["path"]), str(headers.get("content-type", "")))
	var path := free_path(dir, n)
	var part := path + ".part"
	var f := FileAccess.open(part, FileAccess.WRITE)
	if f == null:
		return _fail("could not write %s" % part)
	_set_job({"name": path.get_file(), "path": path, "part": part, "total": total, "state": "body"})
	var bytes := 0
	var last_data := Time.get_ticks_msec()
	var next_space_check := 64 * 1024 * 1024
	var why := ""
	while client.get_status() == HTTPClient.STATUS_BODY:
		if bool(_job_get("cancel")):
			why = "cancelled"
			break
		client.poll()
		var chunk := client.read_response_body_chunk()
		if chunk.is_empty():
			if Time.get_ticks_msec() - last_data > STALL_TIMEOUT_MSEC:
				why = "no data for %d s" % (STALL_TIMEOUT_MSEC / 1000)
				break
			OS.delay_msec(2)
			continue
		last_data = Time.get_ticks_msec()
		bytes += chunk.size()
		if total > 0 and bytes > total:
			why = "the server sent more than the %s it announced" % gb(total)
			break
		f.store_buffer(chunk)
		if bytes >= next_space_check:
			next_space_check += 64 * 1024 * 1024
			left = space_left(dir)
			if left >= 0 and left < KEEP_FREE:
				why = "the disk is down to %s free (it keeps %s)" % [gb(left), gb(KEEP_FREE)]
				break
		_set_job({"bytes": bytes})
	f.close()
	client.close()
	if why == "" and total > 0 and bytes < total:
		why = "the connection closed at %s of %s" % [gb(bytes), gb(total)]
	if why == "" and bool(_job_get("cancel")):
		why = "cancelled"
	if why != "":
		DirAccess.remove_absolute(part)
		return _fail(why)
	if DirAccess.rename_absolute(part, path) != OK:
		DirAccess.remove_absolute(part)
		return _fail("could not rename the finished file")
	_set_job({"bytes": bytes, "state": "done"})
	return true


func _exit_tree() -> void:
	if _thread != null:
		_mutex.lock()
		_job["cancel"] = true
		_mutex.unlock()
		_thread.wait_to_finish()
		_thread = null
