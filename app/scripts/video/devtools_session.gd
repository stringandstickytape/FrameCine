extends RefCounted

## A lasting DevTools connection to the browser's page (docs/window-source.md, "Voice into a field"): one WebSocket to
## the page target that browser_devtools.gd found (its webSocketDebuggerUrl, on 127.0.0.1 only), kept open while the
## browser is on the big screen, so asking the page something costs one round trip, not a new connection.
##
## On opening it sends Page.enable (Page.frameNavigated tells a page change) and Target.setAutoAttach with flatten, so
## the page's cross-origin iframes (a login box from another site: its own process, which the page's Runtime can't see
## into) attach as sessions on this same socket: frames lists them, and request() takes a session id to talk to one.
##
##   var s := DevtoolsSession.new()
##   s.open("ws://127.0.0.1:N/devtools/page/ID")            # "" or why not
##   var r: Dictionary = await s.request(tree, "Runtime.evaluate", {...}, session_id := "")   # {result} or {error}
##   s.pump()            # every frame while nobody awaits: events (navigated, frames)
##   s.close()
## Nothing here logs what goes over the socket: a page's fields and what is typed into them stay in the headset.

signal navigated
signal closed

const TIMEOUT_MSEC := 1500

var ws_url := ""
var peer: WebSocketPeer
## Main-frame navigations seen (Page.frameNavigated without a parent frame, on the page's own session).
var navigations := 0
## The attached iframe targets: session id -> {target_id, url, type}.
var frames := {}
## Every event's method, for the tests (the last 64; never their contents).
var event_methods: Array[String] = []
var _next_id := 1
var _answers := {}
var _setup_sent := false
var _was_open := false


## Connects (no waiting: request() and pump() finish the handshake). "" or the reason.
func open(url: String) -> String:
	close()
	if not url.begins_with("ws://127.0.0.1:"):
		return "no DevTools socket for the page"
	ws_url = url
	peer = WebSocketPeer.new()
	# A page's answer (a big evaluate) can be larger than the default 64 KiB.
	peer.inbound_buffer_size = 1 << 20
	if peer.connect_to_url(url) != OK:
		peer = null
		return "could not connect to the page"
	return ""


func is_open() -> bool:
	return peer != null and peer.get_ready_state() == WebSocketPeer.STATE_OPEN


func is_connecting() -> bool:
	return peer != null and peer.get_ready_state() == WebSocketPeer.STATE_CONNECTING


func close() -> void:
	if peer != null:
		peer.close()
	peer = null
	ws_url = ""
	frames.clear()
	_answers.clear()
	_setup_sent = false
	if _was_open:
		_was_open = false
		closed.emit()


## Reads what has arrived: answers for request(), events. Call it every frame.
func pump() -> void:
	if peer == null:
		return
	peer.poll()
	var state := peer.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN and not _setup_sent:
		_setup_sent = true
		_was_open = true
		_send("Page.enable", {}, "")
		_send("Target.setAutoAttach", {"autoAttach": true, "waitForDebuggerOnStart": false, "flatten": true}, "")
	while peer != null and peer.get_available_packet_count() > 0:
		var msg: Variant = JSON.parse_string(peer.get_packet().get_string_from_utf8())
		if not (msg is Dictionary):
			continue
		var m: Dictionary = msg
		if m.has("id"):
			_answers[int(m["id"])] = m
		elif m.has("method"):
			_on_event(str(m["method"]), m.get("params", {}) if m.get("params") is Dictionary else {},
					str(m.get("sessionId", "")))
	if peer != null and state == WebSocketPeer.STATE_CLOSED:
		peer = null
		frames.clear()
		_setup_sent = false
		if _was_open:
			_was_open = false
			closed.emit()


func _on_event(method: String, params: Dictionary, session: String) -> void:
	event_methods.append(method)
	if event_methods.size() > 64:
		event_methods.pop_front()
	match method:
		"Target.attachedToTarget":
			var info: Dictionary = params.get("targetInfo", {}) if params.get("targetInfo") is Dictionary else {}
			var sid := str(params.get("sessionId", ""))
			if sid != "":
				frames[sid] = {"target_id": str(info.get("targetId", "")), "url": str(info.get("url", "")),
						"type": str(info.get("type", ""))}
				# Its own cross-origin iframes too.
				_send("Target.setAutoAttach", {"autoAttach": true, "waitForDebuggerOnStart": false, "flatten": true},
						sid)
		"Target.detachedFromTarget":
			frames.erase(str(params.get("sessionId", "")))
		"Page.frameNavigated":
			var frame: Dictionary = params.get("frame", {}) if params.get("frame") is Dictionary else {}
			if session == "" and str(frame.get("parentId", "")) == "":
				navigations += 1
				navigated.emit()


func _send(method: String, params: Dictionary, session: String) -> int:
	var id := _next_id
	_next_id += 1
	var msg := {"id": id, "method": method, "params": params}
	if session != "":
		msg["sessionId"] = session
	peer.send_text(JSON.stringify(msg))
	return id


## Sends one command and waits for its answer: {result} or {error} (no socket, no answer within the time, or the
## browser's own error message).
func request(tree: SceneTree, method: String, params := {}, session := "", timeout_msec := TIMEOUT_MSEC) -> Dictionary:
	var end := Time.get_ticks_msec() + timeout_msec
	while is_connecting():
		if Time.get_ticks_msec() > end:
			return {"error": "the page did not answer"}
		pump()
		if is_connecting():
			await tree.process_frame
	pump()
	if not is_open():
		return {"error": "no DevTools connection to the page"}
	var id := _send(method, params, session)
	while true:
		if _answers.has(id):
			var m: Dictionary = _answers[id]
			_answers.erase(id)
			if m.has("error"):
				var e: Variant = m["error"]
				return {"error": str(e.get("message", "refused")) if e is Dictionary else str(e)}
			return {"result": m.get("result", {})}
		if peer == null or Time.get_ticks_msec() > end:
			return {"error": "the page did not answer"}
		await tree.process_frame
		pump()
	return {"error": "the page did not answer"}


## Runtime.evaluate of an expression, its value by value: {value} or {error} (an exception in the page included).
func evaluate(tree: SceneTree, expression: String, session := "") -> Dictionary:
	var r := await request(tree, "Runtime.evaluate", {"expression": expression, "returnByValue": true,
			"awaitPromise": false, "userGesture": false}, session)
	if r.has("error"):
		return r
	var res: Dictionary = r["result"] if r["result"] is Dictionary else {}
	if res.has("exceptionDetails"):
		return {"error": "the page's script failed"}
	var obj: Variant = res.get("result", {})
	return {"value": (obj as Dictionary).get("value") if obj is Dictionary else null}
