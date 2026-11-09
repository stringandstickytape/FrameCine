extends RefCounted

## One HTTP GET for the updater, blocking: it runs on the updater's own thread, never on the main thread
## (docs/framedrop.md, "Offline: never wait for the network"). HTTPClient, polled, so every wait has a limit: the name
## lookup, the connection, TLS and each read check the deadline, the stall time and the cancel flag between polls.
## Redirects are followed (GitHub sends /releases/latest/download/... on to the release's file host).
##
##   fetch(url, {deadline_msec, stall_msec, max_bytes}, progress)              -> {ok, code, error, body}
##   fetch(url, {file, offset, stall_msec, deadline_msec}, progress)           -> {ok, code, error, bytes, restarted}
##
## deadline_msec: an absolute Time.get_ticks_msec() limit for the whole fetch (0: none). stall_msec: the longest time
## with no bytes (0: none). With `file`, the body goes to that file: offset > 0 asks for the rest (a Range request)
## and appends; a server that answers 200 instead starts the file again (restarted). 416 (the range is past the end)
## comes back as code 416, for the caller to check what it has.

const USER_AGENT := "framecine-updater"
const MAX_REDIRECTS := 5
const POLL_MSEC := 5


## Shared between the thread and the main thread: bytes so far, the total when known, and the cancel flag.
class Progress:
	var _m := Mutex.new()
	var _received := 0
	var _total := -1
	var _cancelled := false

	func set_bytes(received: int, total: int) -> void:
		_m.lock()
		_received = received
		_total = total
		_m.unlock()

	func received() -> int:
		_m.lock()
		var r := _received
		_m.unlock()
		return r

	func total() -> int:
		_m.lock()
		var t := _total
		_m.unlock()
		return t

	func cancel() -> void:
		_m.lock()
		_cancelled = true
		_m.unlock()

	func cancelled() -> bool:
		_m.lock()
		var c := _cancelled
		_m.unlock()
		return c


## {tls, host, port, path} of an http(s) URL, or {} when it is not one (or has credentials in it).
static func split_url(url: String) -> Dictionary:
	var tls := url.begins_with("https://")
	if not tls and not url.begins_with("http://"):
		return {}
	var rest := url.substr(8 if tls else 7)
	var slash := rest.find("/")
	var hostport := rest if slash < 0 else rest.left(slash)
	var path := "/" if slash < 0 else rest.substr(slash)
	if hostport == "" or "@" in hostport:
		return {}
	var host := hostport
	var port := 443 if tls else 80
	var colon := hostport.rfind(":")
	if colon > 0 and hostport.substr(colon + 1).is_valid_int():
		host = hostport.left(colon)
		port = hostport.substr(colon + 1).to_int()
	return {"tls": tls, "host": host, "port": port, "path": path}


## A Location header against the URL it came from.
static func resolve(base: String, location: String) -> String:
	if location.begins_with("https://") or location.begins_with("http://"):
		return location
	var b := split_url(base)
	if b.is_empty():
		return ""
	var origin := ("https://" if b["tls"] else "http://") + str(b["host"]) + ":" + str(b["port"])
	if location.begins_with("/"):
		return origin + location
	var dir := str(b["path"]).split("?")[0]
	return origin + dir.left(dir.rfind("/") + 1) + location


static func _header(headers: Dictionary, name: String) -> String:
	for k: String in headers:
		if k.to_lower() == name:
			return str(headers[k]).strip_edges()
	return ""


static func _fail(why: String, code := 0) -> Dictionary:
	return {"ok": false, "code": code, "error": why, "body": PackedByteArray(), "bytes": 0, "restarted": false}


## Why a wait must end now ("" if it may go on).
static func _limit(opts: Dictionary, last_byte_msec: int, progress: Progress) -> String:
	var now := Time.get_ticks_msec()
	if progress != null and progress.cancelled():
		return "cancelled"
	var deadline := int(opts.get("deadline_msec", 0))
	if deadline > 0 and now >= deadline:
		return "timed out"
	var stall := int(opts.get("stall_msec", 0))
	if stall > 0 and now - last_byte_msec >= stall:
		return "no data for %d s" % (stall / 1000)
	return ""


static func fetch(url: String, opts: Dictionary, progress: Progress = null) -> Dictionary:
	var current := url
	for _hop in MAX_REDIRECTS + 1:
		var r := _fetch_once(current, opts, progress)
		var location := str(r.get("location", ""))
		if location == "":
			return r
		current = resolve(current, location)
		if current == "":
			return _fail("a redirect to %s" % location)
	return _fail("too many redirects")


static func _fetch_once(url: String, opts: Dictionary, progress: Progress) -> Dictionary:
	var u := split_url(url)
	if u.is_empty():
		return _fail("not an http(s) address")
	var c := HTTPClient.new()
	c.read_chunk_size = 65536
	var last := Time.get_ticks_msec()
	var err := c.connect_to_host(str(u["host"]), int(u["port"]), TLSOptions.client() if u["tls"] else null)
	if err != OK:
		return _fail("can't connect (%s)" % error_string(err))
	while true:
		c.poll()
		var st := c.get_status()
		if st == HTTPClient.STATUS_CONNECTED:
			break
		if st != HTTPClient.STATUS_RESOLVING and st != HTTPClient.STATUS_CONNECTING:
			c.close()
			return _fail(_status_text(st))
		var why := _limit(opts, last, progress)
		if why != "":
			c.close()
			return _fail(why)
		OS.delay_msec(POLL_MSEC)

	var file_path := str(opts.get("file", ""))
	var offset := int(opts.get("offset", 0)) if file_path != "" else 0
	var headers := PackedStringArray(["User-Agent: " + USER_AGENT, "Accept: */*"])
	if offset > 0:
		headers.append("Range: bytes=%d-" % offset)
	err = c.request(HTTPClient.METHOD_GET, str(u["path"]), headers)
	if err != OK:
		c.close()
		return _fail("request failed (%s)" % error_string(err))
	while c.get_status() == HTTPClient.STATUS_REQUESTING:
		var why := _limit(opts, last, progress)
		if why != "":
			c.close()
			return _fail(why)
		OS.delay_msec(POLL_MSEC)
		c.poll()
	if not c.has_response():
		var st := c.get_status()
		c.close()
		return _fail(_status_text(st) if st != HTTPClient.STATUS_CONNECTED else "no response")
	last = Time.get_ticks_msec()
	var code := c.get_response_code()
	var resp := c.get_response_headers_as_dictionary()
	if code in [301, 302, 303, 307, 308]:
		var location := _header(resp, "location")
		c.close()
		if location == "":
			return _fail("a redirect without a location", code)
		return {"location": location}
	if code == 416 and offset > 0:
		c.close()
		return _fail("the range is past the end", 416)

	var f: FileAccess = null
	var restarted := false
	var total := -1
	var expect := c.get_response_body_length()
	if file_path != "":
		if code == 206 and offset > 0:
			var cr := _header(resp, "content-range")  # bytes START-END/TOTAL
			var m := RegEx.create_from_string("^bytes (\\d+)-(\\d+)/(\\d+|\\*)$").search(cr)
			if m == null or m.get_string(1).to_int() != offset:
				c.close()
				return _fail("the server sent another range (%s)" % cr, code)
			if m.get_string(3) != "*":
				total = m.get_string(3).to_int()
			f = FileAccess.open(file_path, FileAccess.READ_WRITE)
			if f != null:
				f.seek_end()
		elif code == 200:
			restarted = offset > 0
			offset = 0
			total = expect
			f = FileAccess.open(file_path, FileAccess.WRITE)
		else:
			c.close()
			return _fail("HTTP %d" % code, code)
		if f == null:
			c.close()
			return _fail("can't write %s (%s)" % [file_path, error_string(FileAccess.get_open_error())], code)
	elif code != 200:
		c.close()
		return _fail("HTTP %d" % code, code)

	var max_bytes := int(opts.get("max_bytes", 0))
	var body := PackedByteArray()
	var got := 0
	if progress != null:
		progress.set_bytes(offset, total)
	while c.get_status() == HTTPClient.STATUS_BODY:
		c.poll()
		var chunk := c.read_response_body_chunk()
		if chunk.size() > 0:
			got += chunk.size()
			last = Time.get_ticks_msec()
			if f != null:
				f.store_buffer(chunk)
			else:
				body.append_array(chunk)
				if max_bytes > 0 and body.size() > max_bytes:
					c.close()
					return _fail("more than %d bytes" % max_bytes, code)
			if progress != null:
				progress.set_bytes(offset + got, total)
			continue
		var why := _limit(opts, last, progress)
		if why != "":
			if f != null:
				f.close()
			c.close()
			var r := _fail(why, code)
			r["bytes"] = got
			r["restarted"] = restarted
			return r
		OS.delay_msec(POLL_MSEC)
	var end_status := c.get_status()
	c.close()
	if f != null:
		f.close()
	if (expect >= 0 and got < expect) or (expect < 0 and end_status != HTTPClient.STATUS_DISCONNECTED
			and end_status != HTTPClient.STATUS_CONNECTED):
		var r := _fail("the connection ended after %d bytes" % got, code)
		r["bytes"] = got
		r["restarted"] = restarted
		return r
	return {"ok": true, "code": code, "error": "", "body": body, "bytes": got, "restarted": restarted}


static func _status_text(st: int) -> String:
	match st:
		HTTPClient.STATUS_CANT_RESOLVE:
			return "the name does not resolve"
		HTTPClient.STATUS_CANT_CONNECT:
			return "can't connect"
		HTTPClient.STATUS_CONNECTION_ERROR:
			return "the connection failed"
		HTTPClient.STATUS_TLS_HANDSHAKE_ERROR:
			return "the TLS handshake failed"
		HTTPClient.STATUS_DISCONNECTED:
			return "disconnected"
	return "HTTP client status %d" % st
