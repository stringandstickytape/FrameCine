extends Node

## Agents running on the headset itself (docs/assistant.md, "Agents on the headset"; the table and the files are in
## agent_terminal.gd). The terminal IS the conversation: its window shows on the pane on the pointer controller
## (ui/agent_pane.gd) while the film carries on, and push-to-talk types straight into it. One agent is active: on the
## pane and taking the voice. A second X11WindowSource alongside the screen's source captures it, and only while the
## pane shows. The terminals outlive the player and film changes: nothing here closes one, and each is found again by
## its window class.
##
## Talk (the bumper on the pointer hand) shows the pane; a quick tap while it shows hides it (the agent keeps working).
## Y on the right controller, while that is the pointer hand, shows or hides it too, and with no agent running starts the
## last one used.
## X on the right controller is Enter whenever the terminal shows (on the pane or the big screen), whichever hand points,
## the menu open or not; its printed legend says ENTER then, and nothing otherwise (X has no other job on the headset's
## own profile). on_enter_button(), enter_ready().
## While it shows, the stick and the trigger stay the film's, except:
##   an agent's prompt is waiting (its hook said so, .player/waiting; the pane's edge turns amber, the hand buzzes, and a
##   note says so if the pane is hidden): stick up / down are arrows, trigger Enter, A Space, B Escape
##   the viewer looks at the pane (the gaze within GAZE_MARGIN_DEG of its edge when calibrated, GAZE_MARGIN_RAW_DEG when
##   not; the edge turns blue): the same keys, and stick left / right are arrows too. No hook is needed, so this answers a
##   list no hook told of. Never with the menu open (the menu keeps its stick and trigger), never while a calibration runs
##   squeeze held: trigger Enter, stick up / down scroll back (Shift + Page Up / Down)
## Until the first start's introduction is gone through (ui/intro.gd), the controllers give the terminal nothing: Y opens
## the menu at the introduction instead.
## A keyboard paired to the headset types into the terminal while the pane shows. With a window on the big screen as
## well (a browser), the look decides: on the pane the terminal has it, anywhere else the window does.
## Spoken alone, "one" to "four", "up", "down", "enter" and "escape" are always that key (a list no hook told of, such as
## the folder trust question, takes only these); "yes" and "no" are the agent's keys while a prompt waits and ordinary
## words otherwise (a "yes" typed at an agent asking a plain question is an answer).
## Words must not answer a prompt by accident: Enter takes a list's highlighted row, usually yes, and Codex's rows answer
## to single letters. So while a prompt waits, words that are not a key are not typed, and a note says what to say. A
## prompt no hook told of is met with Escape, which turns it down, ahead of a lone "no" and of any words before the
## session's first hook has run (until then the app can't tell; Codex before /hooks trusts them, or a plain start).
##
## Nothing here reads the terminal: words and keys go in, the picture goes to the pane, and nothing leaves the headset.
##
##   open_agent(id), restart_agent(id, plain), show_on_screen(id), set_active(id), hide_pane(), toggle_pane()
##   running() -> Array of ids; active -> id or ""; pane_shown(); waiting() -> bool
##   push_to_talk() -> Node or null, for ui_layer.voice_target()
##   on_talk(held), on_trigger(hand, pressed), on_stick(hand, stick, delta), on_button(hand, action) -> bool,
##   on_agent_button(hand), on_enter_button(hand) -> bool, enter_ready() -> bool
##   status(), agent_of(client), register_commands(cmd_host): the Files rows as commands (agents, agent_start, ...)

signal changed

const AgentTerminal := preload("res://scripts/agents/agent_terminal.gd")
const AgentPane := preload("res://ui/agent_pane.gd")
const PushToTalk := preload("res://scripts/dev/push_to_talk.gd")
const Transcriber := preload("res://scripts/voice/transcriber.gd")
const WhisperBackend := preload("res://scripts/voice/whisper_backend.gd")
const AssistantBrowse := preload("res://scripts/assistant/assistant_browse.gd")
const WindowVideoSource := preload("res://scripts/video/window_video_source.gd")
const Assistant := preload("res://scripts/assistant/assistant.gd")
const AssistantSwitches := preload("res://scripts/assistant/assistant_switches.gd")
const DevCommands := preload("res://scripts/dev/dev_commands.gd")

const ENGINE_CLASS := "X11WindowSource"
## How often the running terminals and the waiting flag are looked at, and the context file written (seconds).
const POLL_SECONDS := 0.5
const CONTEXT_SECONDS := 2.0
## A terminal coming up: how long to look for its window.
const START_TIMEOUT := 20.0
const STOP_TIMEOUT := 5.0
## A press of talk shorter than this while the pane shows hides it.
const TAP_MSEC := 350
## Enter goes after the words by this much, or the agent's input takes the burst as a paste and Enter as a new line.
const ENTER_DELAY := 0.15
const STICK_THRESHOLD := 0.7
const STICK_REPEAT := 0.3
## The margin round the pane for the gaze, degrees: a calibrated reading is about 1.3 off (scripts/xr/eye_gaze.gd).
const GAZE_MARGIN_DEG := 3.0
## The same with no calibration (a new install): the headset's own reading is off by a median 1.8 degrees, 3.9 at the
## worst measured (eye_gaze.gd), so 5 still finds the pane. The pane is about 37 x 21 degrees at 45 cm.
const GAZE_MARGIN_RAW_DEG := 5.0
## A look counts after GAZE_ON seconds and lasts GAZE_OFF seconds beyond the last reading on the pane: a blink drops the
## reading, and a glance away mustn't hand the stick to the film mid-press. A held stick keeps it.
const GAZE_ON := 0.15
const GAZE_OFF := 0.4
const SUBTITLE_LINES := 4
const INSTALL_CARD := "agent_install"
const WORDS := {"one": "1", "two": "2", "three": "3", "four": "4", "escape": "escape", "1": "1", "2": "2", "3": "3",
		"4": "4", "up": "up", "down": "down", "enter": "enter"}

## scripts/main.gd
var main: Node3D
## The agent on the pane and taking the voice, or "".
var active := ""
## Agents get a link to the player's API at start (assistant_service.pair_local). Tests turn it off.
var pair_on_start := true
## Stands in for the features' EyeGaze (the tests): calibrating, calibrated(), ray().
var gaze_override: Object
## Stands in for a window on the big screen (the tests).
var window_override := false
## Tests: stands in for ClassDB's X11WindowSource (anything with its methods).
var x: Object
var _running: Array[String] = []
var _window := 0
var _pane: AgentPane
var _ptt: Node
var _jobs := {}
var _poll := 0.0
var _context_left := 0.0
var _waiting := false
var _watch: Array[String] = []
var _starting := {}
var _restarting := {}
var _talk_down := 0
var _talk_was_shown := false
var _stick_hold := -1.0
var _trigger_taken := false
var _last_stick_y := 0.0
var _looking := false
var _look_time := 0.0
## Keys down in the terminal: their release follows them, wherever the viewer looks by then.
var _keys_down := {}


func _ready() -> void:
	_pane = AgentPane.new()
	_pane.name = "AgentPane"
	_pane.app = main
	add_child(_pane)
	_pane.faded.connect(_on_pane_faded)
	_open_x()
	_refresh_running()


func _open_x() -> bool:
	if x != null:
		return true
	if not ClassDB.class_exists(ENGINE_CLASS):
		return false
	var w: Object = ClassDB.instantiate(ENGINE_CLASS)
	if w.call("open") != OK:
		return false
	x = w
	return true


func _exit_tree() -> void:
	# The terminals stay; only our look at them ends.
	if x != null:
		x.call("stop_capture")
		x.call("close")
		x = null


# --- What runs ---------------------------------------------------------------------------------------------------

func running() -> Array[String]:
	return _running


func is_running(id: String) -> bool:
	return id in _running


func _refresh_running() -> void:
	if x == null:
		return
	var now: Array[String] = []
	for id: String in AgentTerminal.AGENTS:
		if AgentTerminal.find_window(x, id) != 0:
			now.append(id)
	if now != _running:
		_running = now
		if active != "" and not (active in _running) and not _starting.has(active) and not _restarting.has(active):
			_on_gone()
		changed.emit()


## The active agent's terminal went away (the agent was quit).
func _on_gone() -> void:
	active = ""
	_window = 0
	_show_pane(false)
	_set_waiting(false)


func pane_shown() -> bool:
	return _pane != null and _pane.is_shown()


func waiting() -> bool:
	return _waiting


## The viewer's look gives the pointer hand to the terminal now.
func looking() -> bool:
	return _looking


## Starts the agent's terminal if it isn't running, then puts it on the pane and gives it the voice. Not installed: a
## card asks first. plain: a new session starts with no briefing; a running one is shown either way.
func open_agent(id: String, plain := false) -> void:
	if not AgentTerminal.AGENTS.has(id):
		return
	if not _open_x():
		_note("No window capture here: %s needs the desktop's display" % AgentTerminal.AGENTS[id]["name"])
		return
	if not is_running(id) and not AgentTerminal.installed(id):
		_ask_install(id)
		return
	_begin(id, false, plain)


## Ends the agent's session and starts a new one, briefed or plain. The folder and its files stay.
func restart_agent(id: String, plain := false) -> void:
	if not AgentTerminal.AGENTS.has(id) or _restarting.has(id) or x == null:
		return
	_restarting[id] = true
	AgentTerminal.stop(id)
	if active == id:
		x.call("stop_capture")
		_window = 0
	var left := STOP_TIMEOUT
	while AgentTerminal.find_window(x, id) != 0 and left > 0.0:
		await get_tree().create_timer(0.1).timeout
		left -= 0.1
	if AgentTerminal.find_window(x, id) == 0:
		await _begin(id, false, plain, true)
	else:
		_note("%s did not stop" % AgentTerminal.AGENTS[id]["name"])
	_restarting.erase(id)


## Asks (a card) to install the agent, then starts it with its installer: the Files entry's Install row.
func install_agent(id: String) -> void:
	if AgentTerminal.AGENTS.has(id) and _open_x():
		_ask_install(id)


func _begin(id: String, install: bool, plain := false, fresh := false) -> void:
	# Never a terminal that can only say "not installed" (a restart, or a start racing a removal): the card asks.
	if not install and not AgentTerminal.installed(id) and AgentTerminal.find_window(x, id) == 0:
		_ask_install(id)
		return
	set_active(id)
	if AgentTerminal.find_window(x, id) == 0 and not _starting.has(id):
		_starting[id] = Time.get_ticks_msec()
		var first := not fresh and not FileAccess.file_exists(AgentTerminal.player_dir(id).path_join("started"))
		# Marks of the last session: a new one tells its own.
		DirAccess.remove_absolute(AgentTerminal.player_dir(id).path_join("waiting"))
		DirAccess.remove_absolute(AgentTerminal.player_dir(id).path_join("hook_seen"))
		if pair_on_start:
			await _pair(id)
		var why := AgentTerminal.start(id, install, plain, fresh)
		if why != "":
			_starting.erase(id)
			_note(why)
			return
		if first:
			# The folder's trust question comes before any hook can run: the stick and the trigger answer it.
			var w := FileAccess.open(AgentTerminal.player_dir(id).path_join("waiting"), FileAccess.WRITE)
			if w != null:
				w.close()
			_tell_permissions(id)
	_show_pane(true)


## Its link to the player's API: the assistant service starts if it is off (the agent needs its guide and API).
func _pair(id: String) -> void:
	var service: Node = Assistant.start(main, true)
	if service == null:
		return
	while not service.is_inside_tree():
		await get_tree().process_frame
	if not await service.pair_local(id):
		_note("%s has no link to the player yet: the headset's certificate isn't ready"
				% AgentTerminal.AGENTS[id]["name"])


## On first start, what the viewer's switches keep from it.
func _tell_permissions(id: String) -> void:
	var service: Node = Assistant.instance()
	var card := _card()
	if service == null or card == null:
		return
	# Every switch that is off (scripts/assistant/assistant_switches.gd), as its row says it.
	var off := AssistantSwitches.off(service.settings)
	if off.is_empty():
		return
	card.show_card({"id": "agent_permissions", "title": AgentTerminal.AGENTS[id]["name"], "seconds": 15.0,
			"text": "It can talk to you and read what plays, but it may not %s yet. Turn on what it needs in System, "
			% (", ".join(off.slice(0, -1)) + " or " + off[-1] if off.size() > 1 else off[0]) + "Assistant."})


## Gives the agent the pane and the voice (the "Voice goes to" choice follows).
func set_active(id: String) -> void:
	if id != active:
		active = id
		_window = 0
		_set_waiting(false)
		if _pane != null and x != null:
			x.call("stop_capture")
		# X's legend follows the terminal (enter_ready()).
		if main.has_method("update_controller_labels"):
			main.update_controller_labels()
	if id != "":
		_ensure_ptt()
		main.settings.set_value("assistant", "voice_to", id)
		main.settings.set_value("assistant", "last_agent", id)
	_write_context()
	changed.emit()


func _ask_install(id: String) -> void:
	var card := _card()
	var a: Dictionary = AgentTerminal.AGENTS[id]
	if card == null:
		return
	card.show_card({"id": INSTALL_CARD, "title": a["name"], "seconds": 60.0,
			"text": "%s isn't installed on this headset. Install it now? It downloads it and runs here as you." % a["name"],
			"actions": [{"id": "install", "label": "Install"}, {"id": "no", "label": "No"}]})
	var slot: Array[Callable] = []
	var answered := func(card_id: String, how: String) -> void:
		if card_id != INSTALL_CARD:
			return
		card.dismissed.disconnect(slot[0])
		if how == "install":
			_begin(id, true)
	slot.append(answered)
	card.dismissed.connect(answered)


## The same terminal on the big screen, for building rooms: its own capture, closed like any source; the terminal stays.
func show_on_screen(id: String) -> void:
	if not _open_x():
		return
	if not is_running(id):
		if not AgentTerminal.installed(id):
			_ask_install(id)
			return
		_begin(id, false)
	set_active(id)
	_show_pane(false)
	main.open_path(WindowVideoSource.terminal_path(id))


## The active agent is on the big screen now.
func on_big_screen() -> bool:
	var src: Object = main.player.source if main.player != null else null
	return active != "" and src is WindowVideoSource and (src as WindowVideoSource).terminal_id == active \
			and (src as WindowVideoSource).has_frame()


func hide_pane() -> void:
	_show_pane(false)


func toggle_pane() -> void:
	_show_pane(not pane_shown())


func _show_pane(on: bool) -> void:
	if _pane == null:
		return
	if on and on_big_screen():
		return
	_pane.set_shown(on)
	if on:
		_capture()
	elif not _pane.visible:
		_on_pane_faded()
	if main.has_method("update_controller_labels"):
		main.update_controller_labels()
	changed.emit()


## The capture ends once the pane has gone from sight: a press that turns it back in its fade finds the picture still there.
func _on_pane_faded() -> void:
	if x != null and not pane_shown():
		x.call("stop_capture")
		_window = 0


## The active agent's window in our capture. True when it is.
func _capture() -> bool:
	if active == "" or x == null:
		return false
	var id := AgentTerminal.find_window(x, active)
	if id == 0:
		return false
	if id != _window:
		if x.call("capture", id) != OK:
			return false
		_window = id
		_pane.set_texture(x.call("get_texture"), x.call("get_size"))
	return true


func _process(delta: float) -> void:
	_poll -= delta
	if _poll <= 0.0:
		_poll = POLL_SECONDS
		_refresh_running()
		_check_files()
		for id: String in _starting.keys():
			if is_running(id) or Time.get_ticks_msec() - int(_starting[id]) > START_TIMEOUT * 1000.0:
				_starting.erase(id)
		if pane_shown() and _window == 0:
			_capture()
	if not _running.is_empty():
		_context_left -= delta
		if _context_left <= 0.0:
			_context_left = CONTEXT_SECONDS
			_write_context()
	if pane_shown() and _window != 0 and x != null:
		x.call("update")
	_update_look(delta)


func _update_look(delta: float) -> void:
	if not pane_shown() or main.menu_shown or _intro_pending():
		_set_looking(false)
		return
	var on := _gaze_on_pane() or (_looking and _stick_hold >= 0.0)
	_look_time = _look_time + delta if on != _looking else 0.0
	if on != _looking and _look_time >= (GAZE_OFF if _looking else GAZE_ON):
		_set_looking(on)


func _gaze() -> Object:
	if gaze_override != null:
		return gaze_override
	return main.features.gaze if main.features != null else null


## The look on the pane: calibrated or not (ray() is the raw reading without a calibration), with the margin for it.
func _gaze_on_pane() -> bool:
	var g := _gaze()
	if g == null or g.calibrating:
		return false
	var r: Array = g.ray()
	return not r.is_empty() and _pane.looked_at(r[0], r[1], gaze_margin())


## The margin round the pane the gaze gets now, degrees.
func gaze_margin() -> float:
	var g := _gaze()
	return GAZE_MARGIN_DEG if g != null and g.calibrated() else GAZE_MARGIN_RAW_DEG


## The first start's introduction (ui/intro.gd) is waiting to be gone through: the terminal takes no controller keys.
func _intro_pending() -> bool:
	var layer: Variant = main.get("ui")
	return layer != null and layer.has_method("intro_pending") and layer.intro_pending()


func _set_looking(on: bool) -> void:
	_look_time = 0.0
	if on == _looking:
		return
	_looking = on
	if not on:
		_stick_hold = -1.0
	_pane.set_looked_at(on)
	if main.has_method("update_controller_labels"):
		main.update_controller_labels()


## The waiting flag (the agent's hook) and any link the agent wants opened.
func _check_files() -> void:
	if active != "":
		_set_waiting(FileAccess.file_exists(_state("waiting")))
	for id: String in _running:
		var f := AgentTerminal.player_dir(id).path_join("open_url")
		if FileAccess.file_exists(f):
			var text := FileAccess.get_file_as_string(f)
			DirAccess.remove_absolute(f)
			var url := text.strip_edges().get_slice("\n", text.strip_edges().get_slice_count("\n") - 1)
			_offer_link(url, str(AgentTerminal.AGENTS[id]["name"]))


## A sign-in link: a card asks, then the Browser source opens it (assistant_browse.gd); the terminal stays on.
func _offer_link(url: String, who: String) -> void:
	var b: Node = AssistantBrowse.ensure(get_tree())
	if not b.is_inside_tree():
		await get_tree().process_frame
	await b.suggest(url, who)


func _state(file: String) -> String:
	return AgentTerminal.player_dir(active).path_join(file)


func _set_waiting(on: bool) -> void:
	if on == _waiting:
		return
	_waiting = on
	if _pane != null:
		_pane.set_waiting(on)
	if on:
		var hand: Variant = _pointer_hand()
		if hand != null:
			hand.pulse()
		if not pane_shown() and not on_big_screen():
			_note("%s is asking: press talk to see it" % AgentTerminal.AGENTS[active]["name"])
	if main.has_method("update_controller_labels"):
		main.update_controller_labels()
	changed.emit()


func _answered() -> void:
	if active != "":
		DirAccess.remove_absolute(_state("waiting"))
	_set_waiting(false)


func _pointer_hand() -> Variant:
	return main.ui.pointer_hand if main.get("ui") != null else null


func _card() -> Node:
	var card: Node = main.ui.get("card") if main.get("ui") != null else null
	return card if card != null and card.has_method("show_card") else null


func _note(text: String) -> void:
	if main.get("ui") != null and main.ui.has_method("notify"):
		main.ui.notify(text)
	else:
		print("Agents: " + text)


# --- The context ----------------------------------------------------------------------------------------------------

## One short line: what is playing and where, for the inline form. "" when nothing is open.
func context_line() -> String:
	if str(main.current_path) == "":
		return ""
	var p: Node = main.player
	return "%s at %s of %s, %s" % [main.display_title(), _clock(p.get_position()), _clock(p.get_duration()),
			"playing" if p.is_playing() else "paused"]


## What the prompt hook prints into every message: the line and the last subtitle lines.
func context_block() -> String:
	var line := context_line()
	if line == "":
		return "[On the headset: nothing is playing.]\n"
	var out := "[On the headset: %s." % line
	var subs: Object = main.features.get("subtitles") if main.get("features") != null else null
	if subs != null and subs.has_method("lines_before"):
		var said: Array = subs.lines_before(main.player.get_position(), SUBTITLE_LINES)
		if not said.is_empty():
			out += " Last subtitle lines:"
			for s: Dictionary in said:
				out += "\n  " + str(s.get("text", "")).replace("\n", " / ")
	return out + "]\n"


## Written whole and renamed into place, so the hook's cat never sees half of it.
func _write_context() -> void:
	if main == null or main.get("player") == null:
		return
	var text := context_block()
	var ids := _running.duplicate()
	if active != "" and not active in ids:
		ids.append(active)
	for id: String in ids:
		var dir := AgentTerminal.player_dir(id)
		if not DirAccess.dir_exists_absolute(dir):
			continue
		var tmp := dir.path_join("context.tmp")
		var f := FileAccess.open(tmp, FileAccess.WRITE)
		if f != null:
			f.store_string(text)
			f.close()
			DirAccess.rename_absolute(tmp, dir.path_join("context.txt"))


static func _clock(t: float) -> String:
	var s := int(maxf(t, 0.0))
	return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60] if s >= 3600 else "%d:%02d" % [s / 60, s % 60]


# --- Voice -----------------------------------------------------------------------------------------------------------

## The push-to-talk that types into the active agent, or null with none active.
func push_to_talk() -> Node:
	return _ptt if active != "" and (is_running(active) or _starting.has(active)) else null


func _ensure_ptt() -> void:
	if _ptt != null:
		return
	_ptt = PushToTalk.new()
	_ptt.name = "AgentPushToTalk"
	_ptt.register_command = false
	_ptt.key_enabled = false
	_ptt.link = self
	add_child(_ptt)
	_ptt.recording_changed.connect(func(on: bool) -> void: _pane.set_recording(on))
	Transcriber.instance().connect("done", _on_transcribed)
	if DisplayServer.get_name() != "headless":
		WhisperBackend.ensure(get_tree())


## PushToTalk's link: the finished clip goes to the speech to text on the headset; nothing leaves it.
func send_event(event_name: String, data: Variant = {}) -> void:
	if event_name != "voice_clip" or not (data is Dictionary):
		return
	var wav := Marshalls.base64_to_raw(str(data.get("wav_b64", "")))
	if wav.size() <= 44:
		return
	var id := Transcriber.transcribe(wav.slice(44), true) if Transcriber.available() else -1
	if id < 0:
		_note("Speech to text isn't working on the headset, so nothing was typed")
		return
	_jobs[id] = active


func _on_transcribed(id: int, text: String, final: bool) -> void:
	if not _jobs.has(id) or not final:
		return
	var agent: String = _jobs[id]
	_jobs.erase(id)
	if agent == active:
		deliver(text)


## The keys a spoken word alone stands for (a character, or "escape"), or "".
func spoken_key(text: String) -> String:
	var word := _spoken_word(text)
	if WORDS.has(word):
		return WORDS[word]
	if _waiting and active != "":
		var keys: Dictionary = AgentTerminal.AGENTS[active]["keys"]
		if keys.has(word):
			return keys[word]
	return ""


func _spoken_word(text: String) -> String:
	return text.strip_edges().to_lower().rstrip(".!?,:;").lstrip("\"'")


## What was said goes in: a key if that is what a lone word means, else the words and Enter, unless a prompt waits.
func deliver(text: String) -> void:
	var t := text.strip_edges()
	if t == "" or active == "":
		return
	var target: Object = _target()
	if target == null:
		return
	# The hook may have written this since the last look.
	_set_waiting(FileAccess.file_exists(_state("waiting")))
	var key := spoken_key(t)
	if key != "":
		_tap(target, key)
		_answered()
		return
	var a: Dictionary = AgentTerminal.AGENTS[active]
	if _waiting:
		_note("%s is asking: say yes, no or a number, or use the stick and trigger" % a["name"])
		return
	var hook_ran := FileAccess.file_exists(_state("hook_seen"))
	if not hook_ran or _spoken_word(t) == "no":
		_tap(target, "escape")
		await get_tree().create_timer(ENTER_DELAY).timeout
	_write_context()
	if bool(a["inline_context"]) and not hook_ran and context_line() != "":
		t = "[%s] %s" % [context_line(), t]
	_type(target, t)
	await get_tree().create_timer(ENTER_DELAY).timeout
	_tap(target, "enter")


## Who takes keys: the big screen's source when the agent is there, else our capture.
func _target() -> Object:
	if on_big_screen():
		return main.player.source
	if _window == 0:
		_capture()
	return self if _window != 0 else null


## The same calls as WindowVideoSource, on our capture.
func send_char(unicode: int) -> void:
	x.call("send_unicode", unicode, true)
	x.call("send_unicode", unicode, false)


func send_godot_key(key: Key, pressed: bool) -> void:
	x.call("send_godot_key", key, pressed)


func _type(target: Object, text: String) -> void:
	for i in text.length():
		target.send_char(text.unicode_at(i))


func _tap(target: Object, key: String) -> void:
	match key:
		"enter":
			_key(target, KEY_ENTER)
		"escape":
			_key(target, KEY_ESCAPE)
		"up":
			_key(target, KEY_UP)
		"down":
			_key(target, KEY_DOWN)
		_:
			target.send_char(key.unicode_at(0))


func _key(target: Object, key: Key, shift := false) -> void:
	if shift:
		target.send_godot_key(KEY_SHIFT, true)
	target.send_godot_key(key, true)
	target.send_godot_key(key, false)
	if shift:
		target.send_godot_key(KEY_SHIFT, false)


# --- Controllers -------------------------------------------------------------------------------------------------

## The talk button: shows the pane; a quick tap while it was showing hides it.
func on_talk(held: bool) -> void:
	if held:
		_talk_down = Time.get_ticks_msec()
		_talk_was_shown = pane_shown()
		if not on_big_screen():
			_show_pane(true)
	elif _talk_was_shown and Time.get_ticks_msec() - _talk_down < TAP_MSEC:
		_show_pane(false)


## Y on the right controller. The pointer hand only: the pane sits there, and the left has no Y for it to be the left's. Not
## while a calibration has the controller. With the menu open it still works (the user, 2026-11-05): the pane shows or
## hides, and the menu keeps the stick and trigger until it closes (has_input()). An agent running: its pane on or off,
## and it keeps working either way. None: starts one, or a card asks to install it.
func on_agent_button(hand: Node) -> void:
	var gaze := _gaze()
	if hand != _pointer_hand() or (gaze != null and gaze.calibrating):
		return
	if _intro_pending():
		main.ui.show_panel(hand)
		return
	if active != "" and (is_running(active) or _starting.has(active)):
		toggle_pane()
	else:
		open_agent(_agent_to_open())


## The one running, the last used if it is one of them; else the last used, or the first installed; else the first there is,
## for its install card.
func _agent_to_open() -> String:
	var last := str(main.settings.get_value("assistant", "last_agent", ""))
	if not _running.is_empty():
		return last if last in _running else _running[0]
	if AgentTerminal.AGENTS.has(last) and AgentTerminal.installed(last):
		return last
	for id: String in AgentTerminal.AGENTS:
		if AgentTerminal.installed(id):
			return id
	return last if AgentTerminal.AGENTS.has(last) else AgentTerminal.AGENTS.keys()[0]


## A keyboard: the terminal takes it as a window on the big screen does (window_pointer.on_key()). True when taken.
func on_key(event: InputEventKey) -> bool:
	if event.keycode in main.window_pointer.RESERVED_KEYS:
		return false
	if not _keys_down.has(event.keycode) and (not event.pressed or event.echo or not _takes_keyboard()):
		return false
	var t := _target()
	if t == null:
		_keys_down.erase(event.keycode)
		return false
	if event.pressed:
		_keys_down[event.keycode] = true
	else:
		_keys_down.erase(event.keycode)
	return keyboard_key(event, t)


## The floating keyboard can keep typing while the menu is open and the viewer looks down at the keys. The
## terminal must still be showing; it never starts or focuses a hidden conversation just because a key was tapped.
func keyboard_target() -> Object:
	if not (pane_shown() or on_big_screen()) or _intro_pending():
		return null
	var t := _target()
	# Keep the capture itself: another agent can replace our x while a key is held.
	return x if t == self else t


## One key path for paired and floating keyboards. Virtual physical keys must be held in X11 for native repeat;
## paired keyboards retain their layout's Unicode path. The engine's X11 API has no left/right location argument.
func keyboard_key(event: InputEventKey, t: Object, physical := false) -> bool:
	if not is_instance_valid(t):
		return false
	if not physical and event.unicode >= 32 and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
		if event.pressed:
			t.send_char(event.unicode)
		return true
	t.send_godot_key(event.keycode, event.pressed)
	if event.pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
		_answered()
	return true


func _takes_keyboard() -> bool:
	if not pane_shown() or main.menu_shown or _intro_pending():
		return false
	return _looking or not (window_override or main.window_pointer.is_active())


## The stick and the trigger belong to the agent now: its pane shows, on the pointer hand, and a prompt waits, the
## squeeze is held or the viewer looks at it.
func has_input(hand: Node) -> bool:
	if not pane_shown() or hand != _pointer_hand() or main.menu_shown or _intro_pending():
		return false
	return _waiting or _looking or bool(hand.get("grip_down"))


## X is Enter now: an agent's terminal shows, on the pane or the big screen (whichever hand points, the menu open or
## not), outside a calibration and the first start's introduction.
func enter_ready() -> bool:
	var gaze := _gaze()
	if active == "" or (gaze != null and gaze.calibrating) or _intro_pending():
		return false
	return pane_shown() or on_big_screen()


## X on the right controller (the action map's "enter"): Enter into the terminal while enter_ready(). True when taken.
func on_enter_button(hand: Node) -> bool:
	if not enter_ready():
		return false
	var t := _target()
	if t == null:
		return false
	_key(t, KEY_ENTER)
	if hand != null and hand.has_method("pulse"):
		hand.pulse()
	_answered()
	return true


func on_trigger(hand: Node, pressed: bool) -> bool:
	if not pressed:
		var taken := _trigger_taken
		_trigger_taken = false
		return taken
	if not has_input(hand):
		return false
	_trigger_taken = true
	var t := _target()
	if t != null:
		_key(t, KEY_ENTER)
		hand.pulse()
		_answered()
	return true


func on_stick(hand: Node, stick: Vector2, delta: float) -> bool:
	if not has_input(hand):
		return false
	if maxf(absf(stick.x), absf(stick.y)) < STICK_THRESHOLD:
		_stick_hold = -1.0
		return true
	if _stick_hold < 0.0 or _stick_hold >= STICK_REPEAT:
		_stick_hold = 0.0
		var t := _target()
		var along := absf(stick.y) >= absf(stick.x)
		if t != null:
			if bool(hand.get("grip_down")):
				if along:
					_key(t, KEY_PAGEUP if stick.y > 0.0 else KEY_PAGEDOWN, true)
			elif along:
				_key(t, KEY_UP if stick.y > 0.0 else KEY_DOWN)
			else:
				_key(t, KEY_RIGHT if stick.x > 0.0 else KEY_LEFT)
	_stick_hold += delta
	return true


## next_file (A) and prev_file (B) while a prompt waits: Space and Escape.
func on_button(hand: Node, action: String) -> bool:
	if not has_input(hand):
		return false
	var t := _target()
	if t != null:
		if action == "next_file":
			_key(t, KEY_SPACE)
		else:
			_key(t, KEY_ESCAPE)
			_answered()
	return true


# --- Commands ----------------------------------------------------------------------------------------------------

## What the agents' entries in Files show, for `agents`: no window titles, no words from the terminals.
func status() -> Array:
	var out: Array = []
	for id: String in AgentTerminal.AGENTS:
		out.append({"id": id, "name": AgentTerminal.AGENTS[id]["name"], "installed": AgentTerminal.installed(id),
				"running": is_running(id), "active": active == id, "pane_shown": active == id and pane_shown(),
				"on_big_screen": active == id and on_big_screen(), "waiting": active == id and waiting()})
	return out


## The agent a paired client is (its row's client name), or "".
static func agent_of(client_name: String) -> String:
	for id: String in AgentTerminal.AGENTS:
		if client_name != "" and AgentTerminal.AGENTS[id]["client"] == client_name:
			return id
	return ""


## The agents' rows in Files as commands (docs/dev/assistant-coverage/files.md), each running what its row runs. An
## agent may hide or show its own pane (it keeps working either way), but a restart of the calling agent ends the very
## session that asked: refused unless it passes self: true.
static func register_commands(cmd_host: Node) -> void:
	var id_param := {"name": "id", "type": "string", "required": true, "enum": AgentTerminal.AGENTS.keys(),
			"description": "the agent, as agents lists it"}
	var agents_of := func() -> Node: return cmd_host.main.local_agents
	var refresh := func(id: String) -> void:
		var layer: Node = cmd_host.main.get("ui")
		var pane: Object = layer.get("ui") if layer != null else null
		var files: Node = pane.get("files") if pane != null else null
		if files != null:
			files.refresh_place("agent://" + id)
	DevCommands.register("agents", func(_args: Dictionary, ctx: DevCommands.Call) -> Variant:
		return {"agents": agents_of.call().status(), "you": agent_of(ctx.client)}, {
		"description": "The agents that can run on the headset: installed, running, which one is active (on the pane "
				+ "and taking the voice), whether its pane shows, whether it is on the big screen, whether a prompt of "
				+ "its waits; you is the calling agent's id, or empty.",
		"returns": "{agents: [{id, name, installed, running, active, pane_shown, on_big_screen, waiting}], you}",
		"assistant": "read"})
	DevCommands.register("agent_start", func(args: Dictionary, ctx: DevCommands.Call) -> Variant:
		var la: Node = agents_of.call()
		var id: String = args["id"]
		if la.is_running(id):
			return ctx.fail("%s runs already (agent_show puts it on the pane, agent_restart starts it afresh)"
					% AgentTerminal.AGENTS[id]["name"])
		var installed := AgentTerminal.installed(id)
		la.open_agent(id, args["plain"])
		refresh.call(id)
		ctx.summary = ("start %s" if installed else "asked to install %s") % AgentTerminal.AGENTS[id]["name"]
		return {"starting": id, "plain": args["plain"], "asked_to_install": not installed}, {
		"description": "Starts an agent in its terminal on the headset and puts it on the pane on the controller, as "
				+ "its Start rows in Files do. Not installed: a card asks the viewer whether to install it.",
		"params": [id_param, {"name": "plain", "type": "bool", "default": false,
				"description": "true: no briefing, it starts and waits; false: briefed on the player first"}],
		"level": "control", "returns": "{starting, plain, asked_to_install}", "assistant": "apps"})
	DevCommands.register("agent_restart", func(args: Dictionary, ctx: DevCommands.Call) -> Variant:
		var la: Node = agents_of.call()
		var id: String = args["id"]
		if not la.is_running(id):
			return ctx.fail("%s isn't running (agent_start starts it)" % AgentTerminal.AGENTS[id]["name"])
		if id == agent_of(ctx.client) and not args["self"]:
			return ctx.fail("that is you: a restart ends this session and this conversation. Pass self: true only "
					+ "if the viewer asked for it")
		la.restart_agent(id, args["plain"])
		ctx.summary = "restart %s" % AgentTerminal.AGENTS[id]["name"]
		return {"restarting": id, "plain": args["plain"]}, {
		"description": "Ends a running agent's session and starts a new one in the same folder, as its Restart rows "
				+ "in Files do. The folder and its files stay.",
		"params": [id_param, {"name": "plain", "type": "bool", "default": false,
				"description": "true: the new session gets no briefing; false: briefed on the player"},
				{"name": "self", "type": "bool", "default": false,
				"description": "needed to restart the calling agent itself, which ends this very session; only when "
				+ "the viewer asked for it"}],
		"level": "control", "returns": "{restarting, plain}", "assistant": "apps"})
	DevCommands.register("agent_show", func(args: Dictionary, ctx: DevCommands.Call) -> Variant:
		var la: Node = agents_of.call()
		var id: String = args["id"]
		if not la.is_running(id):
			return ctx.fail("%s isn't running (agent_start starts it)" % AgentTerminal.AGENTS[id]["name"])
		var old: String = la.active
		var was_shown: bool = la.pane_shown()
		la.open_agent(id)
		refresh.call(id)
		ctx.summary = "%s on the controller" % AgentTerminal.AGENTS[id]["name"]
		ctx.undo = func() -> void:
			if old != "" and old != id and la.is_running(old):
				la.open_agent(old)
			if not was_shown:
				la.hide_pane()
		return {"active": la.active, "pane_shown": la.pane_shown()}, {
		"description": "Puts a running agent on the pane on the controller and gives it the voice, as Show on the "
				+ "controller does. Nothing starts.",
		"params": [id_param], "level": "control", "returns": "{active, pane_shown}", "assistant": "apps"})
	DevCommands.register("agent_hide", func(_args: Dictionary, ctx: DevCommands.Call) -> Variant:
		var la: Node = agents_of.call()
		if not la.pane_shown():
			return ctx.fail("no agent's pane shows")
		var id: String = la.active
		la.hide_pane()
		refresh.call(id)
		ctx.summary = "agent pane hidden"
		ctx.undo = func() -> void:
			if la.active == id and la.is_running(id):
				la.open_agent(id)
		return {"active": la.active, "pane_shown": la.pane_shown()}, {
		"description": "Hides the agent's pane from the controller, as Hide from the controller does; the agent keeps "
				+ "working and keeps the voice.",
		"level": "control", "returns": "{active, pane_shown}", "assistant": "apps"})
	DevCommands.register("agent_big_screen", func(args: Dictionary, ctx: DevCommands.Call) -> Variant:
		var la: Node = agents_of.call()
		var id: String = args["id"]
		var asked: bool = not la.is_running(id) and not AgentTerminal.installed(id)
		la.show_on_screen(id)
		refresh.call(id)
		ctx.summary = ("%s on the big screen" if not asked else "asked to install %s") % AgentTerminal.AGENTS[id]["name"]
		return {"showing": id if not asked else "", "asked_to_install": asked}, {
		"description": "Puts an agent's terminal on the big screen instead of the film, as Put it on the big screen "
				+ "does, starting it first if needed (not installed: a card asks the viewer). The pane hides; opening a "
				+ "file brings the film back.",
		"params": [id_param], "level": "control", "returns": "{showing, asked_to_install}", "assistant": "apps"})
