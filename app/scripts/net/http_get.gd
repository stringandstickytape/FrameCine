extends RefCounted

## A small blocking HTTP client for worker threads (media servers, docs/media-servers.md): one request, follows up to
## 3 redirects, a whole-request timeout. request(url, method, headers, body, timeout) ->
## {code, headers: {lower-case name: value}, body: PackedByteArray, url (after redirects), error: "" or why}.
## http:// only by default; https:// works with the engine's TLS (no certificate pinning).

const MAX_BODY := 16 << 20


static func request(url: String, method := HTTPClient.METHOD_GET, headers: PackedStringArray = [],
		body := "", timeout := 8.0) -> Dictionary:
	var current := url
	for hop in 4:
		var r := _once(current, method, headers, body, timeout)
		if r["error"] == "" and int(r["code"]) in [301, 302, 303, 307, 308] and r["headers"].has("location"):
			current = resolve(current, str(r["headers"]["location"]))
			if int(r["code"]) == 303:
				method = HTTPClient.METHOD_GET
				body = ""
			continue
		r["url"] = current
		return r
	return {"code": 0, "headers": {}, "body": PackedByteArray(), "url": current, "error": "too many redirects"}


## "http://host:port/a/b" -> [scheme, host, port, path]; port 80 / 443 when absent. [] if not http(s).
static func split(url: String) -> Array:
	var tls := url.begins_with("https://")
	if not tls and not url.begins_with("http://"):
		return []
	var rest := url.substr(8 if tls else 7)
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
	return ["https" if tls else "http", host, port, path]


## A link relative to a base URL ("/x", "x", "http://...").
static func resolve(base: String, link: String) -> String:
	if link.begins_with("http://") or link.begins_with("https://"):
		return link
	var p := split(base)
	if p.is_empty():
		return link
	var origin := "%s://%s:%d" % [p[0], p[1] if not str(p[1]).contains(":") else "[%s]" % p[1], p[2]]
	if link.begins_with("/"):
		return origin + link
	var dir := str(p[3]).substr(0, str(p[3]).rfind("/") + 1)
	return origin + dir + link


static func _once(url: String, method: int, headers: PackedStringArray, body: String, timeout: float) -> Dictionary:
	var out := {"code": 0, "headers": {}, "body": PackedByteArray(), "error": ""}
	var p := split(url)
	if p.is_empty():
		out["error"] = "not an http URL: %s" % url
		return out
	var c := HTTPClient.new()
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	var err := c.connect_to_host(p[1], p[2], TLSOptions.client() if p[0] == "https" else null)
	if err != OK:
		out["error"] = "can't connect to %s:%d: %s" % [p[1], p[2], error_string(err)]
		return out
	while c.get_status() in [HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING]:
		c.poll()
		if Time.get_ticks_msec() > deadline:
			out["error"] = "timed out connecting to %s:%d" % [p[1], p[2]]
			return out
		OS.delay_msec(2)
	if c.get_status() != HTTPClient.STATUS_CONNECTED:
		out["error"] = "can't connect to %s:%d (status %d)" % [p[1], p[2], c.get_status()]
		return out
	var all_headers := headers.duplicate()
	all_headers.append("User-Agent: VRVideoPlayer/1 UPnP/1.0 DLNADOC/1.50")
	err = c.request(method, p[3], all_headers, body)
	if err != OK:
		out["error"] = "request failed: %s" % error_string(err)
		return out
	while c.get_status() == HTTPClient.STATUS_REQUESTING:
		c.poll()
		if Time.get_ticks_msec() > deadline:
			out["error"] = "timed out waiting for %s" % url
			return out
		OS.delay_msec(2)
	if not c.has_response():
		out["error"] = "no response from %s (status %d)" % [url, c.get_status()]
		return out
	out["code"] = c.get_response_code()
	var h := {}
	for line in c.get_response_headers():
		var i := line.find(":")
		if i > 0:
			h[line.substr(0, i).strip_edges().to_lower()] = line.substr(i + 1).strip_edges()
	out["headers"] = h
	var buf := PackedByteArray()
	while c.get_status() == HTTPClient.STATUS_BODY:
		c.poll()
		var chunk := c.read_response_body_chunk()
		if chunk.is_empty():
			OS.delay_msec(1)
		else:
			buf.append_array(chunk)
			if buf.size() > MAX_BODY:
				out["error"] = "response over %d MB" % (MAX_BODY >> 20)
				break
		if Time.get_ticks_msec() > deadline:
			out["error"] = "timed out reading %s" % url
			break
	out["body"] = buf
	c.close()
	return out
