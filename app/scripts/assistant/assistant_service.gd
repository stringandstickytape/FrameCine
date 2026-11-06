extends Node

## The assistant service (docs/assistant.md): an HTTPS API on the headset, port 47801, for an assistant on another
## computer on this network (an AI agent, a script). It pulls the guide from GET /, pairs once with a code the
## headset shows, and then sees what plays, hears the viewer (push-to-talk), answers on the card, controls playback and
## changes the room when the viewer allows it. No program is needed on the PC. Separate from the dev link (port 47800,
## scripts/dev/): its own whitelist (assistant_commands.gd), tokens, TLS.
##
## Off unless the user turns on System, Assistant. Even then the port opens only while "Let an assistant find me"
## runs (a 60-minute window in which the guide and pairing need no token) or once an assistant is paired (then only
## paired assistants get past the guide). A connection from an address that is not private is closed at once.
##
## Pairing: POST /pair/start {client} (window only, one attempt at a time) shows a 6-digit code and the client's name
## in the headset; POST /pair {pair_id, code} returns a token (32 random bytes; only its SHA-256 is kept,
## assistant_clients.gd) and the certificate's pins (assistant_tls.gd). Three wrong codes end an attempt; nine in a
## window close it. Tokens and codes are never printed.
##
## Never blocks the frame: the socket, the TLS handshakes and every connection are polled in _process(); requests are
## parsed from what has arrived; replies, event streams and long waits are written with put_partial_data().

signal status_changed
signal connected_changed(on: bool)
## A change the assistant made (pause, seek, ...): the pane shows it with Undo when undo is valid.
signal remote_change(summary: String, undo: Callable)
## The assistant changed the room (room_editor.gd): on show at once, and kept.
signal room_changed(summary: String)
## A pairing attempt started or ended: the panel shows the code, or stops showing it.
signal pairing_changed

const AssistantClients := preload("res://scripts/assistant/assistant_clients.gd")
const AssistantCommands := preload("res://scripts/assistant/assistant_commands.gd")
const AssistantConversation := preload("res://scripts/assistant/assistant_conversation.gd")
const AssistantGuide := preload("res://scripts/assistant/assistant_guide.gd")
const AssistantTls := preload("res://scripts/assistant/assistant_tls.gd")
const DevCommands := preload("res://scripts/dev/dev_commands.gd")
const PushToTalk := preload("res://scripts/dev/push_to_talk.gd")
const RemoteServer := preload("res://scripts/remote/remote_server.gd")
const RoomEditor := preload("res://scripts/assistant/room_editor.gd")
const RoomSnapshot := preload("res://scripts/assistant/room_snapshot.gd")
const RoomPerf := preload("res://scripts/assistant/room_perf.gd")
const AssistantFetch := preload("res://scripts/assistant/assistant_fetch.gd")
const LibraryCopy := preload("res://scripts/library/library_copy.gd")
const AssistantPlaces := preload("res://scripts/assistant/assistant_places.gd")
const AssistantBrowse := preload("res://scripts/assistant/assistant_browse.gd")
const AgentTerminal := preload("res://scripts/agents/agent_terminal.gd")
const Transcriber := preload("res://scripts/voice/transcriber.gd")
const WhisperBackend := preload("res://scripts/voice/whisper_backend.gd")
const Uri := preload("res://scripts/net/uri.gd")
## The problems the panel can show (status_text()), as keys; the values in them stay as they are.
const PROBLEM_TLS := "Can't make the HTTPS certificate: %s." # i18n
const PROBLEM_PORT := "Can't listen on port %d: %s." # i18n

## The API, HTTPS with the headset's own certificate.
const DEFAULT_PORT := 47802
## The address the viewer gives an assistant: plain HTTP, serving only the guide, the API description and the two
## client programs, so a first look works in any browser or fetch tool without a certificate warning. The guide
## carries the certificate's pin, which the headset also shows, so the assistant can check the HTTPS port.
const DEFAULT_GUIDE_PORT := 47801
const LOCAL_PAIR_TIMEOUT_MSEC := 60000
## What the plain-HTTP guide port serves; everything else is refused there.
const GUIDE_PATHS := ["/", "/guide", "/guide.md", "/openapi.json", "/favicon.ico", "/pin"]
## "Let an assistant find me" (the user's number).
const WINDOW_SECONDS := 3600.0
## How long a code waits for the assistant (the viewer reads it out, the assistant types it).
const ATTEMPT_SECONDS := 300.0
const PAIR_TRIES := 3
## Wrong codes in one window before it closes.
const WINDOW_WRONG_MAX := 9
## Pairing starts: one per address every few seconds, a few a minute in all.
const START_GAP := 3.0
const STARTS_PER_MINUTE := 6
## The header says "Assistant" while an assistant follows the events, waits for a message, or asked within this.
const CONNECTED_SECONDS := 60.0
const HEARTBEAT := 15.0
const WAIT_MAX := 600.0
const STATE_PERIOD := 10.0
const MAX_CONNECTIONS := 32
const MAX_HEAD := 65536
## A room change may carry a 20 MB model (27 MB as base64).
const MAX_BODY := 48 << 20
const REQUEST_TIMEOUT := 20.0
const HANDSHAKE_TIMEOUT := 10.0
const READ_BUDGET := 8 << 20
const WRITE_CHUNK := 16384
const WRITE_BUDGET := 8 << 20
const EVENTS_KEEP := 500
const MESSAGES_KEEP := 100
const CLIPS_KEEP := 20
const CARD_SECONDS := 20.0
const TOOLS := {"assistant.py": "res://assistant/tools/assistant.py",
		"mcp_server.py": "res://assistant/tools/mcp_server.py"}
const CLOSED := "pairing is closed: ask the viewer to press \"Let an assistant find me\" in the headset (System, " \
		+ "Assistant), then try again"

## AppSettings ([assistant] port, and the switches: allow_control, allow_room, allow_settings, allow_files, allow_apps).
var settings: RefCounted
var port := DEFAULT_PORT
## The plain-HTTP guide port (-1: none; off with plain_http).
var guide_port := DEFAULT_GUIDE_PORT
## "*" on the headset; tests use "127.0.0.1".
var bind_address := "*"
## Tests point these at other files.
var clients_path := AssistantClients.PATH
var tls_key_path := AssistantTls.KEY_PATH
var tls_cert_path := AssistantTls.CERT_PATH
## Plain HTTP, no TLS: the engine's own TLS client can't read this server's TLS 1.3 replies, so the in-engine test
## (tests/test_assistant.gd) uses this; tools/assistant/test_assistant.py tests HTTPS with curl and Python. Never on
## in the app.
var plain_http := false
## Speech to text on the headset (scripts/voice/whisper_backend.gd), started with the service; tests turn it off.
var start_whisper := true
## Live partial text while the button is held ([voice] live_partials, false): costs the CPU the film needs; the dots
## show until the final text lands either way.
var live_partials := false
var commands: AssistantCommands
## The assistant's room changes (room_editor.gd).
var room: RoomEditor
## GET /snapshot.png (room_snapshot.gd).
var snapshot: RoomSnapshot
## Push-to-talk (scripts/dev/push_to_talk.gd): ui_layer binds it to the pointer hand's bumper while an assistant is
## connected (assistant.gd push_to_talk()).
var ptt: Node
var clients: AssistantClients
var tls: AssistantTls
var conversation: AssistantConversation
## The last thing that went wrong, in words for the log (English); "" when all is well.
var problem := ""
## The same for the panel: [format, values], translated when status_text() shows it (docs/i18n.md).
var _problem_parts: Array = []
var requests := 0
var refused := 0
var _server: TCPServer
var _guide_server: TCPServer
var _tls_options: TLSOptions
var _tls_tried := false
var _listen_retry := 0.0
## [{tcp, tls, address, in, out, out_pos, wlen, since, mode, done, client_id, ...}]
var _conns: Array[Dictionary] = []
var _window_until := 0.0
var _window_wrong := 0
## The pairing attempt: {pair_id, client, code, tries, until, address}, or {}.
var _attempt := {}
var _starts: Array[float] = []
var _last_start_by := {}
var _events: Array[Dictionary] = []
# Ids keep counting across app restarts (they start from the clock, in ms), so a client's `since` or Last-Event-ID
# from before a restart still means "what is newer". Seen on the headset: a restart reset them to 1, and a client
# waiting for messages after 7 would have missed messages 1 to 7 of the new run.
var _next_event := int(Time.get_unix_time_from_system() * 1000.0)
var _messages: Array[Dictionary] = []
var _next_message := int(Time.get_unix_time_from_system() * 1000.0)
## The assistant's line on the card while it works on what the viewer said (dancing dots at once, so the viewer knows
## they were heard; the answer replaces it), or -1. Its uid is the message id.
var _thinking_uid := -1
## This run of the app: changes at every start, so a client can tell the headset restarted (status, events).
var started := Time.get_datetime_string_from_system(true, false) + "Z"
## message id -> its WAV
var _clips := {}
## message id -> its line on the card (the talk-button press)
var _message_uid := {}
var _presses := 0
var _live_uid := -1
var _live_pcm := PackedByteArray()
var _partial_busy := false
var _partial_more := false
var _pending_uids: Array[int] = []
## transcriber id -> {uid, final, ctx, seconds, wav}
var _jobs := {}
var _last_auth := -1.0e9
var _connected := false
var _state_at := 0.0
var _watched_main: Node
var _card: Node
var _registry_version := -1
var _commands_check_at := 0.0
## A hash of /describe's commands as last seen (0: not yet).
var _commands_sig := 0


func _ready() -> void:
	port = int(settings.get_value("assistant", "port", DEFAULT_PORT)) if settings != null else port
	guide_port = int(settings.get_value("assistant", "guide_port", DEFAULT_GUIDE_PORT)) if settings != null else guide_port
	live_partials = bool(settings.get_value("voice", "live_partials", live_partials)) if settings != null else live_partials
	clients = AssistantClients.new()
	clients.path = clients_path
	clients.load_file()
	tls = AssistantTls.new()
	tls.key_path = tls_key_path
	tls.cert_path = tls_cert_path
	conversation = AssistantConversation.new()
	commands = AssistantCommands.new()
	commands.allow_control = control_allowed
	commands.allow_room = room_allowed
	commands.allow_settings = allowed.bind("settings")
	commands.allow_files = allowed.bind("files")
	commands.allow_apps = allowed.bind("apps")
	room = RoomEditor.new()
	room.name = "RoomEditor"
	add_child(room)
	commands.room = room
	room.changed.connect(_on_room_changed)
	snapshot = RoomSnapshot.new()
	snapshot.name = "Snapshot"
	add_child(snapshot)
	Transcriber.instance().connect("done", _on_transcribed)
	ptt = PushToTalk.new()
	ptt.name = "PushToTalk"
	ptt.register_command = false
	# F8 belongs to the dev link's push-to-talk when that is on too.
	ptt.key_enabled = PushToTalk.instance() == null
	ptt.link = self
	add_child(ptt)
	var fetch: Node = AssistantFetch.ensure(get_tree())
	if not fetch.event.is_connected(_on_download):
		fetch.event.connect(_on_download)
	var copy: Node = LibraryCopy.ensure(get_tree())
	if not copy.event.is_connected(_on_library_copy):
		copy.event.connect(_on_library_copy)
	var places: Node = AssistantPlaces.ensure(get_tree())
	if not places.event.is_connected(_on_place):
		places.event.connect(_on_place)
	var browse: Node = AssistantBrowse.ensure(get_tree())
	if not browse.event.is_connected(_on_browse):
		browse.event.connect(_on_browse)
	if start_whisper:
		WhisperBackend.ensure(get_tree())
	print("Assistant: on (%d paired)" % clients.clients.size())
	# A window still open from before an app restart: open again for the time left.
	var until := int(settings.get_value("assistant", "window_until", 0)) if settings != null else 0
	var left := until - int(Time.get_unix_time_from_system())
	if left > 0:
		open_window(minf(float(left), WINDOW_SECONDS))
	elif until != 0 and settings != null:
		settings.set_value("assistant", "window_until", null)


func _exit_tree() -> void:
	var fetch := get_tree().root.get_node_or_null(AssistantFetch.NODE_NAME)
	if fetch == null and get_tree().root.has_meta(AssistantFetch.NODE_NAME):
		fetch = get_tree().root.get_meta(AssistantFetch.NODE_NAME)
	if fetch != null and is_instance_valid(fetch) and fetch.event.is_connected(_on_download):
		fetch.event.disconnect(_on_download)
	var copy := get_tree().root.get_node_or_null(LibraryCopy.NODE_NAME)
	if copy == null and get_tree().root.has_meta(LibraryCopy.NODE_NAME):
		copy = get_tree().root.get_meta(LibraryCopy.NODE_NAME)
	if copy != null and is_instance_valid(copy) and copy.event.is_connected(_on_library_copy):
		copy.event.disconnect(_on_library_copy)
	var places := get_tree().root.get_node_or_null(AssistantPlaces.NODE_NAME)
	if places == null and get_tree().root.has_meta(AssistantPlaces.NODE_NAME):
		places = get_tree().root.get_meta(AssistantPlaces.NODE_NAME)
	if places != null and is_instance_valid(places) and places.event.is_connected(_on_place):
		places.event.disconnect(_on_place)
	var browse := get_tree().root.get_node_or_null(AssistantBrowse.NODE_NAME)
	if browse == null and get_tree().root.has_meta(AssistantBrowse.NODE_NAME):
		browse = get_tree().root.get_meta(AssistantBrowse.NODE_NAME)
	if browse != null and is_instance_valid(browse) and browse.event.is_connected(_on_browse):
		browse.event.disconnect(_on_browse)
	var t: Object = Transcriber.instance()
	if t.is_connected("done", _on_transcribed):
		t.disconnect("done", _on_transcribed)
	_stop_server()
	tls.wait()
	# The speech model holds memory: it goes with the service (the next start loads it again).
	var whisper := get_tree().root.get_node_or_null(WhisperBackend.NODE_NAME) if start_whisper else null
	if whisper != null:
		whisper.queue_free()


# --- For the panel -------------------------------------------------------------------------------------------------

## Whether the viewer lets the assistant use a level (assistant_commands.gd SWITCHES; read and card always).
func allowed(level: String) -> bool:
	return AssistantCommands.AssistantSwitches.is_on(settings, level)


## Every switch now: {control, room, settings, files, apps} (the permissions event, /status).
func switches() -> Dictionary:
	var out := {}
	for level: String in AssistantCommands.SWITCHES:
		out[level] = allowed(level)
	return out


## A switch in the System tab: "Let the assistant control playback", "... change the room", "... change settings",
## "... manage files", "... run apps". Off: that level's commands are refused, naming the switch.
func set_allowed(level: String, on: bool) -> void:
	settings.set_value("assistant", AssistantCommands.SWITCHES[level]["key"], on)
	_publish("permissions", switches())
	status_changed.emit()


func control_allowed() -> bool:
	return allowed("control")


func room_allowed() -> bool:
	return allowed("room")


## "Let the assistant control playback" (off: it can read and show cards only).
func set_allow_control(on: bool) -> void:
	set_allowed("control", on)


## "Let the assistant change the room" (off: room changes are refused; room_state still answers).
func set_allow_room(on: bool) -> void:
	set_allowed("room", on)


## "Let an assistant find me": the guide and pairing need no token for WINDOW_SECONDS.
func open_window(seconds := WINDOW_SECONDS) -> void:
	_window_until = _now() + seconds
	# Remembered, so an app restart within the window keeps pairing open for the time left.
	if settings != null:
		settings.set_value("assistant", "window_until", int(Time.get_unix_time_from_system() + seconds))
	_window_wrong = 0
	problem = ""
	print("Assistant: an assistant may pair for %d min, at %s" % [int(WINDOW_SECONDS / 60.0), guide_address()])
	_update_listen()
	status_changed.emit()


## Stop: pairing closes (paired assistants keep working).
func close_window() -> void:
	if _window_until <= 0.0:
		return
	_window_until = 0.0
	if settings != null:
		settings.set_value("assistant", "window_until", null)
	cancel_pairing()
	print("Assistant: pairing closed")
	status_changed.emit()


func window_open() -> bool:
	return _now() < _window_until


func window_left() -> float:
	return maxf(_window_until - _now(), 0.0)


## The attempt waiting for its code: {client, code, seconds_left, tries}, or {}.
func pairing() -> Dictionary:
	if _attempt.is_empty():
		return {}
	return {"client": _attempt["client"], "code": _attempt["code"], "tries": _attempt["tries"],
			"seconds_left": maxf(float(_attempt["until"]) - _now(), 0.0)}


func cancel_pairing() -> void:
	if _attempt.is_empty():
		return
	var who: String = _attempt["client"]
	_attempt = {}
	_publish("pairing", {"state": "cancelled", "client": who})
	_end_pairing_card()
	pairing_changed.emit()
	status_changed.emit()


## The paired assistants (no hashes).
func paired() -> Array:
	return clients.public_list()


## A client for an agent on this headset (scripts/agents/): the viewer picking its entry is the consent, so no code and
## no pairing window. Its token goes into the agent's link file (mode 600) and nowhere else: never logged, never on a
## command line. A link that still works is kept. True when the agent has a working link.
func pair_local(agent: String) -> bool:
	var a: Dictionary = AgentTerminal.AGENTS[agent]
	var kept := AgentTerminal.link_token(agent)
	if kept != "" and not clients.find(kept).is_empty():
		return true
	for c: Dictionary in clients.clients.duplicate():
		if c["name"] == a["client"]:
			clients.forget(c["id"])
	var added := clients.add(str(a["client"]), "127.0.0.1")
	_update_listen()
	# The headset's certificate is made once, on a thread: the pin comes when it is there.
	var end := Time.get_ticks_msec() + LOCAL_PAIR_TIMEOUT_MSEC
	while tls.pin == "" and Time.get_ticks_msec() < end and is_inside_tree():
		await get_tree().process_frame
		_update_listen()
	if tls.pin == "":
		return false
	print("Assistant: paired %s (on this headset)" % a["client"])
	status_changed.emit()
	return AgentTerminal.write_link(agent, str(added["token"]), tls.pin)


## Forgets a paired assistant: its token stops working and its open streams close.
func forget(id: String) -> void:
	var c := clients.by_id(id)
	if c.is_empty():
		return
	clients.forget(id)
	AgentTerminal.forget_link(str(c["name"]))
	for conn in _conns.duplicate():
		if conn["client_id"] == id and conn["mode"] != "write":  # its last reply still goes out
			_drop(conn)
	print("Assistant: forgot %s" % c["name"])
	_update_listen()
	status_changed.emit()


func is_listening() -> bool:
	return _server != null and _server.is_listening()


## True while an assistant follows the events, waits for the viewer, or asked something in the last minute.
func is_link_connected() -> bool:
	return _connected


## The address to give an assistant.
func address() -> String:
	var a := RemoteServer.lan_address()
	if bind_address != "*" and bind_address != "":
		a = bind_address
	return "https://%s:%d" % [a if a != "" else "127.0.0.1", port]


## What the viewer gives an assistant: the plain-HTTP guide (the HTTPS address when there is no guide port).
func guide_address() -> String:
	if plain_http or guide_port <= 0:
		return address()
	var a := RemoteServer.lan_address()
	if bind_address != "*" and bind_address != "":
		a = bind_address
	return "http://%s:%d" % [a if a != "" else "127.0.0.1", guide_port]


## The certificate's pin, short, for the viewer to compare with what the assistant reads in the guide.
func pin_short() -> String:
	return tls.pin.trim_prefix("sha256//").left(8) if tls != null and tls.pin != "" else ""


## One line for the panel (the System tab's assistant row), in the menus' language; only the panel shows it. The
## client's name, the addresses and a system error stay as they are.
func status_text() -> String:
	if problem != "":
		return tr(str(_problem_parts[0])) % _problem_parts[1] if _problem_parts.size() == 2 else problem
	if not _attempt.is_empty():
		return tr("%s asks to pair. Tell it this code:") % _attempt["client"]
	if window_open():
		return tr("Give an assistant this address: %s (%d min left).") % [guide_address(), ceili(window_left() / 60.0)]
	if clients.is_empty():
		return tr("No assistant yet. Press \"Let an assistant find me\" and give it the address.")
	if _connected:
		return tr("An assistant is connected.")
	return tr("Listening for paired assistants at %s.") % address()


## A problem for the log (English) and for the panel (translated when shown). The format is a key (PROBLEM_*).
func _set_problem(format: String, values: Array) -> void:
	problem = format % values
	_problem_parts = [format, values]


# --- Listening -----------------------------------------------------------------------------------------------------

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _update_listen() -> void:
	var want := window_open() or not clients.is_empty()
	if not want:
		if is_listening():
			_stop_server()
			print("Assistant: not listening (no window, nobody paired)")
			status_changed.emit()
		return
	if is_listening() or _now() < _listen_retry:
		return
	if not tls.ready():
		if tls.making():
			return
		if not tls.load_files():
			if tls.error == "" and not _tls_tried:
				_tls_tried = true
				print("Assistant: making the HTTPS certificate (once)")
				tls.start_making()
			else:
				_set_problem(PROBLEM_TLS, [tls.error if tls.error != "" else "unknown"])
				_listen_retry = _now() + 30.0
				_tls_tried = false
				status_changed.emit()
			return
	_tls_options = TLSOptions.server(tls.key, tls.cert)
	_server = TCPServer.new()
	var err := _server.listen(port, bind_address)
	if err != OK:
		_server = null
		_set_problem(PROBLEM_PORT, [port, error_string(err)])
		_listen_retry = _now() + 5.0
		push_warning("Assistant: " + problem)
		status_changed.emit()
		return
	if not plain_http and guide_port > 0:
		_guide_server = TCPServer.new()
		if _guide_server.listen(guide_port, bind_address) != OK:
			push_warning("Assistant: can't listen on the guide port %d; the guide is only on HTTPS" % guide_port)
			_guide_server = null
	problem = ""
	print("Assistant: listening at %s (the API) and %s (the guide)" % [address(), guide_address()])
	status_changed.emit()


## The `commands` event when what /describe lists changes (a feature registered or dropped a command, a hot reload
## changed one). Registrations come in bursts, so it looks a second after the registry last moved.
func _watch_commands(now: float) -> void:
	var v := DevCommands.version()
	if v != _registry_version:
		_registry_version = v
		_commands_check_at = now + 1.0
	if _commands_check_at <= 0.0 or now < _commands_check_at:
		return
	_commands_check_at = 0.0
	var list: Array = AssistantCommands.describe()["commands"]
	var sig := JSON.stringify(DevCommands.to_json(list)).hash()
	if _commands_sig != 0 and sig != _commands_sig:
		_publish("commands", {"count": list.size()})
	_commands_sig = sig


func _stop_server() -> void:
	for c in _conns.duplicate():
		_drop(c)
	_conns.clear()
	if _server != null:
		_server.stop()
		_server = null
	if _guide_server != null:
		_guide_server.stop()
		_guide_server = null


func _process(delta: float) -> void:
	var now := _now()
	if _window_until > 0.0 and now >= _window_until:
		_window_until = 0.0
		cancel_pairing()
		print("Assistant: the 60 minutes are over; pairing closed")
		status_changed.emit()
	if not _attempt.is_empty() and now >= float(_attempt["until"]):
		var who: String = _attempt["client"]
		_attempt = {}
		_publish("pairing", {"state": "failed", "client": who, "reason": "timed out"})
		_end_pairing_card()
		pairing_changed.emit()
		status_changed.emit()
	_watch_commands(now)
	_update_listen()
	_watch_main()
	if is_listening():
		_accept()
	var msec := Time.get_ticks_msec()
	for c in _conns.duplicate():
		_poll(c, msec)
	_update_connected(now)
	if _has_streams():
		var main := AssistantCommands._main()
		if main != null and "player" in main and main.player.is_playing():
			_state_at += delta
			if _state_at >= STATE_PERIOD:
				_publish_state()


func _accept() -> void:
	_accept_from(_server, not plain_http)
	if _guide_server != null:
		_accept_from(_guide_server, false)


func _accept_from(server: TCPServer, secure: bool) -> void:
	while server.is_connection_available():
		var tcp := server.take_connection()
		var host := tcp.get_connected_host()
		if not RemoteServer.is_private(host) or _conns.size() >= MAX_CONNECTIONS:
			refused += 1
			if refused <= 20 or refused % 100 == 0:
				print("Assistant: refused a connection from %s (%s)" % [host, "not a private address"
						if not RemoteServer.is_private(host) else "too many connections"])
			tcp.disconnect_from_host()
			continue
		tcp.set_no_delay(true)
		var peer: StreamPeer = tcp
		if secure:
			var t := StreamPeerTLS.new()
			if t.accept_stream(tcp, _tls_options) != OK:
				tcp.disconnect_from_host()
				continue
			peer = t
		_conns.append({"tcp": tcp, "tls": peer, "address": host, "in": PackedByteArray(), "out": PackedByteArray(),
				"out_pos": 0, "wlen": 0, "since": Time.get_ticks_msec(), "mode": "read", "done": false,
				"client_id": "", "guide_only": server == _guide_server})


func _poll(c: Dictionary, msec: int) -> void:
	var tcp: StreamPeerTCP = c["tcp"]
	# A StreamPeerTLS, or the StreamPeerTCP itself with plain_http (the status numbers are the same).
	var peer: Variant = c["tls"]
	tcp.poll()
	if peer != tcp and (peer.get_status() == StreamPeerTLS.STATUS_HANDSHAKING
			or peer.get_status() == StreamPeerTLS.STATUS_CONNECTED):
		peer.poll()
	var st: int = peer.get_status()
	if st == StreamPeerTLS.STATUS_HANDSHAKING:
		if msec - int(c["since"]) > HANDSHAKE_TIMEOUT * 1000.0:
			_drop(c)
		return
	if st != StreamPeerTLS.STATUS_CONNECTED:
		_drop(c)
		return
	match c["mode"]:
		"read":
			if not _read(c):
				return
			_try_request(c)
			if c["mode"] == "read" and msec - int(c["since"]) > REQUEST_TIMEOUT * 1000.0:
				_drop(c)
				return
		"sse":
			if not _read(c, true):
				return
			if _now() >= float(c["beat_at"]):
				c["beat_at"] = _now() + HEARTBEAT
				_write(c, ": keepalive\n\n".to_utf8_buffer())
		"wait":
			if not _read(c, true):
				return
			var out := _messages_after(int(c["wait_since"]))
			if not out.is_empty():
				_reply(c, 200, {"ok": true, "result": out, "timed_out": false})
			elif _now() >= float(c["wait_until"]):
				_reply(c, 200, {"ok": true, "result": [], "timed_out": true})
	if _conns.has(c):
		_flush(c)


## Reads what has arrived (discard: an open stream, where the client sends nothing that matters). False when the
## connection was dropped.
func _read(c: Dictionary, discard := false) -> bool:
	var peer: Variant = c["tls"]
	var buf: PackedByteArray = c["in"]
	var got := 0
	while got < READ_BUDGET:
		var r: Array = peer.get_partial_data(65536)
		if r[0] != OK:
			_drop(c)
			return false
		var d: PackedByteArray = r[1]
		if d.is_empty():
			break
		got += d.size()
		if not discard:
			buf.append_array(d)
	if got > 0 and not discard:
		c["in"] = buf
		c["since"] = Time.get_ticks_msec()
	return true


func _write(c: Dictionary, data: PackedByteArray) -> void:
	var out: PackedByteArray = c["out"]
	out.append_array(data)
	c["out"] = out


func _flush(c: Dictionary) -> void:
	var peer: Variant = c["tls"]
	var out: PackedByteArray = c["out"]
	var pos: int = c["out_pos"]
	var sent := 0
	while pos < out.size() and sent < WRITE_BUDGET:
		# After a write that could not go out, TLS wants the very same bytes again.
		var n: int = c["wlen"] if int(c["wlen"]) > 0 else mini(WRITE_CHUNK, out.size() - pos)
		var r: Array = peer.put_partial_data(out.slice(pos, pos + n))
		if r[0] != OK:
			_drop(c)
			return
		if int(r[1]) <= 0:
			c["wlen"] = n
			break
		c["wlen"] = 0
		pos += int(r[1])
		sent += int(r[1])
	if pos >= out.size():
		out = PackedByteArray()
		pos = 0
	c["out"] = out
	c["out_pos"] = pos
	if c["done"] and out.is_empty():
		_drop(c)


func _drop(c: Dictionary) -> void:
	var peer: Variant = c["tls"]
	if peer is StreamPeerTLS and peer.get_status() == StreamPeerTLS.STATUS_CONNECTED:
		peer.disconnect_from_stream()
	(c["tcp"] as StreamPeerTCP).disconnect_from_host()
	_conns.erase(c)


func _has_streams() -> bool:
	return _conns.any(func(c: Dictionary) -> bool: return c["mode"] == "sse")


func _update_connected(now: float) -> void:
	var on := now - _last_auth < CONNECTED_SECONDS or _conns.any(func(c: Dictionary) -> bool:
			return c["client_id"] != "" and (c["mode"] == "sse" or c["mode"] == "wait"))
	if on != _connected:
		_connected = on
		connected_changed.emit(on)
		status_changed.emit()
		# The room's cost is measured while an assistant is connected (GET /perf has a minute of history).
		if is_inside_tree():
			RoomPerf.ensure(get_tree()).hold(self, on)


# --- HTTP ----------------------------------------------------------------------------------------------------------

func _try_request(c: Dictionary) -> void:
	var buf: PackedByteArray = c["in"]
	var head_end := RemoteServer._head_end(buf)
	if head_end < 0:
		if buf.size() > MAX_HEAD:
			_respond(c, 431, "text/plain", "Request header too large".to_utf8_buffer())
		return
	var lines := buf.slice(0, head_end).get_string_from_utf8().split("\r\n")
	var first := lines[0].split(" ")
	if first.size() < 2:
		_respond(c, 400, "text/plain", "Bad request".to_utf8_buffer())
		return
	# A client that leaves spaces unencoded in the target (an smb:// path with a space in a folder name): everything
	# between the method and "HTTP/1.x" is the target.
	if first.size() > 3 and first[-1].begins_with("HTTP/"):
		first = PackedStringArray([first[0], " ".join(first.slice(1, first.size() - 1)).replace(" ", "%20"), first[-1]])
	var headers := {}
	for i in range(1, lines.size()):
		var kv := lines[i].split(":", true, 1)
		if kv.size() == 2:
			headers[kv[0].strip_edges().to_lower()] = kv[1].strip_edges()
	var length := int(headers.get("content-length", "0"))
	if length > MAX_BODY or length < 0:
		_reply(c, 413, {"ok": false, "error": "the body is too large (at most 48 MB)"})
		return
	if buf.size() < head_end + 4 + length:
		return  # the body is still arriving
	var body := buf.slice(head_end + 4, head_end + 4 + length)
	c["in"] = PackedByteArray()
	requests += 1
	_handle(c, first[0].to_upper(), first[1], headers, body)


func _handle(c: Dictionary, method: String, target: String, headers: Dictionary, body: PackedByteArray) -> void:
	var path := target.get_slice("?", 0)
	var query := target.get_slice("?", 1) if target.contains("?") else ""
	if path.length() > 1:
		path = path.trim_suffix("/")
	if headers.has("origin"):
		_reply(c, 403, {"ok": false, "error": "requests from web pages are refused"})
		return
	var url := _url_for(headers)
	if c.get("guide_only", false):
		url = address()
		# An agent on the headset itself: the loopback works with no network at all.
		if str(c.get("address", "")).begins_with("127."):
			url = "https://127.0.0.1:%d" % port
		if not (method == "GET" and (path in GUIDE_PATHS or (path.begins_with("/tools/")
				and TOOLS.has(path.trim_prefix("/tools/"))))):
			_reply(c, 403, {"ok": false, "error": "this plain-HTTP port serves only the guide; the API is HTTPS at "
					+ "%s (read GET / first: it explains the headset's certificate and its pin)" % address()})
			return
		if path == "/pin":
			_reply(c, 200, {"ok": true, "result": {"pin": tls.pin, "cert_sha256": tls.cert_sha256,
					"api": address()}})
			return
	var params := _params(query, headers, body)
	if params.has("_error"):
		_reply(c, 400, {"ok": false, "error": params["_error"]})
		return
	var client := _auth(headers, query)
	if not client.is_empty():
		c["client_id"] = client["id"]
		_last_auth = _now()
		client["last_seen"] = Time.get_datetime_string_from_system(false, true)
		client["address"] = c["address"]
	# Open to anyone on the network: the guide, the API description, the client programs, pairing (window only).
	if method == "GET" and (path == "/" or path == "/guide" or path == "/guide.md"):
		_respond(c, 200, "text/plain; charset=utf-8", AssistantGuide.guide(url, _status_line(client), tls.pin)
				.to_utf8_buffer())
		return
	if method == "GET" and path == "/openapi.json":
		_reply(c, 200, AssistantGuide.openapi(url))
		return
	if method == "GET" and path.begins_with("/tools/") and TOOLS.has(path.trim_prefix("/tools/")):
		var file := FileAccess.get_file_as_bytes(TOOLS[path.trim_prefix("/tools/")])
		_respond(c, 200 if not file.is_empty() else 404, "text/x-python; charset=utf-8", file)
		return
	if method == "GET" and path == "/favicon.ico":
		_respond(c, 204, "text/plain", PackedByteArray())
		return
	if method == "POST" and path == "/pair/start":
		_pair_start(c, params)
		return
	if method == "POST" and path == "/pair":
		_pair(c, params, url)
		return
	if client.is_empty():
		var why := "a token is needed: Authorization: Bearer TOKEN (pair first: GET / says how)"
		if _auth_given(headers, query):
			why = "this token is not paired with this headset (forgotten?): pair again (GET / says how)"
		_reply(c, 401, {"ok": false, "error": why})
		return
	match [method, path]:
		["GET", "/status"]:
			_reply(c, 200, {"ok": true, "result": status(client)})
		["GET", "/describe"]:
			var d := AssistantCommands.describe(allowed)
			d["events"] = AssistantGuide.events()
			_reply(c, 200, {"ok": true, "result": d})
		["GET", "/state"]:
			_run(c, "state", {})
		["GET", "/places"]:
			_run(c, "places", {})
		["GET", "/perf"]:
			_run(c, "perf", {})
		["GET", "/snapshot.png"]:
			_snapshot(c, params)
		["GET", "/snapshot_clip.png"]:
			_snapshot_clip(c, params)
		["GET", "/list"]:
			_run(c, "list_dir", {"path": str(params.get("path", ""))})
		["POST", "/command"]:
			var cmd := str(params.get("cmd", ""))
			if cmd == "":
				_reply(c, 400, {"ok": false, "error": "give cmd (and its arguments): GET /describe lists them"})
				return
			var args: Variant = params.get("args", null)
			if args == null:
				args = _form_args(cmd, params)
			if not (args is Dictionary):
				_reply(c, 400, {"ok": false, "error": "args must be an object"})
				return
			_run(c, cmd, args)
		["POST", "/card"]:
			if str(params.get("text", "")).strip_edges() == "":
				_reply(c, 400, {"ok": false, "error": "text is required"})
				return
			var args := {"text": str(params["text"]), "title": str(params.get("title", ""))}
			if params.has("seconds"):
				args["seconds"] = params["seconds"]
			_run(c, "card", args)
		["POST", "/answer"]:
			_reply_result(c, answer(params))
		["GET", "/messages"]:
			var since := _int(params.get("since"), 0)
			var limit := clampi(_int(params.get("limit"), 20), 1, MESSAGES_KEEP)
			var out := _messages_after(since)
			_reply(c, 200, {"ok": true, "result": out.slice(maxi(out.size() - limit, 0))})
		["GET", "/messages/wait"]:
			c["mode"] = "wait"
			c["wait_since"] = _int(params.get("since"), _next_message - 1)
			c["wait_until"] = _now() + clampf(float(params.get("timeout", 60)), 0.0, WAIT_MAX)
		["GET", "/events"]:
			_start_stream(c, params, headers)
		["POST", "/forget"]:
			_reply(c, 200, {"ok": true, "result": {"forgotten": client["name"]}})
			forget(client["id"])
		_:
			if method == "GET" and path.begins_with("/voice/") and path.ends_with(".wav"):
				var id := path.trim_prefix("/voice/").trim_suffix(".wav")
				if id.is_valid_int() and _clips.has(int(id)):
					_respond(c, 200, "audio/wav", _clips[int(id)])
				else:
					_reply(c, 404, {"ok": false, "error": "no clip %s (the last %d are kept)" % [id, CLIPS_KEEP]})
				return
			_reply(c, 404, {"ok": false, "error": "no such endpoint; GET / lists them"})


## A whole number from a query, form or JSON value, else `default`.
static func _int(v: Variant, default: int) -> int:
	if v is int or (v is float and v == floorf(v)):
		return int(v)
	if v is String and (v as String).strip_edges().is_valid_int():
		return (v as String).strip_edges().to_int()
	return default


## Query parameters, then the body (JSON, or form fields).
static func _params(query: String, headers: Dictionary, body: PackedByteArray) -> Dictionary:
	var out := _form(query)
	if body.is_empty():
		return out
	var text := body.get_string_from_utf8()
	var ctype := str(headers.get("content-type", "")).to_lower()
	if ctype.begins_with("application/json") or text.strip_edges().begins_with("{"):
		var json := JSON.new()
		if json.parse(text) != OK or not (json.data is Dictionary):
			return {"_error": "the body is not a JSON object: %s" % json.get_error_message()}
		out.merge(json.data, true)
		return out
	out.merge(_form(text), true)
	return out


static func _form(text: String) -> Dictionary:
	var out := {}
	for part in text.split("&", false):
		var kv := part.split("=", true, 1)
		out[Uri.decode(kv[0].replace("+", " "))] = Uri.decode(kv[1].replace("+", " ")) if kv.size() > 1 else ""
	return out


## Form fields as a command's arguments: everything but cmd; lists, objects and "any" values are read as JSON.
static func _form_args(cmd: String, params: Dictionary) -> Dictionary:
	var types := {}
	for p: Dictionary in DevCommands.get_spec(cmd).get("params", []):
		types[p["name"]] = str(p["type"])
	var args := {}
	for k: Variant in params:
		if k == "cmd" or k == "token" or k == "timeout":
			continue
		var v: Variant = params[k]
		if v is String and str(types.get(k, "")) in ["array", "object", "any"]:
			var json := JSON.new()
			if json.parse(v) == OK:
				v = json.data
		args[k] = v
	return args


func _auth_given(headers: Dictionary, query: String) -> bool:
	return str(headers.get("authorization", "")) != "" or RemoteServer._query_value(query, "token") != ""


func _auth(headers: Dictionary, query: String) -> Dictionary:
	var token := ""
	var a := str(headers.get("authorization", ""))
	if a.to_lower().begins_with("bearer "):
		token = a.substr(7).strip_edges()
	if token == "":
		token = RemoteServer._query_value(query, "token")
	return clients.find(token) if token != "" else {}


## https:// and the Host the client used (it reached us that way), else our LAN address.
func _url_for(headers: Dictionary) -> String:
	var host := str(headers.get("host", ""))
	var ok := host != "" and host.length() < 100
	for ch in host:
		if not (ch in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-:[]"):
			ok = false
	return "https://" + host if ok else address()


func _respond(c: Dictionary, code: int, content_type: String, body: PackedByteArray, extra := "") -> void:
	var reasons := {200: "OK", 204: "No Content", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden",
			404: "Not Found", 409: "Conflict", 413: "Payload Too Large", 422: "Unprocessable Content",
			429: "Too Many Requests", 431: "Request Header Fields Too Large", 500: "Internal Server Error",
			503: "Service Unavailable"}
	var head := "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-store\r\n" % [code,
			reasons.get(code, "Error"), content_type, body.size()] + "X-Content-Type-Options: nosniff\r\n" + extra \
			+ "Connection: close\r\n\r\n"
	_write(c, head.to_utf8_buffer())
	_write(c, body)
	c["mode"] = "write"
	c["done"] = true


func _reply(c: Dictionary, code: int, obj: Dictionary) -> void:
	if not _conns.has(c):
		return
	_respond(c, code, "application/json; charset=utf-8", JSON.stringify(DevCommands.to_json(obj)).to_utf8_buffer())


## A command's result as an HTTP reply: 200, 409 when refused, 422 when it could not.
func _reply_result(c: Dictionary, r: Dictionary) -> void:
	var out := {"ok": bool(r.get("ok", false))}
	if out["ok"]:
		out["result"] = r.get("result")
	else:
		out["error"] = str(r.get("error", ""))
		for k in ["refused", "errors", "limit", "switch"]:
			if r.has(k):
				out[k] = r[k]
	_reply(c, int(r.get("status", 200 if out["ok"] else (409 if r.get("refused", false) else 422))), out)


func _run(c: Dictionary, cmd: String, args: Dictionary) -> void:
	c["mode"] = "busy"
	var client: Dictionary = clients.by_id(str(c.get("client_id", ""))) if str(c.get("client_id", "")) != "" else {}
	commands.client_name = _clean_name(str(client.get("name", "")))
	var r: Dictionary = await commands.run(cmd, args)
	if not _conns.has(c):
		return
	_reply_result(c, r)
	# The footer's note with Undo: for what a switch allowed, except the room (its own note: kept, no undo).
	var level := DevCommands.assistant_level(cmd)
	if r.get("ok", false) and str(r.get("summary", "")) != "" and AssistantCommands.SWITCHES.has(level) \
			and level != "room":
		remote_change.emit(str(r["summary"]), r.get("undo", Callable()))


# --- Pairing -------------------------------------------------------------------------------------------------------

func _pair_start(c: Dictionary, params: Dictionary) -> void:
	if not window_open():
		_reply(c, 403, {"ok": false, "error": CLOSED})
		return
	var now := _now()
	if not _attempt.is_empty():
		_reply(c, 409, {"ok": false, "error": "another assistant (%s) is pairing now; try again in a few minutes"
				% _attempt["client"]})
		return
	_starts = _starts.filter(func(t: float) -> bool: return now - t < 60.0)
	if now - float(_last_start_by.get(c["address"], -1.0e9)) < START_GAP or _starts.size() >= STARTS_PER_MINUTE:
		_reply(c, 429, {"ok": false, "error": "too many tries: wait a minute"})
		return
	_starts.append(now)
	_last_start_by[c["address"]] = now
	var who := _clean_name(str(params.get("client", "")))
	var crypto := Crypto.new()
	_attempt = {"pair_id": crypto.generate_random_bytes(8).hex_encode(), "client": who,
			"code": "%06d" % (crypto.generate_random_bytes(4).decode_u32(0) % 1000000), "tries": PAIR_TRIES,
			"until": now + ATTEMPT_SECONDS, "address": c["address"]}
	print("Assistant: %s (%s) asks to pair; the code shows in the headset" % [who, c["address"]])
	_publish("pairing", {"state": "started", "client": who})
	_show_pairing_card()
	pairing_changed.emit()
	status_changed.emit()
	_reply(c, 200, {"ok": true, "result": {"pair_id": _attempt["pair_id"], "client": who,
			"seconds": int(ATTEMPT_SECONDS), "next": "Ask your user to read you the 6-digit code shown in the "
			+ "headset, then POST /pair with pair_id and code. Three wrong codes end this attempt."}})


func _pair(c: Dictionary, params: Dictionary, url: String) -> void:
	if not window_open():
		_reply(c, 403, {"ok": false, "error": CLOSED})
		return
	if _attempt.is_empty() or str(params.get("pair_id", "")) != _attempt["pair_id"]:
		_reply(c, 409, {"ok": false, "error": "no pairing attempt with this pair_id (it ended, timed out or was "
				+ "cancelled): start again with POST /pair/start"})
		return
	var digits := ""
	for ch in str(params.get("code", "")):
		if ch >= "0" and ch <= "9":
			digits += ch
	var good := digits.length() == 6 and Crypto.new().constant_time_compare(digits.to_ascii_buffer(),
			str(_attempt["code"]).to_ascii_buffer())
	if not good:
		_attempt["tries"] = int(_attempt["tries"]) - 1
		_window_wrong += 1
		var left: int = _attempt["tries"]
		var who: String = _attempt["client"]
		if left <= 0:
			_attempt = {}
			_publish("pairing", {"state": "failed", "client": who, "reason": "wrong code"})
			_end_pairing_card()
			pairing_changed.emit()
			print("Assistant: three wrong codes from %s; that attempt is over" % who)
		status_changed.emit()
		if _window_wrong >= WINDOW_WRONG_MAX:
			print("Assistant: too many wrong codes; pairing closed")
			close_window()
		_reply(c, 403, {"ok": false, "error": "wrong code; %s" % ("%d %s left" % [left, "try" if left == 1
				else "tries"] if left > 0 else "this attempt is over: start again with POST /pair/start"),
				"tries_left": maxi(left, 0)})
		return
	var who: String = _attempt["client"]
	var added := clients.add(who, c["address"])
	_attempt = {}
	_last_auth = _now()
	c["client_id"] = added["client"]["id"]
	print("Assistant: paired with %s" % who)
	_publish("pairing", {"state": "paired", "client": who})
	_end_pairing_card()
	pairing_changed.emit()
	status_changed.emit()
	_reply(c, 200, {"ok": true, "result": {"token": added["token"], "pin": tls.pin, "cert_sha256": tls.cert_sha256,
			"client_id": added["client"]["id"], "client": who, "expires": "never", "url": url,
			"next": "Keep token, pin and cert_sha256. Send Authorization: Bearer TOKEN with every request, check the "
			+ "pin (curl: -k --pinnedpubkey PIN), and read GET / again: it now shows what plays."}})


static func _clean_name(s: String) -> String:
	var out := ""
	for ch in s.strip_edges():
		if ch.unicode_at(0) >= 32 and ch != "\u007f":
			out += ch
	out = out.strip_edges().left(40)
	return out if out != "" else "An assistant"


func _show_pairing_card() -> void:
	var card := _card_node()
	if card == null:
		return
	var code: String = _attempt["code"]
	card.show_card({"id": "pairing", "title": "Pairing", "seconds": ATTEMPT_SECONDS,
			"text": "%s asks to pair with this headset.\n\nTell it this code:  %s %s\n\n(Cancel in System, Assistant.)"
			% [_attempt["client"], code.left(3), code.right(3)]})


func _end_pairing_card() -> void:
	var card := _card_node()
	if card != null and card.visible and str(card.id) == "pairing":
		card.dismiss("cleared")


# --- Status --------------------------------------------------------------------------------------------------------

func status(client: Dictionary = {}) -> Dictionary:
	var p := {"open": window_open(), "seconds_left": int(window_left())}
	if not _attempt.is_empty():
		p["attempt"] = {"client": _attempt["client"], "tries_left": _attempt["tries"]}
	return {"you": {"id": client.get("id", ""), "name": client.get("name", "")}, "paired": clients.public_list(),
			"control_allowed": control_allowed(), "room_allowed": room_allowed(), "allowed": switches(),
			"transcriber": Transcriber.describe(), "pairing": p, "address": address(),
			"connected": _connected, "last_message_id": _messages[-1]["id"] if not _messages.is_empty() else 0,
			"started": started}


## The guide's "Now:" line. Without a token it says nothing about what plays.
func _status_line(client: Dictionary) -> String:
	if client.is_empty():
		if window_open():
			if not _attempt.is_empty():
				return "pairing is open, and %s is pairing now; if that is you, send the code (step 1.3)." \
						% _attempt["client"]
			return "pairing is open for %d more minutes: pair now (section 1)." % ceili(window_left() / 60.0)
		return CLOSED + ". If you paired before, send your token to see what plays."
	var what := "nothing is open"
	var main := AssistantCommands._main()
	if main != null and "player" in main:
		var s := AssistantCommands.state(main, control_allowed())
		if str(s.get("path", "")) != "":
			what = "%s \"%s\" at %s of %s" % ["playing" if s.get("playing", false) else "paused",
					str(s.get("title", "")) if str(s.get("title", "")) != "" else _file_name(str(s["path"])),
					_clock(float(s.get("position", 0.0))), _clock(float(s.get("duration", 0.0)))]
	var on: PackedStringArray = ["read", "card"]
	var off: PackedStringArray = []
	for level: String in AssistantCommands.SWITCHES:
		if allowed(level):
			on.append(level)
		else:
			off.append(level)
	return "you are paired as %s. %s; the viewer allows %s%s; speech to text on the headset: %s." % [
			client["name"], what[0].to_upper() + what.substr(1), ", ".join(on),
			" (switched off: %s)" % ", ".join(off) if not off.is_empty() else "", Transcriber.describe()]


static func _clock(t: float) -> String:
	var s := int(maxf(t, 0.0))
	return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60] if s >= 3600 else "%d:%02d" % [s / 60, s % 60]


static func _file_name(path: String) -> String:
	return path.get_slice("?", 0).trim_suffix("/").get_file()


# --- Events --------------------------------------------------------------------------------------------------------

func _publish(event_name: String, data: Variant) -> void:
	var ev := {"id": _next_event, "event": event_name, "data": DevCommands.to_json(data)}
	_next_event += 1
	_events.append(ev)
	if _events.size() > EVENTS_KEEP:
		_events = _events.slice(_events.size() - EVENTS_KEEP)
	for c in _conns:
		if c["mode"] == "sse":
			_send_event(c, ev)


func _send_event(c: Dictionary, ev: Dictionary) -> void:
	var types: Array = c["types"]
	if not types.is_empty() and not (ev["event"] in types) and ev["event"] != "status":  # status: first, always
		return
	var line := "event: %s\ndata: %s\n\n" % [ev["event"], JSON.stringify(ev["data"])]
	if int(ev["id"]) > 0:
		line = "id: %d\n" % ev["id"] + line
	_write(c, line.to_utf8_buffer())


func _start_stream(c: Dictionary, params: Dictionary, headers: Dictionary) -> void:
	var types: Array = []
	for t in str(params.get("types", "")).split(",", false):
		types.append(t.strip_edges())
	c["types"] = types
	c["mode"] = "sse"
	c["beat_at"] = _now() + HEARTBEAT
	_write(c, ("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream; charset=utf-8\r\nCache-Control: no-store\r\n"
			+ "X-Accel-Buffering: no\r\nConnection: close\r\n\r\nretry: 3000\n\n").to_utf8_buffer())
	_send_event(c, {"id": 0, "event": "status", "data": DevCommands.to_json(status(clients.by_id(c["client_id"])))})
	var last := str(headers.get("last-event-id", params.get("last_event_id", "")))
	if last.is_valid_int():
		for ev in _events:
			if int(ev["id"]) > last.to_int():
				_send_event(c, ev)
	elif types.is_empty() or "state" in types:
		var main := AssistantCommands._main()
		if main != null and "player" in main:
			_send_event(c, {"id": 0, "event": "state", "data": DevCommands.to_json(_state())})


func _state() -> Dictionary:
	var main := AssistantCommands._main()
	var st := AssistantCommands.state(main, control_allowed())
	st["room_allowed"] = room_allowed()
	return st


func _publish_state() -> void:
	var main := AssistantCommands._main()
	if main != null and "player" in main:
		_state_at = 0.0
		_publish("state", _state())


func _watch_main() -> void:
	var main := AssistantCommands._main()
	if main == _watched_main or main == null or not ("player" in main) or not is_instance_valid(main):
		return
	_watched_main = main
	main.player.playing_changed.connect(_on_playing_changed)
	main.file_opened.connect(_on_file_opened)
	var card := _card_node()
	if card != null and card.has_signal("dismissed") and not card.dismissed.is_connected(_on_card_dismissed):
		card.dismissed.connect(_on_card_dismissed)


func _card_node() -> Node:
	var main := AssistantCommands._main()
	var ui: Node = main.get("ui") if main != null else null
	var card: Node = ui.get("card") if ui != null else null
	return card if card != null and card.has_method("show_card") else null


func _on_playing_changed(_playing: bool) -> void:
	_publish_state()


func _on_file_opened(path: String) -> void:
	var main := AssistantCommands._main()
	_publish("file_opened", {"path": path, "title": main.display_title() if main != null and path != "" else ""})
	_publish_state()


## A page the assistant asked to open (assistant_browse.gd): the `browse` event.
func _on_browse(data: Dictionary) -> void:
	_publish("browse", data)


## A place the assistant suggested (assistant_places.gd): the `place` event.
func _on_place(data: Dictionary) -> void:
	_publish("place", data)


## The headset's download (assistant_fetch.gd): the `download` event.
func _on_download(data: Dictionary) -> void:
	_publish("download", data)


## A copy into the Library (library_copy.gd): the `library_copy` event.
func _on_library_copy(data: Dictionary) -> void:
	_publish("library_copy", data)
	if str(data.get("state", "")) in ["started", "done", "failed", "cancelled"]:
		_publish_state()


func _on_card_dismissed(id: String, how: String) -> void:
	if how != "replaced" and id != "pairing":
		_publish("card_dismissed", {"id": id, "how": how})


func _on_room_changed(summary: String, room_name: String) -> void:
	_publish("room", {"state": "kept", "change": summary, "name": room_name})
	room_changed.emit(summary)


## GET /snapshot.png: a picture of the room as the viewer sees it (or from the seat), rendered on demand.
func _snapshot(c: Dictionary, params: Dictionary) -> void:
	c["mode"] = "busy"
	var from := _snapshot_from(c, params)
	if from == "":
		return
	var w := clampi(_int(params.get("width"), RoomSnapshot.DEFAULT_SIZE.x), 16, RoomSnapshot.MAX_SIDE)
	var h := clampi(_int(params.get("height"), roundi(w * 9.0 / 16.0)), 16, RoomSnapshot.MAX_SIDE)
	var fov := clampf(float(params.get("fov", RoomSnapshot.DEFAULT_FOV)), 20.0, 120.0)
	var r: Dictionary = await snapshot.capture(from, Vector2i(w, h), fov)
	if not _conns.has(c):
		return
	if r.has("error"):
		_reply(c, 503, {"ok": false, "error": r["error"]})
		return
	_respond(c, 200, "image/png", r["png"])


## from (viewer, seat) and seat (a seat's name, with from=seat) as RoomSnapshot.pose takes them; "" after a 400.
func _snapshot_from(c: Dictionary, params: Dictionary) -> String:
	var from := str(params.get("from", "viewer"))
	if not (from in ["viewer", "seat"]):
		_reply(c, 400, {"ok": false, "error": "from: viewer or seat"})
		return ""
	var seat_name := str(params.get("seat", ""))
	if seat_name == "":
		return from
	var main := AssistantCommands._main()
	var names: Array = main.features.seat.names() if main != null and main.get("features") != null else []
	if not (seat_name in names):
		_reply(c, 400, {"ok": false, "error": "seat: no seat %s here (the seats: %s)" % [seat_name,
				", ".join(names) if not names.is_empty() else "none"]})
		return ""
	return "seat:" + seat_name


## GET /snapshot_clip.png: a few seconds of the room, as a sheet of frames (default) or an animated PNG.
func _snapshot_clip(c: Dictionary, params: Dictionary) -> void:
	c["mode"] = "busy"
	var format := str(params.get("format", "sheet"))
	if not (format in ["sheet", "apng"]):
		_reply(c, 400, {"ok": false, "error": "format: sheet or apng"})
		return
	var from := _snapshot_from(c, params)
	if from == "":
		return
	var w := clampi(_int(params.get("width"), RoomSnapshot.CLIP_DEFAULT_SIZE.x), 16, RoomSnapshot.CLIP_MAX_SIDE)
	var h := clampi(_int(params.get("height"), roundi(w * 9.0 / 16.0)), 16, RoomSnapshot.CLIP_MAX_SIDE)
	var seconds := clampf(float(params.get("seconds", 2.0)), 0.25, RoomSnapshot.CLIP_SECONDS_MAX)
	var fps := clampi(_int(params.get("fps"), 8), 1, RoomSnapshot.CLIP_FPS_MAX)
	var fov := clampf(float(params.get("fov", RoomSnapshot.DEFAULT_FOV)), 20.0, 120.0)
	var r: Dictionary = await snapshot.capture_clip(from, Vector2i(w, h), fov, seconds, fps, format)
	if not _conns.has(c):
		return
	if r.has("error"):
		_reply(c, 503, {"ok": false, "error": r["error"]})
		return
	_respond(c, 200, "image/apng" if format == "apng" else "image/png", r["png"],
			"X-Frames: %d\r\nX-Columns: %d\r\n" % [r["frames"], r["columns"]])


# --- The viewer's voice and the conversation card ------------------------------------------------------------------

## Push-to-talk's events (scripts/dev/push_to_talk.gd calls this as its link).
func send_event(event_name: String, data: Variant = {}) -> void:
	var d: Dictionary = data if data is Dictionary else {}
	match event_name:
		"voice_state":
			_publish("voice_state", {"recording": bool(d.get("recording", false))})
			if d.get("recording", false):
				_presses += 1
				_live_uid = _presses
				_live_pcm = PackedByteArray()
				_partial_more = false
				_pending_uids.append(_presses)
				conversation.set_line(_presses, "You", "(listening)", true)
				_show_conversation()
			elif _live_uid >= 0:
				# Too short a press sends no clip: its line goes (checked once the clip had its chance).
				_check_clip.call_deferred(_live_uid)
				_live_uid = -1
		"voice_partial":
			if _live_uid < 0:
				return
			_live_pcm.append_array(Marshalls.base64_to_raw(str(d.get("pcm_b64", ""))))
			if not Transcriber.available() or not live_partials:
				return
			if _partial_busy:
				_partial_more = true
			else:
				_start_partial()
		"voice_clip":
			var uid: int = _pending_uids.pop_front() if not _pending_uids.is_empty() else -1
			if uid == _live_uid:
				_live_uid = -1
			_on_clip(Marshalls.base64_to_raw(str(d.get("wav_b64", ""))), float(d.get("seconds", 0.0)), uid)


func _check_clip(uid: int) -> void:
	if uid in _pending_uids:
		_pending_uids.erase(uid)
		conversation.set_line(uid, "You", null)
		_show_conversation()


func _start_partial() -> void:
	_partial_busy = true
	_partial_more = false
	var id := Transcriber.transcribe(_live_pcm.duplicate(), false)
	if id < 0:
		_partial_busy = false  # skipped (the backend is busy): the next second of audio tries again
		return
	_jobs[id] = {"uid": _live_uid, "final": false}


func _on_clip(wav: PackedByteArray, seconds: float, uid: int) -> void:
	if wav.size() <= 44:
		return
	var ctx: Dictionary = await _context()
	if not is_inside_tree():
		return
	var job := {"uid": uid, "final": true, "ctx": ctx, "seconds": seconds, "wav": wav}
	var id := Transcriber.transcribe(wav.slice(44), true) if Transcriber.available() else -1
	if id >= 0:
		_jobs[id] = job
	else:
		_not_heard(job, "Speech to text isn't working on the headset, so nothing was sent.")


func _on_transcribed(id: int, text: String, final: bool) -> void:
	if not _jobs.has(id):
		return
	var job: Dictionary = _jobs[id]
	_jobs.erase(id)
	if not job["final"]:
		_partial_busy = false
		if job["uid"] == _live_uid and text.strip_edges() != "":
			conversation.set_line(job["uid"], "You", text, true)
			_show_conversation()
		if _partial_more and _live_uid >= 0:
			_start_partial()
		return
	if text.strip_edges() == "":
		_not_heard(job, "Didn't catch that. Try again.")
		return
	_add_message(text.strip_edges(), job)


## A clip that gave no words: nothing goes to the assistant (sending the audio for it to transcribe is slow and a bad
## flow, the user's call); the viewer's line on the card says why, so they can try again.
func _not_heard(job: Dictionary, why: String) -> void:
	conversation.set_line(int(job["uid"]), "You", "(%s)" % why)
	_show_conversation()
	print("Assistant: a %.1f s clip gave no words; not sent (%s)" % [float(job["seconds"]), why])


func _add_message(text: Variant, job: Dictionary) -> void:
	var id := _next_message
	_next_message += 1
	var ctx: Dictionary = job["ctx"]
	var msg := {"id": id, "text": text, "heard_at": Time.get_datetime_string_from_system(false, false),
			"seconds": snappedf(float(job["seconds"]), 0.01), "context": ctx, "block": format_block(text, ctx, id)}
	if text == null:
		msg["audio"] = "/voice/%d.wav" % id
	_clips[id] = job["wav"]
	while _clips.size() > CLIPS_KEEP:
		_clips.erase(_clips.keys().min())
	_messages.append(msg)
	if _messages.size() > MESSAGES_KEEP:
		_messages = _messages.slice(_messages.size() - MESSAGES_KEEP)
	var uid: int = job["uid"]
	_message_uid[id] = uid
	conversation.set_line(uid, "You", text if text != null else "(sent as audio, %.0f s)" % float(job["seconds"]))
	# The viewer waits while the assistant works: dots under their words straight away, or a plain note when no
	# assistant is listening (the user's ask: nothing should look like silence).
	if _thinking_uid >= 0:
		conversation.set_line(_thinking_uid, "Assistant", null)
	if _assistant_listening():
		_thinking_uid = id
		conversation.set_line(id, "Assistant", "", true)
	else:
		_thinking_uid = -1
		conversation.set_line(-1, "Assistant", "(no assistant is listening right now)")
	_show_conversation()
	_publish("viewer_message", msg)
	print("Assistant: the viewer spoke (%.1f s)%s" % [float(job["seconds"]), "" if text != null
			else "; no speech to text here: sent as audio"])


## A paired assistant follows the events or waits for a message now, or asked something in the last minute.
func _assistant_listening() -> bool:
	return _connected or _conns.any(func(c: Dictionary) -> bool:
			return c["client_id"] != "" and (c["mode"] == "sse" or c["mode"] == "wait"))


func _messages_after(since: int) -> Array:
	return _messages.filter(func(m: Dictionary) -> bool: return int(m["id"]) > since)


func _show_conversation() -> void:
	var card := _card_node()
	if card == null:
		return
	if conversation.lines.is_empty():
		if card.visible and str(card.id) == AssistantConversation.ID:
			card.dismiss("cleared")
		return
	card.show_card({"id": AssistantConversation.ID, "title": AssistantConversation.TITLE, "text": conversation.text(),
			"seconds": AssistantConversation.SECONDS})


## POST /answer {text, title?, seconds?, heard?, message_id?}: under the conversation when the viewer spoke in the
## last 10 minutes and no title is given, else on a card of its own.
func answer(params: Dictionary) -> Dictionary:
	var text := str(params.get("text", "")).strip_edges()
	if text == "":
		return {"ok": false, "error": "text is required", "status": 400}
	var heard := str(params.get("heard", "")).strip_edges()
	var mid := _int(params.get("message_id"), -1)
	if heard != "" and mid >= 0:
		for m: Dictionary in _messages:
			if int(m["id"]) == mid:  # a correction of what was heard
				m["text"] = heard
				m["block"] = format_block(heard, m["context"], mid)
				var uid: int = _message_uid.get(mid, -1)
				conversation.set_line(uid if conversation.has_line(uid) else -1, "You", heard)
	var title := str(params.get("title", "")).strip_edges()
	var card := _card_node()
	if card == null:
		return {"ok": false, "error": "the card is not available", "status": 503}
	# working=1: a note while the assistant works ("Looking that up"); the dots stay after it, and the next answer
	# replaces both.
	var working := str(params.get("working", "")).to_lower() in ["1", "true", "yes"]
	if title == "" and conversation.recent():
		var t := text.left(AssistantCommands.CARD_TEXT_MAX)
		if _thinking_uid >= 0 and conversation.has_line(_thinking_uid):
			conversation.set_line(_thinking_uid, "Assistant", t, working)
			if not working:
				_thinking_uid = -1
		elif working:
			_thinking_uid = _next_message
			_next_message += 1
			conversation.set_line(_thinking_uid, "Assistant", t, true)
		else:
			conversation.set_line(-1, "Assistant", t)
		_show_conversation()
		return {"ok": true, "result": {"shown": "conversation"}}
	var seconds := float(params.get("seconds", CARD_SECONDS)) if str(params.get("seconds", "")).is_valid_float() \
			else CARD_SECONDS
	var id: String = card.show_card({"text": text.left(AssistantCommands.CARD_TEXT_MAX),
			"title": (title if title != "" else "Assistant").left(48), "seconds": seconds})
	return {"ok": true, "result": {"shown": "card", "id": id}}


## Where the film was when the viewer spoke: file, position, chapter, the last subtitle lines.
func _context() -> Dictionary:
	var main := AssistantCommands._main()
	if main == null or not ("player" in main):
		return {"note": "the player is not ready"}
	var s := AssistantCommands.state(main, control_allowed())
	var ctx := {}
	for k in ["path", "title", "playing", "position", "duration", "mode", "environment", "chapter"]:
		if s.has(k):
			ctx[k] = s[k]
	ctx["file"] = _file_name(str(s.get("path", "")))
	var r: Dictionary = await commands._subtitle_lines(8)
	if r.get("ok", false) and r.get("result") is Dictionary:
		ctx["subtitles"] = r["result"].get("lines", [])
	return ctx


static func format_block(text: Variant, ctx: Dictionary, id := 0) -> String:
	var out: PackedStringArray = ["Viewer said: %s" % (("\"%s\"" % text) if text != null
			else "(no text: the headset has no speech to text; the audio is at /voice/%d.wav)" % id)]
	if str(ctx.get("file", "")) != "" or str(ctx.get("title", "")) != "":
		var title := str(ctx.get("title", ""))
		out.append("Watching: %s%s" % [ctx.get("file", ""), (" (\"%s\")" % title) if title != "" and title
				!= str(ctx.get("file", "")) else ""])
		out.append("At %s of %s (%s)" % [_clock(float(ctx.get("position", 0.0))),
				_clock(float(ctx.get("duration", 0.0))), "playing" if ctx.get("playing", false) else "paused"])
		var ch: Dictionary = ctx.get("chapter", {}) if ctx.get("chapter") is Dictionary else {}
		if int(ch.get("n", 0)) > 0:
			out.append("Chapter %d of %d: %s" % [int(ch["n"]), int(ch.get("count", 0)), ch.get("title", "")])
		var subs: Array = ctx.get("subtitles", []) if ctx.get("subtitles") is Array else []
		if not subs.is_empty():
			out.append("Last subtitle lines:")
			for x: Dictionary in subs:
				out.append("  [%s] %s" % [_clock(float(x.get("start", 0.0))), str(x.get("text", "")).replace("\n",
						" / ")])
	elif ctx.has("note"):
		out.append("(%s)" % ctx["note"])
	elif str(ctx.get("path", "")) == "":
		out.append("Nothing is open.")
	out.append("Answer the viewer with POST /answer text=... (shown on the card under their words).")
	return "\n".join(out)
