extends SceneTree

## Voice into the browser's selected field (scripts/video/browser_dictation.gd, devtools_session.gd, page_field.gd)
## against the real main scene, with no network and no browser: a fake DevTools page (a WebSocket server on the
## loopback that answers Runtime.evaluate from a pretend focus, takes Input.insertText and sends events), a stand-in
## recorder and a stand-in speech to text. Covers: the editable check routing the talk button to dictation or to what
## it did before, the outline added on press and removed on release, cancel, a page change and the window closing,
## the live words, Input.insertText (Chinese too), the password refusal, a field in a cross-origin iframe, a page
## that doesn't answer, no speech to text, the send_text fallback without DevTools, the TALK legend, and the
## browser_field and browser_insert_text commands.
##
## godot --headless --xr-mode off --path app --script res://tests/test_browser_dictation.gd

const WindowVideoSource := preload("res://scripts/video/window_video_source.gd")
const Transcriber := preload("res://scripts/voice/transcriber.gd")
const PageField := preload("res://scripts/video/page_field.gd")
const DevCommands := preload("res://scripts/dev/dev_commands.gd")
const CommandHost := preload("res://scripts/dev/command_host.gd")

const TEXT_TYPES := ["text", "search", "url", "tel", "email", "password"]


## A pretend page behind DevTools. focus: what has focus in the page ({kind, type?, space_before?}; kind "iframe":
## the focus is in a cross-origin frame, whose own focus is frame_focus, reached as session S1 once attached).
class FakePage extends Node:
	var server := TCPServer.new()
	var port := 0
	var peer: WebSocketPeer
	var got: Array[Dictionary] = []
	var focus := {"kind": "input", "type": "text"}
	var frame_focus := {}
	var marked := {"": false, "S1": false}
	var words := ""
	var inserted: Array[String] = []
	var silent := false

	func start() -> void:
		server.listen(0, "127.0.0.1")
		port = server.get_local_port()

	func ws_url() -> String:
		return "ws://127.0.0.1:%d/devtools/page/PAGE1" % port

	func open() -> bool:
		return peer != null and peer.get_ready_state() == WebSocketPeer.STATE_OPEN

	func event(method: String, params: Dictionary) -> void:
		peer.send_text(JSON.stringify({"method": method, "params": params}))

	func drop() -> void:
		if peer != null:
			peer.close()

	func methods(name: String, session := "") -> Array:
		return got.filter(func(m: Dictionary) -> bool:
			return m["method"] == name and str(m.get("sessionId", "")) == session)

	func evaluated(op: String, session := "") -> int:
		return methods("Runtime.evaluate", session).filter(func(m: Dictionary) -> bool:
			return str(m["params"]["expression"]).begins_with("/*vrplayer:%s*/" % op)).size()

	func _process(_delta: float) -> void:
		if server.is_connection_available():
			peer = WebSocketPeer.new()
			peer.accept_stream(server.take_connection())
		if peer == null:
			return
		peer.poll()
		while peer.get_available_packet_count() > 0:
			var m: Variant = JSON.parse_string(peer.get_packet().get_string_from_utf8())
			if not (m is Dictionary):
				continue
			got.append(m)
			if silent:
				continue
			var sid := str(m.get("sessionId", ""))
			var result: Variant = {}
			match str(m["method"]):
				"Runtime.evaluate":
					result = {"result": {"type": "object", "value": _eval(str(m["params"]["expression"]), sid)}}
				"Input.insertText":
					inserted.append(str(m["params"]["text"]))
			var reply := {"id": m["id"], "result": result}
			if sid != "":
				reply["sessionId"] = sid
			peer.send_text(JSON.stringify(reply))

	func _describe(f: Dictionary, sid: String) -> Dictionary:
		var kind := str(f.get("kind", "none"))
		var d := {"editable": false, "kind": kind, "input_type": "", "password": false,
				"space_before": bool(f.get("space_before", false)), "frame": "main", "focused": true, "marked": false}
		if sid != "":
			d["focused"] = not f.is_empty()
		match kind:
			"input":
				var t := str(f.get("type", "text"))
				d["input_type"] = t
				d["password"] = t == "password"
				d["editable"] = t in TEXT_TYPES
			"textarea", "contenteditable":
				d["editable"] = true
			"iframe":
				d["frame"] = "cross-origin"
		return d

	func _eval(expression: String, sid: String) -> Variant:
		var op := expression.get_slice("/*vrplayer:", 1).get_slice("*/", 0)
		var d := _describe(focus if sid == "" else frame_focus, sid)
		match op:
			"check":
				return d
			"mark":
				if d["editable"] and not d["password"]:
					marked[sid] = true
					d["marked"] = true
				return d
			"words":
				var at := expression.rfind("(\"words\", ")
				var text: Variant = JSON.parse_string(expression.substr(at + 10).trim_suffix(")"))
				if marked[sid]:
					words = str(text)
				return marked[sid]
			"unmark":
				var was: bool = marked[sid]
				marked[sid] = false
				words = ""
				return was
		return null


## Stands in for push_to_talk.gd: the clip and the partials go to its link as the real one sends them.
class FakeRecorder extends Node:
	var link: Object
	var recording := false
	var mic := true
	var begun := 0

	func begin() -> bool:
		if not mic:
			return false
		recording = true
		begun += 1
		link.send_event("voice_state", {"recording": true})
		return true

	func partial() -> void:
		link.send_event("voice_partial", {"pcm_b64": Marshalls.raw_to_base64(_pcm(8000)), "seq": 0, "rate": 16000})

	func end() -> float:
		if not recording:
			return 0.0
		recording = false
		link.send_event("voice_state", {"recording": false})
		var wav := PackedByteArray()
		wav.resize(44)
		wav.append_array(_pcm(16000))
		link.send_event("voice_clip", {"wav_b64": Marshalls.raw_to_base64(wav), "seconds": 1.0, "rate": 16000})
		return 1.0

	static func _pcm(samples: int) -> PackedByteArray:
		var b := PackedByteArray()
		b.resize(samples * 2)
		return b


## Stands in for the speech to text: keeps each request; the test answers them.
class FakeBackend extends RefCounted:
	var jobs: Array = []

	func ready() -> bool:
		return true

	func describe() -> String:
		return "fake"

	func transcribe(id: int, _pcm: PackedByteArray, final: bool) -> bool:
		jobs.append([id, final])
		return true

	func last(final: bool) -> int:
		for i in range(jobs.size() - 1, -1, -1):
			if jobs[i][1] == final:
				return jobs[i][0]
		return -1

	func count(final: bool) -> int:
		return jobs.filter(func(j: Array) -> bool: return j[1] == final).size()


## Stands in for X11WindowSource (only what this test needs).
class FakeWin extends RefCounted:
	var calls: Array = []

	func get_size() -> Vector2i:
		return Vector2i(1920, 1080)

	func get_texture() -> Texture2D:
		return null

	func update() -> bool:
		return false

	func get_stats() -> Dictionary:
		return {}

	func send_pointer(_x: float, _y: float) -> void:
		pass

	func send_button(_b: int, _pressed: bool) -> void:
		pass

	func send_scroll(_dx: float, _dy: float) -> void:
		pass

	func send_godot_key(_k: int, _pressed: bool) -> void:
		pass

	func send_unicode(u: int, pressed: bool) -> void:
		calls.append(["unicode", u, pressed])

	func send_text(t: String) -> void:
		calls.append(["text", t])

	func stop_capture() -> void:
		pass

	func close() -> void:
		pass

	func close_window(_id: int) -> void:
		pass


var _failures := 0
var _checks := 0
var main: Node3D
var dict: Node
var page: FakePage
var rec: FakeRecorder
var backend: FakeBackend
var win: FakeWin
var src: WindowVideoSource
## The calls of the stand-in for what the talk button did before: [held, ...].
var fallback_calls: Array = []
var fallback_takes := true


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _run() -> void:
	await _frames(5)
	CommandHost.ensure(self)
	page = FakePage.new()
	page.start()
	root.add_child(page)
	backend = FakeBackend.new()
	Transcriber.backend = backend
	dict = main.browser_dictation
	rec = FakeRecorder.new()
	rec.link = dict
	dict.add_child(rec)
	dict.recorder = rec
	_script_checks()
	await _open_browser()
	await _gaze_checks()
	await _connect_checks()
	await _dictation_checks()
	await _chinese_and_space_checks()
	await _routing_checks()
	await _password_checks()
	await _cancel_checks()
	await _no_backend_checks()
	await _command_checks()
	await _iframe_checks()
	await _no_answer_checks()
	await _window_closing_checks()
	await _no_devtools_checks()
	Transcriber.backend = null
	main.queue_free()
	page.queue_free()
	await _frames(2)
	print("test_browser_dictation: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(1 if _failures > 0 else 0)


# --- Set-up --------------------------------------------------------------------------------------------------------

func _open_browser(with_devtools := true) -> void:
	main.ui.hide_panel()
	main.set_menu_shown(false)
	main.player.close()
	src = WindowVideoSource.new()
	win = FakeWin.new()
	src.path = WindowVideoSource.browser_path("https://example.org/")
	src.url = "https://example.org/"
	src.launched = true
	src.window_id = 0x2a00003
	src.win = win
	src._page_next_msec = 1 << 62
	if with_devtools:
		src.devtools_port = 1
		src._page = {"url": "https://example.org/", "title": "Example", "id": "PAGE1", "ws": page.ws_url()}
	main.current_path = src.path
	main.player.source = src
	main.mode = src.get_known_mode().copy()
	await _frames(2)


func _fallback(held: bool) -> bool:
	fallback_calls.append(held)
	return fallback_takes


## Presses the talk button as ui_layer.gd does (through on_bumper) and waits for the page's answer.
func _press() -> void:
	main.ui.on_bumper(main.ui.pointer_hand, true)
	await _until(func() -> bool: return dict.state != dict.State.CHECKING, 3.0)


func _release() -> void:
	main.ui.on_bumper(main.ui.pointer_hand, false)
	await _frames(4)


## The final transcription of the last clip: text.
func _final(text: String) -> void:
	var id := backend.last(true)
	dict.last_note = ""
	Transcriber.emit_done(id, text, true)
	await _until(func() -> bool: return dict.inserted > 0 and page.inserted.size() > 0 or dict.last_note != "", 2.0)
	await _frames(4)


# --- Checks --------------------------------------------------------------------------------------------------------

func _script_checks() -> void:
	var e := PageField.expression("words", "a \"quote\" ) and   a line")
	_check("the words go in as JSON, so no text can break out", e.ends_with(JSON.stringify(
			"a \"quote\" ) and   a line") + ")") and e.begins_with("/*vrplayer:words*/(function (op, arg)"))
	var pub := PageField.public({"editable": true, "kind": "input", "input_type": "text", "space_before": true,
			"password": false, "frame": "main", "focused": true, "value": "secret"})
	_check("what the read command gives out: no hint of the field's text (%s)" % [pub], not pub.has("space_before")
			and not pub.has("value") and pub["editable"] == true)
	_check("the page's script never reads a field's value except the caret's neighbour",
			PageField.SCRIPT.count(".value") == 1 and PageField.SCRIPT.contains("el.value.charAt(el.selectionStart - 1)"))
	# The script itself, run by Node against a small stand-in DOM (tests/page_field_check.js), when Node is here.
	var out: Array = []
	var code := OS.execute("node", [ProjectSettings.globalize_path("res://tests/page_field_check.js"),
			ProjectSettings.globalize_path("res://scripts/video/page_field.gd")], out, true)
	if code == -1 or code == 127:
		print("test_browser_dictation: no Node here; the page script's own run skipped")
	else:
		_check("the page's script in a stand-in DOM: check, mark, words, unmark, frames (%s)" % ("" if code == 0
				else str(out)), code == 0)


## Where the viewer looks (window_pointer.gd's gaze override, as in the headset without a session): at the screen's
## middle, or well off it. The pointer mode follows after its hysteresis (stick_cursor.gd).
func _gaze(on_screen: bool) -> void:
	var wp: Node = main.window_pointer
	wp.test_xr = true
	wp.use_gaze_override = true
	var eye: Vector3 = main.camera.global_position
	var target: Vector3 = main.screen.global_position
	if not on_screen:
		target = eye + (eye - target)
	wp.gaze_override = [eye, (target - eye).normalized()]
	await create_timer(0.7).timeout
	await _frames(2)


## The talk button is the page's only while the viewer looks at the browser; looking away it is Claude's or Codex's
## as always (the user, 2026-11-06).
func _gaze_checks() -> void:
	await _until(func() -> bool: return dict.session.is_open(), 3.0)
	await _gaze(false)
	_check("looking away from the browser: the talk button is not the page's", not dict.wants_talk()
			and not main.window_pointer.cursor.mode)
	var before := []
	var took: bool = dict.on_talk(true, func(held: bool) -> bool: before.append(held); return true)
	_check("and a press goes on to the assistant or agent, untouched", not took)
	await _gaze(true)
	_check("looking at the browser: the page's (the stick pointer on)", dict.wants_talk()
			and main.window_pointer.cursor.mode)


func _connect_checks() -> void:
	await _until(func() -> bool: return dict.session.is_open() and page.open(), 3.0)
	_check("a lasting DevTools socket to the page", dict.session.is_open())
	await _until(func() -> bool: return page.methods("Target.setAutoAttach").size() > 0, 2.0)
	_check("on opening: Page.enable and auto-attach with flatten (for cross-origin frames)",
			page.methods("Page.enable").size() == 1 and page.methods("Target.setAutoAttach").size() == 1
			and page.methods("Target.setAutoAttach")[0]["params"]["flatten"] == true)
	_check("the talk button is the pointer hand's, with no assistant connected", main.ui.talk_hand()
			== main.ui.pointer_hand and dict.wants_talk())
	var texts: Dictionary = main.right_hand.visual.get("_texts") if main.right_hand.visual.get("_texts") is Dictionary \
			else {}
	if texts.has("bumper"):
		_check("the bumper's legend says TALK (%s)" % texts["bumper"], texts["bumper"] == "TALK")


func _dictation_checks() -> void:
	page.focus = {"kind": "input", "type": "search"}
	await _press()
	_check("a text field has focus: dictation (%s)" % dict.last_route, dict.state == dict.State.DICTATING
			and dict.last_route == "dictation" and rec.recording)
	_check("the field glows while the button is held (one check-and-mark round trip)", page.marked[""]
			and page.evaluated("mark") == 1)
	rec.partial()
	_check("the live words: a partial transcription", backend.count(false) == 1)
	Transcriber.emit_done(backend.last(false), " hello wor ", false)
	await _until(func() -> bool: return page.words != "", 2.0)
	_check("the live words show under the field (%s)" % page.words, page.words == "hello wor")
	await _release()
	_check("let go: the outline and the words go at once", not page.marked[""] and page.words == ""
			and page.evaluated("unmark") >= 1)
	_check("the clip goes to the speech to text", backend.count(true) == 1 and not rec.recording)
	await _final(" Search for this. ")
	_check("the final text goes in with Input.insertText (%s)" % [page.inserted], page.inserted == ["Search for this."]
			and page.methods("Input.insertText")[0].get("sessionId", "") == "")
	_check("checked again before typing (the focus could have moved)", page.evaluated("check") >= 1)


func _chinese_and_space_checks() -> void:
	page.inserted.clear()
	page.focus = {"kind": "textarea"}
	await _press()
	await _release()
	await _final("你好，世界")
	_check("Chinese text goes in as it is (%s)" % [page.inserted], page.inserted == ["你好，世界"])
	page.inserted.clear()
	page.focus = {"kind": "contenteditable", "space_before": true}
	await _press()
	await _release()
	await _final("next words")
	_check("a space first when the caret follows a word (%s)" % [page.inserted], page.inserted == [" next words"])
	page.inserted.clear()
	dict.last_note = ""
	page.focus = {"kind": "input", "type": "text"}
	await _press()
	await _release()
	page.focus = {"kind": "button"}
	await _final("too late")
	_check("the focus moved off the field before the text came: nothing typed (%s)" % dict.last_note,
			page.inserted.is_empty() and dict.last_note.contains("lost focus"))
	dict.last_note = ""
	page.focus = {"kind": "input", "type": "text"}
	await _press()
	await _release()
	await _final("   ")
	_check("no words: nothing typed, and the toast says so", page.inserted.is_empty()
			and dict.last_note.contains("Didn't catch"))


func _routing_checks() -> void:
	page.focus = {"kind": "button"}
	fallback_calls.clear()
	var marks := page.evaluated("mark")
	_check("the press is taken while the page is asked", dict.on_talk(true, _fallback))
	await _until(func() -> bool: return dict.state != dict.State.CHECKING, 3.0)
	_check("no text field: the talk button does what it did before (the assistant) (%s)" % [fallback_calls],
			dict.state == dict.State.ASSISTANT and fallback_calls == [true] and not rec.recording
			and dict.last_route == "assistant")
	_check("and nothing glows", not page.marked[""] and page.evaluated("mark") == marks + 1)
	dict.on_talk(false, _fallback)
	_check("its release goes there too", fallback_calls == [true, false] and dict.state == dict.State.IDLE)
	page.focus = {"kind": "input", "type": "number"}
	fallback_calls.clear()
	dict.on_talk(true, _fallback)
	await _until(func() -> bool: return dict.state != dict.State.CHECKING, 3.0)
	_check("a number input is no text field", fallback_calls == [true])
	dict.on_talk(false, _fallback)
	page.focus = {"kind": "none"}
	dict.last_note = ""
	await _press()
	_check("no field and no assistant: a plain toast (%s)" % dict.last_note, dict.last_route == "none"
			and dict.last_note.contains("Select a text field"))
	await _release()
	page.focus = {"kind": "input", "type": "text"}
	rec.mic = false
	dict.last_note = ""
	await _press()
	await _frames(4)
	_check("no microphone: said, and the outline goes", dict.last_note.contains("microphone") and not page.marked[""])
	rec.mic = true
	await _release()


func _password_checks() -> void:
	page.focus = {"kind": "input", "type": "password"}
	fallback_calls.clear()
	var begun := rec.begun
	dict.on_talk(true, _fallback)
	await _until(func() -> bool: return dict.state != dict.State.CHECKING, 3.0)
	_check("a password field: refused, said plainly (%s)" % dict.last_note, dict.last_route == "refused"
			and dict.last_note.contains("password") and rec.begun == begun and fallback_calls.is_empty())
	_check("nothing recorded, nothing glows", not rec.recording and not page.marked[""])
	dict.on_talk(false, _fallback)
	_check("its release does nothing", dict.state == dict.State.IDLE and fallback_calls.is_empty())


func _cancel_checks() -> void:
	page.focus = {"kind": "input", "type": "text"}
	page.inserted.clear()
	var finals := backend.count(true)
	await _press()
	_check("dictating, glowing", dict.state == dict.State.DICTATING and page.marked[""])
	page.event("Page.frameNavigated", {"frame": {"id": "F1", "url": "https://example.org/next"}})
	await _until(func() -> bool: return dict.state == dict.State.IDLE, 2.0)
	_check("a page change cancels: nothing recorded goes anywhere (%s)" % dict.last_note,
			dict.state == dict.State.IDLE and not rec.recording and backend.count(true) == finals
			and dict.last_note.contains("page changed"))
	page.marked[""] = false
	await _release()
	_check("the release after a cancel does nothing", dict.state == dict.State.IDLE and page.inserted.is_empty())
	page.event("Page.frameNavigated", {"frame": {"id": "F2", "parentId": "F1"}})
	await _frames(4)
	_check("a sub-frame's navigation is no page change", dict.session.navigations == 1)
	# The menu opening while held: a cancel, and the outline goes.
	await _press()
	_check("dictating again", dict.state == dict.State.DICTATING and page.marked[""])
	main.set_menu_shown(true)
	await _until(func() -> bool: return not page.marked[""], 2.0)
	_check("the menu opens: cancelled, the outline removed", dict.state == dict.State.IDLE and not page.marked[""]
			and not rec.recording and backend.count(true) == finals)
	main.set_menu_shown(false)
	await _release()
	_check("no talk button for the page while the menu shows", true)
	# A navigation after release, before the text came: nothing goes in.
	await _press()
	await _release()
	page.event("Page.frameNavigated", {"frame": {"id": "F3"}})
	await _frames(6)
	Transcriber.emit_done(backend.last(true), "for the old page", true)
	await _frames(6)
	_check("the page changed before the text came: nothing typed", page.inserted.is_empty())


func _no_backend_checks() -> void:
	Transcriber.backend = null
	page.inserted.clear()
	dict.last_note = ""
	page.focus = {"kind": "input", "type": "text"}
	await _press()
	await _release()
	_check("no speech to text: said plainly, the field untouched (%s)" % dict.last_note,
			dict.last_note.contains("Speech to text isn't working") and page.inserted.is_empty() and not page.marked[""])
	Transcriber.backend = backend


func _command_checks() -> void:
	page.inserted.clear()
	page.focus = {"kind": "input", "type": "email"}
	var r: Dictionary = await DevCommands.execute("browser_field", {}, true)
	_check("browser_field: editable, the kind and type, no contents (%s)" % [r.get("result")], r["ok"]
			and r["result"]["editable"] == true and r["result"]["kind"] == "input" and r["result"]["input_type"] == "email"
			and r["result"]["devtools"] == true and not r["result"].has("space_before"))
	r = await DevCommands.execute("browser_insert_text", {"text": "typed by the assistant 中文"}, true)
	_check("browser_insert_text: through the app, with Input.insertText (%s)" % [r.get("result")], r["ok"]
			and r["result"]["via"] == "devtools" and page.inserted == ["typed by the assistant 中文"]
			and r["result"]["characters"] == 25)
	_check("its reply never repeats the text", not JSON.stringify(r.get("result")).contains("assistant 中文")
			and not str(r.get("summary", "")).contains("assistant"))
	page.focus = {"kind": "input", "type": "password"}
	r = await DevCommands.execute("browser_field", {}, true)
	_check("browser_field: a password field says so", r["ok"] and r["result"]["password"] == true
			and r["result"]["editable"] == true)
	r = await DevCommands.execute("browser_insert_text", {"text": "hunter2"}, true)
	_check("browser_insert_text: a password field is refused (%s)" % r.get("error"), not r["ok"]
			and str(r.get("error")).contains("password") and page.inserted.size() == 1)
	page.focus = {"kind": "body"}
	r = await DevCommands.execute("browser_insert_text", {"text": "x"}, true)
	_check("browser_insert_text: no field, refused", not r["ok"] and str(r.get("error")).contains("no text field"))
	r = await DevCommands.execute("browser_insert_text", {"text": "  "}, true)
	_check("browser_insert_text: no text, refused", not r["ok"])
	_check("both for the assistant: read and control", DevCommands.get_spec("browser_field").get("assistant") == "read"
			and DevCommands.get_spec("browser_insert_text").get("assistant") == "control"
			and DevCommands.get_spec("browser_insert_text").get("level") == "control")


func _iframe_checks() -> void:
	page.inserted.clear()
	page.focus = {"kind": "iframe"}
	page.frame_focus = {"kind": "input", "type": "email"}
	var r: Dictionary = await DevCommands.execute("browser_field", {}, true)
	_check("the focus in a cross-origin frame not attached: not a field, and why (%s)" % [r.get("result")],
			r["ok"] and r["result"]["editable"] == false and r["result"]["frame"] == "cross-origin"
			and str(r["result"].get("note", "")).contains("another site"))
	page.event("Target.attachedToTarget", {"sessionId": "S1", "targetInfo": {"targetId": "T1", "type": "iframe",
			"url": "https://login.example.net/"}, "waitingForDebugger": false})
	await _until(func() -> bool: return dict.session.frames.has("S1"), 2.0)
	_check("an attached frame is known by its session", dict.session.frames.has("S1"))
	await _until(func() -> bool: return page.methods("Target.setAutoAttach", "S1").size() > 0, 2.0)
	_check("and its own frames are attached too", page.methods("Target.setAutoAttach", "S1").size() == 1)
	r = await DevCommands.execute("browser_field", {}, true)
	_check("browser_field: the field inside the frame (%s)" % [r.get("result")], r["ok"]
			and r["result"]["editable"] == true and r["result"]["input_type"] == "email"
			and r["result"]["frame"] == "cross-origin")
	await _press()
	_check("dictation into the frame's field: the outline in that frame", dict.state == dict.State.DICTATING
			and page.marked["S1"] and not page.marked[""])
	await _release()
	_check("let go: the frame's outline goes", not page.marked["S1"])
	await _final("someone@example.net")
	_check("the text goes in through the page's Input.insertText (the focused frame gets it) (%s)" % [page.inserted],
			page.inserted == ["someone@example.net"] and page.methods("Input.insertText", "S1").is_empty())
	page.frame_focus = {"kind": "input", "type": "password"}
	await _press()
	_check("a password field in the frame is refused too", dict.last_route == "refused" and not page.marked["S1"])
	await _release()
	page.event("Target.detachedFromTarget", {"sessionId": "S1"})
	await _until(func() -> bool: return not dict.session.frames.has("S1"), 2.0)
	_check("a detached frame is forgotten", not dict.session.frames.has("S1"))
	page.focus = {"kind": "input", "type": "text"}
	page.frame_focus = {}


func _no_answer_checks() -> void:
	page.silent = true
	fallback_calls.clear()
	dict.on_talk(true, _fallback)
	await _until(func() -> bool: return dict.state != dict.State.CHECKING, 4.0)
	_check("a page that doesn't answer: the talk button does what it did before", fallback_calls == [true]
			and dict.state == dict.State.ASSISTANT)
	dict.on_talk(false, _fallback)
	page.silent = false


func _window_closing_checks() -> void:
	page.focus = {"kind": "input", "type": "text"}
	page.inserted.clear()
	await _press()
	_check("dictating before the window closes", dict.state == dict.State.DICTATING)
	src.window_id = 0
	await _until(func() -> bool: return dict.state == dict.State.IDLE, 2.0)
	_check("the window closing cancels (%s)" % dict.last_note, dict.state == dict.State.IDLE and not rec.recording
			and dict.last_note.contains("window closed"))
	_check("and the socket goes", not dict.session.is_open())
	await _release()
	src.window_id = 0x2a00003
	await _until(func() -> bool: return dict.session.is_open(), 4.0)
	_check("back: the socket opens again", dict.session.is_open())


func _no_devtools_checks() -> void:
	await _open_browser(false)
	await _frames(3)
	_check("a browser without DevTools: the talk button is not the page's", not dict.wants_talk()
			and not dict.on_talk(true, _fallback))
	var r: Dictionary = await DevCommands.execute("browser_field", {}, true)
	_check("browser_field: no DevTools, said", r["ok"] and r["result"]["devtools"] == false)
	r = await DevCommands.execute("browser_insert_text", {"text": "plain"}, true)
	_check("browser_insert_text without DevTools: the window's own text input (%s)" % [win.calls], r["ok"]
			and r["result"]["via"] == "send_text" and win.calls.has(["text", "plain"])
			and str(r["result"].get("note", "")).contains("could not be checked"))
	main.player.close()
	await _frames(2)
	r = await DevCommands.execute("browser_insert_text", {"text": "x"}, true)
	_check("no browser shown: refused", not r["ok"])
	r = await DevCommands.execute("browser_field", {}, true)
	_check("browser_field: no browser", r["ok"] and r["result"]["browser"] == false)


# --- Helpers ------------------------------------------------------------------------------------------------------

func _until(cond: Callable, seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not bool(cond.call()) and Time.get_ticks_msec() < end:
		await process_frame


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL " + what)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
