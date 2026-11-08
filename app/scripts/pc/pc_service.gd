extends Node

## The headset's side of PC windows (docs/pc-windows.md, decision D31): the PC dials the headset, as an assistant does
## (D16), so the service is here and nothing listens on the PC.
##   UDP 47803  discovery: a PC's {"t":"pcw_find"} gets {"t":"pcw_here", name, port, pin, pairing} back, only while
##              "Add a PC" runs or when the PC's name is a paired PC's, and only to a private address.
##   TCP 47803  TLS with the assistant service's certificate (assistant_tls.gd; the pin is the SHA-256 of its DER, hex):
##              a control connection per PC (its first line a hello with a token, or with the code while pairing),
##              and a stream connection per open window and one for the sound (the first line names the stream and
##              carries the token; then PCW1 packets, read on a thread: pc_stream.gd).
## Off until System, PC windows is on ([pc_windows] enabled). Even then the ports are open only while "Add a PC" runs
## or once a PC is paired. A connection from an address that is not private is closed at once.
## Pairing: "Add a PC" shows a six-digit code for PAIR_SECONDS; the PC sends it in its hello; the headset answers with
## a token (32 random bytes, hex) and keeps only its SHA-256 and the PC's name, in user://pc_clients.cfg (owner read
## and write only; assistant_clients.gd). WRONG_MAX wrong codes close pairing. Tokens and codes are never printed.
## Polled in _process(), like the assistant service: the frame never waits on a socket; the streams' bytes are read
## on their own threads.

signal status_changed
signal pairing_changed
signal sessions_changed
## A PC's window list changed (or a PC came or went).
signal windows_changed

const PcProtocol := preload("res://scripts/pc/pc_protocol.gd")
const PcSession := preload("res://scripts/pc/pc_session.gd")
const PcStream := preload("res://scripts/pc/pc_stream.gd")
const AssistantTls := preload("res://scripts/assistant/assistant_tls.gd")
const AssistantClients := preload("res://scripts/assistant/assistant_clients.gd")
const RemoteServer := preload("res://scripts/remote/remote_server.gd")

const SECTION := "pc_windows"
const CLIENTS_PATH := "user://pc_clients.cfg"
## "Add a PC": how long the code is shown.
const PAIR_SECONDS := 600.0
const WRONG_MAX := 5
const HANDSHAKE_TIMEOUT := 10.0
const FIRST_LINE_TIMEOUT := 10.0
const MAX_PENDING := 16
## Problems the panel shows (status_text()), as keys.
const PROBLEM_TLS := "Can't make the certificate: %s." # i18n
const PROBLEM_PORT := "Can't listen on port %d: %s." # i18n

var settings: RefCounted
var port := PcProtocol.PORT
## "*" on the headset; tests use "127.0.0.1".
var bind_address := "*"
## Tests point these at other files.
var clients_path := CLIENTS_PATH
var tls_key_path := AssistantTls.KEY_PATH
var tls_cert_path := AssistantTls.CERT_PATH
## The headset's name in discovery and the welcome.
var headset_name := "Steam Frame"
var clients: AssistantClients
var tls: AssistantTls
var problem := ""
var _problem_parts: Array = []
## The pin PCs check: the SHA-256 of the certificate's DER, hex.
var pin := ""
var _server: TCPServer
var _udp: PacketPeerUDP
var _tls_options: TLSOptions
var _tls_tried := false
var _retry_at := 0.0
## Connections whose first line hasn't come: [{tcp, tls, address, in, since}]
var _pending: Array[Dictionary] = []
## client id -> PcSession
var _sessions := {}
var _pair_code := ""
var _pair_until := 0.0
var _wrong := 0
## Counters (tests, status): refused connections, discovery replies, wrong codes in all.
var refused := 0
var replies := 0
var wrong_codes := 0


func _ready() -> void:
	if settings != null:
		port = int(settings.get_value(SECTION, "port", port))
	clients = AssistantClients.new()
	clients.path = clients_path
	clients.load_file()
	tls = AssistantTls.new()
	tls.key_path = tls_key_path
	tls.cert_path = tls_cert_path
	print("PC windows: on (%d paired)" % clients.clients.size())


func _exit_tree() -> void:
	_stop()
	tls.wait()


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# --- Pairing -------------------------------------------------------------------------------------------------------

## "Add a PC": a new code for PAIR_SECONDS.
func start_pairing() -> void:
	var digits := ""
	for b in Crypto.new().generate_random_bytes(6):
		digits += str(b % 10)
	_pair_code = digits
	_pair_until = _now() + PAIR_SECONDS
	_wrong = 0
	print("PC windows: a PC may pair for %d min" % int(PAIR_SECONDS / 60.0))
	_update_listen()
	pairing_changed.emit()
	status_changed.emit()


func cancel_pairing() -> void:
	if _pair_code == "":
		return
	_pair_code = ""
	_pair_until = 0.0
	print("PC windows: pairing closed")
	pairing_changed.emit()
	status_changed.emit()


func pairing() -> bool:
	return _pair_code != "" and _now() < _pair_until


## The code to show, "" when not pairing. Only the panel shows it.
func pairing_code() -> String:
	return _pair_code if pairing() else ""


func pairing_left() -> float:
	return maxf(_pair_until - _now(), 0.0) if pairing() else 0.0


## The paired PCs, without their hashes: [{id, name, paired_at, last_seen, connected}].
func paired() -> Array:
	var out: Array = []
	for c: Dictionary in clients.public_list():
		c["connected"] = _sessions.has(c["id"])
		out.append(c)
	return out


func forget(id: String) -> void:
	if clients.by_id(id).is_empty():
		return
	clients.forget(id)
	if _sessions.has(id):
		(_sessions[id] as PcSession).close("forgotten")
		_sessions.erase(id)
		sessions_changed.emit()
		windows_changed.emit()
	print("PC windows: forgot a PC")
	_update_listen()
	status_changed.emit()


# --- State ---------------------------------------------------------------------------------------------------------

func is_listening() -> bool:
	return _server != null and _server.is_listening()


func sessions() -> Array:
	return _sessions.values()


func session(client_id: String) -> PcSession:
	return _sessions.get(client_id)


## One line for the panel, in the menus' language.
func status_text() -> String:
	if problem != "":
		return tr(str(_problem_parts[0])) % _problem_parts[1] if _problem_parts.size() == 2 else problem
	if pairing():
		return tr("On the PC, run the PC windows app and type this code (%d min left).") % ceili(pairing_left() / 60.0)
	if clients.is_empty():
		return tr("No PC yet. Press Add a PC, then run the PC windows app on the PC.")
	var n := _sessions.size()
	if n == 0:
		return tr("Waiting for a paired PC on this network.")
	return tr_n("%d PC connected.", "%d PCs connected.", n) % n


func _set_problem(format: String, values: Array) -> void:
	problem = format % values
	_problem_parts = [format, values]


# --- Listening -----------------------------------------------------------------------------------------------------

func _update_listen() -> void:
	var want := pairing() or not clients.is_empty()
	if not want:
		if is_listening():
			_stop()
			print("PC windows: not listening (not pairing, nobody paired)")
			status_changed.emit()
		return
	if is_listening() or _now() < _retry_at:
		return
	if not tls.ready():
		if tls.making():
			return
		if not tls.load_files():
			if tls.error == "" and not _tls_tried:
				_tls_tried = true
				print("PC windows: making the certificate (once)")
				tls.start_making()
			else:
				_set_problem(PROBLEM_TLS, [tls.error if tls.error != "" else "unknown"])
				_retry_at = _now() + 30.0
				_tls_tried = false
				status_changed.emit()
			return
	pin = tls.cert_sha256
	_tls_options = TLSOptions.server(tls.key, tls.cert)
	_server = TCPServer.new()
	var err := _server.listen(port, bind_address)
	if err != OK:
		_server = null
		_set_problem(PROBLEM_PORT, [port, error_string(err)])
		_retry_at = _now() + 5.0
		push_warning("PC windows: " + problem)
		status_changed.emit()
		return
	_udp = PacketPeerUDP.new()
	if _udp.bind(port, bind_address) != OK:
		push_warning("PC windows: can't listen for discovery on UDP %d" % port)
		_udp = null
	problem = ""
	print("PC windows: listening on port %d" % port)
	status_changed.emit()


func _stop() -> void:
	for p in _pending:
		_drop_pending(p)
	_pending.clear()
	for s: PcSession in _sessions.values():
		s.close("the service stopped")
	if not _sessions.is_empty():
		_sessions.clear()
		sessions_changed.emit()
		windows_changed.emit()
	if _server != null:
		_server.stop()
		_server = null
	if _udp != null:
		_udp.close()
		_udp = null


func _process(_delta: float) -> void:
	if _pair_code != "" and _now() >= _pair_until:
		cancel_pairing()
	_update_listen()
	if not is_listening():
		return
	_discovery()
	_accept()
	for p in _pending.duplicate():
		_poll_pending(p)
	for id: String in _sessions.keys():
		var s: PcSession = _sessions[id]
		if not s.poll():
			_sessions.erase(id)
			print("PC windows: a PC disconnected (%s)" % s.last_error)
			sessions_changed.emit()
			windows_changed.emit()
			status_changed.emit()


func _discovery() -> void:
	if _udp == null:
		return
	var n := 0
	while _udp.get_available_packet_count() > 0 and n < 32:
		n += 1
		var data := _udp.get_packet()
		var host := _udp.get_packet_ip()
		var from_port := _udp.get_packet_port()
		if not RemoteServer.is_private(host) or data.size() > 4096:
			continue
		var v: Variant = JSON.parse_string(data.get_string_from_utf8())
		if not v is Dictionary or str(v.get("t", "")) != "pcw_find":
			continue
		var asker := str(v.get("pc", ""))
		var known := clients.clients.any(func(c: Dictionary) -> bool: return c["name"] == asker and asker != "")
		if not pairing() and not known:
			continue
		var reply := {"t": "pcw_here", "v": PcProtocol.VERSION, "name": headset_name, "port": port, "pin": pin,
				"pairing": pairing()}
		_udp.set_dest_address(host, from_port)
		_udp.put_packet(JSON.stringify(reply).to_utf8_buffer())
		replies += 1


func _accept() -> void:
	while _server.is_connection_available():
		var tcp := _server.take_connection()
		var host := tcp.get_connected_host()
		if not RemoteServer.is_private(host) or _pending.size() >= MAX_PENDING:
			refused += 1
			if refused <= 20 or refused % 100 == 0:
				print("PC windows: refused a connection (%s)" % ("not a private address"
						if not RemoteServer.is_private(host) else "too many at once"))
			tcp.disconnect_from_host()
			continue
		tcp.set_no_delay(true)
		var t := StreamPeerTLS.new()
		if t.accept_stream(tcp, _tls_options) != OK:
			tcp.disconnect_from_host()
			continue
		_pending.append({"tcp": tcp, "tls": t, "address": host, "in": PackedByteArray(), "since": _now()})


func _drop_pending(p: Dictionary) -> void:
	var t: StreamPeerTLS = p["tls"]
	if t.get_status() == StreamPeerTLS.STATUS_CONNECTED:
		t.disconnect_from_stream()
	(p["tcp"] as StreamPeerTCP).disconnect_from_host()
	_pending.erase(p)


## A connection before its first line: the TLS handshake, then the hello or the stream line.
func _poll_pending(p: Dictionary) -> void:
	var tcp: StreamPeerTCP = p["tcp"]
	var t: StreamPeerTLS = p["tls"]
	tcp.poll()
	if t.get_status() == StreamPeerTLS.STATUS_HANDSHAKING or t.get_status() == StreamPeerTLS.STATUS_CONNECTED:
		t.poll()
	var st := t.get_status()
	if st == StreamPeerTLS.STATUS_HANDSHAKING:
		if _now() - float(p["since"]) > HANDSHAKE_TIMEOUT:
			_drop_pending(p)
		return
	if st != StreamPeerTLS.STATUS_CONNECTED:
		_drop_pending(p)
		return
	var buf: PackedByteArray = p["in"]
	while buf.size() < PcProtocol.MAX_LINE:
		var r: Array = t.get_partial_data(16384)
		if r[0] != OK:
			_drop_pending(p)
			return
		var d: PackedByteArray = r[1]
		if d.is_empty():
			break
		buf.append_array(d)
	p["in"] = buf
	var nl := buf.find(10)
	if nl < 0:
		if _now() - float(p["since"]) > FIRST_LINE_TIMEOUT or buf.size() >= PcProtocol.MAX_LINE:
			_drop_pending(p)
		return
	_pending.erase(p)
	var v: Variant = JSON.parse_string(buf.slice(0, nl).get_string_from_utf8())
	var rest := buf.slice(nl + 1)
	var first: Dictionary = v if v is Dictionary else {}
	match str(first.get("t", "")):
		"hello":
			_hello(p, first, rest)
		"stream":
			_stream(p, first, rest)
		_:
			_refuse(p, "the first line is a hello or a stream")


func _refuse(p: Dictionary, why: String) -> void:
	var t: StreamPeerTLS = p["tls"]
	t.put_data(PcProtocol.line({"t": "refused", "why": why}))
	t.poll()
	t.disconnect_from_stream()
	(p["tcp"] as StreamPeerTCP).disconnect_from_host()


func _hello(p: Dictionary, m: Dictionary, rest: PackedByteArray) -> void:
	var pc := str(m.get("pc", "")).strip_edges().left(64)
	if pc == "":
		pc = "PC"
	var token := str(m.get("token", ""))
	var code := str(m.get("code", ""))
	var client := {}
	var new_token := ""
	if token != "":
		client = clients.find(token)
		if client.is_empty():
			_refuse(p, "unknown token: pair again")
			return
	elif code != "":
		if not pairing():
			_refuse(p, "pairing is closed: press Add a PC in the headset")
			return
		var crypto := Crypto.new()
		if code.length() != 6 or not crypto.constant_time_compare(code.to_ascii_buffer(), _pair_code.to_ascii_buffer()):
			_wrong += 1
			wrong_codes += 1
			print("PC windows: a wrong code (%d of %d)" % [_wrong, WRONG_MAX])
			if _wrong >= WRONG_MAX:
				cancel_pairing()
			_refuse(p, "wrong code")
			return
		var added := clients.add(pc, str(p["address"]))
		client = added["client"]
		new_token = str(added["token"])
		cancel_pairing()
		print("PC windows: a PC paired")
	else:
		_refuse(p, "a hello needs a token or a code")
		return
	client["last_seen"] = Time.get_datetime_string_from_system(false, true)
	client["address"] = str(p["address"])
	clients.save()
	var id := str(client["id"])
	if _sessions.has(id):
		(_sessions[id] as PcSession).close("replaced by a new connection")
	var s := PcSession.new()
	s.client_id = id
	s.pc_name = str(client["name"])
	s.address = str(p["address"])
	s.clock.delay = float(settings.get_value(SECTION, "delay", 0.15)) if settings != null else 0.15
	s.setup(p["tcp"], p["tls"], rest)
	s.windows_changed.connect(func() -> void: windows_changed.emit())
	_sessions[id] = s
	var welcome := {"t": "welcome", "v": PcProtocol.VERSION, "headset": headset_name}
	if new_token != "":
		welcome["token"] = new_token
	s.send(welcome)
	s.send({"t": "list"})
	sessions_changed.emit()
	status_changed.emit()


func _stream(p: Dictionary, m: Dictionary, rest: PackedByteArray) -> void:
	var client := clients.find(str(m.get("token", "")))
	var n := int(m.get("stream", -1))
	var s: PcSession = _sessions.get(str(client.get("id", ""))) if not client.is_empty() else null
	if s == null:
		_refuse(p, "unknown token, or no control connection")
		return
	if not s.expects(n):
		_refuse(p, "stream %d was not asked for" % n)
		return
	var reader := PcStream.new()
	reader.start(p["tcp"], p["tls"], rest, n, s.clock)
	s.attach_stream(n, reader)
