extends RefCounted

## One paired PC while it is connected (docs/pc-windows.md, "Control connection"): its control connection (JSON lines
## both ways, polled by the service on the main thread), its window list, its clock, and its stream connections
## (pc_stream.gd, each on a thread of its own). The service (pc_service.gd) makes it once the PC's hello is accepted;
## the panes (pc_windows.gd) ask it for streams and send it the input.
## Window titles and thumbnails stay in here and in the panel: never logged.

const PcProtocol := preload("res://scripts/pc/pc_protocol.gd")
const PcClock := preload("res://scripts/pc/pc_clock.gd")
const PcStream := preload("res://scripts/pc/pc_stream.gd")

const PING_SECONDS := 5.0
const PONG_TIMEOUT := 15.0
const WRITE_CHUNK := 16384
const MAX_WINDOWS := 256

signal windows_changed
## A window's stream: the PC said what it sends (`stream`), or it ended.
signal stream_changed(number: int)
signal window_closed(id: String)
signal cursor_changed(id: String, shape: String)
signal problem(what: String, id: String)

var client_id := ""
var pc_name := ""
var address := ""
var clock := PcClock.new()
## [{id, kind, title, app, w, h, thumb (Texture2D or null)}]
var windows: Array[Dictionary] = []
## Stream number -> {id, max, fps, kbps, info: {codec, bits, w, h}, reader: PcStream or null}
var streams := {}
## Window id -> the shape of the cursor over it.
var cursors := {}
var sound_on := false
var last_error := ""
var closed := false
var _tcp: StreamPeerTCP
var _tls: StreamPeer
var _in := PackedByteArray()
var _out := PackedByteArray()
var _out_pos := 0
var _wlen := 0
var _next_stream := 1
var _ping_n := 0
var _ping_at := 0.0
var _pong_at := 0.0
## Messages sent, by type (the tests read them).
var sent := {}


func setup(tcp: StreamPeerTCP, tls: StreamPeer, rest: PackedByteArray) -> void:
	_tcp = tcp
	_tls = tls
	_in = rest
	_ping_at = _now() + PING_SECONDS
	_pong_at = _now()


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## One message to the PC.
func send(obj: Dictionary) -> void:
	if closed:
		return
	var t := str(obj.get("t", ""))
	sent[t] = int(sent.get(t, 0)) + 1
	_out.append_array(PcProtocol.line(obj))


## Polled by the service every frame. False once the connection is gone.
func poll() -> bool:
	if closed:
		return false
	_tcp.poll()
	if _tls != _tcp:
		_tls.poll()
	if _tls.get_status() != StreamPeerTLS.STATUS_CONNECTED:
		close("the PC went")
		return false
	while true:
		var r: Array = _tls.get_partial_data(65536)
		if r[0] != OK:
			close("the PC went")
			return false
		var d: PackedByteArray = r[1]
		if d.is_empty():
			break
		_in.append_array(d)
	if not _in.is_empty():
		var t := PcProtocol.take_lines(_in)
		for m: Dictionary in t["lines"]:
			_handle(m)
		if int(t["used"]) > 0:
			_in = _in.slice(int(t["used"]))
		if str(t["error"]) != "":
			close(str(t["error"]))
			return false
	var now := _now()
	if now >= _ping_at:
		_ping_at = now + PING_SECONDS
		_ping_n += 1
		send({"t": "ping", "n": _ping_n})
	if now - _pong_at > PONG_TIMEOUT:
		close("no answer from the PC in %d s" % int(PONG_TIMEOUT))
		return false
	_flush()
	for n: int in streams.keys():
		var reader: PcStream = streams[n].get("reader")
		if reader != null and reader.ended() and not bool(streams[n].get("ended", false)):
			streams[n]["ended"] = true
			stream_changed.emit(n)
	return not closed


func _flush() -> void:
	var sent_bytes := 0
	while _out_pos < _out.size() and sent_bytes < (1 << 20):
		# After a write that could not go out, TLS wants the very same bytes again.
		var n := _wlen if _wlen > 0 else mini(WRITE_CHUNK, _out.size() - _out_pos)
		var r: Array = _tls.put_partial_data(_out.slice(_out_pos, _out_pos + n))
		if r[0] != OK:
			close("the PC went")
			return
		if int(r[1]) <= 0:
			_wlen = n
			return
		_wlen = 0
		_out_pos += int(r[1])
		sent_bytes += int(r[1])
	if _out_pos >= _out.size():
		_out = PackedByteArray()
		_out_pos = 0


func close(why := "") -> void:
	if closed:
		return
	closed = true
	if why != "":
		last_error = why
	for n: int in streams:
		var reader: PcStream = streams[n].get("reader")
		if reader != null:
			reader.stop()
	if _tls is StreamPeerTLS and _tls.get_status() == StreamPeerTLS.STATUS_CONNECTED:
		(_tls as StreamPeerTLS).disconnect_from_stream()
	if _tcp != null:
		_tcp.disconnect_from_host()


func _handle(m: Dictionary) -> void:
	match str(m.get("t", "")):
		"windows":
			_take_windows(m.get("list", []))
		"stream":
			var n := int(m.get("stream", -1))
			if streams.has(n):
				streams[n]["info"] = {"codec": str(m.get("codec", "")), "bits": int(m.get("bits", 8)),
						"w": int(m.get("w", 0)), "h": int(m.get("h", 0))}
				stream_changed.emit(n)
		"resized":
			var id := str(m.get("id", ""))
			for w: Dictionary in windows:
				if w["id"] == id:
					w["w"] = int(m.get("w", w["w"]))
					w["h"] = int(m.get("h", w["h"]))
			windows_changed.emit()
		"closed":
			var id := str(m.get("id", ""))
			var kept: Array[Dictionary] = []
			kept.assign(windows.filter(func(w: Dictionary) -> bool: return w["id"] != id))
			windows = kept
			window_closed.emit(id)
			windows_changed.emit()
		"cursor":
			var shape := str(m.get("shape", "arrow"))
			if not shape in PcProtocol.CURSOR_SHAPES:
				shape = "other"
			cursors[str(m.get("id", ""))] = shape
			cursor_changed.emit(str(m.get("id", "")), shape)
		"pong":
			_pong_at = _now()
		"error":
			last_error = str(m.get("what", ""))
			problem.emit(last_error, str(m.get("id", "")))


## The PC's list, checked: ids as the protocol has them, sizes as numbers, thumbnails decoded (JPEG, at most 256 px).
func _take_windows(list: Variant) -> void:
	if not list is Array:
		return
	var out: Array[Dictionary] = []
	var old := {}
	for w: Dictionary in windows:
		old[w["id"]] = w
	for e: Variant in list:
		if not e is Dictionary or out.size() >= MAX_WINDOWS:
			continue
		var d: Dictionary = e
		var id := str(d.get("id", ""))
		if not PcProtocol.is_window_id(id):
			continue
		var w := {"id": id, "kind": "monitor" if str(d.get("kind", "")) == "monitor" else "window",
				"title": str(d.get("title", "")).left(200), "app": str(d.get("app", "")).left(80),
				"w": clampi(int(d.get("w", 0)), 0, 16384), "h": clampi(int(d.get("h", 0)), 0, 16384), "thumb": null}
		var b64 := str(d.get("thumb", ""))
		if b64 != "" and old.has(id) and str(old[id].get("thumb_b64_hash", "")) == str(b64.hash()):
			w["thumb"] = old[id]["thumb"]
		elif b64 != "" and b64.length() < 1 << 20:
			var img := Image.new()
			if img.load_jpg_from_buffer(Marshalls.base64_to_raw(b64)) == OK and img.get_width() <= 512 \
					and img.get_height() <= 512:
				w["thumb"] = ImageTexture.create_from_image(img)
		w["thumb_b64_hash"] = str(b64.hash()) if b64 != "" else ""
		out.append(w)
	windows = out
	windows_changed.emit()


func window(id: String) -> Dictionary:
	for w: Dictionary in windows:
		if w["id"] == id:
			return w
	return {}


## Asks for a window's stream: its number (1 up).
func open_stream(id: String, max_size: Vector2i, fps: int, kbps: int) -> int:
	var n := _next_stream
	_next_stream += 1
	streams[n] = {"id": id, "max": [max_size.x, max_size.y], "fps": fps, "kbps": kbps, "info": {}, "reader": null}
	send({"t": "open", "id": id, "stream": n, "max": [max_size.x, max_size.y], "fps": fps, "kbps": kbps})
	return n


func close_stream(n: int) -> void:
	if not streams.has(n):
		return
	var reader: PcStream = streams[n].get("reader")
	if reader != null:
		reader.stop()
	streams.erase(n)
	if n != 0:
		send({"t": "close", "stream": n})


func set_quality(n: int, fps: int, kbps: int) -> void:
	if not streams.has(n):
		return
	if int(streams[n]["fps"]) == fps and int(streams[n]["kbps"]) == kbps:
		return
	streams[n]["fps"] = fps
	streams[n]["kbps"] = kbps
	send({"t": "quality", "stream": n, "fps": fps, "kbps": kbps})


func set_sound(on: bool) -> void:
	if on == sound_on:
		return
	sound_on = on
	if on:
		streams[0] = {"id": "", "info": {}, "reader": null}
	else:
		close_stream(0)
	send({"t": "sound", "on": on})


## The service hands a stream connection over once its first line named a stream this PC was asked for.
func expects(n: int) -> bool:
	return streams.has(n) and streams[n].get("reader") == null


func attach_stream(n: int, reader: PcStream) -> void:
	streams[n]["reader"] = reader
	stream_changed.emit(n)


func reader(n: int) -> PcStream:
	return streams[n].get("reader") if streams.has(n) else null


func status() -> Dictionary:
	return {"name": pc_name, "windows": windows.size(), "streams": streams.size(), "sound": sound_on,
			"clock": clock.known(), "error": last_error}
