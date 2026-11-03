extends SceneTree

## The assistant service (scripts/assistant/assistant_service.gd, docs/assistant.md) on 127.0.0.1, as a fresh
## assistant meets it (over plain HTTP here; tools/assistant/test_assistant.py tests HTTPS, the pin and curl): not listening until the window opens; the guide public only in the window; pairing with
## a right and wrong codes, three strikes, one attempt at a time, the rate limit; the token on everything else; the
## pin matching the certificate; the whitelist and the permission
## refusals; the event stream and /messages/wait delivering a viewer message (without speech to text: no text and an
## audio link; with a stand-in backend: live partials, then the text); /answer under the viewer's words on the card;
## a restart keeping the pairing; Forget. Runs the real main scene; settings are read-only and the files are test
## files. The address check is unit-tested (a test can only connect from 127.0.0.1).
## godot --headless --xr-mode off --path app --script res://tests/test_assistant.gd

const Assistant := preload("res://scripts/assistant/assistant.gd")
const AssistantTls := preload("res://scripts/assistant/assistant_tls.gd")
const PushToTalk := preload("res://scripts/dev/push_to_talk.gd")
const RemoteServer := preload("res://scripts/remote/remote_server.gd")
const Transcriber := preload("res://scripts/voice/transcriber.gd")
const DevCommands := preload("res://scripts/dev/dev_commands.gd")
const AssistantSwitches := preload("res://scripts/assistant/assistant_switches.gd")
const CLIENTS := "user://test_assistant_clients.cfg"
const KEY := "user://test_assistant_tls.key"
const CERT := "user://test_assistant_tls.crt"

var _failures := 0
var _checks := 0
var main: Node3D
var service: Node
var port := 0


## One connection, as a client sees it. Plain HTTP (service.plain_http): the engine's TLS client can't read the
## service's TLS 1.3 replies; HTTPS, the pin and curl are tested by tools/assistant/test_assistant.py.
class Conn:
	var tcp := StreamPeerTCP.new()
	var buf := PackedByteArray()

	func open(tree: SceneTree, p: int) -> bool:
		if tcp.connect_to_host("127.0.0.1", p) != OK:
			return false
		var end := Time.get_ticks_msec() + 5000
		while Time.get_ticks_msec() < end:
			tcp.poll()
			if tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED:
				break
			await tree.process_frame
		return tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED

	func send(text: String) -> void:
		tcp.put_data(text.to_utf8_buffer())

	## Reads what has arrived. False once closed.
	func pump() -> bool:
		tcp.poll()
		var n := tcp.get_available_bytes() if tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED else 0
		if n > 0:
			buf.append_array(tcp.get_partial_data(n)[1])
		return tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED

	## Reads until the server closes (or the timeout): {status, head, body, json}.
	func response(tree: SceneTree, timeout := 10.0) -> Dictionary:
		var end := Time.get_ticks_msec() + int(timeout * 1000.0)
		while Time.get_ticks_msec() < end and pump():
			await tree.process_frame
		pump()
		var text := buf.get_string_from_utf8()
		var head := text.get_slice("\r\n\r\n", 0)
		var status := head.get_slice(" ", 1).to_int() if head.begins_with("HTTP/1.1") else 0
		var body := text.substr(head.length() + 4) if text.contains("\r\n\r\n") else ""
		var json := JSON.new()
		var data: Variant = json.data if json.parse(body) == OK else null
		return {"status": status, "head": head, "body": body, "json": data if data is Dictionary else {}}

	## Reads until `needle` arrives on an open stream.
	func until(tree: SceneTree, needle: String, timeout := 5.0) -> bool:
		var end := Time.get_ticks_msec() + int(timeout * 1000.0)
		while Time.get_ticks_msec() < end:
			pump()
			if buf.get_string_from_utf8().contains(needle):
				return true
			await tree.process_frame
		return false

	func close() -> void:
		tcp.disconnect_from_host()


## A stand-in speech-to-text backend: says "hello there" for a final, "hello" for a partial.
class FakeBackend:
	extends RefCounted
	var taken := 0

	func ready() -> bool:
		return true

	func describe() -> String:
		return "a stand-in"

	func transcribe(id: int, _pcm: PackedByteArray, final: bool) -> bool:
		taken += 1
		Transcriber.emit_done(id, "hello there" if final else "hello", final)
		return true


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	current_scene = main  # the shared command handlers find the app as the current scene
	_run.call_deferred()


func _start_service() -> Node:
	var s := Assistant.start(main, false)
	s.bind_address = "127.0.0.1"
	s.clients_path = CLIENTS
	s.tls_key_path = KEY
	s.tls_cert_path = CERT
	s.start_whisper = false
	s.plain_http = true
	s.live_partials = true
	await _frames(2)
	return s


func _run() -> void:
	await _frames(5)
	for f in [CLIENTS, KEY, CERT]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	var probe := TCPServer.new()
	for p in range(47911, 47960):
		if probe.listen(p, "127.0.0.1") == OK:
			port = p
			probe.stop()
			break
	_check("a test port", port > 0)
	main.settings.set_value("assistant", "port", port)
	for level: String in AssistantSwitches.SWITCHES:
		main.settings.set_value("assistant", AssistantSwitches.SWITCHES[level]["key"], false)

	# --- The address check (a connection from anything else is closed before TLS). ---
	for a in ["127.0.0.1", "192.168.1.50", "10.1.2.3", "172.16.0.1", "169.254.1.1", "::1", "fd12::1", "fe80::1",
			"::ffff:192.168.1.5"]:
		_check("%s is private" % a, RemoteServer.is_private(a))
	for a in ["8.8.8.8", "172.32.0.1", "192.169.0.1", "100.64.0.1", "2001:db8::1", "::ffff:8.8.8.8", "", "x"]:
		_check("%s is refused" % a, not RemoteServer.is_private(a))

	service = await _start_service()
	_check("on, nobody paired, no window: not listening", service.is_inside_tree() and not service.is_listening())
	service.open_window()
	await _until(func() -> bool: return service.is_listening(), 90.0)
	_check("the window opens the port (the certificate made once: %s)" % service.problem, service.is_listening())
	_check("the window is 60 minutes", absf(service.window_left() - 3600.0) < 5.0)
	if OS.get_name() == "Linux":
		_check("the key is owner-only", FileAccess.get_unix_permissions(KEY) & 63 == 0)

	# --- The guide is public in the window; nothing else is. ---
	var r: Dictionary = await _http("GET", "/")
	_check("GET / in the window (%d)" % r["status"], r["status"] == 200 and "pairing is open" in r["body"]
			and "Listening to the viewer" in r["body"] and "https://127.0.0.1:%d" % port in r["body"]
			and not "<<" in r["body"])
	_check("the guide has the commands and events", "| `volume` | control |" in r["body"]
			and "`viewer_message`" in r["body"] and "`clock`" in r["body"])
	r = await _http("GET", "/openapi.json")
	_check("openapi.json", r["status"] == 200 and r["json"].get("openapi") == "3.1.0"
			and r["json"]["paths"].has("/pair/start"))
	r = await _http("GET", "/tools/mcp_server.py")
	_check("the MCP adapter is served", r["status"] == 200 and "class McpServer" in r["body"])
	r = await _http("GET", "/tools/assistant.py")
	_check("the command line is served", r["status"] == 200 and "def spki_pin" in r["body"])
	r = await _http("GET", "/tools/../settings.cfg")
	_check("nothing else under /tools", r["status"] == 401 or r["status"] == 404)
	for path in ["/status", "/state", "/events", "/messages/wait", "/describe", "/snapshot.png", "/snapshot_clip.png",
			"/perf"]:
		r = await _http("GET", path)
		_check("%s needs a token (%d)" % [path, r["status"]], r["status"] == 401)
	r = await _http("GET", "/status", "", {"Authorization": "Bearer " + "ab".repeat(32)})
	_check("a wrong token is refused", r["status"] == 401 and "not paired" in str(r["json"].get("error", "")))
	r = await _http("POST", "/command", "cmd=pause")
	_check("a command needs a token", r["status"] == 401)

	# --- Pairing: one attempt at a time, three strikes, the rate limit. ---
	r = await _http("POST", "/pair/start", "client=Test+Agent")
	var pid := str(r["json"].get("result", {}).get("pair_id", ""))
	_check("pair/start (%s)" % r["body"].left(80), r["status"] == 200 and pid.length() == 16)
	var p: Dictionary = service.pairing()
	_check("the headset shows a code and the name", str(p.get("code", "")).length() == 6
			and p.get("client") == "Test Agent")
	r = await _http("POST", "/pair/start", "client=Another")
	_check("one attempt at a time (%d)" % r["status"], r["status"] == 409)
	var code: String = p["code"]
	var wrong := "%06d" % ((code.to_int() + 1) % 1000000)
	for left in [2, 1, 0]:
		r = await _http("POST", "/pair", "pair_id=%s&code=%s" % [pid, wrong])
		_check("wrong code: %d left (%d)" % [left, r["status"]], r["status"] == 403
				and int(r["json"].get("tries_left", -1)) == left)
	_check("three strikes end the attempt", service.pairing().is_empty())
	r = await _http("POST", "/pair", "pair_id=%s&code=%s" % [pid, code])
	_check("the right code is too late now (%d)" % r["status"], r["status"] == 409)
	r = await _http("POST", "/pair/start", "client=Test+Agent")
	_check("pairing starts are rate-limited (%d)" % r["status"], r["status"] == 429)
	await create_timer(3.2).timeout
	r = await _http("POST", "/pair/start", JSON.stringify({"client": "Test Agent"}), {"Content-Type":
			"application/json"})
	pid = str(r["json"].get("result", {}).get("pair_id", ""))
	_check("a new attempt (JSON body)", r["status"] == 200 and pid != "")
	code = service.pairing()["code"]
	r = await _http("POST", "/pair", "pair_id=%s&code=%s %s" % [pid, code.left(3), code.right(3)])
	var res: Dictionary = r["json"].get("result", {})
	var token := str(res.get("token", ""))
	_check("paired (%d)" % r["status"], r["status"] == 200 and token.length() == 64 and res.get("expires") == "never")
	var tls := AssistantTls.new()
	tls.key_path = KEY
	tls.cert_path = CERT
	tls.load_files()
	_check("the pin is the certificate's public key (%s)" % res.get("pin"), str(res.get("pin")) == tls.pin
			and tls.pin.begins_with("sha256//") and str(res.get("cert_sha256")) == tls.cert_sha256)
	var file := FileAccess.get_file_as_string(CLIENTS)
	_check("only the token's hash is kept", not token in file and token.sha256_text() in file)
	if OS.get_name() == "Linux":
		_check("the clients file is owner-only", FileAccess.get_unix_permissions(CLIENTS) & 63 == 0)
	_check("the panel lists it", service.paired().size() == 1 and service.paired()[0]["name"] == "Test Agent")
	var auth := {"Authorization": "Bearer " + token}

	# --- With the token. ---
	r = await _http("GET", "/status", "", auth)
	_check("status with the token", r["status"] == 200 and r["json"]["result"]["you"]["name"] == "Test Agent"
			and r["json"]["result"]["transcriber"] == "none")
	r = await _http("GET", "/status", "", {"Authorization": "Bearer " + token, "Origin": "https://example.com"})
	_check("a web page is refused", r["status"] == 403)
	main.open_path("stub://flat_sbs")
	await _frames(5)
	r = await _http("GET", "/state", "", auth)
	_check("state (%s)" % r["json"].get("result", {}).get("path", ""), r["status"] == 200
			and r["json"]["result"]["path"] == "stub://flat_sbs" and r["json"]["result"]["control"] == false)
	# An agent on the headset: no code, no window; the token in its link file, which works; forgetting deletes it.
	var AgentTerminal: GDScript = load("res://scripts/agents/agent_terminal.gd")
	var agent_home := OS.get_user_data_dir().path_join("test_link_home")
	AgentTerminal.home_override = agent_home
	var linked: bool = await service.pair_local("claude")
	var agent_token: String = AgentTerminal.link_token("claude")
	_check("a local agent is paired with no code (%s)" % str(service.paired()), linked and agent_token.length() == 64
			and service.paired().any(func(x: Dictionary) -> bool: return x["name"] == "Claude Code on this headset"))
	var same: bool = await service.pair_local("claude")
	_check("a working link is kept", same and AgentTerminal.link_token("claude") == agent_token
			and service.paired().filter(func(x: Dictionary) -> bool: return x["name"].ends_with("on this headset")).size()
			== 1)
	r = await _http("GET", "/status", "", {"Authorization": "Bearer " + agent_token})
	_check("its token works over the loopback (%d)" % r["status"], r["status"] == 200)
	var agent_id: String = str(service.paired().filter(func(x: Dictionary) -> bool:
			return x["name"] == "Claude Code on this headset")[0]["id"])
	service.forget(agent_id)
	r = await _http("GET", "/status", "", {"Authorization": "Bearer " + agent_token})
	_check("forgotten: the token is dead and the file gone (%d)" % r["status"], r["status"] == 401
			and not FileAccess.file_exists(AgentTerminal.link_path("claude")))
	AgentTerminal.home_override = ""
	DirAccess.remove_absolute(agent_home.path_join("Claude"))
	DirAccess.remove_absolute(agent_home)
	r = await _http("GET", "/perf", "", auth)
	var pf: Dictionary = r["json"].get("result", {}) if r["json"] is Dictionary else {}
	_check("perf: the budget, the film, the windows and what to make of them (%d, %s)" % [r["status"],
			str(pf.get("notes", "")).left(160)], r["status"] == 200 and float(pf.get("budget_ms", 0)) > 0.0
			and is_equal_approx(float(pf["budget_ms"]), snappedf(1000.0 / float(pf["refresh_hz"]), 0.01))
			and pf.has("windows") and pf.has("dropped_last_minute") and pf.get("film_playing") == true
			and str(pf.get("notes", "")).contains("test pattern"))
	r = await _http("GET", "/snapshot.png?from=seat&width=320", "", auth)
	if DisplayServer.get_name() == "headless":
		_check("snapshot: no renderer here, said with 503 (%d)" % r["status"], r["status"] == 503
				and "renderer" in str(r["json"].get("error", "")))
	else:
		_check("snapshot: a PNG (%d, %s)" % [r["status"], r["head"].get_slice("\r\n", 0)], r["status"] == 200
				and "image/png" in r["head"])
	r = await _http("GET", "/snapshot.png?from=sideways", "", auth)
	_check("snapshot: from is viewer or seat (%d)" % r["status"], r["status"] == 400)
	r = await _http("GET", "/snapshot.png?from=seat&seat=Nowhere%20near", "", auth)
	_check("snapshot: a seat the room has (%d, %s)" % [r["status"], r["body"].left(80)], r["status"] == 400
			and str(r["body"]).contains("no seat Nowhere near"))
	r = await _http("GET", "/snapshot_clip.png?seconds=1&fps=4&width=160", "", auth)
	if DisplayServer.get_name() == "headless":
		_check("clip: no renderer here, said with 503 (%d)" % r["status"], r["status"] == 503)
	else:
		_check("clip: a sheet PNG (%d)" % r["status"], r["status"] == 200 and "X-Frames: 4" in r["head"])
	r = await _http("GET", "/snapshot_clip.png?format=gif", "", auth)
	_check("clip: format is sheet or apng (%d)" % r["status"], r["status"] == 400)
	r = await _http("GET", "/", "", auth)
	_check("the guide says who you are and what plays", "you are paired as Test Agent" in r["body"]
			and "flat_sbs" in r["body"])
	r = await _http("GET", "/describe", "", auth)
	_check("describe", r["status"] == 200 and (r["json"]["result"]["commands"] as Array).size() > 20
			and (r["json"]["result"]["events"] as Array).size() > 5)
	for bad in ["cmd=run&code=print(1)", "cmd=set_prop&path=Player&property=x&value=1", "cmd=get&setting=x",
			"cmd=reload", "cmd=screenshot", "cmd=open_url&url=https://example.com"]:
		r = await _http("POST", "/command", bad, auth)
		_check("%s refused (%d)" % [bad.get_slice("&", 0), r["status"]], r["status"] == 409
				and r["json"].get("refused") == true)
	await _registry_checks(auth)
	r = await _http("POST", "/command", "cmd=volume&level=0.5", auth)
	_check("control not allowed: volume refused (%d)" % r["status"], r["status"] == 409
			and "has not allowed" in str(r["json"].get("error", ""))
			and r["json"].get("switch") == "Let the assistant control playback")
	r = await _http("POST", "/command", "cmd=room_apply&room={\"schema\":1}", auth)
	_check("room changes not allowed: refused", r["status"] == 409)
	r = await _http("POST", "/card", "text=Hello+from+the+test&title=Test", auth)
	_check("a card is always allowed", r["status"] == 200 and main.ui.card.visible)
	var sse := Conn.new()
	await sse.open(self, port)
	sse.send("GET /events?types=permissions,viewer_message,voice_state HTTP/1.1\r\nHost: 127.0.0.1:%d\r\n" % port
			+ "Authorization: Bearer %s\r\n\r\n" % token)
	_check("the event stream starts with the status", await sse.until(self, "event: status"))
	await _until(func() -> bool: return service.is_link_connected())
	_check("connected while the stream is open", service.is_link_connected())
	service.set_allow_control(true)
	_check("permissions event", await sse.until(self, "event: permissions"))
	r = await _http("POST", "/command", "cmd=volume&level=0.5", auth)
	_check("control allowed: volume (form fields)", r["status"] == 200 and is_equal_approx(main.volume, 0.5))
	r = await _http("POST", "/command", JSON.stringify({"cmd": "volume", "args": {"level": 0.3}}), auth)
	_check("volume 0.3 (JSON)", r["status"] == 200 and is_equal_approx(main.volume, 0.3))
	r = await _http("POST", "/command", "cmd=volume&level=0.4&bogus=1", auth)
	_check("an unknown argument (%d)" % r["status"], r["status"] == 422)
	r = await _http("POST", "/command", "cmd=open&path=smb://unknown-host/share/film.mkv", auth)
	_check("an SMB host the viewer never saved is refused", r["status"] == 409)

	# --- The viewer speaks with no speech to text: nothing goes to the assistant, the card says why. ---
	var pcm := PackedByteArray()
	pcm.resize(16000 * 2)
	Transcriber.backend = null
	service.send_event("voice_state", {"recording": true})
	service.send_event("voice_state", {"recording": false})
	service.send_event("voice_clip", {"wav_b64": Marshalls.raw_to_base64(PushToTalk.wav_bytes(pcm, 16000)),
			"seconds": 1.0})
	await _until(func() -> bool: return "isn't working" in service.conversation.text())
	_check("no speech to text: nothing sent, the card says so", "isn't working" in service.conversation.text()
			and service._messages.is_empty())

	# --- The viewer speaks (a stand-in transcriber). ---
	Transcriber.backend = FakeBackend.new()
	var waiter := Conn.new()
	await waiter.open(self, port)
	waiter.send("GET /messages/wait?timeout=30 HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer %s\r\n\r\n" % token)
	await _frames(5)
	service.send_event("voice_state", {"recording": true})
	_check("a live line while the button is held", main.ui.card.visible
			and service.conversation.text().ends_with("(listening) ..."))
	service.send_event("voice_state", {"recording": false})
	service.send_event("voice_clip", {"wav_b64": Marshalls.raw_to_base64(PushToTalk.wav_bytes(pcm, 16000)),
			"seconds": 1.0})
	_check("the stream delivers the message", await sse.until(self, "event: viewer_message"))
	var w: Dictionary = await waiter.response(self)
	var msgs: Array = w["json"].get("result", [])
	var mid: int = int(msgs[0]["id"]) if msgs.size() == 1 else -1
	_check("the wait returns with it (%d)" % w["status"], w["status"] == 200 and msgs.size() == 1
			and msgs[0]["text"] == "hello there" and not msgs[0].has("audio"))
	_check("message ids start from the clock, so they grow across restarts (%d)" % mid,
			mid > int(Time.get_unix_time_from_system() * 1000.0) - 3600000)
	_check("with the film's context", msgs.size() == 1 and msgs[0]["context"].get("file") == "flat_sbs"
			and "Watching: flat_sbs" in str(msgs[0]["block"]))
	r = await _http("GET", "/voice/%d.wav" % mid, "", auth)
	_check("the clip", r["status"] == 200 and "audio/wav" in r["head"])
	r = await _http("POST", "/answer", "text=It+is+the+keeper.&message_id=%d&heard=who+is+that" % mid, auth)
	_check("the answer under the viewer's words (%s)" % service.conversation.text().right(80), r["status"] == 200
			and service.conversation.text().ends_with("You: who is that\n\nAssistant: It is the keeper.")
			and main.ui.card.visible)

	# --- With a speech-to-text backend: live partials, then the text. ---
	var fake := FakeBackend.new()
	Transcriber.backend = fake
	r = await _http("GET", "/status", "", auth)
	_check("status names the transcriber", r["json"]["result"]["transcriber"] == "a stand-in")
	service.send_event("voice_state", {"recording": true})
	service.send_event("voice_partial", {"pcm_b64": Marshalls.raw_to_base64(pcm), "seq": 0})
	await _frames(3)
	_check("a partial shows live (%s)" % service.conversation.text(), service.conversation.text()
			.ends_with("You: hello ..."))
	service.send_event("voice_state", {"recording": false})
	service.send_event("voice_clip", {"wav_b64": Marshalls.raw_to_base64(PushToTalk.wav_bytes(pcm, 16000)),
			"seconds": 1.0})
	await _until(func() -> bool: return "You: hello there" in service.conversation.text())
	_check("the final text replaces it", "You: hello there

Assistant:  ..." in service.conversation.text()
			or service.conversation.text().ends_with("You: hello there"))
	_check("dots under it while an assistant listens (%s)" % service.conversation.text().right(60),
			not service._assistant_listening() or service.conversation.text().ends_with("Assistant:  ..."))
	r = await _http("POST", "/answer", "text=Looking+that+up&working=1", auth)
	_check("a working note keeps the dots", service.conversation.text().ends_with("Assistant: Looking that up ..."))
	r = await _http("POST", "/answer", "text=It+is+Tom.", auth)
	_check("the answer replaces note and dots", service.conversation.text().ends_with("You: hello there

Assistant: It is Tom."))
	r = await _http("GET", "/messages/wait?since=%d&timeout=5" % mid, "", auth)
	_check("the message has its text", r["json"].get("result", []).size() == 1
			and r["json"]["result"][0]["text"] == "hello there")
	Transcriber.backend = null
	service.send_event("voice_state", {"recording": true})
	service.send_event("voice_state", {"recording": false})
	await _frames(2)
	_check("a press too short for a clip leaves no line", not "(listening)" in service.conversation.text())
	sse.close()

	# --- The window closes: the guide says so; the paired assistant keeps working. ---
	service.close_window()
	r = await _http("GET", "/")
	_check("outside the window the guide says pairing is closed", r["status"] == 200
			and "pairing is closed" in r["body"] and "Let an assistant find me" in r["body"] and not "flat_sbs" in r["body"])
	r = await _http("POST", "/pair/start", "client=Late")
	_check("no pairing outside the window (%d)" % r["status"], r["status"] == 403)
	_check("still listening for the paired assistant", service.is_listening())

	# --- A restart keeps the pairing. ---
	Assistant.stop(main, false)
	await _frames(3)
	service = await _start_service()
	await _until(func() -> bool: return service.is_listening(), 10.0)
	r = await _http("GET", "/status", "", auth)
	_check("after a restart: listening, the token works (%d)" % r["status"], service.is_listening()
			and r["status"] == 200)

	# --- Forget: from the assistant, and from the panel. ---
	service.open_window()
	await create_timer(3.2).timeout
	r = await _http("POST", "/pair/start", "client=Second")
	pid = str(r["json"].get("result", {}).get("pair_id", ""))
	r = await _http("POST", "/pair", "pair_id=%s&code=%s" % [pid, service.pairing().get("code", "")])
	var token2 := str(r["json"].get("result", {}).get("token", ""))
	_check("a second assistant", token2.length() == 64 and service.paired().size() == 2)
	r = await _http("POST", "/forget", "", auth)
	_check("forget yourself", r["status"] == 200)
	r = await _http("GET", "/status", "", auth)
	_check("then the token is refused", r["status"] == 401)
	service.forget(service.paired()[0]["id"])
	r = await _http("GET", "/status", "", {"Authorization": "Bearer " + token2})
	_check("Forget in the panel revokes too", r["status"] == 401 and service.paired().is_empty())
	service.close_window()
	await _frames(3)
	_check("nobody paired, no window: the port closes", not service.is_listening())

	Assistant.stop(main, false)
	await _frames(2)
	_check("off", Assistant.instance() == null)
	_finish()


## The registry is the one list (dev_commands.gd `assistant` tags): untagged and code commands are refused, each
## switch gates its level, /describe's schemas hold for every command, the guide and the OpenAPI list them all, and no
## two scripts register one name.
func _registry_checks(auth: Dictionary) -> void:
	_check("no command is registered by two scripts (%s)" % [DevCommands.clashes()], DevCommands.clashes().is_empty())
	var ran := func(_a: Dictionary, ctx: DevCommands.Call) -> Variant: return {"ran": ctx.name, "client": ctx.client}
	DevCommands.register("core_test_untagged", ran, {"level": "control"})
	DevCommands.register("core_test_untagged", ran, {"level": "control"})
	_check("the same script registering again is no clash", DevCommands.clashes().is_empty())
	DevCommands.register("core_test_untagged", service.allowed, {"level": "control"})
	_check("another script registering the name is a clash", DevCommands.clashes().size() == 1
			and DevCommands.clashes()[0]["command"] == "core_test_untagged")
	DevCommands.register("core_test_untagged", ran, {"level": "control"})
	var r: Dictionary = await _http("POST", "/command", "cmd=core_test_untagged", auth)
	_check("an untagged command is refused (%d)" % r["status"], r["status"] == 409 and r["json"].get("refused") == true
			and "not available" in str(r["json"].get("error", "")))
	print("(two errors follow on purpose: a code command and an unknown level, each tagged)")
	DevCommands.register("core_test_code", ran, {"level": "code", "assistant": "read"})
	_check("a code command's tag is dropped", DevCommands.assistant_level("core_test_code") == ""
			and DevCommands.get_spec("core_test_code")["level"] == "code")
	r = await _http("POST", "/command", "cmd=core_test_code", auth)
	_check("a code command is refused (%d)" % r["status"], r["status"] == 409 and r["json"].get("refused") == true)
	DevCommands.register("core_test_odd", ran, {"assistant": "admin"})
	_check("an unknown level is dropped", DevCommands.assistant_level("core_test_odd") == "")
	for level: String in AssistantSwitches.SWITCHES:
		var cmd := "core_test_%s" % level
		DevCommands.register(cmd, ran, {"assistant": level, "level": "control", "description": "A test command."})
		var label: String = AssistantSwitches.SWITCHES[level]["label"]
		r = await _http("POST", "/command", "cmd=" + cmd, auth)
		_check("%s off: refused, naming the switch (%d)" % [level, r["status"]], r["status"] == 409
				and r["json"].get("switch") == label and label in str(r["json"].get("error", "")))
		service.set_allowed(level, true)
		r = await _http("POST", "/command", "cmd=" + cmd, auth)
		_check("%s on: runs, and knows who asked (%s)" % [level, r["json"]], r["status"] == 200
				and r["json"]["result"] == {"ran": cmd, "client": "Test Agent"})
		_check("%s on: /status says so" % level, service.status()["allowed"][level] == true)
		service.set_allowed(level, false)
	for level: String in ["read", "card"]:
		DevCommands.register("core_test_%s" % level, ran, {"assistant": level, "description": "A test command."})
		r = await _http("POST", "/command", "cmd=core_test_%s" % level, auth)
		_check("%s: always runs (%d)" % [level, r["status"]], r["status"] == 200)

	r = await _http("GET", "/describe", "", auth)
	var d: Dictionary = r["json"]["result"]
	var listed := {}
	for c: Dictionary in d["commands"]:
		listed[c["name"]] = c
		var why := _schema_problem(c)
		_check("describe: %s is well formed%s" % [c["name"], (": " + why) if why != "" else ""], why == "")
	var tagged: Array = DevCommands.assistant_names()
	_check("describe lists every tagged command (%d) and describe", tagged.all(func(n: String) -> bool:
			return listed.has(n)) and listed.has("describe") and listed.size() == tagged.size() + 1)
	_check("describe lists nothing untagged", not listed.has("core_test_untagged") and not listed.has("core_test_code")
			and not listed.has("run") and not listed.has("reload") and not listed.has("set_prop"))
	_check("describe gives each command its level", listed["core_test_files"]["level"] == "files"
			and listed["volume"]["level"] == "control" and listed["state"]["level"] == "read")
	var levels: Dictionary = d["levels"]
	var names: Array = levels.keys()
	var order: Array = []
	order.assign(DevCommands.ASSISTANT_LEVELS)
	names.sort()
	order.sort()
	_check("describe's levels: all seven, each with its switch and state (%s)" % [levels], names == order
			and levels["read"]["switch"] == null and levels["read"]["allowed"] == true
			and levels["apps"]["switch"] == "Let the assistant run apps" and levels["apps"]["allowed"] == false)
	r = await _http("GET", "/", "", auth)
	var missing: Array = tagged.filter(func(n: String) -> bool: return not ("| `%s` |" % n) in r["body"])
	_check("the guide lists every tagged command (missing: %s)" % [missing], missing.is_empty())
	_check("the guide lists the levels and their switches", "| files |" in r["body"]
			and "\"Let the assistant manage files\"" in r["body"])
	r = await _http("GET", "/openapi.json")
	var titles: Array = r["json"]["paths"]["/command"]["post"]["requestBody"]["content"]["application/json"][
			"schema"]["oneOf"].map(func(o: Dictionary) -> String: return o["title"])
	_check("the OpenAPI has every tagged command", tagged.all(func(n: String) -> bool: return n in titles))

	# The `commands` event: a second after the list last changed (a change undone within it is no change).
	for level: String in DevCommands.ASSISTANT_LEVELS:
		DevCommands.unregister("core_test_%s" % level)
	for n in ["core_test_untagged", "core_test_code", "core_test_odd"]:
		DevCommands.unregister(n)
	await _until(func() -> bool: return service._commands_check_at == 0.0, 4.0)
	var before: int = service._events.size()
	DevCommands.register("core_test_new", ran, {"assistant": "read", "description": "A test command."})
	await _until(func() -> bool: return service._events.slice(before).any(func(e: Dictionary) -> bool:
			return e["event"] == "commands"), 4.0)
	_check("a commands event when the list changes", service._events.slice(before).any(func(e: Dictionary) -> bool:
			return e["event"] == "commands"))
	DevCommands.unregister("core_test_new")
	# The deliberate clash above is the test's own.
	DevCommands._store()["clashes"].clear()


## Why a /describe entry is not well formed (its input_schema a valid JSON Schema object for its params), or "".
func _schema_problem(c: Dictionary) -> String:
	const TYPES := ["string", "integer", "number", "boolean", "array", "object"]
	if not (c.get("name") is String and c.get("description") is String and c.get("params") is Array):
		return "name, description or params"
	if str(c["description"]).strip_edges() == "":
		return "no description"
	if not (str(c.get("level", "")) in DevCommands.ASSISTANT_LEVELS):
		return "level %s" % c.get("level")
	var s: Variant = c.get("input_schema")
	if not (s is Dictionary) or s.get("type") != "object" or not (s.get("properties") is Dictionary) \
			or s.get("additionalProperties") != false:
		return "input_schema is not a closed object"
	var props: Dictionary = s["properties"]
	if props.size() != (c["params"] as Array).size():
		return "a property per param"
	for req: Variant in s.get("required", []):
		if not props.has(req):
			return "required %s is no property" % req
	for p: Dictionary in c["params"]:
		var ps: Variant = props.get(p["name"])
		if not (ps is Dictionary):
			return "%s: no schema" % p["name"]
		var parts: Array = ps.get("anyOf", [ps])
		for part: Dictionary in parts:
			if part.has("type") and not (part["type"] in TYPES):
				return "%s: type %s" % [p["name"], part["type"]]
		if ps.has("enum") and not (ps["enum"] is Array):
			return "%s: enum" % p["name"]
		if ps.has("default") and ps.has("type") and ps["default"] != null:
			var v: Variant = ps["default"]
			var fits := false
			match str(ps["type"]):
				"string": fits = v is String
				"integer": fits = v is int or (v is float and v == floorf(v))
				"number": fits = v is int or v is float
				"boolean": fits = v is bool
				"array": fits = v is Array
				"object": fits = v is Dictionary
			if not fits:
				return "%s: default %s is not a %s" % [p["name"], v, ps["type"]]
	return ""


func _finish() -> void:
	for f in [CLIENTS, KEY, CERT]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	print("test_assistant: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(1 if _failures > 0 else 0)


func _http(method: String, path: String, body := "", headers := {}) -> Dictionary:
	var c := Conn.new()
	if not await c.open(self, port):
		return {"status": 0, "head": "", "body": "", "json": {}}
	var req := "%s %s HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nConnection: close\r\n" % [method, path, port]
	for k: String in headers:
		req += "%s: %s\r\n" % [k, headers[k]]
	if body != "" and not headers.has("Content-Type"):
		req += "Content-Type: application/x-www-form-urlencoded\r\n"
	req += "Content-Length: %d\r\n\r\n" % body.to_utf8_buffer().size() + body
	c.send(req)
	return await c.response(self)


func _until(cond: Callable, timeout := 5.0) -> void:
	var end := Time.get_ticks_msec() + int(timeout * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await process_frame


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL " + what)
