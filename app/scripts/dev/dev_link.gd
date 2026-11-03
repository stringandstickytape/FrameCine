extends Node

## The headset's connection to the listener on the PC (docs/dev/control-protocol.md). The headset connects OUT to
## [dev] listener_host:listener_port; nothing listens on the headset. Newline-delimited JSON both ways: events and
## replies go to the PC, commands come back on the same socket.
##
## Never blocks the frame: the host name is resolved on the engine's resolver thread, the socket is non-blocking,
## writes go through an outgoing buffer drained with put_partial_data(), and reads take only what has arrived. A lost
## or refused connection is retried with backoff (1, 2, 4, 8, 15, 30 s). While there is no connection, the last
## BACKLOG_MAX messages are kept and sent first after the hello.

signal connected
signal disconnected
## One parsed command line from the PC.
signal message_received(msg: Dictionary)

const PROTOCOL := 1
const DEFAULT_PORT := 47800
const BACKOFF: Array[float] = [1.0, 2.0, 4.0, 8.0, 15.0, 30.0]
const CONNECT_TIMEOUT := 5.0
## No write progress for this long with data waiting: the PC is gone without closing (Wi-Fi). Reconnect.
const STALL_TIMEOUT := 10.0
## A heartbeat event this often, so both ends notice a dead connection.
const HEARTBEAT := 15.0
## Bytes per put_partial_data() call and per frame.
const WRITE_CHUNK := 65536
const WRITE_BUDGET := 1 << 20
const READ_BUDGET := 1 << 20
## Outgoing bytes waiting beyond this: drop new events (not replies) and count them.
const OUT_LIMIT := 64 << 20
const BACKLOG_MAX := 200
## A command line longer than this is dropped (a glTF sent inline is the biggest thing expected).
const MAX_LINE := 64 << 20

enum State { IDLE, RESOLVING, CONNECTING, CONNECTED }

var host := ""
var port := DEFAULT_PORT
## Extra fields for the hello (app, device, settings), set by dev_host.gd.
var hello := {}
var state := State.IDLE
## Events not sent because the outgoing buffer was full, or dropped from the backlog.
var dropped := 0
var session_id := ""

var _peer: StreamPeerTCP
var _resolve_id := -1
var _address := ""
var _attempt := 0
var _retry_at := 0.0
var _state_since := 0.0
var _out := PackedByteArray()
var _out_pos := 0
var _last_progress := 0.0
var _in := PackedByteArray()
var _backlog: Array[PackedByteArray] = []
var _heartbeat_at := 0.0
var _seq := 0


func _ready() -> void:
	session_id = "%08x" % (randi() & 0x7fffffff)
	print("Dev link: will connect to the listener at %s:%d" % [host, port])


func _exit_tree() -> void:
	_close()
	if _resolve_id >= 0:
		IP.erase_resolve_item(_resolve_id)
		_resolve_id = -1


func is_link_connected() -> bool:
	return state == State.CONNECTED


func status() -> Dictionary:
	return {"host": host, "port": port, "state": State.keys()[state].to_lower(), "dropped": dropped,
			"queued_bytes": _out.size() - _out_pos, "attempt": _attempt}


## Sends an event: {"type": "event", "event": name, "t": unix time, "seq": n, "data": data}.
func send_event(event_name: String, data: Variant = {}) -> void:
	_seq += 1
	_send({"type": "event", "event": event_name, "t": Time.get_unix_time_from_system(), "seq": _seq, "data": data},
			false)


## Sends a reply to command `id`.
func send_reply(id: Variant, ok: bool, result: Variant, error := "") -> void:
	var msg := {"type": "reply", "id": id, "ok": ok}
	if ok:
		msg["result"] = result
	else:
		msg["error"] = error
	_send(msg, true)


func _send(msg: Dictionary, is_reply: bool) -> void:
	var line := (JSON.stringify(msg) + "\n").to_utf8_buffer()
	if state != State.CONNECTED:
		if is_reply:
			return  # The command came on a connection that is gone; nobody waits for this.
		_backlog.append(line)
		if _backlog.size() > BACKLOG_MAX:
			_backlog.pop_front()
			dropped += 1
		return
	if not is_reply and _out.size() - _out_pos + line.size() > OUT_LIMIT:
		dropped += 1
		return
	_out.append_array(line)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	match state:
		State.IDLE:
			if now >= _retry_at and host != "":
				_start(now)
		State.RESOLVING:
			_poll_resolve(now)
		State.CONNECTING:
			_peer.poll()
			var st := _peer.get_status()
			if st == StreamPeerTCP.STATUS_CONNECTED:
				_on_connected(now)
			elif st == StreamPeerTCP.STATUS_ERROR or st == StreamPeerTCP.STATUS_NONE \
					or now - _state_since > CONNECT_TIMEOUT:
				_fail(now, "no answer" if st == StreamPeerTCP.STATUS_CONNECTING else "refused")
		State.CONNECTED:
			_peer.poll()
			if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				_fail(now, "closed by the PC")
				return
			_write(now)
			if state == State.CONNECTED:
				_read(now)
			if state == State.CONNECTED and now >= _heartbeat_at:
				_heartbeat_at = now + HEARTBEAT
				send_event("heartbeat", {"uptime": snappedf(now, 0.1), "dropped": dropped})


func _start(now: float) -> void:
	_state_since = now
	if host.is_valid_ip_address():
		_connect_to(host, now)
		return
	_resolve_id = IP.resolve_hostname_queue_item(host, IP.TYPE_IPV4)
	state = State.RESOLVING


func _poll_resolve(now: float) -> void:
	var st := IP.get_resolve_item_status(_resolve_id)
	if st == IP.RESOLVER_STATUS_WAITING:
		if now - _state_since > CONNECT_TIMEOUT:
			IP.erase_resolve_item(_resolve_id)
			_resolve_id = -1
			_fail(now, "name lookup timed out")
		return
	var address := IP.get_resolve_item_address(_resolve_id) if st == IP.RESOLVER_STATUS_DONE else ""
	IP.erase_resolve_item(_resolve_id)
	_resolve_id = -1
	if address == "":
		_fail(now, "can't resolve %s" % host)
		return
	_connect_to(address, now)


func _connect_to(address: String, now: float) -> void:
	_address = address
	_peer = StreamPeerTCP.new()
	var err := _peer.connect_to_host(address, port)
	if err != OK:
		_fail(now, error_string(err))
		return
	state = State.CONNECTING
	_state_since = now


func _on_connected(now: float) -> void:
	_peer.set_no_delay(true)
	state = State.CONNECTED
	_state_since = now
	_last_progress = now
	_heartbeat_at = now + HEARTBEAT
	print("Dev link: connected to %s:%d" % [_address, port])
	_attempt = 0
	_out = PackedByteArray()
	_out_pos = 0
	_in = PackedByteArray()
	var msg := hello.duplicate()
	msg["type"] = "hello"
	msg["proto"] = PROTOCOL
	msg["session"] = session_id
	msg["t"] = Time.get_unix_time_from_system()
	msg["backlog"] = _backlog.size()
	msg["dropped"] = dropped
	_out.append_array((JSON.stringify(msg) + "\n").to_utf8_buffer())
	for line in _backlog:
		_out.append_array(line)
	_backlog.clear()
	connected.emit()


func _fail(now: float, why: String) -> void:
	var was_connected := state == State.CONNECTED
	_close()
	state = State.IDLE
	var wait: float = BACKOFF[mini(_attempt, BACKOFF.size() - 1)]
	_attempt += 1
	_retry_at = now + wait
	# Log the first failure and then every 10th, so a PC that is off does not fill the log.
	if was_connected or _attempt == 1 or _attempt % 10 == 0:
		print("Dev link: %s:%d %s; retrying in %.0f s" % [host, port, why, wait])
	if was_connected:
		disconnected.emit()


func _close() -> void:
	if _peer != null:
		_peer.disconnect_from_host()
		_peer = null


func _write(now: float) -> void:
	var pending := _out.size() - _out_pos
	if pending == 0:
		_last_progress = now
		return
	var budget := WRITE_BUDGET
	while _out_pos < _out.size() and budget > 0:
		var n := mini(mini(WRITE_CHUNK, _out.size() - _out_pos), budget)
		var r: Array = _peer.put_partial_data(_out.slice(_out_pos, _out_pos + n))
		if r[0] != OK:
			_fail(now, "write failed: %s" % error_string(r[0]))
			return
		var sent: int = r[1]
		if sent <= 0:
			break
		_out_pos += sent
		budget -= sent
		_last_progress = now
	if _out_pos >= _out.size():
		_out = PackedByteArray()
		_out_pos = 0
	elif _out_pos > (4 << 20):
		_out = _out.slice(_out_pos)
		_out_pos = 0
	if now - _last_progress > STALL_TIMEOUT:
		_fail(now, "stalled (nothing sent for %.0f s)" % STALL_TIMEOUT)


func _read(now: float) -> void:
	var avail := mini(_peer.get_available_bytes(), READ_BUDGET)
	if avail <= 0:
		return
	var r: Array = _peer.get_partial_data(avail)
	if r[0] != OK:
		_fail(now, "read failed: %s" % error_string(r[0]))
		return
	_in.append_array(r[1])
	while true:
		var nl := _in.find(10)
		if nl < 0:
			break
		var line := _in.slice(0, nl).get_string_from_utf8().strip_edges()
		_in = _in.slice(nl + 1)
		if line != "":
			_on_line(line)
	if _in.size() > MAX_LINE:
		_in = PackedByteArray()
		send_reply(null, false, null, "line longer than %d bytes dropped" % MAX_LINE)


func _on_line(line: String) -> void:
	var json := JSON.new()
	if json.parse(line) != OK or not (json.data is Dictionary):
		send_reply(null, false, null, "not a JSON object: %s" % json.get_error_message())
		return
	message_received.emit(json.data)
