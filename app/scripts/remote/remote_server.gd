extends Node

## The phone remote's HTTP server (idea #13; docs/remote.md): one static page (app/remote/index.html) and one JSON
## endpoint over the same command registry the PC link uses (scripts/dev/dev_commands.gd), so both share one API.
## Made by remote.gd only when the user turns the remote on.
##
## LAN only: it binds to every interface, but a connection from an address that is not private (10/8, 172.16/12,
## 192.168/16, 169.254/16, 127/8, IPv6 loopback, link-local and unique-local) is closed at once. Every API call also
## needs the pairing code ([remote] key, made once and kept; new_key() changes it), which the QR code carries in the
## URL, so a phone that only knows the address can do nothing. The code is never printed to the log.
##
## The phone may read, and use control-level commands (play, pause, seek, open, volume, typing, opening a URL). It may
## not change the scene, write settings files, reload or run code (those are dev-link commands).
##
## Never blocks the frame: the listening socket and each connection are polled in _process(), requests are parsed
## from what has arrived, and replies are written with put_partial_data().

## The address or the code changed, or the server started: the URL to show and its QR code.
signal address_changed(url: String, qr: Image)

const DevCommands := preload("res://scripts/dev/dev_commands.gd")
const CommandHost := preload("res://scripts/dev/command_host.gd")
const QrCode := preload("res://scripts/remote/qr_code.gd")
const ShareRoutes := preload("res://scripts/remote/share_routes.gd")
const Uri := preload("res://scripts/net/uri.gd")

const DEFAULT_PORT := 47880
const PAGE := "res://remote/index.html"
const MAX_CONNECTIONS := 16
const MAX_REQUEST := 256 * 1024
const CONNECTION_TIMEOUT := 10.0
## Re-check the device's addresses this often (Wi-Fi may change networks).
const ADDRESS_CHECK := 10.0
const ALLOWED_LEVELS: Array[String] = ["read", "control"]

## AppSettings (scripts/app_settings.gd), set by remote.gd.
var settings: RefCounted
## What this server serves (remote.gd sets them): the phone remote (/, /api) and the headset's files (/share...).
var remote_enabled := true
var share_enabled := false
var uploads := 0
var downloads := 0
var port := DEFAULT_PORT
var requests := 0
var refused := 0
var _server: TCPServer
## [{peer, in, out, out_pos, since, busy}]
var _conns: Array[Dictionary] = []
var _key := ""
var _url := ""
var _qr_modules: Array = []
var _address_timer := 0.0
var _error := ""


func _ready() -> void:
	port = int(settings.get_value("remote", "port", DEFAULT_PORT))
	_key = str(settings.get_value("remote", "key", ""))
	if _key.length() < 8:
		new_key()
	CommandHost.ensure(get_tree())
	_server = TCPServer.new()
	var err := _server.listen(port, "*")
	if err != OK:
		_error = "can't listen on port %d: %s" % [port, error_string(err)]
		push_error("Phone remote: " + _error)
		set_process(false)
		return
	_update_address(true)
	var what: PackedStringArray = []
	if remote_enabled:
		what.append("remote")
	if share_enabled:
		what.append("files")
	print("Phone remote server: on, http://%s:%d/ (%s; the pairing code is shown in the pane)" % [_url_host(), port,
			" and ".join(what)])


func _exit_tree() -> void:
	for c in _conns:
		(c["peer"] as StreamPeerTCP).disconnect_from_host()
	_conns.clear()
	if _server != null:
		_server.stop()
	print("Phone remote: off")


## A new pairing code: phones paired with the old one stop working.
func new_key() -> void:
	var bytes := Crypto.new().generate_random_bytes(6)
	_key = bytes.hex_encode()
	settings.set_value("remote", "key", _key)
	if _server != null and _server.is_listening():
		_update_address(true)


func get_url() -> String:
	return _url


func get_qr_modules() -> Array:
	return _qr_modules


## The QR code of get_url() as an image, `scale` pixels per module with a light border.
func get_qr_image(scale := 8) -> Image:
	return QrCode.to_image(_qr_modules, scale) if not _qr_modules.is_empty() else null


func status() -> Dictionary:
	return {"running": _server != null and _server.is_listening(), "port": port, "address": _url_host(),
			"connections": _conns.size(), "requests": requests, "refused": refused, "error": _error,
			"remote": remote_enabled, "share": share_enabled, "uploads": uploads, "downloads": downloads}


## The share page's address (with the pairing code), for the pane's QR code.
func get_share_url() -> String:
	return "http://%s:%d/share?k=%s" % [_url_host(), port, _key]


# --- Address and QR code -----------------------------------------------------------------------------------------

## The device's LAN address: a private IPv4 address, 192.168 first.
static func lan_address() -> String:
	var best := ""
	var best_rank := 99
	for a in IP.get_local_addresses():
		if not a.is_valid_ip_address() or a.contains(":") or a.begins_with("127.") or a.begins_with("169.254."):
			continue
		var rank := 0 if a.begins_with("192.168.") else (1 if a.begins_with("10.") else (2 if is_private(a) else 9))
		if rank < best_rank:
			best = a
			best_rank = rank
	return best if best_rank < 9 else ""


func _url_host() -> String:
	var a := lan_address()
	return a if a != "" else "127.0.0.1"


func _update_address(force: bool) -> void:
	var url := "http://%s:%d/?k=%s" % [_url_host(), port, _key]
	if url == _url and not force:
		return
	_url = url
	_qr_modules = QrCode.encode(_url, "M")
	address_changed.emit(_url, get_qr_image(8))


## True for loopback, private, link-local and unique-local addresses (IPv4, IPv6, IPv4-mapped IPv6).
static func is_private(address: String) -> bool:
	var a := address.to_lower()
	if a.begins_with("::ffff:"):
		a = a.trim_prefix("::ffff:")
	if a.contains(":"):
		return a == "::1" or a.begins_with("fe8") or a.begins_with("fe9") or a.begins_with("fea") \
				or a.begins_with("feb") or a.begins_with("fc") or a.begins_with("fd")
	var p := a.split(".")
	if p.size() != 4:
		return false
	var o0 := p[0].to_int()
	var o1 := p[1].to_int()
	return o0 == 10 or o0 == 127 or (o0 == 172 and o1 >= 16 and o1 <= 31) or (o0 == 192 and o1 == 168) \
			or (o0 == 169 and o1 == 254)


# --- Connections ---------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_address_timer += delta
	if _address_timer >= ADDRESS_CHECK:
		_address_timer = 0.0
		_update_address(false)
	while _server.is_connection_available():
		var peer := _server.take_connection()
		var host := peer.get_connected_host()
		if not is_private(host) or _conns.size() >= MAX_CONNECTIONS:
			refused += 1
			if refused <= 20 or refused % 100 == 0:
				print("Phone remote: refused a connection from %s (%s)" % [host,
						"not a private address" if not is_private(host) else "too many connections"])
			peer.disconnect_from_host()
			continue
		_conns.append({"peer": peer, "in": PackedByteArray(), "out": PackedByteArray(), "out_pos": 0,
				"since": Time.get_ticks_msec(), "busy": false, "done": false})
	var now := Time.get_ticks_msec()
	for c in _conns.duplicate():
		var peer: StreamPeerTCP = c["peer"]
		peer.poll()
		var st := peer.get_status()
		# A command may take a while (open waits up to 10 s for a share): no timeout while it runs. An upload's
		# thread has its own.
		var timed_out: bool = not c["busy"] and not c.has("upload") and now - int(c["since"]) > CONNECTION_TIMEOUT * 1000.0
		if st != StreamPeerTCP.STATUS_CONNECTED or timed_out:
			_drop(c)
			continue
		if c.has("upload"):
			_check_upload(c)
			continue
		elif not c["busy"] and not c["done"]:
			var avail := peer.get_available_bytes()
			if avail > 0:
				var r: Array = peer.get_partial_data(avail)
				if r[0] == OK:
					# A packed array in a dictionary is read as a copy: append, then store it back.
					var buf: PackedByteArray = c["in"]
					buf.append_array(r[1])
					c["in"] = buf
			_try_request(c)
		_flush(c)


func _drop(c: Dictionary) -> void:
	(c["peer"] as StreamPeerTCP).disconnect_from_host()
	if c.has("upload"):
		# Cut off mid-upload (the server stops): end the thread, no half file left behind.
		var u: Dictionary = c["upload"]
		u["left"] = 0
		(u["thread"] as Thread).wait_to_finish()
		DirAccess.remove_absolute(u["path"])
		c.erase("upload")
	if c.has("file"):
		(c["file"] as FileAccess).close()
		c.erase("file")
	_conns.erase(c)


func _flush(c: Dictionary) -> void:
	var out: PackedByteArray = c["out"]
	var pos: int = c["out_pos"]
	var peer: StreamPeerTCP = c["peer"]
	var sent := 0
	while true:
		while pos < out.size():
			var r: Array = peer.put_partial_data(out.slice(pos, pos + 65536))
			if r[0] != OK or int(r[1]) <= 0:
				break
			pos += int(r[1])
			sent += int(r[1])
		# A file being sent: the next piece once the last one is out (never the whole file in memory).
		if pos < out.size() or not c.has("file") or int(c["file_left"]) <= 0 or sent > 4 * 1024 * 1024:
			break
		var f: FileAccess = c["file"]
		out = f.get_buffer(mini(int(c["file_left"]), 256 * 1024))
		if out.is_empty():
			c["file_left"] = 0
			break
		c["file_left"] = int(c["file_left"]) - out.size()
		pos = 0
	c["out"] = out
	c["out_pos"] = pos
	if sent > 0:
		c["since"] = Time.get_ticks_msec()
	if c.has("file") and int(c["file_left"]) <= 0 and pos >= out.size():
		(c["file"] as FileAccess).close()
		c.erase("file")
	if c["done"] and pos >= out.size() and not c.has("file"):
		_drop(c)


func _try_request(c: Dictionary) -> void:
	var buf: PackedByteArray = c["in"]
	var head_end := _head_end(buf)
	if head_end < 0:
		if buf.size() > 65536:
			_respond(c, 413, "text/plain", "Request too large".to_utf8_buffer())
		return
	var text := buf.slice(0, head_end).get_string_from_ascii()
	var lines := text.substr(0, head_end).split("\r\n")
	var first := lines[0].split(" ")
	if first.size() < 2:
		_respond(c, 400, "text/plain", "Bad request".to_utf8_buffer())
		return
	var headers := {}
	for i in range(1, lines.size()):
		var kv := lines[i].split(":", true, 1)
		if kv.size() == 2:
			headers[kv[0].strip_edges().to_lower()] = kv[1].strip_edges()
	var length := int(headers.get("content-length", "0"))
	if first[0] == "PUT" and first[1].get_slice("?", 0).begins_with("/share/upload/"):
		requests += 1
		_start_upload(c, first[1], headers, length, buf.slice(head_end + 4))
		return
	if length > MAX_REQUEST:
		_respond(c, 413, "text/plain", "Request too large".to_utf8_buffer())
		return
	if buf.size() < head_end + 4 + length:
		return  # The body is still arriving.
	var body := buf.slice(head_end + 4, head_end + 4 + length).get_string_from_utf8()
	requests += 1
	_handle(c, first[0], first[1], headers, body)


## Where "\r\n\r\n" starts in the first 64 KB, or -1.
static func _head_end(buf: PackedByteArray) -> int:
	for i in range(3, mini(buf.size(), 65536)):
		if buf[i] == 10 and buf[i - 1] == 13 and buf[i - 2] == 10 and buf[i - 3] == 13:
			return i - 3
	return -1


func _handle(c: Dictionary, method: String, target: String, headers: Dictionary, body: String) -> void:
	var path := target.get_slice("?", 0)
	var query := target.get_slice("?", 1) if target.contains("?") else ""
	if path == "/share" or path.begins_with("/share/"):
		_handle_share(c, method, path, query, headers)
		return
	if not remote_enabled and path != "/favicon.ico":
		_respond(c, 404, "text/plain", "Not found".to_utf8_buffer())
		return
	if method == "GET" and (path == "/" or path == "/index.html"):
		var page := FileAccess.get_file_as_bytes(PAGE)
		if page.is_empty():
			_respond(c, 500, "text/plain", "The page is missing".to_utf8_buffer())
		else:
			_respond(c, 200, "text/html; charset=utf-8", page)
		return
	if path == "/api" and method == "POST":
		var key := str(headers.get("x-remote-key", ""))
		if key == "":
			key = _query_value(query, "k")
		if key != _key:
			_respond_json(c, 403, {"ok": false, "error": "wrong or missing pairing code: scan the QR code again"})
			return
		var json := JSON.new()
		if json.parse(body) != OK or not (json.data is Dictionary):
			_respond_json(c, 400, {"ok": false, "error": "the body must be a JSON object {cmd, args}"})
			return
		c["busy"] = true
		_run(c, json.data)
		return
	if method == "GET" and path == "/favicon.ico":
		_respond(c, 204, "text/plain", PackedByteArray())
		return
	_respond(c, 404, "text/plain", "Not found".to_utf8_buffer())


func _run(c: Dictionary, msg: Dictionary) -> void:
	var args: Variant = msg.get("args", {})
	if not (args is Dictionary):
		_respond_json(c, 400, {"ok": false, "error": "args must be an object"})
		return
	var r: Dictionary = await DevCommands.execute(str(msg.get("cmd", "")), args, true, self)
	if not is_instance_valid(self) or not _conns.has(c):
		return
	c["busy"] = false
	c["since"] = Time.get_ticks_msec()
	var out := {"ok": r["ok"]}
	if r["ok"]:
		out["result"] = r["result"]
	else:
		out["error"] = r["error"]
	_respond_json(c, 200, out)


## The command registry's gate: the phone may read and use control-level commands only.
func check(ctx: DevCommands.Call, spec: Dictionary) -> String:
	var level := str(spec.get("level", "read"))
	if ctx.name == "set":
		var setting := str(ctx.args.get("setting", ""))
		level = str(DevCommands.setting_spec(setting).get("level", "change")) if DevCommands.has_setting(setting) \
				else "change"
	if level in ALLOWED_LEVELS:
		return ""
	return "%s is not available from the phone remote" % ctx.name


static func _query_value(query: String, name: String) -> String:
	for part in query.split("&"):
		var kv := part.split("=", true, 1)
		if kv[0] == name:
			return Uri.decode(kv[1]) if kv.size() > 1 else ""
	return ""


# --- Share (the headset as a media server; share_routes.gd) -------------------------------------------------------

func _key_ok(query: String, headers: Dictionary) -> bool:
	var key := str(headers.get("x-remote-key", ""))
	if key == "":
		key = _query_value(query, "k")
	return key == _key


func _handle_share(c: Dictionary, method: String, path: String, query: String, headers: Dictionary) -> void:
	if not share_enabled:
		_respond(c, 404, "text/plain", "Sharing is off".to_utf8_buffer())
		return
	if not _key_ok(query, headers):
		_respond(c, 403, "text/plain", "Wrong or missing pairing code".to_utf8_buffer())
		return
	var all := ShareRoutes.roots(settings)
	if method == "GET" and path == "/share":
		var root := int(_query_value(query, "root")) if _query_value(query, "root") != "" else -1
		_respond(c, 200, "text/html; charset=utf-8", ShareRoutes.page(settings, _key, root,
				_query_value(query, "path")).to_utf8_buffer())
	elif method == "GET" and path == "/share/list":
		var i := int(_query_value(query, "root")) if _query_value(query, "root") != "" else -1
		if i < 0 or i >= all.size():
			var names: Array = []
			for r: Dictionary in all:
				names.append({"name": r["name"], "writable": r["writable"]})
			_respond_json(c, 200, {"roots": names})
			return
		var listing := ShareRoutes.list(all[i], _query_value(query, "path"))
		_respond_json(c, 404 if listing.has("error") else 200, listing)
	elif (method == "GET" or method == "HEAD") and path.begins_with("/share/file/"):
		var rest := path.trim_prefix("/share/file/")
		var i := int(rest.get_slice("/", 0))
		var rel := rest.substr(rest.find("/") + 1) if rest.contains("/") else ""
		var full := ShareRoutes.resolve(all[i], rel) if i >= 0 and i < all.size() else ""
		if full == "" or not FileAccess.file_exists(full):
			_respond(c, 404, "text/plain", "No such file".to_utf8_buffer())
			return
		_respond_file(c, full, str(headers.get("range", "")), method == "HEAD")
	elif method == "GET" and path == "/share/screenshot.png":
		var w := _query_value(query, "width")
		_respond_screenshot(c, int(w) if w != "" else 960)
	else:
		_respond(c, 404, "text/plain", "Not found".to_utf8_buffer())


func _respond_file(c: Dictionary, full: String, range_header: String, head_only: bool) -> void:
	var f := FileAccess.open(full, FileAccess.READ)
	if f == null:
		_respond(c, 404, "text/plain", "Can't read the file".to_utf8_buffer())
		return
	var size := f.get_length()
	var r := ShareRoutes.parse_range(range_header, size)
	if r.is_empty() and size > 0:
		var bad := "HTTP/1.1 416 Range Not Satisfiable\r\nContent-Range: bytes */%d\r\nContent-Length: 0\r\n" % size \
				+ "Connection: close\r\n\r\n"
		f.close()
		c["out"] = bad.to_utf8_buffer()
		c["done"] = true
		return
	var start: int = r[0] if size > 0 else 0
	var end: int = r[1] if size > 0 else -1
	var partial := range_header != ""
	var head := "HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nAccept-Ranges: bytes\r\n" \
			% ["206 Partial Content" if partial else "200 OK", ShareRoutes.mime_of(full), end - start + 1]
	if partial:
		head += "Content-Range: bytes %d-%d/%d\r\n" % [start, end, size]
	head += "Content-Disposition: inline; filename=\"%s\"\r\nConnection: close\r\n\r\n" % full.get_file().replace("\"", "")
	var out: PackedByteArray = c["out"]
	out.append_array(head.to_utf8_buffer())
	c["out"] = out
	c["done"] = true
	downloads += 1
	if head_only or end < start:
		f.close()
		return
	f.seek(start)
	c["file"] = f
	c["file_left"] = end - start + 1


func _respond_screenshot(c: Dictionary, width: int) -> void:
	var tree := get_tree()
	var m: Node = tree.current_scene if tree != null else null
	if m == null or not m.has_method("capture_eyes"):
		_respond(c, 500, "text/plain", "No view to capture".to_utf8_buffer())
		return
	c["busy"] = true
	var img: Image = await m.capture_eyes(clampi(width, 160, 2048))
	if not is_instance_valid(self) or not _conns.has(c):
		return
	c["busy"] = false
	if img == null:
		_respond(c, 500, "text/plain", "The capture failed".to_utf8_buffer())
		return
	var png := img.save_png_to_buffer()
	DirAccess.make_dir_recursive_absolute(ShareRoutes.SCREENSHOTS)
	var name := "shot_%s.png" % Time.get_datetime_string_from_system(false, true).replace(":", "").replace(" ", "_")
	var f := FileAccess.open(ShareRoutes.SCREENSHOTS.path_join(name), FileAccess.WRITE)
	if f != null:
		f.store_buffer(png)
		f.close()
	_respond(c, 200, "image/png", png)


func _start_upload(c: Dictionary, target: String, headers: Dictionary, length: int, first: PackedByteArray) -> void:
	var query := target.get_slice("?", 1) if target.contains("?") else ""
	if not share_enabled:
		_respond(c, 404, "text/plain", "Sharing is off".to_utf8_buffer())
		return
	if not _key_ok(query, headers):
		_respond(c, 403, "text/plain", "Wrong or missing pairing code".to_utf8_buffer())
		return
	if not headers.has("content-length") or length < 0 or length > ShareRoutes.MAX_UPLOAD:
		_respond(c, 411 if not headers.has("content-length") else 413, "text/plain",
				"Give a Content-Length up to 64 GB".to_utf8_buffer())
		return
	var folder := ShareRoutes.drop_folder(settings)
	DirAccess.make_dir_recursive_absolute(folder)
	var d := DirAccess.open(folder)
	if d != null and d.get_space_left() > 0 and d.get_space_left() < length + 256 * 1024 * 1024:
		_respond(c, 507, "text/plain", "Not enough space on the headset".to_utf8_buffer())
		return
	var path := ShareRoutes.free_name(folder, target.get_slice("?", 0).trim_prefix("/share/upload/"))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_respond(c, 500, "text/plain", "Can't write in the Drop folder".to_utf8_buffer())
		return
	var u := {"file": f, "path": path, "left": length, "size": length, "peer": c["peer"], "ok": false}
	c["upload"] = u
	c["in"] = PackedByteArray()
	var take := first.slice(0, mini(first.size(), length))
	f.store_buffer(take)
	u["left"] = length - take.size()
	# The rest on a thread: reading a socket once a frame would cap it at a few MB/s.
	var t := Thread.new()
	u["thread"] = t
	t.start(_upload_thread.bind(u))


## The upload's thread: only it touches the connection's socket and file until it ends.
static func _upload_thread(u: Dictionary) -> void:
	var peer: StreamPeerTCP = u["peer"]
	var f: FileAccess = u["file"]
	var idle_since := Time.get_ticks_msec()
	while int(u["left"]) > 0:
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			break
		var avail := peer.get_available_bytes()
		if avail <= 0:
			if Time.get_ticks_msec() - idle_since > int(CONNECTION_TIMEOUT * 1000.0):
				break
			OS.delay_msec(1)
			continue
		var r: Array = peer.get_partial_data(mini(avail, mini(int(u["left"]), 1024 * 1024)))
		if r[0] != OK:
			break
		f.store_buffer(r[1])
		u["left"] = int(u["left"]) - (r[1] as PackedByteArray).size()
		idle_since = Time.get_ticks_msec()
	f.close()
	u["ok"] = int(u["left"]) <= 0


## Main thread: once the upload's thread is done, answer (or drop the half file).
func _check_upload(c: Dictionary) -> void:
	var u: Dictionary = c["upload"]
	var t: Thread = u["thread"]
	if t.is_alive():
		return
	t.wait_to_finish()
	c.erase("upload")
	if not u["ok"]:
		DirAccess.remove_absolute(u["path"])
		print("Phone remote server: an upload of %s was cut off; removed" % str(u["path"]).get_file())
		_drop(c)
		return
	uploads += 1
	c["since"] = Time.get_ticks_msec()
	print("Phone remote server: received %s (%s)" % [str(u["path"]).get_file(), String.humanize_size(int(u["size"]))])
	_respond_json(c, 201, {"saved": str(u["path"]).get_file(), "bytes": u["size"]})
	_flush(c)


func _respond_json(c: Dictionary, status: int, obj: Dictionary) -> void:
	_respond(c, status, "application/json", JSON.stringify(obj).to_utf8_buffer())


func _respond(c: Dictionary, status: int, content_type: String, body: PackedByteArray) -> void:
	var reasons := {200: "OK", 201: "Created", 204: "No Content", 400: "Bad Request", 403: "Forbidden",
			404: "Not Found", 411: "Length Required", 413: "Payload Too Large", 500: "Internal Server Error",
			507: "Insufficient Storage"}
	var head := "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-store\r\n" \
			% [status, reasons.get(status, "Error"), content_type, body.size()] \
			+ "X-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n"
	var out: PackedByteArray = c["out"]
	out.append_array(head.to_utf8_buffer())
	out.append_array(body)
	c["out"] = out
	c["done"] = true
