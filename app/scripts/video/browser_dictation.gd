extends Node

## Voice into the selected field of the browser on the big screen (docs/window-source.md, "Voice into a field").
## While the browser is on the big screen with the menu hidden, the talk button (the pointer hand's bumper,
## ui_layer.gd talk_hand()) first asks the page over DevTools what has focus (page_field.gd, one round trip on a
## lasting socket, devtools_session.gd):
##   a text field (an input of a text type, a textarea, contenteditable)  -> the recording is transcribed on the
##       headset (scripts/voice/transcriber.gd) and the final text goes in with DevTools Input.insertText, which
##       types as a keyboard does (any Unicode). While the button is held the field glows and the live words show
##       under it; both go on release, on a cancel, a page change and the window closing.
##   a password field   -> refused, with a toast; nothing is recorded
##   anything else, or no answer  -> the talk button does what it did before (the assistant, an agent), untouched
## Fields inside a cross-origin iframe (a login box from another site) are reached through that frame's own DevTools
## session (Target.setAutoAttach, flatten); the text still goes in through the page's Input.insertText, which Chromium
## sends to the focused frame. A browser without DevTools (one that was already running ignores the flag): the talk
## button is the assistant's as before (nothing can tell a password field there), and browser_insert_text falls back
## to the window's own text input (send_text) into whatever has focus.
## Privacy: what a field holds is never read; what was said is never logged, and only the immediate reply of
## browser_insert_text says how many characters went in.
## Settings: [browser] dictation_partials (default true: the live words; each costs a short transcription).
## Commands: browser_field (read), browser_insert_text (control).

const PushToTalk := preload("res://scripts/dev/push_to_talk.gd")
const Transcriber := preload("res://scripts/voice/transcriber.gd")
const WhisperBackend := preload("res://scripts/voice/whisper_backend.gd")
const DevtoolsSession := preload("res://scripts/video/devtools_session.gd")
const PageField := preload("res://scripts/video/page_field.gd")
const DevCommands := preload("res://scripts/dev/dev_commands.gd")
const WindowVideoSource := preload("res://scripts/video/window_video_source.gd")

enum State { IDLE, CHECKING, DICTATING, ASSISTANT, REFUSED }

const SECTION := "browser"
## Seconds between tries to open the page's socket again when it closed.
const RETRY_SECONDS := 2.0
const TEXT_MAX := 10000

## scripts/main.gd
var main: Node3D
var session := DevtoolsSession.new()
## The recorder (push_to_talk.gd, made on first use; tests put a stand-in here): begin() -> bool, end() -> float, and
## it sends voice_partial / voice_clip events to send_event().
var recorder: Node
var partials := true
var state := State.IDLE
## The last notice shown (tests read it; it is also the toast).
var last_note := ""
## Input.insertText sent so far (tests).
var inserted := 0
## The routing of the last press: "dictation", "assistant", "refused", "none" (tests, the read command).
var last_route := ""
var _fallback := Callable()
var _press := 0
## The DevTools session of the field's frame ("" the page's own).
var _field_session := ""
var _marked := false
var _space_before := false
var _cancelling := false
var _live_pcm := PackedByteArray()
var _partial_busy := false
var _partial_more := false
## transcriber id -> {final, press}
var _jobs := {}
## Presses whose text must not go in (cancelled).
var _dropped := {}
var _retry := 0.0
var _whisper_asked := false
var _wanted := false


func _ready() -> void:
	if main != null and main.get("settings") != null:
		partials = bool(main.settings.get_value(SECTION, "dictation_partials", true))
	Transcriber.instance().connect("done", _on_transcribed)
	session.navigated.connect(_on_navigated)
	session.closed.connect(_on_closed)
	register_commands()


func _exit_tree() -> void:
	var t: Object = Transcriber.instance()
	if t.is_connected("done", _on_transcribed):
		t.disconnect("done", _on_transcribed)
	session.close()


## The browser on the big screen (captured), or null.
func browser_source() -> WindowVideoSource:
	var src: Object = main.player.source if main != null else null
	if src is WindowVideoSource and (src as WindowVideoSource).is_browser() and (src as WindowVideoSource).has_frame():
		return src
	return null


## The talk button asks the page first only while the viewer looks at the browser: it is on the big screen, the menu
## hidden, its page has a DevTools socket, and the gaze has the stick pointer on (window_pointer.gd, stick_cursor.gd:
## the ring showing is the cue). Looking anywhere else, the button is the assistant's or the agent's as always, so
## Claude or Codex can be talked to without their window open (the user, 2026-11-06).
func wants_talk() -> bool:
	var src := browser_source()
	return src != null and main.window_pointer.is_active() and src.page_ws() != "" 			and bool(main.window_pointer.cursor.mode)


func busy() -> bool:
	return state == State.CHECKING or state == State.DICTATING


func _process(delta: float) -> void:
	var src := browser_source()
	var ws := src.page_ws() if src != null else ""
	if ws != session.ws_url:
		if session.ws_url != "":
			# Another page target, or the browser left the big screen: closed emits, and _on_closed() cancels.
			session.close()
		if ws != "":
			session.open(ws)
			_retry = RETRY_SECONDS
	elif ws != "" and session.peer == null:
		_retry -= delta
		if _retry <= 0.0:
			_retry = RETRY_SECONDS
			session.open(ws)
	session.pump()
	if ws != "" and not _whisper_asked and DisplayServer.get_name() != "headless":
		# Speech to text loads once the browser can take voice, so the first press doesn't wait for the model.
		_whisper_asked = true
		WhisperBackend.ensure(get_tree())
	if busy() and not main.window_pointer.is_active():
		# The menu opened, or the window went.
		cancel("")
	# The bumper's legend says TALK while the page can take voice (main.gd, ui_layer.gd talk_hand()).
	var wants := wants_talk()
	if wants != _wanted:
		_wanted = wants
		main.update_controller_labels()


# --- The talk button -------------------------------------------------------------------------------------------------

## The talk button pressed (held) or let go. fallback(held) -> bool is what the button did before (ui_layer.gd): the
## assistant or an agent. True when this took the press or its release.
func on_talk(held: bool, fallback: Callable) -> bool:
	if held:
		if state != State.IDLE:
			return true
		if not wants_talk():
			return false
		_press += 1
		_fallback = fallback
		state = State.CHECKING
		_start(_press)
		return true
	match state:
		State.IDLE:
			return false
		State.CHECKING, State.REFUSED:
			state = State.IDLE
		State.DICTATING:
			_finish()
		State.ASSISTANT:
			state = State.IDLE
			if _fallback.is_valid():
				_fallback.call(false)
	return true


func _start(press: int) -> void:
	var d: Dictionary = await _inspect("mark")
	if state != State.CHECKING or press != _press:
		# Let go (or cancelled) before the page answered.
		if bool(d.get("marked", false)):
			session.evaluate(get_tree(), PageField.expression("unmark"), str(d.get("session", "")))
		return
	if d.has("error"):
		_to_assistant()
		return
	if bool(d.get("password", false)):
		state = State.REFUSED
		last_route = "refused"
		_note(tr("That is a password field. Voice never types into one."))
		return
	if not bool(d.get("editable", false)):
		_to_assistant()
		return
	_field_session = str(d.get("session", ""))
	_marked = bool(d.get("marked", false))
	_space_before = bool(d.get("space_before", false))
	_ensure_recorder()
	if not bool(recorder.call("begin")):
		_unmark()
		state = State.IDLE
		last_route = "none"
		_note(tr("No microphone, so nothing was typed."))
		return
	state = State.DICTATING
	last_route = "dictation"
	_live_pcm = PackedByteArray()
	_partial_busy = false
	_partial_more = false
	print("Browser: dictating into the page's %s" % str(d.get("kind", "field")))


func _to_assistant() -> void:
	if _fallback.is_valid() and bool(_fallback.call(true)):
		state = State.ASSISTANT
		last_route = "assistant"
		return
	state = State.IDLE
	last_route = "none"
	_note(tr("Select a text field on the page first, then hold the talk button."))


## Let go while dictating: the outline and the words go now; the text goes in once the final transcription lands.
func _finish() -> void:
	state = State.IDLE
	_unmark()
	if recorder != null:
		recorder.call("end")


## Stops a dictation without typing anything (a page change, the window closing, the menu opening). why: the
## notice, or "" for none.
func cancel(why: String) -> void:
	var was := state
	_dropped[_press] = true
	if was == State.DICTATING and recorder != null:
		_cancelling = true
		recorder.call("end")
		_cancelling = false
	if was == State.CHECKING or was == State.DICTATING:
		state = State.IDLE
	_unmark()
	for id: int in _jobs.keys():
		if int(_jobs[id]["press"]) == _press:
			_jobs.erase(id)
	if why != "":
		_note(why)


func _on_navigated() -> void:
	# The page's document went, and the outline with it.
	_marked = false
	if busy() or _pending_final():
		cancel(tr("The page changed, so nothing was typed."))


func _on_closed() -> void:
	_marked = false
	if busy() or _pending_final():
		cancel(tr("The browser window closed, so nothing was typed."))


func _pending_final() -> bool:
	for id: int in _jobs:
		if bool(_jobs[id]["final"]) and int(_jobs[id]["press"]) == _press:
			return true
	return false


func _ensure_recorder() -> void:
	if recorder != null:
		return
	var p: Node = PushToTalk.new()
	p.name = "BrowserPushToTalk"
	p.set("register_command", false)
	p.set("key_enabled", false)
	p.set("link", self)
	add_child(p)
	recorder = p


func _note(text: String) -> void:
	last_note = text
	var ui: Node = main.get("ui") if main != null else null
	if ui != null and ui.has_method("notify"):
		ui.notify(text)


func _unmark() -> void:
	if not _marked:
		return
	_marked = false
	session.evaluate(get_tree(), PageField.expression("unmark"), _field_session)


# --- The recorder's events and the transcription ---------------------------------------------------------------------

## The recorder's link (push_to_talk.gd calls it): partial audio while held, the clip on release. Nothing leaves the
## headset.
func send_event(event_name: String, data: Variant = {}) -> void:
	var d: Dictionary = data if data is Dictionary else {}
	match event_name:
		"voice_partial":
			if state != State.DICTATING:
				return
			_live_pcm.append_array(Marshalls.base64_to_raw(str(d.get("pcm_b64", ""))))
			if not partials or not Transcriber.available():
				return
			if _partial_busy:
				_partial_more = true
			else:
				_start_partial()
		"voice_clip":
			if _cancelling or _dropped.has(_press):
				return
			var wav := Marshalls.base64_to_raw(str(d.get("wav_b64", "")))
			if wav.size() <= 44:
				return
			var id := Transcriber.transcribe(wav.slice(44), true) if Transcriber.available() else -1
			if id < 0:
				_note(tr("Speech to text isn't working on the headset, so nothing was typed."))
				return
			_jobs[id] = {"final": true, "press": _press}


func _start_partial() -> void:
	_partial_busy = true
	_partial_more = false
	var id := Transcriber.transcribe(_live_pcm.duplicate(), false)
	if id < 0:
		_partial_busy = false
		return
	_jobs[id] = {"final": false, "press": _press}


func _on_transcribed(id: int, text: String, final: bool) -> void:
	if not _jobs.has(id):
		return
	var job: Dictionary = _jobs[id]
	_jobs.erase(id)
	if not bool(job["final"]):
		_partial_busy = false
		if state == State.DICTATING and int(job["press"]) == _press and _marked and text.strip_edges() != "":
			session.evaluate(get_tree(), PageField.expression("words", text.strip_edges()), _field_session)
		if _partial_more and state == State.DICTATING:
			_start_partial()
		return
	if _dropped.has(int(job["press"])):
		return
	var said := text.strip_edges()
	if said == "":
		_note(tr("Didn't catch that. Try again."))
		return
	var r: Dictionary = await insert(said, true)
	if not bool(r["ok"]):
		_note(str(r["note"]))


## Types text into the focused field over DevTools, after checking it is still a text field and not a password
## field: {ok, via: devtools, characters} or {ok: false, error (English, for the command), note (for the toast)}.
## space: put a space first (the character before the caret isn't one).
func insert(text: String, space := false) -> Dictionary:
	var d: Dictionary = await _inspect("check")
	if d.has("error"):
		return {"ok": false, "error": "the page did not answer (%s)" % d["error"],
				"note": tr("The page didn't answer, so nothing was typed.")}
	if bool(d.get("password", false)):
		return {"ok": false, "error": "the focused field is a password field; the player never types into one",
				"note": tr("That is a password field. Voice never types into one.")}
	if not bool(d.get("editable", false)):
		return {"ok": false, "error": "no text field has focus on the page (browser_field says what has)",
				"note": tr("The text field lost focus, so nothing was typed.")}
	var s := (" " + text) if space and bool(d.get("space_before", false)) else text
	var r: Dictionary = await session.request(get_tree(), "Input.insertText", {"text": s})
	if r.has("error"):
		return {"ok": false, "error": "the page refused the text (%s)" % r["error"],
				"note": tr("The page didn't answer, so nothing was typed.")}
	inserted += 1
	return {"ok": true, "via": "devtools", "characters": s.length()}


## What has focus in the page: the check's answer (page_field.gd) plus session (the frame's DevTools session, "" the
## page's own), or {error}. op "mark" also puts the outline on a text field. A focused cross-origin iframe is asked
## through its own session.
func _inspect(op: String) -> Dictionary:
	var tree := get_tree()
	if session.peer == null:
		return {"error": "no DevTools connection to the page"}
	var r: Dictionary = await session.evaluate(tree, PageField.expression(op))
	if r.has("error"):
		return r
	var d: Dictionary = r["value"] if r["value"] is Dictionary else {}
	if d.is_empty():
		return {"error": "the page gave no answer"}
	d["session"] = ""
	if str(d.get("frame", "")) != "cross-origin":
		return d
	for sid: String in session.frames.keys():
		var f: Dictionary = await session.evaluate(tree, PageField.expression("check"), sid)
		var fd: Variant = f.get("value")
		if not (fd is Dictionary) or not bool(fd.get("focused", false)) or str(fd.get("kind", "")) in ["iframe", "none"]:
			continue
		var found: Dictionary = fd
		if op == "mark":
			var m: Dictionary = await session.evaluate(tree, PageField.expression("mark"), sid)
			if m.get("value") is Dictionary:
				found = m["value"]
		found["frame"] = "cross-origin"
		found["session"] = sid
		return found
	d["note"] = "the focus is in a frame from another site that DevTools could not reach"
	return d


# --- Commands ------------------------------------------------------------------------------------------------------

func register_commands() -> void:
	DevCommands.register("browser_field", func(_args: Dictionary, _ctx: DevCommands.Call) -> Variant:
		return await field_status(), {"assistant": "read",
		"description": "What has the keyboard focus in the browser's page on the big screen, read fresh over "
				+ "DevTools: editable (a text input, textarea or contenteditable), kind, input_type, password, frame "
				+ "(main, same-origin or cross-origin iframe). Never the field's contents. browser false when no "
				+ "browser is shown; devtools false when the browser has no DevTools port (then nothing can be told).",
		"returns": "{browser, devtools, editable, kind, input_type, password, frame, note?}"})
	DevCommands.register("browser_insert_text", _cmd_insert, {"level": "control", "assistant": "control",
		"description": "Types text into the focused field of the browser's page on the big screen, as the "
				+ "viewer's voice does: DevTools Input.insertText (any Unicode), after checking the focus is on a "
				+ "text field; a password field is always refused. Without DevTools it goes to whatever has the "
				+ "keyboard focus through the window's own text input. The reply never repeats the text.",
		"params": [{"name": "text", "type": "string", "required": true,
				"description": "the text to type (at most %d characters)" % TEXT_MAX}],
		"returns": "{inserted, via: devtools | send_text, characters, note?}"})


func field_status() -> Dictionary:
	var src := browser_source()
	if src == null:
		return {"browser": false}
	if src.page_ws() == "":
		return {"browser": true, "devtools": false,
				"note": "this browser has no DevTools port (not launched by the player), so its focus can't be read"}
	var d: Dictionary = await _inspect("check")
	if d.has("error"):
		return {"browser": true, "devtools": true, "editable": false, "note": "the page did not answer (%s)" % d["error"]}
	var out := PageField.public(d)
	out["browser"] = true
	out["devtools"] = true
	if d.has("note"):
		out["note"] = d["note"]
	return out


func _cmd_insert(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var text := str(args.get("text", ""))
	if text.strip_edges() == "":
		return ctx.fail("no text")
	if text.length() > TEXT_MAX:
		return ctx.fail("at most %d characters" % TEXT_MAX)
	var src := browser_source()
	if src == null:
		return ctx.fail("no browser on the big screen")
	if src.page_ws() == "":
		src.send_text(text)
		ctx.summary = "typed into the browser"
		return {"inserted": true, "via": "send_text", "characters": text.length(),
				"note": "this browser has no DevTools port, so the focused field could not be checked: the text went "
				+ "to whatever has the keyboard focus"}
	var r: Dictionary = await insert(text)
	if not bool(r["ok"]):
		return ctx.fail(str(r["error"]))
	ctx.summary = "typed into the browser's field"
	return {"inserted": true, "via": "devtools", "characters": int(r["characters"])}
