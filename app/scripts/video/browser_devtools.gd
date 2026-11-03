extends RefCounted

## The Browser source's current page (docs/window-source.md, "The current page"): the browser the player launches
## gets Chromium's DevTools HTTP endpoint on a random free port of the loopback (--remote-debugging-port=N; Chromium
## binds it to 127.0.0.1 only), and GET http://127.0.0.1:N/json lists its targets, the page with its url and title.
## Why that is acceptable: the headset is a single-user device; the port is on the loopback only, never on the
## network; it is a new random port each launch; and it goes away with the browser. A flatpak Chromium shares the
## host's network namespace, so the port is the host's loopback. When the endpoint does not answer (a browser that was
## already running took the launch over and ignored the flag, or a build that refuses remote debugging on its default
## profile), the window's title is all there is (page_info's via = "window title").
##
##   free_port() -> int                      a free loopback port (0 if none)
##   flags(port) -> Array[String]            the browser's extra arguments
##   await read(tree, port) -> {targets} or {error}
##   page_of(targets, window_title) -> {url, title} or {}

const TIMEOUT_MSEC := 1500


static func free_port() -> int:
	var s := TCPServer.new()
	if s.listen(0, "127.0.0.1") != OK:
		return 0
	var port := s.get_local_port()
	s.stop()
	return port


static func flags(port: int) -> Array[String]:
	return ["--remote-debugging-port=%d" % port] if port > 0 else []


## GET /json on the loopback port: {targets: [{type, url, title, id}]} or {error}. Polls on the main loop (never
## blocks a frame for long).
static func read(tree: SceneTree, port: int) -> Dictionary:
	if port <= 0:
		return {"error": "no DevTools port"}
	var c := HTTPClient.new()
	if c.connect_to_host("127.0.0.1", port) != OK:
		return {"error": "could not connect"}
	var end := Time.get_ticks_msec() + TIMEOUT_MSEC
	while c.get_status() in [HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING]:
		if Time.get_ticks_msec() > end:
			return {"error": "no answer"}
		c.poll()
		await tree.process_frame
	if c.get_status() != HTTPClient.STATUS_CONNECTED:
		return {"error": "the DevTools port is closed"}
	c.request(HTTPClient.METHOD_GET, "/json", ["Host: 127.0.0.1:%d" % port, "Accept: application/json"])
	while c.get_status() == HTTPClient.STATUS_REQUESTING:
		if Time.get_ticks_msec() > end:
			return {"error": "no answer"}
		c.poll()
		await tree.process_frame
	var body := PackedByteArray()
	while c.get_status() == HTTPClient.STATUS_BODY:
		if Time.get_ticks_msec() > end:
			return {"error": "the answer did not finish"}
		c.poll()
		var chunk := c.read_response_body_chunk()
		if chunk.is_empty():
			await tree.process_frame
		else:
			body.append_array(chunk)
	if c.get_response_code() != 200:
		return {"error": "the DevTools port answered %d" % c.get_response_code()}
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (data is Array):
		return {"error": "not a target list"}
	return {"targets": data}


## The page target: type "page" (not the browser's own pages), the one titled as the window if there are several.
static func page_of(targets: Array, window_title := "") -> Dictionary:
	var pages: Array = targets.filter(func(t: Variant) -> bool:
		return t is Dictionary and str(t.get("type", "")) == "page" \
				and not str(t.get("url", "")).begins_with("devtools://") \
				and not str(t.get("url", "")).begins_with("chrome-extension://") \
				and not str(t.get("url", "")).begins_with("chrome://"))
	if pages.is_empty():
		return {}
	var best: Dictionary = pages[0]
	for t: Dictionary in pages:
		if window_title != "" and str(t.get("title", "")) != "" and window_title.begins_with(str(t["title"])):
			best = t
			break
	# id and ws stay inside the player (navigate()); page_info() gives out url and title only.
	return {"url": str(best.get("url", "")), "title": str(best.get("title", "")), "id": str(best.get("id", "")),
			"ws": str(best.get("webSocketDebuggerUrl", ""))}


## Sends the page to url over its DevTools WebSocket (Page.navigate): "" or the reason it didn't.
static func navigate(tree: SceneTree, ws_url: String, to_url: String) -> String:
	if not ws_url.begins_with("ws://127.0.0.1:"):
		return "no DevTools socket for the page"
	var ws := WebSocketPeer.new()
	if ws.connect_to_url(ws_url) != OK:
		return "could not connect to the page"
	var end := Time.get_ticks_msec() + TIMEOUT_MSEC * 2
	ws.poll()
	while ws.get_ready_state() == WebSocketPeer.STATE_CONNECTING:
		if Time.get_ticks_msec() > end:
			return "the page did not answer"
		await tree.process_frame
		ws.poll()
	if ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return "the page's socket closed"
	ws.send_text(JSON.stringify({"id": 1, "method": "Page.navigate", "params": {"url": to_url}}))
	while Time.get_ticks_msec() < end:
		await tree.process_frame
		ws.poll()
		while ws.get_available_packet_count() > 0:
			var msg: Variant = JSON.parse_string(ws.get_packet().get_string_from_utf8())
			if msg is Dictionary and int((msg as Dictionary).get("id", 0)) == 1:
				ws.close()
				if (msg as Dictionary).has("error"):
					return str(msg["error"].get("message", "refused"))
				var err := str((msg as Dictionary).get("result", {}).get("errorText", ""))
				return err
		if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			return "the page's socket closed"
	ws.close()
	return "the page did not answer"
